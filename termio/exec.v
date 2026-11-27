module termio

// Exec implements the logic for starting and stopping a subprocess with a
// pty as well as spinning up the necessary read thread to read from the
// pty and forward it to the Termio instance.
import apprt
import buildcfg
import build_meta
import command as commandpkg
import configpkg
import datastruct
import internal_os
import log
import os
import pty
import renderer
import terminal
import time
import xev

#include "@VMODROOT/command_exec.h"

const log_tag = 'io_exec'

// The termios poll rate in milliseconds.
const termios_poll_ms = 200

// PtyFds holds the read and write file descriptors returned on subprocess start.
pub struct PtyFds {
pub:
	read  pty.Fd
	write pty.Fd
}

// Exec holds the subprocess state for the exec backend.
pub struct Exec {
pub mut:
	// The subprocess state for our exec backend.
	subprocess Subprocess
}

// Initialize the exec state. This will NOT start it, this only sets
// up the internal state necessary to start it later.
pub fn Exec.init(cfg ExecConfig) !Exec {
	subprocess := Subprocess.init(cfg)!
	return Exec{
		subprocess: subprocess
	}
}

pub fn (mut self Exec) deinit() {
	self.subprocess.deinit()
}

// Call to initialize the terminal state as necessary for this backend.
// This is called before any termio begins. This should not be called
// after termio begins because it may put the internal terminal state
// into a bad state.
pub fn (mut self Exec) init_terminal(mut term terminal.Terminal, size renderer.Size) {
	// If we have an initial pwd requested by the subprocess, then we
	// set that on the terminal now. This allows rapidly initializing
	// new surfaces to use the proper pwd.
	if cwd := self.subprocess.cwd {
		term.set_pwd(cwd) or { log.warn('error setting initial pwd err=${err}') }
	}

	// Report the same terminal area on startup and on subsequent resizes.
	// This cannot fail because the PTY has yet to be created.
	self.resize(size.grid(), size.terminal()) or { panic('unexpected error setting initial pty size: ${err}') }
}

pub fn (mut self Exec) thread_enter(mut io Termio, mut td ThreadData) ! {
	// Start our subprocess
	pty_fds := self.subprocess.start() or {
		// If we specifically got this error then we are in the forked
		// process and our child failed to execute. If we DIDN'T
		// get this specific error then we're in the parent and
		// we need to bubble it up.
		if !commandpkg.is_exec_failed_in_child(err) {
			return err
		}

		// We're in the child. Nothing more we can do but abnormal exit.
		// The Command will output some additional information.
		C._exit(1)
		return err
	}
	// Zig's errdefers are emulated by reached defers that run until setup succeeds.
	mut ok := false
	defer {
		if !ok {
			self.subprocess.stop()
		}
	}

	// Watcher to detect subprocess exit
	mut process := ?xev.Process(none)
	process_value := self.subprocess.process or { return error('ProcessNotStarted') }
	match process_value {
		SubprocessForkExec {
			pid := process_value.command.pid or { return error('ProcessNoPid') }
			$if windows {
				// The source process watcher takes the process HANDLE, not its
				// numeric process ID. Command retains both for its public ABI.
				process = xev.Process.init(process_value.command.process_handle)!
			} $else {
				process = xev.Process.init(pid)!
			}
		}
		SubprocessFlatpak {
			// The host process cannot be watched through the local process API.
		}
	}

	defer {
		if !ok {
			if mut p := process {
				p.deinit()
			}
		}
	}

	// Track our process start time for abnormal exits
	process_start := time.sys_mono_now()

	// Create our pipe that we'll use to kill our read thread.
	// pipe[0] is the read end, pipe[1] is the write end.
	pipe := internal_os.pipe()!
	defer {
		if !ok {
			pty.close_fd(pty.Fd(pipe[0]))
			pty.close_fd(pty.Fd(pipe[1]))
		}
	}

	// Setup our stream so that we can write.
	stream := xev.Stream.init_fd(pty_fds.write)
	defer {
		if !ok {
			stream.deinit()
		}
	}

	// Start our timer to read termios state changes. This is used
	// to detect things such as when password input is being done
	// so we can render the terminal in a different way.
	termios_timer := xev.Timer.init()!
	defer {
		if !ok {
			termios_timer.deinit()
		}
	}

	// Start our read thread
	read_thread := spawn_reader(pty_fds.read, pipe[0], io)
	ok = true

	// Setup our threadata backend state to be our own
	td.backend = BackendThreadData{
		exec: ExecThreadData{
			start:            process_start
			write_stream:     stream
			process:          process
			write_req_pool:   datastruct.SegmentedPool.init[xev.WriteRequest](exec_write_req_prealloc)
			write_buf_pool:   datastruct.SegmentedPool.init[ExecWriteBuf](exec_write_req_prealloc)
			read_thread:      read_thread
			read_thread_pipe: pty.Fd(pipe[1])
			read_thread_fd:   pty_fds.read
			termios_timer:    termios_timer
		}
	}

	// Start our process watcher. If we have an xev.Process use it.
	if p := td.backend.exec.process {
		p.wait(mut td.loop, &td.backend.exec.process_wait_c, td, exec_process_exit)
	} else if current := self.subprocess.process {
		match current {
			SubprocessFlatpak {
				// If we're in Flatpak, run the special host-command watcher.
				$if linux {
					mut command := current.command
					command.wait_xev(mut td.loop, &td.backend.exec.flatpak_wait_c, td,
						exec_flatpak_exit)
				}
			}
			SubprocessForkExec {}
		}
	}

	// Start our termios timer. We don't support this on Windows.
	// Fundamentally, we could support this on Windows so we're just
	// waiting for someone to implement it.
	$if !windows {
		td.backend.exec.termios_timer.run(mut td.loop, &td.backend.exec.termios_timer_c,
			termios_poll_ms, td, exec_termios_timer)
	}
}

