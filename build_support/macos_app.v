module build_support

import json2
import os

fn (d Driver) macos_configuration() string {
	return if d.cfg.mode == .debug { 'Debug' } else { 'ReleaseLocal' }
}

// Xcode's generated plist settings are pinned project data. The original
// hand-authored plist, including Services, document types and Sparkle keys,
// stays intact; only Xcode substitutions and compiler-generated keys are added.
pub fn (d Driver) write_macos_plist(output string) ! {
	configuration := d.macos_configuration()
	asset_root := os.join_path(d.cfg.root, 'build_assets', 'macos')
	all_settings := json2.decode[map[string]map[string]string](
		os.read_file(os.join_path(asset_root, 'project-plist-settings.json'))!)!
	settings := all_settings[configuration].clone()
	text := os.read_file(os.join_path(asset_root, 'Witty-Info.plist'))!
	os.mkdir_all(os.dir(output))!
	os.write_file(output, text.replace('\x24(INFOPLIST_KEY_CFBundleDisplayName)', settings['CFBundleDisplayName']))!
	mut generated := settings.clone()
	generated['CFBundleIdentifier'] = settings['PRODUCT_BUNDLE_IDENTIFIER']
	generated['CFBundleShortVersionString'] = settings['MARKETING_VERSION']
	generated['CFBundleVersion'] = settings['CURRENT_PROJECT_VERSION']
	generated['CFBundleExecutable'] = settings['EXECUTABLE_NAME']
	generated['CFBundleName'] = 'Witty'
	generated['CFBundlePackageType'] = 'APPL'
	generated['CFBundleInfoDictionaryVersion'] = '6.0'
	generated['LSMinimumSystemVersion'] = '13.0'
	for key, value in generated {
		if key in ['PRODUCT_BUNDLE_IDENTIFIER', 'MARKETING_VERSION', 'CURRENT_PROJECT_VERSION', 'EXECUTABLE_NAME'] {
			continue
		}
		// AppKit's V translation builds its menu programmatically. Swift/Xcode's
		// MainMenu nib selection has no compiled nib in the translated app.
		if key == 'NSMainNibFile' { continue }
		checked_process(d.cfg.root, ['plutil', '-insert', key, '-string', value, output])!
	}
}

// Compiler adaptation of GhosttyXcodebuild: compile the translated V host,
// then perform the source project's asset compilation, bundle copy and signing
// operations. No Swift implementation is linked into the translated host.
pub fn (d Driver) build_macos_app(native_only bool) !string {
	return d.build_macos_app_with_framework(native_only, false)
}

fn (d Driver) build_macos_app_with_framework(native_only bool, framework_ready bool) !string {
	if d.cfg.target.os != 'macos' { return error('macOS app requires a macOS target') }
	if d.cfg.app_runtime == 'none' && !framework_ready {
		d.build_xcframework_slices(native_only, false)!
	}
	d.install_resources()!
	d.install_locales()!
	// Xcodebuild always depends on the source placeholder, even when docs
	// are emitted separately by the installation graph.
	d.install_text('share/man/.placeholder', 'emit-docs not true so no man pages')!
	configuration := d.macos_configuration()
	app := os.join_path(d.cfg.root, 'witty_macos', 'build', configuration, 'Witty.app')
	contents := os.join_path(app, 'Contents')
	if os.exists(app) { os.rmdir_all(app)! }
	for directory in ['MacOS', 'Resources', 'Frameworks'] { os.mkdir_all(os.join_path(contents, directory))! }
	mut executable_slices := []string{}
	architectures := if native_only || d.cfg.xcframework_target == 'native' { [host_target().arch] } else { ['aarch64', 'x86_64'] }
	for architecture in architectures {
		selected := Driver{cfg: d.cfg.retarget(Target{arch: architecture, os: 'macos', minimum: '13.0'})}
		deps := selected.build_native_dependencies(false)!
		executable := selected.build_executable(deps)!
		copy := d.cache_path('macos', architecture, 'witty')
		os.mkdir_all(os.dir(copy))!
		os.cp(executable, copy)!
		executable_slices << copy
	}
	binary := os.join_path(contents, 'MacOS', 'witty')
	if executable_slices.len == 1 { os.cp(executable_slices[0], binary)! }
	else {
		mut command := ['lipo', '-create']
		command << executable_slices
		command << ['-output', binary]
		checked_process(d.cfg.root, command)!
	}
	info := os.join_path(contents, 'Info.plist')
	d.write_macos_plist(info)!
	asset_root := os.join_path(d.cfg.root, 'build_assets', 'macos')
	mut environment := map[string]string{}
	if path := os.getenv_opt('PATH') { environment['PATH'] = path }
	// Preserve Xcodebuild's empty external environment (PATH alone survives).
	checked_process_env(d.cfg.root, ['xcrun', 'actool', '--compile', os.join_path(contents, 'Resources'),
		'--platform', 'macosx', '--minimum-deployment-target', '13.0',
		'--accent-color', 'AccentColor', '--output-partial-info-plist', d.cache_path('macos', 'assets.plist'),
		os.join_path(asset_root, 'Assets.xcassets')], environment, true)!
	asset_plist := d.cache_path('macos', 'assets.plist')
	checked_process(d.cfg.root, ['/usr/libexec/PlistBuddy', '-c', 'Merge ' + asset_plist, info])!
	os.cp(os.join_path(d.cfg.root, 'Witty.app', 'Contents', 'Resources', 'Witty.icns'),
		os.join_path(contents, 'Resources', 'Witty.icns'))!
	for resource in ['bat', 'fish', 'witty', 'locale', 'man', 'nvim', 'terminfo', 'vim', 'zsh', 'bash-completion'] {
		path := os.join_path(d.cfg.prefix, 'share', resource)
		if os.exists(path) { checked_process(d.cfg.root, ['cp', '-R', path, os.join_path(contents, 'Resources')])! }
	}
	sparkle := d.build_sparkle()!
	checked_process(d.cfg.root, ['cp', '-R', sparkle, os.join_path(contents, 'Frameworks')])!
	checked_process(d.cfg.root, ['codesign', '--force', '--deep', '--sign', '-', '--options', 'runtime',
		'--entitlements', os.join_path(asset_root, 'Witty${configuration}.entitlements'), app])!
	checked_process(d.cfg.root, ['dsymutil', binary, '-o', app + '.dSYM'])!
	return app
}

pub fn (d Driver) run_macos_app() ! {
	app := d.build_macos_app(true)!
	checked_process(d.cfg.root, ['/usr/libexec/PlistBuddy', '-c', 'Add :NSQuitAlwaysKeepsWindows bool false',
		os.join_path(app, 'Contents', 'Info.plist')])!
	mut args := [os.join_path(app, 'Contents', 'MacOS', 'witty')]
	args << d.cfg.run_args
	run_foreground(d.cfg.root, args, {'GHOSTTY_LOG': 'stderr,macos', 'GHOSTTY_MAC_LAUNCH_SOURCE': 'zig_run'})!
}
