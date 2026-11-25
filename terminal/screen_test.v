module terminal

// Tests translated from Ghostty's src/terminal/Screen.zig.

// ============================================================
// Helpers
// ============================================================

// Ghostty's `.{ .active = .{ .x = x, .y = y } }` and friends.
fn pt(tag PointTag, x int, y int) Point {
	return Point.new(tag, Coordinate{
		x: u16(x)
		y: u32(y)
	})
}

fn active_pt(x int, y int) Point {
	return pt(.active, x, y)
}

fn screen_pt(x int, y int) Point {
	return pt(.screen, x, y)
}

fn viewport_pt(x int, y int) Point {
	return pt(.viewport, x, y)
}

fn history_pt(x int, y int) Point {
	return pt(.history, x, y)
}

// Ghostty's `s.pages.pin(point).?`.
fn must_pin(s &Screen, point Point) Pin {
	return s.pages.pin(point) or { panic('point ${point} is outside the page list') }
}

// Ghostty's `s.pages.getCell(point).?`.
fn must_cell(s &Screen, point Point) PageCell {
	return s.pages.get_cell(point) or { panic('point ${point} is outside the page list') }
}

// Ghostty's `s.pages.pointFromPin(tag, pin).?`.
fn must_point(s &Screen, tag PointTag, p Pin) Point {
	return s.pages.point_from_pin(tag, p) or { panic('pin is outside the page list') }
}

// Ghostty's `s.pages.pages.first.?`.
fn first_node(s &Screen) &PageNode {
	return s.pages.pages.first or { panic('page list has no first page') }
}

// Ghostty's `s.pages.pages.last.?`.
fn last_node(s &Screen) &PageNode {
	return s.pages.pages.last or { panic('page list has no last page') }
}

// Pointer identity for pages (Ghostty compares `*Page` pointers).
fn same_page(a &Page, b &Page) bool {
	return voidptr(a) == voidptr(b)
}

// Ghostty's `.{ .direct_color_bg = .{ .r = r, .g = g, .b = b } }`.
fn sgr_bg_rgb(r u8, g u8, b u8) SgrAttribute {
	return SgrDirectColorBg{
		rgb: RGB{
			r: r
			g: g
			b: b
		}
	}
}

// ============================================================
// Screen tests
// ============================================================

fn test_screen_read_and_write() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }
	assert s.cursor.style_id == u32(0)

	s.test_write_string('hello, world')!
	str := s.dump_string_alloc(.screen)!
	assert str == 'hello, world'
}

fn test_screen_read_and_write_newline() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }
	assert s.cursor.style_id == u32(0)

	s.test_write_string('hello\nworld')!
	str := s.dump_string_alloc(.screen)!
	assert str == 'hello\nworld'
}

fn test_screen_read_and_write_scrollback() ! {
	mut s := Screen.init(80, 2, 1000)!
	defer { s.deinit() }

	s.test_write_string('hello\nworld\ntest')!
	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == 'hello\nworld\ntest'
	}
	if true {
		str := s.dump_string_alloc(.active)!
		assert str == 'world\ntest'
	}
}

fn test_screen_read_and_write_no_scrollback_small() ! {
	mut s := Screen.init(80, 2, 0)!
	defer { s.deinit() }

	s.test_write_string('hello\nworld\ntest')!
	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == 'world\ntest'
	}
	if true {
		str := s.dump_string_alloc(.active)!
		assert str == 'world\ntest'
	}
}

fn test_screen_read_and_write_no_scrollback_large() ! {
	mut s := Screen.init(80, 2, 0)!
	defer { s.deinit() }

	for i in 0 .. 1000 {
		s.test_write_string('${i}\n')!
	}
	s.test_write_string('1000')!

	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == '999\n1000'
	}
}

fn test_screen_cursor_copy_x_y() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }
	s.cursor_absolute(2, 3)
	assert s.cursor.x == 2
	assert s.cursor.y == 3

	mut s2 := Screen.init(10, 10, 0)!
	defer { s2.deinit() }
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	assert s2.cursor.x == 2
	assert s2.cursor.y == 3
	s2.test_write_string('Hello')!

	if true {
		str := s2.dump_string_alloc(.screen)!
		assert str == '\n\n\n  Hello'
	}
}

fn test_screen_cursor_copy_style_deref() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	mut s2 := Screen.init(10, 10, 0)!
	defer { s2.deinit() }
	page := &s2.cursor.page_pin.node.data

	// Bold should create our style
	s2.set_attribute(SgrBold{})!
	assert page.styles.count() == uint(1)
	assert s2.cursor.style.flags.bold()

	// Copy default style, should release our style
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	assert !s2.cursor.style.flags.bold()
	assert page.styles.count() == uint(0)
}

fn test_screen_cursor_copy_style_deref_new_page() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	mut s2 := Screen.init(10, 10, 2048)!
	defer { s2.deinit() }

	// We need to get the cursor on a new page.
	mut first := first_node(s2)
	first_page_size := int(first.data.capacity.rows)

	// Fill the scrollback with blank lines until
	// there are only 5 rows left on the first page.
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 5 {
		s2.test_write_string('\n')!
	}
	first.data.pause_integrity_checks(false)

	s2.test_write_string('1\n2\n3\n4\n5\n6\n7\n8\n9\n10')!

	// s2.pages.diagram(...):
	//
	//      +----------+ = PAGE 0
	//  ... :          :
	//     +-------------+ ACTIVE
	// 4300 |1         | | 0
	// 4301 |2         | | 1
	// 4302 |3         | | 2
	// 4303 |4         | | 3
	// 4304 |5         | | 4
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |6         | | 5
	//    1 |7         | | 6
	//    2 |8         | | 7
	//    3 |9         | | 8
	//    4 |10        | | 9
	//      :  ^       : : = PIN 0
	//      +----------+ :
	//     +-------------+

	// This should be PAGE 1
	page := &s2.cursor.page_pin.node.data

	// It should be the last page in the list.
	assert same_page(&last_node(s2).data, page)
	// It should have a previous page.
	assert s2.cursor.page_pin.node.prev != none

	// The cursor should be at 2, 9
	assert s2.cursor.x == 2
	assert s2.cursor.y == 9

	// Bold should create our style in page 1.
	s2.set_attribute(SgrBold{})!
	assert page.styles.count() == uint(1)
	assert s2.cursor.style.flags.bold()

	// Copy the cursor for the first screen. This should release
	// the style from page 1 and move the cursor back to page 0.
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	assert !s2.cursor.style.flags.bold()
	assert page.styles.count() == uint(0)
	// The page after the page the cursor is now in should be page 1.
	next := s2.cursor.page_pin.node.next or { panic('cursor page has no next page') }
	assert same_page(page, &next.data)
	// The cursor should be at 0, 0
	assert s2.cursor.x == 0
	assert s2.cursor.y == 0
}

fn test_screen_cursor_copy_style_copy() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }
	s.set_attribute(SgrBold{})!

	mut s2 := Screen.init(10, 10, 0)!
	defer { s2.deinit() }
	page := &s2.cursor.page_pin.node.data
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	assert s2.cursor.style.flags.bold()
	assert page.styles.count() == uint(1)
}

fn test_screen_cursor_copy_hyperlink_deref() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	mut s2 := Screen.init(10, 10, 0)!
	defer { s2.deinit() }
	page := &s2.cursor.page_pin.node.data

	// Create a hyperlink for the cursor.
	s2.start_hyperlink('https://example.com/', none)!
	assert page.hyperlink_set.count() == uint(1)
	assert s2.cursor.hyperlink_id != 0

	// Copy a cursor with no hyperlink, should release our hyperlink.
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	assert page.hyperlink_set.count() == uint(0)
	assert s2.cursor.hyperlink_id == 0
}

fn test_screen_cursor_copy_hyperlink_deref_new_page() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	mut s2 := Screen.init(10, 10, 2048)!
	defer { s2.deinit() }

	// We need to get the cursor on a new page.
	mut first := first_node(s2)
	first_page_size := int(first.data.capacity.rows)

	// Fill the scrollback with blank lines until
	// there are only 5 rows left on the first page.
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 5 {
		s2.test_write_string('\n')!
	}
	first.data.pause_integrity_checks(false)

	s2.test_write_string('1\n2\n3\n4\n5\n6\n7\n8\n9\n10')!

	// s2.pages.diagram(...):
	//
	//      +----------+ = PAGE 0
	//  ... :          :
	//     +-------------+ ACTIVE
	// 4300 |1         | | 0
	// 4301 |2         | | 1
	// 4302 |3         | | 2
	// 4303 |4         | | 3
	// 4304 |5         | | 4
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |6         | | 5
	//    1 |7         | | 6
	//    2 |8         | | 7
	//    3 |9         | | 8
	//    4 |10        | | 9
	//      :  ^       : : = PIN 0
	//      +----------+ :
	//     +-------------+

	// This should be PAGE 1
	page := &s2.cursor.page_pin.node.data

	// It should be the last page in the list.
	assert same_page(&last_node(s2).data, page)
	// It should have a previous page.
	assert s2.cursor.page_pin.node.prev != none

	// The cursor should be at 2, 9
	assert s2.cursor.x == 2
	assert s2.cursor.y == 9

	// Create a hyperlink for the cursor, should be in page 1.
	s2.start_hyperlink('https://example.com/', none)!
	assert page.hyperlink_set.count() == uint(1)
	assert s2.cursor.hyperlink_id != 0

	// Copy the cursor for the first screen. This should release
	// the hyperlink from page 1 and move the cursor back to page 0.
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	assert page.hyperlink_set.count() == uint(0)
	assert s2.cursor.hyperlink_id == 0
	// The page after the page the cursor is now in should be page 1.
	next := s2.cursor.page_pin.node.next or { panic('cursor page has no next page') }
	assert same_page(page, &next.data)
	// The cursor should be at 0, 0
	assert s2.cursor.x == 0
	assert s2.cursor.y == 0
}

fn test_screen_cursor_copy_hyperlink_copy() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	// Create a hyperlink for the cursor.
	s.start_hyperlink('https://example.com/', none)!
	assert s.cursor.page_pin.node.data.hyperlink_set.count() == uint(1)
	assert s.cursor.hyperlink_id != 0

	mut s2 := Screen.init(10, 10, 0)!
	defer { s2.deinit() }
	page := &s2.cursor.page_pin.node.data

	assert page.hyperlink_set.count() == uint(0)
	assert s2.cursor.hyperlink_id == 0

	// Copy the cursor with the hyperlink.
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	assert page.hyperlink_set.count() == uint(1)
	assert s2.cursor.hyperlink_id != 0
}

fn test_screen_cursor_copy_hyperlink_copy_disabled() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	// Create a hyperlink for the cursor.
	s.start_hyperlink('https://example.com/', none)!
	assert s.cursor.page_pin.node.data.hyperlink_set.count() == uint(1)
	assert s.cursor.hyperlink_id != 0

	mut s2 := Screen.init(10, 10, 0)!
	defer { s2.deinit() }
	page := &s2.cursor.page_pin.node.data

	assert page.hyperlink_set.count() == uint(0)
	assert s2.cursor.hyperlink_id == 0

	// Copy the cursor with the hyperlink.
	s2.cursor_copy(s.cursor, CursorCopyOptions{ hyperlink: false })!
	assert page.hyperlink_set.count() == uint(0)
	assert s2.cursor.hyperlink_id == 0
}

fn test_screen_style_basics() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }
	page := &s.cursor.page_pin.node.data
	assert page.styles.count() == uint(0)

	// Set a new style
	s.set_attribute(SgrBold{})!
	assert s.cursor.style_id != 0
	assert page.styles.count() == uint(1)
	assert s.cursor.style.flags.bold()

	// Set another style, we should still only have one since it was unused
	s.set_attribute(SgrItalic{})!
	assert s.cursor.style_id != 0
	assert page.styles.count() == uint(1)
	assert s.cursor.style.flags.italic()
}

fn test_screen_style_reset_to_default() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }
	page := &s.cursor.page_pin.node.data
	assert page.styles.count() == uint(0)

	// Set a new style
	s.set_attribute(SgrBold{})!
	assert s.cursor.style_id != 0
	assert page.styles.count() == uint(1)

	// Reset to default
	s.set_attribute(SgrResetBold{})!
	assert s.cursor.style_id == 0
	assert page.styles.count() == uint(0)
}

fn test_screen_style_reset_with_unset() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }
	page := &s.cursor.page_pin.node.data
	assert page.styles.count() == uint(0)

	// Set a new style
	s.set_attribute(SgrBold{})!
	assert s.cursor.style_id != 0
	assert page.styles.count() == uint(1)

	// Reset to default
	s.set_attribute(SgrUnset{})!
	assert s.cursor.style_id == 0
	assert page.styles.count() == uint(0)
}

fn test_screen_clear_rows_active_one_line() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }

	s.test_write_string('hello, world')!
	s.clear_rows(active_pt(0, 0), none, false)
	assert s.pages.is_dirty(active_pt(0, 0))
	str := s.dump_string_alloc(.screen)!
	assert str == ''
}

fn test_screen_clear_rows_active_multi_line() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }

	s.test_write_string('hello\nworld')!
	s.clear_rows(active_pt(0, 0), none, false)
	assert s.pages.is_dirty(active_pt(0, 0))
	assert s.pages.is_dirty(active_pt(0, 1))
	str := s.dump_string_alloc(.screen)!
	assert str == ''
}

fn test_screen_clear_rows_active_styled_line() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }

	s.set_attribute(SgrBold{})!
	s.test_write_string('hello world')!
	s.set_attribute(SgrUnset{})!

	// We should have one style
	page := &s.cursor.page_pin.node.data
	assert page.styles.count() == uint(1)

	s.clear_rows(active_pt(0, 0), none, false)

	// We should have none because active cleared it
	assert page.styles.count() == uint(0)

	str := s.dump_string_alloc(.screen)!
	assert str == ''
}

fn test_screen_clear_rows_protected() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }

	s.test_write_string('UNPROTECTED')!
	s.cursor.is_protected = true
	s.test_write_string('PROTECTED')!
	s.cursor.is_protected = false
	s.test_write_string('UNPROTECTED')!
	s.test_write_string('\n')!
	s.cursor.is_protected = true
	s.test_write_string('PROTECTED')!
	s.cursor.is_protected = false
	s.test_write_string('UNPROTECTED')!
	s.cursor.is_protected = true
	s.test_write_string('PROTECTED')!
	s.cursor.is_protected = false

	s.clear_rows(active_pt(0, 0), none, true)

	str := s.dump_string_alloc(.screen)!
	assert str == '           PROTECTED\nPROTECTED           PROTECTED'
}

fn test_screen_erase_rows_history() ! {
	mut s := Screen.init(5, 5, 1000)!
	defer { s.deinit() }

	s.test_write_string('1\n2\n3\n4\n5\n6')!

	if true {
		str := s.dump_string_alloc(.active)!
		assert str == '2\n3\n4\n5\n6'
	}
	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == '1\n2\n3\n4\n5\n6'
	}

	s.erase_rows(history_pt(0, 0), none)

	if true {
		str := s.dump_string_alloc(.active)!
		assert str == '2\n3\n4\n5\n6'
	}
	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == '2\n3\n4\n5\n6'
	}
}

fn test_screen_erase_rows_history_with_more_lines() ! {
	mut s := Screen.init(5, 5, 1000)!
	defer { s.deinit() }

	s.test_write_string('A\nB\nC\n1\n2\n3\n4\n5\n6')!

	if true {
		str := s.dump_string_alloc(.active)!
		assert str == '2\n3\n4\n5\n6'
	}
	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == 'A\nB\nC\n1\n2\n3\n4\n5\n6'
	}

	s.erase_rows(history_pt(0, 0), none)

	if true {
		str := s.dump_string_alloc(.active)!
		assert str == '2\n3\n4\n5\n6'
	}
	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == '2\n3\n4\n5\n6'
	}
}

fn test_screen_erase_rows_active_partial() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	s.test_write_string('1\n2\n3')!

	if true {
		str := s.dump_string_alloc(.active)!
		assert str == '1\n2\n3'
	}

	s.erase_rows(active_pt(0, 0), active_pt(0, 1))

	if true {
		str := s.dump_string_alloc(.active)!
		assert str == '3'
	}
	if true {
		str := s.dump_string_alloc(.screen)!
		assert str == '3'
	}
}

fn test_screen_cursor_down_across_pages_preserves_style() ! {
	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }

	// Scroll down enough to go to another page
	mut start_node := last_node(s)
	start_page := &start_node.data
	rem := int(start_page.capacity.rows)
	start_node.data.pause_integrity_checks(true)
	for _ in 0 .. rem {
		s.cursor_down_or_scroll()!
	}
	start_node.data.pause_integrity_checks(false)

	// We need our page to change for this test o make sense. If this
	// assertion fails then the bug is in the test: we should be scrolling
	// above enough for a new page to show up.
	if true {
		page := &s.cursor.page_pin.node.data
		assert !same_page(start_page, page)
	}

	// Scroll back to the previous page
	s.cursor_up(1)
	if true {
		page := &s.cursor.page_pin.node.data
		assert same_page(start_page, page)
	}

	// Go back up, set a style
	s.set_attribute(SgrBold{})!
	if true {
		page := &s.cursor.page_pin.node.data
		styleval := page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}

	// Go back down into the next page and we should have that style
	s.cursor_down(1)
	if true {
		page := &s.cursor.page_pin.node.data
		styleval := page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}
}

fn test_screen_cursor_up_across_pages_preserves_style() ! {
	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }

	// Scroll down enough to go to another page
	mut start_node := last_node(s)
	start_page := &start_node.data
	rem := int(start_page.capacity.rows)
	start_node.data.pause_integrity_checks(true)
	for _ in 0 .. rem {
		s.cursor_down_or_scroll()!
	}
	start_node.data.pause_integrity_checks(false)

	// We need our page to change for this test o make sense. If this
	// assertion fails then the bug is in the test: we should be scrolling
	// above enough for a new page to show up.
	if true {
		page := &s.cursor.page_pin.node.data
		assert !same_page(start_page, page)
	}

	// Go back up, set a style
	s.set_attribute(SgrBold{})!
	if true {
		page := &s.cursor.page_pin.node.data
		styleval := page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}

	// Go back down into the prev page and we should have that style
	s.cursor_up(1)
	if true {
		page := &s.cursor.page_pin.node.data
		assert same_page(start_page, page)

		styleval := page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}
}

fn test_screen_cursor_absolute_across_pages_preserves_style() ! {
	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }

	// Scroll down enough to go to another page
	mut start_node := last_node(s)
	start_page := &start_node.data
	rem := int(start_page.capacity.rows)
	start_node.data.pause_integrity_checks(true)
	for _ in 0 .. rem {
		s.cursor_down_or_scroll()!
	}
	start_node.data.pause_integrity_checks(false)

	// We need our page to change for this test o make sense. If this
	// assertion fails then the bug is in the test: we should be scrolling
	// above enough for a new page to show up.
	if true {
		page := &s.cursor.page_pin.node.data
		assert !same_page(start_page, page)
	}

	// Go back up, set a style
	s.set_attribute(SgrBold{})!
	if true {
		page := &s.cursor.page_pin.node.data
		styleval := page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}

	// Go back down into the prev page and we should have that style
	s.cursor_absolute(1, 1)
	if true {
		page := &s.cursor.page_pin.node.data
		assert same_page(start_page, page)

		styleval := page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}
}

