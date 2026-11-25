module macos

import math

// SurfaceView.KeyStateIndicator / PendingIndicator, BellBorderOverlay
// and SecureInputOverlay. Timing and gesture thresholds are the source values.
fn C.witty_action_shadow_offset(layer voidptr, x f64, y f64)

fn register_action_visual_methods(cls ObjId) {
	add_method(cls, 'hoverEntered:', voidptr(action_hover_entered), 'v@:@')
	add_method(cls, 'hoverExited:', voidptr(action_hover_exited), 'v@:@')
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

fn new_key_indicator(surface &NativeActionSurface) ObjId {
	mut cls := get_class('WittyKeyIndicator')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSButton'), cstr('WittyKeyIndicator'), 0)
		add_ptr_ivar(cls, 'state')
		add_method(cls, 'mouseDown:', voidptr(key_indicator_down), 'v@:@')
		add_method(cls, 'mouseDragged:', voidptr(key_indicator_dragged), 'v@:@')
		add_method(cls, 'mouseUp:', voidptr(key_indicator_up), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	button := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 0, 34))
	C.macos_objc_set_ptr_ivar(button, cstr('state'), voidptr(surface))
	msg_void_bool(button, 'setBordered:', false)
	msg_void_bool(button, 'setWantsLayer:', true)
	layer := msg_id(button, 'layer')
	msg_void_f64(layer, 'setCornerRadius:', 17)
	msg_void_f64(layer, 'setBorderWidth:', 1)
	msg_void1(layer, 'setBorderColor:', msg_id(msg_id_f64(msg_id(get_class('NSColor'), 'labelColor'), 'colorWithAlphaComponent:', 0.15), 'CGColor'))
	msg_void1(layer, 'setShadowColor:', msg_id(msg_id(get_class('NSColor'), 'blackColor'), 'CGColor'))
	C.witty_macos_msg_void_f32(layer, sel('setShadowOpacity:'), 0.2)
	msg_void_f64(layer, 'setShadowRadius:', 8)
	C.witty_action_shadow_offset(layer, 0, 2)
	return button
}

fn key_indicator_down(self ObjId, _cmd Sel, event ObjId) {
	mut surface := action_owner_state(self) or { return }
	surface.key_drag_start = msg_point(event, 'locationInWindow').y
	surface.key_drag_offset = 0
	surface.key_dragging = false
}

fn key_indicator_dragged(self ObjId, _cmd Sel, event ObjId) {
	mut surface := action_owner_state(self) or { return }
	surface.key_dragging = true
	surface.key_drag_offset = surface.key_drag_start - msg_point(event, 'locationInWindow').y
	surface.refresh_key_visuals()
}

fn key_indicator_up(self ObjId, _cmd Sel, _event ObjId) {
	mut surface := action_owner_state(self) or { return }
	if !surface.key_dragging {
		action_key_info(surface.owner, nil_obj(), self)
		return
	}
	if !surface.key_top && surface.key_drag_offset < -50 {
		surface.key_top = true
	} else if surface.key_top && surface.key_drag_offset > 50 {
		surface.key_top = false
	}
	surface.key_dragging = false
	surface.key_drag_offset = 0
	surface.refresh_key_visuals()
}

fn indicator_label(text string, x f64, cap bool) (ObjId, f64) {
	width := action_text_width(text, if cap { 12.0 } else { 13.0 }) + if cap { 10.0 } else { 0.0 }
	label := action_label(text, objc_rect(x, 7, width, 20))
	msg_void1(label, 'setFont:', msg_id_f64(get_class('NSFont'), 'systemFontOfSize:', if cap {
		12
	} else {
		13
	}))
	if cap {
		msg_void_bool(label, 'setWantsLayer:', true)
		layer := msg_id(label, 'layer')
		msg_void_f64(layer, 'setCornerRadius:', 4)
		msg_void_f64(layer, 'setBorderWidth:', 0.5)
		msg_void1(layer, 'setBorderColor:', msg_id(msg_id_f64(msg_id(get_class('NSColor'), 'labelColor'), 'colorWithAlphaComponent:', 0.15), 'CGColor'))
		msg_void1(layer, 'setBackgroundColor:', msg_id(msg_id(get_class('NSColor'), 'controlBackgroundColor'), 'CGColor'))
	}
	return label, width
}

