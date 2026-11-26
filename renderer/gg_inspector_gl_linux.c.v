module renderer

import cimgui
import sokol.gfx
import sokol.memory

$if !renderer_metal ? {
	#include "@VMODROOT/renderer/gg_inspector_gl.h"

	@[typedef]
	struct C.witty_gg_inspector_gl_target {
		framebuffer u32
		width       int
		height      int
		samples     int
		srgb        bool
	}

	@[typedef]
	struct C.witty_gg_inspector_gl_texture {
		width  int
		height int
	}

	fn C.witty_gg_inspector_gl_target_get() C.witty_gg_inspector_gl_target
	fn C.witty_gg_inspector_gl_texture_get(u32) C.witty_gg_inspector_gl_texture

	const inspector_gl_vertex = '#version 330
layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 color;
uniform mat4 projection;
out vec2 frag_uv;
out vec4 frag_color;
void main() {
	gl_Position = projection * vec4(pos, 0, 1);
	frag_uv = uv;
	frag_color = color;
}
'

	const inspector_gl_fragment = '#version 330
uniform sampler2D atlas;
in vec2 frag_uv;
in vec4 frag_color;
out vec4 color;
void main() {
	color = frag_color * texture(atlas, frag_uv);
}
'

	pub struct GGInspectorGL {
	mut:
		state    voidptr
		context  voidptr
		buffers  GGInspectorBuffers
		shader   gfx.Shader
		pipeline gfx.Pipeline
		sampler  gfx.Sampler
		format   gfx.PixelFormat
		samples  int
	}

	// The GLArea must make its context current before releasing its renderer.
	pub fn (mut gpu GGInspectorGL) release() {
		if gpu.state != unsafe { nil } {
			C.witty_gg_gl_destroy(gpu.state, gpu.context == C.witty_gg_gl_current_context())
			gpu = GGInspectorGL{}
		}
	}

	fn (mut gpu GGInspectorGL) prepare(format gfx.PixelFormat, samples int) ! {
		if gpu.shader.id == 0 {
			mut desc := gfx.ShaderDesc{}
			desc.vs.source = &char(inspector_gl_vertex.str)
			desc.fs.source = &char(inspector_gl_fragment.str)
			desc.vs.uniform_blocks[0].size = 64
			desc.vs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'projection', type: .mat4 }
			desc.fs.images[0] = gfx.ShaderImageDesc{ used: true, image_type: ._2d, sample_type: .float }
			desc.fs.samplers[0] = gfx.ShaderSamplerDesc{ used: true, sampler_type: .filtering }
			desc.fs.image_sampler_pairs[0] = gfx.ShaderImageSamplerPairDesc{ used: true, glsl_name: c'atlas' }
			shader := gfx.make_shader(&desc)
			if gfx.query_shader_state(shader) != .valid {
				gfx.destroy_shader(shader)
				return error('cannot create GG inspector shader')
			}
			gpu.shader = shader
		}
		if gpu.pipeline.id == 0 || gpu.format != format || gpu.samples != samples {
			pipeline := inspector_pipeline(gpu.shader, format, samples)
			if gfx.query_pipeline_state(pipeline) != .valid {
				gfx.destroy_pipeline(pipeline)
				return error('cannot create GG inspector pipeline')
			}
			gfx.destroy_pipeline(gpu.pipeline)
			gpu.pipeline = pipeline
			gpu.format = format
			gpu.samples = samples
		}
		if gpu.sampler.id == 0 {
			sampler := inspector_sampler(.none)
			if gfx.query_sampler_state(sampler) != .valid {
				gfx.destroy_sampler(sampler)
				return error('cannot create GG inspector sampler')
			}
			gpu.sampler = sampler
		}
	}

	pub fn (mut gpu GGInspectorGL) render(ctx cimgui.Context, background [4]f32) ! {
		native := C.witty_gg_gl_current_context()
		if native == unsafe { nil } { return error('GG inspector has no current OpenGL context') }
		target := C.witty_gg_inspector_gl_target_get()
		if target.framebuffer == 0 { return error('GG inspector requires a GLArea framebuffer') }
		if !ctx.opengl_update_textures() { return error('no inspector draw data') }
		data := ctx.draw_frame()
		width := int(data.width * data.scale_x)
		height := int(data.height * data.scale_y)
		if width <= 0 || height <= 0 || data.vertex_stride != inspector_vertex_stride
			|| data.index_stride != inspector_index_stride {
			return error('unsupported GG inspector geometry')
		}
		if gpu.context != native {
			gpu.release()
			mut desc := gfx.Desc{}
			desc.logger.func = memory.slog
			state := C.witty_gg_gl_setup(&desc)
			if state == unsafe { nil } {
				return error('cannot initialize GG inspector OpenGL state')
			}
			gpu.state = state
			gpu.context = native
		}

		format := if target.srgb { gfx.PixelFormat.srgb8a8 } else { .rgba8 }
		mut pass := gfx.Pass{
			swapchain: gfx.Swapchain{
				width:        if target.width > 0 { target.width } else { width }
				height:       if target.height > 0 { target.height } else { height }
				sample_count: target.samples
				color_format: format
				depth_format: .none
				gl:           gfx.GlSwapchain{ framebuffer: target.framebuffer }
			}
		}
		pass.action.colors[0].load_action = .clear
		pass.action.colors[0].clear_value = gfx.Color{
			r: background[0]
			g: background[1]
			b: background[2]
			a: background[3]
		}
		pass.action.colors[0].store_action = .store
		pass.action.depth.load_action = .dontcare
		pass.action.stencil.load_action = .dontcare
		scope := C.witty_gg_gl_begin_pass(gpu.state, &pass)
		if scope == unsafe { nil } { return error('cannot begin GG inspector OpenGL pass') }
		defer {
			C.witty_gg_gl_end_pass(scope)
			C.witty_gg_gl_commit(gpu.state)
		}
		gfx.reset_state_cache()
		gpu.prepare(format, target.samples)!
		draws := gpu.buffers.upload(data, width, height, true)!
		mut images := map[u32]gfx.Image{}
		defer {
			for _, image in images { gfx.destroy_image(image) }
		}
		for draw in draws {
			name := u32(uint(draw.texture))
			if name in images { continue }
			size := C.witty_gg_inspector_gl_texture_get(name)
			if size.width <= 0 || size.height <= 0 { return error('unsupported inspector texture') }
			image := gfx.make_image(&gfx.ImageDesc{
				width:        size.width
				height:       size.height
				pixel_format: .rgba8
				gl_textures:  [name, 0]!
			})
			if gfx.query_image_state(image) != .valid {
				gfx.destroy_image(image)
				return error('cannot import inspector texture into GG')
			}
			images[name] = image
		}
		if draws.len > 0 {
			projection := inspector_projection(data, -1)
			gfx.apply_viewport(0, 0, width, height, false)
			gfx.apply_pipeline(gpu.pipeline)
			gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: &projection[0], size: 64 })
			for draw in draws {
				gpu.buffers.draw(draw, images[u32(uint(draw.texture))], gpu.sampler, false)
			}
		}
	}
}
