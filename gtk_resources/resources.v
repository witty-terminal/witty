// Translation of Ghostty src/apprt/gtk/build/{gresource,blueprint}.zig
// and src/build/SharedDeps.zig:gtkNgDistResources. Resources keep source bytes.
module gtk_resources

import os
import semver
import strings

pub const prefix = '/com/alexander/witty'
pub const app_id = 'com.alexander.witty'
pub const icon_sizes = [16, 32, 128, 256, 512, 1024]!
pub const css = ['style.css', 'style-dark.css', 'style-hc.css', 'style-hc-dark.css']!

pub struct Blueprint {
pub:
	major u16
	minor u16
	name string
}

pub const blueprints = [
	Blueprint{major: 1, minor: 0, name: 'clipboard-confirmation-dialog'},
	Blueprint{major: 1, minor: 4, name: 'clipboard-confirmation-dialog'},
	Blueprint{major: 1, minor: 2, name: 'close-confirmation-dialog'},
	Blueprint{major: 1, minor: 2, name: 'config-errors-dialog'},
	Blueprint{major: 1, minor: 2, name: 'debug-warning'},
	Blueprint{major: 1, minor: 3, name: 'debug-warning'},
	Blueprint{major: 1, minor: 5, name: 'imgui-widget'},
	Blueprint{major: 1, minor: 5, name: 'inspector-widget'},
	Blueprint{major: 1, minor: 5, name: 'inspector-window'},
	Blueprint{major: 1, minor: 2, name: 'resize-overlay'},
	Blueprint{major: 1, minor: 2, name: 'search-overlay'},
	Blueprint{major: 1, minor: 2, name: 'key-state-overlay'},
	Blueprint{major: 1, minor: 5, name: 'split-tree'},
	Blueprint{major: 1, minor: 5, name: 'split-tree-split'},
	Blueprint{major: 1, minor: 2, name: 'surface'},
	Blueprint{major: 1, minor: 5, name: 'surface-scrolled-window'},
	Blueprint{major: 1, minor: 5, name: 'surface-title-dialog'},
	Blueprint{major: 1, minor: 3, name: 'surface-child-exited'},
	Blueprint{major: 1, minor: 5, name: 'tab'},
	Blueprint{major: 1, minor: 5, name: 'window'},
	Blueprint{major: 1, minor: 5, name: 'command-palette'},
]!

pub fn blueprint_resource(bp Blueprint) !string {
	for candidate in blueprints {
		if candidate == bp { return '${prefix}/ui/${bp.major}.${bp.minor}/${bp.name}.ui' }
	}
	return error('BlueprintNotFound')
}

// The generator checks each CSS/icon input before emitting the original
// resource aliases. UI inputs are matched by their source suffix.
pub fn xml(repo_root string, ui_files []string) !string {
	mut output := strings.new_builder(4096)
	output.write_string('<?xml version="1.0" encoding="UTF-8"?>\n<gresources>\n')
	output.write_string('  <gresource prefix="${prefix}">\n')
	for name in css {
		path := os.join_path(repo_root, 'apprt', 'gtk', name)
		if !os.exists(path) { return error('FileNotFound: ${path}') }
		output.write_string('    <file compressed="true" alias="${name}">${path}</file>\n')
	}
	output.write_string('  </gresource>\n  <gresource prefix="${prefix}/icons">\n')
	for size in icon_sizes {
		for scale in [1, 2] {
			path := os.join_path(repo_root, 'images', 'gnome', '${size * scale}.png')
			if !os.exists(path) { return error('FileNotFound: ${path}') }
			alias := if scale == 1 { '${size}x${size}' } else { '${size}x${size}@2' }
			output.write_string('    <file alias="${alias}/apps/${app_id}.png">${path}</file>\n')
		}
	}
	output.write_string('  </gresource>\n  <gresource prefix="${prefix}/ui">\n')
	for path in ui_files {
		mut found := false
		for bp in blueprints {
			suffix := '/${bp.major}.${bp.minor}/${bp.name}.ui'
			if !path.ends_with(suffix) { continue }
			output.write_string('    <file compressed="true" preprocess="xml-stripblanks" alias="${bp.major}.${bp.minor}/${bp.name}.ui">${path}</file>\n')
			found = true
			break
		}
		if !found { return error('BlueprintNotFound') }
	}
	output.write_string('  </gresource>\n</gresources>\n')
	return output.str()
}

