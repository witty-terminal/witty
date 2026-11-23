@[has_globals]
module gtk

// close_confirmation_dialog_linux.v - Close confirmation dialog
// (GhosttyCloseConfirmationDialog).
//
// Translated from ghostty/src/apprt/gtk/class/close_confirmation_dialog.zig.
//
// In ghostty this is a GObject class (subclass of the base `Dialog`) that asks
// the user to confirm closing the app / a window / a tab / a split. It carries
// a `target` property, emits `close-request` / `cancel` signals, and derives
// its heading/body from the target.
//
// The GObject class registration (`defineClass`), the `target` PROPERTY, the
// `.ui` template, and the `close-request`/`cancel` SIGNALS are hand-expanded
// below onto the raw GObject/GTK C API. The target -> heading/body text and
// response virtual method are translated directly.

// --- CloseTarget ----------------------------------------------------------
//
// The target of a close dialog. This consolidates all logic for prompting the
// user and closing windows/tabs/surfaces into one source of truth. Mirrors the
// Zig `Target` enum (renamed `CloseTarget` here to avoid colliding with
// apprt's target concept and to be self-documenting).
pub enum CloseTarget as i32 {
	app
	tab
	window
	surface
}

// title returns the dialog heading for this target. Mirrors `Target.title`.
pub fn (t CloseTarget) title() string {
	return match t {
		.app { i18n_('Quit Witty?') }
		.tab { i18n_('Close Tab?') }
		.window { i18n_('Close Window?') }
		.surface { i18n_('Close Split?') }
	}
}

