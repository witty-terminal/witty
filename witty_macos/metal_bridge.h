#ifndef WITTY_METAL_BRIDGE_H
#define WITTY_METAL_BRIDGE_H
#pragma once
#ifndef WITTY_UI2_USES_VLIB_OBJC_BRIDGE
#include <objc_bridge.h>
#endif
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#endif
#include <stdbool.h>
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h>
#include <IOSurface/IOSurface.h>
#include <objc/runtime.h>
#endif
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_observe(void* center, void* observer, void* selector, void* name, void* object) {
	((void (*)(id, SEL, id, SEL, id, id))objc_msgSend)((id)center, sel_registerName("addObserver:selector:name:object:"), (id)observer, (SEL)selector, (id)name, (id)object);
}
#endif

typedef struct witty_macos_point {
	double x;
	double y;
} witty_macos_point;

typedef struct witty_macos_size {
	double width;
	double height;
} witty_macos_size;

typedef struct witty_macos_clear_color {
	double red;
	double green;
	double blue;
	double alpha;
} witty_macos_clear_color;

typedef struct witty_macos_string_task {
	void* view;
	char* text;
} witty_macos_string_task;

typedef struct witty_metal_vertex_attribute {
	unsigned long long format;
	size_t offset;
} witty_metal_vertex_attribute;

typedef struct witty_metal_pipeline_attachment {
	unsigned long long pixel_format;
	bool blending_enabled;
} witty_metal_pipeline_attachment;

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef void (*witty_metal_layer_display_callback)(void*);
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef void (*witty_metal_command_buffer_completion_callback)(
	void*,
	void*,
	unsigned long long,
	bool
);
#endif

/*
 * Minimal Objective-C block ABI used by MTLCommandBuffer's
 * addCompletedHandler:. The block captures only raw pointers, so it needs no
 * copy/dispose helpers; Metal copies the stack block before this function
 * returns and releases that copy after invocation.
 */
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef struct witty_block_descriptor {
	unsigned long reserved;
	unsigned long size;
} witty_block_descriptor;
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef struct witty_metal_completion_block {
	void* isa;
	int flags;
	int reserved;
	void (*invoke)(struct witty_metal_completion_block*, void*);
	const witty_block_descriptor* descriptor;
	witty_metal_command_buffer_completion_callback callback;
	void* renderer;
	void* target;
} witty_metal_completion_block;
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern void* _NSConcreteStackBlock[32];
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static const witty_block_descriptor witty_metal_completion_descriptor = {
	0,
	sizeof(witty_metal_completion_block),
};
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef struct witty_ns_operating_system_version {
	long long major;
	long long minor;
	long long patch;
} witty_ns_operating_system_version;
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_macos_is_at_least_version(long long major, long long minor, long long patch) {
	Class cls = objc_getClass("NSProcessInfo");
	if (!cls) return false;
	id info = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("processInfo"));
	if (!info) return false;
	witty_ns_operating_system_version version = { major, minor, patch };
	return ((bool (*)(id, SEL, witty_ns_operating_system_version))objc_msgSend)(
		info,
		sel_registerName("isOperatingSystemAtLeastVersion:"),
		version
	);
}
#endif

