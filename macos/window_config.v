module macos

import math

// TerminalWindow.DerivedConfig and SurfaceView.DerivedConfig. Primitive values
// keep this native projection independent of the core configuration module.
pub struct NativeWindowConfig {
pub:
	title ?string
	window_title_font_family ?string
	decorations bool = true
	position_x ?i16
	position_y ?i16
	buttons_hidden bool
	shadow bool = true
	titlebar_style int
	theme int
	background u32
	opacity f64 = 1
	blur i16
	step_resize bool
	proxy_icon bool = true
	preserve_split_zoom bool
	unfocused_split_opacity f64 = 0.7
	unfocused_split_fill ?u32
	split_divider_color ?u32
	focus_follows_mouse bool
	maximize bool
}
pub fn native_color_luminance(color u32) f64 {
	return (0.299 * f64((color >> 16) & 255) + 0.587 * f64((color >> 8) & 255) + 0.114 * f64(color & 255)) / 255
}
pub fn native_window_position(frame SplitBounds, visible SplitBounds, x i16, y i16) SplitBounds {
	return SplitBounds{x: visible.x + x, y: visible.y + visible.height - y - frame.height, width: frame.width, height: frame.height}
}
pub fn native_window_transparent(config NativeWindowConfig, native_fullscreen bool, force_opaque bool) bool {
	return !native_fullscreen && !force_opaque && (config.opacity < 1 || config.blur < 0)
}

fn restored_window_frame(frame SplitBounds, visible SplitBounds, saved SplitBounds, restore_origin bool, restore_size bool) SplitBounds {
	mut result := frame
	if restore_size {
		result.width = math.min(saved.width, visible.width)
		result.height = math.min(saved.height, visible.height)
	}
	if restore_origin {
		result.x = math.max(visible.x, math.min(visible.x + visible.width - result.width, saved.x))
		result.y = math.max(visible.y, math.min(visible.y + visible.height - result.height, saved.y))
	}
	return result
}
