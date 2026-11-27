module benchmark

import cli_args
import os
import osc
import simd
import terminal
import unicode

#flag -I @VMODROOT/benchmark

#include "benchmark_shims.h"

fn C.witty_benchmark_wcwidth(cp u32) int

fn C.witty_benchmark_do_not_optimize_u64(value u64)

fn C.witty_benchmark_do_not_optimize_ptr(value voidptr)

// This module translates src/benchmark from Ghostty commit
// 6c0e02d1138d5376e4ac2f5e311b225494514a97. The reusable Benchmark control
// layer is in benchmark_core.v. The C API uses its once mode; the action bodies
// below retain their setup, one step, and teardown in that order.

pub enum Action as u8 {
	codepoint_width
	grapheme_break
	screen_clone
	terminal_parser
	terminal_stream
	is_symbol
	osc_parser
}

pub enum CodepointWidthMode as u8 {
	noop
	wcwidth
	simd
	table
}

pub struct CodepointWidthOptions {
pub mut:
	mode CodepointWidthMode
	data ?string
}

pub enum GraphemeBreakMode as u8 {
	noop
	table
}

pub struct GraphemeBreakOptions {
pub mut:
	mode GraphemeBreakMode = .table
	data ?string
}

pub enum IsSymbolMode as u8 {
	uucode
	table
}

pub struct IsSymbolOptions {
pub mut:
	mode IsSymbolMode
	data ?string
}

pub enum ScreenCloneMode as u8 {
	noop
	clone
	render
}

pub struct ScreenCloneOptions {
pub mut:
	mode          ScreenCloneMode = .clone
	terminal_rows u16             = 80
	terminal_cols u16             = 120
	data          ?string
}

pub struct TerminalStreamOptions {
pub mut:
	terminal_rows u16 = 80
	terminal_cols u16 = 120
	data          ?string
}

pub struct TerminalParserOptions {
pub mut:
	data ?string
}

pub struct OscParserOptions {
pub mut:
	data ?string
}

// DataFile preserves the source's optional file result in a V value. `present`
// distinguishes no configured input from stdin, whose descriptor is zero.
pub struct DataFile {
mut:
	file    os.File
	present bool
}

// data_file returns no handle for none, stdin for "-", or an owned file for
// every other path, matching benchmark/options.zig dataFile.
pub fn data_file(path ?string) !DataFile {
	value := path or { return DataFile{} }
	if value == '-' {
		return DataFile{
			file:    os.stdin()
			present: true
		}
	}
	return DataFile{
		file:    os.open(value)!
		present: true
	}
}

pub fn (mut self DataFile) close() {
	if self.present {
		self.file.close()
	}
	self.present = false
}

pub fn (mut self DataFile) read(mut buf []u8) !int {
	if !self.present {
		return 0
	}
	return self.file.read(mut buf) or {
		if self.file.eof() {
			return 0
		}
		return err
	}
}

// parse_argument_string retains the benchmark module's public helper while the
// shared CLI translation owns the iterator implementation used here and by the
// synthetic generator CLI.
pub fn parse_argument_string(input string) []string {
	return cli_args.parse_argument_string(input)
}

pub fn parse_action(name string) ?Action {
	return match name {
		'codepoint-width' { .codepoint_width }
		'grapheme-break' { .grapheme_break }
		'screen-clone' { .screen_clone }
		'terminal-parser' { .terminal_parser }
		'terminal-stream' { .terminal_stream }
		'is-symbol' { .is_symbol }
		'osc-parser' { .osc_parser }
		else { none }
	}
}

// Args translates benchmark.cli.Args exactly: either read the current process
// arguments or parse one general argument string.
pub struct CliArgs {}

pub struct StringArgs {
pub:
	value string
}

pub type Args = CliArgs | StringArgs

