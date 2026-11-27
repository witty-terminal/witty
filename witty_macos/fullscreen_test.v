module witty_macos

fn test_non_native_fullscreen_source_menu_and_notch_frames() {
	screen := SplitBounds{x: -1280, y: 100, width: 1280, height: 720}
	visible := fullscreen_frame(screen, 0, 24, 32, .visible_menu)
	assert visible.x == -1280 && visible.y == 100 && visible.height == 696
	assert fullscreen_frame(screen, 4, 24, 32, .non_native).height == 720
	assert fullscreen_frame(screen, 4, 24, 32, .padded_notch).height == 688
	assert fullscreen_frame(screen, 8, 24, 32, .padded_notch).height == 688
}
