module termio

import configpkg
import os

fn test_shell_source_layout_and_ordinals() {
	assert sizeof(Shell) == 1
	assert u8(Shell.bash) == 0
	assert u8(Shell.elvish) == 1
	assert u8(Shell.fish) == 2
	assert u8(Shell.nushell) == 3
	assert u8(Shell.zsh) == 4
}

// TmpResourcesDir is a test helper that creates a temporary resources directory
// with shell integration paths.
struct TmpResourcesDir {
	tmp_path   string
	path       string
	shell_path string
}

fn TmpResourcesDir.init(shell Shell) !TmpResourcesDir {
	tmp_path := os.join_path(os.temp_dir(), 'Witty_test_${os.getpid()}_${shell}')
	os.rmdir_all(tmp_path) or {}

	shell_name := match shell {
		.bash { 'bash' }
		.elvish { 'elvish' }
		.fish { 'fish' }
		.nushell { 'nushell' }
		.zsh { 'zsh' }
	}

	relative_shell_path := 'shell-integration/${shell_name}'
	os.mkdir_all(os.join_path(tmp_path, relative_shell_path))!

	shell_path := os.join_path(tmp_path, relative_shell_path)

	if shell == .bash {
		bash_script := os.join_path(tmp_path, 'shell-integration/bash/witty.bash')
		os.write_file(bash_script, '')!
	}

	return TmpResourcesDir{
		tmp_path: tmp_path
		path: tmp_path
		shell_path: shell_path
	}
}

fn (t TmpResourcesDir) deinit() {
	os.rmdir_all(t.tmp_path) or {}
}

// ============================================================
// detect_shell tests
// ============================================================

fn test_detect_shell_unknown() {
	assert detect_shell(configpkg.ShellCmd{ shell: 'sh' }) == none
}

fn test_detect_shell_bash() {
	result := detect_shell(configpkg.ShellCmd{ shell: 'bash' }) or {
		assert false, 'expected bash'
		return
	}
	assert result == .bash
}

fn test_detect_shell_elvish() {
	result := detect_shell(configpkg.ShellCmd{ shell: 'elvish' }) or {
		assert false, 'expected elvish'
		return
	}
	assert result == .elvish
}

fn test_detect_shell_fish() {
	result := detect_shell(configpkg.ShellCmd{ shell: 'fish' }) or {
		assert false, 'expected fish'
		return
	}
	assert result == .fish
}

fn test_detect_shell_nushell() {
	result := detect_shell(configpkg.ShellCmd{ shell: 'nu' }) or {
		assert false, 'expected nushell'
		return
	}
	assert result == .nushell
}

fn test_detect_shell_zsh() {
	result := detect_shell(configpkg.ShellCmd{ shell: 'zsh' }) or {
		assert false, 'expected zsh'
		return
	}
	assert result == .zsh
}

fn test_detect_shell_bash_with_args() {
	result := detect_shell(configpkg.ShellCmd{ shell: "bash -c 'command'" }) or {
		assert false, 'expected bash'
		return
	}
	assert result == .bash
}

fn test_detect_shell_bash_quoted_path() {
	result := detect_shell(configpkg.ShellCmd{ shell: '"/a b/bash"' }) or {
		assert false, 'expected bash'
		return
	}
	assert result == .bash
}

fn test_detect_shell_bin_bash_on_darwin() {
	// Apple's /bin/bash is patched and doesn't support our integration.
	// On non-macOS platforms, /bin/bash would be detected as bash.
	$if macos {
		assert detect_shell(configpkg.ShellCmd{ shell: '/bin/bash' }) == none
	} $else {

		// On non-macOS, /bin/bash is just bash
		result := detect_shell(configpkg.ShellCmd{ shell: '/bin/bash' }) or { return }
		assert result == .bash
	}
}

// ============================================================
// setup_features tests
// ============================================================

fn test_setup_features_all_enabled() {
	mut env := map[string]string{}
	setup_features(mut env, configpkg.ShellIntegrationFeatures.init(true, true, true, true,
		true, true))
	assert env['GHOSTTY_SHELL_FEATURES'] == 'cursor,path,ssh-env,ssh-terminfo,sudo,title'
}

fn test_setup_features_all_disabled() {
	mut env := map[string]string{}
	setup_features(mut env, configpkg.ShellIntegrationFeatures.init(false, false, false,
		false, false, false))
	assert 'GHOSTTY_SHELL_FEATURES' !in env
}

