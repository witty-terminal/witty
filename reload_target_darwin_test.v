module main

import apprt
import witty_macos as macos
#insert "@VMODROOT/initial_size_darwin_test_abi.h"

fn C.witty_initial_size_test_scale2(view voidptr) voidptr
fn C.witty_initial_size_test_restore_class(view voidptr, original voidptr)

fn test_reload_ignores_an_unresolved_surface_without_touching_app_config() {
	// The app is deliberately absent: an unresolved surface target must return
	// before entering the app-wide update path, even for a soft reload.
	assert runtime_action(unsafe { nil }, apprt.SurfaceTarget{surface: unsafe { nil }}, apprt.RuntimeAction{action: .reload_config, data: apprt.ReloadConfig{soft: true}})
}

fn test_native_void_actions_acknowledge_missing_surfaces_without_creating_windows() {
	// These source helpers return void. App.action acknowledges their tags even
	// when the source helper's surface guard prevents any operation.
	for action in [apprt.ActionKey.new_window, .new_tab, .new_split, .close_tab, .close_window] {
		assert runtime_action(unsafe { nil }, apprt.SurfaceTarget{surface: unsafe { nil }}, apprt.RuntimeAction{action: action, data: apprt.ActionVoid{}})
	}
	for action in [apprt.ActionKey.new_tab, .new_split] {
		assert runtime_action(unsafe { nil }, apprt.AppTarget{}, apprt.RuntimeAction{action: action, data: apprt.ActionVoid{}})
	}
	assert !runtime_action(unsafe { nil }, apprt.AppTarget{}, apprt.RuntimeAction{action: .goto_split, data: apprt.GotoSplit.next})
	assert !runtime_action(unsafe { nil }, apprt.AppTarget{}, apprt.RuntimeAction{action: .size_limit, data: apprt.ActionVoid{}})
	assert !runtime_action(unsafe { nil }, apprt.SurfaceTarget{surface: unsafe { nil }}, apprt.RuntimeAction{action: .undo, data: apprt.ActionVoid{}})
	assert !runtime_action(unsafe { nil }, apprt.SurfaceTarget{surface: unsafe { nil }}, apprt.RuntimeAction{action: .redo, data: apprt.ActionVoid{}})
	assert !runtime_action(unsafe { nil }, apprt.AppTarget{}, apprt.RuntimeAction{action: .render, data: apprt.ActionVoid{}})
}

fn test_initial_size_dispatch_keeps_source_points_at_scale_two_without_resizing() {
	// Ghostty.App.setInitialSize stores points without resizing. Surface.zig
	// recomputeInitialSize has already divided cell pixels by content scale.
	macos.app_init()
	view := macos.create_restorable_window(200, 120, 'initial size probe')
	window := macos.view_window(view)
	original_class := C.witty_initial_size_test_scale2(view)
	mut runtime := standalone_runtime()
	original_app := runtime.app
	runtime.app = &apprt.App{}
	defer {
		runtime.app = original_app
		C.witty_initial_size_test_restore_class(view, original_class)
		macos.close_native_window(window)
		macos.release_native_object(window)
		macos.release_native_object(view)
	}
	assert macos.view_backing_scale(view) == 2
	initial_frame := macos.native_window_frame(view)
	mut state := &TermState{
		view: view
	}
	state.controller = &TerminalController{
		focused:       state
		initial_frame: initial_frame
	}
	mut surface := apprt.Surface{
		userdata: voidptr(state)
	}
	core := apprt.CoreSurface{
		runtime_surface: voidptr(&surface)
	}
	target := apprt.SurfaceTarget{
		surface: voidptr(&core)
	}
	assert runtime_action(runtime.app, target, apprt.RuntimeAction{
		action: .initial_size
		data:   apprt.InitialSize{
			width:  800
			height: 600
		}
	})
	assert state.initial_width == 800
	assert state.initial_height == 600
	assert macos.native_window_frame(view) == initial_frame
}

fn test_initial_size_full_dispatch_acknowledges_source_ignored_targets() {
	for target in [apprt.Target(apprt.AppTarget{}), apprt.Target(apprt.SurfaceTarget{})] {
		assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
			action: .initial_size
			data:   apprt.InitialSize{
				width:  800
				height: 600
			}
		})
	}
}
