module main

import apprt
import configpkg
import macos

#insert "@VMODROOT/native_controller_tree_focus_darwin_test_abi.h"

fn C.witty_tree_focus_reset()
fn C.witty_tree_focus_track(view voidptr)
fn C.witty_tree_focus_calls(view voidptr) int
fn C.witty_tree_focus_clear_calls()
fn C.witty_tree_focus_hide_window(window voidptr)
fn C.witty_tree_focus_first_responder(window voidptr) voidptr
fn C.witty_tree_focus_retain_count(view voidptr) u64
fn C.witty_tree_focus_neutral_responder(container voidptr, window voidptr)
fn C.witty_tree_focus_launch()
fn C.witty_tree_focus_pump(seconds f64)

struct TreeFocusFixture {
	controller &TerminalController
	first &TermState
	second &TermState
	third &TermState
	window voidptr
	previous_app &apprt.App
	previous_states []&TermState
	previous_controllers []&TerminalController
}

fn tree_focus_fixture() TreeFocusFixture {
	macos.app_init()
	C.witty_tree_focus_launch()
	macos.clear_native_undo()
	C.witty_tree_focus_reset()
	mut runtime := standalone_runtime()
	previous_app := runtime.app
	previous_states := runtime.states.clone()
	previous_controllers := runtime.controllers.clone()
	view := macos.create_window(640, 480, 'tree undo focus')
	mut controller := &TerminalController{host: macos.create_split_host(view)}
	first := &TermState{view: view, controller: controller}
	second := &TermState{view: macos.create_split_surface_view(controller.host), controller: controller}
	third := &TermState{view: macos.create_split_surface_view(controller.host), controller: controller}
	controller.focused = first
	runtime.app = &apprt.App{config: configpkg.Config.default()}
	runtime.states = [first, second, third]
	runtime.controllers = [controller]
	for state in runtime.states { C.witty_tree_focus_track(state.view) }
	return TreeFocusFixture{controller: controller, first: first, second: second, third: third,
		window: macos.view_window(view), previous_app: previous_app,
		previous_states: previous_states, previous_controllers: previous_controllers}
}

fn (fixture TreeFocusFixture) cleanup() {
	fixture.wait_focus()
	macos.clear_native_undo()
	mut runtime := standalone_runtime()
	runtime.app.config.deinit()
	runtime.app = fixture.previous_app
	runtime.states = fixture.previous_states
	runtime.controllers = fixture.previous_controllers
	if !fixture.controller.closed {
		macos.close_native_window(fixture.window)
		macos.release_native_object(fixture.window)
		macos.release_native_object(fixture.controller.host.container)
	}
	for state in [fixture.first, fixture.second, fixture.third] {
		if !state.closed { macos.release_native_object(state.view) }
	}
}

fn (fixture TreeFocusFixture) neutral_responder() {
	C.witty_tree_focus_neutral_responder(fixture.controller.host.container, fixture.window)
	C.witty_tree_focus_clear_calls()
}

fn (fixture TreeFocusFixture) wait_focus() {
	for _ in 0 .. 100 {
		C.witty_tree_focus_pump(0.02)
		if controller_tree_focus_instance.tasks.len == 0 && !macos.native_focus_retains_view(fixture.first.view) && !macos.native_focus_retains_view(fixture.second.view) && !macos.native_focus_retains_view(fixture.third.view) { return }
	}
	assert controller_tree_focus_instance.tasks.len == 0
	assert !macos.native_focus_retains_view(fixture.first.view)
	assert !macos.native_focus_retains_view(fixture.second.view)
	assert !macos.native_focus_retains_view(fixture.third.view)
}

fn test_tree_replacement_captures_explicit_from_before_outer_queue() {
	fixture := tree_focus_fixture()
	defer { fixture.cleanup() }
	c := fixture.controller
	tree := c.host.tree.inserting(fixture.second.view, fixture.first.view, .right) or { panic(err) }
	before_first := C.witty_tree_focus_retain_count(fixture.first.view)
	before_second := C.witty_tree_focus_retain_count(fixture.second.view)
	macos.native_undo_begin()
	replace_controller_tree(c, tree, fixture.second.view, fixture.first.view, 'New Split')
	macos.native_undo_end()
	// Both the undo closure and outer focus closure capture their views.
	assert C.witty_tree_focus_retain_count(fixture.first.view) >= before_first + 2
	assert C.witty_tree_focus_retain_count(fixture.second.view) >= before_second + 2
	assert controller_tree_focus_instance.tasks.len == 1
	fixture.neutral_responder()
	assert C.witty_tree_focus_calls(fixture.first.view) == 0
	fixture.wait_focus()
	assert controller_tree_focus_instance.tasks.len == 0
	assert C.witty_tree_focus_calls(fixture.first.view) == 1
	assert C.witty_tree_focus_calls(fixture.second.view) == 0
}

