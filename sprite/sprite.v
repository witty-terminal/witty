module sprite

// This file contains the Canvas type and common helper types
// and functions for drawing sprite font glyphs. These are
// generally applicable to multiple sets of glyphs rather than
// being single-use.
//
// Translated from:
//   ghostty/src/font/sprite/Canvas.zig
//   ghostty/src/font/sprite/draw/common.zig
//   ghostty/src/font/sprite/draw/box.zig (Lines/linesChar/arc/dashes/diagonals)
//   ghostty/src/font/sprite/draw/block.zig (fill helpers)
//
// The original Ghostty Canvas is backed by the `z2d` 2D vector graphics
// library. Its required path and raster operations are translated in this
// module so Ghostty's Canvas behavior is preserved in V.

import gg.canvas as ggcanvas
import math
import sprite_types as font

// ============================================================
// Color
// ============================================================

// Color represents a pixel shade value used for sprite drawing.
// We only use the alpha channel, so a pixel is essentially "on"
// or "off", but intermediate shades are used for the block shade
// characters.
pub enum Color as u8 {
	off    = 0x00
	light_ = 0x40
	medium = 0x80
	dark   = 0xc0
	on     = 0xff
}

// ============================================================
// Point / Line / Rect types
// ============================================================

pub struct Point {
pub:
	x f64
	y f64
}

// Transformation is the affine translation applied by Ghostty's z2d-backed
// Canvas. Sprite paths only need the identity matrix plus the canvas padding,
// but retaining the complete value preserves Canvas.transformation's public
// source contract.
pub struct Transformation {
pub:
	ax f64
	by f64
	cx f64
	dy f64
	tx f64
	ty f64
}

pub struct LineSegment {
pub:
	p0 Point
	p1 Point
}

pub struct SpriteRect {
pub:
	x      i32
	y      i32
	width  i32
	height i32
}

// ============================================================
// Canvas
// ============================================================

// Canvas draws sprite font glyphs into a GG raster surface. The RGB channels
// stay zero and the alpha channel holds Ghostty's coverage value. Coordinates
// are cell-relative, with the padding applied internally.
pub struct Canvas {
pub mut:
	width       u32
	height      u32
	padding_x   u32
	padding_y   u32
	clip_top    u32
	clip_left   u32
	clip_right  u32
	clip_bottom u32
mut:
	surface ggcanvas.RasterSurface
}

// sfc_width returns the full surface width (including padding).
pub fn (c &Canvas) sfc_width() u32 {
	return u32(c.surface.width)
}

// sfc_height returns the full surface height (including padding).
pub fn (c &Canvas) sfc_height() u32 {
	return u32(c.surface.height)
}

// init creates a new Canvas with the given dimensions.
// We add padding to both sides (hence `2 *`).
pub fn Canvas.init(w u32, h u32, pad_x u32, pad_y u32) Canvas {
	width := int(w + 2 * pad_x)
	height := int(h + 2 * pad_y)
	surface := if width == 0 || height == 0 {
		ggcanvas.RasterSurface{
			width:  width
			height: height
		}
	} else {
		ggcanvas.new_raster_surface(width: width, height: height) or { panic(err) }
	}
	return Canvas{
		width:     w
		height:    h
		padding_x: pad_x
		padding_y: pad_y
		surface:   surface
	}
}

// deinit releases the canvas-owned raster. V's GC owns the backing storage,
// so dropping the final slice reference is the counterpart to z2d's allocator
// deinitialization.
pub fn (mut c Canvas) deinit() {
	c = Canvas{}
}

// transformation returns the padding translation used for every path.
pub fn (c &Canvas) transformation() Transformation {
	return Transformation{
		ax: 1
		by: 0
		cx: 0
		dy: 1
		tx: f64(c.padding_x)
		ty: f64(c.padding_y)
	}
}

// Draw and fill a single pixel. The coordinate is cell-relative;
// the padding offset is applied here. Out of bounds writes are
// silently ignored, matching z2d's `putPixel` behavior.
pub fn (mut c Canvas) pixel(x i32, y i32, color Color) {
	px := x + i32(c.padding_x)
	py := y + i32(c.padding_y)
	if px < 0 || py < 0 {
		return
	}
	w := i32(c.sfc_width())
	h := i32(c.sfc_height())
	if px >= w || py >= h {
		return
	}
	c.surface.pixels[py * w + px] = u32(color) << 24
}

// Draw and fill a rectangle. This is the main primitive for drawing
// lines as well (which are just generally skinny rectangles).
pub fn (mut c Canvas) rect(v SpriteRect, color Color) {
	// Clip before iterating so margins and off-canvas glyph shapes do not
	// require a bounds check for each covered pixel.
	left := i64(v.x) + i64(c.padding_x)
	top := i64(v.y) + i64(c.padding_y)
	x0 := int(math.max(i64(0), left))
	y0 := int(math.max(i64(0), top))
	x1 := int(math.min(i64(c.surface.width), left + v.width))
	y1 := int(math.min(i64(c.surface.height), top + v.height))
	if x0 >= x1 || y0 >= y1 {
		return
	}
	pixel := u32(color) << 24
	for y in y0 .. y1 {
		row := y * c.surface.width
		for x in x0 .. x1 {
			c.surface.pixels[row + x] = pixel
		}
	}
}

// Convenience wrapper for `Canvas.rect`, taking two corners.
// The corners may be given in any order.
pub fn (mut c Canvas) box(x0 i32, y0 i32, x1 i32, y1 i32, color Color) {
	tl_x := if x0 < x1 { x0 } else { x1 }
	tl_y := if y0 < y1 { y0 } else { y1 }
	br_x := if x0 > x1 { x0 } else { x1 }
	br_y := if y0 > y1 { y0 } else { y1 }
	c.rect(SpriteRect{
		x:      tl_x
		y:      tl_y
		width:  br_x - tl_x
		height: br_y - tl_y
	}, color)
}

