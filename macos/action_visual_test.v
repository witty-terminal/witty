module macos

import os
import math

#insert "@VMODROOT/macos/canvas_overlay_test_bridge.h"

fn C.witty_overlay_test_tile(layer ObjId) u32
fn C.witty_overlay_test_opacity(layer ObjId) f32
fn C.witty_overlay_test_fill_alpha(layer ObjId) f64
fn C.witty_overlay_test_has_16bit_coverage(layer ObjId) bool
fn C.witty_overlay_test_window_fill_matches(layer ObjId, color ObjId) bool
fn C.witty_overlay_test_png(view ObjId) ObjId
fn C.witty_overlay_test_window_png(window ObjId) ObjId
fn C.witty_overlay_test_current_window_png(window ObjId) ObjId
fn C.CACurrentMediaTime() f64

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
	material := msg_id(surface.key_material, 'layer')
	assert msg_bool(material, 'masksToBounds')
	assert msg_f64(material, 'cornerRadius') == 15.5
	assert !is_nil(msg_id(surface.key_shadow, 'contents'))
	surface.apply_key_phase(0)
	for i, dot in surface.key_dots {
		layer := msg_id(dot, 'layer')
		assert !is_nil(layer)
		assert !msg_bool(dot, 'isHidden')
		expected := 0.3 + 0.7 * ((math.sin(f64(i) * math.pi * 2 / 3) + 1) / 2)
		assert math.abs(f64(C.witty_overlay_test_opacity(layer)) - expected) < 0.001
	}
	assert surface.key_width > 0
	assert !is_nil(surface.pulse_timer)
	surface.bell_border = true
	surface.ring_bell()
	assert msg_rect(surface.bell_edges[0], 'frame').height == 3
	assert msg_rect(surface.bell_edges[2], 'frame').y == 3
	for edge in surface.bell_edges {
		assert C.witty_overlay_test_window_fill_matches(edge, native_color(0xffcc00, 0.5))
	}
	assert msg_f64(msg_id1(surface.bell_layer, 'valueForKey:', nsstring('opacity')), 'doubleValue') == 1
	surface.begin_key_down()
	assert msg_f64(msg_id1(surface.bell_layer, 'valueForKey:', nsstring('opacity')), 'doubleValue') == 0
	surface.set_progress(3, none)
	assert msg_f64(msg_id1(surface.progress_layer, 'animationForKey:', nsstring('bounce')), 'duration') == 1.2
	assert !msg_bool(surface.progress_track, 'isHidden')
	accent := msg_id(get_class('NSColor'), 'controlAccentColor')
	rgb := C.witty_canvas_resolve_srgb(surface.progress_view, accent)
	assert C.witty_overlay_test_window_fill_matches(surface.progress_layer, native_color(rgb, 1))
	assert is_nil(msg_id(surface.progress_track, 'contents'))
	assert math.abs(C.witty_overlay_test_fill_alpha(surface.progress_track) - 0.3) < 0.000001
	assert objc_utf8_string(msg_id(surface.progress_view, 'accessibilityValue')) == 'Operation in progress'
	surface.set_progress(4, none)
	assert msg_rect(surface.progress_layer, 'frame').width == view_width(view)
	assert msg_bool(surface.progress_track, 'isHidden')
	assert objc_utf8_string(msg_id(surface.progress_view, 'accessibilityValue')) == '100 percent complete'
	msg_void_bool(surface.secure_badge, 'setHidden:', false)
	surface.refresh_secure_visuals()
	assert !msg_bool(surface.secure_art, 'isHidden')
	assert !msg_bool(surface.secure_symbol, 'isHidden')
	assert !is_nil(msg_id(surface.secure_symbol, 'image'))
	assert msg_id(surface.secure_badge, 'target') == surface.owner
	assert !is_nil(msg_id(surface.secure_gradient, 'contents'))
	assert !is_nil(msg_id(msg_id(surface.secure_card, 'mask'), 'contents'))
	assert !is_nil(msg_id(surface.secure_outline, 'contents'))
	assert !is_nil(msg_id(msg_id(surface.secure_wash, 'mask'), 'contents'))
	rotation := msg_id1(surface.secure_gradient, 'animationForKey:', nsstring('secureRotation'))
	pulse := msg_id1(surface.secure_wash, 'animationForKey:', nsstring('secureOpacity'))
	assert msg_f64(rotation, 'duration') == 2
	assert !msg_bool(rotation, 'autoreverses')
	assert msg_f64(msg_id(rotation, 'toValue'), 'doubleValue') == -math.pi * 2
	assert msg_f64(pulse, 'duration') == 2
	assert msg_bool(pulse, 'autoreverses')
	assert msg_f64(msg_id(pulse, 'fromValue'), 'doubleValue') == 0.5
	assert msg_f64(msg_id(pulse, 'toValue'), 'doubleValue') == 1
	msg_void_bool(surface.secure_badge, 'setHidden:', true)
	surface.refresh_secure_visuals()
	assert msg_bool(surface.secure_art, 'isHidden')
	assert is_nil(msg_id1(surface.secure_gradient, 'animationForKey:', nsstring('secureRotation')))
	assert is_nil(msg_id1(surface.secure_wash, 'animationForKey:', nsstring('secureOpacity')))
	surface.mouse_over_link('https://example.com/long/path')
	assert !is_nil(surface.hover_tracking)
	assert C.witty_overlay_test_has_16bit_coverage(msg_id(surface.hover_background_layer, 'mask'))
	assert objc_utf8_string(msg_id(surface.hover_label, 'accessibilityValue')) == 'https://example.com/long/path'
	tracking := surface.hover_tracking
	assert msg_rect(surface.hover_label, 'frame').x == 0
	action_hover_entered(surface.owner, nil_obj(), nil_obj())
	frame := msg_rect(surface.hover_label, 'frame')
	assert frame.x + frame.width == view_width(view)
	assert surface.hover_tracking == tracking
	surface.mouse_over_link('')
	assert is_nil(surface.hover_tracking)
	assert msg_bool(surface.hover_label, 'isHidden')
	surface.presented()
	assert surface.highlighted
	assert C.witty_overlay_test_has_16bit_coverage(surface.highlight_radial)
	assert C.witty_overlay_test_has_16bit_coverage(surface.highlight_border)
	for i, edge in surface.highlight_edges {
		assert C.witty_overlay_test_tile(edge) == 0xffffffff
		key := if i < 2 { 'bounds.size.height' } else { 'bounds.size.width' }
		animation := msg_id1(edge, 'animationForKey:', nsstring(key))
		assert msg_f64(animation, 'duration') == 0.4
		assert msg_f64(msg_id(animation, 'fromValue'), 'doubleValue') == 2
		assert msg_f64(msg_id(animation, 'toValue'), 'doubleValue') == 4
	}
	msg_void(surface.highlight_timer, 'fire')
	assert !surface.highlighted
	surface.refresh()
	for i, edge in surface.highlight_edges {
		key := if i < 2 { 'bounds.size.height' } else { 'bounds.size.width' }
		fade := msg_id1(edge, 'animationForKey:', nsstring(key))
		assert msg_f64(fade, 'duration') == 0.4
		assert !msg_bool(fade, 'autoreverses')
		assert msg_f64(msg_id(fade, 'toValue'), 'doubleValue') == 2
	}
	for i, shadow in surface.highlight_shadows {
		fade := msg_id1(shadow, 'animationForKey:', nsstring('shadowRadius'))
		assert msg_f64(fade, 'duration') == 0.4
		assert !msg_bool(fade, 'autoreverses')
		assert msg_f64(msg_id(fade, 'toValue'), 'doubleValue') == if i == 0 { 8 } else { 16 }
	}
	set_cursor_shape(view, 8)
	assert msg_id(surface.scroll.scroll, 'documentCursor') == msg_id(get_class('NSCursor'), 'IBeamCursor')
	assert cursor_for_shape(4) == none
}

