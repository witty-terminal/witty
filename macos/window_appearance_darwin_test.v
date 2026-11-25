module macos

import math
import os

#insert "@VMODROOT/macos/canvas_overlay_test_bridge.h"

fn C.witty_overlay_test_srgb_tile_matches(layer ObjId, color ObjId) bool
fn C.witty_overlay_test_window_png(window ObjId) ObjId

struct NativeAppearanceColorCase {
	background      u32
	preferred       u32
	light           bool
	preferred_light bool
}

fn test_native_auto_appearance_and_ventura_chrome_use_source_colors() {
	app_init()
	// Source OSColor uses weighted luminance, not brightness averaged over RGB.
	cases := [
		NativeAppearanceColorCase{0x000000, 0xffffff, false, true},
		NativeAppearanceColorCase{0xffffff, 0x000000, true, false},
		NativeAppearanceColorCase{0x00ff00, 0xff00ff, true, false},
		NativeAppearanceColorCase{0xff00ff, 0x00ff00, false, true},
		NativeAppearanceColorCase{0x7f7f7f, 0x808080, false, true},
		NativeAppearanceColorCase{0x808080, 0x7f7f7f, true, false},
	]
	for style in [0, 2] {
		view := create_window(200, 120, 'source appearance colors')
		window := msg_id(view, 'window')
		assert msg_bool(window, 'isVisible')
		for i, color in cases {
			apply_native_window_config(view, NativeWindowConfig{
				titlebar_style: style
				theme:          0
				background:     color.background
			}, i == 0, color.preferred, 1, false)
			data := native_window_data(window) or { panic('native metadata missing') }
			// Ventura chrome follows focused surface config, independently of
			// its window appearance override from the preferred border color.
			assert data.light == color.light
			expected_light := if style == 2 { color.preferred_light } else { color.light }
			expected := if expected_light {
				'NSAppearanceNameAqua'
			} else {
				'NSAppearanceNameDarkAqua'
			}
			assert objc_utf8_string(msg_id(msg_id(window, 'appearance'), 'name')) == expected
		}
		// Ventura's preferred-color override also takes precedence over an
		// explicit light theme, while the ordinary window honors that theme.
		apply_native_window_config(view, NativeWindowConfig{
			titlebar_style: style
			theme:          2
			background:     0xffffff
		}, false, 0x000000, 1, false)
		data := native_window_data(window) or { panic('native metadata missing') }
		assert data.light
		expected := if style == 2 { 'NSAppearanceNameDarkAqua' } else { 'NSAppearanceNameAqua' }
		assert objc_utf8_string(msg_id(msg_id(window, 'appearance'), 'name')) == expected
		msg_void(window, 'close')
		msg_void(window, 'release')
	}
}

struct NativeDarkBackgroundCase {
	background   u32
	preferred    u32
	opacity      f64 = 1
	force_opaque bool
	very_dark    bool
}

