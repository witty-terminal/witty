@[has_globals]
module gtk

// search_overlay_linux.v - The GObject SearchOverlay widget class for the GTK
// apprt.
//
// Translated from ghostty/src/apprt/gtk/class/search_overlay.zig.
//
// The search overlay is a draggable `adw.Bin` wrapping a `gtk.SearchEntry`. It
// tracks the active state, the total/selected match counts, and its target
// alignment (which corner of the parent it snaps to after a drag). It emits
// signals (stop-search / search-changed / next-match / previous-match) that the
// owning surface/window connects to drive the actual terminal search.
//
// The GObject class registration (ghostty's `gobject.ext.defineClass`), the
// blueprint template with its seven template callbacks + `search_entry` child,
// the seven properties, the four signals (stop-search/search-changed/
// next-match/previous-match), and dispose/finalize are hand-expanded onto the
// raw GObject/GTK C API below. The real search-state logic (active toggle,
// total/selected tracking, drag-end realignment, match-label formatting,
// Enter/Shift-Enter handling) is translated. The class is additionally modeled
// as a plain V struct wrapping the GObject/GtkWidget ptr for callers in V.
//
// Reuses: `Align` (resize_overlay_linux.v), `GtkWidget` / `GdkEvent` /
// `GtkEventControllerKey` (c_gtk_linux.v / surface_class_linux.v). The enum
// param-spec + gtk_align_get_type helpers come from resize_overlay_linux.v.

// --- New C bindings unique to this file -----------------------------------
//
// GtkSearchEntry / GtkEditable helpers + GtkWidget allocation/parent helpers
// not declared elsewhere. grep-checked to avoid redeclaration.

// GtkSearchEntry*.
pub type GtkSearchEntry = voidptr

// GtkGestureDrag*.
pub type GtkGestureDrag = voidptr

fn C.gtk_editable_select_region(editable GtkWidget, start_pos int, end_pos int)

fn C.gtk_editable_get_text(editable GtkWidget) &char

fn C.gtk_editable_set_text(editable GtkWidget, text &char)

fn C.gtk_widget_get_parent(widget GtkWidget) GtkWidget

fn C.gtk_widget_get_allocated_width(widget GtkWidget) int

fn C.gtk_widget_get_allocated_height(widget GtkWidget) int

fn C.gtk_widget_queue_resize(widget GtkWidget)

// gtk_search_entry_get_type binds the `search_entry` template child.
fn C.gtk_search_entry_get_type() GType

// g_param_spec_uint64 registers a u64 property (search-total/search-selected).
// Not declared in gobject_c_linux.v.
fn C.g_param_spec_uint64(name &char, nick &char, blurb &char, minimum u64, maximum u64, default_value u64, flags int) &C.GParamSpec

fn C.g_value_get_uint64(value voidptr) u64

fn C.g_value_set_uint64(value voidptr, v_uint64 u64)

// GDK keyvals used to detect Enter (`gdk_key_return` / `gdk_key_kp_enter`) are
// declared in key_linux.v and reused here.

// --- SearchOverlay --------------------------------------------------------

// SearchOverlay is the V wrapper for the `GhosttySearchOverlay` GObject class.
// Search state lives in the native instance-private struct, matching the Zig
// implementation and the properties used by the template bindings.
@[heap]
pub struct SearchOverlay {

	// The GtkWidget (adw.Bin) pointer for this instance.
pub mut:
	widget GtkWidget = unsafe { nil }

	// The search entry widget (template child).
	search_entry GtkSearchEntry = unsafe { nil }
}

// new_search_overlay creates a new SearchOverlay. Mirrors
// `gobject.ext.newInstance` + the instance `init`: it builds the GObject
// (running the `.ui` template init, which binds the `search_entry` child) and
// reads the template child back into the wrapper.
pub fn new_search_overlay() &SearchOverlay {
	obj := C.g_object_new(search_overlay_get_type(), &char(unsafe { nil }))
	priv := search_overlay_priv(obj)
	return &SearchOverlay{
		widget:       obj
		search_entry: priv.search_entry
	}
}

