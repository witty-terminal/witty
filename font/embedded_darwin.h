#ifndef WITTY_EMBEDDED_DARWIN_H
#define WITTY_EMBEDDED_DARWIN_H

#include <mach-o/getsect.h>
#include <mach-o/ldsyms.h>
#include <stdint.h>

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline unsigned char *witty_mapped_font_bytes(const char *section, uint64_t *len) {
	unsigned long size = 0;
	unsigned char *bytes = getsectiondata(&_mh_execute_header, "__TEXT", section, &size);
	*len = size;
	return bytes;
}
#endif

#endif
