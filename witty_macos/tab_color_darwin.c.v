module witty_macos

const tab_color_indicator_size = 6.0

pub fn native_tab_color(view voidptr) int {
	if data := native_window_data(msg_id(view, 'window')) {
		return data.tab_color
	}
	return 0
}

pub fn set_native_tab_color(view voidptr, color int) {
	mut data := native_window_data(msg_id(view, 'window')) or { return }
	if color == data.tab_color { return }
	data.tab_color = color
	update_native_tab_color_indicator(data.tab_color_indicator, color)
	msg_void(data.window, 'invalidateRestorableState')
}

pub fn native_tab_display_color(view voidptr) ?voidptr {
	return native_tab_color_object(native_tab_color(view))
}

fn native_tab_color_object(color int) ?ObjId {
	selector := match color {
		1 { 'systemBlueColor' }
		2 { 'systemPurpleColor' }
		3 { 'systemPinkColor' }
		4 { 'systemRedColor' }
		5 { 'systemOrangeColor' }
		6 { 'systemYellowColor' }
		7 { 'systemGreenColor' }
		8 {
			if msg_bool1(get_class('NSColor'), 'respondsToSelector:', sel('systemMintColor')) {
				'systemMintColor'
			} else {
				'systemTealColor'
			}
		}
		9 { 'systemGrayColor' }
		else { return none }
	}
	return msg_id(get_class('NSColor'), selector)
}

fn native_tab_color_indicator_intrinsic_size(_self ObjId, _cmd Sel) ObjCSize {
	return ObjCSize{width: tab_color_indicator_size, height: tab_color_indicator_size}
}

fn new_native_tab_color_indicator(color int) ObjId {
	mut cls := get_class('WittyTabColorIndicator')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyTabColorIndicator'), 0)
		C.macos_class_add_ivar(cls, cstr('vtTabColor'), sizeof(voidptr), 3, cstr('^v'))
		add_method(cls, 'intrinsicContentSize', voidptr(native_tab_color_indicator_intrinsic_size), '{CGSize=dd}@:')
		add_method(cls, 'drawRect:', voidptr(draw_native_tab_color_indicator), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		add_method(cls, 'viewDidChangeEffectiveAppearance', voidptr(native_tab_color_appearance_changed), 'v@:')
		C.macos_objc_register_class_pair(cls)
	}
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:',
		objc_rect(0, 0, tab_color_indicator_size, tab_color_indicator_size))
	msg_void_bool(view, 'setTranslatesAutoresizingMaskIntoConstraints:', false)
	C.witty_macos_priority(view, sel('setContentCompressionResistancePriority:forOrientation:'), 250, 0)
	// Keep the title width and shortcut position stable when the color is cleared.
	for anchor in ['widthAnchor', 'heightAnchor'] {
		constraint := msg_id_f64(msg_id(view, anchor), 'constraintEqualToConstant:',
			tab_color_indicator_size)
		msg_void_bool(constraint, 'setActive:', true)
	}
	update_native_tab_color_indicator(view, color)
	return view
}

fn update_native_tab_color_indicator(view ObjId, color int) {
	if is_nil(view) { return }
	C.macos_objc_set_ptr_ivar(view, cstr('vtTabColor'), voidptr(color))
	msg_void_bool(view, 'setNeedsDisplay:', true)
}

fn native_tab_color_appearance_changed(self ObjId, _cmd Sel) {
	view_super_void(self, 'WittyTabColorIndicator', 'viewDidChangeEffectiveAppearance')
	msg_void_bool(self, 'setNeedsDisplay:', true)
}

fn draw_native_tab_color_indicator(self ObjId, _cmd Sel, _dirty ObjCRect) {
	color := native_tab_color_object(int(C.macos_objc_get_ptr_ivar(self, cstr('vtTabColor')))) or { return }
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	bounds := msg_rect(self, 'bounds')
	mut pixel_bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, &bounds, &pixel_bounds, &width, &height)
	mask := if width == height && C.CGBitmapContextGetBitsPerComponent(context) == 0 {
		native_canvas_circle_coverage(width, 1) or { return }
	} else {
		native_canvas_ellipse_mask(width, height, 1) or { return }
	}
	image := C.witty_canvas_make_text_mask(mask.pixels.data, width, height)
	if is_nil(image) { return }
	// Apply the system tint at presentation time so solid pixels keep its precision.
	C.witty_canvas_present_text_mask(context, image, &pixel_bounds, color, false)
	C.CFRelease(image)
}
