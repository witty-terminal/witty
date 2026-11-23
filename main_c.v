// Translated from Ghostty's main_c.zig
//
// This is the main file for the C API. The C API is used to embed Ghostty
// within other applications. Depending on the build settings some APIs
// may not be available (i.e. embedding into macOS exposes various Metal
// support).
//
// This currently isn't supported as a general purpose embedding API.
// This is currently used only to embed ghostty within a macOS app. However,
// it could be expanded to be general purpose in the future.

module main

import cli
import buildcfg
import core
import global_state
import internal_os
import log

// Install the runtime-neutral bridge used by the embedded/libwitty API.
// This keeps apprt free of a circular dependency while ensuring its C-facing
// CoreApp/CoreSurface wrappers use the canonical translated implementations.
fn init() {
	core.install_embedded_bridge()
}

// BuildMode mirrors the C enum ghostty_build_mode_e.
pub enum BuildMode as i32 {
	debug
	release_safe
	release_fast
	release_small
}

// Info corresponds to ghostty_info_s. Contains metadata about the
// Ghostty build such as version and build mode.
pub struct Info {
pub:
	mode        BuildMode
	version     &u8 = unsafe { nil }
	version_len uint
}

// GhosttyString corresponds to ghostty_string_s. A string type used
// across the C API boundary with explicit length and sentinel tracking.
pub struct GhosttyString {
pub:
	ptr      &u8 = unsafe { nil }
	len      uint
	sentinel bool
}

// empty returns an empty GhosttyString with null pointer.
pub fn GhosttyString.empty() GhosttyString {
	return GhosttyString{
		ptr:      unsafe { nil }
		len:      0
		sentinel: false
	}
}

// from_string creates a GhosttyString from a V string.
pub fn GhosttyString.from_string(s string) GhosttyString {
	if s.len == 0 {
		return GhosttyString.empty()
	}
	ptr := unsafe { malloc(s.len + 1) }
	unsafe {
		vmemcpy(ptr, s.str, s.len)
		(&u8(ptr))[s.len] = 0
	}
	return GhosttyString{
		ptr:      &u8(ptr)
		len:      uint(s.len)
		sentinel: true
	}
}

// from_slice creates a non-sentinel GhosttyString from a byte slice. V does
// not encode sentinel slices in the type system, so sentinel-backed strings
// use from_string while ordinary source slices use this entry point.
pub fn GhosttyString.from_slice(b []u8) GhosttyString {
	if b.len == 0 {
		return GhosttyString.empty()
	}
	ptr := unsafe { malloc(b.len) }
	unsafe {
		vmemcpy(ptr, b.data, b.len)
	}
	return GhosttyString{
		ptr:      &u8(ptr)
		len:      uint(b.len)
		sentinel: false
	}
}

pub fn (str GhosttyString) bytes() []u8 {
	if isnil(str.ptr) || str.len == 0 {
		return []u8{}
	}
	return unsafe { str.ptr.vbytes(int(str.len)) }
}

// deinit releases storage owned by this C-facing string.
pub fn (str GhosttyString) deinit() {
	if !isnil(str.ptr) {
		unsafe {
			free(str.ptr)
		}
	}
}

// ghostty_init initializes the process state using the embedding caller's argv.
// Darwin configuration deliberately uses NSProcessInfo.arguments, as in Ghostty.
pub fn ghostty_init(argc int, argv []string) int {
	internal_os.set_process_args(argv[..min_int(if argc < 0 { 0 } else { argc }, argv.len)])
	mut state := global_state.get_state_mut()
	args := if argc > 1 && argv.len > 1 {
		argv[1..min_int(argc, argv.len)]
	} else {
		[]string{}
	}
	state.init_args(args) or {
		log.error('failed to initialize ghostty error=${err}')
		return 1
	}
	return 0
}

