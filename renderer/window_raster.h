#ifndef WITTY_WINDOW_RASTER_H
#define WITTY_WINDOW_RASTER_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef float witty_raster_color __attribute__((ext_vector_type(4)));

typedef struct {
    uint32_t pos[2], size[2];
    int16_t bearings[2];
    uint16_t cell[2];
    uint8_t rgba[4];
    uint8_t atlas, flags;
} witty_raster_glyph;

typedef struct {
    uint32_t count;
    float color[4], bounds[4], outline[68][2];
} witty_raster_overlay;

typedef struct {
    uint32_t *pixels;
    const uint8_t (*bg_cells)[4];
    const uint8_t *grayscale, *color;
    size_t bg_count, stride;
    int width, height;
    int cell_width, cell_height;
    int columns, rows;
    int glyph_x, glyph_y;
    int background_x, background_y;
    uint32_t grayscale_size, color_size;
    uint32_t padding_extend;
    float minimum_contrast;
    uint16_t cursor_col, cursor_row;
    uint8_t background[4], cursor[4];
    bool display_p3, cursor_wide;
} witty_raster_frame;

_Static_assert(sizeof(witty_raster_glyph) == 32, "terminal glyph record size");
_Static_assert(sizeof(witty_raster_overlay) == 580, "terminal overlay record size");

static inline float witty_raster_linear(float value) {
    return value <= 0.04045f ? value / 12.92f : powf((value + 0.055f) / 1.055f, 2.4f);
}

static inline float witty_raster_gamma(float value) {
    return value <= 0.0031308f ? value * 12.92f : powf(value, 1.0f / 2.4f) * 1.055f - 0.055f;
}

// Match the color conversion and premultiplied blending in shaders.metal.
static inline witty_raster_color witty_raster_load(const uint8_t rgba[4], bool display_p3, bool linear) {
    const float unit = 1.0f / 255.0f;
    float r = rgba[0] * unit, g = rgba[1] * unit, b = rgba[2] * unit, a = rgba[3] * unit;
    if (linear || !display_p3) {
        r = witty_raster_linear(r);
        g = witty_raster_linear(g);
        b = witty_raster_linear(b);
        if (!display_p3) {
            // D50-adapted sRGB to XYZ followed by XYZ to Display P3.
            const float x = 0.4360747f*r + 0.3850649f*g + 0.1430804f*b;
            const float y = 0.2225045f*r + 0.7168786f*g + 0.0606169f*b;
            const float z = 0.0139322f*r + 0.0971045f*g + 0.7141733f*b;
            r = 2.40414768f*x - 0.99010704f*y - 0.39759019f*z;
            g = -0.84239098f*x + 1.79905954f*y + 0.01597023f*z;
            b = 0.04838763f*x - 0.09752546f*y + 1.27393636f*z;
        }
        if (!linear) {
            r = witty_raster_gamma(r);
            g = witty_raster_gamma(g);
            b = witty_raster_gamma(b);
        }
    }
    return (witty_raster_color){r*a, g*a, b*a, a};
}

static inline uint32_t witty_raster_channel(float value) {
    if (value <= 0) return 0;
    if (value >= 1) return 255;
    return (uint32_t)nearbyintf(value * 255.0f);
}

static inline uint32_t witty_raster_bgra(witty_raster_color color) {
    return (witty_raster_channel(color[3]) << 24) | (witty_raster_channel(color[0]) << 16)
         | (witty_raster_channel(color[1]) << 8) | witty_raster_channel(color[2]);
}

static inline uint32_t witty_raster_blend(uint32_t pixel, witty_raster_color color) {
    const float unit = 1.0f / 255.0f;
    witty_raster_color old = {(pixel >> 16) & 255, (pixel >> 8) & 255, pixel & 255, pixel >> 24};
    return witty_raster_bgra(color + (1.0f - color[3]) * (old * unit));
}

static inline void witty_raster_fill(const witty_raster_frame *frame, uint32_t pixel,
    int left, int top, int right, int bottom) {
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right > frame->width) right = frame->width;
    if (bottom > frame->height) bottom = frame->height;
    if (left >= right || top >= bottom) return;
    for (int y = top; y < bottom; ++y) {
        uint32_t *row = frame->pixels + (size_t)y * frame->stride;
        for (int x = left; x < right; ++x) row[x] = pixel;
    }
}

