module renderer

import cimgui
import sokol.gfx

pub struct GGInspectorMetal {
mut:
	acquired bool
	shader   gfx.Shader
	pipeline gfx.Pipeline
	format   gfx.PixelFormat
	sampler  gfx.Sampler
	buffers  GGInspectorBuffers
}

$if macos && !renderer_opengl ? {
	#include "@VMODROOT/renderer/gg_inspector_metal.h"

	@[typedef]
	struct C.witty_gg_inspector_target {
		texture voidptr
		width   u32
		height  u32
		format  u64
		red     f64
		green   f64
		blue    f64
		alpha   f64
	}

	@[typedef]
	struct C.witty_gg_inspector_texture {
		width  u32
		height u32
		format u64
	}

	fn C.witty_gg_inspector_target_get(voidptr) C.witty_gg_inspector_target
	fn C.witty_gg_inspector_texture_get(voidptr) C.witty_gg_inspector_texture

	const inspector_metal_shader = '
#include <metal_stdlib>
using namespace metal;
struct Vertex {
    float2 pos [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float4 color [[attribute(2)]];
};
struct Varying {
    float4 pos [[position]];
    float2 uv;
    float4 color;
};
vertex Varying project(Vertex in [[stage_in]], constant float4x4 &projection [[buffer(0)]]) {
    return Varying{projection * float4(in.pos, 0, 1), in.uv, in.color};
}
fragment half4 shade(Varying in [[stage_in]], texture2d<half> atlas [[texture(0)]],
                     sampler filtering [[sampler(0)]]) {
    return half4(in.color) * atlas.sample(filtering, in.uv);
}
'

	pub fn GGInspectorMetal.acquire(device voidptr) GGInspectorMetal {
		return GGInspectorMetal{ acquired: gg_metal_acquire(device, false) }
	}

	pub fn (mut gpu GGInspectorMetal) release() {
		if !gpu.acquired { return }
		C.witty_gg_metal_lock()
		gpu.buffers.release()
		gfx.destroy_sampler(gpu.sampler)
		gfx.destroy_pipeline(gpu.pipeline)
		gfx.destroy_shader(gpu.shader)
		C.witty_gg_metal_unlock()
		gg_metal_release()
		gpu = GGInspectorMetal{}
	}

	fn (mut gpu GGInspectorMetal) prepare(format gfx.PixelFormat) ! {
		if gpu.shader.id == 0 {
			mut desc := gfx.ShaderDesc{}
			desc.vs.source = &char(inspector_metal_shader.str)
			desc.vs.entry = c'project'
			desc.fs.source = &char(inspector_metal_shader.str)
			desc.fs.entry = c'shade'
			desc.vs.uniform_blocks[0].size = 64
			desc.fs.images[0] = gfx.ShaderImageDesc{ used: true, image_type: ._2d, sample_type: .float }
			desc.fs.samplers[0] = gfx.ShaderSamplerDesc{ used: true, sampler_type: .filtering }
			desc.fs.image_sampler_pairs[0] = gfx.ShaderImageSamplerPairDesc{ used: true }
			shader := gfx.make_shader(&desc)
			if gfx.query_shader_state(shader) != .valid {
				gfx.destroy_shader(shader)
				return error('cannot create GG inspector shader')
			}
			gpu.shader = shader
		}
		if gpu.pipeline.id == 0 || gpu.format != format {
			pipeline := inspector_pipeline(gpu.shader, format, 1)
			if gfx.query_pipeline_state(pipeline) != .valid {
				gfx.destroy_pipeline(pipeline)
				return error('cannot create GG inspector pipeline')
			}
			gfx.destroy_pipeline(gpu.pipeline)
			gpu.pipeline = pipeline
			gpu.format = format
		}
		if gpu.sampler.id == 0 {
			sampler := inspector_sampler(.linear)
			if gfx.query_sampler_state(sampler) != .valid {
				gfx.destroy_sampler(sampler)
				return error('cannot create GG inspector sampler')
			}
			gpu.sampler = sampler
		}
	}

	pub fn (mut gpu GGInspectorMetal) render(ctx cimgui.Context, descriptor voidptr, drawable voidptr) ! {
		if !gpu.acquired { return error('GG inspector renderer is unavailable') }
		target := C.witty_gg_inspector_target_get(descriptor)
		metal_format := unsafe { MetalPixelFormat(target.format) }
		format := gg_metal_pixel_format(metal_format)
		if target.texture == unsafe { nil } || format == .none {
			return error('unsupported GG inspector render target')
		}
		if !ctx.metal_update_textures() { return error('no inspector draw data') }
		data := ctx.draw_frame()
		width := int(data.width * data.scale_x)
		height := int(data.height * data.scale_y)
		if width <= 0 || height <= 0 || width != int(target.width) || height != int(target.height)
			|| data.vertex_stride != inspector_vertex_stride || data.index_stride != inspector_index_stride {
			return error('unsupported GG inspector geometry')
		}
		mut frame := gg_metal_begin()
		defer { frame.cancel() }
		gpu.prepare(format)!
		draws := gpu.buffers.upload(data, width, height, false)!
		mut images := []gfx.Image{cap: draws.len}
		for draw in draws {
			tex := C.witty_gg_inspector_texture_get(draw.texture)
			texture_format := gg_metal_pixel_format(unsafe { MetalPixelFormat(tex.format) })
			if texture_format == .none { return error('unsupported inspector texture') }
			images << frame.import_image(draw.texture, tex.width, tex.height, texture_format, false)!
		}
		clear := [target.red, target.green, target.blue, target.alpha]!
		if drawable == unsafe { nil } {
			frame.render_pass([MetalRenderPassAttachment{
				target:      MetalTarget{
					texture:      target.texture
					width:        target.width
					height:       target.height
					pixel_format: metal_format
				}
				clear_color: clear
			}])!
		} else {
			mut pass := gfx.Pass{
				swapchain: gfx.Swapchain{
					width:        width
					height:       height
					sample_count: 1
					color_format: format
					depth_format: .none
					metal:        gfx.MetalSwapchain{ current_drawable: drawable }
				}
			}
			pass.action.colors[0].load_action = .clear
			pass.action.colors[0].store_action = .store
			pass.action.colors[0].clear_value = gfx.Color{f32(clear[0]), f32(clear[1]), f32(clear[2]), f32(clear[3])}
			gfx.begin_pass(&pass)
		}
		if draws.len > 0 {
			projection := inspector_projection(data, 1)
			gfx.apply_pipeline(gpu.pipeline)
			gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: &projection[0], size: 64 })
			for i, draw in draws {
				gpu.buffers.draw(draw, images[i], gpu.sampler, true)
			}
		}
		gfx.end_pass()
		frame.commit()
	}
}
