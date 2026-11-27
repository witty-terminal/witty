#include "metal_bridge.h"

// Private CoreGraphics APIs used by Terminal.app and other terminals to set
// the blur radius behind a translucent NSWindow.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern void* CGSDefaultConnectionForThread(void);
extern int CGSSetWindowBackgroundBlurRadius(void*, size_t, int);
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_set_window_background_blur(void* window, int radius) {
	if (!window) return;
	SEL selector = sel_registerName("windowNumber");
	size_t window_number = ((size_t (*)(id, SEL))objc_msgSend)((id)window, selector);
	(void)CGSSetWindowBackgroundBlurRadius(
		CGSDefaultConnectionForThread(),
		window_number,
		radius
	);
}
#endif

/* ABI adapters for NSTextInputClient and NSEvent. Policy lives in V. */
typedef struct witty_macos_range { unsigned long location, length; } witty_macos_range;
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline witty_macos_range witty_macos_msg_range(void* obj, void* selector) {
	return ((witty_macos_range (*)(id, SEL))objc_msgSend)((id)obj, (SEL)selector);
}
static inline void* witty_macos_msg_id_range(void* obj, void* selector, witty_macos_range range) {
	return ((void* (*)(id, SEL, witty_macos_range))objc_msgSend)((id)obj, (SEL)selector, range);
}
static inline void* witty_macos_msg_super_id2(void* obj, void* selector, void* a, void* b) {
	struct objc_super info = {(id)obj, witty_macos_objc_superclass(obj)};
	return ((void* (*)(struct objc_super*, SEL, id, id))objc_msgSendSuper)(&info, (SEL)selector, (id)a, (id)b);
}
static inline macos_rect witty_macos_msg_rect_rect_obj(void* obj, void* selector, macos_rect rect, void* other) {
	return ((macos_rect (*)(id, SEL, macos_rect, id))objc_msgSend)((id)obj, (SEL)selector, rect, (id)other);
}
static inline macos_rect witty_macos_msg_rect_rect(void* obj, void* selector, macos_rect rect) {
	return ((macos_rect (*)(id, SEL, macos_rect))objc_msgSend)((id)obj, (SEL)selector, rect);
}
static inline void* witty_macos_key_event(void* original, unsigned long long flags, void* chars, void* ignoring) {
	id event = (id)original;
	return ((void* (*)(id, SEL, unsigned long long, witty_macos_point, unsigned long long, double, long long, id, id, id, bool, unsigned short))objc_msgSend)(
		(id)objc_getClass("NSEvent"), sel_registerName("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
		((unsigned long long (*)(id, SEL))objc_msgSend)(event, sel_registerName("type")),
		((witty_macos_point (*)(id, SEL))objc_msgSend)(event, sel_registerName("locationInWindow")), flags,
		((double (*)(id, SEL))objc_msgSend)(event, sel_registerName("timestamp")),
		((long long (*)(id, SEL))objc_msgSend)(event, sel_registerName("windowNumber")), nil, (id)chars, (id)ignoring,
		((bool (*)(id, SEL))objc_msgSend)(event, sel_registerName("isARepeat")),
		((unsigned short (*)(id, SEL))objc_msgSend)(event, sel_registerName("keyCode")));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef void* (*witty_event_monitor_callback)(void*);
typedef struct witty_event_monitor_block {
	void* isa; int flags; int reserved;
	void* (*invoke)(struct witty_event_monitor_block*, void*);
	const witty_block_descriptor* descriptor;
	witty_event_monitor_callback callback;
} witty_event_monitor_block;
static void* witty_event_monitor_invoke(witty_event_monitor_block* block, void* event) { return block->callback(event); }
static const witty_block_descriptor witty_event_monitor_descriptor = {0, sizeof(witty_event_monitor_block)};
static inline void* witty_macos_monitor_key_releases(void* callback) {
	witty_event_monitor_block block = {_NSConcreteStackBlock, 0, 0, witty_event_monitor_invoke, &witty_event_monitor_descriptor, (witty_event_monitor_callback)callback};
	return ((void* (*)(id, SEL, unsigned long long, void*))objc_msgSend)((id)objc_getClass("NSEvent"), sel_registerName("addLocalMonitorForEventsMatchingMask:handler:"), 1ULL << 11, &block);
}
static inline void witty_macos_msg_super_from_void0(void* obj, void* defining_class, void* selector) {
	struct objc_super info = {(id)obj, class_getSuperclass((Class)defining_class)};
	((void (*)(struct objc_super*, SEL))objc_msgSendSuper)(&info, (SEL)selector);
}
static inline witty_macos_range witty_macos_msg_range_u64(void* obj, void* selector, unsigned long long index) {
	return ((witty_macos_range (*)(id, SEL, unsigned long long))objc_msgSend)((id)obj, (SEL)selector, index);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef struct witty_cache_timer_context {
	dispatch_source_t timer;
	void (*callback)(void*);
	void* context;
} witty_cache_timer_context;
static void witty_cache_timer_cancelled(void* raw) { free(raw); }
static void witty_cache_timer_fired(void* raw) {
	witty_cache_timer_context* ctx = raw;
	ctx->callback(ctx->context);
	dispatch_source_cancel(ctx->timer);
	dispatch_release(ctx->timer);
}
static inline void* witty_macos_cache_timer(unsigned long long duration, void* callback, void* context) {
	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	witty_cache_timer_context* ctx = malloc(sizeof(*ctx));
	ctx->timer = timer; ctx->callback = callback; ctx->context = context;
	dispatch_set_context(timer, ctx);
	dispatch_source_set_event_handler_f(timer, witty_cache_timer_fired);
	dispatch_source_set_cancel_handler_f(timer, witty_cache_timer_cancelled);
	dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, duration), DISPATCH_TIME_FOREVER, 0);
	dispatch_resume(timer);
	return timer;
}
static inline void witty_macos_cancel_timer(void* timer) {
	if (timer) { dispatch_source_cancel((dispatch_source_t)timer); dispatch_release((dispatch_source_t)timer); }
}
#endif
/* Public ICU character-break API exported by the macOS libicucore SDK. */
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef struct UBreakIterator UBreakIterator;
extern UBreakIterator* ubrk_open(int32_t, const char*, const uint16_t*, int32_t, int32_t*);
extern int32_t ubrk_first(UBreakIterator*);
extern int32_t ubrk_next(UBreakIterator*);
extern void ubrk_close(UBreakIterator*);
static inline void witty_macos_copy_characters(void* string, uint16_t* output, unsigned long length) {
	witty_macos_range range = {0, length};
	((void (*)(id, SEL, uint16_t*, witty_macos_range))objc_msgSend)((id)string, sel_registerName("getCharacters:range:"), output, range);
}
#endif
/* Swift [weak self] capture across a main-queue callback. */
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern id objc_initWeak(id*, id);
extern id objc_loadWeakRetained(id*);
extern void objc_destroyWeak(id*);
typedef struct witty_macos_weak_task {
	id object;
	dispatch_function_t callback;
} witty_macos_weak_task;
static void witty_macos_weak_task_run(void* raw) {
	witty_macos_weak_task* task = raw;
	id object = objc_loadWeakRetained(&task->object);
	if (object) {
		task->callback((void*)object);
		((void (*)(id, SEL))objc_msgSend)(object, sel_registerName("release"));
	}
	objc_destroyWeak(&task->object);
	free(task);
}
static inline void witty_macos_dispatch_main_weak(void* object, void* callback) {
	witty_macos_weak_task* task = calloc(1, sizeof(*task));
	if (!task) abort();
	objc_initWeak(&task->object, (id)object);
	task->callback = (dispatch_function_t)callback;
	dispatch_async_f(dispatch_get_main_queue(), task, witty_macos_weak_task_run);
}
#endif
