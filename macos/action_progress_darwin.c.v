module macos

import gg.canvas
import math

const progress_bounce_duration = 1.2
const progress_value_duration = 0.2

fn C.witty_action_layer_time(layer ObjId) f64

fn (mut state NativeActionSurface) initialize_progress() {
	state.progress_view = msg_id_rect(alloc('WittyPassiveOverlay'), 'initWithFrame:', objc_rect(0,
		0, view_width(state.view), 2))
	msg_void_bool(state.progress_view, 'setWantsLayer:', true)
	msg_void1(state.overlay, 'addSubview:', state.progress_view)
	clip := msg_id(state.progress_view, 'layer')
	msg_void_bool(clip, 'setMasksToBounds:', true)
	state.progress_track = msg_id(get_class('CALayer'), 'layer')
	state.progress_layer = msg_id(get_class('CALayer'), 'layer')
	C.witty_action_layer_anchor(state.progress_layer, 0, 0.5)
	msg_void_bool(state.progress_layer, 'setAllowsEdgeAntialiasing:', true)
	msg_void1(clip, 'addSublayer:', state.progress_track)
	msg_void1(clip, 'addSublayer:', state.progress_layer)
	msg_void_bool(state.progress_view, 'setAccessibilityElement:', true)
	msg_void1(state.progress_view, 'setAccessibilityRole:', nsstring('AXProgressIndicator'))
}

fn (mut state NativeActionSurface) refresh_progress() {
	msg_void_bool(state.progress_view, 'setHidden:', !state.progress_active)
	if !state.progress_active {
		msg_void(state.progress_layer, 'removeAllAnimations')
		state.progress_tint = NativeProgressTint{}
		state.last_progress_value = -1000
		return
	}

	progress_value := if p := state.progress {
		int(p)
	} else if state.progress_state == 4 {
		100
	} else {
		-1
	}
	determinate := progress_value >= 0
	width := view_width(state.view)
	scale := view_backing_scale(state.view)
	value := if determinate { f64(progress_value) / 100 } else { 0.25 }
	bar_width := math.round(width * value * scale) / scale
	size_changed := width != state.last_progress_width || scale != state.last_progress_scale
	value_start := if determinate && state.last_progress_value >= 0
		&& progress_value != state.last_progress_value {
		?f64(C.witty_action_layer_time(state.progress_layer))
	} else {
		none
	}

	color := msg_id(get_class('NSColor'), match state.progress_state {
		2 { 'systemRedColor' }
		4 { 'systemOrangeColor' }
		else { 'controlAccentColor' }
	})
	rgb := C.witty_canvas_resolve_srgb(state.progress_view, color)
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	if state.progress_color != ?u32(rgb) {
		pixel := canvas.Color4f.from_rgba8(u8(rgb >> 16), u8(rgb >> 8), u8(rgb), 255)
		if set_native_canvas_srgb_tile(state.progress_layer, pixel) {
			state.progress_color = rgb
		}
	}
	if !determinate {
		// Keep the track's alpha and color through the window's final blend.
		C.witty_canvas_set_translucent_fill(state.progress_track, state.progress_view, color, 0.3)
		state.progress_tint.clear(state.progress_layer)
	} else {
		state.progress_tint.update(state.progress_layer, state.progress_view, color, value_start)
	}
	msg_void_rect(state.progress_view, 'setFrame:', objc_rect(0, 0, width, 2))
	msg_void_rect(state.progress_track, 'setFrame:', objc_rect(0, 0, width, 2))
	msg_void_bool(state.progress_track, 'setHidden:', determinate)
	msg_void_rect(state.progress_layer, 'setFrame:', objc_rect(0, 0, bar_width, 2))
	msg_void(transaction, 'commit')
	if determinate {
		state.clear_progress_bounce()
		if start := value_start {
			previous_width := state.last_progress_width * (f64(state.last_progress_value) / 100)
			previous_bar_width := math.round(previous_width * state.last_progress_scale) / state.last_progress_scale
			animate_progress_width(state.progress_layer, previous_bar_width - bar_width, scale,
				start)
		}
	} else {
		if state.last_progress_value >= 0 {
			msg_void(state.progress_layer, 'removeAllAnimations')
		}
		bounce := msg_id1(state.progress_layer, 'animationForKey:', nsstring('bounce'))
		if width > 0 && (size_changed || is_nil(bounce)) {
			start := if is_nil(bounce) {
				C.witty_action_layer_time(state.progress_layer)
			} else {
				msg_f64(bounce, 'beginTime')
			}
			animate_progress_bounce(state.progress_layer, width, scale, start)
		}
	}
	state.last_progress_value = progress_value
	state.last_progress_width = width
	state.last_progress_scale = scale
	msg_void1(state.progress_view, 'setAccessibilityLabel:', nsstring(match state.progress_state {
		2 { 'Terminal progress - Error' }
		4 { 'Terminal progress - Paused' }
		3 { 'Terminal progress - In progress' }
		else { 'Terminal progress' }
	}))
	msg_void1(state.progress_view, 'setAccessibilityValue:', nsstring(if determinate {
		'${progress_value} percent complete'
	} else {
		match state.progress_state {
			2 { 'Operation failed' }
			3 { 'Operation in progress' }
			else { 'Indeterminate progress' }
		}
	}))
}

