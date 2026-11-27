module witty_macos

import math

pub enum NativeQuickPosition { top bottom left right center }
pub struct NativeQuickSize { pub: percentage ?f64 pixels ?u32 }
pub struct NativeQuickConfig {
pub:
	position NativeQuickPosition
	primary NativeQuickSize
	secondary NativeQuickSize
	screen int
	duration f64 = 0.2
	autohide bool = true
	remain_on_space bool
	window NativeWindowConfig
}
fn (s NativeQuickSize) points(parent f64, fallback f64) f64 {
	if percentage := s.percentage { return parent * percentage / 100 }
	if pixels := s.pixels { return f64(pixels) }
	return fallback
}
pub fn (c NativeQuickConfig) dimensions(screen SplitBounds) (f64, f64) {
	return match c.position {
		.left, .right { c.primary.points(screen.width, 400), c.secondary.points(screen.height, screen.height) }
		.top, .bottom { c.secondary.points(screen.width, screen.width), c.primary.points(screen.height, 400) }
		.center { if screen.width >= screen.height { c.primary.points(screen.width, 800), c.secondary.points(screen.height, 400) } else { c.secondary.points(screen.width, 400), c.primary.points(screen.height, 800) } }
	}
}
pub fn quick_terminal_frame(position NativeQuickPosition, window SplitBounds, visible SplitBounds, initial bool) SplitBounds {
	cx := math.round(visible.x + (visible.width - window.width) / 2)
	cy := math.round(visible.y + (visible.height - window.height) / 2)
	return SplitBounds{width: window.width, height: window.height,
		x: match position { .left { if initial { visible.x - window.width } else { visible.x } } .right { if initial { visible.x + visible.width } else { visible.x + visible.width - window.width } } else { cx } },
		y: match position { .top { if initial { visible.y + visible.height } else { visible.y + visible.height - window.height } } .bottom { if initial { -window.height } else { visible.y } } .center { if initial { visible.height - window.width } else { cy } } else { cy } }}
}
pub struct QuickScreenEntry {
pub:
	frame SplitBounds
	screen_width f64
	screen_height f64
	scale f64
pub mut:
	last_seen f64
}
pub fn (e QuickScreenEntry) valid(width f64, height f64, scale f64) bool { return e.scale == scale && e.screen_width <= width && e.screen_height <= height }
pub struct QuickScreenCache { pub mut: entries map[string]QuickScreenEntry }
pub fn (mut c QuickScreenCache) prune_capacity() {
	if c.entries.len <= 10 { return }
	mut keys := c.entries.keys()
	keys.sort_with_compare(fn [c] (a &string, b &string) int { return if c.entries[*a].last_seen < c.entries[*b].last_seen { -1 } else if c.entries[*a].last_seen > c.entries[*b].last_seen { 1 } else { 0 } })
	for key in keys[..keys.len - 10] { c.entries.delete(key) }
}
pub fn (mut c QuickScreenCache) prune_stale(present []string, now f64) {
	for key, entry in c.entries { if key !in present && now - entry.last_seen >= 14 * 24 * 60 * 60 { c.entries.delete(key) } }
	c.prune_capacity()
}
