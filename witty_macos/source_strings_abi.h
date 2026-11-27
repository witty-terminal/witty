#ifndef WITTY_MACOS_SOURCE_STRINGS_ABI_H
#define WITTY_MACOS_SOURCE_STRINGS_ABI_H
#pragma push_macro("UChar")
#undef UChar
#include <unicode/ustring.h>
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
typedef UChar witty_source_icu_char;
#endif
#pragma pop_macro("UChar")

// Native ICU performs Unicode's malformed UTF-8 substitution. No decoder is
// implemented here. A -1 source length gives Swift String(cString:)'s boundary.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void* witty_source_c_utf8_repair(const char* source) {
    UErrorCode error=U_ZERO_ERROR;
    int32_t length=0;
    u_strFromUTF8WithSub(NULL,0,&length,source,-1,0xfffd,NULL,&error);
    if(error!=U_BUFFER_OVERFLOW_ERROR && U_FAILURE(error)) abort();
    witty_source_icu_char* characters=malloc(((size_t)length+1)*sizeof(witty_source_icu_char));
    if(!characters) abort();
    error=U_ZERO_ERROR;
    u_strFromUTF8WithSub(characters,length+1,&length,source,-1,0xfffd,NULL,&error);
    if(U_FAILURE(error)) { free(characters); abort(); }
    id string=((id (*)(id,SEL))objc_msgSend)((id)objc_getClass("NSString"),sel_registerName("alloc"));
    string=((id (*)(id,SEL,const witty_source_icu_char*,unsigned long))objc_msgSend)(string,
        sel_registerName("initWithCharacters:length:"),characters,(unsigned long)length);
    free(characters);
    return ((id (*)(id,SEL))objc_msgSend)(string,sel_registerName("autorelease"));
}
#endif
#endif
