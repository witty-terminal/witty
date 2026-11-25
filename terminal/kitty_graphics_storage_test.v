module terminal

// Tests for Kitty graphics protocol image storage.
//
// Source: graphics_storage.zig tests


// Witty-only: Ghostty's PlacementId is a packed(u33) struct; Witty stores it
// in a u64 with the same bit layout.
fn test_placement_id_packed_layout_matches_ghostty() {
	assert sizeof(PlacementTag) == 1
	assert sizeof(PlacementId) == sizeof(u64)
	internal := PlacementId.init(.internal, 0x89abcdef)
	assert internal.int_val() == 0x1_1357_9bde
	assert internal.tag() == .internal
	assert internal.id() == 0x89abcdef
	external := PlacementId.init(.external, 0xffffffff)
	assert external.int_val() == 0x1_ffff_ffff
	assert external.tag() == .external
	assert external.id() == 0xffffffff
}

// A placement anchored on a tracked pin at the given active coordinate,
// like Ghostty's `.{ .location = .{ .pin = try trackPin(&t, pt) } }`.
fn pin_placement(mut t Terminal, x u16, y u32) Placement {
	return Placement{
		location: PlacementPin{
			pin: track_pin(mut t, Coordinate{ x: x, y: y }) or { panic(err) }
		}
	}
}

fn test_storage_add_placement_with_zero_placement_id() ! {
	mut t := Terminal.init(Options{ cols: 100, rows: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 50, height: 50 })!
	s.add_image(mut t.screens.active, Image{ id: 2, width: 25, height: 25 })!
	s.add_placement(mut t.screens.active, 1, 0, pin_placement(mut t, 25, 25))
	s.add_placement(mut t.screens.active, 1, 0, pin_placement(mut t, 25, 25))

	assert s.placement_count() == 2
	assert s.image_count() == 2

	// verify the placement is what we expect
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.internal, 0)
	}) != none
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.internal, 1)
	}) != none
}

fn test_storage_placement_reclaims_pruned_anchors() ! {
	mut t := Terminal.init(Options{ cols: 80, rows: 3, max_scrollback: 1 })!
	defer { t.deinit() }
	t.width_px = 800
	t.height_px = 60
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := &t.screens.active.kitty_images
	image := Image{ id: 1, width: 10, height: 10 }
	s.add_image(mut t.screens.active, image)!
	old := pin_placement(mut t, 0, 0)
	s.add_placement(mut t.screens.active, image.id, 0, old)
	assert old.rect(image, &t) != none
	pin := (old.location as PlacementPin).pin
	t.set_cursor_pos(3, 1)
	for _ in 0 .. int(initial_capacity(t.cols).rows) * 4 {
		t.index()!
		if pin.garbage {
			break
		}
	}
	assert pin.garbage
	assert old.rect(image, &t) == none

	s.add_placement(mut t.screens.active, image.id, 0, pin_placement(mut t, 1, 1))
	assert s.placement_count() == 1
	assert s.image_count() == 1
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
}

fn test_storage_retransmit_credits_existing_bytes_before_evicting() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer { t.deinit() }
	tracked := t.screens.active.pages.count_tracked_pins()
	mut s := ImageStorage{ total_limit: 9 }
	defer { s.deinit(mut t.screens.active) }

	for id in u32(1) .. u32(4) {
		s.add_image(mut t.screens.active, Image{ id: id, data: [u8(0), 0, 0] })!
		s.add_placement(mut t.screens.active, id, 1, pin_placement(mut t, 1, 1))
	}
	s.add_image(mut t.screens.active, Image{ id: 1, data: [u8(1), 1, 1] })!
	assert s.image_count() == 3
	assert s.placement_count() == 2
	assert s.total_bytes == 9
	assert t.screens.active.pages.count_tracked_pins() == tracked + 2

	s.add_image(mut t.screens.active, Image{ id: 1, data: [u8(2), 2, 2, 2, 2, 2] })!
	assert s.image_count() == 2
	assert s.image_by_id(2) == none
	assert s.image_by_id(3) != none
	image := s.image_by_id(1) or { return error('expected replacement') }
	assert image.data.len == 6
	assert image.transmit_time == 2
	assert s.total_bytes == 9
	assert s.placement_count() == 1
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1

	// A rejected replacement leaves image data and placements intact.
	s.add_image(mut t.screens.active, Image{ id: 3, data: []u8{len: 10} }) or {
		assert err.msg().contains('image exceeds total limit')
		assert s.image_count() == 2
		assert s.placement_count() == 1
		assert s.total_bytes == 9
		assert t.screens.active.pages.count_tracked_pins() == tracked + 1
		return
	}
	assert false, 'expected oversized replacement to fail'
}

