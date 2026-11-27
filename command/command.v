module command

import internal_os
import global_state

#include "@VMODROOT/command_exec.h"

// --- Original Ghostty Comments Start: src/Command.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/Command.zig
//
// Command launches sub-processes. This is an alternate implementation to the
// Zig std.process.Child since at the time of authoring this, std.process.Child
// didn't support the options necessary to spawn a shell attached to a pty.
//
// Consequently, I didn't implement a lot of features that std.process.Child
// supports because we didn't need them. Cross-platform subprocessing is not
// a trivial thing to implement (I've done it in three separate languages now)
// so if we want to replatform onto std.process.Child I'd love to do that.
// This was just the fastest way to get something built.
//
// Issues with std.process.Child:
//
//   * No pre_exec callback for logic after fork but before exec.
//   * posix_spawn is used for Mac, but doesn't support the necessary
//     features for tty setup.
//
// Path to the command to run. This doesn't have to be an absolute path,
// because use exec functions that search the PATH, if necessary.
//
// This field is null-terminated to avoid a copy for the sake of
// adding a null terminator since POSIX systems are so common.
// Command-line arguments. It is the responsibility of the caller to set
// args[0] to the command. If args is empty then args[0] will automatically
// be set to equal path.
// Environment variables for the child process. If this is null, inherits
// the environment variables from this process. These are the exact
// environment variables to set; these are /not/ merged.
// Working directory to change to in the child process. If not set, the
// working directory of the calling process is preserved.
// The file handle to set for stdin/out/err. If this isn't set, we do
// nothing explicitly so it is up to the behavior of the operating system.
// If set, this will be executed /in the child process/ after fork but
// before exec. This is useful to setup some state in the child before the
// exec process takes over, such as signal handlers, setsid, setuid, etc.
// If set, then the process will be created attached to this pseudo console.
// `stdin`, `stdout`, and `stderr` will be ignored if set.
// User data that is sent to the callback. Set with setData and getData
// for a more user-friendly API.
// Process ID is set after start is called.
// LinuxCGroup type depends on our target OS
// The various methods a process may exit.
// Exited by normal exit call, value is exit status
// Exited by a signal, value is the signal
// Exited by a stop signal, value is signal
// Unknown exit reason, value is the status from waitpid
// Start the subprocess. This returns immediately once the child is started.
//
// After this is successful, self.pid is available.
// Use an arena allocator for the temporary allocations we need in this func.
// IMPORTANT: do all allocation prior to the fork(). I believe it is undefined
// behavior if you malloc between fork and exec. The source of the Zig
// stdlib seems to verify this as well as Go.
// Null-terminate all our arguments
// Determine our env vars
// Fork. If we have a cgroup specified on Linxu then we use clone
// Parent, return immediately.
// We are the child.
// Setup our file descriptors for std streams.
// Setup our working directory
// This can fail if we don't have permission to go to
// this directory or if due to race conditions it doesn't
// exist or any various other reasons. We don't want to
// crash the entire process if this fails so we ignore it.
// We don't log because that'll show up in the output.
// Restore any rlimits that were set by Ghostty. This might fail but
// any failures are ignored (its best effort).
// If the user requested a pre exec callback, call it now.
// Finally, replace our process.
// Note: we must use the "p"-variant of exec here because we
// do not guarantee our command is looked up already in the path.
// If we are executing this code, the exec failed. We're in the
// child process so there isn't much we can do. We try to output
// something reasonable. Its important to note we MUST NOT return
// any other error condition from here on out.
// We return a very specific error that can be detected to determine
// we're in the child.
// TODO: In the case of having FDs instead of pty, need to set up
// attributes such that the child process only inherits these handles,
// then set bInheritsHandles below.
// We use dup3 so that we can clear CLO_ON_EXEC. We do NOT want this
// file descriptor to be closed on exec since we're exactly exec-ing after
// this.
// Mac doesn't support dup3 so we use dup2. We purposely clear
// CLO_ON_EXEC for this fd.
// Wait for the command to exit and return information about how it exited.
// Block until the process exits. This returns immediately if the
// process already exited.
// We specify NOHANG because its not our fault if the process we launch
// for the tty doesn't properly waitpid its children. We don't want
// to hang the terminal over it.
// When NOHANG is specified, waitpid will return a pid of 0 if the process
// doesn't have a status to report. When that happens, it is as though the
// wait call has not been performed, so we need to keep trying until we get
// a non-zero pid back, otherwise we end up with zombie processes.
// Sets command->data to data.
// Returns command->data.
// Copied from Zig. This is a publicly exported function but there is no
// way to get it from the std package.
// Copied from Zig. This is a publicly exported function but there is no
// way to get it from the std package.
// count bytes needed
// +1 for '='
// +1 for null byte
// Copied from Zig. This function could be made public in child_process.zig instead.
// This runs in the child, so we can exit and it won't
// kill the test runner.
// Read our stdout
// Read our stdout
// Read our stdout
// Test validate an execveZ failure correctly terminates when error.ExecFailedInChild is correctly handled
//
// Incorrectly handling an error.ExecFailedInChild results in a second copy of the test process running.
// Duplicating the test process leads to weird behavior
// zig build test will hang
// test binary created via -Demit-test-exe will run 2 copies of the test suite
// If cmd.start fails with error.ExecFailedInChild it's the _child_ process that is running. If it does not
// terminate in response to that error both the parent and child will continue as if they _are_ the test suite
// process.
// I am a child process, I must not get confused and continue running the rest of the test suite.
//
// --- Original Ghostty Comments End: src/Command.zig

