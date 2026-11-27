module font

// --- Original Ghostty Comments Start: src/font/Atlas.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/font/Atlas.zig
//
// Implements a texture atlas (https://en.wikipedia.org/wiki/Texture_atlas).
//
// The implementation is based on "A Thousand Ways to Pack the Bin - A
// Practical Approach to Two-Dimensional Rectangle Bin Packing" by Jukka
// Jylänki. This specific implementation is based heavily on
// Nicolas P. Rougier's freetype-gl project as well as Jukka's C++
// implementation: https://github.com/juj/RectangleBinPack
//
// Limitations that are easy to fix, but I didn't need them:
//
//   * Written data must be packed, no support for custom strides.
//   * Texture is always a square, no ability to set width != height. Note
//     that regions written INTO the atlas do not have to be square, only
//     the full atlas texture itself.
//
// Data is the raw texture data.
// Width and height of the atlas texture. The current implementation is
// always square so this is both the width and the height.
// The nodes (rectangles) of available space.
// The format of the texture data being written into the Atlas. This must be
// uniform for all textures in the Atlas. If you have some textures with
// different formats, you must use multiple atlases or convert the textures.
// This will be incremented every time the atlas is modified. This is useful
// for knowing if the texture data has changed since the last time it was
// sent to the GPU. It is up the user of the atlas to read this value atomically
// to observe it.
// This will be incremented every time the atlas is resized. This is useful
// for knowing if a GPU texture can be updated in-place or if it requires
// a resize operation.
// 1 byte per pixel grayscale.
// 3 bytes per pixel BGR.
// 4 bytes per pixel BGRA.
// Atlas cannot fit the desired region. You must enlarge the atlas.
// A region within the texture atlas. These can be acquired using the
// "reserve" function. A region reservation is required to write data.
// Number of nodes to preallocate in the list on init.
//
// TODO: figure out optimal prealloc based on real world usage
// Prealloc some nodes.
// This sets up our initial state
// Reserve a region within the atlas with the given width and height.
//
// May allocate to add a new rectangle into the internal list of rectangles.
// This will not automatically enlarge the texture if it is full.
// x, y are populated within :best_idx below
// If our width/height are 0, then we return the region as-is. This
// may seem like an error case but it simplifies downstream callers who
// might be trying to write empty data.
// Find the location in our nodes list to insert the new node for this region.
// Check if our region fits within this node.
// If we never found a chosen index, the atlas cannot fit our region.
// Insert our new node for this rectangle at the exact best index
// Optimize our rectangles
// Attempts to fit a rectangle of width x height into the node at idx.
// The return value is the y within the texture where the rectangle can be
// placed. The x is the same as the node.
// If the added width exceeds our texture size, it doesn't fit.
// Go node by node looking for space that can fit our width.
// If the added height exceeds our texture size, it doesn't fit.
// Merge adjacent nodes with the same y value.
// Set the data associated with a reserved region. The data is expected
// to fit exactly within the region. The data must be formatted with the
// proper bpp configured on init.
// Like `set` but allows specifying a width for the source data and an
// offset x and y, so that a section of a larger buffer may be copied
// in to the atlas.
// Grow the texture to the new size, preserving all previously written data.
// We reserve space ahead of time for the new node, so that we
// won't have to handle any errors after allocating our new data.
// Function is infallible from this point.
// Keep track of our old data so that we can copy it.
// Update our data and size to our new ones.
// Free the old data once we're done with it.
// Zero the new data out and copy the old data over.
// Add the new rectangle for our added righthand space.
// We are both modified and resized
// Empty the atlas. This doesn't reclaim any previously allocated memory.
// Add our initial rectangle. This is the size of the full texture
// and is the initial rectangle we fit our regions in. We keep a 1px border
// to avoid artifacting when sampling the texture.
// Dump the atlas as a PPM to a writer, for debug purposes.
// Only supports grayscale and bgr atlases.
//
// NOTE: BGR atlases will have the red and blue channels
//       swapped because PPM expects RGB. This would be
//       easy enough to fix so next time someone needs
//       to debug a color atlas they should fix it.
// The wasm-compatible API. This lacks documentation unless the API differs
// from the standard Zig API. To learn what a function does, just look one
// level deeper to what Zig function is called and read the documentation there.
// If you're copying this file (Atlas.zig) out to a separate project,
// just replace this with the allocator you want to use.
// The return value for this should be freed by the caller with "free".
// This creates a Canvas element identified by the id returned that
// the caller can draw into the DOM to visualize the atlas. The returned
// ID must be freed from the JS runtime by calling "zigjs.deleteValue".
// Create our canvas
// Setup our canvas size
// This will return the same context on subsequent calls so it
// is important to reset it.
// We need to draw pixels so this is format dependent.
// Convert from BGRA to RGBA by swapping every R and B.
// Convert from A8 to RGBA so every 4th byte is set to a value.
// Create an ImageData from our buffer and then write it to the canvas
// Get our runtime memory
// Create an array that points to our buffer
// If we're sharing memory then we have to copy the data since
// we can't set ImageData directly using a SharedArrayBuffer.
// Create the image data from our array
// Draw it
// doesn't fit due to border
// 33 because of the 1px border and so on
// zig fmt: off
// zig fmt: on
// 33 because of the 1px border and so on
// None of the `8`s from the source data outside of the
// specified region should have made it on to the atlas.
// Write some data so we can verify that growing doesn't mess it up
// Expand by exactly 1 should fit our new 1x1 block.
// Ensure our data is still set. Not the offsets change due to size.
// This is BGR so its 3 bpp
// 33 because of the 1px border and so on
// Atlas is 4x4 so its a 1px border meaning we only have 2x2 available
// Get our 2x2, which should be ALL our usable space
// This is BGR so its 3 bpp
// Our top left skips the first row (size * depth) and the first
// column (depth) for the 1px border.
// Expand by exactly 1 should fit our new 1x1 block.
// Data should be in same place accounting for the new size
// Should fit the new blocks around the edges
// We use a fixed buffer allocator so that we can consistently hit OOM.
//
// We calculate the size to exactly fit the 4x4 pixels and node list.
// Write some data so we can verify that attempted growing doesn't mess it up.
// Expand by 1, should give OOM, modified and resized should be unchanged.
// Ensure our data is still set.
// Test every failure point in `init` and ensure that we don't
// leak memory (testing.allocator verifies) since we're exiting early.
// Test every failure point in `reserve` and ensure that we don't
// leak memory (testing.allocator verifies) since we're exiting early.
// Test every failure point in `grow` and ensure that we don't
// leak memory (testing.allocator verifies) since we're exiting early.
// Write some data to verify it's preserved after failed grow
// Verify atlas state is unchanged after failed grow
//
// --- Original Ghostty Comments End: src/font/Atlas.zig

