module inspector

import cimgui
import osc
import lib_allocator
import terminal

const max_vt_events = 100

const vt_filter_action_types = [
	terminal.ParserActionType.print_action,
	.execute_action,
	.csi_dispatch_action,
	.esc_dispatch_action,
	.osc_dispatch_action,
	.dcs_hook_action,
	.dcs_put_action,
	.dcs_unhook_action,
	.apc_start_action,
	.apc_put_action,
	.apc_end_action,
]

enum VTKind as u8 {
	print
	execute
	csi
	esc
	osc
	dcs
	apc
}

pub struct VTEvent {
mut:
	seq              uint = 1
	kind             VTKind
	raw_description  string
	cursor           terminal.Cursor
	scrolling_region terminal.ScrollingRegion
	metadata         map[string]string
	imgui_selected   bool
}

fn (mut self VTEvent) deinit() {
	self.raw_description = ''
	self.cursor.hyperlink_state = none
	self.metadata.clear()
}

// VTStream is Ghostty's bounded raw parser-action stream. Parser actions are
// recorded before their semantic counterparts mutate the terminal, so every
// event carries the cursor and scrolling-region state it observed on entry.
pub struct VTStream {
mut:
	events                  []VTEvent
	parser_stream           terminal.Stream[VTHandler]
	paused                  bool
	current_seq             uint = 1
	filter_exclude          [11]bool
	filter_text             string
	filter_native           cimgui.TextFilter
	selected_event_seq      ?u32
	need_scroll_to_selected bool
	is_keyboard_selection   bool
}

pub fn VTStream.init() VTStream {
	mut result := VTStream{
		events:        []VTEvent{cap: 2}
		parser_stream: terminal.Stream.init_alloc[VTHandler](voidptr(1), VTHandler{})
	}
	result.filter_native = cimgui.TextFilter.create('')
	result.filter_exclude[int(terminal.ParserActionType.print_action)] = true
	return result
}

pub fn (mut self VTStream) deinit() {
	self.clear()
	self.parser_stream.deinit()
	self.filter_native.destroy()
}

// record_pty_read advances the parallel parser across one PTY read. Event
// snapshots are recorded before the real terminal consumes the bytes.
pub fn (mut self VTStream) record_pty_read(t &terminal.Terminal, data []u8) ! {
	self.parser_stream.handler.state = VTHandlerState{
		terminal: unsafe { t }
		stream:   unsafe { &self }
	}
	defer {
		self.parser_stream.handler.state = none
	}
	self.parser_stream.next_slice(data)!
}

// The capture state of a VTHandler.
struct VTHandlerState {
	terminal &terminal.Terminal = unsafe { nil }
	stream   &VTStream          = unsafe { nil }
}

// VTHandler is the parser stream handler that records raw parser actions.
// The recording fields stay on VTStream; only the stream interface lives here.
struct VTHandler {
mut:
	// The capture state, must be set before use. If none, then
	// events are dropped.
	state ?VTHandlerState
}

pub fn (mut self VTHandler) deinit() {
	// Required for the parser stream interface
}

pub fn (mut self VTHandler) vt(action terminal.ActionKey, value terminal.ActionValue) ! {
}

@[inline]
pub fn (mut self VTHandler) vt_print(value terminal.ActionPrint) ! {
}

// This is called with every single terminal action.
pub fn (mut self VTHandler) vt_raw(action terminal.ParserAction) !bool {
	state := self.state or { return true }
	mut stream := state.stream
	return stream.vt_raw(action, state.terminal)
}

fn (mut self VTStream) clear() {
	for mut event in self.events {
		event.deinit()
	}
	self.events.clear()
	self.selected_event_seq = none
	self.need_scroll_to_selected = false
	self.is_keyboard_selection = false
}

fn (mut self VTStream) reset() {
	self.clear()
	self.current_seq = 1
}

// vt_raw records a parser action before its semantic handler mutates the
// terminal. The return value tells the stream whether the raw action was
// completely handled and its typed callback should be skipped.
pub fn (mut self VTStream) vt_raw(action terminal.ParserAction, term &terminal.Terminal) bool {
	seq := self.current_seq
	self.current_seq++

	if self.paused || action.tag() in [.dcs_put_action, .apc_put_action] {
		return true
	}
	if self.filter_exclude[int(action.tag())] {
		return true
	}

	mut cursor := term.screens.active.cursor
	if hyperlink := cursor.hyperlink_state {
		cursor.hyperlink_state = hyperlink.dupe()
	}
	mut event := VTEvent{
		seq:              seq
		kind:             vt_kind(action.tag())
		raw_description:  encode_vt_action(action)
		cursor:           cursor
		scrolling_region: term.scrolling_region
		metadata:         vt_action_metadata(action)
	}
	self.filter_native.set(self.filter_text)
	if !event.pass_native_filter(self.filter_native) {
		event.deinit()
		return true
	}

	if self.events.len == max_vt_events {
		mut oldest := self.events[0]
		oldest.deinit()
		self.events.delete(0)
	}
	self.events << event
	return false
}

