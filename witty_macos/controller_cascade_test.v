module witty_macos

fn test_native_cascade_uses_appkit_next_point_and_last_main_is_weak() {
	app_init()
	pool:=msg_id(alloc('NSAutoreleasePool'),'init')
	view:=create_restorable_window(160,100,'cascade probe')
	window:=msg_id(view,'window')
	msg_void_bool(window,'setReleasedWhenClosed:',false)
	initial:=ObjCPoint{x:150,y:650}
	C.witty_macos_msg_void_rect_bool(window,sel('setFrame:display:'),objc_rect(10,10,160,100),false)
	expected:=C.witty_macos_cascade_top_left(window,initial)
	expected_frame:=msg_rect(window,'frame')
	C.witty_macos_msg_void_rect_bool(window,sel('setFrame:display:'),objc_rect(10,10,160,100),false)
	g_terminal_cascade_point=initial
	show_new_terminal_window(view,false)
	assert g_terminal_cascade_point==expected
	assert msg_rect(window,'frame')==expected_frame
	assert msg_bool(window,'isVisible')
	terminal_window_became_main(window)
	assert preferred_terminal_window()==window
	msg_void(window,'close')
	msg_void(window,'release')
	// AppKit can retain a recently closed key window until its next event loop.
	// Verify weak ownership with an object whose native lifetime is deterministic.
	object:=msg_id(alloc('NSObject'),'init')
	g_terminal_last_main.deinit()
	g_terminal_last_main=new_native_weak_object(object)
	assert g_terminal_last_main.object()==object
	msg_void(object,'release')
	msg_void(pool,'drain')
	assert is_nil(g_terminal_last_main.object())
}

fn test_closing_key_terminal_resets_cascade_to_current_top_left() {
	app_init()
	view:=create_window(160,100,'closing cascade probe')
	window:=msg_id(view,'window')
	msg_void_bool(window,'setReleasedWhenClosed:',false)
	frame:=msg_rect(window,'frame')
	terminal_window_will_close_with_focused(window,window)
	assert g_terminal_cascade_point==ObjCPoint{x:frame.x,y:frame.y+frame.height}
	other_view:=create_restorable_window(160,100,'focused cascade probe')
	other:=msg_id(other_view,'window')
	msg_void_bool(other,'setReleasedWhenClosed:',false)
	old:=msg_rect(other,'frame')
	next:=C.witty_macos_cascade_top_left(other,ObjCPoint{})
	C.witty_macos_msg_void_rect_bool(other,sel('setFrame:display:'),old,false)
	terminal_window_will_close_with_focused(window,other)
	assert g_terminal_cascade_point==next
	assert msg_rect(other,'frame')==old
	msg_void(other,'close')
	msg_void(other,'release')
	msg_void(window,'close')
	msg_void(window,'release')
}
