module macos

import gg.canvas
import math
import time

const update_ring_view_size = 16
const update_ring_radius = 7
const update_ring_half_stroke = 1
const update_ring_samples = 8
const update_ring_duration = u64(200 * time.millisecond)

struct UpdateRingTransition {
	start u64
	from  f64
}

fn (transition UpdateRingTransition) progress_at(target f64, now u64) f64 {
	if transition.start == 0 || now >= transition.start + update_ring_duration {
		return target
	}
	if now <= transition.start {
		return transition.from
	}
	fraction := f64(now - transition.start) / update_ring_duration
	// Invert the ease-in-out Bézier's x coordinate to obtain the y coordinate.
	mut low := 0.0
	mut high := 1.0
	for _ in 0 .. 14 {
		t := (low + high) / 2
		x := 3 * t * (1 - t) * ((1 - t) * 0.42 + t * 0.58) + t * t * t
		if x < fraction {
			low = t
		} else {
			high = t
		}
	}
	t := (low + high) / 2
	return transition.from + (target - transition.from) * t * t * (3 - 2 * t)
}

fn (mut controller NativeUpdateController) update_ring_transition(old UpdateState) {
	if old.kind != controller.state.kind || controller.badges.len == 0 {
		controller.stop_ring_transition()
		return
	}
	progress := controller.state.ring_progress() or {
		controller.stop_ring_transition()
		return
	}
	previous := old.ring_progress() or { return }
	if progress == previous {
		return
	}
	now := time.sys_mono_now()
	controller.ring_transition = UpdateRingTransition{
		start: now
		from: controller.ring_transition.progress_at(previous, now)
	}
	if is_nil(controller.ring_timer) {
		controller.ring_timer = ObjId(C.witty_action_timer(1.0 / 60.0, controller.driver,
			sel('redrawProgress:'), nil_obj(), true))
	}
}

fn (mut controller NativeUpdateController) stop_ring_transition() {
	msg_void(controller.ring_timer, 'invalidate')
	controller.ring_timer = nil_obj()
	controller.ring_transition = UpdateRingTransition{}
}

fn update_badge_redraw_progress(self ObjId, _cmd Sel, _timer ObjId) {
	if !update_driver_is_current(voidptr(self)) {
		return
	}
	mut controller := g_update_controller
	for _, badge in controller.badges {
		msg_void_bool(badge, 'setNeedsDisplay:', true)
	}
	if controller.badges.len == 0 || time.sys_mono_now() >= controller.ring_transition.start +
		update_ring_duration {
		controller.stop_ring_transition()
	}
}

fn update_pill_view() ObjId {
	mut cls := get_class('WittyUpdatePill')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSButton'), cstr('WittyUpdatePill'), 0)
		add_method(cls, 'drawRect:', voidptr(update_pill_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		C.macos_objc_register_class_pair(cls)
	}
	return msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 200, 28))
}

fn update_pill_draw(self ObjId, _cmd Sel, _rect ObjCRect) {
	if g_update_controller == unsafe { nil } { return }
	state := g_update_controller.state
	C.witty_update_draw_text(nsstring(state.text()), update_color(state.foreground_color()), msg_rect(self, 'bounds').width)
}

// UpdateBadge.swift: the source's 14-point symbol, clamped progress ring with
// 2-point round stroke, and checking-only 2.5-second continuous rotation.
fn update_badge_view() ObjId {
	mut cls := get_class('WittyUpdateBadge')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyUpdateBadge'), 0)
		add_method(cls, 'drawRect:', voidptr(update_badge_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(cls)
	}
	// Leave one point around the symbol for the centered ring stroke.
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:',
		objc_rect(7, 6, update_ring_view_size, update_ring_view_size))
	msg_void_bool(view, 'setWantsLayer:', true)
	return view
}

fn (state UpdateState) ring_progress() ?f64 {
	if state.kind == .extracting {
		progress := state.extraction_progress
		return if progress > 0 { math.min(progress, 1) } else { 0.0 }
	}
	if state.kind == .downloading {
		if expected := state.expected_length {
			if expected > 0 {
				return math.min(f64(state.downloaded) / f64(expected), 1)
			}
		}
	}
	return none
}