// --- Original Ghostty Comments Start: src/font/Metrics.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/font/Metrics.zig
//
// Recommended cell width and height for a monospace grid using this font.
// Distance in pixels from the bottom of the cell to the text baseline.
// Distance in pixels from the top of the cell to the top of the underline.
// Thickness in pixels of the underline.
// Distance in pixels from the top of the cell to the top of the strikethrough.
// Thickness in pixels of the strikethrough.
// Distance in pixels from the top of the cell to the top of the overline.
// Can be negative to adjust the position above the top of the cell.
// Thickness in pixels of the overline.
// Thickness in pixels of box drawing characters.
// The thickness in pixels of the cursor sprite. This has a default value
// because it is not determined by fonts but rather by user configuration.
// The height in pixels of the cursor sprite.
// The constraint height for nerd fonts icons.
// The constraint height for nerd fonts icons limited to a single cell width.
// The unrounded face width, used in scaling calculations.
// The unrounded face height, used in scaling calculations.
// The offset from the bottom of the cell to the bottom
// of the face's bounding box, based on the rounded and
// potentially adjusted cell height.
// Minimum acceptable values for some fields to prevent modifiers
// from being able to, for example, cause 0-thickness underlines.
// Metrics extracted from a font face, based on
// the metadata tables and glyph measurements.
// Pixels per em, dividing the other values in this struct by this should
// yield sizes in ems, to allow comparing metrics from faces of different
// sizes.
// The minimum cell width that can contain any glyph in the ASCII range.
//
// Determined by measuring all printable glyphs in the ASCII range.
// The typographic ascent metric from the font.
// This represents the maximum vertical position of the highest ascender.
//
// Relative to the baseline, in px, +Y=up
// The typographic descent metric from the font.
// This represents the minimum vertical position of the lowest descender.
//
// Relative to the baseline, in px, +Y=up
//
// Note:
// As this value is generally below the baseline, it is typically negative.
// The typographic line gap (aka "leading") metric from the font.
// This represents the additional space to be added between lines in
// addition to the space defined by the ascent and descent metrics.
//
// Positive value in px
// The TOP of the underline stroke.
//
// Relative to the baseline, in px, +Y=up
// The thickness of the underline stroke in px.
// The TOP of the strikethrough stroke.
//
// Relative to the baseline, in px, +Y=up
// The thickness of the strikethrough stroke in px.
// The height of capital letters in the font, either derived from
// a provided cap height metric or measured from the height of the
// capital H glyph.
// The height of lowercase letters in the font, either derived from
// a provided ex height metric or measured from the height of the
// lowercase x glyph.
// The measured height of the bounding box containing all printable
// ASCII characters. This can be different from ascent - descent for
// two reasons: non-letter symbols like @ and $ often exceed the
// the ascender and descender lines; and fonts often bake the line
// gap into the ascent and descent metrics (as per, e.g., the Google
// Fonts guidelines: https://simoncozens.github.io/gf-docs/metrics.html).
//
// Positive value in px
// The width of the character "水" (CJK water ideograph, U+6C34),
// if present. This is used for font size adjustment, to normalize
// the width of CJK fonts mixed with latin fonts.
//
// NOTE: IC = Ideograph Character
// Convenience function for getting the line height
// (ascent - descent + line_gap).
// Convenience function for getting the cap height. If this is not
// defined in the font, we estimate it as 75% of the ascent.
// Convenience function for getting the ex height. If this is not
// defined in the font, we estimate it as 75% of the cap height.
// Convenience function for getting the ASCII height. If we
// couldn't measure this, we use 1.5 * cap_height as our
// estimator, based on measurements across programming fonts.
// Convenience function for getting the ideograph width. If this is
// not defined in the font, we estimate it as the minimum of the
// ascii height and two cell widths.
// Convenience function for getting the underline thickness. If
// this is not defined in the font, we estimate it as 15% of the ex
// height.
// Convenience function for getting the strikethrough thickness. If
// this is not defined in the font, we set it equal to the
// underline thickness.
// NOTE: The getters below return positions, not sizes, so both
// positive and negative values are valid, hence no sign validation.
// Convenience function for getting the underline position. If
// this is not defined in the font, we place it one underline
// thickness below the baseline.
// Convenience function for getting the strikethrough position. If
// this is not defined in the font, we center it at half the ex
// height, so that it's perfectly centered on lower case text.
// Calculate our metrics based on values extracted from a font.
//
// Try to pass values with as much precision as possible,
// do not round them before using them for this function.
//
// For any nullable options that are not provided, estimates will be used.
// These are the unrounded advance width and line height values,
// which are retained separately from the rounded cell width and
// height values (below), for calculations that need to know how
// much error there is between the design dimensions of the font
// and the pixel dimensions of our cells.
// The cell width and height values need to be integers since they
// represent pixel dimensions of the grid cells in the terminal.
//
// We use @round for the cell width to limit the difference from
// the "true" width value to no more than 0.5px. This is a better
// approximation of the authorial intent of the font than ceiling
// would be, and makes the apparent spacing match better between
// low and high DPI displays.
//
// This does mean that it's possible for a glyph to overflow the
// edge of the cell by a pixel if it has no side bearings, but in
// reality such glyphs are generally meant to connect to adjacent
// glyphs in some way so it's not really an issue.
//
// The same is true for the height. Some fonts are poorly authored
// and have a descender on a normal glyph that extends right up to
// the descent value of the face, and this can result in the glyph
// overflowing the bottom of the cell by a pixel, which isn't good
// but if we try to prevent it by increasing the cell height then
// we get line heights that are too large for most users and even
// more inconsistent across DPIs.
//
// Users who experience such cell-height overflows should:
//
// 1. Nag the font author to either redesign the glyph to not go
//    so low, or else adjust the descent value in the metadata.
//
// 2. Add an `adjust-cell-height` entry to their config to give
//    the cell enough room for the glyph.
// We split our line gap in two parts, and put half of it on the top
// of the cell and the other half on the bottom, so that our text never
// bumps up against either edge of the cell vertically.
// NOTE: Unlike all our other metrics, `cell_baseline` is
// relative to the BOTTOM of the cell rather than the top.
// We calculate the baseline by trying to center the face vertically
// in the pixel-rounded cell height, so that before rounding it will
// be an even distance from the top and bottom of the cell, meaning
// it either sticks out the same amount or is inset the same amount,
// depending on whether the cell height was rounded up or down from
// the line height. We do this by adding half the difference between
// the cell height and the face height.
// We keep track of the offset from the bottom of the cell
// to the bottom of the face's "true" bounding box, which at
// this point, since nothing has been scaled yet, is equivalent
// to the offset between the baseline we draw at (cell_baseline)
// and the one the font wants (face_baseline).
// We calculate a top_to_baseline to make following calculations simpler.
// Get the other font metrics or their estimates. See doc comments
// in FaceMetrics for explanations of the estimation heuristics.
// Same heuristic as the font_patcher script. We store icon_height
// separately from face_height such that modifiers can apply to the former
// without affecting the latter.
// Ensure all metrics are within their allowable range.
// std.log.debug("metrics={}", .{result});
// Apply a set of modifiers.
// We clamp these values to a minimum of 1 to prevent divide-by-zero
// in downstream operations.
// Compute the new value. If it is the same avoid the work.
// Set the new value
// For cell height, we have to also modify some positions
// that are absolute from the top of the cell. The main goal
// here is to center the baseline so that text is vertically
// centered in the cell.
// If the diff is even, the number of pixels we add
// will be the same for the top and the bottom, but
// if the diff is odd then we want to add the extra
// pixel to the edge of the cell that needs it most.
//
// How much the edge "needs it" depends on whether
// the face is higher or lower than it should be to
// be perfectly centered in the cell.
//
// If the face were perfectly centered then face_y
// would be equal to half of the difference between
// the cell height and the face height.
// The baseline is higher than it should be, so we
// add the extra to the top, or if it's a negative
// diff it gets added to the bottom because of how
// floor and ceil work.
// The baseline is lower than it should be, so we
// add the extra to the bottom, or vice versa for
// negative diffs.
// The cell baseline and face_y values are relative to the
// bottom of the cell so we add the bottom diff to them.
// These are all relative to the top of the cell.
// Prevent modifiers from pushing metrics out of their allowable range.
// Helper function for adding an f64 to a u32.
//
// Performs saturating addition or subtraction
// depending on the sign of the provided float.
//
// The f64 is asserted to have an integer value.
// Clamp all metrics to their allowable range.
// A set of modifiers to apply to metrics. We use a hash map because
// we expect most metrics to be unmodified and want to take up as
// little space as possible.
// A modifier to apply to a metrics value. The modifier value represents
// a delta, so percent is a percentage to change, not a percentage of.
// For example, "20%" is 20% larger, not 20% of the value. Likewise,
// an absolute value of "20" is 20 larger, not literally 20.
// Parses the modifier value. If the value ends in "%" it is assumed
// to be a percent, otherwise the value is parsed as an integer.
// So it works with the config framework.
// Used by config formatter
// Apply a modifier to a numeric value.
// Hash using the hasher.
// floats can't be hashed directly so we bitcast to i64.
// for the purpose of what we're trying to do this seems
// good enough but I would prefer value hashing.
// Key is an enum of all the available metrics keys.
// NOTE: This is purposely not pub because we want to force outside callers
// to use the `.{}` syntax so unused fields are detected by the compiler.
// We choose numbers such that the subtracted number of pixels is odd,
// as that's the case that could most easily have off-by-one errors.
// Here we're removing 25 pixels: 13 on the bottom, 12 on top, split
// that way because we're simulating a face that's 0.33px higher than
// it "should" be (due to rounding).
// Cursor height is separate from cell height and does not follow it.
// We choose numbers such that the added number of pixels is odd,
// as that's the case that could most easily have off-by-one errors.
// Here we're adding 75 pixels: 37 on the bottom, 38 on top, split
// that way because we're simulating a face that's 0.33px higher
// than it "should" be (due to rounding).
// Cursor height is separate from cell height and does not follow it.
// Face metrics not affected
// Face metrics not affected
//
// --- Original Ghostty Comments End: src/font/Metrics.zig

import datastruct
import fastmem
import font.feature as feature_parser
import harfbuzz
import io
import math
import sprite_types
import sync.stdatomic
import terminal
import tripwire

// Default DPI for the platform. Fontconfig environments conventionally use
// 96 DPI while CoreText uses 72 DPI, matching font.face.default_dpi.
pub const default_dpi = $if macos { u16(72) } $else { u16(96) }

