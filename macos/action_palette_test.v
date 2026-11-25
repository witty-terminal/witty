module macos

import os
import input

#insert "@VMODROOT/macos/canvas_overlay_test_bridge.h"

fn C.witty_overlay_test_png(view ObjId) ObjId
fn C.witty_overlay_test_window_png(window ObjId) ObjId

fn test_native_palette_uses_localized_filter_and_source_title_order() {
	options := [NativeCommandOption{ title: 'Foo Bar: Two' }, NativeCommandOption{ title: 'Foo: One' },
		NativeCommandOption{
			title:    'Ångström'
			subtitle: 'Subdirectory'
		}, NativeCommandOption{ title: 'Colored', leading_color: voidptr(native_color(0xff0000, 1)) }]
	sorted := sorted_command_options(options)
	assert sorted.map(it.title).index('Foo: One') < sorted.map(it.title).index('Foo Bar: Two')
	assert filtered_command_options(sorted, 'ång')[0].title == 'Ångström'
	assert filtered_command_options(sorted, 'subdirectory')[0].title == 'Ångström'
	assert filtered_command_options(sorted, 'absent').len == 0
	assert palette_color_score(voidptr(native_color(0xff0000, 1)), 'red') > 0
	assert filtered_command_options(sorted, 'red')[0].title == 'Colored'
}

fn test_native_palette_ranks_initials_and_description_matches() {
	options := [
		NativeCommandOption{ title: 'Description', description: 'Open a red tab' },
		NativeCommandOption{ title: 'Subtitle', subtitle: 'red' },
		NativeCommandOption{ title: 'Reload Editor Defaults' },
		NativeCommandOption{ title: 'Red Tab' },
		NativeCommandOption{ title: 'Color', leading_color: voidptr(native_color(0xff0000, 1)) },
	]
	assert filtered_command_options(options, ' RED \n').map(it.title) == [
		'Color',
		'Reload Editor Defaults',
		'Red Tab',
		'Subtitle',
		'Description',
	]
	assert filtered_command_options(options, '   ').len == options.len

	text := nsstring('🌊 Édit 👩🏽‍💻 Terminal')
	matches := C.witty_palette_match_ranges(text, nsstring('e\u0301t'))
	assert msg_u64(matches, 'count') == 2
	first := C.witty_macos_msg_range(msg_id_u64(matches, 'objectAtIndex:', 0), sel('rangeValue'))
	assert first.location == 3 && first.length == 1
	emoji := C.witty_palette_match_ranges(text, nsstring('👩🏽‍💻'))
	range := C.witty_macos_msg_range(msg_id_u64(emoji, 'objectAtIndex:', 0), sel('rangeValue'))
	assert range.location == 8 && range.length == 7
	assert is_nil(C.witty_palette_match_ranges(text, nsstring('e\u0301z')))
}

fn test_native_palette_symbols_from_configured_triggers() {
	assert command_shortcut_symbols(input.Trigger.parse('ctrl+alt+shift+super+right')!) == [
		'⌃',
		'⌥',
		'⇧',
		'⌘',
		'▶',
	]
	assert command_shortcut_symbols(input.Trigger.parse('super+c')!) == ['⌘', 'C']
	assert command_shortcut_symbols(input.Trigger.parse('super+delete')!) == ['⌘', '⌦']
	assert command_shortcut_symbols(input.Trigger{ key: input.TriggerKeyCatchAll{} }).len == 0

	app_init()
	key := C.witty_macos_writing_key_equivalent(0, true)
	if !is_nil(key) {
		trigger := input.Trigger{ key: input.TriggerKeyPhysical{ key: .key_a }, mods: input.Mods.from_int(8) }
		assert command_shortcut_symbols(trigger) == ['⌘',
			objc_utf8_string(msg_id(key, 'uppercaseString'))]
	}
}

