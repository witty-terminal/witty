module terminal

import osc

// Tests translated from ghostty's Terminal.zig

fn test_mouse_mode_storage() {
	assert $sizeof(MouseEvents) == 1
	assert u8(MouseEvents.none) == 0
	assert u8(MouseEvents.any) == 4
	assert $sizeof(MouseFormat) == 1
	assert u8(MouseFormat.x10) == 0
	assert u8(MouseFormat.sgr_pixels) == 4
}

fn test_scroll_viewport_source_layout_and_payload() {
	assert scroll_viewport_top is ScrollViewportTop
	assert scroll_viewport_bottom is ScrollViewportBottom
	wide_delta := int(1_099_511_627_776)
	delta := ScrollViewport.from_delta(wide_delta)
	assert delta is ScrollViewportDelta
	assert (delta as ScrollViewportDelta).delta == wide_delta

	assert sizeof(SwitchScreenMode) == 1
	assert u8(SwitchScreenMode.mode_47) == 0
	assert u8(SwitchScreenMode.mode_1047) == 1
	assert u8(SwitchScreenMode.mode_1049) == 2
	assert sizeof(WrapMode) == 1
	assert u8(WrapMode.none) == 0
	assert u8(WrapMode.reverse) == 1
	assert u8(WrapMode.reverse_extended) == 2
}

fn semantic_click_for(options string) SemanticClick {
	mut t := Terminal.init(Options{ cols: 10, rows: 5 }) or { panic(err) }
	t.semantic_prompt(osc.SemanticPrompt{
		action:              .fresh_line_new_prompt
		options_unvalidated: options
	})
	result := t.screens.active.semantic_prompt.click
	t.deinit()
	return result
}

fn test_terminal_semantic_prompt_click_options() {
	assert semantic_click_for('click_events=1') == semantic_click_click_events
	assert semantic_click_for('click_events=0') == semantic_click_none

	multiple := semantic_click_for('cl=m')
	assert multiple is SemanticClickCl
	assert (multiple as SemanticClickCl).cl == .multiple

	line := semantic_click_for('cl=line')
	assert line is SemanticClickCl
	assert (line as SemanticClickCl).cl == .line

	assert semantic_click_for('click_events=1;cl=m') == semantic_click_click_events
	conservative := semantic_click_for('click_events=0;cl=v')
	assert conservative is SemanticClickCl
	assert (conservative as SemanticClickCl).cl == .conservative_vertical
	assert semantic_click_for('aid=123') == semantic_click_none
}

// ============================================================
// Helper: create a terminal for tests with wraparound mode enabled by default
// ============================================================
fn create_test_terminal(cols u16, rows u16) !Terminal {
	mut t := Terminal.init(Options{ cols: cols, rows: rows })!
	// Enable wraparound by default (same as ghostty)
	t.modes.set(.wraparound, true)
	return t
}

// Helper: an active-area point, like ghostty's `.{ .active = .{ .x = x, .y = y } }`.
fn active_point(x int, y int) Point {
	return Point.new(.active, Coordinate{
		x: u16(x)
		y: u32(y)
	})
}

// Helper: look up an active-area cell like ghostty's
// `t.screens.active.pages.getCell(.{ .active = .{ .x = x, .y = y } }).?`.
fn active_cell(t &Terminal, x int, y int) PageCell {
	return t.screens.active.pages.get_cell(active_point(x, y)) or {
		panic('active cell is outside the page list')
	}
}

// Helper: look up an active-area row like ghostty's
// `t.screens.active.pages.getCell(.{ .active = .{ .y = y } }).?.row`.
fn active_row(t &Terminal, y int) &RowData {
	return active_cell(t, 0, y).row
}

// Helper: read a cell at active-area coordinates (x, y).
fn cell_at(t &Terminal, x int, y int) CellData {
	list_cell := t.screens.active.pages.get_cell(active_point(x, y)) or { return CellData{} }
	return *list_cell.cell
}

// Helper: read the grapheme codepoints of the cell at active-area coordinates
// (x, y), like ghostty's `page.lookupGrapheme(cell)`.
fn graphemes_at(t &Terminal, x int, y int) []u32 {
	list_cell := t.screens.active.pages.get_cell(active_point(x, y)) or { return []u32{} }
	return list_cell.node.data.lookup_grapheme(list_cell.cell) or { []u32{} }
}

// Helper: read the page style of the cell at active-area coordinates (x, y).
fn cell_style_at(t &Terminal, x int, y int) CellStyle {
	return active_cell(t, x, y).style()
}

// Helper: read the page hyperlink of the cell at active-area coordinates
// (x, y), like ghostty's `page.lookupHyperlink(cell)` plus
// `page.hyperlink_set.get(page.memory, id)`.
fn cell_hyperlink_at(t &Terminal, x int, y int) ?Hyperlink {
	list_cell := active_cell(t, x, y)
	page := &list_cell.node.data
	id := page.lookup_hyperlink(list_cell.cell) or { return none }
	return page.hyperlink_set.get(id)
}

// Helper: read whether a row (active-area y) is soft-wrapped.
fn row_wrap_at(t &Terminal, y int) bool {
	list_cell := t.screens.active.pages.get_cell(active_point(0, y)) or { return false }
	return list_cell.row.header.wrap
}

// Helper: read a row's (active-area y) semantic prompt type.
fn row_semantic_prompt_at(t &Terminal, y int) SemanticPromptType {
	list_cell := t.screens.active.pages.get_cell(active_point(0, y)) or { return .unknown }
	return list_cell.row.header.semantic_prompt
}

// ============================================================
// Basic input tests
// ============================================================

fn test_input_with_no_control_characters() {
	mut t := create_test_terminal(40, 40) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Basic grid writing
	t.print_string('hello') or { assert false }
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 5
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hello'

	// The first row should be dirty
	assert t.is_dirty(active_point(5, 0))
	assert !t.is_dirty(active_point(5, 1))
}

fn test_input_with_basic_wraparound() {
	mut t := create_test_terminal(5, 40) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Basic grid writing
	t.print_string('helloworldabc12') or { assert false }
	assert t.screens.active.cursor.y == 2
	assert t.screens.active.cursor.x == 4
	assert t.screens.active.cursor.pending_wrap
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hello\nworld\nabc12'
}

fn test_input_with_basic_wraparound_dirty() {
	mut t := create_test_terminal(5, 40) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('hello') or { assert false }
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	t.print(u32(`w`)) or { assert false }

	// The new row where 'w' was written should be dirty
	assert t.is_dirty(active_point(0, 1))
}

fn test_input_that_forces_scroll() {
	mut t := create_test_terminal(1, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Basic grid writing
	for c in 'abcdef'.runes() {
		t.print(u32(c)) or { assert false }
	}
	assert t.screens.active.cursor.y == 4
	assert t.screens.active.cursor.x == 0
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'b\nc\nd\ne\nf'
}

fn test_print_single_very_long_line() {
	// https://github.com/mitchellh/ghostty/issues/1400
	// This would crash for issue 1400. So the assertion here is
	// that we simply do not crash.
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	for _ in 0 .. 1000 {
		t.print(u32(`x`)) or { assert false }
	}
}

// ============================================================
// Linefeed and carriage return
// ============================================================

fn test_linefeed_and_carriage_return() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Print and CR.
	t.print_string('hello') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }

	t.print_string('world') or { assert false }
	assert t.screens.active.cursor.y == 1
	assert t.screens.active.cursor.x == 5
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hello\nworld'
}

fn test_linefeed_unsets_pending_wrap() {
	mut t := create_test_terminal(5, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Basic grid writing
	t.print_string('hello') or { assert false }
	assert t.screens.active.cursor.pending_wrap == true
	t.linefeed() or { assert false }
	assert t.screens.active.cursor.pending_wrap == false
}

fn test_linefeed_mode_automatic_carriage_return() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Basic grid writing
	t.modes.set(.linefeed, true)
	t.print_string('123456') or { assert false }
	t.linefeed() or { assert false }
	t.print(u32(`X`)) or { assert false }
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '123456\nX'
}

fn test_carriage_return_unsets_pending_wrap() {
	mut t := create_test_terminal(5, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Basic grid writing
	t.print_string('hello') or { assert false }
	assert t.screens.active.cursor.pending_wrap == true
	t.carriage_return()
	assert t.screens.active.cursor.pending_wrap == false
}

fn test_carriage_return_origin_mode_moves_to_left_margin() {
	mut t := create_test_terminal(5, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.origin, true)
	t.screens.active.cursor.x = 0
	t.scrolling_region.left = 2
	t.carriage_return()
	assert t.screens.active.cursor.x == 2
}

fn test_carriage_return_left_of_left_margin_moves_to_zero() {
	mut t := create_test_terminal(5, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.cursor.x = 1
	t.scrolling_region.left = 2
	t.carriage_return()
	assert t.screens.active.cursor.x == 0
}

fn test_carriage_return_right_of_left_margin_moves_to_left_margin() {
	mut t := create_test_terminal(5, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.cursor.x = 3
	t.scrolling_region.left = 2
	t.carriage_return()
	assert t.screens.active.cursor.x == 2
}

fn test_backspace() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// BS
	t.print_string('hello') or { assert false }
	t.backspace()
	t.print(u32(`y`)) or { assert false }
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 5
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'helly'
}

// ============================================================
// Horizontal tabs
// ============================================================

fn test_horizontal_tabs() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// HT
	t.print(u32(`1`)) or { assert false }
	t.horizontal_tab()
	assert t.screens.active.cursor.x == 8

	// HT
	t.horizontal_tab()
	assert t.screens.active.cursor.x == 16

	// HT at the end
	t.horizontal_tab()
	assert t.screens.active.cursor.x == 19
	t.horizontal_tab()
	assert t.screens.active.cursor.x == 19
}

fn test_horizontal_tabs_starting_on_tabstop() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(uint(t.screens.active.cursor.y), 9)
	t.print(u32(`X`)) or { assert false }
	t.set_cursor_pos(uint(t.screens.active.cursor.y), 9)
	t.horizontal_tab()
	t.print(u32(`A`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '        X       A'
}

fn test_horizontal_tabs_with_right_margin() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.left = 2
	t.scrolling_region.right = 5
	t.set_cursor_pos(uint(t.screens.active.cursor.y), 1)
	t.print(u32(`X`)) or { assert false }
	t.horizontal_tab()
	t.print(u32(`A`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X    A'
}

fn test_horizontal_tabs_back() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Edge of screen
	t.set_cursor_pos(uint(t.screens.active.cursor.y), 20)

	// HT back
	t.horizontal_tab_back()
	assert t.screens.active.cursor.x == 16

	// HT back
	t.horizontal_tab_back()
	assert t.screens.active.cursor.x == 8

	// HT back
	t.horizontal_tab_back()
	assert t.screens.active.cursor.x == 0
	t.horizontal_tab_back()
	assert t.screens.active.cursor.x == 0
}

fn test_horizontal_tabs_back_starting_on_tabstop() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(uint(t.screens.active.cursor.y), 9)
	t.print(u32(`X`)) or { assert false }
	t.set_cursor_pos(uint(t.screens.active.cursor.y), 9)
	t.horizontal_tab_back()
	t.print(u32(`A`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A       X'
}

fn test_tab_clear_single() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.cursor.x = 8
	t.tab_clear(.current)
	t.screens.active.cursor.x = 0
	t.horizontal_tab()
	// Skips 8, goes to 16
	assert t.screens.active.cursor.x == 16
}

fn test_tab_clear_all() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.tab_clear(.all)
	t.horizontal_tab()
	// No tabstops, goes to right edge
	assert t.screens.active.cursor.x == 19
}

// ============================================================
// Cursor positioning
// ============================================================

fn test_cursor_pos_resets_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.set_cursor_pos(1, 1)
	assert !t.screens.active.cursor.pending_wrap
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'XBCDE'
}

fn test_cursor_pos_off_the_screen() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(500, 500)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\n\n\n    X'
}

fn test_cursor_pos_relative_to_origin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.top = 2
	t.scrolling_region.bottom = 3
	t.modes.set(.origin, true)
	t.set_cursor_pos(1, 1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\nX'
}

// ============================================================
// Margins
// ============================================================

fn test_set_top_and_bottom_margin_simple() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_top_and_bottom_margin(0, 0)

	t.scroll_down(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nDEF\nGHI'
}

fn test_set_top_and_bottom_margin_top_only() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_top_and_bottom_margin(2, 0)

	t.scroll_down(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\n\nDEF\nGHI'
}

fn test_set_top_and_bottom_margin_top_and_bottom() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_top_and_bottom_margin(1, 2)

	t.scroll_down(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nGHI'
}

fn test_set_top_and_bottom_margin_top_equal_to_bottom() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	// top == bottom should be no-op
	t.set_top_and_bottom_margin(2, 2)

	t.scroll_down(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nDEF\nGHI'
}

// ============================================================
// Insert / Delete lines
// ============================================================

fn test_insert_lines_simple() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(1, 1)

	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nDEF\nGHI'
}

fn test_insert_lines_zero() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.insert_lines(0) // should be no-op
}

fn test_insert_lines_with_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('JKL') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('MNO') or { assert false }
	t.set_top_and_bottom_margin(2, 4)
	t.set_cursor_pos(2, 1)

	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\n\nDEF\nGHI\nMNO'
}

fn test_insert_lines_more_than_remaining() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('JKL') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('MNO') or { assert false }
	t.set_top_and_bottom_margin(2, 4)
	t.set_cursor_pos(2, 1)

	t.insert_lines(100)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\n\n\n\nMNO'
}

fn test_insert_lines_resets_pending_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.insert_lines(1)
	assert !t.screens.active.cursor.pending_wrap
}

fn test_delete_lines_simple() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(1, 1)

	t.delete_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'DEF\nGHI'
}

fn test_delete_lines_zero() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.delete_lines(0) // should be no-op
}

fn test_delete_lines_with_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('JKL') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('MNO') or { assert false }
	t.set_top_and_bottom_margin(2, 4)
	t.set_cursor_pos(2, 1)

	t.delete_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\nGHI\nJKL\n\nMNO'
}

fn test_delete_lines_resets_pending_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.delete_lines(1)
	assert !t.screens.active.cursor.pending_wrap
}

// Translated from ghostty: "Terminal: deleteLines resets wrap".
fn test_delete_lines_resets_soft_wrap_rows() {
	mut t := create_test_terminal(3, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`1`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('ABCDEF') or { assert false }

	t.set_top_and_bottom_margin(1, 2)
	t.set_cursor_pos(1, 1)
	t.delete_lines(1)
	t.print(u32(`X`)) or { assert false }

	assert (t.plain_string() or { '' }) == 'XBC\n\nDEF'
	for y in 0 .. int(t.rows) {
		row := active_row(&t, y)
		assert !row.header.wrap
		if y < 2 {
			assert !row.header.wrap_continuation
		}
	}
}

// ============================================================
// Scroll up / down
// ============================================================

fn test_scroll_up_simple() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(1, 1)

	t.scroll_up(1) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'DEF\nGHI'
}

fn test_scroll_down_simple() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(1, 1)

	t.scroll_down(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nDEF\nGHI'
}

// ============================================================
// Insert blanks / Delete chars / Erase chars
// ============================================================

fn test_insert_blanks() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.set_cursor_pos(1, 4)

	t.insert_blanks(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '123  45678'
}

