module cli

import ascii
import os
import net.urllib
import configpkg
import themepkg
import tui
import vaxis
import zf
import global_state

// When the number of filtered themes is less than or equal to this threshold,
// the window position will be reset to 0 to show all results from the top.
// This ensures better visibility for small result sets while maintaining
// scroll position for larger lists.
const small_list_threshold = 10

// ColorScheme filters which themes to show by color scheme.
pub enum ColorScheme as u8 {
	all
	dark
	light
}

// Options are the command-line flags for list-themes.
pub struct Options {
pub mut:
	// If true, print the full path to the theme.
	path bool
	// If true, force a plain list of themes.
	plain bool
	// Specifies the color scheme of the themes to include in the list.
	color ColorScheme = .all
}

pub fn (opts Options) deinit() {
	_ = opts
}

pub fn (opts Options) help() ! {
	_ = opts
	action_options_help()!
}

// ThemeListElement represents a single discovered theme.
pub struct ThemeListElement {
pub mut:
	location themepkg.Location
	path     string
	theme    string
	rank     ?f64
}

// less_than compares two theme list elements by name, case-insensitive.
// TODO: use Unicode-aware comparison
fn theme_list_less_than(a &ThemeListElement, b &ThemeListElement) int {
	return ascii.order_ignore_case(a.theme, b.theme)
}

// to_uri converts the theme path to a file:// URI string.
pub fn (self &ThemeListElement) to_uri() string {
	return urllib.URL{
		scheme: 'file'
		path:   self.path
	}.str()
}

// The terminal event subscription from pinned cli/list_themes.zig.
type PreviewInputEvent = vaxis.Key | vaxis.Mouse | vaxis.ColorScheme | vaxis.Winsize

// Event is the union of possible input events for the TUI preview.
pub type Event = KeyPressEvent | MouseEvent | ColorSchemeEvent | WinsizeEvent

pub struct KeyPressEvent {
pub:
	key vaxis.Key
}

pub struct MouseEvent {
pub:
	mouse vaxis.Mouse
}

pub struct ColorSchemeEvent {
pub:
	scheme vaxis.Scheme
}

pub struct WinsizeEvent {
pub:
	winsize vaxis.Winsize
}

// PreviewMode tracks which mode the TUI preview is in.
enum PreviewMode as u8 {
	normal
	help
	search
	save
}

// Preview is the TUI preview state for interactively browsing themes.
pub struct Preview {
mut:
	should_quit  bool
	themes       []ThemeListElement
	filtered     []uint
	current      uint
	window       uint
	hex          bool
	mode         PreviewMode  = .normal
	color_scheme vaxis.Scheme = .light
	mouse        ?vaxis.Mouse
	text_input   vaxis.TextInput
	tty          ?&vaxis.Tty
	winsize      vaxis.Winsize
	theme_filter ColorScheme
}

// Preview.init creates a new Preview with the given themes and filter. The
// source's allocator and terminal scratch-buffer arguments are omitted because
// V owns both resources.
pub fn Preview.init(themes []ThemeListElement, theme_filter ColorScheme) !Preview {
	mut p := Preview{
		themes:       themes
		theme_filter: theme_filter
		text_input:   vaxis.TextInput.new()
		winsize:      vaxis.terminal_size()
		color_scheme: .light
	}
	p.update_filtered()!
	return p
}

// deinit releases the preview-owned filtering and text-input state.
pub fn (mut self Preview) deinit() {
	self.filtered.clear()
	self.text_input.deinit()
}

// update_filtered rebuilds the filtered index list based on search text and theme filter.
fn (mut self Preview) update_filtered() ! {
	// Remember current selection's name for re-selection after filtering
	relative := if self.current > self.window { self.current - self.window } else { 0 }
	mut selected := ''
	if self.filtered.len > 0 && self.current < self.filtered.len {
		selected = self.themes[self.filtered[self.current]].theme
	}

	old_filtered := self.filtered.clone()
	self.filtered.clear()

	mut theme_config := configpkg.Config.default_config()

	search_text := self.text_input.get_text()
	if search_text.len > 0 {
		query := ascii.lower_string(search_text)
		tokens := query.split(' ').filter(it.len > 0)

		for i, mut theme in self.themes {
			theme_config.load_file(theme.path)!
			if !should_include_theme(self.theme_filter, theme_config) {
				continue
			}
			r := zf.rank(theme.theme, tokens, zf.RankOptions{
				to_lower: true
				plain:    true
			})
			if r != none {
				theme.rank = r
				self.filtered << uint(i)
			}
		}
	} else {
		for i, mut theme in self.themes {
			theme_config.load_file(theme.path)!
			if should_include_theme(self.theme_filter, theme_config) {
				self.filtered << uint(i)
				theme.rank = none
			}
		}
	}

	// Check if the filtered list changed
	if old_filtered == self.filtered {
		return
	}

	if self.filtered.len == 0 {
		self.current = 0
		self.window = 0
		return
	}

	// Try to keep the same theme selected
	if selected.len > 0 {
		for idx, filt_idx in self.filtered {
			if self.themes[filt_idx].theme == selected {
				idx_usize := uint(idx)
				// Keep the relative position but ensure all search results are visible
				new_window := if idx_usize > relative { idx_usize - relative } else { uint(0) }
				// If the new window would hide some results at the top, adjust it
				self.current = idx_usize
				self.window = if self.filtered.len <= small_list_threshold {
					uint(0)
				} else {
					new_window
				}
				return
			}
		}
	}

	self.current = 0
	self.window = 0
}

