// Translated from Ghostty's helpgen.zig.
//
// Zig's generator combines compile-time reflection with its Zig AST parser.
// The generated records are embedded here so this translated interface has
// the same output without depending on source files at runtime.
module help_strings

// Build-time inputs come from the pinned records. Importing their runtime
// consumers would bring in the renderer and its native libraries.
const config_records = $embed_file('../configpkg/config_help.txt').to_string()
const action_records = $embed_file('../cli/cli_action_help.txt').to_string()
const keybind_records = $embed_file('../input/keybind_action_help.txt').to_string()

// HelpEntry represents a single documented configuration field or action.
pub struct HelpEntry {
pub:
	name string
	text string
}

pub struct ConfigHelp {
pub:
	entries []HelpEntry
}

pub struct ActionHelp {
pub:
	entries []HelpEntry
}

pub struct KeybindActionHelp {
pub:
	entries []HelpEntry
}

// gen_config returns the generated public Config field documentation.
pub fn gen_config() ConfigHelp {
	return ConfigHelp{
		entries: generated_help_entries(config_records, '\x1e').filter(!it.name.starts_with('_'))
	}
}

// gen_actions returns the generated documentation from every CLI action run
// function, in source enum order.
pub fn gen_actions() ActionHelp {
	parsed := generated_help_entries(action_records, '@@')
	// The source reflects Action's enum order. The retained generated input
	// records predate a show-face/crash-report ordering correction.
	mut entries := []HelpEntry{}
	for name in ['version', 'help', 'list-fonts', 'list-keybinds', 'list-themes', 'list-colors',
		'list-actions', 'ssh-cache', 'edit-config', 'show-config', 'validate-config',
		'show-face', 'crash-report', 'boo', 'new-window'] {
		for entry in parsed { if entry.name == name { entries << entry; break } }
	}
	return ActionHelp{
		entries: entries
	}
}

// gen_keybind_actions returns the generated Binding.Action union docs.
pub fn gen_keybind_actions() KeybindActionHelp {
	return KeybindActionHelp{
		entries: generated_help_entries(keybind_records, '@@')
	}
}

pub fn generated_help_entries(source string, marker string) []HelpEntry {
	mut result := []HelpEntry{}
	mut name := ''
	mut docs := []string{}
	for line in source.split_into_lines() {
		if line.starts_with(marker) {
			if name.len > 0 && name != '__end' {
				result << HelpEntry{
					name: name
					text: docs.join('\n')
				}
			}
			name = line[marker.len..]
			docs = []string{}
			continue
		}
		docs << line
	}
	if name.len > 0 && name != '__end' {
		result << HelpEntry{
			name: name
			text: docs.join('\n')
		}
	}
	return result
}
