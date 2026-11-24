@[has_globals]
module macos

import os
import input

// AppKit/Metal bindings for Witty, implemented from V through the macOS
// Objective-C runtime bridge that ships with vlib.

#flag darwin -framework AppKit

#flag darwin -framework Foundation

#flag darwin -framework CoreText

#flag darwin -framework CoreFoundation

#flag darwin -framework CoreGraphics

#flag darwin -framework Metal

#flag darwin -framework QuartzCore

#flag darwin -lobjc

#insert "@VMODROOT/macos/appkit_bridge.h"

// Callback types. Each callback receives the view's userdata pointer first.
pub type DrawCallback = fn (userdata voidptr, ctx voidptr, width f64, height f64)

pub type KeyCallback = fn (userdata voidptr, event voidptr, action input.KeyAction, keycode u16, modflags u64, chars &u8, len int, uchars &u8, ulen int)

pub type ResizeCallback = fn (userdata voidptr, width f64, height f64)

pub type DisplayCallback = fn (userdata voidptr, display_id u32)

pub type ReadyCallback = fn ()

pub type PasteCallback = fn (userdata voidptr, text &u8, len int)

pub type ActionCallback = fn (userdata voidptr, action_id int)

pub type MouseCallback = fn (userdata voidptr, event_type int, x f64, y f64, modflags u64, button_number i64) bool

pub type ScrollCallback = fn (userdata voidptr, x f64, y f64, scroll_mods int)

pub type PressureCallback = fn (userdata voidptr, stage u32, pressure f64)

pub type FocusCallback = fn (userdata voidptr, focused bool)

pub type AppFocusCallback = fn (focused bool)

pub type KeyboardChangedCallback = fn ()

pub type AppBoolCallback = fn () bool

const vt_action_copy = 1
const vt_action_select_all = 2
const vt_action_new_tab = 3
const vt_action_close_tab = 4

const ns_application_activation_policy_regular = u64(0)
const ns_application_activation_policy_prohibited = u64(2)
const ns_backing_store_buffered = u64(2)
const ns_window_above = u64(1)
const ns_window_tabbing_mode_automatic = u64(1)
const ns_window_style_titled = u64(1 << 0)
const ns_window_style_closable = u64(1 << 1)
const ns_window_style_miniaturizable = u64(1 << 2)
const ns_window_style_resizable = u64(1 << 3)
const ns_window_collection_behavior_full_screen_primary = u64(1 << 7)
const ns_event_modifier_flag_control = u64(1 << 18)
const ns_event_modifier_flag_option = u64(1 << 19)
const ns_event_modifier_flag_command = u64(1 << 20)
const ns_event_modifier_flag_caps_lock = u64(1 << 16)
const ns_event_modifier_flag_shift = u64(1 << 17)
const ns_event_modifier_flag_device_independent_mask = u64(0xffff0000)
const nx_device_rshift_key_mask = u64(0x00000004)
const nx_device_rcmd_key_mask = u64(0x00000010)
const nx_device_ralt_key_mask = u64(0x00000040)
const nx_device_rctl_key_mask = u64(0x00002000)
const ns_tracking_mouse_entered_and_exited = u64(0x01)
const ns_tracking_mouse_moved = u64(0x02)
const ns_tracking_active_always = u64(0x80)
const ns_tracking_in_visible_rect = u64(0x200)
const ns_alert_style_warning = u64(2)
const ns_alert_first_button_return = i64(1000)
const objc_assoc_copy_nonatomic = uint(3)
const mtl_pixel_format_bgra8unorm = u64(80)

__global (
	g_draw_cb              DrawCallback
	g_key_cb               KeyCallback
	g_resize_cb            ResizeCallback
	g_display_cb           DisplayCallback
	g_ready_cb             ReadyCallback
	g_paste_cb             PasteCallback
	g_action_cb            ActionCallback
	g_mouse_cb             MouseCallback
	g_scroll_cb            ScrollCallback
	g_pressure_cb          PressureCallback
	g_focus_cb             FocusCallback
	g_app_focus_cb         AppFocusCallback
	g_keyboard_change_cb   KeyboardChangedCallback
	g_should_quit_cb       AppBoolCallback
	g_should_terminate_cb  AppBoolCallback
	g_reopen_cb            AppBoolCallback
	g_app_terminating      bool
	g_classes_registered   bool
	g_window               ObjId
	g_delegate             ObjId
	g_selection_pasteboard ObjId
	g_base_title_key       int
	g_config_menu_items    map[string]ObjId
)

pub fn set_window_background_blur(window voidptr, radius i16) {
	C.witty_macos_set_window_background_blur(window, int(radius))
}

@[inline]
fn shared_app() ObjId {
	return msg_id(get_class('NSApplication'), 'sharedApplication')
}

fn add_method(cls ObjId, name string, imp voidptr, types string) {
	C.macos_class_add_method(cls, sel(name), imp, cstr(types))
}

fn add_ptr_ivar(cls ObjId, name string) {
	C.macos_class_add_ivar(cls, cstr(name), uint(8), u8(3), cstr('^v'))
}

