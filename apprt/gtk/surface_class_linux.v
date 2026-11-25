@[has_globals]
module gtk

// surface_class_linux.v - The GObject Surface *widget* class for the GTK apprt.
//
// Translated from ghostty/src/apprt/gtk/class/surface.zig.
//
// This is the core GTK4 GObject widget that hosts the terminal: a GtkGLArea
// for rendering plus a set of input event controllers (key/mouse/scroll/focus)
// that build input events and forward them to the core surface. In ghostty
// this is a `GhosttySurface` GObject class defined with a `.ui`/blueprint
// template, GObject property/signal registration and template-child bindings.
//
// This port registers the GObject subclass and builds the translated portion
// of the blueprint programmatically. This `gtk` submodule CANNOT import
// witty's root `module main` where the real core `Surface` lives. Therefore:
//
//   * The class is modeled as a plain V struct `SurfaceWidget` that wraps the
//     GObject/GtkWidget pointer and holds the fields that were in the Zig
//     `Private` struct. Methods are `pub fn` on that struct. (The name is
//     `SurfaceWidget`, not `Surface`, to avoid colliding with the apprt
//     adapter `Surface` in surface_linux.v.)
//   * Blueprint children and callbacks are created and connected explicitly;
//     all native GObject properties, signals, and GtkScrollable overrides are
//     registered through the equivalent C API.
//   * Calls into the core surface dispatch to the real `core.Surface` (see
//     core/surface.v). Signatures are kept faithful.
//
// What is genuinely TRANSLATED: the GLArea realize/unrealize/render/resize
// setup, the input event handlers (key press/release, mouse down/up/motion/
// leave, scroll vertical/horizontal), the input-method state machine, clipboard
// get/request/set structure, cursor/title/mouse-shape/focus handling, and the
// Gtk.Scrollable adjustment plumbing. Keyboard handling reuses witty's input
// types (input.Key / input.Mods) and key_linux.v (key_from_keyval /
// translate_mods).

import apprt
import buildcfg
import core
import configpkg
import input
import terminal
import osc
import internal_os
import font
import log
import math
import os

// --- New C bindings unique to this file -----------------------------------
//
// GtkGLArea / GtkEventController* / GtkGesture* / GdkClipboard functions that
// aren't declared elsewhere in the module. All opaque handles are `voidptr`
// aliases (matching the module convention in c_gtk_linux.v). We grep-checked
// that none of these `fn C.` decls already exist in the module.

// GtkGLArea*.
pub type GtkGLArea = voidptr

// GtkEventControllerKey*.
pub type GtkEventControllerKey = voidptr

// GtkEventControllerMotion*.
pub type GtkEventControllerMotion = voidptr

// GtkEventControllerScroll*.
pub type GtkEventControllerScroll = voidptr

// GtkEventControllerFocus*.
pub type GtkEventControllerFocus = voidptr

// GtkGestureClick*.
pub type GtkGestureClick = voidptr

// GtkIMContext* / GtkIMMulticontext*.
pub type GtkIMContext = voidptr

// GdkClipboard*.
pub type GdkClipboard = voidptr

// GdkContentProvider* / GdkContentFormats*.
pub type GdkContentProvider = voidptr

pub type GdkContentFormats = voidptr

// GtkAdjustment*.
pub type GtkAdjustment = voidptr

// GSignalGroup* used to reconnect the vertical adjustment callback whenever
// GtkScrollable replaces its adjustment.
pub type GSignalGroup = voidptr

// GtkScrollablePolicy mirrors GTK_SCROLL_MINIMUM / GTK_SCROLL_NATURAL.
pub enum GtkScrollablePolicy as i32 {
	minimum
	natural
}

// GtkPopover* / GMenu* handles used by the surface context menu.
pub type GtkPopover = voidptr

pub type GMenu = voidptr

pub type GMenuModel = voidptr

// AdwStatusPage* used for the OpenGL initialization error page.
pub type AdwStatusPage = voidptr

// GNotification* / GIcon* used for desktop notifications.
pub type GNotification = voidptr

pub type GIcon = voidptr

// GtkMediaFile* / GtkMediaStream* and GFile* used for audio bells.
pub type GtkMediaFile = voidptr

pub type GtkMediaStream = voidptr

pub type GFile = voidptr

// GtkGLArea
fn C.gtk_gl_area_queue_render(area GtkGLArea)

fn C.gtk_gl_area_make_current(area GtkGLArea)

fn C.gtk_gl_area_get_error(area GtkGLArea) GError

fn C.gtk_gl_area_set_allowed_apis(area GtkGLArea, apis int)

// GtkWidget (extra helpers not in c_gtk_linux.v)
fn C.gtk_widget_has_focus(widget GtkWidget) bool

fn C.gtk_widget_set_cursor_from_name(widget GtkWidget, name &char)

fn C.gtk_widget_set_visible(widget GtkWidget, visible bool)

fn C.gtk_widget_add_css_class(widget GtkWidget, css_class &char)

fn C.gtk_widget_remove_css_class(widget GtkWidget, css_class &char)

fn C.gtk_widget_get_clipboard(widget GtkWidget) GdkClipboard

fn C.gtk_widget_get_primary_clipboard(widget GtkWidget) GdkClipboard

fn C.gtk_widget_add_controller(widget GtkWidget, controller voidptr)

// GtkDropTarget* is a gtk.EventController subclass.
pub type GtkDropTarget = voidptr

// GSList is a glib.SList*, the singly linked list gdk.FileList hands back.
@[typedef]
struct C.GSList {
	data voidptr
	next &C.GSList = unsafe { nil }
}

fn C.gtk_drop_target_new(type_ GType, actions u32) GtkDropTarget

fn C.gtk_drop_target_set_gtypes(target GtkDropTarget, types &GType, n_types uint)

fn C.gdk_file_list_get_type() GType

fn C.gdk_file_list_get_files(file_list voidptr) &C.GSList

fn C.g_slist_free(list &C.GSList)

fn C.g_file_get_type() GType

// GDK_ACTION_COPY. The drop target only ever copies.
const gdk_action_copy = u32(1)

// G_TYPE_INVALID.
const g_type_invalid = GType(0)

// G_TYPE_NONE, the return type of every void signal.
const g_type_none = GType(1 << 2)

fn C.gtk_widget_set_halign(widget GtkWidget, align int)

fn C.gtk_widget_set_valign(widget GtkWidget, align int)

fn C.gtk_adjustment_get_type() GType

fn C.gtk_adjustment_get_value(adjustment GtkAdjustment) f64

fn C.gtk_adjustment_get_upper(adjustment GtkAdjustment) f64

fn C.gtk_adjustment_get_page_size(adjustment GtkAdjustment) f64

fn C.gtk_adjustment_configure(adjustment GtkAdjustment, value f64, lower f64, upper f64, step_increment f64, page_increment f64, page_size f64)

fn C.gtk_scrollable_get_type() GType

// GAction state used by the per-surface action group.
fn C.g_action_get_state(action GAction) GVariant

fn C.g_simple_action_set_state(action GSimpleAction, value GVariant)

fn C.g_variant_get_boolean(value GVariant) bool

fn C.g_variant_new_uint64(value u64) GVariant

// GNotification
fn C.g_notification_new(title &char) GNotification

fn C.g_notification_set_body(notification GNotification, body &char)

fn C.g_notification_set_icon(notification GNotification, icon GIcon)

fn C.g_notification_set_default_action_and_target_value(notification GNotification, action &char, target GVariant)

fn C.g_themed_icon_new(iconname &char) GIcon

fn C.gtk_widget_activate_action_variant(widget GtkWidget, name &char, args GVariant) bool

// GtkMediaFile / GtkMediaStream
fn C.gtk_media_file_new_for_filename(filename &char) GtkMediaFile

fn C.gtk_media_file_get_file(media_file GtkMediaFile) GFile

fn C.gtk_media_stream_set_volume(stream GtkMediaStream, volume f64)

fn C.gtk_media_stream_play(stream GtkMediaStream)

fn C.gtk_media_stream_get_error(stream GtkMediaStream) GError

fn C.g_file_get_path(file GFile) &char

fn C.g_signal_group_new(target_type GType) GSignalGroup

fn C.g_signal_group_connect_data(self GSignalGroup, detailed_signal &char, c_handler GCallback, data voidptr, notify voidptr, flags int)

fn C.g_signal_group_set_target(self GSignalGroup, target GObject)

fn C.g_signal_group_block(self GSignalGroup)

fn C.g_signal_group_unblock(self GSignalGroup)

// GtkIMContext
fn C.gtk_im_context_filter_keypress(context GtkIMContext, event GdkEvent) bool

fn C.gtk_im_context_focus_in(context GtkIMContext)

fn C.gtk_im_context_focus_out(context GtkIMContext)

fn C.gtk_im_context_reset(context GtkIMContext)

fn C.gtk_im_context_set_client_widget(context GtkIMContext, widget GtkWidget)

fn C.gtk_im_context_get_preedit_string(context GtkIMContext, str &&char, attrs voidptr, cursor_pos voidptr)

@[typedef]
pub struct C.GdkRectangle {
pub mut:
	x      int
	y      int
	width  int
	height int
}

fn C.gtk_im_context_set_cursor_location(context GtkIMContext, area &C.GdkRectangle)

fn C.gtk_im_context_activate_osk(context GtkIMContext, event GdkEvent) bool

// Event controllers and gestures.
fn C.gtk_event_controller_key_new() GtkEventControllerKey

fn C.gtk_event_controller_focus_new() GtkEventControllerFocus

fn C.gtk_event_controller_motion_new() GtkEventControllerMotion

fn C.gtk_event_controller_scroll_new(flags int) GtkEventControllerScroll

fn C.gtk_event_controller_scroll_get_unit(controller GtkEventControllerScroll) int

fn C.gtk_event_controller_get_current_event(controller voidptr) GdkEvent

fn C.gtk_gesture_click_new() GtkGestureClick

fn C.gtk_gesture_single_set_button(gesture voidptr, button u32)

fn C.gtk_gesture_single_get_current_button(gesture voidptr) u32

// GdkEvent
fn C.gdk_event_get_modifier_state(event GdkEvent) u32

fn C.gdk_surface_get_scale_factor(surface GdkSurface) int
fn C.gdk_display_get_monitor_at_surface(display GdkDisplay, surface GdkSurface) voidptr

fn C.gdk_key_event_get_consumed_modifiers(event GdkEvent) u32

// GdkClipboard
fn C.gdk_clipboard_set_text(clipboard GdkClipboard, text &char)

fn C.gdk_clipboard_set_content(clipboard GdkClipboard, provider GdkContentProvider) bool

fn C.gdk_clipboard_get_formats(clipboard GdkClipboard) GdkContentFormats

fn C.gdk_clipboard_read_text_async(clipboard GdkClipboard, cancellable voidptr, callback GCallback, user_data voidptr)

fn C.gdk_clipboard_read_text_finish(clipboard GdkClipboard, result GAsyncResult, error &GError) &char

fn C.gdk_content_formats_contain_gtype(formats GdkContentFormats, type_ GType) bool

fn C.gdk_content_provider_new_for_bytes(mime_type &char, bytes GBytes) GdkContentProvider

fn C.gdk_content_provider_new_union(providers &GdkContentProvider, n_providers uint) GdkContentProvider

fn C.adw_bin_new() AdwBin

fn C.gtk_gl_area_new() GtkGLArea

fn C.gtk_gl_area_set_has_stencil_buffer(area GtkGLArea, has_stencil_buffer int)

fn C.gtk_gl_area_set_has_depth_buffer(area GtkGLArea, has_depth_buffer int)

fn C.gtk_overlay_new() GtkWidget

fn C.gtk_overlay_set_child(overlay GtkWidget, child GtkWidget)

fn C.gtk_overlay_add_overlay(overlay GtkWidget, widget GtkWidget)

fn C.gtk_revealer_new() GtkWidget

fn C.gtk_revealer_set_child(revealer GtkWidget, child GtkWidget)

fn C.gtk_revealer_set_reveal_child(revealer GtkWidget, reveal_child bool)

fn C.gtk_revealer_set_transition_type(revealer GtkWidget, transition int)

fn C.gtk_revealer_set_transition_duration(revealer GtkWidget, duration u32)

fn C.gtk_progress_bar_set_fraction(progress_bar GtkWidget, fraction f64)

fn C.gtk_progress_bar_pulse(progress_bar GtkWidget)

fn C.gtk_image_new_from_icon_name(icon_name &char) GtkWidget

fn C.gtk_drawing_area_new() GtkWidget

fn C.gtk_widget_set_can_target(widget GtkWidget, can_target bool)

fn C.gtk_popover_set_has_arrow(popover GtkPopover, has_arrow int)

fn C.gtk_popover_set_pointing_to(popover GtkPopover, rect &C.GdkRectangle)

fn C.gtk_popover_popup(popover GtkPopover)

fn C.g_menu_new() GMenu

fn C.g_menu_append(menu GMenu, label &char, detailed_action &char)

fn C.g_menu_append_section(menu GMenu, label &char, section GMenuModel)

fn C.g_menu_append_submenu(menu GMenu, label &char, submenu GMenuModel)

fn C.adw_status_page_new() AdwStatusPage

fn C.adw_status_page_set_icon_name(page AdwStatusPage, icon_name &char)

fn C.adw_status_page_set_title(page AdwStatusPage, title &char)

fn C.adw_status_page_set_description(page AdwStatusPage, description &char)

fn C.adw_status_page_set_child(page AdwStatusPage, child GtkWidget)

fn C.gtk_link_button_new_with_label(uri &char, label &char) GtkWidget

fn C.gtk_im_multicontext_new() GtkIMContext

fn C.gtk_widget_set_focusable(widget GtkWidget, focusable int)

fn C.gtk_widget_set_focus_on_click(widget GtkWidget, focus_on_click int)

const gtk_event_controller_scroll_vertical = int(1)
const gtk_event_controller_scroll_horizontal = int(2)
const gdk_scroll_unit_surface = int(1)
const gdk_gl_api_gl = int(1)

__global g_terminal_surface_type = GType(0)

// The instance-private offset: the size until class_init adjusts it, then
// the (negative) offset from the instance. Mirrors zig-gobject's `Private.offset`.
__global g_terminal_surface_priv_offset = int(0)
__global g_surface_size_type = GType(0)
__global g_font_desired_size_type = GType(0)
__global g_mouse_shape_type = GType(0)
__global g_mouse_shape_values [35]C.GEnumValue
__global g_surface_pspec_bell_ringing = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_config = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_child_exited = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_default_size = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_error = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_font_size_request = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_focused = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_key_sequence = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_key_table = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_min_size = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_mouse_shape = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_mouse_hidden = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_mouse_hover_url = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_pwd = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_title = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_title_override = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_zoom = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_is_split = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_readonly = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_hadjustment = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_vadjustment = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_hscroll_policy = &C.GParamSpec(unsafe { nil })
__global g_surface_pspec_vscroll_policy = &C.GParamSpec(unsafe { nil })

struct C.GhosttySurfacePrivate {
mut:
	wrapper voidptr
}

const surface_prop_bell_ringing = u32(1)
const surface_prop_config = u32(2)
const surface_prop_child_exited = u32(3)
const surface_prop_default_size = u32(4)
const surface_prop_error = u32(5)
const surface_prop_font_size_request = u32(6)
const surface_prop_focused = u32(7)
const surface_prop_key_sequence = u32(8)
const surface_prop_key_table = u32(9)
const surface_prop_min_size = u32(10)
const surface_prop_mouse_shape = u32(11)
const surface_prop_mouse_hidden = u32(12)
const surface_prop_mouse_hover_url = u32(13)
const surface_prop_pwd = u32(14)
const surface_prop_title = u32(15)
const surface_prop_title_override = u32(16)
const surface_prop_zoom = u32(17)
const surface_prop_is_split = u32(18)
const surface_prop_readonly = u32(19)
const surface_prop_hadjustment = u32(20)
const surface_prop_vadjustment = u32(21)
const surface_prop_hscroll_policy = u32(22)
const surface_prop_vscroll_policy = u32(23)

// defineProperty always marks its compile-time strings static. None of the
// Surface properties at the pinned revision use explicit-notify.
const surface_param_static_strings = int(32 | 64 | 128)

fn surface_size_boxed_copy(value voidptr) voidptr {
	if isnil(value) {
		return unsafe { nil }
	}
	size := unsafe { &Size(value) }
	return voidptr(&Size{
		width:  size.width
		height: size.height
	})
}

fn surface_size_boxed_free(value voidptr) {
	if !isnil(value) {
		unsafe { free(value) }
	}
}

fn surface_size_get_type() GType {
	if g_surface_size_type == GType(0) {
		g_surface_size_type = C.g_boxed_type_register_static(c'GhosttySurfaceSize', voidptr(surface_size_boxed_copy), voidptr(surface_size_boxed_free))
	}
	return g_surface_size_type
}

fn font_desired_size_boxed_copy(value voidptr) voidptr {
	if isnil(value) {
		return unsafe { nil }
	}
	size := unsafe { &font.DesiredSize(value) }
	return voidptr(&font.DesiredSize{
		points: size.points
		xdpi:   size.xdpi
		ydpi:   size.ydpi
	})
}

fn font_desired_size_boxed_free(value voidptr) {
	if !isnil(value) {
		unsafe { free(value) }
	}
}

fn font_desired_size_get_type() GType {
	if g_font_desired_size_type == GType(0) {
		g_font_desired_size_type = C.g_boxed_type_register_static(c'GhosttyFontDesiredSize', voidptr(font_desired_size_boxed_copy), voidptr(font_desired_size_boxed_free))
	}
	return g_font_desired_size_type
}

