module main

import core
import witty_macos as macos
fn begin_screenshot(_ voidptr) {
	mut runtime := standalone_runtime()
	macos.native_undo_disable()
	defer { macos.native_undo_enable() }
	if !do_new_window(none) {
		eprintln('Witty screenshot: could not open the terminal')
		exit(1)
	}
	runtime.screenshot_surface = runtime.states.last()
	macos.dispatch_after(runtime.screenshot.delay, finish_screenshot, unsafe { nil })
}

fn is_screenshot_surface(state &TermState) bool {
	return state == standalone_runtime().screenshot_surface
}

fn finish_screenshot(_ voidptr) {
	mut runtime := standalone_runtime()
	mut state := runtime.screenshot_surface
	if state.closed || isnil(state.surface) {
		eprintln('Witty screenshot: terminal closed before capture')
		exit(1)
	}
	mut status := 0
	core.screenshot_png(state.surface.core(), runtime.screenshot.path) or {
		eprintln('Witty screenshot: ${err.msg()}')
		status = 1
	}
	close_one_controller(state.controller)
	exit(status)
}
