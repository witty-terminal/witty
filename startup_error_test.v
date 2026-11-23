module main

fn test_source_startup_error_diagnostics() {
	assert startup_error_message(error('multiple actions')) == 'Error: multiple CLI actions specified. You must specify only one\naction starting with the `+` character.'
	assert startup_error_message(error('invalid action: missing')) == "Error: unknown CLI action specified. CLI actions are specified with\nthe '+' character.\n\nAll valid CLI actions can be listed with `witty +help`"
	assert startup_error_message(error('allocation failed')) == 'invalid CLI invocation err=allocation failed'
}