fn progress_timing_function() ObjId {
	return msg_id1(get_class('CAMediaTimingFunction'), 'functionWithName:', nsstring('easeInEaseOut'))
}

// Parametric time and position for the ease-in-out curve with control points
// (0.42, 0) and (0.58, 1).
fn progress_curve_time(t f64) f64 {
	u := 1 - t
	return 3 * u * t * (0.42 * u + 0.58 * t) + t * t * t
}

fn progress_curve_position(t f64) f64 {
	return t * t * (3 - 2 * t)
}

fn animate_progress_width(layer ObjId, from f64, scale f64, start f64) {
	if from == 0 { return }

	// Each report contributes its own width change until its animation ends.
	// Scale the sample count with the pixel displacement to keep the
	// linear interpolation error bounded across pane sizes.
	samples := int(math.max(16, math.ceil(128 * math.sqrt(math.abs(from) * scale))))
	mut times := []voidptr{cap: samples + 1}
	mut widths := []voidptr{cap: samples + 1}
	number := get_class('NSNumber')
	for i in 0 .. samples + 1 {
		t := f64(i) / samples
		times << voidptr(msg_id_f64(number, 'numberWithDouble:', progress_curve_time(t)))
		widths << voidptr(msg_id_f64(number, 'numberWithDouble:',
			from * (1 - progress_curve_position(t))))
	}
	animation := msg_id1(get_class('CAKeyframeAnimation'), 'animationWithKeyPath:',
		nsstring('bounds.size.width'))
	msg_void1(animation, 'setKeyTimes:', C.witty_macos_array(times.data, uint(times.len)))
	msg_void1(animation, 'setValues:', C.witty_macos_array(widths.data, uint(widths.len)))
	msg_void_bool(animation, 'setAdditive:', true)
	msg_void_f64(animation, 'setBeginTime:', start)
	msg_void_f64(animation, 'setDuration:', progress_value_duration)
	msg_void2(layer, 'addAnimation:forKey:', animation, nil_obj())
}

fn (state &NativeActionSurface) clear_progress_bounce() {
	msg_void1(state.progress_layer, 'removeAnimationForKey:', nsstring('bounce'))
}

fn progress_bounce_keyframes(property string, times ObjId, values []voidptr) ObjId {
	animation := msg_id1(get_class('CAKeyframeAnimation'), 'animationWithKeyPath:', nsstring(property))
	msg_void1(animation, 'setCalculationMode:', nsstring('discrete'))
	msg_void1(animation, 'setKeyTimes:', times)
	msg_void1(animation, 'setValues:', C.witty_macos_array(values.data, uint(values.len)))
	msg_void_f64(animation, 'setDuration:', progress_bounce_duration)
	return animation
}

fn animate_progress_bounce(layer ObjId, width f64, scale f64, start f64) {
	unrounded_width := width * scale * 0.25
	travel := width * scale - unrounded_width
	number := get_class('NSNumber')
	mut left := 0.0
	mut right := math.round(unrounded_width)
	mut times := []voidptr{}
	mut positions := []voidptr{}
	mut widths := []voidptr{}
	mut phase := 0.0
	for {
		times << voidptr(msg_id_f64(number, 'numberWithDouble:', phase))
		positions << voidptr(msg_id_f64(number, 'numberWithDouble:', left / scale))
		widths << voidptr(msg_id_f64(number, 'numberWithDouble:', (right - left) / scale))

		// Snap each edge independently as it crosses the next half pixel.
		next_left := (left + 0.5) / travel
		next_right := (right + 0.5 - unrounded_width) / travel
		next := math.min(next_left, next_right)
		if next > 1 { break }
		if next_left == next { left += 1 }
		if next_right == next { right += 1 }
		// A snap at the turnaround still needs a nonempty final interval.
		phase = math.min(next, 1 - 0.000001)
	}
	times << voidptr(msg_id_f64(number, 'numberWithDouble:', 1))
	key_times := C.witty_macos_array(times.data, uint(times.len))
	animations := [
		voidptr(progress_bounce_keyframes('position.x', key_times, positions)),
		voidptr(progress_bounce_keyframes('bounds.size.width', key_times, widths)),
	]
	group := msg_id(get_class('CAAnimationGroup'), 'animation')
	msg_void1(group, 'setAnimations:', C.witty_macos_array(animations.data, uint(animations.len)))
	msg_void_f64(group, 'setBeginTime:', start)
	msg_void_f64(group, 'setDuration:', progress_bounce_duration)
	msg_void_bool(group, 'setAutoreverses:', true)
	msg_void1(group, 'setTimingFunction:', progress_timing_function())
	C.witty_action_repeat_forever(group)
	msg_void2(layer, 'addAnimation:forKey:', group, nsstring('bounce'))
}
