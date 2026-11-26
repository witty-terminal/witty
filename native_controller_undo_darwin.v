module main

import apprt
import macos

enum ControllerUndoKind { tree tree_redo restore close focus new_close new_redo }
struct ControllerUndoState {
	tree macos.NativeSplitTree
	frame macos.NativeWindowFrame
	focused voidptr
	tab_group &macos.NativeWeakObject
	tab_index int = -1
	title_override ?string
	tab_color int
}
@[heap]
struct ControllerUndo {
mut:
	kind ControllerUndoKind
	controller &TerminalController = unsafe { nil }
	tree macos.NativeSplitTree
	opposite_tree macos.NativeSplitTree
	focus voidptr
	opposite_focus voidptr
	states []ControllerUndoState
	key_index int = -1
	group bool
	register_redo bool = true
	close_window bool
	mode apprt.CloseTabMode = .this
	name string
	source ?&TermState
	new_tab bool
	base_options apprt.SurfaceOptions
}
fn undo_expiration() f64 { return f64(standalone_runtime().app.config.undo_timeout.duration) / 1e9 }
fn register_controller_undo(record &ControllerUndo, target voidptr) {
	mut runtime := standalone_runtime()
	macos.retain_native_object(record.focus)
	macos.retain_native_object(record.opposite_focus)
	runtime.undos << record
	if !macos.register_expiring_undo(target, undo_expiration(), voidptr(record), record.name, perform_controller_undo, release_controller_undo) { release_controller_undo(voidptr(record)) }
}
fn release_controller_undo(context voidptr) {
	mut runtime := standalone_runtime()
	record := unsafe { &ControllerUndo(context) }
	for i, item in runtime.undos { if item == record { runtime.undos.delete(i); break } }
	macos.release_native_object(record.focus)
	macos.release_native_object(record.opposite_focus)
	for snapshot in record.states { mut group:=snapshot.tab_group; group.deinit() }
	collect_detached_surfaces()
}
fn collect_detached_surfaces() {
	mut runtime := standalone_runtime()
	for mut state in runtime.states {
		if state.closed { continue }
		mut retained := false
		for controller in runtime.controllers { if !controller.closed && (controller.host.tree.root.find(state.view) != none || controller.focused == state) { retained = true; break } }
		if !retained {
			for task in controller_tree_focus_instance.tasks {
				if task.to == state.view || task.from == state.view { retained = true; break }
				if task.from_controller != unsafe { nil } && task.from_controller.focused == state { retained = true; break }
			}
			if macos.native_focus_retains_view(state.view) { retained = true }
			if pending := runtime.pending_quick { if pending.tree.root.find(state.view) != none { retained = true } }
			for record in runtime.undos {
				if record.tree.root.find(state.view) != none || record.opposite_tree.root.find(state.view) != none || record.focus == state.view || record.opposite_focus == state.view { retained = true; break }
				for snapshot in record.states { if snapshot.tree.root.find(state.view) != none { retained = true; break } }
				if retained { break }
			}
		}
		if retained { continue }
		state.closed = true
		state.closing = false
		if state.actions != unsafe { nil } { state.actions.deinit() }
		macos.view_set_userdata(state.view, unsafe { nil })
		if state.surface != unsafe { nil } { apprt.ghostty_surface_free(mut state.surface); state.surface = unsafe { nil } }
		macos.release_native_object(state.view)
	}
}
fn replace_controller_tree(controller &TerminalController, tree macos.NativeSplitTree, new_focus voidptr, old_focus voidptr, name string) {
	if tree.root == unsafe { nil } && !controller.quick { close_controller_immediately(controller, false); return }
	old_tree := controller.host.tree
	mut c := unsafe { &TerminalController(controller) }
	c.host.replace_tree(tree)
	if tree.root == unsafe { nil } { c.focused = unsafe { nil } }
	macos.invalidate_native_restorable_state(c.host.container)
	if new_focus != unsafe { nil } { queue_controller_tree_focus(new_focus, old_focus, unsafe { nil }) }
	register_controller_undo(&ControllerUndo{kind: .tree, controller: c, tree: old_tree, opposite_tree: tree, focus: old_focus, opposite_focus: new_focus, name: name}, voidptr(c))
}
@[heap]
struct ControllerTreeFocus {
	to voidptr
	from voidptr
	from_controller &TerminalController = unsafe { nil }
}
struct ControllerTreeFocusTasks {
mut:
	tasks []&ControllerTreeFocus
}
const controller_tree_focus_instance = &ControllerTreeFocusTasks{}

