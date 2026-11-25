module terminal

// Kitty graphics protocol unicode placeholder / virtual placement feature.
//
// Source: kitty/graphics_unicode.zig
//
// This file contains various logic and data for working with the
// Kitty graphics protocol unicode placeholder, virtual placement feature.

import math

// ============================================================
// VirtualPlacement - a virtual placement in the terminal
// ============================================================

// A virtual placement in the terminal. This can represent more than
// one cell if the cells combine to be a run.
pub struct VirtualPlacement {
pub:
	// The top-left pin of the placement. This can be used to get the
	// screen x/y.
	pin Pin

	// The image ID and placement ID for this virtual placement. The
	// image ID is encoded in the fg color (plus optional a 8-bit high
	// value in the 3rd diacritic). The placement ID is encoded in the
	// underline color (optionally).
	image_id     u32
	placement_id u32

	// Starting row/col index for the image itself. This is the "fragment"
	// of the image we want to show in this placement. This is 0-indexed.
	col u32
	row u32

	// The width/height in cells of this placement.
	width  u32
	height u32
}

// Take this virtual placement and convert it to a render placement.
pub fn (self &VirtualPlacement) render_placement(storage &ImageStorage, img &Image, cell_width u32, cell_height u32) !RenderPlacement {
	// In this function, there is a variable naming convention to try
	// to make it slightly less confusing. The prefix will tell you what
	// coordinate/size space a variable lives in:
	// - img_* is for the original image
	// - p_* is for the final placement
	// - vp_* is for the virtual placement

	// Determine the grid size that this virtual placement fits into.
	p_grid_rows, p_grid_columns := self.grid(storage, img, cell_width, cell_height)!

	// From here on out we switch to floating point math. These are
	// constants that we'll reference repeatedly.
	img_width_f64 := f64(img.width)
	img_height_f64 := f64(img.height)

	// Next we have to fit the source image into the grid size while preserving
	// aspect ratio. We will center the image horizontally/vertically if
	// necessary.
	p_rows_px := f64(p_grid_rows * cell_height)
	p_cols_px := f64(p_grid_columns * cell_width)

	mut p_x_offset := f64(0)
	mut p_y_offset := f64(0)
	mut p_x_scale := f64(0)
	mut p_y_scale := f64(0)

	if img_width_f64 * p_rows_px > img_height_f64 * p_cols_px {
		// Image is wider than the grid, fit width and center height
		p_x_scale = p_cols_px / math.max(img_width_f64, 1.0)
		p_y_scale = p_x_scale
		p_y_offset = (p_rows_px - img_height_f64 * p_y_scale) / 2.0
	} else {
		// Image is taller than the grid, fit height and center width
		p_y_scale = p_rows_px / math.max(img_height_f64, 1.0)
		p_x_scale = p_y_scale
		p_x_offset = (p_cols_px - img_width_f64 * p_x_scale) / 2.0
	}

	// Scale our original image according to the aspect ratio
	// and padding calculated for p_scale.
	img_x_offset := p_x_offset / p_x_scale
	img_y_offset := p_y_offset / p_y_scale
	img_width := img_width_f64 + (img_x_offset * 2.0)
	img_height := img_height_f64 + (img_y_offset * 2.0)

	// Calculate the source rectangle for the scaled image. These
	// coordinates are in the scaled image space.
	vp_width := f64(self.width)
	vp_height := f64(self.height)
	vp_col := f64(self.col)
	vp_row := f64(self.row)
	p_grid_cols_f := f64(p_grid_columns)
	p_grid_rows_f := f64(p_grid_rows)

	// Calculate the scaled source rectangle for the image, undoing
	// the aspect ratio scaling as necessary.
	mut src_width := img_width * (vp_width / p_grid_cols_f)
	mut src_height := img_height * (vp_height / p_grid_rows_f)
	mut src_x := img_width * (vp_col / p_grid_cols_f)
	mut src_y := img_height * (vp_row / p_grid_rows_f)

	// The destination rectangle. The x/y is specified by offsets from
	// the top-left since that's how our RenderPlacement works.
	mut dest_x_offset := f64(0)
	mut dest_y_offset := f64(0)
	mut dest_width := f64(self.width * cell_width)
	mut dest_height := f64(self.height * cell_height)

	if src_y < img_y_offset {
		// If our source rect y is within the offset area, we need to
		// adjust our source rect and destination since the source texture
		// doesn't actually have the offset area blank.
		offset := img_y_offset - src_y
		src_height -= offset
		dest_y_offset = offset
		dest_height -= offset * p_y_scale
		src_y = 0

		// If our height is greater than our original height,
		// bring it back down. This addresses the case where the top
		// and bottom offsets are both used.
		if src_height > img_height_f64 {
			src_height = img_height_f64
			dest_height = img_height_f64 * p_y_scale
		}
	} else if src_y + src_height > img_height - img_y_offset {
		// if our y is in our bottom offset area, we need to shorten the
		// source to fit in the cell.
		src_y -= img_y_offset
		src_height = img_height - img_y_offset - src_y
		src_height -= img_y_offset
		dest_height = src_height * p_y_scale
	} else {
		src_y -= img_y_offset
	}

	if src_x < img_x_offset {
		// If our source rect x is within the offset area, we need to
		// adjust our source rect and destination since the source texture
		// doesn't actually have the offset area blank.
		offset := img_x_offset - src_x
		src_width -= offset
		dest_x_offset = offset
		dest_width -= offset * p_x_scale
		src_x = 0

		// If our width is greater than our original width,
		// bring it back down. This addresses the case where the left
		// and right offsets are both used.
		if src_width > img_width_f64 {
			src_width = img_width_f64
			dest_width = img_width_f64 * p_x_scale
		}
	} else if src_x + src_width > img_width - img_x_offset {
		// if our x is in our right offset area, we need to shorten the
		// source to fit in the cell.
		src_x -= img_x_offset
		src_width = img_width - img_x_offset - src_x
		src_width -= img_x_offset
		dest_width = src_width * p_x_scale
	} else {
		src_x -= img_x_offset
	}

	// If our modified source width/height is less than zero then
	// we render nothing because it means we're rendering outside
	// of the visible image.
	if src_width <= 0 || src_height <= 0 {
		return RenderPlacement{ top_left: self.pin }
	}

	return RenderPlacement{
		top_left:      self.pin
		offset_x:      u32(math.round(dest_x_offset * p_x_scale))
		offset_y:      u32(math.round(dest_y_offset * p_y_scale))
		source_x:      u32(math.round(src_x))
		source_y:      u32(math.round(src_y))
		source_width:  u32(math.round(src_width))
		source_height: u32(math.round(src_height))
		dest_width:    u32(math.round(dest_width))
		dest_height:   u32(math.round(dest_height))
	}
}

