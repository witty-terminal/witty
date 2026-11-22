module build_support

import native_libintl
import native_shaders
import native_sentry
import native_metallib
import os

pub struct NativeDeps {
pub mut:
	archives       []string
	link_flags     []string
	compiler_flags []string
	defines        []string
}

// V bindings need C declarations even when the selected backend removes the
// corresponding function bodies. Stage the original public headers separately
// from choosing which native libraries to compile and link.
fn (d Driver) stage_native_headers() ! {
	for name in ['freetype', 'harfbuzz', 'fontconfig', 'oniguruma'] {
		if !d.cfg.system_libraries[name] { d.native_package(name)! }
	}
	if d.cfg.system_libraries['harfbuzz'] { return }
	hb := os.join_path(d.cache_path('deps', 'harfbuzz'), 'src')
	include := d.cache_path('include', 'harfbuzz')
	os.mkdir_all(include)!
	for name in os.ls(hb)! {
		if name.ends_with('.h') { os.cp(os.join_path(hb, name), os.join_path(include, name))! }
	}
}

fn (d Driver) add_package(mut deps NativeDeps, name string, system_name string, archive string) ! {
	if d.cfg.system_libraries[name] {
		flags := checked_process(d.cfg.root, ['pkg-config', '--libs', system_name])!
		deps.link_flags << flags.trim_space().split(' ').filter(it.len > 0)
		deps.compiler_flags << checked_process(d.cfg.root, ['pkg-config', '--cflags', system_name])!.trim_space().split(' ').filter(it.len > 0)
		deps.defines << 'system_' + name.replace('-', '_')
	} else {
		deps.archives << archive
	}
}

