module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/action_palette_row_darwin.h"

fn C.witty_palette_row_text_width(text ObjId, size f64, medium bool) f64
fn C.witty_palette_draw_canvas_text(context voidptr, text ObjId, color ObjId, matches ObjId, accent ObjId, size f64, medium bool, baseline f64, clip &ObjCRect, bounds &ObjCRect, pixels &u32, width int, height int)
fn C.witty_palette_row_symbol(name ObjId, x f64, height f64, frame &ObjCRect, width &f64) ObjId

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
	height := if option.row_subtitle().len == 0 {
		palette_title_height
	} else {
		palette_title_height + palette_subtitle_spacing + palette_subtitle_height
	}
	badge := option.badge or { '' }
	return (if badge.len > 0 { math.max(height, palette_badge_height) } else { height }) +
		2 * palette_row_padding
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
	draw_palette_text(context, nsstring('No matches'), ink, objc_rect(16, 0, frame.width - 32,
		frame.height), 29)
}

@[params]
struct PaletteTextOptions {
	size    f64 = 13
	medium  bool
	matches ObjId
	accent  ObjId
}

fn draw_palette_text(context voidptr, text ObjId, color ObjId, clip ObjCRect, baseline f64, opts PaletteTextOptions) {
	if clip.width <= 0 { return }
	mut bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, &clip, &bounds, &width, &height)
	mut raster := canvas.new_raster_surface(width: width, height: height) or { return }
	C.witty_palette_draw_canvas_text(context, text, color, opts.matches, opts.accent, opts.size,
		opts.medium, baseline, &clip, &bounds, raster.pixels.data, width, height)
}

fn draw_palette_row_mask(context voidptr, view ObjId, frame ObjCRect, scale f64, radius f64, opts NativeCanvasRoundedMaskOptions, color u32) {
	width := int(math.round(frame.width * scale))
	height := int(math.round(frame.height * scale))
	mask := native_canvas_rounded_mask(width, height, radius * scale, opts) or { return }
	native_canvas_draw_mask(context, view, frame, mask, color)
}

fn draw_palette_row_swatch(context voidptr, view ObjId, frame ObjCRect, scale f64, color ObjId) {
	size := int(math.round(frame.width * scale))
	style := if size == 16 { NativeCanvasRoundedStyle.segmented_circle } else { .circular }
	mask := native_canvas_rounded_mask(size, size, size / 2.0, style: style) or { return }
	image := C.witty_canvas_make_native_color_mask(mask.pixels.data, size, size, view, color)
	if is_nil(image) { return }
	C.witty_canvas_present_tile(context, image, &frame, 1)
	C.CFRelease(image)
}

fn draw_palette_shortcuts(context voidptr, symbols []string, color ObjId, right f64, left f64, height f64, scale f64) f64 {
	if symbols.len == 0 { return right }
	mut widths := []f64{cap: symbols.len}
	mut width := f64(symbols.len - 1)
	for symbol in symbols {
		text_width := C.witty_palette_row_text_width(nsstring(symbol), 13, false)
		widths << text_width
		width += math.max(13.0, math.ceil(text_width * scale) / scale)
	}
	start := right - width
	if start - palette_row_padding <= left { return right }

	mut x := start
	baseline := math.round(((height - palette_title_height) / 2 + 13) * scale) / scale
	for i, symbol in symbols {
		cell := math.max(13.0, math.ceil(widths[i] * scale) / scale)
		centered := math.round((x + (cell - widths[i]) / 2) * scale) / scale
		draw_palette_text(context, nsstring(symbol), color, objc_rect(centered, 0, cell, height),
			baseline)
		x += cell + 1
	}
	return start - palette_row_padding
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
		draw_palette_row_swatch(context, view, objc_rect(x, (bounds.height - 8) / 2, 8, 8),
			scale, ObjId(leading))
		x += 8 + palette_row_padding
	}
	if option.leading_icon.len > 0 {
		mut frame := ObjCRect{}
		mut width := 0.0
		symbol := C.witty_palette_row_symbol(nsstring(option.leading_icon), x, bounds.height, &frame, &width)
		if !is_nil(symbol) {
			tint := if option.emphasis { accent_color } else { secondary_color }
			native_canvas_draw_symbol(context, view, symbol, frame, tint)
			if width > 0 { x += width + palette_row_padding }
		}
	}
	mut right := draw_palette_shortcuts(context, option.symbols, secondary_color,
		bounds.width - palette_row_padding, x, bounds.height, scale)
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
				draw_palette_text(context, text, accent_color,
					objc_rect(badge_x + 7, 0, width - 14, bounds.height), y + 13, size: 10, medium: true)
				right = badge_x - palette_row_padding
			}
		}
	}
	query := nsstring(palette.query)
	title := nsstring(option.title)
	subtitle := option.row_subtitle()
	title_matches := C.witty_palette_match_ranges(title, query)
	title_baseline := if subtitle.len > 0 {
		palette_row_padding + palette_title_height - 3
	} else {
		(bounds.height - palette_title_height) / 2 + 13
	}
	clip := objc_rect(x, 0, right - x, bounds.height)
	draw_palette_text(context, title, msg_id(colors, 'labelColor'), clip, title_baseline,
		medium: option.emphasis, matches: title_matches, accent: accent_color)
	if subtitle.len > 0 {
		text := nsstring(subtitle)
		matches := if is_nil(title_matches) {
			C.witty_palette_match_ranges(text, query)
		} else {
			nil_obj()
		}
		draw_palette_text(context, text, secondary_color, clip, bounds.height - palette_row_padding - 3,
			size: 10, matches: matches, accent: accent_color)
	}
}
