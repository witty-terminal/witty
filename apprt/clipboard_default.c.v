module apprt

// Clipboard identifies the type of system clipboard. Ghostty uses its compact
// u2 backing whenever the application runtime is not GTK; V's smallest enum
// storage is u8.
// If this is changed, you must also update witty.h.
pub enum Clipboard as u8 {
	standard // ctrl+c/v
	selection
	primary
}