// body returns the dialog body for this target. Mirrors `Target.body`.
pub fn (t CloseTarget) body() string {
	return match t {
		.app { i18n_('All terminal sessions will be terminated.') }
		.tab { i18n_('All terminal sessions in this tab will be terminated.') }
		.window { i18n_('All terminal sessions in this window will be terminated.') }
		.surface { i18n_('The currently running process in this split will be terminated.') }
	}
}

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhosttyCloseConfirmationDialog`: a `.ui` template, a `target` enum property,
// `close-request`/`cancel` signals, private data, and a dispose vfunc.

// Ghostty's ui/1.2/close-confirmation-dialog.blp as blueprint-compiler 0.16.0 emits it
// (without the generated-file header). Ghostty compiles it into its
// gresource and loads it with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const close_confirmation_dialog_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttyCloseConfirmationDialog" parent="GhosttyDialog">
    <responses>
      <response id="cancel" translatable="yes">Cancel</response>
      <response id="close" translatable="yes" appearance="destructive">Close</response>
    </responses>
    <property name="close-response">cancel</property>
  </template>
</interface>
'

// The C-layout private struct mirroring ghostty's `Private` (the `target`
// field). Registered via g_type_add_instance_private and used to back the
// `target` property.
struct C.GhosttyCloseConfirmationDialogPrivate {
mut:
	target int
}

// The GObject type id and the private-data offset (returned by
// g_type_add_instance_private), both registered lazily on first use.
__global g_close_confirmation_dialog_type = GType(0)
__global g_close_confirmation_dialog_priv_offset = int(0)
__global g_close_confirmation_target_type = GType(0)
__global g_close_confirmation_target_values = [5]C.GEnumValue{}

// Property ids for the get/set vfunc dispatch.
const close_confirmation_prop_target = u32(1)

// close_confirmation_dialog_priv returns the instance private data pointer.
fn close_confirmation_dialog_priv(obj voidptr) &C.GhosttyCloseConfirmationDialogPrivate {
	return &C.GhosttyCloseConfirmationDialogPrivate(instance_private(obj, g_close_confirmation_dialog_priv_offset))
}

// close_confirmation_dialog_get_property implements the GObjectClass
// get_property vfunc for the `target` property.
fn close_confirmation_dialog_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == close_confirmation_prop_target {
		priv := close_confirmation_dialog_priv(obj)
		C.g_value_set_enum(value, priv.target)
	}
}

// close_confirmation_dialog_set_property implements the GObjectClass
// set_property vfunc for the `target` property.
fn close_confirmation_dialog_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	if property_id == close_confirmation_prop_target {
		mut priv := close_confirmation_dialog_priv(obj)
		priv.target = C.g_value_get_enum(value)
	}
}

fn close_confirmation_target_get_type() GType {
	if g_close_confirmation_target_type == GType(0) {
		g_close_confirmation_target_values[0] = C.GEnumValue{ value: int(CloseTarget.app), value_name: c'app', value_nick: c'app' }
		g_close_confirmation_target_values[1] = C.GEnumValue{ value: int(CloseTarget.tab), value_name: c'tab', value_nick: c'tab' }
		g_close_confirmation_target_values[2] = C.GEnumValue{ value: int(CloseTarget.window), value_name: c'window', value_nick: c'window' }
		g_close_confirmation_target_values[3] = C.GEnumValue{ value: int(CloseTarget.surface), value_name: c'surface', value_nick: c'surface' }
		g_close_confirmation_target_values[4] = C.GEnumValue{ value: 0, value_name: &char(unsafe { nil }), value_nick: &char(unsafe { nil }) }
		g_close_confirmation_target_type = C.g_enum_register_static(c'GhosttyCloseConfirmationDialogTarget', &g_close_confirmation_target_values[0])
	}
	return g_close_confirmation_target_type
}

// close_confirmation_dialog_dispose disposes the template and chains to the
// parent. Mirrors the `dispose` vfunc.
fn close_confirmation_dialog_dispose(obj voidptr) {
	C.gtk_widget_dispose_template(obj, g_close_confirmation_dialog_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// close_confirmation_dialog_class_init installs the template, the `target`
// property, the signals, and overrides the get/set/dispose vfuncs. Mirrors the
// ghostty `Class.init`.
fn close_confirmation_dialog_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_close_confirmation_dialog_priv_offset)
	// Ensure the parent Dialog type is registered (ghostty's ensureType).
	dialog_get_type()

	// Template.
	bytes := C.g_bytes_new_static(close_confirmation_dialog_ui.str, uint(close_confirmation_dialog_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)

	// Property: target.
	pspec := C.g_param_spec_enum(c'target', c'target', c'The close target', close_confirmation_target_get_type(), int(CloseTarget.app), g_param_readwrite)
	C.witty_gobject_class_set_get_property(klass, voidptr(close_confirmation_dialog_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(close_confirmation_dialog_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(close_confirmation_dialog_dispose))
	C.witty_dialog_class_set_response(klass, b2i(supports_dialogs()), voidptr(close_confirmation_native_response_cb))
	C.g_object_class_install_property(klass, close_confirmation_prop_target, pspec)

	// Signals: close-request, cancel (both void, no params).
	self_type := g_close_confirmation_dialog_type
	C.g_signal_new(c'close-request', self_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
	C.g_signal_new(c'cancel', self_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
}

// close_confirmation_dialog_instance_init builds the template. Mirrors the
// ghostty `init` (instanceInit).
fn close_confirmation_dialog_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
}

// close_confirmation_dialog_get_type lazily registers the
// GhosttyCloseConfirmationDialog GObject type. Its parent is the GhosttyDialog
// type; it adds instance-private data for the `target` field.
pub fn close_confirmation_dialog_get_type() GType {
	if g_close_confirmation_dialog_type == GType(0) {
		parent := dialog_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(close_confirmation_dialog_class_init)
			instance_init: voidptr(close_confirmation_dialog_instance_init)
		}
		g_close_confirmation_dialog_type = C.g_type_register_static(parent, c'GhosttyCloseConfirmationDialog', &info, 0)
		g_close_confirmation_dialog_priv_offset = C.g_type_add_instance_private(g_close_confirmation_dialog_type, sizeof(C.GhosttyCloseConfirmationDialogPrivate))
	}
	return g_close_confirmation_dialog_type
}

// --- CloseConfirmationDialog ----------------------------------------------

// CloseConfirmationDialog is the close-confirmation dialog GObject
// (`GhosttyCloseConfirmationDialog`, a subclass of `Dialog`). Modeled as a
// struct embedding the base `Dialog`; the target remains authoritative in the
// native instance-private property storage, as it is in Ghostty.
@[heap]
pub struct CloseConfirmationDialog {
mut:
	// The base dialog. In ghostty this is the parent instance (`Dialog`).
	dialog Dialog
}

// close_confirmation_dialog_new creates a new dialog for the given target.
// Mirrors `gobject.ext.newInstance(Self, .{ .target = target })`: it builds the
// GObject (running the `.ui` template init) with the `target` property set.
pub fn close_confirmation_dialog_new(target CloseTarget) &CloseConfirmationDialog {
	obj := C.g_object_new(close_confirmation_dialog_get_type(), c'target', int(target), &char(unsafe { nil }))
	return &CloseConfirmationDialog{
		dialog: Dialog{
			obj: obj
		}
	}
}

// AdwAlertDialog and AdwMessageDialog both expose the same response signal.
// This callback is installed as the corresponding virtual method on whichever
// parent Dialog class is available.
fn close_confirmation_native_response_cb(obj GObject, response_id &char) {
	if isnil(obj) || isnil(response_id) {
		return
	}
	response := unsafe { cstring_to_vstring(response_id) }
	if response == 'close' {
		C.g_signal_emit_by_name(obj, c'close-request')
	} else {
		C.g_signal_emit_by_name(obj, c'cancel')
	}
}

// present sets up the title/body from the target and shows the dialog. Mirrors
// `CloseConfirmationDialog.present`.
pub fn (mut self CloseConfirmationDialog) present(parent ?GtkWidget) {
	// Setup our title/body text.
	priv := close_confirmation_dialog_priv(voidptr(self.dialog.obj))
	target := unsafe { CloseTarget(priv.target) }
	self.dialog.set_heading(&char(target.title().str))
	self.dialog.set_body(&char(target.body().str))

	// Show it.
	self.dialog.present(parent)
}

// close closes the dialog. Mirrors `CloseConfirmationDialog.close`.
pub fn (mut self CloseConfirmationDialog) close() {
	self.dialog.close()
}

// --- GObject reference counting -------------------------------------------
// Mirrors the `Common(Self, Private)` ref helpers (ref/refSink/unref).

// ref increments the reference count of the dialog GObject and returns this
// wrapper. Mirrors `ref`.
pub fn (mut self CloseConfirmationDialog) ref() &CloseConfirmationDialog {
	self.dialog.ref()
	return self
}

// ref_sink clears the initial floating reference or takes an additional
// reference, and returns this wrapper. Mirrors `refSink`.
pub fn (mut self CloseConfirmationDialog) ref_sink() &CloseConfirmationDialog {
	if !isnil(self.dialog.obj) {
		C.g_object_ref_sink(GObject(self.dialog.obj))
	}
	return self
}

// unref decrements the reference count of the dialog GObject. Mirrors `unref`.
pub fn (mut self CloseConfirmationDialog) unref() {
	self.dialog.unref()
}
