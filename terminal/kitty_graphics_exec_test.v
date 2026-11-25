module terminal


fn make_graphics_terminal() !Terminal {
	mut t := Terminal.init(Options{
		rows: 5
		cols: 5
	})!
	t.width_px = 50
	t.height_px = 100
	return t
}

fn add_graphics_scroll_placement(mut t Terminal, id u32, row u32, col u32, rows u32) ! {
	t.screens.active.cursor_absolute(col, row)
	cmd := CommandParser.parse_string('a=T,f=24,i=${id},s=1,v=4,c=2,r=${rows},C=1;////////////////')!
	response := kitty_graphics_execute(mut t, &cmd) or { return error('expected placement response') }
	assert response.ok()
}

fn graphics_placement_row(t &Terminal, id u32) !u32 {
	screen := t.screens.active
	for entry in screen.kitty_images.placements {
		if entry.key.image_id == id {
			location := entry.value.location as PlacementPin
			point := screen.pages.point_from_pin(.active, *location.pin) or {
				return error('placement is outside the active screen')
			}
			return point.coord().y
		}
	}
	return error('placement was removed')
}

fn test_graphics_scroll_respects_rectangular_margins() ! {
	mut t := make_graphics_terminal()!
	defer { t.deinit() }
	t.set_top_and_bottom_margin(2, 4)
	t.modes.set(.enable_left_and_right_margin, true)
	t.set_left_and_right_margin(2, 4)
	add_graphics_scroll_placement(mut t, 1, 2, 1, 1)!
	add_graphics_scroll_placement(mut t, 2, 2, 0, 1)!
	add_graphics_scroll_placement(mut t, 3, 2, 3, 1)!

	t.scroll_up(1)!
	assert graphics_placement_row(&t, 1)! == 1
	assert graphics_placement_row(&t, 2)! == 2
	assert graphics_placement_row(&t, 3)! == 2

	t.set_cursor_pos(2, 2)
	t.reverse_index()
	assert graphics_placement_row(&t, 1)! == 2
	assert graphics_placement_row(&t, 2)! == 2
	assert graphics_placement_row(&t, 3)! == 2
}

fn test_graphics_scroll_clips_the_source_and_keeps_the_image() ! {
	mut t := make_graphics_terminal()!
	defer { t.deinit() }
	t.set_top_and_bottom_margin(2, 4)
	add_graphics_scroll_placement(mut t, 1, 1, 0, 2)!
	add_graphics_scroll_placement(mut t, 2, 2, 3, 2)!

	t.set_cursor_pos(4, 1)
	t.index()!
	assert graphics_placement_row(&t, 1)! == 1
	assert graphics_placement_row(&t, 2)! == 1
	storage := &t.screens.active.kitty_images
	first := storage.placements[0].value
	assert first.rows == 1
	assert first.source_y == 2
	assert first.source_height == 2

	t.scroll_down(2)
	assert graphics_placement_row(&t, 1)! == 3
	assert graphics_placement_row(&t, 2)! == 3
	second := storage.placements[1].value
	assert second.rows == 1
	assert second.source_y == 0
	assert second.source_height == 2

	t.scroll_down(1)
	assert storage.placement_count() == 0
	assert storage.image_count() == 2
}

fn test_graphics_scroll_into_history_preserves_placements_below_margin() ! {
	mut t := make_graphics_terminal()!
	defer { t.deinit() }
	t.set_top_and_bottom_margin(1, 4)
	add_graphics_scroll_placement(mut t, 1, 2, 1, 1)!
	add_graphics_scroll_placement(mut t, 2, 4, 1, 1)!

	t.scroll_up(2)!
	assert graphics_placement_row(&t, 1)! == 0
	assert graphics_placement_row(&t, 2)! == 4
}

