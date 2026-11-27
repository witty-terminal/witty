module internal_os

import witty_macos as macos
// home_macos mirrors NSFileManager.defaultManager's
// homeDirectoryForCurrentUser.path fallback from Ghostty's homedir.zig.
fn home_macos() ?string {
	return macos.home_directory_for_current_user()
}
