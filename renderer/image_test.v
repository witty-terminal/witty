module renderer

import terminal

// ============================================================
// Image tests
// ============================================================

// Test PixelFormat bytes per pixel.
fn test_pixel_format_bpp() {
	assert sizeof(PixelFormat) == 1
	assert u8(PixelFormat.gray) == 0
	assert u8(PixelFormat.gray_alpha) == 1
	assert u8(PixelFormat.rgb) == 2
	assert u8(PixelFormat.bgr) == 3
	assert u8(PixelFormat.rgba) == 4
	assert u8(PixelFormat.bgra) == 5
	assert PixelFormat.gray.bpp() == 1
	assert PixelFormat.gray_alpha.bpp() == 2
	assert PixelFormat.rgb.bpp() == 3
	assert PixelFormat.bgr.bpp() == 3
	assert PixelFormat.rgba.bpp() == 4
	assert PixelFormat.bgra.bpp() == 4
}

// Test PendingImage data_len calculation.
fn test_pending_image_data_len() {
	p := PendingImage{
		width: 10
		height: 20
		pixel_format: .rgba
	}
	assert p.data_len() == 10 * 20 * 4
}

// Test PendingImage data_len with different format.
fn test_pending_image_data_len_rgb() {
	p := PendingImage{
		width: 5
		height: 5
		pixel_format: .rgb
	}
	assert p.data_len() == 5 * 5 * 3
}

fn test_pending_image_length_uses_source_usize_contract() {
	p := PendingImage{
		width: 70_000
		height: 70_000
		pixel_format: .gray
	}
	assert p.len() == uint(4_900_000_000)
}

fn test_pending_image_data_slice() {
	p := PendingImage{
		width: 2
		height: 1
		pixel_format: .rgb
		data: [u8(1), 2, 3, 4, 5, 6]
	}
	assert p.len() == 6
	assert p.data_slice() == [u8(1), 2, 3, 4, 5, 6]
}

fn test_image_prep_for_upload_converts_in_place() ! {
	mut image := Image(ImagePending{
		pending: PendingImage{
			width: 2
			height: 1
			pixel_format: .bgr
			data: [u8(1), 2, 3, 4, 5, 6]
		}
	})
	image.prep_for_upload()!
	pending := image.get_pending() or { return error('missing converted image') }
	assert pending.pixel_format == .rgba
	assert pending.data == [u8(3), 2, 1, 255, 6, 5, 4, 255]

	// Preparation is idempotent once the data is RGBA.
	image.prep_for_upload()!
	assert (image.get_pending() or { return error('missing converted image') }).data == pending.data
}

// Test Image state transitions.
fn test_image_state_pending() {
	img := Image(ImagePending{})
	assert img is ImagePending
	assert img.is_pending()
	assert !img.is_unloading()
	assert !img.has_texture()
}

// Test Image mark_for_unload.
fn test_image_mark_for_unload() {
	mut img := Image(ImageReady{})
	img.mark_for_unload()
	assert img is ImageUnloadReady
	assert img.is_unloading()
	assert !img.is_pending()
	assert img.has_texture()
}

fn test_image_mark_for_unload_preserves_pending_and_replace_variants() {
	mut pending := Image(ImagePending{})
	pending.mark_for_unload()
	assert pending is ImageUnloadPending
	assert pending.is_pending()
	assert !pending.has_texture()

	mut replace := Image(ImageReplace{})
	replace.mark_for_unload()
	assert replace is ImageUnloadReplace
	assert replace.is_pending()
	assert replace.has_texture()

	replace.mark_for_unload()
	assert replace is ImageUnloadReplace
}

// Test Image has_texture.
fn test_image_has_texture() {
	assert Image(ImageReady{}).has_texture()
	assert Image(ImageReplace{}).has_texture()
	assert !Image(ImagePending{}).has_texture()
	assert Image(ImageUnloadReady{}).has_texture()
	assert Image(ImageUnloadReplace{}).has_texture()
}

// Test Image mark_for_replace.
fn test_image_mark_for_replace() {
	mut img := Image(ImageReady{})
	img.mark_for_replace(ImagePending{
		pending: PendingImage{
			width: 20
			height: 20
			pixel_format: .rgba
		}
	})
	assert img is ImageReplace
	assert img.is_pending()
	assert img.has_texture()
}

