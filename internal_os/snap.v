module internal_os

// filter_snap_paths removes Snap variables and removes path components rooted
// in one of the Snap directories. TERMINFO and Ghostty-owned variables are
// derived from Ghostty's Linux surface implementation.
pub fn filter_snap_paths(mut env map[string]string) {
	snap_vars := ['SNAP', 'SNAP_USER_COMMON', 'SNAP_USER_DATA', 'SNAP_DATA', 'SNAP_COMMON']
	mut env_to_remove := []string{}
	mut env_to_update := map[string]string{}

	for key, value in env {
		if key == 'TERMINFO' || key.starts_with('GHOSTTY') {
			continue
		}
		if key.starts_with('SNAP_') {
			env_to_remove << key
			continue
		}

		mut filtered_paths := []string{}
		mut modified := false
		for path in value.split(':') {
			mut include := true
			for snap_var in snap_vars {
				snap_path := env[snap_var] or { continue }
				if snap_path.len > 0 && path.starts_with(snap_path) {
					include = false
					modified = true
					break
				}
			}
			if include {
				filtered_paths << path
			}
		}

		if modified {
			if filtered_paths.len > 0 {
				env_to_update[key] = filtered_paths.join(':')
			} else {
				env_to_remove << key
			}
		}
	}

	for key, value in env_to_update {
		env[key] = value
	}
	for key in env_to_remove {
		env.delete(key)
	}
}
