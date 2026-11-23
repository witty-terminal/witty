module crash

import buildcfg
import build_meta
import internal_os
import log
import os
import source_file_writer
import font

const sentry_enabled = $if no_sentry ? { false } $else $if windows { false } $else $if sentry ? { true } $else $if macos || ios { true } $else { false }

#flag -I@VMODROOT/thirdparty/sentry/include
#include "sentry.h"

$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
	// Managed builds link the per-target archives from the native graph.
	$if !managed_native ? {
		#flag @VMODROOT/.witty-build/native/libsentry.a
		#flag @VMODROOT/.witty-build/native/libbreakpad.a
	}
	#flag darwin -lc++
	#flag darwin -lobjc
	#flag darwin -framework Foundation
	#flag linux -lstdc++
}

@[typedef]
union C.sentry_value_t {
	_bits   u64
	_double f64
}

@[typedef]
struct C.sentry_uuid_t {
	bytes [16]char
}

fn C.sentry_options_new() voidptr
fn C.sentry_options_free(options voidptr)
fn C.sentry_options_set_release_n(options voidptr, release &char, length uint)
fn C.sentry_transport_new(callback fn (voidptr, voidptr)) voidptr
fn C.sentry_options_set_transport(options voidptr, transport voidptr)
fn C.sentry_options_set_before_send(options voidptr, callback fn (C.sentry_value_t, voidptr, voidptr) C.sentry_value_t, userdata voidptr)
fn C.sentry_options_set_database_path_n(options voidptr, path &char, length uint)
fn C.sentry_options_set_debug(options voidptr, debug int)
fn C.sentry_init(options voidptr) int
fn C.sentry_close() int
fn C.sentry_set_tag_n(key &char, key_len uint, value &char, value_len uint)
fn C.sentry_value_new_object() C.sentry_value_t
fn C.sentry_value_new_string_n(data &char, length uint) C.sentry_value_t
fn C.sentry_value_new_int32(value i32) C.sentry_value_t
fn C.sentry_value_get_by_key_n(value C.sentry_value_t, key &char, length uint) C.sentry_value_t
fn C.sentry_value_set_by_key_n(value C.sentry_value_t, key &char, length uint, item C.sentry_value_t) int
fn C.sentry_value_is_null(value C.sentry_value_t) int
fn C.sentry_value_decref(value C.sentry_value_t)
fn C.sentry_envelope_serialize(envelope voidptr, length &uint) &char
fn C.sentry_envelope_free(envelope voidptr)
fn C.sentry_free(data voidptr)
fn C.sentry_uuid_new_v4() C.sentry_uuid_t
fn C.sentry_uuid_as_string(uuid &C.sentry_uuid_t, out &char)

const selected_runtime_name = $if app_runtime_none ? { 'none' } $else $if app_runtime_gtk ? { 'gtk' } $else $if linux || freebsd { 'gtk' } $else { 'none' }
const selected_renderer_name = $if renderer_opengl ? { 'opengl' } $else $if renderer_metal ? { 'metal' } $else $if renderer_webgl ? { 'webgl' } $else $if macos || ios { 'metal' } $else $if wasm32 { 'webgl' } $else { 'opengl' }

pub struct BuildInfo {
pub:
	release      string = build_meta.version_string
	mode         string = buildcfg.mode_string
	app_runtime  string = selected_runtime_name
	font_backend string = font.Backend.selected_().str()
	renderer     string = selected_renderer_name
}

pub struct Dimensions {
pub:
	screen_width  u32
	screen_height u32
	grid_columns  u32
	grid_rows     u32
	cell_width    u32
	cell_height   u32
}

struct SentryState {
mut:
	init_thread       ?thread
	info              BuildInfo
	dimensions_reader fn (voidptr) Dimensions = unsafe { nil }
}

const sentry_state = &SentryState{}

fn sentry_state_mut() &SentryState { return unsafe { &SentryState(sentry_state) } }

// Cycle-breaking projection: the crash callback still reads live Surface data
// at the instant of capture, including the source's intentionally unlocked read.
pub fn set_dimensions_reader(reader fn (voidptr) Dimensions) {
	mut state := sentry_state_mut()
	if state.dimensions_reader == unsafe { nil } {
		state.dimensions_reader = reader
	} else {
		assert state.dimensions_reader == reader
	}
}

pub fn enabled() bool { return sentry_enabled }

pub fn initialize_with_info(info BuildInfo) ! {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		mut state := sentry_state_mut()
		assert state.init_thread == none
		state.info = info
		state.init_thread = spawn sentry_init_thread()
	}
}

fn sentry_init_thread() {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		$if macos || ios {
			internal_os.set_thread_name('sentry-init')
		}
		sentry_init_thread_internal() or { panic(err) }
	}
}

