module termio

import renderer
import terminal
import apprt
import build_meta
import datastruct
import osc
import sync
import tmux

// ============================================================
// StreamHandler tests
// ============================================================

// TestContext holds all test allocations so pointers stay valid.
struct TestContext {
mut:
	t              terminal.Terminal
	mailbox        Mailbox
	rstate         renderer.State
	rmailbox       &renderer.Mailbox = unsafe { nil }
	rsize          renderer.Size
	messages       []apprt.SurfaceMessage
	timeouts       []datastruct.BlockingQueueTimeoutKind
	reject_instant bool
}

fn collect_surface_message(app voidptr, surface voidptr, msg apprt.SurfaceMessage, timeout datastruct.BlockingQueueTimeout) u32 {
	_ = app
	mut ctx := unsafe { &TestContext(surface) }
	ctx.timeouts << timeout.kind()
	if ctx.reject_instant && timeout.kind() == .instant {
		return 0
	}
	ctx.messages << msg
	return 1
}

// Helper to create a StreamHandler with a test terminal.
fn make_test_handler() (&StreamHandler, &TestContext) {
	mut ctx := &TestContext{
		t:        terminal.Terminal.init(terminal.Options{
			cols: 80
			rows: 24
		}) or { panic('failed to init terminal') }
		mailbox:  Mailbox.init_spsc() or { panic(err) }
		rmailbox: renderer.Mailbox.create() or { panic(err) }
	}

	mut handler := &StreamHandler{
		terminal:             &ctx.t
		termio_mailbox:       &ctx.mailbox
		renderer_state:       &ctx.rstate
		renderer_mailbox:     ctx.rmailbox
		surface_mailbox:      apprt.SurfaceMailbox{
			surface: ctx
			push_fn: collect_surface_message
		}
		size:                 &ctx.rsize
		default_cursor_style: .block
	}
	return handler, ctx
}

fn (mut ctx TestContext) assert_no_io_messages() {
	message := ctx.mailbox.spsc.queue.pop() or { return }
	assert false, 'unexpected terminal I/O message: ${message.kind()}'
}

fn test_surface_message_writer_retries_without_renderer_lock_after_full_queue() ! {
	mut handler, mut ctx := make_test_handler()
	defer {
		ctx.t.deinit()
	}
	ctx.reject_instant = true
	ctx.rstate.mutex = sync.new_mutex()
	ctx.rstate.mutex.lock()
	handler.surface_message_writer(apprt.SurfaceMessageRingBell{})
	ctx.rstate.mutex.unlock()
	ctx.rstate.mutex.destroy()
	ctx.rstate.mutex = unsafe { nil }
	assert ctx.messages.len == 1
	assert ctx.messages[0].kind() == .ring_bell
	assert ctx.timeouts == [.instant, .forever]
}

fn test_progress_report_forwards_payload() ! {
	mut handler, mut ctx := make_test_handler()
	defer {
		ctx.t.deinit()
	}
	handler.progress_report(osc.ProgressReport{
		state:    .set
		progress: 42
	})
	assert ctx.messages.len == 1
	assert ctx.messages[0].kind() == .progress_report
	assert (ctx.messages[0] as osc.ProgressReport).state == osc.ProgressState.set
	assert (ctx.messages[0] as osc.ProgressReport).progress or { 0 } == 42

	handler.progress_report(osc.ProgressReport{
		state: .indeterminate
	})
	assert ctx.messages.len == 2
	assert (ctx.messages[1] as osc.ProgressReport).state == .indeterminate
	assert (ctx.messages[1] as osc.ProgressReport).progress == none
}

fn test_desktop_notification_forwards_typed_payload() ! {
	mut handler, mut ctx := make_test_handler()
	defer {
		ctx.t.deinit()
	}
	handler.show_desktop_notification('Compiler', 'Build failed')!
	assert ctx.messages.len == 1
	assert ctx.messages[0].kind() == .desktop_notification
	assert (ctx.messages[0] as apprt.SurfaceMessageDesktopNotification).title[..8].bytestr() == 'Compiler'
	assert (ctx.messages[0] as apprt.SurfaceMessageDesktopNotification).body[..12].bytestr() == 'Build failed'
}

