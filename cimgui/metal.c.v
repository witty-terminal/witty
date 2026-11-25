module cimgui

$if macos || ios {
	#flag -framework Metal

	fn C.ImGui_SetCurrentContext(voidptr)

	fn C.witty_cimgui_metal_init(device voidptr) bool

	fn C.witty_cimgui_metal_shutdown()

	fn C.witty_cimgui_metal_new_frame(descriptor voidptr)

	fn C.witty_cimgui_metal_render(command_buffer voidptr, descriptor voidptr)
	fn C.witty_cimgui_metal_update_textures(context voidptr) bool

	pub fn (ctx Context) metal_init(device voidptr) bool {
		C.ImGui_SetCurrentContext(ctx.handle)
		return C.witty_cimgui_metal_init(device)
	}

	pub fn (ctx Context) metal_shutdown() {
		C.ImGui_SetCurrentContext(ctx.handle)
		C.witty_cimgui_metal_shutdown()
	}

	pub fn (ctx Context) metal_new_frame(descriptor voidptr) {
		C.ImGui_SetCurrentContext(ctx.handle)
		C.witty_cimgui_metal_new_frame(descriptor)
	}

	pub fn (ctx Context) metal_render(command_buffer voidptr, descriptor voidptr) {
		C.ImGui_SetCurrentContext(ctx.handle)
		C.witty_cimgui_metal_render(command_buffer, descriptor)
	}

	pub fn (ctx Context) metal_update_textures() bool {
		return C.witty_cimgui_metal_update_textures(ctx.handle)
	}
}
