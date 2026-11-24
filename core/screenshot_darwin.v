module core

import apprt

// Captures the canonical core surface owned by the standalone AppKit host.
pub fn screenshot_png(surface &apprt.CoreSurface, path string) ! {
	if isnil(surface.backend) {
		return error('terminal surface is unavailable')
	}
	mut backend := unsafe { &EmbeddedSurfaceCore(surface.backend) }
	backend.surface.renderer.screenshot_png(path)!
}