// Command launches sub-processes. This is an alternate implementation to
// manage subprocess spawning with PTY support.
//
// Consequently, this doesn't implement many features that a full
// subprocess library would. Cross-platform subprocessing is not
// a trivial thing to implement (it has been done in three separate
// languages now) so if we want to replatform onto a standard library
// implementation, that would be great. This was just the fastest way
// to get something built.
//
// Issues with standard library process spawning:
//
//   * No pre_exec callback for logic after fork but before exec.
//   * posix_spawn is used for Mac, but doesn't support the necessary
//     features for tty setup.

// C interop declarations for POSIX process management.
fn C.fork() int

fn C.execvp(file &char, argv &&char) int

fn C.witty_execvpe(file &char, argv &&char, envp &&char) int

fn C.waitpid(pid int, status &int, options int) int

fn C.chdir(path &char) int

fn C._exit(status int)

fn C.witty_command_setup_fd(src int, target int) int

fn C.witty_command_write_exec_error()

fn C.witty_command_start_windows(application &u16, command_line &u16, environment &u16, cwd &u16, stdin_fd int, stdout_fd int, stderr_fd int, pseudo_console voidptr, process_handle &voidptr, process_id &u32) u32

fn C.witty_command_wait_windows(process_handle voidptr, exit_code &u32) u32

// WNOHANG flag for non-blocking waitpid.
const wnohang = 1

const exec_failed_in_child_message = 'ExecFailedInChild'

// is_exec_failed_in_child identifies the one Command.start error that is
// returned only in the forked child process.
pub fn is_exec_failed_in_child(err IError) bool {
	return err.msg() == exec_failed_in_child_message
}

// WIFEXITED and friends - macros for interpreting waitpid status.
// These match the POSIX definitions on macOS and Linux.

// wifexited returns true if the child terminated normally.
fn wifexited(status int) bool {
	return (status & 0x7f) == 0
}

// wexitstatus returns the exit status of a normally terminated child.
fn wexitstatus(status int) u8 {
	return u8((status >> 8) & 0xff)
}

// wifsignaled returns true if the child was terminated by a signal.
fn wifsignaled(status int) bool {
	signal_bits := status & 0x7f
	return signal_bits != 0 && signal_bits != 0x7f
}

// wtermsig returns the signal number that caused the child to terminate.
fn wtermsig(status int) u32 {
	return u32(status & 0x7f)
}

// wifstopped returns true if the child is currently stopped.
fn wifstopped(status int) bool {
	return (status & 0xff) == 0x7f
}

// wstopsig returns the signal number that caused the child to stop.
fn wstopsig(status int) u32 {
	return u32((status >> 8) & 0xff)
}

// PreExecFn is called in the child process after fork but before exec.
// This is useful to setup some state in the child before the exec process
// takes over, such as signal handlers, setsid, setuid, etc.
pub type PreExecFn = fn (mut cmd Command)

// The various methods a process may exit.
pub type Exit = ExitNormal | ExitSignal | ExitStopped | ExitUnknown

pub struct ExitNormal {
pub:
	// Exited by normal exit call, value is exit status.
	status u32
}

pub struct ExitSignal {
pub:
	// Exited by a signal, value is the signal number.
	signal u32
}

pub struct ExitStopped {
pub:
	// Exited by a stop signal, value is signal number.
	signal u32
}

pub struct ExitUnknown {
pub:
	// Unknown exit reason, value is the raw status from waitpid.
	status u32
}

