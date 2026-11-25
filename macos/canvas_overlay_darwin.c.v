module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/canvas_overlay_darwin.h"

fn C.witty_canvas_place_overlay(parent voidptr, child voidptr, above voidptr)
fn C.witty_canvas_present_tile(target voidptr, pixel &u32, positions voidptr, count int)

fn native_canvas_overlay_context() voidptr {
	return voidptr(msg_id(msg_id(get_class('NSGraphicsContext'), 'currentContext'), 'CGContext'))
}

fn native_canvas_overlay_rect(rect SplitBounds, scale f64) ObjCRect {
	// Snap both edges in flipped view coordinates, as SwiftUI does.
	x := math.round(rect.x * scale)
	y := math.round(rect.y * scale)
	right := math.round((rect.x + rect.width) * scale)
	bottom := math.round((rect.y + rect.height) * scale)
	return objc_rect(x / scale, y / scale, (right - x) / scale, (bottom - y) / scale)
}

fn native_canvas_fill_rects(context voidptr, color u32, rects []ObjCRect) {
	if is_nil(context) || rects.len == 0 { return }
	mut tile := canvas.new_raster_surface(width: 1, height: 1) or { return }
	tile.clear(0xff000000 | color)
	C.witty_canvas_present_tile(context, unsafe { &tile.pixels[0] }, rects.data, rects.len)
}
