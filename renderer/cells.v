module renderer

import mathutil
import datastruct
import terminal
import unicode

// --- Original Ghostty Comments Start: src/renderer/cell.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/renderer/cell.zig
//
// The possible cell content keys that exist.
// Returns the GPU vertex type for this key.
// The contents of all the cells in the terminal.
//
// The goal of this data structure is to allow for efficient row-wise
// clearing of data from the GPU buffers, to allow for row-wise dirty
// tracking to eliminate the overhead of rebuilding the GPU buffers
// each frame.
//
// Must be initialized by resizing before calling any operations.
// Flat array containing cell background colors for the terminal grid.
//
// Indexed as `bg_cells[row * size.columns + col]`.
//
// Prefer accessing with `Contents.bgCell(row, col).*` instead
// of directly indexing in order to avoid integer size bugs.
// The ArrayListCollection which holds all of the foreground cells. When
// sized with Contents.resize the individual ArrayLists are given enough
// room that they can hold a single row with #cols glyphs, underlines, and
// strikethroughs; however, appendAssumeCapacity MUST NOT be used since
// it is possible to exceed this with combining glyphs that add a glyph
// but take up no column since they combine with the previous one, as
// well as with fonts that perform multi-substitutions for glyphs, which
// can result in a similar situation where multiple glyphs reside in the
// same column.
//
// Allocations should nevertheless be exceedingly rare since hitting the
// initial capacity of a list would require a row filled with underlined
// struck through characters, at least one of which is a multi-glyph
// composite.
//
// Rows are indexed as Contents.fg_rows[y + 1], because the first list in
// the collection is reserved for the cursor, which must be the first item
// in the buffer.
//
// Must be initialized by calling resize on the Contents struct before
// calling any operations.
// Resize the cell contents for the given grid size. This will
// always invalidate the entire cell contents.
// The foreground lists can hold 3 types of items:
// - Glyphs
// - Underlines
// - Strikethroughs
// So we give them an initial capacity of size.columns * 3, which will
// avoid any further allocations in the vast majority of cases. Sadly
// we can not assume capacity though, since with combining glyphs that
// form a single grapheme, and multi-substitutions in fonts, the number
// of glyphs in a row is theoretically unlimited.
//
// We have size.rows + 2 lists because indexes 0 and size.rows - 1 are
// used for special lists containing the cursor cell which need to
// be first and last in the buffer, respectively.
// We don't need 3*cols worth of cells for the cursor lists, so we can
// replace them with smaller lists. This is technically a tiny bit of
// extra work but resize is not a hot function so it's worth it to not
// waste the memory.
// Perform the swap, no going back from here.
// Reset the cell contents to an empty state without resizing.
// Set the cursor value. If the value is null then the cursor is hidden.
// Block cursors should be drawn first
// Other cursor styles should be drawn last
// Returns the current cursor glyph if present, checking both cursor lists.
// Access a background cell. Prefer this function over direct indexing
// of `bg_cells` in order to avoid integer size bugs causing overflows.
// Add a cell to the appropriate list. Adding the same cell twice will
// result in duplication in the vertex buffer. The caller should clear
// the corresponding row with Contents.clear to remove old cells first.
// We have a special list containing the cursor cell at the start
// of our fg row collection, so we need to add 1 to the y to get
// the correct index.
// Clear all of the cell contents for a given row.
// We have a special list containing the cursor cell at the start
// of our fg row collection, so we need to add 1 to the y to get
// the correct index.
// Returns true if a codepoint for a cell is a covering character. A covering
// character is a character that covers the entire cell. This is used to
// make window-padding-color=extend work better. See #2099.
// U+2588 FULL BLOCK
// Returns true of the codepoint is a "symbol-like" character, which
// for now we define as anything in a private use area, and anything
// in several unicode blocks:
// - Arrows
// - Dingbats
// - Emoticons
// - Miscellaneous Symbols
// - Enclosed Alphanumerics
// - Enclosed Alphanumeric Supplement
// - Miscellaneous Symbols and Pictographs
// - Transport and Map Symbols
//
// In the future it may be prudent to expand this to encompass more
// symbol-like characters, and/or exclude some PUA sections.
// Returns the appropriate `constraint_width` for
// the provided cell when rendering its glyph(s).
// If the grid width of the cell is 2, the constraint
// width will always be 2, so we can just return early.
// We allow "symbol-like" glyphs to extend to 2 cells wide if there's
// space, and if the previous glyph wasn't also a symbol. So if this
// codepoint isn't a symbol then we can return the grid width.
// If we are at the end of the screen it must be constrained to one cell.
// If we have a previous cell and it was a symbol then we need
// to also constrain. This is so that multiple PUA glyphs align.
// This does not apply if the previous symbol is a graphics
// element such as a block element or Powerline glyph.
// If the next cell is whitespace, then we
// allow the glyph to be up to two cells wide.
// Otherwise, this has to be 1 cell wide.
// Whether min contrast should be disabled for a given glyph. True
// for graphics elements such as blocks and Powerline glyphs.
// Some general spaces, others intentionally kept
// to force the font to render as a fixed width.
// Returns true if the codepoint is used for terminal graphics, such
// as box drawing characters, block elements, and Powerline glyphs.
// Returns true if the codepoint is a box drawing character.
// Returns true if the codepoint is a block element.
// Returns true if the codepoint is in a Symbols for Legacy
// Computing block, including supplements.
// Returns true if the codepoint is a part of the Powerline range.
// We should start off empty after resizing.
// And the cursor row should have a capacity of 1 and also be empty.
// Add some contents.
// The fg row index is offset by 1 because of the cursor list.
// And we should be able to clear it.
// Add a block cursor.
// And remove it.
// Add a hollow cursor.
// Set some contents
// bg and fg cells in row 1
// bg and fg cells in row 2
// Clear row 1, this should leave row 2 untouched
// Row 2 should still contain its cells.
// Fg row index is +1 because of cursor list at start
// Set some contents
// bg and fg cells in row 1
// bg and fg cells in row 2
// Clear row 2, this should leave row 1 untouched
// Row 1 should still contain its cells.
// Fg row index is +1 because of cursor list at start
// for each case, the numbers in the comment denote expected
// constraint widths for the symbol-containing cells
// symbol->nothing: 2
// symbol->character: 1
// symbol->space: 2
// symbol->no-break space: 1
// symbol->end of row: 1
// character->symbol: 2
// symbol->symbol: 1,1
// symbol->space->symbol: 2,2
// symbol->powerline: 1  (dedicated test because powerline is special-cased in cellpkg)
// powerline->symbol: 2  (dedicated test because powerline is special-cased in cellpkg)
// powerline->nothing: 2  (dedicated test because powerline is special-cased in cellpkg)
// powerline->space: 2  (dedicated test because powerline is special-cased in cellpkg)
//
// --- Original Ghostty Comments End: src/renderer/cell.zig

