module main

import crypto.sha256

fn test_build_data_action_names_match_source_spellings() {
	assert sizeof(BuildDataAction) == 1
	assert [BuildDataAction.bash, .fish, .zsh, .sublime, .vim_syntax, .vim_ftdetect,
		.vim_ftplugin, .vim_compiler, .terminfo].map(u8(it)) == [u8(0), 1, 2, 3, 4, 5,
		6, 7, 8]
	// These are the `+action` spellings main_build_data.zig accepts.
	assert BuildDataAction.bash.name() == 'bash'
	assert BuildDataAction.fish.name() == 'fish'
	assert BuildDataAction.zsh.name() == 'zsh'
	assert BuildDataAction.sublime.name() == 'sublime'
	assert BuildDataAction.vim_syntax.name() == 'vim-syntax'
	assert BuildDataAction.vim_ftdetect.name() == 'vim-ftdetect'
	assert BuildDataAction.vim_ftplugin.name() == 'vim-ftplugin'
	assert BuildDataAction.vim_compiler.name() == 'vim-compiler'
	assert BuildDataAction.terminfo.name() == 'terminfo'
}

fn test_build_data_action_parses_with_and_without_plus() {
	assert build_data_action('terminfo')? == .terminfo
	assert build_data_action('+terminfo')? == .terminfo
	assert build_data_action('+vim-ftplugin')? == .vim_ftplugin
	assert build_data_action('bash')? == .bash
	assert build_data_action('+fish')? == .fish
	assert build_data_action('zsh')? == .zsh
	assert build_data_action('nonsense') == none
}

fn test_generate_build_data_emits_each_artifact() {
	terminfo_src := generate_build_data(.terminfo)
	assert terminfo_src.starts_with('xterm-witty|witty|Witty,\n')
	assert terminfo_src.contains('\tam,\n')

	assert generate_build_data(.sublime).starts_with('%YAML 1.2\n')
	assert generate_build_data(.vim_syntax).starts_with('" Vim syntax file\n')
	assert generate_build_data(.vim_ftdetect).contains('setf witty')
	assert generate_build_data(.vim_ftplugin).contains('let b:did_ftplugin = 1')
	assert generate_build_data(.vim_compiler).contains('let current_compiler = "witty"')
}

fn test_generate_build_data_matches_witty_artifacts() {
	// Hashes pin the generated Witty artifacts.
	expected := {
		BuildDataAction.bash:         '37438c3c98370b46d3cd6c8c97648e357923bad0dd27a85d0e6d5dd9ec01d9ee'
		BuildDataAction.fish:         'bbe81f47e171da2adfad1f952868712daeaa6f3827d3f55bbc8f208a1b91d753'
		BuildDataAction.zsh:          '82d264b152871b2a7247cd45e2972c8e4fd52e05d54ebb97a5392d2687da9990'
		BuildDataAction.sublime:      '864ce2c091b2095676ccca3975301ea23f9b42645d2dc93cc71bcb1ddacab63f'
		BuildDataAction.vim_syntax:   'd9095d91168363cada00cf50647fc21efcdc455852d3580705efbb73f1e9725a'
		BuildDataAction.vim_ftdetect: '0d39522cbe44c40eeed72e7474dccd157f20130a4d1e73ac383e0f6556277076'
		BuildDataAction.vim_ftplugin: '90b46564eac99d4ad50e79ff07e57bb5d1df7c416baaed4580bf87f0463e0c82'
		BuildDataAction.vim_compiler: '137e96714e6adf30d7f31eac1a71c27064c371c57fce734333bcd2e823a2afce'
		BuildDataAction.terminfo:     'e6781d7c6d2e7c76735f95d6c7eea54ab90b60c4ff6bad1ba49b0102fb16eaa3'
	}
	for action, digest in expected {
		actual := sha256.sum(generate_build_data(action).bytes()).hex()
		assert actual == digest, '${action.name()} output changed'
	}
}
