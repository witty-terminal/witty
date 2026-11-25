#ifndef WITTY_GTK_CANVAS_OVERLAY_H
#define WITTY_GTK_CANVAS_OVERLAY_H

#include <adwaita.h>
#include <math.h>
#include <stdbool.h>
#include "canvas_linux.h"

static inline void witty_gtk_canvas_overlay_append_strip(GtkSnapshot *snapshot,
		GskRenderNode *node, const graphene_rect_t *clip) {
	if (clip->size.height > 0) {
		gtk_snapshot_push_clip(snapshot, clip);
		gtk_snapshot_append_node(snapshot, node);
		gtk_snapshot_pop(snapshot);
	}
}

static inline bool witty_gtk_canvas_overlay_append_background(GtkSnapshot *snapshot,
		GdkTexture *mask, GskRenderNode *node) {
	if (gsk_render_node_get_node_type(node) != GSK_ROUNDED_CLIP_NODE)
		return false;
	GskRenderNode *fill = gsk_rounded_clip_node_get_child(node);
	if (gsk_render_node_get_node_type(fill) != GSK_COLOR_NODE)
		return false;

	graphene_rect_t bounds;
	gsk_render_node_get_bounds(fill, &bounds);
	const GskRoundedRect *clip = gsk_rounded_clip_node_get_clip(node);
	if (!graphene_rect_equal(&clip->bounds, &bounds))
		return false;

	// Keep the rows with curved edges in GTK's primitive. Applying the clip
	// through a mask changes the compositor's antialiasing at the corners.
	const float top = ceilf(MAX(clip->corner[0].height, clip->corner[1].height));
	const float bottom = ceilf(MAX(clip->corner[2].height, clip->corner[3].height));
	const float x = bounds.origin.x, y = bounds.origin.y;
	const float width = bounds.size.width, height = bounds.size.height;
	if (top + bottom >= height || y != floorf(y) || height != floorf(height))
		return false;

	const graphene_rect_t upper = GRAPHENE_RECT_INIT(x, y, width, top);
	const graphene_rect_t lower = GRAPHENE_RECT_INIT(x, y + height - bottom, width, bottom);
	const graphene_rect_t middle = GRAPHENE_RECT_INIT(x, y + top, width, height - top - bottom);
	witty_gtk_canvas_overlay_append_strip(snapshot, node, &upper);
	witty_gtk_canvas_snapshot_mask(snapshot, mask, gsk_color_node_get_color(fill), &middle,
		&middle, 1);
	witty_gtk_canvas_overlay_append_strip(snapshot, node, &lower);
	return true;
}

static inline void witty_gtk_canvas_overlay_append(GtkSnapshot *snapshot,
		GdkTexture *mask, GskRenderNode *node) {
	// GTK places the styled child in the bin and paints its CSS background
	// before the text, controls, and outline. Only replace the background.
	if (gsk_render_node_get_node_type(node) == GSK_TRANSFORM_NODE) {
		GtkSnapshot *local = gtk_snapshot_new();
		witty_gtk_canvas_overlay_append(local, mask, gsk_transform_node_get_child(node));
		g_autoptr(GskRenderNode) child = gtk_snapshot_free_to_node(local);
		g_autoptr(GskRenderNode) placed = gsk_transform_node_new(child,
			gsk_transform_node_get_transform(node));
		gtk_snapshot_append_node(snapshot, placed);
	} else if (gsk_render_node_get_node_type(node) == GSK_CONTAINER_NODE
			&& gsk_container_node_get_n_children(node) > 0
			&& witty_gtk_canvas_overlay_append_background(snapshot, mask,
				gsk_container_node_get_child(node, 0))) {
		guint count = gsk_container_node_get_n_children(node);
		for (guint i = 1; i < count; ++i)
			gtk_snapshot_append_node(snapshot, gsk_container_node_get_child(node, i));
	} else {
		gtk_snapshot_append_node(snapshot, node);
	}
}

static inline void witty_gtk_canvas_overlay_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *native_class = g_type_class_peek(ADW_TYPE_BIN);
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	if (!mask) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	GskRenderNode *node = gtk_snapshot_free_to_node(layout);
	if (node) {
		witty_gtk_canvas_overlay_append(snapshot, mask, node);
		gsk_render_node_unref(node);
	}
}

static inline void witty_gtk_canvas_overlay_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_canvas_overlay_snapshot;
}

static inline void witty_gtk_canvas_overlay_register(void) {
	static gsize type;
	if (g_once_init_enter(&type)) {
		GTypeQuery base;
		g_type_query(ADW_TYPE_BIN, &base);
		GType registered = g_type_register_static_simple(ADW_TYPE_BIN, "WittyCanvasOverlayBin",
			base.class_size, witty_gtk_canvas_overlay_class_init, base.instance_size, NULL, 0);
		g_once_init_leave(&type, registered);
	}
}

static inline bool witty_gtk_canvas_overlay_has_mask(GtkWidget *bin) {
	return g_object_get_data(G_OBJECT(bin), "witty-overlay-mask") != NULL;
}

// The bin takes ownership of the texture.
static inline void witty_gtk_canvas_overlay_set_mask(GtkWidget *bin, GdkTexture *mask) {
	g_object_set_data_full(G_OBJECT(bin), "witty-overlay-mask", mask, g_object_unref);
	gtk_widget_queue_draw(bin);
}

#endif
