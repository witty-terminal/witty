@[has_globals]
module witty_macos

// SurfaceView_AppKit's NSServicesMenuRequestor, NSDraggingDestination and
// accessibility extensions, including its 500 ms CachedValue screen snapshot.

#flag darwin -licucore

fn C.ubrk_open(type_ int, locale &char, text &u16, length int, status &int) voidptr
fn C.ubrk_first(iterator voidptr) int
fn C.ubrk_next(iterator voidptr) int
fn C.ubrk_close(iterator voidptr)
fn C.witty_macos_copy_characters(text voidptr, output &u16, length uint)
fn C.witty_macos_msg_super_id2(obj voidptr, selector voidptr, a voidptr, b voidptr) voidptr
fn C.witty_macos_cache_timer(duration u64, callback voidptr, context voidptr) voidptr
fn C.witty_macos_cancel_timer(timer voidptr)

@[heap]
struct TerminalDropTask {
	view ObjId
	text string
}
__global (g_terminal_drop_tasks map[u64]&TerminalDropTask)

fn register_terminal_interfaces(cls ObjId) {
	for name in ['NSServicesMenuRequestor', 'NSDraggingDestination'] {
		proto := get_protocol(name)
		if !is_nil(proto) { C.macos_class_add_protocol(cls, proto) }
	}
	add_method(cls, 'validRequestorForSendType:returnType:', voidptr(terminal_valid_requestor), '@@:@@')
	add_method(cls, 'writeSelectionToPasteboard:types:', voidptr(terminal_write_selection), 'B@:@@')
	add_method(cls, 'readSelectionFromPasteboard:', voidptr(terminal_read_selection), 'B@:@')
	add_method(cls, 'draggingEntered:', voidptr(terminal_dragging_entered), 'Q@:@')
	add_method(cls, 'performDragOperation:', voidptr(terminal_perform_drop), 'B@:@')
	add_method(cls, 'isAccessibilityElement', voidptr(terminal_accessible), 'B@:')
	add_method(cls, 'accessibilityRole', voidptr(terminal_accessibility_role), '@@:')
	add_method(cls, 'accessibilityHelp', voidptr(terminal_accessibility_help), '@@:')
	add_method(cls, 'accessibilityValue', voidptr(terminal_accessibility_value), '@@:')
	add_method(cls, 'accessibilitySelectedTextRange', voidptr(input_selected_range), '{_NSRange=QQ}@:')
	add_method(cls, 'accessibilitySelectedText', voidptr(terminal_accessibility_selected), '@@:')
	add_method(cls, 'accessibilityNumberOfCharacters', voidptr(terminal_accessibility_count), 'q@:')
	add_method(cls, 'accessibilityVisibleCharacterRange', voidptr(terminal_accessibility_visible), '{_NSRange=QQ}@:')
	add_method(cls, 'accessibilityLineForIndex:', voidptr(terminal_accessibility_line), 'q@:q')
	add_method(cls, 'accessibilityStringForRange:', voidptr(terminal_accessibility_string), '@@:{_NSRange=QQ}')
	add_method(cls, 'accessibilityAttributedStringForRange:', voidptr(terminal_accessibility_attributed), '@@:{_NSRange=QQ}')
}

fn setup_terminal_interfaces(view ObjId) {
	types := msg_id(msg_id(alloc('NSMutableArray'), 'init'), 'autorelease')
	for name in ['public.utf8-plain-text', 'public.file-url', 'public.url'] { msg_void1(types, 'addObject:', nsstring(name)) }
	msg_void1(view, 'registerForDraggedTypes:', types)
}

fn terminal_service_type_supported(value ObjId) bool {
	return is_nil(value) || objc_utf8_string(value) == 'public.utf8-plain-text'
}
fn terminal_valid_requestor(self ObjId, _cmd Sel, send_type ObjId, return_type ObjId) ObjId {
	if terminal_service_type_supported(send_type) && terminal_service_type_supported(return_type) {
		if is_nil(send_type) { return self }
		if g_input_callbacks.has_selection != unsafe { nil } && !is_nil(view_userdata(self)) && g_input_callbacks.has_selection(view_userdata(self)) { return self }
	}
	return ObjId(C.witty_macos_msg_super_id2(voidptr(self), voidptr(sel('validRequestorForSendType:returnType:')), voidptr(send_type), voidptr(return_type)))
}
fn terminal_write_selection(self ObjId, _cmd Sel, pasteboard ObjId, _types ObjId) bool {
	selection := input_selection(self) or { return false }
	msg_id2(pasteboard, 'declareTypes:owner:', msg_id1(get_class('NSArray'), 'arrayWithObject:', nsstring('public.utf8-plain-text')), nil_obj())
	msg_bool2(pasteboard, 'setString:forType:', nsstring(selection.text), nsstring('public.utf8-plain-text'))
	return true
}
fn terminal_read_selection(self ObjId, _cmd Sel, pasteboard ObjId) bool {
	text := opinionated_pasteboard_contents(pasteboard) or { return false }
	if g_input_callbacks.text != unsafe { nil } && !is_nil(view_userdata(self)) { g_input_callbacks.text(view_userdata(self), text) }
	return true
}

