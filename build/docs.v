module build

import build_meta
import help_strings
import strings

// Documentation generators translated from src/build/mdgen and
// src/build/webgen. The source obtains these records from HelpStrings.zig;
// Witty embeds the pinned help records for the standalone documentation tool.

const ghostty_1_header = $embed_file('ghostty_1_header.md').to_string()
const ghostty_1_footer = $embed_file('ghostty_1_footer.md').to_string()
const ghostty_5_header = $embed_file('ghostty_5_header.md').to_string()
const ghostty_5_footer = $embed_file('ghostty_5_footer.md').to_string()

fn find_doc(entries []help_strings.HelpEntry, name string) ?string {
	for entry in entries {
		if entry.name == name {
			return entry.text
		}
	}
	return none
}

// substitute replaces the manpage version marker with the pinned build
// version, matching mdgen.substitute.
pub fn substitute(input_text string) string {
	return input_text.replace('@@VERSION@@', build_meta.version_string)
}

fn write_definition_docs(mut out strings.Builder, docs string) {
	// splitScalar in the source preserves a final empty field. This matters
	// when a documentation comment intentionally ends in a blank line.
	lines := docs.split('\n')
	for i, line in lines {
		out.write_string(if i == 0 { ':   ' } else { '    ' })
		out.write_string(line)
		out.write_u8(`\n`)
	}
	out.write_string('\n\n')
}

// gen_config emits the configuration section used by both Ghostty manpages.
// cli selects the `--option` spelling used by ghostty(1).
pub fn gen_config(cli_options bool) string {
	docs := help_strings.gen_config().entries
	mut out := strings.new_builder(help_strings.config_keys.len * 128)
	out.write_string('\n# CONFIGURATION OPTIONS\n\n')
	for key in help_strings.config_keys {
		out.write_string('**`')
		if cli_options {
			out.write_string('--')
		}
		out.write_string(key)
		out.write_string('`**\n\n')
		if text := find_doc(docs, key) {
			write_definition_docs(mut out, text)
		}
	}
	return out.str()
}

// gen_actions emits the command-line action section used by ghostty(1).
pub fn gen_actions() string {
	docs := help_strings.gen_actions().entries
	mut out := strings.new_builder(docs.len * 128)
	out.write_string('\n# COMMAND LINE ACTIONS\n\n')
	for entry in docs {
		name := entry.name
		match name {
			'help' { out.write_string('**`--help`**\n\n') }
			'version' { out.write_string('**`--version`**\n\n') }
			else { out.write_string('**`+${name}`**\n\n') }
		}
		write_definition_docs(mut out, entry.text)
	}
	return out.str()
}

// gen_keybind_actions emits the keybinding action section used by ghostty(5).
pub fn gen_keybind_actions() string {
	docs := help_strings.gen_keybind_actions().entries
	mut out := strings.new_builder(docs.len * 128)
	out.write_string('\n# KEYBIND ACTIONS\n\n')
	for entry in docs {
		if entry.name.starts_with('_') {
			continue
		}
		out.write_string('**`${entry.name}`**\n\n')
		write_definition_docs(mut out, entry.text)
	}
	return out.str()
}

// gen_web_actions generates the website CLI-action reference.
pub fn gen_web_actions() string {
	docs := help_strings.gen_actions().entries
	mut out := strings.new_builder(docs.len * 128)
	out.write_string('---\n')
	out.write_string('title: Reference\n')
	out.write_string('description: Reference of all Ghostty action subcommands.\n')
	out.write_string('editOnGithubLink: https://github.com/ghostty-org/ghostty/tree/main/src/cli\n')
	out.write_string('---\n')
	out.write_string('Ghostty includes a number of utility actions that can be accessed as subcommands.\n')
	out.write_string('Actions provide utilities to work with config, list keybinds, list fonts, demo themes,\n')
	out.write_string('and debug.\n')
	for entry in docs {
		name := entry.name
		out.write_string('## ${name}\n')
		out.write_string(entry.text)
		out.write_string('\n\n```\n')
		match name {
			'help', 'version' { out.write_string('ghostty --${name}\n') }
			else { out.write_string('ghostty +${name}\n') }
		}
		out.write_string('```\n\n')
	}
	return out.str()
}

