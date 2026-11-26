module main

import configpkg
import apprt
import input
import macos
import osc
import renderer
import terminal

// Ghostty.App.action reports true after every recognized void handler, including
// its early guards. Only the source's explicit Bool handlers report performability.
fn native_action_is_void(action apprt.ActionKey) bool {
	return action in [.start_search, .end_search, .search_total, .search_selected, .key_sequence,
		.key_table, .progress_report, .readonly, .ring_bell, .renderer_health, .mouse_shape,
		.mouse_visibility, .mouse_over_link, .desktop_notification, .float_window, .pwd,
		.reset_window_size, .inspector, .render_inspector, .toggle_command_palette, .scrollbar,
		.color_change, .set_title, .initial_size, .cell_size, .equalize_splits,
		.toggle_fullscreen, .close_tab, .close_window, .toggle_maximize, .toggle_background_opacity,
		.secure_input, .check_for_updates, .toggle_visibility]
}

// Native consumers of Ghostty.App.action. Core actions are produced by the
// translated embedded runtime; these handlers present the source native state.
fn runtime_native_action(app &apprt.App, target apprt.Target, state ?&TermState, action apprt.RuntimeAction) bool {
	is_app := target is apprt.AppTarget
	if action.action == .secure_input {
		data := action.data
		if data is apprt.SecureInput {
			if int(data) !in [0, 1, 2] { return true }
			if is_app {
				macos.secure_set_global(int(data))
			} else if mut current := state {
				if !current.closed && current.actions != unsafe { nil } && app.config.macos_auto_secure_input {
					current.actions.secure_input(int(data))
				}
			}
			return true
		}
	}
	if action.action == .check_for_updates {
		macos.native_update_check()
		return true
	}
	if action.action == .toggle_visibility {
		macos.toggle_native_visibility()
		return true
	}
	if action.action == .goto_window {
		data := action.data
		if data is apprt.GotoWindow { return macos.goto_native_window(int(data)) != none }
	}
	if action.action == .prompt_title && is_app {
		data := action.data
		if data is apprt.PromptTitle {
			if data == .tab {
				view := macos.main_terminal_view()
				if current := state_from_userdata(macos.view_get_userdata(view)) {
					if current.controller != unsafe { nil } {
						current.actions.prompt_title(true, current.controller.title_override or { macos.native_window_title(view) })
						return true
					}
				}
			}
		}
		return false
	}
	mut current := state or {
		if native_action_is_void(action.action) {
			if is_app { eprintln('${action.action} does nothing with an app target') }
			return true
		}
		return false
	}

	if current.closed || current.actions == unsafe { nil } {
		return native_action_is_void(action.action)
	}
	mut overlay := current.actions
	data := action.data
	match action.action {
		.show_child_exited {
			if data is apprt.ChildExited && data.runtime_ms > 0 && macos.native_view_has_window(current.view) {
				overlay.show_child_exit(data.exit_code, data.runtime_ms, app.config.abnormal_command_exit_runtime)
				return true
			}
		}
		.toggle_command_palette {
			if current.controller != unsafe { nil } && current.controller.host.tree.root.find(current.view) != none {
				focused := current.controller.focused
				if focused != unsafe { nil } && !focused.closed && focused.actions != unsafe { nil } {
					mut palette_surface := focused.actions
					palette_surface.toggle_command_palette(native_command_options(app))
				}
			}
			return true
		}
		.prompt_title {
			if data is apprt.PromptTitle {
				if data == .tab && (current.controller == unsafe { nil } || !macos.native_view_has_window(current.view)) {
					return false
				}
				overlay.prompt_title(data == .tab, if data == .tab {
					current.controller.title_override or {
						macos.native_window_title(current.view)
					}
				} else {
					overlay.title
				})
				return true
			}
		}
		.pwd {
			if data is apprt.PwdValue {
				if pwd := macos.source_c_utf8(data.pwd) {
					overlay.set_pwd(pwd, native_controller_config(current).proxy_icon)
				}
				return true
			}
		}
		.move_tab {
			if data is apprt.MoveTab {
				if macos.native_window_tabs(current.view).len <= 1 { return false }
				if current.controller != unsafe { nil } && current.controller.focused != current {
					return true
				}
				return macos.move_native_tab(current.view, data.amount)
			}
		}
		.float_window {
			if data is apprt.FloatWindow {
				macos.float_native_window(current.view, int(data))
				return true
			}
		}
		.reset_window_size {
			do_reset_window_size(current)
			return true
		}
		.color_change {
			if data is apprt.ColorChange {
				if data.kind == .background {
					queue_native_background_color(current, data)
				}
				return true
			}
		}
		.toggle_maximize {
			if current.controller != unsafe { nil } && current.controller.host.tree.root.find(current.view) != none {
				macos.maximize_native_window(current.controller.host.container)
			}
			return true
		}
		.toggle_background_opacity {
			if current.controller != unsafe { nil } && macos.native_view_has_window(current.view) {
				mut controller := current.controller
				controller.force_opaque = !controller.force_opaque
				sync_native_window(current)
			}
			return true
		}
		.inspector {
			if data is apprt.InspectorAction {
				overlay.control_inspector(int(data))
				return true
			}
		}
		.render_inspector {
			overlay.render_inspector()
			return true
		}
		.scrollbar {
			if data is terminal.Scrollbar {
				overlay.set_scrollbar(data.total, data.offset, data.len)
				return true
			}
		}
		.desktop_notification {
			if data is apprt.DesktopNotificationValue {
				if title := macos.source_c_utf8(data.title) {
					if body := macos.source_c_utf8(data.body) { overlay.desktop_notification(title, body) }
				}
				return true
			}
		}
		.start_search {
			if data is apprt.StartSearch {
				overlay.start_search(macos.source_c_utf8_repair(data.needle))
				return true
			}
		}
		.end_search {
			overlay.end_search()
			return true
		}
		.search_total {
			if data is apprt.SearchTotal {
				overlay.search_counts(overlay.search_selected, data.total)
				return true
			}
		}
		.search_selected {
			if data is apprt.SearchSelected {
				overlay.search_counts(data.selected, overlay.search_total)
				return true
			}
		}
		.key_sequence {
			if data is apprt.KeySequence {
				match data {
					input.Trigger {
						if shortcut := macos.shortcut_description(data) {
							overlay.set_key_sequence(true, shortcut)
						} else {
							eprintln('unable to convert trigger to keyboard shortcut')
						}
					}
					apprt.KeySequenceEnd { overlay.set_key_sequence(false, '') }
				}

				return true
			}
		}
		.key_table {
			if data is apprt.KeyTable {
				match data {
					apprt.KeyTableActivate { overlay.set_key_table(0, macos.source_utf8(data.name) or { '' }) }
					apprt.KeyTableDeactivate { overlay.set_key_table(1, '') }
					apprt.KeyTableDeactivateAll { overlay.set_key_table(2, '') }
				}

				return true
			}
		}
		.progress_report {
			if data is osc.ProgressReport {
				overlay.set_progress(int(data.state), data.progress)
				return true
			}
		}
		.readonly {
			if data is apprt.Readonly {
				overlay.set_readonly(data == .on)
				return true
			}
		}
		.ring_bell {
			overlay.ring_bell()
			native_surface_title_changed(voidptr(current), overlay.title)
			overlay.bell_notification(app.config.bell_features.system(),
				app.config.bell_features.attention())
			return true
		}
		.renderer_health {
			if data is renderer.Health {
				overlay.renderer_health(data == .healthy)
				return true
			}
		}
		.mouse_shape {
			if data is terminal.MouseShape {
				macos.set_cursor_shape(current.view, int(data))
				return true
			}
		}
		.mouse_visibility {
			if data is apprt.MouseVisibility {
				if data in [.visible, .hidden] { macos.set_cursor_visibility(data == .visible) }
				return true
			}
		}
		.mouse_over_link {
			if data is apprt.MouseOverLink {
				overlay.mouse_over_link(macos.source_utf8(data.url) or { '' })
				return true
			}
		}
		else {}
	}

	return native_action_is_void(action.action)
}

