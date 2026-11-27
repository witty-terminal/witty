module main

import apprt
import input
import witty_macos as macos
fn install_native_input_callbacks() {
	macos.set_input_client_callbacks(macos.InputClientCallbacks{
		begin_key_down: native_begin_key_down
		translation_mods: native_translation_mods
		key: native_key
		binding: native_binding
		preedit: native_preedit
		text: native_text
		selection: native_selection
		has_selection: native_has_selection
		screen_text: native_screen_text
		font: native_selection_font
		ime_rect: native_ime_rect
		binding_action: native_binding_action
	})
}

fn native_translation_mods(userdata voidptr, mods int) int {
	state := state_from_userdata(userdata) or { return mods }
	if state.closed || state.surface == unsafe { nil } { return mods }
	return apprt.ghostty_surface_key_translation_mods(state.surface, mods)
}

// NSEvent.ghosttyKeyEvent uses the original physical event and the translated
// event's flags only for consumed modifiers. This preserves hidden AppKit bits.
fn native_key_event(event voidptr, translation_event voidptr, action input.KeyAction, text ?string, composing bool) apprt.CAPIKeyEvent {
	mods := macos.event_mods(event)
	translation_mods := macos.event_mods(translation_event)
	unshifted := if macos.event_type(event) == 10 || macos.event_type(event) == 11 { macos.event_characters(event, 0).runes() } else { []rune{} }
	return apprt.CAPIKeyEvent{
		action: action
		mods: mods
		consumed_mods: translation_mods & ~(2 | 8 | 128 | 512)
		keycode: macos.event_keycode(event)
		text: text
		unshifted_codepoint: if unshifted.len > 0 { u32(unshifted[0]) } else { 0 }
		composing: composing
	}
}

fn native_key(userdata voidptr, event voidptr, translation_event voidptr, action input.KeyAction, text ?string, composing bool) bool {
	mut state := state_from_userdata(userdata) or { return false }
	if state.closed || state.surface == unsafe { nil } { return false }
	return apprt.ghostty_surface_key(mut state.surface, native_key_event(event, translation_event, action, text, composing))
}

fn native_binding(userdata voidptr, event voidptr, text string) ?u32 {
	mut state := state_from_userdata(userdata) or { return none }
	if state.closed || state.surface == unsafe { nil } { return none }
	return apprt.ghostty_surface_key_binding_flags(mut state.surface, native_key_event(event, event, .press, text, false))
}

fn native_preedit(userdata voidptr, text ?string) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } { apprt.ghostty_surface_preedit(mut state.surface, text) }
}

fn native_text(userdata voidptr, text string) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } { apprt.ghostty_surface_text(mut state.surface, text) }
}

fn native_selection(userdata voidptr) ?macos.NativeText {
	mut state := state_from_userdata(userdata) or { return none }
	if state.closed || state.surface == unsafe { nil } { return none }
	mut text := apprt.CAPIText{}
	if !apprt.ghostty_surface_read_selection(mut state.surface, mut text) { return none }
	defer { apprt.ghostty_surface_free_text(mut text) }
	return macos.NativeText{text: text.text or { '' }, offset_start: text.offset_start, offset_len: text.offset_len, tl_px_x: text.tl_px_x, tl_px_y: text.tl_px_y}
}

fn native_has_selection(userdata voidptr) bool {
	state := state_from_userdata(userdata) or { return false }
	return !state.closed && state.surface != unsafe { nil } && apprt.ghostty_surface_has_selection(state.surface)
}

fn native_screen_text(userdata voidptr) string {
	mut state := state_from_userdata(userdata) or { return '' }
	if state.closed || state.surface == unsafe { nil } { return '' }
	mut text := apprt.CAPIText{}
	selection := apprt.CAPISelection{tl: apprt.CAPIPoint{tag: .screen, coord_tag: .top_left}, br: apprt.CAPIPoint{tag: .screen, coord_tag: .bottom_right}}
	if !apprt.ghostty_surface_read_text(mut state.surface, selection, mut text) { return '' }
	defer { apprt.ghostty_surface_free_text(mut text) }
	return text.text or { '' }
}

fn native_selection_font(userdata voidptr) voidptr {
	state := state_from_userdata(userdata) or { return unsafe { nil } }
	if state.closed || state.surface == unsafe { nil } { return unsafe { nil } }
	return apprt.ghostty_surface_quicklook_font(state.surface)
}

fn native_ime_rect(userdata voidptr) macos.NativeImeRect {
	state := state_from_userdata(userdata) or { return macos.NativeImeRect{} }
	if state.closed || state.surface == unsafe { nil } { return macos.NativeImeRect{} }
	mut rect := macos.NativeImeRect{}
	apprt.ghostty_surface_ime_point(state.surface, &rect.x, &rect.y, &rect.width, &rect.height)
	size := apprt.ghostty_surface_size(state.surface)
	scale := macos.view_backing_scale(state.view)
	rect.cell_width = f64(size.cell_width_px) / scale
	rect.cell_height = f64(size.cell_height_px) / scale
	return rect
}

fn native_binding_action(userdata voidptr, action string) bool {
	mut state := state_from_userdata(userdata) or { return false }
	if state.closed || state.surface == unsafe { nil } { return false }
	return apprt.ghostty_surface_binding_action(mut state.surface, action)
}
