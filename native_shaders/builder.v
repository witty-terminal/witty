module native_shaders

import os

pub struct Options {
pub:
	compiler      string = 'c++'
	compiler_args []string
	os_tag        string = os.user_os()
	musl          bool
	glslang       bool = true
	spirv_cross   bool = true
	// Archive directory; defaults to the host's .witty-build/native.
	native_dir string
}

fn output_dir(repo_root string, options Options) string {
	return if options.native_dir.len > 0 { options.native_dir } else { os.join_path(repo_root, '.witty-build', 'native') }
}

pub fn archive_path(repo_root string, library string) string {
	return os.join_path(repo_root, '.witty-build', 'native', 'lib${library}.a')
}

// Translates pkg/glslang/build.zig and pkg/spirv-cross/build.zig. Upstream C++
// files remain unchanged; only the build-system interface differs.
pub fn build(repo_root string, options Options) ![]string {
	mut result := []string{}
	for library in ['glslang', 'spirv_cross'] {
		if library == 'glslang' && !options.glslang { continue
		 }
		if library == 'spirv_cross' && !options.spirv_cross { continue
		 }
		root := os.join_path(repo_root, 'thirdparty', library.replace('_', '-'))
		out := os.join_path(output_dir(repo_root, options), library + '-objects')
		os.mkdir_all(out)!
		mut sources := if library == 'glslang' {
			glslang_sources[..].clone()
		} else {
			spirv_cross_sources[..].clone()
		}
		if library == 'glslang' {
			sources << if options.os_tag == 'windows' {
				'glslang/OSDependent/Windows/ossource.cpp'
			} else {
				'glslang/OSDependent/Unix/ossource.cpp'
			}
		}
		mut flags := options.compiler_args.clone()
		flags << ['-std=c++17', '-fno-sanitize=undefined', '-fno-sanitize-trap=undefined',
			'-I' + root]
		if library == 'glslang' {
			flags << '-I' + os.join_path(root, 'override')
			// SpvBuilder.h uses uint32_t without including <cstdint>,
			// relying on transitive includes that current standard
			// libraries no longer provide. Upstream headers stay
			// untouched, so force the include from the build interface.
			// (Two argv elements: process args are passed verbatim,
			// never re-split.)
			flags << ['-include', 'cstdint']
		}
		if library == 'spirv_cross' { flags << ['-DSPIRV_CROSS_C_API_GLSL=1',
				'-DSPIRV_CROSS_C_API_MSL=1'] }
		if options.os_tag == 'freebsd' || options.musl { flags << '-fPIC' }
		mut objects := []string{cap: sources.len}
		for source in sources {
			object := os.join_path(out, source.replace('/', '_') + '.o')
			mut args := flags.clone()
			args << ['-c', os.join_path(root, source), '-o', object]
			run(options.compiler, args)!
			objects << object
		}
		archive := os.join_path(output_dir(repo_root, options), 'lib${library}.a')
		if os.exists(archive) { os.rm(archive)! }
		mut args := ['rcs', archive]
		args << objects
		run('ar', args)!
		result << archive
	}
	return result
}

pub fn run(executable string, args []string) ! {
	mut process := os.new_process(executable)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	errors := process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${executable} failed (${code}): ${output}${errors}') }
}
