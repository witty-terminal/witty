@[has_globals]
module witty_macos

import input

#insert "@VMODROOT/witty_macos/input_source_abi.h"

pub struct C.witty_macos_range {
pub:
	location uint
	length uint
}

pub type NativeRange = C.witty_macos_range

pub struct NativeText {
pub:
	text string
	offset_start u32
	offset_len u32
	tl_px_x f64
	tl_px_y f64
}

pub struct NativeImeRect {
pub mut:
	x f64
	y f64
	width f64
	height f64
	cell_width f64
	cell_height f64
}

pub struct InputClientCallbacks {
pub:
	begin_key_down fn (voidptr) = unsafe { nil }
	translation_mods fn (voidptr, int) int = unsafe { nil }
	key fn (voidptr, voidptr, voidptr, input.KeyAction, ?string, bool) bool = unsafe { nil }
	binding fn (voidptr, voidptr, string) ?u32 = unsafe { nil }
	preedit fn (voidptr, ?string) = unsafe { nil }
	text fn (voidptr, string) = unsafe { nil }
	selection fn (voidptr) ?NativeText = unsafe { nil }
	has_selection fn (voidptr) bool = unsafe { nil }
	screen_text fn (voidptr) string = unsafe { nil }
	font fn (voidptr) voidptr = unsafe { nil }
	ime_rect fn (voidptr) NativeImeRect = unsafe { nil }
	binding_action fn (voidptr, string) bool = unsafe { nil }
}

@[heap]
struct InputViewState {
mut:
	marked ObjId
	accumulating bool
	accumulator []string
	last_perform ?f64
	key_sequence bool
	key_tables bool
	screen_contents ?string
	cache_timer voidptr
}

__global (
	g_input_callbacks InputClientCallbacks
	g_input_views map[u64]&InputViewState
	g_key_release_monitor ObjId
)

fn C.witty_macos_msg_range(obj voidptr, selector voidptr) C.witty_macos_range
fn C.witty_macos_msg_range_u64(obj voidptr, selector voidptr, index u64) C.witty_macos_range
fn C.witty_macos_msg_id_range(obj voidptr, selector voidptr, range C.witty_macos_range) voidptr
fn C.witty_macos_msg_rect_rect_obj(obj voidptr, selector voidptr, rect ObjCRect, other voidptr) ObjCRect
fn C.witty_macos_msg_rect_rect(obj voidptr, selector voidptr, rect ObjCRect) ObjCRect
fn C.witty_macos_key_event(event voidptr, flags u64, chars voidptr, ignoring voidptr) voidptr
fn C.witty_macos_monitor_key_releases(callback voidptr) voidptr
fn C.witty_macos_msg_super_from_void0(obj voidptr, defining_class voidptr, selector voidptr)
fn C.TISCopyCurrentKeyboardInputSource() voidptr
fn C.witty_macos_input_source_id(source voidptr) voidptr
fn C.sel_getName(selector voidptr) &char

pub fn set_input_client_callbacks(callbacks InputClientCallbacks) {
	g_input_callbacks = callbacks
}

pub fn event_mods(event voidptr) int { return int(input_mods(msg_u64(ObjId(event), 'modifierFlags')).int()) }
pub fn event_type(event voidptr) u64 { return msg_u64(ObjId(event), 'type') }
pub fn event_keycode(event voidptr) u32 { return u32(msg_u64(ObjId(event), 'keyCode')) }

// Native sequence/table action consumers use this when their state changes.
pub fn view_set_key_context(view voidptr, sequence bool, tables bool) {
	mut state := input_view_state(ObjId(view))
	state.key_sequence = sequence
	state.key_tables = tables
}

fn input_view_state(view ObjId) &InputViewState {
	key := u64(view)
	if state := g_input_views[key] { return state }
	state := &InputViewState{marked: msg_id1(alloc('NSMutableAttributedString'), 'initWithString:', nsstring(''))}
	g_input_views[key] = state
	return state
}

