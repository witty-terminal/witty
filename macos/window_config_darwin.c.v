@[has_globals]
module macos

import gg.canvas
import math

#insert "@VMODROOT/macos/window_config_abi.h"
fn C.witty_macos_msg_void_f32(obj ObjId, selector Sel, value f32)
fn C.witty_macos_color_rgba(r f64, g f64, b f64, a f64) ObjId
fn C.witty_macos_color_components(color ObjId, r &f64, g &f64, b &f64, a &f64)
fn C.witty_macos_msg_id_obj_f64(obj ObjId, selector Sel, value ObjId, amount f64) ObjId
fn C.witty_macos_msg_super_void_u64(obj ObjId, selector Sel, value u64)
fn C.witty_macos_window_super_void0(obj ObjId, selector Sel)
fn C.witty_macos_window_super_void1(obj ObjId, selector Sel, value ObjId)
fn C.witty_macos_array(objects &voidptr, count uint) ObjId

@[heap]
struct NativeWindowData {
mut:
	config NativeWindowConfig
	window ObjId
	titlebar_color ObjId
	titlebar_fill NativeWindowCanvasFill
	buttons_fill NativeWindowCanvasFill
	light bool
	effect_hidden bool
	backdrop ObjId
	drag_handle ObjId
	title_label ObjId
	new_tab_image_layer ObjId
	backdrop_overlay ObjId
	tab_color int
	tab_color_indicator ObjId
	tab_shortcut ObjId
	tab_shortcut_text string
	tab_shortcut_key bool
	tab_shortcut_refresh_pending bool
	surface_zoomed bool
	zoom_tab_button ObjId
	zoom_toolbar_button ObjId
	zoom_accessory ObjId
	tabs_tahoe bool
	transparent_tahoe bool
	tahoe_title_view ObjId
	tahoe_title_views []ObjId
	tahoe_title string = '👻 Witty'
	tahoe_title_font ObjId
	transparent_title_font_fields []ObjId
	tahoe_has_tab_bar bool
	tahoe_main bool = true
	tahoe_frame_observer ObjId
	tahoe_group_observer ObjId
	tahoe_group ObjId
	tahoe_last_config bool
	preferred_background u32
	preferred_opacity f64 = 1
	force_opaque bool
	focused_view ObjId
}
__global ( g_native_windows map[u64]&NativeWindowData )
fn native_window_data(window ObjId) ?&NativeWindowData { return g_native_windows[u64(window)] or { none } }
fn native_window_can_become_key(_self ObjId, _cmd Sel) bool { return true }
fn native_window_update(self ObjId, cmd Sel) { C.witty_macos_window_super_void0(self, cmd); update_native_titlebar(self) }

fn sync_native_window_terminal_focus(context voidptr) {
	window := ObjId(context)
	responder := msg_id(window, 'firstResponder')
	if msg_bool1(responder, 'isKindOfClass:', get_class('VTTerminalView')) {
		dispatch_focus(responder, msg_bool(window, 'isKeyWindow'))
	}
}

fn update_terminal_focus_for_window_key_change(window ObjId) {
	// AppKit can change the key window without changing its first responder.
	if msg_bool(window, 'isKeyWindow') {
		// Wait for AppKit to finish restoring the first responder.
		C.witty_macos_dispatch_main_weak(voidptr(window), voidptr(sync_native_window_terminal_focus))
	} else {
		sync_native_window_terminal_focus(voidptr(window))
	}
}

