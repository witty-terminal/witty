// Sublime Text syntax file for the Ghostty config file format.
//
// Translated from ghostty/src/extra/sublime.zig. The template is carried over
// verbatim; the keyword alternation is generated from the canonical config key
// list, as the source generates it from Config's fields.
module extra

import help_strings

const sublime_header = '%YAML 1.2\n---\n# See http://www.sublimetext.com/docs/syntax.html\nname: Witty Config\nfile_extensions:\n  - witty\nscope: source.witty\n\ncontexts:\n  main:\n    # Comments\n    - match: \'^\\s*#.*$\'\n      scope: comment.line.number-sign.witty\n\n    # Keywords\n    - match: \'\\b('

const sublime_footer = ')\\b\'\n      scope: keyword.other.witty\n'

// sublime_syntax returns the Sublime Text syntax file.
pub fn sublime_syntax() string {
	return sublime_header + help_strings.config_keys.join('|') + sublime_footer
}
