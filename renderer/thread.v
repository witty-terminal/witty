module renderer

// --- Original Ghostty Comments Start: src/renderer/Thread.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/renderer/Thread.zig
//
// Represents the renderer thread logic. The renderer thread is able to
// be woken up to render.
// Whether calls to `drawFrame` must be done from the app thread.
//
// If this is `true` then we send a `redraw_surface` message to the apprt
// whenever we need to draw instead of calling `drawFrame` directly.
// The type used for sending messages to the IO thread. For now this is
// hardcoded with a capacity. We can make this a comptime parameter in
// the future if we want it configurable.
// Allocator used for some state
// The main event loop for the application. The user data of this loop
// is always the allocator used to create the loop. This is a convenience
// so that users of the loop always have an allocator.
// This can be used to wake up the renderer and force a render safely from
// any thread.
// This can be used to stop the renderer on the next loop iteration.
// The timer used for rendering
// The timer used for draw calls. Draw calls don't update from the
// terminal state so they're much cheaper. They're used for animation
// and are paused when the terminal is not focused.
// This async is used to force a draw immediately. This does not
// coalesce like the wakeup does.
// The timer used for cursor blinking
// The surface we're rendering to.
// The underlying renderer implementation.
// Pointer to the shared state that is used to generate the final render.
// The mailbox that can be used to send this thread messages. Note
// this is a blocking queue so if it is full you will get errors (or block).
// Mailbox to send messages to the app thread
// Configuration we need derived from the main config.
// This is true when a blinking cursor should be visible and false
// when it should not be visible. This is toggled on a timer by the
// thread automatically.
// This is true when the inspector is active.
// This is true when the view is visible. This is used to determine
// if we should be rendering or not.
// This is true when the view is focused. This defaults to true
// and it is up to the apprt to set the correct value.
// Initialize the thread. This does not START the thread. This only sets
// up all the internal state necessary prior to starting the thread. It
// is up to the caller to start the thread with the threadMain entrypoint.
// Create our event loop.
// This async handle is used to "wake up" the renderer and force a render.
// This async handle is used to stop the loop and force the thread to end.
// The primary timer for rendering.
// Draw timer, see comments.
// Draw now async, see comments.
// Setup a timer for blinking the cursor
// The mailbox for messaging this thread
// Clean up the thread. This is only safe to call once the thread
// completes executing; the caller must join prior to this.
// Nothing can possibly access the mailbox anymore, destroy it.
// The main entrypoint for the thread.
// Call child function so we can use errors...
// In the future, we should expose this on the thread struct.
// Right now, on Darwin, `std.Thread.setName` can only name the current
// thread, and we have no way to get the current thread from within it,
// so instead we use this code to name the thread instead.
// Setup our crash metadata
// Setup our thread QoS
// Run our loop start/end callbacks if the renderer cares.
// Run our thread start/end callbacks. This is important because some
// renderers have to do per-thread setup. For example, OpenGL has to set
// some thread-local state since that is how it works.
// Start the async handlers
// Send an initial wakeup message so that we render right away.
// Start blinking the cursor.
// Start the draw timer
// Run
// Thread QoS classes are only relevant on macOS.
// If we aren't visible (our view is fully occluded) then we
// always drop our rendering priority down because it's just
// mostly wasted work.
//
// The renderer itself should be doing this as well (for example
// Metal will stop our DisplayLink) but this also helps with
// general forced updates and CPU usage i.e. a rebuild cells call.
// If we're not focused, but we're visible, then we set a higher
// than default priority because framerates still matter but it isn't
// as important as when we're focused.
// We are focused and visible, we are the definition of user interactive.
// If our renderer supports animations and has them, then we
// always have a draw timer.
// If our config says to always animate, we do so.
// Always animate
// Only when focused
// Never animate
// We're skipping the draw timer. Stop it on the next iteration.
// Set our active state so it knows we're running. We set this before
// even checking the active state in case we have a pending shutdown.
// If our draw timer is already active, then we don't have to do anything.
// Start the timer which loops
// Drain the mailbox.
// There's probably a more elegant way to do this...
//
// This is effectively an @autoreleasepool{} block, which we need in
// order to ensure that autoreleased objects are properly released.
// If our state didn't change we do nothing.
// Set our visible state
// Visibility affects our QoS class
// If we became visible then we immediately trigger a draw.
// We don't need to update frame data because that should
// still be happening.
// Notify the renderer so it can update any state.
// Note that we're explicitly today not stopping any
// cursor timers, draw timers, etc. These things have very
// little resource cost and properly maintaining their active
// state across different transitions is going to be bug-prone,
// so its easier to just let them keep firing and have them
// check the visible state themselves to control their behavior.
// If our state didn't change we do nothing.
// Set our state
// Focus affects our QoS class
// Set it on the renderer
// We always resync our draw timer (may disable it)
// If we're not focused, then we stop the cursor blink
// If we're focused, we immediately show the cursor again
// and then restart the timer.
// Stop and start the draw timer to capture the new
// hasAnimations value.
// Note we don't free the new value because we expect our
// allocators to match.
// Note we don't free the new value because we expect our
// allocators to match.
// Trigger a draw. This will not update frame data or anything, it will
// just trigger a draw/paint.
// If we're invisible, we do not draw.
// If the renderer is managing a vsync on its own, we only draw
// when we're forced to via `now`.
// When we wake up, we check the mailbox. Mailbox producers should
// wake up our thread after publishing.
// Render immediately
// The below is not used anymore but if we ever want to introduce
// a configuration to introduce a delay to coalesce renders, we can
// use this.
//
// // If the timer is already active then we don't have to do anything.
// if (t.render_c.state() == .active) return .rearm;
//
// // Timer is not active, let's start it
// t.render_h.run(
//     &t.loop,
//     &t.render_c,
//     10,
//     Thread,
//     t,
//     renderCallback,
// );
// Draw immediately
// This shouldn't happen so we log it.
// Draw
// Only continue if we're still active
// This shouldn't happen so we log it.
// Update our frame data
// Draw
// This is sent when our timer is canceled. That's fine.
// This shouldn't happen so we log it.
// This makes it easier to work across platforms where different platforms
// support different sets of errors, so we just unify it.
// fn prepFrameCallback(h: *libuv.Prepare) void {
//     _ = h;
//
//     tracy.frameMark();
// }
// Returns the interval for the blinking cursor in milliseconds.
// If we're running under Valgrind, the cursor blink adds enough
// churn that it makes some stalls annoying unless you're on a
// super powerful computer, so we delay it.
//
// This is a hack, we should change some of our cursor timer
// logic to be more efficient:
// https://github.com/ghostty-org/ghostty/issues/8003
//
// --- Original Ghostty Comments End: src/renderer/Thread.zig
import configpkg
import crash
import datastruct
import internal_os
import log
import macos
import time
import xev

