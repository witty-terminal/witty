module renderer

import configpkg
import font
import log
import opengl

$if renderer_opengl ?|| (!renderer_metal ?&& !macos && !ios) {

	// Graphics API wrapper for OpenGL.
	//
	// Translated from ghostty/src/renderer/OpenGL.zig.

	// OpenGLAPI wraps the OpenGL graphics API implementation.
	pub struct OpenGLAPI {
	pub mut:
		// Alpha blending mode
		blending configpkg.AlphaBlending

		// The most recently presented target, in case the runtime needs to
		// present it again without redrawing the terminal contents.
		last_target    ?GLTarget
		texture_output bool
		texture_target ?GLTarget
	mut:
		gg GGOpenGLContext
	}

	// We require at least OpenGL 4.3
	pub const opengl_min_version_major = 4
	pub const opengl_min_version_minor = 3

	// Because OpenGL's frame completion is always
	// sync, we have no need for multi-buffering.
	pub const opengl_swap_chain_count = 1

	// The fragCoord for OpenGL shaders is +Y = up.
	pub const opengl_custom_shader_y_is_down = false

	// init constructs the API state without touching an OpenGL context. The
	// context belongs to the application runtime and may not be current when the
	// renderer itself is allocated.
	pub fn OpenGLAPI.init(options RendererOptions) !OpenGLAPI {
		return OpenGLAPI{
			blending: options.config.blending
		}
	}

	// prepare_context loads and configures the OpenGL context made current by the
	// application runtime.
	pub fn prepare_opengl_context(get_proc_address voidptr) ! {
		version := opengl.load(get_proc_address)!
		major := opengl.version_major(version)
		minor := opengl.version_minor(version)
		if major < opengl_min_version_major
			|| (major == opengl_min_version_major && minor < opengl_min_version_minor) {
			opengl.unload()
			return error('OpenGL ${major}.${minor} is too old; Witty requires OpenGL ${opengl_min_version_major}.${opengl_min_version_minor}')
		}
		opengl.enable(opengl.gl_debug_output) or {
			opengl.unload()
			return err
		}
		opengl.debug_message_callback(opengl_debug_message, unsafe { nil }) or {
			opengl.unload()
			return err
		}
		opengl.enable(opengl.gl_framebuffer_srgb) or {
			opengl.unload()
			return err
		}
	}

	fn opengl_debug_message(source u32, typ u32, id u32, severity u32, length int, message &u8, user_param voidptr) {
		_ = user_param
		source_name := match source {
			opengl.gl_debug_source_api { 'OpenGL API' }
			opengl.gl_debug_source_window_system { 'Window System' }
			opengl.gl_debug_source_shader_compiler { 'Shader Compiler' }
			opengl.gl_debug_source_third_party { 'Third Party' }
			opengl.gl_debug_source_application { 'User' }
			opengl.gl_debug_source_other { 'Other' }
			else { 'Unknown' }
		}
		type_name := match typ {
			opengl.gl_debug_type_error { 'Error' }
			opengl.gl_debug_type_deprecated_behavior { 'Deprecated Behavior' }
			opengl.gl_debug_type_undefined_behavior { 'Undefined Behavior' }
			opengl.gl_debug_type_portability { 'Portability Issue' }
			opengl.gl_debug_type_performance { 'Performance Issue' }
			opengl.gl_debug_type_marker { 'Marker' }
			opengl.gl_debug_type_push_group { 'Group Push' }
			opengl.gl_debug_type_pop_group { 'Group Pop' }
			opengl.gl_debug_type_other { 'Other' }
			else { 'Unknown' }
		}
		text := if length > 0 { unsafe { tos(message, length) } } else { '' }
		formatted := '[${id}] (${source_name}: ${type_name}) ${text}'
		match severity {
			opengl.gl_debug_severity_high { log.error(formatted) }
			opengl.gl_debug_severity_medium { log.warn(formatted) }
			opengl.gl_debug_severity_low { log.info(formatted) }
			opengl.gl_debug_severity_notification { log.debug(formatted) }
			else { log.warn('UNKNOWN SEVERITY ${formatted}') }
		}
	}

	pub fn (mut self OpenGLAPI) deinit() {
		self.release_gg()
		self.last_target = none
		if mut output := self.texture_target { output.deinit() }
		self.texture_target = none
	}

	fn (mut self OpenGLAPI) release_gg() {
		$if linux && !renderer_metal ? {
			if self.gg.handle != unsafe { nil } {
				current := self.gg.native == C.witty_gg_gl_current_context()
				if current {
					self.gg.texture_fbo.destroy()
				}
				C.witty_gg_gl_destroy(self.gg.handle, current)
				self.gg = GGOpenGLContext{}
			}
		}
	}

	// surface_init is called immediately after the runtime creates and makes its
	// OpenGL context current.
	pub fn OpenGLAPI.surface_init() ! {
		$if app_runtime_ui2 ?|| (linux && !app_runtime_none ?) {
			prepare_opengl_context(unsafe { nil })!
		}
		// The source embedded runtime intentionally does not prepare a context.
	}

	// finalize_surface_init is present for graphics-API parity. OpenGL has no
	// final main-thread setup after its context is prepared.
	pub fn (self &OpenGLAPI) finalize_surface_init() ! {
		_ = self
	}

	// thread_enter is a renderer-thread lifecycle hook. UI2 performs OpenGL work
	// on the main thread, so there is no context work here.
	pub fn (self &OpenGLAPI) thread_enter() ! {
		_ = self
	}

	// thread_exit mirrors Ghostty's lifecycle hook. Global GTK bindings are
	// intentionally not unloaded because they may be shared by other surfaces.
	pub fn (self &OpenGLAPI) thread_exit() {
		_ = self
	}

	// display_realized reloads the bindings after GTK recreates a surface.
	pub fn (self &OpenGLAPI) display_realized() {
		_ = self
		$if app_runtime_ui2 ?|| (linux && !app_runtime_none ?) {
			prepare_opengl_context(unsafe { nil }) or {
				log.warn('error preparing GL context in display_realized: ${err}')
			}
		} $else {
			// Zig checks this only when the callback is called; V checks every
			// method eagerly, so retain its unsupported-runtime invariant here.
			panic('display_realized requires the standalone OpenGL runtime')
		}
	}

	pub fn (mut self OpenGLAPI) draw_frame_start() {
		_ = self
	}

	pub fn (mut self OpenGLAPI) draw_frame_end() {
		_ = self
	}

	// Get the current size of the runtime surface.
	pub fn (self &OpenGLAPI) surface_size() (u32, u32) {
		_ = self
		viewport := opengl.viewport_rect() or { return 0, 0 }
		if viewport[2] <= 0 || viewport[3] <= 0 {
			return 0, 0
		}
		return u32(viewport[2]), u32(viewport[3])
	}

	// init_shaders initializes the built-in and optional post-process pipelines.
	pub fn (self &OpenGLAPI) init_shaders(custom_shaders []string) !GLShaders {
		_ = self
		return GLShaders.init(custom_shaders)
	}

	// init_target creates an off-screen render target suitable for presentation.
	pub fn (self &OpenGLAPI) init_target(width uint, height uint) !GLTarget {
		// The final target is sRGB for every blending mode in Ghostty 1.4.
		return GLTarget.init(GLTargetOptions{
			width:           width
			height:          height
			internal_format: .srgba
		})
	}

	// present blits an off-screen target to the default framebuffer.
	pub fn (mut self OpenGLAPI) present(target GLTarget) ! {
		opengl.disable(opengl.gl_framebuffer_srgb)!
		fbo_binding := opengl.Framebuffer{
			id: target.fbo
		}.bind(.read) or {
			opengl.enable(opengl.gl_framebuffer_srgb) or {}
			return err
		}
		defer {
			fbo_binding.unbind()
			opengl.enable(opengl.gl_framebuffer_srgb) or {
				log.error('error re-enabling GL_FRAMEBUFFER_SRGB: ${err}')
			}
		}
		if self.texture_output {
			mut output := self.texture_target or { GLTarget{} }
			if output.width != target.width || output.height != target.height {
				replacement := GLTarget.init(GLTargetOptions{
					width:           target.width
					height:          target.height
					internal_format: .rgba
					texture:         true
				})!
				output.deinit()
				output = replacement
				self.texture_target = output
			}
			// Creating a target binds both framebuffer targets. Restore the read
			// attachment before copying its already encoded sRGB bytes for UI2.
			read := opengl.Framebuffer{ id: target.fbo }.bind(.read)!
			defer { read.unbind() }
			draw := opengl.Framebuffer{ id: output.fbo }.bind(.draw)!
			defer { draw.unbind() }
			opengl.blit_framebuffer(0, 0, int(target.width), int(target.height), 0, 0,
				int(target.width), int(target.height), opengl.gl_color_buffer_bit, .nearest)!
			self.last_target = target
			return
		}
		opengl.blit_framebuffer(0, 0, int(target.width), int(target.height), 0, 0, int(target.width), int(target.height), opengl.gl_color_buffer_bit, .nearest)!
		self.last_target = target
	}

	// present_last_target presents the previous target again when a full redraw
	// is unnecessary but the runtime swapped its default framebuffer.
	pub fn (mut self OpenGLAPI) present_last_target() ! {
		if target := self.last_target {
			self.present(target)!
		}
	}

	// buffer_options returns the options shared by all renderer buffer roles.
	pub fn (self &OpenGLAPI) buffer_options() GLBufferOptions {
		_ = self
		return GLBufferOptions{
			target: .array
			usage:  .dynamic_draw
		}
	}

	pub fn (self &OpenGLAPI) instance_buffer_options() GLBufferOptions {
		return self.buffer_options()
	}

	pub fn (self &OpenGLAPI) uniform_buffer_options() GLBufferOptions {
		return self.buffer_options()
	}

	pub fn (self &OpenGLAPI) fg_buffer_options() GLBufferOptions {
		return self.buffer_options()
	}

	pub fn (self &OpenGLAPI) bg_buffer_options() GLBufferOptions {
		return self.buffer_options()
	}

	pub fn (self &OpenGLAPI) image_buffer_options() GLBufferOptions {
		return self.buffer_options()
	}

	pub fn (self &OpenGLAPI) bg_image_buffer_options() GLBufferOptions {
		return self.buffer_options()
	}

	// texture_options returns the standard color texture configuration.
	pub fn (self &OpenGLAPI) texture_options() GLTextureOptions {
		_ = self
		return GLTextureOptions{
			format:          .rgba
			internal_format: .srgba
			target:          .t2d
			min_filter:      .linear
			mag_filter:      .linear
			wrap_s:          .clamp_to_edge
			wrap_t:          .clamp_to_edge
		}
	}

	// sampler_options returns the sampler configuration shared by renderer
	// texture reads.
	pub fn (self &OpenGLAPI) sampler_options() GLSamplerOptions {
		_ = self
		return GLSamplerOptions{
			min_filter: .linear
			mag_filter: .linear
			wrap_s:     .clamp_to_edge
			wrap_t:     .clamp_to_edge
		}
	}

	// ImageTextureFormat is the CPU pixel layout used for uploaded images.
	//
	// Pixel format for image texture options.
	pub enum ImageTextureFormat as u8 {
		// 1 byte per pixel grayscale.
		gray
		// 4 bytes per pixel RGBA.
		rgba
		// 4 bytes per pixel BGRA.
		bgra
	}

	// gl_pixel_format translates an image pixel layout to its OpenGL format.
	fn (format ImageTextureFormat) gl_pixel_format() opengl.TextureFormat {
		return match format {
			.gray { .red }
			.rgba { .rgba }
			.bgra { .bgra }
		}
	}

	// image_texture_options returns the upload and sampling configuration for an
	// image of the given pixel layout and color space.
	pub fn (self &OpenGLAPI) image_texture_options(format ImageTextureFormat, srgb bool) GLTextureOptions {
		_ = self
		return GLTextureOptions{
			format:          format.gl_pixel_format()
			internal_format: if srgb { .srgba } else { .rgba }
			target:          .t2d
			min_filter:      .linear
			mag_filter:      .linear
			wrap_s:          .clamp_to_edge
			wrap_t:          .clamp_to_edge
		}
	}

	// atlas_texture_options translates a font atlas format to its exact OpenGL
	// pixel layout. BGR is unsupported by the source backend.
	pub fn (self &OpenGLAPI) atlas_texture_options(format font.AtlasFormat) !GLTextureOptions {
		_ = self
		return match format {
			.grayscale {
				GLTextureOptions{
					format:          .red
					internal_format: .red
					target:          .rectangle
					min_filter:      .nearest
					mag_filter:      .nearest
					wrap_s:          .clamp_to_edge
					wrap_t:          .clamp_to_edge
				}
			}
			.bgra {
				GLTextureOptions{
					format:          .bgra
					internal_format: .srgba
					target:          .rectangle
					min_filter:      .nearest
					mag_filter:      .nearest
					wrap_s:          .clamp_to_edge
					wrap_t:          .clamp_to_edge
				}
			}
			.bgr {
				return error('BGR font atlases are unsupported by OpenGL')
			}
		}
	}

	// init_atlas_texture initializes an empty texture matching the atlas. Atlas
	// bytes are synchronized separately by the renderer.
	pub fn (self &OpenGLAPI) init_atlas_texture(atlas &font.Atlas) !GLTexture {
		return GLTexture.init(self.atlas_texture_options(atlas.format)!, atlas.size, atlas.size, none)
	}

	// begin_frame creates a frame that presents target on successful completion.
	pub fn (mut self OpenGLAPI) begin_frame(mut target GLTarget) !GLFrame {
		return GLFrame.begin(mut self, mut target)
	}
}
