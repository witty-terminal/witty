#ifndef WITTY_GTK_BELL_OVERLAY_H
#define WITTY_GTK_BELL_OVERLAY_H

#include "canvas_linux.h"
#include <stdbool.h>

static inline void witty_gtk_bell_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	if (!gtk_widget_has_css_class(widget, "bell-canvas"))
		return;

	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-bell-mask");
	if (!mask)
		return;
	GdkRGBA tint;
	GtkBorder border;
	gtk_widget_get_color(widget, &tint);
	gtk_style_context_get_border(gtk_widget_get_style_context(widget), &border);

	// GTK allocates the snapshot in content coordinates.
	float x = -border.left;
	float y = -border.top;
	float width = gtk_widget_get_width(widget);
	float height = gtk_widget_get_height(widget);
	float outer_width = width + border.left + border.right;
	float outer_height = height + border.top + border.bottom;
	const graphene_rect_t bounds = GRAPHENE_RECT_INIT(x, y, outer_width, outer_height);

	// The CSS background extends beneath the border. Keep the two paints
	// separate so GTK applies the same blending before the revealer fades.
	if (gtk_check_version(4, 16, 0) == NULL)
		witty_gtk_canvas_snapshot_mask(snapshot, mask, &tint, &bounds, &bounds, 1);

	GskRenderer *renderer = gtk_native_get_renderer(gtk_widget_get_native(widget));
	if (!GSK_IS_CAIRO_RENDERER(renderer)) {
		// GPU compositors use GSK's analytic coverage at the border edges.
		GskRoundedRect outline;
		gsk_rounded_rect_init_from_rect(&outline, &bounds, 0);
		const float widths[] = {border.top, border.right, border.bottom, border.left};
		const GdkRGBA colors[] = {tint, tint, tint, tint};
		gtk_snapshot_append_border(snapshot, &outline, widths, colors);
		return;
	}

	const graphene_rect_t edges[] = {
		GRAPHENE_RECT_INIT(x, y, outer_width, border.top),
		GRAPHENE_RECT_INIT(x, height, outer_width, border.bottom),
		GRAPHENE_RECT_INIT(x, 0, border.left, height),
		GRAPHENE_RECT_INIT(width, 0, border.right, height),
	};
	witty_gtk_canvas_snapshot_mask(snapshot, mask, &tint, &bounds, edges, G_N_ELEMENTS(edges));
}

static inline void witty_gtk_bell_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_bell_snapshot;
}

// The widget takes ownership of the Canvas mask texture.
static inline GtkWidget *witty_gtk_bell_box_new(GdkTexture *mask) {
	static gsize type;
	if (g_once_init_enter(&type)) {
		GType registered = g_type_register_static_simple(GTK_TYPE_BOX, "WittyBellOverlay",
			sizeof(GtkBoxClass), witty_gtk_bell_class_init, sizeof(GtkBox), NULL, 0);
		g_once_init_leave(&type, registered);
	}
	GtkWidget *box = g_object_new(type, NULL);
	g_object_set_data_full(G_OBJECT(box), "witty-bell-mask", mask, g_object_unref);
	return box;
}

static inline void witty_gtk_bell_set_canvas(GtkRevealer *revealer, bool enabled) {
	GtkWidget *box = gtk_revealer_get_child(revealer);
	if (enabled && g_object_get_data(G_OBJECT(box), "witty-bell-mask"))
		gtk_widget_add_css_class(box, "bell-canvas");
	else
		gtk_widget_remove_css_class(box, "bell-canvas");
}

#endif