fn native_window_key_changed(self ObjId,cmd Sel) {
	C.witty_macos_window_super_void0(self,cmd)
	update_terminal_focus_for_window_key_change(self)
	if mut data:=native_window_data(self) {
		if !data.tabs_tahoe && msg_bool(self,'isKeyWindow') && msg_u64(msg_id(msg_id(self,'tabGroup'),'windows'),'count')<2 {
			msg_void_bool(data.backdrop,'setHidden:',true)
			msg_void_bool(data.drag_handle,'setHidden:',true)
			msg_void_bool(data.title_label,'setHidden:',false)
		}
		update_native_zoom_views(mut data)
		if data.config.titlebar_style == 2 { refresh_native_window_title_attributes(self) }
		queue_native_tab_shortcuts(self)
	}
	update_native_titlebar(self)
}
fn C.sel_getName(selector Sel) &char
fn native_window_add_accessory(self ObjId, _cmd Sel, controller ObjId) {
	if mut data := native_window_data(self) {
		if data.tabs_tahoe {
			if is_tab_bar_accessory(controller) { clear_tahoe_frame_observer(mut data) }
			else { set_tahoe_has_tab_bar(mut data, false) }
		}
	}
	if data := native_window_data(self) {
		if (data.tabs_tahoe || data.config.titlebar_style == 2) && is_tab_bar_accessory(controller) {
			msg_void_u64(controller, 'setLayoutAttribute:', 2)
			msg_void_u64(self, 'setTitleVisibility:', 1)
			msg_void1(controller, 'setIdentifier:', nsstring('_ghosttyTabBar'))
		}
	}
	C.witty_macos_window_super_void1(self, sel('addTitlebarAccessoryViewController:'), controller)
	if is_tab_bar_accessory(controller) {
		if data:=native_window_data(self) { set_zoom_accessory_attached(data,false) }
		if data := native_window_data(self) { if data.tabs_tahoe { queue_tahoe_window(self, .setup, true, false, 0); return } }
		dispatch_main(push_native_tabs, voidptr(self))
	}
}
fn native_window_remove_accessory(self ObjId, _cmd Sel, index u64) {
	array := msg_id(self, 'titlebarAccessoryViewControllers')
	controller := if index < msg_u64(array, 'count') { msg_id_u64(array, 'objectAtIndex:', index) } else { nil_obj() }
	was_tabbar := is_tab_bar_accessory(controller)
	C.witty_macos_msg_super_void_u64(self, sel('removeTitlebarAccessoryViewControllerAtIndex:'), index)
	if was_tabbar { if mut data := native_window_data(self) { if data.tabs_tahoe { clear_tahoe_frame_observer(mut data); queue_tahoe_window(self, .tab_bar, true, false, 0) } } }
	if was_tabbar { if data := native_window_data(self) { msg_void_bool(data.backdrop, 'setHidden:', true); msg_void_bool(data.drag_handle, 'setHidden:', true); msg_void_bool(data.title_label, 'setHidden:', false) } }
	if was_tabbar { if data:=native_window_data(self) { set_zoom_accessory_attached(data,true) } }
}
fn native_drag_down(self ObjId, _cmd Sel, event ObjId) {
	if msg_u64(event, 'type') == 1 && msg_u64(event, 'clickCount') == 1 { msg_void1(msg_id(self, 'window'), 'performWindowDragWithEvent:', event); msg_void(msg_id(get_class('NSCursor'), 'closedHandCursor'), 'set') }
	else { msg_super_void1(self, 'mouseDown:', event) }
}
fn native_drag_enter(self ObjId, _cmd Sel, event ObjId) { msg_super_void1(self, 'mouseEntered:', event); msg_void(msg_id(self, 'window'), 'disableCursorRects'); msg_void(msg_id(get_class('NSCursor'), 'openHandCursor'), 'set') }
fn native_drag_exit(self ObjId, _cmd Sel, event ObjId) { msg_super_void1(self, 'mouseExited:', event); msg_void(msg_id(self, 'window'), 'enableCursorRects'); msg_void(msg_id(get_class('NSCursor'), 'arrowCursor'), 'set') }
fn vibrant_filter(self ObjId, _cmd Sel) ObjId { return nsstring(if msg_u64(self, 'vtAppearance') == 0 { 'plusD' } else { 'plusL' }) }
fn vibrant_appearance(self ObjId, _cmd Sel) u64 { return u64(C.macos_objc_get_ptr_ivar(self, cstr('vtType'))) }
fn register_native_window_class() {
	if !is_nil(get_class('VTTerminalWindow')) { return }
	cls := C.macos_objc_allocate_class_pair(get_class('NSWindow'), cstr('VTTerminalWindow'), 0)
	add_method(cls, 'close', voidptr(native_window_close), 'v@:')
	add_method(cls, 'canBecomeKeyWindow', voidptr(native_window_can_become_key), 'B@:')
	add_method(cls, 'canBecomeMainWindow', voidptr(native_window_can_become_key), 'B@:')
	register_native_zoom_window_methods(cls)
	register_window_font_methods(cls)
	register_tahoe_window_methods(cls)
	add_method(cls, 'nativeTabShortcutFrameChanged:', voidptr(native_tab_shortcut_frame_changed), 'v@:@')
	for selector in ['becomeKeyWindow','resignKeyWindow'] { add_method(cls,selector,voidptr(native_window_key_changed),'v@:') }
	add_method(cls, 'addTitlebarAccessoryViewController:', voidptr(native_window_add_accessory), 'v@:@')
	add_method(cls, 'removeTitlebarAccessoryViewControllerAtIndex:', voidptr(native_window_remove_accessory), 'v@:Q')
	for selector in ['update', 'layoutIfNeeded', 'updateConstraintsIfNeeded'] { add_method(cls, selector, voidptr(native_window_update), 'v@:') }
	C.macos_objc_register_class_pair(cls)
	drag_cls := C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('VTWindowDragView'), 0)
	add_method(drag_cls, 'mouseDown:', voidptr(native_drag_down), 'v@:@')
	add_method(drag_cls, 'mouseEntered:', voidptr(native_drag_enter), 'v@:@')
	add_method(drag_cls, 'mouseExited:', voidptr(native_drag_exit), 'v@:@')
	C.macos_objc_register_class_pair(drag_cls)
	layer_cls := C.macos_objc_allocate_class_pair(get_class('CALayer'), cstr('VTVibrantLayer'), 0)
	C.macos_class_add_ivar(layer_cls, cstr('vtType'), sizeof(voidptr), 3, cstr('^v'))
	add_method(layer_cls, 'vtAppearance', voidptr(vibrant_appearance), 'Q@:')
	add_method(layer_cls, 'compositingFilter', voidptr(vibrant_filter), '@@:')
	C.macos_objc_register_class_pair(layer_cls)
}
fn native_window_class() ObjId { register_native_window_class(); return get_class('VTTerminalWindow') }
fn native_color(color u32, alpha f64) ObjId { return C.witty_macos_color_rgba(f64((color >> 16) & 255) / 255, f64((color >> 8) & 255) / 255, f64(color & 255) / 255, alpha) }
// OSColor.luminance converts the native color to sRGB before reading components.
fn native_color_object_luminance(color ObjId) f64 {
	rgb := msg_id1(color, 'colorUsingColorSpace:', msg_id(get_class('NSColorSpace'), 'sRGBColorSpace'))
	if is_nil(rgb) { return 0 }
	mut r := f64(0)
	mut g := f64(0)
	mut b := f64(0)
	mut a := f64(0)
	C.witty_macos_color_components(rgb, &r, &g, &b, &a)
	return 0.299 * r + 0.587 * g + 0.114 * b
}
fn titlebar_container(window ObjId) ObjId {
	content := msg_id(window, 'contentView')
	root := msg_id(content, 'superview')
	return first_descendant(root, 'NSTitlebarContainerView')
}
fn first_descendant(view ObjId, class_name string) ObjId {
	if is_nil(view) { return nil_obj() }
	if objc_utf8_string(msg_id(view, 'className')) == class_name { return view }
	children := msg_id(view, 'subviews')
	for i in 0 .. int(msg_u64(children, 'count')) { found := first_descendant(msg_id_u64(children, 'objectAtIndex:', u64(i)), class_name); if !is_nil(found) { return found } }
	return nil_obj()
}
fn hide_descendants(view ObjId, class_name string) {
	if is_nil(view) { return }
	if objc_utf8_string(msg_id(view, 'className')) == class_name { msg_void_bool(view, 'setHidden:', true) }
	children := msg_id(view, 'subviews')
	for i in 0 .. int(msg_u64(children, 'count')) { hide_descendants(msg_id_u64(children, 'objectAtIndex:', u64(i)), class_name) }
}
fn constrain(view ObjId, anchor string, other ObjId, other_anchor string, constant f64) {
	lhs := msg_id(view, anchor)
	rhs := msg_id(other, other_anchor)
	constraint := C.witty_macos_msg_id_obj_f64(lhs, sel('constraintEqualToAnchor:constant:'), rhs, constant)
	msg_void_bool(constraint, 'setActive:', true)
}
fn push_native_tabs(context voidptr) {
	window := ObjId(context)
	mut data := native_window_data(window) or { return }
	if data.tabs_tahoe { setup_tahoe_tab_bar(window); return }
	if data.config.titlebar_style != 2 || msg_u64(window, 'styleMask') & ns_window_style_titled == 0 { return }
	controllers := msg_id(window, 'titlebarAccessoryViewControllers')
	mut controller := nil_obj()
	for i in 0 .. int(msg_u64(controllers, 'count')) { value := msg_id_u64(controllers, 'objectAtIndex:', u64(i)); if is_tab_bar_accessory(value) { controller = value; break } }
	if is_nil(controller) { return }
	if is_nil(msg_id(window, 'toolbar')) {
		toolbar := create_terminal_toolbar(mut data)
		msg_void1(window, 'setToolbar:', toolbar)
		msg_void_u64(window, 'setToolbarStyle:', 4)
	}
	accessory := msg_id(controller, 'view')
	clip := msg_id(accessory, 'superview')
	titlebar := msg_id(clip, 'superview')
	if objc_utf8_string(msg_id(titlebar, 'className')) != 'NSTitlebarView' { return }
	toolbar := first_descendant(titlebar, 'NSToolbarView')
	if is_nil(toolbar) { return }
	if msg_id(data.backdrop, 'superview') != titlebar {
		msg_void(data.backdrop, 'removeFromSuperview')
		data.backdrop = msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(0, 0, 0, 0))
		msg_void1(data.backdrop, 'setIdentifier:', nsstring('_windowButtonsBackdrop'))
		msg_void1(titlebar, 'addSubview:', data.backdrop)
		msg_void_bool(data.backdrop, 'setWantsLayer:', true)
		data.backdrop_overlay = msg_id(alloc('VTVibrantLayer'), 'init')
		set_native_canvas_srgb_tile(data.backdrop_overlay,
			native_window_canvas_color(C.witty_canvas_gamma22_gray(0.95)))
		msg_void_u64(data.backdrop_overlay, 'setAutoresizingMask:', 18)
		msg_void1(msg_id(data.backdrop, 'layer'), 'addSublayer:', data.backdrop_overlay)
		msg_void_bool(data.backdrop, 'setTranslatesAutoresizingMaskIntoConstraints:', false)
		constrain(data.backdrop, 'leftAnchor', toolbar, 'leftAnchor', 0)
		constrain(data.backdrop, 'rightAnchor', toolbar, 'leftAnchor', if native_has_window_buttons(window) { 78 } else { 0 })
		constrain(data.backdrop, 'topAnchor', toolbar, 'topAnchor', 0)
		constrain(data.backdrop, 'heightAnchor', toolbar, 'heightAnchor', 0)
	}
	parent := msg_id(titlebar, 'superview')
	if msg_id(data.drag_handle, 'superview') != parent {
		msg_void(data.drag_handle, 'removeFromSuperview')
		data.drag_handle = msg_id_rect(alloc('VTWindowDragView'), 'initWithFrame:', objc_rect(0, 0, 0, 0))
		msg_void1(data.drag_handle, 'setIdentifier:', nsstring('_windowDragHandle'))
		msg_void1(parent, 'addSubview:', data.drag_handle)
		msg_void_bool(data.drag_handle, 'setTranslatesAutoresizingMaskIntoConstraints:', false)
		constrain(data.drag_handle, 'leftAnchor', toolbar, 'leftAnchor', 0)
		constrain(data.drag_handle, 'rightAnchor', toolbar, 'rightAnchor', 0)
		constrain(data.drag_handle, 'topAnchor', toolbar, 'topAnchor', 0)
		constrain(data.drag_handle, 'bottomAnchor', toolbar, 'topAnchor', 12)
	}
	msg_void_bool(data.backdrop, 'setHidden:', false)
	msg_void_bool(data.drag_handle, 'setHidden:', false)
	msg_void_bool(data.title_label, 'setHidden:', true)
	for view in [clip, accessory] {
		msg_void_bool(view, 'setTranslatesAutoresizingMaskIntoConstraints:', false)
		parent_view := if view == clip { toolbar } else { clip }
		constrain(view, 'leftAnchor', if view == clip { data.backdrop } else { clip }, if view == clip { 'rightAnchor' } else { 'leftAnchor' }, 0)
		constrain(view, 'rightAnchor', parent_view, 'rightAnchor', 0)
		constrain(view, 'topAnchor', parent_view, 'topAnchor', 0)
		constrain(view, 'heightAnchor', parent_view, 'heightAnchor', 0)
		msg_void_bool(view, 'setNeedsLayout:', true)
	}
	update_native_titlebar(window)
}
fn update_native_titlebar(window ObjId) {
	mut data := native_window_data(window) or { return }
	if native_uses_tahoe_titlebar(data) {
		update_tahoe_titlebar(data)
		sync_transparent_title_font_fields(mut data)
		return
	}
	container := titlebar_container(window)
	if is_nil(container) { return }
	mut titlebar_color := data.titlebar_color
	if data.config.titlebar_style == 2 {
		hide_descendants(container, 'NSTitlebarSeparatorView')
		hide_descendants(container, 'NSToolbarClippedItemsIndicatorViewer')
		msg_void_u64(window, 'setTitlebarSeparatorStyle:', 1)
		if !data.effect_hidden { msg_void_bool(first_descendant(container, 'NSVisualEffectView'), 'setHidden:', true); data.effect_hidden = true }
		button := first_descendant(container, 'NSTabBarNewTabButton')
		image_view := first_descendant(button, 'NSImageView')
		msg_void_f64(image_view, 'setAlphaValue:', if msg_bool(window, 'isKeyWindow') { 1 } else { 0.5 })
		image := msg_id(image_view, 'image')
		if !is_nil(image) {
			if is_nil(data.new_tab_image_layer) { data.new_tab_image_layer = msg_id(alloc('VTVibrantLayer'), 'init') }
			C.macos_objc_set_ptr_ivar(data.new_tab_image_layer, cstr('vtType'), voidptr(if data.light { 0 } else { 1 }))
			b := msg_rect(button, 'bounds'); size := C.witty_macos_text_size(image)
			msg_void_rect(data.new_tab_image_layer, 'setFrame:', objc_rect(b.x + (b.width - size.width) / 2, b.y + (b.height - size.height) / 2, size.width, size.height))
			msg_void1(data.new_tab_image_layer, 'setContentsGravity:', nsstring('resizeAspect'))
			C.witty_macos_msg_void_f32(data.new_tab_image_layer, sel('setOpacity:'), 0.5)
			msg_void1(data.new_tab_image_layer, 'setContents:', image)
			msg_void(data.new_tab_image_layer, 'removeFromSuperlayer')
			msg_void1(msg_id(button, 'layer'), 'addSublayer:', data.new_tab_image_layer)
		}
		group := msg_id(window, 'tabGroup'); windows := msg_id(group, 'windows')
		highlighted := msg_id_u64(windows, 'objectAtIndex:', 0) == window
		msg_void_rect(data.backdrop_overlay, 'setFrame:', msg_rect(data.backdrop, 'bounds'))
		msg_void_bool(data.backdrop_overlay, 'setHidden:', !data.light || highlighted)
		background := msg_id(window, 'backgroundColor')
		very_dark := native_color_object_luminance(background) < 0.05
		button_color := if data.light {
			nil_obj()
		} else if !highlighted {
			native_color(0, 0.45)
		} else if very_dark {
			background
		} else {
			nil_obj()
		}
		data.buttons_fill.update(data.backdrop, button_color)
		if very_dark && msg_bool(group, 'isTabBarVisible') {
			titlebar_color = msg_id_f64(titlebar_color, 'highlightWithLevel:', 0.14)
		}
	}
	data.titlebar_fill.update(container, titlebar_color)
}
pub fn apply_native_window_config(view voidptr, config NativeWindowConfig, initial bool, preferred_background u32, preferred_opacity f64, force_opaque bool) {
	window := msg_id(view, 'window')
	if is_nil(window) { return }
	mut data := native_window_data(window) or {
		tahoe := config.decorations && C.witty_native_os_at_least(26, 0, 0)
		&NativeWindowData{
			window: window
			tabs_tahoe: tahoe && config.titlebar_style == 2
			transparent_tahoe: tahoe && config.titlebar_style == 1
		}
	}
	g_native_windows[u64(window)] = data
	data.config = config
	data.preferred_background = preferred_background
	data.preferred_opacity = preferred_opacity
	data.force_opaque = force_opaque
	// syncAppearance receives the controller's focused SurfaceView. Keep it
	// when an inspector/palette later becomes the window's first responder.
	if msg_bool1(view, 'isKindOfClass:', get_class('VTTerminalView')) { data.focused_view = ObjId(view) }
	if !data.tabs_tahoe { msg_void1(data.title_label, 'setStringValue:', msg_id(window, 'title')) }
	// Ventura chrome follows the surface config; its appearance override
	// separately follows the preferred dynamic border background.
	data.light = native_color_luminance(config.background) > 0.5
	titlebar_opacity := math.max(0.001, math.min(1.0, preferred_opacity))
	color := msg_id(native_color(preferred_background, titlebar_opacity), 'retain')
	msg_void(data.titlebar_color, 'release')
	data.titlebar_color = color
	if initial {
		if title := config.title { set_view_title_now(view, title) }
		if !config.decorations { msg_void_u64(window, 'setStyleMask:', msg_u64(window, 'styleMask') & ~ns_window_style_titled) }
		x := config.position_x
		y := config.position_y
		if x != none && y != none {
			mut screen := msg_id(window, 'screen')
			if is_nil(screen) { screen = msg_id_u64(msg_id(get_class('NSScreen'), 'screens'), 'objectAtIndex:', 0) }
			if !is_nil(screen) {
				frame := msg_rect(window, 'frame'); visible := msg_rect(screen, 'visibleFrame')
				pos := native_window_position(SplitBounds{width: frame.width, height: frame.height}, SplitBounds{x: visible.x, y: visible.y, width: visible.width, height: visible.height}, x, y)
				C.witty_macos_msg_void_rect_bool(window, sel('setFrame:display:'), objc_rect(pos.x, pos.y, pos.width, pos.height), true)
			}
		} else if msg_u64(shared_app(), 'activationPolicy') == ns_application_activation_policy_prohibited
			|| !restore_last_window_frame(window, true, false) {
			msg_void(window, 'center')
		}
		for button in [u64(0), 1, 2] { msg_void_bool(msg_id_u64(window, 'standardWindowButton:', button), 'setHidden:', config.buttons_hidden) }
	}
	if host:=split_host(msg_id(window,'contentView')) { data.surface_zoomed=host.tree.zoomed != unsafe { nil } }
	if config.titlebar_style==2 && is_nil(msg_id(window,'toolbar')) && msg_u64(window,'styleMask') & ns_window_style_titled!=0 {
		msg_void1(window,'setToolbar:',create_terminal_toolbar(mut data))
		msg_void_u64(window,'setToolbarStyle:',4)
	}
	update_native_zoom_views(mut data)
	uses_tahoe_titlebar := native_uses_tahoe_titlebar(data)
	if uses_tahoe_titlebar {
		data.tahoe_last_config = true
		observe_tahoe_tab_group(mut data)
		schedule_tahoe_tab_background(window)
	}
	if !msg_bool(window, 'isVisible') {
		if uses_tahoe_titlebar {
			msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:', nsstring(if native_color_luminance(preferred_background) > 0.5 { 'NSAppearanceNameAqua' } else { 'NSAppearanceNameDarkAqua' })))
			msg_void_bool(window, 'setTitlebarAppearsTransparent:', native_titlebar_appears_transparent(data))
			if data.tabs_tahoe { msg_void_u64(window, 'setTitleVisibility:', 1) }
			update_tahoe_titlebar(data)
		}
		return
	}
	appearance_name := if uses_tahoe_titlebar || config.titlebar_style == 2 { if native_color_luminance(preferred_background) > 0.5 { 'NSAppearanceNameAqua' } else { 'NSAppearanceNameDarkAqua' } } else if config.theme == 0 { if data.light { 'NSAppearanceNameAqua' } else { 'NSAppearanceNameDarkAqua' } } else if config.theme == 2 { 'NSAppearanceNameAqua' } else if config.theme == 3 { 'NSAppearanceNameDarkAqua' } else { '' }
	msg_void1(window, 'setAppearance:', if appearance_name.len > 0 { msg_id1(get_class('NSAppearance'), 'appearanceNamed:', nsstring(appearance_name)) } else { nil_obj() })
	msg_void_bool(window, 'setHasShadow:', config.shadow)
	transparent := native_window_transparent(config, msg_u64(window, 'styleMask') & u64(1 << 14) != 0, force_opaque)
	msg_void_bool(window, 'setOpaque:', !transparent)
	msg_void1(window, 'setBackgroundColor:', if transparent { native_color(0xffffff, 0.001) } else { native_color(preferred_background, 1) })
	if transparent && config.blur >= 0 { C.witty_macos_set_window_background_blur(window, int(config.blur)) }
	msg_void_bool(window, 'setTitlebarAppearsTransparent:', native_titlebar_appears_transparent(data))
	msg_void_u64(window, 'setTitleVisibility:', u64(if data.tabs_tahoe || config.titlebar_style in [2, 3] { 1 } else { 0 }))
	reapply_hidden_native_window_style(window)
	update_native_titlebar(window)
	if config.titlebar_style == 2 { dispatch_main(push_native_tabs, voidptr(window)) }
	refresh_native_update_presentation()
}