fn register_classes() {
	if g_classes_registered {
		return
	}
	g_classes_registered = true

	mut view_cls := get_class('VTTerminalView')
	if is_nil(view_cls) {
		view_cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('VTTerminalView'), 0)
		add_ptr_ivar(view_cls, 'vtUserdata')
		add_ptr_ivar(view_cls, 'metalDevice')
		add_ptr_ivar(view_cls, 'metalQueue')
		add_ptr_ivar(view_cls, 'metalLayer')
		add_method(view_cls, 'isFlipped', voidptr(vt_view_is_flipped), 'B@:')
		add_method(view_cls, 'acceptsFirstResponder', voidptr(vt_view_accepts_first_responder), 'B@:')
		add_method(view_cls, 'canBecomeKeyView', voidptr(vt_view_can_become_key_view), 'B@:')
		add_method(view_cls, 'becomeFirstResponder', voidptr(vt_view_become_first_responder), 'B@:')
		add_method(view_cls, 'resignFirstResponder', voidptr(vt_view_resign_first_responder), 'B@:')
		add_method(view_cls, 'updateTrackingAreas', voidptr(vt_view_update_tracking_areas), 'v@:')
		add_method(view_cls, 'viewDidChangeBackingProperties', voidptr(vt_view_backing_changed), 'v@:')
		add_method(view_cls, 'drawRect:', voidptr(vt_view_draw_rect), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(view_cls, 'keyDown:', voidptr(vt_view_key_down), 'v@:@')
		add_method(view_cls, 'keyUp:', voidptr(vt_view_key_up), 'v@:@')
		add_method(view_cls, 'flagsChanged:', voidptr(vt_view_flags_changed), 'v@:@')
		add_method(view_cls, 'mouseDown:', voidptr(vt_view_mouse_down), 'v@:@')
		add_method(view_cls, 'mouseUp:', voidptr(vt_view_mouse_up), 'v@:@')
		add_method(view_cls, 'mouseDragged:', voidptr(vt_view_mouse_dragged), 'v@:@')
		add_method(view_cls, 'rightMouseDown:', voidptr(vt_view_right_mouse_down), 'v@:@')
		add_method(view_cls, 'rightMouseUp:', voidptr(vt_view_right_mouse_up), 'v@:@')
		add_method(view_cls, 'rightMouseDragged:', voidptr(vt_view_right_mouse_dragged), 'v@:@')
		add_method(view_cls, 'otherMouseDown:', voidptr(vt_view_other_mouse_down), 'v@:@')
		add_method(view_cls, 'otherMouseUp:', voidptr(vt_view_other_mouse_up), 'v@:@')
		add_method(view_cls, 'otherMouseDragged:', voidptr(vt_view_other_mouse_dragged), 'v@:@')
		add_method(view_cls, 'mouseEntered:', voidptr(vt_view_mouse_entered), 'v@:@')
		add_method(view_cls, 'mouseExited:', voidptr(vt_view_mouse_exited), 'v@:@')
		add_method(view_cls, 'mouseMoved:', voidptr(vt_view_mouse_moved), 'v@:@')
		add_method(view_cls, 'scrollWheel:', voidptr(vt_view_scroll_wheel), 'v@:@')
		add_method(view_cls, 'pressureChangeWithEvent:', voidptr(vt_view_pressure_change), 'v@:@')
		add_method(view_cls, 'vtFrameDidChange:', voidptr(vt_view_frame_did_change), 'v@:@')
		add_method(view_cls, 'vtScreenDidChange:', voidptr(vt_view_screen_did_change), 'v@:@')
		add_method(view_cls, 'copy:', voidptr(vt_view_copy), 'v@:@')
		add_method(view_cls, 'paste:', voidptr(vt_view_paste), 'v@:@')
		add_method(view_cls, 'selectAll:', voidptr(vt_view_select_all), 'v@:@')
		add_method(view_cls, 'vtNewTab:', voidptr(vt_view_new_tab), 'v@:@')
		add_method(view_cls, 'vtCloseTab:', voidptr(vt_view_close_tab), 'v@:@')
		register_input_methods(view_cls)
		register_terminal_interfaces(view_cls)
		C.macos_objc_register_class_pair(view_cls)
	}

	mut delegate_cls := get_class('VTAppDelegate')
	if is_nil(delegate_cls) {
		delegate_cls = C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('VTAppDelegate'), 0)
		proto := get_protocol('NSApplicationDelegate')
		if !is_nil(proto) {
			C.macos_class_add_protocol(delegate_cls, proto)
		}
		window_proto := get_protocol('NSWindowDelegate')
		if !is_nil(window_proto) {
			C.macos_class_add_protocol(delegate_cls, window_proto)
		}
		add_method(delegate_cls, 'applicationDidFinishLaunching:', voidptr(vt_app_did_finish_launching), 'v@:@')
		add_method(delegate_cls, 'applicationDidBecomeActive:', voidptr(vt_app_did_become_active), 'v@:@')
		add_method(delegate_cls, 'applicationDidHide:', voidptr(vt_app_did_hide), 'v@:@')
		add_method(delegate_cls, 'applicationDidResignActive:', voidptr(vt_app_did_resign_active), 'v@:@')
		add_method(delegate_cls, 'vtKeyboardSelectionDidChange:', voidptr(vt_keyboard_selection_did_change), 'v@:@')
		add_method(delegate_cls, 'applicationShouldTerminateAfterLastWindowClosed:', voidptr(vt_app_should_terminate_after_last_window_closed), 'B@:@')
		add_method(delegate_cls, 'applicationShouldTerminate:', voidptr(vt_app_should_terminate), 'Q@:@')
		add_method(delegate_cls, 'applicationShouldHandleReopen:hasVisibleWindows:', voidptr(vt_app_should_handle_reopen), 'B@:@B')
		add_method(delegate_cls, 'applicationWillTerminate:', voidptr(vt_app_will_terminate), 'v@:@')
		add_method(delegate_cls, 'windowShouldClose:', voidptr(vt_window_should_close), 'B@:@')
		register_native_undo_methods(delegate_cls)
		register_native_restoration_methods(delegate_cls)
		register_native_window_delegate_methods(delegate_cls)
		C.macos_objc_register_class_pair(delegate_cls)
	}
}

fn vt_view_is_flipped(_self ObjId, _cmd Sel) bool {
	// SurfaceView_AppKit inherits NSView's bottom-left coordinate system.
	return false
}

fn vt_view_accepts_first_responder(_self ObjId, _cmd Sel) bool {
	return true
}

fn vt_view_can_become_key_view(_self ObjId, _cmd Sel) bool {
	return true
}

fn dispatch_focus(view ObjId, focused bool) {
	if g_focus_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(view)
	if !is_nil(userdata) {
		g_focus_cb(userdata, focused)
	}
}

fn vt_view_become_first_responder(self ObjId, _cmd Sel) bool {
	result := view_super_bool(self, 'VTTerminalView', 'becomeFirstResponder')
	if result {
		dispatch_focus(self, true)
	}
	return result
}

fn vt_view_resign_first_responder(self ObjId, _cmd Sel) bool {
	result := view_super_bool(self, 'VTTerminalView', 'resignFirstResponder')
	if result {
		dispatch_focus(self, false)
	}
	return result
}

fn setup_view_tracking(view ObjId) {
	areas := msg_id(view, 'trackingAreas')
	count := int(msg_u64(areas, 'count'))
	for i in 0 .. count {
		area := msg_id_u64(areas, 'objectAtIndex:', u64(i))
		msg_void1(view, 'removeTrackingArea:', area)
	}
	options := ns_tracking_mouse_entered_and_exited | ns_tracking_mouse_moved | ns_tracking_in_visible_rect | ns_tracking_active_always
	area := msg_id_rect_u64_obj_obj(alloc('NSTrackingArea'), 'initWithRect:options:owner:userInfo:', msg_rect(view, 'bounds'), options, view, nil_obj())
	if !is_nil(area) {
		msg_void1(view, 'addTrackingArea:', area)
		msg_void(area, 'release')
	}
}

fn vt_view_update_tracking_areas(self ObjId, _cmd Sel) {
	view_super_void(self, 'VTTerminalView', 'updateTrackingAreas')
	setup_view_tracking(self)
}

fn vt_view_backing_changed(self ObjId, _cmd Sel) {
	view_super_void(self, 'VTTerminalView', 'viewDidChangeBackingProperties')
	vt_view_frame_did_change(self, unsafe { nil }, unsafe { nil })
}

fn vt_view_draw_rect(self ObjId, _cmd Sel, _dirty_rect ObjCRect) {
	if g_draw_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(self)
	if is_nil(userdata) {
		return
	}
	ns_context := msg_id(get_class('NSGraphicsContext'), 'currentContext')
	ctx := msg_id(ns_context, 'CGContext')
	bounds := msg_rect(self, 'bounds')
	g_draw_cb(userdata, voidptr(ctx), bounds.width, bounds.height)
}

