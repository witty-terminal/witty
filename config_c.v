// Translated from Ghostty's src/config/CApi.zig.

module main

import configpkg
import input
import log
import cli_args
import internal_os

// ConfigDiagnostic mirrors ghostty_diagnostic_s.
pub struct ConfigDiagnostic {
pub:
	message &char = c''
}

// InputTrigger mirrors ghostty_input_trigger_s. The key field is the storage
// for the C union and mods uses the public C enum's integer representation.
pub struct InputTrigger {
pub:
	tag  int
	key  u32
	mods u32
}

// ghostty_config_new creates a configuration filled with initial defaults.
pub fn ghostty_config_new() ?&configpkg.Config {
	raw := unsafe { malloc(sizeof(configpkg.Config)) }
	if isnil(raw) {
		log.error('error allocating config err=OutOfMemory')
		return none
	}
	mut result := unsafe { &configpkg.Config(raw) }
	unsafe {
		*result = configpkg.Config.default_config()
	}
	return result
}

// ghostty_config_free releases a configuration returned by new or clone.
pub fn ghostty_config_free(mut config configpkg.Config) {
	if isnil(config) {
		return
	}
	config.deinit()
	unsafe {
		free(config)
	}
}

// ghostty_config_clone returns an independently owned deep clone.
pub fn ghostty_config_clone(config &configpkg.Config) ?&configpkg.Config {
	if isnil(config) {
		return none
	}
	raw := unsafe { malloc(sizeof(configpkg.Config)) }
	if isnil(raw) {
		log.error('error allocating config err=OutOfMemory')
		return none
	}
	mut result := unsafe { &configpkg.Config(raw) }
	unsafe {
		*result = config.clone()
	}
	return result
}

// ghostty_config_load_cli_args loads the process arguments, matching the C API
// whose signature intentionally takes no explicit argv.
pub fn ghostty_config_load_cli_args(mut config configpkg.Config) {
	$if linux || freebsd {
		config.load_cli_argv(internal_os.process_args()) or {
			log.error('error loading config err=${err}')
		}
	} $else {
		mut iter := cli_args.args_iterator()
		defer { iter.deinit() }
		mut args := []string{}
		for { args << iter.next() or { break } }
		config.load_cli_args(args) or {
			log.error('error loading config err=${err}')
		}
	}
}

pub fn ghostty_config_load_default_files(mut config configpkg.Config) {
	config.load_default_files() or {
		log.error('error loading config err=${err}')
	}
}

pub fn ghostty_config_load_file(mut config configpkg.Config, path string) {
	config.load_file(path) or {
		log.error('error loading config from file path=${path} err=${err}')
	}
}

pub fn ghostty_config_load_recursive_files(mut config configpkg.Config) {
	config.load_recursive_files() or {
		log.error('error loading config err=${err}')
	}
}

pub fn ghostty_config_finalize(mut config configpkg.Config) {
	config.finalize() or {
		log.error('error finalizing config err=${err}')
	}
}

pub fn ghostty_config_get(mut config configpkg.Config, ptr voidptr, key string) bool {
	return config.c_get(key, ptr)
}

pub fn ghostty_config_trigger(config &configpkg.Config, action_text string) InputTrigger {
	action := input.Action.parse(action_text) or {
		log.error('error finding trigger err=${err}')
		return InputTrigger{}
	}
	trigger := config.keybind.set.get_trigger(action) or { return InputTrigger{} }
	key := match trigger.key {
		input.TriggerKeyPhysical { u32(trigger.key.key) }
		input.TriggerKeyUnicode { trigger.key.codepoint }
		input.TriggerKeyCatchAll { u32(0) }
	}
	return InputTrigger{
		tag: int(trigger.key.tag())
		key: key
		mods: u32(trigger.mods.int())
	}
}

pub fn ghostty_config_diagnostics_count(config &configpkg.Config) u32 {
	if isnil(config) {
		return 0
	}
	return u32(config.diagnostics.len)
}

