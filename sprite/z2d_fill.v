module sprite

// Direct V translations of the z2d v0.10.0 fill tessellator and default
// multisample rasterizer used by Ghostty's sprite Canvas.
//
// Translated from:
//   z2d/src/internal/tess/fill_plotter.zig
//   z2d/src/internal/tess/Polygon.zig
//   z2d/src/internal/raster/sparse_coverage.zig
//   z2d/src/internal/raster/multisample.zig

import math

// Zig keeps the multiply and add in WorkingEdgeSet.inc as separate f64
// operations. Clang otherwise contracts the equivalent generated C into an
// FMA, which changes exact half-pixel intersections by one multisample step.
#flag -ffp-contract=off

const z2d_multisample_scale = 4

struct Z2dEdge {
mut:
	y0      f64
	y1      f64
	x_start f64
	x_inc   f64
}

fn (edge &Z2dEdge) dir() int {
	return if edge.y0 < edge.y1 { -1 } else { 1 }
}

fn (edge &Z2dEdge) top() f64 {
	return if edge.y0 < edge.y1 { edge.y0 } else { edge.y1 }
}

fn (edge &Z2dEdge) bottom() f64 {
	return if edge.y0 < edge.y1 { edge.y1 } else { edge.y0 }
}

struct Z2dPolygon {
mut:
	edges         []Z2dEdge
	scale         f64 = 1.0
	extent_top    f64
	extent_bottom f64
	extent_left   f64
	extent_right  f64
}

fn (mut polygon Z2dPolygon) add_edge(p0 Point, p1 Point) {
	p0_scaled := Point{
		x: p0.x * polygon.scale
		y: p0.y * polygon.scale
	}
	p1_scaled := Point{
		x: p1.x * polygon.scale
		y: p1.y * polygon.scale
	}

	edge := if p0_scaled.y < p1_scaled.y {
		Z2dEdge{
			y0: p0_scaled.y
			y1: p1_scaled.y
			x_start: p0_scaled.x
			x_inc: (p1_scaled.x - p0_scaled.x) / (p1_scaled.y - p0_scaled.y)
		}
	} else if p0_scaled.y > p1_scaled.y {
		Z2dEdge{
			y0: p0_scaled.y
			y1: p1_scaled.y
			x_start: p1_scaled.x
			x_inc: (p0_scaled.x - p1_scaled.x) / (p0_scaled.y - p1_scaled.y)
		}
	} else {
		return
	}

	extent_top := edge.top()
	extent_bottom := edge.bottom()
	extent_left := if p0_scaled.x < p1_scaled.x { p0_scaled.x } else { p1_scaled.x }
	extent_right := if p0_scaled.x < p1_scaled.x { p1_scaled.x } else { p0_scaled.x }
	if polygon.edges.len == 0 {
		polygon.extent_top = extent_top
		polygon.extent_bottom = extent_bottom
		polygon.extent_left = extent_left
		polygon.extent_right = extent_right
	} else {
		if extent_top < polygon.extent_top {
			polygon.extent_top = extent_top
		}
		if extent_bottom > polygon.extent_bottom {
			polygon.extent_bottom = extent_bottom
		}
		if extent_left < polygon.extent_left {
			polygon.extent_left = extent_left
		}
		if extent_right > polygon.extent_right {
			polygon.extent_right = extent_right
		}
	}
	polygon.edges << edge
}

fn (polygon &Z2dPolygon) in_box(scale f64, box_width int, box_height int) bool {
	if polygon.edges.len == 0 {
		return false
	}
	poly_start_x := int(math.floor(polygon.extent_left / scale))
	poly_start_y := int(math.floor(polygon.extent_top / scale))
	poly_end_x := int(math.ceil(polygon.extent_right / scale))
	poly_end_y := int(math.ceil(polygon.extent_bottom / scale))
	poly_width := poly_end_x - poly_start_x
	poly_height := poly_end_y - poly_start_y
	if poly_width < 0 || poly_height < 0 {
		panic('negative polygon width or height')
	}
	if poly_width == 0 || poly_height == 0 {
		return false
	}
	if poly_start_x + poly_width < 0 || poly_start_y + poly_height < 0 {
		return false
	}
	if poly_start_x >= box_width || poly_start_y >= box_height {
		return false
	}
	return true
}

