@[has_globals]
module witty_macos

// SurfaceView_AppKit title publication/prompt and BaseTerminalController tab
// title prompt. Native sheets preserve editing focus and cancellation.
@[heap]
struct NativeTitlePrompt {
mut:
	surface  &NativeActionSurface = unsafe { nil }
	alert    ObjId
	field    ObjId
	tab      bool
	response i64
}

__global g_title_prompts = map[u64]&NativeTitlePrompt{}

fn register_action_title_methods(cls ObjId) {
	add_method(cls, 'titleTimer:', voidptr(action_title_timer), 'v@:@')
	add_method(cls, 'titleFallback:', voidptr(action_title_fallback), 'v@:@')
}

pub fn (mut surface NativeActionSurface) set_title(title string) {
	if surface.closed { return }
	if !is_nil(surface.title_timer) { msg_void(surface.title_timer, 'invalidate') }
	surface.pending_title = title.clone()
	surface.title_timer = C.witty_action_timer(0.075, surface.owner, sel('titleTimer:'), nil_obj(),
		false)
}

fn action_title_timer(self ObjId, _cmd Sel, _timer ObjId) {
	mut surface := action_owner_state(self) or { return }
	surface.title_timer = nil_obj()
	if surface.closed { return }
	if surface.terminal_title != none {
		surface.terminal_title = surface.pending_title.clone()
		return
	}
	surface.title = surface.pending_title.clone()
	surface.publish_title()
}

fn action_title_fallback(self ObjId, _cmd Sel, _timer ObjId) {
	mut surface := action_owner_state(self) or { return }
	surface.title_fallback = nil_obj()
	if !surface.closed && surface.title.len == 0 {
		surface.title = '👻'
		surface.publish_title()
	}
}

fn (mut surface NativeActionSurface) publish_title() {
	invalidate_native_restorable_state(surface.view)
	if surface.title.len > 0 && !is_nil(surface.title_fallback) {
		msg_void(surface.title_fallback, 'invalidate')
		surface.title_fallback = nil_obj()
	}
	if surface.callbacks.title != unsafe { nil } {
		surface.callbacks.title(surface.userdata, surface.title)
	}
}

pub fn (mut surface NativeActionSurface) prompt_title(tab bool, current_title string) {
	if surface.closed { return }
	alert := new_obj('NSAlert')
	msg_void1(alert, 'setMessageText:', nsstring(if tab {
		'Change Tab Title'
	} else {
		'Change Terminal Title'
	}))
	msg_void1(alert, 'setInformativeText:', nsstring('Leave blank to restore the default.'))
	msg_void_u64(alert, 'setAlertStyle:', 1)
	field := msg_id_rect(alloc('NSTextField'), 'initWithFrame:', objc_rect(0, 0, 250, 24))
	msg_void1(field, 'setStringValue:', nsstring(current_title))
	msg_void1(alert, 'setAccessoryView:', field)
	msg_id1(alert, 'addButtonWithTitle:', nsstring('OK'))
	msg_id1(alert, 'addButtonWithTitle:', nsstring('Cancel'))
	msg_void1(msg_id(alert, 'window'), 'setInitialFirstResponder:', field)
	prompt := &NativeTitlePrompt{
		surface: &surface
		alert:   alert
		field:   field
		tab:     tab
	}
	g_title_prompts[u64(prompt)] = prompt
	window := view_window(surface.view)
	if !is_nil(window) {
		C.witty_action_sheet(alert, window, voidptr(title_prompt_response), voidptr(prompt))
	} else {
		title_prompt_response(voidptr(prompt), nil_obj(), msg_i64(alert, 'runModal'), false)
	}
}

fn title_prompt_response(context voidptr, _error ObjId, response i64, _granted bool) {
	mut prompt := unsafe { &NativeTitlePrompt(context) }
	prompt.response = response
	dispatch_main(title_prompt_complete, context)
}

fn title_prompt_complete(context voidptr) {
	mut prompt := unsafe { &NativeTitlePrompt(context) }
	defer {
		msg_void(prompt.field, 'release')
		msg_void(prompt.alert, 'release')
		g_title_prompts.delete(u64(prompt))
	}
	if prompt.surface.closed || prompt.response != 1000 { return }
	value := objc_utf8_string(msg_id(prompt.field, 'stringValue'))
	if prompt.tab {
		if prompt.surface.callbacks.tab_title != unsafe { nil } {
			prompt.surface.callbacks.tab_title(prompt.surface.userdata, if value.len > 0 {
				?string(value)
			} else {
				none
			})
		}
	} else if value.len == 0 {
		previous := prompt.surface.terminal_title or { '👻' }
		prompt.surface.terminal_title = none
		prompt.surface.set_title(previous)
	} else {
		prompt.surface.terminal_title = prompt.surface.title.clone()
		prompt.surface.title = value
		prompt.surface.publish_title()
	}
}

pub fn (mut surface NativeActionSurface) set_pwd(pwd string, proxy_icon bool) {
	surface.proxy_icon = proxy_icon
	surface.pwd = pwd.clone()
	invalidate_native_restorable_state(surface.view)
	if surface.focused {
		url := if proxy_icon {
			msg_id1(get_class('NSURL'), 'fileURLWithPath:', nsstring(pwd))
		} else {
			nil_obj()
		}
		msg_void1(view_window(surface.view), 'setRepresentedURL:', url)
	}
}

pub fn native_window_title(view voidptr) string {
	return objc_utf8_string(msg_id(view_window(view), 'title'))
}

// SurfaceView Codable retains whether terminal titles are currently overridden.
pub fn (surface &NativeActionSurface) saved_surface_title() (?string, bool) {
	return if surface.title.len > 0 { ?string(surface.title) } else { none }, surface.terminal_title != none
}

pub fn (mut surface NativeActionSurface) restore_surface_title(title ?string, user_set bool) {
	if value := title {
		surface.title = value.clone()
		surface.terminal_title = if user_set { ?string(value.clone()) } else { none }
		surface.publish_title()
	}
}

pub fn (surface &NativeActionSurface) saved_pwd() ?string { return surface.pwd }

pub fn (mut surface NativeActionSurface) restore_pwd(pwd ?string, proxy_icon bool) {
	if value := pwd { surface.set_pwd(value, proxy_icon) }
}

pub fn abbreviated_pwd(pwd string) string {
	return objc_utf8_string(msg_id(nsstring(pwd), 'stringByAbbreviatingWithTildeInPath'))
}

pub fn (mut surface NativeActionSurface) configure_title(proxy_icon bool) {
	surface.proxy_icon = proxy_icon
	if surface.focused {
		if pwd := surface.pwd { surface.set_pwd(pwd, proxy_icon) }
	}
}
