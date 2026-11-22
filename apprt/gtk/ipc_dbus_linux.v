module gtk

// ipc_dbus_linux.v - D-Bus helper for IPC.
//
// Translated from ghostty/src/apprt/gtk/ipc/DBus.zig.
//
// This builds and sends an `org.gtk.Actions.Activate` method call over the
// D-Bus *session* bus to a running Ghostty instance, using GDBus/GLib. The
// payload has the GVariant signature `(sava{sv})`:
//   - `s`     : the action name (e.g. "new-window").
//   - `av`    : an array of parameter variants.
//   - `a{sv}` : platform data (we send none).
//
// The opaque handle aliases `GVariant`, `GError`, `GObject` come from
// c_gtk_linux.v; only the *new* C functions this file needs are declared here.

import apprt

// --- Opaque handle aliases ------------------------------------------------
//
// This file is the canonical home for the D-Bus / GVariant handle aliases and
// the core GVariant/GVariantBuilder/GDBusConnection C functions; sibling files
// (e.g. cgroup_linux.v) reuse them. `GVariant`/`GError` come from
// c_gtk_linux.v and `GVariantType` from ext_actions_linux.v, so those are NOT
// redeclared here.

pub type GDBusConnection = voidptr

pub type GVariantBuilder = voidptr

pub type GBytes = voidptr

// GBusType enumerates the well-known message bus types. Mirrors GLib's
// `GBusType`; we only use `.session`.
pub enum GBusType as i32 {
	starter = -1
	@none   = 0
	system  = 1
	session = 2
}

// --- Core GVariant / GVariantBuilder / GDBus C bindings -------------------
//
// Declared here once for the whole module (reused by cgroup_linux.v etc.).

// GVariantType lifecycle.
fn C.g_variant_type_new(type_string &char) GVariantType

fn C.g_variant_type_free(vtype GVariantType)

// GVariantBuilder lifecycle + payload construction.
fn C.g_variant_builder_new(vtype GVariantType) GVariantBuilder

fn C.g_variant_builder_unref(builder GVariantBuilder)

fn C.g_variant_builder_add_value(builder GVariantBuilder, value GVariant)

fn C.g_variant_builder_open(builder GVariantBuilder, vtype GVariantType)

fn C.g_variant_builder_close(builder GVariantBuilder)

fn C.g_variant_builder_end(builder GVariantBuilder) GVariant

fn C.g_variant_new_variant(value GVariant) GVariant

fn C.g_variant_new_tuple(children &GVariant, n_children uint) GVariant

fn C.g_variant_new_string(str &char) GVariant

fn C.g_variant_new_boolean(value int) GVariant

fn C.g_variant_new_uint32(value u32) GVariant

fn C.g_variant_new_dict_entry(key GVariant, value GVariant) GVariant

fn C.g_variant_get_type_string(value GVariant) &char

// GDBus session-bus connection + synchronous method call.
fn C.g_bus_get_sync(bus_type int, cancellable voidptr, error &GError) GDBusConnection

fn C.g_dbus_connection_call_sync(connection GDBusConnection, bus_name &char, object_path &char, interface_name &char, method_name &char, parameters GVariant, reply_type GVariantType, flags int, timeout_msec int, cancellable voidptr, error &GError) GVariant

// GVariant unref.
fn C.g_variant_unref(value GVariant)

// GBytes + GVariant-from-bytes.
fn C.g_bytes_new(data voidptr, size uint) GBytes

fn C.g_bytes_unref(bytes GBytes)

fn C.g_variant_new_from_bytes(vtype GVariantType, bytes GBytes, trusted bool) GVariant

// Bus name / object path validation.
fn C.g_variant_is_object_path(str &char) bool

fn C.g_application_id_is_valid(application_id &char) bool

// GError free.
fn C.g_error_free(err GError)

// GErrorStruct mirrors the head of GLib's public `GError` struct so we can read
// the human-readable `message` field for diagnostics. Layout: `{ GQuark domain;
// gint code; gchar *message; }`. GQuark is a 32-bit int and `code` is a 32-bit
// int, so on all our targets `message` is the third pointer-aligned word.
@[typedef]
struct C.GError {
	domain  u32
	code    int
	message &char
}

// --- DBus helper ----------------------------------------------------------

// DBus is the IPC helper. Mirrors DBus.zig's `Self`. It owns two variant
// builders (payload + parameters) and a session-bus connection, and must be
// finalized with `deinit` after `send`.
pub struct DBus {
	// The target for this IPC.
	target apprt.IpcTarget
mut:
	// Connection to the D-Bus session bus.
	dbus GDBusConnection
	// The bus name of the Ghostty instance we are calling.
	bus_name string
	// The object path of the Ghostty instance we are calling.
	object_path string
	// Builds the top-level DBus payload `(sava{sv})`.
	payload_builder GVariantBuilder
	// Builds the `av` parameter array.
	parameters_builder GVariantBuilder
}

