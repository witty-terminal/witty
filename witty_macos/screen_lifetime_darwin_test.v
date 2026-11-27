@[has_globals]
module witty_macos

#insert "@VMODROOT/witty_macos/input_client_test_bridge.h"
fn C.witty_input_test_run_main_for(seconds f64)

__global (g_weak_dispatch_calls int)
fn weak_dispatch_probe(_raw voidptr) { g_weak_dispatch_calls++ }
fn test_native_main_queue_weak_capture_does_not_keep_view_alive() {
	register_classes()
	view := msg_id_rect(alloc('VTTerminalView'), 'initWithFrame:', objc_rect(0, 0, 30, 20))
	g_weak_dispatch_calls = 0
	C.witty_macos_dispatch_main_weak(voidptr(view), voidptr(weak_dispatch_probe))
	C.witty_input_test_run_main_for(0.02)
	assert g_weak_dispatch_calls == 1
	C.witty_macos_dispatch_main_weak(voidptr(view), voidptr(weak_dispatch_probe))
	msg_void(view, 'release')
	C.witty_input_test_run_main_for(0.02)
	assert g_weak_dispatch_calls == 1
}