// Calculate the grid size for the placement. For virtual placements,
// we use the requested row/cols. If either isn't specified, we choose
// the best size based on the image size to fit the entire image in its
// original size.
//
// This part of the code does NOT preserve any aspect ratios. Its
// dumbly fitting the image into the grid size -- possibly user specified.
fn (self &VirtualPlacement) grid(storage &ImageStorage, image &Image, cell_width u32, cell_height u32) !(u32, u32) {
	target := storage.placeholder_target(self.image_id, self.placement_id) or {
		return error('PlacementMissingPlacement')
	}
	p := target.value
	if cell_width == 0 || cell_height == 0 {
		return error('PlacementGridOutOfBounds')
	}
	rows := if p.rows > 0 { p.rows } else { kitty_grid_extent(image.height, 0, cell_height) }
	columns := if p.columns > 0 { p.columns } else { kitty_grid_extent(image.width, 0, cell_width) }
	if rows == 0 || columns == 0 || rows > max_u16 || columns > max_u16 {
		return error('PlacementGridOutOfBounds')
	}
	return rows, columns
}

// ============================================================
// IncompletePlacement - intermediate state during parsing
// ============================================================

// IncompletePlacement is the placement information present in a single
// cell. It is "incomplete" because the specification allows for missing
// diacritics and so on that continue from previous valid placements.
struct IncompletePlacement {
mut:
	// The pin of the cell that created this incomplete placement.
	pin Pin

	// Lower 24 bits of the image ID. This is specified in the fg color
	// and is always required.
	image_id_low u32 // only bottom 24 bits used

	// Higher 8 bits of the image ID specified using the 3rd diacritic.
	// This is optional.
	image_id_high ?u8

	// Placement ID is optionally specified in the underline color.
	placement_id ?u32 // only bottom 24 bits used

