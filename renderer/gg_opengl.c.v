module renderer

import opengl
import sokol.gfx
import sokol.memory

$if renderer_opengl ?|| (!renderer_metal ?&& !macos && !ios) {
	struct GGOpenGLPipeline {
		program   u32
		primitive opengl.Primitive
		format    gfx.PixelFormat
		pipeline  gfx.Pipeline
	}

	struct GGOpenGLContext {
		handle      voidptr
		native      voidptr
		texture_fbo opengl.Framebuffer
	mut:
		pipelines []GGOpenGLPipeline
	}
}

$if linux && !renderer_metal ? {
	#include "@VMODROOT/renderer/gg_opengl.h"

	fn C.witty_gg_gl_current_context() voidptr
	fn C.witty_gg_gl_setup(desc &gfx.Desc) voidptr
	fn C.witty_gg_gl_destroy(state voidptr, current bool)
	fn C.witty_gg_gl_begin_pass(state voidptr, pass &gfx.Pass) voidptr
	fn C.witty_gg_gl_end_pass(scope voidptr)
	fn C.witty_gg_gl_commit(state voidptr)
	fn C.witty_gg_gl_restore_ui_state()

	// Terminal rendering and UI2 share a GL context but use separate GFX state.
	pub fn restore_ui2_opengl_state() {
		C.witty_gg_gl_restore_ui_state()
	}

	fn (mut api OpenGLAPI) gg_render_pass(attachment GLRenderAttachment) !(voidptr, gfx.PixelFormat) {
		native := C.witty_gg_gl_current_context()
		if native == unsafe { nil } {
			return unsafe { nil }, .none
		}
		if api.gg.native != native {
			api.release_gg()
			opengl.get_error()!
			mut desc := gfx.Desc{}
			desc.logger.func = memory.slog
			handle := C.witty_gg_gl_setup(&desc)
			if handle == unsafe { nil } {
				return unsafe { nil }, .none
			}
			fbo := opengl.Framebuffer.create() or {
				C.witty_gg_gl_destroy(handle, true)
				return err
			}
			api.gg = GGOpenGLContext{ handle: handle, native: native, texture_fbo: fbo }
		}

		target := attachment.target
		fbo, width, height, format := match target {
			GLTarget { target.fbo, target.width, target.height, target.internal_format }
			GLTexture {
				bind := api.gg.texture_fbo.bind(.draw)!
				defer { bind.unbind() }
				bind.texture_2d(.color0, target.target, opengl.Texture{ id: target.id }, 0)!
				if bind.check_status() != .complete {
					return error('OpenGL post-processing framebuffer is incomplete')
				}
				api.gg.texture_fbo.id, target.width, target.height, target.internal_format
			}
		}
		if fbo == 0 || width == 0 || height == 0 || width > max_i32 || height > max_i32 {
			return error('invalid GG OpenGL framebuffer')
		}

		color_format := if format == .srgba { gfx.PixelFormat.srgb8a8 } else { .rgba8 }
		mut pass := gfx.Pass{
			swapchain: gfx.Swapchain{
				width:        int(width)
				height:       int(height)
				sample_count: 1
				color_format: color_format
				depth_format: .none
				gl:           gfx.GlSwapchain{ framebuffer: fbo }
			}
		}
		pass.action.depth.load_action = .dontcare
		pass.action.stencil.load_action = .dontcare
		pass.action.colors[0].store_action = .store
		if color := attachment.clear_color {
			pass.action.colors[0].load_action = .clear
			pass.action.colors[0].clear_value = gfx.Color{ r: color[0], g: color[1], b: color[2], a: color[3] }
		} else {
			pass.action.colors[0].load_action = .load
		}
		scope := C.witty_gg_gl_begin_pass(api.gg.handle, &pass)
		if scope == unsafe { nil } {
			return error('could not begin GG OpenGL pass')
		}
		return scope, color_format
	}

	fn (mut api OpenGLAPI) gg_pipeline(step GLRenderStep, format gfx.PixelFormat) gfx.Pipeline {
		native := step.pipeline
		for cached in api.gg.pipelines {
			if cached.program == native.program && cached.primitive == step.draw.primitive
				&& cached.format == format {
				return cached.pipeline
			}
		}
		primitive := match step.draw.primitive {
			.triangle { gfx.PrimitiveType.triangles }
			.triangle_strip { .triangle_strip }
			else { return gfx.Pipeline{} }
		}
		if native.vertex_source == '' || native.fragment_source == '' {
			return gfx.Pipeline{}
		}
		mut source := gfx.ShaderDesc{}
		source.vs.source = &char(native.vertex_source.str)
		source.fs.source = &char(native.fragment_source.str)
		shader := gfx.make_shader(&source)
		mut pipeline := gfx.Pipeline{}
		if gfx.query_shader_state(shader) == .valid {
			mut desc := gfx.PipelineDesc{
				shader:         shader
				primitive_type: primitive
				depth:          gfx.DepthState{ pixel_format: .none }
			}
			desc.colors[0].pixel_format = format
			desc.colors[0].blend = gfx.BlendState{
				enabled:          native.blending_enabled
				src_factor_rgb:   .one
				dst_factor_rgb:   .one_minus_src_alpha
				src_factor_alpha: .one
				dst_factor_alpha: .one_minus_src_alpha
			}
			pipeline = gfx.make_pipeline(&desc)
			if gfx.query_pipeline_state(pipeline) != .valid {
				gfx.destroy_pipeline(pipeline)
				pipeline = gfx.Pipeline{}
			}
		}
		if pipeline.id == 0 {
			gfx.destroy_shader(shader)
		}
		api.gg.pipelines << GGOpenGLPipeline{
			program:   native.program
			primitive: step.draw.primitive
			format:    format
			pipeline:  pipeline
		}
		return pipeline
	}

	fn (mut pass GLRenderPass) apply_gg_pipeline(step GLRenderStep) bool {
		if pass.gg_scope == unsafe { nil } || step.draw.vertex_count > max_i32
			|| step.draw.instance_count > max_i32 {
			return false
		}
		pipeline := pass.gg_api.gg_pipeline(step, pass.gg_format)
		if pipeline.id == 0 {
			return false
		}
		if pass.gg_needs_reset {
			gfx.reset_state_cache()
			pass.gg_needs_reset = false
		}
		gfx.apply_pipeline(pipeline)
		// Witty's existing VAO and GLSL buffer and sampler slots describe
		// the packed cells, rectangle glyph atlases and uniform blocks.
		gfx.apply_bindings(&gfx.Bindings{})
		return true
	}
}
