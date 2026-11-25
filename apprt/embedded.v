module apprt

// Application runtime for the embedded version of Ghostty. The embedded
// version is when Ghostty is embedded within a parent host application,
// rather than owning the application lifecycle itself. This is used for
// example for the macOS build of Ghostty so that we can use a native
// Swift+XCode-based application.

import input
import configpkg
import internal_os
import math
import time
import cimgui
import inspector
import os

// log_warn logs a warning message.
fn log_warn(msg string) {
	eprintln('[warn] embedded: ${msg}')
}

// log_err logs an error message.
fn log_err(msg string) {
	eprintln('[error] embedded: ${msg}')
}

// log_debug logs a debug message.
fn log_debug(msg string) {
	// In release builds this would be a no-op.
	$if debug {
		eprintln('[debug] embedded: ${msg}')
	}
}

// log_info logs an info message.
fn log_info(msg string) {
	eprintln('[info] embedded: ${msg}')
}

// -----------------------------------------------------------------------
// App
// -----------------------------------------------------------------------

// App is the embedded application runtime. Because we only expect the
// embedding API to be used in embedded environments, the options are
// designed so that we can expose it directly to a C callconv and not pay
// for any translation costs.
pub struct App {
pub mut:
	core_app &CoreApp = unsafe { nil }
	opts     AppOptions
	keymap   input.Keymap

	// The configuration for the app. This is owned by this structure.
	config configpkg.Config
}

// AppOptions contains the callbacks and configuration for the embedded
// runtime. C type: ghostty_runtime_config_s
pub struct AppOptions {
pub mut:
	// Userdata that is passed to all the callbacks.
	userdata voidptr

	// True if the selection clipboard is supported.
	supports_selection_clipboard bool

	// Callback called to wakeup the event loop. This should trigger
	// a full tick of the app loop.
	wakeup_cb fn (voidptr) = unsafe { nil }

	// Callback called to handle an action. RuntimeAction is the V equivalent
	// of Ghostty's tagged ghostty_action_s value.
	action_cb   fn (&App, Target, RuntimeAction) bool = unsafe { nil }
	c_action_cb fn (voidptr, CAPITarget, CAPIAction) bool = unsafe { nil }

	// Read the clipboard value. The return value must be preserved
	// by the host until the next call. If there is no valid clipboard
	// value then this should return null.
	read_clipboard_cb fn (voidptr, int, &ClipboardRequest) = unsafe { nil }

	// This may be called after a read clipboard call to request
	// confirmation that the clipboard value is safe to read. The embedder
	// must call complete_clipboard_request with the given request.
	confirm_read_clipboard_cb   fn (voidptr, string, &ClipboardRequest, ClipboardRequestType) = unsafe { nil }
	c_confirm_read_clipboard_cb fn (voidptr, &char, &ClipboardRequest, int) = unsafe { nil }

	// Write the clipboard value.
	write_clipboard_cb   fn (voidptr, int, []ClipboardContent, bool) = unsafe { nil }
	c_write_clipboard_cb fn (voidptr, int, &CAPIClipboardContentC, uint, bool) = unsafe { nil }

	// Close the current surface given by this function.
	close_surface_cb fn (voidptr, bool) = unsafe { nil }
}

// KeyTarget is the target of a key event. This is used to determine some
// subtly different behavior between app and surface key events.
pub type KeyTarget = AppKeyTarget | SurfaceKeyTarget

pub struct AppKeyTarget {}

pub struct SurfaceKeyTarget {
pub mut:
	surface &Surface
}

// EmbeddedKeyEvent is the key event sent for ghostty_surface_key and
// ghostty_app_key.
pub struct EmbeddedKeyEvent {
pub:
	action              input.KeyAction
	mods                input.Mods
	consumed_mods       input.Mods
	keycode             u32
	text                ?string
	unshifted_codepoint u32
	composing           bool
}

// core converts a libwitty key event into a core key event.
pub fn (self EmbeddedKeyEvent) core() ?input.KeyEvent {
	text := self.text or { '' }
	unshifted_codepoint := if self.unshifted_codepoint <= 0x1FFFFF {
		self.unshifted_codepoint
	} else {
		u32(0)
	}

	// We want to get the physical unmapped key to process keybinds.
	physical_key := input.native_keycode_to_key(self.keycode)

	// Build our final key event
	return input.KeyEvent{
		action: self.action
		key: physical_key
		mods: self.mods
		consumed_mods: self.consumed_mods
		composing: self.composing
		utf8: text
		unshifted_codepoint: unshifted_codepoint
	}
}

// App.init initializes the embedded app.
pub fn (mut self App) init(core_app &CoreApp, config &configpkg.Config, opts AppOptions) ! {
	// We have to clone the config.
	config_clone := config.clone()

	keymap := input.Keymap.init()!

	self.core_app = unsafe { core_app }
	self.config = config_clone
	self.opts = opts
	self.keymap = keymap
}

// terminate shuts down the embedded app.
pub fn (mut self App) terminate() {
	self.keymap.deinit()
	self.config.deinit()
}

// has_global_keybinds returns true if there are any global keybinds
// in the configuration.
pub fn (self &App) has_global_keybinds() bool {
	for entry in self.config.keybind.set.bindings {
		value := entry.value
		match value {
			input.Leader {}
			input.Leaf {
				if value.flags.global() {
					return true
				}
			}
			input.LeafChained {
				if value.flags.global() {
					return true
				}
			}
		}
	}
	return false
}

// focus_event forwards focus state to CoreApp.
pub fn (mut self App) focus_event(focused bool) {
	self.core_app.focus_event(focused)
}

// key_event processes a key event from the embedded runtime.
// See CoreApp.keyEvent.
pub fn (mut self App) key_event(mut target_ KeyTarget, event EmbeddedKeyEvent) !bool {
	// Convert our C key event into a Zig one.
	input_event := event.core() or { return false }

	// Invoke the core Ghostty logic to handle this input.
	effect := match mut target_ {
		AppKeyTarget {
			if self.core_app.key_event(self, &input_event) {
				InputEffect.consumed
			} else {
				InputEffect.ignored
			}
		}
		SurfaceKeyTarget {
			target_.surface.core_surface.key_callback(&input_event) or {
				return err
			}
		}
	}

	return match effect {
		.closed { true }
		.ignored { false }
		.consumed { true }
	}
}

// reload_keymap should be called whenever the keyboard layout was changed.
pub fn (mut self App) reload_keymap() ! {
	// Reload the keymap
	self.keymap.reload()!
}

// keyboard_layout loads the keyboard layout.
//
// Kind of expensive so this should be avoided if possible. When I say
// "kind of expensive" I mean that its not something you probably want
// to run on every keypress.
pub fn (self &App) keyboard_layout() input.KeyboardLayout {
	// We only support keyboard layout detection on macOS.
	$if macos {
		mut buf := []u8{len: 256}
		source_id := self.keymap.source_id(mut buf) or { return .unknown }
		return input.KeyboardLayout.map_apple_id(source_id) or { input.KeyboardLayout.unknown }
	} $else {
		return .unknown
	}
}

// wakeup triggers the event loop wakeup callback.
pub fn (self &App) wakeup() {
	if self.opts.wakeup_cb != unsafe { nil } {
		self.opts.wakeup_cb(self.opts.userdata)
	}
}

// wait waits for the next event. No-op for embedded runtime.
pub fn (self &App) wait() ! {
	// No-op for embedded runtime.
}

