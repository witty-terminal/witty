module main

import apprt
import configpkg
import witty_macos as macos
#insert "@VMODROOT/native_controller_focus_darwin_test_abi.h"

fn C.witty_controller_focus_test_launch()
fn C.witty_controller_focus_test_pump(seconds f64)
fn C.witty_controller_focus_test_track(window voidptr)
fn C.witty_controller_focus_test_responder(view voidptr, window voidptr) voidptr
fn C.witty_controller_focus_test_first_responder(window voidptr) voidptr
fn C.witty_controller_focus_test_calls() int

fn test_close_sibling_tabs_undo_queues_only_window_keying() {
	macos.app_init()
	C.witty_controller_focus_test_launch()
	view := macos.create_window(640, 480, 'sibling undo focus')
	other := macos.create_window(640, 480, 'other window')
	window := macos.view_window(view)
	mut controller := &TerminalController{ host: macos.create_split_host(view) }
	current := &TermState{ view: view, controller: controller }
	controller.focused = current
	mut runtime := standalone_runtime()
	previous_app := runtime.app
	runtime.app = &apprt.App{ config: configpkg.Config.default() }
	runtime.controllers << controller
	defer {
		macos.clear_native_undo()
		runtime.controllers.delete(runtime.controllers.len - 1)
		runtime.app = previous_app
		macos.close_tab(view)
		macos.close_tab(other)
	}
	macos.focus_native_window(window)
	C.witty_controller_focus_test_pump(0.1)
	// AppKit may refuse key status for a command-line app. The queued source
	// message must have the same native effect as this direct source baseline.
	expected_key := macos.native_window_is_key(window)
	responder := C.witty_controller_focus_test_responder(controller.host.container, window)
	assert C.witty_controller_focus_test_first_responder(window) == responder
	macos.focus_native_window(macos.view_window(other))
	C.witty_controller_focus_test_pump(0.03)
	C.witty_controller_focus_test_track(window)
	macos.clear_native_undo()
	macos.native_undo_begin()
	register_controller_undo(&ControllerUndo{ kind: .focus, controller: controller, mode: .other, name: 'Close Other Tabs' }, voidptr(controller))
	macos.native_undo_end()
	// Window refocus must preserve a different actual responder rather than
	// moving to the controller's selected surface. The queued target also
	// outlives the undo record released by NSUndoManager.
	assert controller.focused == current
	assert macos.native_undo()
	assert C.witty_controller_focus_test_calls() == 0
	assert C.witty_controller_focus_test_first_responder(window) == responder
	C.witty_controller_focus_test_pump(0.03)
	assert C.witty_controller_focus_test_calls() == 1
	assert macos.native_window_is_key(window) == expected_key
	assert C.witty_controller_focus_test_first_responder(window) == responder
}

fn test_close_sibling_tabs_queued_refocus_does_not_use_released_window() {
	macos.app_init()
	view := macos.create_window(640, 480, 'close before queued focus')
	controller := &TerminalController{ host: macos.create_split_host(view) }
	mut runtime := standalone_runtime()
	previous_app := runtime.app
	runtime.app = &apprt.App{ config: configpkg.Config.default() }
	runtime.controllers << controller
	defer {
		macos.clear_native_undo()
		runtime.controllers.delete(runtime.controllers.len - 1)
		runtime.app = previous_app
	}
	C.witty_controller_focus_test_track(macos.view_window(view))
	macos.clear_native_undo()
	macos.native_undo_begin()
	register_controller_undo(&ControllerUndo{ kind: .focus, controller: controller, mode: .right, name: 'Close Tabs to the Right' }, voidptr(controller))
	macos.native_undo_end()
	// Source window lookup does not require a selected terminal surface.
	assert controller.focused == unsafe { nil }
	assert macos.native_undo()
	assert C.witty_controller_focus_test_calls() == 0
	close_one_controller(controller)
	assert controller.closed
	C.witty_controller_focus_test_pump(0.03)
	assert C.witty_controller_focus_test_calls() == 0
}
