module font

import quirks

// --- Original Ghostty Comments Start: src/font/face/freetype.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/font/face/freetype.zig
//
// Face represents a single font face. A single font face has a single set
// of properties associated with it such as style, weight, etc.
//
// A Face isn't typically meant to be used directly. It is usually used
// via a Family in order to store it in an Atlas.
// If we have the freetype backend, we should have load flags.
// Our Library
// Our font face.
// This mutex MUST be held while doing anything with the
// glyph slot on the freetype face, because this struct
// may be shared across multiple surfaces.
//
// This means that anywhere where `self.face.loadGlyph`
// is called, this mutex must be held.
// Harfbuzz font corresponding to this face.
// Freetype load flags for this font face.
// Set quirks.disableDefaultFontFeatures
// Set to true to apply a synthetic italic to the face.
// The current size this font is set to.
// Initialize a new font face with the given source in-memory.
// Initialize a new font face with the given source in-memory.
// In debug mode, we output information about available variation axes,
// if they exist.
// Returns the font name. If allocation is required, buf will be used,
// but sometimes allocation isn't required and a static string is
// returned.
// We look for the font family entry.
// There are other encodings that are something other than UTF-8
// but this is one we've seen "in the wild" so far.
// Return a new face that is the same as this but also has synthetic
// bold applied.
// Increase face ref count
// Return a new face that is the same as this but has a transformation
// matrix applied to italicize it.
// Increase face ref count
// Resize the font in-place. If this succeeds, the caller is responsible
// for clearing any glyph caches, font atlas data, etc.
// If we have fixed sizes, we just have to try to pick the one closest
// to what the user requested. Otherwise, we can choose an arbitrary
// pixel size.
// Selects the fixed size in the loaded face that is closest to the
// requested pixel size.
// Set the variation axes for this font. This will modify this font
// in-place.
// If this font doesn't support variations, we can't do anything.
// Freetype requires that we send ALL coordinates in at once so the
// first thing we have to do is get all the vars and put them into
// an array.
// To avoid allocations, we cap the number of variation axes we can
// support. This is arbitrary but Firefox caps this at 16 so I
// feel like that's probably safe... and we do double cause its
// cheap.
// Now we go through each axis and see if its set. This is slow
// but there usually aren't many axes and usually not many set
// variations, either.
// Set them!
// Returns the glyph index for the given Unicode code point. If this
// face doesn't support this glyph, null is returned.
// Returns true if this font is colored. This can be used by callers to
// determine what kind of atlas to pass in.
// Returns true if the given glyph ID is colorized.
// Load the glyph and see what pixel mode it renders with.
// All modes other than BGRA are non-color.
// If the glyph fails to load, just return false.
// NO_SVG set to true because we don't currently support rendering
// SVG glyphs under FreeType, since that requires bundling another
// dependency to handle rendering the SVG.
// Set the load flags to use when loading a glyph for measurement or
// rendering.
// Hinting should only be enabled if the configured load flags specify
// it and the provided constraint doesn't actually do anything, since
// if it does, then it'll mess up the hinting anyway when it moves or
// resizes the glyph.
// If our glyph has color, we want to render the color
// We don't render, because we'll invoke the render
// manually after applying constraints further down.
// use options from config
// If we're gonna be rendering this glyph in monochrome,
// then we should use the monochrome hinter as well, or
// else it won't look very good at all.
//
// Otherwise if the user asked for light hinting we
// use that, otherwise we just use the normal target.
// NO_SVG set to true because we don't currently support rendering
// SVG glyphs under FreeType, since that requires bundling another
// dependency to handle rendering the SVG.
// Get a rect that represents the position and size of the loaded glyph.
// If we're dealing with an outline glyph then we get the
// outline's bounding box instead of using the built-in
// metrics, since that's more precise and allows better
// cell-fitting.
// Get the glyph's bounding box before we transform it at all.
// We use this rather than the metrics, since it's more precise.
// Render a glyph using the glyph index. The rendered glyph is stored in the
// given texture atlas.
// Load the glyph.
// For synthetic bold, we embolden the glyph.
// We need to scale the embolden amount based on the font size.
// This is a heuristic I found worked well across a variety of
// founts: 1 pixel per 64 units of height.
// We get a rect that represents the position
// and size of the glyph before constraints.
// If our glyph is smaller than a quarter pixel in either axis
// then it has no outlines or they're too small to render.
//
// In this case we just return 0-sized glyph struct.
// Next we apply any constraints to get the final size of the glyph.
// We need to add the baseline position before passing to the constrain
// function since it operates on cell-relative positions, not baseline.
// We center all glyphs within the pixel-rounded and adjusted
// cell width if it's larger than the face width, so that they
// aren't weirdly off to the left.
//
// We don't do this if the glyph has a stretch constraint,
// since in that case the position was already calculated with the
// new cell width in mind.
// We add half the difference to re-center.
//
// NOTE: We round this to a whole-pixel amount because under
//       FreeType, the outlines will be hinted, which isn't
//       the case under CoreText. If we move the outlines by
//       a non-whole-pixel amount, it completely ruins the
//       hinting.
// If this is a bitmap glyph, it will always render as full pixels,
// not fractional pixels, so we need to quantize its position and
// size accordingly to align to full pixels so we get good results.
// Now we can render the glyph.
// Manually adjust the glyph outline with this transform.
//
// This offers better precision than using the freetype transform
// matrix, since that has 16.16 coefficients, and also I was having
// weird issues that I can only assume where due to freetype doing
// some bad caching or something when I did this using the matrix.
// We skew by 12 degrees to synthesize italics.
// Convert to f64 for processing
// Subtract original bearings
// Scale
// Add new bearings
// Skew
// Convert back and store
// Copy the glyph's bitmap, making sure
// that it's 8bpp and densely packed.
// If our glyph has a non-color bitmap, we need
// to convert it to dense 8bpp so that the scale
// operation works correctly.
// Make sure the slot owns its bitmap,
// since we'll be modifying it here.
// Free the existing glyph bitmap and
// replace it with the converted one.
// Round our target width and height
// as the size for our scaled bitmap.
// Allocate a buffer for our scaled bitmap.
//
// We'll copy this to the original bitmap once we're
// done so we can free it at the end of this scope.
// Resize
// This should never fail because this is a
// fairly straightforward in-memory operation...
// Replace the bitmap's buffer and size info.
// Update the bearings to account for the new positioning.
// Glyph formats are tags, so we can
// output a semi-readable error here.
// If this is a color glyph but we're trying to render it to the
// grayscale atlas, or vice versa, then we throw and error. Maybe
// in the future we could convert, but for now it should be fine.
// Our whole-pixel bearings for the final glyph.
// The fractional portion will be included in the rasterized position.
//
// For the Y position, FreeType's `bitmap_top` is the distance from the
// baseline to the top of the glyph, but we need the distance from the
// bottom of the cell to the bottom of the glyph, so first we add the
// baseline to get the distance from the bottom of the cell to the top
// of the glyph, then we subtract the height of the glyph to get the
// bottom.
// If our bitmap is grayscale, make sure to multiply all pixel
// values by the right factor to bring `num_grays` up to 256.
//
// This is necessary because FT_Bitmap_Convert doesn't do this,
// it just sets num_grays to the correct number and uses the
// original smaller pixel values.
// Must have non-empty bitmap because we return earlier if zero.
// We assume the rest of this that it is non-zero so this is important.
// If this doesn't match then something is wrong.
// Allocate our texture atlas region and copy our bitmap in to it.
// This should be the distance from the bottom of
// the cell to the top of the glyph's bounding box.
// This should be the distance from the left of
// the cell to the left of the glyph's bounding box.
// Convert 16.6 pixel format to pixels based on the scale factor of the
// current font size.
// Convert 26.6 pixel format to f32
// Get the `FaceMetrics` for this face.
// This code relies on this assumption, and it should always be
// true since we don't do any non-uniform scaling on the font ever.
// Read the 'head' table out of the font data.
// Read the 'post' table out of the font data.
// Read the 'OS/2' table out of the font data.
// Read the 'hhea' table out of the font data.
// Whether the font is in a scalable format. We need to know this
// because many of the metrics provided by FreeType are invalid for
// non-scalable fonts.
// We get the UPM from the head table.
//
// If we have no head, but it is a scalable face, take the UPM from
// FreeType's units_per_EM, otherwise we'll assume that UPM == PPEM.
// If we couldn't get the hhea table, rely on metrics from FreeType.
// We compute the line gap by adding the (negative) descender
// and subtracting the (positive) ascender from the line height
// to get the remaining gap size.
//
// NOTE: This might always be 0... but it doesn't hurt to do.
// If our font has no OS/2 table, then we just
// blindly use the metrics from the hhea table.
// If the font says to use typo metrics, trust it.
// (The USE_TYPO_METRICS bit is bit 7)
// Otherwise we prefer the height metrics from 'hhea' if they
// are available, or else OS/2 sTypo* metrics, and if all else
// fails then we use OS/2 usWin* metrics.
//
// This is not "standard" behavior, but it's our best bet to
// account for fonts being... just weird. It's pretty much what
// FreeType does to get its generic ascent and descent metrics.
// usWinDescent is *positive* -> down unlike sTypoDescender
// and hhea.Descender, so we flip its sign to fix this.
// Some fonts have degenerate 'post' tables where the underline
// thickness (and often position) are 0. We consider them null
// if this is the case and use our own fallbacks when we calculate.
// If the underline position isn't 0 then we do use it,
// even if the thickness is't properly specified.
// Similar logic to the underline above.
// Cell width is calculated by calculating the widest width of the
// visible ASCII characters. Usually 'M' is widest but we just take
// whatever is widest.
//
// ASCII height is calculated as the height of the overall bounding
// box of the same characters.
//
// If we fail to load any visible ASCII we just use max_advance from
// the metrics provided by FreeType, and set ascii_height to null as
// it's optional.
// If we couldn't get valid measurements, just use
// FreeType's max_advance and null, respectively.
// We use the cap and ex heights specified by the font if they're
// available, otherwise we try to measure the `H` and `x` glyphs.
// The OS/2 table does not include these metrics in version 1.
// Measure "水" (CJK water ideograph, U+6C34) for our ic width.
// If the advance of the glyph is less than the width of the actual
// glyph then we just treat it as invalid since it's probably wrong
// and using it for size normalization will instead make the font
// way too big.
//
// This can sometimes happen if there's a CJK font that has been
// patched with the nerd fonts patcher and it butchers the advance
// values so the advance ends up half the width of the actual glyph.
// Copy the font table data for the given tag.
// Generate all visible ASCII
// Test resizing
// Make sure this glyph has color
// glyph 3 is mono in Noto
// Including the newline
// Any glyph at 12pt @ 96 DPI is a bitmap
// glyph 77 = 'i'
// should render crisp
// Expected pixel pattern for Spleen 8x16 'A' (glyph index from char 'A')
// Derived from BDF BITMAP data: 00,00,7C,C6,C6,C6,FE,C6,C6,C6,C6,C6,00,00,00,00
// Including the newline
// Test parameters for bitmap font tests
// Spleen 8x16 is a pure bitmap font at 16px height
// Get glyph index for 'A'
// Verify dimensions match Spleen 8x16
// Verify pixel-perfect rendering
//
// --- Original Ghostty Comments End: src/font/face/freetype.zig