fn test_tree_undo_redo_use_captured_tree_and_live_focus() {
	fixture := tree_focus_fixture()
	defer { fixture.cleanup() }
	mut c := fixture.controller
	new_tree := c.host.tree.inserting(fixture.second.view, fixture.first.view, .right) or { panic(err) }
	macos.native_undo_begin()
	replace_controller_tree(c, new_tree, fixture.second.view, fixture.first.view, 'New Split')
	macos.native_undo_end()
	fixture.neutral_responder()
	fixture.wait_focus()
	c.focused = fixture.second
	// Later non-undoable tree changes cannot replace the newTree captured by
	// the original undo closure. Keep the third view live in this current tree.
	c.host.replace_tree(new_tree.inserting(fixture.third.view, fixture.first.view, .down) or { panic(err) })
	c.focused = fixture.third
	assert macos.native_undo()
	assert c.host.tree.root.leaves() == [fixture.first.view]
	assert !fixture.second.closed && !fixture.third.closed
	c.focused = fixture.first
	fixture.neutral_responder()
	fixture.wait_focus()
	assert C.witty_tree_focus_calls(fixture.first.view) == 1
	assert C.witty_tree_focus_calls(fixture.third.view) == 0
	assert C.witty_tree_focus_calls(fixture.second.view) == 0
	c.focused = fixture.third
	assert macos.native_redo()
	assert c.host.tree.root.equal(new_tree.root)
	assert standalone_runtime().undos.last().focus == fixture.third.view
	fixture.neutral_responder()
	fixture.wait_focus()
	assert C.witty_tree_focus_calls(fixture.third.view) == 1
	// The following undo restores the focus captured by redo's invocation.
	c.focused = fixture.second
	assert macos.native_undo()
	assert controller_tree_focus_instance.tasks.last().to == fixture.third.view
}

fn test_queued_window_presentation_survives_collection() {
	fixture := tree_focus_fixture()
	defer { fixture.cleanup() }
	C.witty_tree_focus_hide_window(fixture.window)
	assert !macos.native_window_is_visible(fixture.window)
	queue_new_controller_show(NewControllerShowTask{controller: fixture.controller}, show_new_controller)
	gc_collect()
	C.witty_tree_focus_pump(0.05)
	assert macos.native_window_is_visible(fixture.window)
}

fn test_restored_focus_retries_until_the_surface_reaches_its_window() {
	fixture := tree_focus_fixture()
	defer { fixture.cleanup() }
	mut controller := fixture.controller
	assert macos.view_window(fixture.second.view) == unsafe { nil }
	queue_restore_native_focus(fixture.second, fixture.window)
	gc_collect()
	C.witty_tree_focus_pump(0.02)
	assert C.witty_tree_focus_first_responder(fixture.window) != fixture.second.view
	tree := controller.host.tree.inserting(fixture.second.view, fixture.first.view, .right) or { panic(err) }
	controller.host.replace_tree(tree)
	fixture.neutral_responder()
	gc_collect()
	C.witty_tree_focus_pump(0.1)
	assert C.witty_tree_focus_first_responder(fixture.window) == fixture.second.view
}

fn test_queued_fullscreen_ignores_a_closed_restored_surface() {
	fixture := tree_focus_fixture()
	defer { fixture.cleanup() }
	mut state := fixture.first
	queue_restore_native_fullscreen(state, .visible_menu)
	state.closed = true
	gc_collect()
	C.witty_tree_focus_pump(0.05)
	state.closed = false
	assert macos.native_fullscreen_mode(state.view) == .native
}

fn test_new_tab_undo_closes_after_the_undo_record_is_released() {
	fixture := tree_focus_fixture()
	defer { fixture.cleanup() }
	controller := fixture.controller
	macos.native_undo_begin()
	register_controller_undo(&ControllerUndo{kind: .new_close, controller: controller, new_tab: true,
		name: 'New Tab'}, voidptr(controller))
	macos.native_undo_end()
	assert macos.native_undo()
	assert !controller.closed
	assert !standalone_runtime().undos.any(it.kind == .new_close)
	gc_collect()
	C.witty_tree_focus_pump(0.05)
	assert controller.closed
}
