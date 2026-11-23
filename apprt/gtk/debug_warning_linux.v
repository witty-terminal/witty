@[has_globals]
module gtk

// debug_warning_linux.v - Debug warning banner (GhosttyDebugWarning).
//
// Translated from ghostty/src/apprt/gtk/class/debug_warning.zig, with the
// GObject class registration (ghostty's `gobject.ext.defineClass`) and the
// blueprint template hand-expanded into the raw GObject/GTK C API.
//
// The parent is AdwBin (wrapping an AdwBanner) when libadwaita supports
// banners (1.3+), otherwise GtkBox (wrapping a GtkLabel), chosen at runtime.

// AdwBin is an AdwBin* (banner container, libadwaita >= 1.3).
pub type AdwBin = voidptr

// The GObject type id, registered lazily on first use (mirrors what
// defineClass's generated getGObjectType does).
__global g_debug_warning_type = GType(0)

// Ghostty's ui/1.3/debug-warning.blp (with the AdwBanner) and
// ui/1.2/debug-warning.blp, as blueprint-compiler 0.16.0 emits them
// (without the generated-file header). Ghostty compiles these into its
// gresource and loads one with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const debug_warning_ui_banner = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttyDebugWarning" parent="AdwBin">
    <child>
      <object class="AdwBanner">
        <property name="title" translatable="yes">⚠️ You\'re running a debug build of Witty! Performance will be degraded.</property>
        <property name="revealed">true</property>
      </object>
    </child>
  </template>
</interface>
'

const debug_warning_ui_label = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttyDebugWarning" parent="GtkBox">
    <property name="orientation">1</property>
    <child>
      <object class="GtkLabel">
        <property name="label" translatable="yes">⚠️ You\'re running a debug build of Witty! Performance will be degraded.</property>
        <property name="margin-top">10</property>
        <property name="margin-bottom">10</property>
      </object>
    </child>
  </template>
</interface>
'

// classInit installs the blueprint template on the widget class. Mirrors the
// Zig `Class.init` which calls setTemplateFromResource.
fn debug_warning_class_init(klass voidptr, class_data voidptr) {
	ui := if supports_banner() { debug_warning_ui_banner } else { debug_warning_ui_label }
	bytes := C.g_bytes_new_static(ui.str, uint(ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)
}

// instanceInit builds the widget tree from the template. Mirrors the Zig
// `init` which calls gtk.Widget.initTemplate.
fn debug_warning_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
}

// debug_warning_get_type lazily registers the GhosttyDebugWarning GObject
// type. This is the hand-expansion of `gobject.ext.defineClass`: query the
// parent for its class/instance sizes and register a static type whose
// class_init/instance_init are our functions above.
pub fn debug_warning_get_type() GType {
	if g_debug_warning_type == GType(0) {
		parent := if supports_banner() { C.adw_bin_get_type() } else { C.gtk_box_get_type() }
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(debug_warning_class_init)
			instance_init: voidptr(debug_warning_instance_init)
		}
		g_debug_warning_type = C.g_type_register_static(parent, c'GhosttyDebugWarning',
			&info, 0)
	}
	return g_debug_warning_type
}

// DebugWarning is the debug-build warning banner GObject
// (`GhosttyDebugWarning`). Modeled as a struct wrapping the GObject pointer.
@[heap]
pub struct DebugWarning {
mut:
	// The underlying AdwBin/GtkBox GObject instance pointer.
	obj GObject = unsafe { nil }
}

// debug_warning_new creates a new DebugWarning banner. Mirrors ghostty's
// `gobject.ext.newInstance(Self, .{})`.
pub fn debug_warning_new() &DebugWarning {
	obj := C.g_object_new(debug_warning_get_type(), &char(unsafe { nil }))
	return &DebugWarning{
		obj: obj
	}
}

// ref increments the reference count of the DebugWarning GObject.
pub fn (mut self DebugWarning) ref() &DebugWarning {
	if !isnil(self.obj) {
		object_ref(self.obj)
	}
	return self
}

// unref decrements the reference count of the DebugWarning GObject.
pub fn (mut self DebugWarning) unref() {
	if !isnil(self.obj) {
		object_unref(self.obj)
	}
}