// Packed Collection.Index reserved for built-in sprites.
pub const sprite_index = Index{ value: u16(8191 << 3) }

// ============================================================
// Metrics
// ============================================================

// Metrics holds font measurement data for the grid.
pub struct Metrics {
pub mut:
	// Recommended cell width and height for a monospace grid using this font.
	cell_width  u32
	cell_height u32
	// Distance in pixels from the bottom of the cell to the text baseline.
	cell_baseline u32
	// Distance in pixels from the top of the cell to the top of the underline.
	underline_position u32
	// Thickness in pixels of the underline.
	underline_thickness u32
	// Distance in pixels from the top of the cell to the top of the strikethrough.
	strikethrough_position u32
	// Thickness in pixels of the strikethrough.
	strikethrough_thickness u32
	// Distance in pixels from the top of the cell to the top of the overline.
	// Can be negative to adjust the position above the top of the cell.
	overline_position i32
	// Thickness in pixels of the overline.
	overline_thickness u32
	// Thickness in pixels of box drawing characters.
	box_thickness u32
	// The thickness in pixels of the cursor sprite. This has a default value
	// because it is not determined by fonts but rather by user configuration.
	cursor_thickness u32 = 1
	// The height in pixels of the cursor sprite.
	cursor_height u32
	// The constraint height for nerd fonts icons.
	icon_height f64
	// The constraint height for nerd fonts icons limited to a single cell width.
	icon_height_single f64
	// The unrounded face width, used in scaling calculations.
	face_width f64
	// The unrounded face height, used in scaling calculations.
	face_height f64
	// The offset from the bottom of the cell to the bottom of the face's
	// bounding box, based on the rounded and potentially adjusted cell height.
	face_y f64
}

// Minimum acceptable values for some fields to prevent modifiers
// from being able to, for example, cause 0-thickness underlines.
const metrics_min_cell_width = u32(1)
const metrics_min_cell_height = u32(1)
const metrics_min_underline_thickness = u32(1)
const metrics_min_strikethrough_thickness = u32(1)
const metrics_min_overline_thickness = u32(1)
const metrics_min_box_thickness = u32(1)
const metrics_min_cursor_thickness = u32(1)
const metrics_min_cursor_height = u32(1)
const metrics_min_icon_height = f64(1.0)
const metrics_min_icon_height_single = f64(1.0)
const metrics_min_face_height = f64(1.0)
const metrics_min_face_width = f64(1.0)

// default_grid_metrics returns a simple Metrics value with the given cell
// width and height, used as a convenience for tests and callers that need a
// grid without a real font face. The icon height is set to the cell height.
pub fn default_grid_metrics(cell_width u32, cell_height u32) Metrics {
	return Metrics{
		cell_width:              cell_width
		cell_height:             cell_height
		cell_baseline:           0
		underline_position:      cell_height
		underline_thickness:     2
		strikethrough_position:  cell_height / 2
		strikethrough_thickness: 1
		overline_position:       0
		overline_thickness:      1
		box_thickness:           1
		cursor_thickness:        1
		cursor_height:           cell_height
		icon_height:             f64(cell_height)
		icon_height_single:      f64(cell_height)
		face_width:              f64(cell_width)
		face_height:             f64(cell_height)
		face_y:                  0.0
	}
}

// calc computes grid Metrics from face-level FaceMetrics.
//
// Try to pass values with as much precision as possible,
// do not round them before using them for this function.
//
// For any nullable options that are not provided, estimates will be used.
pub fn Metrics.calc(face FaceMetrics) Metrics {
	// These are the unrounded advance width and line height values,
	// which are retained separately from the rounded cell width and
	// height values (below), for calculations that need to know how
	// much error there is between the design dimensions of the font
	// and the pixel dimensions of our cells.
	face_width := face.cell_width
	face_height := face.line_height()

	// The cell width and height values need to be integers since they
	// represent pixel dimensions of the grid cells in the terminal.
	//
	// We use round for the cell width to limit the difference from the
	// "true" width value to no more than 0.5px. See ghostty Metrics.zig
	// for the full rationale on rounding vs. ceiling.
	cell_width := math.round(face_width)
	cell_height := math.round(face_height)

	// We split our line gap in two parts, and put half of it on the top
	// of the cell and the other half on the bottom, so that our text never
	// bumps up against either edge of the cell vertically.
	half_line_gap := face.line_gap / 2

	// NOTE: Unlike all our other metrics, cell_baseline is relative to the
	// BOTTOM of the cell rather than the top.
	face_baseline := half_line_gap - face.descent
	// We calculate the baseline by trying to center the face vertically
	// in the pixel-rounded cell height, so that before rounding it will
	// be an even distance from the top and bottom of the cell. We do this
	// by adding half the difference between the cell height and the face
	// height.
	cell_baseline := math.round(face_baseline - (cell_height - face_height) / 2)

	// We keep track of the offset from the bottom of the cell to the bottom
	// of the face's "true" bounding box, which at this point, since nothing
	// has been scaled yet, is equivalent to the offset between the baseline
	// we draw at (cell_baseline) and the one the font wants (face_baseline).
	face_y := cell_baseline - face_baseline

	// We calculate a top_to_baseline to make following calculations simpler.
	top_to_baseline := cell_height - cell_baseline

	// Get the other font metrics or their estimates. See doc comments
	// in FaceMetrics for explanations of the estimation heuristics.
	cap_height := face.cap_height()
	underline_thickness := math.max(1.0, math.ceil(face.underline_thickness()))
	strikethrough_thickness := math.max(1.0, math.ceil(face.strikethrough_thickness()))
	underline_position := math.round(top_to_baseline - face.underline_position())
	strikethrough_position := math.round(top_to_baseline - face.strikethrough_position())

	// Same heuristic as the font_patcher script. We store icon_height
	// separately from face_height such that modifiers can apply to the former
	// without affecting the latter.
	icon_height := face_height
	icon_height_single := (2 * cap_height + face_height) / 3

	mut result := Metrics{
		cell_width:              u32(cell_width)
		cell_height:             u32(cell_height)
		cell_baseline:           u32(cell_baseline)
		underline_position:      u32(underline_position)
		underline_thickness:     u32(underline_thickness)
		strikethrough_position:  u32(strikethrough_position)
		strikethrough_thickness: u32(strikethrough_thickness)
		overline_position:       0
		overline_thickness:      u32(underline_thickness)
		box_thickness:           u32(underline_thickness)
		cursor_thickness:        1
		cursor_height:           u32(cell_height)
		icon_height:             icon_height
		icon_height_single:      icon_height_single
		face_width:              face_width
		face_height:             face_height
		face_y:                  face_y
	}

	// Ensure all metrics are within their allowable range.
	result.clamp()

	return result
}