static inline void witty_window_raster_background(const witty_raster_frame *frame) {
    const uint32_t bg = witty_raster_bgra(witty_raster_load(frame->background, frame->display_p3, false));
    if ((size_t)frame->width == frame->stride) {
        memset_pattern4(frame->pixels, &bg, frame->stride * frame->height * sizeof(bg));
    } else {
        for (int y = 0; y < frame->height; ++y) {
            memset_pattern4(frame->pixels + (size_t)y * frame->stride, &bg, (size_t)frame->width * sizeof(bg));
        }
    }
    if ((size_t)frame->columns * frame->rows != frame->bg_count) return;
    for (int y = 0; y < frame->rows; ++y) {
        const int cell_top = frame->background_y + y * frame->cell_height;
        const int top = y == 0 && (frame->padding_extend & 4) ? 0 : cell_top;
        const int bottom = y == frame->rows - 1 && (frame->padding_extend & 8)
            ? frame->height : cell_top + frame->cell_height;
        for (int x = 0; x < frame->columns; ++x) {
            const uint8_t *rgba = frame->bg_cells[(size_t)y * frame->columns + x];
            if (rgba[3] == 0) continue;
            const uint32_t color = witty_raster_blend(bg, witty_raster_load(rgba, frame->display_p3, false));
            if (color == bg) continue;
            const int cell_left = frame->background_x + x * frame->cell_width;
            const int left = x == 0 && (frame->padding_extend & 1) ? 0 : cell_left;
            const int right = x == frame->columns - 1 && (frame->padding_extend & 2)
                ? frame->width : cell_left + frame->cell_width;
            witty_raster_fill(frame, color, left, top, right, bottom);
        }
    }
}

static inline float witty_raster_luminance(witty_raster_color color) {
    return color[0] * 0.2126f + color[1] * 0.7152f + color[2] * 0.0722f;
}

static inline witty_raster_color witty_raster_glyph_color(const witty_raster_frame *frame,
    const witty_raster_glyph *glyph) {
    const bool at_cursor = glyph->cell[1] == frame->cursor_row &&
        (glyph->cell[0] == frame->cursor_col || (frame->cursor_wide && glyph->cell[0] == frame->cursor_col + 1));
    if (at_cursor && !(glyph->flags & 2)) return witty_raster_load(frame->cursor, frame->display_p3, false);

    if (frame->minimum_contrast > 1.0f && !(glyph->flags & 1)) {
        const witty_raster_color fg = witty_raster_load(glyph->rgba, frame->display_p3, true);
        witty_raster_color bg = witty_raster_load(frame->background, frame->display_p3, true);
        const size_t index = (size_t)glyph->cell[1] * frame->columns + glyph->cell[0];
        if (index < frame->bg_count) {
            const witty_raster_color cell = witty_raster_load(frame->bg_cells[index], frame->display_p3, true);
            bg = cell + bg * (1.0f - cell[3]);
        }
        const float light_fg = witty_raster_luminance(fg) + 0.05f;
        const float light_bg = witty_raster_luminance(bg) + 0.05f;
        const float ratio = fmaxf(light_fg, light_bg) / fminf(light_fg, light_bg);
        if (ratio < frame->minimum_contrast) {
            const float contrast = 1.05f / light_bg > light_bg / 0.05f ? 1.0f : 0.0f;
            return (witty_raster_color){contrast, contrast, contrast, 1.0f};
        }
    }
    return witty_raster_load(glyph->rgba, frame->display_p3, false);
}

// Apple GPU sRGB texture samples use a 12-bit linear value.
static inline float witty_raster_atlas_linear(uint8_t sample) {
    return nearbyintf(witty_raster_linear(sample * (1.0f / 255.0f)) * 4095.0f) * (1.0f / 4095.0f);
}

static inline witty_raster_color witty_raster_emoji(const uint8_t bgra[4]) {
    const float unit = 1.0f / 255.0f;
    const float alpha = bgra[3] * unit;
    return (witty_raster_color){
        witty_raster_gamma(witty_raster_atlas_linear(bgra[2]) / alpha) * alpha,
        witty_raster_gamma(witty_raster_atlas_linear(bgra[1]) / alpha) * alpha,
        witty_raster_gamma(witty_raster_atlas_linear(bgra[0]) / alpha) * alpha,
        alpha
    };
}

