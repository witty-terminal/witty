module main

import apprt
import witty_macos as macos
@[heap]
struct CloseControllerTask {
	current &TermState = unsafe { nil }
	close_window bool
	mode apprt.CloseTabMode = .this
	all bool
}
fn selected_controller_tabs(controller &TerminalController, close_window bool, mode apprt.CloseTabMode) []&TerminalController {
	mut result := []&TerminalController{}
	window := macos.view_window(controller.host.container)
	mut passed_current := false
	for candidate in macos.native_tab_windows(controller.host.container) {
		if candidate == window { passed_current = true }
		selected := close_window || (mode == .this && candidate == window) || (mode == .other && candidate != window) || (mode == .right && passed_current && candidate != window)
		if selected { if c := controller_for_window(candidate) { result << c } }
	}
	return result
}
fn controller_needs_confirmation(controller &TerminalController) ?&TermState {
	for view in controller.host.tree.root.leaves() {
		state := state_from_userdata(macos.view_get_userdata(view)) or { continue }
		if !state.closed && state.surface != unsafe { nil } && apprt.ghostty_surface_needs_confirm_quit(state.surface) { return state }
	}
	return none
}
fn close_selected_tabs_immediately(controller &TerminalController, mode apprt.CloseTabMode) {
	selected := selected_controller_tabs(controller, false, mode)
	if selected.len == 0 { return }
	macos.native_undo_begin()
	for c in selected {
		if snapshot := controller_undo_state(c) {
			register_controller_undo(&ControllerUndo{kind:.restore,states:[snapshot],register_redo:false},voidptr(standalone_runtime().app))
			close_one_controller(c)
		}
	}
	name := if mode == .other { 'Close Other Tabs' } else { 'Close Tabs to the Right' }
	register_controller_undo(&ControllerUndo{kind:.focus,controller:controller,mode:mode,name:name},voidptr(controller))
	macos.native_undo_end()
}
fn finish_close_controller(context voidptr, confirmed bool) {
	if !confirmed { return }
	task := unsafe { &CloseControllerTask(context) }
	if task.all {
		macos.native_undo_begin()
		for controller in standalone_runtime().controllers.clone() { if !controller.quick && !controller.closed { close_controller_immediately(controller,true) } }
		macos.native_undo_set_name('Close All Windows')
		macos.native_undo_end()
		return
	}
	if task.current.controller == unsafe { nil } || task.current.controller.closed { return }
	if task.mode == .this { close_controller_immediately(task.current.controller,task.close_window) }
	else { close_selected_tabs_immediately(task.current.controller,task.mode) }
}
fn do_close_controller(current &TermState, close_window bool, mode apprt.CloseTabMode) bool {
	if current.controller == unsafe { nil } || current.controller.closed { return false }
	if mut quick := macos.quick_terminal_for_view(current.view) { quick.hide(); return true }
	selected := selected_controller_tabs(current.controller,close_window,mode)
	if selected.len == 0 { return false }
	mut confirm := unsafe { &TermState(nil) }
	for controller in selected { if state := controller_needs_confirmation(controller) { confirm = state; break } }
	task := &CloseControllerTask{current:current,close_window:close_window,mode:mode}
	if confirm == unsafe { nil } { finish_close_controller(voidptr(task),true); return true }
	message := if close_window { 'Close Window?' } else { match mode { .this { 'Close Tab?' } .other { 'Close Other Tabs?' } .right { 'Close Tabs on the Right?' } } }
	info := if close_window { 'All terminal sessions in this window will be terminated.' } else { match mode { .this { 'The terminal still has a running process. If you close the tab the process will be killed.' } .other { 'At least one other tab still has a running process. If you close the tab the process will be killed.' } .right { 'At least one tab to the right still has a running process. If you close the tab the process will be killed.' } } }
	macos.confirm_native_controller_close(confirm.view,message,info,'Close',voidptr(task),finish_close_controller)
	return true
}
fn do_close_all_controllers() bool {
	task := &CloseControllerTask{all:true}
	for controller in standalone_runtime().controllers { if !controller.quick && !controller.closed { if state := controller_needs_confirmation(controller) { macos.confirm_native_controller_close(state.view,'Close All Windows?','All terminal sessions will be terminated.','Close All Windows',voidptr(task),finish_close_controller); return true } } }
	finish_close_controller(voidptr(task),true)
	return true
}
