module sprite

// Tests for the pure-logic primitives in sprite.v, translated
// faithfully from the semantics documented in ghostty's
//   src/font/sprite/draw/common.zig   (Fraction, Thickness, fill, Quads, ...)
//   src/font/sprite/canvas.zig        (Canvas.pixel/rect/box/invert/flip)
//
// These tests exercise the documented behavior of the translated logic. The
// exact-pixel translation of Ghostty's golden-atlas test lives in face_test.v.

import sprite_types as font

// ------------------------------------------------------------
// Fraction.fraction -- exact float values per common.zig
// ------------------------------------------------------------

fn test_fraction_val_min_edge() {
	// start/left/top/zero all map to 0.0
	assert Fraction.start.fraction() == 0.0
	assert Fraction.left.fraction() == 0.0
	assert Fraction.top.fraction() == 0.0
	assert Fraction.zero.fraction() == 0.0
}

fn test_fraction_val_eighths() {
	assert Fraction.one_eighth.fraction() == 0.125
	assert Fraction.eighth.fraction() == 0.125
	assert Fraction.two_eighths.fraction() == 0.25
	assert Fraction.three_eighths.fraction() == 0.375
	assert Fraction.four_eighths.fraction() == 0.5
	assert Fraction.five_eighths.fraction() == 0.625
	assert Fraction.six_eighths.fraction() == 0.75
	assert Fraction.seven_eighths.fraction() == 0.875
}

fn test_fraction_val_quarters() {
	assert Fraction.one_quarter.fraction() == 0.25
	assert Fraction.quarter.fraction() == 0.25
	assert Fraction.two_quarters.fraction() == 0.5
	assert Fraction.three_quarters.fraction() == 0.75
}

fn test_fraction_val_thirds() {
	assert Fraction.one_third.fraction() == 1.0 / 3.0
	assert Fraction.third.fraction() == 1.0 / 3.0
	assert Fraction.two_thirds.fraction() == 2.0 / 3.0
}

fn test_fraction_val_halves_and_center() {
	assert Fraction.half_.fraction() == 0.5
	assert Fraction.one_half.fraction() == 0.5
	assert Fraction.center.fraction() == 0.5
	assert Fraction.middle.fraction() == 0.5
}

fn test_fraction_val_max_edge() {
	assert Fraction.end_.fraction() == 1.0
	assert Fraction.right.fraction() == 1.0
	assert Fraction.bottom.fraction() == 1.0
	assert Fraction.one.fraction() == 1.0
	assert Fraction.full.fraction() == 1.0
}

// ------------------------------------------------------------
// Fraction.min / max -- worked example from common.zig
//
// "if size is 7, and we're looking at the half line,
//  size - round((1 - 0.5) * size) => 3; whereas the max
//  coordinate directly rounds ... both start -> half and
//  half -> end will be 4px, from 0 -> 4 and 3 -> 7."
// ------------------------------------------------------------

fn test_fraction_min_max_odd_size_half() {
	assert Fraction.half_.min(7) == 3
	assert Fraction.half_.max(7) == 4
	// start -> half spans 0..4 (4px), half -> end spans 3..7 (4px)
	assert Fraction.start.min(7) == 0
	assert Fraction.end_.max(7) == 7
}

fn test_fraction_min_max_edges() {
	// The min edge fractions produce 0 as a min coord for any size.
	assert Fraction.zero.min(10) == 0
	assert Fraction.zero.min(8) == 0
	// The max edge fractions produce `size` as a max coord.
	assert Fraction.one.max(10) == 10
	assert Fraction.full.max(8) == 8
}

fn test_fraction_min_max_even_size() {
	// size 8, half -> min = 8 - round(0.5*8) = 8 - 4 = 4; max = round(4) = 4
	assert Fraction.half_.min(8) == 4
	assert Fraction.half_.max(8) == 4
	// quarter of 8: min = 8 - round(0.75*8) = 8 - 6 = 2; max = round(0.25*8) = 2
	assert Fraction.one_quarter.min(8) == 2
	assert Fraction.one_quarter.max(8) == 2
}

fn test_fraction_float() {
	assert Fraction.half_.float(10) == 5.0
	assert Fraction.one_quarter.float(8) == 2.0
	assert Fraction.one.float(16) == 16.0
	assert Fraction.zero.float(16) == 0.0
}

