@[has_globals]
module macos

fn C.object_setClass(object ObjId, cls ObjId) ObjId

__global (
	view_super_terminal_focus = []bool{}
	view_super_inspector_focus = []bool{}
)

fn view_super_terminal_callback(_userdata voidptr, focused bool) {
	view_super_terminal_focus << focused
}
fn view_super_inspector_callback(_backend voidptr, focused bool) {
	view_super_inspector_focus << focused
}
fn test_terminal_view_inherited_responder_tracking_and_backing_super_calls() {
	app_init()
	view := create_terminal_view(objc_rect(0, 0, 40, 40))
	defer { view_set_userdata(view, unsafe { nil }); msg_void(view, 'release') }
	previous := g_focus_cb
	defer { g_focus_cb = previous }
	view_set_userdata(view, voidptr(1))
	set_focus_callback(view_super_terminal_callback)
	view_super_terminal_focus = []bool{}
	become := msg_bool(view, 'becomeFirstResponder')
	resign := msg_bool(view, 'resignFirstResponder')
	expected := view_super_terminal_focus.clone()
	view_super_terminal_focus = []bool{}
	cls := C.macos_objc_allocate_class_pair(get_class('VTTerminalView'), cstr('WittyTerminalViewSuperFixture'), 0)
	C.macos_objc_register_class_pair(cls)
	C.object_setClass(view, cls)
	assert msg_bool(view, 'becomeFirstResponder') == become
	assert msg_bool(view, 'resignFirstResponder') == resign
	assert view_super_terminal_focus == expected
	assert expected == [true, false]
	msg_void(view, 'updateTrackingAreas')
	msg_void(view, 'viewDidChangeBackingProperties')
}

fn test_terminal_layer_updates_when_a_detached_view_joins_a_window() {
	app_init()
	window_view := create_restorable_window(200, 120, 'backing scale probe')
	window := view_window(window_view)
	view := create_terminal_view(objc_rect(0, 0, 40, 30))
	layer := msg_id(get_class('CALayer'), 'layer')
	defer {
		msg_void(view, 'removeFromSuperview')
		msg_void(view, 'release')
		close_native_window(window)
		release_native_object(window)
		release_native_object(window_view)
	}
	window_scale := view_backing_scale(window_view)
	detached_scale := if window_scale == 1 { f64(2) } else { f64(1) }
	metal_install_iosurface_layer(view, layer, detached_scale)
	assert msg_f64(layer, 'contentsScale') == detached_scale
	msg_void1(window_view, 'addSubview:', view)
	assert msg_f64(layer, 'contentsScale') == window_scale
	width, height := metal_layer_surface_size(layer)
	assert width == 40 * window_scale
	assert height == 30 * window_scale

	msg_void_f64(layer, 'setContentsScale:', detached_scale)
	msg_void(view, 'viewDidChangeBackingProperties')
	assert msg_f64(layer, 'contentsScale') == window_scale
}

fn test_inspector_view_inherited_responder_and_backing_super_calls() {
	app_init()
	register_inspector_view()
	view := ObjId(C.witty_action_inspector_new(get_class('WittyInspectorView'), C.MTLCreateSystemDefaultDevice(), 40, 40))
	assert !is_nil(view)
	surface := &NativeActionSurface{callbacks: ActionCallbacks{inspector: NativeInspectorCallbacks{focus: view_super_inspector_callback}}}
	mut state := &NativeInspectorView{surface: surface, view: view, backend: voidptr(1)}
	C.macos_objc_set_ptr_ivar(view, cstr('inspector'), voidptr(state))
	defer { state.closed = true; C.macos_objc_set_ptr_ivar(view, cstr('inspector'), nil_obj()); msg_void(view, 'release') }
	view_super_inspector_focus = []bool{}
	become := msg_bool(view, 'becomeFirstResponder')
	resign := msg_bool(view, 'resignFirstResponder')
	expected := view_super_inspector_focus.clone()
	view_super_inspector_focus = []bool{}
	cls := C.macos_objc_allocate_class_pair(get_class('WittyInspectorView'), cstr('WittyInspectorViewSuperFixture'), 0)
	C.macos_objc_register_class_pair(cls)
	C.object_setClass(view, cls)
	assert msg_bool(view, 'becomeFirstResponder') == become
	assert msg_bool(view, 'resignFirstResponder') == resign
	assert view_super_inspector_focus == expected
	assert expected == [true, false]
	msg_void(view, 'viewDidChangeBackingProperties')
}
