module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/action_search_panel_darwin.h"

fn C.witty_search_find_pasteboard() ObjId
fn C.witty_search_configure_editor(field ObjId)
fn C.witty_search_configure_shadow(bar ObjId)
fn C.witty_search_panel_colors(bar ObjId, plate ObjId, field_plate ObjId)
fn C.witty_search_configure_button(button ObjId, label ObjId)
fn C.witty_search_reset_cursor(button ObjId)
fn C.witty_search_symbol_bounds(symbol ObjId, bounds &ObjCRect, frame &ObjCRect) f64
fn C.witty_search_draw_count(context voidptr, view ObjId, bounds &ObjCRect, pixels &u32, width int, height int)
fn C.witty_search_fill_button(context voidptr, view ObjId, bounds &ObjCRect, pixels &u32, width int, height int, pressed bool)

const search_panel_margin = 8.0
const search_panel_height = 44.0
const search_field_width = 238.0
const search_field_height = 28.0

fn (surface &NativeActionSurface) find_pasteboard() ObjId {
	if !is_nil(surface.search_pasteboard) { return surface.search_pasteboard }
	return C.witty_search_find_pasteboard()
}

fn (surface &NativeActionSurface) read_find_query() ?string {
	query := msg_id1(surface.find_pasteboard(), 'stringForType:', nsstring('public.utf8-plain-text'))
	if is_nil(query) { return none }
	return objc_utf8_string(query)
}

fn (surface &NativeActionSurface) write_find_query(needle string) {
	if current := surface.read_find_query() {
		if current == needle { return }
	}
	board := surface.find_pasteboard()
	msg_void(board, 'clearContents')
	msg_bool2(board, 'setString:forType:', nsstring(needle), nsstring('public.utf8-plain-text'))
}

fn search_application_activated(bar ObjId, _cmd Sel, _notification ObjId) {
	mut surface := action_owner_state(bar) or { return }
	if surface.closed || !surface.search_active { return }
	query := surface.read_find_query() or { return }
	if query == surface.search_needle { return }
	surface.replace_search_query(query)
	if editor := search_field_editor(surface.search_field) {
		msg_void1(editor, 'selectAll:', nil_obj())
	}
}

fn search_field_editor(field ObjId) ?ObjId {
	editor := msg_id(field, 'currentEditor')
	if is_nil(editor) { return none }
	return editor
}

