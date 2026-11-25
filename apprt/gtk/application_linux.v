@[has_globals]
module gtk

import apprt
import core
import configpkg
import datastruct
import input
import global_state
import internal_os
import log
import osc
import os
import terminal
import xev

// application_linux.v - The primary GTK application (AdwApplication subclass).
//
// Translated from ghostty/src/apprt/gtk/class/application.zig.
//
// In ghostty this is a GObject class (a subclass of adw.Application) created
// with `gobject.ext.defineClass`, with signal vfunc overrides and GObject
// properties. V hand-expands the same class and keeps its translated private
// state in a stable heap wrapper, so:
//
//   * `GhosttyApplication` is a real AdwApplication subclass whose native
//     private storage points at `Application`.
//   * Its startup/activate/dispose/finalize virtual methods and read-only
//     `config` object property are installed on the native class.
//   * The core `App` (libwitty `CoreApp`) is `core.App`, held directly.
//     Method SIGNATURES are kept faithful; the pure logic (config env setup,
//     single-instance/app-id resolution, action map, quit timer, quit flow) is
//     translated directly.
//
// The apprt `App` adapter (app_linux.v) wraps this `Application` and forwards
// init/run/terminate/wakeup/perform_action to it.

// --- New C bindings --------------------------------------------------------
//
// Only functions not already declared elsewhere in the module are added here
// (see the `fn C.` grep note in the module docs). GApplication / GtkApplication
// / AdwApplication / GMainContext / GLib source + timeout functions.

// GApplication lifecycle
fn C.g_application_register(app GApplication, cancellable voidptr, error &GError) bool

fn C.g_application_activate(app GApplication)

fn C.g_application_get_is_remote(app GApplication) bool

fn C.g_application_get_flags(app GApplication) int

fn C.g_application_set_default(app GApplication)

fn C.g_application_get_default() GApplication

fn C.g_application_get_dbus_connection(app GApplication) GDBusConnection

fn C.g_application_send_notification(app GApplication, id &char, notification voidptr)

fn C.g_application_set_resource_base_path(app GApplication, resource_path &char)

fn C.g_settings_sync()

fn C.g_variant_is_of_type(value GVariant, vtype GVariantType) bool

fn C.g_variant_get_uint64(value GVariant) u64

fn C.g_variant_iter_new(value GVariant) voidptr

fn C.g_variant_iter_next_value(iter voidptr) GVariant

fn C.g_variant_iter_free(iter voidptr)

// GtkApplication
fn C.gtk_application_get_windows(app GtkApplication) GList

fn C.gtk_application_set_accels_for_action(app GtkApplication, detailed_action_name &char, accels &&char)

// AdwApplication / AdwStyleManager
fn C.adw_application_get_style_manager(app AdwApplication) voidptr

fn C.adw_style_manager_set_color_scheme(style_manager voidptr, color_scheme int)

fn C.adw_style_manager_get_dark(style_manager voidptr) bool

fn C.adw_init()

// GTK CSS
pub type GtkCssProvider = voidptr

fn C.gtk_css_provider_new() GtkCssProvider

fn C.gtk_css_provider_load_from_data(provider GtkCssProvider, data &char, length int)

fn C.gtk_css_section_to_string(section voidptr) &char

fn C.witty_gtk_css_section_get_bytes(section voidptr) GBytes

fn C.g_bytes_get_data(bytes GBytes, size &uint) voidptr

fn C.g_quark_to_string(quark u32) &char

fn C.gtk_style_context_add_provider_for_display(display GdkDisplay, provider GtkCssProvider, priority u32)

fn C.gtk_style_context_remove_provider_for_display(display GdkDisplay, provider GtkCssProvider)

// GLib main loop + sources
fn C.g_main_context_default() voidptr

fn C.g_main_context_acquire(context voidptr) bool

fn C.g_main_context_release(context voidptr)

fn C.g_main_context_iteration(context voidptr, may_block bool) bool

fn C.g_main_context_wakeup(context voidptr)

fn C.g_timeout_add(interval u32, function voidptr, data voidptr) u32

fn C.g_source_remove(tag u32) bool

fn C.g_unix_signal_add(signum int, handler voidptr, user_data voidptr) u32

fn C.g_log_set_writer_func(function voidptr, user_data voidptr, user_data_free voidptr)

fn C.witty_glog_field_key(fields voidptr, index uint) &char

fn C.witty_glog_field_value(fields voidptr, index uint) voidptr

fn C.witty_glog_field_length(fields voidptr, index uint) int

// GTK window helpers.
// NOTE: gtk_window_present / gtk_window_destroy / gtk_window_is_active are
// declared in window_linux.v — reused here, NOT redeclared. `is_active` there
// returns `int` (0/non-zero), which we honor below.
fn C.gtk_window_list_toplevels() GList

fn C.gtk_window_set_interactive_debugging(enable bool)

// process env
fn C.setenv(name &char, value &char, overwrite int) int

// --- AdwColorScheme -------------------------------------------------------
//
// Mirrors `adw.ColorScheme`. Values match the AdwColorScheme C enum.
pub enum AdwColorScheme as i32 {
	default_     = 0
	force_light  = 1
	prefer_light = 2
	prefer_dark  = 3
	force_dark   = 4
}

// GtkInterfaceColorScheme backs GtkCssProvider:prefers-color-scheme beginning
// with GTK 4.20. Keep every native value because GTK may surface the other two
// through property APIs even though Ghostty assigns only light and dark.
pub enum GtkInterfaceColorScheme as i32 {
	unsupported = 0
	default_    = 1
	dark        = 2
	light       = 3
}

fn application_interface_color_scheme(scheme apprt.ColorScheme) GtkInterfaceColorScheme {
	return match scheme {
		.light { .light }
		.dark { .dark }
	}
}

const gtk_style_provider_priority_application = u32(600)
const gtk_style_provider_priority_user = u32(800)

// --- GApplicationFlags ----------------------------------------------------
//
// Mirrors the `gio.ApplicationFlags` bits used here. Only `non_unique` matters
// for single-instance resolution.
pub const g_application_default_flags = 0
pub const g_application_non_unique = 0x20

// Linux signal number used by Ghostty for on-demand configuration reloads.
const sigusr2 = 12

const g_log_level_error = u32(1 << 2)
const g_log_level_critical = u32(1 << 3)
const g_log_level_warning = u32(1 << 4)
const g_log_level_message = u32(1 << 5)
const g_log_level_info = u32(1 << 6)
const g_log_level_debug = u32(1 << 7)
const g_log_writer_handled = 1
const g_log_writer_unhandled = 0

fn glib_log_field_string(fields voidptr, index uint) ?string {
	value := C.witty_glog_field_value(fields, index)
	if isnil(value) {
		return none
	}
	length := C.witty_glog_field_length(fields, index)
	if length >= 0 {
		return unsafe { tos(&u8(value), int(length)) }.clone()
	}
	return unsafe { cstring_to_vstring(&char(value)) }.clone()
}

// glib_log_writer_function funnels structured GLib/GObject/GTK messages into
// the same severity buckets used by Witty. Mirrors glibLogWriterFunction.
fn glib_log_writer_function(level u32, fields voidptr, n_fields uint, user_data voidptr) int {
	_ = user_data
	mut message := ?string(none)
	mut domain := ?string(none)
	for i in uint(0) .. n_fields {
		key_ptr := C.witty_glog_field_key(fields, i)
		if isnil(key_ptr) {
			continue
		}
		key := unsafe { cstring_to_vstring(key_ptr) }
		if key == 'MESSAGE' {
			message = glib_log_field_string(fields, i)
		} else if key == 'GLIB_DOMAIN' {
			domain = glib_log_field_string(fields, i)
		}
	}

	msg := message or { return g_log_writer_unhandled }
	domain_name := domain or { '«unknown»' }
	if level & g_log_level_error != 0 {
		log.error('glib: ERROR: ${domain_name}: ${msg}')
	} else if level & g_log_level_critical != 0 {
		log.error('glib: CRITICAL: ${domain_name}: ${msg}')
	} else if level & g_log_level_warning != 0 {
		log.warn('glib: WARNING: ${domain_name}: ${msg}')
	} else if level & g_log_level_message != 0 {
		log.info('glib: MESSAGE: ${domain_name}: ${msg}')
	} else if level & g_log_level_info != 0 {
		log.info('glib: INFO: ${domain_name}: ${msg}')
	} else if level & g_log_level_debug != 0 {
		log.debug('glib: DEBUG: ${domain_name}: ${msg}')
	} else {
		log.debug('glib: UNKNOWN: ${domain_name}: ${msg}')
	}
	return g_log_writer_handled
}

// --- Quit timer state -----------------------------------------------------
//
// Mirrors the `quit_timer: union(enum) { off, active: c_uint, expired }` in the
// Zig Private struct. Only the active arm owns a GLib source id.
pub struct QuitTimerOff {}

pub struct QuitTimerActive {
pub:
	source u32
}

pub struct QuitTimerExpired {}

pub type QuitTimer = QuitTimerOff | QuitTimerActive | QuitTimerExpired

// --- GObject class registration -------------------------------------------

struct C.GhosttyApplicationPrivate {
mut:
	wrapper voidptr
}

__global g_ghostty_application_type = GType(0)

// The instance-private offset: the size until class_init adjusts it, then
// the (negative) offset from the instance. Mirrors zig-gobject's `Private.offset`.
__global g_ghostty_application_priv_offset = int(0)
__global g_ghostty_application_pspec_config = &C.GParamSpec(unsafe { nil })

const ghostty_application_prop_config = u32(1)
const ghostty_application_param_static_strings = int(32 | 64 | 128)

fn ghostty_application_priv(obj voidptr) &C.GhosttyApplicationPrivate {
	return &C.GhosttyApplicationPrivate(instance_private(obj, g_ghostty_application_priv_offset))
}

fn ghostty_application_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := ghostty_application_priv(obj)
	if property_id != ghostty_application_prop_config || isnil(priv.wrapper) {
		return
	}
	self := unsafe { &Application(priv.wrapper) }
	C.g_value_set_object(value, if isnil(self.config_object) {
		unsafe { nil }
	} else {
		self.config_object.obj
	})
}

fn ghostty_application_startup(obj voidptr) {
	C.witty_gapplication_call_parent_startup(obj)
	priv := ghostty_application_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Application(priv.wrapper) }
		self.startup()
	}
}

fn ghostty_application_activate(obj voidptr) {
	priv := ghostty_application_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Application(priv.wrapper) }
		self.activate()
	}
	C.witty_gapplication_call_parent_activate(obj)
}

fn ghostty_application_dispose(obj voidptr) {
	priv := ghostty_application_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Application(priv.wrapper) }
		self.dispose()
	}
	C.witty_gobject_call_parent_dispose(obj)
}

