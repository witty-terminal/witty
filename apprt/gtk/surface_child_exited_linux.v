@[has_globals]
module gtk

// surface_child_exited_linux.v - The GObject SurfaceChildExited widget class
// for the GTK apprt.
//
// Translated from ghostty/src/apprt/gtk/class/surface_child_exited.zig.
//
// A banner overlay shown when the terminal's child process exits, reporting
// whether the command succeeded (exit code 0) or failed. In ghostty this is an
// `adw.Banner` subclass (Adwaita >= 1.3) with a no-op fallback for older
// Adwaita. It carries the `apprt.surface.Message.ChildExited` data and formats
// a banner title + CSS class ("normal"/"abnormal") from the exit code, plus a
// `close-request` signal emitted when the banner's close button is clicked.
//
// The GObject class registration (ghostty's `gobject.ext.defineClass`), the
// blueprint template with its `banner` child + notify_data/clicked callbacks,
// the `data` property, the `close-request` signal, and dispose/finalize are
// hand-expanded onto the raw GObject/GTK C API below, including the pre-1.3
// no-op variant. The real logic (storing the ChildExited data, deriving the
// banner title + css-class from the exit code) is translated. The class is
// additionally modeled as a V owner wrapping the GObject/GtkWidget pointer for
// callers.
//
// Reuses: `apprt.ChildExited` (apprt/surface.v), `gtk_widget_add_css_class` /
// `gtk_widget_remove_css_class` (surface_class_linux.v). The adw.Banner title
// setter is declared here (unique to this file).
import apprt

// --- New C bindings unique to this file -----------------------------------

// AdwBanner*.
pub type AdwBanner = voidptr

fn C.adw_banner_set_title(banner AdwBanner, title &char)

// adw_banner_get_type binds the `banner` template child.
fn C.adw_banner_get_type() GType

fn C.g_malloc0(n_bytes uint) voidptr

struct C.GhosttyApprtChildExited {
mut:
	exit_code  u32
	runtime_ms u64
}

// --- SurfaceChildExited ---------------------------------------------------

// SurfaceChildExited is the V model of the `GhosttySurfaceChildExited` GObject
// class. Fields mirror the Zig `Private` struct. The Zig
// `?*apprt.surface.Message.ChildExited` is modeled with a value + presence
// flag (V has no `?struct` field ergonomics matching a boxed pointer here).
@[heap]
pub struct SurfaceChildExited {

	// The GtkWidget (adw.Bin) pointer for this instance.
pub mut:
	widget GtkWidget = unsafe { nil }

	// The banner widget (template child).
	banner AdwBanner = unsafe { nil }
}

// new_surface_child_exited creates a new SurfaceChildExited. Mirrors
// `gobject.ext.newInstance` + the instance `init`: it builds the GObject
// (running the `.ui` template init, which binds the `banner` child) and reads
// the template child back into the wrapper.
pub fn new_surface_child_exited() &SurfaceChildExited {
	obj := C.g_object_new(surface_child_exited_get_type(), &char(unsafe { nil }))
	priv := surface_child_exited_priv(obj)
	return &SurfaceChildExited{
		widget: obj
		banner: priv.banner
	}
}

pub fn (mut self SurfaceChildExited) ref() &SurfaceChildExited {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

pub fn (mut self SurfaceChildExited) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

// set_data stores a copy of the child-exited data (or clears it) and refreshes
// the banner. Mirrors `setData` (which copies into a glib-allocated boxed value
// and notifies the `data` property, whose notify handler runs `propData`).
pub fn (mut self SurfaceChildExited) set_data(data ?apprt.ChildExited) {
	if isnil(self.widget) {
		return
	}
	if !supports_banner() {
		C.g_signal_emit_by_name(self.widget, c'close-request')
		return
	}
	mut priv := surface_child_exited_priv(self.widget)
	if !isnil(priv.data) {
		child_exited_boxed_free(priv.data)
		priv.data = unsafe { nil }
	}
	d := data or { return }
	priv.data = child_exited_boxed_copy(voidptr(&d))
	C.g_object_notify_by_pspec(self.widget, g_surface_child_exited_pspec_data)
}

// child_exited_apply_data updates the banner title and CSS classes from the
// native private data. Mirrors `propData`.
fn child_exited_apply_data(obj voidptr) {
	priv := surface_child_exited_priv(obj)
	if isnil(priv.data) {
		// Not localized on purpose (matches the Zig original).
		C.adw_banner_set_title(priv.banner, c'This is a bug in Witty. Please report it.')
		return
	}
	data := unsafe { &C.GhosttyApprtChildExited(priv.data) }

	if data.exit_code == 0 {
		title := i18n_('Command succeeded')
		C.adw_banner_set_title(priv.banner, &char(title.str))
		C.gtk_widget_add_css_class(obj, c'normal')
		C.gtk_widget_remove_css_class(obj, c'abnormal')
	} else {
		title := i18n_('Command failed')
		C.adw_banner_set_title(priv.banner, &char(title.str))
		C.gtk_widget_remove_css_class(obj, c'normal')
		C.gtk_widget_add_css_class(obj, c'abnormal')
	}
}

// close_button_clicked is the banner "button-clicked" template callback. It
// requests the banner be closed. Mirrors `closeButtonClicked`.
pub fn (self &SurfaceChildExited) close_button_clicked() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'close-request')
	}
}

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for the Adwaita >= 1.3
// banner variant `GhosttySurfaceChildExited` (parent adw.Bin): a `.ui` template
// with a bound `banner` child + notify_data/clicked callbacks, the `data`
// property, the `close-request` signal, and dispose/finalize vfuncs. The
// pre-1.3 variant registers only `close-request`; `set_data` immediately emits
// it so libwitty falls back to its text exit message.

