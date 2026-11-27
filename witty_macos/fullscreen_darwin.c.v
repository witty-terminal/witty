@[has_globals]
module witty_macos

import math

#insert "@VMODROOT/witty_macos/fullscreen_abi.h"
fn C.witty_macos_objc_msg_void3(obj voidptr, selector voidptr, a voidptr, b voidptr, c voidptr)
fn C.witty_macos_screen_insets(screen voidptr) C.witty_macos_edge_insets
struct C.witty_macos_edge_insets { top f64 left f64 bottom f64 right f64 }
fn C.witty_fullscreen_msg_rect_rect(obj voidptr, selector voidptr, value ObjCRect) ObjCRect
fn C.witty_macos_msg_void_rect_bool(obj voidptr, selector voidptr, value ObjCRect, display bool)
fn C.CGSMainConnectionID() i32
fn C.CGSGetActiveSpace(connection i32) uint
fn C.CGSSpaceGetType(connection i32, space uint) u32
fn C.CGSCopySpacesForWindows(connection i32, mask u32, windows voidptr) voidptr

@[heap]
struct FullscreenState {
mut:
	window ObjId
	mode NativeFullscreenMode
	saved bool
	observer ObjId
	screen_id u32
	content_frame ObjCRect
	style u64
	toolbar ObjId
	toolbar_style u64
	accessories []ObjId
	tab_group ObjId
	tab_index int = -1
	dock bool
	menu bool
	first_responder ObjId
}
__global (
	g_fullscreen_states map[u64]&FullscreenState
	g_presentation_counts map[u64]u32
)