// src/main_bench.zig and benchmark/cli.zig: detect one +action before
// dispatching the existing options/implementation/once-mode lifecycle.
pub fn main() ! {
	mut selected := ?Action(none)
	for argument in os.args {
		if !argument.starts_with('+') { continue
		 }
		if _ := selected { return error('MultipleActions') }
		selected = parse_action(argument[1..]) or {
			return error('InvalidAction')
		}
	}
	action := selected or { return error('NoAction') }
	main_action(action, CliArgs{})!
}

// run_cli parses the action options, constructs its implementation, and runs
// it once, matching benchmark.cli.mainAction as invoked by CApi.zig.
pub fn run_cli(action_name string, argument_string string) ! {
	action := parse_action(action_name) or { return error('unknown action=${action_name}') }
	main_action(action, StringArgs{
		value: argument_string
	})!
}

// main_action parses action-specific options, constructs the corresponding
// implementation, and runs its benchmark once. Mirrors benchmark.cli.mainAction.
pub fn main_action(action Action, args_source Args) ! {
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
			parse_argument_string(args_source.value)
		}
	}

	match action {
		.codepoint_width { run_codepoint_width(args)! }
		.grapheme_break { run_grapheme_break(args)! }
		.screen_clone { run_screen_clone(args)! }
		.terminal_parser { run_terminal_parser(args)! }
		.terminal_stream { run_terminal_stream(args)! }
		.is_symbol { run_is_symbol(args)! }
		.osc_parser { run_osc_parser(args)! }
	}
}

@[heap]
pub struct CodepointWidth {
pub:
	opts CodepointWidthOptions
mut:
	data DataFile
}

pub fn CodepointWidth.create(opts CodepointWidthOptions) &CodepointWidth {
	return &CodepointWidth{
		opts: opts
	}
}

pub fn (mut self CodepointWidth) destroy() {
	self.data.close()
}

pub fn (mut self CodepointWidth) benchmark() Benchmark {
	step_fn := match self.opts.mode {
		.noop { codepoint_width_step_noop }
		.wcwidth { codepoint_width_step_wcwidth }
		.simd { codepoint_width_step_simd }
		.table { codepoint_width_step_table }
	}

	return Benchmark.init(voidptr(self), VTable{
		step_fn:     step_fn
		setup_fn:    codepoint_width_setup
		teardown_fn: codepoint_width_teardown
	})
}

fn run_codepoint_width(args []string) ! {
	mut opts := CodepointWidthOptions{}
	cli_args.parse(mut opts, args)!
	mut implementation := CodepointWidth.create(opts)
	defer {
		implementation.destroy()
	}
	implementation.benchmark().run(RunModeOnce{})!
}

fn codepoint_width_setup(ptr voidptr) ! {
	mut self := unsafe { &CodepointWidth(ptr) }
	assert !self.data.present
	self.data = data_file(self.opts.data)!
}

fn codepoint_width_teardown(ptr voidptr) {
	mut self := unsafe { &CodepointWidth(ptr) }
	self.data.close()
}

fn codepoint_width_step_noop(ptr voidptr) ! {
	_ = ptr
}

fn codepoint_width_step_wcwidth(ptr voidptr) ! {
	$if windows {
		_ = ptr
		return error('wcwidth is unavailable on Windows')
	} $else {
		mut self := unsafe { &CodepointWidth(ptr) }
		if !self.data.present {
			return
		}

		mut decoder := terminal.UTF8Decoder{}
		mut buf := []u8{len: 4096}
		for {
			n := self.data.read(mut buf)!
			if n == 0 {
				break
			}
			for c in buf[..n] {
				result := decoder.next(c)
				assert result.consumed
				if cp := result.codepoint {
					C.witty_benchmark_do_not_optimize_u64(u64(C.witty_benchmark_wcwidth(cp)))
				}
			}
		}
	}
}

fn codepoint_width_step_table(ptr voidptr) ! {
	mut self := unsafe { &CodepointWidth(ptr) }
	if !self.data.present {
		return
	}

	mut decoder := terminal.UTF8Decoder{}
	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			break
		}
		for c in buf[..n] {
			result := decoder.next(c)
			assert result.consumed
			if cp := result.codepoint {
				value := if cp <= 0xff { u8(1) } else { unicode.get(cp).width() }
				C.witty_benchmark_do_not_optimize_u64(u64(value))
			}
		}
	}
}

