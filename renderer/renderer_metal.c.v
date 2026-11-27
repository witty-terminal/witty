module renderer

// The Metal specialization of the generic renderer. Ghostty instantiates
// GenericRenderer with Metal on Apple platforms at compile time; these are the
// parts of the translated renderer that only that instantiation compiles.
import font
import font.shaper as fontshaper
import highlight
import log
import macos
import sync
import terminal
import xev

$if renderer_metal ?|| ( ( macos || ios ) && !renderer_opengl ?) {
	$if gcboehm ? {
		#include "@VMODROOT/renderer/metal_gc_thread.h"

		fn C.witty_metal_register_gc_thread() bool

		fn C.witty_metal_unregister_gc_thread()
	}

	fn Renderer.init_metal(opts RendererOpts) !Renderer {
		// Create the font shaper
		mut font_shaper := fontshaper.NativeShaper.init_backend(opts.font_grid.backend(), font.ShaperOptions{
			features: opts.config.font_features
		})!

		mut metal := if opts.metal_view != unsafe { nil } {
			MetalAPI.init_from_view(opts.metal_view, opts.content_scale) or {
				font_shaper.deinit()
				return err
			}
		} else {
			MetalAPI.init() or {
				font_shaper.deinit()
				return err
			}
		}
		metal.blending = opts.config.blending

		post_shaders := load_from_files(opts.config.custom_shaders, .msl) or {
			log.warn('error loading custom shaders err=${err}')
			[]string{}
		}
		mut shaders := metal.init_shaders(post_shaders) or {
			metal.deinit()
			font_shaper.deinit()
			return err
		}
		has_custom_shaders := shaders.post_pipelines.len > 0
		mut frames := []MetalFrameState{cap: metal_swap_chain_count}
		for _ in 0 .. metal_swap_chain_count {
			frame := MetalFrameState.init(&metal) or {
				for mut initialized in frames {
					initialized.deinit()
				}
				shaders.deinit()
				metal.deinit()
				font_shaper.deinit()
				return err
			}
			frames << frame
		}

		// Get font metrics from the grid
		grid := opts.font_grid
		metrics := grid.metrics

		mut display_link := unsafe { &DisplayLink(nil) }
		$if macos {
			if opts.config.vsync {
				display_link = macos.CVDisplayLink.create_with_active_cg_displays() or {
					for mut frame in frames {
						frame.deinit()
					}
					shaders.deinit()
					metal.deinit()
					font_shaper.deinit()
					return err
				}
			}
		}

		bg_alpha := background_opacity_alpha(opts.config.background_opacity)
		mut result := Renderer{
			draw_mutex:             sync.new_mutex()
			surface_mailbox:        opts.surface_mailbox
			api:                    metal
			images:                 ImageRenderState.empty()
			shaders:                shaders
			frames:                 frames
			frame_sema:             sync.new_semaphore_init(u32(metal_swap_chain_count))
			config:                 opts.config
			grid_metrics:           metrics
			size:                   opts.size
			focused:                true
			display_link:           display_link
			scrollbar:              terminal.Scrollbar{}
			scrollbar_dirty:        false
			search_matches_dirty:   false
			search_matches:         []highlight.Flattened{}
			search_selected_match:  none
			// Render state
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
					cursor_wide:           false
					use_display_p3:        opts.config.colorspace == .display_p3
					use_linear_blending:   opts.config.blending.is_linear()
					use_linear_correction: opts.config.blending == .linear_corrected
				}
			}
			custom_shader_uniforms: CustomShaderUniforms{
				focus: 1
			}
			// Fonts
			font_grid:              opts.font_grid
			font_shaper:            font_shaper
			font_shaper_cache:      font.ShaperCache.init()
			has_custom_shaders:     has_custom_shaders
		}

		// Ensure our undefined values above are correctly initialized
		result.update_font_grid_uniforms()
		result.update_screen_size_uniforms()
		result.update_bg_image_buffer()
		result.prep_background_image() or {
			result.deinit()
			return err
		}

		return result
	}

	fn (mut self Renderer) deinit_metal_swap_chain() {
		if self.swap_chain_defunct {
			return
		}
		self.drain_frame_semaphore(metal_swap_chain_count)
		for mut frame in self.frames {
			frame.deinit()
		}
		self.frames = []MetalFrameState{}
	}

	fn (mut self Renderer) draw_frame_metal(sync_ bool) ! {
		self.api.draw_frame_start()
		defer {
			self.api.draw_frame_end()
		}

		mut surface_width, mut surface_height := self.api.surface_size()
		// A MetalAPI created without a view is useful for off-screen rendering and
		// tests. In that case the configured screen size is the render-target size.
		if self.api.layer == none {
			surface_width = self.size.screen.width
			surface_height = self.size.screen.height
		}

		// If either of our surface dimensions is zero
		// then drawing is absurd, so we just return.
		if surface_width == 0 || surface_height == 0 {
			return
		}
		size_changed := self.size.screen.width != surface_width
			|| self.size.screen.height != surface_height

		// Conditions under which we need to draw the frame, otherwise we
		// don't need to since the previous frame should be identical.
		needs_redraw := size_changed || self.cells_rebuilt || self.reinitialize_shaders
			|| self.has_animations() || sync_

		if !needs_redraw {
			// We still need to present the last target again, because the apprt
			// may be swapping buffers and display an outdated frame if we don't
			// draw something new.
			self.api.present_last_target()!
			return
		}
		self.cells_rebuilt = false
		if self.frames.len == 0 {
			return error('Metal swap chain is unavailable')
		}

		self.acquire_frame()!
		mut frame_submitted := false
		defer {
			if !frame_submitted {
				self.release_frame()
			}
		}
		// SwapChain.nextFrame advances the index before any of the fallible frame
		// preparation below, so a failed frame still consumes its place in the
		// round-robin sequence.
		self.frame_index = (self.frame_index + 1) % self.frames.len
		mut frame_state := &self.frames[self.frame_index]

		if self.reinitialize_shaders {
			self.reinitialize_shaders = false
			self.shaders.deinit()
			post_shaders := load_from_files(self.config.custom_shaders, .msl) or {
				log.warn('error loading custom shaders err=${err}')
				[]string{}
			}
			self.shaders = self.api.init_shaders(post_shaders)!
			self.has_custom_shaders = self.shaders.post_pipelines.len > 0
		}

		post_passes := self.shaders.post_pipelines.len
		self.api.prepare_post_textures(surface_width, surface_height, post_passes)!

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

		gpu_uniforms := metal_uniforms(self.uniforms)
		frame_state.uniforms.sync_values([gpu_uniforms])!
		frame_state.cells_bg.sync_values(self.cells.bg_cells)!
		fg_count := frame_state.cells.sync_from_array_lists(self.cells.fg_rows.lists)!
		if post_passes > 0 {
			frame_state.custom_shader_uniforms.sync_values([self.custom_shader_uniforms])!
		}

		if frame_state.bg_image_buffer_modified != self.bg_image_buffer_modified {
			frame_state.bg_image_buffer.sync_values([self.bg_image_buffer])!
			frame_state.bg_image_buffer_modified = self.bg_image_buffer_modified
		}

		grayscale_modified := self.font_grid.atlas_grayscale.modified.load()
		if grayscale_modified > frame_state.grayscale_modified {
			self.sync_atlas_texture(&self.font_grid.atlas_grayscale, mut frame_state.grayscale)!
			frame_state.grayscale_modified = self.font_grid.atlas_grayscale.modified.load()
		}
		color_modified := self.font_grid.atlas_color.modified.load()
		if color_modified > frame_state.color_modified {
			self.sync_atlas_texture(&self.font_grid.atlas_color, mut frame_state.color)!
			frame_state.color_modified = self.font_grid.atlas_color.modified.load()
		}

		mut frame := MetalFrame.begin_for_device(&self.api, voidptr(self), voidptr(&frame_state.target),
			voidptr(renderer_metal_frame_completed_callback))!
		defer { frame.cancel() }
		mut terminal_target := MetalRenderAttachmentTarget(frame_state.target)
		if post_passes > 0 {
			terminal_target = MetalRenderAttachmentTarget(self.api.post_textures.textures[0])
		}
		mut pass := frame.render_pass([
			MetalRenderPassAttachment{
				target:      terminal_target
				clear_color: [f64(0), 0, 0, 0]!
			},
		])!

		if image := self.bg_image {
			if image is ImageReady {
				pass.step(MetalRenderStep{
					pipeline: self.shaders.bg_image
					uniforms: frame_state.uniforms
					buffers:  [?MetalBuffer(frame_state.bg_image_buffer)]
					textures: [?MetalTexture(MetalTexture(image.texture))]
					draw:     MetalRenderDraw{
						draw_type:    .triangle
						vertex_count: 3
					}
				})
			}
		} else {
			pass.step(MetalRenderStep{
				pipeline: self.shaders.bg_color
				uniforms: frame_state.uniforms
				draw:     MetalRenderDraw{
					draw_type:    .triangle
					vertex_count: 3
				}
			})
		}

		self.images.draw(&self.api, self.shaders.image, frame_state.uniforms, mut pass, .kitty_below_bg)
		if self.cells.bg_cells.len > 0 && self.uniforms.grid_size[0] > 0
			&& self.uniforms.grid_size[1] > 0 {
			pass.step(MetalRenderStep{
				pipeline: self.shaders.cell_bg
				uniforms: frame_state.uniforms
				buffers:  [?MetalBuffer(none), ?MetalBuffer(frame_state.cells_bg)]
				draw:     MetalRenderDraw{
					draw_type:    .triangle
					vertex_count: 3
				}
			})
		}
		self.images.draw(&self.api, self.shaders.image, frame_state.uniforms, mut pass, .kitty_below_text)
		pass.step(MetalRenderStep{
			pipeline: self.shaders.cell_text
			uniforms: frame_state.uniforms
			buffers:  [?MetalBuffer(frame_state.cells), ?MetalBuffer(frame_state.cells_bg)]
			textures: [?MetalTexture(frame_state.grayscale), ?MetalTexture(frame_state.color)]
			draw:     MetalRenderDraw{
				draw_type:      .triangle_strip
				vertex_count:   4
				instance_count: fg_count
			}
		})
		self.images.draw(&self.api, self.shaders.image, frame_state.uniforms, mut pass, .kitty_above_text)
		self.images.draw(&self.api, self.shaders.image, frame_state.uniforms, mut pass, .overlay)
		for index, pipeline in self.shaders.post_pipelines {
			pass.complete()
			input_index := index % 2
			mut output_texture := MetalRenderAttachmentTarget(frame_state.target)
			if index < post_passes - 1 {
				output_texture = MetalRenderAttachmentTarget(self.api.post_textures.textures[1 - input_index])
			}
			pass = frame.render_pass([
				MetalRenderPassAttachment{
					target:      output_texture
					clear_color: [f64(0), 0, 0, 0]!
				},
			])!
			pass.step(MetalRenderStep{
				pipeline: pipeline
				uniforms: frame_state.custom_shader_uniforms
				textures: [?MetalTexture(self.api.post_textures.textures[input_index])]
				samplers: [?MetalSampler(self.api.post_textures.sampler)]
				draw:     MetalRenderDraw{
					draw_type:    .triangle
					vertex_count: 3
				}
			})
		}

		frame.submit(&pass, sync_)!
		frame_submitted = true
	}

	// Metal invokes asynchronous completion blocks on a framework-owned thread.
	// Register that stack while the callback touches V/GC-managed renderer state.
	fn metal_completion_register_thread() bool {
		$if gcboehm ? {
			return C.witty_metal_register_gc_thread()
		} $else {
			return false
		}
	}

	fn metal_completion_unregister_thread(registered bool) {
		$if gcboehm ? {
			if registered {
				C.witty_metal_unregister_gc_thread()
			}
		} $else {
			_ = registered
		}
	}

	fn renderer_metal_frame_completed_callback(renderer_ptr voidptr, target_ptr voidptr, raw_status u64, sync_ bool) {
		registered := metal_completion_register_thread()
		defer {
			metal_completion_unregister_thread(registered)
		}
		if renderer_ptr == unsafe { nil } || target_ptr == unsafe { nil } {
			return
		}
		mut self := unsafe { &Renderer(renderer_ptr) }
		target := unsafe { &MetalTarget(target_ptr) }
		health := if metal_command_buffer_status(raw_status) == .error {
			Health.unhealthy
		} else {
			Health.healthy
		}
		if health == .healthy && self.api.layer != none {
			self.api.present(target, sync_) or {
				log.error('Failed to present render target: err=${err}')
			}
		}
		self.frame_completed(health)
	}

	fn (self &Renderer) sync_atlas_texture(atlas &font.Atlas, mut texture MetalTexture) ! {
		if atlas.size > texture.width {
			// Free our old texture, then reallocate.
			mut replacement := self.api.init_atlas_texture(atlas)!
			texture.deinit()
			texture = replacement
		}
		texture.replace_region(0, 0, atlas.size, atlas.size, atlas.data)
	}

	fn renderer_metal_layer_display_callback(context voidptr) {
		if context == unsafe { nil } {
			return
		}
		mut render := unsafe { &Renderer(context) }
		render.draw_frame(true) or { log.warn('Error drawing frame in display callback, err=${err}') }
	}
}
