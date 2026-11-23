@[has_globals]
module gtk

// window_linux.v - The GObject Window class for the GTK apprt.
//
// Translated from ghostty/src/apprt/gtk/class/window.zig.
//
// GhosttyWindow is registered as a real AdwApplicationWindow subclass. The
// native instance private data points at a stable V wrapper, allowing the ten
// properties and the dispose/finalize vfuncs to share the translated Window
// implementation. The blueprint widget graph is built programmatically with
// the same AdwTabOverview / AdwTabBar / AdwTabView / AdwToolbarView /
// AdwToastOverlay hierarchy and signal contract as the pinned Zig source.
import configpkg
import core
import input
import apprt
import build_meta
import datastruct
import internal_os
import log

// --- New opaque handle aliases --------------------------------------------
// (Grep-verified: none of these `fn C.*` or aliases are declared elsewhere in
// the module.)

// AdwApplicationWindow is an AdwApplicationWindow* (the parent instance type).
pub type AdwApplicationWindow = voidptr

// AdwTabView is an AdwTabView*.
pub type AdwTabView = voidptr

// AdwTabBar is an AdwTabBar*.
pub type AdwTabBar = voidptr

// AdwTabOverview is an AdwTabOverview*.
pub type AdwTabOverview = voidptr

// AdwTabPage is an AdwTabPage*.
pub type AdwTabPage = voidptr

// AdwToolbarView is an AdwToolbarView*.
pub type AdwToolbarView = voidptr

// AdwToastOverlay is an AdwToastOverlay*.
pub type AdwToastOverlay = voidptr

// GtkNative is a gtk.Native* (interface) — the upcast used to reach the
// GdkSurface of a realized window.
pub type GtkNative = voidptr

// --- New GTK/Adw C bindings -----------------------------------------------
// Only functions not already declared anywhere in the module.

fn C.gtk_window_set_title(window GtkWindow, title &char)

fn C.gtk_window_get_title(window GtkWindow) &char

fn C.gtk_window_set_icon_name(window GtkWindow, name &char)

fn C.gtk_window_maximize(window GtkWindow)

fn C.gtk_window_unmaximize(window GtkWindow)

fn C.gtk_window_is_maximized(window GtkWindow) int

fn C.gtk_window_fullscreen(window GtkWindow)

fn C.gtk_window_unfullscreen(window GtkWindow)

fn C.gtk_window_is_fullscreen(window GtkWindow) int

fn C.gtk_window_is_active(window GtkWindow) int

fn C.gtk_window_set_decorated(window GtkWindow, decorated int)

fn C.gtk_window_set_default_size(window GtkWindow, width int, height int)

fn C.gtk_window_present(window GtkWindow)

fn C.gtk_window_close(window GtkWindow)

fn C.gtk_window_destroy(window GtkWindow)

fn C.gtk_window_set_handle_menubar_accel(window GtkWindow, handle_menubar_accel int)

fn C.gtk_native_get_surface(native GtkNative) GdkSurface

fn C.gtk_native_get_surface_transform(native GtkNative, x &f64, y &f64) int

fn C.gdk_surface_beep(surface GdkSurface)

fn C.gtk_show_about_dialog(parent GtkWindow, first_property_name &char, ...)

fn C.adw_show_about_dialog(parent GtkWidget, first_property_name &char, ...)

fn C.adw_application_window_set_content(window AdwApplicationWindow, content GtkWidget)

fn C.adw_tab_overview_new() AdwTabOverview

fn C.adw_tab_overview_set_child(overview AdwTabOverview, child GtkWidget)

fn C.adw_tab_overview_set_view(overview AdwTabOverview, view AdwTabView)

fn C.adw_tab_overview_set_enable_new_tab(overview AdwTabOverview, enable_new_tab int)

fn C.adw_tab_overview_set_show_start_title_buttons(overview AdwTabOverview, show_start_title_buttons int)

fn C.adw_tab_overview_set_show_end_title_buttons(overview AdwTabOverview, show_end_title_buttons int)

fn C.adw_toolbar_view_new() AdwToolbarView

fn C.adw_toolbar_view_set_content(view AdwToolbarView, content GtkWidget)

fn C.adw_toolbar_view_set_top_bar_style(view AdwToolbarView, style int)

fn C.adw_toolbar_view_set_bottom_bar_style(view AdwToolbarView, style int)

fn C.adw_tab_bar_new() AdwTabBar

fn C.adw_tab_bar_set_view(tab_bar AdwTabBar, view AdwTabView)

fn C.adw_tab_bar_set_autohide(tab_bar AdwTabBar, autohide int)

fn C.adw_tab_bar_set_expand_tabs(tab_bar AdwTabBar, expand_tabs int)

fn C.adw_tab_bar_set_start_action_widget(tab_bar AdwTabBar, widget GtkWidget)

fn C.adw_tab_bar_set_end_action_widget(tab_bar AdwTabBar, widget GtkWidget)

fn C.adw_toast_overlay_new() AdwToastOverlay

fn C.adw_toast_overlay_set_child(overlay AdwToastOverlay, child GtkWidget)

fn C.adw_tab_view_new() AdwTabView

fn C.adw_tab_view_set_shortcuts(view AdwTabView, shortcuts int)

fn C.adw_tab_page_get_child(page AdwTabPage) GtkWidget

fn C.adw_tab_view_close_page_finish(view AdwTabView, page AdwTabPage, confirm int)

fn C.adw_toast_new(title &char) voidptr

fn C.adw_toast_set_timeout(toast voidptr, timeout u32)

fn C.adw_toast_overlay_add_toast(overlay AdwToastOverlay, toast voidptr)

fn C.gtk_box_new(orientation int, spacing int) GtkWidget

fn C.gtk_box_append(box GtkWidget, child GtkWidget)

fn C.adw_header_bar_pack_start(header_bar GtkWidget, child GtkWidget)

fn C.adw_header_bar_pack_end(header_bar GtkWidget, child GtkWidget)

fn C.adw_window_title_new(title &char, subtitle &char) GtkWidget

fn C.adw_window_title_set_title(window_title GtkWidget, title &char)

fn C.adw_window_title_set_subtitle(window_title GtkWidget, subtitle &char)

fn C.adw_split_button_new() GtkWidget

fn C.adw_split_button_set_icon_name(button GtkWidget, icon_name &char)

fn C.adw_split_button_set_dropdown_tooltip(button GtkWidget, tooltip &char)

fn C.adw_split_button_set_menu_model(button GtkWidget, menu_model GMenuModel)

fn C.gtk_toggle_button_new() GtkWidget

fn C.gtk_toggle_button_get_active(button GtkWidget) int

fn C.gtk_toggle_button_set_active(button GtkWidget, active int)

fn C.gtk_button_set_icon_name(button GtkWidget, icon_name &char)

fn C.gtk_menu_button_new() GtkWidget

fn C.gtk_menu_button_set_icon_name(button GtkWidget, icon_name &char)

fn C.gtk_menu_button_set_menu_model(button GtkWidget, menu_model GMenuModel)

fn C.gtk_menu_button_get_active(button GtkWidget) int

fn C.gtk_window_controls_new(side int) GtkWidget

fn C.gtk_widget_add_css_class(widget GtkWidget, css_class &char)

fn C.gtk_widget_remove_css_class(widget GtkWidget, css_class &char)

fn C.gtk_widget_set_visible(widget GtkWidget, visible int)

fn C.gtk_widget_get_visible(widget GtkWidget) int

fn C.gtk_widget_set_size_request(widget GtkWidget, width int, height int)

fn C.gdk_display_is_rgba(display GdkDisplay) int

fn C.gdk_display_is_composited(display GdkDisplay) int

fn C.adw_toolbar_style_get_type() GType

fn C.g_signal_handlers_disconnect_matched(instance voidptr, mask u32, signal_id u32, detail u32, closure voidptr, func voidptr, data voidptr) u32

// --- Toolbar style ---------------------------------------------------------

// AdwToolbarStyle mirrors `adw.ToolbarStyle`.
pub enum AdwToolbarStyle as i32 {
	flat
	raised
	raised_border
}

__global g_window_type = GType(0)

// The instance-private offset: the size until class_init adjusts it, then
// the (negative) offset from the instance. Mirrors zig-gobject's `Private.offset`.
__global g_window_priv_offset = int(0)
__global g_window_titlebar_style_type = GType(0)
__global g_window_titlebar_style_values [3]C.GEnumValue
__global g_window_pspec_active_surface = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_config = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_debug = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_headerbar_visible = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_quick_terminal = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_tabs_autohide = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_tabs_visible = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_tabs_wide = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_toolbar_style = &C.GParamSpec(unsafe { nil })
__global g_window_pspec_titlebar_style = &C.GParamSpec(unsafe { nil })

struct C.GhosttyWindowPrivate {
mut:
	wrapper voidptr
}

const window_prop_active_surface = u32(1)
const window_prop_config = u32(2)
const window_prop_debug = u32(3)
const window_prop_headerbar_visible = u32(4)
const window_prop_quick_terminal = u32(5)
const window_prop_tabs_autohide = u32(6)
const window_prop_tabs_visible = u32(7)
const window_prop_tabs_wide = u32(8)
const window_prop_toolbar_style = u32(9)
const window_prop_titlebar_style = u32(10)
const window_param_static_strings = int(32 | 64 | 128)
const g_signal_match_data = u32(1 << 4)

fn window_titlebar_style_get_type() GType {
	if g_window_titlebar_style_type == GType(0) {
		g_window_titlebar_style_values[0] = C.GEnumValue{
			value:      int(configpkg.GtkTitlebarStyle.native)
			value_name: c'native'
			value_nick: c'native'
		}
		g_window_titlebar_style_values[1] = C.GEnumValue{
			value:      int(configpkg.GtkTitlebarStyle.tabs)
			value_name: c'tabs'
			value_nick: c'tabs'
		}
		g_window_titlebar_style_values[2] = C.GEnumValue{
			value:      0
			value_name: &char(unsafe { nil })
			value_nick: &char(unsafe { nil })
		}
		g_window_titlebar_style_type = C.g_enum_register_static(c'GhosttyGtkTitlebarStyle',
			&g_window_titlebar_style_values[0])
	}
	return g_window_titlebar_style_type
}

fn window_priv(obj voidptr) &C.GhosttyWindowPrivate {
	return &C.GhosttyWindowPrivate(instance_private(obj, g_window_priv_offset))
}

fn window_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := window_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	self := unsafe { &Window(priv.wrapper) }
	match property_id {
		window_prop_active_surface {
			if surface := self.get_active_surface() {
				C.g_value_set_object(value, surface.widget)
			} else {
				C.g_value_set_object(value, unsafe { nil })
			}
		}
		window_prop_config {
			C.g_value_set_object(value, if isnil(self.config) {
				unsafe { nil }
			} else {
				self.config.obj
			})
		}
		window_prop_debug {
			C.g_value_set_boolean(value, $if debug { 1 } $else { 0 })
		}
		window_prop_headerbar_visible {
			C.g_value_set_boolean(value, b2i(self.get_headerbar_visible()))
		}
		window_prop_quick_terminal {
			C.g_value_set_boolean(value, b2i(self.quick_terminal))
		}
		window_prop_tabs_autohide {
			C.g_value_set_boolean(value, b2i(self.get_tabs_autohide()))
		}
		window_prop_tabs_visible {
			C.g_value_set_boolean(value, b2i(self.get_tabs_visible()))
		}
		window_prop_tabs_wide {
			C.g_value_set_boolean(value, b2i(self.get_tabs_wide()))
		}
		window_prop_toolbar_style {
			C.g_value_set_enum(value, int(self.get_toolbar_style()))
		}
		window_prop_titlebar_style {
			C.g_value_set_enum(value, int(self.get_titlebar_style()))
		}
		else {}
	}
}