fn codepoint_width_step_simd(ptr voidptr) ! {
	mut self := unsafe { &CodepointWidth(ptr) }
	if !self.data.present {
		return
	}

	mut decoder := terminal.UTF8Decoder{}
	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			break
		}
		for c in buf[..n] {
			result := decoder.next(c)
			assert result.consumed
			if cp := result.codepoint {
				C.witty_benchmark_do_not_optimize_u64(u64(simd.codepoint_width(cp)))
			}
		}
	}
}

@[heap]
pub struct GraphemeBreak {
pub:
	opts GraphemeBreakOptions
mut:
	data DataFile
}

pub fn GraphemeBreak.create(opts GraphemeBreakOptions) &GraphemeBreak {
	return &GraphemeBreak{
		opts: opts
	}
}

pub fn (mut self GraphemeBreak) destroy() {
	self.data.close()
}

pub fn (mut self GraphemeBreak) benchmark() Benchmark {
	step_fn := match self.opts.mode {
		.noop { grapheme_break_step_noop }
		.table { grapheme_break_step_table }
	}

	return Benchmark.init(voidptr(self), VTable{
		step_fn:     step_fn
		setup_fn:    grapheme_break_setup
		teardown_fn: grapheme_break_teardown
	})
}

fn run_grapheme_break(args []string) ! {
	mut opts := GraphemeBreakOptions{}
	cli_args.parse(mut opts, args)!
	mut implementation := GraphemeBreak.create(opts)
	defer {
		implementation.destroy()
	}
	implementation.benchmark().run(RunModeOnce{})!
}

fn grapheme_break_setup(ptr voidptr) ! {
	mut self := unsafe { &GraphemeBreak(ptr) }
	assert !self.data.present
	self.data = data_file(self.opts.data)!
}

fn grapheme_break_teardown(ptr voidptr) {
	mut self := unsafe { &GraphemeBreak(ptr) }
	self.data.close()
}

fn grapheme_break_step_noop(ptr voidptr) ! {
	mut self := unsafe { &GraphemeBreak(ptr) }
	if !self.data.present {
		return
	}
	mut decoder := terminal.UTF8Decoder{}
	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			return
		}
		for c in buf[..n] {
			decoder.next(c)
		}
	}
}

fn grapheme_break_step_table(ptr voidptr) ! {
	mut self := unsafe { &GraphemeBreak(ptr) }
	if !self.data.present {
		return
	}

	mut decoder := terminal.UTF8Decoder{}
	mut state := unicode.BreakState.default
	mut cp1 := u32(0)
	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			break
		}
		for c in buf[..n] {
			result := decoder.next(c)
			assert result.consumed
			if cp2 := result.codepoint {
				is_break := unicode.grapheme_break(cp1, cp2, &state)
				C.witty_benchmark_do_not_optimize_u64(u64(is_break))
				cp1 = cp2
			}
		}
	}
}

@[heap]
pub struct IsSymbol {
pub:
	opts IsSymbolOptions
mut:
	data DataFile
}

pub fn IsSymbol.create(opts IsSymbolOptions) &IsSymbol {
	return &IsSymbol{
		opts: opts
	}
}

pub fn (mut self IsSymbol) destroy() {
	self.data.close()
}

pub fn (mut self IsSymbol) benchmark() Benchmark {
	step_fn := match self.opts.mode {
		.uucode { is_symbol_step_uucode }
		.table { is_symbol_step_table }
	}

	return Benchmark.init(voidptr(self), VTable{
		step_fn:     step_fn
		setup_fn:    is_symbol_setup
		teardown_fn: is_symbol_teardown
	})
}