fn marked_text(view ObjId) string {
	state := input_view_state(view)
	return objc_utf8_string(msg_id(state.marked, 'string'))
}

fn has_marked_text(view ObjId) bool {
	return msg_u64(input_view_state(view).marked, 'length') > 0
}

fn keyboard_layout_id() ?string {
	source := C.TISCopyCurrentKeyboardInputSource()
	if source == unsafe { nil } { return none }
	defer { cf_release(source) }
	id := C.witty_macos_input_source_id(source)
	if id == unsafe { nil } { return none }
	return objc_utf8_string(ObjId(id))
}

fn same_keyboard_layout(before ?string, after ?string) bool {
	if previous := before {
		if current := after { return previous == current }
		return false
	}
	return after == none
}

fn register_input_methods(cls ObjId) {
	proto := get_protocol('NSTextInputClient')
	if !is_nil(proto) { C.macos_class_add_protocol(cls, proto) }
	add_method(cls, 'hasMarkedText', voidptr(input_has_marked), 'B@:')
	add_method(cls, 'markedRange', voidptr(input_marked_range), '{_NSRange=QQ}@:')
	add_method(cls, 'selectedRange', voidptr(input_selected_range), '{_NSRange=QQ}@:')
	add_method(cls, 'setMarkedText:selectedRange:replacementRange:', voidptr(input_set_marked), 'v@:@{_NSRange=QQ}{_NSRange=QQ}')
	add_method(cls, 'unmarkText', voidptr(input_unmark), 'v@:')
	add_method(cls, 'validAttributesForMarkedText', voidptr(input_marked_attributes), '@@:')
	add_method(cls, 'attributedSubstringForProposedRange:actualRange:', voidptr(input_attributed_substring), '@@:{_NSRange=QQ}^{_NSRange=QQ}')
	add_method(cls, 'characterIndexForPoint:', voidptr(input_character_index), 'Q@:{CGPoint=dd}')
	add_method(cls, 'firstRectForCharacterRange:actualRange:', voidptr(input_first_rect), '{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}')
	add_method(cls, 'insertText:replacementRange:', voidptr(input_insert_text), 'v@:@{_NSRange=QQ}')
	add_method(cls, 'doCommandBySelector:', voidptr(input_do_command), 'v@::')
	add_method(cls, 'performKeyEquivalent:', voidptr(input_perform_key_equivalent), 'B@:@')
	add_method(cls, 'dealloc', voidptr(input_view_dealloc), 'v@:')
}

fn input_view_dealloc(self ObjId, _cmd Sel) {
	if mut state := g_input_views[u64(self)] {
		input_cancel_screen_cache(mut state)
		msg_void(state.marked, 'release')
		g_input_views.delete(u64(self))
	}
	C.witty_macos_msg_super_from_void0(voidptr(self), voidptr(get_class('VTTerminalView')), voidptr(sel('dealloc')))
}

fn input_sync_preedit(view ObjId, clear_if_needed bool) {
	if g_input_callbacks.preedit == unsafe { nil } || is_nil(view_userdata(view)) { return }
	if has_marked_text(view) {
		g_input_callbacks.preedit(view_userdata(view), marked_text(view))
	} else if clear_if_needed {
		g_input_callbacks.preedit(view_userdata(view), none)
	}
}