pub fn (mut self Exec) thread_exit(mut td ThreadData) {
	mut exec := &td.backend.exec

	if exec.exited {
		self.subprocess.external_exit()
	}
	self.subprocess.stop()

	// Quit our read thread after exiting the subprocess so that
	// we don't get stuck waiting for data to stop flowing if it is
	// a particularly noisy process.
	$if windows {
		mut written := u32(0)
		quit_byte := u8(`x`)
		if !C.WriteFile(exec.read_thread_pipe, &quit_byte, 1, &written, unsafe { nil }) {
			code := C.GetLastError()
			if code != 109 { // ERROR_BROKEN_PIPE
				log.warn('error writing to read thread quit pipe err=${code}')
			}
		}
		// Interrupt the blocking ReadFile before joining so the reader can
		// inspect the quit pipe. ERROR_NOT_FOUND means no request is pending.
		if !C.CancelIoEx(exec.read_thread_fd, unsafe { nil }) {
			code := C.GetLastError()
			if code != 1168 { log.warn('error interrupting read thread err=${code}') }
		}
	} $else {
		quit_byte := [u8(`x`)]
		if C.write(exec.read_thread_pipe, quit_byte.data, 1) < 0 {
			if C.errno != C.EPIPE {
				log.warn('error writing to read thread quit pipe err=${os.posix_get_error_msg(C.errno)}')
			}
		}
	}

	if t := exec.read_thread {
		t.wait()
	}
}

pub fn (mut self Exec) focus_gained(mut td ThreadData, focused bool) ! {
	_ = self

	mut execdata := &td.backend.exec

	if !focused {
		// Flag the timer to end on the next iteration. This is
		// a lot cheaper than doing full timer cancellation.
		execdata.termios_timer_running = false
	} else {
		// Always set this to true. There is a race condition if we lose
		// focus and regain focus before the termios timer ticks where
		// if we don't set this unconditionally the timer will end on
		// the next iteration.
		execdata.termios_timer_running = true

		// If we're focused, we want to start our termios timer. We
		// only do this if it isn't already running. We use the termios
		// callback because that'll trigger an immediate state check AND
		// start the timer.
		if execdata.termios_timer_c.state() != .active {
			_ = exec_termios_timer(td, unsafe { nil }, unsafe { nil }, none)
		}
	}
}

// resize updates the pty subprocess size.
pub fn (mut self Exec) resize(grid_size renderer.GridSize, screen_size renderer.ScreenSize) ! {
	self.subprocess.resize(grid_size, screen_size)!
}

fn exec_process_exit_common(mut td ThreadData, exit_code u32) {
	mut execdata := &td.backend.exec
	execdata.exited = true

	// Determine how long the process was running for.
	runtime_ns := time.sys_mono_now() - execdata.start
	runtime_ms := runtime_ns / u64(time.millisecond)
	log.debug('child process exited status=${exit_code} runtime=${runtime_ms}ms')

	// We always notify the surface immediately that the child has
	// exited and some metadata about the exit.
	td.surface_mailbox.push(apprt.SurfaceMessage(apprt.ChildExited{
		exit_code:  exit_code
		runtime_ms: runtime_ms
	}), datastruct.blocking_queue_forever)
}

fn exec_process_exit(td_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind, exit_code u32) xev.CallbackAction {
	if _ := r {
		panic('unreachable')
	}
	mut td := unsafe { &ThreadData(td_) }
	exec_process_exit_common(mut td, exit_code)
	return .disarm
}

