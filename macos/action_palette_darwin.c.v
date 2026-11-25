@[has_globals]
module macos

import math

// CommandPalette.swift and TerminalCommandPalette.swift: original option order,
// localized title/subtitle search, color match ranking, selection, submission,
// focus restoration. Native AppKit views implement the same event consumers.
fn C.witty_action_id_f64_f64(obj voidptr, selector voidptr, a f64, b f64) voidptr
fn C.witty_action_compare(a voidptr, b voidptr) i64
fn C.witty_palette_match_ranges(text ObjId, query ObjId) ObjId

pub struct NativeCommandOption {
pub:
	title         string
	subtitle      string
	description   string
	action        string
	invoke        fn () = unsafe { nil }
	leading_icon  string
	symbols       []string
	badge         ?string
	emphasis      bool
	focus_view    voidptr
	leading_color ?voidptr
	sort_key      ?u64
}

@[heap]
struct NativeCommandPalette {
mut:
	surface   &NativeActionSurface = unsafe { nil }
	owner     ObjId
	container ObjId
	chrome    PaletteChrome
	field     ObjId
	scroll    ObjId
	document  ObjId
	options   []NativeCommandOption
	filtered  []NativeCommandOption
	query     string
	selected  ?uint
	hovered   ?uint
}

fn palette_state(self ObjId) ?&NativeCommandPalette {
	ptr := C.macos_objc_get_ptr_ivar(self, cstr('palette'))
	if is_nil(ptr) { return none }
	return unsafe { &NativeCommandPalette(ptr) }
}

pub fn sorted_command_options(options []NativeCommandOption) []NativeCommandOption {
	mut result := []NativeCommandOption{}
	for option in options {
		mut position := result.len
		for position > 0 && palette_option_compare(option, result[position - 1]) < 0 { position-- }
		result.insert(position, option)
	}
	return result
}

fn palette_option_compare(a NativeCommandOption, b NativeCommandOption) int {
	order := C.witty_action_compare(nsstring(a.title.replace(':', '\t')), nsstring(b.title.replace(':', '\t')))
	if order != 0 { return int(order) }
	if left := a.sort_key {
		if right := b.sort_key {
			return if left < right {
				-1
			} else if left > right {
				1
			} else {
				0
			}
		}
	}
	return 0
}

fn palette_color_score(color ?voidptr, query string) f64 {
	value := color or { return 0 }
	color_list := msg_id1(get_class('NSColorList'), 'colorListNamed:', nsstring('Apple'))
	if is_nil(color_list) { return 0 }
	names := msg_id(color_list, 'allKeys')
	lower := objc_utf8_string(msg_id(nsstring(query), 'lowercaseString'))
	mut best := 0.0
	for i in 0 .. int(msg_u64(names, 'count')) {
		name := msg_id_u64(names, 'objectAtIndex:', u64(i))
		lowered := objc_utf8_string(msg_id(name, 'lowercaseString'))
		if !lower.contains(lowered) {
			continue
		}
		system := msg_id1(color_list, 'colorWithKey:', msg_id(name, 'capitalizedString'))
		srgb := msg_id1(system, 'colorUsingColorSpace:', msg_id(get_class('NSColorSpace'),
			'sRGBColorSpace'))
		if is_nil(srgb) {
			continue
		}
		actual := msg_id1(value, 'colorUsingColorSpace:', msg_id(get_class('NSColorSpace'),
			'sRGBColorSpace'))
		if is_nil(actual) {
			continue
		}
		r := msg_f64(actual, 'redComponent') - msg_f64(srgb, 'redComponent')
		g := msg_f64(actual, 'greenComponent') - msg_f64(srgb, 'greenComponent')
		b := msg_f64(actual, 'blueComponent') - msg_f64(srgb, 'blueComponent')
		distance := math.sqrt(2 * r * r + 4 * g * g + 3 * b * b)
		if distance < 1.5 { best = math.max(best, 1 - distance / 1.5) }
	}
	return best
}

fn trim_palette_query(value ObjId) ObjId {
	whitespace := msg_id(get_class('NSCharacterSet'), 'whitespaceAndNewlineCharacterSet')
	return msg_id1(value, 'stringByTrimmingCharactersInSet:', whitespace)
}

struct PaletteOptionMatch {
	option NativeCommandOption
	color  f64
	text   int
}