const draw_interval = 8 // 120 FPS
const cursor_blink_interval_ms = 600
const renderer_mailbox_capacity = 64

// The type used for sending messages to the IO thread. For now this is
// hardcoded with a capacity. We can make this a comptime parameter in
// the future if we want it configurable.
pub type Mailbox = datastruct.BlockingQueue[RendererMessage]

// create allocates the mailbox with its fixed source capacity. V generics have
// no integer parameters, so the capacity is supplied here instead of the type.
pub fn Mailbox.create() !&datastruct.BlockingQueue[RendererMessage] {
	return datastruct.BlockingQueue.create[RendererMessage](renderer_mailbox_capacity)!
}

// ThreadDerivedConfig holds configuration derived from the main config
// that is needed by the renderer thread.
pub struct ThreadDerivedConfig {
pub mut:
	custom_shader_animation configpkg.CustomShaderAnimation
}

pub fn ThreadDerivedConfig.init(config &configpkg.Config) ThreadDerivedConfig {
	return ThreadDerivedConfig{
		custom_shader_animation: config.custom_shader_animation
	}
}

// Flags for the renderer thread state. Ghostty packs these four booleans into
// one byte in declaration order.
pub struct ThreadFlags {
mut:
	value u8 = 0b1100
}

fn (self ThreadFlags) cursor_blink_visible() bool {
	return self.value & 0b0001 != 0
}

