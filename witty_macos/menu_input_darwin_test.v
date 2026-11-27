module witty_macos

import input

fn test_menu_shortcut_functional_keys_and_unicode() {
	up := menu_shortcut(input.Trigger.parse('ctrl+up')!)?
	assert up.key == '\uF700'
	assert up.modifiers == ns_event_modifier_flag_control
	q := menu_shortcut(input.Trigger.parse('super+shift+q')!)?
	assert q.key == 'q'
	assert q.modifiers == ns_event_modifier_flag_command | ns_event_modifier_flag_shift
	assert menu_shortcut(input.Trigger{key: input.TriggerKeyPhysical{key: .key_a}}) == none
	assert menu_shortcut(input.Trigger{key: input.TriggerKeyCatchAll{}}) == none
	assert menu_shortcut(input.Trigger{key: input.TriggerKeyUnicode{codepoint: 0xd800}}) == none
	assert menu_shortcut(input.Trigger{key: input.TriggerKeyUnicode{codepoint: 0x110000}}) == none
}

fn test_menu_shortcut_unbinding_clears_native_item() {
	item := menu_item()
	defer { msg_void(item, 'release') }
	register_config_menu_item(voidptr(item), 'test-action')
	menu_set_shortcut('test-action', input.Trigger.parse('alt+ctrl+up')!)
	assert objc_utf8_string(msg_id(item, 'keyEquivalent')) == '\uF700'
	assert msg_u64(item, 'keyEquivalentModifierMask') == ns_event_modifier_flag_control | ns_event_modifier_flag_option
	menu_set_shortcut('test-action', none)
	assert objc_utf8_string(msg_id(item, 'keyEquivalent')) == ''
	assert msg_u64(item, 'keyEquivalentModifierMask') == 0
	g_config_menu_items.delete('test-action')
}
