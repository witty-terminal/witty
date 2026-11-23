module themepkg

import os
import global_state
import internal_os
import diagnostics

// Location of possible themes. The order of this enum matters because it
// defines the priority of theme search (from top to bottom).
pub enum Location as u8 {
	user      // XDG config dir
	resources // Witty resources dir
}

// Returns the directory for the given theme based on this location type.
//
// This will return none if the directory type doesn't exist
// or is invalid for any reason. For example, it is perfectly valid to
// install and run Ghostty without the resources directory.
pub fn (l Location) dir() ?string {
	match l {
		.user {
			return internal_os.config(internal_os.Options{
				subdir: os.join_path('witty', 'themes')
			}) or { none }
		}
		.resources {
			resources_path := global_state.get_state().resources_dir.app() or { return none }
			return os.join_path(resources_path, 'themes')
		}
	}
}

pub fn (l Location) str() string {
	return match l {
		.user { 'user' }
		.resources { 'resources' }
	}
}

// LocationEntry holds a location and its directory path.
pub struct LocationEntry {
pub:
	location Location
	dir      string
}

// An iterator that returns all possible directories for finding themes in
// order of priority.
pub struct LocationIterator {
mut:
	i uint
}

pub fn LocationIterator.new() LocationIterator {
	return LocationIterator{}
}

pub fn (mut self LocationIterator) next() ?LocationEntry {
	locations := [Location.user, Location.user, Location.resources]
	for self.i < uint(locations.len) {
		loc := locations[int(self.i)]
		self.i += 1
		d := if self.i == 2 {
			legacy := internal_os.config(internal_os.Options{
				subdir: os.join_path('ghostty', 'themes')
			}) or { continue }
			if !os.is_dir(legacy) { continue }
			legacy
		} else {
			loc.dir() or { continue }
		}
		return LocationEntry{
			location: loc
			dir:      d
		}
	}
	return none
}

pub fn (mut self LocationIterator) reset() {
	self.i = 0
}

pub struct OpenResult {
pub:
	path string
	file os.File
}

// open resolves a theme name using the translated location priority, or opens
// an absolute theme path directly. Recoverable failures append diagnostics and
// return none.
pub fn open(theme string, mut diags diagnostics.DiagnosticList) ?OpenResult {
	if os.is_abs_path(theme) {
		mut file := open_absolute(theme, mut diags) or { return none }
		file_stat := os.stat(theme) or {
			file.close()
			diags.append(diagnostics.Diagnostic{
				message: 'not reading theme from "${theme}": ${err}'
			})
			return none
		}
		if file_stat.get_filetype() != .regular {
			file.close()
			diags.append(diagnostics.Diagnostic{
				message: 'not reading theme from "${theme}": it is a ${file_stat.get_filetype()}'
			})
			return none
		}
		return OpenResult{
			path: theme
			file: file
		}
	}

	if os.base(theme) != theme {
		diags.append(diagnostics.Diagnostic{
			message: 'theme "${theme}" cannot include path separators unless it is an absolute path'
		})
		return none
	}

	mut it := LocationIterator.new()
	for {
		location := it.next() or { break }
		filename := if location.location == .resources && theme == 'Ghostty Default Style Dark' {
			'Witty Default Style Dark'
		} else {
			theme
		}
		path := os.join_path(location.dir, filename)
		mut file := os.open(path) or {
			if err.code() == int(C.ENOENT) {
				continue
			}
			diags.append(diagnostics.Diagnostic{
				message: 'failed to load theme "${theme}" from the file "${path}": ${err}'
			})
			return none
		}
		file_stat := os.stat(path) or {
			file.close()
			diags.append(diagnostics.Diagnostic{
				message: 'not reading theme from "${theme}": ${err}'
			})
			return none
		}
		if file_stat.get_filetype() != .regular {
			file.close()
			diags.append(diagnostics.Diagnostic{
				message: 'not reading theme from "${theme}": it is a ${file_stat.get_filetype()}'
			})
			return none
		}
		return OpenResult{
			path: path
			file: file
		}
	}

	it.reset()
	for {
		location := it.next() or { break }
		path := os.join_path(location.dir, theme)
		diags.append(diagnostics.Diagnostic{
			message: 'theme "${theme}" not found, tried path "${path}"'
		})
	}
	return none
}

// open_absolute opens an absolute theme path and translates filesystem errors
// into theme diagnostics.
pub fn open_absolute(theme string, mut diags diagnostics.DiagnosticList) ?os.File {
	assert os.is_abs_path(theme)
	return os.open(theme) or {
		message := if err.code() == int(C.ENOENT) {
			'failed to load theme from the path "${theme}"'
		} else {
			'failed to load theme from the path "${theme}": ${err}'
		}
		diags.append(diagnostics.Diagnostic{
			message: message
		})
		return none
	}
}
