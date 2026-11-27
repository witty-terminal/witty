module witty_macos

import math

fn C.witty_macos_set_frame_origin(window ObjId,point ObjCPoint)

// TerminalController.UndoState and DefaultSize use native AppKit window state.
pub struct NativeWindowFrame {
pub:
	x f64
	y f64
	width f64
	height f64
}
pub fn native_window_frame(view voidptr) NativeWindowFrame {
	f := msg_rect(msg_id(view, 'window'), 'frame')
	return NativeWindowFrame{x: f.x, y: f.y, width: f.width, height: f.height}
}
pub fn apply_native_window_frame(view voidptr, frame NativeWindowFrame) { C.witty_macos_msg_void_rect_bool(msg_id(view, 'window'), sel('setFrame:display:'), objc_rect(frame.x, frame.y, frame.width, frame.height), true) }
pub fn native_tab_windows(view voidptr) []voidptr {
	window := msg_id(view, 'window')
	tabs := msg_id(msg_id(window, 'tabGroup'), 'windows')
	mut result := []voidptr{}
	for i in 0 .. int(msg_u64(tabs, 'count')) { result << msg_id_u64(tabs, 'objectAtIndex:', u64(i)) }
	if result.len == 0 && !is_nil(window) { result << window }
	return result
}
pub fn native_window_is_key(window voidptr) bool { return msg_bool(window, 'isKeyWindow') }
pub fn native_window_is_closed(window voidptr) bool { return !msg_bool(window, 'isVisible') && is_nil(msg_id(window, 'tabGroup')) }
pub fn native_tab_group(view voidptr) voidptr { return msg_id(msg_id(view, 'window'), 'tabGroup') }
pub fn restore_native_tab(view voidptr, group voidptr, index int) {
	if is_nil(group) || index < 0 { return }
	tabs := msg_id(group, 'windows')
	count := int(msg_u64(tabs, 'count'))
	if count == 0 { return }
	anchor := msg_id_u64(tabs, 'objectAtIndex:', u64(if index < count { index } else { count-1 }))
	msg_void2(anchor, 'addTabbedWindow:ordered:', msg_id(view, 'window'), ObjId(if index < count { -1 } else { 1 }))
}
pub fn add_native_tab(parent voidptr, child voidptr) { msg_void2(msg_id(parent, 'window'), 'addTabbedWindow:ordered:', msg_id(child, 'window'), ObjId(1)) }
pub fn attach_native_new_tab(parent voidptr,view voidptr,at_end bool) {
	window:=msg_id(view,'window')
	if msg_bool(parent,'isMiniaturized') { msg_void1(parent,'deminiaturize:',nil_obj()) }
	group:=msg_id(parent,'tabGroup'); tabs:=msg_id(group,'windows')
	for i in 0 .. int(msg_u64(tabs,'count')) { if msg_id_u64(tabs,'objectAtIndex:',u64(i))==window { msg_void1(group,'removeWindow:',window); break } }
	if msg_u64(window,'tabbingMode')!=2 {
		mut anchor:=ObjId(parent)
		if at_end { latest:=msg_id(msg_id(parent,'tabGroup'),'windows'); count:=msg_u64(latest,'count'); if count>0 { anchor=msg_id_u64(latest,'objectAtIndex:',count-1) } }
		msg_void2(anchor,'addTabbedWindow:ordered:',window,ObjId(1))
		queue_native_tab_shortcuts(window)
	}
}
pub fn native_tab_creation_denied(view voidptr) bool {
	window:=msg_id(view,'window')
	if state:=g_fullscreen_states[u64(window)] {
		if state.is_active() && state.mode!=.native {
			alert:=msg_id(alloc('NSAlert'),'init')
			msg_void1(alert,'setMessageText:',nsstring('Cannot Create New Tab'))
			msg_void1(alert,'setInformativeText:',nsstring('New tabs are unsupported while in non-native fullscreen. Exit fullscreen and try again.'))
			msg_id1(alert,'addButtonWithTitle:',nsstring('OK'))
			msg_void_u64(alert,'setAlertStyle:',0)
			msg_void2(alert,'beginSheetModalForWindow:completionHandler:',window,nil_obj())
			msg_void(alert,'release')
			return true
		}
	}
	return false
}
pub fn detach_automatic_native_tab(view voidptr) {
	window:=msg_id(view,'window')
	if msg_u64(window,'styleMask') & u64(1<<14)!=0 { return }
	group:=msg_id(window,'tabGroup')
	if msg_u64(msg_id(group,'windows'),'count')>1 { msg_void1(group,'removeWindow:',window) }
}
pub fn close_native_window(window voidptr) { msg_void(window, 'close'); if g_window == window { g_window = nil_obj() } }
pub fn focus_native_window(window voidptr) { msg_void1(window, 'makeKeyAndOrderFront:', nil_obj()) }
pub fn invalidate_native_restorable_state(view voidptr) { msg_void(msg_id(view, 'window'), 'invalidateRestorableState') }
pub fn reset_native_window_size(view voidptr, maximize bool, initial NativeWindowFrame, width f64, height f64) {
	window := msg_id(view, 'window')
	if maximize {
		mut screen := msg_id(window, 'screen'); if is_nil(screen) { screen = msg_id(get_class('NSScreen'), 'mainScreen') }
		if !is_nil(screen) { C.witty_macos_msg_void_rect_bool(window, sel('setFrame:display:'), msg_rect(screen, 'visibleFrame'), true) }
	} else if width > 0 && height > 0 {
		msg_void_size(window, 'setContentSize:', objc_size(width,height))
		mut screen := msg_id(window, 'screen'); if is_nil(screen) { screen = msg_id(get_class('NSScreen'), 'mainScreen') }
		if !is_nil(screen) {
			old:=msg_rect(window,'frame')
			mut frame := old; visible := msg_rect(screen,'visibleFrame')
			// NSWindow.constrainToScreen from the source extension.
			frame.width = if frame.width > visible.width { visible.width } else { frame.width }
			frame.height = if frame.height > visible.height { visible.height } else { frame.height }
			frame.x = if frame.x < visible.x { visible.x } else if frame.x+frame.width > visible.x+visible.width { visible.x+visible.width-frame.width } else { frame.x }
			frame.y = if frame.y < visible.y { visible.y } else if frame.y+frame.height > visible.y+visible.height { visible.y+visible.height-frame.height } else { frame.y }
			if frame!=old { C.witty_macos_msg_void_rect_bool(window,sel('setFrame:display:'),frame,true) }
		}
	} else { apply_native_window_frame(view, initial) }
}
// TerminalController.adjustForWindowPosition after the deferred intrinsic-size
// application, using NSScreen.origin(fromTopLeftOffsetX:offsetY:windowSize:).
pub fn adjust_native_window_origin_after_default_size(view voidptr,x ?i16,y ?i16) {
	x_offset:=x or { return }
	y_offset:=y or { return }
	window:=msg_id(view,'window')
	mut screen:=msg_id(window,'screen')
	if is_nil(screen) { screen=msg_id(get_class('NSScreen'),'mainScreen') }
	if is_nil(screen) { return }
	frame:=msg_rect(window,'frame')
	vf:=msg_rect(screen,'visibleFrame')
	position:=native_window_position(SplitBounds{width:frame.width,height:frame.height},SplitBounds{x:vf.x,y:vf.y,width:vf.width,height:vf.height},x_offset,y_offset)
	C.witty_macos_set_frame_origin(window,ObjCPoint{x:math.min(math.max(position.x,vf.x),vf.x+vf.width-frame.width),y:math.min(math.max(position.y,vf.y),vf.y+vf.height-frame.height)})
}
