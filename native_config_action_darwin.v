module main

import apprt
import configpkg
import macos

@[heap]
struct NativeConfigChangeTask {
mut:
	config configpkg.Config
	target ?&TermState
}
fn native_config_change(app &apprt.App, action_target apprt.Target, target ?&TermState, config &configpkg.Config) bool {
	if config == unsafe { nil } { return false }
	mut owned := config.clone()
	// App.swift takes ownership before inspecting the target. An unresolved
	// surface still has surface scope and must never replace the app config.
	if action_target is apprt.SurfaceTarget && target == none {
		owned.deinit()
		return false
	}
	if action_target is apprt.AppTarget {
		mut host_app := unsafe { &apprt.App(app) }
		host_app.config.deinit()
		host_app.config = owned.clone()
	}
	task := &NativeConfigChangeTask{config: owned, target: target}
	macos.dispatch_main(native_config_change_main, voidptr(task))
	return true
}
fn native_config_change_main(context voidptr) {
	mut task := unsafe { &NativeConfigChangeTask(context) }
	defer { task.config.deinit() }
	projection := native_window_config(&task.config)
	if mut current := task.target {
		if !current.closed {
			current.native_config = projection
			native_surface_action_config(current,&task.config)
			if current.controller != unsafe { nil } && current.controller.focused == current { sync_native_window(current) }
		}
	} else {
		sync_config_menu(&task.config)
		macos.sync_native_application_appearance(projection)
		macos.update_quick_terminal_config(native_quick_config(&task.config))
		macos.apply_native_save_state(int(task.config.window_save_state))
		mut runtime := standalone_runtime()
		for mut controller in runtime.controllers {
			if controller.closed { continue }
			controller.app_config = projection
			sync_native_split_appearance(mut controller)
			// QuickTerminalWindow is an NSPanel, so the regular TerminalWindow
			// empty-tree branch is excluded regardless of focusedSurface.
			if controller.quick {
				macos.sync_quick_terminal_appearance(controller.force_opaque)
				sync_native_surface_color_scheme(mut controller)
				continue
			}
			// TerminalController only applies app appearance when its tree is empty.
			if controller.host != unsafe { nil } && controller.host.tree.root == unsafe { nil } {
				created := controller.creation_config
				macos.set_native_window_title_font(controller.host.container, projection.window_title_font_family)
				empty := macos.NativeWindowConfig{...created,shadow:projection.shadow,theme:projection.theme,background:projection.background,opacity:projection.opacity,blur:projection.blur}
				macos.apply_native_window_config(controller.host.container,empty,false,created.background,created.opacity,controller.force_opaque)
				if macos.native_window_is_visible(macos.view_window(controller.host.container)) { sync_native_surface_color_scheme(mut controller) }
			}
		}
		for mut current in runtime.states {
			if current.closed { continue }
			// SwiftUI SurfaceView overlays read ghostty.config, while AppKit's
			// SurfaceView derived config observes notifications with object:self.
			native_app_action_config(current,&task.config)
		}
	}
}
fn native_app_action_config(current &TermState, config &configpkg.Config) {
	if current.closed || current.actions == unsafe { nil } { return }
	mut actions := current.actions
	actions.bell_border = config.bell_features.border()
	actions.secure_indication = config.macos_secure_input_indication
	// Cache BaseTerminalController's updated policy for a later focus/pwd
	// publication, without changing the represented URL during notification.
	actions.proxy_icon = config.macos_titlebar_proxy_icon == .visible
	color := config.background
	actions.visual_background = (u32(color.r) << 16) | (u32(color.g) << 8) | u32(color.b)
	actions.refresh_config()
}
fn native_surface_action_config(current &TermState, config &configpkg.Config) {
	if current.closed || current.actions == unsafe { nil } { return }
	mut actions := current.actions
	color := config.background
	actions.configure_scroll(config.scrollbar == .never, (0.299 * f64(color.r) + 0.587 * f64(color.g) + 0.114 * f64(color.b)) / 255 > 0.5)
}
// SurfaceView.mouseMoved reads BaseTerminalController's app-derived setting.
// mouseEntered/mouseExited only publish position and never enter this branch.
fn native_focus_follows_mouse(current &TermState) {
	if current.controller == unsafe { nil } || current.actions == unsafe { nil } || current.actions.focused { return }
	controller := current.controller
	if !controller.app_config.focus_follows_mouse || !macos.native_window_is_key(macos.view_window(current.view)) { return }
	if controller.focused != unsafe { nil } && controller.focused.actions != unsafe { nil } && controller.focused.actions.command_palette_is_showing() { return }
	macos.move_focus(current.view,unsafe { nil },none)
}
struct NativeCellSizeTask {
	state &TermState
	width u32
	height u32
}

fn queue_native_cell_size(state &TermState, width u32, height u32) {
	task := NativeCellSizeTask{state: state, width: width, height: height}
	// libdispatch keeps this context outside V's garbage collector roots.
	context := unsafe { memdup_uncollectable(&task, int($sizeof(NativeCellSizeTask))) }
	macos.dispatch_main(native_cell_size_main, context)
}

fn native_cell_size_main(context voidptr) {
	defer { unsafe { free(context) } }
	task := unsafe { &NativeCellSizeTask(context) }
	mut current := task.state
	if current.closed { return }
	scale := macos.view_backing_scale(current.view)
	current.cell_width = f64(task.width) / scale
	current.cell_height = f64(task.height) / scale
	current.actions.set_scroll_cell_height(current.cell_height)
	if current.controller != unsafe { nil } && current.controller.focused == current {
		config := native_controller_config(current)
		macos.set_native_cell_size(current.view, current.cell_width, current.cell_height, config.step_resize)
		// TerminalSplitTreeView keeps point increments of 1 independently of
		// BaseTerminalController's optional window contentResizeIncrements.
	}
}