fn (mut self ThreadFlags) set_cursor_blink_visible(value bool) {
	self.set(0b0001, value)
}

fn (mut self ThreadFlags) toggle_cursor_blink_visible() {
	self.value ^= 0b0001
}

fn (self ThreadFlags) has_inspector() bool {
	return self.value & 0b0010 != 0
}

fn (mut self ThreadFlags) set_has_inspector(value bool) {
	self.set(0b0010, value)
}

fn (self ThreadFlags) visible() bool {
	return self.value & 0b0100 != 0
}

fn (mut self ThreadFlags) set_visible(value bool) {
	self.set(0b0100, value)
}

fn (self ThreadFlags) focused() bool {
	return self.value & 0b1000 != 0
}

fn (mut self ThreadFlags) set_focused(value bool) {
	self.set(0b1000, value)
}

fn (mut self ThreadFlags) set(mask u8, enabled bool) {
	if enabled {
		self.value |= mask
	} else {
		self.value &= ~mask
	}
}

// RendererThread represents the renderer thread logic. The renderer thread
// is able to be woken up to render.
pub struct RendererThread {
pub mut:
	// The main event loop for the application. The user data of this loop
	// is always the allocator used to create the loop. This is a convenience
	// so that users of the loop always have an allocator.
	loop xev.Loop

	// This can be used to wake up the renderer and force a render safely from
	// any thread.
	wakeup   xev.Async
	wakeup_c xev.Completion

	// This can be used to stop the renderer on the next loop iteration.
	stop   xev.Async
	stop_c xev.Completion

	// The timer used for rebuilding a frame when a Kitty animation advances.
	render_h        xev.Timer
	render_c        xev.Completion
	render_c_cancel xev.Completion
	render_deadline u64

	// The timer used for draw calls. Draw calls don't update from the
	// terminal state so they're much cheaper. They're used for animation
	// and follow the configured animation policy and terminal visibility.
	draw_h      xev.Timer
	draw_c      xev.Completion
	draw_active bool

	// This async is used to force a draw immediately. This does not
	// coalesce like the wakeup does.
	draw_now   xev.Async
	draw_now_c xev.Completion

	// The timer used for cursor blinking
	cursor_h        xev.Timer
	cursor_c        xev.Completion
	cursor_c_cancel xev.Completion

	// The underlying renderer implementation.
	renderer &Renderer = unsafe { nil }

	// Pointer to the shared state that is used to generate the final render.
	state &RenderState = unsafe { nil }

	// The mailbox that can be used to send this thread messages. Note
	// this is a blocking queue so if it is full you will get errors (or block).
	mailbox &datastruct.BlockingQueue[RendererMessage] = unsafe { nil }

	// Mailbox to send messages to the app thread. GTK requires GPU work on the
	// application thread; this callback is the translated App.Mailbox
	// redraw_surface push used there (must_draw_from_app_thread).
	app_redraw           Wakeup
	draw_from_app_thread bool

	// Configuration we need derived from the main config.
	config ThreadDerivedConfig

	// Thread state flags.
	flags ThreadFlags
}

