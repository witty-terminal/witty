@[has_globals]
module macos

import gg.canvas

// TitlebarTabsTahoeTerminalWindow and the inherited macOS 26 transparent
// appearance path.
#insert "@VMODROOT/macos/window_tahoe_abi.h"
fn C.witty_tahoe_observe_frame(view voidptr, context voidptr, callback fn (voidptr)) ObjId
fn C.witty_tahoe_observe_group(group voidptr, observer voidptr)
fn C.witty_tahoe_remove_group_observer(group voidptr, observer voidptr)
fn C.witty_tahoe_event_in_view(view voidptr, event voidptr) bool
fn C.witty_tahoe_title_size(view ObjId, title ObjId, font ObjId) ObjCSize
fn C.witty_tahoe_update_title_vibrancy(view ObjId)
fn C.witty_tahoe_draw_title(view ObjId, context voidptr, title ObjId, font ObjId, main bool, vibrant bool,
	pixel_bounds &ObjCRect, pixels voidptr, width int, height int)

enum TahoeWindowTaskKind {
	title
	font
	tab_bar
	setup
	appearance
	tab_background
}

@[heap]
struct TahoeWindowTask {
mut:
	weak &NativeWeakObject
	retained ObjId
	kind TahoeWindowTaskKind
	has_tab_bar bool
}
__global g_tahoe_window_tasks = []&TahoeWindowTask{}

fn queue_tahoe_window(window ObjId, kind TahoeWindowTaskKind, strong bool, has_tab_bar bool, delay f64) {
	task := &TahoeWindowTask{weak: new_native_weak_object(voidptr(window)),
		retained: if strong { msg_id(window, 'retain') } else { nil_obj() },
		kind: kind, has_tab_bar: has_tab_bar}
	g_tahoe_window_tasks << task
	if delay > 0 { dispatch_after(delay, tahoe_window_task_main, voidptr(task)) }
	else { dispatch_main(tahoe_window_task_main, voidptr(task)) }
}

fn tahoe_window_task_main(context voidptr) {
	mut task := unsafe { &TahoeWindowTask(context) }
	defer { release_tahoe_task(mut task) }
	window := ObjId(task.weak.object())
	mut data := native_window_data(window) or { return }
	if !native_uses_tahoe_titlebar(data) { return }
	match task.kind {
		.title { data.tahoe_title = objc_utf8_string(msg_id(window, 'title')); refresh_tahoe_title_view(data) }
		.font {
			font := msg_id(window_title_font(window), 'retain')
			msg_void(data.tahoe_title_font, 'release')
			data.tahoe_title_font = font
			refresh_tahoe_title_view(data)
		}
		.tab_bar { set_tahoe_has_tab_bar(mut data, task.has_tab_bar) }
		.setup { setup_tahoe_tab_bar(window) }
		.appearance { reapply_tahoe_appearance(window) }
		.tab_background {
			container := window_font_titlebar_container(window)
			glass := tahoe_tab_glass_view(container)
			child := msg_id(msg_id(glass, 'subviews'), 'firstObject')
			msg_void_f64(child, 'setAlphaValue:', 0.5)
		}
	}
}

fn tahoe_tab_glass_view(view ObjId) ObjId {
	if is_nil(view) { return nil_obj() }
	name := objc_utf8_string(msg_id(view, 'className'))
	// AppKit can expose the Swift-private runtime name for this view.
	if name == 'NSSubduedGlassEffectView'
		|| (name.starts_with('_Tt') && name.ends_with('NSSubduedGlassEffectView')) {
		return view
	}
	children := msg_id(view, 'subviews')
	for i in 0 .. int(msg_u64(children, 'count')) {
		found := tahoe_tab_glass_view(msg_id_u64(children, 'objectAtIndex:', u64(i)))
		if !is_nil(found) { return found }
	}
	return nil_obj()
}

fn schedule_tahoe_tab_background(window ObjId) {
	if C.witty_native_os_at_least(27, 0, 0) {
		// AppKit can restore the native glass opacity while arranging tabs.
		queue_tahoe_window(window, .tab_background, false, false, 0.05)
	}
}

fn release_tahoe_task(mut task TahoeWindowTask) {
	task.weak.deinit()
	msg_void(task.retained, 'release')
	for i, pending in g_tahoe_window_tasks { if pending == &task { g_tahoe_window_tasks.delete(i); break } }
}

