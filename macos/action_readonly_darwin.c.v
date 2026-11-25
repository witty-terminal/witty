module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/action_readonly_darwin.h"

fn C.witty_readonly_title_width(title ObjId) f64
fn C.witty_readonly_set_mask(view ObjId, image voidptr, width f64, height f64)
fn C.witty_readonly_draw_content(context voidptr, title ObjId, height f64)

const readonly_title = 'Read-only'
const readonly_height = 23.0
const readonly_margin = 8.0
const readonly_corner = 6.0
const readonly_border_width = 1.5

fn (mut surface NativeActionSurface) initialize_readonly_badge() {
	mut material_class := get_class('WittyReadonlyMaterial')
	if is_nil(material_class) {
		material_class = C.macos_objc_allocate_class_pair(get_class('NSVisualEffectView'),
			cstr('WittyReadonlyMaterial'), 0)
		add_method(material_class, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(material_class)
	}
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

	surface.readonly_material = msg_id_rect(msg_id(material_class, 'alloc'), 'initWithFrame:', frame)
	// The popover material in its active state matches SwiftUI's regular material.
	msg_void_u64(surface.readonly_material, 'setMaterial:', 6)
	msg_void_u64(surface.readonly_material, 'setBlendingMode:', 1)
	msg_void_u64(surface.readonly_material, 'setState:', 1)
	surface.readonly_ink = msg_id_rect(msg_id(ink_class, 'alloc'), 'initWithFrame:', frame)
	for part in [surface.readonly_material, surface.readonly_ink] {
		msg_void_u64(part, 'setAutoresizingMask:', 18)
		msg_void_bool(part, 'setAccessibilityElement:', false)
		msg_void1(surface.readonly_badge, 'addSubview:', part)
		msg_void(part, 'release')
	}
	surface.readonly_title_width = C.witty_readonly_title_width(nsstring(readonly_title))
}

fn (mut surface NativeActionSurface) refresh_readonly_badge() {
	if is_nil(surface.readonly_badge) { return }
	msg_void_bool(surface.readonly_badge, 'setHidden:', !surface.readonly)
	if !surface.readonly { return }
	scale := view_backing_scale(surface.view)
	// Two 8-point insets, an 18-point SF Symbol and 5 points of spacing.
	width := math.ceil((surface.readonly_title_width + 39) * scale) / scale
	x := math.max(0, view_width(surface.view) - readonly_margin - width)
	msg_void_rect(surface.readonly_badge, 'setFrame:', objc_rect(x, readonly_margin, width, readonly_height))
	if surface.readonly_scale == scale { return }
	pixel_width := int(math.round(width * scale))
	pixel_height := int(math.round(readonly_height * scale))
	mask := readonly_round_mask(pixel_width, pixel_height, scale, 0, 1) or { return }
	image := C.witty_canvas_make_alpha_image(mask.pixels.data, pixel_width, pixel_height, 0xffffff,
		nil_obj())
	if is_nil(image) { return }
	C.witty_readonly_set_mask(surface.readonly_material, image, width, readonly_height)
	C.CFRelease(image)
	surface.readonly_scale = scale
	msg_void_bool(surface.readonly_ink, 'setNeedsDisplay:', true)
}

// Coordinates of the three cubic segments in a unit-radius continuous corner.
const readonly_corner_y = [[0.0, 0.0, 0.0, 0.0749114]!,
	[0.0749114, 0.1690600, 0.3728240, 0.6314940]!,
	[0.6314940, 0.8684070, 1.0884900, 1.5286650]!]!
const readonly_corner_x = [[1.5286650, 1.0884900, 0.8684070, 0.6314940]!,
	[0.6314940, 0.3728240, 0.1690600, 0.0749114]!,
	[0.0749114, 0.0, 0.0, 0.0]!]!

fn readonly_cubic(a [4]f64, t f64) f64 {
	inv := 1 - t
	return a[0] * inv * inv * inv + 3 * a[1] * inv * inv * t
		+ 3 * a[2] * inv * t * t + a[3] * t * t * t
}

fn readonly_inset(y f64, height f64, radius f64, margin f64) f64 {
	edge := math.min(y, height - y) - margin
	if edge < 0 { return -1 }
	distance := edge / radius
	if distance >= readonly_corner_y[2][3] { return margin }
	segment := if distance < readonly_corner_y[0][3] {
		0
	} else if distance < readonly_corner_y[1][3] {
		1
	} else {
		2
	}
	curve := readonly_corner_y[segment]
	mut low, mut high := 0.0, 1.0
	for _ in 0 .. 14 {
		t := (low + high) / 2
		if readonly_cubic(curve, t) < distance {
			low = t
		} else {
			high = t
		}
	}
	return margin + radius * readonly_cubic(readonly_corner_x[segment], (low + high) / 2)
}

fn readonly_span(x int, left f64) f64 {
	if left < 0 { return 0 }
	return math.min(1.0, math.max(0.0, x + 1 - left))
}

fn readonly_round_mask(width int, height int, scale f64, line_width f64, opacity f64) !canvas.RasterSurface {
	mut raster := canvas.new_raster_surface(width: width, height: height)!
	radius := readonly_corner * scale
	stroke := line_width * scale
	for row in 0 .. height {
		mut outer := [16]f64{}
		mut inner := [16]f64{}
		for i in 0 .. outer.len {
			y := row + (i + 0.5) / outer.len
			outer[i] = readonly_inset(y, height, radius, 0)
			inner[i] = if stroke > 0 {
				readonly_inset(y, height, radius - stroke, stroke)
			} else {
				-1.0
			}
		}
		for column in 0 .. (width + 1) / 2 {
			mut coverage := 0.0
			for i, edge in outer {
				coverage += readonly_span(column, edge) - readonly_span(column, inner[i])
			}
			pixel := u32(math.round(255 * opacity * coverage / outer.len)) << 24
			raster.pixels[row * width + column] = pixel
			raster.pixels[row * width + width - 1 - column] = pixel
		}
	}
	return raster
}

fn readonly_draw(self ObjId, _cmd Sel, _rect ObjCRect) {
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	bounds := msg_rect(self, 'bounds')
	scale := view_backing_scale(voidptr(self))
	w := int(math.round(bounds.width * scale))
	h := int(math.round(bounds.height * scale))
	border := readonly_round_mask(w, h, scale, readonly_border_width, 0.6) or { return }
	color := C.witty_canvas_resolve_srgb(self, msg_id(get_class('NSColor'), 'systemOrangeColor'))
	image := C.witty_canvas_make_alpha_image(border.pixels.data, w, h, color, self)
	if !is_nil(image) {
		C.witty_canvas_present_tile(context, image, &bounds, 1)
		C.CFRelease(image)
	}
	C.witty_readonly_draw_content(context, nsstring(readonly_title), bounds.height)
}
