module pty

import log
import os

// Pty is a pseudo-terminal abstraction. This provides a cross-platform
// interface for creating and managing pseudo-terminals (PTYs).
//
// On POSIX systems, this wraps the openpty/ioctl/tcgetattr family of
// calls. The C shim selects the correct macOS or Linux headers/constants.
//
// The PTY is used to connect a terminal emulator to a subprocess (shell).
// The master side is read/written by the terminal emulator, and the slave
// side is connected to the child process's stdin/stdout/stderr.

// C interop declarations.
// We declare the C functions we need for PTY management. These are
// available on macOS (via <util.h>) and Linux (via <pty.h>).
#include "pty_shims.h"

#flag linux -lutil
#flag freebsd -lutil

fn C.openpty(master &i32, slave &i32, name &char, termp voidptr, winp voidptr) int

fn C.close(fd int) int

fn C.setsid() int

fn C.fcntl(fd i32, cmd i32, arg ...voidptr) i32

fn C.witty_pty_enable_utf8(fd int) int

fn C.witty_pty_get_mode(fd int, canonical &int, echo &int) int

fn C.witty_pty_get_size(fd int, row &u16, col &u16, xpixel &u16, ypixel &u16) int

fn C.witty_pty_set_size(fd int, row u16, col u16, xpixel u16, ypixel u16) int

fn C.witty_pty_set_controlling_terminal(fd int) int

fn C.witty_pty_reset_signals() int

// fcntl constants
const f_getfd = 1
const f_setfd = 2
const fd_cloexec = 1

// Pty represents the pseudo-terminal with master and slave file descriptors.
//
// The file descriptors for the master and slave side of the pty.
// The slave side is never closed automatically by this struct
// so the caller is responsible for closing it if things go wrong.
pub struct Pty {
pub mut:
	// The master file descriptor (read/write end for the parent process).
	master int = -1
	// The slave file descriptor (connected to the child process).
	slave int = -1
}

// Fd is a file descriptor type alias.
pub type Fd = int

// open creates a new PTY with the given initial size.
//
// This uses the POSIX openpty() call to create a master/slave pair,
// then sets CLOEXEC on the master fd (only the slave should be inherited
// by the child process), and enables UTF-8 mode via IUTF8.
pub fn Pty.open(size Winsize) !Pty {
	// Need to copy so that it becomes non-const for the C call.
	mut size_copy := size

	mut master_fd := i32(-1)
	mut slave_fd := i32(-1)
	if C.openpty(&master_fd, &slave_fd, unsafe { nil }, unsafe { nil }, voidptr(&size_copy)) < 0 {
		return error('openpty failed')
	}

	// From this point until ownership is returned, both descriptors belong to
	// this function. Ghostty's errdefer closes the pair if termios setup fails.
	// Keep that failure atomic here as well so callers never receive a PTY whose
	// required UTF-8 mode was not installed.

	// Set CLOEXEC on the master fd, only the slave fd should be inherited
	// by the child process (shell/command).
	flags := C.fcntl(master_fd, f_getfd, 0)
	if flags < 0 {
		log.warn('error getting flags for master fd err=${os.last_error()}')
	} else if C.fcntl(master_fd, f_setfd, flags | fd_cloexec) < 0 {
		log.warn('error setting CLOEXEC on master fd err=${os.last_error()}')
	}

	// Enable UTF-8 mode. This is on by default on Linux but it
	// is NOT on by default on macOS so we ensure that it is always set.
	if C.witty_pty_enable_utf8(master_fd) != 0 {
		C.close(slave_fd)
		C.close(master_fd)
		return error('openpty failed')
	}

	return Pty{
		master: master_fd
		slave:  slave_fd
	}
}

// deinit closes the master file descriptor of the pty.
// The caller is responsible for having already closed the slave fd
// if needed (typically the child process inherits and closes it).
pub fn (mut self Pty) deinit() {
	if self.master >= 0 {
		C.close(self.master)
		self.master = -1
	}
}

// close_slave closes the slave file descriptor.
// This is typically called after the child process has been forked
// and the slave fd is no longer needed in the parent.
pub fn (mut self Pty) close_slave() {
	if self.slave >= 0 {
		C.close(self.slave)
		self.slave = -1
	}
}

// get_mode reads the current termios mode from the pty master.
// Returns the simplified Mode struct with canonical and echo flags.
pub fn (self Pty) get_mode() !Mode {
	mut canonical := 0
	mut echo := 0
	if C.witty_pty_get_mode(self.master, &canonical, &echo) != 0 {
		return error('tcgetattr failed')
	}

	return Mode.init(canonical != 0, echo != 0)
}

// get_size returns the current size of the pty.
// Uses the TIOCGWINSZ ioctl to query the kernel for the current
// terminal window size.
pub fn (self Pty) get_size() !Winsize {
	mut ws := Winsize{}
	if C.witty_pty_get_size(self.master, &ws.ws_row, &ws.ws_col, &ws.ws_xpixel, &ws.ws_ypixel) != 0 {
		return error('ioctl TIOCGWINSZ failed')
	}
	return ws
}

// set_size updates the pty window size.
// Uses the TIOCSWINSZ ioctl to inform the kernel of the new
// terminal window size. This will cause a SIGWINCH signal to be
// sent to the foreground process group of the terminal.
pub fn (mut self Pty) set_size(size Winsize) ! {
	if C.witty_pty_set_size(self.master, size.ws_row, size.ws_col, size.ws_xpixel, size.ws_ypixel) != 0 {
		return error('ioctl TIOCSWINSZ failed')
	}
}

// child_pre_exec performs child-side pty setup after fork, before exec.
//
// This should be called prior to exec in the forked child process
// in order to setup the tty properly. It:
//   1. Creates a new session via setsid() (so the child is a session leader)
//   2. Sets the slave fd as the controlling terminal via TIOCSCTTY
//   3. Closes both the master and slave fds (they're no longer needed
//      in the child after dup2 has been called for stdin/stdout/stderr)
//
pub fn (self Pty) child_pre_exec() ! {
	// A fork inherits the parent's signal dispositions. Restore every signal
	// Ghostty resets before launching the child so the shell cannot inherit
	// ignored or application-specific handlers. The source deliberately ignores
	// the individual sigaction return values.
	C.witty_pty_reset_signals()

	// Create a new process group / session.
	if C.setsid() < 0 {
		return error('setsid failed')
	}

	// Set controlling terminal. The slave fd becomes the controlling
	// terminal for the new session.
	if C.witty_pty_set_controlling_terminal(self.slave) != 0 {
		log.error('error setting controlling terminal errno=${os.last_error()}')
		return error('ioctl TIOCSCTTY failed: could not set controlling terminal')
	}

	// Can close master/slave pair now. The child process has already
	// had its stdin/stdout/stderr redirected to the slave fd via dup2
	// in the Command.start() call.
	C.close(self.slave)
	C.close(self.master)
}

// std.posix.close owns a native descriptor on each target.
pub fn close_fd(fd Fd) { C.close(fd) }