// apply applies a set of modifiers.
pub fn (mut m Metrics) apply(mods MetricsModifierSet) {
	// cell_width and cell_height are handled specially (clamped and,
	// for height, cause baseline re-centering).
	if mod := mods.get(.cell_width) {
		// We clamp these values to a minimum of 1 to prevent
		// divide-by-zero in downstream operations.
		original := m.cell_width
		new := math_max_u32(mod.apply(original), 1)
		if new != original {
			m.cell_width = new
		}
	}

	if mod := mods.get(.cell_height) {
		original := m.cell_height
		new := math_max_u32(mod.apply(original), 1)
		if new != original {
			// Set the new value.
			m.cell_height = new

			// For cell height, we have to also modify some positions that
			// are absolute from the top of the cell. The main goal here is
			// to center the baseline so that text is vertically centered in
			// the cell.
			original_f64 := f64(original)
			new_f64 := f64(new)
			diff := new_f64 - original_f64
			half_diff := diff / 2.0

			// If the diff is even, the number of pixels we add will be the
			// same for the top and bottom, but if the diff is odd then we
			// want to add the extra pixel to the edge of the cell that needs
			// it most. See ghostty Metrics.zig for the full explanation.
			position_with_respect_to_center := m.face_y - (original_f64 - m.face_height) / 2

			mut diff_top := f64(0)
			mut diff_bottom := f64(0)
			if position_with_respect_to_center > 0 {
				// The baseline is higher than it should be, so we add the
				// extra to the top (or to the bottom for negative diffs due
				// to how floor and ceil work).
				diff_top = math.ceil(half_diff)
				diff_bottom = math.floor(half_diff)
			} else {
				// The baseline is lower than it should be, so we add the
				// extra to the bottom, or vice versa for negative diffs.
				diff_top = math.floor(half_diff)
				diff_bottom = math.ceil(half_diff)
			}

			// The cell baseline and face_y values are relative to the
			// bottom of the cell so we add the bottom diff to them.
			add_float_to_int(mut &m.cell_baseline, diff_bottom)
			m.face_y += diff_bottom

			// These are all relative to the top of the cell.
			add_float_to_int(mut &m.underline_position, diff_top)
			add_float_to_int(mut &m.strikethrough_position, diff_top)
			m.overline_position = saturating_add_i32(m.overline_position, i32(diff_top))
		}
	}

	// icon_height modifies both icon_height and icon_height_single.
	if mod := mods.get(.icon_height) {
		m.icon_height = mod.apply(m.icon_height)
		m.icon_height_single = mod.apply(m.icon_height_single)
	}

	// All remaining keys apply straightforwardly to their matching field.
	if mod := mods.get(.cell_baseline) {
		m.cell_baseline = mod.apply(m.cell_baseline)
	}
	if mod := mods.get(.underline_position) {
		m.underline_position = mod.apply(m.underline_position)
	}
	if mod := mods.get(.underline_thickness) {
		m.underline_thickness = mod.apply(m.underline_thickness)
	}
	if mod := mods.get(.strikethrough_position) {
		m.strikethrough_position = mod.apply(m.strikethrough_position)
	}
	if mod := mods.get(.strikethrough_thickness) {
		m.strikethrough_thickness = mod.apply(m.strikethrough_thickness)
	}
	if mod := mods.get(.overline_position) {
		m.overline_position = mod.apply(m.overline_position)
	}
	if mod := mods.get(.overline_thickness) {
		m.overline_thickness = mod.apply(m.overline_thickness)
	}
	if mod := mods.get(.box_thickness) {
		m.box_thickness = mod.apply(m.box_thickness)
	}
	if mod := mods.get(.cursor_thickness) {
		m.cursor_thickness = mod.apply(m.cursor_thickness)
	}
	if mod := mods.get(.cursor_height) {
		m.cursor_height = mod.apply(m.cursor_height)
	}

	// Prevent modifiers from pushing metrics out of their allowable range.
	m.clamp()
}

// clamp clamps all metrics to their allowable range.
fn (mut m Metrics) clamp() {
	m.cell_width = math_max_u32(m.cell_width, metrics_min_cell_width)
	m.cell_height = math_max_u32(m.cell_height, metrics_min_cell_height)
	m.underline_thickness = math_max_u32(m.underline_thickness, metrics_min_underline_thickness)
	m.strikethrough_thickness = math_max_u32(m.strikethrough_thickness, metrics_min_strikethrough_thickness)
	m.overline_thickness = math_max_u32(m.overline_thickness, metrics_min_overline_thickness)
	m.box_thickness = math_max_u32(m.box_thickness, metrics_min_box_thickness)
	m.cursor_thickness = math_max_u32(m.cursor_thickness, metrics_min_cursor_thickness)
	m.cursor_height = math_max_u32(m.cursor_height, metrics_min_cursor_height)
	if m.icon_height < metrics_min_icon_height {
		m.icon_height = metrics_min_icon_height
	}
	if m.icon_height_single < metrics_min_icon_height_single {
		m.icon_height_single = metrics_min_icon_height_single
	}
	if m.face_height < metrics_min_face_height {
		m.face_height = metrics_min_face_height
	}
	if m.face_width < metrics_min_face_width {
		m.face_width = metrics_min_face_width
	}
}

// math_max_u32 returns the larger of two u32 values.
fn math_max_u32(a u32, b u32) u32 {
	return if a > b { a } else { b }
}

// add_float_to_int performs saturating addition or subtraction of an f64
// (asserted to be integer-valued) to a u32.
fn add_float_to_int(mut value &u32, f f64) {
	assert math.floor(f) == f
	if f >= 0.0 {
		add := u32(f)
		if *value > u32(0xFFFFFFFF) - add {
			unsafe { *value = u32(0xFFFFFFFF) }
			return
		}
		unsafe { *value += add }
		return
	}
	sub := u32(-f)
	unsafe { *value = if *value > sub { *value - sub } else { u32(0) } }
}

// saturating_add_i32 adds two i32 values, saturating at the i32 bounds.
fn saturating_add_i32(a i32, b i32) i32 {
	r := i64(a) + i64(b)
	if r > i64(max_i32) {
		return max_i32
	}
	if r < i64(min_i32) {
		return min_i32
	}
	return i32(r)
}

// i32 bounds. Written as explicit i64 literals because V evaluates
// `i64(-0x80000000)` incorrectly (the unsigned hex literal is negated after
// truncation, yielding a positive value).
const max_i32 = i32(2147483647)
const min_i32 = i32(-2147483648)

// metrics_modifier_apply_u32 applies a modifier to a u32 value, matching
// the Zig Modifier.apply semantics for unsigned integers.
fn metrics_modifier_apply_u32(mod MetricsModifier, v u32) u32 {
	match mod {
		MetricsModifierPercent {
			// Percent is clamped to a minimum of 0.
			p := if mod.value > 0 { mod.value } else { f64(0) }
			applied := math.round(f64(v) * p)
			if applied <= 0 {
				return 0
			}
			if applied > f64(u32(0xFFFFFFFF)) {
				panic('integer overflow applying metrics percentage')
			}
			return u32(applied)
		}
		MetricsModifierAbsolute {
			// Absolute: saturating add, clamped to a minimum of 0 (unsigned).
			applied := i64(v) + i64(mod.value)
			if applied < 0 {
				return 0
			}
			if applied > i64(u32(0xFFFFFFFF)) {
				return u32(0xFFFFFFFF)
			}
			return u32(applied)
		}
	}
}

// metrics_modifier_apply_i32 applies a modifier to an i32 value.
fn metrics_modifier_apply_i32(mod MetricsModifier, v i32) i32 {
	match mod {
		MetricsModifierPercent {
			p := if mod.value > 0 { mod.value } else { f64(0) }
			applied := math.round(f64(v) * p)
			if applied > f64(i32(0x7FFFFFFF)) {
				panic('integer overflow applying metrics percentage')
			}
			if applied < f64(min_i32) {
				panic('integer overflow applying metrics percentage')
			}
			return i32(applied)
		}
		MetricsModifierAbsolute {
			applied := i64(v) + i64(mod.value)
			if applied > i64(max_i32) {
				return max_i32
			}
			if applied < i64(min_i32) {
				// Match `maxInt(T) * sign(clamped_i64)` in the source.
				return -max_i32
			}
			return i32(applied)
		}
	}
}

// metrics_modifier_apply_f64 applies a modifier to an f64 value.
fn metrics_modifier_apply_f64(mod MetricsModifier, v f64) f64 {
	return match mod {
		MetricsModifierPercent {
			p := if mod.value > 0 { mod.value } else { f64(0) }
			v * p
		}
		MetricsModifierAbsolute {
			v + f64(mod.value)
		}
	}
}

// ============================================================
// DesiredSize
// ============================================================

// DesiredSize represents the desired font size with DPI info.
pub struct DesiredSize {
pub mut:
	points f32
	xdpi   u16 = default_dpi
	ydpi   u16 = default_dpi
}

// pixels returns the pixel size derived from points and DPI.
pub fn (d DesiredSize) pixels() f64 {
	return f64(d.points) * f64(d.ydpi) / 72.0
}

// Note: SharedGridSet is in shared_grid_set.v
// Note: SharedGrid is in shared_grid.v

// ============================================================
// Atlas
// ============================================================

// AtlasFormat specifies the pixel format for an atlas.
pub enum AtlasFormat as u8 {
	// 1 byte per pixel grayscale.
	grayscale = 0
	// 3 bytes per pixel BGR.
	bgr       = 1
	// 4 bytes per pixel BGRA.
	bgra      = 2
}

// depth returns the number of bytes per pixel for this format.
pub fn (f AtlasFormat) depth() u8 {
	return match f {
		.grayscale { u8(1) }
		.bgr { u8(3) }
		.bgra { u8(4) }
	}
}

// AtlasRegion is declared in the cycle-free sprite_types module so both the
// Atlas and Canvas.write_atlas use one canonical region value.
pub type AtlasRegion = sprite_types.AtlasRegion

// AtlasNode is a rectangle of available space in the atlas.
struct AtlasNode {
mut:
	x     u32
	y     u32
	width u32
}

