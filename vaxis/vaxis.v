module vaxis

import encoding.base64
import strings
import term
import term.termios
import unicode

pub struct ColorDefault {}

pub struct ColorIndex {
pub:
	index u8 @[required]
}

pub struct ColorRgb {
pub:
	rgb [3]u8 @[required]
}

// Color is vaxis' default/index/RGB tagged union.
pub type Color = ColorDefault | ColorIndex | ColorRgb

pub fn (a Color) eql(b Color) bool {
	match a {
		ColorDefault {
			return b is ColorDefault
		}
		ColorIndex {
			return match b {
				ColorIndex { a.index == b.index }
				else { false }
			}
		}
		ColorRgb {
			return match b {
				ColorRgb { a.rgb == b.rgb }
				else { false }
			}
		}
	}
}

pub fn color_rgb_from_uint(value u32) Color {
	// Source takes u24; V uses a checked u32 carrier for the missing width.
	if value > 0xffffff {
		panic('integer does not fit in destination type')
	}
	return ColorRgb{
		rgb: [u8(value >> 16), u8(value >> 8), u8(value)]!
	}
}

pub fn color_rgb_from_spec(spec string) !Color {
	rgb := parse_color_spec(spec)!
	return ColorRgb{
		rgb: rgb
	}
}

// Scheme is the terminal's preferred light or dark color scheme.
pub enum Scheme as u8 {
	dark
	light
}

// Style represents text styling attributes.
pub struct Style {
pub mut:
	fg            Color          = ColorDefault{}
	bg            Color          = ColorDefault{}
	ul            Color          = ColorDefault{}
	ul_style      UnderlineStyle = .off
	bold          bool
	dim           bool
	italic        bool
	blink         bool
	reverse       bool
	invisible     bool
	strikethrough bool
}

pub fn (a Style) eql(b Style) bool {
	return a.fg.eql(b.fg) && a.bg.eql(b.bg) && a.ul.eql(b.ul) && a.ul_style == b.ul_style
		&& a.bold == b.bold && a.dim == b.dim && a.italic == b.italic && a.blink == b.blink
		&& a.reverse == b.reverse && a.invisible == b.invisible
		&& a.strikethrough == b.strikethrough
}

pub enum UnderlineStyle as u8 {
	off
	single
	double_
	curly
	dotted
	dashed
}

// Modifiers retains vaxis' packed u8 modifier ABI.
pub struct Modifiers {
mut:
	value u8
}

pub fn Modifiers.init(shift bool, alt bool, ctrl bool, super_ bool, hyper_key bool, meta bool, caps_lock bool, num_lock bool) Modifiers {
	return Modifiers{
		value: u8(shift) | (u8(alt) << 1) | (u8(ctrl) << 2) | (u8(super_) << 3) | (u8(hyper_key) << 4) | (u8(meta) << 5) | (u8(caps_lock) << 6) | (u8(num_lock) << 7)
	}
}

pub fn Modifiers.from_int(value u8) Modifiers {
	return Modifiers{
		value: value
	}
}

pub fn (m Modifiers) int() u8 {
	return m.value
}

pub fn (m Modifiers) eql(other Modifiers) bool {
	return m.value == other.value
}

pub fn (m Modifiers) shift() bool {
	return m.value & 1 != 0
}

pub fn (m Modifiers) alt() bool {
	return m.value & 2 != 0
}

pub fn (m Modifiers) ctrl() bool {
	return m.value & 4 != 0
}

pub fn (m Modifiers) super_() bool {
	return m.value & 8 != 0
}

pub fn (m Modifiers) hyper() bool {
	return m.value & 16 != 0
}

pub fn (m Modifiers) meta() bool {
	return m.value & 32 != 0
}

pub fn (m Modifiers) caps_lock() bool {
	return m.value & 64 != 0
}

pub fn (m Modifiers) num_lock() bool {
	return m.value & 128 != 0
}

pub fn (mut m Modifiers) set_shift(value bool) {
	m.set(1, value)
}

pub fn (mut m Modifiers) set_alt(value bool) {
	m.set(2, value)
}

pub fn (mut m Modifiers) set_ctrl(value bool) {
	m.set(4, value)
}

pub fn (mut m Modifiers) set_super(value bool) {
	m.set(8, value)
}

pub fn (mut m Modifiers) set_hyper(value bool) {
	m.set(16, value)
}

pub fn (mut m Modifiers) set_meta(value bool) {
	m.set(32, value)
}

pub fn (mut m Modifiers) set_caps_lock(value bool) {
	m.set(64, value)
}

pub fn (mut m Modifiers) set_num_lock(value bool) {
	m.set(128, value)
}

fn (mut m Modifiers) set(mask u8, value bool) {
	if value {
		m.value |= mask
	} else {
		m.value &= ~mask
	}
}

// KittyFlags retains vaxis' packed u5 flag ABI in the low five bits.
pub struct KittyFlags {
	value u8 = 0b11101
}

pub fn KittyFlags.init(disambiguate bool, report_events bool, report_alternate_keys bool, report_all_as_ctl_seqs bool, report_text bool) KittyFlags {
	return KittyFlags{
		value: (u8(disambiguate) | (u8(report_events) << 1) | (u8(report_alternate_keys) << 2) | (u8(report_all_as_ctl_seqs) << 3) | (u8(report_text) << 4)) & 0x1f
	}
}

pub fn KittyFlags.from_int(value u8) KittyFlags {
	return KittyFlags{
		value: value & 0x1f
	}
}

pub fn (f KittyFlags) int() u8 {
	return f.value
}

pub fn (f KittyFlags) disambiguate() bool {
	return f.value & 1 != 0
}

pub fn (f KittyFlags) report_events() bool {
	return f.value & 2 != 0
}

pub fn (f KittyFlags) report_alternate_keys() bool {
	return f.value & 4 != 0
}

pub fn (f KittyFlags) report_all_as_ctl_seqs() bool {
	return f.value & 8 != 0
}

pub fn (f KittyFlags) report_text() bool {
	return f.value & 16 != 0
}

// Key represents one decoded terminal key event. V has no u21 integer type,
// so codepoints use u32 while retaining vaxis' u21 value domain.
pub struct Key {
pub mut:
	codepoint             u32
	text                  ?string
	shifted_codepoint     ?u32
	base_layout_codepoint ?u32
	mods                  Modifiers
}

// matches follows vaxis' three matching rules: exact, generated text, then
// shifted codepoint.
pub fn (k Key) matches(cp u32, mods Modifiers) bool {
	if k.match_exact(cp, mods) {
		return true
	}
	if k.match_text(cp, mods) {
		return true
	}
	return k.match_shifted_codepoint(cp, mods)
}

pub fn (k Key) matches_any(cps []u32, mods Modifiers) bool {
	for cp in cps {
		if k.matches(cp, mods) {
			return true
		}
	}
	return false
}

pub fn (k Key) match_shortcut(cp u32, mods Modifiers) bool {
	base := k.base_layout_codepoint or { return false }
	return cp == base && k.mods.eql(mods)
}

pub fn (k Key) match_shifted_codepoint(cp u32, mods Modifiers) bool {
	shifted := k.shifted_codepoint or { return false }
	if !k.mods.shift() {
		return false
	}
	mut self_mods := k.mods
	self_mods.set_shift(false)
	self_mods.set_caps_lock(false)
	self_mods.set_num_lock(false)
	// This deliberately compares against `mods`, matching pinned vaxis. The
	// source also constructs a lock-stripped target but does not use it.
	return cp == shifted && self_mods.eql(mods)
}

pub fn (k Key) match_text(cp u32, mods Modifiers) bool {
	text := k.text or { return false }
	mut self_mods := k.mods
	self_mods.set_num_lock(false)
	self_mods.set_shift(false)
	self_mods.set_caps_lock(false)
	mut arg_mods := mods
	mut text_cp := cp
	if cp < 128 && (mods.shift() || mods.caps_lock()) && cp >= `a` && cp <= `z` {
		text_cp -= 32
	}
	arg_mods.set_num_lock(false)
	arg_mods.set_shift(false)
	arg_mods.set_caps_lock(false)
	if text_cp > 0x10ffff || (text_cp >= 0xd800 && text_cp <= 0xdfff) {
		return false
	}
	return text == rune(text_cp).str() && self_mods.eql(arg_mods)
}