fn run_is_symbol(args []string) ! {
	mut opts := IsSymbolOptions{}
	cli_args.parse(mut opts, args)!
	mut implementation := IsSymbol.create(opts)
	defer {
		implementation.destroy()
	}
	implementation.benchmark().run(RunModeOnce{})!
}

fn is_symbol_setup(ptr voidptr) ! {
	mut self := unsafe { &IsSymbol(ptr) }
	assert !self.data.present
	self.data = data_file(self.opts.data)!
}

fn is_symbol_teardown(ptr voidptr) {
	mut self := unsafe { &IsSymbol(ptr) }
	self.data.close()
}

fn is_symbol_step_uucode(ptr voidptr) ! {
	mut self := unsafe { &IsSymbol(ptr) }
	if !self.data.present {
		return
	}

	mut decoder := terminal.UTF8Decoder{}
	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			break
		}
		for c in buf[..n] {
			result := decoder.next(c)
			assert result.consumed
			if cp := result.codepoint {
				C.witty_benchmark_do_not_optimize_u64(u64(unicode.is_symbol_uucode(cp)))
			}
		}
	}
}

fn is_symbol_step_table(ptr voidptr) ! {
	mut self := unsafe { &IsSymbol(ptr) }
	if !self.data.present {
		return
	}

	mut decoder := terminal.UTF8Decoder{}
	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			break
		}
		for c in buf[..n] {
			result := decoder.next(c)
			assert result.consumed
			if cp := result.codepoint {
				C.witty_benchmark_do_not_optimize_u64(u64(unicode.is_symbol(cp)))
			}
		}
	}
}

@[heap]
pub struct TerminalParser {
pub:
	opts TerminalParserOptions
mut:
	data DataFile
}

pub fn TerminalParser.create(opts TerminalParserOptions) &TerminalParser {
	return &TerminalParser{
		opts: opts
	}
}

pub fn (mut self TerminalParser) destroy() {
	self.data.close()
}

pub fn (mut self TerminalParser) benchmark() Benchmark {
	return Benchmark.init(voidptr(self), VTable{
		step_fn:     terminal_parser_step
		setup_fn:    terminal_parser_setup
		teardown_fn: terminal_parser_teardown
	})
}

fn run_terminal_parser(args []string) ! {
	mut opts := TerminalParserOptions{}
	cli_args.parse(mut opts, args)!
	mut implementation := TerminalParser.create(opts)
	defer {
		implementation.destroy()
	}
	implementation.benchmark().run(RunModeOnce{})!
}

fn terminal_parser_setup(ptr voidptr) ! {
	mut self := unsafe { &TerminalParser(ptr) }
	assert !self.data.present
	self.data = data_file(self.opts.data)!
}

fn terminal_parser_teardown(ptr voidptr) {
	mut self := unsafe { &TerminalParser(ptr) }
	self.data.close()
}

fn terminal_parser_step(ptr voidptr) ! {
	mut self := unsafe { &TerminalParser(ptr) }
	if !self.data.present {
		return
	}

	mut parser := terminal.Parser{}
	defer {
		parser.deinit()
	}
	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			break
		}
		for c in buf[..n] {
			actions := parser.next(c)
			C.witty_benchmark_do_not_optimize_ptr(&actions)
		}
	}
}

@[heap]
pub struct TerminalStream {
pub:
	opts TerminalStreamOptions
mut:
	terminal terminal.Terminal
	stream   terminal.Stream[TerminalStreamHandler]
	data     DataFile
}

pub fn TerminalStream.create(opts TerminalStreamOptions) !&TerminalStream {
	mut ptr := &TerminalStream{
		opts:     opts
		terminal: terminal.Terminal.init(terminal.Options{
			rows: opts.terminal_rows
			cols: opts.terminal_cols
		})!
	}
	// The source's stream holds a pointer to the handler stored beside it;
	// the V stream stores the handler value, which holds the same pointer.
	ptr.stream = terminal.Stream.init[TerminalStreamHandler](TerminalStreamHandler{
		t: &ptr.terminal
	})
	return ptr
}

