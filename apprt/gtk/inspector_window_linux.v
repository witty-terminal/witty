@[has_globals]
module gtk

import inspector as inspectorpkg
import log

// GTK terminal inspector translated from:
// - ghostty/src/apprt/gtk/class/inspector_widget.zig
// - ghostty/src/apprt/gtk/class/inspector_window.zig
//
// The source uses GObject subclasses and blueprint templates. Witty's GTK
// runtime expands those templates programmatically, while preserving the same
// ownership and activation lifecycle.

__global g_inspector_widget_type = GType(0)
__global g_inspector_widget_parent = voidptr(unsafe { nil })

fn inspector_widget_class_init(klass voidptr, _ voidptr) {
	g_inspector_widget_parent = C.g_type_class_peek_parent(klass)
	C.witty_imgui_class_set_setup(klass, voidptr(inspector_native_setup))
	C.witty_imgui_class_set_render(klass, voidptr(inspector_native_render))
	C.witty_gobject_class_set_get_property(klass, voidptr(inspector_native_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(inspector_native_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(inspector_native_dispose))
	C.g_object_class_install_property(klass, 1, C.g_param_spec_object(c'surface', c'surface', c'surface', terminal_surface_get_type(), g_param_readwrite))
}

pub fn inspector_widget_get_type() GType {
	if g_inspector_widget_type == GType(0) {
		parent := imgui_widget_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{class_size: u16(query.class_size), instance_size: u16(query.instance_size), class_init: voidptr(inspector_widget_class_init), instance_init: voidptr(inspector_native_instance_init)}
		g_inspector_widget_type = C.g_type_register_static(parent, c'GhosttyInspectorWidget', &info, 0)
	}
	return g_inspector_widget_type
}

fn inspector_native_instance_init(obj voidptr, _ voidptr) {
	mut imgui := imgui_native_wrapper(obj) or { panic('native inspector parent did not initialize') }
	self := &InspectorWidget{imgui: imgui}
	imgui.user_data = voidptr(self)
	imgui.setup_fn = inspector_widget_setup_cb
	imgui.render_fn = inspector_widget_render_cb
	C.gtk_widget_add_css_class(GtkWidget(obj), c'inspector')
}

fn inspector_native_setup(obj voidptr) {
	self := imgui_native_wrapper(obj) or { return }
	if self.setup_fn != unsafe { nil } { self.setup_fn(self.user_data) }
}
fn inspector_native_render(obj voidptr) {
	self := imgui_native_wrapper(obj) or { return }
	if self.render_fn != unsafe { nil } { self.render_fn(self.user_data) }
}
fn inspector_native_get_property(obj voidptr, id u32, value voidptr, _ voidptr) {
	if id != 1 { return }
	imgui := imgui_native_wrapper(obj) or { C.g_value_set_object(value, unsafe { nil }); return }
	self := unsafe { &InspectorWidget(imgui.user_data) }
	// V 0.5.2 emits `if` expressions inside C call arguments as statements.
	mut surface := unsafe { nil }
	if !isnil(self.surface) { surface = voidptr(self.surface.widget) }
	C.g_value_set_object(value, surface)
}
fn inspector_native_set_property(obj voidptr, id u32, value voidptr, _ voidptr) {
	if id != 1 { return }
	imgui := imgui_native_wrapper(obj) or { return }
	mut self := unsafe { &InspectorWidget(imgui.user_data) }
	object := C.g_value_get_object(value)
	if isnil(object) { self.set_surface(none) } else {
		priv := terminal_surface_priv(object)
		if !isnil(priv.wrapper) { self.set_surface(unsafe { &SurfaceWidget(priv.wrapper) }) }
	}
}
fn inspector_native_dispose(obj voidptr) {
	if imgui := imgui_native_wrapper(obj) {
		mut self := unsafe { &InspectorWidget(imgui.user_data) }
		self.set_surface(none)
	}
	C.witty_imgui_parent_dispose(g_inspector_widget_parent, obj)
}

@[heap]
pub struct InspectorWidget {
mut:
	imgui   &ImguiWidget     = unsafe { nil }
	surface &SurfaceWidget   = unsafe { nil }
	owner   &InspectorWindow = unsafe { nil }
}

@[heap]
pub struct InspectorWindow {
mut:
	obj       AdwApplicationWindow = unsafe { nil }
	inspector &InspectorWidget     = unsafe { nil }
}

fn new_inspector_widget(surface &SurfaceWidget) &InspectorWidget {
	imgui := new_imgui_widget_type(inspector_widget_get_type(), unsafe { nil }, unsafe { nil }, unsafe { nil })
	mut self := unsafe { &InspectorWidget(imgui.user_data) }
	self.set_surface(surface)
	return self
}

pub fn (mut self InspectorWidget) ref() &InspectorWidget {
	if !isnil(self.imgui) {
		self.imgui.ref()
	}
	return self
}

pub fn (mut self InspectorWidget) ref_sink() &InspectorWidget {
	if !isnil(self.imgui) {
		self.imgui.ref_sink()
	}
	return self
}

pub fn (mut self InspectorWidget) unref() {
	if !isnil(self.imgui) {
		self.imgui.unref()
	}
}

// get_surface returns the weakly held inspected surface, if it is still live.
// Mirrors `InspectorWidget.getSurface`.
pub fn (self &InspectorWidget) get_surface() ?&SurfaceWidget {
	if isnil(self.surface) {
		return none
	}
	return self.surface
}

// set_surface changes the weak inspected surface. Inspector activation errors
// are diagnosed and absorbed at this source boundary.
pub fn (mut self InspectorWidget) set_surface(surface_ ?&SurfaceWidget) {
	if new_surface := surface_ {
		if self.surface == new_surface {
			return
		}
	} else if isnil(self.surface) {
		return
	}
	if !isnil(self.surface) {
		mut old := unsafe { self.surface }
		self.surface = unsafe { nil }
		if !isnil(old.widget) {
			C.g_object_weak_unref(GObject(old.widget), voidptr(inspector_surface_weak_notify), voidptr(self))
		}
		if old.has_core() {
			mut core_surface := old.core_surface
			core_surface.deactivate_inspector()
		}
		if !isnil(self.owner) && old.inspector == self.owner {
			old.inspector = unsafe { nil }
		}
	}

	surface := surface_ or { return }
	if !surface.has_core() {
		return
	}
	mut core_surface := surface.core_surface
	core_surface.activate_inspector() or {
		log.warn('failed to activate inspector err=${err}')
		return
	}
	C.g_object_weak_ref(GObject(surface.widget), voidptr(inspector_surface_weak_notify), voidptr(self))
	self.surface = surface
	self.imgui.queue_render()
}

fn (mut self InspectorWidget) clear_surface_from_weak(surface_obj GObject) {
	if isnil(self.surface) || GObject(self.surface.widget) != surface_obj {
		return
	}
	mut old := unsafe { self.surface }
	self.surface = unsafe { nil }
	if old.has_core() {
		mut core_surface := old.core_surface
		core_surface.deactivate_inspector()
	}
	old.inspector = unsafe { nil }
	if !isnil(self.owner) {
		self.owner.destroy_window()
	}
}

pub fn (self &InspectorWidget) queue_render() {
	if !isnil(self.imgui) {
		self.imgui.queue_render()
	}
}

fn (mut self InspectorWidget) deinit() {
	self.set_surface(none)
	if !isnil(self.imgui) {
		mut imgui := unsafe { self.imgui }
		imgui.deinit()
		self.imgui = unsafe { nil }
	}
	self.owner = unsafe { nil }
}

fn inspector_widget_setup_cb(data voidptr) {
	if isnil(data) {
		return
	}
	self := unsafe { &InspectorWidget(data) }
	if !isnil(self.imgui) {
		inspectorpkg.setup(self.imgui.context)
	}
}

fn inspector_widget_render_cb(data voidptr) {
	if isnil(data) {
		return
	}
	self := unsafe { &InspectorWidget(data) }
	if isnil(self.surface) || !self.surface.has_core() || isnil(self.imgui) {
		return
	}
	mut core_surface := self.surface.core_surface
	core_surface.render_inspector(self.imgui.context.handle)
}

fn inspector_surface_weak_notify(data voidptr, object GObject) {
	if !isnil(data) {
		mut self := unsafe { &InspectorWidget(data) }
		self.clear_surface_from_weak(object)
	}
}

pub fn new_inspector_window(mut surface SurfaceWidget) &InspectorWindow {
	obj := AdwApplicationWindow(C.g_object_new(C.adw_application_window_get_type(), c'application', surface.app.obj, &char(unsafe { nil })))
	assert !isnil(obj)
	mut self := &InspectorWindow{
		obj: obj
	}
	mut inspector := new_inspector_widget(surface)
	self.inspector = inspector
	inspector.owner = self
	surface.inspector = self

	C.gtk_window_set_title(GtkWindow(obj), c'Witty: Terminal Inspector')
	C.gtk_window_set_icon_name(GtkWindow(obj), &char(application_id.str))
	C.gtk_window_set_default_size(GtkWindow(obj), 1000, 600)
	C.gtk_widget_add_css_class(GtkWidget(obj), c'inspector')

	toolbar := C.adw_toolbar_view_new()
	header := C.adw_header_bar_new()
	title := C.adw_window_title_new(c'Witty: Terminal Inspector', c'')
	C.adw_header_bar_set_title_widget(header, title)
	C.adw_toolbar_view_add_top_bar(toolbar, header)

	content := C.gtk_box_new(1, 0)
	C.gtk_widget_set_hexpand(content, 1)
	C.gtk_widget_set_vexpand(content, 1)
	debug_warning := GtkWidget(C.g_object_new(debug_warning_get_type(), &char(unsafe { nil })))
	C.gtk_widget_set_visible(debug_warning, $if debug { 1 } $else { 0 })
	C.gtk_box_append(content, debug_warning)
	C.gtk_box_append(content, inspector.imgui.as_widget())
	C.adw_toolbar_view_set_content(toolbar, content)
	C.adw_application_window_set_content(obj, GtkWidget(toolbar))
	C.g_object_weak_ref(GObject(obj), voidptr(inspector_window_weak_notify), voidptr(self))
	return self
}

pub fn (mut self InspectorWindow) ref() &InspectorWindow {
	if !isnil(self.obj) {
		object_ref(GObject(self.obj))
	}
	return self
}

pub fn (mut self InspectorWindow) ref_sink() &InspectorWindow {
	if !isnil(self.obj) {
		C.g_object_ref_sink(GObject(self.obj))
	}
	return self
}

pub fn (mut self InspectorWindow) unref() {
	if !isnil(self.obj) {
		object_unref(GObject(self.obj))
	}
}

pub fn (self &InspectorWindow) present() {
	if !isnil(self.obj) {
		C.gtk_window_present(GtkWindow(self.obj))
	}
}

pub fn (self &InspectorWindow) queue_render() {
	if !isnil(self.inspector) {
		self.inspector.queue_render()
	}
}

pub fn (mut self InspectorWindow) close() {
	if !isnil(self.inspector) {
		self.inspector.set_surface(none)
	}
	self.destroy_window()
}

fn (self &InspectorWindow) destroy_window() {
	if !isnil(self.obj) {
		C.gtk_window_destroy(GtkWindow(self.obj))
	}
}

fn inspector_window_weak_notify(data voidptr, object GObject) {
	_ = object
	if isnil(data) {
		return
	}
	mut self := unsafe { &InspectorWindow(data) }
	self.obj = unsafe { nil }
	if !isnil(self.inspector) {
		mut inspector := unsafe { self.inspector }
		inspector.deinit()
		self.inspector = unsafe { nil }
	}
}
