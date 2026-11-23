module termio

// --- Original Ghostty Comments Start: src/termio/Termio.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/termio/Termio.zig
//
// Primary terminal IO ("termio") state. This maintains the terminal state,
// pty, subprocess, etc. This is flexible enough to be used in environments
// that don't have a pty and simply provides the input/output using raw
// bytes.
// Mutex state argument for queueMessage.
// Allocator
// This is the implementation responsible for io.
// The derived configuration for this termio implementation.
// The terminal emulator internal state. This is the abstract "terminal"
// that manages input, grid updating, etc. and is renderer-agnostic. It
// just stores internal state about a grid.
// The shared render state
// A handle to wake up the renderer. This hints to the renderer that that
// a repaint should happen.
// The mailbox for notifying the renderer of things.
// The mailbox for communicating with the surface.
// The cached size info
// The mailbox implementation to use.
// The stream parser. This parses the stream of escape codes and so on
// from the child process and calls callbacks in the stream handler.
// Last time the cursor was reset. This is used to prevent message
// flooding with cursor resets.
// State we have for thread enter. This may be null if we don't need
// to keep track of any state or if its already been freed.
// The state we need to keep around only until we enter the IO
// thread. Then we can throw it all away.
// Initial input to send to the subprocess after starting. This
// memory is freed once the subprocess start is attempted, even
// if it fails, because Exec only starts once.
// If we have no input then we have no thread enter state
// Create our arena allocator
// Allocate our ThreadEnterState
// Copy the input from the config
// Return the initialized state
// Prepare the inputs for use. Allocations happen on the arena.
// The configuration for this IO that is derived from the main
// configuration. This must be exported so that we don't need to
// pass around Config pointers which makes memory management a pain.
// This has to be last so that we copy AFTER the arena allocations
// above happen (Zig assigns in order).
// Initialize the termio state.
//
// This will also start the child process if the termio is configured
// to run a child process.
// The default terminal modes based on our config.
// Setup our initial grapheme cluster support if enabled. We use a
// switch to ensure we get a compiler error if more cases are added.
// Set default cursor blink settings
// Create our terminal
// Set the image size limits
// Set our default cursor style
// Setup our terminal size in pixels for certain requests.
// Setup our backend.
// Create our stream handler. This points to memory in self so it
// isn't safe to use until self.* is set.
// Clear any StreamHandler state
// Clear any initial state if we have it
// Always free our thread enter state when we're done.
// If we have thread enter state then we're going to validate
// and set that all up now so that we can error before we actually
// start the command and pty.
// Setup our backend
// If we have inputs, then queue them all up.
// Send a message to the the mailbox. Depending on the mailbox type in
// use this may process now or it may just enqueue and process later.
//
// This will also notify the mailbox thread to process the message. If
// you're sending a lot of messages, it may be more efficient to use
// the mailbox directly and then call notify separately.
// Queue a write directly to the pty.
//
// If you're using termio.Thread, this must ONLY be called from the
// mailbox thread. If you're not on the thread, use queueMessage with
// mailbox messages instead.
//
// If you're not using termio.Thread, this is not threadsafe.
// Update the configuration.
// The remainder of this function is modifying terminal state or
// the read thread data, all of which requires holding the renderer
// state lock.
// Deinit our old config. We do this in the lock because the
// stream handler may be referencing the old config (i.e. enquiry resp)
// Update our stream handler. The stream handler uses the same
// renderer mutex so this is safe to do despite being executed
// from another thread.
// Update the configuration that we know about.
//
// Specific things we don't update:
//   - command, working-directory: we never restart the underlying
//   process so we don't care or need to know about these.
// Update the default palette.
// Update all our other colors
// Set the image size limits
// Resize the terminal.
// Update the size of our pty.
// Enter the critical area that we want to keep small
// Update the size of our terminal state
// Update our pixel sizes
// Disable synchronized output mode so that we show changes
// immediately for a resize. This is allowed by the spec.
// If we have size reporting enabled we need to send a report.
// Mail the renderer so that it can update the GPU and re-render
// Make a size report.
// 1024 bytes should be enough for size report since report
// in columns and pixels.
// Reset the synchronized output mode. This is usually called by timer
// expiration from the termio thread.
// Clear the screen.
// If we're on the alternate screen, we do not clear. Since this is an
// emulator-level screen clear, this messes up the running programs
// knowledge of where the cursor is and causes rendering issues. So,
// for alt screen, we do nothing.
// Clear our selection
// Clear our scrollback
// If we're not at a prompt, we just delete above the cursor.
// Clear all Kitty graphics state for this screen. This copies
// Kitty's behavior when Cmd+K deletes all Kitty graphics. I
// didn't spend time researching whether it only deletes Kitty
// graphics that are placed baove the cursor or if it deletes
// all of them. We delete all of them for now but if this behavior
// isn't fully correct we should fix this later.
// At a prompt, we want to first fully clear the screen, and then after
// send a FF (0x0C) to the shell so that it can repaint the screen.
// Mark the current row as a not a prompt so we can properly
// clear the full screen in the next eraseDisplay call.
// TODO: fix this
// self.terminal.markSemanticPrompt(.command);
// assert(!self.terminal.cursorIsAtPrompt());
// If we reached here it means we're at a prompt, so we send a form-feed.
// Scroll the viewport
// Jump the viewport to the prompt.
// Called when focus is gained or lost (when focus events are enabled)
// If we have focus events enabled, we send the focus event.
// We always notify our backend of focus changes.
// Process output from the pty. This is the manual API that users can
// call with pty data but it is also called by the read thread when using
// an exec subprocess.
// We are modifying terminal state from here on out and we need
// the lock to grab our read data.
// Process output from readdata but the lock is already held.
// Schedule a render. We can call this first because we have the lock.
// Whenever a character is typed, we ensure the cursor is in the
// non-blink state so it is rendered if visible. If we're under
// HEAVY read load, we don't want to send a ton of these so we
// use a timer under the covers
// If we have an inspector, we enter SLOW MODE because we need to
// process a byte at a time alternating between the inspector handler
// and the termio handler. This is very slow compared to our optimizations
// below but at least users only pay for it if they're using the inspector.
// If our stream handling caused messages to be sent to the mailbox
// thread, then we need to wake it up so that it processes them.
// Sends a DSR response for the current color scheme to the pty.
// ThreadData is the data created and stored in the termio thread
// when the thread is started and destroyed when the thread is
// stopped.
//
// All of the fields in this struct should only be read/written by
// the termio thread. As such, a lock is not necessary.
// Allocator used for the event data
// The event loop associated with this thread. This is owned by
// the Thread but we have a pointer so we can queue new work to it.
// The shared render state
// Mailboxes for different threads
// Data associated with the backend implementation (i.e. pty/exec state)
//
// --- Original Ghostty Comments End: src/termio/Termio.zig

import apprt
import configpkg
import crash
import datastruct
import internal_os
import log
import os
import renderer
import sync
import terminal
import time
import xev

const log_tag_termio = 'io_exec'

pub enum BackendKind as u8 {
	exec
}