fn test_desktop_notification_preserves_full_sentinel_array_payloads() ! {
	mut handler, mut ctx := make_test_handler()
	defer {
		ctx.t.deinit()
	}
	title := 't'.repeat(63)
	body := 'b'.repeat(255)
	handler.show_desktop_notification(title, body)!

	assert ctx.messages.len == 1
	assert (ctx.messages[0] as apprt.SurfaceMessageDesktopNotification).title[..63].bytestr() == title
	assert (ctx.messages[0] as apprt.SurfaceMessageDesktopNotification).title[63] == 0
	assert (ctx.messages[0] as apprt.SurfaceMessageDesktopNotification).body[..255].bytestr() == body
	assert (ctx.messages[0] as apprt.SurfaceMessageDesktopNotification).body[255] == 0
}

// Test that the StreamHandler can be created and deinitialized.
fn test_stream_handler_init_deinit() ! {
	mut handler, mut ctx := make_test_handler()
	handler.deinit()
	ctx.t.deinit()
}

fn test_stream_handler_tmux_viewer_lifecycle_and_commands() ! {
	if !terminal.tmux_control_mode {
		return
	}
	mut handler, mut ctx := make_test_handler()
	defer {
		handler.deinit()
		ctx.t.deinit()
	}

	mut enter := terminal.DcsCommand(terminal.DcsCommandTmux{
		notification: tmux.Notification(tmux.NotifEnter{})
	})
	handler.dcs_command(mut enter)!
	assert handler.tmux_viewer != none

	mut startup_done := terminal.DcsCommand(terminal.DcsCommandTmux{
		notification: tmux.Notification(tmux.NotifBlockEnd{})
	})
	handler.dcs_command(mut startup_done)!
	ctx.assert_no_io_messages()

	mut session := terminal.DcsCommand(terminal.DcsCommandTmux{
		notification: tmux.Notification(tmux.NotifSessionChanged{
			id:   7
			name: 'main'
		})
	})
	handler.dcs_command(mut session)!
	assert handler.termio_messaged
	msg := ctx.mailbox.spsc.queue.pop() or { panic('expected tmux command') }
	assert msg.kind() == .write_small
	assert (msg as WriteSmall).slice().bytestr().starts_with('display-message')

	mut exit := terminal.DcsCommand(terminal.DcsCommandTmux{
		notification: tmux.Notification(tmux.NotifExit{})
	})
	handler.dcs_command(mut exit)!
	assert handler.tmux_viewer == none
}

fn test_xtgettcap_uses_complete_ghostty_capability_encoding() ! {
	// Keys are the hex-encoded capability names exactly as they arrive on the
	// wire, and each value is the full DCS response.
	assert xtgettcap_map['616D'] or { 'missing' } == '\x1bP1+r616D\x1b\\'
	assert xtgettcap_map['636F6C6F7273'] or { '' } == '\x1bP1+r636F6C6F7273=323536\x1b\\'
	assert xtgettcap_map['524742'] or { '' } == '\x1bP1+r524742=38\x1b\\'
	assert xtgettcap_map['536D756C78'] or { '' } == '\x1bP1+r536D756C78=5C455B343A25703125646D\x1b\\'
	assert xtgettcap_map['6B6273'] or { '' } == '\x1bP1+r6B6273=7F\x1b\\'
	assert xtgettcap_map['6B6631'] or { '' } == '\x1bP1+r6B6631=1B4F50\x1b\\'
	assert xtgettcap_map['6B663633'] or { '' } == '\x1bP1+r6B663633=1B5B313B3452\x1b\\'
	assert '6E6F742D612D6361706162696C697479' !in xtgettcap_map

	// Lower-case requests go unanswered, as in the source.
	assert '616d' !in xtgettcap_map
}

