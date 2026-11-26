module macos

fn C.witty_action_shadow_offset(layer voidptr, x f64, y f64)

fn register_action_visual_methods(cls ObjId) {
	add_method(cls, 'mouseEntered:', voidptr(action_hover_entered), 'v@:@')
	add_method(cls, 'mouseExited:', voidptr(action_hover_exited), 'v@:@')
	add_method(cls, 'presentAgain:', voidptr(action_present_again), 'v@:@')
	add_method(cls, 'highlightExpired:', voidptr(action_highlight_expired), 'v@:@')
}

fn action_text_width(text string, size f64) f64 {
	font := msg_id_f64(get_class('NSFont'), 'systemFontOfSize:', size)
	attributes := msg_id2(get_class('NSDictionary'), 'dictionaryWithObject:forKey:', font, nsstring('NSFont'))
	attributed := msg_id2(alloc('NSAttributedString'), 'initWithString:attributes:', nsstring(text), attributes)
	width := C.witty_macos_text_size(attributed).width
	msg_void(attributed, 'release')
	return width
}

fn new_health_overlay() ObjId {
	container := msg_id_rect(alloc('WittyPassiveOverlay'), 'initWithFrame:', objc_rect(0, 0, 486, 128))
	icon := msg_id_rect(alloc('NSImageView'), 'initWithFrame:', objc_rect(0, 0, 128, 128))
	named := msg_id1(get_class('NSImage'), 'imageNamed:', nsstring('AppIconImage'))
	msg_void1(icon, 'setImage:', if is_nil(named) {
		msg_id(shared_app(), 'applicationIconImage')
	} else {
		named
	})
	msg_void_u64(icon, 'setImageScaling:', 0)
	heading := action_label('Oh, no. 😭', objc_rect(136, 89, 350, 36))
	msg_void1(heading, 'setFont:', msg_id_f64(get_class('NSFont'), 'systemFontOfSize:', 28))
	body := action_label('The renderer has failed. This is usually due to exhausting available GPU memory. Please free up available resources.', objc_rect(136, 15, 350, 70))
	msg_void_bool(msg_id(body, 'cell'), 'setWraps:', true)
	msg_void_u64(msg_id(body, 'cell'), 'setLineBreakMode:', 0)
	for child in [icon, heading, body] {
		msg_void1(container, 'addSubview:', child)
		msg_void(child, 'release')
	}
	return container
}

fn (mut surface NativeActionSurface) initialize_visuals() {
	layer_class := get_class('CALayer')
	surface.bell_layer = msg_id(layer_class, 'layer')
	// Keep the color and alpha in the layer so the window can blend them at
	// native precision without dithering a translucent texture.
	fill := msg_id(native_color(0xffcc00, 0.5), 'CGColor')
	for i in 0 .. surface.bell_edges.len {
		surface.bell_edges[i] = msg_id(layer_class, 'layer')
		msg_void1(surface.bell_edges[i], 'setBackgroundColor:', fill)
		msg_void1(surface.bell_layer, 'addSublayer:', surface.bell_edges[i])
	}
	C.witty_macos_msg_void_f32(surface.bell_layer, sel('setOpacity:'), 0)
	msg_void1(msg_id(surface.overlay, 'layer'), 'addSublayer:', surface.bell_layer)
}

fn bell_edge_frames(frame ObjCRect) [4]ObjCRect {
	w, h := frame.width, frame.height
	t := 3.0
	if w <= 2 * t || h <= 2 * t {
		empty := objc_rect(0, 0, 0, 0)
		return [frame, empty, empty, empty]!
	}
	// Keep the translucent corners in the horizontal strips so they blend once.
	return [objc_rect(0, 0, w, t), objc_rect(0, h - t, w, t),
		objc_rect(0, t, t, h - 2 * t), objc_rect(w - t, t, t, h - 2 * t)]!
}

fn (surface &NativeActionSurface) refresh_bell_visuals() {
	lit := surface.bell && surface.bell_border
	frame := native_canvas_overlay_rect(SplitBounds{
		width: view_width(surface.view)
		height: view_height(surface.view)
	}, view_backing_scale(surface.view))
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	msg_void_rect(surface.bell_layer, 'setFrame:', frame)
	for i, edge in bell_edge_frames(frame) {
		msg_void_rect(surface.bell_edges[i], 'setFrame:', edge)
	}
	msg_void(transaction, 'commit')
	msg_void(transaction, 'begin')
	msg_void_f64(transaction, 'setAnimationDuration:', 0.3)
	msg_void1(transaction, 'setAnimationTimingFunction:',
		msg_id1(get_class('CAMediaTimingFunction'), 'functionWithName:', nsstring('easeInEaseOut')))
	C.witty_macos_msg_void_f32(surface.bell_layer, sel('setOpacity:'), if lit { f32(1) } else { f32(0) })
	msg_void(transaction, 'commit')
}
