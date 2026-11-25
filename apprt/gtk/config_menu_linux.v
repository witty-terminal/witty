module gtk

import configpkg
import core

fn config_menu_new() GMenu {
	menu := C.g_menu_new()
	surface_menu_append(menu, 'Open Configuration in OS Editor', c'app.open-config')
	surface_menu_append(menu, 'Open Configuration in New Window', c'app.open-config-new-window')
	surface_menu_append(menu, 'Reload Configuration', c'app.reload-config')
	return menu
}

fn config_editor_launch_options(path string, visual string, editor string) core.SurfaceInitOptions {
	command := if visual.len > 0 {
		visual
	} else if editor.len > 0 {
		editor
	} else {
		'vi'
	}
	// Editor settings may include shell arguments. Pass the path separately so
	// filenames containing whitespace and shell characters remain one argument.
	return core.SurfaceInitOptions{
		command: configpkg.Command(configpkg.DirectCmd{
			direct: ['/bin/sh', '-c', command + ' "$1"', 'witty-config-editor', path]
		})
		title:   '${i18n_('Editing configuration file')} ${path}'
	}
}
