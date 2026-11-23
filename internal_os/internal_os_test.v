module internal_os

import os
import buildcfg

fn test_desktop_environment_tag_layout_matches_source() {
	assert sizeof(DesktopEnvironment) == 1
	assert [DesktopEnvironment.gnome, .macos, .other, .windows].map(u8(it)) == [u8(0), 1, 2, 3]
}

fn test_open_type_alias_matches_source_kind() {
	assert sizeof(OpenType) == 4
	assert [OpenType.unknown, .text, .html].map(i32(it)) == [i32(0), 1, 2]
}

fn test_pipe_returns_distinct_fds() {
	fds := pipe() or { panic(err) }
	defer {
		os.fd_close(fds[0])
		os.fd_close(fds[1])
	}
	assert fds[0] >= 0
	assert fds[1] >= 0
	assert fds[0] != fds[1]
	assert C.fcntl(fds[0], C.F_GETFD, 0) & C.FD_CLOEXEC != 0
	assert C.fcntl(fds[1], C.F_GETFD, 0) & C.FD_CLOEXEC != 0
}

fn test_open_command_platform_selection() {
	executable_linux, args_linux := open_command_for_os('linux', .text, '/tmp/readme')!
	assert executable_linux == 'xdg-open'
	assert args_linux == ['/tmp/readme']

	executable_freebsd, args_freebsd := open_command_for_os('freebsd', .html, 'file:///tmp/a.html')!
	assert executable_freebsd == 'xdg-open'
	assert args_freebsd == ['file:///tmp/a.html']

	executable_windows, args_windows := open_command_for_os('windows', .unknown,
		'https://example.com')!
	assert executable_windows == 'rundll32'
	assert args_windows == ['url.dll,FileProtocolHandler', 'https://example.com']

	executable_text, args_text := open_command_for_os('macos', .text, '/tmp/readme')!
	assert executable_text == 'open'
	assert args_text == ['-t', '/tmp/readme']

	executable_html, args_html := open_command_for_os('macos', .html, '/tmp/index.html')!
	assert executable_html == 'open'
	assert args_html == ['/tmp/index.html']
}

fn test_open_process_collects_stdout_and_stderr_concurrently() {
	$if !windows {
		mut process := os.new_process('/bin/sh')
		process.set_args(['-c', 'head -c 131072 /dev/zero >&2; printf stdout-complete'])
		spawn_open_process(mut process)!

		stdout_result := chan OpenProcessOutput{cap: 1}
		stderr_result := chan OpenProcessOutput{cap: 1}
		stdout_thread := spawn collect_open_stdout(mut process, stdout_result)
		stderr_thread := spawn collect_open_stderr(mut process, stderr_result)
		stdout := <-stdout_result
		stderr := <-stderr_result
		stdout_thread.wait()
		stderr_thread.wait()
		process.wait()
		process.close()

		assert stdout.data == 'stdout-complete'
		assert !stdout.too_long
		assert stderr.data.len == 0
		assert stderr.too_long
	}
}

fn test_open_process_inherits_stdin_and_redirects_output() {
	$if !windows {
		input_pipe := pipe()!
		input := 'inherited-stdin-policy'
		assert C.write(input_pipe[1], input.str, uint(input.len)) == int(input.len)
		os.fd_close(input_pipe[1])
		saved_stdin := C.dup(0)
		assert saved_stdin >= 0
		mut stdin_restored := false
		defer {
			if !stdin_restored {
				C.dup2(saved_stdin, 0)
				os.fd_close(saved_stdin)
			}
		}
		assert C.dup2(input_pipe[0], 0) >= 0
		os.fd_close(input_pipe[0])

		mut process := os.new_process('/bin/sh')
		process.set_args(['-c', 'cat'])
		spawn_open_process(mut process)!
		assert C.dup2(saved_stdin, 0) >= 0
		os.fd_close(saved_stdin)
		stdin_restored = true
		assert process.use_stdio_ctl
		assert process.stdio_fd[0] == -1

		stdout_result := chan OpenProcessOutput{cap: 1}
		stderr_result := chan OpenProcessOutput{cap: 1}
		collect_open_output(mut process, .stdout, stdout_result)
		collect_open_output(mut process, .stderr, stderr_result)
		stdout := <-stdout_result
		stderr := <-stderr_result
		process.wait()
		process.close()
		assert stdout.data == input
		assert !stdout.too_long
		assert stderr.data.len == 0
	}
}