fn test_setup_features_mixed() {
	mut env := map[string]string{}
	setup_features(mut env, configpkg.ShellIntegrationFeatures.init(false, true, false, true,
		false, false))
	assert env['GHOSTTY_SHELL_FEATURES'] == 'ssh-env,sudo'
}

// ============================================================
// setup_bash tests
// ============================================================

fn test_bash_basic() {
	mut res := TmpResourcesDir.init(.bash) or {
		assert false, 'failed to create tmp dir'
		return
	}
	defer {
		res.deinit()
	}

	mut env := map[string]string{}

	cmd := (setup_bash(configpkg.ShellCmd{ shell: 'bash' }, res.path, mut env) or { panic(err) }).value or {
		assert false, 'setup_bash should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'bash --posix'
	} else {
		assert false, 'expected ShellCmd'
	}
	assert env['GHOSTTY_BASH_INJECT'] == '1'
	assert env['ENV'] == '${res.shell_path}/witty.bash'
}

fn test_bash_unsupported_posix() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	assert (setup_bash(configpkg.ShellCmd{ shell: 'bash --posix' }, res.path, mut env) or { panic(err) }).value == none
	assert env.len == 0
}

fn test_bash_unsupported_c_flag() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	assert (setup_bash(configpkg.ShellCmd{ shell: 'bash -c script.sh' }, res.path, mut env) or { panic(err) }).value == none
	assert env.len == 0
}

fn test_bash_unsupported_ic_flag() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	assert (setup_bash(configpkg.ShellCmd{ shell: 'bash -ic script.sh' }, res.path, mut env) or { panic(err) }).value == none
	assert env.len == 0
}

fn test_bash_inject_norc() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	cmd := (setup_bash(configpkg.ShellCmd{ shell: 'bash --norc' }, res.path, mut env) or { panic(err) }).value or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'bash --posix'
	}
	assert env['GHOSTTY_BASH_INJECT'] == '1 --norc'
}

fn test_bash_inject_noprofile() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	cmd := (setup_bash(configpkg.ShellCmd{ shell: 'bash --noprofile' }, res.path, mut env) or { panic(err) }).value or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'bash --posix'
	}
	assert env['GHOSTTY_BASH_INJECT'] == '1 --noprofile'
}

fn test_bash_rcfile() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}

	// bash --rcfile
	cmd := (setup_bash(configpkg.ShellCmd{ shell: 'bash --rcfile profile.sh' }, res.path, mut env) or { panic(err) }).value or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'bash --posix'
	}
	assert env['GHOSTTY_BASH_RCFILE'] == 'profile.sh'
}

fn test_bash_init_file() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}

	// bash --init-file
	cmd := (setup_bash(configpkg.ShellCmd{ shell: 'bash --init-file profile.sh' }, res.path, mut env) or { panic(err) }).value or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'bash --posix'
	}
	assert env['GHOSTTY_BASH_RCFILE'] == 'profile.sh'
}

fn test_bash_histfile_unset() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	_ := (setup_bash(configpkg.ShellCmd{ shell: 'bash' }, res.path, mut env) or { panic(err) }).value or { return }
	histfile := env['HISTFILE'] or { '' }
	assert histfile.ends_with('.bash_history')
	assert env['GHOSTTY_BASH_UNEXPORT_HISTFILE'] == '1'
}

fn test_bash_histfile_set() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	env['HISTFILE'] = 'my_history'

	_ := (setup_bash(configpkg.ShellCmd{ shell: 'bash' }, res.path, mut env) or { panic(err) }).value or { return }
	assert env['HISTFILE'] == 'my_history'
	assert 'GHOSTTY_BASH_UNEXPORT_HISTFILE' !in env
}

fn test_bash_env_preserved() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	env['ENV'] = 'env.sh'

	_ := (setup_bash(configpkg.ShellCmd{ shell: 'bash' }, res.path, mut env) or { panic(err) }).value or { return }
	assert env['GHOSTTY_BASH_ENV'] == 'env.sh'
	assert env['ENV'] == '${res.shell_path}/witty.bash'
}

fn test_bash_empty_env_preserved() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	env['ENV'] = ''

	_ := (setup_bash(configpkg.ShellCmd{ shell: 'bash' }, res.path, mut env) or { panic(err) }).value or { return }
	assert 'GHOSTTY_BASH_ENV' in env
	assert env['GHOSTTY_BASH_ENV'] == ''
	assert env['ENV'] == '${res.shell_path}/witty.bash'
}