fn test_storage_retransmit_automatic_ids_skip_occupied_slots_and_zero() ! {
	mut t := Terminal.init(Options{ cols: 3, rows: 3 })!
	defer { t.deinit() }
	mut s := ImageStorage{ next_image_id: max_u32 }
	defer { s.deinit(mut t.screens.active) }
	s.add_image(mut t.screens.active, Image{ id: max_u32 })!
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	assert s.allocate_image_id() == 2
	assert s.allocate_image_id() == 3
}

fn test_storage_delete_all_placements_and_images() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))

	s.dirty = false
	s.delete(mut t, DeleteAll{ delete: true })
	assert s.dirty
	assert s.image_count() == 1
	assert s.image_by_id(3) != none
	assert s.placement_count() == 0
	assert t.screens.active.pages.count_tracked_pins() == tracked
}

fn test_storage_delete_all_placements_and_images_preserves_limit() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.total_limit = 5000
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))

	s.dirty = false
	s.delete(mut t, DeleteAll{ delete: true })
	assert s.dirty
	assert s.image_count() == 1
	assert s.image_by_id(3) != none
	assert s.placement_count() == 0
	assert s.total_limit == 5000
	assert t.screens.active.pages.count_tracked_pins() == tracked
}

fn test_storage_delete_all_placements() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))

	s.dirty = false
	s.delete(mut t, DeleteAll{ delete: false })
	assert s.dirty
	assert s.placement_count() == 0
	assert s.image_count() == 3
	assert t.screens.active.pages.count_tracked_pins() == tracked
}

fn test_storage_delete_all_placements_by_image_id() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))

	s.dirty = false
	s.delete(mut t, DeleteById{ image_id: 2 })
	assert s.dirty
	assert s.placement_count() == 1
	assert s.image_count() == 3
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
}

fn test_storage_delete_all_placements_by_image_id_and_unused_images() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))

	s.dirty = false
	s.delete(mut t, DeleteById{
		delete:   true
		image_id: 2
	})
	assert s.dirty
	assert s.placement_count() == 1
	assert s.image_count() == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
}

fn test_storage_delete_placement_by_specific_id() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))

	s.dirty = false
	s.delete(mut t, DeleteById{
		delete:       true
		image_id:     1
		placement_id: 2
	})
	assert s.dirty
	assert s.placement_count() == 2
	assert s.image_count() == 3
	assert t.screens.active.pages.count_tracked_pins() == tracked + 2
}

fn test_storage_delete_intersecting_cursor() ! {
	mut t := Terminal.init(Options{ rows: 100, cols: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 50, height: 50 })!
	s.add_image(mut t.screens.active, Image{ id: 2, width: 25, height: 25 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 0, 0))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 25, 25))

	t.screens.active.cursor_absolute(12, 12)

	s.dirty = false
	s.delete(mut t, DeleteIntersectCursor{ delete: false })
	assert s.dirty
	assert s.placement_count() == 1
	assert s.image_count() == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1

	// verify the placement is what we expect
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 2)
	}) != none
}

fn test_storage_delete_intersecting_cursor_plus_unused() ! {
	mut t := Terminal.init(Options{ rows: 100, cols: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 50, height: 50 })!
	s.add_image(mut t.screens.active, Image{ id: 2, width: 25, height: 25 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 0, 0))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 25, 25))

	t.screens.active.cursor_absolute(12, 12)

	s.dirty = false
	s.delete(mut t, DeleteIntersectCursor{ delete: true })
	assert s.dirty
	assert s.placement_count() == 1
	assert s.image_count() == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1

	// verify the placement is what we expect
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 2)
	}) != none
}