// exit_from_status interprets a raw waitpid status value and returns
// the appropriate Exit variant.
pub fn exit_from_status(status int) Exit {
	if wifexited(status) {
		return ExitNormal{
			status: u32(wexitstatus(status))
		}
	} else if wifsignaled(status) {
		return ExitSignal{
			signal: wtermsig(status)
		}
	} else if wifstopped(status) {
		return ExitStopped{
			signal: wstopsig(status)
		}
	} else {
		return ExitUnknown{
			status: u32(status)
		}
	}
}

pub struct Command {
pub mut:
	// Path to the command to run. This doesn't have to be an absolute path,
	// because we use exec functions that search the PATH, if necessary.
	path string

	// Command-line arguments. It is the responsibility of the caller to set
	// args[0] to the command. If args is empty then args[0] will automatically
	// be set to equal path.
	args []string

	// Environment variables for the child process. If this is none, inherits
	// the environment variables from this process. These are the exact
	// environment variables to set; these are /not/ merged.
	env ?map[string]string

	// Working directory to change to in the child process. If not set, the
	// working directory of the calling process is preserved.
	cwd ?string

	// File descriptors for stdin/out/err (as fd integers).
	// -1 means not set, in which case we do nothing explicitly
	// so it is up to the behavior of the operating system.
	stdin_fd  int = -1
	stdout_fd int = -1
	stderr_fd int = -1

	// If set, this will be executed /in the child process/ after fork but
	// before exec. This is useful to setup some state in the child before the
	// exec process takes over, such as signal handlers, setsid, setuid, etc.
	pre_exec ?PreExecFn

	// Linux cgroup v2 path. When set, clone3 creates the child directly in it.
	linux_cgroup ?string

	// User data pointer. Use set_data/get_data for a more user-friendly API.
	data voidptr

	// Process ID is set after start is called.
	pid ?int

	// Windows keeps a process HANDLE separately from the numeric process ID.
	process_handle voidptr

	// Optional Windows ConPTY pseudo-console handle. Standard descriptors are
	// ignored when this is set, matching Ghostty's Command.pseudo_console.
	pseudo_console voidptr
}

// start launches the subprocess. This returns immediately once the child
// is started.
//
// After this is successful, self.pid is available.
//
// On POSIX, this forks and execs. The fork/exec pattern is used instead
// of posix_spawn because we need the pre_exec callback to run between
// fork and exec (e.g. for PTY setup, setsid, signal handling, etc.).
//
// Faithful to Zig `start` which dispatches on the target OS. Windows is a
// boundary (see start_windows).
pub fn (mut self Command) start() ! {
	$if windows {
		self.start_windows()!
	} $else {
		self.start_posix()!
	}
}

