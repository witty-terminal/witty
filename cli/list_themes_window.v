module cli

import vaxis

struct HelpEntry {
	keys string
	help string
}

// Draw into the retained vaxis screen, following pinned Preview.draw.
pub fn (mut self Preview) draw_window(mut vx vaxis.Vaxis) ! {
	win := vx.window()
	win.clear()
	vx.set_mouse_shape(.default)
	theme_list := win.child(vaxis.WindowChildOptions{
		x_off:  0
		y_off:  0
		width:  32
		height: win.height
	})
	mut highlight := ?u16(none)
	if mouse := self.mouse {
		self.mouse = none
		if self.mode == .normal {
			if mouse.button == .wheel_up { self.up(1) }
			if mouse.button == .wheel_down { self.down(1) }
			if local_mouse := theme_list.has_mouse(mouse) {
				if mouse.button == .left && mouse.type_ == .release {
					selection := self.window + uint(local_mouse.row)
					if selection < uint(self.filtered.len) {
						self.current = selection
					}
				}
				highlight = local_mouse.row
			}
		}
	}
	if self.filtered.len == 0 {
		self.current = 0
		self.window = 0
	} else {
		start := self.window
		last_index := self.window + uint(theme_list.height) - 1
		if self.current > last_index {
			self.window = self.current - uint(theme_list.height) + 1
		}
		if self.current < start {
			self.window = self.current
		}
		if self.window >= uint(self.filtered.len) {
			self.window = uint(self.filtered.len - 1)
		}
	}
	theme_list.fill(vaxis.Cell{
		style: self.ui_standard()
	})
	for row := u16(0); row < theme_list.height; row++ {
		index := self.window + uint(row)
		if index >= uint(self.filtered.len) { break }
		theme := self.themes[self.filtered[index]]
		selected := index == self.current
		style := if selected {
			self.ui_selected()
		} else if h := highlight {
			if h == row { self.ui_highlighted() } else { self.ui_standard() }
		} else {
			self.ui_standard()
		}
		if selected {
			theme_list.print_segment(vaxis.CellSegment{
				text:  '❯ '
				style: style
			}, vaxis.PrintOptions{
				row_offset: row
			})
		}
		theme_list.print_segment(vaxis.CellSegment{
			text:  theme.theme
			style: style
			link:  vaxis.CellHyperlink{
				uri: theme.to_uri()
			}
		}, vaxis.PrintOptions{
			row_offset: row
			col_offset: 2
		})
		if selected {
			if theme.theme.len < int(theme_list.width) - 4 {
				for col in 2 + theme.theme.len .. int(theme_list.width) - 2 {
					theme_list.print_segment(vaxis.CellSegment{
						text:  ' '
						style: style
					}, vaxis.PrintOptions{
						row_offset: row
						col_offset: u16(col)
					})
				}
			}
			theme_list.print_segment(vaxis.CellSegment{
				text:  ' ❮'
				style: style
			}, vaxis.PrintOptions{
				row_offset: row
				col_offset: theme_list.width - 2
			})
		}
	}
	self.draw_preview_window(win, theme_list.x_off + int(theme_list.width))!
	match self.mode {
		.normal { win.hide_cursor() }
		.help {
			win.hide_cursor()
			child := win.child(vaxis.WindowChildOptions{
				x_off:  max_int(int(win.width) / 2 - 30, 0)
				y_off:  max_int(int(win.height) / 2 - 11, 0)
				width:  60
				height: 22
				border: vaxis.WindowBorderOptions{
					where_: vaxis.BorderAll{}
					style:  self.ui_standard()
				}
			})
			child.fill(vaxis.Cell{
				style: self.ui_standard()
			})
			for i, entry in preview_help_entries() {
				row := u16(i + 1)
				child.print_segment(vaxis.CellSegment{ text: entry.keys, style: self.ui_standard() }, vaxis.PrintOptions{ row_offset: row, col_offset: 2 })
				child.print_segment(vaxis.CellSegment{ text: '—', style: self.ui_standard() }, vaxis.PrintOptions{ row_offset: row, col_offset: 15 })
				child.print_segment(vaxis.CellSegment{ text: entry.help, style: self.ui_standard() }, vaxis.PrintOptions{ row_offset: row, col_offset: 17 })
			}
		}
		.search {
			assert win.width >= 40 && win.height >= 5
			child := win.child(vaxis.WindowChildOptions{
				x_off:  20
				y_off:  int(win.height) - 5
				width:  u16(int(win.width) - 40)
				height: 3
				border: vaxis.WindowBorderOptions{
					where_: vaxis.BorderAll{}
					style:  self.ui_standard()
				}
			})
			child.fill(vaxis.Cell{
				style: self.ui_standard()
			})
			self.text_input.draw_in_window_with_style(child, self.ui_standard())
		}
		.save {
			assert self.filtered.len > 0
			win.hide_cursor()
			child := win.child(vaxis.WindowChildOptions{
				x_off:  max_int(int(win.width) / 2 - 46, 0)
				y_off:  max_int(int(win.height) / 2 - 8, 0)
				width:  92
				height: 17
				border: vaxis.WindowBorderOptions{
					where_: vaxis.BorderAll{}
					style:  self.ui_standard()
				}
			})
			child.fill(vaxis.Cell{
				style: self.ui_standard()
			})
			theme := self.themes[self.filtered[self.current]]
			for i, line in preview_save_instructions(theme.theme) {
				child.print_segment(vaxis.CellSegment{ text: line, style: self.ui_standard() }, vaxis.PrintOptions{ row_offset: u16(i + 1), col_offset: 2 })
			}
		}
	}
}

