module witty_macos

fn test_configured_window_geometry_and_fullscreen_opacity() {
	frame := SplitBounds{width: 800, height: 600}
	visible := SplitBounds{x: -1920, y: 100, width: 1920, height: 1080}
	pos := native_window_position(frame, visible, 10, 20)
	assert pos.x == -1910 && pos.y == 560
	assert native_window_transparent(NativeWindowConfig{opacity: 0.5}, false, false)
	assert !native_window_transparent(NativeWindowConfig{opacity: 0.5}, true, false)
	assert !native_window_transparent(NativeWindowConfig{opacity: 0.5}, false, true)
	assert native_window_transparent(NativeWindowConfig{blur: -1}, false, false)
}

fn test_saved_window_geometry_fits_its_display() {
	frame := SplitBounds{x: 40, y: 90, width: 800, height: 600}
	visible := SplitBounds{x: -1920, y: 100, width: 1920, height: 1080}
	saved := SplitBounds{x: -500, y: 900, width: 1000, height: 2000}
	assert restored_window_frame(frame, visible, saved, true, true) == SplitBounds{
		x: -1000
		y: 100
		width: 1000
		height: 1080
	}
	assert restored_window_frame(frame, visible, saved, true, false) == SplitBounds{
		x: -800
		y: 580
		width: 800
		height: 600
	}
	assert restored_window_frame(frame, visible, saved, false, true) == SplitBounds{
		x: 40
		y: 90
		width: 1000
		height: 1080
	}
}