enum WebDocBlock as u8 {
	text
	code
	callout_note
	callout_warning
}

fn end_web_block(mut out strings.Builder, block ?WebDocBlock) {
	if value := block {
		match value {
			.text {}
			.code { out.write_string('```\n') }
			.callout_note { out.write_string('</Note>\n') }
			.callout_warning { out.write_string('</Warning>\n') }
		}
	}
}

fn starts_with_ignore_case(value string, prefix string) bool {
	if value.len < prefix.len {
		return false
	}
	return value[..prefix.len].to_lower() == prefix.to_lower()
}

// gen_web_config generates the website configuration reference and performs
// the same deliberately small markdown rewrite as the pinned Zig generator.
pub fn gen_web_config() string {
	docs := help_strings.gen_config().entries
	mut out := strings.new_builder(help_strings.config_keys.len * 192)
	out.write_string('---\n')
	out.write_string('title: Reference\n')
	out.write_string('description: Reference of all Ghostty configuration options.\n')
	out.write_string('editOnGithubLink: https://github.com/ghostty-org/ghostty/edit/main/src/config/Config.zig\n')
	out.write_string('---\n\n')
	out.write_string('This is a reference of all Ghostty configuration options. These\n')
	out.write_string('options are ordered roughly by how common they are to be used\n')
	out.write_string('and grouped with related options. I recommend utilizing your\n')
	out.write_string("browser's search functionality to find the option you're looking\n")
	out.write_string('for.\n\n')
	out.write_string("In the future, we'll have a more user-friendly way to view and\n")
	out.write_string('organize these options.\n\n')

	for i, key in help_strings.config_keys {
		text := find_doc(docs, key) or { continue }
		out.write_string('## `${key}`\n')

		// Undocumented fields following a documented field are grouped under
		// that field until the next documented field.
		if i + 1 < help_strings.config_keys.len {
			for next_key in help_strings.config_keys[i + 1..] {
				if _ := find_doc(docs, next_key) {
					break
				}
				out.write_string('## `${next_key}`\n')
			}
		}
		out.write_u8(`\n`)

		mut block := ?WebDocBlock(none)
		for line in text.split('\n') {
			if line.len == 0 {
				end_web_block(mut out, block)
				block = none
				out.write_u8(`\n`)
				continue
			}

			first := block == none
			if first {
				if line.starts_with('    ') {
					block = .code
					out.write_string('```\n')
				} else if starts_with_ignore_case(line, 'note:') {
					block = .callout_note
					out.write_string('<Note>\n')
				} else if starts_with_ignore_case(line, 'warning:') {
					block = .callout_warning
					out.write_string('<Warning>\n')
				} else {
					block = .text
				}
			}

			value := match block or { WebDocBlock.text } {
				.text { line }
				.callout_note { if first { line['note:'.len..] } else { line } }
				.callout_warning { if first { line['warning:'.len..] } else { line } }
				.code { if line.starts_with('    ') { line[4..] } else { line } }
			}
			out.write_string(value)
			out.write_u8(`\n`)
		}
		end_web_block(mut out, block)
		out.write_u8(`\n`)
	}
	return out.str()
}

// gen_web_keybind_actions is the webgen/actions entry point.
pub fn gen_web_keybind_actions() string {
	return help_strings.web_keybind_actions()
}

// ghostty_1 generates the complete ghostty(1) markdown source.
pub fn ghostty_1() string {
	return substitute(ghostty_1_header) + gen_actions() + gen_config(true) + substitute(ghostty_1_footer)
}

// ghostty_5 generates the complete ghostty(5) markdown source.
pub fn ghostty_5() string {
	return substitute(ghostty_5_header) + gen_config(false) + gen_keybind_actions() +
		substitute(ghostty_5_footer)
}