fn test_fraction_eighths_index_table() {
	// The eighths table indexes i/8 -> the corresponding Fraction,
	// each fraction() == i/8.
	for i in 0 .. 9 {
		f := fraction_eighths[i]
		assert f.fraction() == f64(i) / 8.0
	}
}

fn test_fraction_quarters_index_table() {
	for i in 0 .. 5 {
		f := fraction_quarters[i]
		assert f.fraction() == f64(i) / 4.0
	}
}

fn test_fraction_thirds_index_table() {
	for i in 0 .. 4 {
		f := fraction_thirds[i]
		assert f.fraction() == f64(i) / 3.0
	}
}

fn test_fraction_halves_index_table() {
	for i in 0 .. 3 {
		f := fraction_halves[i]
		assert f.fraction() == f64(i) / 2.0
	}
}

// ------------------------------------------------------------
// Thickness.height -- @max(base/2, 1) / base / base*2
// ------------------------------------------------------------

fn test_thickness_height() {
	assert sizeof(Thickness) == 1
	assert Thickness.light.height(4) == 4
	assert Thickness.heavy.height(4) == 8
	assert Thickness.super_light.height(4) == 2
	// super_light floors base/2 but clamps to a minimum of 1.
	assert Thickness.super_light.height(2) == 1
	assert Thickness.super_light.height(1) == 1
	assert Thickness.super_light.height(3) == 1
	assert Thickness.super_light.height(6) == 3
}

// ------------------------------------------------------------
// Shade / Color enum values
// ------------------------------------------------------------

fn test_shade_values() {
	assert u8(Shade.off) == 0x00
	assert u8(Shade.light_) == 0x40
	assert u8(Shade.medium) == 0x80
	assert u8(Shade.dark) == 0xc0
	assert u8(Shade.on) == 0xff
}

fn test_color_values() {
	assert u8(Color.off) == 0x00
	assert u8(Color.on) == 0xff
}

fn test_corner_and_edge_source_layouts() {
	assert sizeof(Corner) == 1
	assert u8(Corner.tl) == 0
	assert u8(Corner.tr) == 1
	assert u8(Corner.bl) == 2
	assert u8(Corner.br) == 3
	assert sizeof(Edge) == 1
	assert u8(Edge.top) == 0
	assert u8(Edge.left) == 1
	assert u8(Edge.bottom) == 2
	assert u8(Edge.right) == 3
}

fn test_alignment_and_fraction_source_layouts() {
	assert sizeof(HorizontalAlignment) == 1
	assert sizeof(VerticalAlignment) == 1
	assert sizeof(Alignment) == 2
	assert u8(HorizontalAlignment.left) == 0
	assert u8(HorizontalAlignment.right) == 1
	assert u8(HorizontalAlignment.center) == 2
	assert u8(VerticalAlignment.top) == 0
	assert u8(VerticalAlignment.bottom) == 1
	assert u8(VerticalAlignment.middle) == 2
	assert sizeof(Fraction) == 1
	assert u8(Fraction.start) == 0
	assert Fraction.full != Fraction.one
}

fn test_z2d_path_and_cap_source_layouts() {
	assert sizeof(PathNodeTag) == 1
	assert u8(PathNodeTag.move_to) == 0
	assert u8(PathNodeTag.line_to) == 1
	assert u8(PathNodeTag.curve_to) == 2
	assert u8(PathNodeTag.close_path) == 3
	assert sizeof(LineCapMode) == 1
	assert u8(LineCapMode.butt) == 0
	assert u8(LineCapMode.round_) == 1
	assert u8(LineCapMode.square) == 2
}

// ------------------------------------------------------------
// Canvas.pixel / rect / box primitives
// ------------------------------------------------------------

// data_at reads a cell-relative pixel back from the canvas (accounting
// for padding), returning the raw alpha value.
fn data_at(c &Canvas, x int, y int) u8 {
	w := int(c.sfc_width())
	px := x + int(c.padding_x)
	py := y + int(c.padding_y)
	return u8(c.surface.pixels[py * w + px] >> 24)
}

