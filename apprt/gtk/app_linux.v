module gtk

// app_linux.v - The thin apprt App adapter for the GTK runtime.
//
// Translated from ghostty/src/apprt/gtk/App.zig.
//
// In ghostty this struct is a thin wrapper around the GObject `Application`
// class (class/application.zig). All the heavy lifting lives in that GObject
// class, which is translated in `application_linux.v` (the canonical owner of
// the `Application` type). The core `App` is `core.App`, used directly. The
// apprt-interface method signatures are kept faithful to the Zig original.

import apprt
import core

// must_draw_from_app_thread is detected by the Renderer, in which case it
// sends a `redraw_surface` message so we can call `drawFrame` ourselves from
// the app thread, because GTK's `GLArea` does not support drawing from a
// different thread.
pub const must_draw_from_app_thread = true

// application_id is the GTK application ID.
//
// Ghostty selects between a "-debug" and release ID based on the build mode.
// We mirror that using V's `-prod` compile flag.
pub const application_id = $if prod {
	'com.alexander.witty'
} $else {
	'com.alexander.witty-debug'
}

// object_path is the GTK object path, likewise selected by build mode.
pub const object_path = $if prod {
	'/com/alexander/witty'
} $else {
	'/com/alexander/witty_debug'
}

// The GObject `Application` class is the canonical entrypoint that wraps a
// GtkApplication / AdwApplication and owns the run loop. It lives in
// `application_linux.v`.

// App is the main entrypoint to the apprt for the GTK runtime. It is
// initialized in main to start the application.
pub struct App {
pub mut:
	// The GObject Application instance.
	app &Application = unsafe { nil }
	screenshot ScreenshotOptions
}

// init initializes the App. Mirrors `App.init`.
//
// `opts` is required by the apprt interface but unused (an empty struct in
// Zig). We omit it here since V has no anonymous empty-struct parameter idiom.
pub fn (mut self App) init(core_app &core.App) ! {
	app := Application.new(self, core_app)!
	self.app = app
}

// run starts the application main loop. Mirrors `App.run`.
pub fn (mut self App) run() ! {
	self.app.run()!
}

// terminate forcibly deinitializes the app. Mirrors `App.terminate`.
//
// We do not unref because other things tend to have a reference at this
// point, so this just forces disposal now.
pub fn (mut self App) terminate() {
	self.app.deinit()
}

// wakeup is called by CoreApp to wake up the event loop. Mirrors `App.wakeup`.
pub fn (mut self App) wakeup() {
	self.app.wakeup()
}

// perform_action performs an apprt action. Mirrors `App.performAction`.
pub fn (mut self App) perform_action(target apprt.Target, action apprt.ActionKey, data apprt.ActionValue) !bool {
	return self.app.perform_action(target, action, data)
}

// perform_ipc sends the given IPC to a running Ghostty. Returns true if the
// action was performed, false otherwise. Mirrors `App.performIpc`.
//
// This is a static function. Since this is called from a CLI app (or some
// other process that is not Ghostty) there is no full-featured apprt App to
// use.
pub fn App.perform_ipc(target apprt.IpcTarget, action apprt.IpcAction) !bool {
	return ipc_new_window(target, action.new_window)
}

// redraw_inspector redraws the inspector for the given surface. Mirrors
// `App.redrawInspector`.
pub fn (self &App) redraw_inspector(mut surface Surface) {
	surface.redraw_inspector()
}
