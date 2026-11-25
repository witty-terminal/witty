module macos

import os

#insert "@VMODROOT/macos/canvas_overlay_test_bridge.h"

fn C.witty_overlay_test_png(view ObjId) ObjId

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
	surface.toggle_command_palette([]NativeCommandOption{})
	assert surface.palette == unsafe { nil }
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
	names := ['plain', 'selected', 'hover', 'swatch', 'update', 'update-selected']
	options := [
		NativeCommandOption{ title: 'Copy Selection' },
		NativeCommandOption{ title: 'Reload Configuration', subtitle: 'Apply the configuration file' },
		NativeCommandOption{ title: 'Split Right', description: 'Open a terminal in a new split' },
		NativeCommandOption{ title: 'Ocean', leading_color: voidptr(C.witty_macos_color_rgba(0.25, 0.57, 0.82, 1)) },
		update,
		update,
	]
	for i, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		mode := if i == 0 { 'light' } else { 'dark' }
		for j, option in options {
			palette := &NativeCommandPalette{
				filtered: [option]
				selected: if j in [1, 5] { ?uint(uint(0)) } else { none }
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