fn ghostty_application_finalize(obj voidptr) {
	mut priv := ghostty_application_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Application(priv.wrapper) }
		self.finalize()
		self.obj = unsafe { nil }
		priv.wrapper = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

fn ghostty_application_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_ghostty_application_priv_offset)
	_ = class_data
	_ = config_get_type()
	C.witty_gobject_class_set_get_property(klass, voidptr(ghostty_application_get_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(ghostty_application_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(ghostty_application_finalize))
	C.witty_gapplication_class_set_startup(klass, voidptr(ghostty_application_startup))
	C.witty_gapplication_class_set_activate(klass, voidptr(ghostty_application_activate))

	flags := g_param_readable | ghostty_application_param_static_strings
	nil_str := &char(unsafe { nil })
	g_ghostty_application_pspec_config = C.g_param_spec_object(c'config', nil_str, nil_str, config_get_type(), flags)
	C.g_object_class_install_property(klass, ghostty_application_prop_config, g_ghostty_application_pspec_config)
}

fn ghostty_application_instance_init(instance voidptr, klass voidptr) {
	_ = instance
	_ = klass
}

pub fn ghostty_application_get_type() GType {
	if g_ghostty_application_type == GType(0) {
		parent := C.adw_application_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(ghostty_application_class_init)
			instance_init: voidptr(ghostty_application_instance_init)
		}
		g_ghostty_application_type = C.g_type_register_static(parent, c'GhosttyApplication', &info, 0)
		g_ghostty_application_priv_offset = C.g_type_add_instance_private(g_ghostty_application_type, sizeof(C.GhosttyApplicationPrivate))
	}
	return g_ghostty_application_type
}

// --- Application ----------------------------------------------------------
//
// The canonical GTK application object. In ghostty this is `Application`, a
// GObject subclass of `adw.Application`; here it wraps that GObject instance
// (`obj`) and mirrors ghostty's `Private` fields inline.
//
// `@[heap]` so that the apprt `App` adapter can hold a stable `&Application`.
@[heap]
pub struct Application {
mut:
	// The underlying GtkApplication/AdwApplication instance pointer.
	obj GApplication = unsafe { nil }

	// The apprt App. Mirrors `Private.rt_app`.
	rt_app &App = unsafe { nil }

	// The libwitty App instance. Mirrors `Private.core_app`.
	core_app &core.App = unsafe { nil }

	// The core configuration retained by the translated runtime bridge.
	config configpkg.Config

	// The current GTK config wrapper. Reloading replaces this object, matching
	// Ghostty's `Private.config` ownership and property-binding semantics.
	config_object &Config = unsafe { nil }

	// Headless action boundary used by core.App. Actions emitted through it are
	// immediately dispatched back into this GTK runtime after each core tick.
	runtime_bridge apprt.RuntimeApp

	// XDG desktop-portal global shortcut manager.
	global_shortcuts &GlobalShortcuts = unsafe { nil }

	// State and logic for the underlying windowing protocol. Mirrors
	// `Private.winproto`.
	winproto WinProtoApp = NoopApp{}

	// The base path of the transient cgroup, if cgroups are enabled and
	// initialization succeeded. Mirrors `Private.transient_cgroup_base`.
	transient_cgroup_base ?string

	// Set true once we request a window exactly once, to prevent quitting
	// before we've shown one window. Mirrors `Private.requested_window`.
	requested_window bool

	// Set false internally when the event loop should exit and the application
	// should quit. Only set by the main loop thread. Mirrors `Private.running`.
	running bool

	// The quit timer used to quit the app after the last window is closed.
	// Mirrors `Private.quit_timer`.
	quit_timer QuitTimer = QuitTimerOff{}

	// glib source id for our SIGUSR2 signal handler. Mirrors
	// `Private.signal_source`.
	signal_source ?u32

	// The reusable config errors dialog. It can close independently of the
	// application, so retain the same weak reference as Ghostty.
	config_errors_dialog WeakRef = weak_ref_empty()

	// CSS provider for shipped and configuration-derived application styles.
	css_provider GtkCssProvider = unsafe { nil }

	// Providers for user-defined custom stylesheets. Mirrors
	// `Private.custom_css_providers`.
	custom_css_providers []GtkCssProvider

	// Stable V wrappers for the GhosttyWindow objects owned by GtkApplication.
	windows []&Window

	screenshot ScreenshotCapture

	// GObject dispose/finalize can run after the explicit application teardown.
	disposed      bool
	deinitialized bool
}

// default returns the translated wrapper for the default GhosttyApplication.
// Ghostty treats a missing default or a default of the wrong type as an
// invariant violation, because either state means application initialization
// is fundamentally broken.
pub fn Application.default() &Application {
	obj := C.g_application_get_default()
	if isnil(obj) {
		panic('default GApplication is not set')
	}
	if C.g_type_check_instance_is_a(obj, ghostty_application_get_type()) == 0 {
		panic('default GApplication is not a GhosttyApplication')
	}
	priv := ghostty_application_priv(obj)
	if isnil(priv.wrapper) {
		panic('default GhosttyApplication has no translated wrapper')
	}
	return unsafe { &Application(priv.wrapper) }
}

// new creates a new Application. Mirrors `Application.new`.
//
// application_default_config_after_load_error preserves startup when the
// user's configuration cannot be loaded. Ghostty records the failure on a
// fresh default config so the GTK diagnostics UI can explain the degraded
// startup instead of aborting before a window can be shown.
fn application_default_config_after_load_error(err IError) configpkg.Config {
	mut config := configpkg.Config.default_config()
	config.add_diagnostic_fmt('error loading user configuration: ${err}')
	return config
}

// This does far more than a normal constructor because it is the main program
// entrypoint: it loads config, sets GTK env vars, resolves the app id and
// single-instance flags, initializes libadwaita and the windowing protocol,
// and instantiates the AdwApplication. CSS provider/property integration is
// handled separately by the translated wrapper.
pub fn Application.new(rt_app &App, core_app &core.App) !&Application {
	// Capture GLib/GObject/GTK log messages via a writer func.
	C.g_log_set_writer_func(voidptr(glib_log_writer_function), unsafe { nil }, unsafe { nil })

	// Log our GTK/libadwaita versions.
	gtk_log_version()
	adw_log_version()

	// Set the gettext global domain so unqualified translations resolve.
	internal_os.init_global_domain() or {
		log.warn('i18n initialization failed error=${err}')
	}

	// Load defaults, user files, command-line flags, recursive files, and theme
	// replay before GTK reads any startup settings. A broken configuration must
	// not prevent the diagnostics UI from starting.
	mut config := configpkg.Config.load() or {
		application_default_config_after_load_error(err)
	}
	if rt_app.screenshot.path != '' {
		config.initial_window = true
		config.wait_after_command = true
		config.window_save_state = .never
		// Allocate the requested grid directly to the viewport being captured.
		config.window_decoration = .none_
		config.gtk_titlebar = false
		config.gtk_titlebar_style = .native
		config.window_show_tab_bar = .never
	}

	// Setup our GTK init env vars. This must happen BEFORE GTK init.
	set_gtk_env(&config)

	// Initialize libadwaita.
	C.adw_init()

	// Resolve single-instance. `detect` should have been resolved during config
	// load; we treat it as single-instance if not explicitly disabled.
	single_instance := match config.gtk_single_instance {
		.false_ { false }
		.true_ { true }
		.detect { panic('gtk-single-instance must be finalized before GTK initialization') }
	}

	// Setup the flags for our application.
	mut app_flags := g_application_default_flags
	if !single_instance || rt_app.screenshot.path != '' {
		app_flags |= g_application_non_unique
	}

	// Our app id determines uniqueness and maps to our desktop file. If the
	// config specifies a valid `class`, we use it; otherwise the default id.
	mut app_id := application_id
	if class := config.class {
		if C.g_application_id_is_valid(&char(class.str)) {
			app_id = class
		} else {
			log.warn("invalid 'class' in config, ignoring")
		}
	}

	// Setup our windowing protocol logic. A GTK application requires a display;
	// Ghostty exits when GTK cannot provide one, while this fallible constructor
	// returns the error to its caller.
	display := C.gdk_display_get_default()
	if isnil(display) {
		return error('GDK display is unavailable')
	}
	winproto := WinProtoApp.init(display, app_id, &config) or {
		log.warn('error initializing windowing protocol err=${err}')
		NoopApp{}
	}
	protocol_name := match winproto {
		NoopApp { 'none' }
		WaylandApp { 'wayland' }
		X11App { 'x11' }
	}
	log.debug('windowing protocol=${protocol_name}')
	log.debug('creating GTK application id=${app_id} single-instance=${single_instance}')

	// The runtime provider is retained for the application's lifetime. The
	// priority matches Ghostty's application priority + 3.
	css_provider := C.gtk_css_provider_new()
	if isnil(css_provider) {
		return error('failed to create GTK CSS provider')
	}
	C.gtk_style_context_add_provider_for_display(display, css_provider, gtk_style_provider_priority_application + 3)

	// Instantiate the native GhosttyApplication subclass.
	mut self := &Application{
		rt_app:           unsafe { rt_app }
		core_app:         unsafe { core_app }
		config:           config
		config_object:    config_new(config)
		runtime_bridge:   apprt.RuntimeApp{
			config: config.clone()
		}
		global_shortcuts: GlobalShortcuts.new()
		winproto:         winproto
		css_provider:     css_provider
		screenshot:       ScreenshotCapture{ options: rt_app.screenshot }
	}
	obj := C.g_object_new(ghostty_application_get_type(), c'application-id', &char(app_id.str), c'flags', GApplicationFlags(app_flags), c'resource-base-path', c'/com/alexander/witty', &char(unsafe { nil }))
	if isnil(obj) {
		self.deinit()
		return error('failed to create AdwApplication')
	}
	self.obj = GApplication(obj)
	mut priv := ghostty_application_priv(obj)
	priv.wrapper = voidptr(self)
	// Core actions borrow their payloads for the duration of perform_action.
	// Dispatch them synchronously through the translated GTK App, exactly like
	// Ghostty's apprt vtable, rather than retaining borrowed data in a queue.
	self.runtime_bridge.user_data = self
	self.runtime_bridge.action_fn = application_runtime_action_cb
	self.runtime_bridge.wakeup_fn = application_runtime_wakeup_cb
	C.g_signal_connect_data(self.obj, c'notify::config', GCallback(voidptr(application_config_notify_cb)), voidptr(self), unsafe { nil }, 0)

	C.g_signal_connect_data(css_provider, c'parsing-error', GCallback(voidptr(application_css_parsing_error_cb)), voidptr(self), unsafe { nil }, 0)

	// Trigger initial config changes through the native property notification.
	C.g_object_notify_by_pspec(self.obj, g_ghostty_application_pspec_config)

	return self
}

