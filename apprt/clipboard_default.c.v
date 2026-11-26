module apprt

// Clipboard identifies the type of system clipboard. Its backing type
// matches the C API on this platform.
// If this is changed, you must also update witty.h.
pub enum Clipboard as u8 {
	standard // ctrl+c/v
	selection
	primary
}