// Initialize the thread. This does not START the thread. This only sets
// up all the internal state necessary prior to starting the thread. It
// is up to the caller to start the thread with the threadMain entrypoint.
pub fn RendererThread.init(config &configpkg.Config, renderer_impl &Renderer, state &RenderState, app_redraw Wakeup) !RendererThread {
	// Zig's errdefers are emulated by reached defers that run until init succeeds.
	mut init_ok := false

	// Create our event loop.
	mut loop := xev.Loop.init(xev.Options{})!
	defer {
		if !init_ok {
			loop.deinit()
		}
	}

	// This async handle is used to "wake up" the renderer and force a render.
	mut wakeup_h := xev.Async.init()!
	defer {
		if !init_ok {
			wakeup_h.deinit()
		}
	}

	// This async handle is used to stop the loop and force the thread to end.
	mut stop_h := xev.Async.init()!
	defer {
		if !init_ok {
			stop_h.deinit()
		}
	}

	// The primary timer for rendering.
	render_h := xev.Timer.init()!
	defer {
		if !init_ok {
			render_h.deinit()
		}
	}

	// Draw timer, see comments.
	draw_h := xev.Timer.init()!
	defer {
		if !init_ok {
			draw_h.deinit()
		}
	}

	// Draw now async, see comments.
	mut draw_now := xev.Async.init()!
	defer {
		if !init_ok {
			draw_now.deinit()
		}
	}

	// Setup a timer for blinking the cursor
	cursor_timer := xev.Timer.init()!
	defer {
		if !init_ok {
			cursor_timer.deinit()
		}
	}

	// The mailbox for messaging this thread
	mut mailbox := Mailbox.create()!
	defer {
		if !init_ok {
			mailbox.destroy()
		}
	}

	mut result := RendererThread{
		config:     ThreadDerivedConfig.init(config)
		loop:       loop
		wakeup:     wakeup_h
		stop:       stop_h
		render_h:   render_h
		draw_h:     draw_h
		draw_now:   draw_now
		cursor_h:   cursor_timer
		renderer:   unsafe { renderer_impl }
		state:      unsafe { state }
		mailbox:    mailbox
		app_redraw: app_redraw
	}
	$if linux {
		result.draw_from_app_thread = true
	}
	init_ok = true
	return result
}

// Release the font grid references still held by undelivered mailbox messages.
//
// A font grid handoff transfers ownership of the old grid's reference to this
// thread, which must accept the new grid and dereference the old one. The
// surface has already swapped to the new key by the time it queues the
// message, so if the thread stopped before draining it, nothing else holds the
// old grid's reference and the app's grid set never reaches zero.
fn (mut self RendererThread) release_pending_font_grids() {
	if self.mailbox == unsafe { nil } {
		return
	}
	for {
		msg := self.mailbox.pop() or { break }
		if msg is FontGridMessage {
			if msg.set != unsafe { nil } {
				mut set := unsafe { msg.set }
				set.deref(msg.old_key)
			}
		}
	}
}

// Clean up the thread. This is only safe to call once the thread
// completes executing; the caller must join prior to this.
pub fn (mut self RendererThread) deinit() {
	self.stop.deinit()
	self.wakeup.deinit()
	self.render_h.deinit()
	self.draw_h.deinit()
	self.draw_now.deinit()
	self.cursor_h.deinit()
	self.loop.deinit()

	// Nothing can possibly access the mailbox anymore, so hand back anything
	// it still owns before destroying it.
	self.release_pending_font_grids()
	unsafe {
		self.mailbox.destroy()
	}
}

// The main entrypoint for the thread.
pub fn (mut self RendererThread) thread_main() {
	// Call child function so we can use errors...
	self.thread_main_() or {
		// In the future, we should expose this on the thread struct.
		log.warn('error in renderer err=${err}')
	}
}

fn (mut self RendererThread) thread_main_() ! {
	defer {
		log.debug('renderer thread exited')
	}
	// Right now, on Darwin, `std.Thread.setName` can only name the current
	// thread, and we have no way to get the current thread from within it,
	// so instead we use this code to name the thread instead.
	$if macos {
		internal_os.set_thread_name('renderer')
	}

	// Setup our crash metadata
	crash.set_thread_state(crash.ThreadState{
		kind:    .renderer
		surface: self.renderer.surface_mailbox.user_data
	})
	defer {
		crash.clear_thread_state()
	}

	// Setup our thread QoS
	self.set_qos_class()

	// Run our loop start/end callbacks if the renderer cares.
	self.renderer.loop_enter(self)!
	defer {
		self.renderer.loop_exit()
	}

	// Run our thread start/end callbacks. This is important because some
	// renderers have to do per-thread setup. For example, OpenGL has to set
	// some thread-local state since that is how it works.
	self.renderer.thread_enter()!
	defer {
		self.renderer.thread_exit()
	}

	// Start the async handlers
	self.wakeup.wait(mut self.loop, &self.wakeup_c, self, renderer_thread_wakeup_callback)
	self.stop.wait(mut self.loop, &self.stop_c, self, renderer_thread_stop_callback)
	self.draw_now.wait(mut self.loop, &self.draw_now_c, self, renderer_thread_draw_now_callback)

	// Send an initial wakeup message so that we render right away.
	self.wakeup.notify()!

	// Start blinking the cursor.
	self.cursor_h.run(mut self.loop, &self.cursor_c, cursor_blink_interval(), self,
		renderer_thread_cursor_timer_callback)

	// Start the draw timer
	self.sync_draw_timer()

	// Run
	log.debug('starting renderer thread')
	defer {
		log.debug('starting renderer thread shutdown')
	}
	self.loop.run(.until_done)!
}