fn test_screen_cursor_absolute_to_page_with_insufficient_capacity() ! {
	// This test checks for a very specific edge case
	// which previously resulted in memory corruption.
	//
	// The conditions for this edge case are as such:
	// - The cursor has an associated style or other managed memory.
	// - The cursor moves to a different page.
	// - The new page is at capacity and must have its capacity adjusted.

	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }

	// Scroll down enough to go to another page
	mut start_node := last_node(s)
	start_page := &start_node.data
	rem := int(start_page.capacity.rows)
	start_node.data.pause_integrity_checks(true)
	for _ in 0 .. rem {
		s.cursor_down_or_scroll()!
	}
	start_node.data.pause_integrity_checks(false)

	new_page := &s.cursor.page_pin.node.data

	// We need our page to change for this test to make sense. If this
	// assertion fails then the bug is in the test: we should be scrolling
	// above enough for a new page to show up.
	assert !same_page(start_page, new_page)

	// Add styles to the start page until it reaches capacity.
	if true {
		// Pause integrity checks because they're slow and
		// we're not testing this, this is just setup.
		start_node.data.pause_integrity_checks(true)
		defer {
			start_node.data.pause_integrity_checks(false)
			start_node.data.assert_integrity()
		}

		mut n := u32(1)
		for {
			start_node.data.styles.add(CellStyle{
				bg_color: StyleColorRgb{
					rgb: RGB{
						r: u8(n)
						g: u8(n >> 8)
						b: u8(n >> 16)
					}
				}
			}) or { break }
			n += 1
		}
	}

	// Set a style on the cursor.
	s.set_attribute(SgrBold{})!
	if true {
		styleval := new_page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}

	// Go back up into the start page and we should still have that style.
	s.cursor_absolute(1, 1)
	if true {
		cur_page := &s.cursor.page_pin.node.data
		// The page we're on now should NOT equal start_page, since its
		// capacity should have been adjusted, which invalidates our ptr.
		assert !same_page(start_page, cur_page)
		// To make sure we DID change pages we check we're not on new_page.
		assert !same_page(new_page, cur_page)

		styleval := cur_page.styles.get(s.cursor.style_id)
		assert styleval.flags.bold()
	}

	s.cursor.page_pin.node.data.assert_integrity()
	new_page.assert_integrity()
}

fn test_screen_scrolling() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.set_attribute(sgr_bg_rgb(155, 0, 0))!
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Scroll down, should still be bottom
	s.cursor_down_scroll()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 2))
		cell := list_cell.cell
		assert cell.content_tag == .bg_color_rgb
		assert cell.color_rgb_r() == u8(155)
		assert cell.color_rgb_g() == u8(0)
		assert cell.color_rgb_b() == u8(0)
	}

	// Everything is dirty because we have no scrollback
	assert s.pages.is_dirty(active_pt(0, 0))
	assert s.pages.is_dirty(active_pt(0, 1))
	assert s.pages.is_dirty(active_pt(0, 2))

	// Scrolling to the bottom does nothing
	s.scroll(ScrollActive{})

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}
}

fn test_screen_scrolling_with_a_single_row_screen_no_scrollback() ! {
	mut s := Screen.init(10, 1, 0)!
	defer { s.deinit() }
	s.test_write_string('1ABCD')!

	// Scroll down, should still be bottom
	s.cursor_down_scroll()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}

	// Screen should be dirty
	assert s.pages.is_dirty(active_pt(0, 0))
}

fn test_screen_scrolling_with_a_single_row_screen_with_scrollback() ! {
	mut s := Screen.init(10, 1, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD')!

	// Scroll down, should still be bottom
	s.cursor_down_scroll()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}

	// Active should be dirty
	assert s.pages.is_dirty(active_pt(0, 0))

	// Scrollback also dirty because cursor moved from there
	assert s.pages.is_dirty(screen_pt(0, 0))

	s.scroll(ScrollDeltaRow{ delta: -1 })
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD'
	}
}

fn test_screen_scrolling_across_pages_preserves_style() ! {
	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }
	s.set_attribute(SgrBold{})!
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	mut start_node := last_node(s)
	start_page := &start_node.data

	// Scroll down enough to go to another page
	rem := int(start_page.capacity.rows) - int(start_page.size.rows) + 1
	start_node.data.pause_integrity_checks(true)
	for _ in 0 .. rem {
		s.cursor_down_or_scroll()!
	}
	start_node.data.pause_integrity_checks(false)

	// We need our page to change for this test o make sense. If this
	// assertion fails then the bug is in the test: we should be scrolling
	// above enough for a new page to show up.
	page := &last_node(s).data
	assert !same_page(start_page, page)

	styleval := page.styles.get(s.cursor.style_id)
	assert styleval.flags.bold()
}

fn test_screen_scroll_down_from_0() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Scrolling up does nothing, but allows it
	s.scroll(ScrollDeltaRow{ delta: -1 })
	assert s.pages.viewport == .active

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}
}

fn test_screen_scrollback_various_cases() ! {
	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	s.cursor_down_scroll()!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}

	// Scrolling to the bottom
	s.scroll(ScrollActive{})
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}

	// Scrolling back should make it visible again
	s.scroll(ScrollDeltaRow{ delta: -1 })
	assert s.pages.viewport != .active
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}

	// Scrolling back again should do nothing
	s.scroll(ScrollDeltaRow{ delta: -1 })
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}

	// Scrolling to the bottom
	s.scroll(ScrollActive{})
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}

	// Scrolling forward with no grow should do nothing
	s.scroll(ScrollDeltaRow{ delta: 1 })
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}

	// Scrolling to the top should work
	s.scroll(ScrollTop{})
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}

	// Should be able to easily clear active area only
	s.clear_rows(active_pt(0, 0), none, false)
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD'
	}

	// Scrolling to the bottom
	s.scroll(ScrollActive{})
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}
}

fn test_screen_scrollback_with_multi_row_delta() ! {
	mut s := Screen.init(10, 3, 3)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH\n6IJKL')!

	// Scroll to top
	s.scroll(ScrollTop{})
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}

	// Scroll down multiple
	s.scroll(ScrollDeltaRow{ delta: 5 })
	assert s.pages.viewport == .active
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '4ABCD\n5EFGH\n6IJKL'
	}
}

fn test_screen_scrollback_empty() ! {
	mut s := Screen.init(10, 3, 50)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	s.scroll(ScrollDeltaRow{ delta: 1 })
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}
}

fn test_screen_scrollback_doesnt_move_viewport_if_not_at_bottom() ! {
	mut s := Screen.init(10, 3, 3)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH')!

	// First test: we scroll up by 1, so we're not at the bottom anymore.
	s.scroll(ScrollDeltaRow{ delta: -1 })
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL\n4ABCD'
	}

	// Next, we scroll back down by 1, this grows the scrollback but we
	// shouldn't move.
	s.cursor_down_scroll()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL\n4ABCD'
	}

	// Scroll again, this clears scrollback so we should move viewports
	// but still see the same thing since our original view fits.
	s.cursor_down_scroll()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL\n4ABCD'
	}
}

fn test_screen_scrolling_moves_selection() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Select a single line
	s.select(Selection.init(must_pin(s, active_pt(0, 1)), must_pin(s, active_pt(int(s.pages.cols) - 1,
		1)), false))!

	// Scroll down, should still be bottom
	s.cursor_down_scroll()!

	// Our selection should've moved up
	if true {
		sel := s.selection or { panic('no selection') }
		assert must_point(s, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s, .active, sel.end()) == active_pt(int(s.pages.cols) - 1, 0)
	}

	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}

	// Scrolling to the bottom does nothing
	s.scroll(ScrollActive{})

	// Our selection should've stayed the same
	if true {
		sel := s.selection or { panic('no selection') }
		assert must_point(s, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s, .active, sel.end()) == active_pt(int(s.pages.cols) - 1, 0)
	}

	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}

	// Scroll up again
	s.cursor_down_scroll()!

	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '3IJKL'
	}

	// Our selection should be null because it left the screen.
	if true {
		sel := s.selection or { panic('no selection') }
		assert s.pages.point_from_pin(.active, sel.start()) == none
		assert s.pages.point_from_pin(.active, sel.end()) == none
	}
}

fn test_screen_scrolling_moves_viewport() ! {
	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n')!
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	s.scroll(ScrollDeltaRow{ delta: -2 })

	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL\n1ABCD'
	}

	if true {
		assert must_point(s, .screen, s.pages.get_top_left(.viewport)) == screen_pt(0, 1)
	}
}

fn test_screen_scrolling_when_viewport_is_pruned() ! {
	mut s := Screen.init(215, 3, 1)!
	defer { s.deinit() }

	// Write some to create scrollback and move back into our scrollback.
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n')!
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	s.scroll(ScrollDeltaRow{ delta: -2 })

	// Our viewport is now somewhere pinned. Create so much scrollback
	// that we prune it.
	s.test_write_string('\n')!
	for _ in 0 .. 1000 {
		s.test_write_string('1ABCD\n2EFGH\n3IJKL\n')!
	}
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	if true {
		assert must_point(s, .screen, s.pages.get_top_left(.viewport)) == screen_pt(0, 0)
	}
}

fn test_screen_scroll_and_clear_full_screen() ! {
	mut s := Screen.init(10, 3, 5)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}

	s.scroll_clear()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}
}

fn test_screen_scroll_and_clear_partial_screen() ! {
	mut s := Screen.init(10, 3, 5)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH')!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH'
	}

	s.scroll_clear()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '1ABCD\n2EFGH'
	}
}

fn test_screen_scroll_and_clear_empty_screen() ! {
	mut s := Screen.init(10, 3, 5)!
	defer { s.deinit() }
	s.scroll_clear()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == ''
	}
}

fn test_screen_scroll_and_clear_ignore_blank_lines() ! {
	mut s := Screen.init(10, 3, 10)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH')!
	s.scroll_clear()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}

	// Move back to top-left
	s.cursor_absolute(0, 0)

	// Write and clear
	s.test_write_string('3ABCD\n')!
	if true {
		contents := s.dump_string_alloc(.active)!
		assert contents == '3ABCD'
	}

	s.scroll_clear()!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == ''
	}

	// Move back to top-left
	s.cursor_absolute(0, 0)
	s.test_write_string('X')!

	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '1ABCD\n2EFGH\n3ABCD\nX'
	}
}

fn test_screen_scroll_above_same_page() ! {
	mut s := Screen.init(10, 3, 10)!
	defer { s.deinit() }
	s.set_attribute(sgr_bg_rgb(155, 0, 0))!
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	s.cursor_absolute(0, 1)
	s.pages.clear_dirty()

	// At this point:
	//  +-------------+ ACTIVE
	//   +----------+ : = PAGE 0
	// 0 |1ABCD00000| | 0
	// 1 |2EFGH00000| | 1
	//   :^         : : = PIN 0
	// 2 |3IJKL00000| | 2
	//   +----------+ :
	//  +-------------+

	s.cursor_scroll_above()!

	//   +----------+ = PAGE 0
	// 0 |1ABCD00000|
	//  +-------------+ ACTIVE
	// 1 |2EFGH00000| | 0
	// 2 |          | | 1
	//   :^         : : = PIN 0
	// 3 |3IJKL00000| | 2
	//   +----------+ :
	//  +-------------+

	// try s.pages.diagram(std.io.getStdErr().writer());

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n\n3IJKL'
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 1))
		cell := list_cell.cell
		assert cell.content_tag == .bg_color_rgb
		assert cell.color_rgb_r() == u8(155)
		assert cell.color_rgb_g() == u8(0)
		assert cell.color_rgb_b() == u8(0)
	}

	// Page 0 row 1 (active row 0) is dirty because the cursor moved off of it.
	assert s.pages.is_dirty(active_pt(0, 0))
	// Page 0 row 2 (active row 1) is dirty because it was cleared.
	assert s.pages.is_dirty(active_pt(0, 1))
	// Page 0 row 3 (active row 2) is dirty because it's new.
	assert s.pages.is_dirty(active_pt(0, 2))
}

fn test_screen_scroll_above_same_page_but_cursor_on_previous_page() ! {
	mut s := Screen.init(10, 5, 10)!
	defer { s.deinit() }

	// We need to get the cursor to a new page
	mut first := first_node(s)
	first_page_size := int(first.data.capacity.rows)
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 3 {
		s.test_write_string('\n')!
	}
	first.data.pause_integrity_checks(false)

	s.set_attribute(sgr_bg_rgb(155, 0, 0))!
	s.test_write_string('1A\n2B\n3C\n4D\n5E')!
	s.cursor_absolute(0, 1)
	s.pages.clear_dirty()

	// Ensure we're still on the first page and have a second
	assert voidptr(s.cursor.page_pin.node) == voidptr(first_node(s))
	assert first_node(s).next != none

	// At this point:
	//      +----------+ = PAGE 0
	//  ... :          :
	//     +-------------+ ACTIVE
	// 4305 |1A00000000| | 0
	// 4306 |2B00000000| | 1
	//      :^         : : = PIN 0
	// 4307 |3C00000000| | 2
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |4D00000000| | 3
	//    1 |5E00000000| | 4
	//      +----------+ :
	//     +-------------+

	s.cursor_scroll_above()!

	//      +----------+ = PAGE 0
	//  ... :          :
	// 4305 |1A00000000|
	//     +-------------+ ACTIVE
	// 4306 |2B00000000| | 0
	// 4307 |          | | 1
	//      :^         : : = PIN 0
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |3C00000000| | 2
	//    1 |4D00000000| | 3
	//    2 |5E00000000| | 4
	//      +----------+ :
	//     +-------------+

	// try s.pages.diagram(std.io.getStdErr().writer());

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2B\n\n3C\n4D\n5E'
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 1))
		cell := list_cell.cell
		assert cell.content_tag == .bg_color_rgb
		assert cell.color_rgb_r() == u8(155)
		assert cell.color_rgb_g() == u8(0)
		assert cell.color_rgb_b() == u8(0)
	}

	// Page 0's penultimate row is dirty because the cursor moved off of it.
	assert s.pages.is_dirty(active_pt(0, 0))
	// The rest of the rows are dirty because they've been modified or are new.
	assert s.pages.is_dirty(active_pt(0, 1))
	assert s.pages.is_dirty(active_pt(0, 2))
	assert s.pages.is_dirty(active_pt(0, 3))
	assert s.pages.is_dirty(active_pt(0, 4))
}

fn test_screen_scroll_above_same_page_but_cursor_on_previous_page_last_row() ! {
	mut s := Screen.init(10, 5, 10)!
	defer { s.deinit() }

	// We need to get the cursor to a new page
	mut first := first_node(s)
	first_page_size := int(first.data.capacity.rows)
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 2 {
		s.test_write_string('\n')!
	}
	first.data.pause_integrity_checks(false)

	s.set_attribute(sgr_bg_rgb(155, 0, 0))!
	s.test_write_string('1A\n2B\n3C\n4D\n5E')!
	s.cursor_absolute(0, 1)
	s.pages.clear_dirty()

	// Ensure we're still on the first page and have a second
	assert voidptr(s.cursor.page_pin.node) == voidptr(first_node(s))
	assert first_node(s).next != none

	// At this point:
	//      +----------+ = PAGE 0
	//  ... :          :
	//     +-------------+ ACTIVE
	// 4306 |1A00000000| | 0
	// 4307 |2B00000000| | 1
	//      :^         : : = PIN 0
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |3C00000000| | 2
	//    1 |4D00000000| | 3
	//    2 |5E00000000| | 4
	//      +----------+ :
	//     +-------------+

	s.cursor_scroll_above()!

	//      +----------+ = PAGE 0
	//  ... :          :
	// 4306 |1A00000000|
	//     +-------------+ ACTIVE
	// 4307 |2B00000000| | 0
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |          | | 1
	//      :^         : : = PIN 0
	//    1 |3C00000000| | 2
	//    2 |4D00000000| | 3
	//    3 |5E00000000| | 4
	//      +----------+ :
	//     +-------------+

	// try s.pages.diagram(std.io.getStdErr().writer());

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2B\n\n3C\n4D\n5E'
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 1))
		cell := list_cell.cell
		assert cell.content_tag == .bg_color_rgb
		assert cell.color_rgb_r() == u8(155)
		assert cell.color_rgb_g() == u8(0)
		assert cell.color_rgb_b() == u8(0)
	}

	// Page 0's final row is dirty because the cursor moved off of it.
	assert s.pages.is_dirty(active_pt(0, 0))
	// Page 1's rows are all dirty because every row was moved.
	assert s.pages.is_dirty(active_pt(0, 1))
	assert s.pages.is_dirty(active_pt(0, 2))
	assert s.pages.is_dirty(active_pt(0, 3))
	assert s.pages.is_dirty(active_pt(0, 4))

	// Attempt to clear the style from the cursor and
	// then assert the integrity of both of our pages.
	//
	// This catches a case of memory corruption where the cursor
	// is moved between pages without accounting for style refs.
	s.set_attribute(SgrResetBg{})!
	first_node(s).data.assert_integrity()
	last_node(s).data.assert_integrity()
}

fn test_screen_scroll_above_creates_new_page() ! {
	mut s := Screen.init(10, 3, 10)!
	defer { s.deinit() }

	// We need to get the cursor to a new page
	mut first := first_node(s)
	first_page_size := int(first.data.capacity.rows)
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 3 {
		s.test_write_string('\n')!
	}
	first.data.pause_integrity_checks(false)

	s.set_attribute(sgr_bg_rgb(155, 0, 0))!
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	s.cursor_absolute(0, 1)
	s.pages.clear_dirty()

	// Ensure we're still on the first page
	assert voidptr(s.cursor.page_pin.node) == voidptr(first_node(s))

	// At this point:
	//      +----------+ = PAGE 0
	//  ... :          :
	//     +-------------+ ACTIVE
	// 4305 |1ABCD00000| | 0
	// 4306 |2EFGH00000| | 1
	//      :^         : : = PIN 0
	// 4307 |3IJKL00000| | 2
	//      +----------+ :
	//     +-------------+
	s.cursor_scroll_above()!

	//      +----------+ = PAGE 0
	//  ... :          :
	// 4305 |1ABCD00000|
	//     +-------------+ ACTIVE
	// 4306 |2EFGH00000| | 0
	// 4307 |          | | 1
	//      :^         : : = PIN 0
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |3IJKL00000| | 2
	//      +----------+ :
	//     +-------------+

	// try s.pages.diagram(std.io.getStdErr().writer());

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n\n3IJKL'
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 1))
		cell := list_cell.cell
		assert cell.content_tag == .bg_color_rgb
		assert cell.color_rgb_r() == u8(155)
		assert cell.color_rgb_g() == u8(0)
		assert cell.color_rgb_b() == u8(0)
	}

	// Page 0's penultimate row is dirty because the cursor moved off of it.
	assert s.pages.is_dirty(active_pt(0, 0))
	// Page 0's final row is dirty because it was cleared.
	assert s.pages.is_dirty(active_pt(0, 1))
	// Page 1's row is dirty because it's new.
	assert s.pages.is_dirty(active_pt(0, 2))
}

