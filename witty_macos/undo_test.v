module witty_macos

@[heap]
struct UndoProbe { mut: value int released int }
fn probe_release(context voidptr) { mut probe := unsafe { &UndoProbe(context) }; probe.released++ }
fn probe_undo(context voidptr) {
	mut probe := unsafe { &UndoProbe(context) }
	probe.value--
	register_expiring_undo(voidptr(probe), 2, context, 'Source action', probe_redo, probe_release)
}
fn probe_redo(context voidptr) {
	mut probe := unsafe { &UndoProbe(context) }
	probe.value++
	register_expiring_undo(voidptr(probe), 2, context, 'Source action', probe_undo, probe_release)
}
fn test_native_expiring_undo_registration_guards() {
	clear_native_undo()
	mut probe := &UndoProbe{}
	assert !register_expiring_undo(voidptr(probe), 0, voidptr(probe), '', probe_undo, probe_release)
	native_undo_disable()
	assert !register_expiring_undo(voidptr(probe), 1, voidptr(probe), '', probe_undo, probe_release)
	native_undo_enable()
	assert !native_undo()
	assert probe.released == 0
}
fn test_native_undo_redo_and_removing_real_target() {
	clear_native_undo()
	mut probe := &UndoProbe{value:1}
	native_undo_begin()
	assert register_expiring_undo(voidptr(probe), 2, voidptr(probe), 'Source action', probe_undo, probe_release)
	native_undo_end()
	assert native_undo()
	assert probe.value == 0
	assert native_redo()
	assert probe.value == 1
	assert probe.released == 2
	remove_native_undo(voidptr(probe))
	assert probe.released == 3
	assert !native_undo()
}
fn test_scheduled_native_timer_expires_registration() {
	clear_native_undo()
	mut probe := &UndoProbe{value:1}
	native_undo_begin()
	assert register_expiring_undo(voidptr(probe), 0.01, voidptr(probe), 'Close Terminal', probe_undo, probe_release)
	native_undo_end()
	msg_void1(msg_id(get_class('NSRunLoop'),'currentRunLoop'),'runUntilDate:',msg_id_f64(get_class('NSDate'),'dateWithTimeIntervalSinceNow:',0.04))
	assert probe.released == 1
	assert !native_undo()
	assert probe.value == 1
}
