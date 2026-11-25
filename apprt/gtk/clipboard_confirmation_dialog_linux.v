@[has_globals]
module gtk

// clipboard_confirmation_dialog_linux.v - Clipboard confirmation dialog
// (GhosttyClipboardConfirmationDialog).
//
// Translated from ghostty/src/apprt/gtk/class/clipboard_confirmation_dialog.zig.
//
// In ghostty this is a GObject class (subclass of the base `Dialog`) that asks
// the user to authorize a clipboard read/write (OSC 52) or an unsafe paste. It
// carries `request` / `clipboard-contents` / `blur` / `can-remember`
// properties, `confirm` / `deny` signals (each carrying whether the choice
// should be remembered), template children (the text view, reveal/hide
// buttons, remember switch), and blur/reveal/hide behavior.
//
// The GObject class registration (`defineClass`), the four PROPERTIES, the
// `.ui` template + child bindings + template callbacks, and the
// `confirm`/`deny` SIGNALS are hand-expanded below onto the raw GObject/GTK C
// API. The V struct `ClipboardConfirmationDialog` retains only the native
// instance; property state lives in the registered GObject private data.
// The real LOGIC — the request -> heading/body text (prop_request), the blur /
// reveal / hide widget-state toggles, and the response-id -> signal routing
// (with the remember flag) — is translated directly.
//
// NOTE(types): ghostty's `request` is a boxed `?*apprt.ClipboardRequest` and
// `clipboard-contents` is an object `?*gtk.TextBuffer`. The V sum type cannot
// be exposed to GLib directly, so its boxed payload is the equivalent compact
// tag/clipboard projection registered under Ghostty's exact boxed type name.

import apprt

// --- New opaque handle aliases --------------------------------------------
// (Grep-verified: not declared elsewhere in the module.)
// NOTE: GtkScrolledWindow is declared in surface_scrolled_window_linux.v —
// reused here, NOT redeclared.

// GtkTextView is a gtk.TextView*.
pub type GtkTextView = voidptr

// GtkButton is a gtk.Button*.
pub type GtkButton = voidptr

// AdwSwitchRow is an adw.SwitchRow* (libadwaita >= 1.4).
pub type AdwSwitchRow = voidptr

// --- New GTK/Adw C bindings -----------------------------------------------
// Only functions not already declared anywhere else in the module.
// NOTE: gtk_widget_set_visible / gtk_widget_add_css_class /
// gtk_widget_remove_css_class are declared in window_linux.v (int form) —
// reused here via `b2i`, NOT redeclared.

fn C.gtk_widget_set_sensitive(widget GtkWidget, sensitive int)

fn C.adw_switch_row_get_active(row AdwSwitchRow) int