fn window_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := window_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &Window(priv.wrapper) }
	match property_id {
		window_prop_config {
			config_obj := C.g_value_get_object(value)
			if isnil(config_obj) {
				self.set_config_reference(none)
			} else {
				config_private := config_priv(config_obj)
				// V 0.5.2 miscompiles `if` expressions yielding ?&T arguments.
				if isnil(config_private.wrapper) {
					self.set_config_reference(none)
				} else {
					self.set_config_reference(unsafe { &Config(config_private.wrapper) })
				}
			}
		}
		window_prop_quick_terminal {
			self.quick_terminal = C.g_value_get_boolean(value) != 0
		}
		else {}
	}
}

fn window_dispose_object(obj voidptr) {
	priv := window_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Window(priv.wrapper) }
		self.dispose_resources()
	}
	C.adw_application_window_set_content(AdwApplicationWindow(obj), unsafe { nil })
	C.witty_gobject_call_parent_dispose(obj)
}

fn window_finalize_object(obj voidptr) {
	mut priv := window_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Window(priv.wrapper) }
		self.finalize_resources()
		self.obj = unsafe { nil }
		priv.wrapper = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

fn window_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_window_priv_offset)
	_ = class_data
	_ = terminal_surface_get_type()
	_ = config_get_type()
	C.witty_gobject_class_set_get_property(klass, voidptr(window_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(window_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(window_dispose_object))
	C.witty_gobject_class_set_finalize(klass, voidptr(window_finalize_object))
	readable := g_param_readable | window_param_static_strings
	readwrite := g_param_readwrite | window_param_static_strings
	nil_str := &char(unsafe { nil })
	g_window_pspec_active_surface = C.g_param_spec_object(c'active-surface', nil_str, nil_str,
		terminal_surface_get_type(), readable)
	g_window_pspec_config = C.g_param_spec_object(c'config', nil_str, nil_str, config_get_type(),
		readwrite)
	g_window_pspec_debug = C.g_param_spec_boolean(c'debug', nil_str, nil_str, $if debug {
		1
	} $else {
		0
	}, readable)
	g_window_pspec_headerbar_visible = C.g_param_spec_boolean(c'headerbar-visible', nil_str,
		nil_str, 1, readable)
	g_window_pspec_quick_terminal = C.g_param_spec_boolean(c'quick-terminal', nil_str, nil_str, 1,
		readwrite)
	g_window_pspec_tabs_autohide = C.g_param_spec_boolean(c'tabs-autohide', nil_str, nil_str, 1,
		readable)
	g_window_pspec_tabs_visible = C.g_param_spec_boolean(c'tabs-visible', nil_str, nil_str, 1,
		readable)
	g_window_pspec_tabs_wide = C.g_param_spec_boolean(c'tabs-wide', nil_str, nil_str, 1, readable)
	g_window_pspec_toolbar_style = C.g_param_spec_enum(c'toolbar-style', nil_str, nil_str,
		C.adw_toolbar_style_get_type(), int(AdwToolbarStyle.raised), readable)
	g_window_pspec_titlebar_style = C.g_param_spec_enum(c'titlebar-style', nil_str, nil_str,
		window_titlebar_style_get_type(), int(configpkg.GtkTitlebarStyle.native), readable)
	C.g_object_class_install_property(klass, window_prop_active_surface,
		g_window_pspec_active_surface)
	C.g_object_class_install_property(klass, window_prop_config, g_window_pspec_config)
	C.g_object_class_install_property(klass, window_prop_debug, g_window_pspec_debug)
	C.g_object_class_install_property(klass, window_prop_headerbar_visible,
		g_window_pspec_headerbar_visible)
	C.g_object_class_install_property(klass, window_prop_quick_terminal,
		g_window_pspec_quick_terminal)
	C.g_object_class_install_property(klass, window_prop_tabs_autohide,
		g_window_pspec_tabs_autohide)
	C.g_object_class_install_property(klass, window_prop_tabs_visible, g_window_pspec_tabs_visible)
	C.g_object_class_install_property(klass, window_prop_tabs_wide, g_window_pspec_tabs_wide)
	C.g_object_class_install_property(klass, window_prop_toolbar_style,
		g_window_pspec_toolbar_style)
	C.g_object_class_install_property(klass, window_prop_titlebar_style,
		g_window_pspec_titlebar_style)
}

fn window_instance_init(instance voidptr, klass voidptr) {
	_ = instance
	_ = klass
}

pub fn window_get_type() GType {
	if g_window_type == GType(0) {
		parent := C.adw_application_window_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(window_class_init)
			instance_init: voidptr(window_instance_init)
		}
		g_window_type = C.g_type_register_static(parent, c'GhosttyWindow', &info, 0)
		g_window_priv_offset = C.g_type_add_instance_private(g_window_type,
			sizeof(C.GhosttyWindowPrivate))
	}
	return g_window_type
}

// --- Config: GObject config wrapper (owned elsewhere) ---------------------
//
// The canonical `Config` GObject wrapper (translated from class/config.zig)
// now lives in config_class_linux.v, which owns the type, `config_new`, the
// `.get()`/`.get_mut()` accessors, and the GTK-specific config getters
// (gtk_titlebar_style, gtk_wide_tabs, ...) that the appearance logic below
// uses. This file references `Config` directly (same `gtk` module).

// --- SelectTab ------------------------------------------------------------

pub struct SelectTabPrevious {}

pub struct SelectTabNext {}

pub struct SelectTabLast {}

pub struct SelectTabN {
pub:
	n uint
}

pub type SelectTab = SelectTabLast | SelectTabN | SelectTabNext | SelectTabPrevious

// --- Window ---------------------------------------------------------------

// Window is the apprt window GObject (`GhosttyWindow`, an
// `adw.ApplicationWindow`). Modeled as a struct wrapping the GObject pointer
// plus the private-state fields from the Zig `Private` struct.
//
// `@[heap]` so the winproto integration can hold a stable pointer to the
// embedded `ApprtWindow` bridge (mirroring ghostty passing a `*Window`).
@[heap]
pub struct Window {
mut:
	// The underlying AdwApplicationWindow GObject. Set at construction by the
	// native subclass constructor.
	obj AdwApplicationWindow = unsafe { nil }

	// Stable owner used by signal callbacks that need application state.
	app &Application = unsafe { nil }

	// Whether this window is a quick terminal. If it is then it behaves
	// slightly differently under certain scenarios.
	quick_terminal bool

	// The window decoration override. If this is not set then we inherit
	// whatever the config has. This allows overriding the config on a
	// per-window basis. `has_window_decoration` gates whether it is set (V has
	// no `?enum` field ergonomics matching the Zig `?WindowDecoration`).
	window_decoration     configpkg.WindowDecoration = .auto
	has_window_decoration bool

	// The configuration that this window is using.
	config &Config = unsafe { nil }
	// Application-created windows bind their config property to the
	// application's config property for their lifetime.
	config_binding GObject = unsafe { nil }

	// State and logic for windowing protocol for a window.
	winproto WinProtoWindow = NoopWindow{}

	// The bridge object that winproto backends receive. Mirrors ghostty
	// passing `*Window` to winproto (which only calls the small accessor set
	// modeled by `ApprtWindow`).
	apprt_window ApprtWindow

	// Kind of hacky, but this lets us know if we've initialized any single
	// surface yet. We gate default size on this so we don't resize the window
	// after surfaces already exist.
	surface_init bool

	// See tab_overview_open for why we have this. 0 means "no timer".
	tab_overview_focus_timer u32

	// The lazily-created command palette. It owns itself only while open, so
	// retain the same weak GObject reference as Ghostty.
	command_palette WeakRef = weak_ref_empty()

	// Children in the programmatic equivalent of window.blp.
	tab_overview           AdwTabOverview  = unsafe { nil }
	tab_bar                AdwTabBar       = unsafe { nil }
	tab_view               AdwTabView      = unsafe { nil }
	toolbar                AdwToolbarView  = unsafe { nil }
	toast_overlay          AdwToastOverlay = unsafe { nil }
	header_bar             GtkWidget       = unsafe { nil }
	window_title           GtkWidget       = unsafe { nil }
	tab_bar_start          GtkWidget       = unsafe { nil }
	tab_bar_end            GtkWidget       = unsafe { nil }
	overview_header_toggle GtkWidget       = unsafe { nil }
	overview_tab_toggle    GtkWidget       = unsafe { nil }

	// V-side owners for the GhosttyTab wrappers inserted in tab_view.
	tabs      []&Tab
	disposed  bool
	finalized bool
}

fn window_split_menu_new() GMenu {
	menu := C.g_menu_new()
	surface_menu_append(menu, 'Split Up', c'win.split-up')
	surface_menu_append(menu, 'Split Down', c'win.split-down')
	surface_menu_append(menu, 'Split Left', c'win.split-left')
	surface_menu_append(menu, 'Split Right', c'win.split-right')
	return menu
}

fn window_main_menu_new() GMenu {
	menu := C.g_menu_new()

	mut section := C.g_menu_new()
	surface_menu_append(section, 'Copy', c'win.copy')
	surface_menu_append(section, 'Paste', c'win.paste')
	surface_menu_section(menu, section)

	section = C.g_menu_new()
	surface_menu_append(section, 'New Window', c'win.new-window')
	surface_menu_append(section, 'Close Window', c'win.close')
	surface_menu_section(menu, section)

	section = C.g_menu_new()
	surface_menu_append(section, 'New Tab', c'win.new-tab')
	surface_menu_append(section, 'Close Tab', c'win.close-tab::this')
	surface_menu_section(menu, section)

	section = C.g_menu_new()
	submenu := C.g_menu_new()
	surface_menu_append(submenu, 'Change Title…', c'win.prompt-title')
	surface_menu_append(submenu, 'Split Up', c'win.split-up')
	surface_menu_append(submenu, 'Split Down', c'win.split-down')
	surface_menu_append(submenu, 'Split Left', c'win.split-left')
	surface_menu_append(submenu, 'Split Right', c'win.split-right')
	surface_menu_append_submenu(section, 'Split', submenu)
	object_unref(GObject(submenu))
	surface_menu_section(menu, section)

	section = C.g_menu_new()
	surface_menu_append(section, 'Clear', c'win.clear')
	surface_menu_append(section, 'Reset', c'win.reset')
	surface_menu_section(menu, section)

	section = C.g_menu_new()
	surface_menu_append(section, 'Command Palette', c'win.toggle-command-palette')
	surface_menu_append(section, 'Terminal Inspector', c'win.toggle-inspector')
	surface_menu_append(section, 'Open Configuration', c'app.open-config')
	surface_menu_append(section, 'Reload Configuration', c'app.reload-config')
	surface_menu_section(menu, section)

	section = C.g_menu_new()
	surface_menu_append(section, 'About Witty', c'win.about')
	surface_menu_append(section, 'Quit', c'app.quit')
	surface_menu_section(menu, section)
	return menu
}

