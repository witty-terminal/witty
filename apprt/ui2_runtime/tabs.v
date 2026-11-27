module ui2_runtime

import apprt
import datastruct
import gg
import log
import math
import ui2

fn (app &App) active_pane() ?&Pane {
	if app.tabs.len == 0 { return none }
	tab := &app.tabs[app.active_tab]
	node := tab.tree.nodes[tab.active.idx()]
	if node is datastruct.Leaf[Pane] { return node.view }
	return none
}

fn (app &App) pane_by_id(id int) ?&Pane {
	for tab in app.tabs {
		mut iterator := tab.tree.iterator()
		for {
			entry := iterator.next() or { break }
			if entry.view.id == id { return entry.view }
		}
	}
	return none
}

fn (mut app App) new_tab(parent ?&Pane) ! {
	mut pane := app.create_pane(if app.runtime.config.tab_inherit_working_directory {
		parent
	} else {
		none
	})!
	app.tabs << Tab{ tree: datastruct.SplitTree.new[Pane](pane) }
	app.select_pane(app.tabs.len - 1, datastruct.handle_root)
}

fn (mut app App) new_split(direction apprt.SplitDirection) ! {
	if app.tabs.len == 0 { return }
	previous := app.active_pane() or { return }
	parent := ?&Pane(previous)
	mut pane := app.create_pane(if app.runtime.config.split_inherit_working_directory {
		parent
	} else {
		none
	})!
	mut tab := &app.tabs[app.active_tab]
	mut insert := datastruct.SplitTree.new[Pane](pane)
	defer { insert.free() }
	tree := tab.tree.split_(tab.active, match direction {
		.left { .left }
		.right { .right }
		.up { .up }
		.down { .down }
	}, 0.5, &insert)
	tab.tree.free()
	tab.tree = tree
	app.focus_pane_id(previous.id)
	app.focus_pane_id(pane.id)
}

fn (mut app App) focus_pane_id(id int) {
	for i, tab in app.tabs {
		mut iterator := tab.tree.iterator()
		for {
			entry := iterator.next() or { break }
			if entry.view.id == id {
				app.select_pane(i, entry.handle)
				return
			}
		}
	}
}

fn (mut app App) select_pane(tab int, handle datastruct.Handle) {
	if previous := app.active_pane() {
		mut pane := unsafe { previous }
		pane.surface.focus_callback(false) or { log.warn(err.msg()) }
	}
	app.active_tab = tab
	app.tabs[tab].active = handle
	app.apply_focus()
}

fn (mut app App) apply_focus() {
	if current := app.active_pane() {
		mut pane := unsafe { current }
		gg.set_window_title(pane.title)
		pane.surface.focus_callback(app.focused) or { log.warn(err.msg()) }
	}
	ui2.request_refresh()
}

fn (mut app App) goto_split(direction apprt.GotoSplit) {
	if app.tabs.len == 0 { return }
	tab := &app.tabs[app.active_tab]
	to := match direction {
		.previous { datastruct.Goto(datastruct.GotoPreviousWrapped{}) }
		.next { datastruct.Goto(datastruct.GotoNextWrapped{}) }
		.left { datastruct.Goto(datastruct.GotoSpatial{ direction: .left }) }
		.right { datastruct.Goto(datastruct.GotoSpatial{ direction: .right }) }
		.up { datastruct.Goto(datastruct.GotoSpatial{ direction: .up }) }
		.down { datastruct.Goto(datastruct.GotoSpatial{ direction: .down }) }
	}
	if handle := tab.tree.goto_(tab.active, to) {
		if _ := tab.tree.zoomed {
			app.tabs[app.active_tab].tree.zoom(handle)
		}
		app.select_pane(app.active_tab, handle)
	}
}

fn (mut app App) resize_split(value apprt.ResizeSplit) {
	if app.tabs.len == 0 { return }
	mut tab := &app.tabs[app.active_tab]
	bounds := ui2.bounds()
	horizontal := value.direction in [.left, .right]
	size := if horizontal { bounds.width } else { bounds.height }
	if size <= 0 { return }
	sign := if value.direction in [.left, .up] { -1 } else { 1 }
	tree := tab.tree.resize(tab.active, if horizontal { .horizontal } else { .vertical },
		f32(sign) * f32(value.amount) / f32(size))
	tab.tree.free()
	tab.tree = tree
}

fn (mut app App) close_pane(id int) {
	for i, tab in app.tabs {
		mut iterator := tab.tree.iterator()
		for {
			entry := iterator.next() or { break }
			if entry.view.id != id { continue }
			next := tab.tree.goto_(entry.handle, datastruct.GotoNext{}) or {
				tab.tree.goto_(entry.handle, datastruct.GotoPrevious{}) or { entry.handle }
			}
			next_node := tab.tree.nodes[next.idx()]
			active_node := tab.tree.nodes[tab.active.idx()]
			replacement := if tab.active == entry.handle && next_node is datastruct.Leaf[Pane] {
				next_node.view.id
			} else if active_node is datastruct.Leaf[Pane] {
				active_node.view.id
			} else {
				id
			}
			tree := tab.tree.remove(entry.handle)
			app.tabs[i].tree.free()
			if tree.is_empty() {
				app.tabs.delete(i)
				if app.active_tab >= i {
					app.active_tab = int(math.max(0, app.active_tab - 1))
				}
				app.apply_focus()
			} else {
				app.tabs[i].tree = tree
				mut remaining := tree.iterator()
				for {
					item := remaining.next() or { break }
					if item.view.id == replacement {
						app.tabs[i].active = item.handle
						break
					}
				}
				if app.active_tab == i { app.apply_focus() }
			}
			mut pane := unsafe { entry.view }
			app.destroy_pane(mut pane)
			if app.tabs.len == 0 { quit_window() }
			return
		}
	}
}

fn close_surface(data voidptr, confirm bool) {
	pane := unsafe { &Pane(data) }
	mut app := g_app
	if confirm {
		app.dialog = Dialog{
			title:   'Close terminal?'
			message: 'A terminal process is still running.'
			button:  'Close terminal'
			action:  .close
			pane_id: pane.id
		}
		ui2.request_refresh()
	} else {
		// The caller may still be inside a core.Surface method.
		id := pane.id
		ui2.after(0, fn [id] () { g_app.close_pane(id) })
	}
}

fn (mut app App) close_tab(index int, mode apprt.CloseTabMode) {
	mut ids := []int{}
	for i, tab in app.tabs {
		selected := match mode {
			.this { i == index }
			.other { i != index }
			.right { i > index }
		}
		if !selected { continue }
		mut iterator := tab.tree.iterator()
		for {
			entry := iterator.next() or { break }
			ids << entry.view.id
		}
	}
	if ids.len == 0 { return }
	for id in ids {
		pane := app.pane_by_id(id) or { continue }
		if pane.surface.needs_confirm_quit() {
			app.dialog = Dialog{
				title:   'Close tabs?'
				message: 'A terminal process is still running.'
				button:  'Close tabs'
				action:  .close_tabs
				panes:   ids
			}
			return
		}
	}
	ui2.after(0, fn [ids] () {
		for id in ids { g_app.close_pane(id) }
	})
}
