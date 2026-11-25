module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/canvas_overlay_darwin.h"

fn C.witty_canvas_place_overlay(parent voidptr, child voidptr, above voidptr)
fn C.witty_canvas_resolve_srgb(view ObjId, color ObjId) u32
fn C.witty_canvas_resolve_srgb_alpha(view ObjId, color ObjId, alpha &f64) u32
fn C.witty_canvas_make_tile(pixel &u32, target ObjId, opacity f64) voidptr
fn C.witty_canvas_make_alpha_image(pixels &u32, width int, height int, color u32, target ObjId) voidptr
fn C.witty_canvas_make_color_image(pixels &u32, width int, height int) voidptr
fn C.witty_canvas_present_tile(target voidptr, image voidptr, positions voidptr, count int)
fn C.witty_canvas_set_material_mask(view ObjId, image voidptr, width f64, height f64)

fn native_canvas_material_view(frame ObjCRect) ObjId {
	mut cls := get_class('WittyCanvasMaterial')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSVisualEffectView'),
			cstr('WittyCanvasMaterial'), 0)
		add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(cls)
	}
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', frame)
	// Active popover material corresponds to SwiftUI's regular material.
	msg_void_u64(view, 'setMaterial:', 6)
	msg_void_u64(view, 'setBlendingMode:', 1)
	msg_void_u64(view, 'setState:', 1)
	msg_void_bool(view, 'setAccessibilityElement:', false)
	return view
}

fn native_canvas_mask_material(view ObjId, width f64, height f64, mask canvas.RasterSurface) bool {
	image := C.witty_canvas_make_alpha_image(mask.pixels.data, mask.width, mask.height, 0xffffff,
		nil_obj())
	if is_nil(image) { return false }
	C.witty_canvas_set_material_mask(view, image, width, height)
	C.CFRelease(image)
	return true
}

fn native_canvas_draw_mask(context voidptr, view ObjId, frame ObjCRect, mask canvas.RasterSurface, color u32) {
	image := C.witty_canvas_make_alpha_image(mask.pixels.data, mask.width, mask.height, color, view)
	if is_nil(image) { return }
	C.witty_canvas_present_tile(context, image, &frame, 1)
	C.CFRelease(image)
}

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

@[params]
struct NativeCanvasTileOptions {
	target  ObjId
	opacity f64 = 1
}

fn native_canvas_fill_tile(color u32, opts NativeCanvasTileOptions) voidptr {
	mut tile := canvas.new_raster_surface(width: 1, height: 1) or { return unsafe { nil } }
	tile.clear(0xff000000 | color)
	return C.witty_canvas_make_tile(unsafe { &tile.pixels[0] }, opts.target, opts.opacity)
}

fn native_canvas_fill_rects(context voidptr, color u32, rects []ObjCRect) {
	if is_nil(context) || rects.len == 0 { return }
	tile := native_canvas_fill_tile(color)
	if is_nil(tile) { return }
	C.witty_canvas_present_tile(context, tile, rects.data, rects.len)
	C.CFRelease(tile)
}
