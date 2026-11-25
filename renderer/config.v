module renderer

import terminal
import configpkg
import math

// The configuration for this renderer that is derived from the main
// configuration. This must be exported so that we don't need to
// pass around Config pointers which makes memory management a pain.
pub struct DerivedConfig {
pub mut:
	// Whether to thicken font rendering.
	font_thicken bool
	// Strength of font thickening (0-255).
	font_thicken_strength u8
	// Font features to enable (e.g. "liga", "calt").
	font_features []string
	// Which font styles are enabled.
	font_styles FontStyleStatus
	// How to break font shaping runs.
	font_shaping_break configpkg.FontShapingBreak
	// Compiled regular-expression link matchers.
	links LinkSet
	// Cursor color, if set.
	cursor_color ?configpkg.TerminalColor
	// Cursor opacity (0.0 to 1.0).
	cursor_opacity f64 = 1.0
	// Cursor text color, if set.
	cursor_text ?configpkg.TerminalColor
	// Default background color.
	background terminal.RGB = terminal.RGB{
		r: 0
		g: 0
		b: 0
	}
	// Background opacity (0.0 to 1.0).
	background_opacity f64 = 1.0
	// Whether to apply background opacity to cells with explicit bg colors.
	background_opacity_cells bool
	// Default foreground color.
	foreground terminal.RGB = terminal.RGB{
		r: 255
		g: 255
		b: 255
	}
	// Selection background color override.
	selection_background ?configpkg.TerminalColor
	// Selection foreground color override.
	selection_foreground ?configpkg.TerminalColor
	// Search match background color.
	search_background configpkg.TerminalColor = configpkg.TerminalColorColor{
		color: configpkg.ColorRGB{ r: 0xff, g: 0xe0, b: 0x82 }
	}
	// Search match foreground color.
	search_foreground configpkg.TerminalColor = configpkg.TerminalColorColor{
		color: configpkg.ColorRGB{ r: 0, g: 0, b: 0 }
	}
	// Selected search match background color.
	search_selected_background configpkg.TerminalColor = configpkg.TerminalColorColor{
		color: configpkg.ColorRGB{ r: 0xf2, g: 0xa5, b: 0x7e }
	}
	// Selected search match foreground color.
	search_selected_foreground configpkg.TerminalColor = configpkg.TerminalColorColor{
		color: configpkg.ColorRGB{ r: 0, g: 0, b: 0 }
	}
	// Bold color override.
	bold_color ?terminal.BoldColor
	// Opacity for faint text (SGR 2), as a u8 (0-255).
	faint_opacity u8 = 128
	// Minimum contrast ratio for text against background.
	min_contrast f32
	// How to color the padding area.
	padding_color configpkg.WindowPaddingColor = .background
	// Whether a new terminal row should return the viewport to the bottom.
	scroll_to_bottom_on_output bool
	// Custom shader paths.
	custom_shaders configpkg.RepeatablePath
	custom_shader_animation configpkg.CustomShaderAnimation = .true_
	// Background image path.
	bg_image ?configpkg.Path
	// Background image opacity (0.0 to 1.0).
	bg_image_opacity f32 = 1.0
	// Background image position.
	bg_image_position configpkg.BackgroundImagePosition = .center
	// Background image fit mode.
	bg_image_fit configpkg.BackgroundImageFit = .contain
	// Whether the background image should repeat.
	bg_image_repeat bool
	// Whether to enable vsync.
	vsync bool = true
	// Which color space to use.
	colorspace configpkg.WindowColorspace = .srgb
	// Alpha blending mode.
	blending configpkg.AlphaBlending = .native
	// Background blur mode.
	background_blur configpkg.BackgroundBlur = configpkg.BackgroundBlurFalse{}
}

// FontStyleStatus tracks which font styles are enabled.
pub struct FontStyleStatus {
pub mut:
	bold        bool = true
	italic      bool = true
	bold_italic bool = true
}

// Initialize a DerivedConfig from a full configpkg.Config.
pub fn DerivedConfig.init(config &configpkg.Config) !DerivedConfig {
	// Get our font styles. A style is enabled unless its config value is
	// explicitly "false" (matching ghostty's `font-style-* != .false`).
	font_styles := FontStyleStatus{
		bold: !config.font_style_bold.is_false()
		italic: !config.font_style_italic.is_false()
		bold_italic: !config.font_style_bold_italic.is_false()
	}

	bg := terminal.RGB{
		r: config.background.r
		g: config.background.g
		b: config.background.b
	}
	fg := terminal.RGB{
		r: config.foreground.r
		g: config.foreground.g
		b: config.foreground.b
	}
	links := LinkSet.from_config(config.link.links)!
	custom_shaders := config.custom_shader.clone()!
	bg_image := if configured_bg_image := config.background_image {
		configured_bg_image.clone()!
	} else {
		none
	}

	return DerivedConfig{
		background_opacity: clamp_f64(config.background_opacity, 0.0, 1.0)
		background_opacity_cells: config.background_opacity_cells
		font_thicken: config.font_thicken
		font_thicken_strength: config.font_thicken_strength
		font_features: config.font_feature.clone()
		font_styles: font_styles
		font_shaping_break: config.font_shaping_break
		links: links
		cursor_color: config.cursor_color
		cursor_text: config.cursor_text
		cursor_opacity: clamp_f64(config.cursor_opacity, 0.0, 1.0)
		background: bg
		foreground: fg
		bold_color: if bold := config.bold_color {
			match bold {
				configpkg.BoldColorBright { terminal.BoldColor(terminal.BoldColorBright{}) }
				configpkg.BoldColorColor {
					terminal.BoldColor(terminal.BoldColorColor{
						color: terminal.RGB{
							r: bold.color.r
							g: bold.color.g
							b: bold.color.b
						}
					})
				}
			}
		} else {
			none
		}
		faint_opacity: u8(math.ceil(config.faint_opacity * 255))
		min_contrast: f32(config.minimum_contrast)
		padding_color: config.window_padding_color
		scroll_to_bottom_on_output: config.scroll_to_bottom.output()
		selection_background: config.selection_background
		selection_foreground: config.selection_foreground
		search_background: config.search_background
		search_foreground: config.search_foreground
		search_selected_background: config.search_selected_background
		search_selected_foreground: config.search_selected_foreground
		custom_shaders: custom_shaders
		custom_shader_animation: config.custom_shader_animation
		bg_image: bg_image
		bg_image_opacity: config.background_image_opacity
		bg_image_position: config.background_image_position
		bg_image_fit: config.background_image_fit
		bg_image_repeat: config.background_image_repeat
		vsync: config.window_vsync
		colorspace: config.window_colorspace
		blending: config.alpha_blending
		background_blur: config.background_blur
	}
}

fn shader_animation_enabled(mode configpkg.CustomShaderAnimation, focused bool) bool {
	return match mode {
		.false_ { false }
		.true_ { focused }
		.always { true }
	}
}

pub fn (mut c DerivedConfig) deinit() {
	c.font_features = []
	c.custom_shaders.items = []
	c.bg_image = none
	c.links.deinit()
}

// Clamp a float64 between min and max.
fn clamp_f64(val f64, min_val f64, max_val f64) f64 {
	if val < min_val {
		return min_val
	}
	if val > max_val {
		return max_val
	}
	return val
}
