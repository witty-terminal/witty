#ifndef WITTY_GL_DISPATCH_H
#define WITTY_GL_DISPATCH_H

#include <stdint.h>

/* Keep GLAD's types and macros private to its translation unit. Canvas
 * includes the system OpenGL headers in Witty's generated C unit. */
#define WITTY_GL_DISPATCH(X) \
    X(unsigned int, return, GetError, (void), ()) \
    X(void, , GetIntegerv, (unsigned int pname, int *data), (pname, data)) \
    X(const unsigned char *, return, GetStringi, (unsigned int name, unsigned int index), (name, index)) \
    X(void, , ClearColor, (float red, float green, float blue, float alpha), (red, green, blue, alpha)) \
    X(void, , Clear, (unsigned int mask), (mask)) \
    X(void, , DrawArrays, (unsigned int mode, int first, int count), (mode, first, count)) \
    X(void, , DrawArraysInstanced, (unsigned int mode, int first, int count, int primcount), (mode, first, count, primcount)) \
    X(void, , DrawElements, (unsigned int mode, int count, unsigned int type, void *indices), (mode, count, type, indices)) \
    X(void, , DrawElementsInstanced, (unsigned int mode, int count, unsigned int type, void *indices, int primcount), (mode, count, type, indices, primcount)) \
    X(void, , Enable, (unsigned int cap), (cap)) \
    X(void, , Disable, (unsigned int cap), (cap)) \
    X(void, , FrontFace, (unsigned int mode), (mode)) \
    X(void, , BlendFunc, (unsigned int sfactor, unsigned int dfactor), (sfactor, dfactor)) \
    X(void, , Viewport, (int x, int y, int width, int height), (x, y, width, height)) \
    X(void, , PixelStorei, (unsigned int pname, int param), (pname, param)) \
    X(void, , Finish, (void), ()) \
    X(void, , Flush, (void), ()) \
    X(void, , GenBuffers, (int n, unsigned int *buffers), (n, buffers)) \
    X(void, , BindBuffer, (unsigned int target, unsigned int buffer), (target, buffer)) \
    X(void, , DeleteBuffers, (int n, unsigned int *buffers), (n, buffers)) \
    X(void, , BindBufferBase, (unsigned int target, unsigned int index, unsigned int buffer), (target, index, buffer)) \
    X(void, , BufferData, (unsigned int target, intptr_t size, void *data, unsigned int usage), (target, size, data, usage)) \
    X(void, , BufferSubData, (unsigned int target, intptr_t offset, intptr_t size, void *data), (target, offset, size, data)) \
    X(void, , VertexAttribPointer, (unsigned int index, int size, unsigned int type, unsigned char normalized, int stride, void *pointer), (index, size, type, normalized, stride, pointer)) \
    X(void, , VertexAttribIPointer, (unsigned int index, int size, unsigned int type, int stride, void *pointer), (index, size, type, stride, pointer)) \
    X(void, , EnableVertexAttribArray, (unsigned int index), (index)) \
    X(void, , VertexAttribDivisor, (unsigned int index, unsigned int divisor), (index, divisor)) \
    X(void, , ActiveTexture, (unsigned int texture), (texture)) \
    X(void, , GenTextures, (int n, unsigned int *textures), (n, textures)) \
    X(void, , BindTexture, (unsigned int target, unsigned int texture), (target, texture)) \
    X(void, , DeleteTextures, (int n, unsigned int *textures), (n, textures)) \
    X(void, , GenerateMipmap, (unsigned int target), (target)) \
    X(void, , TexParameteri, (unsigned int target, unsigned int pname, int param), (target, pname, param)) \
    X(void, , TexImage2D, (unsigned int target, int level, int internalformat, int width, int height, int border, unsigned int format, unsigned int type, void *pixels), (target, level, internalformat, width, height, border, format, type, pixels)) \
    X(void, , TexSubImage2D, (unsigned int target, int level, int xoffset, int yoffset, int width, int height, unsigned int format, unsigned int type, void *pixels), (target, level, xoffset, yoffset, width, height, format, type, pixels)) \
    X(void, , CopyTexSubImage2D, (unsigned int target, int level, int xoffset, int yoffset, int x, int y, int width, int height), (target, level, xoffset, yoffset, x, y, width, height)) \
    X(void, , GenVertexArrays, (int n, unsigned int *arrays), (n, arrays)) \
    X(void, , BindVertexArray, (unsigned int array), (array)) \
    X(void, , DeleteVertexArrays, (int n, unsigned int *arrays), (n, arrays)) \
    X(unsigned int, return, CreateShader, (unsigned int type), (type)) \
    X(void, , ShaderSource, (unsigned int shader, int count, unsigned char **string, int *length), (shader, count, (const GLchar *const *)string, length)) \
    X(void, , CompileShader, (unsigned int shader), (shader)) \
    X(void, , GetShaderiv, (unsigned int shader, unsigned int pname, int *params), (shader, pname, params)) \
    X(void, , GetShaderInfoLog, (unsigned int shader, int maxLength, int *length, unsigned char *infoLog), (shader, maxLength, length, (GLchar *)infoLog)) \
    X(void, , DeleteShader, (unsigned int shader), (shader)) \
    X(unsigned int, return, CreateProgram, (void), ()) \
    X(void, , DeleteProgram, (unsigned int program), (program)) \
    X(void, , AttachShader, (unsigned int program, unsigned int shader), (program, shader)) \
    X(void, , LinkProgram, (unsigned int program), (program)) \
    X(void, , GetProgramiv, (unsigned int program, unsigned int pname, int *params), (program, pname, params)) \
    X(void, , GetProgramInfoLog, (unsigned int program, int maxLength, int *length, unsigned char *infoLog), (program, maxLength, length, (GLchar *)infoLog)) \
    X(void, , UseProgram, (unsigned int program), (program)) \
    X(void, , UniformBlockBinding, (unsigned int program, unsigned int uniformBlockIndex, unsigned int uniformBlockBinding), (program, uniformBlockIndex, uniformBlockBinding)) \
    X(int, return, GetUniformLocation, (unsigned int program, unsigned char *name), (program, (const GLchar *)name)) \
    X(void, , Uniform1i, (int location, int v0), (location, v0)) \
    X(void, , Uniform1f, (int location, float v0), (location, v0)) \
    X(void, , Uniform2f, (int location, float v0, float v1), (location, v0, v1)) \
    X(void, , Uniform3f, (int location, float v0, float v1, float v2), (location, v0, v1, v2)) \
    X(void, , Uniform4f, (int location, float v0, float v1, float v2, float v3), (location, v0, v1, v2, v3)) \
    X(void, , UniformMatrix4fv, (int location, int count, unsigned char transpose, float *value), (location, count, transpose, value)) \
    X(void, , GenFramebuffers, (int n, unsigned int *ids), (n, ids)) \
    X(void, , DeleteFramebuffers, (int n, unsigned int *framebuffers), (n, framebuffers)) \
    X(void, , BindFramebuffer, (unsigned int target, unsigned int framebuffer), (target, framebuffer)) \
    X(void, , FramebufferTexture2D, (unsigned int target, unsigned int attachment, unsigned int textarget, unsigned int texture, int level), (target, attachment, textarget, texture, level)) \
    X(void, , FramebufferRenderbuffer, (unsigned int target, unsigned int attachment, unsigned int renderbuffertarget, unsigned int renderbuffer), (target, attachment, renderbuffertarget, renderbuffer)) \
    X(void, , DrawBuffers, (int n, unsigned int *bufs), (n, bufs)) \
    X(unsigned int, return, CheckFramebufferStatus, (unsigned int target), (target)) \
    X(void, , GenRenderbuffers, (int n, unsigned int *renderbuffers), (n, renderbuffers)) \
    X(void, , DeleteRenderbuffers, (int n, unsigned int *renderbuffers), (n, renderbuffers)) \
    X(void, , BindRenderbuffer, (unsigned int target, unsigned int renderbuffer), (target, renderbuffer)) \
    X(void, , RenderbufferStorage, (unsigned int target, unsigned int internalformat, int width, int height), (target, internalformat, width, height)) \
    X(void, , GenSamplers, (int n, unsigned int *samplers), (n, samplers)) \
    X(void, , BindSampler, (unsigned int unit, unsigned int sampler), (unit, sampler)) \
    X(void, , SamplerParameteri, (unsigned int sampler, unsigned int pname, int param), (sampler, pname, param)) \
    X(void, , DeleteSamplers, (int n, unsigned int *samplers), (n, samplers))