// Ghostty.Shell.escape intentionally replaces backslash before the remaining
// characters; changing this order double-escapes later inserted backslashes.
pub fn terminal_shell_escape(text string) string {
	mut result := text
	for character in '\\ ()[]{}<>"\'`!#$&;|*?\t' { result = result.replace(character.ascii_str(), '\\' + character.ascii_str()) }
	return result
}
fn pasteboard_urls(pasteboard ObjId) ObjId {
	classes := msg_id1(get_class('NSArray'), 'arrayWithObject:', get_class('NSURL'))
	return msg_id2(pasteboard, 'readObjectsForClasses:options:', classes, nil_obj())
}
fn opinionated_pasteboard_contents(pasteboard ObjId) ?string {
	urls := pasteboard_urls(pasteboard)
	count := int(msg_u64(urls, 'count'))
	if count > 0 {
		mut paths := []string{cap: count}
		for i in 0 .. count {
			url := msg_id_u64(urls, 'objectAtIndex:', u64(i))
			paths << if msg_bool(url, 'isFileURL') { terminal_shell_escape(objc_utf8_string(msg_id(url, 'path'))) } else { objc_utf8_string(msg_id(url, 'absoluteString')) }
		}
		return paths.join(' ')
	}
	str := msg_id1(pasteboard, 'stringForType:', nsstring('public.utf8-plain-text'))
	if is_nil(str) { return none }
	return objc_utf8_string(str)
}
fn terminal_dragging_entered(_self ObjId, _cmd Sel, sender ObjId) u64 {
	types := msg_id(msg_id(sender, 'draggingPasteboard'), 'types')
	for i in 0 .. int(msg_u64(types, 'count')) {
		if objc_utf8_string(msg_id_u64(types, 'objectAtIndex:', u64(i))) in ['public.utf8-plain-text', 'public.file-url', 'public.url'] { return 1 }
	}
	return 0
}
fn terminal_drop_contents(pasteboard ObjId) ?string {
	url := msg_id1(pasteboard, 'stringForType:', nsstring('public.url'))
	if !is_nil(url) { return terminal_shell_escape(objc_utf8_string(url)) }
	urls := pasteboard_urls(pasteboard)
	count := int(msg_u64(urls, 'count'))
	if count > 0 {
		mut paths := []string{cap: count}
		for i in 0 .. count { paths << terminal_shell_escape(objc_utf8_string(msg_id(msg_id_u64(urls, 'objectAtIndex:', u64(i)), 'path'))) }
		return paths.join(' ')
	}
	text := msg_id1(pasteboard, 'stringForType:', nsstring('public.utf8-plain-text'))
	if is_nil(text) { return none }
	return objc_utf8_string(text)
}
fn terminal_perform_drop(self ObjId, _cmd Sel, sender ObjId) bool {
	content := terminal_drop_contents(msg_id(sender, 'draggingPasteboard')) or { return false }
	task := &TerminalDropTask{view: msg_id(self, 'retain'), text: content}
	g_terminal_drop_tasks[u64(task)] = task
	dispatch_main(terminal_drop_main, voidptr(task))
	return true
}
fn terminal_drop_main(raw voidptr) {
	task := unsafe { &TerminalDropTask(raw) }
	g_terminal_drop_tasks.delete(u64(raw))
	input_insert_text(task.view, nil_obj(), nsstring(task.text), C.witty_macos_range{})
	msg_void(task.view, 'release')
}

