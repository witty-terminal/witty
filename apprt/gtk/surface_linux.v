module gtk

// surface_linux.v - The thin apprt Surface adapter for the GTK runtime.
//
// Translated from ghostty/src/apprt/gtk/Surface.zig.
//
// Like the App adapter, this is a thin wrapper around the GhosttySurface
// GObject implemented by SurfaceWidget in surface_class_linux.v.

import apprt
import core

// Surface is the apprt Surface adapter for the GTK runtime.
pub struct Surface {
pub mut:
	// The GObject Surface.
	surface &SurfaceWidget = unsafe { nil }
}

// deinit tears down the surface adapter. Mirrors `Surface.deinit`.
pub fn (mut self Surface) deinit() {}

// gobj returns the GObject surface for this apprt surface. This is a function
// so we can add extra logic if we ever have to. Mirrors `Surface.gobj`.
pub fn (mut self Surface) gobj() &SurfaceWidget {
	return self.surface
}

// core returns the core.Surface for this apprt surface. Mirrors `Surface.core`.
//
// In Zig this asserts non-optional because libwitty should only call this
// for initialized surfaces.
pub fn (mut self Surface) core() &core.Surface {
	return self.surface.core() or { panic('initialized GTK surface has no core surface') }
}

// rt_app returns the apprt App for this surface. Mirrors `Surface.rtApp`.
pub fn (self &Surface) rt_app() &App {
	_ = self
	return Application.default().rt()
}

// close closes the surface. Mirrors `Surface.close`.
pub fn (mut self Surface) close(process_active bool) {
	_ = process_active
	self.surface.close()
}

// cgroup returns the cgroup path for this surface, if any. Mirrors
// `Surface.cgroup`.
pub fn (mut self Surface) cgroup() ?string {
	return self.surface.cgroup_path()
}

// get_title returns the surface title, if any. Mirrors `Surface.getTitle`.
pub fn (mut self Surface) get_title() ?string {
	return self.surface.get_title()
}

// get_content_scale returns the content scale. Mirrors `Surface.getContentScale`.
pub fn (self &Surface) get_content_scale() !apprt.ContentScale {
	return self.surface.get_content_scale()
}

// get_size returns the surface size in pixels. Mirrors `Surface.getSize`.
pub fn (self &Surface) get_size() !apprt.SurfaceSize {
	return self.surface.get_size()
}

// get_cursor_pos returns the cursor position in pixels. Mirrors
// `Surface.getCursorPos`.
pub fn (self &Surface) get_cursor_pos() !apprt.CursorPos {
	return self.surface.get_cursor_pos()
}

// supports_clipboard reports whether the given clipboard type is supported.
// Mirrors `Surface.supportsClipboard`. On GTK all clipboard types are
// supported.
pub fn (self &Surface) supports_clipboard(clipboard_type apprt.Clipboard) bool {
	return match clipboard_type {
		.standard, .selection, .primary { true }
	}
}

// clipboard_request requests clipboard contents. Mirrors
// `Surface.clipboardRequest`.
pub fn (mut self Surface) clipboard_request(clipboard_type apprt.Clipboard, state apprt.ClipboardRequest) !bool {
	return self.surface.clipboard_request(clipboard_type, state)
}

// set_clipboard sets the clipboard contents. Mirrors `Surface.setClipboard`.
pub fn (mut self Surface) set_clipboard(clipboard_type apprt.Clipboard, contents []apprt.ClipboardContent, confirm bool) ! {
	self.surface.set_clipboard(clipboard_type, contents, confirm)
}

// default_termio_env returns the default termio environment map. Mirrors
// `Surface.defaultTermioEnv`.
pub fn (mut self Surface) default_termio_env() !map[string]string {
	return self.surface.default_termio_env()
}

// redraw_inspector redraws the inspector for our surface. Mirrors
// `Surface.redrawInspector`.
pub fn (mut self Surface) redraw_inspector() {
	self.surface.redraw_inspector()
}

// rt returns the apprt App backing this Application. Mirrors `Application.rt()`.
pub fn (self &Application) rt() &App {
	return self.rt_app
}
