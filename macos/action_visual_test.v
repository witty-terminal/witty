module macos

import os

#insert "@VMODROOT/macos/canvas_overlay_test_bridge.h"

fn C.witty_overlay_test_tile(layer ObjId) u32
fn C.witty_overlay_test_png(view ObjId) ObjId

fn test_source_native_visual_layers_and_cursor_consumers() {
	app_init()
	view := create_window(640, 480, 'visuals')
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	defer {
		surface.deinit()
		close_tab(view)
	}
	surface.set_key_table(0, 'first')
	surface.set_key_sequence(true, '⌘K')
	assert surface.key_dots.len == 3
	assert msg_u64(msg_id(surface.key_badge, 'subviews'), 'count') >= 4
	assert surface.key_width > 0
	assert !is_nil(surface.pulse_timer)
	surface.bell_border = true
	surface.ring_bell()
	assert msg_rect(surface.bell_edges[0], 'frame').height == 3
	assert msg_rect(surface.bell_edges[2], 'frame').y == 3
	assert C.witty_overlay_test_tile(surface.bell_edges[0]) >> 24 == 127
	assert msg_f64(msg_id1(surface.bell_layer, 'valueForKey:', nsstring('opacity')), 'doubleValue') == 1
	surface.begin_key_down()
	assert msg_f64(msg_id1(surface.bell_layer, 'valueForKey:', nsstring('opacity')), 'doubleValue') == 0
	surface.set_progress(3, none)
	assert msg_f64(msg_id1(surface.progress_layer, 'animationForKey:', nsstring('bounce')), 'duration') == 1.2
	assert !msg_bool(surface.progress_track, 'isHidden')
	assert C.witty_overlay_test_tile(surface.progress_layer) >> 24 == 255
	assert C.witty_overlay_test_tile(surface.progress_track) >> 24 == 76
	assert objc_utf8_string(msg_id(surface.progress_view, 'accessibilityValue')) == 'Operation in progress'
	surface.set_progress(4, none)
	assert msg_rect(surface.progress_layer, 'frame').width == view_width(view)
	assert msg_bool(surface.progress_track, 'isHidden')
	assert objc_utf8_string(msg_id(surface.progress_view, 'accessibilityValue')) == '100 percent complete'
	surface.mouse_over_link('https://example.com/long/path')
	assert !is_nil(surface.hover_tracking)
	assert msg_u64(msg_id(surface.hover_label, 'cell'), 'lineBreakMode') == 5
	surface.presented()
	assert surface.highlighted
	assert !is_nil(msg_id(surface.highlight_radial, 'contents'))
	assert !is_nil(msg_id(surface.highlight_border, 'contents'))
	assert msg_f64(msg_id1(surface.highlight_mask, 'animationForKey:', nsstring('lineWidth')), 'duration') == 0.4
	msg_void(surface.highlight_timer, 'fire')
	assert !surface.highlighted
	set_cursor_shape(view, 8)
	assert msg_id(surface.scroll.scroll, 'documentCursor') == msg_id(get_class('NSCursor'), 'IBeamCursor')
	assert cursor_for_shape(4) == none
}

fn test_native_highlight_overlay_capture() {
	output := os.getenv_opt('WITTY_HIGHLIGHT_OVERLAY_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 103, 63)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
		nsstring('NSAppearanceNameDarkAqua')))
	view := create_offscreen_terminal_view(103, 63)
	msg_void1(window, 'setContentView:', view)
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	defer {
		surface.deinit()
		msg_void(window, 'close')
		msg_void(window, 'release')
		release_offscreen_terminal_view(view)
	}
	base := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(base, 'setWantsLayer:', true)
	msg_void1(msg_id(base, 'layer'), 'setBackgroundColor:', msg_id(native_color(0x161820, 1), 'CGColor'))
	C.witty_canvas_place_overlay(view, base, nil_obj())
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	msg_void(base, 'release')
	for i, name in ['small', 'medium', 'large'] {
		width := [103, 320, 1030][i]
		height := [63, 240, 800][i]
		msg_void_size(window, 'setContentSize:', objc_size(width, height))
		surface.scroll.layout()
		surface.resize()
		msg_void_rect(base, 'setFrame:', objc_rect(0, 0, width, height))
		surface.presented()
		for kind in ['full', 'glow', 'cleared'] {
			msg_void_bool(surface.highlight_shadows.last(), 'setHidden:', kind == 'glow')
			if kind == 'cleared' { msg_void(surface.highlight_timer, 'fire') }
			png := C.witty_overlay_test_png(surface.scroll.container)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(output, 'highlight-${kind}-${name}-witty.png')), ObjId(1))
		}
	}
}

