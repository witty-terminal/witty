@[has_globals]
module witty_macos

#insert "@VMODROOT/witty_macos/input_client_test_bridge.h"
fn C.witty_input_test_run_main_for(seconds f64)
fn C.witty_input_test_pasteboard() voidptr

@[heap]
struct TerminalInterfaceProbe {
mut:
	reads int
	has_selection bool = true
	texts []string
	content string = 'e\u0301🙂\r\n'
}
fn interface_screen(raw voidptr) string { mut p := unsafe { &TerminalInterfaceProbe(raw) }; p.reads++; return p.content }
fn interface_selection(_raw voidptr) ?NativeText { return NativeText{text: 'selected', offset_start: 3, offset_len: 8} }
fn interface_has_selection(raw voidptr) bool { p := unsafe { &TerminalInterfaceProbe(raw) }; return p.has_selection }
fn interface_text(raw voidptr, text string) { mut p := unsafe { &TerminalInterfaceProbe(raw) }; p.texts << text }
fn interface_view(mut probe TerminalInterfaceProbe) ObjId {
	register_classes()
	view := msg_id_rect(alloc('VTTerminalView'), 'initWithFrame:', objc_rect(0, 0, 300, 200))
	view_set_userdata(voidptr(view), voidptr(&probe))
	setup_terminal_interfaces(view)
	set_input_client_callbacks(InputClientCallbacks{screen_text: interface_screen, selection: interface_selection, has_selection: interface_has_selection, text: interface_text})
	return view
}
fn test_accessibility_cache_unicode_ranges_and_lines_match_swift() {
	mut probe := &TerminalInterfaceProbe{}
	view := interface_view(mut probe)
	defer { msg_void(view, 'release'); set_input_client_callbacks(InputClientCallbacks{}) }
	assert msg_bool(view, 'isAccessibilityElement')
	assert objc_utf8_string(msg_id(view, 'accessibilityRole')) == 'AXTextArea'
	assert terminal_accessibility_count(view, nil_obj()) == 3
	assert terminal_accessibility_visible(view, nil_obj()).length == 3
	assert terminal_accessibility_line(view, nil_obj(), 2) == 0
	assert terminal_accessibility_line(view, nil_obj(), 3) == 2
	assert probe.reads == 1
	// Swift Range(NSRange,in:) permits scalar and half-surrogate endpoints;
	// String(substring) rounds endpoints inside a surrogate down.
	assert objc_utf8_string(terminal_accessibility_string(view, nil_obj(), C.witty_macos_range{location: 0, length: 1})) == 'e'
	assert objc_utf8_string(terminal_accessibility_string(view, nil_obj(), C.witty_macos_range{location: 1, length: 1})) == '\u0301'
	assert objc_utf8_string(terminal_accessibility_string(view, nil_obj(), C.witty_macos_range{location: 2, length: 1})) == ''
	assert objc_utf8_string(terminal_accessibility_string(view, nil_obj(), C.witty_macos_range{location: 3, length: 1})) == '🙂'
	assert is_nil(terminal_accessibility_string(view, nil_obj(), C.witty_macos_range{location: 5, length: 2}))
	assert objc_utf8_string(msg_id(view, 'accessibilitySelectedText')) == 'selected'
	probe.content = 'fresh'
	assert objc_utf8_string(msg_id(view, 'accessibilityValue')) == 'e\u0301🙂\r\n'
	C.witty_input_test_run_main_for(0.55)
	assert objc_utf8_string(msg_id(view, 'accessibilityValue')) == 'fresh'
	assert probe.reads == 2
}
fn test_services_selection_and_drop_priority_and_shell_escaping() {
	mut probe := &TerminalInterfaceProbe{}
	view := interface_view(mut probe)
	defer { msg_void(view, 'release'); set_input_client_callbacks(InputClientCallbacks{}) }
	assert terminal_valid_requestor(view, nil_obj(), nil_obj(), nsstring('public.utf8-plain-text')) == view
	assert terminal_valid_requestor(view, nil_obj(), nsstring('public.utf8-plain-text'), nil_obj()) == view
	probe.has_selection = false
	assert terminal_valid_requestor(view, nil_obj(), nsstring('public.utf8-plain-text'), nil_obj()) != view
	assert terminal_valid_requestor(view, nil_obj(), nil_obj(), nsstring('public.png')) != view
	pasteboard := ObjId(C.witty_input_test_pasteboard())
	assert terminal_write_selection(view, nil_obj(), pasteboard, nil_obj())
	assert objc_utf8_string(msg_id1(pasteboard, 'stringForType:', nsstring('public.utf8-plain-text'))) == 'selected'
	assert terminal_read_selection(view, nil_obj(), pasteboard)
	assert probe.texts == ['selected']
	msg_void(pasteboard, 'clearContents')
	msg_bool2(pasteboard, 'setString:forType:', nsstring('echo a & b'), nsstring('public.utf8-plain-text'))
	assert terminal_drop_contents(pasteboard)? == 'echo a & b'
	msg_bool2(pasteboard, 'setString:forType:', nsstring('https://example.test/a?q=1&b=2'), nsstring('public.url'))
	assert terminal_drop_contents(pasteboard)? == 'https://example.test/a\\?q=1\\&b=2'
	assert terminal_shell_escape('a\\b c\td$e') == 'a\\\\b\\ c\\\td\\$e'
	msg_void(pasteboard, 'clearContents')
	urls := msg_id(msg_id(alloc('NSMutableArray'), 'init'), 'autorelease')
	for path in ['/tmp/a b', '/tmp/c$d'] { msg_void1(urls, 'addObject:', msg_id1(get_class('NSURL'), 'fileURLWithPath:', nsstring(path))) }
	assert msg_bool1(pasteboard, 'writeObjects:', urls)
	assert opinionated_pasteboard_contents(pasteboard)? == '/tmp/a\\ b /tmp/c\\$d'
	assert terminal_drop_contents(pasteboard)? == '/tmp/a\\ b /tmp/c\\$d'
}
fn test_accessibility_cache_timer_cancels_when_view_is_destroyed() {
	mut probe := &TerminalInterfaceProbe{}
	view := interface_view(mut probe)
	terminal_screen_contents(view)
	assert u64(view) in g_input_views
	msg_void(view, 'release')
	assert u64(view) !in g_input_views
	C.witty_input_test_run_main_for(0.55)
	set_input_client_callbacks(InputClientCallbacks{})
	assert probe.reads == 1
}

fn test_swift_extended_grapheme_fixtures_match_native_unicode_iterator() {
	for text, expected in {
		'\r\n': 1
		'🇦🇺🇦🇺': 2
		'👨‍👩‍👧‍👦': 1
		'\u0600a': 1
		'\u0915\u094d\u0937': 1
		'👩🏽': 1
		'a\u200d👩': 2
		'e\u0301': 1
		'👩‍💻': 1
	} {
		assert native_character_count(nsstring(text)) == expected
		assert native_character_prefix(nsstring(text), expected) == uint(msg_u64(nsstring(text), 'length'))
	}
}
