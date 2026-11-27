#ifndef WITTY_MACOS_STRING_ABI_H
#define WITTY_MACOS_STRING_ABI_H
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <Foundation/Foundation.h>
#include <objc/message.h>
#include <objc/runtime.h>
#endif

// NSString bridges must preserve the complete V/Swift String byte slice.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_macos_nsstring(const char* bytes, unsigned long length) {
    id value = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSString"), sel_registerName("alloc"));
    value = ((id (*)(id, SEL, const char*, unsigned long, unsigned long))objc_msgSend)(value,
        sel_registerName("initWithBytes:length:encoding:"), bytes, length, (unsigned long)NSUTF8StringEncoding);
    return ((id (*)(id, SEL))objc_msgSend)(value, sel_registerName("autorelease"));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline unsigned long witty_macos_utf8_length(void* value) {
    return ((unsigned long (*)(id, SEL, unsigned long))objc_msgSend)((id)value,
        sel_registerName("lengthOfBytesUsingEncoding:"), (unsigned long)NSUTF8StringEncoding);
}
#endif
#endif