fn (mut surface NativeActionSurface) initialize_search_panel() {
	mut cls := get_class('WittySearchBar')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittySearchBar'), 0)
		add_ptr_ivar(cls, 'state')
		add_method(cls, 'isFlipped', voidptr(action_flipped), 'B@:')
		add_method(cls, 'mouseDown:', voidptr(search_drag_start), 'v@:@')
		add_method(cls, 'mouseDragged:', voidptr(search_drag_changed), 'v@:@')
		add_method(cls, 'mouseUp:', voidptr(search_drag_end), 'v@:@')
		add_method(cls, 'searchApplicationActivated:', voidptr(search_application_activated), 'v@:@')
		C.macos_objc_register_class_pair(cls)

		count := C.macos_objc_allocate_class_pair(get_class('NSTextField'), cstr('WittySearchCount'), 0)
		add_method(count, 'drawRect:', voidptr(search_draw_count), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(count, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(count)

		button := C.macos_objc_allocate_class_pair(get_class('NSButton'), cstr('WittySearchButton'), 0)
		add_ptr_ivar(button, 'hovered')
		add_method(button, 'drawRect:', voidptr(search_draw_button), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(button, 'mouseEntered:', voidptr(search_button_entered), 'v@:@')
		add_method(button, 'mouseExited:', voidptr(search_button_exited), 'v@:@')
		add_method(button, 'resetCursorRects', voidptr(search_button_cursor), 'v@:')
		C.macos_objc_register_class_pair(button)
	}
	bar := msg_id_rect(alloc('WittySearchBar'), 'initWithFrame:', ObjCRect{})
	surface.search_bar = bar
	C.macos_objc_set_ptr_ivar(bar, cstr('state'), voidptr(surface))
	msg_void_bool(bar, 'setWantsLayer:', true)
	C.witty_search_configure_shadow(bar)
	msg_void1(surface.overlay, 'addSubview:', bar)
	msg_void(bar, 'release')

	surface.search_plate = search_panel_subview('WittyPassiveOverlay', bar, ObjCRect{})
	field_frame := objc_rect(8, 8, search_field_width, search_field_height)
	surface.search_field_plate = search_panel_subview('WittyPassiveOverlay', bar, field_frame)
	surface.search_field = search_panel_subview('NSTextField', bar, objc_rect(14, 14, 184, 19))
	C.witty_search_configure_editor(surface.search_field)
	msg_void1(surface.search_field, 'setDelegate:', surface.owner)
	count := search_panel_subview('WittySearchCount', bar, objc_rect(196, 8, 50, search_field_height))
	surface.search_count = count
	msg_void_bool(count, 'setEditable:', false)
	msg_void_bool(count, 'setSelectable:', false)
	msg_void_bool(count, 'setBordered:', false)
	msg_void_bool(count, 'setDrawsBackground:', false)

	mut x := field_frame.x + field_frame.width
	for index, selector in ['searchNext:', 'searchPrevious:', 'searchClose:'] {
		symbol := C.witty_canvas_system_symbol(nsstring(['chevron.up', 'chevron.down', 'xmark'][index]), 13, 0)
		empty := ObjCRect{}
		mut unused := ObjCRect{}
		width := C.witty_search_symbol_bounds(symbol, &empty, &unused) + 4
		x += 4
		button := search_panel_subview('WittySearchButton', bar, objc_rect(x, 9, width, 26))
		msg_void1(button, 'setImage:', symbol)
		msg_void1(button, 'setTarget:', surface.owner)
		msg_void1(button, 'setAction:', sel(selector))
		C.witty_search_configure_button(button, nsstring(['Next Match', 'Previous Match', 'Close Find'][index]))
		x += width
	}
	surface.search_bar_width = x + search_panel_margin
	surface.search_scale = 0
	C.witty_macos_observe(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), bar,
		sel('searchApplicationActivated:'), nsstring('NSApplicationDidBecomeActiveNotification'), shared_app())
}

fn search_panel_subview(class_name string, parent ObjId, frame ObjCRect) ObjId {
	view := msg_id_rect(alloc(class_name), 'initWithFrame:', frame)
	msg_void_bool(view, 'setWantsLayer:', true)
	msg_void1(parent, 'addSubview:', view)
	msg_void(view, 'release')
	return view
}

fn (mut surface NativeActionSurface) remove_search_panel() {
	msg_void1(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), 'removeObserver:', surface.search_bar)
	window := view_window(surface.view)
	if editor := search_field_editor(surface.search_field) {
		if msg_id(window, 'firstResponder') == editor {
			msg_bool1(window, 'makeFirstResponder:', surface.view)
		}
	}
	msg_void1(surface.search_field, 'setDelegate:', nil_obj())
	C.macos_objc_set_ptr_ivar(surface.search_bar, cstr('state'), nil_obj())
	msg_void(surface.search_bar, 'removeFromSuperview')
	surface.search_bar = nil_obj()
	surface.search_plate = nil_obj()
	surface.search_field_plate = nil_obj()
	surface.search_field = nil_obj()
	surface.search_count = nil_obj()
	surface.search_dragging = false
}

fn (surface &NativeActionSurface) search_panel_frame() ObjCRect {
	right := surface.search_corner in [.top_right, .bottom_right]
	bottom := surface.search_corner in [.bottom_left, .bottom_right]
	return objc_rect(if right { view_width(surface.view) - surface.search_bar_width - search_panel_margin } else { search_panel_margin },
		if bottom { view_height(surface.view) - search_panel_height - search_panel_margin } else { search_panel_margin },
		surface.search_bar_width, search_panel_height)
}