// Stroke a line of the given thickness.
pub fn (mut c Canvas) line(l LineSegment, thickness f64, color Color) ! {
	mut path := c.static_path(2)
	path.move_to(l.p0.x, l.p0.y)
	path.line_to(l.p1.x, l.p1.y)
	c.stroke_path(path.wrapped_path, StrokeOptions{
		line_cap_mode: .butt
		line_width:    thickness
	}, color)!
}

// Draw and fill a quad.
pub fn (mut c Canvas) quad(q Quad, color Color) ! {
	mut path := c.static_path(6)
	path.move_to(q.p0.x, q.p0.y)
	path.line_to(q.p1.x, q.p1.y)
	path.line_to(q.p2.x, q.p2.y)
	path.line_to(q.p3.x, q.p3.y)
	path.close()
	c.fill_path(path.wrapped_path, FillOptions{}, color)!
}

// Draw and fill a triangle.
pub fn (mut c Canvas) triangle(t Triangle, color Color) ! {
	mut path := c.static_path(5)
	path.move_to(t.p0.x, t.p0.y)
	path.line_to(t.p1.x, t.p1.y)
	path.line_to(t.p2.x, t.p2.y)
	path.close()
	c.fill_path(path.wrapped_path, FillOptions{}, color)!
}

// static_path creates a StaticPath for vector path operations.
// Use this function instead of making the path manually since it
// ensures that the padding transformation is applied.
pub fn (mut c Canvas) static_path(max_nodes int) StaticPath {
	return StaticPath{
		canvas: unsafe { &c }
		nodes:  []PathNode{cap: max_nodes}
	}
}

// get_context returns a drawing context for the canvas.
pub fn (mut c Canvas) get_context() Context {
	return Context{
		canvas:     unsafe { &c }
		line_width: 2.0
	}
}

// Invert all pixels on the canvas.
pub fn (mut c Canvas) invert() {
	for i, pixel in c.surface.pixels {
		c.surface.pixels[i] = (u32(255) - (pixel >> 24)) << 24
	}
}

// Only really useful for test purposes, since the clipping region is
// automatically excluded when the rasterized glyph is written to an atlas.
pub fn (mut c Canvas) clear_clipping_regions() {
	width := c.sfc_width()
	height := c.sfc_height()

	for y in 0 .. height {
		for x in 0 .. c.clip_left {
			c.surface.pixels[y * width + x] = 0
		}
	}

	for y in 0 .. height {
		for x in width - c.clip_right .. width {
			c.surface.pixels[y * width + x] = 0
		}
	}

	for y in 0 .. c.clip_top {
		for x in 0 .. width {
			c.surface.pixels[y * width + x] = 0
		}
	}

	for y in height - c.clip_bottom .. height {
		for x in 0 .. width {
			c.surface.pixels[y * width + x] = 0
		}
	}
}

// Mirror the canvas horizontally.
pub fn (mut c Canvas) flip_horizontal() {
	w := int(c.sfc_width())
	h := int(c.sfc_height())
	for y in 0 .. h {
		for x in 0 .. w / 2 {
			left := y * w + x
			right := y * w + w - x - 1
			c.surface.pixels[left], c.surface.pixels[right] = c.surface.pixels[right], c.surface.pixels[left]
		}
	}
	c.clip_left, c.clip_right = c.clip_right, c.clip_left
}

// Mirror the canvas vertically.
pub fn (mut c Canvas) flip_vertical() {
	w := int(c.sfc_width())
	h := int(c.sfc_height())
	for y in 0 .. h / 2 {
		for x in 0 .. w {
			top := y * w + x
			bottom := (h - y - 1) * w + x
			c.surface.pixels[top], c.surface.pixels[bottom] = c.surface.pixels[bottom], c.surface.pixels[top]
		}
	}
	c.clip_top, c.clip_bottom = c.clip_bottom, c.clip_top
}

// Adjust clip boundaries to trim off any fully transparent rows or columns.
fn (mut c Canvas) trim() {
	width := c.sfc_width()
	height := c.sfc_height()

	// top
	for c.clip_top < height - c.clip_bottom {
		y := c.clip_top
		x0 := c.clip_left
		x1 := width - c.clip_right
		mut found := false
		for x in x0 .. x1 {
			if c.surface.pixels[y * width + x] != 0 {
				found = true
				break
			}
		}
		if found {
			break
		}
		c.clip_top += 1
	}

	// bottom
	for c.clip_bottom < height - c.clip_top {
		y := sat_sub(height - c.clip_bottom, 1)
		x0 := c.clip_left
		x1 := width - c.clip_right
		mut found := false
		for x in x0 .. x1 {
			if c.surface.pixels[y * width + x] != 0 {
				found = true
				break
			}
		}
		if found {
			break
		}
		c.clip_bottom += 1
	}

	// left
	for c.clip_left < width - c.clip_right {
		x := c.clip_left
		y0 := c.clip_top
		y1 := height - c.clip_bottom
		mut found := false
		for y in y0 .. y1 {
			if c.surface.pixels[y * width + x] != 0 {
				found = true
				break
			}
		}
		if found {
			break
		}
		c.clip_left += 1
	}

	// right
	for c.clip_right < width - c.clip_left {
		x := sat_sub(width - c.clip_right, 1)
		y0 := c.clip_top
		y1 := height - c.clip_bottom
		mut found := false
		for y in y0 .. y1 {
			if c.surface.pixels[y * width + x] != 0 {
				found = true
				break
			}
		}
		if found {
			break
		}
		c.clip_right += 1
	}
}