fn tahoe_titlebar_view(window ObjId) ObjId {
	root := window_font_view_root(msg_id(window, 'contentView'))
	if !msg_bool1(root, 'respondsToSelector:', ObjId(sel('titlebarView'))) { return nil_obj() }
	return msg_id1(root, 'valueForKey:', nsstring('titlebarView'))
}

fn tahoe_tab_bar_view(window ObjId) ObjId {
	return first_descendant(tahoe_titlebar_view(window), 'NSTabBar')
}

fn first_superview(view ObjId, class_name string) ObjId {
	mut parent := msg_id(view, 'superview')
	for !is_nil(parent) {
		if objc_utf8_string(msg_id(parent, 'className')) == class_name { return parent }
		parent = msg_id(parent, 'superview')
	}
	return nil_obj()
}

fn tahoe_tab_accessory_container(tab_bar ObjId) ObjId {
	clip := first_superview(tab_bar, 'NSTitlebarAccessoryClipView')
	return if is_nil(clip) {
		first_superview(tab_bar, 'NSTitlebarAccessoryContainerView')
	} else {
		clip
	}
}

fn clear_tahoe_frame_observer(mut data NativeWindowData) {
	if is_nil(data.tahoe_frame_observer) { return }
	msg_void1(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), 'removeObserver:', data.tahoe_frame_observer)
	msg_void(data.tahoe_frame_observer, 'release')
	data.tahoe_frame_observer = nil_obj()
}

fn tahoe_tab_bar_frame_changed(context voidptr) {
	window := ObjId(context)
	mut data := native_window_data(window) or { return }
	clear_tahoe_frame_observer(mut data)
	queue_tahoe_window(window, .setup, true, false, 0)
}

fn setup_tahoe_tab_bar(window ObjId) {
	mut data := native_window_data(window) or { return }
	if !data.tabs_tahoe || !is_nil(data.tahoe_frame_observer) { return }
	titlebar := tahoe_titlebar_view(window)
	tab_bar := tahoe_tab_bar_view(window)
	if is_nil(titlebar) || is_nil(tab_bar) { return }
	queue_tahoe_window(window, .tab_bar, false, true, 0)
	clip := tahoe_tab_accessory_container(tab_bar)
	if is_nil(clip) { return }
	children := msg_id(clip, 'subviews')
	if msg_u64(children, 'count') == 0 { return }
	accessory := msg_id_u64(children, 'objectAtIndex:', 0)
	toolbar := first_descendant(titlebar, 'NSToolbarView')
	if is_nil(toolbar) { return }
	new_button := first_descendant(titlebar, 'NSTabBarNewTabButton')
	if is_nil(new_button) { return }
	frame := msg_rect(tab_bar, 'frame')
	msg_void_rect(tab_bar, 'setFrame:', objc_rect(frame.x, frame.y, frame.width, msg_rect(new_button, 'frame').width))
	for view in [clip, accessory] { msg_void_bool(view, 'setTranslatesAutoresizingMaskIntoConstraints:', false) }
	constrain(clip, 'leftAnchor', toolbar, 'leftAnchor', if data.config.buttons_hidden { 0 } else { 70 })
	constrain(clip, 'rightAnchor', toolbar, 'rightAnchor', 0)
	constrain(clip, 'topAnchor', toolbar, 'topAnchor', 2)
	constrain(clip, 'heightAnchor', toolbar, 'heightAnchor', 0)
	for anchor in ['leftAnchor', 'rightAnchor', 'topAnchor', 'heightAnchor'] { constrain(accessory, anchor, clip, anchor, 0) }
	for view in [clip, accessory] { msg_void_bool(view, 'setNeedsLayout:', true) }
	schedule_tahoe_tab_background(window)
	msg_void_bool(tab_bar, 'setPostsFrameChangedNotifications:', true)
	data.tahoe_frame_observer = C.witty_tahoe_observe_frame(voidptr(tab_bar), voidptr(window), tahoe_tab_bar_frame_changed)
}

fn set_tahoe_has_tab_bar(mut data NativeWindowData, visible bool) {
	data.tahoe_has_tab_bar = visible
	refresh_tahoe_title_view(data)
}

fn tahoe_title_intrinsic_size(self ObjId, _cmd Sel) ObjCSize {
	window := ObjId(C.macos_objc_get_ptr_ivar(self, cstr('vtWindow')))
	data := native_window_data(window) or { return ObjCSize{width: 1, height: 1} }
	if data.tahoe_has_tab_bar { return ObjCSize{width: 1, height: 1} }
	return C.witty_tahoe_title_size(self, tahoe_title_text(data), data.tahoe_title_font)
}

