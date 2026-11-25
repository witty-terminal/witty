#pragma once

#include "gg_opengl.h"

typedef struct witty_gg_inspector_gl_target {
	unsigned int framebuffer;
	int width, height, samples;
	bool srgb;
} witty_gg_inspector_gl_target;

typedef struct witty_gg_inspector_gl_texture {
	int width, height;
} witty_gg_inspector_gl_texture;

#if defined(V_SOKOL_GL_CONTEXTS) && defined(SOKOL_GLCORE)
static inline witty_gg_inspector_gl_target witty_gg_inspector_gl_target_get(void) {
	GLint framebuffer, samples, viewport[4];
	glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &framebuffer);
	glGetIntegerv(GL_SAMPLES, &samples);
	glGetIntegerv(GL_VIEWPORT, viewport);
	GLint encoding = GL_LINEAR;
	if (framebuffer != 0) {
		glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			GL_FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING, &encoding);
	}
	return (witty_gg_inspector_gl_target){
		(unsigned int)framebuffer, viewport[2], viewport[3], samples > 0 ? samples : 1, encoding == GL_SRGB
	};
}

static inline witty_gg_inspector_gl_texture witty_gg_inspector_gl_texture_get(unsigned int name) {
	witty_gg_inspector_gl_texture size = {0};
	if (!glIsTexture(name)) return size;
	GLint previous;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &previous);
	glBindTexture(GL_TEXTURE_2D, name);
	glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &size.width);
	glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &size.height);
	glBindTexture(GL_TEXTURE_2D, (GLuint)previous);
	return size;
}
#else
static inline witty_gg_inspector_gl_target witty_gg_inspector_gl_target_get(void) {
	return (witty_gg_inspector_gl_target){0};
}
static inline witty_gg_inspector_gl_texture witty_gg_inspector_gl_texture_get(unsigned int name) {
	return (witty_gg_inspector_gl_texture){0};
}
#endif
