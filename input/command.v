module input

import ascii

// --- Original Ghostty Comments Start: src/input/command.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/input/command.zig
//
// A command is a named binding action that can be executed from
// something like a command palette.
//
// A command must be associated with a binding; all commands can be
// mapped to traditional `keybind` configurations. This restriction
// makes it so that there is nothing special about commands and likewise
// it makes it trivial and consistent to define custom commands.
//
// For apprt implementers: a command palette doesn't have to make use
// of all the fields here. We try to provide as much information as
// possible to make it easier to implement a command palette in the way
// that makes the most sense for the application.
// ghostty_command_s
// Convert this command to a C struct at comptime.
// Convert this command to a C struct at runtime.
//
// This shares memory with the original command.
//
// The action string is allocated using the provided allocator. You can
// free the slice directly if you need to but we recommend an arena
// for this.
// Implements a comparison function for std.mem.sortUnstable
// and similar functions. The sorting is defined by Ghostty
// to be what we prefer. If a caller wants some other sorting,
// they should do it themselves.
// Defaults in C-compatible form.
// Returns the set of commands associated with this action key by
// default. Not all actions should have commands. As a general guideline,
// an action should have a command only if it is useful and reasonable
// to appear in a command palette.
// This is implemented as a function and switch rather than a
// flat comptime const because we want to ensure we get a compiler
// error when a new binding is added so that the contributor has
// to consider whether that new binding should have commands or not.
// Note: the use of `comptime` prefix on the return values
// ensures that the data returned is all in the binary and
// and not pointing to the stack.
// No commands because they're parameterized and there
// aren't obvious values users would use. It is possible that
// these may have commands in the future if there are very
// common values that users tend to use.
// No commands because I'm not sure they make sense in a command
// palette context.
// No commands for obvious reasons
// All generated commands should have the same action as the
// action passed in.
// This just ensures that defaults is analyzed and works.
//
// --- Original Ghostty Comments End: src/input/command.zig

// Command is a named binding action that can be executed from
// something like a command palette.
//
// A command must be associated with a binding; all commands can be
// mapped to traditional keybind configurations. This restriction
// makes it so that there is nothing special about commands and likewise
// it makes it trivial and consistent to define custom commands.
pub struct Command {
pub:
	// The action to perform when this command is triggered.
	action Action
	// The human-readable title of the command.
	title string
	// A longer description of what the command does.
	description string
}

// CCommand is ghostty_command_s.
pub struct CCommand {
pub:
	action_key  &char = unsafe { nil }
	action      &char = unsafe { nil }
	title       &char = unsafe { nil }
	description &char = unsafe { nil }
}

// clone creates a deep copy of a Command.
pub fn (c Command) clone() Command {
	return Command{
		action: c.action.clone()
		title: c.title.clone()
		description: c.description.clone()
	}
}

// equal returns true if two commands are equal.
pub fn (a Command) equal(b Command) bool {
	if a.action.hash() != b.action.hash() {
		return false
	}
	if a.title != b.title {
		return false
	}
	return a.description == b.description
}

// comptime_cval is Command.comptimeCval. V uses the same representation for
// values constructed while initializing module constants and at runtime.
pub fn (c Command) comptime_cval() CCommand {
	return c.cval()
}

// cval converts this command to its C representation. The title and
// description remain borrowed from the command, matching the source API.
pub fn (c Command) cval() CCommand {
	action_key := c.action.tag().str()
	action := c.action.format()
	return CCommand{
		action_key: &char(action_key.str)
		action: &char(action.str)
		title: &char(c.title.str)
		description: &char(c.description.str)
	}
}

// less_than implements comparison for sorting commands alphabetically by title.
pub fn (a Command) less_than(b Command) bool {
	return ascii.order_ignore_case(a.title, b.title) < 0
}

// command_defaults is the set of default commands, built by iterating over
// every action and collecting the commands it contributes, then sorting them
// alphabetically by title (case-insensitive). This mirrors the Zig `defaults`
// comptime constant which does the same via `actionCommands` per Action.Key.
pub const command_defaults = build_command_defaults()

