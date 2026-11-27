module main

import apprt
import configpkg
import witty_macos as macos
#insert "@VMODROOT/native_config_scope_darwin_test_abi.h"
#insert "@VMODROOT/native_title_font_darwin_test_abi.h"

fn C.witty_config_scope_drain_main()
fn C.witty_config_scope_finish_launching()
fn C.witty_title_font_matches(view voidptr, family &char) bool
fn C.witty_title_font_title(view voidptr, title &char) bool

fn title_font_target(state &TermState) apprt.SurfaceTarget {
	surface := &apprt.Surface{ userdata: voidptr(state) }
	return apprt.SurfaceTarget{ surface: voidptr(&apprt.CoreSurface{ runtime_surface: voidptr(surface) }) }
}

fn test_focused_surface_title_font_projection_and_native_set_title_hook() {
	macos.app_init()
	C.witty_config_scope_finish_launching()
	mut runtime := standalone_runtime()
	original_app := runtime.app
	original_states := runtime.states.clone()
	original_controllers := runtime.controllers.clone()
	mut config := configpkg.Config.default()
	config.macos_titlebar_style = .tabs
	config.window_title_font_family = 'Courier'
	view := macos.create_restorable_window(400, 300, 'focused font')
	window := macos.view_window(view)
	projection := native_window_config(&config)
	mut first := &TermState{ view: view, native_config: projection }
	macos.view_set_userdata(view, voidptr(first))
	mut controller := &TerminalController{ host: macos.create_split_host(view), app_config: projection, creation_config: projection }
	first.controller = controller
	second_view := macos.create_split_surface_view(controller.host)
	mut second_config := config.clone()
	second_config.window_title_font_family = 'Menlo'
	mut second := &TermState{ view: second_view, native_config: native_window_config(&second_config), controller: controller }
	macos.view_set_userdata(second_view, voidptr(second))
	controller.host.replace_tree(controller.host.tree.inserting(second_view, view, .down) or { panic(err) })
	controller.focused = second
	runtime.app = &apprt.App{ config: config.clone() }
	runtime.states = [first, second]
	runtime.controllers = [controller]
	defer {
		runtime.app.config.deinit()
		runtime.app = original_app
		runtime.states = original_states
		runtime.controllers = original_controllers
		macos.view_set_userdata(view, unsafe { nil })
		macos.view_set_userdata(second_view, unsafe { nil })
		macos.close_native_window(window)
		macos.release_native_object(window)
		macos.release_native_object(controller.host.container)
		macos.release_native_object(second_view)
		macos.release_native_object(view)
		config.deinit()
		second_config.deinit()
	}
	// The bottom focused surface supplies font independently of the top-border
	// preferred background surface. The setter precedes the visibility guard.
	sync_native_window(first)
	assert C.witty_title_font_matches(second_view, c'Menlo')
	assert C.witty_title_font_title(second_view, c'font title hook')
	macos.focus_native_window(window)
	mut app_config := config.clone()
	defer { app_config.deinit() }
	app_config.window_title_font_family = 'Helvetica'
	assert runtime_action(runtime.app, apprt.AppTarget{}, apprt.RuntimeAction{ action: .config_change, data: apprt.ConfigChange{ config: &app_config } })
	C.witty_config_scope_drain_main()
	assert C.witty_title_font_matches(second_view, c'Menlo')
	second_config.window_title_font_family = 'Courier'
	assert runtime_action(runtime.app, title_font_target(second), apprt.RuntimeAction{ action: .config_change, data: apprt.ConfigChange{ config: &second_config } })
	C.witty_config_scope_drain_main()
	assert C.witty_title_font_matches(second_view, c'Courier')
	second_config.window_title_font_family = none
	assert runtime_action(runtime.app, title_font_target(second), apprt.RuntimeAction{ action: .config_change, data: apprt.ConfigChange{ config: &second_config } })
	C.witty_config_scope_drain_main()
	assert C.witty_title_font_matches(second_view, unsafe { nil })
	// The source controller's empty-tree App notification enters its private
	// syncAppearance(config), including the app-derived font assignment.
	controller.host.replace_tree(macos.NativeSplitTree{})
	controller.focused = unsafe { nil }
	app_config.window_title_font_family = 'Courier'
	assert runtime_action(runtime.app, apprt.AppTarget{}, apprt.RuntimeAction{
		action: .config_change
		data:   apprt.ConfigChange{ config: &app_config }
	})
	C.witty_config_scope_drain_main()
	assert C.witty_title_font_matches(controller.host.container, c'Courier')
}