fn test_stream_handler_xtgettcap_omits_unknown_and_formats_boolean() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	mut query := terminal.DcsXtgettcap{
		data: '616D;756E6B6E6F776E;636F6C6F7273'.bytes()
	}
	handler.dcs_xtgettcap(mut query)

	boolean_msg := ctx.mailbox.spsc.queue.pop() or {
		assert false
		return
	}
	assert boolean_msg.kind() == .write_stable
	assert (boolean_msg as MessageWriteStable).data == '\x1bP1+r616D\x1b\\'

	numeric_msg := ctx.mailbox.spsc.queue.pop() or {
		assert false
		return
	}
	assert numeric_msg.kind() == .write_stable
	assert (numeric_msg as MessageWriteStable).data == '\x1bP1+r636F6C6F7273=323536\x1b\\'
	ctx.assert_no_io_messages()
}

fn test_stream_handler_xtversion_uses_build_version() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.report_xtversion()!

	msg := ctx.mailbox.spsc.queue.pop() or { panic('expected XTVERSION response') }
	assert msg.kind() == .write_small
	assert (msg as WriteSmall).slice().bytestr() == '\x1bP>|witty ${build_meta.version_string}\x1b\\'
	ctx.assert_no_io_messages()
}

fn test_stream_handler_request_mode_uses_dec_protocol_value() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.request_mode(.cursor_visible)!

	msg := ctx.mailbox.spsc.queue.pop() or { panic('expected DECRQM response') }
	assert msg.kind() == .write_small
	assert (msg as WriteSmall).slice().bytestr() == '\x1b[?25;1\$y'
}

fn test_stream_handler_request_mode_uses_ansi_protocol_value() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.request_mode(.insert)!

	msg := ctx.mailbox.spsc.queue.pop() or { panic('expected DECRQM response') }
	assert msg.kind() == .write_small
	assert (msg as WriteSmall).slice().bytestr() == '\x1b[4;2\$y'
}

fn test_stream_handler_decrqss_requires_declrmm_for_horizontal_margins() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.dcs_decrqss(.decslrm)
	disabled := ctx.mailbox.spsc.queue.pop() or { panic('expected invalid DECRPSS response') }
	assert (disabled as WriteSmall).slice().bytestr() == '\x1bP0\$r\x1b\\'

	handler.terminal.modes.set(.enable_left_and_right_margin, true)
	handler.dcs_decrqss(.decslrm)
	enabled := ctx.mailbox.spsc.queue.pop() or { panic('expected valid DECRPSS response') }
	assert (enabled as WriteSmall).slice().bytestr() == '\x1bP1\$r1;80s\x1b\\'
}

fn test_stream_handler_decrqss_hollow_cursor_uses_blink_mode() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.terminal.screens.active.cursor.cursor_style = .block_hollow

	handler.terminal.modes.set(.cursor_blinking, true)
	handler.dcs_decrqss(.decscusr)
	blinking := ctx.mailbox.spsc.queue.pop() or {
		panic('expected blinking cursor DECRPSS response')
	}
	assert (blinking as WriteSmall).slice().bytestr() == '\x1bP1\$r1 q\x1b\\'

	handler.terminal.modes.set(.cursor_blinking, false)
	handler.dcs_decrqss(.decscusr)
	steady := ctx.mailbox.spsc.queue.pop() or { panic('expected steady cursor DECRPSS response') }
	assert (steady as WriteSmall).slice().bytestr() == '\x1bP1\$r2 q\x1b\\'
}

fn test_stream_handler_decrqss_uses_terminal_sgr_serialization() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	mut stream := terminal.Stream.init[StreamHandler](handler)
	stream.next_slice('\x1b[4:3;53m\x1bP\$qm\x1b\\'.bytes())!

	msg := ctx.mailbox.spsc.queue.pop() or { panic('expected SGR DECRPSS response') }
	assert (msg as WriteSmall).slice().bytestr() == '\x1bP1\$r0;4:3;53m\x1b\\'
}

// Test bell dispatches without crashing.
fn test_stream_handler_bell() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.bell, terminal.ActionVoid{})!
}

// Test horizontal tab.
fn test_stream_handler_horizontal_tab() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.horizontal_tab, u16(1))!
	// The cursor should have moved to the first tabstop
	assert handler.terminal.screens.active.cursor.x == 8
}

