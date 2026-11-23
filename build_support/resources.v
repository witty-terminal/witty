module build_support

import buildcfg
import os

pub struct Driver {
pub:
	cfg Config
}

// native_dir holds compiled native archives. Host-target builds use the
// shared `native` directory that host tools link; other targets (the second
// architecture of a universal build, iOS slices, cross builds) get their own
// so their archives never overwrite the host's.
pub fn (d Driver) native_dir() string {
	host := host_target()
	if d.cfg.target.arch == host.arch && d.cfg.target.os == host.os && d.cfg.target.abi == host.abi {
		return d.cache_path('native')
	}
	mut name := 'native-${d.cfg.target.arch}-${d.cfg.target.os}'
	if d.cfg.target.abi.len > 0 { name += '-${d.cfg.target.abi}' }
	return d.cache_path(name)
}

pub fn (d Driver) cache_path(parts ...string) string {
	mut path := os.join_path(d.cfg.root, '.witty-build')
	for part in parts { path = os.join_path(path, part) }
	return path
}

pub fn (d Driver) install_text(relative string, text string) ! {
	path := os.join_path(d.cfg.prefix, relative)
	os.mkdir_all(os.dir(path))!
	os.write_file(path, text)!
}

pub fn (d Driver) install_file(source string, relative string) ! {
	path := os.join_path(d.cfg.prefix, relative)
	os.mkdir_all(os.dir(path))!
	os.cp(source, path)!
}

// Compilers append .exe to Windows executables; host tools must be invoked
// by that name because absolute paths are not resolved further.
pub fn host_executable(name string) string {
	return $if windows { name + '.exe' } $else { name }
}

pub fn (d Driver) host_tool(name string, folder string) !string {
	output := d.cache_path('host', host_executable(name))
	os.mkdir_all(os.dir(output))!
	// The source host generators do not initialize crash, SIMD, or gettext.
	mut args := [d.cfg.compiler, '-path', d.compiler_module_path()!, '-d', 'no_i18n']
	$if macos {
		// Some generators still link Breakpad through their imports.
		args << macos_bundled_gc_options
	}
	args << compile_options(d.cfg.root, .debug, .exe, d.cfg.version)!
	args << ['-cflags', '-fno-omit-frame-pointer', '-cflags', '-funwind-tables',
		'-o', output, os.join_path(d.cfg.root, folder)]
	checked_process(d.cfg.root, args) or { return error('building ${name}: ${err}') }
	return output
}

pub fn (d Driver) install_tree(source string, relative string, excluded_extensions []string) ! {
	for entry in os.ls(source)! {
		path := os.join_path(source, entry)
		destination := os.join_path(relative, entry)
		if os.is_dir(path) { d.install_tree(path, destination, excluded_extensions)!; continue }
		if excluded_extensions.any(entry.ends_with(it)) { continue }
		d.install_file(path, destination)!
	}
}

// GhosttyResources.init: terminfo is compiled for every non-Windows install,
// regardless of whether the optional source/termcap artifacts were selected.
pub fn (d Driver) install_resources() ! {
	tool := d.host_tool('ghostty-build-data', 'tools/build_data')!
	info := checked_process(d.cfg.root, [tool, '+terminfo'])!
	share_dir := if d.cfg.target.os == 'freebsd' { 'site-terminfo' } else { 'terminfo' }
	source := d.cache_path('resources', 'ghostty.terminfo')
	os.mkdir_all(os.dir(source))!
	os.write_file(source, info)!
	if d.cfg.emit_terminfo { d.install_file(source, 'share/${share_dir}/ghostty.terminfo')! }
	if d.cfg.target.os != 'windows' {
		if d.cfg.emit_termcap {
			cap := checked_process(d.cfg.root, ['infotocap', source])!
			d.install_text('share/${share_dir}/ghostty.termcap', cap)!
		}
		db := d.cache_path('resources', share_dir)
		checked_process(d.cfg.root, ['tic', '-x', '-o', db, source])!
		// InstallDir drops aliases which are symlinks. Preserve them exactly as
		// the source's cp -R step does, including the directory nesting.
		os.mkdir_all(os.join_path(d.cfg.prefix, 'share', share_dir))!
		checked_process(d.cfg.root, ['cp', '-R', db, os.join_path(d.cfg.prefix, 'share')])!
	}
	d.install_tree(os.join_path(d.cfg.root, 'shell-integration'), 'share/ghostty/shell-integration', ['.md'])!
	if d.cfg.emit_themes {
		d.install_tree(os.join_path(d.cfg.root, 'build_assets', 'themes'), 'share/ghostty/themes', ['.md'])!
	}
	linux := d.cfg.target.os == 'linux'
	command := if linux { buildcfg.linux_executable_name } else { 'ghostty' }
	for action, destination in {
		'fish': 'share/fish/vendor_completions.d/${command}.fish'
		'zsh': 'share/zsh/site-functions/_${command}'
		'bash': 'share/bash-completion/completions/${command}.bash'
	} {
		mut text := checked_process(d.cfg.root, [tool, '+${action}'])!
		if linux {
			text = match action {
				'fish' { text.replace('complete -c ghostty ', 'complete -c ${command} ').replace('(ghostty +', '(${command} +') }
				'zsh' { text.replace('#compdef ghostty', '#compdef ${command}').replace('_ghostty', '_${command}').replace('(ghostty +', '(${command} +') }
				else { text.replace('-F _ghostty ghostty', '-F _${command} ${command}').replace('_ghostty()', '_${command}()') }
			}
		}
		d.install_text(destination, text)!
	}
	d.install_text('share/bat/syntaxes/ghostty.sublime-syntax',
		checked_process(d.cfg.root, [tool, '+sublime'])!)!
	for action, relative in {
		'vim-syntax': 'syntax/ghostty.vim'
		'vim-ftdetect': 'ftdetect/ghostty.vim'
		'vim-ftplugin': 'ftplugin/ghostty.vim'
		'vim-compiler': 'compiler/ghostty.vim'
	} {
		mut text := checked_process(d.cfg.root, [tool, '+${action}'])!
		if linux && action == 'vim-compiler' {
			text = text.replace('makeprg=ghostty', 'makeprg=${command}')
		}
		for editor in ['share/vim/vimfiles', 'share/nvim/site'] { d.install_text('${editor}/${relative}', text)! }
	}
	if linux { d.install_linux_resources()! }
}

