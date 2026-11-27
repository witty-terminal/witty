@[has_globals]
module witty_macos

pub type QuickTerminalCreateCallback = fn (view voidptr) bool
pub type QuickTerminalClosedCallback = fn (view voidptr) bool
@[heap]
pub struct NativeQuickTerminal {
pub mut:
	view voidptr
	config NativeQuickConfig
	visible bool
	previous_app voidptr
	previous_space uint
	cache QuickScreenCache
	pending_fullscreen bool
mut:
	window ObjId
	observer ObjId
	hidden_dock bool
	dock_hidden_at_resign bool
	previous_dock_autohide bool
	dock_state_saved bool
	handling_resize bool
	animation_in bool
	animation_frame ObjCRect
	focus_retries u8
	force_opaque bool
}
__global (
	g_quick_terminal &NativeQuickTerminal
	g_quick_create QuickTerminalCreateCallback
	g_quick_can_close QuickTerminalClosedCallback
)
fn C.CoreDockGetOrientationAndPinning(orientation &i32, pinning &i32)
fn C.CoreDockGetAutoHideEnabled() bool
fn C.CoreDockSetAutoHideEnabled(enabled bool)
fn C.CGDisplayCreateUUIDFromDisplayID(display u32) voidptr
fn C.CFUUIDCreateString(allocator voidptr, uuid voidptr) voidptr
fn C.CFRelease(value voidptr)
fn screen_uuid(screen ObjId) string {
	id := screen_display_id(screen)
	if id == 0 { return '' }
	uuid := C.CGDisplayCreateUUIDFromDisplayID(id)
	if is_nil(uuid) { return '' }
	str := ObjId(C.CFUUIDCreateString(nil_obj(), uuid))
	result := objc_utf8_string(str)
	C.CFRelease(str); C.CFRelease(uuid)
	return result
}
fn native_now() f64 { return msg_f64(msg_id(get_class('NSDate'), 'date'), 'timeIntervalSince1970') }
fn quick_screen(c NativeQuickConfig) ObjId {
	if c.screen == 0 { return msg_id(get_class('NSScreen'), 'mainScreen') }
	screens := msg_id(get_class('NSScreen'), 'screens')
	if c.screen == 2 { return if msg_u64(screens, 'count') > 0 { msg_id_u64(screens, 'objectAtIndex:', 0) } else { nil_obj() } }
	mouse := msg_point(get_class('NSEvent'), 'mouseLocation')
	for i in 0 .. int(msg_u64(screens, 'count')) { screen := msg_id_u64(screens, 'objectAtIndex:', u64(i)); b := msg_rect(screen, 'frame'); if mouse.x >= b.x && mouse.x <= b.x + b.width && mouse.y >= b.y && mouse.y <= b.y + b.height { return screen } }
	return nil_obj()
}
fn quick_from_observer(observer ObjId) ?&NativeQuickTerminal {
	ptr := C.macos_objc_get_ptr_ivar(observer, cstr('vtQuickTerminal'))
	if is_nil(ptr) { return none }
	return unsafe { &NativeQuickTerminal(ptr) }
}
fn quick_did_resign_key(observer ObjId, _cmd Sel, notification ObjId) {
	mut q := quick_from_observer(observer) or { return }
	if msg_id(notification, 'object') != q.window { return }
	update_terminal_focus_for_window_key_change(q.window)
	if !q.visible || !is_nil(msg_id(q.window, 'attachedSheet')) { return }
	if app_is_active() { msg_void(q.previous_app,'release'); q.previous_app = unsafe { nil } }
	q.dock_hidden_at_resign = q.hidden_dock
	q.restore_dock()
	if !q.config.autohide { return }
	active := C.CGSGetActiveSpace(C.CGSMainConnectionID())
	if q.config.remain_on_space || active == q.previous_space { q.hide(); return }
	if state := g_fullscreen_states[u64(q.window)] { if state.is_active() { mut fs := state; fs.exit(); q.pending_fullscreen = true } }
	dispatch_main(quick_move_to_space, voidptr(q))
	q.previous_space = active
}
fn quick_move_to_space(context voidptr) {
	mut q := unsafe { &NativeQuickTerminal(context) }
	if q.pending_fullscreen { q.pending_fullscreen = false; q.toggle_fullscreen() }
	msg_void1(q.window, 'makeKeyAndOrderFront:', nil_obj())
}
fn quick_did_become_key(observer ObjId, _cmd Sel, notification ObjId) {
	mut q := quick_from_observer(observer) or { return }
	if msg_id(notification, 'object') != q.window { return }
	update_terminal_focus_for_window_key_change(q.window)
	if q.visible && q.dock_hidden_at_resign { q.hide_dock() }
}
fn quick_did_resize(observer ObjId, _cmd Sel, notification ObjId) {
	mut q := quick_from_observer(observer) or { return }
	if msg_id(notification, 'object') != q.window || !q.visible || q.handling_resize { return }
	mut screen := msg_id(q.window, 'screen'); if is_nil(screen) { screen = msg_id(get_class('NSScreen'), 'mainScreen') }
	if is_nil(screen) { return }
	q.handling_resize = true
	frame := msg_rect(q.window, 'frame'); visible := msg_rect(screen, 'visibleFrame')
	mut positioned := quick_terminal_frame(q.config.position, SplitBounds{x: frame.x, y: frame.y, width: frame.width, height: frame.height}, SplitBounds{x: visible.x, y: visible.y, width: visible.width, height: visible.height}, false)
	if q.config.position in [.top, .bottom] { positioned.y = frame.y }
	if q.config.position in [.left, .right] { positioned.x = frame.x }
	C.witty_macos_msg_void_rect_bool(q.window, sel('setFrame:display:'), objc_rect(positioned.x, positioned.y, positioned.width, positioned.height), true)
	q.handling_resize = false
}
fn quick_screens_changed(observer ObjId, _cmd Sel, _notification ObjId) {
	mut q := quick_from_observer(observer) or { return }
	screens := msg_id(get_class('NSScreen'), 'screens'); now := native_now()
	mut present := []string{}
	for i in 0 .. int(msg_u64(screens, 'count')) {
		screen := msg_id_u64(screens, 'objectAtIndex:', u64(i)); key := screen_uuid(screen)
		if key.len == 0 { continue }; present << key
		if mut entry := q.cache.entries[key] {
			frame := msg_rect(screen, 'frame'); scale := msg_f64(screen, 'backingScaleFactor')
			if !entry.valid(frame.width, frame.height, scale) { q.cache.entries.delete(key) }
			else { q.cache.entries[key] = QuickScreenEntry{...entry, screen_width: frame.width, screen_height: frame.height, last_seen: now} }
		}
	}
	q.cache.prune_stale(present, now)
}
fn quick_will_terminate(observer ObjId, _cmd Sel, _notification ObjId) { if mut q := quick_from_observer(observer) { q.restore_dock() } }
fn (mut q NativeQuickTerminal) hide_dock() {
	if q.hidden_dock { return }
	if !q.dock_state_saved { q.previous_dock_autohide = C.CoreDockGetAutoHideEnabled(); q.dock_state_saved = true }
	presentation_acquire(1); C.CoreDockSetAutoHideEnabled(true); q.hidden_dock = true
}
fn (mut q NativeQuickTerminal) restore_dock() {
	if !q.hidden_dock { return }; presentation_release(1); C.CoreDockSetAutoHideEnabled(q.previous_dock_autohide); q.hidden_dock = false
}
fn quick_conflicts_dock(position NativeQuickPosition, screen ObjId) bool {
	if !screen_has_dock(screen) { return false }
	mut orientation := i32(0); mut pinning := i32(0)
	C.CoreDockGetOrientationAndPinning(&orientation, &pinning)
	return match orientation { 1 { position in [.top, .left, .right] } 2 { position in [.bottom, .left, .right] } 3, 4 { position in [.top, .bottom] } else { false } }
}
fn (mut q NativeQuickTerminal) cached_frame(screen ObjId) ?SplitBounds {
	key := screen_uuid(screen)
	mut entry := q.cache.entries[key] or { return none }
	frame := msg_rect(screen, 'frame')
	if !entry.valid(frame.width, frame.height, msg_f64(screen, 'backingScaleFactor')) { q.cache.entries.delete(key); return none }
	entry.last_seen = native_now(); q.cache.entries[key] = entry
	return entry.frame
}
pub fn (mut q NativeQuickTerminal) save_screen_state(should_exit_fullscreen bool) {
	if should_exit_fullscreen { exit_fullscreen(q.view) }
	frame := msg_rect(q.window, 'frame'); screen := msg_id(q.window, 'screen')
	if frame.width <= 0 || frame.height <= 0 || is_nil(screen) { return }
	key := screen_uuid(screen); if key.len == 0 { return }
	s := msg_rect(screen, 'frame')
	q.cache.entries[key] = QuickScreenEntry{frame: SplitBounds{x: frame.x, y: frame.y, width: frame.width, height: frame.height}, screen_width: s.width, screen_height: s.height, scale: msg_f64(screen, 'backingScaleFactor'), last_seen: native_now()}
	q.cache.prune_capacity()
}
@[heap]
struct QuickAnimationTask {
	quick &NativeQuickTerminal
	entering bool
	frame ObjCRect
}
__global ( g_quick_animation_tasks []&QuickAnimationTask )
fn quick_animate_change(context voidptr, animation_context voidptr) {
	task := unsafe { &QuickAnimationTask(context) }
	q := task.quick
	msg_void_f64(ObjId(animation_context), 'setDuration:', q.config.duration)
	msg_void1(ObjId(animation_context), 'setTimingFunction:', msg_id1(get_class('CAMediaTimingFunction'), 'functionWithName:', nsstring('easeIn')))
	animator := msg_id(q.window, 'animator')
	msg_void_f64(animator, 'setAlphaValue:', if task.entering { 1 } else { 0 })
	C.witty_macos_msg_void_rect_bool(animator, sel('setFrame:display:'), task.frame, task.entering)
}
fn quick_focus_retry(context voidptr) {
	mut q := unsafe { &NativeQuickTerminal(context) }
	if !q.visible { return }
	view := ObjId(q.view)
	if msg_id(view, 'window') != q.window { return }
	msg_void1(q.window, 'makeKeyAndOrderFront:', nil_obj())
	msg_bool1(q.window, 'makeFirstResponder:', view)
	if msg_bool(q.window, 'isKeyWindow') || q.focus_retries == 0 { return }
	q.focus_retries--
	dispatch_after(0.025, quick_focus_retry, context)
}
fn quick_animate_complete(context voidptr) {
	task := unsafe { &QuickAnimationTask(context) }
	mut q := task.quick
	for i, running in g_quick_animation_tasks { if running == task { g_quick_animation_tasks.delete(i); break } }
	if task.entering {
		if !q.visible { q.restore_dock(); return }
		msg_void_u64(q.window, 'setLevel:', 3)
		sync_quick_terminal_appearance(q.force_opaque)
		dispatch_main(quick_focus_retry, voidptr(q))
		if !app_is_active() { msg_void_bool(shared_app(), 'activateIgnoringOtherApps:', true); q.focus_retries = 10; dispatch_main(quick_focus_retry, voidptr(q)) }
	} else {
		msg_void1(q.window, 'orderOut:', nil_obj())
		if g_app_was_hidden { msg_void1(shared_app(), 'hide:', nil_obj()) }
	}
}
pub fn (mut q NativeQuickTerminal) show() {
	if q.visible { return }; q.visible = true
	msg_void2(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), 'postNotificationName:object:', nsstring('QuickTerminalDidChangeVisibility'), q.observer)
	if !app_is_active() {
		previous := msg_id(msg_id(get_class('NSWorkspace'), 'sharedWorkspace'), 'frontmostApplication')
		bundle := msg_id(get_class('NSBundle'), 'mainBundle')
		if objc_utf8_string(msg_id(previous, 'bundleIdentifier')) != objc_utf8_string(msg_id(bundle, 'bundleIdentifier')) { msg_void(q.previous_app,'release'); q.previous_app = voidptr(msg_id(previous, 'retain')) }
	}
	q.previous_space = C.CGSGetActiveSpace(C.CGSMainConnectionID())
	if g_quick_create != unsafe { nil } && is_nil(view_userdata(ObjId(q.view))) {
		if is_nil(view_window(q.view)) {
			q.view = voidptr(create_terminal_view(msg_rect(msg_id(q.window, 'contentView'), 'bounds')))
			msg_void1(q.window, 'setContentView:', ObjId(q.view))
		}
		if !g_quick_create(q.view) { q.visible = false; return }
	}
	screen := quick_screen(q.config); if is_nil(screen) { return }
	visible := msg_rect(screen, 'visibleFrame')
	w, h := q.config.dimensions(SplitBounds{width: visible.width, height: visible.height})
	cached := q.cached_frame(screen)
	mut size := SplitBounds{width: w, height: h}
	if frame := cached { size.width = frame.width; size.height = frame.height }
	old_frame := msg_rect(q.window, 'frame')
	mut initial := quick_terminal_frame(q.config.position, SplitBounds{width: old_frame.width, height: old_frame.height}, SplitBounds{x: visible.x, y: visible.y, width: visible.width, height: visible.height}, true)
	initial.width = size.width; initial.height = size.height
	final := quick_terminal_frame(q.config.position, size, SplitBounds{x: visible.x, y: visible.y, width: visible.width, height: visible.height}, false)
	msg_void_f64(q.window, 'setAlphaValue:', 0)
	C.witty_macos_msg_void_rect_bool(q.window, sel('setFrame:display:'), objc_rect(initial.x, initial.y, initial.width, initial.height), false)
	msg_void_u64(q.window, 'setLevel:', 101)
	if quick_conflicts_dock(q.config.position, screen) { q.hide_dock() } else { q.restore_dock(); q.dock_state_saved = false }
	q.animation_in = true; q.animation_frame = objc_rect(final.x, final.y, final.width, final.height)
	msg_void1(q.window, 'makeKeyAndOrderFront:', nil_obj())
	task := &QuickAnimationTask{quick: &q, entering: q.animation_in, frame: q.animation_frame}
	g_quick_animation_tasks << task
	C.witty_controller_animate(voidptr(task), voidptr(quick_animate_change), voidptr(quick_animate_complete))
}
pub fn (mut q NativeQuickTerminal) hide() {
	if !q.visible { return }; q.visible = false
	msg_void2(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), 'postNotificationName:object:', nsstring('QuickTerminalDidChangeVisibility'), q.observer)
	q.save_screen_state(true); q.restore_dock(); q.dock_state_saved = false; q.dock_hidden_at_resign = false
	if !msg_bool(q.window, 'isOnActiveSpace') { msg_void(q.previous_app,'release'); q.previous_app = unsafe { nil }; msg_void1(q.window, 'orderOut:', nil_obj()); if g_app_was_hidden { msg_void1(shared_app(),'hide:',nil_obj()) }; return }
	mut screen := msg_id(q.window, 'screen'); if is_nil(screen) { screen = msg_id(get_class('NSScreen'), 'mainScreen') }; if is_nil(screen) { return }
	if !is_nil(q.previous_app) {
		previous := ObjId(q.previous_app); q.previous_app = unsafe { nil }
		if !msg_bool(previous, 'isTerminated') { msg_bool_u64(previous, 'activateWithOptions:', 0) }
		msg_void(previous, 'release')
	}
	frame := msg_rect(q.window, 'frame'); visible := msg_rect(screen, 'visibleFrame')
	initial := quick_terminal_frame(q.config.position, SplitBounds{width: frame.width, height: frame.height}, SplitBounds{x: visible.x, y: visible.y, width: visible.width, height: visible.height}, true)
	q.animation_in = false; q.animation_frame = objc_rect(initial.x, initial.y, initial.width, initial.height)
	msg_void_u64(q.window, 'setLevel:', 101)
	task := &QuickAnimationTask{quick: &q, entering: q.animation_in, frame: q.animation_frame}
	g_quick_animation_tasks << task
	C.witty_controller_animate(voidptr(task), voidptr(quick_animate_change), voidptr(quick_animate_complete))
}
pub fn quick_terminal(config NativeQuickConfig, create QuickTerminalCreateCallback, can_close QuickTerminalClosedCallback) &NativeQuickTerminal {
	if g_quick_terminal != unsafe { nil } { g_quick_terminal.config = config; return g_quick_terminal }
	register_classes()
	window := msg_id_rect_u64_u64_bool(msg_id(quick_window_class(), 'alloc'), 'initWithContentRect:styleMask:backing:defer:', objc_rect(0, 0, 800, 400), ns_window_style_resizable | u64(1 << 7), ns_backing_store_buffered, false)
	view := create_terminal_view(objc_rect(0, 0, 800, 400))
	msg_void1(window, 'setContentView:', view)
	msg_void_bool(window, 'setRestorable:', false)
	msg_void1(window, 'setIdentifier:', nsstring('com.alexander.witty.quickTerminal'))
	msg_void1(window, 'setAccessibilitySubrole:', nsstring('AXFloatingWindow'))
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void_u64(window, 'setCollectionBehavior:', u64(1 << 6) | u64(1 << 8) | if config.remain_on_space { u64(1 << 1) } else { u64(1) })
	mut cls := get_class('VTQuickTerminalObserver')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('VTQuickTerminalObserver'), 0)
		C.macos_class_add_ivar(cls, cstr('vtQuickTerminal'), sizeof(voidptr), 3, cstr('^v'))
		add_method(cls, 'vtResignKey:', voidptr(quick_did_resign_key), 'v@:@')
		add_method(cls, 'vtBecomeKey:', voidptr(quick_did_become_key), 'v@:@')
		add_method(cls, 'vtResize:', voidptr(quick_did_resize), 'v@:@')
		add_method(cls, 'vtScreens:', voidptr(quick_screens_changed), 'v@:@')
		add_method(cls, 'vtTerminate:', voidptr(quick_will_terminate), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	observer := msg_id(msg_id(cls, 'alloc'), 'init')
	q := &NativeQuickTerminal{view: voidptr(view), window: window, observer: observer, config: config}
	C.macos_objc_set_ptr_ivar(observer, cstr('vtQuickTerminal'), voidptr(q))
	g_quick_terminal = q; g_quick_create = create; g_quick_can_close = can_close
	center := msg_id(get_class('NSNotificationCenter'), 'defaultCenter')
	for pair in [['NSWindowDidResignKeyNotification','vtResignKey:'],['NSWindowDidBecomeKeyNotification','vtBecomeKey:'],['NSWindowDidResizeNotification','vtResize:']] { C.witty_macos_observe(center,observer,sel(pair[1]),nsstring(pair[0]),window) }
	for pair in [['NSApplicationDidChangeScreenParametersNotification','vtScreens:'],['NSApplicationWillTerminateNotification','vtTerminate:']] { C.witty_macos_observe(center,observer,sel(pair[1]),nsstring(pair[0]),nil_obj()) }
	return q
}
pub fn quick_terminal_for_view(view voidptr) ?&NativeQuickTerminal {
	if g_quick_terminal != unsafe { nil } && view_window(view) == voidptr(g_quick_terminal.window) { return g_quick_terminal }
	return none
}
pub fn quick_terminal_deny_tab(view voidptr) bool {
	if _ := quick_terminal_for_view(view) {
		alert := msg_id(alloc('NSAlert'), 'init')
		msg_void1(alert, 'setMessageText:', nsstring('Cannot Create New Tab'))
		msg_void1(alert, 'setInformativeText:', nsstring("Tabs aren't supported in the Quick Terminal."))
		msg_id1(alert, 'addButtonWithTitle:', nsstring('OK'))
		msg_void_u64(alert, 'setAlertStyle:', 0)
		msg_void2(alert, 'beginSheetModalForWindow:completionHandler:', ObjId(view_window(view)), nil_obj())
		msg_void(alert,'release')
		return true
	}
	return false
}

