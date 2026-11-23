module cli

import configpkg
import os

fn test_list_actions_lists_keybinding_actions() {
	output := list_actions_output([])!
	assert output.starts_with('ignore\nunbind\ncsi\n')
	assert output.contains('toggle_command_palette\n')
	assert output.ends_with('crash\n')
	assert !output.contains('list-fonts\n')
}

fn test_list_actions_docs_and_unknown_option() {
	output := list_actions_output(['--docs'])!
	assert output.starts_with('\nignore:\n  Ignore this key combination.\n')
	assert output.contains('new_window:\n  Open a new window.\n')

	list_actions_output(['--plain']) or {
		assert err.msg() == 'invalid field'
		return
	}
	assert false
}

fn test_action_boolean_options_accept_explicit_false() {
	assert !list_actions_output(['--docs=false'])!.contains('ignore:\n')
	colors := parse_action_options[ListColorsOptions](['--plain=false'])!
	assert !colors.plain
	keybinds := parse_action_options[ListKeybindsOptions](['--default=false', '--docs=false',
		'--plain=false'])!
	assert !keybinds.default_
	assert !keybinds.docs
	assert !keybinds.plain
	show_config := parse_show_config_options(['--default=false', '--changes-only=false',
		'--docs=false'])!
	assert !show_config.default_
	assert !show_config.changes_only
	assert !show_config.docs
}

fn test_list_colors_plain_contains_complete_sorted_x11_data() {
	output := list_colors_output(['--plain'])!
	lines := output.trim_space().split_into_lines()
	assert lines.len == 782
	assert lines[0] == 'alice blue = #f0f8ff'
	assert lines[1] == 'AliceBlue = #f0f8ff'
	assert output.contains('RebeccaPurple = #663399\n')
	assert output.contains('yellow green = #9acd32\n')
}

fn test_list_colors_rejects_unknown_options() {
	list_colors_output(['--wat']) or {
		assert err.msg() == 'invalid field'
		return
	}
	assert false
}

fn test_list_colors_pretty_uses_source_column_order_and_truecolor() {
	entries := sorted_color_entries()
	output := list_colors_pretty_output(entries, 120)
	assert output.starts_with(unicode_mode_set)
	assert output.ends_with(unicode_mode_reset)
	assert output.contains('alice blue')
	assert output.contains('\x1b[38;2;240;248;255m#f0f8ff\x1b[0m')
	assert output.contains('\x1b[38;2;240;248;255;48;2;240;248;255m  \x1b[0m')
	// The source fills columns top-to-bottom, so the second visible entry in
	// the first row is one `step` into the sorted input rather than index 1.
	mut max_name_len := 0
	for entry in entries {
		if entry.name.len > max_name_len {
			max_name_len = entry.name.len
		}
	}
	columns := (120 + 2) / (max_name_len + 15)
	step := entries.len / columns + 1
	first_row := output.all_after(unicode_mode_set).all_before('\n')
	first_index := first_row.index(entries[0].name) or { -1 }
	second_index := first_row.index(entries[step].name) or { -1 }
	assert second_index > first_index
}

fn test_list_keybinds_default_is_valid_config_syntax() {
	output := list_keybinds_output(['--default', '--plain'])!
	assert output.len > 0
	assert output.contains('keybind = ')
	assert output.contains('=new_window\n')
}

fn test_list_keybinds_pretty_flattens_sorts_and_styles_bindings() {
	mut keybinds := configpkg.Keybinds{}
	keybinds.parse_cli('ctrl+a>shift+b=new_window')!
	keybinds.parse_cli('ctrl+c=copy_to_clipboard')!
	keybinds.parse_cli('ctrl+d=text:hello')!
	keybinds.parse_cli('chain=copy_title_to_clipboard')!
	keybinds.parse_cli('tools/alt+x=paste_from_clipboard')!

	output := list_keybinds_pretty_output(keybinds)
	assert output.starts_with(unicode_mode_set)
	assert output.ends_with(unicode_mode_reset)
	assert output.contains('\x1b[38;5;2mctrl \x1b[0m + a')
	assert output.contains('\x1b[38;5;6;1m  >  \x1b[0m')
	assert output.contains('\x1b[38;5;4mshift\x1b[0m + b')
	assert output.contains('text\x1b[2m:\x1b[0m\x1b[38;5;5mhello\x1b[0m')
	assert output.contains('\x1b[2m, \x1b[0mcopy_title_to_clipboard')
	assert output.contains('\x1b[38;5;8mtools\x1b[0m\x1b[38;5;8m/\x1b[0m')
	chord_index := output.index('new_window') or { -1 }
	single_index := output.index('copy_to_clipboard') or { -1 }
	table_index := output.index('tools') or { -1 }
	assert chord_index < single_index
	assert single_index < table_index
}

