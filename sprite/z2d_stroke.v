module sprite

// Direct V translations of the identity-transformation stroke path used by
// Ghostty's Canvas through z2d v0.10.0.
//
// Translated from:
//   z2d/src/internal/tess/Slope.zig
//   z2d/src/internal/tess/Face.zig
//   z2d/src/internal/tess/Pen.zig
//   z2d/src/internal/tess/stroke_plotter.zig
//
// Ghostty's Canvas applies its padding transformation while constructing the
// path and calls painter.stroke with the identity transformation. Therefore
// the non-identity CTM branches in z2d are outside this wrapper's surface.

import math

#include <math.h>

fn C.hypot(f64, f64) f64
fn C.fma(f64, f64, f64) f64

// Use z2d's compensated norm for sprite-sized vectors. A one-ULP change
// can move a stroke edge across a multisample rounding boundary.
fn z2d_slope_magnitude(dx f64, dy f64) f64 {
	x := math.max(math.abs(dx), math.abs(dy))
	y := math.min(math.abs(dx), math.abs(dy))
	if x * math.sqrt(2.220446049250313e-16 / 2) >= y {
		return x
	}
	sum_squares := C.fma(x, x, y * y)
	if sum_squares <= 2.2250738585072014e-308 || math.is_inf(sum_squares, 1) {
		return C.hypot(dx, dy)
	}
	r := math.sqrt(sum_squares)
	rr := r * r
	xx := x * x
	error_ := C.fma(-y, y, rr - xx) + C.fma(r, r, -rr) - C.fma(x, x, -xx)
	return r - error_ / (2 * r)
}

enum Z2dJoinMode as u8 {
	miter
	round_
	bevel
}

struct Z2dSlope {
mut:
	dx f64
	dy f64
}

fn Z2dSlope.init(a Point, b Point) Z2dSlope {
	return Z2dSlope{
		dx: b.x - a.x
		dy: b.y - a.y
	}
}

fn (mut slope Z2dSlope) normalize() f64 {
	assert slope.dx != 0.0 || slope.dy != 0.0
	mut magnitude := 0.0
	if slope.dx == 0.0 {
		if slope.dy > 0.0 {
			magnitude = slope.dy
			slope.dy = 1.0
		} else {
			magnitude = -slope.dy
			slope.dy = -1.0
		}
	} else if slope.dy == 0.0 {
		if slope.dx > 0.0 {
			magnitude = slope.dx
			slope.dx = 1.0
		} else {
			magnitude = -slope.dx
			slope.dx = -1.0
		}
	} else {
		magnitude = z2d_slope_magnitude(slope.dx, slope.dy)
		slope.dx /= magnitude
		slope.dy /= magnitude
	}
	return magnitude
}

fn z2d_sign(value f64) int {
	return if value < 0 {
		-1
	} else if value > 0 { 1 } else { 0 }
}

fn (a Z2dSlope) compare(b Z2dSlope) int {
	// std.math.floatEps(f64), as used by z2d's Slope.compare.
	float_epsilon := 2.220446049250313e-16
	bdy := if math.abs(b.dy - a.dy) > float_epsilon { b.dy } else { a.dy }
	bdx := if math.abs(b.dx - a.dx) > float_epsilon { b.dx } else { a.dx }
	comparison := z2d_sign(a.dy * bdx - bdy * a.dx)
	if comparison != 0 {
		return comparison
	}
	if a.dx == 0 && a.dy == 0 && bdx == 0 && bdy == 0 {
		return 0
	}
	if a.dx == 0 && a.dy == 0 {
		return 1
	}
	if bdx == 0 && bdy == 0 {
		return -1
	}
	if z2d_sign(a.dx) != z2d_sign(bdx) || z2d_sign(a.dy) != z2d_sign(bdy) {
		return if a.dx > 0 || (a.dx == 0 && a.dy > 0) { -1 } else { 1 }
	}
	return 0
}

fn z2d_compare_for_miter_limit(in_slope Z2dSlope, out_slope Z2dSlope, miter_limit f64) bool {
	mut in_normal := in_slope
	mut out_normal := out_slope
	in_normal.normalize()
	out_normal.normalize()
	in_dot_out := in_normal.dx * out_normal.dx + in_normal.dy * out_normal.dy
	return 2 <= miter_limit * miter_limit * (1 + in_dot_out)
}

struct Z2dFace {
	p0         Point
	p1         Point
	width      f64
	dev_slope  Z2dSlope
	user_slope Z2dSlope
	half_width f64
	p0_cw      Point
	p0_ccw     Point
	p1_cw      Point
	p1_ccw     Point
}

