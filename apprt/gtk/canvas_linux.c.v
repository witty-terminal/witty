module gtk

import configpkg
import gg.canvas
import os

#include "@VMODROOT/apprt/gtk/canvas_linux.h"

fn C.gdk_memory_texture_new(int, int, int, GBytes, usize) voidptr
fn C.g_get_user_config_dir() &char
fn C.witty_gtk_canvas_fill_new(mask voidptr) GtkWidget

fn gtk_canvas_styles_enabled(config &configpkg.Config) bool {
	if config.gtk_custom_css.items.len != 0 { return false }
	dir := unsafe { cstring_to_vstring(C.g_get_user_config_dir()) }
	return !os.exists(os.join_path(dir, 'gtk-4.0', 'gtk.css'))
}

fn gtk_canvas_texture(surface canvas.RasterSurface) voidptr {
	stride := uint(surface.width) * sizeof(u32)
	pixels := C.g_bytes_new(surface.pixels.data, stride * uint(surface.height))
	defer { C.g_bytes_unref(pixels) }
	return C.gdk_memory_texture_new(surface.width, surface.height, int(C.GDK_MEMORY_DEFAULT),
		pixels, stride)
}

fn gtk_canvas_solid_mask() voidptr {
	mut mask := canvas.new_raster_surface(width: 1, height: 1) or { return unsafe { nil } }
	mask.clear(0xffffffff)
	return gtk_canvas_texture(mask)
}

fn gtk_canvas_fill_new() GtkWidget {
	mask := gtk_canvas_solid_mask()
	if isnil(mask) { return unsafe { nil } }
	return C.witty_gtk_canvas_fill_new(mask)
}
