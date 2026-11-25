module renderer

import opengl

pub struct ScreenshotFrame {
pub:
	width  int
	height int
	rgba   []u8
}

// screenshot_frame reads the completed target, including custom shader passes.
// The caller must make the surface's GL context current.
pub fn (mut r Renderer) screenshot_frame() !ScreenshotFrame {
	r.draw_mutex.lock()
	defer { r.draw_mutex.unlock() }
	target := r.api.last_target or { return error('no completed terminal frame') }
	width, height := int(target.width), int(target.height)
	pixels := opengl.Framebuffer{ id: target.fbo }.read_rgba8(u32(target.width),
		u32(target.height))!
	data := unsafe { &u8(pixels.data) }

	stride := width * 4
	row := []u8{len: stride}
	for y in 0 .. height / 2 {
		bottom := y * stride
		top := (height - y - 1) * stride
		unsafe {
			vmemcpy(row.data, data + bottom, stride)
			vmemcpy(data + bottom, data + top, stride)
			vmemcpy(data + top, row.data, stride)
		}
	}
	return ScreenshotFrame{ width: width, height: height, rgba: pixels }
}