// replaceSurfaceTree adds an outer main-queue closure before moveFocus's own
// work item. The closure owns both explicit views; undo reads focusedSurface
// from its captured controller when that outer closure runs.
fn queue_controller_tree_focus(to voidptr, from voidptr, from_controller &TerminalController) {
	task := &ControllerTreeFocus{to: to, from: from, from_controller: from_controller}
	macos.retain_native_object(task.to)
	macos.retain_native_object(task.from)
	mut tasks := unsafe { &controller_tree_focus_instance.tasks }
	tasks << task
	macos.dispatch_main(controller_tree_focus_main, voidptr(task))
}
fn controller_tree_focus_main(context voidptr) {
	task := unsafe { &ControllerTreeFocus(context) }
	mut from := task.from
	if task.from_controller != unsafe { nil } {
		from = unsafe { nil }
		if task.from_controller.focused != unsafe { nil } { from = task.from_controller.focused.view }
	}
	macos.move_focus(task.to, from, none)
	macos.release_native_object(task.to)
	macos.release_native_object(task.from)
	mut tasks := unsafe { &controller_tree_focus_instance.tasks }
	for i, pending in controller_tree_focus_instance.tasks {
		if pending == task { tasks.delete(i); break }
	}
}
fn focus_controller_surface(context voidptr) {
	state := unsafe { &TermState(context) }
	if !state.closed { macos.focus_split_view(state.view) }
}
// Close-other/right undo queues the controller, then resolves its window on
// the next main-queue turn. Runtime.controllers retains the controller; a
// closed controller has already released its native host and window.
fn refocus_controller_window(context voidptr) {
	controller := unsafe { &TerminalController(context) }
	if controller.closed { return }
	macos.focus_native_window(macos.view_window(controller.host.container))
}
fn controller_undo_state(controller &TerminalController) ?ControllerUndoState {
	views := controller.host.tree.root.leaves()
	if views.len == 0 { return none }
	view := views[0]
	window := macos.view_window(view)
	mut index := -1
	for i, tab in macos.native_tab_windows(view) { if tab == window { index = i; break } }
	mut focused := voidptr(unsafe { nil })
	if controller.focused != unsafe { nil } { focused = controller.focused.view }
	return ControllerUndoState{tree: controller.host.tree, frame: macos.native_window_frame(view), focused: focused, tab_group: macos.new_native_weak_object(macos.native_tab_group(view)), tab_index: index, title_override: controller.title_override, tab_color: macos.native_tab_color(view)}
}
fn restore_controller_state(snapshot ControllerUndoState) &TerminalController {
	view := macos.create_window(800, 600, '')
	mut runtime := standalone_runtime()
	app_config := native_window_config(&runtime.app.config)
	mut controller := &TerminalController{host: macos.create_split_host(view), app_config: app_config, creation_config: app_config, initial_frame: snapshot.frame, title_override: snapshot.title_override}
	runtime.controllers << controller
	controller.host.replace_tree(snapshot.tree)
	macos.release_native_object(view)
	for leaf in snapshot.tree.root.leaves() {
		mut state := state_from_userdata(macos.view_get_userdata(leaf)) or { continue }
		state.controller = controller
		state.closing = false
		if controller.focused == unsafe { nil } || leaf == snapshot.focused { controller.focused = state }
	}
	if controller.focused != unsafe { nil } {
		state := controller.focused
		macos.set_native_window_title_font(state.view, state.native_config.window_title_font_family)
		macos.apply_native_window_config(state.view, native_surface_appearance_config(state), true, state.background_color or { state.native_config.background }, state.native_config.opacity, false)
		macos.apply_native_window_frame(state.view, snapshot.frame)
		macos.configure_native_restoration(state.view, true)
		macos.restore_native_tab(state.view, snapshot.tab_group.object(), snapshot.tab_index)
		macos.set_native_tab_color(state.view, snapshot.tab_color)
		if title := snapshot.title_override { macos.set_view_title(state.view, title) }
		macos.dispatch_main(focus_controller_surface, voidptr(state))
	}
	return controller
}
fn controller_for_window(window voidptr) ?&TerminalController {
	for controller in standalone_runtime().controllers { if !controller.closed && macos.view_window(controller.host.container) == window { return controller } }
	return none
}
fn close_one_controller(controller &TerminalController) {
	mut c := unsafe { &TerminalController(controller) }
	if c.closed { return }
	window := macos.view_window(c.host.container)
	c.closed = true
	c.focused = unsafe { nil }
	macos.remove_native_undo(voidptr(c))
	c.host.replace_tree(macos.NativeSplitTree{})
	macos.close_native_window(window)
	macos.release_native_object(c.host.container)
	macos.release_native_object(window)
	collect_detached_surfaces()
}
fn close_controller_immediately(controller &TerminalController, close_window bool) {
	if controller.closed || controller.quick { return }
	mut controllers := [controller]
	if close_window {
		controllers = []&TerminalController{}
		for window in macos.native_tab_windows(controller.host.container) { if c := controller_for_window(window) { controllers << c } }
	}
	mut states := []ControllerUndoState{}
	mut key_index := -1
	for c in controllers {
		if mut snapshot := controller_undo_state(c) {
			if macos.native_window_is_key(macos.view_window(c.host.container)) { key_index = states.len }
			if close_window && controllers.len > 1 { snapshot = ControllerUndoState{...snapshot, tab_group: macos.new_native_weak_object(unsafe { nil })} }
			states << snapshot
		}
	}
	register_controller_undo(&ControllerUndo{kind: .restore, states: states, key_index: key_index, group: close_window && controllers.len > 1, close_window: close_window, name: if close_window { 'Close Window' } else { 'Close Tab' }}, voidptr(standalone_runtime().app))
	for c in controllers { close_one_controller(c) }
}
fn perform_controller_undo(context voidptr) {
	record := unsafe { &ControllerUndo(context) }
	match record.kind {
		.tree {
			if record.controller.closed { return }
			mut c := record.controller
			c.host.replace_tree(record.tree)
			if record.tree.root == unsafe { nil } { c.focused = unsafe { nil } }
			macos.invalidate_native_restorable_state(c.host.container)
			if record.focus != unsafe { nil } { queue_controller_tree_focus(record.focus, unsafe { nil }, c) }
			register_controller_undo(&ControllerUndo{kind: .tree_redo, controller: c, tree: record.opposite_tree, focus: record.opposite_focus, name: record.name}, voidptr(c))
		}
		.tree_redo {
			if record.controller.closed { return }
			c := record.controller
			mut from := voidptr(unsafe { nil })
			if c.focused != unsafe { nil } { from = c.focused.view }
			replace_controller_tree(c, record.tree, record.focus, from, record.name)
		}
		.restore {
			mut restored := []&TerminalController{}
			for state in record.states { restored << restore_controller_state(state) }
			if restored.len == 0 { return }
			if record.group { for c in restored[1..] { macos.add_native_tab(restored[0].host.container, c.host.container) } }
			index := if record.key_index >= 0 && record.key_index < restored.len { record.key_index } else { restored.len-1 }
			macos.focus_native_window(macos.view_window(restored[index].host.container))
			if record.register_redo { register_controller_undo(&ControllerUndo{kind: .close, controller: restored[0], close_window: record.close_window, name: record.name}, voidptr(restored[0])) }
		}
		.close { if record.mode != .this { close_selected_tabs_immediately(record.controller, record.mode) } else { close_controller_immediately(record.controller, record.close_window) } }
		.focus {
			if record.controller.closed { return }
			macos.dispatch_main(refocus_controller_window, voidptr(record.controller))
			register_controller_undo(&ControllerUndo{kind: .close, controller: record.controller, mode: record.mode, name: record.name}, voidptr(record.controller))
		}
		.new_close {
			if record.controller.closed { return }
			if record.new_tab { macos.dispatch_main(undo_new_tab_close, voidptr(record.controller)) }
			else { undo_new_controller_close(record.controller, false) }
			register_controller_undo(&ControllerUndo{kind: .new_redo, source: record.source, new_tab: record.new_tab, name: record.name,base_options:record.base_options}, voidptr(standalone_runtime().app))
		}
		.new_redo { new_controller_with_options(record.source,record.base_options,record.new_tab) }
	}
}
fn undo_new_tab_close(context voidptr) {
	// The undo record is released before this callback. The runtime roots the controller.
	controller := unsafe { &TerminalController(context) }
	undo_new_controller_close(controller, true)
}
fn undo_new_controller_close(controller &TerminalController, new_tab bool) {
	if controller.closed || controller.focused == unsafe { nil } { return }
	macos.native_undo_disable()
	do_close_controller(controller.focused, !new_tab, .this)
	macos.native_undo_enable()
}
fn register_new_controller_undo(state &TermState, source ?&TermState, tab bool,options apprt.SurfaceOptions) { register_controller_undo(&ControllerUndo{kind: .new_close, controller: state.controller, source: source, new_tab: tab, name: if tab { 'New Tab' } else { 'New Window' },base_options:options}, voidptr(state.controller)) }
fn do_reset_window_size(current &TermState) bool {
	if current.controller == unsafe { nil } || current.controller.closed || current.controller.quick { return false }
	config := native_controller_config(current)
	macos.reset_native_window_size(current.view, config.maximize, current.controller.initial_frame, current.initial_width, current.initial_height)
	return true
}
fn apply_initial_native_content_size(context voidptr) {
	controller:=unsafe { &TerminalController(context) }
	if controller.closed || controller.quick || controller.focused == unsafe { nil } { return }
	state:=controller.focused
	if state.closed || state.initial_width<=0 || state.initial_height<=0 { return }
	macos.reset_native_window_size(state.view,false,controller.initial_frame,state.initial_width,state.initial_height)
	config := native_controller_config(state)
	macos.adjust_native_window_origin_after_default_size(state.view,config.position_x,config.position_y)
}
