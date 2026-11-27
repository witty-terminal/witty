@[has_globals]
module witty_macos

import os
import json2

#insert "@VMODROOT/witty_macos/updater_test_abi.h"
#insert "@VMODROOT/witty_macos/canvas_overlay_test_bridge.h"
fn C.witty_update_test_block(kind int) voidptr
fn C.witty_update_test_count() int
fn C.witty_update_test_value() int
fn C.witty_update_test_reset()
fn C.witty_update_test_object() ObjId
fn C.witty_overlay_test_png(view ObjId) ObjId
fn C.witty_overlay_test_window_png(window ObjId) ObjId

fn test_update_badge_ring_progress_and_canvas_coverage() {
	assert UpdateState{kind: .downloading}.ring_progress() == none
	assert UpdateState{kind: .downloading, expected_length: 0}.ring_progress() == none
	assert UpdateState{kind: .downloading, expected_length: 80, downloaded: 20}.ring_progress()? == 0.25
	assert UpdateState{kind: .downloading, expected_length: 80, downloaded: 100}.ring_progress()? == 1
	assert UpdateState{kind: .extracting, extraction_progress: -0.1}.ring_progress()? == 0
	assert UpdateState{kind: .extracting, extraction_progress: 1.5}.ring_progress()? == 1

	empty := update_ring_raster(32, 0, 1)!
	quarter := update_ring_raster(32, 0.25, 1)!
	full := update_ring_raster(32, 1, 1)!
	assert empty.pixels[2 * 32 + 16] >> 24 == 51
	assert quarter.pixels[2 * 32 + 16] >> 24 == 255
	assert quarter.pixels[16 * 32 + 29] >> 24 == 255
	assert quarter.pixels[29 * 32 + 16] >> 24 == 51
	assert full.pixels[29 * 32 + 16] >> 24 == 255
	assert full.pixels[16 * 32 + 16] == 0
}

fn test_update_badge_ring_progress_eases_and_settles() {
	transition := UpdateRingTransition{start: 1, from: 0.25}
	assert transition.progress_at(0.75, 1) == 0.25
	assert transition.progress_at(0.75, 1 + update_ring_duration / 4) < 0.375
	middle := transition.progress_at(0.75, 1 + update_ring_duration / 2)
	assert middle > 0.4999 && middle < 0.5001
	assert transition.progress_at(0.75, 1 + update_ring_duration * 3 / 4) > 0.625
	assert transition.progress_at(0.75, 1 + update_ring_duration) == 0.75
}

fn test_native_update_badge_ring_capture() {
	output := os.getenv_opt('WITTY_UPDATE_RING_OUTPUT') or { return }
	app_init()
	frame := objc_rect(0, 0, 32, 32)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(view, 'setWantsLayer:', true)
	msg_void1(window, 'setContentView:', view)
	badge := update_badge_view()
	msg_void_rect(badge, 'setFrame:', objc_rect(8, 8, update_ring_view_size, update_ring_view_size))
	msg_void1(view, 'addSubview:', badge)
	g_update_controller = &NativeUpdateController{}
	defer {
		stop_native_updater()
		msg_void(window, 'close')
		msg_void(window, 'release')
		msg_void(badge, 'release')
		msg_void(view, 'release')
	}
	appearances := ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua']
	names := ['light', 'dark']
	for i, appearance in appearances {
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		gray := if i == 0 { 0.9 } else { 0.2 }
		color := C.witty_macos_color_rgba(gray, gray, gray, 1)
		msg_void1(msg_id(view, 'layer'), 'setBackgroundColor:', msg_id(color, 'CGColor'))
		for percentage in [0, 12, 25, 50, 87, 100] {
			g_update_controller.state = UpdateState{
				kind: .extracting
				extraction_progress: f64(percentage) / 100
			}
			msg_void_bool(badge, 'setNeedsDisplay:', true)
			png := C.witty_overlay_test_png(view)
			assert !is_nil(png)
			assert msg_bool2(png, 'writeToFile:atomically:',
				nsstring(os.join_path(output, '${names[i]}-${percentage}-witty.png')), ObjId(1))
		}
	}
}

