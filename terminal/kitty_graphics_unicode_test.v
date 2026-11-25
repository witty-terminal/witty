module terminal

// Tests for Kitty graphics protocol unicode placement feature.
//
// Source: graphics_unicode.zig tests


fn test_unicode_diacritic_sorted() {
	// diacritics must be sorted since we use a binary search.
	for i in 1 .. diacritics.len {
		assert diacritics[i - 1] < diacritics[i], 'diacritics not sorted at index ${i}'
	}
}

fn test_unicode_diacritic() {
	// Some spot checks based on Kitty behavior
	assert get_index(0x483) or { panic('expected diacritic 0x483') } == 30
	assert get_index(0x1d242) or { panic('expected diacritic 0x1d242') } == 294
}

fn test_unicode_placement_none() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Single cell
	t.print_string('hello\nworld\n1\n2')!

	// No placements
	pin := t.screens.active.pages.get_top_left(.viewport)
	mut it := placement_iterator(pin, none)
	assert it.next() == none
}

fn test_unicode_placement_single_row_col() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Single cell
	t.print_string('\U0010EEEE̅̅')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
	}
	assert it.next() == none
}

fn test_unicode_placement_continuation_break() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 10 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Two runs because it jumps cols
	t.print_string('\U0010EEEE̅̅')!
	t.print_string('\U0010EEEE̅̎')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected first placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
		assert p.width == 1
	}
	{
		p := it.next() or { panic('expected second placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 2
		assert p.width == 1
	}
	assert it.next() == none
}

fn test_unicode_placement_continuation_with_diacritics_set() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 10 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Three cells. They'll continue even though they're explicit
	t.print_string('\U0010EEEE̅̅')!
	t.print_string('\U0010EEEE̅̍')!
	t.print_string('\U0010EEEE̅̎')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
		assert p.width == 3
	}
	assert it.next() == none
}

fn test_unicode_placement_continuation_with_no_col() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 10 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Three cells. They'll continue even though they're explicit
	t.print_string('\U0010EEEE̅̅')!
	t.print_string('\U0010EEEE̅')!
	t.print_string('\U0010EEEE̅')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
		assert p.width == 3
	}
	assert it.next() == none
}

fn test_unicode_placement_continuation_with_no_diacritics() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 10 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Three cells. They'll continue even though they're explicit
	t.print_string('\U0010EEEE')!
	t.print_string('\U0010EEEE')!
	t.print_string('\U0010EEEE')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
		assert p.width == 3
	}
	assert it.next() == none
}

fn test_unicode_placement_run_ending() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 10 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Three cells. They'll continue even though they're explicit
	t.print_string('\U0010EEEE̅̅')!
	t.print_string('\U0010EEEE̅̍')!
	t.print_string('ABC')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
		assert p.width == 2
	}
	assert it.next() == none
}

fn test_unicode_placement_run_starting_in_the_middle() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 10 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Three cells. They'll continue even though they're explicit
	t.print_string('ABC')!
	t.print_string('\U0010EEEE̅̅')!
	t.print_string('\U0010EEEE̅̍')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 0
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
		assert p.width == 2
	}
	assert it.next() == none
}

fn test_unicode_placement_specifying_image_id_as_palette() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Single cell
	t.set_attribute(SgrFg256{ idx: 42 })!
	t.print_string('\U0010EEEE̅̅')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 42
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
	}
	assert it.next() == none
}

fn test_unicode_placement_specifying_image_id_with_high_bits() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Single cell
	t.set_attribute(SgrFg256{ idx: 42 })!
	t.print_string('\U0010EEEE̅̅̎')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 33554474
		assert p.placement_id == 0
		assert p.row == 0
		assert p.col == 0
	}
	assert it.next() == none
}

fn test_unicode_placement_specifying_placement_id_as_palette() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Single cell
	t.set_attribute(SgrFg256{ idx: 42 })!
	t.set_attribute(SgrUnderlineColor256{ idx: 21 })!
	t.print_string('\U0010EEEE̅̅')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 42
		assert p.placement_id == 21
		assert p.row == 0
		assert p.col == 0
	}
	assert it.next() == none
}

// Witty-only: covers the rgb branch of colorToId for the placement ID.
fn test_unicode_placement_specifying_placement_id_as_rgb() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer {
		t.deinit()
	}
	t.modes.set(.grapheme_cluster, true)

	// Single cell
	t.set_attribute(SgrFg256{ idx: 42 })!
	t.set_attribute(SgrUnderlineColor{ rgb: RGB{ r: 0x12, g: 0x34, b: 0x56 } })!
	t.print_string('\U0010EEEE̅̅')!

	// Get our top left pin
	pin := t.screens.active.pages.get_top_left(.viewport)

	// Should have exactly one placement
	mut it := placement_iterator(pin, none)
	{
		p := it.next() or { panic('expected placement') }
		assert p.image_id == 42
		assert p.placement_id == 0x123456
		assert p.row == 0
		assert p.col == 0
	}
	assert it.next() == none
}

