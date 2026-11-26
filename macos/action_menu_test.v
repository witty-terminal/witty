@[has_globals]
module macos

import input

__global source_menu_bindings = []string{}

fn source_menu_binding(_userdata voidptr, action string) bool {
	source_menu_bindings << action
	return true
}

fn test_native_menu_bindings_are_live_core_actions() {
	app_init()
	for action in menu_actions() {
		_ := input.Action.parse(action) or { panic('${action}: ${err}') }
	}
	set_input_client_callbacks(InputClientCallbacks{ binding_action: source_menu_binding })
	defer { set_input_client_callbacks(InputClientCallbacks{}) }
	view := create_window(640, 480, 'menu')
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	board := msg_id(get_class('NSPasteboard'), 'pasteboardWithUniqueName')
	surface.search_pasteboard = board
	defer {
		surface.deinit()
		msg_void(board, 'releaseGlobally')
		close_tab(view)
	}
	item := g_config_menu_items['close_tab:right'] or { panic('missing close-right consumer') }
	action_menu_binding(view, nil_obj(), item)
	assert source_menu_bindings.last() == 'close_tab:right'
	readonly := g_config_menu_items['toggle_readonly'] or { panic('missing readonly consumer') }
	surface.set_readonly(true)
	assert action_menu_validate(view, nil_obj(), readonly)
	assert msg_i64(readonly, 'state') == 1
	find := g_config_menu_items['end_search'] or { panic('missing find consumer') }
	assert !action_menu_validate(view, nil_obj(), find)
	surface.start_search('needle')
	assert action_menu_validate(view, nil_obj(), find)
}
