// SPDX-License-Identifier: MPL-2.0
// Copyright © 2024-2026 Chris Marchesi
// Path offsetting for sprite outlines, based on z2d's internal/path_fx/offset.zig.
module sprite

import math

struct OffsetSegment {
	start Point
	slope Z2dSlope
mut:
	end Point
}

fn compare_offset_slopes(a Z2dSlope, b Z2dSlope) int {
	epsilon := 2.220446049250313e-16
	dx := if math.abs(b.dx - a.dx) > epsilon { b.dx } else { a.dx }
	dy := if math.abs(b.dy - a.dy) > epsilon { b.dy } else { a.dy }
	return z2d_sign(a.dy * dx - dy * a.dx)
}

fn append_offset_segment(mut contour []OffsetSegment, start Point, end Point) {
	if points_equal(start, end) {
		return
	}
	mut slope := Z2dSlope.init(start, end)
	slope.normalize()
	if contour.len > 0 && compare_offset_slopes(contour.last().slope, slope) == 0 {
		contour[contour.len - 1].end = end
		return
	}
	contour << OffsetSegment{ start: start, end: end, slope: slope }
}

fn offset_point(point Point, slope Z2dSlope, distance f64) Point {
	return Point{ x: point.x - slope.dy * distance, y: point.y + slope.dx * distance }
}

fn offset_join(incoming OffsetSegment, outgoing OffsetSegment, distance f64) Point {
	a := offset_point(incoming.end, incoming.slope, distance)
	b := offset_point(outgoing.start, outgoing.slope, distance)
	u := incoming.slope
	v := outgoing.slope
	determinant := u.dx * v.dy - u.dy * v.dx
	if determinant == 0.0 {
		return a
	}
	t := ((b.x - a.x) * v.dy - (b.y - a.y) * v.dx) / determinant
	return Point{ x: a.x + t * u.dx, y: a.y + t * u.dy }
}

fn append_offset_contour(mut nodes []PathNode, contour []OffsetSegment, closed bool, inset f64) {
	if contour.len == 0 || (closed && contour.len < 3) {
		return
	}
	if !closed {
		clockwise := contour.len == 1 || compare_offset_slopes(contour[0].slope, contour[1].slope) < 0
		distance := if clockwise { inset } else { -inset }
		first := contour[0]
		nodes << PathMoveTo{ point: offset_point(first.start, first.slope, distance) }
		for i in 1 .. contour.len {
			nodes << PathLineTo{ point: offset_join(contour[i - 1], contour[i], distance) }
		}
		last := contour.last()
		nodes << PathLineTo{ point: offset_point(last.end, last.slope, distance) }
		return
	}

	// The orientation at the leftmost vertex determines the interior of a
	// closed contour, including contours that have concave joins elsewhere.
	mut first := 0
	for i in 1 .. contour.len {
		if contour[i].start.x < contour[first].start.x {
			first = i
		}
	}
	previous := (first + contour.len - 1) % contour.len
	clockwise := compare_offset_slopes(contour[previous].slope, contour[first].slope) < 0
	distance := if clockwise { inset } else { -inset }
	start := offset_join(contour[previous], contour[first], distance)
	nodes << PathMoveTo{ point: start }
	for i in 1 .. contour.len {
		index := (first + i) % contour.len
		prior := (index + contour.len - 1) % contour.len
		nodes << PathLineTo{ point: offset_join(contour[prior], contour[index], distance) }
	}
	nodes << PathClose{}
	nodes << PathMoveTo{ point: start }
}

// Flatten curves with the same tolerance as the stroke rasterizer, then
// intersect adjacent translated segments to keep the original join angles.
fn inset_sprite_path(path Path, inset f64) !Path {
	mut nodes := []PathNode{cap: path.nodes.len}
	mut contour := []OffsetSegment{}
	mut current := ?Point(none)
	mut initial := Point{}
	for node in path.nodes {
		match node {
			PathMoveTo {
				append_offset_contour(mut nodes, contour, false, inset)
				contour.clear()
				current = node.point
				initial = node.point
			}
			PathLineTo {
				start := current or { return error('invalid inset path state') }
				append_offset_segment(mut contour, start, node.point)
				current = node.point
			}
			PathCurveTo {
				mut start := current or { return error('invalid inset path state') }
				for point in decompose_spline(start, node.p1, node.p2, node.p3, default_tolerance) {
					append_offset_segment(mut contour, start, point)
					start = point
				}
				current = node.p3
			}
			PathClose {
				if point := current {
					append_offset_segment(mut contour, point, initial)
					append_offset_contour(mut nodes, contour, true, inset)
				}
				contour.clear()
				current = none
			}
		}
	}
	append_offset_contour(mut nodes, contour, false, inset)
	return Path{ nodes: nodes }
}
