module terminal

import encoding.utf8.validate
import osc
import simd
import lib_allocator

// --- Original Ghostty Comments Start: src/terminal/stream.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/terminal/stream.zig
//
// Flip this to true when you want verbose debug output for
// debugging terminal stream issues. In addition to louder
// output this will also disable the SIMD optimizations in
// order to make it easier to see every byte. So if you're
// debugging an issue in the SIMD code then you'll need to
// do something else.
// The possible actions that can be emitted by the Stream
// function for handling.
// C ABI functions.
// TODO: Before shipping an ABI-compatible libwitty, verify this.
// This was just arbitrarily chosen for now.
// Field types
// The value of the cursor movement. Depending on the tag of this
// union this may be an absolute value or it may be a relative
// value. For example, `cursor_up` is relative, but `cursor_row`
// is absolute.
// Returns a type that can process a stream of tty control characters.
// This will call the `vt` function on type T with the following signature:
//
//   fn(comptime action: Action.Key, value: Action.Value(action)) !void
//
// The handler type T can choose to react to whatever actions it cares
// about in its pursuit of implementing a terminal emulator or other
// functionality.
//
// The Handler type must also have a `deinit` function.
//
// The "comptime" key is on purpose (vs. a standard Zig tagged union)
// because it allows the compiler to optimize away unimplemented actions.
// e.g. you don't need to pay a conditional branching cost on every single
// action because the Zig compiler codegens separate code paths for every
// single action at comptime.
// Initialize an allocation-free stream. This will preallocate various
// sizes as necessary and anything over that will be dropped. If you
// want to support more dynamic behavior use initAlloc instead.
//
// As a concrete example of something that requires heap allocation,
// consider OSC 52 (clipboard operations) which can be arbitrarily
// large.
//
// If you want to limit allocation size, use an allocator with
// a size limit with initAlloc.
//
// This takes ownership of the handler and will call deinit
// when the stream is deinitialized.
// Initialize the stream that supports heap allocation as necessary.
// Process a string of characters.
// Disable SIMD optimizations if build requests it or if our
// manual debug mode is on.
// This is the maximum number of codepoints we can decode
// at one time for this function call. This is somewhat arbitrary
// so if someone can demonstrate a better number then we can switch.
// Split the input into chunks that fit into cp_buf.
// If the scalar UTF-8 decoder was in the middle of processing
// a code sequence, we continue until it's not.
// If we're not in the ground state then we process until
// we are. This can happen if the last chunk of input put us
// in the middle of a control sequence.
// If we're in the ground state then we can use SIMD to process
// input until we see an ESC (0x1B), since all other characters
// up to that point are just UTF-8.
// Consume the bytes we just processed.
// If our offset is NOT an escape then we must have a
// partial UTF-8 sequence. In that case, we pass it off
// to the scalar parser.
// Process control sequences until we run out.
// Parses back-to-back escape sequences until none are left.
// Returns the number of bytes consumed from the provided input.
//
// Expects input to start with 0x1B, use consumeUntilGround first
// if the stream may be in the middle of an escape sequence.
// Parses escape sequences until the parser reaches the ground state.
// Returns the number of bytes consumed from the provided input.
// Like nextSlice but takes one byte and is necessarily a scalar
// operation that can't use SIMD. Prefer nextSlice if you can and
// try to get multiple bytes at once.
// The scalar path can be responsible for decoding UTF-8.
// Process the next byte and print as necessary.
//
// This assumes we're in the UTF-8 decoding state. If we may not
// be in the UTF-8 decoding state call nextSlice or next.
// We optimize for the scenario where the text being
// printed in the terminal ISN'T full of ill-formed
// UTF-8 sequences.
// It should be impossible for the decoder
// to not consume the byte twice in a row.
// To be called whenever the utf-8 decoder produces a codepoint.
//
// This function is abstracted this way to handle the case where
// the decoder emits a 0x1B after rejecting an ill-formed sequence.
// We need to increase the eval branch limit because a lot of
// tests end up running almost completely at comptime due to
// a chain of inline functions.
// C0 control
// ESC
// Process the next character and call any callbacks if necessary.
//
// This assumes that we're not in the UTF-8 decoding state. If
// we may be in the UTF-8 decoding state call nextSlice or next.
// Fast path for CSI entry.
// Fast path for CSI params.
// csi_param is the most common parser state
// other than ground by a fairly wide margin.
//
// ref: https://github.com/qwerasd205/asciinema-stats
// A C0 escape (yes, this is valid):
// We ignore C0 escapes > 0xF since execute
// doesn't have processing for them anyway:
// We don't currently have any handling for
// 0x18 or 0x1A, but they should still move
// the parser state to ground.
// A parameter digit:
// The parser's CSI param action uses param_acc_idx
// to decide if there's a final param that needs to
// be consumed or not, but it doesn't matter really
// what it is as long as it's not 0.
// A parameter separator:
// Explicitly ignored:
// Defer to the state machine to
// handle any other characters:
// We explicitly inline this call here for performance reasons.
//
// We do this rather than mark Parser.next as inline because doing
// that causes weird behavior in some tests- I'm not sure if they
// miscompile or it's just very counter-intuitive comptime stuff,
// but regardless, this is the easy solution.
// A handler can expose this to get the raw action before
// it is further parsed. If this returns `true` then we skip
// processing ourselves.
// Always skip erroneous actions because we can't
// be sure...
// If the character is > 0x7F, it's a C1 (8-bit) control,
// which is strictly equivalent to `ESC` plus `c - 0x40`.
// We ignore SOH/STX: https://github.com/microsoft/terminal/issues/10786
// The branch hints here are based on real world data
// which indicates that the most common CSI finals are:
//
// 1. m
// 2. H
// 3. K
// 4. A
// 5. C
// 6. X
// 7. l
// 8. h
// 9. r
//
// Together, these 9 finals make up about 96% of all
// CSI sequences encountered in real world scenarios.
//
// Additionally, within the prongs, unlikely branch
// hints have been added to branches that deal with
// invalid sequences/commands, this is in order to
// optimize for the happy path where we're getting
// valid data from the program we're running.
//
// ref: https://github.com/qwerasd205/asciinema-stats
// CUU - Cursor Up
// CUD - Cursor Down
// CUF - Cursor Right
// CUB - Cursor Left
// CNL - Cursor Next Line
// CPL - Cursor Previous Line
// HPA - Cursor Horizontal Position Absolute
// TODO: test
// CUP - Set Cursor Position.
// TODO: test
// CHT - Cursor Horizontal Tabulation
// Erase Display
// Erase Line
// IL - Insert Lines
// TODO: test
// DL - Delete Lines
// TODO: test
// Delete Character (DCH)
// Scroll Up (SD)
// Scroll Down (SD)
// Cursor Tabulation Control
// Erase Characters (ECH)
// CHT - Cursor Horizontal Tabulation Back
// HPR - Cursor Horizontal Position Relative
// Repeat Previous Char (REP)
// c - Device Attributes (DA1)
// VPA - Cursor Vertical Position Absolute
// VPR - Cursor Vertical Position Relative
// TBC - Tab Clear
// TODO: test
// SM - Set Mode
// RM - Reset Mode
// SGR - Select Graphic Rendition
// This is the most common case.
// log.info("parse SGR params={any}", .{input.params});
// log.info("SGR attribute: {}", .{attr});
// Reset
// We don't support any of the subparams yet for these.
// We only support the numeric form.
// Nothing, but I wanted a place to put this comment:
// there are others forms of CSI m that have intermediates.
// `vim --clean` uses `CSI ? 4 m` and I don't know what
// that means.
// TODO: test
// Handle deviceStatusReport first
// Handle other forms of CSI n
// This isn't strictly correct. CSI > n has parameters that
// control what exactly is being disabled. However, we
// only support reverting back to modify other keys in
// numeric except format.
// DECRQM - Request Mode
// DECSCUSR - Select Cursor Style
// TODO: test
// DECSCA
// XTVERSION
// DECSTBM - Set Top and Bottom Margins
// Restore Mode
// DECSLRM
// CSI S is ambiguous with zero params so we defer
// to our handler to do the proper logic. If mode 69
// is set, then we should invoke DECSLRM, otherwise
// we should invoke SC.
// XTSHIFTESCAPE
// XTWINOPS
// report the text area size in pixels
// report cell size in pixels
// report screen size in characters
// report window title
// we only support window title
// push/pop title
// Kitty keyboard protocol
// ICH - Insert Blanks
// DECSASD - Select Active Status Display
// Verify we're getting a DECSASD command
// The branch hints here are based on real world data
// which indicates that the most common OSC commands are:
//
// 1. hyperlink_end
// 2. change_window_title
// 3. change_window_icon
// 4. hyperlink_start
// 5. report_pwd
// 6. color_operation
// 7. semantic_prompt
//
// Together, these 7 commands make up about 96% of all
// OSC commands encountered in real world scenarios.
//
// Additionally, within the prongs, unlikely branch
// hints have been added to branches that deal with
// invalid sequences/commands, this is in order to
// optimize for the happy path where we're getting
// valid data from the program we're running.
//
// ref: https://github.com/qwerasd205/asciinema-stats
// This is an invalid internal state, not an invalid OSC
// string being parsed. We shouldn't see this.
// TODO: support slots '-', '.', '/'
// The branch hints here are based on real world data
// which indicates that the most common ESC finals are:
//
// 1. B
// 2. \
// 3. 0
// 4. M
// 5. 8
// 6. 7
// 7. >
// 8. =
//
// Together, these 8 finals make up nearly 99% of all
// ESC sequences encountered in real world scenarios.
//
// Additionally, within the prongs, unlikely branch
// hints have been added to branches that deal with
// invalid sequences/commands, this is in order to
// optimize for the happy path where we're getting
// valid data from the program we're running.
//
// ref: https://github.com/qwerasd205/asciinema-stats
// Charsets
// DECSC - Save Cursor
// DECRC - Restore Cursor
// DECALN - Fill Screen with E
// IND - Index
// NEL - Next Line
// HTS - Horizontal Tab Set
// RI - Reverse Index
// SS2 - Single Shift 2
// SS3 - Single Shift 3
// SPA - Start of Guarded Area
// EPA - End of Guarded Area
// DECID
// RIS - Full Reset
// LS2 - Locking Shift 2
// LS3 - Locking Shift 3
// LS1R - Locking Shift 1 Right
// LS2R - Locking Shift 2 Right
// LS3R - Locking Shift 3 Right
// Set application keypad mode
// Reset application keypad mode
// Sets ST (string terminator). We don't have to do anything
// because our parser always accepts ST.
// Forces the C type to be reified when the target is C, ensuring
// all our types are C ABI compatible.
// Invalid and ignored by the handler
// Invalid and ignored by the handler
// Invalid and ignored by the handler
// Invalid and ignored by the handler
// Invalid and ignored by the handler
// Kakoune-style SGR with underline color as 17th parameter
// This tests the fix where param 17 was being dropped
//
// --- Original Ghostty Comments End: src/terminal/stream.zig