fn tahoe_title_text(data &NativeWindowData) ObjId {
	return nsstring(if data.tahoe_title == '' { ' ' } else { data.tahoe_title })
}

fn tahoe_draw_title(self ObjId, _cmd Sel, _dirty ObjCRect) {
	tahoe_draw_title_ink(self, self)
}

fn tahoe_draw_vibrant_title(self ObjId, _cmd Sel, _dirty ObjCRect) {
	tahoe_draw_title_ink(self, msg_id(self, 'superview'))
}

fn tahoe_draw_title_ink(view ObjId, item ObjId) {
	window := ObjId(C.macos_objc_get_ptr_ivar(item, cstr('vtWindow')))
	data := native_window_data(window) or { return }
	if data.tahoe_has_tab_bar || data.tahoe_title == '' { return }
	vibrant := view != item
	if vibrant && data.tahoe_main { return }
	context := native_canvas_overlay_context()
	if is_nil(context) { return }
	bounds := msg_rect(view, 'bounds')
	mut pixel_bounds := ObjCRect{}
	mut width, mut height := 0, 0
	C.witty_canvas_pixel_bounds(context, &bounds, &pixel_bounds, &width, &height)
	mut raster := canvas.new_raster_surface(width: width, height: height) or { return }
	C.witty_tahoe_draw_title(view, context, tahoe_title_text(data), data.tahoe_title_font,
		data.tahoe_main, vibrant, &pixel_bounds, raster.pixels.data, width, height)
}

fn tahoe_refresh_vibrant_title(ink ObjId) {
	C.witty_tahoe_update_title_vibrancy(ink)
	msg_void_bool(ink, 'setNeedsDisplay:', true)
}

fn tahoe_title_environment_changed(self ObjId, command Sel) {
	name := unsafe { cstring_to_vstring(C.sel_getName(command)) }
	view_super_void(self, 'VTTahoeTitleItem', name)
	if name == 'viewDidChangeBackingProperties' {
		msg_void(self, 'invalidateIntrinsicContentSize')
	}
	msg_void_bool(self, 'setNeedsDisplay:', true)
	tahoe_refresh_vibrant_title(ObjId(C.macos_objc_get_ptr_ivar(self, cstr('vtTitleInk'))))
}

fn refresh_tahoe_title_view(data &NativeWindowData) {
	title := tahoe_title_text(data)
	for view in data.tahoe_title_views {
		msg_void1(view, 'setAccessibilityValue:', title)
		msg_void_bool(view, 'setAccessibilityElement:', !data.tahoe_has_tab_bar)
		msg_void(view, 'invalidateIntrinsicContentSize')
		msg_void_bool(view, 'setNeedsLayout:', true)
		msg_void_bool(view, 'setNeedsDisplay:', true)
		ink := ObjId(C.macos_objc_get_ptr_ivar(view, cstr('vtTitleInk')))
		msg_void_bool(ink, 'setHidden:', data.tahoe_main || data.tahoe_has_tab_bar)
		tahoe_refresh_vibrant_title(ink)
	}
}