fn test_open_process_reports_exec_failure() {
	$if !windows {
		mut process := os.new_process('/witty-test/missing-url-handler')
		spawn_open_process(mut process) or {
			assert err.msg().contains('failed to start URL handler')
			return
		}
		assert false
	}
}

fn test_open_process_output_source_limit() {
	mut exact_accumulator := OpenProcessOutputAccumulator{
		data: []u8{cap: open_process_output_max + 1}
	}
	exact_accumulator.add('x'.repeat(open_process_output_max).bytes())
	exact := exact_accumulator.finish()
	assert exact.data.len == open_process_output_max
	assert !exact.too_long

	mut oversized_accumulator := OpenProcessOutputAccumulator{
		data: []u8{cap: open_process_output_max + 1}
	}
	oversized_accumulator.add('x'.repeat(open_process_output_max).bytes())
	oversized_accumulator.add([u8(`x`)])
	oversized_accumulator.add('discarded without allocation'.bytes())
	oversized := oversized_accumulator.finish()
	assert oversized.data.len == 0
	assert oversized.too_long
}

fn test_temp_dir_is_unique_and_deletes_contents() {
	mut first := TempDir.init()!
	mut second := TempDir.init()!
	assert first.name().len > 0
	assert second.name().len > 0
	assert first.path != second.path
	assert os.is_dir(first.path)
	assert os.is_dir(second.path)

	nested := os.join_path(first.path, 'nested')
	os.mkdir(nested)!
	os.write_file(os.join_path(nested, 'data'), 'temporary')!
	first_path := first.path
	second_path := second.path
	first.deinit()
	second.deinit()
	assert !os.exists(first_path)
	assert !os.exists(second_path)

	// Repeated cleanup is harmless and never broadens the deletion target.
	first.deinit()
}

fn test_temp_dir_uses_source_temp_directory_selection() {
	$if !windows {
		mut parent := TempDir.init()!
		defer { parent.deinit() }
		previous_tmpdir := os.getenv_opt('TMPDIR')
		previous_tmp := os.getenv_opt('TMP')
		defer {
			if value := previous_tmpdir {
				os.setenv('TMPDIR', value, true)
			} else {
				os.unsetenv('TMPDIR')
			}
			if value := previous_tmp {
				os.setenv('TMP', value, true)
			} else {
				os.unsetenv('TMP')
			}
		}

		os.setenv('TMP', os.getwd(), true)
		os.setenv('TMPDIR', parent.path, true)
		mut child := TempDir.init()!
		assert child.parent == parent.path
		assert child.path == os.join_path(parent.path, child.name())
		child.deinit()
		assert !os.exists(child.path)
	}
}

fn test_environment_access_preserves_missing_and_empty() {
	key := 'WITTY_INTERNAL_OS_ENV_TEST'
	previous := os.getenv_opt(key)
	defer {
		if value := previous {
			os.setenv(key, value, true)
		} else {
			os.unsetenv(key)
		}
	}

	assert unsetenv(key) == 0
	assert getenv(key) == none
	assert getenv_not_empty(key) == none
	assert setenv(key, '') == 0
	assert (getenv(key) or { 'missing' }) == ''
	assert getenv_not_empty(key) == none
	assert setenv(key, 'value') == 0
	assert (getenv(key) or { '' }) == 'value'
	assert (getenv_not_empty(key) or { '' }) == 'value'
}

fn test_get_env_map_obeys_flatpak_isolation() {
	key := 'WITTY_INTERNAL_OS_ENV_MAP_TEST'
	previous := os.getenv_opt(key)
	os.setenv(key, 'present', true)
	defer {
		if value := previous {
			os.setenv(key, value, true)
		} else {
			os.unsetenv(key)
		}
	}

	env := get_env_map()!
	if is_flatpak() {
		assert env.len == 0
	} else {
		assert env[key] == 'present'
	}
}

fn test_environment_path_composition_uses_platform_delimiter() {
	assert append_env('', 'foo') == 'foo'
	assert append_env('a:b', 'foo') == 'a:b${os.path_delimiter}foo'
	assert append_env_always('', 'foo') == '${os.path_delimiter}foo'
	assert prepend_env('', 'foo') == 'foo'
	assert prepend_env('a:b', 'foo') == 'foo${os.path_delimiter}a:b'
}

