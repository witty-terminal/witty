module main

import os
import apprt
import cli
import configpkg
import global_state
import input
import macos
import source_startup

// The macOS executable is a native host for Ghostty's translated embedded
// runtime. The host owns AppKit windows; terminal, renderer, input, selection,
// configuration, and subprocess behavior stay behind the embedded API.

@[heap]
struct TermState {
mut:
	view    voidptr
	native_config macos.NativeWindowConfig
	background_color ?u32
	cell_width f64
	cell_height f64
	actions &macos.NativeActionSurface = unsafe { nil }
	controller &TerminalController = unsafe { nil }
	surface &apprt.Surface = unsafe { nil }
	closing bool
	closed  bool
	initial_width f64
	initial_height f64
}

@[heap]
struct TerminalController {
mut:
	host &macos.NativeSplitHost = unsafe { nil }
	focused &TermState = unsafe { nil }
	// BaseTerminalController/TerminalController listen for app notifications.
	// The window's own DerivedConfig is captured when its class is created.
	app_config macos.NativeWindowConfig
	creation_config macos.NativeWindowConfig
	applied_color_scheme ?apprt.ColorScheme
	force_opaque bool
	quick bool
	closed bool
	initial_frame macos.NativeWindowFrame
	title_override ?string
	restorable bool = true
}

struct StandaloneRuntime {
mut:
	app    &apprt.App = unsafe { nil }
	screenshot ScreenshotLaunch
	screenshot_surface &TermState = unsafe { nil }
	states []&TermState
	controllers []&TerminalController
	undos []&ControllerUndo
	pending_quick ?NativeRestoredController
}

struct StandaloneRuntimeSingleton {
mut:
	runtime StandaloneRuntime
}

const standalone_runtime_instance = &StandaloneRuntimeSingleton{}

fn standalone_runtime() &StandaloneRuntime {
	return unsafe { &standalone_runtime_instance.runtime }
}

fn state_from_userdata(userdata voidptr) ?&TermState {
	if userdata == unsafe { nil } {
		return none
	}
	return unsafe { &TermState(userdata) }
}

fn state_from_target(target apprt.Target) ?&TermState {
	match target {
		apprt.AppTarget {
			return none
		}
		apprt.SurfaceTarget {
			if target.surface == unsafe { nil } {
				return none
			}
			core_surface := unsafe { &apprt.CoreSurface(target.surface) }
			if core_surface.runtime_surface == unsafe { nil } {
				return none
			}
			surface := unsafe { &apprt.Surface(core_surface.runtime_surface) }
			return state_from_userdata(surface.userdata)
		}
	}
}

fn surface_options(view voidptr, userdata voidptr, inherited apprt.SurfaceOptions) apprt.SurfaceOptions {
	return apprt.SurfaceOptions{
		...inherited
		platform_tag: int(apprt.PlatformTag.macos)
		platform:     apprt.PlatformC{
			nsview: view
		}
		userdata:     userdata
		scale_factor: macos.view_backing_scale(view)
	}
}

fn create_surface(view voidptr, inherited apprt.SurfaceOptions) ?&TermState {
	if view == unsafe { nil } {
		return none
	}
	mut runtime := standalone_runtime()
	if runtime.app == unsafe { nil } {
		return none
	}

	mut state := &TermState{
		view: view
		native_config: native_window_config(&runtime.app.config)
	}
	macos.view_set_userdata(view, voidptr(state))
	state.actions = macos.new_action_surface(view, voidptr(state), macos.ActionCallbacks{inspector: native_inspector_callbacks(), size: on_resize, binding: native_binding_action, title: native_surface_title_changed, tab_title: native_tab_title_changed, present: native_present_view})
	state.actions.bell_border = runtime.app.config.bell_features.border()
	state.actions.secure_indication = runtime.app.config.macos_secure_input_indication
    native_action_config(state,&runtime.app.config)
	opts := surface_options(view, voidptr(state), inherited)
	mut app := runtime.app
	state.surface = apprt.ghostty_surface_new(mut app, &opts) or {
		state.closed = true
		state.actions.deinit()
		macos.view_set_userdata(view, unsafe { nil })
		macos.close_tab(view)
		return none
	}
	runtime.states << state
	if macos.view_window(view) != unsafe { nil } {
		app_config := native_window_config(&runtime.app.config)
		state.controller = &TerminalController{host: macos.create_split_host(view), focused: state, app_config: app_config, creation_config: app_config, restorable: (inherited.command or { '' }) == ''}
		macos.set_native_window_title_font(view, state.native_config.window_title_font_family)
		macos.apply_native_window_config(view, state.native_config, true, state.native_config.background, state.native_config.opacity, false)
		state.controller.initial_frame = macos.native_window_frame(view)
		if runtime.app.config.maximize {
			macos.reset_native_window_size(view,true,state.controller.initial_frame,state.initial_width,state.initial_height)
			state.controller.initial_frame=macos.native_window_frame(view)
		} else if state.initial_width>0 && state.initial_height>0 {
			macos.dispatch_after(0.01,apply_initial_native_content_size,voidptr(state.controller))
		}
		runtime.controllers << state.controller
		macos.configure_native_restoration(view, state.controller.restorable)
		macos.detach_automatic_native_tab(view)
	}

	scale := macos.view_backing_scale(view)
	apprt.ghostty_surface_set_size(mut state.surface, u32(macos.view_width(view) * scale),
		u32(macos.view_height(view) * scale))
	apprt.ghostty_surface_set_focus(mut state.surface, true)
	return state
}