// ============================================================
// Action types
// ============================================================

// The possible actions that can be emitted by the Stream function for
// handling: the key of the source's Action union.
pub enum ActionKey as i32 {
	print
	print_repeat
	bell
	backspace
	horizontal_tab
	horizontal_tab_back
	linefeed
	carriage_return
	enquiry
	invoke_charset
	cursor_up
	cursor_down
	cursor_left
	cursor_right
	cursor_col
	cursor_row
	cursor_col_relative
	cursor_row_relative
	cursor_pos
	cursor_style
	erase_display_below
	erase_display_above
	erase_display_complete
	erase_display_scrollback
	erase_display_scroll_complete
	erase_line_right
	erase_line_left
	erase_line_complete
	erase_line_right_unless_pending_wrap
	delete_chars
	erase_chars
	insert_lines
	insert_blanks
	delete_lines
	scroll_up
	scroll_down
	tab_clear_current
	tab_clear_all
	tab_set
	tab_reset
	index
	next_line
	reverse_index
	full_reset
	set_mode
	reset_mode
	save_mode
	restore_mode
	request_mode
	request_mode_unknown
	top_and_bottom_margin
	left_and_right_margin
	left_and_right_margin_ambiguous
	save_cursor
	restore_cursor
	modify_key_format
	mouse_shift_capture
	protected_mode_off
	protected_mode_iso
	protected_mode_dec
	size_report
	title_push
	title_pop
	xtversion
	device_attributes
	device_status
	kitty_keyboard_query
	kitty_keyboard_push
	kitty_keyboard_pop
	kitty_keyboard_set
	kitty_keyboard_set_or
	kitty_keyboard_set_not
	dcs_hook
	dcs_put
	dcs_unhook
	apc_start
	apc_end
	apc_put
	end_hyperlink
	active_status_display
	decaln
	window_title
	report_pwd
	show_desktop_notification
	progress_report
	start_hyperlink
	clipboard_contents
	mouse_shape
	configure_charset
	set_attribute
	kitty_color_report
	color_operation
	semantic_prompt
}

// The value of an action whose union field is `void`.
pub struct ActionVoid {}

// Field types. These are the source's `Action.X` types; V has no nested
// type namespaces, so they carry an `Action` prefix.
pub struct ActionPrint {
pub:
	cp u32
}

pub struct ActionInvokeCharset {
pub:
	bank    ActiveSlot
	charset CharsetSlot
	locking bool
}

pub struct ActionCursorMovement {
pub:
	// The value of the cursor movement. Depending on the tag of this
	// union this may be an absolute value or it may be a relative
	// value. For example, `cursor_up` is relative, but `cursor_row`
	// is absolute.
	value u16
}

pub struct ActionCursorPos {
pub:
	row u16
	col u16
}

pub struct ActionDeviceStatus {
pub:
	request DeviceStatusRequest
}

pub struct ActionMode {
pub:
	mode Mode
}

pub struct ActionRawMode {
pub:
	mode u16
	ansi bool
}

pub struct ActionMargin {
pub:
	top_left     u16
	bottom_right u16
}

pub struct ActionKittyKeyboardFlags {
pub:
	flags KeyFlags
}

pub struct ActionWindowTitle {
pub:
	title string
}

pub struct ActionReportPwd {
pub:
	url string
}

pub struct ActionShowDesktopNotification {
pub:
	title string
	body  string
}

pub struct ActionStartHyperlink {
pub:
	uri string
	id  ?string
}

pub struct ActionClipboardContents {
pub:
	kind u8
	data string
}

pub struct ActionConfigureCharset {
pub:
	slot    CharsetSlot
	charset Charset
}

pub struct ActionColorOperation {
pub:
	op         osc.ColorOperation
	requests   lib_allocator.SegmentedList[osc.ColorRequest]
	terminator osc.Terminator
}

// The value for an action: the payload type of the matching Action union
// field. `ActionVoid` stands in for `void`.
pub type ActionValue = ActionClipboardContents
	| ActionColorOperation
	| ActionConfigureCharset
	| ActionCursorMovement
	| ActionCursorPos
	| ActionDeviceStatus
	| ActionInvokeCharset
	| ActionKittyKeyboardFlags
	| ActionMargin
	| ActionMode
	| ActionPrint
	| ActionRawMode
	| ActionReportPwd
	| ActionShowDesktopNotification
	| ActionStartHyperlink
	| ActionVoid
	| ActionWindowTitle
	| AnsiCursorStyle
	| DCSAction
	| DeviceAttributeReq
	| ModifyKeyFormat
	| MouseShape
	| SgrAttribute
	| SizeReportStyle
	| StatusDisplay
	| bool
	| osc.KittyColorOSC
	| osc.ProgressReport
	| osc.SemanticPrompt
	| u16
	| u8
	| uint

