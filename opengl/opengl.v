module opengl

import log

// Translated from:
// - ghostty/pkg/opengl/main.zig
// - ghostty/pkg/opengl/c.zig
// - ghostty/pkg/opengl/glad.zig
// - ghostty/pkg/opengl/errors.zig
// - ghostty/pkg/opengl/extensions.zig
// - ghostty/pkg/opengl/primitives.zig
// - ghostty/pkg/opengl/draw.zig
// - ghostty/pkg/opengl/Buffer.zig
// - ghostty/pkg/opengl/Texture.zig
// - ghostty/pkg/opengl/VertexArray.zig
// - ghostty/pkg/opengl/Shader.zig
// - ghostty/pkg/opengl/Program.zig
// - ghostty/pkg/opengl/Framebuffer.zig
// - ghostty/pkg/opengl/Renderbuffer.zig
// - ghostty/pkg/opengl/Sampler.zig
// - ghostty/pkg/opengl/build.zig

#flag darwin -framework OpenGL

#flag linux -lGL

#flag linux -ldl

#flag freebsd -lGL

#flag freebsd -ldl

#flag windows -lopengl32

#flag -I @VMODROOT/opengl

$if !managed_native ? {
	#flag @VMODROOT/opengl/glad.c
	#flag @VMODROOT/opengl/gl_dispatch.c
}

#insert "@VMODROOT/opengl/gl_headers.h"

fn C.witty_gl_load(get_proc_address voidptr) int

fn C.witty_gl_unload()

fn C.witty_glGetError() u32

fn C.witty_glGetIntegerv(pname u32, data &int)

fn C.witty_glGetStringi(name u32, index u32) &u8

fn C.witty_glClearColor(red f32, green f32, blue f32, alpha f32)

fn C.witty_glClear(mask u32)

fn C.witty_glDrawArrays(mode u32, first int, count int)

fn C.witty_glDrawArraysInstanced(mode u32, first int, count int, primcount int)

fn C.witty_glDrawElements(mode u32, count int, typ u32, indices voidptr)

fn C.witty_glDrawElementsInstanced(mode u32, count int, typ u32, indices voidptr, primcount int)

fn C.witty_glEnable(cap u32)

fn C.witty_glDisable(cap u32)

fn C.witty_glFrontFace(mode u32)

fn C.witty_glBlendFunc(sfactor u32, dfactor u32)

fn C.witty_glViewport(x int, y int, width int, height int)

fn C.witty_glPixelStorei(mode u32, param int)

fn C.witty_glFinish()

fn C.witty_glFlush()

fn C.witty_glGenBuffers(n int, buffers &u32)

fn C.witty_glBindBuffer(target u32, buffer u32)

fn C.witty_glDeleteBuffers(n int, buffers &u32)

fn C.witty_glBindBufferBase(target u32, index u32, buffer u32)

fn C.witty_glBufferData(target u32, size int, data voidptr, usage u32)

fn C.witty_glBufferSubData(target u32, offset int, size int, data voidptr)

fn C.witty_glVertexAttribPointer(index u32, size int, typ u32, normalized u8, stride int, pointer voidptr)

fn C.witty_glVertexAttribIPointer(index u32, size int, typ u32, stride int, pointer voidptr)

fn C.witty_glEnableVertexAttribArray(index u32)

fn C.witty_glVertexAttribDivisor(index u32, divisor u32)

fn C.witty_glVertexBindingDivisor(bindingindex u32, divisor u32) int

fn C.witty_glVertexAttribBinding(attribindex u32, bindingindex u32) int

fn C.witty_glVertexAttribFormat(attribindex u32, size int, typ u32, normalized u8, relativeoffset u32) int

fn C.witty_glVertexAttribIFormat(attribindex u32, size int, typ u32, relativeoffset u32) int

fn C.witty_glVertexAttribLFormat(attribindex u32, size int, typ u32, relativeoffset u32) int

fn C.witty_glBindVertexBuffer(bindingindex u32, buffer u32, offset int, stride int) int

fn C.witty_glActiveTexture(texture u32)

fn C.witty_glGenTextures(n int, textures &u32)

fn C.witty_glBindTexture(target u32, texture u32)

fn C.witty_glDeleteTextures(n int, textures &u32)

fn C.witty_glGenerateMipmap(target u32)

fn C.witty_glTexParameteri(target u32, pname u32, param int)

fn C.witty_glTexImage2D(target u32, level int, internalformat int, width int, height int, border int, format u32, typ u32, pixels voidptr)

fn C.witty_glTexSubImage2D(target u32, level int, xoffset int, yoffset int, width int, height int, format u32, typ u32, pixels voidptr)

fn C.witty_glCopyTexSubImage2D(target u32, level int, xoffset int, yoffset int, x int, y int, width int, height int)

fn C.witty_glGenVertexArrays(n int, arrays &u32)

fn C.witty_glBindVertexArray(array u32)

fn C.witty_glDeleteVertexArrays(n int, arrays &u32)

fn C.witty_glCreateShader(typ u32) u32

fn C.witty_glShaderSource(shader u32, count int, string &&u8, length &int)

fn C.witty_glCompileShader(shader u32)