// deinit force-deinitializes the application. Mirrors `Application.deinit`.
//
// Normally the GObject finalizer would do this, but applications are never
// fully unreferenced, so this ensures cleanup happens.
pub fn (mut self Application) deinit() {
	if self.deinitialized {
		return
	}
	self.deinitialized = true
	self.dispose()
	self.winproto.deinit()
	if !isnil(self.global_shortcuts) {
		mut shortcuts := unsafe { self.global_shortcuts }
		shortcuts.dispose()
		shortcuts.unref()
		self.global_shortcuts = unsafe { nil }
	}
	if !isnil(self.config_object) {
		mut config := unsafe { self.config_object }
		config.unref()
		self.config_object = unsafe { nil }
	}
	display := C.gdk_display_get_default()
	if !isnil(display) && !isnil(self.css_provider) {
		C.gtk_style_context_remove_provider_for_display(display, self.css_provider)
	}
	if !isnil(self.css_provider) {
		object_unref(GObject(self.css_provider))
		self.css_provider = unsafe { nil }
	}
	for provider in self.custom_css_providers {
		if !isnil(display) {
			C.gtk_style_context_remove_provider_for_display(display, provider)
		}
		object_unref(GObject(provider))
	}
	self.custom_css_providers.clear()
	self.windows.clear()
	self.runtime_bridge.action_fn = unsafe { nil }
	self.runtime_bridge.wakeup_fn = unsafe { nil }
	self.runtime_bridge.user_data = unsafe { nil }
	self.runtime_bridge.config.deinit()
	self.config.deinit()
}

// core returns the core app associated with this application. Not
// reference-counted; do not store. Mirrors `Application.core`.
pub fn (self &Application) core() &core.App {
	return self.core_app
}

// winproto returns the app winproto implementation. Mirrors
// `Application.winproto`.
pub fn (mut self Application) winproto() &WinProtoApp {
	return &self.winproto
}

// cgroup_base returns the cgroup base path, if any. Mirrors
// `Application.cgroupBase`.
pub fn (self &Application) cgroup_base() ?string {
	return self.transient_cgroup_base
}

// init_quick_terminal initializes the quick terminal at the app layer for the
// given window, delegating to the active windowing protocol backend. Mirrors
// the app-side of ghostty's quick-terminal setup
// (`priv.winproto.initQuickTerminal`).
pub fn (mut self Application) init_quick_terminal(mut apprt_window ApprtWindow) ! {
	self.winproto.init_quick_terminal(mut apprt_window)!
}

// ref increments the reference count of the Application GObject and returns
// the application. Mirrors `Common.ref`.
pub fn (mut self Application) ref() &Application {
	if !isnil(self.obj) {
		object_ref(self.obj)
	}
	return self
}

// unref decrements the reference count of the Application GObject. Mirrors
// the GObject `unref`.
pub fn (mut self Application) unref() {
	if !isnil(self.obj) {
		object_unref(self.obj)
	}
}

// --- Run loop -------------------------------------------------------------

// run runs the application. This replaces `gio.Application.run` so we can
// tightly integrate the event loop with libwitty. Mirrors `Application.run`.
pub fn (mut self Application) run() ! {
	// Acquire the default main context for the application.
	ctx := C.g_main_context_default()
	if !C.g_main_context_acquire(ctx) {
		return error('context acquire failed')
	}
	defer {
		// Ensure our timer source is removed.
		self.stop_quit_timer()
		self.stop_screenshot_timer()
		// Sync any remaining settings.
		C.g_settings_sync()
		// Clear out the event loop without blocking.
		for C.g_main_context_iteration(ctx, false) {
		}
		// Release the context so something else can use it.
		C.g_main_context_release(ctx)
	}

	// Register the application.
	if !isnil(self.obj) {
		mut err := GError(unsafe { nil })
		if !C.g_application_register(self.obj, unsafe { nil }, &err) {
			if !isnil(err) {
				C.g_error_free(err)
			}
			return error('application register failed')
		}
		if !isnil(err) {
			C.g_error_free(err)
		}
	}

	// Fire `activate` as part of the normal startup routine, but only if the
	// config allows an initial window (background launch otherwise).
	if self.config.initial_window && !isnil(self.obj) {
		C.g_application_activate(self.obj)
	}

	// If we are NOT the primary instance, we never run the loop.
	if !isnil(self.obj) && C.g_application_get_is_remote(self.obj) {
		log.debug('application is remote, exiting run loop after activation')
		return
	}

	// Tell systemd that we are ready.
	internal_os.ready()

	log.debug('entering runloop')
	defer {
		log.debug('exiting runloop')
	}
	self.running = true
	if self.screenshot.options.path != '' {
		self.start_screenshot_timer()
	}
	for self.running {
		C.g_main_context_iteration(ctx, true)

		// Tick the core Ghostty terminal app.
		if !isnil(self.core_app) {
			mut core_app := unsafe { self.core_app }
			core_app.tick(mut self.runtime_bridge)!
			self.dispatch_runtime_actions()!
		}

		// Check if we must quit based on the current state.
		must_quit := self.must_quit()
		if must_quit {
			// All must-quit scenarios do not need confirmation, and may make it
			// unsafe to even access app/surface memory, so exit immediately.
			self.quit_now()
		}
	}
	if self.screenshot.options.path != '' {
		if err := self.screenshot.failure { return err }
		if !self.screenshot.complete { return error('terminal closed before screenshot') }
	}
}

// must_quit computes whether the run loop should exit. Mirrors the `must_quit`
// block inside `Application.run`.
fn (self &Application) must_quit() bool {
	// If configured to always stay running, don't quit.
	if !self.config.quit_after_last_window_closed {
		return false
	}

	// If the quit timer has expired, quit.
	if self.quit_timer is QuitTimerExpired {
		log.debug('must_quit due to quit timer expired')
		return true
	}

	// If we have no windows attached to our app, also quit — but only when no
	// closed-delay is configured (with a delay we exit eventually via timer).
	if self.config.quit_after_last_window_closed_delay == none && self.requested_window
		&& !isnil(self.obj) {
		windows := C.gtk_application_get_windows(GtkApplication(self.obj))
		if isnil(windows) {
			log.debug('must_quit due to no app windows')
			return true
		}
	}

	return false
}

// quit starts the process to stop the run loop. It does not `exit`. Mirrors
// `Application.quit`.
pub fn (mut self Application) quit() {
	// If our run loop already exited then we're done.
	if !self.running {
		return
	}

	// If the core app doesn't need to confirm quit, exit immediately.
	if isnil(self.core_app) || !self.core_app.needs_confirm_quit() {
		self.quit_now()
		return
	}

	// Parent the prompt to the active application window when one exists.
	parent := self.active_window()
	mut dialog := close_confirmation_dialog_new(.app)
	dialog.set_canvas_enabled(gtk_canvas_styles_enabled(&self.config))
	C.g_signal_connect_data(dialog.dialog.obj, c'close-request', GCallback(voidptr(application_close_confirmed_cb)), voidptr(self), unsafe { nil }, 0)
	dialog.present(GtkWidget(parent))
}

fn application_close_confirmed_cb(dialog GObject, user_data voidptr) {
	_ = dialog
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Application(user_data) }
	self.quit_now()
}

// active_window returns the active window owned by this GtkApplication, or
// nil when none is focused.
fn (self &Application) active_window() GtkWindow {
	if isnil(self.obj) {
		return unsafe { nil }
	}
	windows := C.gtk_application_get_windows(GtkApplication(self.obj))
	for i in u32(0) .. list_length(windows) {
		window := GtkWindow(list_data_at(windows, i))
		if !isnil(window) && C.gtk_window_is_active(window) != 0 {
			return window
		}
	}
	return unsafe { nil }
}

// quit_now destroys all our windows and triggers the run loop exit. Mirrors
// `Application.quitNow`.
fn (mut self Application) quit_now() {
	// GtkApplication's window list contains only our windows, unlike the global
	// GTK toplevel list which may include nested IME/fcitx windows we do not own.
	if !isnil(self.obj) {
		windows := C.gtk_application_get_windows(GtkApplication(self.obj))
		mut owned := []GtkWindow{cap: int(list_length(windows))}
		for i in u32(0) .. list_length(windows) {
			window := GtkWindow(list_data_at(windows, i))
			if !isnil(window) {
				owned << window
			}
		}
		for window in owned {
			C.gtk_window_destroy(window)
		}
	}

	// Trigger our runloop exit.
	self.running = false
}

// --- Quit timer -----------------------------------------------------------

// start_quit_timer is called when there are no more open surfaces. Mirrors
// `Application.startQuitTimer`.
fn (mut self Application) start_quit_timer() {
	// Cancel any previous timer.
	self.stop_quit_timer()

	// No-op unless we quit after the last window closes.
	if !self.config.quit_after_last_window_closed {
		return
	}

	if delay := self.config.quit_after_last_window_closed_delay {
		self.quit_timer = QuitTimerActive{
			source: C.g_timeout_add(delay.as_milliseconds(), voidptr(handle_quit_timer_expired),
				voidptr(self))
		}
	} else {
		// If no delay is configured, treat the timer as immediately expired.
		self.quit_timer = QuitTimerExpired{}
	}
}

// handle_quit_timer_expired marks the one-shot GLib timeout as expired.
fn handle_quit_timer_expired(data voidptr) int {
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &Application(data) }
	self.quit_timer = QuitTimerExpired{}
	return 0
}

// stop_quit_timer is called when a new surface gets opened. Mirrors
// `Application.stopQuitTimer`.
fn (mut self Application) stop_quit_timer() {
	timer := self.quit_timer
	match timer {
		QuitTimerOff { return }
		QuitTimerExpired {}
		QuitTimerActive {
			if !C.g_source_remove(timer.source) {
				log.warn('unable to remove quit timer source=${timer.source}')
			}
		}
	}
	self.quit_timer = QuitTimerOff{}
}

// --- Action accelerators --------------------------------------------------