fn input_cancel_screen_cache(mut state InputViewState) {
	if state.cache_timer != unsafe { nil } { C.witty_macos_cancel_timer(state.cache_timer); state.cache_timer = unsafe { nil } }
	state.screen_contents = none
}
fn terminal_cache_expired(raw voidptr) {
	mut state := unsafe { &InputViewState(raw) }
	state.screen_contents = none
	state.cache_timer = unsafe { nil }
}
fn terminal_screen_contents(view ObjId) string {
	mut state := input_view_state(view)
	if contents := state.screen_contents { return contents }
	text := if g_input_callbacks.screen_text != unsafe { nil } && !is_nil(view_userdata(view)) { g_input_callbacks.screen_text(view_userdata(view)) } else { '' }
	state.screen_contents = text
	state.cache_timer = C.witty_macos_cache_timer(500_000_000, voidptr(terminal_cache_expired), voidptr(state))
	return text
}
fn terminal_accessible(_self ObjId, _cmd Sel) bool { return true }
fn terminal_accessibility_role(_self ObjId, _cmd Sel) ObjId { return nsstring('AXTextArea') }
fn terminal_accessibility_help(_self ObjId, _cmd Sel) ObjId { return nsstring('Terminal content area') }
fn terminal_accessibility_value(self ObjId, _cmd Sel) ObjId { return nsstring(terminal_screen_contents(self)) }
fn terminal_accessibility_selected(self ObjId, _cmd Sel) ObjId {
	if selection := input_selection(self) { if selection.text.len > 0 { return nsstring(selection.text) } }
	return nil_obj()
}
// Swift String.count/prefix use extended grapheme clusters (UAX #29). The
// legacy NSString composed-character API differs for CRLF and Prepend; use
// the macOS Unicode character-break iterator for those standard-library ops.
fn native_character_prefix(text ObjId, count int) uint {
	if count < 0 { panic('String.prefix requires a nonnegative length') }
	length := int(msg_u64(text, 'length'))
	characters := []u16{len: length}
	C.witty_macos_copy_characters(voidptr(text), characters.data, uint(length))
	mut status := 0
	iterator := C.ubrk_open(0, unsafe { nil }, characters.data, length, &status)
	if iterator == unsafe { nil } || status > 0 { panic('Unicode character-break iterator initialization failed') }
	defer { C.ubrk_close(iterator) }
	C.ubrk_first(iterator)
	mut offset := 0
	mut n := int(0)
	for n < count {
		next := C.ubrk_next(iterator)
		if next < 0 { break }
		offset = next
		n++
	}
	return uint(offset)
}
fn native_character_count(text ObjId) int {
	length := int(msg_u64(text, 'length'))
	characters := []u16{len: length}
	C.witty_macos_copy_characters(voidptr(text), characters.data, uint(length))
	mut status := 0
	iterator := C.ubrk_open(0, unsafe { nil }, characters.data, length, &status)
	if iterator == unsafe { nil } || status > 0 { panic('Unicode character-break iterator initialization failed') }
	defer { C.ubrk_close(iterator) }
	C.ubrk_first(iterator)
	mut count := int(0)
	for C.ubrk_next(iterator) >= 0 { count++ }
	return count
}
fn terminal_accessibility_count(self ObjId, _cmd Sel) int { return native_character_count(nsstring(terminal_screen_contents(self))) }
fn terminal_accessibility_visible(self ObjId, _cmd Sel) C.witty_macos_range { return C.witty_macos_range{length: uint(terminal_accessibility_count(self, nil_obj()))} }
fn terminal_accessibility_line(self ObjId, _cmd Sel, index int) int {
	text := nsstring(terminal_screen_contents(self))
	length := native_character_prefix(text, index)
	prefix := ObjId(C.witty_macos_msg_id_range(voidptr(text), voidptr(sel('substringWithRange:')), C.witty_macos_range{length: length}))
	mut lines := int(0)
	for scalar in objc_utf8_string(prefix).runes() { if scalar in [`\n`, `\r`, `\u0085`, `\u2028`, `\u2029`, `\v`, `\f`] { lines++ } }
	return lines
}
struct TextRange {
	location uint
	length uint
}

fn native_text_range(text ObjId, range C.witty_macos_range) ?TextRange {
	length := uint(msg_u64(text, 'length'))
	if range.location > length || range.length > length - range.location { return none }
	// Swift Range(NSRange, in: String) accepts UTF-16 positions within a
	// surrogate pair. String(substring) rounds both endpoints down to the
	// scalar boundary. Preserve that behavior instead of NSString's isolated
	// surrogate substring; verified against the original Swift operations.
	mut start := uint(0)
	mut end := uint(0)
	mut offset := uint(0)
	for scalar in objc_utf8_string(text).runes() {
		offset += if scalar > 0xffff { uint(2) } else { uint(1) }
		if offset <= range.location { start = offset }
		if offset <= range.location + range.length { end = offset }
	}
	return TextRange{location: start, length: end - start}
}
fn terminal_accessibility_string(self ObjId, _cmd Sel, range C.witty_macos_range) ObjId {
	text := nsstring(terminal_screen_contents(self))
	normalized := native_text_range(text, range) or { return nil_obj() }
	return ObjId(C.witty_macos_msg_id_range(voidptr(text), voidptr(sel('substringWithRange:')), C.witty_macos_range{location: normalized.location, length: normalized.length}))
}
fn terminal_accessibility_attributed(self ObjId, _cmd Sel, range C.witty_macos_range) ObjId {
	if is_nil(view_userdata(self)) { return nil_obj() }
	plain := terminal_accessibility_string(self, nil_obj(), range)
	if is_nil(plain) { return nil_obj() }
	return input_attributed_text(self, objc_utf8_string(plain))
}