fn inherited_options(state ?&TermState, context apprt.NewSurfaceContext) apprt.SurfaceOptions {
	if source := state {
		if !source.closed && source.surface != unsafe { nil } {
			return apprt.ghostty_surface_inherited_config(source.surface, context)
		}
	}
	return apprt.SurfaceOptions{
		context: context
	}
}

fn do_new_window(source ?&TermState) bool {
	return new_controller_with_options(source,inherited_options(source,.window),false)
}
fn new_controller_with_options(source ?&TermState,options apprt.SurfaceOptions,tab bool) bool {
	mut parent:=voidptr(unsafe { nil })
	if current:=source { if tab { if macos.quick_terminal_deny_tab(current.view) || macos.native_tab_creation_denied(current.view) { return true }; parent=macos.view_window(current.view) } }
	is_tab:=tab && parent != unsafe { nil }
	if parent == unsafe { nil } { parent=macos.preferred_terminal_window() }
	view := macos.create_restorable_window(800, 600, '')
	state := create_surface(view, options) or { return false }
	if is_tab { macos.attach_native_new_tab(parent,state.view,standalone_runtime().app.config.window_new_tab_position == .end) }
	if !is_tab && parent != unsafe { nil } {
		config:=standalone_runtime().app.config
		if macos.native_window_is_fullscreen(parent) { macos.toggle_fullscreen_mode(state.view,.native) }
		else if config.fullscreen {
			mode:=match config.macos_non_native_fullscreen { .false_ { macos.NativeFullscreenMode.native } .true_ { .non_native } .visible_menu { .visible_menu } .padded_notch { .padded_notch } }
			if mode==.native { macos.toggle_fullscreen_mode(state.view,mode) }
			else { macos.dispatch_main(show_configured_new_fullscreen,voidptr(&NewControllerShowTask{controller:state.controller,mode:mode})) }
		}
	}
	macos.dispatch_main(show_new_controller,voidptr(&NewControllerShowTask{controller:state.controller,tab:is_tab}))
	register_new_controller_undo(state, source, is_tab, options)
	return true
}

@[heap]
struct NewControllerShowTask {
	controller &TerminalController
	tab bool
	mode macos.NativeFullscreenMode
}
fn show_configured_new_fullscreen(context voidptr) {
	task:=unsafe { &NewControllerShowTask(context) }
	if task.controller.closed { return }
	macos.toggle_fullscreen_mode(task.controller.host.container,task.mode)
}
fn show_new_controller(context voidptr) {
	task:=unsafe { &NewControllerShowTask(context) }
	if task.controller.closed { return }
	if standalone_runtime().screenshot.path == '' {
		macos.show_new_terminal_window(task.controller.host.container,task.tab)
	}
	if task.controller.focused != unsafe { nil } { sync_native_window(task.controller.focused) }
}

fn do_new_tab(source ?&TermState) bool {
	return new_controller_with_options(source,inherited_options(source,.tab),true)
}

