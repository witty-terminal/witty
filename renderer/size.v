module renderer

import configpkg

// All relevant sizes for a rendered terminal.
pub struct Size {
pub mut:
	screen  ScreenSize
	cell    CellSize
	padding Padding
}

// The dimensions of the screen that the grid is rendered to, in pixels.
pub struct ScreenSize {
pub mut:
	width  u32
	height u32
}

// The dimensions of a single terminal cell in world-space pixels.
pub struct CellSize {
pub mut:
	width  u32
	height u32
}

// The dimensions of the terminal grid. Ghostty's Unit is CellCountInt (u16).
pub struct GridSize {
pub mut:
	columns u16
	rows    u16
}

// Padding around a terminal screen.
pub struct Padding {
pub mut:
	top    u32
	bottom u32
	left   u32
	right  u32
}

// Return the grid size after subtracting the configured padding.
pub fn (self Size) grid() GridSize {
	return GridSize.init(self.screen.sub_padding(self.padding), self.cell)
}

// Return the terminal size: the screen with padding removed.
pub fn (self Size) terminal() ScreenSize {
	return self.screen.sub_padding(self.padding)
}

// Apply explicit padding and balance the remaining space if configured.
pub fn (mut self Size) set_padding(explicit Padding, balance configpkg.WindowPaddingBalance) {
	self.padding = explicit
	if balance == .false_ {
		return
	}
	self.padding = Padding.balanced(self.screen, self.grid(), self.cell)
	if balance == .equal {
		return
	}

	max_top := (explicit.left + explicit.right + self.cell.width) / 2
	vshift := if self.padding.top > max_top {
		self.padding.top - max_top
	} else {
		u32(0)
	}
	self.padding.top -= vshift
	self.padding.bottom += vshift
}

// A coordinate. This is defined as a tagged union to allow for different
// coordinate systems to be represented.
//
// A coordinate is only valid within the context of a stable Size value.
// If any of the sizes in the Size struct change, the coordinate is no
// longer valid and must be recalculated.
//
// The coordinate systems are:
//
//   * surface: (0, 0) is the top-left of the surface (with padding). Negative
//     values are allowed and are off the surface. Units are pixels.
//
//   * terminal: (0, 0) is the top-left of the terminal grid. This is the
//     same as the surface but with the padding removed. Units are pixels.
//
//   * grid: (0, 0) is the top-left of the grid. Units are in cells. Negative
//     values are not allowed but values greater than the grid size are
//     possible and are off the grid.
pub type Coordinate = SurfaceCoord | TerminalCoord | GridCoord

pub struct SurfaceCoord {
pub:
	x f64
	y f64
}

pub struct TerminalCoord {
pub:
	x f64
	y f64
}

pub struct GridCoord {
pub:
	x u16
	y u16
}

// Coordinate system tag for conversion.
pub enum CoordTag as u8 {
	surface
	terminal
	grid
}

// Convert a coordinate to a different space within the same Size.
pub fn (self Coordinate) convert(to CoordTag, size Size) Coordinate {
	// Same-space conversion is an exact identity, even when the coordinate is
	// outside the current surface or grid.
	match self {
		SurfaceCoord {
			if to == .surface {
				return self
			}
		}
		TerminalCoord {
			if to == .terminal {
				return self
			}
		}
		GridCoord {
			if to == .grid {
				return self
			}
		}
	}

	// First convert to surface coordinates.
	surface := self.convert_to_surface(size)

	if to == .surface {
		return Coordinate(SurfaceCoord{
			x: surface.x
			y: surface.y
		})
	} else if to == .terminal {
		return Coordinate(TerminalCoord{
			x: surface.x - f64(size.padding.left)
			y: surface.y - f64(size.padding.top)
		})
	} else {
		// .grid
		// Get rid of the padding.
		term_x := surface.x - f64(size.padding.left)
		term_y := surface.y - f64(size.padding.top)

		// We need our grid to clamp
		g := size.grid()

		// Calculate the grid position.
		cell_width := f64(size.cell.width)
		cell_height := f64(size.cell.height)
		clamped_x := if term_x > 0 { term_x } else { 0.0 }
		clamped_y := if term_y > 0 { term_y } else { 0.0 }
		col := u16(clamped_x / cell_width)
		row := u16(clamped_y / cell_height)
		clamped_col := if col < g.columns - 1 { col } else { g.columns - 1 }
		clamped_row := if row < g.rows - 1 { row } else { g.rows - 1 }
		return Coordinate(GridCoord{
			x: clamped_col
			y: clamped_row
		})
	}
}