pub fn (mut self SearchOverlay) ref() &SearchOverlay {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

pub fn (mut self SearchOverlay) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

// grab_focus focuses the search entry and selects all its text. Mirrors
// `grabFocus`.
pub fn (self &SearchOverlay) grab_focus() {
	C.gtk_widget_grab_focus(self.search_entry)
	// Select all text: -1 is distance from the end, selecting everything.
	C.gtk_editable_select_region(self.search_entry, 0, -1)
}

// set_search_active sets the active status. When transitioning from inactive to
// active, it re-emits the current search text so the search is (re)run. Mirrors
// `setSearchActive`.
pub fn (mut self SearchOverlay) set_search_active(active bool) {
	if !isnil(self.widget) {
		C.g_object_set(GObject(self.widget), c'active', b2i(active), unsafe { nil })
	}
}

// get_search_active returns the active state. Mirrors `getSearchActive`.
pub fn (self &SearchOverlay) get_search_active() bool {
	if isnil(self.widget) {
		return false
	}
	return search_overlay_priv(voidptr(self.widget)).active != 0
}

// set_search_contents sets the contents of the search entry and emits a
// search-changed signal. Mirrors `setSearchContents`.
pub fn (mut self SearchOverlay) set_search_contents(content string) {
	C.gtk_editable_set_text(self.search_entry, content.str)
	self.emit_search_changed(content)
}

// set_search_total sets the total number of matches, notifying property changes
// only when the value (or its presence) actually changes. Mirrors
// `setSearchTotal`.
pub fn (mut self SearchOverlay) set_search_total(total ?uint) {
	if isnil(self.widget) {
		return
	}
	mut priv := search_overlay_priv(voidptr(self.widget))
	had_total := priv.has_search_total != 0
	same_total := if value := total {
		had_total && priv.search_total == u64(value)
	} else {
		!had_total
	}
	if same_total {
		return
	}
	if value := total {
		priv.search_total = u64(value)
		priv.has_search_total = 1
	} else {
		priv.search_total = 0
		priv.has_search_total = 0
	}
	C.g_object_notify_by_pspec(self.widget, g_search_overlay_pspec_search_total)
	now_total := total != none
	if had_total != now_total {
		C.g_object_notify_by_pspec(self.widget, g_search_overlay_pspec_has_search_total)
	}
}

// set_search_selected sets the currently selected match index. Mirrors
// `setSearchSelected`.
pub fn (mut self SearchOverlay) set_search_selected(selected ?uint) {
	if isnil(self.widget) {
		return
	}
	mut priv := search_overlay_priv(voidptr(self.widget))
	had_selected := priv.has_search_selected != 0
	same_selected := if value := selected {
		had_selected && priv.search_selected == u64(value)
	} else {
		!had_selected
	}
	if same_selected {
		return
	}
	if value := selected {
		priv.search_selected = u64(value)
		priv.has_search_selected = 1
	} else {
		priv.search_selected = 0
		priv.has_search_selected = 0
	}
	C.g_object_notify_by_pspec(self.widget, g_search_overlay_pspec_search_selected)
	now_selected := selected != none
	if had_selected != now_selected {
		C.g_object_notify_by_pspec(self.widget, g_search_overlay_pspec_has_search_selected)
	}
}

// get_search_total returns the total match count (0 if unknown). Mirrors
// `getSearchTotal`.
pub fn (self &SearchOverlay) get_search_total() u64 {
	if isnil(self.widget) {
		return 0
	}
	return search_overlay_priv(voidptr(self.widget)).search_total
}

// get_has_search_total reports whether a total is known. Mirrors
// `getHasSearchTotal`.
pub fn (self &SearchOverlay) get_has_search_total() bool {
	return !isnil(self.widget)
		&& search_overlay_priv(voidptr(self.widget)).has_search_total != 0
}

// get_search_selected returns the selected match index (0 if none). Mirrors
// `getSearchSelected`.
pub fn (self &SearchOverlay) get_search_selected() u64 {
	if isnil(self.widget) {
		return 0
	}
	return search_overlay_priv(voidptr(self.widget)).search_selected
}

// get_has_search_selected reports whether a match is selected. Mirrors
// `getHasSearchSelected`.
pub fn (self &SearchOverlay) get_has_search_selected() bool {
	return !isnil(self.widget)
		&& search_overlay_priv(voidptr(self.widget)).has_search_selected != 0
}

// match_label builds the "selected/total" label shown in the overlay. Mirrors
// `closureMatchLabel`: "0/0" when there is no total, otherwise
// "<selected+1>/<total>" (or "0/<total>" when nothing is selected yet).
pub fn (self &SearchOverlay) match_label() string {
	has_total := self.get_has_search_total()
	total := self.get_search_total()
	if !has_total || total == 0 {
		return '0/0'
	}
	numerator := if self.get_has_search_selected() {
		self.get_search_selected() + 1
	} else {
		u64(0)
	}
	return '${numerator}/${total}'
}

// --- Template callbacks ---------------------------------------------------

// entry_text returns the current text of the search entry. Helper used by the
// callbacks (Zig calls `getText()` inline).
fn (self &SearchOverlay) entry_text() string {
	c := C.gtk_editable_get_text(self.search_entry)
	if isnil(c) {
		return ''
	}
	return unsafe { cstring_to_vstring(c) }
}

// search_changed is the "search-changed" template callback on the entry.
// Mirrors `searchChanged`: re-emits the search-changed signal with the entry
// text.
pub fn (mut self SearchOverlay) search_changed() {
	self.emit_search_changed(self.entry_text())
}

// stop_search is the "stop-search" template callback. Mirrors `stopSearch`.
pub fn (self &SearchOverlay) stop_search() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'stop-search')
	}
}