// up moves the selection up by count items.
fn (mut self Preview) up(count uint) {
	if self.filtered.len == 0 {
		self.current = 0
		return
	}
	self.current = if self.current > count { self.current - count } else { 0 }
}

// down moves the selection down by count items.
fn (mut self Preview) down(count uint) {
	if self.filtered.len == 0 {
		self.current = 0
		return
	}
	self.current += count
	if self.current >= uint(self.filtered.len) {
		self.current = uint(self.filtered.len - 1)
	}
}

// update processes a single input event.
pub fn (mut self Preview) update(event Event) ! {
	match event {
		KeyPressEvent {
			key := event.key
			if key.matches(u32(`c`), vaxis.Modifiers.init(false, false, true, false, false, false,
				false, false))
			{
				self.should_quit = true
			}
			match self.mode {
				.normal {
					if key.matches_any([u32(`q`), vaxis.escape], vaxis.Modifiers{}) {
						self.should_quit = true
					}
					if key.matches_any([u32(`?`), vaxis.f1], vaxis.Modifiers{}) {
						self.mode = .help
					}
					if key.matches(u32(`h`), vaxis.Modifiers.init(false, false, true, false, false,
						false, false, false))
					{
						self.mode = .help
					}
					if key.matches(u32(`/`), vaxis.Modifiers{}) {
						self.mode = .search
					}
					if key.matches_any([vaxis.enter, vaxis.kp_enter], vaxis.Modifiers{}) {
						self.mode = .save
					}
					if key.matches_any([u32(`x`), u32(`/`)], vaxis.Modifiers.init(false, false,
						true, false, false, false, false, false))
					{
						self.text_input.clear_retaining_capacity()
						self.update_filtered()!
					}
					if key.matches_any([vaxis.home, vaxis.kp_home], vaxis.Modifiers{}) {
						self.current = 0
					}
					if key.matches_any([vaxis.end, vaxis.kp_end], vaxis.Modifiers{}) {
						assert self.filtered.len > 0
						self.current = uint(self.filtered.len - 1)
					}
					if key.matches_any([u32(`j`), u32(`+`), vaxis.down, vaxis.kp_down, vaxis.kp_add], vaxis.Modifiers{}) {
						self.down(1)
					}
					if key.matches_any([vaxis.page_down, vaxis.kp_down], vaxis.Modifiers{}) {
						self.down(20)
					}
					if key.matches_any([u32(`k`), u32(`-`), vaxis.up, vaxis.kp_up, vaxis.kp_subtract], vaxis.Modifiers{}) {
						self.up(1)
					}
					if key.matches_any([vaxis.page_up, vaxis.kp_page_up], vaxis.Modifiers{}) {
						self.up(20)
					}
					if key.matches_any([u32(`h`), u32(`x`)], vaxis.Modifiers{}) {
						self.hex = true
					}
					if key.matches(u32(`d`), vaxis.Modifiers{}) {
						self.hex = false
					}
					if key.matches(u32(`c`), vaxis.Modifiers{}) {
						self.copy_to_system_clipboard(self.themes[self.filtered[self.current]].theme)!
					} else if key.matches(u32(`c`), vaxis.Modifiers.init(true, false, false, false,
						false, false, false, false))
					{
						self.copy_to_system_clipboard(self.themes[self.filtered[self.current]].path)!
					}
					if key.matches(u32(`f`), vaxis.Modifiers{}) {
						match self.theme_filter {
							.all {
								self.theme_filter = .dark
							}
							.dark {
								self.theme_filter = .light
							}
							.light {
								self.theme_filter = .all
							}
						}

						self.update_filtered()!
					}
				}
				.help {
					if key.matches(u32(`q`), vaxis.Modifiers{}) {
						self.should_quit = true
					}
					if key.matches_any([u32(`?`), vaxis.escape, vaxis.f1], vaxis.Modifiers{}) {
						self.mode = .normal
					}
					if key.matches(u32(`h`), vaxis.Modifiers.init(false, false, true, false, false,
						false, false, false))
					{
						self.mode = .normal
					}
				}
				.search {
					if key.matches_any([vaxis.escape, vaxis.enter], vaxis.Modifiers{}) {
						self.mode = .normal
						return
					}
					if key.matches_any([u32(`x`), u32(`/`)], vaxis.Modifiers.init(false, false,
						true, false, false, false, false, false))
					{
						self.text_input.clear_retaining_capacity()
						self.update_filtered()!
						return
					}
					self.text_input.update(key)
					self.update_filtered()!
				}
				.save {
					if key.matches(u32(`q`), vaxis.Modifiers{}) {
						self.should_quit = true
					}
					if key.matches_any([vaxis.escape, vaxis.enter, vaxis.kp_enter], vaxis.Modifiers{}) {
						self.mode = .normal
					}
					if key.matches(u32(`w`), vaxis.Modifiers{}) {
						self.save_selected_theme()
					}
				}
			}
		}
		ColorSchemeEvent {
			self.color_scheme = event.scheme
		}
		MouseEvent {
			self.mouse = event.mouse
		}
		WinsizeEvent {
			self.winsize = event.winsize
		}
	}
}

