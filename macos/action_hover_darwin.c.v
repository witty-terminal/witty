module macos

import gg.canvas
import math
import strings

#insert "@VMODROOT/macos/action_hover_darwin.h"

fn C.witty_hover_line(text ObjId, limit f64, width &f64) voidptr
fn C.witty_hover_rasterize_line(line voidptr, view ObjId, pixels &u32, width int, height int, padding f64, baseline f64) voidptr

const hover_padding = 5.0
const hover_height = 26.0
const hover_spacer = 8.0
const hover_radius = 9.0

fn new_hover_banner(surface &NativeActionSurface) ObjId {
	mut cls := get_class('WittyHoverBanner')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyHoverBanner'), 0)
		add_ptr_ivar(cls, 'state')
		add_method(cls, 'drawRect:', voidptr(action_hover_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(cls)
	}
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 0, 0))
	C.macos_objc_set_ptr_ivar(view, cstr('state'), voidptr(surface))
	msg_void_bool(view, 'setHidden:', true)
	msg_void_bool(view, 'setWantsLayer:', true)
	msg_void_bool(view, 'setAccessibilityElement:', true)
	msg_void1(view, 'setAccessibilityRole:', nsstring('AXStaticText'))
	return view
}

fn action_hover_entered(self ObjId, _cmd Sel, _event ObjId) {
	if mut surface := action_owner_state(self) {
		surface.hover_left = true
		surface.refresh_hover_visuals()
	}
}

fn action_hover_exited(self ObjId, _cmd Sel, _event ObjId) {
	if mut surface := action_owner_state(self) {
		surface.hover_left = false
		surface.refresh_hover_visuals()
	}
}

fn hover_display_url(raw string) string {
	url_class := get_class('NSURL')
	mut url := msg_id1(url_class, 'URLWithString:', nsstring(raw))
	if is_nil(msg_id(url, 'scheme')) {
		url = msg_id1(url_class, 'fileURLWithPath:', nsstring(raw))
	}
	mut display := raw
	if msg_bool(url, 'isFileURL') {
		standard := msg_id(url, 'URLByStandardizingPath')
		display = objc_utf8_string(msg_id(msg_id(standard, 'URLByResolvingSymlinksInPath'), 'path'))
	}
	// Ghostty's display string makes line breaks and invisible formatting visible.
	mut escaped := strings.new_builder(display.len)
	for scalar in display.runes() {
		if scalar <= 0x1f || scalar in [rune(0x061c), 0x2060, 0xfeff]
			|| (scalar >= 0x7f && scalar <= 0x9f) || (scalar >= 0x200b && scalar <= 0x200f)
			|| (scalar >= 0x2028 && scalar <= 0x202e) || (scalar >= 0x2066 && scalar <= 0x2069) {
			escaped.write_string('\\u{${u32(scalar):X}}')
		} else {
			escaped.write_rune(scalar)
		}
	}
	return escaped.str()
}

fn (mut surface NativeActionSurface) clear_hover_line() {
	if surface.hover_line != unsafe { nil } {
		C.CFRelease(surface.hover_line)
		surface.hover_line = unsafe { nil }
	}
	surface.hover_text_limit = -1
}

fn (mut surface NativeActionSurface) clear_hover_tracking() {
	if !is_nil(surface.hover_tracking) {
		msg_void1(surface.overlay, 'removeTrackingArea:', surface.hover_tracking)
		msg_void(surface.hover_tracking, 'release')
		surface.hover_tracking = nil_obj()
	}
}

