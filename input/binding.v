module input

import strings
import zig_fmt

// --- Original Ghostty Comments Start: src/input/Binding.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/input/Binding.zig
//
// A binding maps some input trigger to an action. When the trigger
// occurs, the action is performed.
// The trigger that needs to be performed to execute the action.
// The action to take if this binding matches
// Boolean flags that can be set per binding.
// Flags the full binding-scoped flags that can be set per binding.
// True if this binding should consume the input when the
// action is triggered.
// True if this binding should be forwarded to all active surfaces
// in the application.
// True if this binding is global. Global bindings should work system-wide
// and not just while Ghostty is focused. This may not work on all platforms.
// See the keybind config documentation for more information.
// True if this binding should only be triggered if the action can be
// performed. If the action can't be performed then the binding acts as
// if it doesn't exist.
// C type
// Converts this to a C-compatible value.
//
// Sync with witty.h for enums.
// Full binding parser. The binding parser is implemented as an iterator
// which yields elements to support multi-key sequences without allocation.
// A leader trigger in a sequence.
// The final trigger and action in a sequence.
// A chained action `chain=<action>` that should be appended
// to the previous binding. Note that any action is parsed, including
// invalid actions for chains such as `unbind`. We expect downstream
// consumers to validate that the action is valid for chaining.
// Find the equal sign. This is more complicated than it seems on
// the surface because we need to ignore equal signs that are
// part of the trigger.
// TODO: We should change this parser into a real state machine
// based parser that parses the trigger fully, then yields the
// action after. The loop below is a total mess.
// Find: '=+ctrl' or '==action'
// Looks like the real equal sign.
// Detect chains. Chains must not have flags.
// Sequence iterator goes up to the equal, action is after. We can
// parse the action now.
// This is kind of hacky but we put a dummy trigger
// for chained inputs. The `next` will never yield this
// because we have chain set. When we find a nicer way to
// do this we can remove it, the e2e is tested.
// Find the next prefix
// If the prefix is one of our flags then set it.
// If we don't recognize the prefix then we're done. We
// let any unknown prefix fallthrough to trigger-specific
// parsing in case there are trigger-specific prefixes
// (none currently but historically there was `physical:`
// at one point). Breaking here lets us always implement new
// prefixes.
// Move past the prefix
// Get our trigger. If we're out of triggers then we're done.
// If this is our last trigger then it is our final binding.
// Global/all bindings can't be sequences
// If we're a chain then return it as-is.
// Out of triggers, yield the final action.
// An iterator that yields each trigger in a sequence of triggers. For
// example, the sequence "ctrl+a>ctrl+b" would yield "ctrl+a" and then
// "ctrl+b". The iterator approach allows us to parse a sequence of
// triggers without allocations.
// The input of triggers. This is expected to be ONLY triggers. Things
// like the "unconsumed:" prefix or action must be stripped before
// passing to this iterator.
// Returns the next trigger in the sequence if there is no parsing error.
// Returns true if there are no more triggers to parse.
// Parse a single, non-sequenced binding. To support sequences you must
// use parse. This is a convenience function for single bindings aimed
// primarily at tests.
//
// This doesn't support `chain` either, since chaining requires some
// stateful concept of a prior binding.
// Returns true if lhs should be sorted before rhs
// The set of actions that a keybinding can take.
// Ignore this key combination.
//
// Ghostty will not process this combination nor forward it to the child
// process within the terminal, but it may still be processed by the OS or
// other applications.
// Unbind a previously bound key binding.
//
// This cannot unbind bindings that were not bound by Ghostty or the user
// (e.g. bindings set by the OS or some other application).
// Send a CSI sequence.
//
// The value should be the CSI sequence without the CSI header (`ESC [` or
// `\x1b[`).
//
// For example, `csi:0m` can be sent to reset all styles of the current text.
// Send an `ESC` sequence.
// Send the specified text.
//
// Uses Zig string literal syntax. This is currently not validated.
// If the text is invalid (i.e. contains an invalid escape sequence),
// the error will currently only show up in logs.
// Send data to the pty depending on whether cursor key mode is enabled
// (`application`) or disabled (`normal`).
// Reset the terminal.
//
// This can fix a lot of issues when a running program puts the terminal
// into a broken state, equivalent to running the `reset` command.
//
// If you do this while in a TUI program such as vim, this may break
// the program. If you do this while in a shell, you may have to press
// enter after to get a new prompt.
// Copy the selected text to the clipboard.
// Paste the contents of the default clipboard.
// Paste the contents of the selection clipboard.
// If there is a URL under the cursor, copy it to the default clipboard.
// Copy the terminal title to the clipboard. If the terminal title is not
// set or is empty this has no effect.
// Increase the font size by the specified amount in points (pt).
//
// For example, `increase_font_size:1.5` will increase the font size
// by 1.5 points.
// Decrease the font size by the specified amount in points (pt).
//
// For example, `decrease_font_size:1.5` will decrease the font size
// by 1.5 points.
// Reset the font size to the original configured size.
// Set the font size to the specified size in points (pt).
//
// For example, `set_font_size:14.5` will set the font size
// to 14.5 points.
// Start a search for the given text. If the text is empty, then
// the search is canceled. A canceled search will not disable any GUI
// elements showing search. For that, the explicit end_search binding
// should be used.
//
// If a previous search is active, it is replaced.
// Start a search for the current text selection. If there is no
// selection, this does nothing. If a search is already active, this
// changes the search terms.
// Navigate the search results. If there is no active search, this
// is not performed.
// Start a search if it isn't started already. This doesn't set any
// search terms, but opens the UI for searching.
// End the current search if any and hide any GUI elements.
// Clear the screen and all scrollback.
// Select all text on the screen.
// Scroll to the top of the screen.
// Scroll to the bottom of the screen.
// Scroll to the selected text.
// Scroll to the given absolute row in the screen with 0 being
// the first row.
// Scroll the screen up by one page.
// Scroll the screen down by one page.
// Scroll the screen by the specified fraction of a page.
//
// Positive values scroll downwards, and negative values scroll upwards.
//
// For example, `scroll_page_fractional:0.5` would scroll the screen
// downwards by half a page, while `scroll_page_fractional:-1.5` would
// scroll it upwards by one and a half pages.
// Scroll the screen by the specified amount of lines.
//
// Positive values scroll downwards, and negative values scroll upwards.
//
// For example, `scroll_page_lines:3` would scroll the screen downwards
// by 3 lines, while `scroll_page_lines:-10` would scroll it upwards by 10
// lines.
// Adjust the current selection in the given direction or position,
// relative to the cursor.
//
// WARNING: This does not create a new selection, and does nothing when
// there currently isn't one.
//
// Valid arguments are:
//
//   - `left`, `right`
//
//     Adjust the selection one cell to the left or right respectively.
//
//   - `up`, `down`
//
//     Adjust the selection one line upwards or downwards respectively.
//
//   - `page_up`, `page_down`
//
//     Adjust the selection one page upwards or downwards respectively.
//
//   - `home`, `end`
//
//     Adjust the selection to the top-left or the bottom-right corner
//     of the screen respectively.
//
//   - `beginning_of_line`, `end_of_line`
//
//     Adjust the selection to the beginning or the end of the line
//     respectively.
//
// Jump the viewport forward or back by the given number of prompts.
//
// Requires shell integration.
//
// Positive values scroll downwards, and negative values scroll upwards.
// Write the entire scrollback into a temporary file with the specified
// action. The action determines what to do with the filepath.
//
// Valid actions are:
//
//   - `copy`
//
//     Copy the file path into the clipboard.
//
//   - `paste`
//
//     Paste the file path into the terminal.
//
//   - `open`
//
//     Open the file in the default OS editor for text files.
//
//     The default OS editor is determined by using `open` on macOS
//     and `xdg-open` on Linux.
//
// Write the contents of the screen into a temporary file with the
// specified action.
//
// See `write_scrollback_file` for possible actions.
// Write the currently selected text into a temporary file with the
// specified action.
//
// See `write_scrollback_file` for possible actions.
//
// Does nothing when no text is selected.
// Open a new window.
//
// If the application isn't currently focused,
// this will bring it to the front.
// Open a new tab.
// Go to the previous tab.
// Go to the next tab.
// Go to the last tab.
// Go to the tab with the specific index, starting from 1.
//
// If the tab number is higher than the number of tabs,
// this will go to the last tab.
// Moves a tab by a relative offset.
//
// Positive values move the tab forwards, and negative values move it
// backwards. If the new position is out of bounds, it is wrapped around
// cyclically within the tab list.
//
// For example, `move_tab:1` moves the tab one position forwards, and if
// it was already the last tab in the list, it wraps around and becomes
// the first tab in the list. Likewise, `move_tab:-1` moves the tab one
// position backwards, and if it was the first tab, then it will become
// the last tab.
// Toggle the tab overview.
//
// This is only supported on Linux and when the system's libadwaita
// version is 1.4 or newer. The current libadwaita version can be
// found by running `witty +version`.
// Change the title of the current focused surface via a pop-up prompt.
//
// This requires libadwaita 1.5 or newer on Linux. The current libadwaita
// version can be found by running `witty +version`.
// Change the title of the current tab/window via a pop-up prompt. The
// title set via this prompt overrides any title set by the terminal
// and persists across focus changes within the tab.
// Create a new split in the specified direction.
//
// Valid arguments:
//
//   - `right`, `down`, `left`, `up`
//
//     Creates a new split in the corresponding direction.
//
//   - `auto`
//
//     Creates a new split along the larger direction.
//     For example, if the parent split is currently wider than it is tall,
//     then a left-right split would be created, and vice versa.
//
// Focus on a split either in the specified direction (`right`, `down`,
// `left` and `up`), or in the adjacent split in the order of creation
// (`previous` and `next`).
// Focus on either the previous window or the next one ('previous', 'next')
// Zoom in or out of the current split.
//
// When a split is zoomed into, it will take up the entire space in
// the current tab, hiding other splits. The tab or tab bar would also
// reflect this by displaying an icon indicating the zoomed state.
// Toggle read-only mode for the current surface.
//
// When a surface is in read-only mode:
//   - No input is sent to the PTY (mouse events, key encoding)
//   - Input can still be used at the terminal level to make selections,
//     copy/paste (keybinds), scroll, etc.
//   - Warn before quit is always enabled in this state even if an active
//     process is not running
// Resize the current split in the specified direction and amount in
// pixels. The two arguments should be joined with a comma (`,`),
// like in `resize_split:up,10`.
// Equalize the size of all splits in the current window.
// Reset the window to the default size. The "default size" is the
// size that a new window would be created with. This has no effect
// if the window is fullscreen.
//
// Only implemented on macOS.
// Control the visibility of the terminal inspector.
//
// Valid arguments: `toggle`, `show`, `hide`.
// Show the GTK inspector.
//
// Has no effect on macOS.
// Show the on-screen keyboard if one is present.
//
// Only implemented on Linux (GTK). On GNOME, the "Screen Keyboard"
// accessibility feature must be turned on, which can be found under
// Settings > Accessibility > Typing. Other platforms are as of now
// untested.
// Open the configuration file in the default OS editor.
//
// If your default OS editor isn't configured then this will fail.
// Currently, any failures to open the configuration will show up only in
// the logs.
// Reload the configuration.
//
// The exact meaning depends on the app runtime in use, but this usually
// involves re-reading the configuration file and applying any changes
// Note that not all changes can be applied at runtime.
// Close the current "surface", whether that is a window, tab, split, etc.
//
// This might trigger a close confirmation popup, depending on the value
// of the `confirm-close-surface` configuration setting.
// Close the current tab and all splits therein, close all other tabs, or
// close every tab to the right of the current one depending on the mode.
//
// If the mode is not specified, defaults to closing the current tab.
//
// This might trigger a close confirmation popup, depending on the value
// of the `confirm-close-surface` configuration setting.
// Close the current window and all tabs and splits therein.
//
// This might trigger a close confirmation popup, depending on the value
// of the `confirm-close-surface` configuration setting.
// Close all windows.
//
// WARNING: This action has been deprecated and has no effect on either
// Linux or macOS. Users are instead encouraged to use `all:close_window`
// instead.
// Maximize or unmaximize the current window.
//
// This has no effect on macOS as it does not have the concept of
// maximized windows.
// Fullscreen or unfullscreen the current window.
// Toggle window decorations (titlebar, buttons, etc.) for the current window.
//
// Only implemented on Linux.
// Toggle whether the terminal window should always float on top of other
// windows even when unfocused.
//
// Terminal windows always start as normal (not float-on-top) windows.
//
// Only implemented on macOS.
// Toggle secure input mode.
//
// This is used to prevent apps from monitoring your keyboard input
// when entering passwords or other sensitive information.
//
// This applies to the entire application, not just the focused terminal.
// You must manually untoggle it or quit Ghostty entirely to disable it.
//
// Only implemented on macOS, as this uses a built-in system API.
// Toggle mouse reporting on or off.
//
// When mouse reporting is disabled, mouse events will not be reported to
// terminal applications even if they request it. This allows you to always
// use the mouse for selection and other terminal UI interactions without
// applications capturing mouse input.
//
// This can also be controlled via the `mouse-reporting` configuration
// option.
// Toggle the command palette.
//
// The command palette is a popup that lets you see what actions
// you can perform, their associated keybindings (if any), a search bar
// to filter the actions, and the ability to then execute the action.
//
// This requires libadwaita 1.5 or newer on Linux. The current libadwaita
// version can be found by running `witty +version`.
// Toggle the quick terminal.
//
// The quick terminal, also known as the "Quake-style" or drop-down
// terminal, is a terminal window that appears on demand from a keybinding,
// often sliding in from a screen edge such as the top. This is useful for
// quick access to a terminal without having to open a new window or tab.
//
// The terminal state is preserved between appearances, so showing the
// quick terminal after it was already hidden would display the same
// window instead of creating a new one.
//
// As quick terminals are often useful when other windows are currently
// focused, they are best used with *global* keybinds. For example, one
// can define the following key bind to toggle the quick terminal from
// anywhere within the system by pressing `` Cmd+` ``:
//
// ```ini
// keybind = global:cmd+backquote=toggle_quick_terminal
// ```
//
// The quick terminal has some limitations:
//
//   - Only one quick terminal instance can exist at a time.
//
//   - Unlike normal terminal windows, the quick terminal will not be
//     restored when the application is restarted on systems that support
//     window restoration like macOS.
//
//   - On Linux, the quick terminal is only supported on Wayland and not
//     X11, and only on Wayland compositors that support the `wlr-layer-shell-v1`
//     protocol. In practice, this means that only GNOME users would not be
//     able to use this feature.
//
//   - On Linux, slide-in animations are only supported on KDE, and when
//     the "Sliding Popups" KWin plugin is enabled.
//
//     If you do not have this plugin enabled, open System Settings > Apps
//     & Windows > Window Management > Desktop Effects, and enable the
//     plugin in the plugin list. Ghostty would then need to be restarted
//     fully for this to take effect.
//
//   - Quick terminal tabs are only supported on Linux and not on macOS.
//     This is because tabs on macOS require a title bar.
//
//   - On macOS, a fullscreened quick terminal will always be in non-native
//     fullscreen mode. This is a requirement due to how the quick terminal
//     is rendered.
//
// See the various configurations for the quick terminal in the
// configuration file to customize its behavior.
// Show or hide all windows. If all windows become shown, we also ensure
// Ghostty becomes focused. When hiding all windows, focus is yielded
// to the next application as determined by the OS.
//
// Note: When the focused surface is fullscreen, this method does nothing.
//
// Only implemented on macOS.
// Toggle the window background opacity between transparent and opaque.
//
// This does nothing when `background-opacity` is set to 1 or above.
//
// When `background-opacity` is less than 1, this action will either make
// the window transparent or not depending on its current transparency state.
//
// Only implemented on macOS.
// Check for updates.
//
// Only implemented on macOS.
// Undo the last undoable action for the focused surface or terminal,
// if possible. This can undo actions such as closing tabs or
// windows.
//
// Not every action in Ghostty can be undone or redone. The list
// of actions support undo/redo is currently limited to:
//
//   - New window, close window
//   - New tab, close tab
//   - New split, close split
//
// All actions are only undoable/redoable for a limited time.
// For example, restoring a closed split can only be done for
// some number of seconds since the split was closed. The exact
// amount is configured with the `undo-timeout` configuration settings.
//
// The undo/redo actions being limited ensures that there is
// bounded memory usage over time, closed surfaces don't continue running
// in the background indefinitely, and the keybinds become available
// for terminal applications to use.
//
// Only implemented on macOS.
// Redo the last undoable action for the focused surface or terminal,
// if possible. See "undo" for more details on what can and cannot
// be undone or redone.
// End the currently active key sequence, if any, and flush the
// keys up to this point to the terminal, excluding the key that
// triggered this action.
//
// For example: `ctrl+w>escape=end_key_sequence` would encode
// `ctrl+w` to the terminal and exit the key sequence.
//
// Normally, an invalid sequence will reset the key sequence and
// flush all data including the invalid key. This action allows
// you to flush only the prior keys, which is useful when you want
// to bind something like a control key (`ctrl+w`) but not send
// additional inputs.
// Activate a named key table (see `keybind` configuration documentation).
// The named key table will remain active until `deactivate_key_table`
// is called. If you want a one-shot key table activation, use the
// `activate_key_table_once` action instead.
//
// If the named key table does not exist, this action has no effect
// and performable will report false.
//
// If the named key table is already the currently active key table,
// this action has no effect and performable will report false.
// Same as activate_key_table, but the key table will only be active
// until the first valid keybinding from that table is used (including
// any defined `catch_all` bindings).
//
// The "once" check is only done if this is the currently active
// key table. If another key table is activated later, then this
// table will remain active until it pops back out to being the
// active key table.
// Deactivate the currently active key table, if any. The next most
// recently activated key table (if any) will become active again.
// If no key table is active, this action has no effect.
// Deactivate all active key tables. If no active key table exists,
// this will report performable as false.
// Quit Ghostty.
// Crash Ghostty in the desired thread for the focused surface.
//
// WARNING: This is a hard crash (panic) and data can be lost.
//
// The purpose of this action is to test crash handling. For some
// users, it may be useful to test crash reporting functionality in
// order to determine if it all works as expected.
//
// The value determines the crash location:
//
//   - `main`
//
//     Crash on the main (GUI) thread.
//
//   - `io`
//
//     Crash on the IO thread for the focused surface.
//
//   - `render`
//
//     Crash on the render thread for the focused surface.
//
// Make this a valid gobject if we're in a GTK environment.
// For backwards compatibility we map "top" and "bottom" onto the enum
// values "up" and "down"
// This type will mix multiple distinct types with a set content-type
// such as text/html for html, so that the OS/application can choose
// what is best when pasting.
// If we don't have a `,`, default to the plain format. This is
// also very important for backwards compatibility before Ghostty
// 1.3 which didn't support output formats.
// Extern because it is used in the embedded runtime ABI.
// Fields can provide a custom "parse" function
// Only tuples are supported to avoid ambiguity with field
// ordering
// If we have extra parameters it is an error
// Parse an action in the format of "key=value" where key is the
// action name and value is the action parameter. The parameter
// is optional depending on the action.
// Split our action by colon. A colon may not exist for some
// actions so it is optional. The part preceding the colon is the
// action name.
// An action name is always required
// If the field type is void we expect no value
// Cursor keys can't be set currently
// Get the parameter after the colon. The parameter
// can be optional for action types that can have a
// "default" decl.
// The scope of an action. The scope is the context in which an action
// must be executed.
// Returns the scope of an action.
// Doesn't really matter, so we'll see app.
// Obviously app actions.
// These are app but can be special-cased in a surface context.
// Obviously surface actions.
// These are less obvious surface actions. They're surface
// actions because they are relevant to the surface they
// come from. For example `new_window` needs to be sourced to
// a surface so inheritance can be done correctly.
// Returns a union type that only contains actions that are scoped to
// the given scope.
// Find all fields that are app-scoped
// Build our union
// Returns the scoped version of this action. If the action is not
// scoped to the given scope then this returns null.
//
// The benefit of this function is that it allows us to use Zig's
// exhaustive switch safety to ensure we always properly handle certain
// scoped actions.
// Use comptime to prune out non-app actions
// Initialize our app action
// Implements the formatter for the fmt package. This encodes the
// action back into the format used by parse.
// All actions start with the tag.
// Only write the value depending on the type if it's not void
// Clone this action with the given allocator. The allocator
// should be an arena-style allocator since fine-grained
// deallocation is not possible.
// Returns a hash code that can be used to uniquely identify this
// action.
// Hash the action into the given hasher.
// Always has the active tag.
// Hash the value of the field.
// Do nothing for void
// Floats are hashed by their bits. This is totally not
// portable and there are edge cases such as NaNs and
// signed zeros but these are not cases we expect for
// our bindings.
// Everything else automatically handle.
// Compares two actions for equality.
// For the Set.Context
// Trigger is the associated key state that can trigger an action.
// This is an extern struct because this is also used in the C API.
//
// This must be kept in sync with include/witty.h ghostty_input_trigger_s
// The key that has to be pressed for a binding to take action.
// The key modifiers that must be active for this to match.
// key is the "physical" version. This is the same as mapped for
// standard US keyboard layouts. For non-US keyboard layouts, this
// is used to bind to a physical key location rather than a translated
// key.
// This is used for binding to keys that produce a certain unicode
// codepoint. This is useful for binding to keys that don't have a
// registered keycode with Ghostty.
// A catch-all key that matches any key press that is otherwise
// unbound.
// The extern struct used for triggers in the C API.
// Parse a single trigger. The input is expected to be ONLY the trigger
// (i.e. in the sequence `a=ignore` input is only `a`). The trigger may
// not be part of a sequence (i.e. `a>b`). This parses exactly a single
// trigger.
// Check if its a modifier
// Repeat not allowed
// Alias modifiers
// Repeat not allowed
// Anything after this point is a key and we only support
// single keys.
// If the part is empty it means that it is actually
// a literal `+`, which we treat as a Unicode character.
// Check if its a key
// If we're still unset and we have exactly one unicode
// character then we can use that as a key.
// Invalid UTF8 drops to invalid format
// No codepoints or multiple codepoints drops to invalid format
// Look for a matching w3c name next.
// Check for catch_all. We do this near the end since its unlikely
// in most cases that we're setting a catch-all key.
// If we're still unset then we look for backwards compatible
// keys with Ghostty 1.1.x. We do this last so its least likely
// to impact performance for modern users.
// We didn't recognize this value
// The values that are backwards compatible with Ghostty 1.1.x.
// Ghostty 1.2+ doesn't support these anymore since we moved to
// W3C key codes.
// Physical variants. This is a blunt approach to this but its
// glue for backwards compatibility so I'm not too worried about
// making this super nice.
// Returns true if this trigger has no key set.
// Returns a hash code that can be used to uniquely identify this trigger.
// Hash the trigger into the given hasher.
// The codepoint we use for comparisons. Case folding can result
// in more codepoints so we need to use a 3 element array.
// ASCII fast path
// Unicode slow path. Case folding can result in more codepoints.
// If more codepoints are produced then we return the codepoint
// as-is which isn't correct but until we have a failing test
// then I don't want to handle this.
// Returns true if two triggers are equal.
// Returns true if two triggers are equal using folded codepoints.
// For the Set.Context
// Convert the trigger to a C API compatible trigger.
// catch_all has no associated value so its an error
// for a C consumer to look at it.
// Format implementation for fmt package.
// Modifiers first
// Key
// A structure that contains a set of bindings and focuses on fast lookup.
// The use case is that this will be called on EVERY key input to look
// for an associated action so it must be fast.
// The set of bindings.
// The reverse mapping of action to binding. Note that multiple
// bindings can map to the same action and this map will only have
// the most recently added binding for an action.
//
// Sequenced triggers are never present in the reverse map at this time.
// This is a conscious decision since the primary use case of the reverse
// map is to support GUI toolkit keyboard accelerators and no mainstream
// GUI toolkit supports sequences.
//
// Performable triggers are also not present in the reverse map. This
// is so that GUI toolkits don't register performable triggers as
// menu shortcuts (the primary use case of the reverse map). GUI toolkits
// such as GTK handle menu shortcuts too early in the event lifecycle
// for performable to work so this is a conscious decision to ease the
// integration with GUI toolkits.
// The chain parent is the information necessary to attach a chained
// action to the proper location in our mapping. It tracks both the
// entry in the hashmap and the set it belongs to, which is needed
// to properly update reverse mappings when converting a leaf to
// a chained action.
// Information about a chain parent entry, including which set it
// belongs to. This is needed because reverse mappings are only
// maintained in the root set, but the chain parent entry may be
// in a nested set (for leader key sequences).
// The entry type for the forward mapping of trigger to action.
// This key is a leader key in a sequence. You must follow the given
// set to find the next key in the sequence.
// This trigger completes a sequence and the value is the action
// to take along with the flags that may define binding behavior.
// A set of actions to take in response to a trigger.
// Implements the formatter for the fmt package. This encodes the
// action back into the format used by parse.
// the leader key was already printed.
// action implements the format
// Writes the configuration entries for the binding
// that this value is part of.
//
// The value may be part of multiple configuration entries
// if they're all part of the same prefix sequence (e.g. 'a>b', 'a>c').
// These will result in multiple separate entries in the configuration.
//
// `buffer_stream` is a FixedBufferStream used for temporary storage
// that is shared between calls to nested levels of the set.
// For example, 'a>b>c=x' and 'a>b>d=y' will reuse the 'a>b' written
// to the buffer before flushing it to the formatter with 'c=x' and 'd=y'.
// We'll rewind to this position after each sub-entry,
// sharing the prefix between siblings.
// I'm not exactly if this is safe for any arbitrary
// writer since the Writer interface does not have any
// rewind functions, but for our use case of a
// fixed-size buffer writer this should work just fine.
// When we get to the leaf, the buffer_stream contains
// the full sequence of keys needed to reach this action.
// Leaf node of a set is an action to trigger. This is a "leaf" compared
// to the inner nodes which are "leaders" for sequences.
// Leaf node of a set that triggers multiple actions in sequence.
// A generic leaf node that can be used to unify the handling of
// leaf and leaf_chained.
// A full key-value entry for the set.
// Clear any leaders if we have them
// Parse a user input binding and add it to the set. This will handle
// the "unbind" case, ensure consumed/unconsumed fields are set correctly,
// handle sequences, etc.
//
// If this returns an OutOfMemory error then the set is in a broken
// state and should not be used again. Any Error returned is validated
// before any set modifications are made.
// To make cleanup easier, we ensure that the full sequence is
// valid before making any set modifications. This is more expensive
// computationally but it makes cleanup way, way easier.
// We use recursion so that we can utilize the stack as our state
// for cleanup.
// If this gets sent up to the root then we've unbound
// all the way up and this put was a success.
// If our parser input was too short then the format
// is invalid because we handle all valid cases.
// If we had a chain without a parent then the format is wrong.
// If we had an invalid action for a chain (e.g. unbind).
// Unrecoverable
// Errors must never fall through.
// If we have an updated set (a binding was added) then we store
// it for our chain parent. If we didn't update a set then we clear
// our chain parent since chaining is no longer valid until a
// valid binding is saved.
// A successful addition must have recorded a chain parent.
// Returns the set that was ultimately updated if a binding was
// added. Unbind does not return a set since nothing was added.
// If we have a leader, we need to upsert a set for it.
// Since we remove the value, we need to copy it.
// We have an existing leader for this key already
// so recurse into this set.
// Our child put unbound. If our set is empty we
// need to dealloc and continue up. If our set is
// not empty then we're done.
// Remove the existing action. Fallthrough as if
// we don't have a leader.
// Create our new set for this leader
// Insert the leader entry
// Recurse
// If our action was to unbind, we restore the old
// action if we have it.
// Rebuild our chain
// Chains can only happen on the root.
// Unbind is not valid for chains.
// Add a binding to the set. If the binding already exists then
// this will overwrite it.
// Add a binding to the set with explicit flags.
// unbind should never go into the set, it should be handled prior
// This is true if we're going to track this entry as
// a reverse mapping. There are certain scenarios we don't.
// See the reverse map docs for more information.
// No matter what our chained parent becomes invalid because
// getOrPut invalidates pointers.
// If we have any errors we can't trust our values here. And
// we can't restore the old values because they're also invalidated
// by getOrPut so we just disable chaining.
// If we have a leader we need to clean up the memory
// If we have an existing binding for this trigger, we have to
// update the reverse mapping to remove the old action.
// Chained leaves aren't in the reverse mapping so we just
// clear it out.
// Invariant: after successful put, chain_parent must be valid and point
// to the entry we just added/updated.
// Append a chained action to the prior set action.
//
// It is an error if there is no valid prior chain parent.
// Unbind is not a valid chain action; callers must check this.
// Leader can never be a chain parent. Verified through various
// assertions and unit tests.
// If it is already a chained action, we just append the
// action. Easy!
// If it is a leaf, we need to convert it to a leaf_chained.
// We also need to be careful to remove any prior reverse
// mappings for this action since chained actions are not
// part of the reverse mapping.
// Setup our failable actions list first.
// Convert to leaf_chained first, before fixing up reverse
// mapping. This is important because fixupReverseForAction
// searches for other bindings with the same action, and we
// don't want to find this entry (which is now chained).
// Clean up our reverse mapping. Chained actions are not
// part of the reverse mapping, so we need to fix up the
// reverse map (possibly restoring another trigger for the
// same action).
// Get a binding for a given trigger.
// Get a trigger for the given action. An action can have multiple
// triggers so this will return the first one found.
// Get an entry for the given key event. This will attempt to find
// a binding using multiple parts of the event in the following order:
//
//   1. Translated key (event.key)
//   2. Physical key (event.physical_key)
//   3. Unshifted Unicode codepoint (event.unshifted_codepoint)
//
// If our UTF-8 text is exactly one codepoint, we try to match that.
// No codepoints or multiple codepoints drops to invalid format
// Finally fallback to the full unshifted codepoint if we have one.
// Question: should we be doing this if we have UTF-8 text? I
// suspect "no" but we don't currently have any failing scenarios
// to verify this.
// Fallback to catch_all with modifiers first, then without modifiers.
// Remove a binding for a given trigger.
// Removal always resets our chain parent. We could make this
// finer grained but the way it is documented is that chaining
// must happen directly after sets so this works.
// For a leader removal, we need to deallocate our child set.
// Leaders are never part of reverse maps so no other accounting
// needs to be done.
// For an action we need to fix up the reverse mapping.
// Chained leaves are never in our reverse mapping so no
// cleanup is required.
// Fix up the reverse mapping after removing an action.
//
// When an action is removed from a binding (either by removal or by
// converting to a chained action), we need to update the reverse mapping.
// If another binding has the same action, we update the reverse mapping
// to point to that binding. Otherwise, we remove the action from the
// reverse mapping entirely.
//
// The `old` parameter is the trigger that was previously bound to this
// action. It is used to check if the reverse mapping still points to
// this trigger; if not, no fixup is needed since the reverse map already
// points to a different trigger for this action.
//
// Note: we'd LIKE to replace this with the most recent binding but
// our hash map obviously has no concept of ordering so we have to
// choose whatever. Maybe a switch to an array hash map here.
// If our value is not the same as the old trigger, we can
// ignore it because our reverse mapping points somewhere else.
// It is the same trigger, so let's now go through our bindings
// and try to find another trigger that maps to the same action.
// No other trigger points to this action so we remove
// the reverse mapping completely.
// Deep clone the set.
// If we have any leaders we need to clone them.
// Leaves could have data to clone (i.e. text actions
// contain allocated strings).
// Must be deep cloned.
// We need to clone the action keys in the reverse map since
// they may contain allocated values.
// The hash map context for the set. This defines how the hash map
// gets the hash key and checks for equality.
// This seems crazy at first glance but this is also how
// the Zig standard library handles hashing for array
// hash maps!
// single character
// single modifier
// multiple modifier
// key can come before modifier
// physical keys
// unicode keys
// unconsumed keys
// unconsumed physical keys
// performable keys
// invalid key
// repeated control
// multiple character
// Exact match
// Case-sensitive
// Basic catch_all
// catch_all with modifiers
// Modifier
// Modifier
// For Ghostty 1.2+ we changed our key names to match the W3C and removed
// `physical:`. This tests the backwards compatibility with the old format.
// Note that our backwards compatibility isn't 100% perfect since triggers
// like `a` now map to unicode instead of "translated" (which was also
// removed). But we did our best here with what was unambiguous.
// simple, for sanity
// duplicates
// test our full map
// global keys
// global physical keys
// global unconsumed keys
// global sequences not allowed
// all keys
// all physical keys
// all unconsumed keys
// all sequences not allowed
// Equal physical keys
// Different physical keys
// Different mods
// Equal unicode keys
// Different unicode keys
// Different key types
// catch_all
// catch_all with different mods
// invalid action
// no parameters
// parameter
// parameter
// parameter
// parameter
// parameter
// parameter
// parameter
// missing parameter
// too many
// invalid type
// Valid
// Chain can't have flags
// Chain can't be part of a sequence
// single character
// multi character
// empty
// empty starting sequence
// empty ending sequence
// single character
// sequence
// Creates forward mapping
// Creates reverse mapping
// Sets up the chain parent properly
// Creates forward mapping
// Creates reverse mapping
// Sets up the chain parent properly
// Creates forward mapping
// Sets up the chain parent properly
// chain_parent should be set
// chain_parent value should be a leaf
// chain_parent should be set
// chain_parent value should be a leaf with correct flags
// chain_parent should be set and point to 'b' (the final leaf)
// chain_parent value should be a leaf
// After first binding, chain_parent should be 'b'
// After second binding, chain_parent should be updated to 'c'
// After unbind, chain_parent should be cleared
// After unbind, chain_parent should be cleared even though 'c' remains
// But 'c' should still exist
// After removal, chain_parent should be cleared
// Try an invalid parse - should fail
// chain_parent should be unchanged
// Clone should have null chain_parent
// But should have the binding
// Create a chained binding using parseAndPut with chain=
// Verify we have a leaf_chained
// Clone the set
// Verify the cloned set has the leaf_chained with same actions
// Create a chained binding with text actions (which have allocated strings)
// Verify we have a leaf_chained
// Clone the set
// Verify the cloned set has independent copies of the text
// Verify the pointers are different (truly cloned, not shared)
// Creates reverse mapping
// Creates reverse mapping
// should be most recent
// removal should replace
// trigger should be non-performable
// removal of performable should do nothing
// should be most recent
// Creates forward mapping as leaf_chained
// Does not create reverse mapping, because reverse mappings are only for
// non-chained actions.
// Chain without a prior binding should fail
// Should have 3 actions chained
// Should preserve unconsumed flag
// Chain after unbind should fail because chain_parent is cleared
// Navigate to the inner set
// Check the chained binding
// chain=unbind is not valid
// Original binding should still exist
// Physical matches on physical
// Physical does not match on UTF8/codepoint
// Matches on codepoint
// Matches on UTF-8
// Doesn't match on physical
// Lowercase codepoint
// Uppercase codepoint
// Negative case for sanity
// Matches unbound key without modifiers
// Matches unbound key with modifiers (falls back to catch_all without mods)
// Specific binding takes precedence over catch_all
// Key with ctrl matches catch_all with ctrl modifier
// Key without mods matches catch_all without mods
// Key with different mods falls back to catch_all without mods
// parameter
// parameter
// parameter
// parameter
// paramet  r
// First appendChain converts leaf to leaf_chained and appends the new action
// Verify reverse mapping exists before chaining
// Chaining should remove the reverse mapping
// Reverse mapping should be gone since chained actions are not in reverse map
// Add a non-performable binding first
// Add a performable binding (not in reverse map) and chain it
// close_surface was performable, so not in reverse map
// Chaining the performable binding should not crash or affect anything
// The non-performable new_window binding should still be in reverse map
// Add two bindings for the same action
// Reverse mapping should point to 'b' (most recent)
// Chain an action to 'b', which should restore 'a' in the reverse map
// Now reverse mapping should point to 'a'
// Create a chained binding
// Verify it's a leaf_chained
// Format the entries
// Write the trigger first (as formatEntry in Config.zig does)
// Create a chained binding with 3 actions
// Verify it's a leaf_chained with 3 actions
// Format the entries
// Create a chained binding with text actions
// Format the entries
//
// --- Original Ghostty Comments End: src/input/Binding.zig

