@[has_globals]
module gtk

// tab_linux.v - The GObject Tab *widget* class for the GTK apprt.
//
// Translated from ghostty/src/apprt/gtk/class/tab.zig.
//
// A Tab is the content of a single AdwTabPage: it holds a SplitTree (which in
// turn holds one or more terminal surfaces) plus the tab's title/tooltip state.
// In ghostty this is a `GhosttyTab` GObject class (a gtk.Box) defined with a
// `.ui`/blueprint template, GObject property/signal registration, and
// template-child bindings.
//
// The class is modeled as a stable V wrapper around a real GhosttyTab GtkBox
// subclass. Its native properties, close-request signal, ownership vfuncs, and
// SplitTree notification wiring mirror the pinned Zig class; the blueprint's
// title/tooltip expressions are evaluated by sync_from_active_surface.

import core
import datastruct
import apprt
import log

// --- New Adw C bindings unique to this file -------------------------------
//
// AdwTabView / AdwTabPage functions used by the tab-page action logic. Grep-
// verified that none of these `fn C.` decls already exist in the module.

fn C.adw_tab_page_get_selected(page AdwTabPage) int

fn C.adw_tab_page_set_needs_attention(page AdwTabPage, needs_attention int)

fn C.adw_tab_page_set_title(page AdwTabPage, title &char)

fn C.adw_tab_page_set_tooltip(page AdwTabPage, tooltip &char)

fn C.adw_tab_view_select_next_page(view AdwTabView) int

fn C.adw_tab_view_select_previous_page(view AdwTabView) int

fn C.adw_tab_view_close_page(view AdwTabView, page AdwTabPage)

fn C.adw_tab_view_close_other_pages(view AdwTabView, page AdwTabPage)

fn C.adw_tab_view_close_pages_after(view AdwTabView, page AdwTabPage)

fn C.adw_tab_view_get_type() GType

fn C.gtk_widget_get_ancestor(widget GtkWidget, widget_type GType) GtkWidget

fn C.gtk_widget_set_hexpand(widget GtkWidget, expand int)

fn C.gtk_widget_set_vexpand(widget GtkWidget, expand int)

fn C.gtk_orientable_set_orientation(orientable voidptr, orientation int)

__global g_tab_type = GType(0)

// The instance-private offset: the size until class_init adjusts it, then
// the (negative) offset from the instance. Mirrors zig-gobject's `Private.offset`.
__global g_tab_priv_offset = int(0)
__global g_tab_pspec_active_surface = &C.GParamSpec(unsafe { nil })
__global g_tab_pspec_config = &C.GParamSpec(unsafe { nil })
__global g_tab_pspec_split_tree = &C.GParamSpec(unsafe { nil })
__global g_tab_pspec_surface_tree = &C.GParamSpec(unsafe { nil })
__global g_tab_pspec_title = &C.GParamSpec(unsafe { nil })
__global g_tab_pspec_tooltip = &C.GParamSpec(unsafe { nil })

struct C.GhosttyTabPrivate {
mut:
	wrapper voidptr
}

const tab_prop_active_surface = u32(1)
const tab_prop_config = u32(2)
const tab_prop_split_tree = u32(3)
const tab_prop_surface_tree = u32(4)
const tab_prop_title = u32(5)
const tab_prop_tooltip = u32(6)
const tab_param_static_strings = int(32 | 64 | 128)

fn tab_priv(obj voidptr) &C.GhosttyTabPrivate {
	return &C.GhosttyTabPrivate(instance_private(obj, g_tab_priv_offset))
}

