@[has_globals]
module gtk

import log

// resize_overlay_linux.v - The GObject ResizeOverlay widget class for the GTK
// apprt.
//
// Translated from ghostty/src/apprt/gtk/class/resize_overlay.zig.
//
// The overlay shows the current terminal size while a surface is resizing. It
// is a small `adw.Bin` subclass wrapping a `gtk.Label`, plus three glib
// timeout/idle sources that drive the show/hide behavior:
//
//   1. `first_delay` (delay_timer): a startup delay before ANY overlay is shown.
//   2. `idler`: coalesces schedule() calls onto the next GTK idle tick so we
//      don't flicker while GTK is busy rearranging widgets mid-resize.
//   3. `duration` (timer): how long the overlay stays visible before hiding.
//
// The GObject class registration (ghostty's `gobject.ext.defineClass`), the
// blueprint template, the five properties (duration/first-delay/label/
// overlay-halign/overlay-valign), and the dispose/finalize vfuncs are
// hand-expanded onto the raw GObject/GTK C API below. The real timer/idle
// state-machine logic is translated. The class is additionally modeled as a
// plain V struct wrapping the GObject/GtkWidget ptr for callers in V.

// --- New C bindings unique to this file -----------------------------------
//
// GtkLabel + a couple of GtkWidget helpers not declared elsewhere in the
// module. All opaque handles reuse the module's `voidptr` alias convention. We
// grep-checked that none of these `fn C.` decls already exist.

// GtkLabel*.
pub type GtkLabel = voidptr

fn C.gtk_label_set_label(label GtkLabel, str &char)

// gtk_align_get_type is the registered GType of the gtk.Align enum, used to
// register the overlay-halign / overlay-valign enum properties. Declared here
// (first overlay file that needs it); other overlay files reuse it.
fn C.gtk_align_get_type() GType

// g_value_get_enum / g_value_set_enum read/write enum GValues.
fn C.g_value_get_enum(value voidptr) int

fn C.g_value_set_enum(value voidptr, v_enum int)

// glib.idleAdd equivalent (declared in split_tree_class_linux.v as
// C.g_idle_add) is reused here for the idle coalescing source.

// --- gtk.Align ------------------------------------------------------------

// Align mirrors gtk.Align. Declared here (the first overlay file that needs
// it); search_overlay_linux.v / key_state_overlay_linux.v reuse it.
pub enum Align as i32 {
	fill
	start
	end
	center
	baseline
}

// --- ResizeOverlay --------------------------------------------------------

// ResizeOverlay is the V wrapper for the `GhosttyResizeOverlay` GObject class.
// Runtime state lives in the native instance-private struct, matching the Zig
// implementation, so GLib callbacks never depend on the lifetime of this V
// wrapper.
@[heap]
pub struct ResizeOverlay {

	// The GtkWidget (adw.Bin) pointer for this instance.
pub mut:
	widget GtkWidget = unsafe { nil }

	// The label with the text (template child).
	label GtkLabel = unsafe { nil }
}

// new_resize_overlay creates a new ResizeOverlay. Mirrors
// `gobject.ext.newInstance` + the instance `init`: it builds the GObject
// (running the `.ui` template init, which binds the `label` child), reads the
// template child back into the wrapper. Instance initialization arms the
// first-delay timer from native private state.
pub fn new_resize_overlay() &ResizeOverlay {
	obj := C.g_object_new(resize_overlay_get_type(), &char(unsafe { nil }))
	priv := resize_overlay_priv(obj)
	return &ResizeOverlay{
		widget: obj
		label:  priv.label
	}
}

