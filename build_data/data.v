// Translated from src/main_build_data.zig; shared by the standalone host tool.
module build_data

import extra
import terminfo

// cli.action.detectIter specialized to the generator's enum. Only a leading
// '+' marks an action; an unknown or second action fails before generating.
pub fn detect_action(args []string) !BuildDataAction {
	mut pending := ?BuildDataAction(none)
	for arg in args {
		if !arg.starts_with('+') { continue }
		if pending != none { return error('MultipleActions') }
		pending = build_data_action(arg[1..]) or { return error('InvalidAction') }
	}
	return pending or { return error('NoAction') }
}

// BuildDataAction is the complete set of artifacts emitted by the source
// command, in source declaration order.
pub enum BuildDataAction as u8 {
	// Shell completions
	bash
	fish
	zsh

	// Editor syntax files
	sublime
	vim_syntax
	vim_ftdetect
	vim_ftplugin
	vim_compiler

	// Other
	terminfo
}

// build_data_action_name is the `+action` spelling for an action, matching the
// source's enum field names.
pub fn (action BuildDataAction) name() string {
	return match action {
		.bash { 'bash' }
		.fish { 'fish' }
		.zsh { 'zsh' }
		.sublime { 'sublime' }
		.vim_syntax { 'vim-syntax' }
		.vim_ftdetect { 'vim-ftdetect' }
		.vim_ftplugin { 'vim-ftplugin' }
		.vim_compiler { 'vim-compiler' }
		.terminfo { 'terminfo' }
	}
}

// build_data_action parses a `+action` spelling, or none if unrecognized.
pub fn build_data_action(name string) ?BuildDataAction {
	trimmed := name.trim_string_left('+')
	for action in [BuildDataAction.bash, .fish, .zsh, .sublime, .vim_syntax, .vim_ftdetect,
		.vim_ftplugin, .vim_compiler, .terminfo] {
		if action.name() == trimmed {
			return action
		}
	}
	return none
}

// generate_build_data returns the artifact for the given action. The source
// writes this to stdout.
pub fn generate_build_data(action BuildDataAction) string {
	return match action {
		.bash { extra.bash_completions() }
		.fish { extra.fish_completions() }
		.zsh { extra.zsh_completions() }
		.sublime { extra.sublime_syntax() }
		.vim_syntax { extra.syntax() }
		.vim_ftdetect { extra.ftdetect }
		.vim_ftplugin { extra.ftplugin }
		.vim_compiler { extra.compiler }
		.terminfo { terminfo.witty.encode() }
	}
}