fn window_split_button_new(menu GMenu, flat bool, self &Window) GtkWidget {
	button := C.adw_split_button_new()
	if flat {
		C.gtk_widget_add_css_class(button, c'flat')
	}
	C.adw_split_button_set_icon_name(button, c'tab-new-symbolic')
	tooltip := i18n_('New Tab')
	dropdown_tooltip := i18n_('New Split')
	C.gtk_widget_set_tooltip_text(button, &char(tooltip.str))
	C.adw_split_button_set_dropdown_tooltip(button, &char(dropdown_tooltip.str))
	C.adw_split_button_set_menu_model(button, GMenuModel(menu))
	C.gtk_widget_set_focusable(button, 0)
	C.gtk_widget_set_focus_on_click(button, 0)
	C.g_signal_connect_data(button, c'clicked', GCallback(voidptr(window_new_tab_button_cb)),
		voidptr(self), unsafe { nil }, 0)
	return button
}

fn window_overview_toggle_new(flat bool, self &Window) GtkWidget {
	button := C.gtk_toggle_button_new()
	if flat {
		C.gtk_widget_add_css_class(button, c'flat')
	}
	C.gtk_button_set_icon_name(button, c'view-grid-symbolic')
	tooltip := i18n_('View Open Tabs')
	C.gtk_widget_set_tooltip_text(button, &char(tooltip.str))
	C.gtk_widget_set_focusable(button, 0)
	C.gtk_widget_set_focus_on_click(button, 0)
	C.g_signal_connect_data(button, c'toggled', GCallback(voidptr(window_overview_toggle_cb)),
		voidptr(self), unsafe { nil }, 0)
	return button
}

fn window_menu_button_new(menu GMenu, flat bool, self &Window) GtkWidget {
	button := C.gtk_menu_button_new()
	if flat {
		C.gtk_widget_add_css_class(button, c'flat')
	}
	C.gtk_menu_button_set_icon_name(button, c'open-menu-symbolic')
	C.gtk_menu_button_set_menu_model(button, GMenuModel(menu))
	tooltip := i18n_('Main Menu')
	C.gtk_widget_set_tooltip_text(button, &char(tooltip.str))
	C.gtk_widget_set_focusable(button, 0)
	C.g_signal_connect_data(button, c'notify::active', GCallback(voidptr(window_menu_active_cb)),
		voidptr(self), unsafe { nil }, 0)
	return button
}