fn test_native_key_indicator_capture() {
	output := os.getenv('WITTY_KEY_INDICATOR_OUTPUT')
	live := os.getenv('WITTY_KEY_INDICATOR_LIVE_OUTPUT')
	if output.len == 0 && live.len == 0 { return }
	app_init()
	frame := objc_rect(0, 0, 260, 96)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void_bool(window, 'setHasShadow:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(260, 96)
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
	color := C.witty_macos_color_rgba(0.2, 0.3, 0.4, 1)
	msg_void1(msg_id(base, 'layer'), 'setBackgroundColor:', msg_id(color, 'CGColor'))
	C.witty_canvas_place_overlay(view, base, nil_obj())
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	msg_void(base, 'release')
	surface.scroll.layout()

	names := ['table', 'stack', 'sequence', 'combined']
	tables := [['first'], ['first', 'second'], []string{}, ['first']]
	keys := [[]string{}, []string{}, ['⌘K', 'C'], ['⌘K']]
	for m, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		mode := if m == 0 { 'light' } else { 'dark' }
		for index, name in names {
			surface.set_key_table(2, '')
			surface.set_key_sequence(false, '')
			for table in tables[index] { surface.set_key_table(0, table) }
			for key in keys[index] { surface.set_key_sequence(true, key) }
			if !is_nil(surface.pulse_timer) { msg_void(surface.pulse_timer, 'invalidate') }
			surface.apply_key_phase(0)
			badge := msg_rect(surface.key_badge, 'frame')
			assert badge.height == if keys[index].len > 0 { 31.0 } else { 28.0 }
			assert badge.y + badge.height == frame.height - 8
			filename := '${mode}-${name}-witty.png'
			if output.len > 0 {
				png := C.witty_overlay_test_png(surface.scroll.container)
				assert !is_nil(png)
				assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output, filename)), ObjId(1))
			}
			if live.len > 0 {
				png := C.witty_overlay_test_window_png(window)
				assert !is_nil(png)
				assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(live, filename)), ObjId(1))
			}
		}
	}
}

