module renderer

$if !renderer_opengl ? {
	fn test_window_compute_bins_clip_bounds_and_preserve_draw_order() {
		api := MetalAPI{}
		mut state := WindowComputeState{
			offsets: MetalBuffer{opts: api.buffer_options()}
			indices: MetalBuffer{opts: api.buffer_options()}
		}
		grid := ComputeGrid{
			width:       32
			height:      16
			columns:     2
			rows:        1
			cell_width:  16
			cell_height: 16
		}
		glyphs := [
			CellText{ bearings: [i16(-3), 16]!, glyph_size: [u32(20), 10]! },
			CellText{ bearings: [i16(0), 16]!, glyph_size: [u32(2), 2]!, grid_pos: [u16(1), 0]! },
			CellText{ bearings: [i16(0), 16]!, glyph_size: [u32(2), 2]!, grid_pos: [u16(2), 0]! },
		]
		count := state.bin_glyphs(grid, [glyphs])
		assert state.tile_offsets == [u32(0), 1, 3]
		assert state.tile_indices[..count] == [u32(0), 0, 1]
		assert state.bin_glyphs(grid, [][]CellText{}) == 0
		assert state.tile_offsets == [u32(0), 0, 0]
	}
}