// A binding maps some input trigger to an action. When the trigger
// occurs, the action is performed.

// Binding represents a complete key binding: trigger + action + flags.
pub struct Binding {
pub:
	// The trigger that needs to be performed to execute the action.
	trigger Trigger
	// The action to take if this binding matches.
	action Action
	// Boolean flags that can be set per binding.
	flags Flags
}

pub fn (a Binding) == (b Binding) bool {
	return a.trigger.equal(b.trigger) && a.action.equal(b.action) && a.flags == b.flags
}

// BindingError represents binding parsing errors.
pub enum BindingError {
	invalid_format
	invalid_action
	unexpected_chain
	unexpected_sequence
}

// Flags are the full binding-scoped flags that can be set per binding.
// Ghostty exposes this exact packed byte through its C API.
pub struct Flags {
mut:
	value u8 = 0b0001
}

pub fn Flags.init(consumed bool, all bool, global bool, performable bool) Flags {
	return Flags{
		value: u8(consumed) | (u8(all) << 1) | (u8(global) << 2) | (u8(performable) << 3)
	}
}

pub fn (self Flags) consumed() bool {
	return self.value & 0b0001 != 0
}

pub fn (self Flags) all() bool {
	return self.value & 0b0010 != 0
}

pub fn (self Flags) global() bool {
	return self.value & 0b0100 != 0
}

