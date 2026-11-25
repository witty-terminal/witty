module renderer

// The OpenGL specialization of the generic renderer. Ghostty instantiates
// GenericRenderer with OpenGL on Linux at compile time; these are the parts of
// the translated renderer that only that instantiation compiles.
import font
import font.shaper as fontshaper
import highlight
import log
import macos
import sync
import terminal

$if renderer_opengl ?|| ( !renderer_metal ?&& !macos && !ios ) {
	fn Renderer.init_opengl(opts RendererOpts) !Renderer {
		mut font_shaper := fontshaper.NativeShaper.init_backend(opts.font_grid.backend(), font.ShaperOptions{
			features: opts.config.font_features
		})!
		mut api := OpenGLAPI.init(RendererOptions{
			config:    opts.config
			font_grid: opts.font_grid
			size:      opts.size
		}) or {
			font_shaper.deinit()
			return err
		}
		post_shaders := load_from_files(opts.config.custom_shaders, .glsl) or {
			log.warn('error loading custom shaders err=${err}')
			[]string{}
		}
		mut shaders := api.init_shaders(post_shaders) or {
			api.deinit()
			font_shaper.deinit()
			return err
		}
		has_custom_shaders := shaders.post_pipelines.len > 0
		mut frames := []GLFrameState{cap: opengl_swap_chain_count}
		for _ in 0 .. opengl_swap_chain_count {
			frame := GLFrameState.init(&api, has_custom_shaders) or {
				for mut initialized in frames {
					initialized.deinit()
				}
				shaders.deinit()
				api.deinit()
				font_shaper.deinit()
				return err
			}
			frames << frame
		}

		mut display_link := unsafe { &DisplayLink(nil) }
		$if macos {
			if opts.config.vsync {
				display_link = macos.CVDisplayLink.create_with_active_cg_displays() or {
					for mut frame in frames { frame.deinit() }
					shaders.deinit()
					api.deinit()
					font_shaper.deinit()
					return err
				}
			}
		}

		metrics := opts.font_grid.metrics
		bg_alpha := background_opacity_alpha(opts.config.background_opacity)
		mut result := Renderer{
			display_link:           display_link
			draw_mutex:             sync.new_mutex()
			surface_mailbox:        opts.surface_mailbox
			api:                    api
			images:                 ImageRenderState.empty()
			shaders:                shaders
			frames:                 frames
			frame_sema:             sync.new_semaphore_init(u32(opengl_swap_chain_count))
			config:                 opts.config
			grid_metrics:           metrics
			size:                   opts.size
			focused:                true
			scrollbar:              terminal.Scrollbar{}
			search_matches:         []highlight.Flattened{}
			cells:                  CellContents{}
			uniforms:               Uniforms{
				min_contrast: opts.config.min_contrast
				cursor_pos:   [u16(0xFFFF), u16(0xFFFF)]!
				bg_color:     [
					opts.config.background.r,
					opts.config.background.g,
					opts.config.background.b,
					bg_alpha,
				]!
				bools:        UniformBools{
					use_display_p3:        opts.config.colorspace == .display_p3
					use_linear_blending:   opts.config.blending.is_linear()
					use_linear_correction: opts.config.blending == .linear_corrected
				}
			}
			custom_shader_uniforms: CustomShaderUniforms{
				focus: 1
			}
			font_grid:              opts.font_grid
			font_shaper:            font_shaper
			font_shaper_cache:      font.ShaperCache.init()
			has_custom_shaders:     has_custom_shaders
		}
		result.update_font_grid_uniforms()
		result.update_screen_size_uniforms()
		result.update_bg_image_buffer()
		result.prep_background_image() or {
			result.deinit()
			return err
		}
		return result
	}

	fn (mut self Renderer) deinit_opengl_swap_chain() {
		if self.swap_chain_defunct {
			return
		}
		self.drain_frame_semaphore(opengl_swap_chain_count)
		for mut frame in self.frames {
			frame.deinit()
		}
		self.frames = []GLFrameState{}
	}

	fn (mut self Renderer) draw_frame_opengl(sync_ bool) ! {
		// OpenGL completes synchronously regardless of the requested mode.
		_ = sync_
		self.api.draw_frame_start()
		defer {
			self.api.draw_frame_end()
		}

		surface_width, surface_height := self.api.surface_size()
		if surface_width == 0 || surface_height == 0 {
			return
		}
		size_changed := self.size.screen.width != surface_width
			|| self.size.screen.height != surface_height
		needs_redraw := size_changed || self.cells_rebuilt || self.has_animations() || sync_
		if !needs_redraw {
			self.api.present_last_target()!
			return
		}
		self.cells_rebuilt = false
		if self.frames.len == 0 {
			return error('OpenGL swap chain is unavailable')
		}

		self.acquire_frame()!
		mut frame_submitted := false
		defer {
			if !frame_submitted {
				self.release_frame()
			}
		}
		// Match SwapChain.nextFrame: select the slot before any later operation
		// can fail, preserving the source round-robin sequence after errors.
		self.frame_index = (self.frame_index + 1) % self.frames.len
		mut frame_state := &self.frames[self.frame_index]

		if self.reinitialize_shaders {
			self.reinitialize_shaders = false
			self.api.release_gg()
			self.shaders.deinit()
			post_shaders := load_from_files(self.config.custom_shaders, .glsl) or {
				log.warn('error loading custom shaders err=${err}')
				[]string{}
			}
			self.shaders = self.api.init_shaders(post_shaders)!
			self.has_custom_shaders = self.shaders.post_pipelines.len > 0
		}

		if self.has_custom_shaders {
			if _ := frame_state.custom_shader_state {
			} else {
				mut state := GLCustomShaderState.init(&self.api)!
				state.resize(&self.api, surface_width, surface_height)!
				frame_state.custom_shader_state = state
			}
		} else if mut state := frame_state.custom_shader_state {
			state.deinit()
			frame_state.custom_shader_state = none
		}

		if size_changed {
			self.size.screen = ScreenSize{
				width:  surface_width
				height: surface_height
			}
			self.update_screen_size_uniforms()
		}

		if frame_state.target.width != surface_width || frame_state.target.height != surface_height
			|| frame_state.target_config_modified != self.target_config_modified {
			frame_state.resize_target(&self.api, surface_width, surface_height)!
			frame_state.target_config_modified = self.target_config_modified
		}

		_ = self.images.upload(&self.api)
		self.upload_background_image()!
		self.update_custom_shader_uniforms_for_frame()!

		gpu_uniforms := gl_uniforms(self.uniforms)
		frame_state.uniforms.sync_values([gpu_uniforms])!
		frame_state.cells_bg.sync_values(self.cells.bg_cells)!
		fg_count := frame_state.cells.sync_from_array_lists(self.cells.fg_rows.lists)!
		if mut state := frame_state.custom_shader_state {
			state.uniforms.sync_values([self.custom_shader_uniforms])!
			frame_state.custom_shader_state = state
		}
		if frame_state.bg_image_buffer_modified != self.bg_image_buffer_modified {
			frame_state.bg_image_buffer.sync_values([self.bg_image_buffer])!
			frame_state.bg_image_buffer_modified = self.bg_image_buffer_modified
		}

		grayscale_modified := self.font_grid.atlas_grayscale.modified.load()
		if grayscale_modified > frame_state.grayscale_modified {
			self.sync_gl_atlas_texture(&self.font_grid.atlas_grayscale, mut frame_state.grayscale)!
			frame_state.grayscale_modified = self.font_grid.atlas_grayscale.modified.load()
		}
		color_modified := self.font_grid.atlas_color.modified.load()
		if color_modified > frame_state.color_modified {
			self.sync_gl_atlas_texture(&self.font_grid.atlas_color, mut frame_state.color)!
			frame_state.color_modified = self.font_grid.atlas_color.modified.load()
		}

		mut frame := self.api.begin_frame(mut frame_state.target)!
		mut terminal_attachment := GLRenderAttachment{
			target:      GLRenderAttachmentTarget(frame_state.target)
			clear_color: [f32(0), 0, 0, 0]!
		}
		if state := frame_state.custom_shader_state {
			terminal_attachment = GLRenderAttachment{
				target:      GLRenderAttachmentTarget(state.back_texture)
				clear_color: [f32(0), 0, 0, 0]!
			}
		}
		mut pass := frame.render_pass(terminal_attachment)!

		if image := self.bg_image {
			if image is ImageReady && image.texture.id != 0 {
				pass.step(GLRenderStep{
					pipeline: self.shaders.bg_image
					uniforms: frame_state.uniforms
					buffers:  [frame_state.bg_image_buffer]
					textures: [image.texture]
					draw:     GLDraw{
						primitive:    .triangle
						vertex_count: 3
					}
				})
			}
		} else {
			pass.step(GLRenderStep{
				pipeline: self.shaders.bg_color
				uniforms: frame_state.uniforms
				buffers:  [GLBuffer{}, frame_state.cells_bg]
				draw:     GLDraw{
					primitive:    .triangle
					vertex_count: 3
				}
			})
		}

		self.images.draw(&self.api, self.shaders.image, mut pass, .kitty_below_bg)
		pass.step(GLRenderStep{
			pipeline: self.shaders.cell_bg
			uniforms: frame_state.uniforms
			buffers:  [GLBuffer{}, frame_state.cells_bg]
			draw:     GLDraw{
				primitive:    .triangle
				vertex_count: 3
			}
		})
		self.images.draw(&self.api, self.shaders.image, mut pass, .kitty_below_text)
		pass.step(GLRenderStep{
			pipeline: self.shaders.cell_text
			uniforms: frame_state.uniforms
			buffers:  [frame_state.cells, frame_state.cells_bg]
			textures: [frame_state.grayscale, frame_state.color]
			draw:     GLDraw{
				primitive:      .triangle_strip
				vertex_count:   4
				instance_count: fg_count
			}
		})
		self.images.draw(&self.api, self.shaders.image, mut pass, .kitty_above_text)
		self.images.draw(&self.api, self.shaders.image, mut pass, .overlay)
		pass.complete()

		if mut state := frame_state.custom_shader_state {
			for index, pipeline in self.shaders.post_pipelines {
				mut attachment := GLRenderAttachment{
					target:      GLRenderAttachmentTarget(frame_state.target)
					clear_color: [f32(0), 0, 0, 0]!
				}
				if index < self.shaders.post_pipelines.len - 1 {
					attachment = GLRenderAttachment{
						target:      GLRenderAttachmentTarget(state.front_texture)
						clear_color: [f32(0), 0, 0, 0]!
					}
				}
				mut post_pass := frame.render_pass(attachment)!
				post_pass.step(GLRenderStep{
					pipeline: pipeline
					uniforms: state.uniforms
					textures: [state.back_texture]
					samplers: [state.sampler]
					draw:     GLDraw{
						primitive:    .triangle
						vertex_count: 3
					}
				})
				post_pass.complete()
				state.swap()
			}
			frame_state.custom_shader_state = state
		}

		frame.complete(sync_)
		self.frame_completed(if frame.healthy { .healthy } else { .unhealthy })
		frame_submitted = true
	}

	fn (self &Renderer) sync_gl_atlas_texture(atlas &font.Atlas, mut texture GLTexture) ! {
		if atlas.format == .bgr {
			return error('BGR font atlases are unsupported by OpenGL')
		}
		if atlas.size > texture.width {
			mut replacement := GLTexture.init(self.api.atlas_texture_options(atlas.format)!,
				atlas.size, atlas.size, none)!
			texture.deinit()
			texture = replacement
		}
		texture.replace_region(0, 0, atlas.size, atlas.size, atlas.data)!
	}
}