struct NativeBellFixture {
	name string
	width f64 = 103
	height f64 = 63
	background u32 = 0x161820
}

fn test_native_bell_overlay_capture() {
	output := os.getenv_opt('WITTY_BELL_OVERLAY_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 103, 63)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(103, 63)
	msg_void1(window, 'setContentView:', view)
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	root := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void1(window, 'setContentView:', root)
	msg_void1(root, 'addSubview:', surface.scroll.container)
	msg_void(root, 'release')
	defer {
		surface.deinit()
		msg_void(window, 'close')
		msg_void(window, 'release')
		release_offscreen_terminal_view(view)
	}
	base := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(base, 'setWantsLayer:', true)
	C.witty_canvas_place_overlay(view, base, nil_obj())
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	msg_void(base, 'release')

	fixtures := [
		NativeBellFixture{name: 'lit-dark'},
		NativeBellFixture{name: 'cleared-dark'},
		NativeBellFixture{name: 'lit-light', width: 89, height: 41, background: 0xf9f3e5},
		NativeBellFixture{name: 'resized', width: 73, height: 27, background: 0x3a87c0},
		NativeBellFixture{name: 'narrow', width: 5, height: 19, background: 0x3a87c0},
		NativeBellFixture{name: 'short', width: 31, height: 4},
		NativeBellFixture{name: 'fractional', width: 81.5, height: 33.5},
		NativeBellFixture{name: 'disabled'},
	]
	for fixture in fixtures {
		surface.bell_border = fixture.name != 'disabled'
		surface.ring_bell()
		msg_void_size(window, 'setContentSize:', objc_size(fixture.width, fixture.height))
		pane := objc_rect(0, 0, fixture.width, fixture.height)
		msg_void_rect(surface.scroll.container, 'setFrame:', pane)
		surface.scroll.layout()
		surface.resize()
		msg_void_rect(base, 'setFrame:', pane)
		msg_void1(msg_id(base, 'layer'), 'setBackgroundColor:',
			msg_id(native_color(fixture.background, 1), 'CGColor'))
		if fixture.name == 'cleared-dark' { surface.begin_key_down() }
		png := C.witty_overlay_test_png(surface.scroll.container)
		assert !is_nil(png)
		assert msg_bool2(png, 'writeToFile:atomically:',
			nsstring(os.join_path(output, 'bell-${fixture.name}-witty.png')), ObjId(1))
	}
}

fn test_native_progress_overlay_capture() {
	output := os.getenv_opt('WITTY_PROGRESS_OVERLAY_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 101, 6)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(101, 6)
	msg_void1(window, 'setContentView:', view)
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	defer {
		surface.deinit()
		msg_void(window, 'close')
		msg_void(window, 'release')
		release_offscreen_terminal_view(view)
	}
	base := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(base, 'setWantsLayer:', true)
	msg_void1(msg_id(base, 'layer'), 'setBackgroundColor:', msg_id(native_color(0x161820, 1), 'CGColor'))
	C.witty_canvas_place_overlay(view, base, nil_obj())
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	msg_void(base, 'release')
	surface.scroll.layout()

	names := ['normal', 'error', 'paused', 'paused-partial', 'indeterminate', 'error-indeterminate', 'empty', 'edge']
	report_states := [1, 2, 4, 4, 3, 2, 1, 1]
	values := [37, 62, -1, 53, -1, -1, 0, 50]
	snapshots := ['light', 'dark']
	for i, appearance_name in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance_name)))
		for index, name in names {
			surface.set_progress(0, none)
			value := values[index]
			surface.set_progress(report_states[index], if value < 0 { none } else { ?u8(u8(value)) })
			png := C.witty_overlay_test_png(surface.scroll.container)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(output, '${snapshots[i]}-${name}-witty.png')), ObjId(1))
		}
	}
}
