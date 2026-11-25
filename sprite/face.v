module sprite

// --- Original Ghostty Comments Start: src/font/sprite/Face.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/font/sprite/Face.zig
//
// This implements the built-in "sprite face". This font renders
// the built-in glyphs for the terminal, such as box drawing fonts, as well
// as specific sprites that are part of our rendering model such as
// text decorations (underlines).
//
// This isn't really a "font face" so much as it is quacks like a font
// face with regards to how it works with font.Group. We don't use any
// dynamic dispatch so it isn't truly an interface but the functions
// and behaviors are close enough to a system face that it makes it easy
// to integrate with font.Group. This is desirable so that higher level
// processes such as GroupCache, Shaper, etc. don't need to be aware of
// special sprite handling and just treat it like a normal font face.
// Grid metrics for rendering sprites.
// Something went wrong while doing math.
// A function that draws a glyph on the provided canvas.
// Automatically collect ranges for functions with names
// in the format `draw<CP>` or `draw<MIN>_<MAX>`.
// Structs containing drawing functions for codepoint ranges.
// Count how many draw fns we have
// Make an array and collect ranges for each function.
// Sort ranges in ascending order
// Ensure there's no overlapping ranges
// We need to copy in to a const rather than a var in order to take
// the reference at comptime so that we can break with a slice here.
// For special sprites (cursors, underlines, etc.) all sprites are drawn
// by functions from `Special` that share the name of the enum field.
// Pray that the compiler is smart enough to
// turn this in to a jump table or something...
// Returns true if the codepoint exists in our sprite font.
// We ignore presentation. No matter what presentation is
// requested we always provide glyphs for our codepoints.
// Render the glyph.
// It should be impossible for this to be null and we assert that
// in runtime safety modes but in case it is its not worth memory
// corruption so we return a valid, blank glyph.
// We adjust our sprite width based on the cell width.
// Make a canvas of the desired size
// Write the drawing to the atlas
// Used in `testDrawRanges`, checks for diff between the provided atlas
// and the reference file for the range, returns true if there is a diff.
// Get the file contents, we compare the PNG data first in
// order to ensure that no one smuggles arbitrary binary
// data in to the reference PNGs.
// Get the reference file contents to compare.
// Copy the test PNG in to the CWD so it isn't
// cleaned up with the rest of the tmp dir files.
// Do our PNG bytes comparison, if it's the same then we can
// move on, otherwise we'll decode the reference file and do
// a pixel-for-pixel diff.
// Copy the test PNG in to the CWD so it isn't
// cleaned up with the rest of the tmp dir files.
// Use wuffs to decode the reference PNG to raw pixels.
// These will be RGBA, so when diffing we can just compare
// every fourth byte.
// We'll make a visual representation of the diff using
// red for removed pixels and green for added. We make
// a z2d surface for that here.
// If the pixels match, write it as a faded gray.
// Otherwise put the reference value in the red
// channel and the new value in the green channel.
// If the PNG data differs but not the raw pixels, that's
// a big red flag, since it could mean someone is trying to
// smuggle binary data in to the test files.
// Drop the diff image as a PNG in the cwd.
// Draws all ranges in to a set of 16x16 glyph atlases, checks for regressions
// against reference files, logs errors and exposes a diff for any difference
// between the reference and test atlas.
//
// Returns true if there was a diff.
// Fudged number, not used in anything we care about here.
// Canvas to draw glyphs on, we'll reuse this for all glyphs.
// We render glyphs in batches of 256, which we copy (including padding) to
// a 16 by 16 surface to be compared with the reference file for that range.
// Try to make the sprite_face_test folder if it doesn't already exist.
// We set this to true if we have any fails so we can
// return an error after we're done comparing all glyphs.
// If we've moved to a new batch of 256, check the
// current one and clear the surface for the next one.
// Export to our tmp dir.
// This test is way too slow to run under Valgrind, unfortunately.
// Renders all sprites to an atlas and compares
// it to a ground truth for regression testing.
// testDrawRanges(width, ascent, descent, thickness):
//
// We compare 4 different sets of metrics;
// - even cell size / even thickness
// - even cell size / odd thickness
// - odd cell size / even thickness
// - odd cell size / odd thickness
// (Also a decreasing range of sizes.)
// test "sprite face print all sprites" {
//     std.debug.print("\n\n", .{});
//     inline for (ranges) |range| {
//         for (range.min..range.max + 1) |cp| {
//             std.debug.print("{u}", .{ @as(u21, @intCast(cp)) });
//         }
//     }
//     std.debug.print("\n\n", .{});
// }
//
// --- Original Ghostty Comments End: src/font/sprite/Face.zig

