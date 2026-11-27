module ui2_runtime

$if linux || windows {
	import apprt
	import opengl
	import renderer
	import sokol.gfx
	import stbi
	import ui2

	struct PanePresentation {}

	fn (p PanePresentation) deinit() {}

	fn initial_window_scale() f64 { return ui2.scale() }

	fn quit_window() { ui2.quit() }

	fn (mut pane Pane) enable_presentation() {
		pane.surface.renderer.api.texture_output = true
	}

	fn prepare_draw(size apprt.SurfaceSize) ! {
		opengl.viewport(0, 0, int(size.width), int(size.height))!
	}

	fn restore_ui_state() {
		$if linux {
			renderer.restore_ui2_opengl_state()
		} $else {
			gfx.reset_state_cache()
		}
	}

	fn (mut pane Pane) present() !bool {
		target := pane.surface.renderer.api.texture_target or { return false }
		ui2.set_gl_surface_texture(pane.element_id(), target.texture, int(target.width), int(target.height))
		return true
	}

	fn (mut pane Pane) capture(path string) ! {
		image := pane.surface.renderer.screenshot_frame()!
		stbi.stbi_write_png(path, image.width, image.height, 4, image.rgba.data, image.width * 4)!
	}
}