fn test_graphics_placement_overwrite_releases_the_old_anchor() ! {
	mut t := make_graphics_terminal()!
	defer { t.deinit() }
	tracked := t.screens.active.pages.count_tracked_pins()
	storage := &t.screens.active.kitty_images

	transmit := CommandParser.parse_string('a=T,f=24,i=1,p=4,s=1,v=1,c=1,r=1,C=1;////')!
	first := kitty_graphics_execute(mut t, &transmit) or { return error('expected response') }
	assert first.ok()

	move := CommandParser.parse_string('a=p,i=1,p=4,c=2,r=2,C=1')!
	for row in u32(2) .. u32(5) {
		t.set_cursor_pos(row, 2)
		response := kitty_graphics_execute(mut t, &move) or { return error('expected response') }
		assert response.ok()
		assert storage.placement_count() == 1
		assert t.screens.active.pages.count_tracked_pins() == tracked + 1
		assert graphics_placement_row(&t, 1)! == row - 1
		assert storage.placements[0].value.rows == 2
	}

	virtual := CommandParser.parse_string('a=p,i=1,p=4,c=2,r=2,U=1')!
	response := kitty_graphics_execute(mut t, &virtual) or { return error('expected response') }
	assert response.ok()
	assert storage.placement_count() == 1
	assert storage.placements[0].value.location is PlacementVirtual
	assert t.screens.active.pages.count_tracked_pins() == tracked
}

fn test_graphics_erase_scrollback_removes_history_anchors() ! {
	mut t := make_graphics_terminal()!
	defer { t.deinit() }
	tracked := t.screens.active.pages.count_tracked_pins()
	mut storage := &t.screens.active.kitty_images
	add_graphics_scroll_placement(mut t, 1, 0, 1, 1)!
	add_graphics_scroll_placement(mut t, 2, 3, 1, 1)!
	virtual := CommandParser.parse_string('a=p,i=1,p=7,c=1,r=1,U=1')!
	response := kitty_graphics_execute(mut t, &virtual) or { return error('expected response') }
	assert response.ok()
	t.set_cursor_pos(5, 1)
	t.index()!

	assert storage.placement_count() == 3
	assert t.screens.active.pages.total_rows == 6
	t.erase_display(.scrollback, false)
	assert storage.placement_count() == 2
	assert storage.image_count() == 2
	assert t.screens.active.pages.total_rows == 5
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
	assert graphics_placement_row(&t, 2)! == 2
	assert storage.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 7)
	}) != none

	// Clearing history can expose an active placement when the viewport
	// is scrolled up, even if no placement is removed this time.
	t.index()!
	t.screens.active.scroll(ScrollTop{})
	assert !t.screens.active.viewport_is_bottom()
	storage.dirty = false
	t.erase_display(.scrollback, false)
	assert t.screens.active.viewport_is_bottom()
	assert storage.dirty
	assert storage.placement_count() == 2
}

fn test_graphics_resize_without_scrollback_removes_dropped_anchors() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 10, max_scrollback: 0 })!
	defer { t.deinit() }
	t.width_px = 100
	t.height_px = 60
	t.print_string('one\ntwo\nthree')!
	add_graphics_scroll_placement(mut t, 1, 0, 1, 1)!
	add_graphics_scroll_placement(mut t, 2, 2, 1, 1)!

	t.resize(10, 2)!
	storage := &t.screens.active.kitty_images
	assert t.screens.active.pages.total_rows == 2
	assert storage.placement_count() == 1
	assert storage.image_count() == 2
	assert graphics_placement_row(&t, 2)! == 1
}

fn test_graphics_execute_persists_transmitted_image() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	cmd := CommandParser.parse_string('a=t,f=24,t=d,i=1,s=1,v=1;////')!
	response := kitty_graphics_execute(mut t, &cmd) or { panic('expected transmit response') }
	assert response.ok()
	assert response.id == 1

	storage := &t.screens.active.kitty_images
	assert storage.image_count() == 1
	image := storage.image_by_id(1) or { panic('expected transmitted image') }
	assert image.data == [u8(255), 255, 255]
}