fn tab_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := tab_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &Tab(priv.wrapper) }
	match property_id {
		tab_prop_active_surface {
			if surface := self.get_active_surface() {
				C.g_value_set_object(value, surface.widget)
			} else {
				C.g_value_set_object(value, unsafe { nil })
			}
		}
		tab_prop_config {
			if isnil(self.config) {
				C.g_value_set_object(value, unsafe { nil })
			} else {
				C.g_value_set_object(value, self.config.obj)
			}
		}
		tab_prop_split_tree {
			if isnil(self.split_tree) {
				C.g_value_set_object(value, unsafe { nil })
			} else {
				C.g_value_set_object(value, self.split_tree.widget)
			}
		}
		tab_prop_surface_tree {
			if tree := self.get_surface_tree() {
				C.g_value_set_boxed(value, tree)
			} else {
				C.g_value_set_boxed(value, unsafe { nil })
			}
		}
		tab_prop_title {
			if title := self.title {
				C.g_value_set_string(value, &char(title.str))
			} else {
				C.g_value_set_string(value, unsafe { nil })
			}
		}
		tab_prop_tooltip {
			if tooltip := self.tooltip {
				C.g_value_set_string(value, &char(tooltip.str))
			} else {
				C.g_value_set_string(value, unsafe { nil })
			}
		}
		else {}
	}
}

fn tab_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := tab_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &Tab(priv.wrapper) }
	match property_id {
		tab_prop_config {
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
		tab_prop_title {
			text := C.g_value_get_string(value)
			self.set_title(if isnil(text) {
				?string(none)
			} else {
				?string(unsafe { cstring_to_vstring(text) })
			})
		}
		tab_prop_tooltip {
			text := C.g_value_get_string(value)
			self.set_tooltip(if isnil(text) {
				?string(none)
			} else {
				?string(unsafe { cstring_to_vstring(text) })
			})
		}
		else {}
	}
}

fn tab_dispose(obj voidptr) {
	priv := tab_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Tab(priv.wrapper) }
		self.set_config_reference(none)
	}
	C.witty_gobject_call_parent_dispose(obj)
}

fn tab_finalize(obj voidptr) {
	mut priv := tab_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &Tab(priv.wrapper) }
		self.title = none
		self.title_override = none
		self.tooltip = none
		self.widget = unsafe { nil }
		self.split_tree = unsafe { nil }
		priv.wrapper = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

