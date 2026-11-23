// Vim support files for the Ghostty config file format.
//
// Translated from ghostty/src/extra/vim.zig. The literal file bodies are
// carried over verbatim; the syntax file's keyword list is generated from the
// canonical config key list, as the source generates it from Config's fields.
module extra

import help_strings

// ftdetect is the Vim filetype detection file.
pub const ftdetect = '" Vim filetype detect file\n" Language: Ghostty config file\n" Maintainer: Ghostty <https://github.com/ghostty-org/ghostty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nau BufRead,BufNewFile */ghostty/config,*/*.ghostty/config,*/ghostty/themes/*,*.ghostty setf ghostty\n'

// ftplugin is the Vim filetype plugin file.
pub const ftplugin = '" Vim filetype plugin file\n" Language: Ghostty config file\n" Maintainer: Ghostty <https://github.com/ghostty-org/ghostty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nif exists(\'b:did_ftplugin\')\n  finish\nendif\nlet b:did_ftplugin = 1\n\nsetlocal commentstring=#\\ %s\nsetlocal iskeyword+=-\n\n" Use syntax keywords for completion\nsetlocal omnifunc=syntaxcomplete#Complete\n\nlet b:undo_ftplugin = \'setl cms< isk< ofu<\'\n\nif !exists(\'current_compiler\')\n  compiler ghostty\n  let b:undo_ftplugin .= " makeprg< errorformat<"\nendif\n'

// compiler is the Vim compiler file.
pub const compiler = '" Vim compiler file\n" Language: Ghostty config file\n" Maintainer: Ghostty <https://github.com/ghostty-org/ghostty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nif exists("current_compiler")\n  finish\nendif\nlet current_compiler = "ghostty"\n\nCompilerSet makeprg=ghostty\\ +validate-config\\ --config-file=%:S\nCompilerSet errorformat=%f:%l:%m,%m\n'

const syntax_head = '" Vim syntax file\n" Language: Ghostty config file\n" Maintainer: Ghostty <https://github.com/ghostty-org/ghostty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nif exists(\'b:current_syntax\')\n  finish\nendif\n\nlet b:current_syntax = \'ghostty\'\n\nlet s:cpo_save = &cpo\nset cpo&vim\n\nsyn iskeyword @,48-57,-\nsyn keyword ghosttyConfigKeyword'

const syntax_tail = '\n\nsyn match ghosttyConfigComment /^\\s*#.*/ contains=@Spell\n\nhi def link ghosttyConfigComment Comment\nhi def link ghosttyConfigKeyword Keyword\n\nlet &cpo = s:cpo_save\nunlet s:cpo_save\n'

// syntax returns the Vim syntax file.
pub fn syntax() string {
	mut out := syntax_head
	for key in help_strings.config_keys {
		out += '\n\t\\ ${key}'
	}
	out += syntax_tail
	return out
}
