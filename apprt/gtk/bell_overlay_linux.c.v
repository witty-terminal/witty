module gtk

import gg.canvas

#include "@VMODROOT/apprt/gtk/bell_overlay_linux.h"

fn C.witty_gtk_bell_box_new(mask voidptr) GtkWidget
fn C.witty_gtk_bell_set_canvas(revealer GtkWidget, enabled bool)

fn surface_bell_box_new() GtkWidget {
	mut mask := canvas.new_raster_surface(width: 1, height: 1) or { return C.gtk_box_new(0, 0) }
	mask.clear(0xffffffff)
	return C.witty_gtk_bell_box_new(gtk_canvas_texture(mask))
}
