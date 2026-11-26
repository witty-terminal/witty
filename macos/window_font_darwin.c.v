@[has_globals]
module macos

#insert "@VMODROOT/macos/window_font_abi.h"
fn C.witty_window_font_super_set_title(window ObjId, title ObjId)

__global native_title_font_key = u8(0)

fn window_title_font(window ObjId) ObjId {
	return C.macos_get_associated_object(window, voidptr(&native_title_font_key))
}

// TerminalWindow.titlebarContainer searches from the absolute view root,
// including the separate AppKit fullscreen toolbar window owned by this window.
fn window_font_view_root(view ObjId) ObjId {
	mut root := view
	for !is_nil(msg_id(root, 'superview')) { root = msg_id(root, 'superview') }
	return root
}

fn window_font_titlebar_container(window ObjId) ObjId {
	if msg_u64(window, 'styleMask') & u64(1 << 14) == 0 {
		return first_descendant(window_font_view_root(msg_id(window, 'contentView')), 'NSTitlebarContainerView')
	}
	windows := msg_id(shared_app(), 'windows')
	for i in 0 .. int(msg_u64(windows, 'count')) {
		candidate := msg_id_u64(windows, 'objectAtIndex:', u64(i))
		if objc_utf8_string(msg_id(candidate, 'className')) != 'NSToolbarFullScreenWindow' { continue }
		if msg_id(candidate, 'parentWindow') != window { continue }
		return first_descendant(window_font_view_root(msg_id(candidate, 'contentView')), 'NSTitlebarContainerView')
	}
	return nil_obj()
}

fn window_font_title_fields(window ObjId) []ObjId {
	titlebar := first_descendant(window_font_titlebar_container(window), 'NSTitlebarView')
	tahoe := if data := native_window_data(window) { native_uses_tahoe_titlebar(data) } else { false }
	if !tahoe {
		field := first_descendant(titlebar, 'NSTextField')
		return if is_nil(field) { []ObjId{} } else { [field] }
	}
	children := msg_id(titlebar, 'subviews')
	mut fields := []ObjId{}
	// A nested text field can belong to AppKit's tab strip or a toolbar item.
	for i in 0 .. int(msg_u64(children, 'count')) {
		child := msg_id_u64(children, 'objectAtIndex:', u64(i))
		if objc_utf8_string(msg_id(child, 'className')) == 'NSTextField' {
			fields << child
		}
	}
	return fields
}

fn window_font_single_line(window ObjId) {
	tabs := msg_id(window, 'tabbedWindows')
	single_line := msg_u64(tabs, 'count') <= 1
	for field in window_font_title_fields(window) {
		msg_void_bool(field, 'setUsesSingleLineMode:', single_line)
	}
}

fn window_font_attributed_title(window ObjId) ObjId {
	font := window_title_font(window)
	if is_nil(font) { return nil_obj() }
	attributes := new_obj('NSMutableDictionary')
	defer { msg_void(attributes, 'release') }
	msg_void2(attributes, 'setObject:forKey:', font, nsstring('NSFont'))
	msg_void2(attributes, 'setObject:forKey:', msg_id(get_class('NSColor'), if msg_bool(window, 'isKeyWindow') { 'labelColor' } else { 'secondaryLabelColor' }), nsstring('NSColor'))
	return msg_id(msg_id2(alloc('NSAttributedString'), 'initWithString:attributes:', msg_id(window, 'title'), attributes), 'autorelease')
}

fn refresh_native_window_title_attributes(window ObjId) {
	msg_void1(msg_id(window, 'tab'), 'setAttributedTitle:', window_font_attributed_title(window))
}

fn window_font_title_changed(self ObjId, _cmd Sel, title ObjId) {
	C.witty_window_font_super_set_title(self, title)
	refresh_native_window_title_attributes(self)
	window_font_single_line(self)
	if data := native_window_data(self) { if data.tabs_tahoe { queue_tahoe_window(self, .title, false, false, 0) } }
}

fn register_window_font_methods(cls ObjId) {
	add_method(cls, 'setTitle:', voidptr(window_font_title_changed), 'v@:@')
}

// TerminalController.syncAppearance projects the focused surface's optional
// family to NSFont(name:size:), before TerminalWindow.syncAppearance runs.
pub fn set_native_window_title_font(view voidptr, family ?string) {
	window := msg_id(view, 'window')
	if is_nil(window) || !msg_bool1(window, 'isKindOfClass:', get_class('VTTerminalWindow')) { return }
	size := msg_f64(get_class('NSFont'), 'systemFontSize')
	font := if name := family { C.witty_macos_msg_id_obj_f64(get_class('NSFont'), sel('fontWithName:size:'), nsstring(name), size) } else { nil_obj() }
	C.macos_set_associated_object(window, voidptr(&native_title_font_key), font, uint(1))
	display_font := if is_nil(font) { msg_id_f64(get_class('NSFont'), 'titleBarFontOfSize:', size) } else { font }
	for field in window_font_title_fields(window) {
		msg_void1(field, 'setFont:', display_font)
	}
	// TitlebarTabsVenturaTerminalWindow.titlebarFont also projects the font to
	// TerminalToolbar's centered label when that custom toolbar exists.
	if data := native_window_data(window) {
		if data.tabs_tahoe { queue_tahoe_window(window, .font, false, false, 0) }
		else { msg_void1(data.title_label, 'setFont:', display_font) }
	}
	window_font_single_line(window)
	refresh_native_window_title_attributes(window)
}
