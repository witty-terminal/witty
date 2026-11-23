module build_support

import os

// GhosttyLib.initMacOSUniversal and GhosttyXCFramework.init. Each retargeted
// output is copied before another compile reuses the compiler's artifact path.
fn (d Driver) xcframework_slice(target Target, name string) !string {
	selected := Driver{cfg: d.cfg.retarget(target)}
	deps := selected.build_native_dependencies(false)!
	library := selected.build_library(deps, true)!
	output := d.cache_path('xcframework', name, 'libwitty.a')
	os.mkdir_all(os.dir(output))!
	os.cp(library, output)!
	return output
}

pub fn (d Driver) build_xcframework(native_only bool) !string {
	return d.build_xcframework_slices(native_only, true)
}

// build_xcframework_slices optionally omits the iOS slices. The macOS app links
// only the macOS slice, so building it alone does not need them; V 0.5.2 also
// cannot compile iOS slices (its C output redeclares posix_spawn).
fn (d Driver) build_xcframework_slices(native_only bool, include_ios bool) !string {
	if !d.cfg.target.darwin() { return error('XCFramework requires a Darwin target') }
	mut libraries := []string{}
	macos_target := Target{arch: host_target().arch, os: 'macos', minimum: '13.0'}
	if native_only || d.cfg.xcframework_target == 'native' {
		libraries << d.xcframework_slice(macos_target, 'macos-native')!
	} else {
		arm := d.xcframework_slice(Target{...macos_target, arch: 'aarch64'}, 'macos-arm64')!
		x86 := d.xcframework_slice(Target{...macos_target, arch: 'x86_64'}, 'macos-x86_64')!
		universal := d.cache_path('xcframework', 'macos-universal', 'libwitty.a')
		os.mkdir_all(os.dir(universal))!
		checked_process(d.cfg.root, ['lipo', '-create', arm, x86, '-output', universal])!
		libraries << universal
		if include_ios {
			libraries << d.xcframework_slice(Target{arch: 'aarch64', os: 'ios', minimum: '17.0'}, 'ios-arm64')!
			// Preserve the source's Apple A17 simulator override.
			libraries << d.xcframework_slice(Target{arch: 'aarch64', os: 'ios', minimum: '17.0',
				abi: 'simulator', cpu: 'apple_a17'}, 'ios-simulator-arm64')!
		}
	}
	output := os.join_path(d.cfg.root, 'macos', 'WittyKit.xcframework')
	if os.exists(output) { os.rmdir_all(output)! }
	mut command := ['xcodebuild', '-create-xcframework']
	for library in libraries {
		command << ['-library', library, '-headers', os.join_path(d.cfg.root, 'include')]
	}
	command << ['-output', output]
	checked_process(d.cfg.root, command)!
	return output
}