fn test_screen_scroll_above_with_cursor_on_non_final_row() ! {
	mut s := Screen.init(10, 4, 10)!
	defer { s.deinit() }

	// Get the cursor to be 2 rows above a new page
	mut first := first_node(s)
	first_page_size := int(first.data.capacity.rows)
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 3 {
		s.test_write_string('\n')!
	}
	first.data.pause_integrity_checks(false)

	// Write 3 lines of text, forcing the last line into the first
	// row of a new page. Move our cursor onto the previous page.
	s.set_attribute(sgr_bg_rgb(155, 0, 0))!
	s.test_write_string('1AB\n2BC\n3DE\n4FG')!
	s.cursor_absolute(0, 1)
	s.pages.clear_dirty()

	// Ensure we're still on the first page. So our cursor is on the first
	// page but we have two pages of data.
	assert voidptr(s.cursor.page_pin.node) == voidptr(first_node(s))

	//      +----------+ = PAGE 0
	//  ... :          :
	//     +-------------+ ACTIVE
	// 4305 |1AB0000000| | 0
	// 4306 |2BC0000000| | 1
	//      :^         : : = PIN 0
	// 4307 |3DE0000000| | 2
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |4FG0000000| | 3
	//      +----------+ :
	//     +-------------+
	s.cursor_scroll_above()!

	//     +----------+ = PAGE 0
	//  ... :          :
	// 4305 |1AB0000000|
	//     +-------------+ ACTIVE
	// 4306 |2BC0000000| | 0
	// 4307 |          | | 1
	//      :^         : : = PIN 0
	//      +----------+ :
	//      +----------+ : = PAGE 1
	//    0 |3DE0000000| | 2
	//    1 |4FG0000000| | 3
	//      +----------+ :
	//     +-------------+
	// try s.pages.diagram(std.io.getStdErr().writer());

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2BC\n\n3DE\n4FG'
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 1))
		cell := list_cell.cell
		assert cell.content_tag == .bg_color_rgb
		assert cell.color_rgb_r() == u8(155)
		assert cell.color_rgb_g() == u8(0)
		assert cell.color_rgb_b() == u8(0)
	}

	// Page 0's penultimate row is dirty because the cursor moved off of it.
	assert s.pages.is_dirty(active_pt(0, 0))
	// Page 0's final row is dirty because it was cleared.
	assert s.pages.is_dirty(active_pt(0, 1))
	// Page 1's row is dirty because it's new.
	assert s.pages.is_dirty(active_pt(0, 2))
}

fn test_screen_scroll_above_no_scrollback_bottom_of_page() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }

	mut first := first_node(s)
	first_page_size := int(first.data.capacity.rows)
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 3 {
		s.test_write_string('\n')!
	}
	first.data.pause_integrity_checks(false)

	s.set_attribute(sgr_bg_rgb(155, 0, 0))!
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!
	s.cursor_absolute(0, 1)
	s.pages.clear_dirty()

	// At this point:
	//  +-------------+ ACTIVE
	//   +----------+ : = PAGE 0
	// 0 |1ABCD00000| | 0
	// 1 |2EFGH00000| | 1
	//   :^         : : = PIN 0
	// 2 |3IJKL00000| | 2
	//   +----------+ :
	//  +-------------+

	s.cursor_scroll_above()!

	//   +----------+ = PAGE 0
	// 0 |1ABCD00000|
	//  +-------------+ ACTIVE
	// 1 |2EFGH00000| | 0
	// 2 |          | | 1
	//   :^         : : = PIN 0
	// 3 |3IJKL00000| | 2
	//   +----------+ :
	//  +-------------+

	// try s.pages.diagram(std.io.getStdErr().writer());

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n\n3IJKL'
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 1))
		cell := list_cell.cell
		assert cell.content_tag == .bg_color_rgb
		assert cell.color_rgb_r() == u8(155)
		assert cell.color_rgb_g() == u8(0)
		assert cell.color_rgb_b() == u8(0)
	}

	// Page 0 row 1 (active row 0) is dirty because the cursor moved off of it.
	assert s.pages.is_dirty(active_pt(0, 0))
	// Page 0 row 2 (active row 1) is dirty because it was cleared.
	assert s.pages.is_dirty(active_pt(0, 1))
	// Page 0 row 3 (active row 2) is dirty because it is new.
	assert s.pages.is_dirty(active_pt(0, 2))
}

fn test_screen_clone() ! {
	mut s := Screen.init(10, 3, 10)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH')!
	if true {
		contents := s.dump_string_alloc(.active)!
		assert contents == '1ABCD\n2EFGH'
	}
	assert s.cursor.x == 5
	assert s.cursor.y == 1

	// Clone
	mut s2 := s.clone(active_pt(0, 0), none)!
	defer { s2.deinit() }
	if true {
		contents := s2.dump_string_alloc(.active)!
		assert contents == '1ABCD\n2EFGH'
	}
	assert s2.cursor.x == 5
	assert s2.cursor.y == 1

	// Write to s1, should not be in s2
	s.test_write_string('\n34567')!
	if true {
		contents := s.dump_string_alloc(.active)!
		assert contents == '1ABCD\n2EFGH\n34567'
	}
	if true {
		contents := s2.dump_string_alloc(.active)!
		assert contents == '1ABCD\n2EFGH'
	}
	assert s2.cursor.x == 5
	assert s2.cursor.y == 1
}

fn test_screen_clone_partial() ! {
	mut s := Screen.init(10, 3, 10)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH')!
	if true {
		contents := s.dump_string_alloc(.active)!
		assert contents == '1ABCD\n2EFGH'
	}
	assert s.cursor.x == 5
	assert s.cursor.y == 1

	// Clone
	mut s2 := s.clone(active_pt(0, 1), none)!
	defer { s2.deinit() }
	if true {
		contents := s2.dump_string_alloc(.active)!
		assert contents == '2EFGH'
	}

	// Cursor is shifted since we cloned partial
	assert s2.cursor.x == 5
	assert s2.cursor.y == 0
}

fn test_screen_clone_partial_cursor_out_of_bounds() ! {
	mut s := Screen.init(10, 3, 10)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH')!
	if true {
		contents := s.dump_string_alloc(.active)!
		assert contents == '1ABCD\n2EFGH'
	}
	assert s.cursor.x == 5
	assert s.cursor.y == 1

	// Clone
	mut s2 := s.clone(active_pt(0, 0), active_pt(0, 0))!
	defer { s2.deinit() }
	if true {
		contents := s2.dump_string_alloc(.active)!
		assert contents == '1ABCD'
	}

	// Cursor is shifted since we cloned partial
	assert s2.cursor.x == 0
	assert s2.cursor.y == 0
}

fn test_screen_clone_contains_full_selection() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Select a single line
	s.select(Selection.init(must_pin(s, active_pt(0, 1)), must_pin(s, active_pt(int(s.pages.cols) - 1,
		1)), false))!

	// Clone
	mut s2 := s.clone(active_pt(0, 0), none)!
	defer { s2.deinit() }

	// Our selection should remain valid
	if true {
		sel := s2.selection or { panic('no selection') }
		assert must_point(s2, .active, sel.start()) == active_pt(0, 1)
		assert must_point(s2, .active, sel.end()) == active_pt(int(s2.pages.cols) - 1, 1)
	}
}

fn test_screen_clone_contains_none_of_selection() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Select a single line
	s.select(Selection.init(must_pin(s, active_pt(0, 0)), must_pin(s, active_pt(int(s.pages.cols) - 1,
		0)), false))!

	// Clone
	mut s2 := s.clone(active_pt(0, 1), none)!
	defer { s2.deinit() }

	// Our selection should be null
	assert s2.selection == none
}

fn test_screen_clone_contains_selection_start_cutoff() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Select a single line
	s.select(Selection.init(must_pin(s, active_pt(0, 0)), must_pin(s, active_pt(int(s.pages.cols) - 1,
		1)), false))!

	// Clone
	mut s2 := s.clone(active_pt(0, 1), none)!
	defer { s2.deinit() }

	// Our selection should remain valid
	if true {
		sel := s2.selection or { panic('no selection') }
		assert must_point(s2, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s2, .active, sel.end()) == active_pt(int(s2.pages.cols) - 1, 0)
	}
}

fn test_screen_clone_contains_selection_end_cutoff() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Select a single line
	s.select(Selection.init(must_pin(s, active_pt(0, 1)), must_pin(s, active_pt(2, 2)),
		false))!

	// Clone
	mut s2 := s.clone(active_pt(0, 0), active_pt(0, 1))!
	defer { s2.deinit() }

	// Our selection should remain valid
	if true {
		sel := s2.selection or { panic('no selection') }
		assert must_point(s2, .active, sel.start()) == active_pt(0, 1)
		assert must_point(s2, .active, sel.end()) == active_pt(int(s2.pages.cols) - 1, 2)
	}
}

fn test_screen_clone_contains_selection_end_cutoff_reversed() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	// Select a single line
	s.select(Selection.init(must_pin(s, active_pt(2, 2)), must_pin(s, active_pt(0, 1)),
		false))!

	// Clone
	mut s2 := s.clone(active_pt(0, 0), active_pt(0, 1))!
	defer { s2.deinit() }

	// Our selection should remain valid
	if true {
		sel := s2.selection or { panic('no selection') }
		assert must_point(s2, .active, sel.start()) == active_pt(0, 1)
		assert must_point(s2, .active, sel.end()) == active_pt(int(s2.pages.cols) - 1, 2)
	}
}

fn test_screen_clone_contains_subset_of_selection() ! {
	mut s := Screen.init(5, 4, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n4ABCD')!

	// Select the full screen
	s.select(Selection.init(must_pin(s, active_pt(0, 0)), must_pin(s, active_pt(0, 3)),
		false))!

	// Clone
	mut s2 := s.clone(active_pt(0, 1), active_pt(0, 2))!
	defer { s2.deinit() }

	// Our selection should remain valid
	if true {
		sel := s2.selection or { panic('no selection') }
		assert must_point(s2, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s2, .active, sel.end()) == active_pt(int(s2.pages.cols) - 1, 3)
	}
}

fn test_screen_clone_contains_subset_of_rectangle_selection() ! {
	mut s := Screen.init(5, 4, 1)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n4ABCD')!

	// Select the full screen from x=1 to x=3
	s.select(Selection.init(must_pin(s, active_pt(1, 0)), must_pin(s, active_pt(3, 3)),
		true))!

	// Clone
	mut s2 := s.clone(active_pt(0, 1), active_pt(0, 2))!
	defer { s2.deinit() }

	// Our selection should remain valid and be properly clipped
	// preserving the columns of the start and end points of the
	// selection.
	if true {
		sel := s2.selection or { panic('no selection') }
		assert must_point(s2, .active, sel.start()) == active_pt(1, 0)
		assert must_point(s2, .active, sel.end()) == active_pt(3, 3)
	}
}

fn test_screen_clone_basic() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL')!

	if true {
		mut s2 := s.clone(active_pt(0, 1), active_pt(0, 1))!
		defer { s2.deinit() }

		// Test our contents rotated
		contents := s2.dump_string_alloc(.active)!
		assert contents == '2EFGH'
	}

	if true {
		mut s2 := s.clone(active_pt(0, 1), active_pt(0, 2))!
		defer { s2.deinit() }

		// Test our contents rotated
		contents := s2.dump_string_alloc(.active)!
		assert contents == '2EFGH\n3IJKL'
	}
}

fn test_screen_clone_empty_viewport() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }

	if true {
		mut s2 := s.clone(viewport_pt(0, 0), viewport_pt(0, 0))!
		defer { s2.deinit() }

		// Test our contents rotated
		contents := s2.dump_string_alloc(.viewport)!
		assert contents == ''
	}
}

fn test_screen_clone_one_line_viewport() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.test_write_string('1ABC')!

	if true {
		mut s2 := s.clone(viewport_pt(0, 0), viewport_pt(0, 0))!
		defer { s2.deinit() }

		// Test our contents
		contents := s2.dump_string_alloc(.viewport)!
		assert contents == '1ABC'
	}
}

fn test_screen_clone_empty_active() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }

	if true {
		mut s2 := s.clone(active_pt(0, 0), active_pt(0, 0))!
		defer { s2.deinit() }

		// Test our contents rotated
		contents := s2.dump_string_alloc(.active)!
		assert contents == ''
	}
}

fn test_screen_clone_one_line_active_with_extra_space() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.test_write_string('1ABC')!

	if true {
		mut s2 := s.clone(active_pt(0, 0), none)!
		defer { s2.deinit() }

		// Test our contents rotated
		contents := s2.dump_string_alloc(.active)!
		assert contents == '1ABC'
	}
}

fn test_screen_clear_history_with_no_history() ! {
	mut s := Screen.init(10, 3, 3)!
	defer { s.deinit() }
	s.test_write_string('4ABCD\n5EFGH\n6IJKL')!
	assert s.pages.viewport == .active
	s.erase_rows(history_pt(0, 0), none)
	assert s.pages.viewport == .active
	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '4ABCD\n5EFGH\n6IJKL'
	}
	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.screen)!
		assert contents == '4ABCD\n5EFGH\n6IJKL'
	}
}

fn test_screen_clear_history() ! {
	mut s := Screen.init(10, 3, 3)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH\n6IJKL')!
	assert s.pages.viewport == .active

	// Scroll to top
	s.scroll(ScrollTop{})
	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD\n2EFGH\n3IJKL'
	}

	s.erase_rows(history_pt(0, 0), none)
	assert s.pages.viewport == .active
	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '4ABCD\n5EFGH\n6IJKL'
	}
	if true {
		// Test our contents rotated
		contents := s.dump_string_alloc(.screen)!
		assert contents == '4ABCD\n5EFGH\n6IJKL'
	}
}

fn test_screen_clear_above_cursor() ! {
	mut s := Screen.init(10, 10, 3)!
	defer { s.deinit() }
	s.test_write_string('4ABCD\n5EFGH\n6IJKL')!
	s.clear_rows(active_pt(0, 0), active_pt(0, int(s.cursor.y) - 1), false)
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '\n\n6IJKL'
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '\n\n6IJKL'
	}

	assert s.cursor.x == 5
	assert s.cursor.y == 2
}

fn test_screen_clear_above_cursor_with_history() ! {
	mut s := Screen.init(10, 3, 3)!
	defer { s.deinit() }
	s.test_write_string('1ABCD\n2EFGH\n3IJKL\n')!
	s.test_write_string('4ABCD\n5EFGH\n6IJKL')!
	s.clear_rows(active_pt(0, 0), active_pt(0, int(s.cursor.y) - 1), false)
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '\n\n6IJKL'
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '1ABCD\n2EFGH\n3IJKL\n\n\n6IJKL'
	}

	assert s.cursor.x == 5
	assert s.cursor.y == 2
}

fn test_screen_resize_no_reflow_more_rows() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	// Resize
	s.resize(ScreenResize{ cols: 10, rows: 10, reflow: false })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
}

fn test_screen_resize_no_reflow_less_rows() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!
	assert s.cursor.x == 5
	assert s.cursor.y == 2
	s.resize(ScreenResize{ cols: 10, rows: 2, reflow: false })!

	// Since we shrunk, we should adjust our cursor
	assert s.cursor.x == 5
	assert s.cursor.y == 1

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2EFGH\n3IJKL'
	}
}

fn test_screen_resize_no_reflow_less_rows_trims_blank_lines() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD'
	s.test_write_string(str)!

	// Write only a background color into the remaining rows
	for y in 1 .. int(s.pages.rows) {
		list_cell := must_cell(s, active_pt(0, y))
		mut cell := list_cell.cell
		unsafe {
			*cell = CellData.from_color_payload(.bg_color_rgb, u32(0xFF) | (u32(0) << 8) | (u32(0) << 16))
		}
	}

	cursor := s.cursor
	s.resize(ScreenResize{ cols: 6, rows: 2, reflow: false })!

	// Cursor should not move
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD'
	}
}

fn test_screen_resize_no_reflow_more_rows_trims_blank_lines() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD'
	s.test_write_string(str)!

	// Write only a background color into the remaining rows
	for y in 1 .. int(s.pages.rows) {
		list_cell := must_cell(s, active_pt(0, y))
		mut cell := list_cell.cell
		unsafe {
			*cell = CellData.from_color_payload(.bg_color_rgb, u32(0xFF) | (u32(0) << 8) | (u32(0) << 16))
		}
	}

	cursor := s.cursor
	s.resize(ScreenResize{ cols: 10, rows: 7, reflow: false })!

	// Cursor should not move
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '1ABCD'
	}
}

fn test_screen_resize_no_reflow_more_cols() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 20, rows: 3, reflow: false })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
}

fn test_screen_resize_no_reflow_less_cols() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 4, rows: 3, reflow: false })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1ABC\n2EFG\n3IJK'
		assert contents == expected
	}
}

fn test_screen_resize_no_reflow_more_rows_with_scrollback_cursor_end() ! {
	mut s := Screen.init(7, 3, 2)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 7, rows: 10, reflow: false })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
}

fn test_screen_resize_no_reflow_less_rows_with_scrollback() ! {
	mut s := Screen.init(7, 3, 2)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 7, rows: 2, reflow: false })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '4ABCD\n5EFGH'
		assert contents == expected
	}
}

// https://github.com/mitchellh/ghostty/issues/1030
fn test_screen_resize_no_reflow_less_rows_with_empty_trailing() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1\n2\n3\n4\n5\n6\n7\n8'
	s.test_write_string(str)!
	s.scroll_clear()!
	s.cursor_absolute(0, 0)
	s.test_write_string('A\nB')!

	cursor := s.cursor
	s.resize(ScreenResize{ cols: 5, rows: 2, reflow: false })!
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == 'A\nB'
	}
}

fn test_screen_resize_no_reflow_more_rows_with_soft_wrapping() ! {
	mut s := Screen.init(2, 3, 3)!
	defer { s.deinit() }
	str := '1A2B\n3C4E\n5F6G'
	s.test_write_string(str)!

	// Every second row should be wrapped
	for y in 0 .. 6 {
		list_cell := must_cell(s, screen_pt(0, y))
		row := list_cell.row
		wrapped := (y % 2 == 0)
		assert row.header.wrap == wrapped
	}

	// Resize
	s.resize(ScreenResize{ cols: 2, rows: 10, reflow: false })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1A\n2B\n3C\n4E\n5F\n6G'
		assert contents == expected
	}

	// Every second row should be wrapped
	for y in 0 .. 6 {
		list_cell := must_cell(s, screen_pt(0, y))
		row := list_cell.row
		wrapped := (y % 2 == 0)
		assert row.header.wrap == wrapped
	}
}

fn test_screen_resize_more_rows_no_scrollback() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!
	cursor := s.cursor
	s.resize(ScreenResize{ cols: 5, rows: 10 })!

	// Cursor should not move
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
}

fn test_screen_resize_more_rows_with_empty_scrollback() ! {
	mut s := Screen.init(5, 3, 10)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!
	cursor := s.cursor
	s.resize(ScreenResize{ cols: 5, rows: 10 })!

	// Cursor should not move
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
}

