module renderer

$if !renderer_opengl ? {
	fn test_window_raster_clips_glyphs_and_respects_surface_stride() {
		assert sizeof(CellText) == 32
		assert sizeof(WindowComputeOverlay) == 580
		mut pixels := []u32{len: 8, init: 0xfeedface}
		mask := [u8(0), 255, 255, 0]
		mut transparent_emoji := []u8{len: 16, init: 255}
		transparent_emoji[3] = 0
		frame := C.witty_raster_frame{
			pixels:         pixels.data
			grayscale:      mask.data
			color:          transparent_emoji.data
			stride:         4
			width:          3
			height:         2
			cell_width:     2
			cell_height:    2
			grayscale_size: 2
			color_size:     2
			cursor_col:     0xffff
			cursor_row:     0xffff
			background:     [u8(0x18), 0x28, 0x38, 255]!
			display_p3:     true
		}
		glyphs := [
			CellText{
				bearings:   [i16(-1), 2]!
				glyph_size: [u32(2), 2]!
				color:      [u8(0xab), 0xcd, 0xef, 255]!
			},
			CellText{
				bearings:   [i16(0), 2]!
				glyph_size: [u32(1), 1]!
				atlas:      .color
			},
		]
		C.witty_window_raster_background(&frame)
		C.witty_window_raster_glyphs(&frame, glyphs.data, usize(glyphs.len))
		assert pixels == [u32(0xffabcdef), 0xff182838, 0xff182838, 0xfeedface,
			0xff182838, 0xff182838, 0xff182838, 0xfeedface]
	}
}
