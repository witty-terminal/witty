module macos

import math
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
	if tint.target != none {
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
	changed := target != previous
	if !changed && value_start == none { return }
	tint.target = target
	now := value_start or { C.witty_action_layer_time(layer) }
	tint.changes = tint.changes.filter(it.start + progress_value_duration > now)
	mut end := now
	if start := value_start {
		end = start + progress_value_duration
		if changed {
			prior := progress_tint_to_oklab(previous)
			lab := progress_tint_to_oklab(target)
			tint.changes << ProgressTintChange{
				start: start
				delta: zigimg.Oklab{l: prior.l - lab.l, a: prior.a - lab.a, b: prior.b - lab.b}
			}
		}
	} else {
		active := msg_id1(layer, 'animationForKey:', nsstring('progressTint'))
		if !is_nil(active) { end = msg_f64(active, 'beginTime') + msg_f64(active, 'duration') }
	}
	if end > now && animate_progress_tint(layer, now, end - now, target, tint.changes) { return }
	msg_void1(layer, 'removeAnimationForKey:', nsstring('progressTint'))
	tint.changes.clear()
}

// Use Ottosson's direct linear-sRGB matrices to match the precision of the
// native progress tint when overlapping colors are converted back to RGB.
// https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
fn progress_tint_to_oklab(color zigimg.Colorf32) zigimg.Oklab {
	r, g, b := f64(color.r), f64(color.g), f64(color.b)
	l := math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	m := math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	s := math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return zigimg.Oklab{
		l: f32(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s)
		a: f32(1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s)
		b: f32(0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
	}
}

fn progress_tint_from_oklab(color zigimg.Oklab) zigimg.Colorf32 {
	lightness, a, b := f64(color.l), f64(color.a), f64(color.b)
	l_root := lightness + 0.3963377774 * a + 0.2158037573 * b
	m_root := lightness - 0.1055613458 * a - 0.0638541728 * b
	s_root := lightness - 0.0894841775 * a - 1.2914855480 * b
	l, m, s := l_root * l_root * l_root, m_root * m_root * m_root, s_root * s_root * s_root
	return zigimg.Colorf32{
		r: f32(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
		g: f32(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
		b: f32(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
		a: 1
	}
}

fn progress_tint_remaining(elapsed f64) f32 {
	fraction := elapsed / progress_value_duration
	if fraction >= 1 { return 0 }
	if fraction <= 0 { return 1 }
	mut low, mut high := 0.0, 1.0
	for _ in 0 .. 24 {
		t := (low + high) / 2
		if progress_curve_time(t) < fraction {
			low = t
		} else {
			high = t
		}
	}
	return f32(1 - progress_curve_position((low + high) / 2))
}

fn animate_progress_tint(layer ObjId, now f64, duration f64, target zigimg.Colorf32, changes []ProgressTintChange) bool {
	space := CGColorSpace.create_named(.extended_linear_srgb) or { return false }
	defer { space.release() }
	transparent := C.witty_canvas_make_srgb_tile(0, 0, 0, 0)
	if is_nil(transparent) { return false }
	defer { C.CFRelease(transparent) }
	samples := if changes.len > 0 { 100 } else { 1 }
	target_lab := if changes.len > 0 { progress_tint_to_oklab(target) } else { zigimg.Oklab{} }
	mut colors := []voidptr{cap: samples + 1}
	defer {
		for color in colors { C.CFRelease(color) }
	}
	for sample in 0 .. samples + 1 {
		time := now + duration * f64(sample) / samples
		mut lab := target_lab
		for change in changes {
			remaining := progress_tint_remaining(time - change.start)
			lab.l += change.delta.l * remaining
			lab.a += change.delta.a * remaining
			lab.b += change.delta.b * remaining
		}
		rgb := if changes.len > 0 { progress_tint_from_oklab(lab) } else { target }
		color := C.witty_canvas_make_opaque_color(space, rgb.r, rgb.g, rgb.b)
		if is_nil(color) { return false }
		colors << color
	}
	fill := msg_id1(get_class('CAKeyframeAnimation'), 'animationWithKeyPath:', nsstring('backgroundColor'))
	msg_void1(fill, 'setValues:', C.witty_macos_array(colors.data, uint(colors.len)))
	msg_void_f64(fill, 'setDuration:', duration)

	// Blend the moving edge with a native fill and restore the Canvas tile
	// when the progress animation finishes.
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
