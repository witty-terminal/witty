module terminal

import buildcfg

// Translated from ghostty/src/terminal/build_options.zig

// Options set by Zig build.zig and exposed via `terminal_options`.
pub struct BuildOptions {
pub:
	// The target artifact to build. This will gate some functionality.
	artifact Artifact = .ghostty
	// Whether Oniguruma regex support is available. If this isn't
	// available, some features will be disabled. This may be outdated,
	// but the specific disabled features are:
	//
	// - Kitty graphics protocol
	// - Tmux control mode
	//
	oniguruma bool
	// Whether to build SIMD-accelerated code paths. This pulls in more
	// build-time dependencies and adds libc as a runtime dependency,
	// but results in significant performance improvements.
	simd bool
	// True if we should enable the "slow" runtime safety checks. These
	// are runtime safety checks that are slower than typical and should
	// generally be disabled in production builds.
	slow_runtime_safety bool
	// Force C ABI mode on or off. If not set, then it will be set based on
	// Options.
	c_abi bool
}

pub enum Artifact as u8 {
	// Ghostty application
	ghostty
	// libwitty-vt, Zig module
	lib
}

// Synthesized terminal module options for this build. Ghostty derives both
// protocol features directly from its Oniguruma option.
pub const oniguruma = buildcfg.oniguruma
pub const kitty_graphics = buildcfg.kitty_graphics
pub const tmux_control_mode = buildcfg.tmux_control_mode
