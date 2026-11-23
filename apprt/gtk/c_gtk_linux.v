module gtk

// c_gtk_linux.v - Shared GTK/GObject/GDK C bindings for the GTK apprt.
//
// Translated/adapted from the C imports scattered across ghostty's
// src/apprt/gtk/ (gtk4 / libadwaita / glib / gobject / gdk).
//
// PLATFORM: This file is compiled ONLY on Linux (the `_linux.v` suffix), so
// the `#flag`/`#include` directives and `fn C.*` declarations below never
// affect the macOS build. GTK is not installed on macOS.
//
// All opaque GTK/GObject/GDK pointers are modeled as simple `voidptr` type
// aliases. This avoids having to declare the corresponding C structs (and the
// attendant collisions), while still giving us readable, self-documenting
// signatures.

#flag linux -DGTK_APPRT
#flag linux -I @VMODROOT/.witty-build/gtk
#flag linux @VMODROOT/.witty-build/gtk/witty_resources.c
#pkgconfig gtk4
#pkgconfig libadwaita-1

#include <gtk/gtk.h>

#include <adwaita.h>

#include <glib-unix.h>

// --- Opaque handle type aliases -------------------------------------------
//
// These are all just `voidptr`. Declared once here for the whole module.

// GObject core
pub type GObject = voidptr
pub type GType = uint
pub type GVariant = voidptr
pub type GError = voidptr

// GLib / GIO application
pub type GApplication = voidptr
pub type GApplicationFlags = int

// GTK
pub type GtkWidget = voidptr
pub type GtkWindow = voidptr
pub type GtkApplication = voidptr
pub type GtkApplicationWindow = voidptr

// GDK
pub type GdkDisplay = voidptr
pub type GdkSurface = voidptr
pub type GdkDevice = voidptr
pub type GdkEvent = voidptr
pub type GdkKeyEvent = voidptr
pub type GdkKeymap = voidptr

// libadwaita
pub type AdwApplication = voidptr

fn C.gtk_init_check() bool

// --- GObject reference counting -------------------------------------------

fn C.g_object_ref(obj GObject) GObject
fn C.g_object_unref(obj GObject)

// object_ref increments the reference count of a GObject.
pub fn object_ref(obj GObject) GObject {
	return C.g_object_ref(obj)
}

// object_unref decrements the reference count of a GObject.
pub fn object_unref(obj GObject) {
	C.g_object_unref(obj)
}

// --- GLib memory ----------------------------------------------------------

fn C.g_free(mem voidptr)

// g_free_mem frees memory allocated by GLib.
pub fn g_free_mem(mem voidptr) {
	C.g_free(mem)
}

// --- Core GTK widget functions --------------------------------------------

fn C.gtk_widget_get_display(widget GtkWidget) GdkDisplay
fn C.gtk_widget_grab_focus(widget GtkWidget) bool
fn C.gtk_widget_queue_draw(widget GtkWidget)
fn C.gtk_widget_get_scale_factor(widget GtkWidget) int
fn C.gtk_widget_show(widget GtkWidget)
fn C.gtk_widget_get_width(widget GtkWidget) int
fn C.gtk_widget_get_height(widget GtkWidget) int

fn C.gdk_display_get_default() GdkDisplay

// widget_get_display returns the GdkDisplay for a widget.
pub fn widget_get_display(widget GtkWidget) GdkDisplay {
	return C.gtk_widget_get_display(widget)
}

// widget_grab_focus causes a widget to have keyboard focus.
pub fn widget_grab_focus(widget GtkWidget) bool {
	return C.gtk_widget_grab_focus(widget)
}

// widget_queue_draw schedules a redraw of the widget.
pub fn widget_queue_draw(widget GtkWidget) {
	C.gtk_widget_queue_draw(widget)
}

// --- GDK keyval helpers ---------------------------------------------------
// These are shared by key_linux.v (used for trigger/keyval string building).

fn C.gdk_keyval_name(keyval u32) &char
fn C.gdk_keyval_to_unicode(keyval u32) u32
fn C.gdk_keyval_from_name(name &char) u32

// keyval_name returns the string name for a GDK keyval, or nil if none.
// The returned string is owned by GDK and must not be freed.
pub fn keyval_name(keyval u32) &char {
	return C.gdk_keyval_name(keyval)
}

// keyval_to_unicode converts a GDK keyval to a Unicode codepoint, or 0.
pub fn keyval_to_unicode(keyval u32) u32 {
	return C.gdk_keyval_to_unicode(keyval)
}
