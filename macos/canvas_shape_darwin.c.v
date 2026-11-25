module macos

import gg.canvas
import math

// Coordinates of the three cubic segments in a unit-radius continuous corner.
const canvas_corner_y = [[0.0, 0.0, 0.0, 0.0749114]!,
	[0.0749114, 0.1690600, 0.3728240, 0.6314940]!,
	[0.6314940, 0.8684070, 1.0884900, 1.5286650]!]!
const canvas_corner_x = [[1.5286650, 1.0884900, 0.8684070, 0.6314940]!,
	[0.6314940, 0.3728240, 0.1690600, 0.0749114]!,
	[0.0749114, 0.0, 0.0, 0.0]!]!

enum NativeCanvasRoundedStyle {
	circular
	continuous
	continuous_capsule
}

fn canvas_corner_cubic(a [4]f64, t f64) f64 {
	inv := 1 - t
	return a[0] * inv * inv * inv + 3 * a[1] * inv * inv * t
		+ 3 * a[2] * inv * t * t + a[3] * t * t * t
}

fn canvas_rounded_inset(y f64, height f64, radius f64, margin f64, style NativeCanvasRoundedStyle) f64 {
	edge := math.min(y, height - y) - margin
	if edge < 0 { return -1 }
	if radius == 0 || (edge >= radius && style == .circular) { return margin }
	if style == .circular {
		dy := radius - edge
		return margin + radius - math.sqrt(radius * radius - dy * dy)
	}
	distance := edge / radius
	if style == .continuous_capsule && distance >= canvas_corner_y[1][3] {
		// The rendered continuous capsule tapers into the center of the endcap.
		middle := math.max(0.0, (1 - distance) / (1 - canvas_corner_y[1][3]))
		return margin + radius * canvas_corner_x[2][0] * middle * (0.56 + 0.44 * middle)
	}
	if distance >= canvas_corner_y[2][3] { return margin }
	segment := if distance < canvas_corner_y[0][3] {
		0
	} else if distance < canvas_corner_y[1][3] {
		1
	} else {
		2
	}
	curve := canvas_corner_y[segment]
	mut low, mut high := 0.0, 1.0
	for _ in 0 .. 14 {
		t := (low + high) / 2
		if canvas_corner_cubic(curve, t) < distance {
			low = t
		} else {
			high = t
		}
	}
	return margin + radius * canvas_corner_cubic(canvas_corner_x[segment], (low + high) / 2)
}

fn canvas_rounded_span(x int, left f64) f64 {
	if left < 0 { return 0 }
	return math.min(1.0, math.max(0.0, x + 1 - left))
}

@[params]
struct NativeCanvasRoundedMaskOptions {
	stroke  f64
	opacity f64 = 1
	style   NativeCanvasRoundedStyle
}

// Create coverage for a fill or inside stroke. The radius and stroke are in backing pixels.
fn native_canvas_rounded_mask(width int, height int, corner f64, opts NativeCanvasRoundedMaskOptions) !canvas.RasterSurface {
	mut raster := canvas.new_raster_surface(width: width, height: height)!
	extent_x := if opts.style == .circular { 1.0 } else { canvas_corner_y[2][3] }
	extent_y := if opts.style == .continuous { extent_x } else { 1.0 }
	radius := math.min(corner, math.min(width / (2 * extent_x), height / (2 * extent_y)))
	stroke := opts.stroke
	for row in 0 .. height {
		mut outer := [16]f64{}
		mut inner := [16]f64{}
		for i in 0 .. outer.len {
			y := row + (i + 0.5) / outer.len
			outer[i] = canvas_rounded_inset(y, height, radius, 0, opts.style)
			inner[i] = if stroke > 0 {
				canvas_rounded_inset(y, height, math.max(0.0, radius - stroke), stroke, opts.style)
			} else {
				-1.0
			}
		}
		for column in 0 .. (width + 1) / 2 {
			mut coverage := 0.0
			for i, edge in outer {
				coverage += canvas_rounded_span(column, edge) - canvas_rounded_span(column, inner[i])
			}
			pixel := u32(math.round(255 * opts.opacity * coverage / outer.len)) << 24
			raster.pixels[row * width + column] = pixel
			raster.pixels[row * width + width - 1 - column] = pixel
		}
	}
	return raster
}

fn canvas_blur_kernel(sigma f64) []f64 {
	radius := int(math.ceil(3 * sigma))
	mut kernel := []f64{cap: 2 * radius + 1}
	mut total := 0.0
	for offset in -radius .. radius + 1 {
		weight := math.exp(-f64(offset * offset) / (2 * sigma * sigma))
		kernel << weight
		total += weight
	}
	for i, weight in kernel { kernel[i] = weight / total }
	return kernel
}

fn native_canvas_shadow_mask(mask canvas.RasterSurface, sigma f64, opacity f64) !canvas.RasterSurface {
	kernel := canvas_blur_kernel(sigma)
	pad := kernel.len / 2
	width := mask.width + 2 * pad
	height := mask.height + 2 * pad
	mut shadow := canvas.new_raster_surface(width: width, height: height)!
	mut horizontal := []f64{len: width * mask.height}
	// Leave transparent padding in both passes, so the edge can fade to zero.
	for y in 0 .. mask.height {
		for x in 0 .. width {
			mut sum := 0.0
			for source in math.max(0, x - 2 * pad) .. math.min(mask.width, x + 1) {
				sum += f64(mask.pixels[y * mask.width + source] >> 24) * kernel[x - source]
			}
			horizontal[y * width + x] = sum
		}
	}
	for y in 0 .. height {
		for x in 0 .. width {
			mut sum := 0.0
			for source in math.max(0, y - 2 * pad) .. math.min(mask.height, y + 1) {
				sum += horizontal[source * width + x] * kernel[y - source]
			}
			shadow.pixels[y * width + x] = u32(math.round(sum * opacity)) << 24
		}
	}
	return shadow
}