fn test_canvas_dimensions() {
	c := Canvas.init(10, 20, 2, 3)
	assert c.width == 10
	assert c.height == 20
	assert c.padding_x == 2
	assert c.padding_y == 3
	assert c.sfc_width() == 10 + 2 * 2
	assert c.sfc_height() == 20 + 2 * 3
	// Buffer is fully allocated and zeroed.
	assert c.surface.pixels.len == int(c.sfc_width() * c.sfc_height())
	for v in c.surface.pixels {
		assert v == 0
	}
}

fn test_canvas_transformation_matches_padding_translation() {
	c := Canvas.init(10, 20, 2, 3)
	t := c.transformation()
	assert t.ax == 1
	assert t.by == 0
	assert t.cx == 0
	assert t.dy == 1
	assert t.tx == 2
	assert t.ty == 3
}

fn test_canvas_deinit_releases_owned_raster() {
	mut c := Canvas.init(10, 20, 2, 3)
	assert c.surface.pixels.len > 0
	c.deinit()
	assert c.surface.pixels.len == 0
	assert c.sfc_width() == 0
	assert c.sfc_height() == 0
}

fn test_canvas_pixel() {
	mut c := Canvas.init(4, 4, 0, 0)
	c.pixel(1, 2, .on)
	assert data_at(&c, 1, 2) == 255
	// Other pixels remain off.
	assert data_at(&c, 0, 0) == 0
	assert data_at(&c, 3, 3) == 0
}

fn test_canvas_pixel_out_of_bounds_ignored() {
	mut c := Canvas.init(4, 4, 0, 0)
	// z2d silently ignores out-of-bounds writes; so does our translation.
	c.pixel(-1, 0, .on)
	c.pixel(0, -1, .on)
	c.pixel(4, 0, .on)
	c.pixel(0, 4, .on)
	for v in c.surface.pixels {
		assert v == 0
	}
}

fn test_canvas_rect() {
	mut c := Canvas.init(6, 6, 0, 0)
	c.rect(SpriteRect{ x: 1, y: 1, width: 3, height: 2 }, .on)
	// Interior of the rect is on.
	for y in 1 .. 3 {
		for x in 1 .. 4 {
			assert data_at(&c, x, y) == 255
		}
	}
	// Just outside is off.
	assert data_at(&c, 0, 1) == 0
	assert data_at(&c, 4, 1) == 0
	assert data_at(&c, 1, 3) == 0
}

fn test_canvas_box_orders_corners() {
	mut c := Canvas.init(6, 6, 0, 0)
	// Pass the corners in reversed order; the box should normalize them.
	c.box(4, 3, 1, 1, .on)
	for y in 1 .. 3 {
		for x in 1 .. 4 {
			assert data_at(&c, x, y) == 255
		}
	}
	assert data_at(&c, 0, 1) == 0
	assert data_at(&c, 4, 1) == 0
}

fn test_canvas_rect_clips_to_the_padded_raster() {
	mut c := Canvas.init(4, 4, 1, 1)
	c.rect(SpriteRect{ x: -3, y: -2, width: 4, height: 3 }, .medium)
	assert data_at(&c, -1, -1) == 128
	assert data_at(&c, 0, 0) == 128
	assert data_at(&c, 1, 0) == 0
	assert data_at(&c, 0, 1) == 0
}

fn test_canvas_pixel_padding_offset() {
	// With padding, cell-relative (0,0) maps to surface (padding_x, padding_y).
	mut c := Canvas.init(4, 4, 2, 3)
	c.pixel(0, 0, .on)
	w := int(c.sfc_width())
	// Direct surface index at (padding_x, padding_y).
	assert c.surface.pixels[3 * w + 2] == u32(255) << 24
	// Surface origin (0,0) untouched.
	assert c.surface.pixels[0] == 0
}

// ------------------------------------------------------------
// Canvas.invert / flip_horizontal / flip_vertical
// ------------------------------------------------------------

fn test_canvas_invert() {
	mut c := Canvas.init(3, 3, 0, 0)
	c.pixel(0, 0, .on)
	c.invert()
	// The on pixel becomes off, and all previously-off pixels become on.
	assert data_at(&c, 0, 0) == 0
	assert data_at(&c, 1, 1) == 255
	assert data_at(&c, 2, 2) == 255
}