fn tab_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_tab_priv_offset)
	_ = class_data
	_ = split_tree_get_type()
	_ = terminal_surface_get_type()
	_ = config_get_type()
	C.witty_gobject_class_set_get_property(klass, voidptr(tab_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(tab_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(tab_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(tab_finalize))
	readable := g_param_readable | tab_param_static_strings
	readwrite := g_param_readwrite | tab_param_static_strings
	nil_str := &char(unsafe { nil })
	g_tab_pspec_active_surface = C.g_param_spec_object(c'active-surface', nil_str, nil_str, terminal_surface_get_type(), readable)
	g_tab_pspec_config = C.g_param_spec_object(c'config', nil_str, nil_str, config_get_type(), readwrite)
	g_tab_pspec_split_tree = C.g_param_spec_object(c'split-tree', nil_str, nil_str, split_tree_get_type(), readable)
	g_tab_pspec_surface_tree = C.g_param_spec_boxed(c'surface-tree', nil_str, nil_str, surface_tree_get_type(), readable)
	g_tab_pspec_title = C.g_param_spec_string(c'title', nil_str, nil_str, nil_str, readwrite)
	g_tab_pspec_tooltip = C.g_param_spec_string(c'tooltip', nil_str, nil_str, nil_str, readwrite)
	C.g_object_class_install_property(klass, tab_prop_active_surface, g_tab_pspec_active_surface)
	C.g_object_class_install_property(klass, tab_prop_config, g_tab_pspec_config)
	C.g_object_class_install_property(klass, tab_prop_split_tree, g_tab_pspec_split_tree)
	C.g_object_class_install_property(klass, tab_prop_surface_tree, g_tab_pspec_surface_tree)
	C.g_object_class_install_property(klass, tab_prop_title, g_tab_pspec_title)
	C.g_object_class_install_property(klass, tab_prop_tooltip, g_tab_pspec_tooltip)
	C.g_signal_new(c'close-request', g_tab_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
}

fn tab_instance_init(instance voidptr, klass voidptr) {
	_ = klass
	C.gtk_orientable_set_orientation(instance, 1)
	C.gtk_widget_set_hexpand(GtkWidget(instance), 1)
	C.gtk_widget_set_vexpand(GtkWidget(instance), 1)
}

pub fn tab_get_type() GType {
	if g_tab_type == GType(0) {
		parent := C.gtk_box_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(tab_class_init)
			instance_init: voidptr(tab_instance_init)
		}
		g_tab_type = C.g_type_register_static(parent, c'GhosttyTab', &info, 0)
		g_tab_priv_offset = C.g_type_add_instance_private(g_tab_type, sizeof(C.GhosttyTabPrivate))
	}
	return g_tab_type
}

// --- CloseTabMode ---------------------------------------------------------

// CloseTabMode is the canonical C-backed apprt action value consumed by the
// source tab.close action.
pub type CloseTabMode = apprt.CloseTabMode

// --- Tab ------------------------------------------------------------------

// Tab is the V model of the `GhosttyTab` GObject class. It wraps the
// GObject/GtkWidget pointer and carries the state that lived in the Zig
// `Private` struct; the native instance private data points back to this stable
// wrapper for property and lifecycle dispatch.
@[heap]
pub struct Tab {
pub mut:
	// The GtkWidget (gtk.Box) pointer for this instance.
	widget GtkWidget = unsafe { nil }

	// The configuration this tab is using.
	config &Config = unsafe { nil }
	window &Window = unsafe { nil }

	// The title of this tab. Usually bound to the active surface.
	title ?string

	// The tooltip of this tab. Usually bound to the active surface.
	tooltip ?string

	// The split tree widget that holds this tab's surface(s) (template child).
	split_tree &SplitTreeWidget = unsafe { nil }
mut:
	title_override ?string
}

// --- Construction ---------------------------------------------------------

// new_tab creates a new Tab. Mirrors the GObject `init`: it pulls the config
// from the application if unset and creates the initial surface in the split
// tree.
pub fn new_tab(window &Window, config &Config) &Tab {
	// A tab constructed without an explicit config inherits the application's
	// config in Ghostty's instance initializer.
	mut effective_config := config
	mut inherited_config := false
	if isnil(effective_config) {
		mut app := Application.default()
		effective_config = app.get_config()
		inherited_config = true
	}
	defer {
		if inherited_config {
			mut owned := effective_config
			owned.unref()
		}
	}

	obj := C.g_object_new(tab_get_type(), &char(unsafe { nil }))
	split_tree := new_split_tree_widget(window, effective_config)
	C.gtk_box_append(GtkWidget(obj), split_tree.widget)
	mut self := &Tab{
		widget:     GtkWidget(obj)
		window:     window
		split_tree: split_tree
	}
	mut priv := tab_priv(obj)
	priv.wrapper = voidptr(self)
	self.set_config_reference(effective_config)
	C.g_signal_connect_data(split_tree.widget, c'notify::tree', GCallback(voidptr(tab_split_tree_notify_tree_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(split_tree.widget, c'notify::active-surface', GCallback(voidptr(tab_split_tree_notify_active_surface_cb)), voidptr(self), unsafe { nil }, 0)

	// Init our actions.
	self.init_action_map()
	self.split_tree.new_split(.right, none)

	return self
}

pub fn (mut self Tab) ref() &Tab {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

pub fn (mut self Tab) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

fn tab_split_tree_notify_tree_cb(split_tree GtkWidget, pspec voidptr, data voidptr) {
	_ = split_tree
	_ = pspec
	if !isnil(data) {
		mut self := unsafe { &Tab(data) }
		self.prop_split_tree()
	}
}

fn tab_split_tree_notify_active_surface_cb(split_tree GtkWidget, pspec voidptr, data voidptr) {
	_ = split_tree
	_ = pspec
	if !isnil(data) {
		mut self := unsafe { &Tab(data) }
		self.prop_active_surface()
	}
}

// init_action_map registers the "tab" action group. Mirrors `initActionMap`.
fn (mut self Tab) init_action_map() {
	string_type := C.g_variant_type_new(c's')
	actions := [
		Action.init('close', GCallback(voidptr(tab_action_close_cb)), string_type),
		Action.init('ring-bell', GCallback(voidptr(tab_action_ring_bell_cb)), unsafe { nil }),
		Action.init('next-page', GCallback(voidptr(tab_action_next_page_cb)), unsafe { nil }),
		Action.init('previous-page', GCallback(voidptr(tab_action_previous_page_cb)), unsafe { nil }),
	]
	add_as_group(voidptr(self), self.widget, 'tab', actions)
	C.g_variant_type_free(string_type)
}

fn tab_action_close_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	if isnil(data) {
		return
	}
	if isnil(parameter) {
		log.warn('tab.close-tab called without a parameter')
		return
	}
	mut length := uint(0)
	value := C.g_variant_get_string(parameter, &length)
	mut self := unsafe { &Tab(data) }
	self.action_close(if isnil(value) {
		?string(none)
	} else {
		?string(unsafe { cstring_to_vstring(value) })
	})
}

// action_close handles the "tab.close" action. Mirrors `actionClose`: it
// resolves the parent page before validating the externally supplied mode,
// then delegates to AdwTabView so its close-page signal can be intercepted.
fn (mut self Tab) action_close(mode_ ?string) {
	tab_view := self.get_tab_view()
	if isnil(tab_view) {
		return
	}
	page := C.adw_tab_view_get_page(tab_view, self.widget)

	mode_value := mode_ or {
		log.warn('invalid mode provided to tab.close-tab')
		return
	}
	mode := match mode_value {
		'this' { CloseTabMode.this }
		'other' { CloseTabMode.other }
		'right' { CloseTabMode.right }
		else {
			log.warn('invalid mode provided to tab.close-tab: ${mode_value}')
			return
		}
	}

	match mode {
		.this { C.adw_tab_view_close_page(tab_view, page) }
		.other { C.adw_tab_view_close_other_pages(tab_view, page) }
		.right { C.adw_tab_view_close_pages_after(tab_view, page) }
		else { panic('invalid CloseTabMode') }
	}
}

fn tab_action_ring_bell_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	_ = parameter
	if !isnil(data) {
		mut self := unsafe { &Tab(data) }
		self.action_ring_bell()
	}
}

fn tab_action_next_page_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	_ = parameter
	if !isnil(data) {
		mut self := unsafe { &Tab(data) }
		self.action_next_page()
	}
}

fn tab_action_previous_page_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	_ = parameter
	if !isnil(data) {
		mut self := unsafe { &Tab(data) }
		self.action_previous_page()
	}
}

// set_parent sets the parent of this tab page (only affects the first surface).
// Mirrors `setParent`.
pub fn (mut self Tab) set_parent(parent &core.Surface) {
	self.set_parent_with_context(parent, .tab)
}

// set_parent_with_context sets the parent using the given context. Mirrors
// `setParentWithContext`.
pub fn (mut self Tab) set_parent_with_context(parent &core.Surface, context apprt.NewSurfaceContext) {
	if mut surface := self.get_active_surface() {
		surface.set_parent(parent, context)
	}
}

// --- Properties -----------------------------------------------------------

fn (mut self Tab) set_config_reference(config_ ?&Config) {
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

fn (self &Tab) notify_property(pspec &C.GParamSpec) {
	if !isnil(self.widget) && !isnil(pspec) {
		C.g_object_notify_by_pspec(self.widget, pspec)
	}
}

// get_active_surface returns the currently active surface, or `none`. See the
// "active-surface" property. Mirrors `getActiveSurface`. Does not ref.
pub fn (mut self Tab) get_active_surface() ?&SurfaceWidget {
	assert !isnil(self.split_tree)
	return self.split_tree.get_active_surface()
}

// get_surface_tree returns the surface tree of this tab, or `none`. Mirrors
// `getSurfaceTree`.
pub fn (mut self Tab) get_surface_tree() ?&datastruct.SplitTree[SurfaceWidget] {
	assert !isnil(self.split_tree)
	return self.split_tree.get_tree()
}

// get_split_tree returns the split tree widget in this tab. Mirrors
// `getSplitTree`.
pub fn (self &Tab) get_split_tree() &SplitTreeWidget {
	return self.split_tree
}

// get_needs_confirm_quit returns true if this tab needs confirmation before
// quitting. Mirrors `getNeedsConfirmQuit`.
pub fn (self &Tab) get_needs_confirm_quit() bool {
	assert !isnil(self.split_tree)
	return self.split_tree.get_needs_confirm_quit()
}

// get_tab_view returns the AdwTabView holding this tab, if any. Mirrors
// `getTabView`. Uses the widget ancestor lookup.
fn (self &Tab) get_tab_view() AdwTabView {
	if isnil(self.widget) {
		return AdwTabView(unsafe { nil })
	}
	return AdwTabView(C.gtk_widget_get_ancestor(self.widget, C.adw_tab_view_get_type()))
}

// get_tab_page returns the AdwTabPage holding this tab, if any. Mirrors
// `getTabPage`.
fn (self &Tab) get_tab_page() AdwTabPage {
	tab_view := self.get_tab_view()
	if isnil(tab_view) {
		return AdwTabPage(unsafe { nil })
	}
	return C.adw_tab_view_get_page(tab_view, self.widget)
}

// --- Title / tooltip ------------------------------------------------------

// get_title returns the tab title, if any. Mirrors the "title" property getter.
pub fn (self &Tab) get_title() ?string {
	return self.title
}

fn tab_from_widget(widget GtkWidget) ?&Tab {
	if isnil(widget) || C.g_type_check_instance_is_a(widget, tab_get_type()) == 0 {
		return none
	}
	priv := tab_priv(voidptr(widget))
	if isnil(priv.wrapper) {
		return none
	}
	return unsafe { &Tab(priv.wrapper) }
}

fn (self &Tab) prompt_title() {
	prompt_title_dialog(self.widget, self.config, i18n_('Change Tab Title'),
		if override := self.title_override { ?string(override) } else { self.title },
		GCallback(voidptr(tab_title_dialog_set_cb)))
}

fn tab_title_dialog_set_cb(_ GObject, title &char, widget GtkWidget) {
	mut self := tab_from_widget(widget) or { return }
	if isnil(self.window) {
		return
	}
	self.title_override = title_override_from_entry(title)
	self.sync_from_active_surface()
}

// set_title sets the tab title. Mirrors the "title" property setter.
pub fn (mut self Tab) set_title(title ?string) {
	self.title = title
	self.notify_property(g_tab_pspec_title)
	page := self.get_tab_page()
	if !isnil(page) {
		if value := title {
			C.adw_tab_page_set_title(page, &char(value.str))
		} else {
			C.adw_tab_page_set_title(page, c'')
		}
	}
	if !isnil(self.window) {
		mut window := unsafe { self.window }
		window.sync_selected_tab()
	}
}

// get_tooltip returns the tab tooltip, if any. Mirrors the "tooltip" property.
pub fn (self &Tab) get_tooltip() ?string {
	return self.tooltip
}

// set_tooltip sets the tab tooltip. Mirrors the "tooltip" property setter.
pub fn (mut self Tab) set_tooltip(tooltip ?string) {
	self.tooltip = tooltip
	self.notify_property(g_tab_pspec_tooltip)
	page := self.get_tab_page()
	if !isnil(page) {
		if value := tooltip {
			C.adw_tab_page_set_tooltip(page, &char(value.str))
		} else {
			C.adw_tab_page_set_tooltip(page, c'')
		}
	}
}

// sync_from_active_surface is the direct equivalent of the tab blueprint's
// title and tooltip bindings.
pub fn (mut self Tab) sync_from_active_surface() {
	mut surface := self.get_active_surface() or {
		self.set_title(none)
		self.set_tooltip(none)
		return
	}
	title := self.computed_title(self.config, surface.title, surface.title_override, self.split_tree.get_is_zoomed(), surface.bell_ringing)
	self.set_title(title)
	self.set_tooltip(surface.pwd)
}

// --- Signal handlers ------------------------------------------------------

// prop_split_tree handles the split tree's "notify::tree". Mirrors
// `propSplitTree`: notifies the surface-tree property and, if the tree is now
// empty, requests the tab be closed.
pub fn (mut self Tab) prop_split_tree() {
	self.notify_property(g_tab_pspec_surface_tree)

	// If our tree is empty we close the tab.
	empty := if tree := self.get_surface_tree() {
		tree.is_empty()
	} else {
		true
	}
	if empty {
		if !isnil(self.widget) {
			C.g_signal_emit_by_name(self.widget, c'close-request')
		}
		return
	}
	self.sync_from_active_surface()
}

// prop_active_surface handles the split tree's "notify::active-surface".
// Mirrors `propActiveSurface`.
pub fn (mut self Tab) prop_active_surface() {
	self.notify_property(g_tab_pspec_active_surface)
	self.sync_from_active_surface()
}

// --- Actions --------------------------------------------------------------

// action_ring_bell handles the "tab.ring-bell" action. Mirrors `actionRingBell`:
// marks the page as needing attention only if it isn't the selected page.
pub fn (mut self Tab) action_ring_bell() {
	page := self.get_tab_page()
	if isnil(page) {
		return
	}
	// If already selected, don't mark it as needing attention.
	if C.adw_tab_page_get_selected(page) != 0 {
		return
	}
	C.adw_tab_page_set_needs_attention(page, 1)
}

// action_next_page selects the next tab page. Mirrors `actionNextPage`.
pub fn (mut self Tab) action_next_page() {
	tab_view := self.get_tab_view()
	if isnil(tab_view) {
		return
	}
	C.adw_tab_view_select_next_page(tab_view)
}

// action_previous_page selects the previous tab page. Mirrors
// `actionPreviousPage`.
pub fn (mut self Tab) action_previous_page() {
	tab_view := self.get_tab_view()
	if isnil(tab_view) {
		return
	}
	C.adw_tab_view_select_previous_page(tab_view)
}

// --- Computed title -------------------------------------------------------

// computed_title builds the display title for this tab. Faithful translation of
// `closureComputedTitle`: the tab override takes precedence over the surface
// override, terminal title, configured title, and default.
pub fn (self &Tab) computed_title(config_ &Config, terminal_ ?string, override_ ?string, zoomed bool, bell_ringing bool) string {
	default_title := 'Witty'

	plain := if tab_title := self.title_override {
		tab_title
	} else if o := override_ {
		o
	} else if t := terminal_ {
		t
	} else {
		config_title(config_) or { default_title }
	}
	if isnil(config_) {
		log.warn('config unavailable for computed title, likely bug')
		return plain
	}
	cfg := config_.get()

	// Build the final title with any prefixes.
	mut result := ''

	// Bell prefix.
	if bell_ringing && cfg.bell_features.title() {
		result += '🔔 ' // bell emoji (U+1F514)
	}

	// Zoom prefix.
	if zoomed {
		result += '🔍 ' // magnifying glass emoji (U+1F50D)
	}

	result += plain
	return result
}

// config_title returns the configured static title, if any. Helper for
// computed_title. Mirrors the inner `config_title` block of the closure.
fn config_title(config_ &Config) ?string {
	if isnil(config_) {
		return none
	}
	return config_.get().title
}
