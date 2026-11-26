module apprt

// Test Runtime enum values.
fn test_runtime_enum() {
	assert Runtime.none_ == .none_
	assert Runtime.ui2 == .ui2
	assert sizeof(Runtime) == 1
	$if linux {
		assert Runtime.default() == .ui2
	} $else {
		assert Runtime.default() == .none_
	}
}
