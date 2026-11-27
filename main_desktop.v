module main

$if (linux || macos || windows) && !app_runtime_none ? {
	import apprt.ui2_runtime
	import core
	import global_state
	import internal_os
	import os
	import source_startup

	fn main() {
		$if !managed_native ?&& !test {
			$compile_warn('Run `make` from the repository root to build Witty and its native dependencies.')
		}
		source_startup.prepare_app()
		mut screenshot := ScreenshotLaunch{}
		mut args := if os.args.len > 1 { os.args[1..] } else { []string{} }
		// xdg-terminal-exec supplies a command in argv, including its own flags.
		if internal_os.parse_terminal_exec(os.args) == none {
			screenshot, args = parse_screenshot_launch(args) or {
				eprintln('Witty: ${err.msg()}')
				exit(1)
			}
			if screenshot.path != '' {
				mut argv := [os.args[0]]
				argv << args
				internal_os.set_process_args(argv)
			}
		}
		mut state := global_state.get_state_mut()
		state.init_args(args) or {
			eprintln(startup_error_message(err))
			exit(1)
		}
		defer { state.deinit() }
		ghostty_cli_try_action()

		// Create our app state.
		mut app := core.App.create() or {
			eprintln('failed to create app: ${err}')
			exit(1)
		}
		defer {
			app.destroy()
		}

		ui2_runtime.run(mut app, screenshot.path, screenshot.delay) or {
			eprintln('Witty: ${err}')
			exit(1)
		}
	}
}