pub fn (self Flags) performable() bool {
	return self.value & 0b1000 != 0
}

fn (mut self Flags) set_consumed(value bool) {
	self.set(0b0001, value)
}

fn (mut self Flags) set_all(value bool) {
	self.set(0b0010, value)
}

fn (mut self Flags) set_global(value bool) {
	self.set(0b0100, value)
}

fn (mut self Flags) set_performable(value bool) {
	self.set(0b1000, value)
}

fn (mut self Flags) set(mask u8, enabled bool) {
	if enabled {
		self.value |= mask
	} else {
		self.value &= ~mask
	}
}

// cval converts flags to a packed u8 value.
pub fn (f Flags) cval() u8 {
	return f.value
}

// TriggerKey is the key part of a trigger: the source's `Trigger.Key`
// tagged union.
pub type TriggerKey = TriggerKeyCatchAll | TriggerKeyPhysical | TriggerKeyUnicode

// key is the "physical" version. This is the same as mapped for
// standard US keyboard layouts. For non-US keyboard layouts, this
// is used to bind to a physical key location rather than a translated
// key.
pub struct TriggerKeyPhysical {
pub:
	key Key
}

// This is used for binding to keys that produce a certain unicode
// codepoint. This is useful for binding to keys that don't have a
// registered keycode with Ghostty.
pub struct TriggerKeyUnicode {
pub:
	// The source stores a u21.
	codepoint u32
}

// A catch-all key that matches any key press that is otherwise
// unbound.
pub struct TriggerKeyCatchAll {}

// TriggerKeyTag is the source's `Trigger.C.Tag`, an `enum(c_int)`.
pub enum TriggerKeyTag as i32 {
	physical
	unicode
	catch_all
}

// The tag of the active key variant.
pub fn (self TriggerKey) tag() TriggerKeyTag {
	return match self {
		TriggerKeyPhysical { .physical }
		TriggerKeyUnicode { .unicode }
		TriggerKeyCatchAll { .catch_all }
	}
}

// Trigger is the associated key state that can trigger an action.
pub struct Trigger {
pub:
	// The key that has to be pressed for a binding to take action.
	key TriggerKey = TriggerKeyPhysical{
		key: .unidentified
	}
	// The key modifiers that must be active for this to match.
	mods Mods
}

pub fn (a Trigger) == (b Trigger) bool {
	return a.equal(b)
}

// Returns true if this trigger has no key set.
pub fn (t Trigger) is_key_unset() bool {
	return match t.key {
		TriggerKeyPhysical { t.key.key == .unidentified }
		TriggerKeyUnicode, TriggerKeyCatchAll { false }
	}
}

// Returns true if two triggers are equal.
pub fn (self Trigger) equal(other Trigger) bool {
	if self.mods != other.mods {
		return false
	}
	if self.key.tag() != other.key.tag() {
		return false
	}
	return match self.key {
		TriggerKeyPhysical { self.key.key == (other.key as TriggerKeyPhysical).key }
		TriggerKeyUnicode { self.key.codepoint == (other.key as TriggerKeyUnicode).codepoint }
		TriggerKeyCatchAll { true }
	}
}

// Returns true if two triggers are equal using folded codepoints
// (case-insensitive for unicode keys).
pub fn (self Trigger) folded_equal(other Trigger) bool {
	if self.mods != other.mods {
		return false
	}
	if self.key.tag() != other.key.tag() {
		return false
	}
	return match self.key {
		TriggerKeyPhysical { self.key.key == (other.key as TriggerKeyPhysical).key }
		TriggerKeyUnicode {
			folded_codepoint(self.key.codepoint) == folded_codepoint((other.key as TriggerKeyUnicode).codepoint)
		}
		TriggerKeyCatchAll { true }
	}
}

// folded_codepoint returns the source's fixed-width case-folded key. Full
// Unicode folding can expand one codepoint into as many as three codepoints.
fn folded_codepoint(cp u32) [3]u32 {
	if cp >= u32(`A`) && cp <= u32(`Z`) {
		return [cp + 32, u32(0), 0]!
	}
	return unicode_case_fold(cp)
}

