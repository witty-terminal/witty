#ifndef WITTY_GG_METAL_H
#define WITTY_GG_METAL_H

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
	// Sokol releases the imported device and textures under manual reference
	// counting. Give it its own reference alongside Witty's.
	((void* (*)(void*, SEL))objc_msgSend)(object, sel_registerName("retain"));
	return true;
#else
	return false;
#endif
}
#endif

#endif
