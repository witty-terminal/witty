module main

import apprt
import configpkg
import witty_macos as macos
fn test_native_config_change_preserves_unresolved_surface_scope() {
	// App.swift clones the supplied config, then its missing-surface guard
	// prevents an app-wide notification or replacement of the app config.
	config := configpkg.Config.default()
	assert runtime_action(unsafe { nil }, apprt.SurfaceTarget{}, apprt.RuntimeAction{
		action: .config_change
		data: apprt.ConfigChange{ config: &config }
	})
}

fn test_native_void_dispatch_preserves_source_missing_surface_return() {
	app := unsafe { &apprt.App(nil) }
	target := apprt.SurfaceTarget{}
	for kind in [apprt.ActionKey.reset_window_size, .float_window, .renderer_health, .mouse_shape,
		.pwd, .start_search, .close_tab, .cell_size] {
		assert runtime_native_action(app, target, none, apprt.RuntimeAction{ target: target, action: kind })
		closed := &TermState{ closed: true }
		assert runtime_native_action(app, target, closed, apprt.RuntimeAction{ target: target, action: kind })
	}
	assert runtime_native_action(app, target, none, apprt.RuntimeAction{ target: target, action: .secure_input, data: apprt.SecureInput.on })
	for kind in [apprt.ActionKey.prompt_title, .move_tab, .resize_split, .toggle_split_zoom,
		.size_limit, .quit_timer, .render] {
		assert !runtime_native_action(app, target, none, apprt.RuntimeAction{ target: target, action: kind })
	}
}

fn test_native_reset_dispatch_ignores_internal_controller_performability() {
	app := unsafe { &apprt.App(nil) }
	current := &TermState{ actions: &macos.NativeActionSurface{ closed: true } }
	assert runtime_native_action(app, apprt.SurfaceTarget{}, current, apprt.RuntimeAction{ target: apprt.SurfaceTarget{}, action: .reset_window_size })
	assert !runtime_native_action(app, apprt.SurfaceTarget{}, current, apprt.RuntimeAction{ target: apprt.SurfaceTarget{}, action: .prompt_title })
}

fn native_dispatch_target(state &TermState) apprt.SurfaceTarget {
	runtime := &apprt.Surface{ userdata: voidptr(state) }
	core := &apprt.CoreSurface{ runtime_surface: voidptr(runtime) }
	return apprt.SurfaceTarget{ surface: voidptr(core) }
}

fn test_native_dispatch_title_guard_and_source_acknowledgement() {
	state := &TermState{}
	assert runtime_action(unsafe { nil }, native_dispatch_target(state), apprt.RuntimeAction{
		action: .set_title
		data: apprt.SetTitle{ title: 'unavailable surface' }
	})
	for kind in [apprt.ActionKey.set_title, .toggle_fullscreen, .initial_size, .cell_size,
		.equalize_splits, .inspector, .render_inspector, .desktop_notification, .pwd,
		.float_window, .secure_input, .mouse_shape, .mouse_visibility, .mouse_over_link,
		.reset_window_size, .renderer_health, .toggle_command_palette, .toggle_maximize,
		.toggle_background_opacity, .key_sequence, .key_table, .progress_report,
		.config_change, .reload_config, .color_change, .ring_bell, .readonly, .scrollbar,
		.start_search, .end_search, .search_total, .search_selected] {
		assert runtime_action(unsafe { nil }, apprt.SurfaceTarget{}, apprt.RuntimeAction{ action: kind })
	}
	for kind in [apprt.ActionKey.move_tab, .goto_tab, .goto_split, .resize_split,
		.toggle_split_zoom, .prompt_title, .undo, .redo, .present_terminal,
		.toggle_tab_overview, .toggle_window_decorations, .size_limit, .quit_timer,
		.show_child_exited, .reserved_29, .show_on_screen_keyboard, .command_finished, .render] {
		assert !runtime_action(unsafe { nil }, apprt.SurfaceTarget{}, apprt.RuntimeAction{ action: kind })
	}
}