// hash returns a hash code for the trigger.
pub fn (t Trigger) hash() u64 {
	mut hasher := SourceHash{}
	// Trigger.Key is union(C.Tag), and C.Tag is enum(c_int).
	hasher.put_i32(i32(t.key.tag()))
	match t.key {
		TriggerKeyPhysical {
			// input.Key is also enum(c_int).
			hasher.put_i32(i32(t.key.key))
		}
		TriggerKeyUnicode {
			for cp in folded_codepoint(t.key.codepoint) {
				hasher.put_u21(cp)
			}
		}
		TriggerKeyCatchAll {}
	}
	hasher.put_u16(t.mods.binding().int())
	return hasher.final()
}

// format returns the trigger as a string (e.g. "ctrl+a", "shift+key_a").
pub fn (t Trigger) format() string {
	mut parts := []string{}
	if t.mods.super_() {
		parts << 'super'
	}
	if t.mods.ctrl() {
		parts << 'ctrl'
	}
	if t.mods.alt() {
		parts << 'alt'
	}
	if t.mods.shift() {
		parts << 'shift'
	}
	match t.key {
		TriggerKeyPhysical {
			parts << t.key.key.key_name()
		}
		TriggerKeyUnicode {
			if t.key.codepoint < 128 {
				parts << [u8(t.key.codepoint)].bytestr()
			} else {
				// encode as utf-8
				parts << rune(t.key.codepoint).str()
			}
		}
		TriggerKeyCatchAll {
			parts << 'catch_all'
		}
	}
	return parts.join('+')
}

// parse parses a single trigger string (e.g. "ctrl+a", "shift+key_a").
pub fn Trigger.parse(input_str string) !Trigger {
	if input_str.len == 0 {
		return error('InvalidFormat')
	}
	mut result := Trigger{}
	mut rem := input_str
	for rem.len > 0 {
		idx := rem.index_u8(`+`)
		part, next := if idx >= 0 {
			rem[..idx], rem[idx + 1..]
		} else {
			rem, ''
		}
		rem = next

		// Check if it's a modifier
		if part == 'shift' {
			if result.mods.shift() {
				return error('InvalidFormat')
			}
			mut mods := result.mods
			mods.set_shift(true)
			result = Trigger{
				...result
				mods: mods
			}
			continue
		}
		if part == 'ctrl' {
			if result.mods.ctrl() {
				return error('InvalidFormat')
			}
			mut mods := result.mods
			mods.set_ctrl(true)
			result = Trigger{
				...result
				mods: mods
			}
			continue
		}
		if part == 'alt' {
			if result.mods.alt() {
				return error('InvalidFormat')
			}
			mut mods := result.mods
			mods.set_alt(true)
			result = Trigger{
				...result
				mods: mods
			}
			continue
		}
		if part == 'super' {
			if result.mods.super_() {
				return error('InvalidFormat')
			}
			mut mods := result.mods
			mods.set_super(true)
			result = Trigger{
				...result
				mods: mods
			}
			continue
		}

		// Check modifier aliases
		if alias := mod_alias(part) {
			if alias == 'super_' {
				if result.mods.super_() {
					return error('InvalidFormat')
				}
				mut mods := result.mods
				mods.set_super(true)
				result = Trigger{
					...result
					mods: mods
				}
				continue
			}
			if alias == 'alt' {
				if result.mods.alt() {
					return error('InvalidFormat')
				}
				mut mods := result.mods
				mods.set_alt(true)
				result = Trigger{
					...result
					mods: mods
				}
				continue
			}
			if alias == 'ctrl' {
				if result.mods.ctrl() {
					return error('InvalidFormat')
				}
				mut mods := result.mods
				mods.set_ctrl(true)
				result = Trigger{
					...result
					mods: mods
				}
				continue
			}
		}

		// Anything after this point is a key and we only support single keys.
		if !result.is_key_unset() {
			return error('InvalidFormat')
		}

		// If the part is empty it means it is actually a literal `+`,
		// which we treat as a Unicode character.
		if part.len == 0 {
			result = Trigger{
				...result
				key: TriggerKeyUnicode{ codepoint: u32(`+`) }
			}
			continue
		}

		// Check if it's a known physical key name
		if k := key_from_name(part) {
			if k != .unidentified {
				result = Trigger{
					...result
					key: TriggerKeyPhysical{ key: k }
				}
				continue
			}
		}

		// If we have exactly one unicode codepoint, use that as a key.
		if result.is_key_unset() {
			runes := part.runes()
			if runes.len == 1 {
				result = Trigger{
					...result
					key: TriggerKeyUnicode{ codepoint: u32(runes[0]) }
				}
				continue
			}
		}

		// Look for a matching W3C name
		if w3c_key := Key.from_w3c(part) {
			result = Trigger{
				...result
				key: TriggerKeyPhysical{ key: w3c_key }
			}
			continue
		}

		// Check for catch_all
		if part == 'catch_all' {
			result = Trigger{
				...result
				key: TriggerKeyCatchAll{}
			}
			continue
		}

		// Check backwards compatible keys
		if old_key := backwards_compatible_key(part) {
			result = Trigger{
				...result
				key: old_key
			}
			continue
		}

		// We didn't recognize this value
		return error('InvalidFormat')
	}

	return result
}

// --- Action ---

// Ignore this key combination.
pub struct ActionIgnore {}

// Unbind a previously bound key binding.
pub struct ActionUnbind {}

// Send a CSI sequence.
pub struct ActionCsi {
pub:
	value string
}

// Send an ESC sequence.
pub struct ActionEsc {
pub:
	value string
}

// Send the specified text.
pub struct ActionText {
pub:
	value string
}

// Send data to the pty depending on whether cursor key mode is enabled
// (application) or disabled (normal).
pub struct ActionCursorKey {
pub:
	value CursorKey
}

// Reset the terminal.
pub struct ActionReset {}

// Copy the selected text to the clipboard.
pub struct ActionCopyToClipboard {
pub:
	value CopyToClipboard
}

// Paste the contents of the default clipboard.
pub struct ActionPasteFromClipboard {}

// Paste the contents of the selection clipboard.
pub struct ActionPasteFromSelection {}

// If there is a URL under the cursor, copy it to the default clipboard.
pub struct ActionCopyUrlToClipboard {}

// Copy the terminal title to the clipboard.
pub struct ActionCopyTitleToClipboard {}

// Increase the font size by the specified amount in points.
pub struct ActionIncreaseFontSize {
pub:
	value f32
}

// Decrease the font size by the specified amount in points.
pub struct ActionDecreaseFontSize {
pub:
	value f32
}

// Reset the font size to the original configured size.
pub struct ActionResetFontSize {}

// Set the font size to the specified size in points.
pub struct ActionSetFontSize {
pub:
	value f32
}

// Start a search for the given text.
pub struct ActionSearch {
pub:
	value string
}

// Start a search for the current text selection.
pub struct ActionSearchSelection {}

// Navigate the search results.
pub struct ActionNavigateSearch {
pub:
	value NavigateSearch
}

// Start a search if it isn't started already.
pub struct ActionStartSearch {}

// End the current search if any and hide any GUI elements.
pub struct ActionEndSearch {}

// Clear the screen and all scrollback.
pub struct ActionClearScreen {}

// Select all text on the screen.
pub struct ActionSelectAll {}

// Scroll to the top of the screen.
pub struct ActionScrollToTop {}

// Scroll to the bottom of the screen.
pub struct ActionScrollToBottom {}

// Scroll to the selected text.
pub struct ActionScrollToSelection {}

// Scroll to the given absolute row.
pub struct ActionScrollToRow {
pub:
	value uint
}

// Scroll the screen up by one page.
pub struct ActionScrollPageUp {}

// Scroll the screen down by one page.
pub struct ActionScrollPageDown {}

// Scroll the screen by the specified fraction of a page.
pub struct ActionScrollPageFractional {
pub:
	value f32
}

// Scroll the screen by the specified amount of lines.
pub struct ActionScrollPageLines {
pub:
	value i16
}

// Adjust the current selection.
pub struct ActionAdjustSelection {
pub:
	value AdjustSelection
}

// Jump the viewport forward or back by the given number of prompts.
pub struct ActionJumpToPrompt {
pub:
	value i16
}

// Write the entire scrollback into a temporary file with the specified action.
pub struct ActionWriteScrollbackFile {
pub:
	value WriteScreen
}

// Write the contents of the screen into a temporary file.
pub struct ActionWriteScreenFile {
pub:
	value WriteScreen
}

// Write the currently selected text into a temporary file.
pub struct ActionWriteSelectionFile {
pub:
	value WriteScreen
}

// Open a new window.
pub struct ActionNewWindow {}

// Open a new tab.
pub struct ActionNewTab {}

// Go to the previous tab.
pub struct ActionPreviousTab {}

// Go to the next tab.
pub struct ActionNextTab {}

// Go to the last tab.
pub struct ActionLastTab {}

// Go to the tab with the specific index.
pub struct ActionGotoTab {
pub:
	value uint
}

// Moves a tab by a relative offset.
pub struct ActionMoveTab {
pub:
	value int
}

// Toggle the tab overview.
pub struct ActionToggleTabOverview {}

// Change the title of the current focused surface via a pop-up prompt.
pub struct ActionPromptSurfaceTitle {}

// Change the title of the current tab/window via a pop-up prompt.
pub struct ActionPromptTabTitle {}

// Create a new split in the specified direction.
pub struct ActionNewSplit {
pub:
	value SplitDirection
}

// Focus on a split.
pub struct ActionGotoSplit {
pub:
	value SplitFocusDirection
}

// Focus on a window.
pub struct ActionGotoWindow {
pub:
	value GotoWindow
}

// Zoom in or out of the current split.
pub struct ActionToggleSplitZoom {}

// Toggle read-only mode for the current surface.
pub struct ActionToggleReadonly {}

// Resize the current split.
pub struct ActionResizeSplit {
pub:
	value SplitResizeParameter
}

// Equalize the size of all splits.
pub struct ActionEqualizeSplits {}

// Reset the window to the default size.
pub struct ActionResetWindowSize {}

// Control the visibility of the terminal inspector.
pub struct ActionInspector {
pub:
	value InspectorMode
}

// Show the GTK inspector.
pub struct ActionShowGtkInspector {}

// Show the on-screen keyboard.
pub struct ActionShowOnScreenKeyboard {}

// Open the configuration file.
pub struct ActionOpenConfig {}

// Reload the configuration.
pub struct ActionReloadConfig {}

// Close the current surface.
pub struct ActionCloseSurface {}

// Close the current tab.
pub struct ActionCloseTab {
pub:
	value CloseTabMode
}

// Close the current window.
pub struct ActionCloseWindow {}

// Close all windows.
pub struct ActionCloseAllWindows {}

// Maximize or unmaximize the current window.
pub struct ActionToggleMaximize {}

// Fullscreen or unfullscreen the current window.
pub struct ActionToggleFullscreen {}

// Toggle window decorations.
pub struct ActionToggleWindowDecorations {}

// Toggle whether the window should float on top.
pub struct ActionToggleWindowFloatOnTop {}

// Toggle secure input mode.
pub struct ActionToggleSecureInput {}

// Toggle mouse reporting.
pub struct ActionToggleMouseReporting {}

// Toggle the command palette.
pub struct ActionToggleCommandPalette {}

// Toggle the quick terminal.
pub struct ActionToggleQuickTerminal {}

// Show or hide all windows.
pub struct ActionToggleVisibility {}

// Toggle background opacity.
pub struct ActionToggleBackgroundOpacity {}

// Check for updates.
pub struct ActionCheckForUpdates {}

// Undo the last undoable action.
pub struct ActionUndo {}

// Redo the last undoable action.
pub struct ActionRedo {}

// End the currently active key sequence.
pub struct ActionEndKeySequence {}

// Activate a named key table.
pub struct ActionActivateKeyTable {
pub:
	value string
}

// Same as activate_key_table, but only for one use.
pub struct ActionActivateKeyTableOnce {
pub:
	value string
}

// Deactivate the currently active key table.
pub struct ActionDeactivateKeyTable {}

// Deactivate all active key tables.
pub struct ActionDeactivateAllKeyTables {}

// Quit the application.
pub struct ActionQuit {}

// Crash the application for testing.
pub struct ActionCrash {
pub:
	value CrashThread
}

pub type Action = ActionActivateKeyTable
	| ActionActivateKeyTableOnce
	| ActionAdjustSelection
	| ActionCheckForUpdates
	| ActionClearScreen
	| ActionCloseAllWindows
	| ActionCloseSurface
	| ActionCloseTab
	| ActionCloseWindow
	| ActionCopyTitleToClipboard
	| ActionCopyToClipboard
	| ActionCopyUrlToClipboard
	| ActionCrash
	| ActionCsi
	| ActionCursorKey
	| ActionDeactivateAllKeyTables
	| ActionDeactivateKeyTable
	| ActionDecreaseFontSize
	| ActionEndKeySequence
	| ActionEndSearch
	| ActionEqualizeSplits
	| ActionEsc
	| ActionGotoSplit
	| ActionGotoTab
	| ActionGotoWindow
	| ActionIgnore
	| ActionIncreaseFontSize
	| ActionInspector
	| ActionJumpToPrompt
	| ActionLastTab
	| ActionMoveTab
	| ActionNavigateSearch
	| ActionNewSplit
	| ActionNewTab
	| ActionNewWindow
	| ActionNextTab
	| ActionOpenConfig
	| ActionPasteFromClipboard
	| ActionPasteFromSelection
	| ActionPreviousTab
	| ActionPromptSurfaceTitle
	| ActionPromptTabTitle
	| ActionQuit
	| ActionRedo
	| ActionReloadConfig
	| ActionReset
	| ActionResetFontSize
	| ActionResetWindowSize
	| ActionResizeSplit
	| ActionScrollPageDown
	| ActionScrollPageFractional
	| ActionScrollPageLines
	| ActionScrollPageUp
	| ActionScrollToBottom
	| ActionScrollToRow
	| ActionScrollToSelection
	| ActionScrollToTop
	| ActionSearch
	| ActionSearchSelection
	| ActionSelectAll
	| ActionSetFontSize
	| ActionShowGtkInspector
	| ActionShowOnScreenKeyboard
	| ActionStartSearch
	| ActionText
	| ActionToggleBackgroundOpacity
	| ActionToggleCommandPalette
	| ActionToggleFullscreen
	| ActionToggleMaximize
	| ActionToggleMouseReporting
	| ActionToggleQuickTerminal
	| ActionToggleReadonly
	| ActionToggleSecureInput
	| ActionToggleSplitZoom
	| ActionToggleTabOverview
	| ActionToggleVisibility
	| ActionToggleWindowDecorations
	| ActionToggleWindowFloatOnTop
	| ActionUnbind
	| ActionUndo
	| ActionWriteScreenFile
	| ActionWriteScrollbackFile
	| ActionWriteSelectionFile

