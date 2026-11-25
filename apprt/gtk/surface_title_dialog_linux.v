@[has_globals]
module gtk

// surface_title_dialog_linux.v - Surface title prompt dialog
// (GhosttySurfaceTitleDialog).
//
// Translated from ghostty/src/apprt/gtk/class/surface_title_dialog.zig.
//
// In ghostty this is a GObject class (subclass of `adw.AlertDialog`, NOT the
// base `Dialog`) that prompts the user for a new surface title with a text
// entry. It carries an `initial-value` property, a `set` signal (emitted with
// the new title), and an `entry` template child. Its response is handled
// asynchronously via `adw.AlertDialog.choose` / `chooseFinish`.
//
// The GObject class registration (`defineClass`), the `initial-value` PROPERTY,
// the `.ui` template + `entry` binding, and the `set` SIGNAL are hand-expanded
// below onto the raw GObject/GTK C API. Parent ancestor resolution, entry
// seeding, the asynchronous choose/choose-finish flow, and the "ok" ->
// emit(title) routing are translated directly.

// --- New opaque handle aliases --------------------------------------------
// (Grep-verified: not declared elsewhere in the module.)

// AdwWindow is an AdwWindow* (a window ancestor we prefer to attach to).
pub type AdwWindow = voidptr

// AdwEntryBuffer is a gtk.EntryBuffer* backing the title entry.
pub type GtkEntry = voidptr

// GtkEntryBuffer is a gtk.EntryBuffer*.
pub type GtkEntryBuffer = voidptr

// --- New GTK C bindings ---------------------------------------------------
// Only functions not already declared anywhere else in the module.

fn C.gtk_entry_get_buffer(entry GtkEntry) GtkEntryBuffer

fn C.gtk_entry_buffer_set_text(buffer GtkEntryBuffer, chars &char, n_chars int)

fn C.gtk_entry_buffer_get_text(buffer GtkEntryBuffer) &char

fn C.adw_alert_dialog_choose(dialog AdwAlertDialog, parent GtkWidget, cancellable voidptr, callback GCallback, user_data voidptr)