fn test_key_indicator_capsule_stroke_covers_straight_sides() {
	width := 148
	height := 56
	stroke := native_canvas_capsule_mask(width, height, 2, 1, 1)!
	assert stroke.pixels[12 * width] >> 24 == 0
	assert stroke.pixels[13 * width] >> 24 > 0 && stroke.pixels[13 * width] >> 24 < 255
	assert stroke.pixels[14 * width] >> 24 == 255
	assert stroke.pixels[14 * width + 1] >> 24 == 255
	assert stroke.pixels[14 * width + 2] >> 24 == 0
	assert stroke.pixels[15 * width - 1] >> 24 == 255
	assert stroke.pixels[(height - 15) * width] >> 24 == 255
}

fn test_key_indicator_keycap_stroke_has_continuous_outer_edges() {
	width := 60
	stroke := native_canvas_continuous_rect(width, 38, 2, 4, stroke: 0.5, fill_stroke: true)!
	for cross in [11, width - 12] {
		assert stroke.pixels[cross] >> 24 >= 250
		assert stroke.pixels[width + cross] >> 24 <= 5
	}
	for column in [0, width - 1] {
		assert stroke.pixels[11 * width + column] >> 24 >= 250
	}
}

fn test_readonly_badge_canvas_stroke_and_silhouette() {
	border := native_canvas_rounded_mask(197, 46, 12, style: .continuous, stroke: 3,
		opacity: 0.6)!
	mask := native_canvas_rounded_mask(197, 46, 12, style: .continuous)!
	assert mask.pixels[0] == 0
	assert mask.pixels[98] == 0xff000000
	assert border.pixels[98] >> 24 == 153
	assert border.pixels[2 * 197 + 98] == border.pixels[98]
	assert border.pixels[3 * 197 + 98] == 0
	assert border.pixels[23 * 197 + 98] == 0
	for row in 0 .. 46 {
		for column in 0 .. 197 {
			assert border.pixels[row * 197 + column] == border.pixels[(45 - row) * 197 + 196 - column]
		}
	}
}