fn Z2dFace.init(p0 Point, p1 Point, thickness f64) Z2dFace {
	mut dev_slope := Z2dSlope.init(p0, p1)
	dev_slope.normalize()
	half_width := thickness / 2
	offset_x := -dev_slope.dy * half_width
	offset_y := dev_slope.dx * half_width
	return Z2dFace{
		p0: p0
		p1: p1
		width: thickness
		dev_slope: dev_slope
		user_slope: dev_slope
		half_width: half_width
		p0_cw: Point{ x: p0.x + offset_x, y: p0.y + offset_y }
		p0_ccw: Point{ x: p0.x - offset_x, y: p0.y - offset_y }
		p1_cw: Point{ x: p1.x + offset_x, y: p1.y + offset_y }
		p1_ccw: Point{ x: p1.x - offset_x, y: p1.y - offset_y }
	}
}

fn (in_face Z2dFace) intersect(out_face Z2dFace, clockwise bool) Point {
	in_point := if clockwise { in_face.p1_ccw } else { in_face.p1_cw }
	out_point := if clockwise { out_face.p0_ccw } else { out_face.p0_cw }
	mut in_slope := in_face.dev_slope
	mut out_slope := out_face.dev_slope
	in_slope.normalize()
	out_slope.normalize()
	numerator := (out_point.x - in_point.x) * in_slope.dy * out_slope.dy - out_point.y * out_slope.dx * in_slope.dy + in_point.y * in_slope.dx * out_slope.dy
	denominator := in_slope.dx * out_slope.dy - out_slope.dx * in_slope.dy
	result_y := numerator / denominator
	result_x := if math.abs(in_slope.dy) >= math.abs(out_slope.dy) {
		(result_y - in_point.y) * in_slope.dx / in_slope.dy + in_point.x
	} else {
		(result_y - out_point.y) * out_slope.dx / out_slope.dy + out_point.x
	}
	return Point{ x: result_x, y: result_y }
}

struct Z2dPenVertex {
	point Point
mut:
	slope_cw  Z2dSlope
	slope_ccw Z2dSlope
}

struct Z2dPen {
	vertices []Z2dPenVertex
}

fn Z2dPen.init(thickness f64, tolerance f64) Z2dPen {
	radius := thickness / 2
	major_axis := radius
	mut num_vertices := 0
	if tolerance >= major_axis * 4 {
		num_vertices = 1
	} else if tolerance >= major_axis {
		num_vertices = 4
	} else {
		delta := math.acos(1 - tolerance / major_axis)
		if delta == 0 {
			num_vertices = 4
		} else {
			num_vertices = int(math.ceil(2 * math.pi / delta))
			if num_vertices < 4 {
				num_vertices = 4
			} else if num_vertices % 2 != 0 {
				num_vertices += 1
			}
		}
	}

	mut vertices := []Z2dPenVertex{cap: num_vertices}
	for i in 0 .. num_vertices {
		theta := 2 * math.pi * f64(i) / f64(num_vertices)
		vertices << Z2dPenVertex{
			point: Point{
				x: radius * math.cos(theta)
				y: radius * math.sin(theta)
			}
		}
	}
	for i in 0 .. num_vertices {
		next := if i >= num_vertices - 1 { 0 } else { i + 1 }
		prev := if i == 0 { num_vertices - 1 } else { i - 1 }
		vertices[i].slope_cw = Z2dSlope.init(vertices[prev].point, vertices[i].point)
		vertices[i].slope_ccw = Z2dSlope.init(vertices[i].point, vertices[next].point)
	}
	return Z2dPen{ vertices: vertices }
}