fn test_insert_blanks_pushes_off_end() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789A') or { assert false }
	t.set_cursor_pos(1, 4)

	t.insert_blanks(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '123  45678'
}

fn test_insert_blanks_more_than_size() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789A') or { assert false }
	t.set_cursor_pos(1, 4)

	t.insert_blanks(100)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '123'
}

fn test_delete_chars() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.set_cursor_pos(1, 4)

	t.delete_chars(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '1236789'
}

fn test_delete_chars_zero_count() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.set_cursor_pos(1, 4)

	t.delete_chars(0) // should be no-op
}

fn test_delete_chars_more_than_line_width() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.set_cursor_pos(1, 4)

	// The source accepts usize and clamps to the remaining columns before any
	// narrowing. Keep this above V's signed 32-bit int range.
	t.delete_chars(uint(3_000_000_000))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '123'
}

fn test_delete_chars_resets_pending_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.delete_chars(1)
	assert !t.screens.active.cursor.pending_wrap
	t.print(u32(`X`)) or { assert false }
	assert (t.plain_string() or { panic(err) }) == 'ABCDX'
}

fn test_erase_chars_simple() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.set_cursor_pos(1, 4)

	t.erase_chars(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '123  6789'
}

fn test_erase_chars_minimum_one() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.set_cursor_pos(1, 4)

	t.erase_chars(0) // Minimum 1

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '123 56789'
}

fn test_erase_chars_beyond_screen_edge() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789A') or { assert false }
	t.set_cursor_pos(1, 8)

	t.erase_chars(uint(3_000_000_000))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '1234567'
}

fn test_erase_chars_protected_attributes_respected_with_iso() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.iso)
	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.erase_chars(2)
	assert t.plain_string() or { '' } == 'ABC'
}

fn test_erase_chars_protected_attributes_ignored_with_dec_most_recent() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.iso)
	t.print_string('ABC') or { assert false }
	t.set_protected_mode(.dec)
	t.set_protected_mode(.off)
	t.set_cursor_pos(1, 1)
	t.erase_chars(2)
	assert t.plain_string() or { '' } == '  C'
}

fn test_erase_chars_protected_attributes_ignored_with_dec_set() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.dec)
	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.erase_chars(2)
	assert t.plain_string() or { '' } == '  C'
}

fn test_protected_erases_update_managed_row_flags() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)
	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	for y in 0 .. 2 {
		t.set_cursor_pos(uint(y + 1), 1)
		t.print(u32(`x`)) or { assert false }
		t.print(0x0301) or { assert false }
		row := active_row(&t, y)
		assert row.header.grapheme
		assert row.header.hyperlink
	}
	t.screens.active.end_hyperlink()
	t.set_cursor_pos(1, 1)

	// ISO is the most recent protection mode, but these cells themselves are
	// unprotected, so both erases must clear them through clearUnprotectedCells.
	t.screens.active.protected_mode = .iso
	t.erase_chars(1)
	row0 := active_row(&t, 0)
	assert !row0.header.grapheme
	assert !row0.header.hyperlink

	t.set_cursor_pos(2, 1)
	t.erase_line(.right, false)
	row1 := active_row(&t, 1)
	assert !row1.header.grapheme
	assert !row1.header.hyperlink
}

// ============================================================
// Erase line
// ============================================================

fn test_erase_line_simple_erase_right() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('0123456789') or { assert false }
	t.set_cursor_pos(1, 6)

	t.erase_line(.right, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '01234'
}

fn test_erase_line_resets_pending_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.erase_line(.right, false)
	assert !t.screens.active.cursor.pending_wrap
}

fn test_erase_line_simple_erase_left() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('0123456789') or { assert false }
	t.set_cursor_pos(1, 6)

	t.erase_line(.left, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '      6789'
}

// ============================================================
// Erase display
// ============================================================

fn test_erase_display_simple_erase_below() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(2, 1)

	t.erase_display(.below, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC'
}

fn test_erase_display_simple_erase_above() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(2, 2)

	t.erase_display(.above, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n  F\nGHI'
}

fn test_erase_display_complete_preserves_cursor() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.set_cursor_pos(2, 2)
	old_x := t.screens.active.cursor.x
	old_y := t.screens.active.cursor.y

	t.erase_display(.complete, false)

	// Cursor should be preserved
	assert t.screens.active.cursor.x == old_x
	assert t.screens.active.cursor.y == old_y

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ''
}

// ============================================================
// Index / Reverse Index
// ============================================================

fn test_index() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.index() or { assert false }
	assert t.screens.active.cursor.y == 1
}

fn test_index_from_the_bottom() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('JKL') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('MNO') or { assert false }

	// At bottom, index should scroll
	t.index() or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'DEF\nGHI\nJKL\nMNO'
}

fn test_reverse_index() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(1, 1)

	// At top, reverse_index should scroll down
	t.reverse_index()

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nDEF\nGHI'
}

// ============================================================
// Cursor movement
// ============================================================

fn test_cursor_up_basic() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(3, 1)
	t.cursor_up(1)
	assert t.screens.active.cursor.y == 1
}

fn test_cursor_up_below_top_scroll_margin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.top = 2
	t.set_cursor_pos(4, 1)
	t.cursor_up(5)
	// Should stop at top margin (row 2)
	assert t.screens.active.cursor.y == 2
}

fn test_cursor_up_above_top_scroll_margin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.top = 2
	t.set_cursor_pos(2, 1)
	t.cursor_up(5)
	// Above margin, should stop at row 0
	assert t.screens.active.cursor.y == 0
}

fn test_cursor_up_resets_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.cursor_up(1)
	assert !t.screens.active.cursor.pending_wrap
}

fn test_cursor_down_basic() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.cursor_down(2)
	assert t.screens.active.cursor.y == 2
}

fn test_cursor_down_above_bottom_scroll_margin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.bottom = 2
	t.cursor_down(10)
	// Should stop at bottom margin (row 2)
	assert t.screens.active.cursor.y == 2
}

fn test_cursor_down_below_bottom_scroll_margin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.bottom = 2
	t.set_cursor_pos(4, 1) // row 3, below margin
	t.cursor_down(10)
	// Below margin, should stop at bottom of screen (row 4)
	assert t.screens.active.cursor.y == 4
}

fn test_cursor_down_resets_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.cursor_down(1)
	assert !t.screens.active.cursor.pending_wrap
}

fn test_cursor_right_resets_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.cursor_right(1)
	assert !t.screens.active.cursor.pending_wrap
}

fn test_cursor_right_to_the_edge_of_screen() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.cursor_right(10)
	assert t.screens.active.cursor.x == 4
}

fn test_cursor_left_no_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(1, 4)
	t.cursor_left(2)
	assert t.screens.active.cursor.x == 1
}

fn test_cursor_left_unsets_pending_wrap_state() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.cursor_left(1)
	assert !t.screens.active.cursor.pending_wrap
	// In no-wrap mode (default for cursor_left without reverse wrap),
	// pending_wrap is cleared and cursor moves left by 1 from x=4
	assert t.screens.active.cursor.x == 3
}

fn test_cursor_operations_clamp_pointer_width_inputs_before_narrowing() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	large := uint(65_536)
	t.set_cursor_pos(3, 3)
	t.cursor_up(large)
	assert t.screens.active.cursor.y == 0
	t.cursor_down(large)
	assert t.screens.active.cursor.y == 4
	t.cursor_right(large)
	assert t.screens.active.cursor.x == 4
	t.cursor_left(large)
	assert t.screens.active.cursor.x == 0

	// Positioning accepts the source's full usize domain and clamps before
	// converting to the terminal's compact row/column representation.
	t.set_cursor_pos(~uint(0), ~uint(0))
	assert t.screens.active.cursor.x == 4
	assert t.screens.active.cursor.y == 4
}

// ============================================================
// Save / Restore cursor
// ============================================================

fn test_save_cursor() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(2, 5)
	t.save_cursor()
	t.set_cursor_pos(1, 1)
	t.restore_cursor()
	assert t.screens.active.cursor.x == 4
	assert t.screens.active.cursor.y == 1
}

fn test_save_cursor_pending_wrap_state() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.save_cursor()
	t.set_cursor_pos(1, 1)
	assert !t.screens.active.cursor.pending_wrap
	t.restore_cursor()
	assert t.screens.active.cursor.pending_wrap
}

fn test_save_cursor_origin_mode() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.origin, true)
	t.save_cursor()
	t.modes.set(.origin, false)
	t.restore_cursor()
	assert t.modes.get(.origin) == true
}

// ============================================================
// Protected mode
// ============================================================

fn test_set_protected_mode() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.iso)
	assert t.screens.active.cursor.is_protected
	assert t.screens.active.protected_mode == .iso
	t.set_protected_mode(.off)
	assert !t.screens.active.cursor.is_protected
	// screen.protected_mode is NOT reset to .off
	assert t.screens.active.protected_mode == .iso
}

// ============================================================
// Print repeat
// ============================================================

fn test_print_repeat_simple() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.print_repeat(3) or { assert false }
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AAAA'
}

fn test_print_repeat_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.print_repeat(7) or { assert false }
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AAAAA\nAAA'
}

fn test_print_repeat_no_previous_character() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_repeat(3) or { assert false }
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 0
}

// ============================================================
// DECALN
// ============================================================

fn test_decaln() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.decaln() or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'EEEEE\nEEEEE\nEEEEE\nEEEEE\nEEEEE'
}

fn test_decaln_reset_margins() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_top_and_bottom_margin(2, 5)
	t.decaln() or { assert false }

	// Margins should be reset
	assert t.scrolling_region.top == 0
	assert t.scrolling_region.bottom == t.rows - 1
	assert t.scrolling_region.left == 0
	assert t.scrolling_region.right == t.cols - 1
}

fn test_decaln_preserves_color() {
	mut t := create_test_terminal(3, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xff } }) or { assert false }
	t.modes.set(.origin, true)
	t.set_top_and_bottom_margin(2, 3)
	t.decaln() or { assert false }
	t.scroll_down(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nEEE\nEEE'
	cell := cell_at(&t, 0, 0)
	assert cell.content_tag == .bg_color_rgb
	assert cell.color_rgb_r() == 0xff
	assert cell.color_rgb_g() == 0
	assert cell.color_rgb_b() == 0
}

fn test_decaln_resets_graphemes_with_protected_mode() {
	mut t := create_test_terminal(3, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Add protected mode. DECALN must ignore protection while retaining the
	// cursor's protected state for subsequent writes.
	t.set_protected_mode(.iso)
	t.modes.set(.grapheme_cluster, true)
	for cp in [u32(0x1f468), 0x200d, 0x1f469, 0x200d, 0x1f467] {
		t.print(cp) or { assert false }
	}
	assert active_row(&t, 0).header.grapheme

	t.decaln() or { assert false }

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.is_protected
	assert t.screens.active.protected_mode == .iso
	for y in 0 .. int(t.rows) {
		row := active_row(&t, y)
		assert row.header.dirty
		assert !row.header.grapheme
		for cell in row.cells {
			assert cell.codepoint() == u32(`E`)
			assert !cell.has_grapheme()
			assert !cell.is_protected
		}
	}
}

fn test_decaln_clears_non_color_attributes() {
	mut t := create_test_terminal(2, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_attribute(SgrBold{}) or { assert false }
	t.set_attribute(SgrUnderline{ style: .single }) or { assert false }
	t.set_attribute(SgrDirectColorFg{ rgb: RGB{ r: 0x12, g: 0x34, b: 0x56 } }) or { assert false }
	t.decaln() or { assert false }

	assert !t.screens.active.cursor.style.flags.bold()
	assert t.screens.active.cursor.style.flags.underline() == .none
	style := cell_style_at(&t, 0, 0)
	assert style.fg_color is StyleColorRgb
	rgb := (style.fg_color as StyleColorRgb).rgb
	assert rgb.r == 0x12
	assert rgb.g == 0x34
	assert rgb.b == 0x56
	assert !style.flags.bold()
	assert style.flags.underline() == .none
}

// ============================================================
// DECCOLM
// ============================================================

fn test_deccolm_without_dec_mode_40() {
	mut t := create_test_terminal(80, 24) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Without mode 40, should be ignored
	t.deccolm(.cols_132) or { assert false }
	assert t.cols == 80
}

fn test_deccolm_unset() {
	mut t := create_test_terminal(132, 24) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.enable_mode_3, true)
	t.deccolm(.cols_80) or { assert false }
	assert t.cols == 80
}

fn test_deccolm_resets_scroll_region() {
	mut t := create_test_terminal(80, 24) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.enable_mode_3, true)
	t.set_top_and_bottom_margin(5, 10)
	t.deccolm(.cols_132) or { assert false }

	assert t.scrolling_region.top == 0
	assert t.scrolling_region.bottom == t.rows - 1
}

// ============================================================
// Full reset
// ============================================================

fn test_full_reset_with_a_non_empty_pen() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_attribute(SgrBold{}) or { assert false }
	t.print_string('A') or { assert false }
	t.full_reset()

	// Style should be reset
	assert !t.screens.active.cursor.style.flags.bold()
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ''
}

fn test_full_reset_hyperlink() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	assert t.screens.active.cursor.hyperlink_id != 0
	t.full_reset()
	assert t.screens.active.cursor.hyperlink_id == 0
}

fn test_full_reset_with_a_non_empty_saved_cursor() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_attribute(SgrDirectColorFg{ rgb: RGB{ r: 255, b: 127 } }) or { assert false }
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 255, b: 127 } }) or { assert false }
	t.save_cursor()
	assert t.screens.active.saved_cursor != none
	t.full_reset()
	assert t.screens.active.saved_cursor == none
	assert t.screens.active.cursor.style_id == default_style_id
}

fn test_full_reset_origin_mode() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.origin, true)
	t.full_reset()
	assert !t.modes.get(.origin)
}

fn test_full_reset_status_display() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.status_display = .status_line
	t.full_reset()
	assert t.status_display == .main
}

fn test_full_reset_clears_alternate_screen_kitty_keyboard_state() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.switch_screen_mode(.mode_1049, true) or { assert false }
	t.screens.active.kitty_keyboard.push(KeyFlags.from_int(0b1_1111))
	assert t.screens.active.kitty_keyboard.current() == key_flags_all
	t.switch_screen_mode(.mode_1049, false) or { assert false }

	t.full_reset()
	assert t.screens.get(.alternate) == none
}

fn test_full_reset_default_modes() {
	mut defaults := build_default_modes()
	defaults.data |= mode_mask(.grapheme_cluster)
	mut t := Terminal.init(Options{
		cols:          10
		rows:          10
		default_modes: defaults
	}) or {
		assert false
		return
	}
	defer { t.deinit() }

	assert t.modes.get(.grapheme_cluster)
	t.modes.set(.grapheme_cluster, false)
	t.full_reset()
	assert t.modes.get(.grapheme_cluster)
}

// ============================================================
// Resize
// ============================================================

fn test_resize_less_cols_with_print() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDEFGH') or { assert false }
	t.resize(5, 5) or { assert false }
	t.print(u32(`X`)) or { assert false }

	// Should not crash
	assert t.cols == 5
}

fn test_resize_with_left_and_right_margin_set() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(3, 5)
	t.resize(5, 5) or { assert false }

	// Margins should be reset
	assert t.scrolling_region.left == 0
	assert t.scrolling_region.right == 4
}

