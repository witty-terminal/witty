// Vim support files for the Ghostty config file format.
//
// Translated from ghostty/src/extra/vim.zig. The literal file bodies are
// carried over verbatim; the syntax file's keyword list is generated from the
// canonical config key list, as the source generates it from Config's fields.
module extra

import help_strings

// ftdetect is the Vim filetype detection file.
pub const ftdetect = '" Vim filetype detect file\n" Language: Witty config file\n" Maintainer: Witty <https://github.com/witty-terminal/witty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nau BufRead,BufNewFile */witty/config,*/*.witty/config,*/witty/themes/*,*.witty setf witty\n'

// ftplugin is the Vim filetype plugin file.
pub const ftplugin = '" Vim filetype plugin file\n" Language: Witty config file\n" Maintainer: Witty <https://github.com/witty-terminal/witty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nif exists(\'b:did_ftplugin\')\n  finish\nendif\nlet b:did_ftplugin = 1\n\nsetlocal commentstring=#\\ %s\nsetlocal iskeyword+=-\n\n" Use syntax keywords for completion\nsetlocal omnifunc=syntaxcomplete#Complete\n\nlet b:undo_ftplugin = \'setl cms< isk< ofu<\'\n\nif !exists(\'current_compiler\')\n  compiler witty\n  let b:undo_ftplugin .= " makeprg< errorformat<"\nendif\n'

// compiler is the Vim compiler file.
pub const compiler = '" Vim compiler file\n" Language: Witty config file\n" Maintainer: Witty <https://github.com/witty-terminal/witty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nif exists("current_compiler")\n  finish\nendif\nlet current_compiler = "witty"\n\nCompilerSet makeprg=witty\\ +validate-config\\ --config-file=%:S\nCompilerSet errorformat=%f:%l:%m,%m\n'

const syntax_head = '" Vim syntax file\n" Language: Witty config file\n" Maintainer: Witty <https://github.com/witty-terminal/witty>\n"\n" THIS FILE IS AUTO-GENERATED\n\nif exists(\'b:current_syntax\')\n  finish\nendif\n\nlet b:current_syntax = \'witty\'\n\nlet s:cpo_save = &cpo\nset cpo&vim\n\nsyn iskeyword @,48-57,-\nsyn keyword wittyConfigKeyword'

const syntax_tail = '\n\nsyn match wittyConfigComment /^\\s*#.*/ contains=@Spell\n\nhi def link wittyConfigComment Comment\nhi def link wittyConfigKeyword Keyword\n\nlet &cpo = s:cpo_save\nunlet s:cpo_save\n'

// syntax returns the Vim syntax file.
pub fn syntax() string {
	mut out := syntax_head
	for key in help_strings.config_keys {
		out += '\n\t\\ ${key}'
	}
	out += syntax_tail
	return out
}