fn input_key_down(view ObjId, event ObjId) {
	if g_input_callbacks.key == unsafe { nil } || is_nil(view_userdata(view)) {
		msg_void1(view, 'interpretKeyEvents:', msg_id1(get_class('NSArray'), 'arrayWithObject:', event))
		return
	}
	if g_input_callbacks.begin_key_down != unsafe { nil } { g_input_callbacks.begin_key_down(view_userdata(view)) }
	original_flags := msg_u64(event, 'modifierFlags')
	mods := int(input_mods(original_flags).int())
	translated := if g_input_callbacks.translation_mods != unsafe { nil } {
		g_input_callbacks.translation_mods(view_userdata(view), mods)
	} else { mods }
	// Keep AppKit's hidden flags, changing only the four translated flags.
	mask := ns_event_modifier_flag_shift | ns_event_modifier_flag_control | ns_event_modifier_flag_option | ns_event_modifier_flag_command
	flags := (original_flags & ~mask) | event_modifier_flags(translated)
	translation_event := if flags == original_flags { event } else {
		characters := msg_id_u64(event, 'charactersByApplyingModifiers:', flags)
		ignoring := msg_id(event, 'charactersIgnoringModifiers')
		created := ObjId(C.witty_macos_key_event(voidptr(event), flags, voidptr(if is_nil(characters) { nsstring('') } else { characters }), voidptr(if is_nil(ignoring) { nsstring('') } else { ignoring })))
		if is_nil(created) { event } else { created }
	}
	mut state := input_view_state(view)
	state.accumulating = true
	state.accumulator.clear()
	defer { state.accumulating = false; state.accumulator.clear() }
	marked_before := has_marked_text(view)
	layout_before := if !marked_before { keyboard_layout_id() } else { none }
	state.last_perform = none
	msg_void1(view, 'interpretKeyEvents:', msg_id1(get_class('NSArray'), 'arrayWithObject:', translation_event))
	if !marked_before && !same_keyboard_layout(layout_before, keyboard_layout_id()) { return }
	input_sync_preedit(view, marked_before)
	action := if msg_bool(event, 'isARepeat') { input.KeyAction.repeat } else { input.KeyAction.press }
	if state.accumulator.len > 0 {
		for text in state.accumulator { input_key_action(view, event, translation_event, action, text, false) }
	} else {
		input_key_action(view, event, translation_event, action, ghostty_characters(translation_event), has_marked_text(view) || marked_before)
	}
}

// NSEvent.ghosttyCharacters. Control/PUA interpretation is shared with native
// key equivalents, while source keyAction rejects leading control UTF-8 bytes.
fn ghostty_characters(event ObjId) ?string {
	obj := msg_id(event, 'characters')
	if is_nil(obj) { return none }
	text := objc_utf8_string(obj)
	// Swift String.count counts composed characters rather than UTF-16 units.
	if text.len > 0 && native_character_count(obj) == 1 {
		cp := text.runes()[0]
		if cp < 0x20 {
			flags := msg_u64(event, 'modifierFlags') & ~ns_event_modifier_flag_control
			chars := msg_id_u64(event, 'charactersByApplyingModifiers:', flags)
			if is_nil(chars) { return none }
			return objc_utf8_string(chars)
		}
		if cp >= 0xf700 && cp <= 0xf8ff { return none }
	}
	return text
}

fn input_key_action(view ObjId, event ObjId, translation_event ObjId, action input.KeyAction, text ?string, composing bool) bool {
	if g_input_callbacks.key == unsafe { nil } {
		dispatch_key(view, event, action)
		return false
	}
	mut encoded := ?string(none)
	if value := text { if value.len > 0 && value[0] >= 0x20 { encoded = value } }
	return g_input_callbacks.key(view_userdata(view), voidptr(event), voidptr(translation_event), action, encoded, composing)
}