fn test_canvas_clear_clipping_regions() {
	mut c := Canvas.init(5, 4, 0, 0)
	c.surface.clear(u32(255) << 24)
	c.clip_left = 1
	c.clip_right = 2
	c.clip_top = 1
	c.clip_bottom = 1
	c.clear_clipping_regions()

	for y in 0 .. 4 {
		for x in 0 .. 5 {
			expected := if y == 1 || y == 2 {
				if x == 1 || x == 2 { u8(255) } else { u8(0) }
			} else {
				u8(0)
			}
			assert data_at(&c, x, y) == expected
		}
	}
}

fn test_canvas_flip_horizontal() {
	mut c := Canvas.init(4, 1, 0, 0)
	c.pixel(0, 0, .on)
	c.flip_horizontal()
	// The pixel at x=0 moves to the far right (x = width-1).
	assert data_at(&c, 0, 0) == 0
	assert data_at(&c, 3, 0) == 255
}

fn test_canvas_flip_horizontal_swaps_clip() {
	mut c := Canvas.init(4, 4, 0, 0)
	c.clip_left = 1
	c.clip_right = 2
	c.flip_horizontal()
	assert c.clip_left == 2
	assert c.clip_right == 1
}

fn test_canvas_flip_vertical() {
	mut c := Canvas.init(1, 4, 0, 0)
	c.pixel(0, 0, .on)
	c.flip_vertical()
	assert data_at(&c, 0, 0) == 0
	assert data_at(&c, 0, 3) == 255
}

fn test_canvas_flip_vertical_swaps_clip() {
	mut c := Canvas.init(4, 4, 0, 0)
	c.clip_top = 1
	c.clip_bottom = 3
	c.flip_vertical()
	assert c.clip_top == 3
	assert c.clip_bottom == 1
}

// ------------------------------------------------------------
// Vector path stroking
// ------------------------------------------------------------

fn test_z2d_path_coordinates_are_clamped_before_transform() {
	mut c := Canvas.init(1, 1, 2, 3)
	mut path := c.static_path(3)
	path.move_to(-8388609, 8388608)
	assert (path.nodes[0] as PathMoveTo).point.x == -8388608.0 + 2.0
	assert (path.nodes[0] as PathMoveTo).point.y == 8388607.0 + 3.0

	path.line_to(8388608, -8388609)
	assert (path.nodes[1] as PathLineTo).point.x == 8388607.0 + 2.0
	assert (path.nodes[1] as PathLineTo).point.y == -8388608.0 + 3.0

	path.curve_to(-8388609, 8388608, 3, 4, 8388608, -8388609)
	assert (path.nodes[2] as PathCurveTo).p1.x == -8388608.0 + 2.0
	assert (path.nodes[2] as PathCurveTo).p1.y == 8388607.0 + 3.0
	assert (path.nodes[2] as PathCurveTo).p2.x == 5
	assert (path.nodes[2] as PathCurveTo).p2.y == 7
	assert (path.nodes[2] as PathCurveTo).p3.x == 8388607.0 + 2.0
	assert (path.nodes[2] as PathCurveTo).p3.y == -8388608.0 + 3.0
}

fn test_stroke_path_closes_closed_subpaths() {
	mut c := Canvas.init(12, 12, 0, 0)
	mut path := c.static_path(4)
	path.move_to(2, 2)
	path.line_to(9, 2)
	path.line_to(9, 9)
	path.close()
	c.stroke_path(path.wrapped_path, StrokeOptions{ line_width: 2 }, .on)!

	// This lies on the final segment from (9, 9) back to (2, 2).
	assert data_at(&c, 5, 5) > 0
}

fn test_z2d_spline_straight_line_fast_path() {
	end := Point{ x: 8, y: 4 }
	points := decompose_spline(Point{}, Point{}, end, end, default_tolerance)
	assert points == [end]
}

fn test_z2d_spline_adaptive_decomposition() {
	points := decompose_spline(Point{}, Point{ x: 0, y: 10 }, Point{ x: 10, y: 10 }, Point{ x: 10, y: 0 }, default_tolerance)
	assert points.len == 16
	assert points.last() == Point{ x: 10, y: 0 }
}