// sat_sub is a saturating subtraction for u32 (matches Zig's `-|`).
fn sat_sub(a u32, b u32) u32 {
	return if a > b { a - b } else { u32(0) }
}

// sat_add is a saturating addition for u32 (matches Zig's `+|`).
fn sat_add(a u32, b u32) u32 {
	return if b > u32(0xffff_ffff) - a { u32(0xffff_ffff) } else { a + b }
}

// write_atlas trims this drawing and stores its coverage in a grayscale atlas.
pub fn (mut c Canvas) write_atlas[T](mut atlas T) !font.AtlasRegion {
	return c.rasterize().write_atlas(mut atlas)
}

// rasterize trims transparent margins and exports the alpha mask with the
// clipped rectangle. The atlas stores one byte of coverage per pixel.
pub fn (mut c Canvas) rasterize() RasterizedGlyph {
	c.trim()

	sfc_width := c.sfc_width()
	sfc_height := c.sfc_height()

	// Subtract our clip margins from the width and height to
	// get the region size (saturating, matching Zig's `-|`).
	region_width := sat_sub(sat_sub(sfc_width, c.clip_left), c.clip_right)
	region_height := sat_sub(sat_sub(sfc_height, c.clip_top), c.clip_bottom)

	mut mask := []u8{len: c.surface.pixels.len}
	for i, pixel in c.surface.pixels {
		mask[i] = u8(pixel >> 24)
	}
	return RasterizedGlyph{
		data:       mask
		data_width: sfc_width
		source_x:   c.clip_left
		source_y:   c.clip_top
		width:      region_width
		height:     region_height
	}
}

pub struct RasterizedGlyph {
pub:
	data       []u8
	data_width u32
	source_x   u32
	source_y   u32
	width      u32
	height     u32
}

// write_atlas stores the clipped mask. The atlas type is supplied by the
// caller so sprite can remain independent of the font module.
pub fn (r &RasterizedGlyph) write_atlas[T](mut atlas T) !font.AtlasRegion {
	assert atlas.format.depth() == 1
	region := atlas.reserve(r.width, r.height)!
	if region.width > 0 && region.height > 0 {
		atlas.set_from_larger(region, r.data, r.data_width, r.source_x, r.source_y)
	}
	return region
}

// ============================================================
// Path types
// ============================================================

// A tagged union of all path node types.
pub enum PathNodeTag as u8 {
	move_to
	line_to
	curve_to
	close_path
}

pub type PathNode = PathClose | PathCurveTo | PathLineTo | PathMoveTo

// The tag of the active path node variant.
pub fn (self PathNode) tag() PathNodeTag {
	return match self {
		PathMoveTo { .move_to }
		PathLineTo { .line_to }
		PathCurveTo { .curve_to }
		PathClose { .close_path }
	}
}

// Represents a moveto path node. This starts a new subpath and moves the
// current point to (x, y).
pub struct PathMoveTo {
pub:
	point Point
}

// Represents a lineto path node. This draws a line to (x, y) and sets it as
// its current point.
pub struct PathLineTo {
pub:
	point Point
}

// Represents a curveto path node. This draws a cubic bezier with the three
// supplied control points from the current point. The new current point is
// set to p3.
pub struct PathCurveTo {
pub:
	p1 Point
	p2 Point
	p3 Point
}

// Represents a closepath node.
pub struct PathClose {}

pub struct Path {
pub:
	nodes []PathNode
}

pub struct FillOptions {}

pub enum LineCapMode as u8 {
	butt
	round_
	square
}

pub struct StrokeOptions {
pub:
	line_cap_mode LineCapMode = .butt
	line_width    f64         = 2.0
}

// StaticPath is a fixed-capacity path builder. It mirrors z2d's
// `StaticPath` including the automatic transform (padding offset)
// applied to every coordinate.
pub struct StaticPath {
pub mut:
	canvas        &Canvas = unsafe { nil }
	nodes         []PathNode
	wrapped_path  Path
	initial_point ?Point
	current_point ?Point
}

// z2d stores path coordinates in its Cairo-compatible signed 24-bit range.
fn clamp_i24(value f64) f64 {
	return math.clamp(value, -8388608.0, 8388607.0)
}

// px/py apply the padding transformation to a coordinate, matching
// z2d's `wrapped_path.transformation` set in `Canvas.staticPath`.
fn (p &StaticPath) tx(x f64) f64 {
	return clamp_i24(x) + p.canvas.transformation().tx
}

fn (p &StaticPath) ty(y f64) f64 {
	return clamp_i24(y) + p.canvas.transformation().ty
}

// move_to adds a move-to node.
pub fn (mut p StaticPath) move_to(x f64, y f64) {
	point := Point{ x: p.tx(x), y: p.ty(y) }
	if p.nodes.len > 0 {
		last := p.nodes.last()
		if last is PathMoveTo && points_equal(last.point, point) {
			return
		}
	}
	p.nodes << PathMoveTo{
		point: point
	}
	p.initial_point = point
	p.current_point = point
	p.wrapped_path = Path{
		nodes: p.nodes
	}
}

// line_to adds a line-to node.
pub fn (mut p StaticPath) line_to(x f64, y f64) {
	if p.current_point == none {
		p.move_to(x, y)
		return
	}
	p.nodes << PathLineTo{
		point: Point{ x: p.tx(x), y: p.ty(y) }
	}
	p.current_point = Point{ x: p.tx(x), y: p.ty(y) }
	p.wrapped_path = Path{
		nodes: p.nodes
	}
}

