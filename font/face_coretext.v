module font

import gg.canvas
import log
import macos
import math
import opentype
import quirks
import harfbuzz

// CoreText-based font face implementation for macOS.
//
// A CoreTextFace represents a single font face backed by Apple's CoreText
// framework. It provides glyph lookup, rendering, metrics, and table access.
//
// This is the macOS equivalent of the FreeType-based Face in face.v.
// Translated from ghostty/src/font/face/coretext.zig

// copy_coretext_font_with_size returns a retained copy of a native CoreText
// font. It returns nil on non-Darwin targets or for a non-CoreText face.
pub fn copy_coretext_font_with_size(font_ptr voidptr, size f64) voidptr {
	if isnil(font_ptr) {
		return unsafe { nil }
	}
	$if macos || ios {
		ct_font := unsafe { &macos.CTFont(font_ptr) }
		copy := ct_font.copy_with_attributes(size, unsafe { nil }, unsafe { nil }) or {
			return unsafe { nil }
		}
		return voidptr(copy)
	} $else {
		return unsafe { nil }
	}
}

// release_coretext_font releases a font returned by
// copy_coretext_font_with_size.
pub fn release_coretext_font(font_ptr voidptr) {
	if !isnil(font_ptr) {
		$if macos || ios {
			macos.cf_release(font_ptr)
		}
	}
}

// ============================================================
// CoreTextFace
// ============================================================

// CoreTextFace is a font face backed by Apple's CoreText framework.
pub struct CoreTextFace {
pub mut:
	// Our font face (CoreText CTFont). Stored as voidptr because
	// V's C interop treats Objective-C/CoreFoundation objects opaquely.
	ct_font voidptr = unsafe { nil }

	// Harfbuzz font corresponding to this face. We only use this
	// if we're using Harfbuzz.
	hb_font harfbuzz.Font

	// Set quirks.disableDefaultFontFeatures
	quirks_disable_default_font_features bool

	// True if this font face should be rasterized with a synthetic bold
	// effect. This is used for fonts that don't have a bold variant.
	synthetic_bold ?f64

	// If the face can possibly be colored, then this is the state
	// used to check for color information. This is null if the font
	// can't possibly be colored (i.e. doesn't have SVG, sbix, etc
	// tables).
	color ?ColorState

	// The current size this font is set to.
	size DesiredSize
}

// True if our build is using Harfbuzz. If we're not, we can avoid
// some Harfbuzz-specific code paths.
pub const coretext_harfbuzz_shaper = Backend.selected_().has_harfbuzz()

// The matrix applied to a regular font to auto-italicize it.
// This is an affine transform with a shear of approximately tan(15 degrees).
pub const italic_skew_a = f64(1)
pub const italic_skew_b = f64(0)
pub const italic_skew_c = f64(0.267949) // approx. tan(15)
pub const italic_skew_d = f64(1)
pub const italic_skew_tx = f64(0)
pub const italic_skew_ty = f64(0)

// AffineTransform represents a 2D affine transformation matrix.
// Used for synthetic italic skew.
pub struct AffineTransform {
pub:
	a  f64 = 1
	b  f64
	c  f64
	d  f64 = 1
	tx f64
	ty f64
}

// The italic skew transform as a struct.
pub const italic_skew = AffineTransform{
	a:  italic_skew_a
	b:  italic_skew_b
	c:  italic_skew_c
	d:  italic_skew_d
	tx: italic_skew_tx
	ty: italic_skew_ty
}

