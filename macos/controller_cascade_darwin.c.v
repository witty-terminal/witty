@[has_globals]
module macos

#insert "@VMODROOT/macos/controller_cascade_abi.h"
fn C.witty_macos_cascade_top_left(window ObjId, point ObjCPoint) ObjCPoint

// TerminalController.lastCascadePoint and weak lastMain. AppKit owns the native
// window ordering used by TerminalController.all and preferredParent.
__global (
	g_terminal_cascade_point ObjCPoint
	g_terminal_last_main &NativeWeakObject
)
fn is_regular_terminal_window(window ObjId) bool {
	return !is_nil(window) && msg_bool1(window,'isKindOfClass:',get_class('VTTerminalWindow'))
}
pub fn preferred_terminal_window() voidptr {
	windows:=msg_id(shared_app(),'windows')
	mut last:=nil_obj()
	for i in 0 .. int(msg_u64(windows,'count')) {
		window:=msg_id_u64(windows,'objectAtIndex:',u64(i))
		if !is_regular_terminal_window(window) { continue }
		if msg_bool(window,'isMainWindow') { return window }
		last=window
	}
	if g_terminal_last_main != unsafe { nil } {
		window:=g_terminal_last_main.object()
		if !is_nil(window) { return window }
	}
	return last
}
fn terminal_window_became_main(window ObjId) {
	if !is_regular_terminal_window(window) { return }
	save_native_window_frame(window)
	if g_terminal_last_main != unsafe { nil } { g_terminal_last_main.deinit() }
	g_terminal_last_main=new_native_weak_object(voidptr(window))
}
fn native_window_did_become_main(_self ObjId,_cmd Sel,notification ObjId) { terminal_window_became_main(msg_id(notification,'object')) }
fn register_terminal_cascade_delegate_methods(cls ObjId) { add_method(cls,'windowDidBecomeMain:',voidptr(native_window_did_become_main),'v@:@') }
fn terminal_window_will_close(window ObjId) {
	focused:=msg_id(shared_app(),'keyWindow')
	terminal_window_will_close_with_focused(window,focused)
}
fn terminal_window_will_close_with_focused(window ObjId,focused ObjId) {
	if is_nil(focused) { return }
	if focused!=window {
		old:=msg_rect(focused,'frame')
		g_terminal_cascade_point=C.witty_macos_cascade_top_left(focused,ObjCPoint{})
		if msg_rect(focused,'frame')!=old { C.witty_macos_msg_void_rect_bool(focused,sel('setFrame:display:'),old,true) }
		return
	}
	frame:=msg_rect(focused,'frame')
	g_terminal_cascade_point=ObjCPoint{x:frame.x,y:frame.y+frame.height}
}
pub fn native_window_is_fullscreen(window voidptr) bool { return msg_u64(window,'styleMask') & u64(1<<14)!=0 }
pub fn show_new_terminal_window(view voidptr,tab bool) {
	window:=msg_id(view,'window')
	if is_nil(window) { return }
	if !native_window_is_fullscreen(voidptr(window)) && (!tab || msg_u64(msg_id(msg_id(window,'tabGroup'),'windows'),'count')<=1) {
		g_terminal_cascade_point=C.witty_macos_cascade_top_left(window,g_terminal_cascade_point)
	}
	msg_void1(window,'makeKeyAndOrderFront:',nil_obj())
	msg_void_bool(shared_app(),'activateIgnoringOtherApps:',true)
}