// curve_to adds a cubic Bezier curve node with the two control points
// (c1, c2) and the end point (x, y). Matches z2d `path.curveTo`.
pub fn (mut p StaticPath) curve_to(c1x f64, c1y f64, c2x f64, c2y f64, x f64, y f64) {
	if p.current_point == none {
		panic('curve_to requires a current point')
	}
	p.nodes << PathCurveTo{
		p1: Point{ x: p.tx(c1x), y: p.ty(c1y) }
		p2: Point{ x: p.tx(c2x), y: p.ty(c2y) }
		p3: Point{ x: p.tx(x), y: p.ty(y) }
	}
	p.current_point = Point{ x: p.tx(x), y: p.ty(y) }
	p.wrapped_path = Path{
		nodes: p.nodes
	}
}

// close closes the current path.
//
pub fn (mut p StaticPath) close() {
	if p.current_point == none {
		return
	}
	p.nodes << PathClose{}
	initial := p.initial_point or { return }
	p.nodes << PathMoveTo{
		point: initial
	}
	p.wrapped_path = Path{
		nodes: p.nodes
	}
}

// z2d's default maximum error tolerance for spline decomposition.
const default_tolerance = 0.1

// decompose_spline is z2d v0.10.0's internal/tess/Spline.zig decomposition.
// It adaptively subdivides a cubic Bezier using the same error bound rather
// than choosing an unrelated fixed number of segments.
fn decompose_spline(a Point, b Point, c Point, d Point, tolerance f64) []Point {
	if points_equal(a, b) && points_equal(c, d) {
		return [d]
	}
	mut result := []Point{}
	mut knots := SplineKnots{
		a: a
		b: b
		c: c
		d: d
	}
	decompose_spline_into(mut result, mut knots, a, tolerance * tolerance)
	result << d
	return result
}

fn decompose_spline_into(mut result []Point, mut knots SplineKnots, start Point, tolerance f64) {
	if knots.error_sq() < tolerance {
		if !points_equal(knots.a, start) {
			result << knots.a
		}
		return
	}

	mut second := knots.de_casteljau()
	decompose_spline_into(mut result, mut knots, start, tolerance)
	decompose_spline_into(mut result, mut second, start, tolerance)
}

struct SplineKnots {
mut:
	a Point
	b Point
	c Point
	d Point
}

// error_sq returns z2d's upper bound on the squared error from replacing this
// spline with the line segment joining its endpoints.
fn (knots SplineKnots) error_sq() f64 {
	mut b_x_delta := knots.b.x - knots.a.x
	mut b_y_delta := knots.b.y - knots.a.y
	mut c_x_delta := knots.c.x - knots.a.x
	mut c_y_delta := knots.c.y - knots.a.y

	if knots.a.x != knots.d.x || knots.a.y != knots.d.y {
		d_x_delta := knots.d.x - knots.a.x
		d_y_delta := knots.d.y - knots.a.y
		d_dot_sq := dot_sq(d_x_delta, d_y_delta)

		b_d_dot := b_x_delta * d_x_delta + b_y_delta * d_y_delta
		if b_d_dot >= d_dot_sq {
			b_x_delta -= d_x_delta
			b_y_delta -= d_y_delta
		} else {
			b_x_delta -= b_d_dot / d_dot_sq * d_x_delta
			b_y_delta -= b_d_dot / d_dot_sq * d_y_delta
		}

		c_d_dot := c_x_delta * d_x_delta + c_y_delta * d_y_delta
		if c_d_dot >= d_dot_sq {
			c_x_delta -= d_x_delta
			c_y_delta -= d_y_delta
		} else {
			c_x_delta -= c_d_dot / d_dot_sq * d_x_delta
			c_y_delta -= c_d_dot / d_dot_sq * d_y_delta
		}
	}

	b_error := dot_sq(b_x_delta, b_y_delta)
	c_error := dot_sq(c_x_delta, c_y_delta)
	return if b_error > c_error { b_error } else { c_error }
}

// de_casteljau mutates this knot to the first half and returns the second.
fn (mut knots SplineKnots) de_casteljau() SplineKnots {
	ab := lerp_half(knots.a, knots.b)
	bc := lerp_half(knots.b, knots.c)
	cd := lerp_half(knots.c, knots.d)
	abbc := lerp_half(ab, bc)
	bccd := lerp_half(bc, cd)
	final := lerp_half(abbc, bccd)

	result := SplineKnots{
		a: final
		b: bccd
		c: cd
		d: knots.d
	}
	knots.b = ab
	knots.c = abbc
	knots.d = final
	return result
}

fn dot_sq(x f64, y f64) f64 {
	return x * x + y * y
}

fn lerp_half(a Point, b Point) Point {
	return Point{
		x: a.x + (b.x - a.x) / 2.0
		y: a.y + (b.y - a.y) / 2.0
	}
}

// fill_path fills a closed path using the non-zero winding rule, with
// z2d's default 4x multisample anti-aliasing. This is the workhorse used by
// `fill`, `quad`, `triangle`, and Context.fill.
pub fn (mut c Canvas) fill_path(path Path, opts FillOptions, color Color) ! {
	_ = opts
	if path.nodes.len == 0 {
		return
	}
	if !path_nodes_closed(path.nodes) {
		return error('path not closed')
	}
	polygon := z2d_fill_plot(path, z2d_multisample_scale, default_tolerance)!
	z2d_multisample_fill(mut c, polygon, color)
}

fn path_nodes_closed(nodes []PathNode) bool {
	if nodes.len == 0 {
		return false
	}
	mut closed := false
	for i, node in nodes {
		match node {
			PathMoveTo {
				if !closed && i != 0 {
					break
				}
			}
			PathClose {
				closed = true
			}
			else {
				closed = false
			}
		}
	}
	return closed
}