// Initialize a CoreText-based font from a TTF/TTC in memory.
pub fn CoreTextFace.init(lib Library, source []u8, opts FaceOptions) !CoreTextFace {
	_ = lib
	$if macos || ios {
		data := macos.CFData.create_with_bytes_no_copy(source)!
		defer { data.release() }
		desc := macos.create_font_descriptor_from_data(data) or {
			return error('CoreText: failed to create font descriptor from data')
		}
		defer { desc.release() }
		base := macos.CTFont.create_with_descriptor(desc, 12)!
		defer { base.release() }
		return CoreTextFace.init_font_copy(voidptr(base), opts)!
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// Initialize a CoreText-based face from another initialized font face
// but with a new size. This is often how CoreText fonts are initialized
// because the font is loaded at a default size during discovery, and then
// adjusted to the final size for final load.
pub fn CoreTextFace.init_font_copy(base voidptr, opts FaceOptions) !CoreTextFace {
	// Create a copy. copyWithAttributes takes a size in points, but we need
	// to scale by the DPI, which is what DesiredSize.pixels() does.
	ct_font := copy_coretext_font_with_size(base, opts.size.pixels())
	if isnil(ct_font) {
		return error('CoreText: failed to copy font with size')
	}
	// init_font takes ownership of ct_font.
	return CoreTextFace.init_font(voidptr(ct_font), opts)!
}

// Initialize a face with a CTFont. This will take ownership over
// the CTFont. This does NOT copy or retain the CTFont.
pub fn CoreTextFace.init_font(ct_font voidptr, opts FaceOptions) !CoreTextFace {
	if isnil(ct_font) {
		return error('CoreText: null font')
	}

	// Determine color state from the font's symbolic traits and tables.
	mut color := ?ColorState(none)
	mut is_color := false
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(ct_font) }
		is_color = native_font.get_symbolic_traits().color_glyphs
	}
	if is_color {
		color = ColorState.init(ct_font) or {
			release_coretext_font(ct_font)
			return error(err.msg())
		}
	}

	mut hb_font := harfbuzz.Font{}
	$if macos || ios {
		if (opts.backend or { Backend.selected_() }).has_harfbuzz() {
			hb_font = harfbuzz.Font.create_coretext(ct_font) or {
				if c := color {
					c.deinit()
				}
				release_coretext_font(ct_font)
				return err
			}
			pixels := opentype.F26Dot6.from(opts.size.pixels())
			hb_font.set_scale(u32(pixels.raw), u32(pixels.raw))
		}
	} $else {
		if c := color {
			c.deinit()
		}
		release_coretext_font(ct_font)
		return error('CoreText: unsupported platform')
	}
	mut result := CoreTextFace{
		ct_font: ct_font
		hb_font: hb_font
		color:   color
		size:    opts.size
	}
	result.quirks_disable_default_font_features = quirks.disable_default_font_features(&result)

	// In debug mode, output the available variation axes when they exist.
	$if (macos || ios) && debug {
		native_font := unsafe { &macos.CTFont(ct_font) }
		if axes_ptr := native_font.copy_attribute(.variation_axes) {
			axes := unsafe { &macos.CFArray(axes_ptr) }
			defer { axes.release() }
			mut name_buf := []u8{len: 1024}
			font_name := result.name(mut name_buf) or {
				result.deinit()
				return err
			}
			log.debug('variation axes font=${font_name}')
			for i in 0 .. axes.get_count() {
				axis_ptr := axes.get_value_at_index(i)
				assert !isnil(axis_ptr)
				axis := unsafe { &macos.CFDictionary(axis_ptr) }
				name_ptr := axis.get_value(macos.CTFontVariationAxisKey.name.key())
				identifier_ptr := axis.get_value(macos.CTFontVariationAxisKey.identifier.key())
				minimum_ptr := axis.get_value(macos.CTFontVariationAxisKey.minimum_value.key())
				maximum_ptr := axis.get_value(macos.CTFontVariationAxisKey.maximum_value.key())
				default_ptr := axis.get_value(macos.CTFontVariationAxisKey.default_value.key())
				assert !isnil(name_ptr)
				assert !isnil(identifier_ptr)
				assert !isnil(minimum_ptr)
				assert !isnil(maximum_ptr)
				assert !isnil(default_ptr)
				name_string := unsafe { &macos.CFString(name_ptr) }
				identifier_number := unsafe { &macos.CFNumber(identifier_ptr) }
				minimum_number := unsafe { &macos.CFNumber(minimum_ptr) }
				maximum_number := unsafe { &macos.CFNumber(maximum_ptr) }
				default_number := unsafe { &macos.CFNumber(default_ptr) }
				axis_name := if name_cstr := name_string.cstring(mut name_buf, .utf8) {
					unsafe { cstring_to_vstring(name_cstr) }
				} else {
					''
				}
				mut identifier := i32(0)
				mut minimum := f64(0)
				mut maximum := f64(0)
				mut default_value := f64(0)
				identifier_number.get_value(.int_type, voidptr(&identifier))
				minimum_number.get_value(.double_, voidptr(&minimum))
				maximum_number.get_value(.double_, voidptr(&maximum))
				default_number.get_value(.double_, voidptr(&default_value))
				id := VariationId{
					value: u32(identifier)
				}
				log.debug('variation axis: name=${axis_name} id=${id.str()} min=${minimum} max=${maximum} def=${default_value}')
			}
		}
	}
	return result
}

// deinit releases all resources associated with this face.
pub fn (mut self CoreTextFace) deinit() {
	if !isnil(self.ct_font) {
		release_coretext_font(self.ct_font)
		self.ct_font = unsafe { nil }
	}
	self.hb_font.destroy()
	if c := self.color {
		c.deinit()
	}
	self.color = none
	// ColorState owns cloned SVG table bytes; V manages their lifetime.
}

