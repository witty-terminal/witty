// Native C ABI exported by Ghostty's lib_vt.zig.
//
// These wrappers deliberately keep opaque handles as void pointers at the V
// boundary. Their exported signatures match the public witty/vt headers;
// all behavior delegates to the translated terminal_c implementation.

module main

import input
import lib_allocator
import osc
import terminal
import terminal_c

fn lib_vt_allocator(raw &lib_allocator.Allocator) ?&lib_allocator.Allocator {
	if isnil(raw) {
		return none
	}
	unsafe {
		return raw
	}
}

@[export: 'ghostty_key_event_new']
fn ghostty_key_event_new_export(allocator &lib_allocator.Allocator, out &voidptr) terminal_c.Result {
	if isnil(out) {
		return .invalid_value
	}
	status, event := terminal_c.key_event_new_alloc(lib_vt_allocator(allocator))
	unsafe {
		*out = voidptr(event)
	}
	return status
}

@[export: 'ghostty_key_event_free']
fn ghostty_key_event_free_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	terminal_c.key_event_free(mut event)
}

@[export: 'ghostty_key_event_set_action']
fn ghostty_key_event_set_action_export(raw voidptr, action input.KeyAction) {
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	event.set_action(action)
}

@[export: 'ghostty_key_event_get_action']
fn ghostty_key_event_get_action_export(raw voidptr) input.KeyAction {
	event := unsafe { &terminal_c.KeyEvent(raw) }
	return event.get_action()
}

@[export: 'ghostty_key_event_set_key']
fn ghostty_key_event_set_key_export(raw voidptr, key input.Key) {
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	event.set_key(key)
}

@[export: 'ghostty_key_event_get_key']
fn ghostty_key_event_get_key_export(raw voidptr) input.Key {
	event := unsafe { &terminal_c.KeyEvent(raw) }
	return event.get_key()
}

@[export: 'ghostty_key_event_set_mods']
fn ghostty_key_event_set_mods_export(raw voidptr, mods u16) {
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	event.set_mods(input.Mods.from_int(mods))
}

@[export: 'ghostty_key_event_get_mods']
fn ghostty_key_event_get_mods_export(raw voidptr) u16 {
	event := unsafe { &terminal_c.KeyEvent(raw) }
	return event.get_mods().int()
}

@[export: 'ghostty_key_event_set_consumed_mods']
fn ghostty_key_event_set_consumed_mods_export(raw voidptr, mods u16) {
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	event.set_consumed_mods(input.Mods.from_int(mods))
}

@[export: 'ghostty_key_event_get_consumed_mods']
fn ghostty_key_event_get_consumed_mods_export(raw voidptr) u16 {
	event := unsafe { &terminal_c.KeyEvent(raw) }
	return event.get_consumed_mods().int()
}

@[export: 'ghostty_key_event_set_composing']
fn ghostty_key_event_set_composing_export(raw voidptr, composing bool) {
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	event.set_composing(composing)
}

@[export: 'ghostty_key_event_get_composing']
fn ghostty_key_event_get_composing_export(raw voidptr) bool {
	event := unsafe { &terminal_c.KeyEvent(raw) }
	return event.get_composing()
}

@[export: 'ghostty_key_event_set_utf8']
fn ghostty_key_event_set_utf8_export(raw voidptr, utf8 &char, len uint) {
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	// The C API borrows this buffer. `tos` constructs the matching non-owning V
	// string view; callers must keep it alive for the event's lifetime.
	event.event.utf8 = if isnil(utf8) { '' } else { unsafe { tos(&u8(utf8), int(len)) } }
}

@[export: 'ghostty_key_event_get_utf8']
fn ghostty_key_event_get_utf8_export(raw voidptr, len &uint) &char {
	event := unsafe { &terminal_c.KeyEvent(raw) }
	if !isnil(len) {
		unsafe {
			*len = uint(event.event.utf8.len)
		}
	}
	if event.event.utf8.len == 0 {
		return &char(unsafe { nil })
	}
	return event.event.utf8.str
}