// The possible actions that can be emitted by the Stream function for
// handling: the source's Action union, as its key and that key's value.
pub struct Action {
pub:
	key   ActionKey
	value ActionValue = ActionVoid{}
}

// ============================================================
// Stream
// ============================================================

// Returns a type that can process a stream of tty control characters.
// This will call the `vt` function on type H with the following signature:
//
//   fn (mut self H) vt(action ActionKey, value ActionValue) !
//
// The handler type H can choose to react to whatever actions it cares
// about in its pursuit of implementing a terminal emulator or other
// functionality.
//
// The Handler type must also have a `deinit` function.
//
// The source dispatches on a comptime key; V has no dependent comptime
// parameters, so the key is a runtime enum and the value a sum type.
pub struct Stream[H] {
pub mut:
	handler     H
	parser      Parser
	utf8decoder UTF8Decoder
}

// Initialize an allocation-free stream. This will preallocate various
// sizes as necessary and anything over that will be dropped. If you
// want to support more dynamic behavior use init_alloc instead.
//
// As a concrete example of something that requires heap allocation,
// consider OSC 52 (clipboard operations) which can be arbitrarily
// large.
//
// This takes ownership of the handler and will call deinit
// when the stream is deinitialized.
pub fn Stream.init[H](h H) Stream[H] {
	return Stream[H]{
		handler: h
		parser:  Parser.init()
	}
}

// Initialize the stream that supports heap allocation as necessary. V
// manages the payload storage itself, while the non-null token preserves
// OSC capability selection in the translated parser.
pub fn Stream.init_alloc[H](allocator voidptr, h H) Stream[H] {
	// The source is `var self: Self = .init(h)` followed by the allocator
	// assignment. Calling Stream.init[H] from here makes this V compiler mix
	// up the instantiations of H, so the init body is inlined instead.
	mut parser := Parser.init()
	parser.osc_parser = osc.Parser.init(allocator)
	return Stream[H]{
		handler: h
		parser:  parser
	}
}

pub fn (mut self Stream[H]) deinit() {
	self.parser.deinit()
	self.handler.deinit()
}

// Process a string of characters.
pub fn (mut self Stream[H]) next_slice(input []u8) ! {
	// This is the maximum number of codepoints we can decode
	// at one time for this function call. This is somewhat arbitrary
	// so if someone can demonstrate a better number then we can switch.
	mut cp_buf := []u32{len: 4096}

	// Split the input into chunks that fit into cp_buf.
	mut i := uint(0)
	for {
		len := if uint(cp_buf.len) < uint(input.len) - i {
			uint(cp_buf.len)
		} else {
			uint(input.len) - i
		}
		self.next_slice_capped(input[i..i + len], mut cp_buf)!
		i += len
		if i >= uint(input.len) {
			break
		}
	}
}

fn (mut self Stream[H]) next_slice_capped(input []u8, mut cp_buf []u32) ! {
	assert input.len <= cp_buf.len

	mut offset := uint(0)

	// If the scalar UTF-8 decoder was in the middle of processing
	// a code sequence, we continue until it's not.
	for self.utf8decoder.state != 0 {
		if offset >= uint(input.len) {
			return
		}
		self.next_utf8(input[offset])!
		offset += 1
	}
	if offset >= uint(input.len) {
		return
	}

	// If we're not in the ground state then we process until
	// we are. This can happen if the last chunk of input put us
	// in the middle of a control sequence.
	offset += self.consume_until_ground(input[offset..])!
	if offset >= uint(input.len) {
		return
	}
	offset += self.consume_all_escapes(input[offset..])!

	// If we're in the ground state then we can use SIMD to process
	// input until we see an ESC (0x1B), since all other characters
	// up to that point are just UTF-8.
	for self.parser.state == .ground && offset < uint(input.len) {
		res := simd.utf8_decode_until_control_seq(input[offset..], mut cp_buf)
		for cp in cp_buf[..res.decoded] {
			if cp <= 0xF {
				self.execute(u8(cp))!
			} else {
				self.print(cp)!
			}
		}
		// Consume the bytes we just processed.
		offset += res.consumed

		if offset >= uint(input.len) {
			return
		}

		// If our offset is NOT an escape then we must have a
		// partial UTF-8 sequence. In that case, we pass it off
		// to the scalar parser.
		if input[offset] != 0x1B {
			rem := input[offset..]
			for c in rem {
				self.next_utf8(c)!
			}
			return
		}

		// Process control sequences until we run out.
		offset += self.consume_all_escapes(input[offset..])!
	}
}

// Parses back-to-back escape sequences until none are left.
// Returns the number of bytes consumed from the provided input.
//
// Expects input to start with 0x1B, use consume_until_ground first
// if the stream may be in the middle of an escape sequence.
fn (mut self Stream[H]) consume_all_escapes(input []u8) !uint {
	mut offset := uint(0)
	for input[offset] == 0x1B {
		self.parser.state = .escape
		self.parser.clear()
		offset += 1
		offset += self.consume_until_ground(input[offset..])!
		if offset >= uint(input.len) {
			return uint(input.len)
		}
	}
	return offset
}

// Parses escape sequences until the parser reaches the ground state.
// Returns the number of bytes consumed from the provided input.
fn (mut self Stream[H]) consume_until_ground(input []u8) !uint {
	mut offset := uint(0)
	for self.parser.state != .ground {
		if offset >= uint(input.len) {
			return uint(input.len)
		}
		self.next_non_utf8(input[offset])!
		offset += 1
	}
	return offset
}

// Like next_slice but takes one byte and is necessarily a scalar
// operation that can't use SIMD. Prefer next_slice if you can and
// try to get multiple bytes at once.
pub fn (mut self Stream[H]) next(c u8) ! {
	// The scalar path can be responsible for decoding UTF-8.
	if self.parser.state == .ground {
		self.next_utf8(c)!
		return
	}

	self.next_non_utf8(c)!
}

// Process the next byte and print as necessary.
//
// This assumes we're in the UTF-8 decoding state. If we may not
// be in the UTF-8 decoding state call next_slice or next.
fn (mut self Stream[H]) next_utf8(c u8) ! {
	at_ground := self.parser.state == .ground
	assert at_ground

	res := self.utf8decoder.next(c)
	consumed := res.consumed
	if codepoint := res.codepoint {
		self.handle_codepoint(codepoint)!
	}
	if !consumed {
		// We optimize for the scenario where the text being
		// printed in the terminal ISN'T full of ill-formed
		// UTF-8 sequences.
		retry := self.utf8decoder.next(c)
		// It should be impossible for the decoder
		// to not consume the byte twice in a row.
		assert retry.consumed == true
		if codepoint := retry.codepoint {
			self.handle_codepoint(codepoint)!
		}
	}
}

// To be called whenever the utf-8 decoder produces a codepoint.
//
// This function is abstracted this way to handle the case where
// the decoder emits a 0x1B after rejecting an ill-formed sequence.
fn (mut self Stream[H]) handle_codepoint(c u32) ! {
	// C0 control
	if c <= 0xF {
		self.execute(u8(c))!
		return
	}
	// ESC
	if c == 0x1B {
		self.parser.state = .escape
		self.parser.clear()
		return
	}
	self.print(c)!
}

