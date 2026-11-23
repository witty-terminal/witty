module input

import help_strings

$if generated_help_strings ? {
	const binding_action_help_data = $embed_file('@VMODROOT/.witty-build/generated/keybind_action_help.txt').to_string()
} $else {
	const binding_action_help_data = $embed_file('keybind_action_help.txt').to_string()
}

pub fn generated_action_help_data() string {
	return binding_action_help_data
}

// This module is a help generator for keybind actions documentation.
// It can generate documentation in different formats (plaintext for CLI,
// markdown for website) while maintaining consistent content.

// Format represents the output format for documentation.
pub enum Format as u8 {
	// Plain text output with indentation.
	plaintext
	// Markdown formatted output.
	markdown
}

// generate formats the keybinding action reference for the selected output.
pub fn generate(format Format, show_docs bool) string {
	return help_strings.format_keybind_actions(binding_action_help_data, format == .markdown, show_docs)
}
