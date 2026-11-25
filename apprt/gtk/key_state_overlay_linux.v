@[has_globals]
module gtk

// key_state_overlay_linux.v - The GObject KeyStateOverlay widget class for the
// GTK apprt.
//
// Translated from ghostty/src/apprt/gtk/class/key_state_overlay.zig.
//
// An overlay that displays the current key-table stack and the pending
// key-sequence, so users can see what key bindings are active and which keys
// they've pressed in a multi-key sequence. It is a draggable `adw.Bin` that
// snaps between top-center and bottom-center of its parent (horizontal
// alignment is always center for this overlay).
//
// The GObject class registration (ghostty's `gobject.ext.defineClass`), the
// blueprint template with its five template callbacks, the five properties
// (tables/has-tables/sequence/has-sequence/valign-target), and the dispose/
// finalize vfuncs are hand-expanded onto the raw GObject/GTK C API below. The
// real state logic (tables/sequence StringLists, has-* derivations, the
// chevron/has-state/text closures, and the drag-end vertical realignment) is
// translated. The class is additionally modeled as a plain V struct wrapping
// the GObject/GtkWidget ptr for callers in V.
//
// Reuses: `Align` (resize_overlay_linux.v), `StringList` (ext_slice_linux.v),
// `GtkWidget` (c_gtk_linux.v). GtkWidget allocation/parent/queue-resize C
// helpers are declared in search_overlay_linux.v and reused here; the enum
// param-spec + gtk_align_get_type helpers come from resize_overlay_linux.v.

// --- KeyStateOverlay ------------------------------------------------------

// KeyStateOverlay is the V model of the `GhosttyKeyStateOverlay` GObject class.
// The state itself lives in the registered GObject instance-private storage;
// this wrapper only carries the widget pointer.
@[heap]
pub struct KeyStateOverlay {

	// The GtkWidget (adw.Bin) pointer for this instance.
pub mut:
	widget GtkWidget = unsafe { nil }
}

// new_key_state_overlay creates a new KeyStateOverlay. Mirrors
// `gobject.ext.newInstance` + the instance `init` (which just runs the
// template).
pub fn new_key_state_overlay() &KeyStateOverlay {
	obj := C.g_object_new(key_state_overlay_get_type(), &char(unsafe { nil }))
	return &KeyStateOverlay{
		widget: obj
	}
}

// --- Property getters/setters ---------------------------------------------

// get_tables returns the optional key-table StringList. Mirrors `getTables`.
pub fn (self &KeyStateOverlay) get_tables() ?&StringList {
	if isnil(self.widget) {
		return none
	}
	tables := key_state_priv(voidptr(self.widget)).tables
	if isnil(tables) {
		return none
	}
	return unsafe { &StringList(tables) }
}

// get_sequence returns the optional key-sequence StringList. Mirrors
// `getSequence`.
pub fn (self &KeyStateOverlay) get_sequence() ?&StringList {
	if isnil(self.widget) {
		return none
	}
	sequence := key_state_priv(voidptr(self.widget)).sequence
	if isnil(sequence) {
		return none
	}
	return unsafe { &StringList(sequence) }
}

// set_tables replaces the key-table StringList, destroying the old one (which
// this object owns). Mirrors `setTables`.
pub fn (mut self KeyStateOverlay) set_tables(value ?&StringList) {
	if isnil(self.widget) {
		return
	}
	mut priv := key_state_priv(voidptr(self.widget))
	if !isnil(priv.tables) {
		mut old := unsafe { &StringList(priv.tables) }
		old.destroy()
		priv.tables = unsafe { nil }
	}
	if v := value {
		priv.tables = voidptr(v)
	}
	C.g_object_notify_by_pspec(self.widget, g_key_state_overlay_pspec_tables)
	C.g_object_notify_by_pspec(self.widget, g_key_state_overlay_pspec_has_tables)
}

// set_sequence replaces the key-sequence StringList, destroying the old one.
// Mirrors `setSequence`.
pub fn (mut self KeyStateOverlay) set_sequence(value ?&StringList) {
	if isnil(self.widget) {
		return
	}
	mut priv := key_state_priv(voidptr(self.widget))
	if !isnil(priv.sequence) {
		mut old := unsafe { &StringList(priv.sequence) }
		old.destroy()
		priv.sequence = unsafe { nil }
	}
	if v := value {
		priv.sequence = voidptr(v)
	}
	C.g_object_notify_by_pspec(self.widget, g_key_state_overlay_pspec_sequence)
	C.g_object_notify_by_pspec(self.widget, g_key_state_overlay_pspec_has_sequence)
}