// Fish:
// printf "\033_Gf=100,i=1,t=f,q=2;$(printf dog.png | base64)\033\\"
// printf "\e[38;5;1m\U10EEEE\U0305\U0305\U10EEEE\U0305\U030D\U10EEEE\U0305\U030E\U10EEEE\U0305\U0310\e[39m\n"
// printf "\e[38;5;1m\U10EEEE\U030D\U0305\U10EEEE\U030D\U030D\U10EEEE\U030D\U030E\U10EEEE\U030D\U0310\e[39m\n"
// printf "\033_Ga=p,i=1,U=1,q=2,c=4,r=2\033\\"
fn test_unicode_render_placement_dog_4x2() ! {
	cell_width := u32(36)
	cell_height := u32(80)

	mut t := Terminal.init(Options{ cols: 100, rows: 100 })!
	defer {
		t.deinit()
	}
	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}

	image := Image{
		id:     1
		width:  500
		height: 306
	}
	s.add_image(mut t.screens.active, image)!
	s.add_placement(mut t.screens.active, 1, 0, Placement{
		location: PlacementVirtual{}
		columns:  4
		rows:     2
	})

	// Row 1
	{
		p := VirtualPlacement{
			pin:          *t.screens.active.cursor.page_pin
			image_id:     1
			placement_id: 0
			col:          0
			row:          0
			width:        4
			height:       1
		}
		rp := p.render_placement(&s, &image, cell_width, cell_height)!
		assert rp.offset_x == 0
		assert rp.offset_y == 36
		assert rp.source_x == 0
		assert rp.source_y == 0
		assert rp.source_width == 500
		assert rp.source_height == 153
		assert rp.dest_width == 144
		assert rp.dest_height == 44
	}
	// Row 2
	{
		p := VirtualPlacement{
			pin:          *t.screens.active.cursor.page_pin
			image_id:     1
			placement_id: 0
			col:          0
			row:          1
			width:        4
			height:       1
		}
		rp := p.render_placement(&s, &image, cell_width, cell_height)!
		assert rp.offset_x == 0
		assert rp.offset_y == 0
		assert rp.source_x == 0
		assert rp.source_y == 153
		assert rp.source_width == 500
		assert rp.source_height == 153
		assert rp.dest_width == 144
		assert rp.dest_height == 44
	}
}

// Fish:
// printf "\033_Gf=100,i=1,t=f,q=2;$(printf dog.png | base64)\033\\"
// printf "\e[38;5;1m\U10EEEE\U0305\U0305\U10EEEE\U0305\U030D\U10EEEE\U0305\U030E\U10EEEE\U0305\U0310\e[39m\n"
// printf "\e[38;5;1m\U10EEEE\U030D\U0305\U10EEEE\U030D\U030D\U10EEEE\U030D\U030E\U10EEEE\U030D\U0310\e[39m\n"
// printf "\033_Ga=p,i=1,U=1,q=2,c=2,r=2\033\\"
fn test_unicode_render_placement_dog_2x2_with_blank_cells() ! {
	cell_width := u32(36)
	cell_height := u32(80)

	mut t := Terminal.init(Options{ cols: 100, rows: 100 })!
	defer {
		t.deinit()
	}
	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}

	image := Image{
		id:     1
		width:  500
		height: 306
	}
	s.add_image(mut t.screens.active, image)!
	s.add_placement(mut t.screens.active, 1, 0, Placement{
		location: PlacementVirtual{}
		columns:  2
		rows:     2
	})

	// Row 1
	{
		p := VirtualPlacement{
			pin:          *t.screens.active.cursor.page_pin
			image_id:     1
			placement_id: 0
			col:          0
			row:          0
			width:        4
			height:       1
		}
		rp := p.render_placement(&s, &image, cell_width, cell_height)!
		assert rp.offset_x == 0
		assert rp.offset_y == 58
		assert rp.source_x == 0
		assert rp.source_y == 0
		assert rp.source_width == 500
		assert rp.source_height == 153
		assert rp.dest_width == 72
		assert rp.dest_height == 22
	}
	// Row 2
	{
		p := VirtualPlacement{
			pin:          *t.screens.active.cursor.page_pin
			image_id:     1
			placement_id: 0
			col:          0
			row:          1
			width:        4
			height:       1
		}
		rp := p.render_placement(&s, &image, cell_width, cell_height)!
		assert rp.offset_x == 0
		assert rp.offset_y == 0
		assert rp.source_x == 0
		assert rp.source_y == 153
		assert rp.source_width == 500
		assert rp.source_height == 153
		assert rp.dest_width == 72
		assert rp.dest_height == 22
	}
}

