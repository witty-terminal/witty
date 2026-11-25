module terminal

// Kitty graphics protocol command parser and types.
//
// Source: kitty/graphics_command.zig
//
// The Kitty graphics protocol allows terminal applications to display
// images and animations using escape sequences. This module implements
// the parser for the command portion of the protocol.

import simd
import zig_fmt

// ============================================================
// CommandParser
// ============================================================

// CommandParser state for the key-value pair parsing state machine.
enum CommandParserState as u8 {
	// Parsing k/v pairs. The "ignore" variants are in that state
	// but ignore any data because we know they're invalid.
	control_key
	control_key_ignore
	control_value
	control_value_ignore
	// Collecting the data payload blob.
	data
}

// Command parser parses the Kitty graphics protocol escape sequence.
pub struct CommandParser {
mut:
	// This is the list of KV pairs that we're building up.
	kv map[u8]u32
	// This is used as a buffer to store the key/value of a KV pair. The value
	// of a KV pair is at most a 32-bit integer which at most is 10 characters
	// (4294967295), plus one character for the sign bit on signed ints.
	kv_temp     [11]u8
	kv_temp_len u8
	kv_current  u8 // Current kv key
	// This is the list we use to collect the bytes from the data payload.
	// The Kitty Graphics protocol specification seems to imply that the
	// payload content of a single command should never exceed 4096 bytes,
	// but Kitty itself supports larger payloads, so we use an array
	// here instead of a fixed buffer so that we can too.
	data_buf []u8
	// Internal state for parsing.
	state CommandParserState = .control_key
}

// Initialize the parser.
pub fn CommandParser.init() CommandParser {
	return CommandParser{}
}

// Release all parser-owned state. V's garbage collector owns the backing
// allocations, so clearing the containers is the source deinitializer's
// observable operation.
pub fn (mut self CommandParser) deinit() {
	self.kv = map[u8]u32{}
	self.data_buf = []u8{}
	self.kv_temp_len = 0
	self.kv_current = 0
	self.state = .control_key
}

// Parse a complete command string.
pub fn CommandParser.parse_string(data string) !Command {
	mut parser := CommandParser.init()
	for c in data.bytes() {
		parser.feed(c)!
	}
	return parser.complete()!
}

// Feed a single byte to the parser.
//
// The first byte to start parsing should be the byte immediately following
// the "G" in the APC sequence, i.e. "\x1b_G123" the first byte should
// be "1".
pub fn (mut self CommandParser) feed(c u8) ! {
	match self.state {
		.control_key {
			match c {
				// '=' means the key is complete and we're moving to the value.
				`=` {
					if self.kv_temp_len != 1 {
						// All control keys are a single character right now so
						// if we're not a single character just ignore follow-up
						// data.
						self.state = .control_value_ignore
						self.kv_temp_len = 0
					} else {
						self.kv_current = self.kv_temp[0]
						self.kv_temp_len = 0
						self.state = .control_value
					}
				}

				// This can be encountered if we have a sequence with no
				// control data, only payload data (i.e. "\x1b_G;<data>").
				//
				// Kitty treats this as valid so we do as well.
				`;` {
					self.state = .data
				}
				else {
					self.accumulate_value(c, .control_key_ignore)!
				}
			}
		}
		.control_key_ignore {
			match c {
				`=` {
					self.state = .control_value_ignore
				}
				else {}
			}
		}
		.control_value {
			match c {
				`,` { self.finish_value(.control_key)! } // move to next key
				`;` { self.finish_value(.data)! } // move to data
				else { self.accumulate_value(c, .control_value_ignore)! }
			}
		}
		.control_value_ignore {
			match c {
				`,` {
					self.state = .control_key_ignore
				}
				`;` {
					self.state = .data
				}
				else {}
			}
		}
		.data {
			self.data_buf << c
		}
	}
}