pub fn (mut self TerminalStream) destroy() {
	self.data.close()
	self.terminal.deinit()
}

pub fn (mut self TerminalStream) benchmark() Benchmark {
	return Benchmark.init(voidptr(self), VTable{
		step_fn:     terminal_stream_step
		setup_fn:    terminal_stream_setup
		teardown_fn: terminal_stream_teardown
	})
}

fn run_terminal_stream(args []string) ! {
	mut opts := TerminalStreamOptions{}
	cli_args.parse(mut opts, args)!
	mut implementation := TerminalStream.create(opts)!
	defer {
		implementation.destroy()
	}
	implementation.benchmark().run(RunModeOnce{})!
}

fn terminal_stream_setup(ptr voidptr) ! {
	mut self := unsafe { &TerminalStream(ptr) }
	self.terminal.full_reset()
	assert !self.data.present
	self.data = data_file(self.opts.data)!
}

fn terminal_stream_teardown(ptr voidptr) {
	mut self := unsafe { &TerminalStream(ptr) }
	self.data.close()
}

fn terminal_stream_step(ptr voidptr) ! {
	mut self := unsafe { &TerminalStream(ptr) }
	if !self.data.present {
		return
	}

	mut buf := []u8{len: 4096}
	for {
		n := self.data.read(mut buf)!
		if n == 0 {
			break
		}
		self.stream.next_slice(buf[..n]) or {
			// error processing data file chunk
			return error('BenchmarkFailed')
		}
	}
}

// Implements the handler interface for the terminal.Stream.
// We should expand this to include more operations to make
// our benchmark more realistic.
struct TerminalStreamHandler {
mut:
	t &terminal.Terminal = unsafe { nil }
}

@[inline]
pub fn (mut self TerminalStreamHandler) vt_print(value terminal.ActionPrint) ! {
	self.t.print(value.cp)!
}

pub fn (mut self TerminalStreamHandler) vt(action terminal.ActionKey, value terminal.ActionValue) ! {
	match action {
		.print {
			if value is terminal.ActionPrint {
				self.vt_print(value)!
			}
		}
		else {}
	}
}

pub fn (mut self TerminalStreamHandler) deinit() {}

@[heap]
pub struct ScreenClone {
pub:
	opts ScreenCloneOptions
mut:
	terminal terminal.Terminal
}

pub fn ScreenClone.create(opts ScreenCloneOptions) !&ScreenClone {
	return &ScreenClone{
		opts:     opts
		terminal: terminal.Terminal.init(terminal.Options{
			rows: opts.terminal_rows
			cols: opts.terminal_cols
		})!
	}
}

pub fn (mut self ScreenClone) destroy() {
	self.terminal.deinit()
}

pub fn (mut self ScreenClone) benchmark() Benchmark {
	step_fn := match self.opts.mode {
		.noop { screen_clone_step_noop }
		.clone { screen_clone_step_clone }
		.render { screen_clone_step_render }
	}

	return Benchmark.init(voidptr(self), VTable{
		step_fn:     step_fn
		setup_fn:    screen_clone_setup
		teardown_fn: screen_clone_teardown
	})
}

fn run_screen_clone(args []string) ! {
	mut opts := ScreenCloneOptions{}
	cli_args.parse(mut opts, args)!
	mut implementation := ScreenClone.create(opts)!
	defer {
		implementation.destroy()
	}
	implementation.benchmark().run(RunModeOnce{})!
}

fn screen_clone_setup(ptr voidptr) ! {
	mut self := unsafe { &ScreenClone(ptr) }
	self.terminal.full_reset()

	mut setup_stream := self.terminal.vt_stream()
	setup_stream.next_slice('\x1b[48;2;20;40;60m'.bytes())!
	for _ in 0 .. int(self.terminal.rows) - 1 {
		setup_stream.next_slice('hello\r\n'.bytes())!
	}
	setup_stream.next_slice('hello'.bytes())!
	setup_stream.deinit()

	mut data := data_file(self.opts.data)!
	if data.present {
		mut stream := self.terminal.vt_stream()
		defer {
			stream.deinit()
		}
		mut buf := []u8{len: 4096}
		for {
			n := data.read(mut buf)!
			if n == 0 {
				break
			}
			stream.next_slice(buf[..n])!
		}
	}
}

