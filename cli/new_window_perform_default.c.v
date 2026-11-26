module cli

// The Linux implementation launches a new process for the new-window action.
fn perform_new_window_ipc(opts NewWindowOptions) !bool {
	_ = opts
	return false
}
