module build_support

import os

// Breakpad owns the Mach exception handler, which the collector only needs in
// incremental mode. Build V's bundled collector with that handler disabled.
const macos_bundled_gc_options = ['-d', 'use_bundled_libgc', '-cflags', '-DNO_MPROTECT_VDB=1']

fn compiler_argument(value string) string {
	// V accepts a string of C flags; its C compiler command still needs shell
	// quoting even though the outer build invocation uses structured argv.
	$if windows {
		// Windows C compiles read flags with Windows quoting rules, where single
		// quotes are literal characters; double-quote only when needed.
		if !value.contains_any(' \t"') { return value }
		return '"' + value.replace('"', '\\"') + '"'
	}
	return "'" + value.replace("'", "'\\''") + "'"
}

pub fn (d Driver) v_arguments(artifact Artifact, deps NativeDeps) ![]string {
	module_path := d.compiler_module_path()!
	cc := if d.cfg.target.wasm() { os.getenv_opt('EMCC') or { 'emcc' } } else { os.getenv_opt('CC') or { 'clang' } }
	mut args := [d.cfg.compiler, '-path', module_path, '-cc', cc,
		'-d', 'managed_native']
	args << d.cfg.options(artifact)!
	// V represents `?`*T payloads with a fixed pointer type, so taking the
	// address of a narrower pointee (e.g. `?&TiffTagId`, an enum over u16)
	// emits an incompatible-pointer-types diagnostic. Newer Clang promotes
	// that diagnostic to an error while older toolchains only warned. Keep
	// the historical warning behavior; V's own build silences the same
	// diagnostic. Only clang/gcc-family drivers accept -W flags.
	if cc.contains('clang') || cc.contains('gcc') || cc.contains('emcc') {
		args << ['-cflags', compiler_argument('-Wno-incompatible-pointer-types')]
	}
	for define in deps.defines {
		args << ['-d', define]
	}
	if !d.cfg.target.wasm() {
		args << ['-os', d.cfg.target.os]
	}
	if d.cfg.target.arch in ['aarch64', 'x86_64', 'x86'] {
		args << ['-arch', match d.cfg.target.arch {
			'aarch64' { 'arm64' }
			'x86_64' { 'amd64' }
			else { 'i386' }
		}]
	}
	if !d.cfg.target.wasm() {
		for argument in d.cfg.sdk_arguments()! {
			args << ['-cflags', compiler_argument(argument)]
		}
	}
	if d.cfg.target.os == 'ios' {
		// V's builtin adds the bundled libgc include and defines only for
		// macOS/Linux; iOS slices compile against the same gc.c that
		// runtime_archive links, with its flags.
		gc_include := os.join_path(os.dir(os.real_path(d.cfg.compiler)), 'thirdparty', 'libgc', 'include')
		args << ['-cflags', compiler_argument('-I' + gc_include), '-cflags', '-DGC_BUILTIN_ATOMIC=1',
			'-cflags', '-DALL_INTERIOR_POINTERS=1']
	}
	if d.cfg.target.abi == 'gnu' { args << '-glibc' }
	if d.cfg.target.abi == 'musl' { args << '-musl' }
	for argument in deps.compiler_flags {
		args << ['-cflags', compiler_argument(argument)]
	}
	for archive in deps.archives {
		// V's C builder leaves -x c active for linker flags whose quoted path
		// it cannot classify. Pass archive files directly to the linker so
		// neither the C frontend nor shell reparses them as source inputs.
		args << ['-ldflags', '-Xlinker ' + compiler_argument(archive)]
	}
	for flag in deps.link_flags {
		args << ['-ldflags', compiler_argument(flag)]
	}
	return args
}

fn (d Driver) stage_sources(name string, filenames []string) !string {
	path := d.cache_path('staging', name)
	os.mkdir_all(path)!
	mut imports := []string{}
	mut bodies := []string{}
	for filename in filenames {
		if filename.ends_with('_darwin.v') && !d.cfg.target.darwin() { continue
		 }
		text := os.read_file(os.join_path(d.cfg.root, filename))!
		mut body := []string{}
		// Windows checkouts may use CRLF; `module main\r` must still be dropped.
		for line in text.replace('\r\n', '\n').split('\n') {
			if line == 'module main' { continue
			 }
			if line.starts_with('import ') {
				if line !in imports { imports << line }
			} else {
				body << line
			}
		}
		bodies << body.join('\n')
	}
	// Directory builds qualify the module by its containing directories. A
	// single no_main compilation unit preserves V's exported-function runtime
	// initializer and lazy reachability; function bodies are copied unchanged.
	output := os.join_path(path, name + '.v')
	os.write_file(output, 'module no_main\n\n' + imports.join('\n') + '\n\n' + bodies.join('\n\n'))!
	return output
}