// Convert a coordinate to the surface coordinate system.
fn (self Coordinate) convert_to_surface(size Size) SurfaceCoord {
	match self {
		SurfaceCoord {
			return SurfaceCoord{
				x: self.x
				y: self.y
			}
		}
		TerminalCoord {
			return SurfaceCoord{
				x: self.x + f64(size.padding.left)
				y: self.y + f64(size.padding.top)
			}
		}
		GridCoord {
			col := f64(self.x)
			row := f64(self.y)
			cell_width := f64(size.cell.width)
			cell_height := f64(size.cell.height)
			padding_left := f64(size.padding.left)
			padding_top := f64(size.padding.top)
			return SurfaceCoord{
				x: col * cell_width + padding_left
				y: row * cell_height + padding_top
			}
		}
	}
}

// Subtract padding from the screen size.
pub fn (self ScreenSize) sub_padding(padding Padding) ScreenSize {
	lr := padding.left + padding.right
	tb := padding.top + padding.bottom
	return ScreenSize{
		width: if self.width > lr { self.width - lr } else { 0 }
		height: if self.height > tb { self.height - tb } else { 0 }
	}
}

// Returns true if two screen sizes are equal.
pub fn (self ScreenSize) equals(other ScreenSize) bool {
	return self.width == other.width && self.height == other.height
}

// Calculates the amount of blank space around the grid. This is possible
// when padding isn't balanced.
//
// The "self" screen size here should be the unpadded screen.
pub fn (self ScreenSize) blank_padding(padding Padding, g GridSize, cell CellSize) Padding {
	grid_width := u32(g.columns) * cell.width
	grid_height := u32(g.rows) * cell.height
	padded_width := grid_width + (padding.left + padding.right)
	padded_height := grid_height + (padding.top + padding.bottom)

	// Note these use saturating subtraction to avoid underflow
	// because our padding can cause the padded sizes to be larger than
	// our real screen if the screen is shrunk to a minimal size.
	leftover_width := if self.width > padded_width {
		self.width - padded_width
	} else {
		u32(0)
	}
	leftover_height := if self.height > padded_height {
		self.height - padded_height
	} else {
		u32(0)
	}

	return Padding{
		top: 0
		bottom: leftover_height
		right: leftover_width
		left: 0
	}
}

// Returns padding that balances the whitespace around the screen
// for the given grid and cell sizes.
pub fn Padding.balanced(screen ScreenSize, g GridSize, cell CellSize) Padding {
	// Turn our cell sizes into floats for the math
	cell_width := f32(cell.width)
	cell_height := f32(cell.height)

	// The size of our full grid
	grid_width := f32(g.columns) * cell_width
	grid_height := f32(g.rows) * cell_height

	// The empty space to the right of a line and bottom of the last row
	space_right := f32(screen.width) - grid_width
	space_bot := f32(screen.height) - grid_height

	// The padding is split equally along both axes.
	padding_right := int(space_right / 2)
	padding_left := padding_right

	padding_bot := int(space_bot / 2)
	padding_top := padding_bot

	return Padding{
		top: u32(if padding_top > 0 { padding_top } else { 0 })
		bottom: u32(if padding_bot > 0 { padding_bot } else { 0 })
		right: u32(if padding_right > 0 { padding_right } else { 0 })
		left: u32(if padding_left > 0 { padding_left } else { 0 })
	}
}

// Add another padding to this one.
pub fn (self Padding) add(other Padding) Padding {
	return Padding{
		top: self.top + other.top
		bottom: self.bottom + other.bottom
		left: self.left + other.left
		right: self.right + other.right
	}
}

// Equality test between two paddings.
pub fn (self Padding) eql(other Padding) bool {
	return self.top == other.top && self.bottom == other.bottom
		&& self.right == other.right && self.left == other.left
}

// Initialize a grid size based on a screen and cell size.
pub fn GridSize.init(screen ScreenSize, cell CellSize) GridSize {
	mut result := GridSize{}
	result.update(screen, cell)
	return result
}

// Update the columns/rows for the grid based on the given screen and
// cell size.
pub fn (mut self GridSize) update(screen ScreenSize, cell CellSize) {
	cell_width := f32(cell.width)
	cell_height := f32(cell.height)
	screen_width := f32(screen.width)
	screen_height := f32(screen.height)
	calc_cols := u16(screen_width / cell_width)
	calc_rows := u16(screen_height / cell_height)
	self.columns = if calc_cols > 1 { calc_cols } else { 1 }
	self.rows = if calc_rows > 1 { calc_rows } else { 1 }
}

// Returns true if two grid sizes are equal.
pub fn (self GridSize) equals(other GridSize) bool {
	return self.columns == other.columns && self.rows == other.rows
}