fn test_native_readonly_badge_layout_and_capture() {
	output := os.getenv('WITTY_READONLY_BADGE_OUTPUT')
	app_init()
	frame := objc_rect(0, 0, 180, 64)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(180, 64)
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
	C.witty_canvas_place_overlay(view, base, nil_obj())
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	msg_void(base, 'release')
	surface.scroll.layout()

	assert msg_bool(surface.readonly_badge, 'isHidden')
	surface.set_readonly(true)
	assert !msg_bool(surface.readonly_badge, 'isHidden')
	badge := msg_rect(surface.readonly_badge, 'frame')
	assert badge.x + badge.width == frame.width - 8
	assert badge.y == 8 && badge.height == 23
	assert msg_id(surface.readonly_badge, 'target') == surface.owner
	assert msg_id(surface.readonly_badge, 'action') == sel('readonly:')
	assert !is_nil(msg_id(surface.readonly_material, 'maskImage'))
	if output.len > 0 {
		layer := msg_id(base, 'layer')
		for index, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
			msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
				nsstring(appearance)))
			mode := if index == 0 { 'light' } else { 'dark' }
			for name, rgb in {'blue': [0.2, 0.3, 0.4], 'plain': [0.085, 0.095, 0.125]} {
				color := C.witty_macos_color_rgba(rgb[0], rgb[1], rgb[2], 1)
				msg_void1(layer, 'setBackgroundColor:', msg_id(color, 'CGColor'))
				png := C.witty_overlay_test_png(surface.scroll.container)
				assert !is_nil(png)
				assert msg_bool2(png, 'writeToFile:atomically:',
					nsstring(os.join_path(output, '${mode}-${name}-witty.png')), ObjId(1))
			}
		}
	}
	surface.set_readonly(false)
	assert msg_bool(surface.readonly_badge, 'isHidden')
}

fn test_native_hover_banner_capture() {
	output := os.getenv('WITTY_HOVER_BANNER_OUTPUT')
	live := os.getenv('WITTY_HOVER_BANNER_LIVE_OUTPUT')
	if output.len == 0 && live.len == 0 { return }
	app_init()
	width := os.getenv('WITTY_HOVER_BANNER_WIDTH').int()
	window_width := if width > 0 { width } else { 240 }
	frame := objc_rect(0, 0, f64(window_width), 80)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(window_width, 80)
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
	color := C.witty_macos_color_rgba(0.2, 0.3, 0.4, 1)
	msg_void1(msg_id(base, 'layer'), 'setBackgroundColor:', msg_id(color, 'CGColor'))
	C.witty_canvas_place_overlay(view, base, nil_obj())
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	msg_void(base, 'release')
	surface.scroll.layout()

	names := ['short', 'long', 'unicode', 'file', 'emoji', 'emoji-sequences']
	urls := ['https://example.org/path', 'https://example.org/long/path/to/an/application/file.html',
		'https://example.org/é/東京', 'file:///private/tmp/../tmp/', 'https://x.test/🚀/😃',
		'https://x.test/👍🏽/🇯🇵']
	for m, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		mode := if m == 0 { 'light' } else { 'dark' }
		for i, url in urls {
			surface.mouse_over_link(url)
			for side in ['left', 'right'] {
				if side == 'left' {
					action_hover_exited(surface.owner, nil_obj(), nil_obj())
				} else {
					action_hover_entered(surface.owner, nil_obj(), nil_obj())
				}
				filename := '${mode}-${names[i]}-${side}-witty.png'
				if output.len > 0 {
					png := C.witty_overlay_test_png(surface.scroll.container)
					assert !is_nil(png)
					assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output, filename)), ObjId(1))
				}
				if live.len > 0 {
					png := C.witty_overlay_test_window_png(window)
					assert !is_nil(png)
					assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(live, filename)), ObjId(1))
				}
			}
		}
	}
}

fn test_hover_banner_clips_the_url_when_an_ellipsis_does_not_fit() {
	url := nsstring('https://example.org/path')
	mut width := 0.0
	line := C.witty_hover_line(url, 4, &width)
	assert !is_nil(line)
	defer { C.CFRelease(line) }
	assert width == 4
	assert hover_banner_width(22, width, 2) == 14
	assert hover_banner_width(15, 0, 2) == 8.5
}

fn test_hover_banner_middle_truncation_restores_prefix_when_both_ends_fit() {
	url := nsstring('https://example.org/long/path/to/an/application/file.html')
	mut width := 0.0
	line := C.witty_hover_line(url, 18, &width)
	assert !is_nil(line)
	defer { C.CFRelease(line) }
	assert math.abs(width - 10.384765625) < 0.001
	assert hover_banner_width(36, width, 2) == 20.5

	both := C.witty_hover_line(url, 24, &width)
	assert !is_nil(both)
	defer { C.CFRelease(both) }
	assert math.abs(width - 21.16943359375) < 0.001
	assert hover_banner_width(42, width, 2) == 31.5
}

