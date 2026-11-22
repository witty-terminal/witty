module xev

// Translations of the Zig 0.15.2 std.posix wrappers that libxev's backends
// call. Each keeps the source's errno mapping, EINTR retry, and `unreachable`
// cases (translated as panics). Only the POSIX (non-Windows, non-WASI)
// branches apply to Witty's targets.
//
// C constants assigned through a cast are written `T(int(C.X))`: V's checker
// registers `x = T(C.X)` as a C global of type T, which retypes the constant
// for every other module (vlib `os` then fails on `flags |= o_nonblock`).

#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

fn C.pread(fd int, buf voidptr, count uint, offset i64) int
fn C.pwrite(fd int, buf voidptr, count uint, offset i64) int
// vlib net declares recvfrom/sendto with an int result and V keeps one
// declaration per C function, so these match it (ssize_t fits: buffers < 2 GiB).
fn C.recvfrom(sockfd int, buf voidptr, len uint, flags int, src_addr voidptr, addrlen &u32) int
fn C.sendto(sockfd int, buf voidptr, len uint, flags int, dest_addr voidptr, addrlen u32) int
fn C.accept(sockfd int, addr voidptr, addrlen &u32) int
fn C.getsockopt(sockfd int, level int, optname int, optval voidptr, optlen &u32) int
fn C.fcntl(fd int, cmd int, arg ...voidptr) int
fn C.clock_gettime(clock_id int, tp &C.timespec) int

pub struct C.timespec {
pub mut:
	tv_sec  i64
	tv_nsec i64
}

// Translation of std.posix.timespec. Options and results must hold the alias:
// this V sizes their payload for a bare `struct timespec` as a pointer.
pub type Timespec = C.timespec

// posix_errno returns the errno of a libc call's result, or zero for success.
@[inline]
fn posix_errno(rc i64) int {
	return if rc == -1 { C.errno } else { 0 }
}

@[noreturn]
fn posix_unreachable() {
	panic('reached unreachable code')
}

// Translation of std.posix.unexpectedErrno. Unexpected-error tracing is only
// enabled in Zig debug builds with an explicit option, so it is not modeled.
fn unexpected_errno(err int) IError {
	_ = err
	return new_error(.unexpected)
}

fn posix_max_count() uint {
	$if linux {
		return 0x7ffff000
	} $else $if macos || ios {
		return uint(max_i32)
	} $else {
		return uint(max_i64)
	}
}