fn exec_termios_timer(td_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	// log.debug("termios timer fired", .{});

	// This should never happen because we guard starting our
	// timer on windows but we want this assertion to fire if
	// we ever do start the timer on windows.
	// TODO: support on windows
	$if windows {
		panic('termios timer not implemented on Windows')
	}

	if err := r {
		match err {
			// This is sent when our timer is canceled. That's fine.
			.canceled {
				return .disarm
			}
			else {
				log.warn('error in termios timer callback err=${err}')
				panic('crash in termios timer callback')
			}
		}
	}

	mut td := unsafe { &ThreadData(td_) }
	mut exec := &td.backend.exec

	$if !windows {
		// This is kind of hacky but we rebuild a Pty struct to get the
		// termios data.
		mode := pty.Pty{
			master: exec.read_thread_fd
		}.get_mode() or {
			log.warn('error getting termios mode err=${err}')

			// If we have an error we return the default mode values
			// which are the likely values.
			pty.Mode{}
		}

		// If the mode changed, then we process it.
		if mode != exec.termios_mode {
			log.debug('termios change mode=${mode}')
			exec.termios_mode = mode

			// We assume we're in some sort of password input if we're
			// in canonical mode and not echoing. This is a heuristic.
			password_input := mode.canonical() && !mode.echo()

			// If our password input state changed on the terminal then
			// we notify the surface.
			td.renderer_state.mutex.lock()
			t := td.renderer_state.terminal_
			unchanged := t.flags.password_input() == password_input
			td.renderer_state.mutex.unlock()

			if !unchanged {
				// We have to notify the surface that we're in password input.
				// We must block on this because the balanced true/false state
				// of this is critical to apprt behavior.
				td.surface_mailbox.push(apprt.SurfaceMessagePasswordInput{ value: password_input },
					datastruct.blocking_queue_forever)
			}
		}
	}

	// Repeat the timer
	if exec.termios_timer_running {
		exec.termios_timer.run(mut td.loop, &exec.termios_timer_c, termios_poll_ms, td,
			exec_termios_timer)
	}

	return .disarm
}

pub fn (mut self Exec) queue_write(mut td ThreadData, data []u8, linefeed bool) ! {
	_ = self
	mut exec := &td.backend.exec

	// If our process is exited then we don't send any more writes.
	if exec.exited {
		return
	}

	// We go through and chunk the data if necessary to fit into
	// our cached buffers that we can queue to the stream.
	mut i := 0
	for i < data.len {
		req := exec.write_req_pool.get_grow()!
		mut buf := exec.write_buf_pool.get_grow()!
		mut slice := []u8{}
		if !linefeed {
			// The maximum end index is either the end of our data or
			// the end of our buffer, whichever is smaller.
			max := if data.len < i + exec_write_buf_len { data.len } else { i + exec_write_buf_len }

			// Fast
			len := max - i
			unsafe { vmemcpy(&buf.bytes[0], &data[i], len) }
			i = max
			slice = unsafe { (&u8(&buf.bytes[0])).vbytes(len) }
		} else {
			// Slow, have to replace \r with \r\n
			mut buf_i := 0
			for i < data.len && buf_i < exec_write_buf_len - 1 {
				ch := data[i]
				i += 1

				if ch != `\r` {
					buf.bytes[buf_i] = ch
					buf_i += 1
					continue
				}

				// CRLF
				buf.bytes[buf_i] = `\r`
				buf.bytes[buf_i + 1] = `\n`
				buf_i += 2
			}

			slice = unsafe { (&u8(&buf.bytes[0])).vbytes(buf_i) }
		}

		// for (slice) |b| log.warn("write: {x}", .{b});

		exec.write_stream.queue_write(mut td.loop, &exec.write_queue, req, xev.WriteBuffer(xev.WriteBufferSlice{
			slice: slice
		}), exec, exec_tty_write)
	}
}

fn exec_tty_write(td_ voidptr, _ &xev.Loop, _ &xev.Completion, _ xev.Stream, _ xev.WriteBuffer, r ?xev.ErrorKind, n uint) xev.CallbackAction {
	mut td := unsafe { &ExecThreadData(td_) }
	td.write_req_pool.put()
	td.write_buf_pool.put()

	if err := r {
		log.error('write error: ${err}')
		return .disarm
	}
	_ = n
	// log.info("WROTE: {d}", .{d});

	return .disarm
}

// The preallocation size for the write request pool. This should be big
// enough to satisfy most write requests. It must be a power of 2.
const exec_write_req_prealloc = 32

// The size of each pooled pty write buffer.
const exec_write_buf_len = 64

// A pooled pty write buffer (Zig's [64]u8 pool element).
pub struct ExecWriteBuf {
pub mut:
	bytes [64]u8
}

// The thread local data for the exec implementation.
pub struct ExecThreadData {
pub mut:
	// Process start time and boolean of whether its already exited.
	start  u64
	exited bool

