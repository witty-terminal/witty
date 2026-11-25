module renderer

import macos
import sokol.gfx

enum GGMetalDrawKind {
	background
	cell_background
	image
	background_image
}

struct GGMetalPipeline {
	pipeline gfx.Pipeline
	shader   gfx.Shader
	sampler  gfx.Sampler
	kind     GGMetalDrawKind
}

$if macos && !renderer_opengl ? {
	$if compiled_metallib ? {
		fn (mut shaders MetalShaders) init_gg_pipelines() {
			C.witty_gg_metal_lock()
			defer { C.witty_gg_metal_unlock() }
			shaders.bg_color.gg = gg_metal_pipeline(.background, 'full_screen_vertex', 'bg_color_fragment')
			shaders.cell_bg.gg = gg_metal_pipeline(.cell_background, 'full_screen_vertex', 'cell_bg_fragment')
			shaders.image.gg = gg_metal_pipeline(.image, 'image_vertex', 'image_fragment')
			shaders.bg_image.gg = gg_metal_pipeline(.background_image, 'bg_image_vertex', 'bg_image_fragment')
		}

		fn gg_metal_pipeline(kind GGMetalDrawKind, vertex string, fragment string) GGMetalPipeline {
			bytecode := gfx.Range{
				ptr:  metal_shader_library.data
				size: uint(metal_shader_library.len)
			}
			textured := kind in [.image, .background_image]
			mut shader_desc := gfx.ShaderDesc{}
			// Sokol requires continuous uniform slots in the descriptor. The
			// shared Metal shaders read their uniforms at slot one.
			shader_desc.fs.uniform_blocks[0].size = 16
			shader_desc.fs.uniform_blocks[1].size = $sizeof(MetalUniforms)
			if textured {
				shader_desc.fs.images[0] = gfx.ShaderImageDesc{ used: true, image_type: ._2d }
				shader_desc.fs.samplers[0].used = true
				shader_desc.fs.image_sampler_pairs[0].used = true
				if kind == .background_image {
					shader_desc.vs = shader_desc.fs
				} else {
					shader_desc.vs.uniform_blocks = shader_desc.fs.uniform_blocks
				}
			}
			shader_desc.vs.bytecode = bytecode
			shader_desc.vs.entry = &char(vertex.str)
			shader_desc.fs.bytecode = bytecode
			shader_desc.fs.entry = &char(fragment.str)
			shader := gfx.make_shader(&shader_desc)
			if gfx.query_shader_state(shader) != .valid {
				gfx.destroy_shader(shader)
				return GGMetalPipeline{}
			}

			mut desc := gfx.PipelineDesc{
				shader:         shader
				depth:          gfx.DepthState{ pixel_format: .none }
				primitive_type: .triangles
			}
			desc.colors[0].pixel_format = .bgra8
			desc.colors[0].blend = gfx.BlendState{
				enabled:          kind != .background
				src_factor_rgb:   .one
				dst_factor_rgb:   .one_minus_src_alpha
				src_factor_alpha: .one
				dst_factor_alpha: .one_minus_src_alpha
			}
			if kind == .image {
				desc.primitive_type = .triangle_strip
				desc.layout.buffers[0] = gfx.VertexBufferLayoutState{
					stride:    int($sizeof(ImageVertex))
					step_func: .per_instance
				}
				for i, attribute in metal_image_attributes() {
					desc.layout.attrs[i] = gfx.VertexAttrDesc{
						offset: int(attribute.offset)
						format: if attribute.format == .float4 { .float4 } else { .float2 }
					}
				}
			}
			if kind == .background_image {
				desc.layout.buffers[0] = gfx.VertexBufferLayoutState{
					stride:    int($sizeof(BgImageBuffer))
					step_func: .per_instance
				}
				desc.layout.attrs[0] = gfx.VertexAttrDesc{
					offset: __offsetof(BgImageBuffer, opacity)
					format: .float
				}
				// Metal takes the first component for the shader's scalar
				// uchar. The following bytes are padding in BgImageBuffer.
				desc.layout.attrs[1] = gfx.VertexAttrDesc{
					offset: __offsetof(BgImageBuffer, info)
					format: .ubyte4
				}
			}
			pipeline := gfx.make_pipeline(&desc)
			if gfx.query_pipeline_state(pipeline) != .valid {
				gfx.destroy_pipeline(pipeline)
				gfx.destroy_shader(shader)
				return GGMetalPipeline{}
			}
			mut sampler := gfx.Sampler{}
			if textured {
				// Sokol validates the texture and sampler as a pair. The
				// Metal shader uses its own pixel-coordinate constexpr sampler.
				sampler = gfx.make_sampler(&gfx.SamplerDesc{
					min_filter: .linear
					mag_filter: .linear
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
		primitive := if pipeline.kind == .image {
			MetalPrimitiveType.triangle_strip
		} else {
			.triangle
		}
		if step.draw.draw_type != primitive || step.draw.vertex_count > max_i32
			|| step.draw.instance_count > max_i32 {
			return error('GG Metal draw does not match the pipeline primitive or count range')
		}
		uniforms := step.uniforms or { return error('GG Metal draw has no uniforms') }
		uniform_size := $sizeof(MetalUniforms)
		data := macos.metal_buffer_contents(uniforms.handle)
		if data == unsafe { nil } || macos.metal_buffer_length(uniforms.handle) < uniform_size {
			return error('GG Metal draw has invalid uniforms')
		}
		uniform_range := gfx.Range{ ptr: data, size: uniform_size }
		mut bindings := gfx.Bindings{}
		mut cell_backgrounds := voidptr(unsafe { nil })
		match pipeline.kind {
			.background {}
			.cell_background {
				if step.buffers.len < 2 {
					return error('GG Metal draw has no cell background buffer slot')
				}
				buffer := step.buffers[1] or { return error('GG Metal draw has no cell backgrounds') }
				cell_backgrounds = buffer.handle
			}
			.image, .background_image {
				if step.buffers.len == 0 || step.textures.len == 0 {
					return error('GG Metal image draw has no buffer or texture slot')
				}
				buffer := step.buffers[0] or { return error('GG Metal image draw has no vertices') }
				texture := step.textures[0] or { return error('GG Metal image draw has no texture') }
				bindings.vertex_buffers[0] = frame.import_vertex_buffer(buffer.handle)!
				bindings.fs.images[0] = frame.import_image(texture.handle, texture.width,
					texture.height, .srgb8a8, false)!
				bindings.fs.samplers[0] = pipeline.sampler
				if pipeline.kind == .background_image {
					bindings.vs = bindings.fs
				}
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
		if pipeline.kind in [.image, .background_image] {
			gfx.apply_uniforms(.vs, 1, &uniform_range)
		}
		gfx.apply_uniforms(.fs, 1, &uniform_range)
		if cell_backgrounds != unsafe { nil } {
			// The shader reads the variable-length grid from Metal buffer two,
			// outside Sokol's storage buffer slots.
			macos.metal_encoder_set_buffer(encoder, cell_backgrounds, 2)
		}
		gfx.draw(0, int(step.draw.vertex_count), int(step.draw.instance_count))
	}
}
