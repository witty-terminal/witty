module witty_macos

import gg.canvas

fn C.witty_canvas_gamma22_gray(white f64) ObjId
fn C.CGColorEqualToColor(left voidptr, right voidptr) bool

// The window owns this layer even if AppKit replaces the titlebar view.
struct NativeWindowCanvasFill {
mut:
	layer      ObjId
	tile_color ?canvas.Color4f
}

fn native_window_canvas_color(color ObjId) canvas.Color4f {
	srgb := msg_id1(color, 'colorUsingColorSpace:', msg_id(get_class('NSColorSpace'), 'sRGBColorSpace'))
	if is_nil(srgb) { return canvas.Color4f{} }
	mut r, mut g, mut b, mut a := f64(0), f64(0), f64(0), f64(0)
	C.witty_macos_color_components(srgb, &r, &g, &b, &a)
	return canvas.Color4f{ r: f32(r), g: f32(g), b: f32(b), a: f32(a) }
}

fn (mut fill NativeWindowCanvasFill) update(view ObjId, color ObjId) {
	if is_nil(view) { return }
	msg_void_bool(view, 'setWantsLayer:', true)
	root := msg_id(view, 'layer')
	if is_nil(root) { return }
	if !is_nil(msg_id(root, 'backgroundColor')) {
		msg_void1(root, 'setBackgroundColor:', nil_obj())
	}

	pixel := native_window_canvas_color(color)
	if pixel.a == 0 {
		fill.clear()
		return
	}
	if is_nil(fill.layer) {
		fill.layer = msg_id(alloc('CALayer'), 'init')
		msg_void_f64(fill.layer, 'setZPosition:', -1)
		msg_void_u64(fill.layer, 'setAutoresizingMask:', 18)
	}
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	defer { msg_void(transaction, 'commit') }
	if pixel.is_opaque() {
		if fill.tile_color != ?canvas.Color4f(pixel) {
			if !set_native_canvas_srgb_tile(fill.layer, pixel) { return }
			msg_void1(fill.layer, 'setBackgroundColor:', nil_obj())
			fill.tile_color = pixel
		}
	} else {
		// Keep the original color and alpha through Core Animation compositing.
		if fill.tile_color != none {
			msg_void1(fill.layer, 'setContents:', nil_obj())
			fill.tile_color = none
		}
		native := msg_id(color, 'CGColor')
		previous := msg_id(fill.layer, 'backgroundColor')
		if is_nil(previous) || !C.CGColorEqualToColor(previous, native) {
			msg_void1(fill.layer, 'setBackgroundColor:', native)
		}
	}
	frame := msg_rect(root, 'bounds')
	if msg_rect(fill.layer, 'frame') != frame {
		msg_void_rect(fill.layer, 'setFrame:', frame)
	}
	if msg_id(fill.layer, 'superlayer') != root {
		msg_void(fill.layer, 'removeFromSuperlayer')
		msg_void1(root, 'addSublayer:', fill.layer)
	}
}

fn (mut fill NativeWindowCanvasFill) clear() {
	msg_void(fill.layer, 'removeFromSuperlayer')
	msg_void(fill.layer, 'release')
	fill.layer = nil_obj()
	fill.tile_color = none
}
