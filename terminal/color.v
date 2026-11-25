module terminal

// color.v - Color types for the terminal emulator.
//
// Translated from Ghostty's terminal/color.zig.
//
// Contains:
// - RGB struct methods (parse, luminance, contrast, etc.)
// - DynamicPalette with current/original palettes and mask bitset
// - DynamicRGB with override/default optional RGBs
// - Name enum for the 16 named colors
// - Special enum for bold/underline/blink/reverse/italic
// - Dynamic enum for foreground/background/cursor etc
// - BoldColor

import math
import zig_fmt

// ============================================================
// Palette - the 256 color palette.
// ============================================================

// The default palette, computed at init time.
// Contains: 16 named colors + 216 color cube + 24 grayscale ramp.
pub const default_palette = init_default_palette()

// init_default_palette computes the default 256-color palette.
// The first 16 entries are the named colors, the next 216 are a
// 6x6x6 color cube, and the last 24 are a grayscale ramp.
fn init_default_palette() [256]RGB {
	mut result := [256]RGB{}

	// Named values (0..15)
	for i in 0 .. 16 {
		result[i] = unsafe { Name(u8(i)) }.default() or {
			panic('unreachable: named palette color has no default')
		}
	}

	// 6x6x6 color cube (indices 16..231)
	mut idx := 16
	for r in 0 .. 6 {
		for g in 0 .. 6 {
			for b in 0 .. 6 {
				result[idx] = RGB{
					r: if r == 0 { u8(0) } else { u8(r * 40 + 55) }
					g: if g == 0 { u8(0) } else { u8(g * 40 + 55) }
					b: if b == 0 { u8(0) } else { u8(b * 40 + 55) }
				}
				idx += 1
			}
		}
	}

	// Grayscale ramp (indices 232..255)
	for i in 232 .. 256 {
		value := u8((i - 232) * 10 + 8)
		result[i] = RGB{
			r: value
			g: value
			b: value
		}
	}

	return result
}

// ============================================================
// DynamicPalette - a palette that can have its colors changed
// and reset. Purposely built for terminal color operations.
// ============================================================

// DynamicPalette is a palette that can have its colors changed and reset.
// It tracks which indices have been modified from their default values
// using a bitmask, allowing efficient reset and default-change operations.
pub struct DynamicPalette {
pub mut:
	// The current palette including any user modifications.
	current [256]RGB

	// The original/default palette values.
	original [256]RGB

	// A bitmask where each bit represents whether the corresponding
	// palette index has been modified from its default value.
	// Stored as 4 x u64 = 256 bits.
	mask [4]u64
}

// dynamic_palette_default is the default DynamicPalette initialized
// with the default 256-color palette.
pub const dynamic_palette_default_val = DynamicPalette.init(default_palette)

// init initializes a dynamic palette with a default palette.
pub fn DynamicPalette.init(def [256]RGB) DynamicPalette {
	return DynamicPalette{
		current: def
		original: def
		mask: [4]u64{}
	}
}

// set sets a custom color at the given palette index.
pub fn (mut self DynamicPalette) set(idx u8, color RGB) {
	self.current[int(idx)] = color
	self.mask_set(idx)
}

// reset resets the color at the given palette index to its original value.
pub fn (mut self DynamicPalette) reset(idx u8) {
	self.current[int(idx)] = self.original[int(idx)]
	self.mask_unset(idx)
}

// reset_all resets all colors to their original values.
pub fn (mut self DynamicPalette) reset_all() {
	new := DynamicPalette.init(self.original)
	self.current = new.current
	self.original = new.original
	self.mask = new.mask
}

// change_default changes the default palette, but preserves the changed values.
pub fn (mut self DynamicPalette) change_default(def [256]RGB) {
	self.original = def

	// Fast path: the palette is usually not changed.
	if self.mask_count() == 0 {
		self.current = self.original
		return
	}

	// There are usually less set than unset, so iterate over the changed
	// values and override them.
	mut current := self.original
	for i in 0 .. 256 {
		if self.mask_is_set(u8(i)) {
			current[i] = self.current[i]
		}
	}
	self.current = current
}

// mask_set sets the bit for the given index in the bitmask.
fn (mut self DynamicPalette) mask_set(idx u8) {
	word := int(idx) >> 6
	bit := int(idx) & 63
	self.mask[word] |= u64(1) << bit
}