pub fn (k Key) match_exact(cp u32, mods Modifiers) bool {
	mut self_mods := k.mods
	self_mods.set_caps_lock(false)
	self_mods.set_num_lock(false)
	mut target_mods := mods
	target_mods.set_caps_lock(false)
	target_mods.set_num_lock(false)
	return k.codepoint == cp && self_mods.eql(target_mods)
}

pub fn (k Key) is_modifier() bool {
	return k.codepoint in [left_shift, left_alt, left_super, left_hyper, left_control, left_meta,
		right_shift, right_alt, right_super, right_hyper, right_control, right_meta]
}

pub const tab = u32(0x09)
pub const enter = u32(0x0d)
pub const escape = u32(0x1b)
pub const space = u32(0x20)
pub const backspace = u32(0x7f)
pub const multicodepoint = u32(1_114_113)
pub const insert = u32(57348)
pub const delete = u32(57349)
pub const left = u32(57350)
pub const right = u32(57351)
pub const up = u32(57352)
pub const down = u32(57353)
pub const page_up = u32(57354)
pub const page_down = u32(57355)
pub const home = u32(57356)
pub const end = u32(57357)
pub const caps_lock = u32(57358)
pub const scroll_lock = u32(57359)
pub const num_lock = u32(57360)
pub const print_screen = u32(57361)
pub const pause = u32(57362)
pub const menu = u32(57363)
pub const f1 = u32(57364)
pub const f2 = u32(57365)
pub const f3 = u32(57366)
pub const f4 = u32(57367)
pub const f5 = u32(57368)
pub const f6 = u32(57369)
pub const f7 = u32(57370)
pub const f8 = u32(57371)
pub const f9 = u32(57372)
pub const f10 = u32(57373)
pub const f11 = u32(57374)
pub const f12 = u32(57375)
pub const f13 = u32(57376)
pub const f14 = u32(57377)
pub const f15 = u32(57378)
pub const f16 = u32(57379)
pub const f17 = u32(57380)
pub const f18 = u32(57381)
pub const f19 = u32(57382)
pub const f20 = u32(57383)
pub const f21 = u32(57384)
pub const f22 = u32(57385)
pub const f23 = u32(57386)
pub const f24 = u32(57387)
pub const f25 = u32(57388)
pub const f26 = u32(57389)
pub const f27 = u32(57390)
pub const f28 = u32(57391)
pub const f29 = u32(57392)
pub const f30 = u32(57393)
pub const f31 = u32(57394)
// V reserves `f32` as a type name, so this is the source `f32` key constant.
pub const f32_key = u32(57395)
pub const f33 = u32(57396)
pub const f34 = u32(57397)
pub const f35 = u32(57398)
pub const kp_0 = u32(57399)
pub const kp_1 = u32(57400)
pub const kp_2 = u32(57401)
pub const kp_3 = u32(57402)
pub const kp_4 = u32(57403)
pub const kp_5 = u32(57404)
pub const kp_6 = u32(57405)
pub const kp_7 = u32(57406)
pub const kp_8 = u32(57407)
pub const kp_9 = u32(57408)
pub const kp_decimal = u32(57409)
pub const kp_divide = u32(57410)
pub const kp_multiply = u32(57411)
pub const kp_subtract = u32(57412)
pub const kp_add = u32(57413)
pub const kp_enter = u32(57414)
pub const kp_equal = u32(57415)
pub const kp_separator = u32(57416)
pub const kp_left = u32(57417)
pub const kp_right = u32(57418)
pub const kp_up = u32(57419)
pub const kp_down = u32(57420)
pub const kp_page_up = u32(57421)
pub const kp_page_down = u32(57422)
pub const kp_home = u32(57423)
pub const kp_end = u32(57424)
pub const kp_insert = u32(57425)
pub const kp_delete = u32(57426)
pub const kp_begin = u32(57427)
pub const media_play = u32(57428)
pub const media_pause = u32(57429)
pub const media_play_pause = u32(57430)
pub const media_reverse = u32(57431)
pub const media_stop = u32(57432)
pub const media_fast_forward = u32(57433)
pub const media_rewind = u32(57434)
pub const media_track_next = u32(57435)
pub const media_track_previous = u32(57436)
pub const media_record = u32(57437)
pub const lower_volume = u32(57438)
pub const raise_volume = u32(57439)
pub const mute_volume = u32(57440)
pub const left_shift = u32(57441)
pub const left_control = u32(57442)
pub const left_alt = u32(57443)
pub const left_super = u32(57444)
pub const left_hyper = u32(57445)
pub const left_meta = u32(57446)
pub const right_shift = u32(57447)
pub const right_control = u32(57448)
pub const right_alt = u32(57449)
pub const right_super = u32(57450)
pub const right_hyper = u32(57451)
pub const right_meta = u32(57452)
pub const iso_level_3_shift = u32(57453)
pub const iso_level_5_shift = u32(57454)

pub const name_map = {
	'plus':                 u32(`+`)
	'minus':                u32(`-`)
	'colon':                u32(`:`)
	'semicolon':            u32(`;`)
	'comma':                u32(`,`)
	'tab':                  tab
	'enter':                enter
	'escape':               escape
	'space':                space
	'backspace':            backspace
	'insert':               insert
	'delete':               delete
	'left':                 left
	'right':                right
	'up':                   up
	'down':                 down
	'page_up':              page_up
	'page_down':            page_down
	'home':                 home
	'end':                  end
	'caps_lock':            caps_lock
	'scroll_lock':          scroll_lock
	'num_lock':             num_lock
	'print_screen':         print_screen
	'pause':                pause
	'menu':                 menu
	'f1':                   f1
	'f2':                   f2
	'f3':                   f3
	'f4':                   f4
	'f5':                   f5
	'f6':                   f6
	'f7':                   f7
	'f8':                   f8
	'f9':                   f9
	'f10':                  f10
	'f11':                  f11
	'f12':                  f12
	'f13':                  f13
	'f14':                  f14
	'f15':                  f15
	'f16':                  f16
	'f17':                  f17
	'f18':                  f18
	'f19':                  f19
	'f20':                  f20
	'f21':                  f21
	'f22':                  f22
	'f23':                  f23
	'f24':                  f24
	'f25':                  f25
	'f26':                  f26
	'f27':                  f27
	'f28':                  f28
	'f29':                  f29
	'f30':                  f30
	'f31':                  f31
	'f32':                  f32_key
	'f33':                  f33
	'f34':                  f34
	'f35':                  f35
	'kp_0':                 kp_0
	'kp_1':                 kp_1
	'kp_2':                 kp_2
	'kp_3':                 kp_3
	'kp_4':                 kp_4
	'kp_5':                 kp_5
	'kp_6':                 kp_6
	'kp_7':                 kp_7
	'kp_8':                 kp_8
	'kp_9':                 kp_9
	'kp_decimal':           kp_decimal
	'kp_divide':            kp_divide
	'kp_multiply':          kp_multiply
	'kp_subtract':          kp_subtract
	'kp_add':               kp_add
	'kp_enter':             kp_enter
	'kp_equal':             kp_equal
	'kp_separator':         kp_separator
	'kp_left':              kp_left
	'kp_right':             kp_right
	'kp_up':                kp_up
	'kp_down':              kp_down
	'kp_page_up':           kp_page_up
	'kp_page_down':         kp_page_down
	'kp_home':              kp_home
	'kp_end':               kp_end
	'kp_insert':            kp_insert
	'kp_delete':            kp_delete
	'kp_begin':             kp_begin
	'media_play':           media_play
	'media_pause':          media_pause
	'media_play_pause':     media_play_pause
	'media_reverse':        media_reverse
	'media_stop':           media_stop
	'media_fast_forward':   media_fast_forward
	'media_rewind':         media_rewind
	'media_track_next':     media_track_next
	'media_track_previous': media_track_previous
	'media_record':         media_record
	'lower_volume':         lower_volume
	'raise_volume':         raise_volume
	'mute_volume':          mute_volume
	'left_shift':           left_shift
	'left_control':         left_control
	'left_alt':             left_alt
	'left_super':           left_super
	'left_hyper':           left_hyper
	'left_meta':            left_meta
	'right_shift':          right_shift
	'right_control':        right_control
	'right_alt':            right_alt
	'right_super':          right_super
	'right_hyper':          right_hyper
	'right_meta':           right_meta
	'iso_level_3_shift':    iso_level_3_shift
	'iso_level_5_shift':    iso_level_5_shift
}

pub struct Mouse {
pub:
	button  MouseButton
	type_   MouseType
	col     u16
	row     u16
	xoffset u16
	yoffset u16
	mods    MouseModifiers
}

