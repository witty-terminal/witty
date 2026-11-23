module internal_os

import os

fn test_resources_dir_detects_env() {
	old := os.getenv_opt('GHOSTTY_RESOURCES_DIR')
	os.setenv('GHOSTTY_RESOURCES_DIR', '/tmp/witty-resources-env', true)
	defer {
		if value := old {
			os.setenv('GHOSTTY_RESOURCES_DIR', value, true)
		} else {
			os.unsetenv('GHOSTTY_RESOURCES_DIR')
		}
	}

	result := resources_dir()
	assert result.app()? == '/tmp/witty-resources-env'
	assert result.host()? == '/tmp/witty-resources-env'
}

fn test_resources_dir_detects_share_layout() {
	tmp := os.join_path(os.temp_dir(), 'witty-resources-test-${os.getpid()}')
	defer {
		os.rmdir_all(tmp) or {}
	}
	sentinel := $if macos { 'terminfo/78/xterm-witty' } $else $if freebsd { 'site-terminfo/w/witty' } $else $if windows { 'terminfo/witty.terminfo' } $else { 'terminfo/w/witty' }
	sentinel_path := os.join_path(tmp, 'share', sentinel)
	os.mkdir_all(os.dir(sentinel_path)) or { panic(err) }
	os.write_file(sentinel_path, '') or { panic(err) }

	result := resources_dir_from_exe(os.join_path(tmp, 'bin', 'witty'))
	assert result.app()? == os.join_path(tmp, 'share', 'witty')
}

fn test_resources_maybe_dir_returns_verified_parent() {
	tmp := os.join_path(os.temp_dir(), 'witty-resources-maybe-${os.getpid()}')
	defer {
		os.rmdir_all(tmp) or {}
	}
	sentinel := os.join_path(tmp, 'share', 'terminfo', 'w', 'witty')
	os.mkdir_all(os.dir(sentinel))!
	os.write_file(sentinel, '')!
	assert (maybe_dir(tmp, 'share', 'terminfo/w/witty') or { '' }) == os.join_path(tmp, 'share')
	assert maybe_dir(tmp, 'share', 'terminfo/x/missing') == none
}

fn test_resources_dir_returns_empty_when_not_found() {
	tmp := os.join_path(os.temp_dir(), 'witty-resources-empty-${os.getpid()}')
	defer {
		os.rmdir_all(tmp) or {}
	}
	os.mkdir_all(os.join_path(tmp, 'bin')) or { panic(err) }

	result := resources_dir_from_exe(os.join_path(tmp, 'bin', 'witty'))
	assert result.app() == none
	assert result.host() == none
}

fn test_resources_dir_host_falls_back_to_app() {
	mut result := ResourcesDir{
		app_path: '/some/app/path'
	}
	assert result.host()? == '/some/app/path'

	result_with_host := ResourcesDir{
		app_path: '/some/app/path'
		host_path: '/some/host/path'
	}
	assert result_with_host.host()? == '/some/host/path'
	assert result_with_host.app()? == '/some/app/path'

	result.deinit()
	assert result.app() == none
	assert result.host() == none

	empty := ResourcesDir{}
	assert empty.app() == none
	assert empty.host() == none
}