// BackendConfig retains backend.Config's explicit exec arm.
pub struct BackendConfig {
pub:
	exec ExecConfig
}

pub fn (self BackendConfig) kind() BackendKind {
	return .exec
}

// Backend retains backend.Backend's explicit exec arm. The pinned source has
// one backend kind, so a product wrapper preserves the arm without inventing
// another discriminator.
pub struct Backend {
pub mut:
	exec Exec
}

pub fn (self Backend) kind() BackendKind {
	return .exec
}

pub fn (mut self Backend) deinit() {
	self.exec.deinit()
}

pub fn (mut self Backend) init_terminal(mut term terminal.Terminal) {
	self.exec.init_terminal(mut term)
}

pub fn (mut self Backend) thread_enter(mut io Termio, mut td ThreadData) ! {
	self.exec.thread_enter(mut io, mut td)!
}

pub fn (mut self Backend) thread_exit(mut td ThreadData) {
	self.exec.thread_exit(mut td)
}

pub fn (mut self Backend) focus_gained(mut td ThreadData, focused bool) ! {
	self.exec.focus_gained(mut td, focused)!
}

pub fn (mut self Backend) resize(grid_size renderer.GridSize, screen_size renderer.ScreenSize) ! {
	self.exec.resize(grid_size, screen_size)!
}

pub fn (mut self Backend) queue_write(mut td ThreadData, data []u8, linefeed bool) ! {
	self.exec.queue_write(mut td, data, linefeed)!
}

// Termio manages terminal IO between the surface and the pty.
//
// This maintains the terminal state, pty, subprocess, etc. It parses the
// stream of bytes from the child process, dispatches the resulting events
// to the stream handler which mutates terminal state, and coordinates with
// the renderer and surface via mailboxes.
pub struct Termio {
pub mut:
	// The derived configuration for this termio implementation.
	config DerivedConfig

	// The terminal emulator internal state. This is the abstract "terminal"
	// that manages input, grid updating, etc. and is renderer-agnostic.
	terminal terminal.Terminal

	// The shared render state.
	renderer_state &renderer.State = unsafe { nil }

	// A handle to wake up the renderer.
	renderer_wakeup xev.Async

	// The mailbox for notifying the renderer of things.
	renderer_mailbox &datastruct.BlockingQueue[renderer.RendererMessage] = unsafe { nil }

	// The mailbox for communicating with the surface.
	surface_mailbox apprt.SurfaceMailbox

	// The cached size info.
	size renderer.Size

	// The mailbox implementation to use.
	mailbox Mailbox

	// The stream parser. This parses the stream of escape codes and so on
	// from the child process and calls callbacks in the stream handler.
	terminal_stream terminal.Stream[StreamHandler]

	// The backend implementation responsible for io (i.e. the pty/exec state).
	backend Backend

	// Last time the cursor was reset (monotonic nanoseconds). This is used
	// to prevent message flooding with cursor resets. -1 means never.
	last_cursor_reset i64 = -1

	// Startup-only input, cloned and escape-decoded from the full config.
	// This is discarded after the one allowed subprocess start attempt.
	thread_enter_input []configpkg.ReadableIO
}

pub fn (mut t Termio) init(opts TermioOpts) ! {
	size := opts.size
	grid := size.grid()
	mut term := terminal.Terminal.init(terminal.Options{
		cols: u16(grid.columns)
		rows: u16(grid.rows)
		max_scrollback: uint(opts.full_config.scrollback_limit)
		colors: terminal.Colors{
			background: terminal.DynamicRGB.init(opts.config.background)
			foreground: terminal.DynamicRGB.init(opts.config.foreground)
			cursor: if cursor := opts.config.cursor_color {
				terminal.DynamicRGB.init(cursor)
			} else {
				terminal.dynamic_rgb_unset
			}
			palette: terminal.DynamicPalette.init(opts.config.palette)
		}
	})!
	// Setup our initial grapheme cluster support if enabled.
	term.modes.set(.grapheme_cluster, opts.full_config.grapheme_width_method == .unicode)
	term.modes.set(.cursor_blinking, opts.config.cursor_blink or { true })
	term.modes.default = term.modes.values
	term.screens.active.cursor.cursor_style = opts.config.cursor_style
	term.width_px = u32(grid.columns) * size.cell.width
	term.height_px = u32(grid.rows) * size.cell.height
	// Set the image size limits
	for key in [terminal.ScreenKey.primary, .alternate] {
		if mut screen := term.screens.get(key) {
			screen.kitty_images.set_limit(mut screen, uint(opts.config.image_storage_limit))
		}
	}

	// Setup our backend.
	mut backend := opts.backend
	backend.init_terminal(mut term)

	t.config = opts.config
	t.terminal = term
	t.renderer_state = opts.renderer_state
	t.renderer_wakeup = opts.renderer_wakeup
	t.renderer_mailbox = opts.renderer_mailbox
	t.surface_mailbox = opts.surface_mailbox
	t.size = size
	t.mailbox = opts.mailbox
	t.backend = backend
	if opts.full_config.input.items.len > 0 {
		t.thread_enter_input = opts.full_config.input.clone_parsed()!.items
	} else {
		t.thread_enter_input = []
	}
	t.renderer_state.terminal_ = &t.terminal
	handler := StreamHandler{
		size: &t.size
		terminal: &t.terminal
		termio_mailbox: &t.mailbox
		surface_mailbox: t.surface_mailbox
		renderer_state: t.renderer_state
		renderer_wakeup: t.renderer_wakeup
		renderer_mailbox: t.renderer_mailbox
		osc_color_report_format: t.config.osc_color_report_format
		clipboard_write: t.config.clipboard_write
		enquiry_response: t.config.enquiry_response
		default_cursor_style: t.config.cursor_style
		default_cursor_blink: t.config.cursor_blink
	}
	t.terminal_stream = terminal.Stream.init_alloc[StreamHandler](voidptr(1), handler)
}

pub fn (mut t Termio) deinit() {
	t.backend.deinit()
	t.terminal.deinit()
	t.config.deinit()
	t.mailbox.deinit()
	// Clear any StreamHandler state
	t.terminal_stream.deinit()
	t.thread_enter_input = []
}

// Send a message to the mailbox. Depending on the mailbox type in use this
// may process now or it may just enqueue and process later. This will also
// notify the mailbox thread to process the message.
pub fn (mut t Termio) queue_message(msg Message, mutex_state MutexState) {
	match mutex_state {
		.locked {
			t.mailbox.send(msg, t.renderer_state.mutex)
		}
		.unlocked {
			t.mailbox.send(msg, unsafe { nil })
		}
	}
	t.mailbox.notify()
}

// Queue a write directly to the pty.
//
// If you're using termio.Thread, this must ONLY be called from the
// mailbox thread. If you're not on the thread, use queueMessage with
// mailbox messages instead.
//
// If you're not using termio.Thread, this is not threadsafe.
pub fn (mut t Termio) queue_write(mut td ThreadData, data []u8, linefeed bool) ! {
	t.backend.queue_write(mut td, data, linefeed)!
}

// The options that are used to configure a terminal IO implementation.
pub struct TermioOpts {
pub:
	// All size metrics for the terminal.
	size renderer.Size