fn native_begin_key_down(userdata voidptr) {
	if mut state := state_from_userdata(userdata) {
		if !state.closed && state.actions != unsafe { nil } { state.actions.begin_key_down() }
	}
}

fn native_surface_title_changed(userdata voidptr, title string) {
	state := state_from_userdata(userdata) or { return }
	if state.closed || state.controller == unsafe { nil } || state.controller.focused != state {
		return
	}
	value := state.controller.title_override or { title }
	macos.set_view_title(state.view, if state.actions.bell
		&& standalone_runtime().app.config.bell_features.title() {
		'🔔 ${value}'
	} else {
		value
	})
}

fn native_tab_title_changed(userdata voidptr, title ?string) {
	mut state := state_from_userdata(userdata) or { return }
	if state.closed || state.controller == unsafe { nil } { return }
	state.controller.title_override = title
	macos.invalidate_native_restorable_state(state.view)
	native_surface_title_changed(userdata, state.actions.title)
}

fn native_command_options(app &apprt.App) []macos.NativeCommandOption {
	mut options := []macos.NativeCommandOption{}
	for state in standalone_runtime().states {
		if state.closed || state.surface == unsafe { nil } {
			continue
		}
		title := if state.actions.title.len > 0 {
			state.actions.title
		} else {
			macos.native_window_title(state.view)
		}
		shown := if title.len > 0 { title } else { 'Untitled' }
		pwd := macos.abbreviated_pwd(state.actions.saved_pwd() or { '' })
		options << macos.NativeCommandOption{
			title:         'Focus: ${shown}'
			subtitle:      if pwd.len > 0 && !shown.contains(pwd) { pwd } else { '' }
			focus_view:    state.view
			sort_key:      u64(state.view)
			leading_color: macos.native_tab_display_color(state.view)
			leading_icon:  'rectangle.on.rectangle'
		}
	}
	for command in app.config.command_palette_entry.items {
		if command.action.tag() in [.toggle_tab_overview, .toggle_window_decorations] {
			continue
		}
		symbols := if trigger := app.config.keybind.set.get_trigger(command.action) {
			macos.command_shortcut_symbols(trigger)
		} else {
			[]string{}
		}
		options << macos.NativeCommandOption{
			title:       macos.source_c_utf8_repair(command.title)
			description: macos.source_c_utf8_repair(command.description)
			action:      command.action.format()
			symbols:     symbols
		}
	}
	mut updates := []macos.NativeCommandOption{}
	if macos.native_update_is_installable() {
		updates << macos.NativeCommandOption{
			title:        if macos.native_update_is_available() {
				'Update Witty and Restart'
			} else {
				macos.native_update_text()
			}
			invoke:       macos.native_update_install
			description:  macos.native_update_description()
			leading_icon: macos.native_update_icon_name() or { 'shippingbox.fill' }
			badge:        macos.native_update_badge()
			emphasis:     true
		}
		updates << macos.NativeCommandOption{ title: 'Cancel or Skip Update', description: 'Dismiss the current update process', invoke: macos.native_update_cancel }
	}
	updates << macos.sorted_command_options(options)
	return updates
}