pub enum MouseButton as u8 {
	left
	middle
	right
	none_
	wheel_up    = 64
	wheel_down  = 65
	wheel_right = 66
	wheel_left  = 67
	button_8    = 128
	button_9    = 129
	button_10   = 130
	button_11   = 131
}

pub enum MouseType as u8 {
	press
	release
	motion
	drag
}

// MouseModifiers retains vaxis' packed u3 value in the low three bits.
pub struct MouseModifiers {
	value u8
}

fn MouseModifiers.new(shift bool, alt bool, ctrl bool) MouseModifiers {
	return MouseModifiers{
		value: u8(shift) | (u8(alt) << 1) | (u8(ctrl) << 2)
	}
}

pub fn (m MouseModifiers) shift() bool {
	return m.value & 1 != 0
}

pub fn (m MouseModifiers) alt() bool {
	return m.value & 2 != 0
}

pub fn (m MouseModifiers) ctrl() bool {
	return m.value & 4 != 0
}

pub struct Winsize {
pub:
	rows    u16
	cols    u16
	x_pixel u16
	y_pixel u16
}

pub struct KeyRelease {
pub:
	key Key
}

pub struct MouseLeave {}

pub struct FocusIn {}

pub struct FocusOut {}

pub struct PasteStart {}

pub struct PasteEnd {}

pub struct Paste {
pub:
	text string
}

pub struct ColorReportFg {}

pub struct ColorReportBg {}

pub struct ColorReportCursor {}

pub struct ColorReportIndex {
pub:
	index u8
}

pub type ColorReportKind = ColorReportBg | ColorReportCursor | ColorReportFg | ColorReportIndex

pub struct ColorReport {
pub:
	kind  ColorReportKind
	value [3]u8
}

pub struct ColorScheme {
pub:
	scheme Scheme
}

pub enum Capability as u8 {
	kitty_keyboard
	kitty_graphics
	rgb
	sgr_pixels
	unicode
	da1
	color_scheme_updates
	multi_cursor
}

pub struct CapabilityEvent {
pub:
	capability Capability
}

pub type InputEvent = CapabilityEvent
	| ColorReport
	| ColorScheme
	| FocusIn
	| FocusOut
	| Key
	| KeyRelease
	| Mouse
	| MouseLeave
	| Paste
	| PasteEnd
	| PasteStart
	| Winsize

struct ParsedInput {
	event    ?InputEvent
	consumed int
}

fn own_input_key_text(event InputEvent) InputEvent {
	match event {
		Key {
			mut key := event
			if text := key.text { key.text = text.clone() }
			return InputEvent(key)
		}
		KeyRelease {
			mut key := event.key
			if text := key.text { key.text = text.clone() }
			return InputEvent(KeyRelease{key: key})
		}
		else { return event }
	}
}

// Tty incrementally decodes events read from the terminal.
@[heap]
pub struct Tty {
mut:
	pending        []u8
	fd             int = -1
	original_state termios.Termios
	stdin_handle   voidptr
	stdout_handle  voidptr
	input_mode     u32
	output_mode    u32
	output_cp      u32
	last_mouse_button_press u16
}

pub fn Tty.new() !Tty {
	$if windows {
		tty := Tty.open_windows()!
		register_recovery_tty(tty)
		return tty
	} $else {
		tty := Tty.open_posix()!
		register_recovery_tty(tty)
		return tty
	}
}

// poll returns one event when input is available and otherwise returns none.
pub fn (mut tty Tty) poll() ?InputEvent {
	if tty.pending.len == 0 {
		$if windows {
			raw := term.key_pressed(blocking: false, echo: false)
			if raw < 0 {
				return none
			}
			tty.append_raw(raw)
		} $else {
			tty.poll_posix()
		}
	}
	$if windows {
		for {
			raw := term.key_pressed(blocking: false, echo: false)
			if raw < 0 {
				break
			}
			tty.append_raw(raw)
		}
	} $else {
		tty.poll_posix()
	}

	return tty.parse_pending()
}

fn (mut tty Tty) parse_pending() ?InputEvent {
	for tty.pending.len > 0 {
		parsed := parse_input(tty.pending) or { return none }
		tty.pending.delete_many(0, parsed.consumed)
		if event := parsed.event {
			return event
		}
	}
	return none
}

fn (mut tty Tty) append_raw(value i64) {
	if value == 0 {
		tty.pending << u8(0)
		return
	}
	mut raw := u64(value)
	for _ in 0 .. 8 {
		byte := u8(raw & 0xff)
		if byte == 0 {
			break
		}
		tty.pending << byte
		raw >>= 8
	}
}

fn parse_input(data []u8) ?ParsedInput {
	mut parser := Parser{}
	mut parsed := decode_input(data, mut parser, false) or { return none }
	// The legacy polling adapter owns text because it drains/shifts its dynamic
	// pending buffer before callers can use the returned event.
	if data.len > 1 && data[0] == 27 && data[1] == `[` {
		if event := parsed.event {
			parsed = ParsedInput{ event: own_input_key_text(event), consumed: parsed.consumed }
		}
	}
	return parsed
}

fn decode_input(data []u8, mut parser Parser, borrow bool) ?ParsedInput {
	if data.len == 0 {
		return none
	}

	if data[0] == u8(escape) {
		if data.len == 1 {
			return parsed_key(escape, Modifiers{}, 1)
		}
		match data[1] {
			`O` { return parse_ss3(data) }
			`P`, `X`, `^` { return skip_until_st(data) }
			`[` { return parse_csi(data, mut parser) }
			`]` { return parse_osc(data, true) or { return none } }
			`_` { return parse_apc(data) }
			else {}
		}

		return ParsedInput{
			event:    InputEvent(Key{
				codepoint: u32(data[1])
				mods:      Modifiers.init(false, true, false, false, false, false, false, false)
			})
			consumed: 2
		}
	}

	byte := data[0]
	if byte == 0 {
		return parsed_key(u32(`@`), Modifiers.init(false, false, true, false, false, false, false,
			false), 1)
	}
	if byte == 0x08 {
		return parsed_key(backspace, Modifiers{}, 1)
	}
	if byte == 0x09 {
		return parsed_key(tab, Modifiers{}, 1)
	}
	if byte == 0x0a {
		return parsed_key(u32(`j`), Modifiers.init(false, false, true, false, false, false, false,
			false), 1)
	}
	if byte == 0x0d {
		return parsed_key(enter, Modifiers{}, 1)
	}
	if (byte >= 0x01 && byte <= 0x07) || (byte >= 0x0b && byte <= 0x0c)
		|| (byte >= 0x0e && byte <= 0x1a) {
		return ParsedInput{
			event:    InputEvent(Key{
				codepoint: u32(`a` + byte - 1)
				mods:      Modifiers.init(false, false, true, false, false, false, false, false)
			})
			consumed: 1
		}
	}
	if byte == 0x7f {
		return parsed_key(backspace, Modifiers{}, 1)
	}

	mut iter := InputUtf8Iterator{ bytes: data }
	first := iter.next() or { return none }
	mut consumed := iter.i
	mut rune_count := 1
	mut previous := first
	mut state := unicode.BreakState.default
	for {
		current := iter.next() or { break }
		if vaxis_grapheme_break(previous, current, &state) {
			break
		}
		consumed = iter.i
		rune_count++
		previous = current
	}
	codepoint := if rune_count > 1 { multicodepoint } else { first }
	text := if borrow { unsafe { tos(data.data, consumed) } } else { data[..consumed].bytestr() }
	return parsed_key_text(codepoint, text, Modifiers{}, consumed)
}

fn parse_apc(data []u8) ?ParsedInput {
	if data.len < 3 {
		return none
	}
	sequence_end := find_byte(data, 2, u8(escape))
	if sequence_end < 0 {
		return none
	}
	consumed := sequence_end + 2
	input_parser_slice(data, 0, consumed)
	if data[2] == `G` {
		return ParsedInput{
			event:    InputEvent(CapabilityEvent{
				capability: .kitty_graphics
			})
			consumed: consumed
		}
	}
	return ParsedInput{
		consumed: consumed
	}
}

fn skip_until_st(data []u8) ?ParsedInput {
	if data.len < 3 {
		return none
	}
	sequence_end := find_byte(data, 2, u8(escape))
	if sequence_end < 0 || data.len < sequence_end + 2 {
		return none
	}
	return ParsedInput{
		consumed: sequence_end + 2
	}
}