fn test_graphics_retransmit_removes_placements_after_the_last_chunk() ! {
	mut t := make_graphics_terminal()!
	defer { t.deinit() }
	tracked := t.screens.active.pages.count_tracked_pins()
	storage := &t.screens.active.kitty_images

	for command in [
		'a=T,f=24,i=1,p=1,s=1,v=1,c=1,r=1,C=1;////',
		'a=p,i=1,p=2,c=1,r=1,C=1',
		'a=p,i=1,p=3,c=1,r=1,U=1',
		'a=T,f=24,i=2,p=1,s=1,v=1,c=1,r=1,C=1;/wAA',
	] {
		cmd := CommandParser.parse_string(command)!
		response := kitty_graphics_execute(mut t, &cmd) or { return error('expected response') }
		assert response.ok()
	}
	assert storage.placement_count() == 4
	assert t.screens.active.pages.count_tracked_pins() == tracked + 3

	first := CommandParser.parse_string('a=t,f=24,i=1,s=1,v=2,m=1;AP8A')!
	assert kitty_graphics_execute(mut t, &first) == none
	assert storage.placement_count() == 4
	last := CommandParser.parse_string('m=0;AP8A')!
	reply := kitty_graphics_execute(mut t, &last) or { return error('expected transmit response') }
	assert reply.ok()
	assert storage.placement_count() == 1
	assert storage.placements[0].key.image_id == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
	assert (storage.image_by_id(1) or { return error('expected replacement') }).data == [
		u8(0), 255, 0, 0, 255, 0,
	]

	t.set_cursor_pos(3, 3)
	place := CommandParser.parse_string('a=p,i=1,p=1,c=1,r=2,C=1')!
	placed := kitty_graphics_execute(mut t, &place) or { return error('expected display response') }
	assert placed.ok()
	assert graphics_placement_row(&t, 1)! == 2
}

fn test_graphics_execute_reports_invalid_image_length_as_invalid_data() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	cmd := CommandParser.parse_string('a=t,f=24,t=d,i=1,s=2,v=2;////')!
	response := kitty_graphics_execute(mut t, &cmd) or { panic('expected transmit error') }
	assert !response.ok()
	assert response.message == 'EINVAL: invalid data'
}

fn test_graphics_execute_chunked_quiet_inheritance() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	// The first chunk suppresses successful responses with q=1.
	first := CommandParser.parse_string('a=t,f=24,t=d,i=1,s=1,v=2,m=1,q=1;////')!
	assert kitty_graphics_execute(mut t, &first) == none
	storage_loading := &t.screens.active.kitty_images
	assert storage_loading.loading != none

	// With q omitted, the final chunk inherits q=1 from the first chunk.
	last := CommandParser.parse_string('m=0;////')!
	assert kitty_graphics_execute(mut t, &last) == none
	storage := &t.screens.active.kitty_images
	assert storage.loading == none
	image := storage.image_by_id(1) or { panic('expected completed image') }
	assert image.data.len == 6
}

fn test_graphics_execute_chunked_q0_responds_on_final_chunk() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	first := CommandParser.parse_string('a=t,f=24,t=d,s=1,v=2,c=10,r=1,m=1,i=1,q=0;////')!
	assert kitty_graphics_execute(mut t, &first) == none

	last := CommandParser.parse_string('m=0;////')!
	response := kitty_graphics_execute(mut t, &last) or { panic('expected final response') }
	assert response.ok()
}

fn test_graphics_execute_chunk_can_increase_quiet_level() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	first := CommandParser.parse_string('a=t,f=24,t=d,s=1,v=2,c=10,r=1,m=1,i=1,q=0;////')!
	assert kitty_graphics_execute(mut t, &first) == none

	last := CommandParser.parse_string('m=0,q=1;////')!
	assert kitty_graphics_execute(mut t, &last) == none
}

fn test_graphics_execute_defaults_to_rgba() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	cmd := CommandParser.parse_string('a=t,t=d,i=1,s=1,v=2,c=10,r=1;///////////')!
	response := kitty_graphics_execute(mut t, &cmd) or { panic('expected transmit response') }
	assert response.ok()
	storage := &t.screens.active.kitty_images
	image := storage.image_by_id(1) or { panic('expected transmitted image') }
	assert image.format == .rgba
}

fn test_graphics_execute_accepts_extreme_protocol_integers() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	max_id := CommandParser.parse_string('a=p,i=4294967295')!
	max_id_response := kitty_graphics_execute(mut t, &max_id) or { panic('expected display error') }
	assert !max_id_response.ok()
	assert max_id_response.message == 'ENOENT: image not found'

	min_z := CommandParser.parse_string('a=p,i=1,z=-2147483648')!
	min_z_response := kitty_graphics_execute(mut t, &min_z) or { panic('expected display error') }
	assert !min_z_response.ok()
	assert min_z_response.message == 'ENOENT: image not found'
}

fn test_graphics_execute_implicit_transmits_do_not_respond() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	transmit := CommandParser.parse_string('a=t,f=24,t=d,s=1,v=2,c=10,r=1,i=0,I=0;////////')!
	assert kitty_graphics_execute(mut t, &transmit) == none

	transmit_display := CommandParser.parse_string('a=T,f=24,t=d,s=1,v=2,c=10,r=1,i=0,I=0;////////')!
	assert kitty_graphics_execute(mut t, &transmit_display) == none
}

