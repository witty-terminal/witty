module oniguruma

// Ghostty uses the same system dependency when system integration is enabled.
$if managed_native ? {
	$if !system_oniguruma ? {
		#flag -I@VMODROOT/.witty-build/deps/oniguruma/src
	}
} $else {
	#flag darwin -I/opt/homebrew/include
	#flag darwin -L/opt/homebrew/lib
	#flag linux -I/usr/include
	#flag -lonig
}
$if no_oniguruma ? {
	#flag -DWITTY_NO_ONIGURUMA
}

#include "bridge.h"

fn C.witty_onig_initialize(encodings &voidptr, count uint) int

fn C.onig_end() int

fn C.witty_onig_new(out &voidptr, pattern &u8, pattern_len uint, options u32, encoding voidptr, syntax voidptr, error_par &voidptr, error_par_end &voidptr) int

fn C.witty_onig_encoding_ascii() voidptr
fn C.witty_onig_encoding_iso_8859_1() voidptr
fn C.witty_onig_encoding_iso_8859_2() voidptr
fn C.witty_onig_encoding_iso_8859_3() voidptr
fn C.witty_onig_encoding_iso_8859_4() voidptr
fn C.witty_onig_encoding_iso_8859_5() voidptr
fn C.witty_onig_encoding_iso_8859_6() voidptr
fn C.witty_onig_encoding_iso_8859_7() voidptr
fn C.witty_onig_encoding_iso_8859_8() voidptr
fn C.witty_onig_encoding_iso_8859_9() voidptr
fn C.witty_onig_encoding_iso_8859_10() voidptr
fn C.witty_onig_encoding_iso_8859_11() voidptr
fn C.witty_onig_encoding_iso_8859_13() voidptr
fn C.witty_onig_encoding_iso_8859_14() voidptr
fn C.witty_onig_encoding_iso_8859_15() voidptr
fn C.witty_onig_encoding_iso_8859_16() voidptr
fn C.witty_onig_encoding_utf8() voidptr
fn C.witty_onig_encoding_utf16_be() voidptr
fn C.witty_onig_encoding_utf16_le() voidptr
fn C.witty_onig_encoding_utf32_be() voidptr
fn C.witty_onig_encoding_utf32_le() voidptr
fn C.witty_onig_encoding_euc_jp() voidptr
fn C.witty_onig_encoding_euc_tw() voidptr
fn C.witty_onig_encoding_euc_kr() voidptr
fn C.witty_onig_encoding_euc_cn() voidptr
fn C.witty_onig_encoding_sjis() voidptr
fn C.witty_onig_encoding_koi8() voidptr
fn C.witty_onig_encoding_koi8_r() voidptr
fn C.witty_onig_encoding_cp1251() voidptr
fn C.witty_onig_encoding_big5() voidptr
fn C.witty_onig_encoding_gb18030() voidptr

fn C.witty_onig_syntax_default_() voidptr
fn C.witty_onig_syntax_asis() voidptr
fn C.witty_onig_syntax_posix_basic() voidptr
fn C.witty_onig_syntax_posix_extended() voidptr
fn C.witty_onig_syntax_emacs() voidptr
fn C.witty_onig_syntax_grep() voidptr
fn C.witty_onig_syntax_gnu_regex() voidptr
fn C.witty_onig_syntax_java() voidptr
fn C.witty_onig_syntax_perl() voidptr
fn C.witty_onig_syntax_perl_ng() voidptr
fn C.witty_onig_syntax_ruby() voidptr
fn C.witty_onig_syntax_oniguruma() voidptr

fn C.onig_free(regex voidptr)

fn C.onig_region_free(region voidptr, free_self int)

fn C.witty_onig_error_string(error_message &u8, code int) int

fn C.witty_onig_search(regex voidptr, string &u8, string_len uint, start uint, end uint, region voidptr, options u32) int

pub const max_error_len = 90
pub const mismatch_error = 'oniguruma mismatch'

// Options is Oniguruma's canonical packed OnigOptionType word.
pub struct Options {
mut:
	value u32
}

// Option is the source-shaped name; Options remains for existing V callers.
pub type Option = Options

pub fn (o Options) int() u32 {
	return o.value
}

pub fn Options.from_int(value u32) Options {
	return Options{ value: value }
}

fn (o Options) bit(index u32) bool {
	return o.value & (u32(1) << index) != 0
}

fn (mut o Options) set_bit(index u32, enabled bool) {
	mask := u32(1) << index
	if enabled {
		o.value |= mask
	} else {
		o.value &= ~mask
	}
}