// Atlas holds a texture atlas for font glyphs.
//
// The implementation is based on "A Thousand Ways to Pack the Bin - A
// Practical Approach to Two-Dimensional Rectangle Bin Packing" by Jukka
// Jylänki (see ghostty/src/font/Atlas.zig for the full commentary).
pub struct Atlas {
pub mut:
	// Modification counter, incremented on each atlas update.
	modified stdatomic.AtomicVal[uint]
	// Resize counter, incremented on each atlas resize.
	resized stdatomic.AtomicVal[uint]
	// The size of the atlas texture (width and height are equal).
	size u32
	// The pixel format of this atlas.
	format AtlasFormat
	// The raw pixel data.
	data []u8
	// The nodes (rectangles) of available space.
	nodes []AtlasNode
}

pub enum AtlasInitFailPoint as u8 {
	alloc_data
	alloc_nodes
}

pub enum AtlasReserveFailPoint as u8 {
	insert_node
}

pub enum AtlasGrowFailPoint as u8 {
	ensure_node_capacity
	alloc_data
}

struct AtlasTripwires {
mut:
	init    tripwire.TripwireModule[AtlasInitFailPoint]
	reserve tripwire.TripwireModule[AtlasReserveFailPoint]
	grow    tripwire.TripwireModule[AtlasGrowFailPoint]
}

const atlas_tripwires = &AtlasTripwires{}

pub fn atlas_init_tripwire() &tripwire.TripwireModule[AtlasInitFailPoint] {
	return unsafe { &atlas_tripwires.init }
}

pub fn atlas_reserve_tripwire() &tripwire.TripwireModule[AtlasReserveFailPoint] {
	return unsafe { &atlas_tripwires.reserve }
}

pub fn atlas_grow_tripwire() &tripwire.TripwireModule[AtlasGrowFailPoint] {
	return unsafe { &atlas_tripwires.grow }
}

// init creates a new Atlas with the given initial size and format.
pub fn Atlas.init(size u32, format AtlasFormat) !Atlas {
	mut tw := atlas_init_tripwire()
	tw.check(.alloc_data)!
	mut a := Atlas{
		size:   size
		format: format
		data:   []u8{len: int(size * size * format.depth())}
		nodes:  []AtlasNode{cap: 64}
	}
	tw.check(.alloc_nodes)!
	// This sets up our initial state.
	a.clear()
	return a
}

// deinit releases atlas resources.
pub fn (mut a Atlas) deinit() {
	a.data = []
	a.nodes = []
}

// reserve reserves a region within the atlas with the given width and height.
//
// May allocate to add a new rectangle into the internal list of rectangles.
// This will not automatically enlarge the texture if it is full.
pub fn (mut a Atlas) reserve(width u32, height u32) !AtlasRegion {
	// x, y are populated within the best-index search below.
	mut region := AtlasRegion{
		x:      0
		y:      0
		width:  width
		height: height
	}

	// If our width/height are 0, then we return the region as-is. This
	// may seem like an error case but it simplifies downstream callers who
	// might be trying to write empty data.
	if width == 0 && height == 0 {
		return region
	}

	// Find the location in our nodes list to insert the new node for this region.
	mut best_height := u32(0xFFFFFFFF)
	mut best_width := best_height
	mut chosen := -1

	for i in 0 .. a.nodes.len {
		// Check if our region fits within this node.
		y := a.fit(i, width, height) or { continue }

		node := a.nodes[i]
		if (y + height) < best_height || ((y + height) == best_height
			&& (node.width > 0 && node.width < best_width)) {
			chosen = i
			best_width = node.width
			best_height = y + height
			region.x = node.x
			region.y = y
		}
	}

	// If we never found a chosen index, the atlas cannot fit our region.
	if chosen < 0 {
		return error('AtlasFull')
	}
	best_idx := chosen

	// Insert our new node for this rectangle at the exact best index.
	mut tw := atlas_reserve_tripwire()
	tw.check(.insert_node)!
	a.nodes.insert(best_idx, AtlasNode{
		x:     region.x
		y:     region.y + height
		width: width
	})

	// Optimize our rectangles.
	mut i := best_idx + 1
	for i < a.nodes.len {
		prev := a.nodes[i - 1]
		if a.nodes[i].x < (prev.x + prev.width) {
			shrink := prev.x + prev.width - a.nodes[i].x
			a.nodes[i].x += shrink
			// Saturating subtract.
			a.nodes[i].width = if a.nodes[i].width > shrink {
				a.nodes[i].width - shrink
			} else {
				u32(0)
			}
			if a.nodes[i].width <= 0 {
				// Remove the now-empty node. Zig decrements i then relies on
				// the loop's i+=1 step; the net effect is that i is unchanged
				// so we re-examine the node that shifted into this slot.
				a.nodes.delete(i)
				continue
			}
		}

		break
	}
	a.merge()

	return region
}

// fit attempts to fit a rectangle of width x height into the node at idx.
// The return value is the y within the texture where the rectangle can be
// placed. The x is the same as the node.
fn (a &Atlas) fit(idx int, width u32, height u32) ?u32 {
	// If the added width exceeds our texture size, it doesn't fit.
	node := a.nodes[idx]
	if (node.x + width) > (a.size - 1) {
		return none
	}

	// Go node by node looking for space that can fit our width.
	mut y := node.y
	mut i := idx
	mut width_left := width
	for width_left > 0 {
		n := a.nodes[i]
		if n.y > y {
			y = n.y
		}

		// If the added height exceeds our texture size, it doesn't fit.
		if (y + height) > (a.size - 1) {
			return none
		}

		// Saturating subtract.
		width_left = if width_left > n.width { width_left - n.width } else { u32(0) }
		i += 1
	}

	return y
}

// merge merges adjacent nodes with the same y value.
fn (mut a Atlas) merge() {
	mut i := 0
	for i < a.nodes.len - 1 {
		next := a.nodes[i + 1]
		if a.nodes[i].y == next.y {
			a.nodes[i].width += next.width
			a.nodes.delete(i + 1)
			continue
		}

		i += 1
	}
}

// set sets the data associated with a reserved region. The data is expected
// to fit exactly within the region. The data must be formatted with the
// proper bpp configured on init.
pub fn (mut a Atlas) set(reg AtlasRegion, data []u8) {
	assert reg.x < a.size - 1
	assert reg.x + reg.width <= a.size - 1
	assert reg.y < a.size - 1
	assert reg.y + reg.height <= a.size - 1

	depth := a.format.depth()
	for i in u32(0) .. reg.height {
		tex_offset := (((reg.y + i) * a.size) + reg.x) * depth
		data_offset := i * reg.width * depth
		row := reg.width * depth
		mut dest := a.data[int(tex_offset)..]
		fastmem.copy(mut dest, data[int(data_offset)..int(data_offset + row)])
	}

	_ = a.modified.add(1)
}

// set_from_larger is like set but allows specifying a width for the source
// data and an offset x and y, so that a section of a larger buffer may be
// copied in to the atlas.
pub fn (mut a Atlas) set_from_larger(reg AtlasRegion, src []u8, src_width u32, src_x u32, src_y u32) {
	assert reg.x < a.size - 1
	assert reg.x + reg.width <= a.size - 1
	assert reg.y < a.size - 1
	assert reg.y + reg.height <= a.size - 1

	depth := a.format.depth()
	for i in u32(0) .. reg.height {
		tex_offset := (((reg.y + i) * a.size) + reg.x) * depth
		src_offset := (((src_y + i) * src_width) + src_x) * depth
		row := reg.width * depth
		mut dest := a.data[int(tex_offset)..]
		fastmem.copy(mut dest, src[int(src_offset)..int(src_offset + row)])
	}

	_ = a.modified.add(1)
}

// grow grows the texture to the new size, preserving all previously written data.
pub fn (mut a Atlas) grow(size_new u32) ! {
	assert size_new >= a.size
	if size_new == a.size {
		return
	}

	depth := a.format.depth()
	mut tw := atlas_grow_tripwire()
	tw.check(.ensure_node_capacity)!
	a.nodes.ensure_cap(a.nodes.len + 1)
	tw.check(.alloc_data)!

	// Keep track of our old data so that we can copy it.
	data_old := a.data
	size_old := a.size

	// Update our data and size to our new ones.
	a.data = []u8{len: int(size_new * size_new * depth)}
	a.size = size_new

	// Zero the new data out and copy the old data over.
	// (New data is already zeroed on allocation.)
	//
	// We skip the first border row of the old data, since we copy it in
	// starting at y=1 in the new atlas.
	a.set(AtlasRegion{
		x:      0 // don't bother skipping border so we can avoid strides
		y:      1 // skip the first border row
		width:  size_old
		height: size_old - 2 // skip the last border row
	}, data_old[int(size_old * depth)..])

	// Add the new rectangle for our added righthand space.
	a.nodes << AtlasNode{
		x:     size_old - 1
		y:     1
		width: size_new - size_old
	}

	// We are both modified and resized.
	_ = a.modified.add(1)
	_ = a.resized.add(1)
}

