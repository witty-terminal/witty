module terminal

import strings

// Developer note: this is in src/terminal and not src/renderer because
// the goal is that this remains generic to multiple renderers. This can
// aid specifically with libwitty-vt with converting terminal state to
// a renderable form.
//
// Translated from Ghostty's render.zig.

// Contains the state required to render the screen, including optimizing
// for repeated render calls and only rendering dirty regions.
//
// Previously, our renderer would use `clone` to clone the screen within
// the viewport to perform rendering. This worked well enough that we kept
// it all the way up through the Ghostty 1.2.x series, but the clone time
// was repeatedly a bottleneck blocking IO.
//
// Rather than a generic clone that tries to clone all screen state per call
// (within a region), a stateful approach that optimizes for only what a
// renderer needs to do makes more sense.
//
// To use this, initialize the render state to empty, then call `update`
// on each frame to update the state to the latest terminal state.
//
//     mut state := RenderState.empty()
//     defer { state.deinit() }
//     state.update(&t)
//
// Note: the render state retains as much memory as possible between updates
// to prevent future allocations. If a very large frame is rendered once,
// the render state will retain that much memory until deinit. To avoid
// waste, it is recommended that the caller `deinit` and start with an
// empty render state every so often.
pub struct RenderState {
pub mut:
	// The current screen dimensions. It is possible that these don't match
	// the renderer's current dimensions in grid cells because resizing
	// can happen asynchronously. For example, for Metal, our NSView resizes
	// at a different time than when our internal terminal state resizes.
	// This can lead to a one or two frame mismatch a renderer needs to
	// handle.
	//
	// The viewport is always exactly equal to the active area size so this
	// is also the viewport size.
	rows u16
	cols u16

	// The color state for the terminal.
	colors RenderColors

	// Cursor state within the viewport.
	cursor RenderCursor

	// The rows (y=0 is top) of the viewport.
	row_data []RenderRow

	// The dirty state of the render state. This is set by the update method.
	// The renderer/caller should set this to false when it has handled
	// the dirty state.
	dirty RenderDirty

	// The screen type that this state represents. This is used primarily
	// to detect changes.
	screen ScreenKey

	// The last viewport pin used to generate this state. This is NOT
	// a tracked pin and is generally NOT safe to read other than the direct
	// values for comparison.
	viewport_pin ?Pin

	// The cached selection so we can avoid expensive selection calculations
	// if possible.
	selection_cache ?RenderSelectionCache
}

// The color state for the terminal.
//
// The background/foreground will be reversed if the terminal reverse
// color mode is on! You do not need to handle that manually!
pub struct RenderColors {
pub mut:
	background RGB
	foreground RGB
	cursor     ?RGB
	palette    [256]RGB
}

// Cursor state within the viewport.
pub struct RenderCursor {
pub mut:
	// The x/y position of the cursor within the active area.
	active Coordinate

	// The x/y position of the cursor within the viewport. This
	// may be null if the cursor is not visible within the viewport.
	viewport ?ViewportPoint

	// The cell data for the cursor position. Managed memory is not
	// safe to access from this.
	cell CellData

	// The style, always valid even if the cell is default style.
	style CellStyle

	// The visual style of the cursor itself, such as a block or
	// bar.
	visual_style CursorStyle

	// True if the cursor is detected to be at a password input field.
	password_input bool

	// Cursor visibility state determined by the terminal mode.
	visible bool

	// Cursor blink state determined by the terminal mode.
	blinking bool
}

// ViewportPoint represents a position within the viewport.
// This is used by both RenderCursor and the renderer.
pub struct ViewportPoint {
pub mut:
	// The x/y position within the viewport.
	x u16
	y u16

	// Whether the cursor is part of a wide character and
	// on the tail of it. If so, some renderers may use this
	// to move the cursor back one.
	wide_tail bool
}

// A row within the viewport.
pub struct RenderRow {
pub mut:
	// The page pin. This is not safe to read unless you can guarantee
	// the terminal state hasn't changed since the last `update` call.
	pin Pin

