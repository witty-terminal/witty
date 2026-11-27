@[has_globals]
module witty_macos

__global g_native_application_action fn (string) bool

pub fn set_native_application_action(callback fn (string) bool) {
	g_native_application_action = callback
}

// Source SurfaceView/AppDelegate menu consumers share the core binding producer.
fn register_native_action_menu() {
	cls := get_class('VTTerminalView')
	add_method(cls, 'vtNativeBinding:', voidptr(action_menu_binding), 'v@:@')
	add_method(cls, 'validateMenuItem:', voidptr(action_menu_validate), 'B@:@')
	add_method(get_class('VTAppDelegate'), 'vtNativeApplicationAction:', voidptr(action_menu_application), 'v@:@')
	add_method(get_class('VTAppDelegate'), 'vtDefaultLevel:', voidptr(action_menu_default_level), 'v@:@')
	add_method(get_class('VTAppDelegate'), 'validateMenuItem:', voidptr(action_menu_app_validate), 'B@:@')
	add_method(get_class('VTAppDelegate'), 'vtSecureEntry:', voidptr(action_menu_secure), 'v@:@')
}

fn action_menu_binding(self ObjId, _cmd Sel, sender ObjId) {
	action := objc_utf8_string(msg_id(sender, 'representedObject'))
	if g_input_callbacks.binding_action != unsafe { nil } {
		g_input_callbacks.binding_action(view_userdata(self), action)
	}
}

fn action_menu_validate(self ObjId, _cmd Sel, item ObjId) bool {
	action := objc_utf8_string(msg_id(item, 'representedObject'))
	surface := g_action_surfaces[u64(self)] or { return true }
	if action == 'toggle_window_float_on_top' && !msg_bool1(view_window(voidptr(self)), 'isKindOfClass:', get_class('VTTerminalWindow')) {
		return false
	}
	match action {
		'end_search' { return surface.search_active }
		'toggle_readonly' {
			msg_void_u64(item, 'setState:', u64(if surface.readonly { 1 } else { 0 }))
			return true
		}
		'toggle_window_float_on_top' {
			msg_void_u64(item, 'setState:', u64(if msg_i64(view_window(voidptr(self)), 'level') == 3 {
				1
			} else {
				0
			}))
			return true
		}
		else { return true }
	}
}

fn action_menu_application(_self ObjId, _cmd Sel, sender ObjId) {
	if g_native_application_action != unsafe { nil } {
		g_native_application_action(objc_utf8_string(msg_id(sender, 'representedObject')))
	}
}

fn source_application_menu(menu ObjId, title string, action string) {
	item := menu_add_item(menu, title, 'vtNativeApplicationAction:', '')
	msg_void1(item, 'setTarget:', g_delegate)
	msg_void1(item, 'setRepresentedObject:', nsstring(action))
	register_config_menu_item(voidptr(item), action)
}

fn action_menu_default_level(_self ObjId, _cmd Sel, _sender ObjId) { save_native_default_level() }

fn action_menu_app_validate(_self ObjId, _cmd Sel, item ObjId) bool {
	if msg_id(item, 'action') == sel('vtDefaultLevel:') {
		window := msg_id(shared_app(), 'keyWindow')
		return msg_bool1(window, 'isKindOfClass:', get_class('VTTerminalWindow'))
	}
	action := objc_utf8_string(msg_id(item, 'representedObject'))
	if action in ['undo', 'redo'] {
		manager := native_undo_manager()
		available := msg_bool(manager, if action == 'undo' { 'canUndo' } else { 'canRedo' })
		title := if action == 'undo' { 'Undo' } else { 'Redo' }
		name := objc_utf8_string(msg_id(manager, if action == 'undo' {
			'undoActionName'
		} else {
			'redoActionName'
		}))
		msg_void1(item, 'setTitle:', nsstring(if available { '${title} ${name}' } else { title }))
		return available
	}
	return true
}

fn action_menu_secure(_self ObjId, _cmd Sel, _sender ObjId) { secure_set_global(2) }

fn source_binding_menu(menu ObjId, title string, action string) {
	item := menu_add_item(menu, title, 'vtNativeBinding:', '')
	msg_void1(item, 'setRepresentedObject:', nsstring(action))
	register_config_menu_item(voidptr(item), action)
}

fn install_native_action_menu(app_menu ObjId, file_menu ObjId, edit_menu ObjId, view_menu ObjId, window_menu ObjId) {
	register_native_action_menu()
	source_application_menu(file_menu, 'New Window', 'new_window')
	source_application_menu(file_menu, 'Close All Windows', 'close_all_windows')
	source_application_menu(edit_menu, 'Undo', 'undo')
	source_application_menu(edit_menu, 'Redo', 'redo')
	source_application_menu(view_menu, 'Quick Terminal', 'toggle_quick_terminal')
	source_application_menu(view_menu, 'Show or Hide All Windows', 'toggle_visibility')
	secure := menu_add_item(app_menu, 'Secure Keyboard Entry', 'vtSecureEntry:', '')
	msg_void1(secure, 'setTarget:', g_delegate)
	g_config_menu_items['toggle_secure_input'] = secure
	menu_add_separator(file_menu)
	for pair in [['Close Other Tabs', 'close_tab:other'],
		['Close Tabs to the Right', 'close_tab:right'], ['Close Window', 'close_window'],
		['Change Terminal Title…', 'prompt_surface_title'],
		['Change Tab Title…', 'prompt_tab_title']] {
		source_binding_menu(file_menu, pair[0], pair[1])
	}
	menu_add_separator(edit_menu)
	for pair in [['Find…', 'start_search'], ['Find Next', 'navigate_search:next'],
		['Find Previous', 'navigate_search:previous'], ['Hide Find', 'end_search']] {
		source_binding_menu(edit_menu, pair[0], pair[1])
	}
	menu_add_separator(view_menu)
	for pair in [['Command Palette', 'toggle_command_palette'], ['Read-Only Mode', 'toggle_readonly'],
		['Terminal Inspector', 'inspector:toggle'], ['Reset Window Size', 'reset_window_size'],
		['Toggle Background Opacity', 'toggle_background_opacity']] {
		source_binding_menu(view_menu, pair[0], pair[1])
	}
	menu_add_separator(window_menu)
	for pair in [['Move Tab Left', 'move_tab:-1'], ['Move Tab Right', 'move_tab:1'],
		['Previous Window', 'goto_window:previous'], ['Next Window', 'goto_window:next'],
		['Float on Top', 'toggle_window_float_on_top']] {
		source_binding_menu(window_menu, pair[0], pair[1])
	}
	default_level := menu_add_item(window_menu, 'Use As Default', 'vtDefaultLevel:', '')
	msg_void1(default_level, 'setTarget:', g_delegate)
}
