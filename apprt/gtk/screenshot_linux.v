module gtk

import time

fn C.gdk_memory_texture_new(width int, height int, format int, bytes GBytes, stride uint) voidptr
fn C.gdk_texture_save_to_png(texture voidptr, path &char) bool

pub struct ScreenshotOptions {
pub:
	path     string
	delay_ms i64
}

struct ScreenshotCapture {
	options ScreenshotOptions
mut:
	source      u32
	started_ms  i64
	first_frame ?i64
	complete    bool
	failure     ?IError
}

fn (mut app Application) start_screenshot_timer() {
	app.screenshot.started_ms = i64(time.sys_mono_now() / u64(time.millisecond))
	app.screenshot.source = C.g_timeout_add(16, voidptr(screenshot_tick), voidptr(app))
}

fn (mut app Application) stop_screenshot_timer() {
	if app.screenshot.source != 0 {
		C.g_source_remove(app.screenshot.source)
		app.screenshot.source = 0
	}
}

fn screenshot_tick(data voidptr) int {
	mut app := unsafe { &Application(data) }
	complete := app.capture_screenshot_when_ready() or {
		app.screenshot.failure = err
		true
	}
	if !complete {
		return 1
	}
	app.screenshot.source = 0
	app.screenshot.complete = true
	app.quit_now()
	return 0
}

fn (mut app Application) capture_screenshot_when_ready() !bool {
	now := i64(time.sys_mono_now() / u64(time.millisecond))
	mut surface := app.screenshot_surface() or {
		if now - app.screenshot.started_ms >= 10_000 {
			return error('terminal did not render a frame for the screenshot')
		}
		return false
	}
	if app.screenshot.first_frame == none {
		app.screenshot.first_frame = now
	}
	first_frame := app.screenshot.first_frame or { now }
	if now - first_frame < app.screenshot.options.delay_ms {
		return false
	}

	C.gtk_gl_area_make_current(surface.gl_area)
	gl_error := C.gtk_gl_area_get_error(surface.gl_area)
	if !isnil(gl_error) {
		return error(error_message(gl_error))
	}
	frame := surface.core_surface.renderer.screenshot_frame()!
	bytes := C.g_bytes_new(frame.rgba.data, uint(frame.rgba.len))
	defer { C.g_bytes_unref(bytes) }
	texture := C.gdk_memory_texture_new(frame.width, frame.height,
		C.GDK_MEMORY_R8G8B8A8_PREMULTIPLIED, bytes, uint(frame.width * 4))
	if isnil(texture) {
		return error('could not create screenshot texture')
	}
	defer { object_unref(GObject(texture)) }
	path := app.screenshot.options.path
	if !C.gdk_texture_save_to_png(texture, &char(path.str)) {
		return error('could not write screenshot to ${path}')
	}
	return true
}

fn (app &Application) screenshot_surface() ?&SurfaceWidget {
	if app.windows.len == 0 {
		return none
	}
	surface := app.windows[0].get_active_surface() or { return none }
	if !surface.has_core() || surface.core_surface.renderer.api.last_target == none {
		return none
	}
	return surface
}