fn native_present_view(_userdata voidptr, view voidptr) {
	state := state_from_userdata(macos.view_get_userdata(view)) or { return }
	if state.closed { return }
	if state.controller == unsafe { nil } || state.controller.host.tree.root.find(view) == none { return }
	macos.present_view(view)
	if state.actions != unsafe { nil } { state.actions.presented() }
}

fn native_action_config(current &TermState, config &configpkg.Config) {
	if current.closed || current.actions == unsafe { nil } { return }
	mut actions := current.actions
	actions.bell_border = config.bell_features.border()
	actions.secure_indication = config.macos_secure_input_indication
	actions.configure_resize_indicator(config.resize_overlay, config.resize_overlay_position,
		config.resize_overlay_duration.duration)
	actions.configure_title(config.macos_titlebar_proxy_icon == .visible)
	color := config.background
	actions.visual_background = (u32(color.r) << 16) | (u32(color.g) << 8) | u32(color.b)
	actions.configure_scroll(config.scrollbar == .never, (0.299 * f64(color.r) + 0.587 * f64(color.g) + 0.114 * f64(color.b)) / 255 > 0.5)
	actions.refresh_config()
}

fn native_menu_application_action(action string) bool {
	runtime := standalone_runtime()
	if runtime.app == unsafe { nil } { return false }
	kind := match action {
		'new_window' { apprt.ActionKey.new_window }
		'close_all_windows' { .close_all_windows }
		'undo' { .undo }
		'redo' { .redo }
		'toggle_quick_terminal' { .toggle_quick_terminal }
		'toggle_visibility' { .toggle_visibility }
		else { return false }
	}
	return runtime_action(runtime.app, apprt.AppTarget{}, apprt.RuntimeAction{ action: kind, data: apprt.ActionVoid{} })
}
