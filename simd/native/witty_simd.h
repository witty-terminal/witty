#ifndef WITTY_GHOSTTY_SIMD_H
#define WITTY_GHOSTTY_SIMD_H
#include <stdint.h>
#include <stddef.h>
// ABI declarations from Ghostty src/simd/*.zig, matching the reused C++.
size_t ghostty_simd_base64_max_length(const unsigned char *, size_t);
size_t ghostty_simd_base64_decode(const unsigned char *, size_t, unsigned char *);
size_t ghostty_simd_index_of(uint8_t, const unsigned char *, size_t);
int8_t ghostty_simd_codepoint_width(uint32_t);
size_t ghostty_simd_decode_utf8_until_control_seq(const unsigned char *, size_t,
                                               uint32_t *, size_t *);
#endif