fn create_tahoe_title_view(mut data NativeWindowData) {
	mut title_cls := get_class('VTTahoeTitleItem')
	if is_nil(title_cls) {
		title_cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('VTTahoeTitleItem'), 0)
		C.macos_class_add_ivar(title_cls, cstr('vtWindow'), sizeof(voidptr), 3, cstr('^v'))
		C.macos_class_add_ivar(title_cls, cstr('vtTitleInk'), sizeof(voidptr), 3, cstr('^v'))
		add_method(title_cls, 'intrinsicContentSize', voidptr(tahoe_title_intrinsic_size), '{CGSize=dd}@:')
		add_method(title_cls, 'drawRect:', voidptr(tahoe_draw_title), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(title_cls, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		for name in ['viewDidChangeBackingProperties', 'viewDidChangeEffectiveAppearance'] {
			add_method(title_cls, name, voidptr(tahoe_title_environment_changed), 'v@:')
		}
		C.macos_objc_register_class_pair(title_cls)
		ink_class := C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('VTTahoeTitleInk'), 0)
		add_method(ink_class, 'drawRect:', voidptr(tahoe_draw_vibrant_title), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		C.macos_objc_register_class_pair(ink_class)
	}
	data.tahoe_title_view = msg_id_rect(alloc('VTTahoeTitleItem'), 'initWithFrame:', objc_rect(0, 0, 100, 22))
	C.macos_objc_set_ptr_ivar(data.tahoe_title_view, cstr('vtWindow'), voidptr(data.window))
	ink := msg_id_rect(alloc('VTTahoeTitleInk'), 'initWithFrame:', msg_rect(data.tahoe_title_view, 'bounds'))
	msg_void_bool(ink, 'setWantsLayer:', true)
	msg_void_u64(ink, 'setAutoresizingMask:', 18)
	msg_void1(data.tahoe_title_view, 'addSubview:', ink)
	C.macos_objc_set_ptr_ivar(data.tahoe_title_view, cstr('vtTitleInk'), voidptr(ink))
	msg_void(ink, 'release')
	msg_void1(data.tahoe_title_view, 'setAccessibilityRole:', nsstring('AXStaticText'))
	data.tahoe_title_views << data.tahoe_title_view
	refresh_tahoe_title_view(data)
}

fn create_tahoe_terminal_toolbar(mut data NativeWindowData) ObjId {
	mut toolbar_cls := get_class('VTTahoeTerminalToolbar')
	if is_nil(toolbar_cls) {
		toolbar_cls = C.macos_objc_allocate_class_pair(get_class('NSToolbar'), cstr('VTTahoeTerminalToolbar'), 0)
		C.macos_class_add_protocol(toolbar_cls, get_protocol('NSToolbarDelegate'))
		add_method(toolbar_cls, 'toolbarAllowedItemIdentifiers:', voidptr(native_toolbar_allowed), '@@:@')
		add_method(toolbar_cls, 'toolbarDefaultItemIdentifiers:', voidptr(native_toolbar_defaults), '@@:@')
		add_method(toolbar_cls, 'toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:', voidptr(native_toolbar_item), '@@:@@B')
		C.macos_objc_register_class_pair(toolbar_cls)
	}
	queue_tahoe_window(data.window, .title, false, false, 0)
	queue_tahoe_window(data.window, .font, false, false, 0)
	toolbar := msg_id1(msg_id(toolbar_cls, 'alloc'), 'initWithIdentifier:', nsstring('TerminalToolbar'))
	g_toolbar_windows[u64(toolbar)] = data.window
	msg_void1(toolbar, 'setDelegate:', toolbar)
	msg_void1(toolbar, 'setCenteredItemIdentifiers:', msg_id1(get_class('NSSet'), 'setWithObject:', nsstring('Title')))
	return toolbar
}

fn native_uses_tahoe_titlebar(data &NativeWindowData) bool {
	return data.tabs_tahoe || data.transparent_tahoe
}

fn native_titlebar_appears_transparent(data &NativeWindowData) bool {
	// Tahoe's native title uses AppKit vibrancy over the custom background.
	return data.config.titlebar_style == 1 && !native_uses_tahoe_titlebar(data)
}

fn update_tahoe_titlebar(data &NativeWindowData) {
	// TransparentTitlebarTerminalWindow.syncAppearanceTahoe uses the inherited
	// titlebar container, including the separate native fullscreen window.
	container := window_font_titlebar_container(data.window)
	titlebar := first_descendant(container, 'NSTitlebarView')
	if !is_nil(titlebar) {
		msg_void_bool(titlebar, 'setWantsLayer:', true)
		glass := data.config.blur < 0 && data.config.titlebar_style in [1, 2]
		color := native_window_canvas_color(if glass { nil_obj() } else { data.titlebar_color })
		C.witty_canvas_set_layer_srgb_fill(msg_id(titlebar, 'layer'), color.r, color.g, color.b, color.a)
	}
	msg_void_bool(first_descendant(container, 'NSTitlebarBackgroundView'), 'setHidden:', true)
}

fn clear_tahoe_tab_group(mut data NativeWindowData) {
	if is_nil(data.tahoe_group) { return }
	C.witty_tahoe_remove_group_observer(voidptr(data.tahoe_group), voidptr(data.tahoe_group_observer))
	msg_void(data.tahoe_group, 'release')
	data.tahoe_group = nil_obj()
}

fn tahoe_tab_group_changed(self ObjId, _cmd Sel, _key ObjId, _object ObjId, _change ObjId, _context voidptr) {
	window := ObjId(C.macos_objc_get_ptr_ivar(self, cstr('vtWindow')))
	reapply_tahoe_appearance(window)
}

fn observe_tahoe_tab_group(mut data NativeWindowData) {
	group := msg_id(data.window, 'tabGroup')
	if group == data.tahoe_group { return }
	clear_tahoe_tab_group(mut data)
	if is_nil(group) { return }
	if is_nil(data.tahoe_group_observer) {
		mut cls := get_class('VTTahoeTabGroupObserver')
		if is_nil(cls) {
			cls = C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('VTTahoeTabGroupObserver'), 0)
			C.macos_class_add_ivar(cls, cstr('vtWindow'), sizeof(voidptr), 3, cstr('^v'))
			add_method(cls, 'observeValueForKeyPath:ofObject:change:context:', voidptr(tahoe_tab_group_changed), 'v@:@@@^v')
			C.macos_objc_register_class_pair(cls)
		}
		data.tahoe_group_observer = msg_id(msg_id(cls, 'alloc'), 'init')
		C.macos_objc_set_ptr_ivar(data.tahoe_group_observer, cstr('vtWindow'), voidptr(data.window))
	}
	data.tahoe_group = msg_id(group, 'retain')
	C.witty_tahoe_observe_group(voidptr(group), voidptr(data.tahoe_group_observer))
}