// Test carriage return.
fn test_stream_handler_carriage_return() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	// Move cursor right first
	handler.terminal.cursor_right(5)
	assert handler.terminal.screens.active.cursor.x == 5
	// Carriage return
	handler.vt(.carriage_return, terminal.ActionVoid{})!
	assert handler.terminal.screens.active.cursor.x == 0
}

// Test cursor movement dispatching.
fn test_stream_handler_cursor_movement() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// cursor_right
	handler.vt(.cursor_right, terminal.ActionCursorMovement{ value: 3 })!
	assert handler.terminal.screens.active.cursor.x == 3

	// cursor_down
	handler.vt(.cursor_down, terminal.ActionCursorMovement{ value: 2 })!
	assert handler.terminal.screens.active.cursor.y == 2

	// cursor_left
	handler.vt(.cursor_left, terminal.ActionCursorMovement{ value: 1 })!
	assert handler.terminal.screens.active.cursor.x == 2

	// cursor_up
	handler.vt(.cursor_up, terminal.ActionCursorMovement{ value: 1 })!
	assert handler.terminal.screens.active.cursor.y == 1
}

// Test cursor_pos dispatching (row, col in 1-based).
fn test_stream_handler_cursor_pos() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.cursor_pos, terminal.ActionCursorPos{ row: 5, col: 10 })!
	assert handler.terminal.screens.active.cursor.y == 4 // 0-based
	assert handler.terminal.screens.active.cursor.x == 9 // 0-based
}

// Test set_cursor_style dispatching.
fn test_stream_handler_cursor_style() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// Set to steady underline
	handler.vt(.cursor_style, terminal.AnsiCursorStyle.steady_underline)!
	assert handler.terminal.screens.active.cursor.cursor_style == .underline
	assert !handler.default_cursor

	// Set to default
	handler.vt(.cursor_style, terminal.AnsiCursorStyle.default_)!
	assert handler.default_cursor
	assert handler.terminal.screens.active.cursor.cursor_style == .block
}

// Test set_mode dispatching.
fn test_stream_handler_set_mode_origin() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// Move cursor somewhere
	handler.terminal.set_cursor_pos(5, 10)
	assert handler.terminal.screens.active.cursor.y == 4

	// Setting origin mode resets cursor to (1,1)
	handler.vt(.set_mode, terminal.ActionMode{ mode: .origin })!
	assert handler.terminal.screens.active.cursor.y == 0
	assert handler.terminal.screens.active.cursor.x == 0
}

// Test print dispatching.
fn test_stream_handler_print() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.print, terminal.ActionPrint{ cp: u32(`A`) })!
	assert handler.terminal.screens.active.cursor.x == 1
}

// Test full_reset dispatching.
fn test_stream_handler_full_reset() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// Move cursor, change mode
	handler.terminal.set_cursor_pos(10, 20)
	handler.terminal.modes.set(.origin, true)

	// Full reset
	handler.vt(.full_reset, terminal.ActionVoid{})!

	assert !handler.terminal.modes.get(.origin)
	assert handler.terminal.screens.active.cursor.x == 0
	assert handler.terminal.screens.active.cursor.y == 0
}

// Test save/restore cursor dispatching.
fn test_stream_handler_save_restore_cursor() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// Move cursor
	handler.terminal.set_cursor_pos(5, 10)
	assert handler.terminal.screens.active.cursor.y == 4
	assert handler.terminal.screens.active.cursor.x == 9

	// Save cursor
	handler.vt(.save_cursor, terminal.ActionVoid{})!

	// Move cursor elsewhere
	handler.terminal.set_cursor_pos(1, 1)
	assert handler.terminal.screens.active.cursor.y == 0

	// Restore cursor
	handler.vt(.restore_cursor, terminal.ActionVoid{})!
	assert handler.terminal.screens.active.cursor.y == 4
	assert handler.terminal.screens.active.cursor.x == 9
}

