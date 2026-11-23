module core

// Runtime bridge for the embedded/libwitty application runtime.
//
// The canonical core package imports apprt for its platform boundary, so V
// cannot also import core from apprt. Ghostty solves this selection at Zig
// comptime. Witty uses this opaque callback table instead: the embedded ABI
// remains in apprt and every operation here delegates to the same App and
// Surface implementations used by the other runtimes.

import apprt
import configpkg
import datastruct
import font
import input
import log
import renderer
import terminal

struct EmbeddedAppCore {
mut:
	app      &App = unsafe { nil }
	runtime  apprt.RuntimeApp
	surfaces []&EmbeddedSurfaceCore
}

struct EmbeddedSurfaceCore {
mut:
	app              &EmbeddedAppCore = unsafe { nil }
	wrapper          &apprt.CoreSurface = unsafe { nil }
	runtime_app      apprt.RuntimeApp
	runtime_surface  apprt.RuntimeSurface
	surface          Surface
	surface_ref      SurfaceRef
	rt_surface       &apprt.Surface = unsafe { nil }
	selection        terminal.Selection
	binding_flags    input.Flags
	registered       bool
	inspector_marker voidptr
}

// install_embedded_bridge connects apprt's opaque ABI wrappers to the
// translated core implementation. Root artifacts call this during init.
pub fn install_embedded_bridge() {
	apprt.install_core_bridge(apprt.CoreBridge{
		app_create: bridge_app_create
		app_destroy: bridge_app_destroy
		app_tick: bridge_app_tick
		app_focus: bridge_app_focus
		app_key: bridge_app_key
		app_key_is_binding: bridge_app_key_is_binding
		app_add_surface: bridge_app_add_surface
		app_delete_surface: bridge_app_delete_surface
		app_needs_confirm: bridge_app_needs_confirm
		app_color_scheme: bridge_app_color_scheme
		app_update_config: bridge_app_update_config
		app_focused_pwd: bridge_app_focused_pwd
		surface_init: bridge_surface_init
		surface_deinit: bridge_surface_deinit
		surface_snapshot: bridge_surface_snapshot
		surface_key: bridge_surface_key
		surface_refresh: bridge_surface_refresh
		surface_draw: bridge_surface_draw
		surface_content_scale: bridge_surface_content_scale
		surface_size: bridge_surface_size
		surface_color_scheme: bridge_surface_color_scheme
		surface_mouse_button: bridge_surface_mouse_button
		surface_mouse_pressure: bridge_surface_mouse_pressure
		surface_scroll: bridge_surface_scroll
		surface_cursor_pos: bridge_surface_cursor_pos
		surface_preedit: bridge_surface_preedit
		surface_text: bridge_surface_text
		surface_focus: bridge_surface_focus
		surface_occlusion: bridge_surface_occlusion
		surface_close: bridge_surface_close
		surface_has_selection: bridge_surface_has_selection
		surface_dump_text: bridge_surface_dump_text
		surface_active_sel: bridge_surface_active_selection
		surface_resolve_sel: bridge_surface_resolve_selection
		surface_lock: bridge_surface_lock
		surface_unlock: bridge_surface_unlock
		surface_mouse_captured: bridge_surface_mouse_captured
		surface_binding: bridge_surface_binding
		surface_update_config: bridge_surface_update_config
		surface_needs_confirm: bridge_surface_needs_confirm
		surface_ime: bridge_surface_ime
		surface_pwd: bridge_surface_pwd
		surface_clipboard: bridge_surface_clipboard
		surface_font_size: bridge_surface_font_size
		surface_inspector_on: bridge_surface_inspector_on
		surface_inspector_off: bridge_surface_inspector_off
		surface_inspector_render: bridge_surface_inspector_render
		surface_key_binding: bridge_surface_key_binding
		surface_display_id: bridge_surface_display_id
		surface_quicklook_font: bridge_surface_quicklook_font
		surface_quicklook_sel: bridge_surface_quicklook_selection
	})
}

