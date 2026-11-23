module gtk

// winproto_x11_linux.v - X11 window-protocol backend for the GTK apprt.
//
// Translated from ghostty/src/apprt/gtk/winproto/x11.zig.
//
// Implements:
//   - Xkb initialization (WM_CLASS / program class, XkbQueryExtension,
//     XkbSelectEventDetails) and modifier snapshotting via XkbStateNotify.
//   - KDE background blur (_KDE_NET_WM_BLUR_BEHIND_REGION) property.
//   - Motif WM decoration hints (_MOTIF_WM_HINTS).
//   - WINDOWID subprocess env + urgency hint.
//
// Opaque Xlib handles (Display) are modeled as `voidptr`. Atoms are `u64`
// (unsigned long). We link against Xlib and pull in the Xlib headers only on
// Linux.

import input
import configpkg
import log

#flag linux -lX11

#include <X11/Xlib.h>

#include <X11/Xatom.h>

#include <X11/XKBlib.h>

#include <gdk/x11/gdkx.h>

#include "x11_shims.h"

// --- Opaque X11 handle aliases ---------------------------------------------

// XDisplay is an opaque Xlib `Display*`.
pub type XDisplay = voidptr

// XAtom is an Xlib `Atom` (unsigned long).
pub type XAtom = u64

// XWindow is an Xlib `Window` XID (unsigned long).
pub type XWindow = u64

// --- GDK-X11 bridge C declarations -----------------------------------------
// These come from gdk/x11/gdkx.h. We only need to detect an X11 display, pull
// out the underlying Xlib Display, set the program class, and resolve atoms.

fn C.gdk_x11_display_get_xdisplay(display GdkDisplay) XDisplay

fn C.gdk_x11_display_set_program_class(display GdkDisplay, program_class &char)

fn C.gdk_x11_get_xatom_by_name_for_display(display GdkDisplay, atom_name &char) XAtom

fn C.gdk_x11_surface_get_xid(surface GdkSurface) XWindow

fn C.witty_gdk_is_x11_surface(surface GdkSurface) int

fn C.gdk_x11_surface_set_urgency_hint(surface GdkSurface, urgent int)

// g_set_prgname sets the GLib program name (used to derive WM_CLASS instance).
fn C.g_set_prgname(prgname &char)

// GDK type check for X11 displays. Returns non-zero when the display is X11.
// This mirrors ghostty's `gobject.ext.cast(gdk_x11.X11Display, ...)`.
fn C.GDK_IS_X11_DISPLAY(display GdkDisplay) int

// --- Xlib C declarations ---------------------------------------------------

fn C.XkbQueryExtension(display XDisplay, opcode_rtrn &int, event_rtrn &int, error_rtrn &int, major_in_out &int, minor_in_out &int) int

fn C.XkbSelectEventDetails(display XDisplay, device_spec u32, event_type u32, bits_to_change u64, values_for_bits u64) int

fn C.XEventsQueued(display XDisplay, mode int) int

fn C.XPeekEvent(display XDisplay, event_return voidptr) int

fn C.XGetWindowProperty(display XDisplay, w XWindow, property XAtom, long_offset i64, long_length i64, delete int, req_type XAtom, actual_type_return &XAtom, actual_format_return &int, nitems_return &u64, bytes_after_return &u64, prop_return &voidptr) int

fn C.XChangeProperty(display XDisplay, w XWindow, property XAtom, typ XAtom, format int, mode int, data &u8, nelements int) int

fn C.XDeleteProperty(display XDisplay, w XWindow, property XAtom) int

fn C.XFree(data voidptr) int

fn C.witty_x11_event_type(event voidptr) int

fn C.witty_xkb_event_type(event voidptr) int

fn C.witty_xkb_event_lookup_mods(event voidptr) u32

