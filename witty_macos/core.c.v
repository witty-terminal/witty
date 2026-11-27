module witty_macos

// Translated from:
// - ghostty/pkg/macos/foundation/base.zig
// - ghostty/pkg/macos/foundation/type.zig
// - ghostty/pkg/macos/foundation/string.zig
// - ghostty/pkg/macos/foundation/number.zig
// - ghostty/pkg/macos/foundation/dictionary.zig
// - ghostty/pkg/macos/foundation/array.zig
// - ghostty/pkg/macos/foundation/attributed_string.zig
// - ghostty/pkg/macos/foundation/data.zig
// - ghostty/pkg/macos/foundation/url.zig
// - ghostty/pkg/macos/foundation/character_set.zig
// - ghostty/pkg/macos/text.zig
// - ghostty/pkg/macos/text/c.zig
// - ghostty/pkg/macos/text/typesetter.zig
// - ghostty/pkg/macos/text/paragraph_style.zig
// - ghostty/pkg/macos/text/line.zig
// - ghostty/pkg/macos/text/run.zig
// - ghostty/pkg/macos/text/frame.zig
// - ghostty/pkg/macos/text/framesetter.zig
// - ghostty/pkg/macos/text/stylized_strings.zig
// - ghostty/pkg/macos/text/font_collection.zig
// - ghostty/pkg/macos/text/font_manager.zig
// - ghostty/pkg/macos/text/font_descriptor.zig
// - ghostty/pkg/macos/text/font.zig
// - ghostty/pkg/macos/graphics/affine_transform.zig
// - ghostty/pkg/macos/graphics/geometry.zig
// - ghostty/pkg/macos/graphics/font.zig
// - ghostty/pkg/macos/graphics/color_space.zig
// - ghostty/pkg/macos/graphics/path.zig
// - ghostty/pkg/macos/graphics/bitmap_context.zig
// - ghostty/pkg/macos/graphics/context.zig
// - ghostty/pkg/macos/graphics/image.zig
// - ghostty/pkg/macos/iosurface/iosurface.zig
// - ghostty/pkg/macos/iosurface.zig
// - ghostty/pkg/macos/iosurface/c.zig
// - ghostty/pkg/macos/video/pixel_format.zig
// - ghostty/pkg/macos/foundation/c.zig
// - ghostty/pkg/macos/foundation.zig
// - ghostty/pkg/macos/os/log.zig
// - ghostty/pkg/macos/os/signpost.zig
// - ghostty/pkg/macos/os/c.zig
// - ghostty/pkg/macos/os.zig
// - ghostty/pkg/macos/main.zig
// - ghostty/pkg/macos/carbon/c.zig
// - ghostty/pkg/macos/carbon.zig
// - ghostty/pkg/macos/build.zig