fn (pen &Z2dPen) vertices_for(from_slope Z2dSlope, to_slope Z2dSlope, clockwise bool) []Z2dPenVertex {
	mut start := 0
	mut end := 0
	vertices_len := pen.vertices.len
	if clockwise {
		mut low := 0
		mut high := vertices_len
		mut i := (low + high) >> 1
		for high - low > 1 {
			if pen.vertices[i].slope_cw.compare(from_slope) < 0 {
				low = i
			} else {
				high = i
			}
			i = (low + high) >> 1
		}
		if pen.vertices[i].slope_cw.compare(from_slope) < 0 {
			i += 1
			if i == vertices_len {
				i = 0
			}
		}
		start = i
		if to_slope.compare(pen.vertices[i].slope_ccw) >= 0 {
			low = i
			high = i + vertices_len
			i = (low + high) >> 1
			for high - low > 1 {
				j := if i >= vertices_len { i - vertices_len } else { i }
				if pen.vertices[j].slope_cw.compare(to_slope) > 0 {
					high = i
				} else {
					low = i
				}
				i = (low + high) >> 1
			}
			if i >= vertices_len {
				i -= vertices_len
			}
		}
		end = i
	} else {
		mut low := 0
		mut high := vertices_len
		mut i := (low + high) >> 1
		for high - low > 1 {
			if from_slope.compare(pen.vertices[i].slope_ccw) < 0 {
				low = i
			} else {
				high = i
			}
			i = (low + high) >> 1
		}
		if from_slope.compare(pen.vertices[i].slope_ccw) < 0 {
			i += 1
			if i == vertices_len {
				i = 0
			}
		}
		start = i
		if pen.vertices[i].slope_cw.compare(to_slope) <= 0 {
			low = i
			high = i + vertices_len
			i = (low + high) >> 1
			for high - low > 1 {
				j := if i >= vertices_len { i - vertices_len } else { i }
				if to_slope.compare(pen.vertices[j].slope_ccw) > 0 {
					high = i
				} else {
					low = i
				}
				i = (low + high) >> 1
			}
			if i >= vertices_len {
				i -= vertices_len
			}
		}
		end = i
	}

	mut result := []Z2dPenVertex{}
	mut idx := start
	for idx != end {
		result << pen.vertices[idx]
		if clockwise {
			idx += 1
			if idx == pen.vertices.len {
				idx = 0
			}
		} else {
			if idx == 0 {
				idx = pen.vertices.len
			}
			idx -= 1
		}
	}
	return result
}

fn (face Z2dFace) cap_points(cap_mode LineCapMode, clockwise bool, pen ?Z2dPen) []Point {
	return match cap_mode {
		.butt {
			if clockwise { [face.p1_ccw, face.p1_cw] } else { [face.p1_cw, face.p1_ccw] }
		}
		.square {
			offset_x := face.user_slope.dx * face.half_width
			offset_y := face.user_slope.dy * face.half_width
			if clockwise {
				[
					face.p1_ccw,
					Point{ x: face.p1_ccw.x + offset_x, y: face.p1_ccw.y + offset_y },
					Point{ x: face.p1_cw.x + offset_x, y: face.p1_cw.y + offset_y },
					face.p1_cw,
				]
			} else {
				[
					face.p1_cw,
					Point{ x: face.p1_cw.x + offset_x, y: face.p1_cw.y + offset_y },
					Point{ x: face.p1_ccw.x + offset_x, y: face.p1_ccw.y + offset_y },
					face.p1_ccw,
				]
			}
		}
		.round_ {
			actual_pen := pen or { return []Point{} }
			to_slope := Z2dSlope{ dx: -face.dev_slope.dx, dy: -face.dev_slope.dy }
			mut result := []Point{}
			result << if clockwise { face.p1_ccw } else { face.p1_cw }
			for vertex in actual_pen.vertices_for(face.dev_slope, to_slope, clockwise) {
				result << Point{ x: face.p1.x + vertex.point.x, y: face.p1.y + vertex.point.y }
			}
			result << if clockwise { face.p1_cw } else { face.p1_ccw }
			result
		}
	}
}

fn (face Z2dFace) cap_p0_points(cap_mode LineCapMode, clockwise bool, pen ?Z2dPen) []Point {
	reversed := Z2dFace.init(face.p1, face.p0, face.width)
	return reversed.cap_points(cap_mode, clockwise, pen)
}

struct Z2dContour {
mut:
	points []Point
	scale  f64
}

fn (mut contour Z2dContour) plot(point Point, before_start bool) {
	scaled := Point{ x: point.x * contour.scale, y: point.y * contour.scale }
	if before_start {
		contour.points.insert(0, scaled)
	} else {
		contour.points << scaled
	}
}

fn (mut contour Z2dContour) plot_reverse(point Point) {
	contour.points.insert(0, Point{ x: point.x * contour.scale, y: point.y * contour.scale })
}

fn (mut polygon Z2dPolygon) add_edges_from_contour(contour Z2dContour) {
	if contour.points.len == 0 {
		return
	}
	for i in 0 .. contour.points.len - 1 {
		polygon.add_edge(contour.points[i], contour.points[i + 1])
	}
	polygon.add_edge(contour.points.last(), contour.points[0])
}

struct Z2dStrokePointBuffer {
mut:
	items []Point
}

fn (mut points Z2dStrokePointBuffer) add(point Point) {
	if points.items.len < 5 {
		points.items << point
	} else {
		points.items[2] = points.items[3]
		points.items[3] = points.items[4]
		points.items[4] = point
	}
}

fn (mut points Z2dStrokePointBuffer) reset() {
	points.items.clear()
}

