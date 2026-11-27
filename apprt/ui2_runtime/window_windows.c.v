module ui2_runtime

import sokol.sapp

#include "@VMODROOT/apprt/ui2_runtime/window_windows.h"

fn C.witty_ui2_windows_resize(window voidptr, width u32, height u32) bool

fn identify_window(_ string) {}

fn set_initial_window_size(width u32, height u32) bool {
	return C.witty_ui2_windows_resize(sapp.win32_get_hwnd(), width, height)
}