$if macos || ios {
	#flag -framework CoreFoundation

	#flag -framework CoreText

	#flag -framework CoreGraphics

	#flag -framework CoreVideo

	#flag -framework QuartzCore

	#flag -framework IOSurface

	$if macos {
		#flag -framework Carbon
	}

	// The framework headers are only for native code: FastC's TinyCC units cannot parse them.
	#include "@VMODROOT/witty_macos/core_frameworks.h"

	fn C.CFRelease(obj voidptr)

	fn C.CFRetain(obj voidptr) voidptr

	fn C.CFStringCreateWithBytes(alloc voidptr, bytes voidptr, bytes_len int, encoding u32, external bool) voidptr

	fn C.CFStringCreateWithCharactersNoCopy(alloc voidptr, chars voidptr, chars_len int, deallocator voidptr) voidptr

	fn C.CFStringCreateMutable(alloc voidptr, max_len int) voidptr

	fn C.CFStringAppendCharacters(str voidptr, chars voidptr, chars_len int)

	fn C.CFStringGetLength(str voidptr) int

	fn C.CFStringHasPrefix(str voidptr, prefix voidptr) int

	fn C.CFStringCompare(str voidptr, other voidptr, opts u32) int

	fn C.CFStringGetCString(str voidptr, buffer &char, buffer_size int, encoding u32) int

	fn C.CFStringGetCStringPtr(str voidptr, encoding u32) &char

	fn C.CFStringGetSurrogatePairForLongCharacter(cp u32, surrogates voidptr) int

	fn C.CFNumberCreate(alloc voidptr, number_type i64, value_ptr voidptr) voidptr

	fn C.CFNumberGetValue(number voidptr, number_type i64, value_ptr voidptr) int

	fn C.CFDictionaryCreate(alloc voidptr, keys voidptr, values voidptr, count int, key_cb voidptr, value_cb voidptr) voidptr

	fn C.CFDictionaryCreateMutable(alloc voidptr, cap int, key_cb voidptr, value_cb voidptr) voidptr

	fn C.CFDictionaryCreateMutableCopy(alloc voidptr, cap int, src voidptr) voidptr

	fn C.CFDictionarySetValue(dict voidptr, key voidptr, value voidptr)

	fn C.CFDictionaryGetCount(dict voidptr) int

	fn C.CFDictionaryGetValue(dict voidptr, key voidptr) voidptr

	fn C.CFDictionaryGetKeysAndValues(dict voidptr, keys voidptr, values voidptr)

	fn C.CFArrayCreate(alloc voidptr, values voidptr, count int, callbacks voidptr) voidptr

	fn C.CFArrayCreateMutable(alloc voidptr, cap int, callbacks voidptr) voidptr

	fn C.CFArrayAppendValue(arr voidptr, value voidptr)

	fn C.CFArrayGetCount(arr voidptr) int

	fn C.CFArrayGetValueAtIndex(arr voidptr, idx int) voidptr

	fn C.CFAttributedStringCreate(alloc voidptr, str voidptr, attrs voidptr) voidptr

	fn C.CFAttributedStringCreateMutable(alloc voidptr, max_len int) voidptr

	fn C.CFAttributedStringGetLength(str voidptr) int

	fn C.CFAttributedStringGetString(str voidptr) voidptr

	fn C.CFDataCreateWithBytesNoCopy(alloc voidptr, bytes voidptr, bytes_len int, deallocator voidptr) voidptr

	fn C.CFDataGetBytePtr(data voidptr) voidptr

	fn C.CFDataGetLength(data voidptr) int

	fn C.CFURLCreateWithString(alloc voidptr, url_string voidptr, base_url voidptr) voidptr

	fn C.CFURLCreateWithFileSystemPath(alloc voidptr, path voidptr, style int, dir int) voidptr

	fn C.CFURLCreateStringByReplacingPercentEscapes(alloc voidptr, original voidptr, escape voidptr) voidptr

	fn C.CFURLCopyPath(url voidptr) voidptr

	fn C.CFCharacterSetCreateWithCharactersInString(alloc voidptr, str voidptr) voidptr

	fn C.CTTypesetterCreateWithAttributedStringAndOptions(str voidptr, opts voidptr) voidptr

	fn C.CTFrameGetLines(frame voidptr) voidptr

	fn C.CTFramesetterCreateWithAttributedString(str voidptr) voidptr

	fn C.CTLineGetGlyphCount(line voidptr) int

	fn C.CTLineGetGlyphRuns(line voidptr) voidptr

	fn C.CTRunGetStatus(run voidptr) u32

	fn C.CTRunGetGlyphCount(run voidptr) int

	fn C.CGContextRelease(ctx voidptr)

	fn C.CGContextSetLineWidth(ctx voidptr, width f64)

	fn C.CGContextSetAllowsAntialiasing(ctx voidptr, v bool)

	fn C.CGContextSetAllowsFontSmoothing(ctx voidptr, v bool)

	fn C.CGContextSetAllowsFontSubpixelPositioning(ctx voidptr, v bool)

	fn C.CGContextSetAllowsFontSubpixelQuantization(ctx voidptr, v bool)

	fn C.CGContextSetShouldAntialias(ctx voidptr, v bool)

	fn C.CGContextSetShouldSmoothFonts(ctx voidptr, v bool)

	fn C.CGContextSetShouldSubpixelPositionFonts(ctx voidptr, v bool)

	fn C.CGContextSetShouldSubpixelQuantizeFonts(ctx voidptr, v bool)

	fn C.CGContextSetGrayFillColor(ctx voidptr, gray f64, alpha f64)

	fn C.CGContextSetGrayStrokeColor(ctx voidptr, gray f64, alpha f64)

	fn C.CGContextSetRGBFillColor(ctx voidptr, r f64, g f64, b f64, alpha f64)

	fn C.CGContextSetRGBStrokeColor(ctx voidptr, r f64, g f64, b f64, alpha f64)

	fn C.CGContextSetTextDrawingMode(ctx voidptr, mode int)

	fn C.CGContextSetTextPosition(ctx voidptr, x f64, y f64)

	fn C.CGContextScaleCTM(ctx voidptr, sx f64, sy f64)

	fn C.CGContextTranslateCTM(ctx voidptr, tx f64, ty f64)

	fn C.CTFontCollectionCreateFromAvailableFonts(opts voidptr) voidptr

	fn C.CTFontCollectionCreateWithFontDescriptors(descs voidptr, opts voidptr) voidptr

	fn C.CTFontCollectionCreateMatchingFontDescriptors(collection voidptr) voidptr

	fn C.CTFontManagerCreateFontDescriptorsFromURL(url voidptr) voidptr

	fn C.CTFontManagerCreateFontDescriptorsFromData(data voidptr) voidptr

	fn C.CTFontManagerCreateFontDescriptorFromData(data voidptr) voidptr

	fn C.CTFontDescriptorCreateWithAttributes(attrs voidptr) voidptr

	fn C.CTFontDescriptorCreateWithNameAndSize(name voidptr, size f64) voidptr

	fn C.CTFontDescriptorCreateCopyWithAttributes(original voidptr, attrs voidptr) voidptr

	fn C.CTFontDescriptorCreateCopyWithVariation(original voidptr, id voidptr, value f64) voidptr

	fn C.CTFontDescriptorCopyAttribute(desc voidptr, attribute voidptr) voidptr

	fn C.CTFontGetGlyphCount(font voidptr) int

	fn C.CTFontCreateWithFontDescriptor(desc voidptr, size f64, matrix voidptr) voidptr

	fn C.CTFontCreateCopyWithAttributes(font voidptr, size f64, matrix voidptr, desc voidptr) voidptr

	fn C.CTFontCopyFontDescriptor(font voidptr) voidptr

	fn C.CTFontCopyTable(font voidptr, tag u32, opts u32) voidptr

	fn C.CTFontCopyPostScriptName(font voidptr) voidptr

	fn C.CTFontCopyAttribute(font voidptr, attribute voidptr) voidptr

	fn C.CTFontCopyFamilyName(font voidptr) voidptr

	fn C.CTFontCopyDisplayName(font voidptr) voidptr

	fn C.CTFontGetSymbolicTraits(font voidptr) u32

	fn C.CTFontGetGlyphsForCharacters(font voidptr, characters &u16, glyphs &u16, count int) bool

	fn C.CTFontGetAdvancesForGlyphs(font voidptr, orientation u32, glyphs &u16, advances voidptr, count int) f64

	fn C.CTFontGetSize(font voidptr) f64

	fn C.CTFontGetAscent(font voidptr) f64

	fn C.CTFontGetDescent(font voidptr) f64

	fn C.CTFontGetLeading(font voidptr) f64

	fn C.CTFontGetCapHeight(font voidptr) f64

	fn C.CTFontGetXHeight(font voidptr) f64

	fn C.CTFontGetUnitsPerEm(font voidptr) u32

	fn C.CTFontDrawGlyphs(font voidptr, glyphs &u16, positions voidptr, count uint, context voidptr)

	fn C.vt_ct_typesetter_create_line(typesetter voidptr, location int, length int) voidptr

	fn C.vt_ctrun_get_glyphs_all(run voidptr, out_glyphs voidptr)

	fn C.vt_ctrun_get_advances_all(run voidptr, out_advances voidptr)

	fn C.vt_ctrun_get_positions_all(run voidptr, out_positions voidptr)

	fn C.vt_ctrun_get_string_indices_all(run voidptr, out_indices voidptr)

	fn C.vt_ctfont_get_bounding_rects_for_glyphs(font voidptr, orientation u32, glyphs &u16, rects voidptr, count uint, x &f64, y &f64, width &f64, height &f64)

	fn C.vt_ctfont_create_for_string(font voidptr, str voidptr, location int, length int) voidptr

	fn C.vt_ctparagraphstyle_create(settings_ptr voidptr, count uint) voidptr

	fn C.vt_ctframesetter_create_frame(framesetter_ptr voidptr, location int, length int, path_ptr voidptr, attrs_ptr voidptr) voidptr

	fn C.vt_ctframe_get_line_origins(frame_ptr voidptr, location int, length int, points_ptr voidptr)

	fn C.vt_cgrect_is_null(x f64, y f64, w f64, h f64) bool

	fn C.vt_cgpath_create_with_rect(x f64, y f64, w f64, h f64) voidptr

	fn C.vt_cgpath_create_mutable() voidptr

	fn C.vt_cgpath_add_rect(path voidptr, x f64, y f64, w f64, h f64)

	fn C.vt_cgpath_get_bounding_box(path voidptr, x &f64, y &f64, w &f64, h &f64)

	fn C.vt_cgcolorspace_create_device_gray() voidptr

	fn C.vt_cgcolorspace_create_device_rgb() voidptr

	fn C.vt_cgcolorspace_create_named(name_id int) voidptr

	fn C.vt_cgcolorspace_release(space voidptr)

	fn C.vt_cgbitmap_context_create(data voidptr, width uint, height uint, bits_per_component uint, bytes_per_row uint, space voidptr, opts u32) voidptr

	fn C.vt_cgcontext_set_text_matrix(ctx voidptr, a f64, b f64, c f64, d f64, tx f64, ty f64)

	fn C.vt_cgcontext_fill_rect(ctx voidptr, x f64, y f64, w f64, h f64)

	fn C.vt_dispatch_get_main_queue() voidptr

	fn C.vt_dispatch_data_create(data voidptr, len uint, queue voidptr) voidptr

	fn C.vt_dispatch_release(obj voidptr)

	fn C.vt_kca_gravity_top_left() voidptr

	fn C.vt_kca_gravity_bottom_left() voidptr

	fn C.vt_kca_gravity_center() voidptr



	fn C.vt_os_log_create(subsystem &char, category &char) voidptr

	fn C.vt_os_release(obj voidptr)

	fn C.vt_os_log_type_enabled(log voidptr, typ u8) bool

	fn C.vt_os_log_with_type_str(log voidptr, typ u8, msg &char)

	fn C.vt_os_signpost_enabled(log voidptr) bool

	fn C.vt_os_signpost_id_generate(log voidptr) u64

	fn C.vt_os_signpost_id_for_pointer(log voidptr, ptr voidptr) u64

	fn C.vt_os_signpost_event_emit(log voidptr, id u64, name &char)

	fn C.vt_os_signpost_interval_begin(log voidptr, id u64, name &char)

	fn C.vt_os_signpost_interval_end(log voidptr, id u64, name &char)

	fn C.vt_iosurface_create(width int, height int, pixel_format u32, bytes_per_element int, colorspace voidptr) voidptr

	fn C.vt_iosurface_deinit(surface voidptr)

	fn C.vt_iosurface_retain(surface voidptr)

	fn C.vt_iosurface_release(surface voidptr)

	fn C.vt_iosurface_set_color_space(surface voidptr, colorspace voidptr)

	fn C.vt_iosurface_lock(surface voidptr)

	fn C.vt_iosurface_unlock(surface voidptr)

	fn C.vt_iosurface_get_alloc_size(surface voidptr) uint

	fn C.vt_iosurface_get_width(surface voidptr) uint

	fn C.vt_iosurface_get_height(surface voidptr) uint

	fn C.vt_iosurface_get_bytes_per_element(surface voidptr) uint

	fn C.vt_iosurface_get_bytes_per_row(surface voidptr) uint

	fn C.vt_iosurface_get_base_address(surface voidptr) voidptr

	fn C.vt_iosurface_get_element_width(surface voidptr) uint

	fn C.vt_iosurface_get_element_height(surface voidptr) uint

	fn C.vt_iosurface_get_pixel_format(surface voidptr) u32

	// Exposed by core_shims.h for CF callback structs and CF/CoreText constants.
	fn C.vt_cf_allocator_null() voidptr

	fn C.vt_cf_type_dictionary_key_callbacks() voidptr

	fn C.vt_cf_type_dictionary_value_callbacks() voidptr

	fn C.vt_cf_type_array_callbacks() voidptr

	fn C.vt_cf_character_set_create_with_range(location int, length int) voidptr

	fn C.vt_k_ct_font_open_type_feature_tag() voidptr

	fn C.vt_k_ct_font_open_type_feature_value() voidptr

	fn C.vt_k_ct_font_feature_settings_attribute() voidptr

	fn C.vt_k_ct_typesetter_option_forced_embedding_level() voidptr

	fn C.vt_k_ct_paragraph_style_attribute_name() voidptr

	fn C.vt_k_ct_writing_direction_attribute_name() voidptr

	fn C.vt_k_cf_null() voidptr

	fn C.vt_ct_font_attribute(attribute int) voidptr

	fn C.vt_ct_font_trait_key(key int) voidptr

	fn C.vt_ct_font_variation_axis_key(key int) voidptr

	fn C.vt_cfattributedstring_replace_string(str voidptr, location int, length int, replacement voidptr)

	fn C.vt_cfattributedstring_set_attribute(str voidptr, location int, length int, key voidptr, value voidptr)

	@[inline]
	fn cast_cf_ref[T](ptr voidptr) &T {
		return unsafe { &T(ptr) }
	}

	@[inline]
	fn require_cf_ref[T](ptr voidptr, name string) !&T {
		if isnil(ptr) {
			return error('${name} failed')
		}
		return cast_cf_ref[T](ptr)
	}

	// ============================================================
	// CoreFoundation base
	// ============================================================

	// CFRelease releases a CoreFoundation object.
	pub fn cf_release(obj voidptr) {
		if !isnil(obj) {
			C.CFRelease(obj)
		}
	}

	// CFRetain retains a CoreFoundation object.
	pub fn cf_retain(obj voidptr) voidptr {
		if isnil(obj) {
			return unsafe { nil }
		}
		return C.CFRetain(obj)
	}

	pub enum ComparisonResult as int {
		less    = -1
		equal   = 0
		greater = 1
	}

	pub type FourCharCode = u32

	pub type StringComparison = u32

	pub const string_compare_case_insensitive = StringComparison(1 << 0)
	pub const string_compare_backwards = StringComparison(1 << 2)
	pub const string_compare_anchored = StringComparison(1 << 3)
	pub const string_compare_nonliteral = StringComparison(1 << 4)
	pub const string_compare_localized = StringComparison(1 << 5)
	pub const string_compare_numerically = StringComparison(1 << 6)
	pub const string_compare_diacritic_insensitive = StringComparison(1 << 7)
	pub const string_compare_width_insensitive = StringComparison(1 << 8)
	pub const string_compare_forced_ordering = StringComparison(1 << 9)

	// ============================================================
	// foundation.String
	// ============================================================

	pub struct CFString {}

	// Create a CFString from a slice of UTF-16 characters (no-copy).
	pub fn CFString.create_with_characters_no_copy(unichars []u16) &CFString {
		mut chars_ptr := voidptr(unsafe { nil })
		if unichars.len > 0 {
			chars_ptr = voidptr(unichars.data)
		}
		ptr := C.CFStringCreateWithCharactersNoCopy(unsafe { nil }, chars_ptr, int(unichars.len), C.vt_cf_allocator_null())
		if isnil(ptr) {
			// Maintain prior non-error API: return a null-like pointer on failure.
			return unsafe { &CFString(nil) }
		}
		return cast_cf_ref[CFString](ptr)
	}

	// Create a CFString from bytes with the given encoding.
	pub fn CFString.create_with_bytes(bytes []u8, encoding Encoding, external_rep bool) !&CFString {
		mut bytes_ptr := voidptr(unsafe { nil })
		if bytes.len > 0 {
			bytes_ptr = voidptr(bytes.data)
		}
		ptr := C.CFStringCreateWithBytes(unsafe { nil }, bytes_ptr, int(bytes.len), u32(encoding), external_rep)
		return require_cf_ref[CFString](ptr, 'CFStringCreateWithBytes')
	}

	pub fn (s &CFString) release() {
		cf_release(voidptr(s))
	}

	pub fn (s &CFString) get_length() int {
		return int(C.CFStringGetLength(voidptr(s)))
	}

	pub fn (s &CFString) has_prefix(prefix &CFString) bool {
		return C.CFStringHasPrefix(voidptr(s), voidptr(prefix)) != 0
	}

	pub fn (s &CFString) compare(other &CFString, options StringComparison) ComparisonResult {
		return unsafe { ComparisonResult(C.CFStringCompare(voidptr(s), voidptr(other), options)) }
	}

	pub fn (s &CFString) cstring(mut buf []u8, encoding Encoding) ?&char {
		if buf.len == 0 {
			return none
		}
		mut ptr := unsafe { &char(nil) }
		ptr = unsafe { &char(buf.data) }
		if C.CFStringGetCString(voidptr(s), ptr, int(buf.len), u32(encoding)) == 0 {
			return none
		}
		return ptr
	}

	pub fn (s &CFString) cstring_ptr(encoding Encoding) ?&char {
		ptr := C.CFStringGetCStringPtr(voidptr(s), u32(encoding))
		if isnil(ptr) {
			return none
		}
		return ptr
	}

	pub enum Encoding as u32 {
		invalid         = 0xffffffff
		mac_roman       = 0
		windows_latin_1 = 0x0500
		iso_latin_1     = 0x0201
		nextstep_latin  = 0x0b01
		ascii           = 0x0600
		unicode         = 0x0100
		utf8            = 0x08000100
		non_lossy_ascii = 0x0bff
		utf16_be        = 0x10000100
		utf16_le        = 0x14000100
		utf32           = 0x0c000100
		utf32_be        = 0x18000100
		utf32_le        = 0x1c000100
	}

	pub struct CFMutableString {}

	pub fn CFMutableString.create(cap uint) !&CFMutableString {
		ptr := C.CFStringCreateMutable(unsafe { nil }, int(cap))
		return require_cf_ref[CFMutableString](ptr, 'CFStringCreateMutable')
	}

	pub fn (s &CFMutableString) release() {
		cf_release(voidptr(s))
	}

	pub fn (s &CFMutableString) as_string() &CFString {
		return cast_cf_ref[CFString](voidptr(s))
	}

	pub fn (s &CFMutableString) append_characters(chars []u16) {
		mut chars_ptr := voidptr(unsafe { nil })
		if chars.len > 0 {
			chars_ptr = voidptr(chars.data)
		}
		C.CFStringAppendCharacters(voidptr(s), chars_ptr, int(chars.len))
	}

	// SurrogatePair holds the result of UTF-16 surrogate pair encoding.
	pub struct SurrogatePair {
	pub:
		hi      u16
		lo      u16
		is_pair bool
	}

	// Get a surrogate pair for a character > U+FFFF.
	// Returns the high/low surrogates and whether the character required a pair.
	pub fn get_surrogate_pair(cp u32) SurrogatePair {
		mut pair := [u16(0), 0]!
		if C.CFStringGetSurrogatePairForLongCharacter(cp, voidptr(&pair[0])) != 0 {
			return SurrogatePair{
				hi:      pair[0]
				lo:      pair[1]
				is_pair: true
			}
		}
		return SurrogatePair{
			hi:      u16(cp)
			lo:      0
			is_pair: false
		}
	}

	pub fn string_get_surrogate_pair_for_long_character(ch u32, mut surrogates []u16) bool {
		if surrogates.len < 2 {
			return false
		}
		return C.CFStringGetSurrogatePairForLongCharacter(ch, voidptr(surrogates.data)) != 0
	}

	// ============================================================
	// foundation.Number
	// ============================================================

	pub struct CFNumber {}

	pub fn CFNumber.create(num_type NumberType, value_ptr voidptr) !&CFNumber {
		ptr := C.CFNumberCreate(unsafe { nil }, i64(num_type), value_ptr)
		return require_cf_ref[CFNumber](ptr, 'CFNumberCreate')
	}

	pub fn (n &CFNumber) get_value(num_type NumberType, value_ptr voidptr) bool {
		return C.CFNumberGetValue(voidptr(n), i64(num_type), value_ptr) != 0
	}

	pub fn (n &CFNumber) release() {
		cf_release(voidptr(n))
	}

	// CFNumberType is CF_ENUM(CFIndex, ...), and every supported macOS target has
	// a 64-bit CFIndex. V does not permit isize as an enum backing type.
	pub enum NumberType as i64 {
		sint8      = 1
		sint16     = 2
		sint32     = 3
		sint64     = 4
		float32    = 5
		float64    = 6
		char_      = 7
		short_     = 8
		int_type   = 9
		long_      = 10
		long_long  = 11
		float_     = 12
		double_    = 13
		cf_index   = 14
		ns_integer = 15
		cg_float   = 16
	}

	// ============================================================
	// foundation.Dictionary
	// ============================================================

	pub struct CFDictionary {}

	pub fn CFDictionary.create(keys []voidptr, values []voidptr) !&CFDictionary {
		if keys.len != values.len {
			return error('CFDictionaryCreate: keys/values length mismatch')
		}
		mut keys_ptr := voidptr(unsafe { nil })
		if keys.len > 0 {
			keys_ptr = voidptr(&keys[0])
		}
		mut values_ptr := voidptr(unsafe { nil })
		if values.len > 0 {
			values_ptr = voidptr(&values[0])
		}
		ptr := C.CFDictionaryCreate(unsafe { nil }, keys_ptr, values_ptr, int(keys.len), C.vt_cf_type_dictionary_key_callbacks(), C.vt_cf_type_dictionary_value_callbacks())
		return require_cf_ref[CFDictionary](ptr, 'CFDictionaryCreate')
	}

	pub fn (d &CFDictionary) get_count() int {
		return int(C.CFDictionaryGetCount(voidptr(d)))
	}

	pub fn (d &CFDictionary) get_value(key voidptr) voidptr {
		return C.CFDictionaryGetValue(voidptr(d), key)
	}

	pub fn (d &CFDictionary) get_keys_and_values(mut keys []voidptr, mut values []voidptr) bool {
		count := d.get_count()
		if keys.len < count || values.len < count {
			return false
		}
		mut keys_ptr := voidptr(unsafe { nil })
		if keys.len > 0 {
			keys_ptr = voidptr(keys.data)
		}
		mut values_ptr := voidptr(unsafe { nil })
		if values.len > 0 {
			values_ptr = voidptr(values.data)
		}
		C.CFDictionaryGetKeysAndValues(voidptr(d), keys_ptr, values_ptr)
		return true
	}

	pub fn (d &CFDictionary) release() {
		cf_release(voidptr(d))
	}

	pub struct CFMutableDictionary {}

	pub fn CFMutableDictionary.create(cap uint) !&CFMutableDictionary {
		ptr := C.CFDictionaryCreateMutable(unsafe { nil }, int(cap), C.vt_cf_type_dictionary_key_callbacks(), C.vt_cf_type_dictionary_value_callbacks())
		return require_cf_ref[CFMutableDictionary](ptr, 'CFDictionaryCreateMutable')
	}

	pub fn CFMutableDictionary.create_mutable_copy(cap uint, src &CFDictionary) !&CFMutableDictionary {
		ptr := C.CFDictionaryCreateMutableCopy(unsafe { nil }, int(cap), voidptr(src))
		return require_cf_ref[CFMutableDictionary](ptr, 'CFDictionaryCreateMutableCopy')
	}

	pub fn (d &CFMutableDictionary) release() {
		cf_release(voidptr(d))
	}

	pub fn (d &CFMutableDictionary) set_value(key voidptr, value voidptr) {
		C.CFDictionarySetValue(voidptr(d), key, value)
	}

	pub fn (d &CFMutableDictionary) as_dictionary() &CFDictionary {
		return cast_cf_ref[CFDictionary](voidptr(d))
	}

	// ============================================================
	// foundation.Data
	// ============================================================

	pub struct CFData {}

	pub fn CFData.create_with_bytes_no_copy(data []u8) !&CFData {
		mut bytes_ptr := voidptr(unsafe { nil })
		if data.len > 0 {
			bytes_ptr = voidptr(data.data)
		}
		ptr := C.CFDataCreateWithBytesNoCopy(unsafe { nil }, bytes_ptr, int(data.len), C.vt_cf_allocator_null())
		return require_cf_ref[CFData](ptr, 'CFDataCreateWithBytesNoCopy')
	}

	pub fn (d &CFData) release() {
		cf_release(voidptr(d))
	}

	pub fn (d &CFData) get_pointer() &u8 {
		return unsafe { &u8(C.CFDataGetBytePtr(voidptr(d))) }
	}

	pub fn (d &CFData) get_length() int {
		return int(C.CFDataGetLength(voidptr(d)))
	}

	// ============================================================
	// foundation.URL
	// ============================================================

	pub struct CFURL {}

	pub enum URLPathStyle as int {
		posix   = 0
		windows = 2
	}

	pub fn CFURL.create_with_string(str &CFString, base &CFURL) !&CFURL {
		ptr := C.CFURLCreateWithString(unsafe { nil }, voidptr(str), voidptr(base))
		return require_cf_ref[CFURL](ptr, 'CFURLCreateWithString')
	}

	pub fn CFURL.create_with_file_system_path(path &CFString, style URLPathStyle, dir bool) !&CFURL {
		ptr := C.CFURLCreateWithFileSystemPath(unsafe { nil }, voidptr(path), int(style), if dir {
			1
		} else {
			0
		})
		return require_cf_ref[CFURL](ptr, 'CFURLCreateWithFileSystemPath')
	}

	pub fn CFURL.create_string_by_replacing_percent_escapes(str &CFString, escape &CFString) !&CFString {
		ptr := C.CFURLCreateStringByReplacingPercentEscapes(unsafe { nil }, voidptr(str), voidptr(escape))
		return require_cf_ref[CFString](ptr, 'CFURLCreateStringByReplacingPercentEscapes')
	}

	pub fn (u &CFURL) release() {
		cf_release(voidptr(u))
	}

	pub fn (u &CFURL) copy_path() ?&CFString {
		ptr := C.CFURLCopyPath(voidptr(u))
		if isnil(ptr) {
			return none
		}
		return cast_cf_ref[CFString](ptr)
	}

	// ============================================================
	// foundation.CharacterSet
	// ============================================================

	pub struct CFCharacterSet {}

	pub fn CFCharacterSet.create_with_characters_in_string(str &CFString) !&CFCharacterSet {
		ptr := C.CFCharacterSetCreateWithCharactersInString(unsafe { nil }, voidptr(str))
		return require_cf_ref[CFCharacterSet](ptr, 'CFCharacterSetCreateWithCharactersInString')
	}

	pub fn CFCharacterSet.create_with_characters_in_range(range CFRange) !&CFCharacterSet {
		ptr := C.vt_cf_character_set_create_with_range(range.location, range.length)
		return require_cf_ref[CFCharacterSet](ptr, 'CFCharacterSetCreateWithCharactersInRange')
	}

	pub fn (cset &CFCharacterSet) release() {
		cf_release(voidptr(cset))
	}

	// ============================================================
	// foundation.MutableArray
	// ============================================================

	pub struct CFMutableArray {}

	pub fn CFMutableArray.create() !&CFMutableArray {
		ptr := C.CFArrayCreateMutable(unsafe { nil }, 0, C.vt_cf_type_array_callbacks())
		return require_cf_ref[CFMutableArray](ptr, 'CFArrayCreateMutable')
	}

	pub fn (mut a CFMutableArray) append_value(val voidptr) {
		C.CFArrayAppendValue(voidptr(&a), val)
	}

	pub fn (a &CFMutableArray) release() {
		cf_release(voidptr(a))
	}

	// ============================================================
	// foundation.AttributedString
	// ============================================================

	pub struct CFAttributedString {}

	pub fn CFAttributedString.create(str &CFString, attrs &CFDictionary) !&CFAttributedString {
		ptr := C.CFAttributedStringCreate(unsafe { nil }, voidptr(str), voidptr(attrs))
		return require_cf_ref[CFAttributedString](ptr, 'CFAttributedStringCreate')
	}

	pub fn (s &CFAttributedString) get_length() int {
		return int(C.CFAttributedStringGetLength(voidptr(s)))
	}

	pub fn (s &CFAttributedString) get_string() &CFString {
		return cast_cf_ref[CFString](C.CFAttributedStringGetString(voidptr(s)))
	}

	pub fn (s &CFAttributedString) release() {
		cf_release(voidptr(s))
	}

	pub struct CFMutableAttributedString {}

	pub fn CFMutableAttributedString.create(cap uint) !&CFMutableAttributedString {
		ptr := C.CFAttributedStringCreateMutable(unsafe { nil }, int(cap))
		return require_cf_ref[CFMutableAttributedString](ptr, 'CFAttributedStringCreateMutable')
	}

	pub fn (s &CFMutableAttributedString) release() {
		cf_release(voidptr(s))
	}

	pub fn (s &CFMutableAttributedString) replace_string(range CFRange, replacement &CFString) {
		C.vt_cfattributedstring_replace_string(voidptr(s), range.location, range.length, voidptr(replacement))
	}

	pub fn (s &CFMutableAttributedString) set_attribute(range CFRange, key voidptr, value voidptr) {
		C.vt_cfattributedstring_set_attribute(voidptr(s), range.location, range.length, key, value)
	}

	pub fn (s &CFMutableAttributedString) get_length() int {
		return int(C.CFAttributedStringGetLength(voidptr(s)))
	}

	// ============================================================
	// text.Typesetter
	// ============================================================

	pub struct CTTypesetter {}

	pub fn CTTypesetter.create_with_attributed_string_and_options(attr_str &CFAttributedString, opts &CFDictionary) !&CTTypesetter {
		ptr := C.CTTypesetterCreateWithAttributedStringAndOptions(voidptr(attr_str), voidptr(opts))
		return require_cf_ref[CTTypesetter](ptr, 'CTTypesetterCreateWithAttributedStringAndOptions')
	}

	pub fn (t &CTTypesetter) create_line(range CFRange) &CTLine {
		ptr := C.vt_ct_typesetter_create_line(voidptr(t), range.location, range.length)
		if isnil(ptr) {
			return unsafe { &CTLine(nil) }
		}
		return cast_cf_ref[CTLine](ptr)
	}

	pub fn (t &CTTypesetter) release() {
		cf_release(voidptr(t))
	}

	pub struct CFRange {
	pub:
		location int
		length   int
	}

	pub fn CFRange.init(location int, length int) CFRange {
		return CFRange{
			location: int(location)
			length:   int(length)
		}
	}

	// ============================================================
	// text.ParagraphStyle
	// ============================================================

	pub struct CTParagraphStyle {}

	pub struct CTParagraphStyleSetting {
	pub:
		spec       CTParagraphStyleSpecifier
		value_size uint
		value      voidptr
	}

	pub enum CTParagraphStyleSpecifier as u32 {
		base_writing_direction = 13
	}

	pub enum WritingDirection as int {
		natural = -1
		ltr     = 0
		rtl     = 1
		lro     = 2
		rlo     = 3
	}

	pub fn CTParagraphStyle.create(settings []CTParagraphStyleSetting) !&CTParagraphStyle {
		mut settings_ptr := voidptr(unsafe { nil })
		if settings.len > 0 {
			settings_ptr = voidptr(settings.data)
		}
		ptr := C.vt_ctparagraphstyle_create(settings_ptr, settings.len)
		return require_cf_ref[CTParagraphStyle](ptr, 'CTParagraphStyleCreate')
	}

	pub fn (p &CTParagraphStyle) release() {
		cf_release(voidptr(p))
	}

	// ============================================================
	// text.Line
	// ============================================================

	pub struct CTLine {}

	pub fn (l &CTLine) get_glyph_count() int {
		return int(C.CTLineGetGlyphCount(voidptr(l)))
	}

	pub fn (l &CTLine) get_glyph_runs() &CFArray {
		ptr := C.CTLineGetGlyphRuns(voidptr(l))
		if isnil(ptr) {
			return unsafe { &CFArray(nil) }
		}
		return cast_cf_ref[CFArray](ptr)
	}

	pub fn (l &CTLine) release() {
		cf_release(voidptr(l))
	}

	// ============================================================
	// text.Frame
	// ============================================================

	pub struct CTFrame {}

	pub fn (f &CTFrame) release() {
		cf_release(voidptr(f))
	}

	pub fn (f &CTFrame) get_line_origins(range CFRange, points []CGPoint) {
		if points.len == 0 {
			return
		}
		C.vt_ctframe_get_line_origins(voidptr(f), range.location, range.length, voidptr(points.data))
	}

	pub fn (f &CTFrame) get_lines() &CFArray {
		ptr := C.CTFrameGetLines(voidptr(f))
		if isnil(ptr) {
			return unsafe { &CFArray(nil) }
		}
		return cast_cf_ref[CFArray](ptr)
	}

	// ============================================================
	// text.Framesetter
	// ============================================================

	pub struct CTFramesetter {}

	pub fn CTFramesetter.create_with_attributed_string(str &CFAttributedString) !&CTFramesetter {
		ptr := C.CTFramesetterCreateWithAttributedString(voidptr(str))
		return require_cf_ref[CTFramesetter](ptr, 'CTFramesetterCreateWithAttributedString')
	}

	pub fn (f &CTFramesetter) release() {
		cf_release(voidptr(f))
	}

	pub fn (f &CTFramesetter) create_frame(range CFRange, path &CGPath, attrs ?&CFDictionary) !&CTFrame {
		mut attrs_ptr := voidptr(unsafe { nil })
		if attrs_ := attrs {
			attrs_ptr = voidptr(attrs_)
		}
		ptr := C.vt_ctframesetter_create_frame(voidptr(f), range.location, range.length, voidptr(path), attrs_ptr)
		return require_cf_ref[CTFrame](ptr, 'CTFramesetterCreateFrame')
	}

	// ============================================================
	// text.Run
	// ============================================================

	pub struct CTRun {}

	pub fn (r &CTRun) get_status() CTRunStatus {
		raw := C.CTRunGetStatus(voidptr(r))
		return CTRunStatus{
			right_to_left: (raw & u32(1)) != 0
			non_monotonic: (raw & u32(2)) != 0
		}
	}

	pub fn (r &CTRun) get_glyphs() []u32 {
		count := r.get_glyph_count()
		if count <= 0 {
			return []u32{}
		}

		mut buf := []u16{len: count}
		C.vt_ctrun_get_glyphs_all(voidptr(r), voidptr(buf.data))

		mut out := []u32{len: count}
		for i in 0 .. count {
			out[i] = u32(buf[i])
		}
		return out
	}

	pub fn (r &CTRun) get_advances() []CGSize {
		count := r.get_glyph_count()
		if count <= 0 {
			return []CGSize{}
		}
		mut out := []CGSize{len: count}
		C.vt_ctrun_get_advances_all(voidptr(r), voidptr(out.data))
		return out
	}

	pub fn (r &CTRun) get_positions() []CGPoint {
		count := r.get_glyph_count()
		if count <= 0 {
			return []CGPoint{}
		}
		mut out := []CGPoint{len: count}
		C.vt_ctrun_get_positions_all(voidptr(r), voidptr(out.data))
		return out
	}

	pub fn (r &CTRun) get_string_indices() []int {
		count := r.get_glyph_count()
		if count <= 0 {
			return []int{}
		}
		mut tmp := []int{len: count}
		C.vt_ctrun_get_string_indices_all(voidptr(r), voidptr(tmp.data))
		mut out := []int{len: count}
		for i in 0 .. count {
			out[i] = int(tmp[i])
		}
		return out
	}

	pub fn (r &CTRun) get_glyph_count() int {
		return int(C.CTRunGetGlyphCount(voidptr(r)))
	}

	pub struct CTRunStatus {
	pub:
		non_monotonic bool
		right_to_left bool
	}

	// ============================================================
	// text.FontDescriptor
	// ============================================================

	pub struct CTFontDescriptor {}

	pub enum CTFontAttribute as u8 {
		url
		name
		display_name
		family_name
		style_name
		traits
		variation
		size
		matrix
		cascade_list
		character_set
		languages
		baseline_adjust
		macintosh_encodings
		features
		feature_settings
		fixed_advance
		orientation
		format
		registration_scope
		priority
		enabled
		downloadable
		downloaded
		variation_axes
	}

	pub fn (a CTFontAttribute) key() voidptr {
		return C.vt_ct_font_attribute(int(a))
	}

	pub enum CTFontTraitKey as u8 {
		symbolic
		weight
		width
		slant
	}

	pub fn (k CTFontTraitKey) key() voidptr {
		return C.vt_ct_font_trait_key(int(k))
	}

	pub enum CTFontVariationAxisKey as u8 {
		identifier
		minimum_value
		maximum_value
		default_value
		name
		hidden
	}

	pub fn (k CTFontVariationAxisKey) key() voidptr {
		return C.vt_ct_font_variation_axis_key(int(k))
	}

	pub fn k_cf_null() voidptr {
		return C.vt_k_cf_null()
	}

	pub fn CTFontDescriptor.create_with_attributes(attrs &CFDictionary) !&CTFontDescriptor {
		ptr := C.CTFontDescriptorCreateWithAttributes(voidptr(attrs))
		return require_cf_ref[CTFontDescriptor](ptr, 'CTFontDescriptorCreateWithAttributes')
	}

	pub fn CTFontDescriptor.create_with_name_and_size(name &CFString, size f64) !&CTFontDescriptor {
		ptr := C.CTFontDescriptorCreateWithNameAndSize(voidptr(name), size)
		return require_cf_ref[CTFontDescriptor](ptr, 'CTFontDescriptorCreateWithNameAndSize')
	}

	pub fn (d &CTFontDescriptor) copy_with_attributes(attrs &CFDictionary) !&CTFontDescriptor {
		ptr := C.CTFontDescriptorCreateCopyWithAttributes(voidptr(d), voidptr(attrs))
		return require_cf_ref[CTFontDescriptor](ptr, 'CTFontDescriptorCreateCopyWithAttributes')
	}

	pub fn (d &CTFontDescriptor) copy_with_variation(id &CFNumber, value f64) !&CTFontDescriptor {
		ptr := C.CTFontDescriptorCreateCopyWithVariation(voidptr(d), voidptr(id), value)
		return require_cf_ref[CTFontDescriptor](ptr, 'CTFontDescriptorCreateCopyWithVariation')
	}

	pub fn (d &CTFontDescriptor) copy_attribute(attribute CTFontAttribute) ?voidptr {
		ptr := C.CTFontDescriptorCopyAttribute(voidptr(d), attribute.key())
		if isnil(ptr) {
			return none
		}
		return ptr
	}

	pub fn (d &CTFontDescriptor) release() {
		cf_release(voidptr(d))
	}

	// ============================================================
	// text.Font (CTFont)
	// ============================================================

	pub struct CTFont {}

	pub type CTFontTableTag = u32

	pub enum CTFontOrientation as u32 {
		default_
		horizontal
		vertical
	}

	pub fn CTFontTableTag.init(tag string) CTFontTableTag {
		assert tag.len == 4
		return CTFontTableTag(u32(tag[0]) << 24 | u32(tag[1]) << 16 | u32(tag[2]) << 8 |
			u32(tag[3]))
	}

	pub struct CTFontSymbolicTraits {
	pub:
		italic       bool
		bold         bool
		expanded     bool
		condensed    bool
		monospace    bool
		vertical     bool
		ui_optimized bool
		color_glyphs bool
		composite    bool
	}

	pub fn CTFontSymbolicTraits.from_raw(raw u32) CTFontSymbolicTraits {
		return CTFontSymbolicTraits{
			italic:       raw & (u32(1) << 0) != 0
			bold:         raw & (u32(1) << 1) != 0
			expanded:     raw & (u32(1) << 5) != 0
			condensed:    raw & (u32(1) << 6) != 0
			monospace:    raw & (u32(1) << 10) != 0
			vertical:     raw & (u32(1) << 11) != 0
			ui_optimized: raw & (u32(1) << 12) != 0
			color_glyphs: raw & (u32(1) << 13) != 0
			composite:    raw & (u32(1) << 14) != 0
		}
	}

	pub fn (f &CTFont) copy_with_attributes(size f64, matrix voidptr, desc voidptr) !&CTFont {
		ptr := C.CTFontCreateCopyWithAttributes(voidptr(f), size, matrix, desc)
		return require_cf_ref[CTFont](ptr, 'CTFontCreateCopyWithAttributes')
	}

	pub fn (f &CTFont) copy_descriptor() !&CTFontDescriptor {
		ptr := C.CTFontCopyFontDescriptor(voidptr(f))
		return require_cf_ref[CTFontDescriptor](ptr, 'CTFontCopyFontDescriptor')
	}

	pub fn (f &CTFont) copy_table(tag CTFontTableTag) ?&CFData {
		ptr := C.CTFontCopyTable(voidptr(f), u32(tag), 0)
		if isnil(ptr) {
			return none
		}
		return cast_cf_ref[CFData](ptr)
	}

	pub fn (f &CTFont) copy_post_script_name() !&CFString {
		ptr := C.CTFontCopyPostScriptName(voidptr(f))
		return require_cf_ref[CFString](ptr, 'CTFontCopyPostScriptName')
	}

	pub fn (f &CTFont) copy_family_name() !&CFString {
		ptr := C.CTFontCopyFamilyName(voidptr(f))
		return require_cf_ref[CFString](ptr, 'CTFontCopyFamilyName')
	}

	pub fn (f &CTFont) copy_display_name() !&CFString {
		ptr := C.CTFontCopyDisplayName(voidptr(f))
		return require_cf_ref[CFString](ptr, 'CTFontCopyDisplayName')
	}

	pub fn (f &CTFont) copy_attribute(attribute CTFontAttribute) ?voidptr {
		ptr := C.CTFontCopyAttribute(voidptr(f), attribute.key())
		if isnil(ptr) {
			return none
		}
		return ptr
	}

	pub fn (f &CTFont) get_symbolic_traits() CTFontSymbolicTraits {
		return CTFontSymbolicTraits.from_raw(C.CTFontGetSymbolicTraits(voidptr(f)))
	}

	pub fn (f &CTFont) get_glyph_count() int {
		return int(C.CTFontGetGlyphCount(voidptr(f)))
	}

	pub fn (f &CTFont) get_glyphs_for_characters(characters []u16, glyphs []CGGlyph) bool {
		assert characters.len == glyphs.len
		return C.CTFontGetGlyphsForCharacters(voidptr(f), characters.data, glyphs.data,
			int(characters.len))
	}

	pub fn (f &CTFont) get_advances_for_glyphs(orientation CTFontOrientation, glyphs []CGGlyph, advances voidptr) f64 {
		return C.CTFontGetAdvancesForGlyphs(voidptr(f), u32(orientation), glyphs.data, advances,
			int(glyphs.len))
	}

	pub fn (f &CTFont) get_bounding_rects_for_glyphs(orientation CTFontOrientation, glyphs []CGGlyph, rects []CGRect) CGRect {
		assert rects.len == 0 || rects.len == glyphs.len
		mut rects_ptr := voidptr(unsafe { nil })
		if rects.len > 0 {
			rects_ptr = voidptr(rects.data)
		}
		mut result := CGRect{}
		C.vt_ctfont_get_bounding_rects_for_glyphs(voidptr(f), u32(orientation), glyphs.data,
			rects_ptr, uint(glyphs.len), &result.origin.x, &result.origin.y, &result.size.width,
			&result.size.height)
		return result
	}

	pub fn (f &CTFont) get_size() f64 {
		return C.CTFontGetSize(voidptr(f))
	}

	pub fn (f &CTFont) get_ascent() f64 {
		return C.CTFontGetAscent(voidptr(f))
	}

	pub fn (f &CTFont) get_descent() f64 {
		return C.CTFontGetDescent(voidptr(f))
	}

	pub fn (f &CTFont) get_leading() f64 {
		return C.CTFontGetLeading(voidptr(f))
	}

	pub fn (f &CTFont) get_cap_height() f64 {
		return C.CTFontGetCapHeight(voidptr(f))
	}

	pub fn (f &CTFont) get_x_height() f64 {
		return C.CTFontGetXHeight(voidptr(f))
	}

	pub fn (f &CTFont) get_units_per_em() u32 {
		return C.CTFontGetUnitsPerEm(voidptr(f))
	}

	pub fn (f &CTFont) create_for_string(str &CFString, range CFRange) ?&CTFont {
		ptr := C.vt_ctfont_create_for_string(voidptr(f), voidptr(str), range.location,
			range.length)
		if isnil(ptr) {
			return none
		}
		return cast_cf_ref[CTFont](ptr)
	}

	pub fn CTFont.create_with_descriptor(desc &CTFontDescriptor, size f64) !&CTFont {
		ptr := C.CTFontCreateWithFontDescriptor(voidptr(desc), size, unsafe { nil })
		return require_cf_ref[CTFont](ptr, 'CTFontCreateWithFontDescriptor')
	}

	pub fn (f &CTFont) release() {
		cf_release(voidptr(f))
	}

	pub fn (f &CTFont) draw_glyphs(glyphs []CGGlyph, positions []CGPoint, context &CGContext) {
		assert positions.len == glyphs.len
		C.CTFontDrawGlyphs(voidptr(f), glyphs.data, voidptr(positions.data), uint(glyphs.len),
			voidptr(context))
	}

	// ============================================================
	// text.StringAttribute
	// ============================================================

	pub enum StringAttribute as u8 {
		font
		paragraph_style
		writing_direction
	}

	pub fn (a StringAttribute) key() voidptr {
		match a {
			.font {
				return ct_font_attribute_name()
			}
			.paragraph_style {
				return k_ct_paragraph_style_attribute_name()
			}
			.writing_direction {
				return k_ct_writing_direction_attribute_name()
			}
		}
	}

	// ============================================================
	// CoreText constants
	// ============================================================

	// kCTFontOpenTypeFeatureTag
	pub fn k_ct_font_open_type_feature_tag() voidptr {
		return C.vt_k_ct_font_open_type_feature_tag()
	}

	// kCTFontOpenTypeFeatureValue
	pub fn k_ct_font_open_type_feature_value() voidptr {
		return C.vt_k_ct_font_open_type_feature_value()
	}

	// kCTFontFeatureSettingsAttribute
	pub fn k_ct_font_feature_settings_attribute() voidptr {
		return C.vt_k_ct_font_feature_settings_attribute()
	}

	// kCTTypesetterOptionForcedEmbeddingLevel
	pub fn k_ct_typesetter_option_forced_embedding_level() voidptr {
		return C.vt_k_ct_typesetter_option_forced_embedding_level()
	}

	// ============================================================
	// graphics
	// ============================================================

	pub struct CGAffineTransform {
	pub:
		a  f64
		b  f64
		c  f64
		d  f64
		tx f64
		ty f64
	}

	pub fn CGAffineTransform.identity() CGAffineTransform {
		return CGAffineTransform{
			a:  1
			b:  0
			c:  0
			d:  1
			tx: 0
			ty: 0
		}
	}

	pub struct CGPoint {
	pub:
		x f64
		y f64
	}

	pub struct CGSize {
	pub:
		width  f64
		height f64
	}

	pub struct CGRect {
	pub:
		origin CGPoint
		size   CGSize
	}

	pub fn CGRect.init(x f64, y f64, width f64, height f64) CGRect {
		return CGRect{
			origin: CGPoint{
				x: x
				y: y
			}
			size:   CGSize{
				width:  width
				height: height
			}
		}
	}

	pub fn (r CGRect) is_null() bool {
		return C.vt_cgrect_is_null(r.origin.x, r.origin.y, r.size.width, r.size.height)
	}

	pub fn (r CGRect) get_height() f64 {
		return r.size.height
	}

	pub fn (r CGRect) get_width() f64 {
		return r.size.width
	}

	pub type CGGlyph = u16

	pub enum CGImageAlphaInfo as u32 {
		none                = 0
		premultiplied_last  = 1
		premultiplied_first = 2
		last                = 3
		first               = 4
		none_skip_last      = 5
		none_skip_first     = 6
		only                = 7
	}

	pub enum CGBitmapInfo as u32 {
		alpha_mask           = 0x1F
		float_mask           = 0xF00
		float_components     = 0x100
		byte_order_mask      = 0x7000
		byte_order_default   = 0x0000
		byte_order_16_little = 0x1000
		byte_order_32_little = 0x2000
		byte_order_16_big    = 0x3000
		byte_order_32_big    = 0x4000
	}

	pub struct CGColorSpace {}

	pub enum CGColorSpaceName as u8 {
		display_p3
		extended_linear_display_p3
		srgb
		linear_srgb
		extended_srgb
		extended_linear_srgb
		generic_gray_gamma2_2
		linear_gray
		extended_gray
		extended_linear_gray
	}

	pub fn CGColorSpace.create_device_gray() !&CGColorSpace {
		ptr := C.vt_cgcolorspace_create_device_gray()
		return require_cf_ref[CGColorSpace](ptr, 'CGColorSpaceCreateDeviceGray')
	}

	pub fn CGColorSpace.create_device_rgb() !&CGColorSpace {
		ptr := C.vt_cgcolorspace_create_device_rgb()
		return require_cf_ref[CGColorSpace](ptr, 'CGColorSpaceCreateDeviceRGB')
	}

	pub fn CGColorSpace.create_named(name CGColorSpaceName) !&CGColorSpace {
		ptr := C.vt_cgcolorspace_create_named(int(name))
		return require_cf_ref[CGColorSpace](ptr, 'CGColorSpaceCreateWithName')
	}

	pub fn (s &CGColorSpace) release() {
		C.vt_cgcolorspace_release(voidptr(s))
	}

	pub struct CGPath {}

	pub fn CGPath.create_with_rect(rect CGRect) !&CGPath {
		ptr := C.vt_cgpath_create_with_rect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
		return require_cf_ref[CGPath](ptr, 'CGPathCreateWithRect')
	}

	pub fn (p &CGPath) release() {
		cf_release(voidptr(p))
	}

	pub struct CGMutablePath {}

	pub fn CGMutablePath.create() !&CGMutablePath {
		ptr := C.vt_cgpath_create_mutable()
		return require_cf_ref[CGMutablePath](ptr, 'CGPathCreateMutable')
	}

	pub fn (p &CGMutablePath) release() {
		cf_release(voidptr(p))
	}

	pub fn (p &CGMutablePath) add_rect(rect CGRect) {
		C.vt_cgpath_add_rect(voidptr(p), rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
	}

	pub fn (p &CGMutablePath) get_bounding_box() CGRect {
		mut x := f64(0)
		mut y := f64(0)
		mut w := f64(0)
		mut h := f64(0)
		C.vt_cgpath_get_bounding_box(voidptr(p), &x, &y, &w, &h)
		return CGRect.init(x, y, w, h)
	}

	pub enum CGContextTextDrawingMode as int {
		fill             = 0
		stroke           = 1
		fill_stroke      = 2
		invisible        = 3
		fill_clip        = 4
		stroke_clip      = 5
		fill_stroke_clip = 6
		clip             = 7
	}

	pub struct CGContext {}

	pub fn (ctx &CGContext) release() {
		C.CGContextRelease(voidptr(ctx))
	}

	pub fn (ctx &CGContext) set_line_width(width f64) {
		C.CGContextSetLineWidth(voidptr(ctx), width)
	}

	pub fn (ctx &CGContext) set_allows_antialiasing(v bool) {
		C.CGContextSetAllowsAntialiasing(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_allows_font_smoothing(v bool) {
		C.CGContextSetAllowsFontSmoothing(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_allows_font_subpixel_positioning(v bool) {
		C.CGContextSetAllowsFontSubpixelPositioning(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_allows_font_subpixel_quantization(v bool) {
		C.CGContextSetAllowsFontSubpixelQuantization(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_should_antialias(v bool) {
		C.CGContextSetShouldAntialias(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_should_smooth_fonts(v bool) {
		C.CGContextSetShouldSmoothFonts(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_should_subpixel_position_fonts(v bool) {
		C.CGContextSetShouldSubpixelPositionFonts(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_should_subpixel_quantize_fonts(v bool) {
		C.CGContextSetShouldSubpixelQuantizeFonts(voidptr(ctx), v)
	}

	pub fn (ctx &CGContext) set_gray_fill_color(gray f64, alpha f64) {
		C.CGContextSetGrayFillColor(voidptr(ctx), gray, alpha)
	}

	pub fn (ctx &CGContext) set_gray_stroke_color(gray f64, alpha f64) {
		C.CGContextSetGrayStrokeColor(voidptr(ctx), gray, alpha)
	}

	pub fn (ctx &CGContext) set_rgb_fill_color(r f64, g f64, b f64, alpha f64) {
		C.CGContextSetRGBFillColor(voidptr(ctx), r, g, b, alpha)
	}

	pub fn (ctx &CGContext) set_rgb_stroke_color(r f64, g f64, b f64, alpha f64) {
		C.CGContextSetRGBStrokeColor(voidptr(ctx), r, g, b, alpha)
	}

	pub fn (ctx &CGContext) set_text_drawing_mode(mode CGContextTextDrawingMode) {
		C.CGContextSetTextDrawingMode(voidptr(ctx), int(mode))
	}

	pub fn (ctx &CGContext) set_text_matrix(matrix CGAffineTransform) {
		C.vt_cgcontext_set_text_matrix(voidptr(ctx), matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty)
	}

	pub fn (ctx &CGContext) set_text_position(x f64, y f64) {
		C.CGContextSetTextPosition(voidptr(ctx), x, y)
	}

	pub fn (ctx &CGContext) fill_rect(rect CGRect) {
		C.vt_cgcontext_fill_rect(voidptr(ctx), rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
	}

	pub fn (ctx &CGContext) scale_ctm(sx f64, sy f64) {
		C.CGContextScaleCTM(voidptr(ctx), sx, sy)
	}

	pub fn (ctx &CGContext) translate_ctm(tx f64, ty f64) {
		C.CGContextTranslateCTM(voidptr(ctx), tx, ty)
	}

	pub struct CGBitmapContext {}

	pub fn CGBitmapContext.create(data []u8, width uint, height uint, bits_per_component uint, bytes_per_row uint, space &CGColorSpace, opts u32) !&CGBitmapContext {
		mut data_ptr := voidptr(unsafe { nil })
		if data.len > 0 {
			data_ptr = voidptr(data.data)
		}
		ptr := C.vt_cgbitmap_context_create(data_ptr, width, height, bits_per_component, bytes_per_row, voidptr(space), opts)
		return require_cf_ref[CGBitmapContext](ptr, 'CGBitmapContextCreate')
	}

	pub fn (ctx &CGBitmapContext) as_context() &CGContext {
		return cast_cf_ref[CGContext](voidptr(ctx))
	}

	// Upstream-style aliases from pkg/macos/graphics.zig.
	pub type AffineTransform = CGAffineTransform

	pub type Point = CGPoint

	pub type Size = CGSize

	pub type Rect = CGRect

	pub type Glyph = u16

	pub type ImageAlphaInfo = CGImageAlphaInfo

	pub type BitmapInfo = CGBitmapInfo

	pub type ColorSpace = CGColorSpace

	pub type Path = CGPath

	pub type MutablePath = CGMutablePath

	pub type TextDrawingMode = CGContextTextDrawingMode

	pub type BitmapContext = CGBitmapContext

	pub type Font = CTFont

	pub type FontTableTag = CTFontTableTag

	pub type FontOrientation = CTFontOrientation

	pub type FontDescriptor = CTFontDescriptor

	pub type FontAttribute = CTFontAttribute

	pub type FontTraitKey = CTFontTraitKey

	pub type FontVariationAxisKey = CTFontVariationAxisKey

	pub type FontCollection = CTFontCollection

	pub type Typesetter = CTTypesetter

	pub type Line = CTLine

	pub type Run = CTRun



	pub type Log = OSLog

	pub type AttributedString = CFAttributedString

	pub type MutableAttributedString = CFMutableAttributedString

	pub type Range = CFRange

	pub type CharacterSet = CFCharacterSet

	pub type Data = CFData

	pub type Dictionary = CFDictionary

	pub type MutableDictionary = CFMutableDictionary

	pub type Number = CFNumber

	pub type String = CFString

	pub type MutableString = CFMutableString

	pub type StringEncoding = Encoding

	pub type URL = CFURL

	pub type ParagraphStyle = CTParagraphStyle

	pub type ParagraphStyleSetting = CTParagraphStyleSetting

	pub type ParagraphStyleSpecifier = CTParagraphStyleSpecifier

	pub type Frame = CTFrame

	pub type Framesetter = CTFramesetter

	// ============================================================
	// CFArray (generic array wrapper)
	// ============================================================

	pub struct CFArray {}

	pub fn CFArray.create(values []voidptr) !&CFArray {
		mut values_ptr := voidptr(unsafe { nil })
		if values.len > 0 {
			values_ptr = voidptr(&values[0])
		}
		ptr := C.CFArrayCreate(unsafe { nil }, values_ptr, int(values.len), C.vt_cf_type_array_callbacks())
		return require_cf_ref[CFArray](ptr, 'CFArrayCreate')
	}

	pub fn (a &CFArray) get_count() int {
		return int(C.CFArrayGetCount(voidptr(a)))
	}

	pub fn (a &CFArray) get_value_at_index(idx int) voidptr {
		if idx < 0 || idx >= a.get_count() {
			return unsafe { nil }
		}
		return C.CFArrayGetValueAtIndex(voidptr(a), int(idx))
	}

	pub fn (a &CFArray) release() {
		cf_release(voidptr(a))
	}

	pub type Array = CFArray

	pub type MutableArray = CFMutableArray

	// ============================================================
	// text.stylized_strings
	// ============================================================

	pub fn k_ct_paragraph_style_attribute_name() voidptr {
		return C.vt_k_ct_paragraph_style_attribute_name()
	}

	pub fn k_ct_writing_direction_attribute_name() voidptr {
		return C.vt_k_ct_writing_direction_attribute_name()
	}

	// ============================================================
	// text.font_collection
	// ============================================================

	pub struct CTFontCollection {}

	pub fn CTFontCollection.create_from_available_fonts() !&CTFontCollection {
		ptr := C.CTFontCollectionCreateFromAvailableFonts(unsafe { nil })
		return require_cf_ref[CTFontCollection](ptr, 'CTFontCollectionCreateFromAvailableFonts')
	}

	pub fn CTFontCollection.create_with_font_descriptors(descs &CFArray) !&CTFontCollection {
		ptr := C.CTFontCollectionCreateWithFontDescriptors(voidptr(descs), unsafe { nil })
		return require_cf_ref[CTFontCollection](ptr, 'CTFontCollectionCreateWithFontDescriptors')
	}

	pub fn (fc &CTFontCollection) release() {
		cf_release(voidptr(fc))
	}

	pub fn (fc &CTFontCollection) create_matching_font_descriptors() !&CFArray {
		ptr := C.CTFontCollectionCreateMatchingFontDescriptors(voidptr(fc))
		if !isnil(ptr) {
			return cast_cf_ref[CFArray](ptr)
		}
		return CFArray.create([])!
	}

	// ============================================================
	// text.font_manager
	// ============================================================

	pub fn create_font_descriptors_from_url(url &CFURL) ?&CFArray {
		ptr := C.CTFontManagerCreateFontDescriptorsFromURL(voidptr(url))
		if isnil(ptr) {
			return none
		}
		return cast_cf_ref[CFArray](ptr)
	}

	pub fn create_font_descriptors_from_data(data &CFData) ?&CFArray {
		ptr := C.CTFontManagerCreateFontDescriptorsFromData(voidptr(data))
		if isnil(ptr) {
			return none
		}
		return cast_cf_ref[CFArray](ptr)
	}

	pub fn create_font_descriptor_from_data(data &CFData) ?&CTFontDescriptor {
		ptr := C.CTFontManagerCreateFontDescriptorFromData(voidptr(data))
		if isnil(ptr) {
			return none
		}
		return cast_cf_ref[CTFontDescriptor](ptr)
	}

	// ============================================================
	// dispatch
	// ============================================================

	pub type DispatchQueue = voidptr

	pub fn dispatch_get_main_queue() DispatchQueue {
		return C.vt_dispatch_get_main_queue()
	}

	pub struct DispatchData {}

	pub fn DispatchData.create(data []u8, queue DispatchQueue) !&DispatchData {
		mut data_ptr := voidptr(unsafe { nil })
		if data.len > 0 {
			data_ptr = voidptr(data.data)
		}
		ptr := C.vt_dispatch_data_create(data_ptr, data.len, queue)
		return require_cf_ref[DispatchData](ptr, 'dispatch_data_create')
	}

	pub fn (d &DispatchData) release() {
		C.vt_dispatch_release(voidptr(d))
	}

	// ============================================================
	// animation
	// ============================================================

	pub fn k_ca_gravity_top_left() voidptr {
		return C.vt_kca_gravity_top_left()
	}

	pub fn k_ca_gravity_bottom_left() voidptr {
		return C.vt_kca_gravity_bottom_left()
	}

	pub fn k_ca_gravity_center() voidptr {
		return C.vt_kca_gravity_center()
	}

	// ============================================================
	// video.display_link
	// ============================================================



	// ============================================================
	// os.log
	// ============================================================

	pub enum LogType as u8 {
		default_ = 0x00
		debug    = 0x02
		info     = 0x01
		err      = 0x10
		fault    = 0x11
	}

	pub struct OSLog {}

	pub fn OSLog.create(subsystem string, category string) &OSLog {
		ptr := C.vt_os_log_create(subsystem.str, category.str)
		if isnil(ptr) {
			return unsafe { &OSLog(nil) }
		}
		return cast_cf_ref[OSLog](ptr)
	}

	pub fn (l &OSLog) release() {
		C.vt_os_release(voidptr(l))
	}

	pub fn (l &OSLog) type_enabled(typ LogType) bool {
		return C.vt_os_log_type_enabled(voidptr(l), u8(typ))
	}

	pub fn (l &OSLog) log(typ LogType, msg string) {
		C.vt_os_log_with_type_str(voidptr(l), u8(typ), msg.str)
	}

	// ============================================================
	// os.signpost
	// ============================================================

	pub fn signpost_init() {
		// Zig-specific dso handle workaround is not needed in this V translation.
	}

	pub enum SignpostType as u8 {
		event          = 0
		interval_begin = 1
		interval_end   = 2
	}

	pub const signpost_type_mask = u8(0x03)

	pub fn signpost_enabled(log &OSLog) bool {
		return C.vt_os_signpost_enabled(voidptr(log))
	}

	pub type SignpostId = u64

	pub const signpost_id_null = u64(0)
	pub const signpost_id_invalid = u64(0xFFFFFFFFFFFFFFFF)
	pub const signpost_id_exclusive = u64(0xEEEEB0B5B2B2EEEE)

	pub fn signpost_id_generate(log &OSLog) SignpostId {
		return C.vt_os_signpost_id_generate(voidptr(log))
	}

	pub fn signpost_id_for_pointer(log &OSLog, ptr voidptr) SignpostId {
		return C.vt_os_signpost_id_for_pointer(voidptr(log), ptr)
	}

	pub fn signpost_emit_event(log &OSLog, id SignpostId, name string) {
		C.vt_os_signpost_event_emit(voidptr(log), id, name.str)
	}

	pub fn signpost_interval_begin(log &OSLog, id SignpostId, name string) {
		C.vt_os_signpost_interval_begin(voidptr(log), id, name.str)
	}

	pub fn signpost_interval_end(log &OSLog, id SignpostId, name string) {
		C.vt_os_signpost_interval_end(voidptr(log), id, name.str)
	}

	pub const signpost_category_points_of_interest = 'PointsOfInterest'
	pub const signpost_category_dynamic_tracing = 'DynamicTracing'
	pub const signpost_category_dynamic_stack_tracing = 'DynamicStackTracing'

	// ============================================================
	// iosurface
	// ============================================================

	// CoreVideo's kCVPixelFormatType_* FourCC codes, written out so that V code does not need
	// CoreVideo's headers (FastC's TinyCC units cannot parse CoreGraphics).
	pub enum PixelFormat as int {
		p1_monochrome                                = 0x00000001 // kCVPixelFormatType_1Monochrome
		p2_indexed                                   = 0x00000002 // kCVPixelFormatType_2Indexed
		p4_indexed                                   = 0x00000004 // kCVPixelFormatType_4Indexed
		p8_indexed                                   = 0x00000008 // kCVPixelFormatType_8Indexed
		p1_indexed_gray_white_is_zero                = 0x00000021 // kCVPixelFormatType_1IndexedGray_WhiteIsZero
		p2_indexed_gray_white_is_zero                = 0x00000022 // kCVPixelFormatType_2IndexedGray_WhiteIsZero
		p4_indexed_gray_white_is_zero                = 0x00000024 // kCVPixelFormatType_4IndexedGray_WhiteIsZero
		p8_indexed_gray_white_is_zero                = 0x00000028 // kCVPixelFormatType_8IndexedGray_WhiteIsZero
		p16_be_555                                   = 0x00000010 // kCVPixelFormatType_16BE555
		p16_le_555                                   = 0x4c353535 // kCVPixelFormatType_16LE555
		p16_le_5551                                  = 0x35353531 // kCVPixelFormatType_16LE5551
		p16_be_565                                   = 0x42353635 // kCVPixelFormatType_16BE565
		p16_le_565                                   = 0x4c353635 // kCVPixelFormatType_16LE565
		p24_rgb                                      = 0x00000018 // kCVPixelFormatType_24RGB
		p24_bgr                                      = 0x32344247 // kCVPixelFormatType_24BGR
		p32_argb                                     = 0x00000020 // kCVPixelFormatType_32ARGB
		p32_bgra                                     = 0x42475241 // kCVPixelFormatType_32BGRA
		p32_abgr                                     = 0x41424752 // kCVPixelFormatType_32ABGR
		p32_rgba                                     = 0x52474241 // kCVPixelFormatType_32RGBA
		p64_argb                                     = 0x62363461 // kCVPixelFormatType_64ARGB
		p64_rgbale                                   = 0x6c363472 // kCVPixelFormatType_64RGBALE
		p48_rgb                                      = 0x62343872 // kCVPixelFormatType_48RGB
		p32_alpha_gray                               = 0x62333261 // kCVPixelFormatType_32AlphaGray
		p16_gray                                     = 0x62313667 // kCVPixelFormatType_16Gray
		p30_rgb                                      = 0x5231306b // kCVPixelFormatType_30RGB
		p30_rgb_r_210                                = 0x72323130 // kCVPixelFormatType_30RGB_r210
		p422_yp_cb_cr_8                              = 0x32767579 // kCVPixelFormatType_422YpCbCr8
		p4444_yp_cb_cr_a_8                           = 0x76343038 // kCVPixelFormatType_4444YpCbCrA8
		p4444_yp_cb_cr_a_8_r                         = 0x72343038 // kCVPixelFormatType_4444YpCbCrA8R
		p4444_ayp_cb_cr_8                            = 0x79343038 // kCVPixelFormatType_4444AYpCbCr8
		p4444_ayp_cb_cr_16                           = 0x79343136 // kCVPixelFormatType_4444AYpCbCr16
		p4444_ayp_cb_cr_float                        = 0x7234666c // kCVPixelFormatType_4444AYpCbCrFloat
		p444_yp_cb_cr_8                              = 0x76333038 // kCVPixelFormatType_444YpCbCr8
		p422_yp_cb_cr_16                             = 0x76323136 // kCVPixelFormatType_422YpCbCr16
		p422_yp_cb_cr_10                             = 0x76323130 // kCVPixelFormatType_422YpCbCr10
		p444_yp_cb_cr_10                             = 0x76343130 // kCVPixelFormatType_444YpCbCr10
		p420_yp_cb_cr_8_planar                       = 0x79343230 // kCVPixelFormatType_420YpCbCr8Planar
		p420_yp_cb_cr_8_planar_full_range            = 0x66343230 // kCVPixelFormatType_420YpCbCr8PlanarFullRange
		p422_yp_cb_cr_4_a_8_bi_planar                = 0x61327679 // kCVPixelFormatType_422YpCbCr_4A_8BiPlanar
		p420_yp_cb_cr_8_bi_planar_video_range        = 0x34323076 // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
		p420_yp_cb_cr_8_bi_planar_full_range         = 0x34323066 // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
		p422_yp_cb_cr_8_bi_planar_video_range        = 0x34323276 // kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange
		p422_yp_cb_cr_8_bi_planar_full_range         = 0x34323266 // kCVPixelFormatType_422YpCbCr8BiPlanarFullRange
		p444_yp_cb_cr_8_bi_planar_video_range        = 0x34343476 // kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange
		p444_yp_cb_cr_8_bi_planar_full_range         = 0x34343466 // kCVPixelFormatType_444YpCbCr8BiPlanarFullRange
		p422_yp_cb_cr_8_yuvs                         = 0x79757673 // kCVPixelFormatType_422YpCbCr8_yuvs
		p422_yp_cb_cr_8_full_range                   = 0x79757666 // kCVPixelFormatType_422YpCbCr8FullRange
		one_component_8                              = 0x4c303038 // kCVPixelFormatType_OneComponent8
		two_component_8                              = 0x32433038 // kCVPixelFormatType_TwoComponent8
		p30_rgblepacked_wide_gamut                   = 0x77333072 // kCVPixelFormatType_30RGBLEPackedWideGamut
		argb_2101010_lepacked                        = 0x6c313072 // kCVPixelFormatType_ARGB2101010LEPacked
		p40_argblewide_gamut                         = 0x77343061 // kCVPixelFormatType_40ARGBLEWideGamut
		p40_argblewide_gamut_premultiplied           = 0x7734306d // kCVPixelFormatType_40ARGBLEWideGamutPremultiplied
		one_component_10                             = 0x4c303130 // kCVPixelFormatType_OneComponent10
		one_component_12                             = 0x4c303132 // kCVPixelFormatType_OneComponent12
		one_component_16                             = 0x4c303136 // kCVPixelFormatType_OneComponent16
		two_component_16                             = 0x32433136 // kCVPixelFormatType_TwoComponent16
		one_component_16_half                        = 0x4c303068 // kCVPixelFormatType_OneComponent16Half
		one_component_32_float                       = 0x4c303066 // kCVPixelFormatType_OneComponent32Float
		two_component_16_half                        = 0x32433068 // kCVPixelFormatType_TwoComponent16Half
		two_component_32_float                       = 0x32433066 // kCVPixelFormatType_TwoComponent32Float
		p64_rgbahalf                                 = 0x52476841 // kCVPixelFormatType_64RGBAHalf
		p128_rgbafloat                               = 0x52476641 // kCVPixelFormatType_128RGBAFloat
		p14_bayer_grbg                               = 0x67726234 // kCVPixelFormatType_14Bayer_GRBG
		p14_bayer_rggb                               = 0x72676734 // kCVPixelFormatType_14Bayer_RGGB
		p14_bayer_bggr                               = 0x62676734 // kCVPixelFormatType_14Bayer_BGGR
		p14_bayer_gbrg                               = 0x67627234 // kCVPixelFormatType_14Bayer_GBRG
		disparity_float_16                           = 0x68646973 // kCVPixelFormatType_DisparityFloat16
		disparity_float_32                           = 0x66646973 // kCVPixelFormatType_DisparityFloat32
		depth_float_16                               = 0x68646570 // kCVPixelFormatType_DepthFloat16
		depth_float_32                               = 0x66646570 // kCVPixelFormatType_DepthFloat32
		p420_yp_cb_cr_10_bi_planar_video_range       = 0x78343230 // kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
		p422_yp_cb_cr_10_bi_planar_video_range       = 0x78343232 // kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
		p444_yp_cb_cr_10_bi_planar_video_range       = 0x78343434 // kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange
		p420_yp_cb_cr_10_bi_planar_full_range        = 0x78663230 // kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
		p422_yp_cb_cr_10_bi_planar_full_range        = 0x78663232 // kCVPixelFormatType_422YpCbCr10BiPlanarFullRange
		p444_yp_cb_cr_10_bi_planar_full_range        = 0x78663434 // kCVPixelFormatType_444YpCbCr10BiPlanarFullRange
		p420_yp_cb_cr_8_video_range_8_a_tri_planar   = 0x76306138 // kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar
		p16_versatile_bayer                          = 0x62703136 // kCVPixelFormatType_16VersatileBayer
		p64_rgba_downscaled_pro_res_raw              = 0x62703634 // kCVPixelFormatType_64RGBA_DownscaledProResRAW
		p422_yp_cb_cr_16_bi_planar_video_range       = 0x73763232 // kCVPixelFormatType_422YpCbCr16BiPlanarVideoRange
		p444_yp_cb_cr_16_bi_planar_video_range       = 0x73763434 // kCVPixelFormatType_444YpCbCr16BiPlanarVideoRange
		p444_yp_cb_cr_16_video_range_16_a_tri_planar = 0x73346173 // kCVPixelFormatType_444YpCbCr16VideoRange_16A_TriPlanar
		_
	}

	pub struct IOSurfaceProperties {
	pub:
		width             int
		height            int
		pixel_format      PixelFormat = .p32_bgra
		bytes_per_element int         = 4
		colorspace        ?&CGColorSpace
	}

	pub struct IOSurface {}

	pub fn IOSurface.init(properties IOSurfaceProperties) !&IOSurface {
		mut colorspace_ptr := voidptr(unsafe { nil })
		if colorspace := properties.colorspace {
			colorspace_ptr = voidptr(colorspace)
		}
		ptr := C.vt_iosurface_create(properties.width, properties.height, u32(properties.pixel_format), properties.bytes_per_element, colorspace_ptr)
		return require_cf_ref[IOSurface](ptr, 'IOSurfaceCreate')
	}

	pub fn (s &IOSurface) deinit() {
		C.vt_iosurface_deinit(voidptr(s))
	}

	pub fn (s &IOSurface) retain() {
		C.vt_iosurface_retain(voidptr(s))
	}

	pub fn (s &IOSurface) release() {
		C.vt_iosurface_release(voidptr(s))
	}

	pub fn (s &IOSurface) set_color_space(colorspace &CGColorSpace) {
		C.vt_iosurface_set_color_space(voidptr(s), voidptr(colorspace))
	}

	pub fn (s &IOSurface) lock() {
		C.vt_iosurface_lock(voidptr(s))
	}

	pub fn (s &IOSurface) unlock() {
		C.vt_iosurface_unlock(voidptr(s))
	}

	pub fn (s &IOSurface) get_alloc_size() uint {
		return C.vt_iosurface_get_alloc_size(voidptr(s))
	}

	pub fn (s &IOSurface) get_width() uint {
		return C.vt_iosurface_get_width(voidptr(s))
	}

	pub fn (s &IOSurface) get_height() uint {
		return C.vt_iosurface_get_height(voidptr(s))
	}

	pub fn (s &IOSurface) get_bytes_per_element() uint {
		return C.vt_iosurface_get_bytes_per_element(voidptr(s))
	}

	pub fn (s &IOSurface) get_bytes_per_row() uint {
		return C.vt_iosurface_get_bytes_per_row(voidptr(s))
	}

	pub fn (s &IOSurface) get_base_address() ?&u8 {
		ptr := C.vt_iosurface_get_base_address(voidptr(s))
		if isnil(ptr) {
			return none
		}
		return unsafe { &u8(ptr) }
	}

	pub fn (s &IOSurface) get_element_width() uint {
		return C.vt_iosurface_get_element_width(voidptr(s))
	}

	pub fn (s &IOSurface) get_element_height() uint {
		return C.vt_iosurface_get_element_height(voidptr(s))
	}

	pub fn (s &IOSurface) get_pixel_format() PixelFormat {
		return unsafe { PixelFormat(C.vt_iosurface_get_pixel_format(voidptr(s))) }
	}
}
