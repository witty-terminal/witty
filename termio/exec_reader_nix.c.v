module termio

import crash
import internal_os
import log
import os
import pty

fn spawn_reader(fd pty.Fd, quit internal_os.PipeFd, io &Termio) thread {
	return spawn thread_main_posix(fd, quit, io)
}

pub fn thread_main_posix(fd int, quit int, io &Termio) {
	// Always close our end of the pipe when we exit.
	defer {
		C.close(quit)
	}

	$if macos || ios {
		internal_os.set_thread_name('io-reader')
	}

	has_crash_state := io != unsafe { nil }
	if has_crash_state {
		crash.set_thread_state(crash.ThreadState{
			kind:    .io
			surface: io.surface_mailbox.surface
		})
	}
	defer {
		if has_crash_state {
			crash.clear_thread_state()
		}
	}

	// Take a mutable alias to the Termio so we can call process_output.
	mut tio := unsafe { io }

	// Set the fd to non-blocking so we can try to read in a tight loop
	// and only fall back to poll when there's no data.
	flags := C.fcntl(fd, f_getfl, 0)
	if flags >= 0 {
		if C.fcntl(fd, f_setfl, flags | o_nonblock) < 0 {
			log.warn('read thread failed to set flags err=${os.posix_get_error_msg(C.errno)}')
			log.warn("this isn't a fatal error, but may cause performance issues")
		}
	} else {
		log.warn('read thread failed to get flags err=${os.posix_get_error_msg(C.errno)}')
		log.warn("this isn't a fatal error, but may cause performance issues")
	}

	// Build up the list of fds we're going to poll. We watch for data
	// on the pty fd and our quit notification pipe.
	mut pollfds := [2]PollFd{}
	pollfds[0] = PollFd{
		fd:      i32(fd)
		events:  pollin
		revents: 0
	}
	pollfds[1] = PollFd{
		fd:      i32(quit)
		events:  pollin
		revents: 0
	}

	mut buf := [1024]u8{}
	for {
		// Inner loop: try to read as much as possible without blocking.
		// We only check the quit fd when the main fd blocks. This optimizes
		// for the realistic scenario that data will eventually stop while
		// we're trying to quit.
		for {
			n := C.witty_read_retry(fd, &buf[0], uint(1024))
			if n < 0 {
				match C.witty_read_error_kind() {
					// No more data, fall back to poll and check for exit
					// conditions.
					1 {
						break
					}
					// The pty is closed. We're probably gracefully shutting down.
					2 {
						log.info('io reader exiting')
						return
					}
					// The pinned implementation treats all other read errors as
					// unreachable because continuing would hide an IO failure.
					else {
						log.error('io reader error err=${os.posix_get_error_msg(C.errno)}')
						panic('unexpected pty read error')
					}
				}
			}
			if n == 0 {
				// EOF - this happens on macOS when the child process dies.
				break
			}
			// Successfully read data. Forward it to the Termio for
			// processing (escape-code parsing + terminal state mutation).
			if tio != unsafe { nil } {
				chunk := unsafe { buf[..int(n)].clone() }
				tio.process_output(chunk)
			}
		}

		// Wait for data using poll with infinite timeout (-1).
		pollfds[0].revents = 0
		pollfds[1].revents = 0
		poll_result := C.poll(&pollfds[0], u32(2), -1)
		if poll_result < 0 {
			errno := C.errno
			if errno == C.EINTR {
				continue
			}
			log.warn('poll failed on read thread, exiting early err=${os.posix_get_error_msg(errno)}')
			return
		}

		// If our quit fd is readable, we're done.
		if pollfds[1].revents & pollin != 0 {
			log.info('read thread got quit signal')
			return
		}

		// If the pty fd has HUP, the child process has closed the pty.
		if pollfds[0].revents & pollhup != 0 {
			log.info('pty fd closed, read thread exiting')
			return
		}
	}
}
