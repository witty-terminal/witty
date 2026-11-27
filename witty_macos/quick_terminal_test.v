module witty_macos

import math
fn test_source_quick_frames_and_fractional_size() {
	v := SplitBounds{x: -1440, y: 200, width: 1440, height: 900}
	w := SplitBounds{width: 801, height: 400}
	assert quick_terminal_frame(.bottom, w, v, true).y == -400
	assert quick_terminal_frame(.center, w, v, true).y == 99
	assert quick_terminal_frame(.top, w, v, false).x == -1121
	assert quick_terminal_frame(.top, w, v, false).y == 700
	c := NativeQuickConfig{position: .left, primary: NativeQuickSize{percentage: 33.3}}
	width, height := c.dimensions(v)
	assert math.abs(width - 479.52) < 1e-8 && height == 900
}
fn test_source_quick_screen_cache_capacity_and_ttl() {
	mut cache := QuickScreenCache{}
	for i in 0 .. 12 { cache.entries[i.str()] = QuickScreenEntry{last_seen: f64(i)} }
	cache.prune_capacity()
	assert cache.entries.len == 10 && '0' !in cache.entries && '1' !in cache.entries
	cache.prune_stale(['2'], f64(14 * 24 * 60 * 60 + 100))
	assert cache.entries.len == 1 && '2' in cache.entries
	assert QuickScreenEntry{screen_width: 100, screen_height: 200, scale: 2}.valid(200, 200, 2)
	assert !QuickScreenEntry{screen_width: 100, screen_height: 200, scale: 2}.valid(99, 200, 2)
}
