module renderer

import witty_macos as macos

$if !renderer_opengl ? {
	#include "@VMODROOT/renderer/window_compute.h"

	fn C.witty_window_compute_configure(window voidptr)
	fn C.witty_window_compute_can_write(texture voidptr) bool
	fn C.witty_window_compute_make_pipeline(device voidptr, library voidptr) voidptr
	fn C.witty_window_compute_present(pipeline voidptr, drawable voidptr, uniforms voidptr,
		background voidptr, glyphs voidptr, offsets voidptr, indices voidptr, grayscale voidptr,
		color voidptr, params voidptr, params_size usize) int

	pub fn configure_ui2_window_compute(window voidptr) {
		C.witty_window_compute_configure(window)
	}

	struct ComputeParams {
	mut:
		padding      [2]u32
		tile_columns u32
		point_count  u32
		color        [4]f32
		bounds       [4]f32
		outline      [68][2]f32
	}


	fn (mut state WindowComputeState) deinit() {
		state.offsets.deinit()
		state.indices.deinit()
		macos.metal_release(state.pipeline)
		state.pipeline = unsafe { nil }
		state.tile_offsets = []u32{}
		state.tile_indices = []u32{}
	}

	fn (mut state WindowComputeState) start(api &MetalAPI, library voidptr) ! {
		if state.pipeline != unsafe { nil } { return }
		state.pipeline = C.witty_window_compute_make_pipeline(api.device, library)
		if state.pipeline == unsafe { nil } {
			// A local build can reuse an older metallib. Compile the same source used
			// by the release build if that archive has no compute entry point.
			source := $embed_file('shaders.metal').to_string()
			source_library := macos.metal_new_library_source(api.device, source)
			defer { macos.metal_release(source_library) }
			state.pipeline = C.witty_window_compute_make_pipeline(api.device, source_library)
		}
		if state.pipeline == unsafe { nil } { return error('Metal window compute pipeline unavailable') }
		state.offsets = MetalBuffer.init(api.buffer_options(), 256)!
		state.indices = MetalBuffer.init(api.buffer_options(), 256)!
	}

	const window_tile_size = 16

	struct ComputeGrid {
		width int
		height int
		columns int
		rows int
		cell_width int
		cell_height int
		padding_x int
		padding_y int
	}

	fn (grid ComputeGrid) glyph_tiles(glyph CellText) (int, int, int, int) {
		x := grid.padding_x + int(glyph.grid_pos[0]) * grid.cell_width + int(glyph.bearings[0])
		y := grid.padding_y + (int(glyph.grid_pos[1]) + 1) * grid.cell_height - int(glyph.bearings[1])
		left := if x < 0 { 0 } else { x }
		top := if y < 0 { 0 } else { y }
		right_edge := x + int(glyph.glyph_size[0])
		right := if right_edge > grid.width { grid.width } else { right_edge }
		bottom_edge := y + int(glyph.glyph_size[1])
		bottom := if bottom_edge > grid.height { grid.height } else { bottom_edge }
		if left >= right || top >= bottom { return 0, 0, 0, 0 }
		return left / window_tile_size, top / window_tile_size,
			(right + window_tile_size - 1) / window_tile_size, (bottom + window_tile_size - 1) / window_tile_size
	}

	fn (mut state WindowComputeState) bin_glyphs(grid ComputeGrid, glyph_rows [][]CellText) int {
		tile_count := grid.columns * grid.rows
		if state.tile_offsets.len != tile_count + 1 {
			state.tile_offsets = []u32{len: tile_count + 1}
		} else {
			unsafe { vmemset(state.tile_offsets.data, 0, int(sizeof(u32)) * state.tile_offsets.len) }
		}
		// Count each glyph once per touched tile, then build contiguous lists.
		// Glyph indices retain the draw order of the original rows.
		for row in glyph_rows {
			for glyph in row {
				left, top, right, bottom := grid.glyph_tiles(glyph)
				for y in top .. bottom {
					for x in left .. right {
						state.tile_offsets[y * grid.columns + x + 1]++
					}
				}
			}
		}
		for tile in 1 .. tile_count + 1 {
			state.tile_offsets[tile] += state.tile_offsets[tile - 1]
		}
		index_count := int(state.tile_offsets[tile_count])
		if state.tile_indices.len < index_count {
			state.tile_indices = []u32{len: index_count + index_count / 4}
		}
		mut glyph_index := u32(0)
		for row in glyph_rows {
			for glyph in row {
				left, top, right, bottom := grid.glyph_tiles(glyph)
				for y in top .. bottom {
					for x in left .. right {
						tile := y * grid.columns + x
						state.tile_indices[state.tile_offsets[tile]] = glyph_index
						state.tile_offsets[tile]++
					}
				}
				glyph_index++
			}
		}
		for tile := tile_count; tile > 0; tile-- {
			state.tile_offsets[tile] = state.tile_offsets[tile - 1]
		}
		state.tile_offsets[0] = 0
		return index_count
	}

	fn (mut state WindowComputeState) draw(api &MetalAPI, library voidptr, frame &MetalFrameState,
		size Size, glyph_rows [][]CellText, request &WindowComputeRequest) !WindowMetalDraw {
		if state.failed { return .drawn }
		state.start(api, library)!
		width := int(size.screen.width)
		height := int(size.screen.height)
		grid := ComputeGrid{
			width: width
			height: height
			columns: (width + window_tile_size - 1) / window_tile_size
			rows: (height + window_tile_size - 1) / window_tile_size
			cell_width: int(size.cell.width)
			cell_height: int(size.cell.height)
			padding_x: int(size.padding.left)
			padding_y: int(size.padding.top)
		}
		index_count := state.bin_glyphs(grid, glyph_rows)
		state.offsets.sync_values(state.tile_offsets)!
		state.indices.sync_values(state.tile_indices[..index_count])!
		params := ComputeParams{
			padding: [u32(grid.padding_x), u32(grid.padding_y)]!
			tile_columns: u32(grid.columns)
			point_count: request.overlay.count
			color: request.overlay.color
			bounds: request.overlay.bounds
			outline: request.overlay.points
		}
		status := C.witty_window_compute_present(state.pipeline, request.drawable, frame.uniforms.handle,
			frame.cells_bg.handle, frame.cells.handle, state.offsets.handle, state.indices.handle,
			frame.grayscale.handle, frame.color.handle, &params, sizeof(ComputeParams))
		if status < 0 {
			state.deinit()
			state.failed = true
			return .retry
		}
		return if status == 1 { .presented } else { .drawn }
	}
}