// mask_unset clears the bit for the given index in the bitmask.
fn (mut self DynamicPalette) mask_unset(idx u8) {
	word := int(idx) >> 6
	bit := int(idx) & 63
	self.mask[word] &= ~(u64(1) << bit)
}

// mask_is_set returns whether the bit for the given index is set.
pub fn (self &DynamicPalette) mask_is_set(idx u8) bool {
	word := int(idx) >> 6
	bit := int(idx) & 63
	return (self.mask[word] >> bit) & 1 != 0
}

// mask_count returns the number of set bits in the bitmask.
pub fn (self &DynamicPalette) mask_count() uint {
	mut count := uint(0)
	for w in self.mask {
		mut v := w
		for v != 0 {
			v &= v - 1
			count += 1
		}
	}
	return count
}

// ============================================================
// DynamicRGB - RGB value that can be changed and reset.
// This can also be totally unset in every way, in which case
// the caller can determine their own ultimate default.
// ============================================================

pub struct DynamicRGB {
pub mut:
	override_color ?RGB
	default_color  ?RGB
}

// dynamic_rgb_unset is a DynamicRGB with no override and no default.
pub const dynamic_rgb_unset = DynamicRGB{
	override_color: none
	default_color: none
}

// init_dynamic_rgb creates a DynamicRGB with a default color and no override.
pub fn DynamicRGB.init(def RGB) DynamicRGB {
	return DynamicRGB{
		override_color: none
		default_color: def
	}
}

// get returns the effective color: override if set, otherwise default.
pub fn (self &DynamicRGB) get() ?RGB {
	return self.override_color or { return self.default_color }
}

// set sets the override color.
pub fn (mut self DynamicRGB) set(color RGB) {
	self.override_color = color
}

// reset clears the override so the effective color follows the configured default.
pub fn (mut self DynamicRGB) reset() {
	self.override_color = none
}

// ============================================================
// Name - color names in the standard 8 or 16 color palette.
// ============================================================

// Name represents the 16 named ANSI colors plus unnamed
// values in the 256-color palette.
pub enum Name as u8 {
	black          = 0
	red            = 1
	green          = 2
	yellow         = 3
	blue           = 4
	magenta        = 5
	cyan           = 6
	white          = 7
	bright_black   = 8
	bright_red     = 9
	bright_green   = 10
	bright_yellow  = 11
	bright_blue    = 12
	bright_magenta = 13
	bright_cyan    = 14
	bright_white   = 15
}

// cval returns the underlying u8 value.
pub fn (self Name) cval() u8 {
	return u8(self)
}

// default returns the default RGB value for a named color.
pub fn (self Name) default() !RGB {
	if u8(self) >= 16 {
		return error('no default value')
	}
	return match self {
		.black { RGB{ r: 0x1d, g: 0x1f, b: 0x21 } }
		.red { RGB{ r: 0xcc, g: 0x66, b: 0x66 } }
		.green { RGB{ r: 0xb5, g: 0xbd, b: 0x68 } }
		.yellow { RGB{ r: 0xf0, g: 0xc6, b: 0x74 } }
		.blue { RGB{ r: 0x81, g: 0xa2, b: 0xbe } }
		.magenta { RGB{ r: 0xb2, g: 0x94, b: 0xbb } }
		.cyan { RGB{ r: 0x8a, g: 0xbe, b: 0xb7 } }
		.white { RGB{ r: 0xc5, g: 0xc8, b: 0xc6 } }
		.bright_black { RGB{ r: 0x66, g: 0x66, b: 0x66 } }
		.bright_red { RGB{ r: 0xd5, g: 0x4e, b: 0x53 } }
		.bright_green { RGB{ r: 0xb9, g: 0xca, b: 0x4a } }
		.bright_yellow { RGB{ r: 0xe7, g: 0xc5, b: 0x47 } }
		.bright_blue { RGB{ r: 0x7a, g: 0xa6, b: 0xda } }
		.bright_magenta { RGB{ r: 0xc3, g: 0x97, b: 0xd8 } }
		.bright_cyan { RGB{ r: 0x70, g: 0xc0, b: 0xb1 } }
		.bright_white { RGB{ r: 0xea, g: 0xea, b: 0xea } }
	}
}