fn test_resize_clears_redrawable_prompt_on_primary_screen() {
	mut t := create_test_terminal(10, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE\n') or { assert false }
	mut primary := t.screens.get(.primary) or { panic('primary screen must be initialized') }
	primary.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	t.print_string('> ') or { assert false }
	primary.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_eol })
	t.print_string('echo') or { assert false }
	assert t.plain_string() or { '' } == 'ABCDE\n> echo'

	t.flags.set_shell_redraws_prompt(.redraw_true)
	t.resize(20, 3) or { assert false }

	assert primary.cursor.x == 6
	assert primary.cursor.y == 1
	assert t.plain_string() or { '' } == 'ABCDE'
}

fn test_resize_clears_redrawable_prompt_on_inactive_primary_screen() {
	mut t := create_test_terminal(10, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE\n') or { assert false }
	mut primary := t.screens.get(.primary) or { panic('primary screen must be initialized') }
	primary.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	t.print_string('> ') or { assert false }
	primary.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_eol })
	t.print_string('echo') or { assert false }
	assert t.plain_string() or { '' } == 'ABCDE\n> echo'

	t.switch_screen_mode(.mode_47, true) or { assert false }
	assert t.screens.active_key == .alternate
	t.flags.set_shell_redraws_prompt(.redraw_true)
	t.resize(20, 3) or { assert false }
	t.switch_screen_mode(.mode_47, false) or { assert false }

	assert t.screens.active_key == .primary
	assert t.plain_string() or { '' } == 'ABCDE'
}

// ------------------------------------------------------------
// resize-with-reflow tests (from ghostty Terminal.zig)
// ------------------------------------------------------------

fn test_resize_less_cols_with_wide_char_then_print() {
	mut t := Terminal.init(Options{ cols: 3, rows: 3 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)

	t.print(u32(`x`)) or { assert false }
	t.print(u32(`😀`)) or { assert false } // 0x1F600
	t.resize(2, 3) or { assert false }
	t.set_cursor_pos(1, 2)
	t.print(u32(`😀`)) or { assert false } // 0x1F600

	// Should not crash
	assert t.cols == 2
}

fn test_resize_less_cols_eliminates_wide_char_that_cannot_fit() {
	mut t := Terminal.init(Options{ cols: 2, rows: 1, max_scrollback: 0 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)
	t.print(u32(`😀`)) or { assert false }
	assert (t.plain_string() or { '' }) == '😀'
	assert cell_at(&t, 0, 0).wide == .wide

	t.resize(1, 1) or { assert false }

	assert (t.plain_string() or { 'unexpected' }) == ''
	cell := cell_at(&t, 0, 0)
	assert cell.codepoint == 0
	assert cell.wide == .narrow
}

fn test_resize_less_cols_wraps_wide_char() {
	mut t := Terminal.init(Options{ cols: 3, rows: 3, max_scrollback: 0 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)
	t.print(u32(`x`)) or { assert false }
	t.print(u32(`😀`)) or { assert false }
	assert (t.plain_string() or { '' }) == 'x😀'

	t.resize(2, 3) or { assert false }

	assert (t.plain_string() or { '' }) == 'x\n😀'
	assert cell_at(&t, 1, 0).wide == .spacer_head
	assert active_row(&t, 0).header.wrap
	assert cell_at(&t, 0, 1).wide == .wide
	assert cell_at(&t, 1, 1).wide == .spacer_tail
}

fn test_resize_more_cols_unwraps_wide_spacer_head() {
	mut t := Terminal.init(Options{ cols: 3, rows: 2, max_scrollback: 0 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)
	t.print_string('  ') or { assert false }
	t.print(u32(`😀`)) or { assert false }
	assert (t.plain_string() or { '' }) == '  \n😀'
	assert cell_at(&t, 2, 0).wide == .spacer_head

	t.resize(4, 2) or { assert false }

	assert (t.plain_string() or { '' }) == '  😀'
	assert cell_at(&t, 2, 0).wide == .wide
	assert cell_at(&t, 3, 0).wide == .spacer_tail
}

fn test_resize_more_cols_unwraps_wide_spacer_head_multiple_lines() {
	mut t := Terminal.init(Options{ cols: 3, rows: 3, max_scrollback: 0 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)
	t.print_string('xxxyy') or { assert false }
	t.print(u32(`😀`)) or { assert false }
	assert (t.plain_string() or { '' }) == 'xxx\nyy\n😀'
	assert cell_at(&t, 2, 1).wide == .spacer_head

	t.resize(8, 2) or { assert false }

	assert (t.plain_string() or { '' }) == 'xxxyy😀'
	assert cell_at(&t, 5, 0).wide == .wide
	assert cell_at(&t, 6, 0).wide == .spacer_tail
}

fn test_resize_more_cols_preserves_required_wide_spacer_head() {
	mut t := Terminal.init(Options{ cols: 2, rows: 2, max_scrollback: 0 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)
	t.print_string('xx') or { assert false }
	t.print(u32(`😀`)) or { assert false }
	assert (t.plain_string() or { '' }) == 'xx\n😀'

	t.resize(3, 2) or { assert false }

	assert (t.plain_string() or { '' }) == 'xx\n😀'
	assert cell_at(&t, 2, 0).wide == .spacer_head
	assert cell_at(&t, 0, 1).wide == .wide
	assert cell_at(&t, 1, 1).wide == .spacer_tail
}

fn test_resize_reflow_preserves_kitty_unicode_placeholder_row_flag() {
	mut t := Terminal.init(Options{ cols: 3, rows: 2, max_scrollback: 0 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)
	t.print(kitty_unicode_placeholder) or { assert false }
	t.print_string('ab') or { assert false }
	assert active_row(&t, 0).header.kitty_virtual_placeholder

	t.resize(2, 2) or { assert false }

	assert cell_at(&t, 0, 0).codepoint == kitty_unicode_placeholder
	assert active_row(&t, 0).header.kitty_virtual_placeholder
}

// https://github.com/mitchellh/ghostty/issues/723
// This was found via fuzzing so its highly specific.
fn test_resize_with_left_and_right_margin_set_fuzz() {
	cols := u16(70)
	rows := u16(23)
	mut t := Terminal.init(Options{ cols: cols, rows: rows }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)

	t.modes.set(.enable_left_and_right_margin, true)
	t.print(u32(`0`)) or { assert false }
	t.modes.set(.enable_mode_3, true)
	t.resize(cols, rows) or { assert false }
	t.set_left_and_right_margin(2, 0)
	t.print_repeat(1850) or { assert false }
	t.modes.restore(.enable_mode_3)
	t.resize(cols, rows) or { assert false }

	// Should not crash
	assert t.cols == cols
}

// https://github.com/mitchellh/ghostty/issues/1343
fn test_resize_with_wraparound_off() {
	cols := u16(4)
	rows := u16(2)
	mut t := Terminal.init(Options{ cols: cols, rows: rows }) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, false)
	t.print(u32(`0`)) or { assert false }
	t.print(u32(`1`)) or { assert false }
	t.print(u32(`2`)) or { assert false }
	t.print(u32(`3`)) or { assert false }
	new_cols := u16(2)
	t.resize(new_cols, rows) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '01'
}

fn test_resize_with_wraparound_on() {
	cols := u16(4)
	rows := u16(2)
	mut t := Terminal.init(Options{ cols: cols, rows: rows }) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.print(u32(`0`)) or { assert false }
	t.print(u32(`1`)) or { assert false }
	t.print(u32(`2`)) or { assert false }
	t.print(u32(`3`)) or { assert false }
	new_cols := u16(2)
	t.resize(new_cols, rows) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '01\n23'
}

fn test_resize_with_high_unique_style_per_cell() {
	mut t := Terminal.init(Options{ cols: 30, rows: 30 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)

	for y in 0 .. int(t.rows) {
		for x in 0 .. int(t.cols) {
			t.set_cursor_pos(y, x)
			t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: u8(x), g: u8(y), b: 0 } }) or { assert false }
			t.print(u32(`x`)) or { assert false }
		}
	}

	t.resize(60, 30) or { assert false }

	// Should not crash
	assert t.cols == 60
}

fn test_resize_with_high_unique_style_per_cell_with_wrapping() {
	mut t := Terminal.init(Options{ cols: 30, rows: 30 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)

	cell_count := int(t.rows) * int(t.cols)
	for i in 0 .. cell_count {
		r := u8(i >> 8)
		g := u8(i & 0xFF)
		t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: r, g: g, b: 0 } }) or { assert false }
		t.print(u32(`x`)) or { assert false }
	}

	t.resize(60, 30) or { assert false }

	// Should not crash
	assert t.cols == 60
}

fn test_resize_with_reflow_and_saved_cursor() {
	mut t := Terminal.init(Options{ cols: 2, rows: 3 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)

	t.print_string('1A2B') or { assert false }
	t.set_cursor_pos(2, 2)
	{
		cell := cell_at(&t, int(t.screens.active.cursor.x), int(t.screens.active.cursor.y))
		assert cell.codepoint == u32(`B`)
	}
	{
		str := t.plain_string() or {
			assert false
			return
		}
		assert str == '1A\n2B'
	}

	t.save_cursor()
	t.resize(5, 3) or { assert false }
	t.restore_cursor()

	{
		str := t.plain_string() or {
			assert false
			return
		}
		assert str == '1A2B'
	}

	// Verify our cursor is still in the same place
	{
		cell := cell_at(&t, int(t.screens.active.cursor.x), int(t.screens.active.cursor.y))
		assert cell.codepoint == u32(`B`)
	}
}

fn test_resize_with_reflow_and_saved_cursor_pending_wrap() {
	mut t := Terminal.init(Options{ cols: 2, rows: 3 }) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.wraparound, true)

	t.print_string('1A2B') or { assert false }
	{
		cell := cell_at(&t, int(t.screens.active.cursor.x), int(t.screens.active.cursor.y))
		assert cell.codepoint == u32(`B`)
	}
	{
		str := t.plain_string() or {
			assert false
			return
		}
		assert str == '1A\n2B'
	}

	t.save_cursor()
	t.resize(5, 3) or { assert false }
	t.restore_cursor()

	{
		str := t.plain_string() or {
			assert false
			return
		}
		assert str == '1A2B'
	}

	// Pending wrap should be reset
	t.print(u32(`X`)) or { assert false }
	{
		str := t.plain_string() or {
			assert false
			return
		}
		assert str == '1A2BX'
	}
}

// ============================================================
// Screen switching
// ============================================================

fn test_switch_screen_returns_optional_previous_screen() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	unchanged := t.switch_screen(.primary) or { panic(err) }
	assert unchanged.previous == none

	switched := t.switch_screen(.alternate) or { panic(err) }
	previous := switched.previous or {
		assert false, 'switch must return the primary screen'
		return
	}
	primary := t.screens.get(.primary) or { panic('missing primary screen') }
	assert voidptr(previous) == voidptr(primary)
	assert t.screens.active_key == .alternate

	unchanged_alt := t.switch_screen(.alternate) or { panic(err) }
	assert unchanged_alt.previous == none
	_ = t.switch_screen(.primary) or { panic(err) }
}

fn test_mode_47_alt_screen_plain() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Print on primary screen
	t.print_string('1A') or { assert false }

	// Go to alt screen with mode 47
	t.switch_screen_mode(.mode_47, true) or { assert false }
	assert t.screens.active_key == .alternate

	// Screen should be empty
	empty := t.plain_string() or {
		assert false
		return
	}
	assert empty == ''

	// Print on alt screen. This should be off center because we copy
	// the cursor over from the primary screen (matches Ghostty / xterm).
	t.print_string('2B') or { assert false }
	alt_str := t.plain_string() or {
		assert false
		return
	}
	assert alt_str == '  2B'

	// Switch back to primary
	t.switch_screen_mode(.mode_47, false) or { assert false }
	assert t.screens.active_key == .primary

	// Primary screen should still have the original content
	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '1A'

	// Go back to alt screen with mode 47; it should retain content
	t.switch_screen_mode(.mode_47, true) or { assert false }
	assert t.screens.active_key == .alternate
	retained := t.plain_string() or {
		assert false
		return
	}
	assert retained == '  2B'
}

fn test_mode_47_copies_cursor_style_both_directions() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_attribute(SgrDirectColorFg{ rgb: RGB{ r: 255, b: 127 } }) or {
		assert false
	}
	t.switch_screen_mode(.mode_47, true) or { assert false }
	assert t.screens.active_key == .alternate
	assert t.screens.active.cursor.style_id != default_style_id
	assert t.screens.active.cursor.style.fg_color is StyleColorRgb
	alt_rgb := (t.screens.active.cursor.style.fg_color as StyleColorRgb).rgb
	assert alt_rgb.r == 255
	assert alt_rgb.b == 127

	t.set_attribute(SgrDirectColorFg{ rgb: RGB{ g: 255 } }) or { assert false }
	t.switch_screen_mode(.mode_47, false) or { assert false }
	assert t.screens.active_key == .primary
	assert t.screens.active.cursor.style_id != default_style_id
	assert t.screens.active.cursor.style.fg_color is StyleColorRgb
	primary_rgb := (t.screens.active.cursor.style.fg_color as StyleColorRgb).rgb
	assert primary_rgb.r == 0
	assert primary_rgb.g == 255
}

fn test_mode_1047_alt_screen_plain() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('1A') or { assert false }
	t.switch_screen_mode(.mode_1047, true) or { assert false }
	assert t.screens.active_key == .alternate
	assert t.plain_string() or { '' } == ''

	t.print_string('2B') or { assert false }
	assert t.plain_string() or { '' } == '  2B'

	t.switch_screen_mode(.mode_1047, false) or { assert false }
	assert t.screens.active_key == .primary
	assert t.plain_string() or { '' } == '1A'

	// Unlike mode 47, mode 1047 clears the alternate screen on exit.
	t.switch_screen_mode(.mode_1047, true) or { assert false }
	assert t.screens.active_key == .alternate
	assert t.plain_string() or { 'not empty' } == ''
}

fn test_mode_1047_copies_cursor_style_both_directions() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_attribute(SgrDirectColorFg{ rgb: RGB{ r: 255, b: 127 } }) or {
		assert false
	}
	t.switch_screen_mode(.mode_1047, true) or { assert false }
	assert t.screens.active.cursor.style.fg_color is StyleColorRgb
	alt_rgb := (t.screens.active.cursor.style.fg_color as StyleColorRgb).rgb
	assert alt_rgb.r == 255
	assert alt_rgb.b == 127

	t.set_attribute(SgrDirectColorFg{ rgb: RGB{ g: 255 } }) or { assert false }
	t.switch_screen_mode(.mode_1047, false) or { assert false }
	assert t.screens.active_key == .primary
	assert t.screens.active.cursor.style.fg_color is StyleColorRgb
	primary_rgb := (t.screens.active.cursor.style.fg_color as StyleColorRgb).rgb
	assert primary_rgb.r == 0
	assert primary_rgb.g == 255
}

fn test_mode_1049_alt_screen_plain() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('Hello') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('World') or { assert false }

	// Mode 1049 saves cursor on enable
	t.switch_screen_mode(.mode_1049, true) or { assert false }
	assert t.screens.active_key == .alternate

	// Write on alternate
	t.print_string('Alt') or { assert false }

	// Switch back - restores cursor
	t.switch_screen_mode(.mode_1049, false) or { assert false }
	assert t.screens.active_key == .primary

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'Hello\nWorld'
}