fn test_image_mark_for_replace_without_texture_stays_pending() {
	mut img := Image(ImageUnloadPending{})
	img.mark_for_replace(ImagePending{
		pending: PendingImage{
			width: 20
			height: 20
			pixel_format: .rgba
		}
	})
	assert img is ImagePending
	assert img.is_pending()
	assert !img.has_texture()
}

// Test ImageId z ordering.
fn test_image_id_z_ordering_kitty() {
	a := ImageId(KittyImageId{ id: 1 })
	b := ImageId(KittyImageId{ id: 2 })
	assert a.z_less_than(b)
	assert !b.z_less_than(a)
}

fn test_image_id_z_ordering_kitty_before_overlay() {
	a := ImageId(KittyImageId{ id: 1 })
	b := ImageId(OverlayImageId{})
	// Kitty images always sort before non-kitty images
	assert a.z_less_than(b)
	assert !b.z_less_than(a)
}

fn test_image_id_z_ordering_overlay_same() {
	a := ImageId(OverlayImageId{})
	b := ImageId(OverlayImageId{})
	// No sensible ordering for identical types
	assert !a.z_less_than(b)
	assert !b.z_less_than(a)
}

// Test ImageRenderState creation and deinit.
fn test_image_render_state_empty() {
	mut state := ImageRenderState.empty()
	assert state.images.len == 0
	assert state.kitty_placements.len == 0
	assert state.overlay_placements.len == 0
	assert !state.kitty_virtual
	state.deinit()
}

fn test_overlay_update_prepares_image_and_placement() ! {
	mut state := ImageRenderState.empty()
	mut overlay := Overlay.init(Size{ screen: ScreenSize{ width: 2, height: 3 } })!
	overlay.surface.clear(0x07070707)
	state.overlay_update(overlay)

	assert overlay_image_key in state.images
	entry := state.images[overlay_image_key] or { panic('missing overlay image') }
	assert entry.image is ImagePending
	pending := entry.image.get_pending() or { panic('missing pending overlay') }
	assert pending.width == 2
	assert pending.height == 3
	assert pending.pixel_format == .rgba
	assert pending.data == []u8{len: 2 * 3 * 4, init: 7}
	assert state.overlay_placements.len == 1
	placement := state.overlay_placements[0]
	assert placement.width == 2
	assert placement.height == 3
	assert placement.source_width == 2
	assert placement.source_height == 3
}

fn test_kitty_update_reads_terminal_storage() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		rows: 5
		cols: 5
	})!
	t.width_px = 50
	t.height_px = 100
	defer {
		t.deinit()
	}

	transmit := terminal.CommandParser.parse_string('a=t,f=24,t=d,i=7,s=1,v=1;////')!
	assert (t.kitty_graphics(&transmit) or { panic('expected transmit response') }).ok()
	display := terminal.CommandParser.parse_string('a=p,i=7,p=9,c=1,r=1,C=1')!
	assert (t.kitty_graphics(&display) or { panic('expected display response') }).ok()

	mut state := ImageRenderState.empty()
	defer {
		state.deinit()
	}
	assert state.kitty_requires_update(&t)
	state.kitty_update(&t, CellSize{
		width: 10
		height: 20
	})

	storage := &t.screens.active.kitty_images
	assert !storage.dirty
	assert kitty_image_key(7) in state.images
	entry := state.images[kitty_image_key(7)] or { panic('expected prepared image') }
	pending := entry.image.get_pending() or { panic('expected pending image') }
	assert pending.pixel_format == .rgba
	assert pending.data == [u8(255), 255, 255, 255]
	assert state.kitty_placements.len == 1
	placement := state.kitty_placements[0]
	assert placement.image_id == ImageId(KittyImageId{ id: 7 })
	assert placement.x == 0
	assert placement.y == 0
	assert placement.width == 10
	assert placement.height == 20
}

fn test_kitty_virtual_placement_keeps_renderer_updates_active_without_placeholder() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		rows: 5
		cols: 5
	})!
	t.width_px = 50
	t.height_px = 100
	defer {
		t.deinit()
	}

	transmit := terminal.CommandParser.parse_string('a=t,f=24,t=d,i=7,s=1,v=1;////')!
	assert (t.kitty_graphics(&transmit) or { panic('expected transmit response') }).ok()
	virtual_display := terminal.CommandParser.parse_string('a=p,i=7,p=9,c=1,r=1,U=1,C=1')!
	assert (t.kitty_graphics(&virtual_display) or { panic('expected display response') }).ok()

	mut state := ImageRenderState.empty()
	defer {
		state.deinit()
	}
	state.kitty_update(&t, CellSize{
		width: 10
		height: 20
	})
	assert state.kitty_virtual
	assert state.kitty_placements.len == 0
	assert state.kitty_requires_update(&t)
}

