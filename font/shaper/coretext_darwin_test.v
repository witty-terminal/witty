module shaper

import font
import witty_macos as macos
import terminal

// ============================================================
// Test helpers
// ============================================================

struct TestShaper {
mut:
	shp  Shaper
	grid font.SharedGrid
	lib  font.Library
}

fn (mut self TestShaper) deinit() {
	self.shp.deinit()
	self.grid.deinit()
	self.lib.deinit()
}

enum TestFont {
	code_new_roman
	geist_mono
	inconsolata
	jetbrains_mono
	monaspace_neon
	nerd_font
}

// Helper to return a fully initialized shaper.
fn create_shaper() !TestShaper {
	return create_shaper_with_font(.inconsolata)
}

fn create_shaper_with_font(font_req TestFont) !TestShaper {
	data := match font_req {
		.code_new_roman { font.embedded_code_new_roman }
		.geist_mono { font.embedded_geist_mono }
		.inconsolata { font.embedded_inconsolata }
		.jetbrains_mono { font.embedded_jetbrains_mono }
		.monaspace_neon { font.embedded_monaspace_neon }
		.nerd_font { font.embedded_test_nerd_font }
	}
	mut lib := font.Library.init()!
	mut collection := font.Collection.init()
	collection.load_options = font.LoadOptions{
		library: lib
		size:    font.DesiredSize{ points: 12, xdpi: 72, ydpi: 72 }
	}
	load_options := collection.load_options or { return error('missing load options') }
	collection.add(font.Face.init_mem(lib, data, load_options.face_options())!, font.AddOptions{
		style:           .regular
		fallback:        false
		size_adjustment: .none_
	})!

	// CoreText cannot load the embedded Noto color font format, so use the
	// platform emoji face exactly as Ghostty's CoreText test setup does.
	mut discovery := font.Discover.init()
	defer { discovery.deinit() }
	mut iterator := discovery.discover(font.Descriptor{
		family:    'Apple Color Emoji'
		size:      12
		monospace: false
	})!
	defer { iterator.deinit() }
	emoji_value := iterator.next()!
	if emoji_value.has_value {
		collection.add_deferred(emoji_value.face, font.AddOptions{
			style:           .regular
			fallback:        false
			size_adjustment: .none_
		})!
	}
	collection.add(font.Face.init_mem(lib, font.embedded_emoji_text, load_options.face_options())!, font.AddOptions{
		style:           .regular
		fallback:        false
		size_adjustment: .none_
	})!
	grid := font.SharedGrid.init(font.CodepointResolver{
		collection: collection
	})!
	mut shp := Shaper.init(font.ShaperOptions{
		features: ['dlig']
	})!

	return TestShaper{
		shp:  shp
		grid: grid
		lib:  lib
	}
}

// Return a fully initialized shaper by discovering a named font on the system.
fn create_shaper_with_discovered_font(font_req string) !TestShaper {
	mut lib := font.Library.init()!
	mut collection := font.Collection.init()
	collection.load_options = font.LoadOptions{
		library: lib
		size:    font.DesiredSize{ points: 12, xdpi: 72, ydpi: 72 }
	}
	mut discovery := font.Discover.init()
	defer { discovery.deinit() }
	mut iterator := discovery.discover(font.Descriptor{
		family:    font_req
		size:      12
		monospace: false
	})!
	defer { iterator.deinit() }
	value := iterator.next()!
	if !value.has_value {
		return error('font not found: ${font_req}')
	}
	mut deferred := value.face
	load_options := collection.load_options or { return error('missing load options') }
	mut face := deferred.load(lib, load_options.face_options())!
	mut name_buf := []u8{len: 512}
	name := face.name(mut name_buf) or { '' }
	if !name.contains(font_req) {
		face.deinit()
		return error('font not found: ${font_req}')
	}
	collection.add(face, font.AddOptions{
		style:           .regular
		fallback:        false
		size_adjustment: .none_
	})!
	grid := font.SharedGrid.init(font.CodepointResolver{
		collection: collection
	})!
	mut shp := Shaper.init(font.ShaperOptions{
		features: []string{}
	})!

	return TestShaper{
		shp:  shp
		grid: grid
		lib:  lib
	}
}

struct CtShapeResult {
mut:
	runs   []font.TextRun
	glyphs [][]font.ShapeCell
}

