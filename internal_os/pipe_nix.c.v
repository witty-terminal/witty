module internal_os

import os

pub type PipeFd = int

// pipe() that works on POSIX systems. This sets CLOEXEC on the file
// descriptors. Returns [read_fd, write_fd].
// The native fd_t alias is an int. Returning the primitive fixed-array type
// avoids V 0.5.2 generating an inconsistent result typedef for alias elements.
pub fn pipe() ![2]int {
	// pipe(2) writes two C ints even when V's int is wider.
	mut fds := [2]i32{}
	if C.pipe(&fds[0]) != 0 {
		return os.error_posix()
	}

	// POSIX doesn't have pipe2() everywhere (e.g. macOS), so we set
	// CLOEXEC manually with fcntl to match Ghostty's pipe2(.{ .CLOEXEC = true }).
	set_cloexec(fds[0]) or {
		os.fd_close(fds[0])
		os.fd_close(fds[1])
		return err
	}
	set_cloexec(fds[1]) or {
		os.fd_close(fds[0])
		os.fd_close(fds[1])
		return err
	}
	return [int(fds[0]), int(fds[1])]!
}

// set_cloexec sets the FD_CLOEXEC flag on the given file descriptor.
fn set_cloexec(fd int) ! {
	flags := C.fcntl(fd, C.F_GETFD, 0)
	if flags < 0 {
		return os.error_posix()
	}
	if C.fcntl(fd, C.F_SETFD, flags | C.FD_CLOEXEC) < 0 {
		return os.error_posix()
	}
}
