@[has_globals]
module macos

import gg.canvas

#insert "@VMODROOT/macos/window_zoom_abi.h"
fn C.witty_native_os_at_least(major i64,minor i64,patch i64) bool
fn C.witty_zoom_canvas_template(bytes &u8, count usize, draw fn (ObjId, &ObjCRect) bool) ObjId

const reset_zoom_pdf = $embed_file('@VMODROOT/build_assets/macos/Assets.xcassets/ResetZoom.imageset/ResetZoom.pdf').to_bytes()
const zoom_accessory_spacing = 8.0
__global g_reset_zoom_template ObjId

fn draw_reset_zoom_template(source ObjId, glyph &ObjCRect) bool {
	context := native_canvas_overlay_context()
	if is_nil(context) { return false }
	mut bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, glyph, &bounds, &width, &height)
	mut mask := canvas.new_raster_surface(width: width, height: height) or { return false }
	if !C.witty_canvas_symbol_mask(source, glyph, &bounds, mask.pixels.data, width, height, false) {
		return false
	}
	image := C.witty_canvas_make_text_mask(mask.pixels.data, width, height)
	if is_nil(image) { return false }
	C.witty_canvas_present_text_mask(context, image, &bounds, msg_id(get_class('NSColor'), 'blackColor'),
		false)
	C.CFRelease(image)
	return true
}

fn reset_zoom_template() ObjId {
	if is_nil(g_reset_zoom_template) {
		image := C.witty_zoom_canvas_template(reset_zoom_pdf.data, usize(reset_zoom_pdf.len),
			draw_reset_zoom_template)
		g_reset_zoom_template = msg_id(image, 'retain')
	}
	return g_reset_zoom_template
}