	// The data stream is the main IO for the pty.
	write_stream xev.Stream

	// The process watcher
	process ?xev.Process

	// This is the pool of available (unused) write requests. If you grab
	// one from the pool, you must put it back when you're done!
	write_req_pool datastruct.SegmentedPool[xev.WriteRequest]

	// The pool of available buffers for writing to the pty.
	write_buf_pool datastruct.SegmentedPool[ExecWriteBuf]

	// The write queue for the data stream.
	write_queue xev.WriteQueue

	// This is used for both waiting for the process to exit and then
	// subsequently to wait for the data_stream to close.
	process_wait_c xev.Completion

	// The completion specific to Flatpak process waiting.
	flatpak_wait_c internal_os.FlatpakCompletion

	// Reader thread state
	read_thread      ?thread
	read_thread_pipe pty.Fd
	read_thread_fd   pty.Fd

	// The timer to detect termios state changes.
	termios_timer         xev.Timer
	termios_timer_c       xev.Completion
	termios_timer_running bool = true

	// The last known termios mode. Used for change detection
	// to prevent unnecessary locking of expensive mutexes.
	termios_mode pty.Mode
}

pub fn (mut self ExecThreadData) deinit() {
	pty.close_fd(self.read_thread_pipe)

	// Clear our write pools. We know we aren't ever going to do
	// any more IO since we stop our data stream below so we can just
	// drop this.
	self.write_req_pool.deinit()
	self.write_buf_pool.deinit()

	// Stop our process watcher
	if mut p := self.process {
		p.deinit()
	}

	// Stop our write stream
	self.write_stream.deinit()

	// Stop our termios timer
	self.termios_timer.deinit()
}

// ExecConfig holds the configuration for starting a subprocess.
pub struct ExecConfig {
pub:
	command                    ?configpkg.Command
	env                        map[string]string
	env_override               configpkg.RepeatableStringMap
	shell_integration          configpkg.ShellIntegration = .detect
	shell_integration_features configpkg.ShellIntegrationFeatures
	working_directory          ?string
	resources_dir              ?string
	term                       string = 'xterm-witty'
	linux_cgroup               ?string
}

// Subprocess manages the child process lifecycle.
pub struct Subprocess {
pub mut:
	cwd          ?string
	env          ?map[string]string
	args         []string
	grid_size    renderer.GridSize
	screen_size  renderer.ScreenSize
	pty_         ?pty.Pty
	process      ?SubprocessProcess
	linux_cgroup ?string
}

pub enum SubprocessProcessKind as u8 {
	fork_exec
	flatpak
}

pub struct SubprocessForkExec {
pub:
	command commandpkg.Command
}

pub struct SubprocessFlatpak {
pub:
	// The Flatpak API requires stable command storage while its asynchronous
	// watcher is active, so the active union arm owns a GC-stable pointer.
	command &internal_os.FlatpakHostCommand = unsafe { nil }
}

pub type SubprocessProcess = SubprocessForkExec | SubprocessFlatpak

pub fn (self SubprocessProcess) kind() SubprocessProcessKind {
	return match self {
		SubprocessForkExec { .fork_exec }
		SubprocessFlatpak { .flatpak }
	}
}

struct ArgsFormatter {
	args []string
}

fn (self ArgsFormatter) str() string {
	mut result := []string{cap: self.args.len}
	for arg in self.args {
		result << '`${arg}`'
	}
	return result.join(', ')
}

// Add our executable directory to the child environment. Flatpak commands run
// on the host, where a binary inside the sandbox cannot be reached.
fn add_executable_to_path(mut env map[string]string, executable string, flatpak bool) {
	if flatpak || executable.len == 0 {
		return
	}

	exe_dir := os.dir(executable)
	if exe_dir.len == 0 {
		return
	}
	log.debug('appending witty bin to path dir=${exe_dir}')

	// We always set this so that if the shell overwrites the path scripts
	// still have a way to find the Ghostty binary when running in Ghostty.
	env['GHOSTTY_BIN_DIR'] = exe_dir
	env['GHOSTTY_BIN_NAME'] = os.base(executable)

	// Append so that Ghostty is the last priority in PATH, avoiding a duplicate
	// entry when the executable directory is already present.
	if existing_path := env['PATH'] {
		for entry in existing_path.split(os.path_delimiter) {
			if entry == exe_dir {
				return
			}
		}
		env['PATH'] = internal_os.append_env(existing_path, exe_dir)
	} else {
		env['PATH'] = exe_dir
	}
}

