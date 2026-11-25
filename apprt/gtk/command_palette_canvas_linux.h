#ifndef WITTY_GTK_COMMAND_PALETTE_CANVAS_H
#define WITTY_GTK_COMMAND_PALETTE_CANVAS_H

#include "canvas_overlay_linux.h"

static inline void witty_gtk_palette_append(GtkSnapshot *snapshot, GdkTexture *mask,
		GskRenderNode *node, float top, float bottom) {
	const GskRenderNodeType type = gsk_render_node_get_node_type(node);
	switch (type) {
	case GSK_CONTAINER_NODE:
		for (guint i = 0; i < gsk_container_node_get_n_children(node); ++i)
			witty_gtk_palette_append(snapshot, mask, gsk_container_node_get_child(node, i), top, bottom);
		return;
	case GSK_TRANSFORM_NODE: {
		GskTransform *transform = gsk_transform_node_get_transform(node);
		// Adwaita scales the dialog during its opening and closing animations.
		if (gsk_transform_get_category(transform) < GSK_TRANSFORM_CATEGORY_2D_TRANSLATE)
			break;
		float x, y;
		gsk_transform_to_translate(transform, &x, &y);
		if (x != floorf(x) || y != floorf(y))
			break;
		GtkSnapshot *local = gtk_snapshot_new();
		witty_gtk_palette_append(local, mask, gsk_transform_node_get_child(node), top - y, bottom - y);
		g_autoptr(GskRenderNode) contents = gtk_snapshot_free_to_node(local);
		if (!contents)
			break;
		g_autoptr(GskRenderNode) placed = gsk_transform_node_new(contents, transform);
		gtk_snapshot_append_node(snapshot, placed);
		return;
	}
	case GSK_CLIP_NODE:
		gtk_snapshot_push_clip(snapshot, gsk_clip_node_get_clip(node));
		witty_gtk_palette_append(snapshot, mask, gsk_clip_node_get_child(node), top, bottom);
		gtk_snapshot_pop(snapshot);
		return;
	case GSK_ROUNDED_CLIP_NODE: {
		const GskRoundedRect *clip = gsk_rounded_clip_node_get_clip(node);
		GskRenderNode *child = gsk_rounded_clip_node_get_child(node);
		const float y = clip->bounds.origin.y;
		const float end = y + clip->bounds.size.height;
		if (gsk_render_node_get_node_type(child) == GSK_COLOR_NODE) {
			// The shared fill keeps the curved strips in the native snapshot.
			if (y >= top && end <= bottom && gsk_color_node_get_color(child)->alpha == 1
					&& witty_gtk_canvas_overlay_append_background(snapshot, mask, node))
				return;
			break;
		}

		// Keep the rounded clip around its original content and convert fills
		// only in the central rectangle where the clip is fully opaque.
		const float inner_top = y + MAX(clip->corner[0].height, clip->corner[1].height);
		const float inner_bottom = end - MAX(clip->corner[2].height, clip->corner[3].height);
		GtkSnapshot *local = gtk_snapshot_new();
		witty_gtk_palette_append(local, mask, child, MAX(top, inner_top), MIN(bottom, inner_bottom));
		g_autoptr(GskRenderNode) contents = gtk_snapshot_free_to_node(local);
		if (!contents)
			break;
		g_autoptr(GskRenderNode) clipped = gsk_rounded_clip_node_new(contents, clip);
		gtk_snapshot_append_node(snapshot, clipped);
		return;
	}
	case GSK_COLOR_NODE:
	case GSK_BORDER_NODE: {
		// Preserve opaque list backgrounds so GSK composites the search
		// focus outline with the same coverage in a bottom sheet.
		if (type == GSK_COLOR_NODE && isfinite(top) && gsk_color_node_get_color(node)->alpha == 1)
			break;
		// List separators are rectangular. Keep GTK's analytic coverage
		// for the dialog outline and rounded focus rings.
		if (type == GSK_BORDER_NODE && !gsk_rounded_rect_is_rectilinear(gsk_border_node_get_outline(node)))
			break;
		graphene_rect_t bounds;
		gsk_render_node_get_bounds(node, &bounds);
		if (bounds.origin.y >= top && bounds.origin.y + bounds.size.height <= bottom
				&& (witty_gtk_canvas_overlay_append_background(snapshot, mask, node)
					|| witty_gtk_canvas_overlay_append_outline(snapshot, mask, node)))
			return;
		break;
	}
	default:
		break;
	}
	gtk_snapshot_append_node(snapshot, node);
}

static inline void witty_gtk_palette_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *native_class = g_type_class_peek(ADW_TYPE_DIALOG);
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	if (!mask) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (node)
		witty_gtk_palette_append(snapshot, mask, node, -INFINITY, INFINITY);
}

static inline void witty_gtk_palette_canvas_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_palette_snapshot;
}

static inline void witty_gtk_palette_canvas_register(void) {
	static gsize type;
	if (g_once_init_enter(&type)) {
		GTypeQuery base;
		g_type_query(ADW_TYPE_DIALOG, &base);
		GType registered = g_type_register_static_simple(ADW_TYPE_DIALOG, "WittyCanvasCommandDialog",
			base.class_size, witty_gtk_palette_canvas_class_init, base.instance_size, NULL, 0);
		g_once_init_leave(&type, registered);
	}
}

#endif