	// The full app configuration. This is only available during initialization.
	// The memory it points to is NOT stable after the init call so any values
	// in here must be copied.
	full_config &configpkg.Config = unsafe { nil }

	// The derived configuration for this termio implementation.
	config DerivedConfig

	// The backend for termio that implements where reads/writes are sourced.
	backend Backend

	// The mailbox for the terminal. This is how messages are delivered.
	// If you're using termio.Thread this MUST be "mailbox".
	mailbox Mailbox

	// The render state. The IO implementation can modify anything here. The
	// surface thread will setup the initial "terminal" pointer but the IO impl
	// is free to change that if that is useful (i.e. doing some sort of dual
	// terminal implementation.)
	renderer_state &renderer.State = unsafe { nil }

	// A handle to wake up the renderer. This hints to the renderer that that
	// a repaint should happen.
	renderer_wakeup xev.Async

	// The mailbox for renderer messages.
	renderer_mailbox &datastruct.BlockingQueue[renderer.RendererMessage] = unsafe { nil }

	// The mailbox for sending the surface messages.
	surface_mailbox apprt.SurfaceMailbox
}

// DerivedConfig holds configuration derived from the main config
// that the stream handler needs.
pub struct DerivedConfig {
pub mut:
	osc_color_report_format configpkg.OSCColorReportFormat = .format_16_bit
	clipboard_write         configpkg.ClipboardAccess = .allow
	enquiry_response        string
	cursor_style            terminal.CursorStyle = .block
	cursor_blink            ?bool

	// The default 256-color palette.
	palette [256]terminal.RGB

	// The default foreground/background colors and optional cursor color.
	foreground   terminal.RGB = terminal.RGB{ r: 0xff, g: 0xff, b: 0xff }
	background   terminal.RGB = terminal.RGB{ r: 0x28, g: 0x2c, b: 0x34 }
	cursor_color ?terminal.RGB

	// The image storage limit in bytes.
	image_storage_limit int

	// The conditional state, used for the color scheme (light/dark) report.
	conditional_state configpkg.ConditionalState
}

pub fn DerivedConfig.init(config &configpkg.Config) !DerivedConfig {
	mut palette := [256]terminal.RGB{}
	for i, color in config.palette.value {
		palette[i] = color.to_terminal_rgb()
	}
	return DerivedConfig{
		palette: palette
		foreground: config.foreground.to_terminal_rgb()
		background: config.background.to_terminal_rgb()
		cursor_color: if cursor_color := config.cursor_color {
			cursor_color.to_terminal_rgb()
		} else {
			none
		}
		image_storage_limit: int(config.image_storage_limit)
		cursor_style: config.cursor_style
		cursor_blink: config.cursor_style_blink
		osc_color_report_format: config.osc_color_report_format
		clipboard_write: config.clipboard_write
		enquiry_response: config.enquiry_response.clone()
		conditional_state: config.conditional_state
	}
}

pub fn (d DerivedConfig) deinit() {}

// ============================================================
// Termio methods (translated from Termio.zig)
// ============================================================

pub fn (mut t Termio) thread_enter(mut thr Thread, mut data ThreadData) ! {
	// Always free our thread enter state when we're done.
	defer {
		// Exec only starts once, so startup input is never retained afterward.
		t.thread_enter_input = []
	}

	// If we have thread enter state then we're going to validate
	// and set that all up now so that we can error before we actually
	// start the command and pty.
	mut inputs := t.prepare_input()!
	defer {
		close_prepared_inputs(mut inputs)
	}

	data.loop = &thr.loop
	data.renderer_state = t.renderer_state
	data.surface_mailbox = t.surface_mailbox
	data.mailbox = &t.mailbox
	// Backend must replace data.backend on threadEnter.

	// Setup our backend
	t.backend.thread_enter(mut t, mut data)!
	// Zig's errdefer is emulated by a reached defer that runs until setup succeeds.
	mut ok := false
	defer {
		if !ok {
			t.backend.thread_exit(mut data)
		}
	}

	// If we have inputs, then queue them all up.
	for mut item in inputs {
		match mut item {
			PreparedInputString {
				t.queue_write(mut data, item.data, false) or {
					log.warn('failed to queue input string err=${err}')
					return error('input failed')
				}
			}
			PreparedInputFile {
				bytes := read_initial_input_file(mut item.file) or {
					log.warn('failed to read input file err=${err}')
					return error('input failed')
				}
				t.queue_write(mut data, bytes, false) or {
					log.warn('failed to queue input file err=${err}')
					return error('input failed')
				}
			}
		}
	}
	ok = true
}

const initial_input_max_bytes = 10 * 1024 * 1024

struct PreparedInputString {
	data []u8
}

struct PreparedInputFile {
mut:
	file os.File
}

type PreparedInput = PreparedInputFile | PreparedInputString

fn (t &Termio) prepare_input() ![]PreparedInput {
	mut result := []PreparedInput{cap: t.thread_enter_input.len}
	for item in t.thread_enter_input {
		match item {
			configpkg.ReadableIORaw {
				result << PreparedInputString{
					data: item.value.bytes()
				}
			}
			configpkg.ReadableIOPath {
				file := os.open(item.value) or {
					log.warn('failed to open input file=${item.value} err=${err}')
					close_prepared_inputs(mut result)
					return error('input not found')
				}
				result << PreparedInputFile{
					file: file
				}
			}
		}
	}
	return result
}

fn read_initial_input_file(mut file os.File) ![]u8 {
	mut data := []u8{len: initial_input_max_bytes + 1}
	mut total := 0
	for total < data.len {
		read := file.read_from(u64(total), mut data[total..]) or {
			if err is os.Eof {
				break
			}
			return err
		}
		if read == 0 {
			break
		}
		total += read
	}
	if total > initial_input_max_bytes {
		return error('input failed')
	}
	data.trim(total)
	return data
}

fn close_prepared_inputs(mut inputs []PreparedInput) {
	for mut item in inputs {
		match mut item {
			PreparedInputFile { item.file.close() }
			PreparedInputString {}
		}
	}
}

pub fn (mut t Termio) thread_exit(mut data ThreadData) {
	t.backend.thread_exit(mut data)
}

// change_config updates the configuration.
pub fn (mut t Termio) change_config(mut td ThreadData, config &DerivedConfig) ! {
	// The remainder of this function is modifying terminal state or the read
	// thread data, all of which requires holding the renderer state lock.
	t.renderer_state.mutex.lock()
	defer {
		t.renderer_state.mutex.unlock()
	}

	// Deinit our old config. We do this in the lock because the stream
	// handler may be referencing the old config (i.e. enquiry resp).
	t.config.deinit()
	t.config = *config

	// Update our stream handler. The stream handler uses the same renderer
	// mutex so this is safe to do despite being executed from another thread.
	t.terminal_stream.handler.change_config(&t.config)
	td.backend.change_config(&t.config)

	// Update the configuration that we know about.
	//
	// Specific things we don't update:
	//   - command, working-directory: we never restart the underlying
	//     process so we don't care or need to know about these.

	// Update the default palette.
	t.terminal.colors.palette.change_default(config.palette)
	t.terminal.flags.set_dirty_palette(true)

	// Update all our other colors.
	t.terminal.colors.background.default_color = config.background
	t.terminal.colors.foreground.default_color = config.foreground
	t.terminal.colors.cursor.default_color = config.cursor_color

	// Set the image size limits
	for key in [terminal.ScreenKey.primary, .alternate] {
		if mut screen := t.terminal.screens.get(key) {
			screen.kitty_images.set_limit(mut screen, uint(config.image_storage_limit))
		}
	}
}

