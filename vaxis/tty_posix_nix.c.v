module vaxis

import log
import os
import term.termios

#flag -I @VMODROOT/vaxis
#include "tty_winch.h"
#include <fcntl.h>
#include <errno.h>
#include "@VMODROOT/internal_os/posix_poll.h"
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

fn C.witty_posix_poll(fds voidptr, nfds u32, timeout int) int

fn C.read(fd int, buf voidptr, count uint) int

fn C.write(fd int, buf voidptr, count uint) int

fn C.witty_vaxis_install_winch()

fn C.witty_vaxis_reset_winch()

fn C.witty_vaxis_notify_winch(context voidptr, callback voidptr) int

struct TtyPollFd {
mut:
	fd      int
	events  i16
	revents i16
}

struct C.winsize {
pub mut:
	ws_row    u16
	ws_col    u16
	ws_xpixel u16
	ws_ypixel u16
}

// PosixTty.init in pinned vaxis opens the controlling terminal and installs
// raw mode once, retaining the original termios until deinit.
fn Tty.open_posix() !Tty {
	fd := C.open(c'/dev/tty', C.O_RDWR, 0)
	if fd < 0 {
		return error('open /dev/tty failed')
	}
	mut original := termios.Termios{}
	if termios.tcgetattr(fd, mut original) != 0 {
		C.close(fd)
		return error('tcgetattr failed')
	}
	mut raw := original
	raw.c_iflag &=
		termios.invert(termios.flag(int(C.IGNBRK) | int(C.BRKINT) | int(C.PARMRK) | int(C.ISTRIP) | int(C.INLCR) | int(C.IGNCR) | int(C.ICRNL) | int(C.IXON)))
	raw.c_oflag &= termios.invert(termios.flag(int(C.OPOST)))
	raw.c_lflag &=
		termios.invert(termios.flag(int(C.ECHO) | int(C.ECHONL) | int(C.ICANON) | int(C.ISIG) | int(C.IEXTEN)))
	raw.c_cflag &= termios.invert(termios.flag(int(C.CSIZE) | int(C.PARENB)))
	raw.c_cflag |= termios.flag(int(C.CS8))
	raw.c_cc[int(C.VMIN)] = 1
	raw.c_cc[int(C.VTIME)] = 0
	if termios.tcsetattr(fd, C.TCSAFLUSH, mut raw) != 0 {
		C.close(fd)
		return error('tcsetattr failed')
	}
	C.witty_vaxis_install_winch()
	return Tty{
		pending:        []u8{cap: 1024}
		fd:             fd
		original_state: original
	}
}

pub fn Tty.notify_winsize(context voidptr, callback voidptr) ! {
	if C.witty_vaxis_notify_winch(context, callback) == 0 {
		return error('OutOfMemory')
	}
}

pub fn Tty.reset_winsize_handler() {
	C.witty_vaxis_reset_winch()
}

pub fn (mut tty Tty) deinit() {
	if tty.fd >= 0 {
		mut original := tty.original_state
		if termios.tcsetattr(tty.fd, C.TCSAFLUSH, mut original) != 0 {
			log.error('could not restore terminal: ${os.posix_get_error_msg(C.errno)}')
		}
		$if !macos {
			C.close(tty.fd)
			tty.fd = -1
		}
		// Source leaves /dev/tty open on macOS; repeated deinit restores the
		// retained original state and its writer remains usable.
	}
}

pub fn (tty &Tty) get_winsize() !Winsize {
	mut size := C.winsize{}
	if termios.ioctl(tty.fd, u64(C.TIOCGWINSZ), &size) != 0 {
		return error('ioctl TIOCGWINSZ failed')
	}
	return Winsize{
		rows:    size.ws_row
		cols:    size.ws_col
		x_pixel: size.ws_xpixel
		y_pixel: size.ws_ypixel
	}
}

pub fn (tty &Tty) write(bytes string) ! {
	mut written := 0
	for written < bytes.len {
		count := C.write(tty.fd, unsafe { bytes.str + written }, uint(bytes.len - written))
		if count < 0 {
			if C.errno == C.EINTR {
				continue
			}
			return error('write /dev/tty failed')
		}
		if count == 0 {
			return error('write /dev/tty returned zero')
		}
		written += int(count)
	}
}

// PosixTty.read: return after each raw read, including ignored parser reports.
pub fn (tty &Tty) read(mut buf []u8) !uint {
	for {
		count := C.read(tty.fd, buf.data, uint(buf.len))
		if count < 0 {
			if C.errno == C.EINTR {
				continue
			}
			return error('read /dev/tty failed')
		}
		return uint(count)
	}
	panic('unreachable')
}

fn (mut tty Tty) poll_posix() {
	mut pfd := TtyPollFd{
		fd:     tty.fd
		events: i16(C.POLLIN)
	}
	for C.witty_posix_poll(&pfd, 1, 0) > 0 && pfd.revents & i16(C.POLLIN) != 0 {
		mut buf := [1024]u8{}
		count := C.read(tty.fd, &buf[0], uint(buf.len))
		if count <= 0 {
			break
		}
		for i in 0 .. int(count) {
			tty.pending << buf[i]
		}
		pfd.revents = 0
	}
}

pub fn (mut tty Tty) next_input() !InputEvent {
	for {
		if event := tty.parse_pending() {
			return event
		}
		mut buf := [1024]u8{}
		count := C.read(tty.fd, &buf[0], uint(buf.len))
		if count < 0 {
			if C.errno == C.EINTR {
				continue
			}
			return error('read /dev/tty failed')
		}
		if count == 0 {
			return error('read /dev/tty returned zero')
		}
		for i in 0 .. int(count) {
			tty.pending << buf[i]
		}
	}
	panic('unreachable')
}
