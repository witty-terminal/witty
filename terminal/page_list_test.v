module terminal

import buildcfg

fn test_page_list_direction_values_match_source_order() ! {
	assert sizeof(IterDirection) == 1
	assert int(IterDirection.left_up) == 0
	assert int(IterDirection.right_down) == 1
}

fn test_page_list_internal_tag_layouts_match_source() ! {
	assert sizeof(PageViewport) == 1
	assert u8(PageViewport.active) == 0
	assert u8(PageViewport.top) == 1
	assert u8(PageViewport.pin) == 2
	assert sizeof(PinCellSubset) == 1
	assert u8(PinCellSubset.all) == 0
	assert u8(PinCellSubset.left) == 1
	assert u8(PinCellSubset.right) == 2
	assert sizeof(PageReflowWriteResult) == 1
	assert u8(PageReflowWriteResult.success) == 0
	assert u8(PageReflowWriteResult.repeat) == 1
	assert u8(PageReflowWriteResult.skip_next) == 2
	assert sizeof(IncreaseCapacity) == 1
	assert u8(IncreaseCapacity.styles) == 0
	assert u8(IncreaseCapacity.grapheme_bytes) == 1
	assert u8(IncreaseCapacity.hyperlink_bytes) == 2
	assert u8(IncreaseCapacity.string_bytes) == 3
}

// Tests translated from Ghostty's PageList.zig

// ============================================================
// Helper: write a codepoint into a cell in the active area
// ============================================================

fn set_active_cell(mut pl PageList, x u16, y u16, cp u32) {
	p := pl.pin(Point.new(.active, Coordinate{ x: x, y: y })) or { return }
	if int(p.y) < p.node.data.rows.len {
		mut row := &p.node.data.rows[int(p.y)]
		if int(p.x) < row.cells.len {
			row.cells[int(p.x)] = CellData{
				content_tag: .codepoint
				codepoint:   cp
			}
		}
	}
}

fn set_screen_cell(mut pl PageList, x u16, y u16, cp u32) {
	p := pl.pin(Point.new(.screen, Coordinate{ x: x, y: y })) or { return }
	if int(p.y) < p.node.data.rows.len {
		mut row := &p.node.data.rows[int(p.y)]
		if int(p.x) < row.cells.len {
			row.cells[int(p.x)] = CellData{
				content_tag: .codepoint
				codepoint:   cp
			}
		}
	}
}

fn set_screen_semantic_cell(mut pl PageList, x u16, y u16, cp u32, semantic SemanticContent) {
	p := pl.pin(Point.new(.screen, Coordinate{ x: x, y: y })) or { return }
	mut row := &p.node.data.rows[int(p.y)]
	row.cells[int(p.x)] = CellData{
		content_tag:      .codepoint
		codepoint:        cp
		semantic_content: semantic
	}
}

fn set_screen_semantic_range(mut pl PageList, y u16, start u16, end u16, cp u32, semantic SemanticContent) {
	for x in start .. end {
		set_screen_semantic_cell(mut pl, x, y, cp, semantic)
	}
}

fn mark_screen_prompt(mut pl PageList, y u16) {
	mut p := pl.pin(Point.new(.screen, Coordinate{ x: 0, y: y })) or { return }
	p.node.data.rows[int(p.y)].header.semantic_prompt = .prompt
}

fn assert_page_list_semantic_highlight(pl &PageList, at Pin, content SemanticContent, start Pin, end Pin) {
	at_pin := pl.pin(Point.new(.screen, Coordinate{ x: u16(at.x), y: u16(at.y) })) or {
		assert false, 'highlight start pin missing'
		return
	}
	hl := pl.highlight_semantic_content(at_pin, content) or {
		assert false, 'semantic highlight missing'
		return
	}
	start_point := pl.point_from_pin(.screen, hl.start) or {
		assert false
		return
	}
	end_point := pl.point_from_pin(.screen, hl.end) or {
		assert false
		return
	}
	assert start_point is PointScreen
	assert start_point.coord().x == start.x
	assert start_point.coord().y == start.y
	assert end_point is PointScreen
	assert end_point.coord().x == end.x
	assert end_point.coord().y == end.y
}

fn grow_page_list_to_second_page(mut pl PageList, extra_rows uint) {
	first := pl.pages.first or { return }
	remaining := uint(first.data.capacity.rows - first.data.size.rows)
	pl.grow_rows(remaining) or { panic(err) }
	assert pl.total_pages() == 1
	pl.grow_rows(extra_rows) or { panic(err) }
	assert pl.total_pages() == 2
}

// ============================================================
// Init tests
// ============================================================

fn test_page_list_init_tripwire_layouts_and_cleanup() ! {
	assert sizeof(PageListInitFailPoint) == 1
	assert u8(PageListInitFailPoint.init_memory_pool) == 0
	assert u8(PageListInitFailPoint.init_pages) == 1
	assert u8(PageListInitFailPoint.viewport_pin) == 2
	assert u8(PageListInitFailPoint.viewport_pin_track) == 3
	assert sizeof(PageListInitPagesFailPoint) == 1
	assert u8(PageListInitPagesFailPoint.page_node) == 0
	assert u8(PageListInitPagesFailPoint.page_buf_std) == 1
	assert u8(PageListInitPagesFailPoint.page_buf_non_std) == 2

	for point in [PageListInitFailPoint.init_memory_pool, .init_pages, .viewport_pin,
		.viewport_pin_track] {
		mut tw := page_list_init_tripwire()
		tw.error_always(point, error('OutOfMemory'))
		if _ := PageList.init(80, 24, none) {
			assert false, 'expected init failure at ${point}'
		} else {
			assert err.msg() == 'OutOfMemory'
		}
		tw.end(.reset)!
	}

	max_standard_cols := std_capacity.max_cols() or { panic('standard capacity has no columns') }
	nonstandard_cols := max_standard_cols + 1
	for point in [PageListInitPagesFailPoint.page_node, .page_buf_std, .page_buf_non_std] {
		cols := if point == .page_buf_std { u16(80) } else { nonstandard_cols }
		mut tw := page_list_init_pages_tripwire()
		tw.error_always(point, error('OutOfMemory'))
		if _ := PageList.init(cols, 24, none) {
			assert false, 'expected page init failure at ${point}'
		} else {
			assert err.msg() == 'OutOfMemory'
		}
		tw.end(.reset)!
	}

	// Fail the second non-standard page allocation to exercise cleanup of a
	// page that was already appended successfully.
	nonstandard_cap := initial_capacity(nonstandard_cols)
	mut tw := page_list_init_pages_tripwire()
	tw.error_after(.page_buf_non_std, error('OutOfMemory'), 1)
	if _ := PageList.init(nonstandard_cols, nonstandard_cap.rows + 1, none) {
		assert false, 'expected second non-standard page failure'
	} else {
		assert err.msg() == 'OutOfMemory'
	}
	tw.end(.reset)!
}

fn test_page_list_init() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.cols == 80
	assert s.rows == 24
	assert s.total_rows == 24
	assert s.viewport == .active

	// Verify we can get cells in the active area
	cell := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert cell.cell.codepoint == 0
}

fn test_page_list_init_without_limit_uses_max_usize() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }

	assert s.explicit_max_size == ~uint(0)
}

fn test_page_list_scrollbar_cval() ! {
	value := Scrollbar{ total: 42, offset: 7, len: 24 }.cval()
	assert value.total == 42
	assert value.offset == 7
	assert value.len == 24
}

fn test_page_list_increase_capacity_rejects_layout_over_max_page_size() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	// Only the capacity metadata needs to be large to exercise the guard; the
	// rejected path must not attempt to allocate or clone this layout.
	first.data.capacity.cols = max_u16
	first.data.capacity.rows = max_u16
	old_serial := s.page_serial
	mut error_message := ''
	s.increase_capacity(first, .styles) or { error_message = err.msg() }
	assert error_message == 'OutOfSpace'
	current := s.pages.first or {
		assert false
		return
	}
	assert voidptr(current) == voidptr(first)
	assert s.page_serial == old_serial
}

fn test_page_list_increase_capacity_rehashes_without_growing() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	old_capacity := first.data.capacity
	tracked := s.track_pin(Pin{ node: first, y: 1, x: 1 })!
	new_node := s.increase_capacity(first, none) or {
		assert false, err.msg()
		return
	}
	assert voidptr(new_node) != voidptr(first)
	assert new_node.data.capacity == old_capacity
	assert voidptr(tracked.node) == voidptr(new_node)
	assert tracked.y == 1
	assert tracked.x == 1
}

fn test_page_list_increase_capacity_to_increase_styles() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	original_capacity := first.data.capacity.styles
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			first.data.rows[y].cells[x].codepoint = u32(x)
		}
	}

	new_node := s.increase_capacity(first, .styles) or { panic(err) }
	assert s.total_pages() == 1
	assert new_node.data.capacity.styles == original_capacity * 2
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			assert new_node.data.rows[y].cells[x].codepoint == u32(x)
		}
	}
}

fn test_page_list_increase_capacity_to_increase_graphemes() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	original_capacity := first.data.capacity.grapheme_bytes
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			first.data.rows[y].cells[x].codepoint = u32(x)
		}
	}

	new_node := s.increase_capacity(first, .grapheme_bytes) or { panic(err) }
	assert s.total_pages() == 1
	assert new_node.data.capacity.grapheme_bytes == original_capacity * 2
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			assert new_node.data.rows[y].cells[x].codepoint == u32(x)
		}
	}
}

fn test_page_list_increase_capacity_to_increase_hyperlinks() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	original_capacity := first.data.capacity.hyperlink_bytes
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			first.data.rows[y].cells[x].codepoint = u32(x)
		}
	}

	new_node := s.increase_capacity(first, .hyperlink_bytes) or { panic(err) }
	assert s.total_pages() == 1
	assert new_node.data.capacity.hyperlink_bytes == original_capacity * 2
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			assert new_node.data.rows[y].cells[x].codepoint == u32(x)
		}
	}
}

fn test_page_list_increase_capacity_to_increase_string_bytes() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	original_capacity := first.data.capacity.string_bytes
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			first.data.rows[y].cells[x].codepoint = u32(x)
		}
	}

	new_node := s.increase_capacity(first, .string_bytes) or { panic(err) }
	assert s.total_pages() == 1
	assert new_node.data.capacity.string_bytes == original_capacity * 2
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			assert new_node.data.rows[y].cells[x].codepoint == u32(x)
		}
	}
}

fn test_page_list_increase_capacity_tracked_pins() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	old_node := s.pages.first or {
		assert false
		return
	}
	tracked := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 1, y: 1 })) or {
		assert false
		return
	})!
	assert voidptr(old_node) == voidptr(tracked.node)

	new_node := s.increase_capacity(old_node, .styles) or { panic(err) }
	assert voidptr(new_node) == voidptr(tracked.node)
	assert tracked.x == 1
	assert tracked.y == 1
}

fn test_page_list_increase_capacity_returns_out_of_space_at_max_capacity() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	for {
		first := s.pages.first or {
			assert false
			return
		}
		s.increase_capacity(first, .styles) or {
			assert err.msg() == 'OutOfSpace'
			current := s.pages.first or {
				assert false
				return
			}
			assert current.data.capacity.styles == max_u16
			break
		}
	}
}

fn test_page_list_increase_capacity_after_col_shrink() ! {
	mut s := PageList.init(10, 2, uint(0))!
	defer { s.deinit() }

	s.resize(PageResizeOpts{
		cols:   5
		reflow: false
	}) or { panic(err) }
	assert s.cols == 5
	mut first := s.pages.first or {
		assert false
		return
	}
	assert first.data.size.cols == 5
	assert first.data.capacity.cols >= 10

	new_node := s.increase_capacity(first, .styles) or { panic(err) }
	assert new_node.data.size.cols == 5
	assert s.cols == 5
}

fn test_page_list_increase_capacity_multi_page() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	for s.pages.first == s.pages.last {
		_ = s.grow()!
	}
	second := s.pages.last or {
		assert false
		return
	}
	first_styles_capacity := first.data.capacity.styles
	second_styles_capacity := second.data.capacity.styles

	new_first := s.increase_capacity(first, .styles) or { panic(err) }
	assert new_first.data.capacity.styles == first_styles_capacity * 2
	last := s.pages.last or {
		assert false
		return
	}
	assert last.data.capacity.styles == second_styles_capacity
}

fn test_page_list_increase_capacity_preserves_dirty_flag() ! {
	mut s := PageList.init(2, 4, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.dirty = true
	first.data.rows[0].header.dirty = true
	first.data.rows[1].header.dirty = false
	first.data.rows[2].header.dirty = true
	first.data.rows[3].header.dirty = false

	new_node := s.increase_capacity(first, .styles) or { panic(err) }
	assert new_node.data.dirty
	assert new_node.data.rows[0].header.dirty
	assert !new_node.data.rows[1].header.dirty
	assert new_node.data.rows[2].header.dirty
	assert !new_node.data.rows[3].header.dirty
}

fn test_page_list_grow_allows_exceeding_max_size_for_active_area() ! {
	cap := initial_capacity(5)
	mut s := PageList.init(5, cap.rows, uint(0))!
	defer { s.deinit() }
	assert s.count_total_rows() == uint(s.rows)

	_ = s.grow()!
	start_pages := s.total_pages()
	assert start_pages >= 2

	mut node := s.pages.first
	for {
		mut page_node := node or { break }
		page_node.data.size.rows = 1
		page_node.data.capacity.rows = 1
		node = page_node.next
	}
	s.total_rows = s.count_total_rows()

	_ = s.grow()!
	assert s.total_pages() == start_pages + 1
}

fn test_page_list_grow_prune_required_with_a_single_page() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }

	for {
		first := s.pages.first or {
			assert false
			return
		}
		if Page.layout(first.data.capacity).total_size > standard_page_size() {
			break
		}
		s.increase_capacity(first, .grapheme_bytes) or { panic(err) }
	}
	assert s.total_pages() == 1

	first := s.pages.first or {
		assert false
		return
	}
	remaining := first.data.capacity.rows - first.data.size.rows
	for _ in 0 .. int(remaining) {
		assert s.grow()!.node == none
	}
	new_node := s.grow()!.node or {
		assert false
		return
	}
	current_first := s.pages.first or {
		assert false
		return
	}
	assert voidptr(new_node) != voidptr(current_first)
	assert s.scrollbar().eql(Scrollbar{
		total:  s.count_total_rows()
		offset: s.total_rows - uint(s.rows)
		len:    uint(s.rows)
	})
}

fn test_page_list_compact_standard_size_page_returns_none() ! {
	mut s := PageList.init(80, 24, uint(0))!
	defer { s.deinit() }

	node := s.pages.first or {
		assert false
		return
	}
	assert page_backing_size(node.data.capacity) <= standard_page_size()
	assert s.compact(node)!.node == none
	current := s.pages.first or {
		assert false
		return
	}
	assert voidptr(current) == voidptr(node)
}

fn test_page_list_compact_oversized_page() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }

	mut first := s.pages.first or {
		assert false
		return
	}
	for s.total_pages() == 1 {
		_ = s.grow()!
	}
	for y in 0 .. int(first.data.size.rows) {
		for x in 0 .. int(s.cols) {
			first.data.rows[y].cells[x].codepoint = u32(x + y * int(s.cols))
		}
	}
	tracked := s.track_pin(Pin{
		node: first
		x:    5
		y:    10
	})!

	mut node := first
	for page_backing_size(node.data.capacity) <= standard_page_size() {
		node = s.increase_capacity(node, .grapheme_bytes) or { panic(err) }
	}
	oversized_size := page_backing_size(node.data.capacity)
	original_rows := node.data.size.rows
	original_cols := node.data.size.cols
	second := node.next or {
		assert false
		return
	}
	node.data.dirty = true

	new_node := s.compact(node)!.node or {
		assert false
		return
	}
	assert page_backing_size(new_node.data.capacity) < oversized_size
	assert new_node.data.size.rows == original_rows
	assert new_node.data.size.cols == original_cols
	assert new_node.data.dirty
	current_first := s.pages.first or {
		assert false
		return
	}
	assert voidptr(new_node) == voidptr(current_first)
	assert new_node.prev == none
	assert voidptr(new_node.next or {
		assert false
		return
	}) == voidptr(second)
	assert voidptr(second.prev or {
		assert false
		return
	}) == voidptr(new_node)
	assert voidptr(tracked.node) == voidptr(new_node)
	assert tracked.x == 5
	assert tracked.y == 10
	for y in 0 .. int(new_node.data.size.rows) {
		for x in 0 .. int(s.cols) {
			assert new_node.data.rows[y].cells[x].codepoint == u32(x + y * int(s.cols))
		}
	}
}

fn test_page_list_compact_insufficient_savings_returns_none() ! {
	mut s := PageList.init(80, 24, uint(0))!
	defer { s.deinit() }

	mut node := s.pages.first or {
		assert false
		return
	}
	node = s.increase_capacity(node, .grapheme_bytes) or { panic(err) }
	old_size := page_backing_size(node.data.capacity)

	if old_size <= standard_page_size() {
		assert s.compact(node)!.node == none
	} else if compacted := s.compact(node)!.node {
		assert page_backing_size(compacted.data.capacity) < old_size
	}
}

fn test_page_chunk_rows_full_page_and_overlap() ! {
	mut s := PageList.init(3, 3, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	mut marked_row := &first.data.rows[1]
	marked_row.cells[0].codepoint = u32(`x`)

	full := PageChunk{ node: first, start: 0, end: 3 }
	middle := PageChunk{ node: first, start: 1, end: 2 }
	tail := PageChunk{ node: first, start: 2, end: 3 }
	assert full.full_page()
	assert !middle.full_page()
	assert middle.rows().len == 1
	assert middle.rows()[0].cells[0].codepoint == u32(`x`)
	assert full.overlaps(middle)
	assert !middle.overlaps(tail)

	mut other := &PageNode{ data: Page.init(first.data.capacity)! }
	defer { other.data.deinit() }
	assert !full.overlaps(PageChunk{ node: other, start: 0, end: 1 })
}

fn test_reflow_cursor_count_trailing_empty_cells() ! {
	mut s := PageList.init(5, 1, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	mut cursor := ReflowCursor.init(first)
	assert cursor.count_trailing_empty_cells() == 5

	mut row := &first.data.rows[0]
	row.cells[2].codepoint = u32(`x`)
	assert cursor.count_trailing_empty_cells() == 2
	row.header.wrap = true
	assert cursor.count_trailing_empty_cells() == 0
	row.header.wrap = false
	row.cells[2] = CellData{}
	row.header.semantic_prompt = .prompt
	assert cursor.count_trailing_empty_cells() == 4
}

fn test_page_list_tracked_pin_accessors_and_diagram() ! {
	mut s := PageList.init(3, 2, uint(0))!
	defer { s.deinit() }

	// The viewport pin is permanently tracked.
	assert s.count_tracked_pins() == 1
	pin := s.pin(Point.new(.screen, Coordinate{ x: 2, y: 1 })) or {
		assert false
		return
	}
	tracked := s.track_pin(pin)!
	assert s.count_tracked_pins() == 2
	view := s.tracked_pins()
	assert view.len == 2
	assert voidptr(view[1]) == voidptr(tracked)

	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.rows[0].cells[0].codepoint = u32(`A`)
	diagram := s.diagram() or {
		assert false, err.msg()
		return
	}
	assert diagram.contains('ACTIVE')
	assert diagram.contains('= PAGE 0')
	assert diagram.contains('A00')
	assert diagram.contains('= PIN')
}

fn test_page_pin_row_cell_grapheme_and_style_accessors() ! {
	mut s := PageList.init(4, 3, uint(0))!
	defer { s.deinit() }

	mut pin := s.pin(Point.new(.screen, Coordinate{ x: 1, y: 1 })) or {
		assert false
		return
	}
	mut page := &pin.node.data
	style := CellStyle{ flags: StyleFlags.init(true, false, false, false, false, false, false, false, .none) }
	style_id := page.styles.add(style) or {
		assert false, err.msg()
		return
	}
	page.rows[int(pin.y)].cells[int(pin.x)] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`a`)
		style_id:    style_id
	}
	page.rows[int(pin.y)].header.styled = true
	page.set_graphemes(uint(pin.y), uint(pin.x), [u32(0x0301)]) or { panic(err) }

	rac := pin.row_and_cell()
	assert voidptr(rac.row) == voidptr(pin.row_data())
	assert voidptr(rac.cell) == voidptr(pin.cell_data())
	assert pin.cells(.all).len == 4
	assert pin.cells(.left).len == 2
	assert pin.cells(.right).len == 3
	assert pin.grapheme(rac.cell) or { []u32{} } == [u32(0x0301)]
	foreign := CellData{
		content_tag: .codepoint_grapheme
		codepoint:   u32(`z`)
	}
	assert pin.grapheme(&foreign) == none
	assert pin.style(rac.cell).eql(&style)
	assert pin.style(&CellData{}).default()

	page_cell := s.get_cell(Point.new(.screen, Coordinate{ x: pin.x, y: pin.y })) or {
		assert false
		return
	}
	assert page_cell.style().eql(&style)
	assert !page_cell.is_dirty()
	pin.mark_dirty()
	assert page_cell.is_dirty()
	screen_point := page_cell.screen_point()
	assert screen_point is PointScreen
	assert screen_point.coord() == Coordinate{ x: 1, y: 1 }
}

fn test_page_pin_left_right_wrap() ! {
	mut s := PageList.init(4, 4, uint(0))!
	defer { s.deinit() }

	pin := s.pin(Point.new(.screen, Coordinate{ x: 1, y: 2 })) or {
		assert false
		return
	}
	left := pin.left_wrap(3) or {
		assert false
		return
	}
	assert left.y == 1
	assert left.x == 2
	right := pin.right_wrap(5) or {
		assert false
		return
	}
	assert right.y == 3
	assert right.x == 2
	assert pin.left_wrap(10) == none
	assert pin.right_wrap(7) == none
}

fn test_page_list_pause_integrity_checks_is_nested() ! {
	if !buildcfg.slow_runtime_safety { return }
	mut s := PageList.init(3, 2, uint(0))!
	defer { s.deinit() }
	original_total := s.total_rows
	s.total_rows += 1
	assert (s.verify_integrity() or { panic('missing integrity violation') }) == .total_rows_mismatch
	s.pause_integrity_checks(true)
	s.pause_integrity_checks(true)
	assert s.verify_integrity() == none
	s.pause_integrity_checks(false)
	assert s.verify_integrity() == none
	s.pause_integrity_checks(false)
	assert (s.verify_integrity() or { panic('missing integrity violation') }) == .total_rows_mismatch
	s.total_rows = original_total
}

fn test_page_list_init_rows_across_two_pages() ! {
	// Use enough rows to require two pages
	cap := initial_capacity(80)
	rows := u16(cap.rows * 2 + 10)
	mut s := PageList.init(80, rows, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.total_rows == uint(rows)
	assert s.total_pages() >= 2
}

// The pinned Zig reference values below were emitted on arm64 macOS, where
// `std.heap.page_size_min` is 16 KiB. Elsewhere it is 4 KiB, so the page's
// total size (and everything derived from it) is the same end offset aligned
// to 4 KiB instead.
fn page_list_page_size_min_reference(darwin_arm64 uint, other uint) uint {
	$if macos && arm64 {
		return darwin_arm64
	} $else {
		return other
	}
}

fn test_page_list_uses_pinned_standard_page_byte_accounting() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }

	std_size := page_list_page_size_min_reference(589824, 585728)
	assert initial_capacity(80).rows == u16(page_list_page_size_min_reference(582, 576))
	assert standard_page_size() == std_size
	assert s.page_size == std_size
	assert s.min_max_size == 2 * std_size
}