fn (mut self Preview) copy_to_system_clipboard(text string) ! {
	tty := self.tty or { return error('NoTty') }
	tty.write(vaxis.clipboard_copy_sequence(text))!
}

// ui_fg returns the foreground color for the UI based on color scheme.
pub fn (self &Preview) ui_fg() vaxis.Color {
	return match self.color_scheme {
		.light {
			vaxis.ColorRgb{
				rgb: [u8(0x00), 0x00, 0x00]!
			}
		}
		.dark {
			vaxis.ColorRgb{
				rgb: [u8(0xff), 0xff, 0xff]!
			}
		}
	}
}

// ui_bg returns the background color for the UI based on color scheme.
pub fn (self &Preview) ui_bg() vaxis.Color {
	return match self.color_scheme {
		.light {
			vaxis.ColorRgb{
				rgb: [u8(0xff), 0xff, 0xff]!
			}
		}
		.dark {
			vaxis.ColorRgb{
				rgb: [u8(0x00), 0x00, 0x00]!
			}
		}
	}
}

// ui_standard returns a standard style with UI fg/bg.
pub fn (self &Preview) ui_standard() vaxis.Style {
	return vaxis.Style{
		fg: self.ui_fg()
		bg: self.ui_bg()
	}
}

// ui_hover_bg returns the hover background color.
pub fn (self &Preview) ui_hover_bg() vaxis.Color {
	return match self.color_scheme {
		.light {
			vaxis.ColorRgb{
				rgb: [u8(0xbb), 0xbb, 0xbb]!
			}
		}
		.dark {
			vaxis.ColorRgb{
				rgb: [u8(0x22), 0x22, 0x22]!
			}
		}
	}
}

// ui_highlighted returns a style for hovered items.
pub fn (self &Preview) ui_highlighted() vaxis.Style {
	return vaxis.Style{
		fg: self.ui_fg()
		bg: self.ui_hover_bg()
	}
}

// ui_selected_fg returns the foreground color for selected items.
pub fn (self &Preview) ui_selected_fg() vaxis.Color {
	return match self.color_scheme {
		.light {
			vaxis.ColorRgb{
				rgb: [u8(0x00), 0xaa, 0x00]!
			}
		}
		.dark {
			vaxis.ColorRgb{
				rgb: [u8(0x00), 0xaa, 0x00]!
			}
		}
	}
}

// ui_selected_bg returns the background color for selected items.
pub fn (self &Preview) ui_selected_bg() vaxis.Color {
	return match self.color_scheme {
		.light {
			vaxis.ColorRgb{
				rgb: [u8(0xaa), 0xaa, 0xaa]!
			}
		}
		.dark {
			vaxis.ColorRgb{
				rgb: [u8(0x33), 0x33, 0x33]!
			}
		}
	}
}

// ui_selected returns a style for selected items.
pub fn (self &Preview) ui_selected() vaxis.Style {
	return vaxis.Style{
		fg: self.ui_selected_fg()
		bg: self.ui_selected_bg()
	}
}

