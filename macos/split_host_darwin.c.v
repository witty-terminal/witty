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
	divider_view ObjId
	divider_layers []ObjId
	divider_rgb u32
	divider_brightness f64 = 1
	inspector_divider_color u32
	dividers []NativeSplitDivider
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
	add_method(cls, 'hitTest:', voidptr(split_host_hit_test), '@@:{CGPoint=dd}')
	add_method(cls, 'mouseDown:', voidptr(split_host_mouse_down), 'v@:@')
	add_method(cls, 'mouseDragged:', voidptr(split_host_mouse_dragged), 'v@:@')
	add_method(cls, 'mouseUp:', voidptr(split_host_mouse_up), 'v@:@')
	add_method(cls, 'isFlipped', voidptr(split_host_is_flipped), 'B@:')
	add_method(cls, 'resizeSubviewsWithOldSize:', voidptr(split_host_resize), 'v@:{CGSize=dd}')
	C.macos_objc_register_class_pair(cls)

	overlay := C.macos_objc_allocate_class_pair(get_class('NSView'), cstr('WittySplitDividerOverlay'), 0)
	add_method(overlay, 'isFlipped', voidptr(split_host_is_flipped), 'B@:')
	add_method(overlay, 'hitTest:', voidptr(action_passive_hit), '@@:{CGPoint=dd}')
	add_method(overlay, 'viewDidChangeBackingProperties', voidptr(split_divider_backing_changed), 'v@:')
	C.macos_objc_register_class_pair(overlay)
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
		if child != host.divider_view && voidptr(child) !in containers { msg_void(child, 'removeFromSuperview') }
	}
	for view in leaves {
		container := surface_container(view)
        if msg_id(container, 'superview') != host.container { msg_void1(host.container, 'addSubview:', container) }
		msg_void_bool(container, 'setHidden:', host.tree.zoomed != unsafe { nil } && !host.tree.zoomed.leaves().contains(view))
	}
	root := if host.tree.zoomed == unsafe { nil } { host.tree.root } else { host.tree.zoomed }
	area := SplitBounds{width: bounds.width, height: bounds.height}
	for slot in native_split_layout(root, area, host.increment_width, host.increment_height) {
		b := slot.bounds
		msg_void_rect(surface_container(slot.node.view), 'setFrame:', objc_rect(b.x, b.y, b.width, b.height))
		surface_container_layout(slot.node.view)
	}
	host.dividers = split_dividers(root, area, host.increment_width, host.increment_height)
	host.layout_divider_view(bounds)
	host.refresh_surface_appearance()
}

fn (mut host NativeSplitHost) layout_divider_view(bounds ObjCRect) {
	if host.dividers.len == 0 {
		if !is_nil(host.divider_view) { msg_void_bool(host.divider_view, 'setHidden:', true) }
		return
	}
	if is_nil(host.divider_view) {
		host.divider_view = msg_id_rect(alloc('WittySplitDividerOverlay'), 'initWithFrame:', bounds)
		layer := msg_id(get_class('CALayer'), 'layer')
		msg_void_bool(layer, 'setGeometryFlipped:', true)
		msg_void1(host.divider_view, 'setLayer:', layer)
		msg_void_bool(host.divider_view, 'setWantsLayer:', true)
		C.witty_canvas_place_overlay(host.container, host.divider_view, nil_obj())
		msg_void(host.divider_view, 'release')
	} else if msg_id(msg_id(host.container, 'subviews'), 'lastObject') != host.divider_view {
		C.witty_canvas_place_overlay(host.container, host.divider_view, nil_obj())
	}
	msg_void_rect(host.divider_view, 'setFrame:', bounds)
	msg_void_bool(host.divider_view, 'setHidden:', false)
	host.layout_divider_layers(view_backing_scale(voidptr(host.divider_view)))
}

fn native_split_divider_shade(config NativeWindowConfig) (u32, f64) {
	if color := config.split_divider_color { return color, 1 }
	background := config.background
	// Scaling HSB brightness preserves hue and saturation in the RGB channels.
	brightness := if native_color_luminance(background) > 0.5 { 0.92 } else { 0.6 }
	return background, brightness
}

fn split_divider_channel(value u32, brightness f64) u32 {
	// SwiftUI's non-linear sRGB renderer stores the shade in half precision
	// before converting it to an eight-bit output pixel.
	fraction, exponent := math.frexp(f64(value) * brightness / 255)
	component := math.ldexp(math.round(fraction * 2048), exponent - 11)
	return u32(math.round(component * 255))
}

