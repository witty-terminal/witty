#pragma once
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <CoreServices/CoreServices.h>
#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

// ABI adapters; URL and editor selection remain in open_url_darwin.c.v.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_open_url_utf8_string(void* bytes, unsigned long length) {
    id string = ((id (*)(id,SEL))objc_msgSend)((id)objc_getClass("NSString"),sel_registerName("alloc"));
    string = ((id (*)(id,SEL,void*,unsigned long,unsigned long))objc_msgSend)(string,
        sel_registerName("initWithBytes:length:encoding:"),bytes,length,(unsigned long)NSUTF8StringEncoding);
    return ((id (*)(id,SEL))objc_msgSend)(string,sel_registerName("autorelease"));
}
static inline void* witty_open_url_plain_text_type(void) { return (void*)UTTypePlainText; }
static inline void* witty_open_url_decoded_path(void* path) {
    const unsigned char zero=0;
    CFStringRef leaveEscaped=(CFStringRef)witty_open_url_utf8_string((void*)&zero,1);
    CFStringRef decoded=CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL,
        (CFStringRef)path,leaveEscaped,kCFStringEncodingUTF8);
    return ((id (*)(id,SEL))objc_msgSend)((id)decoded,sel_registerName("autorelease"));
}
static inline void* witty_open_url_default_application(void* identifier) {
    return (void*)LSCopyDefaultApplicationURLForContentType((CFStringRef)identifier, kLSRolesAll, NULL);
}
static inline void witty_open_urls_with_application(void* workspace, void* urls, void* application, void* configuration) {
    ((void (*)(id,SEL,id,id,id,id))objc_msgSend)((id)workspace,
        sel_registerName("openURLs:withApplicationAtURL:configuration:completionHandler:"),
        (id)urls,(id)application,(id)configuration,nil);
}
#endif