fn C.witty_glGetShaderiv(shader u32, pname u32, params &int)

fn C.witty_glGetShaderInfoLog(shader u32, max_length int, length &int, info_log &u8)

fn C.witty_glDeleteShader(shader u32)

fn C.witty_glCreateProgram() u32

fn C.witty_glDeleteProgram(program u32)

fn C.witty_glAttachShader(program u32, shader u32)

fn C.witty_glLinkProgram(program u32)

fn C.witty_glGetProgramiv(program u32, pname u32, params &int)

fn C.witty_glGetProgramInfoLog(program u32, max_length int, length &int, info_log &u8)

fn C.witty_glUseProgram(program u32)

fn C.witty_glUniformBlockBinding(program u32, index u32, binding u32)

fn C.witty_glGetUniformLocation(program u32, name &u8) int

fn C.witty_glUniform1i(location int, v0 int)

fn C.witty_glUniform1f(location int, v0 f32)

fn C.witty_glUniform2f(location int, v0 f32, v1 f32)

fn C.witty_glUniform3f(location int, v0 f32, v1 f32, v2 f32)

fn C.witty_glUniform4f(location int, v0 f32, v1 f32, v2 f32, v3 f32)

fn C.witty_glUniformMatrix4fv(location int, count int, transpose u8, value &f32)

fn C.witty_glGenFramebuffers(n int, ids &u32)

fn C.witty_glDeleteFramebuffers(n int, framebuffers &u32)

fn C.witty_glBindFramebuffer(target u32, framebuffer u32)

fn C.witty_glFramebufferTexture2D(target u32, attachment u32, textarget u32, texture u32, level int)

fn C.witty_glFramebufferRenderbuffer(target u32, attachment u32, renderbuffertarget u32, renderbuffer u32)

fn C.witty_glDrawBuffers(n int, bufs &u32)

fn C.witty_glCheckFramebufferStatus(target u32) u32

fn C.witty_glBlitFramebuffer(src_x0 int, src_y0 int, src_x1 int, src_y1 int, dst_x0 int, dst_y0 int, dst_x1 int, dst_y1 int, mask u32, filter u32) int

fn C.witty_glDebugMessageCallback(callback voidptr, user_param voidptr) int

fn C.witty_glGenRenderbuffers(n int, renderbuffers &u32)

fn C.witty_glDeleteRenderbuffers(n int, renderbuffers &u32)

fn C.witty_glBindRenderbuffer(target u32, renderbuffer u32)

fn C.witty_glRenderbufferStorage(target u32, internalformat u32, width int, height int)

fn C.witty_glGenSamplers(n int, samplers &u32)

fn C.witty_glBindSampler(unit u32, sampler u32)

fn C.witty_glSamplerParameteri(sampler u32, pname u32, param int)

fn C.witty_glDeleteSamplers(n int, samplers &u32)

// ============================================================
// glad.zig compatibility
// ============================================================

// load initializes the pinned Glad thread-local context. A null resolver uses
// Glad's platform loader; a non-null resolver follows gladLoadGLContext.
pub fn load(get_proc_address voidptr) !u32 {
	result := C.witty_gl_load(get_proc_address)
	if result == 0 {
		return error('GLInitFailed')
	}
	return u32(result)
}

// unload releases the platform loader owned by the current Glad context and
// invalidates that context, matching Ghostty's glad.unload lifecycle.
pub fn unload() {
	C.witty_gl_unload()
}

pub fn version_major(res u32) u32 {
	return res / 10_000
}

pub fn version_minor(res u32) u32 {
	return res % 10_000
}

// ============================================================
// errors.zig
// ============================================================

pub fn get_error() ! {
	code := int(C.witty_glGetError())
	match code {
		C.GL_NO_ERROR {}
		C.GL_INVALID_ENUM {
			return error('InvalidEnum')
		}
		C.GL_INVALID_VALUE {
			return error('InvalidValue')
		}
		C.GL_INVALID_OPERATION {
			return error('InvalidOperation')
		}
		C.GL_INVALID_FRAMEBUFFER_OPERATION {
			return error('InvalidFramebufferOperation')
		}
		C.GL_OUT_OF_MEMORY {
			return error('OutOfMemory')
		}
		else {
			return error('Unknown')
		}
	}
}

pub fn must_error() ! {
	get_error()!
	return error('Unknown')
}

// ============================================================
// extensions.zig
// ============================================================

pub fn extensions_len() !u32 {
	mut n := int(0)
	C.witty_glGetIntegerv(C.GL_NUM_EXTENSIONS, &n)
	get_error()!
	return u32(n)
}

pub struct ExtensionIterator {
pub mut:
	len u32
	i   u32
}

pub fn extensions_iterator() !ExtensionIterator {
	return ExtensionIterator{
		len: extensions_len()!
		i: 0
	}
}

// ExtensionNextResult preserves Ghostty's `!?[]const u8` return contract. V
// cannot combine an optional value with an error result directly, so
// `value == none` represents the exhausted iterator.
pub struct ExtensionNextResult {
pub:
	value ?string
}

