@[has_globals]
module gtk

// config_errors_dialog_linux.v - Config errors dialog
// (GhosttyConfigErrorsDialog).
//
// Translated from ghostty/src/apprt/gtk/class/config_errors_dialog.zig.
//
// In ghostty this is a GObject class (subclass of the base `Dialog`) that shows
// the configuration diagnostics and offers to reload. It holds a `config`
// property (a ref-counted `Config` GObject) and emits a `reload-config` signal
// when the user picks "reload".
//
// The GObject class registration (`defineClass`), the `config` PROPERTY, the
// `.ui` template, and the `reload-config` SIGNAL are hand-expanded below onto
// the raw GObject/GTK C API. The native instance-private property is the sole
// config owner. The real LOGIC — the response-id routing ("reload" -> emit)
// and the config ref/unref ownership (get/set/dispose) — is translated
// directly.
//
// The `config` property is typed as GhosttyConfig, matching the pinned class.

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhosttyConfigErrorsDialog`: a `.ui` template, a `config` object property,
// a `reload-config` signal, private data, and a dispose vfunc.

// Runtime template for ui/1.2/config-errors-dialog.blp.
const config_errors_dialog_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttyConfigErrorsDialog" parent="GhosttyDialog">
    <property name="heading" translatable="yes">Configuration Errors</property>
    <property name="body" translatable="yes">One or more configuration errors were found. Please review the errors below, and either reload your configuration or ignore these errors.</property>
    <responses>
      <response id="ignore" translatable="yes">Ignore</response>
      <response id="reload" translatable="yes" appearance="suggested">Reload Configuration</response>
    </responses>
    <property name="extra-child">
      <object class="GtkScrolledWindow">
        <property name="min-content-width">500</property>
        <property name="min-content-height">100</property>
        <child>
          <object class="GtkTextView" id="diagnostics">
            <property name="editable">false</property>
            <property name="cursor-visible">false</property>
            <property name="top-margin">8</property>
            <property name="bottom-margin">8</property>
            <property name="left-margin">8</property>
            <property name="right-margin">8</property>
            <binding name="buffer">
              <lookup name="diagnostics-buffer" type="GhosttyConfig">
                <lookup name="config" type="GhosttyConfigErrorsDialog">
                  <constant>GhosttyConfigErrorsDialog</constant>
                </lookup>
              </lookup>
            </binding>
          </object>
        </child>
      </object>
    </property>
  </template>
</interface>
'

// The private data holds the wrapped Config and the diagnostics text view.
struct C.GhosttyConfigErrorsDialogPrivate {
mut:
	config      voidptr
	diagnostics voidptr
}

// The GObject type id and private-data offset, registered lazily.
__global g_config_errors_dialog_type = GType(0)
__global g_config_errors_dialog_priv_offset = int(0)

// Property id for the `config` property.
const config_errors_prop_config = u32(1)

fn config_errors_dialog_priv(obj voidptr) &C.GhosttyConfigErrorsDialogPrivate {
	return &C.GhosttyConfigErrorsDialogPrivate(instance_private(obj, g_config_errors_dialog_priv_offset))
}

// config_errors_dialog_get_property implements get_property for `config`.
// Mirrors `getConfig`.
fn config_errors_dialog_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == config_errors_prop_config {
		priv := config_errors_dialog_priv(obj)
		C.g_value_set_object(value, priv.config)
	}
}

// config_errors_dialog_set_property implements set_property for `config`.
// Mirrors `setConfig`: unref the old, take the new (the GValue object
// accessor refs it).
fn config_errors_dialog_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == config_errors_prop_config {
		mut priv := config_errors_dialog_priv(obj)
		if !isnil(priv.config) {
			object_unref(GObject(priv.config))
		}
		newv := C.g_value_get_object(value)
		mut use_canvas := false
		if !isnil(newv) {
			priv.config = voidptr(object_ref(GObject(newv)))
			wrapper := config_priv(newv).wrapper
			if !isnil(wrapper) {
				use_canvas = gtk_canvas_styles_enabled(unsafe { (&Config(wrapper)).get() })
			}
		} else {
			priv.config = unsafe { nil }
		}
		gtk_canvas_overlay_set_mask(GtkWidget(obj), use_canvas)
	}
}

// config_errors_dialog_dispose releases the held config, disposes the template
// and chains to the parent. Mirrors the `dispose` vfunc.
fn config_errors_dialog_dispose(obj voidptr) {
	mut priv := config_errors_dialog_priv(obj)
	C.witty_gtk_dialog_canvas_set_fill_widget(GtkWidget(obj), unsafe { nil })
	if !isnil(priv.config) {
		object_unref(GObject(priv.config))
		priv.config = unsafe { nil }
	}
	C.gtk_widget_dispose_template(obj, g_config_errors_dialog_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// Route the inherited Adwaita response virtual method to Ghostty's
// reload-config signal. Mirrors `ConfigErrorsDialog.response`.
fn config_errors_dialog_native_response_cb(obj GObject, response_id &char) {
	if isnil(obj) || isnil(response_id) {
		return
	}
	if unsafe { cstring_to_vstring(response_id) } == 'reload' {
		C.g_signal_emit_by_name(obj, c'reload-config')
	}
}

// config_errors_dialog_class_init installs the template, the `config` property,
// the `reload-config` signal, and overrides the get/set/dispose vfuncs.
fn config_errors_dialog_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_config_errors_dialog_priv_offset)
	dialog_get_type()
	C.witty_gtk_dialog_canvas_class_init(klass)

	bytes := C.g_bytes_new_static(config_errors_dialog_ui.str, uint(config_errors_dialog_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)
	offset := g_config_errors_dialog_priv_offset +
		int(__offsetof(C.GhosttyConfigErrorsDialogPrivate, diagnostics))
	C.gtk_widget_class_bind_template_child_full(klass, c'diagnostics', 0, offset)

	pspec := C.g_param_spec_object(c'config', c'config', c'The config being shown', config_get_type(), g_param_readwrite)
	C.witty_gobject_class_set_get_property(klass, voidptr(config_errors_dialog_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(config_errors_dialog_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(config_errors_dialog_dispose))
	C.witty_dialog_class_set_response(klass, b2i(supports_dialogs()), voidptr(config_errors_dialog_native_response_cb))
	C.g_object_class_install_property(klass, config_errors_prop_config, pspec)

	C.g_signal_new(c'reload-config', g_config_errors_dialog_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
}

fn config_errors_dialog_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
	priv := config_errors_dialog_priv(instance)
	C.witty_gtk_dialog_canvas_set_fill_widget(GtkWidget(instance), GtkWidget(priv.diagnostics))
}

// config_errors_dialog_get_type lazily registers the GhosttyConfigErrorsDialog
// GObject type, parented to GhosttyDialog, with instance-private data.
pub fn config_errors_dialog_get_type() GType {
	if g_config_errors_dialog_type == GType(0) {
		parent := dialog_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(config_errors_dialog_class_init)
			instance_init: voidptr(config_errors_dialog_instance_init)
		}
		g_config_errors_dialog_type = C.g_type_register_static(parent, c'GhosttyConfigErrorsDialog', &info, 0)
		g_config_errors_dialog_priv_offset = C.g_type_add_instance_private(g_config_errors_dialog_type, sizeof(C.GhosttyConfigErrorsDialogPrivate))
	}
	return g_config_errors_dialog_type
}

// --- ConfigErrorsDialog ---------------------------------------------------

// ConfigErrorsDialog is the config-errors dialog GObject
// (`GhosttyConfigErrorsDialog`, a subclass of `Dialog`). Native private data is
// authoritative; the V value only wraps the object instance.
@[heap]
pub struct ConfigErrorsDialog {
mut:
	dialog Dialog
}

// config_errors_dialog_new creates a new dialog for the given config. Mirrors
// `gobject.ext.newInstance(Self, .{ .config = config })`: it builds the GObject
// (running the `.ui` template init) with the `config` property set (the setter
// takes a reference).
pub fn config_errors_dialog_new(config &Config) &ConfigErrorsDialog {
	mut config_obj := GObject(unsafe { nil })
	if !isnil(config) {
		config_obj = config.obj
	}
	obj := C.g_object_new(config_errors_dialog_get_type(), c'config', config_obj, &char(unsafe { nil }))
	return &ConfigErrorsDialog{
		dialog: Dialog{
			obj: obj
		}
	}
}

// config_errors_dialog_from_object performs the typed half of Ghostty's
// WeakRef(ConfigErrorsDialog).get. The transient wrapper borrows the caller's
// strong native-object reference.
fn config_errors_dialog_from_object(obj GObject) ?&ConfigErrorsDialog {
	if isnil(obj)
		|| C.g_type_check_instance_is_a(obj, config_errors_dialog_get_type()) == 0 {
		return none
	}
	return &ConfigErrorsDialog{
		dialog: Dialog{
			obj: obj
		}
	}
}

// present shows the dialog. Mirrors `ConfigErrorsDialog.present`.
pub fn (mut self ConfigErrorsDialog) present(parent ?GtkWidget) {
	self.dialog.present(parent)
}

// close closes the dialog. Mirrors `ConfigErrorsDialog.close`.
pub fn (mut self ConfigErrorsDialog) close() {
	self.dialog.close()
}

// get_config returns the held config (without taking a reference). Mirrors
// `getConfig` (the `config` property getter).
pub fn (self &ConfigErrorsDialog) get_config() ?&Config {
	config_obj := config_errors_dialog_priv(voidptr(self.dialog.obj)).config
	if isnil(config_obj) {
		return none
	}
	wrapper := config_priv(config_obj).wrapper
	if isnil(wrapper) {
		return none
	}
	return unsafe { &Config(wrapper) }
}

// set_config updates the registered object property. Its native setter owns
// the reference exactly once, matching Ghostty's typed GValue accessor.
fn (mut self ConfigErrorsDialog) set_config(config ?&Config) {
	if !isnil(self.dialog.obj) {
		value := config or {
			C.g_object_set(self.dialog.obj, c'config', GObject(unsafe { nil }), unsafe { nil })
			return
		}
		config_obj := value.obj
		C.g_object_set(self.dialog.obj, c'config', config_obj, unsafe { nil })
	}
}

// --- GObject reference counting -------------------------------------------
// Mirrors the `Common(Self, Private)` ref helpers.

// ref increments the reference count of the dialog GObject. Mirrors `ref`.
pub fn (mut self ConfigErrorsDialog) ref() &ConfigErrorsDialog {
	self.dialog.ref()
	return self
}

// unref decrements the reference count of the dialog GObject. Mirrors `unref`.
pub fn (mut self ConfigErrorsDialog) unref() {
	self.dialog.unref()
}
