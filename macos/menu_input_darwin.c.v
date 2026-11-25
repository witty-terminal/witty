module macos

import input

#insert "@VMODROOT/macos/menu_input_darwin.h"

fn C.witty_macos_writing_key_equivalent(code u16, command bool) ObjId

// Ghostty.Input.keyboardShortcut and AppDelegate.syncMenuShortcut. The menu
// stores its action so later native menu additions share the same conversion.
pub struct MenuShortcut {
pub:
	key       string
	modifiers u64
}

pub fn register_config_menu_item(item voidptr, action string) {
	if !is_nil(item) {
		g_config_menu_items[action] = ObjId(item)
	}
}

pub fn menu_actions() []string {
	return g_config_menu_items.keys()
}

pub fn menu_shortcut(trigger input.Trigger) ?MenuShortcut {
	key := match trigger.key {
		input.TriggerKeyPhysical {
			match trigger.key.key {
				.arrow_up { '\uF700' }
				.arrow_down { '\uF701' }
				.arrow_left { '\uF702' }
				.arrow_right { '\uF703' }
				.home { '\uF729' }
				.end { '\uF72B' }
				.delete, .backspace { '\x7f' }
				.page_up { '\uF72C' }
				.page_down { '\uF72D' }
				.escape { '\x1b' }
				.enter { '\r' }
				.tab { '\t' }
				.space { ' ' }
				else { return none }
			}
		}
		input.TriggerKeyUnicode {
			cp := trigger.key.codepoint
			if cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) {
				return none
			}
			rune(cp).str()
		}
		input.TriggerKeyCatchAll { return none }
	}
	return MenuShortcut{ key: key, modifiers: event_modifier_flags(int(trigger.mods.int())) }
}

pub fn menu_set_shortcut(action string, trigger ?input.Trigger) {
	item := g_config_menu_items[action] or { return }
	mut equivalent := ''
	mut modifiers := u64(0)
	if value := trigger {
		if shortcut := menu_shortcut(value) {
			equivalent = shortcut.key
			modifiers = shortcut.modifiers
		}
	}
	msg_void1(item, 'setKeyEquivalent:', nsstring(equivalent))
	msg_void_u64(item, 'setKeyEquivalentModifierMask:', modifiers)
}

// Ghostty.eventModifierFlags intentionally maps only these four public flags.
pub fn event_modifier_flags(mods int) u64 {
	mut flags := u64(0)
	if mods & 1 != 0 { flags |= ns_event_modifier_flag_shift }
	if mods & 2 != 0 { flags |= ns_event_modifier_flag_control }
	if mods & 4 != 0 { flags |= ns_event_modifier_flag_option }
	if mods & 8 != 0 { flags |= ns_event_modifier_flag_command }
	return flags
}

// KeyboardShortcut+Extension.keyList / description used by key-sequence caps.
pub fn shortcut_description(trigger input.Trigger) ?string {
	shortcut := menu_shortcut(trigger) or { return none }
	return shortcut_symbols(shortcut.key, trigger.mods).join('')
}

// Palette labels also resolve physical writing-system keys through the current
// keyboard layout. The command modifier can select a different layout table.
pub fn command_shortcut_symbols(trigger input.Trigger) []string {
	if trigger.key is input.TriggerKeyPhysical {
		physical := trigger.key.key
		if physical == .delete {
			return shortcut_symbols('\uF728', trigger.mods)
		}
		if int(physical) >= int(input.Key.backquote) && int(physical) <= int(input.Key.slash) {
			for entry in input.keycodes_entries {
				if entry.key == physical && entry.native != 0xffff {
					key := C.witty_macos_writing_key_equivalent(u16(entry.native), trigger.mods.super_())
					if !is_nil(key) { return shortcut_symbols(objc_utf8_string(key), trigger.mods) }
					break
				}
			}
			return []string{}
		}
	}
	shortcut := menu_shortcut(trigger) or { return []string{} }
	return shortcut_symbols(shortcut.key, trigger.mods)
}

fn shortcut_symbols(key string, modifiers input.Mods) []string {
	mut parts := []string{}
	mods := int(modifiers.int())
	if mods & 2 != 0 { parts << '⌃' }
	if mods & 4 != 0 { parts << '⌥' }
	if mods & 1 != 0 { parts << '⇧' }
	if mods & 8 != 0 { parts << '⌘' }
	parts << match key {
		'\r' { '⏎' }
		'\x1b' { '⎋' }
		'\x7f' { '⌫' }
		'\uF728' { '⌦' }
		' ' { '␣' }
		'\t' { '⇥' }
		'\uF700' { '▲' }
		'\uF701' { '▼' }
		'\uF702' { '◀' }
		'\uF703' { '▶' }
		'\uF72C' { '↑' }
		'\uF72D' { '↓' }
		'\uF729' { '⤒' }
		'\uF72B' { '⤓' }
		else { objc_utf8_string(msg_id(nsstring(key), 'uppercaseString')) }
	}
	return parts
}
