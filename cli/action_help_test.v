module cli

fn test_generated_action_help_covers_source_action_enum() {
	names := [
		'version',
		'help',
		'list-fonts',
		'list-keybinds',
		'list-themes',
		'list-colors',
		'list-actions',
		'ssh-cache',
		'edit-config',
		'show-config',
		'validate-config',
		'crash-report',
		'show-face',
		'boo',
		'new-window',
	]
	for name in names {
		help := action_help_output(name) or { panic('missing action help for ${name}') }
		assert help.len > 2
		assert help.ends_with('\n\n')
	}
	assert action_help_output('none') == none
	assert action_help_output('not-an-action') == none
}

fn test_action_help_matches_generated_source_text() {
	list_actions := action_help_output('list-actions') or { panic('missing list-actions help') }
	assert list_actions == 'The `list-actions` command is used to list all the available keybind\n' + 'actions for Witty. These are distinct from the CLI Actions which can\n' + 'be listed via `+help`\n\n' + 'Flags:\n\n' + '  * `--docs`: will print out the documentation for each action.\n\n'

	new_window := action_help_output('new-window') or { panic('missing new-window help') }
	assert new_window.contains('arguments after the `-e` flag')
	assert new_window.ends_with('Available since: 1.2.0\n\n')
}

fn test_action_option_parsers_propagate_help_request() {
	if _ := list_actions_output(['--help']) {
		assert false, 'list-actions help must leave through ActionHelpRequested'
	} else {
		assert is_action_help_requested(err)
	}
	if _ := parse_list_themes_options(['-h']) {
		assert false, 'list-themes help must leave through ActionHelpRequested'
	} else {
		assert is_action_help_requested(err)
	}
	if _ := parse_list_themes_options(['--unknown', '--help']) {
		assert false, 'an earlier option error must win over a later help request'
	} else {
		assert !is_action_help_requested(err)
	}
	if _ := parse_show_face_options(['--help']) {
		assert false, 'show-face help must leave through ActionHelpRequested'
	} else {
		assert is_action_help_requested(err)
	}
	if _ := parse_ssh_cache_options(['-h']) {
		assert false, 'ssh-cache help must leave through ActionHelpRequested'
	} else {
		assert is_action_help_requested(err)
	}
	if _ := run_show_face(['--help']) {
		assert false, 'show-face runner must preserve ActionHelpRequested'
	} else {
		assert is_action_help_requested(err)
	}
	if _ := new_window_result(['--help']) {
		assert false, 'new-window runner must preserve ActionHelpRequested'
	} else {
		assert is_action_help_requested(err)
	}
}

fn test_new_window_stops_option_parsing_after_execute_flag() {
	if _ := parse_new_window_options(['--help', '-e', 'echo']) {
		assert false, 'help before -e must request action help'
	} else {
		assert is_action_help_requested(err)
	}

	opts := parse_new_window_options(['-e', 'echo', '--help'])!
	assert opts.arguments or { []string{} } == ['echo', '--help']
}