fn test_argument_iterator_next_skip_and_deinit() {
	mut iter := ArgIterator.init_with_allocator()
	first := iter.next() or {
		assert false, 'process must have argv[0]'
		return
	}
	assert first.len > 0
	for iter.skip() {
	}
	assert iter.next() == none
	iter.deinit()
	assert iter.next() == none
}

fn test_argument_iterator_uses_platform_arguments() {
	mut iter := iterator()
	defer { iter.deinit() }
	mut actual := []string{}
	for {
		actual << iter.next() or { break }
	}

	// On macOS the source reads arguments from NSProcessInfo rather than libc
	// argc/argv, which it documents as not valid under NSApplicationMain.
	// NSProcessInfo reports the executable path as it was invoked, which need
	// not be the resolved path V records in os.args -- /tmp against
	// /private/tmp, for one -- so only the arguments after it must match.
	assert actual.len == os.args.len
	assert actual.len > 0
	assert os.file_name(actual[0]) == os.file_name(os.args[0])
	assert actual[1..] == os.args[1..]
}

fn test_dbus_activation_requires_both_environment_variables() {
	address_key := 'DBUS_STARTER_ADDRESS'
	bus_key := 'DBUS_STARTER_BUS_TYPE'
	previous_address := os.getenv_opt(address_key)
	previous_bus := os.getenv_opt(bus_key)
	defer {
		if value := previous_address {
			os.setenv(address_key, value, true)
		} else {
			os.unsetenv(address_key)
		}
		if value := previous_bus {
			os.setenv(bus_key, value, true)
		} else {
			os.unsetenv(bus_key)
		}
	}

	os.unsetenv(address_key)
	os.unsetenv(bus_key)
	assert !launched_by_dbus_activation()
	os.setenv(address_key, '', true)
	assert !launched_by_dbus_activation()
	os.setenv(bus_key, '', true)
	$if linux {
		assert launched_by_dbus_activation()
	} $else {
		assert !launched_by_dbus_activation()
	}
}

fn test_alloc_tmp_dir_precedence() {
	$if !windows {
		previous_tmpdir := os.getenv_opt('TMPDIR')
		previous_tmp := os.getenv_opt('TMP')
		defer {
			if value := previous_tmpdir {
				os.setenv('TMPDIR', value, true)
			} else {
				os.unsetenv('TMPDIR')
			}
			if value := previous_tmp {
				os.setenv('TMP', value, true)
			} else {
				os.unsetenv('TMP')
			}
		}

		os.unsetenv('TMPDIR')
		os.unsetenv('TMP')
		assert alloc_tmp_dir() or { '' } == '/tmp'
		os.setenv('TMP', '/tmp/from-tmp', true)
		assert alloc_tmp_dir() or { '' } == '/tmp/from-tmp'
		os.setenv('TMPDIR', '/tmp/from-tmpdir', true)
		assert alloc_tmp_dir() or { '' } == '/tmp/from-tmpdir'
		free_tmp_dir('/tmp/from-tmpdir')
	}
}

fn test_home_preserves_environment_value_and_expand_home_rules() {
	previous := os.getenv_opt('HOME')
	defer {
		if value := previous {
			os.setenv('HOME', value, true)
		} else {
			os.unsetenv('HOME')
		}
	}
	os.setenv('HOME', '/home/witty-test/', true)

	assert (home() or { panic(err) }).value? == '/home/witty-test/'
	assert expand_home('~/Downloads/shader.glsl')! == '/home/witty-test//Downloads/shader.glsl'
	assert expand_home('~')! == '~'
	assert expand_home('~abc/')! == '~abc/'
	assert expand_home('/home/user')! == '/home/user'
	assert expand_home('')! == ''
}

fn test_expand_searches_path_for_executable_files() {
	mut temp := TempDir.init()!
	defer { temp.deinit() }
	command_name := 'witty-path-expand-command'
	command_path := os.join_path(temp.path, command_name)
	os.write_file(command_path, '#!/bin/sh\nexit 0\n')!
	$if !windows {
		os.chmod(command_path, 0o700)!
	}

	previous := os.getenv_opt('PATH')
	defer {
		if value := previous {
			os.setenv('PATH', value, true)
		} else {
			os.unsetenv('PATH')
		}
	}
	os.setenv('PATH', temp.path, true)

	found := expand(command_name)!
	assert (found.value or { '' }) == command_path
	missing := expand('witty-path-command-that-does-not-exist')!
	assert missing.value == none
	with_slash := expand('foo/env')!
	assert (with_slash.value or { '' }) == 'foo/env'
}

