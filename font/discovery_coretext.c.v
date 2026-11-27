module font

// CoreText discovery (discovery.zig's CoreText and Descriptor.toCoreTextDescriptor),
// compiled only for Darwin where the CoreText font backend is selected.
import ascii
import log
import witty_macos as macos
import opentype

$if macos || ios {

	// to_core_text_descriptor converts the descriptor to a CoreText font
	// descriptor for font lookup or conversion to a specific font.
	//
	// Builds a CTFontDescriptor from our fields (family, style, codepoint
	// character set, size and symbolic traits) via the C shim. The returned
	// descriptor is retained; callers must release it with macos.cf_release.
	pub fn (d &Descriptor) to_core_text_descriptor() !&macos.CTFontDescriptor {
		attrs := macos.CFMutableDictionary.create(0)!
		defer { attrs.release() }

		if family_bytes := d.family {
			family := macos.CFString.create_with_bytes(family_bytes.bytes(), .utf8, false)!
			defer { family.release() }
			attrs.set_value(macos.CTFontAttribute.family_name.key(), voidptr(family))
		}
		if style_bytes := d.style {
			style := macos.CFString.create_with_bytes(style_bytes.bytes(), .utf8, false)!
			defer { style.release() }
			attrs.set_value(macos.CTFontAttribute.style_name.key(), voidptr(style))
		}
		if d.codepoint > 0 {
			character_set := macos.CFCharacterSet.create_with_characters_in_range(macos.CFRange.init(int(d.codepoint),
				1))!
			defer { character_set.release() }
			attrs.set_value(macos.CTFontAttribute.character_set.key(), voidptr(character_set))
		}
		if d.size > 0 {
			size_value := i32(d.size + 0.5)
			size := macos.CFNumber.create(.sint32, voidptr(&size_value))!
			defer { size.release() }
			attrs.set_value(macos.CTFontAttribute.size.key(), voidptr(size))
		}

		traits_value := (if d.italic { u32(1) << 0 } else { u32(0) }) |
			(if d.bold { u32(1) << 1 } else { u32(0) }) |
			(if d.monospace { u32(1) << 10 } else { u32(0) })
		if traits_value > 0 {
			traits_raw := i32(traits_value)
			traits_num := macos.CFNumber.create(.sint32, voidptr(&traits_raw))!
			defer { traits_num.release() }
			traits := macos.CFMutableDictionary.create(0)!
			defer { traits.release() }
			traits.set_value(macos.CTFontTraitKey.symbolic.key(), voidptr(traits_num))
			attrs.set_value(macos.CTFontAttribute.traits.key(), voidptr(traits))
		}
		return macos.CTFontDescriptor.create_with_attributes(attrs.as_dictionary())!
	}

	// CoreTextDiscovery discovers fonts using Apple's CoreText framework (macOS).
	pub struct CoreTextDiscovery {}

	// init creates a new CoreTextDiscovery instance.
	// Required for the "interface" but does nothing for CoreText.
	pub fn CoreTextDiscovery.init() CoreTextDiscovery {
		return CoreTextDiscovery{}
	}

	// deinit releases resources (no-op for CoreText).
	pub fn (mut ct CoreTextDiscovery) deinit() {
	}

	// discover finds fonts matching the descriptor. Returns an iterator
	// that can be used to build up the deferred fonts.
	pub fn (ct &CoreTextDiscovery) discover(desc Descriptor) !CtDiscoverIterator {
		// Build the CoreText descriptor we'll search for.
		ct_desc := desc.to_core_text_descriptor()!
		defer {
			macos.cf_release(voidptr(ct_desc))
		}

		// Our descriptors have to be in an array.
		desc_arr := macos.CFArray.create([voidptr(ct_desc)])!
		defer { desc_arr.release() }

		// Build our collection and grab the matching descriptors.
		set := macos.CTFontCollection.create_with_font_descriptors(desc_arr)!
		defer { set.release() }
		list := set.create_matching_font_descriptors()!
		defer { list.release() }

		// Copy the matching descriptors into a V slice, retaining each so they
		// survive the release of the CFArray, then sort by score.
		mut zig_list := copy_matching_descriptors(list)
		sort_matching_descriptors(desc, mut zig_list)

		return CtDiscoverIterator{
			list:       zig_list
			variations: desc.variations
			i:          0
		}
	}

	// copy_matching_descriptors copies the CFArray of matching descriptors into a
	// V slice, retaining each descriptor (the array releases its members when it
	// is freed, so we must retain to keep them alive).
	fn copy_matching_descriptors(list &macos.CFArray) []voidptr {
		n := list.get_count()
		mut out := []voidptr{cap: n}
		for i in 0 .. n {
			d := list.get_value_at_index(i)
			macos.cf_retain(d)
			out << d
		}
		return out
	}

	// sort_matching_descriptors sorts the descriptor list so that the best
	// matches (highest score) come first. This mirrors ghostty's
	// sortMatchingDescriptors: a higher score is "less" (earlier).
	fn sort_matching_descriptors(desc Descriptor, mut list []voidptr) {
		list.sort_with_compare(fn [desc] (a &voidptr, b &voidptr) int {
			lhs := Score.score(&desc, *a).int()
			rhs := Score.score(&desc, *b).int()
			// Higher score is earlier.
			if lhs > rhs {
				return -1
			}
			if lhs < rhs {
				return 1
			}
			return 0
		})
	}

	// score computes the sorting score for a candidate CoreText descriptor.
	// The control flow and score precedence are a direct translation of
	// discovery.zig's Score.score; the C shim only exposes primitive CoreText
	// values that V's C interop cannot retrieve generically.
	fn Score.score(desc &Descriptor, ct_desc voidptr) Score {
		descriptor := unsafe { &macos.CTFontDescriptor(ct_desc) }
		native_font := macos.CTFont.create_with_descriptor(descriptor, 12) or {
			return Score{}
		}
		defer { native_font.release() }
		font_ptr := voidptr(native_font)

		glyph_count_raw := native_font.get_glyph_count()
		glyph_count := if glyph_count_raw > 0xffff { u16(0xffff) } else { u16(glyph_count_raw) }

		mut has_codepoint := false
		if desc.codepoint > 0 {
			mut unichars := []u16{len: 2}
			pair := macos.string_get_surrogate_pair_for_long_character(desc.codepoint,
				mut unichars)
			len := if pair { 2 } else { 1 }
			mut glyphs := []macos.CGGlyph{len: 2}
			has_codepoint = native_font.get_glyphs_for_characters(unichars[..len], glyphs[..len])
		}

		mut symbolic_traits := macos.CTFontSymbolicTraits{}
		if traits_ptr := descriptor.copy_attribute(.traits) {
			traits := unsafe { &macos.CFDictionary(traits_ptr) }
			defer { traits.release() }
			symbolic_ptr := traits.get_value(macos.CTFontTraitKey.symbolic.key())
			if !isnil(symbolic_ptr) {
				symbolic := unsafe { &macos.CFNumber(symbolic_ptr) }
				mut raw := i32(0)
				if symbolic.get_value(.sint32, voidptr(&raw)) {
					symbolic_traits = macos.CTFontSymbolicTraits.from_raw(u32(raw))
				}
			}
		}
		mut is_bold := symbolic_traits.bold
		mut is_italic := symbolic_traits.italic
		monospace := symbolic_traits.monospace

		core_face := CoreTextFace{
			ct_font: font_ptr
		}
		if head := score_head_table(core_face) {
			is_bold = is_bold || head.mac_style & 1 == 1
			is_italic = is_italic || head.mac_style & 2 == 2
		}
		if os2 := score_os2_table(core_face) {
			is_bold = is_bold || os2.fs_selection.bold()
			is_italic = is_italic || os2.fs_selection.italic()
		}

		if axes_ptr := native_font.copy_attribute(.variation_axes) {
			axes := unsafe { &macos.CFArray(axes_ptr) }
			defer { axes.release() }
			if values_ptr := native_font.copy_attribute(.variation) {
				values := unsafe { &macos.CFDictionary(values_ptr) }
				defer { values.release() }
				mut ital_seen := false
				for i in 0 .. axes.get_count() {
					axis_ptr := axes.get_value_at_index(i)
					assert !isnil(axis_ptr)
					axis := unsafe { &macos.CFDictionary(axis_ptr) }
					identifier_ptr := axis.get_value(macos.CTFontVariationAxisKey.identifier.key())
					name_ptr := axis.get_value(macos.CTFontVariationAxisKey.name.key())
					default_ptr := axis.get_value(macos.CTFontVariationAxisKey.default_value.key())
					assert !isnil(identifier_ptr)
					assert !isnil(name_ptr)
					assert !isnil(default_ptr)
					identifier := unsafe { &macos.CFNumber(identifier_ptr) }
					name_string := unsafe { &macos.CFString(name_ptr) }
					default_value := unsafe { &macos.CFNumber(default_ptr) }
					mut name_buf := []u8{len: 1024}
					name := if name_cstr := name_string.cstring(mut name_buf, .utf8) {
						unsafe { cstring_to_vstring(name_cstr) }
					} else {
						''
					}
					mut value := f64(0)
					default_value.get_value(.double_, voidptr(&value))
					configured_ptr := values.get_value(voidptr(identifier))
					if !isnil(configured_ptr) {
						configured := unsafe { &macos.CFNumber(configured_ptr) }
						configured.get_value(.double_, voidptr(&value))
					}
					if name == 'wght' {
						is_bold = value > 600
						continue
					}
					if name == 'ital' {
						is_italic = value > 0.5
						ital_seen = true
						continue
					}
					if !ital_seen && name == 'slnt' {
						is_italic = value <= -5.0
					}
				}
			}
		}

		mut style_str := ''
		if style_ptr := descriptor.copy_attribute(.style_name) {
			style := unsafe { &macos.CFString(style_ptr) }
			defer { style.release() }
			mut style_buf := []u8{len: 128}
			if style_cstr := style.cstring(mut style_buf, .utf8) {
				style_str = unsafe { cstring_to_vstring(style_cstr) }
			}
		}

		mut desired_styles := []string{}
		if style := desc.style {
			desired_styles << style
		} else if desc.bold {
			if desc.italic {
				desired_styles = ['bold italic', 'bold', 'italic', 'oblique']
			} else {
				desired_styles = ['bold', 'upright']
			}
		} else if desc.italic {
			desired_styles = ['italic', 'regular', 'oblique']
		} else {
			desired_styles = ['regular', 'upright']
		}

		exact_style := ascii.eql_ignore_case(style_str, desired_styles[0])
		mut fuzzy_style := u8(style_str.len)
		for desired in desired_styles {
			if ascii.index_of_ignore_case(style_str, desired) != none {
				fuzzy_style = if int(fuzzy_style) > desired.len {
					fuzzy_style - u8(desired.len)
				} else {
					u8(0)
				}
			}
		}
		fuzzy_style = u8(255) - fuzzy_style

		return Score.init(glyph_count, fuzzy_style, desc.bold == is_bold, desc.italic == is_italic,
			exact_style, monospace, has_codepoint)
	}

	fn score_head_table(face CoreTextFace) ?opentype.Head {
		data := face.copy_table('head') or { return none }
		return opentype.Head.init(data) or {
			log.warn('error parsing head table: ${err}')
			return none
		}
	}

	fn score_os2_table(face CoreTextFace) ?opentype.OS2 {
		data := face.copy_table('OS/2') or { return none }
		return opentype.OS2.init(data) or {
			log.warn('error parsing OS/2 table: ${err}')
			return none
		}
	}

	// discover_fallback finds fallback fonts for a codepoint.
	pub fn (ct &CoreTextDiscovery) discover_fallback(mut collection Collection, desc Descriptor) !CtDiscoverIterator {
		// If we have a codepoint within the CJK unified ideographs block then we
		// fall back to macOS to find a font that supports it because there isn't
		// a better way manually with CoreText that properly takes into account
		// system locale.
		//
		// References:
		// - http://unicode.org/charts/PDF/U4E00.pdf
		// - https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/platform/fonts/LocaleInFonts.md#unified-han-ideographs
		if desc.codepoint >= 0x4E00 && desc.codepoint <= 0x9FFF {
			han := ct.discover_codepoint(mut collection, desc)!
			if han.has_value {
				return CtDiscoverIterator{
					list:       [han.descriptor]
					variations: desc.variations
					i:          0
				}
			}
		}

		mut it := ct.discover(desc)!

		// If our normal discovery doesn't find anything and we have a specific
		// codepoint, then fall back to CTFontCreateForString to find a matching
		// font that CoreText wants to use.
		// See: https://github.com/ghostty-org/ghostty/issues/2499
		if it.list.len == 0 && desc.codepoint > 0 {
			ct_desc := ct.discover_codepoint(mut collection, desc)!
			if ct_desc.has_value {
				return CtDiscoverIterator{
					list:       [ct_desc.descriptor]
					variations: desc.variations
					i:          0
				}
			}
		}

		return it
	}

	// CtDescriptorValue preserves Ghostty's fallible optional descriptor result.
	// V cannot nest an Option inside a Result, so has_value represents the
	// optional layer while the containing Result preserves face-load failures.
	struct CtDescriptorValue {
		has_value  bool
		descriptor voidptr
	}

	// discover_codepoint discovers a font for a specific codepoint using the
	// CoreText CTFontCreateForString API, starting from the active collection face
	// that best matches the descriptor's requested style. Returns a retained
	// descriptor or none.
	fn (ct &CoreTextDiscovery) discover_codepoint(mut collection Collection, desc Descriptor) !CtDescriptorValue {
		_ = ct
		assert desc.codepoint > 0

		// The order matters: prefer an exact style, then progressively fall back
		// to the primary regular face.
		mut styles := []Style{}
		if desc.bold && desc.italic {
			styles << .bold_italic
		}
		if desc.bold {
			styles << .bold
		}
		if desc.italic {
			styles << .italic
		}
		styles << .regular

		mut seed_font := voidptr(unsafe { nil })
		for style in styles {
			if collection.face_count(style) == 0 {
				continue
			}
			// Ghostty uses `try collection.getFace` here. Once a requested style
			// has entries, failure to load its primary face must not silently fall
			// through to a different style.
			face := collection.get_face(Index.init(style, 0))!
			if !isnil(face.ct_font) {
				seed_font = face.ct_font
				break
			}
		}
		if isnil(seed_font) {
			return CtDescriptorValue{}
		}

		encoded := rune(desc.codepoint).str()
		str := macos.CFString.create_with_bytes(encoded.bytes(), .utf8, false)!
		defer { str.release() }

		mut unichars := []u16{len: 2}
		pair := macos.string_get_surrogate_pair_for_long_character(desc.codepoint,
			mut unichars)
		range_len := if pair { 2 } else { 1 }
		original := unsafe { &macos.CTFont(seed_font) }
		fallback := original.create_for_string(str, macos.CFRange.init(0, range_len)) or {
			return CtDescriptorValue{}
		}
		defer { fallback.release() }

		postscript_name := fallback.copy_post_script_name()!
		defer { postscript_name.release() }
		mut name_buf := []u8{len: 64}
		if name_ptr := postscript_name.cstring(mut name_buf, .utf8) {
			if unsafe { cstring_to_vstring(name_ptr) } == 'LastResort' {
				return CtDescriptorValue{}
			}
		}

		out := fallback.copy_descriptor()!
		return CtDescriptorValue{
			has_value:  true
			descriptor: voidptr(out)
		}
	}

	// CtDiscoverIterator iterates over CoreText discovery results.
	pub struct CtDiscoverIterator {
	pub mut:
		list       []voidptr // []&macos.CTFontDescriptor
		variations []Variation
		i          int
	}

	// deinit releases the iterator resources.
	pub fn (mut it CtDiscoverIterator) deinit() {
		for d in it.list {
			if !isnil(d) {
				macos.cf_release(d)
			}
		}
		it.list = []voidptr{}
	}

	// next returns the next deferred face or an empty value when exhausted.
	pub fn (mut it CtDiscoverIterator) next() !DeferredFaceValue {
		if it.i >= it.list.len {
			return DeferredFaceValue{}
		}
		src := it.list[it.i]

		// Get our descriptor. We remove the character-set limitation because we
		// may have used it to filter, but we don't want it anymore because it
		// would restrict the characters available on the loaded font.
		attrs := macos.CFMutableDictionary.create(0)!
		defer { attrs.release() }
		attrs.set_value(macos.CTFontAttribute.character_set.key(), macos.k_cf_null())
		src_descriptor := unsafe { &macos.CTFontDescriptor(src) }
		desc := src_descriptor.copy_with_attributes(attrs.as_dictionary())!
		defer { desc.release() }

		// Retain the discovered CTFont. File lookup is deferred until a
		// FreeType-backed render face is actually requested.
		font_ptr := voidptr(macos.CTFont.create_with_descriptor(desc, 12)!)
		it.i++
		return DeferredFaceValue{
			has_value: true
			face:      DeferredFace{
				coretext: CoreTextDeferredFace{
					ct_font:    font_ptr
					variations: it.variations.clone()
				}
			}
		}
	}

	// ============================================================
	// Score (for CoreText result sorting)
	// ============================================================
}