// --- Original Ghostty Comments Start: src/font/face.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/font/face.zig
//
// Face implementation for the compile options.
// If a DPI can't be calculated, this DPI is used. This is probably
// wrong on modern devices so it is highly recommended you get the DPI
// using whatever platform method you can.
// These are the flags to customize how freetype loads fonts. This is
// only non-void if the freetype backend is enabled.
// Options for initializing a font face.
// The desired size for loading a font.
// Desired size in points
// The DPI of the screen so we can convert points to pixels.
// Converts points to pixels
// 1 point = 1/72 inch
// A font variation setting. The best documentation for this I know of
// is actually the CSS font-variation-settings property on MDN:
// https://developer.mozilla.org/en-US/docs/Web/CSS/font-variation-settings
// Converts the ID to a string. The return value is only valid
// for the lifetime of the self pointer.
// The size and position of a glyph.
// Additional options for rendering glyphs.
// The metrics that are defining the grid layout. These are usually
// the metrics of the primary font face. The grid metrics are used
// by the font face to better layout the glyph in situations where
// the font is not exactly the same size as the grid.
// The number of grid cells this glyph will take up. This can be used
// optionally by the rasterizer to better layout the glyph.
// Constraint and alignment properties for the glyph. The rasterizer
// should call the `constrain` function on this with the original size
// and bearings of the glyph to get remapped values that the glyph
// should be scaled/moved to.
// The number of cells, horizontally that the glyph is free to take up
// when resized and aligned by `constraint`. This is usually 1, but if
// there's whitespace to the right of the cell then it can be 2.
// Thicken the glyph. This draws the glyph with a thicker stroke width.
// This is purely an aesthetic setting.
//
// This only works with CoreText currently.
// "Strength" of the thickening, between `0` and `255`.
// Only has an effect when `thicken` is enabled.
//
// `0` does not correspond to *no* thickening,
// just the *lightest* thickening available.
//
// CoreText only.
// See the `constraint` field.
// Don't constrain the glyph in any way.
// Sizing rule.
// Vertical alignment rule.
// Horizontal alignment rule.
// Top padding when resizing.
// Left padding when resizing.
// Right padding when resizing.
// Bottom padding when resizing.
// Size and bearings of the glyph relative
// to the bounding box of its scale group.
// Maximum aspect ratio (width/height) to allow when stretching.
// Maximum number of cells horizontally to use.
// What to use as the height metric when constraining the glyph and
// the constraint width is 1,
// Don't change the size of this glyph.
// Scale the glyph down if needed to fit within the bounds,
// preserving aspect ratio.
// Scale the glyph up or down to exactly match the bounds,
// preserving aspect ratio.
// Scale the glyph down if needed to fit within the bounds,
// preserving aspect ratio. If the glyph doesn't cover a
// single cell, scale up. If the glyph exceeds a single
// cell but is within the bounds, do nothing.
// (Nerd Font specific rule.)
// Stretch the glyph to exactly fit the bounds in both
// directions, disregarding aspect ratio.
// Don't move the glyph on this axis.
// Move the glyph so that its leading (bottom/left)
// edge aligns with the leading edge of the axis.
// Move the glyph so that its trailing (top/right)
// edge aligns with the trailing edge of the axis.
// Move the glyph so that it is centered on this axis.
// Move the glyph so that it is centered on this axis,
// but always with respect to the first cell even for
// multi-cell constraints. (Nerd Font specific rule.)
// Use the full line height of the primary face for
// constraining this glyph.
// Use the icon height from the grid metrics for
// constraining this glyph. Unlike `cell`, the value of
// this height depends on both the constraint width and the
// affected by the `adjust-icon-height` config option.
// Returns true if the constraint does anything. If it doesn't,
// because it neither sizes nor positions the glyph, then this
// returns false.
// Apply this constraint to the provided glyph
// size, given the available width and height.
// Number of cells horizontally available for this glyph.
// Stretched glyphs are usually meant to align across cell
// boundaries, which works best if they're scaled and
// aligned to the grid rather than the face. This is most
// easily done by inserting this little fib in the metrics.
// Negative padding for stretched glyphs is a band-aid to
// avoid gaps due to pixel rounding, but at the cost of
// unsightly overlap artifacts. Since we scale and align to
// the grid rather than the face, we don't need it.
// For extra wide font faces, never stretch glyphs across two cells.
// This mirrors font_patcher.
// The bounding box for the glyph's scale group.
// Scaling and alignment rules are calculated for
// this box and then applied to the glyph.
// Apply prescribed scaling, preserving the
// center bearings of the group bounding box
// NOTE: font_patcher jumps through a lot of hoops at this
// point to ensure that the glyph remains within the target
// bounding box after rounding to font definition units.
// This is irrelevant here as we're not rounding, we're
// staying in f64 and heading straight to rendering.
// Apply prescribed alignment
// Transfer the scaling and alignment back to the glyph and return.
// Return width and height scaling factors for this scaling group.
// Like font-patcher, the icon constraint height depends on the
// constraint width. Unlike font-patcher, the multi-cell
// icon_height may be different from face_height due to the
// `adjust-icon-height` config option.
// Scale down to fit if needed
// Scale to cover
// Scale down to fit or up to cover at least one cell
// NOTE: This is similar to font_patcher's "pa" mode,
// however, font_patcher will only do the upscaling
// part if the constraint width is 1, resulting in
// some icons becoming smaller when the constraint
// width increases. You'd see icons shrinking when
// opening up a space after them. This makes no
// sense, so we've fixed the rule such that these
// icons are scaled to the same size for multi-cell
// constraints as they would be for single-cell.
// Call back into this function with
// constraint width 1 to get single-cell scale
// factors. We use the height factor as width
// could have been modified by max_xy_ratio.
// Reduce aspect ratio if required
// Return vertical bearing for aligning this group
// If we don't have any constraints affecting the vertical axis,
// we don't touch vertical alignment.
// We use face_height and offset by face_y, rather than
// using cell_height directly, to account for the asymmetry
// of the pixel cell around the face (a consequence of
// aligning the baseline with a pixel boundary rather than
// vertically centering the face).
// NOTE: Even if there is no prescribed alignment, we ensure
// that the group doesn't protrude outside the padded cell,
// since this is implied by every available size constraint. If
// the group is too high we fall back to centering, though if we
// hit the .none prong we always have self.size != .none, so
// this should never happen.
// Return horizontal bearing for aligning this group
// If we don't have any constraints affecting the horizontal
// axis, we don't touch horizontal alignment.
// For multi-cell constraints, we align relative to the span
// from the left edge of the first cell to the right edge of
// the last face cell assuming it's left-aligned within the
// rounded and adjusted pixel cell. Any horizontal offset to
// center the face within the grid cell is the responsibility
// of the backend-specific rendering code, and should be done
// after applying constraints.
// NOTE: Even if there is no prescribed alignment, we ensure
// that the glyph doesn't protrude outside the padded cell,
// since this is implied by every available size constraint. The
// left-side bound has priority if the group is too wide, though
// if we hit the .none prong we always have self.size != .none,
// so this should never happen.
// NOTE: .center1 implements the font_patcher rule of centering
// in the first cell even for multi-cell constraints. Since glyphs
// are not allowed to protrude to the left, this results in the
// left-alignment like .start when the glyph is wider than a cell.
// Hardcoded data matches metrics from CoreText at size 12 and DPI 96.
// Define grid metrics (matches font-family = JetBrains Mono)
// ASCII (no constraint).
// BBox of 'x' from JetBrains Mono.
// Any constraint width: do nothing.
// Symbol (same constraint as hardcoded in Renderer.addGlyph).
// BBox of '■' (0x25A0 black square) from Iosevka.
// NOTE: This glyph is designed to span two cells.
// Constraint width 1: scale down and shift to fit a single cell.
// Constraint width 2: do nothing.
// Emoji (same constraint as hardcoded in SharedGrid.renderGlyph).
// BBox of '🥸' (0x1F978) from Apple Color Emoji.
// Constraint width 2: scale to cover two cells with padding, center;
// Nerd Font default.
// Verify that this is the constraint we expect.
// BBox of '' (0xEA61 nf-cod-lightbulb) from Symbols Only.
// NOTE: This icon is part of a group, so the
// constraint applies to a larger bounding box.
// Constraint width 1: scale and shift group to fit a single cell.
// Constraint width 2: no scaling; left-align and vertically center group.
// Nerd Font stretch.
// Verify that this is the constraint we expect.
// BBox of ' ' (0xE0C0 nf-ple-flame_thick) from Symbols Only.
// Constraint width 1: stretch and position to exactly cover one cell.
// Constraint width 1: stretch and position to exactly cover two cells.
//
// --- Original Ghostty Comments End: src/font/face.zig