pub fn (mut it ExtensionIterator) next() !ExtensionNextResult {
	if it.i >= it.len {
		return ExtensionNextResult{}
	}
	ptr := C.witty_glGetStringi(C.GL_EXTENSIONS, it.i)
	get_error()!
	it.i++
	return ExtensionNextResult{
		value: unsafe { cstring_to_vstring(&char(ptr)) }
	}
}

// ============================================================
// primitives.zig
// ============================================================

pub enum Primitive as i32 {
	point          = C.GL_POINTS
	line           = C.GL_LINES
	line_strip     = C.GL_LINE_STRIP
	triangle       = C.GL_TRIANGLES
	triangle_strip = C.GL_TRIANGLE_STRIP
}

// ============================================================
// draw.zig
// ============================================================

pub fn clear_color(r f32, g f32, b f32, a f32) {
	C.witty_glClearColor(r, g, b, a)
}

pub fn clear(mask u32) {
	C.witty_glClear(mask)
}

pub fn draw_arrays(mode u32, first int, count int) ! {
	C.witty_glDrawArrays(mode, first, count)
	get_error()!
}

pub fn draw_arrays_instanced(mode Primitive, first int, count int, primcount int) ! {
	C.witty_glDrawArraysInstanced(u32(mode), first, count, primcount)
	get_error()!
}

pub fn draw_elements(mode u32, count int, typ u32, offset uint) ! {
	mut ptr := voidptr(unsafe { nil })
	if offset > 0 {
		ptr = voidptr(offset)
	}
	C.witty_glDrawElements(mode, count, typ, ptr)
	get_error()!
}

pub fn draw_elements_instanced(mode u32, count int, typ u32, primcount int) ! {
	C.witty_glDrawElementsInstanced(mode, count, typ, unsafe { nil }, primcount)
	get_error()!
}

pub fn enable(cap u32) ! {
	C.witty_glEnable(cap)
	get_error()!
}

pub fn disable(cap u32) ! {
	C.witty_glDisable(cap)
	get_error()!
}

pub fn front_face(mode u32) ! {
	C.witty_glFrontFace(mode)
	get_error()!
}

pub fn blend_func(sfactor u32, dfactor u32) ! {
	C.witty_glBlendFunc(sfactor, dfactor)
	get_error()!
}

pub fn viewport(x int, y int, width int, height int) ! {
	C.witty_glViewport(x, y, width, height)
}

pub fn viewport_rect() ![4]int {
	mut values := [4]int{}
	C.witty_glGetIntegerv(C.GL_VIEWPORT, &values[0])
	get_error()!
	return values
}

pub fn pixel_store[T](mode u32, value T) ! {
	$if T is $int {
		C.witty_glPixelStorei(mode, int(value))
	} $else {
		$compile_error('pixel_store only supports integer values')
	}
	get_error()!
}

pub fn finish() {
	C.witty_glFinish()
}

pub fn flush() {
	C.witty_glFlush()
}

pub const gl_blend = u32(C.GL_BLEND)
pub const gl_color_buffer_bit = u32(C.GL_COLOR_BUFFER_BIT)
pub const gl_debug_output = u32(C.GL_DEBUG_OUTPUT)
pub const gl_debug_source_api = u32(C.GL_DEBUG_SOURCE_API)
pub const gl_debug_source_window_system = u32(C.GL_DEBUG_SOURCE_WINDOW_SYSTEM)
pub const gl_debug_source_shader_compiler = u32(C.GL_DEBUG_SOURCE_SHADER_COMPILER)
pub const gl_debug_source_third_party = u32(C.GL_DEBUG_SOURCE_THIRD_PARTY)
pub const gl_debug_source_application = u32(C.GL_DEBUG_SOURCE_APPLICATION)
pub const gl_debug_source_other = u32(C.GL_DEBUG_SOURCE_OTHER)
pub const gl_debug_type_error = u32(C.GL_DEBUG_TYPE_ERROR)
pub const gl_debug_type_deprecated_behavior = u32(C.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR)
pub const gl_debug_type_undefined_behavior = u32(C.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR)
pub const gl_debug_type_portability = u32(C.GL_DEBUG_TYPE_PORTABILITY)
pub const gl_debug_type_performance = u32(C.GL_DEBUG_TYPE_PERFORMANCE)
pub const gl_debug_type_marker = u32(C.GL_DEBUG_TYPE_MARKER)
pub const gl_debug_type_push_group = u32(C.GL_DEBUG_TYPE_PUSH_GROUP)
pub const gl_debug_type_pop_group = u32(C.GL_DEBUG_TYPE_POP_GROUP)
pub const gl_debug_type_other = u32(C.GL_DEBUG_TYPE_OTHER)
pub const gl_debug_severity_high = u32(C.GL_DEBUG_SEVERITY_HIGH)
pub const gl_debug_severity_medium = u32(C.GL_DEBUG_SEVERITY_MEDIUM)
pub const gl_debug_severity_low = u32(C.GL_DEBUG_SEVERITY_LOW)
pub const gl_debug_severity_notification = u32(C.GL_DEBUG_SEVERITY_NOTIFICATION)
pub const gl_framebuffer_srgb = u32(C.GL_FRAMEBUFFER_SRGB)
pub const gl_one = u32(C.GL_ONE)
pub const gl_one_minus_src_alpha = u32(C.GL_ONE_MINUS_SRC_ALPHA)
pub const gl_byte = u32(C.GL_BYTE)
pub const gl_short = u32(C.GL_SHORT)
pub const gl_unsigned_short = u32(C.GL_UNSIGNED_SHORT)
pub const gl_int = u32(C.GL_INT)
pub const gl_unsigned_int = u32(C.GL_UNSIGNED_INT)
pub const gl_float = u32(C.GL_FLOAT)
pub const gl_double = u32(C.GL_DOUBLE)
pub const gl_half_float = u32(C.GL_HALF_FLOAT)
pub const gl_unsigned_byte = u32(C.GL_UNSIGNED_BYTE)