pub fn (mut self ResizeOverlay) ref() &ResizeOverlay {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

pub fn (mut self ResizeOverlay) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

// set_label sets the overlay label text. This does NOT show the overlay if it
// is currently hidden; callers must call `schedule`. Mirrors `setLabel`.
pub fn (mut self ResizeOverlay) set_label(label ?string) {
	if isnil(self.widget) {
		return
	}
	mut priv := resize_overlay_priv(voidptr(self.widget))
	if !isnil(priv.label_text) {
		C.g_free(priv.label_text)
		priv.label_text = unsafe { nil }
	}
	if text := label {
		priv.label_text = C.g_strdup(&char(text.str))
	}
	C.g_object_notify_by_pspec(self.widget, g_resize_overlay_pspec_label)
}

// set_duration updates how long the overlay remains visible. The native
// property machinery applies the same 250ms minimum as Ghostty.
pub fn (mut self ResizeOverlay) set_duration(duration u32) {
	if !isnil(self.widget) {
		C.g_object_set(GObject(self.widget), c'duration', duration, unsafe { nil })
	}
}

// set_position updates the alignment properties bound by the widget template.
pub fn (mut self ResizeOverlay) set_position(halign Align, valign Align) {
	if !isnil(self.widget) {
		C.g_object_set(GObject(self.widget), c'overlay-halign', int(halign), c'overlay-valign', int(valign), unsafe { nil })
	}
}

// schedule schedules the overlay to be shown on the next idle tick. To avoid
// flickering during resizes we defer the actual show to when GTK is idle.
// Mirrors `schedule`.
pub fn (mut self ResizeOverlay) schedule() {
	if isnil(self.widget) {
		return
	}
	mut priv := resize_overlay_priv(voidptr(self.widget))
	// If we have a delay timer then we're not showing anything yet, so do
	// nothing.
	if priv.delay_timer != 0 {
		return
	}

	// Wait until GTK is "idle" before updating the widget; scheduling multiple
	// idle sources would be wasteful, so bail if one is already armed.
	if priv.idler != 0 {
		return
	}
	priv.idler = C.g_idle_add(on_resize_idle, self.widget)
}

// on_resize_idle is the idle callback that actually shows/hides the overlay. Mirrors
// `onIdle`. Returns 0 (G_SOURCE_REMOVE) as in the Zig original.
fn on_resize_idle(ud voidptr) int {
	if isnil(ud) {
		return 0
	}
	mut priv := resize_overlay_priv(ud)
	// No matter what, our idler is complete with this callback.
	priv.idler = 0

	// Cancel our previous show timer no matter what.
	if priv.timer != 0 {
		if !C.g_source_remove(priv.timer) {
			log.warn('unable to remove size overlay timer')
		}
		priv.timer = 0
	}

	// If we have a label to show, show ourselves. Otherwise hide.
	if isnil(priv.label_text) {
		C.gtk_widget_set_visible(GtkWidget(ud), false)
		return 0
	}

	// Set our label and show it.
	C.gtk_label_set_label(GtkLabel(priv.label), priv.label_text)
	C.gtk_widget_set_visible(GtkWidget(ud), true)

	// Setup the new timer to hide ourselves after the duration.
	priv.timer = C.g_timeout_add(priv.duration, on_resize_timer, ud)

	return 0
}

// on_resize_timer hides the overlay when the display duration elapses. Mirrors
// `onTimer`.
fn on_resize_timer(ud voidptr) int {
	if isnil(ud) {
		return 0
	}
	mut priv := resize_overlay_priv(ud)
	priv.timer = 0
	C.gtk_widget_set_visible(GtkWidget(ud), false)
	return 0
}

// on_resize_delay_timer clears the first-delay timer once it elapses. Mirrors
// `onDelayTimer`.
fn on_resize_delay_timer(ud voidptr) int {
	if isnil(ud) {
		return 0
	}
	mut priv := resize_overlay_priv(ud)
	priv.delay_timer = 0
	return 0
}

// --- GObject class registration -------------------------------------------
// Hand-expansion of ghostty's `gobject.ext.defineClass` for
// `GhosttyResizeOverlay` (parent adw.Bin): a `.ui` template with a bound
// `label` child, five properties, and dispose/finalize vfuncs.

// Ghostty's ui/1.2/resize-overlay.blp as blueprint-compiler 0.16.0 emits it
// (without the generated-file header). Ghostty compiles it into its
// gresource and loads it with setTemplateFromResource; we load the same
// bytes directly with gtk_widget_class_set_template.
const resize_overlay_ui = '<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"/>
  <template class="GhosttyResizeOverlay" parent="AdwBin">
    <property name="visible">false</property>
    <property name="duration">750</property>
    <property name="first-delay">250</property>
    <property name="overlay-halign">center</property>
    <property name="overlay-valign">center</property>
    <child>
      <object class="WittyCanvasOverlayBin">
        <child>
          <object class="GtkLabel" id="label">
            <style>
              <class name="background"/>
              <class name="resize-overlay"/>
            </style>
            <property name="focusable">false</property>
            <property name="focus-on-click">false</property>
            <property name="justify">2</property>
            <property name="selectable">false</property>
            <property name="halign" bind-source="GhosttyResizeOverlay" bind-property="overlay-halign" bind-flags="sync-create"/>
            <property name="valign" bind-source="GhosttyResizeOverlay" bind-property="overlay-valign" bind-flags="sync-create"/>
          </object>
        </child>
      </object>
    </child>
  </template>
</interface>
'

// The C-layout private struct mirroring ghostty\'s `Private`.
struct C.GhosttyResizeOverlayPrivate {
mut:
	label       voidptr
	label_text  &char = unsafe { nil }
	duration    u32
	first_delay u32
	idler       u32
	timer       u32
	delay_timer u32
	halign      int
	valign      int
}

// The GObject type id and private-data offset, registered lazily.
__global g_resize_overlay_type = GType(0)
__global g_resize_overlay_priv_offset = int(0)

// The registered GParamSpec* pointers, captured in class_init so the wrapper
// methods can notify them.
__global g_resize_overlay_pspec_duration = &C.GParamSpec(unsafe { nil })
__global g_resize_overlay_pspec_first_delay = &C.GParamSpec(unsafe { nil })
__global g_resize_overlay_pspec_label = &C.GParamSpec(unsafe { nil })
__global g_resize_overlay_pspec_halign = &C.GParamSpec(unsafe { nil })
__global g_resize_overlay_pspec_valign = &C.GParamSpec(unsafe { nil })

// Property ids for the get/set vfunc dispatch.
const resize_overlay_prop_duration = u32(1)
const resize_overlay_prop_first_delay = u32(2)
const resize_overlay_prop_label = u32(3)
const resize_overlay_prop_halign = u32(4)
const resize_overlay_prop_valign = u32(5)

fn resize_overlay_priv(obj voidptr) &C.GhosttyResizeOverlayPrivate {
	return &C.GhosttyResizeOverlayPrivate(instance_private(obj, g_resize_overlay_priv_offset))
}

// resize_overlay_get_property implements the GObjectClass get_property vfunc.
fn resize_overlay_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	priv := resize_overlay_priv(obj)
	match property_id {
		resize_overlay_prop_duration { C.g_value_set_uint(value, priv.duration) }
		resize_overlay_prop_first_delay { C.g_value_set_uint(value, priv.first_delay) }
		resize_overlay_prop_label { C.g_value_set_string(value, priv.label_text) }
		resize_overlay_prop_halign { C.g_value_set_enum(value, priv.halign) }
		resize_overlay_prop_valign { C.g_value_set_enum(value, priv.valign) }
		else {}
	}
}