// resize resizes the terminal.
pub fn (mut t Termio) resize(mut td ThreadData, size renderer.Size) ! {
	t.size = size
	grid_size := size.grid()

	// Update the size of our pty.
	t.backend.resize(grid_size, size.terminal())!

	// Enter the critical area that we want to keep small.
	{
		t.renderer_state.mutex.lock()
		defer {
			t.renderer_state.mutex.unlock()
		}

		// Update the size of our terminal state.
		t.terminal.resize(u16(grid_size.columns), u16(grid_size.rows))!

		// Update our pixel sizes.
		t.terminal.width_px = u32(grid_size.columns) * t.size.cell.width
		t.terminal.height_px = u32(grid_size.rows) * t.size.cell.height

		// Disable synchronized output mode so that we show changes
		// immediately for a resize. This is allowed by the spec.
		t.terminal.modes.set(.synchronized_output, false)

		// If we have size reporting enabled we need to send a report.
		if t.terminal.modes.get(.in_band_size_reports) {
			t.size_report_locked(mut td, .mode_2048)!
		}
	}

	// Mail the renderer so that it can update the GPU and re-render.
	_ = t.renderer_mailbox.push(renderer.RendererMessage(renderer.ResizeMessage{
		size: t.size
	}), datastruct.blocking_queue_forever)
	t.renderer_wakeup.notify() or {}
}

// size_report makes a size report of the given style.
pub fn (mut t Termio) size_report(mut td ThreadData, style SizeReportKind) ! {
	t.renderer_state.mutex.lock()
	defer {
		t.renderer_state.mutex.unlock()
	}
	t.size_report_locked(mut td, style)!
}

fn (mut t Termio) size_report_locked(mut td ThreadData, style SizeReportKind) ! {
	grid_size := t.size.grid()

	// Build the size report message. Reports in columns and pixels.
	message := match style {
		.mode_2048 {
			'\x1b[48;${grid_size.rows};${grid_size.columns};${u32(grid_size.rows) * t.size.cell.height};${u32(grid_size.columns) * t.size.cell.width}t'
		}
		.csi_14_t {
			'\x1b[4;${u32(grid_size.rows) * t.size.cell.height};${u32(grid_size.columns) * t.size.cell.width}t'
		}
		.csi_16_t {
			'\x1b[6;${t.size.cell.height};${t.size.cell.width}t'
		}
		.csi_18_t {
			'\x1b[8;${grid_size.rows};${grid_size.columns}t'
		}
	}

	t.queue_write(mut td, message.bytes(), false)!
}

// reset_synchronized_output resets the synchronized output mode. This is
// usually called by timer expiration from the termio thread.
pub fn (mut t Termio) reset_synchronized_output() {
	t.renderer_state.mutex.lock()
	defer {
		t.renderer_state.mutex.unlock()
	}
	t.terminal.modes.set(.synchronized_output, false)
	t.renderer_wakeup.notify() or {}
}

// clear_screen clears the screen. If history is true, the scrollback is
// also cleared.
pub fn (mut t Termio) clear_screen(mut td ThreadData, history bool) ! {
	{
		t.renderer_state.mutex.lock()
		defer {
			t.renderer_state.mutex.unlock()
		}

		// If we're on the alternate screen, we do not clear. Since this is
		// an emulator-level screen clear, this messes up the running
		// program's knowledge of where the cursor is and causes rendering
		// issues. So, for alt screen, we do nothing.
		if t.terminal.screens.active_key == .alternate {
			return
		}

		// Clear our selection.
		t.terminal.screens.active.clear_selection()

		// Clear our scrollback.
		if history {
			t.terminal.erase_display(.scrollback, false)
		}

		// If we're not at a prompt, we just delete above the cursor.
		if !t.terminal.cursor_is_at_prompt() {
			if t.terminal.screens.active.cursor.y > 0 {
				t.terminal.screens.active.erase_rows(terminal.Point.new(.active, terminal.Coordinate{}), terminal.Point.new(.active, terminal.Coordinate{
					y: t.terminal.screens.active.cursor.y - 1
				}))
			}
			t.terminal.screens.active.kitty_images.delete(mut t.terminal, terminal.DeleteAll{
				delete: true
			})
			return
		}

		// At a prompt, we want to first fully clear the screen, and then
		// after send a FF (0x0C) to the shell so that it can repaint the
		// screen.
		t.terminal.erase_display(.complete, false)
	}

	// If we reached here it means we're at a prompt, so we send a form-feed.
	t.queue_write(mut td, [u8(0x0C)], false)!
}

// scroll_viewport scrolls the viewport.
pub fn (mut t Termio) scroll_viewport(scroll terminal.ScrollViewport) ! {
	t.renderer_state.mutex.lock()
	defer {
		t.renderer_state.mutex.unlock()
	}
	t.terminal.scroll_viewport(scroll)!
}

// jump_to_prompt jumps the viewport to the prompt.
pub fn (mut t Termio) jump_to_prompt(delta int) ! {
	{
		t.renderer_state.mutex.lock()
		defer {
			t.renderer_state.mutex.unlock()
		}
		t.terminal.screens.active.scroll(terminal.ScrollDeltaPrompt{
			delta: delta
		})
	}

	t.renderer_wakeup.notify()!
}

// focus_gained is called when focus is gained or lost (when focus events
// are enabled).
pub fn (mut t Termio) focus_gained(mut td ThreadData, focused bool) ! {
	t.renderer_state.mutex.lock()
	focus_event := t.terminal.modes.get(.focus_event)
	t.renderer_state.mutex.unlock()

	// If we have focus events enabled, we send the focus event.
	if focus_event {
		seq := if focused { '\x1b[I' } else { '\x1b[O' }
		t.queue_write(mut td, seq.bytes(), false)!
	}

	// We always notify our backend of focus changes.
	t.backend.focus_gained(mut td, focused)!
}

// process_output processes output from the pty. This is the manual API that
// users can call with pty data but it is also called by the read thread when
// using an exec subprocess.
pub fn (mut t Termio) process_output(buf []u8) {
	// We are modifying terminal state from here on out and we need the lock
	// to grab our read data.
	t.renderer_state.mutex.lock()
	defer {
		t.renderer_state.mutex.unlock()
	}
	t.process_output_locked(buf)
}