struct Z2dStrokePlotter {
	thickness   f64
	tolerance   f64
	cap_mode    LineCapMode
	join_mode   Z2dJoinMode = .miter
	miter_limit f64 = 10.0
mut:
	pen       ?Z2dPen
	points    Z2dStrokePointBuffer
	clockwise ?bool
	result    Z2dPolygon
	outer     Z2dContour
	inner     Z2dContour
}

fn (mut plotter Z2dStrokePlotter) run_line_to(point Point, join_mode Z2dJoinMode) ! {
	if plotter.points.items.len == 0 {
		return error('invalid stroke path state')
	}
	current := plotter.points.items.last()
	if points_equal(point, current) {
		return
	}
	plotter.points.add(point)
	if plotter.points.items.len > 2 {
		len := plotter.points.items.len
		plotter.join(join_mode, plotter.points.items[len - 3], plotter.points.items[len - 2], plotter.points.items[len - 1], false)
	}
}

fn (mut plotter Z2dStrokePlotter) plot_single(start Point, end Point) {
	face := Z2dFace.init(start, end, plotter.thickness)
	for point in face.cap_p0_points(plotter.cap_mode, true, plotter.pen) {
		plotter.outer.plot(point, false)
	}
	for point in face.cap_points(plotter.cap_mode, true, plotter.pen) {
		plotter.outer.plot(point, false)
	}
	plotter.result.add_edges_from_contour(plotter.outer)
	plotter.outer = Z2dContour{ scale: z2d_multisample_scale }
	plotter.clockwise = none
}

fn (mut plotter Z2dStrokePlotter) plot_open_joined(start0 Point, end0 Point, start1 Point, end1 Point) {
	start_face := Z2dFace.init(start0, end0, plotter.thickness)
	end_face := Z2dFace.init(start1, end1, plotter.thickness)
	clockwise := plotter.clockwise or { true }
	start_cap := start_face.cap_p0_points(plotter.cap_mode, clockwise, plotter.pen)
	// z2d inserts each point before the same pre-existing linked-list node, so
	// the cap points retain their plotted order. Prepending in reverse gives the
	// identical order with V's array-backed contour.
	for i := start_cap.len - 1; i >= 0; i-- {
		plotter.outer.plot(start_cap[i], true)
	}
	for point in end_face.cap_points(plotter.cap_mode, clockwise, plotter.pen) {
		plotter.outer.plot(point, false)
	}
	plotter.outer.points << plotter.inner.points
	plotter.result.add_edges_from_contour(plotter.outer)
	plotter.outer = Z2dContour{ scale: z2d_multisample_scale }
	plotter.inner = Z2dContour{ scale: z2d_multisample_scale }
	plotter.clockwise = none
}

fn (mut plotter Z2dStrokePlotter) plot_closed_joined(initial0 Point, initial1 Point, p1 Point, p2 Point) {
	if !points_equal(p2, initial0) {
		plotter.join(plotter.join_mode, p1, p2, initial0, false)
		plotter.join(plotter.join_mode, p2, initial0, initial1, false)
	} else {
		plotter.join(plotter.join_mode, p1, initial0, initial1, false)
	}
	plotter.result.add_edges_from_contour(plotter.outer)
	plotter.result.add_edges_from_contour(plotter.inner)
	plotter.outer = Z2dContour{ scale: z2d_multisample_scale }
	plotter.inner = Z2dContour{ scale: z2d_multisample_scale }
	plotter.clockwise = none
}

fn (mut plotter Z2dStrokePlotter) plot_dotted(point Point) {
	if plotter.cap_mode != .round_ {
		return
	}
	pen := plotter.pen or { return }
	for vertex in pen.vertices {
		plotter.outer.plot(Point{ x: point.x + vertex.point.x, y: point.y + vertex.point.y }, false)
	}
	plotter.result.add_edges_from_contour(plotter.outer)
	plotter.outer = Z2dContour{ scale: z2d_multisample_scale }
	plotter.clockwise = none
}

fn (mut plotter Z2dStrokePlotter) close_path() {
	match plotter.points.items.len {
		0 {}
		1 { plotter.plot_dotted(plotter.points.items[0]) }
		2 { plotter.plot_single(plotter.points.items[0], plotter.points.items[1]) }
		else {
			len := plotter.points.items.len
			plotter.plot_closed_joined(plotter.points.items[0], plotter.points.items[1], plotter.points.items[len - 2], plotter.points.items[len - 1])
		}
	}
	plotter.points.reset()
}