// PointBuffer(1, 3) keeps the first point and the last two points once full.
struct Z2dFillPointBuffer {
mut:
	items []Point
}

fn (mut points Z2dFillPointBuffer) add(point Point) {
	if points.items.len < 3 {
		points.items << point
	} else {
		points.items[1] = points.items[2]
		points.items[2] = point
	}
}

fn (mut points Z2dFillPointBuffer) reset() {
	points.items.clear()
}

fn (points &Z2dFillPointBuffer) first() ?Point {
	if points.items.len == 0 {
		return none
	}
	return points.items[0]
}

fn (points &Z2dFillPointBuffer) last() ?Point {
	if points.items.len == 0 {
		return none
	}
	return points.items.last()
}

fn z2d_fill_plot(path Path, scale f64, tolerance f64) !Z2dPolygon {
	mut result := Z2dPolygon{
		scale: scale
	}
	mut points := Z2dFillPointBuffer{}

	for i, node in path.nodes {
		match node {
			PathMoveTo {
				// Path.close adds this final move back to the subpath start.
				if i == path.nodes.len - 1 {
					break
				}
				points.reset()
				points.add(node.point)
			}
			PathLineTo {
				if last := points.last() {
					point := node.point
					if !points_equal(last, point) {
						result.add_edge(last, point)
						points.add(point)
					}
				} else {
					return error('invalid fill path state')
				}
			}
			PathCurveTo {
				if last := points.last() {
					for point in decompose_spline(last, node.p1, node.p2, node.p3, tolerance) {
						if current := points.last() {
							if !points_equal(current, point) {
								result.add_edge(current, point)
								points.add(point)
							}
						}
					}
				} else {
					return error('invalid fill path state')
				}
			}
			PathClose {
				if points.items.len >= 3 {
					first := points.first() or { continue }
					last := points.last() or { continue }
					if points_equal(last, first) {
						continue
					}
					result.add_edge(last, first)
					points.add(first)
				}
			}
		}
	}
	return result
}

struct Z2dWorkingEdge {
	edge Z2dEdge
mut:
	x int
}

fn z2d_breakpoints(polygon &Z2dPolygon) []int {
	mut result := []int{cap: polygon.edges.len * 2}
	for edge in polygon.edges {
		for value in [int(math.round(edge.top())), int(math.round(edge.bottom()))] {
			mut low := 0
			mut high := result.len
			for low < high {
				mid := low + (high - low) / 2
				if result[mid] < value {
					low = mid + 1
				} else {
					high = mid
				}
			}
			if low == result.len {
				result << value
			} else if result[low] != value {
				result.insert(low, value)
			}
		}
	}
	return result
}

fn z2d_rescan_edges(polygon &Z2dPolygon, line_y int) []Z2dWorkingEdge {
	line_y_middle := f64(line_y) + 0.5
	mut result := []Z2dWorkingEdge{cap: polygon.edges.len}
	for edge in polygon.edges {
		if edge.top() < line_y_middle && edge.bottom() >= line_y_middle {
			result << Z2dWorkingEdge{
				edge: edge
			}
		}
	}
	return result
}

fn z2d_inc_sort_filter(mut edges []Z2dWorkingEdge, y int) []int {
	y_mid := f64(y) + 0.5
	for i in 0 .. edges.len {
		edges[i].x = int(math.round(edges[i].edge.x_start + edges[i].edge.x_inc * (y_mid - edges[i].edge.top())))
	}
	edges.sort(a.x < b.x)

	// Ghostty uses z2d's default non-zero fill rule.
	mut result := []int{cap: edges.len}
	mut winding_number := 0
	for edge in edges {
		result << edge.x
		if winding_number == 0 {
			winding_number += edge.edge.dir()
		} else {
			winding_number += edge.edge.dir()
			if winding_number != 0 {
				result.delete_last()
			}
		}
	}
	return result
}

struct Z2dSparseCoverageBuffer {
mut:
	values   []u8
	lengths  []u32
	len      u32
	capacity u32
}

fn Z2dSparseCoverageBuffer.init(capacity u32) Z2dSparseCoverageBuffer {
	return Z2dSparseCoverageBuffer{
		values: []u8{len: int(capacity)}
		lengths: []u32{len: int(capacity)}
		capacity: capacity
	}
}

fn (mut buffer Z2dSparseCoverageBuffer) reset() {
	buffer.len = 0
	if buffer.lengths.len > 0 {
		buffer.lengths[0] = 0
	}
}

