// C ABI adapters for Ghostty's embedded application and surface runtime.
// The internal apprt types remain idiomatic V; the structs in this file mirror
// include/witty.h at the pinned source revision byte-for-byte.

module main

import apprt
import benchmark
import configpkg
import input

pub struct RuntimeConfigC {
pub:
	userdata                     voidptr
	supports_selection_clipboard bool
	wakeup_cb                    fn (voidptr) = unsafe { nil }
	action_cb                    fn (voidptr, apprt.CAPITarget, apprt.CAPIAction) bool = unsafe { nil }
	read_clipboard_cb            fn (voidptr, int, &apprt.ClipboardRequest) = unsafe { nil }
	confirm_read_clipboard_cb    fn (voidptr, &char, &apprt.ClipboardRequest, int) = unsafe { nil }
	write_clipboard_cb           fn (voidptr, int, &apprt.CAPIClipboardContentC, uint, bool) = unsafe { nil }
	close_surface_cb             fn (voidptr, bool) = unsafe { nil }
}

pub struct InputKeyC {
pub:
	action              int
	mods                int
	consumed_mods       int
	keycode             u32
	text                &char = unsafe { nil }
	unshifted_codepoint u32
	composing           bool
}

pub struct EnvVarC {
pub:
	key   &char = unsafe { nil }
	value &char = unsafe { nil }
}

pub struct SurfaceConfigC {
pub mut:
	platform_tag       int
	platform           voidptr
	userdata           voidptr
	scale_factor       f64
	font_size          f32
	working_directory  &char = unsafe { nil }
	command            &char = unsafe { nil }
	env_vars           &EnvVarC = unsafe { nil }
	env_var_count      uint
	initial_input      &char = unsafe { nil }
	wait_after_command bool
	context            int
}

pub struct TextC {
pub mut:
	tl_px_x      f64
	tl_px_y      f64
	offset_start u32
	offset_len   u32
	text         &char = unsafe { nil }
	text_len     uint
}

pub struct PointC {
pub:
	tag   int
	coord int
	x     u32
	y     u32
}

pub struct SelectionC {
pub:
	top_left     PointC
	bottom_right PointC
	rectangle    bool
}

fn runtime_options_from_c(opts &RuntimeConfigC) apprt.AppOptions {
	return apprt.AppOptions{
		userdata: opts.userdata
		supports_selection_clipboard: opts.supports_selection_clipboard
		wakeup_cb: opts.wakeup_cb
		c_action_cb: opts.action_cb
		read_clipboard_cb: opts.read_clipboard_cb
		c_confirm_read_clipboard_cb: opts.confirm_read_clipboard_cb
		c_write_clipboard_cb: opts.write_clipboard_cb
		close_surface_cb: opts.close_surface_cb
	}
}

fn input_key_from_c(event InputKeyC) ?apprt.CAPIKeyEvent {
	action := match event.action {
		0 { input.KeyAction.release }
		1 { input.KeyAction.press }
		2 { input.KeyAction.repeat }
		else {
			return none
		}
	}
	text := if isnil(event.text) {
		none
	} else {
		unsafe { cstring_to_vstring(event.text) }
	}
	return apprt.CAPIKeyEvent{
		action: action
		mods: event.mods
		consumed_mods: event.consumed_mods
		keycode: event.keycode
		text: text
		unshifted_codepoint: event.unshifted_codepoint
		composing: event.composing
	}
}

fn optional_cstring(value &char) ?string {
	if isnil(value) {
		return none
	}
	return unsafe { cstring_to_vstring(value) }
}

// Run one of Ghostty's benchmark CLI actions. The implementation mirrors
// src/benchmark/CApi.zig: unknown actions and action failures return false.
@[export: 'ghostty_benchmark_cli']
fn ghostty_benchmark_cli_c(action_name &char, args &char) bool {
	if isnil(action_name) || isnil(args) {
		return false
	}
	action := unsafe { cstring_to_vstring(action_name) }
	argument_string := unsafe { cstring_to_vstring(args) }
	benchmark.run_cli(action, argument_string) or {
		eprintln('benchmark: failed to run action=${action} err=${err}')
		return false
	}
	return true
}