@[export: 'ghostty_key_event_set_unshifted_codepoint']
fn ghostty_key_event_set_unshifted_codepoint_export(raw voidptr, codepoint u32) {
	mut event := unsafe { &terminal_c.KeyEvent(raw) }
	event.set_unshifted_codepoint(codepoint)
}

@[export: 'ghostty_key_event_get_unshifted_codepoint']
fn ghostty_key_event_get_unshifted_codepoint_export(raw voidptr) u32 {
	event := unsafe { &terminal_c.KeyEvent(raw) }
	return event.get_unshifted_codepoint()
}

@[export: 'ghostty_key_encoder_new']
fn ghostty_key_encoder_new_export(allocator &lib_allocator.Allocator, out &voidptr) terminal_c.Result {
	if isnil(out) {
		return .invalid_value
	}
	status, encoder := terminal_c.key_encoder_new_alloc(lib_vt_allocator(allocator))
	unsafe {
		*out = voidptr(encoder)
	}
	return status
}

@[export: 'ghostty_key_encoder_free']
fn ghostty_key_encoder_free_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut encoder := unsafe { &terminal_c.KeyEncoder(raw) }
	terminal_c.key_encoder_free(mut encoder)
}

@[export: 'ghostty_key_encoder_setopt']
fn ghostty_key_encoder_setopt_export(raw voidptr, option terminal_c.KeyEncoderOption, value voidptr) {
	if isnil(raw) || isnil(value) {
		return
	}
	if !terminal_c.key_encoder_option_valid(option) { return }
	mut encoder := unsafe { &terminal_c.KeyEncoder(raw) }
	match option {
		.cursor_key_application, .keypad_key_application, .ignore_keypad_with_numlock, .alt_esc_prefix, .modify_other_keys_state_2 {
			encoder.setopt(option, terminal_c.KeyEncoderOptionValue(unsafe { *(&bool(value)) }))
		}
		.kitty_flags {
			encoder.setopt(option, terminal_c.KeyEncoderOptionValue(unsafe { *(&u8(value)) }))
		}
		.macos_option_as_alt {
			encoder.setopt(option, terminal_c.KeyEncoderOptionValue(unsafe {
				*(&input.OptionAsAlt(value))
			}))
		}
	}
}

@[export: 'ghostty_key_encoder_encode']
fn ghostty_key_encoder_encode_export(encoder_raw voidptr, event_raw voidptr, out &u8, out_len uint, written &uint) terminal_c.Result {
	if isnil(encoder_raw) || isnil(event_raw) || isnil(written) {
		return .invalid_value
	}
	encoder := unsafe { &terminal_c.KeyEncoder(encoder_raw) }
	event := unsafe { &terminal_c.KeyEvent(event_raw) }
	mut output := if isnil(out) || out_len == 0 {
		[]u8{}
	} else {
		unsafe { out.vbytes(int(out_len)) }
	}
	status, required := encoder.encode(event, mut output)
	unsafe {
		*written = required
	}
	return status
}

@[export: 'ghostty_osc_new']
fn ghostty_osc_new_export(allocator &lib_allocator.Allocator, out &voidptr) terminal_c.Result {
	if isnil(out) {
		return .invalid_value
	}
	status, parser := terminal_c.osc_new_alloc(lib_vt_allocator(allocator))
	unsafe {
		*out = voidptr(parser)
	}
	return status
}

@[export: 'ghostty_osc_free']
fn ghostty_osc_free_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut parser := unsafe { &terminal_c.OscParser(raw) }
	terminal_c.osc_free_alloc(mut parser)
}

@[export: 'ghostty_osc_reset']
fn ghostty_osc_reset_export(raw voidptr) {
	mut parser := unsafe { &terminal_c.OscParser(raw) }
	parser.reset()
}

@[export: 'ghostty_osc_next']
fn ghostty_osc_next_export(raw voidptr, byte u8) {
	mut parser := unsafe { &terminal_c.OscParser(raw) }
	parser.next(byte)
}

@[export: 'ghostty_osc_end']
fn ghostty_osc_end_export(raw voidptr, terminator u8) voidptr {
	mut parser := unsafe { &terminal_c.OscParser(raw) }
	command := parser.end_ptr(terminator) or { return unsafe { nil } }
	return voidptr(command)
}