// resize_overlay_set_property implements the GObjectClass set_property vfunc.
fn resize_overlay_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	mut priv := resize_overlay_priv(obj)
	match property_id {
		resize_overlay_prop_duration {
			priv.duration = C.g_value_get_uint(value)
		}
		resize_overlay_prop_first_delay {
			priv.first_delay = C.g_value_get_uint(value)
		}
		resize_overlay_prop_label {
			if !isnil(priv.label_text) {
				C.g_free(priv.label_text)
			}
			priv.label_text = C.g_strdup(C.g_value_get_string(value))
		}
		resize_overlay_prop_halign {
			priv.halign = C.g_value_get_enum(value)
		}
		resize_overlay_prop_valign {
			priv.valign = C.g_value_get_enum(value)
		}
		else {}
	}
}

// resize_overlay_dispose removes all pending sources, disposes the template,
// and chains to the parent. Mirrors the `dispose` vfunc.
fn resize_overlay_dispose(obj voidptr) {
	mut priv := resize_overlay_priv(obj)
	if priv.idler != 0 {
		if !C.g_source_remove(priv.idler) {
			log.warn('unable to remove resize overlay idler')
		}
		priv.idler = 0
	}
	if priv.timer != 0 {
		if !C.g_source_remove(priv.timer) {
			log.warn('unable to remove resize overlay timer')
		}
		priv.timer = 0
	}
	if priv.delay_timer != 0 {
		if !C.g_source_remove(priv.delay_timer) {
			log.warn('unable to remove resize overlay delay timer')
		}
		priv.delay_timer = 0
	}
	C.gtk_widget_dispose_template(obj, g_resize_overlay_type)
	C.witty_gobject_call_parent_dispose(obj)
}

