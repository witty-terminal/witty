module build_support

import crypto.sha256
import x.json2
import os

pub struct NativePackage {
pub:
	url      string
	zig_hash string
	sha256   string
}

const native_packages = $embed_file('@VMODROOT/build_assets/native/packages.json').to_string()

// The raw archive hashes were recorded only after Zig 0.15.2 verified each
// package against the original build.zig.zon's package hash. A V build can
// subsequently verify the immutable archive without requiring a Zig builder.
pub fn (d Driver) native_package(name string) !string {
	packages := json2.decode[map[string]NativePackage](native_packages)!
	spec := packages[name] or { return error('unknown native package ${name}') }
	ext := if spec.url.ends_with('.xz') { '.tar.xz' } else { '.tar.gz' }
	archive := d.cache_path('downloads', name + ext)
	if !os.exists(archive) {
		os.mkdir_all(os.dir(archive))!
		temporary := archive + '.partial'
		checked_process(d.cfg.root, ['curl', '--fail', '--location', '--silent', '--show-error',
			'--output', temporary, spec.url])!
		if sha256.sum(os.read_bytes(temporary)!).hex() != spec.sha256 {
			return error('${name} archive checksum mismatch')
		}
		os.mv(temporary, archive)!
	}
	if sha256.sum(os.read_bytes(archive)!).hex() != spec.sha256 {
		return error('${name} archive checksum mismatch')
	}
	path := d.cache_path('deps', name)
	if !os.exists(os.join_path(path, '.source-checksum')) {
		os.mkdir_all(path)!
		d.extract_archive(archive, path)!
		os.write_file(os.join_path(path, '.source-checksum'), spec.sha256)!
	}
	return path
}

pub struct NativeCompileOptions {
pub:
	compiler  string = 'cc'
	arguments []string
}

pub fn (d Driver) compile_native(name string, root string, sources []string, options NativeCompileOptions, flags []string) !string {
	dir := os.join_path(d.native_dir(), name + '-objects')
	os.mkdir_all(dir)!
	mut objects := []string{}
	for source in sources {
		output := os.join_path(dir, source.replace('/', '_') + '.o')
		mut args := [options.compiler]
		args << options.arguments
		args << flags
		if source.ends_with('.rc') {
			resource_target := match d.cfg.target.arch {
				'x86_64' { 'pe-x86-64' }
				'aarch64' { 'pe-aarch64-little' }
				else { 'pe-i386' }
			}
			args = [os.getenv_opt('RC') or { 'windres' }, '--target=' + resource_target,
				'-I' + os.join_path(root, 'include'), '--input', os.join_path(root, source), '--output',
				output]
		} else {
			args << ['-c', os.join_path(root, source), '-o', output]
		}
		checked_process(d.cfg.root, args)!
		objects << output
	}
	archive := os.join_path(d.native_dir(), 'lib${name}.a')
	// ar rcs replaces named members but retains removed members. Retargeted
	// builds must begin with a fresh archive, as std.Build's library step does.
	if os.exists(archive) { os.rm(archive)! }
	mut args := ['ar', 'rcs', archive]
	args << objects
	checked_process(d.cfg.root, args)!
	return archive
}

fn native_sources(name string) ![]string {
	text := match name {
		'zlib' { $embed_file('@VMODROOT/build_assets/native/zlib-sources.json').to_string() }
		'libpng' { $embed_file('@VMODROOT/build_assets/native/libpng-sources.json').to_string() }
		'freetype' {
			$embed_file('@VMODROOT/build_assets/native/freetype-sources.json').to_string()
		}
		'oniguruma' {
			$embed_file('@VMODROOT/build_assets/native/oniguruma-sources.json').to_string()
		}
		'libxml2' { $embed_file('@VMODROOT/build_assets/native/libxml2-sources.json').to_string() }
		'fontconfig' {
			$embed_file('@VMODROOT/build_assets/native/fontconfig-sources.json').to_string()
		}
		else { return error('no source manifest for ${name}') }
	}
	return json2.decode[[]string](text)
}

// The source lists and flags are pkg/zlib/build.zig and pkg/libpng/build.zig.
pub fn (d Driver) build_zlib(options NativeCompileOptions) !string {
	root := d.native_package('zlib')!
	return d.compile_native('z', root, native_sources('zlib')!, options,
		['-I' + root, '-DHAVE_SYS_TYPES_H', '-DHAVE_STDINT_H', '-DHAVE_STDDEF_H', '-DZ_HAVE_UNISTD_H'])
}

// libpng's png.h requires the configured pnglibconf.h. FreeType's PNG shim
// includes png.h too, so stage it for whichever is compiled first.
fn (d Driver) libpng_source() !string {
	root := d.native_package('libpng')!
	os.cp(os.join_path(d.cfg.root, 'build_assets', 'native', 'pnglibconf.h'), os.join_path(root, 'pnglibconf.h'))!
	return root
}

