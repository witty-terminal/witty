#ifndef WITTY_GTK_PROGRESS_OVERLAY_H
#define WITTY_GTK_PROGRESS_OVERLAY_H

#include "canvas_linux.h"
#include <stdbool.h>

static inline void witty_gtk_progress_append(GtkSnapshot *snapshot, GdkTexture *mask,
		GskRenderNode *node) {
	switch (gsk_render_node_get_node_type(node)) {
	case GSK_COLOR_NODE: {
		graphene_rect_t bounds;
		gsk_render_node_get_bounds(node, &bounds);
		witty_gtk_canvas_snapshot_mask(snapshot, mask, gsk_color_node_get_color(node),
			&bounds, &bounds, 1);
		break;
	}
	case GSK_CONTAINER_NODE:
		for (guint i = 0; i < gsk_container_node_get_n_children(node); ++i)
			witty_gtk_progress_append(snapshot, mask, gsk_container_node_get_child(node, i));
		break;
	case GSK_TRANSFORM_NODE:
		gtk_snapshot_save(snapshot);
		gtk_snapshot_transform(snapshot, gsk_transform_node_get_transform(node));
		witty_gtk_progress_append(snapshot, mask, gsk_transform_node_get_child(node));
		gtk_snapshot_restore(snapshot);
		break;
	case GSK_CLIP_NODE:
		gtk_snapshot_push_clip(snapshot, gsk_clip_node_get_clip(node));
		witty_gtk_progress_append(snapshot, mask, gsk_clip_node_get_child(node));
		gtk_snapshot_pop(snapshot);
		break;
	case GSK_ROUNDED_CLIP_NODE:
		gtk_snapshot_push_rounded_clip(snapshot, gsk_rounded_clip_node_get_clip(node));
		witty_gtk_progress_append(snapshot, mask, gsk_rounded_clip_node_get_child(node));
		gtk_snapshot_pop(snapshot);
		break;
	default:
		gtk_snapshot_append_node(snapshot, node);
		break;
	}
}

static inline void witty_gtk_progress_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *native_class = g_type_class_peek(GTK_TYPE_PROGRESS_BAR);
	if (!g_object_get_data(G_OBJECT(widget), "witty-progress-canvas")) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	// GTK lays out the trough and the indicator, including clipping and pulse
	// placement. Canvas supplies the coverage for their solid fills.
	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	GskRenderNode *node = gtk_snapshot_free_to_node(layout);
	if (node) {
		GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-progress-mask");
		witty_gtk_progress_append(snapshot, mask, node);
		gsk_render_node_unref(node);
	}
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

static inline void witty_gtk_progress_set_canvas(GtkWidget *bar, bool enabled) {
	GObject *object = G_OBJECT(bar);
	void *mode = GINT_TO_POINTER(enabled && g_object_get_data(object, "witty-progress-mask"));
	if (g_object_get_data(object, "witty-progress-canvas") != mode) {
		g_object_set_data(object, "witty-progress-canvas", mode);
		gtk_widget_queue_draw(bar);
	}
}

#endif