// DebugMessageCallback matches GLDEBUGPROC.
pub type DebugMessageCallback = fn (source u32, typ u32, id u32, severity u32, length int, message &u8, user_param voidptr)

pub fn debug_message_callback(callback DebugMessageCallback, user_param voidptr) ! {
	if C.witty_glDebugMessageCallback(voidptr(callback), user_param) == 0 {
		return error('glDebugMessageCallback unavailable')
	}
	get_error()!
}

// ============================================================
// Buffer.zig
// ============================================================

pub struct Buffer {
pub:
	id u32
}

pub enum BufferTarget as u32 {
	array         = C.GL_ARRAY_BUFFER
	element_array = C.GL_ELEMENT_ARRAY_BUFFER
	uniform       = C.GL_UNIFORM_BUFFER
	storage       = C.GL_SHADER_STORAGE_BUFFER
}

pub enum BufferUsage as u32 {
	stream_draw  = C.GL_STREAM_DRAW
	stream_read  = C.GL_STREAM_READ
	stream_copy  = C.GL_STREAM_COPY
	static_draw  = C.GL_STATIC_DRAW
	static_read  = C.GL_STATIC_READ
	static_copy  = C.GL_STATIC_COPY
	dynamic_draw = C.GL_DYNAMIC_DRAW
	dynamic_read = C.GL_DYNAMIC_READ
	dynamic_copy = C.GL_DYNAMIC_COPY
}

pub struct BufferBinding {
pub:
	id     u32
	target BufferTarget
}

pub fn Buffer.create() !Buffer {
	mut id := u32(0)
	C.witty_glGenBuffers(1, &id)
	return Buffer{
		id: id
	}
}

pub fn (b Buffer) bind(target BufferTarget) !BufferBinding {
	C.witty_glBindBuffer(u32(target), b.id)
	return BufferBinding{
		id: b.id
		target: target
	}
}

pub fn (b Buffer) destroy() {
	mut id := b.id
	C.witty_glDeleteBuffers(1, &id)
}

pub fn (b Buffer) bind_base(target BufferTarget, idx u32) ! {
	C.witty_glBindBufferBase(u32(target), idx, b.id)
	get_error()!
}

pub fn (b BufferBinding) unbind() {
	C.witty_glBindBuffer(u32(b.target), 0)
}

struct BufferDataInfo {
	size int
	ptr  voidptr
}

fn buffer_data_info[T](data T) BufferDataInfo {
	$if T is $array {
		mut ptr := voidptr(unsafe { nil })
		if data.len > 0 {
			ptr = voidptr(data.data)
		}
		return BufferDataInfo{
			size: int(uint(data.len) * uint(sizeof(data[0])))
			ptr:  ptr
		}
	} $else $if T is $pointer {
		return BufferDataInfo{
			size: int(sizeof(*data))
			ptr:  voidptr(data)
		}
	} $else {
		$compile_error('buffer data must be a slice or single-item pointer')
	}
}

pub fn (b BufferBinding) set_data[T](data T, usage BufferUsage) ! {
	info := buffer_data_info(data)
	C.witty_glBufferData(u32(b.target), info.size, info.ptr, u32(usage))
	get_error()!
}

pub fn (b BufferBinding) set_sub_data[T](offset uint, data T) ! {
	info := buffer_data_info(data)
	C.witty_glBufferSubData(u32(b.target), int(offset), info.size, info.ptr)
	get_error()!
}

pub fn (b BufferBinding) set_data_null[T](usage BufferUsage) ! {
	C.witty_glBufferData(u32(b.target), int(sizeof(T)), unsafe { nil }, u32(usage))
	get_error()!
}

pub fn (b BufferBinding) set_data_null_manual(size uint, usage BufferUsage) ! {
	C.witty_glBufferData(u32(b.target), int(size), unsafe { nil }, u32(usage))
	get_error()!
}

pub fn (b BufferBinding) enable_attrib_array(idx u32) ! {
	C.witty_glEnableVertexAttribArray(idx)
	get_error()!
}

// attribute is the common homogeneous fixed-array shorthand from Buffer.zig.
// The pinned Ghostty implementation only accepts fixed arrays of f32.
pub fn (b BufferBinding) attribute[T](idx u32, size int, offset uint) ! {
	$if T is $array_fixed {
		value := T{}
		component_size := buffer_attribute_component_size(value[0])
		b.attribute_advanced(idx, size, gl_float, false, int(sizeof(T)), offset * component_size)!
		b.enable_attrib_array(idx)!
	} $else {
		$compile_error('BufferBinding.attribute only supports fixed arrays')
	}
}