fn test_native_palette_edit_and_wrapping_selection_consumers() {
	app_init()
	view := create_window(640, 480, '')
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	defer {
		surface.deinit()
		close_tab(view)
	}
	surface.toggle_command_palette([
		NativeCommandOption{ title: 'One', subtitle: 'First command', leading_icon: 'shippingbox.fill', badge: '1.2', emphasis: true },
		NativeCommandOption{ title: 'Two' },
	])
	mut palette := surface.palette
	assert palette.selected == none
	assert msg_rect(palette.container, 'bounds').height == 249
	assert !is_nil(msg_id(palette.chrome.mask, 'contents'))
	assert !is_nil(msg_id(palette.chrome.shadow, 'contents'))
	assert !is_nil(msg_id(palette.chrome.shadow_mask, 'contents'))
	assert msg_rect(palette.chrome.shadow_mask, 'frame') == msg_rect(palette.chrome.shadow, 'bounds')
	assert msg_f64(palette.chrome.shadow, 'zPosition') > msg_f64(msg_id(palette.chrome.plate,
		'layer'), 'zPosition')
	if palette.chrome.native_backdrop {
		layers := msg_id(palette.chrome.material, 'sublayers')
		blur := msg_id_u64(layers, 'objectAtIndex:', 0)
		assert msg_u64(msg_id(blur, 'filters'), 'count') == 2
		assert msg_rect(blur, 'frame') == msg_rect(palette.chrome.plate, 'bounds')
		limit := msg_id_u64(layers, 'objectAtIndex:', 1)
		assert !is_nil(msg_id(limit, 'contents'))
	}
	reduced := msg_bool(msg_id(get_class('NSWorkspace'), 'sharedWorkspace'),
		'accessibilityDisplayShouldReduceTransparency')
	assert msg_bool(palette.chrome.material, 'isHidden') == reduced
	assert msg_bool(palette.chrome.opaque_material, 'isHidden') == !reduced
	assert msg_bool(palette.chrome.tint, 'isHidden') == reduced
	palette.chrome.set_reduce_transparency(!reduced)
	assert msg_bool(palette.chrome.material, 'isHidden') == !reduced
	assert msg_bool(palette.chrome.opaque_material, 'isHidden') == reduced
	assert msg_bool(palette.chrome.tint, 'isHidden') == !reduced
	msg_void2(palette_accessibility_center(), 'postNotificationName:object:',
		nsstring('NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification'), nil_obj())
	assert msg_bool(palette.chrome.material, 'isHidden') == reduced
	rows := msg_id(palette.document, 'subviews')
	first_row := msg_id_u64(rows, 'objectAtIndex:', 0)
	second_row := msg_id_u64(rows, 'objectAtIndex:', 1)
	assert msg_bool1(first_row, 'isKindOfClass:', get_class('WittyPaletteRow'))
	assert objc_utf8_string(msg_id(first_row, 'title')) == 'One'
	assert msg_rect(first_row, 'frame').height == 47
	assert msg_rect(second_row, 'frame').height == 32
	assert msg_rect(second_row, 'frame').y == 61
	assert palette_command(palette.owner, sel('control:textView:doCommandBySelector:'),
		palette.field, nil_obj(), sel('moveDown:'))
	assert (palette.selected or { uint(99) }) == 0
	palette_command(palette.owner, nil_obj(), palette.field, nil_obj(), sel('moveUp:'))
	assert (palette.selected or { uint(99) }) == 1
	assert msg_id_u64(msg_id(palette.document, 'subviews'), 'objectAtIndex:', 0) == first_row
	set_view_size(view, 416, 480)
	palette.layout()
	assert msg_rect(first_row, 'frame').width == msg_rect(palette.document, 'bounds').width - 20
	msg_void1(palette.field, 'setStringValue:', nsstring('one'))
	palette_edit(palette.owner, nil_obj(), nil_obj())
	assert palette.filtered.len == 1
	assert palette.filtered[0].title == 'One'
	msg_void1(palette.field, 'setStringValue:', nsstring('absent'))
	palette_edit(palette.owner, nil_obj(), nil_obj())
	assert palette.filtered.len == 0
	assert msg_rect(palette.scroll, 'frame').height == 48
	assert msg_rect(palette.container, 'bounds').height == 97
	surface.toggle_command_palette([]NativeCommandOption{})
	assert surface.palette == unsafe { nil }
}

fn test_native_palette_panel_capture() {
	output := os.getenv('WITTY_PALETTE_PANEL_OUTPUT')
	live := os.getenv('WITTY_PALETTE_LIVE_OUTPUT')
	if output.len == 0 && live.len == 0 { return }
	app_init()
	frame := objc_rect(0, 0, 680, 440)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		objc_rect(80, 80, frame.width, frame.height), 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void_bool(window, 'setHasShadow:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(680, 440)
	msg_void1(window, 'setContentView:', view)
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	base := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(base, 'setWantsLayer:', true)
	C.witty_canvas_place_overlay(view, base, nil_obj())
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	msg_void(base, 'release')
	defer {
		surface.deinit()
		msg_void(window, 'close')
		msg_void(window, 'release')
		release_offscreen_terminal_view(view)
	}
	options := [
		NativeCommandOption{ title: 'Copy Selection' },
		NativeCommandOption{ title: 'Reload Configuration', subtitle: 'Apply the configuration file' },
		NativeCommandOption{ title: 'Split Right', description: 'Open a terminal in a new split' },
	]
	for i, mode in ['dark', 'light'] {
		color := if i == 0 { u32(0x344d66) } else { u32(0xd6c9b0) }
		surface.visual_background = color
		msg_void1(msg_id(base, 'layer'), 'setBackgroundColor:', msg_id(native_color(color, 1), 'CGColor'))
		surface.toggle_command_palette(options)
		mut palette := surface.palette
		for j, name in ['panel', 'empty', 'single', 'terminal'] {
			if output.len == 0 { break }
			palette.options = match j {
				1 { []NativeCommandOption{} }
				2 { [options[0]] }
				else { options }
			}
			palette.rebuild()
			height := msg_rect(palette.container, 'bounds').height
			if name == 'terminal' {
				assert msg_rect(palette.container, 'frame').y == 46
			} else {
				msg_void_rect(palette.container, 'setFrame:', objc_rect(90, 80, 500, height))
			}
			png := C.witty_overlay_test_png(ObjId(view))
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output,
				'${mode}-${name}-witty.png')), ObjId(1))
		}
		if live.len > 0 {
			palette.options = options
			palette.rebuild()
			msg_void_rect(palette.container, 'setFrame:', objc_rect(90, 80, 500, 249))
			capture_palette_live(window, base, live, mode)
		}
		surface.toggle_command_palette([]NativeCommandOption{})
	}
}

