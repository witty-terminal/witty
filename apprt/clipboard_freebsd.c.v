module apprt

// The FreeBSD C API uses a full C int for the clipboard type.
// If this is changed, you must also update witty.h.
pub enum Clipboard as int {
	standard // ctrl+c/v
	selection
	primary
}
