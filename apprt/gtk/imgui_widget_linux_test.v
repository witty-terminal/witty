module gtk

import cimgui
import font
import opengl
import time

fn C.g_type_is_a(GType, GType) int
fn C.g_type_name(GType) &char
fn C.gtk_window_new() GtkWidget
fn C.gtk_window_set_child(GtkWindow, GtkWidget)
fn C.gtk_gl_area_attach_buffers(GtkGLArea)
fn C.glGetIntegerv(u32, &int)

struct ImguiWidgetCallbackCounts {
mut:
	setup  int
	render int
}

fn count_imgui_setup(data voidptr) {
	mut counts := unsafe { &ImguiWidgetCallbackCounts(data) }
	counts.setup++
}

fn count_imgui_render(data voidptr) {
	mut counts := unsafe { &ImguiWidgetCallbackCounts(data) }
	counts.render++
}

fn test_imgui_native_class_and_inspector_inheritance() {
	base := imgui_widget_get_type()
	inspector := inspector_widget_get_type()
	assert C.g_type_is_a(base, C.adw_bin_get_type()) != 0
	assert C.g_type_is_a(inspector, base) != 0
	assert unsafe { cstring_to_vstring(C.g_type_name(base)) } == 'GhosttyImguiWidget'
	assert unsafe { cstring_to_vstring(C.g_type_name(inspector)) } == 'GhosttyInspectorWidget'
}

fn test_imgui_widget_native_virtual_methods_dispatch_the_inspector_override() {
	if !C.gtk_init_check() { return }
	C.adw_init()
	mut counts := &ImguiWidgetCallbackCounts{}
	mut widget := new_imgui_widget_type(inspector_widget_get_type(), count_imgui_setup,
		count_imgui_render, voidptr(counts))
	widget.ref_sink()
	widget.setup()
	widget.render()
	widget.render()
	assert counts.setup == 1
	assert counts.render == 2
	// Avoid invoking the inspector surface lifecycle with synthetic user_data.
	object := GObject(widget.widget)
	native_wrapper_set(object, imgui_widget_wrapper_key, unsafe { nil })
	widget.deinit()
	object_unref(object)
}

struct ImguiRenderProbe {
mut:
	widget &ImguiWidget = unsafe { nil }
	setups int
}

fn setup_imgui_render_probe(data voidptr) {
	mut probe := unsafe { &ImguiRenderProbe(data) }
	probe.setups++
	probe.widget.context.inspector_setup(font.embedded_regular)
}

fn draw_imgui_render_probe(data voidptr) {
	probe := unsafe { &ImguiRenderProbe(data) }
	ctx := probe.widget.context
	if ctx.begin_window('Terminal inspector') {
		ctx.text('Screen and scrollback')
		ctx.text_colored(cimgui.Color{ r: 0.2, g: 0.7, b: 0.5, a: 0.6 }, 'Attributes')
		if ctx.begin_table('cells', 2, 0) {
			for row in 0 .. 12 {
				ctx.table_next_row()
				ctx.table_set_column(0)
				ctx.text('Row ${row}')
				ctx.table_set_column(1)
				ctx.text('Ω · ░─▓')
			}
			ctx.end_table()
		}
	}
	ctx.end_window()
	if ctx.begin_window('Other pane') { ctx.text('Input') }
	ctx.end_window()
}

fn wait_for_imgui_gl_area(widget &ImguiWidget) bool {
	for _ in 0 .. 150 {
		for C.g_main_context_iteration(unsafe { nil }, false) {
		}
		if widget.opengl_ready && widget.last_render_ns != 0 { return true }
		time.sleep(10 * time.millisecond)
	}
	return false
}

fn test_gtk_inspector_gg_matches_native_pixels_and_recreates_gl_context() ! {
	if !C.gtk_init_check() { return }
	C.adw_init()
	mut probe := &ImguiRenderProbe{}
	mut widget := new_imgui_widget_type(inspector_widget_get_type(), setup_imgui_render_probe,
		draw_imgui_render_probe, voidptr(probe))
	widget.ref_sink()
	probe.widget = widget
	window := GtkWindow(C.gtk_window_new())
	C.gtk_window_set_default_size(window, 640, 460)
	C.gtk_window_set_child(window, widget.widget)
	defer {
		C.gtk_window_set_child(window, unsafe { nil })
		native_wrapper_set(GObject(widget.widget), imgui_widget_wrapper_key, unsafe { nil })
		object := GObject(widget.widget)
		widget.deinit()
		object_unref(object)
		C.gtk_window_destroy(window)
	}
	C.gtk_window_present(window)
	assert wait_for_imgui_gl_area(widget)
	assert probe.setups == 1
	C.gtk_gl_area_make_current(widget.gl_area)
	C.gtk_gl_area_attach_buffers(widget.gl_area)
	_ = opengl.load(unsafe { nil })!
	defer { opengl.unload() }
	mut name := 0
	C.glGetIntegerv(u32(C.GL_DRAW_FRAMEBUFFER_BINDING), &name)
	assert name != 0
	fbo := opengl.Framebuffer{ id: u32(name) }
	frame := widget.context.draw_frame()
	width, height := u32(frame.width * frame.scale_x), u32(frame.height * frame.scale_y)
	assert frame.lists >= 2
	imgui_clear()
	widget.context.opengl_new_frame()
	widget.context.opengl_render()
	expected := fbo.read_rgba8(width, height)!
	assert expected[0..4] == [u8(40), 44, 52, 255]
	assert expected.any(it > 100 && it < 255)
	widget.gpu.render(widget.context, imgui_background)!
	actual := fbo.read_rgba8(width, height)!
	assert actual == expected

	C.gtk_window_set_child(window, unsafe { nil })
	assert !widget.opengl_ready
	widget.last_render_ns = 0
	C.gtk_window_set_child(window, widget.widget)
	assert wait_for_imgui_gl_area(widget)
	assert probe.setups == 1
	C.gtk_gl_area_make_current(widget.gl_area)
	C.gtk_gl_area_attach_buffers(widget.gl_area)
	widget.gpu.render(widget.context, imgui_background)!
}
