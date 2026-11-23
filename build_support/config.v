module build_support

import os
import semver

// Config.zig's build-time decisions are independent of the platform on which
// this driver runs. In particular, retargeting changes the target and options
// without changing the host tools used to generate resources.
pub struct Target {
pub:
	arch string
	os string
	abi string
	minimum string
	cpu string = 'baseline'
}

pub fn host_target() Target {
	return Target{
		arch: $if arm64 { 'aarch64' } $else $if amd64 { 'x86_64' } $else { 'native' }
		os: os.user_os()
		abi: $if glibc { 'gnu' } $else { '' }
	}
}

pub fn (target Target) darwin() bool { return target.os in ['macos', 'ios'] }
pub fn (target Target) wasm() bool { return target.arch in ['wasm32', 'wasm64'] }

pub fn parse_target(value string) !Target {
	if value == 'native' || value == '' { return host_target() }
	parts := value.split('-')
	if parts.len < 2 || parts.len > 3 { return error('invalid target: ${value}') }
	mut name := parts[1]
	mut minimum := ''
	if name.contains('.') {
		minimum = name.all_after('.')
		name = name.all_before('.')
	}
	if name !in ['macos', 'ios', 'linux', 'freebsd', 'windows', 'wasi', 'freestanding'] {
		return error('invalid target OS: ${name}')
	}
	return Target{arch: parts[0], os: name, abi: if parts.len == 3 { parts[2] } else { '' }, minimum: minimum}
}

pub enum Entrypoint {
	ghostty
	helpgen
	mdgen_witty_1
	mdgen_witty_5
	webgen_config
	webgen_actions
	webgen_commands
}

pub struct Config {
pub mut:
	root string
	prefix string
	compiler string
	target Target
	mode Mode
	xcframework_target string = 'universal'
	wasm_target string = 'browser'
	app_runtime string
	renderer string
	font_backend string
	x11 bool
	wayland bool
	sentry bool
	simd bool
	i18n bool
	wasm_shared bool = true
	entrypoint Entrypoint
	version string
	pie bool
	strip bool
	patch_rpath ?string
	flatpak bool
	snap bool
	emit_bench bool
	emit_docs bool
	emit_exe bool
	emit_helpgen bool
	emit_macos_app bool
	emit_terminfo bool
	emit_termcap bool
	emit_test_exe bool
	emit_themes bool
	emit_xcframework bool
	emit_webdata bool
	emit_unicode_table_gen bool
	system_package bool
	system_libraries map[string]bool
	steps []string
	run_args []string
	test_filters []string
}

fn option_bool(options map[string]string, key string, default_value bool) !bool {
	if key !in options { return default_value }
	value := options[key]
	return match value {
		'true', '1' { true }
		'false', '0' { false }
		else { return error('invalid boolean -D${key}=${value}') }
	}
}