// new_surface creates a new surface for the app.
fn (mut self App) new_surface(opts SurfaceOptions) !&Surface {
	// Grab a surface allocation because we're going to need it.
	raw := unsafe { malloc(sizeof(Surface)) }
	if isnil(raw) {
		return error('OutOfMemory')
	}
	mut surface := unsafe { &Surface(raw) }
	unsafe {
		*surface = Surface{}
	}

	// Create the surface
	surface.init(mut self, opts) or {
		unsafe { free(surface) }
		return err
	}

	return surface
}

// close_surface closes the given surface.
pub fn (mut self App) close_surface(mut surface Surface) {
	surface.deinit()
	unsafe { free(&surface) }
}

// redraw_inspector queues a render for the inspector.
pub fn (mut self App) redraw_inspector(mut surface Surface) {
	surface.queue_inspector_render()
}

// perform_action performs a given action. Returns true if the action was
// able to be performed, false otherwise.
pub fn (mut self App) perform_action(target_ Target, action ActionKey, data ActionValue) !bool {
	// Special case certain actions before they are sent to the
	// embedded apprt.
	self.perform_pre_action(target_, action, data)

	// A config-change value holds a borrowed Config pointer; log it as a
	// pointer rather than recursively formatting the whole configuration.
	if data is ConfigChange {
		log_debug('dispatching action target=${target_} action=${action} config=${voidptr(data.config)}')
	} else {
		log_debug('dispatching action target=${target_} action=${action} data=${data}')
	}

	if self.opts.action_cb != unsafe { nil } {
		return self.opts.action_cb(self, target_, RuntimeAction{
			target: target_
			action: action
			data: data
		})
	}
	if self.opts.c_action_cb != unsafe { nil } {
		return self.opts.c_action_cb(voidptr(self), target_.capi(), RuntimeAction{
			target: target_
			action: action
			data: data
		}.capi())
	}
	return false
}

// perform_pre_action handles actions that need pre-processing before
// being sent to the embedder.
fn (mut self App) perform_pre_action(target_ Target, action ActionKey, data ActionValue) {
	// Special case certain actions before they are sent to the embedder
	match action {
		.set_title {
			match target_ {
				AppTarget {}
				SurfaceTarget {
					// Store a copy of the title on the surface so that
					// getTitle works without the embedder needing to track it.
					if target_.surface != unsafe { nil } {
						core_surface := unsafe { &CoreSurface(target_.surface) }
						if !isnil(core_surface.runtime_surface) {
							surface_ptr := unsafe { &Surface(core_surface.runtime_surface) }
							if data is SetTitle {
								unsafe {
									surface_ptr.title = data.title.clone()
								}
							}
						}
					}
				}
			}
		}
		.config_change {
			match target_ {
				SurfaceTarget {}
				// For app updates, we update our core config. We need to
				// clone it because the caller owns the param.
				AppTarget {
					if data is ConfigChange {
						updated := data.config.clone()
						self.config.deinit()
						self.config = updated
					}
				}
			}
		}
		else {}
	}
}

// perform_ipc sends the given IPC to a running Ghostty. Returns true if
// the action was able to be performed, false otherwise.
//
// Note that this is a static function. Since this is called from a CLI app
// (or some other process that is not Ghostty) there is no full-featured
// apprt App to use.
pub fn perform_ipc(action string) !bool {
	// IPC is not supported in the embedded runtime. The embedded runtime
	// runs within a host application that manages its own IPC. Returning false
	// tells the caller that no existing instance handled the action.
	_ = action
	return false
}

// -----------------------------------------------------------------------
// Platform
// -----------------------------------------------------------------------

// Platform is platform-specific configuration for libwitty.
pub type Platform = MacOSPlatform | IOSPlatform

// MacOSPlatform holds the macOS-specific platform config.
pub struct MacOSPlatform {
pub:
	// The view to render the surface on.
	nsview voidptr
}

// IOSPlatform holds the iOS-specific platform config.
pub struct IOSPlatform {
pub:
	// The view to render the surface on.
	uiview voidptr
}

// PlatformTag identifies the platform.
pub enum PlatformTag as i32 {
	// "0" is reserved for invalid so we can detect unset values
	// from the C API.
	macos = 1
	ios   = 2
}

// PlatformC is the C ABI compatible version of Platform. The tag is
// expected to be stored elsewhere.
pub struct PlatformC {
pub mut:
	// For macOS.
	nsview voidptr
	// For iOS.
	uiview voidptr
}

// platform_init initializes a Platform from a tag and configuration
// from the C ABI.
pub fn platform_init(tag_int int, c_platform PlatformC) !Platform {
	return match tag_int {
		int(PlatformTag.macos) {
			$if !macos && !ios {
				return error('UnsupportedPlatform')
			}
			if c_platform.nsview == unsafe { nil } {
				return error('NSView must be set')
			}
			Platform(MacOSPlatform{ nsview: c_platform.nsview })
		}
		int(PlatformTag.ios) {
			$if !macos && !ios {
				return error('UnsupportedPlatform')
			}
			if c_platform.uiview == unsafe { nil } {
				return error('UIView must be set')
			}
			Platform(IOSPlatform{ uiview: c_platform.uiview })
		}
		else {
			return error('InvalidEnumTag')
		}
	}
}

// -----------------------------------------------------------------------
// EnvVar
// -----------------------------------------------------------------------

// EnvVar represents an environment variable key-value pair.
pub struct EnvVar {
pub:
	// The name of the environment variable.
	key string
	// The value of the environment variable.
	value string
}

// -----------------------------------------------------------------------
// Surface
// -----------------------------------------------------------------------

// Surface represents a single terminal surface in the embedded runtime.
pub struct Surface {
pub mut:
	app           &App = unsafe { nil }
	platform      Platform = MacOSPlatform{}
	userdata      voidptr
	core_surface  CoreSurface
	content_scale ContentScale
	size          SurfaceSize
	cursor_pos    CursorPos
	inspector_    ?&TerminalInspector

	// The current title of the surface. The embedded apprt saves this so
	// that getTitle works without the implementer needing to save it.
	title ?string

	// Retain the borrowed working-directory pointer returned by the C ABI.
	capi_inherited_working_directory string
}

// SurfaceOptions contains initialization options for a Surface.
pub struct SurfaceOptions {
pub:
	// The platform that this surface is being initialized for and
	// the associated platform-specific configuration.
	platform_tag int
	platform     PlatformC

	// Userdata passed to some of the callbacks.
	userdata voidptr

	// The scale factor of the screen.
	scale_factor f64 = 1.0

	// The font size to inherit. If 0, default font size will be used.
	font_size f32

	// The working directory to load into.
	working_directory ?string

	// The command to run in the new surface. If this is set then
	// the "wait-after-command" option is also automatically set to true,
	// since this is used for scripting.
	//
	// This command always run in a shell (e.g. via `/bin/sh -c`),
	// despite Ghostty allowing directly executed commands via config.
	// This is a legacy thing and we should probably change it in the
	// future once we have a concrete use case.
	command ?string

	// Extra environment variables to set for the surface.
	env_vars []EnvVar

	// Input to send to the command after it is started.
	initial_input ?string

	// Wait after the command exits.
	wait_after_command bool

	// Context for the new surface.
	context NewSurfaceContext = .window
}