// Returns an owned UTF-8 copy of NSFileManager's user-domain directory path.
// The caller must release it with free().
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline char* witty_macos_user_directory(unsigned long directory) {
	Class pool_cls = objc_getClass("NSAutoreleasePool");
	id pool = pool_cls
		? ((id (*)(id, SEL))objc_msgSend)(
			((id (*)(id, SEL))objc_msgSend)((id)pool_cls, sel_registerName("alloc")),
			sel_registerName("init")
		)
		: nil;
	Class manager_cls = objc_getClass("NSFileManager");
	id manager = manager_cls
		? ((id (*)(id, SEL))objc_msgSend)((id)manager_cls, sel_registerName("defaultManager"))
		: nil;
	id url = manager
		? ((id (*)(id, SEL, unsigned long, unsigned long, id, bool, id*))objc_msgSend)(
			manager,
			sel_registerName("URLForDirectory:inDomain:appropriateForURL:create:error:"),
			directory,
			1ul,
			nil,
			true,
			nil
		)
		: nil;
	id path = url
		? ((id (*)(id, SEL))objc_msgSend)(url, sel_registerName("path"))
		: nil;
	const char* utf8 = path
		? ((const char* (*)(id, SEL))objc_msgSend)(path, sel_registerName("UTF8String"))
		: NULL;
	char* result = utf8 ? strdup(utf8) : NULL;
	if (pool) ((void (*)(id, SEL))objc_msgSend)(pool, sel_registerName("drain"));
	return result;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_macos_is_main_thread(void) {
	return pthread_main_np() != 0;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_dispatch_main(void* fn, void* ctx) {
	if (!fn) return;
	dispatch_async_f(dispatch_get_main_queue(), ctx, (dispatch_function_t)fn);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline witty_macos_string_task* witty_macos_string_task_new(void* view, char* text) {
	witty_macos_string_task* task = (witty_macos_string_task*)calloc(1, sizeof(witty_macos_string_task));
	if (!task) return NULL;
	task->view = view;
	if (text) {
		size_t len = strlen(text);
		task->text = (char*)malloc(len + 1);
		if (!task->text) {
			free(task);
			return NULL;
		}
		memcpy(task->text, text, len + 1);
	}
	return task;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_string_task_free(witty_macos_string_task* task) {
	if (!task) return;
	free(task->text);
	free(task);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline witty_macos_point witty_macos_objc_msg_point0(void* obj, void* sel) {
	return ((witty_macos_point (*)(void*, void*))objc_msgSend)(obj, sel);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline witty_macos_point witty_macos_objc_msg_point_point_obj(void* obj, void* sel, witty_macos_point point, void* a1) {
	return ((witty_macos_point (*)(void*, void*, witty_macos_point, void*))objc_msgSend)(obj, sel, point, a1);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_macos_objc_msg_bool2(void* obj, void* sel, void* a0, void* a1) {
	return ((bool (*)(void*, void*, void*, void*))objc_msgSend)(obj, sel, a0, a1);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_macos_objc_msg_bool_u64(void* obj, void* sel, unsigned long long a0) {
	return ((bool (*)(void*, void*, unsigned long long))objc_msgSend)(obj, sel, a0);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_macos_objc_msg_id_rect_u64_obj_obj(
	void* obj,
	void* selector,
	macos_rect rect,
	unsigned long long options,
	void* owner,
	void* user_info
) {
	return ((void* (*)(void*, void*, macos_rect, unsigned long long, void*, void*))objc_msgSend)(
		obj,
		selector,
		rect,
		options,
		owner,
		user_info
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline Class witty_macos_objc_superclass(void* obj) {
	if (!obj) return Nil;
	return class_getSuperclass(object_getClass((id)obj));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_macos_objc_msg_super_bool0(void* obj, void* selector) {
	Class superclass = witty_macos_objc_superclass(obj);
	if (!superclass) return false;
	struct objc_super info = { (id)obj, superclass };
	return ((bool (*)(struct objc_super*, SEL))objc_msgSendSuper)(&info, (SEL)selector);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_objc_msg_super_void0(void* obj, void* selector) {
	Class superclass = witty_macos_objc_superclass(obj);
	if (!superclass) return;
	struct objc_super info = { (id)obj, superclass };
	((void (*)(struct objc_super*, SEL))objc_msgSendSuper)(&info, (SEL)selector);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_objc_msg_super_void1(void* obj, void* selector, void* value) {
	Class superclass = witty_macos_objc_superclass(obj);
	if (!superclass) return;
	struct objc_super info = { (id)obj, superclass };
	((void (*)(struct objc_super*, SEL, void*))objc_msgSendSuper)(&info, (SEL)selector, value);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_objc_msg_void_size(void* obj, void* sel, witty_macos_size size) {
	((void (*)(void*, void*, witty_macos_size))objc_msgSend)(obj, sel, size);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_objc_msg_void_clear_color(void* obj, void* sel, witty_macos_clear_color color) {
	((void (*)(void*, void*, witty_macos_clear_color))objc_msgSend)(obj, sel, color);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_new_buffer_length(void* device, size_t length, unsigned long long options) {
	if (!device) return NULL;
	return ((void* (*)(void*, SEL, unsigned long, unsigned long long))objc_msgSend)(
		device,
		sel_registerName("newBufferWithLength:options:"),
		(unsigned long)length,
		options
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_new_buffer_bytes(void* device, const void* bytes, size_t length, unsigned long long options) {
	if (!device || (!bytes && length != 0)) return NULL;
	return ((void* (*)(void*, SEL, const void*, unsigned long, unsigned long long))objc_msgSend)(
		device,
		sel_registerName("newBufferWithBytes:length:options:"),
		bytes,
		(unsigned long)length,
		options
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline size_t witty_metal_buffer_length(void* buffer) {
	if (!buffer) return 0;
	return ((unsigned long (*)(void*, SEL))objc_msgSend)(buffer, sel_registerName("length"));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_buffer_contents(void* buffer) {
	if (!buffer) return NULL;
	return ((void* (*)(void*, SEL))objc_msgSend)(buffer, sel_registerName("contents"));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_buffer_did_modify(void* buffer, size_t length) {
	if (!buffer) return;
	NSRange range = NSMakeRange(0, length);
	((void (*)(void*, SEL, NSRange))objc_msgSend)(buffer, sel_registerName("didModifyRange:"), range);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_new_texture(
	void* device,
	unsigned long long pixel_format,
	size_t width,
	size_t height,
	unsigned long long resource_options,
	unsigned long long usage
) {
	if (!device || width == 0 || height == 0) return NULL;
	Class cls = objc_getClass("MTLTextureDescriptor");
	if (!cls) return NULL;
	void* desc = ((void* (*)(void*, SEL))objc_msgSend)((void*)cls, sel_registerName("alloc"));
	desc = ((void* (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("init"));
	if (!desc) return NULL;
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setPixelFormat:"), pixel_format);
	((void (*)(void*, SEL, unsigned long))objc_msgSend)(desc, sel_registerName("setWidth:"), (unsigned long)width);
	((void (*)(void*, SEL, unsigned long))objc_msgSend)(desc, sel_registerName("setHeight:"), (unsigned long)height);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setResourceOptions:"), resource_options);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setUsage:"), usage);
	void* texture = ((void* (*)(void*, SEL, void*))objc_msgSend)(device, sel_registerName("newTextureWithDescriptor:"), desc);
	((void (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("release"));
	return texture;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_texture_replace_region(
	void* texture,
	size_t x,
	size_t y,
	size_t width,
	size_t height,
	const void* bytes,
	size_t bytes_per_row
) {
	if (!texture || !bytes) return;
	MTLRegion region = MTLRegionMake2D((NSUInteger)x, (NSUInteger)y, (NSUInteger)width, (NSUInteger)height);
	((void (*)(void*, SEL, MTLRegion, unsigned long, const void*, unsigned long))objc_msgSend)(
		texture,
		sel_registerName("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"),
		region,
		0,
		bytes,
		(unsigned long)bytes_per_row
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_texture_get_bytes(
	void* texture,
	void* bytes,
	size_t bytes_per_row,
	size_t x,
	size_t y,
	size_t width,
	size_t height
) {
	if (!texture || !bytes) return;
	MTLRegion region = MTLRegionMake2D((NSUInteger)x, (NSUInteger)y, (NSUInteger)width, (NSUInteger)height);
	((void (*)(void*, SEL, void*, unsigned long, MTLRegion, unsigned long))objc_msgSend)(
		texture,
		sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
		bytes,
		(unsigned long)bytes_per_row,
		region,
		0
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_command_buffer_commit(void* command_buffer) {
	if (!command_buffer) return;
	((void (*)(void*, SEL))objc_msgSend)(command_buffer, sel_registerName("commit"));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_command_buffer_wait(void* command_buffer) {
	if (!command_buffer) return;
	((void (*)(void*, SEL))objc_msgSend)(command_buffer, sel_registerName("waitUntilCompleted"));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline unsigned long long witty_metal_command_buffer_status(void* command_buffer) {
	if (!command_buffer) return 5;
	return ((unsigned long long (*)(void*, SEL))objc_msgSend)(command_buffer, sel_registerName("status"));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_command_buffer_completion_invoke(
	witty_metal_completion_block* block,
	void* command_buffer
) {
	if (!block || !block->callback) return;
	block->callback(
		block->renderer,
		block->target,
		witty_metal_command_buffer_status(command_buffer),
		false
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_metal_command_buffer_add_completed_handler(
	void* command_buffer,
	witty_metal_command_buffer_completion_callback callback,
	void* renderer,
	void* target
) {
	if (!command_buffer || !callback) return false;
	witty_metal_completion_block block = {
		_NSConcreteStackBlock,
		0,
		0,
		witty_metal_command_buffer_completion_invoke,
		&witty_metal_completion_descriptor,
		callback,
		renderer,
		target,
	};
	((void (*)(void*, SEL, void*))objc_msgSend)(
		command_buffer,
		sel_registerName("addCompletedHandler:"),
		&block
	);
	return true;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_command_buffer_invoke_completion(
	void* command_buffer,
	witty_metal_command_buffer_completion_callback callback,
	void* renderer,
	void* target,
	bool sync
) {
	if (!command_buffer || !callback) return;
	callback(
		renderer,
		target,
		witty_metal_command_buffer_status(command_buffer),
		sync
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_render_pass_descriptor(void) {
	Class cls = objc_getClass("MTLRenderPassDescriptor");
	if (!cls) return NULL;
	return ((void* (*)(void*, SEL))objc_msgSend)((void*)cls, sel_registerName("renderPassDescriptor"));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_render_pass_set_attachment(
	void* descriptor,
	unsigned long index,
	void* texture,
	bool has_clear_color,
	witty_macos_clear_color color
) {
	if (!descriptor || !texture) return;
	void* attachments = ((void* (*)(void*, SEL))objc_msgSend)(descriptor, sel_registerName("colorAttachments"));
	void* attachment = ((void* (*)(void*, SEL, unsigned long))objc_msgSend)(attachments, sel_registerName("objectAtIndexedSubscript:"), index);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setLoadAction:"), has_clear_color ? 2ull : 1ull);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setStoreAction:"), 1ull);
	((void (*)(void*, SEL, void*))objc_msgSend)(attachment, sel_registerName("setTexture:"), texture);
	if (has_clear_color) {
		MTLClearColor clear = MTLClearColorMake(color.red, color.green, color.blue, color.alpha);
		((void (*)(void*, SEL, MTLClearColor))objc_msgSend)(attachment, sel_registerName("setClearColor:"), clear);
	}
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_encoder_set_pipeline(void* encoder, void* pipeline) {
	if (!encoder || !pipeline) return;
	((void (*)(void*, SEL, void*))objc_msgSend)(encoder, sel_registerName("setRenderPipelineState:"), pipeline);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_encoder_set_buffer(void* encoder, void* buffer, unsigned long index) {
	if (!encoder || !buffer) return;
	((void (*)(void*, SEL, void*, unsigned long, unsigned long))objc_msgSend)(encoder, sel_registerName("setVertexBuffer:offset:atIndex:"), buffer, 0, index);
	((void (*)(void*, SEL, void*, unsigned long, unsigned long))objc_msgSend)(encoder, sel_registerName("setFragmentBuffer:offset:atIndex:"), buffer, 0, index);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_encoder_set_texture(void* encoder, void* texture, unsigned long index) {
	if (!encoder || !texture) return;
	((void (*)(void*, SEL, void*, unsigned long))objc_msgSend)(encoder, sel_registerName("setVertexTexture:atIndex:"), texture, index);
	((void (*)(void*, SEL, void*, unsigned long))objc_msgSend)(encoder, sel_registerName("setFragmentTexture:atIndex:"), texture, index);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_encoder_set_sampler(void* encoder, void* sampler, unsigned long index) {
	if (!encoder || !sampler) return;
	((void (*)(void*, SEL, void*, unsigned long))objc_msgSend)(encoder, sel_registerName("setFragmentSamplerState:atIndex:"), sampler, index);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_encoder_draw(
	void* encoder,
	unsigned long long primitive,
	unsigned long vertex_count,
	unsigned long instance_count
) {
	if (!encoder || instance_count == 0) return;
	((void (*)(void*, SEL, unsigned long long, unsigned long, unsigned long, unsigned long))objc_msgSend)(
		encoder,
		sel_registerName("drawPrimitives:vertexStart:vertexCount:instanceCount:"),
		primitive,
		0,
		vertex_count,
		instance_count
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_new_sampler(
	void* device,
	unsigned long long min_filter,
	unsigned long long mag_filter,
	unsigned long long s_address_mode,
	unsigned long long t_address_mode
) {
	if (!device) return NULL;
	Class cls = objc_getClass("MTLSamplerDescriptor");
	if (!cls) return NULL;
	void* desc = ((void* (*)(void*, SEL))objc_msgSend)((void*)cls, sel_registerName("alloc"));
	desc = ((void* (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("init"));
	if (!desc) return NULL;
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setMinFilter:"), min_filter);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setMagFilter:"), mag_filter);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setSAddressMode:"), s_address_mode);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setTAddressMode:"), t_address_mode);
	void* sampler = ((void* (*)(void*, SEL, void*))objc_msgSend)(device, sel_registerName("newSamplerStateWithDescriptor:"), desc);
	((void (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("release"));
	return sampler;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_new_iosurface_texture(
	void* device,
	void* surface,
	unsigned long long pixel_format,
	size_t width,
	size_t height,
	unsigned long long resource_options,
	unsigned long long usage
) {
	if (!device || !surface || width == 0 || height == 0) return NULL;
	Class cls = objc_getClass("MTLTextureDescriptor");
	if (!cls) return NULL;
	void* desc = ((void* (*)(void*, SEL))objc_msgSend)((void*)cls, sel_registerName("alloc"));
	desc = ((void* (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("init"));
	if (!desc) return NULL;
	((void (*)(void*, SEL, unsigned long))objc_msgSend)(desc, sel_registerName("setWidth:"), (unsigned long)width);
	((void (*)(void*, SEL, unsigned long))objc_msgSend)(desc, sel_registerName("setHeight:"), (unsigned long)height);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setPixelFormat:"), pixel_format);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setUsage:"), usage);
	((void (*)(void*, SEL, unsigned long long))objc_msgSend)(desc, sel_registerName("setResourceOptions:"), resource_options);
	void* texture = ((void* (*)(void*, SEL, void*, void*, unsigned long))objc_msgSend)(device, sel_registerName("newTextureWithDescriptor:iosurface:plane:"), desc, surface, 0);
	((void (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("release"));
	return texture;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_nsstring(const char* bytes, size_t length) {
	if (!bytes) return NULL;
	Class cls = objc_getClass("NSString");
	if (!cls) return NULL;
	void* value = ((void* (*)(void*, SEL))objc_msgSend)((void*)cls, sel_registerName("alloc"));
	return ((void* (*)(void*, SEL, const void*, unsigned long, unsigned long))objc_msgSend)(
		value,
		sel_registerName("initWithBytes:length:encoding:"),
		bytes,
		(unsigned long)length,
		4
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_new_library_source(void* device, const char* source, size_t length) {
	if (!device || !source) return NULL;
	void* string = witty_metal_nsstring(source, length);
	if (!string) return NULL;
	void* error = NULL;
	void* library = ((void* (*)(void*, SEL, void*, void*, void**))objc_msgSend)(device, sel_registerName("newLibraryWithSource:options:error:"), string, NULL, &error);
	((void (*)(void*, SEL))objc_msgSend)(string, sel_registerName("release"));
	return library;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_library_data(void* device, void* data, void** error) {
	return ((void* (*)(void*, SEL, void*, void**))objc_msgSend)(device, sel_registerName("newLibraryWithData:error:"), data, error);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_dispatch_data(const void* bytes, size_t length) {
	return (void*)dispatch_data_create(bytes, length, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_dispatch_release(void* data) { dispatch_release((dispatch_data_t)data); }
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline const char* witty_metal_error_description(void* error) {
	void* description = ((void* (*)(void*, SEL))objc_msgSend)(error, sel_registerName("localizedDescription"));
	return ((const char* (*)(void*, SEL, unsigned long))objc_msgSend)(description, sel_registerName("cStringUsingEncoding:"), 1);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_new_pipeline(
	void* device,
	void* vertex_library,
	void* fragment_library,
	const char* vertex_name,
	size_t vertex_name_length,
	const char* fragment_name,
	size_t fragment_name_length,
	const witty_metal_vertex_attribute* attributes,
	size_t attribute_count,
	size_t vertex_stride,
	unsigned long long step_function,
	const witty_metal_pipeline_attachment* pipeline_attachments,
	size_t pipeline_attachment_count
) {
	if (!device || !vertex_library || !fragment_library || !vertex_name || !fragment_name) return NULL;
	void* vertex_string = witty_metal_nsstring(vertex_name, vertex_name_length);
	void* fragment_string = witty_metal_nsstring(fragment_name, fragment_name_length);
	if (!vertex_string || !fragment_string) {
		if (vertex_string) ((void (*)(void*, SEL))objc_msgSend)(vertex_string, sel_registerName("release"));
		if (fragment_string) ((void (*)(void*, SEL))objc_msgSend)(fragment_string, sel_registerName("release"));
		return NULL;
	}
	void* vertex_function = ((void* (*)(void*, SEL, void*))objc_msgSend)(vertex_library, sel_registerName("newFunctionWithName:"), vertex_string);
	void* fragment_function = ((void* (*)(void*, SEL, void*))objc_msgSend)(fragment_library, sel_registerName("newFunctionWithName:"), fragment_string);
	((void (*)(void*, SEL))objc_msgSend)(vertex_string, sel_registerName("release"));
	((void (*)(void*, SEL))objc_msgSend)(fragment_string, sel_registerName("release"));
	if (!vertex_function || !fragment_function) {
		if (vertex_function) ((void (*)(void*, SEL))objc_msgSend)(vertex_function, sel_registerName("release"));
		if (fragment_function) ((void (*)(void*, SEL))objc_msgSend)(fragment_function, sel_registerName("release"));
		return NULL;
	}

	Class pipeline_cls = objc_getClass("MTLRenderPipelineDescriptor");
	void* desc = ((void* (*)(void*, SEL))objc_msgSend)((void*)pipeline_cls, sel_registerName("alloc"));
	desc = ((void* (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("init"));
	((void (*)(void*, SEL, void*))objc_msgSend)(desc, sel_registerName("setVertexFunction:"), vertex_function);
	((void (*)(void*, SEL, void*))objc_msgSend)(desc, sel_registerName("setFragmentFunction:"), fragment_function);

	void* vertex_desc = NULL;
	if (attribute_count > 0) {
		Class vertex_cls = objc_getClass("MTLVertexDescriptor");
		vertex_desc = ((void* (*)(void*, SEL))objc_msgSend)((void*)vertex_cls, sel_registerName("alloc"));
		vertex_desc = ((void* (*)(void*, SEL))objc_msgSend)(vertex_desc, sel_registerName("init"));
		void* attrs = ((void* (*)(void*, SEL))objc_msgSend)(vertex_desc, sel_registerName("attributes"));
		for (size_t i = 0; i < attribute_count; ++i) {
			void* attr = ((void* (*)(void*, SEL, unsigned long))objc_msgSend)(attrs, sel_registerName("objectAtIndexedSubscript:"), (unsigned long)i);
			((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attr, sel_registerName("setFormat:"), attributes[i].format);
			((void (*)(void*, SEL, unsigned long))objc_msgSend)(attr, sel_registerName("setOffset:"), (unsigned long)attributes[i].offset);
			((void (*)(void*, SEL, unsigned long))objc_msgSend)(attr, sel_registerName("setBufferIndex:"), 0);
		}
		void* layouts = ((void* (*)(void*, SEL))objc_msgSend)(vertex_desc, sel_registerName("layouts"));
		void* layout = ((void* (*)(void*, SEL, unsigned long))objc_msgSend)(layouts, sel_registerName("objectAtIndexedSubscript:"), 0);
		((void (*)(void*, SEL, unsigned long long))objc_msgSend)(layout, sel_registerName("setStepFunction:"), step_function);
		((void (*)(void*, SEL, unsigned long))objc_msgSend)(layout, sel_registerName("setStride:"), (unsigned long)vertex_stride);
		((void (*)(void*, SEL, void*))objc_msgSend)(desc, sel_registerName("setVertexDescriptor:"), vertex_desc);
	}

	void* color_attachments = ((void* (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("colorAttachments"));
	for (size_t i = 0; i < pipeline_attachment_count; ++i) {
		void* attachment = ((void* (*)(void*, SEL, unsigned long))objc_msgSend)(color_attachments, sel_registerName("objectAtIndexedSubscript:"), (unsigned long)i);
		((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setPixelFormat:"), pipeline_attachments[i].pixel_format);
		((void (*)(void*, SEL, bool))objc_msgSend)(attachment, sel_registerName("setBlendingEnabled:"), pipeline_attachments[i].blending_enabled);
		if (pipeline_attachments[i].blending_enabled) {
			((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setRgbBlendOperation:"), 0);
			((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setAlphaBlendOperation:"), 0);
			((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setSourceRGBBlendFactor:"), 1);
			((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setSourceAlphaBlendFactor:"), 1);
			((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setDestinationRGBBlendFactor:"), 5);
			((void (*)(void*, SEL, unsigned long long))objc_msgSend)(attachment, sel_registerName("setDestinationAlphaBlendFactor:"), 5);
		}
	}

	void* error = NULL;
	void* state = ((void* (*)(void*, SEL, void*, void**))objc_msgSend)(device, sel_registerName("newRenderPipelineStateWithDescriptor:error:"), desc, &error);
	if (vertex_desc) ((void (*)(void*, SEL))objc_msgSend)(vertex_desc, sel_registerName("release"));
	((void (*)(void*, SEL))objc_msgSend)(desc, sel_registerName("release"));
	((void (*)(void*, SEL))objc_msgSend)(vertex_function, sel_registerName("release"));
	((void (*)(void*, SEL))objc_msgSend)(fragment_function, sel_registerName("release"));
	return state;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_iosurface_layer_display(void* target, SEL command) {
	(void)command;
	Ivar callback_ivar = class_getInstanceVariable(object_getClass(target), "display_cb");
	Ivar context_ivar = class_getInstanceVariable(object_getClass(target), "display_ctx");
	witty_metal_layer_display_callback callback = (witty_metal_layer_display_callback)object_getIvar(target, callback_ivar);
	void* context = object_getIvar(target, context_ivar);
	if (callback) callback(context);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_iosurface_layer_action(void* target, SEL command, void* key) {
	(void)target;
	(void)command;
	(void)key;
	Class cls = objc_getClass("NSNull");
	return cls ? ((void* (*)(void*, SEL))objc_msgSend)((void*)cls, sel_registerName("null")) : NULL;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline Class witty_metal_iosurface_layer_class(void) {
	static Class subclass = Nil;
	static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
	if (subclass) return subclass;
	pthread_mutex_lock(&lock);
	if (!subclass) {
		Class superclass = objc_getClass("CALayer");
		subclass = objc_allocateClassPair(superclass, "WittyIOSurfaceLayer", 0);
		if (!subclass) {
			subclass = objc_getClass("WittyIOSurfaceLayer");
		} else {
			class_addIvar(subclass, "display_cb", sizeof(void*), 3, "^v");
			class_addIvar(subclass, "display_ctx", sizeof(void*), 3, "^v");
			class_addMethod(subclass, sel_registerName("display"), (IMP)witty_metal_iosurface_layer_display, "v@:");
			class_addMethod(subclass, sel_registerName("actionForKey:"), (IMP)witty_metal_iosurface_layer_action, "@@:@");
			objc_registerClassPair(subclass);
		}
	}
	pthread_mutex_unlock(&lock);
	return subclass;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_metal_iosurface_layer_new(void) {
	Class cls = witty_metal_iosurface_layer_class();
	if (!cls) return NULL;
	void* layer = ((void* (*)(void*, SEL))objc_msgSend)((void*)cls, sel_registerName("layer"));
	if (!layer) return NULL;
	((void (*)(void*, SEL))objc_msgSend)(layer, sel_registerName("retain"));
	Class string_cls = objc_getClass("NSString");
	void* gravity = ((void* (*)(void*, SEL, const char*))objc_msgSend)((void*)string_cls, sel_registerName("stringWithUTF8String:"), "topLeft");
	((void (*)(void*, SEL, void*))objc_msgSend)(layer, sel_registerName("setContentsGravity:"), gravity);
	return layer;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_iosurface_layer_set_display_callback(void* layer, witty_metal_layer_display_callback callback, void* context) {
	if (!layer) return;
	Ivar callback_ivar = class_getInstanceVariable(object_getClass(layer), "display_cb");
	Ivar context_ivar = class_getInstanceVariable(object_getClass(layer), "display_ctx");
	object_setIvar(layer, callback_ivar, (void*)callback);
	object_setIvar(layer, context_ivar, context);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_iosurface_layer_set_surface_sync(void* layer, void* surface) {
	if (!layer || !surface) return;
	((void (*)(void*, SEL, void*))objc_msgSend)(layer, sel_registerName("setContents:"), surface);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef struct witty_metal_layer_surface_task {
	void* layer;
	IOSurfaceRef surface;
} witty_metal_layer_surface_task;
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_metal_iosurface_layer_set_surface_task(void* context) {
	witty_metal_layer_surface_task* task = (witty_metal_layer_surface_task*)context;
	CGRect bounds = ((CGRect (*)(void*, SEL))objc_msgSend)(task->layer, sel_registerName("bounds"));
	double scale = ((double (*)(void*, SEL))objc_msgSend)(task->layer, sel_registerName("contentsScale"));
	size_t width = (size_t)(bounds.size.width * scale);
	size_t height = (size_t)(bounds.size.height * scale);
	if (width == IOSurfaceGetWidth(task->surface) && height == IOSurfaceGetHeight(task->surface)) {
		witty_metal_iosurface_layer_set_surface_sync(task->layer, task->surface);
	}
	((void (*)(void*, SEL))objc_msgSend)(task->layer, sel_registerName("release"));
	CFRelease(task->surface);
	free(task);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_metal_iosurface_layer_set_surface(void* layer, void* surface) {
	if (!layer || !surface) return false;
	witty_metal_layer_surface_task* task = (witty_metal_layer_surface_task*)calloc(1, sizeof(witty_metal_layer_surface_task));
	if (!task) return false;
	task->layer = ((void* (*)(void*, SEL))objc_msgSend)(layer, sel_registerName("retain"));
	task->surface = (IOSurfaceRef)CFRetain(surface);
	if (pthread_main_np() != 0) {
		witty_metal_iosurface_layer_set_surface_task(task);
	} else {
		dispatch_async_f(dispatch_get_main_queue(), task, witty_metal_iosurface_layer_set_surface_task);
	}
	return true;
}
#endif
#endif