fn test_ventura_dark_chrome_uses_actual_native_window_color() {
	app_init()
	msg_void(shared_app(), 'finishLaunching')
	view := create_window(320, 160, 'native window background')
	other := create_window(320, 160, 'native tab')
	window := msg_id(view, 'window')
	other_window := msg_id(other, 'window')
	defer {
		msg_void(window, 'close')
		msg_void(other_window, 'close')
		msg_void(window, 'release')
		msg_void(other_window, 'release')
	}
	for tab in [view, other] {
		// This regression exercises the pre-Tahoe Ventura class explicitly.
		tab_window := msg_id(tab, 'window')
		g_native_windows[u64(tab_window)] = &NativeWindowData{ window: tab_window }
		apply_native_window_config(tab, NativeWindowConfig{ titlebar_style: 2 }, true, 0, 1, false)
	}
	add_native_tab(view, other)
	msg_void1(window, 'makeKeyAndOrderFront:', nil_obj())
	group := msg_id(window, 'tabGroup')
	assert !is_nil(group)
	msg_void_bool(group, 'setTabBarVisible:', true)
	msg_void1(msg_id(get_class('NSRunLoop'), 'currentRunLoop'), 'runUntilDate:', msg_id_f64(get_class('NSDate'),
		'dateWithTimeIntervalSinceNow:', 0.1))
	push_native_tabs(voidptr(window))
	assert msg_bool(group, 'isTabBarVisible')
	assert msg_id_u64(msg_id(group, 'windows'), 'objectAtIndex:', 0) == window
	mut data := native_window_data(window) or { panic('native metadata missing') }
	container := titlebar_container(window)
	assert !is_nil(container)
	// Ventura is a macOS 13–15 style. On newer AppKit, attach a native view
	// fixture when its tab accessory layout cannot create the backdrop. This
	// exercises the color branch in the real window without testing that layout.
	mut fixture_backdrop := nil_obj()
	mut fixture_overlay := nil_obj()
	if is_nil(data.backdrop) {
		fixture_backdrop = msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(0, 0, 78, 28))
		msg_void_bool(fixture_backdrop, 'setWantsLayer:', true)
		msg_void1(container, 'addSubview:', fixture_backdrop)
		fixture_overlay = msg_id(alloc('VTVibrantLayer'), 'init')
		msg_void1(msg_id(fixture_backdrop, 'layer'), 'addSublayer:', fixture_overlay)
		data.backdrop = fixture_backdrop
		data.backdrop_overlay = fixture_overlay
	}
	defer {
		if !is_nil(fixture_backdrop) {
			msg_void(fixture_backdrop, 'removeFromSuperview')
			msg_void(fixture_backdrop, 'release')
			msg_void(fixture_overlay, 'release')
		}
	}
	assert !is_nil(data.backdrop)
	assert native_color_object_luminance(nil_obj()) == 0
	assert math.abs(native_color_object_luminance(native_color(0x00ff00, 0)) - 0.587) < 0.000001
	cases := [
		NativeDarkBackgroundCase{
			background: 0x404040
			preferred:  0x000000
			very_dark:  true
		},
		NativeDarkBackgroundCase{
			background: 0x000000
			preferred:  0x404040
		},
		NativeDarkBackgroundCase{
			background: 0x000000
			preferred:  0x000000
			opacity:    0.5
		},
		NativeDarkBackgroundCase{
			background:   0x404040
			preferred:    0x000000
			opacity:      0.5
			force_opaque: true
			very_dark:    true
		},
		NativeDarkBackgroundCase{
			background: 0x000000
			preferred:  0x0c0c0c
			very_dark:  true
		},
		NativeDarkBackgroundCase{
			background: 0x000000
			preferred:  0x0d0d0d
		},
	]
	for color in cases {
		apply_native_window_config(view, NativeWindowConfig{
			titlebar_style: 2
			background:     color.background
			opacity:        color.opacity
		}, false, color.preferred, color.opacity, color.force_opaque)
		actual_background := msg_id(window, 'backgroundColor')
		transparent := color.opacity < 1 && !color.force_opaque
		expected_luminance := if transparent {
			f64(1)
		} else {
			native_color_luminance(color.preferred)
		}
		assert math.abs(native_color_object_luminance(actual_background) - expected_luminance) < 0.000001
		assert math.abs(msg_f64(actual_background, 'alphaComponent') - if transparent {
			0.001
		} else {
			1.0
		}) < 0.000001
		assert !data.light
		update_native_titlebar(window)
		expected_backdrop := if color.very_dark { actual_background } else { native_color(0, 0) }
		assert C.witty_overlay_test_srgb_tile_matches(data.buttons_fill.layer, expected_backdrop)
		expected_titlebar := if color.very_dark {
			msg_id_f64(data.titlebar_color, 'highlightWithLevel:', 0.14)
		} else {
			data.titlebar_color
		}
		assert C.witty_overlay_test_srgb_tile_matches(data.titlebar_fill.layer, expected_titlebar)
		assert msg_id(data.titlebar_fill.layer, 'superlayer') == msg_id(container, 'layer')
	}
	// preferredBackgroundColor clamps alpha in the source, including zero.
	apply_native_window_config(view, NativeWindowConfig{ titlebar_style: 2, opacity: 0 }, false,
		0x404040, 0, false)
	assert math.abs(msg_f64(data.titlebar_color, 'alphaComponent') - 0.001) < 0.000001
}

