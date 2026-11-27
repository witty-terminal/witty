module witty_macos

fn C.vt_display_link_create_with_active_displays() voidptr

fn C.vt_display_link_release(link voidptr)

fn C.vt_display_link_start(link voidptr) bool

fn C.vt_display_link_stop(link voidptr) bool

fn C.vt_display_link_is_running(link voidptr) bool

fn C.vt_display_link_set_current_display(link voidptr, display_id u32) bool

fn C.vt_display_link_set_output_callback(link voidptr, callback voidptr, context voidptr) bool

pub type DisplayLink = CVDisplayLink

pub struct CVDisplayLink {}

pub fn CVDisplayLink.create_with_active_cg_displays() !&CVDisplayLink {
	ptr := C.vt_display_link_create_with_active_displays()
	return require_cf_ref[CVDisplayLink](ptr, 'CVDisplayLinkCreateWithActiveCGDisplays')
}

pub fn (d &CVDisplayLink) release() {
	C.vt_display_link_release(voidptr(d))
}

pub fn (d &CVDisplayLink) start() ! {
	if !C.vt_display_link_start(voidptr(d)) {
		return error('CVDisplayLinkStart failed')
	}
}

pub fn (d &CVDisplayLink) stop() ! {
	if !C.vt_display_link_stop(voidptr(d)) {
		return error('CVDisplayLinkStop failed')
	}
}

pub fn (d &CVDisplayLink) is_running() bool {
	return C.vt_display_link_is_running(voidptr(d))
}

pub fn (d &CVDisplayLink) set_current_cg_display(display_id u32) ! {
	if !C.vt_display_link_set_current_display(voidptr(d), display_id) {
		return error('CVDisplayLinkSetCurrentCGDisplay failed')
	}
}

// set_output_callback registers a C-compatible CVDisplayLink output callback.
// The callback receives the CVDisplayLinkRef, timing values, option flags, and
// the caller-provided context exactly as CoreVideo supplies them.
pub fn (d &CVDisplayLink) set_output_callback(callback voidptr, context voidptr) ! {
	if !C.vt_display_link_set_output_callback(voidptr(d), callback, context) {
		return error('CVDisplayLinkSetOutputCallback failed')
	}
}