fn mouse_shape_get_type() GType {
	if g_mouse_shape_type == GType(0) {
		g_mouse_shape_values[0] = C.GEnumValue{ value: int(terminal.MouseShape.default_), value_name: c'default', value_nick: c'default' }
		g_mouse_shape_values[1] = C.GEnumValue{ value: int(terminal.MouseShape.context_menu), value_name: c'context_menu', value_nick: c'context_menu' }
		g_mouse_shape_values[2] = C.GEnumValue{ value: int(terminal.MouseShape.help), value_name: c'help', value_nick: c'help' }
		g_mouse_shape_values[3] = C.GEnumValue{ value: int(terminal.MouseShape.pointer), value_name: c'pointer', value_nick: c'pointer' }
		g_mouse_shape_values[4] = C.GEnumValue{ value: int(terminal.MouseShape.progress), value_name: c'progress', value_nick: c'progress' }
		g_mouse_shape_values[5] = C.GEnumValue{ value: int(terminal.MouseShape.wait), value_name: c'wait', value_nick: c'wait' }
		g_mouse_shape_values[6] = C.GEnumValue{ value: int(terminal.MouseShape.cell), value_name: c'cell', value_nick: c'cell' }
		g_mouse_shape_values[7] = C.GEnumValue{ value: int(terminal.MouseShape.crosshair), value_name: c'crosshair', value_nick: c'crosshair' }
		g_mouse_shape_values[8] = C.GEnumValue{ value: int(terminal.MouseShape.text), value_name: c'text', value_nick: c'text' }
		g_mouse_shape_values[9] = C.GEnumValue{ value: int(terminal.MouseShape.vertical_text), value_name: c'vertical_text', value_nick: c'vertical_text' }
		g_mouse_shape_values[10] = C.GEnumValue{ value: int(terminal.MouseShape.alias), value_name: c'alias', value_nick: c'alias' }
		g_mouse_shape_values[11] = C.GEnumValue{ value: int(terminal.MouseShape.copy), value_name: c'copy', value_nick: c'copy' }
		g_mouse_shape_values[12] = C.GEnumValue{ value: int(terminal.MouseShape.move), value_name: c'move', value_nick: c'move' }
		g_mouse_shape_values[13] = C.GEnumValue{ value: int(terminal.MouseShape.no_drop), value_name: c'no_drop', value_nick: c'no_drop' }
		g_mouse_shape_values[14] = C.GEnumValue{ value: int(terminal.MouseShape.not_allowed), value_name: c'not_allowed', value_nick: c'not_allowed' }
		g_mouse_shape_values[15] = C.GEnumValue{ value: int(terminal.MouseShape.grab), value_name: c'grab', value_nick: c'grab' }
		g_mouse_shape_values[16] = C.GEnumValue{ value: int(terminal.MouseShape.grabbing), value_name: c'grabbing', value_nick: c'grabbing' }
		g_mouse_shape_values[17] = C.GEnumValue{ value: int(terminal.MouseShape.all_scroll), value_name: c'all_scroll', value_nick: c'all_scroll' }
		g_mouse_shape_values[18] = C.GEnumValue{ value: int(terminal.MouseShape.col_resize), value_name: c'col_resize', value_nick: c'col_resize' }
		g_mouse_shape_values[19] = C.GEnumValue{ value: int(terminal.MouseShape.row_resize), value_name: c'row_resize', value_nick: c'row_resize' }
		g_mouse_shape_values[20] = C.GEnumValue{ value: int(terminal.MouseShape.n_resize), value_name: c'n_resize', value_nick: c'n_resize' }
		g_mouse_shape_values[21] = C.GEnumValue{ value: int(terminal.MouseShape.e_resize), value_name: c'e_resize', value_nick: c'e_resize' }
		g_mouse_shape_values[22] = C.GEnumValue{ value: int(terminal.MouseShape.s_resize), value_name: c's_resize', value_nick: c's_resize' }
		g_mouse_shape_values[23] = C.GEnumValue{ value: int(terminal.MouseShape.w_resize), value_name: c'w_resize', value_nick: c'w_resize' }
		g_mouse_shape_values[24] = C.GEnumValue{ value: int(terminal.MouseShape.ne_resize), value_name: c'ne_resize', value_nick: c'ne_resize' }
		g_mouse_shape_values[25] = C.GEnumValue{ value: int(terminal.MouseShape.nw_resize), value_name: c'nw_resize', value_nick: c'nw_resize' }
		g_mouse_shape_values[26] = C.GEnumValue{ value: int(terminal.MouseShape.se_resize), value_name: c'se_resize', value_nick: c'se_resize' }
		g_mouse_shape_values[27] = C.GEnumValue{ value: int(terminal.MouseShape.sw_resize), value_name: c'sw_resize', value_nick: c'sw_resize' }
		g_mouse_shape_values[28] = C.GEnumValue{ value: int(terminal.MouseShape.ew_resize), value_name: c'ew_resize', value_nick: c'ew_resize' }
		g_mouse_shape_values[29] = C.GEnumValue{ value: int(terminal.MouseShape.ns_resize), value_name: c'ns_resize', value_nick: c'ns_resize' }
		g_mouse_shape_values[30] = C.GEnumValue{ value: int(terminal.MouseShape.nesw_resize), value_name: c'nesw_resize', value_nick: c'nesw_resize' }
		g_mouse_shape_values[31] = C.GEnumValue{ value: int(terminal.MouseShape.nwse_resize), value_name: c'nwse_resize', value_nick: c'nwse_resize' }
		g_mouse_shape_values[32] = C.GEnumValue{ value: int(terminal.MouseShape.zoom_in), value_name: c'zoom_in', value_nick: c'zoom_in' }
		g_mouse_shape_values[33] = C.GEnumValue{ value: int(terminal.MouseShape.zoom_out), value_name: c'zoom_out', value_nick: c'zoom_out' }
		g_mouse_shape_values[34] = C.GEnumValue{ value: 0, value_name: &char(unsafe { nil }), value_nick: &char(unsafe { nil }) }
		g_mouse_shape_type = C.g_enum_register_static(c'GhosttyMouseShape', &g_mouse_shape_values[0])
	}
	return g_mouse_shape_type
}

fn terminal_surface_priv(obj voidptr) &C.GhosttySurfacePrivate {
	return &C.GhosttySurfacePrivate(instance_private(obj, g_terminal_surface_priv_offset))
}

fn terminal_surface_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := terminal_surface_priv(obj)
	if isnil(priv.wrapper) {
		match property_id {
			surface_prop_bell_ringing, surface_prop_child_exited, surface_prop_error,
			surface_prop_focused, surface_prop_mouse_hidden, surface_prop_zoom,
			surface_prop_is_split, surface_prop_readonly {
				C.g_value_set_boolean(value, 0)
			}
			surface_prop_mouse_shape {
				C.g_value_set_enum(value, int(terminal.MouseShape.text))
			}
			surface_prop_config {
				C.g_value_set_object(value, unsafe { nil })
			}
			surface_prop_default_size, surface_prop_font_size_request, surface_prop_key_sequence,
			surface_prop_key_table, surface_prop_min_size {
				C.g_value_set_boxed(value, unsafe { nil })
			}
			surface_prop_mouse_hover_url, surface_prop_pwd, surface_prop_title,
			surface_prop_title_override {
				C.g_value_set_string(value, &char(unsafe { nil }))
			}
			surface_prop_hadjustment, surface_prop_vadjustment {
				C.g_value_set_object(value, unsafe { nil })
			}
			surface_prop_hscroll_policy, surface_prop_vscroll_policy {
				C.g_value_set_enum(value, int(GtkScrollablePolicy.natural))
			}
			else {}
		}
		return
	}
	self := unsafe { &SurfaceWidget(priv.wrapper) }
	match property_id {
		surface_prop_bell_ringing { C.g_value_set_boolean(value, b2i(self.bell_ringing)) }
		surface_prop_config {
			C.g_value_set_object(value, if isnil(self.config) {
				unsafe { nil }
			} else {
				self.config.obj
			})
		}
		surface_prop_child_exited { C.g_value_set_boolean(value, b2i(self.child_exited)) }
		surface_prop_default_size {
			if size := self.default_size {
				C.g_value_set_boxed(value, &size)
			} else {
				C.g_value_set_boxed(value, unsafe { nil })
			}
		}
		surface_prop_error { C.g_value_set_boolean(value, b2i(self.error_state)) }
		surface_prop_font_size_request {
			if size := self.font_size_request {
				C.g_value_set_boxed(value, &size)
			} else {
				C.g_value_set_boxed(value, unsafe { nil })
			}
		}
		surface_prop_focused { C.g_value_set_boolean(value, b2i(self.focused)) }
		surface_prop_key_sequence {
			list := StringList.create(self.key_sequence)
			C.g_value_take_boxed(value, list)
		}
		surface_prop_key_table {
			list := StringList.create(self.key_tables)
			C.g_value_take_boxed(value, list)
		}
		surface_prop_min_size {
			if size := self.min_size {
				C.g_value_set_boxed(value, &size)
			} else {
				C.g_value_set_boxed(value, unsafe { nil })
			}
		}
		surface_prop_mouse_shape { C.g_value_set_enum(value, int(self.mouse_shape)) }
		surface_prop_mouse_hidden { C.g_value_set_boolean(value, b2i(self.mouse_hidden)) }
		surface_prop_mouse_hover_url {
			if text := self.mouse_hover_url {
				C.g_value_set_string(value, &char(text.str))
			} else {
				C.g_value_set_string(value, &char(unsafe { nil }))
			}
		}
		surface_prop_pwd {
			if text := self.pwd {
				C.g_value_set_string(value, &char(text.str))
			} else {
				C.g_value_set_string(value, &char(unsafe { nil }))
			}
		}
		surface_prop_title {
			if text := self.title {
				C.g_value_set_string(value, &char(text.str))
			} else {
				C.g_value_set_string(value, &char(unsafe { nil }))
			}
		}
		surface_prop_title_override {
			if text := self.title_override {
				C.g_value_set_string(value, &char(text.str))
			} else {
				C.g_value_set_string(value, &char(unsafe { nil }))
			}
		}
		surface_prop_zoom { C.g_value_set_boolean(value, b2i(self.zoom)) }
		surface_prop_is_split { C.g_value_set_boolean(value, b2i(self.is_split)) }
		surface_prop_readonly { C.g_value_set_boolean(value, b2i(self.get_readonly())) }
		surface_prop_hadjustment { C.g_value_set_object(value, self.hadj) }
		surface_prop_vadjustment { C.g_value_set_object(value, self.vadj) }
		surface_prop_hscroll_policy { C.g_value_set_enum(value, int(self.hscroll_policy)) }
		surface_prop_vscroll_policy { C.g_value_set_enum(value, int(self.vscroll_policy)) }
		else {}
	}
}

fn terminal_surface_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := terminal_surface_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &SurfaceWidget(priv.wrapper) }
	match property_id {
		surface_prop_bell_ringing {
			self.set_bell_ringing(C.g_value_get_boolean(value) != 0)
		}
		surface_prop_config {
			config_obj := C.g_value_get_object(value)
			if isnil(config_obj) {
				self.set_config_reference(none)
			} else {
				config_private := config_priv(config_obj)
				if !isnil(config_private.wrapper) {
					self.set_config_reference(unsafe { &Config(config_private.wrapper) })
				}
			}
		}
		surface_prop_child_exited {
			self.child_exited = C.g_value_get_boolean(value) != 0
		}
		surface_prop_default_size {
			boxed := C.g_value_get_boxed(value)
			if isnil(boxed) {
				self.default_size = none
			} else {
				self.set_default_size(unsafe { *&Size(boxed) })
			}
		}
		surface_prop_error {
			self.set_error(C.g_value_get_boolean(value) != 0)
		}
		surface_prop_font_size_request {
			boxed := C.g_value_get_boxed(value)
			if isnil(boxed) {
				self.font_size_request = none
			} else {
				self.font_size_request = unsafe { *&font.DesiredSize(boxed) }
			}
		}
		surface_prop_focused {
			self.focused = C.g_value_get_boolean(value) != 0
			self.sync_unfocused_split_overlay()
		}
		surface_prop_min_size {
			boxed := C.g_value_get_boxed(value)
			if isnil(boxed) {
				self.min_size = none
			} else {
				self.set_min_size(unsafe { *&Size(boxed) })
			}
		}
		surface_prop_mouse_shape {
			self.set_mouse_shape(unsafe { terminal.MouseShape(C.g_value_get_enum(value)) })
		}
		surface_prop_mouse_hidden {
			self.set_mouse_hidden(C.g_value_get_boolean(value) != 0)
		}
		surface_prop_mouse_hover_url {
			text := C.g_value_get_string(value)
			self.set_mouse_hover_url(if isnil(text) {
				?string(none)
			} else {
				?string(unsafe { cstring_to_vstring(text) })
			})
		}
		surface_prop_pwd {
			text := C.g_value_get_string(value)
			self.set_pwd(if isnil(text) {
				?string(none)
			} else {
				?string(unsafe { cstring_to_vstring(text) })
			})
		}
		surface_prop_title {
			text := C.g_value_get_string(value)
			self.set_title(if isnil(text) {
				?string(none)
			} else {
				?string(unsafe { cstring_to_vstring(text) })
			})
		}
		surface_prop_title_override {
			text := C.g_value_get_string(value)
			self.set_title_override(if isnil(text) {
				?string(none)
			} else {
				?string(unsafe { cstring_to_vstring(text) })
			})
		}
		surface_prop_zoom {
			self.zoom = C.g_value_get_boolean(value) != 0
		}
		surface_prop_is_split {
			self.set_is_split(C.g_value_get_boolean(value) != 0)
		}
		surface_prop_hadjustment {
			self.set_h_adjustment(GtkAdjustment(C.g_value_get_object(value)))
		}
		surface_prop_vadjustment {
			self.set_v_adjustment(GtkAdjustment(C.g_value_get_object(value)))
		}
		surface_prop_hscroll_policy {
			self.hscroll_policy = unsafe { GtkScrollablePolicy(C.g_value_get_enum(value)) }
		}
		surface_prop_vscroll_policy {
			self.vscroll_policy = unsafe { GtkScrollablePolicy(C.g_value_get_enum(value)) }
		}
		else {}
	}
}

fn terminal_surface_scrollable_init(iface voidptr, data voidptr) {
	_ = iface
	_ = data
}

fn terminal_surface_dispose(obj voidptr) {
	priv := terminal_surface_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &SurfaceWidget(priv.wrapper) }
		if !isnil(self.config) {
			self.config.unref()
			self.config = unsafe { nil }
		}
		if !isnil(self.vadj_signal_group) {
			C.g_signal_group_set_target(self.vadj_signal_group, unsafe { nil })
			object_unref(GObject(self.vadj_signal_group))
			self.vadj_signal_group = unsafe { nil }
		}
		if !isnil(self.hadj) {
			object_unref(GObject(self.hadj))
			self.hadj = unsafe { nil }
		}
		if !isnil(self.vadj) {
			object_unref(GObject(self.vadj))
			self.vadj = unsafe { nil }
		}
		if self.progress_bar_timer != 0 {
			if !C.g_source_remove(self.progress_bar_timer) {
				log.warn('unable to remove progress bar timer')
			}
			self.progress_bar_timer = 0
		}
		if self.idle_rechild != 0 {
			if !C.g_source_remove(self.idle_rechild) {
				log.warn('unable to remove idle source')
			}
			self.idle_rechild = 0
		}
		if self.pending_horizontal_scroll_reset != 0 {
			if !C.g_source_remove(self.pending_horizontal_scroll_reset) {
				log.warn('unable to remove pending horizontal scroll reset source')
			}
			self.pending_horizontal_scroll_reset = 0
		}
		C.adw_bin_set_child(AdwBin(obj), GtkWidget(unsafe { nil }))
		if !isnil(self.terminal_page) {
			object_unref(GObject(self.terminal_page))
			self.terminal_page = unsafe { nil }
		}
		if !isnil(self.error_page) {
			object_unref(GObject(self.error_page))
			self.error_page = unsafe { nil }
		}
		if !isnil(self.im_context) {
			object_unref(GObject(self.im_context))
			self.im_context = unsafe { nil }
		}
	}
	C.witty_gobject_call_parent_dispose(obj)
}

fn terminal_surface_finalize(obj voidptr) {
	mut priv := terminal_surface_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &SurfaceWidget(priv.wrapper) }
		if !isnil(self.inspector) {
			mut inspector_window := unsafe { self.inspector }
			inspector_window.close()
			self.inspector = unsafe { nil }
		}
		if self.has_core() {
			if !isnil(self.core_surface_ref) && !isnil(self.app) && !isnil(self.app.core_app) {
				mut app := unsafe { self.app.core_app }
				app.delete_surface(self.core_surface_ref)
			}
			mut core_surface := self.core_surface
			core_surface.deinit()
			self.core_surface = unsafe { nil }
			self.core_surface_ref = unsafe { nil }
		}
		self.clear_cgroup()
		self.mouse_hover_url = none
		self.default_size = none
		self.font_size_request = none
		self.min_size = none
		self.pwd = none
		self.title = none
		self.title_override = none
		self.key_sequence.clear()
		self.key_tables.clear()
		self.widget = unsafe { nil }
		priv.wrapper = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