	// The row/col index for the image. These are 0-indexed. These
	// are specified using diacritics. The row is first and the col
	// is second. Both are optional. If not specified, they can continue
	// a previous placement under certain conditions.
	row ?u32
	col ?u32

	// The run width so far in cells.
	width u32 = 1
}

// Parse the incomplete placement information from a row and cell.
fn IncompletePlacement.init(row &Pin, cell &CellData) IncompletePlacement {
	assert cell.codepoint() == kitty_unicode_placeholder
	style := row.style(cell)

	mut result := IncompletePlacement{
		pin:          *row
		image_id_low: color_to_id(style.fg_color)
		placement_id: fn_placement_id(style)
	}

	// Try to decode all our diacritics. Any invalid diacritics are
	// treated as if they don't exist. This isn't explicitly specified
	// at the time of writing this but it appears to be how Kitty behaves.
	cps := row.grapheme(cell) or { []u32{} }
	if cps.len > 0 {
		result.row = get_index(cps[0])

		if cps.len > 1 {
			result.col = get_index(cps[1])

			if cps.len > 2 {
				if high := get_index(cps[2]) {
					if high <= 255 {
						result.image_id_high = u8(high)
					}
				}
				// Any additional diacritics are ignored.
			}
		}
	}

	return result
}

// Append this incomplete placement to an existing placement to
// create a run. This returns true if the placements are compatible
// and were combined. If this returns false, the other placement is
// unchanged.
fn (mut self IncompletePlacement) append(other &IncompletePlacement) bool {
	if !self.can_append(other) {
		return false
	}
	self.width += 1
	return true
}

fn (self &IncompletePlacement) can_append(other &IncompletePlacement) bool {
	// Converted from Kitty's logic, don't @ me.
	if self.image_id_low != other.image_id_low {
		return false
	}
	if self.placement_id != other.placement_id {
		return false
	}
	if other_row := other.row {
		if self_row := self.row {
			if other_row != self_row {
				return false
			}
		} else {
			return false
		}
	}
	if other_col := other.col {
		if self_col := self.col {
			if other_col != self_col + self.width {
				return false
			}
		} else {
			return false
		}
	}
	if other_high := other.image_id_high {
		if self_high := self.image_id_high {
			if other_high != self_high {
				return false
			}
		} else {
			return false
		}
	}
	return true
}

// Complete the incomplete placement to create a full placement.
// This creates a new placement that isn't continuous with any previous
// placements.
fn (self &IncompletePlacement) complete() VirtualPlacement {
	low := self.image_id_low
	high := u32(self.image_id_high or { 0 })

	return VirtualPlacement{
		pin:          self.pin
		image_id:     low | (high << 24)
		placement_id: self.placement_id or { 0 }
		col:          self.col or { 0 }
		row:          self.row or { 0 }
		width:        self.width
		height:       1
	}
}

// Convert a style color to a Kitty image protocol ID. This works by
// taking the 24 most significant bits of the color, which lets it work
// for both palette and rgb-based colors.
fn color_to_id(color StyleColor) u32 {
	return match color {
		StyleColorNone { u32(0) }
		StyleColorPalette { u32((color as StyleColorPalette).index) }
		StyleColorRgb {
			rgb := (color as StyleColorRgb).rgb
			r32 := u32(rgb.r)
			g32 := u32(rgb.g)
			b32 := u32(rgb.b)
			(r32 << 16) | (g32 << 8) | b32
		}
	}
}

// Get placement ID from underline color (if set).
fn fn_placement_id(style CellStyle) ?u32 {
	id := color_to_id(style.underline_color)
	if id != 0 {
		return id
	}
	return none
}

// ============================================================
// PlacementIterator
// ============================================================

// Returns an iterator that iterates over all of the virtual placements
// in the given pin. If `limit` is provided, the iterator will stop
// when it reaches that pin (inclusive). If `limit` is not provided,
// the iterator will continue until the end of the page list.
pub fn placement_iterator(pin Pin, limit ?Pin) PlacementIterator {
	mut row_it := pin.row_iterator(.right_down, limit)
	row := row_it.next()
	return PlacementIterator{
		row_it: row_it
		row:    row
	}
}

// Iterator over unicode virtual placements.
pub struct PlacementIterator {
mut:
	row_it RowIterator
	row    ?Pin
}

