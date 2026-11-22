module main

// Linux entry point. Translated from ghostty's src/main_ghostty.zig main():
// after global state and CLI actions (handled elsewhere), it creates the
// core App, initializes the apprt runtime App with it, and runs the GUI
// event loop. On Linux the runtime is GTK.
import core
import apprt.gtk
import global_state
import source_startup

fn main() {
	$if !managed_native ? && !test {
		$compile_warn('Run `make` from the repository root to build Witty and its native dependencies.')
	}
	source_startup.prepare()
	mut state := global_state.get_state_mut()
	state.init() or {
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

	// Create our runtime app.
	mut app_runtime := gtk.App{}
	app_runtime.init(app) or {
		eprintln('failed to initialize runtime app: ${err}')
		exit(1)
	}
	defer {
		app_runtime.terminate()
	}

	// The reference GTK App adapter has no startQuitTimer declaration;
	// main_ghostty.zig's @hasDecl check is false for this runtime.

	// Run the GUI event loop.
	app_runtime.run() or {
		eprintln('runtime app failed: ${err}')
		exit(1)
	}
}