fn test_stroke_path_round_caps_extend_past_endpoints() {
	mut butt := Canvas.init(12, 12, 0, 0)
	mut butt_path := butt.static_path(2)
	butt_path.move_to(3, 6)
	butt_path.line_to(9, 6)
	butt.stroke_path(butt_path.wrapped_path, StrokeOptions{
		line_cap_mode: .butt
		line_width: 2
	}, .on)!

	mut rounded := Canvas.init(12, 12, 0, 0)
	mut rounded_path := rounded.static_path(2)
	rounded_path.move_to(3, 6)
	rounded_path.line_to(9, 6)
	rounded.stroke_path(rounded_path.wrapped_path, StrokeOptions{
		line_cap_mode: .round_
		line_width: 2
	}, .on)!

	assert data_at(&butt, 2, 6) == 0
	assert data_at(&rounded, 2, 6) > 0
}

fn test_inner_stroke_open_path_moves_the_centerline_inward() {
	mut c := Canvas.init(12, 12, 0, 0)
	mut path := c.static_path(3)
	path.move_to(2, 2)
	path.line_to(10, 2)
	path.line_to(10, 10)
	c.inner_stroke_path(path.wrapped_path, StrokeOptions{ line_width: 2 }, .on)!

	assert data_at(&c, 5, 1) == 0
	assert data_at(&c, 5, 2) > 0
	assert data_at(&c, 5, 3) > 0
	assert data_at(&c, 5, 4) == 0
}

fn test_inner_stroke_closed_path_uses_the_same_inset_for_both_windings() {
	points := [Point{ x: 2, y: 2 }, Point{ x: 10, y: 2 }, Point{ x: 10, y: 10 }, Point{ x: 2, y: 10 }]
	mut expected := Canvas.init(12, 12, 0, 0)
	mut centerline := expected.static_path(6)
	centerline.move_to(3, 3)
	centerline.line_to(9, 3)
	centerline.line_to(9, 9)
	centerline.line_to(3, 9)
	centerline.close()
	opts := StrokeOptions{ line_width: 2 }
	expected.stroke_path(centerline.wrapped_path, opts, .on)!

	for winding in [points, points.reverse()] {
		mut actual := Canvas.init(12, 12, 0, 0)
		mut path := actual.static_path(6)
		path.move_to(winding[0].x, winding[0].y)
		for point in winding[1..] {
			path.line_to(point.x, point.y)
		}
		path.close()
		actual.inner_stroke_path(path.wrapped_path, opts, .on)!
		assert actual.surface.pixels == expected.surface.pixels
	}
}

fn test_powerline_mirrored_variants_are_exact_flips() {
	metrics := font.default_grid_metrics(12, 20)
	mut left := Canvas.init(12, 20, 0, 0)
	draw_e0b5(0xe0b5, mut left, 12, 20, metrics)!
	left.flip_horizontal()

	mut right := Canvas.init(12, 20, 0, 0)
	draw_e0b7(0xe0b7, mut right, 12, 20, metrics)!
	assert left.surface.pixels == right.surface.pixels
}

fn test_branch_arc_glyph_uses_box_bezier_arc() {
	metrics := font.default_grid_metrics(12, 20)
	mut actual := Canvas.init(12, 20, 0, 0)
	draw_f5d0_f60d(0xf5d6, mut actual, 12, 20, metrics)!

	mut expected := Canvas.init(12, 20, 0, 0)
	arc(metrics, mut expected, .br, .light)!
	assert actual.surface.pixels == expected.surface.pixels
}

fn test_geometric_outline_uses_inner_stroke_path() {
	metrics := font.default_grid_metrics(12, 20)
	mut actual := Canvas.init(12, 20, 0, 0)
	corner_triangle_outline(metrics, mut actual, .tl)!

	mut expected := Canvas.init(12, 20, 0, 0)
	mut path := expected.static_path(5)
	path.move_to(0, 0)
	path.line_to(0, 20)
	path.line_to(12, 0)
	path.close()
	expected.inner_stroke_path(path.wrapped_path, StrokeOptions{
		line_cap_mode: .butt
		line_width: f64(Thickness.light.height(metrics.box_thickness))
	}, .on)!
	assert actual.surface.pixels == expected.surface.pixels
}