fn test_native_update_pill_capture() {
	output := os.getenv('WITTY_UPDATE_PILL_OUTPUT')
	live := os.getenv('WITTY_UPDATE_PILL_LIVE_OUTPUT')
	if output.len == 0 && live.len == 0 { return }
	app_init()
	frame := objc_rect(0, 0, 290, 64)
	window := msg_id_rect_u64_u64_bool(alloc('NSWindow'), 'initWithContentRect:styleMask:backing:defer:',
		frame, 0, ns_backing_store_buffered, false)
	msg_void_bool(window, 'setReleasedWhenClosed:', false)
	msg_void_bool(window, 'setHasShadow:', false)
	msg_void1(window, 'setColorSpace:', msg_id(get_class('NSColorSpace'), 'displayP3ColorSpace'))
	view := msg_id_rect(alloc('NSView'), 'initWithFrame:', frame)
	msg_void_bool(view, 'setWantsLayer:', true)
	background := C.witty_macos_color_rgba(0.2, 0.3, 0.4, 1)
	msg_void1(msg_id(view, 'layer'), 'setBackgroundColor:', msg_id(background, 'CGColor'))
	msg_void1(window, 'setContentView:', view)
	pill := update_pill_view()
	msg_void1(view, 'addSubview:', pill)
	badge := update_badge_view()
	msg_void1(pill, 'addSubview:', badge)
	g_update_controller = &NativeUpdateController{}
	defer {
		stop_native_updater()
		msg_void(window, 'close')
		msg_void(window, 'release')
		msg_void(badge, 'release')
		msg_void(pill, 'release')
		msg_void(view, 'release')
	}

	names := ['permission', 'checking', 'available', 'not-found', 'error', 'download',
		'download-unknown', 'extract', 'install', 'unicode-error', 'mixed-error']
	states := [
		UpdateState{kind: .permission_request},
		UpdateState{kind: .checking},
		UpdateState{kind: .update_available, version: '1.4.0'},
		UpdateState{kind: .not_found},
		UpdateState{kind: .error, error_description: 'Connection failed'},
		UpdateState{kind: .downloading, expected_length: 100, downloaded: 25},
		UpdateState{kind: .downloading},
		UpdateState{kind: .extracting, extraction_progress: 0.75},
		UpdateState{kind: .installing},
		UpdateState{kind: .error, error_description: 'Cannot open café 👩‍💻'},
		UpdateState{kind: .error, error_description: 'Café 👩🏽‍💻🇯🇵 مرحبا 🚀\nTry again'},
	]
	scale := view_backing_scale(voidptr(view))
	assert states[5].pill_width(scale) == states[6].pill_width(scale)
	for i, appearance in ['NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'] {
		msg_void1(window, 'setAppearance:', msg_id1(get_class('NSAppearance'), 'appearanceNamed:',
			nsstring(appearance)))
		mode := if i == 0 { 'light' } else { 'dark' }
		for j, state in states {
			g_update_controller.state = state
			width := state.pill_width(scale)
			msg_void_rect(pill, 'setFrame:', objc_rect(12, frame.height - 12 - update_pill_height,
				width, update_pill_height))
			msg_void_bool(pill, 'setNeedsDisplay:', true)
			msg_void_bool(badge, 'setNeedsDisplay:', true)
			name := '${mode}-${names[j]}-witty.png'
			if output.len > 0 {
				png := C.witty_overlay_test_png(view)
				assert !is_nil(png)
				assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(output, name)), ObjId(1))
			}
			if live.len > 0 {
				png := C.witty_overlay_test_window_png(window)
				assert !is_nil(png)
				assert msg_bool2(png, 'writeToFile:atomically:', nsstring(os.join_path(live, name)), ObjId(1))
			}
		}
	}
}

fn audit_load_sparkle() {
	path := os.getenv_opt('WITTY_SPARKLE_TEST_FRAMEWORK') or {
		os.join_path(@VMODROOT, '.witty-build', 'native', 'Sparkle.xcframework', 'macos-arm64_x86_64', 'Sparkle.framework')
	}
	bundle := msg_id1(get_class('NSBundle'), 'bundleWithPath:', nsstring(path))
	assert msg_bool(bundle, 'load')
}

struct UpdateProbeRecord {
	text string
	width string
	icon ?string
	badge ?string
	installable bool
}

fn test_original_swift_view_model_records() {
	states := [
		UpdateState{},
		UpdateState{kind: .permission_request},
		UpdateState{kind: .checking},
		UpdateState{kind: .update_available, version: '1.3.0'},
		UpdateState{kind: .not_found},
		UpdateState{kind: .error, error_description: 'Source error'},
		UpdateState{kind: .downloading},
		UpdateState{kind: .downloading, expected_length: 0},
		UpdateState{kind: .downloading, expected_length: 200, downloaded: 25},
		UpdateState{kind: .downloading, expected_length: 100, downloaded: 150},
		UpdateState{kind: .extracting, extraction_progress: 0.125},
		UpdateState{kind: .extracting, extraction_progress: 1.5},
		UpdateState{kind: .installing},
		UpdateState{kind: .installing, auto_update: true},
	]
	mut records := []UpdateProbeRecord{}
	for state in states { records << UpdateProbeRecord{state.text(), state.max_width_text(), state.icon_name(), state.badge(), state.is_installable()} }
	if path := os.getenv_opt('WITTY_UPDATER_MODEL_OUTPUT') { os.write_file(path, json2.encode(records, escape_unicode: true, time_as_unix: true))! }
}