fn terminal_surface_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_terminal_surface_priv_offset)
	_ = class_data
	C.witty_gobject_class_set_get_property(klass, voidptr(terminal_surface_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(terminal_surface_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(terminal_surface_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(terminal_surface_finalize))
	nil_str := &char(unsafe { nil })
	readwrite := g_param_readwrite | surface_param_static_strings
	readable := g_param_readable | surface_param_static_strings
	g_surface_pspec_bell_ringing = C.g_param_spec_boolean(c'bell-ringing', nil_str, nil_str, 0, readwrite)
	g_surface_pspec_config = C.g_param_spec_object(c'config', nil_str, nil_str, config_get_type(), readwrite)
	g_surface_pspec_child_exited = C.g_param_spec_boolean(c'child-exited', nil_str, nil_str, 0, readwrite)
	g_surface_pspec_default_size = C.g_param_spec_boxed(c'default-size', nil_str, nil_str, surface_size_get_type(), readwrite)
	g_surface_pspec_error = C.g_param_spec_boolean(c'error', nil_str, nil_str, 0, readwrite)
	g_surface_pspec_font_size_request = C.g_param_spec_boxed(c'font-size-request', nil_str, nil_str, font_desired_size_get_type(), readwrite)
	g_surface_pspec_focused = C.g_param_spec_boolean(c'focused', nil_str, nil_str, 0, readwrite)
	g_surface_pspec_key_sequence = C.g_param_spec_boxed(c'key-sequence', nil_str, nil_str, StringList.get_gobject_type(), readable)
	g_surface_pspec_key_table = C.g_param_spec_boxed(c'key-table', nil_str, nil_str, StringList.get_gobject_type(), readable)
	g_surface_pspec_min_size = C.g_param_spec_boxed(c'min-size', nil_str, nil_str, surface_size_get_type(), readwrite)
	g_surface_pspec_mouse_shape = C.g_param_spec_enum(c'mouse-shape', nil_str, nil_str, mouse_shape_get_type(), int(terminal.MouseShape.text), readwrite)
	g_surface_pspec_mouse_hidden = C.g_param_spec_boolean(c'mouse-hidden', nil_str, nil_str, 0, readwrite)
	g_surface_pspec_mouse_hover_url = C.g_param_spec_string(c'mouse-hover-url', nil_str, nil_str, nil_str, readwrite)
	g_surface_pspec_pwd = C.g_param_spec_string(c'pwd', nil_str, nil_str, nil_str, readwrite)
	g_surface_pspec_title = C.g_param_spec_string(c'title', nil_str, nil_str, nil_str, readwrite)
	g_surface_pspec_title_override = C.g_param_spec_string(c'title-override', nil_str, nil_str, nil_str, readwrite)
	g_surface_pspec_zoom = C.g_param_spec_boolean(c'zoom', nil_str, nil_str, 0, readwrite)
	g_surface_pspec_is_split = C.g_param_spec_boolean(c'is-split', nil_str, nil_str, 0, readwrite)
	g_surface_pspec_readonly = C.g_param_spec_boolean(c'readonly', nil_str, nil_str, 0, readable)
	C.g_object_class_install_property(klass, surface_prop_bell_ringing, g_surface_pspec_bell_ringing)
	C.g_object_class_install_property(klass, surface_prop_config, g_surface_pspec_config)
	C.g_object_class_install_property(klass, surface_prop_child_exited, g_surface_pspec_child_exited)
	C.g_object_class_install_property(klass, surface_prop_default_size, g_surface_pspec_default_size)
	C.g_object_class_install_property(klass, surface_prop_error, g_surface_pspec_error)
	C.g_object_class_install_property(klass, surface_prop_font_size_request, g_surface_pspec_font_size_request)
	C.g_object_class_install_property(klass, surface_prop_focused, g_surface_pspec_focused)
	C.g_object_class_install_property(klass, surface_prop_key_sequence, g_surface_pspec_key_sequence)
	C.g_object_class_install_property(klass, surface_prop_key_table, g_surface_pspec_key_table)
	C.g_object_class_install_property(klass, surface_prop_min_size, g_surface_pspec_min_size)
	C.g_object_class_install_property(klass, surface_prop_mouse_shape, g_surface_pspec_mouse_shape)
	C.g_object_class_install_property(klass, surface_prop_mouse_hidden, g_surface_pspec_mouse_hidden)
	C.g_object_class_install_property(klass, surface_prop_mouse_hover_url, g_surface_pspec_mouse_hover_url)
	C.g_object_class_install_property(klass, surface_prop_pwd, g_surface_pspec_pwd)
	C.g_object_class_install_property(klass, surface_prop_title, g_surface_pspec_title)
	C.g_object_class_install_property(klass, surface_prop_title_override, g_surface_pspec_title_override)
	C.g_object_class_install_property(klass, surface_prop_zoom, g_surface_pspec_zoom)
	C.g_object_class_install_property(klass, surface_prop_is_split, g_surface_pspec_is_split)
	C.g_object_class_install_property(klass, surface_prop_readonly, g_surface_pspec_readonly)
	C.g_object_class_override_property(klass, surface_prop_hadjustment, c'hadjustment')
	C.g_object_class_override_property(klass, surface_prop_vadjustment, c'vadjustment')
	C.g_object_class_override_property(klass, surface_prop_hscroll_policy, c'hscroll-policy')
	C.g_object_class_override_property(klass, surface_prop_vscroll_policy, c'vscroll-policy')
	g_surface_pspec_hadjustment = C.g_object_class_find_property(klass, c'hadjustment')
	g_surface_pspec_vadjustment = C.g_object_class_find_property(klass, c'vadjustment')
	g_surface_pspec_hscroll_policy = C.g_object_class_find_property(klass, c'hscroll-policy')
	g_surface_pspec_vscroll_policy = C.g_object_class_find_property(klass, c'vscroll-policy')
	for name in ['bell', 'close-request', 'clipboard-read', 'init', 'menu', 'present-request',
		'toggle-fullscreen', 'toggle-maximize'] {
		C.g_signal_new(&char(name.str), g_terminal_surface_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 0)
	}
	mut clipboard_type := g_type_int
	mut clipboard_text := g_type_string
	C.g_signal_new(c'clipboard-write', g_terminal_surface_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 2, clipboard_type, clipboard_text)
}

fn terminal_surface_instance_init(instance voidptr, klass voidptr) {
	_ = instance
	_ = klass
}

pub fn terminal_surface_get_type() GType {
	if g_terminal_surface_type == GType(0) {
		parent := C.adw_bin_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(terminal_surface_class_init)
			instance_init: voidptr(terminal_surface_instance_init)
		}
		g_terminal_surface_type = C.g_type_register_static(parent, c'GhosttySurface', &info, 0)
		g_terminal_surface_priv_offset = C.g_type_add_instance_private(g_terminal_surface_type, sizeof(C.GhosttySurfacePrivate))
		interface_info := C.GInterfaceInfo{
			interface_init: voidptr(terminal_surface_scrollable_init)
		}
		C.g_type_add_interface_static(g_terminal_surface_type, C.gtk_scrollable_get_type(), &interface_info)
	}
	return g_terminal_surface_type
}

// --- IMKeyEvent -----------------------------------------------------------

// IMKeyEvent is the state of the key event while doing IM composition.
// See key_event for detailed descriptions. Mirrors the Zig `IMKeyEvent`.
pub enum IMKeyEvent as u8 {
	// Not in a key event.
	false_
	// In a key event but im_composing was either true or false prior to the
	// calling IME processing. This is important to work around different input
	// methods calling commit and preedit end in a different order.
	composing
	not_composing
}

// Size is the simple dimensions struct used by various properties.
// Mirrors the Zig boxed `Surface.Size`.
pub struct Size {
pub mut:
	width  u32
	height u32
}

@[heap]
struct ClipboardReadRequest {
mut:
	surface &SurfaceWidget
	state   apprt.ClipboardRequest
}

// --- SurfaceWidget --------------------------------------------------------

// SurfaceWidget is the V model of the `GhosttySurface` GObject class. It wraps
// the GObject/GtkWidget pointer and carries the state that lived in the Zig
// `Private` struct. The GObject subclass and GtkScrollable interface are
// registered above; the translated blueprint is assembled in the constructor.
@[heap]
pub struct SurfaceWidget {
pub mut:
	// The GtkWidget (adw.Bin) pointer for this instance. In ghostty this is the
	// GObject parent instance; here we just hold the widget handle.
	widget GtkWidget = unsafe { nil }

	// Owning GTK objects and containers.
	app           &Application            = unsafe { nil }
	split_tree    &SplitTreeWidget        = unsafe { nil }
	context       apprt.NewSurfaceContext = .window
	init_options  core.SurfaceInitOptions
	terminal_page GtkWidget               = unsafe { nil }
	error_page    GtkWidget               = unsafe { nil }

	// The GLArea that renders the actual surface (template child).
	gl_area GtkGLArea = unsafe { nil }

	// The input method context (template child).
	im_context GtkIMContext = unsafe { nil }

	// URL hover labels and the right-click context menu from the surface
	// blueprint.
	url_left             GtkLabel            = unsafe { nil }
	url_right            GtkLabel            = unsafe { nil }
	context_menu         GtkPopover          = unsafe { nil }
	readonly_revealer    GtkWidget           = unsafe { nil }
	progress_bar_overlay GtkWidget           = unsafe { nil }
	bell_revealer        GtkWidget           = unsafe { nil }
	resize_overlay       &ResizeOverlay      = unsafe { nil }
	search_overlay       &SearchOverlay      = unsafe { nil }
	key_state_overlay    &KeyStateOverlay    = unsafe { nil }
	child_exited_overlay &SurfaceChildExited = unsafe { nil }
	unfocused_revealer   GtkWidget           = unsafe { nil }

	// The core surface backing this GTK surface. This starts out nil because it
	// can't be initialized until there is a realized GLArea. In ghostty this is
	// `?*core.Surface`; we model "unset" with `unsafe { nil }`.
	core_surface         &core.Surface = unsafe { nil }
	core_runtime_surface apprt.RuntimeSurface
	core_surface_ref     &core.SurfaceRef = unsafe { nil }

	// Weakly-owned terminal inspector window. The window clears this pointer
	// when it closes, matching Ghostty's InspectorWindow weak notification.
	inspector &InspectorWindow = unsafe { nil }

	// The apprt Surface adapter (see surface_linux.v).
	rt_surface Surface

	// The configuration this surface uses (the GhosttyConfig GObject wrapper).
	config &Config = unsafe { nil }

	// The cgroup created for this surface, if any.
	cgroup_path ?string

	// The default/min size for a window embedding this surface.
	default_size ?Size
	min_size     ?Size

	// The requested font size (only applies to initialization). This is a value
	// copy of Ghostty's boxed `?*font.face.DesiredSize`.
	font_size_request ?font.DesiredSize

	// The mouse shape to show for the surface.
	mouse_shape terminal.MouseShape = .text

	// Whether the mouse should be hidden as requested externally.
	mouse_hidden bool

	// The URL that the mouse is currently hovering over.
	mouse_hover_url ?string

	// The current working directory (reported externally by shell integration).
	pwd ?string

	// The terminal-set title and manually overridden title.
	title          ?string
	title_override ?string

	// The current focus state.
	focused bool = true

	// Whether this surface is "zoomed" (takes full bounds of a split view).
	zoom bool

	// Cached metrics for libwitty callbacks.
	size       apprt.SurfaceSize
	cursor_pos apprt.CursorPos

	// Input method state. All related to key input.
	in_keyevent  IMKeyEvent = .false_
	im_composing bool
	im_buf       []u8 = []u8{len: 128}
	im_len       int

	// True when we have a precision scroll in progress.
	precision_scroll bool

	// True when the child has exited.
	child_exited bool

	// True while the bell is ringing.
	bell_ringing bool

	// Removes stalled OSC progress reports after fifteen seconds.
	progress_bar_timer u32

	// True if this surface is in an error state (terminal non-functional).
	error_state  bool
	idle_rechild u32

	// True if the current surface is a split (for unfocused-split-* options).
	is_split bool

	// Whether primary paste (middle-click paste) is enabled.
	gtk_enable_primary_paste bool = true

	// Key state tracking for key sequences and tables.
	key_sequence []string
	key_tables   []string

	// Stateful actions local to this surface.
	action_group GSimpleActionGroup = unsafe { nil }

	// Gtk.Scrollable interface adjustments.
	hadj              GtkAdjustment       = unsafe { nil }
	vadj              GtkAdjustment       = unsafe { nil }
	hscroll_policy    GtkScrollablePolicy = .natural
	vscroll_policy    GtkScrollablePolicy = .natural
	vadj_signal_group GSignalGroup        = unsafe { nil }

	// How much pending horizontal scroll we have.
	pending_horizontal_scroll       f64
	pending_horizontal_scroll_reset u32

	// Async reads and confirmation dialogs retain their V payload until the
	// corresponding GLib callback completes.
	pending_clipboard_reads   []&ClipboardReadRequest
	pending_clipboard_dialogs []&ClipboardConfirmationDialog
}

// --- Basic accessors ------------------------------------------------------

// core returns the (optional) core surface. Mirrors `Surface.core`.
pub fn (self &SurfaceWidget) core() ?&core.Surface {
	if isnil(self.core_surface) {
		return none
	}
	return self.core_surface
}

// has_core reports whether the core surface has been initialized.
pub fn (self &SurfaceWidget) has_core() bool {
	return !isnil(self.core_surface)
}

// rt returns the apprt Surface adapter. Mirrors `Surface.rt`.
pub fn (mut self SurfaceWidget) rt() &Surface {
	return &self.rt_surface
}

fn (self &SurfaceWidget) notify_property(pspec &C.GParamSpec) {
	if !isnil(self.widget) && !isnil(pspec) {
		C.g_object_notify_by_pspec(self.widget, pspec)
	}
}

// set_parent captures inheritable state before the GLArea realizes. No parent
// pointer is retained, matching Ghostty's Surface.setParent.
pub fn (mut self SurfaceWidget) set_parent(parent &core.Surface, context apprt.NewSurfaceContext) {
	if self.has_core() {
		log.warn('setParent called after surface is already realized')
		return
	}
	self.context = context
	self.font_size_request = parent.font_size
	self.notify_property(g_surface_pspec_font_size_request)
	if isnil(self.config) {
		return
	}
	inherit_pwd := match context {
		.window { self.config.get().window_inherit_working_directory }
		.tab { self.config.get().tab_inherit_working_directory }
		.split { self.config.get().split_inherit_working_directory }
	}
	if inherit_pwd {
		self.set_pwd(parent.pwd())
	}
}

// redraw forces the surface to redraw itself. Mirrors `Surface.redraw`.
pub fn (self &SurfaceWidget) redraw() {
	C.gtk_gl_area_queue_render(self.gl_area)
}

// as_widget returns the underlying GtkWidget. Mirrors `self.as(gtk.Widget)`.
fn (self &SurfaceWidget) as_widget() GtkWidget {
	return self.widget
}

// --- Focus ----------------------------------------------------------------

// grab_focus focuses the input (GLArea) part of the surface.
// Mirrors `Surface.grabFocus`.
pub fn (self &SurfaceWidget) grab_focus() {
	C.gtk_widget_grab_focus(self.gl_area)
}

// get_focused returns the focus state. Mirrors `Surface.getFocused`.
pub fn (self &SurfaceWidget) get_focused() bool {
	return self.focused
}

// --- Content scale / size / cursor ----------------------------------------

// get_content_scale returns the content scale for the surface. Mirrors
// `Surface.getContentScale`. The GTK scale factor and gtk-xft-dpi scaling are
// combined, matching the Zig original.
pub fn (self &SurfaceWidget) get_content_scale() apprt.ContentScale {
	mut gtk_scale := f32(1.0)
	s := C.gtk_widget_get_scale_factor(self.gl_area)
	if s > 0 {
		gtk_scale = f32(s)
	} else {
		log.warn('gtk_widget_get_scale_factor returned a non-positive number: ${s}')
	}

	// Also scale using font-specific DPI (gtk-xft-dpi is font DPI * 1024).
	mut xft_dpi_scale := f32(1.0)
	if gtk_xft_dpi := gtk_setting_xft_dpi() {
		if gtk_xft_dpi > 0 {
			xft_dpi := f32(gtk_xft_dpi) / 1024.0
			xft_dpi_scale = xft_dpi / 96.0
		} else {
			log.warn('gtk-xft-dpi has invalid value (${gtk_xft_dpi}), using default')
		}
	} else {
		log.warn('gtk-xft-dpi was not set, using default value')
	}

	scale := gtk_scale * xft_dpi_scale
	return apprt.ContentScale{
		x: scale
		y: scale
	}
}

// get_size returns the cached surface size in pixels. Mirrors `Surface.getSize`.
pub fn (self &SurfaceWidget) get_size() apprt.SurfaceSize {
	return self.size
}

// get_cursor_pos returns the cached cursor position. Mirrors
// `Surface.getCursorPos`.
pub fn (self &SurfaceWidget) get_cursor_pos() apprt.CursorPos {
	return self.cursor_pos
}

// scaled_coordinates scales x/y by the GDK device scale factor. Mirrors
// `Surface.scaledCoordinates`.
fn (self &SurfaceWidget) scaled_coordinates(x f64, y f64) (f64, f64) {
	scale_factor := f64(C.gtk_widget_get_scale_factor(self.gl_area))
	return x * scale_factor, y * scale_factor
}

// --- Title / pwd ----------------------------------------------------------

// get_title returns the terminal-set title, if any. Mirrors `Surface.getTitle`.
pub fn (self &SurfaceWidget) get_title() ?string {
	return self.title
}

// set_title sets the terminal-set title (a copy). Mirrors `Surface.setTitle`.
pub fn (mut self SurfaceWidget) set_title(title ?string) {
	self.title = title
	self.notify_property(g_surface_pspec_title)
	self.sync_tab()
}

// set_title_override sets the manually overridden title. Mirrors
// `Surface.setTitleOverride`.
pub fn (mut self SurfaceWidget) set_title_override(title ?string) {
	self.title_override = title
	self.notify_property(g_surface_pspec_title_override)
	self.sync_tab()
}

// prompt_title asks for a manual surface-title override.
pub fn (mut self SurfaceWidget) prompt_title() {
	mut initial_value := ?string(none)
	if title := self.title_override {
		initial_value = title
	} else if title := self.title {
		initial_value = title
	}
	prompt_title_dialog(self.widget, self.config, i18n_('Change Terminal Title'), initial_value,
		GCallback(voidptr(surface_title_dialog_set_cb)))
}

// init_action_map registers the actions exposed by the surface context menu.
// Mirrors Surface.initActionMap.
fn (mut self SurfaceWidget) init_action_map() {
	actions := [
		Action.init('prompt-title', GCallback(voidptr(action_prompt_title)), unsafe { nil }),
		Action.init_stateful('notify-on-next-command-finish', GCallback(voidptr(action_notify_on_next_command_finish)), unsafe { nil }, C.g_variant_new_boolean(0)),
	]
	self.action_group = add_as_group(voidptr(self), self.widget, 'surface', actions)
}

// action_prompt_title is the source public action callback. V exposes the
// surface through GLib's user-data slot instead of a third typed parameter.
pub fn action_prompt_title(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	_ = parameter
	if isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	surface.perform_binding_action(input.ActionPromptSurfaceTitle{}) or {
		log.warn('unable to perform prompt title action err=${err}')
	}
}

// action_notify_on_next_command_finish is the source public stateful action
// callback with the same GLib user-data adaptation as action_prompt_title.
pub fn action_notify_on_next_command_finish(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = parameter
	_ = data
	if isnil(action) {
		return
	}
	state := C.g_action_get_state(GAction(action))
	if isnil(state) {
		return
	}
	defer {
		C.g_variant_unref(state)
	}
	bool_type := C.g_variant_type_new(c'b')
	is_bool := C.g_variant_is_of_type(state, bool_type)
	C.g_variant_type_free(bool_type)
	if !is_bool {
		return
	}
	C.g_simple_action_set_state(action, C.g_variant_new_boolean(if C.g_variant_get_boolean(state) {
		0
	} else {
		1
	}))
}

fn surface_title_dialog_set_cb(_ GObject, title &char, widget GtkWidget) {
	mut self := window_surface_wrapper(widget) or { return }
	self.set_title_override(title_override_from_entry(title))
}

// get_pwd returns the pwd, if any. Mirrors `Surface.getPwd`.
pub fn (self &SurfaceWidget) get_pwd() ?string {
	return self.pwd
}

// set_pwd sets the pwd (a copy). Mirrors `Surface.setPwd`.
pub fn (mut self SurfaceWidget) set_pwd(pwd ?string) {
	self.pwd = pwd
	self.notify_property(g_surface_pspec_pwd)
	self.sync_tab()
}

fn (self &SurfaceWidget) sync_tab() {
	if !isnil(self.split_tree) {
		self.split_tree.sync_tab()
	}
}

// --- Mouse shape / hidden / hover url --------------------------------------

// get_mouse_shape returns the mouse shape. Mirrors `Surface.getMouseShape`.
pub fn (self &SurfaceWidget) get_mouse_shape() terminal.MouseShape {
	return self.mouse_shape
}

// set_mouse_shape sets the mouse shape and applies it. Mirrors
// `Surface.setMouseShape` + `propMouseShape`.
pub fn (mut self SurfaceWidget) set_mouse_shape(shape terminal.MouseShape) {
	self.mouse_shape = shape
	self.notify_property(g_surface_pspec_mouse_shape)
	self.apply_mouse_shape()
}

// get_mouse_hidden returns whether the mouse is hidden. Mirrors
// `Surface.getMouseHidden`.
pub fn (self &SurfaceWidget) get_mouse_hidden() bool {
	return self.mouse_hidden
}

// set_mouse_hidden sets whether the mouse is hidden and applies it. Mirrors
// `Surface.setMouseHidden` + `propMouseHidden`.
pub fn (mut self SurfaceWidget) set_mouse_hidden(hidden bool) {
	self.mouse_hidden = hidden
	self.notify_property(g_surface_pspec_mouse_hidden)
	if self.mouse_hidden {
		C.gtk_widget_set_cursor_from_name(self.widget, c'none')
		return
	}
	self.apply_mouse_shape()
}

// apply_mouse_shape sets the widget cursor from the current mouse shape.
// The enum values use the W3C/GTK cursor names directly.
fn (self &SurfaceWidget) apply_mouse_shape() {
	if self.mouse_hidden {
		return
	}
	name := match self.mouse_shape {
		.default_ { c'default' }
		.context_menu { c'context-menu' }
		.help { c'help' }
		.pointer { c'pointer' }
		.progress { c'progress' }
		.wait { c'wait' }
		.cell { c'cell' }
		.crosshair { c'crosshair' }
		.text { c'text' }
		.vertical_text { c'vertical-text' }
		.alias { c'alias' }
		.copy { c'copy' }
		.move { c'move' }
		.no_drop { c'no-drop' }
		.not_allowed { c'not-allowed' }
		.grab { c'grab' }
		.grabbing { c'grabbing' }
		.all_scroll { c'all-scroll' }
		.col_resize { c'col-resize' }
		.row_resize { c'row-resize' }
		.n_resize { c'n-resize' }
		.e_resize { c'e-resize' }
		.s_resize { c's-resize' }
		.w_resize { c'w-resize' }
		.ne_resize { c'ne-resize' }
		.nw_resize { c'nw-resize' }
		.se_resize { c'se-resize' }
		.sw_resize { c'sw-resize' }
		.ew_resize { c'ew-resize' }
		.ns_resize { c'ns-resize' }
		.nesw_resize { c'nesw-resize' }
		.nwse_resize { c'nwse-resize' }
		.zoom_in { c'zoom-in' }
		.zoom_out { c'zoom-out' }
	}
	C.gtk_widget_set_cursor_from_name(self.widget, name)
}

// set_mouse_hover_url sets the hovered URL (a copy) and toggles the URL label.
// Mirrors `Surface.setMouseHoverUrl` + `propMouseHoverUrl`.
pub fn (mut self SurfaceWidget) set_mouse_hover_url(url ?string) {
	self.mouse_hover_url = url
	self.notify_property(g_surface_pspec_mouse_hover_url)
	text := url or { '' }
	if !isnil(self.url_left) {
		C.gtk_label_set_label(self.url_left, &char(text.str))
		C.gtk_widget_set_visible(GtkWidget(self.url_left), text.len > 0)
	}
	if !isnil(self.url_right) {
		C.gtk_label_set_label(self.url_right, &char(text.str))
	}
}

// --- Bell / error ---------------------------------------------------------

// get_bell_ringing returns whether the bell is ringing. Mirrors
// `Surface.getBellRinging`.
pub fn (self &SurfaceWidget) get_bell_ringing() bool {
	return self.bell_ringing
}

// set_bell_ringing sets the bell ringing state. Mirrors `Surface.setBellRinging`.
pub fn (mut self SurfaceWidget) set_bell_ringing(ringing bool) {
	C.g_object_freeze_notify(self.widget)
	defer {
		C.g_object_thaw_notify(self.widget)
	}
	// Logic around bell reaction happens on every event even if we're already
	// ringing.
	if ringing {
		self.ring_bell()
		if self.focused {
			return
		}
	}

	// Property change only happens on actual state change.
	if self.bell_ringing == ringing {
		return
	}
	self.bell_ringing = ringing
	self.notify_property(g_surface_pspec_bell_ringing)
	self.sync_bell_border_overlay()
	self.sync_tab()
}

fn (self &SurfaceWidget) sync_bell_border_overlay() {
	if isnil(self.bell_revealer) {
		return
	}
	if !self.bell_ringing {
		C.gtk_revealer_set_reveal_child(self.bell_revealer, false)
		return
	}
	if isnil(self.config) {
		log.warn('config unavailable for computing whether border should be shown, likely bug')
		C.gtk_revealer_set_reveal_child(self.bell_revealer, false)
		return
	}
	show := self.config.get().bell_features.border()
	C.gtk_revealer_set_reveal_child(self.bell_revealer, show)
}

// get_readonly reads the canonical state from the core, matching the pinned
// read-only GObject property getter.
pub fn (self &SurfaceWidget) get_readonly() bool {
	if !self.has_core() {
		return false
	}
	return self.core_surface.readonly
}

// set_readonly mirrors Surface.setReadonly and the readonly blueprint binding.
pub fn (mut self SurfaceWidget) set_readonly(_ apprt.Readonly) bool {
	self.notify_property(g_surface_pspec_readonly)
	if !isnil(self.readonly_revealer) {
		C.gtk_revealer_set_reveal_child(self.readonly_revealer, self.get_readonly())
	}
	return true
}

// set_is_split mirrors the split-tree to surface property binding.
pub fn (mut self SurfaceWidget) set_is_split(is_split bool) {
	if self.is_split == is_split {
		return
	}
	self.is_split = is_split
	self.notify_property(g_surface_pspec_is_split)
	self.sync_unfocused_split_overlay()
}

fn (self &SurfaceWidget) sync_unfocused_split_overlay() {
	if isnil(self.unfocused_revealer) {
		return
	}
	search_active := !isnil(self.search_overlay) && self.search_overlay.get_search_active()
	C.gtk_revealer_set_reveal_child(self.unfocused_revealer, self.is_split && !self.focused
		&& !search_active)
}

// set_progress_report mirrors Surface.setProgressReport. Every update resets
// the bad-actor timeout; remove hides immediately while all other states show.
pub fn (mut self SurfaceWidget) set_progress_report(value osc.ProgressReport) {
	if self.progress_bar_timer != 0 {
		if !C.g_source_remove(self.progress_bar_timer) {
			log.warn('unable to remove progress bar timer')
		}
		self.progress_bar_timer = 0
	}

	if isnil(self.progress_bar_overlay) {
		return
	}

	match value.state {
		.remove {
			C.gtk_widget_set_visible(self.progress_bar_overlay, false)
			return
		}
		.set {
			C.gtk_widget_remove_css_class(self.progress_bar_overlay, c'error')
			if progress := value.progress {
				C.gtk_progress_bar_set_fraction(self.progress_bar_overlay, compute_fraction(progress))
			} else {
				C.gtk_progress_bar_pulse(self.progress_bar_overlay)
			}
		}
		.err_state {
			C.gtk_widget_add_css_class(self.progress_bar_overlay, c'error')
			if progress := value.progress {
				C.gtk_progress_bar_set_fraction(self.progress_bar_overlay, compute_fraction(progress))
			} else {
				C.gtk_progress_bar_pulse(self.progress_bar_overlay)
			}
		}
		.indeterminate {
			C.gtk_progress_bar_pulse(self.progress_bar_overlay)
		}
		.pause {
			if progress := value.progress {
				C.gtk_progress_bar_set_fraction(self.progress_bar_overlay, compute_fraction(progress))
			}
		}
	}

	C.gtk_widget_set_visible(self.progress_bar_overlay, true)
	self.progress_bar_timer = C.g_timeout_add(15_000, voidptr(surface_progress_bar_timer_cb), voidptr(self))
}

// compute_fraction converts an OSC progress percentage to the 0..1 fraction a
// GtkProgressBar takes. The value is clamped because a report can carry any
// byte, and a fraction above 1.0 is not meaningful to GTK.
fn compute_fraction(progress u8) f64 {
	clamped := if progress > 100 { u8(100) } else { progress }
	return f64(clamped) / 100.0
}

// command_finished applies the per-surface command notification policy.
// Mirrors Surface.commandFinished, including the one-shot context-menu action.
pub fn (mut self SurfaceWidget) command_finished(value apprt.CommandFinished) bool {
	mut notify_next_command_finish := false
	if !isnil(self.action_group) {
		action := C.g_action_map_lookup_action(GActionMap(self.action_group), c'notify-on-next-command-finish')
		if !isnil(action) {
			state := C.g_action_get_state(action)
			if !isnil(state) {
				bool_type := C.g_variant_type_new(c'b')
				is_bool := C.g_variant_is_of_type(state, bool_type)
				C.g_variant_type_free(bool_type)
				if is_bool {
					notify_next_command_finish = C.g_variant_get_boolean(state)
					C.g_simple_action_set_state(GSimpleAction(action), C.g_variant_new_boolean(0))
				}
				C.g_variant_unref(state)
			}
		}
	}

	if isnil(self.config) {
		return false
	}
	cfg := self.config.get()
	if !notify_next_command_finish {
		if cfg.notify_on_command_finish == .never {
			return true
		}
		if cfg.notify_on_command_finish == .unfocused && self.get_focused() {
			return true
		}
	}
	if value.duration.lte(cfg.notify_on_command_finish_after) {
		return true
	}

	action := cfg.notify_on_command_finish_action
	if action.bell() {
		self.set_bell_ringing(true)
	}
	if action.notify() {
		title := if exit_code := value.exit_code {
			if exit_code == 0 { i18n_('Command Succeeded') } else { i18n_('Command Failed') }
		} else {
			i18n_('Command Finished')
		}
		duration := value.duration.round(1_000_000).format()
		body := if exit_code := value.exit_code {
			'Command took ${duration} and exited with code ${exit_code}.'
		} else {
			'Command took ${duration}.'
		}
		self.send_desktop_notification(title, body)
	}

	return true
}

// send_desktop_notification creates the native GNotification and makes
// activating it present this exact core surface.
pub fn (self &SurfaceWidget) send_desktop_notification(title string, body string) {
	if !self.has_core() {
		log.warn("can't send notification because there is no core surface")
		return
	}
	if isnil(self.app) || isnil(self.app.obj) {
		return
	}

	actual_title := if title.len == 0 { 'Witty' } else { title }
	notification := C.g_notification_new(&char(actual_title.str))
	if isnil(notification) {
		return
	}
	defer {
		object_unref(GObject(notification))
	}
	C.g_notification_set_body(notification, &char(body.str))

	icon := C.g_themed_icon_new(c'com.alexander.witty')
	if !isnil(icon) {
		C.g_notification_set_icon(notification, icon)
		object_unref(GObject(icon))
	}

	pointer := C.g_variant_new_uint64(u64(uint(voidptr(self.core_surface))))
	C.g_notification_set_default_action_and_target_value(notification, c'app.present-surface', pointer)
	C.g_application_send_notification(self.app.obj, &char(body.str), notification)
}

fn surface_progress_bar_timer_cb(data voidptr) int {
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &SurfaceWidget(data) }
	self.progress_bar_timer = 0
	self.set_progress_report(osc.ProgressReport{ state: .remove })
	return 0
}

