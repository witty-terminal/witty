module renderer

import cimgui
import math
import sokol.gfx

pub struct GGInspectorMetal {
mut:
	acquired   bool
	shader     gfx.Shader
	pipeline   gfx.Pipeline
	format     gfx.PixelFormat
	sampler    gfx.Sampler
	vertices   gfx.Buffer
	indices    gfx.Buffer
	vertex_cap int
	index_cap  int
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

	struct GGInspectorMetalDraw {
		bindings gfx.Bindings
		clip     [4]int
		first    int
		count    int
	}

	pub fn GGInspectorMetal.acquire(device voidptr) GGInspectorMetal {
		return GGInspectorMetal{ acquired: gg_metal_acquire(device) }
	}

	pub fn (mut gpu GGInspectorMetal) release() {
		if !gpu.acquired { return }
		C.witty_gg_metal_lock()
		gfx.destroy_buffer(gpu.indices)
		gfx.destroy_buffer(gpu.vertices)
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
			mut desc := gfx.PipelineDesc{
				shader:     gpu.shader
				index_type: .uint16
				depth:      gfx.DepthState{ pixel_format: .none }
			}
			desc.layout.buffers[0].stride = 20
			desc.layout.attrs[0] = gfx.VertexAttrDesc{ format: .float2, offset: 0 }
			desc.layout.attrs[1] = gfx.VertexAttrDesc{ format: .float2, offset: 8 }
			desc.layout.attrs[2] = gfx.VertexAttrDesc{ format: .ubyte4n, offset: 16 }
			desc.colors[0].pixel_format = format
			desc.colors[0].blend = gfx.BlendState{
				enabled:          true
				src_factor_rgb:   .src_alpha
				dst_factor_rgb:   .one_minus_src_alpha
				src_factor_alpha: .one
				dst_factor_alpha: .one_minus_src_alpha
			}
			pipeline := gfx.make_pipeline(&desc)
			if gfx.query_pipeline_state(pipeline) != .valid {
				gfx.destroy_pipeline(pipeline)
				return error('cannot create GG inspector pipeline')
			}
			gfx.destroy_pipeline(gpu.pipeline)
			gpu.pipeline = pipeline
			gpu.format = format
		}
		if gpu.sampler.id == 0 {
			sampler := gfx.make_sampler(&gfx.SamplerDesc{
				min_filter:    .linear
				mag_filter:    .linear
				mipmap_filter: .linear
				wrap_u:        .clamp_to_edge
				wrap_v:        .clamp_to_edge
			})
			if gfx.query_sampler_state(sampler) != .valid {
				gfx.destroy_sampler(sampler)
				return error('cannot create GG inspector sampler')
			}
			gpu.sampler = sampler
		}
	}

	fn inspector_stream_buffer(buffer gfx.Buffer, capacity int, size int, kind gfx.BufferType) !(gfx.Buffer, int) {
		if size <= capacity { return buffer, capacity }
		new_capacity := math.max(4096, size + size / 2)
		next := gfx.make_buffer(&gfx.BufferDesc{ size: uint(new_capacity), usage: .stream, type: kind })
		if gfx.query_buffer_state(next) != .valid {
			gfx.destroy_buffer(next)
			return error('cannot allocate GG inspector geometry')
		}
		gfx.destroy_buffer(buffer)
		return next, new_capacity
	}

	fn inspector_clip(draw cimgui.DrawCommand, data cimgui.DrawFrame, width int, height int) ?[4]int {
		left := math.max(0.0, (draw.left - data.x) * data.scale_x)
		top := math.max(0.0, (draw.top - data.y) * data.scale_y)
		right := math.min(f32(width), (draw.right - data.x) * data.scale_x)
		bottom := math.min(f32(height), (draw.bottom - data.y) * data.scale_y)
		clip := [int(left), int(top), int(right - left), int(bottom - top)]!
		if clip[2] <= 0 || clip[3] <= 0 { return none }
		return clip
	}

	fn (mut gpu GGInspectorMetal) geometry(mut frame GGMetalFrame, data cimgui.DrawFrame, width int, height int) ![]GGInspectorMetalDraw {
		gpu.vertices, gpu.vertex_cap = inspector_stream_buffer(gpu.vertices, gpu.vertex_cap,
			data.vertices * 20, .vertexbuffer)!
		// GG aligns every appended list to four bytes.
		gpu.indices, gpu.index_cap = inspector_stream_buffer(gpu.indices, gpu.index_cap,
			data.indices * 2 + data.lists * 4, .indexbuffer)!
		mut draws := []GGInspectorMetalDraw{}
		for i in 0 .. data.lists {
			list := data.draw_list(i)
			if list.vertex_count == 0 || list.index_count == 0 { continue }
			vertex_base := gfx.append_buffer(gpu.vertices, &gfx.Range{ ptr: list.vertices, size: uint(list.vertex_count * 20) })
			index_base := gfx.append_buffer(gpu.indices, &gfx.Range{ ptr: list.indices, size: uint(list.index_count * 2) })
			if gfx.query_buffer_overflow(gpu.vertices) || gfx.query_buffer_overflow(gpu.indices) {
				return error('GG inspector geometry exceeds its buffers')
			}
			for j in 0 .. list.commands {
				draw := list.command(j)
				if draw.callback { return error('inspector draw uses a native renderer callback') }
				if draw.count == 0 { continue }
				clip := inspector_clip(draw, data, width, height) or { continue }
				if draw.texture == unsafe { nil } { return error('inspector draw has no texture') }
				tex := C.witty_gg_inspector_texture_get(draw.texture)
				format := gg_metal_pixel_format(unsafe { MetalPixelFormat(tex.format) })
				if format == .none { return error('unsupported inspector texture') }
				image := frame.import_image(draw.texture, tex.width, tex.height, format, false)!
				mut bindings := gfx.Bindings{
					index_buffer:        gpu.indices
					index_buffer_offset: index_base
				}
				bindings.vertex_buffers[0] = gpu.vertices
				bindings.vertex_buffer_offsets[0] = vertex_base + int(draw.vertex_offset) * 20
				bindings.fs.images[0] = image
				bindings.fs.samplers[0] = gpu.sampler
				// Leave the index binding four-byte aligned. The index offset is
				// applied in index units by the draw call.
				draws << GGInspectorMetalDraw{
					bindings: bindings
					clip:     clip
					first:    int(draw.index_offset)
					count:    int(draw.count)
				}
			}
		}
		return draws
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
			|| data.vertex_stride != 20 || data.index_stride != 2 {
			return error('unsupported GG inspector geometry')
		}
		mut frame := gg_metal_begin()
		defer { frame.cancel() }
		gpu.prepare(format)!
		draws := gpu.geometry(mut frame, data, width, height)!
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
			left, top := data.x, data.y
			right, bottom := left + data.width, top + data.height
			projection := [f32(2) / (right - left), 0, 0, 0, 0, 2 / (top - bottom), 0, 0, 0, 0,
				1, 0, (right + left) / (left - right), (top + bottom) / (bottom - top), 0, 1]!
			gfx.apply_pipeline(gpu.pipeline)
			gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: &projection[0], size: 64 })
			for draw in draws {
				gfx.apply_scissor_rect(draw.clip[0], draw.clip[1], draw.clip[2], draw.clip[3], true)
				gfx.apply_bindings(&draw.bindings)
				gfx.draw(draw.first, draw.count, 1)
			}
		}
		gfx.end_pass()
		frame.commit()
	}
}
