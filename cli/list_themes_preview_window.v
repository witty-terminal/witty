module cli

import configpkg
import vaxis

fn (self &Preview) put_window_segment(pane vaxis.Window, x_off int, row int, col int, right int, text string, style vaxis.Style) {
	_ = self
	if row < 0 || row >= int(pane.height) || col < x_off || col >= right {
		return
	}
	pane.print_segment(vaxis.CellSegment{
		text:  text
		style: style
	}, vaxis.PrintOptions{
		row_offset: u16(row)
		col_offset: u16(col - x_off)
	})
}

fn (self &Preview) put_window_link(pane vaxis.Window, x_off int, row int, col int, right int, text string, uri string, style vaxis.Style, wrap vaxis.PrintWrap) {
	_ = self
	if row < 0 || row >= int(pane.height) || col < x_off || col >= right {
		return
	}
	pane.print_segment(vaxis.CellSegment{
		text:  text
		style: style
		link:  vaxis.CellHyperlink{
			uri: uri
		}
	}, vaxis.PrintOptions{
		row_offset: u16(row)
		col_offset: u16(col - x_off)
		wrap:       wrap
	})
}

fn (self &Preview) put_window_preview_segment(pane vaxis.Window, x_off int, row int, col int, right int, bottom int, text string, style vaxis.Style) {
	if row >= bottom {
		return
	}
	self.put_window_segment(pane, x_off, row, col, right, text, style)
}

fn (self &Preview) put_window_preview_segments(pane vaxis.Window, x_off int, row int, col int, right int, bottom int, segments []PreviewSegment) {
	_ = self
	if row < 0 || row >= bottom || col < x_off || col >= right {
		return
	}
	mut cells := []vaxis.CellSegment{cap: segments.len}
	for segment in segments {
		cells << vaxis.CellSegment{
			text:  segment.text
			style: segment.style
		}
	}
	bounded := pane.child(vaxis.WindowChildOptions{
		x_off:  0
		y_off:  0
		width:  pane.width
		height: u16(min_int(bottom, int(pane.height)))
	})
	bounded.print(cells, vaxis.PrintOptions{
		row_offset: u16(row)
		col_offset: u16(col - x_off)
	})
}

