module gtk

import apprt
import configpkg
import core
import input

fn test_application_accelerator_uses_reverse_keybind_lookup() {
	mut cfg := configpkg.Config{}
	cfg.keybind.parse_cli('ctrl+shift+a=new_split:left')!
	app := Application{
		config: cfg
	}
	action := input.ActionNewSplit{ value: .left }

	assert app.accelerator_for_action(action) or { '' } == '<Shift><Ctrl>a'
	assert app.accelerator_for_action(input.ActionNewSplit{ value: .right }) == none
}

fn test_application_accelerator_ignores_chained_binding() {
	mut cfg := configpkg.Config{}
	cfg.keybind.parse_cli('global:ctrl+b=ignore')!
	cfg.keybind.parse_cli('chain=new_window')!
	app := Application{
		config: cfg
	}

	assert app.accelerator_for_action(input.ActionIgnore{}) == none
	assert app.accelerator_for_action(input.ActionNewWindow{}) == none
}

fn test_application_quit_timer_without_delay_expires_immediately() {
	mut app := Application{
		config: configpkg.Config{
			quit_after_last_window_closed: true
		}
	}
	app.start_quit_timer()
	assert app.quit_timer is QuitTimerExpired
}

fn test_application_quit_timer_callback_marks_expired() {
	mut app := Application{
		quit_timer: QuitTimerActive{ source: 42 }
	}
	assert (app.quit_timer as QuitTimerActive).source == 42
	assert handle_quit_timer_expired(voidptr(&app)) == 0
	assert app.quit_timer is QuitTimerExpired
}

fn test_application_cgroup_mode_gate() {
	assert !cgroup_isolation_enabled(.never, g_application_default_flags)
	assert cgroup_isolation_enabled(.always, g_application_non_unique)
	assert cgroup_isolation_enabled(.single_instance, g_application_default_flags)
	assert !cgroup_isolation_enabled(.single_instance, g_application_non_unique)
}

fn test_application_get_config_returns_referenced_wrapper() {
	mut inner := configpkg.Config.default_config()
	defer {
		inner.deinit()
	}
	mut config := config_new(inner)
	mut app := Application{
		config_object: config
	}
	mut acquired := app.get_config()
	assert acquired == config

	// get_config owns an additional GObject reference, so releasing it must
	// leave the application's original reference valid.
	acquired.unref()
	assert config.get().background == inner.background
	config.unref()
}

fn test_application_config_load_failure_uses_diagnostic_default() {
	mut config := application_default_config_after_load_error(error('InvalidConfigPath'))
	mut default_config := configpkg.Config.default_config()
	defer {
		config.deinit()
		default_config.deinit()
	}
	assert config.diagnostics.len == 1
	assert config.diagnostics[0].format() ==
		'error loading user configuration: InvalidConfigPath'
	assert config.font_size == default_config.font_size
}

fn test_application_cgroup_startup_failure_becomes_config_diagnostic() {
	mut core_config := configpkg.Config.default_config()
	defer {
		core_config.deinit()
	}
	mut config_object := config_new(core_config)
	mut app := Application{
		config: core_config.clone()
		config_object: config_object
	}
	defer {
		app.config.deinit()
		config_object.unref()
	}

	app.record_cgroup_startup_error(error('DbusConnectionFailed'))
	expected := 'cgroup initialization failed: DbusConnectionFailed'
	assert app.config.diagnostics.len == 1
	assert app.config.diagnostics[0].format() == expected
	assert config_object.get().diagnostics.len == 1
	assert config_object.get().diagnostics[0].format() == expected
}

fn test_application_activate_queues_new_window() {
	mut core_app := &core.App{
		mailbox: core.MailboxQueue.create() or { panic(err) }
	}
	mut app := Application{
		core_app: core_app
	}
	assert core_app.mailbox.len() == 0
	app.activate()
	assert core_app.mailbox.len() == 1
}

fn test_application_action_table() {
	string_array_type := C.g_variant_type_new(c'as')
	u64_type := C.g_variant_type_new(c't')
	actions := application_action_descriptors(string_array_type, u64_type)
	assert actions.map(it.name) == [
		'new-window',
		'new-window-command',
		'open-config',
		'open-config-new-window',
		'present-surface',
		'quit',
		'reload-config',
	]
	assert isnil(actions[0].parameter_type)
	assert actions[1].parameter_type == string_array_type
	assert isnil(actions[3].parameter_type)
	assert actions[4].parameter_type == u64_type
	C.g_variant_type_free(string_array_type)
	C.g_variant_type_free(u64_type)
}

fn test_config_editor_launch_options_preserves_the_path_as_one_argument() {
	path := "/tmp/config with spaces and 'quotes'.witty"
	for i, setting in [['vim -u NONE', 'nano'], ['', 'nano'], ['', '']] {
		options := config_editor_launch_options(path, setting[0], setting[1])
		command := options.command or { panic('missing editor command') }
		expected := ['vim -u NONE', 'nano', 'vi'][i]
		assert (command as configpkg.DirectCmd).direct == [
			'/bin/sh',
			'-c',
			expected + ' "$1"',
			'witty-config-editor',
			path,
		]
	}
}

fn test_application_action_callbacks_queue_core_messages() {
	mut core_app := &core.App{
		mailbox: core.MailboxQueue.create() or { panic(err) }
	}
	mut app := Application{
		core_app: core_app
	}
	application_action_new_window_cb(unsafe { nil }, unsafe { nil }, voidptr(&app))
	app.action_open_config(unsafe { nil }, unsafe { nil })
	assert core_app.mailbox.len() == 2
	application_action_open_config_cb(unsafe { nil }, unsafe { nil }, voidptr(&app))
	assert core_app.mailbox.len() == 3
}

fn test_application_dispatches_core_runtime_actions() ! {
	mut app := Application{
		config: configpkg.Config{
			quit_after_last_window_closed: true
		}
	}
	app.runtime_bridge.actions << apprt.RuntimeAction{
		target: apprt.Target(apprt.AppTarget{})
		action: .quit_timer
		data: apprt.ActionValue(apprt.QuitTimer.start)
	}
	app.dispatch_runtime_actions()!
	assert app.runtime_bridge.actions.len == 0
	assert app.quit_timer is QuitTimerExpired

	app.runtime_bridge.actions << apprt.RuntimeAction{
		target: apprt.Target(apprt.AppTarget{})
		action: .quit_timer
		data: apprt.ActionValue(apprt.QuitTimer.stop)
	}
	app.dispatch_runtime_actions()!
	assert app.quit_timer is QuitTimerOff
}

fn test_application_sigusr2_callback_continues_without_instance() {
	assert application_sigusr2_cb(unsafe { nil }) == 1
}

fn test_application_quit_without_confirmation_stops_runloop() {
	mut app := Application{
		running: true
	}
	app.quit()
	assert !app.running
}