// Test modify_key_format dispatching.
fn test_stream_handler_modify_key_format() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	assert !handler.terminal.flags.modify_other_keys_2()

	handler.vt(.modify_key_format, terminal.ModifyKeyFormat.other_keys_numeric)!
	assert handler.terminal.flags.modify_other_keys_2()

	handler.vt(.modify_key_format, terminal.ModifyKeyFormat.legacy)!
	assert !handler.terminal.flags.modify_other_keys_2()
}

// Test linefeed dispatching (calls index).
fn test_stream_handler_linefeed() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.linefeed, terminal.ActionVoid{})!
	assert handler.terminal.screens.active.cursor.y == 1
}

// Test protected mode dispatching.
fn test_stream_handler_protected_mode() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.vt(.protected_mode_dec, terminal.ActionVoid{})!
	assert handler.terminal.screens.active.cursor.is_protected

	handler.vt(.protected_mode_off, terminal.ActionVoid{})!
	assert !handler.terminal.screens.active.cursor.is_protected
}

// Test backspace dispatching.
fn test_stream_handler_backspace() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.terminal.cursor_right(3)
	assert handler.terminal.screens.active.cursor.x == 3
	handler.vt(.backspace, terminal.ActionVoid{})!
	assert handler.terminal.screens.active.cursor.x == 2
}

// Test erase_display_complete dispatching.
fn test_stream_handler_erase_display() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	// Print something
	handler.terminal.print(u32(`X`)) or {}
	// Erase complete
	handler.vt(.erase_display_complete, false)!
	// Verify cursor x didn't change (erase doesn't move cursor)
}

// Test scroll_up dispatching.
fn test_stream_handler_scroll_up() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.scroll_up, uint(1))!
	// Should not crash
}

// Test erase_chars dispatching.
fn test_stream_handler_erase_chars() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.erase_chars, uint(5))!
}

// Test insert_lines dispatching.
fn test_stream_handler_insert_lines() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.insert_lines, uint(2))!
}

// Test delete_lines dispatching.
fn test_stream_handler_delete_lines() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.delete_lines, uint(1))!
}

// Test insert_blanks dispatching.
fn test_stream_handler_insert_blanks() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.insert_blanks, uint(3))!
}

// Test delete_chars dispatching.
fn test_stream_handler_delete_chars() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.delete_chars, uint(2))!
}

// Test tab_set and tab_clear_current dispatching.
fn test_stream_handler_tab_operations() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.tab_set, terminal.ActionVoid{})!
	handler.vt(.tab_clear_current, terminal.ActionVoid{})!
	handler.vt(.tab_clear_all, terminal.ActionVoid{})!
	handler.vt(.tab_reset, terminal.ActionVoid{})!
}

// Test kitty keyboard push/pop dispatching.
fn test_stream_handler_kitty_keyboard() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	assert handler.terminal.screens.active.kitty_keyboard.current() == terminal.key_flags_disabled

	// Push
	handler.vt(.kitty_keyboard_push, terminal.ActionKittyKeyboardFlags{
		flags: terminal.KeyFlags.from_int(5)
	})!
	assert handler.terminal.screens.active.kitty_keyboard.current().int() == 5

	// Pop
	handler.vt(.kitty_keyboard_pop, u16(1))!
	assert handler.terminal.screens.active.kitty_keyboard.current() == terminal.key_flags_disabled

	// The full u16 count must reach FlagStack.pop; narrowing to u8 would
	// turn 256 into zero instead of resetting the stack.
	handler.terminal.screens.active.kitty_keyboard.set(.set_, terminal.KeyFlags.from_int(3))
	handler.terminal.screens.active.kitty_keyboard.push(terminal.KeyFlags.from_int(5))
	handler.vt(.kitty_keyboard_pop, u16(256))!
	assert handler.terminal.screens.active.kitty_keyboard.current() == terminal.key_flags_disabled
}

