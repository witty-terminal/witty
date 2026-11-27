// The pinned Zig executable startup installs a caught SIGPIPE disposition.
// V's startup leaves the default terminating disposition; reproduce the
// source runtime boundary before invoking translated executable entrypoints.
module source_startup

import os

#include "@VMODROOT/source_startup/sigpipe.h"
fn C.witty_source_startup_sigpipe() int

$if gcboehm ? {
	fn C.GC_set_free_space_divisor(divisor uint)
}

pub fn prepare() {
	status := C.witty_source_startup_sigpipe()
	if status != 0 { panic('unreachable sigaction failure') }
}

pub fn prepare_app() {
	prepare()
	$if gcboehm ? {
		// Collect earlier during terminal output bursts so the app carries
		// less spare heap into idle time. Honor the collector's environment override.
		if os.getenv_opt('GC_FREE_SPACE_DIVISOR') == none {
			divisor := $if macos && app_runtime_ui2 ? { u32(24) } $else { u32(8) }
			C.GC_set_free_space_divisor(divisor)
		}
	}
}