// Face represents a single font face. A single font face has a single set
// of properties associated with it such as style, weight, etc.
//
// A Face isn't typically meant to be used directly. It is usually used
// via a Collection in order to store it in an Atlas.
//
// Translated from ghostty/src/font/face/freetype.zig
import freetype
import fontconfig
import harfbuzz
import log
import math
import os
import stb
import sync

// ============================================================
// Library
// ============================================================

// Library owns the selected backend library. FreeType uses a shared mutex;
// CoreText and WebCanvas have no native library object.
// A Library can be shared across multiple faces and surfaces.
pub struct Library {
pub mut:
	backend Backend = Backend.selected_()
	lib     freetype.Library
	mutex   &sync.Mutex = unsafe { nil }
}

// init creates a new font Library.
pub fn Library.init() !Library {
	return Library.init_backend(Backend.selected_())
}

// Explicit backend initialization is used for source backend tests and build
// variants; the application calls init with the selected build backend.
pub fn Library.init_backend(backend Backend) !Library {
	if backend.has_freetype() {
		return Library{
			backend: backend
			lib:     freetype.Library.init()!
			mutex:   &sync.Mutex{}
		}
	}
	return Library{
		backend: backend
	}
}

pub fn (mut l Library) deinit() {
	if l.backend.has_freetype() { l.lib.deinit() }
}

// ============================================================
// FreetypeLoadFlags
// ============================================================

// FreetypeLoadFlags controls operations performed during glyph loading.
// Only a subset is exposed for configuration; for the whole set of flags
// see freetype.LoadFlags.
pub struct FreetypeLoadFlags {
	value u8 = 0x19
}

pub fn FreetypeLoadFlags.init(hinting bool, force_autohint bool, monochrome bool, autohint bool, light bool) FreetypeLoadFlags {
	mut value := u8(0)
	if hinting {
		value |= 0x01
	}
	if force_autohint {
		value |= 0x02
	}
	if monochrome {
		value |= 0x04
	}
	if autohint {
		value |= 0x08
	}
	if light {
		value |= 0x10
	}
	return FreetypeLoadFlags{
		value: value
	}
}

pub fn (flags FreetypeLoadFlags) hinting() bool {
	return flags.value & 0x01 != 0
}

pub fn (flags FreetypeLoadFlags) force_autohint() bool {
	return flags.value & 0x02 != 0
}

pub fn (flags FreetypeLoadFlags) monochrome() bool {
	return flags.value & 0x04 != 0
}

pub fn (flags FreetypeLoadFlags) autohint() bool {
	return flags.value & 0x08 != 0
}

pub fn (flags FreetypeLoadFlags) light() bool {
	return flags.value & 0x10 != 0
}

pub fn (flags FreetypeLoadFlags) int_val() u8 {
	return flags.value
}

// format_entry preserves Config.FreetypeLoadFlags's packed-field order.
pub fn (f FreetypeLoadFlags) format_entry() string {
	return [if f.hinting() {
		'hinting'
	} else {
		'no-hinting'
	}, if f.force_autohint() {
		'force-autohint'
	} else {
		'no-force-autohint'
	}, if f.monochrome() {
		'monochrome'
	} else {
		'no-monochrome'
	}, if f.autohint() {
		'autohint'
	} else {
		'no-autohint'
	}, if f.light() {
		'light'
	} else {
		'no-light'
	}].join(',')
}

// Default load flags.
pub const freetype_load_flags_default = FreetypeLoadFlags{}

// ============================================================
// FaceOptions
// ============================================================

// FaceOptions holds options for creating or resizing a font face.
pub struct FaceOptions {
pub mut:
	backend ?Backend
	// The desired font size.
	size DesiredSize
	// Freetype load flags to use when loading glyphs.
	freetype_load_flags FreetypeLoadFlags = freetype_load_flags_default
}

// ============================================================
// Variation
// ============================================================

// VariationId is a 4-byte OpenType variation axis identifier.
pub struct VariationId {
pub:
	value u32
}

// VariationId.init builds an id from a 4-byte axis tag (e.g. "wght").
// The first byte is the most significant, matching the OpenType tag layout.
pub fn VariationId.init(v string) VariationId {
	return VariationId{
		value: u32(v[0]) << 24 | u32(v[1]) << 16 | u32(v[2]) << 8 | u32(v[3])
	}
}

// str returns the 4-character tag representation.
pub fn (id VariationId) str() string {
	bytes := [u8((id.value >> 24) & 0xFF), u8((id.value >> 16) & 0xFF), u8((id.value >> 8) & 0xFF),
		u8(id.value & 0xFF)]
	return bytes.bytestr()
}

// Variation describes a setting for a font variation axis.
pub struct Variation {
pub:
	// The 4-byte axis identifier (e.g., 'wght', 'wdth').
	id VariationId
	// The value for this axis.
	value f64
}

// ============================================================
// GlyphSize
// ============================================================

// GlyphSize holds the position and size of a glyph bounding box
// as f64 values.
pub struct GlyphSize {
pub mut:
	x      f64
	y      f64
	width  f64
	height f64
}

// ============================================================
// FaceMetrics
// ============================================================

// FaceMetrics holds per-face measurement data extracted from font tables.
// These are used to calculate grid-level Metrics via Metrics.calc().
pub struct FaceMetrics {
pub mut:
	// Pixels per em unit.
	px_per_em f64
	// Width of the widest visible ASCII character.
	cell_width f64
	// Ascent from baseline to top of em square (positive).
	ascent f64
	// Descent from baseline to bottom (negative).
	descent f64
	// Line gap (additional leading between lines).
	line_gap f64
	// Underline position (from baseline, negative = below).
	underline_position ?f64
	// Underline thickness.
	underline_thickness ?f64
	// Strikethrough position (from baseline).
	strikethrough_position ?f64
	// Strikethrough thickness.
	strikethrough_thickness ?f64
	// Cap height (height of capital letters like 'H').
	cap_height ?f64
	// x-height (height of lowercase letters like 'x').
	ex_height ?f64
	// Height of the bounding box of visible ASCII characters.
	ascii_height ?f64
	// Advance width of '水' (CJK ideograph), for ic-width sizing.
	ic_width ?f64
}

// line_height returns the total line height (ascent - descent + gap).
pub fn (m FaceMetrics) line_height() f64 {
	return m.ascent - m.descent + m.line_gap
}

// cap_height returns the cap height. If this is not defined in the
// font (or is non-positive), we estimate it as 75% of the ascent.
pub fn (m FaceMetrics) cap_height() f64 {
	if v := m.cap_height {
		if v > 0 {
			return v
		}
	}
	return 0.75 * m.ascent
}

// ex_height returns the ex height. If this is not defined in the
// font (or is non-positive), we estimate it as 75% of the cap height.
pub fn (m FaceMetrics) ex_height() f64 {
	if v := m.ex_height {
		if v > 0 {
			return v
		}
	}
	return 0.75 * m.cap_height()
}

// ascii_height returns the ASCII height. If we couldn't measure it,
// we use 1.5 * cap_height as our estimator, based on measurements across
// programming fonts.
pub fn (m FaceMetrics) ascii_height() f64 {
	if v := m.ascii_height {
		if v > 0 {
			return v
		}
	}
	return 1.5 * m.cap_height()
}

// ic_width returns the ideograph width. If this is not defined in the
// font, we estimate it as the minimum of the ascii height and two cell widths.
pub fn (m FaceMetrics) ic_width() f64 {
	if v := m.ic_width {
		if v > 0 {
			return v
		}
	}
	ah := m.ascii_height()
	two_cell := 2.0 * m.cell_width
	return if ah < two_cell { ah } else { two_cell }
}

// underline_thickness returns the underline thickness. If this is not
// defined in the font, we estimate it as 15% of the ex height.
pub fn (m FaceMetrics) underline_thickness() f64 {
	if v := m.underline_thickness {
		if v > 0 {
			return v
		}
	}
	return 0.15 * m.ex_height()
}

// strikethrough_thickness returns the strikethrough thickness. If this
// is not defined in the font, we set it equal to the underline thickness.
pub fn (m FaceMetrics) strikethrough_thickness() f64 {
	if v := m.strikethrough_thickness {
		if v > 0 {
			return v
		}
	}
	return m.underline_thickness()
}

// NOTE: The getters below return positions, not sizes, so both positive and
// negative values are valid, hence no sign validation.

// underline_position returns the underline position. If this is not
// defined in the font, we place it one underline thickness below the baseline.
pub fn (m FaceMetrics) underline_position() f64 {
	return m.underline_position or { -m.underline_thickness() }
}

// strikethrough_position returns the strikethrough position. If this is
// not defined in the font, we center it at half the ex height, so that it's
// perfectly centered on lower case text.
pub fn (m FaceMetrics) strikethrough_position() f64 {
	return m.strikethrough_position or { (m.ex_height() + m.strikethrough_thickness()) * 0.5 }
}

// ============================================================
// DeferredFace
// ============================================================