fn test_page_list_init_more_than_max_cols() ! {
	// Test large column count triggers capacity adjustment
	mut s := PageList.init(500, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.cols == 500
	assert s.rows == 24
	assert s.total_rows == 24
}

fn test_page_list_reflow_grows_style_capacity_without_losing_styles() ! {
	mut list := PageList.init(60, 2, uint(0x7FFFFFFFFFFFFFFF))!
	defer { list.deinit() }
	first := list.pages.first or {
		assert false, 'missing first page'
		return
	}
	list.split(Pin{ node: first, y: 1 }) or {
		assert false, 'failed to split source pages'
		return
	}
	second := first.next or {
		assert false, 'missing second page'
		return
	}

	for page_index, node in [first, second] {
		mut page := &node.data
		page.rows[0].header.styled = true
		for x in 0 .. 60 {
			style := CellStyle{
				fg_color: StyleColorRgb{
					rgb: RGB{
						r: u8(x)
						g: u8(page_index + 1)
					}
				}
			}
			id := page.styles.add(style) or {
				assert false, 'failed to populate source style ${page_index}:${x}'
				return
			}
			page.rows[0].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(`a`) + u32(page_index)
				style_id:    id
			}
		}
	}

	list.resize(PageResizeOpts{
		cols:   120
		reflow: true
	}) or { panic(err) }

	dst_node := list.pages.first or {
		assert false, 'missing reflow destination page'
		return
	}
	dst := &dst_node.data
	assert dst.capacity.styles > std_capacity.styles
	assert dst.size.rows >= 2
	for y in 0 .. 2 {
		assert dst.rows[y].header.styled
		for x in 0 .. 60 {
			cell := dst.rows[y].cells[x]
			assert cell.style_id != default_style_id
			style := dst.styles.get(cell.style_id)
			assert style.fg_color is StyleColorRgb
			rgb := (style.fg_color as StyleColorRgb).rgb
			assert rgb.r == u8(x)
			assert rgb.g == u8(y + 1)
		}
	}
	if integrity_error := dst.verify_integrity() {
		assert false, 'reflow destination failed integrity: ${integrity_error}'
	}
}

fn test_page_list_erase_row_propagates_style_capacity_error_across_pages() ! {
	mut list := PageList.init(60, 3, uint(0x7FFFFFFFFFFFFFFF))!
	defer { list.deinit() }
	first := list.pages.first or {
		assert false, 'missing first page'
		return
	}
	list.split(Pin{ node: first, y: 2 }) or {
		assert false, 'failed to split source pages'
		return
	}
	second := first.next or {
		assert false, 'missing second page'
		return
	}

	for page_index, row_ref in [
		Pin{ node: first, y: 1 },
		Pin{ node: second, y: 0 },
	] {
		mut page := &row_ref.node.data
		page.rows[int(row_ref.y)].header.styled = true
		for x in 0 .. 60 {
			style := CellStyle{
				fg_color: StyleColorRgb{
					rgb: RGB{
						r: u8(x)
						g: u8(page_index + 1)
					}
				}
			}
			id := page.styles.add(style) or {
				assert false, 'failed to populate source style ${page_index}:${x}'
				return
			}
			page.rows[int(row_ref.y)].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(`a`) + u32(page_index)
				style_id:    id
			}
		}
	}

	mut error_message := ''
	list.erase_row(Point.new(.active, Coordinate{})) or { error_message = err.msg() }
	assert error_message == PageCloneError.style_set_out_of_memory.str()

	dst_node := list.pages.first or {
		assert false, 'missing erase destination page'
		return
	}
	assert voidptr(dst_node) == voidptr(first)
	dst := &dst_node.data
	assert dst.capacity.styles == std_capacity.styles
	if integrity_error := dst.verify_integrity() {
		assert false, 'erase destination failed integrity: ${integrity_error}'
	}
}

// ============================================================
// pointFromPin tests
// ============================================================

fn test_page_list_point_from_pin_active_no_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// With no history, active pin at (0,0) should be at screen (0,0)
	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}
	pt := s.point_from_pin(.active, p) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert pt.coord().x == 0
	assert pt.coord().y == 0

	// Active pin at (5, 10)
	p2 := s.pin(Point.new(.active, Coordinate{ x: 5, y: 10 })) or {
		assert false, 'get_pin failed'
		return
	}
	pt2 := s.point_from_pin(.active, p2) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert pt2.coord().x == 5
	assert pt2.coord().y == 10
}

fn test_page_list_point_from_pin_active_with_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow to create scrollback
	s.grow_rows(50)!

	// Active pin at (0,0) should still be (0,0) in active coords
	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}
	pt := s.point_from_pin(.active, p) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert pt.coord().x == 0
	assert pt.coord().y == 0

	// Screen pin at active area should have y offset by history
	pt_screen := s.point_from_pin(.screen, p) or {
		assert false, 'point_from_pin screen failed'
		return
	}
	assert pt_screen.coord().y > 0 // Should be offset by scrollback
}

fn test_page_list_point_from_pin_traverse_pages() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow enough to span multiple pages
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 3)!

	// Get a pin in the active area and convert
	p := s.pin(Point.new(.active, Coordinate{ x: 5, y: 10 })) or {
		assert false, 'get_pin failed'
		return
	}
	pt := s.point_from_pin(.active, p) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert pt.coord().x == 5
	assert pt.coord().y == 10
}

// ============================================================
// Grow tests
// ============================================================

fn test_page_list_grow_fit_in_capacity() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	initial_pages := s.total_pages()
	initial_rows := s.total_rows

	// Grow by one row - should fit in existing page
	_ = s.grow()!
	assert s.total_rows == initial_rows + 1
	assert s.total_pages() == initial_pages
}

fn test_page_list_grow_allocate() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Fill the first page
	cap := initial_capacity(80)
	remaining := uint(cap.rows) - s.total_rows
	s.grow_rows(remaining)!

	initial_pages := s.total_pages()

	// Now grow one more should allocate new page
	_ = s.grow()!
	assert s.total_pages() == initial_pages + 1
}

fn test_page_list_active_after_grow() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Write to first active row
	set_active_cell(mut s, 0, 0, u32(0x41))

	// Grow
	s.grow_rows(50)!

	// Row 0 in active should now be blank (original row scrolled to history)
	cell := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert cell.cell.codepoint == 0 || cell.cell.content_tag == .bg_color_palette
}

fn test_page_list_grow_prune_scrollback() ! {
	// Use limited max_size to force pruning
	cap := initial_capacity(80)
	page_bytes := uint(cap.cols) * uint(cap.rows) * 16
	max_sz := page_bytes * 2 // Only room for ~2 pages

	mut s := PageList.init(80, 24, max_sz)!
	defer { s.deinit() }

	// Grow until we've exceeded our capacity
	for _ in 0 .. int(cap.rows) * 5 {
		_ = s.grow()!
	}

	// Total rows should still be valid
	assert s.total_rows >= uint(s.rows)
	s.assert_integrity()
}

fn test_page_list_grow_prune_with_viewport_pin() ! {
	cap := initial_capacity(80)
	page_bytes := uint(cap.cols) * uint(cap.rows) * 16
	max_sz := page_bytes * 3

	mut s := PageList.init(80, 24, max_sz)!
	defer { s.deinit() }

	// Grow to create some scrollback
	s.grow_rows(50)!

	// Scroll to top to set viewport pin
	s.scroll(PageScrollTop{})
	assert s.viewport == .top

	// Grow a lot more to force pruning
	for _ in 0 .. int(cap.rows) * 5 {
		_ = s.grow()!
	}

	// Should still be valid
	assert s.total_rows >= uint(s.rows)
	s.assert_integrity()
}

fn test_page_list_grow_prune_scrollback_with_viewport_pin_not_in_pruned_page() ! {
	mut s := PageList.init(80, 24, standard_page_size())!
	defer { s.deinit() }

	page1_node := s.pages.last or {
		assert false, 'first page missing'
		return
	}
	page1_rows := page1_node.data.capacity.rows
	page1_remaining := int(page1_rows - page1_node.data.size.rows)
	for _ in 0 .. page1_remaining {
		assert s.grow()!.node == none
	}
	assert page1_node.data.size.rows == page1_rows

	page2_node := s.grow()!.node or {
		assert false, 'second page was not allocated'
		return
	}
	page2_remaining := int(page2_node.data.capacity.rows - page2_node.data.size.rows)
	for _ in 0 .. page2_remaining {
		assert s.grow()!.node == none
	}
	old_page_size := s.page_size

	pin_y := u16(page1_rows + 5)
	viewport_pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: pin_y })) or {
		assert false, 'viewport pin missing'
		return
	}
	s.scroll(PageScrollPin{ pin: viewport_pin })
	assert s.viewport == .pin
	assert voidptr(s.viewport_pin.node) == voidptr(page2_node)
	assert s.scrollbar().offset == uint(pin_y)

	new_node := s.grow()!.node or {
		assert false, 'pruned page was not reused'
		return
	}
	assert voidptr(s.pages.last or { return }) == voidptr(new_node)
	assert s.page_size == old_page_size
	assert voidptr(s.pages.first or { return }) == voidptr(page2_node)
	assert voidptr(s.viewport_pin.node) == voidptr(page2_node)
	assert s.scrollbar().offset == uint(pin_y - page1_rows)
}

fn test_page_list_grow_reuses_non_standard_page_without_leak() ! {
	mut s := PageList.init(80, 24, 3 * standard_page_size())!
	defer { s.deinit() }

	for {
		first := s.pages.first or { return }
		if page_backing_size(first.data.capacity) > standard_page_size() {
			break
		}
		s.increase_capacity(first, .grapheme_bytes) or { panic(err) }
	}
	first_page := s.pages.first or {
		assert false, 'first page missing'
		return
	}
	assert page_backing_size(first_page.data.capacity) > standard_page_size()
	first_page_mem := first_page.data.memory.data

	for first_page.data.size.rows < first_page.data.capacity.rows {
		_ = s.grow()!
	}
	s.grow()!.node or {
		assert false, 'second page was not allocated'
		return
	}
	for s.page_size + standard_page_size() <= s.max_size()
		|| (s.pages.last or { return }).data.size.rows < (s.pages.last or { return }).data.capacity.rows {
		_ = s.grow()!
	}
	assert voidptr(s.pages.first or { return }) == voidptr(first_page)
	assert s.total_rows >= uint(s.rows)
	last := s.pages.last or { return }
	assert last.data.size.rows == last.data.capacity.rows

	tracked := s.track_pin(Pin{ node: first_page })!
	_ = s.grow()!
	assert voidptr(s.pages.first or { return }) != voidptr(first_page)
	// The source compares backing memory; pooled node slots may be reused.
	assert (s.pages.last or { return }).data.memory.data != first_page_mem
	assert voidptr(tracked.node) == voidptr(s.pages.first or { return })
	assert tracked.x == 0
	assert tracked.y == 0
	assert tracked.garbage
	s.untrack_pin(tracked)
}

fn test_page_list_grow_non_standard_page_prune_protection() ! {
	mut s := PageList.init(80, 600, standard_page_size())!
	defer { s.deinit() }

	for {
		first := s.pages.first or { return }
		if page_backing_size(first.data.capacity) > standard_page_size() {
			break
		}
		s.increase_capacity(first, .grapheme_bytes) or { panic(err) }
	}
	first_page := s.pages.first or { return }
	first_page_rows := first_page.data.capacity.rows
	for first_page.data.size.rows < first_page_rows {
		_ = s.grow()!
	}
	for voidptr(s.pages.first or { return }) == voidptr(s.pages.last or { return }) {
		_ = s.grow()!
	}
	last := s.pages.last or { return }
	second_rows := last.data.capacity.rows
	for last.data.size.rows < second_rows {
		_ = s.grow()!
	}

	would_remain := s.total_rows - uint(first_page_rows) + 1
	assert would_remain < uint(s.rows)
	assert s.page_size + standard_page_size() > s.max_size()
	_ = s.grow()!
	assert s.total_rows >= uint(s.rows)
}

fn test_page_list_scrollbar_with_max_size_0_after_grow() ! {
	mut s := PageList.init(80, 24, uint(0))!
	defer { s.deinit() }

	s.grow_rows(10)!

	sb := s.scrollbar()
	assert sb.total == uint(s.rows)
	assert sb.len == uint(s.rows)
}

// ============================================================
// Scroll tests
// ============================================================

fn test_page_list_scroll_with_max_size_0_no_history() ! {
	mut s := PageList.init(80, 24, uint(0))!
	defer { s.deinit() }

	s.scroll(PageScrollDeltaRow{ delta: -1 })
	assert s.viewport == .active

	s.scroll(PageScrollTop{})
	assert s.viewport == .active
}

fn test_page_list_scroll_top() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	s.scroll(PageScrollTop{})
	assert s.viewport == .top

	sb := s.scrollbar()
	assert sb.offset == 0

	// Back to active
	s.scroll(PageScrollActive{})
	assert s.viewport == .active
}

fn test_page_list_scroll_delta_row_back() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	// Scroll back
	s.scroll(PageScrollDeltaRow{ delta: -10 })

	// Should be in pin mode (not active)
	assert s.viewport != .active

	sb := s.scrollbar()
	expected_offset := s.total_rows - uint(s.rows) - 10
	assert sb.offset == expected_offset
}

fn test_page_list_scroll_delta_row_back_overflow() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create some scrollback
	s.grow_rows(50)!

	// Scroll back more than available
	s.scroll(PageScrollDeltaRow{ delta: -int(s.total_rows) })

	// Should be at top
	assert s.viewport == .top

	sb := s.scrollbar()
	assert sb.offset == 0
}

fn test_page_list_scroll_delta_row_forward() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback and scroll to top
	s.grow_rows(100)!
	s.scroll(PageScrollTop{})

	// Scroll forward
	s.scroll(PageScrollDeltaRow{ delta: 10 })

	sb := s.scrollbar()
	assert sb.offset == 10
}

fn test_page_list_scroll_delta_row_forward_into_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback and scroll to top
	s.grow_rows(100)!
	s.scroll(PageScrollTop{})

	// Scroll forward more than scrollback
	s.scroll(PageScrollDeltaRow{ delta: int(s.total_rows) })

	// Should be back at active
	assert s.viewport == .active
}

fn test_page_list_scroll_to_pin() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	// Get a pin in scrollback
	p := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 5 })) or {
		assert false, 'get_pin failed'
		return
	}

	s.scroll(PageScrollPin{ pin: p })
	assert s.viewport == .pin
}

fn test_page_list_scroll_to_pin_in_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	// Get a pin in active area
	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 10 })) or {
		assert false, 'get_pin failed'
		return
	}

	// Scrolling to active pin should keep viewport active
	s.scroll(PageScrollPin{ pin: p })
	assert s.viewport == .active
}

fn test_page_list_scroll_to_pin_at_top() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	// Get pin at very top
	p := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}

	s.scroll(PageScrollPin{ pin: p })
	assert s.viewport == .top
}

fn test_page_list_scroll_to_row_0() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	s.scroll(PageScrollRow{ n: 0 })
	assert s.viewport == .top

	sb := s.scrollbar()
	assert sb.offset == 0
}

fn test_page_list_scroll_to_row_in_scrollback() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	s.scroll(PageScrollRow{ n: 10 })
	assert s.viewport == .pin

	sb := s.scrollbar()
	assert sb.offset == 10
}

fn test_page_list_scroll_to_row_in_middle() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	mid := s.total_rows / 2
	s.scroll(PageScrollRow{ n: mid })
	assert s.viewport == .pin

	sb := s.scrollbar()
	assert sb.offset == mid
}

fn test_page_list_scroll_to_row_at_active_boundary() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	boundary := s.total_rows - uint(s.rows)
	s.scroll(PageScrollRow{ n: boundary })

	// Should be at active since this is the active boundary
	assert s.viewport == .active
}

fn test_page_list_scroll_to_row_beyond_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	s.scroll(PageScrollRow{ n: s.total_rows })

	// Past active should clamp to active
	assert s.viewport == .active
}

fn test_page_list_scroll_to_row_without_scrollback() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// No scrollback, any scroll should stay active
	s.scroll(PageScrollRow{ n: 0 })
	assert s.viewport == .top

	s.scroll(PageScrollRow{ n: 10 })
	assert s.viewport == .active
}

fn test_page_list_scroll_to_row_then_delta() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create scrollback
	s.grow_rows(100)!

	// Scroll to row 10
	s.scroll(PageScrollRow{ n: 10 })
	assert s.viewport == .pin

	sb1 := s.scrollbar()
	assert sb1.offset == 10

	// Now delta forward by 5
	s.scroll(PageScrollDeltaRow{ delta: 5 })

	sb2 := s.scrollbar()
	assert sb2.offset == 15
}

fn test_page_list_scroll_clear() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Write to a few rows
	for y in u16(0) .. 2 {
		set_active_cell(mut s, 0, y, u32(0x41))
	}

	initial_rows := s.total_rows

	// Scroll clear pushes active content to scrollback
	s.scroll_clear() or { panic(err) }

	assert s.total_rows == initial_rows + 2
	assert (s.get_cell(Point.new(.viewport, Coordinate{})) or {
		assert false, 'viewport cell missing'
		return
	}).screen_point() == Point.new(.screen, Coordinate{ y: 2 })
}

fn test_page_list_scroll_clear_empty_active_area() ! {
	mut s := PageList.init(5, 5, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	initial_rows := s.total_rows

	s.scroll_clear() or { panic(err) }

	assert s.total_rows == initial_rows
}

fn test_page_list_scroll_clear_counts_background_only_cell() ! {
	mut s := PageList.init(5, 5, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	p := s.pin(Point.new(.active, Coordinate{ y: 1 })) or {
		assert false, 'active pin missing'
		return
	}
	mut row := &p.node.data.rows[int(p.y)]
	row.cells[0] = CellData{
		content_tag: .bg_color_palette
	}
	initial_rows := s.total_rows

	s.scroll_clear() or { panic(err) }

	assert s.total_rows == initial_rows + 2
}

fn test_page_list_scroll_clear_includes_internal_blank_rows() ! {
	mut s := PageList.init(5, 5, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	set_active_cell(mut s, 0, 0, u32(`A`))
	set_active_cell(mut s, 0, 4, u32(`B`))
	initial_rows := s.total_rows

	s.scroll_clear() or { panic(err) }

	assert s.total_rows == initial_rows + 5
}

fn test_page_list_scroll_clear_counts_trailing_rows_across_pages() ! {
	mut s := PageList.init(80, 600, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	assert s.total_pages() > 1
	set_active_cell(mut s, 0, 580, u32(`A`))
	initial_rows := s.total_rows

	s.scroll_clear() or { panic(err) }

	assert s.total_rows == initial_rows + 581
}

// ============================================================
// Total pages / rows tests
// ============================================================

fn test_page_list_total_pages() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	initial := s.total_pages()
	assert initial >= 1

	// Grow enough to create new pages
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 3)!

	assert s.total_pages() > initial
}

fn test_page_list_count_total_rows() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.count_total_rows() == s.total_rows

	s.grow_rows(100)!

	assert s.count_total_rows() == s.total_rows
}

// ============================================================
// Get top-left / bottom-right tests
// ============================================================

fn test_page_list_get_top_left_screen() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	tl := s.get_top_left(.screen)
	assert tl.y == 0
	assert tl.x == 0
}

fn test_page_list_get_top_left_active_no_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	tl_screen := s.get_top_left(.screen)
	tl_active := s.get_top_left(.active)

	// With no history, screen and active should be the same
	assert tl_screen.eql(tl_active)
}

fn test_page_list_get_top_left_active_with_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(50)!

	tl_screen := s.get_top_left(.screen)
	tl_active := s.get_top_left(.active)

	// Active should be after screen (history is before active)
	assert tl_screen.before(tl_active)
}

fn test_page_list_get_top_left_pinned_viewport_preserves_pin() ! {
	mut s := PageList.init(10, 3, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	s.grow_rows(3)!

	p := s.pin(Point.new(.screen, Coordinate{ x: 4, y: 1 })) or {
		assert false, 'viewport pin missing'
		return
	}
	s.scroll(PageScrollPin{ pin: p })
	assert s.viewport == .pin
	assert s.get_top_left(.viewport).eql(p)
	assert s.viewport_pin_row_offset == none
	assert s.scrollbar().offset == 1
	assert s.viewport_pin_row_offset or { uint(max_usize) } == 1
}

fn test_page_list_get_bottom_right() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	br := s.get_bottom_right(.active) or {
		assert false, 'get_bottom_right failed'
		return
	}
	assert br.x == s.cols - 1
}

fn test_page_list_get_bottom_right_uses_owning_page_width() ! {
	mut s := PageList.init(10, 3, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	mut last := s.pages.last or {
		assert false, 'last page missing'
		return
	}
	last.data.size.cols = 7
	br := s.get_bottom_right(.active) or {
		assert false, 'get_bottom_right failed'
		return
	}
	assert br.x == 6
}

// ============================================================
// Track pin tests
// ============================================================

fn test_page_list_track_pin() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 5, y: 10 })) or {
		assert false, 'get_pin failed'
		return
	}

	tp := s.track_pin(p)!
	assert tp.x == 5
	assert tp.y == p.y

	s.untrack_pin(tp)
}

fn test_page_list_pin_is_valid() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}

	assert s.pin_is_valid(p)

	// Page widths can temporarily differ during an incomplete reflow. Pin
	// validity is bounded by the owning page rather than the list target width.
	mut node := p.node
	node.data.size.cols = 1
	assert !s.pin_is_valid(Pin{
		node: node
		y:    0
		x:    1
	})
	node.data.size.cols = 80
}

fn test_page_list_pin_is_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create history
	s.grow_rows(50)!

	// Active pin
	p_active := s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}
	assert s.pin_is_active(p_active)

	// Screen pin at row 0 should be history (not active)
	p_screen := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}
	assert !s.pin_is_active(p_screen)
}

// ============================================================
// Erase tests
// ============================================================

fn test_page_list_erase() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.total_pages() >= 1

	// Grow to 5+ pages
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!

	assert s.total_pages() >= 5
	assert s.total_rows > uint(s.rows)

	// Erase entire history
	s.erase_rows(Point.new(.history, Coordinate{}), none)
	assert s.total_rows == uint(s.rows)
	// Should be back to 1 page (or close)
	assert s.total_pages() <= 2
}

fn test_page_list_erase_active_regrows_automatically() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.total_rows == uint(s.rows)

	// Erase some active rows
	s.erase_rows(Point.new(.active, Coordinate{}), none)
	assert s.total_rows == uint(s.rows)
}

fn test_page_list_erase_resets_viewport_to_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow and scroll to top
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!

	s.scroll(PageScrollTop{})
	assert s.viewport == .top

	// Erase history
	s.erase_rows(Point.new(.history, Coordinate{}), none)

	// Viewport should be back to active since there's no history
	assert s.viewport == .active || s.viewport == .top
}

fn test_page_list_erase_one_row_active() ! {
	mut s := PageList.init(10, 1, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.total_pages() >= 1

	// Write a letter
	set_active_cell(mut s, 0, 0, u32(0x41))

	// Verify it's there
	cell := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert cell.cell.codepoint == u32(0x41)

	// Erase active
	s.erase_rows(Point.new(.active, Coordinate{}), none)
	assert s.total_rows == uint(s.rows)

	// Row should be empty
	cell2 := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed after erase'
		return
	}
	assert cell2.cell.codepoint == 0 || cell2.cell.content_tag == .bg_color_palette
}

fn test_page_list_point_pin_and_partial_active_erase() ! {
	mut s := PageList.init(8, 6, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	for y in 0 .. 6 {
		set_active_cell(mut s, 0, u16(y), u32(`A`) + u32(y))
	}
	tracked_survivor := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 2, y: 4 })) or {
		panic('missing survivor pin')
	})!
	defer { s.untrack_pin(tracked_survivor) }
	tracked_erased := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 3, y: 2 })) or {
		panic('missing erased pin')
	})!
	defer { s.untrack_pin(tracked_erased) }

	s.erase_rows(Point.new(.active, Coordinate{}), Point.new(.active, Coordinate{ y: 3 }))
	assert s.total_rows == uint(s.rows)
	first := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or { panic('missing first active cell') }
	second := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 1 })) or { panic('missing second active cell') }
	assert first.cell.codepoint == u32(`E`)
	assert second.cell.codepoint == u32(`F`)
	assert tracked_survivor.y == 0
	assert tracked_survivor.x == 2
	assert tracked_erased.y == 0
	assert tracked_erased.x == 0
}