fn vt_kind(action_type terminal.ParserActionType) VTKind {
	return match action_type {
		.print_action { .print }
		.execute_action { .execute }
		.csi_dispatch_action { .csi }
		.esc_dispatch_action { .esc }
		.osc_dispatch_action { .osc }
		.dcs_hook_action, .dcs_put_action, .dcs_unhook_action { .dcs }
		.apc_start_action, .apc_put_action, .apc_end_action { .apc }
	}
}

fn encode_vt_action(action terminal.ParserAction) string {
	return match action {
		terminal.ParserPrint { "'${rune(action.cp)}' (U+${action.cp:X})" }
		terminal.ParserExecute { '${execute_name(action.code)} (0x${action.code:X})' }
		terminal.CSIAction { encode_csi_action(action) }
		terminal.ESCAction { encode_esc_action(action) }
		osc.Command { '${action.key()} ' }
		else { action.tag().str() }
	}
}

fn execute_name(value u8) string {
	return match value {
		0x00 { 'NUL' }
		0x01 { 'SOH' }
		0x02 { 'STX' }
		0x03 { 'ETX' }
		0x04 { 'EOT' }
		0x05 { 'ENQ' }
		0x06 { 'ACK' }
		0x07 { 'BEL' }
		0x08 { 'BS' }
		0x09 { 'HT' }
		0x0a { 'LF' }
		0x0b { 'VT' }
		0x0c { 'FF' }
		0x0d { 'CR' }
		0x0e { 'SO' }
		0x0f { 'SI' }
		else { '?' }
	}
}

fn encode_csi_action(action terminal.CSIAction) string {
	mut result := ''
	for intermediate in action.intermediates {
		result += '${rune(intermediate)} '
	}
	for index, param in action.params {
		if index > 0 {
			result += ';'
		}
		result += param.str()
	}
	if action.intermediates.len > 0 || action.params.len > 0 {
		result += ' '
	}
	result += rune(action.final_byte).str()
	return result
}

fn encode_esc_action(action terminal.ESCAction) string {
	mut result := ''
	for intermediate in action.intermediates {
		result += '${rune(intermediate)} '
	}
	result += rune(action.final_byte).str()
	return result
}

fn vt_action_metadata(action terminal.ParserAction) map[string]string {
	mut result := map[string]string{}
	if action is osc.Command {
		cmd := action as osc.Command
		$for variant in osc.Command.variants {
			// V's unused-variable check misses comptime variants used in type guards.
			_ = variant.typ
			if cmd is variant { encode_metadata(mut result, cmd) }
		}
	}
	return result
}

struct KittyColorMetadataSource {
	list       []osc.KittyColorRequest
	terminator osc.Terminator
}

// The V sum type wraps Zig's string/void/union payloads in named structs.
// Unwrap those representations before translating the source reflection.
fn encode_metadata[T](mut metadata map[string]string, value T) {
	$if T is string {
		metadata['data'] = value.clone()
	} $else $if T is osc.KittyColorOSC {
		// The V allocation owner is storage, outside the source OSC payload.
		encode_metadata(mut metadata, KittyColorMetadataSource{ list: value.list, terminator: value.terminator })
	} $else $if T is osc.ConEmuChangeTabTitle {
		metadata['data'] = match value.title {
			osc.ConEmuTabTitleReset { 'reset' }
			string { 'value=${value.title}' }
		}
	} $else $if T is $struct {
		$for field in T.fields {
			key := if field.name == 'value' { 'data' } else { field.name }
			$if field.typ is $option {
				$if field.typ is ?bool {
					encode_metadata_optional_bool(mut metadata, key, ?bool(value.$(field.name)))
				} $else $if field.typ is ?u8 {
					encode_metadata_optional_u8(mut metadata, key, ?u8(value.$(field.name)))
				} $else $if field.typ is ?string {
					encode_metadata_optional_string(mut metadata, key, ?string(value.$(field.name)))
				} $else {
					$compile_error('unsupported OSC optional metadata type')
				}
			} $else {
				encode_metadata_single(mut metadata, key, value.$(field.name))
			}
		}
	} $else {
		// A runtime panic, not $compile_error: V 0.5.2 master reaches this branch
		// while checking the generic body, even though no OSC variant does.
		panic('unsupported OSC metadata payload')
	}
}

