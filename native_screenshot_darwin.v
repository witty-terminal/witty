module main

import core
import macos
import os
import strconv

struct ScreenshotLaunch {
	path  string
	delay f64 = 2
}

fn parse_screenshot_launch(args []string) !(ScreenshotLaunch, []string) {
	mut path := ''
	mut remaining := []string{cap: args.len}
	for i := 0; i < args.len; i++ {
		arg := args[i]
		if arg == '-e' {
			remaining << args[i..]
			break
		}
		if arg != '--screenshot' && !arg.starts_with('--screenshot=') {
			remaining << arg
			continue
		}
		if path != '' {
			return error('--screenshot may be specified once')
		}
		if arg == '--screenshot' {
			i++
			if i == args.len || args[i].starts_with('-') {
				return error('--screenshot requires a PNG output path')
			}
			path = args[i]
		} else {
			path = arg['--screenshot='.len..]
		}
		if path == '' {
			return error('--screenshot requires a PNG output path')
		}
	}
	if path == '' {
		return ScreenshotLaunch{}, remaining
	}
	value := os.getenv_opt('SCREENSHOT_SETTLE_SECONDS') or { '2' }
	delay := strconv.atof64(value) or { return error('invalid SCREENSHOT_SETTLE_SECONDS: ${value}') }
	// dispatch_after takes a signed 64-bit nanosecond offset.
	if !(delay >= 0 && delay < f64(max_i64) / 1e9) {
		return error('invalid SCREENSHOT_SETTLE_SECONDS: ${value}')
	}
	return ScreenshotLaunch{ path: os.abs_path(path), delay: delay }, remaining
}

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