// command_defaults_c is the C-compatible form of command_defaults.
pub const command_defaults_c = build_command_defaults_c()

fn build_command_defaults_c() []CCommand {
	return command_defaults.map(it.comptime_cval())
}

// build_command_defaults assembles and sorts the default command list.
// Faithful to Zig `defaults`.
fn build_command_defaults() []Command {
	mut result := []Command{}
	// Iterate every action tag and append its default commands. Faithful to
	// the Zig loop over `@typeInfo(Action.Key).@"enum".fields`.
	for tag in action_tags() {
		result << action_commands(tag)
	}

	// Sort alphabetically by title, case-insensitive (Command.less_than).
	result.sort_with_compare(fn (a &Command, b &Command) int {
		return ascii.order_ignore_case(a.title, b.title)
	})

	return result
}

// action_tags translates the source's type-info iteration so newly added enum
// values are included automatically.
fn action_tags() []ActionTag {
	mut result := []ActionTag{}
	$for enum_value in ActionTag.values {
		result << enum_value.value
	}
	return result
}

// cmd is a small helper to build a Command from an action, title and
// description, matching the Zig `.{ .action = ..., .title = ..., .description = ... }`.
fn cmd(action Action, title string, description string) Command {
	return Command{
		action: action
		title: title
		description: description
	}
}

