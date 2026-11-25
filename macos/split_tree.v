module macos

import math

// Translation of Features/Splits/SplitTree.swift. NSView references remain
// opaque here; leaf equality is object identity, split equality is structural.
pub enum SplitAxis { horizontal vertical }
pub enum SplitNewDirection { left right down up }
pub enum SplitFocusDirection { previous next left right up down }
pub struct SplitBounds {
pub mut:
	x f64
	y f64
	width f64
	height f64
}
@[heap]
pub struct NativeSplitNode {
pub:
	view voidptr
	axis SplitAxis
	ratio f64 = 0.5
	left &NativeSplitNode = unsafe { nil }
	right &NativeSplitNode = unsafe { nil }
}
pub struct NativeSplitTree {
pub:
	root &NativeSplitNode = unsafe { nil }
	zoomed &NativeSplitNode = unsafe { nil }
}
pub struct SplitSlot {
pub:
	node &NativeSplitNode
	bounds SplitBounds
}
pub fn native_split_leaf(view voidptr) &NativeSplitNode { return &NativeSplitNode{view: view} }
pub fn (n &NativeSplitNode) is_leaf() bool { return n.left == unsafe { nil } }
pub fn (n &NativeSplitNode) equal(other &NativeSplitNode) bool {
	if n == unsafe { nil } || other == unsafe { nil } { return n == other }
	if n.is_leaf() { return other.is_leaf() && n.view == other.view }
	return !other.is_leaf() && n.axis == other.axis && n.ratio == other.ratio && n.left.equal(other.left) && n.right.equal(other.right)
}
pub fn (n &NativeSplitNode) leaves() []voidptr {
	if n == unsafe { nil } { return []voidptr{} }
	if n.is_leaf() { return [n.view] }
	mut result := n.left.leaves()
	result << n.right.leaves()
	return result
}
pub fn (n &NativeSplitNode) find(view voidptr) ?&NativeSplitNode {
	if n == unsafe { nil } { return none }
	if n.is_leaf() { return if n.view == view { n } else { none } }
	if found := n.left.find(view) { return found }
	return n.right.find(view)
}
pub fn (n &NativeSplitNode) path(target &NativeSplitNode) ?[]bool {
	if n == unsafe { nil } { return none }
	if n.equal(target) { return []bool{} }
	if n.is_leaf() { return none }
	if path := n.left.path(target) { mut result := [false]; result << path; return result }
	if path := n.right.path(target) { mut result := [true]; result << path; return result }
	return none
}
pub fn (n &NativeSplitNode) at(path []bool) ?&NativeSplitNode {
	if n == unsafe { nil } { return none }
	if path.len == 0 { return n }
	if n.is_leaf() { return none }
	return if path[0] { n.right.at(path[1..]) } else { n.left.at(path[1..]) }
}
pub fn (n &NativeSplitNode) replacing(path []bool, replacement &NativeSplitNode) !&NativeSplitNode {
	if path.len == 0 { return replacement }
	if n == unsafe { nil } || n.is_leaf() { return error('viewNotFound') }
	return &NativeSplitNode{axis: n.axis, ratio: n.ratio,
		left: if !path[0] { n.left.replacing(path[1..], replacement)! } else { n.left },
		right: if path[0] { n.right.replacing(path[1..], replacement)! } else { n.right }}
}
pub fn (t NativeSplitTree) inserting(view voidptr, at voidptr, direction SplitNewDirection) !NativeSplitTree {
	path := t.root.path(native_split_leaf(at)) or { return error('viewNotFound') }
	left := direction in [.left, .up]
	axis := if direction in [.left, .right] { SplitAxis.horizontal } else { SplitAxis.vertical }
	mut left_view := at
	mut right_view := view
	if left { left_view = view; right_view = at }
	replacement := &NativeSplitNode{axis: axis, left: native_split_leaf(left_view), right: native_split_leaf(right_view)}
	return NativeSplitTree{root: t.root.replacing(path, replacement)!}
}
fn (n &NativeSplitNode) remove(target &NativeSplitNode) &NativeSplitNode {
	if n == unsafe { nil } || n.equal(target) { return unsafe { nil } }
	if n.is_leaf() { return n }
	left := n.left.remove(target)
	right := n.right.remove(target)
	if left == unsafe { nil } { return right }
	if right == unsafe { nil } { return left }
	return &NativeSplitNode{axis: n.axis, ratio: n.ratio, left: left, right: right}
}
pub fn (t NativeSplitTree) removing(target &NativeSplitNode) NativeSplitTree {
	return NativeSplitTree{root: t.root.remove(target), zoomed: if t.zoomed.equal(target) { unsafe { nil } } else { t.zoomed }}
}
pub fn (t NativeSplitTree) replacing(target &NativeSplitNode, replacement &NativeSplitNode) !NativeSplitTree {
	path := t.root.path(target) or { return error('viewNotFound') }
	return NativeSplitTree{root: t.root.replacing(path, replacement)!, zoomed: if t.zoomed.equal(target) { replacement } else { t.zoomed }}
}
fn (n &NativeSplitNode) weight(axis SplitAxis) int {
	if n.is_leaf() || n.axis != axis { return 1 }
	return n.left.weight(axis) + n.right.weight(axis)
}
fn (n &NativeSplitNode) equalized() &NativeSplitNode {
	if n == unsafe { nil } || n.is_leaf() { return n }
	left_weight := n.left.weight(n.axis)
	right_weight := n.right.weight(n.axis)
	return &NativeSplitNode{axis: n.axis, ratio: f64(left_weight) / f64(left_weight + right_weight), left: n.left.equalized(), right: n.right.equalized()}
}
pub fn (t NativeSplitTree) equalized() NativeSplitTree { return NativeSplitTree{root: t.root.equalized(), zoomed: t.zoomed} }
fn (n &NativeSplitNode) dimensions() (f64, f64) {
	if n.is_leaf() { return 1, 1 }
	lw, lh := n.left.dimensions()
	rw, rh := n.right.dimensions()
	return if n.axis == .horizontal { lw + rw } else { math.max(lw, rw) }, if n.axis == .vertical { lh + rh } else { math.max(lh, rh) }
}
pub fn (n &NativeSplitNode) spatial(bounds SplitBounds) []SplitSlot {
	if n == unsafe { nil } { return []SplitSlot{} }
	mut slots := [SplitSlot{node: n, bounds: bounds}]
	if n.is_leaf() { return slots }
	left := if n.axis == .horizontal { SplitBounds{x: bounds.x, y: bounds.y, width: bounds.width * n.ratio, height: bounds.height} } else { SplitBounds{x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height * n.ratio} }
	right := if n.axis == .horizontal { SplitBounds{x: bounds.x + left.width, y: bounds.y, width: bounds.width * (1 - n.ratio), height: bounds.height} } else { SplitBounds{x: bounds.x, y: bounds.y + left.height, width: bounds.width, height: bounds.height * (1 - n.ratio)} }
	slots << n.left.spatial(left)
	slots << n.right.spatial(right)
	return slots
}
pub fn (t NativeSplitTree) focus_target(direction SplitFocusDirection, current &NativeSplitNode) ?voidptr {
	if t.root == unsafe { nil } { return none }
	leaves := t.root.leaves()
	current_leaves := current.leaves()
	if direction in [.previous, .next] {
		mut view := current_leaves[0]
		if direction == .next { view = current_leaves[current_leaves.len - 1] }
		idx := leaves.index(view)
		if idx < 0 { return none }
		return leaves[(idx + leaves.len + if direction == .previous { -1 } else { 1 }) % leaves.len]
	}
	w, h := t.root.dimensions()
	slots := t.root.spatial(SplitBounds{width: w, height: h})
	mut reference := SplitBounds{}
	mut found := false
	for slot in slots { if slot.node.equal(current) { reference = slot.bounds; found = true; break } }
	if !found { return none }
	mut candidates := []SplitSlot{}
	for slot in slots {
		if slot.node.equal(current) { continue }
		b := slot.bounds
		candidate := match direction {
			.left { b.x + b.width <= reference.x }
			.right { b.x >= reference.x + reference.width }
			.up { b.y + b.height <= reference.y }
			.down { b.y >= reference.y + reference.height }
			else { false }
		}
		if candidate { candidates << slot }
	}
	candidates.sort_with_compare(fn [reference] (a &SplitSlot, b &SplitSlot) int {
		da := math.sqrt(math.pow(a.bounds.x - reference.x, 2) + math.pow(a.bounds.y - reference.y, 2))
		db := math.sqrt(math.pow(b.bounds.x - reference.x, 2) + math.pow(b.bounds.y - reference.y, 2))
		return if da < db { -1 } else if da > db { 1 } else { 0 }
	})
	if candidates.len == 0 { return none }
	for candidate in candidates { if candidate.node.is_leaf() { return candidate.node.view } }
	views := candidates[0].node.leaves()
	return if direction in [.up, .left] { views[0] } else { views[views.len - 1] }
}
pub fn (t NativeSplitTree) resizing(target &NativeSplitNode, pixels u16, direction SplitFocusDirection, bounds SplitBounds) !NativeSplitTree {
	path := t.root.path(target) or { return error('viewNotFound') }
	axis := if direction in [.up, .down] { SplitAxis.vertical } else { SplitAxis.horizontal }
	for i := path.len - 1; i >= 0; i-- {
		parent_path := path[..i]
		parent := t.root.at(parent_path) or { continue }
		if parent.is_leaf() || parent.axis != axis { continue }
		for slot in t.root.spatial(SplitBounds{width: bounds.width, height: bounds.height}) {
			if !slot.node.equal(parent) { continue }
			dimension := if axis == .horizontal { slot.bounds.width } else { slot.bounds.height }
			delta := f64(pixels) / dimension * if direction in [.left, .up] { -1 } else { 1 }
			ratio := math.max(0.1, math.min(0.9, parent.ratio + delta))
			return NativeSplitTree{root: t.root.replacing(parent_path, &NativeSplitNode{axis: axis, ratio: ratio, left: parent.left, right: parent.right})!}
		}
	}
	return error('viewNotFound')
}
pub fn (t NativeSplitTree) borders(direction SplitFocusDirection, target &NativeSplitNode) bool {
	if t.root == unsafe { nil } { return false }
	w, h := t.root.dimensions()
	for slot in t.root.spatial(SplitBounds{width: w, height: h}) {
		if slot.node.equal(target) { b := slot.bounds; return match direction { .up { b.y == 0 } .down { b.y + b.height == h } .left { b.x == 0 } .right { b.x + b.width == w } else { false } } }
	}
	return false
}