// start_posix implements the POSIX fork/exec subprocess launch.
$if !windows {
	fn (mut self Command) start_posix() ! {
		// Null-terminate the argument pointers before fork. The command's argument
		// strings remain alive for the lifetime of this function.
		mut c_argv := unsafe { []&char{len: self.args.len + 1, init: &char(0)} }
		for i, arg in self.args {
			c_argv[i] = arg.str
		}

		// Build the exact environment before fork and retain its backing strings.
		// `none` represents inheritance; a present empty map is an explicitly empty
		// environment, matching Command.env's source contract.
		mut has_env := false
		env := if values := self.env {
			has_env = true
			create_null_delimited_env(values)
		} else {
			NullDelimitedEnv{}
		}

		// Fork. IMPORTANT: do all allocation prior to the fork().
		// It is undefined behavior to malloc between fork and exec.
		// Keep the source platform selection as a statement. V's checker also
		// resolves names in excluded compile-time expression branches, which
		// otherwise requires a non-Linux cgroup placeholder.
		mut pid := int(0)
		$if linux {
			if cgroup := self.linux_cgroup {
				pid = internal_os.clone_into(cgroup)!
			} else {
				pid = C.fork()
			}
		} $else {
			pid = C.fork()
		}
		if pid < 0 {
			return error('fork failed')
		}

		if pid != 0 {
			// Parent, return immediately.
			self.pid = pid
			return
		}

		// We are the child.

		// Setup our file descriptors for std streams.
		if self.stdin_fd >= 0 {
			setup_fd(self.stdin_fd, 0) or { return error(exec_failed_in_child_message) }
		}
		if self.stdout_fd >= 0 {
			setup_fd(self.stdout_fd, 1) or { return error(exec_failed_in_child_message) }
		}
		if self.stderr_fd >= 0 {
			setup_fd(self.stderr_fd, 2) or { return error(exec_failed_in_child_message) }
		}

		// Setup our working directory.
		// This can fail if we don't have permission to go to this directory
		// or if due to race conditions it doesn't exist or any various other
		// reasons. We don't want to crash the entire process if this fails
		// so we ignore it. We don't log because that'll show up in the output.
		if cwd := self.cwd {
			C.chdir(cwd.str)
		}

		// Ghostty may raise process-wide resource limits during startup. Restore
		// the inherited originals in the child before handing control to it.
		global_state.get_state().rlimits.restore()

		// If the user requested a pre exec callback, call it now.
		// This runs in the child process after fork but before exec,
		// which is useful for PTY setup, signal handling, setsid, etc.
		if pre_exec_fn := self.pre_exec {
			pre_exec_fn(mut self)
		}

		// Finally, replace our process.
		// Note: we must use the "p"-variant of exec here because we
		// do not guarantee our command is looked up already in the path.
		// We use execvp/witty_execvpe, both of which search PATH.

		// Determine our env vars. Faithful to Zig `startPosix`:
		//
		//   const envp = if (self.env) |env_map|
		//       (try createNullDelimitedEnvMap(arena, env_map)).ptr
		//   else ... std.c.environ;
		//
		// If custom environment variables were provided, we build a full
		// null-delimited `envp` array (these are the EXACT vars to set; they
		// are NOT merged with the parent environment) and use execvpe.
		// Otherwise we use execvp, which inherits the current environment.
		if has_env {
			C.witty_execvpe(self.path.str, c_argv.data, env.pointers.data)
		} else {
			C.execvp(self.path.str, c_argv.data)
		}

		// If we are executing this code, the exec failed. We're in the
		// child process so there isn't much we can do. We try to output
		// something reasonable. It's important to note we MUST NOT return
		// any other error condition from here on out - we must exit.
		C.witty_command_write_exec_error()

		// This specific error tells the caller that execution is continuing in the
		// forked child and that it must terminate instead of resuming parent logic.
		return error(exec_failed_in_child_message)
	}
}

// setup_fd preserves Command.setupFd's target-specific behavior: Linux uses
// dup3 so close-on-exec is cleared atomically, while Darwin/FreeBSD clear the
// source flag and use dup2.
fn setup_fd(src int, target int) ! {
	$if windows {
		return error('unsupported platform')
	} $else {
		if C.witty_command_setup_fd(src, target) != 0 {
			return error('unable to configure child file descriptor')
		}
	}
}

// wait waits for the command to exit and returns information about
// how it exited.
//
// If block is true, this blocks until the process exits.
// If block is false, this uses WNOHANG and polls until the process
// has a status to report. When NOHANG is specified, waitpid will
// return a pid of 0 if the process doesn't have a status to report.
// When that happens, it is as though the wait call has not been
// performed, so we need to keep trying until we get a non-zero pid
// back, otherwise we end up with zombie processes.
pub fn (self Command) wait(block bool) !Exit {
	pid := self.pid or { return error('process not started') }
	$if windows {
		_ = pid
		_ = block
		if self.process_handle == unsafe { nil } {
			return error('process handle is unavailable')
		}
		mut exit_code := u32(0)
		result := C.witty_command_wait_windows(self.process_handle, &exit_code)
		if result != 0 {
			return error('WaitForSingleObject failed with Windows error ${result}')
		}
		return Exit(ExitNormal{
			status: exit_code
		})
	} $else {
		mut status := 0
		if block {
			result := C.waitpid(pid, &status, 0)
			if result < 0 {
				return error('waitpid failed')
			}
		} else {
			// We specify NOHANG because its not our fault if the process we launch
			// for the tty doesn't properly waitpid its children. We don't want
			// to hang the terminal over it.
			for {
				result := C.waitpid(pid, &status, wnohang)
				if result < 0 {
					return error('waitpid failed')
				}
				if result != 0 {
					break
				}
				// result == 0 means no status yet, keep polling
			}
		}

		return exit_from_status(status)
	}
}

// set_data sets the user data pointer on the command.
pub fn (mut self Command) set_data(pointer voidptr) {
	self.data = pointer
}

// get_data returns the user data pointer, cast to the appropriate type.
// Returns none if the data pointer is null.
pub fn (self Command) get_data() voidptr {
	return self.data
}

