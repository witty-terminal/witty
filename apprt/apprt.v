@[has_globals]
module apprt

import configpkg
import input
import internal_os
import log

// "apprt" is the "application runtime" package. This abstracts the
// application runtime and lifecycle management such as creating windows,
// getting user input (mouse/keyboard), etc.
//
// This enables compile-time interfaces to be built to swap out the underlying
// application runtime. For example: pure macOS Cocoa, GTK+, browser, etc.
//
// The goal is to have different implementations share as much of the core
// logic as possible, and to only reach out to platform-specific implementation
// code when absolutely necessary.
//
// Types are organized across multiple files in this module:
//   action.v   - Action types, enums, and associated value structs
//   structs.v  - Basic structs: ContentScale, SurfaceSize, Clipboard, etc.
//   surface.v  - Surface message types
//   ipc.v      - Inter-process communication types
//   runtime.v  - Runtime enum
//   none.v     - "none" runtime stubs
//   browser.v  - Browser (WASM) runtime stubs
//   embedded.v - Embedded runtime (macOS / libwitty)

pub type RuntimeAppActionFn = fn (voidptr, RuntimeAction) !bool

pub type RuntimeAppWakeupFn = fn (voidptr)

// RuntimeApp is the runtime-neutral application boundary used by the
// translated core package and tests. Platform runtimes install callbacks;
// the headless implementation retains actions for its consumer.
pub struct RuntimeApp {
pub mut:
	config             configpkg.Config
	actions            []RuntimeAction
	handled            map[ActionKey]bool
	actions_handled    bool
	quit_timer_running bool
	user_data          voidptr = unsafe { nil }
	action_fn          RuntimeAppActionFn = unsafe { nil }
	wakeup_fn          RuntimeAppWakeupFn = unsafe { nil }
	keyboard_layout    input.KeyboardLayout
}

pub struct RuntimeAction {
pub:
	target Target
	action ActionKey
	data   ActionValue = ActionVoid{}
}

pub fn (mut r RuntimeApp) perform_action(target Target, action ActionKey, data ActionValue) !bool {
	if unsafe { voidptr(&r) == nil } {
		return false
	}
	event := RuntimeAction{
		target: target
		action: action
		data: data
	}
	if action == .quit_timer {
		if data is QuitTimer {
			r.quit_timer_running = data == .start
		}
	}
	if r.action_fn != unsafe { nil } {
		return r.action_fn(r.user_data, event)
	}
	r.actions << event
	return r.actions_handled || r.handled[action]
}

// wakeup notifies the runtime that the core app mailbox has work. Ghostty's
// App.Mailbox performs this after every enqueue so platform event loops never
// leave PTY or renderer messages waiting for unrelated UI activity.
pub fn (r &RuntimeApp) wakeup() {
	if r != unsafe { nil } && r.wakeup_fn != unsafe { nil } {
		r.wakeup_fn(r.user_data)
	}
}

pub type RuntimeSurfaceCloseFn = fn (voidptr, bool)

pub type RuntimeSurfaceContentScaleFn = fn (voidptr) !ContentScale

pub type RuntimeSurfaceSizeFn = fn (voidptr) !SurfaceSize

pub type RuntimeSurfaceCursorPosFn = fn (voidptr) !CursorPos

pub type RuntimeSurfaceTitleFn = fn (voidptr) ?string

pub type RuntimeSurfaceSetClipboardFn = fn (voidptr, Clipboard, []ClipboardContent, bool) !

pub type RuntimeSurfaceSupportsClipboardFn = fn (voidptr, Clipboard) bool

pub type RuntimeSurfaceClipboardRequestFn = fn (voidptr, Clipboard, ClipboardRequest) !bool

pub type RuntimeSurfaceDefaultEnvFn = fn (voidptr) !map[string]string

pub struct RuntimeClipboardRequest {
pub:
	clipboard Clipboard
	request   ClipboardRequest
}

// RuntimeSurface is the runtime-neutral surface boundary. Platform runtimes
// install callbacks; the headless implementation retains observable state.
pub struct RuntimeSurface {
pub mut:
	content_scale       ContentScale = ContentScale{ x: 1, y: 1 }
	size                SurfaceSize = SurfaceSize{ width: 800, height: 600 }
	cursor_pos          CursorPos
	title               ?string
	clipboards          map[Clipboard][]ClipboardContent
	requests            []RuntimeClipboardRequest
	closed              bool
	close_confirm       bool
	selection_clipboard bool
	default_env         map[string]string
	linux_cgroup        ?string
	// Native NSView/UIView used by the Metal renderer. GTK leaves this nil
	// because its current GL context is the rendering surface.
	renderer_view         voidptr = unsafe { nil }
	user_data             voidptr = unsafe { nil }
	close_fn              RuntimeSurfaceCloseFn = unsafe { nil }
	content_scale_fn      RuntimeSurfaceContentScaleFn = unsafe { nil }
	size_fn               RuntimeSurfaceSizeFn = unsafe { nil }
	cursor_pos_fn         RuntimeSurfaceCursorPosFn = unsafe { nil }
	title_fn              RuntimeSurfaceTitleFn = unsafe { nil }
	set_clipboard_fn      RuntimeSurfaceSetClipboardFn = unsafe { nil }
	supports_clipboard_fn RuntimeSurfaceSupportsClipboardFn = unsafe { nil }
	clipboard_request_fn  RuntimeSurfaceClipboardRequestFn = unsafe { nil }
	default_env_fn        RuntimeSurfaceDefaultEnvFn = unsafe { nil }
}

