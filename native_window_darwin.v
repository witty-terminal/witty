module main

import configpkg
import macos

fn native_window_config(config &configpkg.Config) macos.NativeWindowConfig {
	c := config.background
	// Ghostty.Config's title and windowTitleFontFamily getters use Swift's
	// repairing String(cString:), including its first-NUL boundary.
	return macos.NativeWindowConfig{title: if title := config.title { macos.source_c_utf8_repair(title) } else { none }, window_title_font_family: if family := config.window_title_font_family { macos.source_c_utf8_repair(family) } else { none }, decorations: config.window_decoration != .none_, position_x: config.window_position_x, position_y: config.window_position_y, buttons_hidden: config.macos_window_buttons == .hidden, shadow: config.macos_window_shadow, titlebar_style: int(config.macos_titlebar_style), theme: int(config.window_theme), background: u32(c.r) << 16 | u32(c.g) << 8 | c.b, opacity: config.background_opacity, blur: config.background_blur.cval(), step_resize: config.window_step_resize, proxy_icon: config.macos_titlebar_proxy_icon == .visible, preserve_split_zoom: config.split_preserve_zoom.navigation(), focus_follows_mouse: config.focus_follows_mouse, maximize: config.maximize
		unfocused_split_opacity: config.unfocused_split_opacity
		unfocused_split_fill: if fill := config.unfocused_split_fill {
			?u32(u32(fill.r) << 16 | u32(fill.g) << 8 | fill.b)
		} else { none }
	}
}
fn native_controller_config(current &TermState) macos.NativeWindowConfig {
	if current.controller != unsafe { nil } { return current.controller.app_config }
	return current.native_config
}
fn native_surface_appearance_config(current &TermState) macos.NativeWindowConfig {
	if current.controller == unsafe { nil } { return current.native_config }
	// TerminalWindow captures its own configuration on creation. Its controller
	// syncAppearance consumes only the focused SurfaceView.DerivedConfig fields.
	base := current.controller.creation_config
	return macos.NativeWindowConfig{...base, window_title_font_family: current.native_config.window_title_font_family, shadow: current.native_config.shadow, theme: current.native_config.theme, background: current.native_config.background, opacity: current.native_config.opacity, blur: current.native_config.blur}
}
fn sync_native_split_dimming(mut controller TerminalController) {
	if controller.host == unsafe { nil } { return }
	// Find and other native controls can temporarily own the first responder.
	focused := if controller.focused == unsafe { nil } { unsafe { nil } } else { controller.focused.view }
	controller.host.set_dimming(controller.app_config, focused)
}

fn sync_native_window(current &TermState) {
	if current.controller == unsafe { nil } { return }
	mut controller := current.controller
	sync_native_split_dimming(mut controller)
	if current.controller.quick {
		macos.sync_quick_terminal_appearance(current.controller.force_opaque)
		sync_native_surface_color_scheme(mut controller)
		return
	}
	focused := current.controller.focused
	if focused == unsafe { nil } { return }
	mut chosen := focused
	tree := current.controller.host.tree
	if node := tree.root.find(focused.view) {
		if !tree.borders(.up, node) {
			views := tree.root.leaves()
			if views.len > 0 {
				chosen = state_from_userdata(macos.view_get_userdata(views[0])) or { focused }
			}
		}
	}
	background := chosen.background_color or { chosen.native_config.background }
	// TerminalController.syncAppearance assigns the focused surface's family
	// before invoking TerminalWindow.syncAppearance, including while invisible.
	macos.set_native_window_title_font(focused.view, focused.native_config.window_title_font_family)
	macos.apply_native_window_config(focused.view, native_surface_appearance_config(focused), false, background, chosen.native_config.opacity, current.controller.force_opaque)
	// TerminalWindow's defer occurs after its isVisible guard; Quick Terminal
	// publishes before that guard instead.
	if macos.native_window_is_visible(macos.view_window(focused.view)) {
		sync_native_surface_color_scheme(mut controller)
	}
}