// Surface.init initializes a new embedded surface.
pub fn (mut self Surface) init(mut app App, opts SurfaceOptions) ! {
	self.app = unsafe { app }
	self.platform = platform_init(opts.platform_tag, opts.platform)!
	self.userdata = opts.userdata
	self.core_surface = CoreSurface{}
	scale := f32(opts.scale_factor)
	self.content_scale = ContentScale{
		x: scale
		y: scale
	}
	self.size = SurfaceSize{ width: 800, height: 600 }
	self.cursor_pos = CursorPos{ x: -1, y: -1 }

	// Add ourselves to the list of surfaces on the app.
	app.core_app.add_surface(self)!

	// Clone the config and inherit surface-scoped values from the previously
	// focused surface, matching the shared apprt surface initializer.
	mut config := new_config(app.core_app, &app.config, opts.context)
	defer {
		config.deinit()
	}

	// If we have a working directory from the options then we set it.
	if wd := opts.working_directory {
		if wd.len > 0 && os.is_abs_path(wd) && os.is_dir(wd) {
			config.working_directory = wd
		}
	}

	// If we have a command from the options then we set it.
	if cmd := opts.command {
		if cmd.len > 0 {
			config.command = configpkg.ShellCmd{ shell: cmd }
			config.wait_after_command = true
		}
	}

	// Apply any environment variables that were requested.
	for env_var in opts.env_vars {
		mut replaced := false
		for i, entry in config.env.entries {
			if entry.key == env_var.key {
				config.env.entries[i] = configpkg.StringMapEntry{
					key: env_var.key
					value: env_var.value
				}
				replaced = true
				break
			}
		}
		if !replaced {
			config.env.entries << configpkg.StringMapEntry{
				key: env_var.key
				value: env_var.value
			}
		}
	}

	// If we have initial input, escape the bytes into the retained config
	// representation. Termio decodes this after cloning the startup state.
	if initial := opts.initial_input {
		config.input.items.clear()
		config.input.items << configpkg.ReadableIORaw{
			value: input.zig_escape(initial)
		}
	}

	// Wait after command
	if opts.wait_after_command {
		config.wait_after_command = true
	}

	// Initialize our surface right away. We're given a view that is
	// ready to use.
	self.core_surface.init(&config, app.core_app, app, self) or {
		app.core_app.delete_surface(self)
		return err
	}

	// If our options requested a specific font-size, set that.
	if opts.font_size != 0 {
		mut font_size := self.core_surface.font_size
		font_size.points = opts.font_size
		self.core_surface.set_font_size(font_size) or {
			self.core_surface.deinit()
			app.core_app.delete_surface(self)
			return err
		}
	}
}

// deinit shuts down the surface.
pub fn (mut self Surface) deinit() {
	// Shut down our inspector
	self.free_inspector()

	// Remove ourselves from the list of known surfaces in the app.
	unsafe {
		self.app.core_app.delete_surface(self)
	}

	// Clean up our core surface so that all the rendering and IO stop.
	self.core_surface.deinit()
}

// init_inspector initializes the inspector instance. A surface can only
// have one inspector at any given time, so this will return the previous
// inspector if it was already initialized.
pub fn (mut self Surface) init_inspector() !&TerminalInspector {
	if v := self.inspector_ {
		return v
	}

	mut insp := &TerminalInspector{}
	insp.init(mut self)!
	self.inspector_ = insp
	return insp
}

// free_inspector frees the inspector if one is active.
pub fn (mut self Surface) free_inspector() {
	if mut v := self.inspector_ {
		v.deinit()
		self.inspector_ = none
	}
}

// core returns a pointer to the core surface.
pub fn (mut self Surface) core() &CoreSurface {
	return &self.core_surface
}

// rt_app returns the parent app.
pub fn (self &Surface) rt_app() &App {
	return self.app
}

// close requests that the surface be closed.
pub fn (self &Surface) close(process_alive bool) {
	if self.app.opts.close_surface_cb == unsafe { nil } {
		log_info('runtime embedder does not support closing a surface')
		return
	}
	self.app.opts.close_surface_cb(self.userdata, process_alive)
}

// get_content_scale returns the content scale of the surface.
pub fn (self &Surface) get_content_scale() !ContentScale {
	return self.content_scale
}

// get_size returns the size of the surface.
pub fn (self &Surface) get_size() !SurfaceSize {
	return self.size
}

// get_title returns the current title of the surface.
pub fn (self &Surface) get_title() ?string {
	return self.title
}

// supports_clipboard returns true if the given clipboard type is supported.
pub fn (self &Surface) supports_clipboard(clipboard_type Clipboard) bool {
	return match clipboard_type {
		.standard { true }
		.selection, .primary { self.app.opts.supports_selection_clipboard }
	}
}

// clipboard_request initiates a clipboard read request.
pub fn (mut self Surface) clipboard_request(clipboard_type Clipboard, state ClipboardRequest) !bool {
	// We need to allocate to get a pointer to store our clipboard request
	// so that it is stable until the read_clipboard callback and call
	// complete_clipboard_request. This sucks but clipboard requests aren't
	// high throughput so it's probably fine.
	raw_state := unsafe { malloc(sizeof(ClipboardRequest)) }
	if isnil(raw_state) {
		return error('OutOfMemory')
	}
	mut state_ptr := unsafe { &ClipboardRequest(voidptr(raw_state)) }
	unsafe {
		*state_ptr = state
	}
	if self.app.opts.read_clipboard_cb != unsafe { nil } {
		self.app.opts.read_clipboard_cb(
			self.userdata,
			int(clipboard_type),
			state_ptr,
		)
	} else {
		unsafe { free(state_ptr) }
	}

	// Embedded apprt can't synchronously check clipboard content types,
	// so we always return true to indicate the request was started.
	return true
}

// complete_clipboard_request completes a clipboard read request.
fn (mut self Surface) complete_clipboard_request(str string, state &ClipboardRequest, confirmed bool) {
	// Attempt to complete the request, but we may request
	// confirmation.
	self.core_surface.complete_clipboard_request(*state, str, confirmed) or {
		if err.msg() !in ['UnsafePaste', 'UnauthorizedPaste'] {
			log_err('error completing clipboard request err=${err}')
			unsafe { free(state) }
			return
		}
		// If the paste is unsafe or unauthorized, ask for confirmation.
		if self.app.opts.confirm_read_clipboard_cb != unsafe { nil } {
			self.app.opts.confirm_read_clipboard_cb(
				self.userdata,
				str,
				state,
				state.tag(),
			)
			return
		}
		if self.app.opts.c_confirm_read_clipboard_cb != unsafe { nil } {
			self.app.opts.c_confirm_read_clipboard_cb(
				self.userdata,
				&char(str.str),
				state,
				int(state.tag()),
			)
			return
		}
	}
	unsafe { free(state) }
}

// set_clipboard sets the clipboard content.
pub fn (self &Surface) set_clipboard(clipboard_type Clipboard, contents []ClipboardContent, confirm bool) ! {
	if self.app.opts.write_clipboard_cb != unsafe { nil } {
		self.app.opts.write_clipboard_cb(
			self.userdata,
			int(clipboard_type),
			contents,
			confirm,
		)
		return
	}
	if self.app.opts.c_write_clipboard_cb != unsafe { nil } {
		mut values := []CAPIClipboardContentC{len: contents.len}
		for idx, content in contents {
			values[idx] = CAPIClipboardContentC{
				mime: &char(content.mime.str)
				data: &char(content.data.str)
			}
		}
		mut ptr := unsafe { &CAPIClipboardContentC(nil) }
		if values.len > 0 {
			ptr = unsafe { &values[0] }
		}
		self.app.opts.c_write_clipboard_cb(
			self.userdata,
			int(clipboard_type),
			ptr,
			uint(values.len),
			confirm,
		)
	}
}

// get_cursor_pos returns the current cursor position.
pub fn (self &Surface) get_cursor_pos() !CursorPos {
	return self.cursor_pos
}

// refresh tells the surface it needs to schedule a render.
pub fn (mut self Surface) refresh() {
	self.core_surface.refresh_callback() or {
		log_err('error in refresh callback err=${err}')
		return
	}
}