fn test_page_list_erase_history_preserves_managed_survivor() ! {
	mut s := PageList.init(6, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	s.grow_rows(2)!
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	style_id := page.styles.add(CellStyle{
		flags: StyleFlags.init(true, false, false, false, false, false, false, false, .none)
	}) or {
		assert false, 'style add failed'
		return
	}
	page.rows[2].cells[3] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`S`)
		style_id:    style_id
	}
	page.rows[2].header.styled = true
	page.set_graphemes(2, 3, [u32(0x0302)]) or { panic(err) }
	hyperlink_id := page.insert_hyperlink(Hyperlink{
		id:  HyperlinkExplicitId{
			value: 'survivor'
		}
		uri: 'https://example.com/survivor'
	}) or { panic(err) }
	page.set_hyperlink(2, 3, hyperlink_id) or { panic(err) }

	// The first two rows are history. Erasing them compacts old row 2 to row 0.
	s.erase_rows(Point.new(.history, Coordinate{}), none)

	assert s.total_rows == 4
	cell := page.rows[0].cells[3]
	assert cell.codepoint == u32(`S`)
	assert (page.lookup_grapheme_at(0, 3) or { []u32{} }) == [u32(0x0302)]
	assert page.styles.get(cell.style_id).flags.bold()
	assert page.styles.ref_count(cell.style_id) == 1
	moved_link_id := page.lookup_hyperlink_at(0, 3) or {
		assert false, 'survivor hyperlink mapping missing'
		return
	}
	assert page.hyperlink_set.get(moved_link_id).uri == 'https://example.com/survivor'
	assert page.hyperlink_set.ref_count(moved_link_id) == 1
	assert page.lookup_hyperlink_at(2, 3) == none
	page.assert_integrity()
}

fn test_page_list_erase_row() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Write codepoints to identify rows
	for y in u16(0) .. s.rows {
		set_active_cell(mut s, 0, y, u32(y) + u32(0x41))
	}

	// Erase row 0
	s.erase_row(Point.new(.active, Coordinate{})) or { panic(err) }

	// After erase, row 0 should have what was row 1 ('B')
	cell := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert cell.cell.codepoint == u32(0x42)
}

fn test_page_list_erase_row_preserves_rotated_row_metadata() ! {
	mut s := PageList.init(4, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	first := s.pages.first or { panic('no first page') }
	mut page := &first.data
	page.rows[0].header.wrap = true
	page.rows[0].header.wrap_continuation = true
	page.rows[0].header.semantic_prompt = .prompt
	page.rows[0].header.kitty_virtual_placeholder = true
	page.rows[0].cells[0] = CellData.init(kitty_unicode_placeholder)
	page.rows[0].header.dirty = false

	s.erase_row(Point.new(.active, Coordinate{})) or { panic(err) }

	last := page.rows[int(page.size.rows) - 1]
	assert last.cells[0].is_zero()
	assert last.header.wrap
	assert last.header.wrap_continuation
	assert last.header.semantic_prompt == .prompt
	assert last.header.kitty_virtual_placeholder
	assert !last.header.dirty
}

fn test_page_list_erase_row_with_tracked_pin() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Track a pin at row 5
	p := s.pin(Point.new(.active, Coordinate{ x: 2, y: 5 })) or {
		assert false, 'get_pin failed'
		return
	}
	tp := s.track_pin(p)!

	// Erase row 0 (before tracked pin)
	s.erase_row(Point.new(.active, Coordinate{})) or { panic(err) }

	// Tracked pin should shift up by 1
	assert tp.y == p.y - 1

	s.untrack_pin(tp)
}

fn test_page_list_erase_row_preserves_managed_cell_data() ! {
	mut s := PageList.init(8, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	style_id := page.styles.add(CellStyle{
		flags: StyleFlags.init(true, false, false, false, false, false, false, false, .none)
	}) or {
		assert false, 'style add failed'
		return
	}
	page.rows[1].cells[2] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`M`)
		style_id:    style_id
	}
	page.rows[1].header.styled = true
	page.set_graphemes(1, 2, [u32(0x0301)]) or { panic(err) }
	hyperlink_id := page.insert_hyperlink(Hyperlink{
		id:  HyperlinkExplicitId{
			value: 'managed'
		}
		uri: 'https://example.com/managed'
	}) or { panic(err) }
	page.set_hyperlink(1, 2, hyperlink_id) or { panic(err) }

	s.erase_row(Point.new(.active, Coordinate{})) or { panic(err) }

	cell := page.rows[0].cells[2]
	assert cell.codepoint == u32(`M`)
	assert cell.has_grapheme()
	assert (page.lookup_grapheme_at(0, 2) or { []u32{} }) == [u32(0x0301)]
	assert cell.style_id == style_id
	assert page.styles.get(cell.style_id).flags.bold()
	assert page.styles.ref_count(cell.style_id) == 1
	assert cell.has_hyperlink
	moved_link_id := page.lookup_hyperlink_at(0, 2) or {
		assert false, 'moved hyperlink mapping missing'
		return
	}
	assert moved_link_id == hyperlink_id
	assert page.hyperlink_set.get(moved_link_id).uri == 'https://example.com/managed'
	assert page.hyperlink_set.ref_count(moved_link_id) == 1
	assert page.lookup_hyperlink_at(1, 2) == none
	page.assert_integrity()
}

fn test_page_list_erase_row_moves_managed_cell_and_pin_across_page_boundary() ! {
	mut s := PageList.init(4, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	s.split(Pin{ node: first, y: 2, x: 0 }) or {
		assert false, 'split failed'
		return
	}
	second := first.next or {
		assert false, 'no second page'
		return
	}
	mut second_page := &second.data
	second_page.rows[0].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`B`)
	}
	hyperlink_id := second_page.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{
			offset: 7
		}
		uri: 'https://example.com/boundary'
	}) or { panic(err) }
	second_page.set_hyperlink(0, 1, hyperlink_id) or { panic(err) }
	tracked := s.track_pin(Pin{ node: second, y: 0, x: 1 })!

	s.erase_row(Point.new(.active, Coordinate{ y: 1 })) or { panic(err) }

	assert voidptr(tracked.node) == voidptr(first)
	assert tracked.y == 1
	assert tracked.x == 1
	mut first_page := &first.data
	assert first_page.rows[1].cells[1].codepoint == u32(`B`)
	moved_link_id := first_page.lookup_hyperlink_at(1, 1) or {
		assert false, 'cross-page hyperlink mapping missing'
		return
	}
	assert first_page.hyperlink_set.get(moved_link_id).uri == 'https://example.com/boundary'
	assert first_page.hyperlink_set.ref_count(moved_link_id) == 1
	assert second_page.lookup_hyperlink_at(0, 1) == none
	first_page.assert_integrity()
	second_page.assert_integrity()
	s.untrack_pin(tracked)
}

// ============================================================
// Split tests
// ============================================================

fn test_page_list_split_at_middle_row() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	// Write to identify rows
	for y in u16(0) .. 10 {
		set_active_cell(mut s, 0, y, u32(y) + u32(0x41))
	}

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	split_pin := Pin{
		node: first
		y:    5
		x:    0
	}
	s.split(split_pin) or {
		assert false, 'split failed: ${err}'
		return
	}

	// Should now have 2 pages
	assert s.total_pages() == 2

	// First page should have rows 0-4
	assert first.data.size.rows == 5

	// Second page should have rows 5-9
	second := first.next or {
		assert false, 'no second page'
		return
	}
	assert second.data.size.rows == 5
}

fn test_page_list_split_at_row_0_noop() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	split_pin := Pin{
		node: first
		y:    0
		x:    0
	}
	s.split(split_pin) or {
		assert false, 'split failed: ${err}'
		return
	}

	// Should still have 1 page (no-op for y=0)
	assert s.total_pages() == 1
}

fn test_page_list_split_at_last_row() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	split_pin := Pin{
		node: first
		y:    9
		x:    0
	}
	s.split(split_pin) or {
		assert false, 'split failed: ${err}'
		return
	}

	// Should have 2 pages: 9 rows + 1 row
	assert s.total_pages() == 2
	assert first.data.size.rows == 9

	second := first.next or {
		assert false, 'no second page'
		return
	}
	assert second.data.size.rows == 1
}

fn test_page_list_split_moves_tracked_pins() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	// Track a pin at row 7
	p := s.pin(Point.new(.active, Coordinate{ x: 2, y: 7 })) or {
		assert false, 'get_pin failed'
		return
	}
	tp := s.track_pin(p)!

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	split_pin := Pin{
		node: first
		y:    5
		x:    0
	}
	s.split(split_pin) or {
		assert false, 'split failed: ${err}'
		return
	}

	// Pin was at row 7, split at 5, so pin should move to second page row 2
	second := first.next or {
		assert false, 'no second page'
		return
	}
	assert voidptr(tp.node) == voidptr(second)
	assert tp.y == 2 // 7 - 5
	assert tp.x == 2

	s.untrack_pin(tp)
}

fn test_page_list_split_tracked_pin_before_split_unchanged() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	// Track a pin at row 2
	p := s.pin(Point.new(.active, Coordinate{ x: 3, y: 2 })) or {
		assert false, 'get_pin failed'
		return
	}
	tp := s.track_pin(p)!

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	split_pin := Pin{
		node: first
		y:    5
		x:    0
	}
	s.split(split_pin) or {
		assert false, 'split failed: ${err}'
		return
	}

	// Pin should stay in first page
	assert voidptr(tp.node) == voidptr(first)
	assert tp.y == p.y
	assert tp.x == 3

	s.untrack_pin(tp)
}

fn test_page_list_split_tracked_pin_at_split_point() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	// Track a pin at exactly row 5
	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 5 })) or {
		assert false, 'get_pin failed'
		return
	}
	tp := s.track_pin(p)!

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	split_pin := Pin{
		node: first
		y:    5
		x:    0
	}
	s.split(split_pin) or {
		assert false, 'split failed: ${err}'
		return
	}

	// Pin at split point moves to second page row 0
	second := first.next or {
		assert false, 'no second page'
		return
	}
	assert voidptr(tp.node) == voidptr(second)
	assert tp.y == 0

	s.untrack_pin(tp)
}

fn test_page_list_split_preserves_wrap_flags() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Set wrap flags on rows
	page.rows[5].header.wrap = true
	page.rows[6].header.wrap_continuation = true
	page.rows[7].header.wrap = true
	page.rows[7].header.wrap_continuation = true

	split_pin := Pin{
		node: first
		y:    5
		x:    0
	}
	s.split(split_pin) or {
		assert false, 'split failed: ${err}'
		return
	}

	second := first.next or {
		assert false, 'no second page'
		return
	}

	// Row 5 -> second page row 0
	assert second.data.rows[0].header.wrap == true
	assert second.data.rows[0].header.wrap_continuation == false

	// Row 6 -> second page row 1
	assert second.data.rows[1].header.wrap == false
	assert second.data.rows[1].header.wrap_continuation == true

	// Row 7 -> second page row 2
	assert second.data.rows[2].header.wrap == true
	assert second.data.rows[2].header.wrap_continuation == true
}

fn test_page_list_split_middle_page_preserves_order() ! {
	mut s := PageList.init(10, 12, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	// Split to create 2 pages (at row 4)
	split1 := Pin{
		node: first
		y:    4
		x:    0
	}
	s.split(split1) or {
		assert false, 'split1 failed: ${err}'
		return
	}
	assert s.total_pages() == 2

	// Split second page to create 3 pages
	second := first.next or {
		assert false, 'no second page'
		return
	}
	split2 := Pin{
		node: second
		y:    4
		x:    0
	}
	s.split(split2) or {
		assert false, 'split2 failed: ${err}'
		return
	}
	assert s.total_pages() == 3

	// Verify linked list order
	n1 := s.pages.first or {
		assert false
		return
	}
	n2 := n1.next or {
		assert false
		return
	}
	n3 := n2.next or {
		assert false
		return
	}
	assert n3.next == none

	// Verify row counts: 4, 4, 4
	assert n1.data.size.rows == 4
	assert n2.data.size.rows == 4
	assert n3.data.size.rows == 4
}

// ============================================================
// Clone tests
// ============================================================

fn test_page_list_clone() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	mut c := s.clone(PageCloneOpts{ top: Point.new(.screen, Coordinate{}) }) or { panic(err) }
	defer { c.deinit() }

	assert c.total_rows == s.total_rows
	assert c.cols == s.cols
	assert c.rows == s.rows
}

fn test_page_list_clone_with_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(100)!

	mut c := s.clone(PageCloneOpts{ top: Point.new(.screen, Coordinate{}) }) or { panic(err) }
	defer { c.deinit() }

	assert c.total_rows == s.total_rows
}

fn test_page_list_clone_partial_trimmed_right() ! {
	mut s := PageList.init(80, 20, none)!
	defer { s.deinit() }
	s.grow_rows(30)!

	mut c := s.clone(PageCloneOpts{
		top: Point.new(.screen, Coordinate{})
		bot: Point.new(.screen, Coordinate{ y: 39 })
	}) or { panic(err) }
	defer { c.deinit() }
	assert c.count_total_rows() == 40
}

fn test_page_list_clone_partial_trimmed_left() ! {
	mut s := PageList.init(80, 20, none)!
	defer { s.deinit() }
	s.grow_rows(30)!

	mut c := s.clone(PageCloneOpts{
		top: Point.new(.screen, Coordinate{ y: 10 })
	}) or { panic(err) }
	defer { c.deinit() }
	assert c.count_total_rows() == 40
}

fn test_page_list_clone_partial_trimmed_left_reclaims_styles() ! {
	mut s := PageList.init(80, 20, none)!
	defer { s.deinit() }
	s.grow_rows(30)!
	mut first := s.pages.first or {
		assert false
		return
	}
	style_id := first.data.styles.add(CellStyle{
		flags: StyleFlags.init(true, false, false, false, false, false, false, false, .none)
	}) or { panic(err) }
	for y in 0 .. 10 {
		first.data.rows[y].header.styled = true
		first.data.rows[y].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`A`)
			style_id:    style_id
		}
		first.data.styles.use_style(style_id)
	}
	first.data.styles.release(style_id)
	assert first.data.styles.set.count() == 1

	mut c := s.clone(PageCloneOpts{
		top: Point.new(.screen, Coordinate{ y: 10 })
	}) or { panic(err) }
	defer { c.deinit() }
	assert c.count_total_rows() == 40
	cloned_first := c.pages.first or {
		assert false
		return
	}
	assert cloned_first.data.styles.set.count() == 0
}

fn test_page_list_clone_partial_trimmed_both() ! {
	mut s := PageList.init(80, 20, none)!
	defer { s.deinit() }
	s.grow_rows(30)!

	mut c := s.clone(PageCloneOpts{
		top: Point.new(.screen, Coordinate{ y: 10 })
		bot: Point.new(.screen, Coordinate{ y: 35 })
	}) or { panic(err) }
	defer { c.deinit() }
	assert c.count_total_rows() == 26
}

fn test_page_list_clone_ignores_valid_horizontal_coordinates() ! {
	mut s := PageList.init(10, 20, none)!
	defer { s.deinit() }
	s.grow_rows(30)!

	mut c := s.clone(PageCloneOpts{
		top: Point.new(.screen, Coordinate{ x: 9, y: 10 })
		bot: Point.new(.screen, Coordinate{ x: 9, y: 35 })
	}) or { panic(err) }
	defer { c.deinit() }
	assert c.count_total_rows() == 26
}

fn test_page_list_clone_remap_tracked_pin() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }
	tracked := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 6 })) or {
		assert false
		return
	})!

	mut remap := PageTrackedPinsRemap.init()
	defer { remap.deinit() }
	mut c := s.clone(PageCloneOpts{
		top:          Point.new(.active, Coordinate{ y: 5 })
		tracked_pins: &remap
	}) or { panic(err) }
	defer { c.deinit() }

	new_pin := remap.get(tracked) or {
		assert false
		return
	}
	point := c.point_from_pin(.active, *new_pin) or {
		assert false
		return
	}
	assert point.coord().x == 0
	assert point.coord().y == 1
}

fn test_page_list_clone_remap_tracked_pin_not_in_cloned_area() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }
	tracked := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 3 })) or {
		assert false
		return
	})!

	mut remap := PageTrackedPinsRemap.init()
	defer { remap.deinit() }
	mut c := s.clone(PageCloneOpts{
		top:          Point.new(.active, Coordinate{ y: 5 })
		tracked_pins: &remap
	}) or { panic(err) }
	defer { c.deinit() }
	assert remap.get(tracked) == none
}

fn test_page_list_clone_full_dirty() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }
	for y in [u16(0), 12, 23] {
		s.mark_dirty(Point.new(.active, Coordinate{ y: y }))
	}

	mut c := s.clone(PageCloneOpts{ top: Point.new(.screen, Coordinate{}) }) or { panic(err) }
	defer { c.deinit() }
	for y in 0 .. 24 {
		assert c.is_dirty(Point.new(.active, Coordinate{ y: u32(y) })) == (y in [0, 12, 23])
	}
}

fn test_page_list_clone_restarts_page_serials() ! {
	mut s := PageList.init(80, 24, none)!
	defer { s.deinit() }
	s.grow_rows(uint(initial_capacity(s.cols).rows))!

	mut cloned := s.clone(PageCloneOpts{ top: Point.new(.screen, Coordinate{}) }) or { panic(err) }
	defer { cloned.deinit() }
	mut expected := u64(0)
	mut node := cloned.pages.first
	for {
		current := node or { break }
		assert current.serial == expected
		expected++
		node = current.next
	}
	assert cloned.page_serial == expected
}

fn test_page_list_clone_active_only() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(100)!

	mut c := s.clone(PageCloneOpts{
		top: Point.new(.active, Coordinate{})
	}) or { panic(err) }
	defer { c.deinit() }

	// Clone of active should have at least 24 rows
	assert c.total_rows >= uint(s.rows)
}

fn test_page_list_clone_less_than_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(100)!

	// Clone just active area, should be regrown to full active size
	mut c := s.clone(PageCloneOpts{
		top: Point.new(.active, Coordinate{})
	}) or { panic(err) }
	defer { c.deinit() }

	assert c.total_rows >= uint(s.rows)
}

// ============================================================
// Resize without reflow tests
// ============================================================

