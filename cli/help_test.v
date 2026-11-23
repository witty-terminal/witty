module cli

import cli_args

fn test_help_output_matches_source_text_and_action_enum() {
	help := help_output()
	command := 'witty'
	assert help.starts_with('Usage: ${command} [+action] [options]\n\n')
	assert help.contains('`${command} -e top`')
	assert help.contains('Run the Witty terminal emulator or a specific helper action.\n')
	assert help.contains('  +list-actions\n')
	assert help.ends_with('where `<action>` is one of actions listed above.\n')
}

fn test_help_action_parses_its_ordinary_help_field() {
	mut opts := HelpOptions{}
	cli_args.parse(mut opts, ['--help'])!
	assert opts.help

	if _ := cli_args.parse(mut opts, ['--unknown']) {
		assert false, 'unknown help action fields must fail'
	} else {
		assert err.msg() == 'invalid field'
	}
}
