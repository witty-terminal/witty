#ifndef WITTY_GTK_WINDOW_CANVAS_H
#define WITTY_GTK_WINDOW_CANVAS_H

#include "canvas_overlay_linux.h"

static inline GtkWidget *witty_gtk_window_canvas_next_toast(GtkWidget *child, GtkWidget *content) {
	for (; child; child = gtk_widget_get_next_sibling(child)) {
		if (child != content && gtk_widget_get_mapped(child))
			return child;
	}
	return NULL;
}

static inline void witty_gtk_window_canvas_replace_fill(GskRenderNode **node, GdkTexture *mask,
		const graphene_rect_t *area) {
	GskRenderNode *updated = witty_gtk_canvas_replace_fill(*node, mask, area, WITTY_CANVAS_FIRST_FILL);
	if (updated) {
		gsk_render_node_unref(*node);
		*node = updated;
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
	GtkWidget *content = adw_application_window_get_content(ADW_APPLICATION_WINDOW(widget));
	if (ADW_IS_TAB_OVERVIEW(content) && adw_tab_overview_get_open(ADW_TAB_OVERVIEW(content))) {
		// The open overview replaces the title bars with its own backdrop.
		if (gtk_widget_compute_bounds(content, widget, &areas[0])
				&& areas[0].size.width > 0 && areas[0].size.height > 0)
			count = 1;
	} else {
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
	}
	GtkWidget *overlay = g_object_get_data(G_OBJECT(widget), "witty-canvas-toast-overlay");
	GtkWidget *toast_content = NULL;
	GtkWidget *toast = NULL;
	if (overlay && gtk_widget_get_mapped(overlay)) {
		toast_content = adw_toast_overlay_get_child(ADW_TOAST_OVERLAY(overlay));
		toast = witty_gtk_window_canvas_next_toast(gtk_widget_get_first_child(overlay), toast_content);
	}
	if (!count && !toast) {
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkSnapshot *layout = gtk_snapshot_new();
	native_class->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (!node)
		return;
	for (guint i = 0; i < count; ++i)
		witty_gtk_window_canvas_replace_fill(&node, mask, &areas[i]);
	// A disappearing toast may still be mapped while its replacement enters.
	for (; toast; toast = witty_gtk_window_canvas_next_toast(gtk_widget_get_next_sibling(toast), toast_content)) {
		graphene_rect_t area;
		if (gtk_widget_compute_bounds(toast, widget, &area))
			witty_gtk_window_canvas_replace_fill(&node, mask, &area);
	}
	gtk_snapshot_append_node(snapshot, node);
}

static inline void witty_gtk_window_canvas_class_init(void *klass) {
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_window_canvas_snapshot;
}

static inline void witty_gtk_window_canvas_set_widgets(GtkWidget *window, GtkWidget *header,
		GtkWidget *tabs, GtkWidget *overlay) {
	g_object_set_data(G_OBJECT(window), "witty-canvas-headerbar", header);
	g_object_set_data(G_OBJECT(window), "witty-canvas-tabbar", tabs);
	g_object_set_data(G_OBJECT(window), "witty-canvas-toast-overlay", overlay);
}

#endif