// ActionTag is the tag of the Action union.
pub enum ActionTag as u8 {
	ignore
	unbind
	csi
	esc
	text
	cursor_key
	reset
	copy_to_clipboard
	paste_from_clipboard
	paste_from_selection
	copy_url_to_clipboard
	copy_title_to_clipboard
	increase_font_size
	decrease_font_size
	reset_font_size
	set_font_size
	search
	search_selection
	navigate_search
	start_search
	end_search
	clear_screen
	select_all
	scroll_to_top
	scroll_to_bottom
	scroll_to_selection
	scroll_to_row
	scroll_page_up
	scroll_page_down
	scroll_page_fractional
	scroll_page_lines
	adjust_selection
	jump_to_prompt
	write_scrollback_file
	write_screen_file
	write_selection_file
	new_window
	new_tab
	previous_tab
	next_tab
	last_tab
	goto_tab
	move_tab
	toggle_tab_overview
	prompt_surface_title
	prompt_tab_title
	new_split
	goto_split
	goto_window
	toggle_split_zoom
	toggle_readonly
	resize_split
	equalize_splits
	reset_window_size
	inspector
	show_gtk_inspector
	show_on_screen_keyboard
	open_config
	reload_config
	close_surface
	close_tab
	close_window
	close_all_windows
	toggle_maximize
	toggle_fullscreen
	toggle_window_decorations
	toggle_window_float_on_top
	toggle_secure_input
	toggle_mouse_reporting
	toggle_command_palette
	toggle_quick_terminal
	toggle_visibility
	toggle_background_opacity
	check_for_updates
	undo
	redo
	end_key_sequence
	activate_key_table
	activate_key_table_once
	deactivate_key_table
	deactivate_all_key_tables
	quit
	crash
}

// The tag of the active action variant.
pub fn (a Action) tag() ActionTag {
	return match a {
		ActionIgnore { .ignore }
		ActionUnbind { .unbind }
		ActionCsi { .csi }
		ActionEsc { .esc }
		ActionText { .text }
		ActionCursorKey { .cursor_key }
		ActionReset { .reset }
		ActionCopyToClipboard { .copy_to_clipboard }
		ActionPasteFromClipboard { .paste_from_clipboard }
		ActionPasteFromSelection { .paste_from_selection }
		ActionCopyUrlToClipboard { .copy_url_to_clipboard }
		ActionCopyTitleToClipboard { .copy_title_to_clipboard }
		ActionIncreaseFontSize { .increase_font_size }
		ActionDecreaseFontSize { .decrease_font_size }
		ActionResetFontSize { .reset_font_size }
		ActionSetFontSize { .set_font_size }
		ActionSearch { .search }
		ActionSearchSelection { .search_selection }
		ActionNavigateSearch { .navigate_search }
		ActionStartSearch { .start_search }
		ActionEndSearch { .end_search }
		ActionClearScreen { .clear_screen }
		ActionSelectAll { .select_all }
		ActionScrollToTop { .scroll_to_top }
		ActionScrollToBottom { .scroll_to_bottom }
		ActionScrollToSelection { .scroll_to_selection }
		ActionScrollToRow { .scroll_to_row }
		ActionScrollPageUp { .scroll_page_up }
		ActionScrollPageDown { .scroll_page_down }
		ActionScrollPageFractional { .scroll_page_fractional }
		ActionScrollPageLines { .scroll_page_lines }
		ActionAdjustSelection { .adjust_selection }
		ActionJumpToPrompt { .jump_to_prompt }
		ActionWriteScrollbackFile { .write_scrollback_file }
		ActionWriteScreenFile { .write_screen_file }
		ActionWriteSelectionFile { .write_selection_file }
		ActionNewWindow { .new_window }
		ActionNewTab { .new_tab }
		ActionPreviousTab { .previous_tab }
		ActionNextTab { .next_tab }
		ActionLastTab { .last_tab }
		ActionGotoTab { .goto_tab }
		ActionMoveTab { .move_tab }
		ActionToggleTabOverview { .toggle_tab_overview }
		ActionPromptSurfaceTitle { .prompt_surface_title }
		ActionPromptTabTitle { .prompt_tab_title }
		ActionNewSplit { .new_split }
		ActionGotoSplit { .goto_split }
		ActionGotoWindow { .goto_window }
		ActionToggleSplitZoom { .toggle_split_zoom }
		ActionToggleReadonly { .toggle_readonly }
		ActionResizeSplit { .resize_split }
		ActionEqualizeSplits { .equalize_splits }
		ActionResetWindowSize { .reset_window_size }
		ActionInspector { .inspector }
		ActionShowGtkInspector { .show_gtk_inspector }
		ActionShowOnScreenKeyboard { .show_on_screen_keyboard }
		ActionOpenConfig { .open_config }
		ActionReloadConfig { .reload_config }
		ActionCloseSurface { .close_surface }
		ActionCloseTab { .close_tab }
		ActionCloseWindow { .close_window }
		ActionCloseAllWindows { .close_all_windows }
		ActionToggleMaximize { .toggle_maximize }
		ActionToggleFullscreen { .toggle_fullscreen }
		ActionToggleWindowDecorations { .toggle_window_decorations }
		ActionToggleWindowFloatOnTop { .toggle_window_float_on_top }
		ActionToggleSecureInput { .toggle_secure_input }
		ActionToggleMouseReporting { .toggle_mouse_reporting }
		ActionToggleCommandPalette { .toggle_command_palette }
		ActionToggleQuickTerminal { .toggle_quick_terminal }
		ActionToggleVisibility { .toggle_visibility }
		ActionToggleBackgroundOpacity { .toggle_background_opacity }
		ActionCheckForUpdates { .check_for_updates }
		ActionUndo { .undo }
		ActionRedo { .redo }
		ActionEndKeySequence { .end_key_sequence }
		ActionActivateKeyTable { .activate_key_table }
		ActionActivateKeyTableOnce { .activate_key_table_once }
		ActionDeactivateKeyTable { .deactivate_key_table }
		ActionDeactivateAllKeyTables { .deactivate_all_key_tables }
		ActionQuit { .quit }
		ActionCrash { .crash }
	}
}

// CursorKey is the pair of sequences a cursor-key binding sends, selected
// by the terminal's cursor-key mode.
pub struct CursorKey {
pub:
	normal      string
	application string
}

// SplitResizeParameter is the source's `struct { SplitResizeDirection, u16 }`
// tuple.
pub struct SplitResizeParameter {
pub:
	direction SplitResizeDirection
	amount    u16
}

// equal compares two actions for equality.
pub fn (a Action) equal(b Action) bool {
	return a == b
}

// clone duplicates the active action payload. Strings are the only owned
// payloads; numeric, enum, and void payloads are values.
pub fn (a Action) clone() Action {
	match a {
		ActionCsi {
			return ActionCsi{
				value: a.value.clone()
			}
		}
		ActionEsc {
			return ActionEsc{
				value: a.value.clone()
			}
		}
		ActionText {
			return ActionText{
				value: a.value.clone()
			}
		}
		ActionSearch {
			return ActionSearch{
				value: a.value.clone()
			}
		}
		ActionActivateKeyTable {
			return ActionActivateKeyTable{
				value: a.value.clone()
			}
		}
		ActionActivateKeyTableOnce {
			return ActionActivateKeyTableOnce{
				value: a.value.clone()
			}
		}
		ActionCursorKey {
			return ActionCursorKey{
				value: CursorKey{
					normal:      a.value.normal.clone()
					application: a.value.application.clone()
				}
			}
		}
		else {
			return a
		}
	}
}

// hash returns a hash code that can be used to uniquely identify this
// action.
pub fn (a Action) hash() u64 {
	mut hasher := SourceHash{}
	// Always has the active tag. Action's inferred tag type is u7 at the
	// pinned source revision.
	hasher.put_u8(u8(a.tag()))

	// Hash the value of the field.
	match a {
		ActionCursorKey {
			hasher.put_deep_string(a.value.normal)
			hasher.put_deep_string(a.value.application)
		}
		ActionCsi {
			hasher.put_deep_string(a.value)
		}
		ActionEsc {
			hasher.put_deep_string(a.value)
		}
		ActionText {
			hasher.put_deep_string(a.value)
		}
		ActionSearch {
			hasher.put_deep_string(a.value)
		}
		ActionActivateKeyTable {
			hasher.put_deep_string(a.value)
		}
		ActionActivateKeyTableOnce {
			hasher.put_deep_string(a.value)
		}
		// Floats are hashed by their bits.
		ActionIncreaseFontSize {
			hasher.put_f32(a.value)
		}
		ActionDecreaseFontSize {
			hasher.put_f32(a.value)
		}
		ActionSetFontSize {
			hasher.put_f32(a.value)
		}
		ActionScrollPageFractional {
			hasher.put_f32(a.value)
		}
		ActionJumpToPrompt {
			hasher.put_i16(a.value)
		}
		ActionScrollPageLines {
			hasher.put_i16(a.value)
		}
		ActionMoveTab {
			// isize is eight bytes on Ghostty's supported 64-bit targets.
			hasher.put_i64(i64(a.value))
		}
		ActionScrollToRow {
			// usize is eight bytes on Ghostty's supported 64-bit targets.
			hasher.put_u64(u64(a.value))
		}
		ActionGotoTab {
			hasher.put_u64(u64(a.value))
		}
		ActionNewSplit {
			hasher.put_u8(u8(a.value))
		}
		ActionGotoSplit {
			hasher.put_u8(u8(a.value))
		}
		ActionGotoWindow {
			hasher.put_u8(u8(a.value))
		}
		ActionNavigateSearch {
			hasher.put_u8(u8(a.value))
		}
		ActionAdjustSelection {
			hasher.put_u8(u8(a.value))
		}
		ActionCopyToClipboard {
			hasher.put_u8(u8(a.value))
		}
		ActionInspector {
			hasher.put_u8(u8(a.value))
		}
		ActionCloseTab {
			hasher.put_u8(u8(a.value))
		}
		ActionCrash {
			hasher.put_u8(u8(a.value))
		}
		ActionWriteScrollbackFile {
			hasher.put_u8(u8(a.value.action))
			hasher.put_u8(u8(a.value.emit))
		}
		ActionWriteScreenFile {
			hasher.put_u8(u8(a.value.action))
			hasher.put_u8(u8(a.value.emit))
		}
		ActionWriteSelectionFile {
			hasher.put_u8(u8(a.value.action))
			hasher.put_u8(u8(a.value.emit))
		}
		ActionResizeSplit {
			hasher.put_u8(u8(a.value.direction))
			hasher.put_u16(a.value.amount)
		}
		else {
			// Do nothing for void
		}
	}
	return hasher.final()
}

// format returns the action in the same syntax accepted by Action.parse.
// Ghostty uses std.zig.stringEscape for string payloads so that arbitrary
// bytes, including UTF-8, can safely round-trip through a config file.
pub fn (a Action) format() string {
	// All actions start with the tag.
	name := a.tag().str()
	return match a {
		ActionCsi { '${name}:${zig_escape(a.value)}' }
		ActionEsc { '${name}:${zig_escape(a.value)}' }
		ActionText { '${name}:${zig_escape(a.value)}' }
		ActionSearch { '${name}:${zig_escape(a.value)}' }
		ActionActivateKeyTable { '${name}:${zig_escape(a.value)}' }
		ActionActivateKeyTableOnce { '${name}:${zig_escape(a.value)}' }
		ActionIncreaseFontSize { '${name}:${a.value}' }
		ActionDecreaseFontSize { '${name}:${a.value}' }
		ActionSetFontSize { '${name}:${a.value}' }
		ActionScrollPageFractional { '${name}:${a.value}' }
		ActionJumpToPrompt { '${name}:${a.value}' }
		ActionScrollPageLines { '${name}:${a.value}' }
		ActionMoveTab { '${name}:${a.value}' }
		ActionScrollToRow { '${name}:${a.value}' }
		ActionGotoTab { '${name}:${a.value}' }
		ActionNewSplit { '${name}:${split_direction_name(a.value)}' }
		ActionGotoSplit { '${name}:${a.value}' }
		ActionGotoWindow { '${name}:${a.value}' }
		ActionNavigateSearch { '${name}:${a.value}' }
		ActionAdjustSelection { '${name}:${adjust_selection_name(a.value)}' }
		ActionCopyToClipboard { '${name}:${a.value}' }
		ActionInspector { '${name}:${a.value}' }
		ActionCloseTab { '${name}:${a.value}' }
		ActionCrash { '${name}:${crash_thread_name(a.value)}' }
		ActionResizeSplit { '${name}:${a.value.direction},${a.value.amount}' }
		ActionWriteScrollbackFile { '${name}:${a.value.format()}' }
		ActionWriteScreenFile { '${name}:${a.value.format()}' }
		ActionWriteSelectionFile { '${name}:${a.value.format()}' }
		else { name }
	}
}

fn split_direction_name(value SplitDirection) string {
	return if value == .auto_ { 'auto' } else { value.str() }
}

fn adjust_selection_name(value AdjustSelection) string {
	return if value == .end_ { 'end' } else { value.str() }
}

fn crash_thread_name(value CrashThread) string {
	return if value == .main_thread { 'main' } else { value.str() }
}

pub fn zig_escape(value string) string {
	mut result := strings.new_builder(value.len)
	for ch in value.bytes() {
		if ch == `\\` {
			result.write_string('\\\\')
		} else if ch == `\n` {
			result.write_string('\\n')
		} else if ch == `\r` {
			result.write_string('\\r')
		} else if ch == `\t` {
			result.write_string('\\t')
		} else if ch == `"` {
			result.write_string('\\"')
		} else if ch >= 0x20 && ch <= 0x7e {
			result.write_u8(ch)
		} else {
			result.write_string('\\x${ch:02x}')
		}
	}
	return result.str()
}

