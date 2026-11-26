module macos

import configpkg
import gg.canvas
import math
import time

#insert "@VMODROOT/macos/action_resize_indicator_darwin.h"

fn C.witty_resize_indicator_timer(interval f64, owner ObjId, selector Sel) ObjId
fn C.witty_resize_indicator_text_width(text ObjId) f64
fn C.witty_resize_indicator_place(view ObjId, parent ObjId)
fn C.witty_resize_indicator_set_mask(view ObjId, pixels &u32, width int, height int, scale f64, shadow bool)
fn C.witty_resize_indicator_set_fill(view ObjId)
fn C.witty_resize_indicator_draw(target voidptr, view ObjId, text ObjId, frame &ObjCRect, pixels &u32, width int, height int)

const resize_indicator_grace = u64(500 * time.millisecond)
const resize_indicator_height = 26.0
const resize_indicator_padding = 5.0

struct NativeResizeIndicator {
mut:
	mode       configpkg.ResizeOverlay = .after_first
	position   configpkg.ResizeOverlayPosition
	duration   u64 = u64(750 * time.millisecond)
	geometry   ObjCSize
	started_at u64
	focused_at u64
	timer      ObjId
	text       string
	container  ObjId
	shadow     ObjId
	fill       ObjId
	ink        ObjId
	mask_size  ObjCSize
	mask_scale f64
	mask_phases int
}

pub fn (mut surface NativeActionSurface) configure_resize_indicator(mode configpkg.ResizeOverlay,
		position configpkg.ResizeOverlayPosition, duration u64) {
	mut indicator := &surface.resize_indicator
	indicator.mode = mode
	indicator.position = position
	indicator.duration = duration
	if mode == .never { surface.hide_resize_indicator() }
	else { surface.layout_resize_indicator() }
}

fn (mut surface NativeActionSurface) note_resize_indicator_focus() {
	surface.resize_indicator.focused_at = time.sys_mono_now()
}

pub fn (mut surface NativeActionSurface) update_resize_indicator(width f64, height f64, columns u16, rows u16) {
	surface.update_resize_indicator_at(ObjCSize{width: width, height: height}, columns, rows,
		time.sys_mono_now())
}

fn (mut surface NativeActionSurface) update_resize_indicator_at(geometry ObjCSize, columns u16, rows u16, now u64) {
	mut indicator := &surface.resize_indicator
	previous := indicator.geometry
	if geometry == previous {
		surface.update_resize_indicator_grid(columns, rows)
		return
	}
	indicator.geometry = geometry
	// The initial geometry starts the grace period and supplies the resize baseline.
	if previous.width == 0 { indicator.started_at = now }
	if indicator.mode == .never || indicator.duration == 0 || columns == 0 || rows == 0
		|| now - indicator.started_at < resize_indicator_grace
		|| (indicator.focused_at != 0 && now - indicator.focused_at < resize_indicator_grace) {
		surface.hide_resize_indicator()
		return
	}
	if !is_nil(indicator.timer) { msg_void(indicator.timer, 'invalidate') }
	indicator.text = '${columns} ⨯ ${rows}'
	indicator.timer = C.witty_resize_indicator_timer(f64(indicator.duration) / time.second,
		surface.owner, sel('resizeIndicatorTimer:'))
	surface.layout_resize_indicator()
}

pub fn (mut surface NativeActionSurface) update_resize_indicator_grid(columns u16, rows u16) {
	if surface.resize_indicator.text.len == 0 || columns == 0 || rows == 0 { return }
	text := '${columns} ⨯ ${rows}'
	if text == surface.resize_indicator.text { return }
	surface.resize_indicator.text = text
	surface.layout_resize_indicator()
}

fn (mut surface NativeActionSurface) hide_resize_indicator() {
	mut indicator := &surface.resize_indicator
	if !is_nil(indicator.timer) { msg_void(indicator.timer, 'invalidate') }
	indicator.timer = nil_obj()
	indicator.text = ''
	if !is_nil(indicator.container) { msg_void_bool(indicator.container, 'setHidden:', true) }
}

fn action_resize_indicator_timer(self ObjId, _cmd Sel, timer ObjId) {
	mut surface := action_owner_state(self) or { return }
	if timer == surface.resize_indicator.timer { surface.hide_resize_indicator() }
}

fn resize_indicator_frame(bounds ObjCRect, width f64, position configpkg.ResizeOverlayPosition, scale f64) ObjCRect {
	x := match position {
		.top_left, .bottom_left { 0.0 }
		.top_right, .bottom_right { bounds.width - width }
		else { (bounds.width - width) / 2 }
	}
	y := match position {
		.top_left, .top_center, .top_right { 0.0 }
		.bottom_left, .bottom_center, .bottom_right { bounds.height - resize_indicator_height }
		.center { (bounds.height - resize_indicator_height) / 2 }
	}
	return objc_rect(math.round(x * scale) / scale, math.round(y * scale) / scale,
		math.round(width * scale) / scale, resize_indicator_height)
}