// ui_err_fg returns the foreground color for error messages.
pub fn (self &Preview) ui_err_fg() vaxis.Color {
	return match self.color_scheme {
		.light {
			vaxis.ColorRgb{
				rgb: [u8(0xff), 0x00, 0x00]!
			}
		}
		.dark {
			vaxis.ColorRgb{
				rgb: [u8(0xff), 0x00, 0x00]!
			}
		}
	}
}

// ui_err returns a style for error messages.
pub fn (self &Preview) ui_err() vaxis.Style {
	return vaxis.Style{
		fg: self.ui_err_fg()
		bg: self.ui_bg()
	}
}

// run is the TUI preview event loop.
pub fn (mut self Preview) run() ! {
	mut tty := vaxis.Tty.new()!
	defer { tty.deinit() }
	self.tty = &tty
	defer { self.tty = none }
	self.winsize = tty.get_winsize()!
	mut vx := vaxis.Vaxis.new(vaxis.VaxisOptions{})
	defer {
		tty.write(vx.deinit()) or {}
	}
	mut loop := vaxis.Loop.new[PreviewInputEvent](mut tty, mut vx)
	loop.init()!
	loop.start()!
	defer { loop.deinit() }
	tty.write(vx.enter_alt_screen())!
	tty.write(vx.set_title('👻 Witty Theme Preview 👻'))!
	vx.query_terminal(mut tty, 1_000_000_000)!
	tty.write(vx.set_mouse_mode(true))!
	if vx.caps.color_scheme_updates {
		tty.write(vx.subscribe_to_color_scheme_updates())!
	}
	tty.write(vx.resize(self.winsize))!
	mut dirty := true
	for !self.should_quit {
		if !dirty {
			loop.poll_event()
		}
		for {
			event := loop.try_event() or { break }
			if event is vaxis.Winsize {
				tty.write(vx.resize(event))!
			}
			self.update_from_vaxis(event)!
			dirty = true
		}

		if dirty && !self.should_quit {
			self.draw_window(mut vx)!
			tty.write(vx.render())!
			dirty = false
		}
	}
}

fn (mut self Preview) update_from_vaxis(event PreviewInputEvent) ! {
	match event {
		vaxis.Key { self.update(Event(KeyPressEvent{ key: event }))! }
		vaxis.Mouse { self.update(Event(MouseEvent{ mouse: event }))! }
		vaxis.ColorScheme { self.update(Event(ColorSchemeEvent{ scheme: event.scheme }))! }
		vaxis.Winsize { self.update(Event(WinsizeEvent{ winsize: event }))! }
	}
}

struct PreviewSegment {
	text  string
	style vaxis.Style
}

fn preview_terminal_color(value ?configpkg.TerminalColor, fallback vaxis.Color) vaxis.Color {
	color := value or { return fallback }
	return match color {
		configpkg.TerminalColorColor {
			vaxis.ColorRgb{
				rgb: [color.color.r, color.color.g, color.color.b]!
			}
		}
		configpkg.TerminalColorCellForeground, configpkg.TerminalColorCellBackground {
			// Ghostty reads the tagged union's `.color` arm directly here.
			panic('theme preview requires an explicit terminal color')
		}
	}
}

