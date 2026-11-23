module crash

import os

fn C.sentry_value_new_message_event_n(level int, logger &char, logger_len uint, message &char, message_len uint) C.sentry_value_t
fn C.sentry_capture_event(event C.sentry_value_t) C.sentry_uuid_t
fn C.sentry_value_to_json(event C.sentry_value_t) &char

fn sentry_test_dimensions(_ voidptr) Dimensions {
	return Dimensions{
		screen_width:  800
		screen_height: u32(0xffffffff)
		grid_columns:  80
		grid_rows:     24
		cell_width:    10
		cell_height:   20
	}
}

fn test_native_sentry_callback_enriches_live_thread_dimensions() {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		set_dimensions_reader(sentry_test_dimensions)
		set_thread_state(ThreadState{ kind: .renderer, surface: voidptr(1) })
		defer { clear_thread_state() }
		value := C.sentry_value_new_object()
		defer { C.sentry_value_decref(value) }
		result := sentry_before_send(value, unsafe { nil }, unsafe { nil })
		text := C.sentry_value_to_json(result)
		defer { C.sentry_free(text) }
		json := unsafe { cstring_to_vstring(text) }
		assert json.contains('"thread-type":"renderer"')
		assert json.contains('"screen-width":800')
		assert json.contains('"screen-height":-1')
		assert json.contains('"grid-columns":80')
		assert json.contains('"cell-height":20')
	}
}

fn test_native_sentry_sdk_capture_uses_local_envelope_transport() {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		root := os.join_path(os.temp_dir(), 'witty-native-sentry-${os.getpid()}')
		os.mkdir_all(root)!
		old_cache := os.getenv_opt('XDG_CACHE_HOME')
		old_state := os.getenv_opt('XDG_STATE_HOME')
		os.setenv('XDG_CACHE_HOME', os.join_path(root, 'cache'), true)
		os.setenv('XDG_STATE_HOME', os.join_path(root, 'state'), true)
		defer {
			if path := old_cache {
				os.setenv('XDG_CACHE_HOME', path, true)
			} else {
				os.unsetenv('XDG_CACHE_HOME')
			}
			if path := old_state {
				os.setenv('XDG_STATE_HOME', path, true)
			} else {
				os.unsetenv('XDG_STATE_HOME')
			}
			os.rmdir_all(root) or {}
		}
		initialize_with_info(BuildInfo{
			release:      'audit-native-test'
			mode:         'ReleaseFast'
			app_runtime:  'none'
			font_backend: 'coretext_freetype'
			renderer:     'metal'
		})!
		worker := sentry_state.init_thread or { panic('Sentry initializer was not spawned') }
		worker.wait()
		// This test consumes the initialization handle itself, then closes SDK.
		mut state := sentry_state_mut()
		state.init_thread = none
		defer { _ = C.sentry_close() }
		message := 'source local native capture'
		event := C.sentry_value_new_message_event_n(2, unsafe { nil }, 0, &char(message.str), uint(message.len))
		_ = C.sentry_capture_event(event)
		directory := default_dir()!
		reports := os.ls(directory.path)!
		crashes := reports.filter(it.ends_with('.wittycrash'))
		assert crashes.len == 1
		data := os.read_file(os.join_path(directory.path, crashes[0]))!
		assert data.contains('source local native capture')
		assert data.contains('audit-native-test')
		assert data.contains('"font-backend":"coretext_freetype"')
	}
}

$if macos || ios || linux {
	#include "@VMODROOT/crash/test_fault.h"
	#include <unistd.h>
	#include <sys/wait.h>
	fn C.fork() int
	fn C.waitpid(int, &int, int) int
	fn C.witty_sentry_test_fault()
	fn C._exit(int)
}

fn test_native_sentry_breakpad_captures_a_fault_in_a_child_process() {
	$if !no_sentry ?&& !windows && ( sentry ?|| macos || ios ) {
		root := os.join_path(os.temp_dir(), 'witty-native-sentry-fault-${os.getpid()}')
		os.mkdir_all(root)!
		defer { os.rmdir_all(root) or {} }
		child := C.fork()
		assert child >= 0
		if child == 0 {
			os.setenv('XDG_CACHE_HOME', os.join_path(root, 'cache'), true)
			os.setenv('XDG_STATE_HOME', os.join_path(root, 'state'), true)
			initialize_with_info(BuildInfo{ release: 'audit-native-fault' }) or { C._exit(100) }
			worker := sentry_state.init_thread or {
				C._exit(101)
				return
			}
			worker.wait()
			set_thread_state(ThreadState{ kind: .io, surface: voidptr(1) })
			C.witty_sentry_test_fault()
			C._exit(102)
		}
		mut status := 0
		assert C.waitpid(child, &status, 0) == child
		assert status != 0
		// The pinned Breakpad backend writes fatal envelopes to its disk
		// transport; the next SDK startup replays them through our transport.
		old_cache := os.getenv_opt('XDG_CACHE_HOME')
		old_state := os.getenv_opt('XDG_STATE_HOME')
		os.setenv('XDG_CACHE_HOME', os.join_path(root, 'cache'), true)
		os.setenv('XDG_STATE_HOME', os.join_path(root, 'state'), true)
		defer {
			if path := old_cache {
				os.setenv('XDG_CACHE_HOME', path, true)
			} else {
				os.unsetenv('XDG_CACHE_HOME')
			}
			if path := old_state {
				os.setenv('XDG_STATE_HOME', path, true)
			} else {
				os.unsetenv('XDG_STATE_HOME')
			}
		}
		initialize_with_info(BuildInfo{ release: 'audit-native-restart' })!
		worker := sentry_state.init_thread or { panic('Sentry restart was not spawned') }
		worker.wait()
		mut state := sentry_state_mut()
		state.init_thread = none
		defer { _ = C.sentry_close() }
		directory := os.join_path(root, 'state', 'witty', 'crash')
		crashes := os.ls(directory)!.filter(it.ends_with('.wittycrash'))
		assert crashes.len == 1
		data := os.read_file(os.join_path(directory, crashes[0]))!
		assert data.contains('audit-native-fault')
		assert data.contains('minidump')
	}
}
