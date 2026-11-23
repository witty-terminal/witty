module native_metallib

fn test_metallib_build_preserves_source_sdk_and_minimum_version_mapping() {
	mac := create('/repo', Options{ os_tag: 'macos' })?
	assert mac.compile_args == ['-sdk', 'macosx', 'metal', '-o', '/repo/.witty-build/native/witty.ir',
		'-c', '/repo/renderer/shaders.metal', '-mmacos-version-min=10.14']
	assert mac.archive_args == ['-sdk', 'macosx', 'metallib', '-o',
		'/repo/.witty-build/native/witty.metallib', '/repo/.witty-build/native/witty.ir']
	simulator := create('/repo', Options{ os_tag: 'ios', simulator: true, minimum_version: '15.0', sources: ['custom.metal'] })?
	assert simulator.compile_args == ['-sdk', 'iphoneos', 'metal', '-o',
		'/repo/.witty-build/native/witty.ir', '-c', 'custom.metal', '-mios-simulator-version-min=15.0']
	device := create('/repo', Options{ os_tag: 'ios' })?
	assert device.compile_args.last() == '-mios-version-min=11.0'
	assert create('/repo', Options{ os_tag: 'linux' }) == none
}
