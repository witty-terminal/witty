@[has_globals]
module macos

import json2
import os

#insert "@VMODROOT/macos/window_tahoe_test_abi.h"
#insert "@VMODROOT/macos/canvas_overlay_test_bridge.h"
fn C.witty_tahoe_test_size(view voidptr, width &f64, height &f64)
fn C.witty_tahoe_test_priority(view voidptr) f32
fn C.witty_tahoe_test_event(kind u64, flags u64, button u64, x f64, y f64) ObjId
fn C.witty_tahoe_test_replace_send_event()
fn C.witty_tahoe_test_restore_send_event()
fn C.witty_tahoe_test_fallback_count() int
fn C.witty_tahoe_test_watch_add_accessory(accessory voidptr)
fn C.witty_tahoe_test_restore_add_accessory()
fn C.witty_tahoe_test_super_accessory_layout() i64
fn C.witty_overlay_test_solid_layer_matches(layer ObjId, color ObjId) bool
fn C.object_setClass(object ObjId, cls ObjId) ObjId

fn test_tahoe_tab_glass_finds_swift_private_view_names() {
	app_init()
	cls := C.macos_objc_allocate_class_pair(get_class('NSView'),
		cstr('_TtC9WittyTest24NSSubduedGlassEffectView'), 0)
	C.macos_objc_register_class_pair(cls)
	container := msg_id(alloc('NSView'), 'init')
	glass := msg_id(msg_id(cls, 'alloc'), 'init')
	defer {
		msg_void(glass, 'release')
		msg_void(container, 'release')
	}
	msg_void1(container, 'addSubview:', glass)
	assert tahoe_tab_glass_view(container) == glass
}

fn test_tahoe_titlebar_hides_only_the_decoration_separator() {
	app_init()
	view := new_obj('NSView')
	defer { msg_void(view, 'release') }
	msg_void_bool(view, 'setWantsLayer:', true)
	decoration := new_obj('CALayer')
	separator := new_obj('CALayer')
	scroll_edge := new_obj('CALayer')
	defer {
		for layer in [decoration, separator, scroll_edge] {
			msg_void(layer, 'release')
		}
	}
	msg_void1(separator, 'setName:', nsstring('CUIWindowSeparatorBarLayer'))
	msg_void1(scroll_edge, 'setName:', nsstring('Separator'))
	msg_void1(msg_id(view, 'layer'), 'addSublayer:', decoration)
	msg_void1(decoration, 'addSublayer:', separator)
	msg_void1(decoration, 'addSublayer:', scroll_edge)
	C.witty_tahoe_hide_titlebar_separator(view)
	assert msg_bool(separator, 'isHidden')
	assert !msg_bool(scroll_edge, 'isHidden')
}

__global g_tahoe_test_right_clicks = 0
__global g_tahoe_test_tab_userdata = uint(0)

fn tahoe_test_new_tab(userdata voidptr, action string) bool {
	assert action == 'new_tab'
	g_tahoe_test_tab_userdata = uint(userdata)
	return true
}

fn tahoe_test_right_click(_self ObjId, _cmd Sel, _event ObjId) {
	g_tahoe_test_right_clicks++
}

fn tahoe_test_tab_bar_name(_self ObjId, _cmd Sel) ObjId { return nsstring('NSTabBar') }

fn tahoe_test_size(view ObjId) ObjCSize {
	mut width := f64(0)
	mut height := f64(0)
	C.witty_tahoe_test_size(voidptr(view), &width, &height)
	return ObjCSize{width: width, height: height}
}

fn tahoe_test_drain() {
	msg_void1(msg_id(get_class('NSRunLoop'), 'currentRunLoop'), 'runUntilDate:',
		msg_id_f64(get_class('NSDate'), 'dateWithTimeIntervalSinceNow:', 0.1))
}

