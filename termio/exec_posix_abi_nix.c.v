module termio

import command as commandpkg
import log
import time

// C interop declarations for process management.
#include <signal.h>

#include <unistd.h>

#include <poll.h>

#include <fcntl.h>

#include <sys/wait.h>

fn C.pipe(fds voidptr) int

fn C.close(fd int) int

fn C.access(path &char, mode int) int

fn C.witty_read_retry(fd int, buf voidptr, count uint) int

fn C.witty_read_error_kind() int

fn C.write(fd int, buf voidptr, count uint) int

fn C.poll(fds voidptr, nfds u32, timeout int) int

fn C.fcntl(fd i32, cmd i32, arg ...voidptr) i32

fn C.kill(pid int, sig int) int

fn C.killpg(pgrp int, sig int) int

fn C.getpgid(pid int) int

fn C.waitpid(pid int, status &int, options int) int

fn C._exit(status int)

// Signal constants
const sig_hup = int(C.SIGHUP)

// fcntl constants
const f_getfl = int(C.F_GETFL)
const f_setfl = int(C.F_SETFL)
const o_nonblock = int(C.O_NONBLOCK)
const f_ok = int(C.F_OK)

// poll event flags
const pollin = i16(int(C.POLLIN))
const pollhup = i16(int(C.POLLHUP))

// waitpid options
const wnohang = int(C.WNOHANG)

// pollfd struct for C.poll()
struct PollFd {
mut:
	fd      i32
	events  i16
	revents i16
}


fn kill_pid(pid int) ! {
	pgid := subprocess_getpgid(pid) or { return }

	// It is possible to send a killpg between the time that
	// our child process calls setsid but before or simultaneous
	// to calling execve. In this case, the direct child dies
	// but grandchildren survive. To work around this, we loop
	// and repeatedly kill the process group until all
	// descendents are well and truly dead. We will not rest
	// until the entire family tree is obliterated.
	for {
		if C.killpg(pgid, sig_hup) != 0 {
			errno := C.errno
			mut ignore := false
			$if macos || ios {
				// killpg failed with EPERM, expected on Darwin and ignoring
				ignore = errno == C.EPERM
				if ignore {
					log.debug('killpg failed with EPERM, expected on Darwin and ignoring')
				}
			}
			if !ignore {
				log.warn('error killing process group pgid=${pgid} err=${errno}')
				return error('KillFailed')
			}
		} else {
			log.debug('process group killed pgid=${pgid}')
		}

		// See Command.zig wait for why we specify WNOHANG.
		// The gist is that it lets us detect when children
		// are still alive without blocking so that we can
		// kill them again.
		mut status := 0
		res := C.waitpid(pid, &status, wnohang)
		log.debug('waitpid result=${res}')
		if res != 0 {
			break
		}
		time.sleep(10 * time.millisecond)
	}
}

fn subprocess_getpgid(pid int) ?int {
	// Get our process group ID. Before the child pid calls setsid
	// the pgid will be ours because we forked it. Its possible that
	// we may be calling this before setsid if we are killing a surface
	// VERY quickly after starting it.
	my_pgid := C.getpgid(0)

	// We loop while pgid == my_pgid. The expectation if we have a valid
	// pid is that setsid will eventually be called because it is the
	// FIRST thing the child process does and as far as I can tell,
	// setsid cannot fail. I'm sure that's not true, but I'd rather
	// have a bug reported than defensively program against it now.
	for {
		pgid := C.getpgid(pid)
		if pgid == my_pgid {
			log.warn('pgid is our own, retrying')
			time.sleep(10 * time.millisecond)
			continue
		}

		// Don't know why it would be zero but its not a valid pid
		if pgid == 0 {
			return none
		}

		// If the pid doesn't exist then... we're done!
		if pgid == C.ESRCH {
			return none
		}

		// If we have an error we're done.
		if pgid < 0 {
			log.warn('error getting pgid for kill')
			return none
		}

		return pgid
	}
	return none
}


// This runs in the forked child after Command has redirected the standard
// descriptors and before it replaces the process image.
fn subprocess_child_pre_exec(mut cmd commandpkg.Command) {
	mut subprocess := unsafe { &Subprocess(cmd.get_data()) }
	subprocess.child_pre_exec() or { log.error('error initializing child: ${err}') }
}

fn (self &Subprocess) child_pre_exec() ! {
	p := self.pty_ or { return error('subprocess pty is unavailable') }
	p.child_pre_exec()!
}