fn preview_palette_style(config configpkg.Config, index int, bg vaxis.Color) vaxis.Style {
	return vaxis.Style{
		fg: color_from_palette(config, index)
		bg: bg
	}
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

// save_selected_theme writes the selected theme to the auto config file.
fn (mut self Preview) save_selected_theme() {
	if self.filtered.len == 0 {
		return
	}
	idx := self.filtered[self.current]
	theme := self.themes[idx]
	write_auto_theme_file(theme.theme) or { return }
}

// The lorem ipsum text used in the theme preview.
const lorem_ipsum = $embed_file('lorem_ipsum.txt').to_string()

// resolve_auto_theme_path returns the path to the auto theme config file.
fn resolve_auto_theme_path() !string {
	main_cfg_path := configpkg.preferred_default_file_path()!
	if main_cfg_path.len == 0 {
		return error('no default config path')
	}
	base_dir := os.dir(main_cfg_path)
	return os.join_path(base_dir, 'auto', 'theme.witty')
}

// write_auto_theme_file writes a theme = <name> line to the auto theme config file.
fn write_auto_theme_file(theme_name string) ! {
	auto_path := resolve_auto_theme_path()!

	dir := os.dir(auto_path)
	if dir.len > 0 {
		os.mkdir_all(dir)!
	}

	os.write_file(auto_path, 'theme = ${theme_name}\n')!
}

// color returns a vaxis.Color from the config palette at the given index.
fn color_from_palette(cfg configpkg.Config, palette int) vaxis.Color {
	c := cfg.palette.value[palette]
	return vaxis.ColorRgb{
		rgb: [c.r, c.g, c.b]!
	}
}

// preview launches the TUI preview for the given themes.
fn preview(themes []ThemeListElement, theme_filter ColorScheme) ! {
	mut app := Preview.init(themes, theme_filter)!
	defer {
		app.deinit()
	}
	app.run()!
}

// should_include_theme returns true if the theme should be listed based on the color filter.
// Determines dark/light by computing the luminance of the theme's background color.
pub fn should_include_theme(theme_filter ColorScheme, theme_config configpkg.Config) bool {
	rf := f32(theme_config.background.r) / 255.0
	gf := f32(theme_config.background.g) / 255.0
	bf := f32(theme_config.background.b) / 255.0
	luminance := 0.2126 * rf + 0.7152 * gf + 0.0722 * bf
	is_dark := luminance < 0.5
	return theme_filter == .all || (theme_filter == .dark && is_dark)
		|| (theme_filter == .light && !is_dark)
}

// The `list-themes` command is used to preview or list all the available
// themes for Ghostty.
//
// If this command is run from a TTY, a TUI preview of the themes will be
// shown. While in the preview, `F1` will bring up a help screen and `ESC` will
// exit the preview. Other keys that can be used to navigate the preview are
// listed in the help screen.
//
// If this command is not run from a TTY, or the output is piped to another
// command, a plain list of theme names will be printed to the screen. A plain
// list can be forced using the `--plain` CLI flag.
//
// Two different directories will be searched for themes.
//
// The first directory is the `themes` subdirectory of your Ghostty
// configuration directory. This is `$XDG_CONFIG_HOME/witty/themes` or
// `~/.config/witty/themes`.
//
// The second directory is the `themes` subdirectory of the Ghostty resources
// directory. Ghostty ships with a multitude of themes that will be installed
// into this directory. On macOS, this directory is the
// `Witty.app/Contents/Resources/witty/themes`. On Linux, this directory
// is the `share/witty/themes` (wherever you installed the Ghostty "share"
// directory). If you're running Ghostty from the source, this is the
// `zig-out/share/witty/themes` directory.
//
// You can also set the `GHOSTTY_RESOURCES_DIR` environment variable to point
// to the resources directory.
//
// Flags:
//
//   * `--path`: Show the full path to the theme.
//
//   * `--plain`: Force a plain listing of themes.
//
//   * `--color`: Specify the color scheme of the themes included in the list.
//                This can be `dark`, `light`, or `all`. The default is `all`.
pub fn run_list_themes(args []string) !int {
	opts := parse_list_themes_options(args)!

	resources_dir := global_state.get_state().resources_dir.app()
	if resources_dir == none {
		eprintln('Could not find the Witty resources directory. Please ensure that Witty is installed correctly.')
	}

	mut count := 0
	mut themes := []ThemeListElement{}

	mut it := themepkg.LocationIterator.new()
	for {
		loc := it.next() or { break }
		if !os.exists(loc.dir) {
			continue
		}
		entries := os.ls(loc.dir) or {
			eprintln('error trying to open ${loc.dir}: ${err}')
			continue
		}
		for entry in entries {
			// Ghostty accepts regular files and symbolic-link directory entries.
			full_path := os.join_path(loc.dir, entry)
			if !os.is_file(full_path) && !os.is_link(full_path) {
				continue
			}
			if entry == '.DS_Store' {
				continue
			}
			count += 1
			themes << ThemeListElement{
				path:     full_path
				location: loc.location
				theme:    entry
			}
		}
	}

	if count == 0 {
		eprintln('No themes found, check to make sure that the themes were installed correctly.')
		return 1
	}

	themes.sort_with_compare(theme_list_less_than)

	if tui.can_pretty_print && !opts.plain && os.is_atty(1) > 0 {
		preview(themes, opts.color)!
		return 0
	}

	mut theme_config := configpkg.Config.default_config()
	for theme in themes {
		theme_config.load_file(theme.path)!
		if !should_include_theme(opts.color, theme_config) {
			continue
		}
		if opts.path {
			println('${theme.theme} (${theme.location}) ${theme.path}')
		} else {
			println('${theme.theme} (${theme.location})')
		}
	}

	// Don't forget to flush!
	// (V's println auto-flushes)
	return 0
}

fn parse_list_themes_options(args []string) !Options {
	return parse_action_options[Options](args)
}