fn (buffer &Z2dSparseCoverageBuffer) get(x u32) (u8, u32) {
	return buffer.values[x], buffer.lengths[x]
}

fn (mut buffer Z2dSparseCoverageBuffer) put(x u32, value u8, len u32) {
	assert x + len <= buffer.capacity
	buffer.values[x] = value
	buffer.lengths[x] = len
}

fn (mut buffer Z2dSparseCoverageBuffer) put_value(x u32, value u8) {
	buffer.values[x] = value
}

fn (mut buffer Z2dSparseCoverageBuffer) split_inner(x u32, len u32) {
	mut idx := x
	mut rem := len
	for {
		current_value, current_len := buffer.get(idx)
		if rem < current_len {
			buffer.put(idx, current_value, rem)
			buffer.put(idx + rem, current_value, current_len - rem)
			break
		} else if rem == current_len {
			break
		}
		rem -= current_len
		idx += current_len
	}
}

fn (mut buffer Z2dSparseCoverageBuffer) extend(x u32, len u32) {
	if len == 0 {
		return
	}
	if x == buffer.len {
		buffer.put(x, 0, len)
		buffer.len = x + len
		return
	}
	if x > buffer.len {
		buffer.put(buffer.len, 0, x - buffer.len)
		buffer.put(x, 0, len)
		buffer.len = x + len
		return
	}

	buffer.split_inner(0, x)
	span_len := x + len
	if span_len > buffer.len {
		buffer.put(buffer.len, 0, span_len - buffer.len)
		buffer.len = span_len
	}
	buffer.split_inner(x, len)
}

fn (mut buffer Z2dSparseCoverageBuffer) add_span(x u32, value u8, len u32) {
	buffer.extend(x, len)
	mut x_cur := x
	x_end := x + len
	for x_cur < x_end {
		coverage_value, coverage_len := buffer.get(x_cur)
		buffer.put_value(x_cur, coverage_value + value)
		x_cur += coverage_len
	}
}

fn (mut buffer Z2dSparseCoverageBuffer) add_single(x u32, value u8) {
	buffer.extend(x, 1)
	coverage_value, _ := buffer.get(x)
	buffer.put_value(x, coverage_value + value)
}

fn z2d_add_multisample_span(mut buffer Z2dSparseCoverageBuffer, x u32, len u32) {
	assert x + len <= buffer.capacity * z2d_multisample_scale
	if len == 0 {
		return
	}

	start_x := x / z2d_multisample_scale
	start_offset := x - start_x * z2d_multisample_scale
	if start_offset == 0 && len >= z2d_multisample_scale {
		front_len := len / z2d_multisample_scale
		buffer.add_span(start_x, z2d_multisample_scale, front_len)
		end_coverage := u8(z2d_min_u32(z2d_multisample_scale, len - front_len * z2d_multisample_scale))
		if end_coverage > 0 {
			buffer.add_single(start_x + front_len, end_coverage)
		}
	} else {
		start_coverage_raw := u8(z2d_min_u32(z2d_multisample_scale, z2d_min_u32(len, z2d_multisample_scale - start_offset)))
		buffer.add_single(start_x, start_coverage_raw)
		after_start_raw := len - start_coverage_raw
		mid_len := after_start_raw / z2d_multisample_scale
		if mid_len > 0 {
			buffer.add_span(start_x + 1, z2d_multisample_scale, mid_len)
		}
		end_coverage_raw := u8(z2d_min_u32(z2d_multisample_scale, after_start_raw - mid_len * z2d_multisample_scale))
		if end_coverage_raw > 0 {
			buffer.add_single(start_x + 1 + mid_len, end_coverage_raw)
		}
	}
}

fn z2d_min_u32(a u32, b u32) u32 {
	return if a < b { a } else { b }
}

fn clamp_int(value int, low int, high int) int {
	return if value < low {
		low
	} else if value > high { high } else { value }
}

fn z2d_composite_span(mut c Canvas, x int, y int, len u32, color Color, opacity u8) {
	pattern_alpha := u32(u8(color))
	source_alpha := pattern_alpha * u32(opacity) / 255
	width := c.surface.width
	start := y * width + x
	for i in 0 .. int(len) {
		destination_alpha := c.surface.pixels[start + i] >> 24
		c.surface.pixels[start + i] = (source_alpha + destination_alpha - source_alpha * destination_alpha / 255) << 24
	}
}