fn parse_osc(data []u8, clipboard bool) !ParsedInput {
	if data.len < 3 {
		return ParsedInput{}
	}
	mut bel_terminated := false
	mut sequence_end := 0
	escape_end := find_byte(data, 2, u8(escape))
	if escape_end >= 0 && data.len >= escape_end + 2 {
		sequence_end = escape_end + 2
	} else {
		bel := find_byte(data, 2, 0x07)
		if bel < 0 {
			return ParsedInput{}
		}
		bel_terminated = true
		sequence_end = bel + 1
	}
	semicolon := find_byte(data, 2, `;`)
	if semicolon < 0 {
		return ParsedInput{
			consumed: sequence_end
		}
	}
	ps := parse_input_unsigned(data[2..semicolon].bytestr(), 10, 8) or {
		return ParsedInput{
			consumed: sequence_end
		}
	}
	content_end := if bel_terminated { sequence_end - 1 } else { sequence_end - 2 }
	if ps == 4 {
		color_delimiter := find_byte(data, semicolon + 1, `;`)
		if color_delimiter < 0 {
			return ParsedInput{
				consumed: sequence_end
			}
		}
		index := parse_input_unsigned(data[semicolon + 1..color_delimiter].bytestr(), 10, 8) or {
			return ParsedInput{
				consumed: sequence_end
			}
		}
		rgb :=
			parse_color_spec(input_parser_slice(data, color_delimiter + 1, content_end).bytestr())!
		return ParsedInput{
			event:    InputEvent(ColorReport{
				kind:  ColorReportKind(ColorReportIndex{
					index: u8(index)
				})
				value: rgb
			})
			consumed: sequence_end
		}
	}
	if ps == 10 || ps == 11 || ps == 12 {
		rgb := parse_color_spec(input_parser_slice(data, semicolon + 1, content_end).bytestr())!
		kind := match ps {
			10 {
				ColorReportKind(ColorReportFg{})
			}
			11 {
				ColorReportKind(ColorReportBg{})
			}
			12 {
				ColorReportKind(ColorReportCursor{})
			}
			else {
				return ParsedInput{
					consumed: sequence_end
				}
			}
		}

		return ParsedInput{
			event:    InputEvent(ColorReport{
				kind:  kind
				value: rgb
			})
			consumed: sequence_end
		}
	}
	if ps == 52 {
		if data[semicolon + 1] != `c` {
			return ParsedInput{
				consumed: sequence_end
			}
		}
		payload := input_parser_slice(data, semicolon + 3, content_end)
		if !clipboard { panic('attempt to use null value') }
		text := decode_clipboard_base64(payload)!
		return ParsedInput{
			event:    InputEvent(Paste{
				text: text
			})
			consumed: sequence_end
		}
	}
	return ParsedInput{
		consumed: sequence_end
	}
}

fn parse_color_spec(spec string) ![3]u8 {
	parts := spec.split(':')
	if parts.len < 2 || parts[0] != 'rgb' {
		return error('InvalidColorSpec')
	}
	channels := parts[1].split('/')
	if channels.len < 3 {
		return error('InvalidColorSpec')
	}
	mut result := [3]u8{}
	for channel in channels[..3] {
		if channel.len != 4 {
			return error('InvalidColorSpec')
		}
	}
	for i, channel in channels[..3] {
		result[i] = u8(parse_input_unsigned(channel[2..], 16, 8)!)
	}
	return result
}

fn find_byte(data []u8, start int, target u8) int {
	for i in start .. data.len {
		if data[i] == target {
			return i
		}
	}
	return -1
}

fn parse_ss3(data []u8) ?ParsedInput {
	if data.len < 3 {
		return none
	}
	if data[2] == u8(escape) {
		return ParsedInput{
			consumed: 2
		}
	}
	code := match data[2] {
		`A` {
			up
		}
		`B` {
			down
		}
		`C` {
			right
		}
		`D` {
			left
		}
		`E` {
			kp_begin
		}
		`F` {
			end
		}
		`H` {
			home
		}
		`P` {
			f1
		}
		`Q` {
			f2
		}
		`R` {
			f3
		}
		`S` {
			f4
		}
		else {
			return ParsedInput{
				consumed: 3
			}
		}
	}

	return parsed_key(code, Modifiers{}, 3)
}