// draw tells the surface it needs to draw NOW if possible.
pub fn (mut self Surface) draw() {
	self.core_surface.draw() or {
		log_err('error in draw err=${err}')
		return
	}
}

// update_content_scale updates the DPI content scale of the surface.
pub fn (mut self Surface) update_content_scale(x f64, y f64) {
	// We are an embedded API so the caller can send us all sorts of
	// garbage. We want to make sure that the float values are valid
	// and we don't want to support fractional scaling below 1.
	x_scaled := math.max(1.0, if math.is_nan(x) { 1.0 } else { x })
	y_scaled := math.max(1.0, if math.is_nan(y) { 1.0 } else { y })

	self.content_scale = ContentScale{
		x: f32(x_scaled)
		y: f32(y_scaled)
	}

	self.core_surface.content_scale_callback(self.content_scale) or {
		log_err('error in content scale callback err=${err}')
		return
	}
}

// update_size updates the pixel size of the surface.
pub fn (mut self Surface) update_size(width u32, height u32) {
	// Runtimes sometimes generate superfluous resize events even
	// if the size did not actually change (SwiftUI). We check
	// that the size actually changed from what we last recorded
	// since resizes are expensive.
	if self.size.width == width && self.size.height == height {
		return
	}

	self.size = SurfaceSize{
		width: width
		height: height
	}

	// Call the primary callback.
	self.core_surface.size_callback(self.size) or {
		log_err('error in size callback err=${err}')
		return
	}
}

// color_scheme_callback notifies the surface of a color scheme change.
pub fn (mut self Surface) color_scheme_callback(scheme ColorScheme) {
	self.core_surface.color_scheme_callback(scheme) or {
		log_err('error setting color scheme err=${err}')
		return
	}
}

// mouse_button_callback handles a mouse button event.
pub fn (mut self Surface) mouse_button_callback(action input.MouseButtonState, button input.MouseButton, mods input.Mods) bool {
	return self.core_surface.mouse_button_callback(action, button, mods) or {
		log_err('error in mouse button callback err=${err}')
		return false
	}
}

// mouse_pressure_callback handles a mouse pressure event (Force Touch).
pub fn (mut self Surface) mouse_pressure_callback(stage input.PressureStage, pressure f64) {
	self.core_surface.mouse_pressure_callback(stage, pressure) or {
		log_err('error in mouse pressure callback err=${err}')
		return
	}
}

// scroll_callback handles a scroll event.
pub fn (mut self Surface) scroll_callback(xoff f64, yoff f64, mods input.ScrollMods) {
	self.core_surface.scroll_callback(xoff, yoff, mods) or {
		log_err('error in scroll callback err=${err}')
		return
	}
}

// cursor_pos_callback handles a cursor position update.
pub fn (mut self Surface) cursor_pos_callback(x f64, y f64, mods input.Mods) {
	// Convert our unscaled x/y to scaled.
	self.cursor_pos = self.cursor_pos_to_pixels(CursorPos{
		x: f32(x)
		y: f32(y)
	}) or {
		log_err('error converting cursor pos to scaled pixels in cursor pos callback err=${err}')
		return
	}

	self.core_surface.cursor_pos_callback(self.cursor_pos, mods) or {
		log_err('error in cursor pos callback err=${err}')
		return
	}
}

// preedit_callback handles IME preedit text.
pub fn (mut self Surface) preedit_callback(preedit ?string) {
	self.core_surface.preedit_callback(preedit) or {
		log_err('error in preedit callback err=${err}')
		return
	}
}

// text_callback handles committed text input.
pub fn (mut self Surface) text_callback(text string) {
	self.core_surface.text_callback(text) or {
		log_err('error in key callback err=${err}')
		return
	}
}

// focus_callback handles focus state changes.
pub fn (mut self Surface) focus_callback(focused bool) {
	self.core_surface.focus_callback(focused) or {
		log_err('error in focus callback err=${err}')
		return
	}
}

// occlusion_callback handles occlusion state changes.
pub fn (mut self Surface) occlusion_callback(visible bool) {
	self.core_surface.occlusion_callback(visible) or {
		log_err('error in occlusion callback err=${err}')
		return
	}
}

// queue_inspector_render queues an inspector render.
fn (mut self Surface) queue_inspector_render() {
	self.app.perform_action(
		Target(SurfaceTarget{ surface: voidptr(&self.core_surface) }),
		.render_inspector,
		ActionVoid{},
	) or {
		log_err('error rendering the inspector err=${err}')
		return
	}
}

// new_surface_options returns the options to use for a surface that
// inherits from this one.
pub fn (self &Surface) new_surface_options(context NewSurfaceContext) SurfaceOptions {
	font_size := if self.app.config.window_inherit_font_size {
		self.core_surface.font_size.points
	} else {
		f32(0)
	}

	working_directory := if should_inherit_working_directory(context, &self.app.config) {
		self.core_surface.pwd() or { '' }
	} else {
		''
	}

	return SurfaceOptions{
		font_size: font_size
		working_directory: if working_directory.len > 0 {
			working_directory
		} else {
			none
		}
		context: context
	}
}

// default_termio_env returns the default environment variables for the
// terminal IO process.
pub fn (self &Surface) default_termio_env() !map[string]string {
	mut env := internal_os.get_env_map()!

	$if macos || ios {
		// Xcode injects a set of loader variables as a group. Only scrub the group
		// when its marker is present, matching Ghostty and avoiding changes to
		// deliberately configured shell environments.
		if '__XCODE_BUILT_PRODUCTS_DIR_PATHS' in env {
			for key in ['__XCODE_BUILT_PRODUCTS_DIR_PATHS', '__XPC_DYLD_LIBRARY_PATH',
				'DYLD_FRAMEWORK_PATH', 'DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH', 'LD_LIBRARY_PATH',
				'SECURITYSESSIONID', 'XPC_SERVICE_NAME'] {
				env.delete(key)
			}
		}

		env.delete('GHOSTTY_MAC_LAUNCH_SOURCE')
		if internal_os.launched_from_desktop() {
			env.delete('LANGUAGE')
		}
	}

	return env
}

// cursor_pos_to_pixels converts screen coordinates to pixel coordinates.
// The cursor position from the host directly is in screen coordinates but
// all our interface works in pixels.
fn (self &Surface) cursor_pos_to_pixels(pos CursorPos) !CursorPos {
	scale := self.get_content_scale()!
	return CursorPos{ x: pos.x * scale.x, y: pos.y * scale.y }
}

// -----------------------------------------------------------------------
// TerminalInspector
// -----------------------------------------------------------------------

// TerminalInspector is the state required for the terminal inspector. A terminal
// inspector is 1:1 with a Surface.
pub struct TerminalInspector {
pub mut:
	surface       &Surface = unsafe { nil }
	content_scale f64 = 1.0
	context       cimgui.Context
	metal_active  bool

	// Our previous instant used to calculate delta time for animations.
	prev_time_ns ?i64
}

// TerminalInspector.init initializes the inspector.
pub fn (mut self TerminalInspector) init(mut surface Surface) ! {
	context := cimgui.Context.create()!
	context.set_backend_platform(.embedded)
	inspector.setup(context)
	self.surface = unsafe { surface }
	self.context = context

	surface.core_surface.activate_inspector() or {
		log_err('failed to activate inspector err=${err}')
	}
}

// deinit destroys the inspector.
pub fn (mut self TerminalInspector) deinit() {
	self.surface.core_surface.deactivate_inspector()
	$if macos || ios {
	if self.metal_active {
		self.context.metal_shutdown()
		self.metal_active = false
	}
	}
	self.context.destroy()
	self.context = cimgui.Context{}
}

