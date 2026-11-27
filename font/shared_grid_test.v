module font

fn test_font_style_and_presentation_storage() {
	assert $sizeof(Style) == 1
	assert u8(Style.regular) == 0
	assert u8(Style.bold_italic) == 3
	assert $sizeof(Presentation) == 1
	assert u8(Presentation.text) == 0
	assert u8(Presentation.emoji) == 1
}

// Tests for SharedGrid.
// Translated from ghostty/src/font/SharedGrid.zig tests.

fn make_grid(mode string) !SharedGrid {
	_ = mode
	mut c := Collection.init()
	c.load_options = LoadOptions{
		library: Library.init()!
		size:    DesiredSize{
			points: 12
			xdpi:   96
			ydpi:   96
		}
	}

	load_opts := c.load_options or { return error('missing load options') }
	c.add(Face.init_mem(load_opts.library, embedded_regular, load_opts.face_options())!, AddOptions{
		style:           .regular
		fallback:        false
		size_adjustment: .none_
	})!

	r := CodepointResolver{
		collection: c
	}

	return SharedGrid.init(r)!
}

fn test_shared_grid_get_index() {
	mut grid := make_grid('normal') or { panic(err) }
	defer { grid.deinit() }
	for cp := u32(32); cp < 127; cp++ {
		value := grid.get_index(cp, .regular, none) or { panic(err) }
		assert value.has_value
		assert value.index.style() == .regular
		assert value.index.idx() == 0
		assert grid.has_codepoint(value.index, cp, none)
	}
	// The second pass exercises the cached lookup path.
	for cp := u32(32); cp < 127; cp++ {
		value := grid.get_index(cp, .regular, none) or { panic(err) }
		assert value.has_value && value.index.idx() == 0
	}
}

fn test_shared_grid_render_glyph_cache() {
	mut grid := make_grid('normal') or { panic(err) }
	defer { grid.deinit() }
	value := grid.get_index(u32(`A`), .regular, none) or { panic(err) }
	face := grid.resolver.collection.get_face(value.index) or { panic(err) }
	glyph_index := face.glyph_index(u32(`A`)) or { panic('missing A') }
	opts := RenderOptions{ grid_metrics: grid.metrics }
	first := grid.render_glyph(value.index, glyph_index, opts) or { panic(err) }
	count := grid.glyphs.len
	second := grid.render_glyph(value.index, glyph_index, opts) or { panic(err) }
	assert first == second
	assert grid.glyphs.len == count
}

fn test_shared_grid_grows_full_sprite_atlas() {
	mut grid := make_grid('normal') or { panic(err) }
	defer { grid.deinit() }
	grid.atlas_grayscale.deinit()
	grid.atlas_grayscale = Atlas.init(32, .grayscale)!
	grid.atlas_grayscale.reserve(30, 30)!
	original_size := grid.atlas_grayscale.size

	result := grid.render_glyph(Index.init_special(.sprite), 0x2500, RenderOptions{
		grid_metrics: grid.metrics
	})!
	assert result.glyph.width > 0
	assert grid.atlas_grayscale.size == original_size * 2
}

fn test_shared_grid_grows_past_first_doubling_for_large_glyph() {
	mut grid := make_grid('normal')!
	defer { grid.deinit() }
	grid.atlas_grayscale.deinit()
	grid.atlas_grayscale = Atlas.init(4, .grayscale)!

	result := grid.render_glyph(Index.init_special(.sprite), 0x2588, RenderOptions{
		grid_metrics: grid.metrics
	})!
	assert result.glyph.width > 0
	assert grid.atlas_grayscale.size > 8
}

fn test_shared_grid_render_codepoint() {
	mut grid := make_grid('normal') or { panic(err) }
	defer { grid.deinit() }
	value := grid.render_codepoint(u32(`A`), .regular, none, RenderOptions{
		grid_metrics: grid.metrics
	}) or { panic(err) }
	assert value.has_value
	assert value.render.glyph.width > 0
	missing := grid.render_codepoint(0x10ffff, .regular, none, RenderOptions{
		grid_metrics: grid.metrics
	}) or { panic(err) }
	assert !missing.has_value
}

fn test_shared_grid_render_glyph_tripwire_rolls_back_cache() {
	mut grid := make_grid('normal') or { panic(err) }
	defer { grid.deinit() }
	value := grid.get_index(u32(`A`), .regular, none) or { panic(err) }
	face := grid.resolver.collection.get_face(value.index) or { panic(err) }
	glyph_index := face.glyph_index(u32(`A`)) or { panic('missing A') }
	opts := RenderOptions{ grid_metrics: grid.metrics }
	key := GlyphKey{value.index, glyph_index, opts}
	hash := key.hash_key()
	assert glyph_cache_get(grid.glyphs, hash, key) == none

	mut tw := shared_grid_render_glyph_tripwire()
	defer { tw.end(.reset) or {} }
	tw.error_always(.get_presentation, error('tripwire render presentation'))
	grid.render_glyph(value.index, glyph_index, opts) or {
		assert err.msg() == 'tripwire render presentation'
		assert glyph_cache_get(grid.glyphs, hash, key) == none
		return
	}
	assert false, 'expected render tripwire failure'
}

