module ui2_runtime

import apprt
import core
import datastruct
import math
import opengl
import renderer
import sokol.sapp
import stbi
import terminal
import ui2

@[heap]
struct Pane {
	id int
mut:
	surface      &core.Surface
	host         &apprt.RuntimeSurface
	surface_ref  &core.SurfaceRef = unsafe { nil }
	frame        ui2.Rect
	title        string = 'Terminal'
	search       bool
	query        string
	matches      ?uint
	selected     ?uint
	readonly     bool
	progress     ?u8
	scrollbar    terminal.Scrollbar
	mouse_cursor sapp.MouseCursor = .ibeam
}

struct Tab {
mut:
	tree   datastruct.SplitTree[Pane]
	active datastruct.Handle
}

fn (mut pane Pane) ref() &Pane { return pane }

fn (mut pane Pane) unref() {}

fn (pane &Pane) eql(other &Pane) bool { return pane.id == other.id }

fn (mut app App) create_pane(parent ?&Pane) !&Pane {
	defer { renderer.restore_ui2_opengl_state() }
	app.next_id++
	scale := f32(ui2.scale())
	frame := ui2.bounds()
	mut pane := &Pane{
		id:      app.next_id
		surface: &core.Surface{}
		host:    &apprt.RuntimeSurface{
			content_scale:         apprt.ContentScale{ x: scale, y: scale }
			size:                  size_in_pixels(frame, f64(scale))
			close_fn:              close_surface
			set_clipboard_fn:      set_clipboard
			clipboard_request_fn:  clipboard_request
			supports_clipboard_fn: supports_clipboard
			startup_size_fn:       startup_size
		}
	}
	pane.host.user_data = pane
	pane.surface_ref = &core.SurfaceRef{ id: pane.id, core_surface: pane.surface, rt_app: app.runtime }
	// Actions during initialization can set the title before the pane is mounted.
	app.initializing = pane
	defer { app.initializing = unsafe { nil } }
	mut config := app.runtime.config
	if old := parent {
		if pwd := old.surface.pwd() {
			config.working_directory = pwd
		}
	}
	pane.surface.init(&config, mut app.core, app.runtime, pane.host)!
	pane.surface.renderer.api.texture_output = true
	app.core.add_surface(pane.surface_ref)
	return pane
}

fn startup_size(data voidptr, size apprt.InitialSize, minimum apprt.SizeLimit) ?apprt.SurfaceSize {
	mut app := g_app
	if app.tabs.len > 0 { return none }
	requested := apprt.SurfaceSize{
		width: math.min(u32(65535), math.max(size.width, minimum.min_width))
		height: math.min(u32(65535), math.max(size.height, minimum.min_height))
	}
	if app.screenshot != '' {
		app.capture_size = requested
	} else if !set_initial_window_size(requested.width, requested.height) {
		return none
	}
	mut pane := unsafe { &Pane(data) }
	pane.host.size = requested
	return requested
}

fn (mut app App) destroy_pane(mut pane Pane) {
	defer { renderer.restore_ui2_opengl_state() }
	app.core.delete_surface(pane.surface_ref)
	pane.surface.deinit()
}

fn (pane &Pane) element_id() string { return 'terminal-${pane.id}' }

fn size_in_pixels(frame ui2.Rect, scale f64) apprt.SurfaceSize {
	return apprt.SurfaceSize{
		width:  u32(math.max(1, math.round(frame.width * scale)))
		height: u32(math.max(1, math.round(frame.height * scale)))
	}
}

fn render_pane(id string, frame ui2.Rect, scale f64, _ f64) {
	mut app := g_app
	mut pane := app.pane_by_id(id.all_after('terminal-').int()) or { return }
	app.draw(mut pane, frame, scale) or {
		app.failure = err
		ui2.quit()
	}
}

fn (mut app App) draw(mut pane Pane, frame ui2.Rect, scale f64) ! {
	defer { renderer.restore_ui2_opengl_state() }
	size := if app.capture_size.width > 0 { app.capture_size } else { size_in_pixels(frame, scale) }
	if pane.host.content_scale.x != f32(scale) {
		pane.host.content_scale = apprt.ContentScale{ x: f32(scale), y: f32(scale) }
		pane.surface.content_scale_callback(pane.host.content_scale)!
	}
	if pane.host.size != size {
		pane.host.size = size
		pane.surface.size_callback(size)!
	}
	opengl.viewport(0, 0, int(size.width), int(size.height))!
	pane.surface.draw()!
	if target := pane.surface.renderer.api.texture_target {
		ui2.set_gl_surface_texture(pane.element_id(), target.texture, int(target.width), int(target.height))
		if app.screenshot != '' && !app.capture_started {
			app.capture_started = true
			ui2.after(app.screenshot_delay, mark_capture_due)
		}
		if app.capture_due {
			image := pane.surface.renderer.screenshot_frame()!
			stbi.stbi_write_png(app.screenshot, image.width, image.height, 4, image.rgba.data, image.width * 4)!
			app.capture_complete = true
			ui2.quit()
		}
	}
}

fn mark_capture_due() {
	g_app.capture_due = true
}
