module main

import configpkg
import input
import macos

fn sync_config_menu(config &configpkg.Config) {
	macos.sync_native_updater_config(native_update_config(config))
	for action_text in macos.menu_actions() {
		action := input.Action.parse(action_text) or { continue }
		macos.menu_set_shortcut(action_text, config.keybind.set.get_trigger(action))
	}
	mut shortcuts := [9]string{}
	for index in 0 .. shortcuts.len {
		action := input.Action(input.ActionGotoTab{value: uint(index + 1)})
		if trigger := config.keybind.set.get_trigger(action) {
			shortcuts[index] = macos.command_shortcut_symbols(trigger).join('')
		}
	}
	macos.set_native_tab_shortcuts(shortcuts)
}
