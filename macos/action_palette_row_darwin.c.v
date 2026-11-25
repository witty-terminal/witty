module macos

import math

#insert "@VMODROOT/macos/action_palette_row_darwin.h"

fn C.witty_palette_row_text_width(text ObjId, size f64, medium bool) f64
fn C.witty_palette_draw_row_text(context voidptr, text ObjId, color ObjId, size f64, medium bool, x f64, baseline f64, width f64, height f64)
fn C.witty_palette_draw_row_symbol(context voidptr, name ObjId, tint voidptr, x f64, height f64) f64
fn C.witty_palette_draw_swatch(context voidptr, frame &ObjCRect, mask voidptr, color ObjId)

const palette_row_padding = 8.0
const palette_row_gap = 4.0
const palette_row_radius = 5.0
const palette_title_height = 16.0
const palette_subtitle_height = 13.0
const palette_subtitle_spacing = 2.0
const palette_badge_height = 19.0
// The CommandRow corner clip darkens fractional coverage at the outside edge.
const palette_clip_gamma = 2.2

fn (option NativeCommandOption) row_subtitle() string {
	return if option.subtitle.len > 0 { option.subtitle } else { option.description }
}

fn (option NativeCommandOption) row_height() f64 {
	height := palette_title_height + 2 * palette_row_padding
	return if option.row_subtitle().len == 0 {
		height
	} else {
		height + palette_subtitle_spacing + palette_subtitle_height
	}
}

fn new_palette_row(palette &NativeCommandPalette, index int, frame ObjCRect) ObjId {
	mut cls := get_class('WittyPaletteRow')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSButton'), cstr('WittyPaletteRow'), 0)
		add_ptr_ivar(cls, 'palette')
		add_method(cls, 'drawRect:', voidptr(palette_draw_row), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(cls, 'viewDidChangeEffectiveAppearance', voidptr(palette_row_restyle), 'v@:')
		C.macos_objc_register_class_pair(cls)
	}
	row := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', frame)
	C.macos_objc_set_ptr_ivar(row, cstr('palette'), voidptr(palette))
	option := palette.filtered[index]
	msg_void1(row, 'setTitle:', nsstring(option.title))
	msg_void_bool(row, 'setBordered:', false)
	msg_void1(row, 'setToolTip:', nsstring(option.description))
	msg_void1(row, 'setTarget:', palette.owner)
	msg_void1(row, 'setAction:', sel('submit:'))
	msg_void_u64(row, 'setTag:', u64(index))
	msg_void_u64(row, 'setAutoresizingMask:', 2)
	msg_void_bool(row, 'setWantsLayer:', true)
	msg_void_u64(row, 'setLayerContentsRedrawPolicy:', 2)
	if !is_nil(palette.owner) {
		tag := msg_id_u64(get_class('NSNumber'), 'numberWithUnsignedInteger:', u64(index))
		info := msg_id2(get_class('NSDictionary'), 'dictionaryWithObject:forKey:', tag, nsstring('row'))
		tracking := msg_id_rect_u64_obj_obj(alloc('NSTrackingArea'), 'initWithRect:options:owner:userInfo:',
			msg_rect(row, 'bounds'), 1 | 128 | 512, palette.owner, info)
		msg_void1(row, 'addTrackingArea:', tracking)
		msg_void(tracking, 'release')
	}
	return row
}

fn palette_row_restyle(view ObjId, _cmd Sel) {
	view_super_void(view, 'WittyPaletteRow', 'viewDidChangeEffectiveAppearance')
	msg_void_bool(view, 'setNeedsDisplay:', true)
}

fn new_palette_empty_message(frame ObjCRect) ObjId {
	mut cls := get_class('WittyPaletteEmptyMessage')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyPaletteEmptyMessage'), 0)
		add_method(cls, 'isFlipped', voidptr(action_flipped), 'B@:')
		add_method(cls, 'drawRect:', voidptr(palette_draw_empty_message), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		C.macos_objc_register_class_pair(cls)
	}
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', frame)
	msg_void_u64(view, 'setAutoresizingMask:', 2)
	msg_void_bool(view, 'setAccessibilityElement:', true)
	msg_void1(view, 'setAccessibilityRole:', nsstring('AXStaticText'))
	msg_void1(view, 'setAccessibilityValue:', nsstring('No matches'))
	return view
}

fn palette_draw_empty_message(view ObjId, _cmd Sel, _rect ObjCRect) {
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	frame := msg_rect(view, 'bounds')
	ink := msg_id(get_class('NSColor'), 'secondaryLabelColor')
	C.witty_palette_draw_row_text(context, nsstring('No matches'), ink, 13, false, 16, 29,
		frame.width - 32, frame.height)
}