fn vt_view_key_down(self ObjId, _cmd Sel, event ObjId) {
	input_key_down(self, event)
}

fn vt_view_key_up(self ObjId, _cmd Sel, event ObjId) {
	input_key_action(self, event, event, .release, none, false)
}

fn vt_view_flags_changed(self ObjId, _cmd Sel, event ObjId) {
	keycode := u16(msg_u64(event, 'keyCode'))
	flags := msg_u64(event, 'modifierFlags')
	action := modifier_key_action(keycode, flags) or { return }
	input_key_action(self, event, event, action, none, false)
}

// modifier_key_action translates AppKit's flagsChanged event into a press or
// release. The logical modifier bit alone is insufficient for right-side keys:
// it stays set while the opposite side remains held, so consult the legacy
// device-specific mask for those keycodes as the AppKit frontend does.
fn modifier_key_action(keycode u16, flags u64) ?input.KeyAction {
	logical_mask := match keycode {
		0x39 { ns_event_modifier_flag_caps_lock }
		0x38, 0x3c { ns_event_modifier_flag_shift }
		0x3b, 0x3e { ns_event_modifier_flag_control }
		0x3a, 0x3d { ns_event_modifier_flag_option }
		0x37, 0x36 { ns_event_modifier_flag_command }
		else {
			return none
		}
	}

	if flags & logical_mask == 0 {
		return .release
	}

	side_pressed := match keycode {
		0x3c { flags & nx_device_rshift_key_mask != 0 }
		0x3e { flags & nx_device_rctl_key_mask != 0 }
		0x3d { flags & nx_device_ralt_key_mask != 0 }
		0x36 { flags & nx_device_rcmd_key_mask != 0 }
		else { true }
	}
	return if side_pressed { input.KeyAction.press } else { input.KeyAction.release }
}

fn dispatch_key(self ObjId, event ObjId, action input.KeyAction) {
	if g_key_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(self)
	if is_nil(userdata) {
		return
	}
	keycode := u16(msg_u64(event, 'keyCode'))
	flags := msg_u64(event, 'modifierFlags')
	chars := objc_utf8_string(msg_id(event, 'characters'))
	uchars := objc_utf8_string(msg_id(event, 'charactersIgnoringModifiers'))
	g_key_cb(userdata, voidptr(event), action, keycode, flags, chars.str, chars.len, uchars.str, uchars.len)
}

fn vt_view_mouse_down(self ObjId, _cmd Sel, event ObjId) {
	dispatch_mouse(self, event, 0)
}

fn vt_view_mouse_up(self ObjId, _cmd Sel, event ObjId) {
	dispatch_mouse(self, event, 1)
	dispatch_pressure(self, 0, 0)
}

fn vt_view_mouse_dragged(self ObjId, _cmd Sel, event ObjId) {
	dispatch_mouse(self, event, 7)
}

fn vt_view_right_mouse_down(self ObjId, _cmd Sel, event ObjId) {
	if !dispatch_mouse(self, event, 3) {
		view_super_void1(self, 'VTTerminalView', 'rightMouseDown:', event)
	}
}

fn vt_view_right_mouse_up(self ObjId, _cmd Sel, event ObjId) {
	if !dispatch_mouse(self, event, 4) {
		view_super_void1(self, 'VTTerminalView', 'rightMouseUp:', event)
	}
}

fn vt_view_other_mouse_down(self ObjId, _cmd Sel, event ObjId) {
	dispatch_mouse(self, event, 5)
}

fn vt_view_other_mouse_up(self ObjId, _cmd Sel, event ObjId) {
	dispatch_mouse(self, event, 6)
}

fn vt_view_mouse_entered(self ObjId, _cmd Sel, event ObjId) {
	view_super_void1(self, 'VTTerminalView', 'mouseEntered:', event)
	dispatch_mouse(self, event, 2)
}

fn vt_view_mouse_exited(self ObjId, _cmd Sel, event ObjId) {
	if msg_u64(get_class('NSEvent'), 'pressedMouseButtons') != 0 {
		return
	}
	dispatch_mouse_at(self, event, 2, -1, -1)
}

fn vt_view_mouse_moved(self ObjId, _cmd Sel, event ObjId) {
	dispatch_mouse(self, event, 7)
}

fn vt_view_right_mouse_dragged(self ObjId, _cmd Sel, event ObjId) {
	vt_view_mouse_moved(self, unsafe { nil }, event)
}

fn vt_view_other_mouse_dragged(self ObjId, _cmd Sel, event ObjId) {
	vt_view_mouse_moved(self, unsafe { nil }, event)
}

fn scroll_momentum(raw u64) input.Momentum {
	return match raw {
		1 { .began }
		2 { .stationary }
		4 { .changed }
		8 { .ended }
		16 { .cancelled }
		32 { .may_begin }
		else { .none_ }
	}
}

fn vt_view_scroll_wheel(self ObjId, _cmd Sel, event ObjId) {
	if g_scroll_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(self)
	if is_nil(userdata) {
		return
	}
	precision := msg_bool(event, 'hasPreciseScrollingDeltas')
	mut x := msg_f64(event, 'scrollingDeltaX')
	mut y := msg_f64(event, 'scrollingDeltaY')
	if precision {
		x *= 2
		y *= 2
	}
	mods := input.ScrollMods.init(precision, scroll_momentum(msg_u64(event, 'momentumPhase')))
	g_scroll_cb(userdata, x, y, int(mods.int()))
}

fn dispatch_pressure(view ObjId, stage u32, pressure f64) {
	if g_pressure_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(view)
	if !is_nil(userdata) {
		g_pressure_cb(userdata, stage, pressure)
	}
}

fn vt_view_pressure_change(self ObjId, _cmd Sel, event ObjId) {
	dispatch_pressure(self, u32(msg_u64(event, 'stage')), msg_f64(event, 'pressure'))
}

fn dispatch_mouse_at(view ObjId, event ObjId, event_type int, x f64, y f64) bool {
	if g_mouse_cb == unsafe { nil } {
		return false
	}
	userdata := view_userdata(view)
	if is_nil(userdata) {
		return false
	}
	return g_mouse_cb(userdata, event_type, x, y, msg_u64(event, 'modifierFlags'), msg_i64(event, 'buttonNumber'))
}

fn dispatch_mouse(view ObjId, event ObjId, event_type int) bool {
	window_point := msg_point(event, 'locationInWindow')
	point := msg_point_point_obj(view, 'convertPoint:fromView:', window_point, nil_obj())
	return dispatch_mouse_at(view, event, event_type, point.x, msg_rect(view, 'frame').height - point.y)
}

fn vt_view_frame_did_change(self ObjId, _cmd Sel, _notification ObjId) {
	if g_app_terminating {
		return
	}
	update_metal_drawable_size(self)
	if g_resize_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(self)
	if is_nil(userdata) {
		return
	}
	bounds := msg_rect(self, 'bounds')
	g_resize_cb(userdata, bounds.width, bounds.height)
}

fn vt_view_copy(self ObjId, _cmd Sel, _sender ObjId) {
	dispatch_action(self, vt_action_copy)
}

