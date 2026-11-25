#ifndef WITTY_GTK_MENU_CANVAS_H
#define WITTY_GTK_MENU_CANVAS_H

#include "canvas_overlay_linux.h"

static inline void witty_gtk_menu_canvas_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *native_class = g_type_class_peek(GTK_TYPE_POPOVER_MENU);
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-menu-mask");
	GtkWidget *child = gtk_popover_get_child(GTK_POPOVER(widget));
	GtkWidget *contents = child ? gtk_widget_get_parent(child) : NULL;
	graphene_rect_t area;
	// The contents bounds exclude the arrow and shadow. Restrict the
	// replacement to the panel so custom backgrounds and rows keep their CSS.
	if (!mask || !contents || gtk_widget_get_parent(contents) != widget
			|| !gtk_widget_compute_bounds(contents, widget, &area)) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (node) {
		g_autoptr(GskRenderNode) fill = witty_gtk_canvas_replace_fill(node, mask, &area);
		if (!fill) {
			// Themes can clip the background to the padding box inside the
			// border. Match that exact allocation as well.
			GtkBorder border;
			gtk_style_context_get_border(gtk_widget_get_style_context(contents), &border);
			if (border.left || border.right || border.top || border.bottom) {
				area.origin.x += border.left;
				area.origin.y += border.top;
				area.size.width -= border.left + border.right;
				area.size.height -= border.top + border.bottom;
				if (area.size.width > 0 && area.size.height > 0)
					fill = witty_gtk_canvas_replace_fill(node, mask, &area);
			}
		}
		gtk_snapshot_append_node(snapshot, fill ? fill : node);
	}
}

static inline void witty_gtk_menu_canvas_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_menu_canvas_snapshot;
}

// The popup takes ownership of its Canvas mask independently of the window's CSS.
static inline GtkWidget *witty_gtk_menu_canvas_new(GMenuModel *model, GtkPopoverMenuFlags flags,
		GdkTexture *mask) {
	GType parent = GTK_TYPE_POPOVER_MENU;
	if (!mask || g_type_test_flags(parent, G_TYPE_FLAG_FINAL)) {
		g_clear_object(&mask);
		return gtk_popover_menu_new_from_model_full(model, flags);
	}

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
	GtkWidget *popover = g_object_new(type, "flags", flags, "menu-model", model, NULL);
	g_object_set_data_full(G_OBJECT(popover), "witty-menu-mask", mask, g_object_unref);
	return popover;
}

static inline void witty_gtk_menu_canvas_attach(GtkWidget *button, GMenuModel *model, GdkTexture *mask) {
	GtkWidget *popover = witty_gtk_menu_canvas_new(model, 0, mask);
	if (ADW_IS_SPLIT_BUTTON(button))
		adw_split_button_set_popover(ADW_SPLIT_BUTTON(button), GTK_POPOVER(popover));
	else
		gtk_menu_button_set_popover(GTK_MENU_BUTTON(button), popover);

	// Match the accessible label relation installed by GTK's menu-model setter.
	GtkWidget *owner = gtk_widget_get_parent(popover);
	if (owner)
		gtk_accessible_update_relation(GTK_ACCESSIBLE(popover),
			GTK_ACCESSIBLE_RELATION_LABELLED_BY, owner, NULL, -1);
}

#endif