// ============================================================
// Path stroking
// ============================================================

// stroke_path strokes the given (open or closed) path with z2d's tessellator.
pub fn (mut c Canvas) stroke_path(path Path, opts StrokeOptions, color Color) ! {
	if path.nodes.len == 0 {
		return
	}
	polygon := z2d_stroke_plot(path, opts)!
	z2d_multisample_fill(mut c, polygon, color)
}

// inner_stroke_path strokes only the portion of a path that lies inside
// the shape produced by closing it. Ghostty uses the same two-surface mask
// technique around z2d; the V renderer performs that alpha multiplication
// directly on two temporary canvases.
pub fn (mut c Canvas) inner_stroke_path(path Path, opts StrokeOptions, color Color) ! {
	mut closed_nodes := path.nodes.clone()
	closed_nodes << PathClose{}
	if path.nodes.len > 0 {
		for node in path.nodes {
			if node is PathMoveTo {
				closed_nodes << node
				break
			}
		}
	}

	mut fill_canvas := Canvas.init(c.width, c.height, c.padding_x, c.padding_y)
	fill_canvas.fill_path(Path{ nodes: closed_nodes }, FillOptions{}, .on)!

	mut stroke_canvas := Canvas.init(c.width, c.height, c.padding_x, c.padding_y)
	stroke_canvas.stroke_path(path, StrokeOptions{
		line_cap_mode: opts.line_cap_mode
		line_width:    opts.line_width * 2.0
	}, color)!

	for i, pixel in c.surface.pixels {
		fill := fill_canvas.surface.pixels[i] >> 24
		stroke := stroke_canvas.surface.pixels[i] >> 24
		src := u32(math.round(f64(fill) * f64(stroke) / 255.0))
		dst := pixel >> 24
		c.surface.pixels[i] = (src + dst - src * dst / 255) << 24
	}
}

fn points_equal(a Point, b Point) bool {
	return a.x == b.x && a.y == b.y
}

// ============================================================
// Context (for arc/circle drawing)
// ============================================================

// Context provides a higher-level, path-building drawing interface,
// mirroring z2d's `Context`. Coordinates are cell-relative; the
// padding transform is applied through the underlying StaticPath.
pub struct Context {
pub mut:
	canvas        &Canvas     = unsafe { nil }
	line_width    f64         = 2.0
	line_cap_mode LineCapMode = .butt
	color         Color       = .on
	nodes         []PathNode
	// Tracks the current point for relative operations like `arc`.
	has_current bool
	cur_x       f64
	cur_y       f64
	start_x     f64
	start_y     f64
	has_start   bool
}

pub fn (mut ctx Context) deinit() {
	// no-op; nothing to free
}

// SourcePattern for setting the drawing source color.
pub struct SourcePattern {
pub:
	opaque_pattern OpaquePattern
}

pub struct OpaquePattern {
pub:
	pixel PixelUnion
}

pub struct PixelUnion {
pub:
	alpha8 Alpha8
}

pub struct Alpha8 {
pub:
	a u8
}

pub fn (mut ctx Context) set_source(source SourcePattern) {
	ctx.color = unsafe { Color(source.opaque_pattern.pixel.alpha8.a) }
}

pub fn (mut ctx Context) set_line_width(width f64) {
	ctx.line_width = width
}

fn (ctx &Context) tx(x f64) f64 {
	return clamp_i24(x) + f64(ctx.canvas.padding_x)
}

fn (ctx &Context) ty(y f64) f64 {
	return clamp_i24(y) + f64(ctx.canvas.padding_y)
}

pub fn (mut ctx Context) move_to(x f64, y f64) {
	point := Point{ x: ctx.tx(x), y: ctx.ty(y) }
	if ctx.nodes.len > 0 {
		last := ctx.nodes.last()
		if last is PathMoveTo && points_equal(last.point, point) {
			return
		}
	}
	ctx.nodes << PathMoveTo{
		point: point
	}
	ctx.cur_x = x
	ctx.cur_y = y
	ctx.start_x = x
	ctx.start_y = y
	ctx.has_current = true
	ctx.has_start = true
}

pub fn (mut ctx Context) line_to(x f64, y f64) {
	if !ctx.has_current {
		ctx.move_to(x, y)
		return
	}
	ctx.nodes << PathLineTo{
		point: Point{ x: ctx.tx(x), y: ctx.ty(y) }
	}
	ctx.cur_x = x
	ctx.cur_y = y
	ctx.has_current = true
}

pub fn (mut ctx Context) curve_to(c1x f64, c1y f64, c2x f64, c2y f64, x f64, y f64) ! {
	if !ctx.has_current {
		return error('curve_to requires a current point')
	}
	ctx.nodes << PathCurveTo{
		p1: Point{ x: ctx.tx(c1x), y: ctx.ty(c1y) }
		p2: Point{ x: ctx.tx(c2x), y: ctx.ty(c2y) }
		p3: Point{ x: ctx.tx(x), y: ctx.ty(y) }
	}
	ctx.cur_x = x
	ctx.cur_y = y
	ctx.has_current = true
}

// arc appends a circular arc using z2d v0.10.0's internal/arc.zig algorithm.
pub fn (mut ctx Context) arc(x f64, y f64, r f64, start_angle f64, end_angle f64) ! {
	mut effective_end := end_angle
	for effective_end < start_angle {
		effective_end += math.tau
	}
	z2d_arc_in_direction(mut ctx, x, y, r, start_angle, effective_end)!
}

