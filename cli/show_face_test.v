module cli

fn test_show_face_options_and_required_input() {
	opts := parse_show_face_options(['--cp=0x41', '--style=bold_italic', '--presentation=text',
		'--font-family=Menlo'])!
	assert opts.cp? == 65
	assert opts.style == .bold_italic
	assert opts.presentation? == .text
	diagnostics := opts.diagnostics.items()
	assert diagnostics.len == 1
	assert diagnostics[0].format() == 'cli:4:font-family: unknown field'

	missing := show_face([])!
	assert missing.code == 1
	assert missing.errors.contains('You must specify a codepoint')
}

fn test_show_face_codepoint_bases_and_invalid_values() {
	for raw in ['65', '0x41', '0o101', '0b1000001', '+0x4__1'] {
		opts := parse_show_face_options(['--cp=${raw}'])!
		assert opts.cp? == 65
		assert opts.diagnostics.empty()
	}
	zero := parse_show_face_options(['--cp=-0'])!
	assert zero.cp? == 0
	for raw in ['0x200000', '0x_41', 'wat'] {
		opts := parse_show_face_options(['--cp=${raw}'])!
		items := opts.diagnostics.items()
		assert items.len == 1
		assert items[0].format() == 'cli:1:cp: invalid value "${raw}"'
	}
}

fn test_show_face_filters_diagnostics_by_parser_ownership() {
	action_error := show_face(['+show-face', '--font-size=14', '--cp=wat'])!
	assert action_error.code == 1
	assert action_error.errors == 'config error: cli:3:cp: invalid value "wat"\n'

	config_error := show_face(['+show-face', '--cp=65', '--config-default-files=false',
		'--unknown-show-face-option=true'])!
	assert config_error.code == 0
	assert config_error.errors == 'config error: cli:4:unknown-show-face-option: unknown field\n'

	empty := show_face(['--cp=65', '--cp=', '--config-default-files=false'])!
	assert empty.code == 1
	assert empty.errors == 'You must specify a codepoint with --cp or a string with --string\n'
}

fn test_show_face_resolves_embedded_face_and_sprites() {
	text := show_face(['--cp=65', '--config-default-files=false'])!
	assert text.code == 0
	assert text.output.contains('U+41 « A » found in face')

	sprite := show_face(['--cp=0x2500', '--config-default-files=false'])!
	assert sprite.code == 0
	assert sprite.output.contains("handled by Witty's internal sprites")
}

fn test_show_face_formats_config_diagnostics() {
	result := show_face(['--cp=65', '--config-default-files=false', '--font-size=wat'])!
	assert result.errors.contains('config error: cli:')
	assert result.errors.contains('font-size:')
	assert !result.errors.contains('Diagnostic{')
}
