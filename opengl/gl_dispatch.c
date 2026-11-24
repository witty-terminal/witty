#include "gl_dispatch.h"
#include <glad/gl.h>
#include <string.h>

#if defined(_MSC_VER)
#define WITTY_GL_THREAD_LOCAL __declspec(thread)
#else
#define WITTY_GL_THREAD_LOCAL _Thread_local
#endif

static WITTY_GL_THREAD_LOCAL GladGLContext witty_gl_context;

int witty_gl_load(void *get_proc_address) {
	if (get_proc_address != 0) {
		return gladLoadGLContext(&witty_gl_context, (GLADloadfunc)get_proc_address);
	}
	return gladLoaderLoadGLContext(&witty_gl_context);
}

void witty_gl_unload(void) {
	gladLoaderUnloadGLContext(&witty_gl_context);
	memset(&witty_gl_context, 0, sizeof(witty_gl_context));
}

int witty_glVertexBindingDivisor(unsigned int bindingindex, unsigned int divisor) {
	if (witty_gl_context.VertexBindingDivisor == 0) {
		return 0;
	}
	witty_gl_context.VertexBindingDivisor(bindingindex, divisor);
	return 1;
}

int witty_glVertexAttribBinding(unsigned int attribindex, unsigned int bindingindex) {
	if (witty_gl_context.VertexAttribBinding == 0) {
		return 0;
	}
	witty_gl_context.VertexAttribBinding(attribindex, bindingindex);
	return 1;
}

int witty_glVertexAttribFormat(
	unsigned int attribindex,
	int size,
	unsigned int type,
	unsigned char normalized,
	unsigned int relativeoffset
) {
	if (witty_gl_context.VertexAttribFormat == 0) {
		return 0;
	}
	witty_gl_context.VertexAttribFormat(attribindex, size, type, normalized, relativeoffset);
	return 1;
}

int witty_glVertexAttribIFormat(
	unsigned int attribindex,
	int size,
	unsigned int type,
	unsigned int relativeoffset
) {
	if (witty_gl_context.VertexAttribIFormat == 0) {
		return 0;
	}
	witty_gl_context.VertexAttribIFormat(attribindex, size, type, relativeoffset);
	return 1;
}

int witty_glVertexAttribLFormat(
	unsigned int attribindex,
	int size,
	unsigned int type,
	unsigned int relativeoffset
) {
	if (witty_gl_context.VertexAttribLFormat == 0) {
		return 0;
	}
	witty_gl_context.VertexAttribLFormat(attribindex, size, type, relativeoffset);
	return 1;
}

int witty_glBindVertexBuffer(
	unsigned int bindingindex,
	unsigned int buffer,
	intptr_t offset,
	int stride
) {
	if (witty_gl_context.BindVertexBuffer == 0) {
		return 0;
	}
	witty_gl_context.BindVertexBuffer(bindingindex, buffer, offset, stride);
	return 1;
}

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
) {
	if (witty_gl_context.BlitFramebuffer == 0) {
		return 0;
	}
	witty_gl_context.BlitFramebuffer(src_x0, src_y0, src_x1, src_y1, dst_x0, dst_y0, dst_x1, dst_y1, mask, filter);
	return 1;
}

int witty_glDebugMessageCallback(void *callback, void *user_param) {
	if (witty_gl_context.DebugMessageCallback == 0) {
		return 0;
	}
	witty_gl_context.DebugMessageCallback((GLDEBUGPROC)callback, user_param);
	return 1;
}

static const GLubyte *witty_gl_test_get_string(GLenum name) {
	if (name == GL_VERSION) {
		return (const GLubyte *)"4.3 Witty Glad test";
	}
	return (const GLubyte *)"";
}

static void witty_gl_test_get_integerv(GLenum name, GLint *value) {
	(void)name;
	if (value != 0) {
		*value = 0;
	}
}

static GLenum witty_gl_test_get_error(void) {
	return GL_NO_ERROR;
}

static void witty_gl_test_noop(void) {
}

static GLADapiproc witty_gl_test_resolver(const char *name) {
	if (strcmp(name, "glGetString") == 0) {
		return (GLADapiproc)witty_gl_test_get_string;
	}
	if (strcmp(name, "glGetIntegerv") == 0) {
		return (GLADapiproc)witty_gl_test_get_integerv;
	}
	if (strcmp(name, "glGetError") == 0) {
		return (GLADapiproc)witty_gl_test_get_error;
	}
	return (GLADapiproc)witty_gl_test_noop;
}

void *witty_gl_test_resolver_pointer(void) {
	return (void *)witty_gl_test_resolver;
}

int witty_gl_test_context_loaded(void) {
	return witty_gl_context.GetString != 0 &&
		witty_gl_context.GetIntegerv != 0 &&
		witty_gl_context.GetError != 0;
}

#define WITTY_GL_DEFINE(type, keyword, name, params, args) \
    type witty_gl##name params { keyword witty_gl_context.name args; }
WITTY_GL_DISPATCH(WITTY_GL_DEFINE)
#undef WITTY_GL_DEFINE