fn (d Driver) install_linux_resources() ! {
	debug := d.cfg.mode in [.debug, .release_safe]
	name := 'Ghostty${if debug { ' (Debug)' } else { '' }}'
	app_id := 'com.mitchellh.ghostty${if debug { '-debug' } else { '' }}'
	mut templates := {
		'app.desktop.in': 'share/applications/${app_id}.desktop'
		'dbus.service${if d.cfg.flatpak { '.flatpak' } else { '' }}.in': 'share/dbus-1/services/${app_id}.service'
		'com.mitchellh.ghostty.metainfo.xml.in': 'share/metainfo/${app_id}.metainfo.xml'
	}
	if !d.cfg.flatpak {
		templates['systemd.service.in'] = '${if d.cfg.system_package { 'lib' } else { 'share' }}/systemd/user/app-${app_id}.service'
	}
	for source, destination in templates {
		text := os.read_file(os.join_path(d.cfg.root, 'build_assets', 'dist', 'linux', source))!
		d.install_text(destination, text.replace('@NAME@', name).replace('@APPID@', app_id)
			.replace('@GHOSTTY@', os.join_path(d.cfg.prefix, 'bin', buildcfg.linux_executable_name)))!
	}
	for source, destination in {
		'ghostty_dolphin.desktop': 'share/kio/servicemenus/com.mitchellh.ghostty.desktop'
		'ghostty_nautilus.py': 'share/nautilus-python/extensions/ghostty.py'
	} { d.install_file(os.join_path(d.cfg.root, 'build_assets', 'dist', 'linux', source), destination)! }
	mut icons := {'16': '16x16', '32': '32x32', '128': '128x128', '256': '256x256', '512': '512x512'}
	if !d.cfg.flatpak { icons['1024'] = '1024x1024' }
	for source, size in icons {
		d.install_file(os.join_path(d.cfg.root, 'images', 'gnome', '${source}.png'),
			'share/icons/hicolor/${size}/apps/com.mitchellh.ghostty.png')!
	}
	for source, size in {'32': '16x16@2'} {
		d.install_file(os.join_path(d.cfg.root, 'images', 'gnome', '${source}.png'),
			'share/icons/hicolor/${size}/apps/com.mitchellh.ghostty.png')!
	}
}

pub fn (d Driver) install_docs() ! {
	if !d.cfg.emit_docs {
		if d.cfg.target.darwin() { d.install_text('share/man/.placeholder', 'emit-docs not true so no man pages')! }
		return
	}
	tool := d.host_tool('ghostty-docgen', 'tools/docgen')!
	for section in ['1', '5'] {
		text := checked_process(d.cfg.root, [tool, 'mdgen_ghostty_${section}'])!
		markdown := d.cache_path('docs', 'ghostty.${section}.md')
		os.mkdir_all(os.dir(markdown))!
		os.write_file(markdown, text)!
		d.install_file(markdown, 'share/ghostty/doc/ghostty.${section}.md')!
		for format in ['html', 'man'] {
			out := checked_process(d.cfg.root, ['pandoc', '--standalone', '--from', 'markdown', '--to', format, markdown])!
			d.install_text(if format == 'man' { 'share/man/man${section}/ghostty.${section}' }
				else { 'share/ghostty/doc/ghostty.${section}.html' }, out)!
		}
	}
}

pub fn (d Driver) install_webdata() ! {
	tool := d.host_tool('ghostty-webgen', 'tools/docgen')!
	for action in ['config', 'actions', 'commands'] {
		d.install_text('share/ghostty/webdata/${action}.mdx', checked_process(d.cfg.root, [tool, 'webgen_${action}'])!)!
	}
}