// SharedDeps.add chooses native libraries from the artifact's font/runtime/
// renderer options. Static archive paths are retained for libtool composition.
pub fn (d Driver) build_native_dependencies(vt_only bool) !NativeDeps {
	cc := NativeCompileOptions{
		compiler:  os.getenv_opt('CC') or { 'clang' }
		arguments: d.cfg.sdk_arguments()!
	}
	cxx := NativeCompileOptions{
		compiler:  os.getenv_opt('CXX') or { 'clang++' }
		arguments: d.cfg.sdk_arguments()!
	}
	mut deps := NativeDeps{}
	d.generate_unicode_tables()!
	deps.defines << 'generated_unicode_tables'
	if d.cfg.simd {
		deps.archives << d.build_simd(cxx)!
		for name, pkg in {
			'simdutf': 'simdutf'
			'highway': 'libhwy'
		} {
			if d.cfg.system_libraries[name] {
				deps.link_flags << checked_process(d.cfg.root, ['pkg-config', '--libs', pkg])!.trim_space().split(' ').filter(it.len > 0)
			}
		}
		deps.link_flags << if d.cfg.target.darwin() { '-lc++' } else { '-lstdc++' }
	}
	// terminal/page_pool_allocator.h reserves pages with NtAllocateVirtualMemory.
	if d.cfg.target.os == 'windows' { deps.link_flags << '-lntdll' }
	if vt_only {
		// terminal/string_map imports oniguruma, whose bridge includes
		// oniguruma.h even under -d no_oniguruma; stage the pinned headers.
		if !d.cfg.system_libraries['oniguruma'] { d.native_package('oniguruma')! }
		return deps
	}
	frames := d.frame_data()!
	generated := d.cache_path('generated', 'framedata.compressed')
	if frames != generated {
		os.mkdir_all(os.dir(generated))!
		os.cp(frames, generated)!
	}
	deps.defines << 'generated_framedata'
	if d.cfg.renderer == 'metal' {
		native_metallib.build(d.cfg.root, native_metallib.Options{
			os_tag:          d.cfg.target.os
			simulator:       d.cfg.target.abi == 'simulator'
			minimum_version: d.cfg.target.minimum
		})!
		deps.defines << 'compiled_metallib'
	}
	d.stage_native_headers()!
	deps.archives << d.compile_native('wuffs', os.join_path(d.cfg.root, 'wuffs'), [
		'wuffs_bridge.c',
	], cc, [])!
	deps.archives << d.compile_native('stb', os.join_path(d.cfg.root, 'stb'), [
		'stb_bridge.c',
	], cc, [])!
	if d.cfg.renderer == 'opengl' {
		deps.archives << d.compile_native('glad', os.join_path(d.cfg.root, 'opengl'), [
			'glad.c',
		], cc, ['-I' + os.join_path(d.cfg.root, 'opengl')])!
	}
	if d.cfg.sentry && d.cfg.target.os != 'windows' {
		deps.archives << native_sentry.build(d.cfg.root, native_sentry.Options{
			c_compiler:    cc.compiler
			cpp_compiler:  cxx.compiler
			compiler_args: cc.arguments
			os_tag:        d.cfg.target.os
			native_dir:    d.native_dir()
		})!
	}

	// Dependents precede their own dependencies in the linker arguments.
	// V stores the source's compile-time backend alternatives in runtime
	// tagged values. Their live destructors/dispatch retain Fontconfig and
	// HarfBuzz references even when CoreText is selected; link the unchanged
	// source native packages for those compiler-retained branches.
	if !d.cfg.target.wasm() {
		fc := if d.cfg.system_libraries['fontconfig'] { '' } else { d.build_fontconfig(cc)! }
		d.add_package(mut deps, 'fontconfig', 'fontconfig', fc)!
		if !d.cfg.system_libraries['fontconfig'] {
			xml := if d.cfg.system_libraries['libxml2'] { '' } else { d.build_libxml2(cc)! }
			d.add_package(mut deps, 'libxml2', 'libxml-2.0', xml)!
			if d.cfg.target.os != 'windows' { deps.link_flags << '-lpthread' }
			if d.cfg.target.os == 'windows' { deps.link_flags << '-lws2_32' }
			if d.cfg.target.darwin() { deps.link_flags << '-liconv' }
		}
	}
	if !d.cfg.target.wasm() {
		hb := if d.cfg.system_libraries['harfbuzz'] { '' } else { d.build_harfbuzz(cxx)! }
		d.add_package(mut deps, 'harfbuzz', 'harfbuzz', hb)!
	}
	deps.archives << d.build_cimgui(cxx)!
	if d.cfg.target.darwin() {
		deps.link_flags << '-lobjc'
		for framework in ['Foundation', 'CoreFoundation', 'CoreGraphics', 'CoreText', 'CoreVideo',
			'QuartzCore', 'IOSurface', 'Metal'] {
			deps.link_flags << ['-framework', framework]
		}
		if d.cfg.target.os == 'macos' { deps.link_flags << ['-framework', 'AppKit', '-framework',
				'Carbon'] }
		if d.cfg.renderer == 'opengl' { deps.link_flags << ['-framework', 'OpenGL'] }
	}
	deps.link_flags << if d.cfg.target.darwin() { '-lc++' } else { '-lstdc++' }
	ft := if d.cfg.system_libraries['freetype'] { '' } else { d.build_freetype(cc)! }
	d.add_package(mut deps, 'freetype', 'freetype2', ft)!
	if d.cfg.system_libraries['freetype'] { deps.link_flags << '-lbz2' }
	png := if d.cfg.system_libraries['libpng'] { '' } else { d.build_png(cc)! }
	d.add_package(mut deps, 'libpng', 'libpng', png)!
	z := if d.cfg.system_libraries['zlib'] { '' } else { d.build_zlib(cc)! }
	d.add_package(mut deps, 'zlib', 'zlib', z)!
	onig := if d.cfg.system_libraries['oniguruma'] { '' } else { d.build_oniguruma(cc)! }
	d.add_package(mut deps, 'oniguruma', 'oniguruma', onig)!
	deps.archives << native_shaders.build(d.cfg.root, native_shaders.Options{
		compiler:      cxx.compiler
		compiler_args: cxx.arguments
		os_tag:        d.cfg.target.os
		musl:          d.cfg.target.abi == 'musl'
		glslang:       !d.cfg.system_libraries['glslang']
		spirv_cross:   !d.cfg.system_libraries['spirv-cross']
		native_dir:    d.native_dir()
	})!
	for name, packages in {
		'glslang':     ['glslang', 'glslang-default-resource-limits']
		'spirv-cross': ['spirv-cross-c-shared']
	} {
		if !d.cfg.system_libraries[name] { continue
		 }
		deps.defines << 'system_' + name.replace('-', '_')
		for package in packages {
			deps.link_flags << checked_process(d.cfg.root, ['pkg-config', '--libs', package])!.trim_space().split(' ').filter(it.len > 0)
			deps.compiler_flags << checked_process(d.cfg.root, ['pkg-config', '--cflags', package])!.trim_space().split(' ').filter(it.len > 0)
		}
	}
	if d.cfg.target.darwin() && d.cfg.i18n {
		deps.archives << native_libintl.build(d.cfg.root, cc.compiler, cc.arguments, d.native_dir())!
	}
	d.prepare_gtk_resources()!
	d.generate_help_strings()!
	deps.defines << 'generated_help_strings'
	return deps
}