// Fish:
// printf "\033_Gf=100,i=1,t=f,q=2;$(printf dog.png | base64)\033\\"
// printf "\e[38;5;1m\U10EEEE\U0305\U0305\U10EEEE\U0305\U030D\U10EEEE\U0305\U030E\U10EEEE\U0305\U0310\e[39m\n"
// printf "\033_Ga=p,i=1,U=1,q=2,c=1,r=1\033\\"
fn test_unicode_render_placement_dog_1x1() ! {
	cell_width := u32(36)
	cell_height := u32(80)

	mut t := Terminal.init(Options{ cols: 100, rows: 100 })!
	defer {
		t.deinit()
	}
	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}

	image := Image{
		id:     1
		width:  500
		height: 306
	}
	s.add_image(mut t.screens.active, image)!
	s.add_placement(mut t.screens.active, 1, 0, Placement{
		location: PlacementVirtual{}
		columns:  1
		rows:     1
	})

	// Row 1
	{
		p := VirtualPlacement{
			pin:          *t.screens.active.cursor.page_pin
			image_id:     1
			placement_id: 0
			col:          0
			row:          0
			width:        4
			height:       1
		}
		rp := p.render_placement(&s, &image, cell_width, cell_height)!
		assert rp.offset_x == 0
		assert rp.offset_y == 29
		assert rp.source_x == 0
		assert rp.source_y == 0
		assert rp.source_width == 500
		assert rp.source_height == 306
		assert rp.dest_width == 36
		assert rp.dest_height == 22
	}
}

fn test_unicode_render_placement_prefers_lowest_explicit_id() ! {
	mut t := Terminal.init(Options{ cols: 5, rows: 5 })!
	defer {
		t.deinit()
	}
	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	image := Image{ id: 42, width: 24, height: 18 }
	s.add_image(mut t.screens.active, image)!
	s.add_placement(mut t.screens.active, 42, 0, Placement{
		location: PlacementVirtual{}
		columns:  3
		rows:     2
	})
	s.add_placement(mut t.screens.active, 42, 9, Placement{
		location: PlacementVirtual{}
		columns:  2
		rows:     1
	})
	s.add_placement(mut t.screens.active, 42, 4, Placement{
		location: PlacementVirtual{}
		columns:  4
		rows:     2
	})

	implicit := VirtualPlacement{ image_id: 42 }
	rows, columns := implicit.grid(&s, &image, 10, 20)!
	assert rows == 2
	assert columns == 4

	explicit := VirtualPlacement{ image_id: 42, placement_id: 9 }
	explicit_rows, explicit_columns := explicit.grid(&s, &image, 10, 20)!
	assert explicit_rows == 1
	assert explicit_columns == 2
}

fn test_unicode_render_placement_rejects_invalid_grid() ! {
	mut t := Terminal.init(Options{ cols: 5, rows: 5 })!
	defer {
		t.deinit()
	}
	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	image := Image{ id: 42, width: u32(max_u16) + 1, height: 18 }
	s.add_image(mut t.screens.active, image)!
	s.add_placement(mut t.screens.active, 42, 0, Placement{ location: PlacementVirtual{} })
	placeholder := VirtualPlacement{ image_id: 42 }
	for cell_width in [u32(0), 1] {
		placeholder.render_placement(&s, &image, cell_width, 20) or {
			assert err.msg() == 'PlacementGridOutOfBounds'
			continue
		}
		assert false, 'expected invalid grid error for cell width ${cell_width}'
	}
}

// Witty-only: direct unit coverage of IncompletePlacement run merging.
fn test_incomplete_placement_can_append_same_image() {
	a := IncompletePlacement{
		image_id_low: 42
		row:          0
		col:          0
		width:        1
	}
	b := IncompletePlacement{
		image_id_low: 42
		row:          0
		col:          1
		width:        1
	}
	assert a.can_append(&b)
}

fn test_incomplete_placement_cannot_append_different_image() {
	a := IncompletePlacement{
		image_id_low: 42
		row:          0
		col:          0
		width:        1
	}
	b := IncompletePlacement{
		image_id_low: 99
		row:          0
		col:          1
		width:        1
	}
	assert !a.can_append(&b)
}

fn test_incomplete_placement_cannot_append_discontinuous_col() {
	a := IncompletePlacement{
		image_id_low: 42
		row:          0
		col:          0
		width:        1
	}
	b := IncompletePlacement{
		image_id_low: 42
		row:          0
		col:          2 // should be 1 (col + width)
		width:        1
	}
	assert !a.can_append(&b)
}

fn test_incomplete_placement_complete() {
	ip := IncompletePlacement{
		pin:           Pin{
			x: 3
			y: 5
		}
		image_id_low:  0x123456
		image_id_high: 0xAB
		placement_id:  42
		row:           7
		col:           2
		width:         3
	}
	vp := ip.complete()
	assert vp.pin.x == 3
	assert vp.pin.y == 5
	assert vp.image_id == 0xAB123456
	assert vp.placement_id == 42
	assert vp.row == 7
	assert vp.col == 2
	assert vp.width == 3
	assert vp.height == 1
}