// Complete the parsing. This must be called after all the
// bytes have been fed to the parser.
pub fn (mut self CommandParser) complete() !Command {
	match self.state {
		// We can't ever end in the control key state and be valid.
		// This means the command looked something like "a=1,b"
		.control_key, .control_key_ignore {
			return error('InvalidFormat: ended in control key state')
		}

		// Some commands (i.e. placements) end without extra data so
		// we end in the value state. i.e. "a=1,b=2"
		.control_value {
			self.finish_value(.data)!
		}
		.control_value_ignore {}
		// Most commands end in data, i.e. "a=1,b=2;1234"
		.data {}
	}

	// Determine our action, which is always a single character.
	action := if `a` in self.kv {
		v := self.kv[u8(`a`)]
		if v > 255 {
			return error('InvalidFormat: action out of range')
		}
		u8(v)
	} else {
		u8(`t`)
	}

	control := match action {
		`q` {
			Control(ControlQuery{
				transmission: Transmission.parse(self.kv)!
			})
		}
		`t` {
			Control(ControlTransmit{
				transmission: Transmission.parse(self.kv)!
			})
		}
		`T` {
			Control(TransmitAndDisplay{
				transmission: Transmission.parse(self.kv)!
				display:      Display.parse(self.kv)!
			})
		}
		`p` { Control(Display.parse(self.kv)!) }
		`d` { Control(Delete.parse(self.kv)!) }
		`f` { Control(AnimationFrameLoading.parse(self.kv)!) }
		`a` { Control(AnimationControl.parse(self.kv)!) }
		`c` { Control(AnimationFrameComposition.parse(self.kv)!) }
		else {
			return error('InvalidFormat: unknown action ${action}')
		}
	}

	// Determine our quiet value
	quiet := if `q` in self.kv {
		v := self.kv[u8(`q`)]
		match v {
			0 { Quiet.no }
			1 { Quiet.ok }
			2 { Quiet.failures }
			else {
				return error('InvalidFormat: unknown quiet value ${v}')
			}
		}
	} else {
		Quiet.no
	}

	return Command{
		control: control
		quiet:   quiet
		data:    self.decode_data()!
	}
}

// Decodes the payload data from base64 and returns it as a slice.
// This function destroys the contents of data_buf and must only be used after
// all payload bytes have been collected.
fn (mut self CommandParser) decode_data() ![]u8 {
	if self.data_buf.len == 0 {
		return []u8{}
	}

	max_len := simd.max_len(self.data_buf)
	assert max_len <= self.data_buf.len
	mut output := self.data_buf[..max_len]
	decoded := simd.decode(self.data_buf, mut output) or {
		return error('InvalidData: failed to decode base64 payload')
	}
	self.data_buf = decoded
	return self.data_buf
}

fn (mut self CommandParser) accumulate_value(c u8, overflow_state CommandParserState) ! {
	idx := self.kv_temp_len
	self.kv_temp_len += 1
	if self.kv_temp_len > 11 {
		self.state = overflow_state
		self.kv_temp_len = 0
		return
	}
	self.kv_temp[idx] = c
}

fn (mut self CommandParser) finish_value(next_state CommandParserState) ! {
	// We can move states right away, we don't use it.
	self.state = next_state

	// Check for ASCII chars first
	if self.kv_temp_len == 1 {
		c := self.kv_temp[0]
		if c < `0` || c > `9` {
			self.kv[self.kv_current] = u32(c)
			self.kv_temp_len = 0
			return
		}
	}

	// Handle integer fields, parsing signed fields accordingly. We still
	// store the fields as u32 as they can be bitcast back later during
	// building of the higher-level command tree.
	temp_str := self.kv_temp[0..self.kv_temp_len].bytestr()
	v := match self.kv_current {
		`z`, `H`, `V` {
			signed := zig_fmt.parse_int_signed(temp_str, 32, 10) or {
				if err.msg() == 'overflow' {
					return error('Overflow')
				}
				return error('InvalidCharacter')
			}
			// Reinterpret i32 as u32
			signed_i32 := i32(signed)
			unsafe { *(&u32(&signed_i32)) }
		}
		else {
			parsed := zig_fmt.parse_int_unsigned(temp_str, 32, 10) or {
				if err.msg() == 'overflow' {
					return error('Overflow')
				}
				return error('InvalidCharacter')
			}
			u32(parsed)
		}
	}
	self.kv[self.kv_current] = v

	// Clear our temp buffer
	self.kv_temp_len = 0
}