fn parse_csi(data []u8, mut parser Parser) ?ParsedInput {
	mut final_index := -1
	for i in 2 .. data.len {
		byte := data[i]
		if byte >= 0x40 {
			final_index = i
			break
		}
	}
	if final_index < 0 {
		return none
	}

	sequence := data[..final_index + 1].bytestr()
	final := data[final_index]
	if final == `M` || final == `m` {
		return parse_mouse(data, sequence)
	}

	if final in [`A`, `B`, `C`, `D`, `E`, `F`, `H`, `P`, `Q`, `R`, `S`] {
		code := match final {
			`A` {
				up
			}
			`B` {
				down
			}
			`C` {
				right
			}
			`D` {
				left
			}
			`E` {
				kp_begin
			}
			`F` {
				end
			}
			`H` {
				home
			}
			`P` {
				f1
			}
			`Q` {
				f2
			}
			`R` {
				f3
			}
			`S` {
				f4
			}
			else {
				return ParsedInput{
					consumed: sequence.len
				}
			}
		}

		mut key := Key{
			codepoint: code
		}
		mut is_release := false
		fields := sequence[2..sequence.len - 1].split(';')
		if fields.len > 1 {
			modifier_parts := fields[1].split(':')
			mask := parse_param_u8(modifier_parts[0], u8(1)) or {
				return ParsedInput{
					consumed: sequence.len
				}
			}
			key.mods = Modifiers.from_int(if mask > 0 { mask - 1 } else { 0 })
			if modifier_parts.len > 1 && modifier_parts[1] == '3' {
				is_release = true
			}
		}
		if fields.len > 2 {
			key.text = parser.parse_codepoint_text(fields[2]) or {
				return ParsedInput{
					consumed: sequence.len
				}
			}
		}
		return ParsedInput{
			event:    if is_release {
				InputEvent(KeyRelease{
					key: key
				})
			} else {
				InputEvent(key)
			}
			consumed: sequence.len
		}
	}

	if final == `~` {
		fields := sequence[2..sequence.len - 1].split(';')
		number := parse_input_unsigned(fields[0], 10, 16) or {
			return ParsedInput{
				consumed: sequence.len
			}
		}
		if number == 200 {
			return ParsedInput{
				event:    InputEvent(PasteStart{})
				consumed: sequence.len
			}
		}
		if number == 201 {
			return ParsedInput{
				event:    InputEvent(PasteEnd{})
				consumed: sequence.len
			}
		}
		code := match number {
			2 {
				insert
			}
			3 {
				delete
			}
			5 {
				page_up
			}
			6 {
				page_down
			}
			7 {
				home
			}
			8 {
				end
			}
			11 {
				f1
			}
			12 {
				f2
			}
			13 {
				f3
			}
			14 {
				f4
			}
			15 {
				f5
			}
			17 {
				f6
			}
			18 {
				f7
			}
			19 {
				f8
			}
			20 {
				f9
			}
			21 {
				f10
			}
			23 {
				f11
			}
			24 {
				f12
			}
			57427 {
				kp_begin
			}
			else {
				return ParsedInput{
					consumed: sequence.len
				}
			}
		}

		mut key := Key{
			codepoint: code
		}
		mut is_release := false
		if fields.len > 1 {
			modifier_parts := fields[1].split(':')
			mask := parse_param_u8(modifier_parts[0], u8(1)) or {
				return ParsedInput{
					consumed: sequence.len
				}
			}
			key.mods = Modifiers.from_int(if mask > 0 { mask - 1 } else { 0 })
			if modifier_parts.len > 1 && modifier_parts[1] == '3' {
				is_release = true
			}
		}
		if fields.len > 2 {
			key.text = parser.parse_codepoint_text(fields[2]) or {
				return ParsedInput{
					consumed: sequence.len
				}
			}
		}
		return ParsedInput{
			event:    if is_release {
				InputEvent(KeyRelease{
					key: key
				})
			} else {
				InputEvent(key)
			}
			consumed: sequence.len
		}
	}

	if final == `I` {
		return ParsedInput{
			event:    InputEvent(FocusIn{})
			consumed: sequence.len
		}
	}
	if final == `O` {
		return ParsedInput{
			event:    InputEvent(FocusOut{})
			consumed: sequence.len
		}
	}
	if final == `c` {
		if sequence.len < 4 { panic('Assertion failed: sequence.len >= 4') }
		if sequence[2] == `?` {
			return ParsedInput{
				event:    InputEvent(CapabilityEvent{
					capability: .da1
				})
				consumed: sequence.len
			}
		}
		return ParsedInput{
			consumed: sequence.len
		}
	}
	if final == `n` {
		if sequence.len >= 3 && sequence[2] == `?` {
			delimiter := find_byte(data, 3, `;`)
			if delimiter >= 0 {
				ps := parse_input_unsigned(data[3..delimiter].bytestr(), 10, 16) or {
					return ParsedInput{
						consumed: sequence.len
					}
				}
				if ps == 997 {
					if delimiter + 1 >= sequence.len { panic('index out of bounds') }
					scheme := match sequence[delimiter + 1] {
						`1` {
							Scheme.dark
						}
						`2` {
							Scheme.light
						}
						else {
							return ParsedInput{
								consumed: sequence.len
							}
						}
					}

					return ParsedInput{
						event:    InputEvent(ColorScheme{
							scheme: scheme
						})
						consumed: sequence.len
					}
				}
			}
		}
		return ParsedInput{
			consumed: sequence.len
		}
	}
	if final == `t` {
		fields := sequence[2..sequence.len - 1].split(';')
		if fields.len >= 3 && fields[0] == '48' {
			rows := parse_u16(fields[1]) or { return ParsedInput{
				consumed: sequence.len
			} }
			cols := parse_u16(fields[2]) or { return ParsedInput{
				consumed: sequence.len
			} }
			y_pixel := if fields.len > 3 {
				parse_u16(fields[3]) or { return ParsedInput{
					consumed: sequence.len
				} }
			} else {
				u16(0)
			}
			x_pixel := if fields.len > 4 {
				parse_u16(fields[4]) or { return ParsedInput{
					consumed: sequence.len
				} }
			} else {
				u16(0)
			}
			return ParsedInput{
				event:    InputEvent(Winsize{
					rows:    rows
					cols:    cols
					x_pixel: x_pixel
					y_pixel: y_pixel
				})
				consumed: sequence.len
			}
		}
		return ParsedInput{
			consumed: sequence.len
		}
	}

	if final == `u` {
		if sequence.len > 2 && sequence[2] == `?` {
			return ParsedInput{
				event:    InputEvent(CapabilityEvent{
					capability: .kitty_keyboard
				})
				consumed: sequence.len
			}
		}
		fields := sequence[2..sequence.len - 1].split(';')
		alternate := fields[0].split(':')
		codepoint := parse_param_u21(alternate[0]) or {
			return ParsedInput{
				consumed: sequence.len
			}
		}
		mut key := Key{
			codepoint: codepoint
		}
		mut is_release := false
		if alternate.len > 1 {
			key.shifted_codepoint = parse_param_u21(alternate[1])
		}
		if alternate.len > 2 {
			key.base_layout_codepoint = parse_param_u21(alternate[2])
		}
		if fields.len > 1 {
			modifier_parts := fields[1].split(':')
			mask := parse_param_u8(modifier_parts[0], u8(1)) or {
				return ParsedInput{
					consumed: sequence.len
				}
			}
			key.mods = Modifiers.from_int(if mask > 0 { mask - 1 } else { 0 })
			if modifier_parts.len > 1 && modifier_parts[1] == '3' {
				is_release = true
			}
		}
		if fields.len > 2 {
			key.text = parser.parse_codepoint_text(fields[2]) or {
				return ParsedInput{
					consumed: sequence.len
				}
			}
		}
		only_shift := Modifiers.init(true, false, false, false, false, false, key.mods.caps_lock(),
			key.mods.num_lock())
		if key.text == none && key.mods.eql(only_shift) && key.codepoint <= 0xff
			&& key.codepoint >= 0x20 && key.codepoint <= 0x7e {
			upper := if key.codepoint >= `a` && key.codepoint <= `z` {
				key.codepoint - 32
			} else {
				key.codepoint
			}
			parser.buf[0] = u8(upper)
			key.text = unsafe { tos(&parser.buf[0], 1) }
			key.shifted_codepoint = upper
		}
		return ParsedInput{
			event:    if is_release {
				InputEvent(KeyRelease{
					key: key
				})
			} else {
				InputEvent(key)
			}
			consumed: sequence.len
		}
	}

	if final == `y` {
		delimiter := find_byte(data, 3, `;`)
		if delimiter >= 0 {
			ps := parse_input_unsigned(data[3..delimiter].bytestr(), 10, 16) or {
				return ParsedInput{
					consumed: sequence.len
				}
			}
			pm := parse_input_unsigned(input_parser_slice(data, delimiter + 1, sequence.len - 2).bytestr(),
				10, 8) or { return ParsedInput{
				consumed: sequence.len
			} }
			capability := match ps {
				1016 {
					Capability.sgr_pixels
				}
				2027 {
					Capability.unicode
				}
				2031 {
					Capability.color_scheme_updates
				}
				else {
					return ParsedInput{
						consumed: sequence.len
					}
				}
			}

			if pm != 0 && pm != 4 {
				return ParsedInput{
					event:    InputEvent(CapabilityEvent{
						capability: capability
					})
					consumed: sequence.len
				}
			}
		}
		return ParsedInput{
			consumed: sequence.len
		}
	}
	if final == `q` {
		if sequence.len >= 2 && sequence[sequence.len - 2] == ` ` {
			for byte in sequence[..sequence.len - 2].bytes() {
				if byte >= `0` && byte <= `9` {
					return ParsedInput{
						event:    InputEvent(CapabilityEvent{
							capability: .multi_cursor
						})
						consumed: sequence.len
					}
				}
			}
		}
		return ParsedInput{
			consumed: sequence.len
		}
	}

	return ParsedInput{
		consumed: sequence.len
	}
}

fn parse_u16(raw string) ?u16 {
	return u16(parse_input_unsigned(raw, 10, 16) or { return none })
}

fn parse_param_u8(raw string, default ?u8) ?u8 {
	if raw.len == 0 {
		return default
	}
	return u8(parse_input_unsigned(raw, 10, 8) or { return none })
}

fn parse_param_u21(raw string) ?u32 {
	value := parse_param_u32(raw, none) or { return none }
	if value > 0x1fffff {
		return none
	}
	return value
}

fn parse_mouse(data []u8, sequence string) ?ParsedInput {
	mut button_mask := u64(0)
	mut px := u16(0)
	mut py := u16(0)
	mut xterm := false
	if sequence.len == 3 && sequence[2] == `M` {
		if data.len < 6 {
			return ParsedInput{
				consumed: sequence.len
			}
		}
		xterm = true
		button_mask = u64(input_parser_sub32(data[3]))
		px = input_parser_sub32(data[4])
		py = input_parser_sub32(data[5])
	} else if sequence.len >= 4 && sequence[2] == `<` {
		parts := sequence[3..sequence.len - 1].split(';')
		if parts.len != 3 {
			return ParsedInput{
				consumed: sequence.len
			}
		}
		button_mask = parse_input_unsigned(parts[0], 10, 16) or {
			return ParsedInput{
				consumed: sequence.len
			}
		}
		px = parse_mouse_position(parts[1]) or { return ParsedInput{
			consumed: sequence.len
		} }
		py = parse_mouse_position(parts[2]) or { return ParsedInput{
			consumed: sequence.len
		} }
	} else {
		return ParsedInput{
			consumed: sequence.len
		}
	}
	if button_mask & 0x100 != 0 {
		return ParsedInput{
			event:    InputEvent(MouseLeave{})
			consumed: if xterm { 6 } else { sequence.len }
		}
	}
	button_value := u8(button_mask & 0xc3)
	if button_value >= 192 { panic('invalid enum value') }
	button := unsafe { MouseButton(button_value) }
	motion := button_mask & 0x20 != 0
	type_ := if motion && button != .none_ {
		MouseType.drag
	} else if motion {
		MouseType.motion
	} else if xterm && button == .none_ {
		MouseType.release
	} else if !xterm && sequence.ends_with('m') {
		MouseType.release
	} else {
		MouseType.press
	}
	return ParsedInput{
		event:    InputEvent(Mouse{
			button: button
			type_:  type_
			row:    if py == 0 { u16(0) } else { u16(py - 1) }
			col:    if px == 0 { u16(0) } else { u16(px - 1) }
			mods:   MouseModifiers.new(button_mask & 0x04 != 0, button_mask & 0x08 != 0,
				button_mask & 0x10 != 0)
		})
		consumed: if xterm { 6 } else { sequence.len }
	}
}