// Return a new face that is the same as this but has a transformation
// matrix applied to italicize it.
pub fn (self &CoreTextFace) synthetic_italic(opts FaceOptions) !CoreTextFace {
	$if macos || ios {
		original := unsafe { &macos.CTFont(self.ct_font) }
		matrix := macos.CGAffineTransform{
			a:  italic_skew.a
			b:  italic_skew.b
			c:  italic_skew.c
			d:  italic_skew.d
			tx: italic_skew.tx
			ty: italic_skew.ty
		}
		ct_font := original.copy_with_attributes(0, voidptr(&matrix), unsafe { nil })!
		return CoreTextFace.init_font(voidptr(ct_font), opts)!
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// Return a new face that is the same as this but applies a synthetic
// bold effect to it. This is useful for fonts that don't have a bold
// variant.
pub fn (self &CoreTextFace) synthetic_bold(opts FaceOptions) !CoreTextFace {
	// Copy the font without any additional transforms.
	ct_font := copy_coretext_font_with_size(self.ct_font, 0.0)
	if isnil(ct_font) {
		return error('CoreText: failed to copy font for synthetic bold')
	}
	mut face := CoreTextFace.init_font(ct_font, opts)!

	// To determine our synthetic bold line width we get a multiplier from the
	// font size in points. This is a heuristic: a line width of 1 looks good
	// at a certain point size, and we scale it up roughly linearly with size.
	points_f64 := f64(opts.size.points)
	line_width := if points_f64 / 14.0 > 1.0 { points_f64 / 14.0 } else { f64(1) }
	face.synthetic_bold = line_width

	return face
}

// Returns the font name. If allocation is required, buf will be used,
// but sometimes allocation isn't required and a static string is
// returned.
pub fn (self &CoreTextFace) name(mut buf []u8) !string {
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		family_name := native_font.copy_family_name()!
		defer { family_name.release() }
		if name_ptr := family_name.cstring_ptr(.utf8) {
			return unsafe { cstring_to_vstring(name_ptr) }
		}
		if name_ptr := family_name.cstring(mut buf, .utf8) {
			return unsafe { cstring_to_vstring(name_ptr) }
		}
		return error('CoreText: failed to copy family name')
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// Resize the font in-place. If this succeeds, the caller is responsible
// for clearing any glyph caches, font atlas data, etc.
pub fn (mut self CoreTextFace) set_size(opts FaceOptions) ! {
	// We just create a copy at the new size and replace ourself.
	face := CoreTextFace.init_font_copy(self.ct_font, opts)!
	self.deinit()
	self = face
}

// Set the variation axes for this font. This will modify this font
// in-place.
pub fn (mut self CoreTextFace) set_variations(vs []Variation, opts FaceOptions) ! {
	// If we have no variations, we don't need to do anything.
	if vs.len == 0 {
		return
	}

	$if macos || ios {
		original := unsafe { &macos.CTFont(self.ct_font) }
		mut desc := original.copy_descriptor()!
		defer { desc.release() }
		for v in vs {
			id_value := i32(v.id.value)
			id := macos.CFNumber.create(.int_type, voidptr(&id_value))!
			defer { id.release() }
			mut next := desc.copy_with_variation(id, v.value)!
			desc.release()
			desc = next
		}

		mut new_opts := opts
		new_opts.size = self.size
		ct_font := original.copy_with_attributes(0, unsafe { nil }, voidptr(desc))!
		face := CoreTextFace.init_font(voidptr(ct_font), new_opts)!
		self.deinit()
		self = face
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// Returns true if the face has any glyphs that are colorized.
// To determine if an individual glyph is colorized you must use
// is_color_glyph.
pub fn (self &CoreTextFace) has_color() bool {
	return self.color != none
}

// Returns true if the given glyph ID is colorized.
pub fn (self &CoreTextFace) is_color_glyph(glyph_id u32) bool {
	c := self.color or { return false }
	return c.is_color_glyph(glyph_id)
}

// Returns the glyph index for the given Unicode code point. If this
// face doesn't support this glyph, null is returned.
pub fn (self CoreTextFace) glyph_index(cp u32) ?u32 {
	$if macos || ios {
		mut unichars := []u16{len: 2}
		pair := macos.string_get_surrogate_pair_for_long_character(cp, mut unichars)
		len := if pair { 2 } else { 1 }

		mut glyphs := []macos.CGGlyph{len: 2}
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		if !native_font.get_glyphs_for_characters(unichars[..len], glyphs[..len]) {
			return none
		}
		if pair {
			assert glyphs[1] == 0
		}
		return u32(glyphs[0])
	} $else {
		return none
	}
}

struct CoreTextGlyphLayout {
	rect        GlyphSize
	px_width    u32
	px_height   u32
	offset_x    i32
	offset_y    i32
	translate_x f64
	translate_y f64
	scale_x     f64
	scale_y     f64
}

// coretext_glyph_layout translates the backend-independent portion of
// CoreText Face.renderGlyph: synthetic-bold bounds, constraints, alignment,
// subpixel bearings, and the final raster canvas dimensions.
fn coretext_glyph_layout(bounds GlyphSize, sbix bool, synthetic_bold ?f64, opts RenderOptions) ?CoreTextGlyphLayout {
	mut rect := bounds
	if !sbix {
		if line_width := synthetic_bold {
			rect.width += line_width
			rect.height += line_width
			rect.x -= line_width / 2
			rect.y -= line_width / 2
		}
	}
	if rect.width < 0.25 || rect.height < 0.25 {
		return none
	}

	metrics := opts.grid_metrics
	cell_width := f64(metrics.cell_width)
	cell_height := f64(metrics.cell_height)
	glyph_size := opts.constraint.constrain(GlyphSize{
		width:  rect.width
		height: rect.height
		x:      rect.x
		y:      rect.y + f64(metrics.cell_baseline)
	}, metrics, opts.constraint_width)
	mut x := glyph_size.x
	mut y := glyph_size.y
	mut width := glyph_size.width
	mut height := glyph_size.height

	if opts.constraint.size != .stretch {
		dx := (cell_width - metrics.face_width) / 2
		x += dx
		if dx < 0 {
			x -= math.trunc(dx)
		}
	}
	if sbix {
		width = cell_width - math.round(cell_width - width - x) - math.round(x)
		height = cell_height - math.round(cell_height - height - y) - math.round(y)
		x = math.round(x)
		y = math.round(y)
	}

	canvas_padding := if opts.thicken && !sbix { u32(1) } else { u32(0) }
	px_x := i32(math.floor(x)) - i32(canvas_padding)
	px_y := i32(math.floor(y)) - i32(canvas_padding)
	frac_x := x - math.floor(x)
	frac_y := y - math.floor(y)
	px_width := u32(math.ceil(width + frac_x)) + 2 * canvas_padding
	px_height := u32(math.ceil(height + frac_y)) + 2 * canvas_padding
	return CoreTextGlyphLayout{
		rect:        rect
		px_width:    px_width
		px_height:   px_height
		offset_x:    px_x
		offset_y:    px_y + i32(px_height)
		translate_x: frac_x + f64(canvas_padding)
		translate_y: frac_y + f64(canvas_padding)
		scale_x:     width / rect.width
		scale_y:     height / rect.height
	}
}

// Render a glyph using the glyph index. The rendered glyph is stored
// in the given texture atlas.
pub fn (self CoreTextFace) render_glyph(mut atlas Atlas, glyph_index u32, opts RenderOptions) !Glyph {
	opts.assert_narrow_widths()
	mut bounds := GlyphSize{}
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		rect := native_font.get_bounding_rects_for_glyphs(.horizontal, [
			macos.CGGlyph(glyph_index),
		], []macos.CGRect{})
		if rect.is_null() {
			return error('CoreText: failed to get glyph bounds')
		}
		bounds = GlyphSize{
			x:      rect.origin.x
			y:      rect.origin.y
			width:  rect.size.width
			height: rect.size.height
		}
	} $else {
		return error('CoreText: unsupported platform')
	}
	is_color := self.is_color_glyph(glyph_index)
	sbix := if color := self.color { is_color && color.sbix } else { false }
	layout := coretext_glyph_layout(bounds, sbix, self.synthetic_bold, opts) or { return Glyph{} }
	depth := if is_color { u32(4) } else { u32(1) }
	if atlas.format.depth() != depth {
		log.warn("font atlas color depth doesn't equal font color depth atlas=${atlas.format.depth()} font=${depth}")
		return error('CoreText: font atlas color depth does not match glyph color depth')
	}
	$if macos || ios {
		color_space := if is_color {
			macos.CGColorSpace.create_named(.display_p3)!
		} else {
			macos.CGColorSpace.create_named(.linear_gray)!
		}
		defer { color_space.release() }

		bytes_per_row := uint(layout.px_width * depth)
		byte_count := int(bytes_per_row * layout.px_height)
		// CoreText writes into zero-initialized storage. Color glyphs use a
		// Canvas BGRA surface, and monochrome glyphs use a one-byte alpha mask.
		color_surface := if is_color {
			canvas.new_raster_surface(width: int(layout.px_width), height: int(layout.px_height))!
		} else {
			canvas.RasterSurface{}
		}
		pixels := if is_color {
			unsafe { (&u8(color_surface.pixels.data)).vbytes(byte_count) }
		} else {
			[]u8{len: byte_count}
		}
		context_opts := if is_color {
			u32(macos.CGBitmapInfo.byte_order_32_little) | u32(macos.CGImageAlphaInfo.premultiplied_first)
		} else {
			u32(macos.CGImageAlphaInfo.only)
		}
		bitmap := macos.CGBitmapContext.create(pixels, uint(layout.px_width),
			uint(layout.px_height), 8, bytes_per_row, color_space, context_opts)!
		context := bitmap.as_context()
		defer { context.release() }

		context.set_allows_font_smoothing(true)
		context.set_should_smooth_fonts(opts.thicken)
		context.set_allows_font_subpixel_positioning(true)
		context.set_should_subpixel_position_fonts(true)
		context.set_allows_font_subpixel_quantization(false)
		context.set_should_subpixel_quantize_fonts(false)
		context.set_allows_antialiasing(true)
		context.set_should_antialias(true)

		if is_color {
			context.set_rgb_fill_color(1, 1, 1, 1)
			context.set_rgb_stroke_color(1, 1, 1, 1)
		} else {
			strength := f64(opts.thicken_strength) / 255.0
			context.set_gray_fill_color(strength, 1)
			context.set_gray_stroke_color(strength, 1)
		}
		if line_width := self.synthetic_bold {
			context.set_text_drawing_mode(.fill_stroke)
			context.set_line_width(line_width)
		}

		context.translate_ctm(layout.translate_x, layout.translate_y)
		context.scale_ctm(layout.scale_x, layout.scale_y)
		ct_font := unsafe { &macos.CTFont(self.ct_font) }
		ct_font.draw_glyphs([macos.CGGlyph(glyph_index)], [
			macos.CGPoint{
				x: -layout.rect.x
				y: -layout.rect.y
			},
		], context)

		region := atlas.reserve(layout.px_width, layout.px_height)!
		atlas.set(region, pixels)
		return Glyph{
			width:    layout.px_width
			height:   layout.px_height
			offset_x: layout.offset_x
			offset_y: layout.offset_y
			atlas_x:  region.x
			atlas_y:  region.y
		}
	} $else {
		return error('CoreText: unsupported platform')
	}
}

struct CoreTextSize {
	width  f64
	height f64
}

// Get the FaceMetrics for this face. CoreText supplies glyph measurements;
// OpenType tables supply the same metric precedence and broken-table handling
// used by Ghostty.
pub fn (mut self CoreTextFace) get_metrics() FaceMetrics {
	mut px_per_em := f64(0)
	mut ascent := f64(0)
	mut raw_descent := f64(0)
	mut line_gap := f64(0)
	mut cap_height := f64(0)
	mut ex_height := f64(0)
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		px_per_em = native_font.get_size()
		ascent = native_font.get_ascent()
		raw_descent = native_font.get_descent()
		line_gap = native_font.get_leading()
		cap_height = native_font.get_cap_height()
		ex_height = native_font.get_x_height()
	} $else {
		return FaceMetrics{}
	}

	// Measure the widest visible ASCII advance and the height of their
	// collective bounds.
	mut characters := []u16{len: 127 - 32}
	for i in 0 .. characters.len {
		characters[i] = u16(i + 32)
	}
	mut glyphs := []u16{len: characters.len}
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		native_font.get_glyphs_for_characters(characters, glyphs)
	}
	mut advances := []CoreTextSize{len: glyphs.len}
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		native_font.get_advances_for_glyphs(.horizontal, glyphs, advances.data)
	}
	mut cell_width := f64(0)
	for advance in advances {
		cell_width = math.max(cell_width, advance.width)
	}
	mut ascii_bounds := GlyphSize{}
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		rect := native_font.get_bounding_rects_for_glyphs(.horizontal, glyphs, []macos.CGRect{})
		ascii_bounds = GlyphSize{
			x:      rect.origin.x
			y:      rect.origin.y
			width:  rect.size.width
			height: rect.size.height
		}
	}

	// Measure "水" (CJK water ideograph, U+6C34) for the CSS ic unit.
	mut ic_width := ?f64(none)
	if water_glyph := self.glyph_index(0x6c34) {
		mut water_glyphs := [u16(water_glyph)]
		mut water_advance := [CoreTextSize{}]
		$if macos || ios {
			native_font := unsafe { &macos.CTFont(self.ct_font) }
			native_font.get_advances_for_glyphs(.horizontal, water_glyphs[..], water_advance.data)
		}
		mut water_bounds := GlyphSize{}
		$if macos || ios {
			native_font := unsafe { &macos.CTFont(self.ct_font) }
			rect := native_font.get_bounding_rects_for_glyphs(.horizontal, water_glyphs[..],
				[]macos.CGRect{})
			water_bounds = GlyphSize{
				x:      rect.origin.x
				y:      rect.origin.y
				width:  rect.size.width
				height: rect.size.height
			}
		}
		if water_bounds.width > water_advance[0].width {
			mut name_buf := []u8{len: 1024}
			font_name := self.name(mut name_buf) or { '<Error getting font name>' }
			log.warn('(getMetrics) Width of glyph \'水\' for font "${font_name}" is greater than its advance (${water_bounds.width} > ${water_advance[0].width}), discarding ic_width metric.')
		} else {
			ic_width = water_advance[0].width
		}
	}

	base := FaceMetrics{
		px_per_em:               px_per_em
		cell_width:              cell_width
		ascent:                  ascent
		descent:                 -raw_descent
		line_gap:                line_gap
		underline_position:      none
		underline_thickness:     none
		strikethrough_position:  none
		strikethrough_thickness: none
		cap_height:              cap_height
		ex_height:               ex_height
		ascii_height:            ascii_bounds.height
		ic_width:                ic_width
	}

	head := self.parse_head_table()
	post := self.parse_post_table()
	os2 := self.parse_os2_table()
	hhea := self.parse_hhea_table()
	units_per_em := if value := head {
		u32(value.units_per_em)
	} else {
		mut value := u32(0)
		$if macos || ios {
			native_font := unsafe { &macos.CTFont(self.ct_font) }
			value = native_font.get_units_per_em()
		}
		value
	}
	return refine_coretext_metrics(base, units_per_em, post, os2, hhea)
}

