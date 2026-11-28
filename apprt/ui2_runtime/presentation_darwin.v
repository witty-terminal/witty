module ui2_runtime

import apprt
import renderer
import sokol.gfx
import ui2

struct PanePresentation {
mut:
	texture voidptr
	image gfx.Image
	direct bool
}

fn (p PanePresentation) deinit() {
	if p.image.id != 0 {
		gfx.destroy_image(p.image)
	}
}

fn (mut pane Pane) enable_presentation() {}

fn (mut tab Tab) release_presentation() {
	renderer.wait_for_ui2_metal_readers()
	mut iterator := tab.tree.iterator()
	for {
		entry := iterator.next() or { break }
		mut pane := unsafe { entry.view }
		pane.release_presentation()
	}
}

fn (mut pane Pane) release_presentation() {
	pane.clear_presentation()
	pane.surface.renderer.release_ui2_metal_targets()
}

fn (mut pane Pane) destroy_presentation() {
	renderer.wait_for_ui2_metal_readers()
	pane.clear_presentation()
}

fn (mut pane Pane) clear_presentation() {
	ui2.clear_surface_image(pane.element_id())
	pane.presentation.deinit()
	pane.presentation = PanePresentation{}
}

fn render_window_pane(id string, scale f64, swapchain gfx.Swapchain) ui2.WindowSurfaceResult {
	mut app := g_app
	if app.screenshot != '' || app.runtime.config.background_opacity < 1
		|| swapchain.color_format != .bgra8 || swapchain.sample_count != 1
		|| swapchain.metal.current_drawable == unsafe { nil } {
		return .unhandled
	}
	mut pane := app.active_pane() or { return .unhandled }
	if pane.element_id() != id { return .unhandled }
	texture := renderer.ui2_metal_drawable_texture(swapchain)
	if texture == unsafe { nil } { return .retry }
	size := apprt.SurfaceSize{ width: u32(swapchain.width), height: u32(swapchain.height) }
	prepare_pane_size(mut pane, size, scale) or {
		app.failure = err
		quit_window()
		return .retry
	}
	renderer.wait_for_ui2_metal_readers()
	drawn := pane.surface.renderer.draw_ui2_metal_window(texture, size.width, size.height,
		swapchain.metal.current_drawable, app.window_compute_overlay(pane, scale)) or {
		app.failure = err
		quit_window()
		return .retry
	}
	if drawn == .unhandled { return .unhandled }
	if drawn == .retry { return .retry }
	if !pane.presentation.direct {
		pane.release_presentation()
		pane.presentation.direct = true
	}
	return if drawn == .presented { .presented } else { .drawn }
}

// Render the optional scroll thumb with the terminal. Widget scenes use UI2's regular pass.
fn (app &App) window_compute_overlay(pane &Pane, scale f64) ?renderer.WindowComputeOverlay {
	$if show_fps ? { return none }
	if app.dialog != none || app.context_menu != none || app.palette || app.toast != ''
		|| pane.readonly || pane.progress != none || pane.search {
		return none
	}
	mut overlay := renderer.WindowComputeOverlay{}
	if app.runtime.config.scrollbar != .never {
		if rect := pane.scrollbar_frame() {
			mut points := []f64{cap: 32}
			ui2.window_solid_outline(mut points, rect, scrollbar_box.radius, scale)
			overlay.count = u32(points.len / 2)
			if overlay.count > u32(overlay.points.len) { return none }
			color := scrollbar_box.bg
			overlay.color = [f32((color >> 16) & 0xff) / 255, f32((color >> 8) & 0xff) / 255,
				f32(color & 0xff) / 255, f32(1)]!
			overlay.bounds = [f32(rect.x * scale), f32(rect.y * scale),
				f32((rect.x + rect.width) * scale), f32((rect.y + rect.height) * scale)]!
			for i in 0 .. int(overlay.count) {
				overlay.points[i] = [f32(points[i * 2] * scale), f32(points[i * 2 + 1] * scale)]!
			}
		}
	}
	return overlay
}


fn prepare_draw(_ apprt.SurfaceSize) ! {
	renderer.wait_for_ui2_metal_readers()
}

fn restore_ui_state() {}

fn (mut pane Pane) present() !bool {
	target := pane.surface.renderer.ui2_metal_target()
	if target.texture == unsafe { nil } { return false }
	if pane.presentation.texture != target.texture {
		image := renderer.import_ui2_metal_target(target)!
		pane.presentation.deinit()
		pane.presentation = PanePresentation{ texture: target.texture, image: image }
	}
	ui2.set_surface_image(pane.element_id(), pane.presentation.image.id, int(target.width), int(target.height))
	return true
}

fn (mut pane Pane) capture(path string) ! {
	pane.surface.renderer.screenshot_png(path)!
}