fn parse_param_u32(raw string, default ?u32) ?u32 {
	if raw.len == 0 {
		return default
	}
	return u32(parse_input_unsigned(raw, 10, 32) or { return none })
}

fn parse_mouse_position(raw string) ?u16 {
	if raw.len == 0 {
		return u16(1)
	}
	return u16(parse_input_unsigned(raw, 10, 16) or { return none })
}

fn parsed_key(codepoint u32, mods Modifiers, consumed int) ParsedInput {
	return ParsedInput{
		event:    InputEvent(Key{
			codepoint: codepoint
			mods:      mods
		})
		consumed: consumed
	}
}

fn parsed_key_text(codepoint u32, text string, mods Modifiers, consumed int) ParsedInput {
	return ParsedInput{
		event:    InputEvent(Key{
			codepoint: codepoint
			text:      text
			mods:      mods
		})
		consumed: consumed
	}
}

// TextInputBuffer is the source TextInput.Buffer gap buffer. V's arrays own
// their storage, replacing the source allocator field without changing the
// cursor/gap behavior.
pub struct TextInputBuffer {
pub mut:
	buffer   []u8  @[required]
	cursor   uint @[required]
	gap_size uint @[required]
}

pub fn TextInputBuffer.new() TextInputBuffer {
	return TextInputBuffer{
		buffer:   []u8{}
		cursor:   0
		gap_size: 0
	}
}

pub fn (mut b TextInputBuffer) deinit() {
	b.clear_and_free()
}

pub fn (b &TextInputBuffer) first_half() []u8 {
	if b.cursor > uint(b.buffer.len) {
		panic('index out of bounds')
	}
	return b.buffer[..int(b.cursor)]
}

pub fn (b &TextInputBuffer) second_half() []u8 {
	start := widget_checked_add(b.cursor, b.gap_size)
	if start > uint(b.buffer.len) {
		panic('index out of bounds')
	}
	return b.buffer[int(start)..]
}

pub fn (mut b TextInputBuffer) grow(n uint) {
	new_length := widget_checked_add(widget_checked_add(uint(b.buffer.len), n), 512)
	if new_length > uint(0x7fffffff) {
		panic('TextInputBuffer allocation exceeds V array capacity')
	}
	new_size := int(new_length)
	mut new_memory := []u8{len: new_size}
	first := b.first_half()
	second := b.second_half()
	copy(mut new_memory[..first.len], first)
	copy(mut new_memory[new_size - second.len..], second)
	b.buffer = new_memory
	remaining := uint(new_size - second.len)
	if b.cursor > remaining {
		panic('integer overflow')
	}
	b.gap_size = remaining - b.cursor
}

pub fn (mut b TextInputBuffer) insert_slice_at_cursor(data string) {
	if data.len == 0 {
		return
	}
	if b.gap_size <= uint(data.len) {
		b.grow(uint(data.len))
	}
	limit := widget_checked_add(b.cursor, uint(data.len))
	if limit > uint(b.buffer.len) {
		panic('index out of bounds')
	}
	copy(mut b.buffer[int(b.cursor)..int(limit)], data.bytes())
	b.cursor = limit
	if b.gap_size < uint(data.len) {
		panic('integer overflow')
	}
	b.gap_size -= uint(data.len)
}

pub fn (mut b TextInputBuffer) move_gap_left(n uint) {
	new_index := if n > b.cursor { uint(0) } else { b.cursor - n }
	destination := widget_checked_add(new_index, b.gap_size)
	if destination > uint(b.buffer.len) || b.cursor > uint(b.buffer.len) {
		panic('index out of bounds')
	}
	count := b.cursor - new_index
	if count > uint(b.buffer.len) - destination {
		panic('index out of bounds')
	}
	for i in 0 .. int(count) {
		b.buffer[int(destination) + i] = b.buffer[int(new_index) + i]
	}
	b.cursor = new_index
}

pub fn (mut b TextInputBuffer) move_gap_right(n uint) {
	new_index := widget_checked_add(b.cursor, n)
	if b.cursor > uint(b.buffer.len) {
		panic('start index ${u64(b.cursor).str()} is larger than end index ${b.buffer.len}')
	}
	source := widget_checked_add(b.cursor, b.gap_size)
	limit := widget_checked_add(new_index, b.gap_size)
	if source > limit || limit > uint(b.buffer.len) {
		panic('index out of bounds')
	}
	for i in 0 .. int(n) {
		b.buffer[int(b.cursor) + i] = b.buffer[int(source) + i]
	}
	b.cursor = new_index
}

pub fn (mut b TextInputBuffer) grow_gap_left(n uint) {
	b.gap_size = widget_checked_add(b.gap_size, n)
	b.cursor = widget_saturating_sub(b.cursor, n)
}

pub fn (mut b TextInputBuffer) grow_gap_right(n uint) {
	new_gap := widget_checked_add(b.gap_size, n)
	if b.cursor > uint(b.buffer.len) {
		panic('integer overflow')
	}
	maximum := uint(b.buffer.len) - b.cursor
	b.gap_size = if new_gap > maximum { maximum } else { new_gap }
}

pub fn (mut b TextInputBuffer) clear_and_free() {
	b.cursor = 0
	b.buffer = []u8{}
	b.gap_size = 0
}

pub fn (mut b TextInputBuffer) clear_retaining_capacity() {
	b.cursor = 0
	b.gap_size = uint(b.buffer.len)
}

pub fn (mut b TextInputBuffer) to_owned_slice() string {
	result := b.string()
	b.clear_and_free()
	return result
}

pub fn (b &TextInputBuffer) real_length() uint {
	return uint(b.first_half().len + b.second_half().len)
}

pub fn (b &TextInputBuffer) string() string {
	mut result := []u8{len: int(b.real_length())}
	first := b.first_half()
	second := b.second_half()
	copy(mut result[..first.len], first)
	copy(mut result[first.len..], second)
	return result.bytestr()
}

// TextInput implements vaxis' cursor-aware editing behavior.
pub struct TextInput {
pub mut:
	buf             TextInputBuffer @[required]
	draw_offset     u16
	prev_cursor_col u16
	prev_cursor_idx u16
	scroll_offset   u16 = 4
}

pub fn TextInput.new() TextInput {
	return TextInput{
		buf: TextInputBuffer.new()
	}
}

pub fn (mut t TextInput) deinit() {
	t.buf.deinit()
}

pub fn (t &TextInput) real_length() uint {
	return t.buf.real_length()
}

pub fn (t &TextInput) get_text() string {
	return t.buf.string()
}

pub fn (mut t TextInput) update(key Key) {
	ctrl := Modifiers.from_int(4)
	alt := Modifiers.from_int(2)
	if key.matches(backspace, Modifiers{}) {
		t.delete_before_cursor()
	} else if key.matches(delete, Modifiers{}) || key.matches(u32(`d`), ctrl) {
		t.delete_after_cursor()
	} else if key.matches(left, Modifiers{}) || key.matches(u32(`b`), ctrl) {
		t.cursor_left()
	} else if key.matches(right, Modifiers{}) || key.matches(u32(`f`), ctrl) {
		t.cursor_right()
	} else if key.matches(u32(`a`), ctrl) || key.matches(home, Modifiers{}) {
		t.buf.move_gap_left(uint(t.buf.first_half().len))
	} else if key.matches(u32(`e`), ctrl) || key.matches(end, Modifiers{}) {
		t.buf.move_gap_right(uint(t.buf.second_half().len))
	} else if key.matches(u32(`k`), ctrl) {
		t.delete_to_end()
	} else if key.matches(u32(`u`), ctrl) {
		t.delete_to_start()
	} else if key.matches(u32(`b`), alt) || key.matches(left, alt) {
		t.move_backward_wordwise()
	} else if key.matches(u32(`f`), alt) || key.matches(right, alt) {
		t.move_forward_wordwise()
	} else if key.matches(u32(`w`), ctrl) || key.matches(backspace, alt) {
		t.delete_word_before()
	} else if key.matches(u32(`d`), alt) {
		t.delete_word_after()
	} else if text := key.text {
		t.insert_slice_at_cursor(text)
	}
}

pub fn (mut t TextInput) insert_slice_at_cursor(data string) {
	mut iter := text_input_grapheme_iterator(data)
	for {
		grapheme := iter.next() or { break }
		t.buf.insert_slice_at_cursor(data[grapheme.start..grapheme.limit])
	}
}

pub fn (t &TextInput) slice_to_cursor() string {
	return t.buf.first_half().bytestr()
}