fn buffer_attribute_component_size[T](value T) uint {
	_ = value
	$if T is f32 {
		return uint(sizeof(T))
	} $else {
		$compile_error('BufferBinding.attribute only supports f32 array components')
	}
}

pub fn (b BufferBinding) attribute_divisor(idx u32, divisor u32) ! {
	_ = b
	C.witty_glVertexAttribDivisor(idx, divisor)
	get_error()!
}

pub fn (b BufferBinding) attribute_advanced(idx u32, size int, typ u32, normalized bool, stride int, offset uint) ! {
	_ = b
	C.witty_glVertexAttribPointer(idx, size, typ, if normalized { u8(C.GL_TRUE) } else { u8(C.GL_FALSE) }, stride, voidptr(offset))
	get_error()!
}

pub fn (b BufferBinding) attribute_i_advanced(idx u32, size int, typ u32, stride int, offset uint) ! {
	_ = b
	C.witty_glVertexAttribIPointer(idx, size, typ, stride, voidptr(offset))
	get_error()!
}

// ============================================================
// Texture.zig
// ============================================================

pub struct Texture {
pub:
	id u32
}

pub enum TextureTarget as u32 {
	t1d                   = C.GL_TEXTURE_1D
	t2d                   = C.GL_TEXTURE_2D
	t3d                   = C.GL_TEXTURE_3D
	t1d_array             = C.GL_TEXTURE_1D_ARRAY
	t2d_array             = C.GL_TEXTURE_2D_ARRAY
	rectangle             = C.GL_TEXTURE_RECTANGLE
	cube_map              = C.GL_TEXTURE_CUBE_MAP
	buffer                = C.GL_TEXTURE_BUFFER
	t2d_multisample       = 0x9100 // GL_TEXTURE_2D_MULTISAMPLE
	t2d_multisample_array = 0x9102 // GL_TEXTURE_2D_MULTISAMPLE_ARRAY
}

pub enum TextureParameter as u32 {
	base_level   = C.GL_TEXTURE_BASE_LEVEL
	compare_func = C.GL_TEXTURE_COMPARE_FUNC
	compare_mode = C.GL_TEXTURE_COMPARE_MODE
	lod_bias     = C.GL_TEXTURE_LOD_BIAS
	min_filter   = C.GL_TEXTURE_MIN_FILTER
	mag_filter   = C.GL_TEXTURE_MAG_FILTER
	min_lod      = C.GL_TEXTURE_MIN_LOD
	max_lod      = C.GL_TEXTURE_MAX_LOD
	max_level    = C.GL_TEXTURE_MAX_LEVEL
	swizzle_r    = C.GL_TEXTURE_SWIZZLE_R
	swizzle_g    = C.GL_TEXTURE_SWIZZLE_G
	swizzle_b    = C.GL_TEXTURE_SWIZZLE_B
	swizzle_a    = C.GL_TEXTURE_SWIZZLE_A
	wrap_s       = C.GL_TEXTURE_WRAP_S
	wrap_t       = C.GL_TEXTURE_WRAP_T
	wrap_r       = C.GL_TEXTURE_WRAP_R
}

pub enum TextureInternalFormat as i32 {
	red              = C.GL_RED
	rgb              = C.GL_RGB8
	rgba             = C.GL_RGBA8
	srgb             = C.GL_SRGB8
	srgba            = C.GL_SRGB8_ALPHA8
	rgba_compressed  = 0x8e8c // GL_COMPRESSED_RGBA_BPTC_UNORM
	srgba_compressed = 0x8e8d // GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM
}

pub enum TextureFormat as u32 {
	red  = C.GL_RED
	rgb  = C.GL_RGB
	rgba = C.GL_RGBA
	bgra = C.GL_BGRA
}

pub enum TextureMinFilter as i32 {
	nearest                = C.GL_NEAREST
	linear                 = C.GL_LINEAR
	nearest_mipmap_nearest = C.GL_NEAREST_MIPMAP_NEAREST
	linear_mipmap_nearest  = C.GL_LINEAR_MIPMAP_NEAREST
	nearest_mipmap_linear  = C.GL_NEAREST_MIPMAP_LINEAR
	linear_mipmap_linear   = C.GL_LINEAR_MIPMAP_LINEAR
}

pub enum TextureMagFilter as i32 {
	nearest = C.GL_NEAREST
	linear  = C.GL_LINEAR
}

pub enum TextureWrap as i32 {
	clamp_to_edge   = C.GL_CLAMP_TO_EDGE
	clamp_to_border = C.GL_CLAMP_TO_BORDER
	mirrored_repeat = C.GL_MIRRORED_REPEAT
	repeat          = C.GL_REPEAT
}

pub enum TextureDataType as u32 {
	unsigned_byte = C.GL_UNSIGNED_BYTE
}

pub struct TextureBinding {
pub:
	target TextureTarget
}

pub fn texture_active(index u32) ! {
	C.witty_glActiveTexture(index + u32(C.GL_TEXTURE0))
	get_error()!
}

