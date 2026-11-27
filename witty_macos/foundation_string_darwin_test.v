module witty_macos

fn test_foundation_string_bridge_preserves_complete_utf8_byte_slices() {
	// Swift String and NSString both preserve embedded NUL, including UTF-8
	// following it. A C-string bridge loses that part of the source value.
	data := [u8(0x61), 0, 0xcf, 0x80, 0xf0, 0x9f, 0x91, 0xbb]
	value := data.bytestr()
	native := nsstring(value)
	assert !is_nil(native)
	assert msg_u64(native, 'length') == 5
	assert objc_utf8_string(native) == value
	assert objc_utf8_string(nsstring('')) == ''
	assert is_nil(nsstring([u8(0xff)].bytestr()))
	assert is_nil(nsstring([u8(0x61), 0, 0xff].bytestr()))
}