fn test_mode_1049_restores_primary_cursor_and_clears_on_entry() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('1A') or { assert false }
	t.switch_screen_mode(.mode_1049, true) or { assert false }
	assert t.screens.active_key == .alternate
	assert t.plain_string() or { 'not empty' } == ''

	t.print_string('2B') or { assert false }
	assert t.plain_string() or { '' } == '  2B'
	t.switch_screen_mode(.mode_1049, false) or { assert false }
	assert t.screens.active_key == .primary
	assert t.plain_string() or { '' } == '1A'

	// The primary cursor was saved before entry and restored on exit.
	t.print_string('C') or { assert false }
	assert t.plain_string() or { '' } == '1AC'

	// Every mode 1049 entry clears the alternate screen.
	t.switch_screen_mode(.mode_1049, true) or { assert false }
	assert t.screens.active_key == .alternate
	assert t.plain_string() or { 'not empty' } == ''
}

// ============================================================
// PWD
// ============================================================

fn test_set_get_pwd() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	assert t.get_pwd() == none
	t.set_pwd('/home/user') or { assert false }
	pwd := t.get_pwd() or {
		assert false
		return
	}
	assert pwd == '/home/user'
}

// ============================================================
// Cursor is at prompt
// ============================================================

fn test_cursor_is_at_prompt() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// By default, cursor is at output
	assert !t.cursor_is_at_prompt()

	// Set semantic content to prompt
	t.screens.active.cursor.semantic_content = .prompt
	assert t.cursor_is_at_prompt()

	// Set to input
	t.screens.active.cursor.semantic_content = .input
	assert t.cursor_is_at_prompt()

	// Set to output
	t.screens.active.cursor.semantic_content = .output
	assert !t.cursor_is_at_prompt()
}

fn test_cursor_is_at_prompt_alternate_screen() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// On alternate screen, never at prompt
	t.switch_screen_mode(.mode_47, true) or { assert false }
	t.screens.active.cursor.semantic_content = .prompt
	assert !t.cursor_is_at_prompt()
}

// ============================================================
// Dirty / clear dirty
// ============================================================

fn test_terminal_dirty_packed_layout() {
	mut dirty := Dirty.init(true, true, true, true)
	assert sizeof(Dirty) == 1
	assert dirty.int() == 0b1111
	dirty.set_palette(false)
	dirty.set_preedit(false)
	assert dirty.int() == 0b0110
	assert !dirty.palette()
	assert dirty.reverse_colors()
	assert dirty.clear()
	assert !dirty.preedit()
}

fn test_terminal_flags_packed_layout_and_defaults() {
	mut flags := TerminalFlags{}
	assert sizeof(TerminalFlags) == 4
	assert sizeof(MouseShiftCaptureState) == 1
	assert flags.int() == u32(1 << 11)
	assert flags.shell_redraws_prompt() == .redraw_true
	assert !flags.modify_other_keys_2()
	assert flags.mouse_event() == .none
	assert flags.mouse_format() == .x10
	assert flags.mouse_shift_capture() == .null_
	assert flags.focused()
	assert !flags.password_input()
	assert !flags.selection_scroll()
	assert !flags.search_viewport_dirty()
	assert flags.dirty().int() == 0

	flags.set_shell_redraws_prompt(.last)
	flags.set_modify_other_keys_2(true)
	flags.set_mouse_event(.any)
	flags.set_mouse_format(.sgr_pixels)
	flags.set_mouse_shift_capture(.true_)
	flags.set_focused(false)
	flags.set_password_input(true)
	flags.set_selection_scroll(true)
	flags.set_search_viewport_dirty(true)
	flags.set_dirty(Dirty.init(true, true, true, true))
	assert flags.int() == u32(2 | (1 << 2) | (4 << 3) | (4 << 6) | (2 << 9) | (1 << 12) | (1 << 13) | (1 << 14) | (0b1111 << 15))
}

fn test_screen_dirty_packed_layout() {
	mut dirty := ScreenDirty.init(true, true)
	assert sizeof(ScreenDirty) == 1
	assert dirty.int() == 0b11
	dirty.set_selection(false)
	assert dirty.int() == 0b10
	assert !dirty.selection()
	assert dirty.hyperlink_hover()
}

fn test_is_dirty_and_clear() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('Hello') or { assert false }
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	assert !t.is_dirty(active_point(0, 0))
}

// ============================================================
// Print attributes
// ============================================================

fn test_print_attributes() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Default attributes
	result := t.print_attributes() or {
		assert false
		return
	}
	assert result == '0'

	// Bold
	t.set_attribute(SgrBold{}) or { assert false }
	result2 := t.print_attributes() or {
		assert false
		return
	}
	assert result2 == '0;1'

	// Bold + italic
	t.set_attribute(SgrItalic{}) or { assert false }
	result3 := t.print_attributes() or {
		assert false
		return
	}
	assert result3 == '0;1;3'
}

// ============================================================
// Soft wrap
// ============================================================

fn test_soft_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('helloworld') or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hello\nworld'
}

fn test_soft_wrap_with_semantic_prompt() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Mark the cursor as prompt
	t.screens.active.cursor.semantic_content = .prompt

	t.print_string('helloworld') or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hello\nworld'
}

// Translated from ghostty: "Terminal: index in prompt mode marks new row as
// prompt continuation". This tests the Fish shell workaround: when in prompt
// mode and we get a newline, assume the new row is a prompt continuation
// (since Fish doesn't emit OSC133 k=s markers for continuation lines).
fn test_index_in_prompt_mode_marks_new_row_as_prompt_continuation() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Start a prompt.
	t.semantic_prompt(osc.SemanticPrompt.init(.fresh_line_new_prompt))
	for c in 'hello' {
		t.print(u32(c)) or { assert false }
	}

	// Verify first row is marked as prompt.
	assert row_semantic_prompt_at(t, 0) == .prompt

	// Now do a linefeed while still in prompt mode.
	t.carriage_return()
	t.linefeed() or { assert false }

	// The new row should automatically be marked as prompt continuation.
	assert row_semantic_prompt_at(t, 1) == .prompt_continuation

	// The cursor semantic content should still be prompt.
	assert t.screens.active.cursor.semantic_content == .prompt
}

// Translated from ghostty: "Terminal: index in input mode does not mark new
// row as prompt". Despite the ghostty test name, input mode DOES mark the new
// row as a prompt continuation on newline (only output mode does not).
fn test_index_in_input_mode_marks_new_row_as_prompt_continuation() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Start a prompt then switch to input.
	t.semantic_prompt(osc.SemanticPrompt.init(.fresh_line_new_prompt))
	for c in '\$ ' {
		t.print(u32(c)) or { assert false }
	}
	t.semantic_prompt(osc.SemanticPrompt.init(.end_prompt_start_input))
	for c in 'echo \\' {
		t.print(u32(c)) or { assert false }
	}

	// Linefeed while in input mode.
	t.carriage_return()
	t.linefeed() or { assert false }

	// The new row should be marked as prompt continuation.
	assert row_semantic_prompt_at(t, 1) == .prompt_continuation

	// Our cursor should still be in input.
	assert t.screens.active.cursor.semantic_content == .input
}

// Translated from ghostty: "Terminal: index in output mode does not mark new
// row as prompt". Output mode should NOT trigger prompt continuation.
fn test_index_in_output_mode_does_not_mark_new_row_as_prompt() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Complete prompt cycle: prompt -> input -> output.
	t.semantic_prompt(osc.SemanticPrompt.init(.fresh_line_new_prompt))
	for c in '\$ ' {
		t.print(u32(c)) or { assert false }
	}
	t.semantic_prompt(osc.SemanticPrompt.init(.end_prompt_start_input))
	for c in 'ls' {
		t.print(u32(c)) or { assert false }
	}
	t.semantic_prompt(osc.SemanticPrompt.init(.end_input_start_output))

	// Linefeed while in output mode.
	t.carriage_return()
	t.linefeed() or { assert false }

	// The new row should NOT be marked as a prompt. Witty's default row
	// semantic prompt is `.unknown` (ghostty uses `.none`).
	assert row_semantic_prompt_at(t, 1) == .unknown
}

// ============================================================
// Mode state tests
// ============================================================

fn test_mode_state_set_get() {
	mut ms := ModeState{}

	assert !ms.get(.wraparound)
	ms.set(.wraparound, true)
	assert ms.get(.wraparound)

	ms.set(.origin, true)
	assert ms.get(.origin)
	assert ms.get(.wraparound)

	ms.set(.wraparound, false)
	assert !ms.get(.wraparound)
	assert ms.get(.origin)
}

fn test_mode_state_reset() {
	mut ms := ModeState{}
	ms.default.data = mode_mask(.wraparound)

	ms.set(.origin, true)
	ms.set(.wraparound, false)
	ms.reset()

	assert ms.get(.wraparound) // restored from default
	assert !ms.get(.origin) // not in default
}

// ============================================================
// Tabstops
// ============================================================

fn test_tabstops_init() {
	ts := Tabstops.init(80, 8) or {
		assert false
		return
	}
	assert !ts.get(0)
	assert !ts.get(1)
	assert !ts.get(7)
	assert ts.get(8)
	assert ts.get(16)
	assert ts.get(24)
}

fn test_tabstops_set_unset() {
	mut ts := Tabstops.init(80, 8) or {
		assert false
		return
	}
	assert !ts.get(0)
	ts.set(0)
	assert ts.get(0)
	ts.unset(0)
	assert !ts.get(0)
	ts.set(5)
	assert ts.get(5)
}

fn test_tabstops_reset() {
	mut ts := Tabstops.init(80, 8) or {
		assert false
		return
	}
	ts.unset(8)
	ts.unset(16)
	ts.reset(8)
	assert !ts.get(0)
	assert ts.get(8)
	assert ts.get(16)
}

// ============================================================
// DynamicRGB struct (defined in color.v)
// ============================================================

fn test_dynamic_rgb() {
	a := DynamicRGB{}
	b := DynamicRGB{
		override_color: RGB{ r: 255, g: 0, b: 0 }
	}

	assert a.get() == none
	rgb := b.get() or {
		assert false, 'expected color'
		return
	}
	assert rgb.r == 255
}

// ============================================================
// Wide char tests (real unicode width detection)
// ============================================================

fn test_print_wide_char() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x1F600) or { assert false } // Smiley face
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x1F600
	assert c0.wide == .wide
	c1 := cell_at(&t, 1, 0)
	assert c1.wide == .spacer_tail

	assert t.is_dirty(active_point(0, 0))
}

fn test_print_wide_char_in_single_width_terminal() {
	mut t := create_test_terminal(1, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x1F600) or { assert false } // Smiley face
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.pending_wrap

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0
	assert c0.wide == .narrow

	assert t.is_dirty(active_point(0, 0))
}

fn test_print_kitty_unicode_placeholder_marks_row() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(kitty_unicode_placeholder) or { assert false }
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1
	assert cell_at(&t, 0, 0).codepoint == kitty_unicode_placeholder
	assert active_row(&t, 0).header.kitty_virtual_placeholder
	assert t.is_dirty(active_point(0, 0))
}

fn test_print_over_wrapped_wide_char_clears_previous_spacer_head() {
	mut t := create_test_terminal(2, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.print(0x6A4B) or { assert false } // 橋
	assert cell_at(&t, 1, 0).wide == .spacer_head
	assert cell_at(&t, 0, 1).wide == .wide
	assert cell_at(&t, 1, 1).wide == .spacer_tail

	t.set_cursor_pos(2, 1)
	t.print(u32(`X`)) or { assert false }
	assert cell_at(&t, 1, 0).wide == .narrow
	assert cell_at(&t, 0, 1).codepoint == u32(`X`)
	assert cell_at(&t, 1, 1).wide == .narrow
}

fn test_print_over_wrapped_wide_tail_clears_previous_spacer_head() {
	mut t := create_test_terminal(2, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.print(0x6A4B) or { assert false } // 橋
	t.set_cursor_pos(2, 2)
	t.print(u32(`X`)) or { assert false }
	assert cell_at(&t, 1, 0).wide == .narrow
	assert cell_at(&t, 0, 1).wide == .narrow
	assert cell_at(&t, 1, 1).codepoint == u32(`X`)
}

fn test_print_over_wide_char_at_0_0() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x1F600) or { assert false } // Smiley face
	t.set_cursor_pos(0, 0)
	t.print(u32(`A`)) or { assert false }

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == u32(`A`)
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert c1.wide == .narrow

	assert t.is_dirty(active_point(0, 0))
	assert !t.is_dirty(active_point(0, 1))
}

fn test_print_over_wide_spacer_tail() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x6A4B) or { assert false } // 橋 (wide)
	t.set_cursor_pos(1, 2)
	t.print(u32(`X`)) or { assert false }

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == u32(`X`)
	assert c1.wide == .narrow

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ' X'

	assert t.is_dirty(active_point(0, 0))
}

// Helper: count cells in the active area that carry grapheme data. Used to
// mirror ghostty's page.graphemeCount() assertions. witty stores graphemes
// inline on the cell rather than in a per-page ref-counted set, so we count
// cells with has_grapheme set.
fn active_grapheme_count(t &Terminal) int {
	mut n := 0
	for y in 0 .. int(t.rows) {
		row := active_row(t, y)
		for cell in row.cells {
			if cell.has_grapheme() {
				n++
			}
		}
	}
	return n
}

// ============================================================
// Wide char + grapheme + variation selector (VS15/VS16) tests
// Translated from ghostty Terminal.zig.
// ============================================================

fn test_zero_width_character_at_start() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// This used to crash the terminal. This is not allowed so we should
	// just ignore it.
	t.print(0x200D) or { assert false }

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 0

	// Should not be dirty since we changed nothing.
	assert !t.is_dirty(active_point(0, 0))
}

fn test_print_wide_char_at_edge_creates_spacer_head() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(1, 10)
	t.print(0x1F600) or { assert false } // Smiley face
	assert t.screens.active.cursor.y == 1
	assert t.screens.active.cursor.x == 2

	c_head := cell_at(&t, 9, 0)
	assert c_head.wide == .spacer_head
	c_wide := cell_at(&t, 0, 1)
	assert c_wide.codepoint == 0x1F600
	assert c_wide.wide == .wide
	c_tail := cell_at(&t, 1, 1)
	assert c_tail.wide == .spacer_tail

	assert t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))
}

fn test_print_wide_char_with_1_column_width() {
	mut t := create_test_terminal(1, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x1F600) or { assert false }

	// This prints a space so we should be dirty.
	assert t.is_dirty(active_point(0, 0))
}

