module gtk

// ipc_new_window_linux.v - Send a "new-window" IPC to a running instance.
//
// Translated from ghostty/src/apprt/gtk/ipc/new_window.zig.
//
// Uses a D-Bus method call to open a new window on GTK.
// See: https://wiki.gnome.org/Projects/GLib/GApplication/DBusAPI
//
// `witty +new-window` is equivalent to (on a release build):
//   gdbus call --session --dest com.alexander.witty \
//     --object-path /com/alexander/witty \
//     --method org.gtk.Actions.Activate new-window [] []
//
// `witty +new-window -e echo hello` is equivalent to:
//   gdbus call --session --dest com.alexander.witty \
//     --object-path /com/alexander/witty \
//     --method org.gtk.Actions.Activate new-window-command \
//     '[<@as ["echo" "hello"]>]' []

import apprt

// The "as" command array is built with the module's heap GVariantBuilder API
// and the GVariant/GBytes helpers, all declared in ipc_dbus_linux.v. The Zig
// original (new_window.zig) uses a stack-allocated GVariantBuilder, but the
// heap builder is functionally equivalent and avoids modeling GLib's internal
// on-stack struct layout in V.

// ipc_new_window sends a new-window (or new-window-command) IPC to the running
// Ghostty instance identified by `target`. Returns true on success. Mirrors
// `new_window.newWindow`.
pub fn ipc_new_window(target apprt.IpcTarget, value apprt.IpcNewWindow) !bool {
	// Choose the action based on whether command arguments were given.
	action := if _ := value.arguments {
		'new-window-command'
	} else {
		'new-window'
	}

	mut dbus := dbus_init(target, action)!
	defer {
		dbus.deinit()
	}

	if arguments := value.arguments {
		// If `-e` was specified on the command line, the first parameter is an
		// array of strings that contain the arguments that came after `-e`,
		// which will be interpreted as a command to run.
		as_variant_type := C.g_variant_type_new(c'as')
		defer {
			C.g_variant_type_free(as_variant_type)
		}
		s_variant_type := C.g_variant_type_new(c's')
		defer {
			C.g_variant_type_free(s_variant_type)
		}

		command := C.g_variant_builder_new(as_variant_type)

		for argument in arguments {
			// arg.len + 1 to include the terminating NUL, like ghostty.
			bytes := C.g_bytes_new(argument.str, uint(argument.len + 1))
			string_variant := C.g_variant_new_from_bytes(s_variant_type, bytes, true)
			C.g_bytes_unref(bytes)
			C.g_variant_builder_add_value(command, string_variant)
		}

		// g_variant_builder_end returns a floating variant referencing the
		// builder's contents; we add it as a parameter, then release the
		// builder itself. (The heap builder must be unref'd; the stack builder
		// in the Zig original is instead cleared on the error path.)
		dbus.add_parameter(C.g_variant_builder_end(command))
		C.g_variant_builder_unref(command)
	}

	dbus.send()!

	return true
}