fn (mut plotter Z2dStrokePlotter) finish() {
	match plotter.points.items.len {
		0, 1 {}
		2 { plotter.plot_single(plotter.points.items[0], plotter.points.items[1]) }
		else {
			len := plotter.points.items.len
			plotter.plot_open_joined(plotter.points.items[0], plotter.points.items[1], plotter.points.items[len - 2], plotter.points.items[len - 1])
		}
	}
}

fn (mut plotter Z2dStrokePlotter) join(join_mode Z2dJoinMode, p0 Point, p1 Point, p2 Point, before_outer bool) {
	if points_equal(p0, p1) || points_equal(p1, p2) {
		if plotter.clockwise == none {
			plotter.clockwise = false
		}
		return
	}
	in_face := Z2dFace.init(p0, p1, plotter.thickness)
	out_face := Z2dFace.init(p1, p2, plotter.thickness)
	join_clockwise := in_face.dev_slope.compare(out_face.dev_slope) < 0
	poly_clockwise := plotter.clockwise or { join_clockwise }
	direction_switched := join_clockwise != poly_clockwise

	mut outer_points := []Point{}
	mut inner_points := []Point{}
	if in_face.dev_slope.compare(out_face.dev_slope) == 0 {
		outer_points << if join_clockwise { in_face.p1_ccw } else { in_face.p1_cw }
		inner_points << if join_clockwise { in_face.p1_cw } else { in_face.p1_ccw }
	} else {
		match join_mode {
			.miter, .bevel {
				if join_mode == .miter && z2d_compare_for_miter_limit(in_face.dev_slope, out_face.dev_slope, plotter.miter_limit) {
					outer_points << in_face.intersect(out_face, join_clockwise)
				} else {
					outer_points << if join_clockwise { in_face.p1_ccw } else { in_face.p1_cw }
					outer_points << if join_clockwise { out_face.p0_ccw } else { out_face.p0_cw }
				}
			}
			.round_ {
				pen := plotter.pen or { Z2dPen{} }
				outer_points << if join_clockwise { in_face.p1_ccw } else { in_face.p1_cw }
				for vertex in pen.vertices_for(in_face.dev_slope, out_face.dev_slope, join_clockwise) {
					outer_points << Point{ x: p1.x + vertex.point.x, y: p1.y + vertex.point.y }
				}
				outer_points << if join_clockwise { out_face.p0_ccw } else { out_face.p0_cw }
			}
		}
		inner_points << if join_clockwise { in_face.p1_cw } else { in_face.p1_ccw }
		inner_points << p1
		inner_points << if join_clockwise { out_face.p0_cw } else { out_face.p0_ccw }
	}

	if direction_switched {
		for point in outer_points {
			plotter.inner.plot_reverse(point)
		}
		for point in inner_points {
			plotter.outer.plot(point, before_outer)
		}
	} else {
		for point in outer_points {
			plotter.outer.plot(point, before_outer)
		}
		for point in inner_points {
			plotter.inner.plot_reverse(point)
		}
	}
	if plotter.clockwise == none {
		plotter.clockwise = poly_clockwise
	}
}

fn z2d_stroke_plot(path Path, options StrokeOptions) !Z2dPolygon {
	minimum_line_width := 0.00390625
	thickness := if options.line_width >= minimum_line_width {
		options.line_width
	} else {
		minimum_line_width
	}
	cap_mode := if options.line_width >= 2 { options.line_cap_mode } else { LineCapMode.butt }
	mut plotter := Z2dStrokePlotter{
		thickness: thickness
		tolerance: default_tolerance
		cap_mode: cap_mode
		join_mode: .miter
		miter_limit: 10
		outer: Z2dContour{ scale: z2d_multisample_scale }
		inner: Z2dContour{ scale: z2d_multisample_scale }
	}
	if plotter.join_mode == .round_ || plotter.cap_mode == .round_ {
		plotter.pen = Z2dPen.init(thickness, default_tolerance)
	}

	for node in path.nodes {
		match node {
			PathMoveTo {
				if plotter.points.items.len > 0 {
					plotter.finish()
				}
				plotter.points.reset()
				plotter.points.add(node.point)
			}
			PathLineTo {
				plotter.run_line_to(node.point, plotter.join_mode)!
			}
			PathCurveTo {
				if plotter.points.items.len == 0 {
					return error('invalid stroke path state')
				}
				if plotter.pen == none {
					plotter.pen = Z2dPen.init(thickness, default_tolerance)
				}
				current := plotter.points.items.last()
				for point in decompose_spline(current, node.p1, node.p2, node.p3, default_tolerance) {
					plotter.run_line_to(point, .round_)!
				}
			}
			PathClose {
				plotter.close_path()
			}
		}
	}
	plotter.finish()
	return plotter.result
}