fn (self CoreTextFace) parse_head_table() ?opentype.Head {
	data := self.copy_table('head') or { self.copy_table('bhed') or { return none } }
	return opentype.Head.init(data) or {
		log.warn('error parsing head table: ${err}')
		none
	}
}

fn (self CoreTextFace) parse_post_table() ?opentype.Post {
	data := self.copy_table('post') or { return none }
	return opentype.Post.init(data) or {
		log.warn('error parsing post table: ${err}')
		none
	}
}

fn (self CoreTextFace) parse_os2_table() ?opentype.OS2 {
	data := self.copy_table('OS/2') or { return none }
	return opentype.OS2.init(data) or {
		log.warn('error parsing OS/2 table: ${err}')
		none
	}
}

fn (self CoreTextFace) parse_hhea_table() ?opentype.Hhea {
	data := self.copy_table('hhea') or { return none }
	return opentype.Hhea.init(data) or {
		log.warn('error parsing hhea table: ${err}')
		none
	}
}

fn refine_coretext_metrics(base FaceMetrics, units_per_em u32, post ?opentype.Post, os2 ?opentype.OS2, hhea ?opentype.Hhea) FaceMetrics {
	px_per_unit := base.px_per_em / f64(units_per_em)
	mut result := base

	if hhea_value := hhea {
		if os2_value := os2 {
			if os2_value.fs_selection.use_typo_metrics() {
				result.ascent = f64(os2_value.s_typo_ascender) * px_per_unit
				result.descent = f64(os2_value.s_typo_descender) * px_per_unit
				result.line_gap = f64(os2_value.s_typo_line_gap) * px_per_unit
			} else if hhea_value.ascender != 0 || hhea_value.descender != 0 {
				result.ascent = f64(hhea_value.ascender) * px_per_unit
				result.descent = f64(hhea_value.descender) * px_per_unit
				result.line_gap = f64(hhea_value.line_gap) * px_per_unit
			} else if os2_value.s_typo_ascender != 0 || os2_value.s_typo_descender != 0 {
				result.ascent = f64(os2_value.s_typo_ascender) * px_per_unit
				result.descent = f64(os2_value.s_typo_descender) * px_per_unit
				result.line_gap = f64(os2_value.s_typo_line_gap) * px_per_unit
			} else {
				result.ascent = f64(os2_value.us_win_ascent) * px_per_unit
				result.descent = -f64(os2_value.us_win_descent) * px_per_unit
				result.line_gap = 0
			}
		} else {
			result.ascent = f64(hhea_value.ascender) * px_per_unit
			result.descent = f64(hhea_value.descender) * px_per_unit
			result.line_gap = f64(hhea_value.line_gap) * px_per_unit
		}
	}

	result.underline_position = none
	result.underline_thickness = none
	if post_value := post {
		broken := post_value.underline_thickness == 0
		if !broken || post_value.underline_position != 0 {
			result.underline_position = f64(post_value.underline_position) * px_per_unit
		}
		if !broken {
			result.underline_thickness = f64(post_value.underline_thickness) * px_per_unit
		}
	}

	result.strikethrough_position = none
	result.strikethrough_thickness = none
	if os2_value := os2 {
		broken := os2_value.y_strikeout_size == 0
		if !broken || os2_value.y_strikeout_position != 0 {
			result.strikethrough_position = f64(os2_value.y_strikeout_position) * px_per_unit
		}
		if !broken {
			result.strikethrough_thickness = f64(os2_value.y_strikeout_size) * px_per_unit
		}
		if os2_value.has_s_cap_height {
			result.cap_height = f64(os2_value.s_cap_height) * px_per_unit
		}
		if os2_value.has_sx_height {
			result.ex_height = f64(os2_value.sx_height) * px_per_unit
		}
	}

	return result
}

