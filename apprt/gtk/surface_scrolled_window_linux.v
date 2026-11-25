@[has_globals]
module gtk

// surface_scrolled_window_linux.v - The GObject SurfaceScrolledWindow widget
// class for the GTK apprt.
//
// Translated from ghostty/src/apprt/gtk/class/surface_scrolled_window.zig.
//
// A wrapper widget that embeds a Surface inside a GtkScrolledWindow to provide
// scrollbar functionality for the terminal surface. The embedded surface can be
// set during initialization or changed dynamically via the `surface` property.
// It also carries a `config` property (bound from the surface) that drives the
// scrollbar policy.
//
// The GObject class registration (ghostty's `gobject.ext.defineClass`), the
// blueprint template with its scrollbar_policy/notify_surface callbacks, and
// the `config` / `surface` object properties are hand-expanded onto the raw
// GObject/GTK C API below (there are no signals). The class is additionally
// modeled as a stable V wrapper around the native instance.
//
// Reuses: `Config` (config_class_linux.v), `SurfaceWidget`
// (surface_class_linux.v — the GObject `Surface` in Zig), `GtkWidget`
// (c_gtk_linux.v). GtkWidget parent helpers are declared in
// search_overlay_linux.v.
import configpkg as _

// --- New C bindings unique to this file -----------------------------------

// GtkScrolledWindow*.
pub type GtkScrolledWindow = voidptr

fn C.gtk_scrolled_window_set_child(sw GtkScrolledWindow, child GtkWidget)

fn C.gtk_scrolled_window_get_type() GType

const g_binding_sync_create = int(1 << 1)

// --- PolicyType -----------------------------------------------------------

// PolicyType mirrors gtk.PolicyType (the scrollbar display policy).
pub enum PolicyType as i32 {
	always
	automatic
	never
	external
}

// --- SurfaceScrolledWindow ------------------------------------------------

// SurfaceScrolledWindow is the V model of the `GhostttySurfaceScrolledWindow`
// GObject class. Fields mirror the Zig `Private` struct.
@[heap]
pub struct SurfaceScrolledWindow {

	// The GtkWidget (adw.Bin) pointer for this instance.
pub mut:
	widget GtkWidget = unsafe { nil }

	// The configuration this widget uses. nil means "unset".
	config &Config = unsafe { nil }

	// Binding from the embedded Surface's config property to ours.
	config_binding GObject = unsafe { nil }

	// The embedded surface widget. nil means "unset".
	surface &SurfaceWidget = unsafe { nil }
}

// new_surface_scrolled_window creates a new SurfaceScrolledWindow. Mirrors
// `gobject.ext.newInstance` + the instance `init` (which just runs the
// template).
pub fn new_surface_scrolled_window() &SurfaceScrolledWindow {
	obj := C.g_object_new(surface_scrolled_window_get_type(), &char(unsafe { nil }))
	mut self := &SurfaceScrolledWindow{
		widget: obj
	}
	mut priv := surface_scrolled_window_priv(obj)
	priv.wrapper = voidptr(self)
	return self
}

