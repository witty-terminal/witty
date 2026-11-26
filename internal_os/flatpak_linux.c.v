module internal_os

import log
import pty

#pkgconfig gio-2.0 gio-unix-2.0

#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <errno.h>
#include <unistd.h>
#include "@VMODROOT/internal_os/flatpak_linux.h"

// GLib/GIO declarations, typed as the GTK runtime declares them (V keeps one
// declaration per C function). GVariants are built with the typed
// constructors instead of g_variant_new's format varargs.
@[typedef]
struct C.GError {
	domain  u32
	code    int
	message &char
}

fn C.g_main_context_new() voidptr
fn C.g_main_context_unref(context voidptr)
fn C.g_main_context_push_thread_default(context voidptr)
fn C.g_main_context_pop_thread_default(context voidptr)
fn C.g_main_loop_new(context voidptr, is_running int) voidptr
fn C.g_main_loop_unref(loop voidptr)
fn C.g_main_loop_run(loop voidptr)
fn C.g_main_loop_quit(loop voidptr)
fn C.witty_flatpak_bus_get_sync(bus_type int, cancellable voidptr, error &&C.GError) voidptr
fn C.g_object_unref(obj voidptr)
fn C.g_error_free(err &C.GError)
fn C.g_free(mem voidptr)
fn C.g_get_current_dir() &char
fn C.g_unix_fd_list_new() voidptr
fn C.g_unix_fd_list_append(list voidptr, fd int, error &&C.GError) int
fn C.G_VARIANT_TYPE(type_string &char) voidptr
fn C.g_variant_builder_new(vtype voidptr) voidptr
fn C.g_variant_builder_unref(builder voidptr)
fn C.g_variant_builder_add_value(builder voidptr, value voidptr)
fn C.g_variant_builder_end(builder voidptr) voidptr
fn C.g_variant_new_tuple(children &voidptr, n_children uint) voidptr
fn C.g_variant_new_dict_entry(key voidptr, value voidptr) voidptr
fn C.g_variant_new_uint32(value u32) voidptr
fn C.g_variant_new_boolean(value int) voidptr
fn C.g_variant_new_string(str &char) voidptr
fn C.g_variant_new_handle(value int) voidptr
fn C.g_variant_new_bytestring(str &char) voidptr
fn C.g_variant_new_bytestring_array(strv &&char, length int) voidptr
fn C.g_variant_ref_sink(value voidptr) voidptr
fn C.g_variant_unref(value voidptr)
fn C.g_variant_get_child_value(value voidptr, index uint) voidptr
fn C.g_variant_get_uint32(value voidptr) u32
fn C.witty_flatpak_subscribe_host_command_exited(connection voidptr, user_data voidptr) u32
fn C.g_dbus_connection_signal_unsubscribe(connection voidptr, subscription_id u32)
fn C.witty_flatpak_dbus_call_sync(connection voidptr, bus_name &char, object_path &char, interface_name &char, method_name &char, parameters voidptr, reply_type voidptr, flags int, timeout_msec int, cancellable voidptr, error &&C.GError) voidptr
fn C.g_dbus_connection_call_with_unix_fd_list_sync(connection voidptr, bus_name &char, object_path &char, interface_name &char, method_name &char, parameters voidptr, reply_type voidptr, flags int, timeout_msec int, fd_list voidptr, out_fd_list &voidptr, cancellable voidptr, error &&C.GError) voidptr
fn C.read(fd int, buf voidptr, count uint) int

fn gerror_message(err &C.GError) string {
	if isnil(err) {
		return ''
	}
	return unsafe { cstring_to_vstring(err.message) }
}

// g_variant_get(value, "(u...)") for the uint32 child at index.
fn flatpak_variant_get_uint32(value voidptr, index uint) u32 {
	child := C.g_variant_get_child_value(value, index)
	defer {
		C.g_variant_unref(child)
	}
	return C.g_variant_get_uint32(child)
}

fn flatpak_host_command_signal_linux(pid u32, sig u8, pg bool) ! {
	// Get our bus connection.
	mut g_err := &C.GError(unsafe { nil })
	defer {
		if !isnil(g_err) {
			C.g_error_free(g_err)
		}
	}
	bus := C.witty_flatpak_bus_get_sync(C.G_BUS_TYPE_SESSION, unsafe { nil }, &g_err)
	if isnil(bus) {
		log.warn('signal error getting bus: ${gerror_message(g_err)}')
		return error('FlatpakSetupFail')
	}
	defer {
		C.g_object_unref(bus)
	}

	// "(uub)"
	params := [C.g_variant_new_uint32(pid), C.g_variant_new_uint32(u32(sig)),
		C.g_variant_new_boolean(if pg { 1 } else { 0 })]
	reply := C.witty_flatpak_dbus_call_sync(bus, c'org.freedesktop.Flatpak', c'/org/freedesktop/Flatpak/Development',
		c'org.freedesktop.Flatpak.Development', c'HostCommandSignal', C.g_variant_new_tuple(params.data,
		uint(params.len)), C.G_VARIANT_TYPE(c'()'), C.G_DBUS_CALL_FLAGS_NONE, C.G_MAXINT,
		unsafe { nil }, &g_err)
	if !isnil(g_err) {
		log.warn('signal send error: ${gerror_message(g_err)}')
		return
	}
	C.g_variant_unref(reply)
}