// init initializes the subprocess configuration. This will NOT start it,
// this only sets up the internal state necessary to start it later.
pub fn Subprocess.init(cfg ExecConfig) !Subprocess {
	mut env := cfg.env.clone()

	// If we have a resources dir then set our env var
	if dir := cfg.resources_dir {
		log.info('found Witty resources dir: ${dir}')
		env['GHOSTTY_RESOURCES_DIR'] = dir
	}

	// Set our TERM var. This is a bit complicated because we want to use
	// the ghostty TERM value but we want to only do that if we have
	// ghostty in the TERMINFO database.
	//
	// For now, we just look up a bundled dir but in the future we should
	// also load the terminfo database and look for it.
	if base := cfg.resources_dir {
		env['TERM'] = cfg.term
		env['COLORTERM'] = 'truecolor'

		// Assume that the resources directory is adjacent to the terminfo
		// database
		parent := os.dir(base)
		if parent.len > 0 {
			env['TERMINFO'] = '${parent}/terminfo'
		}
	} else {
		$if macos || ios {
			log.warn('witty terminfo not found, using xterm-256color')
			log.warn('the terminfo SHOULD exist on macos, please ensure')
			log.warn("you're using a valid app bundle.")
		}
		env['TERM'] = 'xterm-256color'
		env['COLORTERM'] = 'truecolor'
	}

	// Add our binary to the path if we can find it. Skip this for Flatpak
	// because the command runs on the host and cannot reach sandbox binaries.
	add_executable_to_path(mut env, os.executable(), buildcfg.flatpak && internal_os.is_flatpak())

	// On macOS, export additional data directories from our
	// application bundle.
	$if macos || ios {
		if resources_dir := cfg.resources_dir {
			data_dir := '${resources_dir}/..'
			xdg_data_dirs_key := 'XDG_DATA_DIRS'
			existing_xdg := if v := env[xdg_data_dirs_key] {
				v
			} else {
				'/usr/local/share:/usr/share'
			}
			env[xdg_data_dirs_key] = internal_os.append_env(existing_xdg, data_dir)

			manpath_key := 'MANPATH'
			man_dir := '${resources_dir}/../man'
			// Always append with colon in front, as it mean that if
			// `MANPATH` is empty, then it should be treated as an extra
			// path instead of overriding all paths set by OS.
			existing_man := env[manpath_key] or { '' }
			env[manpath_key] = internal_os.append_env_always(existing_man, man_dir)
		}
	}

	// Set environment variables used by some programs (such as neovim) to detect
	// which terminal emulator and version they're running under.
	env['TERM_PROGRAM'] = 'witty'
	env['TERM_PROGRAM_VERSION'] = build_meta.version_string

	// VTE_VERSION is set by gnome-terminal and other VTE-based terminals.
	// We don't want our child processes to think we're running under VTE.
	env.delete('VTE_VERSION')

	// Setup our shell integration, if we can.
	default_shell_command := cfg.command or {
		$if windows {
			configpkg.ShellCmd{
				shell: 'cmd.exe'
			}
		} $else {
			configpkg.ShellCmd{
				shell: 'sh'
			}
		}
	}

	// Always set up shell features (GHOSTTY_SHELL_FEATURES). These are
	// used by both automatic and manual shell integrations.
	setup_features(mut env, cfg.shell_integration_features)

	shell_command := setup_shell_command(cfg.shell_integration, cfg.resources_dir,
		default_shell_command, mut env)!

	// Add the environment variables that override any others.
	mut it := cfg.env_override.iterator()
	for {
		entry := it.next() or { break }
		env[entry.key] = entry.value
	}

	// Build our args list
	args := exec_command(shell_command)!

	// We have to copy the cwd because there is no guarantee that
	// pointers in full_config remain valid.
	cwd := cfg.working_directory

	// Propagate the current working directory (CWD) to the shell, enabling
	// the shell to display the current directory name rather than the
	// resolved path for symbolic links.
	// https://bugs.kde.org/show_bug.cgi?id=242114
	// https://github.com/kovidgoyal/kitty/issues/1595
	// https://github.com/ghostty-org/ghostty/discussions/7769
	if pwd := cwd {
		env['PWD'] = pwd
	}

	return Subprocess{
		env:          env
		cwd:          cwd
		args:         args
		linux_cgroup: cfg.linux_cgroup
		// Should be initialized with init_terminal call.
		grid_size:    renderer.GridSize{}
		screen_size:  renderer.ScreenSize{
			width:  1
			height: 1
		}
	}
}

// Clean up the subprocess. This will stop the subprocess if it is started.
pub fn (mut self Subprocess) deinit() {
	self.stop()
	if mut p := self.pty_ {
		p.deinit()
	}
	self.env = none
}

