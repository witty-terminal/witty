module ui2_runtime

import input
import log
import math
import ui2

fn (app &App) palette_view(bounds ui2.Rect) ui2.Element {
	width := math.max(1, math.min(bounds.width - 24, 460))
	height := math.max(1, math.min(bounds.height - 24, 340))
	mut rows := []ui2.Element{}
	query := app.palette_query.to_lower()
	for i, command in app.runtime.config.command_palette_entry.items {
		if command.action.tag() == .show_gtk_inspector { continue }
		if !command.title.to_lower().contains(query) && !command.description.to_lower().contains(query) {
			continue
		}
		rows << ui2.button('palette-command-${i}', command.title,
			ui2.rect(0, f64(rows.len) * 32, width - 24, 30), control, foreground)
	}
	return ui2.view('palette-overlay', bounds, ui2.BoxStyle{ bg: 0x141518 }, [
		ui2.view('palette', ui2.rect((bounds.width - width) / 2, 12, width, height), panel, [
			ui2.text_field_with_change('palette-query', 'Find a command', app.palette_query,
				ui2.rect(12, 12, width - 24, 32), control, foreground, 0),
			ui2.scroll('palette-items', ui2.rect(12, 52, width - 24, height - 64), 0x25272b, rows),
		]),
	])
}

fn (mut app App) select_command(id string) {
	if id == 'palette-query' {
		app.palette_query = ui2.text(id).clone()
		return
	}
	if !id.starts_with('palette-command-') { return }
	index := id.all_after('palette-command-').int()
	commands := app.runtime.config.command_palette_entry.items
	if index >= commands.len { return }
	action := commands[index].action
	app.palette = false
	ui2.focus('')
	if action.scope() == .app {
		app.core.perform_action(mut app.runtime, action) or { log.warn(err.msg()) }
	} else if current := app.active_pane() {
		mut pane := unsafe { current }
		pane.surface.perform_binding_action(action) or { log.warn(err.msg()) }
	}
}

fn context_view(frame ui2.Rect, bounds ui2.Rect) ui2.Element {
	labels := ['Copy', 'Paste', 'Find…', 'New Tab', 'Split Right']
	mut rows := []ui2.Element{}
	for i, label in labels {
		rows << ui2.button('context-${i}', label,
			ui2.rect(4, f64(i) * 31 + 4, frame.width - 8, 29), control, foreground)
	}
	return ui2.view('', bounds, ui2.BoxStyle{ transparent: true }, [
		ui2.button('context-dismiss', '', bounds, ui2.BoxStyle{ transparent: true }, foreground),
		ui2.view('context-menu', frame, panel, rows),
	])
}

fn (mut app App) select_context_item(id string) {
	app.context_menu = none
	mut pane := app.active_pane() or { return }
	action := match id {
		'context-0' { input.Action(input.ActionCopyToClipboard{}) }
		'context-1' { input.Action(input.ActionPasteFromClipboard{}) }
		'context-2' { input.Action(input.ActionStartSearch{}) }
		'context-3' {
			app.new_tab(pane) or { log.warn(err.msg()) }
			return
		}
		'context-4' {
			app.new_split(.right) or { log.warn(err.msg()) }
			return
		}
		else { return }
	}
	pane.surface.perform_binding_action(action) or { log.warn(err.msg()) }
}
