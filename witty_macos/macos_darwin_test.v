module witty_macos

fn test_foundation_enum_contracts_match_source() {
	assert sizeof(ComparisonResult) == sizeof(int)
	assert int(ComparisonResult.less) == -1
	assert int(ComparisonResult.equal) == 0
	assert int(ComparisonResult.greater) == 1

	assert sizeof(Encoding) == sizeof(u32)
	assert u32(Encoding.invalid) == 0xffffffff
	assert u32(Encoding.mac_roman) == 0
	assert u32(Encoding.windows_latin_1) == 0x0500
	assert u32(Encoding.iso_latin_1) == 0x0201
	assert u32(Encoding.nextstep_latin) == 0x0b01
	assert u32(Encoding.ascii) == 0x0600
	assert u32(Encoding.unicode) == 0x0100
	assert u32(Encoding.utf8) == 0x08000100
	assert u32(Encoding.non_lossy_ascii) == 0x0bff
	assert u32(Encoding.utf16_be) == 0x10000100
	assert u32(Encoding.utf16_le) == 0x14000100
	assert u32(Encoding.utf32) == 0x0c000100
	assert u32(Encoding.utf32_be) == 0x18000100
	assert u32(Encoding.utf32_le) == 0x1c000100

	assert sizeof(NumberType) == sizeof(i64)
	assert i64(NumberType.sint8) == 1
	assert i64(NumberType.sint16) == 2
	assert i64(NumberType.sint32) == 3
	assert i64(NumberType.sint64) == 4
	assert i64(NumberType.float32) == 5
	assert i64(NumberType.float64) == 6
	assert i64(NumberType.char_) == 7
	assert i64(NumberType.short_) == 8
	assert i64(NumberType.int_type) == 9
	assert i64(NumberType.long_) == 10
	assert i64(NumberType.long_long) == 11
	assert i64(NumberType.float_) == 12
	assert i64(NumberType.double_) == 13
	assert i64(NumberType.cf_index) == 14
	assert i64(NumberType.ns_integer) == 15
	assert i64(NumberType.cg_float) == 16

	assert sizeof(URLPathStyle) == sizeof(int)
	assert int(URLPathStyle.posix) == 0
	assert int(URLPathStyle.windows) == 2
}

fn test_number_create_and_get_value() {
	value := i32(42)
	number := CFNumber.create(.sint32, &value) or { panic(err) }
	defer {
		number.release()
	}
	mut actual := i32(0)
	assert number.get_value(.sint32, &actual)
	assert actual == value
}

fn test_text_and_graphics_enum_contracts_match_source() {
	assert sizeof(CTParagraphStyleSpecifier) == sizeof(u32)
	assert u32(CTParagraphStyleSpecifier.base_writing_direction) == 13

	assert sizeof(WritingDirection) == sizeof(int)
	assert int(WritingDirection.natural) == -1
	assert int(WritingDirection.ltr) == 0
	assert int(WritingDirection.rtl) == 1
	assert int(WritingDirection.lro) == 2
	assert int(WritingDirection.rlo) == 3

	assert sizeof(StringAttribute) == sizeof(u8)
	assert u8(StringAttribute.font) == 0
	assert u8(StringAttribute.paragraph_style) == 1
	assert u8(StringAttribute.writing_direction) == 2

	assert sizeof(CGImageAlphaInfo) == sizeof(u32)
	assert u32(CGImageAlphaInfo.none) == 0
	assert u32(CGImageAlphaInfo.premultiplied_last) == 1
	assert u32(CGImageAlphaInfo.premultiplied_first) == 2
	assert u32(CGImageAlphaInfo.last) == 3
	assert u32(CGImageAlphaInfo.first) == 4
	assert u32(CGImageAlphaInfo.none_skip_last) == 5
	assert u32(CGImageAlphaInfo.none_skip_first) == 6
	assert u32(CGImageAlphaInfo.only) == 7

	assert sizeof(CGBitmapInfo) == sizeof(u32)
	assert u32(CGBitmapInfo.alpha_mask) == 0x1f
	assert u32(CGBitmapInfo.float_mask) == 0xf00
	assert u32(CGBitmapInfo.float_components) == 0x100
	assert u32(CGBitmapInfo.byte_order_mask) == 0x7000
	assert u32(CGBitmapInfo.byte_order_default) == 0
	assert u32(CGBitmapInfo.byte_order_16_little) == 0x1000
	assert u32(CGBitmapInfo.byte_order_32_little) == 0x2000
	assert u32(CGBitmapInfo.byte_order_16_big) == 0x3000
	assert u32(CGBitmapInfo.byte_order_32_big) == 0x4000

	assert sizeof(CGColorSpaceName) == sizeof(u8)
	assert u8(CGColorSpaceName.display_p3) == 0
	assert u8(CGColorSpaceName.extended_linear_display_p3) == 1
	assert u8(CGColorSpaceName.srgb) == 2
	assert u8(CGColorSpaceName.linear_srgb) == 3
	assert u8(CGColorSpaceName.extended_srgb) == 4
	assert u8(CGColorSpaceName.extended_linear_srgb) == 5
	assert u8(CGColorSpaceName.generic_gray_gamma2_2) == 6
	assert u8(CGColorSpaceName.linear_gray) == 7
	assert u8(CGColorSpaceName.extended_gray) == 8
	assert u8(CGColorSpaceName.extended_linear_gray) == 9

	assert sizeof(CGContextTextDrawingMode) == sizeof(int)
	assert int(CGContextTextDrawingMode.fill) == 0
	assert int(CGContextTextDrawingMode.stroke) == 1
	assert int(CGContextTextDrawingMode.fill_stroke) == 2
	assert int(CGContextTextDrawingMode.invisible) == 3
	assert int(CGContextTextDrawingMode.fill_clip) == 4
	assert int(CGContextTextDrawingMode.stroke_clip) == 5
	assert int(CGContextTextDrawingMode.fill_stroke_clip) == 6
	assert int(CGContextTextDrawingMode.clip) == 7
}

fn test_font_table_tag_and_symbolic_traits() {
	assert u32(CTFontTableTag.init('SVG ')) == 0x53564720
	assert u32(CTFontTableTag.init('sbix')) == 0x73626978
	assert u32(CTFontOrientation.default_) == 0
	assert u32(CTFontOrientation.horizontal) == 1
	assert u32(CTFontOrientation.vertical) == 2

	traits := CTFontSymbolicTraits.from_raw((u32(1) << 0) | (u32(1) << 10) |
		(u32(1) << 13))
	assert traits.italic
	assert !traits.bold
	assert traits.monospace
	assert traits.color_glyphs
	assert !traits.composite
}

fn test_os_and_video_enum_contracts_match_source() {
	assert sizeof(LogType) == sizeof(u8)
	assert u8(LogType.default_) == 0
	assert u8(LogType.debug) == 2
	assert u8(LogType.info) == 1
	assert u8(LogType.err) == 0x10
	assert u8(LogType.fault) == 0x11

	assert sizeof(SignpostType) == sizeof(u8)
	assert u8(SignpostType.event) == 0
	assert u8(SignpostType.interval_begin) == 1
	assert u8(SignpostType.interval_end) == 2

	assert sizeof(PixelFormat) == sizeof(int)
	assert int(PixelFormat.p1_monochrome) == 1
	assert u32(PixelFormat.p32_bgra) == 0x42475241
}