pub fn (mut self PlacementIterator) next() ?VirtualPlacement {
	for {
		mut row := self.row or { break }

		// This row flag is set on rows that have the virtual placeholder
		if !row.row_and_cell().row.header.kitty_virtual_placeholder {
			self.row = self.row_it.next()
			continue
		}

		// Our current run. A run is always only a single row. This
		// assumption is built-in to our logic so if we want to change
		// this later we have to redo the logic; tests should cover;
		mut run := ?IncompletePlacement(none)

		// Iterate over our remaining cells and find one with a placeholder.
		cells := row.cells(.right)
		start_x := int(row.x)
		for i in 0 .. cells.len {
			cell := unsafe { &cells[i] }

			// "row" now points to the top-left pin of the placement.
			// We need this temporary state to build our incomplete
			// placement.
			row.x = u16(start_x + i)
			self.row = row

			// If this cell doesn't have the placeholder, then we
			// complete the run if we have it otherwise we just move
			// on and keep searching.
			if cell.codepoint() != kitty_unicode_placeholder {
				if prev := run {
					return prev.complete()
				}
				continue
			}

			// If we don't have a previous run, then we save this
			// incomplete one, start a run, and move on.
			curr := IncompletePlacement.init(&row, cell)
			if mut prev := run {
				// If we can't append, then we complete the previous
				// run and return it.
				if !prev.append(&curr) {
					// Note: self.row is already updated due to the
					// row pointer above. It points back at this same
					// cell so we can continue the new placements from
					// here.
					return prev.complete()
				}

				// append is mutating so if we reached this point
				// then prev has been updated.
				run = prev
			} else {
				// For appending, we need to set our initial values.
				mut prev := curr
				if prev.row == none {
					prev.row = 0
				}
				if prev.col == none {
					prev.col = 0
				}
				run = prev
			}
		}

		// We move to the next row no matter what
		self.row = self.row_it.next()

		// If we have a run, we complete it here.
		if prev := run {
			return prev.complete()
		}
	}

	return none
}

// ============================================================
// Diacritic index lookup
// ============================================================

