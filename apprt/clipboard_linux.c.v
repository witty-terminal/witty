module apprt

// The GTK runtime exposes Clipboard through GObject, so Ghostty deliberately
// uses a full C int as its backing type.
// If this is changed, you must also update witty.h.
pub enum Clipboard as int {
	standard // ctrl+c/v
	selection
	primary
}
