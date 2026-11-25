module opengl

fn C.witty_gl_test_resolver_pointer() voidptr

fn C.witty_gl_test_context_loaded() int

fn test_glad_custom_loader_lifecycle() {
	version := load(C.witty_gl_test_resolver_pointer()) or { panic(err) }
	assert version_major(version) == 4
	assert version_minor(version) == 3
	assert C.witty_gl_test_context_loaded() == 1
	get_error() or { panic(err) }
	viewport := viewport_rect() or { panic(err) }
	assert viewport == [7, 11, 640, 480]!
	unload()
	assert C.witty_gl_test_context_loaded() == 0
}

fn test_compile_surface() {
	// Compile-time smoke checks for translated pkg/opengl surface.
	_ = Primitive.triangle
	_ = BufferTarget.array
	_ = BufferUsage.dynamic_draw
	_ = TextureTarget.t2d
	_ = TextureParameter.min_filter
	_ = TextureInternalFormat.rgba
	_ = TextureFormat.rgba
	_ = TextureDataType.unsigned_byte
	_ = FramebufferTarget.framebuffer
	_ = FramebufferAttachment.color0
	_ = FramebufferStatus.complete
	_ = shader_type_vertex
	_ = shader_type_fragment
	_ = gl_float
	_ = gl_double
	_ = gl_half_float
	_ = gl_unsigned_int
	_ = BufferTarget.storage
}

fn test_native_enum_widths_match_ghostty_c_types() {
	assert sizeof(Primitive) == sizeof(i32)
	assert sizeof(BufferTarget) == sizeof(u32)
	assert sizeof(BufferUsage) == sizeof(u32)
	assert sizeof(TextureTarget) == sizeof(u32)
	assert sizeof(TextureParameter) == sizeof(u32)
	assert sizeof(TextureInternalFormat) == sizeof(i32)
	assert sizeof(TextureFormat) == sizeof(u32)
	assert sizeof(TextureMinFilter) == sizeof(i32)
	assert sizeof(TextureMagFilter) == sizeof(i32)
	assert sizeof(TextureWrap) == sizeof(i32)
	assert sizeof(TextureDataType) == sizeof(u32)
	assert sizeof(FramebufferTarget) == sizeof(u32)
	assert sizeof(FramebufferAttachment) == sizeof(u32)
	assert sizeof(FramebufferStatus) == sizeof(u32)
}

// Compile all generic Buffer.Binding translations without requiring a live GL
// context during the test.
fn compile_buffer_binding_generics(binding BufferBinding, data []u32) ! {
	binding.set_data(data, .dynamic_draw)!
	binding.set_sub_data(0, data)!
	value := u64(0)
	binding.set_data(&value, .dynamic_draw)!
	binding.set_sub_data(0, &value)!
	fixed := [4]f32{}
	binding.set_data(&fixed, .dynamic_draw)!
	binding.set_sub_data(0, &fixed)!
	binding.set_data_null[[4]f32](.dynamic_draw)!
	binding.attribute[[4]f32](0, 4, 1)!
	pixel_store(u32(C.GL_UNPACK_ALIGNMENT), u32(4))!
}
