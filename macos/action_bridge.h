#include <stdbool.h>
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <objc/runtime.h>
#include <objc/message.h>
#include <CoreGraphics/CoreGraphics.h>
#endif
/* Objective-C ABI adapters only; translated action logic lives in V. */
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_action_timer(double interval, void* target, void* selector, void* info, bool repeats) {
 return ((id(*)(id,SEL,double,id,SEL,id,bool))objc_msgSend)((id)objc_getClass("NSTimer"),sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),interval,(id)target,(SEL)selector,(id)info,repeats);
}
static inline void* witty_action_hit_super(void* view, void* defining_class, double x, double y) {
 struct objc_super sup = {(id)view,class_getSuperclass((Class)defining_class)};
 return ((id(*)(struct objc_super*,SEL,CGPoint))objc_msgSendSuper)(&sup,sel_registerName("hitTest:"),(CGPoint){x,y});
}
static inline void witty_action_add_tab(void* window, void* other, long order) {
 ((void(*)(id,SEL,id,long))objc_msgSend)((id)window,sel_registerName("addTabbedWindow:ordered:"),(id)other,order);
}
static inline void witty_macos_set_document_cursor(void* view, void* cursor) {
 ((void(*)(id,SEL,CGRect,id))objc_msgSend)((id)view,sel_registerName("addCursorRect:cursor:"),((CGRect(*)(id,SEL))objc_msgSend)((id)view,sel_registerName("bounds")),(id)cursor);
}
static inline void witty_action_show_popover(void* popover, void* view, unsigned long edge) {
 ((void(*)(id,SEL,CGRect,id,unsigned long))objc_msgSend)((id)popover,sel_registerName("showRelativeToRect:ofView:preferredEdge:"),((CGRect(*)(id,SEL))objc_msgSend)((id)view,sel_registerName("bounds")),(id)view,edge);
}
static inline void witty_action_repeat_forever(void* animation) {
 ((void(*)(id,SEL,float))objc_msgSend)((id)animation,sel_registerName("setRepeatCount:"),__builtin_inff());
}
static inline long long witty_action_compare(void* a, void* b) {
 return ((long long(*)(id,SEL,id))objc_msgSend)((id)a,sel_registerName("localizedCaseInsensitiveCompare:"),(id)b);
}
static inline void witty_action_scroll_rect(void* view,double x,double y,double width,double height) {
 ((void(*)(id,SEL,CGRect))objc_msgSend)((id)view,sel_registerName("scrollRectToVisible:"),(CGRect){{x,y},{width,height}});
}
#endif

typedef struct witty_action_insets { double top,left,bottom,right; } witty_action_insets;
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef struct witty_action_os_version { long major,minor,patch; } witty_action_os_version;
static inline witty_action_os_version witty_action_os_current(void) {
 id info = ((id(*)(id,SEL))objc_msgSend)((id)objc_getClass("NSProcessInfo"),sel_registerName("processInfo"));
 return ((witty_action_os_version(*)(id,SEL))objc_msgSend)(info,sel_registerName("operatingSystemVersion"));
}
static inline long witty_action_os_major(void) { return witty_action_os_current().major; }
static inline long witty_action_os_minor(void) { return witty_action_os_current().minor; }
static inline double witty_action_content_height(void* scroll) { return ((CGSize(*)(id,SEL))objc_msgSend)((id)scroll,sel_registerName("contentSize")).height; }
static inline double witty_action_content_width(void* scroll) { return ((CGSize(*)(id,SEL))objc_msgSend)((id)scroll,sel_registerName("contentSize")).width; }
static inline void witty_action_scroll_point(void* clip,double y) { ((void(*)(id,SEL,CGPoint))objc_msgSend)((id)clip,sel_registerName("scrollToPoint:"),(CGPoint){0,y}); }
#endif

typedef struct witty_action_inspector_size { double width,height; } witty_action_inspector_size;
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_action_inspector_new(void* cls,void* device,double width,double height) {
 id obj = ((id(*)(id,SEL))objc_msgSend)((id)cls,sel_registerName("alloc"));
 return ((id(*)(id,SEL,CGRect,id))objc_msgSend)(obj,sel_registerName("initWithFrame:device:"),(CGRect){{0,0},{width,height}},(id)device);
}
static inline witty_action_inspector_size witty_action_to_backing(void* view,double width,double height) {
 CGRect rect=((CGRect(*)(id,SEL,CGRect))objc_msgSend)((id)view,sel_registerName("convertRectToBacking:"),(CGRect){{0,0},{width,height}}); return (witty_action_inspector_size){rect.size.width,rect.size.height};
}
static inline void* witty_action_rounded_path(double width,double height,double radius) { return CGPathCreateWithRoundedRect((CGRect){{0,0},{width,height}},radius,radius,NULL); }
static inline void witty_action_path_release(void* path) { CGPathRelease((CGPathRef)path); }
static inline void witty_action_layer_anchor(void* layer,double x,double y) { ((void(*)(id,SEL,CGPoint))objc_msgSend)((id)layer,sel_registerName("setAnchorPoint:"),(CGPoint){x,y}); }
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_action_id_f64_f64(void* obj,void* selector,double a,double b) { return ((id(*)(id,SEL,double,double))objc_msgSend)((id)obj,(SEL)selector,a,b); }
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_action_shadow_offset(void* obj,double x,double y) { ((void(*)(id,SEL,CGSize))objc_msgSend)((id)obj,sel_registerName("setShadowOffset:"),(CGSize){x,y}); }
#endif
