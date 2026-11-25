#ifndef WITTY_GTK_WINDOW_CANVAS_H
#define WITTY_GTK_WINDOW_CANVAS_H

#include "canvas_overlay_linux.h"

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
		GskRenderNode *updated = witty_gtk_canvas_replace_fill(node, mask, &areas[i]);
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
