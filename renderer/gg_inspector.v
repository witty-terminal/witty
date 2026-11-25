module renderer

import cimgui
import math
import sokol.gfx

const inspector_vertex_stride = 20
const inspector_index_stride = 2

struct GGInspectorBuffers {
mut:
	vertices   gfx.Buffer
	indices    gfx.Buffer
	vertex_cap int
	index_cap  int
}

struct GGInspectorDraw {
	texture voidptr
	clip    [4]int
	vertex  int
	index   int
	first   int
	count   int
}

fn (mut buffers GGInspectorBuffers) release() {
	gfx.destroy_buffer(buffers.indices)
	gfx.destroy_buffer(buffers.vertices)
	buffers = GGInspectorBuffers{}
}

fn inspector_pipeline(shader gfx.Shader, format gfx.PixelFormat, samples int) gfx.Pipeline {
	mut desc := gfx.PipelineDesc{
		shader:       shader
		index_type:   .uint16
		sample_count: samples
		depth:        gfx.DepthState{ pixel_format: .none }
	}
	desc.layout.buffers[0].stride = inspector_vertex_stride
	desc.layout.attrs[0] = gfx.VertexAttrDesc{ format: .float2 }
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
	return gfx.make_pipeline(&desc)
}

fn inspector_sampler(mipmap_filter gfx.Filter) gfx.Sampler {
	return gfx.make_sampler(&gfx.SamplerDesc{
		min_filter:    .linear
		mag_filter:    .linear
		mipmap_filter: mipmap_filter
		wrap_u:        .clamp_to_edge
		wrap_v:        .clamp_to_edge
	})
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

fn inspector_clip(draw cimgui.DrawCommand, data cimgui.DrawFrame, width int, height int, gl bool) ?[4]int {
	left := (draw.left - data.x) * data.scale_x
	top := (draw.top - data.y) * data.scale_y
	right := (draw.right - data.x) * data.scale_x
	bottom := (draw.bottom - data.y) * data.scale_y
	clip := if gl {
		// Match glScissor's bottom-left origin and its rounding of both the
		// origin and extent before clipping against the framebuffer.
		[int(left), int(f32(height) - bottom), int(right - left), int(bottom - top)]!
	} else {
		[int(math.max(0.0, left)), int(math.max(0.0, top)),
			int(math.min(f32(width), right) - math.max(0.0, left)),
			int(math.min(f32(height), bottom) - math.max(0.0, top))]!
	}
	if clip[2] <= 0 || clip[3] <= 0 { return none }
	return clip
}

fn (mut buffers GGInspectorBuffers) upload(data cimgui.DrawFrame, width int, height int, gl bool) ![]GGInspectorDraw {
	buffers.vertices, buffers.vertex_cap = inspector_stream_buffer(buffers.vertices, buffers.vertex_cap,
		data.vertices * inspector_vertex_stride, .vertexbuffer)!
	// GG aligns each appended list to four bytes.
	buffers.indices, buffers.index_cap = inspector_stream_buffer(buffers.indices, buffers.index_cap,
		data.indices * inspector_index_stride + data.lists * 4, .indexbuffer)!
	mut draws := []GGInspectorDraw{}
	for i in 0 .. data.lists {
		list := data.draw_list(i)
		if list.vertex_count == 0 || list.index_count == 0 { continue }
		vertex := gfx.append_buffer(buffers.vertices, &gfx.Range{
			ptr:  list.vertices
			size: uint(list.vertex_count * inspector_vertex_stride)
		})
		index := gfx.append_buffer(buffers.indices, &gfx.Range{
			ptr:  list.indices
			size: uint(list.index_count * inspector_index_stride)
		})
		if gfx.query_buffer_overflow(buffers.vertices) || gfx.query_buffer_overflow(buffers.indices) {
			return error('GG inspector geometry exceeds its buffers')
		}
		for j in 0 .. list.commands {
			draw := list.command(j)
			if draw.callback { return error('inspector draw uses a native renderer callback') }
			if draw.count == 0 { continue }
			clip := inspector_clip(draw, data, width, height, gl) or { continue }
			if draw.texture == unsafe { nil } { return error('inspector draw has no texture') }
			draws << GGInspectorDraw{
				texture: draw.texture
				clip:    clip
				vertex:  vertex + int(draw.vertex_offset) * inspector_vertex_stride
				index:   index
				first:   int(draw.index_offset)
				count:   int(draw.count)
			}
		}
	}
	return draws
}

fn inspector_projection(data cimgui.DrawFrame, z f32) [16]f32 {
	left, top := data.x, data.y
	right, bottom := left + data.width, top + data.height
	return [f32(2) / (right - left), 0, 0, 0, 0, 2 / (top - bottom), 0, 0, 0, 0, z, 0,
		(right + left) / (left - right), (top + bottom) / (bottom - top), 0, 1]!
}

fn (buffers &GGInspectorBuffers) draw(cmd GGInspectorDraw, image gfx.Image, sampler gfx.Sampler, origin_top_left bool) {
	mut bindings := gfx.Bindings{
		index_buffer:        buffers.indices
		index_buffer_offset: cmd.index
	}
	bindings.vertex_buffers[0] = buffers.vertices
	bindings.vertex_buffer_offsets[0] = cmd.vertex
	bindings.fs.images[0] = image
	bindings.fs.samplers[0] = sampler
	gfx.apply_scissor_rect(cmd.clip[0], cmd.clip[1], cmd.clip[2], cmd.clip[3], origin_top_left)
	gfx.apply_bindings(&bindings)
	gfx.draw(cmd.first, cmd.count, 1)
}