// Xlib event type constants (from XKBlib.h / X.h).
const xkb_use_core_kbd = u32(0x0100)
const xkb_state_notify = u32(2)
const xkb_modifier_state_mask = u64(0x0004)
const xkb_major_version = 1
const xkb_minor_version = 0

const queued_after_reading = 1
const x_none = XAtom(0)
const x_success = 0

// Property change modes (from X.h).
const prop_mode_replace = 0

// Property formats.
const prop_format_32 = 32

// XA_CARDINAL predefined atom (from Xatom.h).
const xa_cardinal = XAtom(6)

// XKB modifier masks (from X.h). Same values as GDK uses, but read from the
// Xkb lookup_mods field of an XkbStateNotifyEvent.
const x_shift_mask = u64(1) << 0
const x_lock_mask = u64(1) << 1
const x_control_mask = u64(1) << 2
const x_mod1_mask = u64(1) << 3
const x_mod4_mask = u64(1) << 6

// Region is the KDE blur region property payload. Mirrors x11.zig's `Region`
// extern struct: four `c_long` (x, y, width, height).
struct Region {
mut:
	x      i64
	y      i64
	width  i64
	height i64
}

// MotifWMHints mirrors x11.zig's `MotifWMHints` extern struct (Xm/MwmUtil.h).
// We only care about the `decorations` flag/value; the layout must match the
// C `_MOTIF_WM_HINTS` property (five unsigned/long words).
struct MotifWMHints {
mut:
	flags       u64
	functions   u64
	decorations u64
	input_mode  i64
	status      u64
}

// Motif hint bit for the "decorations" flag word (bit 1).
const motif_flag_decorations = u64(1) << 1

// Atoms holds the interned X11 atoms we use. Mirrors x11.zig's `Atoms`.
struct Atoms {
	kde_blur       XAtom
	motif_wm_hints XAtom
}

fn Atoms.init(display GdkDisplay) Atoms {
	return Atoms{
		kde_blur: C.gdk_x11_get_xatom_by_name_for_display(display, c'_KDE_NET_WM_BLUR_BEHIND_REGION')
		motif_wm_hints: C.gdk_x11_get_xatom_by_name_for_display(display, c'_MOTIF_WM_HINTS')
	}
}

// --- App -------------------------------------------------------------------

// X11App is the application-wide X11 state. Mirrors x11.zig's `App`.
//
// `@[heap]` so the per-window state (X11Window) can hold a stable `&X11App`
// reference (mirroring ghostty's `*App`).
@[heap]
pub struct X11App {
pub mut:
	display         XDisplay = unsafe { nil }
	base_event_code int
	atoms           Atoms
}

// V cannot express Ghostty's error-union-of-optional return directly. Keep a
// display mismatch separate from XKB initialization errors.
struct X11AppProbe {
	matched bool
	app     X11App
}

// X11App.init sets up the X11 backend for the given display, or returns a
// non-matching probe if the display is not X11. Actual initialization failures
// remain errors, matching `x11.App.init`.
fn X11App.init(gdk_display GdkDisplay, app_id string, config &configpkg.Config) !X11AppProbe {
	// If the display isn't X11, then we don't need to do anything.
	if C.GDK_IS_X11_DISPLAY(gdk_display) == 0 {
		return X11AppProbe{}
	}

	xlib_display := C.gdk_x11_display_get_xdisplay(gdk_display)

	// Select the program name used to derive the WM_CLASS instance name.
	default_program_name := $if prod { 'witty' } $else { 'witty-debug' }
	x11_program_name := config.x11_instance_name or { default_program_name }

	// Set the X11 window class property (WM_CLASS). g_set_prgname supplies
	// the instance name; set_program_class supplies the class name.
	C.g_set_prgname(x11_program_name.str)
	C.gdk_x11_display_set_program_class(gdk_display, app_id.str)

	// XKB init.
	log.debug('Xkb.init: initializing Xkb')
	log.debug('Xkb.init: running XkbQueryExtension')
	mut opcode := 0
	mut base_event_code := 0
	mut base_error_code := 0
	mut major := xkb_major_version
	mut minor := xkb_minor_version
	if C.XkbQueryExtension(xlib_display, &opcode, &base_event_code, &base_error_code, &major, &minor) == 0 {
		log.error('Fatal: error initializing Xkb extension: error executing XkbQueryExtension')
		return error('XkbInitializationError')
	}

	log.debug('Xkb.init: running XkbSelectEventDetails')
	if C.XkbSelectEventDetails(xlib_display, xkb_use_core_kbd, xkb_state_notify, xkb_modifier_state_mask, xkb_modifier_state_mask) == 0 {
		log.error('Fatal: error initializing Xkb extension: error executing XkbSelectEventDetails')
		return error('XkbInitializationError')
	}

	return X11AppProbe{
		matched: true
		app: X11App{
			display: xlib_display
			base_event_code: base_event_code
			atoms: Atoms.init(gdk_display)
		}
	}
}