fn test_page_list_resize_no_reflow_more_rows() ! {
	mut s := PageList.init(80, 3, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.total_rows == 3

	s.resize(PageResizeOpts{
		cols:   80
		rows:   10
		reflow: false
	}) or { panic(err) }

	assert s.rows == 10
	assert s.total_rows >= 10
}

fn test_page_list_resize_no_reflow_more_rows_with_history() ! {
	mut s := PageList.init(80, 3, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Create history
	s.grow_rows(50)!

	old_total := s.total_rows

	s.resize(PageResizeOpts{
		cols:   80
		rows:   10
		reflow: false
	}) or { panic(err) }

	assert s.rows == 10
	assert s.total_rows >= old_total
}

fn test_page_list_resize_no_reflow_less_rows() ! {
	mut s := PageList.init(80, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Write to all rows
	for y in u16(0) .. 10 {
		set_active_cell(mut s, 0, y, u32(y) + u32(0x41))
	}

	s.resize(PageResizeOpts{
		cols:   80
		rows:   5
		reflow: false
	}) or { panic(err) }

	assert s.rows == 5
}

fn test_page_list_resize_no_reflow_one_row() ! {
	mut s := PageList.init(80, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Write to all rows
	for y in u16(0) .. 10 {
		set_active_cell(mut s, 0, y, u32(y) + u32(0x41))
	}

	s.resize(PageResizeOpts{
		cols:   80
		rows:   1
		reflow: false
	}) or { panic(err) }

	assert s.rows == 1
}

fn test_page_list_resize_no_reflow_less_cols() ! {
	mut s := PageList.init(10, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.resize(PageResizeOpts{
		cols:   5
		rows:   10
		reflow: false
	}) or { panic(err) }

	assert s.cols == 5

	// Resizing changes the live column count but preserves the fixed backing
	// capacity of every row, matching Page's packed allocation.
	mut node := s.pages.first
	for {
		n := node or { break }
		for row in n.data.rows {
			assert row.cells.len == int(n.data.capacity.cols)
		}
		node = n.next
	}
}

fn test_page_list_resize_no_reflow_less_cols_pin_in_trimmed() ! {
	mut s := PageList.init(10, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Track a pin at x=8
	p := s.pin(Point.new(.active, Coordinate{ x: 8, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}
	tp := s.track_pin(p)!

	s.resize(PageResizeOpts{
		cols:   5
		rows:   10
		reflow: false
	}) or { panic(err) }

	// Pin should be clamped to x=4
	assert tp.x == 4

	s.untrack_pin(tp)
}

fn test_page_list_resize_no_reflow_more_cols() ! {
	mut s := PageList.init(5, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.resize(PageResizeOpts{
		cols:   10
		rows:   10
		reflow: false
	}) or { panic(err) }

	assert s.cols == 10

	// Verify all rows have 10 cells
	mut node := s.pages.first
	for {
		n := node or { break }
		for row in n.data.rows {
			assert row.cells.len == 10
		}
		node = n.next
	}
}

fn test_page_list_resize_no_reflow_less_cols_then_more() ! {
	mut s := PageList.init(5, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.resize(PageResizeOpts{
		cols:   2
		rows:   10
		reflow: false
	}) or { panic(err) }
	assert s.cols == 2

	s.resize(PageResizeOpts{
		cols:   5
		rows:   10
		reflow: false
	}) or { panic(err) }
	assert s.cols == 5

	// Verify all rows have 5 cells
	mut node := s.pages.first
	for {
		n := node or { break }
		for row in n.data.rows {
			assert row.cells.len == 5
		}
		node = n.next
	}
}

fn test_page_list_resize_no_reflow_less_rows_and_cols() ! {
	mut s := PageList.init(10, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.resize(PageResizeOpts{
		cols:   5
		rows:   5
		reflow: false
	}) or { panic(err) }

	assert s.cols == 5
	assert s.rows == 5
}

fn test_page_list_resize_no_reflow_more_rows_and_less_cols() ! {
	mut s := PageList.init(10, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.resize(PageResizeOpts{
		cols:   5
		rows:   20
		reflow: false
	}) or { panic(err) }

	assert s.cols == 5
	assert s.rows == 20
	assert s.total_rows >= 20
}

fn test_page_list_resize_no_reflow_empty_screen() ! {
	mut s := PageList.init(5, 5, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.resize(PageResizeOpts{
		cols:   10
		rows:   10
		reflow: false
	}) or { panic(err) }

	assert s.cols == 10
	assert s.rows == 10

	// Verify cell access works
	cell := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert cell.cell.codepoint == 0 || cell.cell.content_tag == .bg_color_palette
}

fn test_page_list_resize_more_rows_and_cols_large() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	new_cols := u16(600)
	new_rows := u16(600)
	cap := std_capacity.adjust(PageCapacityAdjustment{ cols: new_cols }) or { panic(err) }
	assert cap.rows < new_rows

	s.resize(PageResizeOpts{
		cols:   new_cols
		rows:   new_rows
		reflow: true
	}) or { panic(err) }

	assert s.cols == new_cols
	assert s.rows == new_rows
	assert s.total_rows == uint(new_rows)
}

// ============================================================
// Reset tests
// ============================================================

fn test_page_list_reset() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Write something
	set_active_cell(mut s, 0, 0, u32(0x41))

	s.reset()

	assert s.viewport == .active
	assert s.total_rows == uint(s.rows)

	// Content should be cleared
	first := s.pages.first or {
		assert false, 'no first page after reset'
		return
	}
	_ = first // exists
}

fn test_page_list_reset_across_two_pages() ! {
	cap := initial_capacity(80)
	rows := u16(cap.rows + 10)
	mut s := PageList.init(80, rows, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.reset()

	assert s.viewport == .active
	assert s.total_rows == uint(rows)
}

fn test_page_list_reset_moves_tracked_pins() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Track a pin
	p := s.pin(Point.new(.active, Coordinate{ x: 5, y: 10 })) or {
		assert false, 'get_pin failed'
		return
	}
	tp := s.track_pin(p)!

	s.reset()

	// Tracked pin should be marked garbage
	assert tp.garbage == true
	assert tp.y == 0
	assert tp.x == 0

	// Viewport pin should NOT be garbage
	assert s.viewport_pin.garbage == false

	s.untrack_pin(tp)
}

fn test_page_list_reset_clears_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow to create history
	s.grow_rows(100)!
	assert s.total_rows > uint(s.rows)

	s.reset()

	assert s.total_rows == uint(s.rows)
}

// ============================================================
// Dirty tracking tests
// ============================================================

fn test_page_list_dirty() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Clear dirty
	s.clear_dirty()
	point := Point.new(.active, Coordinate{})
	assert !s.is_dirty(point)

	// Set a row dirty
	s.mark_dirty(point)

	assert s.is_dirty(point)

	s.clear_dirty()
	assert !s.is_dirty(point)
}

// ============================================================
// Iterator tests
// ============================================================

fn test_page_list_page_iterator_single_page() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	mut it := s.page_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	mut count := 0
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count >= 1
}

fn test_page_list_page_iterator_two_pages() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow to create 2+ pages
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 2)!

	mut it := s.page_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	mut count := 0
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count >= 2
}

fn test_page_list_page_iterator_reverse() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 2)!

	mut it := s.page_iterator(.left_up, Point.new(.screen, Coordinate{}), none)
	mut count := 0
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count >= 2
}

fn test_page_list_row_iterator() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	mut count := uint(0)
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count == uint(s.rows)
}

fn test_page_list_row_iterator_with_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(50)!

	// Active iterator should still give rows count
	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	mut count := uint(0)
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count == uint(s.rows)

	// Screen iterator should give total_rows
	mut it2 := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	mut count2 := uint(0)
	for {
		_ := it2.next() or { break }
		count2 += 1
	}
	assert count2 == s.total_rows
}

fn test_page_list_cell_iterator() ! {
	mut s := PageList.init(10, 5, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	mut it := s.cell_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	mut count := uint(0)
	for {
		_ := it.next() or { break }
		count += 1
	}
	// Should be cols * rows cells
	assert count == uint(s.cols) * uint(s.rows)
}

fn test_page_list_cell_iterator_reverse() ! {
	mut s := PageList.init(10, 5, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	mut it := s.cell_iterator(.left_up, Point.new(.active, Coordinate{}), none)
	mut count := uint(0)
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count == uint(s.cols) * uint(s.rows)
}

fn test_page_list_cell_iterator_preserves_starting_column() ! {
	mut s := PageList.init(5, 2, uint(0))!
	defer { s.deinit() }

	start := s.pin(Point.new(.screen, Coordinate{ x: 3, y: 0 })) or {
		assert false
		return
	}
	limit := s.pin(Point.new(.screen, Coordinate{ x: 4, y: 0 })) or {
		assert false
		return
	}
	mut forward := start.cell_iterator(.right_down, limit)
	assert (forward.next() or { Pin{} }).x == 3
	assert (forward.next() or { Pin{} }).x == 4
	assert forward.next() == none

	mut reverse := start.cell_iterator(.left_up, s.pin(Point.new(.screen, Coordinate{ x: 0, y: 0 })))
	assert (reverse.next() or { Pin{} }).x == 3
	assert (reverse.next() or { Pin{} }).x == 2
	assert (reverse.next() or { Pin{} }).x == 1
	assert (reverse.next() or { Pin{} }).x == 0
	assert reverse.next() == none
}

fn test_page_list_prompt_iterator() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }

	// Set semantic prompts on some rows
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	page.rows[5].header.semantic_prompt = .prompt
	page.rows[10].header.semantic_prompt = .prompt
	page.rows[11].header.semantic_prompt = .prompt_continuation

	// A continuation belongs to the prompt immediately before it.
	tl := s.get_top_left(.screen)
	mut it := tl.prompt_iterator(.right_down, none)
	mut count := 0
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count == 2
}

fn test_page_list_prompt_iterator_reverse() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	page.rows[5].header.semantic_prompt = .prompt
	page.rows[10].header.semantic_prompt = .prompt
	page.rows[11].header.semantic_prompt = .prompt_continuation

	// Reverse prompt iterator from bottom
	br := s.get_bottom_right(.screen) or {
		assert false, 'get_bottom_right failed'
		return
	}
	mut it := br.prompt_iterator(.left_up, none)
	mut count := 0
	for {
		_ := it.next() or { break }
		count += 1
	}
	assert count == 2
}

fn test_page_list_prompt_iterator_left_up() ! {
	mut s := PageList.init(2, 20, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.rows[3].header.semantic_prompt = .prompt
	first.data.rows[6].header.semantic_prompt = .prompt
	first.data.rows[7].header.semantic_prompt = .prompt_continuation
	first.data.rows[8].header.semantic_prompt = .prompt_continuation
	first.data.rows[12].header.semantic_prompt = .prompt_continuation

	mut it := s.prompt_iterator(.left_up, Point.new(.screen, Coordinate{}), none)
	for expected in [u32(12), 6, 3] {
		pin := it.next() or {
			assert false
			return
		}
		point := s.point_from_pin(.screen, pin) or {
			assert false
			return
		}
		assert point is PointScreen
		assert point.coord() == Coordinate{ x: 0, y: expected }
	}
	assert it.next() == none
}

fn test_page_list_prompt_iterator_right_down() ! {
	mut s := PageList.init(2, 20, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.rows[3].header.semantic_prompt = .prompt
	first.data.rows[6].header.semantic_prompt = .prompt
	first.data.rows[7].header.semantic_prompt = .prompt_continuation
	first.data.rows[8].header.semantic_prompt = .prompt_continuation
	first.data.rows[12].header.semantic_prompt = .prompt_continuation

	mut it := s.prompt_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for expected in [u32(3), 6, 12] {
		pin := it.next() or {
			assert false
			return
		}
		point := s.point_from_pin(.screen, pin) or {
			assert false
			return
		}
		assert point is PointScreen
		assert point.coord() == Coordinate{ x: 0, y: expected }
	}
	assert it.next() == none
}

fn test_page_list_prompt_iterator_right_down_continuation_at_start() ! {
	mut s := PageList.init(2, 20, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.rows[0].header.semantic_prompt = .prompt_continuation
	first.data.rows[1].header.semantic_prompt = .prompt_continuation
	first.data.rows[5].header.semantic_prompt = .prompt

	mut it := s.prompt_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for expected in [u32(0), 5] {
		pin := it.next() or {
			assert false
			return
		}
		point := s.point_from_pin(.screen, pin) or {
			assert false
			return
		}
		assert point is PointScreen
		assert point.coord() == Coordinate{ x: 0, y: expected }
	}
	assert it.next() == none
}

fn test_page_list_prompt_iterator_right_down_with_prompt_before_continuation() ! {
	mut s := PageList.init(2, 20, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.rows[2].header.semantic_prompt = .prompt
	first.data.rows[3].header.semantic_prompt = .prompt_continuation
	first.data.rows[4].header.semantic_prompt = .prompt_continuation

	mut it := s.prompt_iterator(.right_down, Point.new(.screen, Coordinate{ y: 3 }), none)
	pin := it.next() or {
		assert false
		return
	}
	point := s.point_from_pin(.screen, pin) or {
		assert false
		return
	}
	assert point == Point.new(.screen, Coordinate{ x: 0, y: 3 })
	assert it.next() == none
}

fn test_page_list_prompt_iterator_right_down_limit_inclusive() ! {
	mut s := PageList.init(2, 20, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.rows[5].header.semantic_prompt = .prompt
	first.data.rows[10].header.semantic_prompt = .prompt

	mut it := s.prompt_iterator(.right_down, Point.new(.screen, Coordinate{}), Point.new(.screen,
		Coordinate{ y: 5 }))
	pin := it.next() or {
		assert false
		return
	}
	point := s.point_from_pin(.screen, pin) or {
		assert false
		return
	}
	assert point == Point.new(.screen, Coordinate{ x: 0, y: 5 })
	assert it.next() == none
}

fn test_page_list_prompt_iterator_left_up_limit_inclusive() ! {
	mut s := PageList.init(2, 20, uint(0))!
	defer { s.deinit() }
	mut first := s.pages.first or {
		assert false
		return
	}
	first.data.rows[5].header.semantic_prompt = .prompt
	first.data.rows[10].header.semantic_prompt = .prompt

	mut it := s.prompt_iterator(.left_up, Point.new(.screen, Coordinate{ y: 10 }), Point.new(.screen,
		Coordinate{ y: 15 }))
	pin := it.next() or {
		assert false
		return
	}
	point := s.point_from_pin(.screen, pin) or {
		assert false
		return
	}
	assert point == Point.new(.screen, Coordinate{ x: 0, y: 10 })
	assert it.next() == none
}

fn test_page_list_highlight_semantic_content() ! {
	mut s := PageList.init(10, 8, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[2].header.semantic_prompt = .prompt
	page.rows[6].header.semantic_prompt = .prompt

	for x in 0 .. 2 {
		page.rows[2].cells[x] = CellData{
			codepoint:        u32(`$`)
			semantic_content: .prompt
		}
	}
	for x in 2 .. 5 {
		page.rows[2].cells[x] = CellData{
			codepoint:        u32(`i`)
			semantic_content: .input
		}
	}
	for x in 0 .. 3 {
		page.rows[3].cells[x] = CellData{
			codepoint:        u32(`o`)
			semantic_content: .output
		}
	}
	page.rows[4].cells[1] = CellData{
		codepoint:        u32(`z`)
		semantic_content: .output
	}

	at := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 2 })) or {
		assert false
		return
	}
	prompt := s.highlight_semantic_content(at, .prompt) or {
		assert false, 'prompt highlight missing'
		return
	}
	assert (s.point_from_pin(.screen, prompt.start) or { Point(PointActive{}) }) == Point.new(.screen,
		Coordinate{ x: 0, y: 2 })
	assert (s.point_from_pin(.screen, prompt.end) or { Point(PointActive{}) }) == Point.new(.screen,
		Coordinate{ x: 4, y: 2 })

	input := s.highlight_semantic_content(at, .input) or {
		assert false, 'input highlight missing'
		return
	}
	assert (s.point_from_pin(.screen, input.start) or { Point(PointActive{}) }) == Point.new(.screen,
		Coordinate{ x: 2, y: 2 })
	assert (s.point_from_pin(.screen, input.end) or { Point(PointActive{}) }) == Point.new(.screen,
		Coordinate{ x: 4, y: 2 })

	output := s.highlight_semantic_content(at, .output) or {
		assert false, 'output highlight missing'
		return
	}
	assert (s.point_from_pin(.screen, output.start) or { Point(PointActive{}) }) == Point.new(.screen,
		Coordinate{ x: 0, y: 3 })
	assert (s.point_from_pin(.screen, output.end) or { Point(PointActive{}) }) == Point.new(.screen,
		Coordinate{ x: 1, y: 4 })
}

fn test_page_list_highlight_semantic_content_missing_input_and_output() ! {
	mut s := PageList.init(5, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false
		return
	}
	mut page := &first.data
	page.rows[0].header.semantic_prompt = .prompt
	for x in 0 .. 5 {
		page.rows[0].cells[x] = CellData{
			codepoint:        u32(`$`)
			semantic_content: .prompt
		}
	}
	at := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 0 })) or {
		assert false
		return
	}
	assert s.highlight_semantic_content(at, .input) == none
	assert s.highlight_semantic_content(at, .output) == none
}

fn test_page_list_highlight_semantic_content_prompt() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 5, u32(`A`), .prompt)
	set_screen_semantic_range(mut s, 5, 5, 8, u32(`B`), .input)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 2, y: 5 }, .prompt, Pin{ x: 0, y: 5 }, Pin{ x: 7, y: 5 })
}

fn test_page_list_highlight_semantic_content_prompt_with_output() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 3, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 3, 7, u32(`l`), .input)
	set_screen_semantic_range(mut s, 5, 7, 10, u32(`o`), .output)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .prompt, Pin{ x: 0, y: 5 }, Pin{ x: 6, y: 5 })
}

fn test_page_list_highlight_semantic_content_prompt_multiline() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 10, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 6, 0, 5, u32(`c`), .input)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 2, y: 5 }, .prompt, Pin{ x: 0, y: 5 }, Pin{ x: 4, y: 6 })
}

fn test_page_list_highlight_semantic_content_prompt_only() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 5, u32(`$`), .prompt)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .prompt, Pin{ x: 0, y: 5 }, Pin{ x: 4, y: 5 })
}

fn test_page_list_highlight_semantic_content_prompt_to_end_of_screen() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 15)
	set_screen_semantic_range(mut s, 15, 0, 3, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 15, 3, 8, u32(`c`), .input)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 15 }, .prompt, Pin{ x: 0, y: 15 }, Pin{ x: 7, y: 15 })
}

fn test_page_list_highlight_semantic_content_input_basic() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 3, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 3, 8, u32(`l`), .input)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .input, Pin{ x: 3, y: 5 }, Pin{ x: 7, y: 5 })
}

fn test_page_list_highlight_semantic_content_input_with_output() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 2, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 2, 5, u32(`c`), .input)
	set_screen_semantic_range(mut s, 5, 5, 10, u32(`o`), .output)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .input, Pin{ x: 2, y: 5 }, Pin{ x: 4, y: 5 })
}

fn test_page_list_highlight_semantic_content_input_multiline_with_continuation() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 2, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 2, 10, u32(`c`), .input)
	set_screen_semantic_range(mut s, 6, 0, 2, u32(`>`), .prompt)
	set_screen_semantic_range(mut s, 6, 2, 6, u32(`d`), .input)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .input, Pin{ x: 2, y: 5 }, Pin{ x: 5, y: 6 })
}

fn test_page_list_highlight_semantic_content_input_no_input_returns_none() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 3, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 3, 10, u32(`o`), .output)
	mark_screen_prompt(mut s, 10)
	at := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 5 })) or {
		assert false
		return
	}
	assert s.highlight_semantic_content(at, .input) == none
}

fn test_page_list_highlight_semantic_content_input_to_end_of_screen() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 15)
	set_screen_semantic_range(mut s, 15, 0, 2, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 15, 2, 7, u32(`c`), .input)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 15 }, .input, Pin{ x: 2, y: 15 }, Pin{ x: 6, y: 15 })
}

fn test_page_list_highlight_semantic_content_input_prompt_only_returns_none() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 10, u32(`$`), .prompt)
	for y in u16(6) .. u16(10) {
		set_screen_semantic_range(mut s, y, 0, 10, 0, .prompt)
	}
	mark_screen_prompt(mut s, 10)
	at := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 5 })) or {
		assert false
		return
	}
	assert s.highlight_semantic_content(at, .input) == none
}

fn test_page_list_highlight_semantic_content_output_basic() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 2, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 2, 5, u32(`l`), .input)
	set_screen_semantic_range(mut s, 5, 5, 8, u32(`o`), .output)
	set_screen_semantic_range(mut s, 5, 8, 10, 0, .prompt)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .output, Pin{ x: 5, y: 5 }, Pin{ x: 7, y: 5 })
}

fn test_page_list_highlight_semantic_content_output_multiline() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 2, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 2, 4, u32(`l`), .input)
	set_screen_semantic_range(mut s, 5, 4, 10, u32(`o`), .output)
	set_screen_semantic_range(mut s, 6, 0, 10, u32(`o`), .output)
	set_screen_semantic_range(mut s, 7, 0, 5, u32(`o`), .output)
	set_screen_semantic_range(mut s, 7, 5, 10, 0, .input)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .output, Pin{ x: 4, y: 5 }, Pin{ x: 4, y: 7 })
}

fn test_page_list_highlight_semantic_content_output_stops_at_next_prompt() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 2, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 2, 4, u32(`l`), .input)
	set_screen_semantic_range(mut s, 5, 4, 10, u32(`o`), .output)
	set_screen_semantic_range(mut s, 6, 0, 3, u32(`o`), .output)
	set_screen_semantic_range(mut s, 6, 3, 6, u32(`$`), .prompt)
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .output, Pin{ x: 4, y: 5 }, Pin{ x: 2, y: 6 })
}

fn test_page_list_highlight_semantic_content_output_to_end_of_screen() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 15)
	set_screen_semantic_range(mut s, 15, 0, 2, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 15, 2, 4, u32(`c`), .input)
	set_screen_semantic_range(mut s, 15, 4, 10, u32(`o`), .output)
	set_screen_semantic_range(mut s, 16, 0, 8, u32(`o`), .output)
	set_screen_semantic_range(mut s, 16, 8, 10, 0, .prompt)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 15 }, .output, Pin{ x: 4, y: 15 }, Pin{ x: 7, y: 16 })
}

fn test_page_list_highlight_semantic_content_output_no_output_returns_none() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 3, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 5, 3, 10, u32(`c`), .input)
	for y in u16(6) .. u16(10) {
		set_screen_semantic_range(mut s, y, 0, 10, 0, .input)
	}
	mark_screen_prompt(mut s, 10)
	at := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 5 })) or {
		assert false
		return
	}
	assert s.highlight_semantic_content(at, .output) == none
}

fn test_page_list_highlight_semantic_content_output_skips_empty_cells() ! {
	mut s := PageList.init(10, 20, uint(0))!
	defer { s.deinit() }
	mark_screen_prompt(mut s, 5)
	set_screen_semantic_range(mut s, 5, 0, 3, u32(`$`), .prompt)
	set_screen_semantic_range(mut s, 6, 0, 4, u32(`l`), .input)
	for y in u16(7) .. u16(9) {
		set_screen_semantic_range(mut s, y, 0, 5, u32(`o`), .output)
	}
	mark_screen_prompt(mut s, 10)
	assert_page_list_semantic_highlight(&s, Pin{ x: 0, y: 5 }, .output, Pin{ x: 0, y: 7 }, Pin{ x: 4, y: 8 })
}

// ============================================================
// Pin movement tests
// ============================================================

fn test_page_pin_left_right() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 5, y: 3 })) or {
		assert false, 'get_pin failed'
		return
	}

	left := p.left(2)
	assert left.x == 3
	assert left.y == p.y

	right := p.right(3)
	assert right.x == 8
	assert right.y == p.y
}

fn test_page_pin_left_clamp_right_clamp() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 2, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}

	// Left clamp past 0
	lc := p.left_clamp(10)
	assert lc.x == 0

	// Right clamp past end
	rc := p.right_clamp(20)
	assert rc.x == 9 // cols - 1
	assert p.right_clamp(max_u16).x == 9
}

fn test_page_pin_horizontal_movement_preserves_garbage() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	base := s.pin(Point.new(.active, Coordinate{ x: 5, y: 3 })) or {
		assert false, 'pin failed'
		return
	}
	p := Pin{
		node:    base.node
		y:       base.y
		x:       base.x
		garbage: true
	}
	assert p.left(1).garbage
	assert p.right(1).garbage
	assert p.left_clamp(max_u16).garbage
	assert p.right_clamp(max_u16).garbage
	assert (p.left_wrap(1) or {
		assert false
		return
	}).garbage
	assert (p.right_wrap(1) or {
		assert false
		return
	}).garbage
}

fn test_page_pin_down_up() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	}

	// Down
	d := p.down(5) or {
		assert false, 'down failed'
		return
	}
	pt := s.point_from_pin(.active, d) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert pt.coord().y == 5

	// Up
	u := d.up(3) or {
		assert false, 'up failed'
		return
	}
	pt2 := s.point_from_pin(.active, u) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert pt2.coord().y == 2
}

fn test_page_pin_down_overflow() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 5 })) or {
		assert false, 'get_pin failed'
		return
	}

	// Within bounds
	result := p.down_overflow(3)
	match result {
		DownOverflowOffset {
			pt := s.point_from_pin(.active, result.pin) or {
				assert false, 'point_from_pin failed'
				return
			}
			assert pt.coord().y == 8
		}
		DownOverflowOverflow {
			assert false, 'should not overflow'
		}
	}

	// Past end
	result2 := p.down_overflow(100)
	match result2 {
		DownOverflowOffset {
			assert false, 'should overflow'
		}
		DownOverflowOverflow {
			assert result2.remaining > 0
		}
	}

	// Movement uses Ghostty's usize contract rather than narrowing at u32.
	large := uint(max_u32) + 1
	result3 := p.down_overflow(large)
	match result3 {
		DownOverflowOffset {
			assert false, 'should overflow'
		}
		DownOverflowOverflow {
			assert result3.remaining == large - 4
		}
	}
}

fn test_page_pin_up_overflow() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 0, y: 5 })) or {
		assert false, 'get_pin failed'
		return
	}

	// Within bounds
	result := p.up_overflow(3)
	match result {
		UpOverflowOffset {
			pt := s.point_from_pin(.active, result.pin) or {
				assert false, 'point_from_pin failed'
				return
			}
			assert pt.coord().y == 2
		}
		UpOverflowOverflow {
			assert false, 'should not overflow'
		}
	}

	// Past beginning
	result2 := p.up_overflow(100)
	match result2 {
		UpOverflowOffset {
			assert false, 'should overflow'
		}
		UpOverflowOverflow {
			assert result2.remaining > 0
		}
	}

	large := uint(max_u32) + 1
	result3 := p.up_overflow(large)
	match result3 {
		UpOverflowOffset {
			assert false, 'should overflow'
		}
		UpOverflowOverflow {
			assert result3.remaining == large - 5
		}
	}
}

fn test_page_pin_before() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	p1 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 2 })) or {
		assert false
		return
	}
	p2 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 5 })) or {
		assert false
		return
	}

	assert p1.before(p2)
	assert !p2.before(p1)
	assert !p1.before(p1) // Same pin
}

fn test_page_pin_eql() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	p1 := s.pin(Point.new(.active, Coordinate{ x: 3, y: 5 })) or {
		assert false
		return
	}
	p2 := s.pin(Point.new(.active, Coordinate{ x: 3, y: 5 })) or {
		assert false
		return
	}
	p3 := s.pin(Point.new(.active, Coordinate{ x: 4, y: 5 })) or {
		assert false
		return
	}

	assert p1.eql(p2)
	assert !p1.eql(p3)
}

fn test_page_pin_is_between() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	top := s.pin(Point.new(.active, Coordinate{ x: 0, y: 2 })) or {
		assert false
		return
	}
	mid := s.pin(Point.new(.active, Coordinate{ x: 0, y: 5 })) or {
		assert false
		return
	}
	bot := s.pin(Point.new(.active, Coordinate{ x: 0, y: 8 })) or {
		assert false
		return
	}

	assert mid.is_between(top, bot)
	assert top.is_between(top, bot) // Inclusive
	assert bot.is_between(top, bot) // Inclusive
	assert !s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or { return }.is_between(top, bot)
}

// ============================================================
// Integrity tests
// ============================================================

fn test_page_list_assert_integrity() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.assert_integrity()

	s.grow_rows(100)!
	s.assert_integrity()
}