// ============================================================
// Cell content types for GPU rendering
// ============================================================

// AtlasKind identifies which texture atlas a glyph belongs to.
pub enum AtlasKind as u8 {
	grayscale = 0
	color     = 1
}

// CellTextBools is the packed byte of boolean flags consumed by the text
// shaders. Ghostty represents this as a packed struct(u8).
pub struct CellTextBools {
mut:
	value u8
}

pub fn cell_text_bools(no_min_contrast bool, is_cursor_glyph bool) CellTextBools {
	return CellTextBools{
		value: u8(no_min_contrast) | (u8(is_cursor_glyph) << 1)
	}
}

pub fn (self CellTextBools) no_min_contrast() bool {
	return self.value & 0x01 != 0
}

pub fn (self CellTextBools) is_cursor_glyph() bool {
	return self.value & 0x02 != 0
}

pub fn (self CellTextBools) packed() u8 {
	return self.value
}

// CellText represents a foreground (text) cell for GPU rendering.
// Each glyph rendered to the screen becomes one of these.
pub struct CellText {
pub mut:
	// Position of the glyph in the atlas [x, y].
	glyph_pos [2]u32
	// Size of the glyph in the atlas [w, h].
	glyph_size [2]u32
	// Bearing offsets [x, y] for positioning.
	bearings [2]i16
	// Grid position [col, row].
	grid_pos [2]u16
	// Color [r, g, b, a].
	color [4]u8
	// Which texture atlas this glyph is in.
	atlas AtlasKind = .grayscale
	// Boolean flags.
	bools CellTextBools
}

// CellBg is the RGBA value consumed by the cell background shader.
pub type CellBg = [4]u8

// CellKey identifies the source cell content collection.
pub enum CellKey as u8 {
	bg
	text
	underline
	strikethrough
	overline
}

// ============================================================
// CellContents - manages all cells for a frame
// ============================================================