fn test_print_multicodepoint_grapheme_disabled_mode_2027() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// grapheme_cluster disabled by default. This is: 👨‍👩‍👧
	t.print(0x1F468) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F469) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F467) or { assert false }

	// We should have 6 cells taken up
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 6

	// With mode 2027 disabled, each ZWJ (zero-width) attaches to the
	// preceding cell's grapheme data, but the emoji themselves remain as
	// separate wide cells (no cluster merging).
	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x1F468
	assert c0.has_grapheme()
	assert c0.wide == .wide
	assert graphemes_at(&t, 0, 0).len == 1
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert !c1.has_grapheme()
	assert c1.wide == .spacer_tail
	c2 := cell_at(&t, 2, 0)
	assert c2.codepoint == 0x1F469
	assert c2.has_grapheme()
	assert c2.wide == .wide
	assert graphemes_at(&t, 2, 0).len == 1
	c3 := cell_at(&t, 3, 0)
	assert c3.codepoint == 0
	assert !c3.has_grapheme()
	assert c3.wide == .spacer_tail
	c4 := cell_at(&t, 4, 0)
	assert c4.codepoint == 0x1F467
	assert !c4.has_grapheme()
	assert c4.wide == .wide
	c5 := cell_at(&t, 5, 0)
	assert c5.codepoint == 0
	assert !c5.has_grapheme()
	assert c5.wide == .spacer_tail

	assert t.is_dirty(active_point(0, 0))
}

fn test_vs16_doesnt_make_character_with_2027_disabled() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	// grapheme clustering disabled (default)
	t.print(0x2764) or { assert false } // Heart
	t.print(0xFE0F) or { assert false } // VS16 to make wide

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x2764
	assert c0.has_grapheme()
	assert c0.wide == .narrow
	assert graphemes_at(&t, 0, 0).len == 1
	assert graphemes_at(&t, 0, 0)[0] == 0xFE0F
}

fn test_ignored_vs16_doesnt_mark_dirty() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x2764) or { assert false } // Heart
	assert t.is_dirty(active_point(0, 0))

	t.clear_dirty()
	t.print(0xFE0F) or { assert false } // VS16 to make wide
	assert !t.is_dirty(active_point(0, 0))
}

fn test_print_invalid_vs16_non_grapheme() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	// grapheme clustering disabled (default). Issue 1482.
	t.print(u32(`x`)) or { assert false }
	t.print(0xFE0F) or { assert false }

	// We should have 1 narrow cell.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == u32(`x`)
	assert !c0.has_grapheme()
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
}

fn test_invalid_vs16_doesnt_mark_dirty() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`x`)) or { assert false }
	assert t.is_dirty(active_point(0, 0))

	t.clear_dirty()
	t.print(0xFE0F) or { assert false } // VS16 to make wide
	assert !t.is_dirty(active_point(0, 0))
}

fn test_print_multicodepoint_grapheme_mode_2027() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// This is: 👨‍👩‍👧
	t.print(0x1F468) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F469) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F467) or { assert false }

	// We should have 2 cells taken up. It is one character but "wide".
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	assert t.is_dirty(active_point(0, 0))

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x1F468
	assert c0.has_grapheme()
	assert c0.wide == .wide
	// The other 4 codepoints (ZWJ, 👩, ZWJ, 👧) are stored as graphemes.
	assert graphemes_at(&t, 0, 0).len == 4
	assert graphemes_at(&t, 0, 0)[0] == 0x200D
	assert graphemes_at(&t, 0, 0)[1] == 0x1F469
	assert graphemes_at(&t, 0, 0)[2] == 0x200D
	assert graphemes_at(&t, 0, 0)[3] == 0x1F467

	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert !c1.has_grapheme()
	assert c1.wide == .spacer_tail
}

fn test_keypad_sequence_vs15() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// This is: "#︎" (number sign with text presentation selector)
	t.print(0x23) or { assert false } // # (valid base)
	t.print(0xFE0E) or { assert false } // VS15 (text presentation)

	// VS15 should combine into a single narrow grapheme cluster.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1

	assert t.is_dirty(active_point(0, 0))

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x23
	assert c0.has_grapheme()
	assert c0.wide == .narrow
}

fn test_keypad_sequence_vs16() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// This is: "#️" (number sign with emoji presentation selector)
	t.print(0x23) or { assert false } // # (valid base)
	t.print(0xFE0F) or { assert false } // VS16 (emoji presentation)

	// VS16 should combine into a single wide grapheme cluster (2 cells).
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	assert t.is_dirty(active_point(0, 0))

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x23
	assert c0.has_grapheme()
	assert c0.wide == .wide
	c1 := cell_at(&t, 1, 0)
	assert c1.wide == .spacer_tail
}

fn test_fitzpatrick_skin_tone_next_valid_base() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// This is: "👋🏿" (waving hand with dark skin tone)
	t.print(0x1F44B) or { assert false } // 👋 Waving hand
	t.print(0x1F3FF) or { assert false } // 🏿 Dark skin tone modifier

	// The skin tone combines into a single wide grapheme cluster (2 cells).
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	assert t.is_dirty(active_point(0, 0))

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x1F44B
	assert c0.has_grapheme()
	assert c0.wide == .wide
}

fn test_fitzpatrick_skin_tone_next_to_non_base() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// The skin tone should NOT join with the quotes.
	t.print(0x22) or { assert false } // "
	t.print(0x1F3FF) or { assert false } // Dark skin tone
	t.print(0x22) or { assert false } // "

	// We should have 4 cells taken up.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 4

	assert t.is_dirty(active_point(0, 0))

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x22
	assert !c0.has_grapheme()
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0x1F3FF
	assert !c1.has_grapheme()
	assert c1.wide == .wide
	c3 := cell_at(&t, 3, 0)
	assert c3.codepoint == 0x22
	assert !c3.has_grapheme()
	assert c3.wide == .narrow
}

fn test_multicodepoint_grapheme_marks_dirty_on_every_codepoint() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x1F468) or { assert false }
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	t.print(0x200D) or { assert false }
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	t.print(0x1F469) or { assert false }
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	t.print(0x200D) or { assert false }
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	t.print(0x1F467) or { assert false }
	assert t.is_dirty(active_point(0, 0))

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2
}

fn test_vs15_to_make_narrow_character() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x2614) or { assert false } // Umbrella with rain drops, width=2
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()

	// We should have 2 cells taken up (wide).
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	t.print(0xFE0E) or { assert false } // VS15 to make narrow
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()

	// VS15 should send us back a cell since our char is no longer wide.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x2614
	assert c0.has_grapheme()
	assert c0.wide == .narrow
	assert graphemes_at(&t, 0, 0).len == 1
	// The wide spacer tail must have been reverted to narrow.
	c1 := cell_at(&t, 1, 0)
	assert c1.wide == .narrow
}

fn test_vs15_on_already_narrow_emoji() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x26C8) or { assert false } // Thunder cloud and rain, width=1
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	t.print(0xFE0E) or { assert false } // VS15 to make narrow
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()

	// Character takes up one cell.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x26C8
	assert c0.has_grapheme()
	assert c0.wide == .narrow
	assert graphemes_at(&t, 0, 0).len == 1
}

fn test_print_invalid_vs15_following_emoji_is_wide() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x1F9E0) or { assert false } // 🧠
	t.print(0xFE0E) or { assert false } // not valid with U+1F9E0 as base

	// We should have 2 cells taken up (wide).
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x1F9E0
	assert !c0.has_grapheme()
	assert c0.wide == .wide
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert c1.wide == .spacer_tail
}

fn test_print_invalid_vs15_in_emoji_zwj_sequence() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x1F469) or { assert false } // 👩
	t.print(0xFE0E) or { assert false } // not valid with U+1F469 as base
	t.print(0x200D) or { assert false } // ZWJ
	t.print(0x1F466) or { assert false } // 👦

	// We should have 2 cells taken up (wide).
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x1F469
	assert c0.has_grapheme()
	// The invalid VS15 is dropped; only ZWJ + 👦 attach.
	assert graphemes_at(&t, 0, 0).len == 2
	assert graphemes_at(&t, 0, 0)[0] == 0x200D
	assert graphemes_at(&t, 0, 0)[1] == 0x1F466
	assert c0.wide == .wide
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert c1.wide == .spacer_tail
}

fn test_vs15_to_make_narrow_character_with_pending_wrap() {
	mut t := create_test_terminal(2, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x2614) or { assert false } // Umbrella, width=2
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()

	// We only move one because we're in a pending wrap state.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1
	assert t.screens.active.cursor.pending_wrap

	t.print(0xFE0E) or { assert false } // VS15 to make narrow
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()

	// VS15 should clear the pending wrap state.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1
	assert !t.screens.active.cursor.pending_wrap

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x2614
	assert c0.has_grapheme()
	assert c0.wide == .narrow
	assert graphemes_at(&t, 0, 0).len == 1
}

fn test_vs16_to_make_wide_character_with_mode_2027() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x2764) or { assert false } // Heart
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()
	t.print(0xFE0F) or { assert false } // VS16 to make wide
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x2764
	assert c0.has_grapheme()
	assert c0.wide == .wide
	assert graphemes_at(&t, 0, 0).len == 1
	c1 := cell_at(&t, 1, 0)
	assert c1.wide == .spacer_tail
}

fn test_vs16_repeated_with_mode_2027() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x2764) or { assert false } // Heart
	t.print(0xFE0F) or { assert false } // VS16 to make wide
	t.print(0x2764) or { assert false } // Heart
	t.print(0xFE0F) or { assert false } // VS16 to make wide

	assert t.is_dirty(active_point(0, 0))

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x2764
	assert c0.has_grapheme()
	assert c0.wide == .wide
	assert graphemes_at(&t, 0, 0).len == 1
	c2 := cell_at(&t, 2, 0)
	assert c2.codepoint == 0x2764
	assert c2.has_grapheme()
	assert c2.wide == .wide
	assert graphemes_at(&t, 2, 0).len == 1
}

fn test_print_invalid_vs16_grapheme() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// Issue 1482.
	t.print(u32(`x`)) or { assert false }
	t.print(0xFE0F) or { assert false } // invalid VS16

	// We should have 1 narrow cell.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == u32(`x`)
	assert !c0.has_grapheme()
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert c1.wide == .narrow
}

fn test_print_invalid_vs16_with_second_char() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(u32(`x`)) or { assert false }
	t.print(0xFE0F) or { assert false }
	t.print(u32(`y`)) or { assert false }

	// Two separate narrow characters.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == u32(`x`)
	assert !c0.has_grapheme()
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == u32(`y`)
	assert !c1.has_grapheme()
	assert c1.wide == .narrow
}

fn test_print_invalid_vs16_with_second_char_combining() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(u32(`n`)) or { assert false }
	t.print(0xFE0F) or { assert false } // invalid VS16
	t.print(0x0303) or { assert false } // combining tilde

	// One narrow cell.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == u32(`n`)
	assert c0.has_grapheme()
	// The invalid VS16 is dropped; only the combining tilde attaches.
	assert graphemes_at(&t, 0, 0).len == 1
	assert graphemes_at(&t, 0, 0)[0] == 0x0303
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert c1.wide == .narrow
}

fn test_overwrite_grapheme_should_clear_grapheme_data() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	t.print(0x26C8) or { assert false } // Thunder cloud and rain
	t.print(0xFE0E) or { assert false } // VS15 to make narrow
	assert t.is_dirty(active_point(0, 0))
	t.clear_dirty()

	t.set_cursor_pos(1, 1)
	t.print(u32(`A`)) or { assert false }
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A'

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == u32(`A`)
	assert !c0.has_grapheme()
	assert c0.wide == .narrow
}

fn test_overwrite_multicodepoint_grapheme_clears_grapheme_data() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// This is: 👨‍👩‍👧
	t.print(0x1F468) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F469) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F467) or { assert false }

	// We should have 2 cells taken up (wide).
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2

	// One cell with graphemes.
	assert active_grapheme_count(&t) == 1

	// Move back and overwrite wide.
	t.set_cursor_pos(1, 1)
	t.clear_dirty()
	t.print(u32(`X`)) or { assert false }
	assert t.is_dirty(active_point(0, 0))

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 1
	assert active_grapheme_count(&t) == 0

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X'
}

fn test_overwrite_multicodepoint_grapheme_tail_clears_grapheme_data() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// This is: 👨‍👩‍👧
	t.print(0x1F468) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F469) or { assert false }
	t.print(0x200D) or { assert false }
	t.print(0x1F467) or { assert false }

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2
	assert active_grapheme_count(&t) == 1

	// Move back and overwrite the wide tail.
	t.set_cursor_pos(1, 2)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ' X'

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 2
	assert active_grapheme_count(&t) == 0
}

fn test_print_breaks_valid_grapheme_cluster_with_prepend_ascii_for_speed() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)

	// Make sure we're not at cursor.x == 0 for the next char.
	t.print(u32(`_`)) or { assert false }

	// U+0600 ARABIC NUMBER SIGN (Prepend)
	t.print(0x0600) or { assert false }
	t.print(u32(`1`)) or { assert false }

	// We should have 3 cells taken up, each narrow. Note that this is
	// **incorrect** grapheme break behavior per UAX #29 GB9b, but as an
	// optimization we assume a grapheme break when c <= 255.
	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 3

	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0x0600
	assert !c1.has_grapheme()
	assert c1.wide == .narrow
	c2 := cell_at(&t, 2, 0)
	assert c2.codepoint == u32(`1`)
	assert !c2.has_grapheme()
	assert c2.wide == .narrow
}

// ============================================================
// cursorPos additional
// ============================================================

fn test_cursor_pos_relative_to_origin_with_left_right() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.top = 2
	t.scrolling_region.bottom = 3
	t.scrolling_region.left = 2
	t.scrolling_region.right = 4
	t.modes.set(.origin, true)
	t.set_cursor_pos(1, 1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\n  X'
}

fn test_cursor_pos_limits_with_full_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.top = 2
	t.scrolling_region.bottom = 3
	t.scrolling_region.left = 2
	t.scrolling_region.right = 4
	t.modes.set(.origin, true)
	t.set_cursor_pos(500, 500)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\n\n    X'
}

fn test_set_cursor_pos_original() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 0

	// Setting it to 0 keeps it zero (1 based)
	t.set_cursor_pos(0, 0)
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 0

	// Should clamp to size
	t.set_cursor_pos(81, 81)
	assert t.screens.active.cursor.x == 79
	assert t.screens.active.cursor.y == 79

	// Should reset pending wrap
	t.set_cursor_pos(0, 80)
	t.print(u32(`c`)) or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.set_cursor_pos(0, 80)
	assert !t.screens.active.cursor.pending_wrap

	// Origin mode
	t.modes.set(.origin, true)

	// No change without a scroll region
	t.set_cursor_pos(81, 81)
	assert t.screens.active.cursor.x == 79
	assert t.screens.active.cursor.y == 79

	// Set the scroll region
	t.set_top_and_bottom_margin(10, uint(t.rows))
	t.set_cursor_pos(0, 0)
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 9

	t.set_cursor_pos(1, 1)
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 9

	t.set_cursor_pos(100, 0)
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 79

	t.set_top_and_bottom_margin(10, 11)
	t.set_cursor_pos(2, 0)
	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 10
}

// ============================================================
// cursorUp / cursorDown / cursorLeft / cursorRight (additional)
// ============================================================

fn test_cursor_right_left_of_right_margin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.right = 2
	t.cursor_right(100)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  X'
}

fn test_cursor_right_right_of_right_margin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.right = 2
	t.set_cursor_pos(1, 4)
	t.cursor_right(100)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '    X'
}

fn test_cursor_left_unsets_pending_wrap_state_with_longer_jump() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.cursor_left(3)
	assert !t.screens.active.cursor.pending_wrap
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AXCDE'
}

fn test_cursor_left_reverse_wrap_with_pending_wrap_state() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap, true)

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.cursor_left(1)
	assert !t.screens.active.cursor.pending_wrap
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABCDX'
}

