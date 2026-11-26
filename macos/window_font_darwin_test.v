@[has_globals]
module macos

import os

#insert "@VMODROOT/macos/window_font_test_abi.h"
#insert "@VMODROOT/macos/canvas_overlay_test_bridge.h"
fn C.witty_window_font_test_attribute(value ObjId, name ObjId) ObjId
fn C.witty_overlay_test_png(view ObjId) ObjId

fn C.object_setClass(object ObjId, cls ObjId) ObjId

fn font_fixture_fullscreen(_self ObjId, _cmd Sel) u64 { return u64(1 << 14) }
fn font_fixture_toolbar_name(_self ObjId, _cmd Sel) ObjId { return nsstring('NSToolbarFullScreenWindow') }
fn font_fixture_container_name(_self ObjId, _cmd Sel) ObjId { return nsstring('NSTitlebarContainerView') }
__global font_fixture_is_key = false
fn font_fixture_key_window(_self ObjId, _cmd Sel) bool { return font_fixture_is_key }

fn test_legacy_window_title_capture() {
	output := os.getenv_opt('WITTY_WINDOW_TITLE_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 180, 60)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	root := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(root, 'setWantsLayer:', true)
	msg_void1(window, 'setContentView:', root)
	msg_void1(msg_id(root, 'layer'), 'setBackgroundColor:',
		msg_id(native_color(0x566993, 1), 'CGColor'))
	mut data := &NativeWindowData{window: window}
	toolbar := create_terminal_toolbar(mut data)
	label := data.title_label
	msg_void1(root, 'addSubview:', label)
	msg_void_rect(label, 'setFrame:', objc_rect(40, 19, 100, 22))
	defer {
		g_toolbar_windows.delete(u64(toolbar))
		msg_void(toolbar, 'release')
		msg_void(label, 'release')
		msg_void(window, 'close')
		msg_void(window, 'release')
		msg_void(root, 'release')
	}
	titles := ['Witty test', 'Long title — café 日本語 👩‍💻', '', 'café 日本 👩‍💻']
	for i, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		mode := if i == 0 { 'light' } else { 'dark' }
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		for j, title in titles {
			msg_void1(label, 'setStringValue:', nsstring(title))
			msg_void_bool(label, 'setNeedsDisplay:', true)
			image := C.witty_overlay_test_png(root)
			assert !is_nil(image)
			assert msg_bool2(image, 'writeToFile:atomically:',
				nsstring(os.join_path(output, '${mode}-${j}.png')), ObjId(1))
		}
	}
}