// ghostty_cli_try_action runs the detected CLI action if one was set during
// global state init. If there is no action this returns; otherwise it runs
// the action and exits the process with its return code.
pub fn ghostty_cli_try_action() {
	state := global_state.get_state()
	action := state.action or { return }
	log.info('executing CLI action=${action}')
	code := run_cli_action(action, state.cli_args) or {
		log.error('CLI action failed error=${err}')
		exit(1)
	}
	exit(code)
}

pub fn run_cli_action(action global_state.Action, args []string) !int {
	return run_cli_action_main(action, args) or {
		if cli.is_action_help_requested(err) {
			help := cli.action_help_output(action.cli_name()) or { return err }
			print(help)
			return 0
		}
		return err
	}
}

fn run_cli_action_main(action global_state.Action, args []string) !int {
	return match action {
		.version { cli.run_version()! }
		.help { cli.run_help(action_args(args, action))! }
		.list_themes { cli.run_list_themes(action_args(args, action))! }
		.list_fonts { cli.run_list_fonts(action_args(args, action))! }
		.list_colors { cli.run_list_colors(action_args(args, action))! }
		.list_keybinds { cli.run_list_keybinds(action_args(args, action))! }
		.validate_config { cli.run_validate_config(action_args(args, action))! }
		.edit_config { cli.run_edit_config(action_args(args, action))! }
		.show_config { cli.run_show_config(action_args(args, action))! }
		.show_face { cli.run_show_face(action_args(args, action))! }
		.ssh_cache { cli.run_ssh_cache(action_args(args, action))! }
		.crash_report { cli.run_crash_report(action_args(args, action))! }
		.boo { cli.run_boo(action_args(args, action))! }
		.new_window { cli.run_new_window(action_args(args, action))! }
		.list_actions { cli.run_list_actions(action_args(args, action))! }
	}
}

fn action_args(args []string, action global_state.Action) []string {
	_ = action
	// Ghostty's ArgsIterator skips action tokens while iterating, rather than
	// deleting them up front, so CLI diagnostic indexes still count them.
	return args.clone()
}

// ghostty_info: Return metadata about Ghostty, such as version, build mode, etc.
pub fn ghostty_info() Info {
	return Info{
		mode:        match buildcfg.mode_string {
			'ReleaseSafe' { .release_safe }
			'ReleaseSmall' { .release_small }
			'ReleaseFast' { .release_fast }
			else { .debug }
		}
		version:     version_string.str
		version_len: uint(version_string.len)
	}
}

// ghostty_translate: Translate a string maintained by libwitty into the
// current application language. This will return the same string (same pointer)
// if no translation is found, so the pointer must be stable through
// the function call.
//
// This should only be used for singular strings maintained by Ghostty.
pub fn ghostty_translate(msgid string) string {
	return internal_os.translate(msgid)
}

// ghostty_string_free: Free a string allocated by Ghostty.
pub fn ghostty_string_free(str GhosttyString) {
	str.deinit()
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

// C ABI entrypoints. The V-facing helpers above remain convenient for tests
// and native callers while these wrappers preserve Ghostty's public symbols.
@[export: 'ghostty_init']
fn ghostty_init_export(argc uint, argv &&char) int {
	mut args := []string{cap: int(argc)}
	unsafe {
		for i in 0 .. int(argc) {
			value := argv[i]
			args << if isnil(value) { '' } else { cstring_to_vstring(value) }
		}
	}
	return ghostty_init(int(argc), args)
}

@[export: 'ghostty_cli_try_action']
fn ghostty_cli_try_action_export() {
	ghostty_cli_try_action()
}

@[export: 'ghostty_info']
fn ghostty_info_export() Info {
	return ghostty_info()
}

@[export: 'ghostty_translate']
fn ghostty_translate_export(msgid &char) &char {
	return internal_os.translate_c(msgid)
}

@[export: 'ghostty_string_free']
fn ghostty_string_free_export(str GhosttyString) {
	ghostty_string_free(str)
}
