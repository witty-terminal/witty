module gtk

#include "@VMODROOT/apprt/gtk/menu_canvas_linux.h"

fn C.witty_gtk_menu_canvas_new(model GMenuModel, flags int) GtkWidget
fn C.witty_gtk_menu_canvas_attach(button GtkWidget, model GMenuModel)
