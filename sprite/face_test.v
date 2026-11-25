module sprite

// Tests for the sprite Face codepoint dispatch, translated from the
// behavior of ghostty's src/font/sprite/Face.zig:
//   - getDrawFn  -> get_draw_fn   (range dispatch + special sprites)
//   - hasCodepoint -> has_codepoint
//
// Ghostty's Face.zig has a single unit test ("sprite face render all
// sprites") which compares PNG golden atlases. The corresponding test below
// compares SHA-256 digests of the decoded grayscale pixels, keeping the same
// exact-pixel regression coverage without depending on a sibling checkout.

import sprite_types as font
import crypto.sha256

fn new_face() SpriteFace {
	return SpriteFace{
		metrics: font.default_grid_metrics(8, 16)
	}
}

// draw_fn_is_none reports whether get_draw_fn returns no function for
// the given codepoint. (V generates invalid C for a direct `== none`
// comparison on an optional function-pointer value, so we branch on the
// optional with an `or` block instead.)
fn draw_fn_is_none(cp u32) bool {
	get_draw_fn(cp) or { return true }
	return false
}

// ------------------------------------------------------------
// has_codepoint: codepoints inside sprite ranges are covered.
// ------------------------------------------------------------

fn test_has_codepoint_covered_ranges() {
	f := new_face()
	covered := [
		u32(0x2500), // box drawing (min)
		0x257f, // box drawing (max)
		0x2580, // block elements (min)
		0x259f, // block elements (max)
		0x2800, // braille (min)
		0x28ff, // braille (max)
		0x25e2, // geometric shapes
		0x25e5,
		0x25f8,
		0x25fa,
		0x25ff,
		0xe0b0, // powerline
		0xe0bf,
		0xe0d2,
		0xe0d4,
		0xf5d0, // branch drawing (min)
		0xf60d, // branch drawing (max)
		0x1fb00, // legacy computing (min)
		0x1fbef, // circles (max in that block)
		0x1cd00, // octants (min)
		0x1cde5, // octants (max)
		0x1ce90, // sixteenth blocks (min)
		0x1ceaf, // sixteenth blocks (max)
	]
	for cp in covered {
		assert f.has_codepoint(cp), 'expected codepoint 0x${cp:x} to be covered'
	}
}

// ------------------------------------------------------------
// has_codepoint: codepoints outside all ranges are not covered.
// ------------------------------------------------------------

fn test_has_codepoint_uncovered() {
	f := new_face()
	uncovered := [
		u32(0x0041), // 'A'
		0x24ff, // just below box drawing
		0x25a0, // gap between block elements and geometric shapes
		0x25e1, // just below geometric shapes 0x25e2
		0x25e6, // just above geometric shapes 0x25e5
		0x2600, // miscellaneous symbols, no sprite
		0xe0af, // just below powerline 0xe0b0
		0xf5cf, // just below branch drawing
		0xf60e, // just above branch drawing
		0x10ffff, // max unicode, below sprite.start, in no range
	]
	for cp in uncovered {
		assert !f.has_codepoint(cp), 'expected codepoint 0x${cp:x} to be uncovered'
	}
}

// ------------------------------------------------------------
// has_codepoint is independent of presentation; presentation filtering is
// performed by the font resolver.
// ------------------------------------------------------------

fn test_has_codepoint_ignores_presentation() {
	f := new_face()
	assert f.has_codepoint(0x2500)
	assert !f.has_codepoint(0x0041)
}

// ------------------------------------------------------------
// get_draw_fn returns the correct function for each range.
// V supports function value equality, so we can assert the exact
// dispatch target for representative codepoints.
// ------------------------------------------------------------

fn test_get_draw_fn_box_range() {
	// Every codepoint in 0x2500..0x257f dispatches to draw_2500_257f.
	for cp in [u32(0x2500), 0x2540, 0x257f] {
		fn_ := get_draw_fn(cp) or { panic('expected draw fn for 0x${cp:x}') }
		assert fn_ == DrawFn(draw_2500_257f)
	}
}

fn test_get_draw_fn_block_range() {
	for cp in [u32(0x2580), 0x2590, 0x259f] {
		fn_ := get_draw_fn(cp) or { panic('expected draw fn for 0x${cp:x}') }
		assert fn_ == DrawFn(draw_2580_259f)
	}
}

fn test_get_draw_fn_braille_range() {
	for cp in [u32(0x2800), 0x2850, 0x28ff] {
		fn_ := get_draw_fn(cp) or { panic('expected draw fn for 0x${cp:x}') }
		assert fn_ == DrawFn(draw_2800_28ff)
	}
}

fn test_get_draw_fn_geometric_range() {
	for cp in [u32(0x25e2), 0x25e5] {
		fn_ := get_draw_fn(cp) or { panic('expected draw fn for 0x${cp:x}') }
		assert fn_ == DrawFn(draw_25e2_25e5)
	}
}

