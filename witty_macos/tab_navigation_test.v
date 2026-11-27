module witty_macos
fn test_source_numeric_and_special_tab_navigation() {
	assert native_tab_index(1, 1, 3) or { -99 } == 0
	assert native_tab_index(99, 1, 3) or { -99 } == 2
	assert native_tab_index(-1, 0, 3) or { -99 } == 2
	assert native_tab_index(-2, 2, 3) or { -99 } == 0
	assert native_tab_index(-3, 0, 3) or { -99 } == 2
	assert native_tab_index(0, 1, 3) == none
}
