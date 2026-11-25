module sprite

// Powerline + Powerline Extra Symbols | U+E0B0...U+E0D4
// https://github.com/ryanoasis/powerline-extra-symbols
//
//
//
//
//
// We implement the more geometric glyphs here, but not the stylized ones.
//
// Translated from ghostty/src/font/sprite/draw/powerline.zig

import sprite_types as font
import math

//
pub fn draw_e0b0(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = metrics
	float_width := f64(width)
	float_height := f64(height)
	canvas.triangle(Triangle{
		p0: Point{ x: 0, y: 0 }
		p1: Point{ x: float_width, y: float_height / 2 }
		p2: Point{ x: 0, y: float_height }
	}, .on)!
}

//
pub fn draw_e0b2(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = metrics
	float_width := f64(width)
	float_height := f64(height)
	canvas.triangle(Triangle{
		p0: Point{ x: float_width, y: 0 }
		p1: Point{ x: 0, y: float_height / 2 }
		p2: Point{ x: float_width, y: float_height }
	}, .on)!
}

//
pub fn draw_e0b8(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = metrics
	float_width := f64(width)
	float_height := f64(height)
	canvas.triangle(Triangle{
		p0: Point{ x: 0, y: 0 }
		p1: Point{ x: float_width, y: float_height }
		p2: Point{ x: 0, y: float_height }
	}, .on)!
}

//
pub fn draw_e0b9(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = width
	_ = height
	light_diagonal_upper_left_to_lower_right(metrics, mut canvas)
}

//
pub fn draw_e0ba(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = metrics
	float_width := f64(width)
	float_height := f64(height)
	canvas.triangle(Triangle{
		p0: Point{ x: float_width, y: 0 }
		p1: Point{ x: float_width, y: float_height }
		p2: Point{ x: 0, y: float_height }
	}, .on)!
}

//
pub fn draw_e0bb(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = width
	_ = height
	light_diagonal_upper_right_to_lower_left(metrics, mut canvas)
}

//
pub fn draw_e0bc(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = metrics
	float_width := f64(width)
	float_height := f64(height)
	canvas.triangle(Triangle{
		p0: Point{ x: 0, y: 0 }
		p1: Point{ x: float_width, y: 0 }
		p2: Point{ x: 0, y: float_height }
	}, .on)!
}

//
pub fn draw_e0bd(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = width
	_ = height
	light_diagonal_upper_right_to_lower_left(metrics, mut canvas)
}

//
pub fn draw_e0be(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = metrics
	float_width := f64(width)
	float_height := f64(height)
	canvas.triangle(Triangle{
		p0: Point{ x: 0, y: 0 }
		p1: Point{ x: float_width, y: 0 }
		p2: Point{ x: float_width, y: float_height }
	}, .on)!
}

//
pub fn draw_e0bf(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = width
	_ = height
	light_diagonal_upper_left_to_lower_right(metrics, mut canvas)
}

//
pub fn draw_e0b1(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	float_width := f64(width)
	float_height := f64(height)

	mut path := canvas.static_path(3)
	path.move_to(0, 0)
	path.line_to(float_width, float_height / 2)
	path.line_to(0, float_height)

	canvas.stroke_path(path.wrapped_path, StrokeOptions{
		line_cap_mode: .butt
		line_width: f64(Thickness.light.height(metrics.box_thickness))
	}, .on)!
}

//
pub fn draw_e0b3(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	draw_e0b1(cp, mut canvas, width, height, metrics)!
	canvas.flip_horizontal()
}

//
pub fn draw_e0b4(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp
	_ = metrics

	float_width := f64(width)
	float_height := f64(height)

	// Coefficient for approximating a circular arc.
	c := (math.sqrt2 - 1.0) * 4.0 / 3.0
	radius := math.min(float_width, float_height / 2)

	mut path := canvas.static_path(6)
	path.move_to(0, 0)
	path.curve_to(radius * c, 0, radius, radius - radius * c, radius, radius)
	path.line_to(radius, float_height - radius)
	path.curve_to(radius, float_height - radius + radius * c, radius * c, float_height, 0, float_height)
	path.close()

	canvas.fill_path(path.wrapped_path, FillOptions{}, .on)!
}

//
pub fn draw_e0b5(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp

	float_width := f64(width)
	float_height := f64(height)

	// Coefficient for approximating a circular arc.
	c := (math.sqrt2 - 1.0) * 4.0 / 3.0
	radius := math.min(float_width, float_height / 2)

	// Horizontal endpoint segments keep the inset stroke's butt caps square.
	mut path := canvas.static_path(6)
	path.move_to(0, 0)
	path.line_to(1, 0)
	path.curve_to(radius * c, 0, radius, radius - radius * c, radius, radius)
	path.line_to(radius, float_height - radius)
	path.curve_to(radius, float_height - radius + radius * c, radius * c, float_height, 1, float_height)
	path.line_to(0, float_height)

	canvas.inner_stroke_path(path.wrapped_path, StrokeOptions{
		line_width: f64(metrics.box_thickness)
		line_cap_mode: .butt
	}, .on)!
}

//
pub fn draw_e0b6(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	draw_e0b4(cp, mut canvas, width, height, metrics)!
	canvas.flip_horizontal()
}

//
pub fn draw_e0b7(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	draw_e0b5(cp, mut canvas, width, height, metrics)!
	canvas.flip_horizontal()
}

//
pub fn draw_e0d2(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	_ = cp

	float_width := f64(width)
	float_height := f64(height)
	float_thick := f64(metrics.box_thickness)

	// Top piece
	{
		mut path := canvas.static_path(6)
		path.move_to(0, 0)
		path.line_to(float_width, 0)
		path.line_to(float_width / 2, float_height / 2 - float_thick / 2)
		path.line_to(0, float_height / 2 - float_thick / 2)
		path.close()

		canvas.fill_path(path.wrapped_path, FillOptions{}, .on)!
	}

	// Bottom piece
	{
		mut path := canvas.static_path(6)
		path.move_to(0, float_height)
		path.line_to(float_width, float_height)
		path.line_to(float_width / 2, float_height / 2 + float_thick / 2)
		path.line_to(0, float_height / 2 + float_thick / 2)
		path.close()

		canvas.fill_path(path.wrapped_path, FillOptions{}, .on)!
	}
}

//
pub fn draw_e0d4(cp u32, mut canvas Canvas, width u32, height u32, metrics font.Metrics) ! {
	draw_e0d2(cp, mut canvas, width, height, metrics)!
	canvas.flip_horizontal()
}
