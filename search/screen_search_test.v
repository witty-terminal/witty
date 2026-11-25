module search

import highlight
import terminal

const screen_search_test_max_scrollback = uint(0xffffffffffffffff)

fn screen_pt(x u16, y u32) terminal.Point {
	return terminal.Point.new(.screen, terminal.Coordinate{ x: x, y: y })
}

fn active_pt(x u16, y u32) terminal.Point {
	return terminal.Point.new(.active, terminal.Coordinate{ x: x, y: y })
}

fn point_of(t &terminal.Terminal, tag terminal.PointTag, p terminal.Pin) terminal.Point {
	return t.screens.active.pages.point_from_pin(tag, p) or {
		panic('search result pin is not in the page list')
	}
}

fn selected_untracked(searcher &ScreenSearch) highlight.Untracked {
	selected := searcher.selected_match() or { panic('missing selected match') }
	return selected.untracked()
}

// Feed newlines until the page list has `pages` pages and then scroll a
// full screen, like the `while (list.totalPages() < n)` setup loops in the
// upstream tests.
fn grow_to_pages(mut t terminal.Terminal, mut s terminal.ReadonlyStream, pages uint) ! {
	for t.screens.active.pages.total_pages() < pages {
		s.next_slice('\r\n'.bytes())!
	}
	for _ in 0 .. t.screens.active.pages.rows {
		s.next_slice('\r\n'.bytes())!
	}
}

fn test_simple_search() ! {
	mut t := terminal.Terminal.init(terminal.Options{ cols: 10, rows: 2 })!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }
	s.next_slice('Fizz\r\nBuzz\r\nFizz\r\nBang'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!
	assert searcher.active_results.len == 2
	// We don't test history results since there is overlap

	// Get all matches
	matches := searcher.matches()
	assert matches.len == 2

	{
		sel := matches[0].untracked()
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 2)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 2)
	}
	{
		sel := matches[1].untracked()
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}
}

fn test_simple_search_with_history() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		cols:           10
		rows:           2
		max_scrollback: screen_search_test_max_scrollback
	})!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }

	s.next_slice('Fizz\r\n'.bytes())!
	grow_to_pages(mut t, mut s, 3)!
	s.next_slice('hello.'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!
	assert searcher.active_results.len == 0

	// Get all matches
	matches := searcher.matches()
	assert matches.len == 1

	{
		sel := matches[0].untracked()
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}
}

fn test_reload_active_with_history_change() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		cols:           10
		rows:           2
		max_scrollback: screen_search_test_max_scrollback
	})!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }
	s.next_slice('Fizz\r\n'.bytes())!

	// Start up our search which will populate our initial active area.
	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!
	{
		matches := searcher.matches()
		assert matches.len == 1
	}

	// Grow into two pages so our history pin will move.
	grow_to_pages(mut t, mut s, 2)!
	s.next_slice('2Fizz'.bytes())!

	// Active area changed so reload
	searcher.reload_active()!
	searcher.search_all()!

	// Get all matches
	{
		matches := searcher.matches()
		assert matches.len == 2
		{
			sel := matches[1].untracked()
			assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
			assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
		}
		{
			sel := matches[0].untracked()
			assert point_of(&t, .active, sel.start) == active_pt(1, 1)
			assert point_of(&t, .active, sel.end) == active_pt(4, 1)
		}
	}

	// Reset the screen which will make our pin garbage.
	t.full_reset()
	s.next_slice('WeFizzing'.bytes())!
	searcher.reload_active()!
	searcher.search_all()!

	{
		matches := searcher.matches()
		assert matches.len == 1
		{
			sel := matches[0].untracked()
			assert point_of(&t, .active, sel.start) == active_pt(2, 0)
			assert point_of(&t, .active, sel.end) == active_pt(5, 0)
		}
	}
}

