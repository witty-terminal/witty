module synthetic

import encoding.binary
import encoding.utf8
import rand

struct TestFixedWriter {
	capacity int
pub mut:
	data []u8
}

fn (mut writer TestFixedWriter) write(data []u8) !int {
	if data.len > writer.capacity - writer.data.len {
		return error('WriteFailed')
	}
	writer.data << data
	return data.len
}

fn test_synthetic_action_detection() {
	assert detect_action(['witty-gen', '+osc'])!.action? == .osc
	assert detect_action(['witty-gen', '--style=parser'])!.action == none
	if _ := detect_action(['witty-gen', '+osc', '+utf8']) {
		assert false, 'expected multiple actions to fail'
	} else {
		assert err.msg() == 'multiple actions'
	}
	if _ := detect_action(['witty-gen', '+unknown']) {
		assert false, 'expected invalid action to fail'
	} else {
		assert err.msg() == 'invalid action: unknown'
	}
}

fn test_ascii_cli_lifecycle_and_output() {
	mut rng := rand.new_default(seed_: [u32(0), 1])
	mut writer := TestFixedWriter{
		capacity: 1024
	}
	mut implementation := AsciiCli.create(AsciiOptions{})
	defer {
		implementation.destroy()
	}
	implementation.run(mut writer, rng)!
	assert writer.data.len == 1024
	for byte in writer.data {
		assert byte in ascii
	}
}

fn test_utf8_cli_lifecycle_and_output() {
	mut rng := rand.new_default(seed_: [u32(0), 1])
	mut writer := TestFixedWriter{
		capacity: 1024
	}
	mut implementation := Utf8Cli.create(Utf8Options{})
	defer {
		implementation.destroy()
	}
	implementation.run(mut writer, rng)!
	assert writer.data.len == 1024
	assert utf8.validate_str(writer.data.bytestr())
}

fn test_osc_cli_streaming_output() {
	mut rng := rand.new_default(seed_: [u32(0), 1])
	mut writer := TestFixedWriter{
		capacity: 1024
	}
	mut implementation := OscCli.create(OscOptions{
		p_valid: 1.0
		style:   .streaming
	})
	defer {
		implementation.destroy()
	}
	implementation.run(mut writer, rng)!
	assert writer.data.len > 3
	assert writer.data[0] == 0x1b
	assert writer.data[1] == `]`
	assert writer.data.contains(0x07)
}

fn test_osc_cli_parser_output_has_native_length_prefix() {
	mut rng := rand.new_default(seed_: [u32(0), 1])
	mut writer := TestFixedWriter{
		capacity: 2048
	}
	mut implementation := OscCli.create(OscOptions{
		p_valid: 1.0
		style:   .parser
	})
	defer {
		implementation.destroy()
	}
	implementation.run(mut writer, rng)!
	assert writer.data.len > int(sizeof(uint))
	length := if sizeof(uint) == 8 {
		uint(binary.little_endian_u64(writer.data[..8]))
	} else {
		uint(binary.little_endian_u32(writer.data[..4]))
	}
	assert length > 0
	assert int(sizeof(uint)) + int(length) <= writer.data.len
}

fn test_synthetic_main_action_retains_source_argument_variants() {
	assert Args(CliArgs{}) is CliArgs
	assert Args(StringArgs{}) is StringArgs
	mut rng := rand.new_default(seed_: [u32(0), 1])
	mut writer := TestFixedWriter{
		capacity: 1024
	}
	main_action_impl(.osc, StringArgs{
		value: '--p-valid=1 --style=streaming'
	}, mut writer, rng)!
	assert writer.data.len > 3
}

fn test_synthetic_main_action_preserves_parse_errors() {
	mut rng := rand.new_default(seed_: [u32(0), 1])
	mut writer := TestFixedWriter{
		capacity: 1024
	}
	if _ := main_action_impl(.osc, StringArgs{ value: '--style=invalid' }, mut writer, rng) {
		assert false, 'expected option parsing to fail'
	} else {
		assert err.msg() == 'invalid value'
	}
}