// CellContents manages the current set of cells to render.
// This is rebuilt on every frame but kept around to avoid reallocation.
pub struct CellContents {
pub mut:
	// The size of the grid (columns x rows).
	size GridSize
	// Background cells, one per grid position (row-major).
	bg_cells []CellBg
	// Foreground cells. Screen row y is stored at y + 1: list zero is
	// reserved for a block cursor that must be drawn first, and the final
	// list is reserved for cursor styles that must be drawn last.
	fg_rows datastruct.ArrayListCollection[CellText]
}

// Resize the cell contents to the given grid size.
pub fn (mut c CellContents) resize(size GridSize) ! {
	c.size = size
	total := int(size.columns) * int(size.rows)
	c.bg_cells = []CellBg{len: total}
	// Ghostty keeps two extra lists around the screen rows so cursor ordering
	// is represented by the container itself rather than reconstructed by each
	// renderer backend.
	mut fg_rows := datastruct.ArrayListCollection.init[CellText](uint(size.rows) + 2, uint(size.columns) * 3)
	fg_rows.lists[0] = []CellText{cap: 1}
	fg_rows.lists[int(size.rows) + 1] = []CellText{cap: 1}
	c.fg_rows = fg_rows
}

// Reset all cell contents (clear everything).
pub fn (mut c CellContents) reset() {
	// Clear all background cells to transparent
	zero := CellBg([u8(0), 0, 0, 0]!)
	for i in 0 .. c.bg_cells.len {
		c.bg_cells[i] = zero
	}
	// Clear all foreground rows
	c.fg_rows.reset()
}

// Clear a specific row's foreground cells.
pub fn (mut c CellContents) clear(row u16) {
	assert row < c.size.rows
	c.fg_rows.lists[int(row) + 1].clear()
	// Also clear bg cells for this row
	start := int(row) * int(c.size.columns)
	end := start + int(c.size.columns)
	zero := CellBg([u8(0), 0, 0, 0]!)
	for i in start .. end {
		c.bg_cells[i] = zero
	}
}

// bg_cell accesses a background cell. Prefer this function over direct
// indexing so the row-major offset is always calculated with usize values.
// The opaque pointer is a V binding adaptation: the fallback compiler emits a
// fixed array by value when a function returns `&CellBg`, even though CellBg
// aliases Ghostty's `[4]u8` GPU value.
pub fn (mut c CellContents) bg_cell(row uint, col uint) voidptr {
	return voidptr(&c.bg_cells[row * uint(c.size.columns) + col])
}

// Add a foreground cell to the given layer.
pub fn (mut c CellContents) add(key CellKey, cell CellText) ! {
	assert key != .bg
	row := int(cell.grid_pos[1])
	assert row < int(c.size.rows)
	c.fg_rows.lists[row + 1] << cell
}

// Set the cursor cell and style.
pub fn (mut c CellContents) set_cursor(cell ?CellText, style_ ?Style) {
	if c.size.rows == 0 {
		return
	}
	c.fg_rows.lists[0].clear()
	c.fg_rows.lists[int(c.size.rows) + 1].clear()
	value := cell or { return }
	visual_style := style_ or { return }
	match visual_style {
		.block { c.fg_rows.lists[0] << value }
		.block_hollow, .bar, .underline, .lock {
			c.fg_rows.lists[int(c.size.rows) + 1] << value
		}
	}
}

// Get the cursor glyph, if one is set.
pub fn (c &CellContents) get_cursor_glyph() ?CellText {
	if c.size.rows == 0 {
		return none
	}
	if c.fg_rows.lists[0].len > 0 {
		return c.fg_rows.lists[0][0]
	}
	last := int(c.size.rows) + 1
	if c.fg_rows.lists[last].len > 0 {
		return c.fg_rows.lists[last][0]
	}
	return none
}

// ============================================================
// UniformBools - boolean uniforms for shader control
// ============================================================

// UniformBools contains boolean flags sent to the shader.
pub struct UniformBools {
pub mut:
	// Whether the cursor occupies a wide (2-cell) character.
	cursor_wide bool
	// Whether to use Display P3 color space.
	use_display_p3 bool
	// Whether to use linear alpha blending.
	use_linear_blending bool
	// Whether to apply linear correction after blending.
	use_linear_correction bool
}

// ============================================================
// PaddingExtend - which padding edges to extend
// ============================================================

// PaddingExtend tracks which padding edges should extend the
// cell background color.
pub struct PaddingExtend {
pub mut:
	up    bool
	down  bool
	left  bool
	right bool
}

// ============================================================
// Uniforms - shader uniform values
// ============================================================