fn bridge_app_create() !voidptr {
	core_app := App.create()!
	return voidptr(&EmbeddedAppCore{
		app: core_app
	})
}

fn bridge_app_destroy(ptr voidptr) {
	if isnil(ptr) {
		return
	}
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	// App.deinit owns all remaining runtime surfaces in Ghostty. Deinitialize
	// the embedded wrappers first so their bridge pointers and the canonical
	// app's SurfaceRefs are removed together.
	for surface in self.surfaces.clone() {
		if !isnil(surface.rt_surface) {
			mut rt_surface := surface.rt_surface
			rt_surface.deinit()
		}
	}
	if !isnil(self.app) {
		self.app.destroy()
		self.app = unsafe { nil }
	}
	self.runtime.config.deinit()
	self.surfaces.clear()
}

fn bridge_app_sync_runtime(mut self EmbeddedAppCore, app &apprt.App) {
	self.runtime.config.deinit()
	self.runtime.config = app.config.clone()
}

fn bridge_app_flush_actions(mut self EmbeddedAppCore, app &apprt.App) ! {
	if self.runtime.actions.len == 0 {
		return
	}
	actions := self.runtime.actions.clone()
	self.runtime.actions.clear()
	mut rt_app := unsafe { &apprt.App(app) }
	for action in actions {
		target := bridge_apprt_target(self, action.target) or {
			log.warn('dropping embedded action for stale surface action=${action.action}')
			continue
		}
		_ = rt_app.perform_action(target, action.action, action.data)!
	}
}

fn bridge_apprt_target(self &EmbeddedAppCore, target apprt.Target) ?apprt.Target {
	match target {
		apprt.AppTarget {
			return apprt.Target(apprt.AppTarget{})
		}
		apprt.SurfaceTarget {
			for surface in self.surfaces {
				if target.surface == voidptr(&surface.surface) {
					return apprt.Target(apprt.SurfaceTarget{
						surface: voidptr(surface.wrapper)
					})
				}
			}
		}
	}
	return none
}

fn bridge_app_tick(ptr voidptr, app &apprt.App) ! {
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	bridge_app_sync_runtime(mut self, app)
	self.app.tick(mut self.runtime)!
	bridge_app_flush_actions(mut self, app)!
}

fn bridge_app_focus(ptr voidptr, focused bool) {
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	self.app.focus_event(focused)
}

fn bridge_app_key(ptr voidptr, app &apprt.App, event &input.KeyEvent) bool {
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	bridge_app_sync_runtime(mut self, app)
	result := self.app.key_event(mut self.runtime, *event)
	bridge_app_flush_actions(mut self, app) or {
		log.error('error performing embedded app keybind action err=${err}')
	}
	return result
}

fn bridge_app_key_is_binding(ptr voidptr, app &apprt.App, event &input.KeyEvent) bool {
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	bridge_app_sync_runtime(mut self, app)
	return self.app.key_event_is_binding(mut self.runtime, *event)
}

// Surface registration occurs after CoreSurface.init has created its stable
// SurfaceRef. The apprt call happens before that, matching Ghostty's ordering.
fn bridge_app_add_surface(ptr voidptr, surface voidptr) ! {
	_ = ptr
	_ = surface
}

fn bridge_app_delete_surface(ptr voidptr, surface_ptr voidptr) {
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	if isnil(surface_ptr) {
		return
	}
	rt_surface := unsafe { &apprt.Surface(surface_ptr) }
	backend := rt_surface.core_surface.backend
	if isnil(backend) {
		return
	}
	mut surface := unsafe { &EmbeddedSurfaceCore(backend) }
	if surface.registered {
		self.app.delete_surface(&surface.surface_ref)
		surface.registered = false
	}
	self.surfaces = self.surfaces.filter(it != surface)
}

fn bridge_app_needs_confirm(ptr voidptr) bool {
	self := unsafe { &EmbeddedAppCore(ptr) }
	return self.app.needs_confirm_quit()
}