fn vt_view_paste(self ObjId, _cmd Sel, _sender ObjId) {
	if g_paste_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(self)
	if is_nil(userdata) {
		return
	}
	text := clipboard_get_text() or { return }
	if text.len > 0 {
		g_paste_cb(userdata, text.str, text.len)
	}
}

fn vt_view_select_all(self ObjId, _cmd Sel, _sender ObjId) {
	dispatch_action(self, vt_action_select_all)
}

fn vt_view_new_tab(self ObjId, _cmd Sel, _sender ObjId) {
	dispatch_action(self, vt_action_new_tab)
}

fn vt_view_close_tab(self ObjId, _cmd Sel, _sender ObjId) {
	dispatch_action(self, vt_action_close_tab)
}

fn dispatch_action(view ObjId, action_id int) {
	if g_action_cb == unsafe { nil } {
		return
	}
	userdata := view_userdata(view)
	if !is_nil(userdata) {
		g_action_cb(userdata, action_id)
	}
}

fn vt_app_did_finish_launching(_self ObjId, _cmd Sel, _notification ObjId) {
	app := shared_app()
	if msg_u64(app, 'activationPolicy') == ns_application_activation_policy_regular {
		msg_void_bool(app, 'activateIgnoringOtherApps:', true)
	}
	if g_ready_cb != unsafe { nil } {
		g_ready_cb()
	}
}

fn vt_app_did_become_active(_self ObjId, _cmd Sel, _notification ObjId) {
	first_activation:=!g_application_has_become_active
	g_application_has_become_active = true
	g_app_was_hidden = false
    clear_native_hidden_windows()
	if g_app_focus_cb != unsafe { nil } {
		g_app_focus_cb(true)
	}
	if first_activation && g_first_active_callback != unsafe { nil } { g_first_active_callback() }
}

fn vt_app_did_resign_active(_self ObjId, _cmd Sel, _notification ObjId) {
	if g_app_focus_cb != unsafe { nil } {
		g_app_focus_cb(false)
	}
}

fn vt_keyboard_selection_did_change(_self ObjId, _cmd Sel, _notification ObjId) {
	if g_keyboard_change_cb != unsafe { nil } {
		g_keyboard_change_cb()
	}
}

fn vt_window_should_close(_self ObjId, _cmd Sel, window ObjId) bool {
	view := terminal_view_for_window(window)
	if is_nil(view) || g_action_cb == unsafe { nil } {
		return true
	}
	userdata := view_userdata(view)
	if is_nil(userdata) {
		return true
	}
	g_action_cb(userdata, 5)
	return false
}

fn vt_app_should_terminate_after_last_window_closed(_self ObjId, _cmd Sel, _app ObjId) bool {
	if g_should_quit_cb != unsafe { nil } {
		return g_should_quit_cb()
	}
	return false
}

fn vt_app_should_terminate(_self ObjId, _cmd Sel, _app ObjId) u64 {
	if g_should_terminate_cb != unsafe { nil } && !g_should_terminate_cb() {
		return 0
	}
	g_app_terminating = true
	return 1
}

fn vt_app_should_handle_reopen(_self ObjId, _cmd Sel, _app ObjId, has_visible_windows bool) bool {
	if has_visible_windows {
		return true
	}
	if g_reopen_cb != unsafe { nil } {
		return g_reopen_cb()
	}
	return false
}

fn vt_app_will_terminate(_self ObjId, _cmd Sel, _notification ObjId) {
	g_app_terminating = true
}

fn display_title_for_input(title string) string {
	if title.len == 0 {
		return 'Witty'
	}
	return title
}

fn runtime_title_for_input(title string) string {
	return title
}

fn expand_tilde(path string) string {
	home := os.home_dir()
	if path == '~' {
		return home
	}
	if path.starts_with('~/') {
		return os.join_path(home, path[2..])
	}
	return path
}

fn abbrev_path(path string) string {
	home := os.home_dir()
	if home.len > 0 && path == home {
		return '~'
	}
	if home.len > 0 && path.starts_with(home + '/') {
		return '~/' + path[(home.len + 1)..]
	}
	return path
}

fn url_for_title(title string) ObjId {
	if title.len == 0 {
		return nil_obj()
	}
	expanded := expand_tilde(title)
	if !os.is_dir(expanded) {
		return nil_obj()
	}
	return msg_id1(get_class('NSURL'), 'fileURLWithPath:', nsstring(expanded))
}

fn base_title_key() voidptr {
	return voidptr(&g_base_title_key)
}

fn set_base_title(window ObjId, base string) {
	if is_nil(window) {
		return
	}
	C.macos_set_associated_object(window, base_title_key(), nsstring(base), objc_assoc_copy_nonatomic)
}

fn get_base_title(window ObjId) string {
	if is_nil(window) {
		return ''
	}
	value := C.macos_get_associated_object(window, base_title_key())
	return objc_utf8_string(value)
}

fn refresh_one_tab_label(tab ObjId, _tab_count int, _index int) {
 // TerminalController publishes the selected surface's title, independently
 // of the working-directory proxy URL and tab-index titlebar accessories.
 msg_void1(tab,'setTitle:',nsstring(get_base_title(tab)))
}

fn refresh_tab_labels(anchor_window ObjId) {
	if is_nil(anchor_window) {
		return
	}
	tabs := msg_id(anchor_window, 'tabbedWindows')
	count := int(msg_u64(tabs, 'count'))
	if is_nil(tabs) || count == 0 {
		refresh_one_tab_label(anchor_window, 1, 0)
		return
	}
	for i in 0 .. count {
		tab := msg_id_u64(tabs, 'objectAtIndex:', u64(i))
		refresh_one_tab_label(tab, count, i)
	}
}

fn configure_window_common(window ObjId, base_title string) {
	if is_nil(window) {
		return
	}
	msg_void_size(window, 'setMinSize:', objc_size(200, 100))
	msg_void_u64(window, 'setTabbingMode:', ns_window_tabbing_mode_automatic)
	msg_void1(window, 'setTabbingIdentifier:', nsstring('Witty.tabs'))
	msg_void_u64(window, 'setCollectionBehavior:', ns_window_collection_behavior_full_screen_primary)
	msg_void_bool(window, 'setTitlebarAppearsTransparent:', false)
	msg_void_bool(window, 'setMovableByWindowBackground:', false)
	if !is_nil(g_delegate) {
		msg_void1(window, 'setDelegate:', g_delegate)
	}
	set_base_title(window, base_title)
	msg_void1(window, 'setRepresentedURL:', nil_obj())
    apply_native_default_level(window)
}

fn menu_with_title(title string) ObjId {
	return msg_id1(alloc('NSMenu'), 'initWithTitle:', nsstring(title))
}

fn menu_item() ObjId {
	return msg_id(alloc('NSMenuItem'), 'init')
}

fn menu_add_item(menu ObjId, title string, action string, key string) ObjId {
	return msg_id_obj_sel_obj(menu, 'addItemWithTitle:action:keyEquivalent:', nsstring(title), sel(action), nsstring(key))
}

