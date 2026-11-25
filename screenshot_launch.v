module main

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
