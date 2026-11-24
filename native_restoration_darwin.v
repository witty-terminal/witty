module main

import apprt
import macos

struct NativeRestoredController {
	tree macos.NativeSplitTree
	focused_uuid ?string
	mode ?macos.NativeFullscreenMode
	tab_color int
	title_override ?string
	cache macos.QuickScreenCache
}
fn native_restoration_allowed() bool {
	runtime := standalone_runtime()
	return runtime.screenshot.path == '' && runtime.app != unsafe { nil }
		&& runtime.app.config.window_save_state != .never
}
fn save_native_surface(view voidptr) macos.NativeSavedSurface {
	state:=state_from_userdata(macos.view_get_userdata(view)) or { panic('surface missing during native restoration encoding') }
	title,user_set:=state.actions.saved_surface_title()
	return macos.NativeSavedSurface{pwd:state.actions.saved_pwd(),uuid:state.actions.uuid,title:title or { '' },is_user_set_title:user_set}
}
fn load_native_surface(saved macos.NativeSavedSurface,_quick bool) ?voidptr {
	// SurfaceView.init(from:) starts a fresh shell using the saved directory.
	// QuickTerminalRestorable.baseConfig is a controller base configuration;
	// already decoded SurfaceViews retain the source decoder configuration.
	view:=macos.create_offscreen_terminal_view(800,600)
	mut state:=create_surface(view,apprt.SurfaceOptions{working_directory:saved.pwd}) or { return none }
	if uuid:=macos.native_uuid_string(saved.uuid) { state.actions.uuid=uuid }
	state.actions.restore_surface_title(saved.title,saved.is_user_set_title)
	state.actions.restore_pwd(saved.pwd,native_controller_config(state).proxy_icon)
	return view
}
fn encode_native_controller(view voidptr,quick bool) ?voidptr {
	runtime:=standalone_runtime()
	mut controller:=unsafe { &TerminalController(nil) }
	mut cache:=macos.QuickScreenCache{}
	if quick {
		if pending:=runtime.pending_quick { return encode_restored_controller(pending,true) }
		mut q:=macos.quick_terminal_initialized() or { return none }
		state:=state_from_userdata(macos.view_get_userdata(q.view)) or { return none }
		controller=state.controller
		q.save_screen_state(true)
		cache=q.cache
	} else {
		state:=state_from_userdata(macos.view_get_userdata(view)) or { return none }
		controller=state.controller
	}
	if controller == unsafe { nil } || !controller.restorable { return none }
	mut uuid:=?string(none)
	if controller.focused != unsafe { nil } { uuid=controller.focused.actions.uuid }
	return encode_restored_controller(NativeRestoredController{tree:controller.host.tree,focused_uuid:uuid,mode:macos.native_fullscreen_mode(controller.host.container),tab_color:macos.native_tab_color(controller.host.container),title_override:controller.title_override,cache:cache},quick)
}
fn encode_restored_controller(saved NativeRestoredController,quick bool) voidptr {
	d:=macos.codable_dictionary()
	if uuid:=saved.focused_uuid { macos.codable_put(d,'focusedSurface',macos.codable_string(uuid)) }
	macos.codable_put(d,'surfaceTree',macos.encode_native_split_tree(saved.tree,save_native_surface))
	if quick { macos.codable_put(d,'screenStateEntries',macos.encode_quick_screen_cache(saved.cache)) }
	else {
		macos.codable_put(d,'tabColor',macos.codable_int(saved.tab_color))
		if title:=saved.title_override { macos.codable_put(d,'titleOverride',macos.codable_string(title)) }
		if mode:=saved.mode { macos.codable_put(d,'effectiveFullscreenMode',macos.codable_string(match mode { .native { 'native' } .non_native { 'nonNative' } .visible_menu { 'nonNativeVisibleMenu' } .padded_notch { 'nonNativePaddedNotch' } })) }
	}
	return d
}
fn decode_native_controller(value voidptr,quick bool) ?voidptr {
	if !macos.codable_is_dictionary(value) { return none }
	tree:=macos.decode_native_split_tree(macos.codable_get(value,'surfaceTree'),quick,load_native_surface) or { collect_detached_surfaces(); return none }
	mut mode:=?macos.NativeFullscreenMode(none)
	if text:=macos.codable_as_string(macos.codable_get(value,'effectiveFullscreenMode')) { mode=match text { 'native' { macos.NativeFullscreenMode.native } 'nonNative' { .non_native } 'nonNativeVisibleMenu' { .visible_menu } 'nonNativePaddedNotch' { .padded_notch } else { collect_detached_surfaces(); return none } } }
	mut color:=0
	mut cache:=macos.QuickScreenCache{}
	if quick { cache=macos.decode_quick_screen_cache(macos.codable_get(value,'screenStateEntries')) or { collect_detached_surfaces(); return none } }
	else { color=macos.codable_as_int(macos.codable_get(value,'tabColor')) or { collect_detached_surfaces(); return none }; if color<0 || color>9 { collect_detached_surfaces(); return none } }
	saved:=NativeRestoredController{tree:tree,focused_uuid:macos.codable_as_optional_string(macos.codable_get(value,'focusedSurface')),mode:mode,tab_color:color,title_override:macos.codable_as_optional_string(macos.codable_get(value,'titleOverride')),cache:cache}
	if quick { mut runtime:=standalone_runtime(); runtime.pending_quick=saved; return none }
	view:=macos.create_restorable_window(800,600,'')
	controller:=attach_restored_controller(view,saved,false)
	window:=macos.view_window(controller.host.container)
	if controller.focused != unsafe { nil } {
		macos.dispatch_main(restore_native_focus,voidptr(&RestoreNativeFocusTask{view:controller.focused.view,window:window}))
		if m:=saved.mode { if m!=.native { macos.dispatch_main(restore_native_fullscreen,voidptr(&RestoreNativeFullscreenTask{view:controller.focused.view,mode:m})) } }
	}
	return window
}
fn attach_restored_controller(view voidptr,saved NativeRestoredController,quick bool) &TerminalController {
	mut runtime:=standalone_runtime()
	app_config := native_window_config(&runtime.app.config)
	mut controller:=&TerminalController{host:macos.create_split_host(view),app_config:app_config,creation_config:app_config,quick:quick,title_override:saved.title_override}
	runtime.controllers << controller
	controller.host.replace_tree(saved.tree)
	macos.detach_automatic_native_tab(controller.host.container)
	for leaf in saved.tree.root.leaves() {
		mut state:=state_from_userdata(macos.view_get_userdata(leaf)) or { continue }
		state.controller=controller
		state.closing=false
		if controller.focused == unsafe { nil } || state.actions.uuid == (saved.focused_uuid or { '' }) { controller.focused=state }
	}
	if controller.focused != unsafe { nil } {
		state:=controller.focused
		if !quick { macos.set_native_window_title_font(state.view, state.native_config.window_title_font_family) }
		macos.apply_native_window_config(state.view,native_surface_appearance_config(state),true,state.background_color or { state.native_config.background },state.native_config.opacity,false)
		macos.configure_native_restoration(state.view,!quick)
		macos.set_native_tab_color(state.view,saved.tab_color)
		controller.initial_frame=macos.native_window_frame(state.view)
		if title:=saved.title_override { macos.set_view_title(state.view,title) }
		if mut q:=macos.quick_terminal_initialized() { if quick { q.view=state.view; q.cache=saved.cache } }
	}
	macos.release_native_object(view)
	return controller
}
@[heap]
struct RestoreNativeFocusTask { view voidptr window voidptr attempts int }
fn restore_native_focus(context voidptr) {
	task:=unsafe { &RestoreNativeFocusTask(context) }
	window:=macos.view_window(task.view)
	if window == unsafe { nil } { if task.attempts<40 { macos.dispatch_after(0.05,restore_native_focus,voidptr(&RestoreNativeFocusTask{view:task.view,window:task.window,attempts:task.attempts+1})) }; return }
	if window != task.window { return }
	macos.restore_native_window_focus(task.view)
}
@[heap]
struct RestoreNativeFullscreenTask { view voidptr mode macos.NativeFullscreenMode }
fn restore_native_fullscreen(context voidptr) { task:=unsafe { &RestoreNativeFullscreenTask(context) }; macos.toggle_fullscreen_mode(task.view,task.mode) }