pub fn (d Driver) build_png(options NativeCompileOptions) !string {
	root := d.libpng_source()!
	mut flags := ['-I' + root, '-DPNG_ARM_NEON_OPT=0', '-DPNG_POWERPC_VSX_OPT=0',
		'-DPNG_INTEL_SSE_OPT=0', '-DPNG_MIPS_MSA_OPT=0']
	if !d.cfg.system_libraries['zlib'] { flags << '-I' + d.native_package('zlib')! }
	return d.compile_native('png', root, native_sources('libpng')!, options, flags)
}

pub fn (d Driver) build_freetype(options NativeCompileOptions) !string {
	root := d.native_package('freetype')!
	mut sources := native_sources('freetype')!
	sources << match d.cfg.target.os {
		'linux' { 'builds/unix/ftsystem.c' }
		'windows' { 'builds/windows/ftsystem.c' }
		else { 'src/base/ftsystem.c' }
	}
	sources << if d.cfg.target.os == 'windows' {
		'builds/windows/ftdebug.c'
	} else {
		'src/base/ftdebug.c'
	}
	if d.cfg.target.os == 'windows' { sources << 'src/base/ftver.rc' }
	mut flags := ['-I' + os.join_path(root, 'include'), '-DFT2_BUILD_LIBRARY',
		'-DFT_CONFIG_OPTION_SYSTEM_ZLIB=1', '-DFT_CONFIG_OPTION_USE_PNG=1', '-DHAVE_UNISTD_H',
		'-DHAVE_FCNTL_H', '-fno-sanitize=undefined']
	if d.cfg.target.os == 'freebsd' || d.cfg.target.abi == 'musl' { flags << '-fPIC' }
	if !d.cfg.system_libraries['zlib'] { flags << '-I' + d.native_package('zlib')! }
	if !d.cfg.system_libraries['libpng'] { flags << '-I' + d.libpng_source()! }
	return d.compile_native('freetype', root, sources, options, flags)
}

pub fn (d Driver) build_harfbuzz(options NativeCompileOptions) !string {
	root := d.native_package('harfbuzz')!
	mut flags := ['-I' + os.join_path(root, 'src'), '-DHAVE_STDBOOL_H']
	if d.cfg.target.os != 'windows' {
		flags << ['-DHAVE_UNISTD_H', '-DHAVE_SYS_MMAN_H', '-DHAVE_PTHREAD=1']
	}
	// Retain the native entry points used by V's runtime backend values.
	if !d.cfg.target.wasm() {
		flags << ['-DHAVE_FREETYPE=1', '-DHAVE_FT_GET_VAR_BLEND_COORDINATES=1',
			'-DHAVE_FT_SET_VAR_BLEND_COORDINATES=1', '-DHAVE_FT_DONE_MM_VAR=1',
			'-DHAVE_FT_GET_TRANSFORM=1']
		if !d.cfg.system_libraries['freetype'] {
			flags << '-I' + os.join_path(d.native_package('freetype')!, 'include')
		} else {
			output := checked_process(d.cfg.root, ['pkg-config', '--cflags-only-I', 'freetype2'])!
			flags << output.trim_space().split(' ').filter(it.len > 0)
		}
	}
	if d.cfg.target.darwin() {
		flags << '-DHAVE_CORETEXT=1'
	}
	flags << '-std=c++17'
	return d.compile_native('harfbuzz', root, ['src/harfbuzz.cc'], options, flags)
}

pub fn (d Driver) build_oniguruma(options NativeCompileOptions) !string {
	root := d.native_package('oniguruma')!
	ptr_size := d.cfg.target.pointer_size()!
	long_size := if d.cfg.target.os == 'windows' { 4 } else { ptr_size }
	values := {
		'PACKAGE':          '"oniguruma"'
		'PACKAGE_VERSION':  '"6.9.9"'
		'VERSION':          '"6.9.9"'
		'HAVE_ALLOCA':      '1'
		'HAVE_ALLOCA_H':    '1'
		'HAVE_STDINT_H':    '1'
		'HAVE_SYS_TIMES_H': '1'
		'HAVE_SYS_TIME_H':  '1'
		'HAVE_SYS_TYPES_H': '1'
		'HAVE_UNISTD_H':    '1'
		'HAVE_INTTYPES_H':  '1'
		'SIZEOF_INT':       '4'
		'SIZEOF_LONG':      '${long_size}'
		'SIZEOF_LONG_LONG': '8'
		'SIZEOF_VOIDP':     '${ptr_size}'
	}
	template := os.read_file(os.join_path(root, 'src', 'config.h.cmake.in'))!
	os.write_file(os.join_path(root, 'src', 'config.h'), configure_cmake(template, values))!
	return d.compile_native('onig', root, native_sources('oniguruma')!, options, ['-I' + os.join_path(root, 'src')])
}