fn test_page_list_verify_integrity() ! {
	if !buildcfg.slow_runtime_safety { return }
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	assert s.verify_integrity() == none

	s.grow_rows(100)!
	assert s.verify_integrity() == none

	// Cached row count must match the linked pages.
	s.total_rows++
	assert (s.verify_integrity() or { panic('missing integrity violation') }) == .total_rows_mismatch
	s.total_rows--

	// Every live page serial must be at least page_serial_min.
	s.page_serial_min = s.page_serial
	assert (s.verify_integrity() or { panic('missing integrity violation') }) == .page_serial_invalid
	s.page_serial_min = 0

	// Tracked pins must point within a live page.
	old_y := s.viewport_pin.y
	s.viewport_pin.y = s.viewport_pin.node.data.size.rows
	assert (s.verify_integrity() or { panic('missing integrity violation') }) == .tracked_pin_invalid
	s.viewport_pin.y = old_y

	// A pinned viewport cache must equal its independently calculated offset.
	s.viewport = .pin
	s.viewport_pin.node = s.pages.first or {
		assert false, 'missing first page'
		return
	}
	s.viewport_pin.y = 0
	s.viewport_pin.x = 0
	s.viewport_pin_row_offset = 1
	assert (s.verify_integrity() or { panic('missing integrity violation') }) == .viewport_pin_offset_mismatch
	s.viewport_pin_row_offset = 0
	assert s.verify_integrity() == none

	// A pin too close to the bottom cannot fill the viewport.
	last := s.pages.last or {
		assert false, 'missing last page'
		return
	}
	s.viewport_pin.node = last
	s.viewport_pin.y = last.data.size.rows - 1
	s.viewport_pin_row_offset = none
	assert (s.verify_integrity() or { panic('missing integrity violation') }) == .viewport_pin_insufficient_rows

	// Restore a valid state for deferred cleanup.
	s.viewport = .active
	s.viewport_pin.node = s.pages.first or { return }
	s.viewport_pin.y = 0
	s.viewport_pin.x = 0
}

// ============================================================
// Scrollbar tests
// ============================================================

fn test_page_list_scrollbar_no_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	sb := s.scrollbar()
	assert sb.total == uint(s.rows)
	assert sb.offset == 0
	assert sb.len == uint(s.rows)
}

fn test_page_list_scrollbar_with_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(100)!

	sb := s.scrollbar()
	assert sb.total == s.total_rows
	assert sb.offset == s.total_rows - uint(s.rows)
	assert sb.len == uint(s.rows)
}

fn test_page_list_scrollbar_at_top() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(100)!
	s.scroll(PageScrollTop{})

	sb := s.scrollbar()
	assert sb.total == s.total_rows
	assert sb.offset == 0
	assert sb.len == uint(s.rows)
}

fn test_page_list_scrollbar_in_middle() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(100)!
	s.scroll(PageScrollRow{ n: 50 })

	sb := s.scrollbar()
	assert sb.total == s.total_rows
	assert sb.offset == 50
	assert sb.len == uint(s.rows)
}

// ============================================================
// Page-linked-list tests
// ============================================================

fn test_page_node_list_append_remove() ! {
	mut list := PageNodeList{}

	n1 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 1
	}
	n2 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 2
	}
	n3 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 3
	}

	list.append(n1)
	list.append(n2)
	list.append(n3)

	// Verify order
	f := list.first or {
		assert false
		return
	}
	assert f.serial == 1
	s := f.next or {
		assert false
		return
	}
	assert s.serial == 2
	t := s.next or {
		assert false
		return
	}
	assert t.serial == 3

	// Remove middle
	list.remove(n2)
	f2 := list.first or {
		assert false
		return
	}
	n := f2.next or {
		assert false
		return
	}
	assert n.serial == 3
}

fn test_page_node_list_prepend() ! {
	mut list := PageNodeList{}

	n1 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 1
	}
	n2 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 2
	}

	list.append(n1)
	list.prepend(n2)

	f := list.first or {
		assert false
		return
	}
	assert f.serial == 2
}

fn test_page_node_list_insert_after() ! {
	mut list := PageNodeList{}

	n1 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 1
	}
	n2 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 2
	}
	n3 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 3
	}

	list.append(n1)
	list.append(n3)
	list.insert_after(n1, n2)

	f := list.first or {
		assert false
		return
	}
	s := f.next or {
		assert false
		return
	}
	assert s.serial == 2
	t := s.next or {
		assert false
		return
	}
	assert t.serial == 3
}

fn test_page_node_list_insert_before() ! {
	mut list := PageNodeList{}

	n1 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 1
	}
	n2 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 2
	}
	n3 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 3
	}

	list.append(n1)
	list.append(n3)
	list.insert_before(n3, n2)

	f := list.first or {
		assert false
		return
	}
	s := f.next or {
		assert false
		return
	}
	assert s.serial == 2
}

fn test_page_node_list_pop() ! {
	mut list := PageNodeList{}

	n1 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 1
	}
	n2 := &PageNode{
		data:   Page.init(std_capacity)!
		serial: 2
	}

	list.append(n1)
	list.append(n2)

	first := list.pop_first() or {
		assert false
		return
	}
	assert first.serial == 1

	last := list.pop_last() or {
		assert false
		return
	}
	assert last.serial == 2

	assert list.first == none
	assert list.last == none
}

// ============================================================
// Newly translated tests from Ghostty PageList.zig
// ============================================================

fn test_page_list_point_from_pin_active_from_prior_page() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow so we take up at least 5 pages.
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!

	last := s.pages.last or {
		assert false, 'no last page'
		return
	}
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	// Pin in the active (last) page.
	pt := s.point_from_pin(.active, Pin{ node: last, y: 0, x: 2 }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert pt.coord().x == 2
	assert pt.coord().y == 0

	// A pin in a prior (first) page is not in the active area.
	if _ := s.point_from_pin(.active, Pin{ node: first, y: 0, x: 0 }) {
		assert false, 'expected point_from_pin to return none for prior page'
	}
}

fn test_page_list_scroll_delta_row_back_without_space_preserves_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.scroll(PageScrollDeltaRow{ delta: -1 })

	pc := s.get_cell(Point.new(.viewport, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp := pc.screen_point()
	assert sp.coord().x == 0
	assert sp.coord().y == 0

	assert s.viewport == .active

	sb := s.scrollbar()
	assert sb.total == s.total_rows
	assert sb.offset == s.total_rows - uint(s.rows)
	assert sb.len == uint(s.rows)
}

fn test_page_list_jump_zero_prompts() ! {
	mut s := PageList.init(5, 3, none)!
	defer { s.deinit() }
	s.grow_rows(3)!
	mut first := s.pages.first or { return }
	assert voidptr(first) == voidptr(s.pages.last or { return })
	first.data.rows[1].header.semantic_prompt = .prompt
	first.data.rows[5].header.semantic_prompt = .prompt

	s.scroll(PageScrollDeltaPrompt{})
	assert s.viewport == .active
	assert s.scrollbar() == Scrollbar{
		total:  s.total_rows
		offset: s.total_rows - uint(s.rows)
		len:    uint(s.rows)
	}
}

fn test_page_list_jump_back_one_prompt() ! {
	mut s := PageList.init(5, 3, none)!
	defer { s.deinit() }
	s.grow_rows(3)!
	mut first := s.pages.first or { return }
	assert voidptr(first) == voidptr(s.pages.last or { return })
	first.data.rows[1].header.semantic_prompt = .prompt
	first.data.rows[5].header.semantic_prompt = .prompt

	s.scroll(PageScrollDeltaPrompt{ delta: -1 })
	assert s.viewport == .pin
	viewport := s.get_top_left(.viewport)
	assert s.point_from_pin(.screen, viewport) or { return } == Point.new(.screen, Coordinate{
		x: 0
		y: 1
	})
	assert s.scrollbar() == Scrollbar{ total: s.total_rows, offset: 1, len: uint(s.rows) }

	s.scroll(PageScrollDeltaPrompt{ delta: -1 })
	assert s.viewport == .pin
	assert s.point_from_pin(.screen, s.get_top_left(.viewport)) or { return } == Point.new(.screen,
		Coordinate{ x: 0, y: 1 })
	assert s.scrollbar().offset == 1

	s.scroll(PageScrollDeltaPrompt{ delta: 1 })
	assert s.viewport == .active
	assert s.scrollbar().offset == s.total_rows - uint(s.rows)
	s.scroll(PageScrollDeltaPrompt{ delta: 1 })
	assert s.viewport == .active
}

fn test_page_list_scroll_to_row_with_cache_fast_path_down() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	s.grow_rows(50)!

	s.scroll(PageScrollRow{ n: 10 })
	assert s.viewport == .pin
	sb1 := s.scrollbar()
	assert sb1.total == s.total_rows
	assert sb1.offset == 10
	assert sb1.len == uint(s.rows)

	pc1 := s.get_cell(Point.new(.viewport, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp1 := pc1.screen_point()
	assert sp1.coord().x == 0
	assert sp1.coord().y == 10

	// Cache should be populated.
	off1 := s.viewport_pin_row_offset or {
		assert false, 'viewport_pin_row_offset not cached'
		return
	}
	assert off1 == 10

	// Scroll down to a different row - fast path.
	s.scroll(PageScrollRow{ n: 20 })
	assert s.viewport == .pin
	sb2 := s.scrollbar()
	assert sb2.offset == 20

	pc2 := s.get_cell(Point.new(.viewport, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp2 := pc2.screen_point()
	assert sp2.coord().y == 20

	s.grow_rows(10)!
	pc3 := s.get_cell(Point.new(.viewport, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp3 := pc3.screen_point()
	assert sp3.coord().y == 20

	sb3 := s.scrollbar()
	assert sb3.offset == 20
}

fn test_page_list_scroll_to_row_with_cache_fast_path_up() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	s.grow_rows(50)!

	s.scroll(PageScrollRow{ n: 30 })
	assert s.viewport == .pin
	sb1 := s.scrollbar()
	assert sb1.offset == 30

	pc1 := s.get_cell(Point.new(.viewport, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert pc1.screen_point().coord().y == 30

	off1 := s.viewport_pin_row_offset or {
		assert false, 'viewport_pin_row_offset not cached'
		return
	}
	assert off1 == 30

	// Scroll up to a different row - fast path.
	s.scroll(PageScrollRow{ n: 15 })
	assert s.viewport == .pin
	sb2 := s.scrollbar()
	assert sb2.offset == 15

	pc2 := s.get_cell(Point.new(.viewport, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert pc2.screen_point().coord().y == 15

	s.grow_rows(10)!
	pc3 := s.get_cell(Point.new(.viewport, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert pc3.screen_point().coord().y == 15

	sb3 := s.scrollbar()
	assert sb3.offset == 15
}

fn test_page_list_reset_moves_tracked_pins_and_marks_garbage() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	p := s.pin(Point.new(.active, Coordinate{ x: 42, y: 12 })) or {
		assert false, 'get_pin failed'
		return
	}
	tp := s.track_pin(p)!

	s.reset()

	// Our added pin should now be garbage.
	assert tp.garbage

	// Viewport pin should not be garbage because it makes sense.
	assert !s.viewport_pin.garbage

	s.untrack_pin(tp)
}

fn test_page_list_clears_history() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	s.grow_rows(30)!
	s.reset()
	assert s.viewport == .active
	assert s.pages.first != none
	assert s.total_rows == uint(s.rows)

	// Active area should be the top.
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	tl := s.get_top_left(.active)
	assert voidptr(tl.node) == voidptr(first)
	assert tl.y == 0
	assert tl.x == 0
}

// ============================================================
// erase_row_bounded tests
// ============================================================

fn test_page_list_erase_row_bounded_less_than_full_row() ! {
	mut s := PageList.init(80, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	p_top := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 5 })) or {
		assert false, 'get_pin failed'
		return
	})!
	p_bot := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 8 })) or {
		assert false, 'get_pin failed'
		return
	})!
	p_out := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 9 })) or {
		assert false, 'get_pin failed'
		return
	})!

	// Erase only a few rows in our active.
	s.erase_row_bounded(Point.new(.active, Coordinate{ y: 5 }), 3) or { panic(err) }
	assert s.total_rows == uint(s.rows)

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(p_top.node) == voidptr(first)
	assert p_top.y == 4
	assert p_top.x == 0

	assert voidptr(p_bot.node) == voidptr(first)
	assert p_bot.y == 7
	assert p_bot.x == 0

	assert voidptr(p_out.node) == voidptr(first)
	assert p_out.y == 9
	assert p_out.x == 0

	s.untrack_pin(p_top)
	s.untrack_pin(p_bot)
	s.untrack_pin(p_out)
}

fn test_page_list_erase_row_bounded_preserves_managed_cell_data() ! {
	mut s := PageList.init(6, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	style_id := page.styles.add(CellStyle{
		flags: StyleFlags.init(false, true, false, false, false, false, false, false, .none)
	}) or {
		assert false, 'style add failed'
		return
	}
	page.rows[1].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`M`)
		style_id:    style_id
	}
	page.rows[1].header.styled = true
	page.set_graphemes(1, 1, [u32(0x0308)]) or { panic(err) }
	hyperlink_id := page.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{
			offset: 9
		}
		uri: 'https://example.com/bounded'
	}) or { panic(err) }
	page.set_hyperlink(1, 1, hyperlink_id) or { panic(err) }

	s.erase_row_bounded(Point.new(.active, Coordinate{}), 1) or { panic(err) }

	cell := page.rows[0].cells[1]
	assert cell.codepoint == u32(`M`)
	assert (page.lookup_grapheme_at(0, 1) or { []u32{} }) == [u32(0x0308)]
	assert page.styles.get(cell.style_id).flags.italic()
	assert page.styles.ref_count(cell.style_id) == 1
	moved_link_id := page.lookup_hyperlink_at(0, 1) or {
		assert false, 'bounded hyperlink mapping missing'
		return
	}
	assert page.hyperlink_set.get(moved_link_id).uri == 'https://example.com/bounded'
	assert page.hyperlink_set.ref_count(moved_link_id) == 1
	assert page.rows[1].cells[1].is_zero()
	page.assert_integrity()
}

fn test_page_list_erase_row_bounded_exact_page_boundary() ! {
	mut s := PageList.init(4, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	s.split(Pin{ node: first, y: 2, x: 0 }) or {
		assert false, 'split failed'
		return
	}
	second := first.next or {
		assert false, 'no second page'
		return
	}
	mut second_page := &second.data
	second_page.rows[0].cells[2] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`B`)
	}
	hyperlink_id := second_page.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{
			offset: 10
		}
		uri: 'https://example.com/exact-boundary'
	}) or { panic(err) }
	second_page.set_hyperlink(0, 2, hyperlink_id) or { panic(err) }
	tracked := s.track_pin(Pin{ node: second, y: 0, x: 2 })!

	// One row remains in the first page. A limit of one must pull the next
	// page's first row across the boundary, then blank that source row.
	s.erase_row_bounded(Point.new(.active, Coordinate{ y: 1 }), 1) or { panic(err) }

	assert voidptr(tracked.node) == voidptr(first)
	assert tracked.y == 1
	assert tracked.x == 2
	mut first_page := &first.data
	assert first_page.rows[1].cells[2].codepoint == u32(`B`)
	moved_link_id := first_page.lookup_hyperlink_at(1, 2) or {
		assert false, 'exact-boundary hyperlink mapping missing'
		return
	}
	assert first_page.hyperlink_set.get(moved_link_id).uri == 'https://example.com/exact-boundary'
	assert first_page.hyperlink_set.ref_count(moved_link_id) == 1
	assert second_page.rows[0].cells[2].is_zero()
	assert second_page.lookup_hyperlink_at(0, 2) == none
	first_page.assert_integrity()
	second_page.assert_integrity()
	s.untrack_pin(tracked)
}

fn test_page_list_erase_row_bounded_with_pin_at_top() ! {
	mut s := PageList.init(80, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	p_top := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 5, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.erase_row_bounded(Point.new(.active, Coordinate{}), 3) or { panic(err) }
	assert s.total_rows == uint(s.rows)

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(p_top.node) == voidptr(first)
	assert p_top.y == 0
	assert p_top.x == 0

	s.untrack_pin(p_top)
}

fn test_page_list_erase_row_bounded_full_rows_single_page() ! {
	mut s := PageList.init(80, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	p_in := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 7 })) or {
		assert false, 'get_pin failed'
		return
	})!
	p_out := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 9 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.erase_row_bounded(Point.new(.active, Coordinate{ y: 5 }), 10) or { panic(err) }
	assert s.total_rows == uint(s.rows)

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(p_in.node) == voidptr(first)
	assert p_in.y == 6
	assert p_in.x == 0

	assert voidptr(p_out.node) == voidptr(first)
	assert p_out.y == 8
	assert p_out.x == 0

	s.untrack_pin(p_in)
	s.untrack_pin(p_out)
}

fn test_page_list_erase_row_bounded_full_rows_two_pages() ! {
	mut s := PageList.init(80, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow to two pages so our active area straddles.
	first_page := s.pages.first or {
		assert false, 'no first page'
		return
	}
	remaining := uint(first_page.data.capacity.rows) - uint(first_page.data.size.rows)
	s.grow_rows(remaining)!
	s.grow_rows(5)!
	assert s.total_pages() == 2

	last := s.pages.last or {
		assert false, 'no last page'
		return
	}
	assert last.data.size.rows == 5
	prev := last.prev or {
		assert false, 'no prev page'
		return
	}

	// Pins
	p_first := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 4 })) or {
		assert false, 'get_pin failed'
		return
	})!
	p_first_out := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 3 })) or {
		assert false, 'get_pin failed'
		return
	})!
	p_in := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 8 })) or {
		assert false, 'get_pin failed'
		return
	})!
	p_out := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 9 })) or {
		assert false, 'get_pin failed'
		return
	})!

	// Verify initial pin placement.
	assert voidptr(p_first.node) == voidptr(prev)
	assert p_first.y == u16(prev.data.size.rows - 1)
	assert voidptr(p_first_out.node) == voidptr(prev)
	assert p_first_out.y == u16(prev.data.size.rows - 2)
	assert voidptr(p_in.node) == voidptr(last)
	assert p_in.y == 3
	assert voidptr(p_out.node) == voidptr(last)
	assert p_out.y == 4

	// Erase a few rows in our active starting at active y=4.
	s.erase_row_bounded(Point.new(.active, Coordinate{ y: 4 }), 4) or { panic(err) }

	// In-page pin in first page is shifted up by one.
	assert voidptr(p_first.node) == voidptr(prev)
	assert p_first.y == u16(prev.data.size.rows - 2)
	assert p_first.x == 0

	// Out pin in first page should not be shifted.
	assert voidptr(p_first_out.node) == voidptr(prev)
	assert p_first_out.y == u16(prev.data.size.rows - 2)
	assert p_first_out.x == 0

	// In-page pin in last page is shifted.
	assert voidptr(p_in.node) == voidptr(last)
	assert p_in.y == 2
	assert p_in.x == 0

	// Out pin in last page is not shifted.
	assert voidptr(p_out.node) == voidptr(last)
	assert p_out.y == 4
	assert p_out.x == 0

	s.untrack_pin(p_first)
	s.untrack_pin(p_first_out)
	s.untrack_pin(p_in)
	s.untrack_pin(p_out)
}

// ============================================================
// resize (no reflow) tests
// ============================================================

fn test_page_list_resize_no_reflow_one_row_precise() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }
	assert s.total_rows == 10

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	// Write into all rows so we don't get trim behavior.
	for y in u16(0) .. 10 {
		page.rows[int(y)].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`A`)
		}
	}

	s.resize(PageResizeOpts{ rows: 1, reflow: false }) or { panic(err) }
	assert s.rows == 1
	assert s.total_rows == 10

	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp := pc.screen_point()
	assert sp.coord().x == 0
	assert sp.coord().y == 9
}

fn test_page_list_resize_no_reflow_less_rows_cursor_on_bottom() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }
	assert s.total_rows == 10

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in u16(0) .. 10 {
		page.rows[int(y)].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(y)
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 9 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ rows: 5, reflow: false }) or { panic(err) }
	assert s.rows == 5
	assert s.total_rows == 10

	// Our cursor should move since it's in the scrollback.
	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 0
	assert cursor.coord().y == 4

	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp := pc.screen_point()
	assert sp.coord().x == 0
	assert sp.coord().y == 5

	s.untrack_pin(p)
}

fn test_page_list_resize_no_reflow_less_rows_cursor_in_scrollback() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }
	assert s.total_rows == 10

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in u16(0) .. 10 {
		page.rows[int(y)].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(y)
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 2 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ rows: 5, reflow: false }) or { panic(err) }
	assert s.rows == 5
	assert s.total_rows == 10

	// Our cursor should now be in scrollback (not active).
	if _ := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) {
		assert false, 'expected pin to be outside active'
	}
	sp_pin := s.point_from_pin(.screen, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin screen failed'
		return
	}
	assert sp_pin.coord().x == 0
	assert sp_pin.coord().y == 2

	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp := pc.screen_point()
	assert sp.coord().x == 0
	assert sp.coord().y == 5

	s.untrack_pin(p)
}

fn test_page_list_resize_no_reflow_more_rows_contains_viewport() ! {
	mut s := PageList.init(5, 5, uint(1))!
	defer { s.deinit() }

	// Make it so we have scrollback.
	_ = s.grow()!
	assert s.rows == 5
	assert s.total_rows == 6

	// Set viewport above active by scrolling up one.
	s.scroll(PageScrollDeltaRow{ delta: -1 })
	assert s.viewport == .top

	s.resize(PageResizeOpts{ rows: 7, reflow: false }) or { panic(err) }
	assert s.rows == 7
	assert s.total_rows == 7
	assert s.viewport == .top
}

fn test_page_list_resize_no_reflow_more_rows_extends_blank_lines() ! {
	mut s := PageList.init(10, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Write codepoint into first line.
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`A`)
	}
	// Fill remaining lines with a background color (still blank).
	for y in u16(1) .. 3 {
		page.rows[int(y)].cells[0] = CellData.from_color_payload(.bg_color_rgb, u32(0xFF) | (u32(0) << 8) | (u32(0) << 16))
	}

	s.resize(PageResizeOpts{ rows: 7, reflow: false }) or { panic(err) }
	assert s.rows == 7
	assert s.total_rows == 7

	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp := pc.screen_point()
	assert sp.coord().x == 0
	assert sp.coord().y == 0
}

fn test_page_list_resize_no_reflow_less_rows_trims_blank_lines() ! {
	mut s := PageList.init(10, 5, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Write codepoint into first line.
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`A`)
	}
	// Fill remaining lines with a background color (still blank).
	for y in u16(1) .. 5 {
		page.rows[int(y)].cells[0] = CellData.from_color_payload(.bg_color_rgb, u32(0xFF) | (u32(0) << 8) | (u32(0) << 16))
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ rows: 2, reflow: false }) or { panic(err) }
	assert s.rows == 2
	assert s.total_rows == 2

	// Cursor should not move since we trimmed.
	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 0
	assert cursor.coord().y == 0

	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp := pc.screen_point()
	assert sp.coord().x == 0
	assert sp.coord().y == 0

	s.untrack_pin(p)
}

fn test_page_list_resize_no_reflow_less_cols_clears_graphemes() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Add a grapheme at (9, 0).
	page.rows[0].cells[9] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`A`)
	}
	page.append_grapheme(0, 9, u32(`A`)) or { panic(err) }
	assert page.grapheme_count() == 1

	s.resize(PageResizeOpts{ cols: 5, reflow: false }) or { panic(err) }
	assert s.cols == 5
	assert s.total_rows == 10

	mut it := s.page_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for {
		chunk := it.next() or { break }
		assert chunk.node.data.grapheme_count() == 0
	}
}

