module gtk

import gg.canvas

#include <gtk/gtk.h>

fn C.gdk_memory_texture_new(int, int, int, GBytes, uint) voidptr

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
