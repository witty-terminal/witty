module macos

import gg.canvas
import math
import strings

#insert "@VMODROOT/macos/action_hover_darwin.h"

fn C.witty_hover_line(text ObjId, limit f64, width &f64) voidptr
fn C.witty_hover_release_line(line voidptr)
fn C.witty_hover_draw_line(target voidptr, line voidptr, view ObjId, bounds &ObjCRect, pixels &u32, width int, height int, padding f64, baseline f64)
fn C.witty_hover_rasterize_circular_corner(pixels &u32, width int, height int, radius f64, round_left bool) bool
fn C.witty_hover_backing_phases(view ObjId) int
fn C.witty_hover_draw_background(target voidptr, view ObjId, bounds &ObjCRect, pixels &u32, width int, height int)
fn C.witty_hover_set_background(view ObjId, layer ObjId, center &ObjCRect, coverage &f32, width int, height int, scale f64)

const hover_padding = 5.0
const hover_height = 26.0
const hover_spacer = 8.0
const hover_radius = 9.0
// SwiftUI corner coverage measured by the macos_hover_corner_masks reference probe.
const hover_corner_masks_1x = $embed_file('@VMODROOT/build_assets/macos/hover_corner_masks_1x.bin').to_bytes()
const hover_corner_masks_2x = $embed_file('@VMODROOT/build_assets/macos/hover_corner_masks_2x.bin').to_bytes()
// Unit-radius intercepts and slopes fitted to live corners at several radii.
// Each knot marks an equally spaced diagonal, measured as the difference between x and y.
const hover_corner_positions = [0.2929106, 0.2039366, 0.1295453, 0.0731686, 0.0359282, 0.0157617,
	0.0070775, 0.0027773, 0.0]!
const hover_corner_slopes = [-0.5, -0.4313139, -0.3448212, -0.2448693, -0.1468378, -0.0693243,
	-0.0276623, -0.0198053, -0.0004360]!
// Narrow shapes compress the horizontal end of the curve. These unit-radius
// samples describe the change in edge distance per missing backing pixel.
const hover_corner_width_start = 0.19
const hover_corner_width_end = 1.55
const hover_corner_width_positions = [0.0, 0.0044276, 0.0179309, 0.0302028, 0.0158039, 0.0059443, 0.0]!
const hover_corner_width_slopes = [0.0, 0.0387408, 0.0717346, 0.0260299, -0.0576664, -0.0292069, 0.0]!
const hover_corner_width_phases = [0.0, 0.0010794, -0.0002302, 0.0137018, -0.0068266, 0.0018925, 0.0]!
const hover_corner_width_phase_slopes = [0.0, 0.0224255, 0.0000827, 0.1182098, 0.1877699, 0.0644234, 0.0]!

struct HoverCornerDiagonal {
	intercept f64
	distance_scale f64 = 1.0
	width_adjustment f64
	width_phase_adjustment f64
}

struct HoverBackgroundMask {
	coverage []f32
	width    int
	height   int
	center   ObjCRect
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

	mut background_class := get_class('WittyHoverBackgroundLayer')
	if is_nil(background_class) {
		background_class = C.macos_objc_allocate_class_pair(get_class('CALayer'),
			cstr('WittyHoverBackgroundLayer'), 0)
		add_method(background_class, 'renderInContext:', voidptr(action_hover_render_background_in_context),
			'v@:^v')
		C.macos_objc_register_class_pair(background_class)
	}
	surface.hover_background_layer = msg_id(background_class, 'layer')
	msg_void1(msg_id(view, 'layer'), 'addSublayer:', surface.hover_background_layer)

	// Drawing the glyph image in the background's layer dithers the solid fill.
	ink := msg_id_rect(msg_id(ink_class, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 0, 0))
	surface.hover_ink = ink
	msg_void_bool(ink, 'setWantsLayer:', true)
	msg_void_bool(ink, 'setAccessibilityElement:', false)
	msg_void_u64(ink, 'setAutoresizingMask:', 18)
	msg_void1(view, 'addSubview:', ink)
	msg_void(ink, 'release')
}