// DeferredFace is a font face that hasn't been fully loaded yet.
// It stores enough information (codepoint coverage, presentation)
// to search for fallback fonts without the overhead of full loading.
pub struct DeferredFace {
pub mut:
	// Native discovery state. Fontconfig retains the render-prepared pattern;
	// CoreText retains the discovered CTFont. These preserve Ghostty's
	// deferred coverage and metadata without loading the render face.
	fontconfig_pattern &fontconfig.Pattern = unsafe { nil }
	fontconfig_charset &fontconfig.CharSet = unsafe { nil }
	fontconfig_langset &fontconfig.LangSet = unsafe { nil }
	coretext           CoreTextDeferredFace
	web_canvas         WebCanvasDeferredFace
	// Portable fallback metadata for file-backed deferred values constructed
	// without native discovery. Native Fontconfig/CoreText paths above bypass
	// these fields for metadata and coverage.
	family_name string
	full_name   string
	// The path to the font file, if file-based.
	path string
	// The face index within the font file.
	face_index i32
	// Codepoint coverage map used for has_codepoint() without having to
	// load the face. This is the witty equivalent of the discovery-backed
	// charset (fontconfig) / loaded CT font used by ghostty's
	// DeferredFace.hasCodepoint. A codepoint maps to true if this face
	// covers it. Codepoints not present in the map are not covered.
	codepoints map[u32]bool
	// Presentation advertised by discovery metadata, when known.
	presentation ?Presentation
	// Variation axes selected by discovery/configuration.
	variations []Variation
}

// family_name returns the family name advertised by discovery.
// Fontconfig already owns the copied string; CoreText uses the caller buffer.
pub fn (d DeferredFace) family_name(mut buf []u8) !string {
	if !isnil(d.fontconfig_pattern) {
		return (d.fontconfig_pattern.get(.family, 0)! as fontconfig.ValueString).value
	}
	if !isnil(d.coretext.ct_font) {
		return d.coretext.family_name(mut buf)
	}
	_ = buf
	return d.family_name
}

// name returns the display/full name advertised by discovery.
pub fn (d DeferredFace) name(mut buf []u8) !string {
	if !isnil(d.fontconfig_pattern) {
		return (d.fontconfig_pattern.get(.fullname, 0)! as fontconfig.ValueString).value
	}
	if !isnil(d.coretext.ct_font) {
		return d.coretext.name(mut buf)
	}
	_ = buf
	return d.full_name
}

// deinit releases deferred face resources.
pub fn (mut d DeferredFace) deinit() {
	if !isnil(d.fontconfig_pattern) {
		d.fontconfig_pattern.destroy()
		d.fontconfig_pattern = unsafe { nil }
		d.fontconfig_charset = unsafe { nil }
		d.fontconfig_langset = unsafe { nil }
	}
	d.coretext.deinit()
	d.codepoints = map[u32]bool{}
	d.variations = []
}

// load fully loads this deferred face into a Face.
pub fn (d DeferredFace) load(lib Library, opts FaceOptions) !Face {
	if lib.backend == .web_canvas {
		return Face.from_web_canvas(lib, d.web_canvas.load(opts)!)
	}
	if !isnil(d.fontconfig_pattern) {
		path := (d.fontconfig_pattern.get(.file, 0)! as fontconfig.ValueString).value
		face_index := (d.fontconfig_pattern.get(.index, 0)! as fontconfig.ValueInteger).value
		mut face := Face.init_file(lib, path, face_index, opts)!
		if d.variations.len > 0 {
			face.set_variations(d.variations, opts) or {
				face.deinit()
				return err
			}
		}
		return face
	}
	if !isnil(d.coretext.ct_font) {
		if lib.backend.has_freetype() {
			return d.coretext.load_freetype(lib, opts)
		}
		return Face.from_coretext(lib, d.coretext.load(lib, FaceOptions{
			...opts
			backend: lib.backend
		})!)
	}
	if d.path.len == 0 {
		return error('deferred face has no file path')
	}
	mut face := Face.init_file(lib, d.path, d.face_index, opts)!
	if d.variations.len > 0 {
		face.set_variations(d.variations, opts) or {
			face.deinit()
			return err
		}
	}
	return face
}

// has_codepoint returns true if this face can satisfy the given codepoint
// and presentation. If presentation is none, then it just checks if the
// codepoint is present at all.
//
// Faithful to ghostty's DeferredFace.hasCodepoint: with a discovery
// mechanism this doesn't require the face to be loaded, using the cached
// coverage data (here, the codepoints map). Presentation is ignored for
// coverage in this backend, matching the fact that our coverage map only
// records presence.
pub fn (d DeferredFace) has_codepoint(cp u32, presentation ?Presentation) bool {
	if !isnil(d.fontconfig_pattern) {
		if isnil(d.fontconfig_charset) || !d.fontconfig_charset.has_char(cp) {
			return false
		}
		if expected := presentation {
			actual := if !isnil(d.fontconfig_langset) && d.fontconfig_langset.has_lang('und-zsye') {
				Presentation.emoji
			} else {
				Presentation.text
			}
			return expected == actual
		}
		return true
	}
	if !isnil(d.coretext.ct_font) {
		return d.coretext.has_codepoint(cp, presentation)
	}
	// If we have coverage data, consult it. A codepoint is covered only
	// if it is present in the map with a true value.
	if d.codepoints.len > 0 {
		if !d.codepoints[cp] {
			return false
		}
		if expected := presentation {
			if actual := d.presentation {
				return expected == actual
			}
		}
		return true
	}

	// A deferred face without discovery coverage cannot prove support without
	// loading. Callers which construct file-backed deferred faces must attach
	// their discovery charset, just as the fontconfig backend does in Ghostty.
	_ = cp
	_ = presentation
	return false
}

// ============================================================
// Face
// ============================================================

// V has no packed structs, so FreeType's two synthetic-style flags retain the
// source declaration-order bits in the smallest available integer.
struct FaceSynthetic {
mut:
	value u8
}

fn (synthetic FaceSynthetic) italic() bool {
	return synthetic.value & 0x01 != 0
}

fn (synthetic FaceSynthetic) bold() bool {
	return synthetic.value & 0x02 != 0
}

fn (mut synthetic FaceSynthetic) set_italic(value bool) {
	if value {
		synthetic.value |= 0x01
	} else {
		synthetic.value &= ~u8(0x01)
	}
}

fn (mut synthetic FaceSynthetic) set_bold(value bool) {
	if value {
		synthetic.value |= 0x02
	} else {
		synthetic.value &= ~u8(0x02)
	}
}

// Face delegates to the implementation selected by font/face.zig.
pub struct Face {
pub mut:
	backend    Backend = Backend.selected_()
	coretext   CoreTextFace
	web_canvas WebCanvasFace
	// Our Library.
	lib Library
	// Our font face.
	face freetype.Face
	// Harfbuzz font corresponding to this face.
	hb_font harfbuzz.Font
	// CoreText font created from the same source. The CoreText shaper must
	// copy this exact face rather than resolving an installed font by name.
	ct_font voidptr = unsafe { nil }
	// FreeType exposes one mutable glyph slot per face. Rendering and metrics
	// measurement therefore serialize access to that slot.
	ft_mutex &sync.Mutex = unsafe { nil }
	// Freetype load flags for this font face.
	load_flags FreetypeLoadFlags
	// Set quirks.disableDefaultFontFeatures.
	quirks_disable_default_font_features bool
	// Synthetic italic and bold flags.
	synthetic FaceSynthetic
	// The current size this font is set to.
	size DesiredSize
}

// init_file initializes a new font face from a file path.
pub fn Face.init_file(lib Library, path string, index i32, opts FaceOptions) !Face {
	if !lib.backend.has_freetype() {
		return Face.init_mem(lib, os.read_bytes(path)!, opts)
	}
	assert !isnil(lib.mutex)
	lib.mutex.lock()
	defer { lib.mutex.unlock() }
	mut ft_face := lib.lib.init_face(path, index)!
	return init_freetype_face(lib, mut ft_face, opts)
}

pub fn Face.init_mem(lib Library, source []u8, opts FaceOptions) !Face {
	if !lib.backend.has_freetype() {
		if lib.backend == .web_canvas {
			return error('WebCanvas fonts use init_named rather than embedded font files')
		}
		return Face.from_coretext(lib, CoreTextFace.init(lib, source, FaceOptions{
			...opts
			backend: lib.backend
		})!)
	}
	assert !isnil(lib.mutex)
	lib.mutex.lock()
	defer { lib.mutex.unlock() }
	mut ft_face := lib.lib.init_memory_face(source, 0)!
	return init_freetype_face(lib, mut ft_face, opts)
}

pub fn Face.init_named(lib Library, name string, presentation Presentation, opts FaceOptions) !Face {
	assert lib.backend == .web_canvas
	return Face.from_web_canvas(lib, WebCanvasFace.init_named(name, opts.size, presentation)!)
}

fn Face.from_coretext(lib Library, native CoreTextFace) Face {
	return Face{
		backend:                              lib.backend
		lib:                                  lib
		coretext:                             native
		ct_font:                              native.ct_font
		hb_font:                              native.hb_font
		quirks_disable_default_font_features: native.quirks_disable_default_font_features
		size:                                 native.size
	}
}

fn Face.from_web_canvas(lib Library, native WebCanvasFace) Face {
	return Face{
		backend:    lib.backend
		lib:        lib
		web_canvas: native
		size:       native.size
	}
}

fn (mut self Face) update_coretext_aliases() {
	self.ct_font = self.coretext.ct_font
	self.hb_font = self.coretext.hb_font
	self.quirks_disable_default_font_features = self.coretext.quirks_disable_default_font_features
	self.size = self.coretext.size
}

