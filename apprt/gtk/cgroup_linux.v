module gtk

import internal_os
import log
import os

// cgroup_linux.v - Systemd cgroup single-instance management.
//
// Translated from ghostty/src/apprt/gtk/cgroup.zig, together with the cgroup
// filesystem helpers it depends on from ghostty/src/os/cgroup.zig
// (internal_os.cgroup.*).
//
// The purpose is to put the Ghostty process (and each surface) into its own
// systemd transient scope + cgroup v2 hierarchy so resource limits can be
// applied per-surface without affecting the main app.
//
// Two layers are translated here:
//   1. The cgroup v2 filesystem helpers (read/write under /sys/fs/cgroup and
//      /proc/<pid>/cgroup). In Zig these use std.fs; here we use V's `os`
//      module (os.read_file / os.write_file / os.mkdir_all).
//   2. The high-level `init` + `create_scope` logic, which creates the systemd
//      transient scope over D-Bus and configures the controllers/limits.
//
// The D-Bus scope creation (create_scope) builds a GVariant parameter tuple and
// calls StartTransientUnit on org.freedesktop.systemd1. There is no D-Bus
// binding module in witty yet, so the minimal GVariant/GDBusConnection C
// functions it needs are declared once in ipc_dbus_linux.v.

// --- Options --------------------------------------------------------------

// Options configures the resource limits applied to the surfaces cgroup.
// Mirrors `cgroup.Options`.
pub struct Options {
pub:
	// memory_high is the soft "high" memory limit in bytes, if set.
	memory_high ?u64
	// pids_max is the hard max number of pids, if set.
	pids_max ?u64
}

// --- D-Bus / GVariant bindings --------------------------------------------
//
// The core GVariant / GVariantBuilder / GDBusConnection types and functions
// (g_variant_type_*, g_variant_builder_*, g_dbus_connection_call_sync,
// g_variant_unref, etc.) are already declared in ipc_dbus_linux.v — reused
// here, NOT redeclared.

// --- High-level init ------------------------------------------------------

// enable_controllers enables all cgroup controllers for the given cgroup.
// Mirrors `enableControllers` in cgroup.zig: it reads the available controllers
// (space-separated) and writes them back prefixed with '+'.
fn enable_controllers(cgroup string) ! {
	raw := internal_os.controllers(cgroup)!

	// Controllers are space-separated; build "+a +b +c".
	mut parts := []string{}
	for controller in raw.split(' ') {
		if controller.len == 0 {
			continue
		}
		parts << '+' + controller
	}
	internal_os.configure_controllers(cgroup, parts.join(' '))!
}

// init initializes the cgroup for the app. It creates the transient systemd
// scope, initializes the app/surfaces cgroups, configures them, and returns the
// cgroup path for the app. Mirrors `cgroup.init`.
//
// `dbus` is a gio.DBusConnection*.
pub fn cgroup_init(dbus GDBusConnection, opts Options) !string {
	pid := os.getpid()

	// Get our initial cgroup so we can detect the switch to the transient one.
	original_result := internal_os.current(pid)!
	original := original_result.value or { '' }

	// Create our transient scope. If this succeeds the unit was created but we
	// may not have moved into it yet, so busy-loop until the move completes.
	create_scope(dbus, pid)!
	mut transient := ''
	for {
		current_result := internal_os.current(pid)!
		current := current_result.value or { '' }
		if current != original {
			transient = current
			break
		}
		// Sleep 25ms between polls, matching the Zig original.
		sleep_ms(25)
	}

	log.info('transient scope created cgroup=${transient}')

	// Create the app cgroup and move ourselves into it. This is required
	// because controllers can't be configured while a process is in a cgroup.
	internal_os.create(transient, 'app', pid)!

	// Create a cgroup that will contain all our surfaces. Controllers/limits are
	// configured only on this cgroup so the main app is unaffected.
	internal_os.create(transient, 'surfaces', none)!
	surfaces := '${transient}/surfaces'

	// Enable all of our cgroup controllers. In the Zig original failures here
	// only get logged; we propagate the error which callers may choose to
	// tolerate.
	enable_controllers(transient)!
	enable_controllers(surfaces)!

	// Configure the "high" (soft) memory limit if requested.
	if limit := opts.memory_high {
		internal_os.configure_limit(surfaces, internal_os.CgroupLimitMemoryHigh{
			value: uint(limit)
		})!
	}

	// Configure the "max" (hard) pids limit if requested.
	if limit := opts.pids_max {
		internal_os.configure_limit(surfaces, internal_os.CgroupLimitPidsMax{
			value: uint(limit)
		})!
	}

	return transient
}