// Start the subprocess. If the subprocess is already started this
// will assert. This forks and execs the configured command
// with the pty slave connected to stdin/stdout/stderr.
pub fn (mut self Subprocess) start() !PtyFds {
	assert self.pty_ == none && self.process == none

	// Create our pty
	mut p := pty.Pty.open(pty.Winsize{
		ws_row:    clamp_u16(self.grid_size.rows)
		ws_col:    clamp_u16(self.grid_size.columns)
		ws_xpixel: clamp_u16(self.screen_size.width)
		ws_ypixel: clamp_u16(self.screen_size.height)
	})!
	self.pty_ = p
	mut in_child := false
	mut started := false
	defer {
		if !in_child && !started {
			$if !windows {
				p.close_slave()
			}
			p.deinit()
			self.pty_ = none
		}
	}

	log.debug('starting command command=${ArgsFormatter{ args: self.args }}')

	// If we can't access the cwd, then don't use it. This is important
	// because our cwd can be set by the shell (OSC 7) and we don't
	// want to break new windows.
	cwd := if c := self.cwd {
		$if linux {
			if buildcfg.flatpak && internal_os.is_flatpak() {
				log.info('flatpak detected, will use host command to verify cwd access')
				if flatpak_cwd_accessible(c)! { c } else { '' }
			} else {
				if C.access(c.str, f_ok) == 0 {
					c
				} else {
					log.warn('cannot access cwd, ignoring: ${os.posix_get_error_msg(C.errno)}')
					''
				}
			}
		} $else $if windows {
			if windows_cwd_access(c) { c } else { '' }
		} $else {
			if C.access(c.str, f_ok) == 0 {
				c
			} else {
				log.warn('cannot access cwd, ignoring: ${os.posix_get_error_msg(C.errno)}')
				''
			}
		}
	} else {
		''
	}

	if self.args.len == 0 {
		return error('no command specified')
	}

	// Flatpak cannot fork a sandbox child into the host namespace. Use the
	// Development portal with the same argv, environment, cwd, and PTY slave
	// descriptors as the pinned implementation.
	$if linux {
		if internal_os.is_flatpak() {
			if !buildcfg.flatpak {
				log.warn('flatpak detected, but flatpak support not built-in')
			} else {
				mut command := &internal_os.FlatpakHostCommand{
					argv:   self.args
					cwd:    if cwd.len > 0 { cwd } else { none }
					env:    self.env
					stdin:  p.slave
					stdout: p.slave
					stderr: p.slave
				}
				pid := command.spawn()!
				self.process = SubprocessProcess(SubprocessFlatpak{
					command: command
				})
				log.info('started subcommand on host via flatpak API path=${self.args[0]} pid=${pid}')
				$if !windows {
					p.close_slave()
				}
				self.env = none
				started = true
				return PtyFds{
					read:  p.master
					write: p.master
				}
			}
		}
	}

	// Build and start the shared Command translation used by Ghostty's exec
	// backend. Command owns the fork/exec, environment, descriptor, cgroup,
	// working-directory, and pre-exec contracts.
	mut cmd := commandpkg.Command{
		path:         self.args[0]
		args:         self.args
		env:          self.env
		cwd:          if cwd.len > 0 { cwd } else { none }
		linux_cgroup: self.linux_cgroup
		data:         voidptr(self)
	}
	$if windows {
		cmd.pseudo_console = p.pseudo_console
	} $else {
		cmd.stdin_fd = p.slave
		cmd.stdout_fd = p.slave
		cmd.stderr_fd = p.slave
		cmd.pre_exec = subprocess_child_pre_exec
	}

	cmd.start() or {
		if commandpkg.is_exec_failed_in_child(err) {
			in_child = true
			return err
		}
		return err
	}
	self.process = SubprocessProcess(SubprocessForkExec{
		command: cmd
	})
	log.info('started subcommand path=${self.args[0]} pid=${cmd.pid}')
	$if linux {
		log.info('subcommand cgroup=${self.linux_cgroup or { '-' }}')
	}

	// Close the slave fd in the parent. The child has already
	// inherited it via fork and duped it to stdin/stdout/stderr.
	$if !windows {
		p.close_slave()
	}

	// We can free the env now that the child has it.
	self.env = none
	started = true

	$if windows {
		return PtyFds{ read: p.out_pipe, write: p.in_pipe }
	} $else {
		return PtyFds{ read: p.master, write: p.master }
	}
}

// Called to notify that we exited externally so we can unset our
// running state.
pub fn (mut self Subprocess) external_exit() {
	self.process = none
}

