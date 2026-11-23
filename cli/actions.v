module cli

import ascii
import configpkg
import font
import input
import log
import os
import terminal
import tui
import vaxis

pub struct ListActionsOptions {
pub mut:
	docs bool
}

pub fn (opts ListActionsOptions) deinit() {
	_ = opts
}

pub fn (opts ListActionsOptions) help() ! {
	_ = opts
	action_options_help()!
}

// list_actions_output lists every keybinding action, not the CLI actions.
// This is the translated `cli/list_actions.zig` output path; `--docs` asks
// the shared input help generator to include each action's documentation.
pub fn list_actions_output(args []string) !string {
	opts := parse_action_options[ListActionsOptions](args)!
	return input.generate(.plaintext, opts.docs)
}

pub fn run_list_actions(args []string) !int {
	print(list_actions_output(args)!)
	return 0
}

pub struct ListColorsOptions {
pub mut:
	plain bool
}

pub fn (opts ListColorsOptions) deinit() {
	_ = opts
}

pub fn (opts ListColorsOptions) help() ! {
	_ = opts
	action_options_help()!
}

// list_colors_output is the deterministic plain form used for pipes and
// tests. run_list_colors selects the translated TTY renderer when appropriate.
pub fn list_colors_output(args []string) !string {
	_ := parse_action_options[ListColorsOptions](args)!
	return list_colors_plain(sorted_color_entries())
}

fn sorted_color_entries() []terminal.NamedRGB {
	mut entries := terminal.x11_color_entries()
	entries.sort_with_compare(fn (a &terminal.NamedRGB, b &terminal.NamedRGB) int {
		return ascii.order_ignore_case(a.name, b.name)
	})
	return entries
}

fn list_colors_plain(entries []terminal.NamedRGB) string {
	mut lines := []string{cap: entries.len}
	for entry in entries {
		lines << '${entry.name} = #${entry.rgb.r:02x}${entry.rgb.g:02x}${entry.rgb.b:02x}'
	}
	return output_lines(lines)
}

pub fn run_list_colors(args []string) !int {
	opts := parse_action_options[ListColorsOptions](args)!
	entries := sorted_color_entries()
	if tui.can_pretty_print && !opts.plain && os.is_atty(1) > 0 {
		print(list_colors_pretty_output(entries, int(vaxis.terminal_size().cols)))
	} else {
		print(list_colors_plain(entries))
	}
	return 0
}

// list_keybinds_output serializes either the default or loaded binding set in
// valid Ghostty configuration syntax. The source's docs lookup currently adds
// only its documented separator lines; run_list_keybinds also selects the TTY
// renderer when appropriate.
pub struct ListKeybindsOptions {
pub mut:
	default_ bool
	docs     bool
	plain    bool
}

pub fn (opts ListKeybindsOptions) deinit() {
	_ = opts
}

pub fn (opts ListKeybindsOptions) help() ! {
	_ = opts
	action_options_help()!
}

pub fn list_keybinds_output(args []string) !string {
	opts := parse_action_options[ListKeybindsOptions](args)!
	_ = opts.docs
	config := load_keybind_config(opts)!
	return output_lines(config.keybind.format_entry_docs(opts.docs))
}

fn load_keybind_config(opts ListKeybindsOptions) !configpkg.Config {
	return if opts.default_ {
		configpkg.Config.default_config()
	} else {
		configpkg.Config.load_args([])!
	}
}

pub fn run_list_keybinds(args []string) !int {
	opts := parse_action_options[ListKeybindsOptions](args)!
	config := load_keybind_config(opts)!
	if tui.can_pretty_print && !opts.plain && os.is_atty(1) > 0 {
		print(list_keybinds_pretty_output(config.keybind))
	} else {
		print(output_lines(config.keybind.format_entry_docs(opts.docs)))
	}
	return 0
}

pub struct FontListOptions {
pub mut:
	family ?string
	style  ?string
	bold   bool
	italic bool
}

pub fn (opts FontListOptions) deinit() {
	_ = opts
}

pub fn (opts FontListOptions) help() ! {
	_ = opts
	action_options_help()!
}

pub struct FontListEntry {
pub:
	family string
	name   string
}

// list_fonts_output uses the same native discovery abstraction as the font
// grid. With no family filter Ghostty sorts by family and full face name; a
// family query deliberately preserves discovery priority.
pub fn list_fonts_output(args []string) !string {
	opts := parse_list_fonts_options(args)!
	mut discovery := font.Discover.init()
	defer {
		discovery.deinit()
	}
	mut iterator := discovery.discover(font.Descriptor{
		family:    opts.family
		style:     opts.style
		bold:      opts.bold
		italic:    opts.italic
		monospace: opts.family == none
	})!
	defer {
		iterator.deinit()
	}
	mut entries := []FontListEntry{}
	for {
		value := iterator.next()!
		if !value.has_value {
			break
		}
		face := value.face
		mut buf := []u8{len: 1024}
		family := face.family_name(mut buf) or {
			log.error('failed to get font family name: ${err}')
			continue
		}
		name := face.name(mut buf) or {
			log.error('failed to get font name: ${err}')
			continue
		}
		if family.len > 0 && name.len > 0 {
			entries << FontListEntry{
				family: family
				name:   name
			}
		}
	}
	return format_font_list(entries, opts.family == none)
}

