module gtk

import configpkg
import encoding.base64
import gg.canvas
import os

fn C.gdk_memory_texture_new(int, int, int, GBytes, usize) voidptr
fn C.gdk_texture_save_to_png_bytes(voidptr) GBytes
fn C.g_get_user_config_dir() &char

fn has_gtk_user_stylesheet() bool {
	dir := unsafe { cstring_to_vstring(C.g_get_user_config_dir()) }
	return os.exists(os.join_path(dir, 'gtk-4.0', 'gtk.css'))
}

// The runtime stylesheet shares the tile across panes. GTK applies opacity
// after compositing the fill, as it does with a CSS background color.
fn split_background_style(fill configpkg.ColorRGB, use_canvas bool, fallback_property string) string {
	if use_canvas {
		if tile := split_canvas_tile(fill) {
			return ' background: url("data:image/png;base64,${tile}") center / 100% 100% no-repeat;\n'
		}
	}
	return ' ${fallback_property}: rgb(${fill.r},${fill.g},${fill.b});\n'
}

fn split_canvas_tile(fill configpkg.ColorRGB) ?string {
	mut tile := canvas.new_raster_surface(width: 1, height: 1) or { return none }
	tile.clear(u32(0xff000000) | u32(fill.r) << 16 | u32(fill.g) << 8 | u32(fill.b))
	pixels := C.g_bytes_new(tile.pixels.data, sizeof(u32))
	defer { C.g_bytes_unref(pixels) }
	texture := C.gdk_memory_texture_new(tile.width, tile.height, int(C.GDK_MEMORY_DEFAULT),
		pixels, sizeof(u32))
	if isnil(texture) { return none }
	defer { object_unref(GObject(texture)) }
	png := C.gdk_texture_save_to_png_bytes(texture)
	if isnil(png) { return none }
	defer { C.g_bytes_unref(png) }
	mut size := uint(0)
	data := C.g_bytes_get_data(png, &size)
	return base64.encode_str(unsafe { tos(&u8(data), int(size)) })
}
