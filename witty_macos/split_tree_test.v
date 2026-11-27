module witty_macos

fn test_native_split_tree_source_navigation_resize_and_equalization() {
	a := voidptr(1)
	b := voidptr(2)
	c := voidptr(3)
	t := NativeSplitTree{root: native_split_leaf(a)}.inserting(b, a, .right) or { panic(err) }
	t2 := t.inserting(c, a, .down) or { panic(err) }
	assert t2.root.leaves() == [a, c, b]
	assert t2.focus_target(.next, t2.root.find(a) or { panic('missing') }) or { voidptr(0) } == c
	assert t2.focus_target(.previous, t2.root.find(a) or { panic('missing') }) or { voidptr(0) } == b
	assert t2.focus_target(.right, t2.root.find(c) or { panic('missing') }) or { voidptr(0) } == b
	assert t2.focus_target(.up, t2.root.find(c) or { panic('missing') }) or { voidptr(0) } == a
	resized := t2.resizing(t2.root.find(c) or { panic('missing') }, 1000, .left, SplitBounds{width: 100, height: 100}) or { panic(err) }
	assert resized.root.ratio == 0.1
	assert resized.zoomed == unsafe { nil }
	assert t2.equalized().root.ratio == 0.5 // orthogonal subtree counts as one
	assert t2.removing(t2.root.find(c) or { panic('missing') }).root.leaves() == [a, b]
	t3 := t.inserting(c, b, .right) or { panic(err) }
	assert t3.equalized().root.ratio == f64(1) / 3
}

fn test_split_invalid_path_and_layout_rounding() {
	t := NativeSplitTree{root: native_split_leaf(voidptr(1))}
	if _ := t.inserting(voidptr(2), voidptr(7), .up) { assert false }
	t2 := t.inserting(voidptr(2), voidptr(1), .right) or { panic(err) }
	layout := native_split_layout(t2.root, SplitBounds{width: 103, height: 50}, 8, 16)
	assert layout[0].bounds.width == 48
	assert layout[1].bounds.x == 48.5
	assert layout[1].bounds.width == 54.5
	assert t2.borders(.up, t2.root.find(voidptr(2)) or { panic('missing') })
}
