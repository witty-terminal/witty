// TerminalWindow.title's super setter must start at its defining class,
// including when AppKit installs a subclass for native tabs or observation.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>

static inline void witty_window_font_super_set_title(void* window, void* title) {
    struct objc_super super = {(id)window, class_getSuperclass((Class)objc_getClass("VTTerminalWindow"))};
    ((void (*)(struct objc_super*, SEL, id))objc_msgSendSuper)(&super, sel_registerName("setTitle:"), (id)title);
}

static inline void witty_window_font_fit_title_field(void* object) {
    NSTextField* field = (NSTextField*)object;
    if (!field.superview) return;
    // Reserve the width of the window button group and its padding.
    const NSRect available = NSInsetRect(field.superview.bounds, 52, 0);
    if (NSIsEmptyRect(available)) return;
    NSSize size = [field sizeThatFits:available.size];
    // Leave room for fixed-width fonts to align vertically.
    size.height *= 1.1;
    if (!NSEqualSizes(field.frame.size, size)) [field setFrameSize:size];
}
#endif