fn (mut surface NativeActionSurface) refresh_key_visuals() {
	if is_nil(surface.key_badge) { return }
	visible := surface.key_tables.len > 0 || surface.key_sequence.len > 0
	msg_void_bool(surface.key_badge, 'setHidden:', !visible)
	if !visible {
		if !is_nil(surface.pulse_timer) {
			msg_void(surface.pulse_timer, 'invalidate')
			surface.pulse_timer = nil_obj()
		}
		return
	}
	if surface.previous_sequence != surface.key_sequence || surface.previous_tables != surface.key_tables {
		surface.previous_sequence = surface.key_sequence.clone()
		surface.previous_tables = surface.key_tables.clone()
		children := msg_id(surface.key_badge, 'subviews')
		for i := int(msg_u64(children, 'count')) - 1; i >= 0; i-- {
			msg_void(msg_id_u64(children, 'objectAtIndex:', u64(i)), 'removeFromSuperview')
		}
		layer := msg_id(surface.key_badge, 'layer')
		for dot in surface.key_dots { msg_void(dot, 'removeFromSuperlayer') }
		surface.key_dots.clear()
		mut material_class := get_class('WittyKeyMaterial')
		if is_nil(material_class) {
			material_class = C.macos_objc_allocate_class_pair(get_class('NSVisualEffectView'), cstr('WittyKeyMaterial'), 0)
			add_method(material_class, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
			C.macos_objc_register_class_pair(material_class)
		}
		material := msg_id_rect(msg_id(material_class, 'alloc'), 'initWithFrame:', objc_rect(0, 0, view_width(voidptr(surface.key_badge)), 34))
		msg_void_u64(material, 'setAutoresizingMask:', 18)
		msg_void_u64(material, 'setMaterial:', 6)
		msg_void_u64(material, 'setBlendingMode:', 0)
		msg_void_bool(material, 'setWantsLayer:', true)
		msg_void_f64(msg_id(material, 'layer'), 'setCornerRadius:', 17)
		msg_void_bool(msg_id(material, 'layer'), 'setMasksToBounds:', true)
		msg_void1(surface.key_badge, 'addSubview:', material)
		msg_void(material, 'release')
		mut x := 12.0
		for i, table in surface.key_tables {
			if i == 0 {
				icon := msg_id_rect(alloc('NSImageView'), 'initWithFrame:', objc_rect(x, 10, 13, 13))
				msg_void1(icon, 'setImage:', msg_id2(get_class('NSImage'), 'imageWithSystemSymbolName:accessibilityDescription:', nsstring('keyboard.badge.ellipsis'), nil_obj()))
				msg_void1(surface.key_badge, 'addSubview:', icon)
				msg_void(icon, 'release')
				x += 18
			} else {
				arrow, w := indicator_label('›', x, false)
				msg_void1(surface.key_badge, 'addSubview:', arrow)
				msg_void(arrow, 'release')
				x += w + 5
			}
			label, w := indicator_label(table, x, false)
			msg_void1(surface.key_badge, 'addSubview:', label)
			msg_void(label, 'release')
			x += w + 5
		}
		if surface.key_tables.len > 0 && surface.key_sequence.len > 0 {
			divider := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(x + 3, 10, 1, 14))
			msg_void_bool(divider, 'setWantsLayer:', true)
			msg_void1(msg_id(divider, 'layer'), 'setBackgroundColor:', msg_id(msg_id(get_class('NSColor'), 'separatorColor'), 'CGColor'))
			msg_void1(surface.key_badge, 'addSubview:', divider)
			msg_void(divider, 'release')
			x += 12
		}
		for sequence in surface.key_sequence {
			label, w := indicator_label(sequence, x, true)
			msg_void1(surface.key_badge, 'addSubview:', label)
			msg_void(label, 'release')
			x += w + 4
		}
		if surface.key_sequence.len > 0 {
			for i in 0 .. 3 {
				dot := msg_id(get_class('CALayer'), 'layer')
				msg_void_rect(dot, 'setFrame:', objc_rect(x + f64(i) * 6, 15, 4, 4))
				msg_void_f64(dot, 'setCornerRadius:', 2)
				msg_void1(dot, 'setBackgroundColor:', msg_id(msg_id(get_class('NSColor'), 'secondaryLabelColor'), 'CGColor'))
				msg_void1(layer, 'addSublayer:', dot)
				surface.key_dots << dot
			}
			x += 16
		}
		surface.key_width = x + 12
	}
	width := math.min(view_width(surface.view) - 16, surface.key_width)
	msg_void_rect(surface.key_badge, 'setFrame:', objc_rect((view_width(surface.view) - width) / 2, (if surface.key_top {
		8.0
	} else {
		view_height(surface.view) - 42
	}) + surface.key_drag_offset, width, 34))
	if !surface.key_dragging {
		phase := msg_f64(msg_id(get_class('NSDate'), 'date'), 'timeIntervalSinceReferenceDate')
		for i, dot in surface.key_dots {
			opacity := 0.3 + 0.7 * ((math.sin((phase + f64(i) / 3) * math.pi * 2) + 1) / 2)
			C.witty_macos_msg_void_f32(dot, sel('setOpacity:'), f32(opacity))
		}
	}
	if surface.key_sequence.len > 0 && is_nil(surface.pulse_timer) {
		surface.pulse_timer = C.witty_action_timer(1.0 / 60, surface.owner, sel('pulseTimer:'), nil_obj(), true)
	} else if surface.key_sequence.len == 0 && !is_nil(surface.pulse_timer) {
		msg_void(surface.pulse_timer, 'invalidate')
		surface.pulse_timer = nil_obj()
	}
}

fn (mut surface NativeActionSurface) initialize_visuals() {
	layer_class := get_class('CALayer')
	surface.bell_layer = msg_id(layer_class, 'layer')
	for i in 0 .. surface.bell_edges.len {
		surface.bell_edges[i] = msg_id(layer_class, 'layer')
		msg_void1(surface.bell_layer, 'addSublayer:', surface.bell_edges[i])
	}
	C.witty_macos_msg_void_f32(surface.bell_layer, sel('setOpacity:'), 0)
	msg_void1(msg_id(surface.overlay, 'layer'), 'addSublayer:', surface.bell_layer)
}

fn (surface &NativeActionSurface) update_bell_tiles() {
	tile := native_canvas_fill_tile(0xffcc00, target: surface.overlay, opacity: 0.5)
	if is_nil(tile) { return }
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	for edge in surface.bell_edges {
		msg_void1(edge, 'setContents:', ObjId(tile))
	}
	msg_void(transaction, 'commit')
	C.CFRelease(tile)
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
	if lit && is_nil(msg_id(surface.bell_edges[0], 'contents')) {
		surface.update_bell_tiles()
	}
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