fn action_hover_render_background_in_context(_self ObjId, _cmd Sel, _context voidptr) {
	// The view draws the background when AppKit captures a bitmap.
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
		C.witty_hover_release_line(surface.hover_line)
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

fn hover_banner_width(available f64, text_width f64, scale f64) f64 {
	padding := 2 * hover_padding
	// The banner padding and the spacer split the shortage in a narrow pane.
	width := if available < padding + hover_spacer {
		(available + padding - hover_spacer) / 2
	} else {
		text_width + padding
	}
	return math.min(available, math.ceil(width * scale) / scale)
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
	width := hover_banner_width(available, surface.hover_text_width, scale)
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
	if !surface.closed && !is_nil(surface.hover_label) && surface.hover_url.len > 0 {
		surface.refresh_hover_background()
		msg_void_bool(surface.hover_label, 'setNeedsDisplay:', true)
		msg_void1(msg_id(surface.hover_ink, 'layer'), 'setContents:', nil_obj())
		msg_void_bool(surface.hover_ink, 'setNeedsDisplay:', true)
	}
}

fn hover_corner_interpolate(left f64, right f64, left_slope f64, right_slope f64, t f64, step f64) f64 {
	s := 1 - t
	return s * s * ((1 + 2 * t) * left + t * step * left_slope)
		+ t * t * ((1 + 2 * s) * right - s * step * right_slope)
}

fn hover_corner_width_adjustment(diagonal f64) (f64, f64) {
	if diagonal <= hover_corner_width_start || diagonal >= hover_corner_width_end { return 0, 0 }
	step := (hover_corner_width_end - hover_corner_width_start) / (hover_corner_width_positions.len - 1)
	interval := (diagonal - hover_corner_width_start) / step
	i := int(interval)
	if i >= hover_corner_width_positions.len - 1 { return 0, 0 }
	t := interval - i
	return hover_corner_interpolate(hover_corner_width_positions[i], hover_corner_width_positions[i + 1],
		hover_corner_width_slopes[i], hover_corner_width_slopes[i + 1], t, step),
		hover_corner_interpolate(hover_corner_width_phases[i], hover_corner_width_phases[i + 1],
			hover_corner_width_phase_slopes[i], hover_corner_width_phase_slopes[i + 1], t, step)
}

fn hover_corner_diagonal(diagonal int, radius f64, missing_width f64) HoverCornerDiagonal {
	step := canvas_corner_x[0][0] / (hover_corner_positions.len - 1)
	interval := diagonal / (radius * step)
	i := int(interval)
	if i >= hover_corner_positions.len - 1 { return HoverCornerDiagonal{} }
	t := interval - i
	s := 1 - t
	// Interpolate the intercept and its derivative in the diagonal coordinate.
	position := hover_corner_interpolate(hover_corner_positions[i], hover_corner_positions[i + 1],
		hover_corner_slopes[i], hover_corner_slopes[i + 1], t, step)
	slope := 6 * t * s * (hover_corner_positions[i + 1] - hover_corner_positions[i]) / step
		+ s * (1 - 3 * t) * hover_corner_slopes[i] + t * (1 - 3 * s) * hover_corner_slopes[i + 1]
	base_adjustment, phase_adjustment := hover_corner_width_adjustment(diagonal / radius)
	// The rasterizer's coverage ramp lies between diagonal and normal distance.
	return HoverCornerDiagonal{
		intercept: radius * position
		distance_scale: 1 + 0.52 * (1 / math.hypot(1 + slope, slope) - 1)
		width_adjustment: missing_width * base_adjustment
		width_phase_adjustment: missing_width * phase_adjustment / radius
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

fn hover_mask_word(data []u8, offset int) int {
	return int(data[offset]) | (int(data[offset + 1]) << 8)
}

fn hover_apply_corner_mask(mut coverage []f32, tile_width int, banner_width int, rows int, scale int, round_left bool, phase int) {
	data := if scale == 1 { hover_corner_masks_1x } else { hover_corner_masks_2x }
	min_width := int(2 * hover_padding) * scale
	max_width := if scale == 1 { 15 } else { 34 }
	mask_width := math.min(math.max(banner_width, min_width), max_width)
	// The 2× atlas stores trailing corners, then their independently sampled leading corners.
	direction_offset := if scale == 2 && round_left { max_width - min_width + 1 } else { 0 }
	index := (direction_offset + mask_width - min_width) * 4 + phase
	mut offset := hover_mask_word(data, index * 2)
	// Each row stores a transparent prefix and a run of 16-bit coverage values.
	// The rest of the row is already opaque.
	for row in 0 .. rows {
		first := int(data[offset])
		count := int(data[offset + 1])
		offset += 2
		for column in 0 .. math.min(tile_width, first + count) {
			x := if round_left { column } else { tile_width - column - 1 }
			coverage[row * tile_width + x] = if column < first {
				f32(0)
			} else {
				f32(hover_mask_word(data, offset + 2 * (column - first))) / 65535
			}
		}
		offset += 2 * count
	}
}

fn hover_corner_coverage(width int, height int, scale f64, round_left bool, phase int) []f32 {
	extent := canvas_corner_x[0][0]
	radius := hover_radius * scale
	corner := int(math.ceil(radius * extent))
	tile_width := math.min(width, corner + 2)
	mut coverage := []f32{len: tile_width * height, init: 1.0}
	rows := math.min(height, corner)
	if scale == 1 || scale == 2 {
		hover_apply_corner_mask(mut coverage, tile_width, width, rows, int(scale), round_left, phase)
		return coverage
	}
	// The banner clips below the horizontal padding width. Include the
	// subpixel ramp when finding where the curve merges with the top edge.
	shape_width := math.max(f64(width), 2 * hover_padding * scale)
	missing_width := math.max(0.0, radius * extent + 0.75 - shape_width)
	columns := math.min(tile_width, corner)
	mut diagonals := []HoverCornerDiagonal{len: math.max(columns, rows) + 1}
	for i in 0 .. diagonals.len {
		diagonals[i] = hover_corner_diagonal(i, radius, missing_width)
	}
	phase_x := phase & 1
	phase_y := (phase >> 1) & 1
	// Core Animation derives the coverage ramp from 2×2 groups of backing pixels.
	for row in 0 .. rows {
		dy := 1 - 2 * ((row + phase_y) & 1)
		for column in 0 .. columns {
			dx := 1 - 2 * ((column + phase_x) & 1)
			distance := hover_corner_distance(column, row, diagonals)
			horizontal := dx * (hover_corner_distance(column + dx, row, diagonals) - distance)
			vertical := dy * (hover_corner_distance(column, row + dy, diagonals) - distance)
			x := if round_left { column } else { tile_width - column - 1 }
			mut adjusted := distance
			if column > row && missing_width > 0 {
				diagonal := diagonals[column - row]
				adjusted += diagonal.width_adjustment + dx * diagonal.width_phase_adjustment
			}
			coverage[row * tile_width + x] = f32(math.clamp(0.5 + adjusted / (horizontal + vertical), 0.0, 1.0))
		}
	}
	return coverage
}

fn hover_square_corner_coverage(crossed_edges int) f32 {
	if crossed_edges == 0 { return 1.0 }
	// A backing pixel shared by one or two shape edges has a wider coverage ramp.
	return f32(0.5 + (0.5 - 0.0065) / crossed_edges)
}

fn hover_background_mask(width int, height int, scale f64, round_left bool, phases int) HoverBackgroundMask {
	corner := int(math.ceil(hover_radius * canvas_corner_x[0][0] * scale))
	// Keep the rounded corner and the opposite edge, with one opaque pixel between them.
	// Core Animation stretches the center row and column to the banner's size.
	tile_width := math.min(width, corner + 2)
	tile_height := math.min(height, corner + 2)
	left := phases & 1
	right := (phases >> 1) & 1
	top := (phases >> 2) & 1
	bottom := (phases >> 3) & 1
	rounded_x := if round_left { left } else { right }
	mut coverage := hover_corner_coverage(width, tile_height, scale, round_left,
		rounded_x | (top << 1))
	square_top := if round_left { tile_width - 1 } else { 0 }
	square_top_x := if round_left { right } else { left }
	bottom_left := (tile_height - 1) * tile_width
	bottom_right := tile_height * tile_width - 1
	coverage[square_top] = math.min(coverage[square_top], hover_square_corner_coverage(square_top_x + top))
	coverage[bottom_left] = math.min(coverage[bottom_left], hover_square_corner_coverage(left + bottom))
	coverage[bottom_right] = math.min(coverage[bottom_right], hover_square_corner_coverage(right + bottom))

	stretch_x := width > tile_width
	stretch_y := height > tile_height
	left_cap := if stretch_x { if round_left { corner } else { 1 } } else { 0 }
	bottom_cap := if stretch_y { 1 } else { 0 }
	center_width := if stretch_x { 1 } else { tile_width }
	center_height := if stretch_y { 1 } else { tile_height }
	return HoverBackgroundMask{
		coverage: coverage
		width: tile_width
		height: tile_height
		center: objc_rect(f64(left_cap) / tile_width, f64(bottom_cap) / tile_height,
			f64(center_width) / tile_width, f64(center_height) / tile_height)
	}
}

fn (surface &NativeActionSurface) refresh_hover_background() {
	bounds := msg_rect(surface.hover_label, 'bounds')
	scale := view_backing_scale(surface.view)
	width := int(math.round(bounds.width * scale))
	height := int(math.round(bounds.height * scale))
	if width <= 0 || height <= 0 { return }
	phases := C.witty_hover_backing_phases(surface.hover_label)
	mask := hover_background_mask(width, height, scale, surface.hover_left, phases)
	C.witty_hover_set_background(surface.hover_label, surface.hover_background_layer, &mask.center,
		mask.coverage.data, mask.width, mask.height, scale)
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