fn test_source_window_title_font_and_native_tab_title_updates() {
	app_init()
	first := create_window(640, 480, 'first')
	second := new_tab(640, 480, 'second')
	defer { close_tab(first); close_tab(second) }
	window := msg_id(second, 'window')
	mut data := &NativeWindowData{ window: window, config: NativeWindowConfig{ titlebar_style: 2 } }
	g_native_windows[u64(window)] = data
	toolbar := create_terminal_toolbar(mut data)
	msg_void1(window, 'setToolbar:', toolbar)
	set_native_window_title_font(second, 'Menlo')
	font := window_title_font(window)
	assert !is_nil(font)
	assert msg_f64(font, 'pointSize') == msg_f64(get_class('NSFont'), 'systemFontSize')
	field := window_font_title_field(window)
	assert !is_nil(field)
	assert msg_id(field, 'font') == font
	assert msg_id(data.title_label, 'font') == font
	assert msg_u64(data.title_label, 'alignment') == C.witty_macos_text_alignment_center()
	assert !msg_bool(field, 'usesSingleLineMode')
	msg_void1(window, 'setTitle:', nsstring('changed title'))
	attributed := msg_id(msg_id(window, 'tab'), 'attributedTitle')
	assert objc_utf8_string(msg_id(attributed, 'string')) == 'changed title'
	assert C.witty_window_font_test_attribute(attributed, nsstring('NSFont')) == font
	assert C.witty_window_font_test_attribute(attributed, nsstring('NSColor')) == msg_id(get_class('NSColor'), if msg_bool(window, 'isKeyWindow') { 'labelColor' } else { 'secondaryLabelColor' })
	assert !msg_bool(field, 'usesSingleLineMode')
	set_native_window_title_font(second, 'ThisFontDoesNotExist_WittySourceAudit')
	assert is_nil(window_title_font(window))
	assert is_nil(msg_id(msg_id(window, 'tab'), 'attributedTitle'))
	expected := msg_id_f64(get_class('NSFont'), 'titleBarFontOfSize:', msg_f64(get_class('NSFont'), 'systemFontSize'))
	assert msg_id(field, 'font') == expected
	assert msg_id(data.title_label, 'font') == expected
	set_native_window_title_font(second, 'Menlo')
	set_native_window_title_font(second, none)
	assert is_nil(window_title_font(window))
	assert is_nil(msg_id(msg_id(window, 'tab'), 'attributedTitle'))
	assert msg_id(field, 'font') == expected
	// AppKit subclasses still call NSWindow's title setter exactly once.
	cls := C.macos_objc_allocate_class_pair(native_window_class(), cstr('WittyFontObservedWindow'), 0)
	add_method(cls, 'isKeyWindow', voidptr(font_fixture_key_window), 'B@:')
	C.macos_objc_register_class_pair(cls)
	probe := msg_id_rect_u64_u64_bool(msg_id(cls, 'alloc'), 'initWithContentRect:styleMask:backing:defer:', objc_rect(0, 0, 640, 480), ns_window_style_titled, ns_backing_store_buffered, false)
	msg_void1(probe, 'setTitle:', nsstring('subclass title'))
	assert objc_utf8_string(msg_id(probe, 'title')) == 'subclass title'
	C.macos_set_associated_object(probe, voidptr(&native_title_font_key), font, uint(1))
	g_native_windows[u64(probe)] = &NativeWindowData{window:probe,config:NativeWindowConfig{titlebar_style:2}}
	font_fixture_is_key = false
	refresh_native_window_title_attributes(probe)
	assert C.witty_window_font_test_attribute(msg_id(msg_id(probe, 'tab'), 'attributedTitle'), nsstring('NSColor')) == msg_id(get_class('NSColor'), 'secondaryLabelColor')
	font_fixture_is_key = true
	msg_void(probe,'becomeKeyWindow')
	assert C.witty_window_font_test_attribute(msg_id(msg_id(probe, 'tab'), 'attributedTitle'), nsstring('NSColor')) == msg_id(get_class('NSColor'), 'labelColor')
	font_fixture_is_key = false
	msg_void(probe,'resignKeyWindow')
	assert C.witty_window_font_test_attribute(msg_id(msg_id(probe, 'tab'), 'attributedTitle'), nsstring('NSColor')) == msg_id(get_class('NSColor'), 'secondaryLabelColor')
	g_native_windows.delete(u64(probe))
	msg_void(probe, 'release')
}

fn test_source_window_font_fullscreen_toolbar_parent_filter() {
	app_init()
	target_view := create_window(640, 480, 'target')
	other_view := create_window(640, 480, 'other')
	target := msg_id(target_view, 'window')
	other := msg_id(other_view, 'window')
	original_class := C.object_getClass(target)
	full := C.macos_objc_allocate_class_pair(original_class, cstr('WittyFontFullscreenStyleFixture'), 0)
	add_method(full, 'styleMask', voidptr(font_fixture_fullscreen), 'Q@:')
	C.macos_objc_register_class_pair(full)
	toolbar_class := C.macos_objc_allocate_class_pair(get_class('NSWindow'), cstr('WittyFontFullscreenToolbarFixture'), 0)
	add_method(toolbar_class, 'className', voidptr(font_fixture_toolbar_name), '@@:')
	C.macos_objc_register_class_pair(toolbar_class)
	container_class := C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyFontFullscreenContainerFixture'), 0)
	add_method(container_class, 'className', voidptr(font_fixture_container_name), '@@:')
	C.macos_objc_register_class_pair(container_class)
	toolbar := msg_id_rect_u64_u64_bool(msg_id(toolbar_class, 'alloc'), 'initWithContentRect:styleMask:backing:defer:', objc_rect(0, 0, 640, 40), 0, ns_backing_store_buffered, false)
	msg_void_bool(toolbar, 'setReleasedWhenClosed:', false)
	container := msg_id_rect(msg_id(container_class, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 640, 40))
	msg_void1(msg_id(toolbar, 'contentView'), 'addSubview:', container)
	defer {
		C.object_setClass(target, original_class)
		msg_void1(target, 'removeChildWindow:', toolbar)
		msg_void1(other, 'removeChildWindow:', toolbar)
		msg_void(toolbar, 'close')
		msg_void(toolbar, 'release')
		msg_void(container, 'release')
		close_tab(target_view)
		close_tab(other_view)
	}
	msg_void2(target, 'addChildWindow:ordered:', toolbar, ObjId(1))
	C.object_setClass(target, full)
	assert window_font_titlebar_container(target) == container
	C.object_setClass(target, original_class)
	msg_void1(target, 'removeChildWindow:', toolbar)
	msg_void2(other, 'addChildWindow:ordered:', toolbar, ObjId(1))
	C.object_setClass(target, full)
	assert is_nil(window_font_titlebar_container(target))
}
