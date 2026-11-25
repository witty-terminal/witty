@[has_globals]
module macos

// Translated native action state and presentation from Ghostty.App.swift and
// SurfaceView{,_AppKit}.swift. AppKit controls stand in for SwiftUI controls;
// editing, callback, timing, focus, and positioning rules are the source rules.
#insert "@VMODROOT/macos/action_bridge.h"

fn C.witty_action_timer(interval f64, target voidptr, selector voidptr, info voidptr, repeats bool) voidptr
fn C.witty_action_hit_super(view voidptr, defining_class voidptr, x f64, y f64) voidptr
fn C.witty_action_add_tab(window voidptr, other voidptr, order i64)
fn C.EnableSecureEventInput() int
fn C.DisableSecureEventInput() int
fn C.witty_macos_set_document_cursor(view voidptr, cursor voidptr)
fn C.witty_action_show_popover(popover voidptr, view voidptr, edge u64)
fn C.witty_action_repeat_forever(animation voidptr)

pub struct ActionCallbacks {
pub:
	inspector NativeInspectorCallbacks
	size      fn (voidptr, f64, f64)    = unsafe { nil }
	present   fn (voidptr, voidptr)     = unsafe { nil }
	binding   fn (voidptr, string) bool = unsafe { nil }
	title     fn (voidptr, string)      = unsafe { nil }
	tab_title fn (voidptr, ?string)     = unsafe { nil }
}

pub enum SearchCorner {
	top_left
	top_right
	bottom_left
	bottom_right
}

@[heap]
pub struct NativeActionSurface {
pub mut:
	terminal_title           ?string
	pwd                      ?string
	proxy_icon               bool
	uuid                     string
	title                    string
	notification_identifiers []string
	view                     voidptr
	userdata                 voidptr
	callbacks                ActionCallbacks
	closed                   bool
	focused                  bool = true
	search_active            bool
	search_needle            string
	search_selected          ?uint
	search_total             ?uint
	search_corner            SearchCorner = .top_right
	key_sequence             []string
	key_tables               []string
	readonly                 bool
	bell                     bool
	healthy                  bool = true
	password_input           bool
	secure_indication        bool = true
	bell_border              bool
	visual_background        u32
	progress_state           int
	progress                 ?u8
	progress_active          bool
mut:
	inspector           &NativeInspectorView  = unsafe { nil }
	scroll              &NativeSurfaceScroll  = unsafe { nil }
	palette             &NativeCommandPalette = unsafe { nil }
	title_timer         ObjId
	title_fallback      ObjId
	pending_title       string
	progress_view       ObjId
	owner               ObjId
	overlay             ObjId
	search_bar          ObjId
	search_field        ObjId
	search_count        ObjId
	search_timer        ObjId
	search_published    bool
	progress_timer      ObjId
	progress_layer      ObjId
	progress_track      ObjId
	progress_color      ?u32
	progress_tint       NativeProgressTint
	popover             ObjId
	secure_badge        ObjId
	pulse_timer         ObjId
	drag_start          ObjCPoint
	drag_origin         ObjCRect
	key_top             bool
	key_drag_start      f64
	key_drag_offset     f64
	key_dragging        bool
	key_width           f64
	key_dots            [3]ObjId
	key_parts           []KeyIndicatorPart
	key_dot_start       f64
	key_layout_scale    f64
	key_surface_size    ObjCSize
	key_surface_scale   f64
	key_material        ObjId
	key_shadow          ObjId
	key_ink             ObjId
	previous_sequence   []string
	previous_tables     []string
	hover_tracking_rect ObjCRect
	hover_tracking      ObjId
	secure_gradient     ObjId
	secure_art          ObjId
	secure_symbol       ObjId
	secure_card         ObjId
	secure_wash         ObjId
	secure_outline      ObjId
	secure_scale        f64
	secure_palette      [5]u32
	bell_layer          ObjId
	bell_edges          [4]ObjId
	highlighted         bool
	highlight_layer     ObjId
	highlight_radial    ObjId
	highlight_border    ObjId
	highlight_mask      ObjId
	highlight_edges     [4]ObjId
	highlight_shadows   []ObjId
	highlight_accent    ?u32
	highlight_texture_size ObjCSize
	highlight_timer     ObjId
	last_progress_value int = -1000
	last_progress_width f64
	last_progress_scale f64
	key_badge           ObjId
	readonly_badge      ObjId
	readonly_material   ObjId
	readonly_ink        ObjId
	readonly_scale      f64
	readonly_title_width f64
	health_label        ObjId
	hover_label         ObjId
	hover_url           string
	hover_display       string
	hover_line          voidptr
	hover_text_limit    f64 = -1
	hover_text_width    f64
	hover_left          bool
}