// This implements the built-in "sprite face". This font renders
// the built-in glyphs for the terminal, such as box drawing fonts, as well
// as specific sprites that are part of our rendering model such as
// text decorations (underlines).
//
// This isn't really a "font face" so much as it is quacks like a font
// face with regards to how it works with font.Group. We don't use any
// dynamic dispatch so it isn't truly an interface but the functions
// and behaviors are close enough to a system face that it makes it easy
// to integrate with font.Group. This is desirable so that higher level
// processes such as GroupCache, Shaper, etc. don't need to be aware of
// special sprite handling and just treat it like a normal font face.
//
// Translated from ghostty/src/font/sprite/Face.zig
import buildcfg
import sprite_types as font

// A function that draws a glyph on the provided canvas.
pub type DrawFn = fn (u32, mut Canvas, u32, u32, font.Metrics) !

// Range represents a codepoint range associated with a draw function.
struct Range {
	min  u32
	max  u32
	draw DrawFn = unsafe { nil }
}

// SpriteFace is the built-in sprite font face for the terminal.
pub struct SpriteFace {
pub:
	// Grid metrics for rendering sprites.
	metrics font.Metrics
}

pub struct RenderOptions {
pub:
	cell_width u32 = 1
}

pub struct RenderedGlyph {
pub:
	raster   RasterizedGlyph
	offset_x i32
	offset_y i32
}

