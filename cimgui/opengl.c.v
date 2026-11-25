module cimgui

$if renderer_opengl ?|| ( !renderer_metal ?&& !macos && !ios ) {
	fn C.witty_cimgui_opengl_init(context voidptr) bool

	fn C.witty_cimgui_opengl_shutdown(context voidptr)

	fn C.witty_cimgui_opengl_new_frame(context voidptr)

	fn C.witty_cimgui_opengl_render(context voidptr)

	pub fn (ctx Context) opengl_init() bool {
		return C.witty_cimgui_opengl_init(ctx.handle)
	}

	pub fn (ctx Context) opengl_shutdown() {
		C.witty_cimgui_opengl_shutdown(ctx.handle)
	}

	pub fn (ctx Context) opengl_new_frame() {
		C.witty_cimgui_opengl_new_frame(ctx.handle)
	}

	pub fn (ctx Context) opengl_render() {
		C.witty_cimgui_opengl_render(ctx.handle)
	}
}

$if linux && !renderer_metal ? {
	fn C.witty_cimgui_opengl_update_textures(context voidptr) bool

	pub fn (ctx Context) opengl_update_textures() bool {
		return C.witty_cimgui_opengl_update_textures(ctx.handle)
	}
}