pub fn (mut r RuntimeSurface) close(confirm bool) {
	if unsafe { voidptr(&r) == nil } {
		return
	}
	if r.close_fn != unsafe { nil } {
		r.close_fn(r.user_data, confirm)
		return
	}
	r.closed = true
	r.close_confirm = confirm
}

pub fn (r RuntimeSurface) get_content_scale() !ContentScale {
	if unsafe { voidptr(&r) == nil } {
		return ContentScale{ x: 1, y: 1 }
	}
	if r.content_scale_fn != unsafe { nil } {
		return r.content_scale_fn(r.user_data)
	}
	return r.content_scale
}

pub fn (r RuntimeSurface) get_size() !SurfaceSize {
	if unsafe { voidptr(&r) == nil } {
		return SurfaceSize{ width: 800, height: 600 }
	}
	if r.size_fn != unsafe { nil } {
		return r.size_fn(r.user_data)
	}
	return r.size
}

pub fn (r RuntimeSurface) get_cursor_pos() !CursorPos {
	if unsafe { voidptr(&r) == nil } {
		return CursorPos{}
	}
	if r.cursor_pos_fn != unsafe { nil } {
		return r.cursor_pos_fn(r.user_data)
	}
	return r.cursor_pos
}

pub fn (r RuntimeSurface) get_title() ?string {
	if unsafe { voidptr(&r) == nil } {
		return none
	}
	if r.title_fn != unsafe { nil } {
		return r.title_fn(r.user_data)
	}
	return r.title
}

pub fn (mut r RuntimeSurface) set_clipboard(loc Clipboard, contents []ClipboardContent, confirm bool) ! {
	if unsafe { voidptr(&r) == nil } {
		return
	}
	if r.set_clipboard_fn != unsafe { nil } {
		r.set_clipboard_fn(r.user_data, loc, contents, confirm)!
		return
	}
	if confirm {
		return error('clipboard confirmation required')
	}
	r.clipboards[loc] = contents.clone()
}

pub fn (r RuntimeSurface) supports_clipboard(loc Clipboard) bool {
	if unsafe { voidptr(&r) == nil } {
		return false
	}
	if r.supports_clipboard_fn != unsafe { nil } {
		return r.supports_clipboard_fn(r.user_data, loc)
	}
	return loc == .standard || r.selection_clipboard
}

pub fn (mut r RuntimeSurface) clipboard_request(loc Clipboard, req ClipboardRequest) !bool {
	if unsafe { voidptr(&r) == nil } {
		return false
	}
	if r.clipboard_request_fn != unsafe { nil } {
		return r.clipboard_request_fn(r.user_data, loc, req)!
	}
	r.requests << RuntimeClipboardRequest{
		clipboard: loc
		request: req
	}
	return true
}

pub fn (r RuntimeSurface) default_termio_env() !map[string]string {
	if unsafe { voidptr(&r) == nil } {
		return internal_os.get_env_map()
	}
	if r.default_env_fn != unsafe { nil } {
		return r.default_env_fn(r.user_data)!
	}
	if r.default_env.len > 0 {
		return r.default_env.clone()
	}
	return internal_os.get_env_map()
}

// CoreApp represents the core application logic. The concrete core.App is
// reached through the bridge installed by the root artifact.
pub struct CoreApp {
pub mut:
	// Opaque implementation supplied by the translated core module. This keeps
	// the runtime interface independent and avoids an apprt -> core import cycle.
	backend voidptr

	// Surfaces tracked by the app.
	surfaces []voidptr

	// Whether the containing application is focused. App-level key events are
	// limited to global bindings while this is false.
	focused bool = true

	// Conditional configuration state used to suppress redundant system-theme
	// reloads.
	config_conditional_state configpkg.ConditionalState
}

pub fn CoreApp.create() !&CoreApp {
	mut result := &CoreApp{}
	if g_core_bridge.app_create != unsafe { nil } {
		result.backend = g_core_bridge.app_create()!
	}
	return result
}

pub fn (mut c CoreApp) destroy() {
	if !isnil(c.backend) && g_core_bridge.app_destroy != unsafe { nil } {
		g_core_bridge.app_destroy(c.backend)
		c.backend = unsafe { nil }
	}
	// The embedded runtime owns and destroys surfaces individually. The core app
	// only retains non-owning pointers to them.
	c.surfaces.clear()
}

pub fn (mut c CoreApp) tick(app &App) ! {
	if !isnil(c.backend) && g_core_bridge.app_tick != unsafe { nil } {
		g_core_bridge.app_tick(c.backend, app)!
		return
	}
	// Embedded runtime actions are delivered synchronously through perform_action.
	// There is no platform event queue to drain here; the host calls this entrypoint
	// after its wakeup callback so queued surface work can be added without changing
	// the ABI.
	_ = app
}

pub fn (mut c CoreApp) focus_event(focused bool) {
	// Prevent redundant focus events.
	if c.focused == focused {
		return
	}
	c.focused = focused
	if !isnil(c.backend) && g_core_bridge.app_focus != unsafe { nil } {
		g_core_bridge.app_focus(c.backend, focused)
	}
}