fn test_bash_additional_args_dash() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}

	// "-" argument separator
	cmd := (setup_bash(configpkg.ShellCmd{ shell: 'bash - --arg file1 file2' }, res.path, mut env) or { panic(err) }).value or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'bash --posix - --arg file1 file2'
	}
}

fn test_bash_additional_args_double_dash() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}

	// "--" argument separator
	cmd := (setup_bash(configpkg.ShellCmd{ shell: 'bash -- --arg file1 file2' }, res.path, mut env) or { panic(err) }).value or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'bash --posix -- --arg file1 file2'
	}
}

fn test_bash_missing_resources() {
	tmp_path := os.join_path(os.temp_dir(), 'Witty_test_missing_${os.getpid()}')
	os.mkdir_all(tmp_path) or { return }
	defer {
		os.rmdir_all(tmp_path) or {}
	}

	mut env := map[string]string{}
	assert (setup_bash(configpkg.ShellCmd{ shell: 'bash' }, tmp_path, mut env) or { panic(err) }).value == none
	assert env.len == 0
}

// ============================================================
// setup_xdg_data_dirs tests
// ============================================================

fn test_xdg_empty() {
	mut res := TmpResourcesDir.init(.fish) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	assert setup_xdg_data_dirs(res.path, mut env) == true

	assert env['GHOSTTY_SHELL_INTEGRATION_XDG_DIR'] == '${res.path}/shell-integration'
	assert env['XDG_DATA_DIRS'] == '${res.path}/shell-integration:/usr/local/share:/usr/share'
}

fn test_xdg_existing() {
	mut res := TmpResourcesDir.init(.fish) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	env['XDG_DATA_DIRS'] = '/opt/share'
	assert setup_xdg_data_dirs(res.path, mut env) == true

	assert env['GHOSTTY_SHELL_INTEGRATION_XDG_DIR'] == '${res.path}/shell-integration'
	assert env['XDG_DATA_DIRS'] == '${res.path}/shell-integration:/opt/share'
}

fn test_xdg_missing_resources() {
	tmp_path := os.join_path(os.temp_dir(), 'Witty_test_xdg_missing_${os.getpid()}')
	os.mkdir_all(tmp_path) or { return }
	defer {
		os.rmdir_all(tmp_path) or {}
	}

	mut env := map[string]string{}
	assert setup_xdg_data_dirs(tmp_path, mut env) == false
	assert env.len == 0
}

// ============================================================
// setup_nushell tests
// ============================================================

fn test_nushell_basic() {
	mut res := TmpResourcesDir.init(.nushell) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	cmd := setup_nushell(configpkg.ShellCmd{ shell: 'nu' }, res.path, mut env) or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == "nu --execute 'use witty *'"
	}
	assert 'GHOSTTY_SHELL_INTEGRATION_XDG_DIR' in env
	xdg := env['XDG_DATA_DIRS'] or { '' }
	assert xdg.starts_with('${res.path}/shell-integration')
}

fn test_nushell_unsupported_command() {
	mut res := TmpResourcesDir.init(.nushell) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	assert setup_nushell(configpkg.ShellCmd{ shell: 'nu --command exit' }, res.path, mut env) == none
	assert 'XDG_DATA_DIRS' in env
	assert 'GHOSTTY_SHELL_INTEGRATION_XDG_DIR' in env
}

fn test_nushell_unsupported_lsp() {
	mut res := TmpResourcesDir.init(.nushell) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	assert setup_nushell(configpkg.ShellCmd{ shell: 'nu --lsp' }, res.path, mut env) == none
	assert 'XDG_DATA_DIRS' in env
}

fn test_nushell_unsupported_c_flag() {
	mut res := TmpResourcesDir.init(.nushell) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	assert setup_nushell(configpkg.ShellCmd{ shell: 'nu -c script.sh' }, res.path, mut env) == none
}

fn test_nushell_missing_resources() {
	tmp_path := os.join_path(os.temp_dir(), 'Witty_test_nu_missing_${os.getpid()}')
	os.mkdir_all(tmp_path) or { return }
	defer {
		os.rmdir_all(tmp_path) or {}
	}

	mut env := map[string]string{}
	assert setup_nushell(configpkg.ShellCmd{ shell: 'nu' }, tmp_path, mut env) == none
	assert env.len == 0
}

