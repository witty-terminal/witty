#ifndef WITTY_GTK_CANVAS_H
#define WITTY_GTK_CANVAS_H

#include <gtk/gtk.h>

static inline void witty_gtk_canvas_snapshot_mask(GtkSnapshot *snapshot, GdkTexture *mask,
		const GdkRGBA *tint, const graphene_rect_t *bounds,
		const graphene_rect_t *pieces, size_t count) {
	gtk_snapshot_push_mask(snapshot, GSK_MASK_MODE_ALPHA);
	for (size_t i = 0; i < count; ++i) {
		if (pieces[i].size.width > 0 && pieces[i].size.height > 0)
			gtk_snapshot_append_scaled_texture(snapshot, mask, GSK_SCALING_FILTER_NEAREST, &pieces[i]);
	}
	gtk_snapshot_pop(snapshot);
	gtk_snapshot_append_color(snapshot, tint, bounds);
	gtk_snapshot_pop(snapshot);
}

static inline void witty_gtk_canvas_fill_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-canvas-mask");
	GdkRGBA tint;
	gtk_widget_get_color(widget, &tint);
	const graphene_rect_t bounds = GRAPHENE_RECT_INIT(0, 0,
		gtk_widget_get_width(widget), gtk_widget_get_height(widget));
	witty_gtk_canvas_snapshot_mask(snapshot, mask, &tint, &bounds, &bounds, 1);
}

static inline void witty_gtk_canvas_fill_class_init(void *klass, void *data) {
	(void)data;
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_canvas_fill_snapshot;
}

// The widget takes ownership of the opaque Canvas mask.
static inline GtkWidget *witty_gtk_canvas_fill_new(GdkTexture *mask) {
	static gsize type;
	if (g_once_init_enter(&type)) {
		GType registered = g_type_register_static_simple(GTK_TYPE_WIDGET, "WittyCanvasFill",
			sizeof(GtkWidgetClass), witty_gtk_canvas_fill_class_init, sizeof(GtkWidget), NULL, 0);
		g_once_init_leave(&type, registered);
	}
	GtkWidget *widget = g_object_new(type, NULL);
	g_object_set_data_full(G_OBJECT(widget), "witty-canvas-mask", mask, g_object_unref);
	gtk_widget_set_can_target(widget, FALSE);
	return widget;
}

#endif