// clear empties the atlas. This doesn't reclaim any previously allocated memory.
pub fn (mut a Atlas) clear() {
	_ = a.modified.add(1)
	for i in 0 .. a.data.len {
		a.data[i] = 0
	}
	a.nodes.clear()

	// Add our initial rectangle. This is the size of the full texture
	// and is the initial rectangle we fit our regions in. We keep a 1px border
	// to avoid artifacting when sampling the texture.
	a.nodes << AtlasNode{
		x:     1
		y:     1
		width: a.size - 2
	}
}

// dump writes the atlas as a PPM image for debugging. As in Ghostty, BGR
// data is written without swapping its red and blue channels.
//
// Only grayscale and BGR atlases are supported. BGRA cannot be represented
// directly by either of the binary PPM encodings used here.
pub fn (a &Atlas) dump(mut writer io.Writer) ! {
	magic := match a.format {
		.grayscale { '5' }
		.bgr { '6' }
		.bgra {
			panic('Cannot dump this atlas format.')
		}
	}
	header := 'P${magic}\n${a.size} ${a.size}\n255\n'
	atlas_write_all(mut writer, header.bytes())!
	atlas_write_all(mut writer, a.data)!
}

fn atlas_write_all(mut writer io.Writer, data []u8) ! {
	mut offset := 0
	for offset < data.len {
		written := writer.write(data[offset..])!
		if written <= 0 || written > data.len - offset {
			return error('atlas writer returned an invalid byte count')
		}
		offset += written
	}
}

// RenderResult holds the result of rendering a glyph.
pub struct RenderResult {
pub:
	glyph        Glyph
	presentation Presentation
}

// RenderOptions for glyph rendering.
pub struct RenderOptions {
pub mut:
	// Ghostty stores this as ?u2 and packs null as zero in glyph cache keys.
	// V has no u2; entry points validate the same two-bit range.
	cell_width       ?u8
	grid_metrics     Metrics
	thicken          bool
	thicken_strength u8 = 255
	constraint       Constraint
	constraint_width u8 = 1
}

// Source RenderOptions width fields are u2. Validate that range at every
// rendering boundary because V's smallest unsigned integer is u8.
fn (opts RenderOptions) assert_narrow_widths() {
	if width := opts.cell_width { assert width <= 3 }
	assert opts.constraint_width <= 3
	assert opts.constraint.max_constraint_width <= 3
}

// Constraint controls how a glyph is constrained to fit its cell.
// Specifies scaling/positioning attributes for glyphs.
pub struct Constraint {
pub mut:
	// Sizing rule.
	size ConstraintSize = .none_
	// Vertical alignment rule.
	align_vertical ConstraintAlign = .none_
	// Horizontal alignment rule.
	align_horizontal ConstraintAlign = .none_
	// Top padding when resizing.
	pad_top f64
	// Left padding when resizing.
	pad_left f64
	// Right padding when resizing.
	pad_right f64
	// Bottom padding when resizing.
	pad_bottom f64
	// Size and bearings of the glyph relative
	// to the bounding box of its scale group.
	relative_width  f64 = 1.0
	relative_height f64 = 1.0
	relative_x      f64
	relative_y      f64
	// Maximum aspect ratio (width/height) to allow when stretching.
	// None means no limit; a present zero remains an active constraint.
	max_xy_ratio ?f64
	// Maximum number of cells horizontally to use.
	max_constraint_width u8 = 2
	// What to use as the height metric when constraining the glyph
	// and the constraint width is 1.
	height ConstraintHeight = .cell
}

// Don't constrain the glyph in any way.
pub const constraint_none = Constraint{}

// Returns true if the constraint does anything. If it doesn't,
// because it neither sizes nor positions the glyph, then this
// returns false.
pub fn (c Constraint) does_anything() bool {
	return c.size != .none_ || c.align_horizontal != .none_ || c.align_vertical != .none_
}

// ConstraintSize specifies how a glyph should be sized.
pub enum ConstraintSize as u8 {
	// Don't change the size of this glyph.
	none_
	// Scale the glyph down if needed to fit within the bounds,
	// preserving aspect ratio.
	fit
	// Scale the glyph up or down to exactly match the bounds,
	// preserving aspect ratio.
	cover
	// Scale the glyph down if needed to fit within the bounds,
	// preserving aspect ratio. If the glyph doesn't cover a
	// single cell, scale up. If the glyph exceeds a single
	// cell but is within the bounds, do nothing.
	// (Nerd Font specific rule.)
	fit_cover1
	// Stretch the glyph to exactly fit the bounds in both
	// directions, disregarding aspect ratio.
	stretch
}

// ConstraintAlign specifies how a glyph should be aligned.
pub enum ConstraintAlign as u8 {
	// Don't move the glyph on this axis.
	none_
	// Move the glyph so that its leading (bottom/left)
	// edge aligns with the leading edge of the axis.
	start
	// Move the glyph so that its trailing (top/right)
	// edge aligns with the trailing edge of the axis.
	end_
	// Move the glyph so that it is centered on this axis.
	center
	// Move the glyph so that it is centered on this axis,
	// but always with respect to the first cell even for
	// multi-cell constraints. (Nerd Font specific rule.)
	center1
}

// ConstraintHeight specifies what height metric to use.
pub enum ConstraintHeight as u8 {
	// Use the full line height of the primary face for
	// constraining this glyph.
	cell
	// Use the icon height from the grid metrics for
	// constraining this glyph. Unlike cell, the value of
	// this height depends on both the constraint width and the
	// adjust-icon-height config option.
	icon
}

// Presentation for a glyph (text or emoji).
pub enum Presentation as u8 {
	text  = 0
	emoji = 1
}

// Style for codepoint rendering.
pub enum Style as u8 {
	regular     = 0
	bold        = 1
	italic      = 2
	bold_italic = 3
}

// ============================================================
// Sprite
// ============================================================

// Sprite enumerates built-in sprite glyphs used for cursors,
// underlines, and other decorations.
// Sprites are represented as special codepoints outside of the Unicode
// codepoint range. The enum values correspond to the codepoint offsets
// from Sprite.start (0x110000), matching ghostty's font/sprite.zig ordering.
pub enum Sprite as u32 {
	underline = 0x110000
	underline_double
	underline_dotted
	underline_dashed
	underline_curly
	strikethrough
	overline
	cursor_rect
	cursor_hollow_rect
	cursor_bar
	cursor_underline
}

// ============================================================
// Shaper
// ============================================================

// HarfBuzz adapter retained for the module-level API. The production source
// backend switch is font.shaper.NativeShaper, used by Renderer.
pub struct Shaper {
mut:
	features   []string
	hb_buf     harfbuzz.Buffer
	hb_feats   []harfbuzz.Feature
	codepoints []ShaperCodepoint
	cell_buf   []ShapeCell
	grid       &SharedGrid = unsafe { nil }
}

struct ShaperCodepoint {
	cluster   u32
	codepoint u32
}

pub fn Shaper.init(opts ShaperOptions) !Shaper {
	mut feature_list := feature_parser.FeatureList{
		features: feature_parser.default_features.clone()
	}
	for setting in opts.features {
		feature_list.append_from_string(setting)
	}
	mut feats := []harfbuzz.Feature{cap: feature_list.features.len}
	for setting in feature_list.features {
		feats << harfbuzz.Feature{
			tag: u32(setting.tag[0]) << 24 | u32(setting.tag[1]) << 16 | u32(setting.tag[2]) << 8 | u32(setting.tag[3])
			value: setting.value
			start: harfbuzz.feature_global_start
			end: harfbuzz.feature_global_end
		}
	}
	return Shaper{
		features: opts.features.clone()
		hb_buf:   harfbuzz.Buffer.create()!
		hb_feats: feats
	}
}

pub fn (mut s Shaper) deinit() {
	s.hb_buf.destroy()
	s.features = []
	s.hb_feats = []
	s.codepoints = []
	s.cell_buf = []
}

// Signal that we're done processing the current frame.
// For some shapers (e.g. CoreText), this triggers off-thread cleanup.
pub fn (mut s Shaper) end_frame() {
	// The FreeType/HarfBuzz backend has no deferred per-frame resources.
}