fn test_shared_grid_tripwire_point_layouts() {
	assert sizeof(SharedGridInitFailPoint) == 1
	assert u8(SharedGridInitFailPoint.codepoints_capacity) == 0
	assert u8(SharedGridInitFailPoint.glyphs_capacity) == 1
	assert u8(SharedGridInitFailPoint.reload_metrics) == 2
	assert sizeof(SharedGridRenderGlyphFailPoint) == 1
	assert u8(SharedGridRenderGlyphFailPoint.get_presentation) == 0
}

fn test_shared_grid_init_tripwires_cleanup() {
	for point in [SharedGridInitFailPoint.codepoints_capacity, .glyphs_capacity, .reload_metrics] {
		mut lib := Library.init() or { panic(err) }
		mut c := Collection.init()
		c.load_options = LoadOptions{
			library: lib
			size:    DesiredSize{ points: 12, xdpi: 96, ydpi: 96 }
		}
		load_opts := c.load_options or { panic('missing load options') }
		c.add(Face.init_mem(load_opts.library, embedded_regular, load_opts.face_options()) or {
			panic(err)
		}, AddOptions{
			style:           .regular
			size_adjustment: .none_
		}) or { panic(err) }
		mut resolver := CodepointResolver{ collection: c }

		mut tw := shared_grid_init_tripwire()
		tw.error_always(point, error('tripwire grid init'))
		SharedGrid.init(resolver) or {
			assert err.msg() == 'tripwire grid init'
			tw.end(.reset) or { panic(err) }
			resolver.deinit()
			lib.deinit()
			continue
		}
		assert false, 'expected init tripwire failure at ${point}'
	}
}

fn test_shared_grid_cell_size() {
	mut grid := make_grid('normal') or { panic(err) }
	defer { grid.deinit() }
	cs := grid.cell_size()
	assert cs.width > 0
	assert cs.height > 0
}

fn test_shared_grid_init_deinit() {
	mut grid := make_grid('normal') or { panic(err) }
	grid.deinit()
}

fn test_codepoint_key_hash_matches_zig_source() {
	assert CodepointKey{
		style:        .regular
		codepoint:    65
		presentation: none
	}.hash_key() == 0xfbefa49ea558c504
	assert CodepointKey{
		style:        .bold
		codepoint:    0x1f600
		presentation: Presentation.emoji
	}.hash_key() == 0x8449aee88adf9900
}

fn test_codepoint_cache_handles_hash_collisions() {
	first_key := CodepointKey{.regular, 65, none}
	second_key := CodepointKey{.bold, 65, Presentation.text}
	first_value := CodepointValue{true, Index.init(.regular, 1)}
	second_value := CodepointValue{true, Index.init(.bold, 2)}
	mut cache := map[u64][]CodepointCacheEntry{}
	collision := u64(7)
	codepoint_cache_put(mut cache, collision, first_key, first_value)
	codepoint_cache_put(mut cache, collision, second_key, second_value)
	assert codepoint_cache_get(cache, collision, first_key) or { panic('missing first key') } == first_value
	assert codepoint_cache_get(cache, collision, second_key) or { panic('missing second key') } == second_value
	codepoint_cache_delete(mut cache, collision, first_key)
	assert codepoint_cache_get(cache, collision, first_key) == none
	assert codepoint_cache_get(cache, collision, second_key) or { panic('missing second key') } == second_value
}

fn test_glyph_key_hash_matches_zig_source() {
	index := Index.init(.bold, 2)
	assert GlyphKey{
		index: index
		glyph: 42
		opts:  RenderOptions{}
	}.hash_key() == 0x4b23988daedd316c
	assert GlyphKey{
		index: index
		glyph: 42
		opts:  RenderOptions{
			cell_width:       2
			thicken:          true
			thicken_strength: 17
			constraint_width: 3
		}
	}.hash_key() == 0xff749c2ed32ca517
}

fn test_glyph_cache_handles_hash_collisions() {
	first_key := GlyphKey{Index.init(.regular, 0), 1, RenderOptions{}}
	second_key := GlyphKey{Index.init(.bold, 2), 42, RenderOptions{ cell_width: 2 }}
	first_value := RenderResult{Glyph{ atlas_x: 1 }, .text}
	second_value := RenderResult{Glyph{ atlas_x: 2 }, .emoji}
	mut cache := map[u64][]GlyphCacheEntry{}
	collision := u64(9)
	glyph_cache_put(mut cache, collision, first_key, first_value)
	glyph_cache_put(mut cache, collision, second_key, second_value)
	assert glyph_cache_get(cache, collision, first_key) or { panic('missing first key') } == first_value
	assert glyph_cache_get(cache, collision, second_key) or { panic('missing second key') } == second_value
}
