#include "metal_bridge.h"
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline witty_macos_point witty_macos_cascade_top_left(void* window, witty_macos_point point) {
    return ((witty_macos_point (*)(id,SEL,witty_macos_point))objc_msgSend)((id)window,sel_registerName("cascadeTopLeftFromPoint:"),point);
}
static inline void witty_macos_set_frame_origin(void* window, witty_macos_point point) {
    ((void (*)(id,SEL,witty_macos_point))objc_msgSend)((id)window,sel_registerName("setFrameOrigin:"),point);
}
#endif