fn close_state_now(mut state TermState) {
	if state.closed || state.controller == unsafe { nil } { return }
	state.closing = false
	mut controller := state.controller
	tree := controller.host.tree
	node := tree.root.find(state.view) or { return }
	if tree.root.leaves().len > 1 {
		mut next := voidptr(unsafe { nil })
		mut old_focus := voidptr(unsafe { nil })
		if controller.focused != unsafe { nil } { old_focus = controller.focused.view }
		if controller.focused == &state { if target := tree.focus_target(if tree.root.leaves()[0] == state.view { macos.SplitFocusDirection.next } else { macos.SplitFocusDirection.previous }, node) { next = target } }
		replace_controller_tree(controller, tree.removing(node), next, old_focus, 'Close Terminal')
	} else if mut quick := macos.quick_terminal_for_view(state.view) {
		quick.hide()
		controller.host.replace_tree(macos.NativeSplitTree{})
		collect_detached_surfaces()
	} else { close_controller_immediately(controller, false) }
}

fn close_state_main(userdata voidptr) {
	mut state := state_from_userdata(userdata) or { return }
	close_state_now(mut state)
}

fn request_close_state(mut state TermState) {
	if state.closed || state.closing {
		return
	}
	state.closing = true
	macos.dispatch_main(close_state_main, voidptr(&state))
}

fn runtime_close_surface(userdata voidptr, confirm bool) {
	mut state := state_from_userdata(userdata) or { return }
	if is_screenshot_surface(state) && !isnil(state.surface)
		&& apprt.ghostty_surface_process_exited(state.surface) {
		return
	}
	if mut q := macos.quick_terminal_for_view(state.view) {
		if state.controller.host.tree.root.leaves().len == 1 && !apprt.ghostty_surface_process_exited(state.surface) { q.hide(); return }
	}
	if confirm {
		macos.confirm_native_controller_close(state.view, 'Close Terminal?', 'The terminal still has a running process. If you close the terminal the process will be killed.', 'Close', voidptr(state), finish_close_surface)
	} else { request_close_state(mut state) }
}
fn finish_close_surface(context voidptr, confirmed bool) { if confirmed { mut state := unsafe { &TermState(context) }; request_close_state(mut state) } }

fn runtime_wakeup(userdata voidptr) {
	macos.dispatch_main(runtime_tick_main, userdata)
}

fn runtime_tick_main(userdata voidptr) {
	if userdata == unsafe { nil } {
		return
	}
	mut runtime := unsafe { &StandaloneRuntime(userdata) }
	if runtime.app != unsafe { nil } {
		apprt.ghostty_app_tick(mut runtime.app)
	}
}

fn on_app_focus(focused bool) {
	macos.secure_app_focus(focused)
	macos.notification_app_focus(focused)
	mut runtime := standalone_runtime()
	if runtime.app != unsafe { nil } {
		apprt.ghostty_app_set_focus(mut runtime.app, focused)
	}
}

fn on_keyboard_changed() {
	mut runtime := standalone_runtime()
	if runtime.app != unsafe { nil } {
		apprt.ghostty_app_keyboard_changed(mut runtime.app)
	}
}

fn on_should_quit_after_last_window() bool {
	runtime := standalone_runtime()
	if runtime.app == unsafe { nil } {
		return false
	}
	return runtime.screenshot.path == '' && runtime.app.config.quit_after_last_window_closed
}
fn on_first_active() {
	runtime:=standalone_runtime()
	if runtime.screenshot.path != '' { return }
	if runtime.app == unsafe { nil } || !runtime.app.config.initial_window || runtime.controllers.any(!it.closed && !it.quick) { return }
	macos.native_undo_disable()
	do_new_window(none)
	macos.native_undo_enable()
}

fn on_should_terminate() bool {
	runtime := standalone_runtime()
	if runtime.app == unsafe { nil } || !macos.termination_requires_confirmation(apprt.ghostty_app_needs_confirm_quit(runtime.app)) {
		return true
	}
	return macos.confirm_quit()
}

fn on_reopen() bool {
	runtime := standalone_runtime()
	if runtime.screenshot.path != '' { return true }
	controllers := runtime.controllers.filter(!it.closed && !it.quick).len
	if !macos.should_create_reopen_window(false, controllers, macos.application_has_become_active()) {
		return true
	}
	do_new_window(none)
	return false
}

