module renderer

import macos
import sokol.gfx

enum GGMetalDrawKind {
	background
	cell_background
	cell_text
	image
	background_image
	post_process
}

fn (kind GGMetalDrawKind) is_strip() bool {
	return kind in [.cell_text, .image]
}

fn (kind GGMetalDrawKind) texture_count() int {
	return match kind {
		.cell_text { 2 }
		.image, .background_image, .post_process { 1 }
		else { 0 }
	}
}

fn (kind GGMetalDrawKind) has_instance_data() bool {
	return kind.is_strip() || kind == .background_image
}

struct GGMetalPipeline {
	pipeline gfx.Pipeline
	shader   gfx.Shader
	sampler  gfx.Sampler
	kind     GGMetalDrawKind
}

$if macos && !renderer_opengl ? {
	fn (kind GGMetalDrawKind) uniform_size() uint {
		return if kind == .post_process {
			$sizeof(CustomShaderUniforms)
		} else {
			$sizeof(MetalUniforms)
		}
	}

	$if compiled_metallib ? {
		fn (mut shaders MetalShaders) init_gg_pipelines(target_format MetalPixelFormat, post_shaders []string) {
			format := gg_metal_pixel_format(target_format)
			if format == .none {
				return
			}
			C.witty_gg_metal_lock()
			defer { C.witty_gg_metal_unlock() }
			shaders.bg_color.gg = gg_metal_pipeline(.background, format, 'full_screen_vertex', 'bg_color_fragment')
			shaders.cell_bg.gg = gg_metal_pipeline(.cell_background, format, 'full_screen_vertex', 'cell_bg_fragment')
			if gg_metal_supports_packed_cells() {
				shaders.cell_text.gg = gg_metal_pipeline(.cell_text, format, 'cell_text_vertex', 'cell_text_fragment')
			}
			shaders.image.gg = gg_metal_pipeline(.image, format, 'image_vertex', 'image_fragment')
			shaders.bg_image.gg = gg_metal_pipeline(.background_image, format, 'bg_image_vertex', 'bg_image_fragment')
			if C.WITTY_GG_MIXED_SHADER_STAGES != 0 {
				for i, mut pipeline in shaders.post_pipelines {
					pipeline.gg = gg_metal_post_pipeline(format, post_shaders[i])
				}
			}
		}

		fn gg_metal_pipeline(kind GGMetalDrawKind, format gfx.PixelFormat, vertex string, fragment string) GGMetalPipeline {
			mut shader_desc := gg_metal_shader_desc(kind, vertex)
			shader_desc.fs.bytecode = shader_desc.vs.bytecode
			shader_desc.fs.entry = &char(fragment.str)
			return gg_metal_make_pipeline(kind, format, &shader_desc)
		}

		fn gg_metal_post_pipeline(format gfx.PixelFormat, source string) GGMetalPipeline {
			mut shader_desc := gg_metal_shader_desc(.post_process, 'full_screen_vertex')
			shader_desc.fs.source = &char(source.str)
			shader_desc.fs.entry = c'main0'
			return gg_metal_make_pipeline(.post_process, format, &shader_desc)
		}

		fn gg_metal_shader_desc(kind GGMetalDrawKind, vertex string) gfx.ShaderDesc {
			texture_count := kind.texture_count()
			mut shader_desc := gfx.ShaderDesc{}
			// Sokol requires continuous uniform slots in the descriptor. The
			// shared Metal shaders read their uniforms at slot one.
			shader_desc.fs.uniform_blocks[0].size = 16
			shader_desc.fs.uniform_blocks[1].size = kind.uniform_size()
			if texture_count > 0 {
				shader_desc.fs.samplers[0].used = true
				for i in 0 .. texture_count {
					shader_desc.fs.images[i] = gfx.ShaderImageDesc{ used: true, image_type: ._2d }
					shader_desc.fs.image_sampler_pairs[i] = gfx.ShaderImageSamplerPairDesc{
						used:       true
						image_slot: i
					}
				}
				if kind == .background_image {
					shader_desc.vs = shader_desc.fs
				} else if kind.has_instance_data() {
					shader_desc.vs.uniform_blocks = shader_desc.fs.uniform_blocks
				}
			}
			shader_desc.vs.bytecode = gfx.Range{
				ptr:  metal_shader_library.data
				size: uint(metal_shader_library.len)
			}
			shader_desc.vs.entry = &char(vertex.str)
			return shader_desc
		}

		fn gg_metal_make_pipeline(kind GGMetalDrawKind, format gfx.PixelFormat, shader_desc &gfx.ShaderDesc) GGMetalPipeline {
			shader := gfx.make_shader(shader_desc)
			if gfx.query_shader_state(shader) != .valid {
				gfx.destroy_shader(shader)
				return GGMetalPipeline{}
			}

			mut desc := gfx.PipelineDesc{
				shader:         shader
				depth:          gfx.DepthState{ pixel_format: .none }
				primitive_type: if kind.is_strip() { .triangle_strip } else { .triangles }
				layout:         gg_metal_vertex_layout(kind)
			}
			desc.colors[0].pixel_format = format
			desc.colors[0].blend = gfx.BlendState{
				enabled:          kind !in [.background, .post_process]
				src_factor_rgb:   .one
				dst_factor_rgb:   .one_minus_src_alpha
				src_factor_alpha: .one
				dst_factor_alpha: .one_minus_src_alpha
			}
			pipeline := gfx.make_pipeline(&desc)
			if gfx.query_pipeline_state(pipeline) != .valid {
				gfx.destroy_pipeline(pipeline)
				gfx.destroy_shader(shader)
				return GGMetalPipeline{}
			}
			mut sampler := gfx.Sampler{}
			if kind.texture_count() > 0 {
				// Post-processing samples with this sampler. Built-in shaders
				// specify their pixel-coordinate sampler in Metal source.
				filter := if kind == .cell_text { gfx.Filter.nearest } else { .linear }
				sampler = gfx.make_sampler(&gfx.SamplerDesc{
					min_filter: filter
					mag_filter: filter
					wrap_u:     .clamp_to_edge
					wrap_v:     .clamp_to_edge
				})
				if gfx.query_sampler_state(sampler) != .valid {
					gfx.destroy_sampler(sampler)
					gfx.destroy_pipeline(pipeline)
					gfx.destroy_shader(shader)
					return GGMetalPipeline{}
				}
			}
			return GGMetalPipeline{ pipeline: pipeline, shader: shader, sampler: sampler, kind: kind }
		}
	}

	fn gg_metal_supports_packed_cells() bool {
		return C.WITTY_GG_USHORT2 != 0 && C.WITTY_GG_UBYTE != 0
	}

	fn gg_metal_vertex_layout(kind GGMetalDrawKind) gfx.VertexLayoutState {
		attributes, stride := match kind {
			.cell_text { metal_text_cell_attributes(), int($sizeof(CellText)) }
			.image { metal_image_attributes(), int($sizeof(ImageVertex)) }
			.background_image { metal_bg_image_attributes(), int($sizeof(BgImageBuffer)) }
			else { return gfx.VertexLayoutState{} }
		}
		mut layout := gfx.VertexLayoutState{}
		layout.buffers[0] = gfx.VertexBufferLayoutState{ stride: stride, step_func: .per_instance }
		for i, attribute in attributes {
			format := match attribute.format {
				.float { gfx.VertexFormat.float }
				.float2 { .float2 }
				.float4 { .float4 }
				.uint2 { .uint2 }
				.short2 { .short2 }
				.ushort2 { unsafe { gfx.VertexFormat(C.WITTY_GG_USHORT2) } }
				.uchar4 { .ubyte4 }
				.uchar {
					// For BgImageBuffer, stock V can still read the first
					// component of a vector covering the trailing padding.
					if C.WITTY_GG_UBYTE == 0 {
						.ubyte4
					} else {
						unsafe { gfx.VertexFormat(C.WITTY_GG_UBYTE) }
					}
				}
				else { .invalid }
			}
			layout.attrs[i] = gfx.VertexAttrDesc{ offset: int(attribute.offset), format: format }
		}
		return layout
	}

	fn (pipeline GGMetalPipeline) deinit() {
		if pipeline.pipeline.id == 0 {
			return
		}
		C.witty_gg_metal_lock()
		defer { C.witty_gg_metal_unlock() }
		gfx.destroy_pipeline(pipeline.pipeline)
		gfx.destroy_shader(pipeline.shader)
		if pipeline.sampler.id != 0 {
			gfx.destroy_sampler(pipeline.sampler)
		}
	}

	fn (mut frame GGMetalFrame) import_vertex_buffer(handle voidptr) !gfx.Buffer {
		for entry in frame.buffers {
			if entry.handle == handle {
				return entry.buffer
			}
		}
		size := macos.metal_buffer_length(handle)
		if size == 0 {
			return error('GG Metal vertex buffer is empty')
		}
		retained := C.witty_gg_metal_retain_import(handle)
		buffer := gfx.make_buffer(&gfx.BufferDesc{
			size:        size
			mtl_buffers: [handle, unsafe { nil }]!
		})
		if gfx.query_buffer_state(buffer) != .valid {
			gfx.destroy_buffer(buffer)
			if retained {
				macos.metal_release(handle)
			}
			return error('GG could not import the Metal vertex buffer')
		}
		frame.buffers << GGMetalBuffer{ handle: handle, buffer: buffer }
		return buffer
	}

	fn (mut frame GGMetalFrame) draw(encoder voidptr, step MetalRenderStep) ! {
		pipeline := step.pipeline.gg
		primitive := if pipeline.kind.is_strip() {
			MetalPrimitiveType.triangle_strip
		} else {
			.triangle
		}
		if step.draw.draw_type != primitive || step.draw.vertex_count > max_i32
			|| step.draw.instance_count > max_i32 {
			return error('GG Metal draw does not match the pipeline primitive or count range')
		}
		uniforms := step.uniforms or { return error('GG Metal draw has no uniforms') }
		if uniforms.handle == unsafe { nil }
			|| macos.metal_buffer_length(uniforms.handle) < pipeline.kind.uniform_size() {
			return error('GG Metal draw has invalid uniforms')
		}
		mut bindings := gfx.Bindings{}
		mut cell_backgrounds := voidptr(unsafe { nil })
		if pipeline.kind in [.cell_background, .cell_text] {
			if step.buffers.len < 2 {
				return error('GG Metal draw has no cell background buffer slot')
			}
			buffer := step.buffers[1] or { return error('GG Metal draw has no cell backgrounds') }
			cell_backgrounds = buffer.handle
		}
		texture_count := pipeline.kind.texture_count()
		if pipeline.kind.has_instance_data() {
			if step.buffers.len == 0 {
				return error('GG Metal draw has no vertex buffer slot')
			}
			buffer := step.buffers[0] or { return error('GG Metal draw has no vertices') }
			bindings.vertex_buffers[0] = frame.import_vertex_buffer(buffer.handle)!
		}
		if texture_count > 0 {
			if step.textures.len < texture_count {
				return error('GG Metal draw has missing texture slots')
			}
			for i in 0 .. texture_count {
				texture := step.textures[i] or { return error('GG Metal draw has no texture') }
				bindings.fs.images[i] = frame.sample_image(texture)!
			}
			bindings.fs.samplers[0] = pipeline.sampler
			if pipeline.kind == .background_image {
				bindings.vs = bindings.fs
			}
		}

		if frame.native_draw {
			// A native draw can replace Sokol's cached bindings and uniform
			// buffer. Restore them before returning to Sokol on this pass.
			gfx.reset_state_cache()
			frame.native_draw = false
		}
		gfx.apply_pipeline(pipeline.pipeline)
		gfx.apply_bindings(&bindings)
		// The renderer owns this buffer for the entire in-flight frame.
		macos.metal_encoder_set_buffer(encoder, uniforms.handle, 1)
		if cell_backgrounds != unsafe { nil } {
			// The shader reads the variable-length grid from Metal buffer two,
			// outside Sokol's storage buffer slots.
			macos.metal_encoder_set_buffer(encoder, cell_backgrounds, 2)
		}
		gfx.draw(0, int(step.draw.vertex_count), int(step.draw.instance_count))
	}
}