pub fn (mut c CoreApp) key_event(app &App, event voidptr) bool {
	if isnil(event) {
		return false
	}
	input_event := unsafe { *&input.KeyEvent(event) }
	if !isnil(c.backend) && g_core_bridge.app_key != unsafe { nil } {
		return g_core_bridge.app_key(c.backend, app, &input_event)
	}
	if input_event.action == .release {
		return false
	}

	entry := app.config.keybind.set.get_event(input_event) or { return false }
	actions, flags := core_app_binding_leaf(entry) or { return false }
	if actions.len == 0 {
		return false
	}

	// When the application isn't focused, only global bindings are eligible.
	if !c.focused && !flags.global() {
		return false
	}

	mut runtime_app := unsafe { &App(app) }
	if flags.global() {
		for action in actions {
			c.perform_all_action(mut runtime_app, action) or {
				log.warn('error performing chained action action=${action.tag()} err=${err}')
			}
		}
		return true
	}

	// Surface-scoped bindings are handled by Surface.key_event. An app key event
	// is consumed only when every action in a chain is app-scoped.
	for action in actions {
		if action.scope() != .app {
			return false
		}
	}
	for action in actions {
		c.perform_app_action(mut runtime_app, action) or {
			log.warn('error performing app keybind action action=${action.tag()} err=${err}')
		}
	}
	return true
}

pub fn (c CoreApp) key_event_is_binding(app &App, event voidptr) bool {
	if isnil(event) {
		return false
	}
	input_event := unsafe { *&input.KeyEvent(event) }
	if !isnil(c.backend) && g_core_bridge.app_key_is_binding != unsafe { nil } {
		return g_core_bridge.app_key_is_binding(c.backend, app, &input_event)
	}
	if input_event.action == .release {
		return false
	}
	return app.config.keybind.set.get_event(input_event) != none
}

pub fn (mut c CoreApp) add_surface(surface voidptr) ! {
	c.surfaces << surface
	if !isnil(c.backend) && g_core_bridge.app_add_surface != unsafe { nil } {
		g_core_bridge.app_add_surface(c.backend, surface)!
	}
}

pub fn (mut c CoreApp) delete_surface(surface voidptr) {
	if !isnil(c.backend) && g_core_bridge.app_delete_surface != unsafe { nil } {
		g_core_bridge.app_delete_surface(c.backend, surface)
	}
	for i, candidate in c.surfaces {
		if candidate == surface {
			c.surfaces[i] = c.surfaces.last()
			c.surfaces.delete_last()
			break
		}
	}
}

pub fn (c CoreApp) needs_confirm_quit() bool {
	if !isnil(c.backend) && g_core_bridge.app_needs_confirm != unsafe { nil } {
		return g_core_bridge.app_needs_confirm(c.backend)
	}
	for surface_ptr in c.surfaces {
		if isnil(surface_ptr) {
			continue
		}
		surface := unsafe { &Surface(surface_ptr) }
		if surface.core_surface.needs_confirm_quit() {
			return true
		}
	}
	return false
}

pub fn (mut c CoreApp) color_scheme_event(app &App, scheme ColorScheme) ! {
	if !isnil(c.backend) && g_core_bridge.app_color_scheme != unsafe { nil } {
		g_core_bridge.app_color_scheme(c.backend, app, scheme)!
		return
	}
	new_theme := match scheme {
		.light { configpkg.Theme.light }
		.dark { configpkg.Theme.dark }
	}
	if c.config_conditional_state.theme == new_theme {
		return
	}
	c.config_conditional_state.theme = new_theme
	mut runtime_app := unsafe { &App(app) }
	runtime_app.perform_action(Target(AppTarget{}), .reload_config, ActionValue(ReloadConfig{ soft: true }))!
}

pub fn (mut c CoreApp) update_config(app &App, config voidptr) ! {
	if isnil(config) {
		return error('configuration pointer is null')
	}
	cfg := unsafe { &configpkg.Config(config) }
	if !isnil(c.backend) && g_core_bridge.app_update_config != unsafe { nil } {
		g_core_bridge.app_update_config(c.backend, app, cfg)!
		return
	}
	for surface_ptr in c.surfaces {
		if isnil(surface_ptr) {
			continue
		}
		mut surface := unsafe { &Surface(surface_ptr) }
		surface.core_surface.update_config(cfg)!
	}
	// The app-level runtime receives the configuration with the app's own
	// conditional state applied. Surface updates above intentionally receive
	// the original so each surface can resolve its own state.
	mut applied := cfg.clone()
	conditional_result := cfg.change_conditional_state(c.config_conditional_state) or {
		log.warn('failed to apply conditional state to config err=${err}')
		configpkg.ConfigChangeResult{}
	}
	if conditional := conditional_result.value {
		applied = conditional
	}
	defer {
		applied.deinit()
	}
	mut runtime_app := unsafe { &App(app) }
	runtime_app.perform_action(Target(AppTarget{}), .config_change, ActionValue(ConfigChange{
			config: &applied
		}))!
}

// focused_surface_pwd returns the working directory reported by the last
// focused surface. The concrete core app owns focus validation; keeping this
// behind the bridge avoids an apprt -> core import cycle.
pub fn (c &CoreApp) focused_surface_pwd() ?string {
	if !isnil(c.backend) && g_core_bridge.app_focused_pwd != unsafe { nil } {
		return g_core_bridge.app_focused_pwd(c.backend)
	}
	return none
}

