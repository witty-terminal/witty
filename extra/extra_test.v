module extra

import help_strings

fn test_vim_syntax_lists_every_config_key() {
	out := syntax()
	assert out.starts_with('" Vim syntax file\n')
	assert out.contains('let b:current_syntax = \'witty\'')
	assert out.contains('syn keyword wittyConfigKeyword')

	// Every config key appears as a continuation-line keyword, in order.
	mut idx := 0
	for key in help_strings.config_keys {
		needle := '\n\t\\ ${key}'
		found := out.index_after(needle, idx) or {
			assert false, 'missing or out-of-order key: ${key}'
			return
		}
		idx = found + needle.len
	}

	assert out.ends_with('unlet s:cpo_save\n')
}

fn test_vim_static_files_are_carried_over() {
	assert ftdetect.starts_with('" Vim filetype detect file\n')
	assert ftdetect.contains('setf witty')
	assert ftplugin.contains('let b:did_ftplugin = 1')
	assert ftplugin.contains('setlocal commentstring=#\\ %s')
	assert compiler.contains('let current_compiler = "witty"')
	assert compiler.contains('CompilerSet errorformat=%f:%l:%m,%m')
}

fn test_sublime_syntax_alternates_every_config_key() {
	out := sublime_syntax()
	assert out.starts_with('%YAML 1.2\n')
	assert out.contains('scope: source.witty')
	assert out.ends_with('scope: keyword.other.witty\n')

	// The keyword alternation is every key joined by '|', in order.
	start := out.index('- match: \'\\b(') or {
		assert false, 'missing keyword match'
		return
	}
	rest := out[start..]
	open_idx := rest.index('(') or {
		assert false
		return
	}
	close_idx := rest.index(')\\b') or {
		assert false
		return
	}
	assert rest[open_idx + 1..close_idx] == help_strings.config_keys.join('|')
}
