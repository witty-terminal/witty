module apprt

// action.v - Action types for the apprt module.
// Translated from ghostty/src/apprt/action.zig

import terminal
import renderer
import configpkg
import input
import osc
import openurl

// Target is the target for an action. This is generally the thing that had
// focus while the action was made but the concept of "focus" is not guaranteed
// since actions can also be triggered by timers, scripts, etc.
pub type Target = AppTarget | SurfaceTarget

pub struct AppTarget {}

pub struct SurfaceTarget {
pub:
	surface voidptr
}

// ActionKey identifies the type of action. The order matters because it maps
// directly to the libwitty C enum. For ABI compatibility, new actions should
// be added to the end.
// Sync with: ghostty_action_tag_e
pub enum ActionKey as i32 {
	// Quit the application.
	quit
	// Open a new window. The target determines whether properties such
	// as font size should be inherited.
	new_window
	// Open a new tab. If the target is a surface it should be opened in
	// the same window as the surface. If the target is the app then
	// the tab should be opened in a new window.
	new_tab
	// Closes the tab belonging to the currently focused split, or all other
	// tabs, depending on the mode.
	close_tab
	// Create a new split. The value determines the location of the split
	// relative to the target.
	new_split
	// Close all open windows.
	close_all_windows
	// Toggle maximized window state.
	toggle_maximize
	// Toggle fullscreen mode.
	toggle_fullscreen
	// Toggle tab overview.
	toggle_tab_overview
	// Toggle whether window directions are shown.
	toggle_window_decorations
	// Toggle the quick terminal in or out.
	toggle_quick_terminal
	// Toggle the command palette. This currently only works on macOS.
	toggle_command_palette
	// Toggle the visibility of all Ghostty terminal windows.
	toggle_visibility
	// Toggle the window background opacity.
	toggle_background_opacity
	// Moves a tab by a relative offset.
	move_tab
	// Jump to a specific tab. Must handle the scenario that the tab
	// value is invalid.
	goto_tab
	// Jump to a specific split.
	goto_split
	// Jump to next/previous window.
	goto_window
	// Resize the split in the given direction.
	resize_split
	// Equalize all the splits in the target window.
	equalize_splits
	// Toggle whether a split is zoomed or not.
	toggle_split_zoom
	// Present the target terminal whether its a tab, split, or window.
	present_terminal
	// Sets a size limit (in pixels) for the target terminal.
	size_limit
	// Resets the window size to the default size.
	reset_window_size
	// Specifies the initial size of the target terminal.
	initial_size
	// The cell size has changed to the given dimensions in pixels.
	cell_size
	// The scrollbar is updating.
	scrollbar
	// The target should be re-rendered.
	render
	// Control whether the inspector is shown or hidden.
	inspector
	// Show the GTK inspector.
	show_gtk_inspector
	// The inspector for the given target has changes and should be
	// rendered at the next opportunity.
	render_inspector
	// Show a desktop notification.
	desktop_notification
	// Set the title of the target to the requested value.
	set_title
	// Set the title of the target to a prompted value.
	prompt_title
	// The current working directory has changed for the target terminal.
	pwd
	// Set the mouse cursor shape.
	mouse_shape
	// Set whether the mouse cursor is visible or not.
	mouse_visibility
	// Called when the mouse is over or recently left a link.
	mouse_over_link
	// The health of the renderer has changed.
	renderer_health
	// Open the Ghostty configuration.
	open_config
	// Called when there are no more surfaces and the app should quit
	// after the configured delay.
	quit_timer
	// Set the window floating state.
	float_window
	// Set the secure input functionality on or off.
	secure_input
	// A sequenced key binding has started, continued, or stopped.
	key_sequence
	// A key table has been activated or deactivated.
	key_table
	// A terminal color was changed programmatically through things
	// such as OSC 10/11.
	color_change
	// A request to reload the configuration.
	reload_config
	// The configuration has changed.
	config_change
	// Closes the currently focused window.
	close_window
	// Called when the bell character is seen.
	ring_bell
	// Undo the last action.
	undo
	// Redo the last undone action.
	redo
	// Check for updates.
	check_for_updates
	// Open a URL using the native OS mechanisms.
	open_url
	// Show a native GUI notification that the child process has exited.
	show_child_exited
	// Show a native GUI notification about the progress of some TUI operation.
	progress_report
	// Show the on-screen keyboard.
	show_on_screen_keyboard
	// A command has finished.
	command_finished
	// Start the search overlay with an optional initial needle.
	start_search
	// End the search overlay, clearing the search state and hiding it.
	end_search
	// The total number of matches found by the search.
	search_total
	// The currently selected search match index (1-based).
	search_selected
	// The readonly state of the surface has changed.
	readonly
}

