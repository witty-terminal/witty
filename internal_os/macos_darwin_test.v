module internal_os

fn test_macos_qos_constants() {
	assert u32(QosClass.user_interactive) == 0x21
	assert u32(QosClass.user_initiated) == 0x19
	assert u32(QosClass.default_) == 0x15
	assert u32(QosClass.utility) == 0x11
	assert u32(QosClass.background) == 0x09
	assert u32(QosClass.unspecified) == 0x00
}

fn test_macos_foundation_directories() {
	assert is_at_least_version(10, 0, 0)
	cache := cache_dir('test')!
	assert cache.contains('Caches')
	assert cache.contains('com.alexander.witty/test')
	app_support := app_support_dir('config.witty')!
	assert app_support.contains('Application Support')
	assert app_support.contains('com.alexander.witty/config.witty')
}

fn test_cf_release_message_retains_release_arm() {
	message := CFReleaseMessage{
		release: CFReleaseMessageRelease{
			refs: [voidptr(1), voidptr(2)]
		}
	}
	assert message.release.refs == [voidptr(1), voidptr(2)]
}
