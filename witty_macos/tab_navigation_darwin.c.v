module witty_macos

pub fn goto_native_tab(view voidptr, value int) bool {
	window := msg_id(view, 'window')
	group := msg_id(window, 'tabGroup')
	tabs := msg_id(group, 'windows')
	count := int(msg_u64(tabs, 'count'))
	if count <= 1 { return false }
	selected_window := msg_id(group, 'selectedWindow')
	mut selected := -1
	for i in 0 .. count { if msg_id_u64(tabs, 'objectAtIndex:', u64(i)) == selected_window { selected = i; break } }
	if index := native_tab_index(value, selected, count) {
		msg_void1(msg_id_u64(tabs, 'objectAtIndex:', u64(index)), 'makeKeyAndOrderFront:', nil_obj())
	}
	return true
}
pub fn set_native_cell_size(view voidptr, width f64, height f64, step_resize bool) {
	if !step_resize || width <= 0 || height <= 0 { return }
	msg_void_size(msg_id(view, 'window'), 'setContentResizeIncrements:', objc_size(width, height))
}