// ring_bell handles bell features that happen on every BEL. Mirrors
// Surface.ringBell: emit the signal, activate ancestor bell actions, and play
// the configured audio file.
fn (self &SurfaceWidget) ring_bell() {
	C.g_signal_emit_by_name(self.widget, c'bell')
	_ = C.gtk_widget_activate_action_variant(self.widget, c'tab.ring-bell', unsafe { nil })
	_ = C.gtk_widget_activate_action_variant(self.widget, c'win.ring-bell', unsafe { nil })

	if isnil(self.config) {
		return
	}
	cfg := self.config.get()
	if !cfg.bell_features.audio() {
		return
	}
	config_path := cfg.bell_audio_path or { return }
	path := match config_path {
		configpkg.PathOptional { config_path.path }
		configpkg.PathRequired { config_path.path }
	}
	required := config_path is configpkg.PathRequired
	assert os.is_abs_path(path)
	volume := if cfg.bell_audio_volume < 0.0 {
		0.0
	} else if cfg.bell_audio_volume > 1.0 {
		1.0
	} else {
		cfg.bell_audio_volume
	}

	media_file := C.gtk_media_file_new_for_filename(&char(path.str))
	if isnil(media_file) {
		return
	}
	if required {
		C.g_signal_connect_data(media_file, c'notify::error', GCallback(voidptr(surface_media_file_error_cb)), unsafe { nil }, unsafe { nil }, 0)
	}
	C.g_signal_connect_data(media_file, c'notify::ended', GCallback(voidptr(surface_media_file_ended_cb)), unsafe { nil }, unsafe { nil }, 0)
	C.gtk_media_stream_set_volume(GtkMediaStream(media_file), volume)
	C.gtk_media_stream_play(GtkMediaStream(media_file))
}

fn surface_media_file_error_cb(media_file GtkMediaFile, pspec voidptr, data voidptr) {
	_ = pspec
	_ = data
	mut path := '<<unknown>>'
	mut owned_path := &char(unsafe { nil })
	file := C.gtk_media_file_get_file(media_file)
	if !isnil(file) {
		owned_path = C.g_file_get_path(file)
		if !isnil(owned_path) {
			path = unsafe { cstring_to_vstring(owned_path) }
		}
	}
	defer {
		if !isnil(owned_path) {
			C.g_free(owned_path)
		}
	}

	err := C.gtk_media_stream_get_error(GtkMediaStream(media_file))
	if isnil(err) {
		return
	}
	c_err := unsafe { &C.GError(err) }
	domain_ptr := C.g_quark_to_string(c_err.domain)
	domain := if isnil(domain_ptr) { '' } else { unsafe { cstring_to_vstring(domain_ptr) } }
	message := if isnil(c_err.message) { '' } else { unsafe { cstring_to_vstring(c_err.message) } }
	log.warn('error playing bell from ${path}: ${domain} ${c_err.code} ${message}')
}

fn surface_media_file_ended_cb(media_file GtkMediaFile, pspec voidptr, data voidptr) {
	_ = pspec
	_ = data
	object_unref(GObject(media_file))
}

// set_error sets the error state. Mirrors `Surface.setError`.
pub fn (mut self SurfaceWidget) set_error(v bool) {
	self.error_state = v
	self.notify_property(g_surface_pspec_error)
	if v {
		C.gtk_widget_add_css_class(self.widget, c'background')
	} else {
		C.gtk_widget_remove_css_class(self.widget, c'background')
	}
	if self.idle_rechild == 0 {
		self.idle_rechild = C.g_idle_add(voidptr(surface_idle_rechild_cb), voidptr(self))
	}
}

fn surface_idle_rechild_cb(data voidptr) int {
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &SurfaceWidget(data) }
	self.idle_rechild = 0
	child := if self.error_state { self.error_page } else { self.terminal_page }
	if !isnil(self.widget) && !isnil(child) {
		C.adw_bin_set_child(AdwBin(self.widget), child)
	}
	return 0
}

// --- Default / min size ----------------------------------------------------

// get_default_size returns the default size, if set. Mirrors
// `Surface.getDefaultSize`.
pub fn (self &SurfaceWidget) get_default_size() ?Size {
	return self.default_size
}

// set_default_size sets the default size. Mirrors `Surface.setDefaultSize`.
pub fn (mut self SurfaceWidget) set_default_size(size Size) {
	self.default_size = size
	self.notify_property(g_surface_pspec_default_size)
}

// get_min_size returns the min size, if set. Mirrors `Surface.getMinSize`.
pub fn (self &SurfaceWidget) get_min_size() ?Size {
	return self.min_size
}

// set_min_size sets the min size. Mirrors `Surface.setMinSize`.
pub fn (mut self SurfaceWidget) set_min_size(size Size) {
	self.min_size = size
	self.notify_property(g_surface_pspec_min_size)
}

// --- cgroup ---------------------------------------------------------------

// init_cgroup creates this surface's child scope under the application's
// transient cgroup. Failure is deliberately non-fatal, matching Ghostty.
fn (mut self SurfaceWidget) init_cgroup() {
	if self.cgroup_path != none || isnil(self.app) {
		return
	}
	base := self.app.cgroup_base() or { return }
	name := 'surfaces/${uint(voidptr(self)):X}.scope'
	internal_os.create(base, name, none) or {
		log.warn('failed to create surface cgroup err=${err}')
		return
	}
	self.cgroup_path = '${base}/${name}'
}

// clear_cgroup removes this surface's child scope after its process has been
// shut down. A dangling empty cgroup is non-fatal.
fn (mut self SurfaceWidget) clear_cgroup() {
	path := self.cgroup_path or { return }
	internal_os.remove(path) or {
		log.warn('failed to remove cgroup for surface path=${path} err=${err}')
	}
	self.cgroup_path = none
}

// cgroup_path returns the cgroup path, if any. Mirrors `Surface.cgroupPath`.
pub fn (self &SurfaceWidget) cgroup_path() ?string {
	return self.cgroup_path
}

// --- Key input ------------------------------------------------------------

// core_key_action maps the apprt/input KeyAction to the core.KeyAction used by
// core.Surface.key_callback. The two enums have different member ordering so a
// numeric cast is not safe.
fn core_key_action(action input.KeyAction) core.KeyAction {
	return match action {
		.press { core.KeyAction.press }
		.repeat { core.KeyAction.repeat }
		.release { core.KeyAction.release }
	}
}