fn test_cursor_uses_cursor_thickness_metric() {
	mut metrics := font.default_grid_metrics(8, 8)
	metrics.cursor_thickness = 2
	mut c := Canvas.init(8, 8, 0, 0)
	cursor_hollow_rect(0, mut c, 8, 8, metrics)!

	assert data_at(&c, 1, 1) == 255
	assert data_at(&c, 2, 2) == 0
}

// ------------------------------------------------------------
// sat_sub -- saturating subtraction (Zig's `-|`)
// ------------------------------------------------------------

fn test_sat_sub() {
	assert sat_sub(5, 3) == 2
	assert sat_sub(3, 5) == 0
	assert sat_sub(0, 1) == 0
	assert sat_sub(10, 10) == 0
}

fn test_sat_add() {
	assert sat_add(5, 3) == 8
	assert sat_add(0xffff_fffe, 1) == 0xffff_ffff
	assert sat_add(0xffff_ffff, 1) == 0xffff_ffff
}

// ------------------------------------------------------------
// fill() -- fills the fraction-bounded box with .on
// ------------------------------------------------------------

fn test_fill_full_cell() {
	metrics := font.default_grid_metrics(8, 8)
	mut c := Canvas.init(8, 8, 0, 0)
	fill(metrics, mut c, Fraction.left, Fraction.right, Fraction.top, Fraction.bottom)
	// Whole cell should be on.
	for y in 0 .. 8 {
		for x in 0 .. 8 {
			assert data_at(&c, x, y) == 255
		}
	}
}

fn test_fill_upper_left_quadrant() {
	metrics := font.default_grid_metrics(8, 8)
	mut c := Canvas.init(8, 8, 0, 0)
	// Fill from left..half horizontally and top..half vertically.
	fill(metrics, mut c, Fraction.left, Fraction.half_, Fraction.top, Fraction.half_)
	// half.max(8) == 4, so the region is x in [0,4), y in [0,4).
	for y in 0 .. 4 {
		for x in 0 .. 4 {
			assert data_at(&c, x, y) == 255
		}
	}
	// Right/bottom halves remain off.
	assert data_at(&c, 4, 0) == 0
	assert data_at(&c, 0, 4) == 0
	assert data_at(&c, 7, 7) == 0
}

// ------------------------------------------------------------
// hline / vline / hline_middle / vline_middle
// ------------------------------------------------------------

fn test_hline() {
	mut c := Canvas.init(6, 6, 0, 0)
	// Horizontal line spanning x in [1,5), top edge at y=2, thickness 1.
	hline(mut c, 1, 5, 2, 1)
	for x in 1 .. 5 {
		assert data_at(&c, x, 2) == 255
	}
	assert data_at(&c, 0, 2) == 0
	assert data_at(&c, 5, 2) == 0
	assert data_at(&c, 1, 1) == 0
	assert data_at(&c, 1, 3) == 0
}

fn test_vline() {
	mut c := Canvas.init(6, 6, 0, 0)
	// Vertical line spanning y in [1,5), left edge at x=3, thickness 1.
	vline(mut c, 1, 5, 3, 1)
	for y in 1 .. 5 {
		assert data_at(&c, 3, y) == 255
	}
	assert data_at(&c, 3, 0) == 0
	assert data_at(&c, 3, 5) == 0
	assert data_at(&c, 2, 1) == 0
	assert data_at(&c, 4, 1) == 0
}

fn test_hline_middle() {
	// cell 8x8, box_thickness 1 -> thick_px 1, top edge at (8-1)/2 = 3.
	metrics := font.default_grid_metrics(8, 8)
	mut c := Canvas.init(8, 8, 0, 0)
	hline_middle(metrics, mut c, Thickness.light)
	for x in 0 .. 8 {
		assert data_at(&c, x, 3) == 255
	}
	assert data_at(&c, 0, 2) == 0
	assert data_at(&c, 0, 4) == 0
}

fn test_vline_middle() {
	metrics := font.default_grid_metrics(8, 8)
	mut c := Canvas.init(8, 8, 0, 0)
	vline_middle(metrics, mut c, Thickness.light)
	// left edge at (8-1)/2 = 3.
	for y in 0 .. 8 {
		assert data_at(&c, 3, y) == 255
	}
	assert data_at(&c, 2, 0) == 0
	assert data_at(&c, 4, 0) == 0
}

// ------------------------------------------------------------
// block_fill / block_shade / full_block_shade
// ------------------------------------------------------------