fn test_kitty_virtual_placement_can_reference_a_pin() ! {
	mut t := terminal.Terminal.init(terminal.Options{ rows: 5, cols: 5 })!
	t.width_px = 50
	t.height_px = 100
	t.modes.set(.grapheme_cluster, true)
	defer {
		t.deinit()
	}

	display := terminal.CommandParser.parse_string('a=T,f=24,t=d,i=7,p=9,s=1,v=1,c=1,r=1,z=-1,C=1;////')!
	assert (t.kitty_graphics(&display) or { panic('expected display response') }).ok()
	mut state := ImageRenderState.empty()
	defer {
		state.deinit()
	}
	cell_size := CellSize{ width: 10, height: 20 }
	state.kitty_update(&t, cell_size)
	assert state.kitty_placements.len == 1
	assert !state.kitty_requires_update(&t)

	t.set_cursor_pos(3, 2)
	t.set_attribute(terminal.SgrFg256{ idx: 7 })!
	t.set_attribute(terminal.SgrUnderlineColor256{ idx: 9 })!
	t.print_string('\U0010EEEE̅̅')!
	assert state.kitty_requires_update(&t)
	state.kitty_update(&t, cell_size)
	assert state.kitty_placements.len == 2
	assert state.kitty_placements[0].virtual_placeholder
	assert !state.kitty_placements[1].virtual_placeholder
	assert state.kitty_virtual

	t.set_cursor_pos(3, 2)
	t.print_string(' ')!
	assert state.kitty_requires_update(&t)
	state.kitty_update(&t, cell_size)
	assert state.kitty_placements.len == 1
	assert !state.kitty_requires_update(&t)
}

fn test_kitty_virtual_placement_uses_viewport_relative_row() ! {
	mut t := terminal.Terminal.init(terminal.Options{
		rows: 5
		cols: 5
	})!
	t.width_px = 50
	t.height_px = 100
	defer {
		t.deinit()
	}

	// Push three rows into history so the viewport starts at screen row 3.
	t.print_string('a\nb\nc\nd\ne\nf\ng\nh')!
	top := t.screens.active.pages.get_top_left(.viewport)
	top_y := (t.screens.active.pages.point_from_pin(.screen, top) or { panic('viewport top is off screen') }).coord().y
	assert top_y == 3
	pin := t.screens.active.pages.pin(terminal.Point.new(.screen, terminal.Coordinate{
		x: 2
		y: 4
	})) or { panic('placeholder pin is off screen') }

	mut storage := terminal.ImageStorage{}
	storage.add_image(mut t.screens.active, terminal.Image{
		id: 7
		width: 1
		height: 1
		data: [u8(255), 255, 255]
	})!
	storage.add_placement(mut t.screens.active, 7, 9, terminal.Placement{
		location: terminal.PlacementVirtual{}
		columns: 1
		rows: 1
	})
	defer {
		storage.deinit(mut t.screens.active)
	}

	mut state := ImageRenderState.empty()
	defer {
		state.deinit()
	}
	state.kitty_update_storage(mut storage, &t, top_y, top_y + 4, CellSize{
		width: 10
		height: 20
	}, []KittyStoredPlacement{}, [terminal.VirtualPlacement{
		pin: pin
		image_id: 7
		placement_id: 9
		width: 1
		height: 1
	}])

	assert state.kitty_placements.len == 1
	assert state.kitty_placements[0].x == 2
	assert state.kitty_placements[0].y == 1
}

// Test DrawPlacements enum.
fn test_draw_placements_enum() {
	assert sizeof(DrawPlacements) == 1
	assert u8(DrawPlacements.kitty_below_bg) == 0
	assert u8(DrawPlacements.kitty_below_text) == 1
	assert u8(DrawPlacements.kitty_above_text) == 2
	assert u8(DrawPlacements.overlay) == 3
}

fn test_image_union_retains_source_variants() {
	assert Image(ImagePending{}) is ImagePending
	assert Image(ImageReplace{}) is ImageReplace
	assert Image(ImageReady{}) is ImageReady
	assert Image(ImageUnloadPending{}) is ImageUnloadPending
	assert Image(ImageUnloadReady{}) is ImageUnloadReady
	assert Image(ImageUnloadReplace{}) is ImageUnloadReplace
}