// ============================================================
// Response
// ============================================================

// Represents a possible response to a command.
pub struct Response {
pub mut:
	id           u32
	image_number u32
	placement_id u32
	message      string = 'OK'
}

pub fn (self Response) encode() string {
	// We only encode a result if we have either an id or an image number.
	if self.id == 0 && self.image_number == 0 {
		return ''
	}

	mut result := '\x1b_G'
	mut prior := false

	if self.id > 0 {
		prior = true
		result += 'i=${self.id}'
	}
	if self.image_number > 0 {
		if prior {
			result += ','
		} else {
			prior = true
		}
		result += 'I=${self.image_number}'
	}
	if self.placement_id > 0 {
		if prior {
			result += ','
		} else {
			prior = true
		}
		result += 'p=${self.placement_id}'
	}
	result += ';'
	result += self.message
	result += '\x1b\\'
	return result
}

// Returns true if this response is not an error.
pub fn (self Response) ok() bool {
	return self.message == 'OK'
}

// Empty response
pub fn (self Response) empty() bool {
	return self.id == 0 && self.image_number == 0
}

// ============================================================
// Command
// ============================================================

pub struct Command {
pub mut:
	control Control
	quiet   Quiet = .no
	data    []u8
}

// Take ownership over the data in this command. If the returned value
// has a length of zero, then the data was empty and need not be freed.
pub fn (mut self Command) to_owned_data() []u8 {
	result := self.data
	self.data = []
	return result
}

pub fn (mut self Command) deinit() {
	self.data = []
}

pub enum CommandAction as u8 {
	query                    // q
	transmit                 // t
	transmit_and_display     // T
	display                  // p
	delete_                  // d
	transmit_animation_frame // f
	control_animation        // a
	compose_animation        // c
}

pub enum Quiet as u8 {
	no       // 0
	ok       // 1
	failures // 2
}

pub type Control = ControlQuery
	| ControlTransmit
	| TransmitAndDisplay
	| Display
	| Delete
	| AnimationFrameLoading
	| AnimationControl
	| AnimationFrameComposition

pub struct ControlQuery {
pub:
	transmission Transmission
}

pub struct ControlTransmit {
pub:
	transmission Transmission
}

// Returns the transmission data if it has any.
pub fn (self Command) transmission() ?Transmission {
	return match self.control {
		ControlQuery {
			(self.control as ControlQuery).transmission
		}
		ControlTransmit {
			(self.control as ControlTransmit).transmission
		}
		TransmitAndDisplay {
			(self.control as TransmitAndDisplay).transmission
		}
		else {
			none
		}
	}
}

// Returns the display data if it has any.
pub fn (self Command) display() ?Display {
	return match self.control {
		Display {
			self.control as Display
		}
		TransmitAndDisplay {
			(self.control as TransmitAndDisplay).display
		}
		else {
			none
		}
	}
}

pub struct TransmitAndDisplay {
pub:
	transmission Transmission
	display      Display
}

// ============================================================
// Transmission
// ============================================================

pub struct Transmission {
pub mut:
	format_      TransmissionFormat = .rgba   // f
	medium       TransmissionMedium = .direct // t
	width        u32 // s
	height       u32 // v
	size         u32 // S
	offset       u32 // O
	image_id     u32 // i
	image_number u32 // I
	placement_id u32 // p
	compression  TransmissionCompression = .none_ // o
	more_chunks  bool // m
}