__global (
	g_action_surfaces map[u64]&NativeActionSurface
	g_secure_global   bool
	g_secure_enabled  bool
	g_secure_scopes   map[u64]bool
)

fn action_owner_state(owner ObjId) ?&NativeActionSurface {
	ptr := C.macos_objc_get_ptr_ivar(owner, cstr('state'))
	if ptr == unsafe { nil } { return none }
	return unsafe { &NativeActionSurface(ptr) }
}

fn action_owner(surface &NativeActionSurface) ObjId {
	mut cls := get_class('WittyActionOwner')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('WittyActionOwner'), 0)
		add_ptr_ivar(cls, 'state')
		register_action_notification_methods(cls)
		register_action_title_methods(cls)
		register_action_visual_methods(cls)
		add_method(cls, 'controlTextDidChange:', voidptr(action_search_edit), 'v@:@')
		add_method(cls, 'control:textView:doCommandBySelector:', voidptr(action_search_command),
			'B@:@@:')
		add_method(cls, 'searchNext:', voidptr(action_search_next), 'v@:@')
		add_method(cls, 'searchPrevious:', voidptr(action_search_previous), 'v@:@')
		add_method(cls, 'searchClose:', voidptr(action_search_close), 'v@:@')
		add_method(cls, 'searchTimer:', voidptr(action_search_timer), 'v@:@')
		add_method(cls, 'progressTimer:', voidptr(action_progress_timer), 'v@:@')
		add_method(cls, 'pulseTimer:', voidptr(action_pulse_timer), 'v@:@')
		add_method(cls, 'readonly:', voidptr(action_readonly_click), 'v@:@')
		add_method(cls, 'keyInfo:', voidptr(action_key_info), 'v@:@')
		add_method(cls, 'readonlyDisable:', voidptr(action_readonly_disable), 'v@:@')
		add_method(cls, 'popoverClose:', voidptr(action_popover_close), 'v@:@')
		add_method(cls, 'secureInfo:', voidptr(action_secure_info), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	obj := msg_id(alloc('WittyActionOwner'), 'init')
	C.macos_objc_set_ptr_ivar(obj, cstr('state'), voidptr(surface))
	return obj
}

fn action_label(text string, frame ObjCRect) ObjId {
	obj := msg_id_rect(alloc('NSTextField'), 'initWithFrame:', frame)
	msg_void_bool(obj, 'setEditable:', false)
	msg_void_bool(obj, 'setSelectable:', false)
	msg_void_bool(obj, 'setBezeled:', false)
	msg_void_bool(obj, 'setDrawsBackground:', false)
	msg_void1(obj, 'setStringValue:', nsstring(text))
	msg_void1(obj, 'setTextColor:', msg_id(get_class('NSColor'), 'labelColor'))
	return obj
}

fn action_button(surface &NativeActionSurface, text string, selector string, frame ObjCRect) ObjId {
	obj := msg_id_rect(alloc('NSButton'), 'initWithFrame:', frame)
	msg_void1(obj, 'setTitle:', nsstring(text))
	msg_void1(obj, 'setTarget:', surface.owner)
	msg_void1(obj, 'setAction:', sel(selector))
	msg_void_u64(obj, 'setBezelStyle:', 13)
	return obj
}

