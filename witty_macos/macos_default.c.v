module witty_macos

// Ghostty's pkg/macos is only compiled for Apple targets. Elsewhere this module
// is empty, so imports resolve and code under `$if macos` is not compiled.
