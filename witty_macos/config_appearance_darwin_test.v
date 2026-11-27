@[has_globals]
module witty_macos

__global (
	appearance_fixture_calls int
	appearance_fixture_dark  bool
)

fn appearance_fixture_changed(dark bool) {
	appearance_fixture_calls++
	appearance_fixture_dark = dark
}

fn appearance_fixture_pump() {
	msg_void1(msg_id(get_class('NSRunLoop'), 'currentRunLoop'), 'runUntilDate:', msg_id_f64(get_class('NSDate'),
		'dateWithTimeIntervalSinceNow:', 0.05))
}

fn test_application_appearance_observes_initial_new_and_ends_native_lifetime() {
	app_init()
	msg_void(shared_app(), 'finishLaunching')
	original := msg_id(shared_app(), 'appearance')
	msg_void(original, 'retain')
	defer {
		stop_application_appearance_callback()
		msg_void1(shared_app(), 'setAppearance:', original)
		msg_void(original, 'release')
	}
	appearance_fixture_calls = 0
	set_application_appearance_callback(appearance_fixture_changed)
	assert appearance_fixture_calls == 1
	assert appearance_fixture_dark == native_application_is_dark()
	sync_native_application_appearance(NativeWindowConfig{ theme: 3 })
	appearance_fixture_pump()
	assert native_application_is_dark()
	assert appearance_fixture_dark
	assert appearance_fixture_calls >= 2
	sync_native_application_appearance(NativeWindowConfig{ theme: 2 })
	appearance_fixture_pump()
	assert !native_application_is_dark()
	assert !appearance_fixture_dark
	assert appearance_fixture_calls >= 3
	stop_application_appearance_callback()
	count := appearance_fixture_calls
	sync_native_application_appearance(NativeWindowConfig{ theme: 3 })
	appearance_fixture_pump()
	assert appearance_fixture_calls == count
}

fn test_application_appearance_source_auto_luminance_and_system_branches() {
	app_init()
	original := msg_id(shared_app(), 'appearance')
	msg_void(original, 'retain')
	defer {
		msg_void1(shared_app(), 'setAppearance:', original)
		msg_void(original, 'release')
	}
	sync_native_application_appearance(NativeWindowConfig{ theme: 0, background: 0xffffff })
	assert !native_application_is_dark()
	sync_native_application_appearance(NativeWindowConfig{ theme: 0, background: 0x000000 })
	assert native_application_is_dark()
	sync_native_application_appearance(NativeWindowConfig{ theme: 1 })
	assert is_nil(msg_id(shared_app(), 'appearance'))
}
