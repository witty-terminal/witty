module crash

import os
import internal_os

#include "@VMODROOT/crash/mtime.h"

fn C.witty_crash_file_info(path &char, regular &int, value &i64) int

fn C.witty_crash_thread_state_set(kind int, surface voidptr)

fn C.witty_crash_thread_state_clear()

fn C.witty_crash_thread_state_get(kind &int, surface &voidptr) int

// ThreadState carries the same per-thread context Ghostty attaches to crash
// reports. The surface stays opaque here to avoid a crash -> core -> crash
// import cycle.
pub struct ThreadState {
pub:
	kind    ThreadType
	surface voidptr
}

pub enum ThreadType as u8 {
	main     = 0
	renderer = 1
	io       = 2
}

pub fn set_thread_state(state ThreadState) {
	C.witty_crash_thread_state_set(int(state.kind), state.surface)
}

pub fn clear_thread_state() {
	C.witty_crash_thread_state_clear()
}

pub fn thread_state() ?ThreadState {
	mut kind := 0
	mut surface := voidptr(unsafe { nil })
	if C.witty_crash_thread_state_get(&kind, &surface) == 0 {
		return none
	}
	return ThreadState{
		kind:    unsafe { ThreadType(kind) }
		surface: surface
	}
}

// Process-wide native crash capture, selected by the source Sentry build flag.
pub fn initialize() ! { initialize_with_info(BuildInfo{})! }

pub fn shutdown() { sentry_shutdown() }

fn sentry_envelope_should_discard(envelope &Envelope) bool {
	for item in envelope.items {
		if item.item_type() == .event {
			return false
		}
	}
	return true
}

pub struct Dir {
pub:
	path string
}

pub struct Report {
pub:
	name  string
	mtime i64
}

// ReportIterator lazily returns regular crash-report files. V's directory API
// returns the directory entries as an owned array, so deinit releases that
// array instead of closing an open directory handle.
pub struct ReportIterator {
	path string
pub mut:
	entries []string
	index   int
}

// ReportIteratorNext preserves Ghostty's error-union-of-optional result.
pub struct ReportIteratorNext {
pub:
	value ?Report
}

// default_dir returns Ghostty's XDG state directory for crash reports.
pub fn default_dir() !Dir {
	return Dir{
		path: internal_os.state(internal_os.Options{
			subdir: 'witty/crash'
		})!
	}
}

// iterator returns an iterator over the crash reports in this directory. A
// missing or unreadable directory behaves like an empty report directory.
pub fn (dir &Dir) iterator() !ReportIterator {
	return ReportIterator{
		path:    dir.path
		entries: os.ls(dir.path) or { []string{} }
	}
}

pub fn (mut self ReportIterator) deinit() {
	self.entries.clear()
	self.index = 0
}

// next returns the next regular crash-report file, skipping directories and
// other non-file entries just like std.fs.Dir.Iterator in Ghostty.
pub fn (mut self ReportIterator) next() !ReportIteratorNext {
	for self.index < self.entries.len {
		name := self.entries[self.index]
		self.index++
		path := os.join_path(self.path, name)

		mut regular := 0
		mut mtime := i64(0)
		result := C.witty_crash_file_info(&char(path.str), &regular, &mtime)
		if result != 0 {
			return error_with_code('unable to stat crash report', result)
		}
		if regular == 0 {
			continue
		}
		return ReportIteratorNext{
			value: Report{
				name:  name
				mtime: mtime
			}
		}
	}
	return ReportIteratorNext{}
}

// reports collects the report iterator for callers that need an owned array.
pub fn (dir &Dir) reports() ![]Report {
	mut iter := dir.iterator()!
	defer {
		iter.deinit()
	}
	mut result := []Report{}
	for {
		next := iter.next()!
		report := next.value or { break }
		result << report
	}
	return result
}