static inline void witty_window_raster_glyphs(const witty_raster_frame *frame,
    const void *data, size_t count) {
    const uint8_t *records = data;
    for (size_t i = 0; i < count; ++i) {
        witty_raster_glyph record;
        memcpy(&record, records + i * sizeof(record), sizeof(record));
        const witty_raster_glyph *glyph = &record;
        const bool emoji = glyph->atlas == 1;
        const uint32_t size = emoji ? frame->color_size : frame->grayscale_size;
        if (!glyph->size[0] || !glyph->size[1] || glyph->pos[0] >= size || glyph->pos[1] >= size ||
            glyph->size[0] > size - glyph->pos[0] || glyph->size[1] > size - glyph->pos[1]) continue;

        const int x0 = frame->glyph_x + glyph->cell[0] * frame->cell_width + glyph->bearings[0];
        const int y0 = frame->glyph_y + (glyph->cell[1] + 1) * frame->cell_height - glyph->bearings[1];
        const int x1 = x0 + (int)glyph->size[0], y1 = y0 + (int)glyph->size[1];
        const int left = x0 < 0 ? 0 : x0, top = y0 < 0 ? 0 : y0;
        const int right = x1 > frame->width ? frame->width : x1;
        const int bottom = y1 > frame->height ? frame->height : y1;
        if (left >= right || top >= bottom) continue;

        const witty_raster_color color = emoji ? (witty_raster_color){0}
            : witty_raster_glyph_color(frame, glyph);
        if (!emoji && color[3] == 0) continue;
        for (int y = top; y < bottom; ++y) {
            uint32_t *row = frame->pixels + (size_t)y * frame->stride;
            const size_t source = (glyph->pos[1] + (size_t)(y - y0)) * size + glyph->pos[0] + (size_t)(left - x0);
            if (emoji) {
                const uint8_t *pixel = frame->color + 4 * source;
                for (int x = left; x < right; ++x, pixel += 4) {
                    if (pixel[3]) row[x] = witty_raster_blend(row[x], witty_raster_emoji(pixel));
                }
            } else {
                const uint8_t *mask = frame->grayscale + source;
                for (int x = left; x < right; ++x, ++mask) {
                    if (*mask) row[x] = witty_raster_blend(row[x], color * (*mask * (1.0f / 255.0f)));
                }
            }
        }
    }
}

static inline void witty_window_raster_overlay(const witty_raster_frame *frame, const void *data) {
    witty_raster_overlay outline;
    memcpy(&outline, data, sizeof(outline));
    const witty_raster_overlay *overlay = &outline;
    if (overlay->count < 3 || overlay->count > sizeof(overlay->outline) / sizeof(*overlay->outline)) return;
    const uint32_t color = witty_raster_bgra((witty_raster_color){
        overlay->color[0], overlay->color[1], overlay->color[2], overlay->color[3]});
    const int left = (int)fmaxf(0, ceilf(overlay->bounds[0] - 0.5f));
    const int top = (int)fmaxf(0, ceilf(overlay->bounds[1] - 0.5f));
    const int right = (int)fminf(frame->width, ceilf(overlay->bounds[2] - 0.5f));
    const int bottom = (int)fminf(frame->height, ceilf(overlay->bounds[3] - 0.5f));
    for (int y = top; y < bottom; ++y) {
        uint32_t *row = frame->pixels + (size_t)y * frame->stride;
        for (int x = left; x < right; ++x) {
            bool inside = true;
            const float *start = overlay->outline[overlay->count - 1];
            for (size_t i = 0; i < overlay->count; ++i) {
                const float *end = overlay->outline[i];
                if ((end[0]-start[0]) * (y+0.5f-start[1]) < (end[1]-start[1]) * (x+0.5f-start[0])) {
                    inside = false;
                    break;
                }
                start = end;
            }
            if (inside) row[x] = color;
        }
    }
}

static inline void *witty_window_raster_allocate(void *old, size_t size) {
    return realloc(old, size);
}

static inline void witty_window_raster_free(void *pixels) {
    free(pixels);
}

#endif
#endif