// sync_action_accelerators syncs all GTK menu accelerators from the keybind
// config. Mirrors `Application.syncActionAccelerators`.
fn (mut self Application) sync_action_accelerators() {
	self.sync_action_accelerator('app.quit', input.ActionQuit{})
	self.sync_action_accelerator('app.open-config', input.ActionOpenConfig{})
	self.sync_action_accelerator('app.reload-config', input.ActionReloadConfig{})
	self.sync_action_accelerator('win.toggle-inspector', input.ActionInspector{ value: .toggle })
	self.sync_action_accelerator('app.show-gtk-inspector', input.ActionShowGtkInspector{})
	self.sync_action_accelerator('win.toggle-command-palette', input.ActionToggleCommandPalette{})
	self.sync_action_accelerator('win.close', input.ActionCloseWindow{})
	self.sync_action_accelerator('win.new-window', input.ActionNewWindow{})
	self.sync_action_accelerator('win.new-tab', input.ActionNewTab{})
	close_this := input.ActionCloseTab{ value: .this }
	self.sync_action_accelerator('win.close-tab::this', close_this)
	self.sync_action_accelerator('tab.close::this', close_this)
	self.sync_action_accelerator('win.split-right', input.ActionNewSplit{ value: .right })
	self.sync_action_accelerator('win.split-down', input.ActionNewSplit{ value: .down })
	self.sync_action_accelerator('win.split-left', input.ActionNewSplit{ value: .left })
	self.sync_action_accelerator('win.split-up', input.ActionNewSplit{ value: .up })
	self.sync_action_accelerator('win.copy', input.ActionCopyToClipboard{ value: .mixed })
	self.sync_action_accelerator('win.paste', input.ActionPasteFromClipboard{})
	self.sync_action_accelerator('win.reset', input.ActionReset{})
	self.sync_action_accelerator('win.clear', input.ActionClearScreen{})
	self.sync_action_accelerator('win.prompt-surface-title', input.ActionPromptSurfaceTitle{})
	self.sync_action_accelerator('win.prompt-tab-title', input.ActionPromptTabTitle{})
	self.sync_action_accelerator('split-tree.new-split::left', input.ActionNewSplit{ value: .left })
	self.sync_action_accelerator('split-tree.new-split::right', input.ActionNewSplit{ value: .right })
	self.sync_action_accelerator('split-tree.new-split::up', input.ActionNewSplit{ value: .up })
	self.sync_action_accelerator('split-tree.new-split::down', input.ActionNewSplit{ value: .down })
}

// sync_action_accelerator clears the GTK accelerator for one detailed action,
// then installs the configured trigger when it can be represented by GTK.
fn (mut self Application) sync_action_accelerator(gtk_action string, action input.Action) {
	if isnil(self.obj) {
		return
	}
	mut no_accels := unsafe { []&char{len: 1, init: &char(0)} }
	C.gtk_application_set_accels_for_action(GtkApplication(self.obj), &char(gtk_action.str), no_accels.data)
	accel := self.accelerator_for_action(action) or { return }
	mut accels := []&char{cap: 2}
	accels << &char(accel.str)
	accels << &char(unsafe { nil })
	C.gtk_application_set_accels_for_action(GtkApplication(self.obj), &char(gtk_action.str), accels.data)
}

// accelerator_for_action performs the keybind reverse lookup and trigger
// conversion shared by every menu action.
fn (self &Application) accelerator_for_action(action input.Action) ?string {
	trigger := self.config.keybind.set.get_trigger(action) or { return none }
	return accel_from_trigger(trigger)
}

// --- Properties -----------------------------------------------------------

// get_config returns the configuration object for this application with its
// GObject reference count increased. The caller owns the returned reference.
// Mirrors `Application.getConfig`.
pub fn (mut self Application) get_config() &Config {
	if isnil(self.config_object) {
		panic('GhosttyApplication has no configuration object')
	}
	mut config := unsafe { self.config_object }
	return config.ref()
}

// set_config sets the configuration and re-applies config-derived state.
// Mirrors `Application.setConfig`.
fn (mut self Application) set_config(config configpkg.Config) {
	self.config.deinit()
	self.config = config
	self.runtime_bridge.config.deinit()
	self.runtime_bridge.config = config.clone()
	new_object := config_new(config)
	if !isnil(self.config_object) {
		mut old_object := unsafe { self.config_object }
		old_object.unref()
	}
	self.config_object = new_object
	if !isnil(self.global_shortcuts) {
		mut shortcuts := unsafe { self.global_shortcuts }
		shortcuts.set_config(self.config_object)
	}
	// notify "config" pspec -> prop_config.
	if !isnil(self.obj) {
		C.g_object_notify_by_pspec(self.obj, g_ghostty_application_pspec_config)
	} else {
		self.prop_config()
	}
	// Show our errors if we have any.
	self.show_config_errors_dialog()
}

fn application_config_notify_cb(obj voidptr, pspec voidptr, user_data voidptr) {
	_ = obj
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Application(user_data) }
		self.prop_config()
	}
}

// prop_config responds to a "config" property change. Mirrors ghostty's
// `propConfig`: sync menu accelerators and reload runtime + custom CSS.
fn (mut self Application) prop_config() {
	// Sync our accelerators for menu items.
	self.sync_action_accelerators()

	self.load_runtime_css()
	self.load_custom_css()
}

// application_runtime_css translates loadRuntimeCss, including both GTK
// version branches. Adwaita loads the four compiled stylesheet variants
// automatically from the application resource-base-path, as in Ghostty.
fn application_runtime_css(config &configpkg.Config, gtk_416 bool) string {
	mut css := ''
	background := config.window_titlebar_background or { config.background }
	foreground := config.window_titlebar_foreground or { config.foreground }
	bell_tint := if gtk_416 { 'color-mix(in srgb, var(--accent-color), transparent 50%)' } else {
		'rgba(58, 148, 74, 0.5)'
	}
	success_tint := if gtk_416 { 'color-mix(in srgb, var(--success-bg-color), transparent 50%)' } else {
		'rgba(38, 162, 105, 0.5)'
	}
	error_tint := if gtk_416 { 'color-mix(in srgb, var(--error-bg-color), transparent 50%)' } else {
		'rgba(192, 28, 40, 0.5)'
	}

	if gtk_416 {
		css += '/*\n * Child Exited Overlay\n */\n\n'
		css += '.child-exited.normal revealer widget {\n  background-color: ${success_tint};\n}\n\n'
		css += '.child-exited.abnormal revealer widget {\n  background-color: ${error_tint};\n}\n\n'
		css += '/*\n * Surface\n */\n\n'
		css += '.surface progressbar.error trough progress {\n  background-color: ${error_tint};\n}\n\n'
		css += '.surface .bell-overlay {\n  background-color: ${bell_tint};\n  border-color: ${bell_tint};\n}\n\n'
		css += '/*\n * Splits\n */\n\n'
		css += '.window .split paned > separator {\n  background-color: color-mix(\n    in srgb,\n    var(--window-bg-color),\n    transparent 0%\n  );\n}\n\n'
		if config.window_theme == .witty {
			css += ':root {\n'
			css += '  --ghostty-fg: rgb(${foreground.r},${foreground.g},${foreground.b});\n'
			css += '  --ghostty-bg: rgb(${background.r},${background.g},${background.b});\n'
			css += '  --headerbar-fg-color: var(--ghostty-fg);\n  --headerbar-bg-color: var(--ghostty-bg);\n'
			css += '  --headerbar-backdrop-color: oklab(from var(--headerbar-bg-color) calc(l * 0.9) a b / alpha);\n'
			css += '  --overview-fg-color: var(--ghostty-fg);\n  --overview-bg-color: var(--ghostty-bg);\n'
			css += '  --popover-fg-color: var(--ghostty-fg);\n  --popover-bg-color: var(--ghostty-bg);\n'
			css += '  --window-fg-color: var(--ghostty-fg);\n  --window-bg-color: var(--ghostty-bg);\n}\n'
			css += 'windowhandle {\n  background-color: var(--headerbar-bg-color);\n  color: var(--headerbar-fg-color);\n}\n'
			css += 'windowhandle:backdrop {\n background-color: var(--headerbar-backdrop-color);\n}\n'
		}
	} else if config.window_theme == .witty {
		css += 'windowhandle {\n  background-color: rgb(${background.r},${background.g},${background.b});\n'
		css += '  color: rgb(${foreground.r},${foreground.g},${foreground.b});\n}\n'
		css += 'windowhandle:backdrop {\n background-color: oklab(from rgb(${background.r},${background.g},${background.b}) calc(l * 0.9) a b / alpha);\n}\n'
	}

	css += '.surface .bell-overlay.bell-canvas {\n color: ${bell_tint};\n background-color: transparent;\n border-color: transparent;\n}\n'
	css += '.child-exited.child-exited-canvas revealer widget { background-color: transparent; }\n'
	css += '.child-exited.normal .child-exited-fill { color: ${success_tint}; }\n'
	css += '.child-exited.abnormal .child-exited-fill { color: ${error_tint}; }\n'

	fill := config.unfocused_split_fill or { config.background }
	css += 'widget.unfocused-split {\n opacity: ${1.0 - config.unfocused_split_opacity:.2f};\n'
	// Keep background-color available to custom stylesheets that override it.
	use_canvas := gtk_canvas_styles_enabled(config)
	css += split_background_style(fill, use_canvas, 'background-color') + '}\n'
	if divider := config.split_divider_color {
		css += '.window .split paned > separator {\n  color: rgb(${divider.r},${divider.g},${divider.b});\n'
		css += split_background_style(divider, use_canvas, 'background') + '}\n'
	}
	if font_family := config.window_title_font_family {
		css += '.window headerbar {\n  font-family: "${font_family}";\n}\n'
	}
	return css
}

fn (mut self Application) load_runtime_css() {
	if isnil(self.css_provider) {
		return
	}
	css := application_runtime_css(&self.config, gtk_runtime_at_least(4, 16, 0))
	C.gtk_css_provider_load_from_data(self.css_provider, &char(css.str), int(css.len))
}

fn (mut self Application) load_custom_css() {
	display := C.gdk_display_get_default()
	if isnil(display) {
		log.warn('unable to get display')
		return
	}

	for provider in self.custom_css_providers {
		C.gtk_style_context_remove_provider_for_display(display, provider)
		object_unref(GObject(provider))
	}
	self.custom_css_providers.clear()

	css_file_size_limit := u64(5 * 1024 * 1024)
	for entry in self.config.gtk_custom_css.items {
		path := match entry {
			configpkg.PathOptional { entry.path }
			configpkg.PathRequired { entry.path }
		}
		optional := entry is configpkg.PathOptional
		if !os.exists(path) {
			if !optional {
				log.warn('error opening gtk-custom-css file ${path}: file not found')
			}
			continue
		}
		log.info('loading gtk-custom-css path=${path}')
		if os.file_size(path) > css_file_size_limit {
			log.warn('gtk-custom-css file ${path} was larger than 5 MiB')
			continue
		}
		contents := os.read_bytes(path) or {
			log.warn('error reading gtk-custom-css file ${path}: ${err}')
			continue
		}
		provider := C.gtk_css_provider_new()
		if isnil(provider) {
			log.warn('unable to create CSS provider for ${path}')
			continue
		}
		C.g_signal_connect_data(provider, c'parsing-error', GCallback(voidptr(application_css_parsing_error_cb)), voidptr(self), unsafe { nil }, 0)
		self.custom_css_providers << provider
		C.gtk_css_provider_load_from_data(provider, &char(contents.data), int(contents.len))
		C.gtk_style_context_add_provider_for_display(display, provider, gtk_style_provider_priority_user)
	}
}