// SplitDirection values for new_split.
pub enum SplitDirection as u8 {
	right
	down
	left
	up
	auto_
}

// SplitFocusDirection values for goto_split.
pub enum SplitFocusDirection as u8 {
	previous
	next
	up
	left
	down
	right
}

// parse_split_focus_direction parses with backwards compatibility for "top"/"bottom".
pub fn parse_split_focus_direction(s string) !SplitFocusDirection {
	return match s {
		'previous' { .previous }
		'next' { .next }
		'up' { .up }
		'left' { .left }
		'down' { .down }
		'right' { .right }
		'top' { .up }
		'bottom' { .down }
		else { error('InvalidFormat') }
	}
}

pub enum GotoWindow as u8 {
	previous
	next
}

pub enum NavigateSearch as u8 {
	previous
	next
}

pub enum AdjustSelection as u8 {
	left
	right
	up
	down
	page_up
	page_down
	home
	end_
	beginning_of_line
	end_of_line
}

pub enum SplitResizeDirection as u8 {
	up
	down
	left
	right
}

pub enum CopyToClipboard as u8 {
	plain
	vt
	html
	mixed
}

pub enum WriteScreenAction as u8 {
	copy
	paste
	open
}

pub enum WriteScreenFormat as u8 {
	plain
	vt
	html
}

pub struct WriteScreen {
pub:
	action WriteScreenAction
	emit   WriteScreenFormat
}

pub fn WriteScreen.parse(param string) !WriteScreen {
	// If we don't have a `,`, default to the plain format. This is
	// also very important for backwards compatibility before Ghostty
	// 1.3 which didn't support output formats.
	idx := param.index_u8(`,`)
	if idx < 0 {
		return WriteScreen{
			action: parse_write_screen_action(param)!
			emit:   .plain
		}
	}
	return WriteScreen{
		action: parse_write_screen_action(param[..idx])!
		emit:   parse_write_screen_format(param[idx + 1..])!
	}
}

pub fn (self WriteScreen) format() string {
	return '${self.action},${self.emit}'
}

pub enum InspectorMode as u8 {
	toggle
	show
	hide
}

pub enum CloseTabMode as u8 {
	this
	other
	right
}

pub enum CrashThread as u8 {
	main_thread
	io
	render
}

// ActionScope indicates whether an action runs at app or surface level.
pub enum ActionScope as u8 {
	app
	surface
}

// scope returns the scope of an action.
pub fn (a Action) scope() ActionScope {
	return match a.tag() {
		.ignore, .unbind { .app }
		.open_config, .reload_config, .close_all_windows, .quit, .toggle_quick_terminal, .toggle_visibility, .check_for_updates, .show_gtk_inspector {
			.app
		}
		.new_window, .undo, .redo { .app }
		else { .surface }
	}
}

// scoped returns this action when it belongs to the requested scope, or none
// otherwise. Ghostty narrows the returned tagged union at comptime; V cannot
// construct that dependent type, so the translated boundary retains the
// canonical Action value after performing the same scope check.
pub fn (a Action) scoped(scope ActionScope) ?Action {
	if a.scope() != scope {
		return none
	}
	return a
}

// parse parses an action in the format of "key=value" where key is the
// action name and value is the action parameter. The parameter is optional
// depending on the action.
pub fn Action.parse(input_str string) !Action {
	// Split our action by colon. A colon may not exist for some
	// actions so it is optional. The part preceding the colon is the
	// action name.
	colon_idx := input_str.index_u8(`:`)
	action_name := if colon_idx >= 0 { input_str[..colon_idx] } else { input_str }

	// An action name is always required
	if action_name.len == 0 {
		return error('InvalidFormat')
	}

	tag := action_tag_by_name(action_name) or { return error('InvalidAction') }

	// If the field type is void we expect no value
	if void_value := void_action(tag) {
		if colon_idx >= 0 {
			return error('InvalidFormat')
		}
		return void_value
	}

	match tag {
		.csi, .esc, .text, .search, .activate_key_table, .activate_key_table_once {
			if colon_idx < 0 {
				return error('InvalidFormat')
			}
			return string_action(tag, input_str[colon_idx + 1..])
		}
		// Cursor keys can't be set currently
		.cursor_key {
			return error('InvalidAction')
		}
		else {}
	}

	// Get the parameter after the colon. The parameter can be optional
	// for action types that can have a "default" decl.
	if colon_idx < 0 {
		match tag {
			.copy_to_clipboard {
				return ActionCopyToClipboard{
					value: .mixed
				}
			}
			.new_split {
				return ActionNewSplit{
					value: .auto_
				}
			}
			.close_tab {
				return ActionCloseTab{
					value: .this
				}
			}
			else {
				return error('InvalidFormat')
			}
		}
	}

	param := input_str[colon_idx + 1..]
	match tag {
		.copy_to_clipboard {
			return ActionCopyToClipboard{
				value: parse_copy_to_clipboard(param)!
			}
		}
		.increase_font_size {
			return ActionIncreaseFontSize{
				value: parse_float(param)!
			}
		}
		.decrease_font_size {
			return ActionDecreaseFontSize{
				value: parse_float(param)!
			}
		}
		.set_font_size {
			return ActionSetFontSize{
				value: parse_float(param)!
			}
		}
		.navigate_search {
			return ActionNavigateSearch{
				value: parse_navigate_search(param)!
			}
		}
		.scroll_to_row {
			return ActionScrollToRow{
				value: uint(strconv_parse_usize(param)!)
			}
		}
		.scroll_page_fractional {
			return ActionScrollPageFractional{
				value: parse_float(param)!
			}
		}
		.scroll_page_lines {
			return ActionScrollPageLines{
				value: i16(strconv_parse_i16(param)!)
			}
		}
		.adjust_selection {
			return ActionAdjustSelection{
				value: parse_adjust_selection(param)!
			}
		}
		.jump_to_prompt {
			return ActionJumpToPrompt{
				value: i16(strconv_parse_i16(param)!)
			}
		}
		.write_scrollback_file {
			return ActionWriteScrollbackFile{
				value: WriteScreen.parse(param)!
			}
		}
		.write_screen_file {
			return ActionWriteScreenFile{
				value: WriteScreen.parse(param)!
			}
		}
		.write_selection_file {
			return ActionWriteSelectionFile{
				value: WriteScreen.parse(param)!
			}
		}
		.goto_tab {
			return ActionGotoTab{
				value: uint(strconv_parse_usize(param)!)
			}
		}
		.move_tab {
			return ActionMoveTab{
				value: int(strconv_parse_isize(param)!)
			}
		}
		.new_split {
			return ActionNewSplit{
				value: parse_split_direction(param)!
			}
		}
		.goto_split {
			return ActionGotoSplit{
				value: parse_split_focus_direction(param)!
			}
		}
		.goto_window {
			return ActionGotoWindow{
				value: parse_goto_window(param)!
			}
		}
		.resize_split {
			return ActionResizeSplit{
				value: parse_resize_split(param)!
			}
		}
		.inspector {
			return ActionInspector{
				value: parse_inspector_mode(param)!
			}
		}
		.close_tab {
			return ActionCloseTab{
				value: parse_close_tab_mode(param)!
			}
		}
		.crash {
			return ActionCrash{
				value: parse_crash_thread(param)!
			}
		}
		else {
			return error('InvalidAction')
		}
	}
}

// action_tag_by_name finds the union field with the given name, standing in
// for the source's `inline for` over the union's fields.
fn action_tag_by_name(name string) ?ActionTag {
	$for tag in ActionTag.values {
		if tag.name == name {
			return tag.value
		}
	}
	return none
}

// void_action returns the payload-free variant for tag, or none when the
// variant carries a value.
fn void_action(tag ActionTag) ?Action {
	match tag {
		.ignore {
			return ActionIgnore{}
		}
		.unbind {
			return ActionUnbind{}
		}
		.reset {
			return ActionReset{}
		}
		.paste_from_clipboard {
			return ActionPasteFromClipboard{}
		}
		.paste_from_selection {
			return ActionPasteFromSelection{}
		}
		.copy_url_to_clipboard {
			return ActionCopyUrlToClipboard{}
		}
		.copy_title_to_clipboard {
			return ActionCopyTitleToClipboard{}
		}
		.reset_font_size {
			return ActionResetFontSize{}
		}
		.search_selection {
			return ActionSearchSelection{}
		}
		.start_search {
			return ActionStartSearch{}
		}
		.end_search {
			return ActionEndSearch{}
		}
		.clear_screen {
			return ActionClearScreen{}
		}
		.select_all {
			return ActionSelectAll{}
		}
		.scroll_to_top {
			return ActionScrollToTop{}
		}
		.scroll_to_bottom {
			return ActionScrollToBottom{}
		}
		.scroll_to_selection {
			return ActionScrollToSelection{}
		}
		.scroll_page_up {
			return ActionScrollPageUp{}
		}
		.scroll_page_down {
			return ActionScrollPageDown{}
		}
		.new_window {
			return ActionNewWindow{}
		}
		.new_tab {
			return ActionNewTab{}
		}
		.previous_tab {
			return ActionPreviousTab{}
		}
		.next_tab {
			return ActionNextTab{}
		}
		.last_tab {
			return ActionLastTab{}
		}
		.toggle_tab_overview {
			return ActionToggleTabOverview{}
		}
		.prompt_surface_title {
			return ActionPromptSurfaceTitle{}
		}
		.prompt_tab_title {
			return ActionPromptTabTitle{}
		}
		.toggle_split_zoom {
			return ActionToggleSplitZoom{}
		}
		.toggle_readonly {
			return ActionToggleReadonly{}
		}
		.equalize_splits {
			return ActionEqualizeSplits{}
		}
		.reset_window_size {
			return ActionResetWindowSize{}
		}
		.show_gtk_inspector {
			return ActionShowGtkInspector{}
		}
		.show_on_screen_keyboard {
			return ActionShowOnScreenKeyboard{}
		}
		.open_config {
			return ActionOpenConfig{}
		}
		.reload_config {
			return ActionReloadConfig{}
		}
		.close_surface {
			return ActionCloseSurface{}
		}
		.close_window {
			return ActionCloseWindow{}
		}
		.close_all_windows {
			return ActionCloseAllWindows{}
		}
		.toggle_maximize {
			return ActionToggleMaximize{}
		}
		.toggle_fullscreen {
			return ActionToggleFullscreen{}
		}
		.toggle_window_decorations {
			return ActionToggleWindowDecorations{}
		}
		.toggle_window_float_on_top {
			return ActionToggleWindowFloatOnTop{}
		}
		.toggle_secure_input {
			return ActionToggleSecureInput{}
		}
		.toggle_mouse_reporting {
			return ActionToggleMouseReporting{}
		}
		.toggle_command_palette {
			return ActionToggleCommandPalette{}
		}
		.toggle_quick_terminal {
			return ActionToggleQuickTerminal{}
		}
		.toggle_visibility {
			return ActionToggleVisibility{}
		}
		.toggle_background_opacity {
			return ActionToggleBackgroundOpacity{}
		}
		.check_for_updates {
			return ActionCheckForUpdates{}
		}
		.undo {
			return ActionUndo{}
		}
		.redo {
			return ActionRedo{}
		}
		.end_key_sequence {
			return ActionEndKeySequence{}
		}
		.deactivate_key_table {
			return ActionDeactivateKeyTable{}
		}
		.deactivate_all_key_tables {
			return ActionDeactivateAllKeyTables{}
		}
		.quit {
			return ActionQuit{}
		}
		else {}
	}
	return none
}

// string_action builds the `[]const u8` variant named by tag.
fn string_action(tag ActionTag, value string) Action {
	match tag {
		.csi {
			return ActionCsi{
				value: value
			}
		}
		.esc {
			return ActionEsc{
				value: value
			}
		}
		.text {
			return ActionText{
				value: value
			}
		}
		.search {
			return ActionSearch{
				value: value
			}
		}
		.activate_key_table {
			return ActionActivateKeyTable{
				value: value
			}
		}
		.activate_key_table_once {
			return ActionActivateKeyTableOnce{
				value: value
			}
		}
		else {
			panic('string_action: ${tag} does not carry a string')
		}
	}
}

// --- Enum parsers ---

fn parse_split_direction(s string) !SplitDirection {
	return match s {
		'right' { .right }
		'down' { .down }
		'left' { .left }
		'up' { .up }
		'auto' { .auto_ }
		else { error('InvalidFormat') }
	}
}

fn parse_copy_to_clipboard(s string) !CopyToClipboard {
	return match s {
		'plain' { .plain }
		'vt' { .vt }
		'html' { .html }
		'mixed' { .mixed }
		else { error('InvalidFormat') }
	}
}

fn parse_navigate_search(s string) !NavigateSearch {
	return match s {
		'previous' { .previous }
		'next' { .next }
		else { error('InvalidFormat') }
	}
}

fn parse_adjust_selection(s string) !AdjustSelection {
	return match s {
		'left' { .left }
		'right' { .right }
		'up' { .up }
		'down' { .down }
		'page_up' { .page_up }
		'page_down' { .page_down }
		'home' { .home }
		'end' { .end_ }
		'beginning_of_line' { .beginning_of_line }
		'end_of_line' { .end_of_line }
		else { error('InvalidFormat') }
	}
}

fn parse_goto_window(s string) !GotoWindow {
	return match s {
		'previous' { .previous }
		'next' { .next }
		else { error('InvalidFormat') }
	}
}

fn parse_inspector_mode(s string) !InspectorMode {
	return match s {
		'toggle' { .toggle }
		'show' { .show }
		'hide' { .hide }
		else { error('InvalidFormat') }
	}
}

fn parse_close_tab_mode(s string) !CloseTabMode {
	return match s {
		'this' { .this }
		'other' { .other }
		'right' { .right }
		else { error('InvalidFormat') }
	}
}