// process_output_locked processes output from readdata but the lock is
// already held.
fn (mut t Termio) process_output_locked(buf []u8) {
	// Schedule a render. We can call this first because we have the lock.
	t.terminal_stream.handler.queue_render() or {
		panic('unreachable: renderer wakeup failed while processing output: ${err}')
	}

	// Whenever a character is typed, we ensure the cursor is in the
	// non-blink state so it is rendered if visible. If we're under HEAVY
	// read load, we don't want to send a ton of these so we use a timer
	// under the covers (500ms throttle).
	now := i64(time.sys_mono_now())
	if t.last_cursor_reset < 0 || (now - t.last_cursor_reset) > (500 * i64(time.millisecond)) {
		t.last_cursor_reset = now
		_ = t.renderer_mailbox.push(renderer.RendererMessage(renderer.ResetCursorBlinkMessage{}),
			datastruct.blocking_queue_instant)
	}

	// If the inspector is active, use Ghostty's slow path: process a byte at a
	// time, record each raw action with pre-dispatch terminal state, and then
	// apply the semantic actions. Normal operation retains the bulk fast path.
	if !isnil(t.renderer_state.inspector) {
		for i, byte in buf {
			t.renderer_state.record_inspector_pty_read(buf[i..i + 1]) or {
				log.error('error recording pty read in inspector err=${err}')
			}

			t.terminal_stream.next(byte) or { log.error('error processing terminal data: ${err}') }
		}
	} else {
		t.terminal_stream.next_slice(buf) or { log.error('error processing terminal data: ${err}') }
	}

	// If our stream handling caused messages to be sent to the mailbox
	// thread, then we need to wake it up so that it processes them.
	if t.terminal_stream.handler.termio_messaged {
		t.terminal_stream.handler.termio_messaged = false
		t.mailbox.notify()
	}
}

// color_scheme_report sends a DSR response for the current color scheme to
// the pty.
pub fn (mut t Termio) color_scheme_report(mut td ThreadData, force bool) ! {
	t.renderer_state.mutex.lock()
	defer {
		t.renderer_state.mutex.unlock()
	}
	t.color_scheme_report_locked(mut td, force)!
}

pub fn (mut t Termio) color_scheme_report_locked(mut td ThreadData, force bool) ! {
	if !force && !t.terminal.modes.get(.report_color_scheme) {
		return
	}
	output := match t.config.conditional_state.theme {
		.light { '\x1b[?997;2n' }
		.dark { '\x1b[?997;1n' }
	}
	t.queue_write(mut td, output.bytes(), false)!
}

// ThreadData is the data created and stored in the termio thread when the
// thread is started and destroyed when the thread is stopped.
//
// All of the fields in this struct should only be read/written by the termio
// thread. As such, a lock is not necessary.
pub struct ThreadData {
pub mut:
	// The event loop associated with this thread. This is owned by
	// the Thread but we have a pointer so we can queue new work to it.
	loop &xev.Loop = unsafe { nil }

	// The shared render state
	renderer_state &renderer.State = unsafe { nil }

	// Mailboxes for different threads
	surface_mailbox apprt.SurfaceMailbox

	// Data associated with the backend implementation (i.e. pty/exec state)
	backend BackendThreadData
	mailbox &Mailbox = unsafe { nil }
}

pub fn (mut self ThreadData) deinit() {
	self.backend.deinit()
}

// BackendThreadData retains backend.ThreadData's explicit exec arm.
pub struct BackendThreadData {
pub mut:
	exec ExecThreadData
}

pub fn (self BackendThreadData) kind() BackendKind {
	return .exec
}

pub fn (mut self BackendThreadData) deinit() {
	self.exec.deinit()
}

pub fn (mut self BackendThreadData) change_config(config &DerivedConfig) {
	_ = self
	_ = config
}

// CursorStyle: use terminal.CursorStyle directly.

// ThreadFlags is the packed set of flags owned by the IO thread.
pub struct ThreadFlags {
mut:
	value u8
}

fn (self ThreadFlags) drain() bool {
	return self.value & 0b001 != 0
}

fn (mut self ThreadFlags) set_drain(value bool) {
	self.set(0b001, value)
}

fn (self ThreadFlags) linefeed_mode() bool {
	return self.value & 0b010 != 0
}

fn (mut self ThreadFlags) set_linefeed_mode(value bool) {
	self.set(0b010, value)
}

fn (self ThreadFlags) has_inspector() bool {
	return self.value & 0b100 != 0
}

fn (mut self ThreadFlags) set_has_inspector(value bool) {
	self.set(0b100, value)
}

fn (mut self ThreadFlags) set(mask u8, enabled bool) {
	if enabled {
		self.value |= mask
	} else {
		self.value &= ~mask
	}
}

// This stores the information that is coalesced.
struct Coalesce {
mut:
	resize ?renderer.Size
}

// The number of milliseconds to coalesce certain messages like resize for.
// Not all message types are coalesced.
const coalesce_min_ms = 25

// The number of milliseconds before we reset the synchronized output flag
// if the running program hasn't already.
const sync_reset_ms = 1000

// The number of milliseconds between each movement during selection scrolling.
const selection_scroll_ms = 15

// Represents the "writer" thread for terminal IO. The reader side is
// handled by the Termio struct itself and dependent on the underlying
// implementation (i.e. if its a pty, manual, etc.).
//
// The writer thread does handle writing bytes to the pty but also handles
// different events such as starting synchronized output, changing some
// modes (like linefeed), etc. The goal is to offload as much from the
// reader thread as possible since it is the hot path in parsing VT
// sequences and updating terminal state.
//
// This thread state can only be used by one thread at a time.
pub struct Thread {
pub mut:
	// The main event loop for the thread. The user data of this loop
	// is always the allocator used to create the loop. This is a convenience
	// so that users of the loop always have an allocator.
	loop xev.Loop

	// The completion to use for the wakeup async handle that is present
	// on the termio.Writer.
	wakeup_c xev.Completion

	// This can be used to stop the thread on the next loop iteration.
	stop   xev.Async
	stop_c xev.Completion

	// This is used for timer-based selection scrolling.
	scroll        xev.Timer
	scroll_c      xev.Completion
	scroll_active bool

	// This is used to coalesce resize events.
	coalesce          xev.Timer
	coalesce_c        xev.Completion
	coalesce_cancel_c xev.Completion
	coalesce_data     Coalesce

	// This timer is used to reset synchronized output modes so that
	// the terminal doesn't freeze with a bad actor.
	sync_reset          xev.Timer
	sync_reset_c        xev.Completion
	sync_reset_cancel_c xev.Completion

	flags ThreadFlags
}

// Initialize the thread. This does not START the thread. This only sets
// up all the internal state necessary prior to starting the thread. It
// is up to the caller to start the thread with the threadMain entrypoint.
pub fn Thread.init() !Thread {
	// Zig's errdefers are emulated by reached defers that run until init succeeds.
	mut init_ok := false

	// Create our event loop.
	mut loop := xev.Loop.init(xev.Options{})!
	defer {
		if !init_ok {
			loop.deinit()
		}
	}

	// This async handle is used to stop the loop and force the thread to end.
	mut stop_h := xev.Async.init()!
	defer {
		if !init_ok {
			stop_h.deinit()
		}
	}

	// This timer is used for selection scrolling.
	scroll_h := xev.Timer.init()!
	defer {
		if !init_ok {
			scroll_h.deinit()
		}
	}

	// This timer is used to coalesce resize events.
	coalesce_h := xev.Timer.init()!
	defer {
		if !init_ok {
			coalesce_h.deinit()
		}
	}

	// This timer is used to reset synchronized output modes.
	sync_reset_h := xev.Timer.init()!
	defer {
		if !init_ok {
			sync_reset_h.deinit()
		}
	}

	init_ok = true
	return Thread{
		loop:       loop
		stop:       stop_h
		scroll:     scroll_h
		coalesce:   coalesce_h
		sync_reset: sync_reset_h
	}
}