fn test_screen_resize_more_rows_with_populated_scrollback() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}

	// Set our cursor to be on the "4"
	s.cursor_absolute(0, 1)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`4`)
	}

	// Resize
	s.resize(ScreenResize{ cols: 5, rows: 10 })!

	// Cursor should still be on the "4"
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`4`)
	}

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}
}

fn test_screen_resize_more_cols_no_reflow() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	cursor := s.cursor
	s.resize(ScreenResize{ cols: 10, rows: 3 })!

	// Cursor should not move
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
}

// https://github.com/mitchellh/ghostty/issues/272#issuecomment-1676038963
fn test_screen_resize_more_cols_perfect_split() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD2EFGH3IJKL'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 10, rows: 3 })!

	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '1ABCD2EFGH\n3IJKL'
	}
}

// https://github.com/mitchellh/ghostty/issues/1159
fn test_screen_resize_no_reflow_more_cols_with_scrollback_scrolled_up() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1\n2\n3\n4\n5\n6\n7\n8'
	s.test_write_string(str)!

	// Cursor at bottom
	assert s.cursor.x == 1
	assert s.cursor.y == 2

	s.scroll(ScrollDeltaRow{ delta: -4 })
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2\n3\n4'
	}

	s.resize(ScreenResize{ cols: 8, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}

	// Cursor remains at bottom
	assert s.cursor.x == 1
	assert s.cursor.y == 2
}

// https://github.com/mitchellh/ghostty/issues/1159
fn test_screen_resize_no_reflow_less_cols_with_scrollback_scrolled_up() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1\n2\n3\n4\n5\n6\n7\n8'
	s.test_write_string(str)!

	// Cursor at bottom
	assert s.cursor.x == 1
	assert s.cursor.y == 2

	s.scroll(ScrollDeltaRow{ delta: -4 })
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '2\n3\n4'
	}

	s.resize(ScreenResize{ cols: 4, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.active)!
		assert contents == '6\n7\n8'
	}

	// Cursor remains at bottom
	assert s.cursor.x == 1
	assert s.cursor.y == 2

	// Old implementation doesn't do this but it makes sense to me:
	// {
	//     const contents = try s.dumpStringAlloc(alloc, .{ .viewport = .{} });
	//     defer alloc.free(contents);
	//     try testing.expectEqualStrings("2\n3\n4", contents);
	// }
}

fn test_screen_resize_more_cols_no_reflow_preserves_semantic_prompt() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }

	// Set one of the rows to be a prompt
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('1ABCD\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('2EFGH')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('\n3IJKL')!

	s.resize(ScreenResize{ cols: 10, rows: 3, reflow: false })!

	expected := '1ABCD\n2EFGH\n3IJKL'
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == expected
	}

	// Our one row should still be a semantic prompt, the others should not.
	if true {
		list_cell := must_cell(s, active_pt(0, 0))
		assert list_cell.row.header.semantic_prompt == .unknown
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 1))
		assert list_cell.row.header.semantic_prompt == .prompt
	}
	if true {
		list_cell := must_cell(s, active_pt(0, 2))
		assert list_cell.row.header.semantic_prompt == .unknown
	}
}

fn test_screen_resize_more_cols_with_reflow_that_fits_full_width() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD2EFGH\n3IJKL'
	s.test_write_string(str)!

	// Verify we soft wrapped
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1ABCD\n2EFGH\n3IJKL'
		assert contents == expected
	}

	// Let's put our cursor on row 2, where the soft wrap is
	s.cursor_absolute(0, 1)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`2`)
	}

	// Resize and verify we undid the soft wrap because we have space now
	s.resize(ScreenResize{ cols: 10, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}

	// Our cursor should've moved
	assert s.cursor.x == 5
	assert s.cursor.y == 0
}

fn test_screen_resize_more_cols_with_reflow_that_ends_in_newline() ! {
	mut s := Screen.init(6, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD2EFGH\n3IJKL'
	s.test_write_string(str)!

	// Verify we soft wrapped
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1ABCD2\nEFGH\n3IJKL'
		assert contents == expected
	}

	// Let's put our cursor on the last row
	s.cursor_absolute(0, 2)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`3`)
	}

	// Resize and verify we undid the soft wrap because we have space now
	s.resize(ScreenResize{ cols: 10, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}

	// Our cursor should still be on the 3
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`3`)
	}
}

fn test_screen_resize_more_cols_with_reflow_that_forces_more_wrapping() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD2EFGH\n3IJKL'
	s.test_write_string(str)!

	// Let's put our cursor on row 2, where the soft wrap is
	s.cursor_absolute(0, 1)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`2`)
	}

	// Verify we soft wrapped
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1ABCD\n2EFGH\n3IJKL'
		assert contents == expected
	}

	// Resize and verify we undid the soft wrap because we have space now
	s.resize(ScreenResize{ cols: 7, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1ABCD2E\nFGH\n3IJKL'
		assert contents == expected
	}

	// Our cursor should've moved
	assert s.cursor.x == 5
	assert s.cursor.y == 0
}

fn test_screen_resize_more_cols_with_reflow_that_unwraps_multiple_times() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD2EFGH3IJKL'
	s.test_write_string(str)!

	// Let's put our cursor on row 2, where the soft wrap is
	s.cursor_absolute(0, 2)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`3`)
	}

	// Verify we soft wrapped
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1ABCD\n2EFGH\n3IJKL'
		assert contents == expected
	}

	// Resize and verify we undid the soft wrap because we have space now
	s.resize(ScreenResize{ cols: 15, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1ABCD2EFGH3IJKL'
		assert contents == expected
	}

	// Our cursor should've moved
	assert s.cursor.x == 10
	assert s.cursor.y == 0
}

fn test_screen_resize_more_cols_with_populated_scrollback() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL\n4ABCD5EFGH'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}

	// // Set our cursor to be on the "5"
	s.cursor_absolute(0, 2)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`5`)
	}

	// Resize
	s.resize(ScreenResize{ cols: 10, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '2EFGH\n3IJKL\n4ABCD5EFGH'
		assert contents == expected
	}

	// Cursor should still be on the "5"
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`5`)
	}
}

fn test_screen_resize_more_cols_with_reflow() ! {
	mut s := Screen.init(2, 3, 5)!
	defer { s.deinit() }
	str := '1ABC\n2DEF\n3ABC\n4DEF'
	s.test_write_string(str)!

	// Let's put our cursor on row 2, where the soft wrap is
	s.cursor_absolute(0, 2)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`E`)
	}

	// Verify we soft wrapped
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'BC\n4D\nEF'
		assert contents == expected
	}

	// Resize and verify we undid the soft wrap because we have space now
	s.resize(ScreenResize{ cols: 7, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '1ABC\n2DEF\n3ABC\n4DEF'
		assert contents == expected
	}

	// Our cursor should've moved
	assert s.cursor.x == 2
	assert s.cursor.y == 2
}

fn test_screen_resize_more_rows_and_cols_with_wrapping() ! {
	mut s := Screen.init(2, 4, 0)!
	defer { s.deinit() }
	str := '1A2B\n3C4D'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1A\n2B\n3C\n4D'
		assert contents == expected
	}

	s.resize(ScreenResize{ cols: 5, rows: 10 })!

	// Cursor should move due to wrapping
	assert s.cursor.x == 3
	assert s.cursor.y == 1

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
}

fn test_screen_resize_less_rows_no_scrollback() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	s.cursor_absolute(0, 0)
	cursor := s.cursor
	s.resize(ScreenResize{ cols: 5, rows: 1 })!

	// Cursor should not move
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '3IJKL'
		assert contents == expected
	}
}

fn test_screen_resize_less_rows_moving_cursor() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	// Put our cursor on the last line
	s.cursor_absolute(1, 2)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`I`)
	}

	// Resize
	s.resize(ScreenResize{ cols: 5, rows: 1 })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '3IJKL'
		assert contents == expected
	}

	// Cursor should be on the last line
	assert s.cursor.x == u32(1)
	assert s.cursor.y == u32(0)
}

fn test_screen_resize_less_rows_with_empty_scrollback() ! {
	mut s := Screen.init(5, 3, 10)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 5, rows: 1 })!

	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL'
		assert contents == expected
	}
}

fn test_screen_resize_less_rows_with_populated_scrollback() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}

	// Resize
	s.resize(ScreenResize{ cols: 5, rows: 1 })!

	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '5EFGH'
		assert contents == expected
	}
}

fn test_screen_resize_less_rows_with_full_scrollback() ! {
	mut s := Screen.init(5, 3, 3)!
	defer { s.deinit() }
	str := '00000\n1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}

	assert s.cursor.x == u32(4)
	assert s.cursor.y == u32(2)

	// Resize
	s.resize(ScreenResize{ cols: 5, rows: 2 })!

	// Cursor should stay in the same relative place (bottom of the
	// screen, same character).
	assert s.cursor.x == u32(4)
	assert s.cursor.y == u32(1)

	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '00000\n1ABCD\n2EFGH\n3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '4ABCD\n5EFGH'
		assert contents == expected
	}
}

fn test_screen_resize_less_cols_no_reflow() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1AB\n2EF\n3IJ'
	s.test_write_string(str)!

	s.cursor_absolute(0, 0)
	cursor := s.cursor
	s.resize(ScreenResize{ cols: 3, rows: 3 })!

	// Cursor should not move
	assert s.cursor.x == cursor.x
	assert s.cursor.y == cursor.y

	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
}

fn test_screen_resize_less_cols_with_reflow_but_row_space() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	str := '1ABCD'
	s.test_write_string(str)!

	// Put our cursor on the end
	s.cursor_absolute(4, 0)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`D`)
	}

	s.resize(ScreenResize{ cols: 3, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '1AB\nCD'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '1AB\nCD'
		assert contents == expected
	}

	// Cursor should be on the last line
	assert s.cursor.x == u32(1)
	assert s.cursor.y == u32(1)
}

fn test_screen_resize_less_cols_with_reflow_with_trimmed_rows() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '3IJKL\n4ABCD\n5EFGH'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 3, rows: 3 })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'CD\n5EF\nGH'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := 'CD\n5EF\nGH'
		assert contents == expected
	}
}

fn test_screen_resize_less_cols_with_reflow_with_trimmed_rows_and_scrollback() ! {
	mut s := Screen.init(5, 3, 1)!
	defer { s.deinit() }
	str := '3IJKL\n4ABCD\n5EFGH'
	s.test_write_string(str)!
	s.resize(ScreenResize{ cols: 3, rows: 3 })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'CD\n5EF\nGH'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '3IJ\nKL\n4AB\nCD\n5EF\nGH'
		assert contents == expected
	}
}

fn test_screen_resize_less_cols_with_reflow_previously_wrapped() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '3IJKL4ABCD5EFGH'
	s.test_write_string(str)!

	// Check
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}

	s.resize(ScreenResize{ cols: 3, rows: 3 })!

	// {
	//     const contents = try s.testString(alloc, .viewport);
	//     defer alloc.free(contents);
	//     const expected = "CD\n5EF\nGH";
	//     try testing.expectEqualStrings(expected, contents);
	// }
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := 'ABC\nD5E\nFGH'
		assert contents == expected
	}
}

fn test_screen_resize_less_cols_with_reflow_and_scrollback() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1A\n2B\n3C\n4D\n5E'
	s.test_write_string(str)!

	// Put our cursor on the end
	s.cursor_absolute(1, u32(s.pages.rows) - 1)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`E`)
	}

	s.resize(ScreenResize{ cols: 3, rows: 3 })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3C\n4D\n5E'
		assert contents == expected
	}

	// Cursor should be on the last line
	assert s.cursor.x == u32(1)
	assert s.cursor.y == u32(2)
}

fn test_screen_resize_less_cols_with_reflow_previously_wrapped_and_scrollback() ! {
	mut s := Screen.init(5, 3, 2)!
	defer { s.deinit() }
	str := '1ABCD2EFGH3IJKL4ABCD5EFGH'
	s.test_write_string(str)!

	// Check
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '3IJKL\n4ABCD\n5EFGH'
		assert contents == expected
	}

	// Put our cursor on the end
	s.cursor_absolute(u32(s.pages.cols) - 1, u32(s.pages.rows) - 1)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`H`)
	}

	s.resize(ScreenResize{ cols: 3, rows: 3 })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'CD5\nEFG\nH'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '1AB\nCD2\nEFG\nH3I\nJKL\n4AB\nCD5\nEFG\nH'
		assert contents == expected
	}

	// Cursor should be on the last line
	assert s.cursor.x == u32(0)
	assert s.cursor.y == u32(2)
	if true {
		list_cell := must_cell(s, active_pt(int(s.cursor.x), int(s.cursor.y)))
		assert list_cell.cell.codepoint == u32(`H`)
	}
}

fn test_screen_resize_less_cols_with_scrollback_keeps_cursor_row() ! {
	mut s := Screen.init(5, 3, 5)!
	defer { s.deinit() }
	str := '1A\n2B\n3C\n4D\n5E'
	s.test_write_string(str)!

	// Lets do a scroll and clear operation
	s.scroll_clear()!

	// Move our cursor to the beginning
	s.cursor_absolute(0, 0)

	s.resize(ScreenResize{ cols: 3, rows: 3 })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := ''
		assert contents == expected
	}

	// Cursor should be on the last line
	assert s.cursor.x == u32(0)
	assert s.cursor.y == u32(0)
}

fn test_screen_resize_more_rows_less_cols_with_reflow_with_scrollback() ! {
	mut s := Screen.init(5, 3, 3)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH3IJKL\n4MNOP'
	s.test_write_string(str)!

	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '1ABCD\n2EFGH\n3IJKL\n4MNOP'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := '2EFGH\n3IJKL\n4MNOP'
		assert contents == expected
	}

	s.resize(ScreenResize{ cols: 2, rows: 10 })!

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'BC\nD\n2E\nFG\nH3\nIJ\nKL\n4M\nNO\nP'
		assert contents == expected
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		expected := '1A\nBC\nD\n2E\nFG\nH3\nIJ\nKL\n4M\nNO\nP'
		assert contents == expected
	}
}

