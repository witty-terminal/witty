module gtk

#include "@VMODROOT/apprt/gtk/terminal_overlay_linux.h"
#include "@VMODROOT/apprt/gtk/split_canvas_linux.h"
#include "@VMODROOT/apprt/gtk/scrollbar_canvas_linux.h"

fn C.witty_gtk_canvas_overlay_register()
fn C.witty_gtk_canvas_overlay_has_mask(bin GtkWidget) bool
fn C.witty_gtk_canvas_overlay_set_mask(bin GtkWidget, mask voidptr)
fn C.witty_gtk_terminal_overlay_new() GtkWidget
fn C.witty_gtk_terminal_overlay_add(overlay GtkWidget, child GtkWidget, paint int)
fn C.witty_gtk_split_canvas_new() GtkWidget
fn C.witty_gtk_scrollbar_canvas_class_init(klass voidptr)

fn gtk_canvas_overlay_set_mask(widget GtkWidget, enabled bool) {
	if isnil(widget) || C.witty_gtk_canvas_overlay_has_mask(widget) == enabled {
		return
	}
	mask := if enabled { gtk_canvas_solid_mask() } else { unsafe { nil } }
	C.witty_gtk_canvas_overlay_set_mask(widget, mask)
}
