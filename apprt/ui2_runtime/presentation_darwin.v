module ui2_runtime

import apprt
import renderer
import sokol.gfx
import ui2

struct PanePresentation {
mut:
	texture voidptr
	image gfx.Image
}

fn (p PanePresentation) deinit() {
	if p.image.id != 0 {
		gfx.destroy_image(p.image)
	}
}

fn (mut pane Pane) enable_presentation() {}

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
