module internal_os

import os

// ResourcesDir holds the application resources directory path.
// Translated from ghostty/src/os/resourcesdir.zig ResourcesDir.
pub struct ResourcesDir {
pub mut:
	// Avoid accessing these directly, use the app() and host() methods instead.
	app_path  ?string
	host_path ?string
}

// deinit releases the owned paths. V's strings are garbage-collected, so
// clearing the references is the ownership-equivalent operation and no
// allocator parameter is required.
pub fn (mut r ResourcesDir) deinit() {
	r.app_path = none
	r.host_path = none
}

// app returns the directory to the bundled resources directory accessible
// by the application.
pub fn (r ResourcesDir) app() ?string {
	return r.app_path
}

// host returns the directory to the bundled resources directory accessible
// by the host environment (i.e. for sandboxed applications). The returned
// directory might not be accessible from the application itself.
//
// In a non-sandboxed environment this is the same as app().
pub fn (r ResourcesDir) host() ?string {
	if p := r.host_path {
		return p
	}
	return r.app_path
}

// The sentinel values are target-specific because each package layout uses
// the exact terminfo database format selected by the pinned build.
const resources_sentinels = $if windows {
	['terminfo/witty.terminfo']
} $else $if macos {
	[
		'terminfo/78/xterm-witty',
	]
} $else $if freebsd {
	['site-terminfo/w/witty', 'site-terminfo/x/xterm-witty']
} $else {
	[
		'terminfo/w/witty',
		'terminfo/x/xterm-witty',
	]
}

// resources_dir gets the directory to the bundled resources directory, if it
// exists (not all platforms or packages have it). This translates Ghostty's
// internal_os.resourcesDir.
//
// Release builds prefer GHOSTTY_RESOURCES_DIR. Debug builds search beside the
// current executable first so a newly built Witty does not inherit stale
// resources from an older parent process.
pub fn resources_dir() ResourcesDir {
	$if !debug {
		if env := resources_dir_from_env() {
			return env
		}
	}

	detected := resources_dir_from_exe(os.executable())
	if detected.app() != none {
		return detected
	}

	$if debug {
		if env := resources_dir_from_env() {
			return env
		}
	}
	return ResourcesDir{}
}

fn resources_dir_from_env() ?ResourcesDir {
	if dir := os.getenv_opt('GHOSTTY_RESOURCES_DIR') {
		if dir.len > 0 {
			return ResourcesDir{
				app_path: dir
			}
		}
	}
	return none
}

// resources_dir_from_exe climbs the directory tree starting from the given
// executable path, looking for the terminfo bundle as Ghostty expects it.
fn resources_dir_from_exe(exe_path string) ResourcesDir {
	mut exe := exe_path

	for {
		dir := os.dir(exe)
		if dir == exe || dir == '.' || dir.len == 0 {
			break
		}
		exe = dir

		$if macos || ios {
			for sentinel in resources_sentinels {
				if v := maybe_dir(dir, 'Contents/Resources', sentinel) {
					return ResourcesDir{
						app_path: os.join_path(v, 'witty')
					}
				}
			}
		}

		sub := $if freebsd { 'local/share' } $else { 'share' }
		for sentinel in resources_sentinels {
			if v := maybe_dir(dir, sub, sentinel) {
				return ResourcesDir{
					app_path: os.join_path(v, 'witty')
				}
			}
		}
	}

	return ResourcesDir{}
}

// maybe_dir checks if "base/sub/suffix" exists and returns "base/sub" when
// it does. This translates Ghostty's maybeDir helper.
pub fn maybe_dir(base string, sub string, suffix string) ?string {
	path := '${base}/${sub}/${suffix}'
	if os.exists(path) {
		return '${base}/${sub}'
	}
	return none
}