// queue_render queues a render for the next frame.
pub fn (mut self TerminalInspector) queue_render() {
	self.surface.queue_inspector_render()
}

$if macos || ios {
// init_metal initializes the inspector for a metal backend.
pub fn (mut self TerminalInspector) init_metal(device voidptr) bool {
	if self.metal_active {
		self.context.metal_shutdown()
		self.metal_active = false
	}
	if !self.context.metal_init(device) {
		log_warn('failed to initialize metal backend')
		return false
	}
	self.metal_active = true
	log_debug('initialized metal backend')
	return true
}

// render_metal renders the inspector using the Metal backend.
pub fn (mut self TerminalInspector) render_metal(command_buffer voidptr, desc voidptr) ! {
	self.prepare_metal_frame(desc)!
	self.context.metal_render(command_buffer, desc)
}

// prepare_metal_frame advances the inspector and produces Dear ImGui draw data.
pub fn (mut self TerminalInspector) prepare_metal_frame(desc voidptr) ! {
	if !self.metal_active {
		return error('inspector Metal backend is not initialized')
	}

	// Ghostty submits two frames so Dear ImGui completes all internal state
	// processing before the draw data is encoded.
	for _ in 0 .. 2 {
		self.context.metal_new_frame(desc)
		self.new_frame()!
		self.surface.core_surface.render_inspector(self.context.handle)
		self.context.render_frame()
	}
}

}

// update_content_scale updates the inspector's content scale.
pub fn (mut self TerminalInspector) update_content_scale(x f64, y f64) {
	_ = y

	// Cache our scale because we use it for cursor position calculations.
	self.content_scale = x
	self.context.reset_style(f32(x))
}

// update_size updates the inspector's display size.
pub fn (mut self TerminalInspector) update_size(width u32, height u32) {
	self.context.set_size(width, height)
}

// mouse_button_callback handles a mouse button event for the inspector.
pub fn (mut self TerminalInspector) mouse_button_callback(action input.MouseButtonState, button input.MouseButton, mods input.Mods) {
	_ = mods
	self.queue_render()

	imgui_button := match button {
		.left { cimgui.MouseButton.left }
		.middle { cimgui.MouseButton.middle }
		.right { cimgui.MouseButton.right }
		else {
			return
		}
	}
	self.context.add_mouse_button(imgui_button, action == .press)
}

// scroll_callback handles a scroll event for the inspector.
pub fn (mut self TerminalInspector) scroll_callback(xoff f64, yoff f64, mods input.ScrollMods) {
	self.queue_render()

	scale := if mods.precision() { 0.1 } else { 1.0 }
	self.context.add_mouse_wheel(f32(xoff * scale), f32(yoff * scale))
}

// cursor_pos_callback handles a cursor position update for the inspector.
pub fn (mut self TerminalInspector) cursor_pos_callback(x f64, y f64) {
	self.queue_render()
	self.context.add_mouse_pos(f32(x * self.content_scale), f32(y * self.content_scale))
}

// focus_callback handles focus state changes for the inspector.
pub fn (mut self TerminalInspector) focus_callback(focused bool) {
	self.queue_render()
	self.context.add_focus(focused)
}

// text_callback handles text input for the inspector.
pub fn (mut self TerminalInspector) text_callback(text string) {
	self.queue_render()
	self.context.add_text(text)
}

// key_callback handles key input for the inspector.
pub fn (mut self TerminalInspector) key_callback(action input.KeyAction, key input.Key, mods input.Mods) ! {
	self.queue_render()

	self.context.add_key(.left_shift, mods.shift())
	self.context.add_key(.left_ctrl, mods.ctrl())
	self.context.add_key(.left_alt, mods.alt())
	self.context.add_key(.left_super, mods.super_())

	if imgui_key := key.imgui_key() {
		self.context.add_key(imgui_key, action == .press || action == .repeat)
	}
}

// new_frame sets up a new ImGui frame with delta time calculation.
fn (mut self TerminalInspector) new_frame() ! {
	now := i64(time.sys_mono_now())
	delta_time := if previous := self.prev_time_ns {
		f32(math.max(0.00001, f64(now - previous) / 1_000_000_000.0))
	} else {
		f32(1.0 / 60.0)
	}
	self.prev_time_ns = now
	self.context.begin_frame(delta_time)
}

// -----------------------------------------------------------------------
// CAPI types
// -----------------------------------------------------------------------

// CAPIKeyEvent is the raw C API version of the key event.
// This is the same as EmbeddedKeyEvent but with C-compatible int types
// for mods.
pub struct CAPIKeyEvent {
pub:
	action              input.KeyAction
	mods                int
	consumed_mods       int
	keycode             u32
	text                ?string
	unshifted_codepoint u32
	composing           bool
}

// key_event converts from the C API key event to an EmbeddedKeyEvent.
pub fn (self CAPIKeyEvent) key_event() EmbeddedKeyEvent {
	return EmbeddedKeyEvent{
		action: self.action
		mods: mods_from_int(self.mods)
		consumed_mods: mods_from_int(self.consumed_mods)
		keycode: self.keycode
		text: self.text
		unshifted_codepoint: self.unshifted_codepoint
		composing: self.composing
	}
}

// mods_from_int converts an integer bitmask to input.Mods.
fn mods_from_int(v int) input.Mods {
	return input.mods_from_int(u16(v))
}

// mods_to_int converts input.Mods to an integer bitmask.
fn mods_to_int(m input.Mods) int {
	return int(m.int())
}

// CAPISurfaceSize represents the C API surface size with grid and pixel info.
pub struct CAPISurfaceSize {
pub:
	columns        u16
	rows           u16
	width_px       u32
	height_px      u32
	cell_width_px  u32
	cell_height_px u32
}

// CAPIClipboardContent represents a clipboard content entry (C ABI).
// ghostty_clipboard_content_s
pub struct CAPIClipboardContent {
pub:
	mime string
	data string
}

// CAPIText represents text read from the terminal with viewport metadata.
// ghostty_text_s
pub struct CAPIText {
pub mut:
	tl_px_x      f64
	tl_px_y      f64
	offset_start u32
	offset_len   u32
	text         ?string
	text_len     uint
}

// deinit frees the text buffer.
pub fn (mut self CAPIText) deinit() {
	self.text = none
	self.text_len = 0
}

// CAPIPoint represents a point in the terminal grid.
// ghostty_point_s
pub struct CAPIPoint {
pub:
	tag       CAPIPointTag
	coord_tag CAPICoordTag
	x         u32
	y         u32
}

// CAPIPointTag identifies the coordinate space.
pub enum CAPIPointTag as i32 {
	active   = 0
	viewport = 1
	screen   = 2
	history  = 3
}

// CAPICoordTag identifies how coordinates should be interpreted.
pub enum CAPICoordTag as i32 {
	exact        = 0
	top_left     = 1
	bottom_right = 2
}

// CAPISelection represents a selection in the terminal.
// ghostty_selection_s
pub struct CAPISelection {
pub:
	tl        CAPIPoint
	br        CAPIPoint
	rectangle bool
}

// -----------------------------------------------------------------------
// CAPI functions (public API)
// -----------------------------------------------------------------------

// ghostty_app_new creates a new app.
pub fn ghostty_app_new(opts &AppOptions, config &configpkg.Config) ?&App {
	return app_new_(opts, config) or {
		log_err('error initializing app err=${err}')
		return none
	}
}