// Source sliceToCursor copies into caller storage and returns its borrowed prefix.
pub fn (t &TextInput) slice_to_cursor_into(mut bytes []u8) []u8 {
	if uint(bytes.len) < t.buf.cursor { panic('Assertion failed') }
	first := t.buf.first_half()
	span := uint(first.len)
	source_address := uint(first.data)
	destination_address := uint(bytes.data)
	if span > 0 && source_address < destination_address + span
		&& destination_address < source_address + span {
		panic('@memcpy arguments alias')
	}
	copy(mut bytes[..first.len], first)
	return unsafe { bytes[..first.len] }
}

pub fn (mut t TextInput) cursor_left() {
	length := text_input_last_grapheme_byte_length(t.buf.first_half().bytestr())
	t.buf.move_gap_left(uint(length))
}

pub fn (mut t TextInput) cursor_right() {
	length := text_input_first_grapheme_byte_length(t.buf.second_half().bytestr())
	t.buf.move_gap_right(uint(length))
}

pub fn (t &TextInput) graphemes_before_cursor() u16 {
	mut iter := text_input_grapheme_iterator(t.buf.first_half().bytestr())
	mut count := 0
	for {
		iter.next() or { break }
		count = text_input_checked_u16_add(count, 1)
	}
	return u16(count)
}

// TextInputDraw is the cell-level result of drawing the source widget into a
// window. The ANSI preview adapter writes these cells at the window's origin.
pub struct TextInputDraw {
pub:
	cells      []TextInputCell
	cursor_col u16
	style      Style
}

pub struct TextInputCell {
pub:
	col  u16
	text string
}

pub fn (mut t TextInput) draw(width int) TextInputDraw {
	return t.draw_with_style(width, Style{})
}

// draw_with_style follows the pinned TextInput.drawWithStyle cursor, scroll,
// and ellipsis rules. Width represents the interior width of its child window.
pub fn (mut t TextInput) draw_with_style(width int, style Style) TextInputDraw {
	return t.draw_with_style_method(width, style, .wcwidth)
}

// The Window passed to pinned TextInput.drawWithStyle supplies this method
// through its Screen. The ANSI adapter passes the negotiated method directly.
pub fn (mut t TextInput) draw_with_style_method(width int, style Style, method GWidthMethod) TextInputDraw {
	mut cells := []TextInputCell{}
	cursor_idx := t.graphemes_before_cursor()
	if cursor_idx < t.draw_offset {
		t.draw_offset = cursor_idx
	}
	if width <= 0 {
		return TextInputDraw{
			style: style
		}
	}

	for {
		cursor_width := t.width_to_cursor_method(method)
		if cursor_width < width {
			break
		}
		delta := cursor_width - width + 1
		next_offset := int(t.draw_offset) + delta
		t.draw_offset = u16(if next_offset > 0xffff { 0xffff } else { next_offset })
	}

	t.prev_cursor_idx = cursor_idx
	t.prev_cursor_col = 0
	mut col := 0
	mut i := 0
	first := t.buf.first_half().bytestr()
	mut first_iter := text_input_grapheme_iterator(first)
	for {
		value := first_iter.next() or { break }
		grapheme := first[value.start..value.limit]
		if i < int(t.draw_offset) {
			i = text_input_checked_u16_add(i, 1)
			continue
		}
		w := int(text_input_gwidth(grapheme, method))
		next_col := text_input_checked_u16_add(col, w)
		if next_col >= width {
			cells << TextInputCell{
				col:  u16(width - 1)
				text: '…'
			}
			break
		}
		if w > 0xff { panic('integer does not fit in destination type') }
		cells << TextInputCell{
			col:  u16(col)
			text: grapheme
		}
		col = next_col
		i = text_input_checked_u16_add(i, 1)
		if i == int(cursor_idx) {
			t.prev_cursor_col = u16(col)
		}
	}

	second := t.buf.second_half().bytestr()
	mut second_iter := text_input_grapheme_iterator(second)
	for {
		value := second_iter.next() or { break }
		grapheme := second[value.start..value.limit]
		if i < int(t.draw_offset) {
			i = text_input_checked_u16_add(i, 1)
			continue
		}
		w := int(text_input_gwidth(grapheme, method))
		next_col := text_input_checked_u16_add(col, w)
		if next_col > width {
			cells << TextInputCell{
				col:  u16(width - 1)
				text: '…'
			}
			break
		}
		if w > 0xff { panic('integer does not fit in destination type') }
		cells << TextInputCell{
			col:  u16(col)
			text: grapheme
		}
		col = next_col
		i = text_input_checked_u16_add(i, 1)
		if i == int(cursor_idx) {
			t.prev_cursor_col = u16(col)
		}
	}
	if t.draw_offset > 0 {
		cells << TextInputCell{
			col:  0
			text: '…'
		}
	}
	return TextInputDraw{
		cells:      cells
		cursor_col: t.prev_cursor_col
		style:      style
	}
}

pub fn (t &TextInput) width_to_cursor() int {
	return t.width_to_cursor_method(.wcwidth)
}

pub fn (t &TextInput) width_to_cursor_method(method GWidthMethod) int {
	first := t.buf.first_half().bytestr()
	mut iter := text_input_grapheme_iterator(first)
	mut i := 0
	mut width := 0
	for {
		value := iter.next() or { break }
		if i >= int(t.draw_offset) {
			width = text_input_checked_u16_add(width, int(text_input_gwidth(first[value.start..value.limit],
				method)))
		}
		i++
	}
	return width
}

// GWidthMethod is the pinned vaxis width strategy selected by terminal
// capabilities. TextInput starts with wcwidth, the source default.
pub enum GWidthMethod as u8 {
	unicode
	wcwidth
	no_zwj
}

// These merged ranges are generated from vaxis' locked uucode UCD files.
const pinned_width_data = $embed_file('@VMODROOT/vaxis/width_data.bin').to_bytes()

fn width_data_u32(index int) u32 {
	offset := index * 4
	return u32(pinned_width_data[offset]) | (u32(pinned_width_data[offset + 1]) << 8)
		| (u32(pinned_width_data[offset + 2]) << 16) | (u32(pinned_width_data[offset + 3]) << 24)
}

fn width_property(cp u32, group int) bool {
	mut offset := 4
	for previous in 0 .. group {
		offset += int(width_data_u32(previous)) * 2
	}
	mut range_left := 0
	mut range_right := int(width_data_u32(group))
	for range_left < range_right {
		middle := (range_left + range_right) / 2
		start := width_data_u32(offset + middle * 2)
		range_end := width_data_u32(offset + middle * 2 + 1)
		if cp < start {
			range_right = middle
		} else if cp > range_end {
			range_left = middle + 1
		} else {
			return true
		}
	}
	return false
}

fn eaw_to_width(cp u32) int {
	if cp == 0 {
		return 0
	}
	if cp < 32 || (cp >= 0x7f && cp < 0xa0) {
		return -1
	}
	if width_property(cp, 1) || cp == 0x00ad || cp == 0x200b || cp == 0x200c
		|| cp == 0x200d || cp == 0x2060 || cp == 0x034f || cp == 0xfeff
		|| (cp >= 0x180b && cp <= 0x180d) || (cp >= 0xfe00 && cp <= 0xfe0f)
		|| (cp >= 0xe0100 && cp <= 0xe01ef) {
		return 0
	}
	return if width_property(cp, 0) { 2 } else { 1 }
}

// gwidth translates vaxis/src/gwidth.zig using the locked uucode byte decoder.
pub fn gwidth(value string, method GWidthMethod) u16 {
	return text_input_gwidth(value, method)
}

pub fn (mut t TextInput) clear_and_free() {
	t.buf.clear_and_free()
	t.reset()
}

pub fn (mut t TextInput) clear_retaining_capacity() {
	t.buf.clear_retaining_capacity()
	t.reset()
}

pub fn (mut t TextInput) to_owned_slice() string {
	defer {
		t.reset()
	}
	return t.buf.to_owned_slice()
}

pub fn (mut t TextInput) reset() {
	t.draw_offset = 0
	t.prev_cursor_col = 0
	t.prev_cursor_idx = 0
}

pub fn (t &TextInput) byte_offset_to_cursor() uint {
	return t.buf.cursor
}

pub fn (mut t TextInput) delete_to_end() {
	t.buf.grow_gap_right(uint(t.buf.second_half().len))
}

pub fn (mut t TextInput) delete_to_start() {
	t.buf.grow_gap_left(t.buf.cursor)
}

