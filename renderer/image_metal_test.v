module renderer

// Image upload and drawing tests that need a Metal device.
import macos
import sokol.gfx

struct ImageMetalFrameCapture {
mut:
	calls  int
	status u64
	sync_  bool
}

fn image_metal_frame_completion(renderer_ptr voidptr, target_ptr voidptr, status u64, sync_ bool) {
	mut capture := unsafe { &ImageMetalFrameCapture(renderer_ptr) }
	assert target_ptr != unsafe { nil }
	capture.calls++
	capture.status = status
	capture.sync_ = sync_
}

// Test ImageRenderState upload removes unloading images.
$if renderer_metal ?|| ( ( macos || ios ) && !renderer_opengl ?) {
	fn test_image_render_state_upload_removes_unloading() {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut state := ImageRenderState.empty()
		state.images[1] = ImageEntry{
			image: ImageUnloadPending{}
		}
		state.images[2] = ImageEntry{
			image: ImageReady{}
		}
		result := state.upload(&api)
		assert result == true
		assert 1 !in state.images
		assert 2 in state.images
		state.deinit()
	}

	fn test_overlay_update_replaces_then_unloads_image() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut state := ImageRenderState.empty()
		mut overlay := Overlay.init(Size{ screen: ScreenSize{ width: 1, height: 1 } })!
		overlay.surface.clear(0x04010203)
		state.overlay_update(overlay)
		mut ready_entry := state.images[overlay_image_key] or { panic('missing overlay image') }
		ready_entry.image = ImageReady{}
		state.images[overlay_image_key] = ready_entry

		overlay.surface.clear(0x08050607)
		state.overlay_update(overlay)
		replaced := state.images[overlay_image_key] or { panic('missing replaced overlay') }
		assert replaced.image is ImageReplace
		assert state.overlay_placements.len == 1

		state.overlay_update(none)
		unloading := state.images[overlay_image_key] or { panic('missing unloading overlay') }
		assert unloading.image is ImageUnloadReplace
		assert state.overlay_placements.len == 0
		state.upload(&api)
		assert overlay_image_key !in state.images
	}

	fn test_image_upload_converts_bgr_to_rgba_texture() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		mut state := ImageRenderState.empty()
		defer {
			state.deinit()
		}
		state.images[3] = ImageEntry{
			image: ImagePending{
				pending: PendingImage{
					width:        2
					height:       1
					pixel_format: .bgr
					data:         [u8(1), 2, 3, 4, 5, 6]
				}
			}
		}
		assert state.upload(&api)
		entry := state.images[3] or { return error('missing uploaded image') }
		assert entry.image is ImageReady
		texture := (entry.image as ImageReady).texture
		assert texture.handle != unsafe { nil }
		mut bytes := []u8{len: 8}
		macos.metal_texture_get_bytes(texture.handle, mut bytes, 8, 0, 0, 2, 1)
		assert bytes == [u8(3), 2, 1, 255, 6, 5, 4, 255]
	}

	fn test_image_draw_encodes_gpu_placement() ! {
		mut api := MetalAPI.init()!
		defer {
			api.deinit()
		}
		api.draw_frame_start()
		defer { api.draw_frame_end() }
		mut shaders := api.init_shaders([]string{})!
		defer {
			shaders.deinit()
		}
		mut state := ImageRenderState.empty()
		defer {
			state.deinit()
		}
		state.images[7] = ImageEntry{
			image: ImagePending{
				pending: PendingImage{
					width:        1
					height:       1
					pixel_format: .rgba
					data:         [u8(255), 0, 0, 255]
				}
			}
		}
		state.kitty_placements << ImagePlacement{
			image_id:      KittyImageId{ id: 7 }
			width:         1
			height:        1
			source_width:  1
			source_height: 1
		}
		state.kitty_bg_end = 1
		assert state.upload(&api)

		mut target := api.init_target(4, 4)!
		defer {
			target.deinit()
		}
		mut uniforms := MetalBuffer.init_fill(api.buffer_options(), [
			metal_uniforms(Uniforms{
				projection_matrix: [f32(0.5), 0, 0, 0, 0, -0.5, 0, 0, 0, 0, 1, 0, -1, 1, 0, 1]!
				screen_size:       [f32(4), 4]!
				cell_size:         [f32(1), 1]!
				grid_size:         [u16(4), 4]!
				bg_color:          [u8(0), 0, 0, 255]!
				bools:             UniformBools{ use_display_p3: true }
			}),
		])!
		defer {
			uniforms.deinit()
		}
		mut colors := [][4]u8{len: 16}
		colors[1] = [u8(0), 255, 0, 255]!
		mut backgrounds := MetalBuffer.init_fill(api.buffer_options(), colors)!
		defer { backgrounds.deinit() }
		mut backdrop := MetalTexture.init(api.image_texture_options(.rgba, true), 1, 1,
			[u8(0), 0, 255, 255])!
		defer { backdrop.deinit() }
		mut backdrop_vertices := MetalBuffer.init_fill(api.buffer_options(), [
			BgImageBuffer{ info: bg_image_info(.br, .none_, true) },
		])!
		defer { backdrop_vertices.deinit() }
		// Exercise a native draw between GG draws, as with text and Kitty layers.
		native_background := MetalPipeline{ handle: shaders.bg_color.handle }
		$if macos && !renderer_opengl ? {
			assert shaders.bg_color.gg.pipeline.id != 0
			assert shaders.cell_bg.gg.pipeline.id != 0
			assert shaders.image.gg.pipeline.id != 0
			assert shaders.bg_image.gg.pipeline.id != 0
			gfx.enable_frame_stats()
		}
		defer {
			$if macos && !renderer_opengl ? {
				gfx.disable_frame_stats()
			}
		}
		mut capture := ImageMetalFrameCapture{}
		mut frame := MetalFrame.begin_for_device(&api, voidptr(&capture), voidptr(&target),
			voidptr(image_metal_frame_completion))!
		defer { frame.cancel() }
		mut pass := frame.render_pass([MetalRenderPassAttachment{
			target:      MetalRenderAttachmentTarget(target)
			clear_color: [f64(0), 0, 0, 1]!
		}])!
		quad := MetalRenderDraw{ draw_type: .triangle, vertex_count: 3 }
		pass.step(MetalRenderStep{
			pipeline: shaders.bg_color
			uniforms: uniforms
			draw:     quad
		})
		pass.step(MetalRenderStep{
			pipeline: native_background
			uniforms: uniforms
			draw:     quad
		})
		pass.step(MetalRenderStep{
			pipeline: shaders.bg_image
			uniforms: uniforms
			buffers:  [?MetalBuffer(backdrop_vertices)]
			textures: [?MetalTexture(backdrop)]
			draw:     quad
		})
		pass.step(MetalRenderStep{
			pipeline: shaders.cell_bg
			uniforms: uniforms
			buffers:  [?MetalBuffer(none), ?MetalBuffer(backgrounds)]
			draw:     quad
		})
		state.draw(&api, shaders.image, uniforms, mut pass, .kitty_below_bg)
		frame.submit(&pass, true)!
		assert capture.calls == 1
		assert metal_command_buffer_status(capture.status) == .completed
		assert capture.sync_
		mut pixels := []u8{len: 12}
		macos.metal_texture_get_bytes(target.texture, mut pixels, 12, 0, 0, 3, 1)
		assert pixels == [u8(0), 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255]
		$if macos && !renderer_opengl ? {
			assert gfx.query_frame_stats().num_draw == 4
		}
	}
}
