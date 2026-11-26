module macos

import gg.canvas
import math
import strings

#insert "@VMODROOT/macos/action_hover_darwin.h"

fn C.witty_hover_line(text ObjId, limit f64, width &f64) voidptr
fn C.witty_hover_draw_line(target voidptr, line voidptr, view ObjId, bounds &ObjCRect, pixels &u32, width int, height int, padding f64, baseline f64)
fn C.witty_hover_rasterize_circular_corner(pixels &u32, width int, height int, radius f64, round_left bool) bool
fn C.witty_hover_corner_phase(view ObjId, round_left bool) int
fn C.witty_hover_draw_background(target voidptr, view ObjId, bounds &ObjCRect, pixels &u32, width int, height int)
fn C.witty_hover_set_background(view ObjId, bottom ObjId, top ObjId, edge ObjId, corner &ObjCRect, coverage &f32, width int, height int, scale f64)

const hover_padding = 5.0
const hover_height = 26.0
const hover_spacer = 8.0
const hover_radius = 9.0
// Unit-radius intercepts and slopes fitted to live corners at several radii.
// Each knot marks an equally spaced diagonal, measured as the difference between x and y.
const hover_corner_positions = [0.2929106, 0.2039366, 0.1295453, 0.0731686, 0.0359282, 0.0157617,
	0.0070775, 0.0027773, 0.0]!
const hover_corner_slopes = [-0.5, -0.4313139, -0.3448212, -0.2448693, -0.1468378, -0.0693243,
	-0.0276623, -0.0198053, -0.0004360]!

struct HoverCornerDiagonal {
	intercept f64
	distance_scale f64 = 1.0
}

fn (mut surface NativeActionSurface) initialize_hover_banner() {
	mut cls := get_class('WittyHoverBanner')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyHoverBanner'), 0)
		add_ptr_ivar(cls, 'state')
		add_method(cls, 'drawRect:', voidptr(action_hover_draw_background), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(cls)
	}
	mut ink_class := get_class('WittyHoverBannerText')
	if is_nil(ink_class) {
		ink_class = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyHoverBannerText'), 0)
		add_method(ink_class, 'drawRect:', voidptr(action_hover_draw_text), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(ink_class, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(ink_class)
	}
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 0, 0))
	surface.hover_label = view
	C.macos_objc_set_ptr_ivar(view, cstr('state'), voidptr(surface))
	msg_void_bool(view, 'setHidden:', true)
	msg_void_bool(view, 'setWantsLayer:', true)
	msg_void_bool(view, 'setAccessibilityElement:', true)
	msg_void1(view, 'setAccessibilityRole:', nsstring('AXStaticText'))
	msg_void1(surface.overlay, 'addSubview:', view)
	msg_void(view, 'release')

	for i in 0 .. surface.hover_fill.len {
		surface.hover_fill[i] = msg_id(get_class('CALayer'), 'layer')
		msg_void1(msg_id(view, 'layer'), 'addSublayer:', surface.hover_fill[i])
	}
	mut corner_class := get_class('WittyHoverCornerLayer')
	if is_nil(corner_class) {
		corner_class = C.macos_objc_allocate_class_pair(get_class('CALayer'),
			cstr('WittyHoverCornerLayer'), 0)
		add_method(corner_class, 'renderInContext:', voidptr(action_hover_render_corner_in_context),
			'v@:^v')
		C.macos_objc_register_class_pair(corner_class)
	}
	surface.hover_corner_layer = msg_id(corner_class, 'layer')
	msg_void1(msg_id(view, 'layer'), 'addSublayer:', surface.hover_corner_layer)

	// Drawing the glyph image in the background's layer dithers the solid fill.
	ink := msg_id_rect(msg_id(ink_class, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 0, 0))
	surface.hover_ink = ink
	msg_void_bool(ink, 'setWantsLayer:', true)
	msg_void_bool(ink, 'setAccessibilityElement:', false)
	msg_void_u64(ink, 'setAutoresizingMask:', 18)
	msg_void1(view, 'addSubview:', ink)
	msg_void(ink, 'release')
}

fn action_hover_render_corner_in_context(_self ObjId, _cmd Sel, _context voidptr) {
	// The view draws the circular corner when AppKit captures a bitmap.
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
	rebuild_line := limit != surface.hover_text_limit
	if rebuild_line {
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
	old_width := view_width(surface.hover_ink)
	msg_void_rect(surface.hover_label, 'setFrame:', objc_rect(x, y, width, hover_height))
	msg_void_bool(surface.hover_label, 'setHidden:', false)
	surface.refresh_hover_background()
	msg_void_bool(surface.hover_label, 'setNeedsDisplay:', true)
	// Moving an existing preview can reuse its glyph layer.
	if rebuild_line {
		if width == old_width {
			// A same-size redraw can reuse a raster backing and change glyph color rounding.
			msg_void1(msg_id(surface.hover_ink, 'layer'), 'setContents:', nil_obj())
		}
		msg_void_bool(surface.hover_ink, 'setNeedsDisplay:', true)
	}

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
		surface.refresh_hover_background()
		msg_void_bool(surface.hover_label, 'setNeedsDisplay:', true)
		msg_void_bool(surface.hover_ink, 'setNeedsDisplay:', true)
	}
}

