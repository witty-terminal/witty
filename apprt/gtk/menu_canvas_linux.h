#ifndef WITTY_GTK_MENU_CANVAS_H
#define WITTY_GTK_MENU_CANVAS_H

#include "canvas_overlay_linux.h"

static inline void witty_gtk_menu_canvas_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *native_class = g_type_class_peek(GTK_TYPE_POPOVER_MENU);
	GtkRoot *root = gtk_widget_get_root(widget);
	GdkTexture *mask = root ? g_object_get_data(G_OBJECT(root), "witty-overlay-mask") : NULL;
	if (!mask) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (node) {
		g_autoptr(GskRenderNode) fill = witty_gtk_canvas_replace_fill(node, mask, NULL);
		gtk_snapshot_append_node(snapshot, fill ? fill : node);
	}
}

static inline void witty_gtk_menu_canvas_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_menu_canvas_snapshot;
}

static inline GtkWidget *witty_gtk_menu_canvas_new(GMenuModel *model, GtkPopoverMenuFlags flags) {
	GType parent = GTK_TYPE_POPOVER_MENU;
	if (g_type_test_flags(parent, G_TYPE_FLAG_FINAL))
		return gtk_popover_menu_new_from_model_full(model, flags);

	// Retain the menu model, native popup, and input handling. GTK keeps the
	// class and instance sizes opaque even on runtimes that allow derivation.
	static gsize type;
	if (g_once_init_enter(&type)) {
		GTypeQuery base;
		g_type_query(parent, &base);
		GType registered = g_type_register_static_simple(parent, "WittyCanvasPopoverMenu",
			base.class_size, witty_gtk_menu_canvas_class_init, base.instance_size, NULL, 0);
		g_once_init_leave(&type, registered);
	}
	return g_object_new(type, "flags", flags, "menu-model", model, NULL);
}

#endif
