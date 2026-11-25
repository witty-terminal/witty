#include "wuffs_bridge.h"

#define WUFFS_CONFIG__MODULES
#define WUFFS_CONFIG__MODULE__AUX__BASE
#define WUFFS_CONFIG__MODULE__AUX__IMAGE
#define WUFFS_CONFIG__MODULE__BASE
#define WUFFS_CONFIG__MODULE__ADLER32
#define WUFFS_CONFIG__MODULE__CRC32
#define WUFFS_CONFIG__MODULE__DEFLATE
#define WUFFS_CONFIG__MODULE__JPEG
#define WUFFS_CONFIG__MODULE__PNG
#define WUFFS_CONFIG__MODULE__ZLIB
#define WUFFS_IMPLEMENTATION
#include "wuffs-v0.4.c"

static int witty_wuffs_check_status(wuffs_base__status status,
                                    const char **error_message) {
  if (wuffs_base__status__is_ok(&status)) {
    return 1;
  }
  if (error_message) {
    *error_message = wuffs_base__status__message(&status);
  }
  return 0;
}

size_t witty_wuffs_decoder_size(int kind) {
  switch (kind) {
    case WITTY_WUFFS_DECODER_PNG:
      return sizeof__wuffs_png__decoder();
    case WITTY_WUFFS_DECODER_JPEG:
      return sizeof__wuffs_jpeg__decoder();
    default:
      return 0;
  }
}

int witty_wuffs_decode_image_config(
    int kind, void *decoder, size_t decoder_size, const uint8_t *source,
    size_t source_len, uint32_t *width, uint32_t *height,
    size_t *source_read_index, uint64_t *work_buffer_len,
    const char **error_message) {
  wuffs_base__status status;
  wuffs_base__image_config config;
  wuffs_base__io_buffer source_buffer =
      wuffs_base__ptr_u8__reader((uint8_t *)source, source_len, true);

  switch (kind) {
    case WITTY_WUFFS_DECODER_PNG: {
      wuffs_png__decoder *png = (wuffs_png__decoder *)decoder;
      status = wuffs_png__decoder__initialize(png, decoder_size, WUFFS_VERSION,
                                              0);
      if (!witty_wuffs_check_status(status, error_message)) {
        return 0;
      }
      status = wuffs_png__decoder__decode_image_config(png, &config,
                                                       &source_buffer);
      if (!witty_wuffs_check_status(status, error_message)) {
        return 0;
      }
      *work_buffer_len = wuffs_png__decoder__workbuf_len(png).max_incl;
      break;
    }
    case WITTY_WUFFS_DECODER_JPEG: {
      wuffs_jpeg__decoder *jpeg = (wuffs_jpeg__decoder *)decoder;
      status = wuffs_jpeg__decoder__initialize(jpeg, decoder_size,
                                               WUFFS_VERSION, 0);
      if (!witty_wuffs_check_status(status, error_message)) {
        return 0;
      }
      status = wuffs_jpeg__decoder__decode_image_config(jpeg, &config,
                                                        &source_buffer);
      if (!witty_wuffs_check_status(status, error_message)) {
        return 0;
      }
      *work_buffer_len = wuffs_jpeg__decoder__workbuf_len(jpeg).max_incl;
      break;
    }
    default:
      return 0;
  }

  *width = wuffs_base__pixel_config__width(&config.pixcfg);
  *height = wuffs_base__pixel_config__height(&config.pixcfg);
  *source_read_index = source_buffer.meta.ri;
  return 1;
}

