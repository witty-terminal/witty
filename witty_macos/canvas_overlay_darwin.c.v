module witty_macos

import gg.canvas
import math

#insert "@VMODROOT/witty_macos/canvas_overlay_darwin.h"

fn C.witty_canvas_place_overlay(parent voidptr, child voidptr, above voidptr)
fn C.witty_canvas_backing_phases(view ObjId) int
fn C.witty_canvas_rect_backing_phases(view ObjId, rect &ObjCRect) int
fn C.witty_canvas_set_layer_mask(layer ObjId, pixels &u32, width int, height int, scale f64)
fn C.witty_canvas_resolve_srgb(view ObjId, color ObjId) u32
fn C.witty_canvas_resolve_srgb_alpha(view ObjId, color ObjId, alpha &f64) u32
fn C.witty_canvas_set_translucent_fill(layer ObjId, view ObjId, color ObjId, opacity f64)
fn C.witty_canvas_set_layer_srgb_fill(layer ObjId, r f32, g f32, b f32, a f32)
fn C.witty_canvas_make_srgb_tile(r f32, g f32, b f32, a f32) voidptr
fn C.witty_canvas_make_tile(pixel &u32, target ObjId, opacity f64, blend_over_gray int) voidptr
fn C.witty_canvas_make_alpha_image(pixels &u32, width int, height int, color u32, target ObjId) voidptr
fn C.witty_canvas_make_gradient_mask(coverage &f32, width int, height int, color u32, target ObjId) voidptr
fn C.witty_canvas_make_color_image(pixels &u32, width int, height int) voidptr
fn C.witty_canvas_make_native_color_mask(pixels &u32, width int, height int, view ObjId, color ObjId) voidptr
fn C.witty_canvas_present_tile(target voidptr, image voidptr, positions voidptr, count int)
fn C.witty_canvas_system_symbol(name ObjId, size f64, weight f64) ObjId
fn C.witty_canvas_pixel_bounds(context voidptr, frame &ObjCRect, bounds &ObjCRect, width &int, height &int)
fn C.witty_canvas_rasterize_attributed_text(text ObjId, frame &ObjCRect, bounds &ObjCRect, pixels &u32, width int, height int, flipped bool) voidptr
fn C.witty_canvas_symbol_mask(symbol ObjId, glyph &ObjCRect, bounds &ObjCRect, pixels &u32, width int, height int, flipped bool) bool
fn C.witty_canvas_present_oriented_image(context voidptr, image voidptr, bounds &ObjCRect, flipped bool)
fn C.witty_canvas_make_text_mask(pixels &u32, width int, height int) voidptr
fn C.witty_canvas_present_text_mask(context voidptr, mask voidptr, bounds &ObjCRect, tint ObjId, flipped bool)

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

fn native_canvas_draw_mask(context voidptr, view ObjId, frame ObjCRect, mask canvas.RasterSurface, color u32) {
	image := C.witty_canvas_make_alpha_image(mask.pixels.data, mask.width, mask.height, color, view)
	if is_nil(image) { return }
	C.witty_canvas_present_tile(context, image, &frame, 1)
	C.CFRelease(image)
}

fn native_canvas_rasterize_symbol(context voidptr, view ObjId, symbol ObjId, glyph ObjCRect) !(canvas.RasterSurface, ObjCRect) {
	if is_nil(symbol) { return error('missing symbol image') }
	mut bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, &glyph, &bounds, &width, &height)
	mut mask := canvas.new_raster_surface(width: width, height: height)!
	if !C.witty_canvas_symbol_mask(symbol, &glyph, &bounds, mask.pixels.data, width, height,
		msg_bool(view, 'isFlipped')) {
		return error('could not rasterize symbol')
	}
	return mask, bounds
}

fn native_canvas_draw_symbol(context voidptr, view ObjId, symbol ObjId, glyph ObjCRect, color ObjId) {
	mask, bounds := native_canvas_rasterize_symbol(context, view, symbol, glyph) or { return }
	image := C.witty_canvas_make_native_color_mask(mask.pixels.data, mask.width, mask.height, view,
		color)
	if is_nil(image) { return }
	C.witty_canvas_present_oriented_image(context, image, &bounds, msg_bool(view, 'isFlipped'))
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
	target          ObjId
	opacity         f64 = 1
	blend_over_gray ?u8
}

fn native_canvas_fill_tile(color u32, opts NativeCanvasTileOptions) voidptr {
	mut tile := canvas.new_raster_surface(width: 1, height: 1) or { return unsafe { nil } }
	tile.clear(0xff000000 | color)
	gray := if value := opts.blend_over_gray { int(value) } else { -1 }
	return C.witty_canvas_make_tile(unsafe { &tile.pixels[0] }, opts.target, opts.opacity, gray)
}

fn set_native_canvas_srgb_tile(layer ObjId, color canvas.Color4f) bool {
	pixel := color.premul()
	image := C.witty_canvas_make_srgb_tile(pixel.r, pixel.g, pixel.b, pixel.a)
	if is_nil(image) { return false }
	msg_void1(layer, 'setContents:', ObjId(image))
	C.CFRelease(image)
	return true
}

// Present a solid Canvas paint directly when Core Animation composites the
// final pixels. Keep its source precision through the profile conversion.
fn native_canvas_layer_fill(layer ObjId, rgb u32, brightness f64) {
	color := canvas.Color4f.from_rgba8(u8(rgb >> 16), u8(rgb >> 8), u8(rgb), 255)
	shade := f32(brightness)
	C.witty_canvas_set_layer_srgb_fill(layer, color.r * shade, color.g * shade, color.b * shade, 1)
}

fn native_canvas_fill_rects(context voidptr, color u32, rects []ObjCRect) {
	if is_nil(context) || rects.len == 0 { return }
	tile := native_canvas_fill_tile(color)
	if is_nil(tile) { return }
	C.witty_canvas_present_tile(context, tile, rects.data, rects.len)
	C.CFRelease(tile)
}