fn surface_options_from_c(opts &SurfaceConfigC) ?apprt.SurfaceOptions {
	if opts.context < 0 || opts.context > 2 || opts.platform_tag < 0 || opts.platform_tag > 2 {
		return none
	}
	mut env_vars := []apprt.EnvVar{cap: int(opts.env_var_count)}
	if opts.env_var_count > 0 && isnil(opts.env_vars) {
		return none
	}
	for idx in 0 .. int(opts.env_var_count) {
		entry := unsafe { opts.env_vars[idx] }
		if isnil(entry.key) || isnil(entry.value) {
			return none
		}
		env_vars << apprt.EnvVar{
			key: unsafe { cstring_to_vstring(entry.key) }
			value: unsafe { cstring_to_vstring(entry.value) }
		}
	}
	return apprt.SurfaceOptions{
		platform_tag: opts.platform_tag
		platform: apprt.PlatformC{
			nsview: opts.platform
			uiview: opts.platform
		}
		userdata: opts.userdata
		scale_factor: opts.scale_factor
		font_size: opts.font_size
		working_directory: optional_cstring(opts.working_directory)
		command: optional_cstring(opts.command)
		env_vars: env_vars
		initial_input: optional_cstring(opts.initial_input)
		wait_after_command: opts.wait_after_command
		context: unsafe { apprt.NewSurfaceContext(opts.context) }
	}
}

fn surface_options_to_c(mut surface apprt.Surface, opts apprt.SurfaceOptions) SurfaceConfigC {
	mut result := SurfaceConfigC{
		scale_factor: opts.scale_factor
		font_size: opts.font_size
		context: int(opts.context)
	}
	if working_directory := opts.working_directory {
		surface.capi_inherited_working_directory = working_directory.clone()
		result.working_directory = &char(surface.capi_inherited_working_directory.str)
	} else {
		surface.capi_inherited_working_directory = ''
	}
	return result
}

@[export: 'ghostty_app_new']
fn ghostty_app_new_c(opts &RuntimeConfigC, config voidptr) voidptr {
	if isnil(opts) || isnil(config) {
		return unsafe { nil }
	}
	internal_opts := runtime_options_from_c(opts)
	app := apprt.ghostty_app_new(&internal_opts, unsafe { &configpkg.Config(config) }) or {
		return unsafe { nil }
	}
	return voidptr(app)
}

@[export: 'ghostty_app_free']
fn ghostty_app_free_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut app := unsafe { &apprt.App(raw) }
	apprt.ghostty_app_free(mut app)
}

@[export: 'ghostty_app_tick']
fn ghostty_app_tick_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut app := unsafe { &apprt.App(raw) }
	apprt.ghostty_app_tick(mut app)
}

@[export: 'ghostty_app_userdata']
fn ghostty_app_userdata_c(raw voidptr) voidptr {
	if isnil(raw) {
		return unsafe { nil }
	}
	return apprt.ghostty_app_userdata(unsafe { &apprt.App(raw) })
}

@[export: 'ghostty_app_set_focus']
fn ghostty_app_set_focus_c(raw voidptr, focused bool) {
	if isnil(raw) {
		return
	}
	mut app := unsafe { &apprt.App(raw) }
	apprt.ghostty_app_set_focus(mut app, focused)
}

@[export: 'ghostty_app_key']
fn ghostty_app_key_c(raw voidptr, event InputKeyC) bool {
	if isnil(raw) {
		return false
	}
	key := input_key_from_c(event) or { return false }
	mut app := unsafe { &apprt.App(raw) }
	return apprt.ghostty_app_key(mut app, key)
}

@[export: 'ghostty_app_key_is_binding']
fn ghostty_app_key_is_binding_c(raw voidptr, event InputKeyC) bool {
	if isnil(raw) {
		return false
	}
	key := input_key_from_c(event) or { return false }
	return apprt.ghostty_app_key_is_binding(unsafe { &apprt.App(raw) }, key)
}

@[export: 'ghostty_app_keyboard_changed']
fn ghostty_app_keyboard_changed_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut app := unsafe { &apprt.App(raw) }
	apprt.ghostty_app_keyboard_changed(mut app)
}

@[export: 'ghostty_app_open_config']
fn ghostty_app_open_config_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut app := unsafe { &apprt.App(raw) }
	apprt.ghostty_app_open_config(mut app)
}

