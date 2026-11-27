#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/NSTextField.h>

static inline unsigned long long witty_macos_text_alignment_center(void) { return NSTextAlignmentCenter; }

static inline void* witty_macos_color_rgba(double r, double g, double b, double a) {
    return ((id (*)(id,SEL,double,double,double,double))objc_msgSend)((id)objc_getClass("NSColor"),sel_registerName("colorWithSRGBRed:green:blue:alpha:"),r,g,b,a);
}
static inline void witty_macos_color_components(void* color, double* r, double* g, double* b, double* a) {
    ((void (*)(id,SEL,double*,double*,double*,double*))objc_msgSend)((id)color,sel_registerName("getRed:green:blue:alpha:"),r,g,b,a);
}
static inline void* witty_macos_msg_id_obj_f64(void* obj, void* selector, void* value, double amount) { return ((id (*)(id,SEL,id,double))objc_msgSend)((id)obj,(SEL)selector,(id)value,amount); }
static inline void witty_macos_msg_super_void_u64(void* obj, void* selector, unsigned long long value) {
    struct objc_super super = {(id)obj,class_getSuperclass((Class)objc_getClass("VTTerminalWindow"))};
    ((void (*)(struct objc_super*,SEL,unsigned long long))objc_msgSendSuper)(&super,(SEL)selector,value);
}
static inline void witty_macos_window_super_void0(void* obj, void* selector) { struct objc_super super={(id)obj,class_getSuperclass((Class)objc_getClass("VTTerminalWindow"))}; ((void (*)(struct objc_super*,SEL))objc_msgSendSuper)(&super,(SEL)selector); }
static inline void witty_macos_window_super_void1(void* obj, void* selector, void* value) { struct objc_super super={(id)obj,class_getSuperclass((Class)objc_getClass("VTTerminalWindow"))}; ((void (*)(struct objc_super*,SEL,id))objc_msgSendSuper)(&super,(SEL)selector,(id)value); }
static inline void* witty_macos_array(void** objects, size_t count) { return ((id (*)(id,SEL,const id*,size_t))objc_msgSend)((id)objc_getClass("NSArray"),sel_registerName("arrayWithObjects:count:"),(const id*)objects,count); }
static inline witty_macos_size witty_macos_text_size(void* obj) { return ((witty_macos_size (*)(id, SEL))objc_msgSend)((id)obj,sel_registerName("size")); }
static inline void witty_macos_priority(void* obj, void* selector, float priority, unsigned long long axis) { ((void (*)(id,SEL,float,unsigned long long))objc_msgSend)((id)obj,(SEL)selector,priority,axis); }
static inline void witty_macos_msg_void_f32(void* obj, void* selector, float value) { ((void (*)(id,SEL,float))objc_msgSend)((id)obj,(SEL)selector,value); }
#endif
