@[has_globals]
module witty_macos

fn C.object_setClass(object ObjId, cls ObjId) ObjId

__global focus_fixture_resigns = 0
__global key_window_terminal_focus = []bool{}
__global focus_fixture_window_is_key = false

fn focus_fixture_resign(_self ObjId, _cmd Sel) bool {
	focus_fixture_resigns++
	return true
}

fn focus_fixture_pump(seconds f64) {
	msg_void1(msg_id(get_class('NSRunLoop'), 'currentRunLoop'), 'runUntilDate:',
		msg_id_f64(get_class('NSDate'), 'dateWithTimeIntervalSinceNow:', seconds))
}

fn record_key_window_terminal_focus(userdata voidptr, focused bool) {
	if userdata == voidptr(1) {
		key_window_terminal_focus << focused
	}
}

fn focus_fixture_key_state(_self ObjId, _cmd Sel) bool {
	return focus_fixture_window_is_key
}

fn mock_focus_fixture_window_key(window ObjId, class_name string) ObjId {
	cls := C.macos_objc_allocate_class_pair(msg_id(window, 'class'), cstr(class_name), 0)
	add_method(cls, 'isKeyWindow', voidptr(focus_fixture_key_state), 'B@:')
	C.macos_objc_register_class_pair(cls)
	return C.object_setClass(window, cls)
}

fn test_terminal_focus_follows_the_key_window_with_its_responder_retained() {
	app_init()
	view := create_restorable_window(640, 480, 'key window focus fixture')
	window := view_window(view)
	original_class := mock_focus_fixture_window_key(window, 'WittyKeyWindowFocusFixture')
	previous := g_focus_cb
	defer {
		g_focus_cb = previous
		view_set_userdata(view, unsafe { nil })
		C.object_setClass(window, original_class)
		close_tab(view)
		release_native_object(window)
		release_native_object(view)
	}
	key_window_terminal_focus = []bool{}
	view_set_userdata(view, voidptr(1))
	set_focus_callback(record_key_window_terminal_focus)

	assert msg_id(window, 'firstResponder') == view
	for focused in [true, false, true] {
		focus_fixture_window_is_key = focused
		sync_native_window_terminal_focus(window)
		assert msg_id(window, 'firstResponder') == view
	}
	assert key_window_terminal_focus == [true, false, true]
}

fn test_quick_terminal_focus_follows_panel_notifications() {
	app_init()
	mut quick := quick_terminal(NativeQuickConfig{autohide: false}, unsafe { nil }, unsafe { nil })
	window := quick.window
	view := quick.view
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	original_class := mock_focus_fixture_window_key(window, 'WittyQuickTerminalFocusFixture')
	previous := g_focus_cb
	defer {
		g_focus_cb = previous
		view_set_userdata(view, unsafe { nil })
		msg_void1(center, 'removeObserver:', quick.observer)
		C.object_setClass(window, original_class)
		msg_void(window, 'close')
		release_native_object(quick.observer)
		release_native_object(window)
		release_native_object(view)
		g_quick_terminal = unsafe { nil }
	}
	quick.visible = true
	assert msg_bool1(window, 'makeFirstResponder:', view)
	key_window_terminal_focus = []bool{}
	view_set_userdata(view, voidptr(1))
	set_focus_callback(record_key_window_terminal_focus)

	for focused in [true, false, true] {
		focus_fixture_window_is_key = focused
		notice := if focused { 'NSWindowDidBecomeKeyNotification' } else { 'NSWindowDidResignKeyNotification' }
		msg_void2(center, 'postNotificationName:object:', nsstring(notice), window)
		focus_fixture_pump(0.03)
		assert msg_id(window, 'firstResponder') == view
	}
	quick.visible = false
	focus_fixture_window_is_key = false
	msg_void2(center, 'postNotificationName:object:', nsstring('NSWindowDidResignKeyNotification'), window)
	assert key_window_terminal_focus == [true, false, true, false]
}

fn test_source_focus_async_does_not_key_or_activate_other_window() {
	app_init()
	msg_void(shared_app(), 'finishLaunching')
	first := create_window(640, 480, 'first')
	second := create_window(640, 480, 'second')
	defer { close_tab(first); close_tab(second) }
	focus_native_window(view_window(first))
	focus_fixture_pump(0.1)
	key := msg_id(shared_app(), 'keyWindow')
	active := app_is_active()
	cls := C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittySourceFocusFixture'), 0)
	add_method(cls, 'resignFirstResponder', voidptr(focus_fixture_resign), 'B@:')
	C.macos_objc_register_class_pair(cls)
	from := msg_id(alloc('WittySourceFocusFixture'), 'init')
	defer { msg_void(from, 'release') }
	focus_fixture_resigns = 0
	move_focus(second, voidptr(from), none)
	assert focus_fixture_resigns == 0
	focus_fixture_pump(0.03)
	assert focus_fixture_resigns == 1
	assert msg_id(view_window(second), 'firstResponder') == second
	assert msg_id(shared_app(), 'keyWindow') == key
	assert app_is_active() == active
}

fn test_source_focus_retries_unattached_view_and_releases_captures() {
	app_init()
	msg_void(shared_app(), 'finishLaunching')
	window_view := create_window(640, 480, 'retry')
	to := create_terminal_view(objc_rect(0, 0, 40, 40))
	defer { msg_void(to, 'release'); close_tab(window_view) }
	initial := g_native_focus_tasks.len
	move_focus(voidptr(to), unsafe { nil }, none)
	assert g_native_focus_tasks.len == initial + 1
	focus_fixture_pump(0.02)
	assert g_native_focus_tasks.len == initial + 1
	assert (g_native_focus_tasks.last().delay or { 0 }) == 0.05
	msg_void1(window_view, 'addSubview:', to)
	focus_fixture_pump(0.06)
	assert g_native_focus_tasks.len == initial
	assert msg_id(view_window(window_view), 'firstResponder') == to
	msg_void(to, 'removeFromSuperview')
	retained := msg_u64(to, 'retainCount')
	move_focus(voidptr(to), unsafe { nil }, none)
	assert msg_u64(to, 'retainCount') == retained + 1
	focus_fixture_pump(0.8)
	assert g_native_focus_tasks.len == initial
	assert msg_u64(to, 'retainCount') == retained
	move_focus(voidptr(to), unsafe { nil }, 0.5)
	assert g_native_focus_tasks.len == initial
}
