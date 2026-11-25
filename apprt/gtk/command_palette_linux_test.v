module gtk

import configpkg
import input

fn test_command_palette_action_accelerator_from_config_keybind() {
	mut inner := configpkg.Config{}
	inner.keybind.parse_cli('ctrl+shift+a=new_window')!
	mut cfg := config_new(inner)
	mut command := Command.new(cfg, input.Command{
		action: input.ActionNewWindow{}
		title:  'New Window'
	})

	assert command.prop_get_action() or { '' } == '<Shift><Ctrl>a'
	// The derived value is cached just as it is in Ghostty's GObject wrapper.
	assert command.prop_get_action() or { '' } == '<Shift><Ctrl>a'

	command.dispose()
	cfg.unref()
}

fn test_command_palette_action_without_keybind_is_none() {
	mut cfg := config_new(configpkg.Config{})
	mut command := Command.new(cfg, input.Command{
		action: input.ActionNewWindow{}
		title:  'New Window'
	})

	assert command.prop_get_action() == none

	command.dispose()
	cfg.unref()
}

fn test_regular_command_has_no_jump_surface() {
	mut cfg := config_new(configpkg.Config{})
	mut command := Command.new(cfg, input.Command{
		action: input.ActionNewWindow{}
		title:  'New Window'
	})

	assert command.get_jump_surface() == none

	command.dispose()
	cfg.unref()
}

fn test_command_data_retains_only_the_active_payload() {
	regular := Command{
		data: RegularData{
			command: input.Command{
				action: input.ActionIgnore{}
				title:  'Regular'
			}
		}
	}
	assert regular.data is RegularData
	assert !regular.is_jump()

	jump := Command{
		data: JumpData{
			sort_key: 42
		}
	}
	assert jump.data is JumpData
	assert jump.is_jump()
	assert jump.get_action() == none
}

fn test_command_palette_action_key_uses_full_action_format() {
	mut cfg := config_new(configpkg.Config{})
	mut command := Command.new(cfg, input.Command{
		action: input.ActionText{
			value: 'hello world'
		}
		title:  'Type Text'
	})

	assert command.prop_get_action_key() or { '' } == 'text:hello world'

	command.dispose()
	cfg.unref()
}

fn C.gtk_single_selection_get_model(GtkSingleSelection) voidptr
fn C.gtk_filter_list_model_get_pending(voidptr) u32

fn settle_palette_filter(palette &CommandPalette) {
	model := C.gtk_single_selection_get_model(palette.model)
	for C.gtk_filter_list_model_get_pending(model) > 0 {
		C.g_main_context_iteration(unsafe { nil }, true)
	}
}

fn test_command_palette_native_filter_matches_title_or_action_key() {
	if !C.gtk_init_check() { return }
	C.adw_init()
	mut cfg := config_new(configpkg.Config{})
	mut palette := new_command_palette()
	palette.commands = [
		Command.new(cfg, input.Command{ action: input.ActionNewWindow{}, title: 'Open a Window' }),
		Command.new(cfg, input.Command{
			action: input.ActionCopyToClipboard{}
			title:  'Copy Selection'
		}),
	]
	for command in palette.commands {
		C.g_list_store_append(palette.source, command.obj)
	}
	for query, title in {
		'OPEN':              'Open a Window'
		'copy_to_clipboard': 'Copy Selection'
	} {
		C.gtk_editable_set_text(GtkWidget(palette.search), &char(query.str))
		settle_palette_filter(palette)
		assert C.g_list_model_get_n_items(palette.model) == 1
		obj := C.g_list_model_get_item(palette.model, 0)
		mut command := command_from_object(obj)?
		assert command.prop_get_title()? == title
		object_unref(obj)
	}
	C.gtk_editable_set_text(GtkWidget(palette.search), c'missing')
	settle_palette_filter(palette)
	assert C.g_list_model_get_n_items(palette.model) == 0
	palette.unref()
	palette.dialog_closed()
	cfg.unref()
}

fn palette_trigger_probe(_ GObject, action &input.Action, data voidptr) {
	mut result := unsafe { &input.Action(data) }
	unsafe {
		*result = *action
	}
}

fn test_command_palette_emits_native_trigger_signal() {
	if !C.gtk_init_check() { return }
	C.adw_init()
	mut palette := new_command_palette()
	mut received := input.Action(input.ActionIgnore{})
	C.g_signal_connect_data(palette.widget, c'trigger', GCallback(voidptr(palette_trigger_probe)),
		voidptr(&received), unsafe { nil }, 0)
	palette.emit_trigger(input.ActionNewWindow{})
	assert received == input.Action(input.ActionNewWindow{})
	palette.unref()
	palette.dialog_closed()
}

fn test_command_palette_uses_configured_entries() {
	// The palette builds real Adwaita widgets, which need GTK initialized
	// against a display. A headless test run has none, so skip there.
	if !C.gtk_init_check() {
		eprintln('skipping: GTK could not open a display')
		return
	}
	C.adw_init()
	mut inner := configpkg.Config.default_config()
	// Start from an empty list. `command-palette-entry =` would not do it: as in
	// Ghostty's cli/args.zig, an empty value resets a field with an `init` to
	// that `init`, which reloads the default entries.
	inner.command_palette_entry = configpkg.RepeatableCommand{}
	inner.load_string('command-palette-entry = title:Only Entry,description:Configured,action:ignore')
	inner.load_string('gtk-custom-css = palette.css')
	mut cfg := config_new(inner)
	mut palette := new_command_palette()
	mut weak := weak_ref_empty()
	weak.set(GObject(palette.widget))
	acquired := weak.get()
	assert !isnil(acquired)
	assert command_palette_from_object(acquired) or { panic('missing command palette wrapper') } == palette
	object_unref(acquired)
	palette.set_config(cfg)

	assert cfg.get().gtk_custom_css.items.len == 1
	assert C.witty_gtk_canvas_overlay_has_mask(GtkWidget(palette.dialog))
	assert palette.commands.len == 1
	mut command := palette.commands[0]
	assert command.prop_get_title() or { '' } == 'Only Entry'
	assert command.prop_get_description() or { '' } == 'Configured'
	assert command.get_action() or { panic('missing command action') } == input.Action(input.ActionIgnore{})

	// new_command_palette returns a caller reference in addition to the
	// self-reference released when the dialog closes.
	palette.unref()
	still_alive := weak.get()
	assert !isnil(still_alive)
	object_unref(still_alive)
	palette.dialog_closed()
	finalized := weak.get()
	assert isnil(finalized)
	cfg.unref()
}
