#ifndef WITTY_GTK_WINDOW_CANVAS_H
#define WITTY_GTK_WINDOW_CANVAS_H

#include "canvas_overlay_linux.h"

// Replace the flat toolbar fill at its allocated bounds, preserving unrelated
// branches and the native composition of the toolbar controls.
static inline GskRenderNode *witty_gtk_window_canvas_background(GskRenderNode *node,
		GdkTexture *mask, const graphene_rect_t *area) {
	graphene_rect_t bounds;
	gsk_render_node_get_bounds(node, &bounds);
	if (!graphene_rect_contains_rect(&bounds, area))
		return NULL;

	switch (gsk_render_node_get_node_type(node)) {
	case GSK_COLOR_NODE: {
		const GdkRGBA *color = gsk_color_node_get_color(node);
		if (!graphene_rect_equal(&bounds, area) || color->alpha != 1)
			return NULL;
		GtkSnapshot *snapshot = gtk_snapshot_new();
		witty_gtk_canvas_snapshot_mask(snapshot, mask, color, &bounds, &bounds, 1);
		return gtk_snapshot_free_to_node(snapshot);
	}
	case GSK_CONTAINER_NODE: {
		const guint count = gsk_container_node_get_n_children(node);
		for (guint i = 0; i < count; ++i) {
			GskRenderNode *child = gsk_container_node_get_child(node, i);
			g_autoptr(GskRenderNode) fill = witty_gtk_window_canvas_background(child, mask, area);
			if (!fill)
				continue;
			GtkSnapshot *snapshot = gtk_snapshot_new();
			for (guint j = 0; j < count; ++j)
				gtk_snapshot_append_node(snapshot, j == i ? fill : gsk_container_node_get_child(node, j));
			return gtk_snapshot_free_to_node(snapshot);
		}
		return NULL;
	}
	case GSK_TRANSFORM_NODE: {
		GskTransform *transform = gsk_transform_node_get_transform(node);
		if (gsk_transform_get_category(transform) < GSK_TRANSFORM_CATEGORY_2D_TRANSLATE)
			return NULL;
		float x, y;
		gsk_transform_to_translate(transform, &x, &y);
		if (x != floorf(x) || y != floorf(y))
			return NULL;
		const graphene_rect_t local = GRAPHENE_RECT_INIT(area->origin.x - x, area->origin.y - y,
			area->size.width, area->size.height);
		g_autoptr(GskRenderNode) fill = witty_gtk_window_canvas_background(
			gsk_transform_node_get_child(node), mask, &local);
		return fill ? gsk_transform_node_new(fill, transform) : NULL;
	}
	case GSK_CLIP_NODE: {
		g_autoptr(GskRenderNode) fill = witty_gtk_window_canvas_background(
			gsk_clip_node_get_child(node), mask, area);
		return fill ? gsk_clip_node_new(fill, gsk_clip_node_get_clip(node)) : NULL;
	}
	case GSK_ROUNDED_CLIP_NODE: {
		const GskRoundedRect *clip = gsk_rounded_clip_node_get_clip(node);
		if (!gsk_rounded_rect_contains_rect(clip, area))
			return NULL;
		g_autoptr(GskRenderNode) fill = witty_gtk_window_canvas_background(
			gsk_rounded_clip_node_get_child(node), mask, area);
		return fill ? gsk_rounded_clip_node_new(fill, clip) : NULL;
	}
	default:
		return NULL;
	}
}

static inline void witty_gtk_window_canvas_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *native_class = g_type_class_peek(ADW_TYPE_APPLICATION_WINDOW);
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	if (!mask) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkWidget *bars[] = {
		g_object_get_data(G_OBJECT(widget), "witty-canvas-headerbar"),
		g_object_get_data(G_OBJECT(widget), "witty-canvas-tabbar"),
	};
	graphene_rect_t areas[G_N_ELEMENTS(bars)];
	guint count = 0;
	GtkWidget *last_handle = NULL;
	for (guint i = 0; i < G_N_ELEMENTS(bars); ++i) {
		if (!bars[i] || !gtk_widget_get_mapped(bars[i]))
			continue;
		GtkWidget *handle = gtk_widget_get_ancestor(bars[i], GTK_TYPE_WINDOW_HANDLE);
		if (!handle || handle == last_handle)
			continue;
		graphene_rect_t area;
		if (gtk_widget_compute_bounds(handle, widget, &area)
				&& area.size.width > 0 && area.size.height > 0) {
			areas[count++] = area;
			last_handle = handle;
		}
	}
	if (!count) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	for (guint i = 0; node && i < count; ++i) {
		GskRenderNode *updated = witty_gtk_window_canvas_background(node, mask, &areas[i]);
		if (updated) {
			gsk_render_node_unref(node);
			node = updated;
		}
	}
	if (node)
		gtk_snapshot_append_node(snapshot, node);
}

static inline void witty_gtk_window_canvas_class_init(void *klass) {
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_window_canvas_snapshot;
}

static inline void witty_gtk_window_canvas_set_bars(GtkWidget *window, GtkWidget *header, GtkWidget *tabs) {
	g_object_set_data(G_OBJECT(window), "witty-canvas-headerbar", header);
	g_object_set_data(G_OBJECT(window), "witty-canvas-tabbar", tabs);
}

#endif
