@[has_globals]
module main

import apprt
import configpkg
import core
import witty_macos as macos
#insert "@VMODROOT/native_config_scope_darwin_test_abi.h"

fn C.witty_config_scope_drain_main()
fn C.witty_config_scope_finish_launching()

__global quick_appearance_calls int

fn quick_appearance_surface_published(_backend voidptr, _scheme apprt.ColorScheme) ! {
	quick_appearance_calls++
}

fn quick_appearance_create(_view voidptr) bool { return false }

fn quick_appearance_close(_view voidptr) bool { return true }

fn test_hidden_quick_config_appearance_without_focus_or_tree() {
	macos.app_init()
	C.witty_config_scope_finish_launching()
	mut runtime := standalone_runtime()
	original_app := runtime.app
	original_states := runtime.states.clone()
	original_controllers := runtime.controllers.clone()
	mut config := configpkg.Config.default()
	config.window_theme = .light
	mut quick := macos.quick_terminal(native_quick_config(&config), quick_appearance_create, quick_appearance_close)
	mut controller := &TerminalController{ host: macos.create_split_host(quick.view), quick: true, app_config: native_window_config(&config), creation_config: native_window_config(&config) }
	controller.host.replace_tree(macos.NativeSplitTree{})
	runtime.app = &apprt.App{ config: config.clone() }
	runtime.states = []&TermState{}
	runtime.controllers = [controller]
	apprt.install_core_bridge(apprt.CoreBridge{ surface_color_scheme: quick_appearance_surface_published })
	defer {
		core.install_embedded_bridge()
		runtime.app.config.deinit()
		runtime.app = original_app
		runtime.states = original_states
		runtime.controllers = original_controllers
		macos.view_set_userdata(quick.view, unsafe { nil })
		macos.close_native_window(macos.view_window(quick.view))
		macos.sync_native_application_appearance(macos.NativeWindowConfig{ theme: 1 })
		config.deinit()
	}
	assert !macos.native_window_is_visible(macos.view_window(quick.view))
	assert controller.focused == unsafe { nil }
	assert runtime_action(runtime.app, apprt.AppTarget{}, apprt.RuntimeAction{ action: .config_change, data: apprt.ConfigChange{ config: &config } })
	C.witty_config_scope_drain_main()
	assert (controller.applied_color_scheme or { panic('empty Quick tree did not cache scheme') }) == .light
	assert quick_appearance_calls == 0
	mut state := &TermState{ view: quick.view, controller: controller, surface: &apprt.Surface{ core_surface: apprt.CoreSurface{ backend: voidptr(uint(1)) } } }
	macos.view_set_userdata(quick.view, voidptr(state))
	controller.host.replace_tree(macos.NativeSplitTree{ root: macos.native_split_leaf(quick.view) })
	config.window_theme = .dark
	assert runtime_action(runtime.app, apprt.AppTarget{}, apprt.RuntimeAction{ action: .config_change, data: apprt.ConfigChange{ config: &config } })
	C.witty_config_scope_drain_main()
	assert (controller.applied_color_scheme or { panic('hidden Quick tree did not publish scheme') }) == .dark
	assert quick_appearance_calls == 1
	assert !macos.native_window_is_visible(macos.view_window(quick.view))
	assert controller.focused == unsafe { nil }
}