fn menu_add_separator(menu ObjId) {
	msg_void1(menu, 'addItem:', msg_id(get_class('NSMenuItem'), 'separatorItem'))
}

fn install_menu_bar() {
	menu_bar := msg_id(alloc('NSMenu'), 'init')

	app_menu_item := menu_item()
	msg_void1(menu_bar, 'addItem:', app_menu_item)
	app_menu := menu_with_title('Witty')
	menu_add_item(app_menu, 'About Witty', 'orderFrontStandardAboutPanel:', '')
	menu_add_separator(app_menu)
	menu_add_item(app_menu, 'Hide Witty', 'hide:', 'h')
	hide_others := menu_add_item(app_menu, 'Hide Others', 'hideOtherApplications:', 'h')
	msg_void_u64(hide_others, 'setKeyEquivalentModifierMask:', ns_event_modifier_flag_command | ns_event_modifier_flag_option)
	menu_add_item(app_menu, 'Show All', 'unhideAllApplications:', '')
	menu_add_separator(app_menu)
	register_config_menu_item(voidptr(menu_add_item(app_menu, 'Quit Witty', 'terminate:', '')), 'quit')
	msg_void1(app_menu_item, 'setSubmenu:', app_menu)

	file_menu_item := menu_item()
	msg_void1(menu_bar, 'addItem:', file_menu_item)
	file_menu := menu_with_title('File')
	register_config_menu_item(voidptr(menu_add_item(file_menu, 'New Tab', 'vtNewTab:', '')), 'new_tab')
	register_config_menu_item(voidptr(menu_add_item(file_menu, 'Close Tab', 'vtCloseTab:', '')), 'close_tab')
	msg_void1(file_menu_item, 'setSubmenu:', file_menu)

	edit_menu_item := menu_item()
	msg_void1(menu_bar, 'addItem:', edit_menu_item)
	edit_menu := menu_with_title('Edit')
	register_config_menu_item(voidptr(menu_add_item(edit_menu, 'Copy', 'copy:', '')), 'copy_to_clipboard')
	register_config_menu_item(voidptr(menu_add_item(edit_menu, 'Paste', 'paste:', '')), 'paste_from_clipboard')
	register_config_menu_item(voidptr(menu_add_item(edit_menu, 'Select All', 'selectAll:', '')), 'select_all')
	msg_void1(edit_menu_item, 'setSubmenu:', edit_menu)

	view_menu_item := menu_item()
	msg_void1(menu_bar, 'addItem:', view_menu_item)
	view_menu := menu_with_title('View')
	fullscreen := menu_add_item(view_menu, 'Toggle Full Screen', 'toggleFullScreen:', 'f')
	msg_void_u64(fullscreen, 'setKeyEquivalentModifierMask:', ns_event_modifier_flag_command | ns_event_modifier_flag_control)
	msg_void1(view_menu_item, 'setSubmenu:', view_menu)

	window_menu_item := menu_item()
	msg_void1(menu_bar, 'addItem:', window_menu_item)
	window_menu := menu_with_title('Window')
	menu_add_item(window_menu, 'Minimize', 'performMiniaturize:', 'm')
	menu_add_item(window_menu, 'Zoom', 'performZoom:', '')
	menu_add_separator(window_menu)
	register_config_menu_item(voidptr(menu_add_item(window_menu, 'Show Previous Tab', 'selectPreviousTab:', '')), 'previous_tab')
	register_config_menu_item(voidptr(menu_add_item(window_menu, 'Show Next Tab', 'selectNextTab:', '')), 'next_tab')
	menu_add_separator(window_menu)
	menu_add_item(window_menu, 'Bring All to Front', 'arrangeInFront:', '')
	msg_void1(window_menu_item, 'setSubmenu:', window_menu)

	install_native_action_menu(app_menu,file_menu,edit_menu,view_menu,window_menu)
	app := shared_app()
	msg_void1(app, 'setWindowsMenu:', window_menu)
	msg_void1(app, 'setMainMenu:', menu_bar)
}

fn setup_view_notifications(view ObjId) {
	msg_void_bool(view, 'setPostsFrameChangedNotifications:', true)
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	C.witty_macos_observe(center, view, sel('vtFrameDidChange:'), nsstring('NSViewFrameDidChangeNotification'), view)
	C.witty_macos_observe(center, view, sel('vtScreenDidChange:'), nsstring('NSWindowDidChangeScreenNotification'), nil_obj())
}

fn refresh_screen_backing(view voidptr) {
	vt_view_backing_changed(ObjId(view), nil_obj())
}

fn vt_view_screen_did_change(self ObjId, _cmd Sel, notification ObjId) {
	window := msg_id(self, 'window')
	if is_nil(window) || msg_id(notification, 'object') != window {
		return
	}
	screen := msg_id(window, 'screen')
	if is_nil(screen) || is_nil(view_userdata(self)) {
		return
	}
	if g_display_cb != unsafe { nil } {
		g_display_cb(view_userdata(self), view_display_id(voidptr(self)))
	}
	// Preserve DispatchQueue.main.async's [weak self] capture from Swift.
	C.witty_macos_dispatch_main_weak(voidptr(self), voidptr(refresh_screen_backing))
}

pub fn view_display_id(view voidptr) u32 {
	screen := msg_id(msg_id(ObjId(view), 'window'), 'screen')
	device := msg_id(screen, 'deviceDescription')
	value := msg_id1(device, 'objectForKey:', nsstring('NSScreenNumber'))
	return u32(msg_u64(value, 'unsignedIntValue'))
}

pub fn set_display_callback(cb DisplayCallback) {
	g_display_cb = cb
}

fn setup_view_metal(view ObjId) {
	device := C.MTLCreateSystemDefaultDevice()
	if is_nil(device) {
		return
	}
	queue := msg_id(device, 'newCommandQueue')
	layer := new_obj('CAMetalLayer')
	msg_void1(layer, 'setDevice:', device)
	msg_void_u64(layer, 'setPixelFormat:', mtl_pixel_format_bgra8unorm)
	msg_void_bool(layer, 'setFramebufferOnly:', true)
	screen := msg_id(get_class('NSScreen'), 'mainScreen')
	scale := msg_f64(screen, 'backingScaleFactor')
	msg_void_f64(layer, 'setContentsScale:', if scale > 0 { scale } else { 1.0 })
	C.macos_objc_set_ptr_ivar(view, cstr('metalDevice'), device)
	C.macos_objc_set_ptr_ivar(view, cstr('metalQueue'), queue)
	C.macos_objc_set_ptr_ivar(view, cstr('metalLayer'), layer)
	update_metal_drawable_size(view)
}

fn create_terminal_view(frame ObjCRect) ObjId {
	view := msg_id_rect(alloc('VTTerminalView'), 'initWithFrame:', frame)
	setup_terminal_interfaces(view)
	setup_view_metal(view)
	setup_view_notifications(view)
	setup_view_tracking(view)
	return view
}