// Template-callback binding.
fn C.gtk_widget_class_bind_template_callback_full(widget_class voidptr, callback_name &char, callback_symbol voidptr)

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhosttyClipboardConfirmationDialog`: a `.ui` template with child bindings +
// callbacks, four properties (blur, can-remember, clipboard-contents, request),
// `confirm`/`deny` signals (each carrying the remember bool), private data, and
// dispose + finalize vfuncs.

// GObject fundamental type used for the signal/property declarations.
// G_TYPE_BOOLEAN = 5 << 2. G_TYPE_POINTER remains module-visible because the
// global-shortcuts signal uses it as a parameter type.
const g_type_boolean = GType(5 << 2)
const g_type_pointer = GType(17 << 2)

// Runtime template for ui/1.4/clipboard-confirmation-dialog.blp.
// Older Adwaita releases use the same template without the switch row.
const clipboard_confirmation_dialog_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttyClipboardConfirmationDialog" parent="GhosttyDialog">
    <style>
      <class name="clipboard-confirmation-dialog"/>
    </style>
    <signal name="notify::blur" handler="notify_blur"/>
    <signal name="notify::request" handler="notify_request"/>
    <property name="heading" translatable="yes">Authorize Clipboard Access</property>
    <property name="body">If you see this text, there is a bug in Witty. Please report it.</property>
    <responses>
      <response id="cancel" translatable="yes" appearance="suggested">Deny</response>
      <response id="ok" translatable="yes" appearance="destructive">Allow</response>
    </responses>
    <property name="default-response">cancel</property>
    <property name="close-response">cancel</property>
    <property name="extra-child">
      <object class="GtkListBox">
        <property name="selection-mode">0</property>
        <child>
          <object class="GtkOverlay">
            <style>
              <class name="osd"/>
              <class name="clipboard-overlay"/>
            </style>
            <child>
              <object class="GtkStack" id="preview">
                <style>
                  <class name="clipboard-contents"/>
                </style>
                <property name="width-request">500</property>
                <property name="height-request">200</property>
                <child>
                  <object class="GtkScrolledWindow">
                    <child>
                      <object class="GtkTextView" id="text_view">
                        <property name="cursor-visible">false</property>
                        <property name="editable">false</property>
                        <property name="monospace">true</property>
                        <property name="buffer" bind-source="GhosttyClipboardConfirmationDialog" bind-property="clipboard-contents" bind-flags="sync-create"/>
                      </object>
                    </child>
                  </object>
                </child>
              </object>
            </child>
            <child type="overlay">
              <object class="GtkButton" id="reveal_button">
                <signal name="clicked" handler="reveal_clicked"/>
                <property name="visible">false</property>
                <property name="halign">2</property>
                <property name="valign">1</property>
                <property name="margin-end">12</property>
                <property name="margin-top">12</property>
                <child>
                  <object class="GtkImage">
                    <property name="icon-name">view-reveal-symbolic</property>
                  </object>
                </child>
              </object>
            </child>
            <child type="overlay">
              <object class="GtkButton" id="hide_button">
                <signal name="clicked" handler="hide_clicked"/>
                <property name="visible">false</property>
                <property name="halign">2</property>
                <property name="valign">1</property>
                <property name="margin-end">12</property>
                <property name="margin-top">12</property>
                <style>
                  <class name="opaque"/>
                </style>
                <child>
                  <object class="GtkImage">
                    <property name="icon-name">view-conceal-symbolic</property>
                  </object>
                </child>
              </object>
            </child>
          </object>
        </child>
        <child>
          <object class="AdwSwitchRow" id="remember_choice">
            <style>
              <class name="card"/>
            </style>
            <property name="visible" bind-source="GhosttyClipboardConfirmationDialog" bind-property="can-remember" bind-flags="sync-create"/>
            <property name="title" translatable="yes">Remember choice for this split</property>
            <property name="subtitle" translatable="yes">Reload configuration to show this prompt again</property>
          </object>
        </child>
      </object>
    </property>
  </template>
</interface>
'

// This is the sole fragment added by Ghostty's 1.4 Blueprint. Removing it
// yields the compiled 1.0 template selected when SwitchRow is unavailable.
const clipboard_confirmation_dialog_switch_row_ui = '        <child>
          <object class="AdwSwitchRow" id="remember_choice">
            <style>
              <class name="card"/>
            </style>
            <property name="visible" bind-source="GhosttyClipboardConfirmationDialog" bind-property="can-remember" bind-flags="sync-create"/>
            <property name="title" translatable="yes">Remember choice for this split</property>
            <property name="subtitle" translatable="yes">Reload configuration to show this prompt again</property>
          </object>
        </child>
'

// ClipboardRequestBox is the scalar boxed representation of Ghostty's tagged
// ClipboardRequest union. GObject treats boxed values as opaque; conversions
// at the V boundary preserve the exact active arm and its clipboard payload.
struct ClipboardRequestBox {
mut:
	tag       apprt.ClipboardRequestType
	clipboard apprt.Clipboard
}

__global g_clipboard_request_boxed_type = GType(0)

fn clipboard_request_box(request apprt.ClipboardRequest) ClipboardRequestBox {
	return match request {
		apprt.ClipboardRequestPaste {
			ClipboardRequestBox{
				tag:       .paste
				clipboard: .standard
			}
		}
		apprt.ClipboardRequestOsc52Read {
			ClipboardRequestBox{
				tag:       .osc_52_read
				clipboard: request.clipboard
			}
		}
		apprt.ClipboardRequestOsc52Write {
			ClipboardRequestBox{
				tag:       .osc_52_write
				clipboard: request.clipboard
			}
		}
	}
}

fn (request &ClipboardRequestBox) value() apprt.ClipboardRequest {
	return match request.tag {
		.paste { apprt.ClipboardRequestPaste{} }
		.osc_52_read { apprt.ClipboardRequestOsc52Read{ clipboard: request.clipboard } }
		.osc_52_write { apprt.ClipboardRequestOsc52Write{ clipboard: request.clipboard } }
	}
}

fn clipboard_request_boxed_copy(value voidptr) voidptr {
	if isnil(value) {
		return unsafe { nil }
	}
	source := unsafe { &ClipboardRequestBox(value) }
	result := C.g_malloc0(sizeof(ClipboardRequestBox))
	if isnil(result) {
		return unsafe { nil }
	}
	mut copy := unsafe { &ClipboardRequestBox(result) }
	copy.tag = source.tag
	copy.clipboard = source.clipboard
	return result
}

fn clipboard_request_boxed_free(value voidptr) {
	if !isnil(value) {
		C.g_free(value)
	}
}

fn clipboard_request_boxed_get_type() GType {
	if g_clipboard_request_boxed_type == GType(0) {
		g_clipboard_request_boxed_type = C.g_boxed_type_register_static(c'GhosttyClipboardRequest',
			voidptr(clipboard_request_boxed_copy), voidptr(clipboard_request_boxed_free))
	}
	return g_clipboard_request_boxed_type
}

// The C-layout private struct mirroring ghostty\'s `Private`: the four property
// fields followed by the template-child pointers (bound at their offsets).
struct C.GhosttyClipboardConfirmationDialogPrivate {
mut:
	request            voidptr
	clipboard_contents voidptr
	blur               int
	can_remember       int
	preview            voidptr
	text_view          voidptr
	reveal_button      voidptr
	hide_button        voidptr
	remember_choice    voidptr
}

// The GObject type id and private-data offset, registered lazily.
__global g_clipboard_confirmation_dialog_type = GType(0)
__global g_clipboard_confirmation_dialog_priv_offset = int(0)

// Property ids for the get/set vfunc dispatch.
const clipboard_prop_blur = u32(1)
const clipboard_prop_can_remember = u32(2)
const clipboard_prop_clipboard_contents = u32(3)
const clipboard_prop_request = u32(4)

fn clipboard_confirmation_dialog_priv(obj voidptr) &C.GhosttyClipboardConfirmationDialogPrivate {
	return &C.GhosttyClipboardConfirmationDialogPrivate(instance_private(obj, g_clipboard_confirmation_dialog_priv_offset))
}

// clipboard_confirmation_dialog_get_property implements get_property for all
// four properties.
fn clipboard_confirmation_dialog_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	priv := clipboard_confirmation_dialog_priv(obj)
	match property_id {
		clipboard_prop_blur { C.g_value_set_boolean(value, priv.blur) }
		clipboard_prop_can_remember { C.g_value_set_boolean(value, priv.can_remember) }
		clipboard_prop_clipboard_contents { C.g_value_set_object(value, priv.clipboard_contents) }
		clipboard_prop_request { C.g_value_set_boxed(value, priv.request) }
		else {}
	}
}

// clipboard_confirmation_dialog_set_property implements set_property for all
// four properties. The object property takes a reference (matching the default
// object-property machinery ghostty relies on).
fn clipboard_confirmation_dialog_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	mut priv := clipboard_confirmation_dialog_priv(obj)
	match property_id {
		clipboard_prop_blur {
			priv.blur = C.g_value_get_boolean(value)
		}
		clipboard_prop_can_remember {
			priv.can_remember = C.g_value_get_boolean(value)
		}
		clipboard_prop_clipboard_contents {
			if !isnil(priv.clipboard_contents) {
				object_unref(GObject(priv.clipboard_contents))
			}
			newv := GObject(C.g_value_get_object(value))
			if !isnil(newv) {
				priv.clipboard_contents = voidptr(object_ref(newv))
			} else {
				priv.clipboard_contents = unsafe { nil }
			}
		}
		clipboard_prop_request {
			if !isnil(priv.request) {
				clipboard_request_boxed_free(priv.request)
			}
			priv.request = C.g_value_dup_boxed(value)
		}
		else {}
	}
}

// clipboard_confirmation_dialog_dispose unrefs the clipboard contents, disposes
// the template and chains to the parent. Mirrors the `dispose` vfunc.
fn clipboard_confirmation_dialog_dispose(obj voidptr) {
	mut priv := clipboard_confirmation_dialog_priv(obj)
	C.witty_gtk_dialog_canvas_set_fill_widget(GtkWidget(obj), unsafe { nil })
	if !isnil(priv.clipboard_contents) {
		object_unref(GObject(priv.clipboard_contents))
		priv.clipboard_contents = unsafe { nil }
	}
	C.gtk_widget_dispose_template(obj, g_clipboard_confirmation_dialog_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// clipboard_confirmation_dialog_finalize clears the boxed request and chains to
// the parent. Mirrors the `finalize` vfunc.
fn clipboard_confirmation_dialog_finalize(obj voidptr) {
	mut priv := clipboard_confirmation_dialog_priv(obj)
	if !isnil(priv.request) {
		clipboard_request_boxed_free(priv.request)
		priv.request = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

// --- Template callbacks (C-callable) --------------------------------------
// These operate on the GObject private directly (mirroring ghostty, whose
// callbacks use `self.private()`).

fn clipboard_confirmation_notify_blur_cb(obj voidptr, pspec voidptr, ud voidptr) {
	priv := clipboard_confirmation_dialog_priv(obj)
	if priv.blur != 0 {
		C.gtk_widget_set_sensitive(priv.preview, b2i(false))
		C.gtk_widget_add_css_class(priv.preview, c'blurred')
		C.gtk_widget_set_visible(priv.reveal_button, b2i(true))
		C.gtk_widget_set_visible(priv.hide_button, b2i(false))
	} else {
		C.gtk_widget_set_sensitive(priv.preview, b2i(true))
		C.gtk_widget_remove_css_class(priv.preview, c'blurred')
		C.gtk_widget_set_visible(priv.reveal_button, b2i(false))
		C.gtk_widget_set_visible(priv.hide_button, b2i(false))
	}
}

fn clipboard_confirmation_notify_request_cb(obj voidptr, pspec voidptr, ud voidptr) {
	priv := clipboard_confirmation_dialog_priv(obj)
	if isnil(priv.request) {
		return
	}
	request := unsafe { &ClipboardRequestBox(priv.request) }
	mut dialog := Dialog{
		obj: GObject(obj)
	}
	match request.tag {
		.osc_52_write {
			dialog.set_heading(&char(i18n_('Authorize Clipboard Access').str))
			dialog.set_body(&char(i18n_('An application is attempting to write to the clipboard. The current clipboard contents are shown below.').str))
		}
		.osc_52_read {
			dialog.set_heading(&char(i18n_('Authorize Clipboard Access').str))
			dialog.set_body(&char(i18n_('An application is attempting to read from the clipboard. The current clipboard contents are shown below.').str))
		}
		.paste {
			dialog.set_heading(&char(i18n_('Warning: Potentially Unsafe Paste').str))
			dialog.set_body(&char(i18n_('Pasting this text into the terminal may be dangerous as it looks like some commands may be executed.').str))
		}
	}
}

fn clipboard_confirmation_reveal_clicked_cb(button voidptr, obj voidptr) {
	priv := clipboard_confirmation_dialog_priv(obj)
	C.gtk_widget_set_sensitive(priv.preview, b2i(true))
	C.gtk_widget_remove_css_class(priv.preview, c'blurred')
	C.gtk_widget_set_visible(priv.hide_button, b2i(true))
	C.gtk_widget_set_visible(priv.reveal_button, b2i(false))
}

fn clipboard_confirmation_hide_clicked_cb(button voidptr, obj voidptr) {
	priv := clipboard_confirmation_dialog_priv(obj)
	C.gtk_widget_set_sensitive(priv.preview, b2i(false))
	C.gtk_widget_add_css_class(priv.preview, c'blurred')
	C.gtk_widget_set_visible(priv.hide_button, b2i(false))
	C.gtk_widget_set_visible(priv.reveal_button, b2i(true))
}

// clipboard_confirmation_dialog_class_init installs the template, binds the
// template children + callbacks, installs the four properties, registers the
// confirm/deny signals, and overrides the get/set/dispose/finalize vfuncs.
fn clipboard_confirmation_dialog_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_clipboard_confirmation_dialog_priv_offset)
	C.witty_gtk_dialog_canvas_class_init(klass, false)
	template_ui := if supports_switch_row() {
		clipboard_confirmation_dialog_ui
	} else {
		clipboard_confirmation_dialog_ui.replace(clipboard_confirmation_dialog_switch_row_ui,
			'')
	}
	bytes := C.g_bytes_new(template_ui.str, uint(template_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)

	// Template child bindings (into the private struct).
	off := g_clipboard_confirmation_dialog_priv_offset
	C.gtk_widget_class_bind_template_child_full(klass, c'preview', 0, off + int(__offsetof(C.GhosttyClipboardConfirmationDialogPrivate, preview)))
	C.gtk_widget_class_bind_template_child_full(klass, c'text_view', 0, off + int(__offsetof(C.GhosttyClipboardConfirmationDialogPrivate, text_view)))
	C.gtk_widget_class_bind_template_child_full(klass, c'hide_button', 0, off + int(__offsetof(C.GhosttyClipboardConfirmationDialogPrivate, hide_button)))
	C.gtk_widget_class_bind_template_child_full(klass, c'reveal_button', 0, off + int(__offsetof(C.GhosttyClipboardConfirmationDialogPrivate, reveal_button)))
	if supports_switch_row() {
		C.gtk_widget_class_bind_template_child_full(klass, c'remember_choice', 0, off + int(__offsetof(C.GhosttyClipboardConfirmationDialogPrivate, remember_choice)))
	}

	// Template callbacks.
	C.gtk_widget_class_bind_template_callback_full(klass, c'reveal_clicked', voidptr(clipboard_confirmation_reveal_clicked_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'hide_clicked', voidptr(clipboard_confirmation_hide_clicked_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'notify_blur', voidptr(clipboard_confirmation_notify_blur_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'notify_request', voidptr(clipboard_confirmation_notify_request_cb))

	// Properties.
	blur_pspec := C.g_param_spec_boolean(c'blur', c'blur', c'Whether contents are blurred', 0, g_param_readwrite)
	can_remember_pspec := C.g_param_spec_boolean(c'can-remember', c'can-remember', c'Whether the choice can be remembered', 0, g_param_readwrite)
	contents_pspec := C.g_param_spec_object(c'clipboard-contents', c'clipboard-contents', c'The clipboard contents', C.gtk_text_buffer_get_type(), g_param_readwrite)
	request_pspec := C.g_param_spec_boxed(c'request', c'request', c'The clipboard request', clipboard_request_boxed_get_type(), g_param_readwrite)
	C.witty_gobject_class_set_get_property(klass, voidptr(clipboard_confirmation_dialog_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(clipboard_confirmation_dialog_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(clipboard_confirmation_dialog_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(clipboard_confirmation_dialog_finalize))
	C.witty_dialog_class_set_response(klass, b2i(supports_dialogs()), voidptr(clipboard_confirmation_native_response_cb))
	C.g_object_class_install_property(klass, clipboard_prop_blur, blur_pspec)
	C.g_object_class_install_property(klass, clipboard_prop_can_remember, can_remember_pspec)
	C.g_object_class_install_property(klass, clipboard_prop_clipboard_contents, contents_pspec)
	C.g_object_class_install_property(klass, clipboard_prop_request, request_pspec)

	// Signals: confirm, deny (each carrying a bool "remember" param).
	mut bool_param := g_type_boolean
	C.g_signal_new(c'confirm', g_clipboard_confirmation_dialog_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 1, bool_param)
	C.g_signal_new(c'deny', g_clipboard_confirmation_dialog_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 1, bool_param)
}

fn clipboard_confirmation_dialog_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
	priv := clipboard_confirmation_dialog_priv(instance)
	C.witty_gtk_dialog_canvas_set_fill_widget(GtkWidget(instance), GtkWidget(priv.text_view))
	gtk_canvas_overlay_set_mask(GtkWidget(instance), !isnil(priv.text_view))
	// Trigger initial values (matches ghostty's `init`).
	clipboard_confirmation_notify_blur_cb(instance, unsafe { nil }, unsafe { nil })
	clipboard_confirmation_notify_request_cb(instance, unsafe { nil }, unsafe { nil })
}

// clipboard_confirmation_dialog_get_type lazily registers the
// GhosttyClipboardConfirmationDialog GObject type, parented to GhosttyDialog,
// with instance-private data.
pub fn clipboard_confirmation_dialog_get_type() GType {
	if g_clipboard_confirmation_dialog_type == GType(0) {
		parent := dialog_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(clipboard_confirmation_dialog_class_init)
			instance_init: voidptr(clipboard_confirmation_dialog_instance_init)
		}
		g_clipboard_confirmation_dialog_type = C.g_type_register_static(parent, c'GhosttyClipboardConfirmationDialog', &info, 0)
		g_clipboard_confirmation_dialog_priv_offset = C.g_type_add_instance_private(g_clipboard_confirmation_dialog_type, sizeof(C.GhosttyClipboardConfirmationDialogPrivate))
	}
	return g_clipboard_confirmation_dialog_type
}

// --- ClipboardConfirmationDialog ------------------------------------------

// ClipboardConfirmationDialog is the clipboard-confirmation dialog GObject
// (`GhosttyClipboardConfirmationDialog`, a subclass of `Dialog`). The native
// instance-private storage is authoritative, as it is in Ghostty.
@[heap]
pub struct ClipboardConfirmationDialog {
mut:
	dialog Dialog
}

// clipboard_confirmation_dialog_new creates a new dialog. Mirrors
// `gobject.ext.newInstance(Self, .{})`.
pub fn clipboard_confirmation_dialog_new() &ClipboardConfirmationDialog {
	obj := C.g_object_new(clipboard_confirmation_dialog_get_type(), &char(unsafe { nil }))
	return &ClipboardConfirmationDialog{
		dialog: Dialog{
			obj: obj
		}
	}
}

// clipboard_confirmation_dialog_new_for_request constructs the populated
// dialog used by Surface.show_clipboard_confirmation.
pub fn clipboard_confirmation_dialog_new_for_request(req apprt.ClipboardRequest, text string) &ClipboardConfirmationDialog {
	buffer := C.gtk_text_buffer_new(unsafe { nil })
	C.gtk_text_buffer_insert_at_cursor(buffer, &char(text.str), text.len)
	request := clipboard_request_box(req)
	can_remember := match req {
		apprt.ClipboardRequestPaste { false }
		apprt.ClipboardRequestOsc52Read, apprt.ClipboardRequestOsc52Write { true }
	}
	obj := C.g_object_new(clipboard_confirmation_dialog_get_type(), c'request', voidptr(&request),
		c'can-remember', b2i(can_remember), c'clipboard-contents', buffer,
		&char(unsafe { nil }))
	object_unref(buffer)
	return &ClipboardConfirmationDialog{
		dialog: Dialog{
			obj: obj
		}
	}
}

// Route the inherited Adwaita response signal to Ghostty's confirm/deny
// signals. This is the runtime C-API equivalent of the Zig response-vfunc
// override.
fn clipboard_confirmation_native_response_cb(obj GObject, response_id &char) {
	if isnil(obj) || isnil(response_id) {
		return
	}
	priv := clipboard_confirmation_dialog_priv(voidptr(obj))
	remember := !isnil(priv.remember_choice)
		&& C.adw_switch_row_get_active(priv.remember_choice) != 0
	response := unsafe { cstring_to_vstring(response_id) }
	if response == 'cancel' {
		C.g_signal_emit_by_name(obj, c'deny', b2i(remember))
	} else if response == 'ok' {
		C.g_signal_emit_by_name(obj, c'confirm', b2i(remember))
	}
}

// present shows the dialog. Mirrors `ClipboardConfirmationDialog.present`.
pub fn (mut self ClipboardConfirmationDialog) present(parent ?GtkWidget) {
	self.dialog.present(parent)
}

// get_request returns the clipboard request without copying. Mirrors
// `getRequest`.
pub fn (self &ClipboardConfirmationDialog) get_request() ?apprt.ClipboardRequest {
	priv := clipboard_confirmation_dialog_priv(voidptr(self.dialog.obj))
	if isnil(priv.request) {
		return none
	}
	return unsafe { &ClipboardRequestBox(priv.request) }.value()
}

// get_clipboard_contents returns the clipboard contents buffer without copying.
// Mirrors `getClipboardContents`.
pub fn (self &ClipboardConfirmationDialog) get_clipboard_contents() ?GtkTextBuffer {
	contents := clipboard_confirmation_dialog_priv(voidptr(self.dialog.obj)).clipboard_contents
	if isnil(contents) {
		return none
	}
	return GtkTextBuffer(contents)
}

// --- GObject reference counting -------------------------------------------
// Mirrors the `Common(Self, Private)` ref helpers.

// ref increments the reference count of the dialog GObject. Mirrors `ref`.
pub fn (mut self ClipboardConfirmationDialog) ref() &ClipboardConfirmationDialog {
	self.dialog.ref()
	return self
}

// unref decrements the reference count of the dialog GObject. Mirrors `unref`.
pub fn (mut self ClipboardConfirmationDialog) unref() {
	self.dialog.unref()
}
