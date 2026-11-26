module oniguruma

fn test_option_bit_order() {
	assert sizeof(Options) == 4
	mut options := Options{}
	options.set_ignorecase(true)
	options.set_extend(true)
	options.set_multiline(true)
	options.set_singleline(true)
	options.set_find_longest(true)
	options.set_find_not_empty(true)
	options.set_negate_singleline(true)
	options.set_dont_capture_group(true)
	options.set_capture_group(true)
	options.set_notbol(true)
	options.set_noteol(true)
	options.set_posix_region(true)
	options.set_check_validity_of_string(true)
	options.set_ignorecase_is_ascii(true)
	options.set_word_is_ascii(true)
	options.set_digit_is_ascii(true)
	options.set_space_is_ascii(true)
	options.set_posix_is_ascii(true)
	options.set_text_segment_extended_grapheme_cluster(true)
	options.set_text_segment_word(true)
	options.set_not_begin_string(true)
	options.set_not_end_string(true)
	options.set_not_begin_position(true)
	options.set_callback_each_match(true)
	options.set_match_whole_string(true)
	assert options.int() == (u32(1) << 25) - 1
	assert options.ignorecase()
	assert options.extend()
	assert options.multiline()
	assert options.singleline()
	assert options.find_longest()
	assert options.find_not_empty()
	assert options.negate_singleline()
	assert options.dont_capture_group()
	assert options.capture_group()
	assert options.notbol()
	assert options.noteol()
	assert options.posix_region()
	assert options.check_validity_of_string()
	assert options.ignorecase_is_ascii()
	assert options.word_is_ascii()
	assert options.digit_is_ascii()
	assert options.space_is_ascii()
	assert options.posix_is_ascii()
	assert options.text_segment_extended_grapheme_cluster()
	assert options.text_segment_word()
	assert options.not_begin_string()
	assert options.not_end_string()
	assert options.not_begin_position()
	assert options.callback_each_match()
	assert options.match_whole_string()
	options.set_extend(false)
	assert options.int() == ((u32(1) << 25) - 1) & ~u32(2)
	assert !options.extend()
	assert Options.from_int(u32(1) << 24).match_whole_string()
}

fn test_convert_error() {
	assert convert_error(42)! == 42
	mut buffer := []u8{len: max_error_len}
	assert error_string(mut buffer, -1)!.len > 0
	if _ := convert_error(-123456) {
		assert false, 'expected unknown error'
	} else {
		assert is_error(err, .unknown)
	}
}

fn test_ensure_init() {
	ensure_init()!
}

fn test_all_linked_encoding_constants() {
	assert sizeof(Encoding) == sizeof(voidptr)
	init([Encoding.ascii(), Encoding.iso_8859_1(), Encoding.iso_8859_2(), Encoding.iso_8859_3(),
		Encoding.iso_8859_4(), Encoding.iso_8859_5(), Encoding.iso_8859_6(), Encoding.iso_8859_7(),
		Encoding.iso_8859_8(), Encoding.iso_8859_9(), Encoding.iso_8859_10(), Encoding.iso_8859_11(),
		Encoding.iso_8859_13(), Encoding.iso_8859_14(), Encoding.iso_8859_15(), Encoding.iso_8859_16(),
		Encoding.utf8(), Encoding.utf16_be(), Encoding.utf16_le(), Encoding.utf32_be(), Encoding.utf32_le(),
		Encoding.euc_jp(), Encoding.euc_tw(), Encoding.euc_kr(), Encoding.euc_cn(), Encoding.sjis(),
		Encoding.koi8_r(), Encoding.cp1251(), Encoding.big5(), Encoding.gb18030()])!
	deinit()
}

fn test_all_syntax_constants() {
	assert sizeof(Syntax) == sizeof(voidptr)
	init([Encoding.utf8()])!
	defer { deinit() }
	for syntax in [Syntax.default_(), Syntax.asis(), Syntax.posix_basic(), Syntax.posix_extended(),
		Syntax.emacs(), Syntax.grep(), Syntax.gnu_regex(), Syntax.java(), Syntax.perl(), Syntax.perl_ng(),
		Syntax.ruby(), Syntax.oniguruma()] {
		mut regex := Regex.init('foo', Options{}, Encoding.utf8(), syntax, none)!
		regex.deinit()
	}
	assert Syntax.default_() == Syntax.oniguruma()
}

fn test_regex_error_info() {
	init([Encoding.utf8()])!
	defer { deinit() }
	mut info := ErrorInfo{}
	if _ := Regex.init('(', Options{}, Encoding.utf8(), Syntax.default_(), &info) {
		assert false, 'expected invalid regex'
	} else {
		assert error_kind_of(err) != none
		assert info.encoding == Encoding.utf8()
	}
}

fn test_regex_search_and_mismatch() {
	init([Encoding.utf8()])!
	defer { deinit() }
	mut regex := Regex.init('foo', Options{}, Encoding.utf8(), Syntax.default_(), none)!
	defer { regex.deinit() }
	mut region := regex.search('hello foo bar', Options{})!
	defer { region.deinit() }
	assert region.count() == 1
	assert region.starts() == [i32(6)]
	assert region.ends() == [i32(9)]
	assert region.starts().data == voidptr(region.beg)
	assert region.ends().data == voidptr(region.end)
	if _ := regex.search('hello', Options{}) {
		assert false, 'expected mismatch'
	} else {
		assert is_error(err, .mismatch)
	}
}

fn test_region_native_layout_and_borrowed_ranges() {
	assert sizeof(Region) == 8 + 3 * sizeof(voidptr)
	init([Encoding.utf8()])!
	defer { deinit() }
	mut regex := Regex.init('(foo) (bar)', Options{}, Encoding.utf8(), Syntax.default_(), none)!
	defer { regex.deinit() }
	mut region := regex.search('xfoo barz', Options{})!
	defer { region.deinit() }
	assert region.count() == 3
	assert region.starts() == [i32(1), 1, 5]
	assert region.ends() == [i32(8), 4, 8]
	assert region.starts().data == voidptr(region.beg)
	assert region.ends().data == voidptr(region.end)
	mut advanced := Region{}
	defer { advanced.deinit() }
	assert regex.search_advanced('xfoo barz', 1, 8, mut advanced, Options{})! == 1
	assert advanced.starts() == [i32(1), 1, 5]
}