pub fn (o Options) ignorecase() bool {
	return o.bit(0)
}

pub fn (mut o Options) set_ignorecase(value bool) {
	o.set_bit(0, value)
}

pub fn (o Options) extend() bool {
	return o.bit(1)
}

pub fn (mut o Options) set_extend(value bool) {
	o.set_bit(1, value)
}

pub fn (o Options) multiline() bool {
	return o.bit(2)
}

pub fn (mut o Options) set_multiline(value bool) {
	o.set_bit(2, value)
}

pub fn (o Options) singleline() bool {
	return o.bit(3)
}

pub fn (mut o Options) set_singleline(value bool) {
	o.set_bit(3, value)
}

pub fn (o Options) find_longest() bool {
	return o.bit(4)
}

pub fn (mut o Options) set_find_longest(value bool) {
	o.set_bit(4, value)
}

pub fn (o Options) find_not_empty() bool {
	return o.bit(5)
}

pub fn (mut o Options) set_find_not_empty(value bool) {
	o.set_bit(5, value)
}

pub fn (o Options) negate_singleline() bool {
	return o.bit(6)
}

pub fn (mut o Options) set_negate_singleline(value bool) {
	o.set_bit(6, value)
}

pub fn (o Options) dont_capture_group() bool {
	return o.bit(7)
}

pub fn (mut o Options) set_dont_capture_group(value bool) {
	o.set_bit(7, value)
}

pub fn (o Options) capture_group() bool {
	return o.bit(8)
}

pub fn (mut o Options) set_capture_group(value bool) {
	o.set_bit(8, value)
}

pub fn (o Options) notbol() bool {
	return o.bit(9)
}

pub fn (mut o Options) set_notbol(value bool) {
	o.set_bit(9, value)
}

pub fn (o Options) noteol() bool {
	return o.bit(10)
}

pub fn (mut o Options) set_noteol(value bool) {
	o.set_bit(10, value)
}

pub fn (o Options) posix_region() bool {
	return o.bit(11)
}

pub fn (mut o Options) set_posix_region(value bool) {
	o.set_bit(11, value)
}

pub fn (o Options) check_validity_of_string() bool {
	return o.bit(12)
}

pub fn (mut o Options) set_check_validity_of_string(value bool) {
	o.set_bit(12, value)
}

pub fn (o Options) ignorecase_is_ascii() bool {
	return o.bit(13)
}

pub fn (mut o Options) set_ignorecase_is_ascii(value bool) {
	o.set_bit(13, value)
}

pub fn (o Options) word_is_ascii() bool {
	return o.bit(14)
}

pub fn (mut o Options) set_word_is_ascii(value bool) {
	o.set_bit(14, value)
}

pub fn (o Options) digit_is_ascii() bool {
	return o.bit(15)
}

pub fn (mut o Options) set_digit_is_ascii(value bool) {
	o.set_bit(15, value)
}

pub fn (o Options) space_is_ascii() bool {
	return o.bit(16)
}

pub fn (mut o Options) set_space_is_ascii(value bool) {
	o.set_bit(16, value)
}

pub fn (o Options) posix_is_ascii() bool {
	return o.bit(17)
}

pub fn (mut o Options) set_posix_is_ascii(value bool) {
	o.set_bit(17, value)
}

pub fn (o Options) text_segment_extended_grapheme_cluster() bool {
	return o.bit(18)
}

pub fn (mut o Options) set_text_segment_extended_grapheme_cluster(value bool) {
	o.set_bit(18, value)
}

pub fn (o Options) text_segment_word() bool {
	return o.bit(19)
}

pub fn (mut o Options) set_text_segment_word(value bool) {
	o.set_bit(19, value)
}

pub fn (o Options) not_begin_string() bool {
	return o.bit(20)
}

pub fn (mut o Options) set_not_begin_string(value bool) {
	o.set_bit(20, value)
}

pub fn (o Options) not_end_string() bool {
	return o.bit(21)
}

pub fn (mut o Options) set_not_end_string(value bool) {
	o.set_bit(21, value)
}

pub fn (o Options) not_begin_position() bool {
	return o.bit(22)
}

pub fn (mut o Options) set_not_begin_position(value bool) {
	o.set_bit(22, value)
}

pub fn (o Options) callback_each_match() bool {
	return o.bit(23)
}

pub fn (mut o Options) set_callback_each_match(value bool) {
	o.set_bit(23, value)
}