fn application_css_parsing_error_cb(provider GtkCssProvider, section voidptr, err GError, data voidptr) {
	_ = provider
	_ = data
	if isnil(err) {
		log.warn('css parsing failed')
		return
	}
	c_err := unsafe { &C.GError(err) }
	message := if isnil(c_err.message) {
		'unknown error'
	} else {
		unsafe { cstring_to_vstring(c_err.message) }
	}
	domain_ptr := C.g_quark_to_string(c_err.domain)
	domain := if isnil(domain_ptr) {
		'unknown-domain'
	} else {
		unsafe { cstring_to_vstring(domain_ptr) }
	}
	mut location := 'unknown location'
	if !isnil(section) {
		location_ptr := C.gtk_css_section_to_string(section)
		if !isnil(location_ptr) {
			location = unsafe { cstring_to_vstring(location_ptr) }
			C.g_free(location_ptr)
		}
	}
	if gtk_at_least(4, 16, 0) && !isnil(section) {
		bytes := C.witty_gtk_css_section_get_bytes(section)
		if !isnil(bytes) {
			mut length := uint(0)
			ptr := C.g_bytes_get_data(bytes, &length)
			if !isnil(ptr) && length <= uint(max_int) {
				contents := unsafe { tos(&u8(ptr), int(length)) }.clone()
				log.warn('css parsing failed at ${location}: ${domain} ${c_err.code} ${message}\n${contents}')
				return
			}
		}
	}
	log.warn('css parsing failed at ${location}: ${domain} ${c_err.code} ${message}')
}

// show_config_errors_dialog shows the config errors dialog if the config has
// diagnostics. Mirrors `Application.showConfigErrorsDialog`.
fn (mut self Application) show_config_errors_dialog() {
	dialog_obj := self.config_errors_dialog.get()
	if !isnil(dialog_obj) {
		defer {
			object_unref(dialog_obj)
		}
		if existing := config_errors_dialog_from_object(dialog_obj) {
			mut dialog := unsafe { existing }
			dialog.set_config(?&Config(self.config_object))
			if self.config_object.has_diagnostics() {
				dialog.present(none)
			} else {
				dialog.close()
			}
			return
		}
		self.config_errors_dialog.set(unsafe { nil })
	}
	if isnil(self.config_object) || !self.config_object.has_diagnostics() {
		return
	}

	mut dialog := config_errors_dialog_new(self.config_object)
	C.g_signal_connect_data(dialog.dialog.obj, c'reload-config', GCallback(voidptr(application_config_errors_reload_cb)), voidptr(self), unsafe { nil }, 0)
	self.config_errors_dialog.set(dialog.dialog.obj)
	dialog.present(none)
}

fn application_config_errors_reload_cb(dialog GObject, data voidptr) {
	_ = dialog
	if isnil(data) {
		return
	}
	mut self := unsafe { &Application(data) }
	// The response handler closes this dialog after emitting the signal. Do not
	// retain it for a later configuration update.
	self.config_errors_dialog.set(unsafe { nil })
	self.reload_config(apprt.Target(apprt.AppTarget{}), false) or {
		log.warn('error reloading config: ${err}')
	}
}

// --- Libghostty callbacks -------------------------------------------------

fn application_runtime_action_cb(data voidptr, action apprt.RuntimeAction) !bool {
	if isnil(data) {
		return false
	}
	mut self := unsafe { &Application(data) }
	return self.perform_action(action.target, action.action, action.data)!
}

fn application_runtime_wakeup_cb(data voidptr) {
	if isnil(data) {
		return
	}
	self := unsafe { &Application(data) }
	self.wakeup()
}

// wakeup wakes up the GTK event loop. Mirrors `Application.wakeup`.
pub fn (self &Application) wakeup() {
	C.g_main_context_wakeup(C.g_main_context_default())
}

// --- Virtual methods (GObject vfunc overrides) ----------------------------
//
// Ghostty installs these through subclass vfuncs. The V wrapper connects the
// corresponding startup/activate GApplication signals and owns disposal.

// startup performs application startup: set as default, setup the event loop
// backend, style manager, signal handlers, action map, global shortcuts, and
// cgroup. Mirrors the `startup` vfunc.
fn (mut self Application) startup() {
	log.debug('startup')

	// Set ourselves as the default application.
	if !isnil(self.obj) {
		C.g_application_set_default(self.obj)
	}

	// Setup our event loop backend (libxev) preference.
	self.startup_xev()

	// Setup our style manager (light/dark mode).
	self.startup_style_manager()

	// Setup some signal handlers.
	self.startup_signals()

	// Setup our action map.
	self.startup_action_map()

	// Setup our global shortcuts.
	self.startup_global_shortcuts()

	// Setup our cgroup for the application.
	self.startup_cgroup() or {
		self.record_cgroup_startup_error(err)
	}

	// Show config diagnostics if any.
	self.show_config_errors_dialog()
}

// record_cgroup_startup_error adds the startup failure to the configuration
// diagnostics that back the GTK error dialog. Witty retains both the core
// value and its GObject wrapper, so both views must receive the same source
// diagnostic.
fn (mut self Application) record_cgroup_startup_error(err IError) {
	message := 'cgroup initialization failed: ${err}'
	self.config.add_diagnostic_fmt(message)
	if !isnil(self.config_object) {
		mut config := unsafe { self.config_object }
		mut inner := config.get_mut()
		inner.add_diagnostic_fmt(message)
	}
}

// Configure libxev to use a specific backend.
//
// This must be called before any other xev APIs are used.
fn (mut self Application) startup_xev() {
	// If our backend is auto then we have no setup to do.
	if self.config.async_backend == .auto {
		return
	}

	// Setup our event loop backend to the preferred method
	result := match self.config.async_backend {
		.auto { panic('unreachable') }
		.epoll { xev.prefer(.epoll) }
		.io_uring { xev.prefer(.io_uring) }
	}

	if result {
		log.info('libxev manual backend=${xev.backend()}')
	} else {
		log.warn('libxev manual backend failed, using default=${xev.backend()}')
	}
}

// startup_style_manager sets up the initial light/dark mode from config and
// registers a listener for changes. Mirrors `Application.startupStyleManager`.
fn (mut self Application) startup_style_manager() {
	if isnil(self.obj) {
		return
	}
	style := C.adw_application_get_style_manager(AdwApplication(self.obj))

	// Compute the initial color scheme from the window theme config.
	scheme := match self.config.window_theme {
		.auto, .witty {
			// Choose light/dark from the perceived luminance of the background.
			if perceived_luminance(self.config.background) > 0.5 {
				AdwColorScheme.prefer_light
			} else {
				AdwColorScheme.prefer_dark
			}
		}
		.system {
			AdwColorScheme.prefer_light
		}
		.dark {
			AdwColorScheme.force_dark
		}
		.light {
			AdwColorScheme.force_light
		}
	}
	C.adw_style_manager_set_color_scheme(style, int(scheme))

	C.g_signal_connect_data(style, c'notify::dark', GCallback(voidptr(application_style_manager_dark_cb)), voidptr(self), unsafe { nil }, 0)
	self.handle_style_manager_dark(style)
}

// startup_signals sets up unix signal handlers (SIGUSR2 -> reload config).
// Mirrors `Application.startupSignals`.
fn (mut self Application) startup_signals() {
	if self.signal_source != none {
		return
	}
	self.signal_source = C.g_unix_signal_add(sigusr2, voidptr(application_sigusr2_cb), voidptr(self))
}

fn application_sigusr2_cb(user_data voidptr) int {
	if isnil(user_data) {
		return 1
	}
	mut self := unsafe { &Application(user_data) }
	log.info('received SIGUSR2, reloading configuration')
	self.reload_config(apprt.Target(apprt.AppTarget{}), false) or {
		log.warn('error reloading config: ${err}')
	}
	return 1
}

// startup_action_map registers our GActions (new-window, open-config, quit,
// reload-config, present-surface, ...). Mirrors `Application.startupActionMap`.
fn (mut self Application) startup_action_map() {
	if isnil(self.obj) {
		return
	}
	string_array_type := C.g_variant_type_new(c'as')
	u64_type := C.g_variant_type_new(c't')
	actions := application_action_descriptors(string_array_type, u64_type)
	add_to_map(voidptr(self), GActionMap(self.obj), actions)
	C.g_variant_type_free(string_array_type)
	C.g_variant_type_free(u64_type)
}

// application_action_descriptors is the exact pinned application action table.
fn application_action_descriptors(string_array_type GVariantType, u64_type GVariantType) []Action {
	return [
		Action.init('new-window', GCallback(voidptr(application_action_new_window_cb)), unsafe { nil }),
		Action.init('new-window-command', GCallback(voidptr(application_action_new_window_cb)), string_array_type),
		Action.init('open-config', GCallback(voidptr(application_action_open_config_cb)), unsafe { nil }),
		Action.init('present-surface', GCallback(voidptr(application_action_present_surface_cb)), u64_type),
		Action.init('quit', GCallback(voidptr(application_action_quit_cb)), unsafe { nil }),
		Action.init('reload-config', GCallback(voidptr(application_action_reload_config_cb)), unsafe { nil }),
	]
}

fn application_action_new_window_cb(action GSimpleAction, parameter GVariant, user_data voidptr) {
	mut self := unsafe { &Application(user_data) }
	self.action_new_window(action, parameter)
}

// action_new_window queues a new window. The `new-window-command` variant's
// string-array parameter is validated and each command argument is logged by
// the pinned source.
pub fn (mut self Application) action_new_window(action GSimpleAction, parameter GVariant) {
	_ = action
	if !isnil(parameter) {
		as_variant_type := C.g_variant_type_new(c'as')
		// ensure that the supplied parameter is an array of strings
		if !C.g_variant_is_of_type(parameter, as_variant_type) {
			type_string := unsafe { cstring_to_vstring(C.g_variant_get_type_string(parameter)) }
			log.warn('parameter is of type ${type_string}')
		} else {
			string_variant_type := C.g_variant_type_new(c's')
			iter := C.g_variant_iter_new(parameter)
			for {
				value := C.g_variant_iter_next_value(iter)
				if isnil(value) {
					break
				}
				// The outer `as` check guarantees this, but retain Ghostty's
				// defensive element check at the native boundary.
				if C.g_variant_is_of_type(value, string_variant_type) {
					mut length := uint(0)
					argument := C.g_variant_get_string(value, &length)
					if !isnil(argument) {
						log.debug('new-window command argument: ${unsafe { tos(&u8(argument), int(length)) }}')
					}
				}
				C.g_variant_unref(value)
			}
			C.g_variant_iter_free(iter)
			C.g_variant_type_free(string_variant_type)
		}
		C.g_variant_type_free(as_variant_type)
	}

	mut mailbox := self.core().mailbox
	_ = mailbox.push(core.Message(core.NewWindowMsg{}), datastruct.blocking_queue_forever)
}