fn ct_render_row(input string, cols u16, graphemes bool) ![]terminal.RenderCell {
	mut term := terminal.Terminal.init(terminal.Options{ cols: cols, rows: 3 })!
	defer { term.deinit() }
	term.modes.set(.grapheme_cluster, graphemes)
	mut stream := term.vt_stream()
	defer { stream.deinit() }
	stream.next_slice(input.bytes())!
	mut state := terminal.RenderState.empty()
	defer { state.deinit() }
	state.update(mut term)
	mut result := []terminal.RenderCell{cap: state.row_data[0].cells.len}
	for cell in state.row_data[0].cells {
		result << terminal.RenderCell{
			raw:      cell.raw
			grapheme: cell.grapheme.clone()
			style:    cell.style
		}
	}
	return result
}

fn (mut td TestShaper) shape_render_cells(cells []terminal.RenderCell, selection ?[2]u16, cursor_x ?u16) !CtShapeResult {
	mut result := CtShapeResult{}
	mut iterator := td.shp.run_iterator(font.RunOptions{
		grid:         &td.grid
		render_cells: cells
		selection:    selection
		cursor_x:     cursor_x
	})
	for {
		run := (iterator.next()!).get() or { break }
		result.runs << run
		result.glyphs << td.shp.shape(run)!.clone()
	}
	return result
}

fn (mut td TestShaper) shape_text(input string, cols u16, graphemes bool) !CtShapeResult {
	cells := ct_render_row(input, cols, graphemes)!
	return td.shape_render_cells(cells, none, none)
}

fn ct_codepoints(codepoints []u32) string {
	mut result := ''
	for cp in codepoints {
		result += rune(cp).str()
	}
	return result
}

// ============================================================
// Tests
// ============================================================

// test "run iterator"
// Verifies basic run iteration: plain text, text with spaces, emoji splits,
// and bad ligatures (fl, fi, st).
fn test_run_iterator() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }
	assert (td.shape_text('ABCD', 5, false) or { panic(err) }).runs.len == 1
	assert (td.shape_text('ABCD   EFG', 10, false) or { panic(err) }).runs.len == 1
	assert (td.shape_text('A😃D', 5, false) or { panic(err) }).runs.len == 3
	for input in ['fl', 'fi', 'st'] {
		assert (td.shape_text(input, 5, false) or { panic(err) }).runs.len == 2
	}
}

// test "run iterator: empty cells with background set"
fn test_run_iterator_empty_cells_with_bg() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }
	mut cells := ct_render_row('\x1b[48;2;255;0;0mA', 5, false) or { panic(err) }
	for i in 1 .. 3 {
		cells[i].raw = terminal.CellData.from_color_payload(.bg_color_rgb, u32(255) | (u32(0) << 8) | (u32(0) << 16))
	}
	result := td.shape_render_cells(cells, none, none) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 3
}

// test "shape"
// Tests basic shaping: thumbs up plain + thumbs up with medium skin tone.
fn test_shape_thumbs_up() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }
	result := td.shape_text('👍👍🏽', 10, false) or { panic(err) }
	assert result.runs.len == 1
}

// test "shape nerd fonts"
// Tests shaping nerd font icon: space + nf-md-folder (U+F024B) + space.
fn test_shape_nerd_fonts() {
	mut td := create_shaper_with_font(.nerd_font) or { return }
	defer { td.deinit() }
	result := td.shape_text(' ' + rune(0xf024b).str() + ' ', 10, false) or { panic(err) }
	assert result.runs.len == 1
}

// test "shape inconsolata ligs"
// Tests ligature shaping: ">=" -> 1 glyph, "===" -> 1 glyph.
fn test_shape_inconsolata_ligs() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }
	for input in ['>=', '==='] {
		result := td.shape_text(input, 5, false) or { panic(err) }
		assert result.runs.len == 1
		assert result.runs[0].cells == u32(input.len)
		assert result.glyphs[0].len == 1
	}
}

