module ui2_runtime

#include "@VMODROOT/apprt/ui2_runtime/x11_window.h"

fn C.witty_ui2_x11_identify(class_name &char)
fn C.witty_ui2_x11_resize(width u32, height u32) bool

fn identify_window(class_name string) {
	C.witty_ui2_x11_identify(&char(class_name.str))
}

fn set_initial_window_size(width u32, height u32) bool {
	return C.witty_ui2_x11_resize(width, height)
}