int witty_wuffs_decode_frame(
    int kind, void *decoder, const uint8_t *source, size_t source_len,
    size_t source_read_index, uint32_t width, uint32_t height,
    uint8_t *destination, size_t destination_len, uint8_t *work_buffer,
    size_t work_buffer_len, const char **error_message) {
  wuffs_base__io_buffer source_buffer =
      wuffs_base__ptr_u8__reader((uint8_t *)source, source_len, true);
  source_buffer.meta.ri = source_read_index;

  wuffs_base__pixel_config pixel_config = wuffs_base__null_pixel_config();
  wuffs_base__pixel_config__set(
      &pixel_config, WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL,
      WUFFS_BASE__PIXEL_SUBSAMPLING__NONE, width, height);

  wuffs_base__pixel_buffer pixel_buffer;
  wuffs_base__status status = wuffs_base__pixel_buffer__set_from_slice(
      &pixel_buffer, &pixel_config,
      wuffs_base__make_slice_u8(destination, destination_len));
  if (!witty_wuffs_check_status(status, error_message)) {
    return 0;
  }

  wuffs_base__slice_u8 work =
      wuffs_base__make_slice_u8(work_buffer, work_buffer_len);
  switch (kind) {
    case WITTY_WUFFS_DECODER_PNG:
      status = wuffs_png__decoder__decode_frame(
          (wuffs_png__decoder *)decoder, &pixel_buffer, &source_buffer,
          WUFFS_BASE__PIXEL_BLEND__SRC, work, NULL);
      break;
    case WITTY_WUFFS_DECODER_JPEG:
      status = wuffs_jpeg__decoder__decode_frame(
          (wuffs_jpeg__decoder *)decoder, &pixel_buffer, &source_buffer,
          WUFFS_BASE__PIXEL_BLEND__SRC, work, NULL);
      break;
    default:
      return 0;
  }
  return witty_wuffs_check_status(status, error_message);
}

int witty_wuffs_swizzle(int kind, const uint8_t *source, size_t source_len,
                        uint8_t *destination, size_t destination_len,
                        const char **error_message) {
  uint32_t source_format;
  switch (kind) {
    case WITTY_WUFFS_SWIZZLE_G_TO_RGBA:
      source_format = WUFFS_BASE__PIXEL_FORMAT__Y;
      break;
    case WITTY_WUFFS_SWIZZLE_GA_TO_RGBA:
      source_format = WUFFS_BASE__PIXEL_FORMAT__YA_PREMUL;
      break;
    case WITTY_WUFFS_SWIZZLE_RGB_TO_RGBA:
      source_format = WUFFS_BASE__PIXEL_FORMAT__RGB;
      break;
    case WITTY_WUFFS_SWIZZLE_BGR_TO_RGBA:
      source_format = WUFFS_BASE__PIXEL_FORMAT__BGR;
      break;
    case WITTY_WUFFS_SWIZZLE_BGRA_TO_RGBA:
      source_format = WUFFS_BASE__PIXEL_FORMAT__BGRA_PREMUL;
      break;
    default:
      return 0;
  }

  wuffs_base__pixel_swizzler swizzler;
  wuffs_base__status status = wuffs_base__pixel_swizzler__prepare(
      &swizzler,
      wuffs_base__make_pixel_format(WUFFS_BASE__PIXEL_FORMAT__RGBA_PREMUL),
      wuffs_base__empty_slice_u8(),
      wuffs_base__make_pixel_format(source_format),
      wuffs_base__empty_slice_u8(), WUFFS_BASE__PIXEL_BLEND__SRC);
  if (!witty_wuffs_check_status(status, error_message)) {
    return 0;
  }

  wuffs_base__pixel_swizzler__swizzle_interleaved_from_slice(
      &swizzler, wuffs_base__make_slice_u8(destination, destination_len),
      wuffs_base__empty_slice_u8(),
      wuffs_base__make_slice_u8((uint8_t *)source, source_len));
  return 1;
}

void witty_wuffs_rgba_src_over(uint8_t *destination, const uint8_t *source,
                             size_t len) {
  wuffs_base__pixel_swizzler swizzler;
  const wuffs_base__pixel_format rgba =
      wuffs_base__make_pixel_format(WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL);
  wuffs_base__status status = wuffs_base__pixel_swizzler__prepare(
      &swizzler, rgba, wuffs_base__empty_slice_u8(), rgba,
      wuffs_base__empty_slice_u8(), WUFFS_BASE__PIXEL_BLEND__SRC_OVER);
  if (wuffs_base__status__is_ok(&status)) {
    wuffs_base__pixel_swizzler__swizzle_interleaved_from_slice(
        &swizzler, wuffs_base__make_slice_u8(destination, len),
        wuffs_base__empty_slice_u8(),
        wuffs_base__make_slice_u8((uint8_t *)source, len));
  }
}
