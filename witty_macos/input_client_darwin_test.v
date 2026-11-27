@[has_globals]
module witty_macos

import input

#insert "@VMODROOT/witty_macos/input_client_test_bridge.h"

fn C.witty_input_test_event(type_ u64, flags u64, timestamp f64, keycode u16, chars &char) voidptr
fn C.witty_input_test_set_marked(view voidptr, text voidptr)
fn C.witty_input_test_insert(view voidptr, text &char)
fn C.witty_input_test_swizzle_current_event(implementation voidptr) voidptr

@[heap]
struct InputClientProbe {
mut:
	preedits []?string
	texts []string
	keys []ProbeKey
	translation int = -1
	interpret int
}
struct ProbeKey {
	original voidptr
	translated voidptr
	text ?string
	composing bool
}
__global (g_probe_current_event ObjId)
fn probe_current_event(_self ObjId, _cmd Sel) ObjId { return g_probe_current_event }
fn probe_preedit(userdata voidptr, text ?string) { mut p := unsafe { &InputClientProbe(userdata) }; p.preedits << text }
fn probe_text(userdata voidptr, text string) { mut p := unsafe { &InputClientProbe(userdata) }; p.texts << text }
fn probe_translate(userdata voidptr, mods int) int { p := unsafe { &InputClientProbe(userdata) }; return if p.translation < 0 { mods } else { p.translation } }
fn probe_key(userdata voidptr, original voidptr, translated voidptr, _action input.KeyAction, text ?string, composing bool) bool {
	mut p := unsafe { &InputClientProbe(userdata) }; p.keys << ProbeKey{original: original, translated: translated, text: text, composing: composing}; return true
}
fn probe_selection(_userdata voidptr) ?NativeText { return NativeText{text: 'selected', offset_start: 3, offset_len: 8, tl_px_x: 12, tl_px_y: 24} }
fn probe_ime(_userdata voidptr) NativeImeRect { return NativeImeRect{x: 40, y: 50, width: 10, height: 18, cell_width: 10, cell_height: 20} }
fn probe_interpret(self ObjId, _cmd Sel, _events ObjId) {
	mut p := unsafe { &InputClientProbe(view_userdata(self)) }
	match p.interpret {
		1 { C.witty_input_test_set_marked(voidptr(self), voidptr(nsstring('候補'))) }
		2 { input_unmark(self, nil_obj()) }
		3 { C.witty_input_test_insert(voidptr(self), cstr('한')) }
		else {}
	}
}
fn probe_view(mut probe InputClientProbe) ObjId {
	register_classes()
	mut cls := get_class('VTInputProbeView')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('VTTerminalView'), cstr('VTInputProbeView'), 0)
		add_method(cls, 'interpretKeyEvents:', voidptr(probe_interpret), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	view := msg_id_rect(msg_id(cls, 'alloc'), 'initWithFrame:', objc_rect(0, 0, 300, 200))
	view_set_userdata(voidptr(view), voidptr(&probe))
	set_input_client_callbacks(InputClientCallbacks{translation_mods: probe_translate, key: probe_key, preedit: probe_preedit, text: probe_text, selection: probe_selection, ime_rect: probe_ime})
	return view
}
fn test_native_input_client_selectors_marked_text_and_candidates() {
	mut probe := &InputClientProbe{}
	view := probe_view(mut probe)
	defer { msg_void(view, 'release'); set_input_client_callbacks(InputClientCallbacks{}) }
	for selector in ['hasMarkedText', 'selectedRange', 'insertText:replacementRange:', 'performKeyEquivalent:'] { assert msg_bool1(view, 'respondsToSelector:', sel(selector)) }
	C.witty_input_test_set_marked(voidptr(view), voidptr(nsstring('候補')))
	assert msg_bool(view, 'hasMarkedText')
	assert C.witty_macos_msg_range(voidptr(view), voidptr(sel('markedRange'))).length == 2
	assert probe.preedits.last()? == '候補'
	selected := input_selected_range(view, nil_obj())
	assert selected.location == 3 && selected.length == 8
	quicklook := input_first_rect(view, nil_obj(), C.witty_macos_range{location: 0, length: 1}, unsafe { nil })
	assert quicklook.x == 10
	assert quicklook.y == 174
	assert quicklook.height == 20
	dictation := input_first_rect(view, nil_obj(), C.witty_macos_range{location: 2, length: 0}, unsafe { nil })
	assert dictation.width == 0 && dictation.x == 60
	input_unmark(view, nil_obj())
	assert !msg_bool(view, 'hasMarkedText') && probe.preedits.last() == none
}
fn test_key_composition_preserves_event_identity_and_cancellation() {
	mut probe := &InputClientProbe{interpret: 1}
	view := probe_view(mut probe)
	defer { msg_void(view, 'release'); set_input_client_callbacks(InputClientCallbacks{}) }
	event := ObjId(C.witty_input_test_event(10, ns_event_modifier_flag_option, 12, 0, cstr('a')))
	input_key_down(view, event)
	assert probe.keys.last().original == voidptr(event)
	assert probe.keys.last().translated == voidptr(event)
	assert probe.keys.last().composing
	probe.interpret = 2
	input_key_down(view, event)
	assert !has_marked_text(view)
	assert probe.keys.last().composing
	probe.translation = 0
	probe.interpret = 0
	input_key_down(view, event)
	assert probe.keys.last().translated != voidptr(event)
	assert !probe.keys.last().composing
}
fn test_committed_composition_and_external_dictation_use_distinct_paths() {
	mut probe := &InputClientProbe{interpret: 3}
	view := probe_view(mut probe)
	defer { msg_void(view, 'release'); set_input_client_callbacks(InputClientCallbacks{}) }
	shared_app()
	event := ObjId(C.witty_input_test_event(10, 0, 13, 0, cstr('a')))
	g_probe_current_event = event
	original := C.witty_input_test_swizzle_current_event(voidptr(probe_current_event))
	defer { C.witty_input_test_swizzle_current_event(original); g_probe_current_event = nil_obj() }
	input_key_down(view, event)
	assert probe.keys.last().text? == '한'
	assert !probe.keys.last().composing && probe.texts.len == 0
	C.witty_input_test_insert(voidptr(view), cstr('dictation'))
	assert probe.texts == ['dictation']
}