fn test_full_block_shade() {
	metrics := font.default_grid_metrics(6, 6)
	mut c := Canvas.init(6, 6, 0, 0)
	full_block_shade(metrics, mut c, Shade.medium)
	for y in 0 .. 6 {
		for x in 0 .. 6 {
			assert data_at(&c, x, y) == 0x80
		}
	}
}

fn test_block_fill_alignment() {
	metrics := font.default_grid_metrics(8, 8)
	mut c := Canvas.init(8, 8, 0, 0)
	// Half-width, half-height block aligned to the top-left corner.
	block_fill(metrics, mut c, align_upper_left, 0.5, 0.5)
	// w = round(8*0.5) = 4, h = 4, x=0, y=0.
	for y in 0 .. 4 {
		for x in 0 .. 4 {
			assert data_at(&c, x, y) == 255
		}
	}
	assert data_at(&c, 4, 0) == 0
	assert data_at(&c, 0, 4) == 0
}

fn test_block_shade_bottom_right() {
	metrics := font.default_grid_metrics(8, 8)
	mut c := Canvas.init(8, 8, 0, 0)
	block_shade(metrics, mut c, align_lower_right, 0.5, 0.5, Shade.dark)
	// w=4, h=4, x = 8-4 = 4, y = 8-4 = 4.
	for y in 4 .. 8 {
		for x in 4 .. 8 {
			assert data_at(&c, x, y) == 0xc0
		}
	}
	assert data_at(&c, 3, 7) == 0
	assert data_at(&c, 7, 3) == 0
}

// ------------------------------------------------------------
// Quads / Corner / Edge / Alignment defaults
// ------------------------------------------------------------

fn test_quads_default() {
	q := Quads{}
	assert sizeof(Quads) == 1
	assert q.value == 0
	assert !q.tl()
	assert !q.tr()
	assert !q.bl()
	assert !q.br()

	assert Quads.from_int(0x01).tl()
	assert Quads.from_int(0x02).tr()
	assert Quads.from_int(0x04).bl()
	assert Quads.from_int(0x08).br()
	all := Quads.from_int(quads_mask)
	assert all.value == 0x0f
	assert all.tl()
	assert all.tr()
	assert all.bl()
	assert all.br()
}

fn test_quads_drive_source_quadrant_order() {
	metrics := font.default_grid_metrics(8, 8)
	mut c := Canvas.init(8, 8, 0, 0)
	quadrant(metrics, mut c, Quads.from_int(quad_tl | quad_br))

	assert data_at(&c, 0, 0) == 255
	assert data_at(&c, 7, 0) == 0
	assert data_at(&c, 0, 7) == 0
	assert data_at(&c, 7, 7) == 255
}

fn test_lines_packed_layout() {
	assert sizeof(LineStyle) == 1
	assert sizeof(Lines) == 1

	lines := Lines.from_int(0x39)
	assert lines.up() == .light
	assert lines.right() == .heavy
	assert lines.down() == .double_
	assert lines.left() == .none_

	all_double := Lines.from_int(0xff)
	assert all_double.up() == .double_
	assert all_double.right() == .double_
	assert all_double.down() == .double_
	assert all_double.left() == .double_
}

fn test_alignment_named_constants() {
	assert align_center.horizontal == .center
	assert align_center.vertical == .middle
	assert align_upper_left.horizontal == .left
	assert align_upper_left.vertical == .top
	assert align_lower_right.horizontal == .right
	assert align_lower_right.vertical == .bottom
	// Aliases resolve to the same underlying alignment.
	assert align_top == align_upper
	assert align_bottom == align_lower
	assert align_middle_center == align_center
	assert align_top_left == align_upper_left
}

// ------------------------------------------------------------
// Diagonal helpers (from common.v) draw *something*.
// ------------------------------------------------------------

fn count_on(c &Canvas) int {
	mut n := 0
	for v in c.surface.pixels {
		if v > 0 {
			n++
		}
	}
	return n
}

fn test_light_diagonal_upper_left_to_lower_right_draws() {
	metrics := font.default_grid_metrics(12, 12)
	mut c := Canvas.init(12, 12, 2, 2)
	light_diagonal_upper_left_to_lower_right(metrics, mut c)
	// A diagonal line must set at least ~cell_height pixels.
	assert count_on(&c) >= 10
	// And the top-left / bottom-right neighborhood must be lit.
	assert data_at(&c, 0, 0) > 0 || data_at(&c, 1, 1) > 0
}

