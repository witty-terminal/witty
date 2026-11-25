@[has_globals]
module gtk

import ascii
import log
// Translated Ghostty native command objects, list/filter model, and signal.
// The live UI loads the compiled blueprint from GResource.
import input

// --- New C bindings unique to this file -----------------------------------
//
// `AdwDialog` and `adw_dialog_present` are declared in dialog_linux.v and
// reused here (grep-checked to avoid redeclaration).

fn C.adw_dialog_new() AdwDialog

fn C.adw_dialog_set_child(dialog AdwDialog, child GtkWidget)

fn C.adw_dialog_set_content_width(dialog AdwDialog, width int)

fn C.adw_header_bar_new() GtkWidget

fn C.adw_header_bar_set_title_widget(header GtkWidget, title_widget GtkWidget)

fn C.gtk_search_entry_new() GtkSearchEntry

fn C.gtk_scrolled_window_new() GtkScrolledWindow

fn C.gtk_scrolled_window_set_min_content_height(scrolled GtkScrolledWindow, height int)

fn C.gtk_widget_get_first_child(widget GtkWidget) GtkWidget

fn C.gtk_widget_set_tooltip_text(widget GtkWidget, text &char)

fn C.gtk_label_set_xalign(label GtkWidget, xalign f32)

fn C.gtk_label_set_ellipsize(label GtkWidget, mode int)

fn C.gtk_label_set_single_line_mode(label GtkWidget, single_line_mode bool)

fn C.gtk_shortcut_label_new(accelerator &char) GtkWidget

fn C.adw_dialog_close(dialog AdwDialog) bool

fn C.gtk_widget_get_realized(widget GtkWidget) bool

fn C.g_object_is_floating(object GObject) bool

pub type GtkListView = voidptr
pub type GtkSingleSelection = voidptr
pub type GListStore = voidptr

fn C.gtk_builder_new() voidptr
fn C.gtk_builder_set_scope(voidptr, voidptr)
fn C.gtk_builder_cscope_new() voidptr
fn C.gtk_builder_cscope_add_callback_symbol(voidptr, &char, voidptr)
fn C.gtk_builder_set_translation_domain(voidptr, &char)
fn C.gtk_builder_add_from_resource(voidptr, &char, &voidptr) u32
fn C.gtk_builder_get_object(voidptr, &char) GObject
fn C.g_list_store_append(GListStore, GObject)
fn C.g_list_store_remove_all(GListStore)
fn C.g_list_model_get_item(voidptr, u32) GObject
fn C.g_list_model_get_n_items(voidptr) u32
fn C.gtk_single_selection_get_selected(GtkSingleSelection) u32

__global g_command_type = GType(0)
__global g_command_parent = voidptr(unsafe { nil })
__global g_command_palette_type = GType(0)
__global g_command_palette_parent = voidptr(unsafe { nil })
const command_wrapper_key = 'ghostty-command-wrapper'

fn command_from_object(obj GObject) ?&Command {
	if isnil(obj) { return none }
	wrapper := native_wrapper_get(obj, command_wrapper_key)
	if isnil(wrapper) { return none }
	return unsafe { &Command(wrapper) }
}

fn command_native_get_property(obj voidptr, id u32, value voidptr, _ voidptr) {
	mut self := command_from_object(GObject(obj)) or { return }
	if id == 1 {
		C.g_value_set_object(value,
			if isnil(self.config) { unsafe { nil } } else { self.config.obj })
		return
	}
	text := match id {
		2 { self.prop_get_action_key() }
		3 { self.prop_get_action() }
		4 { self.prop_get_title() }
		5 { self.prop_get_description() }
		else { none }
	}

	if string_value := text {
		C.g_value_set_string(value, &char(string_value.str))
	} else {
		C.g_value_set_string(value, unsafe { nil })
	}
}

fn command_native_set_property(obj voidptr, id u32, value voidptr, _ voidptr) {
	if id != 1 { return }
	mut self := command_from_object(GObject(obj)) or { return }
	config_obj := C.g_value_get_object(value)
	mut config := &Config(unsafe { nil })
	if !isnil(config_obj) {
		priv := config_priv(config_obj)
		if !isnil(priv.wrapper) { config = unsafe { &Config(priv.wrapper) } }
	}
	if self.config == config { return }
	if !isnil(config) { config = config_ref(config) }
	if !isnil(self.config) { self.config.unref() }
	self.config = config
}