// Specializations avoid V 0.5.2 reusing one option temporary across generic
// instantiations; dispatch still follows the reflected field's actual type.
fn encode_metadata_optional_bool(mut metadata map[string]string, key string, value ?bool) {
	if item := value {
		metadata[key] = item.str()
	} else {
		metadata[key] = '(unset)'
	}
}

fn encode_metadata_optional_u8(mut metadata map[string]string, key string, value ?u8) {
	if item := value {
		metadata[key] = item.str()
	} else {
		metadata[key] = '(unset)'
	}
}

fn encode_metadata_optional_string(mut metadata map[string]string, key string, value ?string) {
	if item := value {
		metadata[key] = item.clone()
	} else {
		metadata[key] = '(unset)'
	}
}

fn encode_metadata_single[T](mut metadata map[string]string, key string, value T) {
	$if T is bool || T is $enum || T is $int {
		metadata[key] = value.str()
	} $else $if T is string {
		metadata[key] = value.clone()
	} $else $if T is []osc.ColorRequest || T is lib_allocator.SegmentedList[osc.ColorRequest] {
		metadata[key] = 'segmented_list.SegmentedList(terminal.osc.parsers.color.Request,2)'
	} $else $if T is []osc.KittyColorRequest || T is lib_allocator.ArrayList[osc.KittyColorRequest] {
		metadata[key] = 'array_list.Aligned(terminal.kitty.color.OSC.Request,null)'
	} $else $if T is $struct {
		metadata[key] = typeof(value).name
	} $else {
		panic('unsupported OSC metadata field ${key} type=${typeof(value).name}')
	}
}

pub fn (self &VTEvent) pass_filter(filter string) bool {
	if imgui_text_filter_pass(filter, self.raw_description) {
		return true
	}
	for key, value in self.metadata {
		if imgui_text_filter_pass(filter, key) || imgui_text_filter_pass(filter, value) {
			return true
		}
	}
	return false
}

fn (self &VTEvent) pass_native_filter(filter cimgui.TextFilter) bool {
	if filter.pass(self.raw_description) { return true }
	for key, value in self.metadata {
		if filter.pass(key) || filter.pass(value) { return true }
	}
	return false
}

// event_table renders the source's standalone, read-only VT event table. The
// live Stream widget currently uses its richer selectable table below, as does
// Ghostty at the pinned revision.
pub fn event_table(context cimgui.Context, events []VTEvent) {
	if !context.begin_table('events', 3, cimgui.table_flags_borders_row_bg) {
		return
	}
	defer {
		context.end_table()
	}
	context.table_setup_column('Seq', cimgui.table_column_width_fixed, 0)
	context.table_setup_column('Kind', cimgui.table_column_width_fixed, 0)
	context.table_setup_column('Description', cimgui.table_column_width_stretch, 0)
	for index := events.len - 1; index >= 0; index-- {
		event := &events[index]
		context.push_id(event)
		context.table_next_row()
		context.table_next_column()
		context.same_line()
		context.text(event.seq.str())
		context.table_next_column()
		context.text(event.kind.str())
		context.table_next_column()
		context.text(event.raw_description)
		context.pop_id()
	}
}

// Reuse the pinned native ImGuiTextFilter parser rather than a V substitute.
fn imgui_text_filter_pass(filter string, text string) bool {
	native := cimgui.TextFilter.create(filter)
	defer { native.destroy() }
	return native.pass(text)
}

pub fn (mut self VTStream) draw(context cimgui.Context, palette [256]terminal.RGB) {
	pause_label := if self.paused { 'Resume##pause_play' } else { 'Pause##pause_play' }
	if context.button(pause_label) {
		self.paused = !self.paused
	}
	context.same_line()
	if context.button('Filter') {
		context.open_popup('Filter')
	}
	if self.events.len > 0 {
		context.same_line()
		if context.button('Clear') {
			self.reset()
		}
	}

	if self.events.len == 0 {
		context.text('Waiting for events...')
	}
	context.separator()
	self.draw_events(context, palette)
	self.draw_filter(context)
}

