module macos

import zigimg

fn C.witty_canvas_resolve_linear_srgb(view ObjId, color ObjId, r &f64, g &f64, b &f64) bool
fn C.witty_canvas_make_opaque_color(space &CGColorSpace, r f64, g f64, b f64) voidptr

struct ProgressTintChange {
	start f64
	delta zigimg.Oklab
}

struct NativeProgressTint {
mut:
	target  ?zigimg.Colorf32
	changes []ProgressTintChange
}

fn (mut tint NativeProgressTint) clear(layer ObjId) {
	if tint.changes.len > 0 {
		msg_void1(layer, 'removeAnimationForKey:', nsstring('progressTint'))
		tint.changes.clear()
	}
	tint.target = none
}

fn (mut tint NativeProgressTint) update(layer ObjId, view ObjId, color ObjId, value_start ?f64) {
	mut r, mut g, mut b := 0.0, 0.0, 0.0
	if !C.witty_canvas_resolve_linear_srgb(view, color, &r, &g, &b) {
		tint.clear(layer)
		return
	}
	target := zigimg.Colorf32{r: f32(r), g: f32(g), b: f32(b), a: 1}
	previous := tint.target or {
		tint.target = target
		return
	}
	if target == previous { return }
	tint.target = target
	now := value_start or { C.witty_action_layer_time(layer) }
	tint.changes = tint.changes.filter(it.start + progress_value_duration > now)
	lab := zigimg.srgb.to_oklab(target)
	if start := value_start {
		prior := zigimg.srgb.to_oklab(previous)
		tint.changes << ProgressTintChange{
			start: start
			delta: zigimg.Oklab{l: prior.l - lab.l, a: prior.a - lab.a, b: prior.b - lab.b}
		}
	}
	if tint.changes.len > 0 && animate_progress_tint(layer, now, lab, tint.changes) { return }
	msg_void1(layer, 'removeAnimationForKey:', nsstring('progressTint'))
	tint.changes.clear()
}

fn progress_tint_remaining(elapsed f64) f32 {
	fraction := elapsed / progress_value_duration
	if fraction >= 1 { return 0 }
	if fraction <= 0 { return 1 }
	mut low, mut high := 0.0, 1.0
	for _ in 0 .. 24 {
		t := (low + high) / 2
		u := 1 - t
		if 3 * u * t * (0.42 * u + 0.58 * t) + t * t * t < fraction {
			low = t
		} else {
			high = t
		}
	}
	t := (low + high) / 2
	return f32(1 - t * t * (3 - 2 * t))
}

fn animate_progress_tint(layer ObjId, now f64, target zigimg.Oklab, changes []ProgressTintChange) bool {
	space := CGColorSpace.create_named(.extended_linear_srgb) or { return false }
	defer { space.release() }
	transparent := C.witty_canvas_make_srgb_tile(0, 0, 0, 0)
	if is_nil(transparent) { return false }
	defer { C.CFRelease(transparent) }
	duration := changes.last().start + progress_value_duration - now
	samples := 96
	mut colors := []voidptr{cap: samples + 1}
	defer {
		for color in colors { C.CFRelease(color) }
	}
	for sample in 0 .. samples + 1 {
		time := now + duration * f64(sample) / samples
		mut lab := target
		for change in changes {
			remaining := progress_tint_remaining(time - change.start)
			lab.l += change.delta.l * remaining
			lab.a += change.delta.a * remaining
			lab.b += change.delta.b * remaining
		}
		rgb := zigimg.srgb.from_oklab(lab, .none)
		color := C.witty_canvas_make_opaque_color(space, rgb.r, rgb.g, rgb.b)
		if is_nil(color) { return false }
		colors << color
	}
	fill := msg_id1(get_class('CAKeyframeAnimation'), 'animationWithKeyPath:', nsstring('backgroundColor'))
	msg_void1(fill, 'setValues:', C.witty_macos_array(colors.data, uint(colors.len)))
	msg_void_f64(fill, 'setDuration:', duration)

	// The animated color occupies the same layer as the Canvas tile. Hide the
	// tile in the presentation layer until the color animation finishes.
	contents := msg_id1(get_class('CABasicAnimation'), 'animationWithKeyPath:', nsstring('contents'))
	msg_void1(contents, 'setFromValue:', ObjId(transparent))
	msg_void1(contents, 'setToValue:', ObjId(transparent))
	msg_void_f64(contents, 'setDuration:', duration)
	animations := [voidptr(fill), voidptr(contents)]
	group := msg_id(get_class('CAAnimationGroup'), 'animation')
	msg_void1(group, 'setAnimations:', C.witty_macos_array(animations.data, uint(animations.len)))
	msg_void_f64(group, 'setBeginTime:', now)
	msg_void_f64(group, 'setDuration:', duration)
	msg_void2(layer, 'addAnimation:forKey:', group, nsstring('progressTint'))
	return true
}
