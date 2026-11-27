// ABI adapters only. Fullscreen behavior is translated in fullscreen_darwin.c.v.
typedef struct witty_macos_edge_insets { double top, left, bottom, right; } witty_macos_edge_insets;
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline witty_macos_edge_insets witty_macos_screen_insets(void* screen) {
    return ((witty_macos_edge_insets (*)(id, SEL))objc_msgSend)((id)screen, sel_registerName("safeAreaInsets"));
}
static inline macos_rect witty_fullscreen_msg_rect_rect(void* obj, void* selector, macos_rect value) {
    return ((macos_rect (*)(id, SEL, macos_rect))objc_msgSend)((id)obj, (SEL)selector, value);
}
static inline void witty_macos_msg_void_rect_bool(void* obj, void* selector, macos_rect value, bool display) {
    ((void (*)(id, SEL, macos_rect, bool))objc_msgSend)((id)obj, (SEL)selector, value, display);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_objc_msg_void3(void* obj, void* selector, void* a, void* b, void* c) { ((void (*)(id, SEL, id, id, id))objc_msgSend)((id)obj, (SEL)selector, (id)a, (id)b, (id)c); }
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern int CGSMainConnectionID(void);
extern size_t CGSGetActiveSpace(int);
extern unsigned int CGSSpaceGetType(int, size_t);
extern void* CGSCopySpacesForWindows(int, unsigned int, void*);
#endif