pub fn (o Options) match_whole_string() bool {
	return o.bit(24)
}

pub fn (mut o Options) set_match_whole_string(value bool) {
	o.set_bit(24, value)
}

// Encoding and Syntax are opaque pointers in the source wrapper. The V values
// retain exactly one native pointer and expose associated constructors because
// V cannot declare a compile-time constant initialized from a C symbol.
pub struct Encoding {
	handle voidptr
}

pub fn Encoding.ascii() Encoding { return Encoding{ handle: C.witty_onig_encoding_ascii() } }
pub fn Encoding.iso_8859_1() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_1() } }
pub fn Encoding.iso_8859_2() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_2() } }
pub fn Encoding.iso_8859_3() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_3() } }
pub fn Encoding.iso_8859_4() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_4() } }
pub fn Encoding.iso_8859_5() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_5() } }
pub fn Encoding.iso_8859_6() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_6() } }
pub fn Encoding.iso_8859_7() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_7() } }
pub fn Encoding.iso_8859_8() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_8() } }
pub fn Encoding.iso_8859_9() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_9() } }
pub fn Encoding.iso_8859_10() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_10() } }
pub fn Encoding.iso_8859_11() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_11() } }
pub fn Encoding.iso_8859_13() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_13() } }
pub fn Encoding.iso_8859_14() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_14() } }
pub fn Encoding.iso_8859_15() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_15() } }
pub fn Encoding.iso_8859_16() Encoding { return Encoding{ handle: C.witty_onig_encoding_iso_8859_16() } }
pub fn Encoding.utf8() Encoding { return Encoding{ handle: C.witty_onig_encoding_utf8() } }
pub fn Encoding.utf16_be() Encoding { return Encoding{ handle: C.witty_onig_encoding_utf16_be() } }
pub fn Encoding.utf16_le() Encoding { return Encoding{ handle: C.witty_onig_encoding_utf16_le() } }
pub fn Encoding.utf32_be() Encoding { return Encoding{ handle: C.witty_onig_encoding_utf32_be() } }
pub fn Encoding.utf32_le() Encoding { return Encoding{ handle: C.witty_onig_encoding_utf32_le() } }
pub fn Encoding.euc_jp() Encoding { return Encoding{ handle: C.witty_onig_encoding_euc_jp() } }
pub fn Encoding.euc_tw() Encoding { return Encoding{ handle: C.witty_onig_encoding_euc_tw() } }
pub fn Encoding.euc_kr() Encoding { return Encoding{ handle: C.witty_onig_encoding_euc_kr() } }
pub fn Encoding.euc_cn() Encoding { return Encoding{ handle: C.witty_onig_encoding_euc_cn() } }
pub fn Encoding.sjis() Encoding { return Encoding{ handle: C.witty_onig_encoding_sjis() } }
pub fn Encoding.koi8() Encoding { return Encoding{ handle: C.witty_onig_encoding_koi8() } }
pub fn Encoding.koi8_r() Encoding { return Encoding{ handle: C.witty_onig_encoding_koi8_r() } }
pub fn Encoding.cp1251() Encoding { return Encoding{ handle: C.witty_onig_encoding_cp1251() } }
pub fn Encoding.big5() Encoding { return Encoding{ handle: C.witty_onig_encoding_big5() } }
pub fn Encoding.gb18030() Encoding { return Encoding{ handle: C.witty_onig_encoding_gb18030() } }

pub struct Syntax {
	handle voidptr
}

pub fn Syntax.default_() Syntax { return Syntax{ handle: C.witty_onig_syntax_default_() } }
pub fn Syntax.asis() Syntax { return Syntax{ handle: C.witty_onig_syntax_asis() } }
pub fn Syntax.posix_basic() Syntax { return Syntax{ handle: C.witty_onig_syntax_posix_basic() } }
pub fn Syntax.posix_extended() Syntax { return Syntax{ handle: C.witty_onig_syntax_posix_extended() } }
pub fn Syntax.emacs() Syntax { return Syntax{ handle: C.witty_onig_syntax_emacs() } }
pub fn Syntax.grep() Syntax { return Syntax{ handle: C.witty_onig_syntax_grep() } }
pub fn Syntax.gnu_regex() Syntax { return Syntax{ handle: C.witty_onig_syntax_gnu_regex() } }
pub fn Syntax.java() Syntax { return Syntax{ handle: C.witty_onig_syntax_java() } }
pub fn Syntax.perl() Syntax { return Syntax{ handle: C.witty_onig_syntax_perl() } }
pub fn Syntax.perl_ng() Syntax { return Syntax{ handle: C.witty_onig_syntax_perl_ng() } }
pub fn Syntax.ruby() Syntax { return Syntax{ handle: C.witty_onig_syntax_ruby() } }
pub fn Syntax.oniguruma() Syntax { return Syntax{ handle: C.witty_onig_syntax_oniguruma() } }

