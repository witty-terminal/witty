@[has_globals]
module witty_macos

// SurfaceView.moveFocus owns its captured views until the main-queue work
// finishes, retrying only while the target has not reached a window.
@[heap]
struct NativeFocusTask {
	to ObjId
	from ObjId
mut:
	delay ?f64
}

__global g_native_focus_tasks = []&NativeFocusTask{}

// Captured SurfaceViews keep their embedded surface alive while the queued
// focus work owns them, including delayed attachment retries.
pub fn native_focus_retains_view(view voidptr) bool {
	for task in g_native_focus_tasks {
		if task.to == view || task.from == view { return true }
	}
	return false
}

pub fn move_focus(to voidptr, from voidptr, delay ?f64) {
	if is_nil(to) || !((delay or { 0.0 }) < 0.5) { return }
	task := &NativeFocusTask{ to: ObjId(to), from: ObjId(from), delay: delay }
	msg_void(task.to, 'retain')
	msg_void(task.from, 'retain')
	g_native_focus_tasks << task
	if seconds := delay {
		dispatch_after(seconds, native_focus_main, voidptr(task))
	} else {
		dispatch_main(native_focus_main, voidptr(task))
	}
}

fn native_focus_main(context voidptr) {
	mut task := unsafe { &NativeFocusTask(context) }
	window := msg_id(task.to, 'window')
	if is_nil(window) {
		next_delay := if delay := task.delay { delay * 2 } else { 0.05 }
		if next_delay < 0.5 {
			task.delay = next_delay
			dispatch_after(next_delay, native_focus_main, context)
			return
		}
	} else {
		if !is_nil(task.from) { msg_bool(task.from, 'resignFirstResponder') }
		msg_bool1(window, 'makeFirstResponder:', task.to)
	}
	msg_void(task.to, 'release')
	msg_void(task.from, 'release')
	for i, pending in g_native_focus_tasks {
		if pending == task { g_native_focus_tasks.delete(i); break }
	}
}