// test "shape monaspace ligs"
// Tests Monaspace Neon "===" ligature.
fn test_shape_monaspace_ligs() {
	mut td := create_shaper_with_font(.monaspace_neon) or { return }
	defer { td.deinit() }
	result := td.shape_text('===', 5, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.runs[0].cells == 3
	assert result.glyphs[0].len == 1
}

// https://github.com/mitchellh/ghostty/issues/1708
// test "shape left-replaced lig in last run"
// Tests "!==" ligature with Geist Mono where the lig replaces from the left.
fn test_shape_left_replaced_lig_last_run() {
	mut td := create_shaper_with_font(.geist_mono) or { return }
	defer { td.deinit() }

	result := td.shape_text('!==', 5, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.runs[0].cells == 3
	assert result.glyphs[0].len == 1
}

// https://github.com/mitchellh/ghostty/issues/1708
// test "shape left-replaced lig in early run"
// Tests "!==X" with Geist Mono; lig + trailing char.
fn test_shape_left_replaced_lig_early_run() {
	mut td := create_shaper_with_font(.geist_mono) or { return }
	defer { td.deinit() }

	result := td.shape_text('!==X', 5, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.runs[0].cells == 4
	assert result.glyphs[0].len == 2
}

// https://github.com/mitchellh/ghostty/issues/1664
// test "shape U+3C9 with JB Mono"
// Tests omega (ω) character with JetBrains Mono.
fn test_shape_omega_jb_mono() {
	mut td := create_shaper_with_font(.jetbrains_mono) or { return }
	defer { td.deinit() }

	result := td.shape_text('ω foo', 10, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 5
}

// test "shape emoji width"
// Tests that a single emoji (thumbs up) shapes to 1 cell.
fn test_shape_emoji_width() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	result := td.shape_text('👍', 5, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 1
}

// test "shape emoji width long"
// Tests a long emoji sequence (person with beard + skin tone + ZWJ + male sign
// + presentation selector) shapes to 1 cell.
fn test_shape_emoji_width_long() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	result := td.shape_text('🧔🏻‍♂️', 30, true) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 1
}

// test "shape variation selector VS15"
// Tests U+270C (victory hand) + U+FE0E (text presentation) -> 1 cell.
fn test_shape_variation_selector_vs15() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	result := td.shape_text('✌︎', 10, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 1
}

// test "shape variation selector VS16"
// Tests U+270C (victory hand) + U+FE0F (emoji presentation) -> 1 cell.
fn test_shape_variation_selector_vs16() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	result := td.shape_text('✌️', 10, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 1
}

// test "shape with empty cells in between"
// Tests "A" + cursor forward 5 + "B" -> 1 run, 7 cells.
fn test_shape_empty_cells_between() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	result := td.shape_text('A\x1b[5CB', 30, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 7
}

// test "shape Combining characters"
// Tests 'n' + U+0308 (combining diaeresis) x2 + 'a' -> 4 cells.
fn test_shape_combining_characters() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	result := td.shape_text('n̈̈a', 30, true) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 4
	assert result.glyphs[0].map(it.x) == [u32(0), 0, 0, 1]
}

// test "shape Devanagari string"
// Tests that non-monotonic CoreText output is sorted correctly.
fn test_shape_devanagari() {
	mut td := create_shaper_with_discovered_font('Arial Unicode MS') or { return }
	defer { td.deinit() }
	result := td.shape_text('अपार्टमेंट', 30, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 8
	assert result.glyphs[0].map(it.x) == [u32(0), 1, 2, 4, 4, 5, 5, 6]
}

// test "shape Tai Tham vowels (position differs from advance)"
// Tests that position.x offset is correct when it differs from advance.
fn test_shape_tai_tham_vowels() {
	mut td := create_shaper_with_discovered_font('Noto Sans Tai Tham') or { return }
	defer { td.deinit() }
	result := td.shape_text(ct_codepoints([u32(0x1a2f), 0x1a70]), 30, true) or {
		panic(err)
	}
	assert result.runs.len == 1
	assert result.glyphs[0].len == 2
	assert result.glyphs[0].map(it.x) == [u32(0), 0]
	cell_width := i32(td.grid.metrics.cell_width)
	assert result.glyphs[0][0].x_offset == cell_width
	assert result.glyphs[0][1].x_offset == 0
}

// test "shape Tai Tham letters (position.y differs from advance)"
// Tests ligature across grapheme clusters with y-offset.
fn test_shape_tai_tham_letters() {
	mut td := create_shaper_with_discovered_font('Noto Sans Tai Tham') or { return }
	defer { td.deinit() }
	input := ct_codepoints([u32(0x1a49), 0x1a60, 0x1a3f, 0x1a69])
	result := td.shape_text(input, 30, true) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 3
	assert result.glyphs[0].map(it.x) == [u32(0), 0, 0]
	assert result.glyphs[0][2].y_offset == -3
}

// test "shape Javanese ligatures"
// Tests PANGKON ligature with correct x_offset.
fn test_shape_javanese_ligatures() {
	mut td := create_shaper_with_discovered_font('Noto Sans Javanese') or { return }
	defer { td.deinit() }
	input := ct_codepoints([u32(0xa9a4), 0xa9c0, 0xa9b2, 0xa9b8])
	result := td.shape_text(input, 30, true) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 3
	assert result.glyphs[0].map(it.x) == [u32(0), 0, 0]
	cell_width := i32(td.grid.metrics.cell_width)
	assert result.glyphs[0][2].x_offset > 3 * cell_width
}

// test "shape Chakma vowel sign with ligature (vowel sign renders first)"
// Tests out-of-order rendering where vowel sign appears before the consonant.
fn test_shape_chakma_vowel_sign() {
	mut td := create_shaper_with_discovered_font('Noto Sans Chakma') or { return }
	defer { td.deinit() }
	input := ct_codepoints([u32(0x1111d), 0x11116, 0x11133, 0x11120, 0x1112c])
	result := td.shape_text(input, 30, true) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 4
	assert result.glyphs[0].map(it.x) == [u32(0), 0, 0, 0]
	assert result.glyphs[0][1].x_offset < result.glyphs[0][2].x_offset
}

// test "shape Bengali ligatures with out of order vowels"
// Tests Bengali text where vowel sign E renders before SSA.
fn test_shape_bengali_ligatures() {
	mut td := create_shaper_with_discovered_font('Arial Unicode MS') or { return }
	defer { td.deinit() }
	input := ct_codepoints([u32(0x09b0), 0x09be, 0x09b7, 0x09cd, 0x099f, 0x09cd, 0x09b0, 0x09c7])
	result := td.shape_text(input, 30, true) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 8
	assert result.glyphs[0].map(it.x) == [u32(0), 0, 0, 0, 0, 0, 0, 0]
	assert result.glyphs[0][2].x_offset < result.glyphs[0][3].x_offset
}

// test "shape box glyphs"
// Tests that box drawing characters (U+2500, U+2501) use the sprite font
// and return codepoints as glyph indices.
fn test_shape_box_glyphs() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	result := td.shape_text('─━', 10, false) or { panic(err) }
	assert result.runs.len == 1
	assert result.glyphs[0].len == 2
	assert result.glyphs[0][0].glyph_index == 0x2500
	assert result.glyphs[0][0].x == 0
	assert result.glyphs[0][1].glyph_index == 0x2501
	assert result.glyphs[0][1].x == 1
}

// test "shape selection boundary"
// Tests that selection boundaries correctly split runs.
fn test_shape_selection_boundary() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	cells := ct_render_row('a1b2c3d4e5', 10, false) or { panic(err) }
	selections := [[u16(0), 9]!, [u16(2), 9]!, [u16(0), 3]!, [u16(1), 3]!, [u16(1), 1]!]
	expected := [1, 2, 2, 3, 3]
	for i, selection in selections {
		result := td.shape_render_cells(cells, selection, none) or { panic(err) }
		assert result.runs.len == expected[i]
	}
}

// test "shape cursor boundary"
// Tests that cursor position correctly splits runs.
fn test_shape_cursor_boundary() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	cells := ct_render_row('a1b2c3d4e5', 10, false) or { panic(err) }
	assert (td.shape_render_cells(cells, none, none) or { panic(err) }).runs.len == 1
	for cursor_x, expected in {
		u16(0): 2
		u16(1): 3
		u16(9): 2
	} {
		result := td.shape_render_cells(cells, none, cursor_x) or { panic(err) }
		assert result.runs.len == expected
		assert (td.shape_render_cells(cells, none, none) or { panic(err) }).runs.len == 1
	}
}