@[export: 'ghostty_app_update_config']
fn ghostty_app_update_config_c(raw voidptr, config voidptr) {
	if isnil(raw) || isnil(config) {
		return
	}
	mut app := unsafe { &apprt.App(raw) }
	apprt.ghostty_app_update_config(mut app, unsafe { &configpkg.Config(config) })
}

@[export: 'ghostty_app_needs_confirm_quit']
fn ghostty_app_needs_confirm_quit_c(raw voidptr) bool {
	return !isnil(raw) && apprt.ghostty_app_needs_confirm_quit(unsafe { &apprt.App(raw) })
}

@[export: 'ghostty_app_has_global_keybinds']
fn ghostty_app_has_global_keybinds_c(raw voidptr) bool {
	return !isnil(raw) && apprt.ghostty_app_has_global_keybinds(unsafe { &apprt.App(raw) })
}

@[export: 'ghostty_app_set_color_scheme']
fn ghostty_app_set_color_scheme_c(raw voidptr, scheme int) {
	if isnil(raw) {
		return
	}
	mut app := unsafe { &apprt.App(raw) }
	apprt.ghostty_app_set_color_scheme(mut app, scheme)
}

@[export: 'ghostty_surface_config_new']
fn ghostty_surface_config_new_c() SurfaceConfigC {
	return SurfaceConfigC{ scale_factor: 1.0 }
}

@[export: 'ghostty_surface_new']
fn ghostty_surface_new_c(app_raw voidptr, opts &SurfaceConfigC) voidptr {
	if isnil(app_raw) || isnil(opts) {
		return unsafe { nil }
	}
	internal_opts := surface_options_from_c(opts) or { return unsafe { nil } }
	mut app := unsafe { &apprt.App(app_raw) }
	surface := apprt.ghostty_surface_new(mut app, &internal_opts) or { return unsafe { nil } }
	return voidptr(surface)
}

@[export: 'ghostty_surface_free']
fn ghostty_surface_free_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_free(mut surface)
}

@[export: 'ghostty_surface_userdata']
fn ghostty_surface_userdata_c(raw voidptr) voidptr {
	if isnil(raw) {
		return unsafe { nil }
	}
	return apprt.ghostty_surface_userdata(unsafe { &apprt.Surface(raw) })
}

@[export: 'ghostty_surface_app']
fn ghostty_surface_app_c(raw voidptr) voidptr {
	if isnil(raw) {
		return unsafe { nil }
	}
	return voidptr(apprt.ghostty_surface_app(unsafe { &apprt.Surface(raw) }))
}

@[export: 'ghostty_surface_inherited_config']
fn ghostty_surface_inherited_config_c(raw voidptr, source int) SurfaceConfigC {
	if isnil(raw) || source < 0 || source > 2 {
		return SurfaceConfigC{ scale_factor: 1.0 }
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	opts := apprt.ghostty_surface_inherited_config(surface, unsafe { apprt.NewSurfaceContext(source) })
	return surface_options_to_c(mut surface, opts)
}

@[export: 'ghostty_surface_update_config']
fn ghostty_surface_update_config_c(raw voidptr, config voidptr) {
	if isnil(raw) || isnil(config) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_update_config(mut surface, unsafe { &configpkg.Config(config) })
}

@[export: 'ghostty_surface_needs_confirm_quit']
fn ghostty_surface_needs_confirm_quit_c(raw voidptr) bool {
	return !isnil(raw) && apprt.ghostty_surface_needs_confirm_quit(unsafe { &apprt.Surface(raw) })
}

@[export: 'ghostty_surface_process_exited']
fn ghostty_surface_process_exited_c(raw voidptr) bool {
	return !isnil(raw) && apprt.ghostty_surface_process_exited(unsafe { &apprt.Surface(raw) })
}

@[export: 'ghostty_surface_refresh']
fn ghostty_surface_refresh_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_refresh(mut surface)
}

@[export: 'ghostty_surface_draw']
fn ghostty_surface_draw_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_draw(mut surface)
}

@[export: 'ghostty_surface_set_content_scale']
fn ghostty_surface_set_content_scale_c(raw voidptr, x f64, y f64) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_set_content_scale(mut surface, x, y)
}

@[export: 'ghostty_surface_set_focus']
fn ghostty_surface_set_focus_c(raw voidptr, focused bool) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_set_focus(mut surface, focused)
}

