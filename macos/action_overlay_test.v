@[has_globals]
module macos

fn test_search_grapheme_debounce_boundary() {
	assert composed_character_count('') == 0
	assert composed_character_count('ab') == 2
	assert composed_character_count('abc') == 3
	assert composed_character_count('a\u0301b') == 2
	assert composed_character_count('👨‍👩‍👧‍👦') == 1
}

fn test_source_key_context_stack_order() {
	mut state := &NativeActionSurface{
		closed: true
	}
	state.set_key_table(0, 'first')
	state.set_key_table(0, 'second')
	assert state.key_tables == ['first', 'second']
	state.set_key_table(1, '')
	assert state.key_tables == ['first']
	state.set_key_table(2, '')
	assert state.key_tables.len == 0
	state.set_key_table(1, '')
	assert state.key_tables.len == 0
	state.set_key_sequence(true, '⌘K')
	state.set_key_sequence(true, '⌘C')
	assert state.key_sequence == ['⌘K', '⌘C']
	state.set_key_sequence(false, '')
	assert state.key_sequence.len == 0
}

__global audit_native_actions = []string{}

fn audit_action_binding(_userdata voidptr, action string) bool {
	audit_native_actions << action
	return true
}

fn test_native_search_editor_and_timer_consumers() {
	app_init()
	view := create_window(640, 480, '')
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{
		binding: audit_action_binding
	})
	board := msg_id(get_class('NSPasteboard'), 'pasteboardWithUniqueName')
	surface.search_pasteboard = board
	defer {
		surface.deinit()
		msg_void(board, 'releaseGlobally')
		close_tab(view)
	}
	audit_native_actions.clear()
	surface.start_search('ab')
	assert surface.search_active
	assert !msg_bool(surface.search_field, 'isBordered')
	assert !msg_bool(surface.search_field, 'drawsBackground')
	assert msg_rect(surface.search_field_plate, 'frame').width == search_field_width
	assert msg_rect(surface.search_bar, 'frame').height == search_panel_height
	assert msg_f64(msg_id(surface.search_plate, 'layer'), 'cornerRadius') == 8
	assert msg_f64(msg_id(surface.search_field_plate, 'layer'), 'cornerRadius') == 6
	assert msg_f64(msg_id(surface.search_bar, 'shadow'), 'shadowBlurRadius') == 4
	assert audit_native_actions.len == 0
	pending := surface.search_timer
	assert msg_bool(pending, 'isValid')
	msg_void(pending, 'retain')
	defer { msg_void(pending, 'release') }
	surface.start_search('abc')
	assert !msg_bool(pending, 'isValid')
	assert audit_native_actions == ['search:abc']
	surface.start_search('')
	assert surface.search_needle == 'abc'
	assert audit_native_actions == ['search:abc']
	surface.search_counts(uint(2), uint(5))
	assert objc_utf8_string(msg_id(surface.search_count, 'stringValue')) == '3/5'
	surface.search_counts(none, uint(0))
	assert objc_utf8_string(msg_id(surface.search_count, 'stringValue')) == '-/0'
	surface.search_counts(uint(0), none)
	assert objc_utf8_string(msg_id(surface.search_count, 'stringValue')) == '1/?'
	// Native control notifications update state through the registered delegate.
	msg_void1(surface.search_field, 'setStringValue:', nsstring('x'))
	action_search_edit(surface.owner, sel('controlTextDidChange:'), nil_obj())
	assert surface.search_needle == 'x'
	msg_void(surface.search_timer, 'fire')
	assert audit_native_actions.last() == 'search:x'
	surface.search_dragging = true
	dragged := objc_rect(8, view_height(view) - search_panel_height - 9,
		surface.search_bar_width, search_panel_height)
	msg_void_rect(surface.search_bar, 'setFrame:', dragged)
	search_drag_end(surface.search_bar, sel('mouseUp:'), nil_obj())
	assert !surface.search_dragging
	assert surface.search_corner == .bottom_left
	assert surface.search_panel_frame().x == search_panel_margin
	controls := msg_id(surface.search_bar, 'subviews')
	for index, name in ['navigate_search:next', 'navigate_search:previous', 'end_search'] {
		button := msg_id_u64(controls, 'objectAtIndex:', u64(4 + index))
		assert objc_utf8_string(msg_id(button, 'className')) == 'WittySearchButton'
		msg_void1(button, 'performClick:', nil_obj())
		assert audit_native_actions.last() == name
	}
	assert audit_native_actions.last() == 'end_search'
	assert !surface.search_active
	assert is_nil(surface.search_field)
	surface.end_search()
	assert audit_native_actions.filter(it == 'end_search').len == 1
	surface.set_progress(1, u8(25))
	assert msg_f64(msg_id(surface.progress_timer, 'fireDate'), 'timeIntervalSinceNow') > 14
	first := surface.progress_timer
	msg_void(first, 'retain')
	defer { msg_void(first, 'release') }
	surface.set_progress(2, none)
	assert !msg_bool(first, 'isValid')
	msg_void(surface.progress_timer, 'fire')
	assert !surface.progress_active
	surface.set_progress(1, u8(25))
	removed := surface.progress_timer
	msg_void(removed, 'retain')
	defer { msg_void(removed, 'release') }
	surface.set_progress(99, u8(25))
	assert !msg_bool(removed, 'isValid')
	assert !surface.progress_active
	assert surface.progress_state == 0
	assert surface.progress == none
	surface.ring_bell()
	assert surface.bell
	surface.begin_key_down()
	assert !surface.bell
	surface.ring_bell()
	surface.focus(true)
	assert !surface.bell
}

fn test_native_find_pasteboard_restores_and_refreshes_search() {
	app_init()
	view := create_window(640, 480, '')
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{
		binding: audit_action_binding
	})
	board := msg_id(get_class('NSPasteboard'), 'pasteboardWithUniqueName')
	surface.search_pasteboard = board
	defer {
		surface.deinit()
		msg_void(board, 'releaseGlobally')
		close_tab(view)
	}
	mime := nsstring('public.utf8-plain-text')
	assert msg_bool2(board, 'setString:forType:', nsstring('needle'), mime)
	audit_native_actions.clear()
	surface.start_search('')
	assert audit_native_actions == ['search:needle']
	editor := search_field_editor(surface.search_field) or { panic('missing search field editor') }
	assert objc_utf8_string(msg_id(editor, 'string')) == 'needle'
	assert C.witty_macos_msg_range(editor, sel('selectedRange')).length == 6

	msg_void(board, 'clearContents')
	assert msg_bool2(board, 'setString:forType:', nsstring('café ✨'), mime)
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	msg_void2(center, 'postNotificationName:object:', nsstring('NSApplicationDidBecomeActiveNotification'),
		shared_app())
	assert audit_native_actions.last() == 'search:café ✨'
	assert objc_utf8_string(msg_id(editor, 'string')) == 'café ✨'
	assert C.witty_macos_msg_range(editor, sel('selectedRange')).length == 6

	msg_void1(surface.search_field, 'setStringValue:', nsstring('another'))
	action_search_edit(surface.owner, sel('controlTextDidChange:'), nil_obj())
	assert objc_utf8_string(msg_id1(board, 'stringForType:', mime)) == 'another'
	surface.end_search()
	surface.start_search('')
	assert audit_native_actions.last() == 'search:another'
	surface.start_search('explicit')
	assert objc_utf8_string(msg_id1(board, 'stringForType:', mime)) == 'explicit'
}
