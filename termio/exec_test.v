module termio

import build_meta
import command as commandpkg
import configpkg
import internal_os
import os
import renderer

// ============================================================
// exec_command tests
// ============================================================

// On macOS, exec_command uses login(1) with passwd-based username
// to create a login shell. On other platforms it wraps with /bin/sh.

fn test_exec_command_shell_posix() {
	// exec_command_posix for shell commands wraps with /bin/sh -c
	result := exec_command_posix(configpkg.ShellCmd{ shell: 'foo bar baz' })
	// Should be ["/bin/sh", "-c", "foo bar baz"] (possibly with -l for flatpak)
	assert result.len >= 3
	assert result[0] == '/bin/sh'
	// The last two should be "-c" and the command
	assert result[result.len - 2] == '-c'
	assert result[result.len - 1] == 'foo bar baz'
}

fn test_exec_command_direct_posix() {
	// exec_command_posix for direct commands returns the args directly
	result := exec_command_posix(configpkg.DirectCmd{ direct: ['foo', 'bar baz'] })
	assert result.len == 2
	assert result[0] == 'foo'
	assert result[1] == 'bar baz'
}

fn test_exec_command_darwin_shell() {
	$if macos {
		// On Darwin, exec_command should use login(1)
		result := exec_command(configpkg.ShellCmd{ shell: 'foo bar baz' })!
		// Result should start with /usr/bin/login
		assert result.len >= 1
		assert result[0] == '/usr/bin/login'
		// Should contain -flp and username
		mut has_flp := false
		for arg in result {
			if arg == '-flp' {
				has_flp = true
			}
		}
		assert has_flp
	} $else $if windows {
		windir := os.getenv('WINDIR')
		result := exec_command(configpkg.ShellCmd{ shell: 'foo bar baz' })!
		assert result == [os.join_path(windir, 'System32', 'cmd.exe'), '/C', 'foo bar baz']
	} $else {
		// On non-macOS, exec_command wraps with /bin/sh
		result := exec_command(configpkg.ShellCmd{ shell: 'foo bar baz' })!
		assert result.len >= 3
		assert result[0] == '/bin/sh'
	}
}

fn test_exec_command_darwin_direct() {
	$if macos {
		// Direct commands on Darwin also use login(1) but pass args directly
		result := exec_command(configpkg.DirectCmd{
			direct: ['foo', 'bar baz']
		})!
		assert result.len >= 1
		assert result[0] == '/usr/bin/login'
		// Should contain the direct args at the end
		assert result[result.len - 2] == 'foo'
		assert result[result.len - 1] == 'bar baz'
	} $else {
		// On non-macOS, direct commands are returned as-is
		result := exec_command(configpkg.DirectCmd{
			direct: ['foo', 'bar baz']
		})!
		assert result.len == 2
		assert result[0] == 'foo'
		assert result[1] == 'bar baz'
	}
}

// ============================================================
// Subprocess tests
// ============================================================

fn test_subprocess_process_union_retains_only_active_arm() {
	assert sizeof(SubprocessProcessKind) == 1
	assert u8(SubprocessProcessKind.fork_exec) == 0
	assert u8(SubprocessProcessKind.flatpak) == 1
	native := SubprocessProcess(SubprocessForkExec{
		command: commandpkg.Command{
			path: '/bin/sh'
		}
	})
	host_command := &internal_os.FlatpakHostCommand{}
	flatpak := SubprocessProcess(SubprocessFlatpak{
		command: host_command
	})
	assert native.kind() == .fork_exec
	assert flatpak.kind() == .flatpak
	assert native is SubprocessForkExec
	assert flatpak is SubprocessFlatpak
}

fn test_args_formatter() {
	assert ArgsFormatter{args: []}.str() == ''
	assert ArgsFormatter{args: ['foo', 'bar baz', '']}.str() == '`foo`, `bar baz`, ``'
}