fn native_split_first_extent(extent f64, ratio f64, increment f64) f64 {
	first := extent * ratio - 0.5
	return first - math.fmod(first, increment)
}

// SplitView.leftRect/rightRect leaves half a point between the child frames.
fn native_split_children(n &NativeSplitNode, bounds SplitBounds, increment_width f64, increment_height f64) (SplitBounds, SplitBounds) {
	mut left := bounds
	mut right := bounds
	if n.axis == .horizontal {
		left.width = native_split_first_extent(bounds.width, n.ratio, increment_width)
		right.x += left.width + 0.5
		right.width -= left.width + 0.5
	} else {
		left.height = native_split_first_extent(bounds.height, n.ratio, increment_height)
		right.y += left.height + 0.5
		right.height -= left.height + 0.5
	}
	return left, right
}

pub fn native_split_layout(n &NativeSplitNode, bounds SplitBounds, increment_width f64, increment_height f64) []SplitSlot {
	if n == unsafe { nil } { return []SplitSlot{} }
	if n.is_leaf() { return [SplitSlot{node: n, bounds: bounds}] }
	left, right := native_split_children(n, bounds, increment_width, increment_height)
	mut slots := native_split_layout(n.left, left, increment_width, increment_height)
	slots << native_split_layout(n.right, right, increment_width, increment_height)
	return slots
}
