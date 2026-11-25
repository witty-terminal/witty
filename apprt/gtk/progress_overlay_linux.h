#ifndef WITTY_GTK_PROGRESS_OVERLAY_H
#define WITTY_GTK_PROGRESS_OVERLAY_H

#include "canvas_overlay_linux.h"

static inline GtkWidget *witty_gtk_progress_find_child(GtkWidget *widget, const char *name) {
	for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
			child = gtk_widget_get_next_sibling(child)) {
		if (g_strcmp0(gtk_widget_get_css_name(child), name) == 0)
			return child;
	}
	return NULL;
}

static inline void witty_gtk_progress_replace_fill(GskRenderNode **node, GdkTexture *mask,
		GtkWidget *bar, GtkWidget *target, WittyCanvasFillSearch search) {
	graphene_rect_t area;
	if (!target || !gtk_widget_get_mapped(target) || !gtk_widget_compute_bounds(target, bar, &area)
			|| area.size.width <= 0 || area.size.height <= 0)
		return;
	GskRenderNode *updated = witty_gtk_canvas_replace_widget_fill(*node, mask, target, &area, search);
	if (!updated)
		updated = witty_gtk_canvas_replace_widget_content_fill(*node, mask, target, bar, &area, search);
	if (updated) {
		gsk_render_node_unref(*node);
		*node = updated;
	}
}

static inline void witty_gtk_progress_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *native_class = g_type_class_peek(GTK_TYPE_PROGRESS_BAR);
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-progress-mask");
	GtkWidget *trough = witty_gtk_progress_find_child(widget, "trough");
	if (!mask || !trough) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	// GTK lays out the trough and the indicator, including clipping and pulse
	// placement. Canvas supplies the coverage for their solid fills.
	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (!node)
		return;
	witty_gtk_progress_replace_fill(&node, mask, widget, trough, WITTY_CANVAS_FIRST_FILL);
	witty_gtk_progress_replace_fill(&node, mask, widget, witty_gtk_progress_find_child(trough, "progress"),
		WITTY_CANVAS_LAST_FILL);
	gtk_snapshot_append_node(snapshot, node);
}

static inline void witty_gtk_progress_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_progress_snapshot;
}

// Takes ownership of the mask. GtkProgressBar's layout is private, so query
// the native sizes when registering the subclass.
static inline GtkWidget *witty_gtk_progress_new(GdkTexture *mask) {
	if (!mask || g_type_test_flags(GTK_TYPE_PROGRESS_BAR, G_TYPE_FLAG_FINAL)) {
		g_clear_object(&mask);
		return gtk_progress_bar_new();
	}
	static gsize type;
	if (g_once_init_enter(&type)) {
		GTypeQuery base;
		g_type_query(GTK_TYPE_PROGRESS_BAR, &base);
		GType registered = g_type_register_static_simple(GTK_TYPE_PROGRESS_BAR, "WittyCanvasProgress",
			base.class_size, witty_gtk_progress_class_init, base.instance_size, NULL, 0);
		g_once_init_leave(&type, registered);
	}
	GtkWidget *bar = g_object_new(type, NULL);
	g_object_set_data_full(G_OBJECT(bar), "witty-progress-mask", mask, g_object_unref);
	return bar;
}

#endif