// Get the row/col index for a diacritic codepoint. These are 0-indexed.
fn get_index(cp u32) ?u32 {
	// Binary search in sorted diacritics array
	mut lo := 0
	mut hi := diacritics.len - 1

	for lo <= hi {
		mid := lo + (hi - lo) / 2
		if diacritics[mid] == cp {
			return u32(mid)
		}
		if diacritics[mid] < cp {
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}
	return none
}

// ============================================================
// Diacritics table
// ============================================================

// These are the diacritics used with the Kitty graphics protocol
// Unicode placement feature to specify the row/column for placement.
// The index into the array determines the value.
//
// This is derived from:
// https://sw.kovidgoyal.net/kitty/_downloads/f0a0de9ec8d9ff4456206db8e0814937/rowcolumn-diacritics.txt
const diacritics = [
	u32(0x0305),
	0x030D,
	0x030E,
	0x0310,
	0x0312,
	0x033D,
	0x033E,
	0x033F,
	0x0346,
	0x034A,
	0x034B,
	0x034C,
	0x0350,
	0x0351,
	0x0352,
	0x0357,
	0x035B,
	0x0363,
	0x0364,
	0x0365,
	0x0366,
	0x0367,
	0x0368,
	0x0369,
	0x036A,
	0x036B,
	0x036C,
	0x036D,
	0x036E,
	0x036F,
	0x0483,
	0x0484,
	0x0485,
	0x0486,
	0x0487,
	0x0592,
	0x0593,
	0x0594,
	0x0595,
	0x0597,
	0x0598,
	0x0599,
	0x059C,
	0x059D,
	0x059E,
	0x059F,
	0x05A0,
	0x05A1,
	0x05A8,
	0x05A9,
	0x05AB,
	0x05AC,
	0x05AF,
	0x05C4,
	0x0610,
	0x0611,
	0x0612,
	0x0613,
	0x0614,
	0x0615,
	0x0616,
	0x0617,
	0x0657,
	0x0658,
	0x0659,
	0x065A,
	0x065B,
	0x065D,
	0x065E,
	0x06D6,
	0x06D7,
	0x06D8,
	0x06D9,
	0x06DA,
	0x06DB,
	0x06DC,
	0x06DF,
	0x06E0,
	0x06E1,
	0x06E2,
	0x06E4,
	0x06E7,
	0x06E8,
	0x06EB,
	0x06EC,
	0x0730,
	0x0732,
	0x0733,
	0x0735,
	0x0736,
	0x073A,
	0x073D,
	0x073F,
	0x0740,
	0x0741,
	0x0743,
	0x0745,
	0x0747,
	0x0749,
	0x074A,
	0x07EB,
	0x07EC,
	0x07ED,
	0x07EE,
	0x07EF,
	0x07F0,
	0x07F1,
	0x07F3,
	0x0816,
	0x0817,
	0x0818,
	0x0819,
	0x081B,
	0x081C,
	0x081D,
	0x081E,
	0x081F,
	0x0820,
	0x0821,
	0x0822,
	0x0823,
	0x0825,
	0x0826,
	0x0827,
	0x0829,
	0x082A,
	0x082B,
	0x082C,
	0x082D,
	0x0951,
	0x0953,
	0x0954,
	0x0F82,
	0x0F83,
	0x0F86,
	0x0F87,
	0x135D,
	0x135E,
	0x135F,
	0x17DD,
	0x193A,
	0x1A17,
	0x1A75,
	0x1A76,
	0x1A77,
	0x1A78,
	0x1A79,
	0x1A7A,
	0x1A7B,
	0x1A7C,
	0x1B6B,
	0x1B6D,
	0x1B6E,
	0x1B6F,
	0x1B70,
	0x1B71,
	0x1B72,
	0x1B73,
	0x1CD0,
	0x1CD1,
	0x1CD2,
	0x1CDA,
	0x1CDB,
	0x1CE0,
	0x1DC0,
	0x1DC1,
	0x1DC3,
	0x1DC4,
	0x1DC5,
	0x1DC6,
	0x1DC7,
	0x1DC8,
	0x1DC9,
	0x1DCB,
	0x1DCC,
	0x1DD1,
	0x1DD2,
	0x1DD3,
	0x1DD4,
	0x1DD5,
	0x1DD6,
	0x1DD7,
	0x1DD8,
	0x1DD9,
	0x1DDA,
	0x1DDB,
	0x1DDC,
	0x1DDD,
	0x1DDE,
	0x1DDF,
	0x1DE0,
	0x1DE1,
	0x1DE2,
	0x1DE3,
	0x1DE4,
	0x1DE5,
	0x1DE6,
	0x1DFE,
	0x20D0,
	0x20D1,
	0x20D4,
	0x20D5,
	0x20D6,
	0x20D7,
	0x20DB,
	0x20DC,
	0x20E1,
	0x20E7,
	0x20E9,
	0x20F0,
	0x2CEF,
	0x2CF0,
	0x2CF1,
	0x2DE0,
	0x2DE1,
	0x2DE2,
	0x2DE3,
	0x2DE4,
	0x2DE5,
	0x2DE6,
	0x2DE7,
	0x2DE8,
	0x2DE9,
	0x2DEA,
	0x2DEB,
	0x2DEC,
	0x2DED,
	0x2DEE,
	0x2DEF,
	0x2DF0,
	0x2DF1,
	0x2DF2,
	0x2DF3,
	0x2DF4,
	0x2DF5,
	0x2DF6,
	0x2DF7,
	0x2DF8,
	0x2DF9,
	0x2DFA,
	0x2DFB,
	0x2DFC,
	0x2DFD,
	0x2DFE,
	0x2DFF,
	0xA66F,
	0xA67C,
	0xA67D,
	0xA6F0,
	0xA6F1,
	0xA8E0,
	0xA8E1,
	0xA8E2,
	0xA8E3,
	0xA8E4,
	0xA8E5,
	0xA8E6,
	0xA8E7,
	0xA8E8,
	0xA8E9,
	0xA8EA,
	0xA8EB,
	0xA8EC,
	0xA8ED,
	0xA8EE,
	0xA8EF,
	0xA8F0,
	0xA8F1,
	0xAAB0,
	0xAAB2,
	0xAAB3,
	0xAAB7,
	0xAAB8,
	0xAABE,
	0xAABF,
	0xAAC1,
	0xFE20,
	0xFE21,
	0xFE22,
	0xFE23,
	0xFE24,
	0xFE25,
	0xFE26,
	0x10A0F,
	0x10A38,
	0x1D185,
	0x1D186,
	0x1D187,
	0x1D188,
	0x1D189,
	0x1D1AA,
	0x1D1AB,
	0x1D1AC,
	0x1D1AD,
	0x1D242,
	0x1D243,
	0x1D244,
]
