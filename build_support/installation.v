module build_support

import os

pub fn (d Driver) install_benchmarks() ! {
	selected := Driver{cfg: Config{...d.cfg, mode: .release_fast}}
	deps := selected.build_native_dependencies(false)!
	for name, folder in {'witty-gen': 'tools/gen', 'witty-bench': 'tools/bench'} {
		output := d.cache_path('artifacts', name + if d.cfg.target.os == 'windows' { '.exe' } else { '' })
		mut command := selected.v_arguments(.exe, deps)!
		command << ['-o', output, os.join_path(d.cfg.root, folder)]
		checked_process(d.cfg.root, command)!
		d.install_file(output, 'bin/' + os.base(output))!
	}
}

// build.zig's default installation graph. Optional generators and test
// artifacts are independent of whether the runtime produces an app or library.
pub fn (d Driver) install() ! {
	d.build_vt()!
	if d.cfg.emit_bench { d.install_benchmarks()! }
	if d.cfg.emit_helpgen { d.install_help_generator()! }
	if d.cfg.emit_unicode_table_gen { d.install_unicode_generators()! }
	if d.cfg.emit_test_exe { d.run_tests(false, false, true)! }
	if d.cfg.app_runtime != 'none' {
		if d.cfg.emit_exe {
			deps := d.build_native_dependencies(false)!
			executable := d.build_executable(deps)!
			d.install_file(executable, 'bin/' + os.base(executable))!
			d.install_resources()!
			d.install_locales()!
		}
	} else if !d.cfg.target.darwin() {
		deps := d.build_native_dependencies(false)!
		shared_library := d.build_library(deps, false)!
		d.install_file(shared_library, 'lib/libwitty.so')!
		static_ := d.build_library(deps, true)!
		d.install_file(static_, 'lib/libwitty.a')!
		d.install_file(os.join_path(d.cfg.root, 'include', 'witty.h'), 'include/witty.h')!
	}
	d.install_docs()!
	if d.cfg.emit_webdata { d.install_webdata()! }
	if d.cfg.target.darwin() {
		if d.cfg.emit_xcframework {
			d.build_xcframework(false)!
			d.install_resources()!
			d.install_locales()!
		}
		if d.cfg.emit_macos_app {
			app := d.build_macos_app_with_framework(false, d.cfg.emit_xcframework)!
			// cp -R retains source framework and terminfo symlinks.
			os.mkdir_all(d.cfg.prefix)!
			checked_process(d.cfg.root, ['cp', '-R', app, d.cfg.prefix])!
		}
	}
}