fn test_cursor_left_reverse_wrap_extended_with_pending_wrap_state() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap_extended, true)

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.cursor_left(1)
	assert !t.screens.active.cursor.pending_wrap
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABCDX'
}

fn test_cursor_left_reverse_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap, true)

	t.print_string('ABCDE1') or { assert false }
	t.cursor_left(2)
	t.print(u32(`X`)) or { assert false }
	assert t.screens.active.cursor.pending_wrap

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABCDX\n1'
}

fn test_cursor_left_reverse_wrap_with_no_soft_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap, true)

	t.print_string('ABCDE') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`1`)) or { assert false }
	t.cursor_left(2)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABCDE\nX'
}

fn test_cursor_left_reverse_wrap_before_left_margin() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap, true)
	t.set_top_and_bottom_margin(3, 0)
	t.cursor_left(1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\nX'
}

fn test_cursor_left_extended_reverse_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap_extended, true)

	t.print_string('ABCDE') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`1`)) or { assert false }
	t.cursor_left(2)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABCDX\n1'
}

fn test_cursor_left_extended_reverse_wrap_bottom_wraparound() {
	mut t := create_test_terminal(5, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap_extended, true)

	t.print_string('ABCDE') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`1`)) or { assert false }
	t.cursor_left(1 + uint(t.cols) + 1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABCDE\n1\n    X'
}

fn test_cursor_left_extended_reverse_wrap_is_priority_if_both_set() {
	mut t := create_test_terminal(5, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap, true)
	t.modes.set(.reverse_wrap_extended, true)

	t.print_string('ABCDE') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`1`)) or { assert false }
	t.cursor_left(1 + uint(t.cols) + 1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABCDE\n1\n    X'
}

fn test_cursor_left_extended_reverse_wrap_above_top_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap_extended, true)

	t.set_top_and_bottom_margin(3, 0)
	t.set_cursor_pos(2, 1)
	t.cursor_left(1000)

	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 0
}

fn test_cursor_left_reverse_wrap_on_first_row() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, true)
	t.modes.set(.reverse_wrap, true)

	t.set_top_and_bottom_margin(3, 0)
	t.set_cursor_pos(1, 2)
	t.cursor_left(1000)

	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 0
}

// ============================================================
// reverseIndex
// ============================================================

fn test_reverse_index_from_the_top() {
	mut t := create_test_terminal(2, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }

	t.set_cursor_pos(1, 1)
	t.reverse_index()
	t.print(u32(`D`)) or { assert false }

	t.carriage_return()
	t.linefeed() or { assert false }
	t.set_cursor_pos(1, 1)
	t.reverse_index()
	t.print(u32(`E`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'E\nD\nA\nB'
}

fn test_reverse_index_top_of_scrolling_region() {
	mut t := create_test_terminal(2, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(2, 1)
	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`C`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`D`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }

	t.set_top_and_bottom_margin(2, 5)
	t.set_cursor_pos(2, 1)
	t.reverse_index()
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nX\nA\nB\nC'
}

fn test_reverse_index_top_of_screen() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.set_cursor_pos(2, 1)
	t.print(u32(`B`)) or { assert false }
	t.set_cursor_pos(3, 1)
	t.print(u32(`C`)) or { assert false }
	t.set_cursor_pos(1, 1)
	t.reverse_index()
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X\nA\nB\nC'
}

fn test_reverse_index_not_top_of_screen() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.set_cursor_pos(2, 1)
	t.print(u32(`B`)) or { assert false }
	t.set_cursor_pos(3, 1)
	t.print(u32(`C`)) or { assert false }
	t.set_cursor_pos(2, 1)
	t.reverse_index()
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X\nB\nC'
}

fn test_reverse_index_top_bottom_margins() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.set_cursor_pos(2, 1)
	t.print(u32(`B`)) or { assert false }
	t.set_cursor_pos(3, 1)
	t.print(u32(`C`)) or { assert false }
	t.set_top_and_bottom_margin(2, 3)
	t.set_cursor_pos(2, 1)
	t.reverse_index()

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\n\nB'
}

fn test_reverse_index_outside_top_bottom_margins() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.set_cursor_pos(2, 1)
	t.print(u32(`B`)) or { assert false }
	t.set_cursor_pos(3, 1)
	t.print(u32(`C`)) or { assert false }
	t.set_top_and_bottom_margin(2, 3)
	t.set_cursor_pos(1, 1)
	t.reverse_index()

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\nB\nC'
}

// ============================================================
// index
// ============================================================

fn test_index_outside_of_scrolling_region() {
	mut t := create_test_terminal(2, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	assert t.screens.active.cursor.y == 0
	t.set_top_and_bottom_margin(2, 5)
	t.index() or { assert false }
	assert t.screens.active.cursor.y == 1
}

fn test_index_from_the_bottom_outside_of_scroll_region() {
	mut t := create_test_terminal(2, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_top_and_bottom_margin(1, 2)
	t.set_cursor_pos(5, 1)
	t.print(u32(`A`)) or { assert false }
	t.clear_dirty()
	t.index() or { assert false }
	t.print(u32(`B`)) or { assert false }
	assert t.is_dirty(active_point(0, 4))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\n\n\nAB'
}

fn test_index_no_scroll_region_top_of_screen() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.clear_dirty()
	t.index() or { assert false }
	t.print(u32(`X`)) or { assert false }

	assert t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\n X'
}

fn test_index_bottom_of_primary_screen() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(5, 1)
	t.print(u32(`A`)) or { assert false }
	t.clear_dirty()
	t.index() or { assert false }
	t.print(u32(`X`)) or { assert false }

	assert t.is_dirty(active_point(0, 3))
	assert t.is_dirty(active_point(0, 4))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\n\nA\n X'
}

fn test_index_inside_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_top_and_bottom_margin(1, 3)
	t.print(u32(`A`)) or { assert false }
	t.clear_dirty()
	t.index() or { assert false }
	t.print(u32(`X`)) or { assert false }

	assert t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\n X'
}

// ============================================================
// deleteLines
// ============================================================

fn test_delete_lines_legacy() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`C`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`D`)) or { assert false }

	t.cursor_up(2)
	t.delete_lines(1)

	t.print(u32(`E`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }

	assert t.screens.active.cursor.x == 0
	assert t.screens.active.cursor.y == 2

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\nE\nD'
}

fn test_delete_lines_with_scroll_region_legacy() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`C`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`D`)) or { assert false }

	t.set_top_and_bottom_margin(1, 3)
	t.set_cursor_pos(1, 1)

	t.clear_dirty()
	t.delete_lines(1)

	assert t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))
	assert t.is_dirty(active_point(0, 2))
	assert !t.is_dirty(active_point(0, 3))

	t.print(u32(`E`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'E\nC\n\nD'
}

fn test_delete_lines_with_scroll_region_large_count() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`C`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`D`)) or { assert false }

	t.set_top_and_bottom_margin(1, 3)
	t.set_cursor_pos(1, 1)
	t.delete_lines(5)

	t.print(u32(`E`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'E\n\n\nD'
}

fn test_delete_lines_with_scroll_region_cursor_outside_of_region() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`C`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`D`)) or { assert false }

	t.set_top_and_bottom_margin(1, 3)
	t.set_cursor_pos(4, 1)
	t.delete_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\nB\nC\nD'
}

fn test_delete_lines_left_right_scroll_region() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF456') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(2, 2)
	t.delete_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC123\nDHI756\nG   89'
}

fn test_delete_lines_left_right_scroll_region_from_top() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF456') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(1, 2)
	t.delete_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AEF423\nDHI756\nG   89'
}

fn test_delete_lines_left_right_scroll_region_high_count() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF456') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(2, 2)
	t.delete_lines(100)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC123\nD   56\nG   89'
}

// ============================================================
// setLeftAndRightMargin
// ============================================================

fn test_set_left_and_right_margin_simple() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(0, 0)

	t.clear_dirty()
	t.erase_chars(1)

	assert t.is_dirty(active_point(0, 0))
	assert !t.is_dirty(active_point(0, 1))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ' BC\nDEF\nGHI'
}

fn test_set_left_and_right_margin_left_only() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(2, 0)
	assert t.scrolling_region.left == 1
	assert t.scrolling_region.right == t.cols - 1
	t.set_cursor_pos(1, 2)
	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\nDBC\nGEF\n HI'
}

fn test_set_left_and_right_margin_left_and_right() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(1, 2)
	t.set_cursor_pos(1, 2)
	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  C\nABF\nDEI\nGH'
}

fn test_set_left_and_right_margin_left_equal_right() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(2, 2)
	t.set_cursor_pos(1, 2)
	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nDEF\nGHI'
}

fn test_set_left_and_right_margin_mode_69_unset() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.modes.set(.enable_left_and_right_margin, false)
	t.set_left_and_right_margin(1, 2)
	t.set_cursor_pos(1, 2)
	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nABC\nDEF\nGHI'
}

// ============================================================
// insertLines (additional)
// ============================================================

fn test_insert_lines_outside_of_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_top_and_bottom_margin(3, 4)
	t.set_cursor_pos(2, 2)

	t.clear_dirty()
	t.insert_lines(1)

	assert !t.is_dirty(active_point(0, 0))
	assert !t.is_dirty(active_point(0, 1))
	assert !t.is_dirty(active_point(0, 2))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\nDEF\nGHI'
}

fn test_insert_lines_top_bottom_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('123') or { assert false }
	t.set_top_and_bottom_margin(1, 3)
	t.set_cursor_pos(2, 2)
	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\n\nDEF\n123'
}

fn test_insert_lines_legacy() {
	mut t := create_test_terminal(2, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`C`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`D`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`E`)) or { assert false }

	t.set_cursor_pos(2, 1)
	t.insert_lines(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A\n\n\nB\nC'
}

fn test_insert_lines_with_scroll_region_legacy() {
	mut t := create_test_terminal(2, 6) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`B`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`C`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`D`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print(u32(`E`)) or { assert false }

	t.set_top_and_bottom_margin(1, 2)
	t.set_cursor_pos(1, 1)

	t.clear_dirty()
	t.insert_lines(1)

	assert t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))
	assert !t.is_dirty(active_point(0, 2))

	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X\nA\nC\nD\nE'
}

fn test_insert_lines_resets_wrap() {
	mut t := create_test_terminal(3, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`1`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('ABCDEF') or { assert false }
	t.set_cursor_pos(1, 1)
	t.insert_lines(1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X\n1\nABC'

	assert !row_wrap_at(&t, 2)
}

fn test_insert_lines_left_right_scroll_region() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF456') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(2, 2)
	t.insert_lines(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC123\nD   56\nGEF489\n HI7'
}

// ============================================================
// scrollUp (additional)
// ============================================================

fn test_scroll_up_top_bottom_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_top_and_bottom_margin(2, 3)
	t.set_cursor_pos(1, 1)

	t.clear_dirty()
	t.scroll_up(1) or { assert false }

	assert t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))
	assert t.is_dirty(active_point(0, 2))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\nGHI'
}

fn test_scroll_up_left_right_scroll_region() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF456') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(2, 2)

	cx := t.screens.active.cursor.x
	cy := t.screens.active.cursor.y
	t.scroll_up(1) or { assert false }
	assert t.screens.active.cursor.x == cx
	assert t.screens.active.cursor.y == cy

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AEF423\nDHI756\nG   89'
}

fn test_scroll_up_left_right_region_preserves_hyperlink_flags() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	t.print_string('DEF456') or { assert false }
	t.screens.active.end_hyperlink()
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(2, 2)
	t.scroll_up(1) or { assert false }

	assert (t.plain_string() or { '' }) == 'AEF423\nDHI756\nG   89'
	row0 := active_row(&t, 0)
	assert row0.header.hyperlink
	for x in 1 .. 4 {
		assert row0.cells[x].has_hyperlink
		link := cell_hyperlink_at(&t, x, 0) or { panic('cell hyperlink is missing') }
		assert link.uri == 'http://example.com'
	}
}

fn test_insert_delete_lines_preserve_full_row_metadata() {
	mut t := create_test_terminal(4, 4) or {
		assert false
		return
	}
	defer { t.deinit() }

	// Put managed and semantic state on the row that will move.
	t.set_cursor_pos(2, 1)
	t.screens.active.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	t.print(kitty_unicode_placeholder) or { assert false }
	t.screens.active.end_hyperlink()
	source := active_row(&t, 1)
	assert source.header.semantic_prompt == .prompt
	assert source.header.hyperlink
	assert source.header.kitty_virtual_placeholder

	t.set_cursor_pos(1, 1)
	t.insert_lines(1)
	moved_down := active_row(&t, 2)
	assert moved_down.header.semantic_prompt == .prompt
	assert moved_down.header.hyperlink
	assert moved_down.header.kitty_virtual_placeholder

	t.set_cursor_pos(2, 1)
	t.delete_lines(1)
	moved_up := active_row(&t, 1)
	assert moved_up.header.semantic_prompt == .prompt
	assert moved_up.header.hyperlink
	assert moved_up.header.kitty_virtual_placeholder
}

fn test_line_shift_recomputes_grapheme_flag_after_wide_boundary_split() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)
	t.print_string('AA') or { assert false }
	t.print(0x1f468) or { assert false }
	t.print(0x200d) or { assert false }
	t.print(0x1f469) or { assert false }
	row_before := active_row(&t, 0)
	assert row_before.cells[2].wide == .wide
	assert row_before.cells[2].has_grapheme()
	assert row_before.cells[3].wide == .spacer_tail
	assert row_before.header.grapheme

	// Splitting the left boundary at the wide tail clears the only grapheme.
	t.scrolling_region.left = 3
	t.scrolling_region.right = 4
	t.screens.active.cursor_absolute(3, 0)
	t.delete_lines(1)

	row_after := active_row(&t, 0)
	assert !row_after.cells[2].has_grapheme()
	assert row_after.cells[2].wide == .narrow
	assert row_after.cells[3].wide == .narrow
	assert !row_after.header.grapheme
}

fn test_scroll_up_preserves_pending_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(1, 5)
	t.print(u32(`A`)) or { assert false }
	t.set_cursor_pos(2, 5)
	t.print(u32(`B`)) or { assert false }
	t.set_cursor_pos(3, 5)
	t.print(u32(`C`)) or { assert false }
	t.scroll_up(1) or { assert false }
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '    B\n    C\n\nX'
}

fn test_scroll_up_full_top_bottom_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('top') or { assert false }
	t.set_cursor_pos(5, 1)
	t.print_string('ABCDE') or { assert false }
	t.set_top_and_bottom_margin(2, 5)

	t.clear_dirty()
	t.scroll_up(4) or { assert false }

	assert t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'top'
}

// ============================================================
// scrollDown (additional)
// ============================================================

fn test_scroll_down_outside_of_scroll_region() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_top_and_bottom_margin(3, 4)
	t.set_cursor_pos(2, 2)

	cx := t.screens.active.cursor.x
	cy := t.screens.active.cursor.y
	t.clear_dirty()
	t.scroll_down(1)
	assert t.screens.active.cursor.x == cx
	assert t.screens.active.cursor.y == cy

	assert !t.is_dirty(active_point(0, 0))
	assert t.is_dirty(active_point(0, 1))
	assert t.is_dirty(active_point(0, 2))
	assert t.is_dirty(active_point(0, 3))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\nDEF\n\nGHI'
}