fn test_format_font_list_sorts_unfiltered_and_preserves_filtered_priority() {
	entries := [
		FontListEntry{
			family: 'Zulu'
			name:   'Zulu Bold'
		},
		FontListEntry{
			family: 'Alpha'
			name:   'Alpha Italic'
		},
		FontListEntry{
			family: 'Alpha'
			name:   'Alpha Regular'
		},
	]
	assert format_font_list(entries, true) == 'Alpha\n  Alpha Italic\n  Alpha Regular\n\nZulu\n  Zulu Bold\n\n'
	assert format_font_list(entries, false) == 'Zulu\n  Zulu Bold\n\nAlpha\n  Alpha Italic\n  Alpha Regular\n\n'
}

fn test_list_fonts_options() {
	opts := parse_list_fonts_options(['--family=JetBrains Mono', '--style=Italic', '--bold',
		'--italic=false'])!
	assert opts.family? == 'JetBrains Mono'
	assert opts.style? == 'Italic'
	assert opts.bold
	assert !opts.italic

	if _ := parse_list_fonts_options(['--style', 'Italic']) {
		assert false, 'action values must use --long=value syntax'
	} else {
		assert err.msg() == 'value required'
	}
}

fn test_validate_config_specific_file() {
	dir := os.join_path(os.temp_dir(), 'witty-cli-validate-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	valid_path := os.join_path(dir, 'valid.conf')
	os.write_file(valid_path, 'font-size = 14\n')!
	valid := validate_config(['--config-file=${valid_path}'])!
	assert valid.code == 0
	assert valid.output == ''

	invalid_path := os.join_path(dir, 'invalid.conf')
	os.write_file(invalid_path, 'no-such-option = true\n')!
	invalid := validate_config(['--config-file=${invalid_path}'])!
	assert invalid.code == 1
	assert invalid.output.contains('no-such-option: unknown field')
}

fn test_validate_config_requires_equals_value_syntax() {
	if _ := validate_config(['--config-file', 'config']) {
		assert false, 'action values must use --long=value syntax'
	} else {
		assert err.msg() == 'value required'
	}
}

fn test_choose_editor_prefers_visual_and_ignores_empty_values() {
	assert choose_editor('nvim', 'vim') == 'nvim'
	assert choose_editor('', 'vim') == 'vim'
	assert choose_editor('', '') == ''
}

fn test_edit_config_target_creates_parent_directory() {
	dir := os.join_path(os.temp_dir(), 'witty-cli-edit-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'witty', 'config.witty')
	ensure_config_parent(path)!
	assert os.is_dir(os.dir(path))
}

// Ghostty's `font-size` default is 13 on macOS and 12 elsewhere.
const default_font_size_line = $if macos { 'font-size = 13.0\n' } $else { 'font-size = 12.0\n' }

fn test_show_config_changes_only_and_full_default() {
	full := show_config_output(['--default'])!
	assert full.contains(default_font_size_line)
	assert full.contains('background = #282c34\n')
	assert full.contains('palette = 255=#eeeeee\n')
	assert full.contains('keybind = ')

	opts := parse_show_config_options(['--changes-only=false', '--docs'])!
	assert !opts.changes_only
	assert opts.docs
}

fn test_show_config_changes_only_false_outputs_every_field() {
	output := show_config_output(['--changes-only=false'])!
	assert output.contains(default_font_size_line)
	assert output.contains('config-default-files = true\n')
}

fn test_show_config_rejects_config_and_unknown_options() {
	show_config_output(['--font-size=19']) or {
		assert err.msg() == 'invalid field'
		return
	}
	assert false
}

fn test_show_config_docs_comments_documented_fields() {
	output := show_config_output(['--default', '--docs'])!
	assert output.starts_with('# The font families to use.\n')
	assert output.contains('# Font size in points. This value can be a non-integer')
	assert output.contains('\n' + default_font_size_line + '\n')
}
