module macos

fn C.CGColorEqualToColor(first voidptr, second voidptr) bool

fn split_dimming_color(view ObjId) voidptr {
	return msg_id(msg_id(view, 'layer'), 'backgroundColor')
}

fn test_native_split_dimming_tracks_the_focused_pane_and_app_config() {
	app_init()
	left_view := create_restorable_window(480, 320, 'Split dimming')
	window := msg_id(left_view, 'window')
	mut host := create_split_host(left_view)
	right_view := create_split_surface_view(host)
	mut left := new_action_surface(left_view, unsafe { nil }, ActionCallbacks{})
	mut right := new_action_surface(right_view, unsafe { nil }, ActionCallbacks{})
	defer {
		left.deinit()
		right.deinit()
		msg_void(window, 'close')
		msg_void(window, 'release')
		msg_void(left_view, 'release')
		msg_void(right_view, 'release')
		msg_void(host.container, 'release')
	}
	config := NativeWindowConfig{ background: 0x161820, unfocused_split_opacity: 0.5 }
	host.set_dimming(config, left_view)
	assert is_nil(left.scroll.split_dimming)

	tree := host.tree.inserting(right_view, left_view, .right) or { panic(err) }
	host.replace_tree(tree)
	assert is_nil(left.scroll.split_dimming)
	right_dimming := right.scroll.split_dimming
	assert !is_nil(right_dimming)
	assert !msg_bool(right_dimming, 'isHidden')
	assert msg_id(msg_id(right.scroll.container, 'subviews'), 'lastObject') == right_dimming
	assert C.CGColorEqualToColor(split_dimming_color(right_dimming), msg_id(native_color(0x161820, 0.5), 'CGColor'))
	assert msg_rect(right_dimming, 'frame') == msg_rect(right.scroll.scroll, 'frame')

	host.set_dimming(config, right_view)
	assert msg_bool(right_dimming, 'isHidden')
	left_dimming := left.scroll.split_dimming
	assert !msg_bool(left_dimming, 'isHidden')
	right.start_search('needle')
	assert right.search_active
	host.layout()
	assert msg_bool(right_dimming, 'isHidden')
	assert !msg_bool(left_dimming, 'isHidden')
	right.end_search()

	updated := NativeWindowConfig{ ...config, unfocused_split_opacity: 0.75, unfocused_split_fill: u32(0x81315a) }
	host.set_dimming(updated, right_view)
	assert C.CGColorEqualToColor(split_dimming_color(left_dimming), msg_id(native_color(0x81315a, 0.25), 'CGColor'))
	host.replace_tree(NativeSplitTree{ root: tree.root, zoomed: tree.root.find(right_view) or { panic('missing right pane') } })
	assert msg_bool(left_dimming, 'isHidden')
	assert msg_bool(right_dimming, 'isHidden')
	host.replace_tree(tree)
	assert !msg_bool(left_dimming, 'isHidden')
	host.set_dimming(NativeWindowConfig{ ...updated, unfocused_split_opacity: 1 }, right_view)
	assert msg_bool(left_dimming, 'isHidden')
}
