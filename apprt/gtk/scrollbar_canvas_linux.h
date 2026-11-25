#ifndef WITTY_GTK_SCROLLBAR_CANVAS_H
#define WITTY_GTK_SCROLLBAR_CANVAS_H

#include "canvas_overlay_linux.h"

static inline GtkWidget *witty_gtk_scrollbar_child(GtkWidget *parent, const char *css_name) {
	if (!parent)
		return NULL;
	for (GtkWidget *child = gtk_widget_get_first_child(parent); child;
			child = gtk_widget_get_next_sibling(child)) {
		if (g_strcmp0(gtk_widget_get_css_name(child), css_name) == 0)
			return child;
	}
	return NULL;
}

static inline void witty_gtk_scrollbar_canvas_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
	GtkWidgetClass *parent = g_type_class_peek(ADW_TYPE_BIN);
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	GtkWidget *scrolled = adw_bin_get_child(ADW_BIN(widget));
	GtkWidget *bar = mask && GTK_IS_SCROLLED_WINDOW(scrolled)
		? gtk_scrolled_window_get_vscrollbar(GTK_SCROLLED_WINDOW(scrolled)) : NULL;
	if (!bar || !gtk_widget_get_mapped(bar)) {
		parent->snapshot(widget, snapshot);
		return;
	}

	// GtkRange owns the track and thumb layout and GtkScrolledWindow owns the fade.
	GtkWidget *range = witty_gtk_scrollbar_child(bar, "range");
	GtkWidget *trough = witty_gtk_scrollbar_child(range, "trough");
	GtkWidget *targets[] = {bar, trough, witty_gtk_scrollbar_child(trough, "slider")};
	GtkSnapshot *layout = gtk_snapshot_new();
	parent->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (!node)
		return;
	// GTK's direct compositing preserves the pixel values of translucent fades.
	for (guint i = 0; i < G_N_ELEMENTS(targets); ++i) {
		GtkWidget *part = targets[i];
		graphene_rect_t area;
		if (!part || !gtk_widget_compute_bounds(part, widget, &area)
				|| area.size.width <= 0 || area.size.height <= 0)
			continue;
		GskRenderNode *fill = witty_gtk_canvas_replace_widget_fill(node, mask, part, &area,
			WITTY_CANVAS_FIRST_FILL);
		if (!fill)
			fill = witty_gtk_canvas_replace_widget_content_fill(node, mask, part, widget, &area,
				WITTY_CANVAS_FIRST_FILL);
		if (fill) {
			gsk_render_node_unref(node);
			node = fill;
		}
	}
	gtk_snapshot_append_node(snapshot, node);
}

static inline void witty_gtk_scrollbar_canvas_class_init(void *klass) {
	GTK_WIDGET_CLASS(klass)->snapshot = witty_gtk_scrollbar_canvas_snapshot;
}

#endif