// test "shape cursor boundary and colored emoji"
// Tests that cursor on a wide emoji does not split it.
fn test_shape_cursor_boundary_colored_emoji() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	cells := ct_render_row('👍🏼', 3, false) or { panic(err) }
	assert (td.shape_render_cells(cells, none, none) or { panic(err) }).runs.len == 1
	for cursor_x in [u16(0), 1] {
		assert (td.shape_render_cells(cells, none, cursor_x) or { panic(err) }).runs.len == 1
		assert (td.shape_render_cells(cells, none, none) or { panic(err) }).runs.len == 1
	}
}

// test "shape cell attribute change"
// Tests that bold/fg color changes split runs, but bg color does not.
fn test_shape_cell_attribute_change() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	inputs := ['>=', '>\x1b[1m=', '\x1b[38;2;1;2;3m>\x1b[38;2;3;2;1m=', '\x1b[48;2;1;2;3m>\x1b[48;2;3;2;1m=',
		'\x1b[48;2;1;2;3m>=']
	expected := [1, 2, 2, 1, 1]
	for i, input in inputs {
		result := td.shape_text(input, 10, false) or { panic(err) }
		assert result.runs.len == expected[i]
	}
}

// test "shape high plane sprite font codepoint"
// While creating runs, the CoreText shaper uses `0` codepoints to
// pad its codepoint list to account for high plane characters which
// use two UTF-16 code units. This is so that, after shaping, the string
// indices can be used to find the originating codepoint / cluster.
//
// This is a problem for special (sprite) fonts, which need to be "shaped"
// by simply returning the input codepoints verbatim. We include logic to
// skip `0` codepoints when constructing the shaped run for sprite fonts,
// this test verifies that it works correctly.
fn test_shape_high_plane_sprite_font_codepoint() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	// U+1FB70 (Vertical One Eighth Block-2) should:
	// - Produce UTF-16 surrogate pair [0xD83E, 0xDF70]
	// - Produce padded codepoint list [{0x1FB70, 0}, {0, 0}]
	// - Shape to 1 cell at position 0 with glyph_index == 0x1FB70
	// - Be identified as a sprite font run

	// Test the surrogate pair encoding directly
	sp := macos.get_surrogate_pair(0x1FB70)
	assert sp.is_pair == true
	assert sp.hi == 0xD83E
	assert sp.lo == 0xDF70

	cells := ct_render_row(rune(0x1fb70).str(), 10, false) or { panic(err) }
	result := td.shape_render_cells(cells, none, none) or { panic(err) }
	assert result.runs.len == 1
	assert result.runs[0].cells == 1
	assert result.runs[0].offset == 0
	assert result.runs[0].font_index == font.sprite_index
	assert td.shp.run_state.unichars == [u16(0xd83e), 0xdf70]
	assert td.shp.run_state.codepoints == [
		Codepoint{ codepoint: 0x1fb70, cluster: 0 },
		Codepoint{ codepoint: 0, cluster: 0 },
	]
	assert result.glyphs[0].len == 1
	assert result.glyphs[0][0].x == 0
	assert result.glyphs[0][0].glyph_index == 0x1fb70
}