// Process the next character and call any callbacks if necessary.
//
// This assumes that we're not in the UTF-8 decoding state. If
// we may be in the UTF-8 decoding state call next_slice or next.
fn (mut self Stream[H]) next_non_utf8(c u8) ! {
	at_ground := self.parser.state == .ground
	assert !at_ground

	// Fast path for CSI entry.
	if self.parser.state == .escape && c == u8(`[`) {
		self.parser.state = .csi_entry
		return
	}
	// Fast path for CSI params.
	if self.parser.state == .csi_param {
		// csi_param is the most common parser state
		// other than ground by a fairly wide margin.
		//
		// ref: https://github.com/qwerasd205/asciinema-stats
		mut handled := true
		match c {
			// A C0 escape (yes, this is valid):
			0x00...0x0F {
				self.execute(c)!
			}
			// We ignore C0 escapes > 0xF since execute
			// doesn't have processing for them anyway:
			0x10...0x17, 0x19, 0x1C...0x1F {}
			// We don't currently have any handling for
			// 0x18 or 0x1A, but they should still move
			// the parser state to ground.
			0x18, 0x1A {
				self.parser.state = .ground
			}
			// A parameter digit:
			`0`...`9` {
				if self.parser.params_idx < max_params {
					v := u32(self.parser.param_acc) * 10 + u32(c - u8(`0`))
					self.parser.param_acc = if v > 0xFFFF { u16(0xFFFF) } else { u16(v) }
					// The parser's CSI param action uses param_acc_idx
					// to decide if there's a final param that needs to
					// be consumed or not, but it doesn't matter really
					// what it is as long as it's not 0.
					self.parser.param_acc_idx |= 1
				}
			}
			// A parameter separator:
			`:`, `;` {
				if self.parser.params_idx < max_params {
					self.parser.params[self.parser.params_idx] = self.parser.param_acc
					if c == u8(`:`) {
						self.parser.params_sep.set(uint(self.parser.params_idx))
					}
					self.parser.params_idx += 1

					self.parser.param_acc = 0
					self.parser.param_acc_idx = 0
				}
			}
			// Explicitly ignored:
			0x7F {}
			// Defer to the state machine to
			// handle any other characters:
			else {
				handled = false
			}
		}
		if handled {
			return
		}
	}

	actions := self.parser.next(c)
	if action := actions.exit_action {
		self.handle_action(action)!
	}
	if action := actions.transition_action {
		self.handle_action(action)!
	}
	if action := actions.entry_action {
		self.handle_action(action)!
	}
}

// The body of the source's `for (actions) |action_opt|` loop.
fn (mut self Stream[H]) handle_action(action ParserAction) ! {
	// A handler can expose this to get the raw action before
	// it is further parsed. If this returns `true` then we skip
	// processing ourselves.
	mut skip := false
	$for method in H.methods {
		$if method.name == 'vt_raw' {
			skip = self.handler.vt_raw(action) or {
				// error handling action manually
				//
				// Always skip erroneous actions because we can't
				// be sure...
				true
			}
		}
	}
	if skip {
		return
	}

	match action {
		ParserPrint {
			self.print(action.cp)!
		}
		ParserExecute {
			self.execute(action.code)!
		}
		CSIAction {
			self.csi_dispatch(action)!
		}
		ESCAction {
			self.esc_dispatch(action)!
		}
		osc.Command {
			self.osc_dispatch(action)!
		}
		DCSAction {
			self.handler.vt(.dcs_hook, action)!
		}
		ParserDcsPut {
			self.handler.vt(.dcs_put, action.code)!
		}
		ParserDcsUnhook {
			self.handler.vt(.dcs_unhook, ActionVoid{})!
		}
		ParserApcStart {
			self.handler.vt(.apc_start, ActionVoid{})!
		}
		ParserApcPut {
			self.handler.vt(.apc_put, action.code)!
		}
		ParserApcEnd {
			self.handler.vt(.apc_end, ActionVoid{})!
		}
	}
}

// Ghostty's comptime tag gives print a concrete payload. V cannot express a
// payload type dependent on the action tag, so keep this dominant typed branch
// explicit instead of heap-copying ActionPrint into ActionValue per codepoint.
@[inline]
pub fn (mut self Stream[H]) print(c u32) ! {
	self.handler.vt_print(ActionPrint{ cp: c })!
}

pub fn (mut self Stream[H]) execute(c u8) ! {
	// If the character is > 0x7F, it's a C1 (8-bit) control,
	// which is strictly equivalent to `ESC` plus `c - 0x40`.
	if c > 0x7F {
		// executing C1 as ESC
		self.esc_dispatch(ESCAction{
			intermediates: []
			final_byte:    c - 0x40
		})!
		return
	}

	match c {
		// We ignore SOH/STX: https://github.com/microsoft/terminal/issues/10786
		0x00, 0x01, 0x02 {} // NUL, SOH, STX
		0x05 {
			// ENQ
			self.handler.vt(.enquiry, ActionVoid{})!
		}
		0x07 {
			// BEL
			self.handler.vt(.bell, ActionVoid{})!
		}
		0x08 {
			// BS
			self.handler.vt(.backspace, ActionVoid{})!
		}
		0x09 {
			// HT
			self.handler.vt(.horizontal_tab, u16(1))!
		}
		0x0A, 0x0B, 0x0C {
			// LF, VT, FF
			self.handler.vt(.linefeed, ActionVoid{})!
		}
		0x0D {
			// CR
			self.handler.vt(.carriage_return, ActionVoid{})!
		}
		0x0E {
			// SO
			self.handler.vt(.invoke_charset, ActionInvokeCharset{
				bank:    .gl
				charset: .g1
				locking: false
			})!
		}
		0x0F {
			// SI
			self.handler.vt(.invoke_charset, ActionInvokeCharset{
				bank:    .gl
				charset: .g0
				locking: false
			})!
		}
		else {
			// invalid C0 character, ignoring
		}
	}
}