fn test_page_list_resize_no_reflow_preserves_hyperlink_key_stride() ! {
	mut s := PageList.init(4, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	link := Hyperlink{
		id:  HyperlinkExplicitId{
			value: 'resize-link'
		}
		uri: 'https://example.com/resize-link'
	}
	link_id := page.insert_hyperlink(link) or { panic(err) }
	page.rows[1].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`a`)
	}
	page.set_hyperlink(1, 1, link_id) or { panic(err) }
	page.hyperlink_set.use_link(link_id)
	page.rows[1].cells[3] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`b`)
	}
	page.set_hyperlink(1, 3, link_id) or { panic(err) }

	s.resize(PageResizeOpts{ cols: 2, reflow: false }) or { panic(err) }
	shrunk_node := s.pages.first or { return }
	shrunk := &shrunk_node.data
	assert shrunk.size.cols == 2
	assert shrunk.capacity.cols == 4
	shrunk_link_id := shrunk.lookup_hyperlink_at(1, 1) or {
		assert false, 'retained hyperlink mapping was lost on shrink'
		return
	}
	assert shrunk_link_id == link_id
	assert shrunk.hyperlink_count() == 1
	assert shrunk.hyperlink_set.ref_count(link_id) == 1

	s.resize(PageResizeOpts{ cols: 4, reflow: false }) or { panic(err) }
	regrown_node := s.pages.first or { return }
	regrown := &regrown_node.data
	regrown_link_id := regrown.lookup_hyperlink_at(1, 1) or {
		assert false, 'retained hyperlink mapping was lost on regrow'
		return
	}
	assert regrown_link_id == link_id
	assert regrown.lookup_hyperlink_at(1, 3) == none
	assert regrown.rows[1].cells[3].is_zero()
	if integrity_error := regrown.verify_integrity() {
		assert false, 'resized page failed integrity: ${integrity_error}'
	}
}

fn test_page_list_resize_no_reflow_less_rows_trims_blank_lines_cursor_in_blank_line() ! {
	mut s := PageList.init(10, 5, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`A`)
	}
	for y in u16(1) .. 5 {
		page.rows[int(y)].cells[0] = CellData.from_color_payload(.bg_color_rgb, u32(0xFF) | (u32(0) << 8) | (u32(0) << 16))
	}

	// Tracked pin in a blank line.
	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 3 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ rows: 2, reflow: false }) or { panic(err) }
	assert s.rows == 2
	assert s.total_rows == 4

	// Our cursor should not move since we trimmed.
	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 0
	assert cursor.coord().y == 1

	s.untrack_pin(p)
}

fn test_page_list_resize_no_reflow_less_rows_trims_blank_lines_erases_pages() ! {
	mut s := PageList.init(100, 5, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}

	// Resize to take up two pages.
	rows := u16(int(first.data.capacity.rows) + 10)
	s.resize(PageResizeOpts{ rows: rows, reflow: false }) or { panic(err) }
	assert s.total_pages() == 2

	// Write codepoint into first line.
	mut page := &first.data
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`A`)
	}

	// Resize down. Every row except the first is blank so we should
	// erase the second page.
	s.resize(PageResizeOpts{ rows: 5, reflow: false }) or { panic(err) }
	assert s.rows == 5
	assert s.total_rows == 5
	assert s.total_pages() == 1
}

fn test_page_list_resize_no_reflow_more_cols_with_spacer_head() ! {
	mut s := PageList.init(2, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Row 0: 'x' then a spacer_head (wrapped line).
	page.rows[0].header.wrap = true
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`x`)
	}
	page.rows[0].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   0
		wide:        .spacer_head
	}
	// Row 1: wide emoji + spacer_tail.
	page.rows[1].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F600)
		wide:        .wide
	}
	page.rows[1].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   0
		wide:        .spacer_tail
	}

	s.resize(PageResizeOpts{ cols: 3, reflow: false }) or { panic(err) }
	assert s.cols == 3
	assert s.total_rows == 3

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut new_page := &np.data
	// Row 0 col 0: 'x' narrow.
	assert new_page.rows[0].cells[0].codepoint == u32(`x`)
	assert new_page.rows[0].cells[0].wide == .narrow
	// Row 0 col 1: the spacer head should now be narrow/empty.
	assert new_page.rows[0].cells[1].codepoint == 0
	assert new_page.rows[0].cells[1].wide == .narrow
	// Row 0 col 2: blank narrow.
	assert new_page.rows[0].cells[2].codepoint == 0
	assert new_page.rows[0].cells[2].wide == .narrow
}

fn test_page_list_resize_no_reflow_more_cols_forces_smaller_cap() ! {
	cap := initial_capacity(100)
	cap2 := initial_capacity(500)
	assert cap2.cols == 500
	assert cap2.rows < cap.rows

	mut s := PageList.init(cap.cols, u16(cap.rows), uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(first) == voidptr(s.pages.last or { return })
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(`A`)
			}
		}
	}

	rows := s.total_rows
	s.resize(PageResizeOpts{ cols: cap2.cols, reflow: false }) or { panic(err) }
	assert s.total_rows == rows

	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for {
		row := it.next() or { break }
		mut rp := &row.node.data
		assert rp.size.cols == cap2.cols
		assert rp.rows[int(row.y)].cells[0].codepoint == u32(`A`)
	}
}

fn test_page_list_resize_no_reflow_more_cols_forces_less_rows_per_page() ! {
	cols := u16(5)
	rows := u16(150)
	initial := std_capacity.adjust(PageCapacityAdjustment{ cols: cols }) or { panic(err) }
	assert initial.rows >= rows

	mut s := PageList.init(cols, rows, uint(0))!
	defer { s.deinit() }

	mut new_cols := u16(50)
	mut adjusted := std_capacity.adjust(PageCapacityAdjustment{ cols: new_cols }) or { panic(err) }
	for adjusted.rows >= rows {
		new_cols += 50
		adjusted = std_capacity.adjust(PageCapacityAdjustment{ cols: new_cols }) or { panic(err) }
	}
	s.resize(PageResizeOpts{ cols: new_cols, reflow: false }) or { panic(err) }
	assert s.cols == new_cols
	assert s.total_rows == uint(rows)
	assert_all_but_last_page_full(&s)

	first := s.pages.first or { return }
	assert first.data.size.rows == first.data.capacity.rows
	new_cols = first.data.size.cols + 50
	adjusted = std_capacity.adjust(PageCapacityAdjustment{ cols: new_cols }) or { panic(err) }
	for adjusted.rows >= first.data.size.rows {
		new_cols += 50
		adjusted = std_capacity.adjust(PageCapacityAdjustment{ cols: new_cols }) or { panic(err) }
	}
	s.resize(PageResizeOpts{ cols: new_cols, reflow: false }) or { panic(err) }
	assert s.cols == new_cols
	assert s.total_rows == uint(rows)
	assert_all_but_last_page_full(&s)
}

fn assert_all_but_last_page_full(s &PageList) {
	mut node := s.pages.first
	for {
		page := node or { break }
		if voidptr(page) == voidptr(s.pages.last or { break }) {
			break
		}
		assert page.data.size.rows == page.data.capacity.rows
		node = page.next
	}
}

fn test_page_list_resize_no_reflow_more_cols_remaps_pins_in_backfill_path() ! {
	cols := u16(5)
	cap := initial_capacity(cols)
	mut s := PageList.init(cols, cap.rows, none)!
	defer { s.deinit() }

	// Grow until we have two pages.
	for voidptr(s.pages.first or { return }) == voidptr(s.pages.last or { return }) {
		_ = s.grow()!
	}
	first_page := s.pages.first or { return }
	second_page := s.pages.last or { return }
	assert voidptr(first_page) != voidptr(second_page)

	// Trim a history row so the first page has spare capacity. This triggers
	// the backfill path in resize_without_reflow_grow_cols.
	s.erase_rows(Point.new(.history, Coordinate{}), Point.new(.history, Coordinate{ y: 0 }))
	assert first_page.data.size.rows < first_page.data.capacity.rows

	// Ensure the resize takes the slow path (new capacity > current capacity).
	new_cols := cols + 1
	adjusted := second_page.data.capacity.adjust(PageCapacityAdjustment{ cols: new_cols }) or {
		panic(err)
	}
	assert second_page.data.capacity.cols < adjusted.cols

	// Track row zero of the second page. Backfill copies this row into the
	// first page, so the tracked pin must move before the old page is destroyed.
	tracked := s.track_pin(Pin{
		node: second_page
		x:    0
		y:    0
	})!
	marker := u32(`X`)
	mut rac := tracked.row_and_cell()
	rac.cell.content_tag = .codepoint
	rac.cell.codepoint = marker

	s.resize(PageResizeOpts{ cols: new_cols, reflow: false }) or { panic(err) }

	mut found := false
	mut node := s.pages.first
	for {
		current := node or { break }
		if voidptr(current) == voidptr(tracked.node) {
			found = true
			break
		}
		node = current.next
	}
	assert found
	assert tracked.y < tracked.node.data.size.rows
	cell := tracked.row_and_cell().cell
	assert cell.content_tag == .codepoint
	assert cell.codepoint == marker

	s.untrack_pin(tracked)
}

fn test_page_list_resize_no_reflow_more_rows_adds_blank_rows_if_cursor_at_bottom() ! {
	mut s := PageList.init(5, 3, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow to 5 total rows (3 active + 2 scrollback).
	s.grow_rows(2)!
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(first) == voidptr(s.pages.last or { return })
	mut page := &first.data
	for y in 0 .. int(s.total_rows) {
		page.rows[y].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(y)
		}
	}

	// Active should be on row 3 (screen y=2).
	pc0 := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert pc0.screen_point().coord().y == 2

	// Tracked pin at cursor position (near bottom of active).
	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: u16(s.rows - 2) })) or {
		assert false, 'get_pin failed'
		return
	})!
	original_cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}

	// Resize with cursor preserved.
	s.resize(PageResizeOpts{
		rows:   10
		reflow: false
		cursor: PageResizeCursor{
			x: 0
			y: u16(s.rows - 2)
		}
	}) or { panic(err) }
	assert s.cols == 5
	assert s.rows == 10

	// Our cursor should not change.
	new_cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert new_cursor.coord().x == original_cursor.coord().x
	assert new_cursor.coord().y == original_cursor.coord().y

	// 12 = 10 active + 2 scrollback preserved by the cursor.
	assert s.total_rows == 12

	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert pc.screen_point().coord().y == 2

	s.untrack_pin(p)
}

// ============================================================
// resize reflow tests
// ============================================================

fn test_page_list_resize_reflow_more_cols_no_wrapped_rows() ! {
	mut s := PageList.init(5, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(`A`)
			}
		}
	}

	s.resize(PageResizeOpts{ cols: 10, reflow: true }) or { panic(err) }
	assert s.cols == 10
	assert s.total_rows == 3

	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for {
		row := it.next() or { break }
		mut rp := &row.node.data
		assert rp.size.cols == 10
		assert rp.rows[int(row.y)].cells[0].codepoint == u32(`A`)
	}
}

fn test_page_list_resize_reflow_more_cols_wrapped_rows() ! {
	mut s := PageList.init(2, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		if y % 2 == 0 {
			page.rows[y].header.wrap = true
		} else {
			page.rows[y].header.wrap_continuation = true
		}
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(`A`)
			}
		}
	}

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 4

	// Active should still be on top.
	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	sp := pc.screen_point()
	assert sp.coord().x == 0
	assert sp.coord().y == 0

	// First row should be unwrapped and hold the reflowed content.
	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	row := it.next() or {
		assert false, 'no row'
		return
	}
	mut rp := &row.node.data
	rd := rp.rows[int(row.y)]
	assert !rd.header.wrap
	assert rp.size.cols == 4
	assert rd.cells[0].codepoint == u32(`A`)
	assert rd.cells[2].codepoint == u32(`A`)
}

fn test_page_list_resize_reflow_invalidates_viewport_offset_cache() ! {
	mut s := PageList.init(2, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	s.grow_rows(20)!

	last := s.pages.last or {
		assert false, 'no last page'
		return
	}
	mut page := &last.data
	for y in 0 .. int(s.rows) {
		if y % 2 == 0 {
			page.rows[y].header.wrap = true
		} else {
			page.rows[y].header.wrap_continuation = true
		}
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(`A`)
			}
		}
	}

	// Scroll to a pinned viewport in history.
	pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 10 })) or {
		assert false, 'get_pin failed'
		return
	}
	s.scroll(PageScrollPin{ pin: pin })
	assert s.viewport == .pin
	sb1 := s.scrollbar()
	assert sb1.total == s.total_rows
	assert sb1.offset == 10
	assert sb1.len == uint(s.rows)

	// Resize with reflow - unwrapping rows changes total_rows.
	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4

	// Verify the scrollbar cache was invalidated during reflow.
	sb2 := s.scrollbar()
	assert sb2.total == s.total_rows
	assert sb2.offset == 5
	assert sb2.len == uint(s.rows)
}

fn test_page_list_resize_reflow_more_cols_creates_multiple_pages() ! {
	// Find a wide col count whose capacity has < 100 rows.
	mut current := u16(100)
	mut cap := initial_capacity(current)
	for cap.rows >= 100 {
		current += 100
		cap = initial_capacity(current)
	}

	mut s := PageList.init(cap.cols, u16(cap.rows), uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(first) == voidptr(s.pages.last or { return })
	mut page := &first.data
	// Wrap every other row so every line is wrapped for reflow.
	for y in 0 .. int(s.rows) {
		if y % 2 == 0 {
			page.rows[y].header.wrap = true
		} else {
			page.rows[y].header.wrap_continuation = true
		}
		page.rows[y].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`A`)
		}
	}

	newcap := initial_capacity(cap.cols + 100)
	assert newcap.rows < cap.rows
	s.resize(PageResizeOpts{ cols: newcap.cols, reflow: true }) or { panic(err) }
	assert s.cols == newcap.cols
	assert s.total_rows == cap.rows

	mut count := 0
	mut it := s.pages.first
	for {
		p := it or { break }
		count += 1
		assert p.data.capacity.cols == newcap.cols
		assert p.data.capacity.rows == newcap.rows
		it = p.next
	}
	// We should have created at least one additional page.
	assert count > 1
}

fn test_page_list_resize_reflow_more_cols_wrap_across_page_boundary() ! {
	mut s := PageList.init(2, 10, uint(0))!
	defer { s.deinit() }
	grow_page_list_to_second_page(mut s, 1)

	mut first := s.pages.first or { return }
	y0 := int(first.data.size.rows) - 1
	first.data.rows[y0].header.wrap = true
	for x in 0 .. int(s.cols) {
		first.data.rows[y0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	mut last := s.pages.last or { return }
	last.data.rows[0].header.wrap_continuation = true
	for x in 0 .. int(s.cols) {
		last.data.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	end_rows := s.total_rows - 1

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == end_rows
	p8 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 8 })) or { return }
	assert !p8.row_data().header.wrap
	assert !p8.row_data().header.wrap_continuation
	for cell in p8.row_data().cells[..4] {
		assert !cell.has_text()
	}
	p9 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 9 })) or { return }
	assert !p9.row_data().header.wrap
	assert !p9.row_data().header.wrap_continuation
	assert p9.row_data().cells[0].codepoint == 0
	assert p9.row_data().cells[1].codepoint == 1
	assert p9.row_data().cells[2].codepoint == 0
	assert p9.row_data().cells[3].codepoint == 1
}

fn test_page_list_resize_reflow_more_cols_wrap_across_page_boundary_cursor_in_second_page() ! {
	mut s := PageList.init(2, 10, uint(0))!
	defer { s.deinit() }
	grow_page_list_to_second_page(mut s, 1)

	mut first := s.pages.first or { return }
	y0 := int(first.data.size.rows) - 1
	first.data.rows[y0].header.wrap = true
	for x in 0 .. int(s.cols) {
		first.data.rows[y0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	mut last := s.pages.last or { return }
	last.data.rows[0].header.wrap_continuation = true
	for x in 0 .. int(s.cols) {
		last.data.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	tracked := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 1, y: 9 })) or { return })!
	assert voidptr(tracked.node) == voidptr(last)
	end_rows := s.total_rows - 1

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == end_rows
	point := s.point_from_pin(.active, *tracked) or { return }
	assert point == Point.new(.active, Coordinate{ x: 3, y: 9 })
	p9 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 9 })) or { return }
	assert !p9.row_data().header.wrap
	assert p9.row_data().cells[0].codepoint == 0
	assert p9.row_data().cells[1].codepoint == 1
	assert p9.row_data().cells[2].codepoint == 0
	assert p9.row_data().cells[3].codepoint == 1
	s.untrack_pin(tracked)
}

fn test_page_list_resize_reflow_less_cols_wrap_across_page_boundary_cursor_in_second_page() ! {
	mut s := PageList.init(5, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	grow_page_list_to_second_page(mut s, 5)

	mut first := s.pages.first or { return }
	y0 := int(first.data.size.rows) - 1
	first.data.rows[y0].header.wrap = true
	for x in 0 .. int(s.cols) {
		first.data.rows[y0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	mut last := s.pages.last or { return }
	last.data.rows[0].header.wrap_continuation = true
	for x in 0 .. int(s.cols) {
		last.data.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	tracked := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 2, y: 5 })) or { return })!
	assert voidptr(tracked.node) == voidptr(last)
	assert tracked.y == 0

	s.resize(PageResizeOpts{
		cols:   4
		reflow: true
		cursor: PageResizeCursor{ x: 2, y: 5 }
	}) or { panic(err) }
	assert s.cols == 4
	point := s.point_from_pin(.active, *tracked) or { return }
	assert point == Point.new(.active, Coordinate{ x: 3, y: 5 })
	p3 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 3 })) or { return }
	assert !p3.row_data().header.wrap
	assert !p3.row_data().header.wrap_continuation
	p4 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 4 })) or { return }
	assert p4.row_data().header.wrap
	assert !p4.row_data().header.wrap_continuation
	assert p4.row_data().cells[0].codepoint == 0
	assert p4.row_data().cells[1].codepoint == 1
	assert p4.row_data().cells[2].codepoint == 2
	assert p4.row_data().cells[3].codepoint == 3
	p5 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 5 })) or { return }
	assert p5.row_data().header.wrap
	assert p5.row_data().header.wrap_continuation
	assert p5.row_data().cells[0].codepoint == 4
	assert p5.row_data().cells[1].codepoint == 0
	assert p5.row_data().cells[2].codepoint == 1
	assert p5.row_data().cells[3].codepoint == 2
	p6 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 6 })) or { return }
	assert !p6.row_data().header.wrap
	assert p6.row_data().header.wrap_continuation
	assert p6.row_data().cells[0].codepoint == 3
	assert p6.row_data().cells[1].codepoint == 4
	s.untrack_pin(tracked)
}

fn test_page_list_resize_grow_cols_with_unwrap_fixes_viewport_pin() ! {
	// Regression: after resize/reflow, the viewport pin can end up where
	// pin.y + rows > total_rows, causing get_bottom_right to fail.
	mut s := PageList.init(2, 10, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	s.grow_rows(30)!
	assert s.total_rows == 40

	// Fill all rows with wrapped content.
	mut pit := s.page_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for {
		chunk := pit.next() or { break }
		mut page := &chunk.node.data
		for y in int(chunk.start) .. int(chunk.end) {
			if y % 2 == 0 {
				page.rows[y].header.wrap = true
			} else {
				page.rows[y].header.wrap_continuation = true
			}
			for x in 0 .. int(s.cols) {
				page.rows[y].cells[x] = CellData{
					content_tag: .codepoint
					codepoint:   u32(`A`)
				}
			}
		}
	}

	// Pin viewport at row 28 (in history).
	pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: 28 })) or {
		assert false, 'get_pin failed'
		return
	}
	s.scroll(PageScrollPin{ pin: pin })
	assert s.viewport == .pin
	if _ := s.get_bottom_right(.viewport) {
		// ok
	} else {
		assert false, 'get_bottom_right returned none before resize'
	}

	// Resize with reflow: unwraps rows, reducing total_rows.
	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows < 40

	// Used to fail here; test that we can still get the bottom right.
	if _ := s.get_bottom_right(.viewport) {
		// ok
	} else {
		assert false, 'get_bottom_right returned none after resize'
	}
}