// Shape a text run into positioned glyphs.
pub fn (mut s Shaper) shape(run TextRun) ![]ShapeCell {
	if _ := run.font_index.special() {
		s.cell_buf.clear()
		for cp in s.codepoints {
			s.cell_buf << ShapeCell{ x: cp.cluster, glyph_index: cp.codepoint }
		}
		return s.cell_buf
	}
	if s.hb_buf.get_length() == 0 {
		return []ShapeCell{}
	}
	if run.grid == unsafe { nil } {
		return error('font shaper has no grid')
	}
	{
		mut grid := unsafe { run.grid }
		// The collection lookup may load a deferred face, and FreeType shaping
		// mutates native state. The source protects both with the grid lock.
		grid.lock.lock()
		defer { grid.lock.unlock() }
		face := grid.resolver.collection.get_face(run.font_index)!
		feature_start := if face.quirks_disable_default_font_features { feature_parser.default_features.len } else { 0 }
		harfbuzz.shape(face.hb_font, s.hb_buf, s.hb_feats[feature_start..])
	}

	info := s.hb_buf.get_glyph_infos()
	positions := s.hb_buf.get_glyph_positions() or { return error('HarfBuzz returned no positions') }
	if info.len != positions.len {
		return error('HarfBuzz glyph info/position length mismatch')
	}
	mut run_cluster := u32(0)
	mut run_x := i32(0)
	mut run_y := i32(0)
	mut cell_cluster := u32(0)
	mut cell_x := i32(0)
	s.cell_buf.clear()
	for i in 0 .. info.len {
		idx := int(info[i].cluster)
		if idx < 0 || idx >= s.codepoints.len {
			return error('HarfBuzz returned an invalid cluster index')
		}
		cluster := s.codepoints[idx].cluster
		if cell_cluster != cluster {
			after_current_cluster := cluster <= run_cluster
			first_in_cluster := idx == 0 || s.codepoints[idx - 1].cluster != cluster
			if first_in_cluster && !after_current_cluster {
				cell_cluster = cluster
				cell_x = run_x
			}
		}
		pos := positions[i]
		s.cell_buf << ShapeCell{
			x:           cell_cluster
			glyph_index: info[i].codepoint
			x_offset:    run_x - cell_x + ((pos.x_offset + 32) >> 6)
			y_offset:    run_y + ((pos.y_offset + 32) >> 6)
		}
		run_x += (pos.x_advance + 32) >> 6
		run_y += (pos.y_advance + 32) >> 6
		if cluster > run_cluster {
			run_cluster = cluster
		}
	}
	return s.cell_buf
}

// Create a run iterator for the given options.
pub fn (mut s Shaper) run_iterator(opts RunOptions) RunIterator {
	s.grid = opts.grid
	return RunIterator.new(unsafe { &s }, opts)
}

pub struct ShaperOptions {
pub:
	features []string
}

// ============================================================
// ShaperCache
// ============================================================

// ShaperCache caches shaped text runs to avoid re-shaping.
pub struct ShaperCache {
mut:
	entries     datastruct.U64CacheTable[[]ShapeCell]
	recent_runs [512]u64
}

pub fn ShaperCache.init() ShaperCache {
	return ShaperCache{
		// Keep up to 256 reusable runs per renderer.
		entries: datastruct.U64CacheTable.init_with_buckets[[]ShapeCell](32)
	}
}

pub fn (mut c ShaperCache) deinit() {
	c.entries.clear()
	c.recent_runs = [512]u64{}
}

// Get cached shaping results for a run.
pub fn (mut c ShaperCache) get(run TextRun) ?[]ShapeCell {
	return c.entries.get(run.hash)
}

// has_recent_run remembers cache misses so one-time runs do not evict
// shaping results that have already been reused.
pub fn (mut c ShaperCache) has_recent_run(run TextRun) bool {
	index := int(run.hash % u64(c.recent_runs.len))
	repeated := run.hash != 0 && c.recent_runs[index] == run.hash
	c.recent_runs[index] = run.hash
	return repeated
}

// Store shaping results for a run in the cache.
pub fn (mut c ShaperCache) put(run TextRun, cells []ShapeCell) ! {
	// The shaper reuses a buffer sized for its largest run. Keep only the
	// cells belonging to this run in the cache.
	mut cached := []ShapeCell{len: cells.len}
	copy(mut cached, cells)
	c.entries.put(run.hash, cached)
}

// Return the number of cached entries.
pub fn (c &ShaperCache) count() int {
	return c.entries.count()
}

// ============================================================
// Shape types (text runs and cells)
// ============================================================

// TextRun represents a run of text to be shaped.
pub struct TextRun {
pub:
	// A unique hash for this run. This can be used to cache the shaping
	// results. The hash is position-independent within the row by using
	// relative cluster positions.
	hash       u64
	font_index Index
	offset     u16
	cells      u16
	grid       &SharedGrid = unsafe { nil }
	// Set by the WebCanvas backend so multi-codepoint graphemes can reserve
	// the private glyph ID that the same face will later render.
	web_canvas_face &WebCanvasFace = unsafe { nil }
}

// TextRunValue preserves Ghostty's !?TextRun return contract. V cannot nest
// an Option inside a Result, so has_value represents the optional layer while
// the containing Result represents iterator errors.
pub struct TextRunValue {
pub:
	has_value bool
	value     TextRun
}

pub fn (value TextRunValue) get() ?TextRun {
	if !value.has_value {
		return none
	}
	return value.value
}

// ShapeCell represents a positioned glyph from shaping.
pub struct ShapeCell {
pub:
	x           u32
	glyph_index u32
	x_offset    i32
	y_offset    i32
}

// RunOptions configures the run iterator.
pub struct RunOptions {
pub mut:
	grid &SharedGrid = unsafe { nil }
	// Render cells are the production representation. `cells` retains the
	// byte-row adapter used by small standalone shaper tests.
	render_cells []terminal.RenderCell
	cells        []u8
	selection    ?[2]u16
	cursor_x     ?u16
}

// apply_break_config removes cursor shaping boundaries when the corresponding
// configuration is disabled.
pub fn (mut self RunOptions) apply_break_config(cursor bool) {
	if !cursor {
		self.cursor_x = none
	}
}

// RunIterator iterates over text runs for shaping.
pub struct RunIterator {
pub mut:
	shaper_ptr  voidptr = unsafe { nil }
	opts        RunOptions
	i           int
	prepare_fn  fn (voidptr)                 = unsafe { nil }
	add_fn      fn (voidptr, u32, u32) !void = unsafe { nil }
	finalize_fn fn (voidptr)                 = unsafe { nil }
}

// RunIteratorHooks lets each shaping backend receive the run's codepoints
// without the iterator knowing the backend's concrete struct layout. This is
// the V equivalent of Ghostty's comptime RunIteratorHook.
pub struct RunIteratorHooks {
pub:
	prepare  fn (voidptr)                 = unsafe { nil }
	add      fn (voidptr, u32, u32) !void = unsafe { nil }
	finalize fn (voidptr)                 = unsafe { nil }
}

// Create a new RunIterator with an opaque pointer to the shaper.
pub fn RunIterator.new(shaper_ptr voidptr, opts ...RunOptions) RunIterator {
	return RunIterator{
		shaper_ptr: shaper_ptr
		opts:       if opts.len > 0 { opts[0] } else { RunOptions{} }
	}
}

pub fn RunIterator.new_with_hooks(shaper_ptr voidptr, opts RunOptions, hooks RunIteratorHooks) RunIterator {
	return RunIterator{
		shaper_ptr:  shaper_ptr
		opts:        opts
		prepare_fn:  hooks.prepare
		add_fn:      hooks.add
		finalize_fn: hooks.finalize
	}
}

// Get the next text run. A value with has_value=false means the iterator is
// exhausted; errors from font lookup or the shaping hook are propagated.
pub fn (mut it RunIterator) next() !TextRunValue {
	if it.shaper_ptr == unsafe { nil } {
		return TextRunValue{}
	}
	if it.opts.render_cells.len == 0 {
		return it.next_bytes()
	}
	return it.next_render_cells()
}

fn default_run_prepare(shaper_ptr voidptr) {
	mut shaper := unsafe { &Shaper(shaper_ptr) }
	shaper.hb_buf.reset()
	shaper.hb_buf.set_content_type(.unicode)
	shaper.hb_buf.set_cluster_level(.characters)
	// Terminal rows are laid out in strictly increasing X order. Ghostty
	// deliberately forces LTR here even for scripts whose natural direction
	// is RTL because bidi layout is handled outside of the font shaper.
	shaper.hb_buf.set_direction(.ltr)
	shaper.codepoints.clear()
}

fn default_run_add(shaper_ptr voidptr, cp u32, cluster u32) {
	mut shaper := unsafe { &Shaper(shaper_ptr) }
	shaper.hb_buf.add(cp, u32(shaper.codepoints.len))
	shaper.codepoints << ShaperCodepoint{ codepoint: cp, cluster: cluster }
}

