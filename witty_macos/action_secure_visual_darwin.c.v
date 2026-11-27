module witty_macos

import gg.canvas
import math

const secure_card_side = 35.0
const secure_corner_radius = 12.0
const secure_outline_width = 1.0
// The rotated square must still cover the whole badge at 45 degrees.
const secure_texture_side = 50.0
// Match the 25-point SwiftUI glyph after NSImageView applies its alignment insets.
const secure_symbol_side = 29.0

fn (mut state NativeActionSurface) initialize_secure_visuals() {
	frame := objc_rect(0, 0, secure_card_side, secure_card_side)
	state.secure_art = msg_id_rect(alloc('WittyPassiveOverlay'), 'initWithFrame:', frame)
	msg_void_bool(state.secure_art, 'setClipsToBounds:', false)
	msg_void_bool(state.secure_art, 'setWantsLayer:', true)
	msg_void1(state.overlay, 'addSubview:', state.secure_art)
	msg_void(state.secure_art, 'release')
	root := msg_id(state.secure_art, 'layer')
	layer_class := get_class('CALayer')
	state.secure_card = msg_id(layer_class, 'layer')
	msg_void_rect(state.secure_card, 'setFrame:', frame)
	card_mask := msg_id(layer_class, 'layer')
	msg_void_rect(card_mask, 'setFrame:', frame)
	msg_void1(state.secure_card, 'setMask:', card_mask)
	msg_void1(root, 'addSublayer:', state.secure_card)

	state.secure_wash = msg_id(layer_class, 'layer')
	msg_void_rect(state.secure_wash, 'setFrame:', frame)
	mask := msg_id(layer_class, 'layer')
	msg_void_rect(mask, 'setFrame:', frame)
	msg_void1(state.secure_wash, 'setMask:', mask)
	msg_void1(state.secure_card, 'addSublayer:', state.secure_wash)
	state.secure_gradient = msg_id(layer_class, 'layer')
	center_offset := (secure_card_side - secure_texture_side) / 2
	msg_void_rect(state.secure_gradient, 'setFrame:',
		objc_rect(center_offset, center_offset, secure_texture_side, secure_texture_side))
	msg_void1(state.secure_wash, 'addSublayer:', state.secure_gradient)

	state.secure_outline = msg_id(layer_class, 'layer')
	msg_void1(root, 'addSublayer:', state.secure_outline)

	state.secure_symbol = msg_id_rect(alloc('NSImageView'), 'initWithFrame:', frame)
	msg_void_bool(state.secure_symbol, 'setWantsLayer:', true)
	symbol := msg_id2(get_class('NSImage'), 'imageWithSystemSymbolName:accessibilityDescription:',
		nsstring('lock.shield.fill'), nsstring('Secure Input'))
	configuration := C.witty_action_id_f64_f64(get_class('NSImageSymbolConfiguration'),
		sel('configurationWithPointSize:weight:'), 18, 0)
	configured := msg_id1(symbol, 'imageWithSymbolConfiguration:', configuration)
	msg_void1(state.secure_symbol, 'setImage:', if is_nil(configured) { symbol } else { configured })
	msg_void_u64(state.secure_symbol, 'setImageScaling:', 3)
	msg_void1(state.secure_symbol, 'setContentTintColor:', msg_id(get_class('NSColor'), 'labelColor'))
	msg_void_bool(state.secure_symbol, 'setAccessibilityElement:', false)
	msg_void1(state.overlay, 'addSubview:', state.secure_symbol)
	msg_void(state.secure_symbol, 'release')

	state.secure_badge = action_button(state, '', 'secureInfo:', frame)
	msg_void_bool(state.secure_badge, 'setBordered:', false)
	msg_void_bool(state.secure_badge, 'setTransparent:', true)
	msg_void1(state.secure_badge, 'setAccessibilityLabel:', nsstring('Secure Input'))
	msg_void1(state.overlay, 'addSubview:', state.secure_badge)
}