fn test_native_window_canvas_fill_reparents_and_keeps_its_tile() {
	app_init()
	first := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(0, 0, 240, 28))
	second := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(0, 0, 400, 32))
	mut fill := NativeWindowCanvasFill{}
	defer {
		fill.clear()
		msg_void(first, 'release')
		msg_void(second, 'release')
	}
	color := native_color(0x526d9a, 0.6)
	fill.update(first, color)
	tile := msg_id(fill.layer, 'contents')
	assert !is_nil(tile)
	fill.update(second, color)
	assert msg_id(fill.layer, 'contents') == tile
	assert msg_id(fill.layer, 'superlayer') == msg_id(second, 'layer')
	assert msg_rect(fill.layer, 'frame') == msg_rect(second, 'bounds')
	fill.update(second, nil_obj())
	assert is_nil(fill.layer)
}

fn test_native_window_canvas_fill_capture() {
	output := os.getenv_opt('WITTY_TITLEBAR_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 320, 110)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		objc_rect(80, 80, frame.width, frame.height), 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void_bool(window, 'setHasShadow:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	root := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void1(window, 'setContentView:', root)
	msg_void_bool(root, 'setWantsLayer:', true)
	msg_void1(msg_id(root, 'layer'), 'setBackgroundColor:', msg_id(native_color(0x566993, 1), 'CGColor'))
	// A second base color checks the same translucent fill across different backgrounds.
	underlay := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(160, 0, 160, frame.height))
	msg_void_bool(underlay, 'setWantsLayer:', true)
	msg_void1(msg_id(underlay, 'layer'), 'setBackgroundColor:', msg_id(native_color(0x9a8260, 1), 'CGColor'))
	msg_void1(root, 'addSubview:', underlay)
	msg_void(underlay, 'release')
	view := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(20, 39, 280, 32))
	msg_void_bool(view, 'setWantsLayer:', true)
	msg_void1(root, 'addSubview:', view)
	mut fill := NativeWindowCanvasFill{}
	defer {
		fill.clear()
		msg_void(window, 'close')
		msg_void(window, 'release')
		msg_void(view, 'release')
		msg_void(root, 'release')
	}

	// Use the native layer colors from the Ghostty titlebar styles as references.
	names := ['opaque', 'translucent', 'very-dark', 'dark-buttons', 'light-buttons', 'clear']
	colors := [
		native_color(0x224466, 1),
		native_color(0x224466, 0.5),
		msg_id_f64(native_color(0x0c0c0c, 1), 'highlightWithLevel:', 0.14),
		native_color(0, 0.45),
		C.witty_canvas_gamma22_gray(0.95),
		native_color(0, 0),
	]
	for i, name in names {
		fill.clear()
		color := colors[i]
		msg_void1(msg_id(view, 'layer'), 'setBackgroundColor:', msg_id(color, 'CGColor'))
		save_window_canvas_capture(window, output, '${name}-ghostty')
		fill.update(view, color)
		assert C.witty_overlay_test_srgb_tile_matches(fill.layer, color)
		save_window_canvas_capture(window, output, '${name}-witty')
	}
}

fn save_window_canvas_capture(window ObjId, output string, name string) {
	png := C.witty_overlay_test_window_png(window)
	assert !is_nil(png)
	assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output, name + '.png')),
		ObjId(1))
}