// core_app_binding_leaf resolves a top-level app binding. App-level key
// sequences are intentionally unsupported, matching Ghostty's CoreApp lookup.
fn core_app_binding_leaf(entry &input.SetEntry) ?([]input.Action, input.Flags) {
	leaf := entry.value.generic() or { return none }
	return leaf.actions_slice(), leaf.flags
}

// perform_app_action translates the app-scoped input action into the embedded
// runtime action boundary. This is the same switch as CoreApp.performAction.
fn (mut c CoreApp) perform_app_action(mut app App, action input.Action) ! {
	target := Target(AppTarget{})
	match action {
		input.ActionUnbind { panic('unbind action reached app dispatch') }
		input.ActionIgnore {}
		input.ActionQuit { app.perform_action(target, .quit, ActionVoid{})! }
		input.ActionNewWindow { app.perform_action(target, .new_window, ActionVoid{})! }
		input.ActionOpenConfig { app.perform_action(target, .open_config, ActionVoid{})! }
		input.ActionReloadConfig {
			app.perform_action(target, .reload_config,
				ActionValue(ReloadConfig{ soft: false }))!
		}
		input.ActionCloseAllWindows { app.perform_action(target, .close_all_windows, ActionVoid{})! }
		input.ActionToggleQuickTerminal {
			app.perform_action(target, .toggle_quick_terminal, ActionVoid{})!
		}
		input.ActionToggleVisibility { app.perform_action(target, .toggle_visibility, ActionVoid{})! }
		input.ActionCheckForUpdates { app.perform_action(target, .check_for_updates, ActionVoid{})! }
		input.ActionShowGtkInspector { app.perform_action(target, .show_gtk_inspector, ActionVoid{})! }
		input.ActionUndo { app.perform_action(target, .undo, ActionVoid{})! }
		input.ActionRedo { app.perform_action(target, .redo, ActionVoid{})! }
		else {}
	}
}

// perform_all_action applies app-scoped actions once and surface-scoped
// actions to every live surface, matching CoreApp.performAllAction.
fn (mut c CoreApp) perform_all_action(mut app App, action input.Action) ! {
	if action.scope() == .app {
		c.perform_app_action(mut app, action)!
		return
	}
	for surface_ptr in c.surfaces {
		if isnil(surface_ptr) {
			continue
		}
		mut surface := unsafe { &Surface(surface_ptr) }
		surface.core_surface.perform_binding_action(action) or {
			log.warn('error performing binding action on surface ptr=${uint(surface_ptr):X} err=${err}')
		}
	}
}

// CoreSurface represents the core terminal surface logic. The concrete
// core.Surface is reached through the bridge installed by the root artifact.
pub struct CoreSurface {
pub mut:
	// Opaque implementation supplied by the translated core module.
	backend voidptr
	// Owning runtime surface. apprt.Target stores a core-surface pointer, while
	// embedded pre-actions sometimes need to recover the runtime surface just as
	// Ghostty follows CoreSurface.rt_surface.
	runtime_surface voidptr

	// Whether the child process has exited.
	child_exited bool
	// The current font size.
	font_size FontSize
	// Configuration.
	config SurfaceConfig
	// The surface size.
	size SurfaceSizeInfo
	// Inspector, if active.
	inspector ?&voidptr
}

pub fn (mut s CoreSurface) init(config voidptr, core_app &CoreApp, app &App, surface voidptr) ! {
	s.runtime_surface = surface
	// Retain the surface-specific configuration used by the embedded ABI.
	if !isnil(config) {
		cfg := unsafe { &configpkg.Config(config) }
		s.config.macos_option_as_alt = cfg.macos_option_as_alt
		s.config.selection_word_chars = cfg.selection_word_chars.codepoints.map(rune(it).str()).join('')
		if !isnil(core_app.backend) && g_core_bridge.surface_init != unsafe { nil } {
			s.backend = g_core_bridge.surface_init(cfg, core_app, app, surface)!
			s.sync_backend()
		}
	}
}

pub fn (mut s CoreSurface) deinit() {
	if !isnil(s.backend) && g_core_bridge.surface_deinit != unsafe { nil } {
		g_core_bridge.surface_deinit(s.backend)
		s.backend = unsafe { nil }
	}
	s.runtime_surface = unsafe { nil }
}

pub fn (mut s CoreSurface) key_callback(event voidptr) !InputEffect {
	if !isnil(s.backend) && !isnil(event) && g_core_bridge.surface_key != unsafe { nil } {
		mut effect := InputEffect.ignored
		g_core_bridge.surface_key(s.backend, unsafe { &input.KeyEvent(event) }, &effect)!
		s.sync_backend()
		return effect
	}
	return .ignored
}

pub fn (mut s CoreSurface) refresh_callback() ! {
	if !isnil(s.backend) && g_core_bridge.surface_refresh != unsafe { nil } {
		g_core_bridge.surface_refresh(s.backend)!
	}
}

pub fn (mut s CoreSurface) draw() ! {
	if !isnil(s.backend) && g_core_bridge.surface_draw != unsafe { nil } {
		g_core_bridge.surface_draw(s.backend)!
	}
}