	// Raw row data.
	raw RowData

	// The cells in this row.
	cells []RenderCell

	// A dirty flag that can be used by the renderer to track
	// its own draw state. `update` will mark this true whenever
	// this row is changed, too.
	dirty bool

	// The x range of the selection within this row.
	selection ?[2]u16

	// The highlights within this row.
	highlights []RenderHighlight
}

// A highlight within a row.
pub struct RenderHighlight {
pub:
	// A special tag that can be used by the caller to differentiate
	// different highlight types. The value is opaque to the RenderState.
	tag u8

	// The x ranges of highlights within this row.
	range [2]u16
}

// Flattened highlight data accepted by RenderState. This mirrors
// highlight.Flattened without importing the highlight module back
// into terminal (which would create a module cycle).
pub struct RenderHighlightChunk {
pub:
	node   &PageNode = unsafe { nil }
	serial u64
	start  u16
	end    u16
}

pub struct RenderFlattenedHighlight {
pub:
	chunks []RenderHighlightChunk
	top_x  u16
	bot_x  u16
}

// A cell within a rendered row.
pub struct RenderCell {
pub mut:
	// Always set, this is the raw copied cell data from CellData.
	// The managed memory (hyperlinks, graphemes, etc.) is NOT safe
	// to access from here. It is duplicated into the other fields if
	// it exists.
	raw CellData

	// Grapheme data for the cell. This is undefined unless the
	// raw cell's content_tag is `codepoint_grapheme`.
	grapheme []u32

	// The style data for the cell. This is undefined unless
	// the style_id is non-default on raw.
	style CellStyle
}

const default_render_cell = RenderCell{}

// Dirty state
pub enum RenderDirty as u8 {
	// Not dirty at all. Can skip rendering if prior state was
	// already rendered.
	false_
	// Partially dirty. Some rows changed but not all. None of the
	// global state changed such as colors.
	partial
	// Fully dirty. Global state changed or dimensions changed. All rows
	// should be redrawn.
	full
}

// Cached selection data for render optimization.
struct RenderSelectionCache {
	selection Selection
	tl_pin    Pin
	br_pin    Pin
}

// Initial state.
pub fn RenderState.empty() RenderState {
	return RenderState{
		rows:     0
		cols:     0
		colors:   RenderColors{
			cursor: none
		}
		cursor:   RenderCursor{
			active:         Coordinate{}
			viewport:       none
			cell:           CellData{}
			style:          CellStyle{}
			visual_style:   .block
			password_input: false
			visible:        true
			blinking:       false
		}
		row_data: []
		dirty:    .false_
		screen:   .primary
	}
}

// Clean up render state resources.
pub fn (mut self RenderState) deinit() {
	self.row_data = []
}