fn flatpak_host_command_thread_main(command &FlatpakHostCommand) {
	mut self := unsafe { command }

	// Create a new thread-local context so that all our sources go
	// to this context and we can run our loop correctly.
	ctx := C.g_main_context_new()
	defer {
		C.g_main_context_unref(ctx)
	}
	C.g_main_context_push_thread_default(ctx)
	defer {
		C.g_main_context_pop_thread_default(ctx)
	}

	// Get our loop for the current thread
	loop := C.g_main_loop_new(ctx, 1)
	defer {
		C.g_main_loop_unref(loop)
	}

	// Get our bus connection. This has to remain active until we exit
	// the thread otherwise our signals won't be called.
	mut g_err := &C.GError(unsafe { nil })
	defer {
		if !isnil(g_err) {
			C.g_error_free(g_err)
		}
	}
	bus := C.witty_flatpak_bus_get_sync(C.G_BUS_TYPE_SESSION, unsafe { nil }, &g_err)
	if isnil(bus) {
		log.warn('spawn error getting bus: ${gerror_message(g_err)}')
		self.update_state(FlatpakStateErr{})
		return
	}
	defer {
		C.g_object_unref(bus)
	}

	// Spawn the command first. This will setup all our IO.
	self.start(bus, loop) or {
		log.warn('error starting host command: ${err}')
		self.update_state(FlatpakStateErr{})
		return
	}

	// Run the event loop. It quits in the exit callback.
	C.g_main_loop_run(loop)
}

// Start the command. This will start the host command and set the
// pid field on success. This will not wait for completion.
//
// Once this is called, the self pointer MUST remain stable. This
// requirement is due to using GLib under the covers with callbacks.
fn (mut self FlatpakHostCommand) start(bus voidptr, loop voidptr) ! {
	mut err := &C.GError(unsafe { nil })
	defer {
		if !isnil(err) {
			C.g_error_free(err)
		}
	}

	// Our list of file descriptors that we need to send to the process.
	fd_list := C.g_unix_fd_list_new()
	defer {
		C.g_object_unref(fd_list)
	}
	if C.g_unix_fd_list_append(fd_list, self.stdin, &err) < 0 {
		log.warn('error adding fd: ${gerror_message(err)}')
		return error('FlatpakSetupFail')
	}
	if C.g_unix_fd_list_append(fd_list, self.stdout, &err) < 0 {
		log.warn('error adding fd: ${gerror_message(err)}')
		return error('FlatpakSetupFail')
	}
	if C.g_unix_fd_list_append(fd_list, self.stderr, &err) < 0 {
		log.warn('error adding fd: ${gerror_message(err)}')
		return error('FlatpakSetupFail')
	}

	// Build our arguments for the file descriptors.
	fd_builder := C.g_variant_builder_new(C.G_VARIANT_TYPE(c'a{uh}'))
	defer {
		C.g_variant_builder_unref(fd_builder)
	}
	C.g_variant_builder_add_value(fd_builder, C.g_variant_new_dict_entry(C.g_variant_new_uint32(0),
		C.g_variant_new_handle(self.stdin)))
	C.g_variant_builder_add_value(fd_builder, C.g_variant_new_dict_entry(C.g_variant_new_uint32(1),
		C.g_variant_new_handle(self.stdout)))
	C.g_variant_builder_add_value(fd_builder, C.g_variant_new_dict_entry(C.g_variant_new_uint32(2),
		C.g_variant_new_handle(self.stderr)))

	// Build our env vars
	env_builder := C.g_variant_builder_new(C.G_VARIANT_TYPE(c'a{ss}'))
	defer {
		C.g_variant_builder_unref(env_builder)
	}
	if env := self.env {
		for key, value in env {
			C.g_variant_builder_add_value(env_builder, C.g_variant_new_dict_entry(C.g_variant_new_string(key.str),
				C.g_variant_new_string(value.str)))
		}
	}

	// Build our args
	mut args := unsafe { []&char{len: self.argv.len + 1, init: &char(nil)} }
	for i, arg in self.argv {
		args[i] = arg.str
	}

	// Get the cwd in case we don't have ours set. A small optimization
	// would be to do this only if we need it but this isn't a
	// common code path.
	g_cwd := C.g_get_current_dir()
	defer {
		C.g_free(g_cwd)
	}

	// The params for our RPC call: "(^ay^aay@a{uh}@a{ss}u)"
	cwd_ptr := if cwd := self.cwd { cwd.str } else { g_cwd }
	children := [C.g_variant_new_bytestring(cwd_ptr), C.g_variant_new_bytestring_array(args.data,
		-1), C.g_variant_builder_end(fd_builder), C.g_variant_builder_end(env_builder),
		C.g_variant_new_uint32(0)]
	params := C.g_variant_new_tuple(children.data, uint(children.len))
	_ = C.g_variant_ref_sink(params) // take ownership
	defer {
		C.g_variant_unref(params)
	}

	// Subscribe to exit notifications
	subscription_id := C.witty_flatpak_subscribe_host_command_exited(bus, self)
	// Zig's errdefer is emulated by a reached defer that runs until start succeeds.
	mut ok := false
	defer {
		if !ok {
			C.g_dbus_connection_signal_unsubscribe(bus, subscription_id)
		}
	}

	// Go!
	reply := C.g_dbus_connection_call_with_unix_fd_list_sync(bus, c'org.freedesktop.Flatpak',
		c'/org/freedesktop/Flatpak/Development', c'org.freedesktop.Flatpak.Development',
		c'HostCommand', params, C.G_VARIANT_TYPE(c'(u)'), C.G_DBUS_CALL_FLAGS_NONE, C.G_MAXINT,
		fd_list, unsafe { nil }, unsafe { nil }, &err)
	if isnil(reply) {
		log.warn('Flatpak.HostCommand failed: ${gerror_message(err)}')
		return error('FlatpakRPCFail')
	}
	defer {
		C.g_variant_unref(reply)
	}

	pid := flatpak_variant_get_uint32(reply, 0)
	log.debug('HostCommand started pid=${pid} subscription=${subscription_id}')

	self.update_state(FlatpakStateStarted{
		pid:          pid
		subscription: subscription_id
		loop:         loop
	})
	ok = true
}