fn secure_gradient_pixel(colors [4]u32, x f64, y f64) u32 {
	angle := math.atan2(y, x)
	turn := (if angle < 0 { angle + 2 * math.pi } else { angle }) / (2 * math.pi)
	segment := turn * 4
	left := int(segment) % 4
	right := (left + 1) % 4
	fraction := segment - math.floor(segment)
	mut pixel := u32(0xff000000)
	for shift in [16, 8, 0] {
		a := f64((colors[left] >> shift) & 255)
		b := f64((colors[right] >> shift) & 255)
		pixel |= u32(math.round(a + (b - a) * fraction)) << shift
	}
	return pixel
}

fn secure_blur_pass(pixels []u32, size int, kernel []f64, vertical bool) []u32 {
	mut output := []u32{len: pixels.len}
	step := if vertical { size } else { 1 }
	line_step := if vertical { 1 } else { size }
	radius := kernel.len / 2
	for line in 0 .. size {
		start := line * line_step
		for offset in 0 .. size {
			mut r, mut g, mut b := 0.0, 0.0, 0.0
			for tap, weight in kernel {
				pos := int(math.clamp(f64(offset + tap - radius), 0, f64(size - 1)))
				pixel := pixels[start + pos * step]
				r += f64((pixel >> 16) & 255) * weight
				g += f64((pixel >> 8) & 255) * weight
				b += f64(pixel & 255) * weight
			}
			output[start + offset * step] = 0xff000000 | u32(math.round(r)) << 16
				| u32(math.round(g)) << 8 | u32(math.round(b))
		}
	}
	return output
}

fn secure_gradient_image(colors [4]u32, scale f64) !voidptr {
	size := int(math.round(secure_texture_side * scale))
	mut raster := canvas.new_raster_surface(width: size, height: size)!
	center := (size - 1) / 2.0
	for y in 0 .. size {
		for x in 0 .. size {
			raster.pixels[y * size + x] = secure_gradient_pixel(colors, x - center, y - center)
		}
	}
	kernel := canvas_blur_kernel(4 * scale)
	horizontal := secure_blur_pass(raster.pixels, size, kernel, false)
	raster.pixels = secure_blur_pass(horizontal, size, kernel, true)
	image := C.witty_canvas_make_color_image(raster.pixels.data, size, size)
	if is_nil(image) { return error('could not create Secure Input gradient image') }
	return image
}

fn secure_mask_image(scale f64) !voidptr {
	size := int(math.round(secure_card_side * scale))
	mut raster := canvas.new_raster_surface(width: size, height: size)!
	center := (size - 1) / 2.0
	for y in 0 .. size {
		dy := y - center
		for x in 0 .. size {
			dx := x - center
			opacity := math.min(1, math.sqrt(dx * dx + dy * dy) / (25 * scale))
			alpha := u32(math.round(opacity * 255))
			raster.pixels[y * size + x] = alpha * 0x01010101
		}
	}
	mask := C.witty_canvas_make_alpha_image(raster.pixels.data, size, size, 0xffffff, nil_obj())
	if is_nil(mask) { return error('could not create Secure Input gradient mask') }
	return mask
}

fn secure_outline_mask(size int, scale f64) !canvas.RasterSurface {
	// Pad to whole pixels so the centered stroke also samples cleanly at 1×.
	half_stroke := secure_outline_width * scale / 2
	pad := int(math.ceil(half_stroke))
	outline_size := size + 2 * pad
	return native_canvas_rounded_mask(outline_size, outline_size,
		secure_corner_radius * scale + half_stroke, style: .continuous,
		stroke: secure_outline_width * scale, padding: pad - half_stroke)
}