// Stop the subprocess. This is safe to call anytime. This will send
// SIGHUP to the process group to signal it to exit.
// This does not close the pty.
pub fn (mut self Subprocess) stop() {
	process := self.process or { return }
	match process {
		SubprocessForkExec {
			// Note: this will also wait for the command to exit, so
			// DO NOT call cmd.wait.
			kill_command(process.command) or {
				log.error('error sending SIGHUP to command, may hang: ${err}')
			}
		}
		SubprocessFlatpak {
			$if linux {
				mut command := process.command
				kill_command_flatpak(mut command) or {
					log.error('error sending SIGHUP to command, may hang: ${err}')
				}
				_ = command.wait() or {
					log.error('error waiting for command to exit: ${err}')
					u8(0)
				}
			}
		}
	}

	self.process = none
}

// Kill the underlying subprocess. This sends a SIGHUP to the child
// process. This also waits for the command to exit and will return the
// exit code.
fn kill_command(command commandpkg.Command) ! {
	if pid := command.pid {
		$if windows {
			if !C.TerminateProcess(command.process_handle, 0) {
				return error('Unexpected: ${C.GetLastError()}')
			}
			mut cmd := command
			_ = cmd.wait(false)!
		} $else {
			kill_pid(pid)!
		}
	}
}

// Resize the pty subprocess. This is safe to call anytime.
pub fn (mut self Subprocess) resize(grid_size renderer.GridSize, screen_size renderer.ScreenSize) ! {
	self.grid_size = grid_size
	self.screen_size = screen_size

	if mut p := self.pty_ {
		// It is theoretically possible for the grid or screen size to
		// exceed u16, although the terminal in that case isn't very
		// usable. This should be protected upstream but we still clamp
		// in case there is a bad caller which has happened before.
		p.set_size(pty.Winsize{
			ws_row:    clamp_u16(grid_size.rows)
			ws_col:    clamp_u16(grid_size.columns)
			ws_xpixel: clamp_u16(screen_size.width)
			ws_ypixel: clamp_u16(screen_size.height)
		})!
	}
}

// clamp_u16 clamps a u32 value to u16 range.
fn clamp_u16(v u32) u16 {
	if v > 0xFFFF {
		return 0xFFFF
	}
	return u16(v)
}

// The read thread sits in a loop doing the following pseudo code:
//
//   while (true) { blocking_read(); exit_if_eof(); process(); }
//
// Almost all terminal-modifying activity is from the pty read, so
// putting this on a dedicated thread keeps performance very predictable
// while also almost optimal. "Locking is fast, lock contention is slow."
// and since we rarely have contention, this is fast.
//
// This is also empirically fast compared to putting the read into
// an async mechanism like io_uring/epoll because the reads are generally
// small.
//
// We use a basic poll syscall here because we are only monitoring two
// fds and this is still much faster and lower overhead than any async
// mechanism.
pub struct ReadThread {}

// thread_main_posix is the main function for the POSIX read thread.
// It reads data from the pty fd in a tight loop, falling back to poll()
// when there is no data available. The quit fd is checked during poll
// to allow clean shutdown. Each chunk of data read is forwarded to the
// Termio's process_output which parses the escape codes and mutates the
// terminal state.
//
// io may be null (e.g. in tests / non-wired usage) in which case data is
// simply drained.

// setup_shell_command handles the shell integration dispatch based on the
// configured shell integration mode and resources directory.
fn setup_shell_command(integration configpkg.ShellIntegration, resources_dir ?string, default_cmd configpkg.Command, mut env map[string]string) !configpkg.Command {
	if integration == .none_ {
		// This is a source of confusion for users despite being
		// opt-in since it results in some Ghostty features not
		// working. We always want to log it.
		log.info('shell integration disabled by configuration')
		return default_cmd
	}

	dir := resources_dir or {
		log.warn('no resources dir set, shell integration disabled')
		return default_cmd
	}

	force := match integration {
		.detect {
			?Shell(none)
		}
		.bash {
			?Shell(Shell.bash)
		}
		.elvish {
			?Shell(Shell.elvish)
		}
		.fish {
			?Shell(Shell.fish)
		}
		.nushell {
			?Shell(Shell.nushell)
		}
		.zsh {
			?Shell(Shell.zsh)
		}
		.none_ { // handled above
			?Shell(none)
		}
	}

	integration_result := setup(dir, default_cmd, mut env, force)!
	result := integration_result.value or {
		log.warn('shell could not be detected, no automatic shell integration will be injected')
		return default_cmd
	}

	log.info('shell integration automatically injected shell=${result.shell}')

	return result.command
}

