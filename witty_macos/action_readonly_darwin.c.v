module witty_macos

import gg.canvas
import math

#insert "@VMODROOT/witty_macos/action_readonly_darwin.h"

fn C.witty_readonly_title_width(title ObjId) f64
fn C.witty_readonly_rasterize_title(title ObjId, tint ObjId, bounds &ObjCRect, pixels &u32, width int, height int) voidptr
fn C.witty_readonly_configure_layers(material ObjId, ink ObjId, corner f64, border f64)
fn C.witty_readonly_outline(ink ObjId) ObjId
fn C.witty_readonly_update_outline(ink ObjId)
fn C.witty_readonly_present_eye(ink ObjId, tint ObjId, bounds &ObjCRect, pixels &u32, width int, height int)

const readonly_title = 'Read-only'
const readonly_height = 23.0
const readonly_margin = 8.0
const readonly_corner = 6.0
const readonly_border_width = 1.5

fn (mut surface NativeActionSurface) initialize_readonly_badge() {
	mut ink_class := get_class('WittyReadonlyInk')
	if is_nil(ink_class) {
		ink_class = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyReadonlyInk'), 0)
		add_method(ink_class, 'drawRect:', voidptr(readonly_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(ink_class, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(ink_class)
	}
	frame := objc_rect(0, 0, 0, readonly_height)
	surface.readonly_badge = action_button(surface, readonly_title, 'readonly:', frame)
	msg_void_bool(surface.readonly_badge, 'setHidden:', true)
	msg_void_bool(surface.readonly_badge, 'setBordered:', false)
	msg_void_bool(surface.readonly_badge, 'setTransparent:', true)
	msg_void_bool(surface.readonly_badge, 'setWantsLayer:', true)
	msg_void1(surface.readonly_badge, 'setAccessibilityLabel:', nsstring('Read-only terminal'))
	msg_void1(surface.overlay, 'addSubview:', surface.readonly_badge)
	msg_void(surface.readonly_badge, 'release')

	surface.readonly_material = native_canvas_material_view(frame)
	surface.readonly_ink = msg_id_rect(msg_id(ink_class, 'alloc'), 'initWithFrame:', frame)
	for part in [surface.readonly_material, surface.readonly_ink] {
		msg_void_u64(part, 'setAutoresizingMask:', 18)
		msg_void_bool(part, 'setAccessibilityElement:', false)
		msg_void1(surface.readonly_badge, 'addSubview:', part)
		msg_void(part, 'release')
	}
	C.witty_readonly_configure_layers(surface.readonly_material, surface.readonly_ink,
		readonly_corner, readonly_border_width)
	surface.readonly_title_width = C.witty_readonly_title_width(nsstring(readonly_title))
}

fn (mut surface NativeActionSurface) refresh_readonly_badge() {
	if is_nil(surface.readonly_badge) { return }
	msg_void_bool(surface.readonly_badge, 'setHidden:', !surface.readonly)
	if !surface.readonly { return }
	surface.refresh_readonly_appearance()
	scale := view_backing_scale(surface.view)
	// Two 8-point insets, an 18-point SF Symbol and 5 points of spacing.
	width := math.ceil((surface.readonly_title_width + 39) * scale) / scale
	x := math.max(0, view_width(surface.view) - readonly_margin - width)
	msg_void_rect(surface.readonly_badge, 'setFrame:', objc_rect(x, readonly_margin, width, readonly_height))
	if surface.readonly_scale == scale { return }
	surface.readonly_scale = scale
	msg_void_bool(surface.readonly_ink, 'setNeedsDisplay:', true)
}

fn (surface &NativeActionSurface) refresh_readonly_appearance() {
	if !surface.readonly || is_nil(surface.readonly_badge) { return }
	appearance := msg_id(view_window(surface.view), 'effectiveAppearance')
	if !is_nil(appearance) && msg_id(surface.readonly_badge, 'appearance') != appearance {
		// The scroll view can use a different appearance for its scrollbar.
		msg_void1(surface.readonly_badge, 'setAppearance:', appearance)
		msg_void_bool(surface.readonly_ink, 'setNeedsDisplay:', true)
	}
}

fn readonly_draw(self ObjId, _cmd Sel, _rect ObjCRect) {
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	C.witty_readonly_update_outline(self)
	bounds := msg_rect(self, 'bounds')
	scale := view_backing_scale(voidptr(self))
	w := int(math.round(bounds.width * scale))
	h := int(math.round(bounds.height * scale))
	bitmap := C.CGBitmapContextGetBitsPerComponent(context) > 0
	mut raster := if bitmap {
		native_canvas_rounded_mask(w, h, readonly_corner * scale, style: .continuous,
			stroke: readonly_border_width * scale, opacity: 0.6) or { return }
	} else {
		canvas.new_raster_surface(width: w, height: h) or { return }
	}
	if bitmap {
		color := C.witty_canvas_resolve_srgb(self, msg_id(get_class('NSColor'), 'systemOrangeColor'))
		native_canvas_draw_mask(context, self, bounds, raster, color)
		raster.clear(0)
	}
	tint := C.witty_macos_color_rgba(0.8, 0.592, 0.4, 1)
	symbol := C.witty_canvas_system_symbol(nsstring('eye.fill'), 12, 0)
	glyph := objc_rect(8, (bounds.height - 12) / 2, 18, 12)
	if bitmap {
		native_canvas_draw_symbol(context, self, symbol, glyph, tint)
	} else if mask, eye_bounds := native_canvas_rasterize_symbol(context, self, symbol, glyph) {
		C.witty_readonly_present_eye(self, tint, &eye_bounds, mask.pixels.data, mask.width,
			mask.height)
	}
	image := C.witty_readonly_rasterize_title(nsstring(readonly_title), tint, &bounds,
		raster.pixels.data, w, h)
	if is_nil(image) { return }
	C.witty_canvas_present_text_mask(context, image, &bounds, tint, false)
	C.CFRelease(image)
}