// action_commands returns the set of commands associated with this action tag
// by default. Not all actions have commands. Faithful to Zig `actionCommands`.
fn action_commands(action ActionTag) []Command {
	result := match action {
		.reset {
			[
				cmd(ActionReset{}, 'Reset Terminal', 'Reset the terminal to a clean state.'),
			]
		}
		.copy_to_clipboard {
			[
				cmd(ActionCopyToClipboard{ value: .mixed }, 'Copy to Clipboard', 'Copy the selected text to the clipboard in both plain and styled formats.'),
				cmd(ActionCopyToClipboard{ value: .plain }, 'Copy Selection as Plain Text to Clipboard', 'Copy the selected text as plain text to the clipboard.'),
				cmd(ActionCopyToClipboard{ value: .vt }, 'Copy Selection as ANSI Sequences to Clipboard', 'Copy the selected text as ANSI escape sequences to the clipboard.'),
				cmd(ActionCopyToClipboard{ value: .html }, 'Copy Selection as HTML to Clipboard', 'Copy the selected text as HTML to the clipboard.'),
			]
		}
		.copy_url_to_clipboard {
			[cmd(ActionCopyUrlToClipboard{}, 'Copy URL to Clipboard', 'Copy the URL under the cursor to the clipboard.')]
		}
		.copy_title_to_clipboard {
			[cmd(ActionCopyTitleToClipboard{}, 'Copy Terminal Title to Clipboard', 'Copy the terminal title to the clipboard. If the terminal title is not set this has no effect.')]
		}
		.paste_from_clipboard {
			[cmd(ActionPasteFromClipboard{}, 'Paste from Clipboard', 'Paste the contents of the main clipboard.')]
		}
		.paste_from_selection {
			[cmd(ActionPasteFromSelection{}, 'Paste from Selection', 'Paste the contents of the selection clipboard.')]
		}
		.start_search {
			[
				cmd(ActionStartSearch{}, 'Start Search', "Start a search if one isn't already active."),
			]
		}
		.search_selection {
			[cmd(ActionSearchSelection{}, 'Search Selection', 'Start a search for the current text selection.')]
		}
		.end_search {
			[cmd(ActionEndSearch{}, 'End Search', 'End the current search if any and hide any GUI elements.')]
		}
		.navigate_search {
			[
				cmd(ActionNavigateSearch{ value: .next }, 'Next Search Result', 'Navigate to the next search result, if any.'),
				cmd(ActionNavigateSearch{ value: .previous }, 'Previous Search Result', 'Navigate to the previous search result, if any.'),
			]
		}
		.increase_font_size {
			[cmd(ActionIncreaseFontSize{ value: 1 }, 'Increase Font Size', 'Increase the font size by 1 point.')]
		}
		.decrease_font_size {
			[cmd(ActionDecreaseFontSize{ value: 1 }, 'Decrease Font Size', 'Decrease the font size by 1 point.')]
		}
		.reset_font_size {
			[
				cmd(ActionResetFontSize{}, 'Reset Font Size', 'Reset the font size to the default.'),
			]
		}
		.clear_screen {
			[
				cmd(ActionClearScreen{}, 'Clear Screen', 'Clear the screen and scrollback.'),
			]
		}
		.select_all {
			[
				cmd(ActionSelectAll{}, 'Select All', 'Select all text on the screen.'),
			]
		}
		.scroll_to_top {
			[
				cmd(ActionScrollToTop{}, 'Scroll to Top', 'Scroll to the top of the screen.'),
			]
		}
		.scroll_to_bottom {
			[
				cmd(ActionScrollToBottom{}, 'Scroll to Bottom', 'Scroll to the bottom of the screen.'),
			]
		}
		.scroll_to_selection {
			[
				cmd(ActionScrollToSelection{}, 'Scroll to Selection', 'Scroll to the selected text.'),
			]
		}
		.scroll_page_up {
			[
				cmd(ActionScrollPageUp{}, 'Scroll Page Up', 'Scroll the screen up by a page.'),
			]
		}
		.scroll_page_down {
			[
				cmd(ActionScrollPageDown{}, 'Scroll Page Down', 'Scroll the screen down by a page.'),
			]
		}
		.write_screen_file {
			write_file_commands(.write_screen_file, 'Screen', 'screen')
		}
		.write_selection_file {
			write_file_commands(.write_selection_file, 'Selection', 'selection')
		}
		.new_window {
			[cmd(ActionNewWindow{}, 'New Window', 'Open a new window.')]
		}
		.new_tab {
			[cmd(ActionNewTab{}, 'New Tab', 'Open a new tab.')]
		}
		.move_tab {
			[
				cmd(ActionMoveTab{ value: -1 }, 'Move Tab Left', 'Move the current tab to the left.'),
				cmd(ActionMoveTab{ value: 1 }, 'Move Tab Right', 'Move the current tab to the right.'),
			]
		}
		.toggle_tab_overview {
			[
				cmd(ActionToggleTabOverview{}, 'Toggle Tab Overview', 'Toggle the tab overview.'),
			]
		}
		.prompt_surface_title {
			[cmd(ActionPromptSurfaceTitle{}, 'Change Terminal Title...', 'Prompt for a new title for the current terminal.')]
		}
		.prompt_tab_title {
			[cmd(ActionPromptTabTitle{}, 'Change Tab Title...', 'Prompt for a new title for the current tab.')]
		}
		.new_split {
			[
				cmd(ActionNewSplit{ value: .left }, 'Split Left', 'Split the terminal to the left.'),
				cmd(ActionNewSplit{ value: .right }, 'Split Right', 'Split the terminal to the right.'),
				cmd(ActionNewSplit{ value: .up }, 'Split Up', 'Split the terminal up.'),
				cmd(ActionNewSplit{ value: .down }, 'Split Down', 'Split the terminal down.'),
			]
		}
		.goto_split {
			[
				cmd(ActionGotoSplit{ value: .previous }, 'Focus Split: Previous', 'Focus the previous split, if any.'),
				cmd(ActionGotoSplit{ value: .next }, 'Focus Split: Next', 'Focus the next split, if any.'),
				cmd(ActionGotoSplit{ value: .left }, 'Focus Split: Left', 'Focus the split to the left, if it exists.'),
				cmd(ActionGotoSplit{ value: .right }, 'Focus Split: Right', 'Focus the split to the right, if it exists.'),
				cmd(ActionGotoSplit{ value: .up }, 'Focus Split: Up', 'Focus the split above, if it exists.'),
				cmd(ActionGotoSplit{ value: .down }, 'Focus Split: Down', 'Focus the split below, if it exists.'),
			]
		}
		.goto_window {
			[
				cmd(ActionGotoWindow{ value: .previous }, 'Focus Window: Previous', 'Focus the previous window, if any.'),
				cmd(ActionGotoWindow{ value: .next }, 'Focus Window: Next', 'Focus the next window, if any.'),
			]
		}
		.toggle_split_zoom {
			[cmd(ActionToggleSplitZoom{}, 'Toggle Split Zoom', 'Toggle the zoom state of the current split.')]
		}
		.toggle_readonly {
			[cmd(ActionToggleReadonly{}, 'Toggle Read-Only Mode', 'Toggle read-only mode for the current surface.')]
		}
		.equalize_splits {
			[
				cmd(ActionEqualizeSplits{}, 'Equalize Splits', 'Equalize the size of all splits.'),
			]
		}
		.reset_window_size {
			[
				cmd(ActionResetWindowSize{}, 'Reset Window Size', 'Reset the window size to the default.'),
			]
		}
		.inspector {
			[cmd(ActionInspector{ value: .toggle }, 'Toggle Inspector', 'Toggle the inspector.')]
		}
		.show_gtk_inspector {
			[
				cmd(ActionShowGtkInspector{}, 'Show the GTK Inspector', 'Show the GTK inspector.'),
			]
		}
		.show_on_screen_keyboard {
			[cmd(ActionShowOnScreenKeyboard{}, 'Show On-Screen Keyboard', 'Show the on-screen keyboard if present.')]
		}
		.open_config {
			[cmd(ActionOpenConfig{}, 'Open Config', 'Open the config file.')]
		}
		.reload_config {
			[
				cmd(ActionReloadConfig{}, 'Reload Config', 'Reload the config file.'),
			]
		}
		.close_surface {
			[
				cmd(ActionCloseSurface{}, 'Close Terminal', 'Close the current terminal.'),
			]
		}
		.close_tab {
			[
				cmd(ActionCloseTab{ value: .this }, 'Close Tab', 'Close the current tab.'),
				cmd(ActionCloseTab{ value: .other }, 'Close Other Tabs', 'Close all tabs in this window except the current one.'),
				cmd(ActionCloseTab{ value: .right }, 'Close Tabs to the Right', 'Close all tabs to the right of the current one.'),
			]
		}
		.close_window {
			[
				cmd(ActionCloseWindow{}, 'Close Window', 'Close the current window.'),
			]
		}
		.close_all_windows {
			[
				cmd(ActionCloseAllWindows{}, 'Close All Windows', 'Close all windows.'),
			]
		}
		.toggle_maximize {
			[cmd(ActionToggleMaximize{}, 'Toggle Maximize', 'Toggle the maximized state of the current window.')]
		}
		.toggle_fullscreen {
			[cmd(ActionToggleFullscreen{}, 'Toggle Fullscreen', 'Toggle the fullscreen state of the current window.')]
		}
		.toggle_window_decorations {
			[cmd(ActionToggleWindowDecorations{}, 'Toggle Window Decorations', 'Toggle the window decorations.')]
		}
		.toggle_window_float_on_top {
			[cmd(ActionToggleWindowFloatOnTop{}, 'Toggle Float on Top', 'Toggle the float on top state of the current window.')]
		}
		.toggle_secure_input {
			[
				cmd(ActionToggleSecureInput{}, 'Toggle Secure Input', 'Toggle secure input mode.'),
			]
		}
		.toggle_mouse_reporting {
			[cmd(ActionToggleMouseReporting{}, 'Toggle Mouse Reporting', 'Toggle whether mouse events are reported to terminal applications.')]
		}
		.toggle_background_opacity {
			[cmd(ActionToggleBackgroundOpacity{}, 'Toggle Background Opacity', 'Toggle the background opacity of a window that started transparent.')]
		}
		.check_for_updates {
			[cmd(ActionCheckForUpdates{}, 'Check for Updates', 'Check for updates to the application.')]
		}
		.undo {
			[cmd(ActionUndo{}, 'Undo', 'Undo the last action.')]
		}
		.redo {
			[cmd(ActionRedo{}, 'Redo', 'Redo the last undone action.')]
		}
		.quit {
			[cmd(ActionQuit{}, 'Quit', 'Quit the application.')]
		}
		.text {
			[
				cmd(ActionText{ value: '👻' }, 'Witty', 'Put a little Witty in your terminal.'),
			]
		}

		// No commands because they're parameterized and there aren't obvious
		// values users would use.
		.csi, .esc, .cursor_key, .set_font_size, .search, .scroll_to_row,
		.scroll_page_fractional, .scroll_page_lines, .adjust_selection, .jump_to_prompt,
		.write_scrollback_file, .goto_tab, .resize_split, .activate_key_table,
		.activate_key_table_once, .deactivate_key_table, .deactivate_all_key_tables,
		.end_key_sequence, .crash {
			[]Command{}
		}
		// No commands because they don't make sense in a command palette context.
		.toggle_command_palette, .toggle_quick_terminal, .toggle_visibility, .previous_tab,
		.next_tab, .last_tab {
			[]Command{}
		}
		// No commands for obvious reasons.
		.ignore, .unbind {
			[]Command{}
		}
	}
	// All generated commands should have the same action tag as the action
	// passed in.
	for generated in result {
		assert generated.action.tag() == action
	}
	return result
}

