#ifndef WITTY_GTK_DIALOG_CANVAS_H
#define WITTY_GTK_DIALOG_CANVAS_H

#include "canvas_overlay_linux.h"

static inline GtkWidget *witty_gtk_dialog_canvas_sheet(GtkWidget *dialog) {
#if ADW_CHECK_VERSION(1, 5, 0)
	// In a floating or bottom-sheet presentation, the sheet surrounding
	// the dialog child owns the panel background. Search only its ancestors.
	for (GtkWidget *child = adw_dialog_get_child(ADW_DIALOG(dialog)); child && child != dialog;
			child = gtk_widget_get_parent(child)) {
		if (g_strcmp0(gtk_widget_get_css_name(child), "sheet") == 0
				&& gtk_widget_has_css_class(child, "background"))
			return child;
	}
#else
	(void)dialog;
#endif
	return NULL;
}

static inline void witty_gtk_dialog_canvas_snapshot(GtkWidget *widget, GtkSnapshot *snapshot, bool panel) {
	GtkWidgetClass *parent = g_type_class_peek_parent(GTK_WIDGET_GET_CLASS(widget));
	GdkTexture *mask = g_object_get_data(G_OBJECT(widget), "witty-overlay-mask");
	GtkWidget *content = panel && mask ? witty_gtk_dialog_canvas_sheet(widget)
		: g_object_get_data(G_OBJECT(widget), "witty-dialog-fill-widget");
	graphene_rect_t area;
	if (!mask || !content || !gtk_widget_compute_bounds(content, widget, &area)
			|| area.size.width <= 0 || area.size.height <= 0) {
		parent->snapshot(widget, snapshot);
		return;
	}

	// Preserve GTK's scrim, shadows and control composition.
	GtkSnapshot *layout = gtk_snapshot_new();
	parent->snapshot(widget, layout);
	g_autoptr(GskRenderNode) node = gtk_snapshot_free_to_node(layout);
	if (!node)
		return;
	g_autoptr(GskRenderNode) fill = panel ? witty_gtk_canvas_replace_widget_fill(node, mask, content, &area)
		: witty_gtk_canvas_replace_fill(node, mask, &area, WITTY_CANVAS_LAST_FILL);
	gtk_snapshot_append_node(snapshot, fill ? fill : node);
}

static inline void witty_gtk_dialog_canvas_snapshot_content(GtkWidget *widget, GtkSnapshot *snapshot) {
	witty_gtk_dialog_canvas_snapshot(widget, snapshot, false);
}

static inline void witty_gtk_dialog_canvas_snapshot_panel(GtkWidget *widget, GtkSnapshot *snapshot) {
	witty_gtk_dialog_canvas_snapshot(widget, snapshot, true);
}

static inline void witty_gtk_dialog_canvas_class_init(void *klass, bool panel) {
	GTK_WIDGET_CLASS(klass)->snapshot = panel ? witty_gtk_dialog_canvas_snapshot_panel :
		witty_gtk_dialog_canvas_snapshot_content;
}

static inline void witty_gtk_dialog_canvas_set_fill_widget(GtkWidget *dialog, GtkWidget *content) {
	g_object_set_data(G_OBJECT(dialog), "witty-dialog-fill-widget", content);
}

#endif