// test "add_codepoint with surrogate pairs"
// Verify that RunIteratorHook.add_codepoint correctly handles BMP and
// supplementary plane characters.
fn test_add_codepoint_surrogate_pairs() {
	mut td := create_shaper() or { return }
	defer { td.deinit() }

	mut hook := RunIteratorHook{
		shaper: &td.shp
	}
	hook.prepare()

	// Add a BMP character ('A' = U+0041)
	hook.add_codepoint(0x41, 0) or { return }
	assert td.shp.run_state.unichars.len == 1
	assert td.shp.run_state.unichars[0] == 0x41
	assert td.shp.run_state.codepoints.len == 1
	assert td.shp.run_state.codepoints[0].codepoint == 0x41
	assert td.shp.run_state.codepoints[0].cluster == 0

	// Add a supplementary plane character (U+1F44D = thumbs up)
	hook.add_codepoint(0x1F44D, 1) or { return }
	// UTF-16: should have added 2 code units (surrogate pair)
	assert td.shp.run_state.unichars.len == 3
	assert td.shp.run_state.unichars[1] == 0xD83D
	assert td.shp.run_state.unichars[2] == 0xDC4D
	// Codepoints: should have real entry + zero padding entry
	assert td.shp.run_state.codepoints.len == 3
	assert td.shp.run_state.codepoints[1].codepoint == 0x1F44D
	assert td.shp.run_state.codepoints[1].cluster == 1
	assert td.shp.run_state.codepoints[2].codepoint == 0
	assert td.shp.run_state.codepoints[2].cluster == 1
}

// test "run state reset"
// Verify that RunState.reset clears both codepoints and unichars.
fn test_run_state_reset() {
	mut state := RunState.init()
	state.codepoints << Codepoint{ codepoint: 0x41, cluster: 0 }
	state.unichars << u16(0x41)
	assert state.codepoints.len == 1
	assert state.unichars.len == 1

	state.reset()
	assert state.codepoints.len == 0
	assert state.unichars.len == 0
}

// test "shaper init and deinit"
// Verify basic lifecycle.
fn test_shaper_init_deinit() {
	mut shp := Shaper.init(font.ShaperOptions{
		features: ['dlig', 'calt']
	}) or { return }
	assert shp.feature_strings.len == 2
	assert shp.feature_strings[0] == 'dlig'
	assert shp.feature_strings[1] == 'calt'
	shp.deinit()
}