fn (t Transmission) response() Response {
	return Response{
		id:           t.image_id
		image_number: t.image_number
		placement_id: t.placement_id
	}
}

pub enum TransmissionFormat as u8 {
	rgb  // 24
	rgba // 32
	png  // 100
	// The following are not supported directly via the protocol
	// but they are formats that a png may decode to that we
	// support.
	gray_alpha
	gray
}

// Bytes per pixel for this format.
pub fn (self TransmissionFormat) bpp() u8 {
	return match self {
		.gray { 1 }
		.gray_alpha { 2 }
		.rgb { 3 }
		.rgba { 4 }
		.png { 0 }
	}
	// Must be validated before
}

pub enum TransmissionMedium as u8 {
	direct         // d
	file           // f
	temporary_file // t
	shared_memory  // s
}

pub enum TransmissionCompression as u8 {
	none_
	zlib_deflate // z
}

fn Transmission.parse(kv map[u8]u32) !Transmission {
	mut result := Transmission{}

	if `f` in kv {
		v := kv[u8(`f`)]
		result.format_ = match v {
			24 { TransmissionFormat.rgb }
			32 { TransmissionFormat.rgba }
			100 { TransmissionFormat.png }
			else {
				return error('InvalidFormat: unknown transmission format ${v}')
			}
		}
	}

	if `t` in kv {
		v := kv[u8(`t`)]
		if v > 255 {
			return error('InvalidFormat: medium out of range')
		}
		c := u8(v)
		result.medium = match c {
			`d` { TransmissionMedium.direct }
			`f` { TransmissionMedium.file }
			`t` { TransmissionMedium.temporary_file }
			`s` { TransmissionMedium.shared_memory }
			else {
				return error('InvalidFormat: unknown medium ${c}')
			}
		}
	}

	if `s` in kv {
		result.width = kv[u8(`s`)]
	}
	if `v` in kv {
		result.height = kv[u8(`v`)]
	}
	if `S` in kv {
		result.size = kv[u8(`S`)]
	}
	if `O` in kv {
		result.offset = kv[u8(`O`)]
	}
	if `i` in kv {
		result.image_id = kv[u8(`i`)]
	}
	if `I` in kv {
		result.image_number = kv[u8(`I`)]
	}
	if `p` in kv {
		result.placement_id = kv[u8(`p`)]
	}

	if `o` in kv {
		v := kv[u8(`o`)]
		if v > 255 {
			return error('InvalidFormat: compression out of range')
		}
		c := u8(v)
		result.compression = match c {
			`z` { TransmissionCompression.zlib_deflate }
			else {
				return error('InvalidFormat: unknown compression ${c}')
			}
		}
	}

	// If the transmission medium is a local-only medium, ignore the "m"
	// key. The Kitty graphics protocol specification does not explicitly
	// call out this behavior (although the "m" key is only mentioned in
	// connection with remote clients) but that's how it's implemented in
	// Kitty and at least one client (mpv) relies on this behavior when
	// using the shared memory transmission medium.
	//
	// https://sw.kovidgoyal.net/kitty/graphics-protocol/#the-transmission-medium
	// https://github.com/kovidgoyal/kitty/blob/ccc3bee9af794f332b4e9adcd714a649f639c397/kitty/graphics.c#L547-L592
	if result.medium == .direct {
		if `m` in kv {
			v := kv[u8(`m`)]
			result.more_chunks = v > 0
		}
	}

	return result
}

// ============================================================
// Display
// ============================================================

pub struct Display {
pub mut:
	image_id            u32 // i
	image_number        u32 // I
	placement_id        u32 // p
	x                   u32 // x
	y                   u32 // y
	width               u32 // w
	height              u32 // h
	x_offset            u32 // X
	y_offset            u32 // Y
	columns             u32 // c
	rows                u32 // r
	cursor_movement     CursorMovement = .after // C
	virtual_placement   bool // U
	parent_id           u32  // P
	parent_placement_id u32  // Q
	horizontal_offset   i32  // H
	vertical_offset     i32  // V
	z                   i32  // z
}