fn (self &RendererThread) set_qos_class() {
	// Thread QoS classes are only relevant on macOS.
	$if macos {
		class := if !self.flags.visible() {
			// If we aren't visible (our view is fully occluded) then we
			// always drop our rendering priority down because it's just
			// mostly wasted work.
			//
			// The renderer itself should be doing this as well (for example
			// Metal will stop our DisplayLink) but this also helps with
			// general forced updates and CPU usage i.e. a rebuild cells call.
			internal_os.QosClass.utility
		} else if !self.flags.focused() {
			// If we're not focused, but we're visible, then we set a higher
			// than default priority because framerates still matter but it isn't
			// as important as when we're focused.
			internal_os.QosClass.user_initiated
		} else {
			// We are focused and visible, we are the definition of user interactive.
			internal_os.QosClass.user_interactive
		}

		internal_os.set_qos_class(class) or {
			log.warn('error setting QoS class err=${err}')
			return
		}
		log.debug('thread QoS class set class=${class}')
	}
}

fn (mut self RendererThread) should_animate() bool {
	return self.flags.visible()
		&& shader_animation_enabled(self.config.custom_shader_animation, self.flags.focused())
		&& self.renderer.has_shader_animation_source()
}

fn (mut self RendererThread) sync_draw_timer() {
	self.draw_active = self.should_animate()
	if !self.draw_active || self.draw_c.state() == .active {
		return
	}

	// Start the timer which loops
	self.draw_h.run(mut self.loop, &self.draw_c, draw_interval, self, renderer_thread_draw_callback)
}