pub fn init_config(root string, args []string) !Config {
	mut options := map[string]string{}
	mut steps := []string{}
	mut run_args := []string{}
	mut filters := []string{}
	mut system_libraries := map[string]bool{}
	mut prefix := os.join_path(root, 'v-out')
	mut compiler := os.getenv('VEXE')
	if compiler == '' { compiler = resolve_executable('v')! }
	mut system_package := false
	mut i := 0
	for i < args.len {
		arg := args[i]
		i++
		if arg == '--' { run_args = args[i..].clone(); break }
		if arg == '--prefix' || arg == '-p' {
			if i == args.len { return error('missing install prefix') }
			prefix = os.abs_path(args[i]); i++; continue
		}
		if arg == '--system' { system_package = true; continue }
		if arg.starts_with('-fsys=') { system_libraries[arg.all_after('=')] = true; continue }
		if arg.starts_with('-fno-sys=') { system_libraries[arg.all_after('=')] = false; continue }
		if arg.starts_with('-D') {
			pair := arg[2..].split_nth('=', 2)
			key := pair[0]
			value := if pair.len == 1 { 'true' } else { pair[1] }
			if key == 'test-filter' { filters << value } else { options[key] = value }
			continue
		}
		if arg.starts_with('-') { return error('unknown build argument: ${arg}') }
		steps << arg
	}
	for key, _ in options {
		if key !in ['optimize', 'target', 'xcframework-target', 'font-backend', 'app-runtime', 'renderer',
			'flatpak', 'snap', 'sentry', 'simd', 'gtk-wayland', 'gtk-x11', 'i18n', 'version-string',
			'patch-rpath', 'pie', 'strip', 'emit-exe', 'emit-test-exe', 'emit-unicode-table-gen',
			'emit-bench', 'emit-helpgen', 'emit-docs', 'emit-terminfo', 'emit-termcap', 'emit-themes',
			'emit-webdata', 'emit-xcframework', 'emit-macos-app', 'wasm-shared'] {
			return error('unknown build option: ${key}')
		}
	}
	mode := match options['optimize'] {
		'', 'Debug' { Mode.debug }
		'ReleaseSafe' { Mode.release_safe }
		'ReleaseFast' { Mode.release_fast }
		'ReleaseSmall' { Mode.release_small }
		else { return error('invalid optimize mode') }
	}
	mut target := parse_target(options['target'])!
	if target.darwin() && target.minimum == '' {
		target = Target{...target, minimum: if target.os == 'macos' { '13.0' } else { '17.0' }}
	}
	mut x11 := false
	mut wayland := false
	gtk := run_process(root, ['pkg-config', '--variable=targets', 'gtk4']) or { os.Result{exit_code: 1} }
	if gtk.exit_code == 0 { x11 = gtk.output.contains('x11'); wayland = gtk.output.contains('wayland') }
	runtime := options['app-runtime'] or { if target.os in ['linux', 'freebsd'] { 'gtk' } else { 'none' } }
	if runtime !in ['gtk', 'none'] { return error('invalid app-runtime') }
	renderer := options['renderer'] or { if target.arch == 'wasm32' { 'webgl' } else if target.darwin() { 'metal' } else { 'opengl' } }
	if renderer !in ['metal', 'opengl', 'webgl'] { return error('invalid renderer') }
	font_backend := options['font-backend'] or { if target.arch == 'wasm32' { 'web_canvas' } else if target.darwin() { 'coretext' } else { 'fontconfig_freetype' } }
	if font_backend !in ['freetype', 'fontconfig_freetype', 'coretext', 'coretext_freetype',
		'coretext_harfbuzz', 'coretext_noshape', 'web_canvas'] { return error('invalid font-backend') }
	emit_bench := option_bool(options, 'emit-bench', false)!
	emit_test := option_bool(options, 'emit-test-exe', false)!
	emit_help := option_bool(options, 'emit-helpgen', false)!
	other := emit_bench || emit_test || emit_help
	pandoc := os.find_abs_path_of_executable('pandoc') or { '' }
	xcframework := option_bool(options, 'emit-xcframework', host_target().darwin() && target.os == 'macos' && runtime == 'none' && !other)!
	version := options['version-string'] or { detect_version(root, '1.3.0')! }
	semver.from(version)!
	xc_target := options['xcframework-target'] or { 'universal' }
	if xc_target !in ['native', 'universal'] { return error('invalid xcframework-target') }
	mut patch_rpath := ?string(none)
	if value := options['patch-rpath'] { patch_rpath = value }
	else if target.os == 'linux' && target.arch == host_target().arch && os.getenv_opt('IN_NIX_SHELL') != none {
		patch_rpath = os.getenv_opt('LD_LIBRARY_PATH')
	}
	for lib in ['freetype', 'harfbuzz', 'fontconfig', 'libxml2', 'libpng', 'zlib', 'oniguruma'] {
		if lib !in system_libraries { system_libraries[lib] = !target.darwin() && system_package }
	}
	for lib in ['glslang', 'spirv-cross', 'simdutf', 'highway'] {
		if lib !in system_libraries { system_libraries[lib] = false }
	}
	if 'gtk4-layer-shell' !in system_libraries { system_libraries['gtk4-layer-shell'] = true }
	return Config{
		root: os.abs_path(root), prefix: prefix, compiler: compiler, target: target, mode: mode,
		xcframework_target: xc_target, app_runtime: runtime, renderer: renderer, font_backend: font_backend,
		x11: option_bool(options, 'gtk-x11', x11)!, wayland: option_bool(options, 'gtk-wayland', wayland)!,
		sentry: option_bool(options, 'sentry', target.darwin())!, simd: option_bool(options, 'simd', !target.wasm())!,
		i18n: option_bool(options, 'i18n', target.darwin() || (target.os in ['linux', 'freebsd'] && target.abi == 'gnu'))!,
		wasm_shared: option_bool(options, 'wasm-shared', true)!, version: version,
		pie: option_bool(options, 'pie', system_package)!, strip: option_bool(options, 'strip', mode in [.release_fast, .release_small])!,
		patch_rpath: patch_rpath, flatpak: option_bool(options, 'flatpak', false)!, snap: option_bool(options, 'snap', false)!,
		emit_bench: emit_bench, emit_test_exe: emit_test, emit_helpgen: emit_help,
		emit_docs: option_bool(options, 'emit-docs', !other && (system_package || pandoc != ''))!,
		emit_exe: option_bool(options, 'emit-exe', true)!,
		emit_terminfo: option_bool(options, 'emit-terminfo', target.os == 'windows' || mode == .debug)!,
		emit_termcap: option_bool(options, 'emit-termcap', mode == .debug)!,
		emit_themes: option_bool(options, 'emit-themes', true)!, emit_webdata: option_bool(options, 'emit-webdata', false)!,
		emit_xcframework: xcframework, emit_macos_app: option_bool(options, 'emit-macos-app', xcframework)!,
		emit_unicode_table_gen: option_bool(options, 'emit-unicode-table-gen', false)!,
		system_package: system_package, system_libraries: system_libraries,
		steps: if steps.len == 0 { ['install'] } else { steps }, run_args: run_args, test_filters: filters,
	}
}