fn runtime_read_clipboard(userdata voidptr, clipboard_type int, request &apprt.ClipboardRequest) {
	mut state := state_from_userdata(userdata) or { return }
	if state.closed || state.surface == unsafe { nil } {
		return
	}
	// The source sends the Swift pasteboard string through withCString before
	// the core consumes it, so only the prefix before the first NUL participates.
	text := macos.source_c_utf8_repair(macos.clipboard_get_text_for(clipboard_type) or { '' })
	apprt.ghostty_surface_complete_clipboard_request(mut state.surface, text, request, false)
}

fn runtime_confirm_read_clipboard(userdata voidptr, value string, request &apprt.ClipboardRequest, request_type apprt.ClipboardRequestType) {
	mut state := state_from_userdata(userdata) or { return }
	if state.closed || state.surface == unsafe { nil } {
		return
	}
	// confirmReadClipboard uses the strict UTF-8 C-string initializer.
	text := macos.source_c_utf8(value) or { return }
	if request_type !in [.paste, .osc_52_read, .osc_52_write] { return }
	confirmed := macos.confirm_clipboard(text, int(request_type))
	apprt.ghostty_surface_complete_clipboard_request(mut state.surface, if confirmed {
		text
	} else {
		''
	}, request, true)
}

fn runtime_write_clipboard(userdata voidptr, clipboard_type int, contents []apprt.ClipboardContent, confirm bool) {
	state := state_from_userdata(userdata) or { return }
	if state.closed || contents.len == 0 || clipboard_type !in [0, 1] {
		return
	}
	// Ghostty.ClipboardContent.from repairs the C-string prefixes before either
	// choosing the confirmation text or mapping MIME types.
	mut values := contents.map(apprt.ClipboardContent{
		mime: macos.source_c_utf8_repair(it.mime)
		data: macos.source_c_utf8_repair(it.data)
	})
	assert values.filter(it.mime == 'text/plain').len <= 1
	if confirm {
		mut text := ''
		mut found := false
		for content in values {
			if content.mime == 'text/plain' {
				text = content.data
				found = true
				break
			}
		}
		if !found || !macos.confirm_clipboard(text, int(apprt.ClipboardRequestType.osc_52_write)) {
			return
		}
		// The confirmation controller only publishes the approved plain text.
		values = [apprt.ClipboardContent{ mime: 'text/plain', data: text }]
	}
	if !macos.clipboard_declare_types(clipboard_type, values.map(it.mime)) {
		return
	}
	for content in values {
		macos.clipboard_set_value(clipboard_type, content.mime, content.data)
	}
}

fn reload_runtime_config(app &apprt.App, target ?&TermState, soft bool) bool {
	mut runtime_app := unsafe { &apprt.App(app) }
	mut config := if soft {
		runtime_app.config.clone()
	} else {
		configpkg.Config.load_args(global_state.get_state().cli_args) or {
			eprintln('error loading config: ${err}')
			return false
		}
	}
	defer {
		config.deinit()
	}
	if mut state := target {
		if state.closed || state.surface == unsafe { nil } {
			return false
		}
		apprt.ghostty_surface_update_config(mut state.surface, &config)
	} else {
		apprt.ghostty_app_update_config(mut runtime_app, &config)
		sync_config_menu(&config)
	}
	return true
}

