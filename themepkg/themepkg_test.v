module themepkg

import os
import diagnostics

fn test_theme_location_source_layout_and_ordinals() {
	assert sizeof(Location) == 1
	assert [Location.user, .resources].map(u8(it)) == [u8(0), 1]
}

fn test_location_user_uses_translated_xdg_resolution() {
	previous_xdg := os.getenv_opt('XDG_CONFIG_HOME')
	previous_home := os.getenv_opt('HOME')
	defer {
		if value := previous_xdg {
			os.setenv('XDG_CONFIG_HOME', value, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
		if value := previous_home {
			os.setenv('HOME', value, true)
		} else {
			os.unsetenv('HOME')
		}
	}

	os.setenv('XDG_CONFIG_HOME', '/tmp/witty-theme-xdg', true)
	assert Location.user.dir() or { '' } == os.join_path('/tmp/witty-theme-xdg', 'witty', 'themes')

	os.unsetenv('XDG_CONFIG_HOME')
	os.setenv('HOME', '/tmp/witty-theme-home/', true)
	assert Location.user.dir() or { '' } == os.join_path('/tmp/witty-theme-home/', '.config', 'witty', 'themes')
}

fn test_location_iterator_order_and_reset() {
	previous_xdg := os.getenv_opt('XDG_CONFIG_HOME')
	defer {
		if value := previous_xdg {
			os.setenv('XDG_CONFIG_HOME', value, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
	}
	os.setenv('XDG_CONFIG_HOME', '/tmp/witty-theme-iterator', true)

	mut it := LocationIterator.new()
	assert sizeof(LocationIterator) == sizeof(uint)
	first := it.next() or { panic('missing user theme location') }
	assert first.location == .user
	assert first.dir == os.join_path('/tmp/witty-theme-iterator', 'witty', 'themes')
	it.reset()
	assert (it.next() or { panic('missing reset user theme location') }).location == .user
}

fn test_open_absolute_theme_and_diagnostics() ! {
	dir := os.join_path(os.temp_dir(), 'witty-theme-open-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'theme')
	os.write_file(path, 'background = #123456\n')!
	mut diags := diagnostics.DiagnosticList{}
	opened := open(path, mut diags) or { panic('expected absolute theme to open') }
	assert opened.path == path
	assert diags.empty()
	mut file := opened.file
	file.close()

	mut missing_diags := diagnostics.DiagnosticList{}
	assert open(os.join_path(dir, 'missing'), mut missing_diags) == none
	assert missing_diags.items()[0].message == 'failed to load theme from the path "${os.join_path(dir, 'missing')}"'

	mut directory_diags := diagnostics.DiagnosticList{}
	assert open(dir, mut directory_diags) == none
	assert directory_diags.items()[0].message == 'not reading theme from "${dir}": it is a directory'
}

fn test_open_named_theme_uses_location_order_and_reports_attempts() ! {
	dir := os.join_path(os.temp_dir(), 'witty-theme-named-${os.getpid()}')
	theme_dir := os.join_path(dir, 'witty', 'themes')
	os.rmdir_all(dir) or {}
	os.mkdir_all(theme_dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	previous_xdg := os.getenv_opt('XDG_CONFIG_HOME')
	os.setenv('XDG_CONFIG_HOME', dir, true)
	defer {
		if value := previous_xdg {
			os.setenv('XDG_CONFIG_HOME', value, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
	}
	path := os.join_path(theme_dir, 'named')
	os.write_file(path, 'foreground = #abcdef\n')!
	mut diags := diagnostics.DiagnosticList{}
	opened := open('named', mut diags) or { panic('expected named theme to open') }
	assert opened.path == path
	assert diags.empty()
	mut file := opened.file
	file.close()

	mut separator_diags := diagnostics.DiagnosticList{}
	assert open(os.join_path('nested', 'theme'), mut separator_diags) == none
	assert separator_diags.items()[0].message == 'theme "${os.join_path('nested', 'theme')}" cannot include path separators unless it is an absolute path'

	mut missing_diags := diagnostics.DiagnosticList{}
	assert open('missing', mut missing_diags) == none
	assert missing_diags.items()[0].message == 'theme "missing" not found, tried path "${os.join_path(theme_dir, 'missing')}"'
}