pub fn (cfg Config) retarget(target Target) Config { return Config{...cfg, target: target} }
pub fn (cfg Config) change_entrypoint(entrypoint Entrypoint) Config { return Config{...cfg, entrypoint: entrypoint} }

pub fn (cfg Config) options(artifact Artifact) ![]string {
	mut args := compile_options(cfg.root, cfg.mode, artifact, cfg.version)!
	for name, enabled in {'flatpak': cfg.flatpak, 'snap': cfg.snap, 'gtk_x11': cfg.x11,
		'gtk_wayland': cfg.wayland, 'sentry': cfg.sentry, 'wasm_shared': cfg.wasm_shared} {
		if enabled { args << ['-d', name] }
	}
	if !cfg.sentry { args << ['-d', 'no_sentry'] }
	if !cfg.simd { args << ['-d', 'no_simd'] }
	args << ['-d', if cfg.i18n { 'i18n' } else { 'no_i18n' }]
	args << ['-d', 'font_backend_${cfg.font_backend}', '-d', 'renderer_${cfg.renderer}',
		'-d', 'app_runtime_${cfg.app_runtime}', '-d', 'exe_entrypoint_${cfg.entrypoint}']
	if cfg.pie && artifact == .exe { args << ['-cflags', '-fPIE', '-ldflags', '-pie'] }
	if cfg.strip { args << ['-cflags', '-fomit-frame-pointer', '-cflags', '-fno-unwind-tables'] }
	else { args << ['-cflags', '-fno-omit-frame-pointer', '-cflags', '-funwind-tables'] }
	return args
}