fn runtime_action(app &apprt.App, target apprt.Target, action apprt.RuntimeAction) bool {
	state := state_from_target(target)
	if action.action == .show_child_exited {
		if surface := state {
			if is_screenshot_surface(surface) { return true }
		}
	}
	match action.action {
		.quit {
			macos.app_terminate()
			return true
		}
		.new_window {
			if target is apprt.AppTarget || state != none { do_new_window(state) }
			return true
		}
		.new_split {
			if current := state {
				data := action.data
				if data is apprt.SplitDirection { do_new_split(current, data) }
			}
			if target is apprt.AppTarget { eprintln('new split does nothing with an app target') }
			return true
		}
		.goto_split {
			if current := state {
				data := action.data
				if data is apprt.GotoSplit { return do_goto_split(current, data) }
			}
		}
		.resize_split {
			if current := state {
				data := action.data
				if data is apprt.ResizeSplit { return do_resize_split(current, data) }
			}
		}
		.equalize_splits {
			if current := state { if current.controller != unsafe { nil } && current.controller.host.tree.root.find(current.view) != none { mut host := current.controller.host; host.replace_tree(host.tree.equalized()); macos.invalidate_native_restorable_state(host.container) } }
			return true
		}
		.toggle_split_zoom {
			if current := state { return do_toggle_split_zoom(current) }
		}
		.new_tab {
			// App.swift posts an object-less notification for an app target;
			// the source AppDelegate/Quick listeners require a surface view.
			if current := state { do_new_tab(current) }
			return true
		}
		.close_tab, .close_window {
			if current := state {
				data := action.data
				if action.action == .close_window {
					do_close_controller(current, true, .this)
				} else if data is apprt.CloseTabMode {
					if int(data) in [0, 1, 2] {
						// QuickTerminalController only observes ghosttyCloseTab;
						// the other/right notifications belong to TerminalController.
						if data == .this || macos.quick_terminal_for_view(current.view) == none {
							do_close_controller(current, false, data)
						}
					}
				}
			}
			return true
		}
		.close_all_windows {
			do_close_all_controllers()
			return true
		}
		// The source native App.action switch has no render arm.
		.render { return false }
		.set_title {
			if mut current := state {
				data := action.data
				if data is apprt.SetTitle && !current.closed && current.actions != unsafe { nil } {
					if title := macos.source_c_utf8(data.title) { current.actions.set_title(title) }
				}
				return true
			}
		}
		.initial_size {
			if mut current := state {
				data := action.data
				if data is apprt.InitialSize {
					// Surface.recomputeInitialSize has already projected these
					// dimensions into points. App.setInitialSize only stores them;
					// TerminalController applies its deferred default-size branch.
					current.initial_width = f64(data.width)
					current.initial_height = f64(data.height)
				}
			}
			if target is apprt.AppTarget { eprintln('initial size does nothing with an app target') }
			return true
		}
		.toggle_quick_terminal { do_toggle_quick_terminal(app); return true }
		.toggle_fullscreen {
			if current := state {
				data := action.data
				if data is apprt.Fullscreen {
					// App.swift validates the raw mode before notifying either
					// controller; both consumers require the focused split.
					if int(data) !in [0, 1, 2, 3] { return true }
					if current.controller == unsafe { nil } || current.controller.focused != current { return true }
					if mut q := macos.quick_terminal_for_view(current.view) {
						q.toggle_fullscreen()
					} else {
						macos.toggle_fullscreen_mode(current.view, match data { .native { macos.NativeFullscreenMode.native } .macos_non_native { .non_native } .macos_non_native_visible_menu { .visible_menu } .macos_non_native_padded_notch { .padded_notch } })
					}
				}
				return true
			}
		}
		.goto_tab {
			if current := state {
				data := action.data
				if data is apprt.GotoTab {
					if macos.native_window_tabs(current.view).len <= 1 { return false }
					if current.controller == unsafe { nil } || current.controller.focused != current { return true }
					return macos.goto_native_tab(current.view, int(data))
				}
			}
		}
		.present_terminal {
			if current := state {
				native_present_view(voidptr(current), current.view)
				return true
			}
		}
		.open_config {
			owned := ghostty_config_open_path()
			defer { owned.deinit() }
			path := owned.bytes().bytestr()
			url := macos.source_config_file_url(path)
			if url.len > 0 { macos.source_open_url(url, 1) }
			return true
		}
		.open_url {
			data := action.data
			if data is apprt.OpenUrl {
				return macos.source_open_url(data.url, i32(data.kind))
			}
			return false
		}
		.reload_config {
			if target is apprt.SurfaceTarget && state == none {
				return true
			}
			data := action.data
			soft := if data is apprt.ReloadConfig { data.soft } else { false }
			reload_runtime_config(app, state, soft)
			return true
		}
		.config_change {
			data := action.data
			if data is apprt.ConfigChange { native_config_change(app, target, state, data.config) }
			return true
		}
		.cell_size {
			if current := state {
				data := action.data
				if data is apprt.CellSize {
					macos.dispatch_main(native_cell_size_main, voidptr(&NativeCellSizeTask{state: current, width: data.width, height: data.height}))
				}
			}
			return true
		}
		.size_limit, .quit_timer { return false }
		.undo, .redo {
			if target is apprt.SurfaceTarget {
				current := state or { return false }
				if macos.view_window(current.view) == unsafe { nil } { return false }
			}
			return if action.action == .undo { macos.native_undo() } else { macos.native_redo() }
		}
		else {}
	}

	return runtime_native_action(app, target, state, action)
}