// Ghostty's ui/1.3/surface-child-exited.blp as blueprint-compiler 0.16.0 emits it
// (without the generated-file header). Ghostty compiles it into its
// gresource and loads it with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const surface_child_exited_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttySurfaceChildExited" parent="AdwBin">
    <style>
      <class name="child-exited"/>
    </style>
    <signal name="notify::data" handler="notify_data"/>
    <child>
      <object class="AdwBin">
        <child>
          <object class="AdwBanner" id="banner">
            <signal name="button-clicked" handler="clicked"/>
            <property name="revealed">true</property>
            <property name="title">This is a bug in Witty. Please report it.</property>
            <property name="button-label" translatable="yes">Close</property>
            <property name="halign">0</property>
            <property name="valign">2</property>
          </object>
        </child>
      </object>
    </child>
  </template>
</interface>
'

// The C-layout private struct mirroring ghostty\'s `Private`: the boxed
// child-exited data pointer and the `banner` template child. The data is served
// as an opaque pointer property (its boxed GType is not registered in witty; the
// real ChildExited copy is held by the V wrapper).
struct C.GhosttySurfaceChildExitedPrivate {
mut:
	data   voidptr
	banner voidptr
}

// The GObject type id and private-data offset, registered lazily.
__global g_surface_child_exited_type = GType(0)
__global g_surface_child_exited_priv_offset = int(0)
__global g_child_exited_boxed_type = GType(0)

// Registered GParamSpec* for the `data` property, captured for notify.
__global g_surface_child_exited_pspec_data = &C.GParamSpec(unsafe { nil })

// Property id for the get/set vfunc dispatch.
const surface_child_exited_prop_data = u32(1)

fn surface_child_exited_priv(obj voidptr) &C.GhosttySurfaceChildExitedPrivate {
	return &C.GhosttySurfaceChildExitedPrivate(instance_private(obj, g_surface_child_exited_priv_offset))
}

fn child_exited_boxed_copy(value voidptr) voidptr {
	if isnil(value) {
		return unsafe { nil }
	}
	data := unsafe { &C.GhosttyApprtChildExited(value) }
	ptr := C.g_malloc0(sizeof(C.GhosttyApprtChildExited))
	if isnil(ptr) {
		return unsafe { nil }
	}
	mut copy := unsafe { &C.GhosttyApprtChildExited(ptr) }
	copy.exit_code = data.exit_code
	copy.runtime_ms = data.runtime_ms
	return ptr
}

fn child_exited_boxed_free(value voidptr) {
	if !isnil(value) {
		C.g_free(value)
	}
}

fn child_exited_boxed_get_type() GType {
	if g_child_exited_boxed_type == GType(0) {
		g_child_exited_boxed_type = C.g_boxed_type_register_static(c'GhosttyApprtChildExited', voidptr(child_exited_boxed_copy), voidptr(child_exited_boxed_free))
	}
	return g_child_exited_boxed_type
}

// surface_child_exited_get_property implements get_property for `data`.
fn surface_child_exited_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == surface_child_exited_prop_data {
		priv := surface_child_exited_priv(obj)
		C.g_value_set_boxed(value, priv.data)
	}
}