@[export: 'ghostty_surface_set_occlusion']
fn ghostty_surface_set_occlusion_c(raw voidptr, visible bool) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_set_occlusion(mut surface, visible)
}

@[export: 'ghostty_surface_set_size']
fn ghostty_surface_set_size_c(raw voidptr, width u32, height u32) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_set_size(mut surface, width, height)
}

@[export: 'ghostty_surface_size']
fn ghostty_surface_size_c(raw voidptr) apprt.CAPISurfaceSize {
	if isnil(raw) {
		return apprt.CAPISurfaceSize{}
	}
	return apprt.ghostty_surface_size(unsafe { &apprt.Surface(raw) })
}

@[export: 'ghostty_surface_set_color_scheme']
fn ghostty_surface_set_color_scheme_c(raw voidptr, scheme int) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_set_color_scheme(mut surface, scheme)
}

@[export: 'ghostty_surface_key_translation_mods']
fn ghostty_surface_key_translation_mods_c(raw voidptr, mods int) int {
	if isnil(raw) {
		return mods
	}
	return apprt.ghostty_surface_key_translation_mods(unsafe { &apprt.Surface(raw) }, mods)
}

@[export: 'ghostty_surface_key']
fn ghostty_surface_key_c(raw voidptr, event InputKeyC) bool {
	if isnil(raw) {
		return false
	}
	key := input_key_from_c(event) or { return false }
	mut surface := unsafe { &apprt.Surface(raw) }
	return apprt.ghostty_surface_key(mut surface, key)
}

@[export: 'ghostty_surface_key_is_binding']
fn ghostty_surface_key_is_binding_c(raw voidptr, event InputKeyC, flags &u32) bool {
	if isnil(raw) {
		return false
	}
	key := input_key_from_c(event) or { return false }
	mut surface := unsafe { &apprt.Surface(raw) }
	value := apprt.ghostty_surface_key_binding_flags(mut surface, key) or { return false }
	if !isnil(flags) {
		unsafe { *flags = value }
	}
	return true
}

@[export: 'ghostty_surface_text']
fn ghostty_surface_text_c(raw voidptr, ptr &u8, len uint) {
	if isnil(raw) || (isnil(ptr) && len > 0) {
		return
	}
	mut text := ''
	if len > 0 {
		text = unsafe { tos(ptr, int(len)) }
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_text(mut surface, text)
}

@[export: 'ghostty_surface_preedit']
fn ghostty_surface_preedit_c(raw voidptr, ptr &u8, len uint) {
	if isnil(raw) || (isnil(ptr) && len > 0) {
		return
	}
	text := if len == 0 { none } else { ?string(unsafe { tos(ptr, int(len)) }) }
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_preedit(mut surface, text)
}

@[export: 'ghostty_surface_mouse_captured']
fn ghostty_surface_mouse_captured_c(raw voidptr) bool {
	return !isnil(raw) && apprt.ghostty_surface_mouse_captured(unsafe { &apprt.Surface(raw) })
}

@[export: 'ghostty_surface_mouse_button']
fn ghostty_surface_mouse_button_c(raw voidptr, action int, button int, mods int) bool {
	if isnil(raw) || action < 0 || action > 1 || button < 0 || button > input.mouse_button_max {
		return false
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	return apprt.ghostty_surface_mouse_button(mut surface, unsafe { input.MouseButtonState(action) }, unsafe { input.MouseButton(button) }, mods)
}

@[export: 'ghostty_surface_mouse_pos']
fn ghostty_surface_mouse_pos_c(raw voidptr, x f64, y f64, mods int) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_mouse_pos(mut surface, x, y, mods)
}

@[export: 'ghostty_surface_mouse_scroll']
fn ghostty_surface_mouse_scroll_c(raw voidptr, x f64, y f64, scroll_mods int) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_mouse_scroll(mut surface, x, y, scroll_mods)
}

@[export: 'ghostty_surface_mouse_pressure']
fn ghostty_surface_mouse_pressure_c(raw voidptr, stage u32, pressure f64) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_mouse_pressure(mut surface, stage, pressure)
}

@[export: 'ghostty_surface_ime_point']
fn ghostty_surface_ime_point_c(raw voidptr, x &f64, y &f64, width &f64, height &f64) {
	if isnil(raw) || isnil(x) || isnil(y) || isnil(width) || isnil(height) {
		return
	}
	apprt.ghostty_surface_ime_point(unsafe { &apprt.Surface(raw) }, x, y, width, height)
}