fn app_new_(opts &AppOptions, config &configpkg.Config) !&App {
	mut core_app := CoreApp.create()!

	// Create our runtime app
	raw := unsafe { malloc(sizeof(App)) }
	if isnil(raw) {
		core_app.destroy()
		return error('OutOfMemory')
	}
	mut app := unsafe { &App(raw) }
	unsafe {
		*app = App{}
	}
	app.init(core_app, config, *opts) or {
		unsafe { free(app) }
		core_app.destroy()
		return err
	}

	return app
}

// ghostty_app_tick ticks the event loop. This should be called whenever
// the "wakeup" callback is invoked for the runtime.
pub fn ghostty_app_tick(mut v App) {
	v.core_app.tick(v) or {
		log_err('error app tick err=${err}')
	}
}

// ghostty_app_userdata returns the userdata associated with the app.
pub fn ghostty_app_userdata(v &App) voidptr {
	return v.opts.userdata
}

// ghostty_app_free frees the app and its resources.
pub fn ghostty_app_free(mut v App) {
	mut core_app := v.core_app
	v.terminate()
	// CoreApp.destroy deinitializes every live surface. Embedded Surface.deinit
	// follows its owning App to unregister itself, so that App must remain alive
	// until core destruction completes. Zig's allocator left the source ordering
	// observable in practice, but V's free makes the same dereference an immediate
	// use-after-free.
	core_app.destroy()
	unsafe { free(&v) }
}

// ghostty_app_set_focus updates the focused state of the app.
pub fn ghostty_app_set_focus(mut app App, focused bool) {
	app.focus_event(focused)
}

// ghostty_app_key notifies the app of a global keypress capture. This will
// return true if the key was captured by the app, in which case the caller
// should not process the key.
pub fn ghostty_app_key(mut app App, event CAPIKeyEvent) bool {
	mut target := KeyTarget(AppKeyTarget{})
	return app.key_event(mut target, event.key_event()) or {
		log_warn('error processing key event err=${err}')
		return false
	}
}

// ghostty_app_key_is_binding returns true if the given key event would
// trigger a binding if it were sent to the surface right now. The
// "right now" is important because things like trigger sequences are only
// valid until the next key event.
pub fn ghostty_app_key_is_binding(app &App, event CAPIKeyEvent) bool {
	core_event := event.key_event().core() or {
		log_warn('error processing key event')
		return false
	}

	return app.core_app.key_event_is_binding(app, &core_event)
}

// ghostty_app_keyboard_changed notifies the app that the keyboard was
// changed. This causes the keyboard layout to be reloaded from the OS.
pub fn ghostty_app_keyboard_changed(mut v App) {
	v.reload_keymap() or {
		log_err('error reloading keyboard map err=${err}')
		return
	}
}

// ghostty_app_open_config opens the configuration.
pub fn ghostty_app_open_config(mut v App) {
	v.perform_action(Target(AppTarget{}), .open_config, ActionVoid{}) or {
		log_err('error reloading config err=${err}')
		return
	}
}

// ghostty_app_update_config updates the configuration to the provided
// config. This will propagate to all surfaces as well.
pub fn ghostty_app_update_config(mut v App, config &configpkg.Config) {
	v.core_app.update_config(v, config) or {
		log_err('error updating config err=${err}')
		return
	}
}

// ghostty_app_needs_confirm_quit returns true if the app needs to confirm
// quitting.
pub fn ghostty_app_needs_confirm_quit(v &App) bool {
	return v.core_app.needs_confirm_quit()
}

// ghostty_app_has_global_keybinds returns true if the app has global
// keybinds.
pub fn ghostty_app_has_global_keybinds(v &App) bool {
	return v.has_global_keybinds()
}

// ghostty_app_set_color_scheme updates the color scheme of the app.
pub fn ghostty_app_set_color_scheme(mut v App, scheme_raw int) {
	scheme := color_scheme_from_int(scheme_raw) or {
		log_warn('invalid color scheme to ghostty_app_set_color_scheme value=${scheme_raw}')
		return
	}

	v.core_app.color_scheme_event(v, scheme) or {
		log_err('error setting color scheme err=${err}')
		return
	}
}

// ghostty_surface_config_new returns initial surface options.
pub fn ghostty_surface_config_new() SurfaceOptions {
	return SurfaceOptions{}
}

// ghostty_surface_new creates a new surface as part of an app.
pub fn ghostty_surface_new(mut app App, opts &SurfaceOptions) ?&Surface {
	return surface_new_(mut app, opts) or {
		log_err('error initializing surface err=${err}')
		return none
	}
}

fn surface_new_(mut app App, opts &SurfaceOptions) !&Surface {
	return app.new_surface(*opts)!
}

// ghostty_surface_free frees a surface.
pub fn ghostty_surface_free(mut surface Surface) {
	unsafe {
		surface.app.close_surface(mut surface)
	}
}

// ghostty_surface_userdata returns the userdata associated with the surface.
pub fn ghostty_surface_userdata(surface &Surface) voidptr {
	return surface.userdata
}

// ghostty_surface_app returns the app associated with a surface.
pub fn ghostty_surface_app(surface &Surface) &App {
	return surface.app
}

// ghostty_surface_inherited_config returns the config to use for surfaces
// that inherit from this one.
pub fn ghostty_surface_inherited_config(surface &Surface, source NewSurfaceContext) SurfaceOptions {
	return surface.new_surface_options(source)
}

// ghostty_surface_update_config updates the configuration for only this
// surface.
pub fn ghostty_surface_update_config(mut surface Surface, config &configpkg.Config) {
	surface.core_surface.update_config(config) or {
		log_err('error updating config err=${err}')
		return
	}
}

// ghostty_surface_needs_confirm_quit returns true if the surface needs
// to confirm quitting.
pub fn ghostty_surface_needs_confirm_quit(surface &Surface) bool {
	return surface.core_surface.needs_confirm_quit()
}

// ghostty_surface_process_exited returns true if the surface process has
// exited.
pub fn ghostty_surface_process_exited(surface &Surface) bool {
	return surface.core_surface.child_exited
}

// ghostty_surface_has_selection returns true if the surface has a selection.
pub fn ghostty_surface_has_selection(surface &Surface) bool {
	return surface.core_surface.has_selection()
}

// ghostty_surface_read_selection reads the text covered by the user's
// active selection, if any. Returns true if a selection was read and
// populated into `result`, false otherwise. Same shape as
// ghostty_surface_read_text but sourced from the live selection.
pub fn ghostty_surface_read_selection(mut surface Surface, mut result CAPIText) bool {
	mut core := &surface.core_surface
	core.renderer_state_lock()
	defer {
		core.renderer_state_unlock()
	}

	// If we don't have a selection, do nothing.
	core_sel := core.active_selection() or { return false }

	return read_text_locked(mut surface, core_sel, mut result)
}

// ghostty_surface_read_text reads arbitrary text from the surface
// covered by `sel`. This is an expensive operation so callers should
// cache and throttle calls.
pub fn ghostty_surface_read_text(mut surface Surface, sel CAPISelection, mut result CAPIText) bool {
	mut core := &surface.core_surface
	core.renderer_state_lock()
	defer {
		core.renderer_state_unlock()
	}

	core_sel := core.resolve_selection(
		int(sel.tl.tag),
		int(sel.tl.coord_tag),
		sel.tl.x,
		sel.tl.y,
		int(sel.br.tag),
		int(sel.br.coord_tag),
		sel.br.x,
		sel.br.y,
		sel.rectangle,
	) or { return false }

	return read_text_locked(mut surface, core_sel, mut result)
}