fn test_page_list_resize_reflow_more_cols_cursor_in_wrapped_row() ! {
	mut s := PageList.init(2, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	// Row 0: wrapped.
	page.rows[0].header.wrap = true
	for x in 0 .. int(s.cols) {
		page.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	// Row 1: wrap continuation.
	page.rows[1].header.wrap_continuation = true
	for x in 0 .. int(s.cols) {
		page.rows[1].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 1, y: 1 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 4

	// Cursor should move to the first row (unwrapped).
	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 3
	assert cursor.coord().y == 0

	s.untrack_pin(p)
}

fn test_page_list_resize_reflow_more_cols_cursor_in_not_wrapped_row() ! {
	mut s := PageList.init(2, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[0].header.wrap = true
	for x in 0 .. int(s.cols) {
		page.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	page.rows[1].header.wrap_continuation = true
	for x in 0 .. int(s.cols) {
		page.rows[1].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 1, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 4

	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 1
	assert cursor.coord().y == 0

	s.untrack_pin(p)
}

fn test_page_list_resize_reflow_more_cols_cursor_in_wrapped_row_that_isnt_unwrapped() ! {
	mut s := PageList.init(2, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	// Row 0: wrap.
	page.rows[0].header.wrap = true
	for x in 0 .. int(s.cols) {
		page.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	// Row 1: wrap + wrap_continuation.
	page.rows[1].header.wrap = true
	page.rows[1].header.wrap_continuation = true
	for x in 0 .. int(s.cols) {
		page.rows[1].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}
	// Row 2: wrap_continuation.
	page.rows[2].header.wrap_continuation = true
	for x in 0 .. int(s.cols) {
		page.rows[2].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 1, y: 2 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 4

	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 1
	assert cursor.coord().y == 1

	s.untrack_pin(p)
}

fn test_page_list_resize_reflow_more_cols_no_reflow_preserves_semantic_prompt() ! {
	mut s := PageList.init(2, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[1].header.semantic_prompt = .prompt

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 4

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(np) == voidptr(s.pages.last or { return })
	mut new_page := &np.data
	assert new_page.rows[1].header.semantic_prompt == .prompt
}

fn test_page_list_resize_reflow_less_cols_no_reflow_preserves_semantic_prompt() ! {
	mut s := PageList.init(4, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[1].header.semantic_prompt = .prompt
	for x in 0 .. int(s.cols) {
		page.rows[1].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 4

	assert voidptr(s.pages.first or { return }) == voidptr(s.pages.last or { return })

	p1 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 1 })) or {
		assert false, 'get_pin failed'
		return
	}
	assert p1.row_data().header.wrap
	assert p1.row_data().header.semantic_prompt == .prompt

	p2 := s.pin(Point.new(.active, Coordinate{ x: 0, y: 2 })) or {
		assert false, 'get_pin failed'
		return
	}
	assert p2.row_data().header.semantic_prompt == .prompt
}

fn test_page_list_resize_reflow_less_cols_no_reflow_preserves_semantic_prompt_on_first_line() ! {
	mut s := PageList.init(4, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[0].header.semantic_prompt = .prompt

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 4

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(np) == voidptr(s.pages.last or { return })
	mut new_page := &np.data
	assert new_page.rows[0].header.semantic_prompt == .prompt
}

fn test_page_list_resize_reflow_less_cols_wrap_preserves_semantic_prompt() ! {
	mut s := PageList.init(4, 4, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[0].header.semantic_prompt = .prompt

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 4

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(np) == voidptr(s.pages.last or { return })
	mut new_page := &np.data
	assert new_page.rows[0].header.semantic_prompt == .prompt
}

fn test_page_list_resize_reflow_less_cols_no_wrapped_rows() ! {
	mut s := PageList.init(10, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. 4 {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	s.resize(PageResizeOpts{ cols: 5, reflow: true }) or { panic(err) }
	assert s.cols == 5
	assert s.total_rows == 3

	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for {
		row := it.next() or { break }
		mut rp := &row.node.data
		assert rp.size.cols == 5
		for x in 0 .. 4 {
			assert rp.rows[int(row.y)].cells[x].codepoint == u32(x)
		}
	}
}

fn test_page_list_resize_reflow_less_cols_wrapped_rows() ! {
	mut s := PageList.init(4, 2, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 4

	// Active moves due to scrollback.
	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert pc.screen_point().coord().y == 2

	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	// Row 0: wrapped, cells[0]=0.
	r0 := it.next() or {
		assert false, 'no row'
		return
	}
	assert r0.row_data().header.wrap
	assert r0.node.data.rows[int(r0.y)].cells[0].codepoint == 0
	// Row 1: not wrapped, cells[0]=2.
	r1 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r1.row_data().header.wrap
	assert r1.node.data.rows[int(r1.y)].cells[0].codepoint == 2
	// Row 2: wrapped, cells[0]=0.
	r2 := it.next() or {
		assert false, 'no row'
		return
	}
	assert r2.row_data().header.wrap
	assert r2.node.data.rows[int(r2.y)].cells[0].codepoint == 0
	// Row 3: not wrapped, cells[0]=2.
	r3 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r3.row_data().header.wrap
	assert r3.node.data.rows[int(r3.y)].cells[0].codepoint == 2
}

fn test_page_list_resize_reflow_preserves_hyperlink_mapping() ! {
	mut s := PageList.init(4, 2, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[0].cells[3] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`L`)
	}
	source_id := page.insert_hyperlink(Hyperlink{
		id:  HyperlinkExplicitId{
			value: 'link-id'
		}
		uri: 'https://example.com/reflow'
	}) or { panic(err) }
	page.set_hyperlink(0, 3, source_id) or { panic(err) }

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }

	mut found := false
	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for {
		pin := it.next() or { break }
		mut reflowed := &pin.node.data
		for x, cell in reflowed.rows[int(pin.y)].cells[..int(reflowed.size.cols)] {
			if cell.codepoint != u32(`L`) {
				continue
			}
			assert cell.has_hyperlink
			id := reflowed.lookup_hyperlink_at(uint(pin.y), uint(x)) or {
				assert false, 'reflowed hyperlink mapping missing'
				return
			}
			link := reflowed.hyperlink_set.get(id)
			assert link.uri == 'https://example.com/reflow'
			match link.id {
				HyperlinkExplicitId {
					assert link.id.value == 'link-id'
				}
				HyperlinkImplicitId {
					assert false
				}
			}
			found = true
		}
	}
	assert found
}

fn test_page_list_resize_reflow_preserves_hyperlinks_across_source_pages() ! {
	mut s := PageList.init(2, 4, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	s.split(Pin{ node: first, y: 2, x: 0 }) or {
		assert false, 'split failed'
		return
	}
	second := first.next or {
		assert false, 'no second page'
		return
	}

	mut first_page := &first.data
	first_page.rows[1].header.wrap = true
	first_page.rows[1].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`A`)
	}
	first_id := first_page.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{
			offset: 1
		}
		uri: 'https://example.com/first'
	}) or { panic(err) }
	first_page.set_hyperlink(1, 1, first_id) or { panic(err) }

	mut second_page := &second.data
	second_page.rows[0].header.wrap_continuation = true
	second_page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`B`)
	}
	second_id := second_page.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{
			offset: 2
		}
		uri: 'https://example.com/second'
	}) or { panic(err) }
	second_page.set_hyperlink(0, 0, second_id) or { panic(err) }

	// The wrapped logical line crosses the old page boundary and is unwrapped
	// into one destination row.
	s.resize(PageResizeOpts{ cols: 3, reflow: true }) or { panic(err) }

	mut found := map[u32]string{}
	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	for {
		pin := it.next() or { break }
		mut reflowed := &pin.node.data
		for x, cell in reflowed.rows[int(pin.y)].cells[..int(reflowed.size.cols)] {
			if cell.codepoint != u32(`A`) && cell.codepoint != u32(`B`) {
				continue
			}
			id := reflowed.lookup_hyperlink_at(uint(pin.y), uint(x)) or {
				assert false, 'reflowed hyperlink mapping missing'
				return
			}
			found[cell.codepoint] = reflowed.hyperlink_set.get(id).uri
		}
	}
	assert found[u32(`A`)] == 'https://example.com/first'
	assert found[u32(`B`)] == 'https://example.com/second'
}

fn test_page_list_resize_reflow_exceeds_hyperlink_memory_forcing_capacity_increase() ! {
	mut s := PageList.init(2, 10, uint(0))!
	defer { s.deinit() }
	grow_page_list_to_second_page(mut s, 1)
	uri := 'a'.repeat(int(string_bytes_default) - 1)

	mut first := s.pages.first or { return }
	mut page0 := &first.data
	y0 := uint(page0.size.rows) - 1
	x0 := uint(page0.size.cols) - 1
	first_id := page0.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{ offset: 0 }
		uri: uri
	}) or { panic(err) }
	page0.rows[y0].header.wrap = true
	page0.rows[y0].cells[x0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`X`)
	}
	page0.set_hyperlink(y0, x0, first_id) or { panic(err) }
	mut first_error := ''
	_ := page0.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{ offset: 1 }
		uri: 'AAAAAAAAAAAAAAAAAAAAAAAAAA'
	}) or {
		first_error = err.msg()
		u32(0)
	}
	assert first_error == 'strings out of memory'

	mut last := s.pages.last or { return }
	mut page1 := &last.data
	second_id := page1.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{ offset: 1 }
		uri: uri
	}) or { panic(err) }
	page1.rows[0].header.wrap_continuation = true
	page1.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`X`)
	}
	page1.set_hyperlink(0, 0, second_id) or { panic(err) }
	mut second_error := ''
	_ := page1.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{ offset: 2 }
		uri: 'AAAAAAAAAAAAAAAAAAAAAAAAAA'
	}) or {
		second_error = err.msg()
		u32(0)
	}
	assert second_error == 'strings out of memory'

	s.resize(PageResizeOpts{ cols: s.cols + 1, reflow: true }) or { panic(err) }
	assert s.cols == 3
}

fn test_page_list_resize_reflow_exceeds_style_memory_forcing_capacity_increase() ! {
	mut s := PageList.init(std_capacity.styles - 1, 10, uint(0))!
	defer { s.deinit() }
	grow_page_list_to_second_page(mut s, 1)

	mut first := s.pages.first or { return }
	mut page0 := &first.data
	y0 := int(page0.size.rows) - 1
	page0.rows[y0].header.wrap = true
	page0.rows[y0].header.styled = true
	for x in 0 .. int(s.cols) {
		style := CellStyle{
			bg_color: StyleColorRgb{
				rgb: RGB{
					r: u8(x)
					g: u8(x >> 8)
					b: u8(x >> 16)
				}
			}
		}
		id := page0.styles.add(style) or { break }
		page0.rows[y0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`X`)
			style_id:    id
		}
	}

	mut last := s.pages.last or { return }
	mut page1 := &last.data
	page1.rows[0].header.wrap_continuation = true
	page1.rows[0].header.styled = true
	for x in 0 .. int(s.cols) {
		style := CellStyle{
			fg_color: StyleColorRgb{
				rgb: RGB{
					r: u8(x)
					g: u8(x >> 8)
					b: u8(x >> 16)
				}
			}
		}
		id := page1.styles.add(style) or { break }
		page1.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`X`)
			style_id:    id
		}
	}

	s.resize(PageResizeOpts{ cols: s.cols * 2, reflow: true }) or { panic(err) }
	assert s.cols == (std_capacity.styles - 1) * 2
}

fn test_page_list_resize_reflow_less_cols_cursor_in_wrapped_row() ! {
	mut s := PageList.init(4, 2, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 2, y: 1 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 4

	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 0
	assert cursor.coord().y == 1

	s.untrack_pin(p)
}

fn reflow_cursor_cell_helper(init_cols u16, new_cols u16, pin_x u16, exp_x u32, exp_y u32) ! {
	mut s := PageList.init(init_cols, 2, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or { return }
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. 2 {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: pin_x, y: 0 })) or { return })!

	s.resize(PageResizeOpts{ cols: new_cols, reflow: true }) or { panic(err) }
	assert s.cols == new_cols
	assert s.total_rows == 2

	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == exp_x
	assert cursor.coord().y == exp_y

	s.untrack_pin(p)
}

fn test_page_list_resize_reflow_less_cols_cursor_in_unchanged_row() ! {
	reflow_cursor_cell_helper(4, 2, 1, 1, 0)!
}

fn test_page_list_resize_reflow_less_cols_cursor_in_blank_cell() ! {
	reflow_cursor_cell_helper(6, 4, 2, 2, 0)!
}

fn test_page_list_resize_reflow_less_cols_cursor_in_final_blank_cell() ! {
	reflow_cursor_cell_helper(6, 4, 3, 3, 0)!
}

fn test_page_list_resize_reflow_less_cols_cursor_in_wrapped_blank_cell() ! {
	reflow_cursor_cell_helper(6, 4, 5, 3, 0)!
}

fn test_page_list_resize_reflow_less_cols_blank_lines() ! {
	mut s := PageList.init(4, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for x in 0 .. 4 {
		page.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 3

	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	r0 := it.next() or {
		assert false, 'no row'
		return
	}
	assert r0.row_data().header.wrap
	assert r0.node.data.rows[int(r0.y)].cells[0].codepoint == 0
	r1 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r1.row_data().header.wrap
	assert r1.node.data.rows[int(r1.y)].cells[0].codepoint == 2
}

fn test_page_list_resize_reflow_less_cols_wrapped_rows_with_graphemes() ! {
	mut s := PageList.init(4, 2, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
		page.append_grapheme(y, 2, u32(`A`)) or { panic(err) }
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 4

	pc := s.get_cell(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_cell failed'
		return
	}
	assert pc.screen_point().coord().y == 2

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(np) == voidptr(s.pages.last or { return })

	mut it := s.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	// Row 0: wrapped, cells[0]=0.
	r0 := it.next() or {
		assert false, 'no row'
		return
	}
	assert r0.row_data().header.wrap
	assert r0.node.data.rows[int(r0.y)].cells[0].codepoint == 0
	// Row 1: not wrapped, has grapheme, cells[0]=2.
	r1 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r1.row_data().header.wrap
	assert r1.row_data().header.grapheme
	assert r1.node.data.rows[int(r1.y)].cells[0].codepoint == 2
	cps := r1.node.data.lookup_grapheme_at(uint(r1.y), 0) or {
		assert false, 'lookup_grapheme failed'
		return
	}
	assert cps.len == 1
	assert cps[0] == u32(`A`)
}

fn test_page_list_resize_reflow_less_cols_cursor_goes_to_scrollback() ! {
	mut s := PageList.init(4, 2, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. int(s.cols) {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 2, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 4

	// Our cursor should now be in scrollback (outside active).
	if _ := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) {
		assert false, 'expected pin outside active'
	}

	s.untrack_pin(p)
}

fn test_page_list_resize_reflow_less_cols_copy_style() ! {
	mut s := PageList.init(4, 2, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	style_id := page.styles.add(CellStyle{
		flags: StyleFlags.init(true, false, false, false, false, false, false, false, .none)
	}) or {
		assert false, 'style add failed'
		return
	}
	for x in 0 .. int(s.cols) - 1 {
		page.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
			style_id:    style_id
		}
		page.rows[0].header.styled = true
		page.styles.use_style(style_id)
	}
	page.styles.release(style_id)

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 2

	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	for {
		row := it.next() or { break }
		mut rp := &row.node.data
		rd := rp.rows[int(row.y)]
		for x in 0 .. int(s.cols) - 1 {
			c := rd.cells[x]
			assert c.style_id != 0
			st := rp.styles.get(c.style_id)
			assert st.flags.bold()
			assert rd.header.styled
		}
	}
}

fn test_page_list_resize_reflow_less_cols_to_eliminate_a_wide_char() ! {
	mut s := PageList.init(2, 1, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F600)
		wide:        .wide
	}
	page.rows[0].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   0
		wide:        .spacer_tail
	}

	s.resize(PageResizeOpts{ cols: 1, reflow: true }) or { panic(err) }
	assert s.cols == 1
	assert s.total_rows == 1

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(np) == voidptr(s.pages.last or { return })
	mut new_page := &np.data
	assert new_page.rows[0].cells[0].codepoint == 0
	assert new_page.rows[0].cells[0].wide == .narrow
}

fn test_page_list_resize_reflow_less_cols_to_wrap_a_wide_char() ! {
	mut s := PageList.init(3, 1, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`x`)
	}
	page.rows[0].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F600)
		wide:        .wide
	}
	page.rows[0].cells[2] = CellData{
		content_tag: .codepoint
		codepoint:   0
		wide:        .spacer_tail
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 2

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(np) == voidptr(s.pages.last or { return })
	mut new_page := &np.data
	// Row 0: 'x' narrow, wrapped, then spacer head.
	assert new_page.rows[0].cells[0].codepoint == u32(`x`)
	assert new_page.rows[0].cells[0].wide == .narrow
	assert new_page.rows[0].header.wrap
	assert new_page.rows[0].cells[1].codepoint == 0
	assert new_page.rows[0].cells[1].wide == .spacer_head
	// Row 1: wide emoji + spacer tail.
	assert new_page.rows[1].cells[0].codepoint == u32(0x1F600)
	assert new_page.rows[1].cells[0].wide == .wide
	assert new_page.rows[1].cells[1].codepoint == 0
	assert new_page.rows[1].cells[1].wide == .spacer_tail
}

fn test_page_list_resize_reflow_less_cols_to_wrap_a_multicodepoint_grapheme_with_a_spacer_head() ! {
	mut s := PageList.init(4, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or { return }
	mut page := &first.data
	graphemes := [u32(0x200D), u32(0x1F468), u32(0x200D), u32(0x1F466), u32(0x200D), u32(0x1F466)]
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F468)
		wide:        .wide
	}
	page.set_graphemes(0, 0, graphemes) or { panic(err) }
	page.rows[0].cells[1] = CellData{
		content_tag: .codepoint
		wide:        .spacer_tail
	}
	page.rows[0].cells[2] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F468)
		wide:        .wide
	}
	page.set_graphemes(0, 2, graphemes) or { panic(err) }
	page.rows[0].cells[3] = CellData{
		content_tag: .codepoint
		wide:        .spacer_tail
	}

	s.resize(PageResizeOpts{ cols: 3, reflow: true }) or { panic(err) }
	assert s.cols == 3
	assert s.total_rows == 2
	new_node := s.pages.first or { return }
	assert voidptr(new_node) == voidptr(s.pages.last or { return })
	mut new_page := &new_node.data
	assert new_page.rows[0].cells[0].codepoint == u32(0x1F468)
	assert new_page.rows[0].cells[0].wide == .wide
	assert new_page.rows[0].header.wrap
	assert new_page.rows[0].cells[1].wide == .spacer_tail
	assert new_page.rows[0].cells[2].wide == .spacer_head
	first_cps := new_page.lookup_grapheme_at(0, 0) or {
		assert false, 'first grapheme missing'
		return
	}
	assert first_cps == graphemes
	assert new_page.rows[1].cells[0].codepoint == u32(0x1F468)
	assert new_page.rows[1].cells[0].wide == .wide
	assert new_page.rows[1].cells[1].wide == .spacer_tail
	second_cps := new_page.lookup_grapheme_at(1, 0) or {
		assert false, 'second grapheme missing'
		return
	}
	assert second_cps == graphemes
}

fn test_page_list_resize_reflow_more_cols_unwrap_wide_spacer_head() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }
	mut node := s.pages.first or { return }
	mut page := &node.data
	page.rows[0].header.wrap = true
	page.rows[0].cells[0] = CellData{ content_tag: .codepoint, codepoint: u32(`x`) }
	page.rows[0].cells[1] = CellData{ content_tag: .codepoint, wide: .spacer_head }
	page.rows[1].header.wrap_continuation = true
	page.rows[1].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F600)
		wide:        .wide
	}
	page.rows[1].cells[1] = CellData{ content_tag: .codepoint, wide: .spacer_tail }

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 2
	new_node := s.pages.first or { return }
	assert voidptr(new_node) == voidptr(s.pages.last or { return })
	new_page := &new_node.data
	assert new_page.rows[0].cells[0].codepoint == u32(`x`)
	assert new_page.rows[0].cells[0].wide == .narrow
	assert !new_page.rows[0].header.wrap
	assert new_page.rows[0].cells[1].codepoint == u32(0x1F600)
	assert new_page.rows[0].cells[1].wide == .wide
	assert new_page.rows[0].cells[2].wide == .spacer_tail
}

fn test_page_list_resize_reflow_more_cols_unwrap_wide_spacer_head_across_two_rows() ! {
	mut s := PageList.init(2, 3, uint(0))!
	defer { s.deinit() }
	mut node := s.pages.first or { return }
	mut page := &node.data
	page.rows[0].header.wrap = true
	page.rows[0].cells[0] = CellData{ content_tag: .codepoint, codepoint: u32(`x`) }
	page.rows[0].cells[1] = CellData{ content_tag: .codepoint, codepoint: u32(`x`) }
	page.rows[1].header.wrap_continuation = true
	page.rows[1].header.wrap = true
	page.rows[1].cells[0] = CellData{ content_tag: .codepoint, codepoint: u32(`x`) }
	page.rows[1].cells[1] = CellData{ content_tag: .codepoint, wide: .spacer_head }
	page.rows[2].header.wrap_continuation = true
	page.rows[2].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F600)
		wide:        .wide
	}
	page.rows[2].cells[1] = CellData{ content_tag: .codepoint, wide: .spacer_tail }

	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 3
	new_page := &(s.pages.first or { return }).data
	assert new_page.rows[0].header.wrap
	assert new_page.rows[0].cells[0].codepoint == u32(`x`)
	assert new_page.rows[0].cells[1].codepoint == u32(`x`)
	assert new_page.rows[0].cells[2].codepoint == u32(`x`)
	assert new_page.rows[0].cells[3].wide == .spacer_head
	assert new_page.rows[1].cells[0].codepoint == u32(0x1F600)
	assert new_page.rows[1].cells[0].wide == .wide
	assert new_page.rows[1].cells[1].wide == .spacer_tail
}

fn test_page_list_resize_reflow_more_cols_unwrap_still_requires_wide_spacer_head() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }
	mut node := s.pages.first or { return }
	mut page := &node.data
	page.rows[0].header.wrap = true
	page.rows[0].cells[0] = CellData{ content_tag: .codepoint, codepoint: u32(`x`) }
	page.rows[0].cells[1] = CellData{ content_tag: .codepoint, codepoint: u32(`x`) }
	page.rows[1].header.wrap_continuation = true
	page.rows[1].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F600)
		wide:        .wide
	}
	page.rows[1].cells[1] = CellData{ content_tag: .codepoint, wide: .spacer_tail }

	s.resize(PageResizeOpts{ cols: 3, reflow: true }) or { panic(err) }
	assert s.cols == 3
	assert s.total_rows == 2
	new_page := &(s.pages.first or { return }).data
	assert new_page.rows[0].header.wrap
	assert new_page.rows[0].cells[0].codepoint == u32(`x`)
	assert new_page.rows[0].cells[1].codepoint == u32(`x`)
	assert new_page.rows[0].cells[2].wide == .spacer_head
	assert new_page.rows[1].cells[0].codepoint == u32(0x1F600)
	assert new_page.rows[1].cells[0].wide == .wide
	assert new_page.rows[1].cells[1].wide == .spacer_tail
}

fn test_page_list_resize_reflow_less_cols_copy_kitty_placeholder() ! {
	mut s := PageList.init(4, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or { return }
	for x in u16(0) .. s.cols - 1 {
		set_screen_semantic_cell(mut s, x, 0, kitty_unicode_placeholder, .output)
	}
	first.data.rows[0].header.kitty_virtual_placeholder = true

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 2
	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	for {
		row := it.next() or { break }
		assert row.row_data().header.kitty_virtual_placeholder
	}
}

fn test_page_list_resize_reflow_more_cols_clears_kitty_placeholder() ! {
	mut s := PageList.init(4, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or { return }
	for x in u16(0) .. s.cols - 1 {
		set_screen_semantic_cell(mut s, x, 0, kitty_unicode_placeholder, .output)
	}
	first.data.rows[0].header.kitty_virtual_placeholder = true

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	s.resize(PageResizeOpts{ cols: 4, reflow: true }) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 2
	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	row0 := it.next() or { return }
	assert row0.row_data().header.kitty_virtual_placeholder
	row1 := it.next() or { return }
	assert !row1.row_data().header.kitty_virtual_placeholder
	assert it.next() == none
}

fn test_page_list_resize_reflow_wrap_moves_kitty_placeholder() ! {
	mut s := PageList.init(4, 2, uint(0))!
	defer { s.deinit() }

	mut first := s.pages.first or { return }
	for x in u16(2) .. s.cols - 1 {
		set_screen_semantic_cell(mut s, x, 0, kitty_unicode_placeholder, .output)
	}
	first.data.rows[0].header.kitty_virtual_placeholder = true

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 2
	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	row0 := it.next() or { return }
	assert !row0.row_data().header.kitty_virtual_placeholder
	row1 := it.next() or { return }
	assert row1.row_data().header.kitty_virtual_placeholder
	assert it.next() == none
}

fn test_page_list_resize_reflow_grapheme_map_capacity_exceeded() ! {
	mut s := PageList.init(4, 10, uint(0))!
	defer { s.deinit() }
	assert s.total_pages() == 1

	first := s.pages.first or { return }
	grapheme_capacity := first.data.grapheme_capacity()
	graphemes_per_page := grapheme_capacity / 2 + grapheme_capacity / 4
	remaining := int(first.data.capacity.rows - first.data.size.rows)
	for _ in 0 .. remaining {
		assert s.grow()!.node == none
	}
	assert s.total_pages() == 1
	s.grow_rows(uint(graphemes_per_page))!
	assert s.total_pages() == 2

	mut page0_node := s.pages.first or { return }
	mut page0 := &page0_node.data
	start_row := uint(page0.size.rows) - graphemes_per_page
	for i in 0 .. graphemes_per_page {
		y := start_row + i
		page0.rows[y].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`A`)
		}
		page0.append_grapheme(y, 0, u32(0x0301)) or { panic(err) }
	}

	mut page1_node := s.pages.last or { return }
	mut page1 := &page1_node.data
	count := if graphemes_per_page < uint(page1.size.rows) {
		graphemes_per_page
	} else {
		uint(page1.size.rows)
	}
	for y in 0 .. count {
		page1.rows[y].cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`B`)
		}
		page1.append_grapheme(y, 0, u32(0x0302)) or { panic(err) }
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
}

fn test_page_list_resize_reflow_exceeds_grapheme_memory_forcing_capacity_increase() ! {
	mut s := PageList.init(2, 10, uint(0))!
	defer { s.deinit() }
	assert s.total_pages() == 1

	first := s.pages.first or { return }
	remaining := int(first.data.capacity.rows - first.data.size.rows)
	for _ in 0 .. remaining {
		assert s.grow()!.node == none
	}
	s.grow_rows(1)!
	assert s.total_pages() == 2

	cps := []u32{len: int(grapheme_bytes_default / sizeof(u32)) - 1, init: u32(`a`)}
	mut page0_node := s.pages.first or { return }
	mut page0 := &page0_node.data
	y0 := uint(page0.size.rows) - 1
	x0 := uint(page0.size.cols) - 1
	page0.rows[y0].header.wrap = true
	page0.rows[y0].cells[x0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`X`)
	}
	page0.set_graphemes(y0, x0, cps) or { panic(err) }

	mut page1_node := s.pages.last or { return }
	mut page1 := &page1_node.data
	page1.rows[0].header.wrap = true
	page1.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`X`)
	}
	page1.set_graphemes(0, 0, cps) or { panic(err) }

	s.resize(PageResizeOpts{ cols: s.cols + 1, reflow: true }) or { panic(err) }
	assert s.cols == 3
}

