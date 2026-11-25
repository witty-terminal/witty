module macos

import gg.canvas
import math

pub fn (mut surface NativeActionSurface) presented() {
	C.witty_action_timer(0.1, surface.owner, sel('presentAgain:'), nil_obj(), false)
	surface.highlighted = true
	if !is_nil(surface.highlight_timer) { msg_void(surface.highlight_timer, 'invalidate') }
	surface.highlight_timer = C.witty_action_timer(0.4, surface.owner, sel('highlightExpired:'), nil_obj(), false)
	surface.refresh()
}

fn action_present_again(self ObjId, _cmd Sel, _timer ObjId) {
	if surface := action_owner_state(self) {
		if !surface.closed { move_focus(surface.view, unsafe { nil }, none) }
	}
}

fn action_highlight_expired(self ObjId, _cmd Sel, _timer ObjId) {
	if mut surface := action_owner_state(self) {
		surface.highlighted = false
		surface.highlight_timer = nil_obj()
		surface.refresh()
	}
}

fn C.witty_action_rect_path(x f64, y f64, width f64, height f64) voidptr

fn highlight_gradient_alpha(t f64, stops [3]f64) f64 {
	p := math.clamp(t, 0, 1) * 2
	if p < 1 {
		return stops[0] + (stops[1] - stops[0]) * p
	}
	return stops[1] + (stops[2] - stops[1]) * (p - 1)
}

fn highlight_gradient_image(target ObjId, width f64, height f64, scale f64, accent u32, radial bool) !voidptr {
	// The 2000-point glow varies slowly. Limit the cached texture size when
	// the pane spans a large display.
	px_width := int(math.clamp(math.round(width * scale), 1, 512))
	px_height := int(math.clamp(math.round(height * scale), 1, 512))
	mut raster := canvas.new_raster_surface(width: px_width, height: px_height)!
	stops := if radial { [f64(0.12), 0.03, 0.0]! } else { [f64(0.8), 0.5, 0.8]! }
	step_x := width / px_width
	step_y := height / px_height
	diagonal := width * width + height * height
	for y in 0 .. px_height {
		point_y := (f64(y) + 0.5) * step_y
		dy := point_y - height / 2
		for x in 0 .. px_width {
			point_x := (f64(x) + 0.5) * step_x
			dx := point_x - width / 2
			t := if radial {
				math.sqrt(dx * dx + dy * dy) / 2000
			} else {
				(point_x * width + point_y * height) / diagonal
			}
			alpha := u32(math.round(highlight_gradient_alpha(t, stops) * 255))
			// Store a premultiplied white coverage mask in the Canvas raster.
			raster.pixels[y * px_width + x] = alpha * 0x01010101
		}
	}
	image := C.witty_canvas_make_alpha_image(raster.pixels.data, px_width, px_height, accent, target)
	if is_nil(image) { return error('could not create highlight gradient image') }
	return image
}

fn (mut surface NativeActionSurface) update_highlight_gradients(width f64, height f64) {
	color := msg_id(get_class('NSColor'), 'controlAccentColor')
	accent := C.witty_canvas_resolve_srgb(surface.overlay, color)
	size := objc_size(width, height)
	if surface.highlight_accent == ?u32(accent) && size == surface.highlight_texture_size { return }
	scale := view_backing_scale(surface.view)
	radial := highlight_gradient_image(surface.overlay, width, height, scale, accent, true) or { return }
	defer { C.CFRelease(radial) }
	border := highlight_gradient_image(surface.overlay, width, height, scale, accent, false) or { return }
	defer { C.CFRelease(border) }
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	msg_void1(surface.highlight_radial, 'setContents:', ObjId(radial))
	msg_void1(surface.highlight_border, 'setContents:', ObjId(border))
	cg := msg_id(native_color(accent, 1), 'CGColor')
	for shadow in surface.highlight_shadows {
		msg_void1(shadow, 'setShadowColor:', cg)
	}
	msg_void(transaction, 'commit')
	surface.highlight_accent = accent
	surface.highlight_texture_size = size
}

fn repeating_visual_animation(layer ObjId, key string, from f64, to f64, duration f64) {
	number := get_class('NSNumber')
	repeating_highlight_animation(layer, key, msg_id_f64(number, 'numberWithDouble:', from),
		msg_id_f64(number, 'numberWithDouble:', to), duration)
}

fn repeating_highlight_animation(layer ObjId, key string, from ObjId, to ObjId, duration f64) {
	animation := msg_id1(get_class('CABasicAnimation'), 'animationWithKeyPath:', nsstring(key))
	msg_void1(animation, 'setFromValue:', from)
	msg_void1(animation, 'setToValue:', to)
	msg_void_f64(animation, 'setDuration:', duration)
	msg_void_bool(animation, 'setAutoreverses:', true)
	msg_void1(animation, 'setTimingFunction:', msg_id1(get_class('CAMediaTimingFunction'), 'functionWithName:', nsstring('easeInEaseOut')))
	C.witty_action_repeat_forever(animation)
	msg_void2(layer, 'addAnimation:forKey:', animation, nsstring(key))
}