fn (match_ PaletteOptionMatch) ranks_before(other PaletteOptionMatch) bool {
	return match_.color > other.color || (match_.color == other.color && match_.text > other.text)
}

pub fn filtered_command_options(options []NativeCommandOption, query string) []NativeCommandOption {
	needle := trim_palette_query(nsstring(query))
	trimmed := objc_utf8_string(needle)
	if trimmed.len == 0 { return options.clone() }
	mut matches := []PaletteOptionMatch{cap: options.len}
	for option in options {
		color := palette_color_score(option.leading_color, trimmed)
		text := if !is_nil(C.witty_palette_match_ranges(nsstring(option.title), needle)) {
			3
		} else if !is_nil(C.witty_palette_match_ranges(nsstring(option.subtitle), needle)) {
			2
		} else if !is_nil(C.witty_palette_match_ranges(nsstring(option.description), needle)) {
			1
		} else {
			0
		}
		if color <= 0 && text == 0 { continue }
		value := PaletteOptionMatch{option: option, color: color, text: text}
		mut position := matches.len
		for position > 0 && value.ranks_before(matches[position - 1]) { position-- }
		matches.insert(position, value)
	}
	return matches.map(it.option)
}

pub fn (mut surface NativeActionSurface) toggle_command_palette(options []NativeCommandOption) {
	if surface.palette != unsafe { nil } {
		surface.palette.close()
		return
	}
	mut cls := get_class('WittyCommandPaletteOwner')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSObject'),
			cstr('WittyCommandPaletteOwner'), 0)
		add_ptr_ivar(cls, 'palette')
		add_method(cls, 'controlTextDidChange:', voidptr(palette_edit), 'v@:@')
		add_method(cls, 'control:textView:doCommandBySelector:', voidptr(palette_command), 'B@:@@:')
		add_method(cls, 'controlTextDidEndEditing:', voidptr(palette_lost_focus), 'v@:@')
		add_method(cls, 'submit:', voidptr(palette_submit), 'v@:@')
		add_method(cls, 'mouseEntered:', voidptr(palette_hover), 'v@:@')
		add_method(cls, 'mouseExited:', voidptr(palette_hover), 'v@:@')
		add_method(cls, 'accessibilityDisplayChanged:', voidptr(palette_accessibility_display_changed), 'v@:@')
		C.macos_objc_register_class_pair(cls)
	}
	mut container_class := get_class('WittyPaletteContainer')
	if is_nil(container_class) {
		container_class = C.macos_objc_allocate_class_pair(get_class('NSView'),
			cstr('WittyPaletteContainer'), 0)
		add_method(container_class, 'isFlipped', voidptr(action_flipped), 'B@:')
		C.macos_objc_register_class_pair(container_class)
	}
	mut palette := &NativeCommandPalette{
		surface: &surface
		options: options.clone()
	}
	palette.owner = msg_id(alloc('WittyCommandPaletteOwner'), 'init')
	C.macos_objc_set_ptr_ivar(palette.owner, cstr('palette'), voidptr(palette))
	palette.container = msg_id_rect(alloc('WittyPaletteContainer'), 'initWithFrame:', objc_rect(16,
		16, 0, 0))
	palette.chrome = new_palette_chrome(palette.container)
	palette.field = msg_id_rect(alloc('NSTextField'), 'initWithFrame:', objc_rect(16, 8, 468, 40))
	msg_void1(palette.field, 'setPlaceholderString:', nsstring('Execute a command…'))
	msg_void_bool(palette.field, 'setBezeled:', false)
	msg_void_bool(palette.field, 'setDrawsBackground:', false)
	msg_void1(palette.field, 'setFont:',
		C.witty_action_id_f64_f64(get_class('NSFont'), sel('systemFontOfSize:weight:'), 20, -0.4))
	msg_void1(palette.field, 'setDelegate:', palette.owner)
	msg_void1(palette.chrome.plate, 'addSubview:', palette.field)
	msg_void(palette.field, 'release')
	palette.scroll = msg_id_rect(alloc('NSScrollView'), 'initWithFrame:',
		objc_rect(0, 48, 500, 200))
	msg_void_bool(palette.scroll, 'setHasVerticalScroller:', true)
	msg_void_bool(palette.scroll, 'setDrawsBackground:', false)
	palette.document = msg_id_rect(alloc('WittyActionOverlay'), 'initWithFrame:', objc_rect(0, 0,
		500, 200))
	msg_void1(palette.scroll, 'setDocumentView:', palette.document)
	msg_void(palette.document, 'release')
	msg_void1(palette.chrome.plate, 'addSubview:', palette.scroll)
	msg_void(palette.scroll, 'release')
	surface.palette = palette
	msg_void1(surface.overlay, 'addSubview:', palette.container)
	C.witty_macos_observe(palette_accessibility_center(), palette.owner,
		sel('accessibilityDisplayChanged:'), nsstring('NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification'), nil_obj())
	palette.rebuild()
	msg_bool1(view_window(surface.view), 'makeFirstResponder:', palette.field)
}