pub fn compile_blueprint(bp Blueprint, adwaita_version string, output string, input string) ! {
	actual := semver.from(adwaita_version)!
	required := semver.build(int(bp.major), int(bp.minor), 0)
	if actual < required { return error('libadwaita is too old: requires ${required}') }
	version_output := run('blueprint-compiler', ['--version'])!
	version := semver.from(version_output.trim_space())!
	if version < semver.build(0, 16, 0) { return error('blueprint-compiler requires version 0.16.0 or newer') }
	_ = run('blueprint-compiler', ['compile', '--output', output, input])!
}

pub fn build(repo_root string, adwaita_version string) !string {
	output := os.join_path(repo_root, '.witty-build', 'gtk')
	os.mkdir_all(output)!
	mut ui_files := []string{cap: blueprints.len}
	for bp in blueprints {
		version := '${bp.major}.${bp.minor}'
		input := os.join_path(repo_root, 'apprt', 'gtk', 'ui', version, bp.name + '.blp')
		ui := os.join_path(output, version, bp.name + '.ui')
		os.mkdir_all(os.dir(ui))!
		compile_blueprint(bp, adwaita_version, ui, input)!
		ui_files << ui
	}
	xml_path := os.join_path(output, 'witty.gresource.xml')
	os.write_file(xml_path, xml(repo_root, ui_files)!)!
	c_path := os.join_path(output, 'witty_resources.c')
	h_path := os.join_path(output, 'witty_resources.h')
	_ = run('glib-compile-resources', ['--c-name', 'ghostty', '--generate-source', '--target', c_path, xml_path])!
	_ = run('glib-compile-resources', ['--c-name', 'ghostty', '--generate-header', '--target', h_path, xml_path])!
	return c_path
}

$if !windows {
	#include <poll.h>
	#include <unistd.h>
	#include <errno.h>
}
fn C.poll(voidptr, u32, int) int
fn C.read(int, voidptr, uint) int

struct ResourcePollFd {
mut:
	fd i32 // C pollfd stores the descriptor in a 32-bit int.
	events i16
	revents i16
}

// process.Child.collectOutput uses Io.poll to drain both pipes, checking each
// accumulated stream separately after each poll. Preserve that algorithm and
// its 65535-byte bound rather than slurping an unbounded process stream.
fn collect_output(mut process os.Process) !(string, string) {
	// GTK resources are only built for GTK targets; Windows has no poll(2).
	$if windows {
		return error('GTK resource compilation is not supported on Windows')
	} $else {
		mut stdout := []u8{}
		mut stderr := []u8{}
		mut fds := [ResourcePollFd{fd: i32(process.stdio_fd[1]), events: i16(C.POLLIN)}, ResourcePollFd{fd: i32(process.stdio_fd[2]), events: i16(C.POLLIN)}]!
		mut buffer := []u8{len: 4096}
		for fds[0].fd >= 0 || fds[1].fd >= 0 {
			if C.poll(&fds[0], 2, -1) < 0 {
				if C.errno == C.EINTR { continue }
				return os.error_posix()
			}
			for index in 0 .. 2 {
				if fds[index].fd < 0 || fds[index].revents == 0 { continue }
				count := C.read(fds[index].fd, buffer.data, uint(buffer.len))
				if count < 0 {
					if C.errno in [C.EINTR, C.EAGAIN] { continue }
					return os.error_posix()
				}
				if count == 0 { fds[index].fd = -1; continue }
				if index == 0 { stdout << buffer[..int(count)] } else { stderr << buffer[..int(count)] }
			}
			if stdout.len > 65535 { return error('StdoutStreamTooLong') }
			if stderr.len > 65535 { return error('StderrStreamTooLong') }
		}
		return stdout.bytestr(), stderr.bytestr()
	}
}

fn run(executable string, args []string) !string {
	mut process := os.new_process(executable)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	output, errors := collect_output(mut process) or {
		process.signal_kill()
		process.wait()
		process.close()
		return err
	}
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${executable} failed (${code}): ${errors}') }
	return output
}