fn parse_crash_thread(s string) !CrashThread {
	return match s {
		'main' { .main_thread }
		'io' { .io }
		'render' { .render }
		else { error('InvalidFormat') }
	}
}

fn parse_resize_split(s string) !SplitResizeParameter {
	comma_idx := s.index_u8(`,`)
	if comma_idx < 0 {
		return error('InvalidFormat')
	}
	dir_str := s[..comma_idx]
	amount_str := s[comma_idx + 1..]
	if amount_str.len == 0 {
		return error('InvalidFormat')
	}
	// If we have extra parameters it is an error
	if amount_str.index_u8(`,`) >= 0 {
		return error('InvalidFormat')
	}
	dir := match dir_str {
		'up' { SplitResizeDirection.up }
		'down' { SplitResizeDirection.down }
		'left' { SplitResizeDirection.left }
		'right' { SplitResizeDirection.right }
		else {
			return error('InvalidFormat')
		}
	}
	return SplitResizeParameter{
		direction: dir
		amount:    u16(parse_unsigned_decimal(amount_str, 65535)!)
	}
}

fn parse_write_screen_action(s string) !WriteScreenAction {
	return match s {
		'copy' { WriteScreenAction.copy }
		'paste' { WriteScreenAction.paste }
		'open' { WriteScreenAction.open }
		else { error('InvalidFormat') }
	}
}

fn parse_write_screen_format(s string) !WriteScreenFormat {
	return match s {
		'plain' { WriteScreenFormat.plain }
		'vt' { WriteScreenFormat.vt }
		'html' { WriteScreenFormat.html }
		else { error('InvalidFormat') }
	}
}

// --- String/number parsers ---

fn parse_float(s string) !f32 {
	return zig_fmt.parse_f32(s) or { return error('InvalidFormat') }
}

fn strconv_parse_i16(s string) !i64 {
	return zig_fmt.parse_int_signed(s, 16, 10) or { return error('InvalidFormat') }
}

fn strconv_parse_isize(s string) !i64 {
	// Ghostty supports only 64-bit application targets, where isize is i64.
	return zig_fmt.parse_int_signed(s, 64, 10) or { return error('InvalidFormat') }
}

fn strconv_parse_usize(s string) !u64 {
	// Ghostty supports only 64-bit application targets, where usize is u64.
	return zig_fmt.parse_int_unsigned(s, 64, 10) or { return error('InvalidFormat') }
}

fn parse_unsigned_decimal(s string, maximum u64) !u64 {
	return zig_fmt.parse_int_unsigned_max(s, maximum, 10) or { return error('InvalidFormat') }
}

// --- Parser ---

// ParserElem is a single element yielded by the binding parser: the
// source's `Parser.Elem` tagged union.
pub type ParserElem = ParserElemBinding | ParserElemChain | ParserElemLeader

// A leader trigger in a sequence.
pub struct ParserElemLeader {
pub:
	trigger Trigger
}

// The final trigger and action in a sequence.
pub struct ParserElemBinding {
pub:
	binding Binding
}

// A chained action `chain=[action]` that should be appended to the
// previous binding. Note that any action is parsed, including invalid
// actions for chains such as `unbind`. We expect downstream consumers to
// validate that the action is valid for chaining.
pub struct ParserElemChain {
pub:
	action Action
}

// Parser is the full binding parser. It yields elements to support
// multi-key sequences without allocation.
pub struct Parser {
pub mut:
	trigger_it SequenceIterator
	action     Action
	flags      Flags
	chain      bool
}

// SequenceIterator yields each trigger in a sequence of triggers.
// For example, "ctrl+a>ctrl+b" yields "ctrl+a" and then "ctrl+b".
pub struct SequenceIterator {
pub mut:
	input string
	i     int
}

// next returns the next trigger in the sequence.
// Returns none when done, or error on parse failure.
pub fn (mut self SequenceIterator) next() !Trigger {
	if self.done() {
		return error('done')
	}
	rem := self.input[self.i..]
	idx := rem.index_u8(`>`)
	part_end := if idx >= 0 { idx } else { rem.len }
	part := rem[..part_end]
	self.i += part_end + 1
	return Trigger.parse(part)!
}

// done returns true if there are no more triggers to parse.
pub fn (self &SequenceIterator) done() bool {
	return self.i > self.input.len
}

// Parser.init creates a new parser from a raw binding string like "ctrl+a=ignore".
pub fn Parser.init(raw_input string) !Parser {
	flags, start_idx := parse_flags(raw_input)!
	inp := raw_input[start_idx..]

	// Find the equal sign. Need to ignore equal signs that are part of the trigger.
	mut eql_idx := -1
	mut offset := 0
	for {
		rest := inp[offset..]
		oi := rest.index_u8(`=`)
		if oi < 0 {
			break
		}
		idx := offset + oi
		// Check for '=+' or '==' patterns (trigger contains =)
		if idx < inp.len - 1 && (inp[idx + 1] == `+` || inp[idx + 1] == `=`) {
			offset = idx + 1
			continue
		}
		// This looks like the real equal sign
		eql_idx = idx
		break
	}

	if eql_idx < 0 {
		return error('InvalidFormat')
	}

	// Detect chains. Chains must not have flags.
	is_chain := inp[..eql_idx] == 'chain'
	if is_chain && start_idx > 0 {
		return error('InvalidFormat')
	}

	trigger_input := if is_chain { 'a' } else { inp[..eql_idx] }
	action := Action.parse(inp[eql_idx + 1..])!

	return Parser{
		trigger_it: SequenceIterator{
			input: trigger_input
		}
		action: action
		flags: flags
		chain: is_chain
	}
}

// parse_flags extracts prefix flags like "unconsumed:", "global:", "all:", "performable:".
fn parse_flags(raw_input string) !(Flags, int) {
	mut flags := Flags{}
	mut start_idx := 0
	mut inp := raw_input

	for {
		idx := inp.index_u8(`:`)
		if idx < 0 {
			break
		}
		prefix := inp[..idx]

		if prefix == 'all' {
			if flags.all() {
				return error('InvalidFormat')
			}
			flags.set_all(true)
		} else if prefix == 'global' {
			if flags.global() {
				return error('InvalidFormat')
			}
			flags.set_global(true)
		} else if prefix == 'unconsumed' {
			if !flags.consumed() {
				return error('InvalidFormat')
			}
			flags.set_consumed(false)
		} else if prefix == 'performable' {
			if flags.performable() {
				return error('InvalidFormat')
			}
			flags.set_performable(true)
		} else {
			// Unknown prefix - let trigger-specific parsing handle it
			break
		}

		start_idx += idx + 1
		inp = inp[idx + 1..]
	}

	return flags, start_idx
}

// next yields the next parser element.
// Returns error('done') when no more elements.
pub fn (mut self Parser) next() !ParserElem {
	trigger := self.trigger_it.next() or {
		if err.msg() == 'done' {
			return error('done')
		}
		return err
	}

	if !self.trigger_it.done() {
		// Global/all bindings can't be sequences
		if self.flags.global() || self.flags.all() {
			return error('InvalidFormat')
		}
		return ParserElemLeader{
			trigger: trigger
		}
	}

	// If we're a chain then return it as-is.
	if self.chain {
		return ParserElemChain{
			action: self.action
		}
	}

	// Out of triggers, yield the final action.
	return ParserElemBinding{
		binding: Binding{
			trigger: trigger
			action: self.action
			flags: self.flags
		}
	}
}

// reset resets the parser to the beginning.
pub fn (mut self Parser) reset() {
	self.trigger_it.i = 0
}

// parse_single parses a single, non-sequenced binding string.
// Convenience function primarily for tests.
pub fn parse_single(raw_input string) !Binding {
	mut p := Parser.init(raw_input)!
	elem := p.next() or {
		if err.msg() == 'done' {
			return error('InvalidFormat')
		}
		return err
	}
	return match elem {
		ParserElemLeader { error('UnexpectedSequence') }
		ParserElemBinding { elem.binding }
		ParserElemChain { error('UnexpectedChain') }
	}
}

// less_than returns true if lhs should be sorted before rhs.
pub fn less_than(lhs Binding, rhs Binding) bool {
	lhs_count := mod_count(lhs.trigger.mods)
	rhs_count := mod_count(rhs.trigger.mods)

	if lhs_count != rhs_count {
		return lhs_count > rhs_count
	}

	lhs_int := mods_int(lhs.trigger.mods)
	rhs_int := mods_int(rhs.trigger.mods)
	if lhs_int != rhs_int {
		return lhs_int > rhs_int
	}

	lhs_key := trigger_key_int(lhs.trigger.key)
	rhs_key := trigger_key_int(rhs.trigger.key)
	return lhs_key < rhs_key
}

fn mod_count(m Mods) int {
	mut count := 0
	if m.super_() {
		count++
	}
	if m.ctrl() {
		count++
	}
	if m.shift() {
		count++
	}
	if m.alt() {
		count++
	}
	return count
}

fn mods_int(m Mods) int {
	return int(m.int())
}

fn trigger_key_int(k TriggerKey) int {
	return match k {
		TriggerKeyPhysical { int(k.key) }
		TriggerKeyUnicode { int(k.codepoint) }
		TriggerKeyCatchAll { -1 }
	}
}

// --- Set ---

// SetValue is the entry type for the forward mapping of trigger to action:
// the source's `Set.Value` tagged union.
pub type SetValue = Leader | Leaf | LeafChained

// This key is a leader key in a sequence. You must follow the given
// set to find the next key in the sequence.
pub struct Leader {
pub:
	set &Set = unsafe { nil }
}

// Leaf node of a set is an action to trigger. This is a "leaf" compared
// to the inner nodes which are "leaders" for sequences.
pub struct Leaf {
pub:
	action Action
	flags  Flags
}

pub fn (self Leaf) generic() GenericLeaf {
	return GenericLeaf{
		flags:   self.flags
		actions: GenericLeafActions(GenericLeafActionsSingle{
			actions: [self.action]!
		})
	}
}

// Leaf node of a set that triggers multiple actions in sequence.
pub struct LeafChained {
pub:
	actions []Action
	flags   Flags
}

pub fn (self LeafChained) generic() GenericLeaf {
	return GenericLeaf{
		flags:   self.flags
		actions: GenericLeafActions(GenericLeafActionsMany{
			actions: self.actions
		})
	}
}

pub struct GenericLeafActionsSingle {
pub:
	actions [1]Action
}

pub struct GenericLeafActionsMany {
pub:
	actions []Action
}

// GenericLeafActions is the source's single-fixed-array or many-slice union.
pub type GenericLeafActions = GenericLeafActionsSingle | GenericLeafActionsMany

// GenericLeaf is a generic leaf node that can be used to unify the
// handling of leaf and leaf_chained.
pub struct GenericLeaf {
pub:
	flags   Flags
	actions GenericLeafActions
}

// generic returns the common leaf view of a leaf or chained leaf, or none
// for a leader: the source's `inline .leaf, .leaf_chained => |leaf|
// leaf.generic()` switch arm.
pub fn (value SetValue) generic() ?GenericLeaf {
	return match value {
		Leader { none }
		Leaf { value.generic() }
		LeafChained { value.generic() }
	}
}

// actions_slice returns every action represented by this leaf.
pub fn (leaf &GenericLeaf) actions_slice() []Action {
	return leaf.actions.slice()
}

fn (actions &GenericLeafActions) slice() []Action {
	return match actions {
		GenericLeafActionsSingle { actions.actions[..] }
		GenericLeafActionsMany { actions.actions }
	}
}

// ChainParent is information about a chain parent entry, including which set
// it belongs to. This is needed because reverse mappings are only maintained
// in the root set, but the chain parent entry may be in a nested set (for
// leader key sequences).
//
// The Zig version stores raw `key_ptr`/`value_ptr` pointers into the hash map
// plus the owning `*Set`. Our V forward mapping is an array rather than a hash
// map, so instead of raw pointers we store the owning set pointer and the
// index of the entry within that set's `bindings` array. Chaining always
// happens directly after a put (and puts never reorder existing entries), so
// this index stays valid for the duration a chain parent is meaningful.
pub struct ChainParent {
pub mut:
	set   &Set = unsafe { nil }
	index int
}

// Set is a structure that contains a set of bindings and focuses on fast lookup.
pub struct Set {
pub mut:
	// Forward mapping: trigger -> value
	bindings []SetEntry
	// Reverse mapping: action -> trigger (most recent)
	reverse []ReverseEntry
	// The chain parent is the information necessary to attach a chained
	// action to the proper location in our mapping. It tracks both the
	// entry in the mapping and the set it belongs to, which is needed
	// to properly update reverse mappings when converting a leaf to a
	// chained action. None when chaining is not currently valid.
	chain_parent ?ChainParent
}

pub struct SetEntry {
pub mut:
	trigger Trigger
	value   SetValue
}

pub struct ReverseEntry {
pub mut:
	action  Action
	trigger Trigger
}

// format_entries serializes every binding into the value side of a Ghostty
// `keybind = ...` config entry. Leaders are recursively flattened into `>`
// sequences and chained actions become subsequent `chain=...` entries.
pub fn (s &Set) format_entries() []string {
	mut result := []string{}
	for entry in s.bindings {
		format_set_value(entry.value, entry.trigger.format(), mut result)
	}
	return result
}

fn format_set_value(value SetValue, prefix string, mut result []string) {
	match value {
		Leader {
			for entry in value.set.bindings {
				format_set_value(entry.value, '${prefix}>${entry.trigger.format()}', mut result)
			}
		}
		Leaf {
			result << '${prefix}=${value.action.format()}'
		}
		LeafChained {
			for i, action in value.actions {
				if i == 0 {
					result << '${prefix}=${action.format()}'
				} else {
					result << 'chain=${action.format()}'
				}
			}
		}
	}
}

// get returns a binding entry for a given trigger.
pub fn (s &Set) get(t Trigger) ?&SetEntry {
	for i in 0 .. s.bindings.len {
		if s.bindings[i].trigger.folded_equal(t) {
			return unsafe { &s.bindings[i] }
		}
	}
	return none
}