pub fn (mut s CoreSurface) content_scale_callback(scale ContentScale) ! {
	if !isnil(s.backend) && g_core_bridge.surface_content_scale != unsafe { nil } {
		g_core_bridge.surface_content_scale(s.backend, scale)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) size_callback(size SurfaceSize) ! {
	if !isnil(s.backend) && g_core_bridge.surface_size != unsafe { nil } {
		g_core_bridge.surface_size(s.backend, size)!
		s.sync_backend()
		return
	}
	s.size.screen = ScreenSizeInfo{ width: size.width, height: size.height }
}

pub fn (mut s CoreSurface) color_scheme_callback(scheme ColorScheme) ! {
	if !isnil(s.backend) && g_core_bridge.surface_color_scheme != unsafe { nil } {
		g_core_bridge.surface_color_scheme(s.backend, scheme)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) mouse_button_callback(action_ input.MouseButtonState, button input.MouseButton, mods input.Mods) !bool {
	if !isnil(s.backend) && g_core_bridge.surface_mouse_button != unsafe { nil } {
		result := g_core_bridge.surface_mouse_button(s.backend, action_, button, mods)!
		s.sync_backend()
		return result
	}
	return false
}

pub fn (mut s CoreSurface) mouse_pressure_callback(stage input.PressureStage, pressure f64) ! {
	if !isnil(s.backend) && g_core_bridge.surface_mouse_pressure != unsafe { nil } {
		g_core_bridge.surface_mouse_pressure(s.backend, stage, pressure)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) scroll_callback(xoff f64, yoff f64, mods input.ScrollMods) ! {
	if !isnil(s.backend) && g_core_bridge.surface_scroll != unsafe { nil } {
		g_core_bridge.surface_scroll(s.backend, xoff, yoff, mods)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) cursor_pos_callback(pos CursorPos, mods input.Mods) ! {
	if !isnil(s.backend) && g_core_bridge.surface_cursor_pos != unsafe { nil } {
		g_core_bridge.surface_cursor_pos(s.backend, pos, mods)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) preedit_callback(preedit ?string) ! {
	if !isnil(s.backend) && g_core_bridge.surface_preedit != unsafe { nil } {
		g_core_bridge.surface_preedit(s.backend, preedit)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) text_callback(text string) ! {
	if !isnil(s.backend) && g_core_bridge.surface_text != unsafe { nil } {
		g_core_bridge.surface_text(s.backend, text)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) focus_callback(focused bool) ! {
	if !isnil(s.backend) && g_core_bridge.surface_focus != unsafe { nil } {
		g_core_bridge.surface_focus(s.backend, focused)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) occlusion_callback(visible bool) ! {
	if !isnil(s.backend) && g_core_bridge.surface_occlusion != unsafe { nil } {
		g_core_bridge.surface_occlusion(s.backend, visible)!
		s.sync_backend()
	}
}

pub fn (s CoreSurface) close() {
	if !isnil(s.backend) && g_core_bridge.surface_close != unsafe { nil } {
		g_core_bridge.surface_close(s.backend)
	}
}

pub fn (s CoreSurface) has_selection() bool {
	if !isnil(s.backend) && g_core_bridge.surface_has_selection != unsafe { nil } {
		return g_core_bridge.surface_has_selection(s.backend)
	}
	return false
}

// dump_text_locked reads the text covered by `sel` from the active screen.
// The renderer state mutex is assumed to be held by the caller. The returned
// DumpedText carries the text bytes along with viewport metadata (if any).
//
pub fn (s CoreSurface) dump_text_locked(sel voidptr) !DumpedText {
	if !isnil(s.backend) && g_core_bridge.surface_dump_text != unsafe { nil } {
		return g_core_bridge.surface_dump_text(s.backend, sel)!
	}
	return DumpedText{}
}

// DumpedText is the result of dump_text/dump_text_locked.
pub struct DumpedText {
pub mut:
	text     string
	viewport ?DumpedTextViewport
}

// DumpedTextViewport is the viewport-relative pixel/offset info for a
// dumped text region. Mirrors Ghostty's `Surface.Text.Viewport`.
pub struct DumpedTextViewport {
pub mut:
	tl_px_x      f64
	tl_px_y      f64
	offset_start u32
	offset_len   u32
}

// active_selection returns the active selection on the surface, if any.
pub fn (s CoreSurface) active_selection() ?voidptr {
	if !isnil(s.backend) && g_core_bridge.surface_active_sel != unsafe { nil } {
		return g_core_bridge.surface_active_sel(s.backend)
	}
	return none
}

// resolve_selection converts a CAPI-style selection into a core selection
// pointer that can be passed back to `dump_text_locked`. Returns none if
// the coordinates do not refer to a valid screen region.
pub fn (s CoreSurface) resolve_selection(tl_tag int, tl_coord_tag int, tl_x u32, tl_y u32, br_tag int, br_coord_tag int, br_x u32, br_y u32, rectangle bool) ?voidptr {
	if !isnil(s.backend) && g_core_bridge.surface_resolve_sel != unsafe { nil } {
		return g_core_bridge.surface_resolve_sel(s.backend, tl_tag, tl_coord_tag, tl_x, tl_y, br_tag, br_coord_tag, br_x, br_y, rectangle)
	}
	_ = tl_tag
	_ = tl_coord_tag
	_ = tl_x
	_ = tl_y
	_ = br_tag
	_ = br_coord_tag
	_ = br_x
	_ = br_y
	_ = rectangle
	return none
}

// renderer_state_lock acquires the renderer-state mutex protecting direct
// terminal/screen access.
pub fn (mut s CoreSurface) renderer_state_lock() {
	if !isnil(s.backend) && g_core_bridge.surface_lock != unsafe { nil } {
		g_core_bridge.surface_lock(s.backend)
	}
}

// renderer_state_unlock releases the renderer-state mutex.
pub fn (mut s CoreSurface) renderer_state_unlock() {
	if !isnil(s.backend) && g_core_bridge.surface_unlock != unsafe { nil } {
		g_core_bridge.surface_unlock(s.backend)
	}
}

pub fn (s CoreSurface) mouse_captured() bool {
	if !isnil(s.backend) && g_core_bridge.surface_mouse_captured != unsafe { nil } {
		return g_core_bridge.surface_mouse_captured(s.backend)
	}
	return false
}

pub fn (mut s CoreSurface) perform_binding_action(action input.Action) !bool {
	if !isnil(s.backend) && g_core_bridge.surface_binding != unsafe { nil } {
		result := g_core_bridge.surface_binding(s.backend, action)!
		s.sync_backend()
		return result
	}
	return false
}

pub fn (mut s CoreSurface) update_config(config voidptr) ! {
	if isnil(config) {
		return error('configuration pointer is null')
	}
	cfg := unsafe { &configpkg.Config(config) }
	if !isnil(s.backend) && g_core_bridge.surface_update_config != unsafe { nil } {
		g_core_bridge.surface_update_config(s.backend, cfg)!
		s.sync_backend()
		return
	}
	s.config.macos_option_as_alt = cfg.macos_option_as_alt
	s.config.selection_word_chars = cfg.selection_word_chars.codepoints.map(rune(it).str()).join('')
}

pub fn (s CoreSurface) needs_confirm_quit() bool {
	if !isnil(s.backend) && g_core_bridge.surface_needs_confirm != unsafe { nil } {
		return g_core_bridge.surface_needs_confirm(s.backend)
	}
	return false
}

pub fn (s CoreSurface) ime_point() IMEPos {
	if !isnil(s.backend) && g_core_bridge.surface_ime != unsafe { nil } {
		return g_core_bridge.surface_ime(s.backend)
	}
	return IMEPos{}
}

pub fn (s CoreSurface) pwd() !string {
	if !isnil(s.backend) && g_core_bridge.surface_pwd != unsafe { nil } {
		return g_core_bridge.surface_pwd(s.backend)!
	}
	return ''
}

pub fn (mut s CoreSurface) complete_clipboard_request(state ClipboardRequest, str string, confirmed bool) ! {
	if !isnil(s.backend) && g_core_bridge.surface_clipboard != unsafe { nil } {
		g_core_bridge.surface_clipboard(s.backend, state, str, confirmed)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) set_font_size(size FontSize) ! {
	if !isnil(s.backend) && g_core_bridge.surface_font_size != unsafe { nil } {
		g_core_bridge.surface_font_size(s.backend, size)!
		s.sync_backend()
		return
	}
	s.font_size = size
}

pub fn (mut s CoreSurface) activate_inspector() ! {
	if !isnil(s.backend) && g_core_bridge.surface_inspector_on != unsafe { nil } {
		g_core_bridge.surface_inspector_on(s.backend)!
		s.sync_backend()
	}
}

pub fn (mut s CoreSurface) deactivate_inspector() {
	if !isnil(s.backend) && g_core_bridge.surface_inspector_off != unsafe { nil } {
		g_core_bridge.surface_inspector_off(s.backend)
		s.sync_backend()
	}
}

// render_inspector draws the core-owned inspector state into the Dear ImGui
// context identified by context_handle.
pub fn (mut s CoreSurface) render_inspector(context_handle voidptr) {
	if !isnil(s.backend) && !isnil(context_handle)
		&& g_core_bridge.surface_inspector_render != unsafe { nil } {
		g_core_bridge.surface_inspector_render(s.backend, context_handle)
	}
}

pub fn (s CoreSurface) key_event_is_binding(event voidptr) ?voidptr {
	if !isnil(s.backend) && !isnil(event) && g_core_bridge.surface_key_binding != unsafe { nil } {
		return g_core_bridge.surface_key_binding(s.backend, unsafe { &input.KeyEvent(event) })
	}
	return none
}

// set_display_id moves macOS rendering to the display hosting the surface.
pub fn (mut s CoreSurface) set_display_id(display_id u32) {
	if !isnil(s.backend) && g_core_bridge.surface_display_id != unsafe { nil } {
		g_core_bridge.surface_display_id(s.backend, display_id)
	}
}

// quicklook_font returns a retained native font at the host coordinate scale.
pub fn (s CoreSurface) quicklook_font() voidptr {
	if !isnil(s.backend) && g_core_bridge.surface_quicklook_font != unsafe { nil } {
		return g_core_bridge.surface_quicklook_font(s.backend)
	}
	return unsafe { nil }
}

// quicklook_selection resolves the word under the supplied surface position
// without modifying the terminal's active selection.
pub fn (s CoreSurface) quicklook_selection(x f64, y f64) ?voidptr {
	if !isnil(s.backend) && g_core_bridge.surface_quicklook_sel != unsafe { nil } {
		return g_core_bridge.surface_quicklook_sel(s.backend, x, y)
	}
	return none
}

fn (mut s CoreSurface) sync_backend() {
	if isnil(s.backend) || g_core_bridge.surface_snapshot == unsafe { nil } {
		return
	}
	snapshot := g_core_bridge.surface_snapshot(s.backend)
	s.child_exited = snapshot.child_exited
	s.font_size = snapshot.font_size
	s.size = snapshot.size
	s.config = snapshot.config
	s.inspector = snapshot.inspector
}

// InputEffect represents the effect of processing an input event.
pub enum InputEffect as u8 {
	// Input was not handled.
	ignored
	// Input was handled and consumed.
	consumed
	// Input resulted in a close event.
	closed
}

// FontSize holds the font size configuration.
pub struct FontSize {
pub mut:
	points f32
}

// SurfaceConfig holds surface-specific derived configuration.
pub struct SurfaceConfig {
pub mut:
	// macos-option-as-alt setting for this surface.
	macos_option_as_alt ?input.OptionAsAlt
	// Selection word boundary characters.
	selection_word_chars string
}

// SurfaceSizeInfo holds the surface's screen and cell size info.
pub struct SurfaceSizeInfo {
pub mut:
	screen ScreenSizeInfo
	cell   CellSizeInfo
}

pub struct ScreenSizeInfo {
pub mut:
	width  u32
	height u32
}

pub struct CellSizeInfo {
pub mut:
	width  u32
	height u32
}

// GridSizeInfo holds the grid (columns/rows) dimensions.
pub struct GridSizeInfo {
pub:
	columns u16
	rows    u16
}

// grid returns the grid dimensions from the surface size.
pub fn (s SurfaceSizeInfo) grid() GridSizeInfo {
	assert s.cell.width > 0
	assert s.cell.height > 0
	calc_columns := f32(s.screen.width) / f32(s.cell.width)
	calc_rows := f32(s.screen.height) / f32(s.cell.height)
	assert calc_columns <= f32(65535)
	assert calc_rows <= f32(65535)
	columns := u16(calc_columns)
	rows := u16(calc_rows)
	return GridSizeInfo{
		columns: if columns > 1 { columns } else { 1 }
		rows: if rows > 1 { rows } else { 1 }
	}
}

// CoreSurfaceSnapshot is the small set of core state exposed directly by the
// libwitty ABI. The opaque bridge refreshes this after mutating operations.
pub struct CoreSurfaceSnapshot {
pub:
	child_exited bool
	font_size    FontSize
	size         SurfaceSizeInfo
	config       SurfaceConfig
	inspector    ?&voidptr
}

pub type CoreAppCreateFn = fn () !voidptr

pub type CoreAppDestroyFn = fn (voidptr)

pub type CoreAppTickFn = fn (voidptr, &App) !

pub type CoreAppFocusFn = fn (voidptr, bool)

pub type CoreAppKeyFn = fn (voidptr, &App, &input.KeyEvent) bool

pub type CoreAppAddSurfaceFn = fn (voidptr, voidptr) !

pub type CoreAppDeleteSurfaceFn = fn (voidptr, voidptr)

pub type CoreAppNeedsConfirmFn = fn (voidptr) bool

pub type CoreAppColorSchemeFn = fn (voidptr, &App, ColorScheme) !

pub type CoreAppUpdateConfigFn = fn (voidptr, &App, &configpkg.Config) !

pub type CoreAppFocusedPwdFn = fn (voidptr) ?string

pub type CoreSurfaceInitFn = fn (&configpkg.Config, &CoreApp, &App, voidptr) !voidptr

pub type CoreSurfaceDeinitFn = fn (voidptr)

pub type CoreSurfaceSnapshotFn = fn (voidptr) CoreSurfaceSnapshot

pub type CoreSurfaceKeyFn = fn (voidptr, &input.KeyEvent, &InputEffect) !

pub type CoreSurfaceVoidFn = fn (voidptr) !

pub type CoreSurfaceContentScaleFn = fn (voidptr, ContentScale) !

pub type CoreSurfaceSizeFn = fn (voidptr, SurfaceSize) !

pub type CoreSurfaceColorSchemeFn = fn (voidptr, ColorScheme) !

pub type CoreSurfaceMouseButtonFn = fn (voidptr, input.MouseButtonState, input.MouseButton, input.Mods) !bool

pub type CoreSurfaceMousePressureFn = fn (voidptr, input.PressureStage, f64) !

pub type CoreSurfaceScrollFn = fn (voidptr, f64, f64, input.ScrollMods) !

pub type CoreSurfaceCursorPosFn = fn (voidptr, CursorPos, input.Mods) !

pub type CoreSurfacePreeditFn = fn (voidptr, ?string) !

pub type CoreSurfaceTextFn = fn (voidptr, string) !

pub type CoreSurfaceBoolFn = fn (voidptr, bool) !

pub type CoreSurfaceCloseFn = fn (voidptr)

pub type CoreSurfaceBoolQueryFn = fn (voidptr) bool

pub type CoreSurfaceDumpTextFn = fn (voidptr, voidptr) !DumpedText

pub type CoreSurfaceSelectionFn = fn (voidptr) ?voidptr

pub type CoreSurfaceResolveSelectionFn = fn (voidptr, int, int, u32, u32, int, int, u32, u32, bool) ?voidptr

pub type CoreSurfaceLockFn = fn (voidptr)

pub type CoreSurfaceBindingFn = fn (voidptr, input.Action) !bool

pub type CoreSurfaceUpdateConfigFn = fn (voidptr, &configpkg.Config) !

pub type CoreSurfaceIMEFn = fn (voidptr) IMEPos

pub type CoreSurfacePwdFn = fn (voidptr) !string

pub type CoreSurfaceClipboardFn = fn (voidptr, ClipboardRequest, string, bool) !

pub type CoreSurfaceFontSizeFn = fn (voidptr, FontSize) !

pub type CoreSurfaceKeyBindingFn = fn (voidptr, &input.KeyEvent) ?voidptr

pub type CoreSurfaceInspectorRenderFn = fn (voidptr, voidptr)

pub type CoreSurfaceDisplayIdFn = fn (voidptr, u32)

pub type CoreSurfaceQuicklookFontFn = fn (voidptr) voidptr

pub type CoreSurfaceQuicklookSelectionFn = fn (voidptr, f64, f64) ?voidptr

// CoreBridge is installed by core.install_embedded_bridge from the root
// artifact. Every callback delegates to the canonical core.App/core.Surface;
// the fallback implementation remains useful for isolated apprt tests.
pub struct CoreBridge {
pub:
	app_create               CoreAppCreateFn = unsafe { nil }
	app_destroy              CoreAppDestroyFn = unsafe { nil }
	app_tick                 CoreAppTickFn = unsafe { nil }
	app_focus                CoreAppFocusFn = unsafe { nil }
	app_key                  CoreAppKeyFn = unsafe { nil }
	app_key_is_binding       CoreAppKeyFn = unsafe { nil }
	app_add_surface          CoreAppAddSurfaceFn = unsafe { nil }
	app_delete_surface       CoreAppDeleteSurfaceFn = unsafe { nil }
	app_needs_confirm        CoreAppNeedsConfirmFn = unsafe { nil }
	app_color_scheme         CoreAppColorSchemeFn = unsafe { nil }
	app_update_config        CoreAppUpdateConfigFn = unsafe { nil }
	app_focused_pwd          CoreAppFocusedPwdFn = unsafe { nil }
	surface_init             CoreSurfaceInitFn = unsafe { nil }
	surface_deinit           CoreSurfaceDeinitFn = unsafe { nil }
	surface_snapshot         CoreSurfaceSnapshotFn = unsafe { nil }
	surface_key              CoreSurfaceKeyFn = unsafe { nil }
	surface_refresh          CoreSurfaceVoidFn = unsafe { nil }
	surface_draw             CoreSurfaceVoidFn = unsafe { nil }
	surface_content_scale    CoreSurfaceContentScaleFn = unsafe { nil }
	surface_size             CoreSurfaceSizeFn = unsafe { nil }
	surface_color_scheme     CoreSurfaceColorSchemeFn = unsafe { nil }
	surface_mouse_button     CoreSurfaceMouseButtonFn = unsafe { nil }
	surface_mouse_pressure   CoreSurfaceMousePressureFn = unsafe { nil }
	surface_scroll           CoreSurfaceScrollFn = unsafe { nil }
	surface_cursor_pos       CoreSurfaceCursorPosFn = unsafe { nil }
	surface_preedit          CoreSurfacePreeditFn = unsafe { nil }
	surface_text             CoreSurfaceTextFn = unsafe { nil }
	surface_focus            CoreSurfaceBoolFn = unsafe { nil }
	surface_occlusion        CoreSurfaceBoolFn = unsafe { nil }
	surface_close            CoreSurfaceCloseFn = unsafe { nil }
	surface_has_selection    CoreSurfaceBoolQueryFn = unsafe { nil }
	surface_dump_text        CoreSurfaceDumpTextFn = unsafe { nil }
	surface_active_sel       CoreSurfaceSelectionFn = unsafe { nil }
	surface_resolve_sel      CoreSurfaceResolveSelectionFn = unsafe { nil }
	surface_lock             CoreSurfaceLockFn = unsafe { nil }
	surface_unlock           CoreSurfaceLockFn = unsafe { nil }
	surface_mouse_captured   CoreSurfaceBoolQueryFn = unsafe { nil }
	surface_binding          CoreSurfaceBindingFn = unsafe { nil }
	surface_update_config    CoreSurfaceUpdateConfigFn = unsafe { nil }
	surface_needs_confirm    CoreSurfaceBoolQueryFn = unsafe { nil }
	surface_ime              CoreSurfaceIMEFn = unsafe { nil }
	surface_pwd              CoreSurfacePwdFn = unsafe { nil }
	surface_clipboard        CoreSurfaceClipboardFn = unsafe { nil }
	surface_font_size        CoreSurfaceFontSizeFn = unsafe { nil }
	surface_inspector_on     CoreSurfaceVoidFn = unsafe { nil }
	surface_inspector_off    CoreSurfaceCloseFn = unsafe { nil }
	surface_inspector_render CoreSurfaceInspectorRenderFn = unsafe { nil }
	surface_key_binding      CoreSurfaceKeyBindingFn = unsafe { nil }
	surface_display_id       CoreSurfaceDisplayIdFn = unsafe { nil }
	surface_quicklook_font   CoreSurfaceQuicklookFontFn = unsafe { nil }
	surface_quicklook_sel    CoreSurfaceQuicklookSelectionFn = unsafe { nil }
}

__global g_core_bridge CoreBridge

// install_core_bridge connects the runtime-neutral embedded ABI to the
// canonical core implementation. It is called once during root-module init.
pub fn install_core_bridge(bridge CoreBridge) {
	g_core_bridge = bridge
}
