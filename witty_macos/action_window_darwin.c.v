@[has_globals]
module witty_macos

// Ghostty.App.{moveTab,gotoWindow,toggleFloatWindow,toggleVisibility,
// toggleMaximize} and their TerminalController/AppDelegate consumers.
__global (
	g_action_hidden_windows []&NativeWeakObject
	g_action_hidden_key     &NativeWeakObject
	g_action_hidden         bool
)

fn action_terminal_window(window ObjId) bool {
	for _, surface in g_action_surfaces {
		if !surface.closed && view_window(surface.view) == window { return true }
	}
	return false
}

pub fn native_window_tabs(view voidptr) []voidptr {
	window := view_window(view)
	tabs := msg_id(msg_id(window, 'tabGroup'), 'windows')
	if is_nil(tabs) { return [window] }
	mut result := []voidptr{}
	for i in 0 .. int(msg_u64(tabs, 'count')) {
		result << msg_id_u64(tabs, 'objectAtIndex:', u64(i))
	}
	return result
}

pub fn move_native_tab(view voidptr, amount int) bool {
	window := view_window(view)
	group := msg_id(window, 'tabGroup')
	tabs := native_window_tabs(view)
	if tabs.len <= 1 { return false }
	if amount == 0 { return true }
	selected := msg_id(group, 'selectedWindow')
	index := tabs.index(selected)
	if index < 0 { return true }
	final_index := if amount < 0 {
		index - int(if -amount < index { -amount } else { int(index) })
	} else {
		index + int(if amount < tabs.len - 1 - index {
			amount
		} else {
			int(tabs.len - 1 -
				index)
		})
	}
	if final_index == index { return true }
	target := tabs[final_index]
	msg_void(selected, 'retain')
	msg_void(target, 'retain')
	defer {
		msg_void(selected, 'release')
		msg_void(target, 'release')
	}
	if C.witty_action_os_major() >= 26 {
		if config := native_window_data(window) {
			if config.tabs_tahoe {
				msg_void1(group, 'removeWindow:', selected)
				C.witty_action_add_tab(target, selected, if amount < 0 { -1 } else { 1 })
				msg_void(selected, 'retain')
				dispatch_main(action_make_key, voidptr(selected))
				return true
			}
		}
	}
	msg_void(get_class('NSAnimationContext'), 'beginGrouping')
	msg_void_f64(msg_id(get_class('NSAnimationContext'), 'currentContext'), 'setDuration:', 0)
	msg_void1(group, 'removeWindow:', selected)
	C.witty_action_add_tab(target, selected, if amount < 0 { -1 } else { 1 })
	msg_void(selected, 'makeKeyWindow')
	msg_void(get_class('NSAnimationContext'), 'endGrouping')
	refresh_tab_labels(selected)
	return true
}

pub fn goto_native_window(direction int) ?voidptr {
	windows := msg_id(shared_app(), 'windows')
	mut candidates := []ObjId{}
	for i in 0 .. int(msg_u64(windows, 'count')) {
		window := msg_id_u64(windows, 'objectAtIndex:', u64(i))
		if !action_terminal_window(window) || !msg_bool(window, 'isVisible') || msg_bool(window, 'isMiniaturized') {
			continue
		}
		group := msg_id(window, 'tabGroup')
		if !is_nil(group) && msg_id(group, 'selectedWindow') != window {
			continue
		}
		candidates << window
	}
	if candidates.len <= 1 { return none }
	mut start := 0
	mut found_key := false
	for i, window in candidates {
		if msg_bool(window, 'isKeyWindow') {
			start = i
			found_key = true
			break
		}
	}
	if !found_key {
		for i, window in candidates {
			if msg_bool(window, 'isMainWindow') {
				start = i
				break
			}
		}
	}
	step := if direction == 1 {
		1
	} else if direction == 0 {
		-1
	} else {
		return none
	}
	mut index := (start + step + candidates.len) % candidates.len
	for index != start {
		candidate := candidates[index]
		if msg_bool(candidate, 'isVisible') && !msg_bool(candidate, 'isMiniaturized') {
			msg_void1(candidate, 'makeKeyAndOrderFront:', nil_obj())
			for _, surface in g_action_surfaces {
				if !surface.closed && surface.focused && view_window(surface.view) == candidate {
					move_focus(surface.view, unsafe { nil }, none)
					return surface.view
				}
			}
			return terminal_view_for_window(candidate)
		}
		index = (index + step + candidates.len) % candidates.len
	}
	return none
}