// ============================================================
// Special - the "special colors" as denoted by xterm. These can
// be set via OSC 5 or via OSC 4 by adding the palette length to it.
//
// https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
// ============================================================

pub enum Special as u8 {
	bold      = 0
	underline = 1
	blink     = 2
	reverse   = 3
	italic    = 4
}

// osc4 returns the OSC 4 index for this special color.
// "The special colors can also be set by adding the maximum
// number of colors (e.g., 88 or 256) to these codes in an
// OSC 4 control" - xterm ctlseqs
pub fn (self Special) osc4() u16 {
	return u16(u8(self)) + 256
}

// ============================================================
// Dynamic - the "dynamic colors" as denoted by xterm. These can
// be set via OSC 10 through 19.
// ============================================================

pub enum Dynamic as u8 {
	foreground           = 10
	background           = 11
	cursor               = 12
	pointer_foreground   = 13
	pointer_background   = 14
	tektronix_foreground = 15
	tektronix_background = 16
	highlight_background = 17
	tektronix_cursor     = 18
	highlight_foreground = 19
}

// next returns the next dynamic color sequentially. This is required because
// specifying colors sequentially without their index will automatically
// use the next dynamic color.
//
// "Each successive parameter changes the next color in the list. The
// value of Ps tells the starting point in the list."
//
// Returns none if there is no next dynamic color.
pub fn (self Dynamic) next() ?Dynamic {
	next_val := u8(self) + 1
	if next_val > 19 {
		return none
	}
	return unsafe { Dynamic(next_val) }
}

// ============================================================
// RGB methods - parse, luminance, contrast, etc.
// Note: the RGB struct itself is defined in terminal.v.
// The eql method is defined in style.v.
// ============================================================

// RGBC is the C-compatible, padding-free representation returned by RGB.cval.
pub struct RGBC {
pub:
	r u8
	g u8
	b u8
}

pub fn (self RGB) cval() RGBC {
	return RGBC{
		r: self.r
		g: self.g
		b: self.b
	}
}

// contrast calculates the contrast ratio between two colors. The contrast
// ratio is a value between 1 and 21 where 1 is the lowest contrast
// and 21 is the highest contrast.
//
// https://www.w3.org/TR/WCAG20/#contrast-ratiodef
pub fn (self RGB) contrast(other RGB) f64 {
	self_lum := self.luminance()
	other_lum := other.luminance()
	// pair[0] = lighter, pair[1] = darker
	lighter := if self_lum > other_lum { self_lum } else { other_lum }
	darker := if self_lum > other_lum { other_lum } else { self_lum }
	return (lighter + 0.05) / (darker + 0.05)
}

// luminance calculates luminance based on the W3C formula. This returns a
// normalized value between 0 and 1 where 0 is black and 1 is white.
//
// https://www.w3.org/TR/WCAG20/#relativeluminancedef
pub fn (self RGB) luminance() f64 {
	r_lum := component_luminance(self.r)
	g_lum := component_luminance(self.g)
	b_lum := component_luminance(self.b)
	return 0.2126 * r_lum + 0.7152 * g_lum + 0.0722 * b_lum
}

// component_luminance calculates single-component luminance based on the W3C formula.
//
// Expects sRGB color space which at the time of writing we don't
// generally use but it's a good enough approximation until we fix that.
// https://www.w3.org/TR/WCAG20/#relativeluminancedef
fn component_luminance(c u8) f64 {
	normalized := f64(c) / 255.0
	if normalized <= 0.03928 {
		return normalized / 12.92
	}
	return math.pow((normalized + 0.055) / 1.055, 2.4)
}

// perceived_luminance calculates "perceived luminance" which is better for
// determining light vs dark.
//
// Source: https://www.w3.org/TR/AERT/#color-contrast
pub fn (self RGB) perceived_luminance() f64 {
	r_f64 := f64(self.r)
	g_f64 := f64(self.g)
	b_f64 := f64(self.b)
	return 0.299 * (r_f64 / 255.0) + 0.587 * (g_f64 / 255.0) + 0.114 * (b_f64 / 255.0)
}

// from_intensity parses a color component from a floating point intensity value.
// The value should be between 0.0 and 1.0, inclusive.
fn from_intensity(value string) ?u8 {
	i := zig_fmt.parse_f64(value) or {
		return none
	}
	if i < 0.0 || i > 1.0 {
		return none
	}
	return u8(i * 255.0)
}