fn sentry_init_thread_internal() ! {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		transport := C.sentry_transport_new(sentry_transport_send)
		assert !isnil(transport)
		// Source intentionally does not free an unused transport on initialization failure.
		opts := C.sentry_options_new()
		mut initialized := false
		defer { if !initialized { C.sentry_options_free(opts) } }
		info := sentry_state.info
		C.sentry_options_set_release_n(opts, &char(info.release.str), uint(info.release.len))
		C.sentry_options_set_transport(opts, transport)
		C.sentry_options_set_before_send(opts, sentry_before_send, unsafe { nil })
		mut cache := ''
		$if macos {
			if os.getenv_opt('XDG_CACHE_HOME') == none { cache = internal_os.cache_dir('sentry')! }
		}
		if cache.len == 0 {
			cache = internal_os.cache(internal_os.Options{ subdir: 'witty/sentry' })!
		}
		C.sentry_options_set_database_path_n(opts, &char(cache.str), uint(cache.len))
		if buildcfg.slow_runtime_safety { C.sentry_options_set_debug(opts, 1) }
		if C.sentry_init(opts) != 0 { return error('SentryInitFailed') }
		initialized = true
		for key, value in {
			'build-mode':   info.mode
			'app-runtime':  info.app_runtime
			'font-backend': info.font_backend
			'renderer':     info.renderer
		} {
			C.sentry_set_tag_n(&char(key.str), uint(key.len), &char(value.str), uint(value.len))
		}
		log.debug('sentry initialized database=${cache}')
	}
}

fn sentry_shutdown() {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		if worker := sentry_state.init_thread {
			worker.wait()
			_ = C.sentry_close()
		}
	}
}

fn set_value(object C.sentry_value_t, key string, value C.sentry_value_t) {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		_ = C.sentry_value_set_by_key_n(object, &char(key.str), uint(key.len), value)
	}
}

fn object_value(event C.sentry_value_t, key string) C.sentry_value_t {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		value := C.sentry_value_get_by_key_n(event, &char(key.str), uint(key.len))
		if C.sentry_value_is_null(value) == 0 { return value }
		object := C.sentry_value_new_object()
		set_value(event, key, object)
		return object
	} $else {
		panic('Sentry SDK is disabled')
	}
}

fn sentry_before_send(event C.sentry_value_t, _ voidptr, _ voidptr) C.sentry_value_t {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		state := thread_state() or {
			log.debug('no thread state, skipping crash metadata')
			return event
		}
		contexts := object_value(event, 'contexts')
		tags := object_value(event, 'tags')
		kind := state.kind.str()
		set_value(tags, 'thread-type', C.sentry_value_new_string_n(&char(kind.str), uint(kind.len)))
		assert sentry_state.dimensions_reader != unsafe { nil }
		dimensions := sentry_state.dimensions_reader(state.surface)
		object := C.sentry_value_new_object()
		for key, value in {
			'screen-width':  dimensions.screen_width
			'screen-height': dimensions.screen_height
			'grid-columns':  dimensions.grid_columns
			'grid-rows':     dimensions.grid_rows
			'cell-width':    dimensions.cell_width
			'cell-height':   dimensions.cell_height
		} {
			cast := if value <= u32(0x7fffffff) { i32(value) } else { i32(-1) }
			set_value(object, key, C.sentry_value_new_int32(cast))
		}
		set_value(contexts, 'Dimensions', object)
	}
	return event
}

fn sentry_transport_send(envelope voidptr, _ voidptr) {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		defer { C.sentry_envelope_free(envelope) }
		sentry_transport_send_internal(envelope) or { log.warn('failed to persist crash report err=${err}') }
	}
}

fn sentry_transport_send_internal(envelope voidptr) ! {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		mut length := uint(0)
		serialized := C.sentry_envelope_serialize(envelope, &length)
		defer { C.sentry_free(serialized) }
		bytes := unsafe { (&u8(serialized)).vbytes(int(length)) }
		mut parsed := Envelope.parse(bytes)!
		defer { parsed.deinit() }
		if sentry_envelope_should_discard(&parsed) {
			log.info('sentry envelope does not contain crash, discarding')
			return
		}
		uuid := C.sentry_uuid_new_v4()
		mut name := []u8{len: 37}
		C.sentry_uuid_as_string(&uuid, &char(name.data))
		dir := default_dir()!
		os.mkdir_all(dir.path)!
		path := os.join_path(dir.path, name[..36].bytestr() + '.wittycrash')
		mut file := os.create(path)!
		defer { file.close() }
		mut writer := source_file_writer.FileWriter.init(file.fd, 4096)
		source_file_writer.write_all(mut writer, bytes)!
		writer.flush()!
		log.warn('crash report written to disk path=${path}')
	}
}