fn test_graphics_quiet_inheritance_only_applies_to_transmissions() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	base := CommandParser.parse_string('a=t,f=24,t=d,i=1,s=1,v=1;////')!
	assert (kitty_graphics_execute(mut t, &base) or { panic('expected base response') }).ok()
	first_chunk := CommandParser.parse_string('a=t,f=24,t=d,i=2,s=1,v=2,m=1,q=1;////')!
	assert kitty_graphics_execute(mut t, &first_chunk) == none

	// A display issued while another image is loading uses its own q=0; it
	// must not inherit the in-progress transmission's q=1.
	display := CommandParser.parse_string('a=p,i=1,p=3,c=1,r=1,C=1')!
	response := kitty_graphics_execute(mut t, &display) or { panic('expected display response') }
	assert response.ok()
	assert response.id == 1
}

fn test_graphics_execute_display_and_delete_use_persistent_storage() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	transmit := CommandParser.parse_string('a=t,f=24,t=d,i=7,s=1,v=1;////')!
	assert (kitty_graphics_execute(mut t, &transmit) or { panic('expected transmit response') }).ok()

	display := CommandParser.parse_string('a=p,i=7,p=9,c=1,r=1,C=1')!
	display_response := kitty_graphics_execute(mut t, &display) or { panic('expected display response') }
	assert display_response.ok()
	assert display_response.id == 7
	storage_after_display := &t.screens.active.kitty_images
	assert storage_after_display.placement_count() == 1

	delete_cmd := CommandParser.parse_string('a=d,d=I,i=7')!
	assert kitty_graphics_execute(mut t, &delete_cmd) == none
	storage_after_delete := &t.screens.active.kitty_images
	assert storage_after_delete.placement_count() == 0
	assert storage_after_delete.image_count() == 0
}

fn test_graphics_execute_respects_disabled_storage() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}
	t.screens.active.kitty_images.set_limit(mut t.screens.active, 0)

	query := CommandParser.parse_string('a=q,f=24,t=d,i=1,s=1,v=1;////')!
	assert kitty_graphics_execute(mut t, &query) == none
	storage := &t.screens.active.kitty_images
	assert !storage.enabled()
	assert storage.image_count() == 0
}

fn test_graphics_storage_follows_screen_reset_and_switch_lifecycle() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	transmit := CommandParser.parse_string('a=t,f=24,t=d,i=1,s=1,v=1;////')!
	assert (kitty_graphics_execute(mut t, &transmit) or { panic('expected transmit response') }).ok()
	mut primary_storage := &t.screens.active.kitty_images
	assert primary_storage.image_count() == 1

	// DEC RIS replaces the storage with a fresh one (so the limit returns
	// to its default) and leaves the renderer-facing dirty bit set.
	t.screens.active.reset()
	primary_storage = &t.screens.active.kitty_images
	assert primary_storage.image_count() == 0
	assert primary_storage.total_limit == ImageStorage{}.total_limit
	assert primary_storage.dirty

	primary_storage.dirty = false
	t.switch_screen(.alternate)!
	t.switch_screen(.primary)!
	primary_storage = &t.screens.active.kitty_images
	assert primary_storage.dirty
}

fn test_graphics_storage_follows_terminal_clear_and_scroll_lifecycle() ! {
	mut t := make_graphics_terminal()!
	defer {
		t.deinit()
	}

	transmit := CommandParser.parse_string('a=t,f=24,t=d,i=1,s=1,v=1;////')!
	assert (kitty_graphics_execute(mut t, &transmit) or { panic('expected transmit response') }).ok()
	display := CommandParser.parse_string('a=p,i=1,p=1,c=1,r=1,C=1')!
	assert (kitty_graphics_execute(mut t, &display) or { panic('expected display response') }).ok()
	mut storage := &t.screens.active.kitty_images
	assert storage.image_count() == 1
	assert storage.placement_count() == 1

	storage.dirty = false
	t.screens.active.scroll(ScrollTop{})
	assert storage.dirty

	t.erase_display(.complete, false)
	storage = &t.screens.active.kitty_images
	assert storage.placement_count() == 0
	assert storage.image_count() == 0
	assert storage.dirty
}