fn C.adw_alert_dialog_choose_finish(dialog AdwAlertDialog, result GAsyncResult) &char

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhosttySurfaceTitleDialog`, whose parent is `adw.AlertDialog` directly (NOT
// GhosttyDialog): a `.ui` template, an `initial-value` string property, a `set`
// signal (carrying the new title), an `entry` template child, private data, and
// dispose + finalize vfuncs.

// NOTE: G_TYPE_STRING (the GObject fundamental string type, 16 << 2) is the
// `g_type_string` const declared in gsettings_linux.v — reused here for the
// `set` signal's string parameter, NOT redeclared.

// Ghostty's ui/1.5/surface-title-dialog.blp as blueprint-compiler 0.16.0 emits it
// (without the generated-file header). Ghostty compiles it into its
// gresource and loads it with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const surface_title_dialog_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttySurfaceTitleDialog" parent="AdwAlertDialog">
    <property name="heading" translatable="yes">Change Terminal Title</property>
    <property name="body" translatable="yes">Leave blank to restore the default title.</property>
    <responses>
      <response id="cancel" translatable="yes">Cancel</response>
      <response id="ok" translatable="yes" appearance="suggested">OK</response>
    </responses>
    <property name="default-response">ok</property>
    <property name="focus-widget">entry</property>
    <property name="extra-child">
      <object class="GtkEntry" id="entry">
        <property name="activates-default">true</property>
      </object>
    </property>
  </template>
</interface>
'

// The C-layout private struct mirroring ghostty\'s `Private`: the (glib-owned)
// initial value string and the `entry` template child.
struct C.GhosttySurfaceTitleDialogPrivate {
mut:
	initial_value &char = unsafe { nil }
	entry         voidptr
}

// gtk_entry_get_type is needed to bind the `entry` template child.
fn C.gtk_entry_get_type() GType

// g_strdup duplicates a C string into glib-owned memory (freed with g_free).
fn C.g_strdup(str &char) &char

// The GObject type id and private-data offset, registered lazily.
__global g_surface_title_dialog_type = GType(0)
__global g_surface_title_dialog_priv_offset = int(0)

// Property id for the `initial-value` property.
const surface_title_prop_initial_value = u32(1)

fn surface_title_dialog_priv(obj voidptr) &C.GhosttySurfaceTitleDialogPrivate {
	return &C.GhosttySurfaceTitleDialogPrivate(instance_private(obj, g_surface_title_dialog_priv_offset))
}

// surface_title_dialog_get_property implements get_property for `initial-value`.
fn surface_title_dialog_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == surface_title_prop_initial_value {
		priv := surface_title_dialog_priv(obj)
		C.g_value_set_string(value, priv.initial_value)
	}
}

// surface_title_dialog_set_property implements set_property for `initial-value`.
// Mirrors the private-string accessor: free the old and dup the new.
fn surface_title_dialog_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == surface_title_prop_initial_value {
		mut priv := surface_title_dialog_priv(obj)
		if !isnil(priv.initial_value) {
			C.g_free(priv.initial_value)
		}
		priv.initial_value = C.g_strdup(C.g_value_get_string(value))
	}
}

// surface_title_dialog_dispose disposes the template and chains to the parent.
// Mirrors the `dispose` vfunc.
fn surface_title_dialog_dispose(obj voidptr) {
	C.gtk_widget_dispose_template(obj, g_surface_title_dialog_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// surface_title_dialog_finalize frees the owned initial value and chains to the
// parent. Mirrors the `finalize` vfunc.
fn surface_title_dialog_finalize(obj voidptr) {
	mut priv := surface_title_dialog_priv(obj)
	if !isnil(priv.initial_value) {
		C.g_free(priv.initial_value)
		priv.initial_value = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

// surface_title_dialog_class_init installs the template, binds the `entry`
// child, registers the `set` signal, installs the `initial-value` property, and
// overrides the get/set/dispose/finalize vfuncs. Mirrors the ghostty
// `Class.init`.
fn surface_title_dialog_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_surface_title_dialog_priv_offset)
	C.witty_gtk_dialog_canvas_class_init(klass, true)
	bytes := C.g_bytes_new_static(surface_title_dialog_ui.str, uint(surface_title_dialog_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)

	// Signal: set (one [*:0]const u8 / string param, void return).
	mut set_param_type := g_type_string
	C.g_signal_new(c'set', g_surface_title_dialog_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 1, set_param_type)

	// Binding: entry template child into the private struct.
	entry_offset := g_surface_title_dialog_priv_offset + int(__offsetof(C.GhosttySurfaceTitleDialogPrivate, entry))
	C.gtk_widget_class_bind_template_child_full(klass, c'entry', 0, entry_offset)

	// Property: initial-value (string).
	pspec := C.g_param_spec_string(c'initial-value', c'initial-value', c'The initial title', &char(unsafe { nil }), g_param_readwrite)
	C.witty_gobject_class_set_get_property(klass, voidptr(surface_title_dialog_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(surface_title_dialog_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(surface_title_dialog_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(surface_title_dialog_finalize))
	C.g_object_class_install_property(klass, surface_title_prop_initial_value, pspec)
}

fn surface_title_dialog_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
}

// surface_title_dialog_get_type lazily registers the GhosttySurfaceTitleDialog
// GObject type, parented to AdwAlertDialog, with instance-private data.
pub fn surface_title_dialog_get_type() GType {
	if g_surface_title_dialog_type == GType(0) {
		parent := C.adw_alert_dialog_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(surface_title_dialog_class_init)
			instance_init: voidptr(surface_title_dialog_instance_init)
		}
		g_surface_title_dialog_type = C.g_type_register_static(parent, c'GhosttySurfaceTitleDialog', &info, 0)
		g_surface_title_dialog_priv_offset = C.g_type_add_instance_private(g_surface_title_dialog_type, sizeof(C.GhosttySurfaceTitleDialogPrivate))
	}
	return g_surface_title_dialog_type
}

// --- SurfaceTitleDialog ---------------------------------------------------

// SurfaceTitleDialog is the surface-title prompt dialog GObject
// (`GhosttySurfaceTitleDialog`, a subclass of `adw.AlertDialog`). Modeled as a
// struct wrapping the GObject pointer plus the private fields.
@[heap]
pub struct SurfaceTitleDialog {
mut:
	// The underlying AdwAlertDialog GObject instance pointer (an instance of the
	// GhosttySurfaceTitleDialog type registered by `surface_title_dialog_get_type`).
	obj GObject = unsafe { nil }
}

// surface_title_dialog_new creates a new surface title dialog with the same
// construct-time `initial-value` property used by Ghostty.
pub fn surface_title_dialog_new(initial_value ?string) &SurfaceTitleDialog {
	mut obj := GObject(unsafe { nil })
	if value := initial_value {
		obj = GObject(C.g_object_new(surface_title_dialog_get_type(), c'initial-value', &char(value.str), &char(unsafe { nil })))
	} else {
		obj = GObject(C.g_object_new(surface_title_dialog_get_type(), &char(unsafe { nil })))
	}
	return &SurfaceTitleDialog{
		obj: obj
	}
}

// get_initial_value returns the optional `initial-value` property. It is the
// V spelling of `properties.initial-value.get`.
pub fn (self &SurfaceTitleDialog) get_initial_value() ?string {
	if isnil(self.obj) {
		return none
	}
	value := surface_title_dialog_priv(voidptr(self.obj)).initial_value
	if isnil(value) {
		return none
	}
	return unsafe { cstring_to_vstring(value) }
}

// set_initial_value replaces the owned `initial-value` property. It routes
// through GObject just like `properties.initial-value.set`, so normal property
// notification is preserved.
pub fn (mut self SurfaceTitleDialog) set_initial_value(value ?string) {
	if isnil(self.obj) {
		return
	}
	if text := value {
		C.g_object_set(self.obj, c'initial-value', &char(text.str), &char(unsafe { nil }))
	} else {
		C.g_object_set(self.obj, c'initial-value', &char(unsafe { nil }), &char(unsafe { nil }))
	}
}

// present shows the dialog attached to the best available window ancestor and
// seeds the entry with the initial value. Mirrors `SurfaceTitleDialog.present`.
pub fn (mut self SurfaceTitleDialog) present(parent GtkWidget) {
	// If we have a window we can attach to, we prefer that.
	mut attach_to := get_ancestor(parent, C.adw_application_window_get_type())
	if isnil(attach_to) {
		attach_to = get_ancestor(parent, C.adw_window_get_type())
	}
	if isnil(attach_to) {
		attach_to = parent
	}

	// Set our initial value.
	priv := surface_title_dialog_priv(voidptr(self.obj))
	if !isnil(priv.initial_value) && !isnil(priv.entry) {
		buffer := C.gtk_entry_get_buffer(priv.entry)
		C.gtk_entry_buffer_set_text(buffer, priv.initial_value, -1)
	}

	C.adw_alert_dialog_choose(AdwAlertDialog(self.obj), attach_to, unsafe { nil }, GCallback(voidptr(surface_title_dialog_ready_cb)), voidptr(self.obj))
}

// surface_title_dialog_ready_cb completes the asynchronous choice and emits
// `set` with the current entry contents when the response is "ok".
fn surface_title_dialog_ready_cb(source GObject, result GAsyncResult, data voidptr) {
	obj := if !isnil(data) { GObject(data) } else { source }
	if isnil(obj) {
		return
	}
	response_id := C.adw_alert_dialog_choose_finish(AdwAlertDialog(obj), result)
	// If we didn't hit "ok" then we do nothing.
	if isnil(response_id) || unsafe { cstring_to_vstring(response_id) } != 'ok' {
		return
	}

	// Emit our signal with the new title.
	priv := surface_title_dialog_priv(voidptr(obj))
	if isnil(priv.entry) {
		return
	}
	buffer := C.gtk_entry_get_buffer(priv.entry)
	title_ptr := C.gtk_entry_buffer_get_text(buffer)
	C.g_signal_emit_by_name(obj, c'set', title_ptr)
}

// --- GObject reference counting -------------------------------------------
// Mirrors the `Common(Self, Private)` ref helpers.

// ref increments the reference count of the dialog GObject. Mirrors `ref`.
pub fn (mut self SurfaceTitleDialog) ref() &SurfaceTitleDialog {
	if !isnil(self.obj) {
		object_ref(self.obj)
	}
	return self
}

// unref decrements the reference count of the dialog GObject. Mirrors `unref`.
pub fn (mut self SurfaceTitleDialog) unref() {
	if !isnil(self.obj) {
		object_unref(self.obj)
	}
}