fn application_action_open_config_cb(action GSimpleAction, parameter GVariant, user_data voidptr) {
	mut self := unsafe { &Application(user_data) }
	self.action_open_config(action, parameter)
}

// action_open_config queues a request to open the configuration file. The
// action and parameter are part of the GAction callback contract and are not
// otherwise used by the pinned implementation.
pub fn (mut self Application) action_open_config(action GSimpleAction, parameter GVariant) {
	_ = action
	_ = parameter
	mut mailbox := self.core().mailbox
	_ = mailbox.push(core.Message(core.OpenConfigMsg{}), datastruct.blocking_queue_forever)
}

fn application_action_present_surface_cb(action GSimpleAction, parameter GVariant, user_data voidptr) {
	_ = action
	if isnil(parameter) {
		return
	}
	type_ := C.g_variant_type_new(c't')
	is_u64 := C.g_variant_is_of_type(parameter, type_)
	C.g_variant_type_free(type_)

	// Make sure that we've receiived a u64 from the system.
	if !is_u64 {
		return
	}

	// Convert that u64 to pointer to a core surface. A value of zero
	// means that there was no target surface for the notification so
	// we don't focus any surface.
	ptr_int := C.g_variant_get_uint64(parameter)
	if ptr_int == 0 {
		return
	}
	surface := unsafe { &core.Surface(voidptr(uint(ptr_int))) }

	// Send a message through the core app mailbox rather than presenting the
	// surface directly so that it can validate that the surface pointer is
	// valid. We could get an invalid pointer if a desktop notification outlives
	// a Ghostty instance and a new one starts up, or there are multiple Ghostty
	// instances running.
	self := unsafe { &Application(user_data) }
	mut mailbox := self.core().mailbox
	_ = mailbox.push(core.Message(core.SurfaceMessageMsg{
		surface: surface
		message: apprt.SurfaceMessagePresentSurface{}
	}), datastruct.blocking_queue_forever)
}

fn application_action_quit_cb(action GSimpleAction, parameter GVariant, user_data voidptr) {
	_ = action
	_ = parameter
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Application(user_data) }
	if isnil(self.core_app) {
		return
	}
	mut core_app := unsafe { self.core_app }
	core_app.perform_action(mut self.runtime_bridge, input.ActionQuit{}) or {
		log.warn('error quitting err=${err}')
		return
	}
	self.dispatch_runtime_actions() or {
		log.warn('error quitting err=${err}')
	}
}

fn application_action_reload_config_cb(action GSimpleAction, parameter GVariant, user_data voidptr) {
	_ = action
	_ = parameter
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Application(user_data) }
	if isnil(self.core_app) {
		return
	}
	mut core_app := unsafe { self.core_app }
	core_app.perform_action(mut self.runtime_bridge, input.ActionReloadConfig{}) or {
		log.warn('error reloading config err=${err}')
		return
	}
	self.dispatch_runtime_actions() or {
		log.warn('error reloading config err=${err}')
	}
}

// reload_config performs the hard/soft load used by the application action.
// A soft reload reapplies the current loaded config; a hard reload reads it
// again from Ghostty's normal config sources.
fn (mut self Application) reload_config(target apprt.Target, soft bool) ! {
	internal_os.reloading()
	defer {
		internal_os.ready()
	}
	mut config := if soft { self.config.clone() } else { configpkg.Config.load()! }
	defer {
		config.deinit()
	}
	match target {
		apprt.SurfaceTarget {
			mut surface := surface_from_target(target) or {
				return error('reload target surface is unavailable')
			}
			mut core_surface := surface.core_surface
			core_surface.update_config(&config)!
		}
		apprt.AppTarget {
			if isnil(self.core_app) {
				self.set_config(config.clone())
				return
			}
			mut core_app := unsafe { self.core_app }
			core_app.update_config(mut self.runtime_bridge, &config)!
			self.dispatch_runtime_actions()!
		}
	}
}

// startup_global_shortcuts sets up desktop-portal global shortcuts. Mirrors
// `Application.startupGlobalShortcuts`.
fn (mut self Application) startup_global_shortcuts() {
	if isnil(self.global_shortcuts) {
		return
	}
	mut shortcuts := unsafe { self.global_shortcuts }
	shortcuts.set_trigger_handler(application_global_shortcut_trigger, voidptr(self))
	if !isnil(self.obj) {
		shortcuts.set_dbus_connection(C.g_application_get_dbus_connection(self.obj))
	}
	if !isnil(self.config_object) {
		shortcuts.set_config(self.config_object)
	}
}

fn application_global_shortcut_trigger(action input.Action, user_data voidptr) {
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Application(user_data) }
	if isnil(self.core_app) {
		return
	}
	mut core_app := unsafe { self.core_app }
	core_app.perform_all_action(mut self.runtime_bridge, action) or {
		log.warn('failed to perform action=${err}')
		return
	}
	self.dispatch_runtime_actions() or {
		log.warn('failed to perform action=${err}')
	}
}

// startup_cgroup sets up the systemd cgroup for the application, if enabled.
// Mirrors `Application.startupCgroup`.
fn (mut self Application) startup_cgroup() ! {
	flags := if isnil(self.obj) {
		g_application_default_flags
	} else {
		C.g_application_get_flags(self.obj)
	}
	if !cgroup_isolation_enabled(self.config.linux_cgroup, flags) {
		return
	}

	if isnil(self.obj) {
		if self.config.linux_cgroup_hard_fail {
			return error('DbusConnectionFailed')
		}
		return
	}
	dbus := C.g_application_get_dbus_connection(self.obj)
	if isnil(dbus) {
		if self.config.linux_cgroup_hard_fail {
			return error('DbusConnectionFailed')
		}
		return
	}

	path := cgroup_init(dbus, Options{
		memory_high: self.config.linux_cgroup_memory_limit
		pids_max:    self.config.linux_cgroup_processes_limit
	}) or {
		if self.config.linux_cgroup_hard_fail {
			return error('CgroupInitFailed')
		}
		return
	}
	self.transient_cgroup_base = path
}

// cgroup_isolation_enabled applies Ghostty's mode gate. A GApplication with
// NON_UNIQUE set is not a single-instance process.
fn cgroup_isolation_enabled(mode configpkg.LinuxCgroup, app_flags int) bool {
	return match mode {
		.never { false }
		.always { true }
		.single_instance { app_flags & g_application_non_unique == 0 }
	}
}

// activate handles the GApplication "activate" signal: queue a new window.
// Mirrors the `activate` vfunc.
fn (mut self Application) activate() {
	// Queue a new window
	mut mailbox := self.core().mailbox
	_ = mailbox.push(core.Message(core.NewWindowMsg{}), datastruct.blocking_queue_forever)
}

// dispose releases the config errors dialog and signal source. Mirrors the
// `dispose` vfunc.
fn (mut self Application) dispose() {
	if self.disposed {
		return
	}
	self.disposed = true
	dialog_obj := self.config_errors_dialog.get()
	if !isnil(dialog_obj) {
		if existing := config_errors_dialog_from_object(dialog_obj) {
			mut dialog := unsafe { existing }
			dialog.close()
		}
		object_unref(dialog_obj)
	}
	self.config_errors_dialog.set(unsafe { nil })

	if v := self.signal_source {
		if !C.g_source_remove(v) {
			log.warn('unable to remove signal source')
		}
		self.signal_source = none
	}
}

// finalize force-deinitializes and chains to the parent finalizer. Mirrors the
// `finalize` vfunc.
fn (mut self Application) finalize() {
	self.deinit()
}

// --- Signal handlers ------------------------------------------------------

// handle_style_manager_dark propagates a light/dark color scheme change to the
// core app and all surfaces. Mirrors `Application.handleStyleManagerDark`.
fn (mut self Application) handle_style_manager_dark(style voidptr) {
	scheme := if !C.adw_style_manager_get_dark(style) {
		apprt.ColorScheme.light
	} else {
		apprt.ColorScheme.dark
	}
	log.debug('style manager changed scheme=${scheme}')
	if !isnil(self.core_app) {
		mut core_app := unsafe { self.core_app }
		core_app.color_scheme_event(mut self.runtime_bridge, scheme) or {
			log.warn('error updating app color scheme err=${err}')
		}
		self.dispatch_runtime_actions() or {
			log.warn('error updating app color scheme err=${err}')
		}
		core_app.color_scheme_surfaces(scheme)
	}
	if gtk_runtime_at_least(4, 20, 0) {
		gtk_scheme := application_interface_color_scheme(scheme)
		if !isnil(self.css_provider) {
			C.g_object_set(GObject(self.css_provider), c'prefers-color-scheme', int(gtk_scheme),
				unsafe { nil })
		}
		for provider in self.custom_css_providers {
			if !isnil(provider) {
				C.g_object_set(GObject(provider), c'prefers-color-scheme', int(gtk_scheme),
					unsafe { nil })
			}
		}
	}
}

fn application_style_manager_dark_cb(style voidptr, pspec &C.GParamSpec, user_data voidptr) {
	_ = pspec
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Application(user_data) }
	self.handle_style_manager_dark(style)
}

// --- apprt API ------------------------------------------------------------