fn test_hover_banner_middle_truncation_uses_remaining_suffix_width() {
	url := nsstring('https://example.org/path')
	mut width := 0.0
	line := C.witty_hover_line(url, 42, &width)
	assert !is_nil(line)
	defer { C.CFRelease(line) }
	assert math.abs(width - 41.919921875) < 0.001
	assert hover_banner_width(60, width, 2) == 52

	kerned := C.witty_hover_line(url, 112, &width)
	assert !is_nil(kerned)
	defer { C.CFRelease(kerned) }
	assert math.abs(width - 111.6806640625) < 0.001

	kerned_pair := C.witty_hover_line(url, 129.5, &width)
	assert !is_nil(kerned_pair)
	defer { C.CFRelease(kerned_pair) }
	assert math.abs(width - 129.3017578125) < 0.001
}

fn test_hover_banner_raster_mirroring_and_display_string() {
	assert hover_display_url('https://example.org/é/東京') == 'https://example.org/é/東京'
	assert hover_display_url('https://example.org/a\u202eb') == 'https://example.org/a\\u{202E}b'
	left := hover_canvas_mask(40, 52, 2, true)!
	right := hover_canvas_mask(40, 52, 2, false)!
	assert left.pixels[0] >> 24 == 0
	assert left.pixels[39] >> 24 == 255
	assert left.pixels[51 * 40] >> 24 == 255
	for row in 0 .. 52 {
		for column in 0 .. 40 {
			a := int(left.pixels[row * 40 + column] >> 24)
			b := int(right.pixels[row * 40 + 39 - column] >> 24)
			// Quartz rounds the circular outline independently in each direction.
			assert math.abs(a - b) <= 1
		}
	}
}

fn test_hover_banner_live_corner_coverage_near_straight_edge() {
	one := hover_corner_coverage(14, 14, 1, true, 0)
	two := hover_corner_coverage(28, 28, 2, true, 0)
	// The corner still covers part of the first row where it approaches the straight edge.
	assert math.round(one[12] * 255) == 249
	assert math.round(two[24] * 255) == 242
}

fn test_hover_banner_live_narrow_corner_keeps_its_radius() {
	full := hover_corner_coverage(28, 28, 2, true, 0)
	narrow := hover_corner_coverage(24, 28, 2, true, 0)
	assert narrow[6 * 24 + 4] == full[6 * 28 + 4]
	assert narrow[24 * 24] == full[24 * 28]
	assert narrow[13] == full[13]
}

fn test_hover_banner_live_corner_follows_backing_pixel_phase() {
	x_odd := hover_corner_coverage(28, 28, 2, true, 1)
	y_odd := hover_corner_coverage(28, 28, 2, true, 2)
	mirrored := hover_corner_coverage(28, 28, 2, false, 1)
	for row in 0 .. 28 {
		for column in 0 .. 28 {
			assert x_odd[row * 28 + column] == y_odd[column * 28 + row]
			assert x_odd[row * 28 + column] == mirrored[row * 28 + 27 - column]
		}
	}
	assert x_odd[12] > y_odd[12]
}

fn test_hover_banner_live_square_corners_follow_backing_pixel_phase() {
	mask := hover_background_mask(317, 53, 2, false, 10)
	assert mask.width == 30 && mask.height == 30
	assert mask.center == objc_rect(1.0 / 30, 1.0 / 30, 1.0 / 30, 1.0 / 30)
	bottom := (mask.height - 1) * mask.width
	assert mask.coverage[0] == 1
	assert mask.coverage[bottom + 1] == 1
	assert math.round(mask.coverage[bottom] * 255) == 253
	assert math.round(mask.coverage[mask.coverage.len - 1] * 255) == 190

	narrow := hover_background_mask(28, 24, 2, true, 4 | 8)
	assert narrow.width == 28 && narrow.height == 24
	assert narrow.center == objc_rect(0, 0, 1, 1)
	assert math.round(narrow.coverage[narrow.width - 1] * 255) == 253
}

fn test_secure_badge_outline_coverage_at_both_scales() {
	one := secure_outline_mask(35, 1)!
	two := secure_outline_mask(70, 2)!
	assert one.width == 37 && two.width == 72
	assert one.pixels[0] == 0 && two.pixels[0] == 0
	// At 1× the stroke straddles the card edge with two half-covered pixels.
	assert one.pixels[18] >> 24 == 128
	assert one.pixels[one.width + 18] >> 24 == 128
	assert one.pixels[2 * one.width + 18] == 0
	assert two.pixels[36] >> 24 == 255
	assert two.pixels[two.width + 36] >> 24 == 255
	assert two.pixels[2 * two.width + 36] == 0
}