fn command_native_dispose(obj voidptr) {
	if mut self := command_from_object(GObject(obj)) { self.dispose_state() }
	C.witty_imgui_parent_dispose(g_command_parent, obj)
}

fn command_native_finalize(obj voidptr) {
	if mut self := command_from_object(GObject(obj)) {
		self.obj = unsafe { nil }
		native_wrapper_set(GObject(obj), command_wrapper_key, unsafe { nil })
	}
	C.witty_gobject_call_parent_finalize(obj)
}

fn command_native_class_init(klass voidptr, _ voidptr) {
	g_command_parent = C.g_type_class_peek_parent(klass)
	C.witty_gobject_class_set_get_property(klass, voidptr(command_native_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(command_native_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(command_native_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(command_native_finalize))
	C.g_object_class_install_property(klass, 1, C.g_param_spec_object(c'config', c'config',
		c'config', config_get_type(), g_param_readwrite))
	for index, name in ['action-key', 'action', 'title', 'description'] {
		C.g_object_class_install_property(klass, u32(index + 2), C.g_param_spec_string(&char(name.str),
			&char(name.str), &char(name.str), unsafe { nil }, g_param_readable))
	}
}

pub fn command_get_type() GType {
	if g_command_type == GType(0) {
		parent := C.g_object_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(command_native_class_init)
		}
		g_command_type = C.g_type_register_static(parent, c'GhosttyCommand', &info, 0)
	}
	return g_command_type
}

fn (mut self Command) attach_native() {
	self.obj = GObject(C.g_object_new(command_get_type(), &char(unsafe { nil })))
	self.native_owner = true
	native_wrapper_set(self.obj, command_wrapper_key, voidptr(&self))
}

fn command_palette_native_get_property(obj voidptr, id u32, value voidptr, _ voidptr) {
	if id != 1 { return }
	self := command_palette_from_object(GObject(obj)) or { return }
	C.g_value_set_object(value, if isnil(self.config) { unsafe { nil } } else { self.config.obj })
}

fn command_palette_native_set_property(obj voidptr, id u32, value voidptr, _ voidptr) {
	if id != 1 { return }
	mut self := command_palette_from_object(GObject(obj)) or { return }
	config_obj := C.g_value_get_object(value)
	if isnil(config_obj) {
		self.set_config_reference(unsafe { nil })
		return
	}
	priv := config_priv(config_obj)
	if !isnil(priv.wrapper) { self.set_config_reference(unsafe { &Config(priv.wrapper) }) }
}

fn command_palette_native_dispose(obj voidptr) {
	if mut self := command_palette_from_object(GObject(obj)) { self.finalize_state() }
	C.witty_imgui_parent_dispose(g_command_palette_parent, obj)
}

fn command_palette_native_class_init(klass voidptr, _ voidptr) {
	g_command_palette_parent = C.g_type_class_peek_parent(klass)
	_ = command_get_type()
	C.witty_gtk_palette_canvas_register()
	C.witty_gobject_class_set_get_property(klass, voidptr(command_palette_native_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(command_palette_native_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(command_palette_native_dispose))
	C.g_object_class_install_property(klass, 1, C.g_param_spec_object(c'config', c'config',
		c'config', config_get_type(), g_param_readwrite))
	C.g_signal_new(c'trigger', g_command_palette_type, g_signal_run_last, 0, unsafe { nil },
		unsafe { nil }, unsafe { nil }, g_type_none, 1, g_type_pointer)
}

pub fn command_palette_get_type() GType {
	if g_command_palette_type == GType(0) {
		parent := C.adw_bin_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(command_palette_native_class_init)
			instance_init: voidptr(command_palette_native_instance_init)
		}
		g_command_palette_type =
			C.g_type_register_static(parent, c'GhosttyCommandPalette', &info, 0)
	}
	return g_command_palette_type
}

fn command_palette_native_instance_init(obj voidptr, _ voidptr) {
	builder := C.gtk_builder_new()
	scope := C.gtk_builder_cscope_new()
	C.gtk_builder_cscope_add_callback_symbol(scope, c'closed',
		voidptr(command_palette_dialog_closed_cb))
	C.gtk_builder_cscope_add_callback_symbol(scope, c'search_stopped',
		voidptr(command_palette_search_stopped_cb))
	C.gtk_builder_cscope_add_callback_symbol(scope, c'search_activated',
		voidptr(command_palette_search_activated_cb))
	C.gtk_builder_cscope_add_callback_symbol(scope, c'row_activated',
		voidptr(command_palette_row_activated_cb))
	C.gtk_builder_set_scope(builder, scope)
	object_unref(GObject(scope))
	C.gtk_builder_set_translation_domain(builder, c'com.alexander.witty')
	mut failure := voidptr(unsafe { nil })
	if C.gtk_builder_add_from_resource(builder,
		c'/com/alexander/witty/ui/1.5/command-palette.ui', &failure) == 0 {
		message := error_message(GError(failure)).clone()
		if !isnil(failure) { C.g_error_free(failure) }
		object_unref(GObject(builder))
		panic('unable to initialize GhosttyCommandPalette blueprint: ${message}')
	}
	mut self := &CommandPalette{
		widget: GtkWidget(obj)
		dialog: AdwDialog(C.gtk_builder_get_object(builder, c'dialog'))
		search: GtkSearchEntry(C.gtk_builder_get_object(builder, c'search'))
		list:   GtkListView(C.gtk_builder_get_object(builder, c'view'))
		model:  GtkSingleSelection(C.gtk_builder_get_object(builder, c'model'))
		source: GListStore(C.gtk_builder_get_object(builder, c'source'))
	}
	// The original template owns its standalone dialog; retain that native
	// owner after releasing the construction-only GtkBuilder.
	object_ref(GObject(self.dialog))
	gtk_canvas_overlay_set_mask(GtkWidget(self.dialog), true)
	for object in [GObject(obj), GObject(self.dialog), GObject(self.search), GObject(self.list)] {
		native_wrapper_set(object, command_palette_wrapper_key, voidptr(self))
	}
	C.g_signal_connect_data(obj, c'notify::config',
		GCallback(voidptr(command_palette_notify_config_cb)), voidptr(self), unsafe { nil }, 0)
	object_unref(GObject(builder))
	C.g_object_weak_ref(GObject(obj), voidptr(command_palette_native_finalize_cb), voidptr(self))
}

// --- CommandData ----------------------------------------------------------

// These types mirror the two payloads of `Private.CommandData`. Keeping the
// payload in a sum type means a command retains only its active representation,
// just like the source union.
pub struct RegularData {
pub mut:
	command        input.Command
	action_str     string
	action_key_str string
}

pub struct JumpData {
pub mut:
	surface     WeakRef        = weak_ref_empty()
	surface_ptr &SurfaceWidget = unsafe { nil }
	title       string
	description string
	sort_key    uint
}

pub type CommandData = JumpData | RegularData

// --- Command --------------------------------------------------------------

// Command is the V model corresponding to Ghostty's `GhosttyCommand` GObject
// wrapper. Fields mirror the Zig `Private` struct.
@[heap]
pub struct Command {
pub mut:
	obj          GObject = unsafe { nil }
	native_owner bool
	// The config this command was built from. nil means "unset".
	config &Config = unsafe { nil }

	data CommandData = RegularData{}
}

// new creates a regular command wrapping an input.Command.
pub fn Command.new(config &Config, command input.Command) &Command {
	mut self := &Command{
		config: unsafe { nil }
		data:   RegularData{
			command: command.clone()
		}
	}
	if !isnil(config) {
		self.config = config_ref(config)
	}
	self.attach_native()
	return self
}

// new_jump creates a jump command focusing a specific surface.
pub fn Command.new_jump(config &Config, surface &SurfaceWidget) &Command {
	mut self := &Command{
		config: unsafe { nil }
		data: JumpData{
			sort_key:    uint(voidptr(surface))
			surface_ptr: unsafe { surface }
		}
	}
	// GLib records the address of the weak reference.
	if mut self.data is JumpData {
		self.data.surface.set(GObject(surface.widget))
	}
	if !isnil(config) {
		self.config = config_ref(config)
	}
	self.attach_native()
	return self
}

// config_ref is a small non-mut wrapper around `Config.ref()` so callers that
// hold an immutable `&Config` can bump the refcount without V flagging the
// parameter as needing `mut`. The underlying `ref()` does not mutate the
// config; this just satisfies the checker.
fn config_ref(config &Config) &Config {
	mut c := config
	return c.ref()
}

// --- Property getters -----------------------------------------------------

// prop_get_action_key returns a stable string key for the action, or `none` for
// jump commands. Mirrors `propGetActionKey`.
pub fn (mut self Command) prop_get_action_key() ?string {
	match mut self.data {
		RegularData {
			if self.data.action_key_str.len > 0 {
				return self.data.action_key_str
			}
			self.data.action_key_str = self.data.command.action.format()
			return self.data.action_key_str
		}
		JumpData {
			return none
		}
	}
}

// prop_get_action returns the GTK accelerator string for this command's action
// (e.g. "<Ctrl>c"), or `none` if there is no keybind. Mirrors `propGetAction`.
pub fn (mut self Command) prop_get_action() ?string {
	match mut self.data {
		RegularData {
			if self.data.action_str.len > 0 {
				return self.data.action_str
			}
			if isnil(self.config) {
				return none
			}

			cfg := self.config.get()
			trigger := cfg.keybind.set.get_trigger(self.data.command.action) or { return none }
			accel := accel_from_trigger(trigger) or { return none }
			self.data.action_str = accel
			return self.data.action_str
		}
		JumpData {
			return none
		}
	}
}

// prop_get_title returns the display title. For jump commands this is
// "Focus: <surface title>" (or "Focus: Untitled"). Mirrors `propGetTitle`.
pub fn (mut self Command) prop_get_title() ?string {
	match mut self.data {
		RegularData {
			return self.data.command.title
		}
		JumpData {
			if self.data.title.len > 0 {
				return self.data.title
			}
			obj := self.data.surface.get()
			if isnil(obj) {
				return none
			}
			defer {
				object_unref(obj)
			}
			if isnil(self.data.surface_ptr) {
				return none
			}
			surface_title := self.data.surface_ptr.get_title() or { 'Untitled' }
			self.data.title = 'Focus: ${surface_title}'
			return self.data.title
		}
	}
}

// prop_get_description returns the (optional) description. For jump commands
// this is the surface pwd when it isn't already part of the title. Mirrors
// `propGetDescription`.
pub fn (mut self Command) prop_get_description() ?string {
	match mut self.data {
		RegularData {
			return self.data.command.description
		}
		JumpData {
			if self.data.description.len > 0 {
				return self.data.description
			}
			obj := self.data.surface.get()
			if isnil(obj) {
				return none
			}
			defer {
				object_unref(obj)
			}
			if isnil(self.data.surface_ptr) {
				return none
			}
			title := self.data.surface_ptr.get_title() or { 'Untitled' }
			if pwd := self.data.surface_ptr.get_pwd() {
				if !title.contains(pwd) {
					self.data.description = pwd
				}
			}
			if self.data.description.len == 0 {
				return none
			}
			return self.data.description
		}
	}
}

// --- Command accessors ----------------------------------------------------

// get_action returns a copy of the action for regular commands, or `none` for
// jump commands. Mirrors `getAction`.
pub fn (self &Command) get_action() ?input.Action {
	return match self.data {
		RegularData { self.data.command.action }
		JumpData { none }
	}
}

// is_jump reports whether this is a jump command. Mirrors `isJump`.
pub fn (self &Command) is_jump() bool {
	return self.data is JumpData
}

// get_jump_surface returns the jump target with a new strong reference. The
// caller must call SurfaceWidget.unref when finished, matching getJumpSurface.
pub fn (mut self Command) get_jump_surface() ?&SurfaceWidget {
	match mut self.data {
		RegularData {
			return none
		}
		JumpData {
			obj := self.data.surface.get()
			if isnil(obj) {
				return none
			}
			if isnil(self.data.surface_ptr) {
				object_unref(obj)
				return none
			}
			return self.data.surface_ptr
		}
	}
}

// present_jump_surface presents the jump target while holding the strong
// reference returned by get_jump_surface.
fn (mut self Command) present_jump_surface() bool {
	mut surface := self.get_jump_surface() or { return false }
	defer {
		surface.unref()
	}
	surface.present()
	return true
}

// dispose releases the config reference and clears the weak surface ref.
// Mirrors the `dispose` virtual method.
pub fn (mut self Command) dispose() {
	if !isnil(self.obj) {
		if self.native_owner {
			self.native_owner = false
			object_unref(self.obj)
		}
		return
	}
	self.dispose_state()
}

fn (mut self Command) dispose_state() {
	if !isnil(self.config) {
		self.config.unref()
		self.config = unsafe { nil }
	}
	match mut self.data {
		RegularData {}
		JumpData {
			self.data.surface.set(unsafe { nil })
			self.data.surface_ptr = unsafe { nil }
		}
	}
}

// --- CommandPalette -------------------------------------------------------

// The wrapper retains the native GhosttyCommandPalette instance and the
// source blueprint's GObject model hierarchy.
@[heap]
pub struct CommandPalette {
pub mut:
	// The native GhosttyCommandPalette AdwBin instance.
	widget GtkWidget = unsafe { nil }

	// The configuration this palette is using. nil means "unset".
	config &Config = unsafe { nil }

	// The dialog object containing the palette UI.
	dialog AdwDialog = unsafe { nil }

	// The search input text field.
	search GtkSearchEntry = unsafe { nil }

	// The original list view, filtered single-selection model and list store.
	list   GtkListView        = unsafe { nil }
	model  GtkSingleSelection = unsafe { nil }
	source GListStore         = unsafe { nil }

	// Temporary command ownership used for source collection/sorting.
	commands []&Command
	window   &Window      = unsafe { nil }
	app      &Application = unsafe { nil }
	disposed bool
}

const command_palette_wrapper_key = 'witty-command-palette-wrapper'

// new_command_palette creates a new CommandPalette. Mirrors
// `CommandPalette.new`: the initial native reference is the palette's
// self-reference, released by dialog_closed, and the returned wrapper owns one
// additional caller reference.
pub fn new_command_palette() &CommandPalette {
	obj := GObject(C.g_object_new(command_palette_get_type(), &char(unsafe { nil })))
	C.g_object_ref_sink(obj)
	object_ref(obj)
	return command_palette_from_object(obj) or {
		panic('native palette instance did not initialize')
	}
}

// ref returns a new caller-owned reference to the palette.
pub fn (mut self CommandPalette) ref() &CommandPalette {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

// ref_sink adopts a floating palette reference or adds a reference when the
// native object is already owned, matching Common.refSink.
pub fn (mut self CommandPalette) ref_sink() &CommandPalette {
	if !isnil(self.widget) {
		C.g_object_ref_sink(GObject(self.widget))
	}
	return self
}

// unref releases one caller or self reference.
pub fn (mut self CommandPalette) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

// command_palette_from_object performs the typed half of Ghostty's
// WeakRef(CommandPalette).get. The returned wrapper borrows the caller's
// strong native-object reference.
fn command_palette_from_object(obj GObject) ?&CommandPalette {
	if isnil(obj) || C.g_type_check_instance_is_a(obj, command_palette_get_type()) == 0 {
		return none
	}
	wrapper := native_wrapper_get(obj, command_palette_wrapper_key)
	if isnil(wrapper) {
		return none
	}
	return unsafe { &CommandPalette(wrapper) }
}

fn command_palette_from_child(obj GObject) ?&CommandPalette {
	if isnil(obj) { return none }
	wrapper := native_wrapper_get(obj, command_palette_wrapper_key)
	if isnil(wrapper) { return none }
	self := unsafe { &CommandPalette(wrapper) }
	if self.disposed { return none }
	return self
}

// set_config applies the ownership and notification behavior of the native
// `config` GObject property. The palette owns its own reference independently
// of the commands rebuilt by prop_config.
pub fn (mut self CommandPalette) set_config(config &Config) {
	if !isnil(self.widget) {
		// V 0.5.2 emits `if` expressions inside C call arguments as statements.
		mut config_obj := unsafe { nil }
		if !isnil(config) { config_obj = voidptr(config.obj) }
		C.g_object_set(GObject(self.widget), c'config', config_obj, unsafe { nil })
		return
	}
	self.set_config_reference(config)
	self.prop_config()
}

fn (mut self CommandPalette) set_config_reference(config &Config) {
	if self.config == config {
		return
	}
	new_config := if isnil(config) { unsafe { nil } } else { config_ref(config) }
	if !isnil(self.config) {
		self.config.unref()
	}
	self.config = new_config
}

// prop_config is the config-changed handler: it clears and rebuilds the command
// list from the new config. Mirrors `propConfig`.
pub fn (mut self CommandPalette) prop_config() {
	if isnil(self.config) {
		log.warn('command palette does not have a config!')
		return
	}

	// Native model objects and their constructor references are independent.
	if !isnil(self.source) { C.g_list_store_remove_all(self.source) }
	for mut command in self.commands {
		command.dispose()
	}
	self.commands = []&Command{}

	self.collect_jump_commands()
	self.collect_regular_commands()

	// Sort commands (colon-normalized, case-insensitive; sort_key tie-break).
	self.commands.sort_with_compare(fn (a &&Command, b &&Command) int {
		mut ca := unsafe { *a }
		mut cb := unsafe { *b }
		if compare_commands(mut ca, mut cb) {
			return -1
		}
		if compare_commands(mut cb, mut ca) {
			return 1
		}
		return 0
	})

	if !isnil(self.source) {
		for mut command in self.commands {
			C.g_list_store_append(self.source, command.obj)
			command.dispose()
		}
	}
}

// collect_regular_commands collects regular commands from the config's
// `command-palette-entry`, filtering out actions unsupported on GTK. Mirrors
// `collectRegularCommands`.
fn (mut self CommandPalette) collect_regular_commands() {
	cfg := self.config.get()
	for command in cfg.command_palette_entry.items {
		if !is_action_supported_on_gtk(command.action) {
			continue
		}
		self.commands << Command.new(self.config, command)
	}
}

// collect_jump_commands collects one jump command per open surface across all
// windows. Mirrors `collectJumpCommands`.
fn (mut self CommandPalette) collect_jump_commands() {
	if isnil(self.app) {
		return
	}
	core_app := self.app.core()
	for surface_ref in core_app.surfaces {
		if isnil(surface_ref) || isnil(surface_ref.core_surface) {
			continue
		}
		core_surface := surface_ref.core_surface
		if isnil(core_surface.rt_surface) || isnil(core_surface.rt_surface.user_data) {
			continue
		}
		surface := unsafe { &SurfaceWidget(core_surface.rt_surface.user_data) }
		if isnil(surface) || surface.core_surface != core_surface {
			continue
		}
		self.commands << Command.new_jump(self.config, surface)
	}
}

// is_action_supported_on_gtk reports whether an action makes sense / is
// implemented on GTK. Mirrors `isActionSupportedOnGtk`.
fn is_action_supported_on_gtk(action input.Action) bool {
	return match action {
		input.ActionCloseAllWindows, input.ActionToggleSecureInput, input.ActionCheckForUpdates,
		input.ActionRedo, input.ActionUndo, input.ActionResetWindowSize,
		input.ActionToggleWindowFloatOnTop {
			false
		}
		else {
			true
		}
	}
}

// compare_commands returns true if command `a` should sort before `b`. Sorts
// alphabetically by title, case-insensitively, with ':' normalized to '\t' so
// "Foo:" sorts before "Foo Bar:". Ties fall back to sort_key for jump commands.
// Mirrors `compareCommands`.
fn compare_commands(mut a Command, mut b Command) bool {
	a_title := a.prop_get_title() or { return false }
	b_title := b.prop_get_title() or { return true }

	min_len := if a_title.len < b_title.len { a_title.len } else { b_title.len }
	for i in 0 .. min_len {
		// Normalize ':' to '\t' so it sorts before space.
		a_char := if a_title[i] == `:` { u8(`\t`) } else { a_title[i] }
		b_char := if b_title[i] == `:` { u8(`\t`) } else { b_title[i] }
		a_lower := ascii.to_lower(a_char)
		b_lower := ascii.to_lower(b_char)
		if a_lower != b_lower {
			return a_lower < b_lower
		}
	}

	// If one title is a prefix of the other, the shorter comes first.
	if a_title.len != b_title.len {
		return a_title.len < b_title.len
	}

	// Titles are equal: use sort_key as a tie-breaker for jump commands. A
	// regular command in either slot means "not less than" (matches the Zig
	// `.regular => return false`).
	a_sort_key := match a.data {
		RegularData { return false }
		JumpData { a.data.sort_key }
	}

	b_sort_key := match b.data {
		RegularData { return false }
		JumpData { b.data.sort_key }
	}

	return a_sort_key < b_sort_key
}

// --- Dialog / activation --------------------------------------------------

// toggle shows or hides the palette dialog. When shown it is modal over the
// given window and the search bar is focused. Mirrors `toggle`.
pub fn (mut self CommandPalette) toggle(window &Window) {
	// If the dialog is already realized (shown), close it.
	if C.gtk_widget_get_realized(self.dialog) {
		self.close()
		return
	}
	self.window = unsafe { window }

	// Window holds the AdwApplicationWindow in `obj`; present it as the parent.
	C.adw_dialog_present(self.dialog, window.obj)

	// Focus the search bar.
	C.gtk_widget_grab_focus(self.search)
}

// close closes the dialog. Mirrors `close`.
fn (self &CommandPalette) close() {
	C.adw_dialog_close(self.dialog)
}

// dialog_closed releases the palette's self-reference. The Window keeps only
// a weak native reference, so finalization clears its cached palette exactly
// as in Ghostty.
pub fn (mut self CommandPalette) dialog_closed() {
	self.unref()
}

// search_stopped is the search "stop-search" template callback (ESC). Mirrors
// `searchStopped`.
pub fn (self &CommandPalette) search_stopped() {
	self.close()
}

// search_activated is the search "activate" template callback (Enter). Mirrors
// `searchActivated`: activates the currently selected row.
pub fn (mut self CommandPalette) search_activated() {
	self.activated(self.model_selected())
}

// row_activated is the list-view "activate" template callback. Mirrors
// `rowActivated`.
pub fn (mut self CommandPalette) row_activated(pos u32) {
	self.activated(pos)
}

// activated dispatches activation of the command at the given (visible)
// position: jump commands present their surface, regular commands emit the
// `trigger` signal with the action. Mirrors `activated`.
fn (mut self CommandPalette) activated(pos u32) {
	// Closing can release the palette's self-reference synchronously.
	self.ref()
	defer {
		self.unref()
	}
	// SelectionModel.getItem returns a strong command reference, retained
	// across close exactly as in the source activated handler.
	obj := if isnil(self.model) {
		GObject(unsafe { nil })
	} else {
		C.g_list_model_get_item(self.model, pos)
	}
	defer {
		if !isnil(obj) { object_unref(obj) }
	}
	self.close()
	mut command := command_from_object(obj) or { return }
	if command.is_jump() {
		command.present_jump_surface()
		return
	}
	action := command.get_action() or { return }
	self.emit_trigger(action)
}

fn (self &CommandPalette) model_selected() u32 {
	return if isnil(self.model) { u32(-1) } else { C.gtk_single_selection_get_selected(self.model) }
}

fn (self &CommandPalette) emit_trigger(action input.Action) {
	C.g_signal_emit_by_name(self.widget, c'trigger', &action)
}

fn command_palette_notify_config_cb(_ GObject, _ voidptr, data voidptr) {
	if !isnil(data) {
		mut self := unsafe { &CommandPalette(data) }
		self.prop_config()
	}
}

fn command_palette_dialog_closed_cb(dialog AdwDialog, _ voidptr) {
	if mut self := command_palette_from_child(GObject(dialog)) { self.dialog_closed() }
}

fn command_palette_native_finalize_cb(data voidptr, _ GObject) {
	if !isnil(data) {
		mut self := unsafe { &CommandPalette(data) }
		self.widget = unsafe { nil }
	}
}

fn command_palette_search_stopped_cb(search GtkSearchEntry, _ voidptr) {
	if self := command_palette_from_child(GObject(search)) { self.search_stopped() }
}

fn command_palette_search_activated_cb(search GtkSearchEntry, _ voidptr) {
	if mut self := command_palette_from_child(GObject(search)) { self.search_activated() }
}

fn command_palette_row_activated_cb(view GtkListView, position u32, _ voidptr) {
	if mut self := command_palette_from_child(GObject(view)) { self.row_activated(position) }
}

// finalize_state mirrors the palette dispose vfunc after the final native
// reference is released. Signal connections are owned by the dialog and have
// already disappeared when the weak notification runs.
fn (mut self CommandPalette) finalize_state() {
	if self.disposed {
		return
	}
	self.disposed = true
	if !isnil(self.source) { C.g_list_store_remove_all(self.source) }
	for mut command in self.commands {
		command.dispose()
	}
	self.commands.clear()
	if !isnil(self.config) {
		self.config.unref()
	}
	self.config = unsafe { nil }
	self.window = unsafe { nil }
	self.app = unsafe { nil }
	self.widget = unsafe { nil }
	if !isnil(self.dialog) { object_unref(GObject(self.dialog)) }
	self.dialog = unsafe { nil }
	self.search = unsafe { nil }
	self.list = unsafe { nil }
	self.model = unsafe { nil }
	self.source = unsafe { nil }
}