pub fn run_list_fonts(args []string) !int {
	print(list_fonts_output(args)!)
	return 0
}

fn parse_list_fonts_options(args []string) !FontListOptions {
	return parse_action_options[FontListOptions](args)
}

pub fn format_font_list(entries []FontListEntry, sort_results bool) string {
	mut families := []string{}
	mut grouped := map[string][]string{}
	for entry in entries {
		if entry.family !in grouped {
			families << entry.family
			grouped[entry.family] = []string{}
		}
		mut names := grouped[entry.family]
		names << entry.name
		grouped[entry.family] = names
	}
	if sort_results {
		families.sort()
	}
	mut lines := []string{}
	for family in families {
		mut names := grouped[family]
		if sort_results {
			names.sort()
		}
		if names.len == 0 {
			continue
		}
		lines << family
		for name in names {
			lines << '  ${name}'
		}
		lines << ''
	}
	return output_lines(lines)
}

pub struct ValidateResult {
pub:
	code   int
	output string
}

pub struct ValidateConfigOptions {
pub mut:
	config_file ?string
}

pub fn (opts ValidateConfigOptions) deinit() {
	_ = opts
}

pub fn (opts ValidateConfigOptions) help() ! {
	_ = opts
	action_options_help()!
}

// validate_config evaluates a specified file, or the normal default config
// stack, and renders every diagnostic one per line.
pub fn validate_config(args []string) !ValidateResult {
	opts := parse_action_options[ValidateConfigOptions](args)!

	mut config := if config_path := opts.config_file {
		mut value := configpkg.Config.default_config()
		abs_path := os.real_path(config_path)
		value.load_file(abs_path)!
		value.load_recursive_files()!
		value.finalize()!
		value
	} else {
		configpkg.Config.load_args([])!
	}
	mut lines := []string{cap: config.diagnostics.len}
	for diagnostic in config.diagnostics {
		lines << diagnostic.format()
	}
	return ValidateResult{
		code:   if lines.len > 0 { 1 } else { 0 }
		output: output_lines(lines)
	}
}

pub fn run_validate_config(args []string) !int {
	result := validate_config(args)!
	print(result.output)
	return result.code
}

// edit_config_target performs the non-exec portion of `+edit-config`: load the
// config once, resolve Ghostty's preferred user file, and make sure its parent
// directory exists so an editor can create a first configuration.
pub struct EditConfigOptions {}

pub fn (opts EditConfigOptions) deinit() {
	_ = opts
}

pub fn (opts EditConfigOptions) help() ! {
	_ = opts
	action_options_help()!
}

pub fn edit_config_target(args []string) !string {
	_ := parse_action_options[EditConfigOptions](args)!
	_ := configpkg.Config.load_args([])!
	path := configpkg.preferred_default_file_path()!
	ensure_config_parent(path)!
	return path
}

fn ensure_config_parent(path string) ! {
	os.mkdir_all(os.dir(path))!
}

pub fn choose_editor(visual string, editor string) string {
	if visual.len > 0 {
		return visual
	}
	return editor
}

pub fn run_edit_config(args []string) !int {
	path := edit_config_target(args)!
	$if windows {
		eprintln('The `witty +edit-config` command is not supported on Windows.')
		eprintln('Please edit the configuration file manually at the following path:\n')
		eprintln(path)
		return 1
	} $else {
		editor := choose_editor(os.getenv('VISUAL'), os.getenv('EDITOR'))
		if editor.len == 0 {
			eprintln('The \$EDITOR or \$VISUAL environment variable is not set or is empty.')
			eprintln('This environment variable is required to edit the Witty configuration')
			eprintln('via this CLI command.\n')
			eprintln('Please set the environment variable to your preferred terminal')
			eprintln('text editor and try again.\n')
			eprintln('If you prefer to edit the configuration file another way,')
			eprintln('you can find the configuration file at the following path:\n')
			eprintln('\x1b]8;;file://${path}\x1b\\${path}\x1b]8;;\x1b\\')
			return 1
		}
		os.execvp(editor, [path]) or {
			eprintln('Failed to execute the editor. ${err.msg()}')
			eprintln('Editor: ${editor}')
			eprintln('Path: ${path}')
			return 1
		}
		return 0
	}
}

pub struct ShowConfigOptions {
pub mut:
	default_     bool
	changes_only bool = true
	docs         bool
}

pub fn (opts ShowConfigOptions) deinit() {
	_ = opts
}

pub fn (opts ShowConfigOptions) help() ! {
	_ = opts
	action_options_help()!
}

pub fn show_config_output(args []string) !string {
	opts := parse_show_config_options(args)!
	config := if opts.default_ {
		configpkg.Config.default_config()
	} else {
		configpkg.Config.load_args([])!
	}
	return config.format_config_with_docs(!opts.default_ && opts.changes_only, opts.docs)
}

pub fn run_show_config(args []string) !int {
	print(show_config_output(args)!)
	return 0
}

fn parse_show_config_options(args []string) !ShowConfigOptions {
	return parse_action_options[ShowConfigOptions](args)
}

fn output_lines(lines []string) string {
	if lines.len == 0 {
		return ''
	}
	return lines.join('\n') + '\n'
}
