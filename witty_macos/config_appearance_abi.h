#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_macos_observe_application_appearance(void* observer) {
    [NSApp addObserver:(id)observer forKeyPath:@"effectiveAppearance"
               options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
               context:NULL];
}
static inline void witty_macos_remove_application_appearance_observer(void* observer) {
    [NSApp removeObserver:(id)observer forKeyPath:@"effectiveAppearance"];
}
#endif
