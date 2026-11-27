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

#if defined(SOKOL_METAL) && defined(V_SOKOL_MTL_END_PASS_HOOK) && defined(V_SOKOL_MTL_PASS_COMMAND_BUFFER)
#include <Metal/Metal.h>
#include <dispatch/dispatch.h>

// The UI thread owns the group. Only the group is captured by completion,
// keeping the command buffer and drawable local to the end-pass hook.
static dispatch_group_t witty_gg_ui2_readers;

static void witty_gg_ui2_window_pass(const void *command, const void *drawable, void *context) {
	if (!drawable) return;
	dispatch_group_t readers = (__bridge dispatch_group_t)context;
	dispatch_group_enter(readers);
	[(__bridge id<MTLCommandBuffer>)command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
		(void)completed;
		dispatch_group_leave(readers);
	}];
}

static inline bool witty_gg_ui2_tracks_frames(void) {
	return witty_gg_ui2_readers != NULL;
}

static inline void witty_gg_ui2_start_tracking(void) {
	if (witty_gg_ui2_readers) return;
	dispatch_group_t readers = dispatch_group_create();
	if (!readers) return;
	if (v_sokol_mtl_set_end_pass_hook(witty_gg_ui2_window_pass, (__bridge void*)readers)) {
		witty_gg_ui2_readers = readers;
		return;
	}
#if !__has_feature(objc_arc)
	dispatch_release(readers);
#endif
}

static inline void witty_gg_ui2_wait_for_readers(void) {
	if (witty_gg_ui2_readers) {
		dispatch_group_wait(witty_gg_ui2_readers, DISPATCH_TIME_FOREVER);
	}
}

static inline void witty_gg_ui2_stop_tracking(void) {
	if (!witty_gg_ui2_readers) return;
	v_sokol_mtl_set_end_pass_hook(NULL, (__bridge void*)witty_gg_ui2_readers);
	witty_gg_ui2_wait_for_readers();
#if !__has_feature(objc_arc)
	dispatch_release(witty_gg_ui2_readers);
#endif
	witty_gg_ui2_readers = NULL;
}
#else
static inline bool witty_gg_ui2_tracks_frames(void) { return false; }
static inline void witty_gg_ui2_start_tracking(void) {}
static inline void witty_gg_ui2_wait_for_readers(void) {}
static inline void witty_gg_ui2_stop_tracking(void) {}
#endif

#endif

#endif