// This seems like it should work fine but for some reason in practice
// in the initial implementation I found this bug! This is a regression
// test for that.
fn test_screen_resize_more_rows_then_shrink_again() ! {
	mut s := Screen.init(5, 3, 10)!
	defer { s.deinit() }
	str := '1ABC'
	s.test_write_string(str)!

	// Grow
	s.resize(ScreenResize{ cols: 5, rows: 10 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}

	// Shrink
	s.resize(ScreenResize{ cols: 5, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}

	// Grow again
	s.resize(ScreenResize{ cols: 5, rows: 10 })!
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == str
	}
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
}

fn test_screen_resize_less_cols_to_eliminate_wide_char() ! {
	mut s := Screen.init(2, 1, 0)!
	defer { s.deinit() }
	str := '😀'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		list_cell := must_cell(s, screen_pt(0, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
		assert cell.codepoint == u32(`😀`)
	}

	// Resize to 1 column can't fit a wide char. So it should be deleted.
	s.resize(ScreenResize{ cols: 1, rows: 1 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == ''
	}
	if true {
		list_cell := must_cell(s, screen_pt(0, 0))
		cell := list_cell.cell
		assert cell.codepoint == u32(0)
		assert cell.wide == CellWide.narrow
	}
}

fn test_screen_resize_less_cols_to_wrap_wide_char() ! {
	mut s := Screen.init(3, 3, 0)!
	defer { s.deinit() }
	str := 'x😀'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		list_cell := must_cell(s, screen_pt(1, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
		assert cell.codepoint == u32(`😀`)
	}
	if true {
		list_cell := must_cell(s, screen_pt(2, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}

	s.resize(ScreenResize{ cols: 2, rows: 3 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == 'x\n😀'
	}
	if true {
		list_cell := must_cell(s, screen_pt(1, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_head
		assert list_cell.row.header.wrap
	}
}

fn test_screen_resize_less_cols_to_eliminate_wide_char_with_row_space() ! {
	mut s := Screen.init(2, 2, 0)!
	defer { s.deinit() }
	str := '😀'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		list_cell := must_cell(s, screen_pt(0, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
		assert cell.codepoint == u32(`😀`)
	}
	if true {
		list_cell := must_cell(s, screen_pt(1, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}

	s.resize(ScreenResize{ cols: 1, rows: 2 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == ''
	}
}

fn test_screen_resize_more_cols_with_wide_spacer_head() ! {
	mut s := Screen.init(3, 2, 0)!
	defer { s.deinit() }
	str := '  😀'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '  \n😀'
	}

	// So this is the key point: we end up with a wide spacer head at
	// the end of row 1, then the emoji, then a wide spacer tail on row 2.
	// We should expect that if we resize to more cols, the wide spacer
	// head is replaced with the emoji.
	if true {
		list_cell := must_cell(s, screen_pt(2, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_head
	}
	if true {
		list_cell := must_cell(s, screen_pt(0, 1))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
	}
	if true {
		list_cell := must_cell(s, screen_pt(1, 1))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}

	s.resize(ScreenResize{ cols: 4, rows: 2 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		list_cell := must_cell(s, screen_pt(2, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
		assert cell.codepoint == u32(`😀`)
	}
	if true {
		list_cell := must_cell(s, screen_pt(3, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}
}

fn test_screen_resize_more_cols_with_wide_spacer_head_multiple_lines() ! {
	mut s := Screen.init(3, 3, 0)!
	defer { s.deinit() }
	str := 'xxxyy😀'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == 'xxx\nyy\n😀'
	}

	// Similar to the "wide spacer head" test, but this time we'er going
	// to increase our columns such that multiple rows are unwrapped.
	if true {
		list_cell := must_cell(s, screen_pt(2, 1))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_head
	}
	if true {
		list_cell := must_cell(s, screen_pt(0, 2))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
	}
	if true {
		list_cell := must_cell(s, screen_pt(1, 2))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}

	s.resize(ScreenResize{ cols: 8, rows: 2 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == str
	}
	if true {
		list_cell := must_cell(s, screen_pt(5, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
		assert cell.codepoint == u32(`😀`)
	}
	if true {
		list_cell := must_cell(s, screen_pt(6, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}
}

fn test_screen_resize_more_cols_requiring_a_wide_spacer_head() ! {
	mut s := Screen.init(2, 2, 0)!
	defer { s.deinit() }
	str := 'xx😀'
	s.test_write_string(str)!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == 'xx\n😀'
	}
	if true {
		list_cell := must_cell(s, screen_pt(0, 1))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
	}
	if true {
		list_cell := must_cell(s, screen_pt(1, 1))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}

	// This resizes to 3 columns, which isn't enough space for our wide
	// char to enter row 1. But we need to mark the wide spacer head on the
	// end of the first row since we're wrapping to the next row.
	s.resize(ScreenResize{ cols: 3, rows: 2 })!
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == 'xx\n😀'
	}
	if true {
		list_cell := must_cell(s, screen_pt(2, 0))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_head
	}
	if true {
		list_cell := must_cell(s, screen_pt(0, 1))
		cell := list_cell.cell
		assert cell.wide == CellWide.wide
		assert cell.codepoint == u32(`😀`)
	}
	if true {
		list_cell := must_cell(s, screen_pt(1, 1))
		cell := list_cell.cell
		assert cell.wide == CellWide.spacer_tail
	}
}

fn test_screen_resize_more_cols_with_cursor_at_prompt() ! {
	mut s := Screen.init(10, 3, 5)!
	defer { s.deinit() }

	// zig fmt: off
	s.test_write_string('ABCDE\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_eol })
	s.test_write_string('echo')!
	// zig fmt: on

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'ABCDE\n> echo'
		assert contents == expected
	}

	s.resize(ScreenResize{
		cols:          20
		rows:          3
		prompt_redraw: .redraw_true
	})!

	// Cursor should not move
	assert s.cursor.x == 6
	assert s.cursor.y == 1

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'ABCDE'
		assert contents == expected
	}
}

fn test_screen_resize_more_cols_with_cursor_not_at_prompt() ! {
	mut s := Screen.init(10, 3, 5)!
	defer { s.deinit() }

	// zig fmt: off
	s.test_write_string('ABCDE\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_eol })
	s.test_write_string('echo\n')!
	s.test_write_string('output')!
	// zig fmt: on

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'ABCDE\n> echo\noutput'
		assert contents == expected
	}

	s.resize(ScreenResize{
		cols:          20
		rows:          3
		prompt_redraw: .redraw_true
	})!

	// Cursor should not move
	assert s.cursor.x == 6
	assert s.cursor.y == 2

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'ABCDE\n> echo\noutput'
		assert contents == expected
	}
}

fn test_screen_resize_with_prompt_redraw_last_clears_only_one_line() ! {
	mut s := Screen.init(10, 4, 5)!
	defer { s.deinit() }

	// zig fmt: off
	s.test_write_string('ABCDE\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello\n')!
	s.test_write_string('world')!
	// zig fmt: on

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'ABCDE\n> hello\nworld'
		assert contents == expected
	}

	// Cursor is at end of "world" line with semantic_content = .input
	s.resize(ScreenResize{
		cols:          20
		rows:          4
		prompt_redraw: .last
	})!

	// With .last, only the current line where cursor is should be cleared
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'ABCDE\n> hello'
		assert contents == expected
	}
}

fn test_screen_resize_with_prompt_redraw_last_multiline_prompt_clears_only_last_line() ! {
	mut s := Screen.init(20, 5, 5)!
	defer { s.deinit() }

	// Create a 3-line prompt: 1 initial + 2 continuation lines
	// zig fmt: off
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('line1\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .continuation })
	s.test_write_string('line2\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .continuation })
	s.test_write_string('line3')!
	// zig fmt: on

	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'line1\nline2\nline3'
		assert contents == expected
	}

	// Cursor is at end of line3 (the last continuation line)
	s.resize(ScreenResize{
		cols:          30
		rows:          5
		prompt_redraw: .last
	})!

	// With .last, only line3 (where cursor is) should be cleared
	if true {
		contents := s.dump_string_alloc(.viewport)!
		expected := 'line1\nline2'
		assert contents == expected
	}
}

fn test_screen_select_untracked() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }
	s.test_write_string('ABC  DEF\n 123\n456')!

	assert s.selection == none
	tracked := s.pages.count_tracked_pins()
	s.select(Selection.init(must_pin(s, active_pt(0, 0)), must_pin(s, active_pt(3, 0)),
		false))!
	assert s.pages.count_tracked_pins() == tracked + 2
	s.select(none)!
	assert s.pages.count_tracked_pins() == tracked
}

fn test_screen_select_all() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	if true {
		s.test_write_string('ABC  DEF\n 123\n456')!
		sel := s.select_all() or { panic('no selection') }
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 2)
	}

	if true {
		s.test_write_string('\nFOO\n BAR\n BAZ\n QWERTY\n 12345678')!
		sel := s.select_all() or { panic('no selection') }
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(8, 7)
	}
}

fn test_screen_select_line() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }
	s.test_write_string('ABC  DEF\n 123\n456')!

	// Outside of active area
	// try testing.expect(s.selectLine(.{ .x = 13, .y = 0 }) == null);
	// try testing.expect(s.selectLine(.{ .x = 0, .y = 5 }) == null);

	// Going forward
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(0, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(7, 0)
	}

	// Going backward
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(7, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(7, 0)
	}

	// Going forward and backward
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(3, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(7, 0)
	}

	// Outside active area
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(9, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(7, 0)
	}
}

fn test_screen_select_line_across_soft_wrap() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	s.test_write_string(' 12 34012   \n 123')!

	// Going forward
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(1, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(3, 1)
	}
}

fn test_screen_select_line_across_full_soft_wrap() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	s.test_write_string('1ABCD2EFGH\n3IJKL')!

	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(2, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(4, 1)
	}
}

fn test_screen_select_line_across_soft_wrap_ignores_blank_lines() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	s.test_write_string(' 12 34012             \n 123')!

	// Going forward
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(1, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(3, 1)
	}

	// Going backward
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(1, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(3, 1)
	}

	// Going forward and backward
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(3, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(3, 1)
	}
}

fn test_screen_select_line_disabled_whitespace_trimming() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	s.test_write_string(' 12 34012   \n 123')!

	// Going forward
	if true {
		sel := s.select_line(SelectLine{
			pin:        must_pin(s, active_pt(1, 0))
			whitespace: none
		}) or { panic('no line selection') }
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(4, 2)
	}

	// Non-wrapped
	if true {
		sel := s.select_line(SelectLine{
			pin:        must_pin(s, active_pt(1, 3))
			whitespace: none
		}) or { panic('no line selection') }
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 3)
		assert must_point(s, .screen, sel.end()) == screen_pt(4, 3)
	}
}

fn test_screen_select_line_with_scrollback() ! {
	mut s := Screen.init(2, 3, 5)!
	defer { s.deinit() }
	s.test_write_string('1A\n2B\n3C\n4D\n5E')!

	// Selecting first line
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(0, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s, .active, sel.end()) == active_pt(1, 0)
	}

	// Selecting last line
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(0, 2)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 2)
		assert must_point(s, .active, sel.end()) == active_pt(1, 2)
	}
}

// https://github.com/mitchellh/ghostty/issues/1329
fn test_screen_select_line_semantic_prompt_boundary() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	s.test_write_string('ABCDE\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('A    ')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('> ')!

	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == 'ABCDE\nA    \n> '
	}

	// Selecting output stops at the prompt even if soft-wrapped
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(1, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		expected := 'A'
		assert contents == expected
	}
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(1, 2)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 2)
		assert must_point(s, .active, sel.end()) == active_pt(0, 2)
	}
}

fn test_screen_select_line_semantic_prompt_to_input_boundary() ! {
	mut s := Screen.init(10, 5, 0)!
	defer { s.deinit() }

	// Write prompt followed by user input on same row: "$>command"
	// Using non-whitespace to avoid whitespace trimming affecting the test
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('$>')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('command')!

	// Selecting from prompt should only select prompt
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(0, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s, .active, sel.end()) == active_pt(1, 0)
	}

	// Selecting from input should only select input
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(5, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(2, 0)
		assert must_point(s, .active, sel.end()) == active_pt(8, 0)
	}
}

fn test_screen_select_line_semantic_input_to_output_boundary() ! {
	mut s := Screen.init(10, 5, 0)!
	defer { s.deinit() }

	// Row 0: user input
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('ls -la\n')!
	// Row 1: command output
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('file.txt')!

	// Selecting from input should only select input
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(2, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'ls -la'
	}

	// Selecting from output should only select output
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(2, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'file.txt'
	}
}

fn test_screen_select_line_semantic_mid_row_boundary() ! {
	mut s := Screen.init(10, 5, 0)!
	defer { s.deinit() }

	// Single row with output then prompt then input: "out$>cmd"
	// Using non-whitespace to avoid whitespace trimming affecting the test
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('out')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('$>')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('cmd')!

	// Selecting from output should stop at prompt
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(1, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s, .active, sel.end()) == active_pt(2, 0)
	}

	// Selecting from prompt should only select prompt
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(3, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(3, 0)
		assert must_point(s, .active, sel.end()) == active_pt(4, 0)
	}

	// Selecting from input should only select input
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(6, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(5, 0)
		assert must_point(s, .active, sel.end()) == active_pt(7, 0)
	}
}

fn test_screen_select_line_semantic_boundary_soft_wrap_with_mid_row_transition() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	// Row 0: prompt "$ " + input "cmd" (soft-wraps)
	// Row 1: input continues "12" + output "out"
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('$ ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('cmd12')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('out')!

	// Verify layout
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == '$ cmd\n12out'
	}

	// Selecting from input on row 0 should get all input across soft-wrap
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(3, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'cmd12'
	}

	// Selecting from input on row 1 should get all input across soft-wrap
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(0, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'cmd12'
	}

	// Selecting from output should only get output
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(3, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'out'
	}
}

fn test_screen_select_line_semantic_boundary_disabled() ! {
	mut s := Screen.init(10, 5, 0)!
	defer { s.deinit() }

	// Write prompt followed by input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('$ ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('command')!

	// With semantic_prompt_boundary = false, should select entire line
	if true {
		sel := s.select_line(SelectLine{
			pin:                      must_pin(s, active_pt(0, 0))
			semantic_prompt_boundary: false
		}) or { panic('no line selection') }
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == '$ command'
	}
}

fn test_screen_select_line_semantic_boundary_first_cell_of_row() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	// Row 0: input that soft-wraps
	// Row 1: output starts at first cell
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('12345')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('ABCDE')!

	// Verify soft-wrap happened
	if true {
		pin := must_pin(s, active_pt(0, 0))
		row := pin.row_and_cell().row
		assert row.header.wrap
	}

	// Selecting from input should stop before output on row 1
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(2, 0)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 0)
		assert must_point(s, .active, sel.end()) == active_pt(4, 0)
	}

	// Selecting from output should only get output
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(2, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 1)
		assert must_point(s, .active, sel.end()) == active_pt(4, 1)
	}
}

fn test_screen_select_line_semantic_all_same_content() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	// All prompt content that soft-wraps
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('prompt text')!

	// Verify soft-wrap
	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == 'promp\nt tex\nt'
	}

	// Should select all prompt content across soft-wraps
	if true {
		sel := s.select_line(SelectLine{ pin: must_pin(s, active_pt(2, 1)) }) or {
			panic('no line selection')
		}
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'prompt text'
	}
}

fn test_screen_select_word() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }
	s.test_write_string('ABC  DEF\n 123\n456')!

	// Default boundary codepoints for word selection
	boundary_codepoints := [u32(0), u32(` `), u32(`\t`), u32(`'`), u32(`"`), u32(`│`), u32(`\``),
		u32(`|`), u32(`:`), u32(`;`), u32(`,`), u32(`(`), u32(`)`), u32(`[`), u32(`]`), u32(`{`),
		u32(`}`), u32(`<`), u32(`>`), u32(`$`)]

	// Outside of active area
	// try testing.expect(s.selectWord(.{ .x = 9, .y = 0 }) == null);
	// try testing.expect(s.selectWord(.{ .x = 0, .y = 5 }) == null);

	// Going forward
	if true {
		sel := s.select_word(must_pin(s, active_pt(0, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 0)
	}

	// Going backward
	if true {
		sel := s.select_word(must_pin(s, active_pt(2, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 0)
	}

	// Going forward and backward
	if true {
		sel := s.select_word(must_pin(s, active_pt(1, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 0)
	}

	// Whitespace
	if true {
		sel := s.select_word(must_pin(s, active_pt(3, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(3, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(4, 0)
	}

	// Whitespace single char
	if true {
		sel := s.select_word(must_pin(s, active_pt(0, 1)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 1)
		assert must_point(s, .screen, sel.end()) == screen_pt(0, 1)
	}

	// End of screen
	if true {
		sel := s.select_word(must_pin(s, active_pt(1, 2)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(0, 2)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 2)
	}
}

fn test_screen_select_word_across_soft_wrap() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	s.test_write_string(' 1234012\n 123')!

	// Default boundary codepoints for word selection
	boundary_codepoints := [u32(0), u32(` `), u32(`\t`), u32(`'`), u32(`"`), u32(`│`), u32(`\``),
		u32(`|`), u32(`:`), u32(`;`), u32(`,`), u32(`(`), u32(`)`), u32(`[`), u32(`]`), u32(`{`),
		u32(`}`), u32(`<`), u32(`>`), u32(`$`)]

	if true {
		contents := s.dump_string_alloc(.screen)!
		assert contents == ' 1234\n012\n 123'
	}

	// Going forward
	if true {
		sel := s.select_word(must_pin(s, active_pt(1, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 1)
	}

	// Going backward
	if true {
		sel := s.select_word(must_pin(s, active_pt(1, 1)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 1)
	}

	// Going forward and backward
	if true {
		sel := s.select_word(must_pin(s, active_pt(3, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 1)
	}
}

fn test_screen_select_word_whitespace_across_soft_wrap() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	s.test_write_string('1       1\n 123')!

	// Default boundary codepoints for word selection
	boundary_codepoints := [u32(0), u32(` `), u32(`\t`), u32(`'`), u32(`"`), u32(`│`), u32(`\``),
		u32(`|`), u32(`:`), u32(`;`), u32(`,`), u32(`(`), u32(`)`), u32(`[`), u32(`]`), u32(`{`),
		u32(`}`), u32(`<`), u32(`>`), u32(`$`)]

	// Going forward
	if true {
		sel := s.select_word(must_pin(s, active_pt(1, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 1)
	}

	// Going backward
	if true {
		sel := s.select_word(must_pin(s, active_pt(1, 1)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 1)
	}

	// Going forward and backward
	if true {
		sel := s.select_word(must_pin(s, active_pt(3, 0)), boundary_codepoints) or {
			panic('no word selection')
		}
		defer { sel.deinit(mut s) }
		assert must_point(s, .screen, sel.start()) == screen_pt(1, 0)
		assert must_point(s, .screen, sel.end()) == screen_pt(2, 1)
	}
}

fn test_screen_select_word_with_character_boundary() ! {
	// Default boundary codepoints for word selection
	boundary_codepoints := [u32(0), u32(` `), u32(`\t`), u32(`'`), u32(`"`), u32(`│`), u32(`\``),
		u32(`|`), u32(`:`), u32(`;`), u32(`,`), u32(`(`), u32(`)`), u32(`[`), u32(`]`), u32(`{`),
		u32(`}`), u32(`<`), u32(`>`), u32(`$`)]

	cases := [
		" 'abc' \n123",
		' "abc" \n123',
		' │abc│ \n123',
		' `abc` \n123',
		' |abc| \n123',
		' :abc: \n123',
		' ;abc; \n123',
		' ,abc, \n123',
		' (abc( \n123',
		' )abc) \n123',
		' [abc[ \n123',
		' ]abc] \n123',
		' {abc{ \n123',
		' }abc} \n123',
		' <abc< \n123',
		' >abc> \n123',
		' \$abc\$ \n123',
	]

	for case in cases {
		mut s := Screen.init(20, 10, 0)!
		defer { s.deinit() }
		s.test_write_string(case)!

		// Inside character forward
		{
			sel := s.select_word(must_pin(s, active_pt(2, 0)), boundary_codepoints) or {
				panic('no word selection')
			}
			defer { sel.deinit(mut s) }
			assert must_point(s, .screen, sel.start()) == screen_pt(2, 0)
			assert must_point(s, .screen, sel.end()) == screen_pt(4, 0)
		}

		// Inside character backward
		{
			sel := s.select_word(must_pin(s, active_pt(4, 0)), boundary_codepoints) or {
				panic('no word selection')
			}
			defer { sel.deinit(mut s) }
			assert must_point(s, .screen, sel.start()) == screen_pt(2, 0)
			assert must_point(s, .screen, sel.end()) == screen_pt(4, 0)
		}

		// Inside character bidirectional
		{
			sel := s.select_word(must_pin(s, active_pt(3, 0)), boundary_codepoints) or {
				panic('no word selection')
			}
			defer { sel.deinit(mut s) }
			assert must_point(s, .screen, sel.start()) == screen_pt(2, 0)
			assert must_point(s, .screen, sel.end()) == screen_pt(4, 0)
		}

		// On quote
		// NOTE: this behavior is not ideal, so we can change this one day,
		// but I think its also not that important compared to the above.
		{
			sel := s.select_word(must_pin(s, active_pt(1, 0)), boundary_codepoints) or {
				panic('no word selection')
			}
			defer { sel.deinit(mut s) }
			assert must_point(s, .screen, sel.start()) == screen_pt(0, 0)
			assert must_point(s, .screen, sel.end()) == screen_pt(1, 0)
		}
	}
}

fn test_screen_select_output() ! {
	mut s := Screen.init(10, 15, 0)!
	defer { s.deinit() }

	// Build content with cell-level semantic content:
	// Row 0-1: output1 (output)
	// Row 2: prompt2 (prompt)
	// Row 3: input2 (input)
	// Row 4-7: output2 (output, with overflow causing wrap)
	// Row 8: "$ " (prompt) + "input3" (input)
	// Row 9-11: output3 (output)
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('output1\n')!
	s.test_write_string('output1\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('prompt2\n')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('input2\n')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('output2output2output2output2\n')!
	s.test_write_string('output2\n')!
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('$ ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('input3\n')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('output3\n')!
	s.test_write_string('output3\n')!
	s.test_write_string('output3')!

	// First output block (rows 0-1), should select those rows
	if true {
		sel := s.select_output(must_pin(s, active_pt(1, 1))) or { panic('no output selection') }
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'output1\noutput1'
	}
	// Second output block (rows 4-7)
	if true {
		sel := s.select_output(must_pin(s, active_pt(3, 7))) or { panic('no output selection') }
		defer { sel.deinit(mut s) }
		contents := s.selection_string(SelectionString{ sel: sel, trim: false })!
		assert contents == 'output2output2output2output2\noutput2'
	}
	// Third output block (rows 9-11)
	if true {
		sel := s.select_output(must_pin(s, active_pt(2, 10))) or { panic('no output selection') }
		defer { sel.deinit(mut s) }
		assert must_point(s, .active, sel.start()) == active_pt(0, 9)
		assert must_point(s, .active, sel.end()) == active_pt(6, 11)
	}
	// Click on prompt should return null
	if true {
		assert s.select_output(must_pin(s, active_pt(1, 8))) == none
	}
	// Click on input should return null
	if true {
		assert s.select_output(must_pin(s, active_pt(5, 8))) == none
	}
}

fn test_screen_selection_string_basic() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 1)), must_pin(s, screen_pt(2, 2)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '2EFGH\n3IJ'
		assert contents == expected
	}
}

fn test_screen_selection_string_start_outside_of_written_area() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 5)), must_pin(s, screen_pt(2, 6)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := ''
		assert contents == expected
	}
}

fn test_screen_selection_string_end_outside_of_written_area() ! {
	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 2)), must_pin(s, screen_pt(2, 6)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '3IJKL'
		assert contents == expected
	}
}

fn test_screen_selection_string_trim_space() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1AB  \n2EFGH\n3IJKL'
	s.test_write_string(str)!

	sel := Selection.init(must_pin(s, screen_pt(0, 0)), must_pin(s, screen_pt(2, 1)),
		false)

	if true {
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '1AB\n2EF'
		assert contents == expected
	}

	// No trim
	if true {
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: false
		})!
		expected := '1AB  \n2EF'
		assert contents == expected
	}
}

fn test_screen_selection_string_trim_empty_line() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	str := '1AB  \n\n2EFGH\n3IJKL'
	s.test_write_string(str)!

	sel := Selection.init(must_pin(s, screen_pt(0, 0)), must_pin(s, screen_pt(2, 2)),
		false)

	if true {
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '1AB\n\n2EF'
		assert contents == expected
	}

	// No trim
	if true {
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: false
		})!
		expected := '1AB  \n\n2EF'
		assert contents == expected
	}
}

fn test_screen_selection_string_soft_wrap() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABCD2EFGH3IJKL'
	s.test_write_string(str)!

	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 1)), must_pin(s, screen_pt(2, 2)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '2EFGH3IJ'
		assert contents == expected
	}
}

fn test_screen_selection_string_wide_char() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1A⚡'
	s.test_write_string(str)!

	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 0)), must_pin(s, screen_pt(3, 0)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := str
		assert contents == expected
	}

	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 0)), must_pin(s, screen_pt(2, 0)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := str
		assert contents == expected
	}

	if true {
		sel := Selection.init(must_pin(s, screen_pt(3, 0)), must_pin(s, screen_pt(3, 0)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '⚡'
		assert contents == expected
	}
}

fn test_screen_selection_string_wide_char_with_header() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	str := '1ABC⚡'
	s.test_write_string(str)!

	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 0)), must_pin(s, screen_pt(4, 0)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := str
		assert contents == expected
	}
}