fn default_run_finalize(shaper_ptr voidptr) {
	mut shaper := unsafe { &Shaper(shaper_ptr) }
	shaper.hb_buf.guess_segment_properties()
}

fn (it &RunIterator) prepare() {
	if it.prepare_fn != unsafe { nil } {
		it.prepare_fn(it.shaper_ptr)
	} else {
		default_run_prepare(it.shaper_ptr)
	}
}

fn (it &RunIterator) add_codepoint(mut hasher SourceHash, cp u32, cluster u32) ! {
	hasher.put_u32(cp)
	hasher.put_u32(cluster)
	if it.add_fn != unsafe { nil } {
		it.add_fn(it.shaper_ptr, cp, cluster)!
	} else {
		default_run_add(it.shaper_ptr, cp, cluster)
	}
}

fn (it &RunIterator) finalize() {
	if it.finalize_fn != unsafe { nil } {
		it.finalize_fn(it.shaper_ptr)
	} else {
		default_run_finalize(it.shaper_ptr)
	}
}

fn (mut it RunIterator) next_bytes() !TextRunValue {
	mut max := it.opts.cells.len
	for max > 0 && it.opts.cells[max - 1] == 0 {
		max--
	}
	if it.i >= max {
		return TextRunValue{}
	}
	it.prepare()
	start := it.i
	mut hasher := SourceHash{}
	for it.i < max {
		cp := if it.opts.cells[it.i] == 0 { u32(` `) } else { u32(it.opts.cells[it.i]) }
		it.add_codepoint(mut hasher, cp, u32(it.i - start))!
		it.i++
	}
	it.finalize()
	hasher.put_u64(u64(it.i - start))
	hasher.put_u16(0)
	return TextRunValue{
		has_value: true
		value:     TextRun{
			hash:       hasher.final()
			font_index: Index{}
			offset:     u16(start)
			cells:      u16(it.i - start)
			grid:       it.opts.grid
		}
	}
}

fn (mut it RunIterator) next_render_cells() !TextRunValue {
	cells := it.opts.render_cells
	mut max := cells.len
	for max > 0 && cells[max - 1].raw.is_empty() {
		max--
	}
	for it.i < max && cell_style(cells[it.i]).flags.invisible() {
		it.i++
	}
	if it.i >= max {
		return TextRunValue{}
	}
	it.prepare()
	start := it.i
	base_style := cell_style(cells[start])
	font_style := style_to_font_style(base_style)
	mut current_font := Index{}
	mut has_font := false
	mut hasher := SourceHash{}
	mut j := start
	for j < max {
		cell := cells[j]
		if bounds := it.opts.selection {
			if j > start && ((bounds[0] > 0 && j == int(bounds[0]))
				|| (bounds[1] > 0 && j == int(bounds[1]) + 1)) {
				break
			}
		}
		if cell.raw.wide == .spacer_head || cell.raw.wide == .spacer_tail {
			j++
			continue
		}
		if j > start {
			prev := cells[j - 1]
			if prev.raw.content_tag == .codepoint && cell.raw.content_tag == .codepoint {
				prev_cp := prev.raw.codepoint()
				cp := cell.raw.codepoint()
				if (prev_cp == `f` && (cp == `l` || cp == `i`))
					|| (prev_cp == `s` && cp == `t`) {
					break
				}
			}
			// Witty carries the concrete style inline. Its nonzero style_id is
			// only a presence discriminator, so compare the values directly;
			// Ghostty gets the same result by comparing page-local style IDs.
			comparable_base := comparable_style(base_style)
			comparable_current := comparable_style(cell_style(cell))
			if !comparable_base.eql(&comparable_current) {
				break
			}
		}
		if cell.raw.content_tag != .codepoint_grapheme {
			if cursor_x := it.opts.cursor_x {
				if (start == int(cursor_x) && j == start + 1) || (start < int(cursor_x)
					&& j == int(cursor_x)) {
					break
				}
			}
		}
		mut presentation := ?Presentation(none)
		if cell.raw.content_tag == .codepoint_grapheme && cell.grapheme.len > 0 {
			if cell.grapheme[0] == 0xfe0e {
				presentation = Presentation.text
			} else if cell.grapheme[0] == 0xfe0f {
				presentation = Presentation.emoji
			}
		}
		mut resolved_cp := cell.raw.codepoint()
		mut index_value := index_for_render_cell(it.opts.grid, &cell, font_style, presentation)!
		if !index_value.has_value {
			mut grid := unsafe { it.opts.grid }
			index_value = grid.get_index(0xfffd, font_style, presentation)!
			if index_value.has_value {
				resolved_cp = 0xfffd
			} else {
				index_value = grid.get_index(u32(` `), font_style, presentation)!
				if !index_value.has_value {
					panic('font grid cannot render a space')
				}
				resolved_cp = u32(` `)
			}
		}
		idx := index_value.index
		if !has_font {
			current_font = idx
			has_font = true
		} else if idx.int() != current_font.int() {
			break
		}
		cluster := u32(j - start)
		if resolved_cp == 0 || resolved_cp == 0x10eeee {
			resolved_cp = u32(` `)
		}
		it.add_codepoint(mut hasher, resolved_cp, cluster)!
		if resolved_cp == cell.raw.codepoint() && cell.raw.content_tag == .codepoint_grapheme {
			for cp in cell.grapheme {
				if cp != 0xfe0e && cp != 0xfe0f {
					it.add_codepoint(mut hasher, cp, cluster)!
				}
			}
		}
		j++
	}
	if j == start {
		return TextRunValue{}
	}
	it.finalize()
	hasher.put_u64(u64(j - start))
	hasher.put_u16(current_font.int())
	it.i = j
	mut web_canvas_face := &WebCanvasFace(unsafe { nil })
	if it.opts.grid.backend() == .web_canvas && current_font.special() == none {
		mut grid := unsafe { it.opts.grid }
		grid.lock.rlock()
		face := grid.resolver.collection.get_face(current_font) or {
			grid.lock.runlock()
			return err
		}
		web_canvas_face = &face.web_canvas
		grid.lock.runlock()
	}
	return TextRunValue{
		has_value: true
		value:     TextRun{
			hash:       hasher.final()
			font_index: current_font
			offset:     u16(start)
			cells:      u16(j - start)
			grid:       it.opts.grid
			web_canvas_face: web_canvas_face
		}
	}
}

fn cell_style(cell terminal.RenderCell) terminal.CellStyle {
	return if cell.raw.has_styling() { cell.style } else { terminal.CellStyle{} }
}

fn style_to_font_style(style terminal.CellStyle) Style {
	return if style.flags.bold() {
		if style.flags.italic() { Style.bold_italic } else { Style.bold }
	} else if style.flags.italic() {
		Style.italic
	} else {
		Style.regular
	}
}

fn comparable_style(style terminal.CellStyle) terminal.CellStyle {
	mut result := style
	result.bg_color = terminal.StyleColorNone{}
	return result
}

fn index_for_render_cell(grid_ptr &SharedGrid, cell &terminal.RenderCell, style Style, presentation ?Presentation) !CodepointValue {
	if grid_ptr == unsafe { nil } {
		return CodepointValue{}
	}
	mut grid := unsafe { grid_ptr }
	primary_cp := cell.raw.codepoint()
	if cell.raw.is_empty() || primary_cp == 0 || primary_cp == 0x10eeee {
		return grid.get_index(u32(` `), style, presentation)!
	}
	primary_value := grid.get_index(primary_cp, style, presentation)!
	if !primary_value.has_value {
		return CodepointValue{}
	}
	primary := primary_value.index
	if cell.raw.content_tag != .codepoint_grapheme {
		return CodepointValue{
			has_value: true
			index:     primary
		}
	}
	mut candidates := [primary]
	for cp in cell.grapheme {
		if cp == 0xfe0e || cp == 0xfe0f || cp == 0x200d {
			continue
		}
		value := grid.get_index(cp, style, none)!
		if !value.has_value {
			return CodepointValue{}
		}
		candidates << value.index
	}
	for idx in candidates {
		if !grid.has_codepoint(idx, primary_cp, presentation) {
			continue
		}
		mut all := true
		for cp in cell.grapheme {
			if cp != 0xfe0e && cp != 0xfe0f && cp != 0x200d
				&& !grid.has_codepoint(idx, cp, none) {
				all = false
				break
			}
		}
		if all {
			return CodepointValue{
				has_value: true
				index:     idx
			}
		}
	}
	return CodepointValue{}
}

// SharedGrid.cell_size returns this module-local projection because importing
// renderer.CellSize here would create a renderer -> font -> renderer cycle.
pub struct CellSize {
pub:
	width  u32
	height u32
}
