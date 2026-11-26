module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/action_key_indicator_darwin.h"

fn C.witty_key_indicator_width(text ObjId, keycap bool) f64
fn C.witty_key_indicator_rasterize_text(text ObjId, keycap bool, clip &ObjCRect, bounds &ObjCRect, pixels &u32, width int, height int) voidptr
fn C.witty_key_indicator_symbol(chevron bool, x f64, height f64, frame &ObjCRect) ObjId

enum KeyIndicatorPartKind {
	keyboard
	chevron
	table
	divider
	keycap
}

struct KeyIndicatorPart {
	kind  KeyIndicatorPartKind
	x     f64
	width f64
	label string
}

fn (mut surface NativeActionSurface) initialize_key_indicator() {
	mut cls := get_class('WittyKeyIndicator')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSButton'), cstr('WittyKeyIndicator'), 0)
		add_ptr_ivar(cls, 'state')
		add_method(cls, 'mouseDown:', voidptr(key_indicator_down), 'v@:@')
		add_method(cls, 'mouseDragged:', voidptr(key_indicator_dragged), 'v@:@')
		add_method(cls, 'mouseUp:', voidptr(key_indicator_up), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	mut ink_class := get_class('WittyKeyIndicatorInk')
	if is_nil(ink_class) {
		ink_class = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyKeyIndicatorInk'), 0)
		add_ptr_ivar(ink_class, 'state')
		add_method(ink_class, 'drawRect:', voidptr(key_indicator_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(ink_class, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(ink_class)
	}
	frame := objc_rect(0, 0, 0, 28)
	button := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', frame)
	surface.key_badge = button
	C.macos_objc_set_ptr_ivar(button, cstr('state'), voidptr(surface))
	msg_void_bool(button, 'setBordered:', false)
	msg_void_bool(button, 'setTransparent:', true)
	msg_void_bool(button, 'setClipsToBounds:', false)
	msg_void_bool(button, 'setWantsLayer:', true)
	msg_void1(button, 'setAccessibilityLabel:', nsstring('Keyboard state'))
	msg_void1(surface.overlay, 'addSubview:', button)
	msg_void(button, 'release')

	root := msg_id(button, 'layer')
	surface.key_shadow = msg_id(get_class('CALayer'), 'layer')
	msg_void_f64(surface.key_shadow, 'setZPosition:', -1)
	msg_void1(root, 'addSublayer:', surface.key_shadow)
	surface.key_material = native_canvas_material_view(frame)
	surface.key_ink = msg_id_rect(msg_id(ink_class, 'alloc'), 'initWithFrame:', frame)
	C.macos_objc_set_ptr_ivar(surface.key_ink, cstr('state'), voidptr(surface))
	msg_void_bool(surface.key_ink, 'setWantsLayer:', true)
	for view in [surface.key_material, surface.key_ink] {
		msg_void_u64(view, 'setAutoresizingMask:', 18)
		msg_void1(button, 'addSubview:', view)
		msg_void(view, 'release')
	}
	ink_layer := msg_id(surface.key_ink, 'layer')
	for i in 0 .. 3 {
		dot := msg_id(get_class('CALayer'), 'layer')
		msg_void_bool(dot, 'setHidden:', true)
		msg_void1(ink_layer, 'addSublayer:', dot)
		surface.key_dots[i] = dot
	}
}

fn (mut surface NativeActionSurface) rebuild_key_layout(scale f64) {
	surface.previous_sequence = surface.key_sequence.clone()
	surface.previous_tables = surface.key_tables.clone()
	surface.key_layout_scale = scale
	surface.key_parts.clear()
	mut x := 12.0
	for i, table in surface.key_tables {
		kind := if i == 0 { KeyIndicatorPartKind.keyboard } else { .chevron }
		icon_width := if i == 0 { 19.5 } else { 8.0 }
		surface.key_parts << KeyIndicatorPart{kind: kind, x: x, width: icon_width}
		x += icon_width + 5
		width := math.ceil(C.witty_key_indicator_width(nsstring(table), false) * scale) / scale
		surface.key_parts << KeyIndicatorPart{kind: .table, x: x, width: width, label: table}
		x += width + 5
	}
	if surface.key_tables.len > 0 { x -= 5 }
	if surface.key_tables.len > 0 && surface.key_sequence.len > 0 {
		x += 8
		surface.key_parts << KeyIndicatorPart{kind: .divider, x: x, width: 1}
		x += 9
	}
	for key in surface.key_sequence {
		width := math.ceil(C.witty_key_indicator_width(nsstring(key), true) * scale) / scale + 10
		surface.key_parts << KeyIndicatorPart{kind: .keycap, x: x, width: width, label: key}
		x += width + 4
	}
	surface.key_dot_start = x
	surface.key_width = x + 12
	if surface.key_sequence.len > 0 { surface.key_width += 16 }
}

fn (mut surface NativeActionSurface) refresh_key_visuals() {
	if is_nil(surface.key_badge) { return }
	sequence := surface.key_sequence.len > 0
	available := view_width(surface.view) - 16
	visible := (surface.key_tables.len > 0 || sequence) && available > 0
	msg_void_bool(surface.key_badge, 'setHidden:', !visible)
	if !visible || !sequence {
		msg_void(surface.pulse_timer, 'invalidate')
		surface.pulse_timer = nil_obj()
	}
	if !visible { return }

	scale := view_backing_scale(surface.view)
	layout_changed := surface.key_layout_scale != scale || surface.previous_sequence != surface.key_sequence
		|| surface.previous_tables != surface.key_tables
	if layout_changed { surface.rebuild_key_layout(scale) }
	width := math.floor(math.min(available, surface.key_width) * scale) / scale
	height := if sequence { 31.0 } else { 28.0 }
	x := math.round((view_width(surface.view) - width) / 2 * scale) / scale
	y := if surface.key_top { 8.0 } else { view_height(surface.view) - height - 8 }
	msg_void_rect(surface.key_badge, 'setFrame:', objc_rect(x, y + surface.key_drag_offset, width, height))
	if surface.key_surface_size != objc_size(width, height) || surface.key_surface_scale != scale {
		surface.update_key_backdrop(width, height, scale)
	}
	if layout_changed {
		for i, dot in surface.key_dots {
			msg_void_rect(dot, 'setFrame:', objc_rect(surface.key_dot_start + i * 6, (height - 4) / 2, 4, 4))
			msg_void_bool(dot, 'setHidden:', !sequence)
		}
		surface.update_key_colors()
	}
	surface.animate_key_dots()
	if sequence && is_nil(surface.pulse_timer) {
		surface.pulse_timer = C.witty_action_timer(1.0 / 60, surface.owner, sel('pulseTimer:'), nil_obj(), true)
	}
}

fn (mut surface NativeActionSurface) update_key_backdrop(width f64, height f64, scale f64) {
	mask := native_canvas_rounded_mask(int(math.round(width * scale)), int(math.round(height * scale)),
		height * scale / 2, style: .continuous_capsule) or { return }
	if !native_canvas_mask_material(surface.key_material, width, height, mask) { return }
	// SwiftUI's Gaussian shadow extends to twice its blur radius.
	shadow := native_canvas_shadow_mask(mask, 8 * scale, 0.2, cutoff: 2) or { return }
	image := C.witty_canvas_make_alpha_image(shadow.pixels.data, shadow.width, shadow.height, 0,
		surface.key_ink)
	if is_nil(image) { return }
	pad := (shadow.width - mask.width) / (2 * scale)
	root := msg_id(surface.key_badge, 'layer')
	offset := if msg_bool(root, 'isGeometryFlipped') { 2.0 } else { -2.0 }
	msg_void_rect(surface.key_shadow, 'setFrame:', objc_rect(-pad, -pad + offset,
		shadow.width / scale, shadow.height / scale))
	msg_void1(surface.key_shadow, 'setContents:', ObjId(image))
	C.CFRelease(image)
	surface.key_surface_size = objc_size(width, height)
	surface.key_surface_scale = scale
	msg_void_bool(surface.key_ink, 'setNeedsDisplay:', true)
}

fn (surface &NativeActionSurface) update_key_colors() {
	msg_void_bool(surface.key_ink, 'setNeedsDisplay:', true)
	if surface.key_sequence.len == 0 || is_nil(surface.key_ink) { return }
	scale := view_backing_scale(surface.view)
	size := int(math.round(4 * scale))
	mut opacity := 0.0
	color := C.witty_canvas_resolve_srgb_alpha(surface.key_ink,
		msg_id(get_class('NSColor'), 'secondaryLabelColor'), &opacity)
	disk := native_canvas_rounded_mask(size, size, size / 2.0, opacity: opacity) or { return }
	image := C.witty_canvas_make_alpha_image(disk.pixels.data, size, size, color, surface.key_ink)
	if is_nil(image) { return }
	for dot in surface.key_dots { msg_void1(dot, 'setContents:', ObjId(image)) }
	C.CFRelease(image)
}

fn (surface &NativeActionSurface) animate_key_dots() {
	if surface.key_dragging || surface.key_sequence.len == 0 { return }
	now := msg_f64(msg_id(get_class('NSDate'), 'date'), 'timeIntervalSinceReferenceDate')
	surface.apply_key_phase(now)
}

fn (surface &NativeActionSurface) apply_key_phase(phase f64) {
	for i, dot in surface.key_dots {
		opacity := 0.3 + 0.7 * ((math.sin((phase + f64(i) / 3) * math.pi * 2) + 1) / 2)
		C.witty_macos_msg_void_f32(dot, sel('setOpacity:'), f32(opacity))
	}
}

fn key_indicator_draw(self ObjId, _cmd Sel, _rect ObjCRect) {
	surface := action_owner_state(self) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	bounds := msg_rect(self, 'bounds')
	scale := view_backing_scale(surface.view)
	w := int(math.round(bounds.width * scale))
	h := int(math.round(bounds.height * scale))
	mut opacity := 0.0
	primary := C.witty_canvas_resolve_srgb_alpha(self, msg_id(get_class('NSColor'), 'labelColor'), &opacity)
	stroke := native_canvas_capsule_stroke(w, h, scale, 0.15 * opacity) or { return }
	native_canvas_draw_mask(context, self, bounds, stroke, primary)
	for part in surface.key_parts {
		if part.x >= bounds.width { break }
		match part.kind {
			.keyboard, .chevron {
				chevron := part.kind == .chevron
				mut frame := ObjCRect{}
				symbol := C.witty_key_indicator_symbol(chevron, part.x, bounds.height, &frame)
				tint := msg_id(get_class('NSColor'), if chevron { 'tertiaryLabelColor' } else { 'secondaryLabelColor' })
				native_canvas_draw_symbol(context, self, symbol, frame, tint)
			}
			.table {
				draw_indicator_text(context, part.label, false, part.x, part.width, bounds)
			}
			.keycap {
				draw_indicator_keycap(self, context, part, bounds, scale, primary, 0.15 * opacity)
			}
			.divider {
				draw_indicator_divider(self, context, part.x, bounds.height)
			}
		}
	}
}

fn draw_indicator_keycap(view ObjId, context voidptr, part KeyIndicatorPart, badge ObjCRect, scale f64, primary u32, opacity f64) {
	y := (badge.height - 19) / 2
	frame := objc_rect(part.x, y, part.width, 19)
	w := int(math.round(frame.width * scale))
	h := int(math.round(frame.height * scale))
	mask := native_canvas_continuous_rect(w, h, scale, 4, 0, 1) or { return }
	shadow := native_canvas_shadow_mask(mask, 0.5 * scale, 0.12, cutoff: 2) or { return }
	pad := (shadow.width - mask.width) / (2 * scale)
	native_canvas_draw_mask(context, view, objc_rect(frame.x - pad, y - pad + 0.5,
		shadow.width / scale, shadow.height / scale), shadow, 0)
	fill := C.witty_canvas_resolve_srgb(view, msg_id(get_class('NSColor'), 'controlBackgroundColor'))
	native_canvas_draw_mask(context, view, frame, mask, fill)
	stroke := native_canvas_continuous_rect(w, h, scale, 4, 0.5, opacity) or { return }
	native_canvas_draw_mask(context, view, frame, stroke, primary)
	draw_indicator_text(context, part.label, true, part.x + 5, part.width - 10, badge)
}

fn draw_indicator_text(context voidptr, text string, keycap bool, x f64, width f64, badge ObjCRect) {
	visible := math.min(width, badge.width - x)
	if visible <= 0 { return }
	clip := objc_rect(x, 0, visible, badge.height)
	mut bounds := ObjCRect{}
	mut w, mut h := 0, 0
	C.witty_canvas_pixel_bounds(context, &clip, &bounds, &w, &h)
	mut raster := canvas.new_raster_surface(width: w, height: h) or { return }
	image := C.witty_key_indicator_rasterize_text(nsstring(text), keycap, &clip, &bounds,
		raster.pixels.data, w, h)
	if is_nil(image) { return }
	C.witty_canvas_present_tile(context, image, &bounds, 1)
	C.CFRelease(image)
}

fn draw_indicator_divider(view ObjId, context voidptr, x f64, badge_height f64) {
	color := C.witty_canvas_resolve_srgb(view, msg_id(get_class('NSColor'), 'separatorColor'))
	tile := native_canvas_fill_tile(color, target: view, opacity: 0.1)
	if is_nil(tile) { return }
	frame := objc_rect(x, (badge_height - 14) / 2, 1, 14)
	C.witty_canvas_present_tile(context, tile, &frame, 1)
	C.CFRelease(tile)
}

fn key_indicator_down(self ObjId, _cmd Sel, event ObjId) {
	mut surface := action_owner_state(self) or { return }
	surface.key_drag_start = msg_point(event, 'locationInWindow').y
	surface.key_drag_offset = 0
	surface.key_dragging = false
}

fn key_indicator_dragged(self ObjId, _cmd Sel, event ObjId) {
	mut surface := action_owner_state(self) or { return }
	surface.key_dragging = true
	surface.key_drag_offset = surface.key_drag_start - msg_point(event, 'locationInWindow').y
	surface.refresh_key_visuals()
}

fn key_indicator_up(self ObjId, _cmd Sel, _event ObjId) {
	mut surface := action_owner_state(self) or { return }
	if !surface.key_dragging {
		action_key_info(surface.owner, nil_obj(), self)
		return
	}
	if !surface.key_top && surface.key_drag_offset < -50 {
		surface.key_top = true
	} else if surface.key_top && surface.key_drag_offset > 50 {
		surface.key_top = false
	}
	surface.key_dragging = false
	surface.key_drag_offset = 0
	surface.refresh_key_visuals()
}