pub fn (mut self Preview) draw_preview_window(win vaxis.Window, x_off int) ! {
	width := max_int(int(win.width) - x_off, 0)
	height := int(win.height)
	pane := win.child(vaxis.WindowChildOptions{
		x_off:  x_off
		y_off:  0
		width:  u16(width)
		height: win.height
	})
	if self.filtered.len == 0 {
		win.fill(vaxis.Cell{
			style: self.ui_standard()
		})
		win.print_segment(vaxis.CellSegment{
			text:  'No theme found!'
			style: self.ui_standard()
		}, vaxis.PrintOptions{
			row_offset: u16(max_int(height / 2 - 1, 0))
			col_offset: u16(max_int(int(win.width) / 2 - 7, 0))
		})
		return
	}

	theme := self.themes[self.filtered[self.current]]
	mut config := configpkg.Config.default_config()
	config.load_file(theme.path) or {
		standard := self.ui_standard()
		pane.fill(vaxis.Cell{
			style: standard
		})
		middle := height / 2
		text := 'Unable to open ${theme.theme} from:'
		self.put_window_segment(pane, x_off, max_int(middle - 1, 0), x_off + max_int((width -
			text.len) / 2, 0), x_off + width, text, self.ui_err())
		self.put_window_link(pane, x_off, middle, x_off + max_int((width - theme.path.len) / 2, 0), x_off +
			width, theme.path, theme.to_uri(), self.ui_err(), .grapheme)
		error_text := err.msg()
		self.put_window_segment(pane, x_off, min_int(middle + 1, max_int(height - 1, 0)), x_off + max_int((width -
			error_text.len) / 2, 0), x_off + width, error_text, self.ui_err())
		return
	}
	fg := vaxis.ColorRgb{
		rgb: [config.foreground.r, config.foreground.g, config.foreground.b]!
	}
	bg := vaxis.ColorRgb{
		rgb: [config.background.r, config.background.g, config.background.b]!
	}
	cursor_fg := preview_terminal_color(config.cursor_text, bg)
	cursor_bg := preview_terminal_color(config.cursor_color, fg)
	selection_fg := preview_terminal_color(config.selection_foreground, bg)
	selection_bg := preview_terminal_color(config.selection_background, fg)
	cursor := vaxis.Style{
		fg: cursor_fg
		bg: cursor_bg
	}
	standard_selection := vaxis.Style{
		fg: selection_fg
		bg: selection_bg
	}
	standard := vaxis.Style{
		fg: fg
		bg: bg
	}
	standard_bold := vaxis.Style{
		fg:   fg
		bg:   bg
		bold: true
	}
	standard_italic := vaxis.Style{
		fg:     fg
		bg:     bg
		italic: true
	}
	standard_bold_italic := vaxis.Style{
		fg:     fg
		bg:     bg
		bold:   true
		italic: true
	}
	standard_underline := vaxis.Style{
		fg:       fg
		bg:       bg
		ul_style: .single
	}
	standard_double_underline := vaxis.Style{
		fg:       fg
		bg:       bg
		ul_style: .double_
	}
	standard_dashed_underline := vaxis.Style{
		fg:       fg
		bg:       bg
		ul_style: .dashed
	}
	standard_curly_underline := vaxis.Style{
		fg:       fg
		bg:       bg
		ul_style: .curly
	}
	standard_dotted_underline := vaxis.Style{
		fg:       fg
		bg:       bg
		ul_style: .dotted
	}

	pane.child(vaxis.WindowChildOptions{
		x_off:  0
		y_off:  0
		width:  pane.width
		height: 4
	}).fill(vaxis.Cell{ style: standard })
	self.put_window_link(pane, x_off, 1, x_off + max_int((width - theme.theme.len) / 2, 0), x_off + width,
		theme.theme, theme.to_uri(), standard_bold_italic, .grapheme)
	self.put_window_link(pane, x_off, 2, x_off + max_int((width - theme.path.len) / 2, 0), x_off + width,
		theme.path, theme.to_uri(), standard, .none)

	mut next_row := 4
	if config.diagnostics.len > 0 && next_row < height {
		heading := 'Problems were encountered trying to load the theme:'
		self.put_window_preview_segment(pane, x_off, next_row, x_off + max_int((width - heading.len) / 2, 0),
			x_off + width, height, heading, self.ui_err())
		for i, diagnostic in config.diagnostics {
			self.put_window_preview_segment(pane, x_off, next_row + 2 + i, x_off + 2, x_off + width, height,
				diagnostic.format(), self.ui_err())
		}
		next_row += 2 + config.diagnostics.len
	}

	pane.child(vaxis.WindowChildOptions{
		x_off:  0
		y_off:  next_row
		width:  pane.width
		height: 6
	}).fill(vaxis.Cell{ style: standard })
	for i in 0 .. 16 {
		row := next_row + (i / 8) * 3
		col := x_off + (i % 8) * 8
		if row >= height || col >= x_off + width {
			continue
		}
		label := if self.hex { ' ${i:02x}' } else { '${i:3}' }
		self.put_window_preview_segment(pane, x_off, row, col, x_off + width, height, label, standard)
		palette_style := vaxis.Style{
			fg: color_from_palette(config, i)
			bg: bg
		}
		self.put_window_preview_segment(pane, x_off, row, col + 4, x_off + width, height, '████', palette_style)
		self.put_window_preview_segment(pane, x_off, row + 1, col + 4, x_off + width, height, '████',
			palette_style)
	}
	next_row += 6

	color1 := preview_palette_style(config, 1, bg)
	color2 := preview_palette_style(config, 2, bg)
	color3 := preview_palette_style(config, 3, bg)
	color4 := preview_palette_style(config, 4, bg)
	color5 := preview_palette_style(config, 5, bg)
	color6 := preview_palette_style(config, 6, bg)
	color6ul := vaxis.Style{
		fg:       color_from_palette(config, 6)
		bg:       bg
		ul_style: .single
	}
	color10 := preview_palette_style(config, 10, bg)
	color12 := preview_palette_style(config, 12, bg)
	color238 := preview_palette_style(config, 238, bg)
	right := x_off + width
	sample_bottom := min_int(next_row + 24, height)
	pane.child(vaxis.WindowChildOptions{
		x_off:  0
		y_off:  next_row
		width:  pane.width
		height: 24
	}).fill(vaxis.Cell{ style: standard })
	self.put_window_preview_segments(pane, x_off, next_row, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '→', style: color2 },
		PreviewSegment{ text: ' ', style: standard },
		PreviewSegment{ text: 'bat', style: color4 },
		PreviewSegment{ text: ' ', style: standard },
		PreviewSegment{ text: 'ziggzagg.zig', style: color6ul },
	])
	self.put_window_preview_segment(pane, x_off, next_row + 1, x_off + 2, right, height,
		'───────┬${'─'.repeat(max_int(width - 10, 0))}', color238)
	self.put_window_preview_segments(pane, x_off, next_row + 2, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '       │ ', style: color238 },
		PreviewSegment{ text: 'File: ', style: standard },
		PreviewSegment{ text: 'ziggzagg.zig', style: standard_bold },
	])
	self.put_window_preview_segment(pane, x_off, next_row + 3, x_off + 2, right, height,
		'───────┼${'─'.repeat(max_int(width - 10, 0))}', color238)
	self.put_window_preview_segments(pane, x_off, next_row + 4, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   1   │ ', style: color238 },
		PreviewSegment{ text: 'const', style: color5 },
		PreviewSegment{ text: ' std ', style: standard },
		PreviewSegment{ text: '= @import', style: color5 },
		PreviewSegment{ text: '(', style: standard },
		PreviewSegment{ text: '"std"', style: color10 },
		PreviewSegment{ text: ');', style: standard },
	])
	self.put_window_preview_segment(pane, x_off, next_row + 5, x_off + 2, right, height, '   2   │', color238)
	self.put_window_preview_segments(pane, x_off, next_row + 6, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   3   │ ', style: color238 },
		PreviewSegment{ text: 'pub ', style: color5 },
		PreviewSegment{ text: 'fn ', style: color12 },
		PreviewSegment{ text: 'main', style: color2 },
		PreviewSegment{ text: '() ', style: standard },
		PreviewSegment{ text: '!', style: color5 },
		PreviewSegment{ text: 'void', style: color12 },
		PreviewSegment{ text: ' {', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 7, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   4   │     ', style: color238 },
		PreviewSegment{ text: 'const ', style: color5 },
		PreviewSegment{ text: 'stdout ', style: standard },
		PreviewSegment{ text: '=', style: color5 },
		PreviewSegment{ text: ' std.Io.getStdOut().writer();', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 8, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   5   │     ', style: color238 },
		PreviewSegment{ text: 'var ', style: color5 },
		PreviewSegment{ text: 'i:', style: standard },
		PreviewSegment{ text: ' usize', style: color12 },
		PreviewSegment{ text: ' =', style: color5 },
		PreviewSegment{ text: ' 1', style: color4 },
		PreviewSegment{ text: ';', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 9, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   6   │     ', style: color238 },
		PreviewSegment{ text: 'while ', style: color5 },
		PreviewSegment{ text: '(i ', style: standard },
		PreviewSegment{ text: '<= ', style: color5 },
		PreviewSegment{ text: '16', style: color4 },
		PreviewSegment{ text: ') : (i ', style: standard },
		PreviewSegment{ text: '+= ', style: color5 },
		PreviewSegment{ text: '1', style: color4 },
		PreviewSegment{ text: ') {', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 10, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   7   │         ', style: color238 },
		PreviewSegment{ text: 'if ', style: color5 },
		PreviewSegment{ text: '(i ', style: standard },
		PreviewSegment{ text: '% ', style: color5 },
		PreviewSegment{ text: '15 ', style: color4 },
		PreviewSegment{ text: '== ', style: color5 },
		PreviewSegment{ text: '0', style: color4 },
		PreviewSegment{ text: ') {', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 11, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   8   │             ', style: color238 },
		PreviewSegment{ text: 'try ', style: color5 },
		PreviewSegment{ text: 'stdout.writeAll(', style: standard },
		PreviewSegment{ text: '"ZiggZagg', style: color10 },
		PreviewSegment{ text: '\\n', style: color12 },
		PreviewSegment{ text: '"', style: color10 },
		PreviewSegment{ text: ');', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 12, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '   9   │         ', style: color238 },
		PreviewSegment{ text: '} ', style: standard },
		PreviewSegment{ text: 'else if ', style: color5 },
		PreviewSegment{ text: '(i ', style: standard },
		PreviewSegment{ text: '% ', style: color5 },
		PreviewSegment{ text: '3 ', style: color4 },
		PreviewSegment{ text: '== ', style: color5 },
		PreviewSegment{ text: '0', style: color4 },
		PreviewSegment{ text: ') {', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 13, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  10   │             ', style: color238 },
		PreviewSegment{ text: 'try ', style: color5 },
		PreviewSegment{ text: 'stdout.writeAll(', style: standard },
		PreviewSegment{ text: '"Zigg', style: color10 },
		PreviewSegment{ text: '\\n', style: color12 },
		PreviewSegment{ text: '"', style: color10 },
		PreviewSegment{ text: ');', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 14, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  11   │         ', style: color238 },
		PreviewSegment{ text: '} ', style: standard },
		PreviewSegment{ text: 'else if ', style: color5 },
		PreviewSegment{ text: '(i ', style: standard },
		PreviewSegment{ text: '% ', style: color5 },
		PreviewSegment{ text: '5 ', style: color4 },
		PreviewSegment{ text: '== ', style: color5 },
		PreviewSegment{ text: '0', style: color4 },
		PreviewSegment{ text: ') {', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 15, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  12   │             ', style: color238 },
		PreviewSegment{ text: 'try ', style: color5 },
		PreviewSegment{ text: 'stdout.writeAll(', style: standard },
		PreviewSegment{ text: '"Zagg', style: color10 },
		PreviewSegment{ text: '\\n', style: color12 },
		PreviewSegment{ text: '"', style: color10 },
		PreviewSegment{ text: ');', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 16, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  13   │         ', style: color238 },
		PreviewSegment{ text: '} ', style: standard },
		PreviewSegment{ text: 'else ', style: color5 },
		PreviewSegment{ text: '{', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 17, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  14   │             ', style: color238 },
		PreviewSegment{ text: 'try ', style: color5 },
		PreviewSegment{ text: 'stdout.print("{d}\\n", .{i})', style: standard_selection },
		PreviewSegment{ text: ';', style: cursor },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 18, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  15   │         ', style: color238 },
		PreviewSegment{ text: '}', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 19, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  16   │     ', style: color238 },
		PreviewSegment{ text: '}', style: standard },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 20, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '  17   │ ', style: color238 },
		PreviewSegment{ text: '}', style: standard },
	])
	self.put_window_preview_segment(pane, x_off, next_row + 21, x_off + 2, right, height,
		'───────┴${'─'.repeat(max_int(width - 10, 0))}', color238)
	self.put_window_preview_segments(pane, x_off, next_row + 22, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: 'witty ', style: color6 },
		PreviewSegment{ text: 'on ', style: standard },
		PreviewSegment{ text: ' main ', style: color4 },
		PreviewSegment{ text: '[+] ', style: color1 },
		PreviewSegment{ text: 'via ', style: standard },
		PreviewSegment{ text: ' v0.13.0 ', style: color3 },
		PreviewSegment{ text: 'via ', style: standard },
		PreviewSegment{ text: '  impure (witty-env)', style: color4 },
	])
	self.put_window_preview_segments(pane, x_off, next_row + 23, x_off + 2, right, sample_bottom, [
		PreviewSegment{ text: '✦ ', style: color4 },
		PreviewSegment{ text: 'at ', style: standard },
		PreviewSegment{ text: '10:36:15 ', style: color3 },
		PreviewSegment{ text: '→', style: color2 },
	])
	next_row += 24
	if next_row < height {
		pane.child(vaxis.WindowChildOptions{
			x_off:  0
			y_off:  next_row
			width:  pane.width
			height: u16(height - next_row)
		}).fill(vaxis.Cell{ style: standard })
	}

	words := lorem_ipsum.split_any(' \n')
	mut row := next_row + 1
	mut col := x_off + 2
	mut word_index := 0
	for row < height && words.len > 0 {
		word := words[word_index]
		word_index = (word_index + 1) % words.len
		word_width := word.len
		if col + word_width > x_off + width {
			row++
			col = x_off + 2
		}
		if row >= height {
			break
		}
		style := match word {
			'ipsum' {
				vaxis.Style{
					fg: color_from_palette(config, 2)
					bg: bg
				}
			}
			'consectetur' {
				standard_bold
			}
			'reprehenderit' {
				standard_italic
			}
			'Praesent' {
				standard_bold_italic
			}
			'auctor' {
				standard_underline
			}
			'dui' {
				standard_double_underline
			}
			'erat' {
				standard_dashed_underline
			}
			'enim' {
				standard_dotted_underline
			}
			'odio' {
				standard_curly_underline
			}
			else {
				standard
			}
		}

		self.put_window_preview_segment(pane, x_off, row, col, x_off + width, height, word, style)
		col += word_width + 1
	}
	return
}
