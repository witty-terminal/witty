module witty_macos

// TerminalController.onGotoTab uses one-based positive bindings and clamps
// out-of-range bindings to the last tab. Zero is not a special binding.
pub fn native_tab_index(value int, selected int, count int) ?int {
	if count <= 0 { return none }
	if value > 0 { return if value - 1 < count { value - 1 } else { count - 1 } }
	if selected < 0 || selected >= count { return none }
	return match value {
		-1 { if selected == 0 { count - 1 } else { selected - 1 } }
		-2 { if selected == count - 1 { 0 } else { selected + 1 } }
		-3 { count - 1 }
		else { none }
	}
}
