module witty_macos

fn test_termination_source_exceptions() {
	assert !should_confirm_termination(0, false, false, 0, true)
	assert !should_confirm_termination(1, false, false, 0, true)
	assert !should_confirm_termination(1, true, true, 0, true)
	for reason in [u32(0x73687574), u32(0x72657374), u32(0x726c676f)] {
		assert !should_confirm_termination(1, true, false, reason, true)
	}
	assert should_confirm_termination(1, true, false, 0, true)
	assert !should_confirm_termination(1, true, false, 0, false)
}

fn test_reopen_source_guards() {
	assert !should_create_reopen_window(true, 0, true)
	assert !should_create_reopen_window(false, 1, true)
	assert !should_create_reopen_window(false, 0, false)
	assert should_create_reopen_window(false, 0, true)
}
