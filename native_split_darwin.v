module main

import apprt
import witty_macos as macos
fn do_new_split(current &TermState, direction apprt.SplitDirection) bool {
	if int(direction) !in [0, 1, 2, 3] { return false }
	if current.controller == unsafe { nil } || current.closed { return false }
	mut controller := current.controller
	if _ := controller.host.tree.root.find(current.view) {} else { return false }
	view := macos.create_split_surface_view(controller.host)
	mut added := create_surface(view, inherited_options(current, .split)) or { return false }
	added.controller = controller
	new_tree := controller.host.tree.inserting(view, current.view, match direction { .left { macos.SplitNewDirection.left } .right { .right } .up { .up } .down { .down } }) or {
		eprintln('failed to insert split: ${err}')
		collect_detached_surfaces()
		return false
	}
	replace_controller_tree(controller, new_tree, view, current.view, 'New Split')
	controller.focused = added
	return true
}
fn do_goto_split(current &TermState, direction apprt.GotoSplit) bool {
	if int(direction) !in [0, 1, 2, 3, 4, 5] { return false }
	if current.controller == unsafe { nil } || !macos.native_view_has_window(current.view) { return false }
	mut host := current.controller.host
	if host.tree.root == unsafe { nil } || host.tree.root.is_leaf() { return false }
	node := host.tree.root.find(current.view) or { return false }
	view := host.tree.focus_target(match direction { .previous { macos.SplitFocusDirection.previous } .next { .next } .left { .left } .right { .right } .up { .up } .down { .down } }, node) or { return false }
	if host.tree.zoomed != unsafe { nil } {
        mut zoomed := unsafe { &macos.NativeSplitNode(nil) }
        if native_controller_config(current).preserve_split_zoom {
            if selected := host.tree.root.find(view) { zoomed = selected }
        }
        host.replace_tree(macos.NativeSplitTree{root:host.tree.root,zoomed:zoomed})
	}
	macos.invalidate_native_restorable_state(host.container)
	macos.move_focus(view, current.view, none)
	return true
}
fn do_resize_split(current &TermState, data apprt.ResizeSplit) bool {
	if int(data.direction) !in [0, 1, 2, 3] { return false }
	if current.controller == unsafe { nil } || !macos.native_view_has_window(current.view) { return false }
	mut host := current.controller.host
	if host.tree.root == unsafe { nil } || host.tree.root.is_leaf() { return false }
	// App.swift acknowledges a valid request once the window has splits.
	// The receiver may subsequently ignore a target absent from its tree.
	node := host.tree.root.find(current.view) or { return true }
	tree := host.tree.resizing(node, data.amount, match data.direction { .left { macos.SplitFocusDirection.left } .right { .right } .up { .up } .down { .down } }, macos.SplitBounds{width: macos.view_width(host.container), height: macos.view_height(host.container)}) or { return true }
	host.replace_tree(tree)
	macos.invalidate_native_restorable_state(host.container)
	return true
}
fn do_toggle_split_zoom(current &TermState) bool {
	if current.controller == unsafe { nil } || !macos.native_view_has_window(current.view) { return false }
	mut host:=current.controller.host
	if host.tree.root == unsafe { nil } || host.tree.root.is_leaf() { return false }
	node:=host.tree.root.find(current.view) or { return true }
	host.replace_tree(macos.NativeSplitTree{root:host.tree.root,zoomed:if host.tree.zoomed==node { unsafe { &macos.NativeSplitNode(nil) } } else { node }})
	macos.invalidate_native_restorable_state(host.container)
	macos.focus_native_window(macos.view_window(host.container))
	macos.move_focus(current.view, unsafe { nil }, none)
	return true
}