fn (mut surface NativeActionSurface) refresh_hover_visuals() {
	if is_nil(surface.hover_label) {
		return
	}
	available := view_width(surface.view)
	if surface.hover_url.len == 0 || available <= 0 {
		msg_void_bool(surface.hover_label, 'setHidden:', true)
		surface.clear_hover_tracking()
		return
	}

	limit := math.max(0, available - 2 * hover_padding - hover_spacer)
	if limit != surface.hover_text_limit {
		surface.clear_hover_line()
		mut text_width := 0.0
		surface.hover_line = C.witty_hover_line(nsstring(surface.hover_display), limit, &text_width)
		surface.hover_text_limit = limit
		surface.hover_text_width = text_width
	}
	scale := view_backing_scale(surface.view)
	width := math.min(available, math.ceil((surface.hover_text_width + 2 * hover_padding) * scale) / scale)
	y := view_height(surface.view) - hover_height
	x := if surface.hover_left { available - width } else { 0.0 }
	msg_void_rect(surface.hover_label, 'setFrame:', objc_rect(x, y, width, hover_height))
	msg_void_bool(surface.hover_label, 'setHidden:', false)
	msg_void_bool(surface.hover_label, 'setNeedsDisplay:', true)

	tracking := objc_rect(0, y, width, hover_height)
	if !is_nil(surface.hover_tracking) && surface.hover_tracking_rect == tracking {
		return
	}
	surface.clear_hover_tracking()
	surface.hover_tracking_rect = tracking
	// The left interaction area stays fixed when the banner moves to the right.
	surface.hover_tracking = msg_id_rect_u64_obj_obj(alloc('NSTrackingArea'),
		'initWithRect:options:owner:userInfo:', tracking, 1 | 128, surface.owner, nil_obj())
	msg_void1(surface.overlay, 'addTrackingArea:', surface.hover_tracking)
}

fn (mut surface NativeActionSurface) refresh_hover_appearance() {
	if !is_nil(surface.hover_label) && surface.hover_url.len > 0 {
		msg_void_bool(surface.hover_label, 'setNeedsDisplay:', true)
	}
}

fn hover_canvas_mask(width int, height int, scale f64, round_left bool) !canvas.RasterSurface {
	mut raster := canvas.new_raster_surface(width: width, height: height)!
	raster.clear(0xff000000)
	radius := math.min(hover_radius * scale, math.min(width, height))
	corner := int(math.ceil(radius))
	// Integrate the covered width across each pixel row of the rounded corner.
	for row in 0 .. corner {
		mut insets := [16]f64{}
		for i in 0 .. insets.len {
			dy := math.max(0, radius - row - (i + 0.5) / insets.len)
			insets[i] = radius - math.sqrt(radius * radius - dy * dy)
		}
		for column in 0 .. corner {
			mut coverage := 0.0
			for inset in insets {
				coverage += math.min(1, math.max(0, column + 1 - inset))
			}
			x := if round_left { column } else { width - column - 1 }
			raster.pixels[row * width + x] = u32(math.round(255 * coverage / insets.len)) << 24
		}
	}
	return raster
}

fn action_hover_draw(self ObjId, _cmd Sel, _rect ObjCRect) {
	surface := action_owner_state(self) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	bounds := msg_rect(self, 'bounds')
	scale := view_backing_scale(surface.view)
	width := int(math.round(bounds.width * scale))
	height := int(math.round(bounds.height * scale))
	mut raster := hover_canvas_mask(width, height, scale, surface.hover_left) or { return }
	color := C.witty_canvas_resolve_srgb(self, msg_id(get_class('NSColor'), 'windowBackgroundColor'))
	image := C.witty_canvas_make_alpha_image(raster.pixels.data, width, height, color, self)
	if !is_nil(image) {
		C.witty_canvas_present_tile(context, image, &bounds, 1)
		C.CFRelease(image)
	}
	if surface.hover_line != unsafe { nil } && bounds.width > 2 * hover_padding {
		raster.clear(0)
		label := C.witty_hover_rasterize_line(surface.hover_line, self, raster.pixels.data, width,
			height, hover_padding, 8)
		if !is_nil(label) {
			C.witty_canvas_present_tile(context, label, &bounds, 1)
			C.CFRelease(label)
		}
	}
}