pub fn Texture.create() !Texture {
	mut id := u32(0)
	C.witty_glGenTextures(1, &id)
	get_error()!
	return Texture{
		id: id
	}
}

pub fn (t Texture) bind(target TextureTarget) !TextureBinding {
	C.witty_glBindTexture(u32(target), t.id)
	get_error()!
	return TextureBinding{
		target: target
	}
}

pub fn (t Texture) destroy() {
	mut id := t.id
	C.witty_glDeleteTextures(1, &id)
}

pub fn (b TextureBinding) unbind() {
	C.witty_glBindTexture(u32(b.target), 0)
}

pub fn (b TextureBinding) generate_mipmap() {
	C.witty_glGenerateMipmap(u32(b.target))
}

pub fn (b TextureBinding) parameter(name TextureParameter, value int) ! {
	C.witty_glTexParameteri(u32(b.target), u32(name), value)
	get_error()!
}

pub fn (b TextureBinding) image_2d(level int, internal_format TextureInternalFormat, width int, height int, format TextureFormat, typ TextureDataType, data voidptr) ! {
	C.witty_glTexImage2D(u32(b.target), level, int(internal_format), width, height, 0, u32(format), u32(typ), data)
	get_error()!
}

pub fn (b TextureBinding) sub_image_2d(level int, xoffset int, yoffset int, width int, height int, format TextureFormat, typ TextureDataType, data voidptr) ! {
	C.witty_glTexSubImage2D(u32(b.target), level, xoffset, yoffset, width, height, u32(format), u32(typ), data)
	get_error()!
}

pub fn (b TextureBinding) copy_sub_image_2d(level int, xoffset int, yoffset int, x int, y int, width int, height int) ! {
	C.witty_glCopyTexSubImage2D(u32(b.target), level, xoffset, yoffset, x, y, width, height)
	get_error()!
}

// ============================================================
// VertexArray.zig
// ============================================================

pub struct VertexArray {
pub:
	id u32
}

pub struct VertexArrayBinding {}

pub fn VertexArray.create() !VertexArray {
	mut id := u32(0)
	C.witty_glGenVertexArrays(1, &id)
	return VertexArray{
		id: id
	}
}

pub fn (v VertexArray) bind() !VertexArrayBinding {
	C.witty_glBindVertexArray(v.id)
	get_error()!
	return VertexArrayBinding{}
}

pub fn (v VertexArray) destroy() {
	mut id := v.id
	C.witty_glDeleteVertexArrays(1, &id)
}

pub fn (b VertexArrayBinding) unbind() {
	_ = b
	C.witty_glBindVertexArray(0)
}

pub fn (b VertexArrayBinding) enable_attrib_array(idx u32) ! {
	_ = b
	C.witty_glEnableVertexAttribArray(idx)
	get_error()!
}

// OpenGL 4.3-only APIs from the Zig package.
pub fn (b VertexArrayBinding) binding_divisor(idx u32, divisor u32) ! {
	_ = b
	if C.witty_glVertexBindingDivisor(idx, divisor) == 0 {
		return error('glVertexBindingDivisor unavailable')
	}
	get_error()!
}

pub fn (b VertexArrayBinding) attribute_binding(attrib_idx u32, binding_idx u32) ! {
	_ = b
	if C.witty_glVertexAttribBinding(attrib_idx, binding_idx) == 0 {
		return error('glVertexAttribBinding unavailable')
	}
	get_error()!
}

pub fn (b VertexArrayBinding) attribute_format(idx u32, size int, typ u32, normalized bool, offset u32) ! {
	_ = b
	if C.witty_glVertexAttribFormat(idx, size, typ, if normalized {
		u8(C.GL_TRUE)
	} else {
		u8(C.GL_FALSE)
	}, offset) == 0 {
		return error('glVertexAttribFormat unavailable')
	}
	get_error()!
}

pub fn (b VertexArrayBinding) attribute_i_format(idx u32, size int, typ u32, offset u32) ! {
	_ = b
	if C.witty_glVertexAttribIFormat(idx, size, typ, offset) == 0 {
		return error('glVertexAttribIFormat unavailable')
	}
	get_error()!
}

pub fn (b VertexArrayBinding) attribute_l_format(idx u32, size int, offset u32) ! {
	_ = b
	if C.witty_glVertexAttribLFormat(idx, size, C.GL_DOUBLE, offset) == 0 {
		return error('glVertexAttribLFormat unavailable')
	}
	get_error()!
}

pub fn (b VertexArrayBinding) bind_vertex_buffer(idx u32, buffer u32, offset int, stride int) ! {
	_ = b
	if C.witty_glBindVertexBuffer(idx, buffer, offset, stride) == 0 {
		return error('glBindVertexBuffer unavailable')
	}
	get_error()!
}

// ============================================================
// Shader.zig
// ============================================================

pub struct Shader {
pub:
	id u32
}

pub const shader_type_vertex = u32(C.GL_VERTEX_SHADER)
pub const shader_type_fragment = u32(C.GL_FRAGMENT_SHADER)

pub fn Shader.create(typ u32) !Shader {
	id := C.witty_glCreateShader(typ)
	if id == 0 {
		must_error()!
		return error('CreateShader failed')
	}
	log.debug('shader created id=${id}')
	return Shader{
		id: id
	}
}