fn tahoe_test_readd_tab_accessory(window ObjId) {
	controllers := msg_id(window, 'titlebarAccessoryViewControllers')
	mut tab_controller := nil_obj()
	mut tab_index := u64(0)
	for i in 0 .. int(msg_u64(controllers, 'count')) {
		controller := msg_id_u64(controllers, 'objectAtIndex:', u64(i))
		if is_tab_bar_accessory(controller) { tab_controller = msg_id(controller, 'retain'); tab_index = u64(i); break }
	}
	assert !is_nil(tab_controller)
	defer { msg_void(tab_controller, 'release') }
	msg_void_u64(window, 'removeTitlebarAccessoryViewControllerAtIndex:', tab_index)
	msg_void_u64(tab_controller, 'setLayoutAttribute:', 4)
	assert msg_u64(tab_controller, 'layoutAttribute') == 4
	C.witty_tahoe_test_watch_add_accessory(voidptr(tab_controller))
	defer { C.witty_tahoe_test_restore_add_accessory() }
	msg_void1(window, 'addTitlebarAccessoryViewController:', tab_controller)
	assert C.witty_tahoe_test_super_accessory_layout() == 2
	assert msg_u64(tab_controller, 'layoutAttribute') == 2
}


struct TahoeTitleRecord {
	input string
	title string
	display_title string
	has_tab_bar bool
	main bool
	font_name ?string
	toolbar_id string
	allowed []string
	defaults []string
	centered bool
	priority u64
	compression f32
	bordered bool
}

fn tahoe_test_record(name string, data &NativeWindowData, item ObjId) TahoeTitleRecord {
	toolbar := msg_id(data.window, 'toolbar')
	mut arrays := [][]string{}
	for value in [native_toolbar_allowed(toolbar, nil_obj(), toolbar), native_toolbar_defaults(toolbar, nil_obj(), toolbar)] {
		mut names := []string{}
		for i in 0 .. int(msg_u64(value, 'count')) { names << objc_utf8_string(msg_id_u64(value, 'objectAtIndex:', u64(i))) }
		arrays << names
	}
	return TahoeTitleRecord{input: name, title: data.tahoe_title,
		display_title: if data.tahoe_title == '' { ' ' } else { data.tahoe_title },
		has_tab_bar: data.tahoe_has_tab_bar, main: data.tahoe_main,
		font_name: if is_nil(data.tahoe_title_font) { none } else { objc_utf8_string(msg_id(data.tahoe_title_font, 'fontName')) },
		toolbar_id: objc_utf8_string(msg_id(toolbar, 'identifier')), allowed: arrays[0], defaults: arrays[1],
		centered: msg_bool1(msg_id(toolbar, 'centeredItemIdentifiers'), 'containsObject:', nsstring('Title')),
		priority: msg_u64(item, 'visibilityPriority'), compression: C.witty_tahoe_test_priority(voidptr(data.tahoe_title_view)), bordered: msg_bool(item, 'isBordered')}
}

