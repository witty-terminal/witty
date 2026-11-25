#ifndef WITTY_GG_OPENGL_H
#define WITTY_GG_OPENGL_H

#ifndef SOKOL_GFX_INCLUDED
#include "sokol_gfx.h"
#endif
#include <stdlib.h>

#if defined(V_SOKOL_GL_CONTEXTS) && defined(SOKOL_GLCORE)
#include <EGL/egl.h>
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#endif
#include <GL/gl.h>

// V's Sokol module undefines Xlib's Status macro. The GLX context query
// needs no Xlib declarations.
typedef struct __GLXcontextRec *witty_gg_glx_context;
extern witty_gg_glx_context glXGetCurrentContext(void);

static inline void *witty_gg_gl_current_context(void) {
	EGLContext egl = eglGetCurrentContext();
	return egl != EGL_NO_CONTEXT ? (void *)egl : (void *)glXGetCurrentContext();
}

static inline void *witty_gg_gl_setup(const sg_desc *desc) {
	void *state = sg_v_gl_alloc_state();
	if (!state) return NULL;

	GLint vertex_array, unpack_alignment;
	glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vertex_array);
	glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpack_alignment);
	GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
	void *previous = sg_v_gl_select_state(state);
	sg_setup(desc);
	bool valid = sg_isvalid();
	sg_v_gl_select_state(previous);

	glBindVertexArray((GLuint)vertex_array);
	glPixelStorei(GL_UNPACK_ALIGNMENT, unpack_alignment);
	if (!scissor) glDisable(GL_SCISSOR_TEST);
	if (!valid) {
		sg_v_gl_destroy_state(state, true);
		return NULL;
	}
	return state;
}

static inline void witty_gg_gl_destroy(void *state, bool current) {
	sg_v_gl_destroy_state(state, current);
}

typedef struct {
	void *previous;
	GLint read_fbo;
	GLint draw_fbo;
	GLint viewport[4];
	GLint scissor[4];
	GLint vertex_array;
	GLint array_buffer;
	GLint program;
	GLboolean scissor_enabled;
	GLboolean srgb;
} witty_gg_gl_pass_scope;

static inline void *witty_gg_gl_begin_pass(void *state, const sg_pass *pass) {
	witty_gg_gl_pass_scope *scope = malloc(sizeof(*scope));
	if (!scope) return NULL;
	glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &scope->read_fbo);
	glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &scope->draw_fbo);
	glGetIntegerv(GL_VIEWPORT, scope->viewport);
	glGetIntegerv(GL_SCISSOR_BOX, scope->scissor);
	glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &scope->vertex_array);
	glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &scope->array_buffer);
	glGetIntegerv(GL_CURRENT_PROGRAM, &scope->program);
	scope->scissor_enabled = glIsEnabled(GL_SCISSOR_TEST);
	scope->srgb = glIsEnabled(GL_FRAMEBUFFER_SRGB);
	scope->previous = sg_v_gl_select_state(state);
	sg_v_gl_begin_fbo_pass(pass, scope->srgb);
	return scope;
}

static inline void witty_gg_gl_end_pass(void *capture) {
	witty_gg_gl_pass_scope *scope = capture;
	sg_end_pass();
	sg_v_gl_select_state(scope->previous);
	glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)scope->read_fbo);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)scope->draw_fbo);
	glViewport(scope->viewport[0], scope->viewport[1], scope->viewport[2], scope->viewport[3]);
	glScissor(scope->scissor[0], scope->scissor[1], scope->scissor[2], scope->scissor[3]);
	glBindVertexArray((GLuint)scope->vertex_array);
	glBindBuffer(GL_ARRAY_BUFFER, (GLuint)scope->array_buffer);
	glUseProgram((GLuint)scope->program);
	if (scope->scissor_enabled) glEnable(GL_SCISSOR_TEST);
	else glDisable(GL_SCISSOR_TEST);
	if (scope->srgb) glEnable(GL_FRAMEBUFFER_SRGB);
	else glDisable(GL_FRAMEBUFFER_SRGB);
	free(scope);
}

static inline void witty_gg_gl_commit(void *state) {
	void *previous = sg_v_gl_select_state(state);
	GLint vertex_array, array_buffer;
	glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vertex_array);
	glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &array_buffer);
	sg_v_gl_bind_vertex_array();
	sg_commit();
	glBindVertexArray((GLuint)vertex_array);
	glBindBuffer(GL_ARRAY_BUFFER, (GLuint)array_buffer);
	sg_v_gl_select_state(previous);
}
#else
static inline void *witty_gg_gl_current_context(void) { return NULL; }
static inline void *witty_gg_gl_setup(const sg_desc *desc) { return NULL; }
static inline void witty_gg_gl_destroy(void *state, bool current) {}
static inline void *witty_gg_gl_begin_pass(void *state, const sg_pass *pass) { return NULL; }
static inline void witty_gg_gl_end_pass(void *capture) {}
static inline void witty_gg_gl_commit(void *state) {}
#endif

#endif
