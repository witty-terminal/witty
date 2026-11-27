module ui2_runtime

import configpkg
import sokol.sapp
import witty_macos as macos

#flag darwin -DWITTY_UI2_USES_VLIB_OBJC_BRIDGE
#include "@VMODROOT/apprt/ui2_runtime/window_darwin.h"

fn C.witty_ui2_macos_resize(window voidptr, width f64, height f64) bool
fn C.witty_ui2_macos_scale(window voidptr) f64
fn C.witty_ui2_macos_quit()
fn C.witty_ui2_macos_set_display_p3(window voidptr)
fn C.witty_ui2_macos_set_translucent(window voidptr, translucent bool)
fn C.witty_ui2_macos_configure_render_targets(window voidptr)

fn identify_window(_ string) {}

fn quit_window() { C.witty_ui2_macos_quit() }

fn configure_window_colorspace() {
	C.witty_ui2_macos_set_display_p3(sapp.macos_get_window())
}

fn configure_window_background(config &configpkg.Config) {
	window := sapp.macos_get_window()
	translucent := config.background_opacity < 1
	C.witty_ui2_macos_set_translucent(window, translucent)
	blur := config.background_blur.cval()
	// Glass materials have their own backdrop. Only pass numeric radii to WindowServer.
	macos.set_window_background_blur(window, if translucent && blur > 0 { blur } else { i16(0) })
}

fn configure_window_render_targets() {
	C.witty_ui2_macos_configure_render_targets(sapp.macos_get_window())
}

fn initial_window_scale() f64 {
	// Sokol can publish the first DPI change after the ready callback.
	return C.witty_ui2_macos_scale(sapp.macos_get_window())
}

fn set_initial_window_size(width u32, height u32) bool {
	scale := initial_window_scale()
	return C.witty_ui2_macos_resize(sapp.macos_get_window(), f64(width) / scale, f64(height) / scale)
}
