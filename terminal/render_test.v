module terminal

import strings

// Tests for RenderState, translated from Ghostty's render.zig.
//
// The witty RenderState operates on the simplified Pages model (a flat
// screen_rows array with an active_start offset) rather than Ghostty's
// PageList + MultiArrayList. The observable behavior of RenderState.update,
// link_cells, to_string and the dirty tracking is preserved so these tests
// mirror the Ghostty originals.

fn test_render_dirty_source_layout() {
	assert sizeof(RenderDirty) == 1
	assert u8(RenderDirty.false_) == 0
	assert u8(RenderDirty.partial) == 1
	assert u8(RenderDirty.full) == 2
}

// ============================================================
// styled
// ============================================================

fn test_render_state_styled() {
	// Fill the screen with decaln, then update. This just exercises the
	// full-screen rebuild path.
	mut t := Terminal.init(Options{ cols: 80, rows: 24 })!
	defer {
		t.deinit()
	}

	t.decaln()!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	assert state.row_data.len == 24
}

// ============================================================
// basic text
// ============================================================

fn test_render_state_basic_text() {
	mut t := Terminal.init(Options{ cols: 10, rows: 3 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('ABCD'.bytes())!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	// Verify we have the right number of rows
	assert state.row_data.len == 3

	// All rows should have cols cells
	assert state.row_data[0].cells.len == 10
	assert state.row_data[1].cells.len == 10
	assert state.row_data[2].cells.len == 10

	// Row zero should contain our text
	assert state.row_data[0].cells[0].raw.codepoint() == u32(`A`)
	assert state.row_data[0].cells[1].raw.codepoint() == u32(`B`)
	assert state.row_data[0].cells[2].raw.codepoint() == u32(`C`)
	assert state.row_data[0].cells[3].raw.codepoint() == u32(`D`)
	assert state.row_data[0].cells[4].raw.codepoint() == 0
}

// ============================================================
// styled text
// ============================================================

fn test_render_state_styled_text() {
	mut t := Terminal.init(Options{ cols: 10, rows: 3 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('\x1b[1mA'.bytes())! // Bold
	s.next_slice('\x1b[0;3mB'.bytes())! // Italic
	s.next_slice('\x1b[0;4mC'.bytes())! // Underline

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	assert state.row_data.len == 3
	assert state.row_data[0].cells.len == 10
	assert state.row_data[1].cells.len == 10
	assert state.row_data[2].cells.len == 10

	// Row zero should contain our styled text
	c0 := state.row_data[0].cells[0]
	assert c0.raw.codepoint() == u32(`A`)
	assert c0.style.flags.bold()

	c1 := state.row_data[0].cells[1]
	assert c1.raw.codepoint() == u32(`B`)
	assert !c1.style.flags.bold()
	assert c1.style.flags.italic()

	assert state.row_data[0].cells[2].raw.codepoint() == u32(`C`)
	assert state.row_data[0].cells[3].raw.codepoint() == 0
}

// ============================================================
// grapheme
// ============================================================

fn test_render_state_grapheme() {
	mut t := Terminal.init(Options{ cols: 10, rows: 3 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('A'.bytes())!
	s.next_slice('👨‍'.bytes())! // this has a ZWJ

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	assert state.row_data.len == 3
	assert state.row_data[0].cells.len == 10

	// Row zero should contain our text
	assert state.row_data[0].cells[0].raw.codepoint() == u32(`A`)

	c1 := state.row_data[0].cells[1]
	assert c1.raw.codepoint() == 0x1F468
	assert c1.raw.wide == .wide
	assert c1.grapheme == [u32(0x200D)]

	c2 := state.row_data[0].cells[2]
	assert c2.raw.codepoint() == 0
	assert c2.raw.wide == .spacer_tail
}

fn test_render_state_reuses_row_storage_and_clears_old_cell_data() ! {
	mut t := Terminal.init(Options{cols: 10, rows: 3})!
	defer { t.deinit() }
	mut stream := t.vt_stream()
	defer { stream.deinit() }
	mut state := RenderState.empty()
	defer { state.deinit() }
	stream.next_slice('\x1b[1m👨‍'.bytes())!
	state.update(mut t)
	storage := state.row_data[0].cells.data
	assert state.row_data[0].cells[0].style.flags.bold()
	assert state.row_data[0].cells[0].grapheme == [u32(0x200D)]

	stream.next_slice('\x1b[0m\x1b[2J\x1b[Hplain'.bytes())!
	state.update(mut t)
	assert state.row_data[0].cells.data == storage
	assert state.row_data[0].cells[0].raw.codepoint() == u32(`p`)
	assert state.row_data[0].cells[0].style.default()
	assert state.row_data[0].cells[0].grapheme.len == 0
}

// ============================================================
// cursor state in viewport
// ============================================================

fn test_render_state_cursor_in_viewport() {
	mut t := Terminal.init(Options{ cols: 10, rows: 5 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('A\x1b[H'.bytes())!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}

	// Initial update
	state.update(mut t)
	assert state.cursor.active.x == 0
	assert state.cursor.active.y == 0
	assert (state.cursor.viewport or { panic('nil') }).x == 0
	assert (state.cursor.viewport or { panic('nil') }).y == 0
	assert state.cursor.cell.codepoint() == u32(`A`)
	assert state.cursor.style.default()

	// Set a style on the cursor
	s.next_slice('\x1b[1m'.bytes())! // Bold
	state.update(mut t)
	assert !state.cursor.style.default()
	assert state.cursor.style.flags.bold()
	s.next_slice('\x1b[0m'.bytes())! // Reset style

	// Move cursor to 2,1
	s.next_slice('\x1b[2;3H'.bytes())!
	state.update(mut t)
	assert state.cursor.active.x == 2
	assert state.cursor.active.y == 1
	assert (state.cursor.viewport or { panic('nil') }).x == 2
	assert (state.cursor.viewport or { panic('nil') }).y == 1
}

// ============================================================
// cursor state out of viewport
// ============================================================

fn test_render_state_cursor_out_of_viewport() {
	mut t := Terminal.init(Options{ cols: 10, rows: 2, max_scrollback: 10000 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('A\r\nB\r\nC\r\nD\r\n'.bytes())!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}

	// Initial update
	state.update(mut t)
	assert state.cursor.active.x == 0
	assert state.cursor.active.y == 1
	assert (state.cursor.viewport or { panic('nil') }).x == 0
	assert (state.cursor.viewport or { panic('nil') }).y == 1

	// Scroll the viewport to the top
	t.scroll_viewport(scroll_viewport_top)!
	state.update(mut t)

	// The cursor is still in the active area but out of the viewport.
	assert state.cursor.active.x == 0
	assert state.cursor.active.y == 1
	assert state.cursor.viewport == none

	// The active cursor cell is still refreshed even though it has no viewport
	// coordinate while scrollback is being viewed.
	s.next_slice('Z\r'.bytes())!
	state.update(mut t)
	assert state.cursor.viewport == none
	assert state.cursor.cell.codepoint() == u32(`Z`)
}

// ============================================================
// dirty state
// ============================================================

fn test_render_state_dirty() {
	mut t := Terminal.init(Options{ cols: 10, rows: 5 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}

	// First update should trigger redraw due to resize
	state.update(mut t)
	assert state.dirty == .full

	// Reset dirty flag and dirty rows
	state.dirty = .false_
	for mut r in state.row_data {
		r.dirty = false
	}

	// Second update with no changes - no dirty rows
	state.update(mut t)
	assert state.dirty == .false_
	for r in state.row_data {
		assert !r.dirty
	}

	// Write to first line
	s.next_slice('A'.bytes())!
	state.update(mut t)
	assert state.dirty == .partial
	assert state.row_data[0].dirty // First row dirty
	assert !state.row_data[1].dirty // Second row clean
}

// ============================================================
// colors
// ============================================================

fn test_render_state_colors() {
	mut t := Terminal.init(Options{ cols: 10, rows: 5 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}

	// Default colors
	state.update(mut t)

	// Change cursor color
	s.next_slice('\x1b]12;#FF0000\a'.bytes())!
	state.update(mut t)

	c := state.colors.cursor or { panic('nil cursor color') }
	assert c.r == 0xFF
	assert c.g == 0
	assert c.b == 0

	// Change palette color 0 to White
	s.next_slice('\x1b]4;0;#FFFFFF\a'.bytes())!
	state.update(mut t)
	p0 := state.colors.palette[0]
	assert p0.r == 0xFF
	assert p0.g == 0xFF
	assert p0.b == 0xFF
}

// ============================================================
// selection single line
// ============================================================

fn test_render_state_selection_single_line() {
	mut t := Terminal.init(Options{ cols: 10, rows: 3 })!
	defer {
		t.deinit()
	}

	mut screen := t.screens.active
	p1 := screen.pages.pin(Point.new(.active, Coordinate{ x: 0, y: 1 })) or { panic('no pin') }
	p2 := screen.pages.pin(Point.new(.active, Coordinate{ x: 2, y: 1 })) or { panic('no pin') }
	screen.select(Selection.init(p1, p2, false))!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	assert state.row_data[0].selection == none
	assert state.row_data[1].selection or { panic('nil') } == [u16(0), u16(2)]!
	assert state.row_data[2].selection == none

	// Clear the selection
	screen.select(none)!
	state.update(mut t)
	assert state.row_data[0].selection == none
	assert state.row_data[1].selection == none
	assert state.row_data[2].selection == none
}

fn test_render_state_selection_starts_on_wide_glyph_tail() ! {
	mut t := Terminal.init(Options{ cols: 8, rows: 3 })!
	defer { t.deinit() }
	t.print_string('A界B')!
	mut screen := t.screens.active
	tail := screen.pages.pin(Point.new(.active, Coordinate{ x: 2, y: 0 })) or { panic('no pin') }
	end := screen.pages.pin(Point.new(.active, Coordinate{ x: 3, y: 0 })) or { panic('no pin') }
	assert tail.row_and_cell().cell.wide == .spacer_tail
	screen.select(Selection.init(tail, end, false))!

	mut state := RenderState.empty()
	defer { state.deinit() }
	state.update(mut t)
	assert state.row_data[0].selection or { panic('missing selection') } == [u16(1), u16(3)]!
}

fn test_render_state_selection_ends_on_wrapped_wide_glyph() ! {
	mut t := Terminal.init(Options{ cols: 5, rows: 3 })!
	defer { t.deinit() }
	t.print_string('ABCD界')!
	mut screen := t.screens.active
	start := screen.pages.pin(Point.new(.active, Coordinate{ x: 2, y: 0 })) or { panic('no pin') }
	head := screen.pages.pin(Point.new(.active, Coordinate{ x: 4, y: 0 })) or { panic('no pin') }
	assert head.row_and_cell().cell.wide == .spacer_head

	mut state := RenderState.empty()
	defer { state.deinit() }
	screen.select(Selection.init(start, head, false))!
	state.update(mut t)
	assert state.row_data[0].selection or { panic('missing selection') } == [u16(2), u16(4)]!
	assert state.row_data[1].selection or { panic('missing wrapped selection') } == [u16(0), u16(0)]!

	screen.select(Selection.init(start, head, true))!
	state.update(mut t)
	assert state.row_data[0].selection or { panic('missing rectangle') } == [u16(2), u16(4)]!
	assert state.row_data[1].selection == none
}

// ============================================================
// selection multiple lines
// ============================================================

fn test_render_state_selection_multiple_lines() {
	mut t := Terminal.init(Options{ cols: 10, rows: 3 })!
	defer {
		t.deinit()
	}

	mut screen := t.screens.active
	p1 := screen.pages.pin(Point.new(.active, Coordinate{ x: 0, y: 1 })) or { panic('no pin') }
	p2 := screen.pages.pin(Point.new(.active, Coordinate{ x: 2, y: 2 })) or { panic('no pin') }
	screen.select(Selection.init(p1, p2, false))!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	assert state.row_data[0].selection == none
	assert state.row_data[1].selection or { panic('nil') } == [u16(0), u16(screen.pages.cols) - 1]!
	assert state.row_data[2].selection or { panic('nil') } == [u16(0), u16(2)]!
}

fn test_render_state_rectangle_selection_mirrored_axes() {
	mut t := Terminal.init(Options{ cols: 10, rows: 3 })!
	defer {
		t.deinit()
	}

	mut screen := t.screens.active
	// Drag from the top-right to the bottom-left. Rectangle orientation only
	// mirrors the x axis here; every selected row must retain the same bounds.
	p1 := screen.pages.pin(Point.new(.active, Coordinate{ x: 4, y: 0 })) or { panic('no pin') }
	p2 := screen.pages.pin(Point.new(.active, Coordinate{ x: 1, y: 2 })) or { panic('no pin') }
	screen.select(Selection.init(p1, p2, true))!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	for row in state.row_data {
		assert row.selection or { panic('missing rectangle row') } == [u16(1), u16(4)]!
	}
}

// ============================================================
// linkCells
// ============================================================

fn test_render_state_link_cells() {
	mut t := Terminal.init(Options{ cols: 10, rows: 5 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}

	// Create a hyperlink
	s.next_slice('\x1b]8;;http://example.com\x1b\\LINK\x1b]8;;\x1b\\'.bytes())!
	state.update(mut t)

	// Query link at 0,0
	cells := state.link_cells(Coordinate{ x: 0, y: 0 })
	assert cells.len == 4
	assert cells[cell_set_key(0, 0)]
	assert cells[cell_set_key(1, 0)]
	assert cells[cell_set_key(2, 0)]
	assert cells[cell_set_key(3, 0)]

	// Query no link
	cells2 := state.link_cells(Coordinate{ x: 4, y: 0 })
	assert cells2.len == 0
}

// ============================================================
// string
// ============================================================

fn test_render_state_string() {
	mut t := Terminal.init(Options{ cols: 5, rows: 2 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('AB'.bytes())!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	mut writer := strings.new_builder(10)
	state.string(mut writer, none)
	result := writer.str()
	expected := 'AB\x00\x00\x00\n\x00\x00\x00\x00\x00\n'
	assert result == expected
}

fn test_render_state_string_map() {
	mut t := Terminal.init(Options{ cols: 2, rows: 1 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('\u00e9'.bytes())!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	mut writer := strings.new_builder(4)
	mut string_map := RenderStringMap{}
	state.string(mut writer, RenderStringOptions{
		map: &string_map
	})
	result := writer.str()
	assert result == '\u00e9\x00\n'
	assert string_map.points.len == result.len
	assert string_map.points[0].eql(Coordinate{ x: 0, y: 0 })
	assert string_map.points[1].eql(Coordinate{ x: 0, y: 0 })
	assert string_map.points[2].eql(Coordinate{ x: 1, y: 0 })
	assert string_map.points[3].eql(Coordinate{ x: 2, y: 0 })
}

// ============================================================
// linkCells with scrollback spanning pages
// ============================================================

// SKIPPED: This test depends on Ghostty's PageList with multiple page
// nodes and cross-page hyperlink lookup (page.std_capacity, page node
// boundaries). The witty simplified Pages model uses a single flat
// screen_rows array, so there is no page boundary to span and the
// specific crash this test guards against cannot occur here.

// ============================================================
// linkCells with invalid viewport point
// ============================================================

fn test_render_state_link_cells_with_scrollback_spanning_pages() {
	viewport_rows := u16(10)
	tail_rows := u16(5)

	mut t := Terminal.init(Options{
		cols:           std_capacity.cols
		rows:           viewport_rows
		max_scrollback: 10_000
	})!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}

	first_node := t.screens.active.pages.pages.first or { panic('missing first page') }
	first_page_cap := first_node.data.capacity.rows

	// Fill first page
	for _ in 0 .. int(first_page_cap) - 1 {
		s.next_slice('\r\n'.bytes())!
	}

	// Create second page with hyperlink
	s.next_slice('\r\n'.bytes())!
	s.next_slice('\x1b]8;;http://example.com\x1b\\LINK\x1b]8;;\x1b\\'.bytes())!
	for _ in 0 .. int(tail_rows) - 1 {
		s.next_slice('\r\n'.bytes())!
	}

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	expected_viewport_y := u32(viewport_rows - tail_rows)
	// BUG: This crashes without the fix
	cells := state.link_cells(Coordinate{
		x: 0
		y: expected_viewport_y
	})
	assert cells.len == 4
}

fn test_render_state_link_cells_invalid_point() {
	mut t := Terminal.init(Options{ cols: 10, rows: 5 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	// Row out of bound
	cells := state.link_cells(Coordinate{ x: 0, y: u32(t.rows) + 10 })
	assert cells.len == 0

	// Col out of bound
	cells2 := state.link_cells(Coordinate{ x: t.cols + 10, y: 0 })
	assert cells2.len == 0
}

// ============================================================
// dirty row resets highlights
// ============================================================

fn test_render_state_dirty_row_resets_highlights() {
	mut t := Terminal.init(Options{ cols: 10, rows: 3 })!
	defer {
		t.deinit()
	}

	mut s := t.vt_stream()
	defer {
		s.deinit()
	}
	s.next_slice('ABC'.bytes())!

	mut state := RenderState.empty()
	defer {
		state.deinit()
	}
	state.update(mut t)

	// Reset dirty state
	state.dirty = .false_
	for mut r in state.row_data {
		r.dirty = false
	}

	// Manually add a highlight to row 0
	state.row_data[0].highlights << RenderHighlight{
		tag: 1
		range: [u16(0), u16(2)]!
	}

	// Verify we have a highlight
	assert state.row_data[0].highlights.len == 1

	// Write to row 0 to make it dirty
	s.next_slice('\x1b[H'.bytes())! // Move to home
	s.next_slice('X'.bytes())!
	state.update(mut t)

	// Verify the highlight was reset on the dirty row
	assert state.row_data[0].highlights.len == 0
}

fn test_render_state_update_flattened_highlights() {
	mut t := Terminal.init(Options{ cols: 10, rows: 4 })!
	defer { t.deinit() }
	mut state := RenderState.empty()
	defer { state.deinit() }
	state.update(mut t)
	state.dirty = .false_

	node := t.screens.active.pages.pages.first or { panic('missing first page') }
	state.update_highlights_flattened(7, [RenderFlattenedHighlight{
		chunks: [RenderHighlightChunk{
			node: node
			serial: node.serial
			start: 1
			end: 3
		}]
		top_x: 2
		bot_x: 4
	}])

	assert state.row_data[0].highlights.len == 0
	assert state.row_data[1].highlights == [RenderHighlight{
		tag: 7
		range: [u16(2), u16(9)]!
	}]
	assert state.row_data[2].highlights == [RenderHighlight{
		tag: 7
		range: [u16(0), u16(4)]!
	}]
	assert state.row_data[3].highlights.len == 0
	assert state.row_data[1].dirty
	assert state.row_data[2].dirty
	assert state.dirty == .partial
}
