module gtk

#include "@VMODROOT/apprt/gtk/bell_overlay_linux.h"

fn C.witty_gtk_bell_box_new(mask voidptr) GtkWidget
fn C.witty_gtk_bell_set_canvas(revealer GtkWidget, enabled bool)

fn surface_bell_box_new() GtkWidget {
	return C.witty_gtk_bell_box_new(gtk_canvas_solid_mask())
}