fn test_page_list_resize_reflow_less_cols_blank_lines_between() ! {
	mut s := PageList.init(4, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for x in 0 .. 4 {
		page.rows[0].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
		page.rows[2].cells[x] = CellData{
			content_tag: .codepoint
			codepoint:   u32(x)
		}
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 5

	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	r0 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r0.row_data().header.wrap
	r1 := it.next() or {
		assert false, 'no row'
		return
	}
	assert r1.row_data().header.wrap
	assert r1.node.data.rows[int(r1.y)].cells[0].codepoint == 0
	r2 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r2.row_data().header.wrap
	assert r2.node.data.rows[int(r2.y)].cells[0].codepoint == 2
}

fn test_page_list_resize_reflow_less_cols_blank_lines_between_no_scrollback() ! {
	mut s := PageList.init(5, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`A`)
	}
	page.rows[2].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`C`)
	}

	s.resize(PageResizeOpts{ cols: 2, reflow: true }) or { panic(err) }
	assert s.cols == 2
	assert s.total_rows == 3

	mut it := s.row_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	r0 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r0.row_data().header.wrap
	assert r0.node.data.rows[int(r0.y)].cells[0].codepoint == u32(`A`)
	r1 := it.next() or {
		assert false, 'no row'
		return
	}
	assert r1.node.data.rows[int(r1.y)].cells[0].codepoint == 0
	r2 := it.next() or {
		assert false, 'no row'
		return
	}
	assert !r2.row_data().header.wrap
	assert r2.node.data.rows[int(r2.y)].cells[0].codepoint == u32(`C`)
}

fn test_page_list_resize_reflow_less_cols_cursor_not_on_last_line_preserves_location() ! {
	mut s := PageList.init(5, 5, uint(1))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in 0 .. int(s.rows) {
		for x in 0 .. 2 {
			page.rows[y].cells[x] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	// Grow blank rows to push our rows back into scrollback.
	s.grow_rows(5)!
	assert s.total_rows == 10

	p := s.track_pin(s.pin(Point.new(.active, Coordinate{ x: 0, y: 0 })) or {
		assert false, 'get_pin failed'
		return
	})!

	s.resize(PageResizeOpts{
		cols:   4
		reflow: true
		cursor: PageResizeCursor{
			x: 1
			y: 1
		}
	}) or { panic(err) }
	assert s.cols == 4
	assert s.total_rows == 10

	cursor := s.point_from_pin(.active, Pin{ node: p.node, y: p.y, x: p.x }) or {
		assert false, 'point_from_pin failed'
		return
	}
	assert cursor.coord().x == 0
	assert cursor.coord().y == 0

	s.untrack_pin(p)
}

fn test_page_list_resize_reflow_less_cols_wraps_spacer_head() ! {
	mut s := PageList.init(4, 3, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	// Row 0: 'x','x','x' then a spacer_head (wrapped).
	page.rows[0].header.wrap = true
	page.rows[0].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`x`)
	}
	page.rows[0].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`x`)
	}
	page.rows[0].cells[2] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`x`)
	}
	page.rows[0].cells[3] = CellData{
		content_tag: .codepoint
		codepoint:   0
		wide:        .spacer_head
	}
	// Row 1: wide emoji + spacer tail.
	page.rows[1].header.wrap_continuation = true
	page.rows[1].cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F600)
		wide:        .wide
	}
	page.rows[1].cells[1] = CellData{
		content_tag: .codepoint
		codepoint:   0
		wide:        .spacer_tail
	}

	s.resize(PageResizeOpts{ cols: 3, reflow: true }) or { panic(err) }
	assert s.cols == 3
	assert s.total_rows == 3

	np := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(np) == voidptr(s.pages.last or { return })
	mut new_page := &np.data
	// Row 0: xxx wrapped.
	assert new_page.rows[0].cells[0].codepoint == u32(`x`)
	assert new_page.rows[0].cells[0].wide == .narrow
	assert new_page.rows[0].header.wrap
	assert new_page.rows[0].cells[1].codepoint == u32(`x`)
	assert new_page.rows[0].cells[2].codepoint == u32(`x`)
	// Row 1: wide emoji + spacer tail.
	assert new_page.rows[1].cells[0].codepoint == u32(0x1F600)
	assert new_page.rows[1].cells[0].wide == .wide
	assert new_page.rows[1].cells[1].codepoint == 0
	assert new_page.rows[1].cells[1].wide == .spacer_tail
}

// ============================================================
// pageIterator / cellIterator precise tests
// ============================================================

fn test_page_list_page_iterator_single_page_precise() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert first.next == none

	mut it := s.page_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	chunk := it.next() or {
		assert false, 'no chunk'
		return
	}
	assert voidptr(chunk.node) == voidptr(first)
	assert chunk.start == 0
	assert chunk.end == u16(s.rows)

	assert it.next() == none
}

fn test_page_list_page_iterator_two_pages_precise() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow to fill page1 then one more to spill onto page2.
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	remaining := uint(first.data.capacity.rows) - uint(first.data.size.rows)
	s.grow_rows(remaining)!
	s.grow_rows(1)!
	assert s.total_pages() == 2

	last := s.pages.last or {
		assert false, 'no last page'
		return
	}

	mut it := s.page_iterator(.right_down, Point.new(.active, Coordinate{}), none)
	chunk1 := it.next() or {
		assert false, 'no chunk1'
		return
	}
	assert voidptr(chunk1.node) == voidptr(first)
	assert chunk1.start == u16(int(first.data.size.rows) - int(s.rows) + 1)
	assert chunk1.end == first.data.size.rows

	chunk2 := it.next() or {
		assert false, 'no chunk2'
		return
	}
	assert voidptr(chunk2.node) == voidptr(last)
	assert chunk2.start == 0
	assert chunk2.end == 1

	assert it.next() == none
}

fn test_page_list_page_iterator_history_two_pages() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	remaining := uint(first.data.capacity.rows) - uint(first.data.size.rows)
	s.grow_rows(remaining)!
	s.grow_rows(1)!
	assert s.total_pages() == 2

	active_tl := s.get_top_left(.active)
	mut it := s.page_iterator(.right_down, Point.new(.history, Coordinate{}), none)
	chunk := it.next() or {
		assert false, 'no chunk'
		return
	}
	assert voidptr(chunk.node) == voidptr(first)
	assert chunk.start == 0
	assert chunk.end == active_tl.y

	assert it.next() == none
}

fn test_page_list_page_iterator_reverse_single_page() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert first.next == none

	mut it := s.page_iterator(.left_up, Point.new(.active, Coordinate{}), none)
	chunk := it.next() or {
		assert false, 'no chunk'
		return
	}
	assert voidptr(chunk.node) == voidptr(first)
	assert chunk.start == 0
	assert chunk.end == u16(s.rows)

	assert it.next() == none
}

fn test_page_list_page_iterator_reverse_two_pages() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	remaining := uint(first.data.capacity.rows) - uint(first.data.size.rows)
	s.grow_rows(remaining)!
	s.grow_rows(1)!
	assert s.total_pages() == 2

	last := s.pages.last or {
		assert false, 'no last page'
		return
	}

	mut it := s.page_iterator(.left_up, Point.new(.active, Coordinate{}), none)
	mut count := u16(0)

	chunk1 := it.next() or {
		assert false, 'no chunk1'
		return
	}
	assert voidptr(chunk1.node) == voidptr(last)
	assert chunk1.start == 0
	assert chunk1.end == 1
	count += chunk1.end - chunk1.start

	chunk2 := it.next() or {
		assert false, 'no chunk2'
		return
	}
	assert voidptr(chunk2.node) == voidptr(first)
	assert chunk2.start == u16(int(first.data.size.rows) - int(s.rows) + 1)
	assert chunk2.end == first.data.size.rows
	count += chunk2.end - chunk2.start

	assert it.next() == none
	assert count == u16(s.rows)
}

fn test_page_list_page_iterator_reverse_history_two_pages() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	remaining := uint(first.data.capacity.rows) - uint(first.data.size.rows)
	s.grow_rows(remaining)!
	s.grow_rows(1)!
	assert s.total_pages() == 2

	active_tl := s.get_top_left(.active)
	mut it := s.page_iterator(.left_up, Point.new(.history, Coordinate{}), none)
	chunk := it.next() or {
		assert false, 'no chunk'
		return
	}
	assert voidptr(chunk.node) == voidptr(first)
	assert chunk.start == 0
	assert chunk.end == active_tl.y

	assert it.next() == none
}

fn test_page_list_cell_iterator_precise() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(first) == voidptr(s.pages.last or { return })
	mut page := &first.data
	for y in u16(0) .. 2 {
		for x in u16(0) .. 2 {
			page.rows[int(y)].cells[int(x)] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	mut it := s.cell_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
	expected := [[u32(0), 0], [u32(1), 0], [u32(0), 1], [u32(1), 1]]
	for exp in expected {
		p := it.next() or {
			assert false, 'iterator ended early'
			return
		}
		pt := s.point_from_pin(.screen, p) or {
			assert false, 'point_from_pin failed'
			return
		}
		assert pt.coord().x == exp[0]
		assert pt.coord().y == exp[1]
	}
	assert it.next() == none
}

fn test_page_list_cell_iterator_reverse_precise() ! {
	mut s := PageList.init(2, 2, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data
	for y in u16(0) .. 2 {
		for x in u16(0) .. 2 {
			page.rows[int(y)].cells[int(x)] = CellData{
				content_tag: .codepoint
				codepoint:   u32(x)
			}
		}
	}

	mut it := s.cell_iterator(.left_up, Point.new(.screen, Coordinate{}), none)
	expected := [[u32(1), 1], [u32(0), 1], [u32(1), 0], [u32(0), 0]]
	for exp in expected {
		p := it.next() or {
			assert false, 'iterator ended early'
			return
		}
		pt := s.point_from_pin(.screen, p) or {
			assert false, 'point_from_pin failed'
			return
		}
		assert pt.coord().x == exp[0]
		assert pt.coord().y == exp[1]
	}
	assert it.next() == none
}

// ============================================================
// erase tests (whole-region)
// ============================================================

fn test_page_list_erase_reaccounts_page_size() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	start_size := s.page_size

	// Grow so we take up at least 5 pages.
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!
	assert s.page_size > start_size

	// Erase the entire history; we should be back to just our active set.
	s.erase_rows(Point.new(.history, Coordinate{}), none)
	assert s.page_size == start_size
}

fn test_page_list_erase_row_with_tracked_pin_resets_to_top_left() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	// Grow so we take up at least 5 pages.
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!
	assert s.total_rows > uint(s.rows)

	// Put a tracked pin in the history.
	p := s.track_pin(s.get_top_left(.history))!

	// Erase the entire history; we should be back to just our active set.
	s.erase_rows(Point.new(.history, Coordinate{}), none)
	assert s.total_rows == uint(s.rows)

	// Our pin should move to the first page.
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(p.node) == voidptr(first)
	assert p.y == 0
	assert p.x == 0

	s.untrack_pin(p)
}

fn test_page_list_erase_row_with_tracked_pin_shifts() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	pin := s.pin(Point.new(.active, Coordinate{ x: 2, y: 4 })) or {
		assert false, 'active pin missing'
		return
	}
	p := s.track_pin(pin)!
	s.erase_rows(Point.new(.active, Coordinate{}), Point.new(.active, Coordinate{ y: 3 }))
	assert s.total_rows == uint(s.rows)
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(p.node) == voidptr(first)
	assert p.y == 0
	assert p.x == 2
	s.untrack_pin(p)
}

fn test_page_list_erase_row_with_tracked_pin_is_erased() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	pin := s.pin(Point.new(.active, Coordinate{ x: 2, y: 2 })) or {
		assert false, 'active pin missing'
		return
	}
	p := s.track_pin(pin)!
	s.erase_rows(Point.new(.active, Coordinate{}), Point.new(.active, Coordinate{ y: 3 }))
	assert s.total_rows == uint(s.rows)
	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(p.node) == voidptr(first)
	assert p.y == 0
	assert p.x == 0
	s.untrack_pin(p)
}

fn test_page_list_erase_resets_viewport_to_active_if_moves_within_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!

	// Move our viewport to the top.
	s.scroll(PageScrollDeltaRow{ delta: -int(s.total_rows) })
	assert s.viewport == .top

	// Erase the entire history; we should be back to just our active set.
	s.erase_rows(Point.new(.history, Coordinate{}), none)
	assert s.viewport == .active
}

fn test_page_list_erase_resets_viewport_if_inside_erased_page_but_not_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!
	s.scroll(PageScrollDeltaRow{ delta: -int(s.total_rows) })
	assert s.viewport == .top

	s.erase_rows(Point.new(.history, Coordinate{}), Point.new(.history, Coordinate{ y: 2 }))
	assert s.viewport == .top
}

fn test_page_list_erase_resets_viewport_to_active_if_top_is_inside_active() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }

	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 5)!

	// Move our viewport to the top.
	s.scroll(PageScrollTop{})

	// Erase the entire history; we should be back to just our active set.
	s.erase_rows(Point.new(.history, Coordinate{}), none)
	assert s.viewport == .active
}

fn test_page_list_erase_rows_invalidates_viewport_offset_cache() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 3)!
	pin_y := cap.rows
	viewport_pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: pin_y })) or { return }
	s.scroll(PageScrollPin{ pin: viewport_pin })
	assert s.scrollbar().offset == uint(pin_y)

	rows_to_erase := cap.rows / 2
	s.erase_rows(Point.new(.history, Coordinate{}), Point.new(.history, Coordinate{
		y: u32(rows_to_erase - 1)
	}))
	assert s.scrollbar() == Scrollbar{
		total:  s.total_rows
		offset: uint(pin_y - rows_to_erase)
		len:    uint(s.rows)
	}
}

fn test_page_list_erase_row_invalidates_viewport_offset_cache() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 3)!
	pin_y := cap.rows
	viewport_pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: pin_y })) or { return }
	s.scroll(PageScrollPin{ pin: viewport_pin })
	assert s.scrollbar().offset == uint(pin_y)

	s.erase_row(Point.new(.history, Coordinate{})) or { panic(err) }
	assert s.scrollbar() == Scrollbar{
		total:  s.total_rows
		offset: uint(pin_y - 1)
		len:    uint(s.rows)
	}
}

fn test_page_list_erase_row_bounded_invalidates_viewport_offset_cache() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 3)!
	pin_y := u16(4)
	viewport_pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: pin_y })) or { return }
	s.scroll(PageScrollPin{ pin: viewport_pin })
	assert s.scrollbar().offset == uint(pin_y)

	s.erase_row_bounded(Point.new(.history, Coordinate{}), 10) or { panic(err) }
	assert s.scrollbar() == Scrollbar{
		total:  s.total_rows
		offset: uint(pin_y - 1)
		len:    uint(s.rows)
	}
}

fn test_page_list_erase_row_bounded_multi_page_invalidates_viewport_offset_cache() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 3)!
	pin_y := u16(cap.rows + 1)
	viewport_pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: pin_y })) or { return }
	s.scroll(PageScrollPin{ pin: viewport_pin })
	assert s.scrollbar().offset == uint(pin_y)

	s.erase_row_bounded(Point.new(.history, Coordinate{}), uint(cap.rows) + 10) or {
		panic(err)
	}
	assert s.scrollbar() == Scrollbar{
		total:  s.total_rows
		offset: uint(pin_y - 1)
		len:    uint(s.rows)
	}
}

fn test_page_list_erase_row_bounded_full_page_shift_invalidates_viewport_offset_cache() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 4)!
	pin_y := u16(5)
	viewport_pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: pin_y })) or { return }
	s.scroll(PageScrollPin{ pin: viewport_pin })
	assert s.scrollbar().offset == uint(pin_y)

	s.erase_row_bounded(Point.new(.history, Coordinate{}), uint(cap.rows) * 2 + 10) or {
		panic(err)
	}
	assert s.scrollbar() == Scrollbar{
		total:  s.total_rows
		offset: uint(pin_y - 1)
		len:    uint(s.rows)
	}
}

fn test_page_list_erase_row_bounded_exhausts_pages_invalidates_viewport_offset_cache() ! {
	mut s := PageList.init(80, 24, uint(0x7FFFFFFFFFFFFFFF))!
	defer { s.deinit() }
	cap := initial_capacity(80)
	s.grow_rows(uint(cap.rows) * 3)!
	total_rows_before := s.total_rows
	pin_y := u16(uint(cap.rows) * 2 + 10)
	viewport_pin := s.pin(Point.new(.screen, Coordinate{ x: 0, y: pin_y })) or { return }
	s.scroll(PageScrollPin{ pin: viewport_pin })
	assert s.scrollbar().offset == uint(pin_y)

	s.erase_row_bounded(Point.new(.history, Coordinate{}), total_rows_before * 2) or {
		panic(err)
	}
	assert s.scrollbar() == Scrollbar{
		total:  s.total_rows
		offset: uint(pin_y - 1)
		len:    uint(s.rows)
	}
}

// ============================================================
// Split tests
// ============================================================

fn test_page_list_split_single_row_page_returns_out_of_space() ! {
	mut s := PageList.init(10, 1, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	split_pin := Pin{ node: first, y: 0, x: 0 }
	// Splitting a single-row page is impossible.
	mut error_message := ''
	s.split(split_pin) or { error_message = err.msg() }
	assert error_message == 'OutOfSpace'

	// The page is unchanged.
	assert s.total_pages() == 1
	assert first.data.size.rows == 1
}

fn test_page_list_split_multiple_tracked_pins_across_regions() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	original := s.pages.first or {
		assert false, 'no first page'
		return
	}

	pin_before := s.track_pin(Pin{ node: original, y: 1, x: 0 })!
	pin_at_split := s.track_pin(Pin{ node: original, y: 5, x: 2 })!
	pin_after1 := s.track_pin(Pin{ node: original, y: 7, x: 3 })!
	pin_after2 := s.track_pin(Pin{ node: original, y: 9, x: 8 })!

	s.split(Pin{ node: original, y: 5, x: 0 }) or {
		assert false, 'split failed: ${err}'
		return
	}

	first_page := s.pages.first or {
		assert false, 'no first page'
		return
	}
	second_page := first_page.next or {
		assert false, 'no second page'
		return
	}

	// Pin before split point stays in original page.
	assert voidptr(pin_before.node) == voidptr(first_page)
	assert pin_before.y == 1
	assert pin_before.x == 0

	// Pin at split point moves to new page with y=0.
	assert voidptr(pin_at_split.node) == voidptr(second_page)
	assert pin_at_split.y == 0
	assert pin_at_split.x == 2

	// Pins after split move to new page with adjusted y.
	assert voidptr(pin_after1.node) == voidptr(second_page)
	assert pin_after1.y == 2
	assert pin_after1.x == 3

	assert voidptr(pin_after2.node) == voidptr(second_page)
	assert pin_after2.y == 4
	assert pin_after2.x == 8

	s.untrack_pin(pin_before)
	s.untrack_pin(pin_at_split)
	s.untrack_pin(pin_after1)
	s.untrack_pin(pin_after2)
}

fn test_page_list_split_tracked_viewport_pin_in_split_region_moves_correctly() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	original := s.pages.first or {
		assert false, 'no first page'
		return
	}

	// Set viewport_pin to row 7 (after split point).
	s.viewport_pin.node = original
	s.viewport_pin.y = 7
	s.viewport_pin.x = 6

	s.split(Pin{ node: original, y: 5, x: 0 }) or {
		assert false, 'split failed: ${err}'
		return
	}

	second := original.next or {
		assert false, 'no second page'
		return
	}
	assert voidptr(s.viewport_pin.node) == voidptr(second)
	assert s.viewport_pin.y == 2
	assert s.viewport_pin.x == 6
}

fn test_page_list_split_last_page_makes_new_page_the_last() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first_node := s.pages.first or {
		assert false, 'no first page'
		return
	}
	s.split(Pin{ node: first_node, y: 5, x: 0 }) or {
		assert false, 'split failed'
		return
	}

	last_before := s.pages.last or {
		assert false, 'no last page'
		return
	}
	assert last_before.data.size.rows == 5

	s.split(Pin{ node: last_before, y: 2, x: 0 }) or {
		assert false, 'split failed'
		return
	}

	new_last := s.pages.last or {
		assert false, 'no last page'
		return
	}
	assert voidptr(new_last) != voidptr(last_before)
	prev := new_last.prev or {
		assert false, 'no prev'
		return
	}
	assert voidptr(prev) == voidptr(last_before)
	assert new_last.next == none

	assert last_before.data.size.rows == 2
	assert new_last.data.size.rows == 3
}

fn test_page_list_split_first_page_keeps_original_as_first() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	original_first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	s.split(Pin{ node: original_first, y: 5, x: 0 }) or {
		assert false, 'split failed'
		return
	}

	// Split the first page again.
	s.split(Pin{ node: original_first, y: 2, x: 0 }) or {
		assert false, 'split failed'
		return
	}

	// Original first should still be first.
	new_first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	assert voidptr(new_first) == voidptr(original_first)
	assert original_first.prev == none
}

fn test_page_list_split_preserves_styled_cells() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Create a style and apply it to cells in rows 5-7.
	style := CellStyle{
		flags: StyleFlags.init(true, false, false, false, false, false, false, false, .none)
	}
	style_id := page.styles.add(style) or {
		assert false, 'style add failed'
		return
	}

	for y in u16(5) .. 8 {
		mut row := &page.rows[int(y)]
		row.cells[0] = CellData{
			content_tag: .codepoint
			codepoint:   u32(`S`)
			style_id:    style_id
		}
		row.header.styled = true
		page.styles.use_style(style_id)
	}
	// Release the extra ref from add.
	page.styles.release(style_id)

	s.split(Pin{ node: first, y: 5, x: 0 }) or {
		assert false, 'split failed'
		return
	}

	second := first.next or {
		assert false, 'no second page'
		return
	}
	mut second_page := &second.data

	// Verify styled cells preserved in new page (rows 0-2).
	for y in u16(0) .. 3 {
		c := second_page.rows[int(y)].cells[0]
		assert c.codepoint == u32(`S`)
		assert c.style_id != 0
		got_style := second_page.styles.get(c.style_id)
		assert got_style.flags.bold()
		assert second_page.rows[int(y)].header.styled
	}
}

fn test_page_list_split_preserves_grapheme_clusters() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Add a grapheme cluster to row 6 (will be row 1 in second page).
	mut row6 := &page.rows[6]
	row6.cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(0x1F468) // Man emoji
	}
	page.set_graphemes(6, 0, [u32(0x200D), u32(0x1F469)]) or { panic(err) }

	assert page.grapheme_count() == 1

	s.split(Pin{ node: first, y: 5, x: 0 }) or {
		assert false, 'split failed'
		return
	}

	second := first.next or {
		assert false, 'no second page'
		return
	}
	mut second_page := &second.data

	// Second page should have exactly 1 grapheme.
	assert second_page.grapheme_count() == 1

	c := second_page.rows[1].cells[0]
	assert c.codepoint == u32(0x1F468)
	assert second_page.rows[1].header.grapheme

	cps := second_page.lookup_grapheme_at(1, 0) or {
		assert false, 'lookup_grapheme failed'
		return
	}
	assert cps.len == 2
	assert cps[0] == u32(0x200D)
	assert cps[1] == u32(0x1F469)
}

fn test_page_list_split_preserves_hyperlinks() ! {
	mut s := PageList.init(10, 10, uint(0))!
	defer { s.deinit() }

	first := s.pages.first or {
		assert false, 'no first page'
		return
	}
	mut page := &first.data

	// Add a hyperlink to row 7 (will be row 2 in second page).
	hyperlink_id := page.insert_hyperlink(Hyperlink{
		id:  HyperlinkImplicitId{
			offset: 0
		}
		uri: 'https://example.com'
	}) or { panic(err) }
	mut row7 := &page.rows[7]
	row7.cells[0] = CellData{
		content_tag: .codepoint
		codepoint:   u32(`L`)
	}
	page.set_hyperlink(7, 0, hyperlink_id) or { panic(err) }

	s.split(Pin{ node: first, y: 5, x: 0 }) or {
		assert false, 'split failed'
		return
	}

	second := first.next or {
		assert false, 'no second page'
		return
	}
	mut second_page := &second.data

	// Second page should have exactly 1 hyperlink.
	assert second_page.hyperlink_count() == 1

	c := second_page.rows[2].cells[0]
	assert c.codepoint == u32(`L`)
	assert c.has_hyperlink

	link_id := second_page.lookup_hyperlink_at(2, 0) or {
		assert false, 'lookup_hyperlink failed'
		return
	}
	link := second_page.hyperlink_set.get(link_id)
	assert link.uri == 'https://example.com'
	assert second_page.hyperlink_set.ref_count(link_id) == 1
}