// write_file_action builds the write-file variant named by tag.
fn write_file_action(tag ActionTag, value WriteScreen) Action {
	return match tag {
		.write_screen_file { ActionWriteScreenFile{ value: value } }
		.write_selection_file { ActionWriteSelectionFile{ value: value } }
		else { panic('write_file_action: ${tag} is not a write-file action') }
	}
}

// write_file_commands builds the 9-entry command set for write_screen_file /
// write_selection_file. `noun` is the capitalized noun used in titles
// ("Screen"/"Selection") and `lower` is the lowercase noun used in
// descriptions. Faithful to the two nearly-identical Zig arms.
fn write_file_commands(tag ActionTag, noun string, lower string) []Command {
	// The plain-format entries (no ",format" suffix in Zig; emit .plain).
	return [
		cmd(write_file_action(tag, WriteScreen{ action: .copy, emit: .plain }), 'Copy ${noun} to Temporary File and Copy Path', 'Copy the ${lower} contents to a temporary file and copy the path to the clipboard.'),
		cmd(write_file_action(tag, WriteScreen{ action: .paste, emit: .plain }), 'Copy ${noun} to Temporary File and Paste Path', 'Copy the ${lower} contents to a temporary file and paste the path to the file.'),
		cmd(write_file_action(tag, WriteScreen{ action: .open, emit: .plain }), 'Copy ${noun} to Temporary File and Open', 'Copy the ${lower} contents to a temporary file and open it.'),
		cmd(write_file_action(tag, WriteScreen{ action: .copy, emit: .html }), 'Copy ${noun} as HTML to Temporary File and Copy Path', 'Copy the ${lower} contents as HTML to a temporary file and copy the path to the clipboard.'),
		cmd(write_file_action(tag, WriteScreen{ action: .paste, emit: .html }), 'Copy ${noun} as HTML to Temporary File and Paste Path', 'Copy the ${lower} contents as HTML to a temporary file and paste the path to the file.'),
		cmd(write_file_action(tag, WriteScreen{ action: .open, emit: .html }), 'Copy ${noun} as HTML to Temporary File and Open', 'Copy the ${lower} contents as HTML to a temporary file and open it.'),
		cmd(write_file_action(tag, WriteScreen{ action: .copy, emit: .vt }), 'Copy ${noun} as ANSI Sequences to Temporary File and Copy Path', 'Copy the ${lower} contents as ANSI escape sequences to a temporary file and copy the path to the clipboard.'),
		cmd(write_file_action(tag, WriteScreen{ action: .paste, emit: .vt }), 'Copy ${noun} as ANSI Sequences to Temporary File and Paste Path', 'Copy the ${lower} contents as ANSI escape sequences to a temporary file and paste the path to the file.'),
		cmd(write_file_action(tag, WriteScreen{ action: .open, emit: .vt }), 'Copy ${noun} as ANSI Sequences to Temporary File and Open', 'Copy the ${lower} contents as ANSI escape sequences to a temporary file and open it.'),
	]
}