fn test_active_change_contents() ! {
	mut t := terminal.Terminal.init(terminal.Options{ cols: 10, rows: 5 })!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }
	s.next_slice('Fuzz\r\nBuzz\r\nFizz\r\nBang'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!
	assert searcher.active_results.len == 1

	// Erase the screen, move our cursor to the top, and change contents.
	s.next_slice('\x1b[2J\x1b[H'.bytes())! // Clear screen and move home
	s.next_slice('Bang\r\nFizz\r\nHello!'.bytes())!

	searcher.reload_active()!
	searcher.search_all()!
	assert searcher.active_results.len == 1

	// Get all matches
	matches := searcher.matches()
	assert matches.len == 1

	{
		sel := matches[0].untracked()
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 1)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 1)
	}
}

fn test_select_next() ! {
	mut t := terminal.Terminal.init(terminal.Options{ cols: 10, rows: 2 })!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }
	s.next_slice('Fizz\r\nBuzz\r\nFizz\r\nBang'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }

	// Initially no selection
	assert searcher.selected_match() == none

	// Select our next match (first)
	searcher.search_all()!
	_ = searcher.do_select(.next)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 2)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 2)
	}

	// Next match
	_ = searcher.do_select(.next)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}

	// Advancing past the oldest match wraps to the newest.
	assert searcher.do_select(.next)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 2)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 2)
	}
}

fn test_select_in_active_changes_contents_completely() ! {
	mut t := terminal.Terminal.init(terminal.Options{ cols: 10, rows: 5 })!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }
	s.next_slice('Fizz\r\nBuzz\r\nFizz\r\nBang'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!
	_ = searcher.do_select(.next)!
	_ = searcher.do_select(.next)!
	{
		// Initial selection is the first fizz
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}

	// Erase the screen, move our cursor to the top, and change contents.
	s.next_slice('\x1b[2J\x1b[H'.bytes())! // Clear screen and move home
	s.next_slice('Fuzz\r\nFizz\r\nHello!'.bytes())!

	searcher.reload_active()!
	{
		// Our selection should move to the first
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 1)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 1)
	}

	// Erase the screen, redraw with same contents.
	s.next_slice('\x1b[2J\x1b[H'.bytes())! // Clear screen and move home
	s.next_slice('Fuzz\r\nFizz\r\nFizz'.bytes())!

	searcher.reload_active()!
	{
		// Our selection should not move to the first
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 1)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 1)
	}
}

fn test_select_into_history() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		cols:           10
		rows:           2
		max_scrollback: screen_search_test_max_scrollback
	})!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }

	s.next_slice('Fizz\r\n'.bytes())!
	grow_to_pages(mut t, mut s, 3)!
	s.next_slice('hello.'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!

	// Get all matches
	_ = searcher.do_select(.next)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}

	// Erase the screen, redraw with same contents.
	s.next_slice('\x1b[2J\x1b[H'.bytes())! // Clear screen and move home
	s.next_slice('yo yo'.bytes())!

	searcher.reload_active()!
	{
		// Our selection should not move since the history is still active.
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}

	// Create some new history by adding more lines.
	s.next_slice('\r\nfizz\r\nfizz\r\nfizz'.bytes())! // Clear screen and move home
	searcher.reload_active()!
	{
		// Our selection should not move since the history is still not
		// pruned.
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}
}

fn test_select_prev() ! {
	mut t := terminal.Terminal.init(terminal.Options{ cols: 10, rows: 2 })!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }
	s.next_slice('Fizz\r\nBuzz\r\nFizz\r\nBang'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }

	// Initially no selection
	assert searcher.selected_match() == none

	// Select prev (oldest first)
	searcher.search_all()!
	_ = searcher.do_select(.prev)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}

	// Prev match (towards newest)
	_ = searcher.do_select(.prev)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 2)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 2)
	}

	// Moving back from the newest match wraps to the oldest.
	assert searcher.do_select(.prev)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}
}

fn test_select_prev_then_next() ! {
	mut t := terminal.Terminal.init(terminal.Options{ cols: 10, rows: 2 })!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }
	s.next_slice('Fizz\r\nBuzz\r\nFizz\r\nBang'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!

	// Select next (newest first)
	_ = searcher.do_select(.next)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 2)
	}

	// Select next (older)
	_ = searcher.do_select(.next)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
	}

	// Select prev (back to newer)
	_ = searcher.do_select(.prev)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 2)
	}
}