fn init_freetype_face(lib Library, mut ft_face freetype.Face, opts FaceOptions) !Face {
	ft_face.select_charmap(.unicode) or {
		ft_face.deinit()
		return err
	}
	set_freetype_size(ft_face, opts.size) or {
		ft_face.deinit()
		return err
	}
	hb_font := harfbuzz.Font.create_freetype(ft_face.handle) or {
		ft_face.deinit()
		return err
	}
	mut result := Face{
		backend:    lib.backend
		lib:        lib
		face:       ft_face
		hb_font:    hb_font
		ft_mutex:   &sync.Mutex{}
		load_flags: opts.freetype_load_flags
		size:       opts.size
	}
	result.quirks_disable_default_font_features = quirks.disable_default_font_features(&result)

	// In debug mode, output the available variation axes when they exist.
	$if debug {
		if result.face.has_multiple_masters() {
			mut name_buf := []u8{len: 1024}
			font_name := result.name(mut name_buf) or {
				result.hb_font.destroy()
				result.face.deinit()
				return err
			}
			log.debug('variation axes font=${font_name}')

			mut mm := result.face.get_mm_var() or {
				result.hb_font.destroy()
				result.face.deinit()
				return err
			}
			defer { result.lib.lib.done_mm_var(&mm) }
			for axis in mm.axis {
				if axis.tag > u64(0x7fff_ffff) {
					continue
				}
				id := VariationId{
					value: u32(axis.tag)
				}
				log.debug('variation axis: name=${axis.name} id=${id.str()} min=${axis.minimum >> 16} max=${axis.maximum >> 16} def=${axis.def >> 16}')
			}
		}
	}
	return result
}

// deinit destroys this face and releases all resources.
pub fn (mut self Face) deinit() {
	if self.backend == .web_canvas {
		self.web_canvas.deinit()
		return
	}
	if !self.backend.has_freetype() {
		self.coretext.deinit()
		self.update_coretext_aliases()
		return
	}
	if !isnil(self.lib.mutex) {
		self.lib.mutex.lock()
		self.face.deinit()
		self.lib.mutex.unlock()
	} else {
		self.face.deinit()
	}
	self.hb_font.destroy()
}

// name returns the font name. Reads the SFNT name table to find
// the font family entry.
//
// If allocation is required, buf will be used, but sometimes
// allocation isn't required and a static string is returned.
pub fn (self &Face) name(mut buf []u8) !string {
	if self.backend == .web_canvas { return self.web_canvas.font_str }
	if !self.backend.has_freetype() { return self.coretext.name(mut buf) }
	count := self.face.get_sfnt_name_count()

	// We look for the font family entry.
	for i in 0 .. count {
		entry := self.face.get_sfnt_name(i) or { continue }
		if entry.name_id == freetype.tt_name_id_font_family {
			str_data := entry.string_data
			// There are other encodings that are something other than UTF-8
			// but this is one we've seen "in the wild" so far.
			if entry.platform_id == freetype.tt_platform_microsoft
				&& entry.encoding_id == freetype.tt_ms_id_unicode_cs {
				if str_data.len % 2 != 0 || str_data.len > 1024 {
					return str_data.bytestr()
				}
				decoded := decode_utf16_be(str_data) or { return str_data.bytestr() }
				if decoded.len > buf.len {
					return error('font family name does not fit output buffer')
				}
				for j, b in decoded.bytes() {
					buf[j] = b
				}
				return buf[..decoded.len].bytestr()
			}
			return str_data.bytestr()
		}
	}

	return ''
}

fn decode_utf16_be(data []u8) ?string {
	if data.len % 2 != 0 {
		return none
	}
	mut result := []rune{cap: data.len / 2}
	mut i := 0
	for i < data.len {
		unit := u16(data[i]) << 8 | u16(data[i + 1])
		i += 2
		if unit >= 0xd800 && unit <= 0xdbff {
			if i >= data.len {
				return none
			}
			low := u16(data[i]) << 8 | u16(data[i + 1])
			if low < 0xdc00 || low > 0xdfff {
				return none
			}
			i += 2
			result << rune(0x10000 + ((u32(unit) - 0xd800) << 10) + (u32(low) - 0xdc00))
		} else if unit >= 0xdc00 && unit <= 0xdfff {
			return none
		} else {
			result << rune(unit)
		}
	}
	return result.string()
}

// synthetic_bold_face returns a new face that is the same as this but
// also has synthetic bold applied.
pub fn (self &Face) synthetic_bold_face(opts FaceOptions) !Face {
	if !self.backend.has_freetype() {
		return Face.from_coretext(self.lib, self.coretext.synthetic_bold(FaceOptions{
			...opts
			backend: self.backend
		})!)
	}
	self.face.ref()
	mut ft_face := self.face
	mut f := init_freetype_face(self.lib, mut ft_face, opts)!
	f.synthetic = self.synthetic
	f.synthetic.set_bold(true)
	return f
}

// synthetic_italic_face returns a new face that is the same as this but
// has a transformation matrix applied to italicize it.
pub fn (self &Face) synthetic_italic_face(opts FaceOptions) !Face {
	if !self.backend.has_freetype() {
		return Face.from_coretext(self.lib, self.coretext.synthetic_italic(FaceOptions{
			...opts
			backend: self.backend
		})!)
	}
	self.face.ref()
	mut ft_face := self.face
	mut f := init_freetype_face(self.lib, mut ft_face, opts)!
	f.synthetic = self.synthetic
	f.synthetic.set_italic(true)
	return f
}

// set_face_size resizes the font in-place. If this succeeds, the caller
// is responsible for clearing any glyph caches, font atlas data, etc.
pub fn (mut self Face) set_face_size(opts FaceOptions) ! {
	if self.backend == .web_canvas {
		self.web_canvas.set_size(opts.size)!
		self.size = opts.size
		return
	}
	if !self.backend.has_freetype() {
		self.coretext.set_size(FaceOptions{ ...opts, backend: self.backend })!
		self.update_coretext_aliases()
		return
	}
	set_freetype_size(self.face, opts.size)!
	self.size = opts.size
}

fn set_freetype_size(face freetype.Face, size DesiredSize) ! {
	if face.is_scalable() {
		face.set_char_size(0, i32(math.round(f64(size.points) * 64.0)), size.xdpi, size.ydpi)!
		return
	}
	select_size_nearest(face, u32(math.round(size.pixels())))!
}

fn select_size_nearest(face freetype.Face, size u32) ! {
	count := face.num_fixed_sizes()
	if count == 0 {
		return error('font has no selectable fixed sizes')
	}
	mut best_i := 0
	mut best_diff := i64(0)
	for i in 0 .. count {
		diff := i64(size) - i64(face.fixed_size_width(i))
		if i == 0 || diff < best_diff {
			best_diff = diff
			best_i = i
		}
	}
	face.select_size(i32(best_i))!
}

// set_variations sets the variation axes for this font.
// This will modify this font in-place.
pub fn (mut self Face) set_variations(vs []Variation, opts FaceOptions) ! {
	if self.backend == .web_canvas { return }
	if !self.backend.has_freetype() {
		self.coretext.set_variations(vs, FaceOptions{ ...opts, backend: self.backend })!
		self.update_coretext_aliases()
		return
	}
	_ = opts

	// If this font doesn't support variations, we can't do anything.
	if !self.face.has_multiple_masters() || vs.len == 0 {
		return
	}

	// Freetype requires that we send ALL coordinates in at once so the
	// first thing we have to do is get all the vars and put them into
	// an array.
	mut mm := self.face.get_mm_var()!
	defer {
		self.lib.lib.done_mm_var(&mm)
	}

	// To avoid allocations, we cap the number of variation axes we can
	// support. This is arbitrary but Firefox caps this at 16 so I
	// feel like that's probably safe... and we do double cause its
	// cheap.
	max_axes := if mm.num_axis < 32 { mm.num_axis } else { u32(32) }
	mut coords := []i64{len: int(max_axes)}
	self.face.get_var_design_coordinates(mut coords)!

	// Now we go through each axis and see if its set. This is slow
	// but there usually aren't many axes and usually not many set
	// variations, either.
	for i in 0 .. mm.num_axis {
		axis := mm.axis[i]
		for v in vs {
			if u32(axis.tag) == v.id.value {
				coords[i] = i64(v.value * 65536)
				break
			}
		}
	}

	// Set them!
	self.face.set_var_design_coordinates(coords)!
}

// glyph_index returns the glyph index for the given Unicode code point.
// If this face doesn't support this glyph, none is returned.
pub fn (self Face) glyph_index(cp u32) ?u32 {
	if self.backend == .web_canvas { return self.web_canvas.glyph_index(cp) }
	if !self.backend.has_freetype() { return self.coretext.glyph_index(cp) }
	return self.face.get_char_index(cp)
}

// has_color returns true if this font is colored. This can be used by
// callers to determine what kind of atlas to pass in.
pub fn (self Face) has_color() bool {
	if self.backend == .web_canvas { return self.web_canvas.presentation == .emoji }
	if !self.backend.has_freetype() { return self.coretext.has_color() }
	return self.face.has_color()
}

// is_color_glyph returns true if the given glyph ID is colorized.
pub fn (self &Face) is_color_glyph(glyph_id u32) bool {
	if self.backend == .web_canvas { return self.web_canvas.presentation == .emoji }
	if !self.backend.has_freetype() { return self.coretext.is_color_glyph(glyph_id) }
	assert !isnil(self.ft_mutex)
	self.ft_mutex.lock()
	defer {
		self.ft_mutex.unlock()
	}
	// Load the glyph and see what pixel mode it renders with.
	// All modes other than BGRA are non-color.
	// If the glyph fails to load, just return false.
	mut flags := freetype.LoadFlags{}
	flags.set_render(true)
	flags.set_color(self.face.has_color())
	// NO_SVG set to true because we don't currently support rendering
	// SVG glyphs under FreeType, since that requires bundling another
	// dependency to handle rendering the SVG.
	flags.set_no_svg(true)
	self.face.load_glyph(glyph_id, flags) or { return false }

	glyph := self.face.glyph() or { panic('FreeType returned no glyph slot') }
	return glyph.bitmap.pixel_mode == freetype.pixel_mode_bgra
}