fn (mut self Stream[H]) csi_dispatch(input CSIAction) ! {
	// The branch hints here are based on real world data
	// which indicates that the most common CSI finals are:
	//
	// 1. m
	// 2. H
	// 3. K
	// 4. A
	// 5. C
	// 6. X
	// 7. l
	// 8. h
	// 9. r
	//
	// Together, these 9 finals make up about 96% of all
	// CSI sequences encountered in real world scenarios.
	//
	// Additionally, within the prongs, unlikely branch
	// hints have been added to branches that deal with
	// invalid sequences/commands, this is in order to
	// optimize for the happy path where we're getting
	// valid data from the program we're running.
	//
	// ref: https://github.com/qwerasd205/asciinema-stats

	match input.final_byte {
		// CUU - Cursor Up
		`A`, `k` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_up, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid cursor up command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI A with intermediates
				}
			}
		}

		// CUD - Cursor Down
		`B` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_down, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid cursor down command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI B with intermediates
				}
			}
		}

		// CUF - Cursor Right
		`C` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_right, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid cursor right command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI C with intermediates
				}
			}
		}

		// CUB - Cursor Left
		`D`, `j` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_left, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid cursor left command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI D with intermediates
				}
			}
		}

		// CNL - Cursor Next Line
		`E` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_down, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid cursor up command
								return
							}
						}
					})!
					self.handler.vt(.carriage_return, ActionVoid{})!
				}
				else {
					// ignoring unimplemented CSI E with intermediates
				}
			}
		}

		// CPL - Cursor Previous Line
		`F` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_up, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid cursor down command
								return
							}
						}
					})!
					self.handler.vt(.carriage_return, ActionVoid{})!
				}
				else {
					// ignoring unimplemented CSI F with intermediates
				}
			}
		}

		// HPA - Cursor Horizontal Position Absolute
		// TODO: test
		`G`, `\`` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_col, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid HPA command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI G with intermediates
				}
			}
		}

		// CUP - Set Cursor Position.
		// TODO: test
		`H`, `f` {
			match input.intermediates.len {
				0 {
					pos := match input.params.len {
						0 {
							ActionCursorPos{
								row: 1
								col: 1
							}
						}
						1 {
							ActionCursorPos{
								row: input.params[0]
								col: 1
							}
						}
						2 {
							ActionCursorPos{
								row: input.params[0]
								col: input.params[1]
							}
						}
						else {
							// invalid CUP command
							return
						}
					}
					self.handler.vt(.cursor_pos, pos)!
				}
				else {
					// ignoring unimplemented CSI H with intermediates
				}
			}
		}

		// CHT - Cursor Horizontal Tabulation
		`I` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.horizontal_tab, match input.params.len {
						0 {
							u16(1)
						}
						1 {
							input.params[0]
						}
						else {
							// invalid horizontal tab command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI I with intermediates
				}
			}
		}

		// Erase Display
		`J` {
			mut protected_ := ?bool(none)
			match input.intermediates.len {
				0 {
					protected_ = false
				}
				1 {
					if input.intermediates[0] == u8(`?`) {
						protected_ = true
					}
				}
				else {}
			}

			protected := protected_ or {
				// invalid erase display command
				return
			}

			mut mode_ := ?EraseDisplay(none)
			match input.params.len {
				0 { mode_ = EraseDisplay.below }
				1 { mode_ = erase_display_from_int(input.params[0]) }
				else {}
			}

			mode := mode_ or {
				// invalid erase display command
				return
			}

			match mode {
				.below { self.handler.vt(.erase_display_below, protected)! }
				.above { self.handler.vt(.erase_display_above, protected)! }
				.complete { self.handler.vt(.erase_display_complete, protected)! }
				.scrollback { self.handler.vt(.erase_display_scrollback, protected)! }
				.scroll_complete { self.handler.vt(.erase_display_scroll_complete, protected)! }
			}
		}

		// Erase Line
		`K` {
			mut protected_ := ?bool(none)
			match input.intermediates.len {
				0 {
					protected_ = false
				}
				1 {
					if input.intermediates[0] == u8(`?`) {
						protected_ = true
					}
				}
				else {}
			}

			protected := protected_ or {
				// invalid erase line command
				return
			}

			mut mode_ := ?EraseLine(none)
			match input.params.len {
				0 {
					mode_ = EraseLine.right
				}
				1 {
					if input.params[0] < 3 {
						mode_ = erase_line_from_int(input.params[0])
					}
				}
				else {}
			}

			mode := mode_ or {
				// invalid erase line command
				return
			}

			match mode {
				.right { self.handler.vt(.erase_line_right, protected)! }
				.left { self.handler.vt(.erase_line_left, protected)! }
				.complete { self.handler.vt(.erase_line_complete, protected)! }
				.right_unless_pending_wrap { self.handler.vt(.erase_line_right_unless_pending_wrap, protected)! }
			}
		}

		// IL - Insert Lines
		// TODO: test
		`L` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.insert_lines, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid IL command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI L with intermediates
				}
			}
		}

		// DL - Delete Lines
		// TODO: test
		`M` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.delete_lines, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid DL command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI M with intermediates
				}
			}
		}

		// Delete Character (DCH)
		`P` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.delete_chars, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid delete characters command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI P with intermediates
				}
			}
		}

		// Scroll Up (SD)
		`S` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.scroll_up, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid scroll up command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI S with intermediates
				}
			}
		}

		// Scroll Down (SD)
		`T` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.scroll_down, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid scroll down command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI T with intermediates
				}
			}
		}

		// Cursor Tabulation Control
		`W` {
			match input.intermediates.len {
				0 {
					if input.params.len == 0 || (input.params.len == 1 && input.params[0] == 0) {
						self.handler.vt(.tab_set, ActionVoid{})!
						return
					}

					match input.params.len {
						1 {
							match input.params[0] {
								2 {
									self.handler.vt(.tab_clear_current, ActionVoid{})!
								}
								5 {
									self.handler.vt(.tab_clear_all, ActionVoid{})!
								}
								else {}
							}
						}
						else {}
					}

					// invalid cursor tabulation control
					return
				}
				1 {
					if input.intermediates[0] == u8(`?`) && input.params[0] == 5 {
						self.handler.vt(.tab_reset, ActionVoid{})!
					} else {
						// invalid cursor tabulation control
					}
				}
				else {
					// ignoring unimplemented CSI W with intermediates
				}
			}
		}

		// Erase Characters (ECH)
		`X` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.erase_chars, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid erase characters command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI X with intermediates
				}
			}
		}

		// CHT - Cursor Horizontal Tabulation Back
		`Z` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.horizontal_tab_back, match input.params.len {
						0 {
							u16(1)
						}
						1 {
							input.params[0]
						}
						else {
							// invalid horizontal tab back command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI Z with intermediates
				}
			}
		}

		// HPR - Cursor Horizontal Position Relative
		`a` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_col_relative, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid HPR command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI a with intermediates
				}
			}
		}

		// Repeat Previous Char (REP)
		`b` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.print_repeat, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid print repeat command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI b with intermediates
				}
			}
		}

		// c - Device Attributes (DA1)
		`c` {
			req := match input.intermediates.len {
				0 { DeviceAttributeReq.primary }
				1 {
					match input.intermediates[0] {
						`>` { DeviceAttributeReq.secondary }
						`=` { DeviceAttributeReq.tertiary }
						else { return }
					}
				}
				else { return }
			}
			self.handler.vt(.device_attributes, req)!
		}

		// VPA - Cursor Vertical Position Absolute
		`d` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_row, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid VPA command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI d with intermediates
				}
			}
		}

		// VPR - Cursor Vertical Position Relative
		`e` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.cursor_row_relative, ActionCursorMovement{
						value: match input.params.len {
							0 {
								u16(1)
							}
							1 {
								input.params[0]
							}
							else {
								// invalid VPR command
								return
							}
						}
					})!
				}
				else {
					// ignoring unimplemented CSI e with intermediates
				}
			}
		}

		// TBC - Tab Clear
		// TODO: test
		`g` {
			match input.intermediates.len {
				0 {
					if input.params.len != 1 {
						// invalid tab clear command
						return
					}
					match input.params[0] {
						u16(TabClear.current) {
							self.handler.vt(.tab_clear_current, ActionVoid{})!
						}
						u16(TabClear.all) {
							self.handler.vt(.tab_clear_all, ActionVoid{})!
						}
						else {
							// unknown tab clear mode
						}
					}
				}
				else {
					// ignoring unimplemented CSI g with intermediates
				}
			}
		}

		// SM - Set Mode
		`h` {
			ansi_mode := if input.intermediates.len == 0 {
				true
			} else if input.intermediates.len == 1 && input.intermediates[0] == u8(`?`) {
				false
			} else {
				// invalid set mode command
				return
			}

			for mode_int in input.params {
				if mode := mode_from_int(mode_int, ansi_mode) {
					self.handler.vt(.set_mode, ActionMode{ mode: mode })!
				} else {
					// unimplemented mode
				}
			}
		}

		// RM - Reset Mode
		`l` {
			ansi_mode := if input.intermediates.len == 0 {
				true
			} else if input.intermediates.len == 1 && input.intermediates[0] == u8(`?`) {
				false
			} else {
				// invalid set mode command
				return
			}

			for mode_int in input.params {
				if mode := mode_from_int(mode_int, ansi_mode) {
					self.handler.vt(.reset_mode, ActionMode{ mode: mode })!
				} else {
					// unimplemented mode
				}
			}
		}

		// SGR - Select Graphic Rendition
		`m` {
			match input.intermediates.len {
				0 {
					// This is the most common case.
					mut p := SgrParser{
						params:     input.params
						params_sep: input.params_sep
					}
					for {
						attr := p.next() or { break }
						self.handler.vt(.set_attribute, attr)!
					}
				}
				1 {
					match input.intermediates[0] {
						`>` {
							self.csi_modify_key_format(input)!
						}
						else {
							// unknown CSI m with intermediate
						}
					}
				}
				else {
					// Nothing, but I wanted a place to put this comment:
					// there are others forms of CSI m that have intermediates.
					// `vim --clean` uses `CSI ? 4 m` and I don't know what
					// that means.
				}
			}
		}

		// TODO: test
		`n` {
			// Handle deviceStatusReport first
			if input.intermediates.len == 0 || input.intermediates[0] == u8(`?`) {
				if input.params.len != 1 {
					// invalid device status report command
					return
				}

				question := if input.intermediates.len == 0 {
					false
				} else if input.intermediates.len == 1 && input.intermediates[0] == u8(`?`) {
					true
				} else {
					// invalid set mode command
					return
				}

				req := req_from_int(input.params[0], question) or {
					// invalid device status report command
					return
				}

				self.handler.vt(.device_status, ActionDeviceStatus{ request: req })!
				return
			}

			// Handle other forms of CSI n
			match input.intermediates.len {
				1 {
					match input.intermediates[0] {
						`>` {
							// This isn't strictly correct. CSI > n has parameters that
							// control what exactly is being disabled. However, we
							// only support reverting back to modify other keys in
							// numeric except format.
							self.handler.vt(.modify_key_format, ModifyKeyFormat.other_keys_numeric_except)!
						}
						else {
							// unknown CSI n with intermediate
						}
					}
				}
				else {
					// ignoring unimplemented CSI n with intermediates
				}
			}
		}

		// DECRQM - Request Mode
		`p` {
			match input.intermediates.len {
				2 {
					self.csi_request_mode(input)!
				}
				else {
					// ignoring unimplemented CSI p with intermediates
				}
			}
		}

		`q` {
			match input.intermediates.len {
				1 {
					match input.intermediates[0] {
						// DECSCUSR - Select Cursor Style
						// TODO: test
						` ` {
							mut style := AnsiCursorStyle.default_
							match input.params.len {
								0 {
									style = .default_
								}
								1 {
									style = match input.params[0] {
										0 {
											AnsiCursorStyle.default_
										}
										1 {
											AnsiCursorStyle.blinking_block
										}
										2 {
											AnsiCursorStyle.steady_block
										}
										3 {
											AnsiCursorStyle.blinking_underline
										}
										4 {
											AnsiCursorStyle.steady_underline
										}
										5 {
											AnsiCursorStyle.blinking_bar
										}
										6 {
											AnsiCursorStyle.steady_bar
										}
										else {
											// invalid cursor style value
											return
										}
									}
								}
								else {
									// invalid set cursor style command
									return
								}
							}
							self.handler.vt(.cursor_style, style)!
						}

						// DECSCA
						`"` {
							mode := match input.params.len {
								0 { ProtectedMode.off }
								1 {
									match input.params[0] {
										0, 2 { ProtectedMode.off }
										1 { ProtectedMode.dec }
										else { return }
									}
								}
								else { return }
							}

							match mode {
								.off { self.handler.vt(.protected_mode_off, ActionVoid{})! }
								.iso { self.handler.vt(.protected_mode_iso, ActionVoid{})! }
								.dec { self.handler.vt(.protected_mode_dec, ActionVoid{})! }
							}
						}

						// XTVERSION
						`>` {
							self.handler.vt(.xtversion, ActionVoid{})!
						}
						else {
							// ignoring unimplemented CSI q with intermediates
						}
					}
				}
				else {
					// ignoring unimplemented CSI p with intermediates
				}
			}
		}

		`r` {
			match input.intermediates.len {
				// DECSTBM - Set Top and Bottom Margins
				0 {
					match input.params.len {
						0 {
							self.handler.vt(.top_and_bottom_margin, ActionMargin{
								top_left:     0
								bottom_right: 0
							})!
						}
						1 {
							self.handler.vt(.top_and_bottom_margin, ActionMargin{
								top_left:     input.params[0]
								bottom_right: 0
							})!
						}
						2 {
							self.handler.vt(.top_and_bottom_margin, ActionMargin{
								top_left:     input.params[0]
								bottom_right: input.params[1]
							})!
						}
						else {
							// invalid DECSTBM command
						}
					}
				}
				1 {
					match input.intermediates[0] {
						// Restore Mode
						`?` {
							for mode_int in input.params {
								if mode := mode_from_int(mode_int, false) {
									self.handler.vt(.restore_mode, ActionMode{ mode: mode })!
								} else {
									// unimplemented restore mode
								}
							}
						}
						else {
							// unknown CSI s with intermediate
						}
					}
				}
				else {
					// ignoring unimplemented CSI s with intermediates
				}
			}
		}

		`s` {
			match input.intermediates.len {
				// DECSLRM
				0 {
					match input.params.len {
						// CSI S is ambiguous with zero params so we defer
						// to our handler to do the proper logic. If mode 69
						// is set, then we should invoke DECSLRM, otherwise
						// we should invoke SC.
						0 {
							self.handler.vt(.left_and_right_margin_ambiguous, ActionVoid{})!
						}
						1 {
							self.handler.vt(.left_and_right_margin, ActionMargin{
								top_left:     input.params[0]
								bottom_right: 0
							})!
						}
						2 {
							self.handler.vt(.left_and_right_margin, ActionMargin{
								top_left:     input.params[0]
								bottom_right: input.params[1]
							})!
						}
						else {
							// invalid DECSLRM command
						}
					}
				}
				1 {
					match input.intermediates[0] {
						`?` {
							for mode_int in input.params {
								if mode := mode_from_int(mode_int, false) {
									self.handler.vt(.save_mode, ActionMode{ mode: mode })!
								} else {
									// unimplemented save mode
								}
							}
						}

						// XTSHIFTESCAPE
						`>` {
							mut capture := false
							match input.params.len {
								0 {
									capture = false
								}
								1 {
									capture = match input.params[0] {
										0 {
											false
										}
										1 {
											true
										}
										else {
											// invalid XTSHIFTESCAPE command
											return
										}
									}
								}
								else {
									// invalid XTSHIFTESCAPE command
									return
								}
							}

							self.handler.vt(.mouse_shift_capture, capture)!
						}
						else {
							// unknown CSI s with intermediate
						}
					}
				}
				else {
					// ignoring unimplemented CSI s with intermediates
				}
			}
		}

		// XTWINOPS
		`t` {
			match input.intermediates.len {
				0 {
					if input.params.len > 0 {
						match input.params[0] {
							14 {
								if input.params.len == 1 {
									// report the text area size in pixels
									self.handler.vt(.size_report, SizeReportStyle.csi_14_t)!
								} else {
									// ignoring CSI 14 t with extra parameters
								}
							}
							16 {
								if input.params.len == 1 {
									// report cell size in pixels
									self.handler.vt(.size_report, SizeReportStyle.csi_16_t)!
								} else {
									// ignoring CSI 16 t with extra parameters
								}
							}
							18 {
								if input.params.len == 1 {
									// report screen size in characters
									self.handler.vt(.size_report, SizeReportStyle.csi_18_t)!
								} else {
									// ignoring CSI 18 t with extra parameters
								}
							}
							21 {
								if input.params.len == 1 {
									// report window title
									self.handler.vt(.size_report, SizeReportStyle.csi_21_t)!
								} else {
									// ignoring CSI 21 t with extra parameters
								}
							}
							22, 23 {
								number := input.params[0]
								if (input.params.len == 2 || input.params.len == 3)
									&& (input.params[1] == 0 || input.params[1] == 2) {
									// we only support window title
									//
									// push/pop title
									index := if input.params.len == 3 { input.params[2] } else { u16(0) }
									if number == 22 {
										self.handler.vt(.title_push, index)!
									} else {
										self.handler.vt(.title_pop, index)!
									}
								} else {
									// ignoring CSI 22/23 t with extra parameters
								}
							}
							else {
								// ignoring CSI t with unimplemented parameter
							}
						}
					} else {
						// ignoring CSI t with no parameters
					}
				}
				else {
					// ignoring unimplemented CSI t with intermediates
				}
			}
		}

		`u` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.restore_cursor, ActionVoid{})!
				}

				// Kitty keyboard protocol
				1 {
					match input.intermediates[0] {
						`?` {
							self.handler.vt(.kitty_keyboard_query, ActionVoid{})!
						}
						`>` {
							flags := if input.params.len == 1 {
								if input.params[0] > 0b1_1111 {
									// invalid pushKittyKeyboard command
									return
								}
								u8(input.params[0])
							} else {
								u8(0)
							}

							self.handler.vt(.kitty_keyboard_push, ActionKittyKeyboardFlags{
								flags: KeyFlags.from_int(flags)
							})!
						}
						`<` {
							number := if input.params.len == 1 { input.params[0] } else { u16(1) }

							self.handler.vt(.kitty_keyboard_pop, number)!
						}
						`=` {
							flags := if input.params.len >= 1 {
								if input.params[0] > 0b1_1111 {
									// invalid setKittyKeyboard command
									return
								}
								u8(input.params[0])
							} else {
								u8(0)
							}

							number := if input.params.len >= 2 { input.params[1] } else { u16(1) }

							action_tag := match number {
								1 {
									ActionKey.kitty_keyboard_set
								}
								2 {
									ActionKey.kitty_keyboard_set_or
								}
								3 {
									ActionKey.kitty_keyboard_set_not
								}
								else {
									// invalid setKittyKeyboard command
									return
								}
							}

							kitty_flags := ActionKittyKeyboardFlags{
								flags: KeyFlags.from_int(flags)
							}
							self.handler.vt(action_tag, kitty_flags)!
						}
						else {
							// unknown CSI s with intermediate
						}
					}
				}
				else {
					// ignoring unimplemented CSI u
				}
			}
		}

		// ICH - Insert Blanks
		`@` {
			match input.intermediates.len {
				0 {
					self.handler.vt(.insert_blanks, match input.params.len {
						0 {
							uint(1)
						}
						1 {
							uint(input.params[0])
						}
						else {
							// invalid ICH command
							return
						}
					})!
				}
				else {
					// ignoring unimplemented CSI @
				}
			}
		}

		// DECSASD - Select Active Status Display
		`}` {
			// Verify we're getting a DECSASD command
			if input.intermediates.len != 1 || input.intermediates[0] != u8(`$`) {
				// unimplemented CSI callback
				return
			}
			if input.params.len != 1 {
				// unimplemented CSI callback
				return
			}

			display := match input.params[0] {
				0 {
					StatusDisplay.main
				}
				1 {
					StatusDisplay.status_line
				}
				else {
					// unimplemented CSI callback
					return
				}
			}

			self.handler.vt(.active_status_display, display)!
		}
		else {
			// unimplemented CSI action
		}
	}
}