fn bridge_app_color_scheme(ptr voidptr, app &apprt.App, scheme apprt.ColorScheme) ! {
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	bridge_app_sync_runtime(mut self, app)
	self.app.color_scheme_event(mut self.runtime, scheme)!
	bridge_app_flush_actions(mut self, app)!
}

fn bridge_app_update_config(ptr voidptr, app &apprt.App, config &configpkg.Config) ! {
	mut self := unsafe { &EmbeddedAppCore(ptr) }
	bridge_app_sync_runtime(mut self, app)
	self.app.update_config(mut self.runtime, config)!
	bridge_app_flush_actions(mut self, app)!
}

fn bridge_app_focused_pwd(ptr voidptr) ?string {
	self := unsafe { &EmbeddedAppCore(ptr) }
	surface := self.app.focused_surface() or { return none }
	return surface.pwd()
}

fn bridge_surface_target(self &EmbeddedSurfaceCore) apprt.Target {
	return apprt.Target(apprt.SurfaceTarget{
		surface: voidptr(self.wrapper)
	})
}

fn bridge_surface_runtime_action(ptr voidptr, action apprt.RuntimeAction) !bool {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	mut app := self.rt_surface.app
	target := match action.target {
		apprt.AppTarget { apprt.Target(apprt.AppTarget{}) }
		apprt.SurfaceTarget { bridge_surface_target(self) }
	}
	return app.perform_action(target, action.action, action.data)!
}

fn bridge_surface_runtime_wakeup(ptr voidptr) {
	if isnil(ptr) {
		return
	}
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	if isnil(self.rt_surface) || isnil(self.rt_surface.app) {
		return
	}
	self.rt_surface.app.wakeup()
}

fn bridge_runtime_close(ptr voidptr, confirm bool) {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.rt_surface.close(confirm)
}

fn bridge_runtime_content_scale(ptr voidptr) !apprt.ContentScale {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.rt_surface.get_content_scale()!
}

fn bridge_runtime_size(ptr voidptr) !apprt.SurfaceSize {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.rt_surface.get_size()!
}

fn bridge_runtime_cursor_pos(ptr voidptr) !apprt.CursorPos {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.rt_surface.get_cursor_pos()!
}

fn bridge_runtime_title(ptr voidptr) ?string {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.rt_surface.get_title()
}

fn bridge_runtime_set_clipboard(ptr voidptr, loc apprt.Clipboard, contents []apprt.ClipboardContent, confirm bool) ! {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.rt_surface.set_clipboard(loc, contents, confirm)!
}

fn bridge_runtime_supports_clipboard(ptr voidptr, loc apprt.Clipboard) bool {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.rt_surface.supports_clipboard(loc)
}

fn bridge_runtime_clipboard_request(ptr voidptr, loc apprt.Clipboard, req apprt.ClipboardRequest) !bool {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.rt_surface.clipboard_request(loc, req)!
}

fn bridge_runtime_default_env(ptr voidptr) !map[string]string {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.rt_surface.default_termio_env()!
}

fn embedded_renderer_view(surface &apprt.Surface) voidptr {
	match surface.platform {
		apprt.MacOSPlatform {
			return surface.platform.nsview
		}
		apprt.IOSPlatform {
			return surface.platform.uiview
		}
	}
}

