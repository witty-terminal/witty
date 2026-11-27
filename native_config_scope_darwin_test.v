module main

import apprt
import configpkg
import witty_macos as macos
#insert "@VMODROOT/native_config_scope_darwin_test_abi.h"

fn C.witty_config_scope_controlled_key_window(view voidptr) voidptr
fn C.witty_config_scope_restore_class(view voidptr, original voidptr)
fn C.witty_config_scope_set_key(key bool)
fn C.witty_config_scope_drain_main()
fn C.witty_config_scope_finish_launching()
fn C.witty_config_scope_opaque(view voidptr) bool
fn C.witty_config_scope_background(view voidptr) u32
fn C.witty_config_scope_scroller(view voidptr) bool
fn C.witty_config_scope_clear_responder(view voidptr)
fn C.witty_config_scope_is_responder(view voidptr) bool

fn config_scope_target(state &TermState) apprt.SurfaceTarget {
	runtime := &apprt.Surface{
		userdata: voidptr(state)
	}
	core := &apprt.CoreSurface{
		runtime_surface: voidptr(runtime)
	}
	return apprt.SurfaceTarget{
		surface: voidptr(core)
	}
}

fn test_native_config_notification_scopes_preserve_surface_appearance() {
	macos.app_init()
	C.witty_config_scope_finish_launching()
	view := macos.create_restorable_window(260, 160, 'config scope probe')
	window := macos.view_window(view)
	mut runtime := standalone_runtime()
	original_app := runtime.app
	original_states := runtime.states.clone()
	original_controllers := runtime.controllers.clone()
	mut original := configpkg.Config.default()
	original.macos_secure_input_indication = false
	mut local := original.clone()
	local.background = configpkg.ColorRGB{
		r: 0x12
		g: 0x34
		b: 0x56
	}
	local.background_opacity = 0.4
	local.macos_window_shadow = false
	local.scrollbar = .never
	mut state := &TermState{
		view:          view
		native_config: native_window_config(&local)
	}
	macos.view_set_userdata(view, voidptr(state))
	state.actions = macos.new_action_surface(view, voidptr(state), macos.ActionCallbacks{})
	projection := native_window_config(&original)
	mut controller := &TerminalController{
		host:            macos.create_split_host(view)
		focused:         state
		app_config:      projection
		creation_config: projection
	}
	state.controller = controller
	native_action_config(state, &original)
	native_surface_action_config(state, &local)
	macos.focus_native_window(window)
	sync_native_window(state)
	runtime.app = &apprt.App{
		config: original.clone()
	}
	runtime.states = [state]
	runtime.controllers = [controller]
	defer {
		runtime.app.config.deinit()
		runtime.app = original_app
		runtime.states = original_states
		runtime.controllers = original_controllers
		state.actions.deinit()
		macos.close_native_window(window)
		macos.release_native_object(window)
		macos.release_native_object(controller.host.container)
		macos.release_native_object(view)
		original.deinit()
		local.deinit()
	}
	assert !C.witty_config_scope_opaque(view)
	assert !C.witty_config_scope_scroller(view)
	before := state.native_config
	frame := macos.native_window_frame(view)
	target := config_scope_target(state)
	assert runtime_action(runtime.app, target, apprt.RuntimeAction{
		action: .color_change
		data:   apprt.ColorChange{
			kind: .background
			r:    0x42
			g:    0x30
			b:    0x62
		}
	})
	C.witty_config_scope_drain_main()
	assert state.background_color == ?u32(0x423062)
	mut app_change := original.clone()
	defer { app_change.deinit() }
	app_change.background = configpkg.ColorRGB{
		r: 0xee
		g: 0xee
		b: 0xee
	}
	app_change.background_opacity = 1
	app_change.scrollbar = .system
	app_change.window_step_resize = true
	app_change.macos_titlebar_proxy_icon = .hidden
	app_change.focus_follows_mouse = true
	app_change.window_position_x = i16(71)
	app_change.window_position_y = i16(82)
	app_change.maximize = true
	app_change.macos_secure_input_indication = true
	assert runtime_action(runtime.app, apprt.AppTarget{}, apprt.RuntimeAction{
		action: .config_change
		data:   apprt.ConfigChange{
			config: &app_change
		}
	})
	C.witty_config_scope_drain_main()
	assert runtime.app.config.background == app_change.background
	assert controller.app_config.step_resize
	assert controller.app_config.maximize
	assert controller.app_config.focus_follows_mouse
	assert controller.app_config.position_x == app_change.window_position_x
	assert !native_controller_config(state).proxy_icon
	assert controller.creation_config == projection
	assert state.native_config == before
	assert state.background_color == ?u32(0x423062)
	assert !C.witty_config_scope_opaque(view)
	assert !C.witty_config_scope_scroller(view)
	assert macos.native_window_frame(view) == frame
	assert state.actions.secure_indication
	assert state.actions.visual_background == 0xeeeeee

	mut surface_change := local.clone()
	defer { surface_change.deinit() }
	surface_change.background = configpkg.ColorRGB{
		r: 0x44
		g: 0x55
		b: 0x66
	}
	surface_change.background_opacity = 1
	surface_change.scrollbar = .system
	surface_change.window_step_resize = false
	surface_change.macos_titlebar_proxy_icon = .visible
	surface_change.macos_secure_input_indication = false
	assert runtime_action(runtime.app, target, apprt.RuntimeAction{
		action: .config_change
		data:   apprt.ConfigChange{
			config: &surface_change
		}
	})
	C.witty_config_scope_drain_main()
	assert state.native_config == native_window_config(&surface_change)
	assert state.background_color == none
	assert C.witty_config_scope_background(view) == 0x445566
	assert C.witty_config_scope_opaque(view)
	assert C.witty_config_scope_scroller(view)
	assert native_controller_config(state).step_resize
	assert !native_controller_config(state).proxy_icon
	assert state.actions.secure_indication
	assert state.actions.visual_background == 0xeeeeee
	assert runtime.app.config.background == app_change.background

	// A terminal color that arrives after a reload should still reach the window.
	surface_change.title = 'Reloaded title ${surface_change.background.r}'
	assert runtime_action(runtime.app, target, apprt.RuntimeAction{
		action: .config_change
		data:   apprt.ConfigChange{
			config: &surface_change
		}
	})
	assert runtime_action(runtime.app, target, apprt.RuntimeAction{
		action: .color_change
		data:   apprt.ColorChange{
			kind: .background
			r:    0x30
			g:    0x47
			b:    0x52
		}
	})
	gc_collect()
	C.witty_config_scope_drain_main()
	assert state.native_config.title == surface_change.title
	assert state.background_color == ?u32(0x304752)
	assert C.witty_config_scope_background(view) == 0x304752
}