fn test_subprocess_init_basic() {
	sub := Subprocess.init(ExecConfig{
		term: 'xterm-256color'
	}) or {
		assert false, 'should succeed'
		return
	}

	// Check that env was set up
	if env := sub.env {
		assert env['TERM'] == 'xterm-256color'
		assert env['COLORTERM'] == 'truecolor'
		assert env['TERM_PROGRAM'] == 'ghostty'
		assert env['TERM_PROGRAM_VERSION'] == build_meta.version_string
	}
}

fn test_add_executable_to_path_appends_once() {
	mut env := {
		'PATH': ['/usr/bin', '/bin'].join(os.path_delimiter)
	}
	add_executable_to_path(mut env, '/opt/ghostty/bin/witty', false)
	assert env['GHOSTTY_BIN_DIR'] == '/opt/ghostty/bin'
	assert env['GHOSTTY_BIN_NAME'] == 'witty'
	assert env['PATH'] == ['/usr/bin', '/bin', '/opt/ghostty/bin'].join(os.path_delimiter)

	add_executable_to_path(mut env, '/opt/ghostty/bin/witty', false)
	assert env['PATH'] == ['/usr/bin', '/bin', '/opt/ghostty/bin'].join(os.path_delimiter)
}

fn test_add_executable_to_path_skips_flatpak_sandbox_binary() {
	mut env := {
		'PATH': ['/usr/bin', '/bin'].join(os.path_delimiter)
	}
	add_executable_to_path(mut env, '/app/bin/ghostty', true)
	assert 'GHOSTTY_BIN_DIR' !in env
	assert 'GHOSTTY_BIN_NAME' !in env
	assert env['PATH'] == ['/usr/bin', '/bin'].join(os.path_delimiter)
}

fn test_subprocess_init_with_resources() {
	sub := Subprocess.init(ExecConfig{
		term:          'xterm-ghostty'
		resources_dir: '/tmp/ghostty-resources'
	}) or {
		assert false, 'should succeed'
		return
	}

	if env := sub.env {
		assert env['TERM'] == 'xterm-ghostty'
		assert env['GHOSTTY_RESOURCES_DIR'] == '/tmp/ghostty-resources'
	}
}

fn test_subprocess_init_with_cwd() {
	sub := Subprocess.init(ExecConfig{
		working_directory: '/tmp'
	}) or {
		assert false, 'should succeed'
		return
	}

	assert sub.cwd or { '' } == '/tmp'
	if env := sub.env {
		assert env['PWD'] == '/tmp'
	}
}

fn test_subprocess_init_preserves_linux_cgroup() {
	sub := Subprocess.init(ExecConfig{
		linux_cgroup: '/user.slice/witty.scope'
	})!
	assert (sub.linux_cgroup or { '' }) == '/user.slice/witty.scope'
}

fn test_subprocess_init_with_env_override() {
	sub := Subprocess.init(ExecConfig{
		env_override: configpkg.RepeatableStringMap{
			entries: [
				configpkg.StringMapEntry{
					key:   'MY_VAR'
					value: 'my_value'
				},
			]
		}
	}) or {
		assert false, 'should succeed'
		return
	}

	if env := sub.env {
		assert env['MY_VAR'] == 'my_value'
	}
}

fn test_subprocess_resize() {
	mut sub := Subprocess.init(ExecConfig{}) or { return }

	sub.resize(renderer.GridSize{
		columns: 80
		rows:    24
	}, renderer.ScreenSize{
		width:  800
		height: 480
	}) or { assert false, 'resize should succeed' }

	assert sub.grid_size.columns == 80
	assert sub.grid_size.rows == 24
	assert sub.screen_size.width == 800
	assert sub.screen_size.height == 480
}

fn test_subprocess_start_delegates_to_command() {
	$if windows {
		return
	}
	mut sub := Subprocess{
		args:        ['/bin/sh', '-c', 'exit 23']
		env:         map[string]string{}
		grid_size:   renderer.GridSize{
			columns: 80
			rows:    24
		}
		screen_size: renderer.ScreenSize{
			width:  800
			height: 480
		}
	}
	defer {
		sub.deinit()
	}
	pty_fds := sub.start()!
	assert pty_fds.read >= 0
	assert pty_fds.write == pty_fds.read
	process := sub.process or { panic('expected the translated Command process') }
	assert process.kind() == .fork_exec
	command := match process {
		SubprocessForkExec { process.command }
		SubprocessFlatpak { panic('expected a native process') }
	}

	assert command.path == '/bin/sh'
	assert command.pid or { -1 } > 0
	exit_state := command.wait(true)!
	match exit_state {
		commandpkg.ExitNormal {
			assert exit_state.status == 23
		}
		else {
			assert false, 'expected a normal command exit'
		}
	}

	sub.external_exit()
}

