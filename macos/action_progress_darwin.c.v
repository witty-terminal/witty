module macos

import math

fn (mut state NativeActionSurface) initialize_progress() {
	state.progress_view = msg_id_rect(alloc('WittyPassiveOverlay'), 'initWithFrame:', objc_rect(0,
		0, view_width(state.view), 2))
	msg_void_bool(state.progress_view, 'setWantsLayer:', true)
	msg_void1(state.overlay, 'addSubview:', state.progress_view)
	clip := msg_id(state.progress_view, 'layer')
	msg_void_bool(clip, 'setMasksToBounds:', true)
	state.progress_track = msg_id(get_class('CALayer'), 'layer')
	state.progress_layer = msg_id(get_class('CALayer'), 'layer')
	msg_void1(clip, 'addSublayer:', state.progress_track)
	msg_void1(clip, 'addSublayer:', state.progress_layer)
	msg_void_bool(state.progress_view, 'setAccessibilityElement:', true)
	msg_void1(state.progress_view, 'setAccessibilityRole:', nsstring('AXProgressIndicator'))
	C.witty_macos_observe(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), state.overlay,
		sel('progressColorsChanged:'), nsstring('NSSystemColorsDidChangeNotification'), nil_obj())
}

fn action_overlay_appearance_changed(self ObjId, _cmd Sel) {
	view_super_void(self, 'WittyActionOverlay', 'viewDidChangeEffectiveAppearance')
	action_progress_colors_changed(self, nil_obj(), nil_obj())
}

fn action_progress_colors_changed(self ObjId, _cmd Sel, _notification ObjId) {
	if mut state := action_owner_state(self) {
		if state.progress_active { state.refresh_progress() }
	}
}

fn (mut state NativeActionSurface) refresh_progress() {
	msg_void_bool(state.progress_view, 'setHidden:', !state.progress_active)
	if !state.progress_active {
		msg_void(state.progress_layer, 'removeAllAnimations')
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
		tile := native_canvas_fill_tile(rgb)
		if !is_nil(tile) {
			msg_void1(state.progress_layer, 'setContents:', ObjId(tile))
			C.CFRelease(tile)
		}
		// The track is a translucent color. Convert it before premultiplication
		// to match SwiftUI's fill in the window's color profile.
		track := native_canvas_fill_tile(rgb, target: state.progress_view, opacity: 0.3)
		if !is_nil(track) {
			msg_void1(state.progress_track, 'setContents:', ObjId(track))
			C.CFRelease(track)
		}
		if !is_nil(tile) && !is_nil(track) { state.progress_color = rgb }
	}
	msg_void_rect(state.progress_view, 'setFrame:', objc_rect(0, 0, width, 2))
	msg_void_rect(state.progress_track, 'setFrame:', objc_rect(0, 0, width, 2))
	msg_void_bool(state.progress_track, 'setHidden:', determinate)
	msg_void(transaction, 'commit')

	animate := determinate && state.last_progress_value >= 0
		&& progress_value != state.last_progress_value && !size_changed
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', !animate)
	msg_void_f64(transaction, 'setAnimationDuration:', 0.2)
	msg_void1(transaction, 'setAnimationTimingFunction:', progress_timing_function())
	msg_void_rect(state.progress_layer, 'setFrame:', objc_rect(0, 0, bar_width, 2))
	msg_void(transaction, 'commit')
	if size_changed || determinate {
		state.clear_progress_bounce()
	}
	if !determinate && is_nil(msg_id1(state.progress_layer, 'animationForKey:', nsstring('bounce'))) {
		end_width := width - math.round(width * 0.75 * scale) / scale
		animate_progress_bounce(state.progress_layer, 'bounce', 'position.x', bar_width / 2,
			width - end_width / 2)
		if end_width != bar_width {
			animate_progress_bounce(state.progress_layer, 'bounceWidth', 'bounds.size.width', bar_width,
				end_width)
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

fn (state &NativeActionSurface) clear_progress_bounce() {
	msg_void1(state.progress_layer, 'removeAnimationForKey:', nsstring('bounce'))
	msg_void1(state.progress_layer, 'removeAnimationForKey:', nsstring('bounceWidth'))
}

fn animate_progress_bounce(layer ObjId, key string, property string, from f64, to f64) {
	animation := msg_id1(get_class('CABasicAnimation'), 'animationWithKeyPath:', nsstring(property))
	cls := get_class('NSNumber')
	msg_void1(animation, 'setFromValue:', msg_id_f64(cls, 'numberWithDouble:', from))
	msg_void1(animation, 'setToValue:', msg_id_f64(cls, 'numberWithDouble:', to))
	msg_void_f64(animation, 'setDuration:', 1.2)
	msg_void_bool(animation, 'setAutoreverses:', true)
	msg_void1(animation, 'setTimingFunction:', progress_timing_function())
	C.witty_action_repeat_forever(animation)
	msg_void2(layer, 'addAnimation:forKey:', animation, nsstring(key))
}