// key_event handles a key press or release. This is the meat of keyboard
// input handling. Faithfully translated from `Surface.keyEvent`:
//   * runs the GdkEvent through the input method context (for preedit/commit),
//   * maintains the in_keyevent / im_composing state machine,
//   * derives the physical key, modifiers, consumed modifiers and utf8 text,
//   * forwards an input.KeyEvent to the core surface via keyCallback.
//
// `event` is the current GdkEvent for the controller. Returns true if handled.
pub fn (mut self SurfaceWidget) key_event(action input.KeyAction, event GdkEvent, keyval u32, keycode u32, gtk_mods u32) bool {
	if isnil(event) {
		return false
	}

	// Input-method handling block. See the function comment.
	{
		// Notify the IM context where the cursor is so it can render dropdowns
		// in the right place.
		if self.has_core() {
			ime_point := self.core_surface.ime_point()
			rect := C.GdkRectangle{
				x:      int(ime_point.x)
				y:      int(ime_point.y)
				width:  1
				height: 1
			}
			C.gtk_im_context_set_cursor_location(self.im_context, &rect)
		}

		// Note that we're in a keypress; some logic depends on this (see the
		// commit handler). We track whether we were composing beforehand
		// because different input methods call callbacks in different orders.
		self.in_keyevent = if self.im_composing {
			IMKeyEvent.composing
		} else {
			IMKeyEvent.not_composing
		}

		// Pass the event through the input method. Returns true if handled.
		im_handled := C.gtk_im_context_filter_keypress(self.im_context, event)

		if im_handled {
			// If composing then we're in a preedit state and don't encode keys.
			if self.im_composing {
				self.in_keyevent = .false_
				return true
			}
			// If we WERE composing and now aren't, we committed text; don't
			// encode a key event for this either.
			if self.in_keyevent == .composing {
				self.in_keyevent = .false_
				return true
			}
			// Not composing and empty IM buffer: the IM reacted (e.g. opened an
			// onscreen keyboard) without giving us text, so don't encode.
			if self.im_len == 0 {
				self.in_keyevent = .false_
				return true
			}
		}
	}

	// Reset in_keyevent now that the IM block is done.
	self.in_keyevent = .false_

	// Get the unicode value for this keyval.
	keyval_cp := keyval_unicode(keyval)

	// Start with the physical W3C key from the XKB native-code column. Then use
	// the pre-remapped keysym when either side is eligible for OS remapping. This
	// is Ghostty's workaround for XKB remaps while retaining correct physical
	// keybindings on non-US layouts.
	mut physical_key := input.xkb_keycode_to_key(keycode)
	if remapped := key_from_keyval(keyval) {
		if physical_key.should_be_remappable() || remapped.should_be_remappable() {
			physical_key = remapped
		}
	}

	// Get our modifiers for the event.
	//
	mut app := Application.default()
	mut app_winproto := app.winproto()
	mods := event_mods(event, physical_key, gtk_mods, action, mut app_winproto)

	consumed_mods := translate_mods(C.gdk_key_event_get_consumed_modifiers(event))
	unshifted_codepoint := keyval_unicode_unshifted(GtkWidget(self.gl_area), event, keycode)

	// If we have no UTF-8 text, try to convert the keyval to a text value.
	// GTK won't process e.g. Ctrl+Shift+1 as "Ctrl+!" but the keyval is set
	// correctly so we extract that. Control characters (< 0x20) are skipped
	// because the encoder handles them directly.
	if self.im_len == 0 && keyval_cp > 0 && keyval_cp < 0x110000 {
		cp := keyval_cp
		if cp >= 0x20 {
			encoded := utf32_to_string(cp)
			if encoded.len > 0 && encoded.len <= self.im_buf.len {
				for i in 0 .. encoded.len {
					self.im_buf[i] = encoded[i]
				}
				self.im_len = encoded.len
			}
		}
	}

	// Reset the IM buffer length after this event regardless of outcome.
	utf8 := self.im_buf[0..self.im_len].bytestr()
	defer {
		self.im_len = 0
	}

	// Invoke the core logic to handle this input.
	if !self.has_core() {
		return false
	}
	mut surface := self.core_surface
	effect := surface.key_callback(core.KeyEvent{
		action:              core_key_action(action)
		key:                 physical_key
		mods:                mods
		consumed_mods:       consumed_mods
		composing:           self.im_composing
		utf8:                utf8
		unshifted_codepoint: unshifted_codepoint
	}) or {
		log.error('error in key callback err=${err}')
		return false
	}

	match effect {
		.closed {
			return true
		}
		.ignored {}
		.consumed {
			if action == .press || action == .repeat {
				// If we were composing, reset the IM context. We do NOT reset
				// otherwise because other IME state must be preserved (e.g.
				// quotation-mark ordering for Chinese input).
				if self.im_composing {
					C.gtk_im_context_reset(self.im_context)
					surface.preedit_callback('') or {}
				}
				// Bell stops ringing when a used key is pressed.
				self.set_bell_ringing(false)
				return true
			}
		}
	}

	return false
}

// ec_key_pressed is the GtkEventControllerKey "key-pressed" handler. Mirrors
// `ecKeyPressed`.
pub fn (mut self SurfaceWidget) ec_key_pressed(event GdkEvent, keyval u32, keycode u32, gtk_mods u32) bool {
	return self.key_event(.press, event, keyval, keycode, gtk_mods)
}

// ec_key_released is the GtkEventControllerKey "key-released" handler. Mirrors
// `ecKeyReleased`.
pub fn (mut self SurfaceWidget) ec_key_released(event GdkEvent, keyval u32, keycode u32, gtk_mods u32) {
	self.key_event(.release, event, keyval, keycode, gtk_mods)
}

// --- Input method callbacks -----------------------------------------------

// im_preedit_start begins composing. Mirrors `imPreeditStart`.
pub fn (mut self SurfaceWidget) im_preedit_start() {
	self.im_composing = true
	self.im_len = 0
}

// im_preedit_changed handles a preedit change. Mirrors `imPreeditChanged`.
// The preedit string is passed in (ghostty pulls it from the IM context).
pub fn (mut self SurfaceWidget) im_preedit_changed(str string) {
	// Any preedit change marks that we're composing.
	self.im_composing = true

	// Can't set preedit unless we have a core surface.
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	surface.preedit_callback(str) or {
		log.warn('error in preedit callback err=${err}')
	}
}

// im_preedit_end ends composing. Mirrors `imPreeditEnd`.
pub fn (mut self SurfaceWidget) im_preedit_end() {
	self.im_composing = false
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	surface.preedit_callback('') or {
		log.warn('error in preedit callback err=${err}')
	}
}

// im_commit handles committed IM text. Faithfully translated from `imCommit`,
// including the in_keyevent state machine that decides whether the text should
// be buffered for the key event or committed directly.
pub fn (mut self SurfaceWidget) im_commit(str string) {
	match self.in_keyevent {
		// Not in a key event: commit came from another source (OSK, tablet).
		.false_ {}
		// Composing in a key event: this commit is part of a multi-keypress
		// commit and we don't want to encode it alongside the keypress.
		.composing {}
		// Not composing: a normal key encoding; buffer it so the key event
		// handler associates it with the keypress.
		.not_composing {
			if str.len > self.im_buf.len {
				log.warn('not enough buffer space for input method commit')
				return
			}
			for i in 0 .. str.len {
				self.im_buf[i] = str[i]
			}
			self.im_len = str.len
			return
		}
	}

	// Reaching here means composing OR not in a keypress: commit directly.
	self.im_composing = false

	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	// Well-behaved IMs trigger preedit-end for us; some don't, so end it here.
	surface.preedit_callback('') or {
		log.warn('error in preedit callback err=${err}')
	}
	// Send the text with an invalid key (no PTY encoding for the key itself).
	surface.key_callback(core.KeyEvent{
		action: .press
		key:    .unidentified
		mods:   input.Mods{}
		utf8:   str
	}) or {
		log.warn('error in key callback err=${err}')
	}
}

// --- Mouse input ----------------------------------------------------------

// translate_mouse_button converts a GTK button number to an input.MouseButton.
// Mirrors the file-scope `translateMouseButton`.
fn translate_mouse_button(button u32) input.MouseButton {
	return match button {
		1 { input.MouseButton.left }
		2 { input.MouseButton.middle }
		3 { input.MouseButton.right }
		4 { input.MouseButton.four }
		5 { input.MouseButton.five }
		6 { input.MouseButton.six }
		7 { input.MouseButton.seven }
		8 { input.MouseButton.eight }
		9 { input.MouseButton.nine }
		10 { input.MouseButton.ten }
		11 { input.MouseButton.eleven }
		else { input.MouseButton.unknown }
	}
}

// gc_mouse_down is the GtkGestureClick "pressed" handler. Mirrors `gcMouseDown`.
// `button` is the current gesture button; `event` is the current GdkEvent.
pub fn (mut self SurfaceWidget) gc_mouse_down(event GdkEvent, button u32, x f64, y f64) {
	if isnil(event) {
		return
	}

	// Bell stops ringing if any mouse button is pressed.
	self.set_bell_ringing(false)

	if !self.has_core() {
		return
	}
	mut surface := self.core_surface

	// If we don't have focus, grab it.
	if !C.gtk_widget_has_focus(self.gl_area) {
		C.gtk_widget_grab_focus(self.gl_area)
	}

	btn := translate_mouse_button(button)

	if btn == .middle && !self.gtk_enable_primary_paste {
		return
	}

	gtk_mods := C.gdk_event_get_modifier_state(event)
	mods := translate_mods(gtk_mods)
	consumed := surface.mouse_button_callback(.press, btn, mods) or {
		log.warn('error in key callback err=${err}')
		false
	}

	// If a right-click isn't consumed, open the context menu.
	if !consumed && btn == .right {
		C.g_signal_emit_by_name(self.widget, c'menu')
		if !isnil(self.context_menu) {
			rect := C.GdkRectangle{
				x:      int(x)
				y:      int(y)
				width:  1
				height: 1
			}
			C.gtk_popover_set_pointing_to(self.context_menu, &rect)
			C.gtk_popover_popup(self.context_menu)
		}
	}
}

// gc_mouse_up is the GtkGestureClick "released" handler. Mirrors `gcMouseUp`.
pub fn (mut self SurfaceWidget) gc_mouse_up(event GdkEvent, button u32) {
	if isnil(event) {
		return
	}
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface

	btn := translate_mouse_button(button)
	if btn == .middle && !self.gtk_enable_primary_paste {
		return
	}

	gtk_mods := C.gdk_event_get_modifier_state(event)
	mods := translate_mods(gtk_mods)
	consumed := surface.mouse_button_callback(.release, btn, mods) or {
		log.warn('error in key callback err=${err}')
		return
	}

	// Trigger the on-screen keyboard if we have no selection and the callback
	// didn't intercept.
	if !consumed && btn == .left && !surface.has_selection() {
		if !self.show_on_screen_keyboard(event) {
			log.warn('failed to activate the on-screen keyboard')
		}
	}
}

// show_on_screen_keyboard asks the current input context to activate the
// platform on-screen keyboard for the event.
pub fn (self &SurfaceWidget) show_on_screen_keyboard(event ?GdkEvent) bool {
	if isnil(self.im_context) {
		return false
	}
	native_event := event or { GdkEvent(unsafe { nil }) }
	return C.gtk_im_context_activate_osk(self.im_context, native_event)
}

// ec_mouse_motion is the GtkEventControllerMotion "motion" handler. Mirrors
// `ecMouseMotion`.
pub fn (mut self SurfaceWidget) ec_mouse_motion(event GdkEvent, x f64, y f64) {
	if isnil(event) {
		return
	}

	sx, sy := self.scaled_coordinates(x, y)
	pos := apprt.CursorPos{
		x: f32(sx)
		y: f32(sy)
	}

	// GTK issues motion events without the cursor actually moving in a couple
	// cases (GLArea resized under the mouse; title updated). Only continue if
	// the cursor actually moved.
	is_cursor_still := abs_f32(self.cursor_pos.x - pos.x) < 1 && abs_f32(self.cursor_pos.y - pos.y) < 1
	if is_cursor_still {
		return
	}

	// If we don't have focus and focus-follows-mouse is on, grab it.
	if !isnil(self.config) && self.config.get().focus_follows_mouse
		&& !C.gtk_widget_has_focus(self.gl_area) {
		C.gtk_widget_grab_focus(self.gl_area)
	}

	// Our pos changed, update.
	self.cursor_pos = pos

	if self.has_core() {
		mut surface := self.core_surface
		gtk_mods := C.gdk_event_get_modifier_state(event)
		mods := translate_mods(gtk_mods)
		surface.cursor_pos_callback(self.cursor_pos, mods) or {
			log.warn('error in cursor pos callback err=${err}')
		}
	}
}

// ec_mouse_leave is the GtkEventControllerMotion "leave" handler. Mirrors
// `ecMouseLeave`: sends an out-of-bounds cursor position.
pub fn (mut self SurfaceWidget) ec_mouse_leave(event GdkEvent) {
	if isnil(event) {
		return
	}
	if self.has_core() {
		mut surface := self.core_surface
		gtk_mods := C.gdk_event_get_modifier_state(event)
		mods := translate_mods(gtk_mods)
		surface.cursor_pos_callback(apprt.CursorPos{ x: -1, y: -1 }, mods) or {
			log.warn('error in cursor pos callback err=${err}')
		}
	}
}

// --- Scroll input ---------------------------------------------------------

// ec_scroll_vertical_precision_begin marks a precision scroll in progress.
// Mirrors `ecMouseScrollVerticalPrecisionBegin`.
pub fn (mut self SurfaceWidget) ec_scroll_vertical_precision_begin() {
	self.precision_scroll = true
}

// ec_scroll_vertical_precision_end clears the precision scroll flag. Mirrors
// `ecMouseScrollVerticalPrecisionEnd`.
pub fn (mut self SurfaceWidget) ec_scroll_vertical_precision_end() {
	self.precision_scroll = false
}

// ec_scroll_vertical is the GtkEventControllerScroll "scroll" handler for
// vertical scroll. Mirrors `ecMouseScrollVertical`.
pub fn (mut self SurfaceWidget) ec_scroll_vertical(x f64, y f64) bool {
	if !self.has_core() {
		return false
	}
	mut surface := self.core_surface

	// Multiply precision scrolls by 10 for a better touchpad response.
	multiplier := if self.precision_scroll { f64(10.0) } else { f64(1.0) }

	sx, sy := self.scaled_coordinates(x, y)
	// We invert because we apply natural scrolling to the values.
	surface.scroll_callback(sx * -1 * multiplier, sy * -1 * multiplier, input.ScrollMods.init(self.precision_scroll, .none_)) or {
		log.warn('error in scroll callback err=${err}')
		return false
	}
	return true
}

// ec_scroll_horizontal is the GtkEventControllerScroll "scroll" handler for
// horizontal scroll. Mirrors `ecMouseScrollHorizontal`: accumulates horizontal
// scroll, resets the accumulator after 500ms of inactivity, and switches tabs
// when the threshold is crossed.
pub fn (mut self SurfaceWidget) ec_scroll_horizontal(x f64) bool {
	self.pending_horizontal_scroll += x

	if abs_f64(self.pending_horizontal_scroll) < 120 {
		if self.pending_horizontal_scroll_reset != 0 {
			C.g_source_remove(self.pending_horizontal_scroll_reset)
		}
		self.pending_horizontal_scroll_reset = C.g_timeout_add(500, voidptr(surface_horizontal_scroll_reset_cb), self)
		return true
	}

	// Route this through the tab action group so touchpad navigation follows
	// the same propagation and availability rules as menus and keybindings.
	_ = C.gtk_widget_activate_action_variant(self.widget, if self.pending_horizontal_scroll < 0 {
		c'tab.next-page'
	} else {
		c'tab.previous-page'
	}, unsafe { nil })
	if self.pending_horizontal_scroll_reset != 0 {
		C.g_source_remove(self.pending_horizontal_scroll_reset)
		self.pending_horizontal_scroll_reset = 0
	}
	self.pending_horizontal_scroll = 0.0
	return true
}

fn surface_horizontal_scroll_reset_cb(data voidptr) int {
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.pending_horizontal_scroll = 0
		self.pending_horizontal_scroll_reset = 0
	}
	return 0
}

// --- Focus event controllers ----------------------------------------------

// ec_focus_enter is the GtkEventControllerFocus "enter" handler. Mirrors
// `ecFocusEnter`.
pub fn (mut self SurfaceWidget) ec_focus_enter() {
	self.focused = true
	self.sync_unfocused_split_overlay()
	C.gtk_im_context_focus_in(self.im_context)
	self.notify_focus()
	self.notify_property(g_surface_pspec_focused)
	// Bell stops ringing as soon as we gain focus.
	self.set_bell_ringing(false)
}

// ec_focus_leave is the GtkEventControllerFocus "leave" handler. Mirrors
// `ecFocusLeave`.
pub fn (mut self SurfaceWidget) ec_focus_leave() {
	self.focused = false
	self.sync_unfocused_split_overlay()
	C.gtk_im_context_focus_out(self.im_context)
	self.notify_focus()
	self.notify_property(g_surface_pspec_focused)
}

// notify_focus forwards the focus state to the core surface. In ghostty this is
// deferred onto a glib idle source (idleFocus) to avoid a deadlock where a
// libwitty callback triggers focus loss while a lock is held.
fn (self &SurfaceWidget) notify_focus() {
	object_ref(self.widget)
	C.g_idle_add(voidptr(surface_idle_focus_cb), voidptr(self))
}

fn surface_idle_focus_cb(data voidptr) int {
	if isnil(data) {
		return 0
	}
	self := unsafe { &SurfaceWidget(data) }
	defer { object_unref(self.widget) }
	if self.has_core() {
		mut surface := self.core_surface
		surface.focus_callback(self.focused) or {
			log.warn('error in focus callback err=${err}')
		}
	}
	return 0
}

// --- GLArea lifecycle -----------------------------------------------------

// glarea_realize is the GtkGLArea "realize" handler. Mirrors `glareaRealize`.
pub fn (mut self SurfaceWidget) glarea_realize() {
	log.debug('realize')
	// Make the GL area current so we can detect OpenGL errors.
	C.gtk_gl_area_make_current(self.gl_area)
	gl_err := C.gtk_gl_area_get_error(self.gl_area)
	if !isnil(gl_err) {
		log.warn('failed to make GL context current: ${error_message(gl_err)}')
		log.warn('this error is almost always due to a library, driver, or GTK issue')
		log.warn('this is a common cause of this issue: https://github.com/witty-terminal/witty/issues')
		self.set_error(true)
		return
	}

	// If we already have an initialized surface, notify it; otherwise we'll
	// initialize on the first resize so we have proper initial dimensions.
	if self.has_core() {
		mut surface := self.core_surface
		mut realized := true
		surface.renderer.display_realized() or {
			log.warn('core displayRealized failed err=${err}')
			realized = false
		}
		if realized {
			self.redraw()
		}
	}

	// Setup our input method (strong ref back to us; released in unrealize).
	C.gtk_im_context_set_client_widget(self.im_context, self.widget)
}

// glarea_unrealize is the GtkGLArea "unrealize" handler. Mirrors
// `glareaUnrealize`.
pub fn (mut self SurfaceWidget) glarea_unrealize() {
	log.debug('unrealize')
	if self.has_core() {
		// The context is not guaranteed current on unrealize, so make it current.
		C.gtk_gl_area_make_current(self.gl_area)
		gl_err := C.gtk_gl_area_get_error(self.gl_area)
		if !isnil(gl_err) {
			log.warn('gl_area_make_current failed in unrealize msg=${error_message(gl_err)}')
			log.warn('OpenGL resources and memory likely leaked')
			return
		}
		mut surface := self.core_surface
		surface.renderer.display_unrealized()
	}

	// Unset our input method.
	C.gtk_im_context_set_client_widget(self.im_context, unsafe { nil })
}

// glarea_render is the GtkGLArea "render" handler. Mirrors `glareaRender`.
// Returns true (GDK_EVENT_STOP-equivalent) as in the Zig original.
pub fn (mut self SurfaceWidget) glarea_render() bool {
	if !self.has_core() {
		return true
	}
	mut surface := self.core_surface
	// core.Surface.draw() draws a single frame (renderer.draw_frame(true)).
	surface.draw() or {
		log.warn('failed to draw frame err=${err}')
		return false
	}
	return true
}

