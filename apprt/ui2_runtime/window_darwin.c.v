module ui2_runtime

import sokol.sapp

#flag darwin -DWITTY_UI2_USES_VLIB_OBJC_BRIDGE
#include "@VMODROOT/apprt/ui2_runtime/window_darwin.h"

fn C.witty_ui2_macos_resize(window voidptr, width f64, height f64) bool
fn C.witty_ui2_macos_scale(window voidptr) f64
fn C.witty_ui2_macos_quit()

fn identify_window(_ string) {}

fn quit_window() { C.witty_ui2_macos_quit() }

fn initial_window_scale() f64 {
	// Sokol can publish the first DPI change after the ready callback.
	return C.witty_ui2_macos_scale(sapp.macos_get_window())
}

fn set_initial_window_size(width u32, height u32) bool {
	scale := initial_window_scale()
	return C.witty_ui2_macos_resize(sapp.macos_get_window(), f64(width) / scale, f64(height) / scale)
}