fn test_get_draw_fn_powerline_single() {
	fn_ := get_draw_fn(0xe0b0) or { panic('expected draw fn') }
	assert fn_ == DrawFn(draw_e0b0)
	fn2 := get_draw_fn(0xe0b4) or { panic('expected draw fn') }
	assert fn2 == DrawFn(draw_e0b4)
}

fn test_get_draw_fn_branch_range() {
	for cp in [u32(0xf5d0), 0xf5f0, 0xf60d] {
		fn_ := get_draw_fn(cp) or { panic('expected draw fn for 0x${cp:x}') }
		assert fn_ == DrawFn(draw_f5d0_f60d)
	}
}

fn test_get_draw_fn_legacy_computing_range() {
	for cp in [u32(0x1fb00), 0x1fb20, 0x1fb3b] {
		fn_ := get_draw_fn(cp) or { panic('expected draw fn for 0x${cp:x}') }
		assert fn_ == DrawFn(draw_1fb00_1fb3b)
	}
}

fn test_get_draw_fn_octant_range() {
	for cp in [u32(0x1cd00), 0x1cd80, 0x1cde5] {
		fn_ := get_draw_fn(cp) or { panic('expected draw fn for 0x${cp:x}') }
		assert fn_ == DrawFn(draw_1cd00_1cde5)
	}
}

fn test_get_draw_fn_none_for_gaps() {
	// Codepoints in no range return none.
	assert draw_fn_is_none(0x0041)
	assert draw_fn_is_none(0x24ff)
	assert draw_fn_is_none(0x25a0)
	assert draw_fn_is_none(0x10ffff)
}

// ------------------------------------------------------------
// Boundary transitions: min-1 differs from min, max differs from max+1.
// ------------------------------------------------------------

fn test_get_draw_fn_box_boundaries() {
	// 0x24ff is below the box range -> none.
	assert draw_fn_is_none(0x24ff)
	// 0x2500 is the first box codepoint.
	lo := get_draw_fn(0x2500) or { panic('expected box fn') }
	assert lo == DrawFn(draw_2500_257f)
	// 0x2580 is the block range, not the box range.
	hi := get_draw_fn(0x2580) or { panic('expected block fn') }
	assert hi == DrawFn(draw_2580_259f)
	assert hi != DrawFn(draw_2500_257f)
}

// ------------------------------------------------------------
// Special sprite dispatch: codepoints at Sprite.start (0x110000)
// map to the special drawing functions in enum-declaration order:
//   underline, underline_double, underline_dotted, underline_dashed,
//   underline_curly, strikethrough, overline, cursor_rect,
//   cursor_hollow_rect, cursor_bar, cursor_underline.
// ------------------------------------------------------------

const special_start = u32(0x110000)

fn test_get_draw_fn_special_sprites() {
	assert get_draw_fn(special_start + 0) or { panic('') } == DrawFn(underline)
	assert get_draw_fn(special_start + 1) or { panic('') } == DrawFn(underline_double)
	assert get_draw_fn(special_start + 2) or { panic('') } == DrawFn(underline_dotted)
	assert get_draw_fn(special_start + 3) or { panic('') } == DrawFn(underline_dashed)
	assert get_draw_fn(special_start + 4) or { panic('') } == DrawFn(underline_curly)
	assert get_draw_fn(special_start + 5) or { panic('') } == DrawFn(strikethrough)
	assert get_draw_fn(special_start + 6) or { panic('') } == DrawFn(overline)
	assert get_draw_fn(special_start + 7) or { panic('') } == DrawFn(cursor_rect)
	assert get_draw_fn(special_start + 8) or { panic('') } == DrawFn(cursor_hollow_rect)
	assert get_draw_fn(special_start + 9) or { panic('') } == DrawFn(cursor_bar)
	assert get_draw_fn(special_start + 10) or { panic('') } == DrawFn(cursor_underline)
}

fn test_get_draw_fn_special_out_of_range() {
	// Above the last special sprite index there is no draw fn.
	assert draw_fn_is_none(special_start + 11)
	assert draw_fn_is_none(special_start + 100)
}

fn test_has_codepoint_special_sprites() {
	f := new_face()
	// The special cursor/underline sprites are all "covered".
	for i in 0 .. 11 {
		assert f.has_codepoint(special_start + u32(i))
	}
	assert !f.has_codepoint(special_start + 11)
}

