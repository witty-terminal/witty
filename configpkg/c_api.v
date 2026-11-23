// Translated from Ghostty's src/config/c_get.zig.
//
// This file contains the C-compatible value projection used by
// ghostty_config_get. Values borrowed through pointers remain owned by Config.

module configpkg

import font as fontpkg
import input as inputpkg
import math
import buildcfg

// CConfigColor mirrors ghostty_config_color_s.
pub struct CConfigColor {
pub:
	r u8
	g u8
	b u8
}

// CConfigColorList mirrors ghostty_config_color_list_s.
pub struct CConfigColorList {
pub:
	colors &CConfigColor = unsafe { nil }
	len    uint
}

// CConfigCommandList mirrors ghostty_config_command_list_s.
pub struct CConfigCommandList {
pub:
	commands &inputpkg.CCommand = unsafe { nil }
	len      uint
}

// CConfigPalette mirrors ghostty_config_palette_s.
pub struct CConfigPalette {
pub mut:
	colors [256]CConfigColor
}

// CQuickTerminalSize mirrors ghostty_quick_terminal_size_s. Its value field is
// the four-byte storage shared by the C union's f32 and u32 alternatives.
pub enum CQuickTerminalSizeTag as i32 {
	none
	percentage
	pixels
}

pub struct CQuickTerminalSize {
pub:
	tag   CQuickTerminalSizeTag
	value u32
}

pub fn CQuickTerminalSize.percentage(value f32) CQuickTerminalSize {
	return CQuickTerminalSize{
		tag: .percentage
		value: math.f32_bits(value)
	}
}

pub fn CQuickTerminalSize.pixels(value u32) CQuickTerminalSize {
	return CQuickTerminalSize{
		tag: .pixels
		value: value
	}
}

// CConfigQuickTerminalSize mirrors ghostty_config_quick_terminal_size_s.
pub struct CConfigQuickTerminalSize {
pub:
	primary   CQuickTerminalSize
	secondary CQuickTerminalSize
}

pub fn (q QuickTerminalSize) cval() CConfigQuickTerminalSize {
	return CConfigQuickTerminalSize{
		primary: quick_terminal_size_value_cval(q.primary)
		secondary: quick_terminal_size_value_cval(q.secondary)
	}
}

