module termio

import crash
import internal_os
import log
import pty

#insert "@VMODROOT/termio/exec_reader_windows.h"

fn C.ReadFile(handle voidptr, buffer voidptr, size u32, count &u32, overlapped voidptr) bool
fn C.WriteFile(handle voidptr, buffer voidptr, size u32, count &u32, overlapped voidptr) bool
fn C.CancelIoEx(handle voidptr, overlapped voidptr) bool
fn C.witty_pty_peek(handle voidptr, available &u32) bool
fn C.TerminateProcess(handle voidptr, code u32) bool
fn C.GetLastError() u32
fn C.CloseHandle(handle voidptr) bool

fn spawn_reader(fd pty.Fd, quit internal_os.PipeFd, io &Termio) thread {
	return spawn thread_main_windows(fd, quit, io)
}

// src/termio/Exec.zig ReadThread.threadMainWindows: blocking reads are only
// interrupted by CancelIoEx; an aborted read checks the separate quit pipe.
pub fn thread_main_windows(fd pty.Fd, quit internal_os.PipeFd, io &Termio) {
	defer { C.CloseHandle(quit) }
	if io != unsafe { nil } {
		crash.set_thread_state(crash.ThreadState{
			kind:    .io
			surface: io.surface_mailbox.surface
		})
	}
	defer { if io != unsafe { nil } { crash.clear_thread_state() } }
	mut tio := unsafe { io }
	mut buf := [1024]u8{}
	for {
		for {
			mut n := u32(0)
			if !C.ReadFile(fd, &buf[0], 1024, &n, unsafe { nil }) {
				code := C.GetLastError()
				if code == 995 { break } // ERROR_OPERATION_ABORTED
				if code in [38, 109, 232] { return } // EOF or closed pipe
				log.error('io reader error err=${code}')
				panic('unexpected pty read error')
			}
			if n == 0 { return }
			if tio != unsafe { nil } {
				tio.process_output(unsafe { buf[..int(n)].clone() })
			}
		}
		mut quit_bytes := u32(0)
		if !C.witty_pty_peek(quit, &quit_bytes) {
			log.error('quit pipe reader error err=${C.GetLastError()}')
			panic('unexpected quit pipe read error')
		}
		if quit_bytes > 0 {
			log.info('read thread got quit signal')
			return
		}
	}
}