fn bridge_surface_init(config &configpkg.Config, core_app &apprt.CoreApp, app &apprt.App, surface_ptr voidptr) !voidptr {
	if isnil(core_app.backend) || isnil(surface_ptr) {
		return error('embedded core bridge is not initialized')
	}
	mut app_core := unsafe { &EmbeddedAppCore(core_app.backend) }
	mut rt_surface := unsafe { &apprt.Surface(surface_ptr) }
	mut wrapper := &rt_surface.core_surface
	mut self := &EmbeddedSurfaceCore{
		app: app_core
		wrapper: wrapper
		rt_surface: rt_surface
	}
	self.runtime_app = apprt.RuntimeApp{
		user_data: voidptr(self)
		action_fn: bridge_surface_runtime_action
		wakeup_fn: bridge_surface_runtime_wakeup
		keyboard_layout: app.keyboard_layout()
	}
	self.runtime_surface = apprt.RuntimeSurface{
		user_data: voidptr(self)
		renderer_view: embedded_renderer_view(rt_surface)
		close_fn: bridge_runtime_close
		content_scale_fn: bridge_runtime_content_scale
		size_fn: bridge_runtime_size
		cursor_pos_fn: bridge_runtime_cursor_pos
		title_fn: bridge_runtime_title
		set_clipboard_fn: bridge_runtime_set_clipboard
		supports_clipboard_fn: bridge_runtime_supports_clipboard
		clipboard_request_fn: bridge_runtime_clipboard_request
		default_env_fn: bridge_runtime_default_env
	}
	self.surface_ref = SurfaceRef{
		core_surface: &self.surface
		rt_app: &app_core.runtime
	}
	// Ghostty registers the runtime surface before initializing the core
	// surface. Publish both identities first because initial size, title, and
	// cell-size actions target this surface synchronously.
	bridge_app_sync_runtime(mut app_core, app)
	wrapper.backend = voidptr(self)
	app_core.surfaces << self
	app_core.app.add_surface(&self.surface_ref)
	self.registered = true
	bridge_app_flush_actions(mut app_core, app) or {
		log.warn('error stopping embedded quit timer err=${err}')
	}
	self.surface.init(config, mut app_core.app, &self.runtime_app, &self.runtime_surface) or {
		if self.registered {
			app_core.app.delete_surface(&self.surface_ref)
			self.registered = false
			bridge_app_flush_actions(mut app_core, app) or {
				log.warn('error starting embedded quit timer during cleanup err=${err}')
			}
		}
		app_core.surfaces = app_core.surfaces.filter(it != self)
		wrapper.backend = unsafe { nil }
		return err
	}
	return voidptr(self)
}

fn bridge_surface_deinit(ptr voidptr) {
	if isnil(ptr) {
		return
	}
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	if self.registered && !isnil(self.app) && !isnil(self.app.app) {
		self.app.app.delete_surface(&self.surface_ref)
		self.registered = false
	}
	self.surface.deinit()
	if !isnil(self.app) {
		self.app.surfaces = self.app.surfaces.filter(it != self)
	}
}

fn bridge_surface_snapshot(ptr voidptr) apprt.CoreSurfaceSnapshot {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	mut inspector := ?&voidptr(none)
	if self.surface.inspector != none {
		self.inspector_marker = voidptr(self.surface.inspector or { unsafe { nil } })
		inspector = &self.inspector_marker
	}
	return apprt.CoreSurfaceSnapshot{
		child_exited: self.surface.child_exited
		font_size: apprt.FontSize{ points: self.surface.font_size.points }
		size: apprt.SurfaceSizeInfo{
			screen: apprt.ScreenSizeInfo{
				width: self.surface.size.screen.width
				height: self.surface.size.screen.height
			}
			cell: apprt.CellSizeInfo{
				width: self.surface.size.cell.width
				height: self.surface.size.cell.height
			}
		}
		config: apprt.SurfaceConfig{
			macos_option_as_alt: self.surface.config.macos_option_as_alt
			selection_word_chars: self.surface.config.selection_word_chars.map(rune(it).str()).join('')
		}
		inspector: inspector
	}
}

fn bridge_surface_key(ptr voidptr, event &input.KeyEvent, effect &apprt.InputEffect) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	value := self.surface.key_callback(*event)!
	unsafe { *effect = value }
}

fn bridge_surface_refresh(ptr voidptr) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.refresh_callback()!
}

fn bridge_surface_draw(ptr voidptr) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.draw()!
}

fn bridge_surface_content_scale(ptr voidptr, scale apprt.ContentScale) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.content_scale_callback(scale)!
}

