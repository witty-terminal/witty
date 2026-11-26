module cli

import os

fn perform_new_window_ipc(opts NewWindowOptions) !bool {
	executable := os.executable()
	mut args := []string{}
	if class := opts.class {
		args << '--class=${class}'
	}
	if command := opts.arguments {
		args << '-e'
		args << command
	}
	os.execvp(executable, args)!
	return true
}