pub fn native_view_has_window(view voidptr) bool { return !is_nil(view_window(view)) }

pub fn float_native_window(view voidptr, mode int) {
	if mode !in [0, 1, 2] { return }
	window := view_window(view)
	if !msg_bool1(window, 'isKindOfClass:', get_class('VTTerminalWindow')) { return }
	level := if mode == 0 {
		3
	} else if mode == 1 {
		0
	} else {
		if msg_i64(window, 'level') == 3 { 0 } else { 3 }
	}
	msg_void_u64(window, 'setLevel:', u64(level))
	if item := g_config_menu_items['toggle_window_float_on_top'] {
		msg_void_u64(item, 'setState:', u64(if level == 3 { 1 } else { 0 }))
	}
}

pub fn maximize_native_window(view voidptr) {
	msg_void1(view_window(view), 'zoom:', nil_obj())
}

pub fn capture_native_hidden_windows() {
	clear_native_hidden_windows()
	key := msg_id(shared_app(), 'keyWindow')
	if !is_nil(key) { g_action_hidden_key = new_native_weak_object(voidptr(key)) }
	windows := msg_id(shared_app(), 'windows')
	mut seen := []voidptr{}
	for i in 0 .. int(msg_u64(windows, 'count')) {
		window := msg_id_u64(windows, 'objectAtIndex:', u64(i))
		if !msg_bool(window, 'isVisible') || msg_u64(window, 'styleMask') & u64(1 << 14) != 0 {
			continue
		}
		selected := msg_id(msg_id(window, 'tabGroup'), 'selectedWindow')
		target := if is_nil(selected) { window } else { selected }
		if target !in seen {
			seen << target
			g_action_hidden_windows << new_native_weak_object(voidptr(target))
		}
	}
	g_action_hidden = true
}

pub fn clear_native_hidden_windows() {
	for mut window in g_action_hidden_windows { window.deinit() }
	g_action_hidden_windows.clear()
	if g_action_hidden_key != unsafe { nil } { g_action_hidden_key.deinit() }
	g_action_hidden_key = unsafe { nil }
	g_action_hidden = false
}

pub fn toggle_native_visibility() {
	if app_is_active() {
		key := msg_id(shared_app(), 'keyWindow')
		if is_nil(key) || msg_u64(key, 'styleMask') & u64(1 << 14) != 0 { return }
		msg_void1(shared_app(), 'hide:', nil_obj())
		return
	}
	msg_void_bool(shared_app(), 'activateIgnoringOtherApps:', true)
	for window in g_action_hidden_windows {
		object := window.object()
		if !is_nil(object) { msg_void(object, 'orderFrontRegardless') }
	}
	if g_action_hidden_key != unsafe { nil } {
		object := g_action_hidden_key.object()
		if !is_nil(object) { msg_void(object, 'makeKeyWindow') }
	}
	clear_native_hidden_windows()
}

pub fn main_terminal_view() voidptr {
	mut window := msg_id(shared_app(), 'mainWindow')
	if is_nil(window) { window = msg_id(shared_app(), 'keyWindow') }
	if !action_terminal_window(window) { return nil_obj() }
	return terminal_view_for_window(window)
}

fn action_make_key(context voidptr) {
	msg_void(context, 'makeKeyWindow')
	msg_void(context, 'release')
}

// TerminalWindow.init and AppDelegate.useAsDefault preserve the native level.
fn apply_native_default_level(window ObjId) {
	defaults := msg_id(get_class('NSUserDefaults'), 'standardUserDefaults')
	value := msg_id1(defaults, 'objectForKey:', nsstring('TerminalDefaultLevel'))
	msg_void_u64(window, 'setLevel:', if is_nil(value) {
		u64(0)
	} else {
		u64(msg_i64(value, 'integerValue'))
	})
}

fn save_native_default_level() {
	defaults := msg_id(get_class('NSUserDefaults'), 'standardUserDefaults')
	item := g_config_menu_items['toggle_window_float_on_top'] or { return }
	if msg_i64(item, 'state') == 1 {
		msg_void2(defaults, 'setObject:forKey:', msg_id_u64(get_class('NSNumber'), 'numberWithUnsignedInteger:', 3), nsstring('TerminalDefaultLevel'))
	} else {
		msg_void1(defaults, 'removeObjectForKey:', nsstring('TerminalDefaultLevel'))
	}
}