fn z2d_multisample_fill(mut canvas Canvas, polygon Z2dPolygon, color Color) {
	coverage_full := z2d_multisample_scale * z2d_multisample_scale
	alpha_scale := 256 / coverage_full
	sfc_width := int(canvas.sfc_width())
	sfc_height := int(canvas.sfc_height())
	if !polygon.in_box(z2d_multisample_scale, sfc_width, sfc_height) {
		return
	}

	start_scanline := clamp_int(int(math.floor(polygon.extent_top / z2d_multisample_scale)), 0, sfc_height - 1)
	end_scanline := clamp_int(int(math.ceil(polygon.extent_bottom / z2d_multisample_scale)), start_scanline, sfc_height - 1)
	scanline_start_x := clamp_int(int(math.floor(polygon.extent_left / z2d_multisample_scale)), 0, sfc_width - 1)
	scanline_end_x := clamp_int(int(math.ceil(polygon.extent_right / z2d_multisample_scale)), scanline_start_x, sfc_width)
	scanline_draw_width := scanline_end_x - scanline_start_x
	if scanline_draw_width < 1 {
		panic('invalid mask dimensions')
	}
	mut coverage_buffer := Z2dSparseCoverageBuffer.init(u32(scanline_draw_width))
	scanline_start_x_scaled := scanline_start_x * z2d_multisample_scale
	scanline_draw_width_scaled := scanline_draw_width * z2d_multisample_scale

	y_breakpoints := z2d_breakpoints(&polygon)
	mut y_breakpoint_idx := -1
	for idx, y in y_breakpoints {
		if y >= start_scanline {
			y_breakpoint_idx = if idx > 0 { idx - 1 } else { 0 }
			break
		}
	}
	if y_breakpoint_idx < 0 {
		return
	}

	mut working_edges := []Z2dWorkingEdge{}
	for y in start_scanline .. end_scanline + 1 {
		y_scaled := y * z2d_multisample_scale
		for y_offset in 0 .. z2d_multisample_scale {
			y_scanline_scaled := y_scaled + y_offset
			if y_scanline_scaled >= y_breakpoints[y_breakpoint_idx] {
				working_edges = z2d_rescan_edges(&polygon, y_scanline_scaled)
				if y_breakpoint_idx < y_breakpoints.len - 1 {
					y_breakpoint_idx += 1
				}
			}
			filtered_edges := z2d_inc_sort_filter(mut working_edges, y_scanline_scaled)
			mut x_min := 0
			for edge_pair_idx in 0 .. filtered_edges.len / 2 {
				edge_pair_start := edge_pair_idx * 2
				start_x := if x_min > filtered_edges[edge_pair_start] - scanline_start_x_scaled {
					x_min
				} else {
					filtered_edges[edge_pair_start] - scanline_start_x_scaled
				}
				if start_x >= scanline_draw_width_scaled {
					break
				}
				end_x := clamp_int(filtered_edges[edge_pair_start + 1] - scanline_start_x_scaled, start_x, scanline_draw_width_scaled)
				fill_len := end_x - start_x
				if fill_len > 0 {
					z2d_add_multisample_span(mut coverage_buffer, u32(if start_x > 0 {
						start_x
					} else {
						0
					}), u32(fill_len))
				}
				x_min = end_x
			}
		}

		coverage_x_max := z2d_min_u32(coverage_buffer.len, coverage_buffer.capacity)
		mut coverage_x := u32(0)
		for coverage_x < coverage_x_max {
			x := int(coverage_x) + scanline_start_x
			coverage_raw, coverage_len_raw := coverage_buffer.get(coverage_x)
			coverage_value := clamp_int(int(coverage_raw), 0, coverage_full)
			coverage_len := z2d_min_u32(coverage_len_raw, u32(if sfc_width - x > 0 {
				sfc_width - x
			} else {
				0
			}))
			if coverage_value == coverage_full {
				z2d_composite_span(mut canvas, x, y, coverage_len, color, 255)
			} else if coverage_value > 0 {
				opacity := u8(clamp_int(coverage_value * alpha_scale - 1, 0, 255))
				z2d_composite_span(mut canvas, x, y, coverage_len, color, opacity)
			}
			coverage_x += coverage_len
		}
		coverage_buffer.reset()
	}
}