// glyph_load_flags returns the LoadFlags to use when loading a glyph
// for measurement or rendering.
//
// Hinting should only be enabled if the configured load flags specify
// it and the provided constraint doesn't actually do anything, since
// if it does, then it'll mess up the hinting anyway when it moves or
// resizes the glyph.
fn (self Face) glyph_load_flags(constrained bool) freetype.LoadFlags {
	do_hinting := self.load_flags.hinting() && !constrained

	mut flags := freetype.LoadFlags{}
	// If our glyph has color, we want to render the color.
	flags.set_color(self.face.has_color())
	// We don't render, because we'll invoke the render manually after applying
	// constraints further down. Use options from config.
	flags.set_render(false)
	flags.set_no_hinting(!do_hinting)
	flags.set_force_autohint(self.load_flags.force_autohint())
	flags.set_no_autohint(!self.load_flags.autohint())
	// Match the monochrome/light/normal hinter to the configured renderer.
	flags.set_target(if self.load_flags.monochrome() {
		.mono
	} else if self.load_flags.light() {
		.light
	} else {
		.normal
	})
	// SVG rendering requires a separate dependency that isn't enabled.
	flags.set_no_svg(true)
	return flags
}

// get_glyph_size returns a rect representing the position and size
// of the loaded glyph.
fn get_glyph_size(glyph &freetype.GlyphSlotRec) GlyphSize {
	// If we're dealing with an outline glyph then we get the
	// outline's bounding box instead of using the built-in
	// metrics, since that's more precise and allows better
	// cell-fitting.
	if glyph.format == freetype.glyph_format_outline {
		// Get the glyph's bounding box before we transform it at all.
		// We use this rather than the metrics, since it's more precise.
		mut bbox := freetype.BBox{}
		freetype.outline_get_bbox(&glyph.outline, mut bbox)

		return GlyphSize{
			x:      freetype.f26dot6_to_f64(bbox.x_min)
			y:      freetype.f26dot6_to_f64(bbox.y_min)
			width:  freetype.f26dot6_to_f64(bbox.x_max - bbox.x_min)
			height: freetype.f26dot6_to_f64(bbox.y_max - bbox.y_min)
		}
	}

	return GlyphSize{
		x:      freetype.f26dot6_to_f64(glyph.metrics.hori_bearing_x)
		y:      freetype.f26dot6_to_f64(glyph.metrics.hori_bearing_y - glyph.metrics.height)
		width:  freetype.f26dot6_to_f64(glyph.metrics.width)
		height: freetype.f26dot6_to_f64(glyph.metrics.height)
	}
}

// render_glyph renders a glyph using the glyph index. The rendered glyph
// is stored in the given texture atlas.
pub fn (self Face) render_glyph(mut atlas Atlas, glyph_index u32, opts RenderOptions) !Glyph {
	opts.assert_narrow_widths()
	if self.backend == .web_canvas {
		return self.web_canvas.render_glyph(mut atlas, glyph_index, opts)
	}
	if !self.backend.has_freetype() {
		return self.coretext.render_glyph(mut atlas, glyph_index, opts)
	}
	assert !isnil(self.ft_mutex)
	self.ft_mutex.lock()
	defer {
		self.ft_mutex.unlock()
	}

	self.face.load_glyph(glyph_index, self.glyph_load_flags(opts.constraint.does_anything()))!
	mut glyph := self.face.glyph() or { panic('FreeType returned no glyph slot') }

	if self.synthetic.bold() && glyph.format == freetype.glyph_format_outline {
		size_metrics := self.face.size_metrics() or { panic('FreeType face has no size metrics') }
		amount := i64(math.ceil(f64(size_metrics.height) * (64.0 / 2048.0)))
		freetype.outline_embolden(mut glyph.outline, amount)
		glyph = self.face.glyph() or { panic('FreeType returned no glyph slot') }
	}

	rect := get_glyph_size(&glyph)
	if rect.width < 0.25 || rect.height < 0.25 {
		return Glyph{}
	}

	metrics := opts.grid_metrics
	cell_width := f64(metrics.cell_width)
	cell_height := f64(metrics.cell_height)
	cell_baseline := f64(metrics.cell_baseline)
	glyph_size := opts.constraint.constrain(GlyphSize{
		width:  rect.width
		height: rect.height
		x:      rect.x
		y:      rect.y + cell_baseline
	}, metrics, opts.constraint_width)
	mut width := glyph_size.width
	mut height := glyph_size.height
	mut x := glyph_size.x
	mut y := glyph_size.y

	if opts.constraint.size != .stretch && metrics.face_width < cell_width {
		x += math.round((cell_width - metrics.face_width) / 2.0)
	}
	if glyph.format == freetype.glyph_format_bitmap {
		width = cell_width - math.round(cell_width - width - x) - math.round(x)
		height = cell_height - math.round(cell_height - height - y) - math.round(y)
		x = math.round(x)
		y = math.round(y)
	}

	mut bitmap := freetype.Bitmap{}
	freetype.bitmap_init(mut bitmap)
	defer {
		freetype.bitmap_done(self.lib.lib, mut bitmap)
	}
	mut bitmap_left := glyph.bitmap_left
	mut bitmap_top := glyph.bitmap_top

	match glyph.format {
		freetype.glyph_format_outline {
			scale_x := width / rect.width
			scale_y := height / rect.height
			skew := if self.synthetic.italic() { math.tan(12.0 * math.pi / 180.0) } else { 0.0 }
			point_count := freetype.outline_points_len(&glyph.outline)
			for i in 0 .. point_count {
				point := freetype.outline_point(&glyph.outline, i)
				mut px := freetype.f26dot6_to_f64(point.x)
				mut py := freetype.f26dot6_to_f64(point.y)
				px = (px - rect.x) * scale_x + x
				py = (py - rect.y) * scale_y + y - cell_baseline
				px += py * skew
				freetype.outline_set_point(mut glyph.outline, i, freetype.OutlinePoint{
					x: i64(math.round(px * 64.0))
					y: i64(math.round(py * 64.0))
				})
			}
			self.face.render_glyph(if self.load_flags.monochrome() { .mono } else { .normal })!
			glyph = self.face.glyph() or { panic('FreeType returned no rendered glyph') }
			freetype.bitmap_convert(self.lib.lib, &glyph.bitmap, mut bitmap, 1)!
			bitmap_left = glyph.bitmap_left
			bitmap_top = glyph.bitmap_top
		}
		freetype.glyph_format_bitmap {
			mut source := glyph.bitmap
			mut converted := freetype.Bitmap{}
			mut converted_initialized := false
			if source.pixel_mode != freetype.pixel_mode_bgra
				&& source.pixel_mode != freetype.pixel_mode_gray {
				freetype.bitmap_init(mut converted)
				converted_initialized = true
				freetype.bitmap_convert(self.lib.lib, &source, mut converted, 1)!
				source = converted
			}
			defer {
				if converted_initialized {
					freetype.bitmap_done(self.lib.lib, mut converted)
				}
			}

			w := u32(math.round(width))
			h := u32(math.round(height))
			pitch := w * atlas.format.depth()
			mut scaled := []u8{len: int(pitch * h)}
			if source.buffer == unsafe { nil } || !unsafe {
				stb.stbir_resize_uint8(source.buffer, int(source.width), int(source.rows), int(source.pitch), &scaled[0], int(w), int(h), int(pitch), int(atlas.format.depth())) != 0
			} {
				return error('glyph bitmap resize failed')
			}
			scaled_bitmap := freetype.Bitmap{
				buffer:     unsafe { &scaled[0] }
				width:      w
				rows:       h
				pitch:      i32(pitch)
				pixel_mode: source.pixel_mode
				num_grays:  source.num_grays
			}
			freetype.bitmap_copy(self.lib.lib, &scaled_bitmap, mut bitmap)!
			bitmap_top = i32(math.floor(y - cell_baseline + height))
			bitmap_left = i32(math.floor(x))
		}
		else {
			log.error('Can\'t render glyph with unsupported glyph format "${freetype.Tag{
				value: glyph.format
			}.str()}"')
			return error('UnsupportedGlyphFormat')
		}
	}

	match bitmap.pixel_mode {
		freetype.pixel_mode_gray {
			if atlas.format != .grayscale {
				return error('grayscale glyph requires grayscale atlas')
			}
		}
		freetype.pixel_mode_bgra {
			if atlas.format != .bgra {
				return error('color glyph requires BGRA atlas')
			}
		}
		else {
			log.warn('glyph=${glyph_index} pixel mode=${bitmap.pixel_mode}')
			panic('unsupported pixel mode')
		}
	}

	px_width := bitmap.width
	px_height := bitmap.rows
	row_bytes := u32(if bitmap.pitch < 0 { -bitmap.pitch } else { bitmap.pitch })
	len := int(row_bytes * px_height)
	mut pixels := unsafe { bitmap.buffer.vbytes(len) }
	if bitmap.pixel_mode == freetype.pixel_mode_gray && bitmap.num_grays < 256 {
		factor := u8(255 / (bitmap.num_grays - 1))
		for mut pixel in pixels {
			pixel *= factor
		}
		bitmap.num_grays = 256
	}
	// FreeType Face.renderGlyph relies on these source invariants. A negative
	// pitch is not a supported alternate layout here.
	assert px_width > 0 && px_height > 0
	assert i64(px_width * atlas.format.depth()) == i64(bitmap.pitch)

	region := atlas.reserve(px_width, px_height)!
	atlas.set(region, pixels)
	px_y := bitmap_top + i32(metrics.cell_baseline) - i32(px_height)
	return Glyph{
		width:    px_width
		height:   px_height
		offset_x: bitmap_left
		offset_y: px_y + i32(px_height)
		atlas_x:  region.x
		atlas_y:  region.y
	}
}

