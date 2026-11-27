module witty_macos

#insert "@VMODROOT/witty_macos/canvas_overlay_test_bridge.h"
fn C.witty_overlay_test_png(view ObjId) ObjId

fn test_native_window_inherited_overrides_use_defining_class_super() {
	app_init()
	register_native_window_class()
	cls:=C.macos_objc_allocate_class_pair(get_class('VTTerminalWindow'),cstr('VTInheritedWindowProbe'),0)
	C.macos_objc_register_class_pair(cls)
	window:=msg_id_rect_u64_u64_bool(msg_id(cls,'alloc'),'initWithContentRect:styleMask:backing:defer:',objc_rect(0,0,100,100),ns_window_style_titled|ns_window_style_closable|ns_window_style_resizable,ns_backing_store_buffered,false)
	defaults:=msg_id(get_class('NSUserDefaults'),'standardUserDefaults')
	previous:=msg_id1(defaults,'objectForKey:',nsstring('NSWindowLastPosition'))
	msg_void(previous,'retain')
	defer {
		if is_nil(previous) { msg_void1(defaults,'removeObjectForKey:',nsstring('NSWindowLastPosition')) }
		else { msg_void2(defaults,'setObject:forKey:',previous,nsstring('NSWindowLastPosition')) }
		msg_void(previous,'release')
	}
	msg_void_bool(window,'setReleasedWhenClosed:',false)
	msg_void(window,'update')
	accessory:=msg_id(alloc('NSTitlebarAccessoryViewController'),'init')
	msg_void1(accessory,'setView:',msg_id_rect(alloc('NSView'),'initWithFrame:',objc_rect(0,0,20,20)))
	msg_void1(window,'addTitlebarAccessoryViewController:',accessory)
	assert msg_u64(msg_id(window,'titlebarAccessoryViewControllers'),'count')==1
	msg_void_u64(window,'removeTitlebarAccessoryViewControllerAtIndex:',0)
	assert msg_u64(msg_id(window,'titlebarAccessoryViewControllers'),'count')==0
	msg_void(window,'close')
	msg_void(window,'release')
}
fn test_native_restoration_class_and_secure_archive_protocol_are_live() {
	app_init()
	view:=create_restorable_window(100,100,'restoration probe')
	assert !msg_bool(msg_id(view,'window'),'isVisible')
	configure_native_restoration(view,true)
	window:=msg_id(view,'window')
	assert msg_bool(window,'isRestorable')
	assert objc_utf8_string(msg_id(window,'identifier'))=='TerminalWindowRestoration'
	assert msg_bool1(msg_id(window,'restorationClass'),'respondsToSelector:',sel('restoreWindowWithIdentifier:state:completionHandler:'))
	assert msg_bool(codable_bridge_class(),'supportsSecureCoding')
	configure_native_restoration(view,false)
	assert !msg_bool(window,'isRestorable')
	msg_void(window,'close')
}
fn test_new_tab_refuses_non_native_fullscreen_with_real_warning_sheet() {
	app_init()
	view:=create_window(160,100,'fullscreen tab probe')
	window:=msg_id(view,'window')
	assert !native_tab_creation_denied(view)
	g_fullscreen_states[u64(window)]=&FullscreenState{window:window,mode:.non_native,saved:true}
	assert native_tab_creation_denied(view)
	sheet:=msg_id(window,'attachedSheet')
	assert !is_nil(sheet)
	msg_void1(window,'endSheet:',sheet)
	msg_void1(sheet,'orderOut:',nil_obj())
	g_fullscreen_states.delete(u64(window))
	msg_void(window,'close')
	msg_void(window,'release')
}
fn test_default_content_size_repositions_and_clamps_configured_native_origin() {
	app_init()
	view:=create_restorable_window(160,100,'default size probe')
	window:=msg_id(view,'window')
	reset_native_window_size(view,false,native_window_frame(view),240,160)
	adjust_native_window_origin_after_default_size(view,-30000,-30000)
	frame:=msg_rect(window,'frame')
	visible:=msg_rect(msg_id(window,'screen'),'visibleFrame')
	assert frame.x==visible.x
	assert frame.y==visible.y+visible.height-frame.height
	adjust_native_window_origin_after_default_size(view,30000,30000)
	clamped:=msg_rect(window,'frame')
	assert clamped.x==visible.x+visible.width-clamped.width
	assert clamped.y==visible.y
	msg_void(window,'close')
	msg_void(window,'release')
}

fn test_native_tab_shortcuts_follow_selection_reorder_and_config_changes() {
	app_init()
	previous := g_native_tab_shortcuts
	defer { set_native_tab_shortcuts(previous) }
	set_native_tab_shortcuts(['⌘1', '⌃B', '', '', '', '', '', '', '']!)
	left := create_restorable_window(400, 200, 'Left')
	right := create_restorable_window(400, 200, 'Right')
	left_window, right_window := view_window(left), view_window(right)
	defer {
		for window in [right_window, left_window] {
			close_native_window(window)
			release_native_object(window)
		}
		for view in [right, left] { release_native_object(view) }
	}
	for view in [left, right] {
		apply_native_window_config(view, NativeWindowConfig{}, true, 0, 1, false)
	}
	attach_native_new_tab(left_window, right, false)
	focus_native_window(right_window)
	assert msg_id(native_tab_group(right), 'selectedWindow') == right_window
	refresh_native_tab_shortcuts(right_window)
	left_data := native_window_data(left_window) or { panic('left window missing') }
	right_data := native_window_data(right_window) or { panic('right window missing') }
	assert objc_utf8_string(msg_id(left_data.tab_shortcut, 'stringValue')) == '⌘1 '
	assert objc_utf8_string(msg_id(right_data.tab_shortcut, 'stringValue')) == '⌃B '
	accessory := msg_id(msg_id(right_window, 'tab'), 'accessoryView')
	indicator := right_data.tab_color_indicator
	assert msg_id_u64(msg_id(accessory, 'arrangedSubviews'), 'objectAtIndex:', 0) == indicator
	bounds := msg_rect(indicator, 'bounds')
	assert bounds.width == tab_color_indicator_size
	assert bounds.height == tab_color_indicator_size
	blank := C.witty_overlay_test_png(indicator)
	assert !is_nil(blank)
	set_native_tab_color(right, 4)
	assert native_tab_color(right) == 4
	assert native_tab_color(left) == 0
	colored := C.witty_overlay_test_png(indicator)
	assert !is_nil(colored)
	assert !msg_bool1(colored, 'isEqualToData:', blank)
	set_native_tab_color(right, 0)
	assert msg_bool1(C.witty_overlay_test_png(indicator), 'isEqualToData:', blank)
	assert !msg_bool(indicator, 'isHidden')
	assert move_native_tab(right, -1)
	assert objc_utf8_string(msg_id(right_data.tab_shortcut, 'stringValue')) == '⌘1 '
	assert objc_utf8_string(msg_id(left_data.tab_shortcut, 'stringValue')) == '⌃B '
	set_native_tab_shortcuts(['', '⇧⌘L', '', '', '', '', '', '', '']!)
	assert objc_utf8_string(msg_id(right_data.tab_shortcut, 'stringValue')) == ' '
	assert objc_utf8_string(msg_id(left_data.tab_shortcut, 'stringValue')) == '⇧⌘L '
}