// Translation of std.posix.read.
pub fn posix_read(fd int, buf []u8) !uint {
	if buf.len == 0 {
		return 0
	}
	for {
		rc := C.read(fd, buf.data, usize_min(uint(buf.len), posix_max_count()))
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EINTR { continue }
			C.EINVAL { posix_unreachable() }
			C.EFAULT { posix_unreachable() }
			C.ESRCH { return new_error(.process_not_found) }
			C.EAGAIN { return new_error(.would_block) }
			C.ECANCELED { return new_error(.canceled) }
			C.EBADF { return new_error(.not_open_for_reading) } // Can be a race condition.
			C.EIO { return new_error(.input_output) }
			C.EISDIR { return new_error(.is_dir) }
			C.ENOBUFS { return new_error(.system_resources) }
			C.ENOMEM { return new_error(.system_resources) }
			C.ENOTCONN { return new_error(.socket_not_connected) }
			C.ECONNRESET { return new_error(.connection_reset_by_peer) }
			C.ETIMEDOUT { return new_error(.connection_timed_out) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

// Translation of std.posix.pread.
pub fn posix_pread(fd int, buf []u8, offset u64) !uint {
	if buf.len == 0 {
		return 0
	}
	for {
		rc := C.pread(fd, buf.data, usize_min(uint(buf.len), posix_max_count()), i64(offset))
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EINTR { continue }
			C.EINVAL { posix_unreachable() }
			C.EFAULT { posix_unreachable() }
			C.ESRCH { return new_error(.process_not_found) }
			C.EAGAIN { return new_error(.would_block) }
			C.EBADF { return new_error(.not_open_for_reading) } // Can be a race condition.
			C.EIO { return new_error(.input_output) }
			C.EISDIR { return new_error(.is_dir) }
			C.ENOBUFS { return new_error(.system_resources) }
			C.ENOMEM { return new_error(.system_resources) }
			C.ENOTCONN { return new_error(.socket_not_connected) }
			C.ECONNRESET { return new_error(.connection_reset_by_peer) }
			C.ETIMEDOUT { return new_error(.connection_timed_out) }
			C.ENXIO { return new_error(.unseekable) }
			C.ESPIPE { return new_error(.unseekable) }
			C.EOVERFLOW { return new_error(.unseekable) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

// Translation of std.posix.write.
pub fn posix_write(fd int, bytes []u8) !uint {
	if bytes.len == 0 {
		return 0
	}
	for {
		rc := C.write(fd, bytes.data, usize_min(uint(bytes.len), posix_max_count()))
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EINTR { continue }
			C.EINVAL { return new_error(.invalid_argument) }
			C.EFAULT { posix_unreachable() }
			C.ESRCH { return new_error(.process_not_found) }
			C.EAGAIN { return new_error(.would_block) }
			C.EBADF { return new_error(.not_open_for_writing) } // can be a race condition.
			C.EDESTADDRREQ { posix_unreachable() } // `connect` was never called.
			C.EDQUOT { return new_error(.disk_quota) }
			C.EFBIG { return new_error(.file_too_big) }
			C.EIO { return new_error(.input_output) }
			C.ENOSPC { return new_error(.no_space_left) }
			C.EACCES { return new_error(.access_denied) }
			C.EPERM { return new_error(.permission_denied) }
			C.EPIPE { return new_error(.broken_pipe) }
			C.ECONNRESET { return new_error(.connection_reset_by_peer) }
			C.EBUSY { return new_error(.device_busy) }
			C.ENXIO { return new_error(.no_device) }
			C.EMSGSIZE { return new_error(.message_too_big) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

// Translation of std.posix.pwrite.
pub fn posix_pwrite(fd int, bytes []u8, offset u64) !uint {
	if bytes.len == 0 {
		return 0
	}
	for {
		rc := C.pwrite(fd, bytes.data, usize_min(uint(bytes.len), posix_max_count()), i64(offset))
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EINTR { continue }
			C.EINVAL { return new_error(.invalid_argument) }
			C.EFAULT { posix_unreachable() }
			C.ESRCH { return new_error(.process_not_found) }
			C.EAGAIN { return new_error(.would_block) }
			C.EBADF { return new_error(.not_open_for_writing) } // Can be a race condition.
			C.EDESTADDRREQ { posix_unreachable() } // `connect` was never called.
			C.EDQUOT { return new_error(.disk_quota) }
			C.EFBIG { return new_error(.file_too_big) }
			C.EIO { return new_error(.input_output) }
			C.ENOSPC { return new_error(.no_space_left) }
			C.EPERM { return new_error(.permission_denied) }
			C.EPIPE { return new_error(.broken_pipe) }
			C.ENXIO { return new_error(.unseekable) }
			C.ESPIPE { return new_error(.unseekable) }
			C.EOVERFLOW { return new_error(.unseekable) }
			C.EBUSY { return new_error(.device_busy) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

// Translation of std.posix.recvfrom.
pub fn posix_recvfrom(sockfd int, buf []u8, flags u32, src_addr voidptr, addrlen &u32) !uint {
	for {
		rc := C.recvfrom(sockfd, buf.data, uint(buf.len), int(flags), src_addr, addrlen)
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EBADF { posix_unreachable() } // always a race condition
			C.EFAULT { posix_unreachable() }
			C.EINVAL { posix_unreachable() }
			C.ENOTCONN { return new_error(.socket_not_connected) }
			C.ENOTSOCK { posix_unreachable() }
			C.EINTR { continue }
			C.EAGAIN { return new_error(.would_block) }
			C.ENOMEM { return new_error(.system_resources) }
			C.ECONNREFUSED { return new_error(.connection_refused) }
			C.ECONNRESET { return new_error(.connection_reset_by_peer) }
			C.ETIMEDOUT { return new_error(.connection_timed_out) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

// Translation of std.posix.recv.
pub fn posix_recv(sock int, buf []u8, flags u32) !uint {
	return posix_recvfrom(sock, buf, flags, unsafe { nil }, unsafe { nil })
}

// Translation of std.posix.sendto.
pub fn posix_sendto(sockfd int, buf []u8, flags u32, dest_addr voidptr, addrlen u32) !uint {
	for {
		rc := C.sendto(sockfd, buf.data, uint(buf.len), int(flags), dest_addr, addrlen)
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EACCES { return new_error(.access_denied) }
			C.EAGAIN { return new_error(.would_block) }
			C.EALREADY { return new_error(.fast_open_already_in_progress) }
			C.EBADF { posix_unreachable() } // always a race condition
			C.ECONNREFUSED { return new_error(.connection_refused) }
			C.ECONNRESET { return new_error(.connection_reset_by_peer) }
			C.EDESTADDRREQ { posix_unreachable() } // The socket is not connection-mode, and no peer address is set.
			C.EFAULT { posix_unreachable() } // An invalid user space address was specified for an argument.
			C.EINTR { continue }
			C.EINVAL { return new_error(.unreachable_address) }
			C.EISCONN { posix_unreachable() } // connection-mode socket was connected already but a recipient was specified
			C.EMSGSIZE { return new_error(.message_too_big) }
			C.ENOBUFS { return new_error(.system_resources) }
			C.ENOMEM { return new_error(.system_resources) }
			C.ENOTSOCK { posix_unreachable() } // The file descriptor sockfd does not refer to a socket.
			C.EOPNOTSUPP { posix_unreachable() } // Some bit in the flags argument is inappropriate for the socket type.
			C.EPIPE { return new_error(.broken_pipe) }
			C.EAFNOSUPPORT { return new_error(.address_family_not_supported) }
			C.ELOOP { return new_error(.sym_link_loop) }
			C.ENAMETOOLONG { return new_error(.name_too_long) }
			C.ENOENT { return new_error(.file_not_found) }
			C.ENOTDIR { return new_error(.not_dir) }
			C.EHOSTUNREACH { return new_error(.network_unreachable) }
			C.ENETUNREACH { return new_error(.network_unreachable) }
			C.ENOTCONN { return new_error(.socket_not_connected) }
			C.ENETDOWN { return new_error(.network_subsystem_failed) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

// Translation of std.posix.send.
pub fn posix_send(sockfd int, buf []u8, flags u32) !uint {
	return posix_sendto(sockfd, buf, flags, unsafe { nil }, 0) or {
		match error_kind(err) {
			.address_family_not_supported, .sym_link_loop, .name_too_long, .file_not_found,
			.not_dir, .network_unreachable, .address_not_available, .socket_not_connected,
			.unreachable_address {
				posix_unreachable()
			}
			else {
				return err
			}
		}
	}
}

// Translation of std.posix.fcntl.
fn posix_fcntl(fd int, cmd int, arg uint) !uint {
	for {
		rc := C.fcntl(fd, cmd, voidptr(arg))
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EINTR { continue }
			// Zig maps these to Locked, FileBusy, PermissionDenied, DeadLock,
			// and LockedRegionLimitExceeded. Every libxev caller treats them as
			// unreachable (see setSockFlags).
			C.EAGAIN, C.EACCES, C.EBUSY, C.EPERM, C.EDEADLK, C.ENOLCK { posix_unreachable() }
			C.EBADF { posix_unreachable() }
			C.EINVAL { posix_unreachable() } // invalid parameters
			C.EMFILE { return new_error(.process_fd_quota_exceeded) }
			C.ENOTDIR { posix_unreachable() } // invalid parameter
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

// Translation of std.posix.setSockFlags (non-Windows branch).
fn posix_set_sock_flags(sock int, flags u32) ! {
	if flags & sock_cloexec != 0 {
		mut fd_flags := posix_fcntl(sock, C.F_GETFD, 0)!
		fd_flags |= uint(int(C.FD_CLOEXEC))
		_ = posix_fcntl(sock, C.F_SETFD, fd_flags)!
	}
	if flags & sock_nonblock != 0 {
		mut fl_flags := posix_fcntl(sock, C.F_GETFL, 0)!
		fl_flags |= uint(int(C.O_NONBLOCK))
		_ = posix_fcntl(sock, C.F_SETFL, fl_flags)!
	}
}

// Translation of std.posix.accept. Darwin has no accept4, so the requested
// socket flags are applied afterwards with setSockFlags.
pub fn posix_accept(sock int, addr voidptr, addr_size &u32, flags u32) !int {
	assert 0 == (flags & ~(sock_nonblock | sock_cloexec)) // Unsupported flag(s)

	mut accepted_sock := 0
	for {
		rc := posix_accept_syscall(sock, addr, addr_size, flags)
		match posix_errno(rc) {
			0 {
				accepted_sock = rc
				break
			}
			C.EINTR { continue }
			C.EAGAIN { return new_error(.would_block) }
			C.EBADF { posix_unreachable() } // always a race condition
			C.ECONNABORTED { return new_error(.connection_aborted) }
			C.EFAULT { posix_unreachable() }
			C.EINVAL { return new_error(.socket_not_listening) }
			C.ENOTSOCK { posix_unreachable() }
			C.EMFILE { return new_error(.process_fd_quota_exceeded) }
			C.ENFILE { return new_error(.system_fd_quota_exceeded) }
			C.ENOBUFS { return new_error(.system_resources) }
			C.ENOMEM { return new_error(.system_resources) }
			C.EOPNOTSUPP { posix_unreachable() }
			C.EPROTO { return new_error(.protocol_failure) }
			C.EPERM { return new_error(.blocked_by_firewall) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}

	$if !linux {
		posix_set_sock_flags(accepted_sock, flags) or {
			posix_close(accepted_sock)
			return err
		}
	}
	return accepted_sock
}

// Translation of std.posix.getsockoptError.
pub fn posix_getsockopt_error(sockfd int) ! {
	mut err_code := i32(0)
	mut size := u32(sizeof(u32))
	rc := C.getsockopt(sockfd, C.SOL_SOCKET, C.SO_ERROR, &err_code, &size)
	assert size == 4
	match posix_errno(rc) {
		0 {
			match int(err_code) {
				0 { return }
				C.EACCES { return new_error(.access_denied) }
				C.EPERM { return new_error(.permission_denied) }
				C.EADDRINUSE { return new_error(.address_in_use) }
				C.EADDRNOTAVAIL { return new_error(.address_not_available) }
				C.EAFNOSUPPORT { return new_error(.address_family_not_supported) }
				C.EAGAIN { return new_error(.system_resources) }
				C.EALREADY { return new_error(.connection_pending) }
				C.EBADF { posix_unreachable() } // sockfd is not a valid open file descriptor.
				C.ECONNREFUSED { return new_error(.connection_refused) }
				C.EFAULT { posix_unreachable() } // The socket structure address is outside the user's address space.
				C.EISCONN { posix_unreachable() } // The socket is already connected.
				C.EHOSTUNREACH { return new_error(.network_unreachable) }
				C.ENETUNREACH { return new_error(.network_unreachable) }
				C.ENOTSOCK { posix_unreachable() } // The file descriptor sockfd does not refer to a socket.
				C.EPROTOTYPE { posix_unreachable() } // The socket type does not support the requested communications protocol.
				C.ETIMEDOUT { return new_error(.connection_timed_out) }
				C.ECONNRESET { return new_error(.connection_reset_by_peer) }
				else { return unexpected_errno(int(err_code)) }
			}
		}
		C.EBADF { posix_unreachable() } // The argument sockfd is not a valid file descriptor.
		C.EFAULT { posix_unreachable() } // The address pointed to by optval or optlen is not in a valid part of the process address space.
		C.EINVAL { posix_unreachable() }
		C.ENOPROTOOPT { posix_unreachable() } // The option is unknown at the level indicated.
		C.ENOTSOCK { posix_unreachable() } // The file descriptor sockfd does not refer to a socket.
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

fn C.socket(domain int, socket_type int, protocol int) int
fn C.setsockopt(fd int, level int, optname int, optval voidptr, optlen u32) int
fn C.bind(sock int, addr voidptr, len u32) int
fn C.listen(sock int, backlog int) int

// Translation of std.posix.socket (non-Windows branch).
pub fn posix_socket(domain u32, socket_type u32, protocol u32) !int {
	have_sock_flags := $if macos || ios { false } $else { true }
	filtered_sock_type := if !have_sock_flags {
		socket_type & ~(sock_nonblock | sock_cloexec)
	} else {
		socket_type
	}
	rc := C.socket(int(domain), int(filtered_sock_type), int(protocol))
	match posix_errno(rc) {
		0 {
			fd := rc
			if !have_sock_flags {
				posix_set_sock_flags(fd, socket_type) or {
					posix_close(fd)
					return err
				}
			}
			return fd
		}
		C.EACCES { return new_error(.access_denied) }
		C.EAFNOSUPPORT { return new_error(.address_family_not_supported) }
		C.EINVAL { return new_error(.protocol_family_not_available) }
		C.EMFILE { return new_error(.process_fd_quota_exceeded) }
		C.ENFILE { return new_error(.system_fd_quota_exceeded) }
		C.ENOBUFS { return new_error(.system_resources) }
		C.ENOMEM { return new_error(.system_resources) }
		C.EPROTONOSUPPORT { return new_error(.protocol_not_supported) }
		C.EPROTOTYPE { return new_error(.socket_type_not_supported) }
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

// Translation of std.posix.setsockopt (non-Windows branch).
pub fn posix_setsockopt(fd int, level int, optname u32, opt []u8) ! {
	rc := C.setsockopt(fd, level, int(optname), opt.data, u32(opt.len))
	match posix_errno(rc) {
		0 {}
		C.EBADF { posix_unreachable() } // always a race condition
		C.ENOTSOCK { posix_unreachable() } // always a race condition
		C.EINVAL { posix_unreachable() }
		C.EFAULT { posix_unreachable() }
		C.EDOM { return new_error(.timeout_too_big) }
		C.EISCONN { return new_error(.already_connected) }
		C.ENOPROTOOPT { return new_error(.invalid_protocol_option) }
		C.ENOMEM { return new_error(.system_resources) }
		C.ENOBUFS { return new_error(.system_resources) }
		C.EPERM { return new_error(.permission_denied) }
		C.ENODEV { return new_error(.no_device) }
		C.EOPNOTSUPP { return new_error(.operation_not_supported) }
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

// Translation of std.posix.bind (non-Windows branch).
pub fn posix_bind(sock int, addr voidptr, len u32) ! {
	rc := C.bind(sock, addr, len)
	match posix_errno(rc) {
		0 { return }
		C.EACCES, C.EPERM { return new_error(.access_denied) }
		C.EADDRINUSE { return new_error(.address_in_use) }
		C.EBADF { posix_unreachable() } // always a race condition if this error is returned
		C.EINVAL { posix_unreachable() } // invalid parameters
		C.ENOTSOCK { posix_unreachable() } // invalid `sockfd`
		C.EAFNOSUPPORT { return new_error(.address_family_not_supported) }
		C.EADDRNOTAVAIL { return new_error(.address_not_available) }
		C.EFAULT { posix_unreachable() } // invalid `addr` pointer
		C.ELOOP { return new_error(.sym_link_loop) }
		C.ENAMETOOLONG { return new_error(.name_too_long) }
		C.ENOENT { return new_error(.file_not_found) }
		C.ENOMEM { return new_error(.system_resources) }
		C.ENOTDIR { return new_error(.not_dir) }
		C.EROFS { return new_error(.read_only_file_system) }
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

// Translation of std.posix.listen (non-Windows branch).
pub fn posix_listen(sock int, backlog u32) ! {
	rc := C.listen(sock, int(backlog))
	match posix_errno(rc) {
		0 { return }
		C.EADDRINUSE { return new_error(.address_in_use) }
		C.EBADF { posix_unreachable() }
		C.ENOTSOCK { return new_error(.file_descriptor_not_a_socket) }
		C.EOPNOTSUPP { return new_error(.operation_not_supported) }
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

fn C.connect(socket int, address voidptr, address_len u32) int
fn C.shutdown(socket int, how int) int
fn C.dup(fd int) int
fn C.sendmsg(sockfd int, msg voidptr, flags int) int

// Translation of std.posix.connect (non-Windows branch).
// Initiate a connection on a socket.
// If `sockfd` is opened in non blocking mode, the function will
// return error.WouldBlock when EAGAIN or EINPROGRESS is received.
pub fn posix_connect(sock int, sock_addr voidptr, len u32) ! {
	for {
		rc := C.connect(sock, sock_addr, len)
		match posix_errno(rc) {
			0 { return }
			C.EACCES { return new_error(.access_denied) }
			C.EPERM { return new_error(.permission_denied) }
			C.EADDRINUSE { return new_error(.address_in_use) }
			C.EADDRNOTAVAIL { return new_error(.address_not_available) }
			C.EAFNOSUPPORT { return new_error(.address_family_not_supported) }
			C.EAGAIN, C.EINPROGRESS { return new_error(.would_block) }
			C.EALREADY { return new_error(.connection_pending) }
			C.EBADF { posix_unreachable() } // sockfd is not a valid open file descriptor.
			C.ECONNREFUSED { return new_error(.connection_refused) }
			C.ECONNRESET { return new_error(.connection_reset_by_peer) }
			C.EFAULT { posix_unreachable() } // The socket structure address is outside the user's address space.
			C.EINTR { continue }
			C.EISCONN { posix_unreachable() } // The socket is already connected.
			C.EHOSTUNREACH { return new_error(.network_unreachable) }
			C.ENETUNREACH { return new_error(.network_unreachable) }
			C.ENOTSOCK { posix_unreachable() } // The file descriptor sockfd does not refer to a socket.
			C.EPROTOTYPE { posix_unreachable() } // The socket type does not support the requested communications protocol.
			C.ETIMEDOUT { return new_error(.connection_timed_out) }
			C.ENOENT { return new_error(.file_not_found) } // Returned when socket is AF.UNIX and the given path does not exist.
			C.ECONNABORTED { posix_unreachable() } // Tried to reuse socket that previously received error.ConnectionRefused.
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
}

// Translation of std.posix.ShutdownHow.
pub enum ShutdownHow as u8 {
	recv
	send
	both
}

// Translation of std.posix.shutdown (non-Windows branch).
// Shutdown socket send/receive operations
pub fn posix_shutdown(sock int, how ShutdownHow) ! {
	how_c := match how {
		.recv { C.SHUT_RD }
		.send { C.SHUT_WR }
		.both { C.SHUT_RDWR }
	}
	rc := C.shutdown(sock, how_c)
	match posix_errno(rc) {
		0 { return }
		C.EBADF { posix_unreachable() }
		C.EINVAL { posix_unreachable() }
		C.ENOTCONN { return new_error(.socket_not_connected) }
		C.ENOTSOCK { posix_unreachable() }
		C.ENOBUFS { return new_error(.system_resources) }
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

// Translation of std.posix.dup.
pub fn posix_dup(old_fd int) !int {
	rc := C.dup(old_fd)
	match posix_errno(rc) {
		0 { return rc }
		C.EMFILE { return new_error(.process_fd_quota_exceeded) }
		C.EBADF { posix_unreachable() } // invalid file descriptor
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

// std.posix.msghdr and std.posix.msghdr_const. libxev only passes pointers
// to them through to the system calls, so their fields are not declared.
pub struct C.msghdr {}

// std.posix.iovec_const.
pub struct C.iovec {}

// Translation of std.posix.sendmsg (non-Windows branch).
pub fn posix_sendmsg(sockfd int, msg &C.msghdr, flags u32) !uint {
	for {
		rc := C.sendmsg(sockfd, msg, int(flags))
		match posix_errno(rc) {
			0 { return uint(rc) }
			C.EACCES { return new_error(.access_denied) }
			C.EAGAIN { return new_error(.would_block) }
			C.EALREADY { return new_error(.fast_open_already_in_progress) }
			C.EBADF { posix_unreachable() } // always a race condition
			C.ECONNRESET { return new_error(.connection_reset_by_peer) }
			C.EDESTADDRREQ { posix_unreachable() } // The socket is not connection-mode, and no peer address is set.
			C.EFAULT { posix_unreachable() } // An invalid user space address was specified for an argument.
			C.EINTR { continue }
			C.EINVAL { posix_unreachable() } // Invalid argument passed.
			C.EISCONN { posix_unreachable() } // connection-mode socket was connected already but a recipient was specified
			C.EMSGSIZE { return new_error(.message_too_big) }
			C.ENOBUFS { return new_error(.system_resources) }
			C.ENOMEM { return new_error(.system_resources) }
			C.ENOTSOCK { posix_unreachable() } // The file descriptor sockfd does not refer to a socket.
			C.EOPNOTSUPP { posix_unreachable() } // Some bit in the flags argument is inappropriate for the socket type.
			C.EPIPE { return new_error(.broken_pipe) }
			C.EAFNOSUPPORT { return new_error(.address_family_not_supported) }
			C.ELOOP { return new_error(.sym_link_loop) }
			C.ENAMETOOLONG { return new_error(.name_too_long) }
			C.ENOENT { return new_error(.file_not_found) }
			C.ENOTDIR { return new_error(.not_dir) }
			C.EHOSTUNREACH { return new_error(.network_unreachable) }
			C.ENETUNREACH { return new_error(.network_unreachable) }
			C.ENOTCONN { return new_error(.socket_not_connected) }
			C.ENETDOWN { return new_error(.network_subsystem_failed) }
			else { return unexpected_errno(posix_errno(rc)) }
		}
	}
	return 0
}

fn C.waitpid(pid int, status &int, options int) int

pub struct WaitPidResult {
pub:
	pid    int
	status u32
}

// Translation of std.posix.waitpid.
pub fn posix_waitpid(pid int, flags u32) WaitPidResult {
	mut status := int(0)
	for {
		rc := C.waitpid(pid, &status, int(flags))
		match posix_errno(rc) {
			0 {
				return WaitPidResult{
					pid: rc
					status: u32(status)
				}
			}
			C.EINTR {
				continue
			}
			C.ECHILD {
				posix_unreachable() // The process specified does not exist. It would be a race condition to handle this error.
			}
			C.EINVAL {
				posix_unreachable() // Invalid flags.
			}
			else {
				posix_unreachable()
			}
		}
	}
	return WaitPidResult{}
}

// Translation of std.posix.close.
pub fn posix_close(fd int) {
	rc := C.close(fd)
	match posix_errno(rc) {
		C.EBADF { posix_unreachable() } // Always a race condition.
		C.EINTR { return } // This is still a success. See https://github.com/ziglang/zig/issues/2425
		else { return }
	}
}

// Translation of std.posix.clock_gettime.
pub fn posix_clock_gettime(clock_id int) !Timespec {
	mut tp := Timespec{}
	rc := C.clock_gettime(clock_id, unsafe { &C.timespec(&tp) })
	match posix_errno(rc) {
		0 { return tp }
		C.EFAULT { posix_unreachable() }
		C.EINVAL { return new_error(.unsupported_clock) }
		else { return unexpected_errno(posix_errno(rc)) }
	}
}

@[inline]
fn usize_min(a uint, b uint) uint {
	return if a < b { a } else { b }
}