// https://github.com/mitchellh/ghostty/issues/289
fn test_screen_selection_string_empty_with_soft_wrap() ! {
	mut s := Screen.init(5, 2, 0)!
	defer { s.deinit() }

	// Let me describe the situation that caused this because this
	// test is not obvious. By writing an emoji below, we introduce
	// one cell with the emoji and one cell as a "wide char spacer".
	// We then soft wrap the line by writing spaces.
	//
	// By selecting only the tail, we'd select nothing and we had
	// a logic error that would cause a crash.
	s.test_write_string('👨')!
	s.test_write_string('      ')!

	if true {
		sel := Selection.init(must_pin(s, screen_pt(1, 0)), must_pin(s, screen_pt(2, 0)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '👨'
		assert contents == expected
	}
}

fn test_screen_selection_string_with_zero_width_joiner() ! {
	mut s := Screen.init(10, 1, 0)!
	defer { s.deinit() }
	str := '👨‍' // this has a ZWJ
	s.test_write_string(str)!

	// Integrity check
	if true {
		pin := must_pin(s, screen_pt(0, 0))
		cell := pin.row_and_cell().cell
		assert cell.codepoint == u32(0x1F468)
		assert cell.wide == CellWide.wide
		cps := pin.node.data.lookup_grapheme(cell) or { panic('no grapheme data') }
		assert cps.len == 1
	}

	// The real test
	if true {
		sel := Selection.init(must_pin(s, screen_pt(0, 0)), must_pin(s, screen_pt(1, 0)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '👨‍'
		assert contents == expected
	}
}

fn test_screen_selection_string_rectangle_basic() ! {
	mut s := Screen.init(30, 5, 0)!
	defer { s.deinit() }
	str := 'Lorem ipsum dolor\n' + 'sit amet, consectetur\n' + 'adipiscing elit, sed do\n' +
		'eiusmod tempor incididunt\n' + 'ut labore et dolore'
	sel := Selection.init(must_pin(s, screen_pt(2, 1)), must_pin(s, screen_pt(6, 3)),
		true)
	expected := 't ame\n' + 'ipisc\n' + 'usmod'
	s.test_write_string(str)!

	contents := s.selection_string(SelectionString{
		sel:  sel
		trim: true
	})!
	assert contents == expected
}

fn test_screen_selection_string_rectangle_w_eol() ! {
	mut s := Screen.init(30, 5, 0)!
	defer { s.deinit() }
	str := 'Lorem ipsum dolor\n' + 'sit amet, consectetur\n' + 'adipiscing elit, sed do\n' +
		'eiusmod tempor incididunt\n' + 'ut labore et dolore'
	sel := Selection.init(must_pin(s, screen_pt(12, 0)), must_pin(s, screen_pt(26, 4)),
		true)
	expected := 'dolor\n' + 'nsectetur\n' + 'lit, sed do\n' + 'or incididunt\n' + ' dolore'
	s.test_write_string(str)!

	contents := s.selection_string(SelectionString{
		sel:  sel
		trim: true
	})!
	assert contents == expected
}

fn test_screen_selection_string_rectangle_more_complex_w_breaks() ! {
	mut s := Screen.init(30, 8, 0)!
	defer { s.deinit() }
	str := 'Lorem ipsum dolor\n' + 'sit amet, consectetur\n' + 'adipiscing elit, sed do\n' +
		'eiusmod tempor incididunt\n' + 'ut labore et dolore\n' + '\n' +
		'magna aliqua. Ut enim\n' + 'ad minim veniam, quis'
	sel := Selection.init(must_pin(s, screen_pt(11, 2)), must_pin(s, screen_pt(26, 7)),
		true)
	expected := 'elit, sed do\n' + 'por incididunt\n' + 't dolore\n' + '\n' + 'a. Ut enim\n' +
		'niam, quis'
	s.test_write_string(str)!

	contents := s.selection_string(SelectionString{
		sel:  sel
		trim: true
	})!
	assert contents == expected
}

fn test_screen_selection_string_multi_page() ! {
	mut s := Screen.init(10, 3, 2048)!
	defer { s.deinit() }

	first_page_size := int(first_node(s).data.capacity.rows)

	// Lazy way to seek to the first page boundary.
	mut first := first_node(s)
	first.data.pause_integrity_checks(true)
	for _ in 0 .. first_page_size - 1 {
		s.test_write_string('\n')!
	}
	first = first_node(s)
	first.data.pause_integrity_checks(false)

	s.test_write_string('123456789\n!@#$%^&*(\n123456789')!

	if true {
		sel := Selection.init(must_pin(s, active_pt(0, 0)), must_pin(s, active_pt(2, 2)),
			false)
		contents := s.selection_string(SelectionString{
			sel:  sel
			trim: true
		})!
		expected := '123456789\n!@#$%^&*(\n123'
		assert contents == expected
	}
}

fn test_screen_line_iterator() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	str := '1ABCD\n2EFGH'
	s.test_write_string(str)!

	// Test the line iterator
	mut iter := s.line_iterator(must_pin(s, viewport_pt(0, 0)))
	if true {
		sel := iter.next() or { panic('line iterator ended early') }
		actual := s.selection_string(SelectionString{
			sel:  sel
			trim: false
		})!
		assert actual == '1ABCD'
	}
	if true {
		sel := iter.next() or { panic('line iterator ended early') }
		actual := s.selection_string(SelectionString{
			sel:  sel
			trim: false
		})!
		assert actual == '2EFGH'
	}
}

fn test_screen_line_iterator_soft_wrap() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	str := '1ABCD2EFGH\n3ABCD'
	s.test_write_string(str)!

	// Test the line iterator
	mut iter := s.line_iterator(must_pin(s, viewport_pt(0, 0)))
	if true {
		sel := iter.next() or { panic('line iterator ended early') }
		actual := s.selection_string(SelectionString{
			sel:  sel
			trim: false
		})!
		assert actual == '1ABCD2EFGH'
	}
	if true {
		sel := iter.next() or { panic('line iterator ended early') }
		actual := s.selection_string(SelectionString{
			sel:  sel
			trim: false
		})!
		assert actual == '3ABCD'
	}
	// try testing.expect(iter.next() == null);
}

fn test_screen_hyperlink_start_end() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	assert s.cursor.hyperlink_id == 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(0)
	}

	s.start_hyperlink('http://example.com', none)!
	assert s.cursor.hyperlink_id != 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(1)
	}

	s.end_hyperlink()
	assert s.cursor.hyperlink_id == 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(0)
	}
}

fn test_screen_hyperlink_reuse() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	assert s.cursor.hyperlink_id == 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(0)
	}

	// Use it for the first time
	s.start_hyperlink('http://example.com', none)!
	assert s.cursor.hyperlink_id != 0
	id := s.cursor.hyperlink_id

	// Reuse the same hyperlink, expect we have the same ID
	s.start_hyperlink('http://example.com', none)!
	assert s.cursor.hyperlink_id == id
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(1)
	}

	s.end_hyperlink()
	assert s.cursor.hyperlink_id == 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(0)
	}
}

fn test_screen_hyperlink_cursor_state_on_resize() ! {
	// This test depends on underlying PageList implementation so
	// it may be invalid one day. It's here to document/verify the
	// current behavior.

	mut s := Screen.init(5, 10, 0)!
	defer { s.deinit() }

	// Start a hyperlink
	s.start_hyperlink('http://example.com', none)!
	assert s.cursor.hyperlink_id != 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(1)
	}

	// Resize. Any column growth will trigger a page to be reallocated.
	s.resize(ScreenResize{ cols: 10, rows: 10 })!
	assert s.cursor.hyperlink_id != 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(1)
	}

	s.end_hyperlink()
	assert s.cursor.hyperlink_id == 0
	if true {
		page := &s.cursor.page_pin.node.data
		assert page.hyperlink_set.count() == uint(0)
	}
}

fn test_screen_cursor_set_hyperlink_oom_uri_too_large_for_string_alloc() ! {
	mut s := Screen.init(80, 24, 0)!
	defer { s.deinit() }

	// Start a hyperlink with a URI that just barely fits in the string alloc.
	// This will ensure that additional string alloc space is needed for the
	// redundant copy of the URI when the page is re-alloced.
	uri := 'a'.repeat(int(std_capacity.string_bytes - 8))
	s.start_hyperlink(uri, none)!

	// Figure out how many cells should can have hyperlinks in this page,
	// and write twice that number, to guarantee the capacity needs to be
	// increased at some point.
	base_capacity := s.cursor.page_pin.node.data.hyperlink_capacity()
	base_string_bytes := s.cursor.page_pin.node.data.capacity.string_bytes
	for _ in 0 .. base_capacity * 2 {
		s.cursor_set_hyperlink()!
		if s.cursor.x >= u32(s.pages.cols) - 1 {
			s.cursor_down_or_scroll()!
			s.cursor_horizontal_absolute(0)
		} else {
			s.cursor_right(1)
		}
	}

	// Make sure the capacity really did increase.
	assert base_capacity < s.cursor.page_pin.node.data.hyperlink_capacity()
	// And that our string_bytes increased as well.
	assert base_string_bytes < s.cursor.page_pin.node.data.capacity.string_bytes
}

fn test_screen_increase_capacity_cursor_style_ref_count_preserved() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	s.set_attribute(SgrBold{})!
	s.test_write_string('1ABCD')!

	// We should have one page and it should be our cursor page
	assert voidptr(first_node(s)) == voidptr(last_node(s))
	assert voidptr(first_node(s)) == voidptr(s.cursor.page_pin.node)

	old_style := s.cursor.style

	if true {
		page := &last_node(s).data
		// 5 chars + cursor = 6 refs
		assert page.styles.ref_count(s.cursor.style_id) == u16(6)
	}

	// This forces the page to change via increaseCapacity.
	new_node := s.increase_capacity(s.cursor.page_pin.node, IncreaseCapacity.grapheme_bytes)!

	// Cursor's page_pin should now point to the new node
	assert voidptr(s.cursor.page_pin.node) == voidptr(new_node)

	// Verify cursor's page_cell and page_row are correctly reloaded from the pin
	page_rac := s.cursor.page_pin.row_and_cell()
	assert voidptr(s.cursor.page_row) == voidptr(page_rac.row)
	assert voidptr(s.cursor.page_cell) == voidptr(page_rac.cell)

	// Style should be preserved
	assert s.cursor.style.eql(&old_style)
	assert s.cursor.style_id != default_style_id

	// After increaseCapacity, the 5 chars are cloned (5 refs) and
	// the cursor's style is re-added (1 ref) = 6 total.
	if true {
		page := &last_node(s).data
		ref_count := page.styles.ref_count(s.cursor.style_id)
		assert ref_count == u16(6)
	}
}

fn test_screen_increase_capacity_cursor_hyperlink_ref_count_preserved() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	s.start_hyperlink('https://example.com/', none)!
	s.test_write_string('1ABCD')!

	// We should have one page and it should be our cursor page
	assert voidptr(first_node(s)) == voidptr(last_node(s))
	assert voidptr(first_node(s)) == voidptr(s.cursor.page_pin.node)

	if true {
		page := &last_node(s).data
		// Cursor has the hyperlink active = 1 count in hyperlink_set
		assert page.hyperlink_set.count() == uint(1)
		assert s.cursor.hyperlink_id != 0
		assert s.cursor.hyperlink_state != none
	}

	// This forces the page to change via increaseCapacity.
	_ = s.increase_capacity(s.cursor.page_pin.node, IncreaseCapacity.grapheme_bytes)!

	// Hyperlink should be preserved with correct URI
	assert s.cursor.hyperlink_state != none
	assert s.cursor.hyperlink_id != 0
	link := s.cursor.hyperlink_state or { panic('cursor has no hyperlink') }
	assert link.uri == 'https://example.com/'

	// After increaseCapacity, the hyperlink is re-added to the new page.
	if true {
		page := &last_node(s).data
		assert page.hyperlink_set.count() == uint(1)
	}
}

fn test_screen_increase_capacity_cursor_with_both_style_and_hyperlink_preserved() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	// Set both a non-default style AND an active hyperlink.
	// Write one character first with bold to mark the row as styled,
	// then start the hyperlink and write more characters.
	s.set_attribute(SgrBold{})!
	s.start_hyperlink('https://example.com/', none)!
	s.test_write_string('1ABCD')!

	// We should have one page and it should be our cursor page
	assert voidptr(first_node(s)) == voidptr(last_node(s))
	assert voidptr(first_node(s)) == voidptr(s.cursor.page_pin.node)

	old_style := s.cursor.style

	if true {
		page := &last_node(s).data
		// 5 chars + cursor = 6 refs for bold style
		assert page.styles.ref_count(s.cursor.style_id) == u16(6)
		// Cursor has the hyperlink active = 1 count in hyperlink_set
		assert page.hyperlink_set.count() == uint(1)
		assert s.cursor.style_id != default_style_id
		assert s.cursor.hyperlink_id != 0
		assert s.cursor.hyperlink_state != none
	}

	// This forces the page to change via increaseCapacity.
	_ = s.increase_capacity(s.cursor.page_pin.node, IncreaseCapacity.grapheme_bytes)!

	// Style should be preserved
	assert s.cursor.style.eql(&old_style)
	assert s.cursor.style_id != default_style_id

	// Hyperlink should be preserved with correct URI
	assert s.cursor.hyperlink_state != none
	assert s.cursor.hyperlink_id != 0
	link := s.cursor.hyperlink_state or { panic('cursor has no hyperlink') }
	assert link.uri == 'https://example.com/'

	// After increaseCapacity, both style and hyperlink are re-added to the new page.
	if true {
		page := &last_node(s).data
		ref_count := page.styles.ref_count(s.cursor.style_id)
		assert ref_count == u16(6)
		assert page.hyperlink_set.count() == uint(1)
	}
}

fn test_screen_increase_capacity_non_cursor_page_returns_early() ! {
	// Test that calling increaseCapacity on a page that is NOT the cursor's
	// page properly delegates to pages.increaseCapacity without doing the
	// extra cursor accounting (style/hyperlink re-adding).
	mut s := Screen.init(80, 24, 10000)!
	defer { s.deinit() }

	// Set up a custom style and hyperlink on the cursor
	s.set_attribute(SgrBold{})!
	s.start_hyperlink('https://example.com/', none)!
	s.test_write_string('Hello')!

	// Store cursor state before growing pages
	old_style := s.cursor.style
	old_style_id := s.cursor.style_id
	old_hyperlink := s.cursor.hyperlink_state
	old_hyperlink_id := s.cursor.hyperlink_id

	// The cursor is on the first (and only) page
	assert voidptr(first_node(s)) == voidptr(last_node(s))
	assert voidptr(s.cursor.page_pin.node) == voidptr(first_node(s))

	// Grow pages until we have multiple pages. The cursor's pin stays on
	// the first page since we're just adding rows.
	mut first_page_node := first_node(s)
	first_page_node.data.pause_integrity_checks(true)
	grow_count := int(first_page_node.data.capacity.rows - first_page_node.data.size.rows)
	for _ in 0 .. grow_count {
		_ = s.pages.grow()!
	}
	first_page_node.data.pause_integrity_checks(false)
	_ = s.pages.grow()!

	// Now we have two pages
	assert voidptr(first_node(s)) != voidptr(last_node(s))
	second_page := last_node(s)

	// Cursor should still be on the first page (where it was created)
	assert voidptr(s.cursor.page_pin.node) == voidptr(first_node(s))
	assert voidptr(s.cursor.page_pin.node) != voidptr(second_page)

	second_page_styles_cap := second_page.data.capacity.styles
	cursor_page_styles_cap := s.cursor.page_pin.node.data.capacity.styles

	// Call increaseCapacity on the second page (NOT the cursor's page)
	new_second_page := s.increase_capacity(second_page, IncreaseCapacity.styles)!

	// The second page should have increased capacity
	assert new_second_page.data.capacity.styles == second_page_styles_cap * 2

	// The cursor's page (first page) should be unchanged
	assert s.cursor.page_pin.node.data.capacity.styles == cursor_page_styles_cap

	// Cursor state should be completely unchanged since we didn't touch its page
	assert s.cursor.style.eql(&old_style)
	assert s.cursor.style_id == old_style_id
	// Ghostty compares the heap-allocated `?*Hyperlink` pointers; Witty stores
	// the cursor hyperlink by value, so compare the values.
	if true {
		old_link := old_hyperlink or { panic('old cursor hyperlink was null') }
		cur_link := s.cursor.hyperlink_state or { panic('cursor hyperlink is null') }
		assert cur_link.eql(old_link)
	}
	assert s.cursor.hyperlink_id == old_hyperlink_id

	// Verify hyperlink is still valid
	assert s.cursor.hyperlink_state != none
	link := s.cursor.hyperlink_state or { panic('cursor has no hyperlink') }
	assert link.uri == 'https://example.com/'
}