// The `'>'` prong of CSI m: set the modify key format.
fn (mut self Stream[H]) csi_modify_key_format(input CSIAction) ! {
	if input.params.len == 0 {
		// Reset
		self.handler.vt(.modify_key_format, ModifyKeyFormat.legacy)!
		return
	}

	mut format := match input.params[0] {
		0 {
			ModifyKeyFormat.legacy
		}
		1 {
			ModifyKeyFormat.cursor_keys
		}
		2 {
			ModifyKeyFormat.function_keys
		}
		4 {
			ModifyKeyFormat.other_keys_none
		}
		else {
			// invalid setModifyKeyFormat
			return
		}
	}

	if input.params.len > 2 {
		// invalid setModifyKeyFormat
		return
	}

	if input.params.len == 2 {
		match format {
			// We don't support any of the subparams yet for these.
			.legacy {}
			.cursor_keys {}
			.function_keys {}
			// We only support the numeric form.
			.other_keys_none {
				if input.params[1] == 2 {
					format = .other_keys_numeric
				}
			}
			.other_keys_numeric_except {}
			.other_keys_numeric {}
		}
	}

	self.handler.vt(.modify_key_format, format)!
}

// The `decrqm` block of CSI p.
fn (mut self Stream[H]) csi_request_mode(input CSIAction) ! {
	ansi_mode := if input.intermediates.len == 1 && input.intermediates[0] == u8(`$`) {
		true
	} else if input.intermediates.len == 2 && input.intermediates[0] == u8(`?`)
		&& input.intermediates[1] == u8(`$`) {
		false
	} else {
		// ignoring unimplemented CSI p with intermediates
		return
	}

	if input.params.len != 1 {
		// invalid DECRQM command
		return
	}

	mode_raw := input.params[0]
	if m := mode_from_int(mode_raw, ansi_mode) {
		self.handler.vt(.request_mode, ActionMode{ mode: m })!
	} else {
		self.handler.vt(.request_mode_unknown, ActionRawMode{
			mode: mode_raw
			ansi: ansi_mode
		})!
	}
}

