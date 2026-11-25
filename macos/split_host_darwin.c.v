module macos

import math

@[heap]
pub struct NativeSplitHost {
pub:
	container voidptr
pub mut:
	tree NativeSplitTree
	increment_width f64 = 1
	increment_height f64 = 1
	drag_path []bool
	dragging bool
	drag_bounds SplitBounds
mut:
	focused_view voidptr
	dim_fill u32
	dim_opacity f64
}

fn split_host(self ObjId) ?&NativeSplitHost {
	ptr := C.macos_objc_get_ptr_ivar(self, cstr('vtSplitHost'))
	if is_nil(ptr) { return none }
	return unsafe { &NativeSplitHost(ptr) }
}
fn split_host_is_flipped(_self ObjId, _cmd Sel) bool { return true }
fn split_host_resize(self ObjId, _cmd Sel, _old_size ObjCSize) {
	if mut host := split_host(self) { host.layout() }
}
fn register_split_host_class() {
	if !is_nil(get_class('VTTerminalSplitHost')) { return }
	cls := C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('VTTerminalSplitHost'), 0)
	C.macos_class_add_ivar(cls, cstr('vtSplitHost'), sizeof(voidptr), 3, cstr('^v'))
	add_method(cls, 'drawRect:', voidptr(split_host_draw), 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
	add_method(cls, 'mouseDown:', voidptr(split_host_mouse_down), 'v@:@')
	add_method(cls, 'mouseDragged:', voidptr(split_host_mouse_dragged), 'v@:@')
	add_method(cls, 'mouseUp:', voidptr(split_host_mouse_up), 'v@:@')
	add_method(cls, 'isFlipped', voidptr(split_host_is_flipped), 'B@:')
	add_method(cls, 'resizeSubviewsWithOldSize:', voidptr(split_host_resize), 'v@:{CGSize=dd}')
	C.macos_objc_register_class_pair(cls)
}
pub fn create_split_host(view voidptr) &NativeSplitHost {
	register_split_host_class()
	window := msg_id(view, 'window')
	bounds := msg_rect(view, 'bounds')
	container := msg_id_rect(alloc('VTTerminalSplitHost'), 'initWithFrame:', bounds)
	host := &NativeSplitHost{container: voidptr(container), tree: NativeSplitTree{root: native_split_leaf(view)}, focused_view: view}
	C.macos_objc_set_ptr_ivar(container, cstr('vtSplitHost'), voidptr(host))
	// The immutable tree owns the views just as the Swift SurfaceTree does.
	msg_void(view, 'retain')
	msg_void1(window, 'setContentView:', container)
	msg_void1(container, 'addSubview:', surface_container(view))
	msg_void1(window, 'setInitialFirstResponder:', view)
	msg_bool1(window, 'makeFirstResponder:', view)
	msg_void(view, 'release')
	return host
}
pub fn create_split_surface_view(host &NativeSplitHost) voidptr {
	return create_terminal_view(msg_rect(host.container, 'bounds'))
}
pub fn (mut host NativeSplitHost) replace_tree(tree NativeSplitTree) {
	host.tree = tree
	set_native_split_zoom(host.container,tree.zoomed != unsafe { nil })
	host.layout()
}
pub fn (mut host NativeSplitHost) layout() {
	bounds := msg_rect(host.container, 'bounds')
	leaves := host.tree.root.leaves()
    containers := leaves.map(surface_container(it))
	children := msg_id(host.container, 'subviews')
	for i := int(msg_u64(children, 'count')) - 1; i >= 0; i-- {
		child := msg_id_u64(children, 'objectAtIndex:', u64(i))
		if voidptr(child) !in containers { msg_void(child, 'removeFromSuperview') }
	}
	for view in leaves {
		container := surface_container(view)
        if msg_id(container, 'superview') != host.container { msg_void1(host.container, 'addSubview:', container) }
		msg_void_bool(container, 'setHidden:', host.tree.zoomed != unsafe { nil } && !host.tree.zoomed.leaves().contains(view))
	}
	root := if host.tree.zoomed == unsafe { nil } { host.tree.root } else { host.tree.zoomed }
	msg_void_bool(host.container, 'setNeedsDisplay:', true)
	for slot in native_split_layout(root, SplitBounds{width: bounds.width, height: bounds.height}, host.increment_width, host.increment_height) {
		b := slot.bounds
		msg_void_rect(surface_container(slot.node.view), 'setFrame:', objc_rect(b.x, b.y, b.width, b.height))
		surface_container_layout(slot.node.view)
	}
	host.refresh_dimming()
}

pub fn (mut host NativeSplitHost) set_dimming(config NativeWindowConfig, focused_view voidptr) {
	fill := config.unfocused_split_fill or { config.background }
	opacity := 1.0 - config.unfocused_split_opacity
	if host.focused_view == focused_view && host.dim_fill == fill && host.dim_opacity == opacity {
		return
	}
	host.focused_view = focused_view
	host.dim_fill = fill
	host.dim_opacity = opacity
	host.refresh_dimming()
}

