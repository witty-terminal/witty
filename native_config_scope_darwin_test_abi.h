#include <AppKit/AppKit.h>
#include <math.h>
#include <objc/runtime.h>
#include <stdint.h>

static BOOL witty_config_scope_key;
static BOOL witty_config_scope_is_key(id self, SEL command) {
    return witty_config_scope_key;
}
static inline void* witty_config_scope_controlled_key_window(void* view) {
    NSWindow* window = [(NSView*)view window];
    Class original = object_getClass(window);
    Class probe = objc_getClass("VTConfigScopeProbeWindow");
    if (!probe) {
        probe = objc_allocateClassPair(original, "VTConfigScopeProbeWindow", 0);
        class_addMethod(probe, @selector(isKeyWindow),
                        (IMP)witty_config_scope_is_key, "B@:");
        objc_registerClassPair(probe);
    }
    object_setClass(window, probe);
    return original;
}
static inline void witty_config_scope_restore_class(void* view, void* original) {
    object_setClass([(NSView*)view window], (Class)original);
}
static inline void witty_config_scope_set_key(bool key) {
    witty_config_scope_key = key;
}
static inline void witty_config_scope_drain_main(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
static inline void witty_config_scope_finish_launching(void) {
    [NSApp finishLaunching];
}
static inline bool witty_config_scope_opaque(void* view) {
    return [[(NSView*)view window] isOpaque];
}
static inline uint32_t witty_config_scope_background(void* view) {
    NSColor* color = [[[(NSView*)view window] backgroundColor]
        colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return ((uint32_t)lround(color.redComponent * 255) << 16)
        | ((uint32_t)lround(color.greenComponent * 255) << 8)
        | (uint32_t)lround(color.blueComponent * 255);
}
static inline bool witty_config_scope_scroller(void* view) {
    return [[(NSView*)view enclosingScrollView] hasVerticalScroller];
}
static inline void witty_config_scope_clear_responder(void* view) {
    [[(NSView*)view window] makeFirstResponder:nil];
}
static inline bool witty_config_scope_is_responder(void* view) {
    return [[(NSView*)view window] firstResponder] == (id)view;
}