fn update_badge_draw(self ObjId, _cmd Sel, _rect ObjCRect) {
	if g_update_controller == unsafe { nil } { return }
	state := g_update_controller.state
	if progress := state.ring_progress() {
		update_badge_draw_ring(self,
			g_update_controller.ring_transition.progress_at(progress, time.sys_mono_now()))
		return
	}
	if icon := state.icon_name() {
		image := msg_id2(get_class('NSImage'), 'imageWithSystemSymbolName:accessibilityDescription:', nsstring(icon), nsstring(state.text()))
		colors := [voidptr(update_color(state.icon_color()))]
		configuration := msg_id1(get_class('NSImageSymbolConfiguration'), 'configurationWithPaletteColors:', C.witty_macos_array(colors.data, 1))
		colored := msg_id1(image, 'imageWithSymbolConfiguration:', configuration)
		msg_void_rect(colored, 'drawInRect:', objc_rect(1, 1, 14, 14))
	}
}

fn update_badge_draw_ring(view ObjId, progress f64) {
	context := native_canvas_overlay_context()
	if is_nil(context) {
		return
	}
	scale := view_backing_scale(voidptr(view))
	size := int(math.round(update_ring_view_size * scale))
	mut opacity := f64(0)
	color := C.witty_canvas_resolve_srgb_alpha(view, update_color('primary'), &opacity)
	raster := update_ring_raster(size, progress, opacity) or { return }
	image := C.witty_canvas_make_alpha_image(raster.pixels.data, size, size, color, view)
	if is_nil(image) {
		return
	}
	bounds := msg_rect(view, 'bounds')
	C.witty_canvas_present_tile(context, image, &bounds, 1)
	C.CFRelease(image)
}

fn update_ring_raster(size int, progress f64, opacity f64) !canvas.RasterSurface {
	mut raster := canvas.new_raster_surface(width: size, height: size)!
	angle := progress * 2 * math.pi
	end_x := math.sin(angle) * update_ring_radius
	end_y := math.cos(angle) * update_ring_radius
	inner_sq := (update_ring_radius - update_ring_half_stroke) * (update_ring_radius - update_ring_half_stroke)
	outer_sq := (update_ring_radius + update_ring_half_stroke) * (update_ring_radius + update_ring_half_stroke)
	samples := update_ring_samples * update_ring_samples
	point_per_sample := f64(update_ring_view_size) / (size * update_ring_samples)
	for row in 0 .. size {
		for column in 0 .. size {
			mut track := 0
			mut arc := 0
			for sy in 0 .. update_ring_samples {
				y := update_ring_view_size / 2 - (row * update_ring_samples + sy + 0.5) * point_per_sample
				for sx in 0 .. update_ring_samples {
					x := (column * update_ring_samples + sx + 0.5) * point_per_sample - update_ring_view_size / 2
					radius_sq := x * x + y * y
					on_track := radius_sq >= inner_sq && radius_sq <= outer_sq
					if on_track {
						track++
					}
					if progress == 0 || radius_sq > outer_sq {
						continue
					}
					// The stroke starts at twelve o'clock and advances clockwise.
					before_end := x * end_y <= y * end_x
					in_sweep := if progress <= 0.5 { x >= 0 && before_end } else { x >= 0 || before_end }
					start_y := y - update_ring_radius
					cap_x := x - end_x
					cap_y := y - end_y
					cap_sq := update_ring_half_stroke * update_ring_half_stroke
					if (on_track && (progress == 1 || in_sweep))
						|| x * x + start_y * start_y <= cap_sq || cap_x * cap_x + cap_y * cap_y <= cap_sq {
						arc++
					}
				}
			}
			track_alpha := f64(track) / samples * opacity * 0.2
			arc_alpha := f64(arc) / samples * opacity
			alpha := arc_alpha + track_alpha * (1 - arc_alpha)
			raster.pixels[row * size + column] = u32(math.round(alpha * 255)) << 24
		}
	}
	return raster
}