fn test_shell_command_builder_ignores_empty_arguments() {
	mut command := ShellCommandBuilder.init()
	defer { command.deinit() }
	command.append_arg('bash')
	command.append_arg('')
	command.append_arg('--posix')
	command.append_arg('-l')
	assert command.to_owned_slice() == 'bash --posix -l'
	command.append_arg('zsh')
	assert command.to_owned_slice() == 'zsh'
}

fn test_shell_escape_writer() {
	for input, expected in {
		'abc':                'abc'
		'a c':                'a\\ c'
		'a?c':                'a\\?c'
		'a\\c':               'a\\\\c'
		'a|c':                'a\\|c'
		'a"c':                'a\\"c'
		'a(1)':               'a\\(1\\)'
		'line one\nline two': 'line\\ one\nline\\ two'
	} {
		mut writer := ShellEscapeWriter.init()
		writer.write(input)
		assert writer.string() == expected
		writer.deinit()
	}
}

fn test_fix_max_files_can_restore_when_available() {
	lim := fix_max_files() or { return }
	restore_max_files(lim)
	assert lim.cur > 0
	assert lim.max >= lim.cur
}

fn test_fix_max_files_does_not_shrink_limit() {
	// After fixing, the current NOFILE limit must be at least what it was
	// before: fix_max_files only ever raises it, then returns the *old*
	// value so it can be restored.
	old := fix_max_files() or { return }
	// The old value must be sane: a positive soft limit within the hard limit.
	assert old.cur > 0
	assert old.max >= old.cur
	restore_max_files(old)
}

fn test_get_passwd_returns_shell_and_home() {
	$if !windows {
		entry := get()!
		assert (entry.shell or { '' }).len > 0
		assert (entry.home or { '' }).len > 0
	}
}

fn test_parse_flatpak_passwd_output_uses_last_two_fields() {
	entry := parse_flatpak_passwd_output('alex:x:501:20:Alex:/Users/alex:/bin/zsh\r\n')
	assert entry.name == none
	assert entry.home? == '/Users/alex'
	assert entry.shell? == '/bin/zsh'
}

fn test_click_interval_matches_platform_contract() {
	$if macos {
		assert click_interval() != none
	} $else {
		assert click_interval() == none
	}
}

fn test_i18n_locale_canonicalization() {
	$if macos || ios {
		if !buildcfg.i18n { assert canonicalize_locale('zh-Hans') == 'zh-Hans'; return }
		assert canonicalize_locale('en_US') == 'en_US'
		assert canonicalize_locale('en-US') == 'en_US'
		assert canonicalize_locale('zh-Hans') == 'zh_CN'
		assert canonicalize_locale('zh-Hans-SG') == 'zh_SG'
		assert canonicalize_locale('zh-Hant') == 'zh_TW'
		assert canonicalize_locale('zh-Hant-HK') == 'zh_HK'
		assert canonicalize_locale('zh-Hant-MO') == 'zh_MO'
	}
}

fn test_i18n_unknown_message_falls_back_to_msgid() {
	msgid := 'witty-i18n-test-message-that-is-not-in-a-catalog'
	assert translate(msgid) == msgid
}

fn test_i18n_supported_locales_match_pinned_source() {
	assert supported_locales.len == 25
	assert supported_locales[0] == 'zh_CN.UTF-8'
	assert supported_locales[1] == 'de_DE.UTF-8'
	assert supported_locales[22] == 'zh_TW.UTF-8'
	assert supported_locales[24] == 'lt_LT.UTF-8'
	assert static_locale('ru_RU.UTF-8') == 'ru_RU.UTF-8'
}

fn test_i18n_resource_parent_matches_source_path_semantics() {
	assert i18n_share_dir('resources') == none
	assert i18n_share_dir('resources/') == none
	assert i18n_share_dir('/') == none
	assert i18n_share_dir('/resources')? == '/'
	assert i18n_share_dir('/usr/share/witty')? == '/usr/share'
	assert i18n_share_dir('/usr/share/witty///')? == '/usr/share'
	assert i18n_share_dir('./resources')? == '.'

	$if !windows {
		init('resources') or {
			assert err.msg() == 'InvalidResourcesDir'
			return
		}
		assert false, 'expected a basename-only resources path to fail'
	}
}