// units_to_px_y converts font design units to pixels based on the
// y-scale factor of the current font size.
fn (self Face) units_to_px_y(units i32) i32 {
	metrics := self.face.size_metrics() or { panic('FreeType face has no size metrics') }
	return i32(freetype.mul_fix(units, i32(metrics.y_scale)) >> 6)
}

// get_metrics returns the FaceMetrics for this face.
//
// This reads metrics from multiple sources:
// - FreeType size metrics (ascender, descender, height, max_advance)
// - 'head' table (Units_Per_EM)
// - 'post' table (underlinePosition, underlineThickness)
// - 'OS/2' table (sTypoAscender/Descender/LineGap, fsSelection,
//   usWinAscent/Descent, sCapHeight, sxHeight, yStrikeoutSize/Position)
// - 'hhea' table (Ascender, Descender, Line_Gap)
//
// Cell width is calculated by measuring all visible ASCII characters
// and taking the widest advance width.
//
// Cap height and ex height are either from OS/2 (v2+) or measured
// from the 'H' and 'x' glyphs respectively.
//
// IC width is measured from '水' (U+6C34).
pub fn (mut self Face) get_metrics() FaceMetrics {
	// The pinned WebCanvas face exposes cell metrics, not getMetrics. Native
	// Collection has no supported WebCanvas instantiation in that revision.
	assert self.backend != .web_canvas
	if !self.backend.has_freetype() { return self.coretext.get_metrics() }
	face := self.face
	size_metrics := face.size_metrics() or { panic('FreeType face has no size metrics') }

	// This code relies on this assumption, and it should always be
	// true since we don't do any non-uniform scaling on the font ever.
	assert size_metrics.x_ppem == size_metrics.y_ppem

	// Whether the font is in a scalable format.
	is_scalable := face.is_scalable()

	// We get the UPM from the head table.
	// If we have no head, but it is a scalable face, take the UPM from
	// FreeType's units_per_EM, otherwise we'll assume that UPM == PPEM.
	head := face.get_sfnt_table_head()
	units_per_em := if h := head {
		h.units_per_em
	} else if is_scalable {
		face.units_per_em()
	} else {
		size_metrics.y_ppem
	}
	px_per_em := f64(size_metrics.y_ppem)
	px_per_unit := px_per_em / f64(units_per_em)

	// Read the 'post' table.
	post := face.get_sfnt_table_post()
	// Read the 'OS/2' table.
	os2_raw := face.get_sfnt_table_os2()
	os2 := if o := os2_raw {
		if o.version != 0xFFFF { os2_raw } else { ?&freetype.TT_OS2(none) }
	} else {
		?&freetype.TT_OS2(none)
	}
	// Read the 'hhea' table.
	hhea := face.get_sfnt_table_hhea()

	// --- Vertical metrics ---
	mut ascent := f64(0)
	mut descent := f64(0)
	mut line_gap := f64(0)

	if h := hhea {
		hhea_ascent := f64(h.ascender)
		hhea_descent := f64(h.descender)
		hhea_line_gap := f64(h.line_gap)

		if o := os2 {
			os2_ascent := f64(o.s_typo_ascender)
			os2_descent := f64(o.s_typo_descender)
			os2_line_gap := f64(o.s_typo_line_gap)

			// If the font says to use typo metrics, trust it.
			// (The USE_TYPO_METRICS bit is bit 7)
			if o.fs_selection & (1 << 7) != 0 {
				ascent = os2_ascent * px_per_unit
				descent = os2_descent * px_per_unit
				line_gap = os2_line_gap * px_per_unit
			} else if h.ascender != 0 || h.descender != 0 {
				// Otherwise prefer hhea metrics if available.
				ascent = hhea_ascent * px_per_unit
				descent = hhea_descent * px_per_unit
				line_gap = hhea_line_gap * px_per_unit
			} else if os2_ascent != 0 || os2_descent != 0 {
				ascent = os2_ascent * px_per_unit
				descent = os2_descent * px_per_unit
				line_gap = os2_line_gap * px_per_unit
			} else {
				win_ascent := f64(o.us_win_ascent)
				win_descent := f64(o.us_win_descent)
				ascent = win_ascent * px_per_unit
				// usWinDescent is *positive* -> down, so flip sign.
				descent = -win_descent * px_per_unit
				line_gap = 0.0
			}
		} else {
			// No OS/2, use hhea blindly.
			ascent = hhea_ascent * px_per_unit
			descent = hhea_descent * px_per_unit
			line_gap = hhea_line_gap * px_per_unit
		}
	} else {
		// No hhea table, rely on FreeType metrics.
		ascent = freetype.f26dot6_to_f64(size_metrics.ascender)
		descent = freetype.f26dot6_to_f64(size_metrics.descender)
		h := freetype.f26dot6_to_f64(size_metrics.height)
		// line_gap = height + descender - ascender
		line_gap = h + descent - ascent
	}

	// --- Underline ---
	mut underline_position := ?f64(none)
	mut underline_thickness := ?f64(none)
	if p := post {
		has_broken_underline := p.underline_thickness == 0
		if !(has_broken_underline && p.underline_position == 0) {
			underline_position = f64(p.underline_position) * px_per_unit
		}
		if !has_broken_underline {
			underline_thickness = f64(p.underline_thickness) * px_per_unit
		}
	}

	// --- Strikethrough ---
	mut strikethrough_position := ?f64(none)
	mut strikethrough_thickness := ?f64(none)
	if o := os2 {
		has_broken_st := o.y_strikeout_size == 0
		if !(has_broken_st && o.y_strikeout_position == 0) {
			strikethrough_position = f64(o.y_strikeout_position) * px_per_unit
		}
		if !has_broken_st {
			strikethrough_thickness = f64(o.y_strikeout_size) * px_per_unit
		}
	}

	// --- Cell width and visible-ASCII bounding height ---
	mut cell_width := f64(0)
	mut ascii_top := f64(0)
	mut ascii_bottom := f64(0)
	assert !isnil(self.ft_mutex)
	self.ft_mutex.lock()
	for cp := u32(32); cp < 127; cp++ {
		if glyph_index := face.get_char_index(cp) {
			face.load_glyph(glyph_index, self.glyph_load_flags(false)) or { continue }
			glyph := face.glyph() or { panic('FreeType returned no glyph slot') }
			advance := freetype.f26dot6_to_f64(glyph.advance.x)
			cell_width = math.max(cell_width, advance)
			rect := get_glyph_size(&glyph)
			ascii_top = math.max(ascii_top, rect.y + rect.height)
			ascii_bottom = math.min(ascii_bottom, rect.y)
		}
	}
	self.ft_mutex.unlock()
	if cell_width == 0.0 {
		cell_width = freetype.f26dot6_to_f64(size_metrics.max_advance)
	}
	ascii_estimate := ascii_top - ascii_bottom
	mut ascii_height := if ascii_estimate > 0.0 { ?f64(ascii_estimate) } else { ?f64(none) }

	// --- Cap height / ex height ---
	mut cap_height := ?f64(none)
	mut ex_height := ?f64(none)
	if o := os2 {
		if o.version >= 2 {
			cap_height = f64(o.s_cap_height) * px_per_unit
			ex_height = f64(o.sx_height) * px_per_unit
		}
	}
	if cap_height == none {
		cap_height = self.measure_glyph_height(u32(`H`))
		ex_height = self.measure_glyph_height(u32(`x`))
	}

	// Measure '水' for the CSS ic unit. Reject patched fonts whose
	// ideograph bounding box is wider than its advance.
	mut ic_width := self.measure_ic_width()

	return FaceMetrics{
		px_per_em:               px_per_em
		cell_width:              cell_width
		ascent:                  ascent
		descent:                 descent
		line_gap:                line_gap
		underline_position:      underline_position
		underline_thickness:     underline_thickness
		strikethrough_position:  strikethrough_position
		strikethrough_thickness: strikethrough_thickness
		cap_height:              cap_height
		ex_height:               ex_height
		ascii_height:            ascii_height
		ic_width:                ic_width
	}
}

fn (self &Face) measure_glyph_height(cp u32) ?f64 {
	assert !isnil(self.ft_mutex)
	self.ft_mutex.lock()
	defer {
		self.ft_mutex.unlock()
	}
	glyph_index := self.face.get_char_index(cp) or { return none }
	self.face.load_glyph(glyph_index, self.glyph_load_flags(false)) or { return none }
	glyph := self.face.glyph() or { panic('FreeType returned no glyph slot') }
	return get_glyph_size(&glyph).height
}

fn (self &Face) measure_ic_width() ?f64 {
	assert !isnil(self.ft_mutex)
	self.ft_mutex.lock()
	defer {
		self.ft_mutex.unlock()
	}
	glyph_index := self.face.get_char_index(0x6c34) or { return none }
	self.face.load_glyph(glyph_index, self.glyph_load_flags(false)) or { return none }
	glyph := self.face.glyph() or { panic('FreeType returned no glyph slot') }
	advance := freetype.f26dot6_to_f64(glyph.advance.x)
	glyph_width := get_glyph_size(&glyph).width
	if glyph_width > advance {
		mut name_buf := []u8{len: 1024}
		font_name := self.name(mut name_buf) or { '<Error getting font name>' }
		log.warn('(getMetrics) Width of glyph \'水\' for font "${font_name}" is greater than its advance (${glyph_width} > ${advance}), discarding ic_width metric.')
		return none
	}
	return advance
}

