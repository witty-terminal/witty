module main

import apprt
import input
import witty_macos as macos
import renderer

@[heap]
struct NativeInspectorBackend {
mut:
	inspector &apprt.TerminalInspector = unsafe { nil }
	gpu       renderer.GGInspectorMetal
}

fn native_inspector_callbacks() macos.NativeInspectorCallbacks {
	return macos.NativeInspectorCallbacks{ init: native_inspector_init, alive: native_inspector_alive, destroy: native_inspector_free, render: native_inspector_render, size: native_inspector_size, focus: native_inspector_focus, button: native_inspector_button, motion: native_inspector_motion, scroll: native_inspector_scroll, key: native_inspector_key, text: native_inspector_text }
}

fn native_inspector_init(userdata voidptr, device voidptr) voidptr {
	mut state := state_from_userdata(userdata) or { return unsafe { nil } }
	if state.closed || state.surface == unsafe { nil } { return unsafe { nil } }
	mut inspector := apprt.ghostty_surface_inspector(mut state.surface) or { return unsafe { nil } }
	if !apprt.ghostty_inspector_metal_init(mut inspector, device) {
		apprt.ghostty_inspector_free(mut state.surface)
		return unsafe { nil }
	}
	mut backend := &NativeInspectorBackend{ inspector: inspector }
	$if macos && !renderer_opengl ? {
		backend.gpu = renderer.GGInspectorMetal.acquire(device)
	}
	return voidptr(backend)
}

fn native_inspector_alive(userdata voidptr) bool {
	state := state_from_userdata(userdata) or { return false }
	return !state.closed && state.surface != unsafe { nil }
}

fn native_inspector_free(userdata voidptr, ptr voidptr) {
	if !isnil(ptr) {
		$if macos && !renderer_opengl ? {
			mut backend := unsafe { &NativeInspectorBackend(ptr) }
			backend.gpu.release()
		}
	}
	if mut state := state_from_userdata(userdata) {
		if state.surface != unsafe { nil } {
			apprt.ghostty_inspector_free(mut state.surface)
		}
	}
}

fn native_inspector_render(ptr voidptr, queue voidptr, descriptor voidptr, drawable voidptr) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	backend.inspector.prepare_metal_frame(descriptor) or { return }
	ctx := backend.inspector.context
	$if macos && !renderer_opengl ? {
		if _ := backend.gpu.render(ctx, descriptor, drawable) {
			return
		}
	}
	command := macos.metal_create_command_buffer(queue)
	if isnil(command) { return }
	macos.inspector_retain_fallback_frame(command, descriptor)
	ctx.metal_render(command, descriptor)
	macos.inspector_present_frame(command, drawable)
}

fn native_inspector_size(ptr voidptr, w u32, h u32, x f64, y f64) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	apprt.ghostty_inspector_set_content_scale(mut backend.inspector, x, y)
	apprt.ghostty_inspector_set_size(mut backend.inspector, w, h)
}

fn native_inspector_focus(ptr voidptr, focused bool) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	apprt.ghostty_inspector_set_focus(mut backend.inspector, focused)
}

fn native_inspector_button(ptr voidptr, action input.MouseButtonState, button input.MouseButton, mods int) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	apprt.ghostty_inspector_mouse_button(mut backend.inspector, action, button, mods)
}

fn native_inspector_motion(ptr voidptr, x f64, y f64) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	apprt.ghostty_inspector_mouse_pos(mut backend.inspector, x, y)
}

fn native_inspector_scroll(ptr voidptr, x f64, y f64, mods int) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	apprt.ghostty_inspector_mouse_scroll(mut backend.inspector, x, y, mods)
}

fn native_inspector_key(ptr voidptr, action input.KeyAction, key input.Key, mods int) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	apprt.ghostty_inspector_key(mut backend.inspector, action, key, mods)
}

fn native_inspector_text(ptr voidptr, value string) {
	mut backend := unsafe { &NativeInspectorBackend(ptr) }
	apprt.ghostty_inspector_text(mut backend.inspector, value)
}