fn test_selected_tahoe_toolbar_preserves_source_async_title_font_and_main_model() {
	if !C.witty_native_os_at_least(26, 0, 0) { return }
	app_init()
	view := create_restorable_window(480, 320, 'original title')
	window := msg_id(view, 'window')
	defer { msg_void(window, 'close'); msg_void(window, 'release'); msg_void(view, 'release') }
	apply_native_window_config(view, NativeWindowConfig{titlebar_style: 2}, true, 0x112233, 1, false)
	mut data := native_window_data(window) or { panic('missing native window config') }
	assert data.tabs_tahoe
	toolbar := msg_id(window, 'toolbar')
	assert objc_utf8_string(msg_id(toolbar, 'identifier')) == 'TerminalToolbar'
	assert msg_u64(window, 'toolbarStyle') == 4
	assert msg_u64(window, 'titleVisibility') == 1
	assert !msg_bool(window, 'titlebarAppearsTransparent')
	allowed := native_toolbar_allowed(toolbar, sel('toolbarAllowedItemIdentifiers:'), toolbar)
	defaults := native_toolbar_defaults(toolbar, sel('toolbarDefaultItemIdentifiers:'), toolbar)
	assert objc_utf8_string(msg_id_u64(allowed, 'objectAtIndex:', 0)) == 'Title'
	assert msg_u64(allowed, 'count') == 3
	assert objc_utf8_string(msg_id_u64(defaults, 'objectAtIndex:', 1)) == 'Title'
	assert msg_bool1(msg_id(toolbar, 'centeredItemIdentifiers'), 'containsObject:', nsstring('Title'))
	item := native_toolbar_item(toolbar, sel('toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:'), toolbar, nsstring('Title'), true)
	defer { msg_void(item, 'release') }
	assert msg_id(item, 'view') == data.tahoe_title_view
	assert msg_u64(item, 'visibilityPriority') == 2000
	assert msg_bool(item, 'isEnabled')
	assert !msg_bool(item, 'isBordered')
	assert C.witty_tahoe_test_priority(voidptr(data.tahoe_title_view)) == 1000
	first_title_view := msg_id(item, 'view')
	second_item := native_toolbar_item(toolbar, sel('toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:'), toolbar, nsstring('Title'), true)
	defer { msg_void(second_item, 'release') }
	assert msg_id(second_item, 'view') != first_title_view
	assert msg_id(item, 'view') == first_title_view
	mut records := [tahoe_test_record('initial', data, item)]
	tahoe_test_drain()
	assert data.tahoe_title == 'original title'
	records << tahoe_test_record('original', data, item)
	msg_void1(window, 'setTitle:', nsstring('changed title'))
	assert data.tahoe_title == 'original title'
	records << tahoe_test_record('queued-title', data, item)
	tahoe_test_drain()
	assert data.tahoe_title == 'changed title'
	for title_view in [first_title_view, data.tahoe_title_view] {
		assert objc_utf8_string(msg_id(title_view, 'accessibilityValue')) == 'changed title'
		assert objc_utf8_string(msg_id(title_view, 'accessibilityRole')) == 'AXStaticText'
		assert msg_bool(title_view, 'isAccessibilityElement')
	}
	original_width := tahoe_test_size(first_title_view).width
	records << tahoe_test_record('changed', data, item)
	set_native_window_title_font(view, 'Menlo')
	assert is_nil(data.tahoe_title_font)
	tahoe_test_drain()
	assert data.tahoe_title_font == window_title_font(window)
	assert tahoe_test_size(first_title_view).width != original_width
	assert tahoe_test_size(first_title_view).width == tahoe_test_size(data.tahoe_title_view).width
	records << tahoe_test_record('font', data, item)
	msg_void(window, 'resignMainWindow')
	assert !data.tahoe_main
	ink := ObjId(C.macos_objc_get_ptr_ivar(data.tahoe_title_view, cstr('vtTitleInk')))
	assert !is_nil(ink)
	assert !msg_bool(ink, 'isHidden')
	records << tahoe_test_record('inactive', data, item)
	msg_void(window, 'becomeMainWindow')
	assert data.tahoe_main
	assert msg_bool(ink, 'isHidden')
	msg_void1(window, 'setTitle:', nsstring(''))
	tahoe_test_drain()
	assert data.tahoe_title == ''
	assert objc_utf8_string(msg_id(data.tahoe_title_view, 'accessibilityValue')) == ' '
	assert tahoe_test_size(data.tahoe_title_view).width > 0
	records << tahoe_test_record('empty', data, item)
	queue_tahoe_window(window, .tab_bar, false, true, 0)
	assert !data.tahoe_has_tab_bar
	tahoe_test_drain()
	assert data.tahoe_has_tab_bar
	assert !msg_bool(data.tahoe_title_view, 'isAccessibilityElement')
	size := tahoe_test_size(data.tahoe_title_view)
	assert size.width == 1 && size.height == 1
	records << tahoe_test_record('tabs', data, item)
	queue_tahoe_window(window, .tab_bar, true, false, 0)
	tahoe_test_drain()
	assert !data.tahoe_has_tab_bar
	assert msg_bool(data.tahoe_title_view, 'isAccessibilityElement')
	records << tahoe_test_record('removed', data, item)
	set_native_window_title_font(view, none)
	tahoe_test_drain()
	assert is_nil(data.tahoe_title_font)
	records << tahoe_test_record('no-font', data, item)
	assert g_tahoe_window_tasks.len == 0
	if path := os.getenv_opt('WITTY_TAHOE_MODEL_OUTPUT') { os.write_file(path, json2.encode(records, escape_unicode: true, time_as_unix: true))! }
}

