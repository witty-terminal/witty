module ui2_runtime

import apprt
import gg
import input
import log
import math
import sokol.sapp
import ui2

fn physical_key(code gg.KeyCode) input.Key {
	n := int(code)
	name := match true {
		n >= 65 && n <= 90 { 'key_${u8(n + 32).ascii_str()}' }
		n >= 48 && n <= 57 { 'digit_${n - 48}' }
		n >= 320 && n <= 329 { 'numpad_${n - 320}' }
		else {
			match code.str() {
				'left', 'right', 'up', 'down' { 'arrow_${code}' }
				'left_bracket' { 'bracket_left' }
				'right_bracket' { 'bracket_right' }
				'apostrophe' { 'quote' }
				'grave_accent' { 'backquote' }
				'left_shift' { 'shift_left' }
				'right_shift' { 'shift_right' }
				'left_control' { 'control_left' }
				'right_control' { 'control_right' }
				'left_alt' { 'alt_left' }
				'right_alt' { 'alt_right' }
				'left_super' { 'meta_left' }
				'right_super' { 'meta_right' }
				'menu' { 'context_menu' }
				'kp_decimal', 'kp_divide', 'kp_multiply', 'kp_subtract',
				'kp_add', 'kp_enter', 'kp_equal' {
					'numpad_${code.str()[3..]}'
				}
				else { code.str() }
			}
		}
	}
	return input.key_from_name(name) or { input.Key.unidentified }
}

fn key_event(event &gg.Event) input.KeyEvent {
	code := int(event.key_code)
	unshifted := if code >= 65 && code <= 90 {
		u32(code + 32)
	} else if code >= 32 && code <= 96 {
		u32(code)
	} else {
		u32(0)
	}
	return input.KeyEvent{
		key:                 physical_key(event.key_code)
		action:              if event.typ == .key_up {
			.release
		} else if event.key_repeat {
			.repeat
		} else {
			.press
		}
		mods:                input.Mods.from_int(u16(event.modifiers & 0x0f))
		unshifted_codepoint: unshifted
	}
}

fn (mut app App) dispatch_key(event input.KeyEvent) {
	if app.core.key_event(mut app.runtime, event) { return }
	if current := app.active_pane() {
		mut pane := unsafe { current }
		pane.surface.key_callback(event) or { log.warn(err.msg()) }
	}
}

fn (mut app App) flush_pending_key(text string) {
	if mut pending := app.pending_key {
		app.pending_key = none
		pending.utf8 = text
		app.dispatch_key(pending)
	}
}

fn (app &App) pane_at(x f64, y f64) ?&Pane {
	if app.tabs.len == 0 { return none }
	tab := &app.tabs[app.active_tab]
	mut iterator := tab.tree.iterator()
	for {
		entry := iterator.next() or { break }
		if zoomed := tab.tree.zoomed {
			if entry.handle != zoomed { continue }
		}
		frame := entry.view.frame
		if x >= frame.x && y >= frame.y && x < frame.x + frame.width && y < frame.y + frame.height {
			return entry.view
		}
	}
	return none
}

fn window_event(event &gg.Event) bool {
	mut app := g_app
	if !app.ready { return false }
	if event.typ != .char { app.flush_pending_key('') }
	match event.typ {
		.focused, .unfocused {
			app.focused = event.typ == .focused
			app.core.focus_event(app.focused)
			app.apply_focus()
			if !app.focused {
				app.mouse_buttons = 0
				app.mouse_pane = 0
			}
			return false
		}
		.quit_requested {
			if app.core.needs_confirm_quit() {
				sapp.cancel_quit()
				app.confirm_close()
				return true
			}
			return false
		}
		else {}
	}
	if event.typ == .key_down && event.key_code == .escape {
		if app.dialog != none || app.palette || app.context_menu != none {
			app.dialog = none
			app.palette = false
			app.context_menu = none
			ui2.focus('')
			return true
		}
	}
	if app.dialog != none || app.palette || app.context_menu != none { return false }
	if event.typ in [.key_down, .key_up, .char] {
		if current := app.active_pane() {
			if current.search && ui2.focused_id() == 'find-query' {
				if event.typ == .key_down && event.key_code == .escape {
					mut pane := unsafe { current }
					pane.end_find()
					return true
				}
				return false
			}
		}
		match event.typ {
			.key_down {
				mods := input.Mods.from_int(u16(event.modifiers & 0x0f))
				if (mods.ctrl() && !mods.alt()) || mods.super_() || event.key_code == .escape {
					app.dispatch_key(key_event(event))
				} else {
					app.pending_key = key_event(event)
				}
			}
			.key_up { app.dispatch_key(key_event(event)) }
			.char {
				if event.char_code >= 32 && event.char_code != 127 {
					text := rune(event.char_code).str()
					if _ := app.pending_key {
						app.flush_pending_key(text)
					} else if event.modifiers & 10 == 0 {
						app.dispatch_key(input.KeyEvent{ utf8: text })
					}
				}
			}
			else {}
		}
		return true
	}
	if event.typ !in [.mouse_move, .mouse_down, .mouse_up, .mouse_scroll] { return false }
	x, y := f64(event.mouse_x), f64(event.mouse_y)
	if app.over_find(x, y) { return false }
	mut pane := if app.mouse_buttons != 0 {
		app.pane_by_id(app.mouse_pane) or { return false }
	} else {
		app.pane_at(x, y) or { return false }
	}
	if event.typ == .mouse_down {
		ui2.focus('')
		app.focus_pane_id(pane.id)
		if event.mouse_button == .right && !pane.surface.mouse_captured() {
			bounds := ui2.bounds()
			app.context_menu = ui2.rect(math.max(0, math.min(x, bounds.width - 180)),
				math.max(0, math.min(y, bounds.height - 160)), 180, 160)
			return true
		}
		app.mouse_pane = pane.id
		app.mouse_buttons |= u32(1) << int(event.mouse_button)
	}
	scale := pane.host.content_scale.x
	pos := apprt.CursorPos{ x: f32(x - pane.frame.x) * scale, y: f32(y - pane.frame.y) * scale }
	mods := input.Mods.from_int(u16(event.modifiers & 0x0f))
	pane.host.cursor_pos = pos
	pane.surface.cursor_pos_callback(pos, mods) or { log.warn(err.msg()) }
	if event.typ == .mouse_move { sapp.set_mouse_cursor(pane.mouse_cursor) }
	if event.typ in [.mouse_down, .mouse_up] {
		state := if event.typ == .mouse_down { input.MouseButtonState.press } else { .release }
		button := match event.mouse_button {
			.left { input.MouseButton.left }
			.middle { input.MouseButton.middle }
			.right { input.MouseButton.right }
			else { input.MouseButton.unknown }
		}
		pane.surface.mouse_button_callback(state, button, mods) or { log.warn(err.msg()) }
		if event.typ == .mouse_up { app.mouse_buttons &= ~(u32(1) << int(event.mouse_button)) }
	} else if event.typ == .mouse_scroll {
		pane.surface.scroll_callback(f64(event.scroll_x), f64(event.scroll_y), input.ScrollMods{}) or {
			log.warn(err.msg())
		}
	}
	return true
}