// Uniforms holds all uniform values sent to the GPU shader.
pub struct Uniforms {
pub mut:
	// Orthographic projection matrix (4x4, column-major).
	projection_matrix mathutil.Mat
	// Cell size in pixels [width, height].
	cell_size [2]f32
	// Grid size in cells [columns, rows].
	grid_size [2]u16
	// Padding around the grid [top, right, bottom, left].
	grid_padding [4]f32
	// Screen size in pixels [width, height].
	screen_size [2]f32
	// Which padding edges are extended.
	padding_extend PaddingExtend
	// Minimum contrast ratio.
	min_contrast f32
	// Cursor position in the grid [col, row].
	// Set to max u16 when cursor is not visible.
	cursor_pos [2]u16
	// Cursor text color [r, g, b, a].
	cursor_color [4]u8
	// Background color [r, g, b, a].
	bg_color [4]u8
	// Boolean flags.
	bools UniformBools
}

// ============================================================
// Custom shader uniforms (Shadertoy-compatible)
// ============================================================

// CustomShaderUniforms holds uniforms for custom (Shadertoy) shaders.
pub struct CustomShaderUniforms {
pub mut:
	// Screen resolution [width, height, pixel_aspect_ratio].
	resolution [3]f32
	// Time in seconds since first frame.
	time f32
	// Time delta since last frame in seconds.
	time_delta f32
	// Rendering frame rate.
	frame_rate f32 = 60.0
	// Current frame number.
	frame i32
	// std140 padding before the first array.
	padding_frame u32
	// Channel time (4 channels, each has time).
	channel_time [4][4]f32
	// Channel resolution (4 channels, each [w, h, aspect, 0]).
	channel_resolution [4][4]f32
	// Mouse position.
	mouse [4]f32
	// Current date [year, month, day, seconds_since_midnight].
	date [4]f32
	// Audio sample rate (N/A).
	sample_rate f32
	// std140 padding before the cursor vectors.
	padding_sample [3]f32
	// Current cursor position and size [x, y, w, h].
	current_cursor [4]f32
	// Previous cursor position and size [x, y, w, h].
	previous_cursor [4]f32
	// Current cursor color [r, g, b, a].
	current_cursor_color [4]f32
	// Previous cursor color [r, g, b, a].
	previous_cursor_color [4]f32
	// Time when cursor last changed position.
	cursor_change_time f32
	// Time when window was last focused.
	time_focus f32
	// Whether the window is focused (0 or 1).
	focus i32 = 1
	// std140 padding before the palette array.
	padding_focus u32
	// 256-color palette as normalized floats [r, g, b, a].
	palette [256][4]f32
	// Background color as normalized floats.
	background_color [4]f32
	// Foreground color as normalized floats.
	foreground_color [4]f32
	// Cursor color as normalized floats.
	cursor_color [4]f32
	// Cursor text color as normalized floats.
	cursor_text [4]f32
	// Selection background color as normalized floats.
	selection_background_color [4]f32
	// Selection foreground color as normalized floats.
	selection_foreground_color [4]f32
}

// ============================================================
// Highlight tags for search matches
// ============================================================

// HighlightTag identifies the type of highlight on a cell.
pub enum HighlightTag as u8 {
	search_match
	search_match_selected
}

// ============================================================
// Background image vertex data
// ============================================================

// BgImagePosition for the background image shader.
pub enum BgImagePosition as u8 {
	tl = 0
	tc = 1
	tr = 2
	ml = 3
	mc = 4
	mr = 5
	bl = 6
	bc = 7
	br = 8
}

// BgImageFit for the background image shader.
pub enum BgImageFit as u8 {
	contain = 0
	cover   = 1
	stretch = 2
	none_   = 3
}

// BgImageInfo holds position/fit/repeat info for the background image.
pub struct BgImageInfo {
mut:
	value u8 = 4
}

pub fn bg_image_info(position BgImagePosition, fit BgImageFit, repeat bool) BgImageInfo {
	return BgImageInfo{
		value: u8(position) | (u8(fit) << 4) | (u8(repeat) << 6)
	}
}

pub fn (self BgImageInfo) position() BgImagePosition {
	return unsafe { BgImagePosition(self.value & 0x0f) }
}

pub fn (self BgImageInfo) fit() BgImageFit {
	return unsafe { BgImageFit((self.value >> 4) & 0x03) }
}

pub fn (self BgImageInfo) repeats() bool {
	return self.value & 0x40 != 0
}

pub fn (self BgImageInfo) packed() u8 {
	return self.value
}

// BgImageBuffer is the vertex data for the background image.
pub struct BgImageBuffer {
pub mut:
	opacity f32 = 1.0
	info    BgImageInfo
}