// read_text_locked is the shared helper for ghostty_surface_read_selection
// and ghostty_surface_read_text. The renderer-state mutex must be held by
// the caller.
fn read_text_locked(mut surface Surface, core_sel voidptr, mut result CAPIText) bool {
	dumped := surface.core_surface.dump_text_locked(core_sel) or {
		log_warn('error reading text err=${err}')
		return false
	}

	// Default viewport metadata when the selection is fully off-screen.
	mut tl_px_x := f64(-1)
	mut tl_px_y := f64(-1)
	mut offset_start := u32(0)
	mut offset_len := u32(0)

	if vp := dumped.viewport {
		tl_px_x = vp.tl_px_x
		tl_px_y = vp.tl_px_y
		offset_start = vp.offset_start
		offset_len = vp.offset_len
	}

	result.tl_px_x = tl_px_x
	result.tl_px_y = tl_px_y
	result.offset_start = offset_start
	result.offset_len = offset_len
	result.text = dumped.text
	result.text_len = uint(dumped.text.len)
	return true
}

// ghostty_surface_free_text frees a text result.
pub fn ghostty_surface_free_text(mut text CAPIText) {
	text.deinit()
}

// ghostty_surface_refresh tells the surface that it needs to schedule a
// render.
pub fn ghostty_surface_refresh(mut surface Surface) {
	surface.refresh()
}

// ghostty_surface_draw tells the surface that it needs to draw NOW.
pub fn ghostty_surface_draw(mut surface Surface) {
	surface.draw()
}

// ghostty_surface_set_size updates the size of a surface. This will trigger
// resize notifications to the pty and the renderer.
pub fn ghostty_surface_set_size(mut surface Surface, w u32, h u32) {
	surface.update_size(w, h)
}

// ghostty_surface_size returns the size information a surface has.
pub fn ghostty_surface_size(surface &Surface) CAPISurfaceSize {
	grid_size := surface.core_surface.size.grid()
	return CAPISurfaceSize{
		columns: grid_size.columns
		rows: grid_size.rows
		width_px: surface.core_surface.size.screen.width
		height_px: surface.core_surface.size.screen.height
		cell_width_px: surface.core_surface.size.cell.width
		cell_height_px: surface.core_surface.size.cell.height
	}
}

// ghostty_surface_set_color_scheme updates the color scheme of the surface.
pub fn ghostty_surface_set_color_scheme(mut surface Surface, scheme_raw int) {
	scheme := color_scheme_from_int(scheme_raw) or {
		log_warn('invalid color scheme to ghostty_surface_set_color_scheme value=${scheme_raw}')
		return
	}
	surface.color_scheme_callback(scheme)
}

fn color_scheme_from_int(value int) ?ColorScheme {
	return match value {
		int(ColorScheme.light) { ColorScheme.light }
		int(ColorScheme.dark) { ColorScheme.dark }
		else { none }
	}
}

// ghostty_surface_set_content_scale updates the content scale of the surface.
pub fn ghostty_surface_set_content_scale(mut surface Surface, x f64, y f64) {
	surface.update_content_scale(x, y)
}

// ghostty_surface_set_focus updates the focused state of a surface.
pub fn ghostty_surface_set_focus(mut surface Surface, focused bool) {
	surface.focus_callback(focused)
}

// ghostty_surface_set_occlusion updates the occlusion state of a surface.
pub fn ghostty_surface_set_occlusion(mut surface Surface, visible bool) {
	surface.occlusion_callback(visible)
}

// ghostty_surface_key_translation_mods filters the mods if necessary.
// This handles settings such as `macos-option-as-alt`. The filtered mods
// should be used for key translation but should NOT be sent back via the
// `_key` function -- the original mods should be used for that.
pub fn ghostty_surface_key_translation_mods(surface &Surface, mods_raw int) int {
	mods := mods_from_int(mods_raw)
	// An explicit surface setting wins; otherwise use the active layout.
	option_as_alt := surface.core_surface.config.macos_option_as_alt or {
		surface.app.keyboard_layout().detect_option_as_alt()
	}
	result := mods.translation(option_as_alt)
	return mods_to_int(result)
}

// ghostty_surface_key sends a raw keypress to the surface.
pub fn ghostty_surface_key(mut surface Surface, event CAPIKeyEvent) bool {
	mut target := KeyTarget(SurfaceKeyTarget{ surface: surface })
	return surface.app.key_event(
		mut target,
		event.key_event(),
	) or {
		log_warn('error processing key event err=${err}')
		return false
	}
}

// ghostty_surface_key_is_binding returns true if the given key event would
// trigger a binding if it were sent to the surface right now.
pub fn ghostty_surface_key_is_binding(mut surface Surface, event CAPIKeyEvent) bool {
	return ghostty_surface_key_binding_flags(mut surface, event) != none
}

// ghostty_surface_key_binding_flags returns the C bitmask for a matching
// binding, preserving the optional out-parameter behavior of witty.h.
pub fn ghostty_surface_key_binding_flags(mut surface Surface, event CAPIKeyEvent) ?u32 {
	core_event := event.key_event().core() or {
		log_warn('error processing key event')
		return none
	}

	flags_raw := surface.core_surface.key_event_is_binding(&core_event) or { return none }
	flags := unsafe { &input.Flags(flags_raw) }
	return u32(flags.cval())
}

// ghostty_surface_text sends raw text to the terminal. This is treated
// like a paste so this isn't useful for sending escape sequences.
pub fn ghostty_surface_text(mut surface Surface, text string) {
	surface.text_callback(text)
}

// ghostty_surface_preedit sets the preedit text for the surface. This is
// used for IME composition.
pub fn ghostty_surface_preedit(mut surface Surface, text ?string) {
	surface.preedit_callback(text)
}

// ghostty_surface_mouse_captured returns true if the surface currently
// has mouse capturing enabled.
pub fn ghostty_surface_mouse_captured(surface &Surface) bool {
	return surface.core_surface.mouse_captured()
}

// ghostty_surface_mouse_button handles a mouse button event on the surface.
pub fn ghostty_surface_mouse_button(mut surface Surface, action input.MouseButtonState, button input.MouseButton, mods int) bool {
	return surface.mouse_button_callback(
		action,
		button,
		mods_from_int(mods),
	)
}

// ghostty_surface_mouse_pos updates the mouse position within the view.
pub fn ghostty_surface_mouse_pos(mut surface Surface, x f64, y f64, mods int) {
	surface.cursor_pos_callback(
		x,
		y,
		mods_from_int(mods),
	)
}

// ghostty_surface_mouse_scroll handles a mouse scroll event.
pub fn ghostty_surface_mouse_scroll(mut surface Surface, x f64, y f64, scroll_mods int) {
	surface.scroll_callback(
		x,
		y,
		input.scroll_mods_from_int(u8(scroll_mods)),
	)
}

// ghostty_surface_mouse_pressure handles a mouse pressure event.
pub fn ghostty_surface_mouse_pressure(mut surface Surface, stage_raw u32, pressure f64) {
	stage := match stage_raw {
		u32(input.PressureStage.none_) { input.PressureStage.none_ }
		u32(input.PressureStage.normal) { input.PressureStage.normal }
		u32(input.PressureStage.deep) { input.PressureStage.deep }
		else {
			log_warn('invalid mouse pressure stage value=${stage_raw}')
			return
		}
	}
	surface.mouse_pressure_callback(stage, pressure)
}

// ghostty_surface_ime_point returns the position for the IME overlay.
pub fn ghostty_surface_ime_point(surface &Surface, x &f64, y &f64, width &f64, height &f64) {
	pos := surface.core_surface.ime_point()
	unsafe {
		*x = pos.x
		*y = pos.y
		*width = pos.width
		*height = pos.height
	}
}