pub fn (s Shader) set_source_and_compile(source string) ! {
	mut src := source.str
	C.witty_glShaderSource(s.id, 1, &src, unsafe { nil })
	C.witty_glCompileShader(s.id)
	mut success := int(0)
	C.witty_glGetShaderiv(s.id, C.GL_COMPILE_STATUS, &success)
	if success != int(C.GL_TRUE) {
		msg := s.get_info_log()
		log.error('shader compilation failure id=${s.id} message=${unsafe {
			cstring_to_vstring(&char(&msg[0]))
		}}')
		return error('CompileFailed')
	}
}

pub fn (s Shader) get_info_log() [512]u8 {
	mut msg := [512]u8{}
	C.witty_glGetShaderInfoLog(s.id, msg.len, unsafe { nil }, &msg[0])
	return msg
}

pub fn (s Shader) destroy() {
	assert s.id != 0
	C.witty_glDeleteShader(s.id)
	log.debug('shader destroyed id=${s.id}')
}

// ============================================================
// Program.zig
// ============================================================

pub struct Program {
pub:
	id u32
}

pub struct ProgramBinding {}

pub fn Program.create() !Program {
	id := C.witty_glCreateProgram()
	if id == 0 {
		must_error()!
		return error('CreateProgram failed')
	}
	log.debug('program created id=${id}')
	return Program{
		id: id
	}
}

pub fn Program.create_vf(vsrc string, fsrc string) !Program {
	vs := Shader.create(shader_type_vertex)!
	defer {
		vs.destroy()
	}
	vs.set_source_and_compile(vsrc)!

	fs := Shader.create(shader_type_fragment)!
	defer {
		fs.destroy()
	}
	fs.set_source_and_compile(fsrc)!

	p := Program.create()!
	p.attach_shader(vs)!
	p.attach_shader(fs)!
	p.link()!
	return p
}

pub fn (p Program) destroy() {
	assert p.id != 0
	C.witty_glDeleteProgram(p.id)
	log.debug('program destroyed id=${p.id}')
}

pub fn (p Program) attach_shader(s Shader) ! {
	C.witty_glAttachShader(p.id, s.id)
	get_error()!
}

pub fn (p Program) link() ! {
	C.witty_glLinkProgram(p.id)
	mut success := int(0)
	C.witty_glGetProgramiv(p.id, C.GL_LINK_STATUS, &success)
	if success == int(C.GL_TRUE) {
		log.debug('program linked id=${p.id}')
		return
	}
	msg := p.get_info_log()
	log.error('program link failure id=${p.id} message=${unsafe {
		cstring_to_vstring(&char(&msg[0]))
	}}')
	return error('CompileFailed')
}

pub fn (p Program) use() !ProgramBinding {
	C.witty_glUseProgram(p.id)
	get_error()!
	return ProgramBinding{}
}

pub fn (b ProgramBinding) unbind() {
	_ = b
	C.witty_glUseProgram(0)
}

pub fn (p Program) uniform_block_binding(index u32, binding u32) ! {
	C.witty_glUniformBlockBinding(p.id, index, binding)
	get_error()!
}

pub fn (p Program) set_uniform[T](name string, value T) ! {
	loc := C.witty_glGetUniformLocation(p.id, name.str)
	if loc < 0 {
		return error('UniformNameInvalid')
	}
	get_error()!

	$if T is bool {
		C.witty_glUniform1i(loc, if value { 1 } else { 0 })
	} $else $if T is int {
		C.witty_glUniform1i(loc, value)
	} $else $if T is f32 {
		C.witty_glUniform1f(loc, value)
	} $else $if T is [2]f32 {
		C.witty_glUniform2f(loc, value[0], value[1])
	} $else $if T is [3]f32 {
		C.witty_glUniform3f(loc, value[0], value[1], value[2])
	} $else $if T is [4]f32 {
		C.witty_glUniform4f(loc, value[0], value[1], value[2], value[3])
	} $else $if T is [16]f32 {
		C.witty_glUniformMatrix4fv(loc, 1, u8(C.GL_FALSE), &value[0])
	} $else {
		$compile_error('unsupported uniform type')
	}

	get_error()!
}

pub fn (p Program) get_info_log() [512]u8 {
	mut msg := [512]u8{}
	C.witty_glGetProgramInfoLog(p.id, msg.len, unsafe { nil }, &msg[0])
	return msg
}

// ============================================================
// Renderbuffer.zig
// ============================================================

pub struct Renderbuffer {
pub:
	id u32
}

pub struct RenderbufferBinding {
pub:
	previous u32
}

pub fn Renderbuffer.create() !Renderbuffer {
	mut id := u32(0)
	C.witty_glGenRenderbuffers(1, &id)
	return Renderbuffer{
		id: id
	}
}

pub fn (r Renderbuffer) destroy() {
	mut id := r.id
	C.witty_glDeleteRenderbuffers(1, &id)
}

pub fn (r Renderbuffer) bind() !RenderbufferBinding {
	mut current := int(0)
	C.witty_glGetIntegerv(C.GL_RENDERBUFFER_BINDING, &current)
	C.witty_glBindRenderbuffer(C.GL_RENDERBUFFER, r.id)
	return RenderbufferBinding{
		previous: u32(current)
	}
}