fn bridge_surface_size(ptr voidptr, size apprt.SurfaceSize) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.size_callback(size)!
}

fn bridge_surface_color_scheme(ptr voidptr, scheme apprt.ColorScheme) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.color_scheme_callback(scheme)!
}

fn bridge_surface_mouse_button(ptr voidptr, action input.MouseButtonState, button input.MouseButton, mods input.Mods) !bool {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.surface.mouse_button_callback(action, button, mods)!
}

fn bridge_surface_mouse_pressure(ptr voidptr, stage input.PressureStage, pressure f64) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.mouse_pressure_callback(stage, pressure)!
}

fn bridge_surface_scroll(ptr voidptr, xoff f64, yoff f64, mods input.ScrollMods) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.scroll_callback(xoff, yoff, mods)!
}

fn bridge_surface_cursor_pos(ptr voidptr, pos apprt.CursorPos, mods input.Mods) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.cursor_pos_callback(pos, mods)!
}

fn bridge_surface_preedit(ptr voidptr, preedit ?string) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.preedit_callback(preedit)!
}

fn bridge_surface_text(ptr voidptr, text string) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.text_callback(text)!
}

fn bridge_surface_focus(ptr voidptr, focused bool) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.focus_callback(focused)!
}

fn bridge_surface_occlusion(ptr voidptr, visible bool) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.occlusion_callback(visible)!
}

fn bridge_surface_close(ptr voidptr) {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.close()
}

fn bridge_surface_has_selection(ptr voidptr) bool {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.surface.has_selection()
}

fn bridge_surface_dump_text(ptr voidptr, selection voidptr) !apprt.DumpedText {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	if isnil(selection) {
		return error('selection pointer is null')
	}
	sel := unsafe { *&terminal.Selection(selection) }
	result := self.surface.dump_text_locked(sel)!
	return apprt.DumpedText{
		text: result.text
		viewport: if viewport := result.viewport {
			apprt.DumpedTextViewport{
				tl_px_x: viewport.tl_px_x
				tl_px_y: viewport.tl_px_y
				offset_start: viewport.offset_start
				offset_len: viewport.offset_len
			}
		} else {
			none
		}
	}
}

fn bridge_surface_active_selection(ptr voidptr) ?voidptr {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	sel := self.surface.renderer_state.terminal_.screens.active.selection or { return none }
	self.selection = sel
	return voidptr(&self.selection)
}

fn bridge_surface_point_tag(value int) ?terminal.PointTag {
	return match value {
		0 { terminal.PointTag.active }
		1 { terminal.PointTag.viewport }
		2 { terminal.PointTag.screen }
		3 { terminal.PointTag.history }
		else { none }
	}
}

fn bridge_surface_pin(screen &terminal.Screen, tag_value int, coord_tag int, x u32, y u32) ?terminal.Pin {
	tag := bridge_surface_point_tag(tag_value) or { return none }
	clamped_x := if screen.pages.cols > 0 { min_u32(x, screen.pages.cols - 1) } else { u32(0) }
	clamped_y := if screen.pages.rows > 0 { min_u32(y, screen.pages.rows - 1) } else { u32(0) }
	return match coord_tag {
		0 {
			screen.pages.pin(terminal.Point.new(tag, terminal.Coordinate{
					x: u16(clamped_x)
					y: clamped_y
			}))
		}
		1 { screen.pages.get_top_left(tag) }
		2 { screen.pages.get_bottom_right(tag) }
		else { none }
	}
}

fn bridge_surface_resolve_selection(ptr voidptr, tl_tag int, tl_coord_tag int, tl_x u32, tl_y u32, br_tag int, br_coord_tag int, br_x u32, br_y u32, rectangle bool) ?voidptr {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	screen := self.surface.renderer_state.terminal_.screens.active
	start := bridge_surface_pin(screen, tl_tag, tl_coord_tag, tl_x, tl_y) or { return none }
	end := bridge_surface_pin(screen, br_tag, br_coord_tag, br_x, br_y) or { return none }
	self.selection = terminal.Selection.init(start, end, rectangle)
	return voidptr(&self.selection)
}