@[export: 'witty_flatpak_host_command_on_exit']
fn flatpak_host_command_on_exit(bus voidptr, params voidptr, ud voidptr) {
	mut self := unsafe { &FlatpakHostCommand(ud) }
	started_state := self.current_state().started()

	// "(uu)"
	pid := flatpak_variant_get_uint32(params, 0)
	exit_status_raw := flatpak_variant_get_uint32(params, 1)
	if started_state.pid != pid {
		return
	}

	// std.posix.W.EXITSTATUS (Linux)
	exit_status := u8((exit_status_raw & 0xff00) >> 8)
	// Update our state
	self.update_state(FlatpakStateExited{
		pid:    pid
		status: exit_status
	})
	log.debug('HostCommand exited pid=${pid} status=${exit_status}')
	if completion_ptr := started_state.completion {
		// The stored pointer is caller-owned mutable completion state; optional
		// unwrapping otherwise marks the alias immutable in the pinned compiler.
		mut completion := unsafe { completion_ptr }
		completion.result = FlatpakWaitResult{
			status: exit_status
		}
		mut loop := started_state.loop_xev or { panic('Flatpak xev completion has no loop') }
		flatpak_completion_run(mut loop, completion)
	}

	// We're done now, so we can unsubscribe
	C.g_dbus_connection_signal_unsubscribe(bus, started_state.subscription)

	// We are also done with our loop so we can exit.
	C.g_main_loop_quit(started_state.loop)
}

fn (mut self FlatpakHostCommand) current_state() FlatpakState {
	self.state_mutex.lock()
	defer {
		self.state_mutex.unlock()
	}
	return self.state
}

fn get_passwd_flatpak(username string) !Entry {
	mut pseudoterminal := pty.Pty.open(pty.Winsize{})!
	defer {
		pseudoterminal.close_slave()
		pseudoterminal.deinit()
	}

	mut command := FlatpakHostCommand{
		argv:   ['/bin/sh', '-l', '-c', 'getent passwd ${username}']
		stdin:  pseudoterminal.slave
		stdout: pseudoterminal.slave
		stderr: pseudoterminal.slave
	}
	command.spawn()!
	command.wait()!
	pseudoterminal.close_slave()

	mut output := []u8{}
	mut buf := [1024]u8{}
	for {
		n := C.read(pseudoterminal.master, &buf[0], uint(buf.len))
		if n < 0 {
			if C.errno == C.EIO {
				break
			}
			return error_with_code('failed to read host passwd entry', C.errno)
		}
		output << buf[..int(n)]
		if output.len > buf.len {
			break
		}
	}

	return parse_flatpak_passwd_output(output.bytestr())
}
