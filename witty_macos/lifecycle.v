module witty_macos

// AppDelegate.applicationShouldTerminate / applicationShouldHandleReopen.
pub fn should_confirm_termination(window_count int, any_visible bool, installing_update bool, apple_event_reason u32, core_needs_confirm bool) bool {
	if window_count == 0 || installing_update || !any_visible {
		return false
	}
	// kAEShutDown, kAERestart, kAEReallyLogOut (AERegistry.h).
	if apple_event_reason in [u32(0x73687574), u32(0x72657374), u32(0x726c676f)] {
		return false
	}
	return core_needs_confirm
}

pub fn should_create_reopen_window(has_visible_windows bool, controller_count int, has_become_active bool) bool {
	return !has_visible_windows && controller_count == 0 && has_become_active
}
