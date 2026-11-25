#ifndef WITTY_WUFFS_BRIDGE_H
#define WITTY_WUFFS_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

enum witty_wuffs_decoder_kind {
  WITTY_WUFFS_DECODER_PNG = 0,
  WITTY_WUFFS_DECODER_JPEG = 1,
};

enum witty_wuffs_swizzle_kind {
  WITTY_WUFFS_SWIZZLE_G_TO_RGBA = 0,
  WITTY_WUFFS_SWIZZLE_GA_TO_RGBA = 1,
  WITTY_WUFFS_SWIZZLE_RGB_TO_RGBA = 2,
  WITTY_WUFFS_SWIZZLE_BGR_TO_RGBA = 3,
  WITTY_WUFFS_SWIZZLE_BGRA_TO_RGBA = 4,
};

size_t witty_wuffs_decoder_size(int kind);

int witty_wuffs_decode_image_config(
    int kind, void *decoder, size_t decoder_size, const uint8_t *source,
    size_t source_len, uint32_t *width, uint32_t *height,
    size_t *source_read_index, uint64_t *work_buffer_len,
    const char **error_message);

int witty_wuffs_decode_frame(
    int kind, void *decoder, const uint8_t *source, size_t source_len,
    size_t source_read_index, uint32_t width, uint32_t height,
    uint8_t *destination, size_t destination_len, uint8_t *work_buffer,
    size_t work_buffer_len, const char **error_message);

int witty_wuffs_swizzle(int kind, const uint8_t *source, size_t source_len,
                        uint8_t *destination, size_t destination_len,
                        const char **error_message);
void witty_wuffs_rgba_src_over(uint8_t *destination, const uint8_t *source,
                             size_t len);

#endif