fn (mut state NativeActionSurface) update_secure_textures() {
	color_class := get_class('NSColor')
	mut palette := [5]u32{}
	for index, name in ['systemCyanColor', 'systemBlueColor', 'systemYellowColor',
		'windowBackgroundColor', 'systemGrayColor'] {
		palette[index] = C.witty_canvas_resolve_srgb(state.secure_art, msg_id(color_class, name))
	}
	scale := view_backing_scale(state.view)
	if state.secure_scale == scale && state.secure_palette == palette { return }
	gradient := secure_gradient_image([palette[0], palette[1], palette[2], palette[1]]!, scale) or { return }
	defer { C.CFRelease(gradient) }
	mask := secure_mask_image(scale) or { return }
	defer { C.CFRelease(mask) }
	base := native_canvas_fill_tile(palette[3])
	if is_nil(base) { return }
	defer { C.CFRelease(base) }

	size := int(math.round(secure_card_side * scale))
	silhouette := native_canvas_rounded_mask(size, size, secure_corner_radius * scale,
		style: .continuous) or { return }
	card_mask := C.witty_canvas_make_alpha_image(silhouette.pixels.data, size, size, 0xffffff, nil_obj())
	if is_nil(card_mask) { return }
	defer { C.CFRelease(card_mask) }

	border := secure_outline_mask(size, scale) or { return }
	pad := (border.width - size) / (2 * scale)
	outline := C.witty_canvas_make_alpha_image(border.pixels.data, border.width, border.height,
		palette[4], state.secure_art)
	if is_nil(outline) { return }
	defer { C.CFRelease(outline) }

	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	msg_void1(state.secure_card, 'setContents:', ObjId(base))
	msg_void1(msg_id(state.secure_card, 'mask'), 'setContents:', ObjId(card_mask))
	msg_void1(state.secure_gradient, 'setContents:', ObjId(gradient))
	msg_void1(msg_id(state.secure_wash, 'mask'), 'setContents:', ObjId(mask))
	msg_void_rect(state.secure_outline, 'setFrame:',
		objc_rect(-pad, -pad, border.width / scale, border.height / scale))
	msg_void1(state.secure_outline, 'setContents:', ObjId(outline))
	msg_void(transaction, 'commit')
	state.secure_palette = palette
	state.secure_scale = scale
}

fn (mut state NativeActionSurface) refresh_secure_visuals() {
	frame := objc_rect(view_width(state.view) - secure_card_side - 10, 10, secure_card_side, secure_card_side)
	msg_void_rect(state.secure_badge, 'setFrame:', frame)
	msg_void_rect(state.secure_art, 'setFrame:', frame)
	inset := (secure_card_side - secure_symbol_side) / 2
	msg_void_rect(state.secure_symbol, 'setFrame:',
		objc_rect(frame.x + inset + 0.5, frame.y + inset - 0.5, secure_symbol_side, secure_symbol_side))
	hidden := msg_bool(state.secure_badge, 'isHidden')
	msg_void_bool(state.secure_art, 'setHidden:', hidden)
	msg_void_bool(state.secure_symbol, 'setHidden:', hidden)
	if hidden {
		msg_void(state.secure_gradient, 'removeAllAnimations')
		msg_void(state.secure_wash, 'removeAllAnimations')
		return
	}
	state.update_secure_textures()
	if !is_nil(msg_id1(state.secure_gradient, 'animationForKey:', nsstring('secureRotation'))) { return }
	C.witty_macos_msg_void_f32(state.secure_wash, sel('setOpacity:'), 0.5)
	secure_animation(state.secure_gradient, 'secureRotation', 'transform.rotation.z', 0, -math.pi * 2, false)
	secure_animation(state.secure_wash, 'secureOpacity', 'opacity', 0.5, 1, true)
}

fn secure_animation(layer ObjId, name string, key string, from f64, to f64, autoreverses bool) {
	animation := msg_id1(get_class('CABasicAnimation'), 'animationWithKeyPath:', nsstring(key))
	number_class := get_class('NSNumber')
	msg_void1(animation, 'setFromValue:', msg_id_f64(number_class, 'numberWithDouble:', from))
	msg_void1(animation, 'setToValue:', msg_id_f64(number_class, 'numberWithDouble:', to))
	msg_void1(animation, 'setTimingFunction:',
		msg_id1(get_class('CAMediaTimingFunction'), 'functionWithName:', nsstring('linear')))
	msg_void_f64(animation, 'setDuration:', 2)
	msg_void_bool(animation, 'setAutoreverses:', autoreverses)
	C.witty_action_repeat_forever(animation)
	msg_void2(layer, 'addAnimation:forKey:', animation, nsstring(name))
}
