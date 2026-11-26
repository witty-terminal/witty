@[has_globals]
module macos

import gg.canvas

fn C.witty_zoom_image_from_pdf(bytes &u8, count usize) ObjId

fn test_reset_zoom_canvas_preserves_pdf_coverage_at_native_backing_scales() {
	app_init()
	source := C.witty_zoom_image_from_pdf(reset_zoom_pdf.data, usize(reset_zoom_pdf.len))
	template := reset_zoom_template()
	assert !is_nil(source)
	assert !is_nil(template)
	glyph := objc_rect(0, 0, 14, 14)
	for scale in [1, 2] {
		size := 14 * scale
		mut expected := canvas.new_raster_surface(width: size, height: size) or { panic(err) }
		mut actual := canvas.new_raster_surface(width: size, height: size) or { panic(err) }
		assert C.witty_canvas_symbol_mask(source, &glyph, &glyph, expected.pixels.data, size, size, false)
		assert C.witty_canvas_symbol_mask(template, &glyph, &glyph, actual.pixels.data, size, size, false)
		assert expected.pixels.any(it >> 24 != 0)
		assert expected.pixels.map(it >> 24) == actual.pixels.map(it >> 24)
	}
}

__global ( g_zoom_probe_actions int )
fn zoom_probe_action(_userdata voidptr,action int) { assert action==10; g_zoom_probe_actions++ }

fn test_native_zoom_projection_has_real_tab_and_titlebar_controls() {
	app_init()
	view:=create_window(160,100,'zoom probe')
	window:=msg_id(view,'window')
	msg_void_bool(window,'setReleasedWhenClosed:',false)
	// ResetZoom belongs to the Ventura toolbar delegate, so select that class.
	g_native_windows[u64(window)] = &NativeWindowData{window: window}
	apply_native_window_config(view,NativeWindowConfig{decorations:true,titlebar_style:2,opacity:1},true,0x202020,1,false)
	data:=native_window_data(window) or { panic('native metadata missing') }
	previous_action:=g_action_cb
	g_action_cb=zoom_probe_action
	defer { g_action_cb=previous_action }
	view_set_userdata(view,voidptr(window))
	assert !is_nil(msg_id(window,'toolbar'))
	assert !is_nil(msg_id(msg_id(window,'tab'),'accessoryView'))
	assert msg_bool(data.zoom_tab_button,'isHidden')
	assert objc_utf8_string(msg_id(data.zoom_tab_button,'toolTip'))=='Reset Zoom'
	assert msg_id(data.zoom_tab_button,'action')==sel('splitZoom:')
	assert msg_id(data.zoom_tab_button,'target')==window
	assert msg_id(data.zoom_toolbar_button,'target')==nil_obj()
	image := msg_id(data.zoom_tab_button, 'image')
	assert !is_nil(image)
	assert msg_bool(image, 'isTemplate')
	assert msg_id(data.zoom_toolbar_button, 'image') == image
	msg_void1(data.zoom_tab_button,'performClick:',nil_obj())
	assert g_zoom_probe_actions==1
	set_native_split_zoom(view,true)
	assert !msg_bool(data.zoom_tab_button,'isHidden')
	assert !msg_bool(msg_id(data.zoom_accessory,'view'),'isHidden')
	assert msg_rect(msg_id(data.zoom_accessory,'view'),'frame').width==30
	toolbar:=msg_id(window,'toolbar')
	item:=native_toolbar_item(toolbar,nil_obj(),toolbar,nsstring('ResetZoom'),true)
	assert msg_id(item,'view')==data.zoom_toolbar_button
	constraints:=msg_id(data.zoom_toolbar_button,'constraints')
	mut width:=false
	for i in 0 .. int(msg_u64(constraints,'count')) { constraint:=msg_id_u64(constraints,'objectAtIndex:',u64(i)); if msg_u64(constraint,'firstAttribute')==7 && msg_f64(constraint,'constant')==22 { width=true } }
	assert width
	set_zoom_accessory_attached(data,false)
	items:=msg_id(window,'titlebarAccessoryViewControllers')
	for i in 0 .. int(msg_u64(items,'count')) { assert msg_id_u64(items,'objectAtIndex:',u64(i))!=data.zoom_accessory }
	set_zoom_accessory_attached(data,true)
	set_native_split_zoom(view,false)
	assert msg_bool(data.zoom_tab_button,'isHidden')
	assert msg_bool(msg_id(data.zoom_accessory,'view'),'isHidden')
	assert msg_rect(msg_id(data.zoom_accessory,'view'),'frame').width==0
	msg_void(window,'close')
	msg_void(window,'release')
}
