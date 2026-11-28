module ui2_runtime

import apprt
import datastruct
import input
import internal_os
import log
import math
import ui2

const bar_height = 34.0
const scrollbar_box = ui2.BoxStyle{ bg: 0x686b71, radius: 2 }
const foreground = ui2.TextStyle{ color: 0xe8e9ec, size: 13 }
const panel = ui2.BoxStyle{ bg: 0x25272b, radius: 6 }
const control = ui2.BoxStyle{ bg: 0x393c42, radius: 4 }

enum DialogAction {
	none
	quit
	close
	close_tabs
	clipboard
}

struct Dialog {
	title     string
	message   string
	button    string
	action    DialogAction
	pane_id   int
	panes     []int
	clipboard ?apprt.ClipboardRequest
}

fn (mut app App) screen(bounds ui2.Rect) ui2.Element {
	mut children := []ui2.Element{}
	mut top := 0.0
	if app.tabs.len > 0 {
		if app.show_tabs() {
			children << app.tab_bar(bounds.width)
			top = bar_height
		}
		mut tab := &app.tabs[app.active_tab]
		root := tab.tree.zoomed or { datastruct.handle_root }
		layout_panes(&tab.tree, root, ui2.rect(0, top, bounds.width,
			math.max(1, bounds.height - top)), app.runtime.config.scrollbar != .never, mut children)
		if current := app.active_pane() {
			if current.search { children << current.find_panel() }
		}
	}
	if app.toast != '' {
		width := math.min(360, bounds.width - 24)
		children << ui2.view('toast', ui2.rect(bounds.width - width - 12, top + 12, width, 44),
			panel, [ui2.label('', app.toast, ui2.rect(12, 0, width - 24, 44), foreground)])
	}
	if app.palette { children << app.palette_view(bounds) }
	if menu := app.context_menu { children << context_view(menu, bounds) }
	if dialog := app.dialog { children << dialog_view(dialog, bounds) }
	return ui2.screen(0x202124, children)
}

fn (app &App) show_tabs() bool {
	if app.screenshot != '' { return false }
	return match app.runtime.config.window_show_tab_bar {
		.always { true }
		.auto { app.tabs.len > 1 }
		.never { false }
	}
}

fn (app &App) tab_bar(width f64) ui2.Element {
	mut items := []ui2.Element{}
	tab_width := math.min(200, math.max(1, (width - 32) / f64(app.tabs.len)))
	for i, tab in app.tabs {
		node := tab.tree.nodes[tab.active.idx()]
		if node is datastruct.Leaf[Pane] {
			style := if i == app.active_tab { control } else { panel }
			items << ui2.button('select-tab-${i}', node.view.title,
				ui2.rect(f64(i) * tab_width, 2, math.max(1, tab_width - 2), bar_height - 4), style, foreground)
		}
	}
	items << ui2.button('new-tab', '+', ui2.rect(width - 30, 2, 28, bar_height - 4), control, foreground)
	return ui2.view('tabs', ui2.rect(0, 0, width, bar_height), panel, items)
}

fn layout_panes(tree &datastruct.SplitTree[Pane], handle datastruct.Handle, frame ui2.Rect, show_scrollbar bool, mut elements []ui2.Element) {
	node := tree.nodes[handle.idx()]
	match node {
		datastruct.Leaf[Pane] {
			mut pane := unsafe { node.view }
			pane.frame = frame
			elements << ui2.opengl(pane.element_id(), frame)
			$if macos {
				// A newly visible pane can register before its texture is ready.
				if !pane.presentation.direct && pane.presentation.image.id == 0 { ui2.request_paint() }
			}
			if show_scrollbar {
				if rect := pane.scrollbar_frame() {
					elements << ui2.view('', rect, scrollbar_box, [])
				}
			}
			if pane.readonly {
				elements << ui2.view('', ui2.rect(frame.x + 8, frame.y + 8, 82, 24), panel,
					[ui2.label('', internal_os.translate('Read only'), ui2.rect(8, 0, 66, 24), foreground)])
			}
			if progress := pane.progress {
				elements << ui2.view('', ui2.rect(frame.x, frame.y + frame.height - 3,
					frame.width * f64(progress) / 100, 3), ui2.BoxStyle{ bg: 0x6eaeff }, [])
			}
		}
		datastruct.Split {
			ratio := f64(node.ratio.f32())
			if node.layout == .horizontal {
				first := math.floor(frame.width * ratio)
				layout_panes(tree, node.left, ui2.rect(frame.x, frame.y, math.max(1, first - 1),
					frame.height), show_scrollbar, mut elements)
				layout_panes(tree, node.right, ui2.rect(frame.x + first + 1, frame.y,
					math.max(1, frame.width - first - 1), frame.height), show_scrollbar, mut elements)
			} else {
				first := math.floor(frame.height * ratio)
				layout_panes(tree, node.left, ui2.rect(frame.x, frame.y, frame.width,
					math.max(1, first - 1)), show_scrollbar, mut elements)
				layout_panes(tree, node.right, ui2.rect(frame.x, frame.y + first + 1, frame.width,
					math.max(1, frame.height - first - 1)), show_scrollbar, mut elements)
			}
		}
	}
}