fn save_native_window_frame(self ObjId) {
	if !msg_bool(self, 'isVisible') { return }
	frame := msg_rect(self, 'frame')
	numbers := [frame.x, frame.y, frame.width, frame.height].map(voidptr(msg_id_f64(get_class('NSNumber'), 'numberWithDouble:', it)))
	array := C.witty_macos_array(numbers.data, uint(numbers.len))
	msg_void2(msg_id(get_class('NSUserDefaults'), 'standardUserDefaults'), 'setObject:forKey:', array, nsstring('NSWindowLastPosition'))
}
fn native_window_geometry_changed(_self ObjId, _cmd Sel, notification ObjId) {
	window := msg_id(notification, 'object')
	if is_regular_terminal_window(window) {
		save_native_window_frame(window)
	}
}

fn register_native_window_delegate_methods(cls ObjId) {
	add_method(cls, 'windowDidMove:', voidptr(native_window_geometry_changed), 'v@:@')
	add_method(cls, 'windowDidResize:', voidptr(native_window_geometry_changed), 'v@:@')
	register_terminal_cascade_delegate_methods(cls)
}
fn native_window_close(self ObjId,_cmd Sel) {
	tabs := msg_id(msg_id(self, 'tabbedWindows'), 'copy')
	defer { msg_void(tabs, 'release') }
	save_native_window_frame(self)
	terminal_window_will_close(self)
	msg_void2(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), 'postNotificationName:object:', nsstring('TerminalWindowWillClose'), self)
	C.witty_macos_window_super_void0(self, sel('close'))
	if mut data := native_window_data(self) {
		clear_transparent_title_font_fields(mut data)
		if !is_nil(data.tab_shortcut) {
			C.witty_macos_objc_msg_void3(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'),
				sel('removeObserver:name:object:'), self, nsstring('NSViewFrameDidChangeNotification'), data.tab_shortcut)
		}
		release_tahoe_window(mut data)
		release_native_zoom_views(data)
		msg_void(data.titlebar_color, 'release')
		data.titlebar_fill.clear()
		data.buttons_fill.clear()
	}
	g_native_windows.delete(u64(self))
	for i in 0 .. int(msg_u64(tabs, 'count')) {
		tab := msg_id_u64(tabs, 'objectAtIndex:', u64(i))
		if tab != self { queue_native_tab_shortcuts(tab); break }
	}
}
pub fn restore_last_terminal_window_size(view voidptr, restore_origin bool) {
	restore_last_window_frame(msg_id(view, 'window'), restore_origin, true)
}