fn (mut surface NativeActionSurface) refresh_search_panel() {
	if !surface.search_active || is_nil(surface.search_bar) { return }
	bar := surface.search_bar
	if !surface.search_dragging { msg_void_rect(bar, 'setFrame:', surface.search_panel_frame()) }
	C.witty_search_panel_colors(bar, surface.search_plate, surface.search_field_plate)
	surface.refresh_search_panel_masks(msg_rect(bar, 'frame'))
}

fn (mut surface NativeActionSurface) refresh_search_panel_masks(frame ObjCRect) {
	scale := view_backing_scale(surface.view)
	phases := C.witty_canvas_rect_backing_phases(surface.overlay, &frame)
	field := objc_rect(frame.x + 8, frame.y + 8, search_field_width, search_field_height)
	field_phases := C.witty_canvas_rect_backing_phases(surface.overlay, &field)
	mask_phases := phases | (field_phases << 4)
	if scale == surface.search_scale && mask_phases == surface.search_phases { return }
	width := int(math.round(surface.search_bar_width * scale))
	height := int(math.round(search_panel_height * scale))
	plate := native_canvas_grouped_continuous_rect(width, height, scale, 8, phases) or { return }
	inner := native_canvas_grouped_continuous_rect(int(math.round(search_field_width * scale)),
		int(math.round(search_field_height * scale)), scale, 6, field_phases) or { return }
	msg_void_rect(surface.search_plate, 'setFrame:', objc_rect(0, 0, surface.search_bar_width, search_panel_height))
	C.witty_canvas_set_layer_mask(msg_id(surface.search_plate, 'layer'), plate.pixels.data, width, height, scale)
	C.witty_canvas_set_layer_mask(msg_id(surface.search_field_plate, 'layer'), inner.pixels.data, inner.width, inner.height, scale)
	surface.search_scale = scale
	surface.search_phases = mask_phases
}

fn search_draw_count(view ObjId, _cmd Sel, _rect ObjCRect) {
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	frame := msg_rect(view, 'bounds')
	mut bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, &frame, &bounds, &width, &height)
	raster := canvas.new_raster_surface(width: width, height: height) or { return }
	C.witty_search_draw_count(context, view, &bounds, raster.pixels.data, width, height)
}

fn search_draw_button(view ObjId, _cmd Sel, _rect ObjCRect) {
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	bounds := msg_rect(view, 'bounds')
	pressed := msg_bool(view, 'isHighlighted')
	hovered := !is_nil(C.macos_objc_get_ptr_ivar(view, cstr('hovered')))
	if hovered || pressed {
		scale := view_backing_scale(voidptr(view))
		mask := native_canvas_grouped_continuous_rect(int(math.round(bounds.width * scale)),
			int(math.round(bounds.height * scale)), scale, 6, C.witty_canvas_backing_phases(view)) or { return }
		C.witty_search_fill_button(context, view, &bounds, mask.pixels.data, mask.width, mask.height, pressed)
	}
	symbol := msg_id(view, 'image')
	mut glyph := ObjCRect{}
	C.witty_search_symbol_bounds(symbol, &bounds, &glyph)
	color := msg_id(get_class('NSColor'), if hovered || pressed { 'labelColor' } else { 'secondaryLabelColor' })
	native_canvas_draw_symbol(context, view, symbol, glyph, color)
}

fn search_button_entered(view ObjId, _cmd Sel, _event ObjId) {
	C.macos_objc_set_ptr_ivar(view, cstr('hovered'), view)
	msg_void_bool(view, 'setNeedsDisplay:', true)
}

fn search_button_exited(view ObjId, _cmd Sel, _event ObjId) {
	C.macos_objc_set_ptr_ivar(view, cstr('hovered'), nil_obj())
	msg_void_bool(view, 'setNeedsDisplay:', true)
}

fn search_button_cursor(view ObjId, _cmd Sel) {
	C.witty_search_reset_cursor(view)
}