// perform_action performs an apprt action. Mirrors `Application.performAction`.
pub fn (mut self Application) perform_action(target apprt.Target, action apprt.ActionKey, data apprt.ActionValue) !bool {
	match action {
		.close_tab {
			if data is apprt.CloseTabMode {
				surface := surface_from_target(target) or { return false }
				mode := data.str()
				return C.gtk_widget_activate_action_variant(surface.widget, c'tab.close',
					C.g_variant_new_string(&char(mode.str)))
			}
		}
		.close_window {
			surface := surface_from_target(target) or { return false }
			return C.gtk_widget_activate_action_variant(surface.widget, c'win.close', unsafe { nil })
		}
		.config_change {
			if data is apprt.ConfigChange {
				if unsafe { data.config == nil } {
					return true
				}
				match target {
					apprt.AppTarget {
						self.set_config(data.config.clone())
					}
					apprt.SurfaceTarget {
						mut surface := surface_from_target(target) or { return false }
						surface.set_owned_config(data.config.clone())
					}
				}
				return true
			}
		}
		.desktop_notification {
			if data is apprt.DesktopNotificationValue {
				match target {
					apprt.AppTarget {
						self.send_desktop_notification(data.title, data.body)
					}
					apprt.SurfaceTarget {
						surface := surface_from_target(target) or { return false }
						surface.send_desktop_notification(data.title, data.body)
					}
				}
				return true
			}
		}
		.equalize_splits {
			if target is apprt.AppTarget {
				log.warn('equalize splits to app is unexpected')
				return false
			}
			surface := surface_from_target(target) or { return false }
			return C.gtk_widget_activate_action_variant(surface.widget, c'split-tree.equalize',
				unsafe { nil })
		}
		.goto_split {
			if data is apprt.GotoSplit {
				surface := surface_from_target(target) or { return false }
				mut tree := split_tree_from_surface(surface) or {
					log.warn('surface is not in a split tree, ignoring goto_split')
					return false
				}
				return tree.goto_(goto_split_target(data))
			}
		}
		.goto_window {
			if data is apprt.GotoWindow {
				return self.goto_window(data)
			}
		}
		.goto_tab {
			if data is apprt.GotoTab {
				surface := surface_from_target(target) or { return false }
				mut window := window_from_surface(surface) or {
					log.warn('surface is not in a window, ignoring new_tab')
					return false
				}
				raw := int(data)
				selection := if raw == int(apprt.GotoTab.previous) {
					SelectTab(SelectTabPrevious{})
				} else if raw == int(apprt.GotoTab.next) {
					SelectTab(SelectTabNext{})
				} else if raw == int(apprt.GotoTab.last) {
					SelectTab(SelectTabLast{})
				} else if raw >= 0 {
					SelectTab(SelectTabN{ n: uint(raw) })
				} else {
					return false
				}
				return window.select_tab(selection)
			}
		}
		.initial_size {
			if data is apprt.InitialSize {
				mut surface := surface_from_target(target) or { return false }
				surface.set_default_size(Size{
					width:  data.width
					height: data.height
				})
				return true
			}
		}
		.inspector {
			if data is apprt.InspectorAction {
				mut surface := surface_from_target(target) or { return false }
				return surface.control_inspector(data)
			}
		}
		.key_sequence {
			if data is apprt.KeySequence {
				if target is apprt.AppTarget {
					log.warn('key_sequence action to app is unexpected')
					return false
				}
				mut surface := surface_from_target(target) or { return false }
				surface.key_sequence_action(data)
				return true
			}
		}
		.key_table {
			if data is apprt.KeyTable {
				if target is apprt.AppTarget {
					log.warn('key_table action to app is unexpected')
					return false
				}
				mut surface := surface_from_target(target) or { return false }
				surface.key_table_action(data)
				return true
			}
		}
		.mouse_over_link {
			if data is apprt.MouseOverLink {
				if target is apprt.AppTarget {
					log.warn('mouse over link to app is unexpected')
					return true
				}
				if mut surface := surface_from_target(target) {
					surface.set_mouse_hover_url(if data.url.len > 0 {
						?string(data.url)
					} else {
						?string(none)
					})
				}
				return true
			}
		}
		.mouse_shape {
			if data is terminal.MouseShape {
				if target is apprt.AppTarget {
					log.warn('mouse shape to app is unexpected')
					return true
				}
				if mut surface := surface_from_target(target) {
					surface.set_mouse_shape(data)
				}
				return true
			}
		}
		.mouse_visibility {
			if data is apprt.MouseVisibility {
				if target is apprt.AppTarget {
					log.warn('mouse visibility to app is unexpected')
					return true
				}
				if mut surface := surface_from_target(target) {
					surface.set_mouse_hidden(data == .hidden)
				}
				return true
			}
		}
		.move_tab {
			if data is apprt.MoveTab {
				mut surface := surface_from_target(target) or { return false }
				mut window := window_from_surface(surface) or {
					log.warn('surface is not in a window, ignoring new_tab')
					return false
				}
				mut rt_surface := surface.rt()
				return window.move_tab(rt_surface, data.amount)
			}
		}
		.new_split {
			if data is apprt.SplitDirection {
				if target is apprt.AppTarget {
					log.warn('new split to app is unexpected')
					return false
				}
				surface := surface_from_target(target) or { return false }
				direction := data.str()
				return C.gtk_widget_activate_action_variant(surface.widget, c'split-tree.new-split',
					C.g_variant_new_string(&char(direction.str)))
			}
		}
		.new_tab {
			if target is apprt.AppTarget {
				log.warn('new tab to app is unexpected')
				return false
			}
			surface := surface_from_target(target) or { return false }
			mut window := window_from_surface(surface) or {
				log.warn('surface is not in a window, ignoring new_tab')
				return false
			}
			window.new_tab(surface.core_surface)
			return true
		}
		.new_window {
			match target {
				apprt.SurfaceTarget {
					if isnil(target.surface) {
						return self.new_window(none)
					}
					return self.new_window(unsafe { &core.Surface(target.surface) })
				}
				else {
					return self.new_window(none)
				}
			}
		}
		.quit {
			self.quit()
			return true
		}
		.quit_timer {
			if data is apprt.QuitTimer {
				match data {
					.start { self.start_quit_timer() }
					.stop { self.stop_quit_timer() }
				}
				return true
			}
		}
		.reload_config {
			if data is apprt.ReloadConfig {
				self.reload_config(target, data.soft)!
				return true
			}
		}
		.open_config {
			path := configpkg.open_path() or {
				log.warn('error getting config file path: ${err}')
				return false
			}
			// The action was resolved once the editable path was found. Ghostty's
			// openUrl helper logs launcher failures but deliberately does not turn
			// them into an unhandled action, which would pass the key through.
			internal_os.open(.text, path) or {
				log.warn('unable to open url: ${err}')
			}
			return true
		}
		.open_url {
			if data is apprt.OpenUrl {
				internal_os.open(data.kind, data.url) or {
					log.warn('unable to open url: ${err}')
				}
				return true
			}
		}
		.pwd {
			if data is apprt.PwdValue {
				if target is apprt.AppTarget {
					log.warn('pwd to app is unexpected')
					return true
				}
				if mut surface := surface_from_target(target) {
					surface.set_pwd(data.pwd)
				}
				return true
			}
		}
		.present_terminal {
			surface := surface_from_target(target) or { return false }
			surface.present()
			return true
		}
		.progress_report {
			if data is osc.ProgressReport {
				mut surface := surface_from_target(target) or { return false }
				surface.set_progress_report(data)
				return true
			}
		}
		.prompt_title {
			if data is apprt.PromptTitle {
				mut surface := surface_from_target(target) or { return false }
				match data {
					.surface { surface.prompt_title() }
					.tab {
						widget := C.gtk_widget_get_ancestor(surface.widget, tab_get_type())
						tab := tab_from_widget(widget) or { return false }
						tab.prompt_title()
					}
				}
				return true
			}
		}
		.render {
			if surface := surface_from_target(target) {
				surface.redraw()
			}
			return true
		}
		.resize_split {
			if data is apprt.ResizeSplit {
				if target is apprt.AppTarget {
					log.warn('resize_split to app is unexpected')
					return false
				}
				surface := surface_from_target(target) or { return false }
				mut tree := split_tree_from_surface(surface) or {
					log.warn('surface is not in a split tree, ignoring resize_split')
					return false
				}
				if !tree.get_is_split() {
					return false
				}
				direction := match data.direction {
					.up { datastruct.Direction.up }
					.down { datastruct.Direction.down }
					.left { datastruct.Direction.left }
					.right { datastruct.Direction.right }
				}
				return tree.resize(direction, data.amount)
			}
		}
		.ring_bell {
			if mut surface := surface_from_target(target) {
				surface.set_bell_ringing(true)
			}
			return true
		}
		.scrollbar {
			if data is terminal.Scrollbar {
				if mut surface := surface_from_target(target) {
					surface.set_scrollbar(data)
				}
				return true
			}
		}
		.set_title {
			if data is apprt.SetTitle {
				if target is apprt.AppTarget {
					log.warn('set_title to app is unexpected')
					return true
				}
				if mut surface := surface_from_target(target) {
					surface.set_title(data.title)
				}
				return true
			}
		}
		.show_child_exited {
			if data is apprt.ChildExited {
				if self.screenshot.options.path != '' && data.exit_code == 0 {
					return true
				}
				mut surface := surface_from_target(target) or { return false }
				return surface.child_exited(data)
			}
		}
		.show_gtk_inspector {
			C.gtk_window_set_interactive_debugging(true)
			return true
		}
		.size_limit {
			if data is apprt.SizeLimit {
				mut surface := surface_from_target(target) or { return false }
				surface.set_min_size(Size{
					width:  data.min_width
					height: data.min_height
				})
				return true
			}
		}
		.toggle_maximize {
			if surface := surface_from_target(target) {
				surface.toggle_maximize()
			}
			return true
		}
		.toggle_fullscreen {
			if surface := surface_from_target(target) {
				surface.toggle_fullscreen()
			}
			return true
		}
		.toggle_quick_terminal {
			return self.toggle_quick_terminal()
		}
		.toggle_tab_overview {
			surface := surface_from_target(target) or { return false }
			mut window := window_from_surface(surface) or {
				log.warn('surface is not in a window, ignoring new_tab')
				return false
			}
			window.toggle_tab_overview()
			return true
		}
		.toggle_window_decorations {
			surface := surface_from_target(target) or { return false }
			mut window := window_from_surface(surface) or {
				log.warn('surface is not in a window, ignoring toggle_window_decorations')
				return false
			}
			window.toggle_window_decorations()
			return true
		}
		.toggle_command_palette {
			surface := surface_from_target(target) or { return false }
			return surface.toggle_command_palette()
		}
		.toggle_split_zoom {
			if target is apprt.AppTarget {
				log.warn('toggle_split_zoom to app is unexpected')
				return false
			}
			surface := surface_from_target(target) or { return false }
			tree := split_tree_from_surface(surface) or {
				log.warn('surface is not in a split tree, ignoring toggle_split_zoom')
				return false
			}
			if !tree.get_is_split() {
				return false
			}
			return C.gtk_widget_activate_action_variant(surface.widget, c'split-tree.zoom',
				unsafe { nil })
		}
		.show_on_screen_keyboard {
			if target is apprt.AppTarget {
				log.warn('show_on_screen_keyboard to app is unexpected')
				return false
			}
			mut surface := surface_from_target(target) or { return false }
			return surface.show_on_screen_keyboard(none)
		}
		.command_finished {
			if data is apprt.CommandFinished {
				mut surface := surface_from_target(target) or { return false }
				return surface.command_finished(data)
			}
		}
		.start_search {
			if data is apprt.StartSearch {
				if mut surface := surface_from_target(target) {
					surface.set_search_active(true, data.needle)
				}
				return true
			}
		}
		.end_search {
			if mut surface := surface_from_target(target) {
				surface.set_search_active(false, '')
			}
			return true
		}
		.search_total {
			if data is apprt.SearchTotal {
				if mut surface := surface_from_target(target) {
					surface.set_search_total(data.total)
				}
				return true
			}
		}
		.search_selected {
			if data is apprt.SearchSelected {
				if mut surface := surface_from_target(target) {
					surface.set_search_selected(data.selected)
				}
				return true
			}
		}
		.readonly {
			if data is apprt.Readonly {
				mut surface := surface_from_target(target) or { return false }
				return surface.set_readonly(data)
			}
		}
		.secure_input, .close_all_windows, .float_window, .toggle_visibility,
		.toggle_background_opacity, .cell_size, .render_inspector, .renderer_health, .color_change,
		.reset_window_size, .check_for_updates, .undo, .redo {
			// These actions are also explicitly unimplemented in the pinned GTK
			// runtime.
			log.warn('unimplemented action=${action}')
			return false
		}
	}
	// Every value matches its action key, so this is unreachable.
	return false
}

