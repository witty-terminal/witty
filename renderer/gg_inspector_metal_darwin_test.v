module renderer

import cimgui
import font
import macos
import sokol.gfx

$if macos && !renderer_opengl ? {
	fn test_gg_metal_inspector_matches_native_draw_data() ! {
		device := macos.metal_system_default_device()
		if device == unsafe { nil } { return }
		mut gpu := GGInspectorMetal.acquire(device)
		assert gpu.acquired
		defer { gpu.release() }
		ctx := cimgui.Context.create()!
		defer { ctx.destroy() }
		ctx.inspector_setup(font.embedded_regular)
		queue := macos.metal_new_command_queue(device)
		assert queue != unsafe { nil }
		defer { macos.metal_release(queue) }
		assert ctx.metal_init(device)
		defer { ctx.metal_shutdown() }

		width, height := u32(640), u32(460)
		gg_target := macos.metal_new_texture(device, u64(MetalPixelFormat.bgra8unorm),
			width, height, 0, 4)
		native_target := macos.metal_new_texture(device, u64(MetalPixelFormat.bgra8unorm),
			width, height, 0, 4)
		assert gg_target != unsafe { nil } && native_target != unsafe { nil }
		defer {
			macos.metal_release(native_target)
			macos.metal_release(gg_target)
		}
		gg_pass := macos.metal_render_pass_descriptor()
		native_pass := macos.metal_render_pass_descriptor()
		green_gray := [40.0 / 255, 44.0 / 255, 52.0 / 255, 1.0]!
		macos.metal_render_pass_set_attachment(gg_pass, 0, gg_target, green_gray)
		macos.metal_render_pass_set_attachment(native_pass, 0, native_target, green_gray)

		ctx.set_size(width, height)
		for iteration in 0 .. 3 {
			ctx.metal_new_frame(native_pass)
			ctx.begin_frame(1.0 / 60)
			if ctx.begin_window('Terminal inspector') {
				ctx.text('Viewport and scrollback')
				ctx.text_colored(cimgui.Color{ r: 0.46, g: 0.71, b: 0.35, a: 0.60 }, 'Attributes')
				if ctx.begin_table('cells', 2, 0) {
					for row in 0 .. 5 + iteration {
						ctx.table_next_row()
						ctx.table_set_column(0)
						ctx.text('Row ${row}')
						ctx.table_set_column(1)
						ctx.text('Ω · ░─▓')
					}
					ctx.end_table()
				}
			}
			ctx.end_window()
			if ctx.begin_window('Other pane') { ctx.text('Input') }
			ctx.end_window()
			ctx.render_frame()
		}
		assert ctx.draw_frame().lists >= 2
		gpu.render(ctx, gg_pass, unsafe { nil })!
		C.witty_gg_metal_lock()
		gfx.flush()
		C.witty_gg_metal_unlock()

		command := macos.metal_create_command_buffer(queue)
		assert command != unsafe { nil }
		macos.inspector_retain_fallback_frame(command, native_pass)
		ctx.metal_render(command, native_pass)
		macos.metal_command_buffer_commit(command)
		macos.metal_command_buffer_wait(command)
		assert macos.metal_command_buffer_status(command) == 4

		mut actual := []u8{len: int(width * height * 4)}
		mut expected := []u8{len: actual.len}
		macos.metal_texture_get_bytes(gg_target, mut actual, width * 4, 0, 0, width, height)
		macos.metal_texture_get_bytes(native_target, mut expected, width * 4, 0, 0, width, height)
		assert expected[0..4] == [u8(52), 44, 40, 255]
		assert expected.any(it > 100 && it < 255)
		assert actual == expected
	}
}
