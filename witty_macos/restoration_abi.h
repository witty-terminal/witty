// Foundation/Objective-C ABI adapters; serialization logic is translated in V.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_restoration_encode_int(void* coder, long value, void* key) { ((void (*)(id,SEL,long,id))objc_msgSend)((id)coder,sel_registerName("encodeInteger:forKey:"),value,(id)key); }
static inline long witty_restoration_decode_int(void* coder, void* key) { return ((long (*)(id,SEL,id))objc_msgSend)((id)coder,sel_registerName("decodeIntegerForKey:"),(id)key); }
static inline void* witty_restoration_number_bool(bool value) { return ((id (*)(id,SEL,bool))objc_msgSend)((id)objc_getClass("NSNumber"),sel_registerName("numberWithBool:"),value); }
static inline void* witty_restoration_number_int(long value) { return ((id (*)(id,SEL,long))objc_msgSend)((id)objc_getClass("NSNumber"),sel_registerName("numberWithInteger:"),value); }
typedef struct witty_restoration_completion_block { void* isa; int flags; int reserved; void (*invoke)(struct witty_restoration_completion_block*,id,id); } witty_restoration_completion_block;
static inline void witty_restoration_complete(void* completion, void* window, void* error) { witty_restoration_completion_block* block=(witty_restoration_completion_block*)completion; block->invoke(block,(id)window,(id)error); }
#endif