fn test_native_background_responder_selects_surface_without_keyboard_focus() {
	macos.app_init()
	C.witty_config_scope_finish_launching()
	view := macos.create_restorable_window(260, 160, 'background responder probe')
	window := macos.view_window(view)
	original_class := C.witty_config_scope_controlled_key_window(view)
	mut state := &TermState{
		view:    view
		surface: &apprt.Surface{}
	}
	state.actions = macos.new_action_surface(view, voidptr(state), macos.ActionCallbacks{})
	state.controller = &TerminalController{
		host: macos.create_split_host(view)
	}
	defer {
		C.witty_config_scope_restore_class(view, original_class)
		state.actions.deinit()
		macos.close_native_window(window)
		macos.release_native_object(window)
		macos.release_native_object(state.controller.host.container)
		macos.release_native_object(view)
	}
	C.witty_config_scope_set_key(false)
	on_focus(voidptr(state), true)
	assert state.controller.focused == state
	assert !state.actions.focused

	C.witty_config_scope_set_key(true)
	on_focus(voidptr(state), true)
	assert state.actions.focused
}

fn test_native_focus_follows_mouse_uses_app_setting_key_window_and_palette_guards() {
	macos.app_init()
	C.witty_config_scope_finish_launching()
	view := macos.create_restorable_window(260, 160, 'mouse focus probe')
	window := macos.view_window(view)
	original_class := C.witty_config_scope_controlled_key_window(view)
	mut state := &TermState{
		view: view
	}
	state.actions = macos.new_action_surface(view, voidptr(state), macos.ActionCallbacks{})
	state.controller = &TerminalController{
		focused:    state
		app_config: macos.NativeWindowConfig{
			focus_follows_mouse: true
		}
	}
	defer {
		C.witty_config_scope_restore_class(view, original_class)
		state.actions.deinit()
		macos.close_native_window(window)
		macos.release_native_object(window)
		macos.release_native_object(view)
	}
	C.witty_config_scope_clear_responder(view)
	state.actions.focused = false
	C.witty_config_scope_set_key(false)
	native_focus_follows_mouse(state)
	C.witty_config_scope_drain_main()
	assert !C.witty_config_scope_is_responder(view)
	C.witty_config_scope_set_key(true)
	state.controller.app_config = macos.NativeWindowConfig{
		focus_follows_mouse: false
	}
	native_focus_follows_mouse(state)
	C.witty_config_scope_drain_main()
	assert !C.witty_config_scope_is_responder(view)
	state.controller.app_config = macos.NativeWindowConfig{
		focus_follows_mouse: true
	}
	state.actions.toggle_command_palette([])
	native_focus_follows_mouse(state)
	C.witty_config_scope_drain_main()
	assert !C.witty_config_scope_is_responder(view)
	state.actions.toggle_command_palette([])
	C.witty_config_scope_drain_main()
	C.witty_config_scope_clear_responder(view)
	state.actions.focused = false
	native_focus_follows_mouse(state)
	C.witty_config_scope_drain_main()
	assert C.witty_config_scope_is_responder(view)
}