fn bridge_surface_lock(ptr voidptr) {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.renderer_state.mutex.lock()
}

fn bridge_surface_unlock(ptr voidptr) {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.renderer_state.mutex.unlock()
}

fn bridge_surface_mouse_captured(ptr voidptr) bool {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.surface.mouse_captured()
}

fn bridge_surface_binding(ptr voidptr, action input.Action) !bool {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.surface.perform_binding_action(action)!
}

fn bridge_surface_update_config(ptr voidptr, config &configpkg.Config) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.update_config(config)!
}

fn bridge_surface_needs_confirm(ptr voidptr) bool {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.surface.needs_confirm_quit()
}

fn bridge_surface_ime(ptr voidptr) apprt.IMEPos {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.surface.ime_point()
}

fn bridge_surface_pwd(ptr voidptr) !string {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	return self.surface.pwd() or { return error('surface working directory is unavailable') }
}

fn bridge_surface_clipboard(ptr voidptr, state apprt.ClipboardRequest, text string, confirmed bool) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.complete_clipboard_request(state, text, confirmed)!
}

fn bridge_surface_font_size(ptr voidptr, size apprt.FontSize) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	mut desired := self.surface.font_size
	desired.points = size.points
	self.surface.set_font_size(desired)!
}

fn bridge_surface_inspector_on(ptr voidptr) ! {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.activate_inspector()!
}

fn bridge_surface_inspector_off(ptr voidptr) {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.deactivate_inspector()
}

fn bridge_surface_inspector_render(ptr voidptr, context_handle voidptr) {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	self.surface.render_inspector(context_handle)
}

fn bridge_surface_key_binding(ptr voidptr, event &input.KeyEvent) ?voidptr {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	flags := self.surface.key_event_is_binding(*event) or { return none }
	self.binding_flags = flags
	return voidptr(&self.binding_flags)
}

fn bridge_surface_display_id(ptr voidptr, display_id u32) {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	_ = self.surface.renderer_thread.mailbox.push(renderer.RendererMessage(renderer.MacosDisplayIdMessage{
		display_id: display_id
	}), datastruct.blocking_queue_forever)
	self.surface.renderer_thread.wakeup.notify() or {}
}

fn bridge_surface_quicklook_font(ptr voidptr) voidptr {
	self := unsafe { &EmbeddedSurfaceCore(ptr) }
	grid := self.surface.font_grid
	if isnil(grid) {
		return unsafe { nil }
	}
	content_scale := self.rt_surface.get_content_scale() or { return unsafe { nil } }
	if content_scale.y <= 0 {
		return unsafe { nil }
	}
	grid.lock.rlock()
	defer {
		grid.lock.runlock()
	}
	mut collection := &grid.resolver.collection
	face := collection.get_face(font.Index{}) or { return unsafe { nil } }
	if isnil(face.ct_font) {
		return unsafe { nil }
	}
	return font.copy_coretext_font_with_size(face.ct_font, face.size.pixels() / f64(content_scale.y))
}

fn bridge_surface_quicklook_selection(ptr voidptr, x f64, y f64) ?voidptr {
	mut self := unsafe { &EmbeddedSurfaceCore(ptr) }
	screen := self.surface.renderer_state.terminal_.screens.active
	point := self.surface.pos_to_viewport(x, y)
	pin := screen.pages.pin(terminal.Point.new(.viewport, terminal.Coordinate{
			x: u16(point.x)
			y: u32(point.y)
	})) or { return none }
	self.selection = self.surface.io.impl.terminal.screens.active.select_word(pin, self.surface.config.selection_word_chars) or { return none }
	return voidptr(&self.selection)
}

fn min_u32(a u32, b u32) u32 {
	return if a < b { a } else { b }
}
