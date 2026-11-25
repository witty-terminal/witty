module macos

import os
import stbi

struct SplitDividerFixture {
	name string
	config NativeWindowConfig
	divider u32
}

fn split_divider_fixture_pixels(host &NativeSplitHost, config NativeWindowConfig, scale int) ![]u8 {
	width, height := 103 * scale, 63 * scale
	mut pixels := []u8{len: width * height * 4}
	space := CGColorSpace.create_named(.srgb)!
	defer { space.release() }
	context := CGBitmapContext.create(pixels, u32(width), u32(height), 8, u32(width * 4), space,
		u32(CGBitmapInfo.byte_order_32_big) | u32(CGImageAlphaInfo.premultiplied_last))!.as_context()
	defer { context.release() }
	background := config.background
	context.set_rgb_fill_color(f64((background >> 16) & 255) / 255, f64((background >> 8) & 255) / 255,
		f64(background & 255) / 255, 1)
	context.fill_rect(CGRect{size: CGSize{width: f64(width), height: f64(height)}})
	context.translate_ctm(0, height)
	context.scale_ctm(scale, -scale)
	host.draw_dividers(voidptr(context), scale)
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
			pixels := split_divider_fixture_pixels(&host, fixture.config, scale)!
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
