module gtk

// flatpak_linux.v - Flatpak-aware resources directory resolution.
//
// Translated from ghostty/src/apprt/gtk/flatpak.zig.
//
// Ghostty's `resourcesDir` first checks — but only when built with the
// `flatpak` build option AND actually running inside a Flatpak sandbox —
// whether it can derive the *host* resources path from `/.flatpak-info`.
// Otherwise it falls back to the generic `internal_os.resourcesDir`.
//
import buildcfg
import internal_os

// --- GKeyFile C bindings --------------------------------------------------
//
// Used to parse `/.flatpak-info` (an INI/keyfile) exactly as ghostty does via
// `glib.KeyFile`. GLib owns the string returned by g_key_file_get_string, so
// we copy it into a V string and free the original with `g_free_mem`.

fn C.g_key_file_new() voidptr

fn C.g_key_file_free(key_file voidptr)

fn C.g_key_file_load_from_file(key_file voidptr, file &char, flags int, error voidptr) int

fn C.g_key_file_get_string(key_file voidptr, group_name &char, key &char, error voidptr) &char

// resources_dir returns the resources directory, consulting the Flatpak
// runtime data when running inside a sandbox. Mirrors `flatpak.resourcesDir`.
pub fn resources_dir() internal_os.ResourcesDir {
	// Only consult Flatpak runtime data for the host case.
	if buildcfg.flatpak && internal_os.is_flatpak() {
		// Inside the sandbox the app resources live at a fixed path.
		mut result := internal_os.ResourcesDir{
			app_path: '/app/share/witty'
		}

		key_file := C.g_key_file_new()
		defer {
			C.g_key_file_free(key_file)
		}

		// If we can't load /.flatpak-info, return just the app path.
		if C.g_key_file_load_from_file(key_file, c'/.flatpak-info', 0, unsafe { nil }) == 0 {
			return result
		}

		// The "app-path" under the "Instance" group is the host-visible path
		// to the app's files.
		app_dir_c := C.g_key_file_get_string(key_file, c'Instance', c'app-path', unsafe { nil })
		if isnil(app_dir_c) {
			return result
		}
		app_dir := unsafe { cstring_to_vstring(app_dir_c) }
		g_free_mem(app_dir_c)

		result.host_path = '${app_dir}/share/witty'
		return result
	}

	// Not sandboxed: use the normal detection.
	return internal_os.resources_dir()
}