// get_draw_fn returns the draw function for a given codepoint, or none.
// For special sprites (cursors, underlines, etc.) all sprites are drawn
// by functions from special.v that share the name of the enum field.
// For Unicode codepoint ranges, the appropriate draw function is returned.
fn get_draw_fn(cp u32) ?DrawFn {
	// For special sprites (cursors, underlines, etc.)
	// Sprite.start is one above the maximum Unicode codepoint (0x110000).
	sprite_start := u32(0x110000)
	if cp >= sprite_start {
		// Dispatch to special sprite drawing functions
		idx := cp - sprite_start
		return match idx {
			0 { DrawFn(underline) }
			1 { DrawFn(underline_double) }
			2 { DrawFn(underline_dotted) }
			3 { DrawFn(underline_dashed) }
			4 { DrawFn(underline_curly) }
			5 { DrawFn(strikethrough) }
			6 { DrawFn(overline) }
			7 { DrawFn(cursor_rect) }
			8 { DrawFn(cursor_hollow_rect) }
			9 { DrawFn(cursor_bar) }
			10 { DrawFn(cursor_underline) }
			else { none }
		}
	}

	// Pray that the compiler is smart enough to
	// turn this in to a jump table or something...
	//
	// Block Elements | U+2580...U+259F
	if cp >= 0x2580 && cp <= 0x259f {
		return DrawFn(draw_2580_259f)
	}
	// Box Drawing | U+2500...U+257F
	if cp >= 0x2500 && cp <= 0x257f {
		return DrawFn(draw_2500_257f)
	}
	// Braille Patterns | U+2800...U+28FF
	if cp >= 0x2800 && cp <= 0x28ff {
		return DrawFn(draw_2800_28ff)
	}
	// Geometric Shapes | U+25E2...U+25E5
	if cp >= 0x25e2 && cp <= 0x25e5 {
		return DrawFn(draw_25e2_25e5)
	}
	// Geometric Shapes | U+25F8...U+25FA
	if cp >= 0x25f8 && cp <= 0x25fa {
		return DrawFn(draw_25f8_25fa)
	}
	// Geometric Shapes | U+25FF
	if cp == 0x25ff {
		return DrawFn(draw_25ff)
	}
	// Powerline symbols
	if cp == 0xe0b0 {
		return DrawFn(draw_e0b0)
	}
	if cp == 0xe0b1 {
		return DrawFn(draw_e0b1)
	}
	if cp == 0xe0b2 {
		return DrawFn(draw_e0b2)
	}
	if cp == 0xe0b3 {
		return DrawFn(draw_e0b3)
	}
	if cp == 0xe0b4 {
		return DrawFn(draw_e0b4)
	}
	if cp == 0xe0b5 {
		return DrawFn(draw_e0b5)
	}
	if cp == 0xe0b6 {
		return DrawFn(draw_e0b6)
	}
	if cp == 0xe0b7 {
		return DrawFn(draw_e0b7)
	}
	if cp == 0xe0b8 {
		return DrawFn(draw_e0b8)
	}
	if cp == 0xe0b9 {
		return DrawFn(draw_e0b9)
	}
	if cp == 0xe0ba {
		return DrawFn(draw_e0ba)
	}
	if cp == 0xe0bb {
		return DrawFn(draw_e0bb)
	}
	if cp == 0xe0bc {
		return DrawFn(draw_e0bc)
	}
	if cp == 0xe0bd {
		return DrawFn(draw_e0bd)
	}
	if cp == 0xe0be {
		return DrawFn(draw_e0be)
	}
	if cp == 0xe0bf {
		return DrawFn(draw_e0bf)
	}
	if cp == 0xe0d2 {
		return DrawFn(draw_e0d2)
	}
	if cp == 0xe0d4 {
		return DrawFn(draw_e0d4)
	}
	// Branch Drawing Characters | U+F5D0...U+F60D
	if cp >= 0xf5d0 && cp <= 0xf60d {
		return DrawFn(draw_f5d0_f60d)
	}
	// Symbols for Legacy Computing | U+1FB00...U+1FB3B
	if cp >= 0x1fb00 && cp <= 0x1fb3b {
		return DrawFn(draw_1fb00_1fb3b)
	}
	// Smooth Mosaics | U+1FB3C...U+1FB67
	if cp >= 0x1fb3c && cp <= 0x1fb67 {
		return DrawFn(draw_1fb3c_1fb67)
	}
	// Edge triangles | U+1FB68...U+1FB6F
	if cp >= 0x1fb68 && cp <= 0x1fb6f {
		return DrawFn(draw_1fb68_1fb6f)
	}
	// Vertical one eighth blocks | U+1FB70...U+1FB75
	if cp >= 0x1fb70 && cp <= 0x1fb75 {
		return DrawFn(draw_1fb70_1fb75)
	}
	// Horizontal one eighth blocks | U+1FB76...U+1FB7B
	if cp >= 0x1fb76 && cp <= 0x1fb7b {
		return DrawFn(draw_1fb76_1fb7b)
	}
	// Mixed block characters | U+1FB7C...U+1FB97
	if cp >= 0x1fb7c && cp <= 0x1fb97 {
		return DrawFn(draw_1fb7c_1fb97)
	}
	// Upper-left to lower-right diagonal fill | U+1FB98
	if cp == 0x1fb98 {
		return DrawFn(draw_1fb98)
	}
	// Upper-right to lower-left diagonal fill | U+1FB99
	if cp == 0x1fb99 {
		return DrawFn(draw_1fb99)
	}
	// Triangles and corner triangle shades | U+1FB9A...U+1FB9F
	if cp >= 0x1fb9a && cp <= 0x1fb9f {
		return DrawFn(draw_1fb9a_1fb9f)
	}
	// Corner diagonal lines | U+1FBA0...U+1FBAE
	if cp >= 0x1fba0 && cp <= 0x1fbae {
		return DrawFn(draw_1fba0_1fbae)
	}
	// Box drawing variant | U+1FBAF
	if cp == 0x1fbaf {
		return DrawFn(draw_1fbaf)
	}
	// Inverted light diagonal cross | U+1FBBD
	if cp == 0x1fbbd {
		return DrawFn(draw_1fbbd)
	}
	// Inverted corner diagonal | U+1FBBE
	if cp == 0x1fbbe {
		return DrawFn(draw_1fbbe)
	}
	// Inverted full corner diagonal | U+1FBBF
	if cp == 0x1fbbf {
		return DrawFn(draw_1fbbf)
	}
	// Left two-thirds block | U+1FBCE
	if cp == 0x1fbce {
		return DrawFn(draw_1fbce)
	}
	// Left one-third block | U+1FBCF
	if cp == 0x1fbcf {
		return DrawFn(draw_1fbcf)
	}
	// Cell diagonals | U+1FBD0...U+1FBDF
	if cp >= 0x1fbd0 && cp <= 0x1fbdf {
		return DrawFn(draw_1fbd0_1fbdf)
	}
	// Circles | U+1FBE0...U+1FBEF
	if cp >= 0x1fbe0 && cp <= 0x1fbef {
		return DrawFn(draw_1fbe0_1fbef)
	}
	// Symbols for Legacy Computing Supplement
	// Octants | U+1CD00...U+1CDE5
	if cp >= 0x1cd00 && cp <= 0x1cde5 {
		return DrawFn(draw_1cd00_1cde5)
	}
	// Separated Block Quadrants | U+1CC21...U+1CC2F
	if cp >= 0x1cc21 && cp <= 0x1cc2f {
		return DrawFn(draw_1cc21_1cc2f)
	}
	// Twelfth and Quarter circle pieces | U+1CC30...U+1CC3F
	if cp >= 0x1cc30 && cp <= 0x1cc3f {
		return DrawFn(draw_1cc30_1cc3f)
	}
	// Box Drawings supplement | U+1CC1B...U+1CC1E
	if cp >= 0x1cc1b && cp <= 0x1cc1e {
		return DrawFn(draw_1cc1b_1cc1e)
	}
	// Right half and left half white circle | U+1CE00
	if cp == 0x1ce00 {
		return DrawFn(draw_1ce00)
	}
	// Lower half and upper half white circle | U+1CE01
	if cp == 0x1ce01 {
		return DrawFn(draw_1ce01)
	}
	// Left half white ellipse | U+1CE0B
	if cp == 0x1ce0b {
		return DrawFn(draw_1ce0b)
	}
	// Right half white ellipse | U+1CE0C
	if cp == 0x1ce0c {
		return DrawFn(draw_1ce0c)
	}
	// Box drawings light vertical and top/bottom | U+1CE16...U+1CE19
	if cp >= 0x1ce16 && cp <= 0x1ce19 {
		return DrawFn(draw_1ce16_1ce19)
	}
	// Separated Block Sextants | U+1CE51...U+1CE8F
	if cp >= 0x1ce51 && cp <= 0x1ce8f {
		return DrawFn(draw_1ce51_1ce8f)
	}
	// Sixteenth Blocks | U+1CE90...U+1CEAF
	if cp >= 0x1ce90 && cp <= 0x1ceaf {
		return DrawFn(draw_1ce90_1ceaf)
	}

	return none
}