fn test_light_diagonal_upper_right_to_lower_left_draws() {
	metrics := font.default_grid_metrics(12, 12)
	mut c := Canvas.init(12, 12, 2, 2)
	light_diagonal_upper_right_to_lower_left(metrics, mut c)
	assert count_on(&c) >= 10
}

// ------------------------------------------------------------
// Canvas.trim -- clip margins collapse onto the drawn content.
// (Translated from canvas.zig `Canvas.trim`.)
// ------------------------------------------------------------

fn test_canvas_trim_single_pixel() {
	// 6x6 surface (no padding). Draw one pixel at (2,3); trim should
	// clip everything except a 1x1 region around it.
	mut c := Canvas.init(6, 6, 0, 0)
	c.pixel(2, 3, .on)
	c.trim()
	// clip_top counts empty rows above the pixel (rows 0,1,2 -> y=3).
	assert c.clip_top == 3
	// clip_bottom counts empty rows below (rows 4,5 -> 2).
	assert c.clip_bottom == 2
	// clip_left counts empty cols left of x=2 -> 2.
	assert c.clip_left == 2
	// clip_right counts empty cols right of x=2 (cols 3,4,5 -> 3).
	assert c.clip_right == 3
}

fn test_canvas_trim_full_transparent() {
	// A fully transparent surface trims to nothing: the trim loops each
	// stop when the remaining span is empty, meeting in the middle.
	mut c := Canvas.init(4, 4, 0, 0)
	c.trim()
	// top advances until clip_top == height - clip_bottom.
	assert c.clip_top + c.clip_bottom == c.sfc_height()
	assert c.clip_left + c.clip_right == c.sfc_width()
}

// ------------------------------------------------------------
// Canvas.rasterize -- returns the trimmed drawing for the font atlas owner.
// ------------------------------------------------------------

fn test_rasterized_region_is_trimmed() {
	// Draw a 2x2 block in the middle of an 8x8 (no padding) canvas.
	mut c := Canvas.init(8, 8, 0, 0)
	c.rect(SpriteRect{ x: 3, y: 2, width: 2, height: 2 }, .on)
	raster := c.rasterize()
	// The region must be trimmed down to the 2x2 drawn content.
	assert raster.width == 2
	assert raster.height == 2
	assert raster.source_x == 3
	assert raster.source_y == 2
	// The returned source rectangle contains the copied 2x2 block.
	for ry in 0 .. 2 {
		for rx in 0 .. 2 {
			idx := (raster.source_y + u32(ry)) * raster.data_width + raster.source_x + u32(rx)
			assert raster.data[int(idx)] == 255
		}
	}
}

fn test_rasterized_empty_canvas() {
	// Nothing drawn -> the region collapses to zero size.
	mut c := Canvas.init(8, 8, 0, 0)
	raster := c.rasterize()
	assert raster.width == 0
	assert raster.height == 0
}

// ------------------------------------------------------------
// SpriteFace.render_glyph -- full pipeline for a covered codepoint.
// (Translated from Face.zig `renderGlyph`.)
// ------------------------------------------------------------

fn test_render_glyph_covered_codepoint() {
	face := SpriteFace{
		metrics: font.default_grid_metrics(8, 16)
	}
	// U+2500 (light horizontal line) is covered and draws a horizontal
	// line, so the resulting glyph must have a non-zero region.
	glyph := face.render_glyph(0x2500, RenderOptions{}) or {
		panic('render_glyph failed: ${err}')
	}
	assert glyph.raster.width > 0
	assert glyph.raster.height > 0
}

fn test_render_glyph_uncovered_codepoint_is_blank() {
	face := SpriteFace{
		metrics: font.default_grid_metrics(8, 16)
	}
	assert !face.has_codepoint(0x0041)
	$if prod {
		// The source retains this blank fallback when runtime safety is off.
		glyph := face.render_glyph(0x0041, RenderOptions{}) or { panic(err) }
		assert glyph.raster.width == 0
		assert glyph.raster.height == 0
	}
}