fn z2d_arc_error_normalized(angle f64) f64 {
	sine := math.sin(angle / 4)
	cosine := math.cos(angle / 4)
	return 2.0 / 27.0 * math.pow(sine, 6) / math.pow(cosine, 2)
}

fn z2d_arc_max_angle_for_tolerance_normalized(tolerance f64) f64 {
	angles := [math.pi, math.pi / 2, math.pi / 3, math.pi / 4, math.pi / 5, math.pi / 6, math.pi / 7,
		math.pi / 8, math.pi / 9, math.pi / 10, math.pi / 11]
	errors := [0.0185185185185185036127, 0.000272567143730179811158, 2.38647043651461047433e-05,
		4.2455377443222443279e-06, 1.11281001494389081528e-06, 3.72662000942734705475e-07,
		1.47783685574284411325e-07, 6.63240432022601149057e-08, 3.2715520137536980553e-08,
		1.73863223499021216974e-08, 9.81410988043554039085e-09]
	for i, arc_error in errors {
		if arc_error < tolerance {
			return angles[i]
		}
	}
	mut angle := 0.0
	for i in angles.len .. 1000 {
		angle = math.pi / f64(i)
		if z2d_arc_error_normalized(angle) <= tolerance {
			break
		}
	}
	return angle
}

fn z2d_arc_segments_needed(angle f64, radius f64, tolerance f64) int {
	max_angle := z2d_arc_max_angle_for_tolerance_normalized(tolerance / radius)
	return int(math.ceil(math.abs(angle) / max_angle))
}

fn z2d_mod(value f64, modulus f64) f64 {
	result := math.fmod(value, modulus)
	return if result < 0 { result + modulus } else { result }
}

fn z2d_arc_segment(mut ctx Context, xc f64, yc f64, radius f64, angle_a f64, angle_b f64) ! {
	r_sin_a := radius * math.sin(angle_a)
	r_cos_a := radius * math.cos(angle_a)
	r_sin_b := radius * math.sin(angle_b)
	r_cos_b := radius * math.cos(angle_b)
	h := 4.0 / 3.0 * math.tan((angle_b - angle_a) / 4.0)
	ctx.curve_to(xc + r_cos_a - h * r_sin_a, yc + r_sin_a + h * r_cos_a, xc + r_cos_b + h * r_sin_b, yc + r_sin_b - h * r_cos_b, xc + r_cos_b, yc + r_sin_b)!
}

// Path.arc uses a line callback that suppresses an exact line to the current
// transformed point before handing the remaining arc to the path builder.
fn z2d_arc_line_to(mut ctx Context, x f64, y f64) {
	if ctx.has_current && ctx.tx(ctx.cur_x) == x && ctx.ty(ctx.cur_y) == y {
		return
	}
	ctx.line_to(x, y)
}

fn z2d_arc_in_direction(mut ctx Context, xc f64, yc f64, radius f64, angle_min f64, angle_max f64) ! {
	mut minimum := angle_min
	mut maximum := angle_max
	if !(maximum * maximum >= 0) || !(minimum * minimum >= 0) {
		return
	}
	if maximum - minimum > math.tau * 65536.0 {
		maximum = z2d_mod(maximum - minimum, math.tau)
		minimum = z2d_mod(minimum, math.tau)
		maximum += minimum + math.tau * 65536.0
	}
	if maximum - minimum > math.pi {
		middle := minimum + (maximum - minimum) / 2
		z2d_arc_in_direction(mut ctx, xc, yc, radius, minimum, middle)!
		z2d_arc_in_direction(mut ctx, xc, yc, radius, middle, maximum)!
	} else if maximum != minimum {
		mut segments := z2d_arc_segments_needed(maximum - minimum, radius, default_tolerance)
		step := (maximum - minimum) / f64(segments)
		segments -= 1
		z2d_arc_line_to(mut ctx, xc + radius * math.cos(minimum), yc + radius * math.sin(minimum))
		for _ in 0 .. segments {
			z2d_arc_segment(mut ctx, xc, yc, radius, minimum, minimum + step)!
			minimum += step
		}
		z2d_arc_segment(mut ctx, xc, yc, radius, minimum, maximum)!
	} else {
		z2d_arc_line_to(mut ctx, xc + radius * math.cos(minimum), yc + radius * math.sin(minimum))
	}
}

pub fn (mut ctx Context) close_path() ! {
	if !ctx.has_current {
		return
	}
	ctx.nodes << PathClose{}
	if ctx.has_start {
		ctx.nodes << PathMoveTo{
			point: Point{ x: ctx.tx(ctx.start_x), y: ctx.ty(ctx.start_y) }
		}
	}
}

pub fn (mut ctx Context) reset_path() {
	ctx.nodes = []PathNode{}
	ctx.has_current = false
	ctx.has_start = false
}

// fill fills the currently-built path with the context's source color.
pub fn (mut ctx Context) fill() ! {
	path := Path{
		nodes: ctx.nodes
	}
	ctx.canvas.fill_path(path, FillOptions{}, ctx.color)!
}

// stroke strokes the currently-built path with the context's source
// color and line width.
pub fn (mut ctx Context) stroke() ! {
	path := Path{
		nodes: ctx.nodes
	}
	ctx.canvas.stroke_path(path, StrokeOptions{
		line_cap_mode: ctx.line_cap_mode
		line_width:    ctx.line_width
	}, ctx.color)!
}

// ============================================================
// Triangle / Quad geometry
// ============================================================

pub struct Triangle {
pub:
	p0 Point
	p1 Point
	p2 Point
}

pub struct Quad {
pub:
	p0 Point
	p1 Point
	p2 Point
	p3 Point
}

// ============================================================
// Thickness
// ============================================================

// The thickness of a line.
pub enum Thickness as u8 {
	super_light
	light
	heavy
}