fn preview_help_entries() []HelpEntry {
	return [
		HelpEntry{ keys: '^C, q, ESC', help: 'Quit.' },
		HelpEntry{ keys: 'F1, ?, ^H', help: 'Toggle help window.' },
		HelpEntry{ keys: 'f', help: 'Cycle through theme filters.' },
		HelpEntry{ keys: 'k, ↑', help: 'Move up 1 theme.' },
		HelpEntry{ keys: 'ScrollUp', help: 'Move up 1 theme.' },
		HelpEntry{ keys: 'PgUp', help: 'Move up 20 themes.' },
		HelpEntry{ keys: 'j, ↓', help: 'Move down 1 theme.' },
		HelpEntry{ keys: 'ScrollDown', help: 'Move down 1 theme.' },
		HelpEntry{ keys: 'PgDown', help: 'Move down 20 themes.' },
		HelpEntry{ keys: 'h, x', help: 'Show palette numbers in hexadecimal.' },
		HelpEntry{ keys: 'd', help: 'Show palette numbers in decimal.' },
		HelpEntry{ keys: 'c', help: 'Copy theme name to the clipboard.' },
		HelpEntry{ keys: 'C', help: 'Copy theme path to the clipboard.' },
		HelpEntry{ keys: 'Home', help: 'Go to the start of the list.' },
		HelpEntry{ keys: 'End', help: 'Go to the end of the list.' },
		HelpEntry{ keys: '/', help: 'Start search.' },
		HelpEntry{ keys: '^X, ^/', help: 'Clear search.' },
		HelpEntry{ keys: '⏎', help: 'Save theme or close search window.' },
		HelpEntry{ keys: 'w', help: 'Write theme to auto config file.' },
	]
}

fn preview_save_instructions(theme string) []string {
	return [
		'To apply this theme, add the following line to your Witty configuration:',
		'',
		'theme = ${theme}',
		'',
		'Save the configuration file and then reload it to apply the new theme.',
		'',
		"Or press 'w' to write an auto theme file to your system's preferred default config path.",
		'Then add the following line to your Witty configuration and reload:',
		'',
		'config-file = ?auto/theme.witty',
		'',
		'For more information, see the Witty repository:',
		'',
		'https://github.com/witty-terminal/witty',
	]
}