fn test_native_secure_badge_capture() {
	output := os.getenv_opt('WITTY_SECURE_OVERLAY_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 61, 55)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(61, 55)
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
	names := ['light', 'dark']
	for index, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		msg_void1(window, 'setAppearance:',
			msg_id1(get_class('NSAppearance'), 'appearanceNamed:', nsstring(appearance)))
		msg_void_bool(surface.secure_badge, 'setHidden:', false)
		surface.refresh_secure_visuals()
		msg_void(surface.secure_gradient, 'removeAllAnimations')
		msg_void(surface.secure_wash, 'removeAllAnimations')
		for phase_index, phase in ['base', 'wash', 'initial', 'peak', 'quarter'] {
			opacity := [f32(0), 0.5, 0.5, 1, 0.625][phase_index]
			rotation := if phase == 'quarter' { -math.pi / 2 } else { 0.0 }
			msg_void_bool(surface.secure_symbol, 'setHidden:', phase_index < 2)
			C.witty_macos_msg_void_f32(surface.secure_wash, sel('setOpacity:'), opacity)
			msg_void2(surface.secure_gradient, 'setValue:forKeyPath:',
				msg_id_f64(get_class('NSNumber'), 'numberWithDouble:', rotation), nsstring('transform.rotation.z'))
			png := C.witty_overlay_test_png(surface.scroll.container)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(output, '${names[index]}-${phase}-witty.png')), ObjId(1))
		}
	}
}

fn test_native_highlight_overlay_capture() {
	output := os.getenv_opt('WITTY_HIGHLIGHT_OVERLAY_OUTPUT') or { return }
	window_output := os.getenv('WITTY_HIGHLIGHT_WINDOW_OUTPUT')
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
	fade_output := os.getenv('WITTY_HIGHLIGHT_FADE_OUTPUT')
	if fade_output != '' {
		assert !is_nil(C.witty_overlay_test_window_png(window))
		loop := msg_id(get_class('NSRunLoop'), 'currentRunLoop')
		start := C.CACurrentMediaTime()
		surface.presented()
		for ms in [200, 300, 360, 395, 420, 440, 470, 520, 600, 750, 850] {
			wait := f64(ms) / 1000 - (C.CACurrentMediaTime() - start)
			msg_void1(loop, 'runUntilDate:', msg_id_f64(get_class('NSDate'),
				'dateWithTimeIntervalSinceNow:', wait))
			png := C.witty_overlay_test_current_window_png(window)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(fade_output, 'witty-${ms}.png')), ObjId(1))
		}
	}
	for size_index, name in ['small', 'medium', 'large'] {
		width := [103, 320, 1030][size_index]
		height := [63, 240, 800][size_index]
		msg_void_size(window, 'setContentSize:', objc_size(width, height))
		surface.scroll.layout()
		surface.resize()
		msg_void_rect(base, 'setFrame:', objc_rect(0, 0, width, height))
		surface.highlighted = true
		surface.refresh_highlight()
		for layer in [surface.highlight_layer, ...surface.highlight_edges, ...surface.highlight_shadows] {
			msg_void(layer, 'removeAllAnimations')
		}
		for kind in ['full', 'glow', 'peak', 'cleared'] {
			msg_void_bool(surface.highlight_shadows.last(), 'setHidden:', kind == 'glow')
			if kind == 'peak' {
				positions := surface.highlight_edges.map(msg_point(it, 'position'))
				surface.layout_highlight_edges(objc_rect(0, 0, width, height), 4)
				for i, edge in surface.highlight_edges {
					assert msg_point(edge, 'position') == positions[i]
					bounds := msg_rect(edge, 'bounds')
					assert (if i < 2 { bounds.height } else { bounds.width }) == 4
				}
				for i, shadow in surface.highlight_shadows {
					msg_void_f64(shadow, 'setShadowRadius:', if i == 0 { 12 } else { 24 })
					C.witty_macos_msg_void_f32(shadow, sel('setShadowOpacity:'), if i == 0 { 0.8 } else { 0.5 })
				}
			}
			if kind == 'cleared' {
				surface.highlighted = false
				surface.refresh_highlight()
				msg_void(surface.highlight_layer, 'removeAllAnimations')
			}
			png := C.witty_overlay_test_png(surface.scroll.container)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(output, 'highlight-${kind}-${name}-witty.png')), ObjId(1))
			if window_output != '' {
				window_png := C.witty_overlay_test_window_png(window)
				assert !is_nil(window_png)
				assert msg_bool2(window_png, 'writeToFile:atomically:',
					nsstring(os.join_path(window_output, 'highlight-${kind}-${name}-witty.png')), ObjId(1))
			}
		}
		for i, shadow in surface.highlight_shadows {
			msg_void_f64(shadow, 'setShadowRadius:', if i == 0 { 8 } else { 16 })
			C.witty_macos_msg_void_f32(shadow, sel('setShadowOpacity:'), if i == 0 { 0.6 } else { 0.3 })
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
	window_output := os.getenv('WITTY_BELL_WINDOW_OUTPUT')
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
		if window_output != '' {
			window_png := C.witty_overlay_test_window_png(window)
			assert !is_nil(window_png)
			assert msg_bool2(window_png, 'writeToFile:atomically:',
				nsstring(os.join_path(window_output, 'bell-${fixture.name}-witty.png')), ObjId(1))
		}
	}
}