fn input_has_marked(self ObjId, _cmd Sel) bool { return has_marked_text(self) }
fn input_marked_range(self ObjId, _cmd Sel) C.witty_macos_range {
	return C.witty_macos_range{length: uint(msg_u64(input_view_state(self).marked, 'length'))}
}
fn input_selected_range(self ObjId, _cmd Sel) C.witty_macos_range {
	if selection := input_selection(self) { return C.witty_macos_range{location: selection.offset_start, length: selection.offset_len} }
	return C.witty_macos_range{}
}
fn input_selection(view ObjId) ?NativeText {
	if g_input_callbacks.selection == unsafe { nil } || is_nil(view_userdata(view)) { return none }
	return g_input_callbacks.selection(view_userdata(view))
}
fn input_set_marked(self ObjId, _cmd Sel, text ObjId, _selection C.witty_macos_range, _replacement C.witty_macos_range) {
	mut state := input_view_state(self)
	mut marked := nil_obj()
	if msg_bool1(text, 'isKindOfClass:', get_class('NSAttributedString')) {
		marked = msg_id1(alloc('NSMutableAttributedString'), 'initWithAttributedString:', text)
	} else if msg_bool1(text, 'isKindOfClass:', get_class('NSString')) {
		marked = msg_id1(alloc('NSMutableAttributedString'), 'initWithString:', text)
	} else { eprintln('unknown marked text') }
	if !is_nil(marked) { msg_void(state.marked, 'release'); state.marked = marked }
	if !state.accumulating { input_sync_preedit(self, true) }
}
fn input_unmark(self ObjId, _cmd Sel) {
	if has_marked_text(self) {
		msg_void1(msg_id(input_view_state(self).marked, 'mutableString'), 'setString:', nsstring(''))
		input_sync_preedit(self, true)
	}
}
fn input_marked_attributes(_self ObjId, _cmd Sel) ObjId { return msg_id(get_class('NSArray'), 'array') }
fn input_attributed_substring(self ObjId, _cmd Sel, range C.witty_macos_range, _actual &C.witty_macos_range) ObjId {
	if range.length == 0 { return nil_obj() }
	if selection := input_selection(self) { return input_attributed_text(self, selection.text) }
	return nil_obj()
}
fn input_attributed_text(view ObjId, text string) ObjId {
	mut attributes := msg_id(get_class('NSDictionary'), 'dictionary')
	if g_input_callbacks.font != unsafe { nil } && !is_nil(view_userdata(view)) {
		font := g_input_callbacks.font(view_userdata(view))
		if !is_nil(font) {
			attributes = msg_id2(get_class('NSDictionary'), 'dictionaryWithObject:forKey:', ObjId(font), nsstring('NSFont'))
			cf_release(font)
		}
	}
	return msg_id(msg_id2(alloc('NSAttributedString'), 'initWithString:attributes:', nsstring(text), attributes), 'autorelease')
}
fn input_character_index(_self ObjId, _cmd Sel, _point ObjCPoint) uint { return 0 }
fn input_first_rect(self ObjId, _cmd Sel, range C.witty_macos_range, _actual &C.witty_macos_range) ObjCRect {
	frame := msg_rect(self, 'frame')
	if g_input_callbacks.ime_rect == unsafe { nil } || is_nil(view_userdata(self)) { return objc_rect(frame.x, frame.y, 0, 0) }
	mut rect := g_input_callbacks.ime_rect(view_userdata(self))
	selected := input_selected_range(self, nil_obj())
	if range.length > 0 && (range.location != selected.location || range.length != selected.length) {
		if selection := input_selection(self) {
			rect.x = selection.tl_px_x - 2; rect.y = selection.tl_px_y + 2
			rect.width = rect.cell_width; rect.height = rect.cell_height
		}
	}
	if range.length == 0 && rect.width > 0 { rect.width = 0; rect.x += rect.cell_width * f64(range.location + range.length) }
	view_rect := objc_rect(rect.x, frame.height - rect.y, rect.width, if rect.height > rect.cell_height { rect.height } else { rect.cell_height })
	window_rect := C.witty_macos_msg_rect_rect_obj(voidptr(self), voidptr(sel('convertRect:toView:')), view_rect, unsafe { nil })
	window := msg_id(self, 'window')
	if is_nil(window) { return window_rect }
	return C.witty_macos_msg_rect_rect(voidptr(window), voidptr(sel('convertRectToScreen:')), window_rect)
}
fn input_plain_text(value ObjId) ?string {
	if msg_bool1(value, 'isKindOfClass:', get_class('NSAttributedString')) { return objc_utf8_string(msg_id(value, 'string')) }
	if msg_bool1(value, 'isKindOfClass:', get_class('NSString')) { return objc_utf8_string(value) }
	return none
}
fn input_insert_text(self ObjId, _cmd Sel, value ObjId, _replacement C.witty_macos_range) {
	if is_nil(msg_id(shared_app(), 'currentEvent')) || is_nil(view_userdata(self)) { return }
	text := input_plain_text(value) or { return }
	input_unmark(self, nil_obj())
	mut state := input_view_state(self)
	if state.accumulating { state.accumulator << text; return }
	if g_input_callbacks.text != unsafe { nil } { g_input_callbacks.text(view_userdata(self), text) }
}
fn input_do_command(self ObjId, _cmd Sel, selector Sel) {
	mut state := input_view_state(self)
	if last := state.last_perform {
		current := msg_id(shared_app(), 'currentEvent')
		if !is_nil(current) && last == msg_f64(current, 'timestamp') { msg_void1(shared_app(), 'sendEvent:', current); return }
	}
	name := unsafe { C.sel_getName(voidptr(selector)).vstring() }
	if g_input_callbacks.binding_action != unsafe { nil } && !is_nil(view_userdata(self)) {
		match name {
			'moveToBeginningOfDocument:' { g_input_callbacks.binding_action(view_userdata(self), 'scroll_to_top') }
			'moveToEndOfDocument:' { g_input_callbacks.binding_action(view_userdata(self), 'scroll_to_bottom') }
			else {}
		}
	}
	println('SEL: ${name}')
}
fn input_perform_key_equivalent(self ObjId, _cmd Sel, event ObjId) bool {
	if msg_u64(event, 'type') != 10 { return false }
	window := msg_id(self, 'window')
	if is_nil(window) || msg_id(window, 'firstResponder') != self { return false }
	mut state := input_view_state(self)
	if g_input_callbacks.binding != unsafe { nil } && !is_nil(view_userdata(self)) {
		if flags := g_input_callbacks.binding(view_userdata(self), voidptr(event), objc_utf8_string(msg_id(event, 'characters'))) {
			if !state.key_sequence && !state.key_tables && flags & (2 | 8) == 0 && flags & 1 != 0 {
				menu := msg_id(shared_app(), 'mainMenu')
				if !is_nil(menu) && msg_bool1(menu, 'performKeyEquivalent:', event) { return true }
			}
			input_key_down(self, event)
			return true
		}
	}
	flags := msg_u64(event, 'modifierFlags')
	mut equivalent := ''
	match objc_utf8_string(msg_id(event, 'charactersIgnoringModifiers')) {
		'\r' { if flags & ns_event_modifier_flag_control == 0 { return false }; equivalent = '\r' }
		'/' { if flags & ns_event_modifier_flag_control == 0 || flags & (ns_event_modifier_flag_shift | ns_event_modifier_flag_command | ns_event_modifier_flag_option) != 0 { return false }; equivalent = '_' }
		else {
			timestamp := msg_f64(event, 'timestamp')
			if timestamp == 0 { return false }
			if flags & (ns_event_modifier_flag_command | ns_event_modifier_flag_control) == 0 { state.last_perform = none; return false }
			mut redispatch := false
			if last := state.last_perform { state.last_perform = none; redispatch = last == timestamp }
			if !redispatch { state.last_perform = timestamp; return false }
			equivalent = objc_utf8_string(msg_id(event, 'characters'))
		}
	}
	created := ObjId(C.witty_macos_key_event(voidptr(event), flags, voidptr(nsstring(equivalent)), voidptr(nsstring(equivalent))))
	if is_nil(created) { panic('NSEvent.keyEvent returned nil') }
	input_key_down(self, created)
	return true
}
fn install_command_release_monitor() {
	if is_nil(g_key_release_monitor) { g_key_release_monitor = ObjId(C.witty_macos_monitor_key_releases(voidptr(input_command_release))) }
}
fn input_command_release(event voidptr) voidptr {
	if msg_u64(ObjId(event), 'modifierFlags') & ns_event_modifier_flag_command == 0 { return event }
	window := msg_id(shared_app(), 'keyWindow')
	view := msg_id(window, 'firstResponder')
	if is_nil(view) || !msg_bool1(view, 'isKindOfClass:', get_class('VTTerminalView')) { return event }
	vt_view_key_up(view, nil_obj(), ObjId(event))
	return unsafe { nil }
}