pub enum CursorMovement as u8 {
	after // 0
	none_ // 1
}

fn Display.parse(kv map[u8]u32) !Display {
	mut result := Display{}

	if `i` in kv {
		result.image_id = kv[u8(`i`)]
	}
	if `I` in kv {
		result.image_number = kv[u8(`I`)]
	}
	if `p` in kv {
		result.placement_id = kv[u8(`p`)]
	}
	if `x` in kv {
		result.x = kv[u8(`x`)]
	}
	if `y` in kv {
		result.y = kv[u8(`y`)]
	}
	if `w` in kv {
		result.width = kv[u8(`w`)]
	}
	if `h` in kv {
		result.height = kv[u8(`h`)]
	}
	if `X` in kv {
		result.x_offset = kv[u8(`X`)]
	}
	if `Y` in kv {
		result.y_offset = kv[u8(`Y`)]
	}
	if `c` in kv {
		result.columns = kv[u8(`c`)]
	}
	if `r` in kv {
		result.rows = kv[u8(`r`)]
	}
	if `C` in kv {
		v := kv[u8(`C`)]
		result.cursor_movement = match v {
			0 { CursorMovement.after }
			1 { CursorMovement.none_ }
			else {
				return error('InvalidFormat: unknown cursor movement ${v}')
			}
		}
	}
	if `U` in kv {
		v := kv[u8(`U`)]
		result.virtual_placement = match v {
			0 { false }
			1 { true }
			else {
				return error('InvalidFormat: unknown virtual placement ${v}')
			}
		}
	}
	if `z` in kv {
		v := kv[u8(`z`)]
		// We can bitcast here because of how we parse it earlier.
		result.z = unsafe { *(&i32(&v)) }
	}
	if `P` in kv {
		result.parent_id = kv[u8(`P`)]
	}
	if `Q` in kv {
		result.parent_placement_id = kv[u8(`Q`)]
	}
	if `H` in kv {
		v := kv[u8(`H`)]
		// We can bitcast here because of how we parse it earlier.
		result.horizontal_offset = unsafe { *(&i32(&v)) }
	}
	if `V` in kv {
		v := kv[u8(`V`)]
		// We can bitcast here because of how we parse it earlier.
		result.vertical_offset = unsafe { *(&i32(&v)) }
	}

	return result
}

// ============================================================
// AnimationFrameLoading
// ============================================================

pub struct AnimationFrameLoading {
pub mut:
	x                u32 // x
	y                u32 // y
	create_frame     u32 // c
	edit_frame       u32 // r
	gap_ms           u32 // z
	composition_mode CompositionMode = .alpha_blend // X
	background       AnimBackground // Y
}

pub struct AnimBackground {
	value u32
}

pub fn AnimBackground.from_int(value u32) AnimBackground {
	return AnimBackground{ value: value }
}

pub fn (background AnimBackground) r() u8 {
	return u8(background.value)
}

pub fn (background AnimBackground) g() u8 {
	return u8(background.value >> 8)
}

pub fn (background AnimBackground) b() u8 {
	return u8(background.value >> 16)
}

pub fn (background AnimBackground) a() u8 {
	return u8(background.value >> 24)
}

pub fn (background AnimBackground) int() u32 {
	return background.value
}

fn AnimationFrameLoading.parse(kv map[u8]u32) !AnimationFrameLoading {
	mut result := AnimationFrameLoading{}

	if `x` in kv {
		result.x = kv[u8(`x`)]
	}
	if `y` in kv {
		result.y = kv[u8(`y`)]
	}
	if `c` in kv {
		result.create_frame = kv[u8(`c`)]
	}
	if `r` in kv {
		result.edit_frame = kv[u8(`r`)]
	}
	if `z` in kv {
		result.gap_ms = kv[u8(`z`)]
	}
	if `X` in kv {
		v := kv[u8(`X`)]
		result.composition_mode = match v {
			0 { CompositionMode.alpha_blend }
			1 { CompositionMode.overwrite }
			else {
				return error('InvalidFormat: unknown composition mode ${v}')
			}
		}
	}
	if `Y` in kv {
		result.background = AnimBackground.from_int(kv[u8(`Y`)])
	}

	return result
}