// create_null_delimited_env builds a null-terminated `envp` array for use
// with execvpe from the given environment map. Each entry is a
// null-terminated "KEY=VALUE" C string, and the array itself is terminated
// by a null pointer.
//
// This is the V translation of Zig `createNullDelimitedEnvMap`. Unlike Zig,
// which builds a `[:null]?[*:0]u8`, V manages the backing string memory via
// its own allocator; we keep the interned `&char` pointers alive by storing
// the V strings for the duration of the exec (this runs in the freshly forked
// child right before exec, so no cleanup is required).
struct NullDelimitedEnv {
	entries  []string
	pointers []&char
}

fn create_null_delimited_env(env map[string]string) NullDelimitedEnv {
	mut entries := []string{cap: env.len}
	for key, val in env {
		entries << '${key}=${val}'
	}
	mut pointers := unsafe { []&char{len: entries.len + 1, init: &char(0)} }
	for i, entry in entries {
		pointers[i] = entry.str
	}
	return NullDelimitedEnv{
		entries:  entries
		pointers: pointers
	}
}

// windows_create_command_line builds a Windows command line string from an
// argv array following the standard Windows quoting/escaping rules. This is
// the V translation of Zig `windowsCreateCommandLine` (copied from the Zig
// stdlib) and is pure string logic, so it is fully portable.
fn windows_create_command_line(argv []string) string {
	mut buf := []u8{}
	for arg_i, arg in argv {
		if arg_i != 0 {
			buf << u8(` `)
		}
		// If the argument contains no special characters, emit it verbatim.
		if !arg_contains_special(arg) {
			for b in arg {
				buf << b
			}
			continue
		}
		buf << u8(`"`)
		mut backslash_count := 0
		for byte in arg {
			match byte {
				`\\` {
					backslash_count++
				}
				`"` {
					// Escape all pending backslashes (doubled) plus the quote.
					for _ in 0 .. backslash_count * 2 + 1 {
						buf << u8(`\\`)
					}
					buf << u8(`"`)
					backslash_count = 0
				}
				else {
					for _ in 0 .. backslash_count {
						buf << u8(`\\`)
					}
					buf << byte
					backslash_count = 0
				}
			}
		}
		// Double any trailing backslashes so they don't escape the closing quote.
		for _ in 0 .. backslash_count * 2 {
			buf << u8(`\\`)
		}
		buf << u8(`"`)
	}
	return buf.bytestr()
}

// arg_contains_special returns true if the argument contains any character
// that requires quoting on a Windows command line.
fn arg_contains_special(arg string) bool {
	for b in arg {
		if b == ` ` || b == `\t` || b == `\n` || b == `"` {
			return true
		}
	}
	return false
}

// create_windows_env_block builds the double-null-terminated UTF-16 block
// consumed by CreateProcessW. The map contains the exact child environment;
// it is not merged with the parent process environment.
fn create_windows_env_block(env map[string]string) []u16 {
	mut result := []u16{}
	for key, value in env {
		wide := '${key}=${value}'.to_wide()
		mut i := 0
		unsafe {
			for wide[i] != 0 {
				result << wide[i]
				i++
			}
			free(wide)
		}
		result << u16(0)
	}
	// Windows requires an extra terminator after the final entry. Ghostty
	// reserves four trailing null code units, which we preserve exactly.
	result << [u16(0), 0, 0, 0]
	return result
}

// start_windows launches the subprocess with CreateProcessW.
fn (mut self Command) start_windows() ! {
	application_w := self.path.to_wide()
	defer {
		unsafe { free(application_w) }
	}

	mut command_line_w := &u16(unsafe { nil })
	if self.args.len > 0 {
		command_line_w = windows_create_command_line(self.args).to_wide()
		defer {
			unsafe { free(command_line_w) }
		}
	}

	mut cwd_w := &u16(unsafe { nil })
	if cwd := self.cwd {
		cwd_w = cwd.to_wide()
		defer {
			unsafe { free(cwd_w) }
		}
	}

	mut environment := []u16{}
	mut environment_w := &u16(unsafe { nil })
	if values := self.env {
		environment = create_windows_env_block(values)
		environment_w = environment.data
	}

	mut process_handle := voidptr(unsafe { nil })
	mut process_id := u32(0)
	result := C.witty_command_start_windows(application_w, command_line_w, environment_w, cwd_w, self.stdin_fd, self.stdout_fd, self.stderr_fd, self.pseudo_console, &process_handle, &process_id)
	if result != 0 {
		return error('CreateProcessW failed with Windows error ${result}')
	}
	self.process_handle = process_handle
	self.pid = int(process_id)
}
