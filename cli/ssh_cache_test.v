module cli

import os
import time

fn test_ssh_cache_add_result_layout_matches_source() {
	assert sizeof(SshCacheAddResult) == 1
	assert int(SshCacheAddResult.added) == 0
	assert int(SshCacheAddResult.updated) == 1
}

fn test_ssh_cache_default_path_is_fallible_and_side_effect_free() {
	key := 'XDG_STATE_HOME'
	previous := os.getenv_opt(key)
	defer {
		if value := previous {
			os.setenv(key, value, true)
		} else {
			os.unsetenv(key)
		}
	}

	base := os.join_path(os.temp_dir(), 'witty-ssh-state-${os.getpid()}')
	os.rmdir_all(base) or {}
	os.setenv(key, base, true)
	assert SshDiskCache.default_path('ghostty')! == os.join_path(base, 'ghostty', 'ssh_cache')
	assert run_inner(SshCacheOptions{})!.output == 'No hosts in cache.\n'
	assert !os.exists(base)
}

fn test_ssh_cache_deinit_entries_releases_returned_container() {
	mut entries := {
		'example.com': SshCacheEntry{
			hostname: 'example.com'
		}
	}
	SshDiskCache.deinit_entries(mut entries)
	assert entries.len == 0
}

fn test_ssh_cache_entry_parsing_format_and_expiration() {
	entry := SshCacheEntry.parse('example.com|1640995200|xterm-witty')?
	assert entry.hostname == 'example.com'
	assert entry.timestamp == 1640995200
	assert entry.terminfo_version == 'xterm-witty'
	assert entry.format() == 'example.com|1640995200|xterm-witty\n'
	assert SshCacheEntry.parse('test.com|1640995200')?.terminfo_version == 'xterm-witty'
	assert SshCacheEntry.parse('example.com|invalid') == none
	assert SshCacheEntry.parse('') == none
	assert SshCacheEntry.parse('host|+42|term')?.timestamp == 42
	assert SshCacheEntry.parse('host|1__2|term')?.timestamp == 12
	assert SshCacheEntry.parse('host|9223372036854775807|term')?.timestamp == max_i64
	assert SshCacheEntry.parse('host|-9223372036854775808|term')?.timestamp == min_i64
	for invalid in ['9223372036854775808', '-9223372036854775809', '1x', '_1', '1_'] {
		assert SshCacheEntry.parse('host|${invalid}|term') == none
	}

	now := time.now().unix()
	assert !SshCacheEntry{
		hostname: 'future.example'
		timestamp: now + 86400
	}.is_expired(1)
	assert SshCacheEntry{
		hostname: 'old.example'
		timestamp: now - 86400 * 31
	}.is_expired(30)
}

fn test_ssh_cache_key_validation() {
	for key in ['example.com', 'user@example.com', '127.0.0.1', '::1', 'user-name@2001:db8::1'] {
		assert valid_ssh_cache_key(key), key
	}
	for key in ['', '@example.com', 'bad user@example.com', '-example.com', 'a@'] {
		assert !valid_ssh_cache_key(key), key
	}
}

fn test_ssh_disk_cache_operations_and_duplicate_resolution() {
	dir := os.join_path(os.temp_dir(), 'witty-ssh-cache-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'ssh_cache')
	cache := SshDiskCache{ path: path }
	assert cache.add('example.com')! == .added
	assert cache.add('example.com')! == .updated
	assert cache.contains('example.com')!
	$if !windows {
		assert os.stat(path)!.mode & 0o777 == 0o600
	}
	entries := cache.list()!
	assert entries.len == 1
	cache.remove('example.com')!
	assert !cache.contains('example.com')!
	cache.clear()!

	os.mkdir_all(dir)!
	os.write_file(path, 'host|10|old\nhost|20|new\nbroken\n')!
	resolved := cache.list()!
	assert resolved['host'].timestamp == 20
	assert resolved['host'].terminfo_version == 'new'
}

fn test_ssh_cache_action_output_and_sorting() {
	dir := os.join_path(os.temp_dir(), 'witty-ssh-cache-action-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	cache := SshDiskCache{ path: os.join_path(dir, 'ssh_cache') }
	added := run_inner_with_cache(cache, SshCacheOptions{ add: 'z.example' })!
	assert added.output == "Added 'z.example' to cache.\n"
	_ = run_inner_with_cache(cache, SshCacheOptions{ add: 'a.example' })!
	listed := run_inner_with_cache(cache, SshCacheOptions{})!
	assert listed.output.index('a.example')? < listed.output.index('z.example')?
	found := run_inner_with_cache(cache, SshCacheOptions{ host: 'a.example' })!
	assert found.code == 0
	missing := run_inner_with_cache(cache, SshCacheOptions{ host: 'missing.example' })!
	assert missing.code == 1
	invalid := run_inner_with_cache(cache, SshCacheOptions{ add: '-bad' })!
	assert invalid.code == 1
	assert invalid.errors.contains('Invalid hostname format')
}

fn test_parse_ssh_cache_options() {
	opts := parse_ssh_cache_options(['--clear=false', '--add=host', '--expire-days=30'])!
	assert !opts.clear
	assert opts.add? == 'host'
	assert opts.expire_days? == 30

	prefixed := parse_ssh_cache_options(['--expire-days=+0x1__e'])!
	assert prefixed.expire_days? == 30
	negative_zero := parse_ssh_cache_options(['--expire-days=-0'])!
	assert negative_zero.expire_days? == 0
	if _ := parse_ssh_cache_options(['--expire-days=0x_1e']) {
		assert false, 'expected an edge underscore to fail'
	}
}

fn test_ssh_atomic_file_uses_exclusive_private_names_and_cleans_unfinished_writes() ! {
	dir := os.join_path(os.temp_dir(), 'witty-ssh-atomic-${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	path := os.join_path(dir, 'ssh_cache')
	mut first := SshAtomicFile.init(path)!
	mut second := SshAtomicFile.init(path)!
	assert first.name.len == 16
	assert first.name != second.name
	$if !windows {
		assert os.stat(os.join_path(dir, first.name))!.mode & 0o777 == 0o600
	}
	first.write('first|1|xterm-witty\n')!
	first.finish()!
	first.deinit()
	second.deinit()
	assert os.ls(dir)! == ['ssh_cache']
	assert os.read_file(path)! == 'first|1|xterm-witty\n'
}

fn test_ssh_cache_read_rejects_reaching_source_bound() ! {
	dir := os.join_path(os.temp_dir(), 'witty-ssh-bound-${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	path := os.join_path(dir, 'ssh_cache')
	cache := SshDiskCache{path: path}
	os.write_file(path, 'x'.repeat(max_ssh_cache_size - 1))!
	assert cache.list()!.len == 0
	for size in [max_ssh_cache_size, max_ssh_cache_size + 1] {
		os.write_file(path, 'x'.repeat(size))!
		cache.list() or {
			assert err.msg() == 'StreamTooLong'
			continue
		}
		assert false, 'reaching the source read limit must fail'
	}
}