pub fn (surface &NativeActionSurface) command_palette_is_showing() bool {
	return surface.palette != unsafe { nil }
}

fn (mut palette NativeCommandPalette) layout() {
	width := math.max(0.0, math.min(500.0, view_width(palette.surface.view) - 32))
	scroll_height := if palette.filtered.len == 0 { 48.0 } else { 200.0 }
	scale := view_backing_scale(palette.surface.view)
	frame := native_canvas_overlay_rect(SplitBounds{
		x: (view_width(palette.surface.view) - width) / 2
		y: view_height(palette.surface.view) * 0.05 + palette_top_inset
		width: width
		height: palette_header_height + scroll_height
	}, scale)
	msg_void_rect(palette.container, 'setFrame:', frame)
	palette.chrome.layout(palette.container, frame.width, frame.height, scale, palette.surface.visual_background)
	msg_void_rect(palette.field, 'setFrame:', objc_rect(14, 11.5, math.max(0.0, frame.width - 28), 34))
	msg_void_rect(palette.scroll, 'setFrame:', objc_rect(0, palette_header_height, frame.width, scroll_height))
	msg_void_rect(palette.document, 'setFrame:',
		objc_rect(0, 0, frame.width, msg_rect(palette.document, 'frame').height))
}

fn (mut palette NativeCommandPalette) close() {
	if palette.surface.palette == unsafe { nil } { return }
	palette.surface.palette = unsafe { nil }
	msg_bool1(view_window(palette.surface.view), 'makeFirstResponder:', palette.surface.view)
	palette.clear_rows()
	msg_void1(palette.field, 'setDelegate:', nil_obj())
	msg_void1(palette_accessibility_center(), 'removeObserver:', palette.owner)
	C.macos_objc_set_ptr_ivar(palette.owner, cstr('palette'), unsafe { nil })
	msg_void(palette.container, 'removeFromSuperview')
	msg_void(palette.container, 'release')
	msg_void(palette.owner, 'release')
}

fn palette_accessibility_center() ObjId {
	return msg_id(msg_id(get_class('NSWorkspace'), 'sharedWorkspace'), 'notificationCenter')
}

fn palette_accessibility_display_changed(self ObjId, _cmd Sel, _notification ObjId) {
	if mut palette := palette_state(self) { palette.layout() }
}

fn (palette &NativeCommandPalette) clear_rows() {
	children := msg_id(palette.document, 'subviews')
	row_class := get_class('WittyPaletteRow')
	for i := int(msg_u64(children, 'count')) - 1; i >= 0; i-- {
		row := msg_id_u64(children, 'objectAtIndex:', u64(i))
		if !is_nil(row_class) && msg_bool1(row, 'isKindOfClass:', row_class) {
			C.macos_objc_set_ptr_ivar(row, cstr('palette'), unsafe { nil })
			msg_void1(row, 'setTarget:', nil_obj())
			areas := msg_id(row, 'trackingAreas')
			for j := int(msg_u64(areas, 'count')) - 1; j >= 0; j-- {
				msg_void1(row, 'removeTrackingArea:', msg_id_u64(areas, 'objectAtIndex:', u64(j)))
			}
		}
		msg_void(row, 'removeFromSuperview')
	}
}

