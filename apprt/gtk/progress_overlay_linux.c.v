module gtk

#include "@VMODROOT/apprt/gtk/progress_overlay_linux.h"

fn C.witty_gtk_progress_new(mask voidptr) GtkWidget

fn surface_progress_bar_new() GtkWidget {
	progress_bar := C.witty_gtk_progress_new(gtk_canvas_solid_mask())
	C.gtk_widget_add_css_class(progress_bar, c'osd')
	C.gtk_widget_set_visible(progress_bar, false)
	C.gtk_widget_set_halign(progress_bar, int(Align.fill))
	C.gtk_widget_set_valign(progress_bar, int(Align.start))
	return progress_bar
}
