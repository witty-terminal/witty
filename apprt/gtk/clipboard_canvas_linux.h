#ifndef WITTY_GTK_CLIPBOARD_CANVAS_H
#define WITTY_GTK_CLIPBOARD_CANVAS_H

#include "canvas_overlay_linux.h"

static inline void witty_gtk_clipboard_dialog_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *parent = g_type_class_peek_parent(GTK_WIDGET_GET_CLASS(widget));
	GtkWidget *preview = g_object_get_data(G_OBJECT(widget), "witty-clipboard-preview");
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	graphene_rect_t area;
	if (!mask || !preview || !gtk_widget_compute_bounds(preview, widget, &area)
			|| area.size.width <= 0 || area.size.height <= 0) {
		parent->snapshot(widget, snapshot);
		return;
	}

	// The matched opaque fill covers the text viewport. The scrim,
	// preview blur and rounded controls retain GTK's native blending.
	GtkSnapshot *layout = gtk_snapshot_new();
	parent->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (!node)
		return;
	g_autoptr(GskRenderNode) fill = witty_gtk_canvas_replace_flat_fill(node, mask, &area);
	gtk_snapshot_append_node(snapshot, fill ? fill : node);
}

static inline void witty_gtk_clipboard_canvas_class_init(void *klass) {
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_clipboard_dialog_snapshot;
}

static inline void witty_gtk_clipboard_canvas_set_preview(GtkWidget *dialog, GtkWidget *preview) {
	g_object_set_data(G_OBJECT(dialog), "witty-clipboard-preview", preview);
}

#endif