// dbus_init initializes the helper. Mirrors `DBus.init`.
//
// `action` is the org.gtk.Actions action name (e.g. "new-window"). Returns an
// error (with a message on stderr) when the bus name / object path are invalid
// or the session bus is unavailable — mirroring `error.IPCFailed`.
pub fn dbus_init(target apprt.IpcTarget, action string) !DBus {
	// Get the appropriate bus name and object path for contacting the
	// Ghostty instance we're interested in.
	mut bus_name := ''
	mut obj_path := ''
	match target {
		apprt.IpcTargetClass {
			// Force the usage of the class specified on the CLI to determine
			// the bus name and object path: "/{class}" with '.' -> '/' and
			// '-' -> '_'.
			bus_name = target.class
			obj_path = '/${target.class}'.replace('.', '/').replace('-', '_')
		}
		apprt.IpcTargetDetect {
			bus_name = application_id
			obj_path = object_path
		}
	}

	if !C.g_application_id_is_valid(bus_name.str) {
		eprintln('D-Bus bus name is not valid: ${bus_name}')
		return error('IPCFailed')
	}

	if !C.g_variant_is_object_path(obj_path.str) {
		eprintln('D-Bus object path is not valid: ${obj_path}')
		return error('IPCFailed')
	}

	// Get a connection to the D-Bus session bus.
	mut err := GError(unsafe { nil })
	dbus := C.g_bus_get_sync(int(GBusType.session), unsafe { nil }, &err)
	if !isnil(err) {
		msg := error_message(err)
		C.g_error_free(err)
		eprintln('Unable to establish connection to D-Bus session bus: ${msg}')
		return error('IPCFailed')
	}
	if isnil(dbus) {
		eprintln('g_bus_get_sync returned null')
		return error('IPCFailed')
	}

	// Set up the payload builder for the top-level "(sava{sv})" tuple.
	payload_variant_type := C.g_variant_type_new(c'(sava{sv})')
	defer {
		C.g_variant_type_free(payload_variant_type)
	}
	payload_builder := C.g_variant_builder_new(payload_variant_type)

	// Add the action name to the payload as a string variant. We build it
	// from bytes (NUL-terminated) exactly as ghostty does so the trailing NUL
	// is included in the string's length, matching the C API expectation.
	{
		s_variant_type := C.g_variant_type_new(c's')
		defer {
			C.g_variant_type_free(s_variant_type)
		}
		// action.len + 1 to include the terminating NUL, like ghostty.
		bytes := C.g_bytes_new(action.str, uint(action.len + 1))
		defer {
			C.g_bytes_unref(bytes)
		}
		value := C.g_variant_new_from_bytes(s_variant_type, bytes, true)
		C.g_variant_builder_add_value(payload_builder, value)
	}

	// Set up the parameters builder for the "av" array.
	parameters_variant_type := C.g_variant_type_new(c'av')
	defer {
		C.g_variant_type_free(parameters_variant_type)
	}
	parameters_builder := C.g_variant_builder_new(parameters_variant_type)

	return DBus{
		target: target
		dbus: dbus
		bus_name: bus_name
		object_path: obj_path
		payload_builder: payload_builder
		parameters_builder: parameters_builder
	}
}

// add_parameter adds a parameter variant to the IPC call. Mirrors
// `DBus.addParameter`.
pub fn (mut self DBus) add_parameter(variant GVariant) {
	// The parameters builder is `av`, so each concrete parameter must be
	// wrapped as a variant (`v`) before insertion. This is the non-variadic C
	// equivalent of Ghostty's `parameters_builder.add("v", variant)` call.
	C.g_variant_builder_add_value(self.parameters_builder, C.g_variant_new_variant(variant))
}

// send sends the IPC to the remote Ghostty. Once it completes, nothing further
// should be done with this object other than call `deinit`. Mirrors
// `DBus.send`.
pub fn (mut self DBus) send() ! {
	// Finish building the parameters and add them to the payload.
	parameters := C.g_variant_builder_end(self.parameters_builder)
	C.g_variant_builder_add_value(self.payload_builder, parameters)

	// Add the (empty) platform data "a{sv}" to the payload.
	{
		platform_data_variant_type := C.g_variant_type_new(c'a{sv}')
		defer {
			C.g_variant_type_free(platform_data_variant_type)
		}
		C.g_variant_builder_open(self.payload_builder, platform_data_variant_type)
		// We have no platform data.
		C.g_variant_builder_close(self.payload_builder)
	}

	payload := C.g_variant_builder_end(self.payload_builder)

	mut err := GError(unsafe { nil })
	result := C.g_dbus_connection_call_sync(self.dbus, self.bus_name.str, self.object_path.str, c'org.gtk.Actions', c'Activate', payload, GVariantType(unsafe { nil }), 0, -1, unsafe { nil }, &err)
	if !isnil(result) {
		C.g_variant_unref(result)
	}
	if !isnil(err) {
		msg := error_message(err)
		C.g_error_free(err)
		eprintln('D-Bus method call returned an error err=${msg}')
		return error('IPCFailed')
	}
}

// deinit frees/unrefs any data held by this instance. Mirrors `DBus.deinit`.
pub fn (mut self DBus) deinit() {
	C.g_variant_builder_unref(self.parameters_builder)
	C.g_variant_builder_unref(self.payload_builder)
	object_unref(self.dbus)
}

// error_message extracts the human-readable message from a GError, or a
// placeholder when unavailable.
fn error_message(err GError) string {
	e := unsafe { &C.GError(err) }
	if isnil(e.message) {
		return '(unknown)'
	}
	return unsafe { cstring_to_vstring(e.message) }
}