// resize_overlay_finalize frees the owned label text and chains to the parent.
// Mirrors the `finalize` vfunc.
fn resize_overlay_finalize(obj voidptr) {
	mut priv := resize_overlay_priv(obj)
	if !isnil(priv.label_text) {
		C.g_free(priv.label_text)
		priv.label_text = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

// resize_overlay_class_init installs the template, binds the `label` child,
// registers the five properties, and overrides the get/set/dispose/finalize
// vfuncs. Mirrors the ghostty `Class.init`.
fn resize_overlay_class_init(klass voidptr, class_data voidptr) {
	C.witty_gtk_canvas_overlay_register()
	C.g_type_class_adjust_private_offset(klass, &g_resize_overlay_priv_offset)
	bytes := C.g_bytes_new_static(resize_overlay_ui.str, uint(resize_overlay_ui.len))
	C.gtk_widget_class_set_template(klass, bytes)
	C.g_bytes_unref(bytes)

	// Binding: label template child into the private struct.
	label_offset := g_resize_overlay_priv_offset + int(__offsetof(C.GhosttyResizeOverlayPrivate, label))
	C.gtk_widget_class_bind_template_child_full(klass, c'label', 0, label_offset)

	// Properties.
	align_type := C.gtk_align_get_type()
	g_resize_overlay_pspec_duration = C.g_param_spec_uint(c'duration', c'duration', c'Overlay display duration', 250, u32(-1), 750, g_param_readwrite)
	g_resize_overlay_pspec_first_delay = C.g_param_spec_uint(c'first-delay', c'first-delay', c'First delay before showing', 250, u32(-1), 250, g_param_readwrite)
	g_resize_overlay_pspec_label = C.g_param_spec_string(c'label', c'label', c'The overlay label text', &char(unsafe { nil }), g_param_readwrite)
	g_resize_overlay_pspec_halign = C.g_param_spec_enum(c'overlay-halign', c'overlay-halign', c'Overlay horizontal alignment', align_type, int(Align.center), g_param_readwrite)
	g_resize_overlay_pspec_valign = C.g_param_spec_enum(c'overlay-valign', c'overlay-valign', c'Overlay vertical alignment', align_type, int(Align.center), g_param_readwrite)

	C.witty_gobject_class_set_get_property(klass, voidptr(resize_overlay_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(resize_overlay_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(resize_overlay_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(resize_overlay_finalize))

	C.g_object_class_install_property(klass, resize_overlay_prop_duration, g_resize_overlay_pspec_duration)
	C.g_object_class_install_property(klass, resize_overlay_prop_label, g_resize_overlay_pspec_label)
	C.g_object_class_install_property(klass, resize_overlay_prop_first_delay, g_resize_overlay_pspec_first_delay)
	C.g_object_class_install_property(klass, resize_overlay_prop_halign, g_resize_overlay_pspec_halign)
	C.g_object_class_install_property(klass, resize_overlay_prop_valign, g_resize_overlay_pspec_valign)
}

// resize_overlay_instance_init builds the template and arms the first-delay
// timer. Mirrors the ghostty `init` (instanceInit).
fn resize_overlay_instance_init(instance voidptr, klass voidptr) {
	C.gtk_widget_init_template(instance)
	mut priv := resize_overlay_priv(instance)
	if priv.first_delay > 0 {
		priv.delay_timer = C.g_timeout_add(priv.first_delay, on_resize_delay_timer, instance)
	}
}

// resize_overlay_get_type lazily registers the GhosttyResizeOverlay GObject
// type, parented to AdwBin, with instance-private data.
pub fn resize_overlay_get_type() GType {
	if g_resize_overlay_type == GType(0) {
		parent := C.adw_bin_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(resize_overlay_class_init)
			instance_init: voidptr(resize_overlay_instance_init)
		}
		g_resize_overlay_type = C.g_type_register_static(parent, c'GhosttyResizeOverlay', &info, 0)
		g_resize_overlay_priv_offset = C.g_type_add_instance_private(g_resize_overlay_type, sizeof(C.GhosttyResizeOverlayPrivate))
	}
	return g_resize_overlay_type
}