// Drain the mailbox.
fn (mut self RendererThread) drain_mailbox() ! {
	// There's probably a more elegant way to do this...
	//
	// This is effectively an @autoreleasepool{} block, which we need in
	// order to ensure that autoreleased objects are properly released.
	mut pool := ?AutoreleasePool(none)
	$if macos || ios {
		pool = macos.AutoreleasePool.init()
	}
	defer {
		$if macos || ios {
			if mut active_pool := pool {
				active_pool.deinit()
			}
		}
	}

	for {
		msg := self.mailbox.pop() or { break }
		log.debug('mailbox message=${msg.type_name()}')
		match msg {
			CrashMessage {
				panic('crash request, crashing intentionally')
			}
			VisibleMessage {
				// If our state didn't change we do nothing.
				if self.flags.visible() != msg.visible {
					// Set our visible state
					self.flags.set_visible(msg.visible)

					// Visibility affects our QoS class
					self.set_qos_class()

					// If we became visible then we immediately trigger a draw.
					// We don't need to update frame data because that should
					// still be happening.
					if msg.visible {
						self.draw_frame(false)
					}

					// Notify the renderer so it can update any state.
					self.renderer.set_visible(msg.visible)
					self.sync_draw_timer()
				}
			}
			FocusMessage {
				// If our state didn't change we do nothing.
				if self.flags.focused() != msg.focused {
					// Set our state
					self.flags.set_focused(msg.focused)

					// Focus affects our QoS class
					self.set_qos_class()

					// Set it on the renderer
					self.renderer.set_focus(msg.focused)!

					// We always resync our draw timer (may disable it)
					self.sync_draw_timer()

					if !msg.focused {
						// If we're not focused, then we stop the cursor blink
						if self.cursor_c.state() == .active && self.cursor_c_cancel.state() == .dead {
							self.cursor_h.cancel(mut self.loop, &self.cursor_c, &self.cursor_c_cancel,
								unsafe { nil }, renderer_thread_cursor_cancel_callback)
						}
					} else {
						// If we're focused, we immediately show the cursor again
						// and then restart the timer.
						if self.cursor_c.state() != .active {
							self.flags.set_cursor_blink_visible(true)
							self.cursor_h.run(mut self.loop, &self.cursor_c, cursor_blink_interval(),
								self, renderer_thread_cursor_timer_callback)
						}
					}
				}
			}
			ResetCursorBlinkMessage {
				self.flags.set_cursor_blink_visible(true)
				if self.cursor_c.state() == .active {
					self.cursor_h.reset(mut self.loop, &self.cursor_c, &self.cursor_c_cancel,
						cursor_blink_interval(), self, renderer_thread_cursor_timer_callback)
				}
			}
			FontGridMessage {
				self.renderer.set_font_grid(msg.grid)
				mut set := unsafe { msg.set }
				set.deref(msg.old_key)
			}
			ResizeMessage {
				self.renderer.set_screen_size(msg.size)
			}
			ChangeConfigMessage {
				self.change_config(msg.thread_config)!
				self.renderer.change_config(msg.renderer_config)!

				// Stop and start the draw timer to capture the new
				// hasAnimations value.
				self.sync_draw_timer()
			}
			SearchViewportMatchesMessage {
				// Note we don't free the new value because we expect our
				// allocators to match.
				for mut old in self.renderer.search_matches {
					old.deinit()
				}
				self.renderer.search_matches = msg.matches
				self.renderer.search_matches_dirty = true
			}
			SearchSelectedMatchMessage {
				// Note we don't free the new value because we expect our
				// allocators to match.
				if mut old := self.renderer.search_selected_match {
					old.deinit()
				}
				self.renderer.search_selected_match = msg.match_
				self.renderer.search_matches_dirty = true
			}
			InspectorMessage {
				self.flags.set_has_inspector(msg.active)
			}
			MacosDisplayIdMessage {
				self.renderer.set_macos_display_id(msg.display_id)!
			}
		}
	}
}

fn (mut self RendererThread) change_config(config &ThreadDerivedConfig) ! {
	self.config = *config
}

// Trigger a draw. This will not update frame data or anything, it will
// just trigger a draw/paint.
fn (mut self RendererThread) draw_frame(now bool) {
	// If we're invisible, we do not draw.
	if !self.flags.visible() {
		return
	}

	// If the renderer is managing a vsync on its own, we only draw
	// when we're forced to via `now`.
	if !now && self.renderer.has_vsync() {
		return
	}

	if self.draw_from_app_thread {
		self.app_redraw.notify() or {}
	} else {
		self.renderer.draw_frame(false) or { log.warn('error drawing err=${err}') }
	}
}

fn renderer_thread_wakeup_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if err := r {
		log.error('error in wakeup err=${err}')
		return .rearm
	}

	mut t := unsafe { &RendererThread(self_) }

	// When we wake up, we check the mailbox. Mailbox producers should
	// wake up our thread after publishing.
	t.drain_mailbox() or { log.error('error draining mailbox err=${err}') }

	// Render immediately
	_ = renderer_thread_render_callback(t, unsafe { nil }, unsafe { nil }, none)
	return .rearm
}

fn renderer_thread_draw_now_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if err := r {
		log.error('error in draw now err=${err}')
		return .rearm
	}

	// Draw immediately
	mut t := unsafe { &RendererThread(self_) }
	t.draw_frame(true)

	return .rearm
}