fn resize_indicator_view(class_name string, parent ObjId) ObjId {
	view := msg_id_rect(alloc(class_name), 'initWithFrame:', ObjCRect{})
	msg_void_bool(view, 'setWantsLayer:', true)
	msg_void1(parent, 'addSubview:', view)
	msg_void(view, 'release')
	return view
}

fn (mut surface NativeActionSurface) setup_resize_indicator_views() {
	mut cls := get_class('WittyResizeIndicator')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyResizeIndicator'), 0)
		add_method(cls, 'isFlipped', voidptr(action_flipped), 'B@:')
		add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(cls)
		ink_class := C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyResizeIndicatorInk'), 0)
		add_method(ink_class, 'drawRect:', voidptr(action_draw_resize_indicator), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		C.macos_objc_register_class_pair(ink_class)
	}
	container := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', ObjCRect{})
	C.witty_resize_indicator_place(container, surface.overlay)
	mut indicator := &surface.resize_indicator
	indicator.container = container
	indicator.shadow = resize_indicator_view('NSView', container)
	indicator.fill = resize_indicator_view('NSView', container)
	indicator.ink = resize_indicator_view('WittyResizeIndicatorInk', container)
	msg_void_bool(indicator.ink, 'setAccessibilityElement:', true)
	msg_void1(indicator.ink, 'setAccessibilityRole:', nsstring('AXStaticText'))
	msg_void(container, 'release')
}

fn (mut surface NativeActionSurface) layout_resize_indicator() {
	if surface.resize_indicator.text.len == 0 { return }
	if is_nil(surface.resize_indicator.container) { surface.setup_resize_indicator_views() }
	mut indicator := &surface.resize_indicator
	text := nsstring(indicator.text)
	bounds := msg_rect(surface.overlay, 'bounds')
	scale := view_backing_scale(surface.view)
	width := math.min(bounds.width, C.witty_resize_indicator_text_width(text) + 2 * resize_indicator_padding)
	frame := resize_indicator_frame(bounds, width, indicator.position, scale)
	msg_void_rect(indicator.container, 'setFrame:', bounds)
	msg_void_rect(indicator.fill, 'setFrame:', frame)
	C.witty_resize_indicator_set_fill(indicator.fill)
	msg_void_rect(indicator.ink, 'setFrame:', frame)
	msg_void1(indicator.ink, 'setAccessibilityLabel:', text)
	// Reusing the AppKit text backing can change its color rounding.
	msg_void1(msg_id(indicator.ink, 'layer'), 'setContents:', nil_obj())
	msg_void_bool(indicator.ink, 'setNeedsDisplay:', true)
	msg_void_bool(indicator.container, 'setHidden:', false)
	mask_size := ObjCSize{width: frame.width, height: frame.height}
	phases := C.witty_canvas_backing_phases(indicator.fill)
	if mask_size != indicator.mask_size || scale != indicator.mask_scale || phases != indicator.mask_phases {
		w := int(math.round(frame.width * scale))
		h := int(math.round(frame.height * scale))
		mask := native_canvas_grouped_continuous_rect(w, h, scale, 4, phases) or { return }
		if shadow := native_canvas_shadow_mask(mask, 3 * scale, 1.0 / 3) {
			pad := f64(shadow.width - w) / (2 * scale)
			msg_void_rect(indicator.shadow, 'setFrame:', objc_rect(frame.x - pad, frame.y - pad,
				shadow.width / scale, shadow.height / scale))
			C.witty_resize_indicator_set_mask(indicator.shadow, shadow.pixels.data, shadow.width,
				shadow.height, scale, true)
		}
		C.witty_resize_indicator_set_mask(indicator.fill, mask.pixels.data, w, h, scale, false)
		indicator.mask_size = mask_size
		indicator.mask_scale = scale
		indicator.mask_phases = phases
	} else {
		shadow_frame := msg_rect(indicator.shadow, 'frame')
		pad := (shadow_frame.width - frame.width) / 2
		msg_void_rect(indicator.shadow, 'setFrame:', objc_rect(frame.x - pad, frame.y - pad,
			shadow_frame.width, shadow_frame.height))
	}
}

fn action_draw_resize_indicator(view ObjId, _cmd Sel, _rect ObjCRect) {
	surface := action_owner_state(msg_id(msg_id(view, 'superview'), 'superview')) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	text := nsstring(surface.resize_indicator.text)
	frame := msg_rect(view, 'bounds')
	scale := view_backing_scale(surface.view)
	w := int(math.round(frame.width * scale))
	h := int(math.round(frame.height * scale))
	raster := canvas.new_raster_surface(width: w, height: h) or { return }
	C.witty_resize_indicator_draw(context, view, text, &frame, raster.pixels.data, w, h)
}
