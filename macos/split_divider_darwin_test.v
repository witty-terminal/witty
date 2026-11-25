module macos

import os
import stbi

struct SplitDividerFixture {
	name string
	config NativeWindowConfig
	divider u32
}

fn split_divider_fixture_pixels(shape ObjCRect, background u32, scale int, draw fn (voidptr)) ![]u8 {
	width, height := int(shape.width) * scale, int(shape.height) * scale
	mut pixels := []u8{len: width * height * 4}
	space := CGColorSpace.create_named(.srgb)!
	defer { space.release() }
	context := CGBitmapContext.create(pixels, u32(width), u32(height), 8, u32(width * 4), space,
		u32(CGBitmapInfo.byte_order_32_big) | u32(CGImageAlphaInfo.premultiplied_last))!.as_context()
	defer { context.release() }
	context.set_rgb_fill_color(f64((background >> 16) & 255) / 255, f64((background >> 8) & 255) / 255,
		f64(background & 255) / 255, 1)
	context.fill_rect(CGRect{size: CGSize{width: f64(width), height: f64(height)}})
	context.translate_ctm(0, height)
	context.scale_ctm(scale, -scale)
	draw(voidptr(context))
	return pixels
}

fn test_native_split_divider_color_and_backing_pixels() ! {
	left, right, bottom := voidptr(1), voidptr(2), voidptr(3)
	tree := NativeSplitTree{root: native_split_leaf(left)}.inserting(right, left, .right)!
	nested := tree.inserting(bottom, left, .down)!
	mut host := NativeSplitHost{
		tree: nested
		dividers: split_dividers(nested.root, SplitBounds{ width: 103, height: 63 }, 1, 1)
	}
	// The reference handle is seven points wide and centered on the divider.
	assert host.divider_at(ObjCPoint{ x: 48, y: 10 }) != none
	assert host.divider_at(ObjCPoint{ x: 47, y: 10 }) == none
	assert host.divider_at(ObjCPoint{ x: 10, y: 28 }) != none
	assert host.divider_at(ObjCPoint{ x: 10, y: 27 }) == none

	fixtures := [
		SplitDividerFixture{ name: 'configured', config: NativeWindowConfig{ background: 0x161820, split_divider_color: u32(0x47637c) }, divider: 0x47637c },
		SplitDividerFixture{ name: 'default-dark', config: NativeWindowConfig{ background: 0x161820 }, divider: 0x0d0e13 },
		SplitDividerFixture{ name: 'default-light', config: NativeWindowConfig{ background: 0xf9f3e5 }, divider: 0xe5dfd3 },
	]
	for fixture in fixtures {
		host.set_appearance(fixture.config, left)
		for scale in [1, 2] {
			width, height := 103 * scale, 63 * scale
			pixels := split_divider_fixture_pixels(objc_rect(0, 0, 103, 63), fixture.config.background, scale,
				fn [host, scale] (context voidptr) { host.draw_dividers(context, scale) })!
			if output := os.getenv_opt('WITTY_SPLIT_DIVIDER_OUTPUT') {
				stbi.stbi_write_png(os.join_path(output, '${fixture.name}-${scale}x-witty.png'), width,
					height, 4, pixels.data, width * 4)!
			}
			divider_x := if scale == 1 { 51 } else { 101 }
			divider_y := if scale == 1 { 31 } else { 61 }
			for y in 0 .. height {
				for x in 0 .. width {
					offset := (y * width + x) * 4
					rgb := (u32(pixels[offset]) << 16) | (u32(pixels[offset + 1]) << 8) | u32(pixels[offset + 2])
					vertical := x >= divider_x && x < divider_x + scale
					horizontal := y >= divider_y && y < divider_y + scale && x < divider_x
					expected := if vertical || horizontal { fixture.divider } else { fixture.config.background }
					assert rgb == expected, '${fixture.name} ${scale}x at (${x}, ${y})'
					assert pixels[offset + 3] == 255
				}
			}
		}
	}
}

fn test_native_inspector_divider_backing_pixels() ! {
	bounds := objc_rect(0, 0, 103, 62)
	background := u32(0x161820)
	divider := u32(0x47637c)
	for index, ratio in [0.5, 0.63] {
		center := [30, 38][index]
		state := NativeSurfaceScroll{ inspector_ratio: ratio, inspector_divider_color: divider }
		for scale in [1, 2] {
			width, height := int(bounds.width) * scale, int(bounds.height) * scale
			pixels := split_divider_fixture_pixels(bounds, background, scale,
				fn [state, bounds, scale] (context voidptr) { state.draw_inspector_divider(context, bounds, scale) })!
			if output := os.getenv_opt('WITTY_SPLIT_DIVIDER_OUTPUT') {
				stbi.stbi_write_png(os.join_path(output, 'inspector-${center}-${scale}x-witty.png'), width,
					height, 4, pixels.data, width * 4)!
			}
			first_row := center * scale - (scale - 1)
			for y in 0 .. height {
				expected := if y >= first_row && y < first_row + scale { divider } else { background }
				for x in 0 .. width {
					offset := (y * width + x) * 4
					rgb := (u32(pixels[offset]) << 16) | (u32(pixels[offset + 1]) << 8) | u32(pixels[offset + 2])
					assert rgb == expected, 'inspector ${ratio} ${scale}x at (${x}, ${y})'
					assert pixels[offset + 3] == 255
				}
			}
		}
	}
}