// c_get writes the requested configuration value using the exact projection
// rules from config/c_get.zig: primitives, optionals, enums as borrowed C
// strings, types with cval projections, and the small packed flag structs.
pub fn (mut c Config) c_get(key string, ptr voidptr) bool {
	if isnil(ptr) {
		return false
	}
	normalized_key := key.replace('-', '_')
	// `class` is a C keyword, so V emits the backing field as `_class`. Dynamic
	// comptime field access does not apply that escape in generated C.
	if normalized_key == 'class' {
		value := c.class or {
			c_write_cstring(ptr, unsafe { nil })
			return true
		}
		c_write_cstring(ptr, &char(value.str))
		return true
	}
	$for field in Config.fields {
		$if field.name != 'class' {
			if field.name.len > 0 && field.name[0] != `_` && field.name == normalized_key
				&& field.name !in ['diagnostics', 'conditional_state', 'conditional_set',
					'replay_steps', 'xdg_terminal_exec', 'capi_strings'] {
				$if field.unaliased_typ is string {
					c_write_cstring(ptr, &char(c.$(field.name).str))
					return true
				} $else $if field.unaliased_typ is ?string {
					if c.$(field.name) == none {
						c_write_cstring(ptr, unsafe { nil })
						return true
					}
					value := c.$(field.name)?
					c_write_cstring(ptr, &char(value.str))
					return true
				} $else $if field.unaliased_typ is bool {
					c_write_value[bool](ptr, c.$(field.name))
					return true
				} $else $if field.unaliased_typ is ?bool {
					if c.$(field.name) == none {
						return false
					}
					c_write_value[bool](ptr, c.$(field.name)?)
					return true
				} $else $if field.unaliased_typ is u8 {
					c_write_value[u32](ptr, u32(c.$(field.name)))
					return true
				} $else $if field.unaliased_typ is u32 {
					c_write_value[u32](ptr, c.$(field.name))
					return true
				} $else $if field.unaliased_typ is i16 {
					c_write_value[i16](ptr, c.$(field.name))
					return true
				} $else $if field.unaliased_typ is ?i16 {
					if c.$(field.name) == none {
						return false
					}
					c_write_value[i16](ptr, c.$(field.name)?)
					return true
				} $else $if field.unaliased_typ is f32 {
					c_write_value[f32](ptr, c.$(field.name))
					return true
				} $else $if field.unaliased_typ is f64 {
					c_write_value[f64](ptr, c.$(field.name))
					return true
				} $else $if field.unaliased_typ is ?ColorRGB {
					if c.$(field.name) == none {
						return false
					}
					c_write_value[CConfigColor](ptr, c.$(field.name)?.cval())
					return true
				} $else $if field.unaliased_typ is ?ColorList {
					if c.$(field.name) == none {
						return false
					}
					c_write_value[CConfigColorList](ptr, c.$(field.name)?.cval())
					return true
				} $else $if field.unaliased_typ is ?Duration {
					if c.$(field.name) == none {
						return false
					}
					c_write_value[uint](ptr, c.$(field.name)?.cval())
					return true
				} $else $if field.unaliased_typ is ?AutoUpdate {
					if c.$(field.name) == none {
						return false
					}
					c_write_cstring(ptr, c.cache_c_string(key, enum_c_name(c.$(field.name)?.str())))
					return true
				} $else $if field.unaliased_typ is ?buildcfg.ReleaseChannel {
					if c.$(field.name) == none {
						return false
					}
					c_write_cstring(ptr, c.cache_c_string(key, enum_c_name(c.$(field.name)?.str())))
					return true
				} $else $if field.unaliased_typ is ?inputpkg.OptionAsAlt {
					if c.$(field.name) == none {
						return false
					}
					c_write_cstring(ptr, c.cache_c_string(key, enum_c_name(c.$(field.name)?.str())))
					return true
				} $else $if field.unaliased_typ is ColorRGB {
					c_write_value[CConfigColor](ptr, c.$(field.name).cval())
					return true
				} $else $if field.unaliased_typ is ColorList {
					c_write_value[CConfigColorList](ptr, c.$(field.name).cval())
					return true
				} $else $if field.unaliased_typ is Palette {
					c_write_value[CConfigPalette](ptr, c.$(field.name).cval())
					return true
				} $else $if field.unaliased_typ is RepeatableCommand {
					c_write_value[CConfigCommandList](ptr, c.$(field.name).cval())
					return true
				} $else $if field.unaliased_typ is QuickTerminalSize {
					c_write_value[CConfigQuickTerminalSize](ptr, c.$(field.name).cval())
					return true
				} $else $if field.unaliased_typ is BackgroundBlur {
					c_write_value[i16](ptr, c.$(field.name).cval())
					return true
				} $else $if field.unaliased_typ is Duration {
					c_write_value[uint](ptr, c.$(field.name).cval())
					return true
				} $else $if field.unaliased_typ is fontpkg.FontSyntheticStyle {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is FontShapingBreak {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is ShellIntegrationFeatures {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is SplitPreserveZoom {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is fontpkg.FreetypeLoadFlags {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is AppNotifications {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is BellFeatures {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is ScrollToBottom {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is NotifyOnCommandFinishAction {
					c_write_value[u32](ptr, u32(c.$(field.name).int_val()))
					return true
				} $else $if field.unaliased_typ is $enum {
					c_write_cstring(ptr, c.cache_c_string(key, enum_c_name(c.$(field.name).str())))
					return true
				} $else {
					return false
				}
			}
		}
	}
	return false
}

@[markused]
fn c_write_value[T](ptr voidptr, value T) {
	unsafe {
		vmemcpy(ptr, &value, sizeof(T))
	}
}

@[markused]
fn c_write_cstring(ptr voidptr, value &char) {
	unsafe {
		vmemcpy(ptr, &value, int(sizeof(voidptr)))
	}
}

@[markused]
fn (mut c Config) cache_c_string(key string, value string) &char {
	c.capi_strings[key] = value
	stored := c.capi_strings[key]
	return &char(stored.str)
}

// c_diagnostic_message returns the preformatted diagnostic text through
// Config-owned storage. Witty's DiagnosticList precomputes this text when a
// diagnostic is appended; the cache provides the same C pointer lifetime in V.
pub fn (mut c Config) c_diagnostic_message(index int) &char {
	return c.cache_c_string('_diagnostic_${index}', c.diagnostics[index].format())
}

@[markused]
fn enum_c_name(value string) string {
	if value == 'format_8_bit' {
		return '8-bit'
	}
	if value == 'format_16_bit' {
		return '16-bit'
	}
	if value == 'io_uring' {
		return value
	}
	return value.trim_string_right('_').replace('_', '-')
}

@[markused]
fn quick_terminal_size_value_cval(value ?QuickTerminalSizeValue) CQuickTerminalSize {
	actual := value or { return CQuickTerminalSize{} }
	return match actual {
		QuickTerminalSizePercentage { CQuickTerminalSize.percentage(actual.value) }
		QuickTerminalSizePixels { CQuickTerminalSize.pixels(actual.value) }
	}
}
