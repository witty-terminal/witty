module witty_macos

import os
import stbi

#insert "@VMODROOT/witty_macos/canvas_overlay_test_bridge.h"

fn C.witty_overlay_test_split_fill_matches(layer ObjId, rgb u32, brightness f64) bool

struct SplitDividerFixture {
	config NativeWindowConfig
	rgb u32
	brightness f64
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

fn test_native_split_divider_color_and_backing_geometry() ! {
	app_init()
	register_split_host_class()
	bounds := objc_rect(0, 0, 103, 63)
	container := msg_id_rect(alloc('NSView'), 'initWithFrame:', bounds)
	defer { msg_void(container, 'release') }
	left, right, bottom := voidptr(1), voidptr(2), voidptr(3)
	tree := NativeSplitTree{root: native_split_leaf(left)}.inserting(right, left, .right)!
	nested := tree.inserting(bottom, left, .down)!
	mut host := NativeSplitHost{
		container: container
		tree: nested
		dividers: split_dividers(nested.root, SplitBounds{ width: 103, height: 63 }, 1, 1)
	}
	// The reference handle is seven points wide and centered on the divider.
	assert host.divider_at(ObjCPoint{ x: 48, y: 10 }) != none
	assert host.divider_at(ObjCPoint{ x: 47, y: 10 }) == none
	assert host.divider_at(ObjCPoint{ x: 10, y: 28 }) != none
	assert host.divider_at(ObjCPoint{ x: 10, y: 27 }) == none

	fixtures := [
		SplitDividerFixture{ config: NativeWindowConfig{ background: 0x161820, split_divider_color: u32(0x47637c) }, rgb: 0x47637c, brightness: 1 },
		SplitDividerFixture{ config: NativeWindowConfig{ background: 0x161820 }, rgb: 0x161820, brightness: 0.6 },
		SplitDividerFixture{ config: NativeWindowConfig{ background: 0xf9f3e5 }, rgb: 0xf9f3e5, brightness: 0.92 },
	]
	host.layout_divider_view(bounds)
	assert host.divider_layers.len == 2
	vertical, horizontal := host.divider_layers[0], host.divider_layers[1]
	for fixture in fixtures {
		host.set_appearance(fixture.config, left)
		assert C.witty_overlay_test_split_fill_matches(vertical, fixture.rgb, fixture.brightness)
		assert C.witty_overlay_test_split_fill_matches(horizontal, fixture.rgb, fixture.brightness)
		for scale in [1, 2] {
			host.layout_divider_layers(scale)
			divider_x := if scale == 1 { 51.0 } else { 50.5 }
			divider_y := if scale == 1 { 31.0 } else { 30.5 }
			assert msg_rect(vertical, 'frame') == objc_rect(divider_x, 0, 1, 63)
			assert msg_rect(horizontal, 'frame') == objc_rect(0, divider_y, 51, 1)
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