pub fn ghostty_config_get_diagnostic(mut config configpkg.Config, idx u32) ConfigDiagnostic {
	if isnil(config) || idx >= u32(config.diagnostics.len) {
		return ConfigDiagnostic{}
	}
	return ConfigDiagnostic{
		message: config.c_diagnostic_message(int(idx))
	}
}

pub fn ghostty_config_open_path() GhosttyString {
	path := configpkg.open_path() or {
		log.error('error opening config in editor err=${err}')
		return GhosttyString.empty()
	}
	return GhosttyString.from_slice(path.bytes())
}

@[export: 'ghostty_config_new']
fn ghostty_config_new_export() voidptr {
	result := ghostty_config_new() or { return unsafe { nil } }
	return voidptr(result)
}

@[export: 'ghostty_config_free']
fn ghostty_config_free_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut config := unsafe { &configpkg.Config(raw) }
	ghostty_config_free(mut config)
}

@[export: 'ghostty_config_clone']
fn ghostty_config_clone_export(raw voidptr) voidptr {
	if isnil(raw) {
		return unsafe { nil }
	}
	result := ghostty_config_clone(unsafe { &configpkg.Config(raw) }) or {
		return unsafe { nil }
	}
	return voidptr(result)
}

@[export: 'ghostty_config_load_cli_args']
fn ghostty_config_load_cli_args_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut config := unsafe { &configpkg.Config(raw) }
	ghostty_config_load_cli_args(mut config)
}

@[export: 'ghostty_config_load_default_files']
fn ghostty_config_load_default_files_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut config := unsafe { &configpkg.Config(raw) }
	ghostty_config_load_default_files(mut config)
}

@[export: 'ghostty_config_load_file']
fn ghostty_config_load_file_export(raw voidptr, path &char) {
	if isnil(raw) || isnil(path) {
		return
	}
	mut config := unsafe { &configpkg.Config(raw) }
	ghostty_config_load_file(mut config, unsafe { cstring_to_vstring(path) })
}

@[export: 'ghostty_config_load_recursive_files']
fn ghostty_config_load_recursive_files_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut config := unsafe { &configpkg.Config(raw) }
	ghostty_config_load_recursive_files(mut config)
}

@[export: 'ghostty_config_finalize']
fn ghostty_config_finalize_export(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut config := unsafe { &configpkg.Config(raw) }
	ghostty_config_finalize(mut config)
}

@[export: 'ghostty_config_get']
fn ghostty_config_get_export(raw voidptr, ptr voidptr, key_ptr &u8, key_len uint) bool {
	if isnil(raw) || isnil(key_ptr) {
		return false
	}
	mut config := unsafe { &configpkg.Config(raw) }
	key := unsafe { tos(key_ptr, int(key_len)) }
	return ghostty_config_get(mut config, ptr, key)
}

@[export: 'ghostty_config_trigger']
fn ghostty_config_trigger_export(raw voidptr, action_ptr &u8, action_len uint) InputTrigger {
	if isnil(raw) || isnil(action_ptr) {
		return InputTrigger{}
	}
	action := unsafe { tos(action_ptr, int(action_len)) }
	return ghostty_config_trigger(unsafe { &configpkg.Config(raw) }, action)
}

@[export: 'ghostty_config_diagnostics_count']
fn ghostty_config_diagnostics_count_export(raw voidptr) u32 {
	if isnil(raw) {
		return 0
	}
	return ghostty_config_diagnostics_count(unsafe { &configpkg.Config(raw) })
}

@[export: 'ghostty_config_get_diagnostic']
fn ghostty_config_get_diagnostic_export(raw voidptr, idx u32) ConfigDiagnostic {
	if isnil(raw) {
		return ConfigDiagnostic{}
	}
	mut config := unsafe { &configpkg.Config(raw) }
	return ghostty_config_get_diagnostic(mut config, idx)
}

@[export: 'ghostty_config_open_path']
fn ghostty_config_open_path_export() GhosttyString {
	return ghostty_config_open_path()
}