// Update the render state to the latest terminal state.
//
// This will reset the terminal dirty state since it is consumed
// by this render state update.
pub fn (mut self RenderState) update(mut t Terminal) {
	mut s := t.screens.active
	viewport_pin := s.pages.get_top_left(.viewport)
	redraw := self.update_redraw(t, viewport_pin)

	// Always set our cheap fields, its more expensive to compare
	self.rows = s.pages.rows
	self.cols = s.pages.cols
	self.viewport_pin = viewport_pin
	self.cursor.active = Coordinate{
		x: u16(s.cursor.x)
		y: s.cursor.y
	}
	self.cursor.cell = *s.cursor.page_cell
	self.cursor.style = s.cursor.style
	self.cursor.visual_style = s.cursor.cursor_style
	self.cursor.password_input = t.flags.password_input()
	self.cursor.visible = t.modes.get(.cursor_visible)
	self.cursor.blinking = t.modes.get(.cursor_blinking)

	// Always reset the cursor viewport position. In the future we can
	// probably cache this by comparing the cursor pin and viewport pin
	// but may not be worth it.
	self.cursor.viewport = none

	// Colors.
	self.colors.cursor = t.colors.cursor.get()
	self.colors.palette = t.colors.palette.current
	// Background/foreground can be unset initially which would
	// depend on "default" background/foreground. The expected use
	// case of Terminal is that the caller set their own configured
	// defaults on load so this doesn't happen.
	if bg := t.colors.background.get() {
		if fg := t.colors.foreground.get() {
			if t.modes.get(.reverse_colors) {
				self.colors.background = fg
				self.colors.foreground = bg
			} else {
				self.colors.background = bg
				self.colors.foreground = fg
			}
		}
	}

	// Ensure our row length is exactly our height, freeing or allocating
	// data as necessary. In most cases we'll have a perfectly matching
	// size.
	if self.row_data.len != int(self.rows) {
		if self.row_data.len < int(self.rows) {
			// Resize our rows to the desired length, marking any added
			// values undefined.
			for _ in self.row_data.len .. int(self.rows) {
				self.row_data << RenderRow{
					dirty: true
				}
			}
		} else {
			self.row_data = self.row_data[..int(self.rows)]
		}
	}

	// Track the last page that we know was dirty. This lets us
	// more quickly do the full-page dirty check.
	mut last_dirty_page := &Page(unsafe { nil })

	// Go through and setup our rows.
	mut row_it := s.pages.row_iterator(.right_down, Point.new(.viewport, Coordinate{}), none)
	mut next_y := 0
	mut any_dirty := false
	for {
		row_pin := row_it.next() or { break }
		// Zig's `defer y += 1` is block scoped; V's defer is function
		// scoped, so advance the row index up front instead.
		y := next_y
		next_y += 1

		// Find our cursor if we haven't found it yet. We do this even
		// if the row is not dirty because the cursor is unrelated.
		if self.cursor.viewport == none && voidptr(row_pin.node) == voidptr(s.cursor.page_pin.node)
			&& row_pin.y == s.cursor.page_pin.y {
			self.cursor.viewport = ViewportPoint{
				y:         u16(y)
				x:         u16(s.cursor.x)
				// Future: we should use our own state here to look this
				// up rather than calling this.
				wide_tail: if s.cursor.x > 0 {
					s.cursor_cell_left(1).wide == .wide
				} else {
					false
				}
			}
		}

		// Store our pin. We have to store these even if we're not dirty
		// because dirty is only a renderer optimization. It doesn't
		// apply to memory movement. This will let us remap any cell
		// pins back to an exact entry in our RenderState.
		self.row_data[y].pin = row_pin

		// Get all our cells in the page.
		mut p := &row_pin.node.data
		page_rac := row_pin.row_and_cell()

		// If we're redrawing then we're definitely dirty. If our page is
		// the same as last time then its dirty. If this page is dirty then
		// clear the dirty flag of the last page and then store this one.
		// This benchmarks faster than iterating pages again later. If our
		// row is dirty then we're dirty.
		mut dirty := redraw || voidptr(p) == voidptr(last_dirty_page)
		if !dirty && p.dirty {
			if !isnil(last_dirty_page) {
				last_dirty_page.dirty = false
			}
			last_dirty_page = p
			dirty = true
		}
		if !dirty && page_rac.row.header.dirty {
			dirty = true
		}

		// Not dirty!
		if !dirty {
			continue
		}

		// Set that at least one row was dirty.
		any_dirty = true

		// Clear our row dirty, we'll clear our page dirty later.
		// We can't clear it now because we have more rows to go through.
		mut row := page_rac.row
		row.header.dirty = false

		// Reset our cells if we're rebuilding this row.
		mut rendered := &self.row_data[y]
		rendered.selection = none
		rendered.highlights = []
		rendered.dirty = true

		// Get all our cells in the page.
		page_cells := p.get_cells(row)
		assert page_cells.len == int(self.cols)

		// Copy our raw row data
		rendered.raw = row.snapshot()

		// Keep the row's storage across updates at the same width. Replacing
		// each cell also clears the old grapheme and style data.
		if rendered.cells.len != page_cells.len {
			rendered.cells = []RenderCell{len: page_cells.len, init: default_render_cell}
		}
		for x, page_cell in page_cells {
			rendered.cells[x] = default_render_cell
			rendered.cells[x].raw = page_cell
		}
		if !row.managed_memory() {
			continue
		}

		for x in 0 .. page_cells.len {
			page_cell := unsafe { &page_cells[x] }
			// Append assuming its a single-codepoint, styled cell
			// (most common by far).
			if page_cell.style_id > 0 {
				rendered.cells[x].style = p.styles.get(page_cell.style_id)
			}

			// Switch on our content tag to handle less likely cases.
			match page_cell.content_tag {
				.codepoint {
					// Primary codepoint goes into `raw` field.
				}
				// If we have a multi-codepoint grapheme, look it up and
				// set our content type.
				.codepoint_grapheme {
					rendered.cells[x].grapheme = (p.lookup_grapheme(page_cell) or { []u32{} }).clone()
				}
				.bg_color_rgb {
					rendered.cells[x].style = CellStyle{
						bg_color: StyleColorRgb{
							rgb: RGB{
								r: page_cell.color_rgb_r()
								g: page_cell.color_rgb_g()
								b: page_cell.color_rgb_b()
							}
						}
					}
				}
				.bg_color_palette {
					rendered.cells[x].style = CellStyle{
						bg_color: StyleColorPalette{ index: page_cell.color_palette() }
					}
				}
			}
		}
	}
	assert next_y == int(self.rows)

	// If our screen has a selection, then mark the rows with the
	// selection. We do this outside of the loop above because its unlikely
	// a selection exists and because the way our selections are structured
	// today is very inefficient.
	//
	// NOTE: To improve the performance of the block below, we'll need
	// to rethink how we model selections in general.
	//
	// There are performance improvements that can be made here, though.
	// For example, `containedRow` recalculates a bunch of information
	// we can cache.
	if sel := s.selection {
		any_dirty = self.update_selection(s, sel, redraw, any_dirty)
	}

	// Handle dirty state.
	if redraw {
		// Fully redraw resets some other state.
		self.screen = t.screens.active_key
		self.dirty = .full

		// Note: we don't clear any row_data here because our rebuild
		// above did this.
	} else if any_dirty && self.dirty == .false_ {
		self.dirty = .partial
	}

	// Finalize our final dirty page
	if !isnil(last_dirty_page) {
		last_dirty_page.dirty = false
	}

	// Clear our dirty flags
	t.flags.set_dirty(Dirty{})
	s.dirty = ScreenDirty{}
}