fn renderer_thread_draw_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if _ := r {
		panic('unreachable')
	}
	if self_ == unsafe { nil } {
		// This shouldn't happen so we log it.
		log.warn('render callback fired without data set')
		return .disarm
	}
	mut t := unsafe { &RendererThread(self_) }

	// Creating the pipelines may have failed since the previous tick.
	if !t.draw_active || !t.should_animate() {
		t.draw_active = false
		return .disarm
	}
	t.draw_frame(false)
	t.draw_h.run(mut t.loop, &t.draw_c, draw_interval, t, renderer_thread_draw_callback)

	return .disarm
}

fn renderer_thread_render_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if _ := r {
		panic('unreachable')
	}
	if self_ == unsafe { nil } {
		// This shouldn't happen so we log it.
		log.warn('render callback fired without data set')
		return .disarm
	}
	mut t := unsafe { &RendererThread(self_) }

	// Update our frame data
	t.renderer.update_frame(t.state, t.flags.cursor_blink_visible()) or {
		log.warn('error rendering err=${err}')
	}
	t.schedule_kitty_animation()

	// Draw
	t.draw_frame(false)

	return .disarm
}

fn (mut t RendererThread) schedule_kitty_animation() {
	if !t.flags.visible() {
		return
	}
	deadline := t.renderer.kitty_animation_deadline or { return }
	now := time.sys_mono_now() / u64(time.millisecond)
	delay := if deadline > now { deadline - now } else { u64(1) }
	if t.render_deadline != 0 && t.render_c.state() == .active {
		if t.render_deadline <= deadline {
			return
		}
		t.render_h.reset(mut t.loop, &t.render_c, &t.render_c_cancel, delay, t,
			renderer_thread_animation_callback)
	} else {
		t.render_h.run(mut t.loop, &t.render_c, delay, t, renderer_thread_animation_callback)
	}
	t.render_deadline = deadline
}

fn renderer_thread_animation_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if r != none || self_ == unsafe { nil } {
		return .disarm
	}
	mut t := unsafe { &RendererThread(self_) }
	t.render_deadline = 0
	if t.flags.visible() && t.renderer.kitty_animation_deadline != none {
		_ = renderer_thread_render_callback(t, unsafe { nil }, unsafe { nil }, none)
	}
	return .disarm
}

fn renderer_thread_cursor_timer_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if err := r {
		match err {
			// This is sent when our timer is canceled. That's fine.
			.canceled {
				return .disarm
			}
			else {
				log.warn('error in cursor timer callback err=${err}')
				panic('unreachable')
			}
		}
	}

	if self_ == unsafe { nil } {
		// This shouldn't happen so we log it.
		log.warn('render callback fired without data set')
		return .disarm
	}
	mut t := unsafe { &RendererThread(self_) }

	t.flags.toggle_cursor_blink_visible()
	t.wakeup.notify() or {}

	t.cursor_h.run(mut t.loop, &t.cursor_c, cursor_blink_interval(), t, renderer_thread_cursor_timer_callback)
	return .disarm
}

fn renderer_thread_cursor_cancel_callback(_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	// This makes it easier to work across platforms where different platforms
	// support different sets of errors, so we just unify it.
	if err := r {
		match err {
			.canceled {} // success
			.not_found {} // completed before it could cancel
			else {
				log.warn('error in cursor cancel callback err=${err}')
				panic('unreachable')
			}
		}
	}

	return .disarm
}

// fn prepFrameCallback(h: *libuv.Prepare) void {
//     _ = h;
//
//     tracy.frameMark();
// }

fn renderer_thread_stop_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if _ := r {
		panic('unreachable')
	}
	mut t := unsafe { &RendererThread(self_) }
	t.loop.stop()
	return .disarm
}

// Returns the interval for the blinking cursor in milliseconds.
fn cursor_blink_interval() u64 {
	if internal_os.running_on_valgrind() > 0 {
		// If we're running under Valgrind, the cursor blink adds enough
		// churn that it makes some stalls annoying unless you're on a
		// super powerful computer, so we delay it.
		//
		// This is a hack, we should change some of our cursor timer
		// logic to be more efficient:
		// https://github.com/ghostty-org/ghostty/issues/8003
		return cursor_blink_interval_ms * 5
	}

	return cursor_blink_interval_ms
}