fn test_screen_cursor_down_to_page_with_insufficient_capacity() ! {
	// Regression test for https://github.com/ghostty-org/ghostty/issues/10282
	//
	// This test exposes a use-after-realloc bug in cursorDown (and similar
	// cursor movement functions). The bug pattern:
	//
	// 1. cursorDown creates a by-value copy of the pin via page_pin.down(n)
	// 2. cursorChangePin is called, which may trigger adjustCapacity
	//    if the target page's style map is full
	// 3. adjustCapacity frees the old page and creates a new one
	// 4. The local pin copy still points to the freed page
	// 5. rowAndCell() on the stale pin accesses freed memory

	// Small screen to make page boundary crossing easy to set up
	mut s := Screen.init(10, 3, 1)!
	defer { s.deinit() }

	// Scroll down enough to create a second page
	mut start_node := last_node(s)
	start_page := &start_node.data
	rem := int(start_page.capacity.rows)
	start_node.data.pause_integrity_checks(true)
	for _ in 0 .. rem {
		s.cursor_down_or_scroll()!
	}
	start_node.data.pause_integrity_checks(false)

	// Cursor should now be on a new page
	mut new_node := s.cursor.page_pin.node
	new_page := &new_node.data
	assert !same_page(start_page, new_page)

	// Fill new_page's style map to capacity. When we move INTO this page
	// with a style set, adjustCapacity will be triggered.
	if true {
		new_node.data.pause_integrity_checks(true)
		defer { new_node.data.pause_integrity_checks(false) }
		defer { new_node.data.assert_integrity() }

		mut n := u32(1)
		for {
			new_node.data.styles.add(CellStyle{
				bg_color: StyleColorRgb{
					rgb: RGB{
						r: u8(n)
						g: u8(n >> 8)
						b: u8(n >> 16)
					}
				}
			}) or { break }
			n += 1
		}
	}

	// Move cursor to start of active area and set a style
	s.cursor_absolute(0, 0)
	s.set_attribute(SgrBold{})!
	assert s.cursor.style.flags.bold()
	assert s.cursor.style_id != default_style_id

	// Find the row just before the page boundary
	mut found_boundary := false
	for row in 0 .. int(s.pages.rows) - 1 {
		s.cursor_absolute(0, u32(row))
		cur_node := s.cursor.page_pin.node
		if next_pin := s.cursor.page_pin.down(1) {
			if voidptr(next_pin.node) != voidptr(cur_node) {
				// Cursor is at 'row', moving down crosses to new_page
				assert same_page(&next_pin.node.data, new_page)

				// This cursorDown triggers the bug: the local page_pin copy
				// becomes stale after adjustCapacity, causing rowAndCell()
				// to access freed memory.
				s.cursor_down(1)

				// If the fix is applied, verify correct state
				assert s.cursor.y == u32(row + 1)
				assert s.cursor.style.flags.bold()

				found_boundary = true
				break
			}
		}
	}
	if !found_boundary {
		// Didn't find boundary
		assert false
	}
}

fn test_screen_set_attribute_increases_capacity_when_style_map_is_full() ! {
	// Tests that setAttribute succeeds when the style map is full by
	// increasing page capacity. When capacity is at max and increaseCapacity
	// returns OutOfSpace, manualStyleUpdate will split the page instead.

	// Use a small screen with multiple rows
	mut s := Screen.init(10, 5, 10)!
	defer { s.deinit() }

	// Write content to multiple rows
	s.test_write_string('line1\nline2\nline3\nline4\nline5')!

	// Get the page and fill its style map to capacity
	mut page := &s.cursor.page_pin.node.data
	original_styles_capacity := page.capacity.styles

	// Fill the style map to capacity using the StyleSet's layout capacity
	// which accounts for the load factor
	if true {
		page.pause_integrity_checks(true)
		defer { page.pause_integrity_checks(false) }
		defer { page.assert_integrity() }

		max_items := page.styles.set.layout.cap
		mut n := uint(1)
		for n < max_items {
			page.styles.add(CellStyle{
				bg_color: StyleColorRgb{
					rgb: RGB{
						r: u8(n)
						g: u8(n >> 8)
						b: u8(n >> 16)
					}
				}
			}) or { break }
			n += 1
		}
	}

	// Now try to set a new unique attribute that would require a new style slot
	// This should succeed by increasing capacity (or splitting if at max capacity)
	s.set_attribute(SgrBold{})!

	// The style should have been applied (bold flag set)
	assert s.cursor.style.flags.bold()

	// The cursor should have a valid non-default style_id
	assert s.cursor.style_id != default_style_id

	// Either the capacity increased or the page was split/changed
	current_page := &s.cursor.page_pin.node.data
	capacity_increased := current_page.capacity.styles > original_styles_capacity
	page_changed := !same_page(current_page, page)
	assert capacity_increased || page_changed
}

fn test_screen_set_attribute_splits_page_on_out_of_space_at_max_styles() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	// Write content to multiple rows so we have something to split
	s.test_write_string('line1\nline2\nline3\nline4\nline5')!

	// Remember the original node
	original_node := s.cursor.page_pin.node

	// Increase the page's style capacity to max by repeatedly calling increaseCapacity
	// Use Screen.increaseCapacity to properly maintain cursor state
	max_styles := u16(max_u16) // std.math.maxInt(size.CellCountInt)
	for s.cursor.page_pin.node.data.capacity.styles < max_styles {
		s.increase_capacity(s.cursor.page_pin.node, IncreaseCapacity.styles) or { break }
	}

	// Get the page reference after increaseCapacity - cursor may have moved
	mut page := &s.cursor.page_pin.node.data
	assert page.capacity.styles == max_styles

	// Fill the style map to capacity using the StyleSet's layout capacity
	// which accounts for the load factor
	if true {
		page.pause_integrity_checks(true)
		defer { page.pause_integrity_checks(false) }
		defer { page.assert_integrity() }

		max_items := page.styles.set.layout.cap
		mut n := uint(1)
		for n < max_items {
			page.styles.add(CellStyle{
				bg_color: StyleColorRgb{
					rgb: RGB{
						r: u8(n)
						g: u8(n >> 8)
						b: u8(n >> 16)
					}
				}
			}) or { break }
			n += 1
		}
	}

	// Track the node before setAttribute
	node_before_set := s.cursor.page_pin.node

	// Now try to set a new unique attribute that would require a new style slot
	// At max capacity, increaseCapacity will return OutOfSpace, triggering page split
	s.set_attribute(SgrBold{})!

	// The style should have been applied (bold flag set)
	assert s.cursor.style.flags.bold()

	// The cursor should have a valid non-default style_id
	assert s.cursor.style_id != default_style_id

	// The page should have been split
	page_was_split := voidptr(s.cursor.page_pin.node) != voidptr(node_before_set)
		|| node_before_set.next != none || node_before_set.prev != none
		|| voidptr(s.cursor.page_pin.node) != voidptr(original_node)
	assert page_was_split
}

fn test_screen_prompt_click_move_line_right_basic() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Move cursor back to start of input (column 2, the 'h')
	s.cursor_absolute(2, 0)

	// Click on first 'l' (column 4), should require 2 right movements (h->e->l)
	click_pin := must_pin(s, active_pt(4, 0))
	result := s.prompt_click_move(click_pin)

	assert result.right == uint(2)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_line_right_cursor_not_on_input() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})

	// Move cursor back to prompt area (column 0, the '>')
	s.cursor_absolute(0, 0)

	// Cursor is on prompt, not input - should return zero
	click_pin := must_pin(s, active_pt(4, 0))
	result := s.prompt_click_move(click_pin)

	assert result == prompt_click_move_zero
}

fn test_screen_prompt_click_move_line_right_click_on_same_position() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Move cursor to column 4
	s.cursor_absolute(4, 0)

	// Click on same position - no movement needed
	click_pin := must_pin(s, active_pt(4, 0))
	result := s.prompt_click_move(click_pin)

	assert result == prompt_click_move_zero
}

fn test_screen_prompt_click_move_line_right_skips_non_input_cells() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write: "> h" then output "X" then input "llo"
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('h')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('X')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('llo')!

	// Move cursor to column 2 (the 'h')
	s.cursor_absolute(2, 0)

	// Click on 'l' at column 5 - should skip the 'X' output cell
	// Movement: h (start) -> l (col 4) -> l (col 5) = 2 right movements
	click_pin := must_pin(s, active_pt(5, 0))
	result := s.prompt_click_move(click_pin)

	assert result.right == uint(2)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_line_right_soft_wrapped_line() ! {
	mut s := Screen.init(10, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input that wraps
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	// Write 8 chars of input, first row has 2 for prompt + 8 input = 10 cols
	s.test_write_string('abcdefgh')!
	// Continue on next row (soft-wrapped)
	s.test_write_string('ij')!

	// Verify soft wrap occurred
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '> abcdefgh\nij'
	}

	// Move cursor to column 2 (the 'a')
	s.cursor_absolute(2, 0)

	// Click on 'j' at column 1, row 1 - should count all input cells
	// Movement: a->b->c->d->e->f->g->h->i->j = 9 right movements
	click_pin := must_pin(s, active_pt(1, 1))
	result := s.prompt_click_move(click_pin)

	assert result.right == uint(9)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_disabled_when_click_is_none() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Click mode is .none by default (disabled)
	assert s.semantic_prompt.click == semantic_click_none

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Move cursor to start of input
	s.cursor_absolute(2, 0)

	// Click should return zero since click mode is disabled
	click_pin := must_pin(s, active_pt(4, 0))
	result := s.prompt_click_move(click_pin)

	assert result == prompt_click_move_zero
}

fn test_screen_prompt_click_move_line_right_stops_at_hard_wrap() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write prompt and input on first line
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!
	// Hard wrap (newline)
	s.test_write_string('\n')!
	s.test_write_string('world')!

	// Move cursor to column 2 (the 'h')
	s.cursor_absolute(2, 0)

	// Click on 'w' at column 0, row 1 - but line mode stops at hard wrap
	// Should only move to end of first line: h->e->l->l->o = 4 movements
	click_pin := must_pin(s, active_pt(0, 1))
	result := s.prompt_click_move(click_pin)

	// Should stop at end of first line, not cross hard wrap
	assert result.right == uint(5)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_line_right_stops_at_non_continuation_row() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Row 0: PROMPT "> hello"
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello\n')!

	// Row 1: CONTINUATION "world"
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .continuation })
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('world\n')!

	// Row 2: NEW PROMPT "> again"
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('again')!

	// Verify content
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '> hello\nworld\n> again'
	}

	// Move cursor to 'w' at column 0, row 1
	s.cursor_absolute(0, 1)

	// Click on 'a' at column 2, row 2 - but row 2 is a new prompt
	// Should stop at end of "world": w->o->r->l->d = 4 movements
	click_pin := must_pin(s, active_pt(2, 2))
	result := s.prompt_click_move(click_pin)

	// Should stop at 'd' (end of world), not cross to new prompt
	assert result.right == uint(5)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_line_left_basic() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Cursor is at column 7 (after 'o'), move it to column 6 (the 'o')
	s.cursor_absolute(6, 0)

	// Click on 'h' (column 2), should require 4 left movements (o->l->l->e->h)
	click_pin := must_pin(s, active_pt(2, 0))
	result := s.prompt_click_move(click_pin)

	assert result.left == uint(4)
	assert result.right == uint(0)
}

fn test_screen_prompt_click_move_line_left_skips_non_input_cells() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write: "> h" then output "X" then input "llo"
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('h')!
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.test_write_string('X')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('llo')!

	// Move cursor to column 6 (the 'o')
	s.cursor_absolute(6, 0)

	// Click on 'h' at column 2 - should skip the 'X' output cell
	// Movement: o->l->l->h = 3 left movements (skipping X)
	click_pin := must_pin(s, active_pt(2, 0))
	result := s.prompt_click_move(click_pin)

	assert result.left == uint(3)
	assert result.right == uint(0)
}

fn test_screen_prompt_click_move_line_left_soft_wrapped_line() ! {
	mut s := Screen.init(10, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input that wraps
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	// Write 8 chars of input, first row has 2 for prompt + 8 input = 10 cols
	s.test_write_string('abcdefgh')!
	// Continue on next row (soft-wrapped)
	s.test_write_string('ij')!

	// Verify soft wrap occurred
	if true {
		contents := s.dump_string_alloc(.viewport)!
		assert contents == '> abcdefgh\nij'
	}

	// Cursor is at column 2, row 1 (after 'j'). Move to 'j' at column 1.
	s.cursor_absolute(1, 1)

	// Click on 'a' at column 2, row 0 - should count all input cells backwards
	// Movement: j->i->h->g->f->e->d->c->b->a = 9 left movements
	click_pin := must_pin(s, active_pt(2, 0))
	result := s.prompt_click_move(click_pin)

	assert result.left == uint(9)
	assert result.right == uint(0)
}

fn test_screen_prompt_click_move_line_left_stops_at_hard_wrap() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write prompt and input on first line, then hard wrap
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!
	// Hard wrap (newline)
	s.test_write_string('\n')!
	s.test_write_string('world')!

	// Move cursor to 'd' at column 4, row 1 (an actual input cell)
	s.cursor_absolute(4, 1)

	// Click on 'h' at column 2, row 0 - but line mode stops at hard wrap
	// Should only move to start of second line, not cross to row 0
	click_pin := must_pin(s, active_pt(2, 0))
	result := s.prompt_click_move(click_pin)

	// Should stop at start of second line: d->l->r->o->w = 4 movements
	assert result.left == uint(4)
	assert result.right == uint(0)
}

fn test_screen_prompt_click_move_click_right_of_input_same_line() ! {
	// Set up: "> hello" where "> " is prompt and "hello" is input
	// Clicking to the right of the 'o' should move cursor past the input

	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Move cursor to start of input (column 2, the 'h')
	s.cursor_absolute(2, 0)

	// Click beyond the input (column 15) - should move to one past the 'o'
	click_pin := must_pin(s, active_pt(15, 0))
	result := s.prompt_click_move(click_pin)

	assert result.right == uint(5)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_click_right_of_input_cursor_at_end() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Cursor is already at column 7 (one past 'o') after writing
	// Click beyond the input (column 15) - no movement needed since
	// cursor is already at the end position
	click_pin := must_pin(s, active_pt(15, 0))
	result := s.prompt_click_move(click_pin)

	assert result.right == uint(0)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_click_right_of_input_on_lower_line() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Move cursor to start of input (column 2, the 'h')
	s.cursor_absolute(2, 0)

	// Click on a lower line (row 1) - should move to end of input
	// This is outside the prompt area so should clamp to end
	click_pin := must_pin(s, active_pt(5, 1))
	result := s.prompt_click_move(click_pin)

	// From 'h', we need to pass e, l, l, o (4 cells) + 1 past end = 5
	assert result.right == uint(5)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_click_right_of_input_cursor_at_end_lower_line() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Cursor is at column 7 after writing (one past 'o')
	// Click on a lower line (row 1) - cursor already at end, no movement needed
	click_pin := must_pin(s, active_pt(5, 1))
	result := s.prompt_click_move(click_pin)

	assert result.right == uint(0)
	assert result.left == uint(0)
}

fn test_screen_prompt_click_move_click_right_of_input_cursor_on_last_char() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }

	// Enable line click mode
	s.semantic_prompt.click = SemanticClick.from_cl(.line)

	// Write a prompt and input
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	s.test_write_string('hello')!

	// Move cursor to last input char (column 6, the 'o')
	s.cursor_absolute(6, 0)

	// Click beyond the input (column 15)
	click_pin := must_pin(s, active_pt(15, 0))
	result := s.prompt_click_move(click_pin)

	assert result.right == uint(1)
	assert result.left == uint(0)
}

// ============================================================
// Witty-only tests
// ============================================================

// Helper for the Witty-only tests: overwrite the page cell at active (x, y).
fn witty_set_active_cell(s &Screen, x int, y int, cell CellData) {
	p := must_pin(s, active_pt(x, y))
	mut page := &p.node.data
	page.rows[int(p.y)].cells[int(p.x)] = cell
}

// Helper for the Witty-only tests: the page row at active y.
fn witty_active_row(s &Screen, y int) &RowData {
	return must_cell(s, active_pt(0, y)).row
}

fn test_semantic_click_source_layout() ! {
	assert semantic_click_none is SemanticClickNone
	assert semantic_click_click_events is SemanticClickEvents
	click := SemanticClick.from_cl(.smart_vertical)
	assert click is SemanticClickCl
	assert (click as SemanticClickCl).cl == .smart_vertical
}

fn test_semantic_input_clear_source_layout() ! {
	assert sizeof(SemanticInputClear) == 1
	assert u8(SemanticInputClear.clear_explicit) == 0
	assert u8(SemanticInputClear.clear_eol) == 1
	assert sizeof(CursorSemanticInput) == 1
	assert sizeof(PromptKind) == 1
	assert u8(PromptKind.initial) == 0
	assert u8(PromptKind.right) == 1
	assert u8(PromptKind.continuation) == 2
	assert u8(PromptKind.secondary) == 3
}

// The fg color and the underline color are stored independently: setting an
// SGR 58 underline color must NOT corrupt the fg color (and vice versa). This
// mirrors ghostty's separate Style.underline_color union.
fn test_screen_style_underline_color_independent_from_fg() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }

	// Set an RGB fg color and a DIFFERENT RGB underline color.
	s.set_attribute(SgrDirectColorFg{ rgb: RGB{ r: 255, g: 0, b: 0 } })!
	s.set_attribute(SgrUnderlineColor{ rgb: RGB{ r: 0, g: 255, b: 0 } })!

	// The fg color must be preserved unchanged.
	assert s.cursor.style.fg_color is StyleColorRgb
	fg_color := (s.cursor.style.fg_color as StyleColorRgb).rgb
	assert fg_color.r == 255
	assert fg_color.g == 0
	assert fg_color.b == 0

	// The underline color is stored in its own fields.
	rgb_underline := s.cursor.style.underline_color
	assert rgb_underline is StyleColorRgb
	underline_rgb := (rgb_underline as StyleColorRgb).rgb
	assert underline_rgb.r == 0
	assert underline_rgb.g == 255
	assert underline_rgb.b == 0

	// Resolution reads back the correct, independent colors.
	mut palette := [256]RGB{}
	fg := s.cursor.style.fg(FgOpts{
		default_color: RGB{}
		palette:       palette
	})
	assert fg.r == 255 && fg.g == 0 && fg.b == 0
	ul := s.cursor.style.underline_color(palette) or { panic('expected underline color') }
	assert ul.r == 0 && ul.g == 255 && ul.b == 0

	// Palette underline color must retain its own payload, independent of fg.
	palette[7] = RGB{
		r: 11
		g: 22
		b: 33
	}
	s.set_attribute(SgrUnderlineColor256{ idx: 7 })!
	palette_underline := s.cursor.style.underline_color
	assert palette_underline is StyleColorPalette
	assert (palette_underline as StyleColorPalette).index == 7
	// fg is still the RGB red we set earlier, untouched by the palette write.
	assert s.cursor.style.fg_color is StyleColorRgb
	assert (s.cursor.style.fg_color as StyleColorRgb).rgb.r == 255
	ul2 := s.cursor.style.underline_color(palette) or { panic('expected underline color') }
	assert ul2.r == 11 && ul2.g == 22 && ul2.b == 33

	// Reset clears only the underline color.
	s.set_attribute(SgrResetUnderlineColor{})!
	assert s.cursor.style.underline_color is StyleColorNone
	assert s.cursor.style.fg_color is StyleColorRgb
	assert (s.cursor.style.fg_color as StyleColorRgb).rgb.r == 255

	// Two styles differing only in underline color must be distinct.
	a := CellStyle{
		underline_color: StyleColorRgb{ rgb: RGB{ r: 1 } }
	}
	b := CellStyle{
		underline_color: StyleColorRgb{ rgb: RGB{ r: 2 } }
	}
	assert !a.eql(&b)
	assert a.hash() != b.hash()
}