fn draw_palette_row_mask(context voidptr, view ObjId, frame ObjCRect, scale f64, radius f64, opts NativeCanvasRoundedMaskOptions, color u32) {
	width := int(math.round(frame.width * scale))
	height := int(math.round(frame.height * scale))
	mask := native_canvas_rounded_mask(width, height, radius * scale, opts) or { return }
	native_canvas_draw_mask(context, view, frame, mask, color)
}

fn draw_palette_row_swatch(context voidptr, frame ObjCRect, scale f64, color ObjId) {
	size := int(math.round(frame.width * scale))
	mask := native_canvas_rounded_mask(size, size, frame.width * scale / 2) or { return }
	image := C.witty_canvas_make_alpha_image(mask.pixels.data, size, size, 0xffffff, nil_obj())
	if is_nil(image) { return }
	C.witty_palette_draw_swatch(context, &frame, image, color)
	C.CFRelease(image)
}

fn palette_draw_row(view ObjId, _cmd Sel, _rect ObjCRect) {
	palette := palette_state(view) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	index := int(msg_u64(view, 'tag'))
	if index < 0 || index >= palette.filtered.len { return }
	option := palette.filtered[index]
	bounds := msg_rect(view, 'bounds')
	scale := view_backing_scale(voidptr(view))
	colors := get_class('NSColor')
	accent_color := msg_id(colors, 'controlAccentColor')
	accent := C.witty_canvas_resolve_srgb(view, accent_color)
	secondary_color := msg_id(colors, 'secondaryLabelColor')
	mut secondary_alpha := 0.0
	secondary := C.witty_canvas_resolve_srgb_alpha(view, secondary_color, &secondary_alpha)
	selected := if n := palette.selected {
		index == if n < uint(palette.filtered.len) { int(n) } else { palette.filtered.len - 1 }
	} else {
		false
	}
	hovered := if n := palette.hovered { index == int(n) } else { false }
	if selected {
		draw_palette_row_mask(context, view, bounds, scale, palette_row_radius,
			NativeCanvasRoundedMaskOptions{ style: .continuous, opacity: 0.2, outer_coverage_gamma: palette_clip_gamma }, accent)
	} else if hovered {
		draw_palette_row_mask(context, view, bounds, scale, palette_row_radius,
			NativeCanvasRoundedMaskOptions{ style: .continuous, opacity: 0.2 * secondary_alpha, outer_coverage_gamma: palette_clip_gamma }, secondary)
	}
	if option.emphasis && !selected {
		draw_palette_row_mask(context, view, bounds, scale, palette_row_radius,
			NativeCanvasRoundedMaskOptions{ style: .continuous, opacity: 0.3, stroke: 1.5 * scale, outer_coverage_gamma: palette_clip_gamma }, accent)
	}

	mut x := palette_row_padding
	if leading := option.leading_color {
		draw_palette_row_swatch(context, objc_rect(x, (bounds.height - 8) / 2, 8, 8),
			scale, ObjId(leading))
		x += 8 + palette_row_padding
	}
	if option.leading_icon.len > 0 {
		tint := if option.emphasis {
			native_canvas_fill_tile(accent, target: view)
		} else {
			native_canvas_fill_tile(secondary, target: view, opacity: secondary_alpha)
		}
		if !is_nil(tint) {
			width := C.witty_palette_draw_row_symbol(context, nsstring(option.leading_icon), tint, x,
				bounds.height)
			C.CFRelease(tint)
			if width > 0 { x += width + palette_row_padding }
		}
	}
	mut right := bounds.width - palette_row_padding
	if badge := option.badge {
		if badge.len > 0 {
			text := nsstring(badge)
			width := math.ceil(C.witty_palette_row_text_width(text, 10, true) * scale) / scale + 14
			badge_x := right - width
			if badge_x - palette_row_padding > x {
				y := (bounds.height - palette_badge_height) / 2
				draw_palette_row_mask(context, view, objc_rect(badge_x, y, width, palette_badge_height), scale,
					palette_badge_height / 2,
					NativeCanvasRoundedMaskOptions{ style: .continuous_capsule, opacity: 0.15 }, accent)
				C.witty_palette_draw_row_text(context, text, accent_color, 10, true, badge_x + 7, y + 13,
					width - 14, bounds.height)
				right = badge_x - palette_row_padding
			}
		}
	}
	C.witty_palette_draw_row_text(context, nsstring(option.title), msg_id(colors, 'labelColor'), 13,
		option.emphasis, x, palette_row_padding + palette_title_height - 3, right - x, bounds.height)
	subtitle := option.row_subtitle()
	if subtitle.len > 0 {
		C.witty_palette_draw_row_text(context, nsstring(subtitle), secondary_color, 10, false, x,
			bounds.height - palette_row_padding - 3, right - x, bounds.height)
	}
}