// new creates the GhosttyWindow GObject and the libadwaita widget graph from
// window.blp. The custom type is registered as an AdwApplicationWindow
// subclass; V-side state remains in this stable wrapper and signal user-data.
pub fn Window.new(app &Application) &Window {
	obj := C.g_object_new(window_get_type(), c'application', app.obj, unsafe { nil })
	if isnil(obj) {
		return &Window{}
	}
	C.gtk_widget_add_css_class(GtkWidget(obj), c'window')

	tab_view := C.adw_tab_view_new()
	C.adw_tab_view_set_shortcuts(tab_view, 0)
	toast_overlay := C.adw_toast_overlay_new()
	C.adw_toast_overlay_set_child(toast_overlay, GtkWidget(tab_view))
	toolbar := C.adw_toolbar_view_new()
	tab_bar := C.adw_tab_bar_new()
	// `tab_bar` is a bound template child in Ghostty, and gtk_widget_init_template
	// keeps a reference to every bound child until dispose. syncAppearance relies
	// on it: removing the tab bar from the toolbar would otherwise finalize it.
	C.g_object_ref_sink(GObject(tab_bar))
	C.adw_tab_bar_set_view(tab_bar, tab_view)
	tab_overview := C.adw_tab_overview_new()
	C.adw_tab_overview_set_view(tab_overview, tab_view)
	C.adw_tab_overview_set_enable_new_tab(tab_overview, 1)

	mut self := &Window{
		obj:           AdwApplicationWindow(obj)
		app:           app
		tab_overview:  tab_overview
		tab_bar:       tab_bar
		tab_view:      tab_view
		toolbar:       toolbar
		toast_overlay: toast_overlay
	}
	mut priv := window_priv(obj)
	priv.wrapper = voidptr(self)
	self.apprt_window.owner = self
	self.set_config_reference(app.config_object)

	// Build the two menus shared by the header bar and integrated tab bar.
	split_menu := window_split_menu_new()
	main_menu := window_main_menu_new()

	// Traditional header bar.
	header_bar := C.adw_header_bar_new()
	window_title := C.adw_window_title_new(c'', c'')
	C.adw_header_bar_set_title_widget(header_bar, window_title)
	C.adw_header_bar_pack_start(header_bar, window_split_button_new(split_menu, false, self))
	header_end := C.gtk_box_new(0, 0)
	overview_header_toggle := window_overview_toggle_new(false, self)
	C.gtk_box_append(header_end, overview_header_toggle)
	C.gtk_box_append(header_end, window_menu_button_new(main_menu, false, self))
	C.adw_header_bar_pack_end(header_bar, header_end)
	C.adw_toolbar_view_add_top_bar(toolbar, header_bar)

	// Integrated tab titlebar controls used by gtk-titlebar-style=tabs.
	tab_bar_start := C.gtk_box_new(0, 0)
	C.gtk_box_append(tab_bar_start, C.gtk_window_controls_new(0))
	C.gtk_box_append(tab_bar_start, window_split_button_new(split_menu, true, self))
	C.adw_tab_bar_set_start_action_widget(tab_bar, tab_bar_start)
	tab_bar_end := C.gtk_box_new(0, 0)
	overview_tab_toggle := window_overview_toggle_new(true, self)
	C.gtk_box_append(tab_bar_end, overview_tab_toggle)
	C.gtk_box_append(tab_bar_end, window_menu_button_new(main_menu, true, self))
	C.gtk_box_append(tab_bar_end, C.gtk_window_controls_new(1))
	C.adw_tab_bar_set_end_action_widget(tab_bar, tab_bar_end)
	C.adw_toolbar_view_add_top_bar(toolbar, GtkWidget(tab_bar))

	// Terminal body and debug-build warning.
	content := C.gtk_box_new(1, 0)
	debug_warning := GtkWidget(C.g_object_new(debug_warning_get_type(), &char(unsafe { nil })))
	C.gtk_widget_set_visible(debug_warning, $if debug { 1 } $else { 0 })
	C.gtk_box_append(content, debug_warning)
	C.gtk_box_append(content, GtkWidget(toast_overlay))
	C.adw_toolbar_view_set_content(toolbar, content)
	C.adw_tab_overview_set_child(tab_overview, GtkWidget(toolbar))
	C.adw_application_window_set_content(AdwApplicationWindow(obj), GtkWidget(tab_overview))
	object_unref(GObject(split_menu))
	object_unref(GObject(main_menu))

	self.header_bar = header_bar
	self.window_title = window_title
	self.tab_bar_start = tab_bar_start
	self.tab_bar_end = tab_bar_end
	self.overview_header_toggle = overview_header_toggle
	self.overview_tab_toggle = overview_tab_toggle
	C.gtk_window_set_default_size(self.as_window(), 800, 600)
	C.gtk_window_set_handle_menubar_accel(self.as_window(), 0)
	C.g_signal_connect_data(self.obj, c'close-request',
		GCallback(voidptr(window_close_request_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.obj, c'realize', GCallback(voidptr(window_realize_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_view, c'notify::n-pages',
		GCallback(voidptr(window_n_pages_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_view, c'notify::selected-page',
		GCallback(voidptr(window_selected_page_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_view, c'close-page', GCallback(voidptr(window_close_page_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_view, c'page-attached',
		GCallback(voidptr(window_page_attached_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_view, c'page-detached',
		GCallback(voidptr(window_page_detached_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_view, c'create-window',
		GCallback(voidptr(window_create_window_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_overview, c'create-tab',
		GCallback(voidptr(window_overview_create_tab_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.tab_overview, c'notify::open',
		GCallback(voidptr(window_overview_open_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.obj, c'notify::config',
		GCallback(voidptr(window_notify_config_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.obj, c'notify::fullscreened',
		GCallback(voidptr(window_notify_fullscreened_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.obj, c'notify::is-active',
		GCallback(voidptr(window_notify_is_active_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.obj, c'notify::maximized',
		GCallback(voidptr(window_notify_maximized_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.obj, c'notify::quick-terminal',
		GCallback(voidptr(window_notify_quick_terminal_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.obj, c'notify::scale-factor',
		GCallback(voidptr(window_notify_scale_factor_cb)), voidptr(self), unsafe { nil }, 0)
	self.init(app)
	return self
}

pub fn (mut self Window) ref() &Window {
	if !isnil(self.obj) {
		object_ref(GObject(self.obj))
	}
	return self
}

pub fn (mut self Window) unref() {
	if !isnil(self.obj) {
		object_unref(GObject(self.obj))
	}
}

// init runs the tractable parts of the Zig `init` instanceInit. Mirrors the
// non-GObject-machinery portions: config fallback, winproto reset, tab-binding
// intent, window icon, action map, initial config-driven state (maximize /
// fullscreen / title), and the final appearance sync.
fn (mut self Window) init(app &Application) {
	// If our configuration is null then we get it from the application.
	if self.config == unsafe { nil } {
		self.set_config_reference(app.config_object)
	}

	// We initialize our windowing protocol to none because we can't actually
	// initialize this until we get realized.
	self.winproto = NoopWindow{}

	// Add our dev CSS class if we're in debug mode.
	$if debug {
		self.add_css_class('devel')
	}

	// Set our window icon.
	self.set_icon_name(application_id)

	// Initialize our actions.
	self.init_action_map()

	// Start states based on config.
	if self.config != unsafe { nil } {
		config := self.config.get()
		if config.maximize {
			self.maximize()
		}
		if config.fullscreen {
			self.fullscreen()
		}
		// If we have an explicit title set, we set that immediately so that
		// any applications inspecting the window states see an immediate title
		// set when the window appears.
		if title := config.title {
			self.set_title(title)
		}
	}

	// We always sync our appearance at the end because loading our config can
	// affect bindings set up initially in initTemplate.
	self.sync_appearance()

	self.notify_property(g_window_pspec_active_surface)
}

fn window_close_request_cb(window GtkWindow, user_data voidptr) int {
	_ = window
	if isnil(user_data) {
		return 0
	}
	mut self := unsafe { &Window(user_data) }
	return b2i(self.window_close_request())
}

fn window_realize_cb(widget GtkWidget, user_data voidptr) {
	_ = widget
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	if isnil(self.app) {
		return
	}
	mut app := unsafe { self.app }
	self.window_realize(mut app)
}

fn window_gdk_surface_resize_cb(surface GdkSurface, pspec voidptr, user_data voidptr) {
	_ = surface
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.prop_gdk_surface_resize()
	}
}

fn window_n_pages_cb(view AdwTabView, pspec voidptr, user_data voidptr) {
	_ = view
	_ = pspec
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	self.tab_view_n_pages()
}

fn window_notify_config_cb(obj voidptr, pspec voidptr, user_data voidptr) {
	_ = obj
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.prop_config()
	}
}

fn window_notify_fullscreened_cb(obj voidptr, pspec voidptr, user_data voidptr) {
	_ = obj
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.prop_fullscreened()
	}
}

fn window_notify_is_active_cb(obj voidptr, pspec voidptr, user_data voidptr) {
	_ = obj
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.prop_is_active()
	}
}

fn window_notify_maximized_cb(obj voidptr, pspec voidptr, user_data voidptr) {
	_ = obj
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.prop_maximized()
	}
}

fn window_notify_quick_terminal_cb(obj voidptr, pspec voidptr, user_data voidptr) {
	_ = obj
	_ = pspec
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	if isnil(self.app) {
		return
	}
	mut app := unsafe { self.app }
	self.prop_quick_terminal(mut app)
}

fn window_notify_scale_factor_cb(obj voidptr, pspec voidptr, user_data voidptr) {
	_ = obj
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.prop_scale_factor()
	}
}

fn window_selected_page_cb(view AdwTabView, pspec voidptr, user_data voidptr) {
	_ = view
	_ = pspec
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.sync_selected_tab()
	}
}

fn window_close_page_cb(view AdwTabView, page AdwTabPage, user_data voidptr) int {
	if isnil(user_data) {
		return 0
	}
	mut self := unsafe { &Window(user_data) }
	mut tab := self.tab_for_page(page) or { return 0 }
	if !tab.get_needs_confirm_quit() {
		tab.split_tree.deinit_surfaces()
		C.adw_tab_view_close_page_finish(view, page, 1)
		return 1
	}
	mut dialog := close_confirmation_dialog_new(.tab)
	C.g_signal_connect_data(dialog.dialog.obj, c'close-request',
		GCallback(voidptr(window_close_tab_confirmed_cb)), page, unsafe { nil }, 0)
	C.g_signal_connect_data(dialog.dialog.obj, c'cancel',
		GCallback(voidptr(window_close_tab_cancelled_cb)), page, unsafe { nil }, 0)
	dialog.present(tab.widget)
	return 1
}

fn window_close_tab_confirmed_cb(dialog GObject, page_data voidptr) {
	_ = dialog
	if isnil(page_data) {
		return
	}
	page := AdwTabPage(page_data)
	child := C.adw_tab_page_get_child(page)
	if isnil(child) {
		return
	}
	priv := tab_priv(voidptr(child))
	if !isnil(priv.wrapper) {
		mut tab := unsafe { &Tab(priv.wrapper) }
		tab.split_tree.deinit_surfaces()
	}
	tab_view := AdwTabView(C.gtk_widget_get_ancestor(child, C.adw_tab_view_get_type()))
	if isnil(tab_view) {
		log.warn('close confirmation called for non-existent page')
		return
	}
	C.adw_tab_view_close_page_finish(tab_view, page, 1)
}

fn window_close_tab_cancelled_cb(dialog GObject, page_data voidptr) {
	_ = dialog
	if isnil(page_data) {
		return
	}
	page := AdwTabPage(page_data)
	child := C.adw_tab_page_get_child(page)
	if isnil(child) {
		return
	}
	tab_view := AdwTabView(C.gtk_widget_get_ancestor(child, C.adw_tab_view_get_type()))
	if isnil(tab_view) {
		log.warn('close confirmation called for non-existent page')
		return
	}
	C.adw_tab_view_close_page_finish(tab_view, page, 0)
}

fn window_page_detached_cb(view AdwTabView, page AdwTabPage, position int, user_data voidptr) {
	_ = view
	_ = position
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	child := C.adw_tab_page_get_child(page)
	for i, mut tab in self.tabs {
		if tab.widget == child {
			C.g_signal_handlers_disconnect_matched(tab.widget, g_signal_match_data, 0, 0,
				unsafe { nil }, unsafe { nil }, voidptr(self))
			if !isnil(tab.split_tree) {
				C.g_signal_handlers_disconnect_matched(tab.split_tree.widget, g_signal_match_data,
					0, 0, unsafe { nil }, unsafe { nil }, voidptr(self))
			}
			if tree := tab.get_surface_tree() {
				self.disconnect_surface_handlers(tree)
			}
			tab.window = unsafe { nil }
			self.tabs.delete(i)
			break
		}
	}
}

fn window_page_attached_cb(view AdwTabView, page AdwTabPage, position int, user_data voidptr) {
	_ = view
	if isnil(user_data) {
		return
	}
	child := C.adw_tab_page_get_child(page)
	if isnil(child) {
		return
	}
	priv := tab_priv(voidptr(child))
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	mut tab := unsafe { &Tab(priv.wrapper) }
	tab.window = self
	if !isnil(tab.split_tree) {
		tab.split_tree.window = self
		C.g_signal_handlers_disconnect_matched(tab.split_tree.widget, g_signal_match_data, 0, 0,
			unsafe { nil }, unsafe { nil }, voidptr(self))
		C.g_signal_connect_data(tab.split_tree.widget, c'changed',
			GCallback(voidptr(window_tab_split_tree_changed_cb)), voidptr(self), unsafe { nil }, 0)
	}
	mut found := false
	for candidate in self.tabs {
		if candidate == tab {
			found = true
			break
		}
	}
	if !found {
		if position >= 0 && position <= self.tabs.len {
			self.tabs.insert(position, tab)
		} else {
			self.tabs << tab
		}
	}
	C.g_signal_handlers_disconnect_matched(tab.widget, g_signal_match_data, 0, 0, unsafe { nil },
		unsafe { nil }, voidptr(self))
	C.g_signal_connect_data(tab.widget, c'close-request',
		GCallback(voidptr(window_tab_close_request_cb)), voidptr(self), unsafe { nil }, 0)
	if tree := tab.get_surface_tree() {
		self.connect_surface_handlers(tree)
	}
}

fn window_create_window_cb(view AdwTabView, user_data voidptr) AdwTabView {
	_ = view
	if isnil(user_data) {
		return AdwTabView(unsafe { nil })
	}
	self := unsafe { &Window(user_data) }
	if isnil(self.app) {
		return AdwTabView(unsafe { nil })
	}
	mut app := unsafe { self.app }
	mut window := Window.new(app)
	if isnil(window.obj) {
		return AdwTabView(unsafe { nil })
	}
	app.windows << window
	C.gtk_window_present(window.as_window())
	return window.tab_view
}

fn window_tab_close_request_cb(tab_widget GtkWidget, user_data voidptr) {
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	page := C.adw_tab_view_get_page(self.tab_view, tab_widget)
	if !isnil(page) {
		C.adw_tab_view_close_page(self.tab_view, page)
	}
}

fn window_new_tab_button_cb(button GtkWidget, user_data voidptr) {
	_ = button
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.perform_binding_action(input.ActionNewTab{})
	}
}

fn window_overview_toggle_cb(button GtkWidget, user_data voidptr) {
	if isnil(user_data) {
		return
	}
	self := unsafe { &Window(user_data) }
	active := C.gtk_toggle_button_get_active(button)
	if active != adw_tab_overview_get_open(self.tab_overview) {
		adw_tab_overview_set_open(self.tab_overview, active)
	}
}

fn window_menu_active_cb(button GtkWidget, pspec voidptr, user_data voidptr) {
	_ = pspec
	if !gtk_at_least(4, 10, 0) || C.gtk_menu_button_get_active(button) == 0 || isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	self.sync_actions()
}

fn window_overview_create_tab_cb(overview AdwTabOverview, user_data voidptr) AdwTabPage {
	_ = overview
	if isnil(user_data) {
		return AdwTabPage(unsafe { nil })
	}
	mut self := unsafe { &Window(user_data) }
	if mut surface := self.get_active_surface() {
		return self.new_tab_page(surface.core(), .tab)
	}
	return self.new_tab_page(none, .tab)
}

fn window_overview_open_cb(overview AdwTabOverview, pspec voidptr, user_data voidptr) {
	_ = pspec
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	open := adw_tab_overview_get_open(overview)
	C.gtk_toggle_button_set_active(self.overview_header_toggle, open)
	C.gtk_toggle_button_set_active(self.overview_tab_toggle, open)
	if open != 0 {
		return
	}
	if self.tab_overview_focus_timer != 0 {
		C.g_source_remove(self.tab_overview_focus_timer)
	}
	self.tab_overview_focus_timer = C.g_timeout_add(500, voidptr(window_overview_focus_timer_cb),
		voidptr(self))
}

fn window_overview_focus_timer_cb(user_data voidptr) int {
	if isnil(user_data) {
		return 0
	}
	mut self := unsafe { &Window(user_data) }
	self.tab_overview_focus_timer = 0
	if surface := self.get_active_surface() {
		surface.grab_focus()
	}
	return 0
}

// init_action_map sets up our action map. Mirrors `initActionMap`.
fn (mut self Window) init_action_map() {
	string_type := C.g_variant_type_new(c's')
	mut actions := []Action{}
	for name in ['about', 'close', 'new-tab', 'new-window', 'ring-bell', 'split-right', 'split-left',
		'split-up', 'split-down', 'copy', 'paste', 'reset', 'clear', 'toggle-command-palette',
		'toggle-inspector'] {
		actions << Action.init(name, GCallback(voidptr(window_action_cb)), unsafe { nil })
	}
	actions << Action.init('close-tab', GCallback(voidptr(window_action_cb)), string_type)
	add_to_map(voidptr(self), GActionMap(self.obj), actions)
	C.g_variant_type_free(string_type)
}

fn window_action_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	if isnil(action) || isnil(data) {
		return
	}
	name_ptr := C.g_action_get_name(action)
	if isnil(name_ptr) {
		return
	}
	name := unsafe { cstring_to_vstring(name_ptr) }
	mut self := unsafe { &Window(data) }
	match name {
		'about' {
			self.action_about()
		}
		'close' {
			self.action_close()
		}
		'close-tab' {
			if isnil(parameter) {
				log.warn('win.close-tab called without a parameter')
				return
			}
			mut length := uint(0)
			value := C.g_variant_get_string(parameter, &length)
			if isnil(value) {
				log.warn('invalid mode provided to win.close-tab')
				return
			}
			mode_value := unsafe { cstring_to_vstring(value) }
			match mode_value {
				'this' {
					self.perform_binding_action(input.ActionCloseTab{ value: .this })
				}
				'other' {
					self.perform_binding_action(input.ActionCloseTab{ value: .other })
				}
				'right' {
					self.perform_binding_action(input.ActionCloseTab{ value: .right })
				}
				else {
					log.warn('invalid mode provided to win.close-tab: ${mode_value}')
				}
			}
		}
		'new-tab' {
			self.action_new_tab()
		}
		'new-window' {
			self.action_new_window()
		}
		'ring-bell' {
			self.action_ring_bell()
		}
		'split-right' {
			self.action_split_right()
		}
		'split-left' {
			self.action_split_left()
		}
		'split-up' {
			self.action_split_up()
		}
		'split-down' {
			self.action_split_down()
		}
		'copy' {
			self.action_copy()
		}
		'paste' {
			self.action_paste()
		}
		'reset' {
			self.action_reset()
		}
		'clear' {
			self.action_clear()
		}
		'toggle-command-palette' {
			self.toggle_command_palette()
		}
		'toggle-inspector' {
			self.toggle_inspector()
		}
		else {}
	}
}

fn (mut self Window) toggle_command_palette() {
	palette_obj := self.command_palette.get()
	if !isnil(palette_obj) {
		defer {
			object_unref(palette_obj)
		}
		if existing := command_palette_from_object(palette_obj) {
			mut palette := unsafe { existing }
			palette.toggle(self)
			return
		}
		self.command_palette.set(unsafe { nil })
	}

	mut palette := new_command_palette()
	defer {
		palette.unref()
	}
	palette.app = self.app
	C.g_object_bind_property(self.obj, c'config', palette.widget, c'config', 2)
	C.g_signal_connect_data(palette.widget, c'trigger',
		GCallback(voidptr(window_command_palette_trigger_cb)), voidptr(&self), unsafe { nil }, 0)
	self.command_palette.set(GObject(palette.widget))
	palette.toggle(self)
}

fn window_command_palette_trigger_cb(_ GObject, action &input.Action, data voidptr) {
	if !isnil(action) && !isnil(data) {
		mut self := unsafe { &Window(data) }
		self.perform_binding_action(*action)
	}
}

// --- Winproto -------------------------------------------------------------

// winproto returns the winproto backend for this window. Mirrors `winproto`.
pub fn (mut self Window) winproto() &WinProtoWindow {
	return &self.winproto
}

// --- Tab management -------------------------------------------------------

// new_tab creates a new tab with the given parent, inserted at the position
// dictated by `window-new-tab-position`. The new tab is selected. Mirrors
// `newTab`.
pub fn (mut self Window) new_tab(parent ?&core.Surface) {
	self.new_tab_page(parent, .tab)
}

// new_tab_for_window mirrors `newTabForWindow`.
pub fn (mut self Window) new_tab_for_window(parent ?&core.Surface) {
	self.new_tab_page(parent, .window)
}

// new_tab_page creates a Tab, computes its insert position, inserts/selects it,
// and wires the SplitTree changed signal. Mirrors `newTabPage`.
fn (mut self Window) new_tab_page(parent ?&core.Surface, context apprt.NewSurfaceContext) AdwTabPage {
	tab_view := self.tab_view
	if isnil(tab_view) {
		return AdwTabPage(unsafe { nil })
	}
	mut tab := new_tab(self, self.config)
	if p := parent {
		tab.set_parent_with_context(p, context)
	}

	// Compute the position to insert at.
	if isnil(self.config) {
		// If we don't have a config we just append at the end. This should
		// never happen.
		return adw_tab_view_append(tab_view, tab.widget)
	}
	position := match self.config.window_new_tab_position() {
		.current {
			selected := adw_tab_view_get_selected_page(tab_view)
			if selected == unsafe { nil } {
				adw_tab_view_get_n_pages(tab_view)
			} else {
				adw_tab_view_get_page_position(tab_view, selected) + 1
			}
		}
		.end {
			adw_tab_view_get_n_pages(tab_view)
		}
	}

	// Add the page and select it.
	page := adw_tab_view_insert(tab_view, tab.widget, position)
	tab.sync_from_active_surface()
	adw_tab_view_set_selected_page(tab_view, page)
	if tree := tab.get_surface_tree() {
		self.connect_surface_handlers(tree)
	}
	return page
}

fn window_tab_split_tree_changed_cb(split_tree GtkWidget, old_tree voidptr, new_tree voidptr, user_data voidptr) {
	_ = split_tree
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	if !isnil(old_tree) {
		tree := unsafe { &datastruct.SplitTree[SurfaceWidget](old_tree) }
		self.disconnect_surface_handlers(tree)
	}
	if !isnil(new_tree) {
		tree := unsafe { &datastruct.SplitTree[SurfaceWidget](new_tree) }
		self.connect_surface_handlers(tree)
	}
}

fn window_surface_wrapper(widget GtkWidget) ?&SurfaceWidget {
	if isnil(widget) {
		return none
	}
	priv := terminal_surface_priv(voidptr(widget))
	if isnil(priv.wrapper) {
		return none
	}
	return unsafe { &SurfaceWidget(priv.wrapper) }
}

fn window_surface_present_request_cb(widget GtkWidget, user_data voidptr) {
	if isnil(user_data) {
		return
	}
	surface := window_surface_wrapper(widget) or { return }
	mut self := unsafe { &Window(user_data) }
	self.present_surface(surface)
}

fn window_surface_clipboard_write_cb(widget GtkWidget, clipboard_type int, text_ptr &char, user_data voidptr) {
	_ = widget
	if isnil(user_data) {
		return
	}
	mut self := unsafe { &Window(user_data) }
	text := if isnil(text_ptr) { '' } else { unsafe { cstring_to_vstring(text_ptr) } }
	self.surface_clipboard_write(unsafe { apprt.Clipboard(clipboard_type) }, text)
}

fn window_surface_menu_cb(widget GtkWidget, user_data voidptr) {
	_ = widget
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.sync_actions()
	}
}

fn window_surface_toggle_fullscreen_cb(widget GtkWidget, user_data voidptr) {
	_ = widget
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.toggle_fullscreen()
	}
}

fn window_surface_toggle_maximize_cb(widget GtkWidget, user_data voidptr) {
	_ = widget
	if !isnil(user_data) {
		mut self := unsafe { &Window(user_data) }
		self.toggle_maximize()
	}
}

fn window_surface_init_cb(widget GtkWidget, user_data voidptr) {
	if isnil(user_data) {
		return
	}
	surface := window_surface_wrapper(widget) or { return }
	mut self := unsafe { &Window(user_data) }
	self.surface_initialized(surface)
}

fn (mut self Window) connect_surface_handlers(tree &datastruct.SplitTree[SurfaceWidget]) {
	mut it := tree.iterator()
	for {
		entry := it.next() or { break }
		surface := entry.view
		C.g_signal_handlers_disconnect_matched(surface.widget, g_signal_match_data, 0, 0,
			unsafe { nil }, unsafe { nil }, voidptr(self))
		C.g_signal_connect_data(surface.widget, c'present-request',
			GCallback(voidptr(window_surface_present_request_cb)), voidptr(self), unsafe { nil }, 0)
		C.g_signal_connect_data(surface.widget, c'clipboard-write',
			GCallback(voidptr(window_surface_clipboard_write_cb)), voidptr(self), unsafe { nil }, 0)
		C.g_signal_connect_data(surface.widget, c'menu',
			GCallback(voidptr(window_surface_menu_cb)), voidptr(self), unsafe { nil }, 0)
		C.g_signal_connect_data(surface.widget, c'toggle-fullscreen',
			GCallback(voidptr(window_surface_toggle_fullscreen_cb)), voidptr(self), unsafe { nil },
			0)
		C.g_signal_connect_data(surface.widget, c'toggle-maximize',
			GCallback(voidptr(window_surface_toggle_maximize_cb)), voidptr(self), unsafe { nil }, 0)
		if !self.surface_init {
			C.g_signal_connect_data(surface.widget, c'init',
				GCallback(voidptr(window_surface_init_cb)), voidptr(self), unsafe { nil }, 0)
		}
	}
}

fn (mut self Window) disconnect_surface_handlers(tree &datastruct.SplitTree[SurfaceWidget]) {
	mut it := tree.iterator()
	for {
		entry := it.next() or { break }
		C.g_signal_handlers_disconnect_matched(entry.view.widget, g_signal_match_data, 0, 0,
			unsafe { nil }, unsafe { nil }, voidptr(self))
	}
}

fn (self &Window) tab_for_page(page AdwTabPage) ?&Tab {
	if isnil(page) {
		return none
	}
	child := C.adw_tab_page_get_child(page)
	if isnil(child) || C.g_type_check_instance_is_a(child, tab_get_type()) == 0 {
		return none
	}
	priv := tab_priv(voidptr(child))
	if isnil(priv.wrapper) {
		return none
	}
	return unsafe { &Tab(priv.wrapper) }
}

// sync_selected_tab is the direct equivalent of Window's title binding group.
pub fn (mut self Window) sync_selected_tab() {
	page := adw_tab_view_get_selected_page(self.tab_view)
	if isnil(page) {
		self.sync_window_title()
		return
	}
	C.adw_tab_page_set_needs_attention(page, 0)
	tab := self.get_selected_tab() or { return }
	if title := tab.title {
		self.set_title(title)
	}
	self.sync_window_title()
}

fn (self &Window) sync_window_title() {
	if isnil(self.window_title) {
		return
	}
	title_ptr := C.gtk_window_get_title(self.as_window())
	C.adw_window_title_set_title(self.window_title, if isnil(title_ptr) {
		c''
	} else {
		title_ptr
	})
	mut subtitle := ''
	if !isnil(self.config) && self.config.get().window_subtitle == .working_directory {
		if surface := self.get_active_surface() {
			if pwd := surface.pwd {
				subtitle = pwd
			}
		}
	}
	C.adw_window_title_set_subtitle(self.window_title, &char(subtitle.str))
}

// present_surface selects the tab that owns surface, focuses it, and raises the
// window. Mirrors Window.surfacePresentRequest.
pub fn (mut self Window) present_surface(surface &SurfaceWidget) {
	// Verify ownership through the native hierarchy, which remains canonical
	// while tabs are being detached or transferred between windows.
	surface_window := C.gtk_widget_get_ancestor(surface.widget, window_get_type())
	if isnil(surface_window) {
		log.warn('present request called for non-existent surface')
		return
	}
	if surface_window != self.obj {
		log.warn('present request called for surface in different window')
		return
	}

	tab_widget := C.gtk_widget_get_ancestor(surface.widget, tab_get_type())
	if isnil(tab_widget) {
		log.warn('present request surface not found')
		return
	}
	page := C.adw_tab_view_get_page(self.tab_view, tab_widget)
	if isnil(page) {
		log.warn('present request surface tab has no page')
		return
	}
	C.adw_tab_view_set_selected_page(self.tab_view, page)
	surface.grab_focus()
	C.gtk_window_present(self.as_window())
}

// surface_initialized applies the initial default/minimum dimensions once per
// window, exactly as Ghostty's Surface.init signal handler does.
pub fn (mut self Window) surface_initialized(surface &SurfaceWidget) {
	if self.surface_init {
		return
	}
	self.surface_init = true
	if size := surface.get_default_size() {
		C.gtk_window_set_default_size(self.as_window(), int(size.width), int(size.height))
	}
	if size := surface.get_min_size() {
		C.gtk_widget_set_size_request(self.as_widget(), int(size.width), int(size.height))
	}
}

// select_tab selects the tab as requested. Returns true if the tab selection
// changed. Mirrors `selectTab` — this is pure position arithmetic and is fully
// translated.
pub fn (mut self Window) select_tab(selection SelectTab) bool {
	tab_view := self.tab_view

	// Get our current tab numeric position.
	selected := adw_tab_view_get_selected_page(tab_view)
	if selected == unsafe { nil } {
		return false
	}
	current := adw_tab_view_get_page_position(tab_view, selected)

	// Get our total.
	total := adw_tab_view_get_n_pages(tab_view)

	target := match selection {
		SelectTabPrevious {
			if current > 0 { current - 1 } else { total - 1 }
		}
		SelectTabNext {
			if current < total - 1 { current + 1 } else { 0 }
		}
		SelectTabLast {
			total - 1
		}
		SelectTabN {
			// 1-indexed
			if selection.n == 0 {
				return false
			}
			if selection.n > uint(2147483647) {
				return false
			}
			n_int := int(selection.n)
			if n_int - 1 < total - 1 {
				n_int - 1
			} else {
				total - 1
			}
		}
	}

	assert target >= 0
	assert target < total

	// If our target is the same as our current then we do nothing.
	if target == current {
		return false
	}

	// Get the page and select it.
	page := adw_tab_view_get_nth_page(tab_view, target)
	adw_tab_view_set_selected_page(tab_view, page)
	return true
}

// move_tab moves the tab containing the given surface by the given amount.
// Returns whether this affected any tab positioning. Mirrors `moveTab`. The
// wrap-around position arithmetic is fully translated.
pub fn (mut self Window) move_tab(surface &Surface, amount int) bool {
	tab_view := self.tab_view

	// If we have one tab we never move.
	total := adw_tab_view_get_n_pages(tab_view)
	if total == 1 {
		return false
	}

	if isnil(surface) || isnil(surface.surface) || isnil(surface.surface.widget) {
		return false
	}
	tab_widget := C.gtk_widget_get_ancestor(surface.surface.widget, tab_get_type())
	if isnil(tab_widget) {
		return false
	}

	// Get the page position that contains the tab.
	page := adw_tab_view_get_page(tab_view, tab_widget)
	pos := adw_tab_view_get_page_position(tab_view, page)

	// Move it (with wrap-around).
	initial := int(int(pos) + amount)
	max := total - 1
	desired_pos := if initial < 0 {
		max + initial + 1
	} else if initial > max {
		initial - max - 1
	} else {
		initial
	}
	assert desired_pos >= 0
	assert desired_pos < total

	return adw_tab_view_reorder_page(tab_view, page, desired_pos) != 0
}

// toggle_tab_overview toggles the tab overview open state. Mirrors
// `toggleTabOverview`.
pub fn (mut self Window) toggle_tab_overview() {
	tab_overview := self.tab_overview
	is_open := adw_tab_overview_get_open(tab_overview) != 0
	adw_tab_overview_set_open(tab_overview, b2i(!is_open))
}

// toggle_visibility toggles the window's visible property. Mirrors
// `toggleVisibility`.
pub fn (mut self Window) toggle_visibility() {
	widget := self.as_widget()
	visible := C.gtk_widget_get_visible(widget) != 0
	C.gtk_widget_set_visible(widget, b2i(!visible))
}

// --- Appearance -----------------------------------------------------------

// sync_appearance updates various appearance properties. This should always be
// safe to call multiple times, whenever a change happens that might affect how
// the window appears (config change, fullscreen, etc.). Mirrors
// `syncAppearance`.
fn (mut self Window) sync_appearance() {
	widget := self.as_widget()

	// Toggle style classes based on whether we're using CSDs or SSDs.
	// (See https://docs.gtk.org/gtk4/class.Window.html#css-nodes.)
	{
		// Reset all style classes first.
		for class in ['ssd', 'csd', 'solid-csd', 'no-border-radius'] {
			self.remove_css_class(class)
		}

		csd_enabled := self.winproto.client_side_decoration_enabled()
		C.gtk_window_set_decorated(self.as_window(), b2i(csd_enabled))

		if csd_enabled {
			display := C.gtk_widget_get_display(widget)

			// We do the exact same check GTK does internally and toggle either
			// the `csd` or `solid-csd` style, based on whether the user's window
			// manager is deemed non-compositing. In practice this only impacts
			// users of traditional X11 window managers.
			if C.gdk_display_is_rgba(display) != 0 && C.gdk_display_is_composited(display) != 0 {
				self.add_css_class('csd')
			} else {
				self.add_css_class('solid-csd')
			}
		} else {
			self.add_css_class('ssd')
			// Fix any artifacting that may occur in window corners.
			self.add_css_class('no-border-radius')
		}
	}

	for pspec in [g_window_pspec_headerbar_visible, g_window_pspec_tabs_autohide,
		g_window_pspec_tabs_visible, g_window_pspec_tabs_wide, g_window_pspec_toolbar_style,
		g_window_pspec_titlebar_style] {
		self.notify_property(pspec)
	}
	C.gtk_widget_set_visible(self.header_bar, b2i(self.get_headerbar_visible()))
	titlebar_tabs := self.get_titlebar_style() == .tabs
	C.gtk_widget_set_visible(self.tab_bar_start, b2i(titlebar_tabs))
	C.gtk_widget_set_visible(self.tab_bar_end, b2i(titlebar_tabs))
	csd_enabled := self.winproto.client_side_decoration_enabled()
	C.adw_tab_overview_set_show_start_title_buttons(self.tab_overview, b2i(csd_enabled))
	C.adw_tab_overview_set_show_end_title_buttons(self.tab_overview, b2i(csd_enabled))

	// Remainder uses the config.
	if self.config == unsafe { nil } {
		return
	}
	config := self.config.get()
	C.adw_tab_bar_set_autohide(self.tab_bar, b2i(self.get_tabs_autohide()))
	C.adw_tab_bar_set_expand_tabs(self.tab_bar, b2i(self.get_tabs_wide()))
	C.gtk_widget_set_visible(self.as_tab_bar_widget(), b2i(self.get_tabs_visible()))
	toolbar_style := int(self.get_toolbar_style())
	C.adw_toolbar_view_set_top_bar_style(self.toolbar, toolbar_style)
	C.adw_toolbar_view_set_bottom_bar_style(self.toolbar, toolbar_style)

	// Only add a solid background if we're opaque.
	self.toggle_css_class('background', config.background_opacity >= 1)

	// Apply class to color headerbar if window-theme is `ghostty` and GTK is
	// before 4.16. Above 4.16 we use GTK CSS color variables.
	self.toggle_css_class('window-theme-witty', !gtk_at_least(4, 16, 0)
		&& config.window_theme == .witty)

	// Move the tab bar to the proper location.
	adw_toolbar_view_remove(self.toolbar, self.as_tab_bar_widget())
	match self.config.gtk_tabs_location() {
		.top { adw_toolbar_view_add_top_bar(self.toolbar, self.as_tab_bar_widget()) }
		.bottom { adw_toolbar_view_add_bottom_bar(self.toolbar, self.as_tab_bar_widget()) }
	}

	// Do our window-protocol specific appearance sync.
	self.winproto.sync_appearance() or {
		log.warn('failed to sync winproto appearance error=${err}')
	}
}

// sync_actions syncs the state of any actions on this window. Mirrors
// `syncActions`.
fn (mut self Window) sync_actions() {
	mut has_selection := false
	if surface := self.get_active_surface() {
		if core_surface := surface.core() {
			has_selection = core_surface.has_selection()
		}
	}
	action := C.g_action_map_lookup_action(GActionMap(self.obj), c'copy')
	if !isnil(action) {
		C.g_simple_action_set_enabled(GSimpleAction(action), b2i(has_selection))
	}
}

// toggle_css_class adds or removes a CSS class based on `value`. Mirrors
// `toggleCssClass`.
fn (mut self Window) toggle_css_class(class string, value bool) {
	if value {
		self.add_css_class(class)
	} else {
		self.remove_css_class(class)
	}
}

// perform_binding_action maps the window action helpers to the canonical input
// actions and dispatches them to the active core surface.
fn (mut self Window) perform_binding_action(action input.Action) {
	mut surface := self.get_active_surface() or { return }
	mut core_surface := surface.core() or { return }
	core_surface.perform_binding_action(action) or {
		log.warn('error performing binding action error=${err}')
	}
}

// add_toast queues a simple text-based toast. All text-based toasts share the
// same timeout for consistency. Mirrors `addToast`.
//
fn (mut self Window) add_toast(title string) {
	if isnil(self.toast_overlay) {
		return
	}
	toast := C.adw_toast_new(&char(title.str))
	if isnil(toast) {
		return
	}
	C.adw_toast_set_timeout(toast, 3)
	C.adw_toast_overlay_add_toast(self.toast_overlay, toast)
}

// --- Properties -----------------------------------------------------------

fn (mut self Window) set_config_reference(config_ ?&Config) {
	config := config_ or { unsafe { nil } }
	if self.config == config {
		return
	}
	if !isnil(self.config) {
		self.config.unref()
		self.config = unsafe { nil }
	}
	if !isnil(config) {
		mut owned := unsafe { config }
		self.config = owned.ref()
	}
}

// bind_application_config mirrors Application.initAndShowWindow's
// application-config -> window-config GObject property binding. The window is
// already initialized from the current application config, so the source does
// not request an initial synchronization.
fn (mut self Window) bind_application_config(app &Application) {
	if !isnil(self.config_binding) {
		object_unref(self.config_binding)
		self.config_binding = unsafe { nil }
	}
	if isnil(app) || isnil(app.obj) || isnil(self.obj) {
		return
	}
	self.config_binding = GObject(C.g_object_bind_property(app.obj, c'config', self.obj, c'config', 0))
}

fn (self &Window) notify_property(pspec &C.GParamSpec) {
	if !isnil(self.obj) && !isnil(pspec) {
		C.g_object_notify_by_pspec(self.obj, pspec)
	}
}

pub fn (mut self Window) set_quick_terminal(value bool) {
	if isnil(self.obj) {
		self.quick_terminal = value
		return
	}
	C.g_object_set(GObject(self.obj), c'quick-terminal', b2i(value), unsafe { nil })
}

// is_quick_terminal reports whether this terminal is a quick terminal. Mirrors
// `isQuickTerminal`.
pub fn (self &Window) is_quick_terminal() bool {
	return self.quick_terminal
}

// get_active_surface gets the currently active surface. See the
// "active-surface" property. This does not ref the value. Mirrors
// `getActiveSurface`.
//
pub fn (self &Window) get_active_surface() ?&SurfaceWidget {
	if isnil(self.tab_view) {
		return none
	}
	mut tab := self.get_selected_tab() or { return none }
	return tab.get_active_surface()
}

// get_selected_tab returns the selected page's GhosttyTab. Every page created
// by this window must have that child type, so a different child is an
// invariant violation rather than an absent selection.
fn (self &Window) get_selected_tab() ?&Tab {
	page := C.adw_tab_view_get_selected_page(self.tab_view)
	if isnil(page) {
		return none
	}
	child := C.adw_tab_page_get_child(page)
	assert C.g_type_check_instance_is_a(child, tab_get_type()) != 0
	return self.tab_for_page(page)
}

// get_config returns the configuration for this window. The reference count is
// not increased. Mirrors `getConfig`.
pub fn (self &Window) get_config() ?&Config {
	if self.config == unsafe { nil } {
		return none
	}
	return self.config
}

// get_tab_view returns the tab view for this window. Mirrors `getTabView`.
pub fn (self &Window) get_tab_view() AdwTabView {
	return self.tab_view
}

// get_window_decoration returns the current window decoration value for this
// window. Mirrors `getWindowDecoration`.
pub fn (self &Window) get_window_decoration() configpkg.WindowDecoration {
	if self.has_window_decoration {
		return self.window_decoration
	}
	if self.config != unsafe { nil } {
		return self.config.get().window_decoration
	}
	return .auto
}

// toggle_window_decorations toggles the window decorations for this window.
// Mirrors `toggleWindowDecorations`.
pub fn (mut self Window) toggle_window_decorations() {
	if self.has_window_decoration {
		// Unset any previously set window decoration settings.
		self.unset_window_decoration()
		return
	}

	if self.config == unsafe { nil } {
		return
	}
	config := self.config.get()
	new_deco := match config.window_decoration {
		// Use auto when the decoration is initially none.
		.none_ { configpkg.WindowDecoration.auto }
		// Anything non-none to none.
		.auto, .client, .server { configpkg.WindowDecoration.none_ }
	}

	self.set_window_decoration(new_deco)
}

// set_window_decoration sets the window decoration override for this window.
// Mirrors the non-null branch of `setWindowDecoration`.
fn (mut self Window) set_window_decoration(new configpkg.WindowDecoration) {
	self.window_decoration = new
	self.has_window_decoration = true
	self.sync_appearance()
}

// unset_window_decoration reverts the window decoration to the config default.
// Mirrors the null branch of `setWindowDecoration`.
fn (mut self Window) unset_window_decoration() {
	self.has_window_decoration = false
	self.sync_appearance()
}

// get_needs_confirm_quit returns true if this window needs confirmation before
// quitting. Mirrors `getNeedsConfirmQuit`.
//
fn (self &Window) get_needs_confirm_quit() bool {
	if isnil(self.tab_view) {
		return false
	}
	n := C.adw_tab_view_get_n_pages(self.tab_view)
	assert n >= 0
	for i in 0 .. n {
		page := C.adw_tab_view_get_nth_page(self.tab_view, i)
		tab := self.tab_for_page(page) or {
			log.warn('unexpected non-Tab child in tab view')
			continue
		}
		if tab.get_needs_confirm_quit() {
			return true
		}
	}
	return false
}

// is_fullscreen reports whether the window is fullscreen. Mirrors
// `isFullscreen`.
pub fn (self &Window) is_fullscreen() bool {
	return C.gtk_window_is_fullscreen(self.as_window()) != 0
}

// is_maximized reports whether the window is maximized. Mirrors `isMaximized`.
pub fn (self &Window) is_maximized() bool {
	return C.gtk_window_is_maximized(self.as_window()) != 0
}

// get_headerbar_visible computes whether the header bar should be visible.
// Mirrors `getHeaderbarVisible` — fully translated logic.
pub fn (self &Window) get_headerbar_visible() bool {
	// Never display the header bar when CSDs are disabled.
	if !self.winproto.client_side_decoration_enabled() {
		return false
	}

	// Never display the header bar as a quick terminal.
	if self.quick_terminal {
		return false
	}

	// If we're fullscreen we never show the header bar.
	if self.is_fullscreen() {
		return false
	}

	// The remainder needs a config.
	if self.config == unsafe { nil } {
		return true
	}

	// Conditionally disable the header bar when maximized and
	// gtk-titlebar-hide-when-maximized is set.
	if self.is_maximized() && self.config.gtk_titlebar_hide_when_maximized() {
		return false
	}

	return match self.config.gtk_titlebar_style() {
		// If the titlebar style is tabs never show the titlebar.
		.tabs { false }
		// If the titlebar style is native show the titlebar if configured to.
		.native { self.config.gtk_titlebar() }
	}
}

// get_tabs_autohide computes whether the tab bar should autohide. Mirrors
// `getTabsAutohide` — fully translated logic.
pub fn (self &Window) get_tabs_autohide() bool {
	if self.config == unsafe { nil } {
		return true
	}
	return match self.config.gtk_titlebar_style() {
		// If the titlebar style is tabs we cannot autohide.
		.tabs {
			false
		}
		.native {
			match self.config.window_show_tab_bar() {
				// Auto we always autohide... obviously.
				.auto { true }
				// Always we never autohide because we always show the tab bar.
				.always { false }
				// Never we autohide because it doesn't matter (getTabsVisible
				// returns false).
				.never { true }
			}
		}
	}
}

// get_tabs_visible computes whether the tab bar should be visible. Mirrors
// `getTabsVisible` — fully translated logic.
pub fn (self &Window) get_tabs_visible() bool {
	if self.config == unsafe { nil } {
		return true
	}
	return match self.config.gtk_titlebar_style() {
		.tabs {
			// Conditionally disable the tab bar when maximized, style is tabs,
			// and gtk-titlebar-hide-when-maximized is set.
			if self.is_maximized() && self.config.gtk_titlebar_hide_when_maximized() {
				false
			} else {
				// If the titlebar style is tabs the tab bar is always visible.
				true
			}
		}
		.native {
			match self.config.window_show_tab_bar() {
				.always, .auto { true }
				.never { false }
			}
		}
	}
}

// get_tabs_wide computes whether tabs should be wide. Mirrors `getTabsWide`.
pub fn (self &Window) get_tabs_wide() bool {
	if self.config == unsafe { nil } {
		return true
	}
	return self.config.gtk_wide_tabs()
}

// get_toolbar_style computes the AdwToolbarStyle from the config. Mirrors
// `getToolbarStyle`.
pub fn (self &Window) get_toolbar_style() AdwToolbarStyle {
	if self.config == unsafe { nil } {
		return .raised
	}
	return match self.config.gtk_toolbar_style() {
		.flat { AdwToolbarStyle.flat }
		.raised { AdwToolbarStyle.raised }
		.raised_border { AdwToolbarStyle.raised_border }
	}
}

// get_titlebar_style computes the GtkTitlebarStyle from the config. Mirrors
// `getTitlebarStyle`.
pub fn (self &Window) get_titlebar_style() configpkg.GtkTitlebarStyle {
	if self.config == unsafe { nil } {
		return .native
	}
	return self.config.gtk_titlebar_style()
}

// --- Fullscreen / maximize toggles ----------------------------------------

// toggle_fullscreen toggles the fullscreen state. Mirrors the body of
// `surfaceToggleFullscreen`.
pub fn (mut self Window) toggle_fullscreen() {
	if self.is_fullscreen() {
		self.unfullscreen()
	} else {
		self.fullscreen()
	}
	// We react to the changes in the prop_fullscreen callback.
}

// toggle_maximize toggles the maximized state. Mirrors the body of
// `surfaceToggleMaximize`.
pub fn (mut self Window) toggle_maximize() {
	if self.is_maximized() {
		self.unmaximize()
	} else {
		self.maximize()
	}
	// We react to the changes in the prop_maximized callback.
}

// --- Signal-handler-equivalents (config/prop reactions) -------------------

// window_realize initializes the window protocol logic once the window is
// realized, sets up resize notifications, and syncs appearance. Mirrors
// `windowRealize`.
pub fn (mut self Window) window_realize(mut app Application) {
	// Initialize our window protocol logic.
	mut app_wp := app.winproto()
	if wp := WinProtoWindow.init(mut app_wp, mut self.apprt_window) {
		self.winproto = wp
	} else {
		log.warn('failed to initialize window protocol error=${err}')
		return
	}

	gdk_surface := C.gtk_native_get_surface(self.as_native())
	if !isnil(gdk_surface) {
		C.g_signal_connect_data(gdk_surface, c'notify::width',
			GCallback(voidptr(window_gdk_surface_resize_cb)), voidptr(self), unsafe { nil }, 0)
		C.g_signal_connect_data(gdk_surface, c'notify::height',
			GCallback(voidptr(window_gdk_surface_resize_cb)), voidptr(self), unsafe { nil }, 0)
	}

	// When we are realized we always setup our appearance since this calls
	// some winproto functions.
	self.sync_appearance()
}

// prop_config reacts to a config change: optionally toasts, then syncs
// appearance. Mirrors `propConfig`.
pub fn (mut self Window) prop_config() {
	if !isnil(self.config) && self.config.get().app_notifications.config_reload() {
		self.add_toast(i18n_('Reloaded the configuration'))
	}
	self.sync_appearance()
	palette_obj := self.command_palette.get()
	if !isnil(palette_obj) {
		if existing := command_palette_from_object(palette_obj) {
			mut palette := unsafe { existing }
			palette.app = self.app
			palette.set_config(self.config)
		}
		object_unref(palette_obj)
	}
}

// surface_clipboard_write shows the same standard-clipboard toast as
// Ghostty's Surface clipboard-write signal handler.
fn (mut self Window) surface_clipboard_write(clipboard_type apprt.Clipboard, text string) {
	if clipboard_type != .standard || isnil(self.config)
		|| !self.config.get().app_notifications.clipboard_copy() {
		return
	}
	self.add_toast(if text.len > 0 {
		i18n_('Copied to clipboard')
	} else {
		i18n_('Cleared clipboard')
	})
}

// prop_gdk_surface_resize reacts to a GdkSurface width/height change (X11 blur
// fix). Mirrors `propGdkSurfaceWidth`/`propGdkSurfaceHeight`.
pub fn (mut self Window) prop_gdk_surface_resize() {
	self.winproto.resize_event() or { log.warn('winproto resize event failed error=${err}') }
}

// prop_is_active reacts to the window active state changing. Mirrors
// `propIsActive`.
pub fn (mut self Window) prop_is_active() {
	// Hide quick-terminal if set to autohide.
	if self.is_quick_terminal() {
		if !isnil(self.config) && self.config.get().quick_terminal_autohide
			&& C.gtk_window_is_active(self.as_window()) == 0 {
			self.toggle_visibility()
		}
	}

	// Don't change urgency if we're not the active window.
	if C.gtk_window_is_active(self.as_window()) == 0 {
		return
	}

	self.winproto.set_urgent(false) or { log.warn('winproto failed to reset urgency=${err}') }
}

// prop_fullscreened reacts to the fullscreen state changing. Mirrors
// `propFullscreened`.
pub fn (mut self Window) prop_fullscreened() {
	self.sync_appearance()
}

// prop_maximized reacts to the maximized state changing. Mirrors
// `propMaximized`.
pub fn (mut self Window) prop_maximized() {
	self.sync_appearance()
}

// prop_scale_factor reacts to a scale-factor change (X11 refresh). Mirrors
// `propScaleFactor`.
pub fn (mut self Window) prop_scale_factor() {
	self.winproto.sync_appearance() or {
		log.warn('failed to sync appearance after scale factor has been updated=${err}')
	}
}

// prop_quick_terminal reacts to the quick-terminal property changing. Mirrors
// `propQuickTerminal`.
pub fn (mut self Window) prop_quick_terminal(mut app Application) {
	if self.surface_init {
		log.warn("quick terminal property can't be changed after surfaces have been initialized")
		return
	}
	if self.quick_terminal {
		// Initialize the quick terminal at the app-layer.
		mut app_wp := app.winproto()
		app_wp.init_quick_terminal(mut self.apprt_window) or {
			log.warn('failed to initialize quick terminal error=${err}')
			return
		}
	}
}

// --- Window close / lifecycle ---------------------------------------------

// window_close_request handles a window close request, showing a confirmation
// dialog if needed. Returns true to stop propagation (keep window open).
// Mirrors `windowCloseRequest`.
pub fn (mut self Window) window_close_request() bool {
	if self.get_needs_confirm_quit() {
		mut dialog := close_confirmation_dialog_new(.window)
		C.g_signal_connect_data(dialog.dialog.obj, c'close-request',
			GCallback(voidptr(window_close_confirmed_cb)), voidptr(self), unsafe { nil }, 0)
		dialog.present(self.as_widget())
		return true
	}
	C.gtk_window_destroy(self.as_window())
	return false
}

fn window_close_confirmed_cb(dialog GObject, user_data voidptr) {
	_ = dialog
	if isnil(user_data) {
		return
	}
	self := unsafe { &Window(user_data) }
	C.gtk_window_destroy(self.as_window())
}

// tab_view_n_pages reacts to the tab view's page count changing: if there are
// no pages left (and the tab overview is closed) we close the window. Mirrors
// `tabViewNPages` — fully translated logic.
pub fn (mut self Window) tab_view_n_pages() {
	if adw_tab_view_get_n_pages(self.tab_view) == 0 {
		// If the tab overview is open we don't close the window (abrupt UX,
		// and it fixes dragging out the last tab).
		if adw_tab_overview_get_open(self.tab_overview) != 0 {
			return
		}
		C.gtk_window_close(self.as_window())
	}
}

// --- Actions ---------------------------------------------------------------

pub fn (mut self Window) action_about() {
	developer_name := internal_os.translate('Witty Developers')
	if supports_dialogs() {
		C.adw_show_about_dialog(self.as_widget(), c'application-name', c'Witty',
			c'developer-name', &char(developer_name.str), c'application-icon',
			c'com.alexander.witty', c'version', &char(build_meta.version_string.str),
			c'issue-url', c'https://github.com/witty-terminal/witty/issues', c'website',
			c'https://github.com/witty-terminal/witty', unsafe { nil })
		return
	}

	title := internal_os.translate('About Witty')
	C.gtk_show_about_dialog(self.as_window(), c'program-name', c'Witty', c'logo-icon-name',
		c'com.alexander.witty', c'title', &char(title.str), c'version',
		&char(build_meta.version_string.str), c'website', c'https://github.com/witty-terminal/witty', unsafe { nil })
}

pub fn (mut self Window) toggle_inspector() {
	mut surface := self.get_active_surface() or { return }
	_ = surface.control_inspector(.toggle)
}

pub fn (mut self Window) action_close() {
	C.gtk_window_close(self.as_window())
}

pub fn (mut self Window) action_new_tab() {
	self.perform_binding_action(input.ActionNewTab{})
}

pub fn (mut self Window) action_new_window() {
	self.perform_binding_action(input.ActionNewWindow{})
}

pub fn (mut self Window) action_split_right() {
	self.perform_binding_action(input.ActionNewSplit{ value: .right })
}

pub fn (mut self Window) action_split_left() {
	self.perform_binding_action(input.ActionNewSplit{ value: .left })
}

pub fn (mut self Window) action_split_up() {
	self.perform_binding_action(input.ActionNewSplit{ value: .up })
}

pub fn (mut self Window) action_split_down() {
	self.perform_binding_action(input.ActionNewSplit{ value: .down })
}

pub fn (mut self Window) action_copy() {
	self.perform_binding_action(input.ActionCopyToClipboard{ value: .mixed })
}

pub fn (mut self Window) action_paste() {
	self.perform_binding_action(input.ActionPasteFromClipboard{})
}

pub fn (mut self Window) action_reset() {
	self.perform_binding_action(input.ActionReset{})
}

pub fn (mut self Window) action_clear() {
	self.perform_binding_action(input.ActionClearScreen{})
}

pub fn (mut self Window) action_ring_bell() {
	if isnil(self.config) {
		return
	}
	cfg := self.config.get()
	if cfg.bell_features.system() {
		native_surface := C.gtk_native_get_surface(self.as_native())
		if isnil(native_surface) {
			log.warn('unable to get native surface from window')
		} else {
			C.gdk_surface_beep(native_surface)
		}
	}

	if cfg.bell_features.attention() {
		if C.gtk_window_is_active(self.as_window()) != 0 {
			return
		}
		self.winproto.set_urgent(true) or { log.warn('winproto failed to set urgency=${err}') }
	}
}

// --- dispose / finalize ---------------------------------------------------

fn (mut self Window) dispose_resources() {
	if self.disposed {
		return
	}
	self.disposed = true
	if self.tab_overview_focus_timer != 0 {
		C.g_source_remove(self.tab_overview_focus_timer)
		self.tab_overview_focus_timer = 0
	}
	for mut tab in self.tabs {
		C.g_signal_handlers_disconnect_matched(tab.widget, g_signal_match_data, 0, 0,
			unsafe { nil }, unsafe { nil }, voidptr(self))
		if !isnil(tab.split_tree) {
			C.g_signal_handlers_disconnect_matched(tab.split_tree.widget, g_signal_match_data, 0,
				0, unsafe { nil }, unsafe { nil }, voidptr(self))
			if tree := tab.get_surface_tree() {
				self.disconnect_surface_handlers(tree)
			}
		}
		tab.window = unsafe { nil }
	}
	self.tabs.clear()
	// Drop the template-child reference taken in init, as GTK's template
	// dispose does.
	if !isnil(self.tab_bar) {
		object_unref(GObject(self.tab_bar))
		self.tab_bar = unsafe { nil }
	}
	self.command_palette.set(unsafe { nil })
	if !isnil(self.config_binding) {
		object_unref(self.config_binding)
		self.config_binding = unsafe { nil }
	}

	if self.config != unsafe { nil } {
		self.config.unref()
		self.config = unsafe { nil }
	}
	if !isnil(self.app) {
		mut app := unsafe { self.app }
		for i, candidate in app.windows {
			if candidate == self {
				app.windows.delete(i)
				break
			}
		}
	}
}

// dispose releases references held by the window. Native instances call this
// before chaining to AdwApplicationWindow.dispose.
pub fn (mut self Window) dispose() {
	self.dispose_resources()
}

fn (mut self Window) finalize_resources() {
	if self.finalized {
		return
	}
	self.finalized = true
	self.winproto.deinit()
	self.app = unsafe { nil }
	self.tab_overview = unsafe { nil }
	self.tab_bar = unsafe { nil }
	self.tab_view = unsafe { nil }
	self.toolbar = unsafe { nil }
	self.toast_overlay = unsafe { nil }
	self.header_bar = unsafe { nil }
	self.window_title = unsafe { nil }
	self.tab_bar_start = unsafe { nil }
	self.tab_bar_end = unsafe { nil }
	self.overview_header_toggle = unsafe { nil }
	self.overview_tab_toggle = unsafe { nil }
}

// finalize tears down protocol state. Native instances then chain to the
// AdwApplicationWindow parent finalizer.
pub fn (mut self Window) finalize() {
	self.finalize_resources()
}

// --- Upcasts / thin wrappers ----------------------------------------------

// as_widget returns this window upcast to a GtkWidget. Mirrors
// `self.as(gtk.Widget)`.
pub fn (self &Window) as_widget() GtkWidget {
	return GtkWidget(self.obj)
}

// as_window returns this window upcast to a GtkWindow. Mirrors
// `self.as(gtk.Window)`.
pub fn (self &Window) as_window() GtkWindow {
	return GtkWindow(self.obj)
}

// as_native returns this window upcast to a GtkNative. Mirrors
// `self.as(gtk.Native)`.
pub fn (self &Window) as_native() GtkNative {
	return GtkNative(self.obj)
}

// as_tab_bar_widget returns the tab bar upcast to a GtkWidget. Mirrors
// `priv.tab_bar.as(gtk.Widget)`.
fn (self &Window) as_tab_bar_widget() GtkWidget {
	return GtkWidget(self.tab_bar)
}

fn (self &Window) set_title(title string) {
	C.gtk_window_set_title(self.as_window(), &char(title.str))
	if !isnil(self.window_title) {
		C.adw_window_title_set_title(self.window_title, &char(title.str))
	}
}

fn (self &Window) set_icon_name(name string) {
	C.gtk_window_set_icon_name(self.as_window(), &char(name.str))
}

fn (self &Window) maximize() {
	C.gtk_window_maximize(self.as_window())
}

fn (self &Window) unmaximize() {
	C.gtk_window_unmaximize(self.as_window())
}

fn (self &Window) fullscreen() {
	C.gtk_window_fullscreen(self.as_window())
}

fn (self &Window) unfullscreen() {
	C.gtk_window_unfullscreen(self.as_window())
}

fn (self &Window) add_css_class(class string) {
	C.gtk_widget_add_css_class(self.as_widget(), &char(class.str))
}

fn (self &Window) remove_css_class(class string) {
	C.gtk_widget_remove_css_class(self.as_widget(), &char(class.str))
}

// b2i converts a bool to a C int (0/1), matching the `@intFromBool` idiom.
fn b2i(b bool) int {
	return if b { 1 } else { 0 }
}

// --- AdwTabView / AdwTabOverview / AdwToolbarView C bindings ---------------
// Wrapped so the tab-management arithmetic above stays readable. These are new
// (grep-verified not declared elsewhere).

fn C.adw_tab_view_get_n_pages(view AdwTabView) int

fn C.adw_tab_view_get_selected_page(view AdwTabView) AdwTabPage

fn C.adw_tab_view_set_selected_page(view AdwTabView, page AdwTabPage)

fn C.adw_tab_view_get_page_position(view AdwTabView, page AdwTabPage) int

fn C.adw_tab_view_get_nth_page(view AdwTabView, position int) AdwTabPage

fn C.adw_tab_view_get_page(view AdwTabView, child GtkWidget) AdwTabPage

fn C.adw_tab_view_append(view AdwTabView, child GtkWidget) AdwTabPage

fn C.adw_tab_view_insert(view AdwTabView, child GtkWidget, position int) AdwTabPage

fn C.adw_tab_view_reorder_page(view AdwTabView, page AdwTabPage, position int) int

fn C.adw_tab_overview_get_open(overview AdwTabOverview) int

fn C.adw_tab_overview_set_open(overview AdwTabOverview, open int)

fn C.adw_toolbar_view_remove(view AdwToolbarView, child GtkWidget)

fn C.adw_toolbar_view_add_top_bar(view AdwToolbarView, child GtkWidget)

fn C.adw_toolbar_view_add_bottom_bar(view AdwToolbarView, child GtkWidget)

fn adw_tab_view_get_n_pages(view AdwTabView) int {
	return C.adw_tab_view_get_n_pages(view)
}

fn adw_tab_view_get_selected_page(view AdwTabView) AdwTabPage {
	return C.adw_tab_view_get_selected_page(view)
}

fn adw_tab_view_set_selected_page(view AdwTabView, page AdwTabPage) {
	C.adw_tab_view_set_selected_page(view, page)
}

fn adw_tab_view_get_page_position(view AdwTabView, page AdwTabPage) int {
	return C.adw_tab_view_get_page_position(view, page)
}

fn adw_tab_view_get_nth_page(view AdwTabView, position int) AdwTabPage {
	return C.adw_tab_view_get_nth_page(view, position)
}

fn adw_tab_view_get_page(view AdwTabView, child GtkWidget) AdwTabPage {
	return C.adw_tab_view_get_page(view, child)
}

fn adw_tab_view_append(view AdwTabView, child GtkWidget) AdwTabPage {
	return C.adw_tab_view_append(view, child)
}

fn adw_tab_view_insert(view AdwTabView, child GtkWidget, position int) AdwTabPage {
	return C.adw_tab_view_insert(view, child, position)
}

fn adw_tab_view_reorder_page(view AdwTabView, page AdwTabPage, position int) int {
	return C.adw_tab_view_reorder_page(view, page, position)
}

fn adw_tab_overview_get_open(overview AdwTabOverview) int {
	return C.adw_tab_overview_get_open(overview)
}

fn adw_tab_overview_set_open(overview AdwTabOverview, open int) {
	C.adw_tab_overview_set_open(overview, open)
}

fn adw_toolbar_view_remove(view AdwToolbarView, child GtkWidget) {
	C.adw_toolbar_view_remove(view, child)
}

fn adw_toolbar_view_add_top_bar(view AdwToolbarView, child GtkWidget) {
	C.adw_toolbar_view_add_top_bar(view, child)
}

fn adw_toolbar_view_add_bottom_bar(view AdwToolbarView, child GtkWidget) {
	C.adw_toolbar_view_add_bottom_bar(view, child)
}
