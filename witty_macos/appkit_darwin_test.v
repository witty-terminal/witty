module witty_macos

fn test_metal_gpu_family_values_match_metal_api() {
	assert mtl_gpu_family_apple3 == 1003
	assert mtl_gpu_family_apple10 == 1010
}

fn test_modifier_key_action() {
	assert modifier_key_action(0x38, ns_event_modifier_flag_shift)? == .press
	assert modifier_key_action(0x38, 0)? == .release
	assert modifier_key_action(0x3b, ns_event_modifier_flag_control)? == .press
	assert modifier_key_action(0x3a, ns_event_modifier_flag_option)? == .press
	assert modifier_key_action(0x37, ns_event_modifier_flag_command)? == .press
	assert modifier_key_action(0x39, ns_event_modifier_flag_caps_lock)? == .press
	assert modifier_key_action(0x39, 0)? == .release
	assert modifier_key_action(0x00, 0) == none
}

fn test_modifier_key_action_right_side_uses_device_mask() {
	assert modifier_key_action(0x3c, ns_event_modifier_flag_shift | nx_device_rshift_key_mask)? == .press
	assert modifier_key_action(0x3c, ns_event_modifier_flag_shift)? == .release
	assert modifier_key_action(0x3e, ns_event_modifier_flag_control | nx_device_rctl_key_mask)? == .press
	assert modifier_key_action(0x3e, ns_event_modifier_flag_control)? == .release
	assert modifier_key_action(0x3d, ns_event_modifier_flag_option | nx_device_ralt_key_mask)? == .press
	assert modifier_key_action(0x3d, ns_event_modifier_flag_option)? == .release
	assert modifier_key_action(0x36, ns_event_modifier_flag_command | nx_device_rcmd_key_mask)? == .press
	assert modifier_key_action(0x36, ns_event_modifier_flag_command)? == .release
}

fn test_input_mods_preserves_c_abi_bits() {
	mods := input_mods(ns_event_modifier_flag_shift | ns_event_modifier_flag_control | ns_event_modifier_flag_option | ns_event_modifier_flag_command | ns_event_modifier_flag_caps_lock | nx_device_rshift_key_mask | nx_device_rctl_key_mask | nx_device_ralt_key_mask | nx_device_rcmd_key_mask)
	assert mods.int() == u16(0x3df)
}

fn test_scroll_momentum_matches_nsevent_phase_values() {
	assert scroll_momentum(0) == .none_
	assert scroll_momentum(1) == .began
	assert scroll_momentum(2) == .stationary
	assert scroll_momentum(4) == .changed
	assert scroll_momentum(8) == .ended
	assert scroll_momentum(16) == .cancelled
	assert scroll_momentum(32) == .may_begin
	assert scroll_momentum(3) == .none_
}