fn test_storage_delete_intersecting_cursor_hits_multiple() ! {
	mut t := Terminal.init(Options{ rows: 100, cols: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 50, height: 50 })!
	s.add_image(mut t.screens.active, Image{ id: 2, width: 25, height: 25 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 0, 0))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 25, 25))

	t.screens.active.cursor_absolute(26, 26)

	s.dirty = false
	s.delete(mut t, DeleteIntersectCursor{ delete: true })
	assert s.dirty
	assert s.placement_count() == 0
	assert s.image_count() == 1
	assert t.screens.active.pages.count_tracked_pins() == tracked
}

fn test_storage_delete_by_column() ! {
	mut t := Terminal.init(Options{ rows: 100, cols: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 50, height: 50 })!
	s.add_image(mut t.screens.active, Image{ id: 2, width: 25, height: 25 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 0, 0))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 25, 25))

	s.dirty = false
	s.delete(mut t, DeleteColumn{
		delete: false
		x:      60
	})
	assert s.dirty
	assert s.placement_count() == 1
	assert s.image_count() == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1

	// verify the placement is what we expect
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 1)
	}) != none
}

fn test_storage_delete_by_column_1x1() ! {
	mut t := Terminal.init(Options{ rows: 100, cols: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 1, height: 1 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 0, 0))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 1, 0))
	s.add_placement(mut t.screens.active, 1, 3, pin_placement(mut t, 2, 0))

	s.delete(mut t, DeleteColumn{
		delete: false
		x:      2
	})
	assert s.placement_count() == 2
	assert s.image_count() == 1

	// verify the placement is what we expect
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 1)
	}) != none
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 3)
	}) != none
}

fn test_storage_delete_by_row() ! {
	mut t := Terminal.init(Options{ rows: 100, cols: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 50, height: 50 })!
	s.add_image(mut t.screens.active, Image{ id: 2, width: 25, height: 25 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 0, 0))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 25, 25))

	s.dirty = false
	s.delete(mut t, DeleteRow{
		delete: false
		y:      60
	})
	assert s.dirty
	assert s.placement_count() == 1
	assert s.image_count() == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1

	// verify the placement is what we expect
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 1)
	}) != none
}

fn test_storage_delete_by_row_1x1() ! {
	mut t := Terminal.init(Options{ rows: 100, cols: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 100
	t.height_px = 100

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1, width: 1, height: 1 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 0, 0))
	s.add_placement(mut t.screens.active, 1, 2, pin_placement(mut t, 0, 1))
	s.add_placement(mut t.screens.active, 1, 3, pin_placement(mut t, 0, 2))

	s.delete(mut t, DeleteRow{
		delete: false
		y:      2
	})
	assert s.placement_count() == 2
	assert s.image_count() == 1

	// verify the placement is what we expect
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 1)
	}) != none
	assert s.get_placement(PlacementKey{
		image_id:     1
		placement_id: PlacementId.init(.external, 3)
	}) != none
}

fn test_storage_delete_images_by_range_1() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))
	assert s.image_count() == 3
	assert s.placement_count() == 2

	s.dirty = false
	s.delete(mut t, DeleteRange{
		delete: false
		first:  1
		last:   2
	})
	assert s.dirty
	assert s.image_count() == 3
	assert s.placement_count() == 0
	assert t.screens.active.pages.count_tracked_pins() == tracked
}

fn test_storage_delete_images_by_range_2() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 3, 1, pin_placement(mut t, 1, 1))
	assert s.image_count() == 3
	assert s.placement_count() == 2

	s.dirty = false
	s.delete(mut t, DeleteRange{
		delete: true
		first:  1
		last:   2
	})
	assert s.dirty
	assert s.image_count() == 1
	assert s.image_by_id(3) != none
	assert s.placement_count() == 1
	assert s.placements[0].key.image_id == 3
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
}

fn test_storage_delete_images_by_range_3() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))
	assert s.image_count() == 3
	assert s.placement_count() == 2

	s.dirty = false
	s.delete(mut t, DeleteRange{ delete: true, first: 2, last: 1 })
	assert !s.dirty
	assert s.image_count() == 3
	assert s.placement_count() == 2

	s.delete(mut t, DeleteRange{
		delete: false
		first:  1
		last:   1
	})
	assert s.dirty
	assert s.image_count() == 3
	assert s.placement_count() == 1
	assert s.placements[0].key.image_id == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
}