@[export: 'ghostty_surface_request_close']
fn ghostty_surface_request_close_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_request_close(mut surface)
}

@[export: 'ghostty_surface_split']
fn ghostty_surface_split_c(raw voidptr, direction int) {
	if isnil(raw) || direction < 0 || direction > 3 {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_split(mut surface, unsafe { apprt.SplitDirection(direction) })
}

@[export: 'ghostty_surface_split_focus']
fn ghostty_surface_split_focus_c(raw voidptr, direction int) {
	if isnil(raw) || direction < 0 || direction > 5 {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_split_focus(mut surface, unsafe { apprt.GotoSplit(direction) })
}

@[export: 'ghostty_surface_split_resize']
fn ghostty_surface_split_resize_c(raw voidptr, direction int, amount u16) {
	if isnil(raw) || direction < 0 || direction > 3 {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_split_resize(mut surface, unsafe { apprt.ResizeSplitDirection(direction) }, amount)
}

@[export: 'ghostty_surface_split_equalize']
fn ghostty_surface_split_equalize_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_surface_split_equalize(mut surface)
}

@[export: 'ghostty_surface_binding_action']
fn ghostty_surface_binding_action_c(raw voidptr, ptr &u8, len uint) bool {
	if isnil(raw) || (isnil(ptr) && len > 0) {
		return false
	}
	mut action := ''
	if len > 0 {
		action = unsafe { tos(ptr, int(len)) }
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	return apprt.ghostty_surface_binding_action(mut surface, action)
}

@[export: 'ghostty_surface_complete_clipboard_request']
fn ghostty_surface_complete_clipboard_request_c(raw voidptr, text_ptr &char, state voidptr, confirmed bool) {
	if isnil(raw) || isnil(text_ptr) || isnil(state) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	text_value := unsafe { cstring_to_vstring(text_ptr) }
	apprt.ghostty_surface_complete_clipboard_request(mut surface, text_value, unsafe { &apprt.ClipboardRequest(state) }, confirmed)
}

fn text_to_c(value apprt.CAPIText, mut result TextC) bool {
	text_value := value.text or { return false }
	raw := unsafe { malloc(text_value.len + 1) }
	if isnil(raw) {
		return false
	}
	if text_value.len > 0 {
		unsafe { vmemcpy(raw, text_value.str, text_value.len) }
	}
	unsafe { (&u8(raw))[text_value.len] = 0 }
	result.tl_px_x = value.tl_px_x
	result.tl_px_y = value.tl_px_y
	result.offset_start = value.offset_start
	result.offset_len = value.offset_len
	result.text = unsafe { &char(raw) }
	result.text_len = uint(text_value.len)
	return true
}

@[export: 'ghostty_surface_has_selection']
fn ghostty_surface_has_selection_c(raw voidptr) bool {
	return !isnil(raw) && apprt.ghostty_surface_has_selection(unsafe { &apprt.Surface(raw) })
}

@[export: 'ghostty_surface_read_selection']
fn ghostty_surface_read_selection_c(raw voidptr, result &TextC) bool {
	if isnil(raw) || isnil(result) {
		return false
	}
	mut value := apprt.CAPIText{}
	mut surface := unsafe { &apprt.Surface(raw) }
	if !apprt.ghostty_surface_read_selection(mut surface, mut value) {
		return false
	}
	mut output := unsafe { &TextC(result) }
	return text_to_c(value, mut output)
}

@[export: 'ghostty_surface_read_text']
fn ghostty_surface_read_text_c(raw voidptr, selection SelectionC, result &TextC) bool {
	if isnil(raw) || isnil(result) {
		return false
	}
	if selection.top_left.tag < 0 || selection.top_left.tag > 3
		|| selection.bottom_right.tag < 0 || selection.bottom_right.tag > 3
		|| selection.top_left.coord < 0 || selection.top_left.coord > 2
		|| selection.bottom_right.coord < 0 || selection.bottom_right.coord > 2 {
		return false
	}
	internal_selection := apprt.CAPISelection{
		tl: apprt.CAPIPoint{
			tag: unsafe { apprt.CAPIPointTag(selection.top_left.tag) }
			coord_tag: unsafe { apprt.CAPICoordTag(selection.top_left.coord) }
			x: selection.top_left.x
			y: selection.top_left.y
		}
		br: apprt.CAPIPoint{
			tag: unsafe { apprt.CAPIPointTag(selection.bottom_right.tag) }
			coord_tag: unsafe { apprt.CAPICoordTag(selection.bottom_right.coord) }
			x: selection.bottom_right.x
			y: selection.bottom_right.y
		}
		rectangle: selection.rectangle
	}
	mut value := apprt.CAPIText{}
	mut surface := unsafe { &apprt.Surface(raw) }
	if !apprt.ghostty_surface_read_text(mut surface, internal_selection, mut value) {
		return false
	}
	mut output := unsafe { &TextC(result) }
	return text_to_c(value, mut output)
}

@[export: 'ghostty_surface_free_text']
fn ghostty_surface_free_text_c(_ voidptr, result &TextC) {
	if isnil(result) {
		return
	}
	mut output := unsafe { &TextC(result) }
	if !isnil(output.text) {
		unsafe { free(output.text) }
	}
	output.text = unsafe { nil }
	output.text_len = 0
}

@[export: 'ghostty_surface_inspector']
fn ghostty_surface_inspector_c(raw voidptr) voidptr {
	if isnil(raw) {
		return unsafe { nil }
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	inspector := apprt.ghostty_surface_inspector(mut surface) or { return unsafe { nil } }
	return voidptr(inspector)
}

@[export: 'ghostty_inspector_free']
fn ghostty_inspector_free_c(raw voidptr) {
	if isnil(raw) {
		return
	}
	mut surface := unsafe { &apprt.Surface(raw) }
	apprt.ghostty_inspector_free(mut surface)
}

@[export: 'ghostty_inspector_set_focus']
fn ghostty_inspector_set_focus_c(raw voidptr, focused bool) {
	if isnil(raw) {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_set_focus(mut inspector, focused)
}

@[export: 'ghostty_inspector_set_content_scale']
fn ghostty_inspector_set_content_scale_c(raw voidptr, x f64, y f64) {
	if isnil(raw) {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_set_content_scale(mut inspector, x, y)
}

@[export: 'ghostty_inspector_set_size']
fn ghostty_inspector_set_size_c(raw voidptr, width u32, height u32) {
	if isnil(raw) {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_set_size(mut inspector, width, height)
}

@[export: 'ghostty_inspector_mouse_button']
fn ghostty_inspector_mouse_button_c(raw voidptr, action int, button int, mods int) {
	if isnil(raw) || action < 0 || action > 1 || button < 0 || button > input.mouse_button_max {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_mouse_button(mut inspector, unsafe { input.MouseButtonState(action) }, unsafe { input.MouseButton(button) }, mods)
}

@[export: 'ghostty_inspector_mouse_pos']
fn ghostty_inspector_mouse_pos_c(raw voidptr, x f64, y f64) {
	if isnil(raw) {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_mouse_pos(mut inspector, x, y)
}

@[export: 'ghostty_inspector_mouse_scroll']
fn ghostty_inspector_mouse_scroll_c(raw voidptr, x f64, y f64, scroll_mods int) {
	if isnil(raw) {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_mouse_scroll(mut inspector, x, y, scroll_mods)
}

@[export: 'ghostty_inspector_key']
fn ghostty_inspector_key_c(raw voidptr, action int, key int, mods int) {
	if isnil(raw) || action < 0 || action > 2 || key < 0 {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_key(mut inspector, unsafe { input.KeyAction(action) }, unsafe { input.Key(key) }, mods)
}

@[export: 'ghostty_inspector_text']
fn ghostty_inspector_text_c(raw voidptr, text_ptr &char) {
	if isnil(raw) || isnil(text_ptr) {
		return
	}
	mut inspector := unsafe { &apprt.TerminalInspector(raw) }
	apprt.ghostty_inspector_text(mut inspector, unsafe { cstring_to_vstring(text_ptr) })
}

@[export: 'ghostty_set_window_background_blur']
fn ghostty_set_window_background_blur_c(app_raw voidptr, window voidptr) {
	if isnil(app_raw) || isnil(window) {
		return
	}
	apprt.ghostty_set_window_background_blur(unsafe { &apprt.App(app_raw) }, window)
}