// next_match is the "next-match" template callback. Mirrors `nextMatch`.
pub fn (self &SearchOverlay) next_match() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'next-match')
	}
}

// previous_match is the "previous-match" template callback. Mirrors
// `previousMatch`.
pub fn (self &SearchOverlay) previous_match() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'previous-match')
	}
}

// emit_search_changed emits the "search-changed" signal with the given text.
// Mirrors the `signals.search-changed.impl.emit(...)` calls.
fn (self &SearchOverlay) emit_search_changed(text string) {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'search-changed', text.str)
	}
}

// search_entry_key_pressed is the "key-pressed" controller callback on the
// entry. On Enter it navigates to the next match (or previous, with Shift) and
// consumes the event. Mirrors `searchEntryKeyPressed`. Returns true when the
// event is handled.
pub fn (self &SearchOverlay) search_entry_key_pressed(keyval u32, keycode u32, gtk_mods u32) bool {
	if keyval == gdk_key_return || keyval == gdk_key_kp_enter {
		mods := translate_mods(gtk_mods)
		if mods.shift() {
			self.previous_match()
		} else {
			self.next_match()
		}
		return true
	}
	return false
}

// on_drag_end is the "drag-end" template callback on the drag gesture. On drag
// end we move our halign/valign to whichever corner we crossed into (based on
// the parent midpoints). Mirrors `onDragEnd`.
pub fn (mut self SearchOverlay) on_drag_end(offset_x f64, offset_y f64) {
	if !isnil(self.widget) {
		search_on_drag_end_cb(unsafe { nil }, offset_x, offset_y, voidptr(self.widget))
	}
}

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhosttySearchOverlay` (parent adw.Bin): a `.ui` template with a bound
// `search_entry` child + seven callbacks, seven properties, four signals, and
// dispose/finalize vfuncs.

// Ghostty's ui/1.2/search-overlay.blp as blueprint-compiler 0.16.0 emits it
// (without the generated-file header). Ghostty compiles it into its
// gresource and loads it with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const search_overlay_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttySearchOverlay" parent="AdwBin">
    <property name="visible" bind-source="GhosttySearchOverlay" bind-property="active" bind-flags="sync-create"/>
    <property name="halign-target">end</property>
    <property name="valign-target">start</property>
    <property name="halign" bind-source="GhosttySearchOverlay" bind-property="halign-target" bind-flags="sync-create"/>
    <property name="valign" bind-source="GhosttySearchOverlay" bind-property="valign-target" bind-flags="sync-create"/>
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
              <class name="search-overlay"/>
            </style>
            <property name="orientation">0</property>
            <property name="spacing">6</property>
            <child>
              <object class="GtkSearchEntry" id="search_entry">
                <property name="placeholder-text" translatable="yes">Find…</property>
                <property name="width-chars">20</property>
                <property name="hexpand">true</property>
                <signal name="stop-search" handler="stop_search"/>
                <signal name="search-changed" handler="search_changed"/>
                <signal name="next-match" handler="next_match"/>
                <signal name="previous-match" handler="previous_match"/>
                <child>
                  <object class="GtkEventControllerKey">
                    <property name="propagation-phase">1</property>
                    <signal name="key-pressed" handler="search_entry_key_pressed"/>
                  </object>
                </child>
              </object>
            </child>
            <child>
              <object class="GtkLabel">
                <style>
                  <class name="dim-label"/>
                </style>
                <binding name="label">
                  <closure function="match_label_closure" type="gchararray">
                    <lookup name="has-search-selected" type="GhosttySearchOverlay">
                      <constant>GhosttySearchOverlay</constant>
                    </lookup>
                    <lookup name="search-selected" type="GhosttySearchOverlay">
                      <constant>GhosttySearchOverlay</constant>
                    </lookup>
                    <lookup name="has-search-total" type="GhosttySearchOverlay">
                      <constant>GhosttySearchOverlay</constant>
                    </lookup>
                    <lookup name="search-total" type="GhosttySearchOverlay">
                      <constant>GhosttySearchOverlay</constant>
                    </lookup>
                  </closure>
                </binding>
                <property name="width-chars">6</property>
                <property name="xalign">1</property>
              </object>
            </child>
            <child>
              <object class="GtkBox" id="button_box">
                <property name="orientation">0</property>
                <property name="spacing">1</property>
                <style>
                  <class name="linked"/>
                </style>
                <child>
                  <object class="GtkButton" id="prev_button">
                    <property name="icon-name">go-up-symbolic</property>
                    <property name="tooltip-text" translatable="yes">Previous Match</property>
                    <signal name="clicked" handler="next_match"/>
                    <property name="cursor">
                      <object class="GdkCursor">
                        <property name="name">pointer</property>
                      </object>
                    </property>
                  </object>
                </child>
                <child>
                  <object class="GtkButton" id="next_button">
                    <property name="icon-name">go-down-symbolic</property>
                    <property name="tooltip-text" translatable="yes">Next Match</property>
                    <signal name="clicked" handler="previous_match"/>
                    <property name="cursor">
                      <object class="GdkCursor">
                        <property name="name">pointer</property>
                      </object>
                    </property>
                  </object>
                </child>
              </object>
            </child>
            <child>
              <object class="GtkButton" id="close_button">
                <property name="icon-name">window-close-symbolic</property>
                <property name="tooltip-text" translatable="yes">Close</property>
                <signal name="clicked" handler="stop_search"/>
                <property name="cursor">
                  <object class="GdkCursor">
                    <property name="name">pointer</property>
                  </object>
                </property>
              </object>
            </child>
          </object>
        </child>
      </object>
    </child>
  </template>
</interface>
'

// The C-layout private struct mirroring ghostty\'s `Private`. The optional
// counts are stored as value + presence flag; the alignment targets and active
// flag back the corresponding properties; search_entry is the template child.
struct C.GhosttySearchOverlayPrivate {
mut:
	search_entry        voidptr
	active              int
	search_total        u64
	has_search_total    int
	search_selected     u64
	has_search_selected int
	halign_target       int
	valign_target       int
}

// The GObject type id and private-data offset, registered lazily.
__global g_search_overlay_type = GType(0)
__global g_search_overlay_priv_offset = int(0)

// Registered GParamSpec* pointers, captured in class_init for notify.
__global g_search_overlay_pspec_active = &C.GParamSpec(unsafe { nil })
__global g_search_overlay_pspec_search_total = &C.GParamSpec(unsafe { nil })
__global g_search_overlay_pspec_has_search_total = &C.GParamSpec(unsafe { nil })
__global g_search_overlay_pspec_search_selected = &C.GParamSpec(unsafe { nil })
__global g_search_overlay_pspec_has_search_selected = &C.GParamSpec(unsafe { nil })
__global g_search_overlay_pspec_halign_target = &C.GParamSpec(unsafe { nil })
__global g_search_overlay_pspec_valign_target = &C.GParamSpec(unsafe { nil })

// Property ids for the get/set vfunc dispatch.
const search_prop_active = u32(1)
const search_prop_search_total = u32(2)
const search_prop_has_search_total = u32(3)
const search_prop_search_selected = u32(4)
const search_prop_has_search_selected = u32(5)
const search_prop_halign_target = u32(6)
const search_prop_valign_target = u32(7)

fn search_overlay_priv(obj voidptr) &C.GhosttySearchOverlayPrivate {
	return &C.GhosttySearchOverlayPrivate(instance_private(obj, g_search_overlay_priv_offset))
}

// search_overlay_get_property implements the GObjectClass get_property vfunc.
fn search_overlay_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	priv := search_overlay_priv(obj)
	match property_id {
		search_prop_active { C.g_value_set_boolean(value, priv.active) }
		search_prop_search_total { C.g_value_set_uint64(value, priv.search_total) }
		search_prop_has_search_total { C.g_value_set_boolean(value, priv.has_search_total) }
		search_prop_search_selected { C.g_value_set_uint64(value, priv.search_selected) }
		search_prop_has_search_selected { C.g_value_set_boolean(value, priv.has_search_selected) }
		search_prop_halign_target { C.g_value_set_enum(value, priv.halign_target) }
		search_prop_valign_target { C.g_value_set_enum(value, priv.valign_target) }
		else {}
	}
}

// search_overlay_set_property implements the GObjectClass set_property vfunc.
fn search_overlay_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	mut priv := search_overlay_priv(obj)
	match property_id {
		search_prop_active {
			active := C.g_value_get_boolean(value)
			if priv.active == 0 && active != 0 {
				text := C.gtk_editable_get_text(priv.search_entry)
				C.g_signal_emit_by_name(obj, c'search-changed', text)
			}
			priv.active = active
		}
		search_prop_halign_target {
			priv.halign_target = C.g_value_get_enum(value)
		}
		search_prop_valign_target {
			priv.valign_target = C.g_value_get_enum(value)
		}
		else {}
	}
}

// search_overlay_dispose disposes the template and chains up. Mirrors `dispose`.
fn search_overlay_dispose(obj voidptr) {
	C.gtk_widget_dispose_template(obj, g_search_overlay_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// search_overlay_finalize chains up. Mirrors `finalize`.
fn search_overlay_finalize(obj voidptr) {
	C.witty_gobject_call_parent_finalize(obj)
}

// --- Template-callback trampolines ----------------------------------------
// The signal/closure callbacks bound via bindTemplateCallback. The signal-
// emitting ones (stop_search/next_match/previous_match/search_changed) receive
// the emitting widget + the overlay instance as user_data and emit the overlay
// signal directly; match_label_closure is a pure function of its args.
fn search_stop_search_cb(widget voidptr, instance voidptr) {
	if !isnil(instance) {
		C.g_signal_emit_by_name(instance, c'stop-search')
	}
}

fn search_next_match_cb(widget voidptr, instance voidptr) {
	if !isnil(instance) {
		C.g_signal_emit_by_name(instance, c'next-match')
	}
}

fn search_previous_match_cb(widget voidptr, instance voidptr) {
	if !isnil(instance) {
		C.g_signal_emit_by_name(instance, c'previous-match')
	}
}

fn search_changed_cb(entry voidptr, instance voidptr) {
	if isnil(instance) {
		return
	}
	text := C.gtk_editable_get_text(entry)
	C.g_signal_emit_by_name(instance, c'search-changed', text)
}

// search_match_label_closure_cb builds the "selected/total" label. Mirrors
// `closureMatchLabel`.
fn search_match_label_closure_cb(instance voidptr, has_selected int, selected u64, has_total int, total u64) &char {
	if has_total == 0 || total == 0 {
		return C.g_strdup(c'0/0')
	}
	numerator := if has_selected != 0 { selected + 1 } else { u64(0) }
	label := '${numerator}/${total}'
	return C.g_strdup(label.str)
}

// search_entry_key_pressed_cb is the entry's key controller callback. On Enter
// it navigates next/previous (Shift) and consumes the event. Mirrors
// `searchEntryKeyPressed`; operates on the overlay instance directly.
fn search_entry_key_pressed_cb(controller voidptr, keyval u32, keycode u32, gtk_mods u32, instance voidptr) int {
	if keyval == gdk_key_return || keyval == gdk_key_kp_enter {
		mods := translate_mods(gtk_mods)
		if mods.shift() {
			if !isnil(instance) {
				C.g_signal_emit_by_name(instance, c'previous-match')
			}
		} else {
			if !isnil(instance) {
				C.g_signal_emit_by_name(instance, c'next-match')
			}
		}
		return 1
	}
	return 0
}

// search_on_drag_end_cb is the drag gesture's "drag-end" callback. It realigns
// the overlay to whichever corner it crossed into. Mirrors `onDragEnd`;
// operates directly on the GObject instance/private.
fn search_on_drag_end_cb(gesture voidptr, offset_x f64, offset_y f64, instance voidptr) {
	if isnil(instance) {
		return
	}
	mut priv := search_overlay_priv(instance)
	parent := C.gtk_widget_get_parent(instance)
	if isnil(parent) {
		return
	}

	parent_width := f64(C.gtk_widget_get_allocated_width(parent))
	parent_height := f64(C.gtk_widget_get_allocated_height(parent))
	self_width := f64(C.gtk_widget_get_allocated_width(instance))
	self_height := f64(C.gtk_widget_get_allocated_height(instance))

	self_x := if priv.halign_target == int(Align.start) {
		f64(0)
	} else {
		parent_width - self_width
	}
	self_y := if priv.valign_target == int(Align.start) {
		f64(0)
	} else {
		parent_height - self_height
	}

	new_x := self_x + offset_x + (self_width / 2)
	new_y := self_y + offset_y + (self_height / 2)

	new_halign := if new_x > parent_width / 2 { Align.end } else { Align.start }
	new_valign := if new_y > parent_height / 2 { Align.end } else { Align.start }

	mut changed := false
	if int(new_halign) != priv.halign_target {
		priv.halign_target = int(new_halign)
		C.g_object_notify_by_pspec(instance, g_search_overlay_pspec_halign_target)
		changed = true
	}
	if int(new_valign) != priv.valign_target {
		priv.valign_target = int(new_valign)
		C.g_object_notify_by_pspec(instance, g_search_overlay_pspec_valign_target)
		changed = true
	}

	if changed {
		C.gtk_widget_queue_resize(instance)
	}
}

// search_overlay_class_init installs the template, binds the `search_entry`
// child, wires the seven callbacks, registers the seven properties + four
// signals, and overrides the get/set/dispose/finalize vfuncs. Mirrors the
// ghostty `Class.init`.
fn search_overlay_class_init(klass voidptr, class_data voidptr) {
	C.witty_gtk_canvas_overlay_register()
	C.g_type_class_adjust_private_offset(klass, &g_search_overlay_priv_offset)
	bytes := C.g_bytes_new_static(search_overlay_ui.str, uint(search_overlay_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)

	// Binding: search_entry template child into the private struct.
	entry_offset := g_search_overlay_priv_offset + int(__offsetof(C.GhosttySearchOverlayPrivate, search_entry))
	C.gtk_widget_class_bind_template_child_full(klass, c'search_entry', 0, entry_offset)

	// Template callbacks.
	C.gtk_widget_class_bind_template_callback_full(klass, c'stop_search', voidptr(search_stop_search_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'search_changed', voidptr(search_changed_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'match_label_closure', voidptr(search_match_label_closure_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'next_match', voidptr(search_next_match_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'previous_match', voidptr(search_previous_match_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'search_entry_key_pressed', voidptr(search_entry_key_pressed_cb))
	C.gtk_widget_class_bind_template_callback_full(klass, c'on_drag_end', voidptr(search_on_drag_end_cb))

	// Properties.
	max_u64 := u64(-1)
	align_type := C.gtk_align_get_type()
	g_search_overlay_pspec_active = C.g_param_spec_boolean(c'active', c'active', c'Whether search is active', 0, g_param_readwrite)
	g_search_overlay_pspec_search_total = C.g_param_spec_uint64(c'search-total', c'search-total', c'Total number of matches', 0, max_u64, 0, g_param_readable)
	g_search_overlay_pspec_has_search_total = C.g_param_spec_boolean(c'has-search-total', c'has-search-total', c'Whether a total is known', 0, g_param_readable)
	g_search_overlay_pspec_search_selected = C.g_param_spec_uint64(c'search-selected', c'search-selected', c'Selected match index', 0, max_u64, 0, g_param_readable)
	g_search_overlay_pspec_has_search_selected = C.g_param_spec_boolean(c'has-search-selected', c'has-search-selected', c'Whether a match is selected', 0, g_param_readable)
	g_search_overlay_pspec_halign_target = C.g_param_spec_enum(c'halign-target', c'halign-target', c'Target horizontal alignment', align_type, int(Align.end), g_param_readwrite)
	g_search_overlay_pspec_valign_target = C.g_param_spec_enum(c'valign-target', c'valign-target', c'Target vertical alignment', align_type, int(Align.start), g_param_readwrite)

	C.witty_gobject_class_set_get_property(klass, voidptr(search_overlay_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(search_overlay_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(search_overlay_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(search_overlay_finalize))

	C.g_object_class_install_property(klass, search_prop_active, g_search_overlay_pspec_active)
	C.g_object_class_install_property(klass, search_prop_search_total, g_search_overlay_pspec_search_total)
	C.g_object_class_install_property(klass, search_prop_has_search_total, g_search_overlay_pspec_has_search_total)
	C.g_object_class_install_property(klass, search_prop_search_selected, g_search_overlay_pspec_search_selected)
	C.g_object_class_install_property(klass, search_prop_has_search_selected, g_search_overlay_pspec_has_search_selected)
	C.g_object_class_install_property(klass, search_prop_halign_target, g_search_overlay_pspec_halign_target)
	C.g_object_class_install_property(klass, search_prop_valign_target, g_search_overlay_pspec_valign_target)

	// Signals: stop-search / next-match / previous-match (void), search-changed
	// (one string param).
	self_type := g_search_overlay_type
	C.g_signal_new(c'stop-search', self_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
	mut string_param := g_type_string
	C.g_signal_new(c'search-changed', self_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 1, string_param)
	C.g_signal_new(c'next-match', self_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
	C.g_signal_new(c'previous-match', self_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
}

fn search_overlay_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
}

// search_overlay_get_type lazily registers the GhosttySearchOverlay GObject
// type, parented to AdwBin, with instance-private data.
pub fn search_overlay_get_type() GType {
	if g_search_overlay_type == GType(0) {
		parent := C.adw_bin_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(search_overlay_class_init)
			instance_init: voidptr(search_overlay_instance_init)
		}
		g_search_overlay_type = C.g_type_register_static(parent, c'GhosttySearchOverlay', &info, 0)
		g_search_overlay_priv_offset = C.g_type_add_instance_private(g_search_overlay_type, sizeof(C.GhosttySearchOverlayPrivate))
	}
	return g_search_overlay_type
}
