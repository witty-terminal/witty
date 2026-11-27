module witty_macos

fn test_native_tab_movement_clamps_and_floating_toggles() {
	app_init()
	first := create_window(640, 480, 'first')
	mut a := new_action_surface(first, unsafe { nil }, ActionCallbacks{})
	second := new_tab(640, 480, 'second')
	mut b := new_action_surface(second, unsafe { nil }, ActionCallbacks{})
	defer {
		a.deinit()
		b.deinit()
		close_tab(first)
		close_tab(second)
	}
	assert native_window_tabs(second).len == 2
	assert move_native_tab(second, -99)
	assert native_window_tabs(second)[0] == view_window(second)
	assert move_native_tab(second, 99)
	assert native_window_tabs(second)[1] == view_window(second)
	assert move_native_tab(second, 0)
	float_native_window(second, 0)
	assert msg_i64(view_window(second), 'level') == 3
	float_native_window(second, 2)
	assert msg_i64(view_window(second), 'level') == 0
	float_native_window(second, 2)
	assert msg_i64(view_window(second), 'level') == 3
	float_native_window(second, 1)
	assert msg_i64(view_window(second), 'level') == 0
}

fn test_native_default_floating_level_uses_source_defaults_key() {
	app_init()
	defaults := msg_id(get_class('NSUserDefaults'), 'standardUserDefaults')
	original := msg_id1(defaults, 'objectForKey:', nsstring('TerminalDefaultLevel'))
	msg_void(original, 'retain')
	defer {
		if is_nil(original) {
			msg_void1(defaults, 'removeObjectForKey:', nsstring('TerminalDefaultLevel'))
		} else {
			msg_void2(defaults, 'setObject:forKey:', original, nsstring('TerminalDefaultLevel'))
			msg_void(original, 'release')
		}
	}
	item := g_config_menu_items['toggle_window_float_on_top'] or { panic('missing source float menu') }
	msg_void_u64(item, 'setState:', 1)
	save_native_default_level()
	view := create_window(640, 480, 'new')
	assert msg_i64(view_window(view), 'level') == 3
	msg_void_u64(item, 'setState:', 0)
	save_native_default_level()
	assert is_nil(msg_id1(defaults, 'objectForKey:', nsstring('TerminalDefaultLevel')))
	close_tab(view)
}