// ImageVertex is a single image-placement parameter for either renderer
// shader backend.
pub struct ImageVertex {
pub:
	grid_pos    [2]f32
	cell_offset [2]f32
	source_rect [4]f32
	dest_size   [2]f32
}

// ============================================================
// Cell classification free functions (from cell.zig)
// ============================================================

// Returns true if a codepoint for a cell is a covering character. A covering
// character is a character that covers the entire cell. This is used to
// make window-padding-color=extend work better. See #2099.
pub fn is_covering(cp u32) bool {
	return match cp {
		// U+2588 FULL BLOCK
		0x2588 { true }
		else { false }
	}
}

// Returns true of the codepoint is a "symbol-like" character, which
// for now we define as anything in a private use area, and anything
// in several unicode blocks:
// - Arrows
// - Dingbats
// - Emoticons
// - Miscellaneous Symbols
// - Enclosed Alphanumerics
// - Enclosed Alphanumeric Supplement
// - Miscellaneous Symbols and Pictographs
// - Transport and Map Symbols
//
// In the future it may be prudent to expand this to encompass more
// symbol-like characters, and/or exclude some PUA sections.
//
// The generated Unicode property table is shared with the terminal and is
// emitted from Ghostty's pinned uucode configuration.
pub fn is_symbol(cp u32) bool {
	return unicode.is_symbol(cp)
}

// Returns the appropriate constraint_width for the provided cell when
// rendering its glyph(s). cells is the rendered row, x is the
// cell index, and cols is the number of columns in the screen.
fn constraint_width(cells []terminal.RenderCell, x int, cols int) u8 {
	cell := &cells[x].raw
	cp := cell.codepoint()

	grid_width := u8(cell.grid_width())

	// If the grid width of the cell is 2, the constraint
	// width will always be 2, so we can just return early.
	if grid_width > 1 {
		return grid_width
	}

	// We allow "symbol-like" glyphs to extend to 2 cells wide if there's
	// space, and if the previous glyph wasn't also a symbol. So if this
	// codepoint isn't a symbol then we can return the grid width.
	if !is_symbol(cp) {
		return grid_width
	}

	// If we are at the end of the screen it must be constrained to one cell.
	if x == cols - 1 {
		return 1
	}

	// If we have a previous cell and it was a symbol then we need
	// to also constrain. This is so that multiple PUA glyphs align.
	// This does not apply if the previous symbol is a graphics
	// element such as a block element or Powerline glyph.
	if x > 0 {
		prev_cp := cells[x - 1].raw.codepoint()
		if is_symbol(prev_cp) && !is_graphics_element(prev_cp) {
			return 1
		}
	}

	// If the next cell is whitespace, then we
	// allow the glyph to be up to two cells wide.
	next_cp := cells[x + 1].raw.codepoint()
	if next_cp == 0 || is_space(next_cp) {
		return 2
	}

	// Otherwise, this has to be 1 cell wide.
	return 1
}

// Whether min contrast should be disabled for a given glyph. True
// for graphics elements such as blocks and Powerline glyphs.
pub fn no_min_contrast(cp u32) bool {
	return is_graphics_element(cp)
}

// Some general spaces, others intentionally kept
// to force the font to render as a fixed width.
fn is_space(cp u32) bool {
	return match cp {
		0x0020, // SPACE
		0x2002 { // EN SPACE
			true
		}
		else {
			false
		}
	}
}

// Returns true if the codepoint is used for terminal graphics, such
// as box drawing characters, block elements, and Powerline glyphs.
fn is_graphics_element(cp u32) bool {
	return is_box_drawing(cp) || is_block_element(cp) || is_legacy_computing(cp)
		|| is_powerline(cp)
}

// Returns true if the codepoint is a box drawing character.
fn is_box_drawing(cp u32) bool {
	return cp >= 0x2500 && cp <= 0x257F
}

// Returns true if the codepoint is a block element.
fn is_block_element(cp u32) bool {
	return cp >= 0x2580 && cp <= 0x259F
}

// Returns true if the codepoint is in a Symbols for Legacy
// Computing block, including supplements.
fn is_legacy_computing(cp u32) bool {
	return (cp >= 0x1FB00 && cp <= 0x1FBFF)
		|| (cp >= 0x1CC00 && cp <= 0x1CEBF) // Supplement introduced in Unicode 16.0
}

// Returns true if the codepoint is a part of the Powerline range.
fn is_powerline(cp u32) bool {
	return cp >= 0xE0B0 && cp <= 0xE0D7
}