// ghostty_surface_request_close requests that the surface become closed.
pub fn ghostty_surface_request_close(mut surface Surface) {
	surface.core_surface.close()
}

// ghostty_surface_split requests that the surface split in the given
// direction.
pub fn ghostty_surface_split(mut surface Surface, direction SplitDirection) {
	surface.app.perform_action(
		Target(SurfaceTarget{ surface: voidptr(&surface.core_surface) }),
		.new_split,
		ActionValue(direction),
	) or {
		log_err('error creating new split err=${err}')
		return
	}
}

// ghostty_surface_split_focus focuses on the next split (if any).
pub fn ghostty_surface_split_focus(mut surface Surface, direction GotoSplit) {
	surface.app.perform_action(
		Target(SurfaceTarget{ surface: voidptr(&surface.core_surface) }),
		.goto_split,
		ActionValue(direction),
	) or {
		log_err('error focusing split err=${err}')
		return
	}
}

// ghostty_surface_split_resize resizes the current split by moving the
// split divider in the given direction. `amount` is a fractional value
// between 0 and 1 that specifies by how much the divider will move.
pub fn ghostty_surface_split_resize(mut surface Surface, direction ResizeSplitDirection, amount u16) {
	surface.app.perform_action(
		Target(SurfaceTarget{ surface: voidptr(&surface.core_surface) }),
		.resize_split,
		ActionValue(ResizeSplit{
				direction: direction
				amount: amount
			}),
	) or {
		log_err('error resizing split err=${err}')
		return
	}
}

// ghostty_surface_split_equalize equalizes the size of all splits in the
// current window.
pub fn ghostty_surface_split_equalize(mut surface Surface) {
	surface.app.perform_action(
		Target(SurfaceTarget{ surface: voidptr(&surface.core_surface) }),
		.equalize_splits,
		ActionVoid{},
	) or {
		log_err('error equalizing splits err=${err}')
		return
	}
}

// ghostty_surface_binding_action invokes a binding action on the surface.
pub fn ghostty_surface_binding_action(mut surface Surface, action_str string) bool {
	action := input.Action.parse(action_str) or {
		log_err('error parsing binding action action=${action_str} err=${err}')
		return false
	}

	return surface.core_surface.perform_binding_action(action) or {
		log_err('error performing binding action action=${action_str} err=${err}')
		return false
	}
}

// ghostty_surface_complete_clipboard_request completes a clipboard read
// request started via the read callback. This can only be called once
// for a given request.
pub fn ghostty_surface_complete_clipboard_request(mut surface Surface, str string, state &ClipboardRequest, confirmed bool) {
	surface.complete_clipboard_request(str, state, confirmed)
}

// ghostty_surface_inspector returns or creates the inspector for a surface.
pub fn ghostty_surface_inspector(mut surface Surface) ?&TerminalInspector {
	return surface.init_inspector() or {
		log_err('error initializing inspector err=${err}')
		return none
	}
}

// ghostty_inspector_free frees the inspector for a surface.
pub fn ghostty_inspector_free(mut surface Surface) {
	surface.free_inspector()
}

// ghostty_inspector_set_size updates the inspector display size.
pub fn ghostty_inspector_set_size(mut insp TerminalInspector, w u32, h u32) {
	insp.update_size(w, h)
}

// ghostty_inspector_set_content_scale updates the inspector content scale.
pub fn ghostty_inspector_set_content_scale(mut insp TerminalInspector, x f64, y f64) {
	insp.update_content_scale(x, y)
}

// ghostty_inspector_mouse_button handles a mouse button event in the inspector.
pub fn ghostty_inspector_mouse_button(mut insp TerminalInspector, action input.MouseButtonState, button input.MouseButton, mods int) {
	insp.mouse_button_callback(
		action,
		button,
		mods_from_int(mods),
	)
}

// ghostty_inspector_mouse_pos updates the mouse position in the inspector.
pub fn ghostty_inspector_mouse_pos(mut insp TerminalInspector, x f64, y f64) {
	insp.cursor_pos_callback(x, y)
}

// ghostty_inspector_mouse_scroll handles a scroll event in the inspector.
pub fn ghostty_inspector_mouse_scroll(mut insp TerminalInspector, x f64, y f64, scroll_mods int) {
	insp.scroll_callback(
		x,
		y,
		input.scroll_mods_from_int(u8(scroll_mods)),
	)
}

// ghostty_inspector_key handles a key event in the inspector.
pub fn ghostty_inspector_key(mut insp TerminalInspector, action input.KeyAction, key input.Key, c_mods int) {
	insp.key_callback(
		action,
		key,
		mods_from_int(c_mods),
	) or {
		log_err('error processing key event err=${err}')
		return
	}
}

// ghostty_inspector_text sends text to the inspector.
pub fn ghostty_inspector_text(mut insp TerminalInspector, text string) {
	insp.text_callback(text)
}

// ghostty_inspector_set_focus updates the inspector focus state.
pub fn ghostty_inspector_set_focus(mut insp TerminalInspector, focused bool) {
	insp.focus_callback(focused)
}

// ghostty_set_window_background_blur sets the window background blur on
// macOS to the desired value. This uses an undocumented, non-public API
// because this is what every terminal appears to use, including
// Terminal.app.
pub fn ghostty_set_window_background_blur(app &App, window voidptr) {
	// Blur only has a visible effect when the window itself is translucent.
	if app.config.background_opacity >= 1.0 {
		return
	}
	set_window_background_blur(window, app.config.background_blur.cval())
}

// -----------------------------------------------------------------------
// Darwin-specific CAPI functions
// -----------------------------------------------------------------------

// ghostty_surface_set_display_id sets the display ID for macOS rendering.
pub fn ghostty_surface_set_display_id(mut surface Surface, display_id u32) {
	surface.core_surface.set_display_id(display_id)
}

// ghostty_surface_quicklook_font returns a CTFontRef that should be used
// for quicklook highlighted text. This is always the primary font in use
// regardless of the selected text.
pub fn ghostty_surface_quicklook_font(surface &Surface) voidptr {
	return surface.core_surface.quicklook_font()
}

// ghostty_surface_quicklook_word returns the selected word for quicklook.
// This will populate the buffer with the word under the cursor and the
// selection info so that quicklook can be rendered.
//
// This does not modify the selection active on the surface (if any).
pub fn ghostty_surface_quicklook_word(mut surface Surface, mut result CAPIText) bool {
	mut core := &surface.core_surface
	core.renderer_state_lock()
	defer {
		core.renderer_state_unlock()
	}

	pos := surface.get_cursor_pos() or { return false }
	selection := core.quicklook_selection(pos.x, pos.y) or { return false }
	return read_text_locked(mut surface, selection, mut result)
}

$if macos || ios {
// ghostty_inspector_metal_init initializes the inspector Metal backend.
pub fn ghostty_inspector_metal_init(mut insp TerminalInspector, device voidptr) bool {
	return insp.init_metal(device)
}

// ghostty_inspector_metal_render renders the inspector using Metal.
pub fn ghostty_inspector_metal_render(mut insp TerminalInspector, command_buffer voidptr, descriptor voidptr) {
	insp.render_metal(command_buffer, descriptor) or {
		log_err('error rendering inspector err=${err}')
		return
	}
}

// ghostty_inspector_metal_shutdown shuts down the inspector Metal backend.
pub fn ghostty_inspector_metal_shutdown(mut insp TerminalInspector) {
	if insp.metal_active {
		insp.context.metal_shutdown()
		insp.metal_active = false
	}
}

}