// create_scope creates a transient systemd scope unit for the current process
// and moves the process into it, via a D-Bus StartTransientUnit call. Mirrors
// `createScope`.
fn create_scope(dbus GDBusConnection, pid_ int) ! {
	pid := u32(pid_)

	// The unit name needs to be unique; use the pid.
	name := 'app-witty-transient-${pid}.scope'

	builder_type := C.g_variant_type_new(c'(ssa(sv)a(sa(sv)))')
	defer {
		C.g_variant_type_free(builder_type)
	}

	// Initialize our builder to build up our parameters.
	builder := C.g_variant_builder_new(builder_type)

	// s: unit name
	C.g_variant_builder_add_value(builder, C.g_variant_new_string(&char(name.str)))
	// s: mode "fail"
	C.g_variant_builder_add_value(builder, C.g_variant_new_string(c'fail'))

	// a(sv): properties
	properties_type := C.g_variant_type_new(c'a(sv)')
	C.g_variant_builder_open(builder, properties_type)

	// ManagedOOMMemoryPressure = "kill"
	// https://www.freedesktop.org/software/systemd/man/latest/systemd-oomd.service.html
	add_sv(builder, 'ManagedOOMMemoryPressure', C.g_variant_new_string(c'kill'))

	// Delegate = true
	add_sv(builder, 'Delegate', C.g_variant_new_boolean(1))

	// PIDs = [pid] (array of u32); we add a single-element array.
	add_sv(builder, 'PIDs', new_uint32_array(pid))

	C.g_variant_builder_close(builder)
	C.g_variant_type_free(properties_type)

	// a(sa(sv)): aux (empty)
	aux_type := C.g_variant_type_new(c'a(sa(sv))')
	C.g_variant_builder_open(builder, aux_type)
	C.g_variant_builder_close(builder)
	C.g_variant_type_free(aux_type)

	reply_type := C.g_variant_type_new(c'(o)')
	defer {
		C.g_variant_type_free(reply_type)
	}

	value := C.g_variant_builder_end(builder)
	C.g_variant_builder_unref(builder)

	mut call_error := GError(unsafe { nil })
	reply := C.g_dbus_connection_call_sync(dbus, c'org.freedesktop.systemd1', c'/org/freedesktop/systemd1', c'org.freedesktop.systemd1.Manager', c'StartTransientUnit', value, reply_type, 0, -1, unsafe { nil }, &call_error)
	if isnil(reply) {
		if !isnil(call_error) {
			c_error := unsafe { &C.GError(call_error) }
			message := if isnil(c_error.message) {
				'(no message)'
			} else {
				unsafe { cstring_to_vstring(c_error.message) }
			}
			log.error('creating transient cgroup scope failed code=${c_error.code} err=${message}')
			C.g_error_free(call_error)
		}
		return error('D-Bus StartTransientUnit call failed')
	}
	C.g_variant_unref(reply)
	if !isnil(call_error) {
		C.g_error_free(call_error)
	}
}

// add_sv appends a "(sv)" tuple (string key -> variant value) to the
// builder. This corresponds to the Zig `builder.add("(sv)", key, value)` calls.
fn add_sv(builder GVariantBuilder, key string, value GVariant) {
	mut children := [
		C.g_variant_new_string(&char(key.str)),
		C.g_variant_new_variant(value),
	]
	tuple := C.g_variant_new_tuple(unsafe { &children[0] }, uint(children.len))
	C.g_variant_builder_add_value(builder, tuple)
}

// new_property_array builds the systemd `a(sv)` property payload used by
// StartTransientUnit. Keeping this construction separate also lets us verify
// the exact tuple signature without making a D-Bus call.
fn new_property_array(key string, value GVariant) GVariant {
	properties_type := C.g_variant_type_new(c'a(sv)')
	builder := C.g_variant_builder_new(properties_type)
	C.g_variant_type_free(properties_type)
	add_sv(builder, key, value)
	result := C.g_variant_builder_end(builder)
	C.g_variant_builder_unref(builder)
	return result
}

// new_uint32_array builds a GVariant array "au" containing a single u32.
// Mirrors the `glib.Variant.newFixedArray(u, &pid, 1, ...)` call in the Zig
// original (a fixed array of one 32-bit unsigned int).
fn new_uint32_array(v u32) GVariant {
	arr_type := C.g_variant_type_new(c'au')
	ab := C.g_variant_builder_new(arr_type)
	C.g_variant_builder_add_value(ab, C.g_variant_new_uint32(v))
	result := C.g_variant_builder_end(ab)
	C.g_variant_builder_unref(ab)
	C.g_variant_type_free(arr_type)
	return result
}

// sleep_ms sleeps for the given number of milliseconds. Uses the POSIX
// nanosleep via a minimal local binding to avoid pulling in `time` here.
fn C.usleep(usec u32) int

fn sleep_ms(ms int) {
	C.usleep(u32(ms) * 1000)
}
