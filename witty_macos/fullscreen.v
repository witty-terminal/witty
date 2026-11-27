module witty_macos

pub enum NativeFullscreenMode { native non_native visible_menu padded_notch }

// Fullscreen.NonNativeFullscreen.fullscreenFrame, preserving its manual
// menu/notch accounting instead of NSScreen.visibleFrame.
pub fn fullscreen_frame(screen SplitBounds, presentation u64, menu_height f64, notch_top f64, mode NativeFullscreenMode) SplitBounds {
	mut result := screen
	if presentation & (u64(1 << 2) | u64(1 << 3)) == 0 { result.height -= menu_height }
	else if mode == .padded_notch { result.height -= notch_top }
	return result
}