pub fn (mut host NativeSplitHost) set_appearance(config NativeWindowConfig, focused_view voidptr) {
	divider_rgb, divider_brightness := native_split_divider_shade(config)
	fill := config.unfocused_split_fill or { config.background }
	opacity := 1.0 - config.unfocused_split_opacity
	divider_changed := host.divider_rgb != divider_rgb || host.divider_brightness != divider_brightness
	if host.focused_view == focused_view && host.dim_fill == fill && host.dim_opacity == opacity && !divider_changed {
		return
	}
	if divider_changed {
		host.divider_rgb = divider_rgb
		host.divider_brightness = divider_brightness
		r := split_divider_channel(divider_rgb >> 16, divider_brightness)
		g := split_divider_channel((divider_rgb >> 8) & 255, divider_brightness)
		b := split_divider_channel(divider_rgb & 255, divider_brightness)
		host.inspector_divider_color = r << 16 | g << 8 | b
		for line in host.divider_layers {
			native_canvas_layer_fill(line, divider_rgb, divider_brightness)
		}
	}
	host.focused_view = focused_view
	host.dim_fill = fill
	host.dim_opacity = opacity
	host.refresh_surface_appearance()
}

fn (host &NativeSplitHost) refresh_surface_appearance() {
	leaves := host.tree.root.leaves()
	focused := if host.focused_view in leaves { host.focused_view } else if leaves.len > 0 { leaves[0] } else { unsafe { nil } }
	for view in leaves {
		dim := leaves.len > 1 && host.tree.zoomed == unsafe { nil } && view != focused
		set_surface_split_dimming(view, host.dim_fill, if dim { host.dim_opacity } else { 0.0 })
		set_surface_inspector_divider_color(view, host.inspector_divider_color)
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

struct NativeSplitDivider {
	node &NativeSplitNode
	bounds SplitBounds
	line SplitBounds
}

fn split_dividers(n &NativeSplitNode, bounds SplitBounds, iw f64, ih f64) []NativeSplitDivider {
	if n == unsafe { nil } || n.is_leaf() { return []NativeSplitDivider{} }
	left, right := native_split_children(n, bounds, iw, ih)
	line := if n.axis == .horizontal {
		SplitBounds{x: left.x + left.width - 0.5, y: bounds.y, width: 1, height: bounds.height}
	} else {
		SplitBounds{x: bounds.x, y: left.y + left.height - 0.5, width: bounds.width, height: 1}
	}
	mut result := [NativeSplitDivider{node: n, bounds: bounds, line: line}]
	result << split_dividers(n.left, left, iw, ih)
	result << split_dividers(n.right, right, iw, ih)
	return result
}
fn split_divider_backing_changed(self ObjId, _cmd Sel) {
	view_super_void(self, 'WittySplitDividerOverlay', 'viewDidChangeBackingProperties')
	mut host := split_host(msg_id(self, 'superview')) or { return }
	if !msg_bool(self, 'isHidden') {
		host.layout_divider_layers(view_backing_scale(voidptr(self)))
	}
}

fn (mut host NativeSplitHost) layout_divider_layers(scale f64) {
	parent := msg_id(host.divider_view, 'layer')
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	for i, divider in host.dividers {
		if i == host.divider_layers.len {
			line := msg_id(get_class('CALayer'), 'layer')
			native_canvas_layer_fill(line, host.divider_rgb, host.divider_brightness)
			msg_void1(parent, 'addSublayer:', line)
			host.divider_layers << line
		}
		line := host.divider_layers[i]
		msg_void_f64(line, 'setContentsScale:', scale)
		msg_void_rect(line, 'setFrame:', native_canvas_overlay_rect(divider.line, scale))
	}
	for host.divider_layers.len > host.dividers.len {
		msg_void(host.divider_layers.pop(), 'removeFromSuperlayer')
	}
	msg_void(transaction, 'commit')
}

fn (host &NativeSplitHost) divider_at(point ObjCPoint) ?NativeSplitDivider {
	// The visible one-point divider has another three points on each side.
	for divider in host.dividers {
		line := divider.line
		x_pad := if divider.node.axis == .horizontal { 3.0 } else { 0.0 }
		y_pad := if divider.node.axis == .vertical { 3.0 } else { 0.0 }
		if point.x >= line.x - x_pad && point.x <= line.x + line.width + x_pad
			&& point.y >= line.y - y_pad && point.y <= line.y + line.height + y_pad {
			return divider
		}
	}
	return none
}

fn split_host_hit_test(self ObjId, _cmd Sel, point ObjCPoint) ObjId {
	if host := split_host(self) {
		local := msg_point_point_obj(self, 'convertPoint:fromView:', point, msg_id(self, 'superview'))
		if host.divider_at(local) != none { return self }
	}
	return C.witty_action_hit_super(self, get_class('VTTerminalSplitHost'), point.x, point.y)
}
fn split_host_mouse_down(self ObjId, _cmd Sel, event ObjId) {
	mut host := split_host(self) or { return }
	point := msg_point_point_obj(self, 'convertPoint:fromView:', msg_point(event, 'locationInWindow'), nil_obj())
	divider := host.divider_at(point) or { return }
	if msg_u64(event, 'clickCount') == 2 {
		host.replace_tree(host.tree.equalized())
		return
	}
	host.drag_path = host.tree.root.path(divider.node) or { return }
	host.drag_bounds = divider.bounds
	host.dragging = true
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