fn main() {
	source_startup.prepare()
	args := if os.args.len > 1 { os.args[1..] } else { []string{} }
	screenshot, config_args := parse_screenshot_launch(args) or {
		eprintln('Witty: ${err.msg()}')
		exit(1)
	}
	mut global := global_state.get_state_mut()
	global.init_args(config_args) or {
		eprintln(startup_error_message(err))
		exit(1)
	}
	defer {
		global.deinit()
	}
	ghostty_cli_try_action()

	mut config := configpkg.Config.load_args(global.cli_args) or {
		eprintln('error loading config: ${err}')
		exit(1)
	}
	defer {
		config.deinit()
	}

	if screenshot.path != '' {
		macos.app_init_for_capture()
	} else {
		macos.app_init()
	}
    macos.set_native_application_action(native_menu_application_action)
	if screenshot.path == '' {
		macos.start_native_updater(native_update_config(&config)) or { eprintln('error starting updater: ${err}') }
	}
	defer { macos.stop_native_updater() }
	macos.set_draw_callback(on_draw)
	macos.set_resize_callback(on_resize)
	macos.set_display_callback(on_display)
	macos.set_paste_callback(on_paste)
	macos.set_action_callback(on_action)
	macos.set_mouse_callback(on_mouse)
	macos.set_scroll_callback(on_scroll)
	macos.set_pressure_callback(on_pressure)
	macos.set_focus_callback(on_focus)
	macos.set_app_focus_callback(on_app_focus)
	macos.set_keyboard_changed_callback(on_keyboard_changed)
	install_native_input_callbacks()
	macos.set_should_quit_after_last_window_callback(on_should_quit_after_last_window)
	macos.set_should_terminate_callback(on_should_terminate)
	macos.set_reopen_callback(on_reopen)
	macos.set_first_active_callback(on_first_active)

	mut runtime := standalone_runtime()
	runtime.screenshot = screenshot
	runtime.app = apprt.ghostty_app_new(&apprt.AppOptions{
		userdata:                     voidptr(runtime)
		supports_selection_clipboard: true
		wakeup_cb:                    runtime_wakeup
		action_cb:                    runtime_action
		read_clipboard_cb:            runtime_read_clipboard
		confirm_read_clipboard_cb:    runtime_confirm_read_clipboard
		write_clipboard_cb:           runtime_write_clipboard
		close_surface_cb:             runtime_close_surface
	}, &config) or {
		eprintln('application initialization failed')
		exit(1)
	}
	apprt.ghostty_app_set_focus(mut runtime.app, macos.app_is_active())
	macos.sync_native_application_appearance(native_window_config(&config))
	macos.set_application_appearance_callback(native_application_appearance_changed)
	defer { macos.stop_application_appearance_callback() }
	sync_config_menu(&config)
	macos.set_native_restoration_callbacks(encode_native_controller, decode_native_controller, native_restoration_allowed)
	if screenshot.path != '' {
		macos.dispatch_main(begin_screenshot, unsafe { nil })
	} else {
		macos.apply_native_save_state(int(config.window_save_state))
	}

	macos.app_run()
	macos.clear_native_undo()

	for mut state in runtime.states {
		if state.closed { continue }
		state.closed = true
		if state.actions != unsafe { nil } { state.actions.deinit() }
		macos.view_set_userdata(state.view, unsafe { nil })
		state.surface = unsafe { nil }
		state.closed = true
	}
	apprt.ghostty_app_free(mut runtime.app)
	runtime.app = unsafe { nil }
	runtime.states.clear()
}

fn on_draw(userdata voidptr, _ctx voidptr, _width f64, _height f64) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } {
		apprt.ghostty_surface_draw(mut state.surface)
	}
}

fn on_resize(userdata voidptr, width f64, height f64) {
	mut state := state_from_userdata(userdata) or { return }
	if state.closed || state.surface == unsafe { nil } || width <= 0 || height <= 0 {
		return
	}
	scale := macos.view_backing_scale(state.view)
	apprt.ghostty_surface_set_content_scale(mut state.surface, scale, scale)
	apprt.ghostty_surface_set_size(mut state.surface, u32(width * scale), u32(height * scale))
	if state.actions != unsafe { nil } { state.actions.resize() }
}

