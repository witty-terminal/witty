module main

import apprt
import macos

// AppDelegate observes NSApplication.effectiveAppearance with .new/.initial
// after the optional libwitty application has been initialized.
fn native_application_appearance_changed(dark bool) {
	mut runtime := standalone_runtime()
	if runtime.app == unsafe { nil } || runtime.app.core_app == unsafe { nil } { return }
	apprt.ghostty_app_set_color_scheme(mut runtime.app, int(if dark {
		apprt.ColorScheme.dark
	} else {
		apprt.ColorScheme.light
	}))
}

// BaseTerminalController.updateColorSchemeForSurfaceTree deliberately derives
// from the application's effective appearance and caches the last publication:
// the surface callback may notify syncAppearance again.
fn sync_native_surface_color_scheme(mut controller TerminalController) {
	if controller.host == unsafe { nil } { return }
	scheme := if macos.native_application_is_dark() {
		apprt.ColorScheme.dark
	} else {
		apprt.ColorScheme.light
	}
	if previous := controller.applied_color_scheme {
		if previous == scheme { return }
	}
	for view in controller.host.tree.root.leaves() {
		mut state := state_from_userdata(macos.view_get_userdata(view)) or { continue }
		if state.surface != unsafe { nil } {
			apprt.ghostty_surface_set_color_scheme(mut state.surface, int(scheme))
		}
	}
	controller.applied_color_scheme = scheme
}
