@[has_globals]
module main

import apprt
import core
import witty_macos as macos
#insert "@VMODROOT/native_config_scope_darwin_test_abi.h"

fn C.witty_config_scope_drain_main()
fn C.witty_config_scope_finish_launching()

__global (
	appearance_app_calls      int
	appearance_surface_calls  []int
	appearance_app_scheme     apprt.ColorScheme
	appearance_surface_scheme apprt.ColorScheme
)

fn appearance_app_published(_backend voidptr, _app &apprt.App, scheme apprt.ColorScheme) ! {
	appearance_app_calls++
	appearance_app_scheme = scheme
}

fn appearance_surface_published(backend voidptr, scheme apprt.ColorScheme) ! {
	appearance_surface_calls << int(uint(backend))
	appearance_surface_scheme = scheme
}

fn test_native_application_and_controller_appearance_publication_and_cache() {
	macos.app_init()
	C.witty_config_scope_finish_launching()
	mut runtime := standalone_runtime()
	original_app := runtime.app
	runtime.app = unsafe { nil }
	apprt.install_core_bridge(apprt.CoreBridge{ app_color_scheme: appearance_app_published, surface_color_scheme: appearance_surface_published })
	defer {
		core.install_embedded_bridge()
		runtime.app = original_app
	}
	appearance_app_calls = 0
	appearance_surface_calls.clear()
	native_application_appearance_changed(true)
	assert appearance_app_calls == 0
	runtime.app = &apprt.App{ core_app: &apprt.CoreApp{ backend: voidptr(uint(1)) } }
	macos.sync_native_application_appearance(macos.NativeWindowConfig{ theme: 2 })
	macos.set_application_appearance_callback(native_application_appearance_changed)
	defer {
		macos.stop_application_appearance_callback()
		macos.sync_native_application_appearance(macos.NativeWindowConfig{ theme: 1 })
	}
	assert appearance_app_calls == 1
	assert appearance_app_scheme == .light
	macos.sync_native_application_appearance(macos.NativeWindowConfig{ theme: 3 })
	C.witty_config_scope_drain_main()
	assert appearance_app_calls >= 2
	assert appearance_app_scheme == .dark

	view := macos.create_restorable_window(300, 200, 'appearance publication')
	window := macos.view_window(view)
	mut first := &TermState{ view: view, native_config: macos.NativeWindowConfig{ theme: 2 }, surface: &apprt.Surface{ core_surface: apprt.CoreSurface{ backend: voidptr(uint(2)) } } }
	macos.view_set_userdata(view, voidptr(first))
	mut controller := &TerminalController{ host: macos.create_split_host(view), focused: first }
	first.controller = controller
	second_view := macos.create_split_surface_view(controller.host)
	mut second := &TermState{ view: second_view, surface: &apprt.Surface{ core_surface: apprt.CoreSurface{ backend: voidptr(uint(3)) } } }
	macos.view_set_userdata(second_view, voidptr(second))
	second.controller = controller
	controller.host.replace_tree(controller.host.tree.inserting(second_view, view, .right) or { panic(err) })
	defer {
		macos.view_set_userdata(view, unsafe { nil })
		macos.view_set_userdata(second_view, unsafe { nil })
		macos.close_native_window(window)
		macos.release_native_object(window)
		macos.release_native_object(controller.host.container)
		macos.release_native_object(second_view)
		macos.release_native_object(view)
	}
	sync_native_window(first)
	assert appearance_surface_calls.len == 0 // regular invisible window guard
	macos.focus_native_window(window)
	sync_native_window(first)
	assert appearance_surface_calls == [2, 3]
	assert appearance_surface_scheme == .dark // App effective, not local light
	assert (controller.applied_color_scheme or { panic('missing scheme') }) == .dark
	sync_native_window(first)
	assert appearance_surface_calls.len == 2
	macos.sync_native_application_appearance(macos.NativeWindowConfig{ theme: 2 })
	sync_native_window(first)
	assert appearance_surface_calls == [2, 3, 2, 3]
	assert appearance_surface_scheme == .light
	// Empty trees still cache the scheme, matching the original for-loop.
	controller.host.replace_tree(macos.NativeSplitTree{})
	macos.sync_native_application_appearance(macos.NativeWindowConfig{ theme: 3 })
	sync_native_surface_color_scheme(mut controller)
	assert (controller.applied_color_scheme or { panic('missing scheme') }) == .dark
	assert appearance_surface_calls.len == 4
}