fn on_display(userdata voidptr, display_id u32) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } {
		apprt.ghostty_surface_set_display_id(mut state.surface, display_id)
	}
}

fn on_focus(userdata voidptr, focused bool) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } {
		apprt.ghostty_surface_set_focus(mut state.surface, focused)
		if state.actions != unsafe { nil } { state.actions.focus(focused) }
		if focused && state.controller != unsafe { nil } {
			state.controller.focused = state
			if mut quick := macos.quick_terminal_for_view(state.view) { quick.view = state.view }
			sync_native_window(state)
			if state.actions != unsafe { nil } { native_surface_title_changed(userdata, state.actions.title) }
		}
	}
}

const vt_action_copy = 1
const vt_action_select_all = 2
const vt_action_new_tab = 3
const vt_action_close_tab = 4

fn on_paste(userdata voidptr, _text &u8, _len int) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } {
		apprt.ghostty_surface_binding_action(mut state.surface, 'paste_from_clipboard')
	}
}

fn on_action(userdata voidptr, action_id int) {
	mut state := state_from_userdata(userdata) or { return }
	if state.closed || state.surface == unsafe { nil } {
		return
	}
	match action_id {
		vt_action_copy {
			apprt.ghostty_surface_binding_action(mut state.surface, 'copy_to_clipboard')
		}
		vt_action_select_all {
			apprt.ghostty_surface_binding_action(mut state.surface, 'select_all')
		}
		vt_action_new_tab {
			do_new_tab(state)
		}
		vt_action_close_tab {
			do_close_controller(state, false, .this)
		}
		5 { do_close_controller(state, true, .this) }
		10 { do_toggle_split_zoom(state) }
		else {}
	}
}

const mouse_left_down = 0
const mouse_left_up = 1
const mouse_left_dragged = 2
const mouse_right_down = 3
const mouse_right_up = 4

fn mouse_button_from_number(number i64) input.MouseButton {
	return match number {
		0 { .left }
		1 { .right }
		2 { .middle }
		3 { .eight }
		4 { .nine }
		5 { .six }
		6 { .seven }
		7 { .four }
		8 { .five }
		9 { .ten }
		10 { .eleven }
		else { .unknown }
	}
}

fn on_mouse(userdata voidptr, event_type int, x f64, y f64, modflags u64, button_number i64) bool {
	mut state := state_from_userdata(userdata) or { return false }
	if state.closed || state.surface == unsafe { nil } {
		return false
	}
	mods := int(macos.input_mods(modflags).int())
	apprt.ghostty_surface_mouse_pos(mut state.surface, x, y, mods)
	if event_type == 7 { native_focus_follows_mouse(state) }
	return match event_type {
		mouse_left_down {
			apprt.ghostty_surface_mouse_button(mut state.surface, .press, .left, mods)
		}
		mouse_left_up {
			apprt.ghostty_surface_mouse_button(mut state.surface, .release, .left, mods)
		}
		mouse_left_dragged {
			false
		}
		mouse_right_down {
			apprt.ghostty_surface_mouse_button(mut state.surface, .press, .right, mods)
		}
		mouse_right_up {
			apprt.ghostty_surface_mouse_button(mut state.surface, .release, .right, mods)
		}
		5 {
			apprt.ghostty_surface_mouse_button(mut state.surface, .press,
				mouse_button_from_number(button_number), mods)
		}
		6 {
			apprt.ghostty_surface_mouse_button(mut state.surface, .release,
				mouse_button_from_number(button_number), mods)
		}
		else {
			false
		}
	}
}

fn on_scroll(userdata voidptr, x f64, y f64, scroll_mods int) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } {
		apprt.ghostty_surface_mouse_scroll(mut state.surface, x, y, scroll_mods)
	}
}

fn on_pressure(userdata voidptr, stage u32, pressure f64) {
	mut state := state_from_userdata(userdata) or { return }
	if !state.closed && state.surface != unsafe { nil } {
		apprt.ghostty_surface_mouse_pressure(mut state.surface, stage, pressure)
	}
}
