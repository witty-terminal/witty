@[has_globals]
module witty_macos

__global native_published_titles = []string{}
fn native_test_title(_data voidptr, title string) {
	native_published_titles << title
}

fn test_native_title_timers_coalesce_and_preserve_user_override() {
	app_init()
	view := create_window(640, 480, '')
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{
		title: native_test_title
	})
	defer {
		surface.deinit()
		close_tab(view)
	}
	native_published_titles.clear()
	surface.set_title('old')
	first := surface.title_timer
	surface.set_title('latest')
	assert !msg_bool(first, 'isValid')
	assert msg_f64(msg_id(surface.title_timer, 'fireDate'), 'timeIntervalSinceNow') > 0.03
	msg_void(surface.title_timer, 'fire')
	assert surface.title == 'latest'
	assert native_published_titles == ['latest']
	assert is_nil(surface.title_fallback)
	// Real native sheet completion content is consumed without displaying a dialog.
	field := msg_id_rect(alloc('NSTextField'), 'initWithFrame:', objc_rect(0, 0, 250, 24))
	msg_void1(field, 'setStringValue:', nsstring('custom'))
	prompt := &NativeTitlePrompt{
		surface:  surface
		field:    field
		response: 1000
	}
	title_prompt_complete(voidptr(prompt))
	assert surface.title == 'custom'
	assert (surface.terminal_title or { '' }) == 'latest'
	surface.set_title('new terminal')
	msg_void(surface.title_timer, 'fire')
	assert surface.title == 'custom'
	assert (surface.terminal_title or { '' }) == 'new terminal'
	clear_field := msg_id_rect(alloc('NSTextField'), 'initWithFrame:', objc_rect(0, 0, 250, 24))
	clear := &NativeTitlePrompt{
		surface:  surface
		field:    clear_field
		response: 1000
	}
	title_prompt_complete(voidptr(clear))
	msg_void(surface.title_timer, 'fire')
	assert surface.title == 'new terminal'
	assert surface.terminal_title == none
}
