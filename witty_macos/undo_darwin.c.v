@[has_globals]
module witty_macos

// ExpiringUndoManager.swift: NSUndoManager owns the undo/redo stacks; proxies
// give each registration its own weak target and scheduled expiration timer.
pub type NativeUndoCallback = fn (voidptr)
@[heap]
struct ExpiringUndoTarget {
mut:
	proxy ObjId
	timer ObjId
	real_target voidptr
	context voidptr
	handler NativeUndoCallback
	release NativeUndoCallback
	active bool = true
}
__global (
	g_native_undo ObjId
	g_expiring_undo_targets []&ExpiringUndoTarget
)
fn undo_target(self ObjId) ?&ExpiringUndoTarget {
	ptr := C.macos_objc_get_ptr_ivar(self, cstr('vtUndoTarget'))
	if is_nil(ptr) { return none }
	return unsafe { &ExpiringUndoTarget(ptr) }
}
fn release_undo_target(mut target ExpiringUndoTarget) {
	if !target.active { return }
	target.active = false
	msg_void(target.timer, 'invalidate')
	target.timer = nil_obj()
	for i, value in g_expiring_undo_targets { if value == &target { g_expiring_undo_targets.delete(i); break } }
	target.release(target.context)
	C.macos_objc_set_ptr_ivar(target.proxy, cstr('vtUndoTarget'), nil_obj())
	msg_void(target.proxy, 'release')
}
fn native_undo_expire(self ObjId, _cmd Sel, _timer ObjId) {
	mut target := undo_target(self) or { return }
	target.real_target = unsafe { nil }
	msg_void1(g_native_undo, 'removeAllActionsWithTarget:', self)
	release_undo_target(mut target)
}
fn native_undo_invoke(self ObjId, _cmd Sel, _object ObjId) {
	mut target := undo_target(self) or { return }
	for i, value in g_expiring_undo_targets { if value == target { g_expiring_undo_targets.delete(i); break } }
	if target.active && !is_nil(target.real_target) { target.handler(target.context) }
	release_undo_target(mut target)
}
pub fn native_undo_manager() voidptr {
	if !is_nil(g_native_undo) { return g_native_undo }
	if is_nil(get_class('VTExpiringUndoTarget')) {
		cls := C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('VTExpiringUndoTarget'), 0)
		C.macos_class_add_ivar(cls, cstr('vtUndoTarget'), sizeof(voidptr), 3, cstr('^v'))
		add_method(cls, 'expire:', voidptr(native_undo_expire), 'v@:@')
		add_method(cls, 'invoke:', voidptr(native_undo_invoke), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	g_native_undo = msg_id(msg_id(get_class('NSUndoManager'), 'alloc'), 'init')
	return g_native_undo
}
pub fn register_expiring_undo(target voidptr, seconds f64, context voidptr, name string, handler NativeUndoCallback, release NativeUndoCallback) bool {
	manager := native_undo_manager()
	if seconds <= 0 || !msg_bool(manager, 'isUndoRegistrationEnabled') { return false }
	proxy := msg_id(msg_id(get_class('VTExpiringUndoTarget'), 'alloc'), 'init')
	mut value := &ExpiringUndoTarget{proxy: proxy, real_target: target, context: context, handler: handler, release: release}
	C.macos_objc_set_ptr_ivar(proxy, cstr('vtUndoTarget'), voidptr(value))
	value.timer = C.witty_controller_timer(seconds, proxy, sel('expire:'))
	g_expiring_undo_targets << value
	if name.len > 0 { msg_void1(manager, 'setActionName:', nsstring(name)) }
	C.witty_controller_register_undo(manager, proxy, sel('invoke:'))
	return true
}
pub fn remove_native_undo(target voidptr) {
	manager := native_undo_manager()
	msg_void1(manager, 'removeAllActionsWithTarget:', target)
	for mut value in g_expiring_undo_targets.clone() {
		if is_nil(value.real_target) || value.real_target == target {
			native_undo_expire(value.proxy, nil_obj(), nil_obj())
		}
	}
}
pub fn clear_native_undo() {
	msg_void(native_undo_manager(), 'removeAllActions')
	for mut value in g_expiring_undo_targets.clone() { release_undo_target(mut value) }
}
pub fn native_undo_begin() { msg_void(native_undo_manager(), 'beginUndoGrouping') }
pub fn native_undo_end() { msg_void(native_undo_manager(), 'endUndoGrouping') }
pub fn native_undo_disable() { msg_void(native_undo_manager(), 'disableUndoRegistration') }
pub fn native_undo_enable() { msg_void(native_undo_manager(), 'enableUndoRegistration') }
pub fn native_undo_set_name(name string) { msg_void1(native_undo_manager(), 'setActionName:', nsstring(name)) }
pub fn native_undo() bool { manager := native_undo_manager(); if !msg_bool(manager, 'canUndo') { return false }; msg_void(manager, 'undo'); return true }
pub fn native_redo() bool { manager := native_undo_manager(); if !msg_bool(manager, 'canRedo') { return false }; msg_void(manager, 'redo'); return true }
fn native_window_undo_manager(_self ObjId, _cmd Sel, _window ObjId) ObjId { return native_undo_manager() }
fn native_undo_action(_self ObjId, _cmd Sel, _sender ObjId) { native_undo() }
fn native_redo_action(_self ObjId, _cmd Sel, _sender ObjId) { native_redo() }
fn register_native_undo_methods(cls ObjId) {
	add_method(cls, 'windowWillReturnUndoManager:', voidptr(native_window_undo_manager), '@@:@')
	add_method(cls, 'undo:', voidptr(native_undo_action), 'v@:@')
	add_method(cls, 'redo:', voidptr(native_redo_action), 'v@:@')
}