// Test set_mode for mouse events.
fn test_stream_handler_mouse_modes() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// Enable mouse normal tracking
	handler.set_mode(.mouse_event_normal, true)!
	assert handler.terminal.flags.mouse_event() == .normal
	assert handler.terminal.mouse_shape == .default_

	// Disable
	handler.set_mode(.mouse_event_normal, false)!
	assert handler.terminal.flags.mouse_event() == .none
	assert handler.terminal.mouse_shape == .text
}

fn test_stream_handler_relative_cursor_movement_saturates() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.terminal.set_cursor_pos(5, 10)
	handler.vt(.cursor_col_relative, terminal.ActionCursorMovement{
		value: ~u16(0)
	})!
	assert handler.terminal.screens.active.cursor.x == 79
	assert handler.terminal.screens.active.cursor.y == 4

	handler.terminal.set_cursor_pos(5, 10)
	handler.vt(.cursor_row_relative, terminal.ActionCursorMovement{
		value: ~u16(0)
	})!
	assert handler.terminal.screens.active.cursor.x == 9
	assert handler.terminal.screens.active.cursor.y == 23
}

// Test set_mode for mouse format.
fn test_stream_handler_mouse_format() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.set_mode(.mouse_format_sgr, true)!
	assert handler.terminal.flags.mouse_format() == .sgr

	handler.set_mode(.mouse_format_sgr, false)!
	assert handler.terminal.flags.mouse_format() == .x10
}

// Test DCS/APC handlers don't crash.
fn test_stream_handler_dcs_apc() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// APC start/put/end
	handler.vt(.apc_start, terminal.ActionVoid{})!
	handler.vt(.apc_put, u8(u8(`G`)))!
	handler.vt(.apc_end, terminal.ActionVoid{})!

	// DCS hook/put/unhook
	handler.vt(.dcs_hook, terminal.DCSAction{})!
	handler.vt(.dcs_put, u8(`x`))!
	handler.vt(.dcs_unhook, terminal.ActionVoid{})!
}

// Test change_config.
fn test_stream_handler_change_config() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	config := DerivedConfig{
		osc_color_report_format: .format_8_bit
		clipboard_write:         .deny
		enquiry_response:        'test'
		cursor_style:            .underline
		cursor_blink:            true
	}
	handler.change_config(&config)

	assert handler.osc_color_report_format == .format_8_bit
	assert handler.clipboard_write == .deny
	assert handler.enquiry_response == 'test'
	assert handler.default_cursor_style == .underline
}

fn test_color_query_response_mirrors_osc_terminator() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.osc_color_report_format = .format_8_bit
	mut stream := terminal.Stream.init_alloc[StreamHandler](voidptr(1), handler)
	defer { stream.deinit() }

	stream.next_slice('\x1b]4;1;?\a'.bytes())!
	bel := ctx.mailbox.spsc.queue.pop() or { panic('expected BEL-terminated color response') }
	assert bel.kind() == .write_small
	assert (bel as WriteSmall).slice().bytestr().ends_with('\a')

	stream.next_slice('\x1b]4;1;?\x1b\\'.bytes())!
	st := ctx.mailbox.spsc.queue.pop() or { panic('expected ST-terminated color response') }
	assert st.kind() == .write_small
	assert (st as WriteSmall).slice().bytestr().ends_with('\x1b\\')
}

fn test_color_query_response_preserves_fixed_buffer_limit() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.osc_color_report_format = .format_16_bit
	mut stream := terminal.Stream.init_alloc[StreamHandler](voidptr(1), handler)
	defer { stream.deinit() }
	query := '\x1b]4' + ';1;?'.repeat(64) + '\x1b\\'

	stream.next_slice(query.bytes()) or {
		assert err.msg() == 'OutOfMemory'
		ctx.assert_no_io_messages()
		return
	}
	assert false, 'the fixed OSC color response buffer must reject oversized output'
}

fn test_kitty_color_query_response_mirrors_osc_terminator() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.vt(.kitty_color_report, osc.KittyColorOSC{
		list:       [osc.KittyColorRequest(osc.KittyColorQuery{
			key: u8(1)
		})]
		terminator: .bel
	})!
	msg := ctx.mailbox.spsc.queue.pop() or { panic('expected Kitty color response') }
	assert msg.kind() == .write_alloc
	response := (msg as MessageWriteAlloc).data
	assert response.starts_with('\x1b]21;1=rgb:')
	assert response.ends_with('\a')
}