// std.Build.Step.ConfigHeader's cmake spelling, used by the source package.
// Unspecified/false feature macros remain undefined; replacement occurs only
// for configured values. This is a build adapter, not runtime feature probing.
fn configure_cmake(template string, values map[string]string) string {
	mut lines := []string{}
	for original in template.split('\n') {
		mut line := original
		if line.starts_with('#cmakedefine ') {
			name := line[13..].all_before(' ')
			if name in values {
				line = '#define ' + line[13..]
			} else {
				line = '/* #undef ${name} */'
			}
		}
		for name, value in values {
			line = line.replace('@${name}@', value).replace('\x24{${name}}', value)
		}
		lines << line
	}
	return lines.join('\n')
}

// pkg/libxml2/build.zig: Fontconfig enables iconv except on Windows. The
// remaining configure switches retain their declared source defaults.
pub fn (d Driver) build_libxml2(options NativeCompileOptions) !string {
	root := d.native_package('libxml2')!
	override := os.join_path(d.cfg.root, 'build_assets', 'native', 'libxml2-override')
	mut flags := ['-I' + os.join_path(override, 'include'), '-I' + os.join_path(root, 'include'),
		'-I' + os.join_path(override, 'config', if d.cfg.target.os == 'windows' {
			'win32'
		} else {
			'posix'
		}), '-DLIBXML_VERSION=201105', '-DLIBXML_VERSION_STRING="201105"', '-DLIBXML_VERSION_EXTRA=""',
		'-DLIBXML_DOTTED_VERSION="2.11.5"', '-DSEND_ARG2_CAST=', '-DGETHOSTBYNAME_ARG_CAST=',
		'-DGETHOSTBYNAME_ARG_CAST_CONST=', '-DLIBXML_STATIC=1', '-DLIBXML_AUTOMATA_ENABLED=1',
		'-DWITHOUT_TRIO=1']
	if d.cfg.target.os != 'windows' {
		for name in ['ARPA_INET', 'ARPA_NAMESER', 'DL', 'NETDB', 'NETINET_IN', 'PTHREAD', 'SYS_DIR',
			'SYS_MMAN', 'SYS_NDIR', 'SYS_SELECT', 'SYS_SOCKET', 'SYS_TIMEB', 'SYS_TIME', 'SYS_TYPES'] {
			flags << '-DHAVE_${name}_H=1'
		}
		flags << ['-DHAVE_SHLLOAD=1', '-DLIBXML_ICONV_ENABLED=1']
	}
	for name in ['C14N', 'CATALOG', 'DEBUG', 'HISTORY', 'HTML', 'ISO8859X', 'MINIMUM', 'OUTPUT',
		'PATTERN', 'PUSH', 'READER', 'REGEXP', 'SAX1', 'SCHEMAS', 'SCHEMATRON', 'THREAD', 'TREE',
		'VALID', 'WRITER', 'XINCLUDE', 'XPATH', 'XPTR', 'MODULES'] {
		flags << '-DLIBXML_${name}_ENABLED=1'
	}
	flags << ['-DHAVE_LIBHISTORY=1', '-DHAVE_LIBREADLINE=1', '-DLIBXML_UNICODE_ENABLED=1',
		'-DHAVE_LIBPTHREAD=1']
	return d.compile_native('xml2', root, native_sources('libxml2')!, options, flags)
}