// deinit mirrors `x11.App.deinit`.
pub fn (mut self X11App) deinit() {}

// event_mods checks for an immediate pending XkbStateNotify event and returns
// the keyboard modifier state if found, else `none`. Mirrors
// `x11.App.eventMods`.
pub fn (self X11App) event_mods(device GdkDevice, gtk_mods u32) ?input.Mods {
	_ = device
	_ = gtk_mods

	if C.XEventsQueued(self.display, queued_after_reading) == 0 {
		return none
	}

	// XEvent is a large union; back it with a buffer big enough for any XKB
	// event. 256 bytes comfortably covers XkbAnyEvent/XkbStateNotifyEvent.
	mut next_event := [256]u8{}
	C.XPeekEvent(self.display, &next_event[0])

	// XAnyEvent's first field is `int type`; if it isn't the Xkb base event
	// code, this isn't an Xkb event at all.
	event_type := C.witty_x11_event_type(&next_event[0])
	if event_type != self.base_event_code {
		return none
	}

	// Confirm the Xkb sub-type is StateNotify, then read lookup_mods through the
	// real Xlib union layout.
	if C.witty_xkb_event_type(&next_event[0]) != int(xkb_state_notify) {
		return none
	}

	lookup_mods := u64(C.witty_xkb_event_lookup_mods(&next_event[0]))
	log.debug('X11: found extra XkbStateNotify event w/lookup_mods: ${lookup_mods:b}')

	mut mods := input.Mods{}
	if lookup_mods & x_shift_mask != 0 {
		mods.set_shift(true)
	}
	if lookup_mods & x_control_mask != 0 {
		mods.set_ctrl(true)
	}
	if lookup_mods & x_mod1_mask != 0 {
		mods.set_alt(true)
	}
	if lookup_mods & x_mod4_mask != 0 {
		mods.set_super(true)
	}
	if lookup_mods & x_lock_mask != 0 {
		mods.set_caps_lock(true)
	}

	return mods
}

// supports_quick_terminal mirrors `x11.App.supportsQuickTerminal`. The quick
// terminal is not yet supported on X11.
pub fn (self X11App) supports_quick_terminal() bool {
	log.warn('quick terminal is not yet supported on X11')
	return false
}

// init_quick_terminal mirrors `x11.App.initQuickTerminal` (no-op on X11).
pub fn (mut self X11App) init_quick_terminal(apprt_window &ApprtWindow) ! {
	_ = apprt_window
}

// --- Window ----------------------------------------------------------------

// X11Window is the per-window X11 state. Mirrors x11.zig's `Window`.
pub struct X11Window {
pub mut:
	app          &X11App = unsafe { nil }
	apprt_window &ApprtWindow = unsafe { nil }
	x11_surface  GdkSurface = unsafe { nil }
	xid          XWindow

	blur_region Region

