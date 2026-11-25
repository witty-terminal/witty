#ifndef WITTY_GTK_BELL_OVERLAY_H
#define WITTY_GTK_BELL_OVERLAY_H

#include "canvas_overlay_linux.h"

static inline void witty_gtk_bell_append(GtkSnapshot *snapshot, GdkTexture *mask,
		GskRenderNode *node, bool cairo) {
	const GskRenderNodeType type = gsk_render_node_get_node_type(node);
	if (type == GSK_COLOR_NODE
			|| (type == GSK_BORDER_NODE && cairo && gsk_rounded_rect_is_rectilinear(gsk_border_node_get_outline(node)))) {
		graphene_rect_t bounds;
		gsk_render_node_get_bounds(node, &bounds);
		witty_gtk_canvas_overlay_append_masked_node(snapshot, mask, node, &bounds);
		return;
	}
	if (type == GSK_CONTAINER_NODE) {
		const guint count = gsk_container_node_get_n_children(node);
		for (guint i = 0; i < count; ++i)
			witty_gtk_bell_append(snapshot, mask, gsk_container_node_get_child(node, i), cairo);
		return;
	}
	if (type == GSK_OPACITY_NODE || type == GSK_TRANSFORM_NODE) {
		GskTransform *transform = NULL;
		GskRenderNode *contents;
		if (type == GSK_OPACITY_NODE) {
			contents = gsk_opacity_node_get_child(node);
		} else {
			transform = gsk_transform_node_get_transform(node);
			float x, y;
			if (gsk_transform_get_category(transform) < GSK_TRANSFORM_CATEGORY_2D_TRANSLATE)
				goto native_paint;
			gsk_transform_to_translate(transform, &x, &y);
			if (x != floorf(x) || y != floorf(y))
				goto native_paint;
			contents = gsk_transform_node_get_child(node);
		}
		// Keep both layers together as GTK fades the revealer.
		GtkSnapshot *layout = gtk_snapshot_new();
		witty_gtk_bell_append(layout, mask, contents, cairo);
		g_autoptr(GskRenderNode) child = gtk_snapshot_free_to_node(layout);
		if (child) {
			g_autoptr(GskRenderNode) wrapped = type == GSK_OPACITY_NODE
				? gsk_opacity_node_new(child, gsk_opacity_node_get_opacity(node))
				: gsk_transform_node_new(child, transform);
			gtk_snapshot_append_node(snapshot, wrapped);
			return;
		}
	}
	// Keep GTK's edge coverage for translucent rounded backgrounds and GPU borders.
	if (type == GSK_ROUNDED_CLIP_NODE && witty_gtk_canvas_overlay_append_solid_background(snapshot, mask, node))
		return;
native_paint:
	gtk_snapshot_append_node(snapshot, node);
}

#endif
