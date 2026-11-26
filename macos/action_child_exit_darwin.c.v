module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/action_child_exit_darwin.h"

fn C.witty_child_exit_duration(runtime u64) ObjId
fn C.witty_child_exit_height(size f64) f64
fn C.witty_child_exit_prepare_view(view ObjId)
fn C.witty_child_exit_set_fill(view ObjId, failed bool)
fn C.witty_child_exit_draw(context voidptr, view ObjId, text ObjId, duration ObjId, size f64, bounds &ObjCRect, pixels &u32, width int, height int)

const child_exit_suffix = 'Press any key to close the terminal.'

pub fn (mut surface NativeActionSurface) show_child_exit(code u32, runtime u64, threshold u32) {
	if surface.closed { return }
	if is_nil(surface.child_exit_banner) {
		mut cls := get_class('WittyChildExitBanner')
		if is_nil(cls) {
			cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyChildExitBanner'), 0)
			add_method(cls, 'drawRect:', voidptr(action_draw_child_exit), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
			add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
			add_method(cls, 'mouseEntered:', voidptr(action_child_exit_entered), 'v@:@')
			add_method(cls, 'mouseExited:', voidptr(action_child_exit_exited), 'v@:@')
			C.macos_objc_register_class_pair(cls)
		}
		view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', ObjCRect{})
		surface.child_exit_banner = view
		C.witty_child_exit_prepare_view(view)
		msg_void1(surface.overlay, 'addSubview:', view)
		msg_void(view, 'release')
	}
	short_run := runtime <= threshold
	surface.child_exit_error = short_run || code != 0
	surface.child_exit_duration = if short_run { objc_utf8_string(C.witty_child_exit_duration(runtime)) } else { '' }
	msg_void1(surface.child_exit_banner, 'setAccessibilityLabel:', nsstring(surface.child_exit_message()))
	surface.refresh_child_exit_banner()
	surface.refresh_hover_visuals()
}

fn (surface &NativeActionSurface) child_exit_message() string {
	if surface.child_exit_duration.len > 0 {
		return 'Process exited after ${surface.child_exit_duration}. ${child_exit_suffix}'
	}
	return 'Process exited. ${child_exit_suffix}'
}

fn (surface &NativeActionSurface) child_exit_font_size() f64 {
	if surface.scroll == unsafe { nil } || surface.scroll.cell_height <= 0 { return 13 }
	return math.min(surface.scroll.cell_height * 0.8, 30)
}

fn (surface &NativeActionSurface) child_exit_banner_height() f64 {
	if is_nil(surface.child_exit_banner) { return 0 }
	return C.witty_child_exit_height(surface.child_exit_font_size())
}

fn (surface &NativeActionSurface) refresh_child_exit_banner() {
	view := surface.child_exit_banner
	if is_nil(view) { return }
	height := surface.child_exit_banner_height()
	msg_void_rect(view, 'setFrame:', objc_rect(0, view_height(surface.view) - height,
		view_width(surface.view), height))
	C.witty_child_exit_set_fill(view, surface.child_exit_error)
	msg_void_bool(view, 'setNeedsDisplay:', true)
}

fn action_child_exit_entered(self ObjId, _cmd Sel, _event ObjId) {
	msg_void_f64(self, 'setAlphaValue:', 0)
}

fn action_child_exit_exited(self ObjId, _cmd Sel, _event ObjId) {
	msg_void_f64(self, 'setAlphaValue:', 1)
}

fn action_draw_child_exit(self ObjId, _cmd Sel, _rect ObjCRect) {
	surface := action_owner_state(msg_id(self, 'superview')) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	frame := msg_rect(self, 'bounds')
	mut bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, &frame, &bounds, &width, &height)
	raster := canvas.new_raster_surface(width: width, height: height) or { return }
	C.witty_child_exit_draw(context, self, nsstring(surface.child_exit_message()),
		nsstring(surface.child_exit_duration), surface.child_exit_font_size(), &bounds,
		raster.pixels.data, width, height)
}
