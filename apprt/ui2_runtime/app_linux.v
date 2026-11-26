@[has_globals]
module ui2_runtime

import apprt
import buildcfg
import configpkg
import core
import input
import internal_os
import log
import os
import renderer
import sokol.sapp
import ui2

struct App {
mut:
	core             &core.App
	runtime          &apprt.RuntimeApp
	tabs             []Tab
	active_tab       int
	next_id          int
	focused          bool = true
	ready            bool
	started          bool
	initializing     &Pane = unsafe { nil }
	screenshot       string
	screenshot_delay f64
	capture_size     apprt.SurfaceSize
	capture_started  bool
	capture_due      bool
	capture_complete bool
	failure          ?IError
	dialog           ?Dialog
	palette          bool
	palette_query    string
	context_menu     ?ui2.Rect
	toast            string
	toast_timer      ui2.TimerId
	pending_key      ?input.KeyEvent
	mouse_pane       int
	mouse_buttons    u32
}

__global g_app = &App(unsafe { nil })

pub fn run(mut terminal core.App, path string, delay f64) ! {
	internal_os.init_global_domain() or { log.warn('i18n initialization failed: ${err}') }
	mut config := configpkg.Config.load() or { config_load_failure(err) }
	if path != '' {
		config.wait_after_command = true
		config.window_show_tab_bar = .never
	}
	mut app := &App{
		core:             terminal
		runtime:          &apprt.RuntimeApp{ config: config, action_fn: dispatch_action, wakeup_fn: wakeup }
		screenshot:       path
		screenshot_delay: delay
	}
	app.runtime.user_data = app
	g_app = app
	defer {
		g_app = unsafe { nil }
	}
	ui2.on_window_ready(window_ready)
	ui2.on_window_cleanup(window_cleanup)
	ui2.set_window_event_filter(window_event)
	ui2.set_gl_surface_renderer(render_pane)
	ui2.run_window_with_options(ui2.WindowOptions{
		title:        'Witty'
		width:        800
		height:       600
		sample_count: 1
		background:   true
		gl:           sapp.GlDesc{
			major_version: renderer.opengl_min_version_major
			minor_version: renderer.opengl_min_version_minor
		}
		fullscreen:   path == '' && config.fullscreen
		borderless:   path != '' || config.window_decoration == .none_
	}, build_screen, handle_control)
	if err := app.failure { return err }
	if !app.started { return error('UI2 could not open a terminal window') }
	if path != '' && !app.capture_complete {
		return error('terminal closed before screenshot')
	}
}

fn config_load_failure(err IError) configpkg.Config {
	mut fallback := configpkg.Config.default()
	fallback.add_diagnostic_fmt(err.msg())
	return fallback
}

fn window_ready(_ voidptr) {
	mut app := g_app
	app.ready = true
	app.started = true
	app.core.focus_event(true)
	identify_window(app.runtime.config.class or {
		if buildcfg.mode_string in ['Debug', 'ReleaseSafe'] { 'com.alexander.witty-debug' } else { 'com.alexander.witty' }
	})
	app.new_tab(none) or {
		app.failure = err
		ui2.quit()
		return
	}
	if app.screenshot != '' {
		ui2.after(10, capture_timeout)
	}
	if text := config_diagnostics(&app.runtime.config) {
		app.dialog = Dialog{ title: 'Configuration', message: text }
	}
	ui2.request_refresh()
}

fn config_diagnostics(config &configpkg.Config) ?string {
	mut messages := []string{}
	for diagnostic in config.diagnostics {
		messages << diagnostic.format()
	}
	return if messages.len == 0 { none } else { messages.join('\n') }
}

fn window_cleanup() {
	mut app := g_app
	app.ready = false
	for mut tab in app.tabs {
		mut iterator := tab.tree.iterator()
		for {
			entry := iterator.next() or { break }
			mut pane := unsafe { entry.view }
			app.destroy_pane(mut pane)
		}
		tab.tree.free()
	}
	app.tabs.clear()
}

fn capture_timeout() {
	mut app := g_app
	if app.capture_started { return }
	app.failure = error('terminal did not render a frame for the screenshot')
	ui2.quit()
}

fn wakeup(_ voidptr) {
	ui2.request_refresh()
}

fn build_screen() ui2.Element {
	mut app := g_app
	if app.ready {
		app.flush_pending_key('')
		app.core.tick(mut app.runtime) or { log.error('terminal update failed: ${err}') }
	}
	return app.screen(ui2.bounds())
}

fn (mut app App) confirm_close() {
	if app.core.needs_confirm_quit() {
		app.dialog = Dialog{
			title:   'Close window?'
			message: 'A terminal process is still running.'
			button:  'Close window'
			action:  .quit
		}
		ui2.request_refresh()
		return
	}
	ui2.quit()
}

fn (mut app App) new_window(parent ?&Pane) ! {
	mut args := []string{}
	if pane := parent {
		if app.runtime.config.window_inherit_working_directory {
			if pwd := pane.surface.pwd() {
				args << '--working-directory=${pwd}'
			}
		}
	}
	executable := os.executable()
	mut child := os.new_process(executable)
	child.set_args(args)
	child.run()
	if child.pid <= 0 {
		return error('could not open a new Witty window')
	}
	spawn wait_for_window(mut child)
}

fn wait_for_window(mut child os.Process) {
	child.wait()
	child.close()
}
