module renderer

import log

$if !renderer_opengl ? {
	#include "@VMODROOT/renderer/window_raster.h"
	#include "@VMODROOT/renderer/window_compute.h"

	@[typedef]
	struct C.witty_raster_frame {
		pixels          voidptr
		bg_cells        voidptr
		grayscale       voidptr
		color           voidptr
		bg_count        usize
		stride          usize
		width           i32
		height          i32
		cell_width      i32
		cell_height     i32
		columns         i32
		rows            i32
		glyph_x         i32
		glyph_y         i32
		background_x    i32
		background_y    i32
		grayscale_size  u32
		color_size      u32
		padding_extend  u32
		minimum_contrast f32
		cursor_col      u16
		cursor_row      u16
		background      [4]u8
		cursor          [4]u8
		display_p3      bool
		cursor_wide     bool
	}

	fn C.witty_window_raster_cpu_writable(texture voidptr) bool
	fn C.witty_window_raster_allocate(old voidptr, bytes usize) voidptr
	fn C.witty_window_raster_free(pixels voidptr)
	fn C.witty_window_raster_background(frame &C.witty_raster_frame)
	fn C.witty_window_raster_glyphs(frame &C.witty_raster_frame, data voidptr, count usize)
	fn C.witty_window_raster_overlay(frame &C.witty_raster_frame, overlay voidptr)
	fn C.witty_window_raster_present(drawable voidptr, pixels voidptr) int

	fn (mut buffer WindowRasterBuffer) deinit() {
		C.witty_window_raster_free(buffer.pixels)
		buffer.pixels = unsafe { nil }
		buffer.capacity = 0
	}

	fn (mut buffer WindowRasterBuffer) reserve(bytes usize) bool {
		if bytes == buffer.capacity { return true }
		pixels := C.witty_window_raster_allocate(buffer.pixels, bytes)
		if pixels == unsafe { nil } { return false }
		buffer.pixels = pixels
		buffer.capacity = bytes
		return true
	}

	// Blend into CPU memory before uploading the frame in one transfer. This
	// keeps per-glyph reads and writes away from the drawable's uncached pages.
	fn (self &Renderer) draw_window_raster(mut buffer WindowRasterBuffer, uniforms &MetalUniforms,
		request &WindowComputeRequest) WindowMetalDraw {
		width := usize(self.size.screen.width)
		if buffer.failed || !buffer.reserve(width * usize(self.size.screen.height) * 4) {
			return .drawn
		}

		mut grid := self.font_grid
		grid.lock.rlock()
		frame := C.witty_raster_frame{
			pixels:           buffer.pixels
			bg_cells:         self.cells.bg_cells.data
			grayscale:        grid.atlas_grayscale.data.data
			color:            grid.atlas_color.data.data
			bg_count:         usize(self.cells.bg_cells.len)
			stride:           width
			width:            i32(self.size.screen.width)
			height:           i32(self.size.screen.height)
			cell_width:       i32(self.size.cell.width)
			cell_height:      i32(self.size.cell.height)
			columns:          i32(uniforms.grid_size[0])
			rows:             i32(uniforms.grid_size[1])
			glyph_x:          i32(self.size.padding.left)
			glyph_y:          i32(self.size.padding.top)
			background_x:     i32(uniforms.grid_padding[3])
			background_y:     i32(uniforms.grid_padding[0])
			grayscale_size:   grid.atlas_grayscale.size
			color_size:       grid.atlas_color.size
			padding_extend:   u32(uniforms.padding_extend)
			minimum_contrast: uniforms.min_contrast
			cursor_col:       uniforms.cursor_pos[0]
			cursor_row:       uniforms.cursor_pos[1]
			background:       uniforms.bg_color
			cursor:           uniforms.cursor_color
			display_p3:       uniforms.use_display_p3 != 0
			cursor_wide:      uniforms.cursor_wide != 0
		}
		C.witty_window_raster_background(&frame)
		for glyphs in self.cells.fg_rows.lists {
			if glyphs.len > 0 {
				C.witty_window_raster_glyphs(&frame, glyphs.data, usize(glyphs.len))
			}
		}
		grid.lock.runlock()
		C.witty_window_raster_overlay(&frame, &request.overlay)

		status := C.witty_window_raster_present(request.drawable, buffer.pixels)
		if status < 0 {
			buffer.failed = true
			buffer.deinit()
			log.warn('CPU drawable presentation failed')
			return .retry
		}
		return if status == 1 { .presented } else { .drawn }
	}
}