// Copy the font table data for the given tag.
pub fn (self CoreTextFace) copy_table(tag string) ![]u8 {
	// CTFontCopyTable expects a 4-character tag.
	if tag.len != 4 {
		return error('CoreText: font table tag must be 4 characters')
	}
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		data := native_font.copy_table(macos.CTFontTableTag.init(tag)) or {
			return error('CoreText: font table not found: ${tag}')
		}
		defer { data.release() }
		len := data.get_length()
		if len == 0 {
			return []u8{}
		}
		return unsafe { data.get_pointer().vbytes(len) }.clone()
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// ============================================================
// ColorState
// ============================================================

// The state associated with a font face that may have colorized glyphs.
// This is used to determine if a specific glyph ID is colorized.
pub struct ColorState {
pub mut:
	// True if there is an sbix font table. For now, the mere presence
	// of an sbix font table causes us to assume the glyph is colored.
	// We can improve this later.
	sbix bool

	// The SVG font table data (if any), which we can use to determine
	// if a glyph is present in the SVG table.
	svg ?opentype.SVG

	// Owns the bytes referenced by svg.
	svg_data []u8
}

// init creates a ColorState from a CoreText font by checking for
// sbix and SVG tables.
pub fn ColorState.init(ct_font voidptr) !ColorState {
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(ct_font) }
		mut sbix := false
		if data := native_font.copy_table(macos.CTFontTableTag.init('sbix')) {
			sbix = data.get_length() > 0
			data.release()
		}

		mut svg_data := []u8{}
		mut svg := ?opentype.SVG(none)
		if data := native_font.copy_table(macos.CTFontTableTag.init('SVG ')) {
			defer { data.release() }
			len := data.get_length()
			if len > 0 {
				svg_data = unsafe { data.get_pointer().vbytes(len) }.clone()
			}
			svg = opentype.SVG.init(svg_data)!
		}
		return ColorState{
			sbix:     sbix
			svg:      svg
			svg_data: svg_data
		}
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// deinit releases resources held by the ColorState.
pub fn (self &ColorState) deinit() {
	// V owns svg_data and releases it with the containing face.
}

// Returns true if the given glyph ID is colored.
pub fn (self &ColorState) is_color_glyph(glyph_id u32) bool {
	// Our font system uses 32-bit glyph IDs for special values but
	// actual fonts only contain 16-bit glyph IDs so if we can't cast
	// into it it must be false.
	if glyph_id > 0xFFFF {
		return false
	}

	// sbix is always true for now
	if self.sbix {
		return true
	}

	// if we have svg data, check it
	if svg := self.svg {
		return svg.has_glyph(u16(glyph_id))
	}

	return false
}

// ============================================================
// CoreText-specific DeferredFace fields
// ============================================================

// CoreTextDeferredFace holds CoreText-specific data for a deferred face.
// This is only present when building with CoreText.
pub struct CoreTextDeferredFace {
pub mut:
	// The initialized font (CTFont pointer, stored as voidptr).
	ct_font voidptr = unsafe { nil }

	// Variations to apply to this font. We apply the variations to the
	// search descriptor but sometimes when the font collection is
	// made the variation axes are reset so we have to reapply them.
	variations []Variation
}

// deinit releases the CoreText deferred face resources.
pub fn (mut self CoreTextDeferredFace) deinit() {
	if self.ct_font != unsafe { nil } {
		release_coretext_font(self.ct_font)
		self.ct_font = unsafe { nil }
	}
	self.variations = []
}

// has_codepoint returns true if this deferred face can render the given
// codepoint with the specified presentation.
pub fn (self CoreTextDeferredFace) has_codepoint(cp u32, p ?Presentation) bool {
	// Steps:
	// 1. This presentation check isn't as detailed as isColorGlyph
	//    because forced presentation modes are only used for emoji and
	//    emoji should always have color glyphs set. This can be
	//    more correct by using the isColorGlyph logic but I'd want
	//    to find a font that actually requires this so we can write
	//    a test for it before changing it.
	//    if p != none:
	//      traits = ct_font.getSymbolicTraits()
	//      actual_p = if traits.color_glyphs { .emoji } else { .text }
	//      if actual_p != p: return false
	//
	// 2. Turn UTF-32 into UTF-16 for CT API:
	//    var unichars [2]u16
	//    pair = stringGetSurrogatePairForLongCharacter(cp, &unichars)
	//    len = if pair { 2 } else { 1 }
	//
	// 3. Get our glyphs:
	//    var glyphs = [2]Glyph{ 0, 0 }
	//    return ct_font.getGlyphsForCharacters(unichars[0..len], glyphs[0..len])
	if presentation := p {
		mut is_color := false
		$if macos || ios {
			native_font := unsafe { &macos.CTFont(self.ct_font) }
			is_color = native_font.get_symbolic_traits().color_glyphs
		}
		actual := if is_color { Presentation.emoji } else { Presentation.text }
		if actual != presentation {
			return false
		}
	}
	$if macos || ios {
		mut unichars := []u16{len: 2}
		pair := macos.string_get_surrogate_pair_for_long_character(cp, mut unichars)
		len := if pair { 2 } else { 1 }

		mut glyphs := []macos.CGGlyph{len: 2}
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		return native_font.get_glyphs_for_characters(unichars[..len], glyphs[..len])
	} $else {
		return false
	}
}

// family_name returns the family name of the deferred CoreText font.
pub fn (self CoreTextDeferredFace) family_name(mut buf []u8) !string {
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		family_ptr := native_font.copy_attribute(.family_name) or { return 'unknown' }
		family_name := unsafe { &macos.CFString(family_ptr) }
		defer { family_name.release() }
		if name_ptr := family_name.cstring_ptr(.utf8) {
			return unsafe { cstring_to_vstring(name_ptr) }
		}
		if name_ptr := family_name.cstring(mut buf, .utf8) {
			return unsafe { cstring_to_vstring(name_ptr) }
		}
		return error('CoreText: failed to copy family name')
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// name returns the display name of the deferred CoreText font.
pub fn (self CoreTextDeferredFace) name(mut buf []u8) !string {
	// display_name = ct_font.copyDisplayName()
	// return display_name.cstringPtr(.utf8) or display_name.cstring(buf, .utf8)
	// "NULL if the internal storage of theString does not allow
	// this to be returned efficiently." In this case, we need
	// to allocate. But we can't return an allocated string because
	// we don't have an allocator. Let's use the stack and log it.
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		display_name := native_font.copy_display_name()!
		defer { display_name.release() }
		if name_ptr := display_name.cstring_ptr(.utf8) {
			return unsafe { cstring_to_vstring(name_ptr) }
		}
		if name_ptr := display_name.cstring(mut buf, .utf8) {
			return unsafe { cstring_to_vstring(name_ptr) }
		}
		return error('CoreText: failed to copy display name')
	} $else {
		return error('CoreText: unsupported platform')
	}
}

// load loads this deferred CoreText face into a CoreTextFace.
pub fn (self CoreTextDeferredFace) load(lib Library, opts FaceOptions) !CoreTextFace {
	// Steps:
	// 1. face = CoreTextFace.init_font_copy(self.ct_font, opts)
	// 2. face.set_variations(self.variations, opts)
	// 3. return face
	_ = lib
	mut face := CoreTextFace.init_font_copy(self.ct_font, opts)!
	face.set_variations(self.variations, opts) or {
		face.deinit()
		return err
	}
	return face
}

// load_freetype loads a CoreText deferred face through FreeType instead.
// This is for the coretext_freetype backend.
pub fn (self CoreTextDeferredFace) load_freetype(lib Library, opts FaceOptions) !Face {
	assert lib.backend.has_freetype()
	// Steps:
	// 1. Get the URL for the font so we can get the filepath:
	//    url = ct_font.copyAttribute(.url) or return error
	//    path = url.copyPath() or return error
	// 2. URL decode the path:
	//    decoded = URL.createStringByReplacingPercentEscapes(path, "")
	// 3. Decode into a null-terminated C string (1024 bytes should be enough).
	// 4. Face index 0 is not always correct. We don't ship this configuration
	//    in a release build. Users should use the pure CoreText builds.
	// 5. face = Face.init_file(lib, path, 0, opts)
	// 6. face.set_variations(self.variations, opts)
	// 7. return face
	$if macos || ios {
		native_font := unsafe { &macos.CTFont(self.ct_font) }
		desc := native_font.copy_descriptor()!
		defer { desc.release() }
		url_ptr := desc.copy_attribute(.url) or { return error('FontHasNoFile') }
		url := unsafe { &macos.CFURL(url_ptr) }
		defer { url.release() }
		path_string := url.copy_path() or { return error('FontHasNoFile') }
		defer { path_string.release() }
		blank := macos.CFString.create_with_bytes([], .utf8, false)!
		defer { blank.release() }
		decoded := macos.CFURL.create_string_by_replacing_percent_escapes(path_string, blank)!
		defer { decoded.release() }
		mut path_buf := []u8{len: 1024}
		path_ptr := decoded.cstring(mut path_buf[..1023], .utf8) or {
			return error('FontPathCantDecode')
		}
		path := unsafe { cstring_to_vstring(path_ptr) }
		path_buf[path.len] = 0
		mut face := Face.init_file(lib, path, 0, opts)!
		face.set_variations(self.variations, opts) or {
			face.deinit()
			return err
		}
		return face
	} $else {
		return error('CoreText: unsupported platform')
	}
}