fn native_window_split_zoom(window ObjId,_cmd Sel,_sender ObjId) {
	view:=terminal_view_for_window(window)
	userdata:=view_userdata(view)
	if !is_nil(userdata) && g_action_cb != unsafe { nil } { g_action_cb(userdata,10) }
}
fn register_native_zoom_window_methods(cls ObjId) { add_method(cls,'splitZoom:',voidptr(native_window_split_zoom),'v@:@') }
fn zoom_button(window ObjId,toolbar bool) ObjId {
	button:=msg_id_rect(alloc('NSButton'),'initWithFrame:',objc_rect(0,0,20,20))
	msg_void1(button,'setTarget:',if toolbar { nil_obj() } else { window })
	msg_void1(button,'setAction:',sel('splitZoom:'))
	msg_void_bool(button,'setBordered:',false)
	msg_void_bool(button,'setAllowsExpansionToolTips:',true)
	msg_void1(button,'setToolTip:',nsstring('Reset Zoom'))
	msg_void1(button,'setContentTintColor:',msg_id(get_class('NSColor'),'controlAccentColor'))
	msg_void_u64(button,'setState:',1)
	msg_void1(button,'setImage:',reset_zoom_template())
	msg_void_bool(button,'setTranslatesAutoresizingMaskIntoConstraints:',false)
	for anchor in ['widthAnchor','heightAnchor'] { msg_void_bool(msg_id_f64(msg_id(button,anchor),'constraintEqualToConstant:',20),'setActive:',true) }
	return button
}
fn prepare_native_zoom_views(mut data NativeWindowData) {
	if !is_nil(data.zoom_tab_button) { return }
	data.zoom_tab_button=zoom_button(data.window,false)
	msg_void_bool(data.zoom_tab_button,'setHidden:',true)
	stack:=msg_id(alloc('NSStackView'),'init')
	msg_void_u64(stack,'setOrientation:',0)
	C.witty_macos_priority(stack,sel('setHuggingPriority:forOrientation:'),750,0)
	msg_void_f64(stack,'setSpacing:',4)
	msg_void_u64(stack,'setAlignment:',10)
	previous:=msg_id(msg_id(data.window,'tab'),'accessoryView')
	if !is_nil(previous) { msg_void1(stack,'addArrangedSubview:',previous) }
	data.tab_color_indicator = new_native_tab_color_indicator(data.tab_color)
	msg_void1(stack, 'addArrangedSubview:', data.tab_color_indicator)
	msg_void(data.tab_color_indicator, 'release')
	msg_void1(stack, 'addArrangedSubview:', prepare_native_tab_shortcut(mut data))
	msg_void1(stack,'addArrangedSubview:',data.zoom_tab_button)
	msg_void1(msg_id(data.window,'tab'),'setAccessoryView:',stack)
	msg_void(stack,'release')
	data.zoom_toolbar_button=zoom_button(data.window,true)
	if msg_u64(data.window,'styleMask') & ns_window_style_titled!=0 {
		data.zoom_accessory=msg_id(alloc('NSTitlebarAccessoryViewController'),'init')
		msg_void_u64(data.zoom_accessory,'setLayoutAttribute:',2)
		container:=msg_id_rect(alloc('NSView'),'initWithFrame:',objc_rect(0,0,0,0))
		button:=zoom_button(data.window,false)
		msg_void1(button,'setToolTip:',nsstring('Reset Split Zoom'))
		msg_void1(container,'addSubview:',button)
		msg_void(button,'release')
		msg_void1(data.zoom_accessory,'setView:',container)
		msg_void(container,'release')
		msg_void1(data.window,'addTitlebarAccessoryViewController:',data.zoom_accessory)
	}
}
fn release_native_zoom_views(data &NativeWindowData) {
	msg_void(data.zoom_tab_button,'release')
	msg_void(data.zoom_toolbar_button,'release')
	msg_void(data.zoom_accessory,'release')
}
fn set_zoom_accessory_attached(data &NativeWindowData,attached bool) {
	if is_nil(data.zoom_accessory) { return }
	items:=msg_id(data.window,'titlebarAccessoryViewControllers')
	for i in 0 .. int(msg_u64(items,'count')) {
		if msg_id_u64(items,'objectAtIndex:',u64(i))!=data.zoom_accessory { continue }
		if !attached { msg_void_u64(data.window,'removeTitlebarAccessoryViewControllerAtIndex:',u64(i)) }
		return
	}
	if attached && msg_u64(data.window,'styleMask') & ns_window_style_titled!=0 { msg_void1(data.window,'addTitlebarAccessoryViewController:',data.zoom_accessory) }
}
fn update_native_zoom_views(mut data NativeWindowData) {
	prepare_native_zoom_views(mut data)
	msg_void_bool(data.zoom_tab_button,'setHidden:',!data.surface_zoomed)
	color:=msg_id(get_class('NSColor'),if msg_bool(data.window,'isKeyWindow') { 'controlAccentColor' } else { 'secondaryLabelColor' })
	msg_void1(data.zoom_tab_button,'setContentTintColor:',color)
	msg_void1(data.zoom_toolbar_button,'setContentTintColor:',msg_id(get_class('NSColor'),if msg_bool(data.window,'isKeyWindow') { 'controlAccentColor' } else { 'tertiaryLabelColor' }))
	view:=msg_id(data.zoom_accessory,'view')
	toolbar:=msg_id(data.window,'toolbar')
	padding:=if C.witty_native_os_at_least(26,0,0) { if !is_nil(toolbar) { 10.0 } else { 5.0 } } else { if !is_nil(toolbar) { 9.0 } else { 4.0 } }
	width := if data.surface_zoomed { 30.0 } else { 0.0 }
	// Match the titlebar stack's spacing between the button and the spacer below it.
	height := if data.surface_zoomed { 20.0 + padding + zoom_accessory_spacing } else { 0.0 }
	msg_void_rect(view, 'setFrame:', objc_rect(0, 0, width, height))
	msg_void_bool(view,'setHidden:',!data.surface_zoomed)
	if msg_u64(msg_id(view,'subviews'),'count')>0 {
		button:=msg_id_u64(msg_id(view,'subviews'),'objectAtIndex:',0)
		msg_void_rect(button, 'setFrame:', objc_rect(0, zoom_accessory_spacing, 20, 20))
		msg_void1(button,'setContentTintColor:',msg_id(get_class('NSColor'),if msg_bool(data.window,'isMainWindow') { 'controlAccentColor' } else { 'secondaryLabelColor' }))
	}
	set_zoom_accessory_attached(data,msg_u64(msg_id(msg_id(data.window,'tabGroup'),'windows'),'count')<=1)
}
pub fn set_native_split_zoom(view voidptr,zoomed bool) {
	if mut data:=native_window_data(msg_id(view,'window')) { data.surface_zoomed=zoomed; update_native_zoom_views(mut data) }
}