fn test_scroll_down_left_right_scroll_region() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF456') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(2, 2)

	cx := t.screens.active.cursor.x
	cy := t.screens.active.cursor.y
	t.scroll_down(1)
	assert t.screens.active.cursor.x == cx
	assert t.screens.active.cursor.y == cy

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A   23\nDBC156\nGEF489\n HI7'
}

fn test_scroll_down_outside_of_left_right_scroll_region() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF456') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI789') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(1, 1)

	cx := t.screens.active.cursor.x
	cy := t.screens.active.cursor.y
	t.scroll_down(1)
	assert t.screens.active.cursor.x == cx
	assert t.screens.active.cursor.y == cy

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A   23\nDBC156\nGEF489\n HI7'
}

fn test_scroll_down_preserves_pending_wrap() {
	mut t := create_test_terminal(5, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(1, 5)
	t.print(u32(`A`)) or { assert false }
	t.set_cursor_pos(2, 5)
	t.print(u32(`B`)) or { assert false }
	t.set_cursor_pos(3, 5)
	t.print(u32(`C`)) or { assert false }
	t.scroll_down(1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n    A\n    B\nX   C'
}

// ============================================================
// insertBlanks (additional)
// ============================================================

fn test_insert_blanks_no_scroll_region_fits() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)

	t.clear_dirty()
	t.insert_blanks(2)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  ABC'
}

fn test_insert_blanks_shift_off_screen() {
	mut t := create_test_terminal(5, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('  ABC') or { assert false }
	t.set_cursor_pos(1, 3)
	t.clear_dirty()
	t.insert_blanks(2)
	assert t.is_dirty(active_point(0, 0))
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  X A'
}

fn test_insert_blanks_inside_left_right_scroll_region() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.scrolling_region.left = 2
	t.scrolling_region.right = 4
	t.set_cursor_pos(1, 3)
	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 3)

	t.clear_dirty()
	t.insert_blanks(2)
	assert t.is_dirty(active_point(0, 0))
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  X A'
}

fn test_insert_blanks_outside_left_right_scroll_region() {
	mut t := create_test_terminal(6, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(1, 4)
	t.print_string('ABC') or { assert false }
	t.scrolling_region.left = 2
	t.scrolling_region.right = 4
	assert t.screens.active.cursor.pending_wrap
	t.clear_dirty()
	t.insert_blanks(2)
	assert !t.is_dirty(active_point(0, 0))
	assert !t.screens.active.cursor.pending_wrap
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '   ABX'
}

fn test_insert_blanks_left_right_scroll_region_large_count() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.origin, true)
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(3, 5)
	t.set_cursor_pos(1, 1)
	t.clear_dirty()
	t.insert_blanks(140)
	assert t.is_dirty(active_point(0, 0))
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  X'
}

// ============================================================
// deleteChars (additional)
// ============================================================

fn test_delete_chars_more_than_half() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	t.set_cursor_pos(1, 2)

	t.clear_dirty()
	t.delete_chars(3)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AE'
}

fn test_delete_chars_should_shift_left() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	t.set_cursor_pos(1, 2)

	t.clear_dirty()
	t.delete_chars(1)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ACDE'
}

fn test_delete_chars_resets_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE123') or { assert false }
	assert row_wrap_at(&t, 0)
	t.set_cursor_pos(1, 1)
	t.delete_chars(1)
	assert !row_wrap_at(&t, 0)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'XCDE\n123'
}

fn test_delete_chars_simple_operation() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.set_cursor_pos(1, 3)

	t.clear_dirty()
	t.delete_chars(2)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AB23'
}

fn test_delete_chars_outside_scroll_region() {
	mut t := create_test_terminal(6, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.scrolling_region.left = 2
	t.scrolling_region.right = 4
	assert t.screens.active.cursor.pending_wrap
	t.clear_dirty()
	t.delete_chars(2)
	assert !t.is_dirty(active_point(0, 0))
	assert t.screens.active.cursor.pending_wrap

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC123'
}

fn test_delete_chars_inside_scroll_region() {
	mut t := create_test_terminal(6, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.scrolling_region.left = 2
	t.scrolling_region.right = 4
	t.set_cursor_pos(1, 4)

	t.clear_dirty()
	t.delete_chars(1)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC2 3'
}

// ============================================================
// insert mode
// ============================================================

fn test_insert_mode_with_space() {
	mut t := create_test_terminal(10, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('hello') or { assert false }
	t.set_cursor_pos(1, 2)
	t.modes.set(.insert, true)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hXello'
}

fn test_insert_mode_doesnt_wrap_pushed_characters() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('hello') or { assert false }
	t.set_cursor_pos(1, 2)
	t.modes.set(.insert, true)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hXell'
}

fn test_insert_mode_does_nothing_at_the_end_of_the_line() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('hello') or { assert false }
	t.modes.set(.insert, true)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'hello\nX'
}

// ============================================================
// eraseLine (additional)
// ============================================================

fn test_erase_line_resets_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE123') or { assert false }
	assert row_wrap_at(&t, 0)

	t.set_cursor_pos(1, 1)
	t.erase_line(.right, false)

	assert !row_wrap_at(&t, 0)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X\n123'
}

fn test_erase_line_left_resets_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.clear_dirty()
	t.erase_line(.left, false)
	assert t.is_dirty(active_point(0, 0))
	assert !t.screens.active.cursor.pending_wrap
	t.print(u32(`B`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '    B'
}

fn test_erase_line_right_protected_attributes_respected_with_iso() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.iso)
	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.clear_dirty()
	t.erase_line(.right, false)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC'
}

fn test_erase_line_right_protected_attributes_ignored_with_dec_set() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.dec)
	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 2)
	t.clear_dirty()
	t.erase_line(.right, false)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A'
}

// ============================================================
// eraseDisplay (additional)
// ============================================================

fn test_erase_display_below_protected_attributes_respected_with_iso() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.iso)
	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(2, 2)
	t.erase_display(.below, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\nDEF\nGHI'
}

fn test_erase_display_above_protected_attributes_respected_with_iso() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_protected_mode(.iso)
	t.print_string('ABC') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('DEF') or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.print_string('GHI') or { assert false }
	t.set_cursor_pos(2, 2)
	t.erase_display(.above, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'ABC\nDEF\nGHI'
}

// ============================================================
// DECCOLM (additional)
// ============================================================

fn test_deccolm_resets_pending_wrap() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	assert t.screens.active.cursor.pending_wrap
	t.modes.set(.enable_mode_3, true)
	t.deccolm(.cols_80) or { assert false }
	assert !t.screens.active.cursor.pending_wrap
}

// ============================================================
// saveCursor (additional)
// ============================================================

fn test_save_cursor_position() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(1, 5)
	t.print(u32(`A`)) or { assert false }
	t.save_cursor()
	t.set_cursor_pos(1, 1)
	t.print(u32(`B`)) or { assert false }
	t.restore_cursor()
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'B   AX'
}

// ============================================================
// eraseDisplay (scroll / complete)
// ============================================================

fn test_erase_display_scroll_complete() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(u32(`A`)) or { assert false }
	t.carriage_return()
	t.linefeed() or { assert false }
	t.erase_display(.scroll_complete, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ''
}

fn test_erase_display_complete_preserves_cursor_style() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_attribute(SgrBold{}) or { assert false }
	t.print_string('AAAA') or { assert false }
	assert t.screens.active.cursor.style_id != default_style_id

	t.erase_display(.complete, false)
	assert t.screens.active.cursor.style_id != default_style_id
}

// ============================================================
// eraseChars (wide char)
// ============================================================

fn test_erase_chars_wide_character() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x6A4B) or { assert false } // 橋
	t.print_string('BC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.erase_chars(1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X BC'
}

fn test_erase_chars_wide_boundary_conditions() {
	mut t := create_test_terminal(8, 1) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('😀a😀b😀') or { assert false }
	assert (t.plain_string() or { '' }) == '😀a😀b😀'
	t.set_cursor_pos(1, 2)
	t.erase_chars(3)
	t.screens.active.assert_integrity()
	assert (t.plain_string() or { '' }) == '     b😀'
}

fn test_erase_chars_splits_requested_wide_boundaries() {
	mut t := create_test_terminal(30, 1) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('x食べて下さい') or { assert false }
	assert (t.plain_string() or { '' }) == 'x食べて下さい'
	t.set_cursor_pos(1, 6)
	t.erase_chars(4)
	t.screens.active.assert_integrity()
	assert (t.plain_string() or { '' }) == 'x食べ    さい'
}

fn test_erase_chars_repairs_wrapped_wide_boundaries() {
	mut t := create_test_terminal(8, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('.......😀abcde😀......') or { assert false }
	assert (t.plain_string() or { '' }) == '.......\n😀abcde\n😀......'
	assert (t.plain_string_unwrapped() or { '' }) == '.......😀abcde😀......'
	t.set_cursor_pos(2, 2)
	t.erase_chars(3)
	t.screens.active.assert_integrity()
	assert (t.plain_string() or { '' }) == '.......\n    cde\n😀......'
	assert (t.plain_string_unwrapped() or { '' }) == '.......     cde\n😀......'
}

// ============================================================
// eraseLine (left wide)
// ============================================================

fn test_erase_line_left_wide_character() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('AB') or { assert false }
	t.print(0x6A4B) or { assert false } // 橋
	t.print_string('DE') or { assert false }
	t.set_cursor_pos(1, 3)
	t.clear_dirty()
	t.erase_line(.left, false)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '    DE'
}

// ============================================================
// deleteChars split wide character
// ============================================================

fn test_delete_chars_split_wide_character_from_spacer_tail() {
	mut t := create_test_terminal(6, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('A') or { assert false }
	t.print(0x6A4B) or { assert false } // 橋
	t.print_string('123') or { assert false }
	t.set_cursor_pos(1, 3)
	t.delete_chars(1)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A 123'
}

fn test_delete_chars_split_wide_character_from_wide() {
	mut t := create_test_terminal(6, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print(0x6A4B) or { assert false } // 橋
	t.print_string('123') or { assert false }
	t.set_cursor_pos(1, 1)
	t.delete_chars(1)

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0
	assert c0.wide == .narrow
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == u32(`1`)
	assert c1.wide == .narrow
}

fn test_delete_chars_split_wide_character_from_end() {
	mut t := create_test_terminal(6, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('A') or { assert false }
	t.print(0x6A4B) or { assert false } // 橋
	t.print_string('123') or { assert false }
	t.set_cursor_pos(1, 1)
	t.delete_chars(1)

	c0 := cell_at(&t, 0, 0)
	assert c0.codepoint == 0x6A4B
	assert c0.wide == .wide
	c1 := cell_at(&t, 1, 0)
	assert c1.codepoint == 0
	assert c1.wide == .spacer_tail
}

fn test_delete_chars_with_a_spacer_head_at_the_end() {
	mut t := create_test_terminal(5, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('0123橋123') or { assert false }
	assert cell_at(&t, 4, 0).wide == .spacer_head
	assert active_row(&t, 0).header.wrap

	t.set_cursor_pos(1, 1)
	t.delete_chars(1)
	c3 := cell_at(&t, 3, 0)
	assert c3.codepoint == 0
	assert c3.wide == .narrow
}

fn test_delete_chars_split_wide_character_tail() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(1, uint(t.cols) - 1)
	t.print(0x6A4B) or { assert false }
	t.carriage_return()
	t.delete_chars(uint(t.cols) - 1)
	t.print(u32(`0`)) or { assert false }

	assert t.plain_string() or { '' } == '0'
}

fn test_delete_chars_wide_character_boundary_conditions() {
	mut t := create_test_terminal(8, 1) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('😀a😀b😀') or { assert false }
	assert t.plain_string() or { '' } == '😀a😀b😀'

	t.set_cursor_pos(1, 2)
	t.delete_chars(3)
	assert t.plain_string() or { '' } == '  b😀'
}

fn test_delete_chars_wide_character_wrap_boundary_conditions() {
	mut t := create_test_terminal(8, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('.......😀abcde😀......') or { assert false }
	assert t.plain_string() or { '' } == '.......\n😀abcde\n😀......'
	assert t.plain_string_unwrapped() or { '' } == '.......😀abcde😀......'

	t.set_cursor_pos(2, 2)
	t.delete_chars(3)
	assert t.plain_string() or { '' } == '.......\n cde\n😀......'
	assert t.plain_string_unwrapped() or { '' } == '.......  cde\n😀......'
}

fn test_delete_chars_wide_character_across_right_margin() {
	mut t := create_test_terminal(8, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456橋') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(2, 7)
	assert t.plain_string() or { '' } == '123456橋'

	t.set_cursor_pos(1, 2)
	t.delete_chars(1)
	assert t.plain_string() or { '' } == '13456'
}

// ============================================================
// horizontal tabs (left margin)
// ============================================================

fn test_horizontal_tabs_with_left_margin_in_origin_mode() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.origin, true)
	t.scrolling_region.left = 2
	t.scrolling_region.right = 5
	t.set_cursor_pos(1, 2)
	t.print(u32(`X`)) or { assert false }
	t.horizontal_tab_back()
	t.print(u32(`A`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  AX'
}

fn test_horizontal_tab_back_with_cursor_before_left_margin() {
	mut t := create_test_terminal(20, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.origin, true)
	t.save_cursor()
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(5, 0)
	t.restore_cursor()
	t.horizontal_tab_back()
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X'
}

// ============================================================
// insert mode with wide characters
// ============================================================

fn test_insert_mode_with_wide_characters() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('hello') or { assert false }
	t.set_cursor_pos(1, 2)
	t.modes.set(.insert, true)
	t.print(0x1f600) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'h😀el'
}

fn test_insert_mode_with_wide_characters_at_end() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('well') or { assert false }
	t.modes.set(.insert, true)
	t.print(0x1f600) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'well\n😀'
}

fn test_insert_mode_pushing_off_wide_character() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123') or { assert false }
	t.print(0x1F600) or { assert false } // 😀
	t.modes.set(.insert, true)
	t.set_cursor_pos(1, 1)
	t.print(u32(`X`)) or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'X123'
}

// ============================================================
// insertBlanks split multi-cell character
// ============================================================

fn test_insert_blanks_split_multi_cell_character() {
	mut t := create_test_terminal(5, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123') or { assert false }
	t.print(0x6A4B) or { assert false } // 橋
	t.set_cursor_pos(1, 1)
	t.clear_dirty()
	t.insert_blanks(1)
	assert t.is_dirty(active_point(0, 0))

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ' 123'
}

fn test_insert_blanks_deleting_graphemes() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.grapheme_cluster, true)

	t.print_string('ABC') or { assert false }
	for cp in [u32(0x1F468), 0x200D, 0x1F469, 0x200D, 0x1F467] {
		t.print(cp) or { assert false }
	}
	assert active_row(&t, 0).header.grapheme

	t.set_cursor_pos(1, 1)
	t.insert_blanks(4)
	assert t.plain_string() or { '' } == '    A'
	row := active_row(&t, 0)
	assert !row.header.grapheme
	for cell in row.cells {
		assert !cell.has_grapheme()
	}
}

fn test_insert_blanks_shifts_graphemes() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }
	t.modes.set(.grapheme_cluster, true)

	t.print(u32(`A`)) or { assert false }
	for cp in [u32(0x1F468), 0x200D, 0x1F469, 0x200D, 0x1F467] {
		t.print(cp) or { assert false }
	}
	t.set_cursor_pos(1, 1)
	t.insert_blanks(1)

	assert t.plain_string() or { '' } == ' A👨‍👩‍👧'
	row := active_row(&t, 0)
	assert row.header.grapheme
	assert row.cells[2].has_grapheme()
}