fn test_native_progress_overlay_capture() {
	output := os.getenv_opt('WITTY_PROGRESS_OVERLAY_OUTPUT') or { return }
	window_output := os.getenv('WITTY_PROGRESS_WINDOW_OUTPUT')
	motion_output := os.getenv('WITTY_PROGRESS_MOTION_OUTPUT')
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
			if window_output != '' {
				// Capture the model frame with the actual window compositor.
				surface.clear_progress_bounce()
				window_png := C.witty_overlay_test_window_png(window)
				assert !is_nil(window_png)
				assert msg_bool2(window_png, 'writeToFile:atomically:',
					nsstring(os.join_path(window_output, '${snapshots[i]}-${name}-witty.png')), ObjId(1))
			}
		}
	}
	value_output := os.getenv('WITTY_PROGRESS_VALUE_OUTPUT')
	if value_output != '' {
		capture_progress_value_motion(window, base, mut surface, value_output, false)
	}
	tint_output := os.getenv('WITTY_PROGRESS_TINT_OUTPUT')
	if tint_output != '' {
		capture_progress_value_motion(window, base, mut surface, tint_output, true)
	}
	if motion_output != '' {
		// Use a nonzero local clock so a resize can retain the original start.
		start := 1.0
		C.witty_macos_msg_void_f32(surface.progress_layer, sel('setSpeed:'), 0)
		for width in [96, 98, 101, 103] {
			surface.set_progress(0, none)
			msg_void_size(window, 'setContentSize:', objc_size(width, 6))
			msg_void_rect(base, 'setFrame:', objc_rect(0, 0, width, 6))
			surface.scroll.layout()
			surface.resize()
			msg_void_f64(surface.progress_layer, 'setTimeOffset:', start)
			surface.set_progress(3, none)
			for phase in 0 .. 9 {
				elapsed := progress_bounce_elapsed_fraction(f64(phase) / 8)
				msg_void_f64(surface.progress_layer, 'setTimeOffset:',
					start + elapsed * progress_bounce_duration)
				png := C.witty_overlay_test_window_png(window)
				assert !is_nil(png)
				assert msg_bool2(png, 'writeToFile:atomically:',
					nsstring(os.join_path(motion_output, '${width}-${phase}-witty.png')), ObjId(1))
			}
		}
		msg_void_f64(surface.progress_layer, 'setTimeOffset:', start + progress_bounce_duration / 2)
		msg_void_size(window, 'setContentSize:', objc_size(98, 6))
		msg_void_rect(base, 'setFrame:', objc_rect(0, 0, 98, 6))
		surface.scroll.layout()
		surface.resize()
		animation := msg_id1(surface.progress_layer, 'animationForKey:', nsstring('bounce'))
		assert msg_f64(animation, 'beginTime') == start
		for index, elapsed in [0.5, 2 - progress_bounce_elapsed_fraction(0.125)] {
			msg_void_f64(surface.progress_layer, 'setTimeOffset:',
				start + elapsed * progress_bounce_duration)
			label := if index == 0 { 'resized' } else { 'return' }
			png := C.witty_overlay_test_window_png(window)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(motion_output, '${label}-witty.png')), ObjId(1))
		}
	}
}