// ActionValue holds the data for an Action. Only the field matching
// the action's key is meaningful. Fields with no associated data
// (void payloads) don't have entries here.
// The value of an action whose union field is `void`.
pub struct ActionVoid {}

// The value for an action: the payload type of the matching Action union
// field. `ActionVoid` stands in for `void`.
pub type ActionValue = ActionVoid
	| CellSize
	| ChildExited
	| CloseTabMode
	| ColorChange
	| CommandFinished
	| ConfigChange
	| DesktopNotificationValue
	| FloatWindow
	| Fullscreen
	| GotoSplit
	| GotoTab
	| GotoWindow
	| InitialSize
	| InspectorAction
	| KeySequence
	| KeyTable
	| MouseOverLink
	| MouseVisibility
	| MoveTab
	| OpenUrl
	| PromptTitle
	| PwdValue
	| QuitTimer
	| Readonly
	| ReloadConfig
	| ResizeSplit
	| SearchSelected
	| SearchTotal
	| SecureInput
	| SetTitle
	| SizeLimit
	| SplitDirection
	| StartSearch
	| osc.ProgressReport
	| renderer.Health
	| terminal.MouseShape
	| terminal.Scrollbar

// SplitDirection is the direction of a new split.
// This is made extern (c_int) to make interop easier with our embedded
// runtime. The small size cost doesn't make a difference in our union.
pub enum SplitDirection as i32 {
	right
	down
	left
	up
}

// GotoSplit is the direction to navigate to a split.
// This is made extern (c_int) to make interop easier with our embedded
// runtime. The small size cost doesn't make a difference in our union.
pub enum GotoSplit as i32 {
	previous
	next
	up
	left
	down
	right
}

// GotoWindow is the direction to navigate windows.
// This is made extern (c_int) to make interop easier with our embedded
// runtime. The small size cost doesn't make a difference in our union.
pub enum GotoWindow as i32 {
	previous
	next
}

// ResizeSplit holds the amount and direction to resize a split by.
pub struct ResizeSplit {
pub:
	amount    u16
	direction ResizeSplitDirection
}

// ResizeSplitDirection is the direction to resize a split.
pub enum ResizeSplitDirection as i32 {
	up
	down
	left
	right
}

// MoveTab holds the relative offset to move a tab by.
pub struct MoveTab {
pub:
	amount int
}

// GotoTab is the tab to jump to. Positive values represent the index
// (zero-based) of the tab to jump to. Negative values are special values.
pub enum GotoTab as i32 {
	previous = -1
	next     = -2
	last     = -3
}

// Fullscreen is the fullscreen mode to toggle to if we're moving to fullscreen.
pub enum Fullscreen as i32 {
	native
	// macOS has a non-native fullscreen mode that is more like a maximized
	// window. This is much faster to enter and exit than the native mode.
	macos_non_native
	macos_non_native_visible_menu
	macos_non_native_padded_notch
}

// FloatWindow controls the window floating state. A floating window is one
// that is always on top of other windows even when not focused.
pub enum FloatWindow as i32 {
	on
	off
	toggle
}

// SecureInput controls whether secure input is on or off.
// "Secure input" means that the user is currently at some sort of prompt
// where they may be entering a password or other sensitive information.
pub enum SecureInput as i32 {
	on
	off
	toggle
}

// InspectorAction controls whether the inspector is shown or hidden.
pub enum InspectorAction as i32 {
	toggle
	show
	hide
}

// QuitTimer controls the quit timer behavior.
pub enum QuitTimer as i32 {
	start
	stop
}

// Readonly controls the readonly state.
pub enum Readonly as i32 {
	off
	on
}

// MouseVisibility controls whether the mouse cursor is visible or not.
pub enum MouseVisibility as i32 {
	visible
	hidden
}

// PromptTitle specifies whether to prompt for the surface title or tab title.
pub enum PromptTitle as i32 {
	surface
	tab
}

// MouseOverLink contains the URL of the link the mouse is over.
pub struct MouseOverLink {
pub:
	url string
}

