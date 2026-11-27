module pty

import sync.stdatomic

// src/pty.zig WindowsPty, Ghostty 6c0e02d. Win32 structures are declared by
// the SDK; ownership, failure cleanup, naming, and ConPTY setup stay in V.
#flag windows -DNTDDI_VERSION=0x0A000006
#include <windows.h>

pub type Fd = voidptr

@[typedef]
struct C.SECURITY_ATTRIBUTES {
mut:
	nLength              u32
	lpSecurityDescriptor voidptr
	bInheritHandle       int
}

@[typedef]
pub struct C.COORD {
pub mut:
	X i16
	Y i16
}

fn C.CreateNamedPipeW(name &u16, open_mode u32, pipe_mode u32, instances u32, out_size u32, in_size u32, timeout u32, attributes &C.SECURITY_ATTRIBUTES) voidptr
fn C.CreateFileW(name &u16, access u32, share u32, attributes &C.SECURITY_ATTRIBUTES, disposition u32, flags u32, template_ voidptr) voidptr
fn C.CreatePipe(read &voidptr, write &voidptr, attributes voidptr, size u32) bool
fn C.SetHandleInformation(handle voidptr, mask u32, flags u32) bool
fn C.CreatePseudoConsole(size C.COORD, input voidptr, output voidptr, flags u32, console &voidptr) int
fn C.ResizePseudoConsole(console voidptr, size C.COORD) int
fn C.ClosePseudoConsole(console voidptr)
fn C.GetCurrentProcessId() u32
fn C.CloseHandle(handle voidptr) bool
fn C.GetLastError() u32

struct PipeNameCounter {
mut:
	value u32 = 1
}

const pipe_name_counter = &PipeNameCounter{}

pub struct Pty {
pub mut:
	out_pipe       voidptr
	in_pipe        voidptr
	out_pipe_pty   voidptr
	in_pipe_pty    voidptr
	pseudo_console voidptr
	size           Winsize
}

pub fn Pty.open(size Winsize) !Pty {
	mut counter := unsafe { pipe_name_counter }
	// The native atomic_fetch_add returns the old value, like Zig fetchAdd.
	serial := C.atomic_fetch_add_u32(&counter.value, 1)
	path := '\\\\.\\pipe\\LOCAL\\witty-pty-${C.GetCurrentProcessId()}-${serial}'
	assert path.len < 128
	path_w := path.to_wide()
	attributes := C.SECURITY_ATTRIBUTES{
		nLength: u32(sizeof(C.SECURITY_ATTRIBUTES))
	}
	mut p := Pty{ size: size }
	mut success := false
	defer {
		if !success {
			// Reverse the source errdefer registrations. A failed open never
			// returns ownership and never closes an uninitialized handle.
			if p.out_pipe != unsafe { nil } && p.out_pipe != voidptr(uint(-1)) {
				C.CloseHandle(p.out_pipe)
				C.CloseHandle(p.out_pipe_pty)
			}
			if p.in_pipe_pty != unsafe { nil } && p.in_pipe_pty != voidptr(uint(-1)) {
				C.CloseHandle(p.in_pipe_pty)
			}
			if p.in_pipe != unsafe { nil } && p.in_pipe != voidptr(uint(-1)) {
				C.CloseHandle(p.in_pipe)
			}
		}
	}
	p.in_pipe = C.CreateNamedPipeW(path_w, u32(0x00000002 | 0x00080000 | 0x40000000),
		0, 1, 4096, 4096, 0, &attributes)
	if p.in_pipe == voidptr(uint(-1)) { return error('Unexpected: ${C.GetLastError()}') }
	mut read_attributes := attributes
	p.in_pipe_pty = C.CreateFileW(path_w, 0x80000000, 0, &read_attributes,
		3, 0x00000080, unsafe { nil })
	if p.in_pipe_pty == voidptr(uint(-1)) { return error('Unexpected: ${C.GetLastError()}') }
	// The input uses an overlapped named pipe; anonymous pipes cannot be used
	// with the libxev IOCP writer. The output reader remains blocking.
	if !C.CreatePipe(&p.out_pipe, &p.out_pipe_pty, unsafe { nil }, 0) {
		return error('Unexpected: ${C.GetLastError()}')
	}
	for handle in [p.in_pipe, p.in_pipe_pty, p.out_pipe, p.out_pipe_pty] {
		if !C.SetHandleInformation(handle, 1, 0) {
			return error('Unexpected: ${C.GetLastError()}')
		}
	}
	assert size.ws_col <= 0x7fff && size.ws_row <= 0x7fff
	mut coord := C.COORD{}
	coord.X = i16(size.ws_col)
	coord.Y = i16(size.ws_row)
	if C.CreatePseudoConsole(coord,
		p.in_pipe_pty, p.out_pipe_pty, 0, &p.pseudo_console) != 0 {
		return error('Unexpected')
	}
	success = true
	return p
}

pub fn (mut self Pty) deinit() {
	C.CloseHandle(self.in_pipe_pty)
	C.CloseHandle(self.in_pipe)
	C.CloseHandle(self.out_pipe_pty)
	C.CloseHandle(self.out_pipe)
	C.ClosePseudoConsole(self.pseudo_console)
	unsafe { self = Pty{} }
}

pub fn (self Pty) get_size() !Winsize {
	return self.size
}

pub fn (mut self Pty) set_size(size Winsize) ! {
	assert size.ws_col <= 0x7fff && size.ws_row <= 0x7fff
	mut coord := C.COORD{}
	coord.X = i16(size.ws_col)
	coord.Y = i16(size.ws_row)
	if C.ResizePseudoConsole(self.pseudo_console, coord) != 0 {
		return error('ResizeFailed')
	}
	self.size = size
}

pub fn close_fd(fd Fd) { C.CloseHandle(fd) }
