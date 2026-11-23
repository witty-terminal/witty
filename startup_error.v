module main

// src/main_ghostty.zig global initialization error diagnostics. The translated
// Action parser carries these error variants as its existing message strings.
fn startup_error_message(err IError) string {
	if err.msg() == 'multiple actions' {
		return 'Error: multiple CLI actions specified. You must specify only one\naction starting with the `+` character.'
	}
	if err.msg().starts_with('invalid action:') {
		return "Error: unknown CLI action specified. CLI actions are specified with\nthe '+' character.\n\nAll valid CLI actions can be listed with `witty +help`"
	}
	return 'invalid CLI invocation err=${err}'
}