fn restore_last_window_frame(window ObjId, restore_origin bool, restore_size bool) bool {
	values := msg_id1(msg_id(get_class('NSUserDefaults'), 'standardUserDefaults'), 'arrayForKey:', nsstring('NSWindowLastPosition'))
	count := msg_u64(values, 'count')
	if count != 2 && count != 4 { return false }
	mut numbers := [4]f64{}
	for i in 0 .. int(count) {
		number := msg_id_u64(values, 'objectAtIndex:', u64(i))
		if !msg_bool1(number, 'isKindOfClass:', get_class('NSNumber')) { return false }
		numbers[i] = msg_f64(number, 'doubleValue')
		if !math.is_finite(numbers[i]) { return false }
	}
	use_size := restore_size && count == 4 && numbers[2] > 0 && numbers[3] > 0
	if !restore_origin && !use_size { return false }

	mut screen := msg_id(window, 'screen')
	if is_nil(screen) { screen = msg_id(get_class('NSScreen'), 'mainScreen') }
	if is_nil(screen) { return false }
	frame := msg_rect(window, 'frame')
	visible := msg_rect(screen, 'visibleFrame')
	restored := restored_window_frame(SplitBounds{x: frame.x, y: frame.y, width: frame.width, height: frame.height},
		SplitBounds{x: visible.x, y: visible.y, width: visible.width, height: visible.height},
		SplitBounds{x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]},
		restore_origin, use_size)
	C.witty_macos_msg_void_rect_bool(window, sel('setFrame:display:'), objc_rect(restored.x, restored.y, restored.width, restored.height), true)
	return true
}

