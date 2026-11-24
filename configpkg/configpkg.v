module configpkg

import os
import io
import input as inputpkg
import terminal
import encoding.utf8.validate
import themepkg
import cli_args
import font
import internal_os
import zig_fmt
import diagnostics as diagnosticspkg
import buildcfg
import comma_splitter
import fontstyle
import log

const default_gtk_opengl_debug = $if debug { true } $else { false }
const default_quit_after_last_window_closed = $if linux { true } $else { false }
const default_linux_cgroup = $if linux { LinuxCgroup.single_instance } $else { LinuxCgroup.never }
const default_quick_terminal_autohide = $if macos { true } $else { false }
const default_font_size = $if macos { f32(13) } $else { f32(12) }
const config_template = $embed_file('config-template').to_string()

// --- Original Witty Comments Start: src/config/Config.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/config/Config.zig
//
// Config is the main config struct. These fields map directly to the
// CLI flag names hence we use a lot of `@""` syntax to support hyphens.
// Pandoc is used to automatically generate manual pages and other forms of
// documentation, so documentation comments on fields in the Config struct
// should use Pandoc's flavor of Markdown.
//
// For a reference to Pandoc's Markdown see their [online
// manual.](https://pandoc.org/MANUAL.html#pandocs-markdown)
// We do this instead of importing all of terminal/main.zig to
// limit the dependency graph. This is important because some things
// like the `witty-build-data` binary depend on the Config but don't
// want to include all the other stuff.
// Used on Unixes for some defaults.
// Witty 1.1 introduced background-blur support for Linux which
// doesn't support a specific radius value. The renaming is to let
// one field be used for both platforms (macOS retained the ability
// to set a radius).
// Witty 1.2 renamed all our adw options to gtk because we now have
// a hard dependency on libadwaita.
// Witty 1.2 removed the `hidden` value from `gtk-tabs-location` and
// moved it to `window-show-tab-bar`.
// Witty 1.2 lets you set `cell-foreground` and `cell-background`
// to match the cell foreground and background colors, respectively.
// This can be used with `cursor-color` and `cursor-text` to recreate
// this behavior. This applies to selection too.
// Witty 1.2 merged `bold-is-bright` into the new `bold-color`
// by setting the value to "bright".
// Witty 1.2 removed the "desktop" option and renamed it to "detect".
// The semantics also changed slightly but this is the correct mapping.
// Witty 1.3 rename the "window" option to "new-window".
// See: https://github.com/ghostty-org/ghostty/pull/9764
// The font families to use.
//
// You can generate the list of valid values using the CLI:
//
//     witty +list-fonts
//
// This configuration can be repeated multiple times to specify preferred
// fallback fonts when the requested codepoint is not available in the primary
// font. This is particularly useful for multiple languages, symbolic fonts,
// etc.
//
// Notes on emoji specifically: On macOS, Witty by default will always use
// Apple Color Emoji and on Linux will always use Noto Emoji. You can
// override this behavior by specifying a font family here that contains
// emoji glyphs.
//
// The specific styles (bold, italic, bold italic) do not need to be
// explicitly set. If a style is not set, then the regular style (font-family)
// will be searched for stylistic variants. If a stylistic variant is not
// found, Witty will use the regular style. This prevents falling back to a
// different font family just to get a style such as bold. This also applies
// if you explicitly specify a font family for a style. For example, if you
// set `font-family-bold = FooBar` and "FooBar" cannot be found, Witty will
// use whatever font is set for `font-family` for the bold style.
//
// Finally, some styles may be synthesized if they are not supported.
// For example, if a font does not have an italic style and no alternative
// italic font is specified, Witty will synthesize an italic style by
// applying a slant to the regular style. If you want to disable these
// synthesized styles then you can use the `font-style` configurations
// as documented below.
//
// You can disable styles completely by using the `font-style` set of
// configurations. See the documentation for `font-style` for more information.
//
// If you want to overwrite a previous set value rather than append a fallback,
// specify the value as `""` (empty string) to reset the list and then set the
// new values. For example:
//
//     font-family = ""
//     font-family = "My Favorite Font"
//
// Setting any of these as CLI arguments will automatically clear the
// values set in configuration files so you don't need to specify
// `--font-family=""` before setting a new value. You only need to specify
// this within config files if you want to clear previously set values in
// configuration files or on the CLI if you want to clear values set on the
// CLI.
// The named font style to use for each of the requested terminal font styles.
// This looks up the style based on the font style string advertised by the
// font itself. For example, "Iosevka Heavy" has a style of "Heavy".
//
// You can also use these fields to completely disable a font style. If you set
// the value of the configuration below to literal `false` then that font style
// will be disabled. If the running program in the terminal requests a disabled
// font style, the regular font style will be used instead.
//
// These are only valid if its corresponding font-family is also specified. If
// no font-family is specified, then the font-style is ignored unless you're
// disabling the font style.
// Control whether Witty should synthesize a style if the requested style is
// not available in the specified font-family.
//
// Witty can synthesize bold, italic, and bold italic styles if the font
// does not have a specific style. For bold, this is done by drawing an
// outline around the glyph of varying thickness. For italic, this is done by
// applying a slant to the glyph. For bold italic, both of these are applied.
//
// Synthetic styles are not perfect and will generally not look as good
// as a font that has the style natively. However, they are useful to
// provide styled text when the font does not have the style.
//
// Set this to "false" or "true" to disable or enable synthetic styles
// completely. You can disable specific styles using "no-bold", "no-italic",
// and "no-bold-italic". You can disable multiple styles by separating them
// with a comma. For example, "no-bold,no-italic".
//
// Available style keys are: `bold`, `italic`, `bold-italic`.
//
// If synthetic styles are disabled, then the regular style will be used
// instead if the requested style is not available. If the font has the
// requested style, then the font will be used as-is since the style is
// not synthetic.
//
// Warning: An easy mistake is to disable `bold` or `italic` but not
// `bold-italic`. Disabling only `bold` or `italic` will NOT disable either
// in the `bold-italic` style. If you want to disable `bold-italic`, you must
// explicitly disable it. You cannot partially disable `bold-italic`.
//
// By default, synthetic styles are enabled.
// Apply a font feature. To enable multiple font features you can repeat
// this multiple times or use a comma-separated list of feature settings.
//
// The syntax for feature settings is as follows, where `feat` is a feature:
//
//   * Enable features with e.g. `feat`, `+feat`, `feat on`, `feat=1`.
//   * Disabled features with e.g. `-feat`, `feat off`, `feat=0`.
//   * Set a feature value with e.g. `feat=2`, `feat = 3`, `feat 4`.
//   * Feature names may be wrapped in quotes, meaning this config should be
//     syntactically compatible with the `font-feature-settings` CSS property.
//
// The syntax is fairly loose, but invalid settings will be silently ignored.
//
// The font feature will apply to all fonts rendered by Witty. A future
// enhancement will allow targeting specific faces.
//
// To disable programming ligatures, use `-calt` since this is the typical
// feature name for programming ligatures. To look into what font features
// your font has and what they do, use a font inspection tool such as
// [fontdrop.info](https://fontdrop.info).
//
// To generally disable most ligatures, use `-calt, -liga, -dlig`.
// Font size in points. This value can be a non-integer and the nearest integer
// pixel size will be selected. If you have a high dpi display where 1pt = 2px
// then you can get an odd numbered pixel size by specifying a half point.
//
// For example, 13.5pt @ 2px/pt = 27px
//
// Changing this configuration at runtime will only affect existing
// terminals that have NOT manually adjusted their font size in some way
// (e.g. increased or decreased the font size). Terminals that have manually
// adjusted their font size will retain their manually adjusted size.
// Otherwise, the font size of existing terminals will be updated on
// reload.
//
// On Linux with GTK, font size is scaled according to both display-wide and
// text-specific scaling factors, which are often managed by your desktop
// environment (e.g. the GNOME display scale and large text settings).
// On macOS we default a little bigger since this tends to look better. This
// is purely subjective but this is easy to modify.
// A repeatable configuration to set one or more font variations values for
// a variable font. A variable font is a single font, usually with a filename
// ending in `-VF.ttf` or `-VF.otf` that contains one or more configurable axes
// for things such as weight, slant, etc. Not all fonts support variations;
// only fonts that explicitly state they are variable fonts will work.
//
// The format of this is `id=value` where `id` is the axis identifier. An axis
// identifier is always a 4 character string, such as `wght`. To get the list
// of supported axes, look at your font documentation or use a font inspection
// tool.
//
// Invalid ids and values are usually ignored. For example, if a font only
// supports weights from 100 to 700, setting `wght=800` will do nothing (it
// will not be clamped to 700). You must consult your font's documentation to
// see what values are supported.
//
// Common axes are: `wght` (weight), `slnt` (slant), `ital` (italic), `opsz`
// (optical size), `wdth` (width), `GRAD` (gradient), etc.
// Force one or a range of Unicode codepoints to map to a specific named font.
// This is useful if you want to support special symbols or if you want to use
// specific glyphs that render better for your specific font.
//
// The syntax is `codepoint=fontname` where `codepoint` is either a single
// codepoint or a range. Codepoints must be specified as full Unicode
// hex values, such as `U+ABCD`. Codepoints ranges are specified as
// `U+ABCD-U+DEFG`. You can specify multiple ranges for the same font separated
// by commas, such as `U+ABCD-U+DEFG,U+1234-U+5678=fontname`. The font name is
// the same value as you would use for `font-family`.
//
// This configuration can be repeated multiple times to specify multiple
// codepoint mappings.
//
// Changing this configuration at runtime will only affect new terminals,
// i.e. new windows, tabs, etc.
// Map specific Unicode codepoints to replacement values when copying text
// to clipboard.
//
// This configuration allows you to replace specific Unicode characters with
// other characters or strings when copying terminal content to the clipboard.
// This is useful for converting special terminal symbols to more compatible
// characters for pasting into other applications.
//
// The syntax is similar to `font-codepoint-map`:
// - Single codepoint: `U+1234=U+ABCD` or `U+1234=replacement_text`
// - Codepoint range: `U+1234-U+5678=U+ABCD`
//
// Examples:
// - `clipboard-codepoint-map = U+2500=U+002D` (box drawing horizontal → hyphen)
// - `clipboard-codepoint-map = U+2502=U+007C` (box drawing vertical → pipe)
// - `clipboard-codepoint-map = U+03A3=SUM` (Greek sigma → "SUM")
//
// This configuration can be repeated multiple times to specify multiple
// mappings. Later entries take priority over earlier ones for overlapping
// ranges.
//
// Note: This only applies to text copying operations, not URL copying.
// Draw fonts with a thicker stroke, if supported.
// This is currently only supported on macOS.
// Strength of thickening when `font-thicken` is enabled.
//
// Valid values are integers between `0` and `255`. `0` does not correspond to
// *no* thickening, rather it corresponds to the lightest available thickening.
//
// Has no effect when `font-thicken` is set to `false`.
//
// This is currently only supported on macOS.
// Locations to break font shaping into multiple runs.
//
// A "run" is a contiguous segment of text that is shaped together. "Shaping"
// is the process of converting text (codepoints) into glyphs (renderable
// characters). This is how ligatures are formed, among other things.
// For example, if a coding font turns "!=" into a single glyph, then it
// must see "!" and "=" next to each other in a single run. When a run
// is broken, the text is shaped separately. To continue our example, if
// "!" is at the end of one run and "=" is at the start of the next run,
// then the ligature will not be formed.
//
// Witty breaks runs at certain points to improve readability or usability.
// For example, Witty by default will break runs under the cursor so that
// text editing can see the individual characters rather than a ligature.
// This configuration lets you configure this behavior.
//
// Combine values with a comma to set multiple options. Prefix an
// option with "no-" to disable it. Enabling and disabling options
// can be done at the same time.
//
// Available options:
//
//   * `cursor` - Break runs under the cursor.
//
// Available since: 1.2.0
// What color space to use when performing alpha blending.
//
// This affects the appearance of text and of any images with transparency.
// Additionally, custom shaders will receive colors in the configured space.
//
// On macOS the default is `native`, on all other platforms the default is
// `linear-corrected`.
//
// Valid values:
//
// * `native` - Perform alpha blending in the native color space for the OS.
//   On macOS this corresponds to Display P3, and on Linux it's sRGB.
//
// * `linear` - Perform alpha blending in linear space. This will eliminate
//   the darkening artifacts around the edges of text that are very visible
//   when certain color combinations are used (e.g. red / green), but makes
//   dark text look much thinner than normal and light text much thicker.
//   This is also sometimes known as "gamma correction".
//
// * `linear-corrected` - Same as `linear`, but with a correction step applied
//   for text that makes it look nearly or completely identical to `native`,
//   but without any of the darkening artifacts.
//
// Available since: 1.1.0
// All of the configurations behavior adjust various metrics determined by the
// font. The values can be integers (1, -1, etc.) or a percentage (20%, -15%,
// etc.). In each case, the values represent the amount to change the original
// value.
//
// For example, a value of `1` increases the value by 1; it does not set it to
// literally 1. A value of `20%` increases the value by 20%. And so on.
//
// There is little to no validation on these values so the wrong values (e.g.
// `-100%`) can cause the terminal to be unusable. Use with caution and reason.
//
// Some values are clamped to minimum or maximum values. This can make it
// appear that certain values are ignored. For example, many `*-thickness`
// adjustments cannot go below 1px.
//
// `adjust-cell-height` has some additional behaviors to describe:
//
//   * The font will be centered vertically in the cell.
//
//   * The cursor will remain the same size as the font, but may be
//     adjusted separately with `adjust-cursor-height`.
//
//   * Powerline glyphs will be adjusted along with the cell height so
//     that things like status lines continue to look aligned.
// Distance in pixels or percentage adjustment from the bottom of the cell to the text baseline.
// Increase to move baseline UP, decrease to move baseline DOWN.
// See the notes about adjustments in `adjust-cell-width`.
// Distance in pixels or percentage adjustment from the top of the cell to the top of the underline.
// Increase to move underline DOWN, decrease to move underline UP.
// See the notes about adjustments in `adjust-cell-width`.
// Thickness in pixels of the underline.
// See the notes about adjustments in `adjust-cell-width`.
// Distance in pixels or percentage adjustment from the top of the cell to the top of the strikethrough.
// Increase to move strikethrough DOWN, decrease to move strikethrough UP.
// See the notes about adjustments in `adjust-cell-width`.
// Thickness in pixels or percentage adjustment of the strikethrough.
// See the notes about adjustments in `adjust-cell-width`.
// Distance in pixels or percentage adjustment from the top of the cell to the top of the overline.
// Increase to move overline DOWN, decrease to move overline UP.
// See the notes about adjustments in `adjust-cell-width`.
// Thickness in pixels or percentage adjustment of the overline.
// See the notes about adjustments in `adjust-cell-width`.
// Thickness in pixels or percentage adjustment of the bar cursor and outlined rect cursor.
// See the notes about adjustments in `adjust-cell-width`.
// Height in pixels or percentage adjustment of the cursor. Currently applies to all cursor types:
// bar, rect, and outlined rect.
// See the notes about adjustments in `adjust-cell-width`.
// Thickness in pixels or percentage adjustment of box drawing characters.
// See the notes about adjustments in `adjust-cell-width`.
// Height in pixels or percentage adjustment of maximum height for nerd font icons.
//
// A positive (negative) value will increase (decrease) the maximum icon
// height. This may not affect all icons equally: the effect depends on whether
// the default size of the icon is height-constrained, which in turn depends on
// the aspect ratio of both the icon and your primary font.
//
// Certain icons designed for box drawing and terminal graphics, such as
// Powerline symbols, are not affected by this option.
//
// See the notes about adjustments in `adjust-cell-width`.
//
// Available in: 1.2.0
// The method to use for calculating the cell width of a grapheme cluster.
// The default value is `unicode` which uses the Unicode standard to determine
// grapheme width. This results in correct grapheme width but may result in
// cursor-desync issues with some programs (such as shells) that may use a
// legacy method such as `wcswidth`.
//
// Valid values are:
//
// * `legacy` - Use a legacy method to determine grapheme width, such as
//   wcswidth This maximizes compatibility with legacy programs but may result
//   in incorrect grapheme width for certain graphemes such as skin-tone
//   emoji, non-English characters, etc.
//
//   This is called "legacy" and not something more specific because the
//   behavior is undefined and we want to retain the ability to modify it.
//   For example, we may or may not use libc `wcswidth` now or in the future.
//
// * `unicode` - Use the Unicode standard to determine grapheme width.
//
// If a running program explicitly enables terminal mode 2027, then `unicode`
// width will be forced regardless of this configuration. When mode 2027 is
// reset, this configuration will be used again.
//
// This configuration can be changed at runtime but will not affect existing
// terminals. Only new terminals will use the new configuration.
// FreeType load flags to enable. The format of this is a list of flags to
// enable separated by commas. If you prefix a flag with `no-` then it is
// disabled. If you omit a flag, its default value is used, so you must
// explicitly disable flags you don't want. You can also use `true` or `false`
// to turn all flags on or off.
//
// This configuration only applies to Witty builds that use FreeType.
// This is usually the case only for Linux builds. macOS uses CoreText
// and does not have an equivalent configuration.
//
// Available flags:
//
//   * `hinting` - Enable or disable hinting. Enabled by default.
//
//   * `force-autohint` - Always use the freetype auto-hinter instead of
//     the font's native hinter. Disabled by default.
//
//   * `monochrome` - Instructs renderer to use 1-bit monochrome rendering.
//     This will disable anti-aliasing, and probably not look very good unless
//     you're using a pixel font. Disabled by default.
//
//   * `autohint` - Enable the freetype auto-hinter. Enabled by default.
//
//   * `light` - Use a light hinting style, better preserving glyph shapes.
//     This is the most common setting in GTK apps and therefore also Witty's
//     default. This has no effect if `monochrome` is enabled. Enabled by
//     default.
//
// Example: `hinting`, `no-hinting`, `force-autohint`, `no-force-autohint`
// A theme to use. This can be a built-in theme name, a custom theme
// name, or an absolute path to a custom theme file. Witty also supports
// specifying a different theme to use for light and dark mode. Each
// option is documented below.
//
// If the theme is an absolute pathname, Witty will attempt to load that
// file as a theme. If that file does not exist or is inaccessible, an error
// will be logged and no other directories will be searched.
//
// If the theme is not an absolute pathname, two different directories will be
// searched for a file name that matches the theme. This is case sensitive on
// systems with case-sensitive filesystems. It is an error for a theme name to
// include path separators unless it is an absolute pathname.
//
// The first directory is the `themes` subdirectory of your Witty
// configuration directory. This is `$XDG_CONFIG_HOME/witty/themes` or
// `~/.config/witty/themes`.
//
// The second directory is the `themes` subdirectory of the Witty resources
// directory. Witty ships with a multitude of themes that will be installed
// into this directory. On macOS, this list is in the
// `Witty.app/Contents/Resources/witty/themes` directory. On Linux, this
// list is in the `share/witty/themes` directory (wherever you installed the
// Witty "share" directory.
//
// To see a list of available themes, run `witty +list-themes`.
//
// A theme file is simply another Witty configuration file. They share
// the same syntax and same configuration options. A theme can set any valid
// configuration option so please do not use a theme file from an untrusted
// source. The built-in themes are audited to only set safe configuration
// options.
//
// Some options cannot be set within theme files. The reason these are not
// supported should be self-evident. A theme file cannot set `theme` or
// `config-file`. At the time of writing this, Witty will not show any
// warnings or errors if you set these options in a theme file but they will
// be silently ignored.
//
// Any additional colors specified via background, foreground, palette, etc.
// will override the colors specified in the theme.
//
// To specify a different theme for light and dark mode, use the following
// syntax: `light:theme-name,dark:theme-name`. For example:
// `light:Rose Pine Dawn,dark:Rose Pine`. Whitespace around all values are
// trimmed and order of light and dark does not matter. Both light and dark
// must be specified in this form. In this form, the theme used will be
// based on the current desktop environment theme.
//
// There are some known bugs with light/dark mode theming. These will
// be fixed in a future update:
//
//   - macOS: titlebar tabs style is not updated when switching themes.
// Background color for the window.
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// Foreground color for the window.
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// Background image for the terminal.
//
// This should be a path to a PNG or JPEG file, other image formats are
// not yet supported.
//
// The background image is currently per-terminal, not per-window. If
// you are a heavy split user, the background image will be repeated across
// splits. A future improvement to Witty will address this.
//
// WARNING: Background images are currently duplicated in VRAM per-terminal.
// For sufficiently large images, this could lead to a large increase in
// memory usage (specifically VRAM usage). A future Witty improvement
// will resolve this by sharing image textures across terminals.
//
// Available since: 1.2.0
// Background image opacity.
//
// This is relative to the value of `background-opacity`.
//
// A value of `1.0` (the default) will result in the background image being
// placed on top of the general background color, and then the combined result
// will be adjusted to the opacity specified by `background-opacity`.
//
// A value less than `1.0` will result in the background image being mixed
// with the general background color before the combined result is adjusted
// to the configured `background-opacity`.
//
// A value greater than `1.0` will result in the background image having a
// higher opacity than the general background color. For instance, if the
// configured `background-opacity` is `0.5` and `background-image-opacity`
// is set to `1.5`, then the final opacity of the background image will be
// `0.5 * 1.5 = 0.75`.
//
// Available since: 1.2.0
// Background image position.
//
// Valid values are:
//   * `top-left`
//   * `top-center`
//   * `top-right`
//   * `center-left`
//   * `center`
//   * `center-right`
//   * `bottom-left`
//   * `bottom-center`
//   * `bottom-right`
//
// The default value is `center`.
//
// Available since: 1.2.0
// Background image fit.
//
// Valid values are:
//
//  * `contain`
//
//    Preserving the aspect ratio, scale the background image to the largest
//    size that can still be contained within the terminal, so that the whole
//    image is visible.
//
//  * `cover`
//
//    Preserving the aspect ratio, scale the background image to the smallest
//    size that can completely cover the terminal. This may result in one or
//    more edges of the image being clipped by the edge of the terminal.
//
//  * `stretch`
//
//    Stretch the background image to the full size of the terminal, without
//    preserving the aspect ratio.
//
//  * `none`
//
//    Don't scale the background image.
//
// The default value is `contain`.
//
// Available since: 1.2.0
// Whether to repeat the background image or not.
//
// If this is set to true, the background image will be repeated if there
// would otherwise be blank space around it because it doesn't completely
// fill the terminal area.
//
// The default value is `false`.
//
// Available since: 1.2.0
// The foreground and background color for selection. If this is not set, then
// the selection color is just the inverted window background and foreground
// (note: not to be confused with the cell bg/fg).
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// Since version 1.2.0, this can also be set to `cell-foreground` to match
// the cell foreground color, or `cell-background` to match the cell
// background color.
// Whether to clear selected text when typing. This defaults to `true`.
// This is typical behavior for most terminal emulators as well as
// text input fields. If you set this to `false`, then the selected text
// will not be cleared when typing.
//
// "Typing" is specifically defined as any non-modifier (shift, control,
// alt, etc.) keypress that produces data to be sent to the application
// running within the terminal (e.g. the shell). Additionally, selection
// is cleared when any preedit or composition state is started (e.g.
// when typing languages such as Japanese).
//
// If this is `false`, then the selection can still be manually
// cleared by clicking once or by pressing `escape`.
//
// Available since: 1.2.0
// Whether to clear selected text after copying. This defaults to `false`.
//
// When set to `true`, the selection will be automatically cleared after
// any copy operation that invokes the `copy_to_clipboard` keyboard binding.
// Importantly, this will not clear the selection if the copy operation
// was invoked via `copy-on-select`.
//
// When set to `false`, the selection remains visible after copying, allowing
// to see what was copied and potentially perform additional operations
// on the same selection.
// Characters that mark word boundaries during text selection operations such
// as double-clicking. When selecting a word, the selection will stop at any
// of these characters.
//
// This is similar to the `WORDCHARS` environment variable in zsh, except this
// specifies the boundary characters rather than the word characters. The
// default includes common delimiters and punctuation that typically separate
// words in code and prose.
//
// Each character in this string becomes a word boundary. Multi-byte UTF-8
// characters are supported, but only single codepoints can be specified.
// Multi-codepoint sequences (e.g. emoji) are not supported.
//
// The null character (U+0000) is always treated as a boundary and does not
// need to be included in this configuration.
//
// Default: ` \t'"│`|:;,()[]{}<>$`
//
// To add or remove specific characters, you can set this to a custom value.
// For example, to treat semicolons as part of words:
//
//     selection-word-chars = " \t'\"│`|:,()[]{}<>$"
//
// Available since: 1.3.0
// The minimum contrast ratio between the foreground and background colors.
// The contrast ratio is a value between 1 and 21. A value of 1 allows for no
// contrast (e.g. black on black). This value is the contrast ratio as defined
// by the [WCAG 2.0 specification](https://www.w3.org/TR/WCAG20/).
//
// If you want to avoid invisible text (same color as background), a value of
// 1.1 is a good value. If you want to avoid text that is difficult to read, a
// value of 3 or higher is a good value. The higher the value, the more likely
// that text will become black or white.
//
// This value does not apply to Emoji or images.
// Color palette for the 256 color form that many terminal applications use.
// The syntax of this configuration is `N=COLOR` where `N` is 0 to 255 (for
// the 256 colors in the terminal color table) and `COLOR` is a typical RGB
// color code such as `#AABBCC` or `AABBCC`, or a named X11 color. For example,
// `palette = 5=#BB78D9` will set the 'purple' color.
//
// The palette index can be in decimal, binary, octal, or hexadecimal.
// Decimal is assumed unless a prefix is used: `0b` for binary, `0o` for octal,
// and `0x` for hexadecimal.
//
// For definitions on the color indices and what they canonically map to,
// [see this cheat sheet](https://www.ditig.com/256-colors-cheat-sheet).
// The color of the cursor. If this is not set, a default will be chosen.
//
// Direct colors can be specified as either hex (`#RRGGBB` or `RRGGBB`)
// or a named X11 color.
//
// Additionally, special values can be used to set the color to match
// other colors at runtime:
//
//   * `cell-foreground` - Match the cell foreground color.
//     (Available since: 1.2.0)
//
//   * `cell-background` - Match the cell background color.
//     (Available since: 1.2.0)
// The opacity level (opposite of transparency) of the cursor. A value of 1
// is fully opaque and a value of 0 is fully transparent. A value less than 0
// or greater than 1 will be clamped to the nearest valid value. Note that a
// sufficiently small value such as 0.3 may be effectively invisible and may
// make it difficult to find the cursor.
// The style of the cursor. This sets the default style. A running program can
// still request an explicit cursor style using escape sequences (such as `CSI
// q`). Shell configurations will often request specific cursor styles.
//
// Note that shell integration will automatically set the cursor to a bar at
// a prompt, regardless of this configuration. You can disable that behavior
// by specifying `shell-integration-features = no-cursor` or disabling shell
// integration entirely.
//
// Valid values are:
//
//   * `block`
//   * `bar`
//   * `underline`
//   * `block_hollow`
// Sets the default blinking state of the cursor. This is just the default
// state; running programs may override the cursor style using `DECSCUSR` (`CSI
// q`).
//
// If this is not set, the cursor blinks by default. Note that this is not the
// same as a "true" value, as noted below.
//
// If this is not set at all (`null`), then Witty will respect DEC Mode 12
// (AT&T cursor blink) as an alternate approach to turning blinking on/off. If
// this is set to any value other than null, DEC mode 12 will be ignored but
// `DECSCUSR` will still be respected.
//
// Valid values are:
//
//   * ` ` (blank)
//   * `true`
//   * `false`
// The color of the text under the cursor. If this is not set, a default will
// be chosen.
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// Since version 1.2.0, this can also be set to `cell-foreground` to match
// the cell foreground color, or `cell-background` to match the cell
// background color.
// Enables the ability to move the cursor at prompts by using `alt+click` on
// Linux and `option+click` on macOS.
//
// This feature requires shell integration (specifically prompt marking
// via `OSC 133`) and only works in primary screen mode. Alternate screen
// applications like vim usually have their own version of this feature but
// this configuration doesn't control that.
//
// It should be noted that this feature works by translating your desired
// position into a series of synthetic arrow key movements, so some weird
// behavior around edge cases are to be expected. This is unfortunately how
// this feature is implemented across terminals because there isn't any other
// way to implement it.
// Hide the mouse immediately when typing. The mouse becomes visible again
// when the mouse is used (button, movement, etc.). Platform-specific behavior
// may dictate other scenarios where the mouse is shown. For example on macOS,
// the mouse is shown again when a new window, tab, or split is created.
// When to scroll the surface to the bottom. The format of this is a list of
// options to enable separated by commas. If you prefix an option with `no-`
// then it is disabled. If you omit an option, its default value is used.
//
// Available options:
//
// - `keystroke` If set, scroll the surface to the bottom when the user
//   presses a key that results in data being sent to the PTY (basically
//   anything but modifiers or keybinds that are processed by Witty).
//
// - `output` If set, scroll the surface to the bottom if there is new data
//   to display. (Currently unimplemented.)
//
// The default is `keystroke, no-output`.
// Determines whether running programs can detect the shift key pressed with a
// mouse click. Typically, the shift key is used to extend mouse selection.
//
// The default value of `false` means that the shift key is not sent with
// the mouse protocol and will extend the selection. This value can be
// conditionally overridden by the running program with the `XTSHIFTESCAPE`
// sequence.
//
// The value `true` means that the shift key is sent with the mouse protocol
// but the running program can override this behavior with `XTSHIFTESCAPE`.
//
// The value `never` is the same as `false` but the running program cannot
// override this behavior with `XTSHIFTESCAPE`. The value `always` is the
// same as `true` but the running program cannot override this behavior with
// `XTSHIFTESCAPE`.
//
// If you always want shift to extend mouse selection even if the program
// requests otherwise, set this to `never`.
//
// Valid values are:
//
//   * `true`
//   * `false`
//   * `always`
//   * `never`
// Enable or disable mouse reporting. When set to `false`, mouse events will
// not be reported to terminal applications even if they request it. This
// allows you to always use the mouse for selection and other terminal UI
// interactions without applications capturing mouse input.
//
// When set to `true` (the default), terminal applications can request mouse
// reporting and will receive mouse events according to their requested mode.
//
// This can be toggled at runtime using the `toggle_mouse_reporting` keybind
// action.
// Multiplier for scrolling distance with the mouse wheel.
//
// A prefix of `precision:` or `discrete:` can be used to set the multiplier
// only for scrolling with the specific type of devices. These can be
// comma-separated to set both types of multipliers at the same time, e.g.
// `precision:0.1,discrete:3`. If no prefix is used, the multiplier applies
// to all scrolling devices. Specifying a prefix was introduced in Witty
// 1.2.1.
//
// The value will be clamped to [0.01, 10,000]. Both of these are extreme
// and you're likely to have a bad experience if you set either extreme.
//
// The default value is "3" for discrete devices and "1" for precision devices.
// The opacity level (opposite of transparency) of the background. A value of
// 1 is fully opaque and a value of 0 is fully transparent. A value less than 0
// or greater than 1 will be clamped to the nearest valid value.
//
// On macOS, background opacity is disabled when the terminal enters native
// fullscreen. This is because the background becomes gray and it can cause
// widgets to show through which isn't generally desirable.
//
// On macOS, changing this configuration requires restarting Witty completely.
// Applies background opacity to cells with an explicit background color
// set.
//
// Normally, `background-opacity` is only applied to the window background.
// If a cell has an explicit background color set, such as red, then that
// background color will be fully opaque. An effect of this is that some
// terminal applications that repaint the background color of the terminal
// such as a Neovim and Tmux may not respect the `background-opacity`
// (by design).
//
// Setting this to `true` will apply the `background-opacity` to all cells
// regardless of whether they have an explicit background color set or not.
//
// Available since: 1.2.0
// Whether to blur the background when `background-opacity` is less than 1.
//
// Valid values are:
//
//   * a nonnegative integer specifying the *blur intensity*
//   * `false`, equivalent to a blur intensity of 0
//   * `true`, equivalent to the default blur intensity of 20, which is
//     reasonable for a good looking blur. Higher blur intensities may
//     cause strange rendering and performance issues.
//
// On macOS 26.0 and later, there are additional special values that
// can be set to use the native macOS glass effects:
//
//   * `macos-glass-regular` - Standard glass effect with some opacity
//   * `macos-glass-clear` - Highly transparent glass effect
//
// If the macOS values are set, then this implies `background-blur = true`
// on non-macOS platforms.
//
// Supported on macOS and on some Linux desktop environments, including:
//
//   * KDE Plasma (Wayland and X11)
//
// Warning: the exact blur intensity is _ignored_ under KDE Plasma, and setting
// this setting to either `true` or any positive blur intensity value would
// achieve the same effect. The reason is that KWin, the window compositor
// powering Plasma, only has one global blur setting and does not allow
// applications to specify individual blur settings.
//
// To configure KWin's global blur setting, open System Settings and go to
// "Apps & Windows" > "Window Management" > "Desktop Effects" and select the
// "Blur" plugin. If disabled, enable it by ticking the checkbox to the left.
// Then click on the "Configure" button and there will be two sliders that
// allow you to set background blur and noise intensities for all apps,
// including Witty.
//
// All other Linux desktop environments are as of now unsupported. Users may
// need to set environment-specific settings and/or install third-party plugins
// in order to support background blur, as there isn't a unified interface for
// doing so.
// The opacity level (opposite of transparency) of an unfocused split.
// Unfocused splits by default are slightly faded out to make it easier to see
// which split is focused. To disable this feature, set this value to 1.
//
// A value of 1 is fully opaque and a value of 0 is fully transparent. Because
// "0" is not useful (it makes the window look very weird), the minimum value
// is 0.15. This value still looks weird but you can at least see what's going
// on. A value outside of the range 0.15 to 1 will be clamped to the nearest
// valid value.
// The color to dim the unfocused split. Unfocused splits are dimmed by
// rendering a semi-transparent rectangle over the split. This sets the color of
// that rectangle and can be used to carefully control the dimming effect.
//
// This will default to the background color.
//
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// The color of the split divider. If this is not set, a default will be chosen.
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
//
// Available since: 1.1.0
// Control when Witty preserves a zoomed split. Under normal circumstances,
// any operation that changes focus or layout of the split tree in a window
// will unzoom any zoomed split. This configuration allows you to control
// this behavior.
//
// This can be set to `navigation` to preserve the zoomed split state
// when navigating to another split (e.g. via `goto_split`). This will
// change the zoomed split to the newly focused split instead of unzooming.
//
// Any options can also be prefixed with `no-` to disable that option.
//
// Example: `split-preserve-zoom = navigation`
//
// Available since: 1.3.0
// The foreground and background color for search matches. This only applies
// to non-focused search matches, also known as candidate matches.
//
// Valid values:
//
//   - Hex (`#RRGGBB` or `RRGGBB`)
//   - Named X11 color
//   - "cell-foreground" to match the cell foreground color
//   - "cell-background" to match the cell background color
//
// The default value is black text on a golden yellow background.
// The foreground and background color for the currently selected search match.
// This is the focused match that will be jumped to when using next/previous
// search navigation.
//
// Valid values:
//
//   - Hex (`#RRGGBB` or `RRGGBB`)
//   - Named X11 color
//   - "cell-foreground" to match the cell foreground color
//   - "cell-background" to match the cell background color
//
// The default value is black text on a soft peach background.
// The command to run, usually a shell. If this is not an absolute path, it'll
// be looked up in the `PATH`. If this is not set, a default will be looked up
// from your system. The rules for the default lookup are:
//
//   * `SHELL` environment variable
//
//   * `passwd` entry (user information)
//
// This can contain additional arguments to run the command with. If additional
// arguments are provided, the command will be executed using `/bin/sh -c`
// to offload shell argument expansion.
//
// To avoid shell expansion altogether, prefix the command with `direct:`, e.g.
// `direct:nvim foo`. This will avoid the roundtrip to `/bin/sh` but will also
// not support any shell parsing such as arguments with spaces, filepaths with
// `~`, globs, etc. (Available since: 1.2.0)
//
// You can also explicitly prefix the command with `shell:` to always wrap the
// command in a shell. This can be used to ensure our heuristics to choose the
// right mode are not used in case they are wrong. (Available since: 1.2.0)
//
// This command will be used for all new terminal surfaces, i.e. new windows,
// tabs, etc. If you want to run a command only for the first terminal surface
// created when Witty starts, use the `initial-command` configuration.
//
// Witty supports the common `-e` flag for executing a command with
// arguments. For example, `witty -e fish --with --custom --args`.
// This flag sets the `initial-command` configuration, see that for more
// information.
// This is the same as "command", but only applies to the first terminal
// surface created when Witty starts. Subsequent terminal surfaces will use
// the `command` configuration.
//
// After the first terminal surface is created (or closed), there is no
// way to run this initial command again automatically. As such, setting
// this at runtime works but will only affect the next terminal surface
// if it is the first one ever created.
//
// If you're using the `witty` CLI there is also a shortcut to set this
// with arguments directly: you can use the `-e` flag. For example: `witty -e
// fish --with --custom --args`. The `-e` flag automatically forces some
// other behaviors as well:
//
//   * Disables shell expansion since the input is expected to already
//     be shell-expanded by the upstream (e.g. the shell used to type in
//     the `witty -e` command).
//
//   * `gtk-single-instance=false` - This ensures that a new instance is
//     launched and the CLI args are respected.
//
//   * `quit-after-last-window-closed=true` - This ensures that the Witty
//     process will exit when the command exits. Additionally, the
//     `quit-after-last-window-closed-delay` is unset.
//
//   * `shell-integration=detect` (if not `none`) - This prevents forcibly
//     injecting any configured shell integration into the command's
//     environment. With `-e` its highly unlikely that you're executing a
//     shell and forced shell integration is likely to cause problems
//     (e.g. by wrapping your command in a shell, setting env vars, etc.).
//     This is a safety measure to prevent unexpected behavior. If you want
//     shell integration with a `-e`-executed command, you must either
//     name your binary appropriately or source the shell integration script
//     manually.
// Controls when command finished notifications are sent. There are
// three options:
//
// * `never` - Never send notifications (the default).
// * `unfocused` - Only send notifications if the surface that the command is
//   running in is not focused.
// * `always` - Always send notifications.
//
// Command finished notifications requires that either shell integration is
// enabled, or that your shell sends OSC 133 escape sequences to mark the start
// and end of commands.
//
// On GTK, there is a context menu item that will enable command finished
// notifications for a single command, overriding the `never` and `unfocused`
// options.
//
// GTK only.
//
// Available since 1.3.0.
// If command finished notifications are enabled, this controls how the user is
// notified.
//
// Available options:
//
// * `bell` - enabled by default
// * `notify` - disabled by default
//
// Options can be combined by listing them as a comma separated list. Options
// can be negated by prefixing them with `no-`. For example `no-bell,notify`.
//
// GTK only.
//
// Available since 1.3.0.
// If command finished notifications are enabled, this controls how long a
// command must have been running before a notification will be sent. The
// default is five seconds.
//
// The duration is specified as a series of numbers followed by time units.
// Whitespace is allowed between numbers and units. Each number and unit will
// be added together to form the total duration.
//
// The allowed time units are as follows:
//
//   * `y` - 365 SI days, or 8760 hours, or 31536000 seconds. No adjustments
//     are made for leap years or leap seconds.
//   * `d` - one SI day, or 86400 seconds.
//   * `h` - one hour, or 3600 seconds.
//   * `m` - one minute, or 60 seconds.
//   * `s` - one second.
//   * `ms` - one millisecond, or 0.001 second.
//   * `us` or `µs` - one microsecond, or 0.000001 second.
//   * `ns` - one nanosecond, or 0.000000001 second.
//
// Examples:
//   * `1h30m`
//   * `45s`
//
// Units can be repeated and will be added together. This means that
// `1h1h` is equivalent to `2h`. This is confusing and should be avoided.
// A future update may disallow this.
//
// The maximum value is `584y 49w 23h 34m 33s 709ms 551µs 615ns`. Any
// value larger than this will be clamped to the maximum value.
//
// GTK only.
//
// Available since 1.3.0
// Extra environment variables to pass to commands launched in a terminal
// surface. The format is `env=KEY=VALUE`.
//
// `env = foo=bar`
// `env = bar=baz`
//
// Setting `env` to an empty string will reset the entire map to default
// (empty).
//
// `env =`
//
// Setting a key to an empty string will remove that particular key and
// corresponding value from the map.
//
// `env = foo=bar`
// `env = foo=`
//
// will result in `foo` not being passed to the launched commands.
//
// Setting a key multiple times will overwrite previous entries.
//
// `env = foo=bar`
// `env = foo=baz`
//
// will result in `foo=baz` being passed to the launched commands.
//
// These environment variables will override any existing environment
// variables set by Witty. For example, if you set `GHOSTTY_RESOURCES_DIR`
// then the value you set here will override the value Witty typically
// automatically injects.
//
// These environment variables _will not_ be passed to commands run by Witty
// for other purposes, like `open` or `xdg-open` used to open URLs in your
// browser.
//
// Available since: 1.2.0
// Data to send as input to the command on startup.
//
// The configured `command` will be launched using the typical rules,
// then the data specified as this input will be written to the pty
// before any other input can be provided.
//
// The bytes are sent as-is with no additional encoding. Therefore, be
// cautious about input that can contain control characters, because this
// can be used to execute programs in a shell.
//
// The format of this value is:
//
//   * `raw:<string>` - Send raw text as-is. This uses Zig string literal
//     syntax so you can specify control characters and other standard
//     escapes.
//
//   * `path:<path>` - Read a filepath and send the contents. The path
//     must be to a file with finite length. e.g. don't use a device
//     such as `/dev/stdin` or `/dev/urandom` as these will block
//     terminal startup indefinitely. Files are limited to 10MB
//     in size to prevent excessive memory usage. If you have files
//     larger than this you should write a script to read the file
//     and send it to the terminal.
//
// If no valid prefix is found, it is assumed to be a `raw:` input.
// This is an ergonomic choice to allow you to simply write
// `input = "Hello, world!"` (a common case) without needing to prefix
// every value with `raw:`.
//
// This can be repeated multiple times to send more data. The data
// is concatenated directly with no separator characters in between
// (e.g. no newline).
//
// If any of the input sources do not exist, then none of the input
// will be sent. Input sources are not verified until the terminal
// is starting, so missing paths will not show up in config validation.
//
// Changing this configuration at runtime will only affect new
// terminals.
//
// Available since: 1.2.0
// If true, keep the terminal open after the command exits. Normally, the
// terminal window closes when the running command (such as a shell) exits.
// With this true, the terminal window will stay open until any keypress is
// received.
//
// This is primarily useful for scripts or debugging.
// The number of milliseconds of runtime below which we consider a process exit
// to be abnormal. This is used to show an error message when the process exits
// too quickly.
//
// On Linux, this must be paired with a non-zero exit code. On macOS, we allow
// any exit code because of the way shell processes are launched via the login
// command.
// The size of the scrollback buffer in bytes. This also includes the active
// screen. No matter what this is set to, enough memory will always be
// allocated for the visible screen and anything leftover is the limit for
// the scrollback.
//
// When this limit is reached, the oldest lines are removed from the
// scrollback.
//
// Scrollback currently exists completely in memory. This means that the
// larger this value, the larger potential memory usage. Scrollback is
// allocated lazily up to this limit, so if you set this to a very large
// value, it will not immediately consume a lot of memory.
//
// This size is per terminal surface, not for the entire application.
//
// It is not currently possible to set an unlimited scrollback buffer.
// This is a future planned feature.
//
// This can be changed at runtime but will only affect new terminal surfaces.
// Control when the scrollbar is shown to scroll the scrollback buffer.
//
// The default value is `system`.
//
// Valid values:
//
//   * `system` - Respect the system settings for when to show scrollbars.
//     For example, on macOS, this will respect the "Scrollbar behavior"
//     system setting which by default usually only shows scrollbars while
//     actively scrolling or hovering the gutter.
//
//   * `never` - Never show a scrollbar. You can still scroll using the mouse,
//     keybind actions, etc. but you will not have a visual UI widget showing
//     a scrollbar.
//
// This only applies to macOS currently. GTK doesn't yet support scrollbars.
// Match a regular expression against the terminal text and associate clicking
// it with an action. This can be used to match URLs, file paths, etc. Actions
// can be opening using the system opener (e.g. `open` or `xdg-open`) or
// executing any arbitrary binding action.
//
// Links that are configured earlier take precedence over links that are
// configured later.
//
// A default link that matches a URL and opens it in the system opener always
// exists. This can be disabled using `link-url`.
//
// TODO: This can't currently be set!
// Enable URL matching. URLs are matched on hover with control (Linux) or
// command (macOS) pressed and open using the default system application for
// the linked URL.
//
// The URL matcher is always lowest priority of any configured links (see
// `link`). If you want to customize URL matching, use `link` and disable this.
// Show link previews for a matched URL.
//
// When true, link previews are shown for all matched URLs. When false, link
// previews are never shown. When set to "osc8", link previews are only shown
// for hyperlinks created with the OSC 8 sequence (in this case, the link text
// can differ from the link destination).
//
// Available since: 1.2.0
// Whether to start the window in a maximized state. This setting applies
// to new windows and does not apply to tabs, splits, etc. However, this setting
// will apply to all new windows, not just the first one.
//
// Available since: 1.1.0
// Start new windows in fullscreen. This setting applies to new windows and
// does not apply to tabs, splits, etc. However, this setting will apply to all
// new windows, not just the first one.
//
// On macOS, this setting does not work if window-decoration is set to
// "none", because native fullscreen on macOS requires window decorations
// to be set.
// The title Witty will use for the window. This will force the title of the
// window to be this title at all times and Witty will ignore any set title
// escape sequences programs (such as Neovim) may send.
//
// If you want a blank title, set this to one or more spaces by quoting
// the value. For example, `title = " "`. This effectively hides the title.
// This is necessary because setting a blank value resets the title to the
// default value of the running program.
//
// This configuration can be reloaded at runtime. If it is set, the title
// will update for all windows. If it is unset, the next title change escape
// sequence will be honored but previous changes will not retroactively
// be set. This latter case may require you to restart programs such as Neovim
// to get the new title.
// The setting that will change the application class value.
//
// This controls the class field of the `WM_CLASS` X11 property (when running
// under X11), the Wayland application ID (when running under Wayland), and the
// bus name that Witty uses to connect to DBus.
//
// Note that changing this value between invocations will create new, separate
// instances, of Witty when running with `gtk-single-instance=true`. See that
// option for more details.
//
// Changing this value may break launching Witty from `.desktop` files, via
// DBus activation, or systemd user services as the system is expecting Witty
// to connect to DBus using the default `class` when it is launched.
//
// The class name must follow the requirements defined [in the GTK
// documentation](https://docs.gtk.org/gio/type_func.Application.id_is_valid.html).
//
// The default is `com.alexander.witty`.
//
// This only affects GTK builds.
// This controls the instance name field of the `WM_CLASS` X11 property when
// running under X11. It has no effect otherwise.
//
// The default is `witty`.
//
// This only affects GTK builds.
// The directory to change to after starting the command.
//
// This setting is secondary to the `window-inherit-working-directory`
// setting. If a previous Witty terminal exists in the same process,
// `window-inherit-working-directory` will take precedence. Otherwise, this
// setting will be used. Typically, this setting is used only for the first
// window.
//
// The default is `inherit` except in special scenarios listed next. On macOS,
// if Witty can detect it is launched from launchd (double-clicked) or
// `open`, then it defaults to `home`. On Linux with GTK, if Witty can detect
// it was launched from a desktop launcher, then it defaults to `home`.
//
// The value of this must be an absolute value or one of the special values
// below:
//
//   * `home` - The home directory of the executing user.
//
//   * `inherit` - The working directory of the launching process.
// Key bindings. The format is `trigger=action`. Duplicate triggers will
// overwrite previously set values. The list of actions is available in
// the documentation or using the `witty +list-actions` command.
//
// Trigger: `+`-separated list of keys and modifiers. Example: `ctrl+a`,
// `ctrl+shift+b`, `up`.
//
// If the key is a single Unicode codepoint, the trigger will match
// any presses that produce that codepoint. These are impacted by
// keyboard layouts. For example, `a` will match the `a` key on a
// QWERTY keyboard, but will match the `q` key on a AZERTY keyboard
// (assuming US physical layout).
//
// For Unicode codepoints, matching is done by comparing the set of
// modifiers with the unmodified codepoint. The unmodified codepoint is
// sometimes called an "unshifted character" in other software, but all
// modifiers are considered, not only shift. For example, `ctrl+a` will match
// `a` but not `ctrl+shift+a` (which is `A` on a US keyboard).
//
// Further, codepoint matching is case-insensitive and the unmodified
// codepoint is always case folded for comparison. As a result,
// `ctrl+A` configured will match when `ctrl+a` is pressed. Note that
// this means some key combinations are impossible depending on keyboard
// layout. For example, `ctrl+_` is impossible on a US keyboard because
// `_` is `shift+-` and `ctrl+shift+-` is not equal to `ctrl+_` (because
// the modifiers don't match!). More details on impossible key combinations
// can be found at this excellent source written by Qt developers:
// https://doc.qt.io/qt-6/qkeysequence.html#keyboard-layout-issues
//
// Physical key codes can be specified by using any of the key codes
// as specified by the [W3C specification](https://www.w3.org/TR/uievents-code/).
// For example, `KeyA` will match the physical `a` key on a US standard
// keyboard regardless of the keyboard layout. These are case-sensitive.
//
// For aesthetic reasons, the w3c codes also support snake case. For
// example, `key_a` is equivalent to `KeyA`. The only exceptions are
// function keys, e.g. `F1` is `f1` (no underscore). This is a consequence
// of our internal code using snake case but is purposely supported
// and tested so it is safe to use. It allows an all-lowercase binding
// which I find more aesthetically pleasing.
//
// Function keys such as `insert`, `up`, `f5`, etc. are also specified
// using the keys as specified by the previously linked W3C specification.
//
// Physical keys always match with a higher priority than Unicode codepoints,
// so if you specify both `a` and `KeyA`, the physical key will always be used
// regardless of what order they are configured.
//
// The special key `catch_all` can be used to match any key that is not
// otherwise bound. This can be combined with modifiers, for example
// `ctrl+catch_all` will match any key pressed with `ctrl` that is not
// otherwise bound. When looking up a binding, Witty first tries to match
// `catch_all` with modifiers. If no match is found and the event has
// modifiers, it falls back to `catch_all` without modifiers.
//
// Valid modifiers are `shift`, `ctrl` (alias: `control`), `alt` (alias: `opt`,
// `option`), and `super` (alias: `cmd`, `command`). You may use the modifier
// or the alias. When debugging keybinds, the non-aliased modifier will always
// be used in output.
//
// Note: The fn or "globe" key on keyboards are not supported as a
// modifier. This is a limitation of the operating systems and GUI toolkits
// that Witty uses.
//
// Some additional notes for triggers:
//
//   * modifiers cannot repeat, `ctrl+ctrl+a` is invalid.
//
//   * modifiers and keys can be in any order, `shift+a+ctrl` is *weird*,
//     but valid.
//
//   * only a single key input is allowed, `ctrl+a+b` is invalid.
//
// You may also specify multiple triggers separated by `>` to require a
// sequence of triggers to activate the action. For example,
// `ctrl+a>n=new_window` will only trigger the `new_window` action if the
// user presses `ctrl+a` followed separately by `n`. In other software, this
// is sometimes called a leader key, a key chord, a key table, etc. There
// is no hardcoded limit on the number of parts in a sequence.
//
// Warning: If you define a sequence as a CLI argument to `witty`,
// you probably have to quote the keybind since `>` is a special character
// in most shells. Example: witty --keybind='ctrl+a>n=new_window'
//
// A trigger sequence has some special handling:
//
//   * Witty will wait an indefinite amount of time for the next key in
//     the sequence. There is no way to specify a timeout. The only way to
//     force the output of a prefix key is to assign another keybind to
//     specifically output that key (e.g. `ctrl+a>ctrl+a=text:foo`) or
//     press an unbound key which will send both keys to the program.
//
//   * If an unbound key is pressed during a sequence and a `catch_all`
//     binding exists that would `ignore` the input, the entire sequence
//     is dropped and nothing happens. Otherwise, the entire sequence is
//     encoded and sent to the running program as if no keybind existed.
//
//   * If a prefix in a sequence is previously bound, the sequence will
//     override the previous binding. For example, if `ctrl+a` is bound to
//     `new_window` and `ctrl+a>n` is bound to `new_tab`, pressing `ctrl+a`
//     will do nothing.
//
//   * Adding to the above, if a previously bound sequence prefix is
//     used in a new, non-sequence binding, the entire previously bound
//     sequence will be unbound. For example, if you bind `ctrl+a>n` and
//     `ctrl+a>t`, and then bind `ctrl+a` directly, both `ctrl+a>n` and
//     `ctrl+a>t` will become unbound.
//
//   * Trigger sequences are not allowed for `global:` or `all:`-prefixed
//     triggers. This is a limitation we could remove in the future.
//
// Action is the action to take when the trigger is satisfied. It takes the
// format `action` or `action:param`. The latter form is only valid if the
// action requires a parameter.
//
//   * `ignore` - Do nothing, ignore the key input. This can be used to
//     black hole certain inputs to have no effect.
//
//   * `unbind` - Remove the binding. This makes it so the previous action
//     is removed, and the key will be sent through to the child command
//     if it is printable. Unbind will remove any matching trigger,
//     including `physical:`-prefixed triggers without specifying the
//     prefix.
//
//   * `csi:text` - Send a CSI sequence. e.g. `csi:A` sends "cursor up".
//
//   * `esc:text` - Send an escape sequence. e.g. `esc:d` deletes to the
//     end of the word to the right.
//
//   * `text:text` - Send a string. Uses Zig string literal syntax.
//     e.g. `text:\x15` sends Ctrl-U.
//
//   * All other actions can be found in the documentation or by using the
//     `witty +list-actions` command.
//
// Some notes for the action:
//
//   * The parameter is taken as-is after the `:`. Double quotes or
//     other mechanisms are included and NOT parsed. If you want to
//     send a string value that includes spaces, wrap the entire
//     trigger/action in double quotes. Example: `--keybind="up=csi:A B"`
//
// There are some additional special values that can be specified for
// keybind:
//
//   * `keybind=clear` will clear all set keybindings. Warning: this
//     removes ALL keybindings up to this point, including the default
//     keybindings.
//
// The keybind trigger can be prefixed with some special values to change
// the behavior of the keybind. These are:
//
//  * `all:`
//
//    Make the keybind apply to all terminal surfaces. By default,
//    keybinds only apply to the focused terminal surface. If this is true,
//    then the keybind will be sent to all terminal surfaces. This only
//    applies to actions that are surface-specific. For actions that
//    are already global (e.g. `quit`), this prefix has no effect.
//
//    Available since: 1.0.0
//
//  * `global:`
//
//    Make the keybind global. By default, keybinds only work within Witty
//    and under the right conditions (application focused, sometimes terminal
//    focused, etc.). If you want a keybind to work globally across your system
//    (e.g. even when Witty is not focused), specify this prefix.
//    This prefix implies `all:`.
//
//    Note: this does not work in all environments; see the additional notes
//    below for more information.
//
//    Available since: 1.0.0 on macOS, 1.2.0 on GTK
//
//  * `unconsumed:`
//
//    Do not consume the input. By default, a keybind will consume the input,
//    meaning that the associated encoding (if any) will not be sent to the
//    running program in the terminal. If you wish to send the encoded value
//    to the program, specify the `unconsumed:` prefix before the entire
//    keybind. For example: `unconsumed:ctrl+a=reload_config`. `global:` and
//    `all:`-prefixed keybinds will always consume the input regardless of
//    this setting. Since they are not associated with a specific terminal
//    surface, they're never encoded.
//
//    Available since: 1.0.0
//
//  * `performable:`
//
//    Only consume the input if the action is able to be performed.
//    For example, the `copy_to_clipboard` action will only consume the input
//    if there is a selection to copy. If there is no selection, Witty
//    behaves as if the keybind was not set. This has no effect with `global:`
//    or `all:`-prefixed keybinds. For key sequences, this will reset the
//    sequence if the action is not performable (acting identically to not
//    having a keybind set at all).
//
//    Performable keybinds will not appear as menu shortcuts in the
//    application menu. This is because the menu shortcuts force the
//    action to be performed regardless of the state of the terminal.
//    Performable keybinds will still work, they just won't appear as
//    a shortcut label in the menu.
//
//    Available since: 1.1.0
//
// Keybind triggers are not unique per prefix combination. For example,
// `ctrl+a` and `global:ctrl+a` are not two separate keybinds. The keybind
// set later will overwrite the keybind set earlier. In this case, the
// `global:` keybind will be used.
//
// Multiple prefixes can be specified. For example,
// `global:unconsumed:ctrl+a=reload_config` will make the keybind global
// and not consume the input to reload the config.
//
// Note: `global:` is only supported on macOS and certain Linux platforms.
//
// On macOS, this feature requires accessibility permissions to be granted
// to Witty. When a `global:` keybind is specified and Witty is launched
// or reloaded, Witty will attempt to request these permissions.
// If the permissions are not granted, the keybind will not work. On macOS,
// you can find these permissions in System Preferences -> Privacy & Security
// -> Accessibility.
//
// On Linux, you need a desktop environment that implements the
// [Global Shortcuts](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html)
// protocol as a part of its XDG desktop protocol implementation.
// Desktop environments that are known to support (or not support)
// global shortcuts include:
//
//  - Users using KDE Plasma (since [5.27](https://kde.org/announcements/plasma/5/5.27.0/#wayland))
//    and GNOME (since [48](https://release.gnome.org/48/#and-thats-not-all)) should be able
//    to use global shortcuts with little to no configuration.
//
//  - Some manual configuration is required on Hyprland. Consult the steps
//    outlined on the [Hyprland Wiki](https://wiki.hyprland.org/Configuring/Binds/#dbus-global-shortcuts)
//    to set up global shortcuts correctly.
//    (Important: [`xdg-desktop-portal-hyprland`](https://wiki.hyprland.org/Hypr-Ecosystem/xdg-desktop-portal-hyprland/)
//    must also be installed!)
//
//  - Notably, global shortcuts have not been implemented on wlroots-based
//    compositors like Sway (see [upstream issue](https://github.com/emersion/xdg-desktop-portal-wlr/issues/240)).
//
// ## Chained Actions
//
// A keybind can have multiple actions by using the `chain` keyword for
// subsequent actions. When a keybind is activated, all chained actions are
// executed in order. The syntax is:
//
// ```ini
// keybind = ctrl+a=new_window
// keybind = chain=goto_split:left
// ```
//
// This binds `ctrl+a` to first open a new window, then move focus to the
// left split. Each `chain` entry appends an action to the most recently
// defined keybind. You can chain as many actions as you want:
//
// ```ini
// keybind = ctrl+a=new_window
// keybind = chain=goto_split:left
// keybind = chain=toggle_fullscreen
// ```
//
// Chained actions cannot have prefixes like `global:` or `unconsumed:`.
// The flags from the original keybind apply to the entire chain.
//
// Chained actions work with key sequences as well. For example:
//
// ```ini
// keybind = ctrl+a>n=new_window
// keybind = chain=goto_split:left
// ````
//
// Chains with key sequences apply to the most recent binding in the
// sequence.
//
// Chained keybinds are available since Witty 1.3.0.
//
// ## Key Tables
//
// You may also create a named set of keybindings known as a "key table."
// A key table must be explicitly activated for the bindings to become
// available. This can be used to implement features such as a
// "copy mode", "vim mode", etc. Generically, this can implement modal
// keyboard input.
//
// Key tables are defined using the syntax `<table>/<binding>`. The
// `<binding>` value is everything documented above for keybinds. The
// `<table>` value is the name of the key table. Table names can contain
// anything except `/`, `=`, `+`, and `>`. The characters `+` and `>` are
// reserved for keybind syntax (modifier combinations and key sequences).
// For example `foo/ctrl+a=new_window` defines a binding within a table
// named `foo`.
//
// Tables are activated and deactivated using the binding actions
// `activate_key_table:<name>` and `deactivate_key_table`. Other table
// related binding actions also exist; see the documentation for a full list.
// These are the primary way to interact with key tables.
//
// Binding lookup proceeds from the innermost table outward, so keybinds in
// the default table remain available unless explicitly unbound in an inner
// table.
//
// A key table has some special syntax and handling:
//
//   * `<name>/` (with no binding) defines and clears a table, resetting all
//     of its keybinds and settings.
//
//   * You cannot activate a table that is already the innermost table; such
//     attempts are ignored. However, the same table can appear multiple times
//     in the stack as long as it is not innermost (e.g., `A -> B -> A -> B`
//     is valid, but `A -> B -> B` is not).
//
//   * A table can be activated in one-shot mode using
//     `activate_key_table_once:<name>`. A one-shot table is automatically
//     deactivated when any non-catch-all binding is invoked.
//
//   * Key sequences work within tables: `foo/ctrl+a>ctrl+b=new_window`.
//     If an invalid key is pressed, the sequence ends but the table remains
//     active.
//
//   * Prefixes like `global:` work within tables:
//     `foo/global:ctrl+a=new_window`.
//
// Key tables are available since Witty 1.3.0.
// Remap modifier keys within Witty. This allows you to swap or reassign
// modifier keys at the application level without affecting system-wide
// settings.
//
// The format is `from=to` where both `from` and `to` are modifier key names.
// You can use generic names like `ctrl`, `alt`, `shift`, `super` (macOS:
// `cmd`/`command`) or sided names like `left_ctrl`, `right_alt`, etc.
//
// This will NOT change keyboard layout or key encodings outside of Witty.
// For example, on macOS, `option+a` may still produce `å` even if `option` is
// remapped to `ctrl`. Desktop environments usually handle key layout long
// before Witty receives the key events.
//
// Example:
//
//     key-remap = ctrl=super
//     key-remap = left_control=right_alt
//
// Important notes:
//
// * This is a one-way remap. If you remap `ctrl=super`, then the physical
//   Ctrl key acts as Super, but the Super key remains Super.
//
// * Remaps are not transitive. If you remap `ctrl=super` and `alt=ctrl`,
//   pressing Alt will produce Ctrl, NOT Super.
//
// * This affects both keybind matching and terminal input encoding.
//   This does NOT impact keyboard layout or how keys are interpreted
//   prior to Witty receiving them. For example, `option+a` on macOS
//   may still produce `å` even if `option` is remapped to `ctrl`.
//
// * Generic modifiers (e.g. `ctrl`) match both left and right physical keys.
//   Use sided names (e.g. `left_ctrl`) to remap only one side.
//
// There are other edge case scenarios that may not behave as expected
// but are working as intended the way this feature is designed:
//
// * On macOS, bindings in the main menu will trigger before any remapping
//   is done. This is because macOS itself handles menu activation and
//   this happens before Witty receives the key event. To workaround
//   this, you should unbind the menu items and rebind them using your
//   desired modifier.
//
// This configuration can be repeated to specify multiple remaps.
// Horizontal window padding. This applies padding between the terminal cells
// and the left and right window borders. The value is in points, meaning that
// it will be scaled appropriately for screen DPI.
//
// If this value is set too large, the screen will render nothing, because the
// grid will be completely squished by the padding. It is up to you as the user
// to pick a reasonable value. If you pick an unreasonable value, a warning
// will appear in the logs.
//
// Changing this configuration at runtime will only affect new terminals, i.e.
// new windows, tabs, etc.
//
// To set a different left and right padding, specify two numerical values
// separated by a comma. For example, `window-padding-x = 2,4` will set the
// left padding to 2 and the right padding to 4. If you want to set both
// paddings to the same value, you can use a single value. For example,
// `window-padding-x = 2` will set both paddings to 2.
// Vertical window padding. This applies padding between the terminal cells and
// the top and bottom window borders. The value is in points, meaning that it
// will be scaled appropriately for screen DPI.
//
// If this value is set too large, the screen will render nothing, because the
// grid will be completely squished by the padding. It is up to you as the user
// to pick a reasonable value. If you pick an unreasonable value, a warning
// will appear in the logs.
//
// Changing this configuration at runtime will only affect new terminals,
// i.e. new windows, tabs, etc.
//
// To set a different top and bottom padding, specify two numerical values
// separated by a comma. For example, `window-padding-y = 2,4` will set the
// top padding to 2 and the bottom padding to 4. If you want to set both
// paddings to the same value, you can use a single value. For example,
// `window-padding-y = 2` will set both paddings to 2.
// Distribute the leftover pixels after fitting whole cells into the viewport.
// Explicit padding is applied first when calculating the number of cells.
// `false` keeps the configured padding. `true` balances the borders and caps
// the top padding, moving excess to the bottom. `equal` balances every edge
// without a cap on the top padding.
// The color of the padding area of the window. Valid values are:
//
// * `background` - The background color specified in `background`.
// * `extend` - Extend the background color of the nearest grid cell.
// * `extend-always` - Same as "extend" but always extends without applying
//   any of the heuristics that disable extending noted below.
//
// The "extend" value will be disabled in certain scenarios. On primary
// screen applications (e.g. not something like Neovim), the color will not
// be extended vertically if any of the following are true:
//
// * The nearest row has any cells that have the default background color.
//   The thinking is that in this case, the default background color looks
//   fine as a padding color.
// * The nearest row is a prompt row (requires shell integration). The
//   thinking here is that prompts often contain powerline glyphs that
//   do not look good extended.
// * The nearest row contains a perfect fit powerline character. These
//   don't look good extended.
// Synchronize rendering with the screen refresh rate. If true, this will
// minimize tearing and align redraws with the screen but may cause input
// latency. If false, this will maximize redraw frequency but may cause tearing,
// and under heavy load may use more CPU and power.
//
// This defaults to true because out-of-sync rendering on macOS can
// cause kernel panics (macOS 14.4+) and performance issues for external
// displays over some hardware such as DisplayLink. If you want to minimize
// input latency, set this to false with the known aforementioned risks.
//
// Changing this value at runtime will only affect new terminals.
//
// This setting is only supported currently on macOS.
// If true, new windows will inherit the working directory of the
// previously focused window. If no window was previously focused, the default
// working directory will be used (the `working-directory` option).
// If true, new tabs will inherit the working directory of the
// previously focused tab. If no tab was previously focused, the default
// working directory will be used (the `working-directory` option).
// If true, new split panes will inherit the working directory of the
// previously focused split. If no split was previously focused, the default
// working directory will be used (the `working-directory` option).
// If true, new windows and tabs will inherit the font size of the previously
// focused window. If no window was previously focused, the default font size
// will be used. If this is false, the default font size specified in the
// configuration `font-size` will be used.
// Configure a preference for window decorations. This setting specifies
// a _preference_; the actual OS, desktop environment, window manager, etc.
// may override this preference. Witty will do its best to respect this
// preference but it may not always be possible.
//
// Valid values:
//
//  * `none`
//
//    All window decorations will be disabled. Titlebar, borders, etc. will
//    not be shown. On macOS, this will also disable tabs (enforced by the
//    system).
//
//  * `auto`
//
//    Automatically decide to use either client-side or server-side
//    decorations based on the detected preferences of the current OS and
//    desktop environment. This option usually makes Witty look the most
//    "native" for your desktop.
//
//  * `client`
//
//    Prefer client-side decorations.
//
//    Available since: 1.1.0
//
//  * `server`
//
//    Prefer server-side decorations. This is only relevant on Linux with GTK,
//    either on X11, or Wayland on a compositor that supports the
//    `org_kde_kwin_server_decoration` protocol (e.g. KDE Plasma, but almost
//    any non-GNOME desktop supports this protocol).
//
//    If `server` is set but the environment doesn't support server-side
//    decorations, client-side decorations will be used instead.
//
//    Available since: 1.1.0
//
// The default value is `auto`.
//
// For the sake of backwards compatibility and convenience, this setting also
// accepts boolean true and false values. If set to `true`, this is equivalent
// to `auto`. If set to `false`, this is equivalent to `none`.
// This is convenient for users who live primarily on systems that don't
// differentiate between client and server-side decorations (e.g. macOS and
// Windows).
//
// The "toggle_window_decorations" keybind action can be used to create
// a keybinding to toggle this setting at runtime.
//
// macOS: To hide the titlebar without removing the native window borders
//        or rounded corners, use `macos-titlebar-style = hidden` instead.
// The font that will be used for the application's window and tab titles.
//
// If this setting is left unset, the system default font will be used.
//
// Note: any font available on the system may be used, this font is not
// required to be a fixed-width font.
//
// Available since: 1.0.0 on macOS, 1.1.0 on GTK
// The text that will be displayed in the subtitle of the window. Valid values:
//
//   * `false` - Disable the subtitle.
//   * `working-directory` - Set the subtitle to the working directory of the
//      surface.
//
// This feature is only supported on GTK.
//
// Available since: 1.1.0
// The theme to use for the windows. Valid values:
//
//   * `auto` - Determine the theme based on the configured terminal
//      background color. This has no effect if the "theme" configuration
//      has separate light and dark themes. In that case, the behavior
//      of "auto" is equivalent to "system".
//   * `system` - Use the system theme.
//   * `light` - Use the light theme regardless of system theme.
//   * `dark` - Use the dark theme regardless of system theme.
//   * `witty` - Use the background and foreground colors specified in the
//     Witty configuration. This is only supported on Linux builds.
//
// On macOS, if `macos-titlebar-style` is `tabs` or `transparent`, the window theme will be
// automatically set based on the luminosity of the terminal background color.
// This only applies to terminal windows. This setting will still apply to
// non-terminal windows within Witty.
//
// This is currently only supported on macOS and Linux.
// The color space to use when interpreting terminal colors. "Terminal colors"
// refers to colors specified in your configuration and colors produced by
// direct-color SGR sequences.
//
// Valid values:
//
//   * `srgb` - Interpret colors in the sRGB color space. This is the default.
//   * `display-p3` - Interpret colors in the Display P3 color space.
//
// This setting is currently only supported on macOS.
// The initial window size. This size is in terminal grid cells by default.
// Both values must be set to take effect. If only one value is set, it is
// ignored.
//
// We don't currently support specifying a size in pixels but a future change
// can enable that. If this isn't specified, the app runtime will determine
// some default size.
//
// Note that the window manager may put limits on the size or override the
// size. For example, a tiling window manager may force the window to be a
// certain size to fit within the grid. There is nothing Witty will do about
// this, but it will make an effort.
//
// Sizes larger than the screen size will be clamped to the screen size.
// This can be used to create a maximized-by-default window size.
//
// This will not affect new tabs, splits, or other nested terminal elements.
// This only affects the initial window size of any new window. Changing this
// value will not affect the size of the window after it has been created. This
// is only used for the initial size.
//
// BUG: On Linux with GTK, the calculated window size will not properly take
// into account window decorations. As a result, the grid dimensions will not
// exactly match this configuration. If window decorations are disabled (see
// `window-decoration`), then this will work as expected.
//
// Windows smaller than 10 wide by 4 high are not allowed.
// The starting window position. This position is in pixels and is relative
// to the top-left corner of the primary monitor. Both values must be set to take
// effect. If only one value is set, it is ignored.
//
// Note that the window manager may put limits on the position or override
// the position. For example, a tiling window manager may force the window
// to be a certain position to fit within the grid. There is nothing Witty
// will do about this, but it will make an effort.
//
// Also note that negative values are also up to the operating system and
// window manager. Some window managers may not allow windows to be placed
// off-screen.
//
// Invalid positions are runtime-specific, but generally the positions are
// clamped to the nearest valid position.
//
// On macOS, the window position is relative to the top-left corner of
// the visible screen area. This means that if the menu bar is visible, the
// window will be placed below the menu bar.
//
// Note: this is only supported on macOS. The GTK runtime does not support
// setting the window position, as windows are only allowed position
// themselves in X11 and not Wayland.
// Whether to enable saving and restoring window state. Window state includes
// their position, size, tabs, splits, etc. Some window state requires shell
// integration, such as preserving working directories. See `shell-integration`
// for more information.
//
// There are three valid values for this configuration:
//
//   * `default` will use the default system behavior. On macOS, this
//     will only save state if the application is forcibly terminated
//     or if it is configured systemwide via Settings.app.
//
//   * `never` will never save window state.
//
//   * `always` will always save window state whenever Witty is exited.
//
// If you change this value to `never` while Witty is not running, the next
// Witty launch will NOT restore the window state.
//
// If you change this value to `default` while Witty is not running and the
// previous exit saved state, the next Witty launch will still restore the
// window state. This is because Witty cannot know if the previous exit was
// due to a forced save or not (macOS doesn't provide this information).
//
// If you change this value so that window state is saved while Witty is not
// running, the previous window state will not be restored because Witty only
// saves state on exit if this is enabled.
//
// The default value is `default`.
//
// This is currently only supported on macOS. This has no effect on Linux.
// Resize the window in discrete increments of the focused surface's cell size.
// If this is disabled, surfaces are resized in pixel increments. Currently
// only supported on macOS.
// The position where new tabs are created. Valid values:
//
//   * `current` - Insert the new tab after the currently focused tab,
//     or at the end if there are no focused tabs.
//
//   * `end` - Insert the new tab at the end of the tab list.
// Whether to show the tab bar.
//
// Valid values:
//
//  - `always`
//
//    Always display the tab bar, even when there's only one tab.
//
//    Available since: 1.2.0
//
//  - `auto` *(default)*
//
//    Automatically show and hide the tab bar. The tab bar is only
//    shown when there are two or more tabs present.
//
//  - `never`
//
//    Never show the tab bar. Tabs are only accessible via the tab
//    overview or by keybind actions.
//
// Currently only supported on Linux (GTK).
// Background color for the window titlebar. This only takes effect if
// window-theme is set to witty. Currently only supported in the GTK app
// runtime.
//
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// Foreground color for the window titlebar. This only takes effect if
// window-theme is set to witty. Currently only supported in the GTK app
// runtime.
//
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// This controls when resize overlays are shown. Resize overlays are a
// transient popup that shows the size of the terminal while the surfaces are
// being resized. The possible options are:
//
//   * `always` - Always show resize overlays.
//   * `never` - Never show resize overlays.
//   * `after-first` - The resize overlay will not appear when the surface
//                     is first created, but will show up if the surface is
//                     subsequently resized.
//
// The default is `after-first`.
// If resize overlays are enabled, this controls the position of the overlay.
// The possible options are:
//
//   * `center`
//   * `top-left`
//   * `top-center`
//   * `top-right`
//   * `bottom-left`
//   * `bottom-center`
//   * `bottom-right`
//
// The default is `center`.
// If resize overlays are enabled, this controls how long the overlay is
// visible on the screen before it is hidden. The default is ¾ of a second or
// 750 ms.
//
// The duration is specified as a series of numbers followed by time units.
// Whitespace is allowed between numbers and units. Each number and unit will
// be added together to form the total duration.
//
// The allowed time units are as follows:
//
//   * `y` - 365 SI days, or 8760 hours, or 31536000 seconds. No adjustments
//     are made for leap years or leap seconds.
//   * `d` - one SI day, or 86400 seconds.
//   * `h` - one hour, or 3600 seconds.
//   * `m` - one minute, or 60 seconds.
//   * `s` - one second.
//   * `ms` - one millisecond, or 0.001 second.
//   * `us` or `µs` - one microsecond, or 0.000001 second.
//   * `ns` - one nanosecond, or 0.000000001 second.
//
// Examples:
//   * `1h30m`
//   * `45s`
//
// Units can be repeated and will be added together. This means that
// `1h1h` is equivalent to `2h`. This is confusing and should be avoided.
// A future update may disallow this.
//
// The maximum value is `584y 49w 23h 34m 33s 709ms 551µs 615ns`. Any
// value larger than this will be clamped to the maximum value.
//
// Available since 1.0.0
// If true, when there are multiple split panes, the mouse selects the pane
// that is focused. This only applies to the currently focused window; e.g.
// mousing over a split in an unfocused window will not focus that split
// and bring the window to front.
//
// Default is false.
// Whether to allow programs running in the terminal to read/write to the
// system clipboard (OSC 52, for googling). The default is to allow clipboard
// reading after prompting the user and allow writing unconditionally.
//
// Valid values are:
//
//   * `ask`
//   * `allow`
//   * `deny`
//
// Trims trailing whitespace on data that is copied to the clipboard. This does
// not affect data sent to the clipboard via `clipboard-write`. This only
// applies to trailing whitespace on lines that have other characters.
// Completely blank lines always have their whitespace trimmed.
// Require confirmation before pasting text that appears unsafe. This helps
// prevent a "copy/paste attack" where a user may accidentally execute unsafe
// commands by pasting text with newlines.
// If true, bracketed pastes will be considered safe. By default, bracketed
// pastes are considered safe. "Bracketed" pastes are pastes while the running
// program has bracketed paste mode enabled (a setting set by the running
// program, not the terminal emulator).
// Enables or disabled title reporting (CSI 21 t). This escape sequence
// allows the running program to query the terminal title. This is a common
// security issue and is disabled by default.
//
// Warning: This can expose sensitive information at best and enable
// arbitrary code execution at worst (with a maliciously crafted title
// and a minor amount of user interaction).
//
// Available since: 1.0.1
// The total amount of bytes that can be used for image data (e.g. the Kitty
// image protocol) per terminal screen. The maximum value is 4,294,967,295
// (4GiB). The default is 320MB. If this is set to zero, then all image
// protocols will be disabled.
//
// This value is separate for primary and alternate screens so the effective
// limit per surface is double.
// Whether to automatically copy selected text to the clipboard. `true`
// will prefer to copy to the selection clipboard, otherwise it will copy to
// the system clipboard.
//
// The value `clipboard` will always copy text to the selection clipboard
// as well as the system clipboard.
//
// Middle-click paste will always use the selection clipboard. Middle-click
// paste is always enabled even if this is `false`.
//
// The default value is true on Linux and macOS.
// The action to take when the user right-clicks on the terminal surface.
//
// Valid values:
//   * `context-menu` - Show the context menu.
//   * `paste` - Paste the contents of the clipboard.
//   * `copy` - Copy the selected text to the clipboard.
//   * `copy-or-paste` - If there is a selection, copy the selected text to
//      the clipboard; otherwise, paste the contents of the clipboard.
//   * `ignore` - Do nothing, ignore the right-click.
//
// The default value is `context-menu`.
// The time in milliseconds between clicks to consider a click a repeat
// (double, triple, etc.) or an entirely new single click. A value of zero will
// use a platform-specific default. The default on macOS is determined by the
// OS settings. On every other platform it is 500ms.
// Additional configuration files to read. This configuration can be repeated
// to read multiple configuration files. Configuration files themselves can
// load more configuration files. Paths are relative to the file containing the
// `config-file` directive. For command-line arguments, paths are relative to
// the current working directory.
//
// Prepend a ? character to the file path to suppress errors if the file does
// not exist. If you want to include a file that begins with a literal ?
// character, surround the file path in double quotes (").
//
// Cycles are not allowed. If a cycle is detected, an error will be logged and
// the configuration file will be ignored.
//
// Configuration files are loaded after the configuration they're defined
// within in the order they're defined. **THIS IS A VERY SUBTLE BUT IMPORTANT
// POINT.** To put it another way: configuration files do not take effect
// until after the entire configuration is loaded. For example, in the
// configuration below:
//
// ```
// config-file = "foo"
// a = 1
// ```
//
// If "foo" contains `a = 2`, the final value of `a` will be 2, because
// `foo` is loaded after the configuration file that configures the
// nested `config-file` value.
// When this is true, the default configuration file paths will be loaded.
// The default configuration file paths are currently only the XDG
// config path ($XDG_CONFIG_HOME/witty/config.witty).
//
// If this is false, the default configuration paths will not be loaded.
// This is targeted directly at using Witty from the CLI in a way
// that minimizes external effects.
//
// This is a CLI-only configuration. Setting this in a configuration file
// will have no effect. It is not an error, but it will not do anything.
// This configuration can only be set via CLI arguments.
// Confirms that a surface should be closed before closing it.
//
// This defaults to `true`. If set to `false`, surfaces will close without
// any confirmation. This can also be set to `always`, which will always
// confirm closing a surface, even if shell integration says a process isn't
// running.
// Whether or not to quit after the last surface is closed.
//
// This defaults to `false` on macOS since that is standard behavior for
// a macOS application. On Linux, this defaults to `true` since that is
// generally expected behavior.
//
// On Linux, if this is `true`, Witty can delay quitting fully until a
// configurable amount of time has passed after the last window is closed.
// See the documentation of `quit-after-last-window-closed-delay`.
// Controls how long Witty will stay running after the last open surface has
// been closed. This only has an effect if `quit-after-last-window-closed` is
// also set to `true`.
//
// The minimum value for this configuration is `1s`. Any values lower than
// this will be clamped to `1s`.
//
// The duration is specified as a series of numbers followed by time units.
// Whitespace is allowed between numbers and units. Each number and unit will
// be added together to form the total duration.
//
// The allowed time units are as follows:
//
//   * `y` - 365 SI days, or 8760 hours, or 31536000 seconds. No adjustments
//     are made for leap years or leap seconds.
//   * `d` - one SI day, or 86400 seconds.
//   * `h` - one hour, or 3600 seconds.
//   * `m` - one minute, or 60 seconds.
//   * `s` - one second.
//   * `ms` - one millisecond, or 0.001 second.
//   * `us` or `µs` - one microsecond, or 0.000001 second.
//   * `ns` - one nanosecond, or 0.000000001 second.
//
// Examples:
//   * `1h30m`
//   * `45s`
//
// Units can be repeated and will be added together. This means that
// `1h1h` is equivalent to `2h`. This is confusing and should be avoided.
// A future update may disallow this.
//
// The maximum value is `584y 49w 23h 34m 33s 709ms 551µs 615ns`. Any
// value larger than this will be clamped to the maximum value.
//
// By default `quit-after-last-window-closed-delay` is unset and
// Witty will quit immediately after the last window is closed if
// `quit-after-last-window-closed` is `true`.
//
// Only implemented on Linux.
// This controls whether an initial window is created when Witty
// is run. Note that if `quit-after-last-window-closed` is `true` and
// `quit-after-last-window-closed-delay` is set, setting `initial-window` to
// `false` will mean that Witty will quit after the configured delay if no
// window is ever created. Only implemented on Linux and macOS.
// The duration that undo operations remain available. After this
// time, the operation will be removed from the undo stack and
// cannot be undone.
//
// The default value is 5 seconds.
//
// This timeout applies per operation, meaning that if you perform
// multiple operations, each operation will have its own timeout.
// New operations do not reset the timeout of previous operations.
//
// A timeout of zero will effectively disable undo operations. It is
// not possible to set an infinite timeout, but you can set a very
// large timeout to effectively disable the timeout (on the order of years).
// This is highly discouraged, as it will cause the undo stack to grow
// indefinitely, memory usage to grow unbounded, and terminal sessions
// to never actually quit.
//
// The duration is specified as a series of numbers followed by time units.
// Whitespace is allowed between numbers and units. Each number and unit will
// be added together to form the total duration.
//
// The allowed time units are as follows:
//
//   * `y` - 365 SI days, or 8760 hours, or 31536000 seconds. No adjustments
//     are made for leap years or leap seconds.
//   * `d` - one SI day, or 86400 seconds.
//   * `h` - one hour, or 3600 seconds.
//   * `m` - one minute, or 60 seconds.
//   * `s` - one second.
//   * `ms` - one millisecond, or 0.001 second.
//   * `us` or `µs` - one microsecond, or 0.000001 second.
//   * `ns` - one nanosecond, or 0.000000001 second.
//
// Examples:
//   * `1h30m`
//   * `45s`
//
// Units can be repeated and will be added together. This means that
// `1h1h` is equivalent to `2h`. This is confusing and should be avoided.
// A future update may disallow this.
//
// This configuration is only supported on macOS. Linux doesn't
// support undo operations at all so this configuration has no
// effect.
//
// Available since: 1.2.0
// The position of the "quick" terminal window. To learn more about the
// quick terminal, see the documentation for the `toggle_quick_terminal`
// binding action.
//
// Valid values are:
//
//   * `top` - Terminal appears at the top of the screen.
//   * `bottom` - Terminal appears at the bottom of the screen.
//   * `left` - Terminal appears at the left of the screen.
//   * `right` - Terminal appears at the right of the screen.
//   * `center` - Terminal appears at the center of the screen.
//
// On macOS, changing this configuration requires restarting Witty
// completely.
//
// Note: There is no default keybind for toggling the quick terminal.
// To enable this feature, bind the `toggle_quick_terminal` action to a key.
// The size of the quick terminal.
//
// The size can be specified either as a percentage of the screen dimensions
// (height/width), or as an absolute size in pixels. Percentage values are
// suffixed with `%` (e.g. `20%`) while pixel values are suffixed with `px`
// (e.g. `300px`). A bare value without a suffix is a config error.
//
// When only one size is specified, the size parameter affects the size of
// the quick terminal on its *primary axis*, which depends on its position:
// height for quick terminals placed on the top or bottom, and width for left
// or right. The primary axis of a centered quick terminal depends on the
// monitor's orientation: height when on a landscape monitor, and width when
// on a portrait monitor.
//
// The *secondary axis* would be maximized for non-center positioned
// quick terminals unless another size parameter is specified, separated
// from the first by a comma (`,`). Percentage and pixel sizes can be mixed
// together: for instance, a size of `50%,500px` for a top-positioned quick
// terminal would be half a screen tall, and 500 pixels wide.
//
// Available since: 1.2.0
// The layer of the quick terminal window. The higher the layer,
// the more windows the quick terminal may conceal.
//
// Valid values are:
//
//  * `overlay`
//
//    The quick terminal appears in front of all windows.
//
//  * `top` (default)
//
//    The quick terminal appears in front of normal windows but behind
//    fullscreen overlays like lock screens.
//
//  * `bottom`
//
//    The quick terminal appears behind normal windows but in front of
//    wallpapers and other windows in the background layer.
//
//  * `background`
//
//    The quick terminal appears behind all windows.
//
// GTK Wayland only.
//
// Available since: 1.2.0
// The namespace for the quick terminal window.
//
// This is an identifier that is used by the Wayland compositor and/or
// scripts to determine the type of layer surfaces and to possibly apply
// unique effects.
//
// GTK Wayland only.
//
// Available since: 1.2.0
// The screen where the quick terminal should show up.
//
// Valid values are:
//
//  * `main` - The screen that the operating system recommends as the main
//    screen. On macOS, this is the screen that is currently receiving
//    keyboard input. This screen is defined by the operating system and
//    not chosen by Witty.
//
//  * `mouse` - The screen that the mouse is currently hovered over.
//
//  * `macos-menu-bar` - The screen that contains the macOS menu bar as
//    set in the display settings on macOS. This is a bit confusing because
//    every screen on macOS has a menu bar, but this is the screen that
//    contains the primary menu bar.
//
// The default value is `main` because this is the recommended screen
// by the operating system.
//
// Only implemented on macOS.
// Duration (in seconds) of the quick terminal enter and exit animation.
// Set it to 0 to disable animation completely. This can be changed at
// runtime.
//
// Only implemented on macOS.
// Automatically hide the quick terminal when focus shifts to another window.
// Set it to false for the quick terminal to remain open even when it loses focus.
//
// Defaults to true on macOS and on false on Linux/BSD. This is because global
// shortcuts on Linux require system configuration and are considerably less
// accessible than on macOS, meaning that it is more preferable to keep the
// quick terminal open until the user has completed their task.
// This default may change in the future.
// This configuration option determines the behavior of the quick terminal
// when switching between macOS spaces. macOS spaces are virtual desktops
// that can be manually created or are automatically created when an
// application is in full-screen mode.
//
// Valid values are:
//
//  * `move` - When switching to another space, the quick terminal will
//    also moved to the current space.
//
//  * `remain` - The quick terminal will stay only in the space where it
//    was originally opened and will not follow when switching to another
//    space.
//
// The default value is `move`.
//
// Only implemented on macOS.
// On Linux the behavior is always equivalent to `move`.
//
// Available since: 1.1.0
// Determines under which circumstances that the quick terminal should receive
// keyboard input. See the corresponding [Wayland documentation](https://wayland.app/protocols/wlr-layer-shell-unstable-v1#zwlr_layer_surface_v1:enum:keyboard_interactivity)
// for a more detailed explanation of the behavior of each option.
//
// > [!NOTE]
// > The exact behavior of each option may differ significantly across
// > compositors -- experiment with them on your system to find one that
// > suits your liking!
//
// Valid values are:
//
//  * `none`
//
//    The quick terminal will not receive any keyboard input.
//
//  * `on-demand` (default)
//
//    The quick terminal would only receive keyboard input when it is focused.
//
//  * `exclusive`
//
//    The quick terminal will always receive keyboard input, even when another
//    window is currently focused.
//
// Only has an effect on Linux Wayland.
// On macOS the behavior is always equivalent to `on-demand`.
//
// Available since: 1.2.0
// Whether to enable shell integration auto-injection or not. Shell integration
// greatly enhances the terminal experience by enabling a number of features:
//
//   * Working directory reporting so new tabs, splits inherit the
//     previous terminal's working directory.
//
//   * Prompt marking that enables the "jump_to_prompt" keybinding.
//
//   * If you're sitting at a prompt, closing a terminal will not ask
//     for confirmation.
//
//   * Resizing the window with a complex prompt usually paints much
//     better.
//
// Allowable values are:
//
//   * `none` - Do not do any automatic injection. You can still manually
//     configure your shell to enable the integration.
//
//   * `detect` - Detect the shell based on the filename.
//
//   * `bash`, `elvish`, `fish`, `nushell`, `zsh` - Use this specific shell injection scheme.
//
// The default value is `detect`.
// Shell integration features to enable. These require our shell integration
// to be loaded, either automatically via shell-integration or manually.
//
// The format of this is a list of features to enable separated by commas. If
// you prefix a feature with `no-` then it is disabled. If you omit a feature,
// its default value is used, so you must explicitly disable features you don't
// want. You can also use `true` or `false` to turn all features on or off.
//
// Example: `cursor`, `no-cursor`, `sudo`, `no-sudo`, `title`, `no-title`
//
// Available features:
//
//   * `cursor` - Set the cursor to a blinking bar at the prompt.
//
//   * `sudo` - Set sudo wrapper to preserve terminfo.
//
//   * `title` - Set the window title via shell integration.
//
//   * `ssh-env` - Enable SSH environment variable compatibility. Automatically
//     converts TERM from `xterm-witty` to `xterm-256color` when connecting to
//     remote hosts and propagates COLORTERM, TERM_PROGRAM, and TERM_PROGRAM_VERSION.
//     Whether or not these variables will be accepted by the remote host(s) will
//     depend on whether or not the variables are allowed in their sshd_config.
//     (Available since: 1.2.0)
//
//   * `ssh-terminfo` - Enable automatic terminfo installation on remote hosts.
//     Attempts to install Witty's terminfo entry using `infocmp` and `tic` when
//     connecting to hosts that lack it. Requires `infocmp` to be available locally
//     and `tic` to be available on remote hosts. Once terminfo is installed on a
//     remote host, it will be automatically "cached" to avoid repeat installations.
//     If desired, the `+ssh-cache` CLI action can be used to manage the installation
//     cache manually using various arguments.
//     (Available since: 1.2.0)
//
//   * `path` - Add Witty's binary directory to PATH. This ensures the `witty`
//     command is available in the shell even if shell init scripts reset PATH.
//     This is particularly useful on macOS where PATH is often overridden by
//     system scripts. The directory is only added if not already present.
//
// SSH features work independently and can be combined for optimal experience:
// when both `ssh-env` and `ssh-terminfo` are enabled, Witty will install its
// terminfo on remote hosts and use `xterm-witty` as TERM, falling back to
// `xterm-256color` with environment variables if terminfo installation fails.
// Custom entries into the command palette.
//
// Each entry requires the title, the corresponding action, and an optional
// description. Each field should be prefixed with the field name, a colon
// (`:`), and then the specified value. The syntax for actions is identical
// to the one for keybind actions. Whitespace in between fields is ignored.
//
// If you need to embed commas or any other special characters in the values,
// enclose the value in double quotes and it will be interpreted as a Zig
// string literal. This is also useful for including whitespace at the
// beginning or the end of a value. See the
// [Zig documentation](https://ziglang.org/documentation/master/#Escape-Sequences)
// for more information on string literals. Note that multiline string literals
// are not supported.
//
// Double quotes can not be used around the field names.
//
// ```ini
// command-palette-entry = title:Reset Font Style, action:csi:0m
// command-palette-entry = title:Crash on Main Thread,description:Causes a crash on the main (UI) thread.,action:crash:main
// command-palette-entry = title:Focus Split: Right,description:"Focus the split to the right, if it exists.",action:goto_split:right
// command-palette-entry = title:"Witty",description:"Add a little Witty to your terminal.",action:"text:\xf0\x9f\x91\xbb"
// ```
//
// By default, the command palette is preloaded with most actions that might
// be useful in an interactive setting yet do not have easily accessible or
// memorizable shortcuts. The default entries can be cleared by setting this
// setting to an empty value:
//
// ```ini
// command-palette-entry =
// ```
//
// Available since: 1.2.0
// Sets the reporting format for OSC sequences that request color information.
// Witty currently supports OSC 10 (foreground), OSC 11 (background), and
// OSC 4 (256 color palette) queries, and by default the reported values
// are scaled-up RGB values, where each component are 16 bits. This is how
// most terminals report these values. However, some legacy applications may
// require 8-bit, unscaled, components. We also support turning off reporting
// altogether. The components are lowercase hex values.
//
// Allowable values are:
//
//   * `none` - OSC 4/10/11 queries receive no reply
//
//   * `8-bit` - Color components are return unscaled, e.g. `rr/gg/bb`
//
//   * `16-bit` - Color components are returned scaled, e.g. `rrrr/gggg/bbbb`
//
// The default value is `16-bit`.
// If true, allows the "KAM" mode (ANSI mode 2) to be used within
// the terminal. KAM disables keyboard input at the request of the
// application. This is not a common feature and is not recommended
// to be enabled. This will not be documented further because
// if you know you need KAM, you know. If you don't know if you
// need KAM, you don't need it.
// Custom shaders to run after the default shaders. This is a file path
// to a GLSL-syntax shader for all platforms.
//
// Warning: Invalid shaders can cause Witty to become unusable such as by
// causing the window to be completely black. If this happens, you can
// unset this configuration to disable the shader.
//
// Custom shader support is based on and compatible with the Shadertoy shaders.
// Shaders should specify a `mainImage` function and the available uniforms
// largely match Shadertoy, with some caveats and Witty-specific extensions.
//
// The uniform values available to shaders are as follows:
//
//  * `sampler2D iChannel0` - Input texture.
//
//    A texture containing the current terminal screen. If multiple custom
//    shaders are specified, the output of previous shaders is written to
//    this texture, to allow combining multiple effects.
//
//  * `vec3 iResolution` - Output texture size, `[width, height, 1]` (in px).
//
//  * `float iTime` - Time in seconds since first frame was rendered.
//
//  * `float iTimeDelta` - Time in seconds since previous frame was rendered.
//
//  * `float iFrameRate` - Average framerate. (NOT CURRENTLY SUPPORTED)
//
//  * `int iFrame` - Number of frames that have been rendered so far.
//
//  * `float iChannelTime[4]` - Current time for video or sound input. (N/A)
//
//  * `vec3 iChannelResolution[4]` - Resolutions of the 4 input samplers.
//
//    Currently only `iChannel0` exists, and `iChannelResolution[0]` is
//    identical to `iResolution`.
//
//  * `vec4 iMouse` - Mouse input info. (NOT CURRENTLY SUPPORTED)
//
//  * `vec4 iDate` - Date/time info. (NOT CURRENTLY SUPPORTED)
//
//  * `float iSampleRate` - Sample rate for audio. (N/A)
//
// Witty-specific extensions:
//
//  * `vec4 iCurrentCursor` - Info about the terminal cursor.
//
//    - `iCurrentCursor.xy` is the -X, +Y corner of the current cursor.
//    - `iCurrentCursor.zw` is the width and height of the current cursor.
//
//  * `vec4 iPreviousCursor` - Info about the previous terminal cursor.
//
//  * `vec4 iCurrentCursorColor` - Color of the terminal cursor.
//
//  * `vec4 iPreviousCursorColor` - Color of the previous terminal cursor.
//
//  * `float iTimeCursorChange` - Timestamp of terminal cursor change.
//
//    When the terminal cursor changes position or color, this is set to
//    the same time as the `iTime` uniform, allowing you to compute the
//    time since the change by subtracting this from `iTime`.
//
//  * `float iTimeFocus` - Timestamp when the surface last gained iFocus.
//
//    When the surface gains focus, this is set to the current value of
//    `iTime`, similar to how `iTimeCursorChange` works. This allows you
//    to compute the time since focus was gained or lost by calculating
//    `iTime - iTimeFocus`. Use this to create animations that restart
//    when the terminal regains focus.
//
//  * `int iFocus` - Current focus state of the surface.
//
//    Set to 1.0 when the surface is focused, 0.0 when unfocused. This
//    allows shaders to detect unfocused state and avoid animation artifacts
//    from large time deltas caused by infrequent "deceptive frames"
//    (e.g., modifier key presses, link hover events in unfocused split panes).
//    Check `iFocus > 0` to determine if the surface is currently focused.
//
//  * `vec3 iPalette[256]` - The 256-color terminal palette.
//
//    RGB values for all 256 colors in the terminal palette, normalized
//    to [0.0, 1.0]. Index 0-15 are the ANSI colors, 16-231 are the 6x6x6
//    color cube, and 232-255 are the grayscale colors.
//
//  * `vec3 iBackgroundColor` - Terminal background color (RGB).
//
//  * `vec3 iForegroundColor` - Terminal foreground color (RGB).
//
//  * `vec3 iCursorColor` - Terminal cursor color (RGB).
//
//  * `vec3 iCursorText` - Terminal cursor text color (RGB).
//
//  * `vec3 iSelectionBackgroundColor` - Selection background color (RGB).
//
//  * `vec3 iSelectionForegroundColor` - Selection foreground color (RGB).
//
// If the shader fails to compile, the shader will be ignored. Any errors
// related to shader compilation will not show up as configuration errors
// and only show up in the log, since shader compilation happens after
// configuration loading on the dedicated render thread.  For interactive
// development, use [shadertoy.com](https://shadertoy.com).
//
// This can be repeated multiple times to load multiple shaders. The shaders
// will be run in the order they are specified.
//
// This can be changed at runtime and will affect all open terminals.
// If `true` (default), the focused terminal surface will run an animation
// loop when custom shaders are used. This uses slightly more CPU (generally
// less than 10%) but allows the shader to animate. This only runs if there
// are custom shaders and the terminal is focused.
//
// If this is set to `false`, the terminal and custom shader will only render
// when the terminal is updated. This is more efficient but the shader will
// not animate.
//
// This can also be set to `always`, which will always run the animation
// loop regardless of whether the terminal is focused or not. The animation
// loop will still only run when custom shaders are used. Note that this
// will use more CPU per terminal surface and can become quite expensive
// depending on the shader and your terminal usage.
//
// This can be changed at runtime and will affect all open terminals.
// Bell features to enable if bell support is available in your runtime. Not
// all features are available on all runtimes. The format of this is a list of
// features to enable separated by commas. If you prefix a feature with `no-`
// then it is disabled. If you omit a feature, its default value is used.
//
// Valid values are:
//
//  * `system`
//
//    Instruct the system to notify the user using built-in system functions.
//    This could result in an audiovisual effect, a notification, or something
//    else entirely. Changing these effects require altering system settings:
//    for instance under the "Sound > Alert Sound" setting in GNOME,
//    or the "Accessibility > System Bell" settings in KDE Plasma.
//
//    On macOS, this plays the system alert sound.
//
//  * `audio`
//
//    Play a custom sound. (GTK only)
//
//  * `attention` *(enabled by default)*
//
//    Request the user's attention when Witty is unfocused, until it has
//    received focus again. On macOS, this will bounce the app icon in the
//    dock once. On Linux, the behavior depends on the desktop environment
//    and/or the window manager/compositor:
//
//    - On KDE, the background of the desktop icon in the task bar would be
//      highlighted;
//
//    - On GNOME, you may receive a notification that, when clicked, would
//      bring the Witty window into focus;
//
//    - On Sway, the window may be decorated with a distinctly colored border;
//
//    - On other systems this may have no effect at all.
//
//  * `title` *(enabled by default)*
//
//    Prepend a bell emoji (🔔) to the title of the alerted surface until the
//    terminal is re-focused or interacted with (such as on keyboard input).
//
//  * `border`
//
//    Display a border around the alerted surface until the terminal is
//    re-focused or interacted with (such as on keyboard input).
//
//    Available since: 1.2.0 on GTK, 1.2.1 on macOS
//
// Example: `audio`, `no-audio`, `system`, `no-system`
//
// Available since: 1.2.0
// If `audio` is an enabled bell feature, this is a path to an audio file. If
// the path is not absolute, it is considered relative to the directory of the
// configuration file that it is referenced from, or from the current working
// directory if this is used as a CLI flag. The path may be prefixed with `~/`
// to reference the user's home directory. (GTK only)
//
// Available since: 1.2.0
// If `audio` is an enabled bell feature, this is the volume to play the audio
// file at (relative to the system volume). This is a floating point number
// ranging from 0.0 (silence) to 1.0 (as loud as possible). The default is 0.5.
// (GTK only)
//
// Available since: 1.2.0
// Control the in-app notifications that Witty shows.
//
// On Linux (GTK), in-app notifications show up as toasts. Toasts appear
// overlaid on top of the terminal window. They are used to show information
// that is not critical but may be important.
//
// Possible notifications are:
//
//   - `clipboard-copy` (default: true) - Show a notification when text is copied
//     to the clipboard.
//   - `config-reload` (default: true) - Show a notification when
//     the configuration is reloaded.
//
// To specify a notification to enable, specify the name of the notification.
// To specify a notification to disable, prefix the name with `no-`. For
// example, to disable `clipboard-copy`, set this configuration to
// `no-clipboard-copy`. To enable it, set this configuration to `clipboard-copy`.
//
// Multiple notifications can be enabled or disabled by separating them
// with a comma.
//
// A value of "false" will disable all notifications. A value of "true" will
// enable all notifications.
//
// This configuration only applies to GTK.
//
// Available since: 1.1.0
// If anything other than false, fullscreen mode on macOS will not use the
// native fullscreen, but make the window fullscreen without animations and
// using a new space. It's faster than the native fullscreen mode since it
// doesn't use animations.
//
// Important: tabs DO NOT WORK in this mode. Non-native fullscreen removes
// the titlebar and macOS native tabs require the titlebar. If you use tabs,
// you should not use this mode.
//
// If you fullscreen a window with tabs, the currently focused tab will
// become fullscreen while the others will remain in a separate window in
// the background. You can switch to that window using normal window-switching
// keybindings such as command+tilde. When you exit fullscreen, the window
// will return to the tabbed state it was in before.
//
// Allowable values are:
//
//   * `true` - Use non-native macOS fullscreen, hide the menu bar
//   * `false` - Use native macOS fullscreen
//   * `visible-menu` - Use non-native macOS fullscreen, keep the menu bar
//     visible
//   * `padded-notch` - Use non-native macOS fullscreen, hide the menu bar,
//     but ensure the window is not obscured by the notch on applicable
//     devices. The area around the notch will remain transparent currently,
//     but in the future we may fill it with the window background color.
//
// Changing this option at runtime works, but will only apply to the next
// time the window is made fullscreen. If a window is already fullscreen,
// it will retain the previous setting until fullscreen is exited.
// Whether the window buttons in the macOS titlebar are visible. The window
// buttons are the colored buttons in the upper left corner of most macOS apps,
// also known as the traffic lights, that allow you to close, miniaturize, and
// zoom the window.
//
// This setting has no effect when `window-decoration = none` or
// `macos-titlebar-style = hidden`, as the window buttons are always hidden in
// these modes.
//
// Valid values are:
//
//   * `visible` - Show the window buttons.
//   * `hidden` - Hide the window buttons.
//
// The default value is `visible`.
//
// Changing this option at runtime only applies to new windows.
//
// Available since: 1.2.0
// The style of the macOS titlebar. Available values are: "native",
// "transparent", "tabs", and "hidden".
//
// The "native" style uses the native macOS titlebar with zero customization.
// The titlebar will match your window theme (see `window-theme`).
//
// The "transparent" style is the same as "native" but the titlebar will
// be transparent and allow your window background color to come through.
// This makes a more seamless window appearance but looks a little less
// typical for a macOS application and may not work well with all themes.
//
// The "transparent" style will also update in real-time to dynamic
// changes to the window background color, e.g. via OSC 11. To make this
// more aesthetically pleasing, this only happens if the terminal is
// a window, tab, or split that borders the top of the window. This
// avoids a disjointed appearance where the titlebar color changes
// but all the topmost terminals don't match.
//
// The "tabs" style is a completely custom titlebar that integrates the
// tab bar into the titlebar. This titlebar always matches the background
// color of the terminal. There are some limitations to this style:
// On macOS 13 and below, saved window state will not restore tabs correctly.
// macOS 14 does not have this issue and any other macOS version has not
// been tested.
//
// The "hidden" style hides the titlebar. Unlike `window-decoration = none`,
// however, it does not remove the frame from the window or cause it to have
// squared corners. Changing to or from this option at run-time may affect
// existing windows in buggy ways.
//
// When "hidden", the top titlebar area can no longer be used for dragging
// the window. To drag the window, you can use option+click on the resizable
// areas of the frame to drag the window. This is a standard macOS behavior
// and not something Witty enables.
//
// The default value is "transparent". This is an opinionated choice
// but its one I think is the most aesthetically pleasing and works in
// most cases.
//
// Changing this option at runtime only applies to new windows.
// Whether the proxy icon in the macOS titlebar is visible. The proxy icon
// is the icon that represents the folder of the current working directory.
// You can see this very clearly in the macOS built-in Terminal.app
// titlebar.
//
// The proxy icon is only visible with the native macOS titlebar style.
//
// Valid values are:
//
//   * `visible` - Show the proxy icon.
//   * `hidden` - Hide the proxy icon.
//
// The default value is `visible`.
//
// This setting can be changed at runtime and will affect all currently
// open windows but only after their working directory changes again.
// Therefore, to make this work after changing the setting, you must
// usually `cd` to a different directory, open a different file in an
// editor, etc.
// Controls the windowing behavior when dropping a file or folder
// onto the Witty icon in the macOS dock.
//
// Valid values are:
//
//   * `new-tab` - Create a new tab in the current window, or open
//     a new window if none exist.
//   * `new-window` - Create a new window unconditionally.
//
// The default value is `new-tab`.
//
// This setting is only supported on macOS and has no effect on other
// platforms.
// macOS doesn't have a distinct "alt" key and instead has the "option"
// key which behaves slightly differently. On macOS by default, the
// option key plus a character will sometimes produce a Unicode character.
// For example, on US standard layouts option-b produces "∫". This may be
// undesirable if you want to use "option" as an "alt" key for keybindings
// in terminal programs or shells.
//
// This configuration lets you change the behavior so that option is treated
// as alt.
//
// The default behavior (unset) will depend on your active keyboard
// layout. If your keyboard layout is one of the keyboard layouts listed
// below, then the default value is "true". Otherwise, the default
// value is "false". Keyboard layouts with a default value of "true" are:
//
//   - U.S. Standard
//   - U.S. International
//
// Note that if an *Option*-sequence doesn't produce a printable character, it
// will be treated as *Alt* regardless of this setting. (e.g. `alt+ctrl+a`).
//
// Explicit values that can be set:
//
// If `true`, the *Option* key will be treated as *Alt*. This makes terminal
// sequences expecting *Alt* to work properly, but will break Unicode input
// sequences on macOS if you use them via the *Alt* key.
//
// You may set this to `false` to restore the macOS *Alt* key unicode
// sequences but this will break terminal sequences expecting *Alt* to work.
//
// The values `left` or `right` enable this for the left or right *Option*
// key, respectively.
// Whether to enable the macOS window shadow. The default value is true.
// With some window managers and window transparency settings, you may
// find false more visually appealing.
// If true, the macOS icon in the dock and app switcher will be hidden. This is
// mainly intended for those primarily using the quick-terminal mode.
//
// Note that setting this to true means that keyboard layout changes
// will no longer be automatic.
//
// Control whether macOS app is excluded from the dock and app switcher,
// a "hidden" state. This is mainly intended for those primarily using
// quick-terminal mode, but is a general configuration for any use
// case.
//
// Available values:
//
//   * `never` - The macOS app is never hidden.
//   * `always` - The macOS app is always hidden.
//
// Note: When the macOS application is hidden, keyboard layout changes
// will no longer be automatic. This is a limitation of macOS.
//
// Available since: 1.2.0
// If true, Witty on macOS will automatically enable the "Secure Input"
// feature when it detects that a password prompt is being displayed.
//
// "Secure Input" is a macOS security feature that prevents applications from
// reading keyboard events. This can always be enabled manually using the
// `Witty > Secure Keyboard Entry` menu item.
//
// Note that automatic password prompt detection is based on heuristics
// and may not always work as expected. Specifically, it does not work
// over SSH connections, but there may be other cases where it also
// doesn't work.
//
// A reason to disable this feature is if you find that it is interfering
// with legitimate accessibility software (or software that uses the
// accessibility APIs), since secure input prevents any application from
// reading keyboard events.
// If true, Witty will show a graphical indication when secure input is
// enabled. This indication is generally recommended to know when secure input
// is enabled.
//
// Normally, secure input is only active when a password prompt is displayed
// or it is manually (and typically temporarily) enabled. However, if you
// always have secure input enabled, the indication can be distracting and
// you may want to disable it.
// Customize the macOS app icon.
//
// This only affects the icon that appears in the dock, application
// switcher, etc. This does not affect the icon in Finder because
// that is controlled by a hardcoded value in the signed application
// bundle and can't be changed at runtime. For more details on what
// exactly is affected, see the `NSApplication.icon` Apple documentation;
// that is the API that is being used to set the icon.
//
// Valid values:
//
//  * `official` - Use the official Witty icon.
//  * `blueprint`, `chalkboard`, `microchip`, `glass`, `holographic`,
//    `paper`, `retro`, `xray` - Official variants of the Witty icon
//    hand-created by artists (no AI).
//  * `custom` - Use a completely custom icon. The location must be specified
//    using the additional `macos-custom-icon` configuration
//  * `custom-style` - Use the official Witty icon but with custom
//    styles applied to various layers. The custom styles must be
//    specified using the additional `macos-icon`-prefixed configurations.
//    The `macos-icon-ghost-color` and `macos-icon-screen-color`
//    configurations are required for this style.
//
// WARNING: The `custom-style` option is _experimental_. We may change
// the format of the custom styles in the future. We're still finalizing
// the exact layers and customization options that will be available.
//
// Other caveats:
//
//   * The icon in the update dialog will always be the official icon.
//     This is because the update dialog is managed through a
//     separate framework and cannot be customized without significant
//     effort.
// The absolute path to the custom icon file.
// Supported formats include PNG, JPEG, and ICNS.
//
// Defaults to `~/.config/witty/Witty.icns`
// The material to use for the frame of the macOS app icon.
//
// Valid values:
//
//  * `aluminum` - A brushed aluminum frame. This is the default.
//  * `beige` - A classic 90's computer beige frame.
//  * `plastic` - A glossy, dark plastic frame.
//  * `chrome` - A shiny chrome frame.
//
// Note: This configuration is required when `macos-icon` is set to
// `custom-style`.
// The color of the ghost in the macOS app icon.
//
// Note: This configuration is required when `macos-icon` is set to
// `custom-style`.
//
// Specified as either hex (`#RRGGBB` or `RRGGBB`) or a named X11 color.
// The color of the screen in the macOS app icon.
//
// The screen is a linear gradient so you can specify multiple colors
// that make up the gradient. Up to 64 comma-separated colors may be
// specified as either hex (`#RRGGBB` or `RRGGBB`) or as named X11
// colors. The first color is the bottom of the gradient and the last
// color is the top of the gradient.
//
// Note: This configuration is required when `macos-icon` is set to
// `custom-style`.
// Whether macOS Shortcuts are allowed to control Witty.
//
// Witty exposes a number of actions that allow Shortcuts to
// control and interact with Witty. This includes creating new
// terminals, sending text to terminals, running commands, invoking
// any keybind action, etc.
//
// This is a powerful feature but can be a security risk if a malicious
// shortcut is able to be installed and executed. Therefore, this
// configuration allows you to disable this feature.
//
// Valid values are:
//
// * `ask` - Ask the user whether for permission. Witty will remember
//   this choice and never ask again. This is similar to other macOS
//   permissions such as microphone access, camera access, etc.
//
// * `allow` - Allow Shortcuts to control Witty without asking.
//
// * `deny` - Deny Shortcuts from controlling Witty.
//
// Available since: 1.2.0
// Put every surface (tab, split, window) into a dedicated Linux cgroup.
//
// This makes it so that resource management can be done on a per-surface
// granularity. For example, if a shell program is using too much memory,
// only that shell will be killed by the oom monitor instead of the entire
// Witty process. Similarly, if a shell program is using too much CPU,
// only that surface will be CPU-throttled.
//
// This will cause startup times to be slower (a hundred milliseconds or so),
// so the default value is "single-instance." In single-instance mode, only
// one instance of Witty is running (see gtk-single-instance) so the startup
// time is a one-time cost. Additionally, single instance Witty is much
// more likely to have many windows, tabs, etc. so cgroup isolation is a
// big benefit.
//
// This feature requires systemd. If systemd is unavailable, cgroup
// initialization will fail. By default, this will not prevent Witty
// from working (see linux-cgroup-hard-fail).
//
// Valid values are:
//
//   * `never` - Never use cgroups.
//   * `always` - Always use cgroups.
//   * `single-instance` - Enable cgroups only for Witty instances launched
//     as single-instance applications (see gtk-single-instance).
// Memory limit for any individual terminal process (tab, split, window,
// etc.) in bytes. If this is unset then no memory limit will be set.
//
// Note that this sets the "memory.high" configuration for the memory
// controller, which is a soft limit. You should configure something like
// systemd-oom to handle killing processes that have too much memory
// pressure.
// Number of processes limit for any individual terminal process (tab, split,
// window, etc.). If this is unset then no limit will be set.
//
// Note that this sets the "pids.max" configuration for the process number
// controller, which is a hard limit.
// If this is false, then any cgroup initialization (for linux-cgroup)
// will be allowed to fail and the failure is ignored. This is useful if
// you view cgroup isolation as a "nice to have" and not a critical resource
// management feature, because Witty startup will not fail if cgroup APIs
// fail.
//
// If this is true, then any cgroup initialization failure will cause
// Witty to exit or new surfaces to not be created.
//
// Note: This currently only affects cgroup initialization. Subprocesses
// must always be able to move themselves into an isolated cgroup.
// Enable or disable GTK's OpenGL debugging logs. The default is `true` for
// debug builds, `false` for all others.
//
// Available since: 1.1.0
// If `true`, the Witty GTK application will run in single-instance mode:
// each new `witty` process launched will result in a new window if there is
// already a running process.
//
// If `false`, each new witty process will launch a separate application.
//
// If `detect`, Witty will assume true (single instance) unless one of
// the following scenarios is found:
//
// 1. TERM_PROGRAM environment variable is a non-empty value. In this
// case, we assume Witty is being launched from a graphical terminal
// session and you want a dedicated instance.
//
// 2. Any CLI arguments exist. In this case, we assume you are passing
// custom Witty configuration. Single instance mode inherits the
// configuration from when it was launched, so we must disable single
// instance to load the new configuration.
//
// If either of these scenarios is producing a false positive, you can
// set this configuration explicitly to the behavior you want.
//
// The pre-1.2 option `desktop` has been deprecated. Please replace
// this with `detect`.
//
// The default value is `detect`.
//
// Note that debug builds of Witty have a separate single-instance ID
// so you can test single instance without conflicting with release builds.
// When enabled, the full GTK titlebar is displayed instead of your window
// manager's simple titlebar. The behavior of this option will vary with your
// window manager.
//
// This option does nothing when `window-decoration` is none or when running
// under macOS.
// Determines the side of the screen that the GTK tab bar will stick to.
// Top, bottom, and hidden are supported. The default is top.
//
// When `hidden` is set, a tab button displaying the number of tabs will appear
// in the title bar. It has the ability to open a tab overview for displaying
// tabs. Alternatively, you can use the `toggle_tab_overview` action in a
// keybind if your window doesn't have a title bar, or you can switch tabs
// with keybinds.
// If this is `true`, the titlebar will be hidden when the window is maximized,
// and shown when the titlebar is unmaximized. GTK only.
//
// Available since: 1.1.0
// Determines the appearance of the top and bottom bars tab bar.
//
// Valid values are:
//
//  * `flat` - Top and bottom bars are flat with the terminal window.
//  * `raised` - Top and bottom bars cast a shadow on the terminal area.
//  * `raised-border` - Similar to `raised` but the shadow is replaced with a
//    more subtle border.
// The style of the GTK titlebar. Available values are `native` and `tabs`.
//
// The `native` titlebar style is a traditional titlebar with a title, a few
// buttons and window controls. A separate tab bar will show up below the
// titlebar if you have multiple tabs open in the window.
//
// The `tabs` titlebar merges the tab bar and the traditional titlebar.
// This frees up vertical space on your screen if you use multiple tabs. One
// limitation of the `tabs` titlebar is that you cannot drag the titlebar
// by the titles any longer (as they are tab titles now). Other areas of the
// `tabs` title bar can be used to drag the window around.
//
// The default style is `native`.
// If `true` (default), then the Witty GTK tabs will be "wide." Wide tabs
// are the new typical Gnome style where tabs fill their available space.
// If you set this to `false` then tabs will only take up space they need,
// which is the old style.
// Custom CSS files to be loaded.
//
// GTK CSS documentation can be found at the following links:
//
//   * https://docs.gtk.org/gtk4/css-overview.html - An overview of GTK CSS.
//   * https://docs.gtk.org/gtk4/css-properties.html - A comprehensive list
//     of supported CSS properties.
//
// Launch Witty with `env GTK_DEBUG=interactive witty` to tweak Witty's
// CSS in real time using the GTK Inspector. Errors in your CSS files would
// also be reported in the terminal you started Witty from. See
// https://developer.gnome.org/documentation/tools/inspector.html for more
// information about the GTK Inspector.
//
// This configuration can be repeated multiple times to load multiple files.
// Prepend a ? character to the file path to suppress errors if the file does
// not exist. If you want to include a file that begins with a literal ?
// character, surround the file path in double quotes (").
// The file size limit for a single stylesheet is 5MiB.
//
// Available since: 1.1.0
// If `true` (default), applications running in the terminal can show desktop
// notifications using certain escape sequences such as OSC 9 or OSC 777.
// Modifies the color used for bold text in the terminal.
//
// This can be set to a specific color, using the same format as
// `background` or `foreground` (e.g. `#RRGGBB` but other formats
// are also supported; see the aforementioned documentation). If a
// specific color is set, this color will always be used for the default
// bold text color. It will set the rest of the bold colors to `bright`.
//
// This can also be set to `bright`, which uses the bright color palette
// for bold text. For example, if the text is red, then the bold will
// use the bright red color. The terminal palette is set with `palette`
// but can also be overridden by the terminal application itself using
// escape sequences such as OSC 4. (Since Witty 1.2.0, the previous
// configuration `bold-is-bright` is deprecated and replaced by this
// usage).
//
// Available since Witty 1.2.0.
// The opacity level (opposite of transparency) of the faint text. A value of
// 1 is fully opaque and a value of 0 is fully transparent. A value less than 0
// or greater than 1 will be clamped to the nearest valid value.
//
// Available since Witty 1.2.0.
// This will be used to set the `TERM` environment variable.
// HACK: We set this with an `xterm` prefix because vim uses that to enable key
// protocols (specifically this will enable `modifyOtherKeys`), among other
// features. An option exists in vim to modify this: `:set
// keyprotocol=witty:kitty`, however a bug in the implementation prevents it
// from working properly. https://github.com/vim/vim/pull/13211 fixes this.
// String to send when we receive `ENQ` (`0x05`) from the command that we are
// running. Defaults to an empty string if not set.
// Configures the low-level API to use for async IO, eventing, etc.
//
// Most users should leave this set to `auto`. This will automatically detect
// scenarios where APIs may not be available (for example `io_uring` on
// certain hardened kernels) and fall back to a different API. However, if
// you want to force a specific backend for any reason, you can set this
// here.
//
// Based on various benchmarks, we haven't found a statistically significant
// difference between the backends with regards to memory, CPU, or latency.
// The choice of backend is more about compatibility and features.
//
// Available options:
//
//   * `auto` - Automatically choose the best backend for the platform
//     based on available options.
//   * `epoll` - Use the `epoll` API
//   * `io_uring` - Use the `io_uring` API
//
// If the selected backend is not available on the platform, Witty will
// fall back to an automatically chosen backend that is available.
//
// Changing this value requires a full application restart to take effect.
//
// This is only supported on Linux, since this is the only platform
// where we have multiple options. On macOS, we always use `kqueue`.
//
// Available since: 1.2.0
// Control the auto-update functionality of Witty. This is only supported
// on macOS currently, since Linux builds are distributed via package
// managers that are not centrally controlled by Witty.
//
// Checking or downloading an update does not send any information to
// the project beyond standard network information mandated by the
// underlying protocols. To put it another way: Witty doesn't explicitly
// add any tracking to the update process. The update process works by
// downloading information about the latest version and comparing it
// client-side to the current version.
//
// Valid values are:
//
//  * `off` - Disable auto-updates.
//  * `check` - Check for updates and notify the user if an update is
//    available, but do not automatically download or install the update.
//  * `download` - Check for updates, automatically download the update,
//    notify the user, but do not automatically install the update.
//
// If unset, we defer to Sparkle's default behavior, which respects the
// preference stored in the standard user defaults (`defaults(1)`).
//
// Changing this value at runtime works after a small delay.
// The release channel to use for auto-updates.
//
// The default value of this matches the release channel of the currently
// running Witty version. If you download a pre-release version of Witty
// then this will be set to `tip` and you will receive pre-release updates.
// If you download a stable version of Witty then this will be set to
// `stable` and you will receive stable updates.
//
// Valid values are:
//
//  * `stable` - Stable, tagged releases such as "1.0.0".
//  * `tip` - Pre-release versions generated from each commit to the
//    main branch. This is the version that was in use during private
//    beta testing by thousands of people. It is generally stable but
//    will likely have more bugs than the stable channel.
//
// Changing this configuration requires a full restart of
// Witty to take effect.
//
// This only works on macOS since only macOS has an auto-update feature.
// This is set by the CLI parser for deinit.
// List of diagnostics that were generated during the loading of
// the configuration.
// The conditional truths for the configuration. This is used to
// determine if a conditional configuration matches or not.
// The conditional keys that are used at any point during the configuration
// loading. This is used to speed up the conditional evaluation process.
// The steps we can use to reload the configuration after it has been loaded
// without reopening the files. This is used in very specific cases such
// as loadTheme which has more details on why.
// Set to true if Witty was executed as xdg-terminal-exec on Linux.
// Load the configuration according to the default rules:
//
//   1. Defaults
//   2. XDG config dir
//   3. "Application Support" directory (macOS only)
//   4. CLI flags
//   5. Recursively defined configuration files
//
// If we have a configuration file in our home directory, parse that first.
// Parse the config from the CLI args.
// Parse the config files that were added from our file and CLI args.
// Build up our basic config
// Add our default keybindings
// Add our default command palette entries
// Add our default link for URL detection
// Load configuration from an iterator that yields values that look like
// command-line arguments, i.e. `--key=value`.
// Load configuration from the target config file at `path`.
//
// `path` must be resolved and absolute.
// Load config from the given File.
// Load config from the given Reader.
// If the file starts with a UTF-8 byte order mark, skip it.
// https://en.wikipedia.org/wiki/Byte_order_mark#UTF-8
// Load optional configuration file from `path`. All errors are ignored.
//
// Returns the action that was taken.
// Load configurations from the default configuration files. The default
// configuration file is at `$XDG_CONFIG_HOME/witty/config.witty`.
//
// On macOS, `$HOME/Library/Application Support/$CFBundleIdentifier/`
// is also loaded.
//
// The legacy `config` file (without extension) is first loaded,
// then `config.witty`.
// Load XDG first
// On macOS load the app support directory as well
// If both files are not found, then we create a template file.
// For macOS, we only create the template file in the app support
// Load and parse the CLI args.
// Fast-path if we are Linux/BSD and have no args.
// Everything else we have to at least try because it may
// not use std.os.argv.
// On Linux, we have a special case where if the executing
// program is "xdg-terminal-exec" then we treat all CLI
// args as if they are a command to execute.
//
// In this mode, we also behave slightly differently:
//
//   - The initial window title is set to the full command. This
//     can be used with window managers to modify positioning,
//     styling, etc. based on the command.
//
// See: https://github.com/Vladimir-csp/xdg-terminal-exec
// First, we add an artificial "-e" so that if we
// replay the inputs to rebuild the config (i.e. if
// a theme is set) then we will get the same behavior.
// Next, take all remaining args and use that to build up
// a command to execute.
// We set config-default-files to true here because this
// should always be reset so we can detect if it is set
// in the CLI since it is documented as having no affect
// from files.
// Keep track of the replay steps up to this point so we
// can replay if we are discarding the default files.
// font-family settings set via the CLI overwrite any prior values
// rather than append. This avoids a UX oddity where you have to
// specify `font-family=""` to clear the font families.
// Initialize our CLI iterator.
// If we are not loading the default files, then we need to
// replay the steps up to this point so that we can rebuild
// the config without it.
// Any paths referenced from the CLI are relative to the current working
// directory.
// Load and parse the config files that were added in the "config-file" key.
// Keeps track of loaded files to prevent cycles.
// We need to insert all of our loaded config-file values
// PRIOR to the "-e" in our replay steps, since everything
// after "-e" becomes an "initial-command". To do this, we
// dupe the values if we find it.
// We don't need to clone the steps because they should
// all be allocated in our arena and we're keeping our
// arena.
// Remove our old values. Again, don't need to free any
// memory here because its all part of our arena.
// We must use a while below and not a for(items) because we
// may add items to the list while iterating for recursive
// config-file entries.
// Error paths
// All paths should already be absolute at this point because
// they're fixed up after each load.
// We must only load a unique file once
// If we have a suffix, add that back.
// Get the arena allocator associated with the configuration.
// Change the state of conditionals and reload the configuration
// based on the new state. This returns a new configuration based
// on the new state. The caller must free the old configuration if they
// wish.
//
// This returns null if the conditional state would result in no changes
// to the configuration. In this case, the caller can continue to use
// the existing configuration or clone if they want a copy.
//
// This doesn't re-read any files, it just re-applies the same
// configuration with the new conditional state. Importantly, this means
// that if you change the conditional state and the user in the interim
// deleted a file that was referenced in the configuration, then the
// configuration can still be reloaded.
// If the conditional state between the old and new is the same,
// then we don't need to do anything.
// Conditional set contains the keys that this config uses. So we
// only continue if we use this key.
// If we got here, then we didn't find any differences between
// the old and new conditional state that would affect the
// configuration.
// Create our new configuration
// Set our conditional state so the replay below can use it
// Replay all of our steps to rebuild the configuration
// Expand the relative paths in config-files to be absolute paths
// relative to the base directory.
// Keep track of this step for replays
// Expand all of our paths
// Load the correct theme depending on the conditional state.
// Dark/light themes were programmed prior to conditional configuration
// so when we introduce that we probably want to replace this.
// Find our theme file and open it. See the open function for details.
// From this point onwards, we load the theme and do a bit of a dance
// to achieve two separate goals:
//
//   (1) We want the theme to be loaded and our existing config to
//       override the theme. So we need to load the theme and apply
//       our config on top of it.
//
//   (2) We want to free existing memory that we aren't using anymore
//       as a result of reloading the configuration.
//
// Point 2 is strictly a result of aur approach to point 1, but it is
// a nice property to have to limit memory bloat as much as possible.
// Load into a new configuration so that we can free the existing memory.
// Load our theme
// Setup our replay to be conditional.
// If we see "-e" then we do NOT make the following arguments
// conditional since they are supposed to be part of the
// initial command.
// Change our arg to be conditional on our theme.
// Replay our previous inputs so that we can override values
// from the theme.
// Success, swap our new config in and free the old.
// Call this once after you are done setting configuration. This
// is idempotent but will waste memory if called multiple times.
// We always load the theme first because it may set other fields
// in our config.
// Warning: loadTheme will deinit our existing config and replace
// it so all memory from self prior to this point will be freed.
// If we have different light vs dark mode themes, disable
// window-theme = auto since that breaks it.
// This setting doesn't make sense with different light/dark themes
// because it'll force the theme based on the Witty theme.
// Mark that we use a conditional theme
// Used for a variety of defaults. See the function docs as well the
// specific variable use sites for more details.
// If we have a font-family set and don't set the others, default
// the others to the font family. This way, if someone does
// --font-family=foo, then we try to get the stylized versions of
// "foo" as well.
// Prevent setting TERM to an empty string
// HACK: See comment above at definition
// The default for the working directory depends on the system.
// From the CLI, we want to inherit where we were launched from.
// Otherwise we typically just want the home directory because
// our pwd is probably a runtime state dir or root or something
// (launchers and desktop environments typically do this).
// If we are missing either a command or home directory, we need
// to look up defaults which is kind of expensive. We only do this
// on desktop.
// First look up the command using the SHELL env var if needed.
// We don't do this in flatpak because SHELL in Flatpak is always
// set to /bin/sh.
// Flatpak always gets its shell from outside the sandbox
// If we were launched from the desktop, our SHELL env var
// will represent our SHELL at login time. We only want to
// read from SHELL if we're in a probable CLI environment.
// If we don't need the working directory, then we can exit now.
// We need the passwd entry for the remainder
// Apprt-specific defaults
// For detection, we assume single instance unless we're
// in a CLI environment, then we disable single instance.
// If we have the special value "inherit" then set it to null which
// does the same. In the future we should change to a tagged union.
// Default our click interval
// Clamp our mouse scroll multiplier
// Clamp our split opacity
// Clamp our contrast
// Minimum window size
// If URLs are disabled, cut off the first link. The first link is
// always the URL matcher.
// We warn when the quit-after-last-window-closed-delay is set to a very
// short value because it can cause Witty to quit before the first
// window is even shown.
// We can't set this as a struct default because our config is
// loaded in environments where a build config isn't available.
// Finalize key remapping set for efficient lookups
// Callback for src/cli/args.zig to allow us to handle special cases
// like `--help` or `-e`. Returns "false" if the CLI parsing should halt.
// Add the special -e marker. This prevents:
// (1) config-file from adding args to the end (see #2908)
// (2) dark/light theme from making this conditional
// Build up the command. We don't clean this up because we take
// ownership in our allocator.
// See "command" docs for the implied configurations and why.
// Do not continue, we consumed everything.
// Keep track of our input args for replay
// If we didn't find a special case, continue parsing normally
// We don't do anything if the value is unset, which is technically
// not EXACTLY the same as prior behavior since it would fallback
// to doing whatever cursor-color/cursor-text were set to, but
// I don't want to store what that is separately so this is close
// enough.
//
// Realistically, these fields were mutually exclusive so anyone
// relying on that behavior should just upgrade to the new
// cursor-color/cursor-text fields.
// Add a diagnostic message to the config with the given string.
// This is always added with a location of "none".
// Create a shallow copy of this config. This will share all the memory
// allocated with the previous config but will have a new arena for
// any changes or new allocations. The config should have `deinit`
// called when it is complete.
//
// Beware: these shallow clones are not meant for a long lifetime,
// they are just meant to exist temporarily for the duration of some
// modifications. It is very important that the original config not
// be deallocated while shallow clones exist.
// Create a copy of the metadata of this configuration but without
// the actual values. Metadata includes conditional state.
// Create a copy of this configuration.
//
// This will not re-read referenced configuration files and operates
// purely in-memory.
// Start with an empty config
// Copy our values
// Copy our diagnostics
// Preserve our replay steps. We copy them exactly to also preserve
// the exact conditionals required for some steps.
// Copy the conditional set
// Do known named types first
// If we're a type that can have decls and we have clone, then
// call clone and be done.
// Back into types of types
// Packed structs we can return directly as copies.
// Returns an iterator that goes through each changed field from
// old to new. The order of old or new do not matter.
// Returns true if the given key has changed from old to new. This
// requires the key to be comptime known to make this more efficient.
// Get the field at comptime
// This yields a key for every changed field between old and new.
// This runs a heuristic to determine if we are likely running
// Witty in a CLI environment. We need this to change some behaviors.
// We should keep the set of behaviors that depend on this as small
// as possible because magic sucks, but each place is well documented.
// Windows has its own problems, just ignore it for now since
// its not a real supported target and GTK via WSL2 assuming
// single instance is probably fine.
// On macOS, we don't want to detect `open` calls as CLI envs.
// Our desktop detection on macOS is very accurate due to how
// processes are launched on macOS, so if we detect we're launched
// from the app bundle then we're not in a CLI environment.
// If we have TERM_PROGRAM set to a non-empty value, we assume
// a graphical terminal environment.
// CLI arguments makes things probable
// Unlikely CLI environment
// This is used to "replay" the configuration. See loadTheme for details.
// An argument to parse as if it came from the CLI or file.
// A base path to expand relative paths against.
// A conditional argument. This arg is parsed only if all
// conditions match (an "AND"). An "OR" can be achieved by
// having multiple conditional arg entries.
// A diagnostic to be added to the new configuration when
// replayed. This should only be used for diagnostics that won't
// be reproduced during playback. For example, `config-file`
// errors are not reloaded so they should be added here.
//
// Diagnostics cannot be conditional. They are always present
// even if the conditionals don't match. This helps users find
// errors in their configuration.
// The start of a "-e" argument. This marks the end of
// traditional configuration and the beginning of the
// "-e" initial command magic. This is separate from "arg"
// because there are some behaviors unique to this (i.e.
// we want to keep this at the end for config-file).
//
// Note: when "-e" is used, ONLY this is present and
// not an additional "arg" with "-e" value.
// This shouldn't happen because to reach this step
// means that it succeeded before. Its possible since
// expanding paths is a side effect process that the
// world state changed and we can't expand anymore.
// In that really unfortunate case, we log a warning.
// Best effort to clone and append the diagnostic.
// If it fails we log a warning and continue.
// All conditions must match.
// Construct a Replay iterator from a slice of replay elements.
// This can be used with args.parse and handles intermediate
// steps such as expanding relative paths.
// Valid values for confirm-close-surface
// c_int because it needs to be extern compatible
// If this is changed, you must also update witty.h
// Valid values for custom-shader-animation
// c_int because it needs to be extern compatible
// If this is changed, you must also update witty.h
// Valid values for macos-non-native-fullscreen
// c_int because it needs to be extern compatible
// If this is changed, you must also update witty.h
// Color represents a color using RGB.
//
// This is a packed struct so that the C API to read color values just
// works by setting it to a C integer.
// ghostty_config_color_s
// Convert this to the terminal RGB struct
// Trim any whitespace before processing
// Deep copy of the struct. Required by Config.
// Compare if two of our value are requal. Required by Config.
// Used by Formatter
// Format the color as a string.
// fromHex parses a color from a hex value such as #RRGGBB. The "#"
// is optional.
// Trim the beginning '#' if it exists
// Expand short hex values to full hex values
// Parse the colors two at a time.
// Represents color values that can also reference special color
// values such as "cell-foreground" or "cell-background".
// Used by Formatter
// Represents color values that can be used for bold. See `bold-color`.
// Used by Formatter
// ghostty_config_color_list_s
// Always reset on parse
// Split the input by commas and parse each color
// Trim whitespace from each color value
// If no colors were parsed, we need to return an error
// Compare if two of our value are requal. Required by Config.
// Used by Formatter
// If no items, we want to render an empty field.
// Build up the value of our config. Our buffer size should be
// sized to contain all possible maximum values.
// Test whitespace handling
// Error cases
// Palette is the 256 color palette for 256-color mode. This is still
// used by many terminal applications.
// The actual value that is updated as we parse.
// ghostty_config_palette_s
// Parse the key part (trim whitespace)
// Parse the color part (Color.parseCLI will handle whitespace)
// Deep copy of the struct. Required by Config.
// Compare if two of our value are requal. Required by Config.
// Used by Formatter
// RepeatableString is a string value that can be repeated to accumulate
// a list of strings. This isn't called "StringList" because I find that
// sometimes leads to confusion that it _accepts_ a list such as
// comma-separated values.
// Allocator for the list is the arena for the parent config.
// If true, then the next value will clear the list and start over
// rather than append. This is a bit of a hack but is here to make
// the font-family set of configurations work with CLI parsing.
// Empty value resets the list
// If we're overwriting then we clear before appending
// Deep copy of the struct. Required by Config.
// Copy the list and all the strings in the list.
// The number of items in the list
// Compare if two of our value are requal. Required by Config.
// Used by Formatter
// If no items, we want to render an empty field.
// Set our overwrite flag
// SelectionWordChars stores the parsed codepoints for word boundary
// characters used during text selection. The string is parsed once
// during configuration and stored as u21 codepoints for efficient
// lookup during selection operations.
// Default boundary characters: ` \t'"│`|:;,()[]{}<>$`
// The parsed codepoints. Always includes null (U+0000) at index 0.
// Parse UTF-8 string into codepoints
// Always include null as first boundary
// Parse the UTF-8 string
// Invalid UTF-8, just use null boundary
// Deep copy of the struct. Required by Config.
// Compare if two values are equal. Required by Config.
// Used by Formatter
// Convert codepoints back to UTF-8 string for display
// Skip the null character at index 0
// Should have null + 4 characters
// FontVariation is a repeatable configuration value that sets a single
// font variation value. Font variations are configurations for what
// are often called "variable fonts." The font files usually end in
// "-VF.ttf."
//
// The value for this is in the format of `id=value` where `id` is the
// 4-character font variation axis identifier and `value` is the
// floating point value for that axis. For more details on font variations
// see the MDN font-variation-settings documentation since this copies that
// behavior almost exactly:
//
// https://developer.mozilla.org/en-US/docs/Web/CSS/font-variation-settings
// Allocator for the list is the arena for the parent config.
// Deep copy of the struct. Required by Config.
// Compare if two of our value are requal. Required by Config.
// Used by Formatter
// Stores a set of keybinds.
// Defined key tables. The default key table is always the root "set",
// which allows all table names to be available without reservation.
// We don't clear the memory because it's in the arena and unlikely
// to be free-able anyways (since arenas can only clear the last
// allocated value). This isn't a memory leak because the arena
// will be freed when the config is freed.
// keybinds for opening and reloading config
// On non-MacOS desktop envs (Windows, KDE, Gnome, Xfce), ctrl+insert is an
// alt keybinding for Copy and shift+ins is an alt keybinding for Paste
//
// The order of these blocks is important. The *last* added keybind for a given action is
// what will display in the menu. We want the more typical keybinds after this block to be
// the standard
// On macOS we default to super but Linux ctrl+shift since
// ctrl+c is to kill the process.
// Increase font size mapping for keyboards with dedicated plus keys (like german)
// Note: this order matters below because the C API will only return
// the last keybinding for a given action. The macOS app uses this to
// set the expected keybind for the menu.
// Expand Selection
// Tabs common to all platforms
// Windowing
// Resizing splits
// Viewport scrolling
// Semantic prompts
// Search
// Inspector, matching Chromium
// Terminal
// Selection clipboard paste
// On macOS we default to super but everywhere else
// is alt.
// Cmd/Alt+N for goto tab N
// We register BOTH the physical `digit_N` key and the unicode
// `N` key. This allows most keyboard layouts to work with
// this shortcut. Namely, AZERTY doesn't produce unicode `N`
// for their digit keys (they're on shifted keys on the same
// physical keys).
// On macOS we keep this not performable so that the
// keyboard shortcuts in tabs work. In the future the
// correct fix is to fix the reverse mapping lookup
// to allow us to lookup performable keybinds
// conditionally.
// Important: this must be the LAST binding set so that the
// libwitty trigger API returns this one for the action,
// so that things like the macOS tab bar key equivalent label
// work properly.
// See comment above with the numeric goto_tab
// Toggle fullscreen
// Toggle zoom a split
// Toggle command palette, matches VSCode
// Mac-specific keyboard bindings.
// Undo/redo
// Viewport scrolling
// Semantic prompts
// Mac windowing
// Jump to prompt, matches Terminal.app
// Search
// Inspector, matching Chromium
// Alternate keybind, common to Mac programs
// Selection clipboard paste, matches Terminal.app
// "Natural text editing" keybinds. This forces these keys to go back
// to legacy encoding (not fixterms). It seems macOS users more than
// others are used to these keys so we set them as defaults. If
// people want to get back to the fixterm encoding they can set
// the keybinds to `unbind`.
// If we don't have a colon, use the value as-is, no copy
// If we have a colon, we copy the whole value for now. We could
// do this more efficiently later if we wanted to.
// Check for special values
// We don't clear the memory because its in the arena and unlikely
// to be free-able anyways (since arenas can only clear the last
// allocated value). This isn't a memory leak because the arena
// will be freed when the config is freed.
// Check for table syntax: "name/" or "name/binding"
// We look for '/' only before the first '=' to avoid matching
// action arguments like "foo=text:/hello".
// Length zero is valid, so you can set `/=action` for the slash key
// Ignore '+', '>' because they can be part of sequences and
// triggers. This lets things like `ctrl+/=action` work.
// Get or create the table
// We need to copy our table name into the arena
// for valid lookups later.
// If there's no binding after the slash, this is a table
// definition/clear command
// Parse and add the binding to the table
// Parse into default set
// Deep copy of the struct. Required by Config.
// Compare if two of our value are requal. Required by Config.
// Compare tables
// Two keybinds are considered equal if their primary bindings
// are the same. We don't compare reverse mappings and such.
// If the count of mappings isn't identical they can't be equal
// If the trigger isn't in the other map, they can't be equal
// If the entry types are different, they can't be equal
// They're equal if both leader sets are equal.
// Actions are compared by field directly
// Like formatEntry but has an option to include docs.
// Format root set bindings
// Format table bindings
// Used by Formatter
// Regression test for https://github.com/ghostty-org/ghostty/issues/2734
// Note they turn into translated keys because they match
// their ASCII mapping.
// NB: This does not currently retain the order of the keybinds.
// Define a table by adding a binding to it
// Add a binding to a table
// Clear the table with "foo/"
// Root set should have the first binding
// Table should have the second binding
// Key sequences should work within tables
// A slash after the = should not be interpreted as a table delimiter
// Should be in root set, not a table
// ctrl+/ should be parsed as a keybind with '/' as the key, not a table
// Should be in root set, not a table
// shift+/ should be parsed as a keybind, not a table
// Should be in root set, not a table
// Bare / as a key should work (empty table name is rejected)
// Should be in root set, not a table
// Key sequence ending with / should work
// Should be in root set, not a table
// Table with a binding that uses / as the key
// Should be in the table
// Table with a key sequence that ends with /
// Should be in the table
// Verify the clone has the same structure
// Add bindings to root set and tables
// Clear all keybinds
// Both root set and tables should be cleared
// Add bindings to tables
// Reset to defaults (empty value)
// Tables should be cleared, root set has defaults
// See "font-codepoint-map" for documentation.
// Deep copy of the struct. Required by Config.
// Compare if two of our value are equal. Required by Config.
// Used by Formatter
// Parses the list of Unicode codepoint ranges. Valid syntax:
//
//   "" (empty returns null)
//   U+1234
//   U+1234-5678
//   U+1234,U+5678
//   U+1234-5678,U+5678
//   U+1234,U+5678-U+9ABC
//
// etc.
// Once we're EOF then we're done without an error.
// One codepoint no matter what
// We're allowed to have any whitespace here
// Otherwise we expect either a range or a comma
// Comma means we have another codepoint but in a different
// range so we return our current codepoint.
// Hyphen means we have a range.
// Advance but break on EOF
// If we didn't consume a single character, we have an error.
// See "clipboard-codepoint-map" for documentation.
// Parse the replacement value - either a codepoint or string
// Parse as codepoint
// Parse as UTF-8 string - validate it's valid UTF-8
// Deep copy of the struct. Required by Config.
// Compare if two of our value are equal. Required by Config.
// Used by Formatter
// Reuse the same UnicodeRangeParser from RepeatableCodepointMap
// Use the default font style that font discovery finds.
// Disable this font style completely. This will fall back to using
// the regular font when this style is encountered.
// A specific named font style to use for this style.
// Returns the string name value that can be used with a font
// descriptor.
// Deep copy of the struct. Required by Config.
// Used by Formatter
// See `font-synthetic-style` for documentation.
// See "font-shaping-break" for documentation
// See "link" for documentation.
// Deep copy of the struct. Required by Config.
// Note: we don't do any errdefers below since the allocation
// is expected to be arena allocated.
// Compare if two of our value are requal. Required by Config.
// Used by Formatter
// This currently can't be set so we don't format anything.
// Options for copy on select behavior.
// Disables copy on select entirely.
// Copy on select is enabled, but goes to the selection clipboard.
// This is not supported on platforms such as macOS. This is the default.
// Copy on select is enabled and goes to both the system clipboard
// and the selection clipboard (for Linux).
// Options for right-click actions.
// No action is taken on right-click.
// Pastes from the system clipboard.
// Copies the selected text to the system clipboard.
// Copies the selected text to the system clipboard and
// pastes the clipboard if no text is selected.
// Shows a context menu with options.
// Shell integration values
// Shell integration features
// ghostty_config_command_list_s
// Unset or empty input clears the list
// Reserve space in our lists
// Deep copy of the struct. Required by Config.
// Compare if two of our value are equal. Required by Config.
// Used by Formatter
// First entry
// Second entry
// OSC 4, 10, 11, and 12 default color reporting format.
// The default window theme.
// See window-colorspace
// See macos-window-buttons
// See macos-titlebar-style
// See macos-titlebar-proxy-icon
// See macos-hidden
// See macos-icon
//
// Note: future versions of Witty can support a custom icon with
// path by changing this to a tagged union, which doesn't change our
// format at all.
// See macos-icon-frame
// See macos-shortcuts
// See gtk-single-instance
// See gtk-tabs-location
// See gtk-toolbar-style
// See gtk-titlebar-style
// See app-notifications
// See bell-features
// See mouse-shift-capture
// See mouse-scroll-multiplier
// Deep copy of the struct. Required by Config.
// Compare if two of our value are equal. Required by Config.
// Used by Formatter
// How to treat requests to write to or read from the clipboard
// See window-save-state
// See window-new-tab-position
// See macos-dock-drop-behavior
// See window-show-tab-bar
// See resize-overlay
// See resize-overlay-position
// See quick-terminal-position
// See quick-terminal-layer
// See quick-terminal-size
// C API structure for QuickTerminalSize
// c_int because it needs to be extern compatible
// See quick-terminal-screen
// See quick-terminal-space-behavior
// See quick-terminal-keyboard-interactivity
// See grapheme-width-method
// See alpha-blending
// See background-image-position
// See background-image-fit
// See freetype-load-flag
// The defaults here at the time of writing this match the defaults
// for Freetype itself. Witty hasn't made any opinionated changes
// to these defaults. (Strictly speaking, `light` isn't FreeType's
// own default, but appears to be the effective default with most
// Fontconfig-aware software using FreeType, so until Witty
// implements Fontconfig support we default to `light`.)
// See linux-cgroup
// See async-backend
// See auto-updates
// See background-blur
// Emulate behavior for bools
// Try to parse normal bools
// Try to parse enums
// We can only parse void types
// We treat these as true because they both imply some blur!
// This has the effect of making the standard blur happen on
// Linux.
// I hate sentinel values like this but this is only for
// our macOS application currently. We can switch to a proper
// tagged union if we ever need to.
// See window-decoration
// Make this a valid gobject if we're in a GTK environment.
// See theme
// If there is a comma, equal sign, or colon, then we assume that
// we're parsing a light/dark mode theme pair. Note that "=" isn't
// actually valid for setting a light/dark mode pair but I anticipate
// it'll be a common typo.
// Trim our value
// Set the value to the specified value directly.
// Deep copy of the struct. Required by Config.
// Used by Formatter
// Single
// Single whitespace
// Light/dark
// Duration in nanoseconds
// The order is important as the first factor that matches will be the
// default unit that is used for formatting.
// Skip over whitespace before the number
// There was whitespace at the end, that's OK
// Find the longest number
// A number without a unit is invalid unless the number is
// exactly zero. In that case, the unit is unambiguous since
// its all the same.
// Find the longest matching unit. Needs to be the longest matching
// to distinguish 'm' from 'ms'.
// Add our time value to the total. Avoid overflow with saturating math.
// Convenience function to convert to milliseconds since many OS and
// library timing functions operate on that timescale.
// Trim whitespace
// See scrollbar
// See scroll-to-bottom
// See notify-on-command-finish
// See notify-on-command-finish-action
// Overflow
// Repeated units
// Should have no changes
// I want to do this but this doesn't work (the API doesn't work)
// try testing.expectEqualDeep(dest, source);
// Should have no changes
// Should have the same conditional state
// This tests a particular bug sequence where:
//   1. Load light
//   2. Convert to dark
//   3. Clone dark
//   4. Convert to light
//   5. Config is still dark (bug)
// Setup our test theme
// Setup our test theme
// Not a conditional theme
// Setup our test theme
// Setup our test theme
// Setup our test theme
// Light
// Dark
// Light to Dark
// We need to test this BEFORE finalize, because finalize will
// convert our detect to a real value.
//
// --- Original Witty Comments End: src/config/Config.zig

// Config represents the full ghostty configuration.
pub struct Config {
pub mut:
	font_size                      f32 = default_font_size
	abnormal_command_exit_runtime  u32 = 250
	clipboard_read                 ClipboardAccess = .ask
	clipboard_write                ClipboardAccess = .allow
	clipboard_trim_trailing_spaces bool = true
	clipboard_paste_protection     bool = true
	clipboard_paste_bracketed_safe bool = true
	clipboard_codepoint_map        RepeatableClipboardCodepointMap
	copy_on_select                 CopyOnSelect = .true_
	confirm_close_surface          ConfirmCloseSurface = .true_
	cursor_click_to_move           bool = true
	desktop_notifications          bool = true
	bell_features                  BellFeatures
	bell_audio_path                ?Path
	bell_audio_volume              f64 = 0.5
	app_notifications              AppNotifications
	mouse_hide_while_typing        bool
	mouse_reporting                bool = true
	mouse_shift_capture            MouseShiftCapture = .false_
	selection_clear_on_copy        bool
	selection_clear_on_typing      bool = true
	selection_word_chars           SelectionWordChars
	vt_kam_allowed                 bool
	wait_after_command             bool
	window_padding_x               WindowPadding = WindowPadding{2, 2}
	window_padding_y               WindowPadding = WindowPadding{2, 2}
	window_padding_balance         WindowPaddingBalance
	window_height                  u32
	window_width                   u32
	title                          ?string
	title_report                   bool
	command                        ?Command
	initial_command                ?Command
	working_directory              ?string
	env                            RepeatableStringMap
	input                          RepeatableReadableIO
	term                           string = 'xterm-witty'
	shell_integration              ShellIntegration = .detect
	shell_integration_features     ShellIntegrationFeatures
	link_previews                  LinkPreviews = .true_
	scroll_to_bottom               ScrollToBottom
	// Renderer-related fields
	font_thicken               bool
	font_thicken_strength      u8 = 255
	font_shaping_break         FontShapingBreak
	cursor_color               ?TerminalColor
	cursor_opacity             f64 = 1.0
	cursor_text                ?TerminalColor
	background_opacity         f64 = 1.0
	background_opacity_cells   bool
	minimum_contrast           f64 = 1.0
	window_padding_color       WindowPaddingColor = .background
	window_vsync               bool = true
	window_colorspace          WindowColorspace = .srgb
	alpha_blending             AlphaBlending = .native
	background_blur            BackgroundBlur = BackgroundBlurFalse{}
	custom_shader              RepeatablePath
	background_image           ?Path
	background_image_opacity   f32 = 1.0
	background_image_position  BackgroundImagePosition = .center
	background_image_fit       BackgroundImageFit = .contain
	background_image_repeat    bool
	faint_opacity              f64 = 0.5
	bold_color                 ?BoldColor
	selection_background       ?TerminalColor
	selection_foreground       ?TerminalColor
	search_background          TerminalColor = TerminalColorColor{ color: ColorRGB{ r: 0xff, g: 0xe0, b: 0x82 } }
	search_foreground          TerminalColor = TerminalColorColor{ color: ColorRGB{ r: 0, g: 0, b: 0 } }
	search_selected_background TerminalColor = TerminalColorColor{ color: ColorRGB{ r: 0xf2, g: 0xa5, b: 0x7e } }
	search_selected_foreground TerminalColor = TerminalColorColor{ color: ColorRGB{ r: 0, g: 0, b: 0 } }
	link                       RepeatableLink
	// Enable URL matching. URLs are matched on hover with control (Linux) or
	// command (macOS) pressed and open using the default system application for
	// the linked URL. The URL matcher is always lowest priority of any
	// configured links.
	link_url bool = true
	// Key bindings. The format is `trigger=action`. See the docs above the
	// `keybind` handler in `apply_kv` for the full syntax. Backed by an
	// `input.Set` (root bindings) plus named key tables.
	keybind Keybinds
	// Custom and built-in commands exposed by application command palettes.
	command_palette_entry RepeatableCommand
	// One-way physical modifier remappings applied before keybinding lookup
	// and terminal input encoding.
	key_remap inputpkg.RemapSet
	// The named font style to use for each of the requested terminal font
	// styles. This looks up the style based on the font style string advertised
	// by the font itself.
	font_style             fontstyle.FontStyle = fontstyle.FontStyleDefault{}
	font_style_bold        fontstyle.FontStyle = fontstyle.FontStyleDefault{}
	font_style_italic      fontstyle.FontStyle = fontstyle.FontStyleDefault{}
	font_style_bold_italic fontstyle.FontStyle = fontstyle.FontStyleDefault{}
	// The font families to use, with fallback fonts appended by repeating the
	// option. An empty list means use the platform default.
	font_family             []string
	font_family_bold        []string
	font_family_italic      []string
	font_family_bold_italic []string
	// Apply font features. See the docs above.
	font_feature                   []string
	font_variation                 RepeatableFontVariation
	font_variation_bold            RepeatableFontVariation
	font_variation_italic          RepeatableFontVariation
	font_variation_bold_italic     RepeatableFontVariation
	font_codepoint_map             RepeatableCodepointMap
	font_synthetic_style           font.FontSyntheticStyle
	adjust_cell_width              ?font.MetricsModifier
	adjust_cell_height             ?font.MetricsModifier
	adjust_font_baseline           ?font.MetricsModifier
	adjust_underline_position      ?font.MetricsModifier
	adjust_underline_thickness     ?font.MetricsModifier
	adjust_strikethrough_position  ?font.MetricsModifier
	adjust_strikethrough_thickness ?font.MetricsModifier
	adjust_overline_position       ?font.MetricsModifier
	adjust_overline_thickness      ?font.MetricsModifier
	adjust_cursor_thickness        ?font.MetricsModifier
	adjust_cursor_height           ?font.MetricsModifier
	adjust_box_thickness           ?font.MetricsModifier
	adjust_icon_height             ?font.MetricsModifier
	freetype_load_flags            font.FreetypeLoadFlags = font.freetype_load_flags_default
	// Draw fonts with a thicker stroke, if supported (macOS only).
	// (font_thicken/font_thicken_strength are declared in the renderer group.)
	// Whether the freetype library should synthesize styles. This is a
	// comma-separated list of style keys with an optional `no-` prefix.
	// Method to use for calculating the cell width of a grapheme cluster.
	grapheme_width_method GraphemeWidthMethod = .unicode
	// The minimum runtime in ms below which we consider a process exit abnormal.
	// (abnormal_command_exit_runtime declared above.)
	// The size of the scrollback buffer in bytes. Includes the active screen.
	scrollback_limit u64 = 10_000_000 // 10MB
	// Control when the scrollbar is shown to scroll the scrollback buffer.
	scrollbar Scrollbar = .system
	// Enable or disable command-finished notifications. See docs above.
	notify_on_command_finish        NotifyOnCommandFinish = .never
	notify_on_command_finish_action NotifyOnCommandFinishAction
	notify_on_command_finish_after  Duration = Duration{ duration: 5_000_000_000 }
	// The setting that will change the application class value (GTK only).
	class ?string
	// This controls the instance name field of the WM_CLASS X11 property.
	x11_instance_name ?string
	// The response to send to the ENQ (0x05) character.
	enquiry_response string
	// Whether to start the window in a maximized state.
	maximize bool
	// Start new windows in fullscreen.
	fullscreen bool
	// A theme to use. Can be a built-in theme name or an absolute path. Both
	// light and dark may be set via `light:foo,dark:bar` syntax.
	theme ?ThemePair
	// The style of the cursor. A running program can request an explicit cursor
	// style using escape sequences.
	cursor_style terminal.CursorStyle = .block
	// The default blinking state of the cursor. null respects DEC Mode 12.
	cursor_style_blink ?bool
	// The opacity level of the unfocused split. 1 disables the fading.
	unfocused_split_opacity f64 = 0.7
	// The color to dim the unfocused split. Defaults to the background color.
	unfocused_split_fill ?ColorRGB
	// The color of the split divider. If not set, a default is chosen.
	split_divider_color ?ColorRGB
	// Control which split-tree operations preserve a zoomed split.
	split_preserve_zoom SplitPreserveZoom
	// Enable URL matching by default. (link_url declared above.)
	// Whether window decorations are enabled.
	window_decoration WindowDecoration = .auto
	// Font used for application window and tab titles.
	window_title_font_family ?string
	// Text shown in the GTK window subtitle.
	window_subtitle WindowSubtitle = .false_
	// The theme to use for the window (auto/system/light/dark/ghostty).
	window_theme WindowTheme = .auto
	// Optional titlebar colors used by the GTK ghostty window theme.
	window_titlebar_background ?ColorRGB
	window_titlebar_foreground ?ColorRGB
	// Position new tabs after the current tab or at the end.
	window_new_tab_position WindowNewTabPosition = .current
	// Controls whether the GTK tab bar is always, automatically, or never shown.
	window_show_tab_bar WindowShowTabBar = .auto
	// Controls when, where, and for how long the terminal grid size is shown
	// while a GTK surface is resized.
	resize_overlay          ResizeOverlay = .after_first
	resize_overlay_position ResizeOverlayPosition = .center
	resize_overlay_duration Duration = Duration{ duration: 750 * 1_000_000 }
	// Whether the mouse follows focus.
	focus_follows_mouse bool
	// Whether a new terminal inherits the working directory of the previous one.
	window_inherit_working_directory bool = true
	tab_inherit_working_directory    bool = true
	split_inherit_working_directory  bool = true
	// Whether a new terminal inherits the font size of the previous one.
	window_inherit_font_size bool = true
	// Initial window position (macOS only). Both axes must be set to take effect.
	window_position_x ?i16
	window_position_y ?i16
	// Window restoration and cell-increment resizing behavior (macOS only).
	window_save_state  WindowSaveState = .default
	window_step_resize bool
	// Whether to create the initial window when starting.
	initial_window bool = true
	// Quick-terminal placement and dimensions.
	quick_terminal_position QuickTerminalPosition = .top
	quick_terminal_size     QuickTerminalSize
	// Wayland layer-shell configuration for the quick terminal.
	gtk_quick_terminal_layer     QuickTerminalLayer = .top
	gtk_quick_terminal_namespace string = 'witty-quick-terminal'
	// Platform-specific quick-terminal presentation behavior.
	quick_terminal_screen             QuickTerminalScreen = .main
	quick_terminal_animation_duration f64 = 0.2
	// Automatically hide a quick terminal when it loses focus. Witty defaults
	// this on for macOS and off for Linux/BSD.
	quick_terminal_autohide               bool = default_quick_terminal_autohide
	quick_terminal_space_behavior         QuickTerminalSpaceBehavior = .move
	quick_terminal_keyboard_interactivity QuickTerminalKeyboardInteractivity = .on_demand
	// How long recently closed terminal operations remain undoable (macOS only).
	undo_timeout Duration = Duration{ duration: 5_000_000_000 }
	// Whether to enable OSC 133 based right-click actions.
	right_click_action RightClickAction = .context_menu
	// Interval in ms for detecting repeated clicks. 0 uses the system default.
	click_repeat_interval u32
	// Whether the image storage limit is enabled and its size in bytes.
	image_storage_limit u32 = 320 * 1000 * 1000
	// Whether Witty may quit after the last window is closed.
	quit_after_last_window_closed bool = default_quit_after_last_window_closed
	// Optional delay before quitting after the last window closes.
	quit_after_last_window_closed_delay ?Duration
	// Whether to load the default config files.
	config_default_files bool = true
	// A list of additional config files to load.
	config_file RepeatablePath
	// Reporting format for OSC color queries.
	osc_color_report_format OSCColorReportFormat = .format_16_bit
	// Whether a custom shader animates.
	custom_shader_animation CustomShaderAnimation = .true_
	// The multiplier applied to the scroll distance with the mouse wheel.
	mouse_scroll_multiplier MouseScrollMultiplier
	// Theme color fields used by list-themes preview
	foreground  ColorRGB = ColorRGB{ r: 0xff, g: 0xff, b: 0xff }
	background  ColorRGB = ColorRGB{ r: 0x28, g: 0x2C, b: 0x34 }
	palette     Palette = Palette.default_palette()
	diagnostics []Diagnostic
	// macOS window, keyboard, security, icon, and automation behavior.
	macos_non_native_fullscreen NonNativeFullscreen = .false_
	macos_window_buttons        MacWindowButtons = .visible
	macos_titlebar_style        MacTitlebarStyle = .transparent
	macos_titlebar_proxy_icon   MacTitlebarProxyIcon = .visible
	// Controls the windowing behavior when dropping a file onto the macOS dock
	// icon. Defaults to `new-tab`.
	macos_dock_drop_behavior      MacOSDockDropBehavior = .new_tab
	macos_option_as_alt           ?inputpkg.OptionAsAlt
	macos_window_shadow           bool = true
	macos_hidden                  MacHidden = .never
	macos_auto_secure_input       bool = true
	macos_secure_input_indication bool = true
	macos_icon                    MacAppIcon = .official
	macos_custom_icon             ?string
	macos_icon_frame              MacAppIconFrame = .aluminum
	macos_icon_ghost_color        ?ColorRGB
	macos_icon_screen_color       ?ColorList
	macos_shortcuts               MacShortcuts = .ask
	// GTK single-instance behavior. `detect` chooses at finalize time.
	gtk_single_instance GtkSingleInstance = .detect
	// Linux systemd cgroup isolation and per-terminal limits.
	linux_cgroup                 LinuxCgroup = default_linux_cgroup
	linux_cgroup_memory_limit    ?u64
	linux_cgroup_processes_limit ?u64
	linux_cgroup_hard_fail       bool
	// Enable GTK OpenGL diagnostics when stderr logging is active.
	gtk_opengl_debug bool = default_gtk_opengl_debug
	// GTK window chrome configuration.
	gtk_titlebar                     bool = true
	gtk_tabs_location                GtkTabsLocation = .top
	gtk_titlebar_hide_when_maximized bool
	gtk_toolbar_style                GtkToolbarStyle = .raised
	gtk_titlebar_style               GtkTitlebarStyle = .native
	gtk_wide_tabs                    bool = true
	// User stylesheets loaded by the GTK application in declaration order.
	gtk_custom_css RepeatablePath
	// Low-level async backend preference (Linux only).
	async_backend AsyncBackend = .auto
	// Sparkle update policy and release channel (macOS only).
	auto_update         ?AutoUpdate
	auto_update_channel ?buildcfg.ReleaseChannel
	// Internal marker set when invoked through xdg-terminal-exec.
	xdg_terminal_exec bool
	// The current conditional state (e.g. light/dark theme). This is not a
	// user-facing config option; it tracks runtime conditional evaluation.
	conditional_state ConditionalState
	// Set of conditional keys (currently only "theme") that affect the config
	// when the conditional state changes.
	conditional_set map[string]bool
	// Ordered source inputs used to rebuild the config around a theme layer.
	replay_steps []ReplayStep
	// Storage backing converted enum strings borrowed through the C API.
	capi_strings map[string]string
}

// MacOSDockDropBehavior controls behavior when dropping onto the macOS dock.
pub enum MacOSDockDropBehavior as u8 {
	new_tab
	new_window
}

pub enum NonNativeFullscreen as i32 {
	false_
	true_
	visible_menu
	padded_notch
}

pub enum MacWindowButtons as u8 {
	visible
	hidden
}

pub enum MacTitlebarStyle as u8 {
	native
	transparent
	tabs
	hidden
}

pub enum MacTitlebarProxyIcon as u8 {
	visible
	hidden
}

pub enum MacHidden as u8 {
	never
	always
}

pub enum MacAppIcon as u8 {
	official
	blueprint
	chalkboard
	microchip
	glass
	holographic
	paper
	retro
	xray
	custom
	custom_style
}

pub enum MacAppIconFrame as u8 {
	aluminum
	beige
	plastic
	chrome
}

pub enum MacShortcuts as u8 {
	allow
	deny
	ask
}

pub struct ColorList {
pub mut:
	colors   []ColorRGB
	colors_c []CConfigColor
}

pub fn (mut c ColorList) parse_cli(input ?string) ! {
	value := input or { return error('value required') }
	if value.len == 0 {
		return error('value required')
	}
	c = ColorList{}
	mut count := 0
	for raw in value.split(',') {
		if raw.len == 0 {
			continue
		}
		count++
		if count > 64 {
			return error('invalid value')
		}
		trimmed := raw.trim(' \t')
		color := color_parse_cli(trimmed)!
		c.colors << color
		c.colors_c << color.cval()
	}
	if c.colors.len == 0 {
		return error('invalid value')
	}
}

pub fn (c ColorList) clone() ColorList {
	return ColorList{
		colors: c.colors.clone()
		colors_c: c.colors_c.clone()
	}
}

@[markused]
pub fn (c ColorList) cval() CConfigColorList {
	return CConfigColorList{
		colors: if c.colors_c.len == 0 {
			unsafe { nil }
		} else {
			unsafe { &CConfigColor(c.colors_c.data) }
		}
		len: uint(c.colors_c.len)
	}
}

pub fn (c ColorList) equal(other ColorList) bool {
	if c.colors.len != other.colors.len {
		return false
	}
	for i, color in c.colors {
		if !color.equal(other.colors[i]) {
			return false
		}
	}
	return true
}

pub fn (c ColorList) format_entry() string {
	return c.colors.map(it.format_buf()).join(',')
}

// GtkSingleInstance controls GTK single-instance behavior.
pub enum GtkSingleInstance as u8 {
	false_
	true_
	detect
}

// LinuxCgroup controls when systemd cgroup isolation is enabled.
pub enum LinuxCgroup as u8 {
	never
	always
	single_instance
}

// GtkTabsLocation controls which edge hosts the tab bar.
pub enum GtkTabsLocation as u8 {
	top
	bottom
}

// GtkToolbarStyle controls the visual separation of the toolbar and terminal.
pub enum GtkToolbarStyle as u8 {
	flat
	raised
	raised_border
}

// GtkTitlebarStyle selects a traditional titlebar or a merged tab titlebar.
pub enum GtkTitlebarStyle as i32 {
	native
	tabs
}

// Keybinds is the config value type backing the `keybind` option. It is a
// faithful translation of Config.zig's `Keybinds` struct. It holds the root
// binding `set` plus any named key `tables`. Bindings are parsed via the
// existing `input.Set.parse_and_put` API.
pub struct Keybinds {
pub mut:
	set inputpkg.Set
	// Defined key tables. The default key table is always the root "set",
	// which allows all table names to be available without reservation.
	tables map[string]inputpkg.Set
}

// parse_cli parses a single `keybind` value into this Keybinds. It handles the
// special `clear` and empty (reset-to-default) values, the `name/binding`
// table syntax, and otherwise dispatches to the root set's parse_and_put.
// Faithful to Config.zig `Keybinds.parseCLI`.
pub fn (mut k Keybinds) parse_cli(input_value string) ! {
	value := input_value

	// Check for special values.
	if value.len == 0 {
		// config has 'keybind =', using default keybinds
		k.init()
		return
	}

	if value == 'clear' {
		// config has 'keybind = clear', all keybinds cleared
		k.set = inputpkg.Set{}
		k.tables = map[string]inputpkg.Set{}
		return
	}

	// Check for table syntax: "name/" or "name/binding". We look for '/' only
	// before the first '=' to avoid matching action arguments like
	// "foo=text:/hello".
	eq_idx := value.index_u8(`=`)
	scan_end := if eq_idx >= 0 { eq_idx } else { value.len }
	before_eq := value[..scan_end]
	slash_idx := before_eq.index_u8(`/`)
	if slash_idx >= 0 {
		table_name := value[..slash_idx]

		// A length-zero table name is not a table (so `/=action` binds the
		// slash key). Also, if the table name contains '+' or '>' then it is
		// part of a sequence/trigger (e.g. `ctrl+/=action`) and not a table.
		if table_name.len > 0 && table_name.index_u8(`+`) < 0 && table_name.index_u8(`>`) < 0 {
			binding := value[slash_idx + 1..]

			// Get or create the table.
			if table_name !in k.tables {
				k.tables[table_name] = inputpkg.Set{}
			}

			// If there's no binding after the slash, this is a table
			// definition/clear command.
			if binding.len == 0 {
				k.tables[table_name] = inputpkg.Set{}
				return
			}

			// Parse and add the binding to the table. The get-or-create
			// above guarantees the entry exists.
			mut t := k.tables[table_name] or { inputpkg.Set{} }
			t.parse_and_put(binding)!
			k.tables[table_name] = t
			return
		}
	}

	// Parse into default set.
	k.set.parse_and_put(value)!
}

// clone deep-copies the Keybinds. Faithful to Config.zig `Keybinds.clone`.
pub fn (k Keybinds) clone() Keybinds {
	mut tables := map[string]inputpkg.Set{}
	for name, s in k.tables {
		tables[name] = s.clone()
	}
	return Keybinds{
		set: k.set.clone()
		tables: tables
	}
}

// equal returns true if two Keybinds are equal. Only the primary bindings are
// compared (reverse mappings are not). Faithful to Config.zig `Keybinds.equal`.
pub fn (k Keybinds) equal(other Keybinds) bool {
	if !keybinds_set_equal(k.set, other.set) {
		return false
	}
	if k.tables.len != other.tables.len {
		return false
	}
	for name, s in k.tables {
		other_set := other.tables[name] or { return false }
		if !keybinds_set_equal(s, other_set) {
			return false
		}
	}
	return true
}

// format_entry_docs serializes all configured keybindings as complete config
// lines. At the pinned source revision the docs lookup compares the binding
// node tags (leader/leaf/leaf_chained) to action help names, so no help entry
// matches; docs mode still emits the leading blank line for each root entry.
// Named key-table bindings never receive documentation.
pub fn (k Keybinds) format_entry_docs(docs bool) []string {
	mut result := []string{}
	if k.set.bindings.len == 0 && k.tables.len == 0 {
		return ['keybind = ']
	}
	for entry in k.set.bindings {
		if docs {
			result << ''
		}
		single := inputpkg.Set{
			bindings: [entry]
		}
		for value in single.format_entries() {
			result << 'keybind = ${value}'
		}
	}
	for name, table in k.tables {
		for value in table.format_entries() {
			if value == 'chain=' || value.starts_with('chain=') {
				result << 'keybind = ${value}'
			} else {
				result << 'keybind = ${name}/${value}'
			}
		}
	}
	return result
}

// format_entries is Keybinds.formatEntry and therefore disables per-binding
// documentation.
pub fn (k Keybinds) format_entries() []string {
	return k.format_entry_docs(false)
}

// format_entry is Keybinds.formatEntry. The V formatter owns the field name,
// so composite values return only the serialized values.
pub fn (k Keybinds) format_entry() []string {
	return k.format_entries().map(it.all_after('keybind = '))
}

// keybinds_set_equal compares two binding sets by their primary bindings.
// Faithful to Config.zig `Keybinds.equalSet`: equal iff the same triggers map
// to the same values (recursing into leader sets). Reverse mappings are
// ignored.
fn keybinds_set_equal(a inputpkg.Set, b inputpkg.Set) bool {
	if a.bindings.len != b.bindings.len {
		return false
	}
	for entry in a.bindings {
		other := b.get(entry.trigger) or { return false }
		value := entry.value
		other_value := other.value
		match value {
			inputpkg.Leader {
				if other_value !is inputpkg.Leader {
					return false
				}
				if !keybinds_set_equal(*value.set, *(other_value as inputpkg.Leader).set) {
					return false
				}
			}
			inputpkg.Leaf {
				if other_value !is inputpkg.Leaf {
					return false
				}
				other_leaf := other_value as inputpkg.Leaf
				if !value.action.equal(other_leaf.action) {
					return false
				}
				if value.flags != other_leaf.flags {
					return false
				}
			}
			inputpkg.LeafChained {
				if other_value !is inputpkg.LeafChained {
					return false
				}
				other_chain := other_value as inputpkg.LeafChained
				if value.flags != other_chain.flags {
					return false
				}
				if value.actions.len != other_chain.actions.len {
					return false
				}
				for i, act in value.actions {
					if !act.equal(other_chain.actions[i]) {
						return false
					}
				}
			}
		}
	}
	return true
}

// init resets this Keybinds to the complete platform-default binding set.
// This follows Config.zig `Keybinds.init` in source order because the reverse
// action lookup intentionally prefers the last trigger registered for an
// action (notably for menu shortcut labels).
pub fn (mut k Keybinds) init() {
	k.set = inputpkg.Set{}
	k.tables = map[string]inputpkg.Set{}

	// keybinds for opening and reloading config
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`,`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods.init(true, false, false, false, false, false, inputpkg.SideInfo{}))
	}, inputpkg.ActionReloadConfig{})
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`,`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods{})
	}, inputpkg.ActionOpenConfig{})

	// copy/paste via dedicated keys
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyPhysical{ key: .copy }
	}, inputpkg.ActionCopyToClipboard{ value: .mixed })
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyPhysical{ key: .paste }
	}, inputpkg.ActionPasteFromClipboard{})

	// On macOS we default to super for copy/paste.
	copy_mods := inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
	k.set.put_flags(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`c`) }
		mods: copy_mods
	}, inputpkg.ActionCopyToClipboard{ value: .mixed }, inputpkg.Flags.init(true, false, false, true))
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`v`) }
		mods: copy_mods
	}, inputpkg.ActionPasteFromClipboard{})

	// Font size
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`=`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods{})
	}, inputpkg.ActionIncreaseFontSize{ value: 1 })
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`+`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods{})
	}, inputpkg.ActionIncreaseFontSize{ value: 1 })
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`-`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods{})
	}, inputpkg.ActionDecreaseFontSize{ value: 1 })
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`0`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods{})
	}, inputpkg.ActionResetFontSize{})

	// Write the visible screen to a temporary file.
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`j`) }
		mods: inputpkg.Mods.init(true, true, false, true, false, false, inputpkg.SideInfo{})
	}, inputpkg.ActionWriteScreenFile{ value: inputpkg.WriteScreen{ action: .copy, emit: .plain } })
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`j`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods.init(true, false, false, false, false, false, inputpkg.SideInfo{}))
	}, inputpkg.ActionWriteScreenFile{ value: inputpkg.WriteScreen{ action: .paste, emit: .plain } })
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`j`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods.init(true, false, true, false, false, false, inputpkg.SideInfo{}))
	}, inputpkg.ActionWriteScreenFile{ value: inputpkg.WriteScreen{ action: .open, emit: .plain } })

	// Expand selection.
	selection_keys := [inputpkg.Key.arrow_left, .arrow_right, .arrow_up, .arrow_down, .page_up,
		.page_down, .home, .end]
	selection_actions := [inputpkg.AdjustSelection.left, .right, .up, .down, .page_up, .page_down,
		.home, .end_]
	for i, key in selection_keys {
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: key }
			mods: inputpkg.Mods.init(true, false, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionAdjustSelection{ value: selection_actions[i] }, inputpkg.Flags.init(true, false, false, true))
	}

	// Tabs common to all platforms.
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyPhysical{ key: .tab }
		mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
	}, inputpkg.ActionPreviousTab{})
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyPhysical{ key: .tab }
		mods: inputpkg.Mods.init(false, true, false, false, false, false, inputpkg.SideInfo{})
	}, inputpkg.ActionNextTab{})

	$if !macos {
		// Non-Darwin windowing.
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`n`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNewWindow{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`w`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionCloseSurface{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`q`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionQuit{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .f4 }
			mods: inputpkg.Mods.init(false, false, true, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionCloseWindow{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`t`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNewTab{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`w`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionCloseTab{ value: .this })
		for item in [
			[inputpkg.Key.arrow_left, inputpkg.Key.arrow_right]!,
			[inputpkg.Key.page_up, inputpkg.Key.page_down]!,
		] {
			mods := if item[0] == .page_up {
				inputpkg.Mods.init(false, true, false, false, false, false, inputpkg.SideInfo{})
			} else {
				inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
			}
			k.set.put_flags(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: item[0] }
				mods: mods
			}, inputpkg.ActionPreviousTab{}, inputpkg.Flags.init(true, false, false, true))
			k.set.put_flags(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: item[1] }
				mods: mods
			}, inputpkg.ActionNextTab{}, inputpkg.Flags.init(true, false, false, true))
		}
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`o`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNewSplit{ value: .right })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`e`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNewSplit{ value: .down })
		for direction, rune_ in [inputpkg.SplitFocusDirection.previous, .next] {
			key := if direction == 0 { `[` } else { `]` }
			k.set.put_flags(inputpkg.Trigger{
				key: inputpkg.TriggerKeyUnicode{ codepoint: u32(key) }
				mods: inputpkg.Mods.init(false, true, false, true, false, false, inputpkg.SideInfo{})
			}, inputpkg.ActionGotoSplit{ value: rune_ }, inputpkg.Flags.init(true, false, false, true))
		}
		focus_keys := [inputpkg.Key.arrow_up, .arrow_down, .arrow_left, .arrow_right]
		focus_dirs := [inputpkg.SplitFocusDirection.up, .down, .left, .right]
		for i, key in focus_keys {
			k.set.put_flags(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: key }
				mods: inputpkg.Mods.init(false, true, true, false, false, false, inputpkg.SideInfo{})
			}, inputpkg.ActionGotoSplit{ value: focus_dirs[i] }, inputpkg.Flags.init(true, false, false, true))
		}
		resize_dirs := [inputpkg.SplitResizeDirection.up, .down, .left, .right]
		for i, key in focus_keys {
			k.set.put_flags(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: key }
				mods: inputpkg.Mods.init(true, true, false, true, false, false, inputpkg.SideInfo{})
			}, inputpkg.ActionResizeSplit{ value: inputpkg.SplitResizeParameter{ direction: resize_dirs[i], amount: 10 } }, inputpkg.Flags.init(true, false, false, true))
		}
		viewport_keys := [inputpkg.Key.home, .end, .page_up, .page_down]
		viewport_actions := [inputpkg.Action(inputpkg.ActionScrollToTop{}),
			inputpkg.ActionScrollToBottom{}, inputpkg.ActionScrollPageUp{},
			inputpkg.ActionScrollPageDown{}]
		for i, key in viewport_keys {
			k.set.put(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: key }
				mods: inputpkg.Mods.init(true, false, false, false, false, false, inputpkg.SideInfo{})
			}, viewport_actions[i])
		}
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .page_up }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionJumpToPrompt{ value: -1 })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .page_down }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionJumpToPrompt{ value: 1 })
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`f`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionStartSearch{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .escape }
		}, inputpkg.ActionEndSearch{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`i`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionInspector{ value: .toggle })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`a`) }
			mods: inputpkg.Mods.init(true, true, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionSelectAll{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .insert }
			mods: inputpkg.Mods.init(true, false, false, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionPasteFromSelection{})
	}

	// Cmd/Alt+N selects tab N. Register both physical and Unicode forms so
	// layouts such as AZERTY retain the shortcut.
	index_mods := $if macos { inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{}) } $else { inputpkg.Mods.init(false, false, true, false, false, false, inputpkg.SideInfo{}) }
	digit_keys := [inputpkg.Key.digit_1, .digit_2, .digit_3, .digit_4, .digit_5, .digit_6, .digit_7,
		.digit_8]
	for i, key in digit_keys {
		performable := $if macos { false } $else { true }
		flags := inputpkg.Flags.init(true, false, false, performable)
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: key }
			mods: index_mods
		}, inputpkg.ActionGotoTab{ value: uint(u64(i + 1)) }, flags)
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`1`) + u32(i) }
			mods: index_mods
		}, inputpkg.ActionGotoTab{ value: uint(u64(i + 1)) }, flags)
	}
	last_tab_performable := $if macos { false } $else { true }
	k.set.put_flags(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`9`) }
		mods: index_mods
	}, inputpkg.ActionLastTab{}, inputpkg.Flags.init(true, false, false, last_tab_performable))

	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyPhysical{ key: .enter }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods{})
	}, inputpkg.ActionToggleFullscreen{})
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyPhysical{ key: .enter }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods.init(true, false, false, false, false, false, inputpkg.SideInfo{}))
	}, inputpkg.ActionToggleSplitZoom{})
	k.set.put(inputpkg.Trigger{
		key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`p`) }
		mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods.init(true, false, false, false, false, false, inputpkg.SideInfo{}))
	}, inputpkg.ActionToggleCommandPalette{})

	$if macos {
		// Darwin application and editing bindings.
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`q`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionQuit{})
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`k`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionClearScreen{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`a`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionSelectAll{})
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`t`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionUndo{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`z`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionUndo{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`z`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionRedo{}, inputpkg.Flags.init(true, false, false, true))

		viewport_keys := [inputpkg.Key.home, .end, .page_up, .page_down]
		viewport_actions := [inputpkg.Action(inputpkg.ActionScrollToTop{}),
			inputpkg.ActionScrollToBottom{}, inputpkg.ActionScrollPageUp{},
			inputpkg.ActionScrollPageDown{}]
		for i, key in viewport_keys {
			k.set.put(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: key }
				mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
			}, viewport_actions[i])
		}
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`j`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionScrollToSelection{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_up }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionJumpToPrompt{ value: -1 })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_down }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionJumpToPrompt{ value: 1 })

		window_keys := [u32(`n`), u32(`w`), u32(`t`)]
		window_actions := [inputpkg.Action(inputpkg.ActionNewWindow{}),
			inputpkg.ActionCloseSurface{}, inputpkg.ActionNewTab{}]
		for i, key in window_keys {
			k.set.put(inputpkg.Trigger{
				key: inputpkg.TriggerKeyUnicode{ codepoint: key }
				mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
			}, window_actions[i])
		}
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`w`) }
			mods: inputpkg.Mods.init(false, false, true, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionCloseTab{ value: .this })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`w`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionCloseWindow{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`w`) }
			mods: inputpkg.Mods.init(true, false, true, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionCloseAllWindows{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`[`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionPreviousTab{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`]`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNextTab{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`d`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNewSplit{ value: .right })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`d`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNewSplit{ value: .down })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`[`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionGotoSplit{ value: .previous })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`]`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionGotoSplit{ value: .next })
		arrow_keys := [inputpkg.Key.arrow_up, .arrow_down, .arrow_left, .arrow_right]
		focus_dirs := [inputpkg.SplitFocusDirection.up, .down, .left, .right]
		resize_dirs := [inputpkg.SplitResizeDirection.up, .down, .left, .right]
		for i, key in arrow_keys {
			k.set.put(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: key }
				mods: inputpkg.Mods.init(false, false, true, true, false, false, inputpkg.SideInfo{})
			}, inputpkg.ActionGotoSplit{ value: focus_dirs[i] })
			k.set.put(inputpkg.Trigger{
				key: inputpkg.TriggerKeyPhysical{ key: key }
				mods: inputpkg.Mods.init(false, true, false, true, false, false, inputpkg.SideInfo{})
			}, inputpkg.ActionResizeSplit{ value: inputpkg.SplitResizeParameter{ direction: resize_dirs[i], amount: 10 } })
		}
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`=`) }
			mods: inputpkg.Mods.init(false, true, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionEqualizeSplits{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_up }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionJumpToPrompt{ value: -1 })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_down }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionJumpToPrompt{ value: 1 })

		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`f`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionStartSearch{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`e`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionSearchSelection{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`f`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionEndSearch{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .escape }
		}, inputpkg.ActionEndSearch{}, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`g`) }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNavigateSearch{ value: .next }, inputpkg.Flags.init(true, false, false, true))
		k.set.put_flags(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`g`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionNavigateSearch{ value: .previous }, inputpkg.Flags.init(true, false, false, true))
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`i`) }
			mods: inputpkg.Mods.init(false, false, true, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionInspector{ value: .toggle })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`f`) }
			mods: inputpkg.Mods.init(false, true, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionToggleFullscreen{})
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyUnicode{ codepoint: u32(`v`) }
			mods: inputpkg.Mods.init(true, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionPasteFromSelection{})

		// Natural text editing keys use legacy sequences on macOS.
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_right }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionText{ value: '\x05' })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_left }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionText{ value: '\x01' })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .backspace }
			mods: inputpkg.Mods.init(false, false, false, true, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionText{ value: '\x15' })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_left }
			mods: inputpkg.Mods.init(false, false, true, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionEsc{ value: 'b' })
		k.set.put(inputpkg.Trigger{
			key: inputpkg.TriggerKeyPhysical{ key: .arrow_right }
			mods: inputpkg.Mods.init(false, false, true, false, false, false, inputpkg.SideInfo{})
		}, inputpkg.ActionEsc{ value: 'f' })
	}
}

// ConfigChangeResult preserves Witty's error-union-of-optional return in V,
// which cannot directly express !?Config. value == none means the conditional
// change is irrelevant; replay and finalization errors are still returned.
pub struct ConfigChangeResult {
pub:
	value ?Config
}

// change_conditional_state returns a new Config with the given conditional
// state applied, or a result containing none if the change is irrelevant.
// This doesn't re-read referenced configuration files: it replays the retained
// steps and finalizes the rebuilt configuration under the new state.
pub fn (c Config) change_conditional_state(state ConditionalState) !ConfigChangeResult {
	if (!c.conditional_set['theme'] || c.conditional_state.theme == state.theme)
		&& (!c.conditional_set['os'] || c.conditional_state.os == state.os) {
		return ConfigChangeResult{}
	}
	mut rebuilt := c.clone_empty()
	rebuilt.conditional_state = state
	replay_steps_into(mut rebuilt, c.replay_steps)
	rebuilt.finalize()!
	return ConfigChangeResult{
		value: rebuilt
	}
}

pub fn (mut c Config) deinit() {
	// Witty releases the arena that owns all configuration allocations and
	// then invalidates the struct. V's GC owns those allocations, so replacing
	// the value drops every retained reference and leaves a valid empty config.
	c = Config{}
}

// default is Config.default. V's garbage collector replaces the explicit
// arena allocator used by the source.
pub fn Config.default() Config {
	return Config.default_config()
}

// shallow_clone copies the Config value while retaining references to its
// existing collection storage. It is intended only for short-lived edits,
// matching Config.shallowClone.
pub fn (c Config) shallow_clone() Config {
	return c
}

// clone_empty retains conditional metadata but resets all public values to
// their defaults.
pub fn (c Config) clone_empty() Config {
	mut result := Config.default_config()
	result.conditional_state = c.conditional_state
	return result
}

// clone creates a deep copy of the config. Slices and nested collections are
// cloned so that mutating the copy does not affect the original.
pub fn (c Config) clone() Config {
	mut copy := c
	copy.font_family = c.font_family.clone()
	copy.font_family_bold = c.font_family_bold.clone()
	copy.font_family_italic = c.font_family_italic.clone()
	copy.font_family_bold_italic = c.font_family_bold_italic.clone()
	copy.font_feature = c.font_feature.clone()
	copy.font_variation = c.font_variation.clone()
	copy.font_variation_bold = c.font_variation_bold.clone()
	copy.font_variation_italic = c.font_variation_italic.clone()
	copy.font_variation_bold_italic = c.font_variation_bold_italic.clone()
	copy.font_codepoint_map = c.font_codepoint_map.clone()
	copy.custom_shader = c.custom_shader.clone() or { RepeatablePath{} }
	copy.config_file = c.config_file.clone() or { RepeatablePath{} }
	copy.gtk_custom_css = c.gtk_custom_css.clone() or { RepeatablePath{} }
	copy.input = c.input.clone()
	if colors := c.macos_icon_screen_color {
		copy.macos_icon_screen_color = colors.clone()
	}
	copy.env = c.env.clone()
	copy.diagnostics = c.diagnostics.clone()
	copy.keybind = c.keybind.clone()
	copy.command_palette_entry = c.command_palette_entry.clone()
	if theme := c.theme {
		copy.theme = theme.clone()
	}
	copy.key_remap = c.key_remap.clone()
	copy.selection_word_chars = c.selection_word_chars.clone()
	copy.clipboard_codepoint_map = c.clipboard_codepoint_map.clone()
	copy.link = c.link.clone()
	copy.conditional_set = c.conditional_set.clone()
	copy.replay_steps = clone_replay_steps(c.replay_steps)
	// C API string caches contain pointers into the source configuration and must
	// never be shared by a clone. They are rebuilt lazily on first access.
	copy.capi_strings = map[string]string{}
	if cmd := c.command {
		copy.command = cmd.clone()
	}
	if cmd := c.initial_command {
		copy.initial_command = cmd.clone()
	}
	return copy
}

// ConfigChangeIterator yields each changed public key in Config declaration
// order, matching Config.ChangeIterator.
pub struct ConfigChangeIterator {
mut:
	old   &Config = unsafe { nil }
	new   &Config = unsafe { nil }
	index int
}

pub fn (old &Config) change_iterator(new &Config) ConfigChangeIterator {
	return unsafe {
		ConfigChangeIterator{
			old: old
			new: new
		}
	}
}

pub fn (mut it ConfigChangeIterator) next() ?string {
	for it.index < config_keys.len {
		key := config_keys[it.index]
		it.index++
		if it.old.changed(it.new, key) {
			return key
		}
	}
	return none
}

// ============================================================
// Types used by renderer DerivedConfig
// ============================================================

// FontShapingBreak controls optional shaping-run boundaries.
pub struct FontShapingBreak {
	value u8 = 0x01
}

pub fn FontShapingBreak.init(cursor bool) FontShapingBreak {
	return FontShapingBreak{
		value: if cursor { u8(0x01) } else { u8(0) }
	}
}

pub fn (config FontShapingBreak) cursor() bool {
	return config.value & 0x01 != 0
}

pub fn (config FontShapingBreak) int_val() u8 {
	return config.value
}

pub fn (config FontShapingBreak) format_entry() string {
	return if config.cursor() { 'cursor' } else { 'no-cursor' }
}

pub struct TerminalColorCellBackground {}

pub struct TerminalColorCellForeground {}

pub struct TerminalColorColor {
pub:
	color ColorRGB
}

// TerminalColor is Config.TerminalColor. Only the explicit-color arm carries
// an RGB value; the two cell-relative arms are payload-free.
pub type TerminalColor = TerminalColorCellBackground | TerminalColorCellForeground | TerminalColorColor

pub fn TerminalColor.parse_cli(input_ ?string) !TerminalColor {
	input := input_ or { return perr(ParseError.value_required) }
	if input == 'cell-foreground' {
		return TerminalColorCellForeground{}
	}
	if input == 'cell-background' {
		return TerminalColorCellBackground{}
	}
	return TerminalColorColor{
		color: ColorRGB.parse_cli(input)!
	}
}

pub fn (c TerminalColor) to_terminal_rgb() ?terminal.RGB {
	return match c {
		TerminalColorColor { c.color.to_terminal_rgb() }
		TerminalColorCellForeground, TerminalColorCellBackground { none }
	}
}

pub fn (c TerminalColor) format_entry() string {
	return match c {
		TerminalColorColor { c.color.format_entry() }
		TerminalColorCellForeground { 'cell-foreground' }
		TerminalColorCellBackground { 'cell-background' }
	}
}

// WindowPaddingBalance controls where to place space left over around the grid.
pub enum WindowPaddingBalance as u8 {
	false_
	true_
	equal
}

// WindowPaddingColor determines how the padding area is colored.
pub enum WindowPaddingColor as u8 {
	background
	extend
	extend_always
}

// WindowColorspace for color rendering.
pub enum WindowColorspace as u8 {
	srgb
	display_p3
}

// AlphaBlending mode for the renderer.
pub enum AlphaBlending as u8 {
	native
	linear
	linear_corrected
}

// Returns true if this blending mode uses linear blending.
pub fn (b AlphaBlending) is_linear() bool {
	return b == .linear || b == .linear_corrected
}

pub struct BackgroundBlurFalse {}

pub struct BackgroundBlurMacosGlassClear {}

pub struct BackgroundBlurMacosGlassRegular {}

pub struct BackgroundBlurRadius {
pub:
	radius u8
}

pub struct BackgroundBlurTrue {}

// BackgroundBlur is Config.BackgroundBlur. Only the radius arm carries data.
pub type BackgroundBlur = BackgroundBlurFalse | BackgroundBlurMacosGlassClear | BackgroundBlurMacosGlassRegular | BackgroundBlurRadius | BackgroundBlurTrue

// parse_cli translates BackgroundBlur.parseCLI. The receiver is only changed
// after a value has parsed successfully, as with the tagged union assignment in
// the source implementation.
pub fn (mut b BackgroundBlur) parse_cli(input ?string) ! {
	b = background_blur_parse_cli(input)!
}

pub fn (b BackgroundBlur) enabled() bool {
	return match b {
		BackgroundBlurFalse { false }
		BackgroundBlurTrue { true }
		BackgroundBlurRadius { b.radius > 0 }
		BackgroundBlurMacosGlassRegular, BackgroundBlurMacosGlassClear { true }
	}
}

// cval returns the integer representation consumed by the macOS private
// background-blur API. The negative values select the two macOS glass modes.
pub fn (b BackgroundBlur) cval() i16 {
	return match b {
		BackgroundBlurFalse { i16(0) }
		BackgroundBlurTrue { i16(20) }
		BackgroundBlurRadius { i16(b.radius) }
		BackgroundBlurMacosGlassRegular { i16(-1) }
		BackgroundBlurMacosGlassClear { i16(-2) }
	}
}

pub fn (b BackgroundBlur) format_entry() string {
	return match b {
		BackgroundBlurFalse { 'false' }
		BackgroundBlurTrue { 'true' }
		BackgroundBlurRadius { b.radius.str() }
		BackgroundBlurMacosGlassRegular { 'macos-glass-regular' }
		BackgroundBlurMacosGlassClear { 'macos-glass-clear' }
	}
}

// BackgroundImagePosition for the background image.
pub enum BackgroundImagePosition as u8 {
	top_left
	top_center
	top_right
	center_left
	center_center
	center_right
	bottom_left
	bottom_center
	bottom_right
	center
}

// BackgroundImageFit for the background image.
pub enum BackgroundImageFit as u8 {
	contain
	cover
	stretch
	none_
}

pub struct BoldColorBright {}

pub struct BoldColorColor {
pub:
	color ColorRGB
}

// BoldColor is Config.BoldColor. Only the color arm owns an RGB value.
pub type BoldColor = BoldColorBright | BoldColorColor

pub fn BoldColor.parse_cli(input ?string) !BoldColor {
	value := input or { return perr(ParseError.value_required) }
	if value == 'bright' {
		return BoldColorBright{}
	}
	return BoldColorColor{
		color: ColorRGB.parse_cli(value)!
	}
}

pub fn (b BoldColor) format_entry() string {
	return match b {
		BoldColorBright { 'bright' }
		BoldColorColor { b.color.format_entry() }
	}
}

// RepeatablePath holds a list of file paths.
pub struct RepeatablePath {
pub mut:
	items []Path
}

pub fn (a RepeatablePath) equal(b RepeatablePath) bool {
	if a.items.len != b.items.len {
		return false
	}
	for i, item in a.items {
		if !item.equal(b.items[i]) {
			return false
		}
	}
	return true
}

pub fn (p RepeatablePath) clone() !RepeatablePath {
	mut items := []Path{cap: p.items.len}
	for item in p.items {
		items << item.clone()!
	}
	return RepeatablePath{
		items: items
	}
}

// expand resolves every relative entry against an absolute configuration-file
// directory. Existing absolute paths and empty values are unchanged.
pub fn (mut p RepeatablePath) expand(base string, mut diagnostics []Diagnostic) ! {
	for mut item in p.items {
		item.expand(base, mut diagnostics)!
	}
}

// parse_cli appends one path, clears the list for an empty value, and ignores
// values that become empty after removing the optional marker or quotes.
pub fn (mut p RepeatablePath) parse_cli(input ?string) ! {
	maybe_item := Path.parse(input)!
	item := maybe_item.value or {
		p.items.clear()
		return
	}
	if item.len() > 0 {
		p.items << item
	}
}

// format_entry returns one formatter value per path. An empty collection
// emits one empty value so the setting can be reset in generated config.
pub fn (p RepeatablePath) format_entry() []string {
	if p.items.len == 0 {
		return ['']
	}
	return p.items.map(it.format_entry())
}

pub struct ReadableIORaw {
pub:
	value string
}

pub struct ReadableIOPath {
pub:
	value string
}

// ReadableIO is a startup input source. Each variant owns its string payload,
// which retains Zig escapes so configuration formatting can recreate the
// original value.
pub type ReadableIO = ReadableIOPath | ReadableIORaw

// parse_zig_string decodes the escape sequences accepted by Zig string
// literals. The output never contains more bytes than the input.
pub fn parse_zig_string(value string) !string {
	mut result := []u8{cap: value.len}
	mut i := 0
	for i < value.len {
		if value[i] != `\\` {
			result << value[i]
			i++
			continue
		}

		i++
		if i >= value.len {
			return error('invalid string')
		}
		match value[i] {
			`n` { result << `\n` }
			`r` { result << `\r` }
			`t` { result << `\t` }
			`\\` { result << `\\` }
			`'` { result << `'` }
			`"` { result << `"` }
			`x` {
				if i + 2 >= value.len {
					return error('invalid string')
				}
				hi := zig_hex_digit(value[i + 1]) or { return error('invalid string') }
				lo := zig_hex_digit(value[i + 2]) or { return error('invalid string') }
				result << u8((hi << 4) | lo)
				i += 2
			}
			`u` {
				if i + 1 >= value.len || value[i + 1] != `{` {
					return error('invalid string')
				}
				i += 2
				mut codepoint := u32(0)
				mut digits := 0
				for i < value.len && value[i] != `}` {
					nibble := zig_hex_digit(value[i]) or { return error('invalid string') }
					if codepoint > 0x10ffff / 16
						|| (codepoint == 0x10ffff / 16 && nibble > 0x10ffff % 16) {
						return error('invalid string')
					}
					codepoint = (codepoint << 4) | nibble
					digits++
					i++
				}
				if digits == 0 || i >= value.len || codepoint > 0x10ffff
					|| (codepoint >= 0xd800 && codepoint <= 0xdfff) {
					return error('invalid string')
				}
				result << rune(codepoint).str().bytes()
			}
			else {
				return error('invalid string')
			}
		}
		i++
	}
	return result.bytestr()
}

fn zig_hex_digit(value u8) ?u32 {
	return match value {
		`0`...`9` { u32(value - `0`) }
		`a`...`f` { u32(value - `a` + 10) }
		`A`...`F` { u32(value - `A` + 10) }
		else { none }
	}
}

pub fn ReadableIO.parse_cli(input ?string) !ReadableIO {
	value := input or { return error('value required') }
	if value.len == 0 {
		return error('value required')
	}

	// Validate the complete input before parsing the tag. Parsed values are
	// retained below so formatting is lossless.
	parse_zig_string(value)!
	colon := value.index_u8(`:`)
	tag_end := if colon < 0 { value.len } else { colon }
	tag := value[..tag_end].trim(' \t')
	payload := if colon < 0 { '' } else { value[colon + 1..].clone() }
	if tag == 'raw' {
		return ReadableIORaw{ value: payload }
	}
	if tag == 'path' {
		return ReadableIOPath{ value: payload }
	}
	return ReadableIORaw{ value: value.clone() }
}

pub fn (r ReadableIO) clone() ReadableIO {
	return match r {
		ReadableIORaw { ReadableIORaw{ value: r.value.clone() } }
		ReadableIOPath { ReadableIOPath{ value: r.value.clone() } }
	}
}

pub fn (r ReadableIO) clone_parsed() !ReadableIO {
	return match r {
		ReadableIORaw { ReadableIORaw{ value: parse_zig_string(r.value)! } }
		ReadableIOPath { ReadableIOPath{ value: parse_zig_string(r.value)! } }
	}
}

pub fn (r ReadableIO) equal(other ReadableIO) bool {
	match r {
		ReadableIORaw {
			if other is ReadableIORaw {
				return r.value == other.value
			}
		}
		ReadableIOPath {
			if other is ReadableIOPath {
				return r.value == other.value
			}
		}
	}
	return false
}

pub fn (r ReadableIO) format_entry() string {
	return match r {
		ReadableIORaw { 'raw:${r.value}' }
		ReadableIOPath { 'path:${r.value}' }
	}
}

pub struct RepeatableReadableIO {
pub mut:
	items []ReadableIO
}

pub fn (mut r RepeatableReadableIO) parse_cli(input ?string) ! {
	value := input or { return error('value required') }
	if value.len == 0 {
		r.items.clear()
		return
	}
	r.items << ReadableIO.parse_cli(value)!
}

pub fn (r RepeatableReadableIO) clone() RepeatableReadableIO {
	return RepeatableReadableIO{
		items: r.items.map(it.clone())
	}
}

pub fn (r RepeatableReadableIO) clone_parsed() !RepeatableReadableIO {
	mut items := []ReadableIO{cap: r.items.len}
	for item in r.items {
		items << item.clone_parsed()!
	}
	return RepeatableReadableIO{
		items: items
	}
}

pub fn (r RepeatableReadableIO) equal(other RepeatableReadableIO) bool {
	if r.items.len != other.items.len {
		return false
	}
	for i, item in r.items {
		if !item.equal(other.items[i]) {
			return false
		}
	}
	return true
}

// format_entry returns one formatter value per readable input. An empty list
// emits one empty value so generated configuration can reset the setting.
pub fn (r RepeatableReadableIO) format_entry() []string {
	if r.items.len == 0 {
		return ['']
	}
	return r.items.map(it.format_entry())
}

// clone_commands deep-copies commands. V 0.5.2 master types
// `.map(it.clone())` on them as `[]input.Command`, which it then refuses to
// assign to the `[]inputpkg.Command` field.
fn clone_commands(items []inputpkg.Command) []inputpkg.Command {
	mut result := []inputpkg.Command{cap: items.len}
	for item in items {
		result << item.clone()
	}
	return result
}

// RepeatableCommand is the configured list of command-palette entries.
pub struct RepeatableCommand {
pub mut:
	items   []inputpkg.Command
	items_c []inputpkg.CCommand
}

// init installs Witty's built-in command palette entries.
pub fn (mut r RepeatableCommand) init() {
	r.items = []inputpkg.Command{cap: inputpkg.command_defaults.len}
	for item in inputpkg.command_defaults {
		r.items << item.clone()
	}
	r.items_c = inputpkg.command_defaults_c.clone()
}

// parse_cli appends a title/action/description record. An empty value clears
// the complete list, matching repeatable configuration semantics.
pub fn (mut r RepeatableCommand) parse_cli(input ?string) ! {
	input_value := input or { '' }
	if input_value.len == 0 {
		r.items.clear()
		r.items_c.clear()
		return
	}

	mut title := ''
	mut description := ''
	mut action_text := ''
	mut has_title := false
	mut has_action := false
	mut splitter := comma_splitter.CommaSplitter.init(input_value)
	for {
		entry := splitter.next() or {
			if splitter.last_error.len > 0 {
				return error('invalid value')
			}
			break
		}
		colon := entry.index_u8(`:`)
		if colon < 0 {
			return error('invalid value')
		}
		key := entry[..colon].trim(' \t')
		mut value := entry[colon + 1..].trim(' \t')
		if value.len >= 2 && value[0] == `"` && value[value.len - 1] == `"` {
			value = cli_args.decode_quoted_value(value) or { return error('invalid value') }
		}
		match key {
			'title' {
				title = value
				has_title = true
			}
			'description' {
				description = value
			}
			'action' {
				action_text = value
				has_action = true
			}
			else {
				return error('invalid value')
			}
		}
	}
	if !has_title || !has_action {
		return error('invalid value')
	}
	action := inputpkg.Action.parse(action_text) or { return error('invalid value') }
	command := inputpkg.Command{
		action: action
		title: title
		description: description
	}
	r.items << command
	r.items_c << command.cval()
}

pub fn (r RepeatableCommand) clone() RepeatableCommand {
	return RepeatableCommand{
		items: clone_commands(r.items)
		items_c: r.items_c.clone()
	}
}

pub fn (r RepeatableCommand) equal(other RepeatableCommand) bool {
	if r.items.len != other.items.len {
		return false
	}
	for i, item in r.items {
		if !item.equal(other.items[i]) {
			return false
		}
	}
	return true
}

@[markused]
pub fn (r RepeatableCommand) cval() CConfigCommandList {
	return CConfigCommandList{
		commands: if r.items_c.len == 0 {
			unsafe { nil }
		} else {
			unsafe { &inputpkg.CCommand(r.items_c.data) }
		}
		len: uint(r.items_c.len)
	}
}

pub fn (r RepeatableCommand) format_entry() []string {
	if r.items.len == 0 {
		return ['']
	}
	mut result := []string{cap: r.items.len}
	for item in r.items {
		mut entry := 'title:"${inputpkg.zig_escape(item.title)}"'
		if item.description.len > 0 {
			entry += ',description:"${inputpkg.zig_escape(item.description)}"'
		}
		entry += ',action:"${item.action.format()}"'
		result << entry
	}
	return result
}

// Path is a tagged config file path. Optional paths may be absent without
// producing a diagnostic; required paths may not.
pub struct PathOptional {
pub mut:
	path string
}

pub struct PathRequired {
pub mut:
	path string
}

pub type Path = PathOptional | PathRequired

pub fn (p Path) len() int {
	return match p {
		PathOptional { p.path.len }
		PathRequired { p.path.len }
	}
}

// PathParseResult preserves Witty's error-union-of-optional return in V,
// which cannot directly express !?Path. value == none is the empty input.
pub struct PathParseResult {
pub:
	value ?Path
}

// parse translates config.Path.parse. A leading question mark makes the path
// optional, and one pair of surrounding quotes is removed.
pub fn Path.parse(input ?string) !PathParseResult {
	mut value := input or { return perr(ParseError.value_required) }
	if value.len == 0 {
		return PathParseResult{}
	}
	optional := value[0] == `?`
	if optional {
		value = value[1..]
	}
	if value.len >= 2 && value[0] == `"` && value[value.len - 1] == `"` {
		value = value[1..value.len - 1]
	}
	return PathParseResult{
		value: if optional {
			Path(PathOptional{
				path: value
			})
		} else {
			Path(PathRequired{
				path: value
			})
		}
	}
}

// parse_cli overwrites the path only when parsing produces a non-empty path.
// Values that become empty after removing `?` or surrounding quotes are
// ignored, matching Path.parseCLI in the source.
pub fn (mut p Path) parse_cli(input ?string) ! {
	assert input != none
	maybe_parsed := Path.parse(input)!
	parsed := maybe_parsed.value or { return }
	if parsed.len() == 0 {
		return
	}
	p = parsed
}

pub fn (a Path) equal(b Path) bool {
	return match a {
		PathOptional {
			b is PathOptional && a.path == b.path
		}
		PathRequired {
			b is PathRequired && a.path == b.path
		}
	}
}

pub fn (p Path) clone() !Path {
	return match p {
		PathOptional {
			Path(PathOptional{
				path: p.path
			})
		}
		PathRequired {
			Path(PathRequired{
				path: p.path
			})
		}
	}
}

// format_entry is the value passed to Config's entry formatter.
pub fn (p Path) format_entry() string {
	return match p {
		PathOptional { '?${p.path}' }
		PathRequired { p.path }
	}
}

// expand resolves this path exactly when a configuration reader finishes a
// file, so paths in nested files remain relative to the file that declared
// them.
pub fn (mut p Path) expand(base string, mut diagnostics []Diagnostic) ! {
	assert os.is_abs_path(base)
	path := match p {
		PathOptional { p.path }
		PathRequired { p.path }
	}
	if path.len == 0 || os.is_abs_path(path) {
		return
	}
	if path.starts_with('~/') {
		$if !windows {
			original := path
			expanded := internal_os.expand_home(original) or {
				p = PathRequired{
					path: ''
				}
				diagnostics << Diagnostic{
					message: 'error expanding home directory for path ${original}: ${err}'
				}
				return
			}
			match mut p {
				PathOptional { p.path = expanded }
				PathRequired { p.path = expanded }
			}
			return
		}
	}
	base_stat := os.stat(base)!
	if base_stat.get_filetype() != .directory {
		return error_with_code('not a directory', C.ENOTDIR)
	}
	joined := os.join_path(base, path)
	// Witty asks the directory for a real path first, preserving canonical
	// symlink resolution for existing entries. A missing entry falls back to
	// lexical path resolution so configuration may name files created later.
	_ := os.stat(joined) or {
		if err.code() == C.ENOENT {
			resolved := os.norm_path(joined)
			match mut p {
				PathOptional { p.path = resolved }
				PathRequired { p.path = resolved }
			}
			return
		}
		original := path
		p = PathRequired{
			path: ''
		}
		diagnostics << Diagnostic{
			message: 'error resolving file path ${original}: ${err}'
		}
		return
	}
	resolved := os.real_path(joined)
	match mut p {
		PathOptional { p.path = resolved }
		PathRequired { p.path = resolved }
	}
}

// RepeatableLink is Config.RepeatableLink. Custom link parsing is deliberately
// unimplemented in the pinned source.
pub struct RepeatableLink {
pub mut:
	links []inputpkg.Link
}

pub fn (mut r RepeatableLink) parse_cli(input ?string) ! {
	_ = input
	return error('not implemented')
}

pub fn (r RepeatableLink) clone() RepeatableLink {
	return RepeatableLink{
		links: r.links.map(it.clone())
	}
}

pub fn (r RepeatableLink) equal(other RepeatableLink) bool {
	if r.links.len != other.links.len {
		return false
	}
	for i, link in r.links {
		if !link.equal(other.links[i]) {
			return false
		}
	}
	return true
}

// format_entry intentionally produces no values because custom links cannot
// be configured yet. This differs from an empty repeatable, which emits a reset.
pub fn (r RepeatableLink) format_entry() []string {
	_ = r
	return []string{}
}

// SelectionWordChars stores parsed word-boundary codepoints. U+0000 is
// always the first boundary, matching Config.zig.
pub struct SelectionWordChars {
pub mut:
	codepoints []u32
}

pub fn SelectionWordChars.defaults() SelectionWordChars {
	return SelectionWordChars{
		codepoints: [u32(0), u32(` `), u32(`\t`), u32(`'`), u32(`"`), 0x2502, u32('`'[0]), u32(`|`),
			u32(`:`), u32(`;`), u32(`,`), u32(`(`), u32(`)`), u32(`[`), u32(`]`), u32(`{`), u32(`}`),
			u32(`<`), u32(`>`), u32(`$`)]
	}
}

pub fn (mut s SelectionWordChars) parse_cli(value ?string) ! {
	input_value := value or { return perr(ParseError.value_required) }
	if !validate.utf8_string(input_value) {
		// Witty retains only the mandatory null boundary for invalid UTF-8.
		s.codepoints = [u32(0)]
		return
	}
	mut result := []u32{cap: input_value.len + 1}
	result << u32(0)
	for cp in input_value.runes() {
		result << u32(cp)
	}
	s.codepoints = result
}

pub fn (s SelectionWordChars) clone() SelectionWordChars {
	return SelectionWordChars{
		codepoints: s.codepoints.clone()
	}
}

pub fn (s SelectionWordChars) equal(other SelectionWordChars) bool {
	return s.codepoints == other.codepoints
}

pub fn (s SelectionWordChars) format_entry() string {
	mut result := ''
	if s.codepoints.len <= 1 {
		return result
	}
	for codepoint in s.codepoints[1..] {
		value := rune(codepoint)
		length := value.length_in_bytes()
		if length < 0 {
			continue
		}
		if result.len + length > 4096 {
			break
		}
		result += value.str()
	}
	return result
}

pub type FontStyleKind = fontstyle.Kind

pub type FontStyle = fontstyle.FontStyle

pub fn font_style_parse_cli(input ?string) !FontStyle {
	return fontstyle.FontStyle.parse(input)
}

// RepeatableFontVariation stores OpenType variation axes in declaration order.
pub struct RepeatableFontVariation {
pub mut:
	list []font.Variation
}

pub fn (mut r RepeatableFontVariation) parse_cli(input ?string) ! {
	value := input or { return perr(ParseError.value_required) }
	eq_idx := value.index_u8(`=`)
	if eq_idx < 0 {
		return perr(ParseError.invalid_value)
	}
	id := value[..eq_idx].trim(' \t')
	axis_value := value[eq_idx + 1..].trim(' \t')
	if id.len != 4 {
		return perr(ParseError.invalid_value)
	}
	parsed := zig_fmt.parse_f64(axis_value) or { return perr(ParseError.invalid_value) }
	r.list << font.Variation{
		id: font.VariationId.init(id)
		value: parsed
	}
}

pub fn (r RepeatableFontVariation) clone() RepeatableFontVariation {
	return RepeatableFontVariation{
		list: r.list.clone()
	}
}

pub fn (r RepeatableFontVariation) equal(other RepeatableFontVariation) bool {
	return r.list == other.list
}

pub fn (r RepeatableFontVariation) format_entry() []string {
	if r.list.len == 0 {
		return ['']
	}
	return r.list.map('${it.id.str()}=${format_f64(it.value)}')
}

// RepeatableCodepointMap maps one or more Unicode ranges to a named font.
pub struct RepeatableCodepointMap {
pub mut:
	map font.CodepointMap
}

pub fn (mut m RepeatableCodepointMap) parse_cli(input ?string) ! {
	value := input or { return perr(ParseError.value_required) }
	eq_idx := value.index_u8(`=`)
	if eq_idx < 0 {
		return perr(ParseError.invalid_value)
	}
	mut parser := UnicodeRangeParser{
		input: value[..eq_idx].trim(' \t')
	}
	family := value[eq_idx + 1..].trim(' \t')
	for {
		next := parser.next()!
		if next.done {
			break
		}
		range_ := next.range
		m.map.add(font.CodepointMapEntry{
			range: range_
			descriptor: font.Descriptor{
				family: family
				monospace: false
			}
		})
	}
}

pub fn (m RepeatableCodepointMap) clone() RepeatableCodepointMap {
	return RepeatableCodepointMap{
		map: m.map.clone()
	}
}

pub fn (m RepeatableCodepointMap) equal(other RepeatableCodepointMap) bool {
	if m.map.entries.len != other.map.entries.len {
		return false
	}
	for i, entry in m.map.entries {
		other_entry := other.map.entries[i]
		if entry.range != other_entry.range || !optional_string_equal(entry.descriptor.family, other_entry.descriptor.family)
			|| entry.descriptor.monospace != other_entry.descriptor.monospace {
			return false
		}
	}
	return true
}

pub fn (m RepeatableCodepointMap) format_entry() []string {
	if m.map.entries.len == 0 {
		return ['']
	}
	mut result := []string{cap: m.map.entries.len}
	for entry in m.map.entries {
		family := entry.descriptor.family or { '' }
		if entry.range[0] == entry.range[1] {
			result << 'U+${entry.range[0]:04X}=${family}'
		} else {
			result << 'U+${entry.range[0]:04X}-U+${entry.range[1]:04X}=${family}'
		}
	}
	return result
}

fn optional_string_equal(a ?string, b ?string) bool {
	if av := a {
		if bv := b {
			return av == bv
		}
		return false
	}
	return b == none
}

// ClipboardCodepointMap retains formatter entries in insertion order. Lookup
// remains linear because configuration maps are expected to stay very small.
pub struct ClipboardCodepointMap {
pub mut:
	list []terminal.CodepointMap
}

pub fn (mut m ClipboardCodepointMap) deinit() {
	m.list = []
}

pub fn (m ClipboardCodepointMap) clone() ClipboardCodepointMap {
	mut list := []terminal.CodepointMap{cap: m.list.len}
	for entry in m.list {
		replacement := match entry.replacement {
			terminal.CodepointRepl {
				terminal.CodepointReplacement(terminal.CodepointRepl{
					codepoint: entry.replacement.codepoint
				})
			}
			terminal.StringRepl {
				terminal.CodepointReplacement(terminal.StringRepl{
					str: entry.replacement.str.clone()
				})
			}
		}
		list << terminal.CodepointMap{
			range_start: entry.range_start
			range_end: entry.range_end
			replacement: replacement
		}
	}
	return ClipboardCodepointMap{
		list: list
	}
}

// add appends an entry so later conflicting ranges retain source priority.
pub fn (mut m ClipboardCodepointMap) add(entry terminal.CodepointMap) {
	assert entry.range_start <= entry.range_end
	m.list << entry
}

pub fn (m ClipboardCodepointMap) equal(other ClipboardCodepointMap) bool {
	return m.list == other.list
}

// RepeatableClipboardCodepointMap maps Unicode ranges to formatter
// replacements.
pub struct RepeatableClipboardCodepointMap {
pub mut:
	map ClipboardCodepointMap
}

pub fn (mut m RepeatableClipboardCodepointMap) parse_cli(value ?string) ! {
	input_value := value or { return perr(ParseError.value_required) }
	eq_idx := input_value.index_u8(`=`)
	if eq_idx < 0 {
		return perr(ParseError.invalid_value)
	}
	key := input_value[..eq_idx].trim(' \t')
	replacement_value := input_value[eq_idx + 1..].trim(' \t')
	replacement := if replacement_value.starts_with('U+') {
		terminal.CodepointReplacement(terminal.CodepointRepl{
			codepoint: parse_unicode_codepoint(replacement_value)!
		})
	} else {
		if !validate.utf8_string(replacement_value) {
			return perr(ParseError.invalid_value)
		}
		terminal.CodepointReplacement(terminal.StringRepl{
			str: replacement_value
		})
	}
	mut parser := UnicodeRangeParser{
		input: key
	}
	for {
		next := parser.next()!
		if next.done {
			break
		}
		range_ := next.range
		m.map.add(terminal.CodepointMap{
			range_start: range_[0]
			range_end: range_[1]
			replacement: replacement
		})
	}
}

pub fn (m RepeatableClipboardCodepointMap) clone() RepeatableClipboardCodepointMap {
	return RepeatableClipboardCodepointMap{
		map: m.map.clone()
	}
}

pub fn (m RepeatableClipboardCodepointMap) equal(other RepeatableClipboardCodepointMap) bool {
	return m.map.equal(other.map)
}

// format_entry returns the exact values passed to Witty's entry formatter.
pub fn (m RepeatableClipboardCodepointMap) format_entry() []string {
	if m.map.list.len == 0 {
		return ['']
	}
	mut result := []string{cap: m.map.list.len}
	for entry in m.map.list {
		range_text := if entry.range_start == entry.range_end {
			'U+${entry.range_start:04X}'
		} else {
			'U+${entry.range_start:04X}-U+${entry.range_end:04X}'
		}
		replacement := match entry.replacement {
			terminal.CodepointRepl { 'U+${entry.replacement.codepoint:04X}' }
			terminal.StringRepl { entry.replacement.str }
		}
		result << '${range_text}=${replacement}'
	}
	return result
}

struct UnicodeRangeParser {
	input string
mut:
	i int
}

struct UnicodeRangeResult {
	done  bool
	range [2]u32
}

fn (mut p UnicodeRangeParser) next() !UnicodeRangeResult {
	if p.eof() {
		return UnicodeRangeResult{ done: true }
	}
	start := p.parse_codepoint()!
	if p.eof() {
		return UnicodeRangeResult{ range: [start, start]! }
	}
	p.consume_whitespace()
	if p.eof() {
		return UnicodeRangeResult{ range: [start, start]! }
	}
	match p.input[p.i] {
		`,` {
			p.advance()
			p.consume_whitespace()
			if p.eof() {
				return perr(ParseError.invalid_value)
			}
			return UnicodeRangeResult{ range: [start, start]! }
		}
		`-` {
			p.advance()
			p.consume_whitespace()
			if p.eof() {
				return perr(ParseError.invalid_value)
			}
			end := p.parse_codepoint()!
			p.consume_whitespace()
			if !p.eof() && p.input[p.i] != `,` {
				return perr(ParseError.invalid_value)
			}
			p.advance()
			p.consume_whitespace()
			if start > end {
				return perr(ParseError.invalid_value)
			}
			return UnicodeRangeResult{ range: [start, end]! }
		}
		else {
			return perr(ParseError.invalid_value)
		}
	}
}

fn (mut p UnicodeRangeParser) consume_whitespace() {
	for !p.eof() && (p.input[p.i] == ` ` || p.input[p.i] == `\t`) {
		p.advance()
	}
}

fn (mut p UnicodeRangeParser) parse_codepoint() !u32 {
	if p.eof() || p.input[p.i] != `U` {
		return perr(ParseError.invalid_value)
	}
	p.advance()
	if p.eof() || p.input[p.i] != `+` {
		return perr(ParseError.invalid_value)
	}
	p.advance()
	if p.eof() {
		return perr(ParseError.invalid_value)
	}
	start := p.i
	for !p.eof() {
		current := p.input[p.i]
		if !((current >= `0` && current <= `9`) || (current >= `A` && current <= `F`)
			|| (current >= `a` && current <= `f`)) {
			break
		}
		p.advance()
	}
	if start == p.i {
		return perr(ParseError.invalid_value)
	}
	return parse_unicode_hex(p.input[start..p.i])
}

fn (mut p UnicodeRangeParser) advance() {
	p.i++
}

fn (p &UnicodeRangeParser) eof() bool {
	return p.i >= p.input.len
}

fn parse_unicode_codepoint(value string) !u32 {
	if !value.starts_with('U+') {
		return perr(ParseError.invalid_value)
	}
	return u32(zig_fmt.parse_int_unsigned_max(value[2..], 0x1fffff, 16) or {
		return perr(ParseError.invalid_value)
	})
}

fn parse_unicode_hex(value string) !u32 {
	return u32(zig_fmt.parse_int_unsigned_max(value, 0x1fffff, 16) or {
		return perr(ParseError.invalid_value)
	})
}

// ============================================================
// Existing types
// ============================================================

// Command represents a command to execute. It can be either a shell
// command string (parsed by /bin/sh) or a direct argument list.
pub type Command = ShellCmd | DirectCmd

// ShellCmd is a shell command string like "bash --norc".
pub struct ShellCmd {
pub:
	shell string
}

// DirectCmd is a direct command with pre-parsed arguments.
pub struct DirectCmd {
pub:
	direct []string
}

// parse_cli parses the source configuration representation. Only literal
// spaces are trimmed; direct commands are intentionally split naively on
// literal spaces, including empty arguments between repeated separators.
pub fn Command.parse_cli(input ?string) !Command {
	value := input or { return error('value required') }
	trimmed := value.trim(' ')
	if trimmed.len == 0 {
		return error('value required')
	}

	if trimmed.starts_with('direct:') {
		command := trimmed[7..].trim(' ')
		return Command(DirectCmd{
			direct: command.split(' ')
		})
	}
	if trimmed.starts_with('shell:') {
		return Command(ShellCmd{
			shell: trimmed[6..].trim(' ')
		})
	}
	return Command(ShellCmd{
		shell: trimmed
	})
}

// arg_iterator returns an iterator over the command's arguments.
// For shell commands, this splits on whitespace with basic quoting support.
// For direct commands, this iterates the args directly.
pub fn (c Command) arg_iterator() ArgIterator {
	match c {
		ShellCmd {
			return ShellArgIterator{
				shell_str: c.shell
				pos: 0
			}
		}
		DirectCmd {
			return DirectArgIterator{
				args: c.direct
				index: 0
			}
		}
	}
}

// clone creates a copy of the command.
pub fn (c Command) clone() Command {
	match c {
		ShellCmd {
			return Command(ShellCmd{ shell: c.shell.clone() })
		}
		DirectCmd {
			return Command(DirectCmd{ direct: c.direct.clone() })
		}
	}
}

// string_val returns the command as a string.
pub fn (c Command) string_val() string {
	match c {
		ShellCmd {
			return c.shell
		}
		DirectCmd {
			return c.direct.join(' ')
		}
	}
}

pub fn (c Command) format_entry() string {
	return match c {
		ShellCmd { c.shell }
		DirectCmd { 'direct:${c.direct.join(' ')}' }
	}
}

pub struct ShellArgIterator {
mut:
	shell_str string
	pos       int
}

pub struct DirectArgIterator {
mut:
	args  []string
	index int
}

// ArgIterator iterates either the allocated shell parser state or the direct
// argument slice and index retained by the corresponding source union arm.
pub type ArgIterator = DirectArgIterator | ShellArgIterator

// next returns the next argument, or none if exhausted.
pub fn (mut it ArgIterator) next() ?string {
	match mut it {
		ShellArgIterator {
			return it.next_shell_arg()
		}
		DirectArgIterator {
			if it.index >= it.args.len {
				return none
			}
			arg := it.args[it.index]
			it.index++
			return arg
		}
	}
}

// deinit mirrors ArgIterator.deinit. V owns iterator strings through the GC,
// so there is no backing allocation to release.
pub fn (mut it ArgIterator) deinit() {}

// next_shell_arg is Zig 0.15.2's process.ArgIteratorGeneral(.{}).next.
// With the default options, double quotes group arguments, single quotes are
// ordinary characters, and backslashes only receive special treatment when
// immediately preceding a double quote.
fn (mut it ShellArgIterator) next_shell_arg() ?string {
	s := it.shell_str
	// Skip space, tab, carriage return, and newline.
	for it.pos < s.len && s[it.pos] in [` `, `\t`, `\r`, `\n`] {
		it.pos++
	}
	if it.pos >= s.len {
		return none
	}

	mut result := []u8{}
	mut backslash_count := 0
	mut in_quote := false
	for it.pos < s.len {
		ch := s[it.pos]
		match ch {
			`'` {
				for _ in 0 .. backslash_count {
					result << `\\`
				}
				backslash_count = 0
				result << ch
			}
			`"` {
				quote_is_real := backslash_count % 2 == 0
				for _ in 0 .. backslash_count / 2 {
					result << `\\`
				}
				backslash_count = 0
				if quote_is_real {
					in_quote = !in_quote
				} else {
					result << `"`
				}
			}
			`\\` {
				backslash_count++
			}
			` `, `\t`, `\r`, `\n` {
				for _ in 0 .. backslash_count {
					result << `\\`
				}
				backslash_count = 0
				if in_quote {
					result << ch
				} else {
					return result.bytestr()
				}
			}
			else {
				for _ in 0 .. backslash_count {
					result << `\\`
				}
				backslash_count = 0
				result << ch
			}
		}
		it.pos++
	}
	for _ in 0 .. backslash_count {
		result << `\\`
	}
	return result.bytestr()
}

// RepeatableStringMap holds key-value string pairs for environment overrides.
pub struct RepeatableStringMap {
pub mut:
	entries []StringMapEntry
}

pub struct StringMapEntry {
pub:
	key   string
	value string
}

// parse_cli accumulates key/value entries in insertion order. Reassigning a
// key replaces its value in place, an empty value removes that key, and an
// empty option resets the complete map.
pub fn (mut m RepeatableStringMap) parse_cli(input ?string) ! {
	value := input or { return error('value required') }
	if value.len == 0 {
		m.entries.clear()
		return
	}

	index := value.index_u8(`=`)
	if index < 0 {
		return error('value required')
	}
	key := value[..index].trim(' \t\n\r\v\f')
	val := value[index + 1..].trim(' \t\n\r\v\f')
	for i, entry in m.entries {
		if entry.key != key {
			continue
		}
		if val.len == 0 {
			m.entries.delete(i)
		} else {
			m.entries[i] = StringMapEntry{
				key: key
				value: val
			}
		}
		return
	}
	if val.len > 0 {
		m.entries << StringMapEntry{
			key: key
			value: val
		}
	}
}

pub fn (m RepeatableStringMap) clone() RepeatableStringMap {
	return RepeatableStringMap{
		entries: m.entries.clone()
	}
}

pub fn (m RepeatableStringMap) count() int {
	return m.entries.len
}

pub fn (m RepeatableStringMap) equal(other RepeatableStringMap) bool {
	if m.entries.len != other.entries.len {
		return false
	}
	for entry in m.entries {
		mut found := false
		for other_entry in other.entries {
			if entry.key == other_entry.key {
				if entry.value != other_entry.value {
					return false
				}
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

pub fn (m RepeatableStringMap) format_entry() []string {
	if m.entries.len == 0 {
		return ['']
	}
	return m.entries.map('${it.key}=${it.value}')
}

// iterator returns an iterator over the string map entries.
pub fn (m RepeatableStringMap) iterator() RepeatableStringMapIterator {
	return RepeatableStringMapIterator{
		entries: m.entries
		idx: 0
	}
}

pub struct RepeatableStringMapIterator {
	entries []StringMapEntry
mut:
	idx int
}

pub fn (mut it RepeatableStringMapIterator) next() ?StringMapEntry {
	if it.idx >= it.entries.len {
		return none
	}
	entry := it.entries[it.idx]
	it.idx++
	return entry
}

// ShellIntegrationFeatures controls which shell integration features are enabled.
pub struct ShellIntegrationFeatures {
	value u8 = 0x25
}

pub fn ShellIntegrationFeatures.init(cursor bool, sudo bool, title bool, ssh_env bool, ssh_terminfo bool, path bool) ShellIntegrationFeatures {
	return ShellIntegrationFeatures{
		value: u8(cursor) | (u8(sudo) << 1) | (u8(title) << 2) | (u8(ssh_env) << 3) | (u8(ssh_terminfo) << 4) | (u8(path) << 5)
	}
}

pub fn (config ShellIntegrationFeatures) cursor() bool {
	return config.value & 0x01 != 0
}

pub fn (config ShellIntegrationFeatures) sudo() bool {
	return config.value & 0x02 != 0
}

pub fn (config ShellIntegrationFeatures) title() bool {
	return config.value & 0x04 != 0
}

pub fn (config ShellIntegrationFeatures) ssh_env() bool {
	return config.value & 0x08 != 0
}

pub fn (config ShellIntegrationFeatures) ssh_terminfo() bool {
	return config.value & 0x10 != 0
}

pub fn (config ShellIntegrationFeatures) path() bool {
	return config.value & 0x20 != 0
}

pub fn (config ShellIntegrationFeatures) int_val() u8 {
	return config.value
}

pub fn (config ShellIntegrationFeatures) format_entry() string {
	return [if config.cursor() { 'cursor' } else { 'no-cursor' },
		if config.sudo() { 'sudo' } else { 'no-sudo' },
		if config.title() { 'title' } else { 'no-title' },
		if config.ssh_env() { 'ssh-env' } else { 'no-ssh-env' },
		if config.ssh_terminfo() { 'ssh-terminfo' } else { 'no-ssh-terminfo' },
		if config.path() { 'path' } else { 'no-path' }].join(',')
}

// SplitPreserveZoom controls which split operations keep the zoomed state.
pub struct SplitPreserveZoom {
	value u8
}

pub fn SplitPreserveZoom.init(navigation bool) SplitPreserveZoom {
	return SplitPreserveZoom{
		value: if navigation { u8(0x01) } else { u8(0) }
	}
}

pub fn (config SplitPreserveZoom) navigation() bool {
	return config.value & 0x01 != 0
}

pub fn (config SplitPreserveZoom) int_val() u8 {
	return config.value
}

pub fn (config SplitPreserveZoom) format_entry() string {
	return if config.navigation() { 'navigation' } else { 'no-navigation' }
}

// BellFeatures controls the system, audio, attention, title, and border bell
// effects. The defaults match Witty's packed struct.
pub struct BellFeatures {
	value u8 = 0x0c
}

pub fn BellFeatures.init(system bool, audio bool, attention bool, title bool, border bool) BellFeatures {
	return BellFeatures{
		value: u8(system) | (u8(audio) << 1) | (u8(attention) << 2) | (u8(title) << 3) | (u8(border) << 4)
	}
}

pub fn (config BellFeatures) system() bool {
	return config.value & 0x01 != 0
}

pub fn (config BellFeatures) audio() bool {
	return config.value & 0x02 != 0
}

pub fn (config BellFeatures) attention() bool {
	return config.value & 0x04 != 0
}

pub fn (config BellFeatures) title() bool {
	return config.value & 0x08 != 0
}

pub fn (config BellFeatures) border() bool {
	return config.value & 0x10 != 0
}

pub fn (config BellFeatures) int_val() u8 {
	return config.value
}

pub fn (config BellFeatures) format_entry() string {
	return [if config.system() { 'system' } else { 'no-system' },
		if config.audio() { 'audio' } else { 'no-audio' },
		if config.attention() { 'attention' } else { 'no-attention' },
		if config.title() { 'title' } else { 'no-title' },
		if config.border() { 'border' } else { 'no-border' }].join(',')
}

// AppNotifications controls the two GTK in-app toast categories. Defaults
// match Witty's packed struct, where both notification kinds are enabled.
pub struct AppNotifications {
	value u8 = 0x03
}

pub fn AppNotifications.init(clipboard_copy bool, config_reload bool) AppNotifications {
	return AppNotifications{
		value: u8(clipboard_copy) | (u8(config_reload) << 1)
	}
}

pub fn (config AppNotifications) clipboard_copy() bool {
	return config.value & 0x01 != 0
}

pub fn (config AppNotifications) config_reload() bool {
	return config.value & 0x02 != 0
}

pub fn (config AppNotifications) int_val() u8 {
	return config.value
}

pub fn (config AppNotifications) format_entry() string {
	return [
		if config.clipboard_copy() { 'clipboard-copy' } else { 'no-clipboard-copy' },
		if config.config_reload() { 'config-reload' } else { 'no-config-reload' },
	].join(',')
}

pub enum ShellIntegration as u8 {
	none_
	detect
	bash
	elvish
	fish
	nushell
	zsh
}

pub enum LinkPreviews as u8 {
	false_
	true_
	osc8
}

pub enum ClipboardAccess as u8 {
	allow
	deny
	ask
}

pub enum CopyOnSelect as u8 {
	false_
	true_
	clipboard
}

pub enum ConfirmCloseSurface as i32 {
	false_
	true_
	always
}

pub enum MouseShiftCapture as u8 {
	false_
	true_
	always
	never
}

pub struct ConditionalState {
pub mut:
	theme Theme
	os    TargetOs = current_target_os()
}

pub enum Theme as u8 {
	light
	dark
}

// TargetOs is the translated Zig 0.15.2 std.Target.Os.Tag used by conditional
// configuration state.
pub enum TargetOs as u8 {
	freestanding
	other
	contiki
	fuchsia
	hermit
	aix
	haiku
	hurd
	linux
	plan9
	rtems
	serenity
	zos
	dragonfly
	freebsd
	netbsd
	openbsd
	driverkit
	ios
	macos
	tvos
	visionos
	watchos
	illumos
	solaris
	windows
	uefi
	ps3
	ps4
	ps5
	emscripten
	wasi
	amdhsa
	amdpal
	cuda
	mesa3d
	nvcl
	opencl
	opengl
	vulkan
}

fn current_target_os() TargetOs {
	$if ios {
		return .ios
	} $else $if macos {
		return .macos
	} $else $if wasm32_emscripten {
		return .emscripten
	} $else $if wasm32_wasi {
		return .wasi
	} $else $if android {
		return .linux
	} $else $if linux {
		return .linux
	} $else $if windows {
		return .windows
	} $else $if freebsd {
		return .freebsd
	} $else $if openbsd {
		return .openbsd
	} $else $if netbsd {
		return .netbsd
	} $else $if dragonfly {
		return .dragonfly
	} $else $if solaris {
		return .solaris
	} $else $if haiku {
		return .haiku
	} $else $if serenity {
		return .serenity
	} $else $if wasm32 {
		return .freestanding
	} $else {
		return .other
	}
}

pub enum ConditionalKey as u8 {
	theme
	os
}

pub enum ConditionalOp as u8 {
	eq
	ne
}

pub struct Conditional {
pub:
	key   ConditionalKey
	op    ConditionalOp
	value string
}

// match tests a single conditional against this typed state.
pub fn (state ConditionalState) match(condition Conditional) bool {
	value := match condition.key {
		.theme { state.theme.str() }
		.os { state.os.str() }
	}
	equal := value == condition.value
	return match condition.op {
		.eq { equal }
		.ne { !equal }
	}
}

// clone deep-copies the conditional value retained by replay steps.
pub fn (condition Conditional) clone() Conditional {
	return Conditional{
		...condition
		value: condition.value.clone()
	}
}

pub struct ScrollToBottom {
	value u8 = 0x01
}

pub fn ScrollToBottom.init(keystroke bool, output bool) ScrollToBottom {
	return ScrollToBottom{
		value: u8(keystroke) | (u8(output) << 1)
	}
}

pub fn (config ScrollToBottom) keystroke() bool {
	return config.value & 0x01 != 0
}

pub fn (config ScrollToBottom) output() bool {
	return config.value & 0x02 != 0
}

pub fn (config ScrollToBottom) int_val() u8 {
	return config.value
}

pub fn (config ScrollToBottom) format_entry() string {
	return [if config.keystroke() { 'keystroke' } else { 'no-keystroke' },
		if config.output() { 'output' } else { 'no-output' }].join(',')
}

pub struct Duration {
pub:
	duration u64
}

pub fn (d Duration) clone() Duration {
	return Duration{
		duration: d.duration
	}
}

pub fn (d Duration) equal(other Duration) bool {
	return d.duration == other.duration
}

// round truncates this duration to a multiple of `to`. This mirrors
// Config.Duration.round and is primarily used for human-facing durations.
pub fn (d Duration) round(to u64) Duration {
	return Duration{
		duration: d.duration / to * to
	}
}

// lte reports whether this duration is less than or equal to another.
pub fn (d Duration) lte(other Duration) bool {
	return d.duration <= other.duration
}

// as_milliseconds converts the nanosecond duration to the unsigned millisecond
// range accepted by GLib, saturating on overflow.
pub fn (d Duration) as_milliseconds() u32 {
	ms := d.duration / 1_000_000
	if ms > u64(0xffff_ffff) {
		return u32(0xffff_ffff)
	}
	return u32(ms)
}

@[markused]
pub fn (d Duration) cval() uint {
	return uint(d.as_milliseconds())
}

// NotifyOnCommandFinish controls when command-finished notifications are sent.
pub enum NotifyOnCommandFinish as u8 {
	never
	unfocused
	always
}

pub struct NotifyOnCommandFinishAction {
	value u8 = 0x01
}

pub fn NotifyOnCommandFinishAction.init(bell bool, notify bool) NotifyOnCommandFinishAction {
	return NotifyOnCommandFinishAction{
		value: u8(bell) | (u8(notify) << 1)
	}
}

pub fn (config NotifyOnCommandFinishAction) bell() bool {
	return config.value & 0x01 != 0
}

pub fn (config NotifyOnCommandFinishAction) notify() bool {
	return config.value & 0x02 != 0
}

pub fn (config NotifyOnCommandFinishAction) int_val() u8 {
	return config.value
}

pub fn (config NotifyOnCommandFinishAction) format_entry() string {
	return [if config.bell() { 'bell' } else { 'no-bell' },
		if config.notify() { 'notify' } else { 'no-notify' }].join(',')
}

// GraphemeWidthMethod for calculating the cell width of a grapheme cluster.
pub enum GraphemeWidthMethod as u8 {
	legacy
	unicode
}

// Scrollbar controls when the scrollbar is shown.
pub enum Scrollbar as u8 {
	system
	never
}

// WindowDecoration controls window decorations.
pub enum WindowDecoration as i32 {
	auto
	client
	server
	none_
}

// WindowTheme controls the theme used for the window.
pub enum WindowTheme as u8 {
	auto
	system
	light
	dark
	witty
}

// RightClickAction controls the action taken on right-click.
pub enum RightClickAction as u8 {
	ignore
	paste
	copy
	copy_or_paste
	context_menu
}

// OSCColorReportFormat controls the reporting format for OSC color queries.
pub enum OSCColorReportFormat as u8 {
	none_
	format_8_bit
	format_16_bit
}

// CustomShaderAnimation controls whether custom shaders animate.
pub enum CustomShaderAnimation as i32 {
	false_
	true_
	always
}

// WindowSubtitle controls the window subtitle text.
pub enum WindowSubtitle as u8 {
	false_
	working_directory
}

// WindowSaveState controls whether window state is saved between runs.
pub enum WindowSaveState as u8 {
	default
	never
	always
}

// WindowNewTabPosition controls where new tabs are placed.
pub enum WindowNewTabPosition as u8 {
	current
	end
}

// WindowShowTabBar controls when the tab bar is shown.
pub enum WindowShowTabBar as u8 {
	always
	auto
	never
}

// ResizeOverlay controls when a resize overlay is shown.
pub enum ResizeOverlay as u8 {
	always
	never
	after_first
}

// ResizeOverlayPosition controls where the resize overlay is drawn.
pub enum ResizeOverlayPosition as u8 {
	center
	top_left
	top_center
	top_right
	bottom_left
	bottom_center
	bottom_right
}

// AsyncBackend selects the async event loop backend.
pub enum AsyncBackend as u8 {
	auto
	epoll
	io_uring
}

// format_entry preserves the source enum tag's underscore in `io_uring`.
pub fn (a AsyncBackend) format_entry() string {
	return a.str()
}

// AutoUpdate controls Sparkle's automatic update behavior on macOS.
pub enum AutoUpdate as u8 {
	off
	check
	download
}

// ============================================================
// Color types for theme preview
// ============================================================

// ColorRGB holds an 8-bit-per-channel color.
pub struct ColorRGB {
pub:
	r u8
	g u8
	b u8
}

// cval projects Color to ghostty_config_color_s.
pub fn (c ColorRGB) cval() CConfigColor {
	return CConfigColor{
		r: c.r
		g: c.g
		b: c.b
	}
}

// to_terminal_rgb converts the configuration color to terminal.color.RGB.
pub fn (c ColorRGB) to_terminal_rgb() terminal.RGB {
	return terminal.RGB{
		r: c.r
		g: c.g
		b: c.b
	}
}

pub fn (c ColorRGB) clone() ColorRGB {
	return c
}

pub fn (c ColorRGB) equal(other ColorRGB) bool {
	return c == other
}

// format_buf is Color.formatBuf; V returns its owned string directly.
pub fn (c ColorRGB) format_buf() string {
	return '#${c.r:02x}${c.g:02x}${c.b:02x}'
}

pub fn (c ColorRGB) format_entry() string {
	return c.format_buf()
}

// from_hex parses a color from #RRGGBB or #RGB syntax.
pub fn ColorRGB.from_hex(input string) !ColorRGB {
	mut trimmed := input
	if trimmed.len != 0 && trimmed[0] == `#` {
		trimmed = trimmed[1..]
	}
	if trimmed.len != 6 && trimmed.len != 3 {
		return perr(ParseError.invalid_value)
	}
	rgb := if trimmed.len == 3 {
		[trimmed[0], trimmed[0], trimmed[1], trimmed[1], trimmed[2], trimmed[2]].bytestr()
	} else {
		trimmed
	}
	r := parse_hex_byte(rgb[0..2]) or { return perr(ParseError.invalid_value) }
	g := parse_hex_byte(rgb[2..4]) or { return perr(ParseError.invalid_value) }
	b := parse_hex_byte(rgb[4..6]) or { return perr(ParseError.invalid_value) }
	return ColorRGB{
		r: r
		g: g
		b: b
	}
}

// parse_cli trims source-defined ASCII whitespace, tries X11 names, and then
// parses hexadecimal syntax.
pub fn ColorRGB.parse_cli(input_ ?string) !ColorRGB {
	input := input_ or { return perr(ParseError.value_required) }
	trimmed := input.trim(' \t')
	if named := named_x11_color(trimmed) {
		return named
	}
	return ColorRGB.from_hex(trimmed)
}

// Palette holds the 256-color terminal palette.
pub struct Palette {
pub mut:
	value [256]ColorRGB
}

// default_palette returns Witty's canonical 256-color palette.
pub fn Palette.default_palette() Palette {
	mut p := Palette{}
	for i in 0 .. 256 {
		color := terminal.default_palette[i]
		p.value[i] = ColorRGB{color.r, color.g, color.b}
	}
	return p
}

@[markused]
pub fn (p Palette) cval() CConfigPalette {
	mut result := CConfigPalette{}
	for i, color in p.value {
		result.colors[i] = color.cval()
	}
	return result
}

pub fn (p Palette) clone() Palette {
	return p
}

pub fn (p Palette) equal(other Palette) bool {
	return p == other
}

pub fn (p Palette) format_entry() []string {
	mut result := []string{cap: 256}
	for i, color in p.value {
		result << '${i}=${color.format_buf()}'
	}
	return result
}

// Diagnostic is the translated cli.Diagnostic, including source location and
// key metadata as well as the human-readable message.
pub type Diagnostic = diagnosticspkg.Diagnostic

enum ReplayStepKind as u8 {
	arg
	expand
	conditional_arg
	diagnostic
	command
}

struct ReplayArg {
	value string
}

struct ReplayExpand {
	base string
}

struct ReplayConditionalArg {
	conditions []Conditional
	arg        string
}

struct ReplayDiagnostic {
	diagnostic Diagnostic
}

struct ReplayCommand {}

// ReplayStep records configuration input in source order. Witty rebuilds a
// configuration from these steps after loading a theme so that the theme is a
// base layer and every user option—including repeatable options—retains its
// normal parser semantics.
type ReplayStep = ReplayArg
	| ReplayExpand
	| ReplayConditionalArg
	| ReplayDiagnostic
	| ReplayCommand

fn (self ReplayStep) kind() ReplayStepKind {
	return match self {
		ReplayArg { .arg }
		ReplayExpand { .expand }
		ReplayConditionalArg { .conditional_arg }
		ReplayDiagnostic { .diagnostic }
		ReplayCommand { .command }
	}
}

// ReplayIterator reapplies retained side effects and yields arguments through
// the ordinary config parser. A command step yields the synthetic `-e` marker;
// the parser then consumes every following argument as the command tail.
struct ReplayIterator {
	steps []ReplayStep
mut:
	config &Config = unsafe { nil }
	index  int
}

fn ReplayIterator.new(steps []ReplayStep, mut config Config) ReplayIterator {
	return ReplayIterator{
		steps: steps
		config: unsafe { &config }
	}
}

fn (mut self ReplayIterator) next() ?string {
	for self.index < self.steps.len {
		step := self.steps[self.index]
		self.index++
		match step {
			ReplayExpand {
				self.config.expand_paths(step.base) or {
					log.warn('error expanding paths err=${err}')
				}
			}
			ReplayDiagnostic {
				self.config.diagnostics << step.diagnostic.clone()
			}
			ReplayConditionalArg {
				mut matches := true
				for condition in step.conditions {
					if !self.config.conditional_state.match(condition) {
						matches = false
						break
					}
				}
				if matches {
					return step.arg
				}
			}
			ReplayArg {
				return step.value
			}
			ReplayCommand {
				return '-e'
			}
		}
	}
	return none
}

// load loads configuration using Witty's default-file order, command-line
// arguments, recursively referenced files, and finalization order.
pub fn Config.load() !Config {
	$if linux || freebsd {
		return Config.load_argv(internal_os.process_args())
	} $else $if windows {
		return Config.load_args([])
	} $else {
		mut iter := cli_args.args_iterator()
		defer {
			iter.deinit()
		}
		mut args := []string{}
		for {
			args << iter.next() or { break }
		}
		return Config.load_args(args)
	}
}

// load_argv loads configuration from a complete process argv, including the
// executable name. This preserves xdg-terminal-exec's argv[0] convention.
pub fn Config.load_argv(argv []string) !Config {
	$if linux || freebsd {
		if command_args := internal_os.parse_terminal_exec(argv) {
			mut c := Config.default_config()
			c.load_default_files()!
			c.load_xdg_terminal_exec_args(command_args)
			c.load_recursive_files()!
			c.finalize()!
			return c
		}
	}
	args := if argv.len > 1 { argv[1..] } else { []string{} }
	return Config.load_args(args)
}

// load_args is the explicit-argv form used by embedders and tests.
pub fn Config.load_args(args []string) !Config {
	mut c := Config.default_config()
	c.load_default_files()!
	c.load_cli_args(args)!
	if !c.config_default_files {
		// config-default-files only has an effect on the CLI. Rebuild from
		// defaults and CLI arguments, discarding all default-file steps.
		mut cli_only := Config.default_config()
		cli_only.load_cli_args(args)!
		c = cli_only
	}
	c.load_recursive_files()!
	c.finalize()!
	return c
}

// load_default_files reads the platform's default configuration paths in the
// same order as Witty's Config.loadDefaultFiles. If no default file exists,
// it creates Witty's commented starter template at the preferred location.
pub fn (mut c Config) load_default_files() ! {
	legacy_xdg_path := legacy_default_xdg_path()!
	previous_xdg_path := previous_default_xdg_path()!
	xdg_path := default_xdg_path()!
	legacy_xdg_action := c.load_optional_file(legacy_xdg_path)
	previous_xdg_action := c.load_optional_file(previous_xdg_path)
	preferred_xdg_action := c.load_optional_file(xdg_path)
	xdg_loaded := legacy_xdg_action != .not_found || previous_xdg_action != .not_found
		|| preferred_xdg_action != .not_found
	$if macos {
		legacy_app_support_path := legacy_default_app_support_path()!
		previous_app_support_path := previous_default_app_support_path()!
		app_support_path := default_app_support_path()!
		legacy_app_support_action := c.load_optional_file(legacy_app_support_path)
		previous_app_support_action := c.load_optional_file(previous_app_support_path)
		preferred_app_support_action := c.load_optional_file(app_support_path)
		app_support_loaded := legacy_app_support_action != .not_found
			|| previous_app_support_action != .not_found
			|| preferred_app_support_action != .not_found
		if !app_support_loaded && !xdg_loaded {
			write_config_template(app_support_path) or {}
		}
	} $else {
		if !xdg_loaded {
			write_config_template(xdg_path) or {}
		}
	}
}

pub enum OptionalFileAction as u8 {
	loaded
	not_found
	error_
}

// load_optional_file ignores file errors and reports the action taken. As in
// Witty, an existing unreadable path is distinct from a missing path so it
// suppresses creation of a replacement template.
pub fn (mut c Config) load_optional_file(path string) OptionalFileAction {
	c.load_file(path) or {
		if kind := open_file_error_of(err) {
			if kind == .file_not_found {
				return .not_found
			}
		}
		return .error_
	}
	return .loaded
}

fn write_config_template(path string) ! {
	directory := os.dir(path)
	if directory.len > 0 {
		os.mkdir_all(directory)!
	}
	os.write_file(path, config_template.replace('{[path]s}', path))!
}

// load_cli_argv preserves loadCliArgs' Linux/FreeBSD std.os.argv fast path
// and xdg-terminal-exec argv[0] dispatch for both executable and C callers.
pub fn (mut c Config) load_cli_argv(argv []string) ! {
	$if linux || freebsd {
		if argv.len <= 1 { return }
		if command_args := internal_os.parse_terminal_exec(argv) {
			c.load_xdg_terminal_exec_args(command_args)
			return
		}
	}
	c.load_cli_args(if argv.len > 1 { argv[1..] } else { []string{} })!
}

// load_cli_args applies Witty's `--key=value` configuration syntax and the
// special `-e command...` tail. Paths declared here resolve against cwd.
pub fn (mut c Config) load_cli_args(args []string) ! {
	c.config_default_files = true
	if args.len == 0 {
		return
	}
	mut iter := cli_args.ArgsIterator.new(args)
	c.load_iter_internal(mut iter, true)
	c.expand_paths(os.getwd())!
}

// load_iter loads configuration from any translated CLI iterator. Iterator
// types that expose location() attach their source location to diagnostics;
// iterators without it produce location-less diagnostics, matching
// cli.Location.fromIter in the source.
pub fn (mut c Config) load_iter[T](mut iter T) {
	c.load_iter_internal(mut iter, false)
}

fn (mut c Config) load_iter_internal[T](mut iter T, overwrite_font_families bool) {
	mut overwritten_font_fields := map[string]bool{}
	for {
		arg := iter.next() or { break }
		if !c.parse_manually_hook(arg, mut iter) {
			return
		}
		location := diagnosticspkg.Location.from_iter(iter)
		if !arg.starts_with('--') {
			c.diagnostics << Diagnostic{
				location: location
				key: arg
				message: 'invalid field'
			}
			continue
		}
		mut key := arg[2..]
		mut value := ''
		mut has_value := false
		if eq := key.index('=') {
			value = key[eq + 1..]
			key = key[..eq]
			has_value = true
		}

		if overwrite_font_families && has_value && is_font_family_key(key)
			&& key !in overwritten_font_fields {
			overwritten_font_fields[key] = true
			c.apply_kv_with_context(key, '', true, location)
		}
		if has_value {
			c.apply_kv_with_context(key, value, true, location)
		} else {
			c.apply_kv_with_context(key, '', false, location)
		}
	}
}

// parse_manually_hook implements Config.parseManuallyHook. It records every
// ordinary argument for replay and owns the special `-e command...` tail.
// V's garbage collector removes the allocator parameter from the source API.
pub fn (mut c Config) parse_manually_hook[T](arg string, mut iter T) bool {
	if arg != '-e' {
		c.replay_steps << ReplayArg{
			value: arg
		}
		return true
	}

	mut command_args := []string{}
	c.replay_steps << ReplayCommand{}
	for {
		param := iter.next() or { break }
		c.replay_steps << ReplayArg{
			value: param
		}
		command_args << param
	}
	c.apply_command_tail(command_args, diagnosticspkg.Location.from_iter(iter))
	return false
}

fn (mut c Config) apply_command_tail(command_args []string, location diagnosticspkg.Location) {
	if command_args.len == 0 {
		c.diagnostics << Diagnostic{
			location: location
			message: 'missing command after -e'
		}
		return
	}
	c.initial_command = Command(DirectCmd{ direct: command_args.clone() })
	c.gtk_single_instance = .false_
	c.quit_after_last_window_closed = true
	c.quit_after_last_window_closed_delay = none
	if c.shell_integration != .none_ {
		c.shell_integration = .detect
	}
}

// load_xdg_terminal_exec_args applies the special xdg-terminal-exec command
// mode. Unlike the normal -e parser, this only sets the initial command and
// marker; all other configuration remains as loaded from default files.
fn (mut c Config) load_xdg_terminal_exec_args(args []string) {
	c.replay_steps << ReplayCommand{}
	for arg in args {
		c.replay_steps << ReplayArg{
			value: arg
		}
	}
	c.xdg_terminal_exec = true
	c.initial_command = Command(DirectCmd{ direct: args.clone() })
}

fn is_font_family_key(key string) bool {
	return key == 'font-family' || key == 'font-family-bold' || key == 'font-family-italic'
		|| key == 'font-family-bold-italic'
}

fn is_boolean_config_key(key string) bool {
	return key in ['font-thicken', 'background-opacity-cells', 'background-image-repeat',
		'window-vsync', 'clipboard-trim-trailing-spaces', 'clipboard-paste-protection',
		'clipboard-paste-bracketed-safe', 'cursor-click-to-move', 'desktop-notifications',
		'mouse-hide-while-typing', 'mouse-reporting', 'selection-clear-on-copy',
		'selection-clear-on-typing', 'vt-kam-allowed', 'wait-after-command', 'window-padding-balance',
		'title-report', 'link-url', 'maximize', 'fullscreen', 'focus-follows-mouse',
		'window-inherit-working-directory', 'tab-inherit-working-directory',
		'split-inherit-working-directory', 'window-inherit-font-size', 'window-step-resize',
		'initial-window', 'quick-terminal-autohide', 'quit-after-last-window-closed',
		'config-default-files', 'linux-cgroup-hard-fail', 'gtk-opengl-debug', 'gtk-titlebar',
		'gtk-titlebar-hide-when-maximized', 'gtk-wide-tabs', 'macos-window-shadow',
		'macos-auto-secure-input', 'macos-secure-input-indication', 'cursor-style-blink']
}

// load_file loads the absolute configuration path. File-open failures are
// returned through config/file_load.zig's constrained error set; malformed
// configuration entries are recorded as diagnostics by the line iterator.
pub fn (mut c Config) load_file(path string) ! {
	c.load_file_result(path)!
}

fn (mut c Config) load_file_result(path string) ! {
	assert os.is_abs_path(path)
	mut file := open(path) or {
		if kind := open_file_error_of(err) {
			if kind == .not_a_file {
				return
			}
		}
		return err
	}
	defer {
		file.close()
	}
	content := io.read_all(reader: file)!
	c.load_string_with_path(content.bytestr(), path)
	c.expand_paths(os.dir(path))!
}

// load_recursive_files loads each config-file entry once, expanding paths
// relative to the file that declared them. The list may grow while it is read.
pub fn (mut c Config) load_recursive_files() ! {
	if c.config_file.items.len == 0 {
		return
	}
	mut replay_suffix := []ReplayStep{}
	for i, step in c.replay_steps {
		if step is ReplayCommand {
			replay_suffix = c.replay_steps[i..].clone()
			c.replay_steps.trim(i)
			break
		}
	}
	mut loaded := map[string]bool{}
	mut index := 0
	for index < c.config_file.items.len {
		item := c.config_file.items[index]
		index++
		path := match item {
			PathOptional { item.path }
			PathRequired { item.path }
		}
		optional := item is PathOptional
		if path.len == 0 {
			continue
		}
		assert os.is_abs_path(path)
		if path in loaded {
			c.add_replay_diagnostic('config-file ${path}: cycle detected')
			continue
		}
		loaded[path] = true
		mut file := os.open(path) or {
			if err.code() != C.ENOENT || !optional {
				message := if err.code() == C.ENOENT {
					'error opening config-file ${path}: error.FileNotFound'
				} else {
					'error opening config-file ${path}: ${err}'
				}
				c.add_replay_diagnostic(message)
			}
			continue
		}
		stat := os.stat(path) or {
			file.close()
			return err
		}
		if stat.get_filetype() != .regular {
			file.close()
			c.add_replay_diagnostic('config-file ${path}: not reading because file type is ${stat.get_filetype().str()}')
			continue
		}
		content := io.read_all(reader: file) or {
			file.close()
			return err
		}
		file.close()
		c.load_string_with_path(content.bytestr(), path)
		c.expand_paths(os.dir(path))!
	}
	if replay_suffix.len > 0 {
		c.replay_steps << replay_suffix
	}
}

fn (mut c Config) expand_paths(base string) ! {
	c.replay_steps << ReplayExpand{
		base: base
	}
	c.custom_shader.expand(base, mut c.diagnostics)!
	c.config_file.expand(base, mut c.diagnostics)!
	c.gtk_custom_css.expand(base, mut c.diagnostics)!
	if mut background_image := c.background_image {
		background_image.expand(base, mut c.diagnostics)!
		c.background_image = background_image
	}
	if mut bell_audio_path := c.bell_audio_path {
		bell_audio_path.expand(base, mut c.diagnostics)!
		c.bell_audio_path = bell_audio_path
	}
}

fn (mut c Config) add_diagnostic(message string) {
	c.diagnostics << Diagnostic{
		message: message
	}
}

// add_diagnostic_fmt appends a caller-formatted diagnostic with no source
// location. V interpolation performs the source's comptime format operation at
// the call site, so the translated API receives the completed message.
pub fn (mut c Config) add_diagnostic_fmt(message string) {
	c.add_diagnostic(message)
}

// add_replay_diagnostic records diagnostics that do not have an input step of
// their own (for example, failure to open a config file). Parser and expansion
// diagnostics are regenerated by replaying their kv/expand step.
fn (mut c Config) add_replay_diagnostic(message string) {
	c.add_replay_diagnostic_entry(Diagnostic{
		message: message
	})
}

fn (mut c Config) add_replay_diagnostic_entry(diagnostic Diagnostic) {
	c.diagnostics << diagnostic
	c.replay_steps << ReplayDiagnostic{
		diagnostic: diagnostic.clone()
	}
}

// load_string parses config file contents from an in-memory string. This is
// the reader-based half of Witty's loadReader, minus the OS file handling.
pub fn (mut c Config) load_string(content string) {
	c.load_string_with_path(content, '')
}

fn (mut c Config) load_string_with_path(content string, path string) {
	mut body := content
	// Skip a leading UTF-8 byte order mark if present.
	if body.len >= 3 && body[0] == 0xef && body[1] == 0xbb && body[2] == 0xbf {
		body = body[3..]
	}
	mut iter := cli_args.LineIterator.new_with_path(body, path)
	c.load_iter(mut iter)
}

fn (mut c Config) apply_kv_with_context(key string, value string, has_value bool, location diagnosticspkg.Location) {
	diagnostic_start := c.diagnostics.len
	if has_value {
		c.apply_kv(key, value)
	} else {
		c.apply_kv_missing(key)
	}
	c.contextualize_diagnostics(diagnostic_start, key, value, has_value, location)
}

fn (mut c Config) contextualize_diagnostics(start int, key string, value string, has_value bool, location diagnosticspkg.Location) {
	for i in start .. c.diagnostics.len {
		diagnostic := c.diagnostics[i]
		mut message := diagnostic.message
		if message == '${key}: unknown field' {
			message = 'unknown field'
		} else if !has_value && is_config_key(key) {
			message = cli_args.format_value_required[Config](key)
		} else if has_value && is_config_key(key) {
			message = cli_args.format_invalid_value[Config](key, value)
		}
		c.diagnostics[i] = Diagnostic{
			location: location.clone()
			key: key
			message: message
		}
	}
}

fn clone_replay_steps(steps []ReplayStep) []ReplayStep {
	mut result := []ReplayStep{cap: steps.len}
	for step in steps {
		match step {
			ReplayArg {
				result << ReplayArg{
					value: step.value.clone()
				}
			}
			ReplayExpand {
				result << ReplayExpand{
					base: step.base.clone()
				}
			}
			ReplayConditionalArg {
				result << ReplayConditionalArg{
					conditions: step.conditions.map(it.clone())
					arg:        step.arg.clone()
				}
			}
			ReplayDiagnostic {
				result << ReplayDiagnostic{
					diagnostic: step.diagnostic.clone()
				}
			}
			ReplayCommand {
				result << ReplayCommand{}
			}
		}
	}
	return result
}

// apply_kv applies a single `key = value` pair to the config. Keys use the
// hyphenated Witty spelling. Unknown keys are ignored (matching Witty's
// behavior of not failing on unknown options). Invalid values are recorded
// as diagnostics.
fn (mut c Config) apply_kv(key string, value string) {
	// Witty's reflected CLI parser handles an explicitly empty value before
	// any type-specific parser: it resets the field to its declared default.
	// Keep this centralized so every Config field has the same behavior rather
	// than duplicating subtly different empty handling in each match arm.
	if value.len == 0 && c.reset_empty_config_value(key) {
		return
	}

	match key {
		'background' {
			if col := parse_color(value) {
				c.background = col
			} else {
				c.diagnostics << Diagnostic{
					message: 'invalid color for "background": ${value}'
				}
			}
		}
		'foreground' {
			if col := parse_color(value) {
				c.foreground = col
			} else {
				c.diagnostics << Diagnostic{
					message: 'invalid color for "foreground": ${value}'
				}
			}
		}
		'cursor-color' {
			if value.len == 0 {
				c.cursor_color = none
			} else {
				c.cursor_color = terminal_color_parse_cli(value) or {
					c.diagnostics << Diagnostic{
						message: 'invalid terminal color for "cursor-color": ${value}'
					}
					return
				}
			}
		}
		'cursor-text' {
			if value.len == 0 {
				c.cursor_text = none
			} else {
				c.cursor_text = terminal_color_parse_cli(value) or {
					c.diagnostics << Diagnostic{
						message: 'invalid terminal color for "cursor-text": ${value}'
					}
					return
				}
			}
		}
		'selection-background' {
			if value.len == 0 {
				c.selection_background = none
			} else {
				c.selection_background = terminal_color_parse_cli(value) or {
					c.diagnostics << Diagnostic{
						message: 'invalid terminal color for "selection-background": ${value}'
					}
					return
				}
			}
		}
		'selection-foreground' {
			if value.len == 0 {
				c.selection_foreground = none
			} else {
				c.selection_foreground = terminal_color_parse_cli(value) or {
					c.diagnostics << Diagnostic{
						message: 'invalid terminal color for "selection-foreground": ${value}'
					}
					return
				}
			}
		}
		'search-background' {
			c.search_background = terminal_color_parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid terminal color for "search-background": ${value}'
				}
				return
			}
		}
		'search-foreground' {
			c.search_foreground = terminal_color_parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid terminal color for "search-foreground": ${value}'
				}
				return
			}
		}
		'search-selected-background' {
			c.search_selected_background = terminal_color_parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid terminal color for "search-selected-background": ${value}'
				}
				return
			}
		}
		'search-selected-foreground' {
			c.search_selected_foreground = terminal_color_parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid terminal color for "search-selected-foreground": ${value}'
				}
				return
			}
		}
		'palette' {
			c.apply_palette(value)
		}
		'theme' {
			c.theme = theme_pair_parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'window-theme' {
			c.window_theme = match value {
				'auto' { .auto }
				'system' { .system }
				'light' { .light }
				'dark' { .dark }
				'witty', 'ghostty' { .witty }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'window-title-font-family' {
			c.window_title_font_family = if value.len == 0 { none } else { value }
		}
		'window-titlebar-background' {
			if value.len == 0 {
				c.window_titlebar_background = none
			} else {
				c.window_titlebar_background = color_parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'window-titlebar-foreground' {
			if value.len == 0 {
				c.window_titlebar_foreground = none
			} else {
				c.window_titlebar_foreground = color_parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'font-family' {
			c.apply_font_family_value(mut &c.font_family, value)
		}
		'font-family-bold' {
			c.apply_font_family_value(mut &c.font_family_bold, value)
		}
		'font-family-italic' {
			c.apply_font_family_value(mut &c.font_family_italic, value)
		}
		'font-family-bold-italic' {
			c.apply_font_family_value(mut &c.font_family_bold_italic, value)
		}
		'font-size' {
			c.font_size = f32(c.parse_config_f64(key, value) or { return })
		}
		'term' {
			c.term = value
		}
		'scrollback-limit' {
			c.scrollback_limit = c.parse_config_u64(key, value) or { return }
		}
		'background-opacity' {
			c.background_opacity = c.parse_config_f64(key, value) or { return }
		}
		'minimum-contrast' {
			c.minimum_contrast = c.parse_config_f64(key, value) or { return }
		}
		'unfocused-split-opacity' {
			c.unfocused_split_opacity = c.parse_config_f64(key, value) or { return }
		}
		'faint-opacity' {
			c.faint_opacity = c.parse_config_f64(key, value) or { return }
		}
		'cursor-opacity' {
			c.cursor_opacity = c.parse_config_f64(key, value) or { return }
		}
		'window-width' {
			c.window_width = c.parse_config_u32(key, value) or { return }
		}
		'window-height' {
			c.window_height = c.parse_config_u32(key, value) or { return }
		}
		'title' {
			c.title = value
		}
		'class' {
			c.class = value
		}
		'x11-instance-name' {
			c.x11_instance_name = value
		}
		'working-directory' {
			c.working_directory = value
		}
		'abnormal-command-exit-runtime' {
			c.abnormal_command_exit_runtime = c.parse_config_u32(key, value) or { return }
		}
		'selection-word-chars' {
			c.selection_word_chars.parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid selection-word-chars "${value}": ${err.msg()}'
				}
			}
		}
		'clipboard-codepoint-map' {
			c.clipboard_codepoint_map.parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid clipboard-codepoint-map "${value}": ${err.msg()}'
				}
			}
		}
		'keybind' {
			c.keybind.parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid keybind "${value}": ${err.msg()}'
				}
			}
		}
		'command-palette-entry' {
			c.command_palette_entry.parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid command-palette-entry "${value}": ${err.msg()}'
				}
			}
		}
		'key-remap' {
			c.key_remap.parse_cli(value) or {
				c.diagnostics << Diagnostic{
					message: 'invalid key-remap "${value}": ${err.msg()}'
				}
			}
		}
		'command' {
			if value.len == 0 {
				c.command = none
			} else {
				c.command = Command.parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'initial-command' {
			if value.len == 0 {
				c.initial_command = none
			} else {
				c.initial_command = Command.parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'input' {
			c.input.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'gtk-quick-terminal-namespace' {
			c.gtk_quick_terminal_namespace = value
		}
		'env' {
			c.apply_env(value)
		}
		'enquiry-response' {
			c.enquiry_response = value
		}
		'font-feature' {
			apply_repeatable_string(mut c.font_feature, value)
		}
		'font-style' {
			c.font_style.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'font-style-bold' {
			c.font_style_bold.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'font-style-italic' {
			c.font_style_italic.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'font-style-bold-italic' {
			c.font_style_bold_italic.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'font-variation' {
			c.font_variation.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'font-variation-bold' {
			c.font_variation_bold.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'font-variation-italic' {
			c.font_variation_italic.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'font-variation-bold-italic' {
			c.font_variation_bold_italic.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'font-codepoint-map' {
			c.font_codepoint_map.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'font-synthetic-style' {
			c.font_synthetic_style = parse_font_synthetic_style(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'freetype-load-flags' {
			c.freetype_load_flags = parse_freetype_load_flags(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'adjust-cell-width', 'adjust-cell-height', 'adjust-font-baseline', 'adjust-underline-position', 'adjust-underline-thickness', 'adjust-strikethrough-position', 'adjust-strikethrough-thickness', 'adjust-overline-position', 'adjust-overline-thickness', 'adjust-cursor-thickness', 'adjust-cursor-height', 'adjust-box-thickness', 'adjust-icon-height' {
			mut parsed := ?font.MetricsModifier(none)
			if value.len > 0 {
				parsed = metric_modifier_parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
			match key {
				'adjust-cell-width' {
					c.adjust_cell_width = parsed
				}
				'adjust-cell-height' {
					c.adjust_cell_height = parsed
				}
				'adjust-font-baseline' {
					c.adjust_font_baseline = parsed
				}
				'adjust-underline-position' {
					c.adjust_underline_position = parsed
				}
				'adjust-underline-thickness' {
					c.adjust_underline_thickness = parsed
				}
				'adjust-strikethrough-position' {
					c.adjust_strikethrough_position = parsed
				}
				'adjust-strikethrough-thickness' {
					c.adjust_strikethrough_thickness = parsed
				}
				'adjust-overline-position' {
					c.adjust_overline_position = parsed
				}
				'adjust-overline-thickness' {
					c.adjust_overline_thickness = parsed
				}
				'adjust-cursor-thickness' {
					c.adjust_cursor_thickness = parsed
				}
				'adjust-cursor-height' {
					c.adjust_cursor_height = parsed
				}
				'adjust-box-thickness' {
					c.adjust_box_thickness = parsed
				}
				'adjust-icon-height' {
					c.adjust_icon_height = parsed
				}
				else {}
			}
		}
		'custom-shader' {
			c.custom_shader.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'gtk-custom-css' {
			c.gtk_custom_css.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'config-file' {
			c.config_file.parse_cli(value) or {
				c.invalid_config_value(key, value)
			}
		}
		'background-image' {
			if value.len == 0 {
				c.background_image = none
			} else {
				maybe_parsed := Path.parse(value) or {
					c.invalid_config_value(key, value)
					return
				}
				if parsed := maybe_parsed.value {
					if parsed.len() > 0 {
						c.background_image = parsed
					}
				}
			}
		}
		'bell-audio-path' {
			if value.len == 0 {
				c.bell_audio_path = none
			} else {
				maybe_parsed := Path.parse(value) or {
					c.invalid_config_value(key, value)
					return
				}
				if parsed := maybe_parsed.value {
					if parsed.len() > 0 {
						c.bell_audio_path = parsed
					}
				}
			}
		}
		'bell-audio-volume' {
			c.bell_audio_volume = c.parse_config_f64(key, value) or { return }
		}
		'bold-color' {
			if value.len == 0 {
				c.bold_color = none
			} else {
				parsed := BoldColor.parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
				c.bold_color = parsed
			}
		}
		'unfocused-split-fill' {
			if value.len == 0 {
				c.unfocused_split_fill = none
			} else {
				c.unfocused_split_fill = color_parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'split-divider-color' {
			if value.len == 0 {
				c.split_divider_color = none
			} else {
				c.split_divider_color = color_parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'split-preserve-zoom' {
			c.split_preserve_zoom = parse_split_preserve_zoom(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'window-padding-x' {
			c.window_padding_x = WindowPadding.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'window-padding-y' {
			c.window_padding_y = WindowPadding.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'window-padding-balance' {
			if value == 'equal' {
				c.window_padding_balance = .equal
			} else {
				balance := c.parse_config_bool(key, value) or { return }
				c.window_padding_balance = if balance { .true_ } else { .false_ }
			}
		}
		'window-position-x' {
			c.window_position_x = if value.len == 0 {
				none
			} else {
				c.parse_config_i16(key, value) or { return }
			}
		}
		'window-position-y' {
			c.window_position_y = if value.len == 0 {
				none
			} else {
				c.parse_config_i16(key, value) or { return }
			}
		}
		'window-save-state' {
			c.window_save_state = match value {
				'default' { .default }
				'never' { .never }
				'always' { .always }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'undo-timeout' {
			c.undo_timeout = Duration.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'async-backend' {
			c.async_backend = match value {
				'auto' { .auto }
				'epoll' { .epoll }
				'io_uring' { .io_uring }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'auto-update' {
			if value.len == 0 {
				c.auto_update = none
			} else {
				c.auto_update = match value {
					'off' { AutoUpdate.off }
					'check' { AutoUpdate.check }
					'download' { AutoUpdate.download }
					else {
						c.invalid_config_value(key, value)
						return
					}
				}
			}
		}
		'auto-update-channel' {
			if value.len == 0 {
				c.auto_update_channel = none
			} else {
				c.auto_update_channel = match value {
					'tip' { buildcfg.ReleaseChannel.tip }
					'stable' { buildcfg.ReleaseChannel.stable }
					else {
						c.invalid_config_value(key, value)
						return
					}
				}
			}
		}
		'font-shaping-break' {
			c.font_shaping_break = parse_font_shaping_break(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'shell-integration-features' {
			c.shell_integration_features = parse_shell_integration_features(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'bell-features' {
			c.bell_features = parse_bell_features(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'app-notifications' {
			c.app_notifications = parse_app_notifications(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'scroll-to-bottom' {
			c.scroll_to_bottom = parse_scroll_to_bottom(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'font-thicken', 'background-opacity-cells', 'background-image-repeat', 'window-vsync', 'clipboard-trim-trailing-spaces', 'clipboard-paste-protection', 'clipboard-paste-bracketed-safe', 'cursor-click-to-move', 'desktop-notifications', 'mouse-hide-while-typing', 'mouse-reporting', 'selection-clear-on-copy', 'selection-clear-on-typing', 'vt-kam-allowed', 'wait-after-command', 'title-report', 'link-url', 'maximize', 'fullscreen', 'focus-follows-mouse', 'window-inherit-working-directory', 'tab-inherit-working-directory', 'split-inherit-working-directory', 'window-inherit-font-size', 'window-step-resize', 'initial-window', 'quick-terminal-autohide', 'quit-after-last-window-closed', 'config-default-files', 'linux-cgroup-hard-fail', 'gtk-opengl-debug', 'gtk-titlebar', 'gtk-titlebar-hide-when-maximized', 'gtk-wide-tabs', '_xdg-terminal-exec' {
			parsed := c.parse_config_bool(key, value) or { return }
			match key {
				'font-thicken' {
					c.font_thicken = parsed
				}
				'background-opacity-cells' {
					c.background_opacity_cells = parsed
				}
				'background-image-repeat' {
					c.background_image_repeat = parsed
				}
				'window-vsync' {
					c.window_vsync = parsed
				}
				'clipboard-trim-trailing-spaces' {
					c.clipboard_trim_trailing_spaces = parsed
				}
				'clipboard-paste-protection' {
					c.clipboard_paste_protection = parsed
				}
				'clipboard-paste-bracketed-safe' {
					c.clipboard_paste_bracketed_safe = parsed
				}
				'cursor-click-to-move' {
					c.cursor_click_to_move = parsed
				}
				'desktop-notifications' {
					c.desktop_notifications = parsed
				}
				'mouse-hide-while-typing' {
					c.mouse_hide_while_typing = parsed
				}
				'mouse-reporting' {
					c.mouse_reporting = parsed
				}
				'selection-clear-on-copy' {
					c.selection_clear_on_copy = parsed
				}
				'selection-clear-on-typing' {
					c.selection_clear_on_typing = parsed
				}
				'vt-kam-allowed' {
					c.vt_kam_allowed = parsed
				}
				'wait-after-command' {
					c.wait_after_command = parsed
				}
				'title-report' {
					c.title_report = parsed
				}
				'link-url' {
					c.link_url = parsed
				}
				'maximize' {
					c.maximize = parsed
				}
				'fullscreen' {
					c.fullscreen = parsed
				}
				'focus-follows-mouse' {
					c.focus_follows_mouse = parsed
				}
				'window-inherit-working-directory' {
					c.window_inherit_working_directory = parsed
				}
				'tab-inherit-working-directory' {
					c.tab_inherit_working_directory = parsed
				}
				'split-inherit-working-directory' {
					c.split_inherit_working_directory = parsed
				}
				'window-inherit-font-size' {
					c.window_inherit_font_size = parsed
				}
				'window-step-resize' {
					c.window_step_resize = parsed
				}
				'initial-window' {
					c.initial_window = parsed
				}
				'quick-terminal-autohide' {
					c.quick_terminal_autohide = parsed
				}
				'quit-after-last-window-closed' {
					c.quit_after_last_window_closed = parsed
				}
				'config-default-files' {
					c.config_default_files = parsed
				}
				'linux-cgroup-hard-fail' {
					c.linux_cgroup_hard_fail = parsed
				}
				'gtk-opengl-debug' {
					c.gtk_opengl_debug = parsed
				}
				'gtk-titlebar' {
					c.gtk_titlebar = parsed
				}
				'gtk-titlebar-hide-when-maximized' {
					c.gtk_titlebar_hide_when_maximized = parsed
				}
				'gtk-wide-tabs' {
					c.gtk_wide_tabs = parsed
				}
				'_xdg-terminal-exec' {
					c.xdg_terminal_exec = parsed
				}
				else {}
			}
		}
		'click-repeat-interval', 'image-storage-limit' {
			parsed := c.parse_config_u32(key, value) or { return }
			match key {
				'click-repeat-interval' {
					c.click_repeat_interval = parsed
				}
				'image-storage-limit' {
					c.image_storage_limit = parsed
				}
				else {}
			}
		}
		'font-thicken-strength' {
			c.font_thicken_strength = c.parse_config_u8(key, value) or { return }
		}
		'background-image-opacity', 'quick-terminal-animation-duration' {
			parsed := c.parse_config_f64(key, value) or { return }
			match key {
				'background-image-opacity' {
					c.background_image_opacity = f32(parsed)
				}
				'quick-terminal-animation-duration' {
					c.quick_terminal_animation_duration = parsed
				}
				else {}
			}
		}
		'mouse-scroll-multiplier' {
			if value.len == 0 {
				c.mouse_scroll_multiplier = MouseScrollMultiplier{}
			} else {
				c.mouse_scroll_multiplier.parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'clipboard-read', 'clipboard-write' {
			parsed := match value {
				'allow' { ClipboardAccess.allow }
				'ask' { ClipboardAccess.ask }
				'deny' { ClipboardAccess.deny }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
			if key == 'clipboard-read' {
				c.clipboard_read = parsed
			} else {
				c.clipboard_write = parsed
			}
		}
		'copy-on-select' {
			c.copy_on_select = match value {
				'false', '0', 'f', 'F' { .false_ }
				'true', '1', 't', 'T' { .true_ }
				'clipboard' { .clipboard }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'confirm-close-surface' {
			c.confirm_close_surface = match value {
				'always' { .always }
				'false', '0', 'f', 'F' { .false_ }
				'true', '1', 't', 'T' { .true_ }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'mouse-shift-capture' {
			c.mouse_shift_capture = match value {
				'never' { .never }
				'always' { .always }
				'false', '0', 'f', 'F' { .false_ }
				'true', '1', 't', 'T' { .true_ }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'shell-integration' {
			c.shell_integration = parse_shell_integration(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'link-previews' {
			c.link_previews = match value {
				'false', '0', 'f', 'F' { .false_ }
				'true', '1', 't', 'T' { .true_ }
				'osc8' { .osc8 }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'grapheme-width-method' {
			c.grapheme_width_method = match value {
				'legacy' { .legacy }
				'unicode' { .unicode }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'scrollbar' {
			c.scrollbar = match value {
				'system' { .system }
				'never' { .never }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'notify-on-command-finish' {
			c.notify_on_command_finish = match value {
				'never' { .never }
				'unfocused' { .unfocused }
				'always' { .always }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'notify-on-command-finish-action' {
			c.notify_on_command_finish_action = parse_notify_on_command_finish_action(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'notify-on-command-finish-after' {
			c.notify_on_command_finish_after = Duration.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'cursor-style' {
			c.cursor_style = match value {
				'block' { .block }
				'bar' { .bar }
				'underline' { .underline }
				'block_hollow' { .block_hollow }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'cursor-style-blink' {
			c.cursor_style_blink = if value.len == 0 {
				none
			} else {
				c.parse_config_bool(key, value) or { return }
			}
		}
		'window-padding-color' {
			c.window_padding_color = match value {
				'background' { .background }
				'extend' { .extend }
				'extend-always' { .extend_always }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'window-colorspace' {
			c.window_colorspace = match value {
				'srgb' { .srgb }
				'display-p3' { .display_p3 }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'alpha-blending' {
			c.alpha_blending = match value {
				'native' { .native }
				'linear' { .linear }
				'linear-corrected' { .linear_corrected }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'background-blur' {
			c.background_blur = background_blur_parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'background-image-position' {
			c.background_image_position = parse_background_image_position(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'background-image-fit' {
			c.background_image_fit = match value {
				'contain' { .contain }
				'cover' { .cover }
				'stretch' { .stretch }
				'none' { .none_ }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'window-decoration' {
			c.window_decoration = WindowDecoration.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'window-subtitle' {
			c.window_subtitle = match value {
				'false' { .false_ }
				'working-directory' { .working_directory }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'window-new-tab-position' {
			c.window_new_tab_position = match value {
				'current' { .current }
				'end' { .end }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'quit-after-last-window-closed-delay' {
			if value.len == 0 {
				c.quit_after_last_window_closed_delay = none
			} else {
				c.quit_after_last_window_closed_delay = Duration.parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'window-show-tab-bar' {
			c.window_show_tab_bar = match value {
				'always' { .always }
				'auto' { .auto }
				'never' { .never }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'resize-overlay' {
			c.resize_overlay = match value {
				'always' { .always }
				'never' { .never }
				'after-first' { .after_first }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'resize-overlay-position' {
			c.resize_overlay_position = match value {
				'center' { .center }
				'top-left' { .top_left }
				'top-center' { .top_center }
				'top-right' { .top_right }
				'bottom-left' { .bottom_left }
				'bottom-center' { .bottom_center }
				'bottom-right' { .bottom_right }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'resize-overlay-duration' {
			c.resize_overlay_duration = Duration.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'quick-terminal-position' {
			c.quick_terminal_position = match value {
				'top' { .top }
				'bottom' { .bottom }
				'left' { .left }
				'right' { .right }
				'center' { .center }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'quick-terminal-size' {
			c.quick_terminal_size.parse_cli(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'gtk-quick-terminal-layer' {
			c.gtk_quick_terminal_layer = match value {
				'overlay' { .overlay }
				'top' { .top }
				'bottom' { .bottom }
				'background' { .background }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'quick-terminal-screen' {
			c.quick_terminal_screen = match value {
				'main' { .main }
				'mouse' { .mouse }
				'macos-menu-bar' { .macos_menu_bar }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'quick-terminal-space-behavior' {
			c.quick_terminal_space_behavior = match value {
				'remain' { .remain }
				'move' { .move }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'quick-terminal-keyboard-interactivity' {
			c.quick_terminal_keyboard_interactivity = match value {
				'none' { .none_ }
				'on-demand' { .on_demand }
				'exclusive' { .exclusive }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'right-click-action' {
			c.right_click_action = parse_right_click_action(value) or {
				c.invalid_config_value(key, value)
				return
			}
		}
		'osc-color-report-format' {
			c.osc_color_report_format = match value {
				'none' { .none_ }
				'8-bit' { .format_8_bit }
				'16-bit' { .format_16_bit }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'custom-shader-animation' {
			c.custom_shader_animation = match value {
				'false', '0', 'f', 'F' { .false_ }
				'true', '1', 't', 'T' { .true_ }
				'always' { .always }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}

		// --- Compatibility handlers for removed/renamed options ---
		// These faithfully translate the CompatibilityHandler entries in
		// Config.zig. They run at parse time and remap deprecated options to
		// their modern equivalents.
		'background-blur-radius' {
			// Witty 1.1 renamed this field to background-blur. The generic
			// renamed-field handler parses the value using the replacement
			// field's type, including resetting an explicitly empty value to the
			// replacement field's declared default.
			if value.len == 0 {
				c.background_blur = BackgroundBlurFalse{}
			} else {
				c.background_blur = background_blur_parse_cli(value) or {
					// A failed renamed-field handler falls through to the original
					// unknown-field diagnostic.
					c.diagnostics << Diagnostic{
						message: '${key}: unknown field'
					}
					return
				}
			}
		}
		'adw-toolbar-style' {
			// Witty 1.2 renamed the libadwaita-prefixed option to its GTK
			// spelling.
			c.gtk_toolbar_style = match value {
				'' { .raised }
				'flat' { .flat }
				'raised' { .raised }
				'raised-border' { .raised_border }
				else {
					c.diagnostics << Diagnostic{
						message: '${key}: unknown field'
					}
					return
				}
			}
		}
		'cursor-invert-fg-bg' {
			// Witty 1.2 removed cursor-invert-fg-bg in favor of setting
			// cursor-color/cursor-text to the cell colors.
			set := parse_bool_opt(if value.len == 0 { 't' } else { value }) or {
				c.diagnostics << Diagnostic{
					message: '${key}: unknown field'
				}
				return
			}
			if set {
				c.cursor_color = TerminalColorCellForeground{}
				c.cursor_text = TerminalColorCellBackground{}
			}
		}
		'selection-invert-fg-bg' {
			set := parse_bool_opt(if value.len == 0 { 't' } else { value }) or {
				c.diagnostics << Diagnostic{
					message: '${key}: unknown field'
				}
				return
			}
			if set {
				c.selection_foreground = TerminalColorCellBackground{}
				c.selection_background = TerminalColorCellForeground{}
			}
		}
		'bold-is-bright' {
			// Witty 1.2 merged bold-is-bright into bold-color = bright.
			set := parse_bool_opt(if value.len == 0 { 't' } else { value }) or {
				c.diagnostics << Diagnostic{
					message: '${key}: unknown field'
				}
				return
			}
			if set {
				c.bold_color = BoldColorBright{}
			}
		}
		'macos-non-native-fullscreen' {
			c.macos_non_native_fullscreen = match value {
				'' { .false_ }
				'false' { .false_ }
				'true' { .true_ }
				'visible-menu' { .visible_menu }
				'padded-notch' { .padded_notch }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-window-buttons' {
			c.macos_window_buttons = match value {
				'' { .visible }
				'visible' { .visible }
				'hidden' { .hidden }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-titlebar-style' {
			c.macos_titlebar_style = match value {
				'' { .transparent }
				'native' { .native }
				'transparent' { .transparent }
				'tabs' { .tabs }
				'hidden' { .hidden }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-titlebar-proxy-icon' {
			c.macos_titlebar_proxy_icon = match value {
				'' { .visible }
				'visible' { .visible }
				'hidden' { .hidden }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-dock-drop-behavior' {
			// Witty 1.3 renamed the "window" option to "new-window".
			if value.len == 0 {
				c.macos_dock_drop_behavior = .new_tab
			} else if value == 'window' {
				c.macos_dock_drop_behavior = .new_window
			} else {
				match value {
					'new-tab' {
						c.macos_dock_drop_behavior = .new_tab
					}
					'new-window' {
						c.macos_dock_drop_behavior = .new_window
					}
					else {
						c.invalid_config_value(key, value)
						return
					}
				}
			}
		}
		'macos-option-as-alt' {
			if value.len == 0 {
				c.macos_option_as_alt = none
			} else {
				c.macos_option_as_alt = match value {
					'false' { inputpkg.OptionAsAlt.false_ }
					'true' { inputpkg.OptionAsAlt.true_ }
					'left' { inputpkg.OptionAsAlt.left }
					'right' { inputpkg.OptionAsAlt.right }
					else {
						c.invalid_config_value(key, value)
						return
					}
				}
			}
		}
		'macos-window-shadow' {
			c.macos_window_shadow = if value.len == 0 {
				true
			} else {
				c.parse_config_bool(key, value) or { return }
			}
		}
		'macos-hidden' {
			c.macos_hidden = match value {
				'' { .never }
				'never' { .never }
				'always' { .always }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-auto-secure-input' {
			c.macos_auto_secure_input = if value.len == 0 {
				true
			} else {
				c.parse_config_bool(key, value) or { return }
			}
		}
		'macos-secure-input-indication' {
			c.macos_secure_input_indication = if value.len == 0 {
				true
			} else {
				c.parse_config_bool(key, value) or { return }
			}
		}
		'macos-icon' {
			c.macos_icon = match value {
				'' { .official }
				'official' { .official }
				'blueprint' { .blueprint }
				'chalkboard' { .chalkboard }
				'microchip' { .microchip }
				'glass' { .glass }
				'holographic' { .holographic }
				'paper' { .paper }
				'retro' { .retro }
				'xray' { .xray }
				'custom' { .custom }
				'custom-style' { .custom_style }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-custom-icon' {
			c.macos_custom_icon = if value.len == 0 { none } else { value }
		}
		'macos-icon-frame' {
			c.macos_icon_frame = match value {
				'' { .aluminum }
				'aluminum' { .aluminum }
				'beige' { .beige }
				'plastic' { .plastic }
				'chrome' { .chrome }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-icon-ghost-color' {
			if value.len == 0 {
				c.macos_icon_ghost_color = none
			} else {
				c.macos_icon_ghost_color = color_parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'macos-icon-screen-color' {
			if value.len == 0 {
				c.macos_icon_screen_color = none
			} else {
				mut colors := ColorList{}
				colors.parse_cli(value) or {
					c.invalid_config_value(key, value)
					return
				}
				c.macos_icon_screen_color = colors
			}
		}
		'macos-shortcuts' {
			c.macos_shortcuts = match value {
				'' { .ask }
				'allow' { .allow }
				'deny' { .deny }
				'ask' { .ask }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'linux-cgroup' {
			c.linux_cgroup = match value {
				'never' { .never }
				'always' { .always }
				'single-instance' { .single_instance }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'linux-cgroup-memory-limit' {
			if value.len == 0 {
				c.linux_cgroup_memory_limit = none
			} else {
				c.linux_cgroup_memory_limit = c.parse_config_u64(key, value) or { return }
			}
		}
		'linux-cgroup-processes-limit' {
			if value.len == 0 {
				c.linux_cgroup_processes_limit = none
			} else {
				c.linux_cgroup_processes_limit = c.parse_config_u64(key, value) or { return }
			}
		}
		'gtk-single-instance' {
			// Witty 1.2 kept `desktop` as a compatibility value that finalize
			// later converts. Before finalize it remains `detect`.
			match value {
				'desktop', 'detect' {
					c.gtk_single_instance = .detect
				}
				'true', 't', '1' {
					c.gtk_single_instance = .true_
				}
				'false', 'f', '0' {
					c.gtk_single_instance = .false_
				}
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'gtk-tabs-location' {
			match value {
				'top' {
					c.gtk_tabs_location = .top
				}
				'bottom' {
					c.gtk_tabs_location = .bottom
				}
				'hidden' {
					// Witty 1.2 removed this enum value and its compatibility
					// handler maps it to the replacement setting.
					c.window_show_tab_bar = .never
				}
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'gtk-toolbar-style' {
			c.gtk_toolbar_style = match value {
				'flat' { .flat }
				'raised' { .raised }
				'raised-border' { .raised_border }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		'gtk-titlebar-style' {
			c.gtk_titlebar_style = match value {
				'native' { .native }
				'tabs' { .tabs }
				else {
					c.invalid_config_value(key, value)
					return
				}
			}
		}
		else {
			// Config's reflected CLI parser reports unknown fields as a
			// diagnostic. Platform-specific fields are still present in Config,
			// so silently accepting a misspelling would diverge from Witty and
			// make `+validate-config` incorrectly succeed.
			c.diagnostics << Diagnostic{
				message: '${key}: unknown field'
			}
		}
	}
}

// apply_kv_missing translates cli.args.parseIntoField when an argument has no
// `=value` portion. Plain and optional booleans use the CLI flag convention of
// true. The few custom Config parsers that intentionally accept null retain
// their source behavior; all other known fields report a required value.
fn (mut c Config) apply_kv_missing(key string) {
	if is_boolean_config_key(key) {
		c.apply_kv(key, 'true')
		return
	}

	match key {
		'background-blur', 'background-blur-radius' {
			c.background_blur = BackgroundBlurTrue{}
		}
		'window-decoration' {
			c.window_decoration = .auto
		}
		'command-palette-entry' {
			c.command_palette_entry = RepeatableCommand{}
		}
		'cursor-invert-fg-bg' {
			c.cursor_color = TerminalColorCellForeground{}
			c.cursor_text = TerminalColorCellBackground{}
		}
		'selection-invert-fg-bg' {
			c.selection_foreground = TerminalColorCellBackground{}
			c.selection_background = TerminalColorCellForeground{}
		}
		'bold-is-bright' {
			c.bold_color = BoldColorBright{}
		}
		'adw-toolbar-style' {
			// compatibilityRenamed fails because the destination enum requires a
			// value, then the original unknown-field error is reported.
			c.diagnostics << Diagnostic{
				message: '${key}: unknown field'
			}
		}
		else {
			message := if is_config_key(key) {
				'value required for ${key}'
			} else {
				'${key}: unknown field'
			}
			c.diagnostics << Diagnostic{
				message: message
			}
		}
	}
}

fn is_config_key(key string) bool {
	normalized_key := key.replace('-', '_')
	$for field in Config.fields {
		if field.name == normalized_key
			&& field.name !in ['diagnostics', 'conditional_state', 'conditional_set', 'replay_steps',
				'xdg_terminal_exec', 'capi_strings'] {
			return true
		}
	}
	return false
}

// reset_empty_config_value translates cli.args.parseIntoField's empty-value
// path. Config.default_config represents the source-level field defaults,
// including platform-dependent values and types whose Zig defaults are backed
// by static data. Internal bookkeeping fields are deliberately excluded from
// reflected config lookup, just like Witty's underscore-prefixed fields.
fn (mut c Config) reset_empty_config_value(key string) bool {
	// RepeatableLink has no usable parser yet in the pinned source, but an empty
	// value is accepted by the generic reset path and restores its field default
	// (an empty list), not Config.default's appended URL matcher.
	if key == 'link' {
		c.link = RepeatableLink{}
		return true
	}

	// This source field intentionally starts with an underscore and is handled
	// by Config's manual parser hook.
	if key == '_xdg-terminal-exec' {
		c.xdg_terminal_exec = false
		return true
	}

	normalized_key := key.replace('-', '_')
	defaults := Config.default_config()
	return reset_config_field(mut c, defaults, normalized_key)
}

// reset_config_field is generic over the config type because V 0.5.2 master
// rejects comptime enum field assignment in non-generic functions.
fn reset_config_field[T](mut c T, defaults T, normalized_key string) bool {
	$for field in T.fields {
		$if !field.is_map {
			if field.name == normalized_key
				&& field.name !in ['diagnostics', 'conditional_state', 'replay_steps',
					'xdg_terminal_exec'] {
				c.$(field.name) = defaults.$(field.name)
				return true
			}
		}
	}
	return false
}

// apply_repeatable_string implements the repeatable-string parser used by
// font-feature: an empty value clears all values and every other value appends.
fn apply_repeatable_string(mut list []string, value string) {
	if value.len == 0 {
		list.clear()
		return
	}
	list << value
}

// apply_env implements RepeatableStringMap.parseCLI. Entries retain insertion
// order, assigning an existing key replaces its value, an empty value removes
// that key, and an entirely empty option clears the map.
fn (mut c Config) apply_env(value string) {
	c.env.parse_cli(value) or {
		c.invalid_config_value('env', value)
	}
}

fn (mut c Config) invalid_config_value(key string, value string) {
	c.diagnostics << Diagnostic{
		message: 'invalid value for "${key}": ${value}'
	}
}

fn (mut c Config) parse_config_bool(key string, value string) ?bool {
	return parse_bool_opt(value) or {
		c.invalid_config_value(key, value)
		return none
	}
}

fn (mut c Config) parse_config_u32(key string, value string) ?u32 {
	parsed := cli_args.parse_unsigned_int(value, 32) or {
		c.invalid_config_value(key, value)
		return none
	}
	return u32(parsed)
}

fn (mut c Config) parse_config_u64(key string, value string) ?u64 {
	parsed := cli_args.parse_unsigned_int(value, 64) or {
		c.invalid_config_value(key, value)
		return none
	}
	return parsed
}

fn (mut c Config) parse_config_u8(key string, value string) ?u8 {
	parsed := cli_args.parse_unsigned_int(value, 8) or {
		c.invalid_config_value(key, value)
		return none
	}
	return u8(parsed)
}

fn (mut c Config) parse_config_i16(key string, value string) ?i16 {
	parsed := cli_args.parse_signed_int(value, 16) or {
		c.invalid_config_value(key, value)
		return none
	}
	return i16(parsed)
}

fn (mut c Config) parse_config_f64(key string, value string) ?f64 {
	parsed := zig_fmt.parse_f64(value) or {
		c.invalid_config_value(key, value)
		return none
	}
	return parsed
}

// Packed boolean structs start from their declared defaults. A standalone
// boolean sets every field; otherwise comma-separated names toggle individual
// fields and the no- prefix disables one.
fn parse_font_shaping_break(value string) ?FontShapingBreak {
	if b := parse_bool_opt(value) {
		return FontShapingBreak.init(b)
	}
	mut result := FontShapingBreak{}
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		if name != 'cursor' {
			return none
		}
		result = FontShapingBreak.init(!negative)
	}
	return result
}

fn parse_split_preserve_zoom(value string) ?SplitPreserveZoom {
	if b := parse_bool_opt(value) {
		return SplitPreserveZoom.init(b)
	}
	mut result := SplitPreserveZoom{}
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		if name != 'navigation' {
			return none
		}
		result = SplitPreserveZoom.init(!negative)
	}
	return result
}

fn parse_font_synthetic_style(value string) ?font.FontSyntheticStyle {
	if b := parse_bool_opt(value) {
		return font.FontSyntheticStyle.init(b, b, b)
	}
	mut bold := true
	mut italic := true
	mut bold_italic := true
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		match name {
			'bold' {
				bold = !negative
			}
			'italic' {
				italic = !negative
			}
			'bold-italic' {
				bold_italic = !negative
			}
			else {
				return none
			}
		}
	}
	return font.FontSyntheticStyle.init(bold, italic, bold_italic)
}

fn parse_freetype_load_flags(value string) ?font.FreetypeLoadFlags {
	if b := parse_bool_opt(value) {
		return font.FreetypeLoadFlags.init(b, b, b, b, b)
	}
	mut hinting := true
	mut force_autohint := false
	mut monochrome := false
	mut autohint := true
	mut light := true
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		match name {
			'hinting' {
				hinting = !negative
			}
			'force-autohint' {
				force_autohint = !negative
			}
			'monochrome' {
				monochrome = !negative
			}
			'autohint' {
				autohint = !negative
			}
			'light' {
				light = !negative
			}
			else {
				return none
			}
		}
	}
	return font.FreetypeLoadFlags.init(hinting, force_autohint, monochrome, autohint, light)
}

fn metric_modifier_parse_cli(value string) !font.MetricsModifier {
	return font.MetricsModifier.parse_cli(value) or { return perr(ParseError.invalid_value) }
}

fn parse_shell_integration_features(value string) ?ShellIntegrationFeatures {
	if b := parse_bool_opt(value) {
		return ShellIntegrationFeatures.init(b, b, b, b, b, b)
	}
	mut cursor := true
	mut sudo := false
	mut title := true
	mut ssh_env := false
	mut ssh_terminfo := false
	mut path := true
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		enabled := !negative
		match name {
			'cursor' {
				cursor = enabled
			}
			'sudo' {
				sudo = enabled
			}
			'title' {
				title = enabled
			}
			'ssh-env' {
				ssh_env = enabled
			}
			'ssh-terminfo' {
				ssh_terminfo = enabled
			}
			'path' {
				path = enabled
			}
			else {
				return none
			}
		}
	}
	return ShellIntegrationFeatures.init(cursor, sudo, title, ssh_env, ssh_terminfo, path)
}

fn parse_bell_features(value string) ?BellFeatures {
	if b := parse_bool_opt(value) {
		return BellFeatures.init(b, b, b, b, b)
	}
	mut system := false
	mut audio := false
	mut attention := true
	mut title := true
	mut border := false
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		enabled := !negative
		match name {
			'system' {
				system = enabled
			}
			'audio' {
				audio = enabled
			}
			'attention' {
				attention = enabled
			}
			'title' {
				title = enabled
			}
			'border' {
				border = enabled
			}
			else {
				return none
			}
		}
	}
	return BellFeatures.init(system, audio, attention, title, border)
}

fn parse_app_notifications(value string) ?AppNotifications {
	if b := parse_bool_opt(value) {
		return AppNotifications.init(b, b)
	}
	mut clipboard_copy := true
	mut config_reload := true
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		enabled := !negative
		match name {
			'clipboard-copy' {
				clipboard_copy = enabled
			}
			'config-reload' {
				config_reload = enabled
			}
			else {
				return none
			}
		}
	}
	return AppNotifications.init(clipboard_copy, config_reload)
}

fn parse_notify_on_command_finish_action(value string) ?NotifyOnCommandFinishAction {
	if b := parse_bool_opt(value) {
		return NotifyOnCommandFinishAction.init(b, b)
	}
	mut bell := true
	mut notify := false
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		enabled := !negative
		match name {
			'bell' {
				bell = enabled
			}
			'notify' {
				notify = enabled
			}
			else {
				return none
			}
		}
	}
	return NotifyOnCommandFinishAction.init(bell, notify)
}

fn parse_scroll_to_bottom(value string) ?ScrollToBottom {
	if b := parse_bool_opt(value) {
		return ScrollToBottom.init(b, b)
	}
	mut keystroke := true
	mut output := false
	for raw in value.split(',') {
		part := raw.trim(' \t')
		negative := part.starts_with('no-')
		name := if negative { part[3..] } else { part }
		enabled := !negative
		match name {
			'keystroke' {
				keystroke = enabled
			}
			'output' {
				output = enabled
			}
			else {
				return none
			}
		}
	}
	return ScrollToBottom.init(keystroke, output)
}

fn parse_shell_integration(value string) ?ShellIntegration {
	return match value {
		'detect' { ShellIntegration.detect }
		'none' { ShellIntegration.none_ }
		'bash' { ShellIntegration.bash }
		'elvish' { ShellIntegration.elvish }
		'fish' { ShellIntegration.fish }
		'nushell' { ShellIntegration.nushell }
		'zsh' { ShellIntegration.zsh }
		else { none }
	}
}

fn parse_background_image_position(value string) ?BackgroundImagePosition {
	return match value {
		'top-left' { BackgroundImagePosition.top_left }
		'top-center' { BackgroundImagePosition.top_center }
		'top-right' { BackgroundImagePosition.top_right }
		'center-left' { BackgroundImagePosition.center_left }
		'center-center' { BackgroundImagePosition.center_center }
		'center' { BackgroundImagePosition.center }
		'center-right' { BackgroundImagePosition.center_right }
		'bottom-left' { BackgroundImagePosition.bottom_left }
		'bottom-center' { BackgroundImagePosition.bottom_center }
		'bottom-right' { BackgroundImagePosition.bottom_right }
		else { none }
	}
}

fn parse_right_click_action(value string) ?RightClickAction {
	return match value {
		'ignore' { RightClickAction.ignore }
		'paste' { RightClickAction.paste }
		'copy' { RightClickAction.copy }
		'copy-or-paste' { RightClickAction.copy_or_paste }
		'context-menu' { RightClickAction.context_menu }
		else { none }
	}
}

// apply_font_family_value appends a font family fallback. Setting the value
// to an empty string resets the list.
fn (c Config) apply_font_family_value(mut list []string, value string) {
	if value.len == 0 {
		list.clear()
		return
	}
	list << value
}

// apply_palette parses a palette entry of the form `N=COLOR` where N is a
// palette index (0-255) and COLOR is a hex color.
fn (mut c Config) apply_palette(value string) {
	inner_eq := value.index('=') or {
		c.diagnostics << Diagnostic{
			message: 'invalid palette entry (missing "="): ${value}'
		}
		return
	}
	idx_str := value[..inner_eq].trim(' \t')
	col_str := value[inner_eq + 1..].trim(' \t')
	idx := parse_palette_index(idx_str) or {
		kind := parse_error_of(err) or { ParseError.invalid_value }
		message := if kind == ParseError.overflow {
			'palette index out of range (0-255): ${idx_str}'
		} else {
			'invalid palette index: ${idx_str}'
		}
		c.diagnostics << Diagnostic{ message: message }
		return
	}
	col := parse_color(col_str) or {
		c.diagnostics << Diagnostic{
			message: 'invalid palette color: ${col_str}'
		}
		return
	}
	c.palette.value[idx] = col
}

// parse_palette_index parses a palette index in decimal, binary (`0b`),
// octal (`0o`), or hexadecimal (`0x`) notation.
fn parse_palette_index(s string) !int {
	n := cli_args.parse_unsigned_int(s, 8) or {
		if err.msg() == 'overflow' {
			return perr(ParseError.overflow)
		}
		return perr(ParseError.invalid_value)
	}
	return int(n)
}

// hex_digit returns the numeric value of a hex digit character, or none.
fn hex_digit(ch u8) ?int {
	return match ch {
		`0`...`9` { int(ch - `0`) }
		`a`...`f` { int(ch - `a` + 10) }
		`A`...`F` { int(ch - `A` + 10) }
		else { none }
	}
}

// parse_color is the optional-return adapter used by the config reader. The
// public parser handles short/long hex values and the complete X11 color set.
fn parse_color(value string) ?ColorRGB {
	return color_parse_cli(value) or { return none }
}

// parse_hex_byte parses a two-character hex string into a byte.
fn parse_hex_byte(s string) ?u8 {
	if s.len != 2 {
		return none
	}
	hi := hex_digit(s[0]) or { return none }
	lo := hex_digit(s[1]) or { return none }
	return u8(hi * 16 + lo)
}

// finalize applies defaults and clamps values after loading.
pub fn (mut c Config) finalize() ! {
	// Load a referenced theme file, if any. This is done first so that the
	// theme's options act as a lower-priority base layer beneath explicitly
	// set config options.
	if theme := c.theme {
		different := theme.light != theme.dark
		c.load_theme(theme)!
		if different {
			if c.window_theme == .auto {
				c.window_theme = .system
			}
			c.conditional_set['theme'] = true
		}
	}

	// If a font-family is set and the style-specific families are not, default
	// them to the primary family so styled variants are searched for too.
	if c.font_family.len > 0 {
		if c.font_family_bold.len == 0 {
			c.font_family_bold = c.font_family.clone()
		}
		if c.font_family_italic.len == 0 {
			c.font_family_italic = c.font_family.clone()
		}
		if c.font_family_bold_italic.len == 0 {
			c.font_family_bold_italic = c.font_family.clone()
		}
	}

	// Prevent setting TERM to an empty string.
	if c.term.len == 0 {
		c.term = 'xterm-witty'
	}

	// The default working directory depends on whether this looks like a CLI
	// launch. Desktop launches use the account home; CLI launches inherit.
	probable_cli := probable_cli_environment()
	wd := c.working_directory or {
		if probable_cli { 'inherit' } else { 'home' }
	}
	wd_home := wd == 'home'

	// Shell and passwd lookup are deliberately skipped in tests in Witty.
	$if !test {
		if c.command == none || wd_home {
			if c.command == none && !internal_os.is_flatpak() && probable_cli {
				if shell := os.getenv_opt('SHELL') {
					if shell.len > 0 {
						log.info('default shell source=env value=${shell}')
						c.command = Command(ShellCmd{ shell: shell })
					}
				}
			}

			$if windows {
				if c.command == none {
					log.warn('no default shell found, will default to using cmd')
					c.command = Command(ShellCmd{ shell: 'cmd.exe' })
				}
				if wd_home {
					if home := internal_os.home()!.value {
						c.working_directory = home
					}
				}
			} $else {
				passwd := internal_os.get()!
				if c.command == none {
					if shell := passwd.shell {
						log.info('default shell src=passwd value=${shell}')
						c.command = Command(ShellCmd{ shell: shell })
					}
				}
				if wd_home {
					if home := passwd.home {
						log.info('default working directory src=passwd value=${home}')
						c.working_directory = home
					}
				}
				if c.command == none {
					log.warn('no default shell found, will default to using sh')
				}
			}
		}
	}

	// Linux is Witty's GTK artifact, so this is the translated apprt-specific
	// default from Config.finalize.
	$if linux {
		if c.gtk_single_instance == .detect {
			c.gtk_single_instance = if probable_cli { .false_ } else { .true_ }
		}
	}

	// "inherit" is represented by null in the retained configuration.
	if wd == 'inherit' {
		c.working_directory = none
	}

	$if !test {
		if c.click_repeat_interval == 0 {
			c.click_repeat_interval = internal_os.click_interval() or { 500 }
		}
	}

	// Clamp both mouse scroll multipliers to [0.01, 10000].
	c.mouse_scroll_multiplier.precision = clamp_f64(c.mouse_scroll_multiplier.precision, 0.01, 10_000.0)
	c.mouse_scroll_multiplier.discrete = clamp_f64(c.mouse_scroll_multiplier.discrete, 0.01, 10_000.0)

	// Clamp the split opacity.
	c.unfocused_split_opacity = clamp_f64(c.unfocused_split_opacity, 0.15, 1.0)

	// Clamp the contrast.
	c.minimum_contrast = clamp_f64(c.minimum_contrast, 1.0, 21.0)

	// The first default link is always the URL matcher.
	if !c.link_url {
		c.link.links = c.link.links[1..].clone()
	}

	// Witty only clamps faint opacity at configuration finalization.
	c.faint_opacity = clamp_f64(c.faint_opacity, 0.0, 1.0)

	// Minimum window size.
	if c.window_width > 0 && c.window_width < 10 {
		c.window_width = 10
	}
	if c.window_height > 0 && c.window_height < 4 {
		c.window_height = 4
	}

	// Config.zig takes the compiled build_config.release_channel here, after
	// preserving any user selection. The build driver supplies that live value.
	if c.auto_update_channel == none {
		c.auto_update_channel = buildcfg.release_channel
	}

	// Sided mappings must be ordered before their unsided counterparts so
	// matching produces the same first-match result as Witty.
	c.key_remap.finalize()
}

// probable_cli_environment translates Config.probableCliEnvironment. Keep
// uses of this heuristic limited to the same startup defaults as the source.
fn probable_cli_environment() bool {
	$if windows {
		return false
	}
	$if macos {
		if internal_os.launched_from_desktop() {
			return false
		}
	}
	if term_program := os.getenv_opt('TERM_PROGRAM') {
		if term_program.len > 0 {
			return true
		}
	}
	return os.args.len > 1
}

// load_theme resolves the configured `theme`, loads it into a fresh default
// configuration, and replays every prior input over it. This is Witty's
// replay model and preserves parser semantics for scalars and repeatable
// values alike:
//
//   * A single theme name/path loads one file.
//   * A `light:...,dark:...` pair chooses based on the conditional state.
//   * Theme options never override explicitly-set config options.
//   * A light/dark pair changes `window-theme` from `auto` to `system`.
//
fn (mut c Config) load_theme(theme ThemePair) ! {
	state := c.conditional_state
	steps := clone_replay_steps(c.replay_steps)
	path := match state.theme {
		.light { theme.light }
		.dark { theme.dark }
	}

	// Resolve the theme before cloning. A recoverable open failure appends its
	// diagnostics to the existing configuration and otherwise leaves it intact.
	mut theme_diagnostics := diagnosticspkg.DiagnosticList{}
	opened := themepkg.open(path, mut theme_diagnostics) or {
		c.diagnostics << theme_diagnostics.items()
		return
	}
	assert theme_diagnostics.empty()
	mut file := opened.file
	defer {
		file.close()
	}

	mut rebuilt := c.clone_empty()
	content_bytes := io.read_all(reader: file)!
	rebuilt.load_string_with_path(content_bytes.bytestr(), opened.path)

	// Theme arguments are conditional on the state that selected this file.
	// Expansion and explicit diagnostics remain unconditional, just as in the
	// source Replay.Step union.
	for i in 0 .. rebuilt.replay_steps.len {
		step := rebuilt.replay_steps[i]
		match step {
			ReplayArg {
				rebuilt.replay_steps[i] = ReplayConditionalArg{
					conditions: [Conditional{
						key:   .theme
						op:    .eq
						value: state.theme.str()
					}]
					arg:        step.value
				}
			}
			ReplayConditionalArg {
				mut conditions := [Conditional{
					key:   .theme
					op:    .eq
					value: state.theme.str()
				}]
				conditions << step.conditions.map(it.clone())
				rebuilt.replay_steps[i] = ReplayConditionalArg{
					conditions: conditions
					arg:        step.arg
				}
			}
			ReplayCommand {
				break
			}
			else {}
		}
	}

	// Replay user/default-file inputs in their original order. The replay
	// itself records the yielded arguments and expansions into the new config,
	// preserving the newly conditional theme steps already present above.
	replay_steps_into(mut rebuilt, steps)

	c = rebuilt
}

// replay_steps_into is the translated Replay.Iterator side-effect loop. It
// reapplies recorded inputs without reopening files and evaluates every
// condition on a conditional argument as an AND.
fn replay_steps_into(mut destination Config, steps []ReplayStep) {
	mut iter := ReplayIterator.new(steps, mut destination)
	destination.load_iter(mut iter)
}

// clamp_f64 clamps v to the inclusive range [lo, hi].
fn clamp_f64(v f64, lo f64, hi f64) f64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// default_config creates a Config with default values.
pub fn Config.default_config() Config {
	mut result := Config{}
	$if !macos {
		result.alpha_blending = .linear_corrected
	}
	$if !macos && !linux {
		result.copy_on_select = .false_
	}
	result.keybind.init()
	result.command_palette_entry.init()
	result.selection_word_chars = SelectionWordChars.defaults()
	result.link = RepeatableLink{
		links: [inputpkg.Link{
			regex: default_url_pattern
			action: .open
			highlight: inputpkg.LinkHighlightHoverMods{
				mods: inputpkg.ctrl_or_super_mods(inputpkg.Mods{})
			}
		}]
	}
	return result
}

fn preferred_existing_config_path(paths []string) !string {
	assert paths.len > 0
	mut first_existing := ?string(none)
	for path in paths {
		mut file := os.open(path) or {
			if err.code() == C.ENOENT || err.code() == C.ENOTDIR {
				continue
			}
			return err
		}
		stat := os.stat(path) or {
			file.close()
			return err
		}
		file.close()
		if stat.size > 0 {
			return path
		}
		if first_existing == none {
			first_existing = path
		}
	}
	if path := first_existing {
		return path
	}
	return paths[0]
}

fn editable_config_path_candidates() ![]string {
	mut paths := []string{}
	$if macos {
		paths << default_app_support_path()!
		paths << previous_default_app_support_path()!
		paths << legacy_default_app_support_path()!
	}
	paths << default_xdg_path()!
	paths << previous_default_xdg_path()!
	paths << legacy_default_xdg_path()!
	return paths
}

// open_path returns the main configuration path and ensures it can be opened
// by an editor. It mirrors config/edit.zig openPath: choose the preferred
// existing path, create its parent directory, and create a missing file
// without changing the contents of an existing one.
pub fn open_path() !string {
	path := preferred_existing_config_path(editable_config_path_candidates()!)!
	ensure_editable_config_path(path)!
	return path
}

fn ensure_editable_config_path(path string) ! {
	directory := os.dir(path)
	if directory.len > 0 {
		os.mkdir_all(directory)!
	}
	create_config_file(path)!
}

// default_xdg_path returns Witty's current XDG configuration path.
pub fn default_xdg_path() !string {
	return internal_os.config(internal_os.Options{
		subdir: os.join_path('witty', 'config.witty')
	})
}

fn previous_default_xdg_path() !string {
	return internal_os.config(internal_os.Options{
		subdir: os.join_path('ghostty', 'config.ghostty')
	})
}

// legacy_default_xdg_path returns Witty's pre-1.3 XDG configuration path.
pub fn legacy_default_xdg_path() !string {
	return internal_os.config(internal_os.Options{
		subdir: os.join_path('ghostty', 'config')
	})
}

// preferred_xdg_path prefers the current non-empty configuration, then the
// legacy non-empty configuration, and otherwise returns the current path.
pub fn preferred_xdg_path() !string {
	path := default_xdg_path()!
	if mut file := open(path) {
		file.close()
		return path
	}
	for fallback in [previous_default_xdg_path()!, legacy_default_xdg_path()!] {
		if mut file := open(fallback) {
			file.close()
			return fallback
		}
	}
	return path
}

// default_app_support_path returns Witty's current macOS Application
// Support configuration path.
pub fn default_app_support_path() !string {
	$if macos {
		return internal_os.app_support_dir('config.witty')
	} $else {
		return error('Application Support is only available on macOS')
	}
}

// legacy_default_app_support_path returns Witty's pre-1.3 macOS
// Application Support configuration path.
pub fn legacy_default_app_support_path() !string {
	$if macos {
		return internal_os.previous_app_support_dir('config')
	} $else {
		return error('Application Support is only available on macOS')
	}
}

fn previous_default_app_support_path() !string {
	$if macos {
		return internal_os.previous_app_support_dir('config.ghostty')
	} $else {
		return error('Application Support is only available on macOS')
	}
}

// preferred_app_support_path applies the same non-empty preference as the XDG
// path pair.
pub fn preferred_app_support_path() !string {
	path := default_app_support_path()!
	if mut file := open(path) {
		file.close()
		return path
	}
	for fallback in [previous_default_app_support_path()!, legacy_default_app_support_path()!] {
		if mut file := open(fallback) {
			file.close()
			return fallback
		}
	}
	return path
}

// preferred_default_file_path returns the preferred default configuration
// file. macOS gives Application Support priority over XDG when either contains
// a non-empty configuration.
pub fn preferred_default_file_path() !string {
	$if macos {
		app_support_path := preferred_app_support_path()!
		if mut file := open(app_support_path) {
			file.close()
			return app_support_path
		}
		xdg_path := preferred_xdg_path()!
		if mut file := open(xdg_path) {
			file.close()
			return xdg_path
		}
		return app_support_path
	} $else {
		return preferred_xdg_path()
	}
}

pub enum OpenFileError {
	file_not_found = 1
	file_is_empty
	file_open_failed
	not_a_file
}

fn open_file_error(kind OpenFileError) IError {
	return error_with_code(kind.str().replace('_', ' '), int(kind))
}

// open_file_error_of returns the translated file-load error carried by err.
pub fn open_file_error_of(err IError) ?OpenFileError {
	code := err.code()
	if code >= int(OpenFileError.file_not_found) && code <= int(OpenFileError.not_a_file) {
		return unsafe { OpenFileError(code) }
	}
	return none
}

// open opens an absolute, non-empty regular file. Its deliberately small
// error set mirrors config/file_load.zig so callers can use it for preference
// selection without depending on platform-specific filesystem errors.
pub fn open(path string) !os.File {
	assert os.is_abs_path(path)
	mut file := os.open(path) or {
		if err.code() == int(C.ENOENT) {
			return open_file_error(.file_not_found)
		}
		return open_file_error(.file_open_failed)
	}
	stat := os.stat(path) or {
		file.close()
		return open_file_error(.file_open_failed)
	}
	if stat.get_filetype() != .regular {
		file.close()
		return open_file_error(.not_a_file)
	}
	if stat.size == 0 {
		file.close()
		return open_file_error(.file_is_empty)
	}
	return file
}

// ============================================================
// Ghostty config value-type parsers (translated from Config.zig)
// ============================================================

// ParseError enumerates the error cases used by Witty's `parseCLI`
// functions. Each parser returns one of these (as an error value whose `code()`
// is the enum value) on failure, so tests can assert on the specific error
// kind, mirroring Zig's error set.
pub enum ParseError {
	value_required     = 1
	invalid_value      = 2
	overflow           = 3
	too_many_arguments = 4
	missing_unit       = 5
}

// perr constructs an error value carrying the given ParseError kind. The kind
// is stored as the error `code()` and can be recovered with `parse_error_of`.
fn perr(kind ParseError) IError {
	return error_with_code(kind.str(), int(kind))
}

// parse_error_of returns the ParseError kind carried by an error value, or
// `none` if it isn't a ParseError.
pub fn parse_error_of(err IError) ?ParseError {
	code := err.code()
	if code >= int(ParseError.value_required) && code <= int(ParseError.missing_unit) {
		return unsafe { ParseError(code) }
	}
	return none
}

// color_from_hex parses a color from a hex value such as `#RRGGBB`. The `#`
// is optional and a 3-character short form (`#RGB`) is expanded. This is a
// faithful translation of `Color.fromHex`.
pub fn color_from_hex(input string) !ColorRGB {
	return ColorRGB.from_hex(input)
}

// color_parse_cli parses a color the way `Color.parseCLI` does: it trims
// surrounding whitespace, then tries a named X11 color, then a hex value.
pub fn color_parse_cli(input string) !ColorRGB {
	return ColorRGB.parse_cli(input)
}

// named_x11_color resolves the complete embedded X.Org rgb.txt table.
fn named_x11_color(name string) ?ColorRGB {
	if rgb := terminal.x11_color_get(name) {
		return ColorRGB{
			r: rgb.r
			g: rgb.g
			b: rgb.b
		}
	}
	return none
}

// format_color renders a color as `#rrggbb` (lowercase), matching
// `Color.formatBuf`.
pub fn format_color(c ColorRGB) string {
	return c.format_buf()
}

// ------------------------------------------------------------
// TerminalColor
// ------------------------------------------------------------

// terminal_color_parse_cli translates `TerminalColor.parseCLI`.
pub fn terminal_color_parse_cli(input string) !TerminalColor {
	return TerminalColor.parse_cli(input)
}

// bold_color_parse_cli translates `BoldColor.parseCLI`.
pub fn bold_color_parse_cli(input ?string) !BoldColor {
	return BoldColor.parse_cli(input)
}

// ------------------------------------------------------------
// Duration
// ------------------------------------------------------------

struct DurationUnit {
	name   string
	factor u64
}

// duration_units mirrors Witty's `Duration.units`. Order matters: the first
// matching factor is the default unit used for formatting.
const duration_units = [
	DurationUnit{'y', u64(365) * 24 * 60 * 60 * 1_000_000_000},
	DurationUnit{'w', u64(7) * 24 * 60 * 60 * 1_000_000_000},
	DurationUnit{'d', u64(24) * 60 * 60 * 1_000_000_000},
	DurationUnit{'h', u64(60) * 60 * 1_000_000_000},
	DurationUnit{'m', u64(60) * 1_000_000_000},
	DurationUnit{'s', u64(1_000_000_000)},
	DurationUnit{'ms', u64(1_000_000)},
	DurationUnit{'µs', u64(1_000)},
	DurationUnit{'us', u64(1_000)},
	DurationUnit{'ns', u64(1)},
]

const u64_max = u64(18446744073709551615)

fn is_ascii_whitespace(ch u8) bool {
	return ch == ` ` || ch == `\t` || ch == `\n` || ch == `\r` || ch == 0x0b || ch == 0x0c
}

// saturating_mul multiplies two u64 saturating to u64_max on overflow.
fn saturating_mul(a u64, b u64) u64 {
	if a == 0 || b == 0 {
		return 0
	}
	if a > u64_max / b {
		return u64_max
	}
	return a * b
}

// saturating_add adds two u64 saturating to u64_max on overflow.
fn saturating_add(a u64, b u64) u64 {
	if a > u64_max - b {
		return u64_max
	}
	return a + b
}

// duration_parse_cli translates `Duration.parseCLI`. It accepts a series of
// number+unit pairs (with optional whitespace) and returns the total number
// of nanoseconds, saturating on overflow.
pub fn duration_parse_cli(input ?string) !Duration {
	mut remaining := input or { return perr(ParseError.value_required) }
	mut value := ?u64(none)

	for remaining.len > 0 {
		// Skip whitespace before the number.
		for remaining.len > 0 && is_ascii_whitespace(remaining[0]) {
			remaining = remaining[1..]
		}
		if remaining.len == 0 {
			break
		}

		// Find the longest leading unsigned integer.
		mut number := ?u64(none)
		mut num_len := 0
		for i := 1; i <= remaining.len; i++ {
			n := parse_uint(remaining[0..i]) or { break }
			number = n
			num_len = i
		}
		num := number or { return perr(ParseError.invalid_value) }
		remaining = remaining[num_len..]

		// A bare number is only valid if it's exactly zero.
		if remaining.len == 0 {
			if num == 0 {
				value = u64(0)
				break
			}
			return perr(ParseError.invalid_value)
		}

		// Find the longest matching unit (to distinguish `m` from `ms`).
		mut factor := ?u64(none)
		mut factor_len := 0
		for i := 1; i <= remaining.len; i++ {
			cand := remaining[0..i]
			for unit in duration_units {
				if unit.name == cand {
					factor = unit.factor
					factor_len = i
					break
				}
			}
		}
		f := factor or { return perr(ParseError.invalid_value) }
		remaining = remaining[factor_len..]

		diff := saturating_mul(num, f)
		value = saturating_add(value or { u64(0) }, diff)
	}

	if v := value {
		return Duration{
			duration: v
		}
	}
	return perr(ParseError.value_required)
}

pub fn Duration.parse_cli(input ?string) !Duration {
	return duration_parse_cli(input)
}

// duration_format renders a Duration the way `Duration.format` does, e.g.
// `1h30m`. `us` is always rendered as `µs`.
pub fn (d Duration) format() string {
	mut value := d.duration
	mut out := ''
	mut i := 0
	for unit in duration_units {
		// Skip the duplicate `us` alias so we never emit it (µs comes first).
		if unit.name == 'us' {
			continue
		}
		if value >= unit.factor {
			if i > 0 {
				out += ' '
			}
			remainder := value % unit.factor
			quotient := (value - remainder) / unit.factor
			out += '${quotient}${unit.name}'
			value = remainder
			i++
		}
	}
	return out
}

pub fn (d Duration) format_entry() string {
	return d.format()
}

// parse_uint is the std.fmt.parseUnsigned adapter used by Duration.parseCLI.
fn parse_uint(s string) ?u64 {
	return zig_fmt.parse_unsigned(s, max_u64, 10) or { return none }
}

// ------------------------------------------------------------
// WindowPadding
// ------------------------------------------------------------

pub struct WindowPadding {
pub:
	top_left     u32
	bottom_right u32
}

pub fn (w WindowPadding) clone() WindowPadding {
	return w
}

pub fn (w WindowPadding) equal(other WindowPadding) bool {
	return w == other
}

pub fn (w WindowPadding) format_entry() string {
	if w.top_left == w.bottom_right {
		return w.top_left.str()
	}
	return '${w.top_left},${w.bottom_right}'
}

// window_padding_parse_cli translates `WindowPadding.parseCLI`.
pub fn window_padding_parse_cli(input ?string) !WindowPadding {
	in_val := input or { return perr(ParseError.value_required) }
	if idx := in_val.index(',') {
		left_str := in_val[..idx].trim(' \t')
		right_str := in_val[idx + 1..].trim(' \t')
		left := parse_u32(left_str) or { return perr(ParseError.invalid_value) }
		right := parse_u32(right_str) or { return perr(ParseError.invalid_value) }
		return WindowPadding{
			top_left: left
			bottom_right: right
		}
	}
	value := parse_u32(in_val.trim(' \t')) or { return perr(ParseError.invalid_value) }
	return WindowPadding{
		top_left: value
		bottom_right: value
	}
}

pub fn WindowPadding.parse_cli(input ?string) !WindowPadding {
	return window_padding_parse_cli(input)
}

// parse_u32 parses a base-10 u32, returning none on invalid input.
fn parse_u32(s string) ?u32 {
	return u32(cli_args.parse_unsigned_int_base(s, 32, 10) or { return none })
}

// ------------------------------------------------------------
// RepeatableString
// ------------------------------------------------------------

// RepeatableStringList is a string value that can be repeated to accumulate a
// list of strings. Mirrors Witty's `RepeatableString`.
pub struct RepeatableStringList {
pub mut:
	list           []string
	overwrite_next bool
}

// parse_cli translates `RepeatableString.parseCLI`. An empty value resets the
// list; otherwise the value is appended (clearing first if `overwrite_next`).
pub fn (mut r RepeatableStringList) parse_cli(input ?string) ! {
	value := input or { return perr(ParseError.value_required) }
	if value.len == 0 {
		r.list.clear()
		return
	}
	if r.overwrite_next {
		r.list.clear()
		r.overwrite_next = false
	}
	r.list << value
}

// count returns the number of items in the list.
pub fn (r RepeatableStringList) count() int {
	return r.list.len
}

pub fn (r RepeatableStringList) clone() RepeatableStringList {
	return RepeatableStringList{
		list: r.list.map(it.clone())
	}
}

pub fn (r RepeatableStringList) equal(other RepeatableStringList) bool {
	return r.list == other.list
}

pub fn (r RepeatableStringList) format_entry() []string {
	return if r.list.len == 0 { [''] } else { r.list.clone() }
}

// ------------------------------------------------------------
// MouseScrollMultiplier
// ------------------------------------------------------------

pub struct MouseScrollMultiplier {
pub mut:
	precision f64 = 1.0
	discrete  f64 = 3.0
}

// mouse_scroll_multiplier_parse_cli translates `MouseScrollMultiplier.parseCLI`.
// A bare float sets both precision and discrete; otherwise a comma-separated
// list of `precision:` / `discrete:` assignments is parsed.
pub fn (mut m MouseScrollMultiplier) parse_cli(input ?string) ! {
	in_val := input or { return perr(ParseError.value_required) }

	// Bare float sets both.
	if bare := parse_float(in_val) {
		m = MouseScrollMultiplier{
			precision: bare
			discrete: bare
		}
		return
	}

	// Otherwise parse a struct-like `key:value,key:value` form. Any empty
	// entry or unknown key is an error.
	mut result := MouseScrollMultiplier{
		precision: m.precision
		discrete: m.discrete
	}
	parts := in_val.split(',')
	for part in parts {
		colon := part.index(':') or { return perr(ParseError.invalid_value) }
		key := part[..colon].trim(' \t')
		val_str := part[colon + 1..].trim(' \t')
		val := parse_float(val_str) or { return perr(ParseError.invalid_value) }
		match key {
			'precision' {
				result.precision = val
			}
			'discrete' {
				result.discrete = val
			}
			else {
				return perr(ParseError.invalid_value)
			}
		}
	}
	m = result
}

pub fn (m MouseScrollMultiplier) clone() MouseScrollMultiplier {
	return m
}

pub fn (m MouseScrollMultiplier) equal(other MouseScrollMultiplier) bool {
	return m.precision == other.precision && m.discrete == other.discrete
}

// format renders the multiplier as `precision:<p>,discrete:<d>`.
pub fn (m MouseScrollMultiplier) format() string {
	return 'precision:${format_f64(m.precision)},discrete:${format_f64(m.discrete)}'
}

pub fn (m MouseScrollMultiplier) format_entry() string {
	return m.format()
}

// parse_float is the V equivalent of std.fmt.parseFloat(f64, s).
fn parse_float(s string) ?f64 {
	return zig_fmt.parse_f64(s) or { return none }
}

// format_f64 renders a float without a trailing `.0` for whole numbers, to
// match Zig's `{d}` formatting.
fn format_f64(v f64) string {
	if v == f64(i64(v)) {
		return i64(v).str()
	}
	return v.str()
}

// ------------------------------------------------------------
// QuickTerminalSize
// ------------------------------------------------------------

pub struct QuickTerminalSizePercentage {
pub:
	value f32
}

pub struct QuickTerminalSizePixels {
pub:
	value u32
}

// QuickTerminalSizeValue is Config.QuickTerminalSize.Size. Each source arm
// retains only its own payload; the tag/value layout is introduced solely by
// CQuickTerminalSize at the C ABI boundary.
pub type QuickTerminalSizeValue = QuickTerminalSizePercentage | QuickTerminalSizePixels

pub fn QuickTerminalSizeValue.parse(input string) !QuickTerminalSizeValue {
	if input.len == 0 {
		return perr(ParseError.value_required)
	}
	if input.ends_with('px') {
		digits := input[..input.len - 2]
		px := parse_u32(digits) or { return perr(ParseError.invalid_value) }
		return QuickTerminalSizePixels{ value: px }
	}
	if input.ends_with('%') {
		digits := input[..input.len - 1]
		pct := zig_fmt.parse_f32(digits) or { return perr(ParseError.invalid_value) }
		if pct < 0 {
			return perr(ParseError.invalid_value)
		}
		return QuickTerminalSizePercentage{ value: pct }
	}
	return perr(ParseError.missing_unit)
}

pub fn (s QuickTerminalSizeValue) to_pixels(parent u32) u32 {
	return match s {
		QuickTerminalSizePercentage { u32(s.value / 100.0 * f32(parent)) }
		QuickTerminalSizePixels { s.value }
	}
}

pub fn (s QuickTerminalSizeValue) format() string {
	return match s {
		QuickTerminalSizePercentage { '${format_f64(f64(s.value))}%' }
		QuickTerminalSizePixels { '${s.value}px' }
	}
}

pub struct QuickTerminalSize {
pub mut:
	primary   ?QuickTerminalSizeValue
	secondary ?QuickTerminalSizeValue
}

pub fn (q QuickTerminalSize) clone() QuickTerminalSize {
	return QuickTerminalSize{
		primary: q.primary
		secondary: q.secondary
	}
}

pub fn (q QuickTerminalSize) format_entry() ?string {
	primary := q.primary or { return none }
	mut result := primary.format()
	if secondary := q.secondary {
		result += ',${secondary.format()}'
	}
	return result
}

pub struct QuickTerminalDimensions {
pub:
	width  u32
	height u32
}

// quick_terminal_size_parse_cli translates `QuickTerminalSize.parseCLI`.
pub fn (mut q QuickTerminalSize) parse_cli(input ?string) ! {
	in_val := input or { return perr(ParseError.value_required) }
	parts := in_val.split(',')

	primary_str := parts[0].trim(' \t')
	q.primary = QuickTerminalSizeValue.parse(primary_str)!

	if parts.len > 1 {
		secondary_str := parts[1].trim(' \t')
		q.secondary = QuickTerminalSizeValue.parse(secondary_str)!
	} else {
		q.secondary = none
	}

	if parts.len > 2 {
		return perr(ParseError.too_many_arguments)
	}
}

// calculate translates `QuickTerminalSize.calculate`.
pub fn (q QuickTerminalSize) calculate(position QuickTerminalPosition, dims QuickTerminalDimensions) QuickTerminalDimensions {
	match position {
		.left, .right {
			return QuickTerminalDimensions{
				width: if p := q.primary { p.to_pixels(dims.width) } else { u32(400) }
				height: if s := q.secondary { s.to_pixels(dims.height) } else { dims.height }
			}
		}
		.top, .bottom {
			return QuickTerminalDimensions{
				width: if s := q.secondary { s.to_pixels(dims.width) } else { dims.width }
				height: if p := q.primary { p.to_pixels(dims.height) } else { u32(400) }
			}
		}
		.center {
			if dims.width >= dims.height {
				return QuickTerminalDimensions{
					width: if p := q.primary { p.to_pixels(dims.width) } else { u32(800) }
					height: if s := q.secondary { s.to_pixels(dims.height) } else { u32(400) }
				}
			} else {
				return QuickTerminalDimensions{
					width: if s := q.secondary { s.to_pixels(dims.width) } else { u32(400) }
					height: if p := q.primary { p.to_pixels(dims.height) } else { u32(800) }
				}
			}
		}
	}
}

pub enum QuickTerminalPosition as u8 {
	top
	bottom
	left
	right
	center
}

pub enum QuickTerminalLayer as u8 {
	overlay
	top
	bottom
	background
}

pub enum QuickTerminalScreen as u8 {
	main
	mouse
	macos_menu_bar
}

pub enum QuickTerminalSpaceBehavior as u8 {
	remain
	move
}

pub enum QuickTerminalKeyboardInteractivity as u8 {
	none_
	on_demand
	exclusive
}

// ------------------------------------------------------------
// BackgroundBlur (parse with radius)
// ------------------------------------------------------------

// background_blur_parse_cli translates `BackgroundBlur.parseCLI`.
pub fn background_blur_parse_cli(input ?string) !BackgroundBlur {
	in_val := input or {
		// Emulate bool behavior: unset means true.
		return BackgroundBlurTrue{}
	}

	// Try normal bools.
	if b := parse_bool_opt(in_val) {
		if b {
			return BackgroundBlurTrue{}
		}
		return BackgroundBlurFalse{}
	}

	// Try the named void-tag enums.
	match in_val {
		'macos-glass-regular' {
			return BackgroundBlurMacosGlassRegular{}
		}
		'macos-glass-clear' {
			return BackgroundBlurMacosGlassClear{}
		}
		else {}
	}

	// Otherwise parse as a u8 radius (base-0: accepts decimal/0x/0o/0b).
	radius := parse_u8_base0(in_val) or { return perr(ParseError.invalid_value) }
	return BackgroundBlurRadius{
		radius: radius
	}
}

// parse_bool_opt parses Witty's accepted boolean spellings.
fn parse_bool_opt(v string) ?bool {
	return match v {
		'1', 't', 'T', 'true' { true }
		'0', 'f', 'F', 'false' { false }
		else { none }
	}
}

// parse_u8_base0 parses a u8 accepting `0x`/`0o`/`0b` prefixes (base 0),
// erroring on overflow. Mirrors Zig's `parseInt(u8, s, 0)`.
fn parse_u8_base0(s string) ?u8 {
	idx := parse_palette_index(s) or { return none }
	if idx > 255 {
		return none
	}
	return u8(idx)
}

// ------------------------------------------------------------
// WindowDecoration.parse_cli
// ------------------------------------------------------------

// window_decoration_parse_cli translates `WindowDecoration.parseCLI`. A null
// input means `auto`; booleans map to auto/none; otherwise the string must be
// a valid enum tag.
pub fn window_decoration_parse_cli(input ?string) !WindowDecoration {
	in_val := input or { return WindowDecoration.auto }
	if b := parse_bool_opt(in_val) {
		return if b { WindowDecoration.auto } else { WindowDecoration.none_ }
	}
	return match in_val {
		'auto' { WindowDecoration.auto }
		'client' { WindowDecoration.client }
		'server' { WindowDecoration.server }
		'none' { WindowDecoration.none_ }
		else {
			return perr(ParseError.invalid_value)
		}
	}
}

pub fn WindowDecoration.parse_cli(input ?string) !WindowDecoration {
	return window_decoration_parse_cli(input)
}

// ------------------------------------------------------------
// ThemePair (light/dark theme parsing)
// ------------------------------------------------------------

// ThemePair holds a light and dark theme name. Mirrors Witty's `Theme`
// struct (renamed to avoid colliding with the existing `Theme` enum).
pub struct ThemePair {
pub mut:
	light string @['cli_required']
	dark  string @['cli_required']
}

pub fn (mut t ThemePair) parse_cli(input ?string) ! {
	t = theme_pair_parse_cli(input)!
}

pub fn (t ThemePair) clone() ThemePair {
	return ThemePair{
		light: t.light.clone()
		dark: t.dark.clone()
	}
}

pub fn (t ThemePair) format_entry() string {
	if t.light == t.dark {
		return t.light
	}
	return 'light:${t.light},dark:${t.dark}'
}

// theme_pair_parse_cli translates `Theme.parseCLI`. A bare value sets both
// light and dark; a value containing `,`, `=`, or `:` is parsed as a
// light/dark pair, both of which are required.
pub fn theme_pair_parse_cli(input ?string) !ThemePair {
	in_val := input or { return perr(ParseError.value_required) }
	if in_val.len == 0 {
		return perr(ParseError.value_required)
	}

	if in_val.contains(',') || in_val.contains('=') || in_val.contains(':') {
		return cli_args.parse_auto_struct[ThemePair](in_val, ThemePair{}) or {
			return perr(ParseError.invalid_value)
		}
	}

	trimmed := in_val.trim(' \t')
	return ThemePair{
		light: trimmed
		dark: trimmed
	}
}

// ------------------------------------------------------------
// Palette.parse_cli (base-aware index + overflow)
// ------------------------------------------------------------

// palette_parse_cli translates `Palette.parseCLI`, mutating the palette in
// place. The index supports base prefixes; an out-of-range index (>255)
// produces an overflow error.
pub fn (mut p Palette) parse_cli(input ?string) ! {
	value := input or { return perr(ParseError.value_required) }
	eq := value.index('=') or { return perr(ParseError.invalid_value) }
	key_str := value[..eq].trim(' \t')
	idx := parse_palette_index(key_str)!
	col := color_parse_cli(value[eq + 1..])!
	p.value[idx] = col
}