// copy_table copies the optional font table data for the given tag.
pub fn (self Face) copy_table(tag string) !freetype.SfntTableValue {
	if !self.backend.has_freetype() {
		data := self.coretext.copy_table(tag) or { return freetype.SfntTableValue{} }
		return freetype.SfntTableValue{
			has_value: true
			data:      data
		}
	}
	return self.face.load_sfnt_table(freetype.Tag.init(tag))
}

// ============================================================
// Constraint.constrain (from face.zig)
// ============================================================

// constrain applies this constraint to the provided glyph size, given the
// available width and height. constraint_width is the number of cells
// horizontally available for this glyph.
//
// Translated from ghostty/src/font/face.zig RenderOptions.Constraint.constrain
pub fn (self Constraint) constrain(glyph GlyphSize, metrics Metrics, constraint_width u32) GlyphSize {
	assert constraint_width <= 3
	assert self.max_constraint_width <= 3
	if !self.does_anything() {
		return glyph
	}

	if self.size == .stretch {
		// Stretched glyphs are usually meant to align across cell
		// boundaries, which works best if they're scaled and aligned to the
		// grid rather than the face. This is most easily done by inserting
		// this little fib in the metrics.
		mut m := metrics
		m.face_width = f64(m.cell_width)
		m.face_height = f64(m.cell_height)
		m.face_y = 0.0

		// Negative padding for stretched glyphs is a band-aid to avoid gaps
		// due to pixel rounding, but at the cost of unsightly overlap
		// artifacts. Since we scale and align to the grid rather than the
		// face, we don't need it.
		mut c := self
		c.pad_bottom = math.max(0.0, c.pad_bottom)
		c.pad_top = math.max(0.0, c.pad_top)
		c.pad_left = math.max(0.0, c.pad_left)
		c.pad_right = math.max(0.0, c.pad_right)

		return c.constrain_inner(glyph, m, constraint_width)
	}

	return self.constrain_inner(glyph, metrics, constraint_width)
}

// constrain_inner performs the core constraint math for a glyph.
fn (self Constraint) constrain_inner(glyph GlyphSize, metrics Metrics, constraint_width u32) GlyphSize {
	// For extra wide font faces, never stretch glyphs across two cells.
	// This mirrors font_patcher.
	min_constraint_width := if self.size == .stretch
		&& metrics.face_width > 0.9 * metrics.face_height {
		u32(1)
	} else {
		// @min(self.max_constraint_width, constraint_width)
		mcw := u32(self.max_constraint_width)
		if mcw < constraint_width {
			mcw
		} else {
			constraint_width
		}
	}

	// The bounding box for the glyph's scale group. Scaling and alignment
	// rules are calculated for this box and then applied to the glyph.
	group_width := glyph.width / self.relative_width
	group_height := glyph.height / self.relative_height
	mut group := GlyphSize{
		width:  group_width
		height: group_height
		x:      glyph.x - (group_width * self.relative_x)
		y:      glyph.y - (group_height * self.relative_y)
	}

	// Apply prescribed scaling, preserving the
	// center bearings of the group bounding box.
	width_factor, height_factor := self.scale_factors(group, metrics, min_constraint_width)
	center_x := group.x + (group.width / 2)
	center_y := group.y + (group.height / 2)
	group.width *= width_factor
	group.height *= height_factor
	group.x = center_x - (group.width / 2)
	group.y = center_y - (group.height / 2)

	// NOTE: font_patcher jumps through a lot of hoops at this point to ensure
	// that the glyph remains within the target bounding box after rounding to
	// font definition units. This is irrelevant here as we're not rounding,
	// we're staying in f64 and heading straight to rendering.

	// Apply prescribed alignment.
	group.y = self.aligned_y(group, metrics)
	group.x = self.aligned_x(group, metrics, min_constraint_width)

	// Transfer the scaling and alignment back to the glyph and return.
	return GlyphSize{
		width:  width_factor * glyph.width
		height: height_factor * glyph.height
		x:      group.x + (group.width * self.relative_x)
		y:      group.y + (group.height * self.relative_y)
	}
}

// scale_factors returns width and height scaling factors for this scaling group.
fn (self Constraint) scale_factors(group GlyphSize, metrics Metrics, min_constraint_width u32) (f64, f64) {
	if self.size == .none_ {
		return 1.0, 1.0
	}

	multi_cell := min_constraint_width > 1

	pad_width_factor := f64(min_constraint_width) - (self.pad_left + self.pad_right)
	pad_height_factor := 1 - (self.pad_bottom + self.pad_top)

	target_width := pad_width_factor * metrics.face_width
	target_height := pad_height_factor * match self.height {
		.cell {
			metrics.face_height
		}
		// Like font-patcher, the icon constraint height depends on the
		// constraint width. Unlike font-patcher, the multi-cell icon_height
		// may be different from face_height due to the `adjust-icon-height`
		// config option.
		.icon {
			if multi_cell { metrics.icon_height } else { metrics.icon_height_single }
		}
	}

	mut width_factor := target_width / group.width
	mut height_factor := target_height / group.height

	match self.size {
		.none_ {
			// unreachable
		}
		.fit {
			// Scale down to fit if needed.
			height_factor = math.min(1.0, math.min(width_factor, height_factor))
			width_factor = height_factor
		}
		.cover {
			// Scale to cover.
			height_factor = math.min(width_factor, height_factor)
			width_factor = height_factor
		}
		.fit_cover1 {
			// Scale down to fit or up to cover at least one cell.
			height_factor = math.min(width_factor, height_factor)
			if multi_cell && height_factor > 1 {
				// Call back into this function with constraint width 1 to get
				// single-cell scale factors. We use the height factor as width
				// could have been modified by max_xy_ratio.
				_, single_height_factor := self.scale_factors(group, metrics, 1)
				height_factor = math.max(1.0, single_height_factor)
			}
			width_factor = height_factor
		}
		.stretch {
			// No aspect ratio preservation.
		}
	}

	// Reduce aspect ratio if required.
	if ratio := self.max_xy_ratio {
		if group.width * width_factor > group.height * height_factor * ratio {
			width_factor = group.height * height_factor * ratio / group.width
		}
	}

	return width_factor, height_factor
}

// aligned_y returns the vertical bearing for aligning this group.
fn (self Constraint) aligned_y(group GlyphSize, metrics Metrics) f64 {
	if self.size == .none_ && self.align_vertical == .none_ {
		// If we don't have any constraints affecting the vertical axis,
		// we don't touch vertical alignment.
		return group.y
	}
	// We use face_height and offset by face_y, rather than using cell_height
	// directly, to account for the asymmetry of the pixel cell around the
	// face (a consequence of aligning the baseline with a pixel boundary
	// rather than vertically centering the face).
	pad_bottom_dy := self.pad_bottom * metrics.face_height
	pad_top_dy := self.pad_top * metrics.face_height
	start_y := metrics.face_y + pad_bottom_dy
	end_y := metrics.face_y + (metrics.face_height - group.height - pad_top_dy)
	center_y := (start_y + end_y) / 2
	return match self.align_vertical {
		// NOTE: Even if there is no prescribed alignment, we ensure that the
		// group doesn't protrude outside the padded cell, since this is
		// implied by every available size constraint. If the group is too
		// high we fall back to centering.
		.none_ {
			if end_y < start_y {
				center_y
			} else {
				math.max(start_y, math.min(group.y, end_y))
			}
		}
		.start {
			start_y
		}
		.end_ {
			end_y
		}
		.center, .center1 {
			center_y
		}
	}
}

// aligned_x returns the horizontal bearing for aligning this group.
fn (self Constraint) aligned_x(group GlyphSize, metrics Metrics, min_constraint_width u32) f64 {
	if self.size == .none_ && self.align_horizontal == .none_ {
		// If we don't have any constraints affecting the horizontal axis,
		// we don't touch horizontal alignment.
		return group.x
	}
	// For multi-cell constraints, we align relative to the span from the
	// left edge of the first cell to the right edge of the last face cell
	// assuming it's left-aligned within the rounded and adjusted pixel cell.
	// Any horizontal offset to center the face within the grid cell is the
	// responsibility of the backend-specific rendering code, and should be
	// done after applying constraints.
	full_face_span := metrics.face_width + f64((min_constraint_width - 1) * metrics.cell_width)
	pad_left_dx := self.pad_left * metrics.face_width
	pad_right_dx := self.pad_right * metrics.face_width
	start_x := pad_left_dx
	end_x := full_face_span - group.width - pad_right_dx
	return match self.align_horizontal {
		// NOTE: Even if there is no prescribed alignment, we ensure that the
		// glyph doesn't protrude outside the padded cell. The left-side bound
		// has priority if the group is too wide.
		.none_ {
			math.max(start_x, math.min(group.x, end_x))
		}
		.start {
			start_x
		}
		.end_ {
			math.max(start_x, end_x)
		}
		.center {
			math.max(start_x, (start_x + end_x) / 2)
		}
		// NOTE: .center1 implements the font_patcher rule of centering in the
		// first cell even for multi-cell constraints. Since glyphs are not
		// allowed to protrude to the left, this results in left-alignment like
		// .start when the glyph is wider than a cell.
		.center1 {
			end1_x := metrics.face_width - group.width - pad_right_dx
			math.max(start_x, (start_x + end1_x) / 2)
		}
	}
}
