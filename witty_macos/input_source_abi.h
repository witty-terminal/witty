#ifndef WITTY_MACOS_INPUT_SOURCE_ABI_H
#define WITTY_MACOS_INPUT_SOURCE_ABI_H
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <Carbon/Carbon.h>
/* kTISPropertyInputSourceID is a CFStringRef global, so V reads it through this adapter. */
static inline void* witty_macos_input_source_id(void* source) {
	return (void*)TISGetInputSourceProperty((TISInputSourceRef)source, kTISPropertyInputSourceID);
}
#endif
#endif
