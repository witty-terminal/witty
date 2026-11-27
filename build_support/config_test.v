module build_support

import os

fn test_config_source_defaults_and_cross_target_decisions() ! {
	root := os.dir(@FILE)
	linux := init_config(root, ['-Dtarget=x86_64-linux-gnu', '-Dversion-string=1.3.0'])!
	assert linux.app_runtime == 'ui2'
	assert linux.font_backend == 'fontconfig_freetype'
	assert linux.renderer == 'opengl'
	assert linux.i18n && linux.simd && !linux.sentry
	assert linux.emit_exe && linux.emit_themes && linux.emit_terminfo && linux.emit_termcap
	assert !linux.strip && !linux.pie && !linux.emit_xcframework
	mac := init_config(root, ['-Dtarget=aarch64-macos', '-Dversion-string=1.3.0', '-Doptimize=ReleaseSafe'])!
	assert mac.target.minimum == '13.0'
	assert mac.app_runtime == 'ui2' && mac.renderer == 'metal' && mac.font_backend == 'coretext'
	assert mac.emit_macos_app == host_target().darwin() && !mac.emit_xcframework
	assert mac.sentry && mac.i18n && !mac.strip && !mac.emit_terminfo && !mac.emit_termcap
	assert !mac.system_libraries['freetype'] && !mac.system_libraries['glslang']
	windows := init_config(root, ['-Dtarget=x86_64-windows-gnu', '-Dversion-string=1.3.0'])!
	assert windows.app_runtime == 'ui2' && windows.renderer == 'opengl' && windows.emit_exe
	assert !windows.emit_macos_app && !windows.emit_xcframework
	wasm := init_config(root, ['-Dtarget=wasm32-freestanding', '-Dversion-string=1.3.0'])!
	assert !wasm.simd && !wasm.i18n && !wasm.sentry
	assert wasm.renderer == 'webgl' && wasm.font_backend == 'web_canvas'
	assert wasm.wasm_target == 'browser' && wasm.wasm_shared
	ios := init_config(root, ['-Dtarget=aarch64-ios-simulator', '-Dversion-string=1.3.0'])!
	assert ios.target.minimum == '17.0' && ios.font_backend == 'coretext' && ios.renderer == 'metal'
}

fn test_config_source_artifacts_overrides_and_retargeting() ! {
	root := os.dir(@FILE)
	cfg := init_config(root, ['--system', '-Dtarget=x86_64-linux-gnu', '-Dversion-string=2.1.0-beta.1',
		'-Doptimize=ReleaseSmall', '-Demit-bench', '-Demit-docs=false',
		'-fsys=glslang', 'run', '--', '+version'])!
	assert cfg.strip && cfg.pie && !cfg.emit_docs && cfg.emit_bench
	assert cfg.system_libraries['glslang'] && cfg.system_libraries['freetype']
	assert cfg.steps == ['run'] && cfg.run_args == ['+version']
	retargeted := cfg.retarget(Target{arch: 'aarch64', os: 'ios', minimum: '17.0', abi: 'simulator', cpu: 'apple_a17'})
	assert retargeted.target.os == 'ios' && cfg.target.os == 'linux'
	assert retargeted.renderer == cfg.renderer && retargeted.version == cfg.version
	entry := retargeted.change_entrypoint(.webgen_config)
	assert entry.entrypoint == .webgen_config && retargeted.entrypoint == .ghostty
	options := entry.options(.lib)!
	assert 'release_small' in options && 'ghostty_lib' in options
	assert 'release_channel=tip' in options && 'app_version_string=2.1.0-beta.1' in options
}

fn test_config_rejects_invalid_build_options() {
	for args in [['-Dversion-string=broken'], ['-Dunknown=true'], ['-Dsimd=maybe'],
		['-Dfont-backend=missing'], ['-Dxcframework-target=missing'],
		['-Dtarget=x86_64-windows-gnu', '-Drenderer=metal'],
		['-Dtarget=aarch64-macos', '-Drenderer=opengl']] {
		if _ := init_config(os.dir(@FILE), args) { assert false } else { assert err.msg().len > 0 }
	}
}
