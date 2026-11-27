@[has_globals]
module witty_macos

fn C.witty_controller_sheet(alert voidptr, window voidptr, context voidptr, callback voidptr)
pub type NativeCloseConfirmation = fn (voidptr, bool)
@[heap]
struct NativeCloseAlert {
	alert ObjId
	context voidptr
	callback NativeCloseConfirmation
}
__global ( g_controller_close_alerts []&NativeCloseAlert )
fn native_close_alert_completed(context voidptr, response i64) {
	task := unsafe { &NativeCloseAlert(context) }
	// confirmClose explicitly orders the sheet out before closing, to keep
	// Stage Manager from stealing focus (TerminalController.swift #8336).
	msg_void1(msg_id(task.alert, 'window'), 'orderOut:', nil_obj())
	task.callback(task.context, response == 1000)
	for i, value in g_controller_close_alerts { if value == task { g_controller_close_alerts.delete(i); break } }
	msg_void(task.alert,'release')
}
pub fn confirm_native_controller_close(view voidptr, message string, informative string, button string, context voidptr, callback NativeCloseConfirmation) {
	alert := msg_id(msg_id(get_class('NSAlert'),'alloc'),'init')
	msg_void1(alert,'setMessageText:',nsstring(message))
	msg_void1(alert,'setInformativeText:',nsstring(informative))
	msg_id1(alert,'addButtonWithTitle:',nsstring(button))
	msg_id1(alert,'addButtonWithTitle:',nsstring('Cancel'))
	msg_void_u64(alert,'setAlertStyle:',0)
	task := &NativeCloseAlert{alert:alert,context:context,callback:callback}
	g_controller_close_alerts << task
	C.witty_controller_sheet(alert,msg_id(view,'window'),voidptr(task),voidptr(native_close_alert_completed))
}