fn test_insert_blanks_split_multi_cell_character_from_tail() {
	mut t := create_test_terminal(5, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('橋123') or { assert false }
	t.set_cursor_pos(1, 2)
	t.insert_blanks(1)
	assert t.plain_string() or { '' } == '   12'
}

fn test_insert_blanks_shifts_hyperlinks() {
	mut t := create_test_terminal(10, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.insert_blanks(2)
	assert t.plain_string() or { '' } == '  ABC'

	row := active_row(&t, 0)
	assert row.header.hyperlink
	for x in 0 .. 2 {
		assert !row.cells[x].has_hyperlink
	}
	for x in 2 .. 5 {
		assert row.cells[x].has_hyperlink
		link := cell_hyperlink_at(&t, x, 0) or { panic('cell hyperlink is missing') }
		assert link.uri == 'http://example.com'
	}
}

fn test_insert_blanks_pushes_hyperlink_off_end_completely() {
	mut t := create_test_terminal(3, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.insert_blanks(3)
	assert t.plain_string() or { 'not empty' } == ''

	row := active_row(&t, 0)
	assert !row.header.hyperlink
	for cell in row.cells {
		assert !cell.has_hyperlink
	}
}

// ============================================================
// Background SGR preservation on erase / scroll paths
// ============================================================
//
// Translated from ghostty's Terminal.zig "preserves background sgr" tests.
// A blank cell created while a background color SGR is active is stored with
// content_tag == .bg_color_rgb (or .bg_color_palette) and the color inline,
// NOT as a styled cell.

// Helper: assert that the cell at active (x, y) is a bg_color_rgb cell with
// the given red/green/blue components.
fn assert_bg_rgb(t &Terminal, x int, y int, r u8, g u8, b u8) {
	cell := cell_at(t, x, y)
	assert cell.content_tag == .bg_color_rgb
	assert cell.color_rgb_r() == r
	assert cell.color_rgb_g() == g
	assert cell.color_rgb_b() == b
}

fn test_erase_chars_preserves_background_sgr() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.erase_chars(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  C'
	assert_bg_rgb(&t, 0, 0, 0xFF, 0, 0)
	assert_bg_rgb(&t, 1, 0, 0xFF, 0, 0)
}

fn test_insert_blanks_preserves_background_sgr() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.insert_blanks(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  ABC'
	assert_bg_rgb(&t, 0, 0, 0xFF, 0, 0)
}

fn test_delete_chars_preserves_background_sgr() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABC123') or { assert false }
	t.set_cursor_pos(1, 3)
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.delete_chars(2)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'AB23'
	// The two right-most columns are the vacated blanks.
	for x in int(t.cols) - 2 .. int(t.cols) {
		assert_bg_rgb(&t, x, 0, 0xFF, 0, 0)
	}
}

fn test_erase_line_right_preserves_background_sgr() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	t.set_cursor_pos(1, 2)
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.erase_line(.right, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == 'A'
	for x in 1 .. 5 {
		assert_bg_rgb(&t, x, 0, 0xFF, 0, 0)
	}
}

fn test_erase_line_left_preserves_background_sgr() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	t.set_cursor_pos(1, 2)
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.erase_line(.left, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '  CDE'
	for x in 0 .. 2 {
		assert_bg_rgb(&t, x, 0, 0xFF, 0, 0)
	}
}

fn test_erase_line_complete_preserves_background_sgr() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('ABCDE') or { assert false }
	t.set_cursor_pos(1, 2)
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.erase_line(.complete, false)

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == ''
	for x in 0 .. 5 {
		assert_bg_rgb(&t, x, 0, 0xFF, 0, 0)
	}
}

fn test_index_bottom_of_primary_screen_background_sgr() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_cursor_pos(5, 1)
	t.print(u32(`A`)) or { assert false }
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.index() or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\n\n\nA'
	// The newly-exposed bottom row is filled with the active bg SGR.
	for x in 0 .. 5 {
		assert_bg_rgb(&t, x, 4, 0xFF, 0, 0)
	}
}

fn test_index_bottom_of_scroll_region_background_sgr() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.set_top_and_bottom_margin(1, 3)
	t.set_cursor_pos(4, 1)
	t.print(u32(`B`)) or { assert false }
	t.set_cursor_pos(3, 1)
	t.print(u32(`A`)) or { assert false }
	t.set_attribute(SgrDirectColorBg{ rgb: RGB{ r: 0xFF, g: 0, b: 0 } }) or { assert false }
	t.index() or { assert false }

	str := t.plain_string() or {
		assert false
		return
	}
	assert str == '\nA\n\nB'
	// The newly-exposed blank row at the bottom of the region carries bg SGR.
	for x in 0 .. int(t.cols) {
		assert_bg_rgb(&t, x, 2, 0xFF, 0, 0)
	}
}

fn test_delete_lines_wide_character_spacer_head() {
	mut t := create_test_terminal(5, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	// The wide character wraps through a spacer head at the end of row 1.
	t.print_string('AAAAABBBB😀CCC') or { assert false }
	t.set_cursor_pos(1, 1)
	t.delete_lines(1)

	assert (t.plain_string() or { '' }) == 'BBBB\n😀CCC'
	assert (t.plain_string_unwrapped() or { '' }) == 'BBBB\n😀CCC'
}

fn test_delete_lines_wide_spacer_head_with_left_margin() {
	mut t := create_test_terminal(5, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('AAAAABBBB😀CCC') or { assert false }
	t.scrolling_region.left = 2
	t.set_cursor_pos(1, 3)
	t.delete_lines(1)

	assert (t.plain_string() or { '' }) == 'AABB\nBBCCC\n😀'
	assert (t.plain_string_unwrapped() or { '' }) == 'AABB BBCCC😀'
}

fn test_delete_lines_wide_spacer_head_with_right_margin() {
	mut t := create_test_terminal(5, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('AAAAABBBB😀CCC') or { assert false }
	t.scrolling_region.right = 3
	t.set_cursor_pos(1, 1)
	t.delete_lines(1)

	assert (t.plain_string() or { '' }) == 'BBBBA\n😀CC\n    C'
	assert (t.plain_string_unwrapped() or { '' }) == 'BBBBA😀CC     C'
}

fn test_delete_lines_wide_spacer_head_with_both_margins() {
	mut t := create_test_terminal(5, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('AAAAABBBB😀CCC') or { assert false }
	t.scrolling_region.left = 2
	t.scrolling_region.right = 3
	t.set_cursor_pos(1, 3)
	t.delete_lines(1)

	assert (t.plain_string() or { '' }) == 'AABBA\nBBCC\n😀  C'
	assert (t.plain_string_unwrapped() or { '' }) == 'AABBABBCC😀  C'
}

fn test_delete_lines_wide_spacer_head_with_left_margin_below_two() {
	mut t := create_test_terminal(5, 3) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('AAAAABBBB😀CCC') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(1, 2)
	t.delete_lines(1)

	assert (t.plain_string() or { '' }) == 'ABBBA\nB CC\n    C'
	assert (t.plain_string_unwrapped() or { '' }) == 'ABBBAB CC     C'
}

fn test_delete_lines_clears_wide_characters_split_by_both_margins() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('AAAAA\n😀B😀') or { assert false }
	t.scrolling_region.left = 1
	t.scrolling_region.right = 3
	t.set_cursor_pos(1, 2)
	t.delete_lines(1)

	assert (t.plain_string() or { '' }) == 'A B A'
}

fn test_disabled_wraparound_rejects_wide_char_with_one_space() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, false)
	t.print_string('AAAA') or { assert false }
	t.clear_dirty()
	t.print(0x1f6a8) or { assert false }

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 4
	assert (t.plain_string() or { '' }) == 'AAAA'
	cell := cell_at(&t, 4, 0)
	assert cell.codepoint == 0
	assert cell.wide == .narrow
	assert !t.is_dirty(active_point(0, 0))
}

fn test_disabled_wraparound_rejects_wide_char_with_no_space() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.wraparound, false)
	t.print_string('AAAAA') or { assert false }
	t.clear_dirty()
	t.print(0x1f6a8) or { assert false }

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 4
	assert (t.plain_string() or { '' }) == 'AAAAA'
	cell := cell_at(&t, 4, 0)
	assert cell.codepoint == `A`
	assert cell.wide == .narrow
	assert !t.is_dirty(active_point(0, 0))
}

fn test_disabled_wraparound_rejects_wide_grapheme_with_half_space() {
	mut t := create_test_terminal(5, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.grapheme_cluster, true)
	t.modes.set(.wraparound, false)
	t.print_string('AAAA') or { assert false }
	t.print(0x2764) or { assert false }
	t.clear_dirty()
	t.print(0xfe0f) or { assert false }

	assert t.screens.active.cursor.y == 0
	assert t.screens.active.cursor.x == 4
	assert (t.plain_string() or { '' }) == 'AAAA❤'
	cell := cell_at(&t, 4, 0)
	assert cell.codepoint == 0x2764
	assert cell.wide == .narrow
	assert !t.is_dirty(active_point(0, 0))
}

fn test_print_wraps_at_right_margin() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(3, 5)
	t.set_cursor_pos(1, 5)
	t.print_string('XY') or { assert false }

	assert (t.plain_string() or { '' }) == '1234X6789\n  Y'
	assert !active_row(&t, 0).header.wrap
}

fn test_print_right_margin_wrap_dirty_tracking() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(3, 5)
	t.set_cursor_pos(1, 5)
	t.clear_dirty()
	t.print(u32(`X`)) or { assert false }
	assert t.is_dirty(active_point(4, 0))
	assert !t.is_dirty(active_point(2, 1))

	t.clear_dirty()
	t.print(u32(`Y`)) or { assert false }
	assert t.is_dirty(active_point(4, 0))
	assert t.is_dirty(active_point(2, 1))
	assert (t.plain_string() or { '' }) == '1234X6789\n  Y'
}

fn test_print_outside_right_margin() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(3, 5)
	t.set_cursor_pos(1, 6)
	t.clear_dirty()
	t.print_string('XY') or { assert false }

	assert (t.plain_string() or { '' }) == '12345XY89'
	assert t.is_dirty(active_point(5, 0))
}

fn test_print_outside_right_margin_wraps_to_left_margin() {
	mut t := create_test_terminal(10, 5) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('123456789') or { assert false }
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(3, 5)
	t.set_cursor_pos(1, 10)
	t.print_string('XY') or { assert false }

	assert (t.plain_string() or { '' }) == '123456789X\n  Y'
}

fn test_print_wide_char_at_right_margin_has_no_spacer_head() {
	mut t := create_test_terminal(10, 10) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(3, 5)
	t.set_cursor_pos(1, 5)
	t.print(0x1f600) or { assert false }

	assert t.screens.active.cursor.y == 1
	assert t.screens.active.cursor.x == 4
	assert t.is_dirty(active_point(4, 0))
	assert t.is_dirty(active_point(4, 1))
	old_margin := cell_at(&t, 4, 0)
	assert old_margin.codepoint == 0
	assert old_margin.wide == .narrow
	assert !active_row(&t, 0).header.wrap
	wide := cell_at(&t, 2, 1)
	assert wide.codepoint == 0x1f600
	assert wide.wide == .wide
	assert cell_at(&t, 3, 1).wide == .spacer_tail
}

fn test_print_writes_to_active_bottom_while_viewport_is_scrolled() {
	mut t := create_test_terminal(5, 2) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.print_string('hello') or { assert false }
	t.set_cursor_pos(0, 0)
	t.index() or { assert false }
	t.index() or { assert false }
	t.index() or { assert false }
	assert (t.plain_string() or { '' }) == ''

	t.screens.active.scroll(ScrollTop{})
	assert (t.plain_string() or { '' }) == 'hello'

	t.print(u32(`A`)) or { assert false }
	t.screens.active.scroll(ScrollActive{})
	assert (t.plain_string() or { '' }) == '\nA'
	assert t.is_dirty(active_point(int(t.screens.active.cursor.x), int(t.screens.active.cursor.y)))
}

fn test_print_with_hyperlink() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	t.print_string('123456') or { assert false }
	row := active_row(&t, 0)
	assert row.header.hyperlink
	for x in 0 .. 6 {
		assert row.cells[x].has_hyperlink
		link := cell_hyperlink_at(&t, x, 0) or { panic('cell hyperlink is missing') }
		assert link.uri == 'http://example.com'
		assert link.id is HyperlinkImplicitId
		assert (link.id as HyperlinkImplicitId).offset == 0
	}
}

fn test_print_over_cell_with_same_hyperlink() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	t.print_string('123456') or { assert false }
	t.set_cursor_pos(1, 1)
	t.print_string('123456') or { assert false }
	row := active_row(&t, 0)
	assert row.header.hyperlink
	for x in 0 .. 6 {
		assert row.cells[x].has_hyperlink
		link := cell_hyperlink_at(&t, x, 0) or { panic('cell hyperlink is missing') }
		assert link.uri == 'http://example.com'
		assert (link.id as HyperlinkImplicitId).offset == 0
	}
}

fn test_print_and_end_hyperlink() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://example.com', none) or { assert false }
	t.print_string('123') or { assert false }
	t.screens.active.end_hyperlink()
	t.print_string('456') or { assert false }
	row := active_row(&t, 0)
	assert row.header.hyperlink
	for x in 0 .. 3 {
		assert row.cells[x].has_hyperlink
		link := cell_hyperlink_at(&t, x, 0) or { panic('cell hyperlink is missing') }
		assert link.uri == 'http://example.com'
	}
	for x in 3 .. 6 {
		assert !row.cells[x].has_hyperlink
	}
}

fn test_print_and_change_hyperlink() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://one.example.com', none) or { assert false }
	t.print_string('123') or { assert false }
	t.screens.active.start_hyperlink('http://two.example.com', none) or { assert false }
	t.print_string('456') or { assert false }
	row := active_row(&t, 0)
	for x in 0 .. 3 {
		assert row.cells[x].has_hyperlink
		link := cell_hyperlink_at(&t, x, 0) or { panic('cell hyperlink is missing') }
		assert link.uri == 'http://one.example.com'
		assert (link.id as HyperlinkImplicitId).offset == 0
	}
	for x in 3 .. 6 {
		assert row.cells[x].has_hyperlink
		link := cell_hyperlink_at(&t, x, 0) or { panic('cell hyperlink is missing') }
		assert link.uri == 'http://two.example.com'
		assert (link.id as HyperlinkImplicitId).offset == 1
	}
}

fn test_overwrite_hyperlink_clears_row_flag() {
	mut t := create_test_terminal(80, 80) or {
		assert false
		return
	}
	defer { t.deinit() }

	t.screens.active.start_hyperlink('http://one.example.com', none) or { assert false }
	t.print_string('123') or { assert false }
	t.set_cursor_pos(1, 1)
	t.screens.active.end_hyperlink()
	t.print_string('456') or { assert false }
	row := active_row(&t, 0)
	assert !row.header.hyperlink
	for x in 0 .. 3 {
		assert !row.cells[x].has_hyperlink
	}
}