// Clean up the thread. This is only safe to call once the thread
// completes executing; the caller must join prior to this.
pub fn (mut self Thread) deinit() {
	self.scroll.deinit()
	self.coalesce.deinit()
	self.sync_reset.deinit()
	self.stop.deinit()
	self.loop.deinit()
}

// The main entrypoint for the thread.
pub fn (mut self Thread) thread_main(mut io Termio) {
	// Call child function so we can use errors...
	self.thread_main_(mut io) or {
		log.warn('error in io thread err=${err}')

		// If there is an error, we replace our terminal screen with
		// the error message. It might be better in the future to send
		// the error to the surface thread and let the apprt deal with it
		// in some way but this works for now. Without this, the user would
		// just see a blank terminal window.
		self.show_start_error(mut io, err.msg())
	}

	// If our loop is not stopped, then we need to keep running so that
	// messages are drained and we can wait for the surface to send a stop
	// message.
	if !self.loop.stopped() {
		log.warn('abrupt io thread exit detected, starting xev to drain mailbox')
		defer {
			log.debug('io thread fully exiting after abnormal failure')
		}
		self.flags.set_drain(true)
		self.loop.run(.until_done) or {
			log.error('failed to start xev loop for draining err=${err}')
		}
	}
}

fn (mut self Thread) thread_main_(mut io Termio) ! {
	defer {
		log.debug('IO thread exited')
	}
	// Right now, on Darwin, `std.Thread.setName` can only name the current
	// thread, and we have no way to get the current thread from within it,
	// so instead we use this code to name the thread instead.
	$if macos || ios {
		internal_os.set_thread_name('io')
	}

	// Setup our crash metadata
	crash.set_thread_state(crash.ThreadState{
		kind:    .io
		surface: io.surface_mailbox.surface
	})
	defer {
		crash.clear_thread_state()
	}

	// Get the mailbox. This must be an SPSC mailbox for threading.
	mut mailbox := &io.mailbox.spsc

	// This is the data sent to xev callbacks. We want a pointer to both
	// ourselves and the thread data so we can thread that through (pun intended).
	mut cb := &CallbackData{
		self_: self
		io:    io
	}

	// Run our thread start/end callbacks. This allows the implementation
	// to hook into the event loop as needed. The thread data is created
	// on the stack here so that it has a stable pointer throughout the
	// lifetime of the thread.
	io.thread_enter(mut self, mut cb.data)!
	defer {
		cb.data.deinit()
	}
	defer {
		io.thread_exit(mut cb.data)
	}

	// Start the async handlers.
	mailbox.wakeup.wait(mut self.loop, &self.wakeup_c, cb, termio_thread_wakeup_callback)
	self.stop.wait(mut self.loop, &self.stop_c, cb, termio_thread_stop_callback)

	// Run
	log.debug('starting IO thread')
	defer {
		log.debug('starting IO thread shutdown')
	}
	self.loop.run(.until_done)!
}

// This is the data passed to xev callbacks on the thread.
@[heap]
struct CallbackData {
mut:
	self_ &Thread = unsafe { nil }
	io    &Termio = unsafe { nil }
	data  ThreadData
}

// Drain the mailbox, handling all the messages in our terminal implementation.
fn (mut self Thread) drain_mailbox(mut cb CallbackData) ! {
	// We assert when starting the thread that this is the state
	mut mailbox := cb.io.mailbox.spsc.queue
	mut io := cb.io
	mut data := &cb.data

	// If we're draining, we just drain the mailbox and return.
	if self.flags.drain() {
		for {
			mailbox.pop() or { break }
		}
		return
	}

	// This holds the mailbox lock for the duration of the drain. The
	// expectation is that all our message handlers will be non-blocking
	// ENOUGH to not mess up throughput on producers.
	mut redraw := false
	for {
		message := mailbox.pop() or { break }
		// If we have a message we always redraw
		redraw = true
		log.debug('mailbox message=${message.kind()}')

		match message {
			MessageColorSchemeReport {
				io.color_scheme_report(mut data, message.force)!
			}
			MessageCrash {
				panic('crash request, crashing intentionally')
			}
			MessageChangeConfig {
				io.change_config(mut data, &message.config)!
			}
			MessageInspector {
				self.flags.set_has_inspector(message.value)
			}
			renderer.Size {
				self.handle_resize(mut cb, message)
			}
			MessageSizeReport {
				io.size_report(mut data, message.style)!
			}
			MessageClearScreen {
				io.clear_screen(mut data, message.history)!
			}
			MessageScrollViewport {
				io.scroll_viewport(message.scroll)!
			}
			MessageSelectionScroll {
				if message.value {
					self.start_scroll_timer(mut cb)
				} else {
					self.stop_scroll_timer()
				}
			}
			MessageJumpToPrompt {
				io.jump_to_prompt(message.delta)!
			}
			MessageStartSynchronizedOutput {
				self.start_synchronized_output(mut cb)
			}
			MessageLinefeedMode {
				self.flags.set_linefeed_mode(message.value)
			}
			MessageFocused {
				io.focus_gained(mut data, message.value)!
			}
			WriteSmall {
				io.queue_write(mut data, message.slice(), self.flags.linefeed_mode())!
			}
			MessageWriteStable {
				io.queue_write(mut data, message.data.bytes(), self.flags.linefeed_mode())!
			}
			MessageWriteAlloc {
				io.queue_write(mut data, message.data.bytes(), self.flags.linefeed_mode())!
			}
		}
	}

	// Trigger a redraw after we've drained so we don't waste cyces
	// messaging a redraw.
	if redraw {
		io.renderer_wakeup.notify()!
	}
}

fn (mut self Thread) start_synchronized_output(mut cb CallbackData) {
	self.sync_reset.reset(mut self.loop, &self.sync_reset_c, &self.sync_reset_cancel_c,
		sync_reset_ms, cb, termio_thread_sync_reset_callback)
}

fn (mut self Thread) handle_resize(mut cb CallbackData, resize renderer.Size) {
	self.coalesce_data.resize = resize

	// If the timer is already active we just return. In the future we want
	// to reset the timer up to a maximum wait time but for now this ensures
	// relatively smooth resizing.
	if self.coalesce_c.state() == .active {
		return
	}

	self.coalesce.reset(mut self.loop, &self.coalesce_c, &self.coalesce_cancel_c, coalesce_min_ms,
		cb, termio_thread_coalesce_callback)
}