fn capture_progress_value_motion(window ObjId, base ObjId, mut surface NativeActionSurface, output string, with_tint bool) {
	loop := msg_id(get_class('NSRunLoop'), 'currentRunLoop')
	C.witty_macos_msg_void_f32(surface.progress_layer, sel('setSpeed:'), 0)
	modes := if with_tint {
		['red', 'orange', 'interrupt', 'retint', 'tint-only']
	} else {
		['increase', 'decrease', 'interrupt', 'empty', 'full', 'resize']
	}
	for mode in modes {
		surface.set_progress(0, none)
		msg_void_f64(surface.progress_layer, 'setTimeOffset:', 1)
		from := match mode {
			'decrease', 'empty' { u8(83) }
			'full' { u8(0) }
			else { u8(17) }
		}
		to := match mode {
			'decrease' { u8(17) }
			'tint-only' { u8(17) }
			'empty' { u8(0) }
			'full' { u8(100) }
			else { u8(83) }
		}
		report := if with_tint {
			if mode == 'orange' { 4 } else { 2 }
		} else {
			1
		}
		surface.set_progress(1, from)
		assert !is_nil(C.witty_overlay_test_window_png(window))
		surface.set_progress(report, to)
		for ms in [10, 30, 50, 70, 90, 110, 130, 150, 170, 190, 210, 230, 350] {
			if ms == 110 {
				msg_void_f64(surface.progress_layer, 'setTimeOffset:', 1.1)
				if mode == 'interrupt' {
					surface.set_progress(if with_tint { 4 } else { 1 }, u8(38))
				} else if mode == 'retint' {
					surface.set_progress(4, to)
				} else if mode == 'resize' {
					msg_void_size(window, 'setContentSize:', objc_size(126, 6))
					msg_void_rect(base, 'setFrame:', objc_rect(0, 0, 126, 6))
					surface.scroll.layout()
					surface.resize()
				}
			}
			msg_void_f64(surface.progress_layer, 'setTimeOffset:', 1 + f64(ms) / 1000)
			msg_void(get_class('CATransaction'), 'flush')
			msg_void1(loop, 'runUntilDate:', msg_id_f64(get_class('NSDate'),
				'dateWithTimeIntervalSinceNow:', 0.06))
			png := C.witty_overlay_test_current_window_png(window)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(output, '${mode}-${ms}.png')), ObjId(1))
		}
	}
	surface.set_progress(1, u8(53))
	msg_void_f64(surface.progress_layer, 'setTimeOffset:', 1.45)
	assert !is_nil(C.witty_overlay_test_window_png(window))
	presented := msg_id(surface.progress_layer, 'presentationLayer')
	assert !is_nil(presented)
	assert msg_rect(presented, 'frame').width != msg_rect(surface.progress_layer, 'frame').width
	if with_tint {
		assert !is_nil(msg_id1(surface.progress_layer, 'animationForKey:', nsstring('progressTint')))
	}
	surface.set_progress(3, none)
	keys := msg_id(surface.progress_layer, 'animationKeys')
	assert msg_u64(keys, 'count') == 1
	assert !is_nil(msg_id1(surface.progress_layer, 'animationForKey:', nsstring('bounce')))
	surface.set_progress(0, none)
	msg_void_size(window, 'setContentSize:', objc_size(101, 6))
	msg_void_rect(base, 'setFrame:', objc_rect(0, 0, 101, 6))
	surface.scroll.layout()
	surface.resize()
	msg_void_f64(surface.progress_layer, 'setTimeOffset:', 0)
	C.witty_macos_msg_void_f32(surface.progress_layer, sel('setSpeed:'), 1)
}

// Invert the ease-in-out curve so the captures correspond to known positions.
fn progress_bounce_elapsed_fraction(phase f64) f64 {
	if phase in [0.0, 0.5, 1.0] { return phase }
	mut low, mut high := 0.0, 1.0
	for _ in 0 .. 40 {
		t := (low + high) / 2
		if progress_curve_position(t) < phase {
			low = t
		} else {
			high = t
		}
	}
	return progress_curve_time((low + high) / 2)
}
