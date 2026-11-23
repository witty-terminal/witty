module input

import help_strings

fn test_help_format_source_layout_and_ordinals() {
	assert sizeof(Format) == 1
	assert [Format.plaintext, .markdown].map(u8(it)) == [u8(0), 1]
}

fn test_generate_action_names() {
	help := generate(.plaintext, false)
	assert help.starts_with('ignore\nunbind\ncsi\n')
	assert help.contains('toggle_command_palette\n')
	assert help.ends_with('crash\n')
}

fn test_generate_plaintext_docs() {
	help := generate(.plaintext, true)
	assert help.starts_with('\nignore:\n  Ignore this key combination.\n  \n  Ghostty will not process')
	assert help.contains('new_window:\n  Open a new window.\n  \n')
	assert help.contains('toggle_readonly:\n  Toggle read-only mode for the current surface.\n  \n')
	assert help.ends_with('    Crash on the render thread for the focused surface.\n')
}

fn test_generate_markdown() {
	help := generate(.markdown, true)
	assert help.starts_with('---\ntitle: Keybinding Action Reference\n')
	assert help.contains('## `copy_to_clipboard`\nCopy the selected text to the clipboard.\n')
}

fn test_embedded_action_help_matches_every_translated_tag() {
	entries := help_strings.generated_help_entries(generated_action_help_data(), '@@')
	mut tags := []string{}
	$for enum_value in ActionTag.values {
		tags << enum_value.name
	}
	assert entries.map(it.name) == tags
	assert entries.len == 83
	assert entries.all(it.text.len > 0)
}