// surface_child_exited_set_property implements set_property for `data`.
fn surface_child_exited_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == surface_child_exited_prop_data {
		mut priv := surface_child_exited_priv(obj)
		if !isnil(priv.data) {
			child_exited_boxed_free(priv.data)
		}
		priv.data = C.g_value_dup_boxed(value)
	}
}

// surface_child_exited_notify_data_cb is the `notify::data` template callback
// (`propData`). It drives the banner from the same native private state exposed
// by the boxed property.
fn surface_child_exited_notify_data_cb(obj voidptr, pspec voidptr, instance voidptr) {
	_ = obj
	_ = pspec
	if !isnil(instance) {
		child_exited_apply_data(instance)
	}
}

// surface_child_exited_clicked_cb is the banner "button-clicked" callback. It
// emits the `close-request` signal on the overlay instance. Mirrors
// `closeButtonClicked`.
fn surface_child_exited_clicked_cb(banner voidptr, instance voidptr) {
	if !isnil(instance) {
		C.g_signal_emit_by_name(instance, c'close-request')
	}
}

// surface_child_exited_dispose disposes the template and chains up. Mirrors
// `dispose`.
fn surface_child_exited_dispose(obj voidptr) {
	if supports_banner() {
		C.gtk_widget_dispose_template(obj, g_surface_child_exited_type)
	}
	C.witty_gobject_call_parent_dispose(obj)
}

// surface_child_exited_finalize releases the private boxed data and chains up.
// Mirrors `finalize`.
fn surface_child_exited_finalize(obj voidptr) {
	mut priv := surface_child_exited_priv(obj)
	if !isnil(priv.data) {
		child_exited_boxed_free(priv.data)
		priv.data = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

// surface_child_exited_class_init installs the template, binds the `banner`
// child, wires the notify_data/clicked callbacks, registers the `data` property
// and `close-request` signal, and overrides the get/set/dispose/finalize
// vfuncs. Mirrors the ghostty `Class.init`.
fn surface_child_exited_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_surface_child_exited_priv_offset)
	C.witty_gobject_class_set_dispose(klass, voidptr(surface_child_exited_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(surface_child_exited_finalize))

	if supports_banner() {
		bytes := C.g_bytes_new_static(surface_child_exited_ui.str, uint(surface_child_exited_ui.len))
		C.gtk_widget_class_set_template(klass, bytes)
		C.g_bytes_unref(bytes)

		// Binding: banner template child into the private struct.
		banner_offset := g_surface_child_exited_priv_offset + int(__offsetof(C.GhosttySurfaceChildExitedPrivate, banner))
		C.gtk_widget_class_bind_template_child_full(klass, c'banner', 0, banner_offset)

		// Template callbacks.
		C.gtk_widget_class_bind_template_callback_full(klass, c'clicked', voidptr(surface_child_exited_clicked_cb))
		C.gtk_widget_class_bind_template_callback_full(klass, c'notify_data', voidptr(surface_child_exited_notify_data_cb))

		// Property: data (the GhosttyApprtChildExited boxed type).
		g_surface_child_exited_pspec_data = C.g_param_spec_boxed(c'data', c'data', c'The child-exited data', child_exited_boxed_get_type(), g_param_readwrite)
		C.witty_gobject_class_set_get_property(klass, voidptr(surface_child_exited_get_property))
		C.witty_gobject_class_set_set_property(klass, voidptr(surface_child_exited_set_property))
		C.g_object_class_install_property(klass, surface_child_exited_prop_data, g_surface_child_exited_pspec_data)
	}

	// Signal: close-request (void).
	C.g_signal_new(c'close-request', g_surface_child_exited_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
}

fn surface_child_exited_instance_init(instance voidptr, klass voidptr) {
	if supports_banner() {
		C.gtk_widget_init_template(instance)
	}
}

// surface_child_exited_get_type lazily registers the GhosttySurfaceChildExited
// GObject type, parented to AdwBin, with instance-private data.
pub fn surface_child_exited_get_type() GType {
	if g_surface_child_exited_type == GType(0) {
		parent := if supports_banner() { C.adw_bin_get_type() } else { C.gtk_widget_get_type() }
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(surface_child_exited_class_init)
			instance_init: voidptr(surface_child_exited_instance_init)
		}
		g_surface_child_exited_type = C.g_type_register_static(parent, c'GhosttySurfaceChildExited', &info, 0)
		g_surface_child_exited_priv_offset = C.g_type_add_instance_private(g_surface_child_exited_type, sizeof(C.GhosttySurfaceChildExitedPrivate))
	}
	return g_surface_child_exited_type
}