	// Cache last applied values to avoid redundant X11 property updates.
	// Redundant updates cause visual glitches with some WMs (ghostty #8075).
	last_applied_blur_region      ?Region
	last_applied_decoration_hints ?MotifWMHints
}

// X11Window.init mirrors `x11.Window.init`.
pub fn X11Window.init(mut app X11App, mut apprt_window ApprtWindow) !X11Window {
	surface := apprt_window.get_surface() or { return error('not an X11 surface') }
	if C.witty_gdk_is_x11_surface(surface) == 0 {
		return error('not an X11 surface')
	}

	// In ghostty this is a cast to gdk_x11.X11Surface; here we resolve the XID
	// directly from the GdkSurface.
	xid := C.gdk_x11_surface_get_xid(surface)

	return X11Window{
		app: &app
		apprt_window: &apprt_window
		x11_surface: surface
		xid: xid
	}
}

// deinit mirrors `x11.Window.deinit`.
pub fn (self X11Window) deinit() {}

// resize_event mirrors `x11.Window.resizeEvent`. The blur region must track
// window resizes.
pub fn (mut self X11Window) resize_event() ! {
	self.sync_blur()!
}

// sync_appearance mirrors `x11.Window.syncAppearance`. Recomputes the blur
// region offset (CSD vs SSD) and re-applies blur + decorations.
pub fn (mut self X11Window) sync_appearance() ! {
	// The user could have toggled between CSDs and SSDs, so recalculate the
	// blur region offset from the surface transform.
	mut x := f64(0)
	mut y := f64(0)
	self.apprt_window.get_surface_transform(&x, &y)

	// Transform surface coordinates to device coordinates.
	scale := f64(self.apprt_window.get_scale_factor())
	x *= scale
	y *= scale

	self.blur_region = Region{
		x: i64(x)
		y: i64(y)
	}

	self.sync_blur() or { log.error('failed to synchronize blur=${err}') }
	self.sync_decorations() or { log.error('failed to synchronize decorations=${err}') }
}

// client_side_decoration_enabled mirrors
// `x11.Window.clientSideDecorationEnabled`.
pub fn (self X11Window) client_side_decoration_enabled() bool {
	return match self.apprt_window.get_window_decoration() {
		.auto, .client { true }
		.server, .none_ { false }
	}
}

// sync_blur applies (or removes) the KDE blur region property. Mirrors
// `x11.Window.syncBlur`.
fn (mut self X11Window) sync_blur() ! {
	config_object := self.apprt_window.get_config() or { return }
	config := config_object.get()

	// When blur is disabled, remove the property if it was previously set.
	blur := config.background_blur
	if !blur_enabled(blur) {
		if self.last_applied_blur_region != none {
			self.delete_property(self.app.atoms.kde_blur)!
			self.last_applied_blur_region = none
		}
		return
	}

	// Transform surface coordinates to device coordinates.
	scale := self.apprt_window.get_scale_factor()
	self.blur_region.width = i64(self.apprt_window.get_width() * scale)
	self.blur_region.height = i64(self.apprt_window.get_height() * scale)

	// Only update X11 properties when the blur region actually changes.
	if last := self.last_applied_blur_region {
		if last == self.blur_region {
			return
		}
	}
	log.debug('set blur=${blur}, window xid=${self.xid}, region=${self.blur_region}')

	self.change_property_region(self.app.atoms.kde_blur, xa_cardinal, &self.blur_region)!
	self.last_applied_blur_region = self.blur_region
}

// sync_decorations applies the Motif WM decoration hints. Mirrors
// `x11.Window.syncDecorations`.
fn (mut self X11Window) sync_decorations() ! {
	mut hints := MotifWMHints{}

	// Read the existing hints, if any. A missing property is fine.
	self.get_window_property_motif(self.app.atoms.motif_wm_hints, self.app.atoms.motif_wm_hints, mut hints) or {
		if err.msg() != 'property not found' {
			return err
		}
	}

	hints.flags |= motif_flag_decorations
	hints.decorations = match self.apprt_window.get_window_decoration() {
		.server { u64(1) }
		.auto, .client, .none_ { u64(0) }
	}

	// Only update decoration hints when they actually change.
	if last := self.last_applied_decoration_hints {
		if last == hints {
			return
		}
	}

	self.change_property_motif(self.app.atoms.motif_wm_hints, self.app.atoms.motif_wm_hints, mut hints)!
	self.last_applied_decoration_hints = hints
}