// create_offscreen_terminal_view constructs the same native view used by a
// window without attaching it to an NSWindow. Renderer integration tests use
// this to exercise the real Metal surface lifecycle without showing UI.
pub fn create_offscreen_terminal_view(w int, h int) voidptr {
	register_classes()
	return voidptr(create_terminal_view(objc_rect(0, 0, f64(w), f64(h))))
}

pub fn release_offscreen_terminal_view(view voidptr) {
	if !is_nil(view) {
		msg_void(ObjId(view), 'release')
	}
}

fn update_metal_drawable_size(view ObjId) {
	stored_layer := ObjId(C.macos_objc_get_ptr_ivar(view, cstr('metalLayer')))
	active_layer := msg_id(view, 'layer')
	if is_nil(stored_layer) && is_nil(active_layer) {
		return
	}
	bounds := msg_rect(view, 'bounds')
	mut scale := if !is_nil(active_layer) {
		msg_f64(active_layer, 'contentsScale')
	} else {
		msg_f64(stored_layer, 'contentsScale')
	}
	if scale <= 0 {
		scale = 1
	}
	if !is_nil(active_layer) {
		msg_void_rect(active_layer, 'setFrame:', bounds)
	}
	// The original view-owned layer is a CAMetalLayer. Once the renderer
	// installs Ghostty's IOSurface layer, the active layer intentionally has
	// no drawableSize property and is sized through its frame instead.
	if !is_nil(stored_layer)
		&& msg_bool1(stored_layer, 'respondsToSelector:', sel('setDrawableSize:')) {
		msg_void_size(stored_layer, 'setDrawableSize:', objc_size(bounds.width * scale, bounds.height * scale))
	}
}

// V-friendly wrappers.
pub fn app_init() {
	init_app(ns_application_activation_policy_regular)
}

pub fn app_init_for_capture() {
	init_app(ns_application_activation_policy_prohibited)
}

fn init_app(activation_policy u64) {
	register_classes()
	app := shared_app()
	msg_void_u64(app, 'setActivationPolicy:', activation_policy)
	msg_void_bool(get_class('NSWindow'), 'setAllowsAutomaticWindowTabbing:', true)
	install_menu_bar()
	install_command_release_monitor()
	g_delegate = msg_id(alloc('VTAppDelegate'), 'init')
	msg_void1(app, 'setDelegate:', g_delegate)
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	C.witty_macos_observe(center, g_delegate, sel('vtKeyboardSelectionDidChange:'), nsstring('NSTextInputContextKeyboardSelectionDidChangeNotification'), nil_obj())
}

pub fn app_run() {
	msg_void(shared_app(), 'run')
}

pub fn app_terminate() {
	msg_void1(shared_app(), 'terminate:', nil_obj())
}

pub fn app_is_active() bool {
	return msg_bool(shared_app(), 'isActive')
}

pub fn create_window(w int, h int, title string) voidptr {
	return create_native_window(w,h,title,true)
}
pub fn create_restorable_window(w int,h int,title string) voidptr { return create_native_window(w,h,title,false) }
fn create_native_window(w int,h int,title string,show bool) voidptr {
	register_classes()
	frame := objc_rect(100, 100, f64(w), f64(h))
	style := ns_window_style_titled | ns_window_style_closable | ns_window_style_miniaturizable | ns_window_style_resizable
	base_title := display_title_for_input(title)

	window := msg_id_rect_u64_u64_bool(msg_id(native_window_class(), 'alloc'), 'initWithContentRect:styleMask:backing:defer:', frame, style, ns_backing_store_buffered, false)
	// NSWindowController owns this lifetime in the source. The translated host
	// releases the allocated window after close_one_controller detaches its tree.
	msg_void_bool(window,'setReleasedWhenClosed:',false)
	g_window = window
	configure_window_common(window, base_title)

	view := create_terminal_view(frame)
	msg_void1(window, 'setContentView:', view)
	msg_void1(window, 'setInitialFirstResponder:', view)
	msg_bool1(window, 'makeFirstResponder:', view)
	if show { msg_void1(window, 'makeKeyAndOrderFront:', nil_obj()) }
	refresh_tab_labels(window)
	return view
}

pub fn set_draw_callback(cb DrawCallback) {
	g_draw_cb = cb
}

pub fn set_key_callback(cb KeyCallback) {
	g_key_cb = cb
}

pub fn set_resize_callback(cb ResizeCallback) {
	g_resize_cb = cb
}

pub fn set_ready_callback(cb ReadyCallback) {
	g_ready_cb = cb
}

pub fn set_paste_callback(cb PasteCallback) {
	g_paste_cb = cb
}

pub fn set_action_callback(cb ActionCallback) {
	g_action_cb = cb
}

pub fn set_mouse_callback(cb MouseCallback) {
	g_mouse_cb = cb
}

pub fn set_scroll_callback(cb ScrollCallback) {
	g_scroll_cb = cb
}

pub fn set_pressure_callback(cb PressureCallback) {
	g_pressure_cb = cb
}

pub fn set_focus_callback(cb FocusCallback) {
	g_focus_cb = cb
}

pub fn set_app_focus_callback(cb AppFocusCallback) {
	g_app_focus_cb = cb
}

pub fn set_keyboard_changed_callback(cb KeyboardChangedCallback) {
	g_keyboard_change_cb = cb
}

pub fn set_should_quit_after_last_window_callback(cb AppBoolCallback) {
	g_should_quit_cb = cb
}

pub fn set_should_terminate_callback(cb AppBoolCallback) {
	g_should_terminate_cb = cb
}

pub fn set_reopen_callback(cb AppBoolCallback) {
	g_reopen_cb = cb
}

fn clipboard_for(clipboard_type int) ObjId {
	return match clipboard_type {
		0 { msg_id(get_class('NSPasteboard'), 'generalPasteboard') }
		1 {
			if is_nil(g_selection_pasteboard) {
				pasteboard := msg_id1(get_class('NSPasteboard'), 'pasteboardWithName:', nsstring('com.alexander.witty.selection'))
				g_selection_pasteboard = msg_id(pasteboard, 'retain')
			}
			g_selection_pasteboard
		}
		else { nil_obj() }
	}
}

pub fn clipboard_clear(clipboard_type int) bool {
	pasteboard := clipboard_for(clipboard_type)
	if is_nil(pasteboard) {
		return false
	}
	msg_void(pasteboard, 'clearContents')
	return true
}

pub fn clipboard_set_value(clipboard_type int, mime string, data string) bool {
	pasteboard := clipboard_for(clipboard_type)
	if is_nil(pasteboard) {
		return false
	}
	return msg_bool2(pasteboard, 'setString:forType:', nsstring(data), clipboard_type_for_mime(mime))
}

pub fn clipboard_declare_types(clipboard_type int, mimes []string) bool {
	pasteboard := clipboard_for(clipboard_type)
	if is_nil(pasteboard) { return false }
	types := msg_id(msg_id(alloc('NSMutableArray'), 'init'), 'autorelease')
	for mime in mimes { msg_void1(types, 'addObject:', clipboard_type_for_mime(mime)) }
	msg_id2(pasteboard, 'declareTypes:owner:', types, nil_obj())
	return true
}

