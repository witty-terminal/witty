module renderer

import sync
import terminal
import input

pub type InspectorOverlayFeaturesFn = fn (voidptr) []OverlayFeature

pub type InspectorRecordPtyReadFn = fn (voidptr, &terminal.Terminal, []u8) !

// InspectorOverlayBridge is the renderer-visible prefix of Inspector. Keeping
// it as Inspector's first field lets RenderState retain Ghostty's opaque
// inspector pointer without creating a V module import cycle.
pub struct InspectorOverlayBridge {
pub:
	overlay_features_fn InspectorOverlayFeaturesFn = unsafe { nil }
	record_pty_read_fn  InspectorRecordPtyReadFn = unsafe { nil }
}

// record_inspector_pty_read records a pty read with the inspector before the
// terminal parser mutates state: Ghostty's `insp.recordPtyRead` call.
pub fn (self &RenderState) record_inspector_pty_read(data []u8) ! {
	if isnil(self.inspector) {
		return
	}
	bridge := unsafe { &InspectorOverlayBridge(self.inspector) }
	if bridge.record_pty_read_fn != unsafe { nil } {
		bridge.record_pty_read_fn(self.inspector, self.terminal_, data)!
	}
}

fn (self &RenderState) inspector_overlay_features() []OverlayFeature {
	if isnil(self.inspector) {
		return []OverlayFeature{}
	}
	bridge := unsafe { &InspectorOverlayBridge(self.inspector) }
	if bridge.overlay_features_fn == unsafe { nil } {
		return []OverlayFeature{}
	}
	return bridge.overlay_features_fn(self.inspector)
}

// This is the render state that is given to a renderer.
// It holds thread-safe shared state between the terminal and renderer.
pub struct RenderState {
pub mut:
	// The mutex that must be held while reading any of the data in the
	// members of this state.
	mutex &sync.Mutex = unsafe { nil }

	// The terminal data.
	terminal_ &terminal.Terminal = unsafe { nil }

	// The terminal inspector, if any. This will be null while the inspector
	// is not active and will be set when it is active.
	inspector voidptr = unsafe { nil }

	// Dead key state. This will render the current dead key preedit text
	// over the cursor.
	preedit ?RenderPreedit

	// Mouse state. This only contains state relevant to what renderers
	// need about the mouse.
	mouse RenderMouse
}

// Mouse state relevant to rendering.
pub struct RenderMouse {
pub mut:
	// The point on the viewport where the mouse currently is.
	point ?terminal.Coordinate
	// The mods that are currently active for the last mouse event.
	mods input.Mods
}

// The pre-edit state for dead key composition.
pub struct RenderPreedit {
pub mut:
	// The codepoints to render as preedit text.
	codepoints []RenderPreeditCodepoint
}

// A single codepoint to render as preedit text.
pub struct RenderPreeditCodepoint {
pub:
	codepoint u32
	wide      bool
}

// Deinit this preedit.
pub fn (self &RenderPreedit) deinit() {
	// codepoints will be GC'd in V
}

// Allocate a copy of this preedit.
pub fn (self &RenderPreedit) clone() RenderPreedit {
	return RenderPreedit{
		codepoints: self.codepoints.clone()
	}
}

// The width in cells of all codepoints in the preedit.
pub fn (self &RenderPreedit) width() uint {
	mut result := uint(0)
	for cp in self.codepoints {
		result += if cp.wide { uint(2) } else { uint(1) }
	}
	return result
}

// Range returns the inclusive start and end x positions of the preedit text
// along with any codepoint offset necessary to fit the preedit
// into the available space.
pub fn (self &RenderPreedit) range(start u16, max u16) (u16, u16, uint) {
	// If our width is greater than the number of cells we have
	// then we need to adjust our codepoint start to a point where
	// our width would be less than the number of cells we have.

	// max is inclusive, so we need to add 1 to it.
	max_width := u32(max) - u32(start) + 1

	// Rebuild our width in reverse order.
	mut w := u32(0)
	mut cp_offset := uint(0)
	for i := self.codepoints.len - 1; i >= 0; i-- {
		cp := self.codepoints[i]
		w += if cp.wide { u32(2) } else { u32(1) }
		if w > max_width {
			cp_offset = uint(i)
			break
		}
	}

	// If our preedit goes off the end of the screen, we adjust it so
	// that it shifts left.
	end := u32(start) + if w > 0 { w - 1 } else { u32(0) }
	start_offset := if end > max { end - max } else { u32(0) }
	result_start := if start > start_offset { u16(start - start_offset) } else { u16(0) }
	return result_start, u16(end - start_offset), cp_offset
}
