#ifndef WITTY_GG_METAL_H
#define WITTY_GG_METAL_H

#ifndef SOKOL_GFX_INCLUDED
#include "sokol_gfx.h"
#endif

#ifdef V_SOKOL_METAL_PACKED_FORMATS
#define WITTY_GG_BGRA8_SRGB SG_PIXELFORMAT_BGRA8_SRGB
#define WITTY_GG_USHORT2 SG_VERTEXFORMAT_USHORT2
#define WITTY_GG_UBYTE SG_VERTEXFORMAT_UBYTE
#else
#define WITTY_GG_BGRA8_SRGB SG_PIXELFORMAT_NONE
#define WITTY_GG_USHORT2 SG_VERTEXFORMAT_INVALID
#define WITTY_GG_UBYTE SG_VERTEXFORMAT_INVALID
#endif

#ifdef V_SOKOL_METAL_MIXED_SHADER_STAGES
#define WITTY_GG_MIXED_SHADER_STAGES 1
#else
#define WITTY_GG_MIXED_SHADER_STAGES 0
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <objc/message.h>
#include <pthread.h>
#include <stdbool.h>

static pthread_mutex_t witty_gg_metal_mutex = PTHREAD_MUTEX_INITIALIZER;

static inline void witty_gg_metal_lock(void) {
	pthread_mutex_lock(&witty_gg_metal_mutex);
}

static inline void witty_gg_metal_unlock(void) {
	pthread_mutex_unlock(&witty_gg_metal_mutex);
}

static inline bool witty_gg_metal_retain_import(void *object) {
#if !__has_feature(objc_arc)
	// Sokol releases imported Metal objects under manual reference
	// counting. Give it its own reference alongside Witty's.
	((void* (*)(void*, SEL))objc_msgSend)(object, sel_registerName("retain"));
	return true;
#else
	return false;
#endif
}

static inline void *witty_gg_metal_pass_command_buffer(void) {
#if defined(V_SOKOL_MTL_PASS_COMMAND_BUFFER)
	return (void *)sg_v_mtl_pass_command_buffer();
#else
	return NULL;
#endif
}
#endif

#endif
