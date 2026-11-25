@[has_globals]
module gtk

// Translated GhosttyImguiWidget native subclass and virtual-method contract.
// The GL/input tree below expands the corresponding source blueprint.
import cimgui
import input
import log
import renderer
import time

#include "imgui_native_shims.h"

fn C.witty_imgui_class_size() uint
fn C.witty_imgui_class_set_setup(voidptr, voidptr)
fn C.witty_imgui_class_set_render(voidptr, voidptr)
fn C.witty_imgui_call_setup(voidptr)
fn C.witty_imgui_call_render(voidptr)
fn C.witty_imgui_parent_dispose(voidptr, voidptr)
fn C.glClearColor(f32, f32, f32, f32)
fn C.glClear(u32)

__global g_imgui_widget_type = GType(0)
__global g_imgui_widget_parent = voidptr(unsafe { nil })
const imgui_widget_wrapper_key = 'ghostty-imgui-widget-wrapper'
const imgui_background = [f32(0x28) / 255, f32(0x2c) / 255, f32(0x34) / 255, f32(1)]!

fn imgui_widget_class_init(klass voidptr, _ voidptr) {
	g_imgui_widget_parent = C.g_type_class_peek_parent(klass)
	C.witty_imgui_class_set_setup(klass, voidptr(imgui_default_setup))
	C.witty_imgui_class_set_render(klass, voidptr(imgui_default_render))
	C.witty_gobject_class_set_dispose(klass, voidptr(imgui_native_dispose))
}

fn imgui_native_instance_init(instance voidptr, _ voidptr) {
	_ = new_imgui_widget_instance(GtkWidget(instance))
}

fn imgui_default_setup(_ voidptr) {
	log.warn('default Dear ImGui setup called, this is a bug.')
}

fn imgui_default_render(_ voidptr) {
	log.warn('default Dear ImGui render called, this is a bug.')
}

fn imgui_native_dispose(obj voidptr) {
	// Parent disposal unrealizes the GLArea before its context is destroyed.
	C.witty_imgui_parent_dispose(g_imgui_widget_parent, obj)
	wrapper := native_wrapper_get(GObject(obj), imgui_widget_wrapper_key)
	if !isnil(wrapper) {
		mut self := unsafe { &ImguiWidget(wrapper) }
		self.deinit()
		native_wrapper_set(GObject(obj), imgui_widget_wrapper_key, unsafe { nil })
	}
}

pub fn imgui_widget_get_type() GType {
	if g_imgui_widget_type == GType(0) {
		parent := C.adw_bin_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(C.witty_imgui_class_size())
			instance_size: u16(query.instance_size)
			class_init:    voidptr(imgui_widget_class_init)
			instance_init: voidptr(imgui_native_instance_init)
		}
		g_imgui_widget_type = C.g_type_register_static(parent, c'GhosttyImguiWidget', &info, 0)
	}
	return g_imgui_widget_type
}

fn imgui_native_wrapper(obj voidptr) ?&ImguiWidget {
	wrapper := native_wrapper_get(GObject(obj), imgui_widget_wrapper_key)
	if isnil(wrapper) { return none }
	return unsafe { &ImguiWidget(wrapper) }
}

pub type ImguiWidgetCallback = fn (voidptr)

@[heap]
pub struct ImguiWidget {
mut:
	widget           GtkWidget    = unsafe { nil }
	gl_area          GtkGLArea    = unsafe { nil }
	im_context       GtkIMContext = unsafe { nil }
	context          cimgui.Context
	context_ready    bool
	opengl_ready     bool
	gpu              renderer.GGInspectorGL
	tick_callback_id u32
	last_render_ns   i64
	previous_ns      i64
	setup_fn         ImguiWidgetCallback = unsafe { nil }
	render_fn        ImguiWidgetCallback = unsafe { nil }
	user_data        voidptr             = unsafe { nil }
}

fn C.gtk_widget_add_tick_callback(widget GtkWidget, callback voidptr, user_data voidptr, notify voidptr) u32

fn C.gtk_widget_remove_tick_callback(widget GtkWidget, id u32)

fn C.g_object_weak_unref(object GObject, notify voidptr, data voidptr)

pub fn new_imgui_widget(setup_fn ImguiWidgetCallback, render_fn ImguiWidgetCallback, user_data voidptr) &ImguiWidget {
	return new_imgui_widget_type(imgui_widget_get_type(), setup_fn, render_fn, user_data)
}

fn new_imgui_widget_type(native_type GType, setup_fn ImguiWidgetCallback, render_fn ImguiWidgetCallback, user_data voidptr) &ImguiWidget {
	widget := GtkWidget(C.g_object_new(native_type, &char(unsafe { nil })))
	mut self := imgui_native_wrapper(widget) or {
		panic('native ImGui instance did not initialize')
	}
	if setup_fn != unsafe { nil } { self.setup_fn = setup_fn }
	if render_fn != unsafe { nil } { self.render_fn = render_fn }
	if !isnil(user_data) { self.user_data = user_data }
	return self
}