// get_trigger returns the trigger for a given action from the reverse map.
pub fn (s &Set) get_trigger(a Action) ?Trigger {
	for entry in s.reverse {
		if entry.action.equal(a) {
			return entry.trigger
		}
	}
	return none
}

// clone deep-clones the set. Faithful to Zig `clone`.
//
// Leaders are recursively deep-cloned into fresh Set allocations so that the
// clone is fully independent of the original. Leaf and leaf_chained actions
// hold V strings (GC-managed, immutable) so copying the value structs is a
// sufficient deep copy; the arrays are duplicated so mutations don't alias.
// The cloned set has no chain_parent (chaining state is not carried over).
pub fn (s &Set) clone() Set {
	mut result := Set{
		bindings: []SetEntry{cap: s.bindings.len}
		reverse: s.reverse.clone()
	}

	for entry in s.bindings {
		mut value := entry.value
		match value {
			Leaf {
				// Leaves could have data to clone (i.e. text actions contain
				// allocated strings). V strings are immutable and GC-managed,
				// so a fresh leaf with the same action is a sufficient copy.
				value = Leaf{
					action: value.action
					flags:  value.flags
				}
			}
			LeafChained {
				// Duplicate the actions slice so the clone is independent.
				value = LeafChained{
					actions: value.actions.clone()
					flags:   value.flags
				}
			}
			Leader {
				// Must be deep cloned into a fresh allocation.
				mut child := value.set.clone()
				value = Leader{
					set: &child
				}
			}
		}
		result.bindings << SetEntry{
			trigger: entry.trigger
			value: value
		}
	}

	return result
}

// put adds a binding to the set. If the binding already exists then it is overwritten.
pub fn (mut s Set) put(t Trigger, action Action) {
	s.put_flags(t, action, Flags{})
}

// put_flags adds a binding to the set with explicit flags.
//
// This also records the chain_parent so that a subsequent chained action
// (chain=...) can be attached to the entry just added/updated. Faithful to
// Zig `putFlags`.
pub fn (mut s Set) put_flags(t Trigger, action Action, flags Flags) {
	// unbind should never go into the set, it should be handled prior.
	// (assert(action != .unbind) in Zig.)

	// This is true if we're going to track this entry as a reverse mapping.
	// There are certain scenarios we don't. See the reverse map docs.
	track_reverse := !flags.performable()

	// Check for existing entry
	for i in 0 .. s.bindings.len {
		if s.bindings[i].trigger.folded_equal(t) {
			old := s.bindings[i].value
			// If we have an existing binding for this trigger, we have to
			// clean up the old value. For a leaf we update the reverse
			// mapping; chained leaves aren't in the reverse mapping.
			if old is Leaf && track_reverse {
				t_hash := t.hash()
				for ri in 0 .. s.reverse.len {
					if s.reverse[ri].trigger.hash() == t_hash {
						s.reverse.delete(ri)
						break
					}
				}
			}
			s.bindings[i].value = Leaf{
				action: action
				flags:  flags
			}
			if track_reverse {
				s.set_reverse(action, t)
			}
			// Record the chain parent pointing to the entry we just updated.
			s.chain_parent = ChainParent{
				set: unsafe { &s }
				index: i
			}
			return
		}
	}

	// New entry
	s.bindings << SetEntry{
		trigger: t
		value: Leaf{
			action: action
			flags:  flags
		}
	}
	if track_reverse {
		s.set_reverse(action, t)
	}
	// Record the chain parent pointing to the entry we just added.
	s.chain_parent = ChainParent{
		set: unsafe { &s }
		index: s.bindings.len - 1
	}
}

// append_chain appends a chained action to the prior set action.
//
// It is an error if there is no valid prior chain parent. Faithful to Zig
// `appendChain`.
pub fn (mut s Set) append_chain(action Action) ! {
	// Unbind is not a valid chain action; callers must check this.
	// (assert(action != .unbind) in Zig.)

	parent := s.chain_parent or { return error('NoChainParent') }
	mut pset := parent.set
	idx := parent.index
	pval := pset.bindings[idx].value

	match pval {
		Leader {
			// Leader can never be a chain parent.
			return error('NoChainParent')
		}
		LeafChained {
			// If it is already a chained action, we just append the action.
			mut actions := pval.actions.clone()
			actions << action
			pset.bindings[idx].value = LeafChained{
				actions: actions
				flags:   pval.flags
			}
		}
		Leaf {
			// If it is a leaf, we need to convert it to a leaf_chained. We
			// also need to remove any prior reverse mappings for this action
			// since chained actions are not part of the reverse mapping.
			prior_action := pval.action
			prior_trigger := pset.bindings[idx].trigger

			// Convert to leaf_chained first, before fixing up the reverse
			// mapping. This is important because fixup_reverse_for_action
			// searches for other bindings with the same action, and we don't
			// want to find this entry (which is now chained).
			pset.bindings[idx].value = LeafChained{
				actions: [prior_action, action]
				flags:   pval.flags
			}

			// Clean up our reverse mapping. Chained actions are not part of
			// the reverse mapping, so we need to fix up the reverse map
			// (possibly restoring another trigger for the same action).
			pset.fixup_reverse_for_action(prior_action, prior_trigger)
		}
	}
}

fn (mut s Set) set_reverse(action Action, t Trigger) {
	for i in 0 .. s.reverse.len {
		if s.reverse[i].action.equal(action) {
			s.reverse[i].trigger = t
			return
		}
	}
	s.reverse << ReverseEntry{
		action: action
		trigger: t
	}
}

// remove removes a binding for a given trigger.
//
// Removal always resets our chain parent. We could make this finer grained
// but the way it is documented is that chaining must happen directly after
// sets so this works. Faithful to Zig `removeExact`.
pub fn (mut s Set) remove(t Trigger) {
	s.chain_parent = none
	for i in 0 .. s.bindings.len {
		if s.bindings[i].trigger.folded_equal(t) {
			entry := s.bindings[i].value
			s.bindings.delete(i)
			match entry {
				Leaf {
					// For an action we need to fix up the reverse mapping.
					s.fixup_reverse_for_action(entry.action, t)
				}
				LeafChained {
					// Chained leaves are never in our reverse mapping so no
					// cleanup is required.
				}
				Leader {
					// For a leader removal, the child set is owned by the GC
					// so no explicit deallocation is needed. Leaders are never
					// part of reverse maps so no other accounting is needed.
				}
			}
			return
		}
	}
}

// fixup_reverse_for_action updates the reverse map after removing an action.
fn (mut s Set) fixup_reverse_for_action(action Action, old Trigger) {
	mut found_idx := -1
	for ri in 0 .. s.reverse.len {
		if s.reverse[ri].action.equal(action) {
			found_idx = ri
			break
		}
	}
	if found_idx < 0 {
		return
	}

	// If our value is not the same as the old trigger, ignore it
	if !s.reverse[found_idx].trigger.equal(old) {
		return
	}

	// Try to find another trigger that maps to the same action
	action_hash := action.hash()
	for entry in s.bindings {
		value := entry.value
		if value is Leaf && value.action.hash() == action_hash {
			s.reverse[found_idx].trigger = entry.trigger
			return
		}
	}

	// No other trigger, remove the reverse mapping
	s.reverse.delete(found_idx)
}

// parse_and_put parses a user input binding and adds it to the set. This
// handles the "unbind" case, ensures consumed/unconsumed fields are set
// correctly, handles sequences and chains, etc. Faithful to Zig `parseAndPut`.
pub fn (mut s Set) parse_and_put(input_str string) ! {
	// To make cleanup easier, we ensure that the full sequence is valid
	// before making any set modifications.
	mut it := Parser.init(input_str)!
	for {
		_ = it.next() or {
			if err.msg() == 'done' {
				break
			}
			return err
		}
	}
	it.reset()

	// We use recursion so that we can utilize the stack as our state.
	//
	// The return convention (matching Zig's `?*Set`):
	//   - some(set): a binding was added; `set` recorded its chain parent.
	//   - none:      nothing was added (e.g. an unbind that left siblings).
	//   - error('SequenceUnbind'): unbound all the way up (still a success).
	updated := s.parse_and_put_recurse(mut s, mut it) or {
		match err.msg() {
			// If this gets sent up to the root then we've unbound all the
			// way up and this put was a success. We clear the chain parent
			// since chaining is no longer valid until a valid binding.
			'SequenceUnbind' {
				s.chain_parent = none
				return
			}

			// If our parser input was too short then the format is invalid.
			'UnexpectedEndOfInput' {
				return error('InvalidFormat')
			}

			// If we had a chain without a parent then the format is wrong.
			'NoChainParent' {
				return error('InvalidFormat')
			}

			// If we had an invalid action for a chain (e.g. unbind).
			'InvalidChainAction' {
				return error('InvalidFormat')
			}
			else {
				return err
			}
		}
	}

	// If we have an updated set (a binding was added) then we store it for
	// our chain parent. If we didn't update a set then we clear our chain
	// parent since chaining is no longer valid until a valid binding.
	if !isnil(updated.set) {
		// A binding was added. Store the chain parent on the root so a
		// following chain= can attach to it. Faithful to:
		//   if (updated_set != self) self.chain_parent = updated_set.chain_parent;
		if updated.set != unsafe { &s } {
			s.chain_parent = updated.set.chain_parent
		}
	} else {
		s.chain_parent = none
	}
}

// RecurseResult carries the outcome of parse_and_put_recurse. It models Zig's
// `?*Set` return: a non-nil `set` means a binding was added and that set
// recorded its chain parent; a nil `set` means nothing was added. The
// SequenceUnbind case is signalled via an error rather than this struct.
struct RecurseResult {
mut:
	set &Set = unsafe { nil }
}

// parse_and_put_recurse returns the set that was ultimately updated if a
// binding was added (non-nil set), or a nil set if nothing was added. Unbind
// that unwinds the stack raises 'SequenceUnbind'. Faithful to Zig
// `parseAndPutRecurse` which takes the root and current set and returns
// `?*Set`.
fn (mut s Set) parse_and_put_recurse(mut root Set, mut it Parser) !RecurseResult {
	elem := it.next() or {
		if err.msg() == 'done' {
			return error('UnexpectedEndOfInput')
		}
		return err
	}

	match elem {
		ParserElemLeader {
			t := elem.trigger
			// If we have a leader, we need to upsert a set for it.
			for i in 0 .. s.bindings.len {
				if s.bindings[i].trigger.folded_equal(t) {
					existing := s.bindings[i].value
					if existing is Leader {
						// We have an existing leader for this key already so
						// recurse into this set.
						mut inner := existing.set
						return root.parse_and_put_recurse2(mut inner, mut it) or {
							if err.msg() == 'SequenceUnbind' {
								// Our child put unbound. If our set is empty we
								// need to remove it and continue up. Otherwise
								// we're done (nothing added at this level).
								if inner.bindings.len == 0 {
									s.remove(t)
									return error('SequenceUnbind')
								}
								return RecurseResult{}
							}
							return err
						}
					}
					// Remove the existing action. Fall through as if we don't
					// have a leader.
					s.remove(t)
					break
				}
			}

			// Create our new set for this leader and insert the leader entry.
			mut next_set := &Set{}
			s.bindings << SetEntry{
				trigger: t
				value: Leader{
					set: next_set
				}
			}

			// Recurse
			return root.parse_and_put_recurse2(mut next_set, mut it) or {
				if err.msg() == 'SequenceUnbind' {
					// If our action was to unbind, we restore the old entry.
					// Here the leader was freshly created and empty, so we
					// just remove it and propagate the unbind up.
					s.remove(t)
					return error('SequenceUnbind')
				}
				return err
			}
		}
		ParserElemBinding {
			b := elem.binding
			if b.action is ActionUnbind {
				s.remove(b.trigger)
				return error('SequenceUnbind')
			}
			s.put_flags(b.trigger, b.action, b.flags)
			return RecurseResult{
				set: unsafe { &s }
			}
		}
		ParserElemChain {
			// Chains can only happen on the root.
			action := elem.action
			// Unbind is not valid for chains.
			if action is ActionUnbind {
				return error('InvalidChainAction')
			}
			s.append_chain(action)!
			return RecurseResult{
				set: unsafe { &s }
			}
		}
	}
	// match is exhaustive; unreachable.
	return error('InvalidFormat')
}

// parse_and_put_recurse2 is the V-friendly indirection used when recursing
// into a nested leader set. It exists because the recursion operates on a
// different `set` (`inner`/`next_set`) than the receiver while still passing
// the same `root`. It simply forwards to parse_and_put_recurse on the child.
fn (mut root Set) parse_and_put_recurse2(mut child Set, mut it Parser) !RecurseResult {
	return child.parse_and_put_recurse(mut root, mut it)
}

// get_event returns an entry for the given key event.
// It attempts to find a binding using multiple parts of the event:
//   1. Physical key (event.key)
//   2. UTF-8 text as unicode codepoint
//   3. Unshifted codepoint
//   4. catch_all with mods, then without mods
pub fn (s &Set) get_event(event KeyEvent) ?&SetEntry {
	mut trigger := Trigger{
		mods: event.mods.binding()
		key: TriggerKeyPhysical{ key: event.key }
	}
	if v := s.get(trigger) {
		return v
	}

	// If our UTF-8 text is exactly one codepoint, try to match that.
	if event.utf8.len > 0 {
		runes := event.utf8.runes()
		if runes.len == 1 {
			trigger = Trigger{
				...trigger
				key: TriggerKeyUnicode{ codepoint: u32(runes[0]) }
			}
			if v := s.get(trigger) {
				return v
			}
		}
	}

	// Fallback to the unshifted codepoint
	if event.unshifted_codepoint > 0 {
		trigger = Trigger{
			...trigger
			key: TriggerKeyUnicode{ codepoint: event.unshifted_codepoint }
		}
		if v := s.get(trigger) {
			return v
		}
	}

	// Fallback to catch_all with modifiers, then without
	trigger = Trigger{
		...trigger
		key: TriggerKeyCatchAll{}
	}
	if v := s.get(trigger) {
		return v
	}
	if !trigger.mods.empty() {
		trigger = Trigger{
			key: TriggerKeyCatchAll{}
		}
		if v := s.get(trigger) {
			return v
		}
	}

	return none
}
