module renderer

import macos

// Capture at device resolution after the final pass, including any custom shader.
// Hold the draw mutex through readback so the swap chain cannot reuse the target.
pub fn (mut self Renderer) screenshot_png(path string) ! {
	$if renderer_opengl ? {
		return error('terminal screenshots require the Metal renderer on macOS')
	} $else {
		self.draw_mutex.lock()
		defer { self.draw_mutex.unlock() }
		mut width, mut height := self.api.surface_size()
		if self.api.layer == none {
			width = self.size.screen.width
			height = self.size.screen.height
		}
		if width == 0 || height == 0 {
			return error('terminal frame has no drawable size')
		}
		self.draw_frame_metal(true)!
		if self.health != .healthy {
			return error('terminal frame render failed')
		}
		macos.write_iosurface_png(self.frames[self.frame_index].target.surface, path)!
	}
}