pub fn (mut self SurfaceScrolledWindow) ref() &SurfaceScrolledWindow {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

pub fn (mut self SurfaceScrolledWindow) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

// get_surface returns the embedded surface widget. Mirrors `getSurface`.
pub fn (self &SurfaceScrolledWindow) get_surface() ?&SurfaceWidget {
	if isnil(self.surface) {
		return none
	}
	return self.surface
}

// set_surface sets the embedded surface widget and re-parents it into the
// scrolled window, rebinding the config. Mirrors `setSurface` + `propSurface`.
pub fn (mut self SurfaceScrolledWindow) set_surface(surface_ ?&SurfaceWidget) {
	surface := surface_ or { unsafe { nil } }
	if surface == self.surface {
		return
	}

	// The notification is queued while frozen and delivered after the field is
	// replaced, matching Ghostty's setSurface ordering.
	if !isnil(self.widget) {
		C.g_object_freeze_notify(self.widget)
		C.g_object_notify_by_pspec(self.widget, g_surface_scrolled_window_pspec_surface)
	}
	self.surface = surface
	if !isnil(self.widget) {
		C.g_object_thaw_notify(self.widget)
	}
}

// set_config_reference is the object-field accessor for the native config
// property. The binding created by prop_surface drives this setter.
fn (mut self SurfaceScrolledWindow) set_config_reference(config_ ?&Config) {
	config := config_ or { unsafe { nil } }
	if self.config == config {
		return
	}
	if !isnil(self.config) {
		self.config.unref()
		self.config = unsafe { nil }
	}
	if isnil(config) {
		return
	}
	self.config = ssw_config_ref(config)
}

// ssw_config_ref is a non-mut wrapper around `Config.ref()` (see the note on
// the analogous helper in command_palette_linux.v).
fn ssw_config_ref(config &Config) &Config {
	mut c := config
	return c.ref()
}

// scrollbar_policy maps the config's scrollbar setting to a GtkPolicyType.
// Mirrors `closureScrollbarPolicy`.
pub fn (self &SurfaceScrolledWindow) scrollbar_policy() PolicyType {
	if isnil(self.config) {
		return .automatic
	}
	cfg := self.config.get()
	return match cfg.scrollbar {
		.never { PolicyType.never }
		.system { PolicyType.automatic }
	}
}

// prop_surface reparents the selected Surface and replaces the config binding.
// Mirrors `propSurface`, including SYNC_CREATE so scrollbar policy is correct
// immediately after a surface is installed.
fn (mut self SurfaceScrolledWindow) prop_surface() {
	if isnil(self.widget) {
		return
	}
	scrolled_window := C.adw_bin_get_child(self.widget)
	assert !isnil(scrolled_window)
	assert C.g_type_check_instance_is_a(scrolled_window, C.gtk_scrolled_window_get_type()) != 0
	child := if isnil(self.surface) {
		GtkWidget(unsafe { nil })
	} else {
		self.surface.as_widget()
	}
	C.gtk_scrolled_window_set_child(scrolled_window, child)

	if !isnil(self.config_binding) {
		object_unref(self.config_binding)
		self.config_binding = unsafe { nil }
	}
	if !isnil(self.surface) && !isnil(self.surface.widget) {
		self.config_binding = GObject(C.g_object_bind_property(self.surface.widget, c'config', self.widget, c'config', g_binding_sync_create))
	}
}

// dispose releases the binding and config reference. The native dispose vfunc
// calls this cleanup before disposing the template and chaining to AdwBin.
pub fn (mut self SurfaceScrolledWindow) dispose() {
	if !isnil(self.config_binding) {
		object_unref(self.config_binding)
		self.config_binding = unsafe { nil }
	}
	if !isnil(self.config) {
		self.config.unref()
		self.config = unsafe { nil }
	}
}

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhostttySurfaceScrolledWindow` (note ghostty's triple-t typo in the type
// name, kept for parity; parent adw.Bin): a `.ui` template with
// scrollbar_policy/notify_surface callbacks, the `config` / `surface`
// properties, and dispose/finalize vfuncs. There are no signals.

// --- New C bindings unique to this file (registration) --------------------

// adw_bin_get_child returns the single child of an AdwBin (the ScrolledWindow).
fn C.adw_bin_get_child(bin GtkWidget) GtkWidget

// g_object_freeze_notify / g_object_thaw_notify batch property-change notifs.
fn C.g_object_freeze_notify(object voidptr)

fn C.g_object_thaw_notify(object voidptr)

// gtk_policy_type_get_type is the registered GType of gtk.PolicyType, used as
// the scrollbar_policy closure's return type.
fn C.gtk_policy_type_get_type() GType

// Ghostty's ui/1.5/surface-scrolled-window.blp as blueprint-compiler 0.16.0 emits it
// (without the generated-file header). Ghostty compiles it into its
// gresource and loads it with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const surface_scrolled_window_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhostttySurfaceScrolledWindow" parent="AdwBin">
    <signal name="notify::surface" handler="notify_surface"/>
    <child>
      <object class="GtkScrolledWindow">
        <property name="hscrollbar-policy">2</property>
        <binding name="vscrollbar-policy">
          <closure function="scrollbar_policy" type="GtkPolicyType">
            <lookup name="config" type="GhostttySurfaceScrolledWindow">
              <constant>GhostttySurfaceScrolledWindow</constant>
            </lookup>
          </closure>
        </binding>
      </object>
    </child>
  </template>
</interface>
'

// The native private storage points at the stable V wrapper that carries the
// translated Zig private fields.
struct C.GhostttySurfaceScrolledWindowPrivate {
mut:
	wrapper voidptr
}

// The GObject type id and private-data offset, registered lazily.
__global g_surface_scrolled_window_type = GType(0)
__global g_surface_scrolled_window_priv_offset = int(0)

// Registered GParamSpec* pointers, captured for notify.
__global g_surface_scrolled_window_pspec_config = &C.GParamSpec(unsafe { nil })
__global g_surface_scrolled_window_pspec_surface = &C.GParamSpec(unsafe { nil })

// Property ids for the get/set vfunc dispatch.
const surface_scrolled_window_prop_config = u32(1)
const surface_scrolled_window_prop_surface = u32(2)

fn surface_scrolled_window_priv(obj voidptr) &C.GhostttySurfaceScrolledWindowPrivate {
	return &C.GhostttySurfaceScrolledWindowPrivate(instance_private(obj, g_surface_scrolled_window_priv_offset))
}

// surface_scrolled_window_get_property implements get_property for config/surface.
fn surface_scrolled_window_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := surface_scrolled_window_priv(obj)
	if isnil(priv.wrapper) {
		C.g_value_set_object(value, unsafe { nil })
		return
	}
	self := unsafe { &SurfaceScrolledWindow(priv.wrapper) }
	match property_id {
		surface_scrolled_window_prop_config {
			C.g_value_set_object(value, if isnil(self.config) {
				unsafe { nil }
			} else {
				self.config.obj
			})
		}
		surface_scrolled_window_prop_surface {
			C.g_value_set_object(value, if isnil(self.surface) {
				unsafe { nil }
			} else {
				self.surface.widget
			})
		}
		else {}
	}
}

// surface_scrolled_window_set_property implements set_property for config/surface.
fn surface_scrolled_window_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := surface_scrolled_window_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &SurfaceScrolledWindow(priv.wrapper) }
	match property_id {
		surface_scrolled_window_prop_config {
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
		surface_scrolled_window_prop_surface {
			surface_obj := C.g_value_get_object(value)
			if isnil(surface_obj) {
				self.set_surface(none)
			} else {
				surface_private := terminal_surface_priv(surface_obj)
				// V 0.5.2 miscompiles `if` expressions yielding ?&T arguments.
				if isnil(surface_private.wrapper) {
					self.set_surface(none)
				} else {
					self.set_surface(unsafe { &SurfaceWidget(surface_private.wrapper) })
				}
			}
		}
		else {}
	}
}

// surface_scrolled_window_scrollbar_policy_cb maps the config's scrollbar
// setting to a GtkPolicyType. Mirrors `closureScrollbarPolicy`. `config_` is
// the opaque `config` property value; here the wrapper drives the policy so
// this returns .automatic when unset.
fn surface_scrolled_window_scrollbar_policy_cb(instance voidptr, config_ voidptr) int {
	_ = instance
	if isnil(config_) {
		return int(PolicyType.automatic)
	}
	priv := config_priv(config_)
	if isnil(priv.wrapper) {
		return int(PolicyType.automatic)
	}
	cfg := unsafe { &Config(priv.wrapper) }.get()
	return match cfg.scrollbar {
		.never { int(PolicyType.never) }
		.system { int(PolicyType.automatic) }
	}
}

// surface_scrolled_window_notify_surface_cb is the `notify::surface` callback
// (propSurface).
fn surface_scrolled_window_notify_surface_cb(obj voidptr, pspec voidptr, instance voidptr) {
	_ = pspec
	_ = instance
	priv := surface_scrolled_window_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &SurfaceScrolledWindow(priv.wrapper) }
		self.prop_surface()
	}
}

// surface_scrolled_window_dispose disposes the template and chains up. Mirrors
// `dispose`.
fn surface_scrolled_window_dispose(obj voidptr) {
	priv := surface_scrolled_window_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &SurfaceScrolledWindow(priv.wrapper) }
		self.dispose()
	}
	C.gtk_widget_dispose_template(obj, g_surface_scrolled_window_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// surface_scrolled_window_finalize chains up. Mirrors `finalize`.
fn surface_scrolled_window_finalize(obj voidptr) {
	mut priv := surface_scrolled_window_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &SurfaceScrolledWindow(priv.wrapper) }
		self.widget = unsafe { nil }
		self.surface = unsafe { nil }
		priv.wrapper = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

// surface_scrolled_window_class_init installs the template, wires the
// scrollbar_policy/notify_surface callbacks, registers the config/surface
// properties, and overrides the get/set/dispose/finalize vfuncs. Mirrors the
// ghostty `Class.init`.
fn surface_scrolled_window_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_surface_scrolled_window_priv_offset)
	bytes := C.g_bytes_new_static(surface_scrolled_window_ui.str, uint(surface_scrolled_window_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)

	// Template callbacks.
	C.gtk_widget_class_bind_template_callback_full(klass, c'scrollbar_policy', voidptr(surface_scrolled_window_scrollbar_policy_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'notify_surface', voidptr(surface_scrolled_window_notify_surface_cb))

	// Object properties.
	g_surface_scrolled_window_pspec_config = C.g_param_spec_object(c'config', c'config', c'The configuration', config_get_type(), g_param_readwrite)
	g_surface_scrolled_window_pspec_surface = C.g_param_spec_object(c'surface', c'surface', c'The embedded surface', terminal_surface_get_type(), g_param_readwrite)
	C.witty_gobject_class_set_get_property(klass, voidptr(surface_scrolled_window_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(surface_scrolled_window_set_property))
	C.witty_gtk_scrollbar_canvas_class_init(klass)
	C.witty_gobject_class_set_dispose(klass, voidptr(surface_scrolled_window_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(surface_scrolled_window_finalize))
	C.g_object_class_install_property(klass, surface_scrolled_window_prop_config, g_surface_scrolled_window_pspec_config)
	C.g_object_class_install_property(klass, surface_scrolled_window_prop_surface, g_surface_scrolled_window_pspec_surface)
}

fn surface_scrolled_window_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
	gtk_canvas_overlay_set_mask(GtkWidget(instance), true)
}

// surface_scrolled_window_get_type lazily registers the
// GhostttySurfaceScrolledWindow GObject type, parented to AdwBin, with
// instance-private data.
pub fn surface_scrolled_window_get_type() GType {
	if g_surface_scrolled_window_type == GType(0) {
		parent := C.adw_bin_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(surface_scrolled_window_class_init)
			instance_init: voidptr(surface_scrolled_window_instance_init)
		}
		g_surface_scrolled_window_type = C.g_type_register_static(parent, c'GhostttySurfaceScrolledWindow', &info, 0)
		g_surface_scrolled_window_priv_offset = C.g_type_add_instance_private(g_surface_scrolled_window_type, sizeof(C.GhostttySurfaceScrolledWindowPrivate))
	}
	return g_surface_scrolled_window_type
}