// test "end_frame with empty pool"
fn test_end_frame_empty() {
	mut shp := Shaper.init(font.ShaperOptions{
		features: []string{}
	}) or { return }
	defer { shp.deinit() }

	// Should be a no-op when pool is empty
	shp.end_frame()
	assert shp.cf_release_pool.len == 0
}

// test "special font shapes codepoints as glyphs"
// Verify that when font_index == sprite_index, codepoints are returned
// directly as glyph indices.
fn test_special_font_shapes_codepoints() {
	mut shp := Shaper.init(font.ShaperOptions{
		features: []string{}
	}) or { return }
	defer { shp.deinit() }

	// Set up run state with some codepoints
	shp.run_state.codepoints << Codepoint{ codepoint: 0x2500, cluster: 0 }
	shp.run_state.codepoints << Codepoint{ codepoint: 0x2501, cluster: 1 }

	// Shape with sprite font index
	cells := shp.shape(font.TextRun{
		font_index: font.sprite_index
		offset:     0
		cells:      2
	}) or { return }

	assert cells.len == 2
	assert cells[0].x == 0
	assert cells[0].glyph_index == 0x2500
	assert cells[1].x == 1
	assert cells[1].glyph_index == 0x2501
}

// test "special font skips zero codepoints"
// Verify that zero-padded codepoints (from surrogate pairs) are skipped
// for sprite font shaping.
fn test_special_font_skips_zero_codepoints() {
	mut shp := Shaper.init(font.ShaperOptions{
		features: []string{}
	}) or { return }
	defer { shp.deinit() }

	// Simulate a high-plane character with surrogate pair padding
	shp.run_state.codepoints << Codepoint{ codepoint: 0x1FB70, cluster: 0 }
	shp.run_state.codepoints << Codepoint{ codepoint: 0, cluster: 0 }

	// Shape with sprite font index
	cells := shp.shape(font.TextRun{
		font_index: font.sprite_index
		offset:     0
		cells:      1
	}) or { return }

	// Should get 1 cell, not 2 (zero padding is skipped)
	assert cells.len == 1
	assert cells[0].x == 0
	assert cells[0].glyph_index == 0x1FB70
}

fn coretext_test_grid() !font.SharedGrid {
	mut collection := font.Collection.init()
	collection.load_options = font.LoadOptions{
		library: font.Library.init()!
		size:    font.DesiredSize{
			points: 12
			xdpi:   96
			ydpi:   96
		}
	}
	load_opts := collection.load_options or { return error('missing load options') }
	collection.add(font.Face.init_mem(load_opts.library, font.embedded_regular, load_opts.face_options())!, font.AddOptions{
		style:           .regular
		fallback:        false
		size_adjustment: .none_
	})!
	return font.SharedGrid.init(font.CodepointResolver{
		collection: collection
	})!
}

fn test_coretext_run_iterator_uses_coretext_hooks() {
	mut shp := Shaper.init(font.ShaperOptions{}) or { panic(err) }
	defer { shp.deinit() }
	mut iterator := shp.run_iterator(font.RunOptions{
		cells: [u8(`A`), `B`, `C`]
	})
	run := (iterator.next()!).get() or { panic('expected a text run') }
	assert run.cells == 3
	assert shp.run_state.codepoints == [
		Codepoint{ codepoint: u32(`A`), cluster: 0 },
		Codepoint{ codepoint: u32(`B`), cluster: 1 },
		Codepoint{ codepoint: u32(`C`), cluster: 2 },
	]
	assert shp.run_state.unichars == [u16(`A`), u16(`B`), u16(`C`)]
}

fn test_coretext_shapes_real_glyph_run() {
	$if macos {
		mut grid := coretext_test_grid() or { panic(err) }
		defer { grid.deinit() }
		mut shp := Shaper.init(font.ShaperOptions{}) or { panic(err) }
		defer { shp.deinit() }
		mut iterator := shp.run_iterator(font.RunOptions{
			grid:  &grid
			cells: [u8(`A`), `B`, `C`]
		})
		run := (iterator.next()!).get() or { panic('expected a text run') }
		cells := shp.shape(run) or { panic(err) }
		assert cells.len == 3
		assert cells[0].x == 0
		assert cells[1].x == 1
		assert cells[2].x == 2
		for cell in cells {
			assert cell.glyph_index != 0
		}
	}
}