// ============================================================
// setup_zsh tests
// ============================================================

fn test_zsh_basic() {
	mut res := TmpResourcesDir.init(.zsh) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	cmd := setup_zsh(configpkg.ShellCmd{ shell: 'zsh' }, res.path, mut env) or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'zsh'
	}
	assert env['ZDOTDIR'] == res.shell_path
	assert 'GHOSTTY_ZSH_ZDOTDIR' !in env
}

fn test_zsh_zdotdir_preserved() {
	mut res := TmpResourcesDir.init(.zsh) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	env['ZDOTDIR'] = '\$HOME/.config/zsh'

	cmd := setup_zsh(configpkg.ShellCmd{ shell: 'zsh' }, res.path, mut env) or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'zsh'
	}
	assert env['ZDOTDIR'] == res.shell_path
	assert env['GHOSTTY_ZSH_ZDOTDIR'] == '\$HOME/.config/zsh'
}

fn test_zsh_empty_zdotdir_preserved() {
	mut res := TmpResourcesDir.init(.zsh) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	env['ZDOTDIR'] = ''

	cmd := setup_zsh(configpkg.ShellCmd{ shell: 'zsh' }, res.path, mut env) or {
		assert false, 'should succeed'
		return
	}
	if cmd is configpkg.ShellCmd {
		assert cmd.shell == 'zsh'
	}
	assert env['ZDOTDIR'] == res.shell_path
	assert 'GHOSTTY_ZSH_ZDOTDIR' in env
	assert env['GHOSTTY_ZSH_ZDOTDIR'] == ''
}

fn test_zsh_missing_resources() {
	tmp_path := os.join_path(os.temp_dir(), 'Witty_test_zsh_missing_${os.getpid()}')
	os.mkdir_all(tmp_path) or { return }
	defer {
		os.rmdir_all(tmp_path) or {}
	}

	mut env := map[string]string{}
	assert setup_zsh(configpkg.ShellCmd{ shell: 'zsh' }, tmp_path, mut env) == none
	assert env.len == 0
}

// ============================================================
// setup (top-level) tests
// ============================================================

fn test_force_shell_bash() {
	mut res := TmpResourcesDir.init(.bash) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	result := setup(res.path, configpkg.ShellCmd{ shell: 'sh' }, mut env, Shell.bash) or { panic(err) }.value
	if r := result {
		assert r.shell == .bash
	} else {
		assert false, 'should have succeeded for bash'
	}
}

fn test_force_shell_zsh() {
	mut res := TmpResourcesDir.init(.zsh) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	result := setup(res.path, configpkg.ShellCmd{ shell: 'sh' }, mut env, Shell.zsh) or { panic(err) }.value
	if r := result {
		assert r.shell == .zsh
	} else {
		assert false, 'should have succeeded for zsh'
	}
}

fn test_force_shell_fish() {
	mut res := TmpResourcesDir.init(.fish) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	result := setup(res.path, configpkg.ShellCmd{ shell: 'sh' }, mut env, Shell.fish) or { panic(err) }.value
	if r := result {
		assert r.shell == .fish
	} else {
		assert false, 'should have succeeded for fish'
	}
}

fn test_force_shell_elvish() {
	mut res := TmpResourcesDir.init(.elvish) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	result := setup(res.path, configpkg.ShellCmd{ shell: 'sh' }, mut env, Shell.elvish) or { panic(err) }.value
	if r := result {
		assert r.shell == .elvish
	} else {
		assert false, 'should have succeeded for elvish'
	}
}

fn test_force_shell_nushell() {
	mut res := TmpResourcesDir.init(.nushell) or { return }
	defer {
		res.deinit()
	}

	mut env := map[string]string{}
	result := setup(res.path, configpkg.ShellCmd{ shell: 'sh' }, mut env, Shell.nushell) or { panic(err) }.value
	if r := result {
		assert r.shell == .nushell
	} else {
		assert false, 'should have succeeded for nushell'
	}
}

fn test_shell_integration_failure() {
	mut env := map[string]string{}
	result := setup('/nonexistent', configpkg.ShellCmd{ shell: 'sh' }, mut env, none) or { panic(err) }.value
	assert result == none
	assert env.len == 0
}