fn test_native_fullscreen_and_split_dispatch_source_predicates() {
	macos.app_init()
	first := macos.create_window(640, 480, 'dispatcher')
	mut first_actions := macos.new_action_surface(first, unsafe { nil }, macos.ActionCallbacks{})
	mut host := macos.create_split_host(first)
	second := macos.create_split_surface_view(host)
	mut second_actions := macos.new_action_surface(second, unsafe { nil }, macos.ActionCallbacks{})
	host.replace_tree(host.tree.inserting(second, first, .right) or { panic(err) })
	mut controller := &TerminalController{ host: host }
	mut current := &TermState{ view: first, actions: first_actions, controller: controller }
	other := &TermState{ view: second, actions: second_actions, controller: controller }
	controller.focused = other
	app := &apprt.App{ config: configpkg.Config.default() }
	assert runtime_action(app, native_dispatch_target(current), apprt.RuntimeAction{ action: .toggle_command_palette })
	assert !first_actions.command_palette_is_showing()
	assert second_actions.command_palette_is_showing()
	assert runtime_action(app, native_dispatch_target(current), apprt.RuntimeAction{ action: .toggle_command_palette })
	assert !second_actions.command_palette_is_showing()
	defer {
		first_actions.deinit()
		second_actions.deinit()
		macos.close_tab(first)
	}
	target := native_dispatch_target(current)
	frame := macos.native_window_frame(first)
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .toggle_fullscreen
		data: apprt.Fullscreen.macos_non_native
	})
	assert macos.native_window_frame(first) == frame
	controller.focused = current
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .toggle_fullscreen
		data: unsafe { apprt.Fullscreen(99) }
	})
	assert macos.native_window_frame(first) == frame
	before := host.tree
	assert !runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .goto_split
		data: unsafe { apprt.GotoSplit(99) }
	})
	assert !runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .resize_split
		data: apprt.ResizeSplit{ amount: 10, direction: unsafe { apprt.ResizeSplitDirection(99) } }
	})
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .new_split
		data: unsafe { apprt.SplitDirection(99) }
	})
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .close_tab
		data: unsafe { apprt.CloseTabMode(99) }
	})
	assert host.tree.root == before.root
	assert host.tree.zoomed == before.zoomed
	// BaseTerminalController owns the app-level navigation preservation policy;
	// the focused SurfaceView's local configuration does not override it.
	controller.app_config = macos.NativeWindowConfig{ preserve_split_zoom: true }
	current.native_config = macos.NativeWindowConfig{ preserve_split_zoom: false }
	first_node := host.tree.root.find(first) or { panic('missing first split') }
	second_node := host.tree.root.find(second) or { panic('missing second split') }
	host.replace_tree(macos.NativeSplitTree{ root: before.root, zoomed: first_node })
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{ action: .goto_split, data: apprt.GotoSplit.next })
	assert host.tree.zoomed == second_node
	controller.app_config = macos.NativeWindowConfig{ preserve_split_zoom: false }
	current.native_config = macos.NativeWindowConfig{ preserve_split_zoom: true }
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{ action: .goto_split, data: apprt.GotoSplit.next })
	assert host.tree.zoomed == unsafe { nil }
	// App.swift's resize/zoom checks require a split window, while their
	// notification consumers separately ignore an absent tree node.
	current.view = host.container
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .resize_split
		data: apprt.ResizeSplit{ amount: 10, direction: .left }
	})
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{ action: .toggle_split_zoom })
	assert !runtime_action(unsafe { nil }, target, apprt.RuntimeAction{ action: .goto_split, data: apprt.GotoSplit.next })
	assert host.tree.root == before.root
	assert host.tree.zoomed == before.zoomed
	current.view = unsafe { nil }
	assert !runtime_action(unsafe { nil }, target, apprt.RuntimeAction{ action: .toggle_split_zoom })
	assert runtime_action(app, target, apprt.RuntimeAction{ action: .toggle_command_palette })
	assert !first_actions.command_palette_is_showing()
	assert !second_actions.command_palette_is_showing()
	assert runtime_action(app, target, apprt.RuntimeAction{ action: .toggle_background_opacity })
	assert !controller.force_opaque
}

fn native_dispatch_quick_created(_view voidptr) bool { return true }
fn native_dispatch_quick_closed(_view voidptr) bool { return true }

fn test_native_quick_close_modes_and_fullscreen_raw_validation() {
	macos.app_init()
	mut quick := macos.quick_terminal(macos.NativeQuickConfig{}, native_dispatch_quick_created, native_dispatch_quick_closed)
	mut actions := macos.new_action_surface(quick.view, unsafe { nil }, macos.ActionCallbacks{})
	mut host := macos.create_split_host(quick.view)
	mut controller := &TerminalController{ host: host, quick: true }
	current := &TermState{ view: quick.view, actions: actions, controller: controller }
	controller.focused = current
	target := native_dispatch_target(current)
	defer {
		quick.visible = false
		actions.deinit()
		macos.close_native_window(macos.view_window(quick.view))
	}
	quick.visible = true
	for mode in [apprt.CloseTabMode.other, .right] {
		assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{ action: .close_tab, data: mode })
		assert quick.visible
	}
	frame := macos.native_window_frame(quick.view)
	assert runtime_action(unsafe { nil }, target, apprt.RuntimeAction{
		action: .toggle_fullscreen
		data: unsafe { apprt.Fullscreen(99) }
	})
	assert macos.native_window_frame(quick.view) == frame
}
