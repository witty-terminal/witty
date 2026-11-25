module renderer

import configpkg
import datastruct
import font
import macos
import sync

struct MetalFrameTestCapture {
mut:
	calls  int
	status u64
	sync_  bool
	done   &sync.Semaphore = unsafe { nil }
}

fn metal_frame_test_completion(renderer_ptr voidptr, target_ptr voidptr, status u64, sync_ bool) {
	mut capture := unsafe { &MetalFrameTestCapture(renderer_ptr) }
	assert target_ptr != unsafe { nil }
	capture.calls++
	capture.status = status
	capture.sync_ = sync_
	if capture.done != unsafe { nil } {
		capture.done.post()
	}
}

$if macos && !renderer_opengl ? {
	fn test_gg_metal_iosurface_passes_and_completion() ! {
		mut api := MetalAPI.init()!
		defer { api.deinit() }
		assert api.gg_owned
		mut sibling := MetalAPI.init()!
		assert sibling.gg_owned
		sibling.deinit()
		api.draw_frame_start()
		defer { api.draw_frame_end() }

		for blending in [configpkg.AlphaBlending.native, .linear_corrected] {
			api.blending = blending
			mut target := api.init_target(4, 4)!
			defer { target.deinit() }
			mut done := sync.new_semaphore()
			defer { done.destroy() }
			mut capture := MetalFrameTestCapture{ done: done }

			attachment := MetalRenderAttachmentTarget(target)
			mut abandoned := MetalFrame.begin_for_device(&api, voidptr(&capture), voidptr(&target),
				voidptr(metal_frame_test_completion))!
			first := abandoned.render_pass([MetalRenderPassAttachment{ target: attachment }])!
			first.complete()
			abandoned.cancel()
			assert capture.calls == 0

			mut frame := MetalFrame.begin_for_device(&api, voidptr(&capture), voidptr(&target),
				voidptr(metal_frame_test_completion))!
			defer { frame.cancel() }

			clear := frame.render_pass([
				MetalRenderPassAttachment{
					target:      attachment
					clear_color: [f64(1), 0, 0, 1]!
				},
			])!
			assert clear.gg
			clear.complete()
			load := frame.render_pass([MetalRenderPassAttachment{ target: attachment }])!
			wait := blending.is_linear()
			frame.submit(&load, wait)!
			done.wait()
			assert capture.calls == 1
			assert capture.sync_ == wait
			assert metal_command_buffer_status(capture.status) == .completed
			mut pixel := []u8{len: 4}
			macos.metal_texture_get_bytes(target.texture, mut pixel, 4, 0, 0, 1, 1)
			assert pixel == [u8(0), 0, 255, 255]
		}
	}
}

fn capture_metal_health_event(data voidptr, event SurfaceEvent, timeout datastruct.BlockingQueueTimeout) u32 {
	assert timeout.kind() == .forever
	mut events := unsafe { &[]Health(data) }
	if event is RendererHealthEvent {
		events << event.health
	}
	return u32(events.len)
}