// Calculate the real height of a line based on its
// thickness and a base thickness value. The base
// thickness value is expected to be in pixels.
pub fn (t Thickness) height(base u32) u32 {
	return match t {
		.super_light {
			if base / 2 > 1 { base / 2 } else { u32(1) }
		}
		.light { base }
		.heavy { base * 2 }
	}
}

// ============================================================
// Shade
// ============================================================

// Shades.
pub enum Shade as u8 {
	off    = 0x00
	light_ = 0x40
	medium = 0x80
	dark   = 0xc0
	on     = 0xff
}

// ============================================================
// Quads
// ============================================================

// Applicable to any set of glyphs with features
// that may be present or not in each quadrant.
const quad_tl = u8(1 << 0)
const quad_tr = u8(1 << 1)
const quad_bl = u8(1 << 2)
const quad_br = u8(1 << 3)
const quads_mask = u8(0x0f)

pub struct Quads {
	value u8
}

pub fn Quads.from_int(value u8) Quads {
	assert value & ~quads_mask == 0
	return Quads{
		value: value
	}
}

pub fn (quads Quads) tl() bool {
	return quads.value & quad_tl != 0
}

pub fn (quads Quads) tr() bool {
	return quads.value & quad_tr != 0
}

pub fn (quads Quads) bl() bool {
	return quads.value & quad_bl != 0
}

pub fn (quads Quads) br() bool {
	return quads.value & quad_br != 0
}

// ============================================================
// Corner
// ============================================================

// A corner of a cell.
pub enum Corner as u8 {
	tl
	tr
	bl
	br
}

// ============================================================
// Edge
// ============================================================

// An edge of a cell.
pub enum Edge as u8 {
	top
	left
	bottom
	right
}

// ============================================================
// HorizontalAlignment / VerticalAlignment / Alignment
// ============================================================

pub enum HorizontalAlignment as u8 {
	left
	right
	center
}

pub enum VerticalAlignment as u8 {
	top
	bottom
	middle
}

// Alignment of a figure within a cell.
pub struct Alignment {
pub:
	horizontal HorizontalAlignment = .center
	vertical   VerticalAlignment   = .middle
}

// Named alignment constants.
pub const align_upper = Alignment{
	vertical: .top
}
pub const align_lower = Alignment{
	vertical: .bottom
}
pub const align_left = Alignment{
	horizontal: .left
}
pub const align_right = Alignment{
	horizontal: .right
}
pub const align_upper_left = Alignment{
	vertical:   .top
	horizontal: .left
}
pub const align_upper_right = Alignment{
	vertical:   .top
	horizontal: .right
}
pub const align_lower_left = Alignment{
	vertical:   .bottom
	horizontal: .left
}
pub const align_lower_right = Alignment{
	vertical:   .bottom
	horizontal: .right
}
pub const align_center = Alignment{}
pub const align_upper_center = align_upper
pub const align_lower_center = align_lower
pub const align_middle_left = align_left
pub const align_middle_right = align_right
pub const align_middle_center = align_center
pub const align_top = align_upper
pub const align_bottom = align_lower
pub const align_center_top = align_top
pub const align_center_bottom = align_bottom
pub const align_top_left = align_upper_left
pub const align_top_right = align_upper_right
pub const align_bottom_left = align_lower_left
pub const align_bottom_right = align_lower_right

// ============================================================
// Fraction
// ============================================================

// A value that indicates some fraction across
// the cell either horizontally or vertically.
//
// This has some redundant names in it so that you can
// use whichever one feels most semantically appropriate.
pub enum Fraction as u8 {
	// Names for the min edge
	start
	left
	top
	zero
	// Names based on eighths
	eighth
	one_eighth
	two_eighths
	three_eighths
	four_eighths
	five_eighths
	six_eighths
	seven_eighths
	// Names based on quarters
	quarter
	one_quarter
	two_quarters
	three_quarters
	// Names based on thirds
	third
	one_third
	two_thirds
	// Names based on halves
	half_
	one_half
	// Alternative names for 1/2
	center
	middle
	// Names for the max edge
	end_
	right
	bottom
	one
	full
}

// This can be indexed to get the fraction for i/8.
pub const fraction_eighths = [Fraction.zero, .one_eighth, .two_eighths, .three_eighths, .four_eighths,
	.five_eighths, .six_eighths, .seven_eighths, .one]

// This can be indexed to get the fraction for i/4.
pub const fraction_quarters = [Fraction.zero, .one_quarter, .two_quarters, .three_quarters, .one]

// This can be indexed to get the fraction for i/3.
pub const fraction_thirds = [Fraction.zero, .one_third, .two_thirds, .one]

// This can be indexed to get the fraction for i/2.
pub const fraction_halves = [Fraction.zero, .one_half, .one]

// Get a float for the fraction this represents.
pub fn (f Fraction) fraction() f64 {
	return match f {
		.start, .left, .top, .zero { 0.0 }
		.eighth, .one_eighth { 0.125 }
		.quarter, .one_quarter, .two_eighths { 0.25 }
		.third, .one_third { 1.0 / 3.0 }
		.three_eighths { 0.375 }
		.half_, .one_half, .two_quarters, .four_eighths, .center, .middle { 0.5 }
		.five_eighths { 0.625 }
		.two_thirds { 2.0 / 3.0 }
		.three_quarters, .six_eighths { 0.75 }
		.seven_eighths { 0.875 }
		.end_, .right, .bottom, .one, .full { 1.0 }
	}
}