// std.meta.intToEnum(csi.EraseDisplay, value) catch null
fn erase_display_from_int(value u16) ?EraseDisplay {
	return match value {
		u16(EraseDisplay.below) { .below }
		u16(EraseDisplay.above) { .above }
		u16(EraseDisplay.complete) { .complete }
		u16(EraseDisplay.scrollback) { .scrollback }
		u16(EraseDisplay.scroll_complete) { .scroll_complete }
		else { none }
	}
}

// @enumFromInt(value) for the non-exhaustive csi.EraseLine, restricted by the
// caller to values below 3.
fn erase_line_from_int(value u16) ?EraseLine {
	return match value {
		u16(EraseLine.right) { .right }
		u16(EraseLine.left) { .left }
		u16(EraseLine.complete) { .complete }
		else { none }
	}
}

fn (mut self Stream[H]) osc_dispatch(cmd osc.Command) ! {
	// The branch hints here are based on real world data
	// which indicates that the most common OSC commands are:
	//
	// 1. hyperlink_end
	// 2. change_window_title
	// 3. change_window_icon
	// 4. hyperlink_start
	// 5. report_pwd
	// 6. color_operation
	// 7. semantic_prompt
	//
	// Together, these 7 commands make up about 96% of all
	// OSC commands encountered in real world scenarios.
	//
	// Additionally, within the prongs, unlikely branch
	// hints have been added to branches that deal with
	// invalid sequences/commands, this is in order to
	// optimize for the happy path where we're getting
	// valid data from the program we're running.
	//
	// ref: https://github.com/qwerasd205/asciinema-stats

	match cmd {
		osc.SemanticPrompt {
			self.handler.vt(.semantic_prompt, cmd)!
		}
		osc.ChangeWindowTitle {
			if !validate.utf8_string(cmd.value) {
				// change title request: invalid utf-8, ignoring request
				return
			}

			self.handler.vt(.window_title, ActionWindowTitle{ title: cmd.value })!
		}
		osc.ChangeWindowIcon {
			// OSC 1 (change icon) received and ignored
		}
		osc.ClipboardContents {
			self.handler.vt(.clipboard_contents, ActionClipboardContents{
				kind: cmd.kind
				data: cmd.data
			})!
		}
		osc.ReportPwd {
			self.handler.vt(.report_pwd, ActionReportPwd{ url: cmd.value })!
		}
		osc.MouseShape {
			shape := MouseShape.from_string(cmd.value) or {
				// unknown cursor shape
				return
			}

			self.handler.vt(.mouse_shape, shape)!
		}
		osc.ColorOperationCommand {
			self.handler.vt(.color_operation, ActionColorOperation{
				op:         cmd.op
				requests:   cmd.requests
				terminator: cmd.terminator
			})!
		}
		osc.KittyColorOSC {
			self.handler.vt(.kitty_color_report, cmd)!
		}
		osc.DesktopNotification {
			self.handler.vt(.show_desktop_notification, ActionShowDesktopNotification{
				title: cmd.title
				body:  cmd.body
			})!
		}
		osc.HyperlinkStart {
			self.handler.vt(.start_hyperlink, ActionStartHyperlink{
				uri: cmd.uri
				id:  cmd.id
			})!
		}
		osc.HyperlinkEnd {
			self.handler.vt(.end_hyperlink, ActionVoid{})!
		}
		osc.ProgressReport {
			self.handler.vt(.progress_report, cmd)!
		}
		osc.ConEmuSleep, osc.ConEmuShowMessageBox, osc.ConEmuChangeTabTitle, osc.ConEmuWaitInput,
		osc.ConEmuGuiMacro, osc.ConEmuComment, osc.ConEmuXtermEmulation,
		osc.ConEmuOutputEnvironmentVariable, osc.ConEmuRunProcess, osc.KittyTextSizing {
			// unimplemented OSC callback
		}
		osc.InvalidCommand {
			// This is an invalid internal state, not an invalid OSC
			// string being parsed. We shouldn't see this.
		}
	}
}