// has_codepoint returns true if the codepoint exists in our sprite font.
// We ignore presentation. No matter what presentation is
// requested we always provide glyphs for our codepoints.
pub fn (self &SpriteFace) has_codepoint(cp u32) bool {
	_ = self
	return get_draw_fn(cp) != none
}

pub fn has_codepoint(cp u32) bool {
	return get_draw_fn(cp) != none
}

// render_glyph renders the glyph for the given codepoint.
//
// The general flow, following ghostty's Face.renderGlyph:
// 1. Look up the draw function via get_draw_fn
// 2. Calculate width based on opts.cell_width
// 3. Create a Canvas with appropriate dimensions and padding
// 4. Call the draw function to rasterize the glyph
// 5. Return the trimmed alpha mask to the font bridge for its grayscale atlas.
pub fn (self &SpriteFace) render_glyph(cp u32, opts RenderOptions) !RenderedGlyph {
	if buildcfg.runtime_safety {
		// Ghostty traps unsupported sprite codepoints in runtime-safety builds.
		assert self.has_codepoint(cp), 'invalid sprite codepoint ${cp:x}'
	}

	draw := get_draw_fn(cp) or { return RenderedGlyph{} }

	metrics := self.metrics

	// We adjust our sprite width based on the cell width.
	width := if opts.cell_width == 0 || opts.cell_width == 1 {
		metrics.cell_width
	} else {
		metrics.cell_width * opts.cell_width
	}

	height := metrics.cell_height

	padding_x := width / 4
	padding_y := height / 4

	// Make a canvas of the desired size
	mut canvas := Canvas.init(width, height, padding_x, padding_y)

	draw(cp, mut canvas, width, height, metrics)!

	raster := canvas.rasterize()

	return RenderedGlyph{
		raster: raster
		// Offsets account for padding and the trimmed edges, matching
		// ghostty Face.renderGlyph.
		offset_x: i32(raster.source_x) - i32(padding_x)
		offset_y: i32(raster.height + canvas.clip_bottom) - i32(padding_y)
	}
}