pub struct ErrorInfo {
pub mut:
	encoding Encoding
	par      &u8 = unsafe { nil }
	par_end  &u8 = unsafe { nil }
}

// init initializes Oniguruma for the encodings that the process will use.
pub fn init(encodings []Encoding) ! {
	mut values := []voidptr{cap: encodings.len}
	for encoding in encodings {
		values << encoding.handle
	}
	result := if values.len == 0 {
		C.witty_onig_initialize(unsafe { nil }, 0)
	} else {
		unsafe { C.witty_onig_initialize(&values[0], uint(values.len)) }
	}
	_ = convert_error(result)!
}

pub fn deinit() {
	_ = C.onig_end()
}

pub fn error_string(mut buffer []u8, code int) ![]u8 {
	length := unsafe { C.witty_onig_error_string(&u8(buffer.data), code) }
	if length <= 0 {
		return buffer[..0]
	}
	return buffer[..length]
}

pub struct Regex {
mut:
	value voidptr
}

pub fn Regex.init(pattern string, options Options, encoding Encoding, syntax Syntax, error_info ?&ErrorInfo) !Regex {
	mut value := voidptr(unsafe { nil })
	mut error_par := voidptr(unsafe { nil })
	mut error_par_end := voidptr(unsafe { nil })
	result := unsafe {
		C.witty_onig_new(&value, pattern.str, uint(pattern.len), options.int(), encoding.handle,
			syntax.handle, &error_par, &error_par_end)
	}
	if result < 0 {
		if mut info := error_info {
			info.encoding = encoding
			unsafe {
				info.par = &u8(error_par)
				info.par_end = &u8(error_par_end)
			}
		}
		_ = convert_error(result)!
	}
	return Regex{
		value: value
	}
}

pub fn (mut r Regex) deinit() {
	C.onig_free(r.value)
}

pub fn (r &Regex) search(str string, options Options) !Region {
	mut region := Region{}
	r.search_advanced(str, 0, uint(str.len), mut region, options) or {
		region.deinit()
		return err
	}
	return region
}

pub fn (r &Regex) search_advanced(str string, start uint, end uint, mut region Region, options Options) !uint {
	result := C.witty_onig_search(r.value, str.str, uint(str.len), start, end, voidptr(&region),
		options.int())
	return uint(convert_error(result)!)
}

pub struct Region {
mut:
	// OnigRegion stores C int counts and offsets, even when V int is 64-bit.
	allocated    i32
	num_regs     i32
	beg          &i32 = unsafe { nil }
	end          &i32 = unsafe { nil }
	history_root voidptr
}

pub fn (mut r Region) deinit() {
	C.onig_region_free(voidptr(&r), 0)
}

pub fn (r &Region) count() uint {
	return uint(r.num_regs)
}

pub fn (r &Region) starts() []i32 {
	if r.num_regs == 0 {
		return []
	}
	mut result := []i32{}
	unsafe {
		result.data = voidptr(r.beg)
		result.len = r.num_regs
		result.cap = r.num_regs
		result.flags = .nogrow | .noshrink | .nofree
	}
	return result
}

pub fn (r &Region) ends() []i32 {
	if r.num_regs == 0 {
		return []
	}
	mut result := []i32{}
	unsafe {
		result.data = voidptr(r.end)
		result.len = r.num_regs
		result.cap = r.num_regs
		result.flags = .nogrow | .noshrink | .nofree
	}
	return result
}

pub fn (r &Region) iterator() RegionIterator {
	return RegionIterator{
		region: unsafe { r }
	}
}

pub struct RegionIterator {
	region &Region
mut:
	index int
}

pub fn (mut it RegionIterator) next() ?[2]uint {
	if it.index >= int(it.region.count()) {
		return none
	}
	start := unsafe { it.region.beg[it.index] }
	end := unsafe { it.region.end[it.index] }
	if start < 0 || end < 0 {
		panic('negative Oniguruma capture boundary')
	}
	result := [uint(start), uint(end)]!
	it.index++
	return result
}
