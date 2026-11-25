#ifndef WITTY_GTK_SPLIT_CANVAS_H
#define WITTY_GTK_SPLIT_CANVAS_H

#include "canvas_overlay_linux.h"

static inline GtkWidget *witty_gtk_split_canvas_separator(GtkWidget *bin) {
	GtkWidget *paned = adw_bin_get_child(ADW_BIN(bin));
	if (!GTK_IS_PANED(paned))
		return NULL;
	for (GtkWidget *child = gtk_widget_get_first_child(paned); child;
			child = gtk_widget_get_next_sibling(child)) {
		if (g_strcmp0(gtk_widget_get_css_name(child), "separator") == 0)
			return child;
	}
	return NULL;
}

static inline void witty_gtk_split_canvas_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *parent = g_type_class_peek(ADW_TYPE_BIN);
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	GtkWidget *separator = mask ? witty_gtk_split_canvas_separator(widget) : NULL;
	graphene_rect_t area;
	if (!separator || !gtk_widget_get_mapped(separator)
			|| !gtk_widget_compute_bounds(separator, widget, &area)
			|| area.size.width <= 0 || area.size.height <= 0) {
		parent->snapshot(widget, snapshot);
		return;
	}

	// Keep GtkPaned's pane order, clipping and separator input handling.
	GtkSnapshot *layout = gtk_snapshot_new();
	parent->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (!node)
		return;
	g_autoptr(GskRenderNode) fill = witty_gtk_canvas_replace_widget_fill(node, mask, separator, &area,
		WITTY_CANVAS_FIRST_FILL);
	if (!fill) {
		// The separator's default background-clip is content-box.
		const graphene_point_t zero = GRAPHENE_POINT_INIT(0, 0);
		graphene_point_t origin;
		const int width = gtk_widget_get_width(separator);
		const int height = gtk_widget_get_height(separator);
		if (width > 0 && height > 0 && gtk_widget_compute_point(separator, widget, &zero, &origin)) {
			const graphene_rect_t content = GRAPHENE_RECT_INIT(origin.x, origin.y, width, height);
			if (!graphene_rect_equal(&area, &content))
				fill = witty_gtk_canvas_replace_fill(node, mask, &content, WITTY_CANVAS_FIRST_FILL);
		}
	}
	gtk_snapshot_append_node(snapshot, fill ? fill : node);
}

static inline void witty_gtk_split_canvas_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_split_canvas_snapshot;
}

static inline GtkWidget *witty_gtk_split_canvas_new(void) {
	static gsize type;
	if (g_once_init_enter(&type)) {
		GTypeQuery base;
		g_type_query(ADW_TYPE_BIN, &base);
		GType registered = g_type_register_static_simple(ADW_TYPE_BIN, "WittyCanvasSplitBin",
			base.class_size, witty_gtk_split_canvas_class_init, base.instance_size, NULL, 0);
		g_once_init_leave(&type, registered);
	}
	return g_object_new(type, NULL);
}

#endif