// NSPasteboard.PasteboardType(mimeType:) prefers the Uniform Type Identifier
// for any recognized MIME type, including dynamically generated identifiers.
fn clipboard_type_for_mime(mime string) ObjId {
	if mime == 'text/plain' { return nsstring('public.utf8-plain-text') }
	type_ := msg_id1(get_class('UTType'), 'typeWithMIMEType:', nsstring(mime))
	return if is_nil(type_) { nsstring(mime) } else { msg_id(type_, 'identifier') }
}

pub fn clipboard_set_text(text string) {
	if text.len == 0 || !clipboard_clear(0) {
		return
	}
	clipboard_set_value(0, 'text/plain', text)
}

pub fn clipboard_get_text_for(clipboard_type int) ?string {
	pasteboard := clipboard_for(clipboard_type)
	if is_nil(pasteboard) {
		return none
	}
	return opinionated_pasteboard_contents(pasteboard)
}

pub fn clipboard_get_text() ?string {
	return clipboard_get_text_for(0)
}

fn request_display_now(view voidptr) {
	if is_nil(view) {
		return
	}
	msg_void_bool(ObjId(view), 'setNeedsDisplay:', true)
}

fn request_display_main_task(ctx voidptr) {
	request_display_now(ctx)
}

pub fn dispatch_main(callback fn (voidptr), context voidptr) {
	C.witty_macos_dispatch_main(voidptr(callback), context)
}

pub fn request_display(view voidptr) {
	if is_nil(view) {
		return
	}
	if !C.witty_macos_is_main_thread() {
		C.witty_macos_dispatch_main(voidptr(request_display_main_task), view)
		return
	}
	request_display_now(view)
}

pub fn view_width(view voidptr) f64 {
	if is_nil(view) {
		return 0
	}
	return msg_rect(ObjId(view), 'bounds').width
}

pub fn view_height(view voidptr) f64 {
	if is_nil(view) {
		return 0
	}
	return msg_rect(ObjId(view), 'bounds').height
}

pub fn view_backing_scale(view voidptr) f64 {
	if is_nil(view) {
		return 1
	}
	window := msg_id(ObjId(view), 'window')
	scale := if is_nil(window) { f64(1) } else { msg_f64(window, 'backingScaleFactor') }
	return if scale > 0 { scale } else { 1 }
}

pub fn set_view_size(view voidptr, width f64, height f64) {
	if is_nil(view) || width <= 0 || height <= 0 {
		return
	}
	window := msg_id(ObjId(view), 'window')
	if !is_nil(window) {
		msg_void_size(window, 'setContentSize:', objc_size(width, height))
	}
}

pub fn toggle_fullscreen(view voidptr) {
	if is_nil(view) {
		return
	}
	window := msg_id(ObjId(view), 'window')
	if !is_nil(window) {
		msg_void1(window, 'toggleFullScreen:', nil_obj())
	}
}

pub fn present_view(view voidptr) {
	if is_nil(view) {
		return
	}
	window := msg_id(ObjId(view), 'window')
	if !is_nil(window) {
		msg_void1(window, 'makeKeyAndOrderFront:', nil_obj())
		move_focus(view, unsafe { nil }, none)
	}
}

pub fn open_url(url string) bool {
	if url.len == 0 {
		return false
	}
	workspace := msg_id(get_class('NSWorkspace'), 'sharedWorkspace')
	value := msg_id1(get_class('NSURL'), 'URLWithString:', nsstring(url))
	return !is_nil(value) && msg_bool1(workspace, 'openURL:', value)
}

// confirm_close presents Ghostty's close confirmation when a surface reports
// that its child process is still alive.
pub fn confirm_close(view voidptr) bool {
	if is_nil(view) {
		return true
	}
	window := msg_id(ObjId(view), 'window')
	if is_nil(window) {
		return true
	}
	alert := new_obj('NSAlert')
	if is_nil(alert) {
		return true
	}
	defer {
		msg_void(alert, 'release')
	}
	msg_void1(alert, 'setMessageText:', nsstring('Close Terminal?'))
	msg_void1(alert, 'setInformativeText:', nsstring('The terminal still has a running process. If you close the terminal the process will be killed.'))
	msg_id1(alert, 'addButtonWithTitle:', nsstring('Close'))
	msg_id1(alert, 'addButtonWithTitle:', nsstring('Cancel'))
	msg_void_u64(alert, 'setAlertStyle:', ns_alert_style_warning)
	return msg_i64(alert, 'runModal') == ns_alert_first_button_return
}

pub fn confirm_quit() bool {
	alert := new_obj('NSAlert')
	if is_nil(alert) {
		return true
	}
	defer {
		msg_void(alert, 'release')
	}
	msg_void1(alert, 'setMessageText:', nsstring('Quit Witty?'))
	msg_void1(alert, 'setInformativeText:', nsstring('All terminal sessions will be terminated.'))
	msg_id1(alert, 'addButtonWithTitle:', nsstring('Close Witty'))
	msg_id1(alert, 'addButtonWithTitle:', nsstring('Cancel'))
	msg_void_u64(alert, 'setAlertStyle:', ns_alert_style_warning)
	return msg_i64(alert, 'runModal') == ns_alert_first_button_return
}

pub fn confirm_clipboard(contents string, request int) bool {
	alert := new_obj('NSAlert')
	if is_nil(alert) {
		return false
	}
	defer {
		msg_void(alert, 'release')
	}
	mut title := 'Authorize Clipboard Access'
	mut reason := 'An application is attempting to write to the clipboard. The content to write is shown below.'
	mut confirm_title := 'Allow'
	mut cancel_title := 'Deny'
	match request {
		0 {
			title = 'Warning: Potentially Unsafe Paste'
			reason = 'Pasting this text to the terminal may be dangerous as it looks like some commands may be executed.'
			confirm_title = 'Paste'
			cancel_title = 'Cancel'
		}
		1 {
			reason = 'An application is attempting to read from the clipboard. The current clipboard contents are shown below.'
		}
		else {}
	}
	msg_void1(alert, 'setMessageText:', nsstring(title))
	msg_void1(alert, 'setInformativeText:', nsstring('${reason}\n\n${contents}'))
	msg_id1(alert, 'addButtonWithTitle:', nsstring(confirm_title))
	msg_id1(alert, 'addButtonWithTitle:', nsstring(cancel_title))
	msg_void_u64(alert, 'setAlertStyle:', ns_alert_style_warning)
	return msg_i64(alert, 'runModal') == ns_alert_first_button_return
}

// input_mods translates NSEvent.ModifierFlags using the same bit layout as
// Ghostty's Ghostty.ghosttyMods Swift adapter.
pub fn input_mods(flags u64) input.Mods {
	return input.Mods.init(flags & ns_event_modifier_flag_shift != 0, flags & ns_event_modifier_flag_control != 0, flags & ns_event_modifier_flag_option != 0, flags & ns_event_modifier_flag_command != 0, flags & ns_event_modifier_flag_caps_lock != 0, false, input.SideInfo.init(if flags & nx_device_rshift_key_mask != 0 {
		.right
	} else {
		.left
	}, if flags & nx_device_rctl_key_mask != 0 { .right } else { .left }, if flags & nx_device_ralt_key_mask != 0 {
		.right
	} else {
		.left
	}, if flags & nx_device_rcmd_key_mask != 0 { .right } else { .left }))
}