// Translate the application action into the split-tree traversal operation.
// Linear previous/next navigation wraps, matching Ghostty's Action.gotoSplit.
fn goto_split_target(value apprt.GotoSplit) datastruct.Goto {
	return match value {
		.previous { datastruct.Goto(datastruct.GotoPreviousWrapped{}) }
		.next { datastruct.Goto(datastruct.GotoNextWrapped{}) }
		.up { datastruct.Goto(datastruct.GotoSpatial{ direction: .up }) }
		.left { datastruct.Goto(datastruct.GotoSpatial{ direction: .left }) }
		.down { datastruct.Goto(datastruct.GotoSpatial{ direction: .down }) }
		.right { datastruct.Goto(datastruct.GotoSpatial{ direction: .right }) }
	}
}

// surface_from_target follows the core Surface's runtime pointer back to the
// GTK surface wrapper. This is the V equivalent of `core.rt_surface.surface`.
fn surface_from_target(target apprt.Target) ?&SurfaceWidget {
	match target {
		apprt.AppTarget {
			return none
		}
		apprt.SurfaceTarget {
			if isnil(target.surface) {
				return none
			}
			core_surface := unsafe { &core.Surface(target.surface) }
			if isnil(core_surface.rt_surface) || isnil(core_surface.rt_surface.user_data) {
				return none
			}
			surface := unsafe { &SurfaceWidget(core_surface.rt_surface.user_data) }
			if isnil(surface) || surface.core_surface != core_surface {
				return none
			}
			return surface
		}
	}
}

fn window_from_surface(surface &SurfaceWidget) ?&Window {
	if isnil(surface) || isnil(surface.widget) {
		return none
	}
	widget := C.gtk_widget_get_ancestor(surface.widget, window_get_type())
	return window_from_native(widget)
}

fn split_tree_from_surface(surface &SurfaceWidget) ?&SplitTreeWidget {
	if isnil(surface) || isnil(surface.widget) {
		return none
	}
	widget := C.gtk_widget_get_ancestor(surface.widget, split_tree_get_type())
	if isnil(widget) {
		return none
	}
	priv := split_tree_priv(voidptr(widget))
	if isnil(priv.wrapper) {
		return none
	}
	tree := unsafe { &SplitTreeWidget(priv.wrapper) }
	if isnil(tree) || tree.widget != widget {
		return none
	}
	return tree
}

fn window_from_native(widget GtkWidget) ?&Window {
	if isnil(widget) || C.g_type_check_instance_is_a(widget, window_get_type()) == 0 {
		return none
	}
	priv := window_priv(voidptr(widget))
	if isnil(priv.wrapper) {
		return none
	}
	window := unsafe { &Window(priv.wrapper) }
	if isnil(window) || window.obj != widget {
		return none
	}
	return window
}

// send_desktop_notification sends an application-scoped notification. A zero
// present-surface target matches Ghostty's no-surface notification behavior.
fn (self &Application) send_desktop_notification(title string, body string) {
	if isnil(self.obj) {
		return
	}
	actual_title := if title.len == 0 { 'Witty' } else { title }
	notification := C.g_notification_new(&char(actual_title.str))
	if isnil(notification) {
		return
	}
	defer {
		object_unref(GObject(notification))
	}
	C.g_notification_set_body(notification, &char(body.str))
	icon := C.g_themed_icon_new(c'com.alexander.witty')
	if !isnil(icon) {
		C.g_notification_set_icon(notification, icon)
		object_unref(GObject(icon))
	}
	target := C.g_variant_new_uint64(0)
	C.g_notification_set_default_action_and_target_value(notification, c'app.present-surface', target)
	C.g_application_send_notification(self.obj, &char(body.str), notification)
}

fn (mut self Application) goto_window(direction apprt.GotoWindow) bool {
	toplevels := C.gtk_window_list_toplevels()
	if isnil(toplevels) {
		return false
	}
	defer {
		C.g_list_free(toplevels)
	}
	count := int(list_length(toplevels))
	if count == 0 {
		return false
	}
	mut active := -1
	for i := 0; i < count; i++ {
		gtk_window := GtkWindow(list_data_at(toplevels, u32(i)))
		if !isnil(gtk_window) && C.gtk_window_is_active(gtk_window) != 0 {
			active = i
			break
		}
	}
	start := goto_window_start(active, direction)
	for offset := 1; offset <= count; offset++ {
		index := if direction == .next {
			(start + offset) % count
		} else {
			(start - offset + count * 2) % count
		}
		gtk_window := GtkWindow(list_data_at(toplevels, u32(index)))
		if isnil(gtk_window) || C.gtk_window_is_active(gtk_window) != 0
			|| C.gtk_widget_get_visible(GtkWidget(gtk_window)) == 0 {
			continue
		}
		mut window := window_from_native(GtkWidget(gtk_window)) or { continue }
		mut surface := window.get_active_surface() or { continue }
		C.gtk_window_present(gtk_window)
		surface.grab_focus()
		return true
	}
	return false
}

// Return the synthetic index immediately before the first candidate. When no
// window is active Ghostty begins at the list head in either direction; after
// that first candidate, previous traversal wraps to the tail.
fn goto_window_start(active int, direction apprt.GotoWindow) int {
	if active >= 0 {
		return active
	}
	return if direction == .next { -1 } else { 1 }
}

fn (mut self Application) toggle_quick_terminal() bool {
	if mut window := get_quick_terminal_window() {
		window.toggle_visibility()
		return true
	}
	if !self.winproto.supports_quick_terminal() {
		return false
	}
	mut window := Window.new(self)
	if isnil(window) || isnil(window.obj) {
		return false
	}
	window.set_quick_terminal(true)
	window.sync_appearance()
	self.windows << window
	window.bind_application_config(self)
	window.new_tab_for_window(none)
	C.gtk_window_present(window.as_window())
	return true
}

// new_window translates Action.newWindow/initAndShowWindow: mark that window
// creation has begun, construct the application-owned GhosttyWindow, seed its
// first tab with window context, and present it.
fn (mut self Application) new_window(parent ?&core.Surface) bool {
	self.requested_window = true
	mut window := Window.new(self)
	if isnil(window.obj) {
		return false
	}
	self.windows << window
	window.bind_application_config(self)
	window.new_tab_for_window(parent)
	C.gtk_window_present(window.as_window())
	return true
}

// get_quick_terminal_window searches GTK's native toplevel list and casts
// each candidate to the registered GhosttyWindow type, matching Ghostty's
// getQuickTerminalWindow helper.
fn get_quick_terminal_window() ?&Window {
	toplevels := C.gtk_window_list_toplevels()
	if isnil(toplevels) {
		return none
	}
	defer {
		C.g_list_free(toplevels)
	}
	count := list_length(toplevels)
	for i := u32(0); i < count; i++ {
		widget := GtkWidget(list_data_at(toplevels, i))
		window := window_from_native(widget) or { continue }
		if window.is_quick_terminal() {
			return window
		}
	}
	return none
}

// dispatch_runtime_actions drains actions explicitly queued by tests or
// headless callers. Normal GTK core actions use application_runtime_action_cb
// and are dispatched synchronously so borrowed action payloads remain valid.
fn (mut self Application) dispatch_runtime_actions() ! {
	actions := self.runtime_bridge.actions.clone()
	self.runtime_bridge.actions.clear()
	for event in actions {
		self.perform_action(event.target, event.action, event.data)!
	}
}

// --- Free helpers ---------------------------------------------------------

// perceived_luminance returns the perceived luminance (0..1) of a color using
// the same weights ghostty uses (terminal RGB perceivedLuminance). Mirrors the
// `config.background.toTerminalRGB().perceivedLuminance()` call.
fn perceived_luminance(c configpkg.ColorRGB) f64 {
	r := f64(c.r) / 255.0
	g := f64(c.g) / 255.0
	b := f64(c.b) / 255.0
	return 0.299 * r + 0.587 * g + 0.114 * b
}

// set_gtk_env sets various GTK-related environment variables (GDK_DEBUG /
// GDK_DISABLE) based on the runtime GTK version. Mirrors `setGtkEnv`.
//
// This must be called BEFORE GTK initialization.
fn set_gtk_env(config &configpkg.Config) {
	// GDK_DEBUG flags.
	mut gdk_debug := []string{}
	// GDK_DISABLE flags.
	mut gdk_disable := []string{}

	// Current gtk color management isn't good enough; disable by default on
	// versions before 4.18.
	mut disable_color_mgmt := true

	if gtk_runtime_at_least(4, 18, 0) {
		disable_color_mgmt = false
	}

	if gtk_runtime_at_least(4, 16, 0) {
		// From gtk 4.16 GDK_DEBUG split into GDK_DEBUG and GDK_DISABLE.
		// The terminal and inspector request desktop GL on their own GLAreas.
		// Let GTK select the GL API for its compositor and native controls.
		gdk_disable << 'vulkan'
	} else if gtk_runtime_at_least(4, 14, 0) {
		// Needed to run on Wayland after GTK 4.14.
		gdk_debug << 'gl-disable-gles'
		gdk_debug << 'vulkan-disable'
		if runtime_until(4, 17, 5) {
			// Removed at GTK v4.17.5.
			gdk_debug << 'gl-no-fractional'
		}
	} else {
		// Versions prior to 4.14 are largely untested for ghostty.
		gdk_debug << 'vulkan-disable'
	}

	if disable_color_mgmt {
		gdk_disable << 'color-mgmt'
	}

	// gtk-opengl-debug dumps directly to stderr; both switches must be true.
	if config.gtk_opengl_debug && global_state.get_state().logging.stderr() {
		gdk_debug << 'opengl'
	}

	gdk_debug_value := gdk_debug.join(',')
	log.warn('setting GDK_DEBUG=${gdk_debug_value}')
	C.setenv(c'GDK_DEBUG', &char(gdk_debug_value.str), 1)

	gdk_disable_value := gdk_disable.join(',')
	log.warn('setting GDK_DISABLE=${gdk_disable_value}')
	C.setenv(c'GDK_DISABLE', &char(gdk_disable_value.str), 1)
}

// find_active_window is a GCompareFunc that matches the currently-active
// toplevel window (returns 0 for a match). Mirrors `findActiveWindow`.
fn find_active_window(data voidptr, _ voidptr) int {
	if isnil(data) {
		return -1
	}
	// Confusingly, is_active returns non-zero when active but we return 0 for
	// equality, matching glib's findCustom contract.
	if C.gtk_window_is_active(GtkWindow(data)) != 0 {
		return 0
	}
	return -1
}