fn (mut palette NativeCommandPalette) rebuild() {
	palette.clear_rows()
	palette.hovered = none
	palette.filtered = filtered_command_options(palette.options, palette.query)
	palette.layout()
	width := msg_rect(palette.document, 'bounds').width
	if palette.filtered.len == 0 {
		msg_void_rect(palette.document, 'setFrame:', objc_rect(0, 0, width, 48))
		label := new_palette_empty_message(objc_rect(0, 0, width, 48))
		msg_void1(palette.document, 'addSubview:', label)
		msg_void(label, 'release')
		return
	}
	mut y := 10.0
	for index, option in palette.filtered {
		height := option.row_height()
		row := new_palette_row(palette, index, objc_rect(10, y, math.max(0.0, width - 20), height))
		msg_void1(palette.document, 'addSubview:', row)
		msg_void(row, 'release')
		y += height + palette_row_gap
	}
	msg_void_rect(palette.document, 'setFrame:', objc_rect(0, 0, width, y + 10 - palette_row_gap))
}

fn (palette &NativeCommandPalette) repaint_rows() {
	children := msg_id(palette.document, 'subviews')
	for i in 0 .. int(msg_u64(children, 'count')) {
		row := msg_id_u64(children, 'objectAtIndex:', u64(i))
		msg_void_bool(row, 'setNeedsDisplay:', true)
	}
}

fn palette_hover(self ObjId, cmd Sel, event ObjId) {
	mut palette := palette_state(self) or { return }
	info := msg_id(msg_id(event, 'trackingArea'), 'userInfo')
	tag := msg_id1(info, 'objectForKey:', nsstring('row'))
	if is_nil(tag) { return }
	index := uint(msg_u64(tag, 'unsignedIntegerValue'))
	if cmd == sel('mouseEntered:') {
		palette.hovered = index
	} else if previous := palette.hovered {
		if previous == index { palette.hovered = none }
	}
	palette.repaint_rows()
}

fn palette_edit(self ObjId, _cmd Sel, _notification ObjId) {
	mut palette := palette_state(self) or { return }
	palette.query = objc_utf8_string(trim_palette_query(msg_id(palette.field, 'stringValue')))
	if palette.query.len > 0 {
		if palette.selected == none { palette.selected = uint(0) }
	} else if value := palette.selected {
		if value == 0 { palette.selected = none }
	}
	palette.rebuild()
}

fn palette_command(self ObjId, _cmd Sel, _control ObjId, _text ObjId, command Sel) bool {
	mut palette := palette_state(self) or { return false }
	if command == sel('cancelOperation:') {
		palette.close()
		return true
	}
	if command == sel('insertNewline:') {
		palette.activate(palette.selected)
		return true
	}
	if command in [sel('moveUp:'), sel('moveDown:')] {
		count := palette.filtered.len
		if count == 0 { return true }
		if command == sel('moveUp:') {
			current := palette.selected or { uint(count) }
			palette.selected = if current == 0 { uint(count - 1) } else { current - 1 }
		} else {
			current := palette.selected or { ~uint(0) }
			palette.selected = if current >= uint(count - 1) { uint(0) } else { current + 1 }
		}
		palette.repaint_rows()
		if index := palette.selected {
			if index < uint(count) {
				children := msg_id(palette.document, 'subviews')
				frame := msg_rect(msg_id_u64(children, 'objectAtIndex:', u64(index)), 'frame')
				C.witty_action_scroll_rect(palette.document, frame.x, frame.y, frame.width, frame.height)
			}
		}
		return true
	}
	return false
}

fn palette_lost_focus(self ObjId, _cmd Sel, _notification ObjId) {
	if mut palette := palette_state(self) { palette.close() }
}

fn palette_submit(self ObjId, _cmd Sel, sender ObjId) {
	if mut palette := palette_state(self) { palette.activate(uint(msg_u64(sender, 'tag'))) }
}

fn (mut palette NativeCommandPalette) activate(selected ?uint) {
	mut value := ?NativeCommandOption(none)
	if index := selected {
		if palette.filtered.len > 0 {
			final_index := if index < uint(palette.filtered.len) {
				int(index)
			} else {
				palette.filtered.len - 1
			}
			value = palette.filtered[final_index]
		}
	}
	palette.close()
	if option := value {
		if !is_nil(option.focus_view) {
			if palette.surface.callbacks.present != unsafe { nil } {
				palette.surface.callbacks.present(palette.surface.userdata, option.focus_view)
			} else {
				present_view(option.focus_view)
			}
		} else if option.invoke != unsafe { nil } {
			option.invoke()
		} else {
			palette.surface.perform(option.action)
		}
	}
}

fn C.witty_action_scroll_rect(view voidptr, x f64, y f64, width f64, height f64)