fn test_tahoe_tab_constraints_observer_reset_event_forwarding_and_appearance() {
	if !C.witty_native_os_at_least(26, 0, 0) { return }
	app_init()
	msg_void(shared_app(), 'finishLaunching')
	view := create_window(600, 400, 'first Tahoe tab')
	other := create_window(600, 400, 'second Tahoe tab')
	window := msg_id(view, 'window')
	other_window := msg_id(other, 'window')
	defer {
		msg_void(window, 'close'); msg_void(other_window, 'close')
		msg_void(window, 'release'); msg_void(other_window, 'release')
		msg_void(view, 'release'); msg_void(other, 'release')
	}
	config := NativeWindowConfig{titlebar_style: 2, opacity: 0.5}
	for target in [view, other] { apply_native_window_config(voidptr(target), config, true, 0x224466, 0.5, false) }
	add_native_tab(view, other)
	msg_void1(window, 'makeKeyAndOrderFront:', nil_obj())
	msg_void_bool(msg_id(window, 'tabGroup'), 'setTabBarVisible:', true)
	tahoe_test_drain()
	setup_tahoe_tab_bar(window)
	tahoe_test_drain()
	mut data := native_window_data(window) or { panic('missing Tahoe config') }
	assert data.tahoe_has_tab_bar
	assert !is_nil(data.tahoe_frame_observer)
	titlebar := tahoe_titlebar_view(window)
	tab_bar := tahoe_tab_bar_view(window)
	clip := tahoe_tab_accessory_container(tab_bar)
	toolbar := first_descendant(titlebar, 'NSToolbarView')
	assert !is_nil(clip) && !is_nil(toolbar)
	new_button := first_descendant(titlebar, 'NSTabBarNewTabButton')
	assert msg_rect(tab_bar, 'frame').height == msg_rect(new_button, 'frame').width
	assert !msg_bool(clip, 'translatesAutoresizingMaskIntoConstraints')
	constraints := msg_id(titlebar, 'constraints')
	mut left_padding := f64(-1)
	mut top_padding := f64(-1)
	for i in 0 .. int(msg_u64(constraints, 'count')) {
		constraint := msg_id_u64(constraints, 'objectAtIndex:', u64(i))
		if msg_id(constraint, 'firstItem') == clip {
			if msg_u64(constraint, 'firstAttribute') == 1 { left_padding = msg_f64(constraint, 'constant') }
			if msg_u64(constraint, 'firstAttribute') == 3 { top_padding = msg_f64(constraint, 'constant') }
		}
	}
	assert left_padding == 70 && top_padding == 2
	observer := data.tahoe_frame_observer
	setup_tahoe_tab_bar(window)
	assert data.tahoe_frame_observer == observer
	msg_void2(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), 'postNotificationName:object:', nsstring('NSViewFrameDidChangeNotification'), tab_bar)
	assert is_nil(data.tahoe_frame_observer)
	tahoe_test_drain()
	assert !is_nil(data.tahoe_frame_observer)
	assert !is_nil(data.tahoe_group_observer) && data.tahoe_group == msg_id(window, 'tabGroup')
	container := window_font_titlebar_container(window)
	background := first_descendant(container, 'NSTitlebarBackgroundView')
	assert is_nil(background) || msg_bool(background, 'isHidden')
	if C.witty_native_os_at_least(27, 0, 0) {
		glass := tahoe_tab_glass_view(container)
		child := msg_id(msg_id(glass, 'subviews'), 'firstObject')
		if !is_nil(child) {
			msg_void_f64(child, 'setAlphaValue:', 1)
			schedule_tahoe_tab_background(window)
			tahoe_test_drain()
			assert msg_f64(child, 'alphaValue') == 0.5
		}
	}
	titlebar_layer := msg_id(first_descendant(container, 'NSTitlebarView'), 'layer')
	assert C.witty_overlay_test_solid_layer_matches(titlebar_layer, native_color(0x224466, 0.5))
	apply_native_window_config(view, NativeWindowConfig{...config, blur: -1}, false, 0x224466, 0.5, false)
	assert C.witty_overlay_test_solid_layer_matches(titlebar_layer, native_color(0, 0))
	// A hot reload changes the derived style while the source window class is fixed.
	apply_native_window_config(view, NativeWindowConfig{...config, titlebar_style: 0, blur: -1}, false, 0xffffff, 0.5, false)
	assert data.tabs_tahoe
	assert objc_utf8_string(msg_id(msg_id(window, 'appearance'), 'name')) == 'NSAppearanceNameAqua'
	assert msg_u64(window, 'titleVisibility') == 1
	assert C.witty_overlay_test_solid_layer_matches(titlebar_layer, native_color(0xffffff, 0.5))
	tahoe_test_readd_tab_accessory(window)
	tahoe_test_drain()
	apply_native_window_config(view, NativeWindowConfig{...config, blur: -1}, false, 0x224466, 0.5, false)
	// Resetting native tab visibility invokes the inherited transparent KVO path.
	msg_void_bool(msg_id(window, 'tabGroup'), 'setTabBarVisible:', false)
	tahoe_test_drain()
	msg_void_bool(msg_id(window, 'tabGroup'), 'setTabBarVisible:', true)
	tahoe_test_drain()
	setup_tahoe_tab_bar(window)
	tahoe_test_drain()
	current_bar := tahoe_tab_bar_view(window)
	original_class := C.object_getClass(current_bar)
	probe_class := C.macos_objc_allocate_class_pair(original_class, cstr('WittyTahoeTabClickFixture'), 0)
	add_method(probe_class, 'rightMouseDown:', voidptr(tahoe_test_right_click), 'v@:@')
	add_method(probe_class, 'className', voidptr(tahoe_test_tab_bar_name), '@@:')
	C.macos_objc_register_class_pair(probe_class)
	C.object_setClass(current_bar, probe_class)
	C.witty_tahoe_test_replace_send_event()
	defer { C.witty_tahoe_test_restore_send_event(); C.object_setClass(current_bar, original_class) }
	point := msg_point_point_obj(current_bar, 'convertPoint:toView:', ObjCPoint{x: 2, y: 2}, nil_obj())
	g_tahoe_test_right_clicks = 0
	for spec in [[u64(3), 0, 1], [u64(25), 0, 2], [u64(1), u64(1 << 18), 0]] {
		event := C.witty_tahoe_test_event(spec[0], spec[1], spec[2], point.x, point.y)
		native_tahoe_send_event(window, sel('sendEvent:'), event)
		msg_void(event, 'release')
	}
	assert g_tahoe_test_right_clicks == 3
	assert C.witty_tahoe_test_fallback_count() == 0
	for spec in [[u64(1), 0, 0], [u64(25), 0, 3], [u64(2), 0, 0]] {
		event := C.witty_tahoe_test_event(spec[0], spec[1], spec[2], point.x, point.y)
		native_tahoe_send_event(window, sel('sendEvent:'), event)
		msg_void(event, 'release')
	}
	event := C.witty_tahoe_test_event(3, 0, 1, -100, -100)
	native_tahoe_send_event(window, sel('sendEvent:'), event)
	msg_void(event, 'release')
	assert g_tahoe_test_right_clicks == 3
	assert C.witty_tahoe_test_fallback_count() == 4
	set_tahoe_has_tab_bar(mut data, false)
	event2 := C.witty_tahoe_test_event(3, 0, 1, point.x, point.y)
	native_tahoe_send_event(window, sel('sendEvent:'), event2)
	msg_void(event2, 'release')
	assert C.witty_tahoe_test_fallback_count() == 5
	clear_tahoe_frame_observer(mut data)
	clear_tahoe_tab_group(mut data)
	assert is_nil(data.tahoe_frame_observer) && is_nil(data.tahoe_group)
}