#define WITTY_GL_DECLARE(type, keyword, name, params, args) type witty_gl##name params;
WITTY_GL_DISPATCH(WITTY_GL_DECLARE)
#undef WITTY_GL_DECLARE

int witty_gl_load(void *get_proc_address);
void witty_gl_unload(void);
int witty_glVertexBindingDivisor(unsigned int bindingindex, unsigned int divisor);
int witty_glVertexAttribBinding(unsigned int attribindex, unsigned int bindingindex);
int witty_glVertexAttribFormat(
	unsigned int attribindex,
	int size,
	unsigned int type,
	unsigned char normalized,
	unsigned int relativeoffset
);
int witty_glVertexAttribIFormat(
	unsigned int attribindex,
	int size,
	unsigned int type,
	unsigned int relativeoffset
);
int witty_glVertexAttribLFormat(
	unsigned int attribindex,
	int size,
	unsigned int type,
	unsigned int relativeoffset
);
int witty_glBindVertexBuffer(
	unsigned int bindingindex,
	unsigned int buffer,
	intptr_t offset,
	int stride
);
int witty_glBlitFramebuffer(
	int src_x0,
	int src_y0,
	int src_x1,
	int src_y1,
	int dst_x0,
	int dst_y0,
	int dst_x1,
	int dst_y1,
	unsigned int mask,
	unsigned int filter
);
int witty_glDebugMessageCallback(void *callback, void *user_param);
int witty_gl_read_rgba8(int width, int height, void *pixels);
void *witty_gl_test_resolver_pointer(void);
int witty_gl_test_context_loaded(void);

#endif