fn screen_clone_teardown(ptr voidptr) {
	_ = ptr
}

fn screen_clone_step_noop(ptr voidptr) ! {
	self := unsafe { &ScreenClone(ptr) }
	for _ in 0 .. 1000 {
		screen := *self.terminal.screens.active
		C.witty_benchmark_do_not_optimize_ptr(&screen)
	}
}

fn screen_clone_step_clone(ptr voidptr) ! {
	self := unsafe { &ScreenClone(ptr) }
	for _ in 0 .. 1000 {
		copy := self.terminal.screens.active.clone(terminal.Point.new(.viewport, terminal.Coordinate{}),
			?terminal.Point(none))!
		C.witty_benchmark_do_not_optimize_ptr(&copy)
	}
}

fn screen_clone_step_render(ptr voidptr) ! {
	mut self := unsafe { &ScreenClone(ptr) }
	mut state := terminal.RenderState.empty()
	state.update(mut self.terminal)
	for _ in 0 .. 1000 {
		state.screen = .alternate
		state.update(mut self.terminal)
		C.witty_benchmark_do_not_optimize_ptr(&state)
	}
}

fn read_exact(mut data DataFile, mut buf []u8) !bool {
	mut offset := 0
	for offset < buf.len {
		n := data.read(mut buf[offset..])!
		if n == 0 {
			return false
		}
		offset += n
	}
	return true
}

@[heap]
pub struct OscParser {
pub:
	opts OscParserOptions
mut:
	data   DataFile
	parser osc.Parser
}

pub fn OscParser.create(opts OscParserOptions) &OscParser {
	return &OscParser{
		opts:   opts
		parser: osc.Parser.init(unsafe { nil })
	}
}

pub fn (mut self OscParser) destroy() {
	self.data.close()
	self.parser.deinit()
}

pub fn (mut self OscParser) benchmark() Benchmark {
	return Benchmark.init(voidptr(self), VTable{
		step_fn:     osc_parser_step
		setup_fn:    osc_parser_setup
		teardown_fn: osc_parser_teardown
	})
}

fn run_osc_parser(args []string) ! {
	mut opts := OscParserOptions{}
	cli_args.parse(mut opts, args)!
	mut implementation := OscParser.create(opts)
	defer {
		implementation.destroy()
	}
	implementation.benchmark().run(RunModeOnce{})!
}

fn osc_parser_setup(ptr voidptr) ! {
	mut self := unsafe { &OscParser(ptr) }
	assert !self.data.present
	self.data = data_file(self.opts.data)!
	self.parser.reset()
}

fn osc_parser_teardown(ptr voidptr) {
	mut self := unsafe { &OscParser(ptr) }
	self.data.close()
}

fn osc_parser_step(ptr voidptr) ! {
	mut self := unsafe { &OscParser(ptr) }
	if !self.data.present {
		return
	}

	mut length_bytes := []u8{len: int(sizeof(uint))}
	mut osc_buf := []u8{len: 4096}
	for {
		if !read_exact(mut self.data, mut length_bytes)! {
			return
		}
		mut length := uint(0)
		for index, value in length_bytes {
			length |= uint(value) << u32(index * 8)
		}
		if length > uint(osc_buf.len) {
			return error('OSC payload exceeds buffer')
		}
		if !read_exact(mut self.data, mut osc_buf[..int(length)])! {
			return
		}
		for value in osc_buf[..int(length)] {
			self.parser.next(value)
		}
		command := self.parser.end(0x07)
		if value := command {
			C.witty_benchmark_do_not_optimize_ptr(&value)
		}
		self.parser.reset()
	}
}