$if renderer_metal ?|| ( ( macos || ios ) && !renderer_opengl ?) {
	fn test_renderer_metal_completion_callback_reports_buffer_health() {
		mut health_events := []Health{}
		mut render := Renderer{
			health:          .unhealthy
			surface_mailbox: SurfaceMailbox{
				user_data: voidptr(&health_events)
				push_fn:   capture_metal_health_event
			}
		}
		mut target := MetalTarget{}
		renderer_metal_frame_completed_callback(voidptr(&render), voidptr(&target), 4, false)
		assert render.health == .healthy
		renderer_metal_frame_completed_callback(voidptr(&render), voidptr(&target), 5, true)
		assert render.health == .unhealthy
		assert health_events == [.healthy, .unhealthy]
	}

	fn test_metal_render_step_counts_retain_source_pointer_width() {
		max_count := ~uint(0)
		buffer := MetalBuffer{
			opts: MetalBufferOptions{
				device:           unsafe { nil }
				resource_options: MetalResourceOptions.init(.write_combined, .shared, .default)
			}
			len:  max_count
		}
		target := MetalTarget{
			width:  max_count
			height: max_count
		}
		texture := MetalTexture{
			width:  max_count
			height: max_count
			bpp:    max_count
		}
		step := MetalRenderStep{
			pipeline: MetalPipeline{}
			draw:     MetalRenderDraw{
				draw_type:      .triangle
				vertex_count:   max_count
				instance_count: max_count
			}
		}
		assert buffer.len == max_count
		assert target.width == max_count
		assert target.height == max_count
		assert texture.width == max_count
		assert texture.height == max_count
		assert texture.bpp == max_count
		assert step.draw.vertex_count == max_count
		assert step.draw.instance_count == max_count
	}

	fn test_metal_pipeline_retains_every_source_attachment() {
		attachments := [
			MetalPipelineAttachment{
				pixel_format: .rgba8unorm
			},
			MetalPipelineAttachment{
				pixel_format:     .bgra8unorm_srgb
				blending_enabled: false
			},
		]
		assert attachments.len == 2
		assert attachments[0].blending_enabled
		assert !attachments[1].blending_enabled
		assert attachments[0].pixel_format == .rgba8unorm
		assert attachments[1].pixel_format == .bgra8unorm_srgb
	}

	fn test_metal_buffer_sync_writes_native_buffer() {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut buffer := MetalBuffer.init(api.buffer_options(), 2)!
		defer {
			buffer.deinit()
		}

		buffer.sync([u8(1), 2, 3, 4])!

		// Metal queries the native allocation on every sync, so Ghostty retains
		// the initialization length even when the underlying buffer grows.
		assert buffer.len == 2
		assert macos.metal_buffer_length(buffer.handle) == 8
		assert read_metal_buffer(buffer, 4) == [u8(1), 2, 3, 4]
	}

	fn test_metal_texture_initial_upload_and_replace_region() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut texture := MetalTexture.init(api.image_texture_options(.gray, false), 4, 4, [
			u8(0),
			1,
			2,
			3,
			4,
			5,
			6,
			7,
			8,
			9,
			10,
			11,
			12,
			13,
			14,
			15,
		])!
		defer {
			texture.deinit()
		}

		texture.replace_region(1, 1, 2, 2, [u8(90), 80, 70, 60])

		bytes := read_metal_texture(texture)
		assert bytes[0..4] == [u8(0), 1, 2, 3]
		assert bytes[5] == 90
		assert bytes[6] == 80
		assert bytes[9] == 70
		assert bytes[10] == 60
	}

	fn test_metal_buffer_init_fill_copies_data() {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut buffer := MetalBuffer.init_fill(api.buffer_options(), [u8(5), 6, 7])!
		defer {
			buffer.deinit()
		}

		assert buffer.len == 3
		assert macos.metal_buffer_length(buffer.handle) == 3
		assert read_metal_buffer(buffer, 3) == [u8(5), 6, 7]
	}

	fn test_metal_buffer_sync_within_capacity_leaves_tail() {
		// Preallocate a 4-element buffer, then sync fewer elements. The
		// remaining (untouched) bytes should not be reallocated away and the
		// capacity should be preserved. (Port of buffer.zig sync semantics.)
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut buffer := MetalBuffer.init_fill(api.buffer_options(), [u8(0), 0, 0, 0])!
		defer {
			buffer.deinit()
		}

		buffer.sync([u8(1), 2])!

		assert buffer.len == 4
		assert macos.metal_buffer_length(buffer.handle) == 4
		data := read_metal_buffer(buffer, 4)
		assert data[0] == 1
		assert data[1] == 2
		// Tail is left untouched (still zero from the initial allocation).
		assert data[2] == 0
		assert data[3] == 0
	}

	fn test_metal_texture_bpp_for_pixel_formats() {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		// r8unorm is 1 byte per pixel: a 2x2 texture is 4 bytes.
		mut gray := MetalTexture.init(api.image_texture_options(.gray, false), 2, 2, none)!
		defer {
			gray.deinit()
		}
		assert gray.bpp == 1

		// bgra8unorm is 4 bytes per pixel: a 2x2 texture is 16 bytes.
		mut color := MetalTexture.init(api.image_texture_options(.bgra, false), 2, 2, none)!
		defer {
			color.deinit()
		}
		assert color.bpp == 4
	}

	fn test_metal_texture_replace_region_respects_bpp() {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		// 2x2 bgra8unorm texture (4 bytes per pixel, row stride = 8 bytes).
		mut texture := MetalTexture.init(api.image_texture_options(.bgra, false), 2, 2, []u8{len: 16})!
		defer {
			texture.deinit()
		}

		// Replace the single pixel at (1, 1) with 4 bytes.
		texture.replace_region(1, 1, 1, 1, [u8(11), 22, 33, 44])

		// Pixel (1, 1) lives at offset 1*8 + 1*4 = 12.
		data := read_metal_texture(texture)
		assert data[12] == 11
		assert data[13] == 22
		assert data[14] == 33
		assert data[15] == 44
		// Other pixels untouched.
		assert data[0] == 0
		assert data[11] == 0
	}

	fn read_metal_buffer(buffer MetalBuffer, len int) []u8 {
		mut result := []u8{len: len}
		if len > 0 {
			ptr := macos.metal_buffer_contents(buffer.handle)
			assert ptr != unsafe { nil }
			unsafe { vmemcpy(result.data, ptr, len) }
		}
		return result
	}

	fn read_metal_texture(texture MetalTexture) []u8 {
		mut result := []u8{len: int(texture.width * texture.height * texture.bpp)}
		macos.metal_texture_get_bytes(texture.handle, mut result, uint(texture.width * texture.bpp), 0, 0, uint(texture.width), uint(texture.height))
		return result
	}

	fn test_metal_sampler_target_and_empty_frame() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}

		mut sampler := MetalSampler.init(api.sampler_options())!
		defer {
			sampler.deinit()
		}
		assert sampler.handle != unsafe { nil }

		mut target := api.init_target(8, 6)!
		defer {
			target.deinit()
		}
		assert target.surface.get_width() == 8
		assert target.surface.get_height() == 6
		assert target.texture != unsafe { nil }

		mut capture := MetalFrameTestCapture{}
		mut frame := MetalFrame.begin(api.queue, voidptr(&capture), voidptr(&target),
			voidptr(metal_frame_test_completion))!
		mut pass := frame.render_pass([MetalRenderPassAttachment{
			target:      MetalRenderAttachmentTarget(target)
			clear_color: [f64(0.25), 0.5, 0.75, 1.0]!
		}])!
		pass.complete()
		mut texture := MetalTexture.init(api.texture_options(), 8, 6, none)!
		defer {
			texture.deinit()
		}
		mut texture_pass := frame.render_pass([MetalRenderPassAttachment{
			target:      MetalRenderAttachmentTarget(texture)
			clear_color: [f64(0), 0, 0, 0]!
		}])!
		texture_pass.complete()
		frame.complete(true)
		assert capture.calls == 1
		assert metal_command_buffer_status(capture.status) == .completed
		assert capture.sync_

		mut async_capture := MetalFrameTestCapture{}
		mut async_frame := MetalFrame.begin(api.queue, voidptr(&async_capture), voidptr(&target),
			voidptr(metal_frame_test_completion))!
		async_frame.complete(false)
		macos.metal_command_buffer_wait(async_frame.command_buffer)
		assert async_capture.calls == 1
		assert metal_command_buffer_status(async_capture.status) == .completed
		assert !async_capture.sync_
	}

	fn test_metal_builtin_shader_pipelines_compile() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut shaders := MetalShaders.init(api.device, []string{}, .bgra8unorm)!
		assert shaders.library != unsafe { nil }
		assert shaders.bg_color.handle != unsafe { nil }
		assert shaders.cell_bg.handle != unsafe { nil }
		assert shaders.cell_text.handle != unsafe { nil }
		assert shaders.image.handle != unsafe { nil }
		assert shaders.bg_image.handle != unsafe { nil }
		assert $sizeof(CellText) == 32

		mut target := api.init_target(4, 4)!
		defer {
			target.deinit()
		}
		mut uniforms := MetalBuffer.init_fill(api.buffer_options(), [metal_uniforms(Uniforms{})])!
		defer {
			uniforms.deinit()
		}
		mut capture := MetalFrameTestCapture{}
		mut frame := MetalFrame.begin(api.queue, voidptr(&capture), voidptr(&target),
			voidptr(metal_frame_test_completion))!
		mut pass := frame.render_pass([MetalRenderPassAttachment{
			target:      MetalRenderAttachmentTarget(target)
			clear_color: [f64(0), 0, 0, 1]!
		}])!
		pass.step(MetalRenderStep{
			pipeline: shaders.bg_color
			uniforms: uniforms
			draw:     MetalRenderDraw{
				draw_type:    .triangle
				vertex_count: 3
			}
		})
		pass.complete()
		frame.complete(true)
		assert capture.calls == 1
		assert metal_command_buffer_status(capture.status) == .completed
		assert capture.sync_

		mut layer := MetalIOSurfaceLayer.init()!
		assert layer.layer != unsafe { nil }
		layer.set_surface_sync(target.surface)
		layer.release()
		shaders.deinit()
		// Ghostty deliberately makes shader teardown idempotent.
		shaders.deinit()
	}

	fn test_metal_text_cell_grayscale_no_flags() {
		cell := CellText{
			atlas:    .grayscale
			grid_pos: [u16(1), 2]!
		}

		assert u8(cell.atlas) == 0
		assert cell.bools.packed() == 0
		assert cell.grid_pos[0] == 1
		assert cell.grid_pos[1] == 2
	}

	fn test_metal_text_cell_keeps_color_atlas_flag() {
		cell := CellText{
			atlas:      .color
			bools:      cell_text_bools(true, true)
			grid_pos:   [u16(3), 4]!
			color:      [u8(10), 20, 30, 40]!
			glyph_pos:  [u32(5), 6]!
			glyph_size: [u32(7), 8]!
			bearings:   [i16(1), 2]!
		}

		assert u8(cell.atlas) == 1
		assert cell.bools.packed() == 3
		assert cell.grid_pos[0] == 3
		assert cell.grid_pos[1] == 4
	}

	fn test_metal_uniform_layout_matches_shader_abi() {
		assert $sizeof(MetalUniforms) == 144
		assert __offsetof(MetalUniforms, projection_matrix) == 0
		assert __offsetof(MetalUniforms, screen_size) == 64
		assert __offsetof(MetalUniforms, cell_size) == 72
		assert __offsetof(MetalUniforms, grid_size) == 80
		assert __offsetof(MetalUniforms, grid_padding) == 96
		assert __offsetof(MetalUniforms, padding_extend) == 112
		assert __offsetof(MetalUniforms, min_contrast) == 116
		assert __offsetof(MetalUniforms, cursor_pos) == 120
		assert __offsetof(MetalUniforms, cursor_color) == 124
		assert __offsetof(MetalUniforms, bg_color) == 128
		assert __offsetof(MetalUniforms, cursor_wide) == 132
		assert __offsetof(MetalUniforms, use_linear_correction) == 135
	}

	fn test_metal_uniform_and_background_flags_are_packed() {
		uniforms := metal_uniforms(Uniforms{
			padding_extend: PaddingExtend{
				left: true
				up:   true
			}
			bools:          UniformBools{
				cursor_wide:           true
				use_linear_correction: true
			}
		})
		assert uniforms.padding_extend == 5
		assert uniforms.cursor_wide == 1
		assert uniforms.use_linear_correction == 1

		background := BgImageBuffer{
			opacity: 0.5
			info:    bg_image_info(.br, .stretch, true)
		}
		assert background.opacity == 0.5
		assert background.info.packed() == u8(8 | (2 << 4) | (1 << 6))
	}

	fn test_metal_image_texture_options_translate_pixel_layout_and_color_space() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}

		gray := api.image_texture_options(.gray, false)
		assert gray.pixel_format == .r8unorm
		assert gray.usage.shader_read()
		assert !gray.usage.render_target()

		rgba := api.image_texture_options(.rgba, true)
		assert rgba.pixel_format == .rgba8unorm_srgb

		bgra := api.image_texture_options(.bgra, true)
		assert bgra.pixel_format == .bgra8unorm_srgb

		// Custom shader textures are chained, so they read and render.
		custom := api.texture_options()
		assert custom.pixel_format == api.target_pixel_format()
		assert custom.usage.shader_read()
		assert custom.usage.render_target()
	}

	fn test_metal_atlas_texture_options_match_atlas_layout() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}

		gray := api.atlas_texture_options(.grayscale)!
		assert gray.pixel_format == .r8unorm
		assert gray.usage.shader_read()
		assert !gray.usage.render_target()

		bgra := api.atlas_texture_options(.bgra)!
		assert bgra.pixel_format == .bgra8unorm_srgb

		if _ := api.atlas_texture_options(font.AtlasFormat.bgr) {
			assert false
		} else {
			assert err.msg().contains('unsupported')
		}
	}

	fn test_metal_draw_frame_brackets_an_autorelease_pool() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}

		assert api.autorelease_pool == none
		api.draw_frame_start()
		assert api.autorelease_pool != none
		api.draw_frame_end()
		assert api.autorelease_pool == none

		// Each frame gets its own pool.
		api.draw_frame_start()
		assert api.autorelease_pool != none
		api.draw_frame_end()
		assert api.autorelease_pool == none

		// Metal has no last target to re-present.
		api.present_last_target()!
	}

	fn test_metal_buffer_sync_from_array_lists_concatenates_rows() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut buffer := MetalBuffer.init(api.buffer_options(), 2)!
		defer {
			buffer.deinit()
		}

		// Empty lists are skipped, not padded, so the rows land back to back.
		lists := [
			[u8(1), 2],
			[]u8{},
			[u8(3)],
			[u8(4), 5, 6],
		]
		assert buffer.sync_from_array_lists(lists)! == 6
		assert read_metal_buffer(buffer, 6) == [u8(1), 2, 3, 4, 5, 6]

		// Growing reallocates to double the requirement.
		assert macos.metal_buffer_length(buffer.handle) == 12

		// A shorter sync leaves the tail untouched, as the source documents.
		assert buffer.sync_from_array_lists([[u8(9)]])! == 1
		assert read_metal_buffer(buffer, 6) == [u8(9), 2, 3, 4, 5, 6]

		// Syncing nothing is still valid and reports zero items.
		assert buffer.sync_from_array_lists([][]u8{})! == 0
	}

	fn test_metal_buffer_typed_growth_matches_source_expression() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}

		mut values_buffer := MetalBuffer.init(api.buffer_options(), uint($sizeof(u32)))!
		defer {
			values_buffer.deinit()
		}
		values_buffer.sync_values([u32(1), 2])!
		// req_bytes (8) * 2 * sizeof(u32) (4), exactly as Buffer(u32).sync.
		assert macos.metal_buffer_length(values_buffer.handle) == 64

		mut lists_buffer := MetalBuffer.init(api.buffer_options(), uint($sizeof(u32)))!
		defer {
			lists_buffer.deinit()
		}
		assert lists_buffer.sync_from_array_lists([[u32(1)], [u32(2)]])! == 2
		// syncFromArrayLists uses the same pinned growth expression.
		assert macos.metal_buffer_length(lists_buffer.handle) == 64
	}

	fn test_metal_api_without_layer_cannot_present() ! {
		// The off-screen API has no runtime surface, so the layer is absent and
		// every layer-driven operation is either a no-op or reports unavailable.
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		assert api.layer == none

		width, height := api.surface_size()
		assert width == 0
		assert height == 0

		mut target := api.init_target(4, 4)!
		defer {
			target.deinit()
		}
		if _ := api.present(&target, true) {
			assert false
		} else {
			assert err.msg().contains('presentation layer unavailable')
		}
	}

	fn test_metal_shaders_survive_a_broken_postprocess_shader() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}

		// A custom shader that does not compile must not block the built-in
		// pipelines; the whole postprocess set is discarded instead.
		mut shaders := api.init_shaders(['this is not valid metal shading language'])!
		defer {
			shaders.deinit()
		}
		assert shaders.post_pipelines.len == 0
		assert shaders.library != unsafe { nil }
		assert shaders.bg_color.handle != unsafe { nil }
		assert shaders.cell_text.handle != unsafe { nil }
		assert shaders.bg_image.handle != unsafe { nil }
	}
}