// pkg/fontconfig/build.zig's default libxml2/freetype build. Override headers
// are committed source inputs; platform and pointer-width macros are selected
// from the artifact target, never from the host process.
pub fn (d Driver) build_fontconfig(options NativeCompileOptions) !string {
	root := d.native_package('fontconfig')!
	override := os.join_path(d.cfg.root, 'build_assets', 'native', 'fontconfig-override', 'include')
	mut flags := ['-I' + override, '-I' + root, '-DENABLE_LIBXML2', '-DLIBXML_STATIC',
		'-DLIBXML_PUSH_ENABLED', '-Wno-implicit-function-declaration', '-Wno-int-conversion',
		'-fno-sanitize=undefined', '-fno-sanitize-trap=undefined', '-DFLEXIBLE_ARRAY_MEMBER',
		'-DFC_GPERF_SIZE_T=size_t']
	for name in ['DIRENT_H', 'FCNTL_H', 'STDLIB_H', 'STRING_H', 'UNISTD_H', 'SYS_PARAM_H', 'MKSTEMP',
		'RAND', 'VPRINTF', 'FT_GET_BDF_PROPERTY', 'FT_GET_PS_FONT_INFO', 'FT_HAS_PS_GLYPH_NAMES',
		'FT_GET_X11_FONT_FORMAT', 'FT_DONE_MM_VAR', 'POSIX_FADVISE', 'STDATOMIC_PRIMITIVES'] {
		flags << '-DHAVE_${name}'
	}
	ptr_size := d.cfg.target.pointer_size()!
	flags << ['-DSIZEOF_VOID_P=${ptr_size}', '-DALIGNOF_VOID_P=${ptr_size}']
	if d.cfg.target.os == 'windows' {
		flags << ['-DFC_CACHEDIR="LOCAL_APPDATA_FONTCONFIG_CACHE"',
			'-DFC_TEMPLATEDIR="c:/share/fontconfig/conf.avail"', '-DCONFIGDIR="c:/etc/fonts/conf.d"',
			'-DFC_DEFAULT_FONTS="\\t<dir>WINDOWSFONTDIR</dir>\\n\\t<dir>WINDOWSUSERFONTDIR</dir>\\n"',
			'-Werror=implicit-function-declaration']
	} else {
		for name in ['FSTATFS', 'FSTATVFS', 'GETOPT', 'GETOPT_LONG', 'LINK', 'LRAND48', 'LSTAT',
			'MKDTEMP', 'MKOSTEMP', '_MKTEMP_S', 'MMAP', 'PTHREAD', 'RANDOM', 'RAND_R', 'READLINK',
			'SYS_MOUNT_H', 'SYS_STATVFS_H'] {
			flags << '-DHAVE_${name}'
		}
		flags << ['-DFC_CACHEDIR="/var/cache/fontconfig"',
			'-DFC_DEFAULT_FONTS="<dir>/usr/share/fonts</dir><dir>/usr/local/share/fonts</dir>"']
		if d.cfg.target.os == 'freebsd' {
			flags << ['-DFC_TEMPLATEDIR="/usr/local/etc/fonts/conf.avail"',
				'-DFONTCONFIG_PATH="/usr/local/etc/fonts"', '-DCONFIGDIR="/usr/local/etc/fonts/conf.d"']
		} else {
			flags << ['-DFC_TEMPLATEDIR="/usr/share/fontconfig/conf.avail"',
				'-DFONTCONFIG_PATH="/etc/fonts"', '-DCONFIGDIR="/usr/local/fontconfig/conf.d"']
		}
		if d.cfg.target.os == 'linux' { flags << ['-DHAVE_SYS_STATFS_H', '-DHAVE_SYS_VFS_H'] }
	}
	if d.cfg.system_libraries['freetype'] {
		flags << checked_process(d.cfg.root, ['pkg-config', '--cflags-only-I', 'freetype2'])!.trim_space().split(' ').filter(it.len > 0)
	} else {
		flags << '-I' + os.join_path(d.native_package('freetype')!, 'include')
	}
	if d.cfg.system_libraries['libxml2'] {
		flags << checked_process(d.cfg.root, ['pkg-config', '--cflags-only-I', 'libxml-2.0'])!.trim_space().split(' ').filter(it.len > 0)
	} else {
		flags << [
			'-I' + os.join_path(d.cfg.root, 'build_assets', 'native', 'libxml2-override', 'include'),
			'-I' + os.join_path(d.native_package('libxml2')!, 'include'),
		]
	}
	return d.compile_native('fontconfig', root, native_sources('fontconfig')!, options, flags)
}

fn repo_relative(root string, path string) string {
	prefix := root.trim_right('/\\') + os.path_separator
	return if path.starts_with(prefix) { path[prefix.len..] } else { path }
}

// tar arguments on every platform: repo-relative (see above) and always
// forward-slashed, since MSYS tar rejects `\` separators.
fn tar_relative(root string, path string) string {
	return repo_relative(root, path).replace('\\', '/')
}

// MSYS tar (Git for Windows) without symlink privilege materializes
// symlinks as copies of their targets, so a link whose target appears
// later in the archive fails with `Cannot create symlink`. Real symlinks
// (Linux, macOS, Developer-Mode Windows) never hit this. Repeating the
// extraction resolves previously missing targets; only symlink-ordering
// failures are retried, anything else aborts immediately.
fn (d Driver) extract_archive(archive string, dest string) ! {
	command := ['tar', 'xf', tar_relative(d.cfg.root, archive), '--strip-components=1', '-C',
		tar_relative(d.cfg.root, dest)]
	for attempt in 0 .. 8 {
		result := run_process(d.cfg.root, command)!
		if result.exit_code == 0 {
			return
		}
		if attempt == 7 {
			return error('tar failed: ${result.output}')
		}
		mut retryable := false
		for line in result.output.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed == '' || trimmed.contains('Exiting with failure status') {
				continue
			}
			if trimmed.contains('Cannot create symlink') {
				retryable = true
				continue
			}
			return error('tar failed: ${result.output}')
		}
		if !retryable {
			return error('tar failed: ${result.output}')
		}
	}
	return error('tar failed after 8 passes')
}