pub fn new_action_surface(view voidptr, userdata voidptr, callbacks ActionCallbacks) &NativeActionSurface {
	mut state := &NativeActionSurface{
		uuid:      objc_utf8_string(msg_id(msg_id(get_class('NSUUID'), 'UUID'), 'UUIDString'))
		view:      view
		userdata:  userdata
		callbacks: callbacks
	}
	state.owner = action_owner(state)
	state.title_fallback = C.witty_action_timer(0.5, state.owner, sel('titleFallback:'), nil_obj(),
		false)
	mut cls := get_class('WittyActionOverlay')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittyActionOverlay'), 0)
		add_ptr_ivar(cls, 'state')
		add_method(cls, 'isFlipped', voidptr(action_flipped), 'B@:')
		add_method(cls, 'hitTest:', voidptr(action_hit_test), '@@:{CGPoint=dd}')
		add_method(cls, 'drawRect:', voidptr(action_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
		add_method(cls, 'viewDidChangeEffectiveAppearance', voidptr(action_overlay_appearance_changed), 'v@:')
		add_method(cls, 'viewDidChangeBackingProperties', voidptr(action_overlay_backing_changed), 'v@:')
		add_method(cls, 'overlayColorsChanged:', voidptr(action_overlay_colors_changed), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	state.overlay = msg_id_rect(alloc('WittyActionOverlay'), 'initWithFrame:', objc_rect(0, 0,
		view_width(view), view_height(view)))
	C.macos_objc_set_ptr_ivar(state.overlay, cstr('state'), voidptr(state))
	msg_void_u64(state.overlay, 'setAutoresizingMask:', 18)
	msg_void1(view, 'addSubview:', state.overlay)
	msg_void_bool(state.overlay, 'setWantsLayer:', true)
	mut passive := get_class('WittyPassiveOverlay')
	if is_nil(passive) {
		passive = C.macos_objc_allocate_class_pair(get_class('NSView'),
			cstr('WittyPassiveOverlay'), 0)
		add_method(passive, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
		C.macos_objc_register_class_pair(passive)
	}
	state.initialize_progress()
	g_action_surfaces[u64(view)] = state
	state.initialize_key_indicator()
	state.initialize_readonly_badge()
	state.health_label = new_health_overlay()
	msg_void1(state.overlay, 'addSubview:', state.health_label)
	state.initialize_secure_visuals()
	state.hover_label = new_hover_banner(state)
	msg_void1(state.overlay, 'addSubview:', state.hover_label)
	msg_void(state.hover_label, 'release')
	state.initialize_visuals()
	state.initialize_highlight()
	state.scroll = new_surface_scroll(state)
	C.witty_macos_observe(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), state.overlay,
		sel('overlayColorsChanged:'), nsstring('NSSystemColorsDidChangeNotification'), nil_obj())
	state.refresh()
	return state
}

pub fn (mut state NativeActionSurface) deinit() {
	if state.closed { return }
	state.hide_inspector()
	state.closed = true
	state.clear_hover_tracking()
	state.clear_hover_line()
	if state.palette != unsafe { nil } { state.palette.close() }
	state.remove_notifications()
	for timer in [state.search_timer, state.progress_timer, state.pulse_timer, state.title_timer,
		state.title_fallback, state.highlight_timer] {
		if !is_nil(timer) { msg_void(timer, 'invalidate') }
	}
	g_secure_scopes.delete(u64(state.view))
	secure_apply()
	g_action_surfaces.delete(u64(state.view))
	C.macos_objc_set_ptr_ivar(state.owner, cstr('state'), nil_obj())
	C.macos_objc_set_ptr_ivar(state.overlay, cstr('state'), nil_obj())
	C.macos_objc_set_ptr_ivar(state.key_badge, cstr('state'), nil_obj())
	C.macos_objc_set_ptr_ivar(state.key_ink, cstr('state'), nil_obj())
	C.macos_objc_set_ptr_ivar(state.hover_label, cstr('state'), nil_obj())
	msg_void1(msg_id(get_class('NSNotificationCenter'), 'defaultCenter'), 'removeObserver:', state.overlay)
	msg_void(state.overlay, 'removeFromSuperview')
	msg_void(state.overlay, 'release')
	msg_void(state.owner, 'release')
	if state.scroll != unsafe { nil } { state.scroll.deinit() }
}

fn action_passive_hit(_self ObjId, _cmd Sel, _point ObjCPoint) ObjId {
	return nil_obj()
}

fn action_flipped(_self ObjId, _cmd Sel) bool {
	return true
}

fn action_hit_test(self ObjId, _cmd Sel, point ObjCPoint) ObjId {
	hit := C.witty_action_hit_super(self, get_class('WittyActionOverlay'), point.x, point.y)
	if hit == self { return nil_obj() }
	return hit
}

pub fn (mut state NativeActionSurface) resize() {
	msg_void_rect(state.overlay, 'setFrame:', objc_rect(0, 0, view_width(state.view),
		view_height(state.view)))
	state.refresh()
}

fn action_overlay_backing_changed(self ObjId, _cmd Sel) {
	view_super_void(self, 'WittyActionOverlay', 'viewDidChangeBackingProperties')
	if mut state := action_owner_state(self) {
		if state.progress_active { state.refresh_progress() }
		state.highlight_accent = none
		if state.highlighted { state.refresh_highlight() }
		state.refresh_secure_visuals()
		if !is_nil(state.bell_layer) { state.refresh_bell_visuals() }
		state.refresh_hover_visuals()
		state.refresh_readonly_badge()
		state.refresh_key_visuals()
		if state.palette != unsafe { nil } { state.palette.layout() }
	}
}

fn action_overlay_appearance_changed(self ObjId, _cmd Sel) {
	view_super_void(self, 'WittyActionOverlay', 'viewDidChangeEffectiveAppearance')
	action_overlay_colors_changed(self, nil_obj(), nil_obj())
}

fn action_overlay_colors_changed(self ObjId, _cmd Sel, _notification ObjId) {
	if mut state := action_owner_state(self) {
		if state.progress_active { state.refresh_progress() }
		if state.highlighted { state.refresh_highlight() }
		state.refresh_secure_visuals()
		state.refresh_hover_appearance()
		msg_void_bool(state.readonly_ink, 'setNeedsDisplay:', true)
		state.update_key_colors()
		if state.palette != unsafe { nil } {
			state.palette.layout()
			state.palette.repaint_rows()
		}
	}
}

fn (mut state NativeActionSurface) refresh() {
	if state.closed { return }
	width := view_width(state.view)
	height := view_height(state.view)
	if state.palette != unsafe { nil } { state.palette.layout() }
	if state.search_active {
		right := state.search_corner in [.top_right, .bottom_right]
		bottom := state.search_corner in [.bottom_left, .bottom_right]
		msg_void_rect(state.search_bar, 'setFrame:', objc_rect(if right { width - 348 } else { 8 }, if bottom {
			height - 50
		} else {
			8
		}, 340, 42))
	}
	state.refresh_key_visuals()
	state.refresh_readonly_badge()
	msg_void_bool(state.health_label, 'setHidden:', state.healthy)
	msg_void_rect(state.health_label, 'setFrame:', objc_rect((width - 486) / 2, (height - 128) / 2, 486, 128))
	state.refresh_hover_visuals()
	msg_void_bool(state.secure_badge, 'setHidden:', !(g_secure_enabled && state.focused
		&& state.secure_indication && msg_bool(view_window(state.view), 'isKeyWindow')))
	state.refresh_secure_visuals()
	state.refresh_bell_visuals()
	state.refresh_highlight()
	state.refresh_progress()
	msg_void_bool(state.overlay, 'setNeedsDisplay:', true)
}

pub fn (mut state NativeActionSurface) start_search(needle string) {
	if state.closed { return }
	if state.search_active {
		if needle.len > 0 && needle != state.search_needle { state.set_search_needle(needle) }
	} else {
		state.search_active = true
		state.search_selected = none
		state.search_total = none
		state.search_needle = ''
		state.search_published = false
		mut cls := get_class('WittySearchBar')
		if is_nil(cls) {
			cls = C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittySearchBar'), 0)
			add_ptr_ivar(cls, 'state')
			add_method(cls, 'isFlipped', voidptr(action_flipped), 'B@:')
			add_method(cls, 'mouseDown:', voidptr(search_drag_start), 'v@:@')
			add_method(cls, 'mouseDragged:', voidptr(search_drag_changed), 'v@:@')
			add_method(cls, 'mouseUp:', voidptr(search_drag_end), 'v@:@')
			C.macos_objc_register_class_pair(cls)
		}
		state.search_bar = msg_id_rect(alloc('WittySearchBar'), 'initWithFrame:', objc_rect(8, 8,
			340, 42))
		C.macos_objc_set_ptr_ivar(state.search_bar, cstr('state'), voidptr(&state))
		msg_void1(state.overlay, 'addSubview:', state.search_bar)
		state.search_field = msg_id_rect(alloc('NSTextField'), 'initWithFrame:', objc_rect(8, 8,
			180, 26))
		msg_void1(state.search_field, 'setPlaceholderString:', nsstring('Search'))
		msg_void1(state.search_field, 'setDelegate:', state.owner)
		msg_void1(state.search_bar, 'addSubview:', state.search_field)
		state.search_count = action_label('', objc_rect(189, 12, 54, 22))
		msg_void1(state.search_bar, 'addSubview:', state.search_count)
		for index, selector in ['searchNext:', 'searchPrevious:', 'searchClose:'] {
			button := action_button(&state, ['⌃', '⌄', '×'][index], selector, objc_rect(244 +
				index * 29, 8, 26, 26))
			msg_void1(state.search_bar, 'addSubview:', button)
			msg_void(button, 'release')
		}
		state.set_search_needle(needle)
	}
	msg_void1(state.search_field, 'setStringValue:', nsstring(state.search_needle))
	state.refresh()
	msg_bool1(view_window(state.view), 'makeFirstResponder:', state.search_field)
}

pub fn (mut state NativeActionSurface) end_search() {
	if !state.search_active { return }
	state.search_active = false
	if !is_nil(state.search_timer) {
		msg_void(state.search_timer, 'invalidate')
		state.search_timer = nil_obj()
	}
	msg_void(state.search_bar, 'removeFromSuperview')
	msg_void(state.search_bar, 'release')
	state.search_bar = nil_obj()
	state.perform('end_search')
}

fn (state &NativeActionSurface) perform(action string) bool {
	if state.closed || state.callbacks.binding == unsafe { nil } { return false }
	return state.callbacks.binding(state.userdata, action)
}

fn composed_character_count(text string) int {
	return int(native_character_count(nsstring(text)))
}

fn (mut state NativeActionSurface) set_search_needle(needle string) {
	// removeDuplicates applies after the first published value too.
	if state.search_published && needle == state.search_needle { return }
	state.search_published = true
	state.search_needle = needle
	if !is_nil(state.search_timer) {
		msg_void(state.search_timer, 'invalidate')
		state.search_timer = nil_obj()
	}
	if needle.len == 0 || composed_character_count(needle) >= 3 {
		state.perform('search:${needle}')
	} else {
		state.search_timer = C.witty_action_timer(0.3, state.owner, sel('searchTimer:'), nil_obj(),
			false)
	}
}

pub fn (mut state NativeActionSurface) search_counts(selected ?uint, total ?uint) {
	if !state.search_active { return }
	state.search_selected = selected
	state.search_total = total
	text := if value := selected {
		'${value + 1}/' + if count := total { count.str() } else { '?' }
	} else if count := total {
		'-/${count}'
	} else {
		''
	}
	msg_void1(state.search_count, 'setStringValue:', nsstring(text))
}

fn action_search_edit(self ObjId, _cmd Sel, _notification ObjId) {
	mut state := action_owner_state(self) or { return }
	value := objc_utf8_string(msg_id(state.search_field, 'stringValue'))
	if value != state.search_needle { state.set_search_needle(value) }
}

fn action_search_command(self ObjId, _cmd Sel, _control ObjId, _text_view ObjId, command Sel) bool {
	mut state := action_owner_state(self) or { return false }
	if command == sel('cancelOperation:') {
		if state.search_needle.len == 0 { state.end_search() }
		msg_bool1(view_window(state.view), 'makeFirstResponder:', state.view)
		return true
	}
	if command == sel('insertNewline:') {
		event := msg_id(msg_id(get_class('NSApplication'), 'sharedApplication'), 'currentEvent')
		state.perform(if msg_u64(event, 'modifierFlags') & ns_event_modifier_flag_shift != 0 {
			'navigate_search:previous'
		} else {
			'navigate_search:next'
		})
		return true
	}
	return false
}

fn action_search_next(self ObjId, _cmd Sel, _sender ObjId) {
	if state := action_owner_state(self) { state.perform('navigate_search:next') }
}

fn action_search_previous(self ObjId, _cmd Sel, _sender ObjId) {
	if state := action_owner_state(self) { state.perform('navigate_search:previous') }
}

fn action_search_close(self ObjId, _cmd Sel, _sender ObjId) {
	if mut state := action_owner_state(self) {
		state.end_search()
		msg_bool1(view_window(state.view), 'makeFirstResponder:', state.view)
	}
}

fn action_search_timer(self ObjId, _cmd Sel, _timer ObjId) {
	if mut state := action_owner_state(self) {
		state.search_timer = nil_obj()
		if state.search_active { state.perform('search:${state.search_needle}') }
	}
}

fn search_drag_start(self ObjId, _cmd Sel, event ObjId) {
	if mut state := action_owner_state(self) {
		state.drag_start = msg_point(event, 'locationInWindow')
		state.drag_origin = msg_rect(self, 'frame')
	}
}

fn search_drag_changed(self ObjId, _cmd Sel, event ObjId) {
	if state := action_owner_state(self) {
		p := msg_point(event, 'locationInWindow')
		frame := state.drag_origin
		msg_void_rect(self, 'setFrame:', objc_rect(frame.x + p.x - state.drag_start.x, frame.y -
			p.y + state.drag_start.y, frame.width, frame.height))
	}
}

fn search_drag_end(self ObjId, _cmd Sel, _event ObjId) {
	if mut state := action_owner_state(self) {
		frame := msg_rect(self, 'frame')
		left := frame.x + frame.width / 2 < view_width(state.view) / 2
		top := frame.y + frame.height / 2 < view_height(state.view) / 2
		state.search_corner = if left {
			if top { SearchCorner.top_left } else { SearchCorner.bottom_left }
		} else {
			if top { SearchCorner.top_right } else { SearchCorner.bottom_right }
		}
		right := state.search_corner in [.top_right, .bottom_right]
		bottom := state.search_corner in [.bottom_left, .bottom_right]
		msg_void(get_class('NSAnimationContext'), 'beginGrouping')
		msg_void_f64(msg_id(get_class('NSAnimationContext'), 'currentContext'), 'setDuration:', 0.2)
		msg_void_rect(msg_id(self, 'animator'), 'setFrame:', objc_rect(if right {
			view_width(state.view) - 348
		} else {
			8
		}, if bottom { view_height(state.view) - 50 } else { 8 }, 340, 42))
		msg_void(get_class('NSAnimationContext'), 'endGrouping')
	}
}

fn action_draw(self ObjId, _cmd Sel, _rect ObjCRect) {
	state := action_owner_state(self) or { return }
	if !state.healthy {
		native_canvas_fill_rects(native_canvas_overlay_context(), state.visual_background, [msg_rect(self, 'bounds')])
	}
}

pub fn (mut state NativeActionSurface) set_key_sequence(active bool, trigger string) {
	if active {
		state.key_sequence << trigger
	} else {
		state.key_sequence.clear()
	}
	view_set_key_context(state.view, state.key_sequence.len > 0, state.key_tables.len > 0)
	state.refresh()
}

pub fn (mut state NativeActionSurface) set_key_table(operation int, name string) {
	match operation {
		0 {
			state.key_tables << name
		}
		1 {
			if state.key_tables.len > 0 { state.key_tables.pop() }
		}
		2 {
			state.key_tables.clear()
		}
		else {}
	}

	view_set_key_context(state.view, state.key_sequence.len > 0, state.key_tables.len > 0)
	state.refresh()
}

pub fn (mut state NativeActionSurface) set_readonly(readonly bool) {
	state.readonly = readonly
	state.refresh()
}

pub fn (mut state NativeActionSurface) ring_bell() {
	state.bell = true
	state.refresh()
}

pub fn (mut state NativeActionSurface) begin_key_down() {
	state.bell = false
	state.publish_title()
	state.refresh()
}

pub fn (mut state NativeActionSurface) renderer_health(healthy bool) {
	state.healthy = healthy
	state.refresh()
}

pub fn (mut state NativeActionSurface) set_progress(report_state int, progress ?u8) {
	if !is_nil(state.progress_timer) {
		msg_void(state.progress_timer, 'invalidate')
		state.progress_timer = nil_obj()
	}
	// Ghostty.Action.ProgressReport.State maps unknown native values to remove.
	normalized := if report_state in [0, 1, 2, 3, 4] { report_state } else { 0 }
	state.progress_active = normalized != 0
	state.progress_state = normalized
	state.progress = if state.progress_active { progress } else { none }
	if state.progress_active {
		state.progress_timer = C.witty_action_timer(15, state.owner, sel('progressTimer:'),
			nil_obj(), false)
	}
	state.refresh()
}

fn action_progress_timer(self ObjId, _cmd Sel, _timer ObjId) {
	if mut state := action_owner_state(self) {
		state.progress_timer = nil_obj()
		state.progress_active = false
		state.progress_state = 0
		state.progress = none
		state.refresh()
	}
}

fn action_pulse_timer(self ObjId, _cmd Sel, _timer ObjId) {
	if state := action_owner_state(self) { state.animate_key_dots() }
}

fn (mut state NativeActionSurface) show_popover(anchor ObjId, title string, text string, disable bool) {
	if !is_nil(state.popover) {
		msg_void1(state.popover, 'performClose:', nil_obj())
		msg_void(state.popover, 'release')
	}
	state.popover = new_obj('NSPopover')
	msg_void_u64(state.popover, 'setBehavior:', 1)
	controller := new_obj('NSViewController')
	content := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(0, 0, 350, 170))
	title_label := action_label(title, objc_rect(16, 140, 318, 22))
	body := action_label(text, objc_rect(16, 50, 318, 90))
	msg_void1(content, 'addSubview:', title_label)
	msg_void1(content, 'addSubview:', body)
	msg_void_u64(body, 'setLineBreakMode:', 0)
	if disable {
		button := action_button(&state, 'Disable', 'readonlyDisable:', objc_rect(250, 10, 84, 28))
		msg_void1(content, 'addSubview:', button)
		msg_void(button, 'release')
	}
	close := action_button(&state, 'Close', 'popoverClose:', objc_rect(if disable {
		156
	} else {
		250
	}, 10, 84, 28))
	msg_void1(content, 'addSubview:', close)
	msg_void(close, 'release')
	msg_void1(controller, 'setView:', content)
	msg_void1(state.popover, 'setContentViewController:', controller)
	C.witty_action_show_popover(state.popover, anchor, if anchor == state.key_badge {
		if state.key_top { u64(1) } else { u64(3) }
	} else {
		u64(1)
	})
	msg_void(title_label, 'release')
	msg_void(body, 'release')
	msg_void(content, 'release')
	msg_void(controller, 'release')
}

fn action_readonly_click(self ObjId, _cmd Sel, _sender ObjId) {
	if mut state := action_owner_state(self) {
		state.show_popover(state.readonly_badge, 'Read-Only Mode',
			'This terminal is in read-only mode. You can still view, select, and scroll through the content, but no input events will be sent to the running application.',
			true)
	}
}

fn action_readonly_disable(self ObjId, _cmd Sel, _sender ObjId) {
	if mut state := action_owner_state(self) {
		state.perform('toggle_readonly')
		msg_void1(state.popover, 'performClose:', nil_obj())
	}
}

fn action_popover_close(self ObjId, _cmd Sel, _sender ObjId) {
	if state := action_owner_state(self) { msg_void1(state.popover, 'performClose:', nil_obj()) }
}

fn action_key_info(self ObjId, _cmd Sel, _sender ObjId) {
	if mut state := action_owner_state(self) {
		state.show_popover(state.key_badge, if state.key_tables.len > 0 {
			'Key Table'
		} else {
			'Key Sequence'
		},
			(if state.key_tables.len > 0 {
				'A key table is a named set of keybindings, activated by some other key. Keys are interpreted using this table until it is deactivated.\n'
			} else {
				''
			}) + (if state.key_sequence.len > 0 {
				'A key sequence is a series of key presses that trigger an action. A pending key sequence is currently active.'
			} else {
				''
			}),
			false)
	}
}

fn action_secure_info(self ObjId, _cmd Sel, _sender ObjId) {
	if mut state := action_owner_state(self) {
		state.show_popover(state.secure_badge, 'Secure Input',
			'Secure Input is active. Secure Input is a macOS security feature that prevents applications from reading keyboard events. This is enabled automatically whenever Witty detects a password prompt in the terminal, or at all times if `Witty > Secure Keyboard Entry` is active.',
			false)
	}
}

pub fn (mut state NativeActionSurface) mouse_over_link(url string) {
	if state.closed || state.hover_url == url {
		return
	}
	state.hover_url = url
	state.clear_hover_line()
	if url.len == 0 {
		state.hover_display = ''
		state.hover_left = false
	} else {
		state.hover_display = hover_display_url(url)
	}
	msg_void1(state.hover_label, 'setAccessibilityValue:', nsstring(state.hover_display))
	state.refresh_hover_visuals()
}

pub fn (mut state NativeActionSurface) focus(focused bool) {
	state.focused = focused
	if state.password_input {
		g_secure_scopes[u64(state.view)] = focused
		secure_apply()
	}
	if focused {
		state.bell = false
		state.publish_title()
		if pwd := state.pwd { state.set_pwd(pwd, state.proxy_icon) }
	}
	state.refresh()
}

pub fn secure_set_global(mode int) {
	g_secure_global = if mode == 0 {
		true
	} else if mode == 1 {
		false
	} else {
		!g_secure_global
	}
	secure_apply()
	secure_refresh()
}

pub fn (mut state NativeActionSurface) secure_input(mode int) {
	state.password_input = if mode == 0 {
		true
	} else if mode == 1 {
		false
	} else {
		!state.password_input
	}
	if state.password_input {
		g_secure_scopes[u64(state.view)] = state.focused
	} else {
		g_secure_scopes.delete(u64(state.view))
	}
	secure_apply()
}

fn secure_desired() bool {
	if g_secure_global { return true }
	for _, focused in g_secure_scopes {
		if focused { return true }
	}
	return false
}

fn secure_apply() {
	if !app_is_active() || g_secure_enabled == secure_desired() { return }
	status := if g_secure_enabled {
		C.DisableSecureEventInput()
	} else {
		C.EnableSecureEventInput()
	}
	if status == 0 {
		g_secure_enabled = secure_desired()
	} else {
		eprintln('secure input apply failed err=${status}')
	}
	secure_refresh()
}

pub fn secure_app_focus(active bool) {
	if active {
		if !g_secure_enabled && secure_desired() {
			if C.EnableSecureEventInput() == 0 { g_secure_enabled = true }
		}
	} else if g_secure_enabled {
		if C.DisableSecureEventInput() == 0 { g_secure_enabled = false }
	}
	secure_refresh()
}

fn secure_refresh() {
	for _, mut state in g_action_surfaces {
		state.refresh()
	}
	if item := g_config_menu_items['toggle_secure_input'] {
		msg_void_u64(item, 'setState:', u64(if g_secure_global { 1 } else { 0 }))
	}
}

pub fn set_cursor_visibility(visible bool) {
	msg_void_bool(get_class('NSCursor'), 'setHiddenUntilMouseMoves:', !visible)
}

fn cursor_for_shape(shape int) ?ObjId {
	cursor_class := get_class('NSCursor')
	if C.witty_action_os_major() >= 15 {
		if shape in [20, 22] {
			return msg_id_u64(cursor_class, 'rowResizeCursorInDirections:', u64(if shape == 20 {
				1
			} else {
				2
			}))
		}
		if shape in [21, 23] {
			return msg_id_u64(cursor_class, 'columnResizeCursorInDirections:', u64(if shape == 23 {
				1
			} else {
				2
			}))
		}
		if shape == 28 { return msg_id(cursor_class, 'columnResizeCursor') }
		if shape == 29 { return msg_id(cursor_class, 'rowResizeCursor') }
	}
	selector := match shape {
		0 { 'arrowCursor' }
		1 { 'contextualMenuCursor' }
		3 { 'pointingHandCursor' }
		7 { 'crosshairCursor' }
		8 { 'IBeamCursor' }
		9 { 'IBeamCursorForVerticalLayout' }
		14 { 'operationNotAllowedCursor' }
		15 { 'openHandCursor' }
		16 { 'closedHandCursor' }
		20 { 'resizeUpCursor' }
		21 { 'resizeRightCursor' }
		22 { 'resizeDownCursor' }
		23 { 'resizeLeftCursor' }
		28 { 'resizeLeftRightCursor' }
		29 { 'resizeUpDownCursor' }
		else { return none }
	}
	return msg_id(cursor_class, selector)
}

pub fn set_cursor_shape(view voidptr, shape int) {
	cursor := cursor_for_shape(shape) or { return }
	if surface := g_action_surfaces[u64(view)] {
		if surface.scroll != unsafe { nil } {
			msg_void1(surface.scroll.scroll, 'setDocumentCursor:', cursor)
		}
	}
	msg_void(cursor, 'set')
	msg_void1(view_window(view), 'invalidateCursorRectsForView:', view)
}

pub fn (mut state NativeActionSurface) refresh_config() { state.refresh() }