// glarea_resize is the GtkGLArea "resize" handler. Mirrors `glareaResize`.
// Stores the cached size and either forwards resize callbacks to the core
// surface or initializes the surface on the first resize.
pub fn (mut self SurfaceWidget) glarea_resize(width int, height int) {
	mut window_scale := 0
	root := C.gtk_widget_get_root(self.gl_area)
	if !isnil(root) {
		gdk_surface := C.gtk_native_get_surface(GtkNative(root))
		if !isnil(gdk_surface) {
			window_scale = C.gdk_surface_get_scale_factor(gdk_surface)
		}
	}
	log.debug('gl resize width=${width} height=${height} scale=${C.gtk_widget_get_scale_factor(self.gl_area)} window_scale=${window_scale}')

	// Store our cached size.
	self.size = apprt.SurfaceSize{
		width:  u32(width)
		height: u32(height)
	}

	// If our surface is realized, send callbacks.
	if self.has_core() {
		mut surface := self.core_surface
		// Update content scale too (no dedicated signal for it).
		scale := self.get_content_scale()
		surface.content_scale_callback(scale) or {
			log.warn('error in content scale callback err=${err}')
		}
		surface.size_callback(self.size) or {
			log.warn('error in size callback err=${err}')
		}
		self.resize_overlay_schedule()
		return
	}

	// If we don't have a surface, initialize it now.
	self.init_surface() or {
		log.warn('surface failed to initialize err=${err}')
	}
}

// apply_resize_overlay_config mirrors the resize-overlay portion of
// `propConfig`: it updates the display duration and the label alignment.
fn (mut self SurfaceWidget) apply_resize_overlay_config() {
	if isnil(self.config) || isnil(self.resize_overlay) {
		return
	}
	cfg := self.config.get()
	mut halign := Align.center
	mut valign := Align.center
	match cfg.resize_overlay_position {
		.center {}
		.top_left {
			halign = .start
			valign = .start
		}
		.top_right {
			halign = .end
			valign = .start
		}
		.top_center {
			valign = .start
		}
		.bottom_left {
			halign = .start
			valign = .end
		}
		.bottom_right {
			halign = .end
			valign = .end
		}
		.bottom_center {
			valign = .end
		}
	}
	self.resize_overlay.set_duration(cfg.resize_overlay_duration.as_milliseconds())
	self.resize_overlay.set_position(halign, valign)
}

// apply_config mirrors the surface's notify::config handler and refreshes
// every programmatic binding that depends on the shared Config object.
pub fn (mut self SurfaceWidget) apply_config() {
	self.apply_resize_overlay_config()
	use_canvas := !isnil(self.config) && gtk_canvas_styles_enabled(self.config.get())
	gtk_canvas_overlay_set_mask(self.terminal_page, use_canvas)
	if !isnil(self.resize_overlay) {
		gtk_canvas_overlay_set_enabled(self.resize_overlay.widget, use_canvas)
	}
	if !isnil(self.search_overlay) {
		gtk_canvas_overlay_set_enabled(self.search_overlay.widget, use_canvas)
	}
	if !isnil(self.key_state_overlay) {
		gtk_canvas_overlay_set_enabled(self.key_state_overlay.widget, use_canvas)
	}
	if !isnil(self.progress_bar_overlay) {
		C.witty_gtk_progress_set_canvas(self.progress_bar_overlay, use_canvas)
	}
	if !isnil(self.bell_revealer) {
		C.witty_gtk_bell_set_canvas(self.bell_revealer, use_canvas)
	}
	if !isnil(self.child_exited_overlay) {
		self.child_exited_overlay.set_canvas(use_canvas)
	}
	self.sync_bell_border_overlay()
}

// set_config_reference is the object-field accessor used by the native
// `config` property. It releases the previous GObject, retains the incoming
// one, emits notify::config, and runs the translated property callback.
fn (mut self SurfaceWidget) set_config_reference(config_ ?&Config) {
	config := config_ or { unsafe { nil } }
	if self.config == config {
		self.notify_property(g_surface_pspec_config)
		self.apply_config()
		return
	}
	if !isnil(self.config) {
		self.config.unref()
	}
	self.config = unsafe { nil }
	if !isnil(config) {
		self.config = config_ref(config)
	}
	self.notify_property(g_surface_pspec_config)
	self.apply_config()
}

// set_config changes the shared configuration object for this surface.
// Mirrors the public `Surface.setConfig` entry point.
pub fn (mut self SurfaceWidget) set_config(config &Config) {
	self.set_config_reference(config)
}

// set_owned_config installs a surface-local config object for a targeted
// reload. The core config is cloned by config_new, matching Config.new.
pub fn (mut self SurfaceWidget) set_owned_config(config configpkg.Config) {
	if !isnil(self.config) {
		self.config.unref()
	}
	self.config = config_new(config)
	self.notify_property(g_surface_pspec_config)
	self.apply_config()
}

// resize_overlay_schedule mirrors `resizeOverlaySchedule`.
fn (mut self SurfaceWidget) resize_overlay_schedule() {
	if !self.has_core() || isnil(self.config) || isnil(self.resize_overlay) {
		return
	}
	cfg := self.config.get()
	match cfg.resize_overlay {
		.always, .after_first {}
		.never {
			return
		}
	}
	self.apply_resize_overlay_config()
	grid_size := self.core_surface.size.grid()
	self.resize_overlay.set_label('${grid_size.columns} x ${grid_size.rows}')
	self.resize_overlay.schedule()
}

// init_surface initializes the core surface on the first GLArea resize.
// Mirrors `initSurface`: it creates the core/runtime bridge, applies inherited
// font and working-directory state, creates the transient cgroup when enabled,
// registers the surface, and emits `init`.
fn (mut self SurfaceWidget) init_surface() ! {
	assert !self.has_core(), 'surface is already initialized'

	// Make the GL context current for surface operations.
	C.gtk_gl_area_make_current(self.gl_area)
	gl_err := C.gtk_gl_area_get_error(self.gl_area)
	if !isnil(gl_err) {
		log.warn('failed to make GL context current: ${error_message(gl_err)}')
		log.warn('this error is usually due to a driver or gtk bug')
		log.warn('this is a common cause of this issue: https://gitlab.gnome.org/GNOME/gtk/-/issues/4950')
		return error('failed to make GL context current')
	}

	if isnil(self.app) || isnil(self.config) || isnil(self.app.core_app) {
		return error('surface application state is unavailable')
	}

	self.init_cgroup()

	mut surface := &core.Surface{}
	mut surface_ref := &core.SurfaceRef{
		core_surface: surface
		rt_app:       &self.app.runtime_bridge
	}
	self.core_surface = surface
	self.core_surface_ref = surface_ref
	self.core_runtime_surface = apprt.RuntimeSurface{
		user_data:             self
		close_fn:              surface_core_close_cb
		content_scale_fn:      surface_core_content_scale_cb
		size_fn:               surface_core_size_cb
		startup_size_fn:       surface_core_startup_size_cb
		cursor_pos_fn:         surface_core_cursor_pos_cb
		title_fn:              surface_core_title_cb
		set_clipboard_fn:      surface_core_set_clipboard_cb
		supports_clipboard_fn: surface_core_supports_clipboard_cb
		clipboard_request_fn:  surface_core_clipboard_request_cb
		default_env_fn:        surface_core_default_env_cb
		linux_cgroup:          self.cgroup_path
	}

	mut core_app := unsafe { self.app.core_app }
	core_app.add_surface(surface_ref)
	mut surface_config := apprt.new_config(core_app, self.config.get(), self.context)
	defer {
		surface_config.deinit()
	}
	if font_size_request := self.font_size_request {
		surface_config.font_size = font_size_request.points
	}
	if pwd := self.pwd {
		surface_config.working_directory = pwd
	}
	surface.init_with_options(&surface_config, mut core_app, &self.app.runtime_bridge,
		&self.core_runtime_surface, self.init_options) or {
		log.warn('failed to initialize surface err=${err}')
		core_app.delete_surface(surface_ref)
		self.core_surface = unsafe { nil }
		self.core_surface_ref = unsafe { nil }
		self.clear_cgroup()
		return error('core surface initialization failed: ${err}')
	}
	C.g_signal_emit_by_name(self.widget, c'init')
}

fn surface_core_close_cb(data voidptr, confirm bool) {
	_ = confirm
	if isnil(data) {
		return
	}
	self := unsafe { &SurfaceWidget(data) }
	self.close()
}

fn surface_core_content_scale_cb(data voidptr) !apprt.ContentScale {
	self := unsafe { &SurfaceWidget(data) }
	return self.get_content_scale()
}

fn surface_core_size_cb(data voidptr) !apprt.SurfaceSize {
	self := unsafe { &SurfaceWidget(data) }
	return self.get_size()
}

fn surface_core_startup_size_cb(data voidptr, requested apprt.InitialSize, limits apprt.SizeLimit) ?apprt.SurfaceSize {
	self := unsafe { &SurfaceWidget(data) }
	if self.context != .window {
		return none
	}
	window := window_from_surface(self) or { return none }
	if window.surface_init || window.is_quick_terminal() || window.is_fullscreen()
		|| window.is_maximized() || isnil(window.config) {
		return none
	}
	config := window.config.get()
	if config.fullscreen || config.maximize {
		return none
	}
	widget := window.as_widget()
	native := C.gtk_native_get_surface(GtkNative(widget))
	if isnil(native) {
		return none
	}
	monitor := C.gdk_display_get_monitor_at_surface(C.gtk_widget_get_display(widget), native)
	if isnil(monitor) {
		return none
	}
	mut geometry := C.GdkRectangle{}
	C.gdk_monitor_get_geometry(monitor, &geometry)
	target_width := i64(math.max(requested.width, limits.min_width))
	target_height := i64(math.max(requested.height, limits.min_height))
	if target_width > geometry.width || target_height > geometry.height {
		return none
	}

	// GTK applies the default size on a later layout. Use the difference
	// between the two default sizes so window chrome stays accounted for.
	mut default_width := 0
	mut default_height := 0
	C.gtk_window_get_default_size(window.as_window(), &default_width, &default_height)
	scale := i64(C.gtk_widget_get_scale_factor(self.gl_area))
	width := i64(self.size.width) + (target_width - default_width) * scale
	height := i64(self.size.height) + (target_height - default_height) * scale
	if default_width <= 0 || default_height <= 0 || scale <= 0 || width <= 0 || height <= 0 {
		return none
	}
	return apprt.SurfaceSize{
		width:  u32(width)
		height: u32(height)
	}
}

fn surface_core_cursor_pos_cb(data voidptr) !apprt.CursorPos {
	self := unsafe { &SurfaceWidget(data) }
	return self.get_cursor_pos()
}

fn surface_core_title_cb(data voidptr) ?string {
	self := unsafe { &SurfaceWidget(data) }
	return self.get_title()
}

fn surface_core_set_clipboard_cb(data voidptr, clipboard apprt.Clipboard, contents []apprt.ClipboardContent, confirm bool) ! {
	mut self := unsafe { &SurfaceWidget(data) }
	self.set_clipboard(clipboard, contents, confirm)
}

fn surface_core_supports_clipboard_cb(data voidptr, clipboard apprt.Clipboard) bool {
	_ = data
	_ = clipboard
	return true
}

fn surface_core_clipboard_request_cb(data voidptr, clipboard apprt.Clipboard, request apprt.ClipboardRequest) !bool {
	mut self := unsafe { &SurfaceWidget(data) }
	return self.clipboard_request(clipboard, request)!
}

fn surface_core_default_env_cb(data voidptr) !map[string]string {
	self := unsafe { &SurfaceWidget(data) }
	return self.default_termio_env()!
}

// --- Clipboard ------------------------------------------------------------

// clipboard_for returns the GdkClipboard for the given apprt clipboard type.
// Mirrors the `Clipboard.get` helper.
fn (self &SurfaceWidget) clipboard_for(clipboard apprt.Clipboard) GdkClipboard {
	return match clipboard {
		.standard { C.gtk_widget_get_clipboard(self.gl_area) }
		.selection, .primary { C.gtk_widget_get_primary_clipboard(self.gl_area) }
	}
}

// set_clipboard sets the clipboard contents. Mirrors `Surface.setClipboard` +
// `Clipboard.set`, including all MIME providers and OSC 52 confirmation.
pub fn (mut self SurfaceWidget) set_clipboard(clipboard_type apprt.Clipboard, contents []apprt.ClipboardContent, confirm bool) {
	// Grab the plaintext content used for signals and confirmation dialogs.
	mut text := ''
	mut found := false
	for content in contents {
		if content.mime == 'text/plain' {
			text = content.data
			found = true
			break
		}
	}
	if !found {
		return
	}

	if !confirm {
		clipboard := self.clipboard_for(clipboard_type)
		if isnil(clipboard) {
			return
		}

		mut providers := []GdkContentProvider{cap: contents.len}
		for content in contents {
			bytes := C.g_bytes_new(content.data.str, uint(content.data.len))
			if content.mime == 'text/plain' {
				mut text_providers := [
					C.gdk_content_provider_new_for_bytes(c'text/plain;charset=utf-8', bytes),
					C.gdk_content_provider_new_for_bytes(c'text/plain', bytes),
				]
				providers << C.gdk_content_provider_new_union(unsafe { &text_providers[0] }, text_providers.len)
			} else {
				providers << C.gdk_content_provider_new_for_bytes(&char(content.mime.str), bytes)
			}
			C.g_bytes_unref(bytes)
		}
		if providers.len > 0 {
			all := C.gdk_content_provider_new_union(unsafe { &providers[0] }, providers.len)
			if !isnil(all) {
				_ = C.gdk_clipboard_set_content(clipboard, all)
				object_unref(all)
			} else {
				C.gdk_clipboard_set_text(clipboard, text.str)
			}
		} else {
			C.gdk_clipboard_set_text(clipboard, text.str)
		}
		C.g_signal_emit_by_name(self.widget, c'clipboard-write', int(clipboard_type), text.str)
		return
	}

	self.show_clipboard_confirmation(apprt.ClipboardRequestOsc52Write{
		clipboard: clipboard_type
	}, text)
}

// clipboard_request requests clipboard contents (reads the clipboard). Mirrors
// `Surface.clipboardRequest` + `Clipboard.request`.
pub fn (mut self SurfaceWidget) clipboard_request(clipboard_type apprt.Clipboard, state apprt.ClipboardRequest) !bool {
	clipboard := self.clipboard_for(clipboard_type)
	if isnil(clipboard) {
		return false
	}

	if state is apprt.ClipboardRequestPaste {
		formats := C.gdk_clipboard_get_formats(clipboard)
		if isnil(formats) || !C.gdk_content_formats_contain_gtype(formats, g_type_string) {
			log.debug('clipboard has no text format, not starting paste request')
			return false
		}
	}

	request := &ClipboardReadRequest{
		surface: self
		state:   state
	}
	self.pending_clipboard_reads << request
	object_ref(self.widget)
	C.gdk_clipboard_read_text_async(clipboard, unsafe { nil }, GCallback(voidptr(surface_clipboard_read_text_cb)), request)
	return true
}

fn surface_clipboard_read_text_cb(source GObject, result GAsyncResult, data voidptr) {
	if isnil(source) || isnil(data) {
		return
	}
	mut request := unsafe { &ClipboardReadRequest(data) }
	mut self := unsafe { request.surface }
	defer {
		self.finish_clipboard_read(request)
		object_unref(self.widget)
	}

	mut read_error := GError(unsafe { nil })
	text_ptr := C.gdk_clipboard_read_text_finish(GdkClipboard(source), result, &read_error)
	if !isnil(read_error) {
		log.warn('failed to read clipboard err=${error_message(read_error)}')
		C.g_error_free(read_error)
		return
	}
	if isnil(text_ptr) || !self.has_core() {
		return
	}
	defer {
		C.g_free(text_ptr)
	}
	text := unsafe { cstring_to_vstring(text_ptr) }
	mut surface := self.core_surface
	surface.complete_clipboard_request(request.state, text, false) or {
		if err.msg() in ['UnsafePaste', 'UnauthorizedPaste'] {
			self.show_clipboard_confirmation(request.state, text)
			return
		}
		log.warn('failed to complete clipboard request err=${err}')
		return
	}
	C.g_signal_emit_by_name(self.widget, c'clipboard-read')
}

// paste pastes explicit text into the surface, routing an unsafe or
// unauthorized paste to the confirmation dialog. Mirrors `Clipboard.paste`.
pub fn (mut self SurfaceWidget) paste(text string) {
	if text.len == 0 {
		return
	}
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	surface.complete_clipboard_request(apprt.ClipboardRequestPaste{}, text, false) or {
		if err.msg() in ['UnsafePaste', 'UnauthorizedPaste'] {
			self.show_clipboard_confirmation(apprt.ClipboardRequestPaste{}, text)
			return
		}
		log.warn('failed to complete clipboard request err=${err}')
	}
}

fn (mut self SurfaceWidget) finish_clipboard_read(request &ClipboardReadRequest) {
	for i, pending in self.pending_clipboard_reads {
		if pending == request {
			self.pending_clipboard_reads.delete(i)
			return
		}
	}
}

fn (mut self SurfaceWidget) show_clipboard_confirmation(request apprt.ClipboardRequest, text string) {
	mut dialog := clipboard_confirmation_dialog_new_for_request(request, text)
	dialog.set_canvas_enabled(!isnil(self.config) && gtk_canvas_styles_enabled(self.config.get()))
	self.pending_clipboard_dialogs << dialog
	C.g_signal_connect_data(dialog.dialog.obj, c'confirm', GCallback(voidptr(surface_clipboard_confirmation_confirm_cb)), self, unsafe { nil }, 0)
	C.g_signal_connect_data(dialog.dialog.obj, c'deny', GCallback(voidptr(surface_clipboard_confirmation_deny_cb)), self, unsafe { nil }, 0)
	dialog.present(self.widget)
}

fn (mut self SurfaceWidget) clipboard_dialog_for_object(obj GObject) ?&ClipboardConfirmationDialog {
	for dialog in self.pending_clipboard_dialogs {
		if dialog.dialog.obj == obj {
			return dialog
		}
	}
	return none
}

fn (mut self SurfaceWidget) finish_clipboard_dialog(dialog &ClipboardConfirmationDialog) {
	for i, pending in self.pending_clipboard_dialogs {
		if pending == dialog {
			self.pending_clipboard_dialogs.delete(i)
			return
		}
	}
}

fn surface_clipboard_confirmation_confirm_cb(obj GObject, remember int, data voidptr) {
	if isnil(obj) || isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	mut dialog := self.clipboard_dialog_for_object(obj) or { return }
	request := dialog.get_request() or { return }
	defer {
		self.finish_clipboard_dialog(dialog)
	}
	text_buffer := dialog.get_clipboard_contents() or { return }
	mut text_ptr := &char(unsafe { nil })
	C.g_object_get(GObject(text_buffer), c'text', &text_ptr, &char(unsafe { nil }))
	if isnil(text_ptr) {
		return
	}
	defer {
		C.g_free(text_ptr)
	}
	text := unsafe { cstring_to_vstring(text_ptr) }
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	if remember != 0 {
		match request {
			apprt.ClipboardRequestOsc52Read {
				surface.config.clipboard_read = .allow
			}
			apprt.ClipboardRequestOsc52Write {
				surface.config.clipboard_write = .allow
			}
			apprt.ClipboardRequestPaste {}
		}
	}
	surface.complete_clipboard_request(request, text, true) or {
		log.warn('failed to complete clipboard request: ${err}')
	}
}