fn (host &NativeSplitHost) refresh_dimming() {
	leaves := host.tree.root.leaves()
	focused := if host.focused_view in leaves { host.focused_view } else if leaves.len > 0 { leaves[0] } else { unsafe { nil } }
	for view in leaves {
		dim := leaves.len > 1 && host.tree.zoomed == unsafe { nil } && view != focused
		set_surface_split_dimming(view, host.dim_fill, if dim { host.dim_opacity } else { 0.0 })
	}
}
pub fn view_window(view voidptr) voidptr { return msg_id(view, 'window') }
pub fn focus_split_view(view voidptr) {
	move_focus(view, unsafe { nil }, none)
}

fn terminal_view_for_window(window ObjId) ObjId {
	responder := msg_id(window, 'firstResponder')
	if msg_bool1(responder, 'isKindOfClass:', get_class('VTTerminalView')) { return responder }
	content := msg_id(window, 'contentView')
	if host := split_host(content) { views := host.tree.root.leaves(); if views.len > 0 { return ObjId(views[0]) } }
	return content
}

fn split_dividers(n &NativeSplitNode, bounds SplitBounds, iw f64, ih f64) []SplitSlot {
	if n == unsafe { nil } || n.is_leaf() { return []SplitSlot{} }
	mut left := bounds
	mut right := bounds
	if n.axis == .horizontal {
		left.width = bounds.width * n.ratio - 0.5
		left.width -= math.fmod(left.width, iw)
		right.x += left.width + 0.5
		right.width -= left.width + 0.5
	} else {
		left.height = bounds.height * n.ratio - 0.5
		left.height -= math.fmod(left.height, ih)
		right.y += left.height + 0.5
		right.height -= left.height + 0.5
	}
	mut result := [SplitSlot{node: n, bounds: bounds}]
	result << split_dividers(n.left, left, iw, ih)
	result << split_dividers(n.right, right, iw, ih)
	return result
}
fn split_host_draw(self ObjId, _cmd Sel, _dirty ObjCRect) {
	host := split_host(self) or { return }
	if host.tree.zoomed != unsafe { nil } { return }
	bounds := msg_rect(self, 'bounds')
	msg_void(msg_id(get_class('NSColor'), 'separatorColor'), 'setFill')
	for slot in split_dividers(host.tree.root, SplitBounds{width: bounds.width, height: bounds.height}, host.increment_width, host.increment_height) {
		b := slot.bounds
		n := slot.node
		mut rect := objc_rect(b.x, b.y, b.width, b.height)
		if n.axis == .horizontal {
			width := b.width * n.ratio - 0.5
			rect.x += width - math.fmod(width, host.increment_width)
			rect.width = 1
		} else {
			height := b.height * n.ratio - 0.5
			rect.y += height - math.fmod(height, host.increment_height)
			rect.height = 1
		}
		msg_void_rect(get_class('NSBezierPath'), 'fillRect:', rect)
	}
}
fn split_host_mouse_down(self ObjId, _cmd Sel, event ObjId) {
	mut host := split_host(self) or { return }
	if host.tree.zoomed != unsafe { nil } { return }
	point := msg_point_point_obj(self, 'convertPoint:fromView:', msg_point(event, 'locationInWindow'), nil_obj())
	bounds := msg_rect(self, 'bounds')
	for slot in split_dividers(host.tree.root, SplitBounds{width: bounds.width, height: bounds.height}, host.increment_width, host.increment_height) {
		b := slot.bounds
		n := slot.node
		hit := if n.axis == .horizontal { math.abs(point.x - (b.x + b.width * n.ratio - 0.5 - math.fmod(b.width * n.ratio - 0.5, host.increment_width))) <= 3.5 && point.y >= b.y && point.y <= b.y + b.height } else { math.abs(point.y - (b.y + b.height * n.ratio - 0.5 - math.fmod(b.height * n.ratio - 0.5, host.increment_height))) <= 3.5 && point.x >= b.x && point.x <= b.x + b.width }
		if !hit { continue }
		if msg_u64(event, 'clickCount') == 2 { host.replace_tree(host.tree.equalized()); return }
		host.drag_path = host.tree.root.path(n) or { return }
		host.drag_bounds = b
		host.dragging = true
		return
	}
}
fn split_host_mouse_dragged(self ObjId, _cmd Sel, event ObjId) {
	mut host := split_host(self) or { return }
	if !host.dragging { return }
	point := msg_point_point_obj(self, 'convertPoint:fromView:', msg_point(event, 'locationInWindow'), nil_obj())
	n := host.tree.root.at(host.drag_path) or { return }
	b := host.drag_bounds
	dimension := if n.axis == .horizontal { b.width } else { b.height }
	location := if n.axis == .horizontal { point.x - b.x } else { point.y - b.y }
	ratio := math.min(math.max(10.0, location), dimension - 10) / dimension
	root := host.tree.root.replacing(host.drag_path, &NativeSplitNode{axis: n.axis, ratio: ratio, left: n.left, right: n.right}) or { return }
	host.replace_tree(NativeSplitTree{root: root, zoomed: host.tree.zoomed})
}
fn split_host_mouse_up(self ObjId, _cmd Sel, _event ObjId) {
	if mut host := split_host(self) { host.dragging = false }
}