// from_hex parses a color component from a string of hexadecimal digits.
//
// The string can contain 1, 2, 3, or 4 characters and represents the color
// value scaled in 4, 8, 12, or 16 bits, respectively.
fn from_hex(value string) ?u8 {
	if value.len == 0 || value.len > 4 {
		return none
	}

	color := zig_fmt.parse_unsigned(value, 65535, 16) or { return none }

	divisor := match value.len {
		1 { u64(0xf) } // maxInt(u4) = 15
		2 { u64(0xff) } // maxInt(u8) = 255
		3 { u64(0xfff) } // maxInt(u12) = 4095
		4 { u64(0xffff) } // maxInt(u16) = 65535
		else {
			panic('unreachable: hexadecimal component length was prevalidated')
		}
	}

	return u8(u64(color) * 255 / divisor)
}

// parse parses a color specification string.
//
// Any of the following forms are accepted:
//
// 1. rgb:<red>/<green>/<blue>
//
//    <red>, <green>, <blue> := h | hh | hhh | hhhh
//
//    where `h` is a single hexadecimal digit.
//
// 2. rgbi:<red>/<green>/<blue>
//
//    where <red>, <green>, and <blue> are floating point values between
//    0.0 and 1.0 (inclusive).
//
// 3. #rgb, #rrggbb, #rrrgggbbb #rrrrggggbbbb
//
//    where `r`, `g`, and `b` are a single hexadecimal digit.
//    These specify a color with 4, 8, 12, and 16 bits of precision
//    per color channel.
pub fn RGB.parse(value string) ?RGB {
	if value.len == 0 {
		return none
	}

	if value[0] == `#` {
		match value.len {
			4 {
				return RGB{
					r: from_hex(value[1..2]) or { return none }
					g: from_hex(value[2..3]) or { return none }
					b: from_hex(value[3..4]) or { return none }
				}
			}
			7 {
				return RGB{
					r: from_hex(value[1..3]) or { return none }
					g: from_hex(value[3..5]) or { return none }
					b: from_hex(value[5..7]) or { return none }
				}
			}
			10 {
				return RGB{
					r: from_hex(value[1..4]) or { return none }
					g: from_hex(value[4..7]) or { return none }
					b: from_hex(value[7..10]) or { return none }
				}
			}
			13 {
				return RGB{
					r: from_hex(value[1..5]) or { return none }
					g: from_hex(value[5..9]) or { return none }
					b: from_hex(value[9..13]) or { return none }
				}
			}
			else {
				return none
			}
		}
	}

	// Check for X11 named colors. We allow whitespace around the edges
	// of the color because Kitty allows whitespace. This is not part of
	// any spec I could find.
	trimmed := value.trim(' ')
	x11 := x11_color_get(trimmed)
	if x11 != none {
		return x11
	}

	if value.len < 'rgb:a/a/a'.len || value[..3] != 'rgb' {
		return none
	}

	mut i := 3

	mut use_intensity := false
	if value[i] == `i` {
		use_intensity = true
		i += 1
	}

	if value[i] != `:` {
		return none
	}
	i += 1

	// Parse red component
	r_end := value.index_after('/', i) or { return none }
	r_slice := value[i..r_end]
	i = r_end + 1

	r := if use_intensity {
		from_intensity(r_slice) or { return none }
	} else {
		from_hex(r_slice) or { return none }
	}

	// Parse green component
	g_end := value.index_after('/', i) or { return none }
	g_slice := value[i..g_end]
	i = g_end + 1

	g := if use_intensity {
		from_intensity(g_slice) or { return none }
	} else {
		from_hex(g_slice) or { return none }
	}

	// Parse blue component
	b_slice := value[i..]
	b := if use_intensity {
		from_intensity(b_slice) or { return none }
	} else {
		from_hex(b_slice) or { return none }
	}

	return RGB{
		r: r
		g: g
		b: b
	}
}

// ============================================================
// BoldColor
// ============================================================

// BoldColor is the cycle-boundary representation of Config.BoldColor used by
// terminal styles. Only the explicit-color arm carries an RGB value.
pub struct BoldColorBright {}

pub struct BoldColorColor {
pub:
	color RGB
}

pub type BoldColor = BoldColorBright | BoldColorColor