// ============================================================
// AnimationFrameComposition
// ============================================================

pub struct AnimationFrameComposition {
pub mut:
	frame            u32 // c
	edit_frame       u32 // r
	x                u32 // x
	y                u32 // y
	width            u32 // w
	height           u32 // h
	left_edge        u32 // X
	top_edge         u32 // Y
	composition_mode CompositionMode = .alpha_blend // C
}

fn AnimationFrameComposition.parse(kv map[u8]u32) !AnimationFrameComposition {
	mut result := AnimationFrameComposition{}

	if `c` in kv {
		result.frame = kv[u8(`c`)]
	}
	if `r` in kv {
		result.edit_frame = kv[u8(`r`)]
	}
	if `x` in kv {
		result.x = kv[u8(`x`)]
	}
	if `y` in kv {
		result.y = kv[u8(`y`)]
	}
	if `w` in kv {
		result.width = kv[u8(`w`)]
	}
	if `h` in kv {
		result.height = kv[u8(`h`)]
	}
	if `X` in kv {
		result.left_edge = kv[u8(`X`)]
	}
	if `Y` in kv {
		result.top_edge = kv[u8(`Y`)]
	}
	if `C` in kv {
		v := kv[u8(`C`)]
		result.composition_mode = match v {
			0 { CompositionMode.alpha_blend }
			1 { CompositionMode.overwrite }
			else {
				return error('InvalidFormat: unknown composition mode ${v}')
			}
		}
	}

	return result
}

// ============================================================
// AnimationControl
// ============================================================

pub struct AnimationControl {
pub mut:
	action        AnimationAction = .invalid // s
	frame         u32 // r
	gap_ms        u32 // z
	current_frame u32 // c
	loops         u32 // v
}

pub enum AnimationAction as u8 {
	invalid  // 0
	stop     // 1
	run_wait // 2
	run      // 3
}

fn AnimationControl.parse(kv map[u8]u32) !AnimationControl {
	mut result := AnimationControl{}

	if `s` in kv {
		v := kv[u8(`s`)]
		result.action = match v {
			0 { AnimationAction.invalid }
			1 { AnimationAction.stop }
			2 { AnimationAction.run_wait }
			3 { AnimationAction.run }
			else {
				return error('InvalidFormat: unknown animation action ${v}')
			}
		}
	}
	if `r` in kv {
		result.frame = kv[u8(`r`)]
	}
	if `z` in kv {
		result.gap_ms = kv[u8(`z`)]
	}
	if `c` in kv {
		result.current_frame = kv[u8(`c`)]
	}
	if `v` in kv {
		result.loops = kv[u8(`v`)]
	}

	return result
}

// ============================================================
// Delete
// ============================================================

pub struct DeleteAll {
pub:
	delete bool // uppercase = delete from disk too
}

pub struct DeleteById {
pub:
	delete       bool // uppercase
	image_id     u32  // i
	placement_id u32  // p
}

pub struct DeleteByNewest {
pub:
	delete       bool // uppercase
	image_number u32  // I
	placement_id u32  // p
}

pub struct DeleteIntersectCell {
pub:
	delete bool // uppercase
	x      u32  // x
	y      u32  // y
}

pub struct DeleteIntersectCellZ {
pub:
	delete bool // uppercase
	x      u32  // x
	y      u32  // y
	z      i32  // z
}

pub struct DeleteRange {
pub:
	delete bool // uppercase
	first  u32  // x
	last   u32  // y
}

pub struct DeleteColumn {
pub:
	delete bool // uppercase
	x      u32  // x
}