fn presentation_acquire(option u64) {
	g_presentation_counts[option]++
	msg_void_u64(shared_app(), 'setPresentationOptions:', msg_u64(shared_app(), 'presentationOptions') | option)
}
fn presentation_release(option u64) {
	count := g_presentation_counts[option]
	if count == 0 { return }
	if count == 1 {
		g_presentation_counts.delete(option)
		msg_void_u64(shared_app(), 'setPresentationOptions:', msg_u64(shared_app(), 'presentationOptions') & ~option)
	} else { g_presentation_counts[option] = count - 1 }
}
fn screen_display_id(screen ObjId) u32 {
	number := msg_id1(msg_id(screen, 'deviceDescription'), 'objectForKey:', nsstring('NSScreenNumber'))
	return u32(msg_u64(number, 'unsignedIntValue'))
}
fn screen_has_dock(screen ObjId) bool {
	defaults := msg_id(get_class('NSUserDefaults'), 'standardUserDefaults')
	domain := msg_id1(defaults, 'persistentDomainForName:', nsstring('com.apple.dock'))
	if msg_bool(msg_id1(domain, 'objectForKey:', nsstring('autohide')), 'boolValue') { return false }
	frame := msg_rect(screen, 'frame')
	visible := msg_rect(screen, 'visibleFrame')
	if visible.width < frame.width { return true }
	menu_height := msg_f64(msg_id(shared_app(), 'mainMenu'), 'menuBarHeight')
	return visible.height < frame.height - math.max(menu_height, C.witty_macos_screen_insets(screen).top) - 5
}
fn window_can_hide_menu(window ObjId) bool {
	number := msg_u64(window, 'windowNumber')
	if number == 0 { return true }
	number_obj := msg_id_u64(get_class('NSNumber'), 'numberWithUnsignedInt:', number)
	windows := msg_id1(get_class('NSArray'), 'arrayWithObject:', number_obj)
	connection := C.CGSMainConnectionID()
	spaces := ObjId(C.CGSCopySpacesForWindows(connection, 7, windows))
	count := int(msg_u64(spaces, 'count'))
	active := C.CGSGetActiveSpace(connection)
	mut no_fullscreen := true
	for i in 0 .. count {
		space := uint(msg_u64(msg_id_u64(spaces, 'objectAtIndex:', u64(i)), 'unsignedLongLongValue'))
		kind := C.CGSSpaceGetType(connection, space)
		if space == active { msg_void(spaces, 'release'); return kind != 4 }
		if kind == 4 { no_fullscreen = false }
	}
	msg_void(spaces, 'release')
	return no_fullscreen
}
fn fullscreen_state_from_observer(observer ObjId) ?&FullscreenState {
	ptr := C.macos_objc_get_ptr_ivar(observer, cstr('vtFullscreenState'))
	if is_nil(ptr) { return none }
	return unsafe { &FullscreenState(ptr) }
}
fn fullscreen_post(state &FullscreenState, entered bool) {
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	if !entered { reapply_hidden_native_window_style(state.window) }
	msg_void2(center, 'postNotificationName:object:', nsstring(if entered { 'com.mitchellh.fullscreenDidEnter' } else { 'com.mitchellh.fullscreenDidExit' }), state.observer)
}
fn fullscreen_screen_changed(observer ObjId, _cmd Sel, notification ObjId) {
	mut state := fullscreen_state_from_observer(observer) or { return }
	if !state.saved || msg_id(notification, 'object') != state.window { return }
	if state.screen_id != screen_display_id(msg_id(state.window, 'screen')) { state.exit() }
}
fn fullscreen_window_closed(observer ObjId, _cmd Sel, _notification ObjId) {
	if mut state := fullscreen_state_from_observer(observer) { if state.saved { state.exit() } }
}
fn fullscreen_native_entered(observer ObjId, _cmd Sel, _notification ObjId) {
	if state := fullscreen_state_from_observer(observer) { fullscreen_post(state, true) }
}
fn fullscreen_native_exited(observer ObjId, _cmd Sel, _notification ObjId) {
	if state := fullscreen_state_from_observer(observer) { fullscreen_post(state, false) }
}
fn make_fullscreen_state(window ObjId) &FullscreenState {
	mut cls := get_class('VTFullscreenObserver')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('VTFullscreenObserver'), 0)
		C.macos_class_add_ivar(cls, cstr('vtFullscreenState'), sizeof(voidptr), 3, cstr('^v'))
		add_method(cls, 'vtScreenChanged:', voidptr(fullscreen_screen_changed), 'v@:@')
		add_method(cls, 'vtClosed:', voidptr(fullscreen_window_closed), 'v@:@')
		add_method(cls, 'vtEntered:', voidptr(fullscreen_native_entered), 'v@:@')
		add_method(cls, 'vtExited:', voidptr(fullscreen_native_exited), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	observer := msg_id(msg_id(cls, 'alloc'), 'init')
	state := &FullscreenState{window: window, observer: observer}
	C.macos_objc_set_ptr_ivar(observer, cstr('vtFullscreenState'), voidptr(state))
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	for pair in [['NSWindowDidEnterFullScreenNotification', 'vtEntered:'], ['NSWindowDidExitFullScreenNotification', 'vtExited:'], ['NSWindowWillCloseNotification', 'vtClosed:']] {
		C.witty_macos_observe(center, observer, sel(pair[1]), nsstring(pair[0]), window)
	}
	return state
}
fn (s &FullscreenState) is_active() bool {
	return if s.mode == .native { msg_u64(s.window, 'styleMask') & u64(1 << 14) != 0 } else { s.saved }
}
fn fullscreen_finish_enter(context voidptr) {
	mut s := unsafe { &FullscreenState(context) }
	if !s.saved { return }
	screen := msg_id(s.window, 'screen')
	screen_frame := msg_rect(screen, 'frame')
	frame_bounds := fullscreen_frame(SplitBounds{x: screen_frame.x, y: screen_frame.y, width: screen_frame.width, height: screen_frame.height}, msg_u64(shared_app(), 'presentationOptions'), msg_f64(msg_id(shared_app(), 'mainMenu'), 'menuBarHeight'), C.witty_macos_screen_insets(screen).top, s.mode)
	frame := objc_rect(frame_bounds.x, frame_bounds.y, frame_bounds.width, frame_bounds.height)
	C.witty_macos_msg_void_rect_bool(s.window, sel('setFrame:display:'), frame, true)
	if !is_nil(s.first_responder) { msg_bool1(s.window, 'makeFirstResponder:', s.first_responder) }
	fullscreen_post(s, true)
}
fn (mut s FullscreenState) enter() {
	if s.is_active() { return }
	if s.mode == .native {
		msg_void_u64(s.window, 'setTitlebarSeparatorStyle:', 1)
		msg_void1(s.window, 'toggleFullScreen:', nil_obj())
		return
	}
	if msg_u64(s.window, 'styleMask') & u64(1 << 14) != 0 { msg_void1(s.window, 'toggleFullScreen:', nil_obj()); return }
	screen := msg_id(s.window, 'screen')
	content := msg_id(s.window, 'contentView')
	if is_nil(screen) || is_nil(content) { return }
	s.screen_id = screen_display_id(screen)
	s.tab_group = msg_id(msg_id(s.window, 'tabGroup'), 'retain')
	s.tab_index = -1
	tabs := msg_id(s.tab_group, 'windows')
	for i in 0 .. int(msg_u64(tabs, 'count')) { if msg_id_u64(tabs, 'objectAtIndex:', u64(i)) == s.window { s.tab_index = i; break } }
	s.content_frame = C.witty_fullscreen_msg_rect_rect(s.window, sel('convertRectToScreen:'), msg_rect(content, 'frame'))
	s.style = msg_u64(s.window, 'styleMask')
	s.toolbar = msg_id(msg_id(s.window, 'toolbar'), 'retain')
	s.toolbar_style = msg_u64(s.window, 'toolbarStyle')
	s.accessories.clear()
	if s.style & ns_window_style_titled != 0 {
		accessories := msg_id(s.window, 'titlebarAccessoryViewControllers')
		for i in 0 .. int(msg_u64(accessories, 'count')) { s.accessories << msg_id(msg_id_u64(accessories, 'objectAtIndex:', u64(i)), 'retain') }
	}
	s.dock = screen_has_dock(screen)
	s.menu = window_can_hide_menu(s.window)
	s.saved = true
	s.first_responder = msg_id(s.window, 'firstResponder')
	if s.dock { presentation_acquire(1) }
	if s.mode != .visible_menu && s.menu { presentation_acquire(u64(1 << 2)) }
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	C.witty_macos_observe(center, s.observer, sel('vtScreenChanged:'), nsstring('NSWindowDidChangeScreenNotification'), s.window)
	msg_void_u64(s.window, 'setStyleMask:', s.style & ~(ns_window_style_titled | ns_window_style_resizable))
	msg_void1(s.window, 'makeKeyAndOrderFront:', nil_obj())
	dispatch_main(fullscreen_finish_enter, voidptr(&s))
}
fn (mut s FullscreenState) exit() {
	if !s.is_active() { return }
	if s.mode == .native {
		msg_void_u64(s.window, 'setTitlebarSeparatorStyle:', 0)
		msg_void1(s.window, 'toggleFullScreen:', nil_obj())
		return
	}
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	C.witty_macos_objc_msg_void3(center, sel('removeObserver:name:object:'), s.observer, nsstring('NSWindowDidChangeScreenNotification'), s.window)
	responder := msg_id(s.window, 'firstResponder')
	if s.dock { presentation_release(1) }
	if s.mode != .visible_menu && s.menu { presentation_release(u64(1 << 2)) }
	msg_void_u64(s.window, 'setStyleMask:', s.style)
	frame := C.witty_fullscreen_msg_rect_rect(s.window, sel('frameRectForContentRect:'), s.content_frame)
	C.witty_macos_msg_void_rect_bool(s.window, sel('setFrame:display:'), frame, true)
	for accessory in s.accessories {
		// AppKit's NSTitlebarAccessoryViewController tab bar must not be restored.
		if is_tab_bar_accessory(accessory) { msg_void(accessory, 'release'); continue }
		current := msg_id(s.window, 'titlebarAccessoryViewControllers')
		if !msg_bool1(current, 'containsObject:', accessory) { msg_void1(s.window, 'addTitlebarAccessoryViewController:', accessory) }
		msg_void(accessory, 'release')
	}
	s.accessories.clear()
	msg_void1(s.window, 'setToolbar:', s.toolbar)
	msg_void_u64(s.window, 'setToolbarStyle:', s.toolbar_style)
	if !is_nil(s.tab_group) && s.tab_index >= 0 {
		tabs := msg_id(s.tab_group, 'windows')
		count := int(msg_u64(tabs, 'count'))
		if count > 0 {
			idx := if s.tab_index == 0 { 0 } else if s.tab_index <= count { s.tab_index - 1 } else { count - 1 }
			anchor := msg_id_u64(tabs, 'objectAtIndex:', u64(idx))
			msg_void2(anchor, 'addTabbedWindow:ordered:', s.window, ObjId(if s.tab_index == 0 || s.tab_index > count { -1 } else { 1 }))
		}
	}
	if !is_nil(responder) { msg_bool1(s.window, 'makeFirstResponder:', responder) }
	s.saved = false
	msg_void(s.toolbar, 'release')
	msg_void(s.tab_group, 'release')
	msg_void1(s.window, 'makeKeyAndOrderFront:', nil_obj())
	fullscreen_post(&s, false)
}
pub fn toggle_fullscreen_mode(view voidptr, mode NativeFullscreenMode) {
	window := msg_id(view, 'window')
	if is_nil(window) { return }
	mut state := g_fullscreen_states[u64(window)] or { make_fullscreen_state(window) }
	g_fullscreen_states[u64(window)] = state
	if state.is_active() {
		state.exit()
		state.mode = mode
		return
	}
	state.mode = mode
	state.enter()
}
pub fn exit_fullscreen(view voidptr) {
	window := msg_id(view, 'window')
	if mut s := g_fullscreen_states[u64(window)] { s.exit() }
}

fn view_contains_class(view ObjId, name string) bool {
	if objc_utf8_string(msg_id(view, 'className')) == name { return true }
	children := msg_id(view, 'subviews')
	for i in 0 .. int(msg_u64(children, 'count')) { if view_contains_class(msg_id_u64(children, 'objectAtIndex:', u64(i)), name) { return true } }
	return false
}
fn is_tab_bar_accessory(accessory ObjId) bool {
	identifier := msg_id(accessory, 'identifier')
	if !is_nil(identifier) { return objc_utf8_string(identifier) == '_ghosttyTabBar' }
	view := msg_id(accessory, 'view')
	if view_contains_class(view, 'NSTabBar') { return true }
	return msg_u64(accessory, 'layoutAttribute') == 4 && objc_utf8_string(msg_id(view, 'className')) == 'NSView' && msg_u64(msg_id(view, 'subviews'), 'count') == 0
}