fn quick_window_class() ObjId {
	mut cls := get_class('VTQuickTerminalWindow')
	if !is_nil(cls) { return cls }
	cls = C.macos_objc_allocate_class_pair(get_class('NSPanel'), cstr('VTQuickTerminalWindow'), 0)
	add_method(cls, 'canBecomeKeyWindow', voidptr(native_window_can_become_key), 'B@:')
	add_method(cls, 'canBecomeMainWindow', voidptr(native_window_can_become_key), 'B@:')
	register_native_zoom_window_methods(cls)
	C.macos_objc_register_class_pair(cls)
	return cls
}
pub fn (mut q NativeQuickTerminal) toggle() { if q.visible { q.hide() } else { q.show() } }
pub fn (mut q NativeQuickTerminal) toggle_fullscreen() {
	front := msg_id(msg_id(get_class('NSWorkspace'), 'sharedWorkspace'), 'frontmostApplication')
	bundle := msg_id(get_class('NSBundle'), 'mainBundle')
	frontmost := objc_utf8_string(msg_id(front, 'bundleIdentifier')) == objc_utf8_string(msg_id(bundle, 'bundleIdentifier'))
	mode := if !frontmost { NativeFullscreenMode.visible_menu } else if C.witty_macos_screen_insets(msg_id(q.window, 'screen')).top > 0 { NativeFullscreenMode.padded_notch } else { NativeFullscreenMode.non_native }
	toggle_fullscreen_mode(q.view, mode)
}