pub struct DeleteRow {
pub:
	delete bool // uppercase
	y      u32  // y
}

pub struct DeleteZ {
pub:
	delete bool // uppercase
	z      i32  // z
}

pub struct DeleteIntersectCursor {
pub:
	delete bool // uppercase
}

pub struct DeleteAnimationFrames {
pub:
	delete bool // uppercase
}

pub type Delete = DeleteAll
	| DeleteById
	| DeleteByNewest
	| DeleteIntersectCursor
	| DeleteAnimationFrames
	| DeleteIntersectCell
	| DeleteIntersectCellZ
	| DeleteRange
	| DeleteColumn
	| DeleteRow
	| DeleteZ

fn Delete.parse(kv map[u8]u32) !Delete {
	what := if `d` in kv {
		v := kv[u8(`d`)]
		if v > 255 {
			return error('InvalidFormat: delete kind out of range')
		}
		u8(v)
	} else {
		u8(`a`)
	}

	return match what {
		`a`, `A` {
			DeleteAll{ delete: what == `A` }
		}
		`i`, `I` {
			mut r := DeleteById{ delete: what == `I` }
			if `i` in kv {
				r = DeleteById{
					...r
					image_id: kv[u8(`i`)]
				}
			}
			if `p` in kv {
				r = DeleteById{
					...r
					placement_id: kv[u8(`p`)]
				}
			}
			r
		}
		`n`, `N` {
			mut r := DeleteByNewest{ delete: what == `N` }
			if `I` in kv {
				r = DeleteByNewest{
					...r
					image_number: kv[u8(`I`)]
				}
			}
			if `p` in kv {
				r = DeleteByNewest{
					...r
					placement_id: kv[u8(`p`)]
				}
			}
			r
		}
		`c`, `C` {
			DeleteIntersectCursor{ delete: what == `C` }
		}
		`f`, `F` {
			DeleteAnimationFrames{ delete: what == `F` }
		}
		`p`, `P` {
			mut r := DeleteIntersectCell{ delete: what == `P` }
			if `x` in kv {
				r = DeleteIntersectCell{
					...r
					x: kv[u8(`x`)]
				}
			}
			if `y` in kv {
				r = DeleteIntersectCell{
					...r
					y: kv[u8(`y`)]
				}
			}
			r
		}
		`q`, `Q` {
			mut r := DeleteIntersectCellZ{ delete: what == `Q` }
			if `x` in kv {
				r = DeleteIntersectCellZ{
					...r
					x: kv[u8(`x`)]
				}
			}
			if `y` in kv {
				r = DeleteIntersectCellZ{
					...r
					y: kv[u8(`y`)]
				}
			}
			if `z` in kv {
				v := kv[u8(`z`)]
				r = DeleteIntersectCellZ{
					...r
					z: unsafe { *(&i32(&v)) }
				}
			}
			r
		}
		`r`, `R` {
			DeleteRange{
				delete: what == `R`
				first:  kv[u8(`x`)]
				last:   kv[u8(`y`)]
			}
		}
		`x`, `X` {
			mut r := DeleteColumn{ delete: what == `X` }
			if `x` in kv {
				r = DeleteColumn{
					...r
					x: kv[u8(`x`)]
				}
			}
			r
		}
		`y`, `Y` {
			mut r := DeleteRow{ delete: what == `Y` }
			if `y` in kv {
				r = DeleteRow{
					...r
					y: kv[u8(`y`)]
				}
			}
			r
		}
		`z`, `Z` {
			mut r := DeleteZ{ delete: what == `Z` }
			if `z` in kv {
				v := kv[u8(`z`)]
				r = DeleteZ{
					...r
					z: unsafe { *(&i32(&v)) }
				}
			}
			r
		}
		else {
			return error('InvalidFormat: unknown delete kind ${what}')
		}
	}
}

// ============================================================
// CompositionMode
// ============================================================

pub enum CompositionMode as u8 {
	alpha_blend // 0
	overwrite   // 1
}