fn (mut surface NativeActionSurface) initialize_highlight() {
	surface.highlight_layer = msg_id(get_class('CALayer'), 'layer')
	surface.highlight_radial = msg_id(get_class('CALayer'), 'layer')
	surface.highlight_border = msg_id(get_class('CALayer'), 'layer')
	surface.highlight_mask = msg_id(get_class('CAShapeLayer'), 'layer')
	msg_void1(surface.highlight_mask, 'setFillColor:', nil_obj())
	msg_void1(surface.highlight_mask, 'setStrokeColor:', msg_id(msg_id(get_class('NSColor'), 'blackColor'), 'CGColor'))
	msg_void_f64(surface.highlight_mask, 'setLineWidth:', 2)
	msg_void1(surface.highlight_border, 'setMask:', surface.highlight_mask)
	msg_void1(surface.highlight_layer, 'addSublayer:', surface.highlight_radial)
	// Apply both shadows in order to the same gradient stroke.
	mut stroke := surface.highlight_border
	for i in 0 .. 2 {
		shadow := msg_id(get_class('CALayer'), 'layer')
		C.witty_action_shadow_offset(shadow, 0, 0)
		msg_void_f64(shadow, 'setShadowRadius:', if i == 0 { 8 } else { 16 })
		C.witty_macos_msg_void_f32(shadow, sel('setShadowOpacity:'), if i == 0 {
			f32(0.6)
		} else {
			f32(0.3)
		})
		msg_void1(shadow, 'addSublayer:', stroke)
		surface.highlight_shadows << shadow
		stroke = shadow
	}
	msg_void1(surface.highlight_layer, 'addSublayer:', stroke)
	C.witty_macos_msg_void_f32(surface.highlight_layer, sel('setOpacity:'), 0)
	msg_void1(msg_id(surface.overlay, 'layer'), 'addSublayer:', surface.highlight_layer)
}

fn (mut surface NativeActionSurface) refresh_highlight() {
	width := view_width(surface.view)
	height := view_height(surface.view)
	frame := objc_rect(0, 0, width, height)
	size_changed := msg_rect(surface.highlight_mask, 'frame') != frame
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	msg_void_rect(surface.highlight_layer, 'setFrame:', frame)
	msg_void_rect(surface.highlight_radial, 'setFrame:', frame)
	msg_void_rect(surface.highlight_border, 'setFrame:', frame)
	msg_void_rect(surface.highlight_mask, 'setFrame:', frame)
	for shadow in surface.highlight_shadows { msg_void_rect(shadow, 'setFrame:', frame) }
	msg_void(transaction, 'commit')
	if surface.highlighted && width > 0 && height > 0 {
		surface.update_highlight_gradients(width, height)
	}
	msg_void(transaction, 'begin')
	msg_void_f64(transaction, 'setAnimationDuration:', 0.4)
	msg_void1(transaction, 'setAnimationTimingFunction:',
		msg_id1(get_class('CAMediaTimingFunction'), 'functionWithName:', nsstring('easeOut')))
	C.witty_macos_msg_void_f32(surface.highlight_layer, sel('setOpacity:'), if surface.highlighted {
		f32(1)
	} else {
		f32(0)
	})
	msg_void(transaction, 'commit')
	if !surface.highlighted {
		msg_void(surface.highlight_mask, 'removeAllAnimations')
		for shadow in surface.highlight_shadows { msg_void(shadow, 'removeAllAnimations') }
	} else if size_changed || is_nil(msg_id1(surface.highlight_mask, 'animationForKey:', nsstring('lineWidth'))) {
		from := C.witty_action_rect_path(1, 1, math.max(0, width - 2), math.max(0, height - 2))
		to := C.witty_action_rect_path(2, 2, math.max(0, width - 4), math.max(0, height - 4))
		msg_void1(surface.highlight_mask, 'setPath:', from)
		repeating_highlight_animation(surface.highlight_mask, 'path', ObjId(from), ObjId(to), 0.4)
		C.witty_action_path_release(from)
		C.witty_action_path_release(to)
		repeating_visual_animation(surface.highlight_mask, 'lineWidth', 2, 4, 0.4)
		for i, shadow in surface.highlight_shadows {
			repeating_visual_animation(shadow, 'shadowRadius', if i == 0 { 8 } else { 16 }, if i == 0 {
				12
			} else {
				24
			}, 0.4)
			repeating_visual_animation(shadow, 'shadowOpacity', if i == 0 { 0.6 } else { 0.3 }, if i == 0 {
				0.8
			} else {
				0.5
			}, 0.4)
		}
	}
}