fn hover_corner_diagonal(diagonal int, radius f64) HoverCornerDiagonal {
	step := canvas_corner_x[0][0] / (hover_corner_positions.len - 1)
	interval := diagonal / (radius * step)
	i := int(interval)
	if i >= hover_corner_positions.len - 1 { return HoverCornerDiagonal{} }
	t := interval - i
	s := 1 - t
	// Interpolate the intercept and its derivative in the diagonal coordinate.
	position := s * s * ((1 + 2 * t) * hover_corner_positions[i] + t * step * hover_corner_slopes[i])
		+ t * t * ((1 + 2 * s) * hover_corner_positions[i + 1] - s * step * hover_corner_slopes[i + 1])
	slope := 6 * t * s * (hover_corner_positions[i + 1] - hover_corner_positions[i]) / step
		+ s * (1 - 3 * t) * hover_corner_slopes[i] + t * (1 - 3 * s) * hover_corner_slopes[i + 1]
	// The rasterizer's coverage ramp lies between diagonal and normal distance.
	return HoverCornerDiagonal{
		intercept: radius * position
		distance_scale: 1 + 0.52 * (1 / math.hypot(1 + slope, slope) - 1)
	}
}

fn hover_corner_distance(x int, y int, diagonals []HoverCornerDiagonal) f64 {
	diagonal := diagonals[math.abs(x - y)]
	return (math.min(x, y) + 0.5 - diagonal.intercept) * diagonal.distance_scale
}

fn hover_canvas_mask(width int, height int, scale f64, round_left bool) !canvas.RasterSurface {
	mut raster := canvas.new_raster_surface(width: width, height: height)!
	radius := math.min(hover_radius * scale, math.min(width, height))
	if !C.witty_hover_rasterize_circular_corner(raster.pixels.data, width, height, radius,
		round_left) {
		return error('Could not rasterize the hover banner corner')
	}
	return raster
}

fn hover_corner_coverage(width int, height int, scale f64, round_left bool, phase int) []f32 {
	mut coverage := []f32{len: width * height, init: 1.0}
	extent := canvas_corner_x[0][0]
	radius := math.min(hover_radius * scale, math.min(width, height) / extent)
	corner := math.min(math.min(width, height), int(math.ceil(radius * extent)))
	mut diagonals := []HoverCornerDiagonal{len: corner + 1}
	for i in 0 .. diagonals.len {
		diagonals[i] = hover_corner_diagonal(i, radius)
	}
	phase_x := phase & 1
	phase_y := (phase >> 1) & 1
	// Core Animation derives the coverage ramp from 2×2 groups of backing pixels.
	for row in 0 .. corner {
		dy := 1 - 2 * ((row + phase_y) & 1)
		for column in 0 .. corner {
			dx := 1 - 2 * ((column + phase_x) & 1)
			distance := hover_corner_distance(column, row, diagonals)
			horizontal := dx * (hover_corner_distance(column + dx, row, diagonals) - distance)
			vertical := dy * (hover_corner_distance(column, row + dy, diagonals) - distance)
			x := if round_left { column } else { width - column - 1 }
			coverage[row * width + x] = f32(math.clamp(0.5 + distance / (horizontal + vertical), 0.0, 1.0))
		}
	}
	return coverage
}

fn (surface &NativeActionSurface) refresh_hover_background() {
	bounds := msg_rect(surface.hover_label, 'bounds')
	scale := view_backing_scale(surface.view)
	corner := surface.hover_corner(bounds, scale)
	width := int(math.round(corner.width * scale))
	height := int(math.round(corner.height * scale))
	if width <= 0 || height <= 0 { return }
	phase := C.witty_hover_corner_phase(surface.hover_label, surface.hover_left)
	coverage := hover_corner_coverage(width, height, scale, surface.hover_left, phase)
	C.witty_hover_set_background(surface.hover_label, surface.hover_fill[0], surface.hover_fill[1],
		surface.hover_corner_layer, &corner, coverage.data, width, height, scale)
}

fn (surface &NativeActionSurface) hover_corner(bounds ObjCRect, scale f64) ObjCRect {
	size := math.ceil(hover_radius * canvas_corner_x[0][0] * scale) / scale
	width := math.min(size, bounds.width)
	height := math.min(size, bounds.height)
	x := if surface.hover_left { bounds.x } else { bounds.x + bounds.width - width }
	return objc_rect(x, bounds.y + bounds.height - height, width, height)
}

fn action_hover_draw_background(self ObjId, _cmd Sel, _rect ObjCRect) {
	surface := action_owner_state(self) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) || C.CGBitmapContextGetBitsPerComponent(context) == 0 { return }
	bounds := msg_rect(self, 'bounds')
	scale := view_backing_scale(surface.view)
	width := int(math.round(bounds.width * scale))
	height := int(math.round(bounds.height * scale))
	raster := hover_canvas_mask(width, height, scale, surface.hover_left) or { return }
	C.witty_hover_draw_background(context, self, &bounds, raster.pixels.data, width, height)
}

fn action_hover_draw_text(self ObjId, _cmd Sel, _rect ObjCRect) {
	surface := action_owner_state(msg_id(self, 'superview')) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) || surface.hover_line == unsafe { nil } { return }
	bounds := msg_rect(self, 'bounds')
	if bounds.width <= 2 * hover_padding { return }
	scale := view_backing_scale(surface.view)
	width := int(math.round(bounds.width * scale))
	height := int(math.round(bounds.height * scale))
	raster := canvas.new_raster_surface(width: width, height: height) or { return }
	C.witty_hover_draw_line(context, surface.hover_line, self, &bounds, raster.pixels.data,
		width, height, hover_padding, 8)
}