pub fn (d Driver) build_cimgui(options NativeCompileOptions) !string {
	root := os.join_path(d.cfg.root, 'cimgui')
	mut sources := ['vendor/imgui/imgui_demo.cpp', 'vendor/imgui/imgui_draw.cpp',
		'vendor/imgui/imgui_tables.cpp', 'vendor/imgui/imgui_widgets.cpp', 'vendor/imgui/imgui.cpp',
		'vendor/imgui/misc/freetype/imgui_freetype.cpp', 'vendor/dear_bindings/dcimgui.cpp',
		'vendor/dear_bindings/dcimgui_internal.cpp', 'ext.cpp', 'text_filter.cpp', 'detail.cpp']
	mut flags := ['-std=c++17', '-DIMGUI_HAS_DOCK=1', '-DIMGUI_USE_WCHAR32=1',
		'-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1', '-DIMGUI_ENABLE_FREETYPE=1',
		'-I' +
			os.join_path(root, 'vendor', 'imgui'),
		'-I' +
			os.join_path(root, 'vendor', 'imgui', 'backends'),
		'-I' +
			os.join_path(root, 'vendor', 'dear_bindings')]
	flags << if d.cfg.target.os == 'windows' {
		'-DIMGUI_IMPL_API=extern\t"C"\t__declspec(dllexport)'
	} else {
		'-DIMGUI_IMPL_API=extern\t"C"'
	}
	if d.cfg.target.os == 'freebsd' || d.cfg.target.abi == 'musl' { flags << '-fPIC' }
	if d.cfg.system_libraries['freetype'] {
		flags << checked_process(d.cfg.root, ['pkg-config', '--cflags', 'freetype2'])!.trim_space().split(' ').filter(it.len > 0)
	} else {
		flags << '-I' + os.join_path(d.native_package('freetype')!, 'include')
	}
	if d.cfg.target.darwin() {
		sources << ['metal_backend.mm', 'metal_bridge.mm']
	}
	if d.cfg.target.os == 'macos' {
		sources << 'vendor/imgui/backends/imgui_impl_osx.mm'
	}
	if d.cfg.renderer == 'opengl' {
		sources << ['vendor/imgui/backends/imgui_impl_opengl3.cpp', 'opengl_bridge.cpp']
	}
	return d.compile_native('dcimgui', root, sources, options, flags)
}

pub fn (d Driver) build_simd(options NativeCompileOptions) ![]string {
	root := os.join_path(d.cfg.root, 'simd', 'native')
	include := ['-I' + root, '-I' + os.join_path(root, 'highway'),
		'-I' + os.join_path(root, 'simdutf'), '-I' + os.join_path(root, 'utfcpp', 'source')]
	mut flags := include.clone()
	flags << '-std=c++17'
	if d.cfg.target.arch == 'x86_64' { flags << ['-DHWY_DISABLED_TARGETS=472', '-Wno-psabi'] }
	mut result := [
		d.compile_native('ghostty-simd', root, ['simd/base64.cpp', 'simd/codepoint_width.cpp',
			'simd/index_of.cpp', 'simd/vt.cpp'], options, flags)!,
	]
	if !d.cfg.system_libraries['simdutf'] {
		mut utf_flags := include.clone()
		utf_flags << ['-DSIMDUTF_IMPLEMENTATION_ICELAKE=0', '-fno-sanitize=undefined',
			'-fno-sanitize-trap=undefined']
		if d.cfg.target.os == 'freebsd' || d.cfg.target.abi == 'musl' { utf_flags << '-fPIC' }
		result << d.compile_native('simdutf', root, ['simdutf/simdutf.cpp'], options, utf_flags)!
	}
	if !d.cfg.system_libraries['highway'] {
		mut hwy := include.clone()
		hwy << ['-std=c++17', '-Wno-builtin-macro-redefined', '-D__DATE__="redacted"',
			'-D__TIMESTAMP__="redacted"', '-D__TIME__="redacted"', '-fmerge-all-constants', '-Wall',
			'-Wextra', '-Wconversion', '-Wsign-conversion', '-Wvla', '-Wnon-virtual-dtor',
			'-Wfloat-overflow-conversion', '-Wfloat-zero-conversion', '-Wfor-loop-analysis',
			'-Wgnu-redeclared-enum', '-Winfinite-recursion', '-Wself-assign', '-Wstring-conversion',
			'-Wtautological-overlap-compare', '-Wthread-safety-analysis', '-Wundefined-func-template',
			'-fno-cxx-exceptions', '-fno-slp-vectorize', '-fno-vectorize', '-fno-sanitize=undefined',
			'-fno-sanitize-trap=undefined']
		if d.cfg.target.os == 'freebsd' || d.cfg.target.abi == 'musl' { hwy << '-fPIC' }
		if d.cfg.target.os != 'windows' { hwy << ['-fmath-errno', '-fno-exceptions'] }
		result << d.compile_native('highway', root, ['highway_bridge.cpp', 'abort.cpp',
			'aligned_allocator.cpp', 'nanobenchmark.cpp', 'per_target.cpp', 'print.cpp',
			'targets.cpp', 'timer.cpp'], options, hwy)!
	}
	return result
}