fn surface_clipboard_confirmation_deny_cb(obj GObject, remember int, data voidptr) {
	if isnil(obj) || isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	mut dialog := self.clipboard_dialog_for_object(obj) or { return }
	request := dialog.get_request() or { return }
	defer {
		self.finish_clipboard_dialog(dialog)
	}
	if remember == 0 || !self.has_core() {
		return
	}
	mut surface := self.core_surface
	match request {
		apprt.ClipboardRequestOsc52Read {
			surface.config.clipboard_read = .deny
		}
		apprt.ClipboardRequestOsc52Write {
			surface.config.clipboard_write = .deny
		}
		apprt.ClipboardRequestPaste {
			panic('paste should not be able to be remembered')
		}
	}
}

// --- Gtk.Scrollable adjustments -------------------------------------------

// get_hadjustment returns the horizontal adjustment. Mirrors
// `Surface.getHAdjustment`.
pub fn (self &SurfaceWidget) get_hadjustment() ?GtkAdjustment {
	if isnil(self.hadj) {
		return none
	}
	return self.hadj
}

// get_h_adjustment is the source-shaped `Surface.getHAdjustment` entry point.
pub fn (self &SurfaceWidget) get_h_adjustment() ?GtkAdjustment {
	return self.get_hadjustment()
}

// set_hadjustment sets the horizontal adjustment (reffed). Mirrors
// `Surface.setHAdjustment`.
pub fn (mut self SurfaceWidget) set_hadjustment(adj ?GtkAdjustment) {
	C.g_object_freeze_notify(self.widget)
	defer {
		C.g_object_thaw_notify(self.widget)
	}
	self.notify_property(g_surface_pspec_hadjustment)
	if !isnil(self.hadj) {
		object_unref(self.hadj)
		self.hadj = unsafe { nil }
	}
	new_adjustment := adj or { return }
	object_ref(new_adjustment)
	self.hadj = new_adjustment
}

// set_h_adjustment is the source-shaped `Surface.setHAdjustment` entry point.
pub fn (mut self SurfaceWidget) set_h_adjustment(adj ?GtkAdjustment) {
	self.set_hadjustment(adj)
}

// get_vadjustment returns the vertical adjustment. Mirrors
// `Surface.getVAdjustment`.
pub fn (self &SurfaceWidget) get_vadjustment() ?GtkAdjustment {
	if isnil(self.vadj) {
		return none
	}
	return self.vadj
}

// get_v_adjustment is the source-shaped `Surface.getVAdjustment` entry point.
pub fn (self &SurfaceWidget) get_v_adjustment() ?GtkAdjustment {
	return self.get_vadjustment()
}

// set_vadjustment sets the vertical adjustment (reffed). Mirrors
// `Surface.setVAdjustment`.
pub fn (mut self SurfaceWidget) set_vadjustment(adj ?GtkAdjustment) {
	C.g_object_freeze_notify(self.widget)
	defer {
		C.g_object_thaw_notify(self.widget)
	}
	self.notify_property(g_surface_pspec_vadjustment)
	if !isnil(self.vadj) {
		object_unref(self.vadj)
		self.vadj = unsafe { nil }
	}
	new_adjustment := adj or {
		self.update_vadjustment_signal_target()
		return
	}
	object_ref(new_adjustment)
	self.vadj = new_adjustment
	self.update_vadjustment_signal_target()
}

// set_v_adjustment is the source-shaped `Surface.setVAdjustment` entry point.
pub fn (mut self SurfaceWidget) set_v_adjustment(adj ?GtkAdjustment) {
	self.set_vadjustment(adj)
}

fn (mut self SurfaceWidget) update_vadjustment_signal_target() {
	if isnil(self.vadj_signal_group) {
		self.vadj_signal_group = C.g_signal_group_new(C.gtk_adjustment_get_type())
		C.g_signal_group_connect_data(self.vadj_signal_group, c'value-changed', GCallback(voidptr(surface_vadjustment_changed_cb)), voidptr(self), unsafe { nil }, 0)
	}
	target := if isnil(self.vadj) { GObject(unsafe { nil }) } else { GObject(self.vadj) }
	C.g_signal_group_set_target(self.vadj_signal_group, target)
}

fn surface_vadjustment_changed_cb(adj GtkAdjustment, data voidptr) {
	if isnil(adj) || isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	if !self.has_core() {
		return
	}
	value := C.gtk_adjustment_get_value(adj)
	row := if value <= 0 { u64(0) } else { u64(value + 0.5) }
	mut surface := self.core_surface
	surface.perform_binding_action(input.ActionScrollToRow{ value: uint(row) }) or {
		log.error('error performing scroll_to_row action err=${err}')
	}
}

fn f64_approx_eq_abs(a f64, b f64, tolerance f64) bool {
	delta := a - b
	return (if delta < 0 { -delta } else { delta }) <= tolerance
}

// set_scrollbar updates the GtkScrollable adjustment without feeding the
// resulting value-changed signal back into the core. Mirrors `setScrollbar`.
pub fn (mut self SurfaceWidget) set_scrollbar(scrollbar terminal.Scrollbar) {
	if isnil(self.vadj) {
		return
	}
	value := f64(scrollbar.offset)
	upper := f64(scrollbar.total)
	page_size := f64(scrollbar.len)
	if f64_approx_eq_abs(C.gtk_adjustment_get_value(self.vadj), value, 0.001)
		&& f64_approx_eq_abs(C.gtk_adjustment_get_upper(self.vadj), upper, 0.001)
		&& f64_approx_eq_abs(C.gtk_adjustment_get_page_size(self.vadj), page_size, 0.001) {
		return
	}
	assert !isnil(self.vadj_signal_group)
	C.g_signal_group_block(self.vadj_signal_group)
	C.gtk_adjustment_configure(self.vadj, value, 0, upper, 1, page_size, page_size)
	C.g_signal_group_unblock(self.vadj_signal_group)
}

// set_search_active mirrors `setSearchActive`: update the overlay property,
// optionally replace the needle, and focus/select the entry when opening.
pub fn (mut self SurfaceWidget) set_search_active(active bool, needle string) {
	if isnil(self.search_overlay) {
		return
	}
	self.search_overlay.set_search_active(active)
	self.sync_unfocused_split_overlay()
	if needle.len > 0 {
		self.search_overlay.set_search_contents(needle)
	}
	if active {
		self.search_overlay.grab_focus()
	}
}

pub fn (mut self SurfaceWidget) set_search_total(total ?uint) {
	if isnil(self.search_overlay) {
		return
	}
	self.search_overlay.set_search_total(total)
}

pub fn (mut self SurfaceWidget) set_search_selected(selected ?uint) {
	if isnil(self.search_overlay) {
		return
	}
	self.search_overlay.set_search_selected(selected)
}

// key_sequence_action mirrors Surface.keySequenceAction. Each trigger is
// converted to the same human-readable GTK label and appended until an end
// action clears the pending sequence.
pub fn (mut self SurfaceWidget) key_sequence_action(value apprt.KeySequence) {
	C.g_object_freeze_notify(self.widget)
	defer {
		C.g_object_thaw_notify(self.widget)
	}
	self.notify_property(g_surface_pspec_key_sequence)
	match value {
		input.Trigger {
			label := label_from_trigger(value) or { return }
			self.key_sequence << label.clone()
		}
		apprt.KeySequenceEnd {
			self.key_sequence.clear()
		}
	}

	if !isnil(self.key_state_overlay) {
		mut list := StringList.create(self.key_sequence)
		self.key_state_overlay.set_sequence(list)
	}
}

// key_table_action mirrors Surface.keyTableAction, maintaining the activation
// stack displayed by the key-state overlay.
pub fn (mut self SurfaceWidget) key_table_action(value apprt.KeyTable) {
	C.g_object_freeze_notify(self.widget)
	defer {
		C.g_object_thaw_notify(self.widget)
	}
	self.notify_property(g_surface_pspec_key_table)
	match value {
		apprt.KeyTableActivate {
			self.key_tables << value.name.clone()
		}
		apprt.KeyTableDeactivate {
			if self.key_tables.len > 0 {
				self.key_tables.delete_last()
			}
		}
		apprt.KeyTableDeactivateAll {
			self.key_tables.clear()
		}
	}

	if !isnil(self.key_state_overlay) {
		mut list := StringList.create(self.key_tables)
		self.key_state_overlay.set_tables(list)
	}
}

// child_exited mirrors Surface.childExited: keep the surface state in sync and
// show the native banner with the full exit payload.
pub fn (mut self SurfaceWidget) child_exited(data apprt.ChildExited) bool {
	self.child_exited = true
	self.notify_property(g_surface_pspec_child_exited)
	if !supports_banner() || isnil(self.child_exited_overlay) {
		return false
	}
	self.child_exited_overlay.set_data(data)
	C.gtk_widget_set_visible(self.child_exited_overlay.widget, true)
	return true
}

fn surface_search_stop_cb(overlay GtkWidget, data voidptr) {
	_ = overlay
	if isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	surface.perform_binding_action(input.ActionEndSearch{}) or {
		log.warn('unable to perform end_search action err=${err}')
	}
	C.gtk_widget_grab_focus(GtkWidget(self.gl_area))
}

fn surface_search_changed_cb(overlay GtkWidget, needle_ptr &char, data voidptr) {
	_ = overlay
	if isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	if !self.has_core() {
		return
	}
	mut needle := ''
	if !isnil(needle_ptr) {
		unsafe {
			needle = cstring_to_vstring(needle_ptr)
		}
	}
	mut surface := self.core_surface
	surface.perform_binding_action(input.ActionSearch{ value: needle }) or {
		log.warn('unable to perform search action err=${err}')
	}
}

fn surface_search_next_cb(overlay GtkWidget, data voidptr) {
	_ = overlay
	surface_search_navigate(data, .next)
}

fn surface_search_previous_cb(overlay GtkWidget, data voidptr) {
	_ = overlay
	surface_search_navigate(data, .previous)
}

fn surface_search_navigate(data voidptr, direction input.NavigateSearch) {
	if isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	if !self.has_core() {
		return
	}
	mut surface := self.core_surface
	surface.perform_binding_action(input.ActionNavigateSearch{ value: direction }) or {
		log.warn('unable to perform navigate_search action err=${err}')
	}
}

// --- Container requests ---------------------------------------------------

// close requests the surface be closed. Mirrors `Surface.close` (emits
// `close-request`).
pub fn (self &SurfaceWidget) close() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'close-request')
	}
}

// present requests this surface come to the front. Mirrors `Surface.present`
// (emits `present-request`).
pub fn (self &SurfaceWidget) present() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'present-request')
	}
}

// toggle_fullscreen requests the container toggle fullscreen. Mirrors
// `Surface.toggleFullscreen` (emits `toggle-fullscreen`).
pub fn (self &SurfaceWidget) toggle_fullscreen() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'toggle-fullscreen')
	}
}

// toggle_maximize requests the container toggle maximize. Mirrors
// `Surface.toggleMaximize` (emits `toggle-maximize`).
pub fn (self &SurfaceWidget) toggle_maximize() {
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'toggle-maximize')
	}
}

// toggle_command_palette asks the containing window to toggle its command
// palette. Mirrors `Surface.toggleCommandPalette`.
pub fn (self &SurfaceWidget) toggle_command_palette() bool {
	return C.gtk_widget_activate_action_variant(self.widget, c'win.toggle-command-palette',
		unsafe { nil })
}

// control_inspector controls the terminal inspector window. Mirrors
// Surface.controlInspector.
pub fn (mut self SurfaceWidget) control_inspector(value apprt.InspectorAction) bool {
	if !isnil(self.inspector) {
		match value {
			.show {}
			.toggle, .hide {
				mut inspector_window := unsafe { self.inspector }
				inspector_window.close()
			}
		}
		return true
	}

	match value {
		.toggle, .show {
			inspector_window := new_inspector_window(mut self)
			self.inspector = inspector_window
			inspector_window.present()
		}
		.hide {}
	}
	return true
}

// redraw_inspector redraws the inspector, if any. Mirrors
// `Surface.redrawInspector`.
pub fn (self &SurfaceWidget) redraw_inspector() {
	if !isnil(self.inspector) {
		self.inspector.queue_render()
	}
}

// --- GObject class registration -------------------------------------------
//
// In ghostty, the class is registered via
// gobject.ext.defineClass(...) with an instanceInit, classInit, a Private
// struct, and the gtk.Scrollable interface. classInit loads the blueprint
// `.ui` template (setTemplateFromResource), binds template children
// (gl_area, im_context, url_left/right, context_menu, drop_target,
// progress_bar_overlay, error_page, terminal_page, resize/search/key-state
// overlays, child_exited_overlay), binds template callbacks (the ec_*/gc_*/
// glarea_*/im_* handlers above), and registers properties/signals.
//
// The V port registers the AdwBin subclass above, creates blueprint children
// programmatically below, and wires callbacks with g_signal_connect_data.
// The GtkScrollable interface is registered above. The remaining non-scroll
// properties still need native registration; handlers are plain methods rather
// than C template callbacks.

// new_surface_widget creates a new SurfaceWidget. Mirrors `Surface.new`
// (gobject.ext.newInstance). It builds the translated blueprint children and
// returns a wrapper with the private-field defaults from the Zig `init`.
fn surface_error_page_new() GtkWidget {
	page := C.adw_status_page_new()
	C.adw_status_page_set_icon_name(page, c'computer-fail-symbolic')
	title := i18n_('Oh, no.')
	description := i18n_('Unable to acquire an OpenGL context for rendering.')
	C.adw_status_page_set_title(page, &char(title.str))
	C.adw_status_page_set_description(page, &char(description.str))
	link := C.gtk_link_button_new_with_label(c'https://github.com/witty-terminal/witty/issues', c'https://github.com/witty-terminal/witty/issues')
	C.adw_status_page_set_child(page, link)
	return GtkWidget(page)
}

fn surface_menu_section(root GMenu, section GMenu) {
	C.g_menu_append_section(root, &char(unsafe { nil }), GMenuModel(section))
	object_unref(GObject(section))
}

fn surface_menu_append(menu GMenu, label string, detailed_action &char) {
	translated := i18n_(label)
	C.g_menu_append(menu, &char(translated.str), detailed_action)
}

fn surface_menu_append_submenu(menu GMenu, label string, submenu GMenu) {
	translated := i18n_(label)
	C.g_menu_append_submenu(menu, &char(translated.str), GMenuModel(submenu))
}

fn surface_context_menu_new() GtkPopover {
	root := C.g_menu_new()

	mut section := C.g_menu_new()
	surface_menu_append(section, 'Copy', c'win.copy')
	surface_menu_append(section, 'Paste', c'win.paste')
	surface_menu_append(section, 'Notify on Next Command Finish', c'surface.notify-on-next-command-finish')
	surface_menu_section(root, section)

	section = C.g_menu_new()
	surface_menu_append(section, 'Clear', c'win.clear')
	surface_menu_append(section, 'Reset', c'win.reset')
	surface_menu_section(root, section)

	section = C.g_menu_new()
	mut submenu := C.g_menu_new()
	surface_menu_append(submenu, 'Change Title…', c'surface.prompt-title')
	surface_menu_append(submenu, 'Split Up', c'split-tree.new-split::up')
	surface_menu_append(submenu, 'Split Down', c'split-tree.new-split::down')
	surface_menu_append(submenu, 'Split Left', c'split-tree.new-split::left')
	surface_menu_append(submenu, 'Split Right', c'split-tree.new-split::right')
	surface_menu_append(submenu, 'Close Split', c'split-tree.close-split')
	surface_menu_append_submenu(section, 'Split', submenu)
	object_unref(GObject(submenu))

	submenu = C.g_menu_new()
	surface_menu_append(submenu, 'New Tab', c'win.new-tab')
	surface_menu_append(submenu, 'Close Tab', c'tab.close::this')
	surface_menu_append_submenu(section, 'Tab', submenu)
	object_unref(GObject(submenu))

	submenu = C.g_menu_new()
	surface_menu_append(submenu, 'New Window', c'win.new-window')
	surface_menu_append(submenu, 'Close Window', c'win.close')
	surface_menu_append_submenu(section, 'Window', submenu)
	object_unref(GObject(submenu))
	surface_menu_section(root, section)

	section = C.g_menu_new()
	submenu = config_menu_new()
	surface_menu_append_submenu(section, 'Config', submenu)
	object_unref(GObject(submenu))
	surface_menu_section(root, section)

	popover := C.witty_gtk_menu_canvas_new(GMenuModel(root), 1, gtk_canvas_solid_mask())
	object_unref(GObject(root))
	C.gtk_popover_set_has_arrow(GtkPopover(popover), 0)
	C.gtk_widget_set_halign(popover, int(Align.start))
	return GtkPopover(popover)
}

fn surface_url_label_new(halign Align) GtkLabel {
	label := C.gtk_label_new(&char(unsafe { nil }))
	C.gtk_widget_add_css_class(label, c'background')
	C.gtk_widget_add_css_class(label, c'url-overlay')
	C.gtk_widget_set_visible(label, false)
	C.gtk_widget_set_halign(label, int(halign))
	C.gtk_widget_set_valign(label, int(Align.end))
	return GtkLabel(label)
}

const gtk_revealer_transition_crossfade = 1

fn surface_revealer_new(child GtkWidget, duration u32, crossfade bool) GtkWidget {
	revealer := C.gtk_revealer_new()
	C.gtk_revealer_set_child(revealer, child)
	C.gtk_revealer_set_transition_duration(revealer, duration)
	if crossfade {
		C.gtk_revealer_set_transition_type(revealer, gtk_revealer_transition_crossfade)
	}
	C.gtk_widget_set_can_target(revealer, false)
	C.gtk_widget_set_focusable(revealer, 0)
	return revealer
}

fn surface_readonly_revealer_new() GtkWidget {
	box := C.gtk_box_new(0, 6)
	C.gtk_widget_add_css_class(box, c'readonly_overlay')
	tooltip := i18n_('This terminal is in read-only mode. You can still view, select, and scroll through the content, but no input events will be sent to the running application.')
	C.gtk_widget_set_tooltip_text(box, &char(tooltip.str))
	C.gtk_widget_set_halign(box, int(Align.end))
	C.gtk_widget_set_valign(box, int(Align.start))
	C.gtk_box_append(box, C.gtk_image_new_from_icon_name(c'changes-prevent-symbolic'))
	label := i18n_('Read-only')
	C.gtk_box_append(box, C.gtk_label_new(&char(label.str)))
	return surface_revealer_new(box, 500, true)
}

