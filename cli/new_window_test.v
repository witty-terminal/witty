module cli

fn test_new_window_options_parse_class_and_command() {
	opts := parse_new_window_options(['--font-size=14', '--class=com.example.Witty', '-e', 'bash',
		'-c', 'echo hello'])!
	assert opts.class or { '' } == 'com.example.Witty'
	assert opts.arguments or { []string{} } == ['bash', '-c', 'echo hello']
}

fn test_new_window_options_empty_class_resets_to_detect() {
	opts := parse_new_window_options(['--class=custom', '--class='])!
	assert opts.class == none
}

fn test_new_window_rejects_empty_command() {
	result := new_window_result(['-e'])!
	assert result.code == 1
	assert result.errors == 'The -e flag was specified on the command line, but no other arguments were found.\n'
}

fn test_new_window_requires_class_value() {
	result := new_window_result(['--class'])!
	assert result.code == 1
	assert result.errors == 'config error: cli:1:class: value required\n'
}

fn test_new_window_filters_config_diagnostics() {
	opts := parse_new_window_options(['--font-size=14', '--class'])!
	items := opts.diagnostics.items()
	assert items.len == 2
	assert items[0].key == 'font-size'
	assert items[1].key == 'class'

	result := new_window_result(['--font-size=14', '--class'])!
	assert result.code == 1
	assert result.errors == 'config error: cli:2:class: value required\n'

	with_action := new_window_result(['+new-window', '--class'])!
	assert with_action.code == 1
	assert with_action.errors == 'config error: cli:2:class: value required\n'
}

$if !linux {
	fn test_new_window_reports_unsupported_platform() {
		result := new_window_result([])!
		assert result.code == 1
		assert result.errors == '+new-window is not supported on this platform.\n'
	}
}