fn test_subprocess_start_failure_releases_pty() {
	$if windows {
		return
	}
	mut sub := Subprocess{
		args:        []
		env:         map[string]string{}
		grid_size:   renderer.GridSize{
			columns: 80
			rows:    24
		}
		screen_size: renderer.ScreenSize{
			width:  800
			height: 480
		}
	}
	sub.start() or {
		assert sub.pty_ == none
		return
	}
	assert false, 'an empty command must fail'
}

fn test_clamp_u16() {
	assert clamp_u16(0) == u16(0)
	assert clamp_u16(100) == u16(100)
	assert clamp_u16(65535) == u16(65535)
	assert clamp_u16(65536) == u16(65535)
	assert clamp_u16(100000) == u16(65535)
}

fn test_read_error_classifies_would_block() {
	mut pipe_fds := [2]int{}
	assert C.pipe(&pipe_fds[0]) == 0
	defer {
		C.close(pipe_fds[0])
		C.close(pipe_fds[1])
	}
	flags := C.fcntl(pipe_fds[0], f_getfl, 0)
	assert flags >= 0
	assert C.fcntl(pipe_fds[0], f_setfl, flags | o_nonblock) >= 0

	mut byte_val := u8(0)
	assert C.witty_read_retry(pipe_fds[0], &byte_val, 1) < 0
	assert C.witty_read_error_kind() == 1
}

fn test_read_error_classifies_closed_pty() {
	mut pipe_fds := [2]int{}
	assert C.pipe(&pipe_fds[0]) == 0
	C.close(pipe_fds[0])
	defer { C.close(pipe_fds[1]) }

	mut byte_val := u8(0)
	assert C.witty_read_retry(pipe_fds[0], &byte_val, 1) < 0
	assert C.witty_read_error_kind() == 2
}

// ============================================================
// ArgIterator tests (from configpkg.Command)
// ============================================================

fn test_arg_iterator_shell_basic() {
	cmd := configpkg.Command(configpkg.ShellCmd{
		shell: 'bash --norc --noprofile'
	})
	mut iter := cmd.arg_iterator()

	assert iter.next() or { '' } == 'bash'
	assert iter.next() or { '' } == '--norc'
	assert iter.next() or { '' } == '--noprofile'
	if _ := iter.next() {
		assert false, 'expected no more args'
	}
}

fn test_arg_iterator_shell_quoted() {
	cmd := configpkg.Command(configpkg.ShellCmd{
		shell: '"/path/to/my bash" --flag'
	})
	mut iter := cmd.arg_iterator()

	assert iter.next() or { '' } == '/path/to/my bash'
	assert iter.next() or { '' } == '--flag'
	if _ := iter.next() {
		assert false, 'expected no more args'
	}
}

fn test_arg_iterator_direct() {
	cmd := configpkg.Command(configpkg.DirectCmd{
		direct: ['foo', 'bar baz', 'qux']
	})
	mut iter := cmd.arg_iterator()

	arg1 := iter.next() or {
		assert false, 'expected foo'
		return
	}
	assert arg1 == 'foo'

	arg2 := iter.next() or {
		assert false, 'expected bar baz'
		return
	}
	assert arg2 == 'bar baz'

	arg3 := iter.next() or {
		assert false, 'expected qux'
		return
	}
	assert arg3 == 'qux'

	// Should be exhausted
	if _ := iter.next() {
		assert false, 'expected none'
	}
}

fn test_subprocess_getpgid_ignores_missing_process() {
	mut child := os.new_process('/usr/bin/true')
	child.run()
	pid := child.pid
	child.wait()
	assert subprocess_getpgid(pid) == none
}