fn (mut self VTStream) draw_events(context cimgui.Context, palette [256]terminal.RGB) {
	if !context.begin_table('table_vt_events', 3,
		cimgui.table_flags_borders_row_bg_sizing_fixed_fit) {
		return
	}
	defer {
		context.end_table()
	}
	context.table_setup_column('Seq', cimgui.table_column_width_fixed, 0)
	context.table_setup_column('Kind', cimgui.table_column_width_fixed, 0)
	context.table_setup_column('Description', cimgui.table_column_width_stretch, 0)

	if context.window_focused() {
		action := vt_key_action(context)
		if action != .none_ {
			self.navigate(action)
		}
	}

	for index := self.events.len - 1; index >= 0; index-- {
		mut event := &self.events[index]
		context.push_id(event)
		context.table_next_row()
		context.table_next_column()

		was_selected := event.imgui_selected
		if selected_seq := self.selected_event_seq {
			event.imgui_selected = u32(event.seq) == selected_seq
		}
		changed, selected := context.selectable_bool('##select', event.imgui_selected)
		event.imgui_selected = selected
		if changed && event.imgui_selected != was_selected {
			self.selected_event_seq = if event.imgui_selected { u32(event.seq) } else { none }
			self.is_keyboard_selection = false
		}

		context.same_line()
		context.text(event.seq.str())
		context.table_next_column()
		context.text(event.kind.str())
		context.table_next_column()
		context.text(event.raw_description)

		if event.imgui_selected {
			draw_vt_event_details(context, event, palette)
			if self.need_scroll_to_selected && self.is_keyboard_selection {
				context.set_scroll_here_y(0.5)
				self.need_scroll_to_selected = false
			}
		}
		context.pop_id()
	}
}

enum VTKeyAction as u8 {
	down
	none_
	up
}

fn vt_key_action(context cimgui.Context) VTKeyAction {
	if context.key_pressed(.key_j) || context.key_pressed(.down_arrow) {
		return .down
	}
	if context.key_pressed(.key_k) || context.key_pressed(.up_arrow) {
		return .up
	}
	return .none_
}

fn (mut self VTStream) navigate(action VTKeyAction) {
	if self.events.len == 0 {
		return
	}
	if selected := self.selected_event_seq {
		mut index := -1
		for i, event in self.events {
			if u32(event.seq) == selected {
				index = i
				break
			}
		}
		if index >= 0 {
			match action {
				.down {
					if index > 0 {
						self.selected_event_seq = u32(self.events[index - 1].seq)
					}
				}
				.up {
					if index + 1 < self.events.len {
						self.selected_event_seq = u32(self.events[index + 1].seq)
					}
				}
				.none_ {
					panic('unreachable')
				}
			}
		}
	} else {
		self.selected_event_seq = match action {
			.down { u32(self.events[self.events.len - 1].seq) }
			.up { u32(self.events[0].seq) }
			.none_ { panic('unreachable') }
		}
	}
	self.need_scroll_to_selected = true
	self.is_keyboard_selection = true
}

fn draw_vt_event_details(context cimgui.Context, event &VTEvent, palette [256]terminal.RGB) {
	cursor_table(context, event.cursor)
	cursor_style(context, event.cursor, palette)
	if !context.begin_table('details', 2, 0) {
		return
	}
	defer {
		context.end_table()
	}
	context.table_next_row()
	context.table_set_column(0)
	context.text('Scroll Region')
	context.table_set_column(1)
	region := event.scrolling_region
	context.text('T=${region.top} B=${region.bottom} L=${region.left} R=${region.right}')
	for key, value in event.metadata {
		context.table_next_row()
		context.table_next_column()
		context.text(key)
		context.table_next_column()
		context.text(value)
	}
}

fn (mut self VTStream) draw_filter(context cimgui.Context) {
	if !context.begin_popup_modal('Filter') {
		return
	}
	defer {
		context.end_popup()
	}
	context.text('Changed filter settings will only affect future events.')
	context.separator()
	if context.begin_table('table_filter_kind', 3, 0) {
		for action_type in vt_filter_action_types {
			if action_type in [.dcs_put_action, .apc_put_action] {
				continue
			}
			context.table_next_column()
			enabled := !self.filter_exclude[int(action_type)]
			changed, updated := context.checkbox(action_type.str(), enabled)
			if changed {
				self.filter_exclude[int(action_type)] = !updated
			}
		}
		context.end_table()
	}
	context.separator()
	context.text('Filter by string. Empty displays all, "abc" finds lines\ncontaining "abc", "abc,xyz" finds lines containing "abc"\nor "xyz", "-abc" excludes lines containing "abc".')
	self.filter_native.set(self.filter_text)
	context.draw_text_filter(self.filter_native, '##filter_text')
	self.filter_text = self.filter_native.get()
	context.separator()
	if context.button('Close') {
		context.close_current_popup()
	}
}