// event_characters applies a Ghostty modifier bitset to an NSEvent. This is
// the AppKit equivalent of characters(byApplyingModifiers:) used by Ghostty.
pub fn event_characters(event voidptr, mods int) string {
	if is_nil(event) {
		return ''
	}
	mut flags := u64(0)
	if mods & 1 != 0 {
		flags |= ns_event_modifier_flag_shift
	}
	if mods & 2 != 0 {
		flags |= ns_event_modifier_flag_control
	}
	if mods & 4 != 0 {
		flags |= ns_event_modifier_flag_option
	}
	if mods & 8 != 0 {
		flags |= ns_event_modifier_flag_command
	}
	return objc_utf8_string(msg_id_u64(ObjId(event), 'charactersByApplyingModifiers:', flags))
}

pub fn view_set_userdata(view voidptr, ptr voidptr) {
	obj := ObjId(view)
	if !is_nil(obj) {
		C.macos_objc_set_ptr_ivar(obj, cstr('vtUserdata'), ptr)
	}
}

fn view_userdata(view ObjId) voidptr {
	if is_nil(view) {
		return unsafe { nil }
	}
	return C.macos_objc_get_ptr_ivar(view, cstr('vtUserdata'))
}

pub fn view_get_userdata(view voidptr) voidptr {
	return view_userdata(ObjId(view))
}

pub fn create_font(name string, size f64) voidptr {
	return C.vt_create_font(cstr(name), size)
}

pub fn draw_text(ctx voidptr, text &u8, text_len int, font voidptr, x f64, y f64, fg_r f64, fg_g f64, fg_b f64) {
	C.vt_draw_text(ctx, text, text_len, font, x, y, fg_r, fg_g, fg_b)
}

pub fn new_tab(w int, h int, title string) voidptr {
	register_classes()
	app := shared_app()
	mut anchor := msg_id(app, 'keyWindow')
	if is_nil(anchor) {
		anchor = msg_id(app, 'mainWindow')
	}
	if is_nil(anchor) {
		anchor = g_window
	}
	if is_nil(anchor) {
		return unsafe { nil }
	}

	mut frame := objc_rect(100, 100, f64(w), f64(h))
	anchor_content := msg_id(anchor, 'contentView')
	if !is_nil(anchor_content) {
		bounds := msg_rect(anchor_content, 'bounds')
		if bounds.width > 0 && bounds.height > 0 {
			frame.width = bounds.width
			frame.height = bounds.height
		}
	}

	style := ns_window_style_titled | ns_window_style_closable | ns_window_style_miniaturizable | ns_window_style_resizable
	base_title := display_title_for_input(title)
	window := msg_id_rect_u64_u64_bool(msg_id(native_window_class(), 'alloc'), 'initWithContentRect:styleMask:backing:defer:', frame, style, ns_backing_store_buffered, false)
	configure_window_common(window, base_title)

	view := create_terminal_view(frame)
	msg_void1(window, 'setContentView:', view)
	msg_void1(window, 'setInitialFirstResponder:', view)
	msg_void2(anchor, 'addTabbedWindow:ordered:', window, ObjId(ns_window_above))
	msg_void1(window, 'makeKeyAndOrderFront:', nil_obj())
	msg_bool1(window, 'makeFirstResponder:', view)
	g_window = anchor
	refresh_tab_labels(window)
	return view
}

pub fn close_tab(view voidptr) {
	if is_nil(view) {
		return
	}
	window := msg_id(ObjId(view), 'window')
	if !is_nil(window) {
		msg_void(window, 'close')
		key_window := msg_id(shared_app(), 'keyWindow')
		if !is_nil(key_window) {
			refresh_tab_labels(key_window)
		} else if !is_nil(g_window) {
			refresh_tab_labels(g_window)
		}
	}
}

pub fn select_tab(offset int) {
	key_window := msg_id(shared_app(), 'keyWindow')
	if is_nil(key_window) {
		return
	}
	if offset > 0 {
		msg_void1(key_window, 'selectNextTab:', nil_obj())
	} else if offset < 0 {
		msg_void1(key_window, 'selectPreviousTab:', nil_obj())
	}
	refresh_tab_labels(key_window)
}

pub fn tab_count() int {
	key_window := msg_id(shared_app(), 'keyWindow')
	if is_nil(key_window) {
		return 1
	}
	tabs := msg_id(key_window, 'tabbedWindows')
	if is_nil(tabs) {
		return 1
	}
	count := int(msg_u64(tabs, 'count'))
	if count <= 0 {
		return 1
	}
	return count
}

fn set_view_title_now(view voidptr, title string) {
	if is_nil(view) {
		return
	}
	window := msg_id(ObjId(view), 'window')
	if is_nil(window) {
		return
	}
	base_title := runtime_title_for_input(title)
	set_base_title(window, base_title)
	refresh_tab_labels(window)
}

fn set_view_title_main_task(ctx voidptr) {
	if ctx == unsafe { nil } {
		return
	}
	task := unsafe { &C.witty_macos_string_task(ctx) }
	view := task.view
	title := if task.text == unsafe { nil } {
		''
	} else {
		unsafe { task.text.vstring().clone() }
	}
	C.witty_macos_string_task_free(task)
	set_view_title_now(view, title)
}

pub fn set_view_title(view voidptr, title string) {
	if is_nil(view) {
		return
	}
	if !C.witty_macos_is_main_thread() {
		task := C.witty_macos_string_task_new(view, cstr(title))
		if task != unsafe { nil } {
			C.witty_macos_dispatch_main(voidptr(set_view_title_main_task), task)
		}
		return
	}
	set_view_title_now(view, title)
}

// Metal wrappers.
pub fn metal_activate_layer(view voidptr) {
	if is_nil(view) {
		return
	}
	layer := metal_layer(view)
	if is_nil(layer) {
		return
	}
	msg_void_bool(ObjId(view), 'setWantsLayer:', true)
	msg_void1(ObjId(view), 'setLayer:', ObjId(layer))
	update_metal_drawable_size(ObjId(view))
}

pub fn metal_device(view voidptr) voidptr {
	if is_nil(view) {
		return unsafe { nil }
	}
	return C.macos_objc_get_ptr_ivar(ObjId(view), cstr('metalDevice'))
}

pub fn metal_queue(view voidptr) voidptr {
	if is_nil(view) {
		return unsafe { nil }
	}
	return C.macos_objc_get_ptr_ivar(ObjId(view), cstr('metalQueue'))
}

pub fn metal_layer(view voidptr) voidptr {
	if is_nil(view) {
		return unsafe { nil }
	}
	return C.macos_objc_get_ptr_ivar(ObjId(view), cstr('metalLayer'))
}
