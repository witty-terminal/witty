module cli

import buildcfg
import cli_args
import global_state

// Unlike the other action option structs, HelpOptions deliberately has no
// help hook. Its --help flag is an ordinary parsed field.
pub struct HelpOptions {
pub mut:
	help bool
}

pub fn (opts HelpOptions) deinit() {
	_ = opts
}

// run_help translates cli/help.zig's action entry point.
pub fn run_help(args []string) !int {
	mut opts := HelpOptions{}
	cli_args.parse(mut opts, args)!
	print(help_output())
	return 0
}

// help_output is the translated cli/help.zig help text. The action list is
// generated from the same enum used by action detection.
pub fn help_output() string {
	command := buildcfg.cli_command
	mut output := 'Usage: ${command} [+action] [options]\n\n'
	output += 'Run the Ghostty terminal emulator or a specific helper action.\n\n'
	output += 'If no `+action` is specified, run the Ghostty terminal emulator.\n'
	output += 'All configuration keys are available as command line options.\n'
	output += 'To specify a configuration key, use the `--<key>=<value>` syntax\n'
	output += "where key and value are the same format you'd put into a configuration\n"
	output += 'file. For example, `--font-size=12` or `--font-family="Fira Code"`.\n\n'
	output += 'To see a list of all available configuration options, please see\n'
	output += 'the `src/config/Config.zig` file. A future update will allow seeing\n'
	output += 'the list of configuration options from the command line.\n\n'
	output += 'A special command line argument `-e <command>` can be used to run\n'
	output += 'the specific command inside the terminal emulator. For example,\n'
	output += '`${command} -e top` will run the `top` command inside the terminal.\n\n'
	output += 'On macOS, launching the terminal emulator from the CLI is not\n'
	output += 'supported and only actions are supported. Use `open -na Ghostty.app`\n'
	output += 'instead, or `open -na ghostty.app --args --foo=bar --baz=quz` to pass\n'
	output += 'arguments.\n\n'
	output += 'Available actions:\n\n'
	for action in global_state.actions() {
		output += '  +${action.cli_name()}\n'
	}
	output += '\nSpecify `+<action> --help` to see the help for a specific action,\n'
	output += 'where `<action>` is one of actions listed above.\n'
	return output
}