fn test_original_update_state_text_equality_and_cancel_rules() {
	assert UpdateState{}.text() == ''
	assert UpdateState{kind: .permission_request}.text() == 'Enable Automatic Updates?'
	assert UpdateState{kind: .checking}.is_installable()
	assert !UpdateState{kind: .not_found}.is_installable()
	assert UpdateState{kind: .update_available, version: '1.3.0'}.text() == 'Update Available: 1.3.0'
	assert UpdateState{kind: .downloading, expected_length: 200, downloaded: 25}.text() == 'Downloading: 12%'
	assert UpdateState{kind: .downloading, expected_length: 0}.text() == 'Downloading…'
	assert UpdateState{kind: .extracting, extraction_progress: 0.5}.text() == 'Preparing: 50%'
	assert UpdateState{kind: .installing, auto_update: true}.text() == 'Restart to Complete Update'
	assert UpdateState{kind: .extracting, extraction_progress: 1.5}.badge()? == '150%'
	assert UpdateState{kind: .update_available, version: '1.3.0'}.equals(UpdateState{kind: .update_available, version: '1.3.0'})
	assert !UpdateState{kind: .error, error_description: 'a'}.equals(UpdateState{kind: .error, error_description: 'b'})
	assert !UpdateState{kind: .downloading, expected_length: none}.equals(UpdateState{kind: .downloading, expected_length: 0})
	C.witty_update_test_reset()
	choice := UpdateCallback{call: update_native_choice, context: C.witty_update_test_block(1)}
	UpdateState{kind: .update_available, reply: choice}.cancel()
	assert C.witty_update_test_value() == int(UpdateChoice.dismiss)
	UpdateState{kind: .update_available, reply: choice}.confirm()
	assert C.witty_update_test_value() == int(UpdateChoice.install)
	UpdateState{kind: .extracting, reply: choice}.confirm()
	assert C.witty_update_test_count() == 2
}

fn test_original_release_note_regex_order_and_urls() {
	url, label := update_release_notes('1.3.0', 'deadbeef')
	assert url == 'https://github.com/witty-terminal/witty/releases/tag/v1.3.0'
	assert label == 'View Release Notes'
	compare, _ := update_release_notes('1.3.0+abcdef123', 'deadbeef')
	assert compare == 'https://github.com/witty-terminal/witty/compare/deadbeef...abcdef123'
	commit, _ := update_release_notes('tip-abcdef123', '')
	assert commit == 'https://github.com/witty-terminal/witty/commit/abcdef123'
	missing, _ := update_release_notes('unversioned', '')
	assert missing == ''
}