pub fn update_quick_terminal_config(config NativeQuickConfig) {
	if g_quick_terminal == unsafe { nil } { return }
	g_quick_terminal.config = NativeQuickConfig{...config, position: g_quick_terminal.config.position}
	sync_quick_terminal_appearance(g_quick_terminal.force_opaque)
}
// QuickTerminalController.syncAppearance uses its app-derived configuration,
// independently of every SurfaceView's targeted derived-config notifications.
pub fn sync_quick_terminal_appearance(force_opaque bool) {
	if g_quick_terminal == unsafe { nil } { return }
	mut q := g_quick_terminal
	q.force_opaque = force_opaque
	msg_void_u64(q.window, 'setCollectionBehavior:', u64(1 << 6) | u64(1 << 8) | if q.config.remain_on_space { u64(1 << 1) } else { u64(1) })
	if !msg_bool(q.window,'isVisible') { return }
	if !force_opaque && (q.config.window.opacity < 1 || q.config.window.blur < 0) {
		msg_void_bool(q.window,'setOpaque:',false)
		msg_void1(q.window,'setBackgroundColor:',native_color(0xffffff,0.001))
		if q.config.window.blur >= 0 { C.witty_macos_set_window_background_blur(q.window,int(q.config.window.blur)) }
	} else {
		msg_void_bool(q.window,'setOpaque:',true)
		msg_void1(q.window,'setBackgroundColor:',msg_id(get_class('NSColor'),'windowBackgroundColor'))
	}
}
