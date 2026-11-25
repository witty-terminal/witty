#ifndef WITTY_GTK_CANVAS_OVERLAY_H
#define WITTY_GTK_CANVAS_OVERLAY_H

#include <adwaita.h>
#include <math.h>
#include <stdbool.h>
#include "canvas_linux.h"

static inline void witty_gtk_canvas_overlay_append_strip(GtkSnapshot *snapshot,
		GskRenderNode *node, const graphene_rect_t *clip) {
	if (clip->size.width > 0 && clip->size.height > 0) {
		gtk_snapshot_push_clip(snapshot, clip);
		gtk_snapshot_append_node(snapshot, node);
		gtk_snapshot_pop(snapshot);
	}
}

static inline bool witty_gtk_canvas_overlay_append_background(GtkSnapshot *snapshot,
		GdkTexture *mask, GskRenderNode *node) {
	if (gsk_render_node_get_node_type(node) == GSK_COLOR_NODE) {
		graphene_rect_t bounds;
		gsk_render_node_get_bounds(node, &bounds);
		witty_gtk_canvas_snapshot_mask(snapshot, mask, gsk_color_node_get_color(node),
			&bounds, &bounds, 1);
		return true;
	}
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

static inline bool witty_gtk_canvas_overlay_append_outline(GtkSnapshot *snapshot,
		GdkTexture *mask, GskRenderNode *node) {
	if (gsk_render_node_get_node_type(node) != GSK_BORDER_NODE)
		return false;

	const GskRoundedRect *outline = gsk_border_node_get_outline(node);
	const float *widths = gsk_border_node_get_widths(node);
	const GdkRGBA *colors = gsk_border_node_get_colors(node);
	const float x = outline->bounds.origin.x, y = outline->bounds.origin.y;
	const float width = outline->bounds.size.width, height = outline->bounds.size.height;
	const float left = ceilf(MAX(widths[3], MAX(outline->corner[0].width, outline->corner[3].width)));
	const float right = ceilf(MAX(widths[1], MAX(outline->corner[1].width, outline->corner[2].width)));
	if (left + right >= width || x != floorf(x) || width != floorf(width)
			|| widths[0] + widths[2] >= height)
		return false;

	// The middle sections are axis-aligned rectangles. Keep the rounded
	// corners and the edge joins in the compositor's border primitive.
	const graphene_rect_t left_strip = GRAPHENE_RECT_INIT(x, y, left, height);
	const graphene_rect_t right_strip = GRAPHENE_RECT_INIT(x + width - right, y, right, height);
	const graphene_rect_t top = GRAPHENE_RECT_INIT(x + left, y, width - left - right, widths[0]);
	const graphene_rect_t bottom = GRAPHENE_RECT_INIT(x + left, y + height - widths[2],
		width - left - right, widths[2]);
	witty_gtk_canvas_overlay_append_strip(snapshot, node, &left_strip);
	witty_gtk_canvas_overlay_append_strip(snapshot, node, &right_strip);
	if (widths[0] > 0)
		witty_gtk_canvas_snapshot_mask(snapshot, mask, &colors[0], &top, &top, 1);
	if (widths[2] > 0)
		witty_gtk_canvas_snapshot_mask(snapshot, mask, &colors[2], &bottom, &bottom, 1);
	return true;
}

static inline void witty_gtk_canvas_overlay_append(GtkSnapshot *snapshot,
		GdkTexture *mask, GskRenderNode *node, bool draw_outline) {
	const GskRenderNodeType type = gsk_render_node_get_node_type(node);
	if (type == GSK_TRANSFORM_NODE || type == GSK_OPACITY_NODE) {
		GskRenderNode *content = type == GSK_TRANSFORM_NODE
			? gsk_transform_node_get_child(node) : gsk_opacity_node_get_child(node);
		GtkSnapshot *local = gtk_snapshot_new();
		witty_gtk_canvas_overlay_append(local, mask, content, draw_outline);
		g_autoptr(GskRenderNode) child = gtk_snapshot_free_to_node(local);
		if (!child) {
			gtk_snapshot_append_node(snapshot, node);
			return;
		}
		g_autoptr(GskRenderNode) placed = type == GSK_TRANSFORM_NODE
			? gsk_transform_node_new(child, gsk_transform_node_get_transform(node))
			: gsk_opacity_node_new(child, gsk_opacity_node_get_opacity(node));
		gtk_snapshot_append_node(snapshot, placed);
	} else if (type == GSK_CONTAINER_NODE) {
		// GTK paints the background first and the outline after its contents.
		guint count = gsk_container_node_get_n_children(node);
		for (guint i = 0; i < count; ++i) {
			GskRenderNode *child = gsk_container_node_get_child(node, i);
			if (i == 0 && witty_gtk_canvas_overlay_append_background(snapshot, mask, child))
				continue;
			if (draw_outline && i + 1 == count
					&& witty_gtk_canvas_overlay_append_outline(snapshot, mask, child))
				continue;
			gtk_snapshot_append_node(snapshot, child);
		}
	} else if (!witty_gtk_canvas_overlay_append_background(snapshot, mask, node)
			&& !(draw_outline && witty_gtk_canvas_overlay_append_outline(snapshot, mask, node))) {
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
		witty_gtk_canvas_overlay_append(snapshot, mask, node, false);
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