fn C.witty_macos_text_size(obj ObjId) ObjCSize
fn C.witty_macos_text_alignment_center() u64
fn C.witty_macos_priority(obj ObjId, selector Sel, priority f32, axis u64)
__global ( g_toolbar_windows map[u64]ObjId )
fn native_title_label_moved(self ObjId, _cmd Sel) {
	msg_void_bool(self, 'setEditable:', false)
	msg_void_bool(self, 'setBordered:', false)
	msg_void_bool(self, 'setDrawsBackground:', false)
	msg_void_u64(self, 'setAlignment:', C.witty_macos_text_alignment_center())
	msg_void_u64(self, 'setLineBreakMode:', 4)
	msg_void_bool(msg_id(self, 'cell'), 'setTruncatesLastVisibleLine:', true)
	msg_void_bool(self, 'setTranslatesAutoresizingMaskIntoConstraints:', false)
	C.witty_macos_priority(self, sel('setContentHuggingPriority:forOrientation:'), 250, 0)
	C.witty_macos_priority(self, sel('setContentCompressionResistancePriority:forOrientation:'), 750, 0)
}
fn native_title_label_draw(self ObjId, _cmd Sel, _dirty ObjCRect) {
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	text := msg_id(msg_id(self, 'attributedStringValue'), 'mutableCopy')
	if is_nil(text) { return }
	defer { msg_void(text, 'release') }
	size := C.witty_macos_text_size(text)
	bounds := msg_rect(self, 'bounds')
	frame := objc_rect(bounds.x, bounds.y + (bounds.height - size.height) / 2 - 1,
		bounds.width, size.height)
	mut pixel_bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, &bounds, &pixel_bounds, &width, &height)
	mut raster := canvas.new_raster_surface(width: width, height: height) or { return }
	flipped := msg_bool(self, 'isFlipped')
	image := C.witty_canvas_rasterize_attributed_text(text, &frame, &pixel_bounds, raster.pixels.data,
		width, height, flipped)
	if is_nil(image) { return }
	C.witty_canvas_present_oriented_image(context, image, &pixel_bounds, flipped)
	C.CFRelease(image)
}
fn toolbar_array(names []string) ObjId {
	mut objects := []voidptr{}
	for name in names { objects << voidptr(nsstring(name)) }
	return C.witty_macos_array(objects.data, uint(objects.len))
}
fn native_toolbar_allowed(self ObjId, _cmd Sel, _toolbar ObjId) ObjId {
	if window := g_toolbar_windows[u64(self)] { if data := native_window_data(window) { if data.tabs_tahoe { return toolbar_array(['Title', 'NSToolbarFlexibleSpaceItem', 'NSToolbarSpaceItem']) } } }
	return toolbar_array(['TitleText', 'NSToolbarFlexibleSpaceItem', 'NSToolbarSpaceItem', 'ResetZoom'])
}
fn native_toolbar_defaults(self ObjId, _cmd Sel, _toolbar ObjId) ObjId {
	if window := g_toolbar_windows[u64(self)] { if data := native_window_data(window) { if data.tabs_tahoe { return toolbar_array(['NSToolbarFlexibleSpaceItem', 'Title', 'NSToolbarFlexibleSpaceItem']) } } }
	return toolbar_array(['NSToolbarFlexibleSpaceItem', 'TitleText', 'NSToolbarFlexibleSpaceItem'])
}
fn native_toolbar_item(self ObjId, _cmd Sel, _toolbar ObjId, identifier ObjId, _inserted bool) ObjId {
	window := g_toolbar_windows[u64(self)] or { return nil_obj() }
	mut data := native_window_data(window) or { return nil_obj() }
	item := msg_id1(alloc('NSToolbarItem'), 'initWithItemIdentifier:', identifier)
	if data.tabs_tahoe && objc_utf8_string(identifier) == 'Title' {
		create_tahoe_title_view(mut data)
		msg_void1(item, 'setView:', data.tahoe_title_view)
		C.witty_macos_priority(data.tahoe_title_view, sel('setContentCompressionResistancePriority:forOrientation:'), 1000, 0)
		msg_void_u64(item, 'setVisibilityPriority:', 2000)
		msg_void_bool(item, 'setEnabled:', true)
		msg_void_bool(item, 'setBordered:', false)
	}
	if !data.tabs_tahoe && objc_utf8_string(identifier) == 'TitleText' {
		msg_void1(item, 'setView:', data.title_label)
		msg_void_u64(item, 'setVisibilityPriority:', 2000)
		height := msg_id_f64(msg_id(data.title_label, 'heightAnchor'), 'constraintEqualToConstant:', 22)
		msg_void_bool(height, 'setActive:', true)
		msg_void_bool(item, 'setEnabled:', true)
	}
	if !data.tabs_tahoe && objc_utf8_string(identifier)=='ResetZoom' {
		prepare_native_zoom_views(mut data)
		msg_void1(item,'setView:',data.zoom_toolbar_button)
		msg_void1(data.zoom_toolbar_button,'removeConstraints:',msg_id(data.zoom_toolbar_button,'constraints'))
		msg_void_bool(msg_id_f64(msg_id(data.zoom_toolbar_button,'widthAnchor'),'constraintEqualToConstant:',22),'setActive:',true)
		msg_void_bool(msg_id_f64(msg_id(data.zoom_toolbar_button,'heightAnchor'),'constraintEqualToConstant:',20),'setActive:',true)
	}
	return item
}
fn create_terminal_toolbar(mut data NativeWindowData) ObjId {
	if data.tabs_tahoe { return create_tahoe_terminal_toolbar(mut data) }
	mut toolbar_cls := get_class('VTTerminalToolbar')
	if is_nil(toolbar_cls) {
		toolbar_cls = C.macos_objc_allocate_class_pair(get_class('NSToolbar'), cstr('VTTerminalToolbar'), 0)
		C.macos_class_add_protocol(toolbar_cls, get_protocol('NSToolbarDelegate'))
		add_method(toolbar_cls, 'toolbarAllowedItemIdentifiers:', voidptr(native_toolbar_allowed), '@@:@')
		add_method(toolbar_cls, 'toolbarDefaultItemIdentifiers:', voidptr(native_toolbar_defaults), '@@:@')
		add_method(toolbar_cls, 'toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:', voidptr(native_toolbar_item), '@@:@@B')
		C.macos_objc_register_class_pair(toolbar_cls)
		label_cls := C.macos_objc_allocate_class_pair(get_class('NSTextField'), cstr('VTCenteredDynamicLabel'), 0)
		add_method(label_cls, 'viewDidMoveToSuperview', voidptr(native_title_label_moved), 'v@:')
		add_method(label_cls, 'drawRect:', voidptr(native_title_label_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		C.macos_objc_register_class_pair(label_cls)
	}
	data.title_label = msg_id_rect(alloc('VTCenteredDynamicLabel'), 'initWithFrame:', objc_rect(0, 0, 100, 22))
	font := window_title_font(data.window)
	msg_void1(data.title_label, 'setFont:', if is_nil(font) { msg_id_f64(get_class('NSFont'), 'titleBarFontOfSize:', msg_f64(get_class('NSFont'), 'systemFontSize')) } else { font })
	msg_void1(data.title_label, 'setStringValue:', msg_id(data.window, 'title'))
	toolbar := msg_id1(msg_id(toolbar_cls, 'alloc'), 'initWithIdentifier:', nsstring('Toolbar'))
	g_toolbar_windows[u64(toolbar)] = data.window
	msg_void1(toolbar, 'setDelegate:', toolbar)
	msg_void1(toolbar, 'setCenteredItemIdentifiers:', msg_id1(get_class('NSSet'), 'setWithObject:', nsstring('TitleText')))
	return toolbar
}

fn native_has_window_buttons(window ObjId) bool {
	for kind in [u64(0), 1, 2] {
		button := msg_id_u64(window, 'standardWindowButton:', kind)
		if !is_nil(button) && !msg_bool(button, 'isHiddenOrHasHiddenAncestor') { return true }
	}
	return false
}
fn reapply_hidden_native_window_style(window ObjId) {
	data := native_window_data(window) or { return }
	if data.config.titlebar_style != 3 { return }
	if state := g_fullscreen_states[u64(window)] { if state.is_active() { return } }
	mask := ns_window_style_titled | ns_window_style_resizable | ns_window_style_closable | ns_window_style_miniaturizable | u64(1 << 15) | (msg_u64(window, 'styleMask') & u64(1 << 14))
	msg_void_u64(window, 'setStyleMask:', mask)
	msg_void_u64(window, 'setTitleVisibility:', 1)
	msg_void_bool(window, 'setTitlebarAppearsTransparent:', true)
	for kind in [u64(0), 1, 2] { msg_void_bool(msg_id_u64(window, 'standardWindowButton:', kind), 'setHidden:', true) }
	msg_void_u64(window, 'setTabbingMode:', 2)
	msg_void_bool(titlebar_container(window), 'setHidden:', true)
}
