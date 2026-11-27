module ui2_runtime

import apprt
import configpkg
import gg
import internal_os
import osc
import sokol.sapp
import terminal
import ui2

fn (app &App) action_pane(target apprt.Target) ?&Pane {
	if target is apprt.SurfaceTarget {
		if !isnil(app.initializing) && voidptr(app.initializing.surface) == target.surface {
			return app.initializing
		}
		for tab in app.tabs {
			mut iterator := tab.tree.iterator()
			for {
				entry := iterator.next() or { break }
				if voidptr(entry.view.surface) == target.surface { return entry.view }
			}
		}
		return none
	}
	return app.active_pane()
}

fn dispatch_action(data voidptr, action apprt.RuntimeAction) !bool {
	mut app := unsafe { &App(data) }
	if app.app_action(action)! {
		ui2.request_refresh()
		return true
	}
	mut pane := app.action_pane(action.target) or { return false }
	result := app.pane_action(mut pane, action)!
	if result { ui2.request_refresh() }
	return result
}

fn (mut app App) app_action(event apprt.RuntimeAction) !bool {
	data := event.data
	match event.action {
		.quit, .close_window, .close_all_windows {
			app.confirm_close()
		}
		.new_window { app.new_window(app.action_pane(event.target))! }
		.new_tab { app.new_tab(app.action_pane(event.target))! }
		.close_tab {
			if data is apprt.CloseTabMode { app.close_tab(app.active_tab, data) }
		}
		.goto_tab {
			if data is apprt.GotoTab && app.tabs.len > 0 {
				index := match data {
					.previous { (app.active_tab + app.tabs.len - 1) % app.tabs.len }
					.next { (app.active_tab + 1) % app.tabs.len }
					.last { app.tabs.len - 1 }
					else { int(data) }
				}
				if index >= 0 && index < app.tabs.len {
					app.select_pane(index, app.tabs[index].active)
				}
			}
		}
		.move_tab {
			if data is apprt.MoveTab && app.tabs.len > 1 {
				i := app.active_tab
				j := ((i + data.amount) % app.tabs.len + app.tabs.len) % app.tabs.len
				tab := app.tabs[i]
				app.tabs.delete(i)
				app.tabs.insert(j, tab)
				app.active_tab = j
			}
		}
		.new_split {
			if data is apprt.SplitDirection { app.new_split(data)! }
		}
		.goto_split {
			if data is apprt.GotoSplit { app.goto_split(data) }
		}
		.resize_split {
			if data is apprt.ResizeSplit { app.resize_split(data) }
		}
		.equalize_splits {
			if app.tabs.len > 0 {
				mut tree := &app.tabs[app.active_tab].tree
				replacement := tree.equalize()
				tree.free()
				unsafe { *tree = replacement }
			}
		}
		.toggle_split_zoom {
			if app.tabs.len > 0 {
				mut tab := &app.tabs[app.active_tab]
				if tab.tree.is_split() {
					if tab.tree.zoomed == none {
						tab.tree.zoom(tab.active)
					} else {
						tab.tree.zoom(none)
					}
				}
			}
		}
		.toggle_fullscreen { sapp.toggle_fullscreen() }
		.toggle_maximize { return ui2.toggle_maximize_window() }
		.open_config {
			path := configpkg.open_path()!
			internal_os.open(.text, path)!
		}
		.reload_config {
			if data is apprt.ReloadConfig {
				mut config := if data.soft {
					app.runtime.config.clone()
				} else {
					configpkg.Config.load_argv(internal_os.process_args())!
				}
				if app.screenshot != '' {
					config.wait_after_command = true
					config.window_show_tab_bar = .never
				}
				app.core.update_config(mut app.runtime, &config)!
				if text := config_diagnostics(&config) {
					app.dialog = Dialog{ title: 'Configuration', message: text }
				}
			}
		}
		.toggle_command_palette {
			app.palette = !app.palette
			if app.palette {
				app.palette_query = ''
				ui2.focus('palette-query')
			} else {
				ui2.focus('')
			}
		}
		.config_change {
			$if macos {
				if app.ready && event.target is apprt.AppTarget {
					configure_window_background(&app.runtime.config)
				}
			}
		}
		.render {}
		.open_url {
			if data is apprt.OpenUrl { internal_os.open(data.kind, data.url)! }
		}
		.desktop_notification {
			if data is apprt.DesktopNotificationValue {
				app.toast = '${data.title}  ${data.body}'
				if app.toast_timer != ui2.TimerId(0) { ui2.cancel_timer(app.toast_timer) }
				app.toast_timer = ui2.after(4, fn () { g_app.toast = '' })
			}
		}
		else { return false }
	}
	return true
}

fn (mut app App) pane_action(mut pane Pane, event apprt.RuntimeAction) !bool {
	data := event.data
	match event.action {
		.set_title {
			if data is apprt.SetTitle {
				pane.title = data.title.clone()
				pane.host.title = pane.title
				if current := app.active_pane() {
					if current.id == pane.id { gg.set_window_title(pane.title) }
				}
			}
		}
		.present_terminal { app.focus_pane_id(pane.id) }
		.start_search {
			if data is apprt.StartSearch {
				pane.query = data.needle.clone()
				pane.search = true
				ui2.focus('find-query')
			}
		}
		.end_search {
			pane.search = false
			ui2.focus('')
		}
		.search_total {
			if data is apprt.SearchTotal { pane.matches = data.total }
		}
		.search_selected {
			if data is apprt.SearchSelected { pane.selected = data.selected }
		}
		.readonly {
			if data is apprt.Readonly { pane.readonly = data == .on }
		}
		.progress_report {
			if data is osc.ProgressReport {
				pane.progress = if data.state == .remove { none } else { data.progress }
			}
		}
		.mouse_shape {
			if data is terminal.MouseShape {
				pane.mouse_cursor = match data {
					.text, .vertical_text { .ibeam }
					.pointer { .pointing_hand }
					.crosshair, .cell { .crosshair }
					.ew_resize, .col_resize, .e_resize, .w_resize { .resize_ew }
					.ns_resize, .row_resize, .n_resize, .s_resize { .resize_ns }
					.ne_resize, .sw_resize, .nesw_resize { .resize_nesw }
					.nw_resize, .se_resize, .nwse_resize { .resize_nwse }
					.no_drop, .not_allowed { .not_allowed }
					else { .arrow }
				}
			}
		}
		.scrollbar {
			if data is terminal.Scrollbar { pane.scrollbar = data }
		}
		.mouse_visibility {
			if data is apprt.MouseVisibility { sapp.show_mouse(data == .visible) }
		}
		.show_child_exited {
			if app.screenshot == '' {
				app.toast = 'Terminal process exited'
			}
		}
		.ring_bell {
			app.toast = 'Terminal bell'
			if app.toast_timer != ui2.TimerId(0) { ui2.cancel_timer(app.toast_timer) }
			app.toast_timer = ui2.after(1, fn () { g_app.toast = '' })
		}
		else { return false }
	}
	return true
}