fn test_select_prev_with_history() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		cols:           10
		rows:           2
		max_scrollback: screen_search_test_max_scrollback
	})!
	defer { t.deinit() }

	mut s := t.vt_stream()
	defer { s.deinit() }

	s.next_slice('Fizz\r\n'.bytes())!
	grow_to_pages(mut t, mut s, 3)!
	s.next_slice('Fizz.'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!

	// Select prev (oldest first, should be in history)
	_ = searcher.do_select(.prev)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .screen, sel.start) == screen_pt(0, 0)
		assert point_of(&t, .screen, sel.end) == screen_pt(3, 0)
	}

	// Select prev (towards newer, should move to active area)
	_ = searcher.do_select(.prev)!
	{
		sel := selected_untracked(&searcher)
		assert point_of(&t, .active, sel.start) == active_pt(0, 1)
		assert point_of(&t, .active, sel.end) == active_pt(3, 1)
	}
}

fn test_screen_search_no_scrollback_has_no_history() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		cols:           10
		rows:           2
		max_scrollback: 0
	})!
	defer { t.deinit() }

	// Alt screen has no scrollback
	_ = t.switch_screen(.alternate)!

	mut s := t.vt_stream()
	defer { s.deinit() }

	// This will probably stop working at some point and we'll have
	// no way to test it using public APIs, but at the time of writing
	// this test, CSI 22 J (scroll complete) pushes into scrollback
	// with alt screen.
	s.next_slice('Fizz\r\n'.bytes())!
	s.next_slice('\x1b[22J'.bytes())!
	s.next_slice('hello.'.bytes())!

	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!
	assert searcher.active_results.len == 0

	// Get all matches
	matches := searcher.matches()
	assert matches.len == 0
}

fn test_reload_active_history_append_existing_failure_cleanup() ! {
	assert sizeof(ReloadActiveFailPoint) == 1
	assert u8(ReloadActiveFailPoint.history_append_new) == 0
	assert u8(ReloadActiveFailPoint.history_append_existing) == 1

	mut t := terminal.Terminal.init(terminal.Options{
		cols:           10
		rows:           2
		max_scrollback: screen_search_test_max_scrollback
	})!
	defer { t.deinit() }
	mut s := t.vt_stream()
	defer { s.deinit() }

	s.next_slice('Fizz\r\nFizz\r\n'.bytes())!
	grow_to_pages(mut t, mut s, 3)!
	s.next_slice('Fizz.'.bytes())!
	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!

	s.next_slice('\r\nFizz\r\nFizz\r\n'.bytes())!
	grow_to_pages(mut t, mut s, 4)!

	mut tw := reload_active_tripwire()
	tw.error_always(.history_append_existing, error('OutOfMemory'))
	defer {
		tw.end(.reset) or { panic(err) }
	}
	if _ := searcher.do_select(.next) {
		assert false, 'expected history append failure'
	} else {
		assert err.msg() == 'OutOfMemory'
	}
}

fn test_reload_active_history_append_new_failure_cleanup() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		cols:           10
		rows:           2
		max_scrollback: screen_search_test_max_scrollback
	})!
	defer { t.deinit() }
	mut s := t.vt_stream()
	defer { s.deinit() }

	s.next_slice('Fizz\r\nFizz\r\n'.bytes())!
	grow_to_pages(mut t, mut s, 3)!
	s.next_slice('Fizz.'.bytes())!
	mut searcher := ScreenSearch.init(mut t.screens.active, 'Fizz'.bytes())!
	defer { searcher.deinit() }
	searcher.search_all()!

	s.next_slice('\r\nFizz\r\nFizz\r\n'.bytes())!
	grow_to_pages(mut t, mut s, 4)!

	mut tw := reload_active_tripwire()
	tw.error_after(.history_append_new, error('OutOfMemory'), 1)
	defer {
		tw.end(.reset) or { panic(err) }
	}
	if _ := searcher.do_select(.next) {
		assert false, 'expected history append failure'
	} else {
		assert err.msg() == 'OutOfMemory'
	}
}