// get_has_tables reports whether there is at least one key table. Mirrors
// `getHasTables`.
pub fn (self &KeyStateOverlay) get_has_tables() bool {
	tables := self.get_tables() or { return false }
	return tables.strings.len > 0
}

// get_has_sequence reports whether there is a pending key sequence. Mirrors
// `getHasSequence`.
pub fn (self &KeyStateOverlay) get_has_sequence() bool {
	sequence := self.get_sequence() or { return false }
	return sequence.strings.len > 0
}

// --- Closures (label/visibility helpers) ----------------------------------

// show_chevron reports whether the separating chevron should be shown (only
// when BOTH tables and a sequence are present). Mirrors `closureShowChevron`.
pub fn (self &KeyStateOverlay) show_chevron(has_tables bool, has_sequence bool) bool {
	return has_tables && has_sequence
}

// has_state reports whether the overlay has anything to show at all. Mirrors
// `closureHasState`.
pub fn (self &KeyStateOverlay) has_state(has_tables bool, has_sequence bool) bool {
	return has_tables || has_sequence
}

// tables_text joins the key-table stack with " > " separators, or `none` if
// there are no tables. Mirrors `closureTablesText`.
pub fn (self &KeyStateOverlay) tables_text(list &StringList) ?string {
	if isnil(list) {
		return none
	}
	if list.strings.len == 0 {
		return none
	}
	mut sb := ''
	for i, s in list.strings {
		if i > 0 {
			sb += ' > '
		}
		sb += s
	}
	return sb
}

// sequence_text joins the pending key sequence with " " separators, or `none`
// if there is no sequence. Mirrors `closureSequenceText`.
pub fn (self &KeyStateOverlay) sequence_text(list &StringList) ?string {
	if isnil(list) {
		return none
	}
	if list.strings.len == 0 {
		return none
	}
	mut sb := ''
	for i, s in list.strings {
		if i > 0 {
			sb += ' '
		}
		sb += s
	}
	return sb
}

// --- Template callbacks ---------------------------------------------------

// on_drag_end is the "drag-end" template callback on the drag gesture. The key
// state overlay only moves between top-center and bottom-center; horizontal
// alignment is always center. Mirrors `onDragEnd`.
pub fn (mut self KeyStateOverlay) on_drag_end(offset_y f64) {
	if isnil(self.widget) {
		return
	}
	mut priv := key_state_priv(voidptr(self.widget))
	parent := C.gtk_widget_get_parent(self.widget)
	if isnil(parent) {
		return
	}

	parent_height := f64(C.gtk_widget_get_allocated_height(parent))
	self_height := f64(C.gtk_widget_get_allocated_height(self.widget))

	self_y := if priv.valign_target == int(Align.start) {
		f64(0)
	} else {
		parent_height - self_height
	}
	new_y := self_y + offset_y + (self_height / 2)

	new_valign := if new_y > parent_height / 2 { Align.end } else { Align.start }

	if int(new_valign) != priv.valign_target {
		priv.valign_target = int(new_valign)
		C.g_object_notify_by_pspec(self.widget, g_key_state_overlay_pspec_valign_target)
		C.gtk_widget_queue_resize(self.widget)
	}
}

// --- GObject reference counting -------------------------------------------

