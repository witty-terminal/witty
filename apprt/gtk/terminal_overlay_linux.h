#ifndef WITTY_GTK_TERMINAL_OVERLAY_H
#define WITTY_GTK_TERMINAL_OVERLAY_H

#include "canvas_overlay_linux.h"

typedef enum {
	WITTY_OVERLAY_NATIVE,
	WITTY_OVERLAY_BADGE,
	WITTY_OVERLAY_DIMMING,
} WittyOverlayPaint;

static inline WittyOverlayPaint witty_gtk_terminal_overlay_paint(GtkWidget *child) {
	WittyOverlayPaint paint = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(child), "witty-overlay-decoration"));
	if (paint != WITTY_OVERLAY_NATIVE && GTK_IS_REVEALER(child)) {
		GtkWidget *contents = gtk_revealer_get_child(GTK_REVEALER(child));
		if (!contents || !gtk_widget_get_mapped(contents))
			return WITTY_OVERLAY_NATIVE;
	}
	return paint;
}

static inline void witty_gtk_terminal_overlay_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	if (!mask) {
		GtkWidgetClass *native_class = g_type_class_peek(GTK_TYPE_OVERLAY);
		native_class->snapshot(widget, snapshot);
		return;
	}

	GtkOverlay *overlay = GTK_OVERLAY(widget);
	const graphene_rect_t bounds = GRAPHENE_RECT_INIT(0, 0,
		gtk_widget_get_width(widget), gtk_widget_get_height(widget));
	// Preserve GtkOverlay's child order and per-child clipping.
	for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
			child = gtk_widget_get_next_sibling(child)) {
		if (!gtk_widget_get_mapped(child))
			continue;
		const bool clip = gtk_overlay_get_clip_overlay(overlay, child);
		if (clip)
			gtk_snapshot_push_clip(snapshot, &bounds);
		const WittyOverlayPaint paint = witty_gtk_terminal_overlay_paint(child);
		if (paint != WITTY_OVERLAY_NATIVE) {
			GtkSnapshot *layout = gtk_snapshot_new();
			gtk_widget_snapshot_child(widget, child, layout);
			g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
			if (node)
				witty_gtk_canvas_overlay_append(snapshot, mask, node, paint == WITTY_OVERLAY_BADGE,
					paint == WITTY_OVERLAY_DIMMING);
		} else {
			gtk_widget_snapshot_child(widget, child, snapshot);
		}
		if (clip)
			gtk_snapshot_pop(snapshot);
	}
}

static inline void witty_gtk_terminal_overlay_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_terminal_overlay_snapshot;
}

static inline GtkWidget *witty_gtk_terminal_overlay_new(void) {
	if (g_type_test_flags(GTK_TYPE_OVERLAY, G_TYPE_FLAG_FINAL))
		return gtk_overlay_new();
	static gsize type;
	if (g_once_init_enter(&type)) {
		GTypeQuery base;
		g_type_query(GTK_TYPE_OVERLAY, &base);
		GType registered = g_type_register_static_simple(GTK_TYPE_OVERLAY, "WittyTerminalOverlay",
			base.class_size, witty_gtk_terminal_overlay_class_init, base.instance_size, NULL, 0);
		g_once_init_leave(&type, registered);
	}
	return g_object_new(type, NULL);
}

static inline void witty_gtk_terminal_overlay_add(GtkOverlay *overlay, GtkWidget *child, bool dimming) {
	g_object_set_data(G_OBJECT(child), "witty-overlay-decoration",
		GINT_TO_POINTER(dimming ? WITTY_OVERLAY_DIMMING : WITTY_OVERLAY_BADGE));
	gtk_overlay_add_overlay(overlay, child);
}

#endif