fn termio_thread_sync_reset_callback(cb_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if err := r {
		match err {
			.canceled {}
			else {
				log.warn('error during sync reset callback err=${err}')
				return .disarm
			}
		}
	}

	if cb_ == unsafe { nil } {
		return .disarm
	}
	mut cb := unsafe { &CallbackData(cb_) }
	cb.io.reset_synchronized_output()
	return .disarm
}

fn termio_thread_coalesce_callback(cb_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if err := r {
		match err {
			.canceled {}
			else {
				log.warn('error during coalesce callback err=${err}')
				return .disarm
			}
		}
	}

	if cb_ == unsafe { nil } {
		return .disarm
	}
	mut cb := unsafe { &CallbackData(cb_) }

	if v := cb.self_.coalesce_data.resize {
		cb.self_.coalesce_data.resize = none
		cb.io.resize(mut cb.data, v) or { log.warn('error during resize err=${err}') }
	}

	return .disarm
}

fn termio_thread_wakeup_callback(cb_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if err := r {
		log.error('error in wakeup err=${err}')
		return .rearm
	}

	// When we wake up, we check the mailbox. Mailbox producers should
	// wake up our thread after publishing.
	if cb_ == unsafe { nil } {
		return .rearm
	}
	mut cb := unsafe { &CallbackData(cb_) }
	cb.self_.drain_mailbox(mut cb) or { log.error('error draining mailbox err=${err}') }

	return .rearm
}

fn termio_thread_stop_callback(cb_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if _ := r {
		panic('unreachable')
	}
	mut cb := unsafe { &CallbackData(cb_) }
	cb.self_.loop.stop()
	return .disarm
}

fn (mut self Thread) start_scroll_timer(mut cb CallbackData) {
	self.scroll_active = true

	match self.scroll_c.state() {
		// If it is already active, e.g. startScrollTimer is called multiple
		// times, then we just return. We can't simply check `scroll_active`
		// because its possible that `stopScrollTimer` was called but there
		// was no loop tick between then and now to halt out completion.
		.active {
			return
		}
		// If the completion is not active then we need to start it.
		.dead {
			self.scroll.run(mut self.loop, &self.scroll_c, selection_scroll_ms, cb, termio_thread_selection_scroll_callback)
		}
	}
}

fn (mut self Thread) stop_scroll_timer() {
	// This will stop the scrolling on the next iteration.
	self.scroll_active = false
}

fn termio_thread_selection_scroll_callback(cb_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if err := r {
		match err {
			.canceled {}
			else {
				log.warn('error during selection scroll callback err=${err}')
				return .disarm
			}
		}
	}

	if cb_ == unsafe { nil } {
		return .disarm
	}
	mut cb := unsafe { &CallbackData(cb_) }
	mut self := cb.self_

	// Send the tick to the main surface
	cb.io.surface_mailbox.push(apprt.SurfaceMessageSelectionScrollTick{ value: self.scroll_active }, datastruct.blocking_queue_instant)

	if self.scroll_active {
		self.scroll.run(mut self.loop, &self.scroll_c, selection_scroll_ms, cb, termio_thread_selection_scroll_callback)
	}

	return .disarm
}

fn (self &Thread) show_start_error(mut io Termio, message string) {
	io.renderer_state.mutex.lock()
	defer { io.renderer_state.mutex.unlock() }
	mut t := io.renderer_state.terminal_

	// Hide the cursor
	t.modes.set(.cursor_visible, false)

	text := match message {
		'openpty failed' {
			'Your system cannot allocate any more pty devices.\n\nGhostty requires a pty device to launch a new terminal.\nThis error is usually due to having too many terminal\nwindows open or having another program that is using too\nmany pty devices.\n\nPlease free up some pty devices and try again.'
		}
		'input not found', 'input failed' {
			"A configured `input` path was not found, was not readable,\nwas too large, or the underlying pty failed to accept\nthe write.\n\nGhostty can't continue since it can't guarantee that\ninitial terminal state will be as desired. Please review\nthe value of `input` in your configuration file and\nensure that all the path values exist and are readable."
		}
		else {
			'error starting IO thread: ${message}\n\nThe underlying shell or command was unable to be started.\nThis error is usually due to exhausting a system resource.\nIf this looks like a bug, please report it.\n\nThis terminal is non-functional. Please close it and try again.'
		}
	}
	t.erase_display(.complete, false)
	t.print_string(text) or {}
}

// ============================================================
// Message: represents an IO message to send to the terminal.
// ============================================================

// Request a color scheme report is sent to the pty.
pub struct MessageColorSchemeReport {
pub:
	// Force write the current color scheme
	force bool
}

// Purposely crash the renderer. This is used for testing and debugging.
// See the "crash" binding action.
pub struct MessageCrash {}

// The derived configuration to update the implementation with. The source
// allocates the config and frees it on receipt; the V message carries the
// GC-managed value.
pub struct MessageChangeConfig {
pub:
	config DerivedConfig
}

// Activate or deactivate the inspector.
pub struct MessageInspector {
pub:
	value bool
}

// Request a size report is sent to the pty ([in-band
// size report, mode 2048](https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83) and
// [XTWINOPS](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Functions-using-CSI-_-ordered-by-the-final-character-lparen-s-rparen:CSI-Ps;Ps;Ps-t.1EB0)).
pub struct MessageSizeReport {
pub:
	style SizeReportKind
}

// Clear the screen.
pub struct MessageClearScreen {
pub:
	// Include clearing the history
	history bool
}

// Scroll the viewport
pub struct MessageScrollViewport {
pub:
	scroll terminal.ScrollViewport
}

// Selection scrolling. If this is set to true then the termio
// thread starts a timer that will trigger a `selection_scroll_tick`
// message back to the surface. This ping/pong is because the
// surface thread doesn't have access to an event loop from libwitty.
pub struct MessageSelectionScroll {
pub:
	value bool
}

// Jump forward/backward n prompts.
pub struct MessageJumpToPrompt {
pub:
	delta int
}

// Send this when a synchronized output mode is started. This will
// start the timer so that the output mode is disabled after a
// period of time so that a bad actor can't hang the terminal.
pub struct MessageStartSynchronizedOutput {}

// Enable or disable linefeed mode (mode 20).
pub struct MessageLinefeedMode {
pub:
	value bool
}

// The surface gained or lost focus.
pub struct MessageFocused {
pub:
	value bool
}

// Write where the data pointer is stable.
pub struct MessageWriteStable {
pub:
	data string
}

// Write where the data is allocated and must be freed.
pub struct MessageWriteAlloc {
pub:
	data string
}

// Message represents an IO message to send to the terminal: the source's
// tagged union. `resize` and `write_small` carry their payload types
// directly.
pub type Message = MessageChangeConfig
	| MessageClearScreen
	| MessageColorSchemeReport
	| MessageCrash
	| MessageFocused
	| MessageInspector
	| MessageJumpToPrompt
	| MessageLinefeedMode
	| MessageScrollViewport
	| MessageSelectionScroll
	| MessageSizeReport
	| MessageStartSynchronizedOutput
	| MessageWriteAlloc
	| MessageWriteStable
	| WriteSmall
	| renderer.Size

