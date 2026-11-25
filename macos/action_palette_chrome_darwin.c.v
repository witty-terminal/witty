module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/action_palette_chrome_darwin.h"

fn C.witty_canvas_set_image(view ObjId, image voidptr)
fn C.witty_palette_backdrop_layer(plate ObjId) ObjId
fn C.witty_palette_backdrop_appearance(material ObjId, light bool, limit voidptr)
fn C.witty_palette_backdrop_frame(material ObjId, width f64, height f64, scale f64)

const palette_search_height = 48.0
const palette_header_height = palette_search_height + 1
// Panel padding and spacing in TerminalCommandPaletteView.
const palette_top_inset = 24.0
const palette_corner_radius = 10.0
const palette_shadow_offset = 12.0

struct PaletteChrome {
mut:
	plate           ObjId
	material        ObjId
	native_backdrop bool
	opaque_material ObjId
	mask            ObjId
	tint            ObjId
	stroke          ObjId
	divider         ObjId
	shadow          ObjId
	shadow_mask     ObjId
	size            ObjCSize
	scale           f64
	background      ?u32
	border_rgb      u32
	border_alpha    f64
}

fn new_palette_chrome(container ObjId) PaletteChrome {
	frame := msg_rect(container, 'bounds')
	msg_void_bool(container, 'setClipsToBounds:', false)
	msg_void_bool(container, 'setWantsLayer:', true)
	root := msg_id(container, 'layer')
	layer_class := get_class('CALayer')

	shadow := msg_id(layer_class, 'layer')
	shadow_mask := msg_id(layer_class, 'layer')
	msg_void1(shadow, 'setMask:', shadow_mask)
	// Draw the exterior shadow after the material has sampled the terminal.
	msg_void_f64(shadow, 'setZPosition:', 0.5)
	msg_void1(root, 'addSublayer:', shadow)

	plate := msg_id_rect(alloc('WittyPaletteContainer'), 'initWithFrame:', frame)
	msg_void_bool(plate, 'setWantsLayer:', true)
	msg_void1(container, 'addSubview:', plate)
	msg_void(plate, 'release')
	plate_layer := msg_id(plate, 'layer')
	mask := msg_id(layer_class, 'layer')
	msg_void1(plate_layer, 'setMask:', mask)

	mut material := C.witty_palette_backdrop_layer(plate)
	native_backdrop := !is_nil(material)
	if !native_backdrop {
		material = native_canvas_material_view(frame)
		msg_void_u64(material, 'setMaterial:', 21) // NSVisualEffectMaterialUnderWindowBackground.
		msg_void1(plate, 'addSubview:', material)
		msg_void(material, 'release')
	}

	opaque_material := palette_chrome_image(plate, frame)
	tint := palette_chrome_image(plate, frame)
	msg_void1(msg_id(tint, 'layer'), 'setCompositingFilter:', nsstring('colorBlendMode'))
	divider := palette_chrome_image(plate, frame)
	stroke := palette_chrome_image(container, frame)
	msg_void_f64(msg_id(stroke, 'layer'), 'setZPosition:', 1)
	return PaletteChrome{
		plate:           plate
		material:        material
		native_backdrop: native_backdrop
		opaque_material: opaque_material
		mask:            mask
		tint:            tint
		stroke:          stroke
		divider:         divider
		shadow:          shadow
		shadow_mask:     shadow_mask
	}
}

fn palette_chrome_image(parent ObjId, frame ObjCRect) ObjId {
	mut cls := get_class('WittyPaletteChromeImage')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSImageView'), cstr('WittyPaletteChromeImage'), 0)
		add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(cls)
	}
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', frame)
	msg_void_u64(view, 'setImageScaling:', 1) // NSImageScaleAxesIndependently.
	msg_void_bool(view, 'setAccessibilityElement:', false)
	msg_void_bool(view, 'setWantsLayer:', true)
	msg_void1(parent, 'addSubview:', view)
	msg_void(view, 'release')
	return view
}

