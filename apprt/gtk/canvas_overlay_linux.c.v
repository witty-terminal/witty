module gtk

#include "@VMODROOT/apprt/gtk/canvas_overlay_linux.h"

fn C.witty_gtk_canvas_overlay_register()
fn C.witty_gtk_canvas_overlay_has_mask(bin GtkWidget) bool
fn C.witty_gtk_canvas_overlay_set_mask(bin GtkWidget, mask voidptr)

fn gtk_canvas_overlay_set_enabled(overlay GtkWidget, enabled bool) {
	bin := C.adw_bin_get_child(overlay)
	if isnil(bin) || C.witty_gtk_canvas_overlay_has_mask(bin) == enabled {
		return
	}
	mask := if enabled { gtk_canvas_solid_mask() } else { unsafe { nil } }
	C.witty_gtk_canvas_overlay_set_mask(bin, mask)
}
