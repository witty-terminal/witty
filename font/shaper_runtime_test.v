module font

fn test_run_options_apply_break_config() {
	mut opts := RunOptions{ cursor_x: u16(7) }
	opts.apply_break_config(true)
	assert opts.cursor_x or { 0 } == u16(7)
	opts.apply_break_config(false)
	assert opts.cursor_x == none
}

// Runtime coverage for the production shaper, cache, and byte-row adapter.

fn test_public_shaper_cache_get_put() {
	mut cache := ShaperCache.init()
	defer {
		cache.deinit()
	}

	run := TextRun{
		hash: 42
		cells: 2
	}
	if _ := cache.get(run) {
		assert false, 'expected cache miss before put'
	}

	mut cells := [
		ShapeCell{
			x: 0
			glyph_index: 65
		},
		ShapeCell{
			x: 1
			glyph_index: 66
		},
	]
	cache.put(run, cells)!
	cells[0] = ShapeCell{
		x: 9
		glyph_index: 99
	}

	got := cache.get(run) or {
		assert false, 'expected cache hit after put'
		return
	}
	assert got.len == 2
	assert got[0].x == 0
	assert got[0].glyph_index == 65
	assert got[1].x == 1
	assert got[1].glyph_index == 66
	assert cache.count() == 1
}

fn test_public_shaper_cache_evicts_least_recently_used_collision() {
	mut cache := ShaperCache.init()
	defer {
		cache.deinit()
	}

	for i in 0 .. 8 {
		cache.put(TextRun{ hash: u64(i * 256) }, [ShapeCell{ glyph_index: u32(i) }])!
	}
	assert cache.get(TextRun{ hash: 0 })?[0].glyph_index == 0
	cache.put(TextRun{ hash: 8 * 256 }, [ShapeCell{ glyph_index: 8 }])!

	assert cache.get(TextRun{ hash: 256 }) == none
	assert cache.get(TextRun{ hash: 0 })?[0].glyph_index == 0
	assert cache.get(TextRun{ hash: 8 * 256 })?[0].glyph_index == 8
	assert cache.count() == 8
}

fn test_shaper_cache_remembers_repeated_misses() {
	mut cache := ShaperCache.init()
	defer { cache.deinit() }
	run := TextRun{ hash: 1 }
	collision := TextRun{ hash: 513 }
	assert !cache.has_recent_run(run)
	assert cache.has_recent_run(run)
	assert !cache.has_recent_run(collision)
	assert !cache.has_recent_run(run)
	assert cache.has_recent_run(run)
}

fn test_public_shaper_identity_shape() {
	mut shaper := Shaper.init(ShaperOptions{})!
	defer { shaper.deinit() }
	shaper.codepoints = [
		ShaperCodepoint{ cluster: 0, codepoint: 65 },
		ShaperCodepoint{ cluster: 1, codepoint: 66 },
		ShaperCodepoint{ cluster: 2, codepoint: 67 },
	]
	cells := shaper.shape(TextRun{ hash: 1, font_index: sprite_index, cells: 3 })!

	assert cells.len == 3
	assert cells[0].x == 0
	assert cells[0].glyph_index == 65
	assert cells[1].x == 1
	assert cells[1].glyph_index == 66
	assert cells[2].x == 2
	assert cells[2].glyph_index == 67
}

fn test_public_run_iterator_yields_single_text_run() {
	mut shaper := Shaper.init(ShaperOptions{})!
	defer { shaper.deinit() }
	mut it := shaper.run_iterator(RunOptions{ cells: [u8(`A`), `B`, `C`] })
	run := (it.next()!).get() or {
		assert false, 'expected one text run for non-empty cells'
		return
	}

	assert run.cells == 3
	assert run.offset == 0
	assert run.font_index == Index{}
	assert run.hash != 0
	if _ := (it.next()!).get() {
		assert false, 'expected iterator to stop after one fallback run'
	}
}

fn test_public_run_iterator_hash_is_position_independent() {
	mut shaper := Shaper.init(ShaperOptions{})!
	defer { shaper.deinit() }

	mut first := shaper.run_iterator(RunOptions{ cells: [u8(`A`), `B`, `C`] })
	run1 := (first.next()!).get() or { panic('expected first text run') }

	mut second := shaper.run_iterator(RunOptions{ cells: [u8(`X`), `A`, `B`, `C`] })
	second.i = 1
	run2 := (second.next()!).get() or { panic('expected offset text run') }

	assert run1.offset == 0
	assert run2.offset == 1
	assert run1.cells == run2.cells
	assert run1.hash == run2.hash
}

fn test_public_run_iterator_hash_includes_length() {
	mut shaper := Shaper.init(ShaperOptions{})!
	defer { shaper.deinit() }

	mut short := shaper.run_iterator(RunOptions{ cells: [u8(`A`)] })
	short_run := (short.next()!).get() or { panic('expected short text run') }
	mut long := shaper.run_iterator(RunOptions{ cells: [u8(`A`), `B`] })
	long_run := (long.next()!).get() or { panic('expected long text run') }

	assert short_run.hash != long_run.hash
}

fn failing_run_add(_ voidptr, _ u32, _ u32) ! {
	return error('run hook failed')
}

fn test_public_run_iterator_propagates_hook_errors() {
	mut shaper := Shaper.init(ShaperOptions{})!
	defer { shaper.deinit() }
	mut it := RunIterator.new_with_hooks(voidptr(&shaper), RunOptions{
		cells: [u8(`A`)]
	}, RunIteratorHooks{
		add: failing_run_add
	})

	it.next() or {
		assert err.msg() == 'run hook failed'
		assert it.i == 0
		return
	}
	assert false, 'expected the shaping hook error'
}

fn test_live_harfbuzz_shaper_uses_source_feature_list_parser() {
	mut shaper := Shaper.init(ShaperOptions{ features: ['-liga,+dlig', 'kern==1'] })!
	defer { shaper.deinit() }
	assert shaper.hb_feats.len == 4
	assert shaper.hb_feats[1].tag == 0x6c696761
	assert shaper.hb_feats[1].value == 0
	assert shaper.hb_feats[2].tag == 0x646c6967
	assert shaper.hb_feats[2].value == 1
	assert shaper.hb_feats[3].tag == 0x6b65726e
	assert shaper.hb_feats[3].value == 1
}