fn (mut chrome PaletteChrome) layout(container ObjId, width f64, height f64, scale f64, background u32) {
	size := objc_size(width, height)
	frame := objc_rect(0, 0, width, height)
	geometry_changed := chrome.size != size || chrome.scale != scale
	light := (0.299 * f64((background >> 16) & 255) + 0.587 * f64((background >> 8) & 255) +
		0.114 * f64(background & 255)) > 127.5
	if chrome.background != ?u32(background) {
		appearance := if light { 'NSAppearanceNameAqua' } else { 'NSAppearanceNameDarkAqua' }
		msg_void1(container, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		if chrome.native_backdrop {
			// Clamp the material luminosity before applying the terminal tint.
			gray := if light { f32(0.975) } else { f32(0.08) }
			limit := C.witty_canvas_make_srgb_tile(gray, gray, gray, 1)
			C.witty_palette_backdrop_appearance(chrome.material, light, limit)
			if !is_nil(limit) { C.CFRelease(limit) }
		}
		tile := native_canvas_fill_tile(background, target: container)
		if !is_nil(tile) {
			C.witty_canvas_set_image(chrome.tint, tile)
			C.CFRelease(tile)
		}
		// Preblend the tint over SwiftUI's opaque ultra-thin material fill.
		opaque := native_canvas_fill_tile(background,
			target:          container
			blend_over_gray: if light { u8(0xde) } else { u8(0x20) }
		)
		if !is_nil(opaque) {
			C.witty_canvas_set_image(chrome.opaque_material, opaque)
			C.CFRelease(opaque)
		}
		chrome.background = background
		mut divider_alpha := 0.0
		divider_color := C.witty_canvas_resolve_srgb_alpha(container,
			msg_id(get_class('NSColor'), 'quaternaryLabelColor'), &divider_alpha)
		divider := native_canvas_fill_tile(divider_color, target: container, opacity: divider_alpha)
		if !is_nil(divider) {
			C.witty_canvas_set_image(chrome.divider, divider)
			C.CFRelease(divider)
		}
	}
	chrome.set_reduce_transparency(msg_bool(msg_id(get_class('NSWorkspace'), 'sharedWorkspace'),
		'accessibilityDisplayShouldReduceTransparency'))
	if width <= 0 { return }

	width_px := int(math.round(width * scale))
	height_px := int(math.round(height * scale))
	if geometry_changed {
		msg_void_rect(chrome.plate, 'setFrame:', frame)
		if chrome.native_backdrop {
			C.witty_palette_backdrop_frame(chrome.material, width, height, scale)
		} else {
			msg_void_rect(chrome.material, 'setFrame:', frame)
		}
		msg_void_rect(chrome.opaque_material, 'setFrame:', frame)
		msg_void_rect(chrome.mask, 'setFrame:', frame)
		msg_void_rect(chrome.tint, 'setFrame:', frame)
		msg_void_rect(chrome.divider, 'setFrame:', objc_rect(0, palette_search_height, width, 1))
		shape := native_canvas_rounded_mask(width_px, height_px, palette_corner_radius * scale,
			style: .continuous
		) or { return }
		set_palette_mask(chrome.mask, shape, 0xffffff, nil_obj())
		chrome.update_shadow(container, width, height, scale, shape)
	}

	mut opacity := 0.0
	border_color := C.witty_canvas_resolve_srgb_alpha(container,
		msg_id(get_class('NSColor'), 'tertiaryLabelColor'), &opacity)
	if geometry_changed || chrome.border_rgb != border_color || chrome.border_alpha != opacity {
		pad := int(math.ceil(0.5 * scale))
		border := native_canvas_rounded_mask(width_px + 2 * pad, height_px + 2 * pad,
			(palette_corner_radius + 0.5) * scale,
			style:   .continuous
			stroke:  scale
			padding: pad - 0.5 * scale
			opacity: opacity * 0.75
		) or { return }
		msg_void_rect(chrome.stroke, 'setFrame:', objc_rect(-pad / scale, -pad / scale,
			border.width / scale, border.height / scale))
		image := C.witty_canvas_make_alpha_image(border.pixels.data, border.width, border.height,
			border_color, container)
		if !is_nil(image) {
			C.witty_canvas_set_image(chrome.stroke, image)
			C.CFRelease(image)
		}
		chrome.border_rgb = border_color
		chrome.border_alpha = opacity
	}
	chrome.size = size
	chrome.scale = scale
}

fn (chrome &PaletteChrome) set_reduce_transparency(reduce bool) {
	msg_void_bool(chrome.material, 'setHidden:', reduce)
	msg_void_bool(chrome.opaque_material, 'setHidden:', !reduce)
	msg_void_bool(chrome.tint, 'setHidden:', reduce)
}

fn set_palette_mask(layer ObjId, mask canvas.RasterSurface, color u32, target ObjId) {
	image := C.witty_canvas_make_alpha_image(mask.pixels.data, mask.width, mask.height, color, target)
	if !is_nil(image) {
		msg_void1(layer, 'setContents:', ObjId(image))
		C.CFRelease(image)
	}
}

fn (chrome &PaletteChrome) update_shadow(container ObjId, width f64, height f64, scale f64, plate canvas.RasterSurface) {
	// The shadow is smooth at this resolution, including on Retina displays.
	sample_scale := 0.5
	shape := native_canvas_rounded_mask(int(math.ceil(width * sample_scale)),
		int(math.ceil(height * sample_scale)), palette_corner_radius * sample_scale,
		style: .continuous
	) or { return }
	shadow := native_canvas_shadow_mask(shape, 29 * sample_scale, 0.33) or { return }
	pad := (shadow.width - shape.width) / 2 / sample_scale
	offset := if msg_bool(msg_id(container, 'layer'), 'isGeometryFlipped') {
		-palette_shadow_offset
	} else {
		palette_shadow_offset
	}
	msg_void_rect(chrome.shadow, 'setFrame:', objc_rect(-pad, -pad + offset,
		width + 2 * pad, height + 2 * pad))
	set_palette_mask(chrome.shadow, shadow, 0, container)

	// The mask uses the plate's backing scale to keep the rounded edge aligned.
	px_pad := int(math.round(pad * scale))
	mut mask := canvas.new_raster_surface(width: plate.width + 2 * px_pad,
		height: plate.height + 2 * px_pad) or { return }
	mask.clear(0xffffffff)
	plate_y := px_pad - int(math.round(palette_shadow_offset * scale))
	for y in 0 .. plate.height {
		dst := (plate_y + y) * mask.width + px_pad
		src := y * plate.width
		for x in 0 .. plate.width {
			mask.pixels[dst + x] = (255 - (plate.pixels[src + x] >> 24)) * 0x01010101
		}
	}
	msg_void_rect(chrome.shadow_mask, 'setFrame:', msg_rect(chrome.shadow, 'bounds'))
	set_palette_mask(chrome.shadow_mask, mask, 0xffffff, nil_obj())
}