@[export: 'ghostty_osc_command_type']
fn ghostty_osc_command_type_export(raw voidptr) osc.CommandType {
	if isnil(raw) {
		return .invalid
	}
	command := unsafe { &osc.Command(raw) }
	return command.key()
}

@[export: 'ghostty_osc_command_data']
fn ghostty_osc_command_data_export(raw voidptr, data terminal_c.CommandData, out voidptr) bool {
	if isnil(raw) || isnil(out) || data != .change_window_title_str {
		return false
	}
	command := unsafe { &osc.Command(raw) }
	match command {
		osc.ChangeWindowTitle {
			unsafe {
				*(&voidptr(out)) = voidptr(command.value.str)
			}
		}
		else {
			return false
		}
	}
	return true
}

@[export: 'ghostty_paste_is_safe']
fn ghostty_paste_is_safe_export(data &char, len uint) bool {
	value := if isnil(data) { '' } else { unsafe { tos(&u8(data), int(len)) } }
	return terminal_c.paste_is_safe(value)
}

@[export: 'ghostty_color_rgb_get']
fn ghostty_color_rgb_get_export(color terminal_c.RGB, r &u8, g &u8, b &u8) {
	red, green, blue := terminal_c.rgb_get(color)
	unsafe {
		*r = red
		*g = green
		*b = blue
	}
}

@[export: 'ghostty_sgr_new']
fn ghostty_sgr_new_export(allocator &lib_allocator.Allocator, out &voidptr) terminal_c.Result {
	if isnil(out) {
		return .invalid_value
	}
	status, parser := terminal_c.sgr_new_alloc(lib_vt_allocator(allocator))
	unsafe {
		*out = voidptr(parser)
	}
	return status
}

@[export: 'ghostty_sgr_free']
fn ghostty_sgr_free_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut parser := unsafe { &terminal_c.SgrParser(raw) }
	terminal_c.sgr_free(mut parser)
}

@[export: 'ghostty_sgr_reset']
fn ghostty_sgr_reset_export(raw voidptr) {
	mut parser := unsafe { &terminal_c.SgrParser(raw) }
	parser.reset()
}

@[export: 'ghostty_sgr_set_params']
fn ghostty_sgr_set_params_export(raw voidptr, params &u16, separators &u8, len uint) terminal_c.Result {
	if isnil(raw) || (isnil(params) && len > 0) {
		return .invalid_value
	}
	mut parser := unsafe { &terminal_c.SgrParser(raw) }
	return parser.set_params_raw(params, separators, len)
}

@[export: 'ghostty_sgr_next']
fn ghostty_sgr_next_export(raw voidptr, out &terminal_c.SgrAttributeC) bool {
	if isnil(raw) || isnil(out) {
		return false
	}
	mut parser := unsafe { &terminal_c.SgrParser(raw) }
	attr := parser.next() or { return false }
	unsafe {
		*out = terminal_c.sgr_attribute_cval(attr)
	}
	return true
}

@[export: 'ghostty_sgr_unknown_full']
fn ghostty_sgr_unknown_full_export(unknown terminal_c.SgrUnknownC, out &voidptr) uint {
	ptr, len := terminal_c.sgr_unknown_full(unknown)
	if !isnil(out) {
		unsafe {
			*out = voidptr(ptr)
		}
	}
	return len
}

@[export: 'ghostty_sgr_unknown_partial']
fn ghostty_sgr_unknown_partial_export(unknown terminal_c.SgrUnknownC, out &voidptr) uint {
	ptr, len := terminal_c.sgr_unknown_partial(unknown)
	if !isnil(out) {
		unsafe {
			*out = voidptr(ptr)
		}
	}
	return len
}

@[export: 'ghostty_sgr_attribute_tag']
fn ghostty_sgr_attribute_tag_export(attr terminal_c.SgrAttributeC) terminal.SgrAttributeTag {
	return attr.tag
}

@[export: 'ghostty_sgr_attribute_value']
fn ghostty_sgr_attribute_value_export(attr &terminal_c.SgrAttributeC) voidptr {
	if isnil(attr) {
		return unsafe { nil }
	}
	return voidptr(&attr.value)
}
