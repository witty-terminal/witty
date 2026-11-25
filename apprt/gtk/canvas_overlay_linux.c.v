module gtk

#include "@VMODROOT/apprt/gtk/terminal_overlay_linux.h"

fn C.witty_gtk_canvas_overlay_register()
fn C.witty_gtk_canvas_overlay_has_mask(bin GtkWidget) bool
fn C.witty_gtk_canvas_overlay_set_mask(bin GtkWidget, mask voidptr)
fn C.witty_gtk_terminal_overlay_new() GtkWidget
fn C.witty_gtk_terminal_overlay_add(overlay GtkWidget, child GtkWidget)

fn gtk_canvas_overlay_set_enabled(overlay GtkWidget, enabled bool) {
	gtk_canvas_overlay_set_mask(C.adw_bin_get_child(overlay), enabled)
}

fn gtk_canvas_overlay_set_mask(widget GtkWidget, enabled bool) {
	if isnil(widget) || C.witty_gtk_canvas_overlay_has_mask(widget) == enabled {
		return
	}
	mask := if enabled { gtk_canvas_solid_mask() } else { unsafe { nil } }
	C.witty_gtk_canvas_overlay_set_mask(widget, mask)
}