fn (mut self Stream[H]) configure_charset(intermediates []u8, set Charset) ! {
	if intermediates.len != 1 {
		// invalid charset intermediate
		return
	}

	slot := match intermediates[0] {
		// TODO: support slots '-', '.', '/'
		`(` {
			CharsetSlot.g0
		}
		`)` {
			CharsetSlot.g1
		}
		`*` {
			CharsetSlot.g2
		}
		`+` {
			CharsetSlot.g3
		}
		else {
			// invalid charset intermediate
			return
		}
	}

	self.handler.vt(.configure_charset, ActionConfigureCharset{
		slot:    slot
		charset: set
	})!
}

fn (mut self Stream[H]) esc_dispatch(action ESCAction) ! {
	// The branch hints here are based on real world data
	// which indicates that the most common ESC finals are:
	//
	// 1. B
	// 2. \
	// 3. 0
	// 4. M
	// 5. 8
	// 6. 7
	// 7. >
	// 8. =
	//
	// Together, these 8 finals make up nearly 99% of all
	// ESC sequences encountered in real world scenarios.
	//
	// Additionally, within the prongs, unlikely branch
	// hints have been added to branches that deal with
	// invalid sequences/commands, this is in order to
	// optimize for the happy path where we're getting
	// valid data from the program we're running.
	//
	// ref: https://github.com/qwerasd205/asciinema-stats

	match action.final_byte {
		// Charsets
		`B` {
			self.configure_charset(action.intermediates, .ascii)!
		}
		`A` {
			self.configure_charset(action.intermediates, .british)!
		}
		`0` {
			self.configure_charset(action.intermediates, .dec_special)!
		}

		// DECSC - Save Cursor
		`7` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.save_cursor, ActionVoid{})!
				}
				else {
					// invalid command
					return
				}
			}
		}

		`8` {
			match action.intermediates.len {
				// DECRC - Restore Cursor
				0 {
					self.handler.vt(.restore_cursor, ActionVoid{})!
					return
				}
				1 {
					match action.intermediates[0] {
						// DECALN - Fill Screen with E
						`#` {
							self.handler.vt(.decaln, ActionVoid{})!
							return
						}
						else {}
					}
				}
				else {} // fall through
			}

			// unimplemented ESC action
		}

		// IND - Index
		`D` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.index, ActionVoid{})!
				}
				else {
					// invalid index command
					return
				}
			}
		}

		// NEL - Next Line
		`E` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.next_line, ActionVoid{})!
				}
				else {
					// invalid next line command
					return
				}
			}
		}

		// HTS - Horizontal Tab Set
		`H` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.tab_set, ActionVoid{})!
				}
				else {
					// invalid tab set command
					return
				}
			}
		}

		// RI - Reverse Index
		`M` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.reverse_index, ActionVoid{})!
				}
				else {
					// invalid reverse index command
					return
				}
			}
		}

		// SS2 - Single Shift 2
		`N` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.invoke_charset, ActionInvokeCharset{
						bank:    .gl
						charset: .g2
						locking: true
					})!
				}
				else {
					// invalid single shift 2 command
					return
				}
			}
		}

		// SS3 - Single Shift 3
		`O` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.invoke_charset, ActionInvokeCharset{
						bank:    .gl
						charset: .g3
						locking: true
					})!
				}
				else {
					// invalid single shift 3 command
					return
				}
			}
		}

		// SPA - Start of Guarded Area
		`V` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.protected_mode_iso, ActionVoid{})!
				}
				else {
					// unimplemented ESC callback
				}
			}
		}

		// EPA - End of Guarded Area
		`W` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.protected_mode_off, ActionVoid{})!
				}
				else {
					// unimplemented ESC callback
				}
			}
		}

		// DECID
		`Z` {
			if action.intermediates.len == 0 {
				self.handler.vt(.device_attributes, DeviceAttributeReq.primary)!
			} else {
				// unimplemented ESC callback
			}
		}

		// RIS - Full Reset
		`c` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.full_reset, ActionVoid{})!
				}
				else {
					// invalid full reset command
					return
				}
			}
		}

		// LS2 - Locking Shift 2
		`n` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.invoke_charset, ActionInvokeCharset{
						bank:    .gl
						charset: .g2
						locking: false
					})!
				}
				else {
					// invalid single shift 2 command
					return
				}
			}
		}

		// LS3 - Locking Shift 3
		`o` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.invoke_charset, ActionInvokeCharset{
						bank:    .gl
						charset: .g3
						locking: false
					})!
				}
				else {
					// invalid single shift 3 command
					return
				}
			}
		}

		// LS1R - Locking Shift 1 Right
		`~` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.invoke_charset, ActionInvokeCharset{
						bank:    .gr
						charset: .g1
						locking: false
					})!
				}
				else {
					// invalid locking shift 1 right command
					return
				}
			}
		}

		// LS2R - Locking Shift 2 Right
		`}` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.invoke_charset, ActionInvokeCharset{
						bank:    .gr
						charset: .g2
						locking: false
					})!
				}
				else {
					// invalid locking shift 2 right command
					return
				}
			}
		}

		// LS3R - Locking Shift 3 Right
		`|` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.invoke_charset, ActionInvokeCharset{
						bank:    .gr
						charset: .g3
						locking: false
					})!
				}
				else {
					// invalid locking shift 3 right command
					return
				}
			}
		}

		// Set application keypad mode
		`=` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.set_mode, ActionMode{ mode: .keypad_keys })!
				}
				else {
					// unimplemented setMode
				}
			}
		}

		// Reset application keypad mode
		`>` {
			match action.intermediates.len {
				0 {
					self.handler.vt(.reset_mode, ActionMode{ mode: .keypad_keys })!
				}
				else {
					// unimplemented setMode
				}
			}
		}

		// Sets ST (string terminator). We don't have to do anything
		// because our parser always accepts ST.
		`\\` {}
		else {
			// unimplemented ESC action
		}
	}
}