fn new_imgui_widget_instance(widget GtkWidget) &ImguiWidget {
	gl_area := C.gtk_gl_area_new()
	C.gtk_widget_add_css_class(widget, c'imgui')
	C.gtk_widget_set_hexpand(widget, 1)
	C.gtk_widget_set_vexpand(widget, 1)
	C.gtk_widget_set_hexpand(GtkWidget(gl_area), 1)
	C.gtk_widget_set_vexpand(GtkWidget(gl_area), 1)
	C.gtk_widget_set_focusable(GtkWidget(gl_area), 1)
	C.gtk_widget_set_focus_on_click(GtkWidget(gl_area), 1)
	C.gtk_gl_area_set_has_stencil_buffer(gl_area, 0)
	C.gtk_gl_area_set_has_depth_buffer(gl_area, 0)
	C.gtk_gl_area_set_allowed_apis(gl_area, gdk_gl_api_gl)
	C.adw_bin_set_child(AdwBin(widget), GtkWidget(gl_area))

	mut self := &ImguiWidget{
		widget:     widget
		gl_area:    gl_area
		im_context: C.gtk_im_multicontext_new()
	}
	native_wrapper_set(GObject(widget), imgui_widget_wrapper_key, voidptr(self))
	C.g_signal_connect_data(gl_area, c'realize', GCallback(voidptr(imgui_glarea_realize_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(gl_area, c'unrealize', GCallback(voidptr(imgui_glarea_unrealize_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(gl_area, c'resize', GCallback(voidptr(imgui_glarea_resize_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(gl_area, c'render', GCallback(voidptr(imgui_glarea_render_cb)),
		voidptr(self), unsafe { nil }, 0)

	focus := C.gtk_event_controller_focus_new()
	C.g_signal_connect_data(focus, c'enter', GCallback(voidptr(imgui_focus_enter_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(focus, c'leave', GCallback(voidptr(imgui_focus_leave_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.gtk_widget_add_controller(GtkWidget(gl_area), focus)

	key := C.gtk_event_controller_key_new()
	C.g_signal_connect_data(key, c'key-pressed', GCallback(voidptr(imgui_key_pressed_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(key, c'key-released', GCallback(voidptr(imgui_key_released_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.gtk_widget_add_controller(GtkWidget(gl_area), key)

	click := C.gtk_gesture_click_new()
	C.gtk_gesture_single_set_button(click, 0)
	C.g_signal_connect_data(click, c'pressed', GCallback(voidptr(imgui_mouse_pressed_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(click, c'released', GCallback(voidptr(imgui_mouse_released_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.gtk_widget_add_controller(GtkWidget(gl_area), click)

	motion := C.gtk_event_controller_motion_new()
	C.g_signal_connect_data(motion, c'motion', GCallback(voidptr(imgui_mouse_motion_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.gtk_widget_add_controller(GtkWidget(gl_area), motion)

	scroll :=
		C.gtk_event_controller_scroll_new(gtk_event_controller_scroll_vertical | gtk_event_controller_scroll_horizontal)
	C.g_signal_connect_data(scroll, c'scroll', GCallback(voidptr(imgui_mouse_scroll_cb)),
		voidptr(self), unsafe { nil }, 0)
	C.gtk_widget_add_controller(GtkWidget(gl_area), scroll)

	C.g_signal_connect_data(self.im_context, c'commit', GCallback(voidptr(imgui_im_commit_cb)),
		voidptr(self), unsafe { nil }, 0)
	return self
}

pub fn (self &ImguiWidget) as_widget() GtkWidget {
	return self.widget
}

pub fn (mut self ImguiWidget) ref() &ImguiWidget {
	if !isnil(self.widget) {
		object_ref(GObject(self.widget))
	}
	return self
}

pub fn (mut self ImguiWidget) ref_sink() &ImguiWidget {
	if !isnil(self.widget) {
		C.g_object_ref_sink(GObject(self.widget))
	}
	return self
}

pub fn (mut self ImguiWidget) unref() {
	if !isnil(self.widget) {
		object_unref(GObject(self.widget))
	}
}

pub fn (self &ImguiWidget) queue_render() {
	if !isnil(self.gl_area) {
		C.gtk_gl_area_queue_render(self.gl_area)
	}
}

// setup calls the widget's setup virtual method. The correct Dear ImGui
// context is current when this is invoked by realize.
pub fn (self &ImguiWidget) setup() {
	if !isnil(self.widget) { C.witty_imgui_call_setup(self.widget) }
}

pub fn (self &ImguiWidget) render() {
	if !isnil(self.widget) { C.witty_imgui_call_render(self.widget) }
}

// set_current_context preserves the source boundary even though the cimgui V
// wrapper makes the context passed to each operation current internally.
fn (self &ImguiWidget) set_current_context() bool {
	if !self.opengl_ready {
		log.warn('Dear ImGui context not initialized')
		return false
	}
	return true
}

fn (mut self ImguiWidget) realize() {
	assert !self.opengl_ready, 'Dear ImGui OpenGL backend already initialized'
	C.gtk_gl_area_make_current(self.gl_area)
	gl_error := C.gtk_gl_area_get_error(self.gl_area)
	if !isnil(gl_error) {
		log.warn('GLArea for Dear ImGui widget failed to realize: ${error_message(gl_error)}')
		return
	}
	first := !self.context_ready
	if first {
		self.context = cimgui.Context.create() or {
			log.warn('unable to initialize Dear ImGui context')
			return
		}
		self.context.set_backend_platform(.gtk)
	}
	if !self.context.opengl_init() {
		if first {
			self.context.destroy()
			self.context = cimgui.Context{}
		}
		log.warn('unable to initialize Dear ImGui OpenGL backend')
		return
	}
	self.opengl_ready = true
	self.previous_ns = 0
	if first {
		self.context_ready = true
		self.setup()
	}
	self.tick_callback_id = C.gtk_widget_add_tick_callback(self.widget, voidptr(imgui_tick_cb),
		voidptr(self), unsafe { nil })
}

fn (mut self ImguiWidget) unrealize() {
	if self.tick_callback_id != 0 {
		C.gtk_widget_remove_tick_callback(self.widget, self.tick_callback_id)
		self.tick_callback_id = 0
	}
	if self.opengl_ready {
		C.gtk_gl_area_make_current(self.gl_area)
		self.gpu.release()
		self.context.opengl_shutdown()
		self.opengl_ready = false
	}
}

pub fn (mut self ImguiWidget) deinit() {
	self.unrealize()
	if self.context_ready {
		self.context.destroy()
		self.context = cimgui.Context{}
		self.context_ready = false
	}
	if !isnil(self.im_context) {
		object_unref(GObject(self.im_context))
		self.im_context = unsafe { nil }
	}
	self.gl_area = unsafe { nil }
	self.widget = unsafe { nil }
}

fn (mut self ImguiWidget) resize(width int, height int) {
	if !self.set_current_context() {
		return
	}
	self.context.set_size(u32(width), u32(height))
	scale := C.gtk_widget_get_scale_factor(GtkWidget(self.gl_area))
	self.context.reset_style(if scale > 0 { f32(scale) } else { f32(1) })
}

fn (mut self ImguiWidget) new_frame() {
	now := i64(time.sys_mono_now())
	delta_time := if self.previous_ns != 0 {
		mut seconds := f32(f64(now - self.previous_ns) / 1_000_000_000.0)
		if seconds < 0.00001 {
			seconds = 0.00001
		}
		seconds
	} else {
		f32(1.0 / 60.0)
	}
	self.previous_ns = now
	self.context.begin_frame(delta_time)
}

fn (mut self ImguiWidget) gl_area_render() bool {
	if !self.set_current_context() {
		return false
	}
	self.last_render_ns = i64(time.sys_mono_now())
	for _ in 0 .. 2 {
		self.new_frame()
		self.render()
		self.context.render_frame()
	}
	self.gpu.render(self.context, imgui_background) or {
		self.context.opengl_new_frame()
		imgui_clear()
		self.context.opengl_render()
	}
	return true
}

fn imgui_clear() {
	C.glClearColor(imgui_background[0], imgui_background[1], imgui_background[2],
		imgui_background[3])
	C.glClear(u32(C.GL_COLOR_BUFFER_BIT))
}

fn (mut self ImguiWidget) key_event(action input.KeyAction, controller GtkEventControllerKey, keyval u32, gtk_mods u32) bool {
	self.queue_render()
	if !self.set_current_context() {
		return false
	}
	mods := translate_mods(gtk_mods)
	self.context.add_key(.left_shift, mods.shift())
	self.context.add_key(.left_ctrl, mods.ctrl())
	self.context.add_key(.left_alt, mods.alt())
	self.context.add_key(.left_super, mods.super_())
	if key := key_from_keyval(keyval) {
		if imgui_key := key.imgui_key() {
			self.context.add_key(imgui_key, action == .press)
		}
	}
	event := C.gtk_event_controller_get_current_event(controller)
	if !isnil(event) {
		_ = C.gtk_im_context_filter_keypress(self.im_context, event)
	}
	return true
}

fn imgui_mouse_button(button u32) ?cimgui.MouseButton {
	return match button {
		1 { cimgui.MouseButton.left }
		2 { cimgui.MouseButton.middle }
		3 { cimgui.MouseButton.right }
		else { none }
	}
}

fn imgui_glarea_realize_cb(area GtkGLArea, data voidptr) {
	_ = area
	if !isnil(data) {
		mut self := unsafe { &ImguiWidget(data) }
		self.realize()
	}
}

fn imgui_glarea_unrealize_cb(area GtkGLArea, data voidptr) {
	_ = area
	if !isnil(data) {
		mut self := unsafe { &ImguiWidget(data) }
		self.unrealize()
	}
}

fn imgui_glarea_resize_cb(area GtkGLArea, width int, height int, data voidptr) {
	_ = area
	if !isnil(data) {
		mut self := unsafe { &ImguiWidget(data) }
		self.resize(width, height)
	}
}

fn imgui_glarea_render_cb(area GtkGLArea, gl_context voidptr, data voidptr) int {
	_ = area
	_ = gl_context
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &ImguiWidget(data) }
	return b2i(self.gl_area_render())
}

fn imgui_focus_enter_cb(controller GtkEventControllerFocus, data voidptr) {
	_ = controller
	if !isnil(data) {
		self := unsafe { &ImguiWidget(data) }
		if self.set_current_context() {
			self.context.add_focus(true)
			self.queue_render()
		}
	}
}

fn imgui_focus_leave_cb(controller GtkEventControllerFocus, data voidptr) {
	_ = controller
	if !isnil(data) {
		self := unsafe { &ImguiWidget(data) }
		if self.set_current_context() {
			self.context.add_focus(false)
			self.queue_render()
		}
	}
}

fn imgui_key_pressed_cb(controller GtkEventControllerKey, keyval u32, keycode u32, gtk_mods u32, data voidptr) int {
	_ = keycode
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &ImguiWidget(data) }
	return b2i(self.key_event(.press, controller, keyval, gtk_mods))
}

fn imgui_key_released_cb(controller GtkEventControllerKey, keyval u32, keycode u32, gtk_mods u32, data voidptr) {
	_ = keycode
	if !isnil(data) {
		mut self := unsafe { &ImguiWidget(data) }
		_ = self.key_event(.release, controller, keyval, gtk_mods)
	}
}

fn imgui_mouse_pressed_cb(gesture GtkGestureClick, press_count int, x f64, y f64, data voidptr) {
	_ = press_count
	_ = x
	_ = y
	if !isnil(data) {
		self := unsafe { &ImguiWidget(data) }
		self.queue_render()
		if self.set_current_context() {
			if button := imgui_mouse_button(C.gtk_gesture_single_get_current_button(gesture)) {
				self.context.add_mouse_button(button, true)
			}
		}
	}
}

fn imgui_mouse_released_cb(gesture GtkGestureClick, press_count int, x f64, y f64, data voidptr) {
	_ = press_count
	_ = x
	_ = y
	if !isnil(data) {
		self := unsafe { &ImguiWidget(data) }
		self.queue_render()
		if self.set_current_context() {
			if button := imgui_mouse_button(C.gtk_gesture_single_get_current_button(gesture)) {
				self.context.add_mouse_button(button, false)
			}
		}
	}
}

fn imgui_mouse_motion_cb(controller GtkEventControllerMotion, x f64, y f64, data voidptr) {
	_ = controller
	if !isnil(data) {
		self := unsafe { &ImguiWidget(data) }
		self.queue_render()
		if self.set_current_context() {
			scale := f64(C.gtk_widget_get_scale_factor(GtkWidget(self.gl_area)))
			self.context.add_mouse_pos(f32(x * scale), f32(y * scale))
		}
	}
}

fn imgui_mouse_scroll_cb(controller GtkEventControllerScroll, x f64, y f64, data voidptr) int {
	_ = controller
	if isnil(data) {
		return 0
	}
	self := unsafe { &ImguiWidget(data) }
	self.queue_render()
	if !self.set_current_context() {
		return 0
	}
	self.context.add_mouse_wheel(f32(x), f32(-y))
	return 1
}

fn imgui_im_commit_cb(context GtkIMContext, bytes &char, data voidptr) {
	_ = context
	if !isnil(data) && !isnil(bytes) {
		self := unsafe { &ImguiWidget(data) }
		self.queue_render()
		if self.set_current_context() {
			self.context.add_text(unsafe { cstring_to_vstring(bytes) })
		}
	}
}

fn imgui_tick_cb(widget GtkWidget, frame_clock voidptr, data voidptr) int {
	_ = widget
	_ = frame_clock
	if isnil(data) {
		return 0
	}
	self := unsafe { &ImguiWidget(data) }
	now := i64(time.sys_mono_now())
	if self.last_render_ns == 0 || now - self.last_render_ns >= i64(1_000_000_000 / 30) {
		self.queue_render()
	}
	return 1
}