fn test_native_update_install_chain_and_protocol_driver_callbacks() {
	app_init()
	audit_load_sparkle()
	view := create_window(640, 480, 'Updater audit')
	apply_native_window_config(view, NativeWindowConfig{}, true, 0, 1, false)
	// Use the real runtime-registered protocol implementation. Native blocks below
	// stand in only for the callbacks Sparkle hands to its SPUUserDriver.
	driver := msg_id(msg_id(register_update_driver(), 'alloc'), 'init')
	g_update_controller = &NativeUpdateController{driver: driver}
	defer { stop_native_updater(); close_tab(view) }
	C.witty_update_test_reset()
	block := ObjId(C.witty_update_test_block(1))
	msg_void1(driver, 'showUserInitiatedUpdateCheckWithCancellation:', ObjId(C.witty_update_test_block(0)))
	native_update_install()
	assert g_update_controller.is_installing()
	assert !termination_requires_confirmation(true)
	C.witty_update_message3(driver, sel('showUpdateFoundWithAppcastItem:state:reply:'), nil_obj(), nil_obj(), block)
	assert C.witty_update_test_count() == 1
	assert C.witty_update_test_value() == int(UpdateChoice.install)
	update_show_downloading(driver, sel(''), ObjId(C.witty_update_test_block(0)))
	msg_void_u64(driver, 'showDownloadDidReceiveExpectedContentLength:', 100)
	msg_void_u64(driver, 'showDownloadDidReceiveDataOfLength:', 42)
	assert native_update_text() == 'Downloading: 42%'
	update_download_expected(driver, sel(''), 200)
	assert native_update_text() == 'Downloading: 0%'
	update_start_extracting(driver, sel(''))
	update_extracting_progress(driver, sel(''), 0.75)
	assert native_update_text() == 'Preparing: 75%'
	msg_void1(driver, 'showReadyToInstallAndRelaunch:', block)
	assert C.witty_update_test_count() == 2
	assert update_install_on_quit(driver, sel(''), nil_obj(), nil_obj(), ObjId(C.witty_update_test_block(0)))
	assert native_update_text() == 'Restart to Complete Update'
	pill := g_update_controller.pills[u64(view_window(view))] or { panic('missing update pill') }
	assert msg_bool(pill, 'isHidden')
	update_show_installing(driver, sel(''), false, ObjId(C.witty_update_test_block(0)))
	assert native_update_text() == 'Installing…'
	assert !msg_bool(pill, 'isHidden')
	assert msg_rect(pill, 'frame').height == update_pill_height
	update_show_error(driver, sel(''), nil_obj(), ObjId(C.witty_update_test_block(0)))
	assert !g_update_controller.is_installing()
	assert !g_update_is_installing
	assert C.witty_update_test_count() == 3
	assert g_update_controller.pills.len == 1
	update_pill_action(driver, sel(''), g_update_controller.pills[u64(view_window(view))] or { panic('missing update pill') })
	assert msg_bool(g_update_controller.popover, 'isShown')
	assert native_update_is_available() == false
	update_will_relaunch(driver, sel(''), nil_obj())
	update_dismiss_installation(driver, sel(''))
	assert native_update_text() == ''
	C.witty_update_test_reset()
	update_show_not_found(driver, sel(''), nil_obj(), ObjId(C.witty_update_test_block(0)))
	update_show_not_found(driver, sel(''), nil_obj(), ObjId(C.witty_update_test_block(3)))
	update_reset_not_found(driver, sel(''), nil_obj())
	assert C.witty_update_test_count() == 1
	assert C.witty_update_test_value() == 0 // timer captures first equal notFound state
	update_show_not_found(driver, sel(''), nil_obj(), ObjId(C.witty_update_test_block(0)))
	update_show_not_found(driver, sel(''), nil_obj(), ObjId(C.witty_update_test_block(3)))
	update_pill_action(driver, sel(''), nil_obj())
	assert C.witty_update_test_value() == 44 // pill click acknowledges current state
	// The source's cancel retains its canceled installCancellable optional.
	update_show_checking(driver, sel(''), ObjId(C.witty_update_test_block(0)))
	native_update_install()
	g_update_controller.check_for_updates()
	g_update_controller.set_state(UpdateState{})
	assert g_update_controller.is_installing()
}

fn test_permission_reply_publishes_idle_before_native_response() {
	app_init()
	// Load the actual pinned Sparkle framework so the permission response is the
	// native SUUpdatePermissionResponse, rather than a test replacement class.
	audit_load_sparkle()
	driver := msg_id(msg_id(register_update_driver(), 'alloc'), 'init')
	g_update_controller = &NativeUpdateController{driver: driver}
	defer { stop_native_updater() }
	g_update_controller.set_state(UpdateState{kind: .permission_request, reply: UpdateCallback{call: update_native_permission, context: C.witty_update_test_block(2), owner: C.witty_update_weak_new(driver)}})
	g_update_controller.state.reply.invoke(1)
	assert g_update_controller.state.kind == .idle
	response := C.witty_update_test_object()
	assert msg_bool(response, 'automaticUpdateChecks')
	assert !msg_bool(response, 'sendSystemProfile')
	msg_void(response, 'release')
}

fn test_native_updater_requires_a_bundle_feed() {
	assert is_nil(update_feed_url(nil_obj(), sel(''), nil_obj()))
	start_native_updater(NativeUpdateConfig{auto_update: 0})!
	assert g_update_controller == unsafe { nil }
}

fn test_source_weak_callbacks_cannot_modify_replacement_controller() {
	app_init()
	audit_load_sparkle()
	first := msg_id(msg_id(register_update_driver(), 'alloc'), 'init')
	g_update_controller = &NativeUpdateController{driver: first}
	update_show_error(first, sel(''), nil_obj(), nil_obj())
	captured := retained_update_state(g_update_controller.state)
	stop_native_updater()
	second := msg_id(msg_id(register_update_driver(), 'alloc'), 'init')
	g_update_controller = &NativeUpdateController{driver: second}
	g_update_controller.set_state(UpdateState{kind: .checking})
	captured.dismiss.invoke(0)
	assert g_update_controller.state.kind == .checking
	release_update_state(captured)
	stop_native_updater()
}