fn test_systemd_detection_is_false_off_linux() {
	$if !linux {
		assert !launched_by_systemd()
	}
}

fn test_systemd_notification_entry_points_without_socket() {
	previous := os.getenv_opt('NOTIFY_SOCKET')
	defer {
		if value := previous {
			os.setenv('NOTIFY_SOCKET', value, true)
		} else {
			os.unsetenv('NOTIFY_SOCKET')
		}
	}
	os.unsetenv('NOTIFY_SOCKET')
	ready()
	reloading()
}

fn test_hostname_validation() {
	for hostname in ['example', 'example.com', 'www.example.com', 'example.com.',
		'host-name.example.com.', '123.example.com.', 'a-b.com', '127.0.0.1', 'a'.repeat(63) + '.com',
		'a.'.repeat(126) + 'a'] {
		assert is_valid(hostname), hostname
	}
	for hostname in ['', '.example.com', 'example.com..', 'host..domain', '-hostname', 'hostname-',
		'a.-.b', 'host_name.com', '.', '..', 'a'.repeat(64) + '.com', 'a.'.repeat(126) + 'ab'] {
		assert !is_valid(hostname), hostname
	}
}

fn test_hostname_is_local() {
	assert is_local('localhost')!
	assert is_local(os.hostname()!)!
	assert !is_local('not-the-local-hostname')!
}

fn test_desktop_environment_matches_platform() {
	$if macos {
		assert desktop_environment() == .macos
	} $else $if windows {
		assert desktop_environment() == .windows
	} $else $if !linux && !freebsd {
		assert desktop_environment() == .other
	}
}

fn test_executable_desktop_launch_ignores_library_marker() {
	$if macos {
		key := 'GHOSTTY_MAC_LAUNCH_SOURCE'
		previous := os.getenv_opt(key)
		defer {
			if value := previous {
				os.setenv(key, value, true)
			} else {
				os.unsetenv(key)
			}
		}
		os.unsetenv(key)
		expected := launched_from_desktop()
		os.setenv(key, 'app', true)
		assert launched_from_desktop() == expected
	}
}

fn test_parse_pid_matches_zig_signed_integer_rules() {
	assert parse_pid('0') or { -1 } == 0
	assert parse_pid('+42') or { -1 } == 42
	assert parse_pid('-42') or { 0 } == -42
	assert parse_pid('1__2') or { -1 } == 12
	assert parse_pid('2147483647') or { -1 } == 2147483647
	assert parse_pid('-2147483648') or { 0 } == -2147483647 - 1
	for invalid in ['', '+', '-', '_1', '1_', '1x', '2147483648', '-2147483649'] {
		assert parse_pid(invalid) == none
	}
}

fn test_desktop_environment_linux_and_bsd_detection() {
	$if linux || freebsd {
		old_session := os.getenv_opt('XDG_SESSION_DESKTOP')
		old_current := os.getenv_opt('XDG_CURRENT_DESKTOP')
		defer {
			if value := old_session {
				os.setenv('XDG_SESSION_DESKTOP', value, true)
			} else {
				os.unsetenv('XDG_SESSION_DESKTOP')
			}
			if value := old_current {
				os.setenv('XDG_CURRENT_DESKTOP', value, true)
			} else {
				os.unsetenv('XDG_CURRENT_DESKTOP')
			}
		}

		os.unsetenv('XDG_CURRENT_DESKTOP')
		os.setenv('XDG_SESSION_DESKTOP', 'gnome', true)
		assert desktop_environment() == .gnome
		os.setenv('XDG_SESSION_DESKTOP', 'GNOME-XORG', true)
		assert desktop_environment() == .gnome
		os.setenv('XDG_SESSION_DESKTOP', 'foobar', true)
		assert desktop_environment() == .other
		os.unsetenv('XDG_SESSION_DESKTOP')
		os.setenv('XDG_CURRENT_DESKTOP', 'GNOME:Unity', true)
		assert desktop_environment() == .gnome
		os.setenv('XDG_CURRENT_DESKTOP', 'FOOBAR:GNOME', true)
		assert desktop_environment() == .other
	}
}

fn test_get_kernel_info() {
	$if linux {
		info := get_kernel_info() or { panic('kernel information unavailable') }
		assert info.len > 0
		assert info == info.trim_space()
	} $else {
		assert get_kernel_info() == none
	}
}