fn test_native_new_tab_button_uses_remembered_focused_surface_core_binding() {
	app_init()
	view := create_restorable_window(480, 320, 'new-tab source')
	window := msg_id(view, 'window')
	mut host := create_split_host(view)
	other := create_split_surface_view(host)
	mut first := new_action_surface(view, voidptr(uint(1)), ActionCallbacks{binding: tahoe_test_new_tab})
	mut second := new_action_surface(other, voidptr(uint(2)), ActionCallbacks{binding: tahoe_test_new_tab})
	host.replace_tree(host.tree.inserting(other, view, .right) or { panic(err) })
	defer {
		first.deinit(); second.deinit()
		msg_void(window, 'close'); msg_void(window, 'release')
		msg_void(view, 'release'); msg_void(other, 'release'); msg_void(host.container, 'release')
	}
	apply_native_window_config(other, NativeWindowConfig{titlebar_style: 2}, true, 0x224466, 1, false)
	// An overlay can own first responder while the controller still remembers
	// its second focused surface. The source selector must keep that surface.
	msg_bool1(window, 'makeFirstResponder:', nil_obj())
	g_tahoe_test_tab_userdata = 0
	msg_void1(window, 'newWindowForTab:', nil_obj())
	assert g_tahoe_test_tab_userdata == 2
	second.deinit()
	msg_void1(window, 'newWindowForTab:', nil_obj())
	assert g_tahoe_test_tab_userdata == 2
}