// The `redraw:` block of RenderState.update.
fn (self &RenderState) update_redraw(t &Terminal, viewport_pin Pin) bool {
	s := t.screens.active

	// If our screen key changed, we need to do a full rebuild
	// because our render state is viewport-specific.
	if t.screens.active_key != self.screen {
		return true
	}

	// If our terminal is dirty at all, we do a full rebuild. These
	// dirty values are full-terminal dirty values.
	if t.flags.dirty().int() > 0 {
		return true
	}

	// If our screen is dirty at all, we do a full rebuild. This is
	// a full screen dirty tracker.
	if s.dirty.int() > 0 {
		return true
	}

	// If our dimensions changed, we do a full rebuild.
	if self.rows != s.pages.rows || self.cols != s.pages.cols {
		return true
	}

	// If our viewport pin changed, we do a full rebuild.
	if old := self.viewport_pin {
		if !old.eql(viewport_pin) {
			return true
		}
	}

	return false
}

// The `selection:` block of RenderState.update.
fn (mut self RenderState) update_selection(s &Screen, sel Selection, redraw bool, any_dirty bool) bool {
	// Populate our selection cache to avoid some expensive
	// recalculation.
	mut cache := RenderSelectionCache{}
	mut cached := false
	if c := self.selection_cache {
		// If we're redrawing, we recalculate the cache just to
		// be safe.
		//
		// If our selection isn't equal, we aren't cached!
		if !redraw && c.selection.eql(sel) {
			// If we have no dirty rows, we can not recalculate.
			if !any_dirty {
				return false
			}

			// We have dirty rows, we can utilize the cache.
			cache = c
			cached = true
		}
	}
	if !cached {
		// Create a new cache
		tl_pin := sel.top_left(s)
		br_pin := sel.bottom_right(s)
		cache = RenderSelectionCache{
			selection: Selection.init(tl_pin, br_pin, sel.rectangle)
			tl_pin:    tl_pin
			br_pin:    br_pin
		}
		self.selection_cache = cache
	}

	// Grab the inefficient data we need from the selection. At
	// least we can cache it.
	tl := (s.pages.point_from_pin(.screen, cache.tl_pin) or { panic('selection top-left is off screen') }).coord()
	// A spacer at the right edge precedes a wide glyph on the next row.
	// Resolve it on each update because text may change under the selection.
	br_pin := if !sel.rectangle && cache.br_pin.row_and_cell().cell.wide == .spacer_head {
		cache.br_pin.right_wrap(1) or { cache.br_pin }
	} else {
		cache.br_pin
	}
	br := (s.pages.point_from_pin(.screen, br_pin) or { panic('selection bottom-right is off screen') }).coord()

	// We need to determine if our selection is within the viewport.
	// The viewport is generally very small so the efficient way to
	// do this is to traverse the viewport pages and check for the
	// matching selection pages.
	mut selection_dirty := false
	for mut row in self.row_data {
		pin := row.pin
		p := (s.pages.point_from_pin(.screen, pin) or { panic('render row pin is off screen') }).coord()
		mut bounds := ?[2]u16(none)
		if row_sel := sel.contained_row_cached(s, cache.tl_pin, br_pin, pin, tl, br, p) {
			start := row_sel.start()
			end := row_sel.end()
			assert voidptr(start.node) == voidptr(end.node)
			assert start.x <= end.x
			assert start.y == end.y
			// Include the glyph when the selection starts on its second cell.
			start_x := if start.x > 0 && start.row_and_cell().cell.wide == .spacer_tail {
				start.x - 1
			} else {
				start.x
			}
			bounds = [start_x, end.x]!
		}
		if bounds != row.selection {
			row.selection = bounds
			row.dirty = true
			selection_dirty = true
		}
	}
	return any_dirty || selection_dirty
}