fn (pane &Pane) scrollbar_frame() ?ui2.Rect {
	scroll := pane.scrollbar
	if scroll.total <= scroll.len || scroll.len == 0 { return none }
	frame := pane.frame
	height := math.max(12, frame.height * f64(scroll.len) / f64(scroll.total))
	offset := (frame.height - height) * f64(scroll.offset) / f64(scroll.total - scroll.len)
	return ui2.rect(frame.x + frame.width - 6, frame.y + offset, 5, height)
}

fn (pane &Pane) find_rect() ui2.Rect {
	width := math.max(1, math.min(340, pane.frame.width - 16))
	return ui2.rect(pane.frame.x + pane.frame.width - width - 8, pane.frame.y + 8, width, 40)
}

fn (pane &Pane) find_panel() ui2.Element {
	frame := pane.find_rect()
	mut status := ''
	if total := pane.matches {
		selected := pane.selected or { uint(0) }
		status = '${selected} / ${total}'
	}
	return ui2.view('find', frame, panel, [
		ui2.text_field_with_change_and_submit('find-query', 'find-next', internal_os.translate('Find in terminal'), pane.query,
			ui2.rect(6, 6, math.max(1, frame.width - 148), 28), control, foreground, 0),
		ui2.label('', status, ui2.rect(frame.width - 136, 6, 46, 28), foreground),
		ui2.button('find-previous', '↑', ui2.rect(frame.width - 90, 6, 26, 28), control, foreground),
		ui2.button('find-next-button', '↓', ui2.rect(frame.width - 62, 6, 26, 28), control, foreground),
		ui2.button('find-close', '×', ui2.rect(frame.width - 34, 6, 26, 28), control, foreground),
	])
}

fn (app &App) over_find(x f64, y f64) bool {
	pane := app.active_pane() or { return false }
	if !pane.search { return false }
	frame := pane.find_rect()
	return x >= frame.x && y >= frame.y && x < frame.x + frame.width && y < frame.y + frame.height
}

fn (mut pane Pane) end_find() {
	pane.surface.perform_binding_action(input.ActionEndSearch{}) or { log.warn(err.msg()) }
}

fn dialog_view(dialog Dialog, bounds ui2.Rect) ui2.Element {
	width := math.max(1, math.min(460, bounds.width - 24))
	height := math.max(1, math.min(220, bounds.height - 24))
	mut items := [
		ui2.label('', dialog.title, ui2.rect(16, 8, width - 32, 30),
			ui2.TextStyle{ ...foreground, bold: true, size: 16 }),
		ui2.label('', dialog.message, ui2.rect(16, 44, width - 32, height - 100),
			ui2.TextStyle{ ...foreground, lines: 0, valign: .top }),
		ui2.button('dialog-cancel', if dialog.action == .none { internal_os.translate('OK') } else { internal_os.translate('Cancel') },
			ui2.rect(width - 200, height - 46, 78, 32), control, foreground),
	]
	if dialog.action != .none {
		items << ui2.button('dialog-confirm', dialog.button, ui2.rect(width - 110, height - 46, 94, 32),
			control, foreground)
	}
	return ui2.view('modal', bounds, ui2.BoxStyle{ bg: 0x141518 }, [
		ui2.view('dialog', ui2.rect((bounds.width - width) / 2, (bounds.height - height) / 2,
			width, height), panel, items),
	])
}

fn handle_control(id string) {
	mut app := g_app
	if dialog := app.dialog {
		match id {
			'dialog-cancel' { app.dialog = none }
			'dialog-confirm' {
				app.dialog = none
				match dialog.action {
					.none {}
					.quit { quit_window() }
					.close { app.close_pane(dialog.pane_id) }
					.close_tabs {
						for pane in dialog.panes { app.close_pane(pane) }
					}
					.clipboard {
						if request := dialog.clipboard {
							mut pane := app.pane_by_id(dialog.pane_id) or { return }
							pane.surface.complete_clipboard_request(request, dialog.message, true) or { log.warn(err.msg()) }
						}
					}
				}
			}
			else {}
		}
		return
	}
	if app.palette {
		app.select_command(id)
		return
	}
	if app.context_menu != none {
		app.select_context_item(id)
		return
	}
	if id.starts_with('select-tab-') {
		index := id.all_after('select-tab-').int()
		if index < app.tabs.len { app.select_pane(index, app.tabs[index].active) }
		return
	}
	if id == 'new-tab' {
		app.new_tab(app.active_pane()) or { log.warn(err.msg()) }
		return
	}
	mut pane := app.active_pane() or { return }
	match id {
		'find-query' {
			pane.query = ui2.text(id).clone()
			pane.surface.perform_binding_action(input.ActionSearch{ value: pane.query }) or { log.warn(err.msg()) }
		}
		'find-next', 'find-next-button', 'find-previous' {
			pane.surface.perform_binding_action(input.ActionNavigateSearch{
				value: if id == 'find-previous' { .previous } else { .next }
			}) or { log.warn(err.msg()) }
		}
		'find-close' { pane.end_find() }
		else {}
	}
}