// Test cursor_blinking mode is ignored when default_cursor_blink is set.
fn test_stream_handler_cursor_blinking_override() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	// Set a default blink preference
	handler.default_cursor_blink = true

	// Try to set cursor_blinking mode - should be ignored
	handler.set_mode(.cursor_blinking, false)!
	// The mode should still be whatever it was (it's ignored)
	// This tests the early return in set_mode for cursor_blinking
}

// Test report_pwd with empty URL.
fn test_stream_handler_report_pwd_empty() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.report_pwd('')!
	assert ctx.messages.len == 2
	assert ctx.messages[0].kind() == .set_title
	assert ctx.messages[1].kind() == .pwd_change
	assert (ctx.messages[1] as apprt.SurfaceMessagePwdChange).req.slice().bytestr() == ''
}

fn test_stream_handler_clipboard_read_forwards_clipboard_type() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.clipboard_contents(`p`, '?')!

	assert ctx.messages.len == 1
	assert ctx.messages[0].kind() == .clipboard_read
	assert (ctx.messages[0] as apprt.SurfaceMessageClipboardRead).clipboard == .primary
}

fn test_stream_handler_clipboard_write_forwards_contents_and_type() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.clipboard_contents(`s`, 'translated clipboard data')!

	assert ctx.messages.len == 1
	assert ctx.messages[0].kind() == .clipboard_write
	assert (ctx.messages[0] as apprt.SurfaceMessageClipboardWrite).clipboard_type == .selection
	assert (ctx.messages[0] as apprt.SurfaceMessageClipboardWrite).req.slice().bytestr() == 'translated clipboard data'
}

fn test_stream_handler_clipboard_write_owns_contents() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	mut data := 'owned clipboard data'.bytes()
	handler.clipboard_contents(`c`, data.bytestr())!
	data[0] = `X`

	assert (ctx.messages[0] as apprt.SurfaceMessageClipboardWrite).req.slice().bytestr() == 'owned clipboard data'
}

fn test_stream_handler_report_pwd_forwards_decoded_path() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.report_pwd('file://localhost/tmp/translated%20path')!

	assert ctx.messages.len == 2
	assert ctx.messages[0].kind() == .pwd_change
	assert (ctx.messages[0] as apprt.SurfaceMessagePwdChange).req.slice().bytestr() == '/tmp/translated path'
	assert ctx.messages[1].kind() == .set_title
}

fn test_stream_handler_report_pwd_preserves_kitty_raw_path() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }

	handler.report_pwd('kitty-shell-cwd://localhost/tmp/raw%20path??#fragment')!

	assert ctx.messages.len == 2
	assert ctx.messages[0].kind() == .pwd_change
	assert (ctx.messages[0] as apprt.SurfaceMessagePwdChange).req.slice().bytestr() == '/tmp/raw%20path??#fragment'
	assert ctx.messages[1].kind() == .set_title
}

// Test window_title with empty title.
fn test_stream_handler_window_title_empty() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.window_title('')!
	assert !handler.seen_title
}

// Test window_title with non-empty title.
fn test_stream_handler_window_title() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.window_title('My Terminal')!
	assert handler.seen_title
}

// A CSI 6 n parsed by the stream reaches deviceStatusReport with its request
// and is answered with the 1-based cursor position.
fn test_stream_handler_device_status_cursor_position_report() ! {
	mut handler, mut ctx := make_test_handler()
	defer { ctx.t.deinit() }
	handler.vt(.cursor_pos, terminal.ActionCursorPos{ row: 3, col: 5 })!
	mut s := terminal.Stream.init[StreamHandler](handler)
	s.next_slice('\x1b[6n'.bytes())!
	msg := ctx.mailbox.spsc.queue.pop() or { panic('expected a cursor position report') }
	assert msg.kind() == .write_small
	assert (msg as WriteSmall).slice().bytestr() == '\x1b[3;5R'
}