pub fn (mut t TextInput) delete_before_cursor() {
	length := text_input_last_grapheme_byte_length(t.buf.first_half().bytestr())
	t.buf.grow_gap_left(uint(length))
}

pub fn (mut t TextInput) delete_after_cursor() {
	length := text_input_first_grapheme_byte_length(t.buf.second_half().bytestr())
	t.buf.grow_gap_right(uint(length))
}

pub fn (mut t TextInput) move_backward_wordwise() {
	first := t.buf.first_half().bytestr()
	trimmed := first.trim_right(' ')
	index := trimmed.last_index(' ') or { -1 }
	destination := if index < 0 { uint(0) } else { uint(index + 1) }
	t.buf.move_gap_left(t.buf.cursor - destination)
}

pub fn (mut t TextInput) move_forward_wordwise() {
	second := t.buf.second_half()
	mut i := 0
	for i < second.len && second[i] == ` ` {
		i++
	}
	mut index := second.len
	for j in i .. second.len {
		if second[j] == ` ` {
			index = j
			break
		}
	}
	t.buf.move_gap_right(uint(index))
}

pub fn (mut t TextInput) delete_word_before() {
	previous := t.buf.cursor
	t.move_backward_wordwise()
	t.buf.grow_gap_right(previous - t.buf.cursor)
}

pub fn (mut t TextInput) delete_word_after() {
	second := t.buf.second_half()
	mut i := 0
	for i < second.len && second[i] == ` ` {
		i++
	}
	mut index := second.len
	for j in i .. second.len {
		if second[j] == ` ` {
			index = j
			break
		}
	}
	t.buf.grow_gap_right(uint(index))
}

pub fn first_grapheme_byte_length(text string) int {
	return text_input_first_grapheme_byte_length(text)
}

// The two pinned uucode revisions share Unicode 16 data, but Ghostty tailors
// emoji modifier clusters while vaxis follows GraphemeBreakProperty=Extend.
// Map those classes to vaxis' source classes in the shared transition table.
fn vaxis_grapheme_break(cp1 u32, cp2 u32, state &unicode.BreakState) bool {
	if cp1 == 0x0d && cp2 == 0x0a {
		unsafe { *state = .default }
		return false
	}
	if cp1 == 0x0d || cp1 == 0x0a || cp2 == 0x0d || cp2 == 0x0a
		|| width_property(cp1, 3) || width_property(cp2, 3) {
		unsafe { *state = .default }
		return true
	}
	gb1 := unicode.get(cp1).grapheme_break()
	gb2 := unicode.get(cp2).grapheme_break()
	from := match gb1 {
		.emoji_modifier_base { u32(0x1f600) }
		.emoji_modifier { u32(0x0301) }
		else { cp1 }
	}
	to := match gb2 {
		.emoji_modifier_base { u32(0x1f600) }
		.emoji_modifier { u32(0x0301) }
		else { cp2 }
	}
	return unicode.grapheme_break(from, to, state)
}

fn last_grapheme_byte_length(text string) int {
	return text_input_last_grapheme_byte_length(text)
}

fn grapheme_count(text string) int {
	mut count := 0
	mut offset := 0
	for offset < text.len {
		length := first_grapheme_byte_length(text[offset..])
		if length == 0 {
			break
		}
		count++
		offset += length
	}
	return count
}

pub fn terminal_size() Winsize {
	cols, rows := term.get_terminal_size()
	return Winsize{
		rows: u16(max_int(rows, 1))
		cols: u16(max_int(cols, 1))
	}
}

pub fn begin_session(title string) {
	print('\x1b[?1049h\x1b]2;${title}\x1b\\\x1b[?1002;1003;1004;1006h')
	flush_stdout()
}

pub fn end_session() {
	print('\x1b[?1002;1003;1004;1006;1016l\x1b[?25h\x1b[0m\x1b[?1049l')
	flush_stdout()
}

pub fn query_color_scheme_update_capability() {
	print('\x1b[?2031$p')
	flush_stdout()
}

pub fn query_unicode_capability() {
	print('\x1b[?2027$p')
	flush_stdout()
}

pub fn enable_unicode_mode() {
	print('\x1b[?2027h')
	flush_stdout()
}

pub fn subscribe_to_color_scheme_updates() {
	print('\x1b[?996n\x1b[?2031h')
	flush_stdout()
}

pub fn unsubscribe_from_color_scheme_updates() {
	print('\x1b[?2031l')
	flush_stdout()
}

pub fn clear_screen() string {
	return '\x1b[2J\x1b[H'
}

pub fn position(row int, col int) string {
	return '\x1b[${max_int(row, 0) + 1};${max_int(col, 0) + 1}H'
}

pub fn hide_cursor() string {
	return '\x1b[?25l'
}

pub fn show_cursor(row int, col int) string {
	return '${position(row, col)}\x1b[?25h'
}

pub fn styled(text string, style Style) string {
	mut result := strings.new_builder(text.len + 64)
	result.write_string(foreground_sequence(style.fg))
	result.write_string(background_sequence(style.bg))
	result.write_string(underline_color_sequence(style.ul))
	match style.ul_style {
		.off {}
		.single { result.write_string('\x1b[4m') }
		.double_ { result.write_string('\x1b[4:2m') }
		.curly { result.write_string('\x1b[4:3m') }
		.dotted { result.write_string('\x1b[4:4m') }
		.dashed { result.write_string('\x1b[4:5m') }
	}

	if style.bold {
		result.write_string('\x1b[1m')
	}
	if style.dim {
		result.write_string('\x1b[2m')
	}
	if style.italic {
		result.write_string('\x1b[3m')
	}
	if style.blink {
		result.write_string('\x1b[5m')
	}
	if style.reverse {
		result.write_string('\x1b[7m')
	}
	if style.invisible {
		result.write_string('\x1b[8m')
	}
	if style.strikethrough {
		result.write_string('\x1b[9m')
	}
	result.write_string(text)
	result.write_string('\x1b[m')
	return result.str()
}

fn foreground_sequence(color Color) string {
	return match color {
		ColorDefault {
			''
		}
		ColorIndex {
			if color.index <= 7 {
				'\x1b[3${color.index}m'
			} else if color.index <= 15 {
				'\x1b[9${color.index - 8}m'
			} else {
				'\x1b[38:5:${color.index}m'
			}
		}
		ColorRgb {
			'\x1b[38:2:${color.rgb[0]}:${color.rgb[1]}:${color.rgb[2]}m'
		}
	}
}

fn background_sequence(color Color) string {
	return match color {
		ColorDefault {
			''
		}
		ColorIndex {
			if color.index <= 7 {
				'\x1b[4${color.index}m'
			} else if color.index <= 15 {
				'\x1b[10${color.index - 8}m'
			} else {
				'\x1b[48:5:${color.index}m'
			}
		}
		ColorRgb {
			'\x1b[48:2:${color.rgb[0]}:${color.rgb[1]}:${color.rgb[2]}m'
		}
	}
}

fn underline_color_sequence(color Color) string {
	return match color {
		ColorDefault { '' }
		ColorIndex { '\x1b[58:5:${color.index}m' }
		ColorRgb { '\x1b[58:2:${color.rgb[0]}:${color.rgb[1]}:${color.rgb[2]}m' }
	}
}

pub fn hyperlink(text string, uri string, style Style) string {
	return '\x1b]8;;${uri}\x1b\\${styled(text, style)}\x1b]8;;\x1b\\'
}

pub fn copy_to_system_clipboard(text string) {
	print(clipboard_copy_sequence(text))
	flush_stdout()
}

pub fn clipboard_copy_sequence(text string) string {
	return '\x1b]52;c;${base64.encode_str(text)}\x1b\\'
}

pub fn truncate(text string, width int) string {
	return truncate_with_method(text, width, .wcwidth)
}

// Match Window.print's non-wrapping grapheme traversal for the ANSI adapter.
pub fn truncate_with_method(text string, width int, method GWidthMethod) string {
	if width <= 0 {
		return ''
	}
	mut visible := strings.new_builder(text.len)
	mut offset := 0
	mut col := 0
	for offset < text.len && col < width {
		length := first_grapheme_byte_length(text[offset..])
		if length == 0 {
			break
		}
		grapheme := text[offset..offset + length]
		offset += length
		if grapheme == '\n' {
			break
		}
		w := int(gwidth(grapheme, method))
		if w == 0 {
			continue
		}
		visible.write_string(grapheme)
		col += w
	}
	return visible.str()
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}