fn test_storage_delete_images_by_range_4() ! {
	mut t := Terminal.init(Options{ rows: 3, cols: 3 })!
	defer {
		t.deinit()
	}
	tracked := t.screens.active.pages.count_tracked_pins()

	mut s := ImageStorage{}
	defer {
		s.deinit(mut t.screens.active)
	}
	s.add_image(mut t.screens.active, Image{ id: 1 })!
	s.add_image(mut t.screens.active, Image{ id: 2 })!
	s.add_image(mut t.screens.active, Image{ id: 3 })!
	s.add_placement(mut t.screens.active, 1, 1, pin_placement(mut t, 1, 1))
	s.add_placement(mut t.screens.active, 2, 1, pin_placement(mut t, 1, 1))
	assert s.image_count() == 3
	assert s.placement_count() == 2

	s.dirty = false
	s.delete(mut t, DeleteRange{
		delete: true
		last:   1
	})
	assert s.dirty
	assert s.image_count() == 2
	assert s.image_by_id(1) == none
	assert s.placement_count() == 1
	assert s.placements[0].key.image_id == 2
	assert t.screens.active.pages.count_tracked_pins() == tracked + 1
}

fn test_storage_aspect_ratio_calculation_when_only_columns_or_rows_specified() ! {
	mut t := Terminal.init(Options{ cols: 100, rows: 100 })!
	defer {
		t.deinit()
	}
	t.width_px = 1000 // 10 px per col
	t.height_px = 2000 // 20 px per row

	// Case 1: Only columns specified
	{
		image := Image{
			id:     1
			width:  16
			height: 9
		}
		placement := Placement{
			location: PlacementVirtual{}
			columns:  10
			rows:     0
		}

		// Image is 16x9, set to a width of 10 columns, at 10px per column
		// that's 100px width. 100px * (9 / 16) = 56.25, which should round
		// to a height of 56px.

		calc_width, calc_height := placement.calculated_size(image, &t)
		assert calc_width == 100
		assert calc_height == 56
	}

	// Case 2: Only rows specified
	{
		image := Image{
			id:     2
			width:  16
			height: 9
		}
		placement := Placement{
			location: PlacementVirtual{}
			columns:  0
			rows:     5
		}

		// Image is 16x9, set to a height of 5 rows, at 20px per row that's
		// 100px height. 100px * (16 / 9) = 177.77..., which should round to
		// a width of 178px.

		calc_width, calc_height := placement.calculated_size(image, &t)
		assert calc_width == 178
		assert calc_height == 100
	}
}

fn test_storage_scales_the_intersected_kitty_crop() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer { t.deinit() }
	t.width_px = 50
	t.height_px = 100
	image := Image{ width: 10, height: 10 }

	native := Placement{ source_x: 8, source_y: 7 }
	assert native.source_rect(image) == PlacementSourceRect{ x: 8, y: 7, width: 2, height: 3 }
	native_width, native_height := native.calculated_size(image, &t)
	assert native_width == 2 && native_height == 3

	scaled := Placement{
		...native
		source_width:  8
		source_height: 8
		x_offset:      3
		y_offset:      4
		columns:       2
	}
	width, height := scaled.calculated_size(image, &t)
	assert width == 17 && height == 26
	cols, rows := scaled.grid_size(image, &t)
	assert cols == 2 && rows == 2

	empty := Placement{ ...scaled, source_x: 10 }
	assert empty.source_rect(image).width == 0
	empty_width, empty_height := empty.calculated_size(image, &t)
	assert empty_width == 17 && empty_height == 0

	explicit := Placement{ ...empty, rows: 2 }
	explicit_width, explicit_height := explicit.calculated_size(image, &t)
	assert explicit_width == 17 && explicit_height == 36
}

fn test_storage_clamps_kitty_offsets_to_the_first_cell() ! {
	mut t := Terminal.init(Options{ rows: 5, cols: 5 })!
	defer { t.deinit() }
	t.width_px = 50
	t.height_px = 100
	p := Placement{ columns: 2, rows: 2, x_offset: 30, y_offset: 44 }
	offset_x, offset_y := p.cell_offset(&t)
	assert offset_x == 9 && offset_y == 19

	width, height := p.calculated_size(Image{ width: 10, height: 10 }, &t)
	assert width == 11 && height == 21
}