// Update the highlights in the render state from the given flattened
// highlights. Because this uses flattened highlights, it does not require
// reading from the terminal state so it should be done outside of
// any critical sections.
//
// This will not clear any previous highlights, so the caller must
// manually clear them if desired.
pub fn (mut self RenderState) update_highlights_flattened(tag u8, hls []RenderFlattenedHighlight) {
	// Fast path, we have no highlights!
	if hls.len == 0 {
		return
	}

	// This is, admittedly, horrendous. This is some low hanging fruit
	// to optimize. In my defense, screens are usually small, the number
	// of highlights is usually small, and this only happens on the
	// viewport outside of a locked area. Still, I'd love to see this
	// improved someday.

	// We need to track whether any row had a match so we can mark
	// the dirty state.
	mut any_dirty := false

	for mut row in self.row_data {
		row_pin := row.pin
		for hl in hls {
			for i, chunk in hl.chunks {
				// If this node doesn't match or we're not within
				// the row range, skip it.
				if voidptr(chunk.node) != voidptr(row_pin.node) || row_pin.y < chunk.start
					|| row_pin.y >= chunk.end {
					continue
				}

				// We're a match!
				row.highlights << RenderHighlight{
					tag:   tag
					range: [
						if i == 0 && row_pin.y == hl.chunks[0].start { hl.top_x } else { u16(0) },
						if i == hl.chunks.len - 1 && row_pin.y == hl.chunks[hl.chunks.len - 1].end - 1 {
							hl.bot_x
						} else {
							self.cols - 1
						},
					]!
				}

				row.dirty = true
				any_dirty = true
			}
		}
	}

	// Mark our dirty state.
	if any_dirty && self.dirty == .false_ {
		self.dirty = .partial
	}
}

// A set of coordinates representing cells.
pub type CellSet = map[u64]bool