// SizeLimit specifies pixel size limits for the target terminal.
pub struct SizeLimit {
pub:
	min_width  u32
	min_height u32
	max_width  u32
	max_height u32
}

// InitialSize specifies the initial dimensions in pixels.
pub struct InitialSize {
pub:
	width  u32
	height u32
}

// CellSize specifies the cell dimensions in pixels.
pub struct CellSize {
pub:
	width  u32
	height u32
}

// SetTitle sets the title of the target to the requested value.
pub struct SetTitle {
pub:
	title string
}

// format matches Ghostty's custom formatter for title actions.
pub fn (value SetTitle) format() string {
	return 'SetTitle{ ${value.title} }'
}

// PwdValue holds the current working directory path.
pub struct PwdValue {
pub:
	pwd string
}

// format matches Ghostty's custom formatter for working-directory actions.
pub fn (value PwdValue) format() string {
	return 'Pwd{ ${value.pwd} }'
}

// DesktopNotificationValue holds the desktop notification to show.
pub struct DesktopNotificationValue {
pub:
	title string
	body  string
}

// format matches Ghostty's custom formatter for notification actions.
pub fn (value DesktopNotificationValue) format() string {
	return 'DesktopNotification{ title: ${value.title}, body: ${value.body} }'
}

// The end of a key sequence.
pub struct KeySequenceEnd {}

// A sequenced key binding has continued with a trigger or ended.
pub type KeySequence = KeySequenceEnd | input.Trigger

// Activate the named key table.
pub struct KeyTableActivate {
pub:
	name string
}

// Deactivate the most recently activated key table.
pub struct KeyTableDeactivate {}

// Deactivate all key tables.
pub struct KeyTableDeactivateAll {}

// A key table has been activated or deactivated.
pub type KeyTable = KeyTableActivate | KeyTableDeactivate | KeyTableDeactivateAll

// The C tag of the active key table variant.
pub fn (self KeyTable) tag() KeyTableTag {
	return match self {
		KeyTableActivate { .activate }
		KeyTableDeactivate { .deactivate }
		KeyTableDeactivateAll { .deactivate_all }
	}
}

// KeyTableTag identifies the key table operation.
// Sync with: ghostty_action_key_table_tag_e
pub enum KeyTableTag as i32 {
	activate
	deactivate
	deactivate_all
}

// ColorChange holds a programmatic terminal color change.
pub struct ColorChange {
pub:
	kind ColorKind
	r    u8
	g    u8
	b    u8
}

// ColorKind identifies the color being changed.
// Negative numbers indicate some named kind, 0+ values indicate a palette index.
pub enum ColorKind as i32 {
	foreground = -1
	background = -2
	cursor     = -3
}

// ReloadConfig controls whether a configuration reload is soft or full.
pub struct ReloadConfig {
pub:
	// A soft reload means that the configuration doesn't need to be
	// read off disk, but libwitty needs the full config again so call
	// updateConfig with it.
	soft bool
}

// ConfigChange holds a pointer to the new configuration. The pointer is only
// valid for the duration of the action and should not be stored.
pub struct ConfigChange {
pub:
	config &configpkg.Config = unsafe { nil }
}

// OpenUrl holds a URL to open.
pub struct OpenUrl {
pub:
	// The type of data that the URL refers to.
	kind OpenUrlKind
	// The URL.
	url string
}

// OpenUrlKind identifies the type of the data at the URL.
// Sync with: ghostty_action_open_url_kind_e
pub type OpenUrlKind = openurl.Kind

// CloseTabMode controls which tab(s) to close.
// Sync with ghostty_action_close_tab_mode_e in witty.h
pub enum CloseTabMode as i32 {
	// Close the current tab.
	this
	// Close all other tabs.
	other
	// Close all tabs to the right of the current tab.
	right
}

// CommandFinished holds information about a finished command.
pub struct CommandFinished {
pub:
	exit_code ?u8
	duration  configpkg.Duration
}

// StartSearch starts the search overlay with an optional initial needle.
pub struct StartSearch {
pub:
	needle string
}

// SearchTotal holds the total number of matches found by the search.
pub struct SearchTotal {
pub:
	total ?uint
}

// SearchSelected holds the currently selected search match index (1-based).
pub struct SearchSelected {
pub:
	selected ?uint
}