fn golden_metrics(width u32, ascent u32, descent u32, thickness u32) font.Metrics {
	height := ascent + descent
	ex_height := 0.75 * 0.75 * f64(ascent)
	return font.Metrics{
		cell_width: width
		cell_height: height
		cell_baseline: descent
		underline_position: ascent + thickness
		underline_thickness: thickness
		strikethrough_position: u32(f64(ascent) - (ex_height + f64(thickness)) * 0.5 + 0.5)
		strikethrough_thickness: thickness
		overline_position: 0
		overline_thickness: thickness
		box_thickness: thickness
		cursor_thickness: 1
		cursor_height: height
		icon_height: f64(height)
		icon_height_single: (2.0 * 0.75 * f64(ascent) + f64(height)) / 3.0
		face_width: f64(width)
		face_height: f64(height)
		face_y: 0
	}
}

fn render_golden_atlas(batch u32, width u32, ascent u32, descent u32, thickness u32) ![]u8 {
	height := ascent + descent
	padding_x := width / 4
	padding_y := height / 4
	stride_x := width + 2 * padding_x
	stride_y := height + 2 * padding_y
	metrics := golden_metrics(width, ascent, descent, thickness)
	mut canvas := Canvas.init(width, height, padding_x, padding_y)
	mut atlas := []u8{len: int(stride_x * 16 * stride_y * 16)}
	atlas_width := int(stride_x * 16)

	for cp in batch .. batch + 0x100 {
		draw := get_draw_fn(cp) or { continue }
		draw(cp, mut canvas, width, height, metrics)!
		canvas.clear_clipping_regions()
		column := (cp - batch) % 16
		row := (cp - batch) / 16
		x_offset := int(stride_x * column)
		y_offset := int(stride_y * row)
		for y in 0 .. int(stride_y) {
			for x in 0 .. int(stride_x) {
				atlas[(y_offset + y) * atlas_width + x_offset + x] = u8(canvas.surface.pixels[y * int(stride_x) +
					x] >> 24)
			}
		}
		canvas.surface.clear(0)
		canvas.clip_top = 0
		canvas.clip_left = 0
		canvas.clip_right = 0
		canvas.clip_bottom = 0
	}
	return atlas
}