pub fn (d Driver) build_vt() !string {
	deps := d.build_native_dependencies(true)!
	mut files := ['lib_vt.v', 'lib_vt_c.v']
	if d.cfg.target.wasm() { files << 'lib_allocator_wasm32.v' }
	source := d.stage_sources('vt', files)!
	mut args :=
		d.v_arguments(if d.cfg.target.wasm() { Artifact.wasm_module } else { Artifact.lib }, deps)!
	args << ['-d', 'no_oniguruma', '-d', 'no_i18n', '-d', 'no_sentry']
	if !d.cfg.target.wasm() { args = args.filter(it != '-shared') }
	extension := if d.cfg.target.wasm() {
		'.wasm'
	} else if d.cfg.target.os == 'windows' {
		'.dll'
	} else if d.cfg.target.darwin() {
		'.0.1.0.dylib'
	} else {
		'.so.0.1.0'
	}
	output := d.cache_path('artifacts', (if d.cfg.target.wasm() { 'ghostty-vt' } else { 'libghostty-vt' }) + extension)
	os.mkdir_all(os.dir(output))!
	if !d.cfg.target.wasm() {
		object := output + '.o'
		args << ['-is_o', '-cflags', '-fPIC', '-o', object, source]
		checked_process(d.cfg.root, args)!
		d.link_library(object, output, deps, true)!
	} else {
		loader := output.all_before_last('.wasm') + '.js'
		args << ['-ldflags', '-sSTANDALONE_WASM=1', '-ldflags', '--no-entry',
			'-ldflags', '-sMODULARIZE=1', '-ldflags', '-sEXPORT_NAME=GhosttyVT',
			// The selected V runtime rejects pointers in the first 64 KiB.
			// Place Wasm static data above that compiler-owned guard, too.
			'-ldflags', '-sGLOBAL_BASE=65536',
			'-ldflags', '-sEXPORTED_RUNTIME_METHODS=HEAPU8,HEAPU16,HEAPU32',
			'-ldflags', '--js-library=' + compiler_argument(os.join_path(d.cfg.root, 'wasm_log', 'host.js')),
			'-ldflags', '-sALLOW_MEMORY_GROWTH=1', '-ldflags', wasm_export_argument(d.cfg.root, files)!,
			'-o', loader, source]
		checked_process(d.cfg.root, args)!
	}
	if !d.cfg.target.wasm() {
		d.install_file(output, 'lib/' + os.base(output))!
		if d.cfg.target.os != 'windows' {
			names := if d.cfg.target.darwin() {
				['libghostty-vt.dylib', 'libghostty-vt.0.dylib']
			} else {
				['libghostty-vt.so', 'libghostty-vt.so.0']
			}
			for name in names {
				path := os.join_path(d.cfg.prefix, 'lib', name)
				if os.exists(path) || os.is_link(path) { os.rm(path)! }
				os.symlink(os.base(output), path)!
			}
		}
		d.install_tree(os.join_path(d.cfg.root, 'include', 'ghostty'), 'include/ghostty', [])!
		pc :=
			'prefix=${d.cfg.prefix}\nincludedir=\x24{prefix}/include\nlibdir=\x24{prefix}/lib\n\n' +
			'Name: libghostty-vt\nURL: https://github.com/ghostty-org/ghostty\nDescription: Ghostty VT library\n' +
			'Version: 0.1.0\nCflags: -I\x24{includedir}\nLibs: -L\x24{libdir} -lghostty-vt'
		d.install_text('share/pkgconfig/libghostty-vt.pc', pc)!
		if d.cfg.target.darwin() {
			checked_process(d.cfg.root, ['dsymutil', output, '-o', output + '.dSYM'])!
		}
	} else {
		d.install_file(output, 'bin/ghostty-vt.wasm')!
		d.install_file(output.all_before_last('.wasm') + '.js', 'bin/ghostty-vt.js')!
	}
	return output
}

pub fn (d Driver) build_library(deps NativeDeps, static_ bool) !string {
	source := d.stage_sources('lib', ['main_c.v', 'embedded_c.v', 'embedded_c_darwin.v', 'config_c.v',
		'build_config.v'])!
	mut args := d.v_arguments(.lib, deps)!
	args = args.filter(it != '-shared')
	object := d.cache_path('artifacts', 'libghostty.o')
	os.mkdir_all(os.dir(object))!
	args << ['-is_o', '-cflags', '-fPIC', '-o', object, source]
	checked_process(d.cfg.root, args)!
	if !static_ {
		extension := if d.cfg.target.os == 'windows' {
			'.dll'
		} else if d.cfg.target.darwin() {
			'.dylib'
		} else {
			'.so'
		}
		output := d.cache_path('artifacts', 'libghostty' + extension)
		d.link_library(object, output, deps, false)!
		if d.cfg.target.darwin() {
			checked_process(d.cfg.root, ['dsymutil', output, '-o', output + '.dSYM'])!
		}
		return output
	}
	archive := d.cache_path('artifacts', 'libghostty.a')
	if os.exists(archive) { os.rm(archive)! }
	if d.cfg.target.darwin() {
		mut command := ['libtool', '-static', '-o', archive]
		command << deps.archives
		command << d.runtime_archive()!
		command << object
		checked_process(d.cfg.root, command)!
	} else {
		checked_process(d.cfg.root, ['ar', 'rcs', archive, object])!
	}
	return archive
}