// Helper to make a coordinate key for CellSet.
fn cell_set_key(x u32, y u32) u64 {
	return u64(y) << 32 | u64(x)
}

// Returns a map of the cells that match to an OSC8 hyperlink over the
// given point in the render state.
//
// IMPORTANT: The terminal must not have updated since the last call to
// `update`. If there is any chance the terminal has updated, the caller
// must first call `update` again to refresh the render state.
//
// For example, you may want to hold a lock for the duration of the
// update and hyperlink lookup to ensure no updates happen in between.
pub fn (self &RenderState) link_cells(viewport_point Coordinate) CellSet {
	mut result := CellSet{}

	// Our viewport point is sent in by the caller and can't be trusted.
	// If it is outside the valid area then just return empty because
	// we can't possibly have a link there.
	if viewport_point.x >= self.cols || viewport_point.y >= u32(self.row_data.len) {
		return result
	}

	// Grab our link ID
	link_pin := self.row_data[int(viewport_point.y)].pin
	mut link_page := &link_pin.node.data
	rac := link_page.get_row_and_cell(uint(viewport_point.x), uint(link_pin.y))

	// The likely scenario is that our mouse isn't even over a link.
	if !rac.cell.has_hyperlink {
		return result
	}

	link_id := link_page.lookup_hyperlink(rac.cell) or { return result }
	link := link_page.hyperlink_set.get(link_id)

	for y, row in self.row_data {
		pin := row.pin
		for x, cell in row.cells {
			if !cell.raw.has_hyperlink {
				continue
			}

			mut other_page := &pin.node.data
			other_rac := other_page.get_row_and_cell(uint(x), uint(pin.y))
			other_id := other_page.lookup_hyperlink(other_rac.cell) or { continue }
			other := other_page.hyperlink_set.get(other_id)

			if link.eql(&other) {
				result[cell_set_key(u32(x), u32(y))] = true
			}
		}
	}

	return result
}

// RenderStringMap maps every byte written by RenderState.string to the
// viewport coordinate that produced it. Ghostty declares this as the nested
// RenderState.StringMap type; V does not support nested type declarations.
pub struct RenderStringMap {
pub mut:
	points []Coordinate
}

// RenderStringOptions contains the optional byte map populated by string.
// The struct preserves Ghostty's optional map argument while V's strings.Builder
// replaces Zig's generic fallible writer.
pub struct RenderStringOptions {
pub:
	map &RenderStringMap = unsafe { nil }
}

// Convert the current render state contents to a UTF-8 encoded string written
// to the given builder. This will unwrap all the wrapped rows. This is useful
// for a minimal viewport search.
//
// This currently writes empty cell contents as \x00 and writes all
// blank lines. This is fine for our current usage (link search) but
// we can adjust this later.
//
// NOTE: There is a limitation in that wrapped lines before/after the
// top/bottom line of the viewport are not included, since the render state
// cuts them off.
pub fn (self &RenderState) string(mut writer strings.Builder, options ?RenderStringOptions) {
	string_map := if opts := options { opts.map } else { &RenderStringMap(unsafe { nil }) }
	for y, row in self.row_data {
		for x, cell in row.cells {
			cp := cell.raw.codepoint()
			before := writer.len
			if cp == 0 {
				writer.write_u8(0) // null byte for empty cells
			} else {
				write_utf8(mut writer, cp)
				if cell.raw.has_grapheme() {
					for grapheme_cp in cell.grapheme {
						write_utf8(mut writer, grapheme_cp)
					}
				}
			}
			if string_map != unsafe { nil } {
				unsafe {
					for _ in before .. writer.len {
						string_map.points << Coordinate{ x: u16(x), y: u32(y) }
					}
				}
			}
		}
		if !row.raw.header.wrap {
			writer.write_u8(u8(`\n`))
			if string_map != unsafe { nil } {
				unsafe {
					string_map.points << Coordinate{ x: u16(row.cells.len), y: u32(y) }
				}
			}
		}
	}
}