fn test_screen_viewport_is_bottom() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }
	assert s.viewport_is_bottom()
}

fn test_screen_reset() ! {
	mut s := Screen.init(80, 24, 1000)!
	defer { s.deinit() }

	s.test_write_string('hello')!
	s.reset()

	str := s.dump_string_alloc(.screen)!
	assert str == ''
	assert s.cursor.x == 0
	assert s.cursor.y == 0
}

fn test_screen_cursor_movement() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	assert s.cursor.x == 0
	assert s.cursor.y == 0

	s.cursor_right(3)
	assert s.cursor.x == 3

	s.cursor_left(1)
	assert s.cursor.x == 2

	s.cursor_down(2)
	assert s.cursor.y == 2

	s.cursor_up(1)
	assert s.cursor.y == 1

	s.cursor_absolute(5, 5)
	assert s.cursor.x == 5
	assert s.cursor.y == 5

	s.cursor_horizontal_absolute(0)
	assert s.cursor.x == 0
	assert s.cursor.y == 5
}

// Ghostty's cursorChangePin marks the old and the new cursor rows dirty
// whenever the pin changes.
fn test_screen_cursor_vertical_movement_marks_old_and_new_rows_dirty() ! {
	mut s := Screen.init(10, 4, 0)!
	defer { s.deinit() }
	s.cursor_absolute(2, 1)
	s.pages.clear_dirty()

	s.cursor_down(2)
	assert s.pages.is_dirty(active_pt(0, 1))
	assert !s.pages.is_dirty(active_pt(0, 2))
	assert s.pages.is_dirty(active_pt(0, 3))

	s.pages.clear_dirty()
	s.cursor_up(1)
	assert !s.pages.is_dirty(active_pt(0, 1))
	assert s.pages.is_dirty(active_pt(0, 2))
	assert s.pages.is_dirty(active_pt(0, 3))
}

fn test_screen_zero_distance_cursor_movement_stays_clean() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.cursor_absolute(2, 1)
	s.pages.clear_dirty()

	s.cursor_up(0)
	s.cursor_down(0)
	s.cursor_absolute(2, 1)
	for y in 0 .. 3 {
		assert !s.pages.is_dirty(active_pt(0, y))
	}
}

fn test_screen_cursor_cell_left_right() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.cursor_absolute(5, 1)
	witty_set_active_cell(s, 3, 1, CellData.init(u32(`L`)))
	witty_set_active_cell(s, 7, 1, CellData.init(u32(`R`)))

	left := s.cursor_cell_left(2)
	right := s.cursor_cell_right(2)
	assert left.codepoint == u32(`L`)
	assert right.codepoint == u32(`R`)
	assert voidptr(left) == voidptr(must_cell(s, active_pt(3, 1)).cell)
	assert voidptr(right) == voidptr(must_cell(s, active_pt(7, 1)).cell)
}

fn test_screen_cursor_previous_cell_and_row_up_reference_page_storage() ! {
	mut s := Screen.init(10, 3, 0)!
	defer { s.deinit() }
	s.cursor_absolute(5, 2)
	witty_set_active_cell(s, 9, 1, CellData.init(u32(`P`)))

	previous_cell := s.cursor_cell_end_of_prev()
	previous_row := s.cursor_row_up(1)
	assert previous_cell.codepoint == u32(`P`)
	assert voidptr(previous_cell) == voidptr(must_cell(s, active_pt(9, 1)).cell)
	assert voidptr(previous_row) == voidptr(witty_active_row(s, 1))
}

fn test_screen_blank_cell() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	cell := s.blank_cell()
	assert cell.codepoint == 0
	assert cell.style_id == 0
}

fn test_screen_select_clear() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	s.test_write_string('hello')!
	tracked := s.pages.count_tracked_pins()
	s.select(Selection.init(must_pin(s, active_pt(0, 0)), must_pin(s, active_pt(4, 0)),
		false))!
	assert s.selection != none
	assert s.pages.count_tracked_pins() == tracked + 2

	s.clear_selection()
	assert s.selection == none
	assert s.pages.count_tracked_pins() == tracked
}

fn test_screen_soft_wrap_write() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	s.test_write_string('helloworld')!

	str := s.dump_string_alloc(.active)!
	assert str == 'hello\nworld'
}

fn test_screen_cursor_reset_wrap() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }

	s.test_write_string('hello')!
	assert s.cursor.pending_wrap == true

	s.cursor_reset_wrap()
	assert s.cursor.pending_wrap == false
}

fn test_screen_cursor_reset_wrap_clears_wide_spacer_head() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	mut row0 := witty_active_row(s, 0)
	mut row1 := witty_active_row(s, 1)
	row0.header.wrap = true
	witty_set_active_cell(s, 4, 0, CellData{
		wide: .spacer_head
	})
	row1.header.wrap_continuation = true

	s.cursor_reset_wrap()

	assert !witty_active_row(s, 0).header.wrap
	assert !witty_active_row(s, 1).header.wrap_continuation
	assert must_cell(s, active_pt(4, 0)).cell.is_zero()
}

fn test_screen_cursor_reset_wrap_preserves_next_row_without_wrap() ! {
	mut s := Screen.init(5, 5, 0)!
	defer { s.deinit() }
	mut row1 := witty_active_row(s, 1)
	row1.header.wrap_continuation = true

	s.cursor_reset_wrap()

	assert witty_active_row(s, 1).header.wrap_continuation
}

fn test_screen_split_cell_boundary_clears_wrapped_wide_spacer_head() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	mut row0 := witty_active_row(s, 0)
	row0.header.wrap = true
	witty_set_active_cell(s, 4, 0, CellData{
		wide: .spacer_head
	})

	s.split_cell_boundary(5)

	assert must_cell(s, active_pt(4, 0)).cell.is_zero()
}

fn test_screen_split_cell_boundary_clears_previous_wrapped_wide_spacer_head() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	s.cursor_absolute(0, 1)
	mut row1 := witty_active_row(s, 1)
	row1.header.wrap_continuation = true
	witty_set_active_cell(s, 0, 1, CellData{
		codepoint: u32(0x1f600)
		wide:      .wide
	})
	witty_set_active_cell(s, 4, 0, CellData{
		wide: .spacer_head
	})

	s.split_cell_boundary(0)

	assert must_cell(s, active_pt(4, 0)).cell.is_zero()
}

fn test_screen_semantic_content() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	assert s.cursor.semantic_content == .output

	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	assert s.cursor.semantic_content == .prompt
	assert s.semantic_prompt.seen

	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	assert s.cursor.semantic_content == .input

	s.cursor_set_semantic_content(CursorSemanticOutput{})
	assert s.cursor.semantic_content == .output
}

fn test_screen_cursor_set_semantic_content_union() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .continuation })
	assert s.semantic_prompt.seen
	assert s.cursor.semantic_content == .prompt
	assert witty_active_row(s, 0).header.semantic_prompt == .prompt_continuation

	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_eol })
	assert s.cursor.semantic_content == .input
	assert s.cursor.semantic_content_clear_eol

	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_explicit })
	assert !s.cursor.semantic_content_clear_eol
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	assert s.cursor.semantic_content == .output
}

fn test_screen_first_implicit_hyperlink_uses_zero_offset() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }

	s.start_hyperlink('https://example.com/', none)!
	link := s.cursor.hyperlink_state or {
		assert false
		return
	}
	match link.id {
		HyperlinkImplicitId {
			assert link.id.offset == 0
		}
		HyperlinkExplicitId {
			assert false
		}
	}
	assert s.cursor.hyperlink_implicit_id == 1
}

fn test_screen_cursor_copy_explicit_hyperlink_id() ! {
	mut s := Screen.init(10, 10, 0)!
	defer { s.deinit() }
	s.start_hyperlink('https://example.com/', 'same-id')!

	mut s2 := Screen.init(10, 10, 0)!
	defer { s2.deinit() }
	s2.cursor_copy(s.cursor, CursorCopyOptions{})!
	link := s2.cursor.hyperlink_state or {
		assert false
		return
	}
	match link.id {
		HyperlinkExplicitId {
			assert link.id.value == 'same-id'
		}
		HyperlinkImplicitId {
			assert false
		}
	}
}

fn test_screen_cursor_set_hyperlink_updates_cursor_cell_and_row() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	s.cursor_absolute(2, 1)
	s.start_hyperlink('https://example.com/cursor', 'cursor')!

	s.cursor_set_hyperlink()!

	assert witty_active_row(s, 1).header.hyperlink
	list_cell := must_cell(s, active_pt(2, 1))
	assert list_cell.cell.has_hyperlink
	page := &list_cell.node.data
	id := page.lookup_hyperlink(list_cell.cell) or {
		assert false, 'cell has no hyperlink'
		return
	}
	assert page.hyperlink_set.get(id).uri == 'https://example.com/cursor'
}

fn test_screen_append_grapheme_updates_cursor_row_cell() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }
	s.cursor_absolute(2, 1)
	witty_set_active_cell(s, 2, 1, CellData.init(u32(`a`)))

	s.append_grapheme(s.cursor.page_cell, u32(0x0301))!

	list_cell := must_cell(s, active_pt(2, 1))
	assert list_cell.row.header.grapheme
	assert list_cell.cell.content_tag == .codepoint_grapheme
	assert list_cell.cell.has_grapheme()
	graphemes := list_cell.node.data.lookup_grapheme(list_cell.cell) or { []u32{} }
	assert graphemes == [u32(0x0301)]
}

fn test_screen_test_write_string_wide_and_grapheme() ! {
	mut s := Screen.init(4, 2, 0)!
	defer { s.deinit() }

	s.test_write_string('A界́')!
	row := witty_active_row(s, 0)
	cell0 := must_cell(s, active_pt(0, 0)).cell
	cell1 := must_cell(s, active_pt(1, 0))
	cell2 := must_cell(s, active_pt(2, 0)).cell
	assert cell0.codepoint == u32(`A`)
	assert cell1.cell.codepoint == u32(`界`)
	assert cell1.cell.wide == .wide
	assert cell1.cell.content_tag == .codepoint_grapheme
	graphemes := cell1.node.data.lookup_grapheme(cell1.cell) or { []u32{} }
	assert graphemes == [u32(0x0301)]
	assert cell2.wide == .spacer_tail
	assert row.header.grapheme
	assert s.cursor.x == 3
}

fn test_screen_test_write_string_wide_wraps_with_spacer_head() ! {
	mut s := Screen.init(3, 2, 0)!
	defer { s.deinit() }

	s.test_write_string('AB界')!
	first := witty_active_row(s, 0)
	second := witty_active_row(s, 1)
	assert must_cell(s, active_pt(2, 0)).cell.wide == .spacer_head
	assert first.header.wrap
	assert second.header.wrap_continuation
	assert must_cell(s, active_pt(0, 1)).cell.codepoint == u32(`界`)
	assert must_cell(s, active_pt(0, 1)).cell.wide == .wide
	assert must_cell(s, active_pt(1, 1)).cell.wide == .spacer_tail
	assert s.cursor.x == 2
	assert s.cursor.y == 1
}

// Narrow cells only: like Ghostty's testWriteString, the wide-char branch
// sets the hyperlink before it marks the row styled, which trips the page
// integrity check when a style and a hyperlink are both active.
fn test_screen_test_write_string_preserves_style_and_hyperlink() ! {
	mut s := Screen.init(4, 2, 0)!
	defer { s.deinit() }

	s.cursor.style.flags.set_bold(true)
	s.manual_style_update()!
	s.start_hyperlink('https://example.com/', 'test')!
	s.test_write_string('AB')!
	row := witty_active_row(s, 0)
	assert row.header.styled
	assert row.header.hyperlink
	assert must_cell(s, active_pt(0, 0)).style().flags.bold()
	assert must_cell(s, active_pt(1, 0)).style().flags.bold()
	assert must_cell(s, active_pt(0, 0)).cell.has_hyperlink
	assert must_cell(s, active_pt(1, 0)).cell.has_hyperlink
}

fn test_screen_dump_string_bounded_region() ! {
	mut s := Screen.init(5, 3, 0)!
	defer { s.deinit() }

	s.test_write_string('ABCDE\nFGHIJ\nKLMNO')!
	result := s.dump_string(DumpStringOptions{
		tl:     must_pin(s, active_pt(1, 0))
		br:     must_pin(s, active_pt(2, 1))
		unwrap: false
	})!
	assert result == 'BCDE\nFGH'
}

// Ghostty's Screen.resize tracks the saved cursor with a pin so reflow
// moves it along with its cell.
fn test_screen_resize_more_cols_reflows_saved_cursor() ! {
	mut s := Screen.init(2, 3, 5)!
	defer { s.deinit() }
	s.test_write_string('1A2B')!
	s.saved_cursor = SavedCursor{
		x: 1
		y: 1
	}

	s.resize(ScreenResize{ cols: 5, rows: 3, reflow: true })!

	sc := s.saved_cursor or {
		assert false, 'saved cursor was dropped'
		return
	}
	assert sc.x == 3
	assert sc.y == 0
	assert !sc.pending_wrap
}

// Selections are tracked pins, so reflow remaps both ends and keeps the
// selection's orientation.
fn test_screen_resize_more_cols_reflows_selection() ! {
	mut s := Screen.init(2, 3, 5)!
	defer { s.deinit() }
	s.test_write_string('1A2B')!
	s.select(Selection.init(must_pin(s, active_pt(1, 1)), must_pin(s, active_pt(0, 0)),
		false))!

	s.resize(ScreenResize{ cols: 5, rows: 3, reflow: true })!

	sel := s.selection or {
		assert false, 'selection was dropped'
		return
	}
	// Preserve the backwards orientation while remapping B and 1.
	assert must_point(s, .active, sel.start()) == active_pt(3, 0)
	assert must_point(s, .active, sel.end()) == active_pt(0, 0)
}

// A pinned viewport follows its row through reflow.
fn test_screen_resize_more_cols_reflows_pinned_viewport() ! {
	mut s := Screen.init(2, 2, 10)!
	defer { s.deinit() }
	s.test_write_string('ABCD\nEF\nGH')!
	assert must_point(s, .screen, s.pages.get_top_left(.active)) == screen_pt(0, 2)
	s.scroll(ScrollRow{ n: 1 })
	assert s.pages.viewport == .pin

	s.resize(ScreenResize{ cols: 4, rows: 2, reflow: true })!

	// The old row 1 was the continuation "CD". It was unwrapped into row 0,
	// so the tracked viewport follows it instead of jumping to active row 1.
	assert must_point(s, .screen, s.pages.get_top_left(.active)) == screen_pt(0, 1)
	assert s.pages.viewport == .pin
	assert must_point(s, .screen, s.pages.get_top_left(.viewport)).coord().y == 0
}

// Ghostty's Screen.clone builds a fresh cursor with only the position and
// page pointers; every other cursor field starts at its default. The cloned
// pages own their managed memory (graphemes, styles, hyperlinks).
fn test_screen_clone_deep_copies_managed_cells_and_resets_cursor_state() ! {
	mut s := Screen.init(3, 2, 10)!
	defer { s.deinit() }
	s.set_attribute(SgrBold{})!
	s.start_hyperlink('https://example.com/screen-clone', 'screen-clone')!
	s.test_write_string('x\u0301')!
	s.cursor.is_protected = true
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_eol })

	mut cloned := s.clone(screen_pt(0, 0), none)!
	defer { cloned.deinit() }
	if true {
		list_cell := must_cell(cloned, active_pt(0, 0))
		page := &list_cell.node.data
		assert list_cell.cell.codepoint == u32(`x`)
		graphemes := page.lookup_grapheme(list_cell.cell) or { []u32{} }
		assert graphemes == [u32(0x0301)]
		assert list_cell.style().flags.bold()
		id := page.lookup_hyperlink(list_cell.cell) or {
			assert false, 'cloned cell has no hyperlink'
			return
		}
		assert page.hyperlink_set.get(id).uri == 'https://example.com/screen-clone'
	}
	assert cloned.cursor.x == 1
	assert cloned.cursor.y == 0
	assert !cloned.cursor.pending_wrap
	assert !cloned.cursor.is_protected
	assert cloned.cursor.style.default()
	assert cloned.cursor.style_id == default_style_id
	assert cloned.cursor.hyperlink_id == 0
	assert cloned.cursor.hyperlink_implicit_id == 0
	assert cloned.cursor.hyperlink_state == none
	assert cloned.cursor.semantic_content == .output
	assert !cloned.cursor.semantic_content_clear_eol

	// Clearing the source must not affect the clone's page memory.
	s.clear_rows(active_pt(0, 0), none, false)
	assert s.dump_string_alloc(.screen)! == ''
	if true {
		list_cell := must_cell(cloned, active_pt(0, 0))
		page := &list_cell.node.data
		assert list_cell.cell.codepoint == u32(`x`)
		graphemes := page.lookup_grapheme(list_cell.cell) or { []u32{} }
		assert graphemes == [u32(0x0301)]
		assert list_cell.style().flags.bold()
		id := page.lookup_hyperlink(list_cell.cell) or {
			assert false, 'cloned cell lost its hyperlink'
			return
		}
		assert page.hyperlink_set.get(id).uri == 'https://example.com/screen-clone'
	}
}

// Ghostty's promptClickMove accepts either an input pen or an input cell
// under the cursor.
fn test_screen_prompt_click_move_uses_input_under_cursor() ! {
	mut s := Screen.init(20, 5, 0)!
	defer { s.deinit() }
	s.semantic_prompt.click = SemanticClick.from_cl(.line)
	s.cursor_set_semantic_content(CursorSemanticPrompt{ kind: .initial })
	s.test_write_string('> ')!
	s.cursor_set_semantic_content(CursorSemanticInput{ clear: .clear_eol })
	s.test_write_string('hello')!

	// The pending pen state is output, but the cursor is moved onto an input
	// cell that was already written. Ghostty permits prompt navigation here.
	s.cursor_set_semantic_content(CursorSemanticOutput{})
	s.cursor_absolute(2, 0)
	r := s.prompt_click_move(must_pin(s, active_pt(4, 0)))
	assert r.right == 2
	assert r.left == 0
}

fn test_key_flag_stack_wraps_at_capacity() ! {
	mut stack := KeyFlagStack{}
	for value in 1 .. 9 {
		stack.push(KeyFlags.from_int(u8(value)))
	}
	assert stack.idx == 0
	assert stack.current().int() == 8

	stack.pop(1)
	assert stack.idx == 7
	assert stack.current().int() == 7
}

fn test_key_flag_stack_pop_zero_is_noop() ! {
	mut stack := KeyFlagStack{}
	stack.push(KeyFlags.from_int(5))
	stack.pop(0)
	assert stack.current().int() == 5
}

fn test_key_flag_stack_large_pop_resets_all_entries() ! {
	mut stack := KeyFlagStack{}
	stack.set(.set_, KeyFlags.from_int(3))
	stack.push(KeyFlags.from_int(5))
	stack.pop(256)
	assert stack.idx == 0
	assert stack.current() == key_flags_disabled
	assert stack.flags == [8]KeyFlags{init: key_flags_disabled}
}
