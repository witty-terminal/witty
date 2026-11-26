module build_support

import os

fn collect_test_files(root string, directory string, mut result []string) ! {
	for name in os.ls(directory)! {
		path := os.join_path(directory, name)
		if os.is_dir(path) {
			if name.starts_with('.') || name in ['v-out', 'thirdparty', 'build_assets', 'reference_probes'] { continue
			 }
			collect_test_files(root, path, mut result)!
		} else if name.ends_with('_test.v') {
			result << path[root.len + 1..]
		}
	}
}

pub fn (d Driver) test_files(vt_only bool) ![]string {
	mut files := []string{}
	collect_test_files(d.cfg.root, d.cfg.root, mut files)!
	if vt_only {
		// GhosttyZig.vt and vt_c expose the terminal and input dependency tree.
		files = files.filter(it.split('/')[0] in ['terminal', 'terminal_c', 'input', 'unicode',
			'osc', 'tmux', 'bitmap_allocator', 'page_allocator', 'lib_allocator', 'lib_abi',
			'segmented_list', 'fastmem', 'simd', 'base64', 'buildcfg'])
	}
	files = files.filter(!(it.contains('_darwin_test.v') && !d.cfg.target.darwin())
		&& !(it.contains('_linux_test.v') && d.cfg.target.os != 'linux')
		&& !(it.contains('_windows_test.v') && d.cfg.target.os != 'windows'))
	files.sort()
	if d.cfg.test_filters.len > 0 {
		mut matching := []string{}
		for file in files {
			source := os.read_file(os.join_path(d.cfg.root, file))!
			for line in source.split_into_lines() {
				if !line.starts_with('fn test_') { continue
				 }
				name := line.all_before('(').all_after('fn ')
				if d.cfg.test_filters.any(name.contains(it)) {
					matching << file
					break
				}
			}
		}
		files = matching.clone()
	}
	return files
}

fn valgrind_arguments(executable string) []string {
	return ['valgrind', '--leak-check=full', '--num-callers=50',
		'--gen-suppressions=all',
		executable]
}

// build.zig's test artifact uses baseline CPU, Debug, frame pointers and
// unwind tables independently of the production optimization/strip settings.
// V has one executable per _test.v compilation unit; each is compiled first,
// then executed (or installed), preserving failure and filter propagation.
pub fn (d Driver) run_tests(vt_only bool, valgrind bool, install_only bool) ! {
	tests := Driver{
		cfg: Config{
			...d.cfg
			mode:   .debug
			strip:  false
			pie:    false
			target: Target{
				...d.cfg.target
				cpu: ''
			}
		}
	}
	mut deps := tests.build_native_dependencies(vt_only)!
	if vt_only {
		// V retains generic regex destructors in test compilation units even
		// when terminal features are disabled. This supplies their native ABI;
		// the actual VT library's lazy export build has no Oniguruma dependency.
		deps.archives << tests.build_oniguruma(NativeCompileOptions{
			compiler:  os.getenv_opt('CC') or { 'clang' }
			arguments: tests.cfg.sdk_arguments()!
		})!
	}
	files := tests.test_files(vt_only)!
	// The native updater tests construct the pinned framework's real objects.
	// Other test selections do not need to download or load Sparkle.
	if files.contains('macos/updater_darwin_test.v') {
		os.setenv('WITTY_SPARKLE_TEST_FRAMEWORK', tests.build_sparkle()!, true)
	}
	for file in files {
		println('test ${file}')
		mut args := tests.v_arguments(.exe, deps)!
		if vt_only { args << ['-d', 'no_oniguruma', '-d', 'no_i18n', '-d', 'no_sentry'] }
		if d.cfg.test_filters.len > 0 {
			args << ['-run-only', d.cfg.test_filters.map('*' + it + '*').join(',')]
		}
		executable := d.cache_path('tests', file.replace('/', '_').all_before_last('.v'))
		os.mkdir_all(os.dir(executable))!
		args << ['-skip-running', '-o', executable, os.join_path(d.cfg.root, file)]
		checked_process(d.cfg.root, args)!
		if d.cfg.emit_test_exe {
			d.install_file(executable, 'bin/witty-tests/' + os.base(executable))!
		}
		if install_only { continue
		 }
		command := if valgrind { valgrind_arguments(executable) } else { [
				executable,
			] }
		checked_process(d.cfg.root, command)!
	}
}

pub fn (d Driver) run_executable(valgrind bool) ! {
	if d.cfg.app_runtime == 'none' {
		if !valgrind && d.cfg.target.os == 'macos' {
			d.run_macos_app()!
		}
		// build.zig does not attach a runnable artifact for these configurations.
		return
	}
	selected := if valgrind {
		Driver{
			cfg: Config{
				...d.cfg
				target: Target{
					...d.cfg.target
					cpu: ''
				}
			}
		}
	} else {
		d
	}
	deps := selected.build_native_dependencies(false)!
	executable := selected.build_executable(deps)!
	mut args := if valgrind { valgrind_arguments(executable) } else { [executable] }
	args << d.cfg.run_args
	if valgrind {
		run_foreground(d.cfg.root, args, map[string]string{})!
	} else {
		// The ordinary run artifact uses the installed resources directory.
		run_foreground(d.cfg.root, args, {
			'GHOSTTY_RESOURCES_DIR': os.join_path(d.cfg.prefix, 'share', 'witty')
		})!
	}
}