fn ghostty_golden_sha256() map[string]string {
	return {
		'U+1CC00...U+1CCFF-11x21+2.png': '053868d5061cd55e79fe85fbfa0d8f9050141d89d60f1462867ce79d2d5d4293'
		'U+1CC00...U+1CCFF-12x24+3.png': 'eb23985b89f4873d68266bbe29d04f5625274253d4c88b41f54d8be0d6e2acd2'
		'U+1CC00...U+1CCFF-18x36+4.png': '532824268be42d1f773665e7030e95f799221d0c652e4a968a6789a76823cc94'
		'U+1CC00...U+1CCFF-9x17+1.png':  'ddd26e495aa2465e954c8a0b74e4e8e0c35ce707e759c91ef402edad10bd99dd'
		'U+1CD00...U+1CDFF-11x21+2.png': '58b6c0df5f81f6953194c4c7cf62245d2706aae5f406f21b36f10873fe577a83'
		'U+1CD00...U+1CDFF-12x24+3.png': '60425a6548b767be6e929e4a228eba84ebb7d9f7f7d92c4efeab1948e174f4aa'
		'U+1CD00...U+1CDFF-18x36+4.png': '1abe0ab2d7441b5cc1a129e6d16ca401e92686ef6f85aae1dfef8ed3aabc7dab'
		'U+1CD00...U+1CDFF-9x17+1.png':  '7bcef7655ba8504d76f48554aad269fa2b86d1835f055e3555eae6220ddfd6af'
		'U+1CE00...U+1CEFF-11x21+2.png': 'fcbb2ff9479c8a46a9617c86e9a47eeae1fe47919daabd24574f5ec1f22086b6'
		'U+1CE00...U+1CEFF-12x24+3.png': '67a0fd8146f8f1e36c024979c01112ccf5b2aa6c6c4c51f627816f73e06e0e73'
		'U+1CE00...U+1CEFF-18x36+4.png': '218e3a36c53e7670e80daeb47c41e3f752cca8ff11a1c36697ed2650c46a680f'
		'U+1CE00...U+1CEFF-9x17+1.png':  '0325ced8dfc393b8b08ec90926b045435d151661c0c86daf162d7b2ef394b579'
		'U+1FB00...U+1FBFF-11x21+2.png': 'a78882d0f9f78feb9681ccc606319d1b088537a2aab1cdad60ceaa05c1d87c3d'
		'U+1FB00...U+1FBFF-12x24+3.png': '43e774008fa613f31b2c903acc64759a8f925485c5afc0c036f9d6c009d8e9cb'
		'U+1FB00...U+1FBFF-18x36+4.png': '7b87f3af7c3011313905bd422aaf6f780aa5c20f2e99b5148a1ad40417b23d45'
		'U+1FB00...U+1FBFF-9x17+1.png':  '068c9e1da4e9a5d7c9ff5a0e2687fc62e87f9aadd28c7925d2c7ed3f59798856'
		'U+2500...U+25FF-11x21+2.png':   '3d09181d714e10a7d6d2ca303b9bd5b4bd317858c7f1adeead7ee5365da0864c'
		'U+2500...U+25FF-12x24+3.png':   'e8f2300f4ce8deee13f6188e78f6ae0e18cd9a5071768aa64279c186baf9b39b'
		'U+2500...U+25FF-18x36+4.png':   '2079ecf4dfbedda893e69cb063851b37863f93ed078ac09d9fb974b780f33772'
		'U+2500...U+25FF-9x17+1.png':    '28e88db99c00fe1e7cde632e3e3c93672a390d4792de3dbf986af7a61cbf6dfb'
		'U+2800...U+28FF-11x21+2.png':   '4d60d1907151c4e6e951361c508dcaf339445e6f20bf815492a046875c62bef7'
		'U+2800...U+28FF-12x24+3.png':   '9d76a16ba90810b693b4071070438ebac36755ec0f62c4042708adbc020b6c40'
		'U+2800...U+28FF-18x36+4.png':   '2965c71c04d77d67be535ef3593b4b54828ba83cb1cd260ae3ea7dafea0f8663'
		'U+2800...U+28FF-9x17+1.png':    '68ebdf6782236f1d0aeb4388ee255a78a28f65ed363ef18b4a47d3054a8916d9'
		'U+E000...U+E0FF-11x21+2.png':   'c6e357aecbb0e8fa821b85a400db0ba7c799cfcedf55683d3f11cb4274a35f3b'
		'U+E000...U+E0FF-12x24+3.png':   '51c1a303f443fbb4d914946ed56fff3d11910e0ca1464030028104a58520d227'
		'U+E000...U+E0FF-18x36+4.png':   '5f2b79dfee498f2da52139d6ce21439db2414e22359517e93ea48ca8a8745fee'
		'U+E000...U+E0FF-9x17+1.png':    'afe7319932a24f14ee185c83006f65232b821c47aa8da0563aa596dcd4aa472d'
		'U+F500...U+F5FF-11x21+2.png':   'dbef4ea626cc0718b784b9ded13b2c474c32d2ff8927dc8b63553077bd5ea06e'
		'U+F500...U+F5FF-12x24+3.png':   'f180d7f67ce1c0db8562def848302259e24f958e79251ee010b22bf5a7fdff34'
		'U+F500...U+F5FF-18x36+4.png':   '4d07b5ab01b8d434d954d1beffd915d6a073df8b899f50fd6d2f0c4434e12985'
		'U+F500...U+F5FF-9x17+1.png':    '9b34c667e4a8c7ac4d438878952bcb1d0522e12adbe93a6ce94580f3bbc1f770'
		'U+F600...U+F6FF-11x21+2.png':   '395d9571b4d7e36af554ab9546cb45c63e564de0c82c7e31287654f8246b9faf'
		'U+F600...U+F6FF-12x24+3.png':   '1f99674e0f000413378b2a24c9c735bad47c01b2b4cb727836f9207e113edd99'
		'U+F600...U+F6FF-18x36+4.png':   'fa1683c51d75aafbe568ed64f63eda9d374b8ff28651913475717c55810b8bd7'
		'U+F600...U+F6FF-9x17+1.png':    'b58872e4078b786b4459f7c78a8c576536b1b9a82ea38be49da073a14fabd800'
	}
}

fn compare_ghostty_golden_atlases(width u32, ascent u32, descent u32, thickness u32) !int {
	batches := [u32(0x2500), 0x2800, 0xe000, 0xf500, 0xf600, 0x1cc00, 0x1cd00, 0x1ce00, 0x1fb00]
	expected_hashes := ghostty_golden_sha256()
	mut total_mismatches := 0
	for batch in batches {
		actual := render_golden_atlas(batch, width, ascent, descent, thickness)!
		name := 'U+${batch:X}...U+${batch + 0xff:X}-${width}x${ascent + descent}+${thickness}.png'
		expected_hash := expected_hashes[name] or { return error('missing Ghostty golden digest for ${name}') }
		actual_hash := sha256.sum(actual).hex()
		if actual_hash != expected_hash {
			eprintln('${name}: expected ${expected_hash}, got ${actual_hash}')
			total_mismatches += 1
		}
	}
	return total_mismatches
}

fn test_sprite_face_matches_all_ghostty_golden_atlases() {
	cases := [
		[u32(18), 30, 6, 4],
		[u32(12), 20, 4, 3],
		[u32(11), 19, 2, 2],
		[u32(9), 15, 2, 1],
	]
	mut total_mismatches := 0
	for case in cases {
		total_mismatches += compare_ghostty_golden_atlases(case[0], case[1], case[2], case[3])!
	}
	assert total_mismatches == 0
}