fn test_tahoe_hidden_window_buttons_use_zero_tab_padding() {
	if !C.witty_native_os_at_least(26, 0, 0) { return }
	app_init()
	msg_void(shared_app(), 'finishLaunching')
	view := create_window(600, 400, 'hidden buttons')
	other := create_window(600, 400, 'hidden buttons tab')
	window := msg_id(view, 'window')
	other_window := msg_id(other, 'window')
	defer {
		msg_void(window, 'close'); msg_void(other_window, 'close')
		msg_void(window, 'release'); msg_void(other_window, 'release')
		msg_void(view, 'release'); msg_void(other, 'release')
	}
	config := NativeWindowConfig{titlebar_style: 2, buttons_hidden: true}
	for target in [view, other] { apply_native_window_config(voidptr(target), config, true, 0x224466, 1, false) }
	add_native_tab(view, other)
	msg_void1(window, 'makeKeyAndOrderFront:', nil_obj())
	msg_void_bool(msg_id(window, 'tabGroup'), 'setTabBarVisible:', true)
	tahoe_test_drain()
	setup_tahoe_tab_bar(window)
	tahoe_test_drain()
	data := native_window_data(window) or { panic('missing Tahoe metadata') }
	assert !is_nil(data.tahoe_frame_observer)
	titlebar := tahoe_titlebar_view(window)
	clip := tahoe_tab_accessory_container(tahoe_tab_bar_view(window))
	constraints := msg_id(titlebar, 'constraints')
	mut zero_padding := false
	for i in 0 .. int(msg_u64(constraints, 'count')) {
		constraint := msg_id_u64(constraints, 'objectAtIndex:', u64(i))
		if msg_id(constraint, 'firstItem') == clip && msg_u64(constraint, 'firstAttribute') == 1 && msg_f64(constraint, 'constant') == 0 { zero_padding = true }
	}
	assert zero_padding
}

fn test_tahoe_update_pill_stays_in_content_and_undecorated_window_uses_default_class() {
	if !C.witty_native_os_at_least(26, 0, 0) { return }
	app_init()
	view := create_window(480, 320, 'Tahoe update placement')
	regular := create_window(480, 320, 'regular update placement')
	undecorated := create_window(480, 320, 'undecorated class')
	window := msg_id(view, 'window')
	regular_window := msg_id(regular, 'window')
	undecorated_window := msg_id(undecorated, 'window')
	defer {
		for target in [window, regular_window, undecorated_window] { msg_void(target, 'close'); msg_void(target, 'release') }
		for target in [view, regular, undecorated] { msg_void(target, 'release') }
	}
	apply_native_window_config(view, NativeWindowConfig{titlebar_style: 2}, true, 0, 1, false)
	apply_native_window_config(regular, NativeWindowConfig{}, true, 0, 1, false)
	apply_native_window_config(undecorated, NativeWindowConfig{titlebar_style: 2, decorations: false}, true, 0, 1, false)
	assert (native_window_data(window) or { panic('missing Tahoe metadata') }).tabs_tahoe
	assert !(native_window_data(undecorated_window) or { panic('missing undecorated metadata') }).tabs_tahoe
	mut controller := &NativeUpdateController{driver: msg_id(alloc('NSObject'), 'init')}
	defer { controller.deinit() }
	controller.set_state(UpdateState{kind: .checking})
	tahoe_pill := controller.pills[u64(window)] or { panic('missing Tahoe update pill') }
	regular_pill := controller.pills[u64(regular_window)] or { panic('missing regular update pill') }
	assert u64(window) !in controller.accessories
	assert msg_id(tahoe_pill, 'superview') == msg_id(window, 'contentView')
	accessory := controller.accessories[u64(regular_window)] or { panic('missing regular update accessory') }
	assert msg_id(regular_pill, 'superview') == msg_id(accessory, 'view')
	apply_native_window_config(view, NativeWindowConfig{}, false, 0, 1, false)
	controller.refresh_presentation()
	assert u64(window) !in controller.accessories
	assert msg_id(tahoe_pill, 'superview') == msg_id(window, 'contentView')
}
