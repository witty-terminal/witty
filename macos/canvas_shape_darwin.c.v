module macos

import gg.canvas
import math

fn C.witty_canvas_rasterize_continuous_rect(pixels &u32, width int, height int, scale f64, radius f64, stroke f64, opacity f64, x &[3][4]f64, y &[3][4]f64) bool

// Coordinates of the three cubic segments in a unit-radius continuous corner.
const canvas_corner_y = [[0.0, 0.0, 0.0, 0.0749114]!,
	[0.0749114, 0.1690600, 0.3728240, 0.6314940]!,
	[0.6314940, 0.8684070, 1.0884900, 1.5286650]!]!
const canvas_corner_x = [[1.5286650, 1.0884900, 0.8684070, 0.6314940]!,
	[0.6314940, 0.3728240, 0.1690600, 0.0749114]!,
	[0.0749114, 0.0, 0.0, 0.0]!]!

enum NativeCanvasRoundedStyle {
	circular
	segmented_circle
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
	if radius == 0 || (edge >= radius && style in [.circular, .segmented_circle]) { return margin }
	if style in [.circular, .segmented_circle] {
		dy := radius - edge
		if style == .segmented_circle {
			// The system's 16-pixel circle has eight straight segments per quadrant.
			step := math.pi / 16
			cosine := dy / radius
			start := step * math.floor(math.acos(cosine) / step)
			end := start + step
			fraction := (math.cos(start) - cosine) / (math.cos(start) - math.cos(end))
			return margin + radius * (1 - math.sin(start) -
				fraction * (math.sin(end) - math.sin(start)))
		}
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

fn canvas_rounded_span(x int, width int, left f64) f64 {
	if left < 0 { return 0 }
	// At a tight corner, the two edges can meet within the middle pixel.
	return math.max(0.0, math.min(f64(x + 1), width - left) - math.max(f64(x), left))
}

@[params]
struct NativeCanvasRoundedMaskOptions {
	stroke               f64
	opacity              f64 = 1
	style                NativeCanvasRoundedStyle
	padding              f64
	outer_coverage_gamma f64 = 1
}

// Create coverage for a fill or inside stroke. All dimensions are in backing pixels.
fn native_canvas_rounded_mask(width int, height int, corner f64, opts NativeCanvasRoundedMaskOptions) !canvas.RasterSurface {
	mut raster := canvas.new_raster_surface(width: width, height: height)!
	extent_x := if opts.style == .continuous_capsule { canvas_corner_y[2][3] } else { 1.0 }
	max_radius := math.min((width - 2 * opts.padding) / (2 * extent_x),
		(height - 2 * opts.padding) / 2)
	radius := math.max(0.0, math.min(corner, max_radius))
	stroke := opts.stroke
	for row in 0 .. height {
		mut outer := [16]f64{}
		mut inner := [16]f64{}
		for i in 0 .. outer.len {
			y := row + (i + 0.5) / outer.len
			outer[i] = canvas_rounded_inset(y, height, radius, opts.padding, opts.style)
			inner[i] = if stroke > 0 {
				canvas_rounded_inset(y, height, math.max(0.0, radius - stroke),
					opts.padding + stroke, opts.style)
			} else {
				-1.0
			}
		}
		for column in 0 .. (width + 1) / 2 {
			mut outer_coverage := 0.0
			mut coverage := 0.0
			for i, edge in outer {
				span := canvas_rounded_span(column, width, edge)
				outer_coverage += span
				coverage += span - canvas_rounded_span(column, width, inner[i])
			}
			if opts.outer_coverage_gamma != 1 && outer_coverage > 0 && outer_coverage < outer.len {
				alpha := outer_coverage / outer.len
				coverage = math.max(0.0, coverage + (math.pow(alpha, opts.outer_coverage_gamma) - alpha) * outer.len)
			}
			pixel := u32(math.round(255 * opts.opacity * coverage / outer.len)) << 24
			raster.pixels[row * width + column] = pixel
			raster.pixels[row * width + width - 1 - column] = pixel
		}
	}
	return raster
}

fn native_canvas_capsule_stroke(width int, height int, stroke f64, opacity f64) !canvas.RasterSurface {
	mut raster := native_canvas_rounded_mask(width, height, height / 2.0,
		style: .continuous_capsule, stroke: stroke, opacity: opacity)!
	if width < height || height <= stroke { return raster }
	// An inset continuous capsule stroke includes straight side segments through
	// the endcaps. The inset centerline's radius determines where they start.
	inset := stroke / 2
	start := inset + (height / 2.0 - inset) * math.sqrt(2) / 3
	for row in int(math.floor(start)) .. height - int(math.floor(start)) {
		row_coverage := math.min(f64(row + 1), height - start) - math.max(f64(row), start)
		for column in 0 .. int(math.ceil(stroke)) {
			coverage := row_coverage * math.min(1.0, stroke - column)
			pixel := u32(math.round(255 * opacity * coverage)) << 24
			left := row * width + column
			right := row * width + width - 1 - column
			raster.pixels[left] = math.max(raster.pixels[left], pixel)
			raster.pixels[right] = math.max(raster.pixels[right], pixel)
		}
	}
	return raster
}

fn native_canvas_continuous_rect(width int, height int, scale f64, radius f64, stroke f64, opacity f64) !canvas.RasterSurface {
	mut raster := canvas.new_raster_surface(width: width, height: height)!
	if !C.witty_canvas_rasterize_continuous_rect(raster.pixels.data, width, height, scale,
		radius, stroke, opacity, &canvas_corner_x, &canvas_corner_y) {
		return error('Could not rasterize a continuous rounded rectangle')
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