// add_subprocess_env mirrors `x11.Window.addSubprocessEnv`. Exposes WINDOWID.
pub fn (mut self X11Window) add_subprocess_env(mut env map[string]string) ! {
	env['WINDOWID'] = self.xid.str()
}

// set_urgent mirrors `x11.Window.setUrgent`.
pub fn (mut self X11Window) set_urgent(urgent bool) ! {
	if !isnil(self.x11_surface) {
		C.gdk_x11_surface_set_urgency_hint(self.x11_surface, b2i(urgent))
	}
}

// --- Low-level property helpers --------------------------------------------

// get_window_property_motif reads a _MOTIF_WM_HINTS property into `result`.
// Mirrors the relevant instantiation of `x11.Window.getWindowProperty`.
fn (mut self X11Window) get_window_property_motif(name XAtom, typ XAtom, mut result MotifWMHints) ! {
	mut actual_type_return := XAtom(0)
	mut actual_format_return := 0
	mut nitems_return := u64(0)
	mut bytes_after_return := u64(0)
	mut prop_return := voidptr(0)

	code := C.XGetWindowProperty(self.app.display, self.xid, name, 0, i64(max_i64), 0, typ, &actual_type_return, &actual_format_return, &nitems_return, &bytes_after_return, &prop_return)
	if code != x_success {
		return error('request failed')
	}
	if actual_type_return == x_none {
		return error('property not found')
	}
	if typ != actual_type_return {
		return error('property type mismatch')
	}
	if prop_format_32 != actual_format_return {
		return error('property format mismatch')
	}

	unsafe {
		result = *(&MotifWMHints(prop_return))
	}
	C.XFree(prop_return)
}

// change_property_region writes a Region property (format 32) in replace mode.
// Mirrors the relevant instantiation of `x11.Window.changeProperty`.
fn (mut self X11Window) change_property_region(name XAtom, typ XAtom, value &Region) ! {
	// Region has 4 c_long fields; each c_long is one format-32 element.
	nelements := int(sizeof(Region) / sizeof(i64))
	status := C.XChangeProperty(self.app.display, self.xid, name, typ, prop_format_32, prop_mode_replace, unsafe { &u8(value) }, nelements)
	// Xlib's XChangeProperty returns 1 on success.
	if status == 0 {
		return error('request failed')
	}
}

// change_property_motif writes a MotifWMHints property (format 32) in replace
// mode. Mirrors the relevant instantiation of `x11.Window.changeProperty`.
fn (mut self X11Window) change_property_motif(name XAtom, typ XAtom, mut value MotifWMHints) ! {
	nelements := int(sizeof(MotifWMHints) / sizeof(i64))
	status := C.XChangeProperty(self.app.display, self.xid, name, typ, prop_format_32, prop_mode_replace, unsafe { &u8(value) }, nelements)
	if status == 0 {
		return error('request failed')
	}
}

// delete_property removes a property. Mirrors `x11.Window.deleteProperty`.
fn (mut self X11Window) delete_property(name XAtom) ! {
	status := C.XDeleteProperty(self.app.display, self.xid, name)
	if status == 0 {
		return error('request failed')
	}
}

// max_i64 is the maximum c_long value, used as XGetWindowProperty's length.
const max_i64 = i64(9223372036854775807)

// blur_enabled reports whether the given config background_blur value enables
fn blur_enabled(blur configpkg.BackgroundBlur) bool {
	return blur.enabled()
}
