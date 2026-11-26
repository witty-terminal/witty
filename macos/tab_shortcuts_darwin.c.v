@[has_globals]
module macos

__global g_native_tab_shortcuts [9]string

pub fn set_native_tab_shortcuts(shortcuts [9]string) {
	g_native_tab_shortcuts = shortcuts
	for _, data in g_native_windows {
		refresh_native_tab_shortcuts(data.window)
	}
}

fn prepare_native_tab_shortcut(mut data NativeWindowData) ObjId {
	empty := msg_id(alloc('NSAttributedString'), 'init')
	label := msg_id1(get_class('NSTextField'), 'labelWithAttributedString:', empty)
	msg_void(empty, 'release')
	data.tab_shortcut = label
	C.witty_macos_priority(label, sel('setContentCompressionResistancePriority:forOrientation:'),
		500, 0)
	msg_void_bool(label, 'setPostsFrameChangedNotifications:', true)
	C.witty_macos_observe(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), data.window,
		sel('nativeTabShortcutFrameChanged:'), nsstring('NSViewFrameDidChangeNotification'), label)
	return label
}

fn update_native_tab_shortcut(window ObjId, index int) {
	mut data := native_window_data(window) or { return }
	if is_nil(data.tab_shortcut) { return }
	text := if index < 0 { '' } else if index < g_native_tab_shortcuts.len {
		g_native_tab_shortcuts[index] + ' '
	} else {
		' '
	}
	key := msg_bool(window, 'isKeyWindow')
	if text == data.tab_shortcut_text && key == data.tab_shortcut_key { return }
	data.tab_shortcut_text = text
	data.tab_shortcut_key = key
	font := msg_id_f64(get_class('NSFont'), 'systemFontOfSize:',
		msg_f64(get_class('NSFont'), 'smallSystemFontSize'))
	color := msg_id(get_class('NSColor'), if key { 'labelColor' } else { 'secondaryLabelColor' })
	attributes := new_obj('NSMutableDictionary')
	msg_void2(attributes, 'setObject:forKey:', font, nsstring('NSFont'))
	msg_void2(attributes, 'setObject:forKey:', color, nsstring('NSColor'))
	value := msg_id2(alloc('NSAttributedString'), 'initWithString:attributes:', nsstring(text), attributes)
	msg_void1(data.tab_shortcut, 'setAttributedStringValue:', value)
	msg_void(value, 'release')
	msg_void(attributes, 'release')
}

fn refresh_native_tab_shortcuts(window ObjId) {
	tabs := msg_id(window, 'tabbedWindows')
	count := int(msg_u64(tabs, 'count'))
	if count < 2 {
		update_native_tab_shortcut(window, -1)
		return
	}
	for i in 0 .. count {
		update_native_tab_shortcut(msg_id_u64(tabs, 'objectAtIndex:', u64(i)), i)
	}
}

fn refresh_native_tab_shortcuts_main(context voidptr) {
	window := ObjId(context)
	mut data := native_window_data(window) or { return }
	data.tab_shortcut_refresh_pending = false
	refresh_native_tab_shortcuts(window)
}

fn queue_native_tab_shortcuts(window ObjId) {
	mut data := native_window_data(window) or { return }
	if data.tab_shortcut_refresh_pending { return }
	data.tab_shortcut_refresh_pending = true
	C.witty_macos_dispatch_main_weak(voidptr(window), voidptr(refresh_native_tab_shortcuts_main))
}

fn native_tab_shortcut_frame_changed(window ObjId, _cmd Sel, _notification ObjId) {
	queue_native_tab_shortcuts(window)
}