// The tag of the active message variant.
pub fn (self Message) kind() MessageKind {
	return match self {
		MessageColorSchemeReport { .color_scheme_report }
		MessageCrash { .crash }
		MessageChangeConfig { .change_config }
		MessageInspector { .inspector }
		renderer.Size { .resize }
		MessageSizeReport { .size_report }
		MessageClearScreen { .clear_screen }
		MessageScrollViewport { .scroll_viewport }
		MessageSelectionScroll { .selection_scroll }
		MessageJumpToPrompt { .jump_to_prompt }
		MessageStartSynchronizedOutput { .start_synchronized_output }
		MessageLinefeedMode { .linefeed_mode }
		MessageFocused { .focused }
		WriteSmall { .write_small }
		MessageWriteStable { .write_stable }
		MessageWriteAlloc { .write_alloc }
	}
}

pub enum MessageKind as u8 {
	color_scheme_report       = 0
	crash                     = 1
	change_config             = 2
	inspector                 = 3
	resize                    = 4
	size_report               = 5
	clear_screen              = 6
	scroll_viewport           = 7
	selection_scroll          = 8
	jump_to_prompt            = 9
	start_synchronized_output = 10
	linefeed_mode             = 11
	focused                   = 12
	write_small               = 13
	write_stable              = 14
	write_alloc               = 15
}

// SizeReportKind identifies what kind of size report to send.
pub enum SizeReportKind as u8 {
	mode_2048 = 0
	csi_14_t  = 1
	csi_16_t  = 2
	csi_18_t  = 3
}

pub struct WriteSmall {
pub mut:
	data [38]u8
	len  u8
}

// WriteReq is the payload queued by Surface while a key sequence is active.
// Ghostty defines this as MessageData(u8, 38), using the same inline capacity
// as Message.write_small.
pub struct WriteReq {
mut:
	payload datastruct.MessageData[u8]
}

pub fn WriteReq.init(data []u8) WriteReq {
	return WriteReq{
		payload: datastruct.MessageData.init[u8](38, data)
	}
}

pub fn WriteReq.from_stable(data []u8) WriteReq {
	return WriteReq{
		payload: datastruct.MessageData.from_stable[u8](data)
	}
}

pub fn (req &WriteReq) slice() []u8 {
	return req.payload.slice()
}

pub fn (req &WriteReq) message() Message {
	data := req.payload.slice()
	return match req.payload.kind() {
		.small { Message(WriteSmall.from_slice(data)) }
		.stable { Message(MessageWriteStable{ data: data.bytestr() }) }
		.alloc { Message(MessageWriteAlloc{ data: data.bytestr() }) }
	}
}

pub fn (mut req WriteReq) deinit() {
	req.payload.deinit()
}

pub fn WriteSmall.from_slice(s []u8) WriteSmall {
	mut w := WriteSmall{}
	length := if s.len < 38 { u8(s.len) } else { u8(38) }
	for i in 0 .. int(length) {
		w.data[i] = s[i]
	}
	w.len = length
	return w
}

pub fn (w &WriteSmall) slice() []u8 {
	mut result := []u8{len: int(w.len)}
	for i in 0 .. int(w.len) {
		result[i] = w.data[i]
	}
	return result
}

// Return a write request for the given data. This will use
// write_small if it fits or write_alloc otherwise. This should NOT
// be used for stable pointers which can be manually set to write_stable.
pub fn Message.write_req(data string) Message {
	// If the data fits in a small write, use that
	if data.len <= 38 {
		return WriteSmall.from_slice(data.bytes())
	}
	// Otherwise use an allocated write
	return MessageWriteAlloc{
		data: data.clone()
	}
}

// write_slice returns the byte payload for any write message.
pub fn (msg &Message) write_slice() []u8 {
	return match msg {
		WriteSmall { msg.slice() }
		MessageWriteStable { msg.data.bytes() }
		MessageWriteAlloc { msg.data.bytes() }
		else { []u8{} }
	}
}

pub enum MutexState as u8 {
	locked   = 0
	unlocked = 1
}

// mailbox_capacity is the number of messages the mailbox can hold. Ghostty
// uses a BlockingQueue with a capacity of 64 that empirically makes sense for
// Ghostty usage.
const mailbox_capacity = 64

// A queue used for storing messages that is periodically drained.
// Typically used by a multi-threaded application. The capacity is
// hardcoded to a value that empirically has made sense for Ghostty usage
// but I'm open to changing it with good arguments.
pub type MailboxQueue = datastruct.BlockingQueue[Message]

pub struct MailboxSpsc {
pub mut:
	// Write messages to a SPSC queue for multi-threaded applications.
	queue  &MailboxQueue = unsafe { nil }
	wakeup xev.Async
}

// The location to where write-related messages are sent. Ghostty's union has
// the single SPSC variant because its unbounded variant is commented out.
pub struct Mailbox {
pub mut:
	spsc MailboxSpsc
}

// Init the SPSC writer.
pub fn Mailbox.init_spsc() !Mailbox {
	mut queue := datastruct.BlockingQueue.create[Message](mailbox_capacity)!
	// Zig's errdefer is emulated by a reached defer that runs until init succeeds.
	mut ok := false
	defer {
		if !ok {
			queue.destroy()
		}
	}

	wakeup := xev.Async.init()!

	ok = true
	return Mailbox{
		spsc: MailboxSpsc{
			queue:  queue
			wakeup: wakeup
		}
	}
}

pub fn (mut m Mailbox) deinit() {
	m.spsc.queue.destroy()
	m.spsc.wakeup.deinit()
}

// Sends the given message without notifying there are messages.
//
// If the optional mutex is given, it must already be LOCKED. If the
// send would block, we'll unlock this mutex, resend the message, and
// lock it again. This handles an edge case where queues are full.
// This may not apply to all writer types.
pub fn (mut m Mailbox) send(msg Message, mtx &sync.Mutex) {
	// Try to write to the queue with an instant timeout. This is the
	// fast path because we can queue without a lock.
	if m.spsc.queue.push(msg, datastruct.blocking_queue_instant) > 0 {
		return
	}

	// If we enter this conditional, the queue is full. We wake up
	// the writer thread so that it can process messages to clear up
	// space. However, the writer thread may require the renderer
	// lock so we need to unlock.
	m.spsc.wakeup.notify() or {
		log.warn('failed to wake up writer, data will be dropped err=${err}')
		return
	}

	// Unlock the renderer state so the writer thread can acquire it.
	// Then try to queue our message before continuing. This is a very
	// slow path because we are having a lot of contention for data.
	// But this only gets triggered in certain pathological cases.
	//
	// Note that writes themselves don't require a lock, but there
	// are other messages in the writer queue (resize, focus) that
	// could acquire the lock. This is why we have to release our lock
	// here.
	if mtx != unsafe { nil } {
		mtx.unlock()
	}
	defer {
		if mtx != unsafe { nil } {
			mtx.lock()
		}
	}
	_ = m.spsc.queue.push(msg, datastruct.blocking_queue_forever)
}

// Notify that there are new messages. This may be a noop depending
// on the writer type.
pub fn (mut m Mailbox) notify() {
	m.spsc.wakeup.notify() or {
		log.warn('failed to notify writer, data will be dropped err=${err}')
	}
}