fn surface_bell_revealer_new() GtkWidget {
	box := surface_bell_box_new()
	C.gtk_widget_add_css_class(box, c'bell-overlay')
	C.gtk_widget_set_halign(box, int(Align.fill))
	C.gtk_widget_set_valign(box, int(Align.fill))
	return surface_revealer_new(box, 500, true)
}

fn surface_unfocused_revealer_new() GtkWidget {
	drawing_area := C.gtk_drawing_area_new()
	C.gtk_widget_add_css_class(drawing_area, c'unfocused-split')
	return surface_revealer_new(drawing_area, 0, false)
}

pub fn new_surface_widget(window &Window, split_tree &SplitTreeWidget, config &Config) &SurfaceWidget {
	obj := C.g_object_new(terminal_surface_get_type(), &char(unsafe { nil }))
	C.gtk_widget_add_css_class(GtkWidget(obj), c'surface')
	gl_area := C.gtk_gl_area_new()
	C.gtk_widget_set_hexpand(GtkWidget(gl_area), 1)
	C.gtk_widget_set_vexpand(GtkWidget(gl_area), 1)
	C.gtk_widget_set_focusable(GtkWidget(gl_area), 1)
	C.gtk_widget_set_focus_on_click(GtkWidget(gl_area), 1)
	C.gtk_gl_area_set_has_stencil_buffer(gl_area, 0)
	C.gtk_gl_area_set_has_depth_buffer(gl_area, 0)
	C.gtk_gl_area_set_allowed_apis(gl_area, gdk_gl_api_gl)
	box := C.gtk_box_new(0, 0)
	C.gtk_box_append(box, GtkWidget(gl_area))
	context_menu := surface_context_menu_new()
	C.gtk_box_append(box, GtkWidget(context_menu))
	terminal_page := C.witty_gtk_terminal_overlay_new()
	C.gtk_overlay_set_child(terminal_page, box)
	readonly_revealer := surface_readonly_revealer_new()
	progress_bar_overlay := surface_progress_bar_new()
	bell_revealer := surface_bell_revealer_new()
	url_left := surface_url_label_new(.start)
	url_right := surface_url_label_new(.end)
	resize_overlay := new_resize_overlay()
	search_overlay := new_search_overlay()
	key_state_overlay := new_key_state_overlay()
	child_exited_overlay := new_surface_child_exited()
	unfocused_revealer := surface_unfocused_revealer_new()
	C.gtk_widget_set_visible(child_exited_overlay.widget, false)
	C.witty_gtk_terminal_overlay_add(terminal_page, readonly_revealer)
	C.gtk_overlay_add_overlay(terminal_page, progress_bar_overlay)
	C.gtk_overlay_add_overlay(terminal_page, bell_revealer)
	C.gtk_overlay_add_overlay(terminal_page, child_exited_overlay.widget)
	C.gtk_overlay_add_overlay(terminal_page, resize_overlay.widget)
	C.witty_gtk_terminal_overlay_add(terminal_page, GtkWidget(url_left))
	C.witty_gtk_terminal_overlay_add(terminal_page, GtkWidget(url_right))
	C.gtk_overlay_add_overlay(terminal_page, search_overlay.widget)
	C.gtk_overlay_add_overlay(terminal_page, key_state_overlay.widget)
	C.gtk_overlay_add_overlay(terminal_page, unfocused_revealer)
	C.g_object_ref_sink(GObject(terminal_page))
	C.adw_bin_set_child(AdwBin(obj), terminal_page)
	error_page := surface_error_page_new()
	C.g_object_ref_sink(GObject(error_page))

	mut w := &SurfaceWidget{
		widget:               GtkWidget(obj)
		app:                  window.app
		split_tree:           split_tree
		config:               config_ref(config)
		gl_area:              gl_area
		im_context:           C.gtk_im_multicontext_new()
		terminal_page:        terminal_page
		error_page:           error_page
		url_left:             url_left
		url_right:            url_right
		context_menu:         context_menu
		readonly_revealer:    readonly_revealer
		progress_bar_overlay: progress_bar_overlay
		bell_revealer:        bell_revealer
		resize_overlay:       resize_overlay
		search_overlay:       search_overlay
		key_state_overlay:    key_state_overlay
		child_exited_overlay: child_exited_overlay
		unfocused_revealer:   unfocused_revealer
	}
	mut native_priv := terminal_surface_priv(obj)
	native_priv.wrapper = voidptr(w)
	w.rt_surface = Surface{ surface: w }
	w.init_action_map()
	w.mouse_shape = .text
	w.apply_config()
	w.sync_unfocused_split_overlay()
	w.focused = true
	w.in_keyevent = .false_
	w.gtk_enable_primary_paste = true
	C.g_signal_connect_data(w.gl_area, c'realize', GCallback(voidptr(surface_glarea_realize_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.gl_area, c'unrealize', GCallback(voidptr(surface_glarea_unrealize_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.gl_area, c'render', GCallback(voidptr(surface_glarea_render_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.gl_area, c'resize', GCallback(voidptr(surface_glarea_resize_cb)), voidptr(w), unsafe { nil }, 0)

	focus := C.gtk_event_controller_focus_new()
	C.g_signal_connect_data(focus, c'enter', GCallback(voidptr(surface_focus_enter_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(focus, c'leave', GCallback(voidptr(surface_focus_leave_cb)), voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(box, focus)

	key := C.gtk_event_controller_key_new()
	C.g_signal_connect_data(key, c'key-pressed', GCallback(voidptr(surface_key_pressed_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(key, c'key-released', GCallback(voidptr(surface_key_released_cb)), voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(box, key)

	vertical_scroll := C.gtk_event_controller_scroll_new(gtk_event_controller_scroll_vertical)
	C.g_signal_connect_data(vertical_scroll, c'scroll', GCallback(voidptr(surface_vertical_scroll_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(vertical_scroll, c'scroll-begin', GCallback(voidptr(surface_vertical_scroll_begin_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(vertical_scroll, c'scroll-end', GCallback(voidptr(surface_vertical_scroll_end_cb)), voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(box, vertical_scroll)

	horizontal_scroll := C.gtk_event_controller_scroll_new(gtk_event_controller_scroll_horizontal)
	C.g_signal_connect_data(horizontal_scroll, c'scroll', GCallback(voidptr(surface_horizontal_scroll_cb)), voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(box, horizontal_scroll)

	motion := C.gtk_event_controller_motion_new()
	C.g_signal_connect_data(motion, c'motion', GCallback(voidptr(surface_mouse_motion_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(motion, c'leave', GCallback(voidptr(surface_mouse_leave_cb)), voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(box, motion)

	// Set up to handle items being dropped on our surface. Files can be
	// dropped from Nautilus and strings can be dropped from many programs.
	// The order of these types matter.
	// G_TYPE_INVALID because the accepted types are set below instead.
	drop_target := C.gtk_drop_target_new(g_type_invalid, gdk_action_copy)
	mut drop_target_types := [
		C.gdk_file_list_get_type(),
		C.g_file_get_type(),
		g_type_string,
	]
	C.gtk_drop_target_set_gtypes(drop_target, unsafe { &drop_target_types[0] }, uint(drop_target_types.len))
	C.g_signal_connect_data(drop_target, c'drop', GCallback(voidptr(surface_drop_target_drop_cb)),
		voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(box, drop_target)

	click := C.gtk_gesture_click_new()
	C.gtk_gesture_single_set_button(click, 0)
	C.g_signal_connect_data(click, c'pressed', GCallback(voidptr(surface_mouse_pressed_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(click, c'released', GCallback(voidptr(surface_mouse_released_cb)), voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(box, click)

	C.g_signal_connect_data(w.im_context, c'preedit-start', GCallback(voidptr(surface_im_preedit_start_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.im_context, c'preedit-changed', GCallback(voidptr(surface_im_preedit_changed_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.im_context, c'preedit-end', GCallback(voidptr(surface_im_preedit_end_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.im_context, c'commit', GCallback(voidptr(surface_im_commit_cb)), voidptr(w), unsafe { nil }, 0)
	url_motion := C.gtk_event_controller_motion_new()
	C.g_signal_connect_data(url_motion, c'enter', GCallback(voidptr(surface_url_enter_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(url_motion, c'leave', GCallback(voidptr(surface_url_leave_cb)), voidptr(w), unsafe { nil }, 0)
	C.gtk_widget_add_controller(GtkWidget(w.url_left), url_motion)
	C.g_signal_connect_data(w.context_menu, c'closed', GCallback(voidptr(surface_context_menu_closed_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.search_overlay.widget, c'stop-search', GCallback(voidptr(surface_search_stop_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.search_overlay.widget, c'search-changed', GCallback(voidptr(surface_search_changed_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.search_overlay.widget, c'next-match', GCallback(voidptr(surface_search_next_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.search_overlay.widget, c'previous-match', GCallback(voidptr(surface_search_previous_cb)), voidptr(w), unsafe { nil }, 0)
	C.g_signal_connect_data(w.child_exited_overlay.widget, c'close-request', GCallback(voidptr(surface_child_exited_close_cb)), voidptr(w), unsafe { nil }, 0)
	return w
}

fn surface_drop_target_drop_cb(target GtkDropTarget, value GValue, x f64, y f64, data voidptr) int {
	_ = target
	_ = x
	_ = y
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &SurfaceWidget(data) }
	return self.dt_drop(value)
}

// dt_drop handles an item dropped onto the surface. Mirrors `dtDrop`.
fn (mut self SurfaceWidget) dt_drop(value GValue) int {
	if g_value_holds(value, C.gdk_file_list_get_type()) {
		unboxed := C.g_value_get_boxed(value)
		if isnil(unboxed) {
			return 0
		}
		list := C.gdk_file_list_get_files(unboxed)
		mut writer := internal_os.ShellEscapeWriter.init()
		mut current := list
		for !isnil(current) {
			item := unsafe { current }
			if !isnil(item.data) {
				path_ptr := C.g_file_get_path(GFile(item.data))
				if !isnil(path_ptr) {
					writer.write(unsafe { cstring_to_vstring(path_ptr) })
					writer.write('\n')
					C.g_free(path_ptr)
				}
			}
			current = item.next
		}
		if !isnil(list) {
			C.g_slist_free(list)
		}
		self.paste(writer.string())
		return 1
	}

	if g_value_holds(value, C.g_file_get_type()) {
		object := C.g_value_get_object(value)
		if isnil(object) {
			return 0
		}
		path_ptr := C.g_file_get_path(GFile(object))
		if isnil(path_ptr) {
			return 0
		}
		defer {
			C.g_free(path_ptr)
		}
		mut writer := internal_os.ShellEscapeWriter.init()
		writer.write(unsafe { cstring_to_vstring(path_ptr) })
		writer.write('\n')
		// The source builds this string and returns without pasting it. That
		// looks like an oversight, but a single dropped file is delivered as a
		// one-element file list by every GTK version we support, so the arm is
		// unreachable in practice and is kept as the source has it.
		return 1
	}

	if g_value_holds(value, g_type_string) {
		text_ptr := C.g_value_get_string(value)
		if !isnil(text_ptr) {
			self.paste(unsafe { cstring_to_vstring(text_ptr) })
		}
		return 1
	}

	return 1
}

fn surface_child_exited_close_cb(overlay GtkWidget, data voidptr) {
	_ = overlay
	if !isnil(data) {
		self := unsafe { &SurfaceWidget(data) }
		self.close()
	}
}

fn surface_url_enter_cb(controller GtkEventControllerMotion, x f64, y f64, data voidptr) {
	_ = controller
	_ = x
	_ = y
	if !isnil(data) {
		self := unsafe { &SurfaceWidget(data) }
		C.gtk_widget_set_visible(GtkWidget(self.url_right), true)
	}
}

fn surface_url_leave_cb(controller GtkEventControllerMotion, data voidptr) {
	_ = controller
	if !isnil(data) {
		self := unsafe { &SurfaceWidget(data) }
		C.gtk_widget_set_visible(GtkWidget(self.url_right), false)
	}
}

fn surface_context_menu_closed_cb(popover GtkPopover, data voidptr) {
	_ = popover
	if !isnil(data) {
		self := unsafe { &SurfaceWidget(data) }
		self.grab_focus()
	}
}

fn surface_focus_enter_cb(controller GtkEventControllerFocus, data voidptr) {
	_ = controller
	if isnil(data) {
		return
	}
	mut self := unsafe { &SurfaceWidget(data) }
	self.ec_focus_enter()
}

fn surface_focus_leave_cb(controller GtkEventControllerFocus, data voidptr) {
	_ = controller
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.ec_focus_leave()
	}
}

fn surface_key_pressed_cb(controller GtkEventControllerKey, keyval u32, keycode u32, state u32, data voidptr) int {
	if isnil(data) {
		return 0
	}
	event := C.gtk_event_controller_get_current_event(controller)
	mut self := unsafe { &SurfaceWidget(data) }
	return b2i(self.ec_key_pressed(event, keyval, keycode, state))
}

fn surface_key_released_cb(controller GtkEventControllerKey, keyval u32, keycode u32, state u32, data voidptr) {
	if isnil(data) {
		return
	}
	event := C.gtk_event_controller_get_current_event(controller)
	mut self := unsafe { &SurfaceWidget(data) }
	self.ec_key_released(event, keyval, keycode, state)
}

fn surface_vertical_scroll_begin_cb(controller GtkEventControllerScroll, data voidptr) {
	_ = controller
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.ec_scroll_vertical_precision_begin()
	}
}

fn surface_vertical_scroll_end_cb(controller GtkEventControllerScroll, data voidptr) {
	_ = controller
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.ec_scroll_vertical_precision_end()
	}
}

fn surface_vertical_scroll_cb(controller GtkEventControllerScroll, x f64, y f64, data voidptr) int {
	_ = controller
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &SurfaceWidget(data) }
	return b2i(self.ec_scroll_vertical(x, y))
}

fn surface_horizontal_scroll_cb(controller GtkEventControllerScroll, x f64, y f64, data voidptr) int {
	_ = y
	if isnil(data) || C.gtk_event_controller_scroll_get_unit(controller) != gdk_scroll_unit_surface {
		return 0
	}
	mut self := unsafe { &SurfaceWidget(data) }
	return b2i(self.ec_scroll_horizontal(x))
}

fn surface_mouse_motion_cb(controller GtkEventControllerMotion, x f64, y f64, data voidptr) {
	if isnil(data) {
		return
	}
	event := C.gtk_event_controller_get_current_event(controller)
	mut self := unsafe { &SurfaceWidget(data) }
	self.ec_mouse_motion(event, x, y)
}

fn surface_mouse_leave_cb(controller GtkEventControllerMotion, data voidptr) {
	if isnil(data) {
		return
	}
	event := C.gtk_event_controller_get_current_event(controller)
	mut self := unsafe { &SurfaceWidget(data) }
	self.ec_mouse_leave(event)
}

fn surface_mouse_pressed_cb(gesture GtkGestureClick, n_press int, x f64, y f64, data voidptr) {
	_ = n_press
	if isnil(data) {
		return
	}
	event := C.gtk_event_controller_get_current_event(gesture)
	button := C.gtk_gesture_single_get_current_button(gesture)
	mut self := unsafe { &SurfaceWidget(data) }
	self.gc_mouse_down(event, button, x, y)
}

fn surface_mouse_released_cb(gesture GtkGestureClick, n_press int, x f64, y f64, data voidptr) {
	_ = n_press
	_ = x
	_ = y
	if isnil(data) {
		return
	}
	event := C.gtk_event_controller_get_current_event(gesture)
	button := C.gtk_gesture_single_get_current_button(gesture)
	mut self := unsafe { &SurfaceWidget(data) }
	self.gc_mouse_up(event, button)
}

fn surface_im_preedit_start_cb(context GtkIMContext, data voidptr) {
	_ = context
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.im_preedit_start()
	}
}

fn surface_im_preedit_changed_cb(context GtkIMContext, data voidptr) {
	if isnil(data) {
		return
	}
	mut text := unsafe { &char(nil) }
	C.gtk_im_context_get_preedit_string(context, &text, unsafe { nil }, unsafe { nil })
	defer {
		if !isnil(text) {
			C.g_free(text)
		}
	}
	mut preedit := ''
	if !isnil(text) {
		preedit = unsafe { cstring_to_vstring(text) }
	}
	mut self := unsafe { &SurfaceWidget(data) }
	self.im_preedit_changed(preedit)
}

fn surface_im_preedit_end_cb(context GtkIMContext, data voidptr) {
	_ = context
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.im_preedit_end()
	}
}

fn surface_im_commit_cb(context GtkIMContext, text &char, data voidptr) {
	_ = context
	if !isnil(data) && !isnil(text) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.im_commit(unsafe { cstring_to_vstring(text) })
	}
}

fn surface_glarea_realize_cb(area GtkGLArea, data voidptr) {
	_ = area
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.glarea_realize()
	}
}

fn surface_glarea_unrealize_cb(area GtkGLArea, data voidptr) {
	_ = area
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.glarea_unrealize()
	}
}

fn surface_glarea_render_cb(area GtkGLArea, context voidptr, data voidptr) int {
	_ = area
	_ = context
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &SurfaceWidget(data) }
	return b2i(self.glarea_render())
}

fn surface_glarea_resize_cb(area GtkGLArea, width int, height int, data voidptr) {
	_ = area
	if !isnil(data) {
		mut self := unsafe { &SurfaceWidget(data) }
		self.glarea_resize(width, height)
	}
}

pub fn (self &SurfaceWidget) default_termio_env() !map[string]string {
	mut env := internal_os.get_env_map()!
	for key in ['GDK_DEBUG', 'GDK_DISABLE', 'GSK_RENDERER', 'GIO_LAUNCHED_DESKTOP_FILE',
		'GIO_LAUNCHED_DESKTOP_FILE_PID', 'DBUS_STARTER_ADDRESS', 'DBUS_STARTER_BUS_TYPE',
		'INVOCATION_ID', 'JOURNAL_STREAM', 'NOTIFY_SOCKET'] {
		env.delete(key)
	}
	// Unset environment variables set by snaps when this is a Snap build. This
	// lets child processes launch other snaps without inheriting our paths.
	if buildcfg.snap && 'SNAP' in env {
		internal_os.filter_snap_paths(mut env)
	}

	// Let the owning window protocol add values such as X11's WINDOWID.
	if mut window := window_from_surface(self) {
		mut winproto := window.winproto()
		winproto.add_subprocess_env(mut env)!
		if window.is_quick_terminal() {
			env['GHOSTTY_QUICK_TERMINAL'] = '1'
		}
	}
	return env
}

// --- small numeric helpers ------------------------------------------------

fn abs_f32(v f32) f32 {
	return if v < 0 { -v } else { v }
}

fn abs_f64(v f64) f64 {
	return if v < 0 { -v } else { v }
}