fn reapply_tahoe_appearance(window ObjId) {
	data := native_window_data(window) or { return }
	if !native_uses_tahoe_titlebar(data) || !data.tahoe_last_config { return }
	apply_native_window_config(voidptr(msg_id(window, 'contentView')), data.config, false,
		data.preferred_background, data.preferred_opacity, data.force_opaque)
}

fn native_window_main_changed(self ObjId, command Sel) {
	C.witty_macos_window_super_void0(self, command)
	mut data := native_window_data(self) or { return }
	update_native_zoom_views(mut data)
	if !native_uses_tahoe_titlebar(data) { return }
	data.tahoe_main = unsafe { cstring_to_vstring(C.sel_getName(command)) } == 'becomeMainWindow'
	if data.tahoe_main {
		if data.tabs_tahoe { setup_tahoe_tab_bar(self) }
		reapply_tahoe_appearance(self)
		if msg_u64(msg_id(msg_id(self, 'tabGroup'), 'windows'), 'count') == 2 { queue_tahoe_window(self, .appearance, false, false, 0.05) }
	}
	if data.tabs_tahoe { refresh_tahoe_title_view(data) }
}

fn native_tahoe_send_event(self ObjId, command Sel, event ObjId) {
	if data := native_window_data(self) {
		if data.tabs_tahoe && data.tahoe_has_tab_bar {
			kind := msg_u64(event, 'type')
			right := kind == 3 || (kind == 25 && msg_u64(event, 'buttonNumber') == 2)
				|| (kind == 1 && msg_u64(event, 'modifierFlags') & u64(1 << 18) != 0)
			if right {
				tab_bar := tahoe_tab_bar_view(self)
				if !is_nil(tab_bar) && C.witty_tahoe_event_in_view(voidptr(tab_bar), voidptr(event)) {
					msg_void1(tab_bar, 'rightMouseDown:', event)
					return
				}
			}
		}
	}
	C.witty_macos_window_super_void1(self, command, event)
}

fn register_tahoe_window_methods(cls ObjId) {
	for name in ['becomeMainWindow', 'resignMainWindow'] { add_method(cls, name, voidptr(native_window_main_changed), 'v@:') }
	add_method(cls, 'sendEvent:', voidptr(native_tahoe_send_event), 'v@:@')
	// TerminalController.newWindowForTab both enables AppKit's native "+"
	// button and forwards its action through the focused surface's core route.
	add_method(cls, 'newWindowForTab:', voidptr(native_window_new_tab), 'v@:@')
}

fn native_window_new_tab(self ObjId, _cmd Sel, _sender ObjId) {
	data := native_window_data(self) or { return }
	surface := g_action_surfaces[u64(data.focused_view)] or { return }
	if !surface.perform('new_tab') { eprintln('action failed action=new_tab') }
}

fn release_tahoe_window(mut data NativeWindowData) {
	if !data.tabs_tahoe && is_nil(data.tahoe_group_observer) { return }
	clear_tahoe_frame_observer(mut data)
	clear_tahoe_tab_group(mut data)
	msg_void(data.tahoe_group_observer, 'release')
	msg_void(data.tahoe_title_font, 'release')
	for view in data.tahoe_title_views { msg_void(view, 'release') }
	for key, window in g_toolbar_windows { if window == data.window { g_toolbar_windows.delete(key) } }
}