pub fn (d Driver) build_executable(deps NativeDeps) !string {
	if d.cfg.target.os == 'linux' && d.cfg.target.arch == host_target().arch
		&& os.exists('/etc/NIXOS') && os.getenv_opt('IN_NIX_SHELL') == none {
		return error('Detected building on and for NixOS outside of the Nix shell environment. Run nix develop -c v run tools/build.')
	}
	mut args := d.v_arguments(.exe, deps)!
	if d.cfg.target.os == 'macos' {
		args << macos_bundled_gc_options
		args << ['-ldflags', '-Wl,-dead_strip_dylibs']
	} else if d.cfg.target.darwin() {
		args << ['-cflags', compiler_argument('-Wl,' + d.runtime_archive()!), '-ldflags',
			'-Wl,-dead_strip_dylibs']
	}
	if d.cfg.target.os == 'windows' {
		resource := d.cache_path('artifacts', 'ghostty-resource.o')
		os.mkdir_all(os.dir(resource))!
		checked_process(d.cfg.root, [os.getenv_opt('WINDRES') or { 'windres' },
			'-I', os.join_path(d.cfg.root, 'build_assets', 'dist', 'windows'),
			'-i', os.join_path(d.cfg.root, 'build_assets', 'dist', 'windows', 'ghostty.rc'),
			'-o', resource])!
		args << ['-ldflags', '-Xlinker ' + compiler_argument(resource), '-ldflags', '-Wl,--subsystem,windows']
	}
	output := d.cache_path('artifacts', 'ghostty' + if d.cfg.target.os == 'windows' {
		'.exe'
	} else {
		''
	})
	os.mkdir_all(os.dir(output))!
	args << ['-o', output, d.cfg.root]
	checked_process(d.cfg.root, args)!
	if value := d.cfg.patch_rpath {
		if value.len > 0 {
			checked_process(d.cfg.root, ['patchelf', '--set-rpath', value, output])!
		}
	}
	if d.cfg.strip { checked_process(d.cfg.root, ['strip', output])! }
	return output
}

fn (d Driver) link_library(object string, output string, deps NativeDeps, vt bool) ! {
	mut command := [os.getenv_opt('CC') or { 'clang' }]
	command << d.cfg.sdk_arguments()!
	command << [if d.cfg.target.darwin() { '-dynamiclib' } else { '-shared' }, '-o', output, object]
	if d.cfg.target.darwin() {
		command << ['-install_name', '@rpath/' +
			if vt { 'libghostty-vt.0.dylib' } else { os.base(output) }]
		if vt { command << ['-current_version', '0.1.0', '-compatibility_version', '0.1.0'] }
	} else if vt && d.cfg.target.os != 'windows' {
		command << '-Wl,-soname,libghostty-vt.so.0'
	} else if d.cfg.target.os == 'windows' {
		command << '-Wl,--export-all-symbols'
	}
	command << deps.archives
	command << deps.link_flags
	command << d.runtime_archive()!
	if !d.cfg.target.darwin() && d.cfg.target.os != 'windows' {
		command << ['-lpthread', '-ldl', '-lm']
	}
	checked_process(d.cfg.root, command)!
}

// Compiler runtime adaptation: use the selected V compiler's unchanged GC
// source with the artifact's target. A prebuilt host archive cannot be used
// in retargeted static libraries or XCFramework slices.
fn (d Driver) runtime_archive() !string {
	root := os.join_path(os.dir(os.real_path(d.cfg.compiler)), 'thirdparty', 'libgc')
	mut flags := ['-I' + os.join_path(root, 'include'), '-DGC_THREADS=1', '-DTHREAD_LOCAL_ALLOC=1',
		'-DGC_BUILTIN_ATOMIC=1', '-DALL_INTERIOR_POINTERS=1', '-DNO_EXECUTE_PERMISSION=1', '-fPIC']
	// MPROTECT_VDB only serves incremental collection, which V never enables,
	// and on Darwin it defines catch_exception_raise, which Breakpad also does.
	if d.cfg.target.darwin() { flags << '-DNO_MPROTECT_VDB=1' }
	if d.cfg.target.os == 'windows' { flags << ['-DGC_NOT_DLL=1', '-DGC_WIN32_THREADS=1'] }
	if d.cfg.target.os == 'freebsd' { flags << ['-DBUS_PAGE_FAULT=T_PAGEFLT', '-DUSE_MMAP'] }
	return d.compile_native('v-runtime-gc', root, ['gc.c'], NativeCompileOptions{
		compiler:  os.getenv_opt('CC') or { 'clang' }
		arguments: d.cfg.sdk_arguments()!
	}, flags)
}

// Zig @export has a named export list; Emscripten needs that same list at link
// time. Read the existing V export annotations rather than exporting private
// compiler or module symbols.
fn wasm_export_argument(root string, files []string) !string {
	mut symbols := []string{}
	for filename in files {
		for line in os.read_file(os.join_path(root, filename))!.split_into_lines() {
			if !line.starts_with("@[export: '") { continue }
			symbols << "'_" + line.all_after("@[export: '").all_before("'") + "'"
		}
	}
	return compiler_argument('-sEXPORTED_FUNCTIONS=[' + symbols.join(',') + ']')
}
