module witty_macos

import os

#insert "@VMODROOT/witty_macos/canvas_overlay_test_bridge.h"

fn C.witty_overlay_test_split_fill_matches(layer ObjId, rgb u32, brightness f64) bool
fn C.witty_overlay_test_opacity(layer ObjId) f32
fn C.witty_overlay_test_png(view ObjId) ObjId

fn assert_split_dimming(view ObjId, rgb u32, opacity f32) {
	layer := msg_id(view, 'layer')
	assert C.witty_overlay_test_split_fill_matches(layer, rgb, 1)
	assert C.witty_overlay_test_opacity(layer) == opacity
}

fn test_native_split_dimming_tracks_the_focused_pane_and_app_config() {
	app_init()
	left_view := create_restorable_window(480, 320, 'Split dimming')
	window := msg_id(left_view, 'window')
	mut host := create_split_host(left_view)
	right_view := create_split_surface_view(host)
	mut left := new_action_surface(left_view, unsafe { nil }, ActionCallbacks{})
	mut right := new_action_surface(right_view, unsafe { nil }, ActionCallbacks{})
	board := msg_id(get_class('NSPasteboard'), 'pasteboardWithUniqueName')
	right.search_pasteboard = board
	defer {
		left.deinit()
		right.deinit()
		msg_void(board, 'releaseGlobally')
		msg_void(window, 'close')
		msg_void(window, 'release')
		msg_void(left_view, 'release')
		msg_void(right_view, 'release')
		msg_void(host.container, 'release')
	}
	config := NativeWindowConfig{ background: 0x161820, unfocused_split_opacity: 0.5 }
	host.set_appearance(config, left_view)
	assert is_nil(left.scroll.split_dimming)

	tree := host.tree.inserting(right_view, left_view, .right) or { panic(err) }
	host.replace_tree(tree)
	assert msg_id(msg_id(host.container, 'subviews'), 'lastObject') == host.divider_view
	assert !msg_bool(host.divider_view, 'isHidden')
	assert is_nil(left.scroll.split_dimming)
	right_dimming := right.scroll.split_dimming
	assert !is_nil(right_dimming)
	assert !msg_bool(right_dimming, 'isHidden')
	assert msg_id(msg_id(right.scroll.container, 'subviews'), 'lastObject') == right_dimming
	assert_split_dimming(right_dimming, 0x161820, 0.5)
	assert msg_rect(right_dimming, 'frame') == msg_rect(right.scroll.scroll, 'frame')

	host.set_appearance(config, right_view)
	assert msg_bool(right_dimming, 'isHidden')
	left_dimming := left.scroll.split_dimming
	assert !msg_bool(left_dimming, 'isHidden')
	right.start_search('needle')
	assert right.search_active
	host.layout()
	assert msg_bool(right_dimming, 'isHidden')
	assert !msg_bool(left_dimming, 'isHidden')
	right.end_search()

	updated := NativeWindowConfig{ ...config, unfocused_split_opacity: 0.75, unfocused_split_fill: u32(0x81315a) }
	host.set_appearance(updated, right_view)
	assert_split_dimming(left_dimming, 0x81315a, 0.25)
	host.layout()
	assert_split_dimming(left_dimming, 0x81315a, 0.25)
	host.replace_tree(NativeSplitTree{ root: tree.root, zoomed: tree.root.find(right_view) or { panic('missing right pane') } })
	assert msg_bool(host.divider_view, 'isHidden')
	assert msg_bool(left_dimming, 'isHidden')
	assert msg_bool(right_dimming, 'isHidden')
	host.replace_tree(tree)
	assert !msg_bool(left_dimming, 'isHidden')
	host.set_appearance(NativeWindowConfig{ ...updated, unfocused_split_opacity: 1 }, right_view)
	assert msg_bool(left_dimming, 'isHidden')
}

fn test_native_surface_overlay_capture() {
	output := os.getenv_opt('WITTY_SURFACE_OVERLAY_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 96, 45)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := create_offscreen_terminal_view(96, 45)
	msg_void1(window, 'setContentView:', view)
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{})
	defer {
		surface.deinit()
		msg_void(window, 'close')
		msg_void(window, 'release')
		release_offscreen_terminal_view(view)
	}
	for i, rgb in [u32(0x161820), 0xe4e5e9, 0x3a87c0, 0xe9b085, 0x1c503b, 0xfeff00] {
		block := msg_id_rect(alloc('NSView'), 'initWithFrame:', objc_rect(i * 16, 0, 16, 45))
		msg_void_bool(block, 'setWantsLayer:', true)
		msg_void1(msg_id(block, 'layer'), 'setBackgroundColor:', msg_id(native_color(rgb, 1), 'CGColor'))
		C.witty_canvas_place_overlay(view, block, nil_obj())
		msg_void(block, 'release')
	}
	// Keep the terminal action overlay above the solid test cells.
	C.witty_canvas_place_overlay(view, surface.overlay, nil_obj())
	surface.scroll.layout()
	for i, name in ['default', 'custom', 'strong', 'disabled', 'health'] {
		fill := [u32(0x161820), 0x81315a, 0x345e9a, 0x81315a, 0][i]
		opacity := [0.3, 0.25, 0.63, 0.0, 0.0][i]
		set_surface_split_dimming(view, fill, opacity)
		if name == 'health' {
			surface.visual_background = 0x161820
			surface.renderer_health(false)
			assert !msg_bool(surface.health_label, 'isHidden')
			// Isolate the configured backdrop in the capture.
			msg_void_bool(surface.health_label, 'setHidden:', true)
		}
		png := C.witty_overlay_test_png(surface.scroll.container)
		assert !is_nil(png)
		assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output, '${name}-witty.png')), ObjId(1))
	}
}