pub fn (b RenderbufferBinding) unbind() {
	C.witty_glBindRenderbuffer(C.GL_RENDERBUFFER, b.previous)
}

pub fn (b RenderbufferBinding) storage(format TextureInternalFormat, width int, height int) ! {
	_ = b
	C.witty_glRenderbufferStorage(C.GL_RENDERBUFFER, u32(format), width, height)
	get_error()!
}

// ============================================================
// Framebuffer.zig
// ============================================================

pub struct Framebuffer {
pub:
	id u32
}

pub enum FramebufferTarget as u32 {
	framebuffer = C.GL_FRAMEBUFFER
	draw        = C.GL_DRAW_FRAMEBUFFER
	read        = C.GL_READ_FRAMEBUFFER
}

pub enum FramebufferAttachment as u32 {
	color0        = C.GL_COLOR_ATTACHMENT0
	depth         = C.GL_DEPTH_ATTACHMENT
	stencil       = C.GL_STENCIL_ATTACHMENT
	depth_stencil = C.GL_DEPTH_STENCIL_ATTACHMENT
}

pub enum FramebufferStatus as u32 {
	complete                      = C.GL_FRAMEBUFFER_COMPLETE
	undefined                     = C.GL_FRAMEBUFFER_UNDEFINED
	incomplete_attachment         = C.GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT
	incomplete_missing_attachment = C.GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT
	incomplete_draw_buffer        = C.GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER
	incomplete_read_buffer        = C.GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER
	unsupported                   = C.GL_FRAMEBUFFER_UNSUPPORTED
	incomplete_multisample        = C.GL_FRAMEBUFFER_INCOMPLETE_MULTISAMPLE
	incomplete_layer_targets      = C.GL_FRAMEBUFFER_INCOMPLETE_LAYER_TARGETS
}

pub struct FramebufferBinding {
pub:
	target   FramebufferTarget
	previous u32
}

pub fn Framebuffer.create() !Framebuffer {
	mut id := u32(0)
	C.witty_glGenFramebuffers(1, &id)
	return Framebuffer{
		id: id
	}
}

pub fn (f Framebuffer) destroy() {
	mut id := f.id
	C.witty_glDeleteFramebuffers(1, &id)
}

pub fn (f Framebuffer) bind(target FramebufferTarget) !FramebufferBinding {
	mut current := int(0)
	C.witty_glGetIntegerv(C.GL_FRAMEBUFFER_BINDING, &current)
	C.witty_glBindFramebuffer(u32(target), f.id)
	return FramebufferBinding{
		target: target
		previous: u32(current)
	}
}

pub fn (b FramebufferBinding) unbind() {
	C.witty_glBindFramebuffer(u32(b.target), b.previous)
}

pub fn (b FramebufferBinding) texture_2d(attachment FramebufferAttachment, textarget TextureTarget, texture Texture, level int) ! {
	C.witty_glFramebufferTexture2D(u32(b.target), u32(attachment), u32(textarget), texture.id, level)
	get_error()!
}

pub fn (b FramebufferBinding) renderbuffer(attachment FramebufferAttachment, buffer Renderbuffer) ! {
	C.witty_glFramebufferRenderbuffer(u32(b.target), u32(attachment), C.GL_RENDERBUFFER, buffer.id)
	get_error()!
}

pub fn (b FramebufferBinding) draw_buffers(bufs []FramebufferAttachment) ! {
	_ = b
	mut ptr := &u32(unsafe { nil })
	if bufs.len > 0 {
		ptr = &u32(bufs.data)
	}
	C.witty_glDrawBuffers(bufs.len, ptr)
	get_error()!
}

pub fn (b FramebufferBinding) check_status() FramebufferStatus {
	return unsafe { FramebufferStatus(C.witty_glCheckFramebufferStatus(u32(b.target))) }
}

pub fn blit_framebuffer(src_x0 int, src_y0 int, src_x1 int, src_y1 int, dst_x0 int, dst_y0 int, dst_x1 int, dst_y1 int, mask u32, filter TextureMagFilter) ! {
	if C.witty_glBlitFramebuffer(src_x0, src_y0, src_x1, src_y1, dst_x0, dst_y0, dst_x1, dst_y1, mask, u32(filter)) == 0 {
		return error('glBlitFramebuffer unavailable')
	}
	get_error()!
}

// ============================================================
// Sampler.zig
// ============================================================

pub struct Sampler {
pub:
	id u32
}

pub fn Sampler.create() !Sampler {
	mut id := u32(0)
	C.witty_glGenSamplers(1, &id)
	get_error()!
	return Sampler{
		id: id
	}
}

pub fn (s Sampler) bind(index u32) ! {
	C.witty_glBindSampler(index, s.id)
	get_error()!
}

pub fn (s Sampler) parameter(name TextureParameter, value int) ! {
	C.witty_glSamplerParameteri(s.id, u32(name), value)
	get_error()!
}

pub fn (s Sampler) destroy() {
	mut id := s.id
	C.witty_glDeleteSamplers(1, &id)
}