// Builds the argv array for the process we should exec for the
// configured command. This isn't as straightforward as it seems since
// we deal with shell-wrapping, macOS login shells, etc.
//
// On macOS, we use login(1) to get all of the proper environment
// variables set, a login shell, and proper hushlogin behavior.
// On other platforms, we wrap shell commands with the platform shell.
fn exec_command(command configpkg.Command) ![]string {
	// If we're on macOS, we have to use `login(1)` to get all of
	// the proper environment variables set, a login shell, and proper
	// hushlogin behavior.
	$if macos || ios {
		passwd := internal_os.get() or {
			log.warn('failed to read passwd, not using a login shell err=${err}')
			return exec_command_posix(command)
		}

		username := passwd.name or {
			log.warn('failed to get username, not using a login shell')
			return exec_command_posix(command)
		}

		hush := if h := passwd.home {
			if !os.is_dir(h) {
				log.warn('failed to open home dir, not checking for hushlogin')
				false
			} else {
				os.exists(os.join_path(h, '.hushlogin'))
			}
		} else {
			false
		}

		// The reason for executing login this way is unclear. This
		// comment will attempt to explain but prepare for a truly
		// unhinged reality.
		//
		// The first major issue is that on macOS, a lot of users
		// put shell configurations in ~/.bash_profile instead of
		// ~/.bashrc (or equivalent for another shell). This file is only
		// loaded for a login shell so macOS users expect all their terminals
		// to be login shells. No other platform behaves this way and its
		// totally braindead but somehow the entire dev community on
		// macOS has cargo culted their way to this reality so we have to
		// do it...
		//
		// To get a login shell, you COULD just prepend argv0 with a `-`
		// but that doesn't fully work because `getlogin()` C API will
		// return the wrong value, SHELL won't be set, and various
		// other login behaviors that macOS users expect.
		//
		// The proper way is to use `login(1)`. But login(1) forces
		// the working directory to change to the home directory,
		// which we may not want. If we specify "-l" then we can avoid
		// this behavior but now the shell isn't a login shell.
		//
		// There is another issue: `login(1)` on macOS 14.3 and earlier
		// checked for ".hushlogin" in the working directory. This means
		// that if we specify "-l" then we won't get hushlogin honored
		// if its in the home directory (which is standard). To get
		// around this, we check for hushlogin ourselves and if present
		// specify the "-q" flag to login(1).
		//
		// So to get all the behaviors we want, we specify "-l" but
		// execute "bash" (which is built-in to macOS). We then use
		// the bash builtin "exec" to replace the process with a login
		// shell ("-l" on exec) with the command we really want.
		//
		// We use "bash" instead of other shells that ship with macOS
		// because as of macOS Sonoma, we found with a microbenchmark
		// that bash can `exec` into the desired command ~2x faster
		// than zsh.
		//
		// To figure out a lot of this logic I read the login.c
		// source code in the OSS distribution Apple provides for
		// macOS.
		//
		// Awesome.
		mut args := []string{}
		args << '/usr/bin/login'
		if hush {
			args << '-q'
		}
		args << '-flp'
		args << username

		match command {
			configpkg.DirectCmd {
				// Direct args can be passed directly to login, since
				// login uses execvp we don't need to worry about PATH
				// searching.
				for a in command.direct {
					args << a
				}
			}
			configpkg.ShellCmd {
				// Use "exec" to replace the bash process with
				// our intended command so we don't have a parent
				// process hanging around.
				cmd_str := 'exec -l ${command.shell}'

				// We execute bash with "--noprofile --norc" so that it doesn't
				// load startup files so that (1) our shell integration doesn't
				// break and (2) user configuration doesn't mess this process
				// up.
				args << '/bin/bash'
				args << '--noprofile'
				args << '--norc'
				args << '-c'
				args << cmd_str
			}
		}

		return args
	}

	$if windows {
		return match command {
			configpkg.DirectCmd {
				// We need to clone the command since there's no guarantee the
				// config remains valid.
				command.direct.clone()
			}
			configpkg.ShellCmd {
				// We run our shell wrapped in `cmd.exe` so that we don't have
				// to parse the command line ourselves if it has arguments.
				windir := os.getenv_opt('WINDIR') or {
					log.warn('failed to get WINDIR, cannot run shell command')
					return error('SystemError')
				}
				[
					os.join_path(windir, 'System32', 'cmd.exe'),
					'/C',
					command.shell,
				]
			}
		}
	}

	return exec_command_posix(command)
}

// exec_command_posix builds the command args for non-macOS platforms.
fn exec_command_posix(command configpkg.Command) []string {
	match command {
		configpkg.DirectCmd {
			// We need to clone the command since there's no guarantee the
			// config remains valid.
			return command.direct.clone()
		}
		configpkg.ShellCmd {
			mut args := []string{}
			// We run our shell wrapped in `/bin/sh` so that we don't have
			// to parse the command line ourselves if it has arguments.
			// Additionally, some environments (NixOS, I found) use /bin/sh
			// to setup some environment variables that are important to
			// have set.
			args << '/bin/sh'
			if internal_os.is_flatpak() {
				args << '-l'
			}
			args << '-c'
			args << command.shell
			return args
		}
	}
}
