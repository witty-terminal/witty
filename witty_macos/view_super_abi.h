#ifndef WITTY_MACOS_VIEW_SUPER_ABI_H
#define WITTY_MACOS_VIEW_SUPER_ABI_H
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <objc/message.h>
#include <objc/runtime.h>
#endif

// Swift super starts at the superclass of the class defining the override.
// The receiver can belong to a further subclass, including a KVO subclass.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline bool witty_macos_view_super_bool0(void* view, void* defining_class, void* selector) {
    if (!view || !defining_class) return false;
    struct objc_super parent = {(id)view, class_getSuperclass((Class)defining_class)};
    return ((bool (*)(struct objc_super*, SEL))objc_msgSendSuper)(&parent, (SEL)selector);
}
static inline void witty_macos_view_super_void0(void* view, void* defining_class, void* selector) {
    if (!view || !defining_class) return;
    struct objc_super parent = {(id)view, class_getSuperclass((Class)defining_class)};
    ((void (*)(struct objc_super*, SEL))objc_msgSendSuper)(&parent, (SEL)selector);
}
static inline void witty_macos_view_super_void1(void* view, void* defining_class, void* selector, void* argument) {
    if (!view || !defining_class) return;
    struct objc_super parent = {(id)view, class_getSuperclass((Class)defining_class)};
    ((void (*)(struct objc_super*, SEL, id))objc_msgSendSuper)(&parent, (SEL)selector, (id)argument);
}
#endif
#endif