pub fn (mut self KeyStateOverlay) ref() &KeyStateOverlay {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

pub fn (mut self KeyStateOverlay) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhosttyKeyStateOverlay` (parent adw.Bin): a `.ui` template with five
// template callbacks, five properties, and dispose/finalize vfuncs.

// Ghostty's ui/1.2/key-state-overlay.blp as blueprint-compiler 0.16.0 emits it
// (without the generated-file header). Ghostty compiles it into its
// gresource and loads it with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const key_state_overlay_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttyKeyStateOverlay" parent="AdwBin">
    <binding name="visible">
      <closure function="has_state" type="gboolean">
        <lookup name="has-tables" type="GhosttyKeyStateOverlay">
          <constant>GhosttyKeyStateOverlay</constant>
        </lookup>
        <lookup name="has-sequence" type="GhosttyKeyStateOverlay">
          <constant>GhosttyKeyStateOverlay</constant>
        </lookup>
      </closure>
    </binding>
    <property name="valign-target">end</property>
    <property name="halign">3</property>
    <property name="valign" bind-source="GhosttyKeyStateOverlay" bind-property="valign-target" bind-flags="sync-create"/>
    <child>
      <object class="GtkGestureDrag">
        <property name="button">1</property>
        <property name="propagation-phase">1</property>
        <signal name="drag-end" handler="on_drag_end"/>
      </object>
    </child>
    <child>
      <object class="WittyCanvasOverlayBin">
        <child>
          <object class="GtkBox" id="container">
            <style>
              <class name="background"/>
              <class name="key-state-overlay"/>
            </style>
            <property name="orientation">0</property>
            <property name="spacing">6</property>
            <child>
              <object class="GtkImage">
                <property name="icon-name">input-keyboard-symbolic</property>
                <property name="pixel-size">16</property>
              </object>
            </child>
            <child>
              <object class="GtkLabel" id="tables_label">
                <property name="visible" bind-source="GhosttyKeyStateOverlay" bind-property="has-tables" bind-flags="sync-create"/>
                <binding name="label">
                  <closure function="tables_text" type="gchararray">
                    <lookup name="tables" type="GhosttyKeyStateOverlay">
                      <constant>GhosttyKeyStateOverlay</constant>
                    </lookup>
                  </closure>
                </binding>
                <property name="xalign">0</property>
              </object>
            </child>
            <child>
              <object class="GtkLabel" id="chevron_label">
                <binding name="visible">
                  <closure function="show_chevron" type="gboolean">
                    <lookup name="has-tables" type="GhosttyKeyStateOverlay">
                      <constant>GhosttyKeyStateOverlay</constant>
                    </lookup>
                    <lookup name="has-sequence" type="GhosttyKeyStateOverlay">
                      <constant>GhosttyKeyStateOverlay</constant>
                    </lookup>
                  </closure>
                </binding>
                <property name="label">›</property>
                <style>
                  <class name="dim-label"/>
                </style>
              </object>
            </child>
            <child>
              <object class="GtkLabel" id="sequence_label">
                <property name="visible" bind-source="GhosttyKeyStateOverlay" bind-property="has-sequence" bind-flags="sync-create"/>
                <binding name="label">
                  <closure function="sequence_text" type="gchararray">
                    <lookup name="sequence" type="GhosttyKeyStateOverlay">
                      <constant>GhosttyKeyStateOverlay</constant>
                    </lookup>
                  </closure>
                </binding>
                <property name="xalign">0</property>
              </object>
            </child>
            <child>
              <object class="GtkSpinner" id="pending_spinner">
                <property name="visible" bind-source="GhosttyKeyStateOverlay" bind-property="has-sequence" bind-flags="sync-create"/>
                <property name="spinning" bind-source="GhosttyKeyStateOverlay" bind-property="has-sequence" bind-flags="sync-create"/>
              </object>
            </child>
          </object>
        </child>
      </object>
    </child>
  </template>
</interface>
'

// The C-layout private struct mirroring ghostty\'s `Private`. The StringLists
// are registered boxed values whose ownership is transferred into this object.
struct C.GhosttyKeyStateOverlayPrivate {
mut:
	tables        voidptr
	sequence      voidptr
	valign_target int
}

// The GObject type id and private-data offset, registered lazily.
__global g_key_state_overlay_type = GType(0)
__global g_key_state_overlay_priv_offset = int(0)

// Registered GParamSpec* pointers, captured in class_init for notify.
__global g_key_state_overlay_pspec_tables = &C.GParamSpec(unsafe { nil })
__global g_key_state_overlay_pspec_has_tables = &C.GParamSpec(unsafe { nil })
__global g_key_state_overlay_pspec_sequence = &C.GParamSpec(unsafe { nil })
__global g_key_state_overlay_pspec_has_sequence = &C.GParamSpec(unsafe { nil })
__global g_key_state_overlay_pspec_valign_target = &C.GParamSpec(unsafe { nil })

// Property ids for the get/set vfunc dispatch.
const key_state_prop_tables = u32(1)
const key_state_prop_has_tables = u32(2)
const key_state_prop_sequence = u32(3)
const key_state_prop_has_sequence = u32(4)
const key_state_prop_valign_target = u32(5)

// --- Template-callback trampolines ----------------------------------------
// These are the C-ABI closures the .ui bindings invoke. show_chevron/has_state
// are pure functions of their bool args; tables_text/sequence_text receive a
// StringList pointer (from the tables/sequence property) and return a
// glib-owned string; on_drag_end forwards to the wrapper via user-data.
fn key_state_show_chevron_cb(self voidptr, has_tables int, has_sequence int) int {
	return if has_tables != 0 && has_sequence != 0 { 1 } else { 0 }
}

fn key_state_has_state_cb(self voidptr, has_tables int, has_sequence int) int {
	return if has_tables != 0 || has_sequence != 0 { 1 } else { 0 }
}

fn key_state_tables_text_cb(self voidptr, tables voidptr) &char {
	if isnil(tables) {
		return &char(unsafe { nil })
	}
	list := unsafe { &StringList(tables) }
	if list.strings.len == 0 {
		return &char(unsafe { nil })
	}
	mut sb := ''
	for i, s in list.strings {
		if i > 0 {
			sb += ' > '
		}
		sb += s
	}
	return C.g_strdup(sb.str)
}

fn key_state_sequence_text_cb(self voidptr, sequence voidptr) &char {
	if isnil(sequence) {
		return &char(unsafe { nil })
	}
	list := unsafe { &StringList(sequence) }
	if list.strings.len == 0 {
		return &char(unsafe { nil })
	}
	mut sb := ''
	for i, s in list.strings {
		if i > 0 {
			sb += ' '
		}
		sb += s
	}
	return C.g_strdup(sb.str)
}

fn key_state_priv(obj voidptr) &C.GhosttyKeyStateOverlayPrivate {
	return &C.GhosttyKeyStateOverlayPrivate(instance_private(obj, g_key_state_overlay_priv_offset))
}

// key_state_overlay_get_property implements the GObjectClass get_property vfunc.
// The StringList-backed tables/sequence and their has-* derivations are served
// from the private pointers so the template lookups resolve.
fn key_state_overlay_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	priv := key_state_priv(obj)
	match property_id {
		key_state_prop_tables {
			C.g_value_set_boxed(value, priv.tables)
		}
		key_state_prop_has_tables {
			has := if isnil(priv.tables) {
				false
			} else {
				unsafe { &StringList(priv.tables) }.strings.len > 0
			}
			C.g_value_set_boolean(value, b2i(has))
		}
		key_state_prop_sequence {
			C.g_value_set_boxed(value, priv.sequence)
		}
		key_state_prop_has_sequence {
			has := if isnil(priv.sequence) {
				false
			} else {
				unsafe { &StringList(priv.sequence) }.strings.len > 0
			}
			C.g_value_set_boolean(value, b2i(has))
		}
		key_state_prop_valign_target {
			C.g_value_set_enum(value, priv.valign_target)
		}
		else {}
	}
}

// key_state_overlay_set_property implements the GObjectClass set_property vfunc.
fn key_state_overlay_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	mut priv := key_state_priv(obj)
	match property_id {
		key_state_prop_tables {
			if !isnil(priv.tables) {
				mut old := unsafe { &StringList(priv.tables) }
				old.destroy()
			}
			priv.tables = C.g_value_dup_boxed(value)
			C.g_object_notify_by_pspec(obj, g_key_state_overlay_pspec_has_tables)
		}
		key_state_prop_sequence {
			if !isnil(priv.sequence) {
				mut old := unsafe { &StringList(priv.sequence) }
				old.destroy()
			}
			priv.sequence = C.g_value_dup_boxed(value)
			C.g_object_notify_by_pspec(obj, g_key_state_overlay_pspec_has_sequence)
		}
		key_state_prop_valign_target {
			priv.valign_target = C.g_value_get_enum(value)
		}
		else {}
	}
}

// key_state_overlay_dispose disposes the template and chains up. Mirrors the
// `dispose` vfunc.
fn key_state_overlay_dispose(obj voidptr) {
	C.gtk_widget_dispose_template(obj, g_key_state_overlay_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// key_state_overlay_finalize releases the owned StringLists and chains up.
// Mirrors the `finalize` vfunc.
fn key_state_overlay_finalize(obj voidptr) {
	mut priv := key_state_priv(obj)
	if !isnil(priv.tables) {
		mut tables := unsafe { &StringList(priv.tables) }
		tables.destroy()
		priv.tables = unsafe { nil }
	}
	if !isnil(priv.sequence) {
		mut sequence := unsafe { &StringList(priv.sequence) }
		sequence.destroy()
		priv.sequence = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

// key_state_overlay_class_init installs the template, wires the five template
// callbacks, registers the five properties, and overrides the
// get/set/dispose/finalize vfuncs. Mirrors the ghostty `Class.init`.
fn key_state_overlay_class_init(klass voidptr, class_data voidptr) {
	C.witty_gtk_canvas_overlay_register()
	C.g_type_class_adjust_private_offset(klass, &g_key_state_overlay_priv_offset)
	bytes := C.g_bytes_new_static(key_state_overlay_ui.str, uint(key_state_overlay_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)

	// Template callbacks.
	C.gtk_widget_class_bind_template_callback_full(klass, c'on_drag_end', voidptr(key_state_on_drag_end_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'show_chevron', voidptr(key_state_show_chevron_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'has_state', voidptr(key_state_has_state_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'tables_text', voidptr(key_state_tables_text_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'sequence_text', voidptr(key_state_sequence_text_cb))

	// Properties.
	align_type := C.gtk_align_get_type()
	string_list_type := StringList.get_gobject_type()
	g_key_state_overlay_pspec_tables = C.g_param_spec_boxed(c'tables', c'tables', c'The key table stack', string_list_type, g_param_readwrite)
	g_key_state_overlay_pspec_has_tables = C.g_param_spec_boolean(c'has-tables', c'has-tables', c'Whether there are key tables', 0, g_param_readable)
	g_key_state_overlay_pspec_sequence = C.g_param_spec_boxed(c'sequence', c'sequence', c'The pending key sequence', string_list_type, g_param_readwrite)
	g_key_state_overlay_pspec_has_sequence = C.g_param_spec_boolean(c'has-sequence', c'has-sequence', c'Whether there is a pending sequence', 0, g_param_readable)
	g_key_state_overlay_pspec_valign_target = C.g_param_spec_enum(c'valign-target', c'valign-target', c'Target vertical alignment', align_type, int(Align.end), g_param_readwrite)

	C.witty_gobject_class_set_get_property(klass, voidptr(key_state_overlay_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(key_state_overlay_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(key_state_overlay_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(key_state_overlay_finalize))

	C.g_object_class_install_property(klass, key_state_prop_tables, g_key_state_overlay_pspec_tables)
	C.g_object_class_install_property(klass, key_state_prop_has_tables, g_key_state_overlay_pspec_has_tables)
	C.g_object_class_install_property(klass, key_state_prop_sequence, g_key_state_overlay_pspec_sequence)
	C.g_object_class_install_property(klass, key_state_prop_has_sequence, g_key_state_overlay_pspec_has_sequence)
	C.g_object_class_install_property(klass, key_state_prop_valign_target, g_key_state_overlay_pspec_valign_target)
}

fn key_state_overlay_instance_init(instance voidptr, klass voidptr) {
	mut priv := key_state_priv(instance)
	priv.valign_target = int(Align.end)
	C.gtk_widget_init_template(instance)
}

// key_state_overlay_get_type lazily registers the GhosttyKeyStateOverlay GObject
// type, parented to AdwBin, with instance-private data.
pub fn key_state_overlay_get_type() GType {
	if g_key_state_overlay_type == GType(0) {
		parent := C.adw_bin_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(key_state_overlay_class_init)
			instance_init: voidptr(key_state_overlay_instance_init)
		}
		g_key_state_overlay_type = C.g_type_register_static(parent, c'GhosttyKeyStateOverlay', &info, 0)
		g_key_state_overlay_priv_offset = C.g_type_add_instance_private(g_key_state_overlay_type, sizeof(C.GhosttyKeyStateOverlayPrivate))
	}
	return g_key_state_overlay_type
}

// key_state_on_drag_end_cb is the C-ABI trampoline for the drag gesture's
// "drag-end" signal. Bound via bindTemplateCallback, GTK passes
// (gesture, offset_x, offset_y, instance) where `instance` is the overlay
// widget. It operates directly on the GObject instance/private (mirroring
// ghostty's `onDragEnd`, which uses `self.private()`): the key state overlay
// only moves between top-center and bottom-center, so horizontal alignment is
// always center.
fn key_state_on_drag_end_cb(gesture voidptr, offset_x f64, offset_y f64, instance voidptr) {
	if isnil(instance) {
		return
	}
	mut priv := key_state_priv(instance)
	parent := C.gtk_widget_get_parent(instance)
	if isnil(parent) {
		return
	}

	parent_height := f64(C.gtk_widget_get_allocated_height(parent))
	self_height := f64(C.gtk_widget_get_allocated_height(instance))

	self_y := if priv.valign_target == int(Align.start) {
		f64(0)
	} else {
		parent_height - self_height
	}
	new_y := self_y + offset_y + (self_height / 2)

	new_valign := if new_y > parent_height / 2 { Align.end } else { Align.start }

	if int(new_valign) != priv.valign_target {
		priv.valign_target = int(new_valign)
		C.g_object_notify_by_pspec(instance, g_key_state_overlay_pspec_valign_target)
		C.gtk_widget_queue_resize(instance)
	}
}
