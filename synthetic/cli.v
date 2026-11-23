module synthetic

import cli_args
import io
import os
import rand
import time

// Action is the set of generators exposed by witty-gen.
pub enum Action as u8 {
	ascii
	osc
	utf8
}

// The source union has a process-argument tag and a general string iterator.
pub struct CliArgs {}

pub struct StringArgs {
pub:
	value string
}

pub type Args = CliArgs | StringArgs

pub struct DetectActionResult {
pub:
	action ?Action
}

pub struct AsciiOptions {}

pub enum OscStyle as u8 {
	streaming
	parser
}

pub struct OscOptions {
pub mut:
	p_valid f64      = 0.5
	style   OscStyle = .streaming
}

pub struct Utf8Options {}

@[heap]
pub struct AsciiCli {}

@[heap]
pub struct OscCli {
pub:
	opts OscOptions
}

@[heap]
pub struct Utf8Cli {}

fn check_ascii_alphabet(byte u8) bool {
	return byte >= 0x21 && byte <= 0x7e
}

// ascii is every printable ASCII byte except space, matching Ascii.zig.
pub const ascii = generate_alphabet(check_ascii_alphabet)

// main is the witty-gen process entry point.
pub fn main() ! {
	detected := detect_action(os.args)!
	action := detected.action or { return error('NoAction') }
	main_action(action, CliArgs{})!
}

// detect_action is cli.action.detectArgs specialized to this action enum.
pub fn detect_action(args []string) !DetectActionResult {
	mut pending := ?Action(none)
	for arg in args {
		if !arg.starts_with('+') {
			continue
		}
		if _ := pending {
			return error('multiple actions')
		}
		mut matched := Action.ascii
		mut found := false
		$for enum_value in Action.values {
			if enum_value.name == arg[1..] {
				matched = enum_value.value
				found = true
			}
		}
		if !found {
			return error('invalid action: ${arg[1..]}')
		}
		pending = matched
	}
	return DetectActionResult{
		action: pending
	}
}

// create and destroy mirror the source implementation lifecycle. V's GC owns
// the allocations, so destroy has no allocator work to perform.
pub fn AsciiCli.create(_ AsciiOptions) &AsciiCli {
	return &AsciiCli{}
}

pub fn (mut self AsciiCli) destroy() {
	_ = self
}

pub fn OscCli.create(opts OscOptions) &OscCli {
	return &OscCli{
		opts: opts
	}
}

pub fn (mut self OscCli) destroy() {
	_ = self
}

pub fn Utf8Cli.create(_ Utf8Options) &Utf8Cli {
	return &Utf8Cli{}
}

pub fn (mut self Utf8Cli) destroy() {
	_ = self
}

// run emits fixed 1024-byte chunks until stdout closes or a fixed writer is
// full. Generator errors still propagate.
pub fn (mut self AsciiCli) run(mut writer io.Writer, rng &rand.PRNG) ! {
	_ = self
	mut generator := Bytes.init(rng)
	generator.alphabet = unsafe { ascii }
	generator.min_len = 1024
	generator.max_len = 1024
	for {
		generator.write_writer(mut writer) or {
			if output_closed(err) {
				return
			}
			return err
		}
	}
}

// run emits complete OSC strings for streaming, or native-usize little-endian
// lengths followed by the unwrapped payload for the parser harness.
pub fn (mut self OscCli) run(mut writer io.Writer, rng &rand.PRNG) ! {
	mut generator := Osc.init(rng)
	generator.p_valid = self.opts.p_valid
	for {
		mut fixed := FixedWriter{
			buffer: []u8{len: 1024}
		}
		generator.next_writer(mut fixed, 1024)!
		data := fixed.buffer[..fixed.end]
		match self.opts.style {
			.streaming {
				write_all(mut writer, data) or {
					if output_closed(err) {
						return
					}
					return err
				}
			}
			.parser {
				mut length := []u8{len: int(sizeof(uint))}
				payload_len := uint(data.len - 3)
				for i in 0 .. length.len {
					length[i] = u8(payload_len >> (i * 8))
				}
				write_all(mut writer, length) or {
					if output_closed(err) {
						return
					}
					return err
				}
				write_all(mut writer, data[2..data.len - 1]) or {
					if output_closed(err) {
						return
					}
					return err
				}
			}
		}
	}
}

// run emits valid UTF-8 chunks of at most 1024 bytes until output closes.
pub fn (mut self Utf8Cli) run(mut writer io.Writer, rng &rand.PRNG) ! {
	_ = self
	mut generator := Utf8.init(rng)
	for {
		generator.next_writer(mut writer, 1024) or {
			if output_closed(err) {
				return
			}
			return err
		}
	}
}

// main_action is the source public dispatcher. It parses before constructing
// the selected implementation, seeds the PRNG, streams to stdout, and flushes.
pub fn main_action(action Action, args_source Args) ! {
	mut stdout := FileWriter{}
	main_action_impl(action, args_source, mut stdout, unsafe { nil })!
	stdout.flush() or { return }
}

fn main_action_impl(action Action, args_source Args, mut writer io.Writer, rng &rand.PRNG) ! {
	args := match args_source {
		CliArgs {
			mut iter := cli_args.args_iterator()
			defer {
				iter.deinit()
			}
			mut values := []string{}
			for {
				values << (iter.next() or { break })
			}
			values
		}
		StringArgs {
			cli_args.parse_argument_string(args_source.value)
		}
	}

	match action {
		.ascii {
			mut opts := AsciiOptions{}
			cli_args.parse(mut opts, args)!
			mut implementation := AsciiCli.create(opts)
			defer {
				implementation.destroy()
			}
			selected_rng := if isnil(rng) {
				new_source_random(u64(time.now().unix_nano()))
			} else {
				rng
			}
			implementation.run(mut writer, selected_rng)!
		}
		.osc {
			mut opts := OscOptions{}
			cli_args.parse(mut opts, args)!
			mut implementation := OscCli.create(opts)
			defer {
				implementation.destroy()
			}
			selected_rng := if isnil(rng) {
				new_source_random(u64(time.now().unix_nano()))
			} else {
				rng
			}
			implementation.run(mut writer, selected_rng)!
		}
		.utf8 {
			mut opts := Utf8Options{}
			cli_args.parse(mut opts, args)!
			mut implementation := Utf8Cli.create(opts)
			defer {
				implementation.destroy()
			}
			selected_rng := if isnil(rng) {
				new_source_random(u64(time.now().unix_nano()))
			} else {
				rng
			}
			implementation.run(mut writer, selected_rng)!
		}
	}
}

fn write_all(mut writer io.Writer, data []u8) ! {
	source_write_all(mut writer, data)!
}

fn output_closed(err IError) bool {
	message := err.msg().to_lower()
	return message in ['writefailed', 'brokenpipe', 'broken pipe', '0 bytes written']
}
