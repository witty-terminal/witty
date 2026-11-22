module cli

import cli_args
import diagnostics

pub struct NewWindowOptions {
pub mut:
	class       ?string
	arguments   ?[]string @['cli_internal']
	diagnostics diagnostics.DiagnosticList
}

pub struct NewWindowResult {
pub:
	code   int
	errors string
}

// parse_manually_hook mirrors Options.parseManuallyHook. Once -e is seen every
// remaining argument is command input, including strings such as --help.
pub fn (mut opts NewWindowOptions) parse_manually_hook(arg string, iter &cli_args.SliceIterator) bool {
	if arg != '-e' {
		return true
	}
	mut arguments := []string{}
	mut remaining := unsafe { &cli_args.SliceIterator(iter) }
	for {
		arguments << remaining.next() or { break }
	}
	opts.arguments = arguments
	return false
}

pub fn (opts NewWindowOptions) deinit() {
	_ = opts
}

pub fn (opts NewWindowOptions) help() ! {
	_ = opts
	action_options_help()!
}

fn parse_new_window_options(args []string) !NewWindowOptions {
	mut opts := NewWindowOptions{}
	cli_args.parse(mut opts, args)!
	return opts
}

pub fn new_window_result(args []string) !NewWindowResult {
	opts := parse_new_window_options(args) or {
		if is_action_help_requested(err) {
			return err
		}
		return NewWindowResult{
			code:   1
			errors: 'Error parsing args: ${err}\n'
		}
	}
	mut errors := []string{}
	for diagnostic in opts.diagnostics.items() {
		if diagnostic.location is diagnostics.CliLocation && diagnostic.key == 'class' {
			errors << 'config error: ${diagnostic.format()}'
		}
	}
	if errors.len > 0 {
		return NewWindowResult{
			code:   1
			errors: errors.join('\n') + '\n'
		}
	}
	if arguments := opts.arguments {
		if arguments.len == 0 {
			return NewWindowResult{
				code:   1
				errors: 'The -e flag was specified on the command line, but no other arguments were found.\n'
			}
		}
	}

	performed := perform_new_window_ipc(opts) or {
		if err.msg() == 'IPCFailed' {
			// The platform IPC layer prints its more specific error itself.
			return NewWindowResult{
				code: 1
			}
		}
		return NewWindowResult{
			code:   1
			errors: 'Sending the IPC failed: ${err}'
		}
	}
	if performed {
		return NewWindowResult{}
	}
	return NewWindowResult{
		code:   1
		errors: '+new-window is not supported on this platform.\n'
	}
}

pub fn run_new_window(args []string) !int {
	result := new_window_result(args)!
	eprint(result.errors)
	return result.code
}
