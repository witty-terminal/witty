module ui2_runtime

import apprt
import ui2

fn supports_clipboard(_ voidptr, clipboard apprt.Clipboard) bool {
	$if !linux {
		if clipboard != .standard { return false }
	}
	return ui2.clipboard_supported()
}

fn clipboard_request(data voidptr, clipboard apprt.Clipboard, request apprt.ClipboardRequest) !bool {
	mut pane := unsafe { &Pane(data) }
	text := if clipboard == .standard {
		ui2.clipboard_text() or { '' }
	} else {
		ui2.primary_selection_text() or { '' }
	}
	pane.surface.complete_clipboard_request(request, text, false) or {
		if err.msg() !in ['UnauthorizedPaste', 'UnsafePaste', 'BracketedPaste'] { return err }
		mut app := g_app
		app.dialog = Dialog{
			title:     if request.tag() == .paste {
				'Paste into terminal?'
			} else {
				'Allow reading the clipboard?'
			}
			message:   text
			button:    if request.tag() == .paste { 'Paste' } else { 'Allow' }
			action:    .clipboard
			pane_id:   pane.id
			clipboard: request
		}
		ui2.request_refresh()
	}
	return true
}

fn set_clipboard(data voidptr, clipboard apprt.Clipboard, contents []apprt.ClipboardContent, confirm bool) ! {
	pane := unsafe { &Pane(data) }
	for content in contents {
		if !content.mime.starts_with('text/plain') { continue }
		if confirm {
			mut app := g_app
			app.dialog = Dialog{
				title:     'Allow writing to the clipboard?'
				message:   content.data
				button:    'Allow'
				action:    .clipboard
				pane_id:   pane.id
				clipboard: apprt.ClipboardRequestOsc52Write{ clipboard: clipboard }
			}
			ui2.request_refresh()
		} else {
			ok := if clipboard == .standard {
				ui2.set_clipboard_text(content.data)
			} else {
				ui2.set_primary_selection(content.data)
			}
			if !ok { return error('could not update the system clipboard') }
		}
		return
	}
}