fn capture_palette_live(window ObjId, base ObjId, output string, mode string) {
	for name in ['flat', 'stripes'] {
		if name == 'stripes' {
			bounds := msg_rect(base, 'bounds')
			for x := 0; x < int(bounds.width); x += 64 {
				stripe := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(x, 0, 32, bounds.height))
				msg_void_bool(stripe, 'setWantsLayer:', true)
				msg_void1(msg_id(stripe, 'layer'), 'setBackgroundColor:', msg_id(native_color(0x567bba, 1), 'CGColor'))
				msg_void1(base, 'addSubview:', stripe)
				msg_void(stripe, 'release')
			}
		}
		png := C.witty_overlay_test_window_png(window)
		assert !is_nil(png), 'Could not capture the compositor output of the palette fixture window'
		assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output,
			'${mode}-${name}-witty.png')), ObjId(1))
	}
	children := msg_id(base, 'subviews')
	for i := int(msg_u64(children, 'count')) - 1; i >= 0; i-- {
		msg_void(msg_id_u64(children, 'objectAtIndex:', u64(i)), 'removeFromSuperview')
	}
}

fn test_native_palette_row_capture() {
	output := os.getenv_opt('WITTY_PALETTE_ROW_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 504, 72)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(view, 'setWantsLayer:', true)
	background := C.witty_macos_color_rgba(0.2, 0.3, 0.4, 1)
	msg_void1(msg_id(view, 'layer'), 'setBackgroundColor:', msg_id(background, 'CGColor'))
	msg_void1(window, 'setContentView:', view)
	defer {
		msg_void(window, 'close')
		msg_void(window, 'release')
		msg_void(view, 'release')
	}
	update := NativeCommandOption{
		title:        'Update Available'
		subtitle:     'Download the latest version'
		leading_icon: 'shippingbox.fill'
		badge:        '1.4.0'
		emphasis:     true
	}
	names := ['plain', 'selected', 'hover', 'swatch', 'update', 'update-selected', 'title-match',
		'initials', 'description-match', 'unicode-match', 'shortcuts', 'shortcut-badge', 'badge-only']
	queries := ['', '', '', '', '', '', 'configuration', 'srt', 'config', 'cafe\u0301', '', 'up',
		'']
	options := [
		NativeCommandOption{ title: 'Copy Selection' },
		NativeCommandOption{ title: 'Reload Configuration', subtitle: 'Apply the configuration file' },
		NativeCommandOption{ title: 'Split Right', description: 'Open a terminal in a new split' },
		NativeCommandOption{ title: 'Ocean', leading_color: voidptr(C.witty_macos_color_rgba(0.25, 0.57, 0.82, 1)) },
		update,
		update,
		NativeCommandOption{ title: 'Reload Configuration', subtitle: 'Apply the configuration file' },
		NativeCommandOption{ title: 'Split Right Terminal', symbols: ['⌘', 'D'] },
		NativeCommandOption{ title: 'Reload', description: 'Apply the configuration file' },
		NativeCommandOption{ title: 'Ångström: Café 👩🏽‍💻' },
		NativeCommandOption{
			title:   'Focus Right Split'
			symbols: ['⌃', '⌥', '⇧', '⌘', '▶']
		},
		NativeCommandOption{
			title:        update.title
			subtitle:     update.subtitle
			leading_icon: update.leading_icon
			badge:        update.badge
			emphasis:     update.emphasis
			symbols:      ['⌘', '⏎']
		},
		NativeCommandOption{ title: 'Preview Badge', badge: '1.4.0', symbols: ['⌥', 'D'] },
	]
	for i, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		mode := if i == 0 { 'light' } else { 'dark' }
		for j, option in options {
			palette := &NativeCommandPalette{
				filtered: [option]
				query:    queries[j]
				selected: if j in [1, 5, 6, 7, 8, 9, 11] { ?uint(uint(0)) } else { none }
				hovered:  if j in [2, 5] { ?uint(uint(0)) } else { none }
			}
			height := option.row_height()
			row := new_palette_row(palette, 0, objc_rect(12, frame.height - 12 - height, 480, height))
			msg_void1(view, 'addSubview:', row)
			png := C.witty_overlay_test_png(view)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output,
				'${mode}-${names[j]}-witty.png')), ObjId(1))
			C.macos_objc_set_ptr_ivar(row, cstr('palette'), unsafe { nil })
			msg_void(row, 'removeFromSuperview')
			msg_void(row, 'release')
		}
	}
}