// Get the x position for this fraction across a particular
// size (width or height), assuming it will be used as the
// min (left/top) coordinate for a block.
//
// For min coordinates, we want to align with the complementary
// fraction taken from the end, this ensures that rounding evens
// out, so that for example, if size is 7, and we're looking
// at the half line, size - round((1 - 0.5) * size) => 3;
// whereas the max coordinate directly rounds, which means that
// both start -> half and half -> end will be 4px, from
// 0 -> 4 and 3 -> 7.
pub fn (f Fraction) min(size u32) i32 {
	s := f64(size)
	return int(s - math.round((1.0 - f.fraction()) * s))
}

// Get the x position for this fraction across a particular
// size (width or height), assuming it will be used as the
// max (right/bottom) coordinate for a block.
pub fn (f Fraction) max(size u32) i32 {
	s := f64(size)
	return int(math.round(f.fraction() * s))
}

// Get this fraction across a particular size (width/height).
// If you need an integer, use min or max instead, since
// they contain special logic for consistent alignment. This
// is for when you're drawing with paths and don't care about
// pixel alignment.
pub fn (f Fraction) float(size u32) f64 {
	return f.fraction() * f64(size)
}

// ============================================================
// Utility names for common fractions
// ============================================================

pub const one_eighth_f = f64(0.125)
pub const one_quarter_f = f64(0.25)
pub const one_third_f = 1.0 / 3.0
pub const three_eighths_f = f64(0.375)
pub const half_f = f64(0.5)
pub const five_eighths_f = f64(0.625)
pub const two_thirds_f = 2.0 / 3.0
pub const three_quarters_f = f64(0.75)
pub const seven_eighths_f = f64(0.875)

// ============================================================
// fill function
// ============================================================

// Fill a section of the cell, specified by a
// horizontal and vertical pair of fraction lines.
pub fn fill(metrics font.Metrics, mut canvas Canvas, x0 Fraction, x1 Fraction, y0 Fraction, y1 Fraction) {
	canvas.box(x0.min(metrics.cell_width), y0.min(metrics.cell_height), x1.max(metrics.cell_width), y1.max(metrics.cell_height), .on)
}

// ============================================================
// Helper line functions from common.zig
// ============================================================

// Centered vertical line of the provided thickness.
pub fn vline_middle(metrics font.Metrics, mut canvas Canvas, thickness Thickness) {
	thick_px := thickness.height(metrics.box_thickness)
	vline(mut canvas, 0, i32(metrics.cell_height), i32(sat_sub(metrics.cell_width, thick_px) / 2), thick_px)
}

// Centered horizontal line of the provided thickness.
pub fn hline_middle(metrics font.Metrics, mut canvas Canvas, thickness Thickness) {
	thick_px := thickness.height(metrics.box_thickness)
	hline(mut canvas, 0, i32(metrics.cell_width), i32(sat_sub(metrics.cell_height, thick_px) / 2), thick_px)
}

// Vertical line with the left edge at x, between y1 and y2.
pub fn vline(mut canvas Canvas, y1 i32, y2 i32, x i32, thickness_px u32) {
	canvas.box(x, y1, x + i32(thickness_px), y2, .on)
}

// Horizontal line with the top edge at y, between x1 and x2.
pub fn hline(mut canvas Canvas, x1 i32, x2 i32, y i32, thickness_px u32) {
	canvas.box(x1, y, x2, y + i32(thickness_px), .on)
}

// ============================================================
// Lines struct (for box-drawing line styles)
// ============================================================

pub enum LineStyle as u8 {
	none_
	light
	heavy
	double_
}

pub struct Lines {
	value u8
}

pub fn Lines.from_int(value u8) Lines {
	return Lines{
		value: value
	}
}

pub fn (lines Lines) up() LineStyle {
	return unsafe { LineStyle((lines.value >> 0) & 0x03) }
}

pub fn (lines Lines) right() LineStyle {
	return unsafe { LineStyle((lines.value >> 2) & 0x03) }
}

pub fn (lines Lines) down() LineStyle {
	return unsafe { LineStyle((lines.value >> 4) & 0x03) }
}

pub fn (lines Lines) left() LineStyle {
	return unsafe { LineStyle((lines.value >> 6) & 0x03) }
}

// ============================================================
// block fill helpers (from block.zig)
// ============================================================

// block_fill fills a block at the given alignment with fractional
// width and height relative to the cell.
pub fn block_fill(metrics font.Metrics, mut canvas Canvas, alignment Alignment, bwidth f64, bheight f64) {
	block_shade(metrics, mut canvas, alignment, bwidth, bheight, .on)
}

// block_shade fills a block at the given alignment with a shade pattern.
pub fn block_shade(metrics font.Metrics, mut canvas Canvas, alignment Alignment, bwidth f64, bheight f64, shade Shade) {
	float_width := f64(metrics.cell_width)
	float_height := f64(metrics.cell_height)

	w := u32(math.round(float_width * bwidth))
	h := u32(math.round(float_height * bheight))

	x := match alignment.horizontal {
		.left { u32(0) }
		.right { metrics.cell_width - w }
		.center { (metrics.cell_width - w) / 2 }
	}
	y := match alignment.vertical {
		.top { u32(0) }
		.bottom { metrics.cell_height - h }
		.middle { (metrics.cell_height - h) / 2 }
	}

	canvas.rect(SpriteRect{
		x:      i32(x)
		y:      i32(y)
		width:  i32(w)
		height: i32(h)
	}, unsafe { Color(u8(shade)) })
}

// full_block_shade fills the entire cell with a shade pattern.
pub fn full_block_shade(metrics font.Metrics, mut canvas Canvas, shade Shade) {
	canvas.box(0, 0, i32(metrics.cell_width), i32(metrics.cell_height), unsafe { Color(u8(shade)) })
}