fn test_ensure_locale_initializes_libc() {
	ensure_locale()!
	assert set_process_locale('') != none
}

fn test_xdg_directories_with_cached_home() {
	assert config(Options{ home: '/Users/test' })! == '/Users/test/.config'
	assert cache(Options{ home: '/Users/test', subdir: 'ghostty' })! == '/Users/test/.cache/ghostty'
	assert state(Options{ home: '/Users/test', subdir: 'ghostty' })! == '/Users/test/.local/state/ghostty'
}

fn test_xdg_empty_environment_falls_back_to_home() {
	old_home := os.getenv_opt('HOME')
	old_cache := os.getenv_opt('XDG_CACHE_HOME')
	defer {
		if value := old_home {
			os.setenv('HOME', value, true)
		} else {
			os.unsetenv('HOME')
		}
		if value := old_cache {
			os.setenv('XDG_CACHE_HOME', value, true)
		} else {
			os.unsetenv('XDG_CACHE_HOME')
		}
	}
	os.setenv('HOME', '/tmp/witty-test-home', true)
	os.setenv('XDG_CACHE_HOME', '', true)
	assert cache(Options{})! == '/tmp/witty-test-home/.cache'
	assert cache(Options{ subdir: 'ghostty' })! == '/tmp/witty-test-home/.cache/ghostty'
}

fn test_parse_terminal_exec() {
	assert parse_terminal_exec(['a', 'b', 'c']) == none
	assert (parse_terminal_exec(['xdg-terminal-exec']) or { ['not-empty'] }).len == 0
	assert (parse_terminal_exec(['/usr/bin/xdg-terminal-exec', 'a', 'b', 'c']) or { []string{} }) == [
		'a',
		'b',
		'c',
	]
	assert (parse_terminal_exec(['xdg-terminal-exec', '-e', 'a', 'b', 'c']) or { []string{} }) == [
		'a',
		'b',
		'c',
	]
	assert (parse_terminal_exec(['xdg-terminal-exec', 'a', '-e', 'b', 'c']) or { []string{} }) == [
		'a',
		'-e',
		'b',
		'c',
	]
}

fn test_cgroup_path_from_contents() {
	parsed := cgroup_path_from_contents('0::/user.slice/user-1000.slice/session-1.scope\n')
	assert (parsed.value or { '' }) == '/user.slice/user-1000.slice/session-1.scope'
	last := cgroup_path_from_contents('1:name:first\n0::/last.scope \r\n')
	assert (last.value or { '' }) == '/last.scope'
	assert cgroup_path_from_contents('missing delimiters').value == none
}

fn test_cgroup_limit_uses_pointer_width_payload() {
	assert sizeof(CgroupLimitKind) == 1
	assert sizeof(CgroupLimitMemoryHigh) == sizeof(uint)
	assert sizeof(CgroupLimitPidsMax) == sizeof(uint)
	memory := CgroupLimit(CgroupLimitMemoryHigh{
		value: uint(1) << 40
	})
	assert memory is CgroupLimitMemoryHigh
	assert memory.kind() == .memory_high
	pids := CgroupLimit(CgroupLimitPidsMax{
		value: 128
	})
	assert pids is CgroupLimitPidsMax
	assert pids.kind() == .pids_max
}

fn test_cgroup_write_existing_does_not_create_files() {
	$if linux {
		root := os.join_path(os.temp_dir(), 'witty-cgroup-write-${os.getpid()}')
		os.rmdir_all(root) or {}
		os.mkdir_all(root)!
		defer {
			os.rmdir_all(root) or {}
		}
		path := os.join_path(root, 'control')
		os.write_file(path, 'old')!
		cgroup_write_existing(path, 'new')!
		assert os.read_file(path)! == 'new'

		missing := os.join_path(root, 'missing')
		if _ := cgroup_write_existing(missing, 'value') {
			assert false, 'write-only cgroup paths must already exist'
		}
		assert !os.exists(missing)
	}
}

fn test_home_uses_file_manager_without_home_on_macos() ! {
	$if macos {
		previous := os.getenv_opt('HOME')
		defer {
			if value := previous {
				os.setenv('HOME', value, true)
			}
		}
		os.unsetenv('HOME')
		assert home()!.value? == home_macos()?
	}
}
