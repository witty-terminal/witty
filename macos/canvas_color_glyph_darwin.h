#ifndef WITTY_CANVAS_COLOR_GLYPH_DARWIN_H
#define WITTY_CANVAS_COLOR_GLYPH_DARWIN_H

#include <CoreText/CoreText.h>
#include <ImageIO/ImageIO.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static inline uint16_t witty_sbix_u16(const UInt8 *bytes) {
    uint16_t value;
    memcpy(&value, bytes, sizeof(value));
    return CFSwapInt16BigToHost(value);
}

static inline uint32_t witty_sbix_u32(const UInt8 *bytes) {
    uint32_t value;
    memcpy(&value, bytes, sizeof(value));
    return CFSwapInt32BigToHost(value);
}

static inline const UInt8 *witty_sbix_strike(CFDataRef table, size_t *length, double target) {
    const size_t size = (size_t)CFDataGetLength(table);
    const UInt8 *bytes = CFDataGetBytePtr(table);
    // Version 1 bitmaps without additional vector outlines.
    if (size < 8 || witty_sbix_u16(bytes) != 1 || witty_sbix_u16(bytes + 2) != 1) return NULL;
    const size_t count = witty_sbix_u32(bytes + 4);
    if (count > (size - 8) / 4) return NULL;

    const UInt8 *selected = NULL;
    uint16_t selected_ppem = 0;
    for (size_t i = 0; i < count; i++) {
        const size_t begin = witty_sbix_u32(bytes + 8 + i * 4);
        const size_t end = i + 1 == count ? size : witty_sbix_u32(bytes + 8 + (i + 1) * 4);
        if (begin < 8 + count * 4 || end > size || begin > end || end - begin < 4) return NULL;
        const uint16_t ppem = witty_sbix_u16(bytes + begin);
        const bool have_fit = target > 0 && selected_ppem >= target;
        if (have_fit ? ppem >= target && ppem < selected_ppem : ppem > selected_ppem) {
            selected_ppem = ppem;
            selected = bytes + begin;
            *length = end - begin;
        }
    }
    return selected;
}

static inline CGImageRef witty_sbix_png(const UInt8 *strike, size_t length, size_t count, CGGlyph glyph) {
    if (length < 8 || count > (length - 8) / 4) return NULL;
    const size_t header = 4 + (count + 1) * 4;
    // Each dupe points to another glyph in the same strike. Bound the walk
    // by the number of glyphs so a malformed cycle falls back to Core Text.
    for (size_t i = 0; i < count && glyph < count; i++) {
        const size_t begin = witty_sbix_u32(strike + 4 + glyph * 4);
        const size_t end = witty_sbix_u32(strike + 8 + glyph * 4);
        if (begin < header || end > length || end < begin || end - begin < 8) return NULL;
        const UInt8 *record = strike + begin;
        if (memcmp(record + 4, "dupe", 4) == 0 && end - begin == 10) {
            glyph = witty_sbix_u16(record + 8);
            continue;
        }
        if (memcmp(record + 4, "png ", 4) != 0 || end - begin == 8) return NULL;
        // ImageIO retains the copied PNG bytes while the display list uses
        // the image, independently of the font table's lifetime.
        CFDataRef data = CFDataCreate(NULL, record + 8, (CFIndex)(end - begin - 8));
        if (!data) return NULL;
        CGImageSourceRef source = CGImageSourceCreateWithData(data, NULL);
        CFRelease(data);
        if (!source) return NULL;
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        return image;
    }
    return NULL;
}

typedef struct {
    CGImageRef image;
    CGRect bounds;
} WittyCanvasColorGlyph;

// Present the font's bitmap in AppKit's display list. Some views need the
// smallest strike that covers the backing-pixel dimensions of the glyph.
static inline bool witty_canvas_draw_color_glyph_range(CGContextRef context, CTRunRef run, CTFontRef font,
        CFRange glyph_range, bool fit_to_backing, double x_offset) {
    // Extra transforms change Core Text's subpixel placement in the display list.
    const CGAffineTransform transform = CGContextGetCTM(context);
    if (fabs(transform.a) != 1 || fabs(transform.d) != 1 || transform.b != 0 || transform.c != 0) return false;
    if (!CGAffineTransformIsIdentity(CTRunGetTextMatrix(run))) return false;
    CFDataRef table = CTFontCopyTable(font, kCTFontTableSbix, kCTFontTableOptionNoOptions);
    if (!table) return false;
    size_t default_length = 0;
    const UInt8 *default_strike = fit_to_backing ? NULL : witty_sbix_strike(table, &default_length, 0);
    const CFIndex count = glyph_range.length;
    WittyCanvasColorGlyph *glyphs = count > 0 && (fit_to_backing || default_strike)
        ? calloc((size_t)count, sizeof(*glyphs)) : NULL;
    bool complete = glyphs != NULL;
    if (glyphs) {
        const size_t font_glyphs = (size_t)CTFontGetGlyphCount(font);
        const CGSize backing = CGContextConvertSizeToDeviceSpace(context, CGSizeMake(1, 1));
        const double sx = fabs(backing.width), sy = fabs(backing.height);
        const CGPoint origin = CGContextGetTextPosition(context);
        complete = sx > 0 && sy > 0;
        for (CFIndex i = 0; i < count && complete; i++) {
            const CFRange range = CFRangeMake(glyph_range.location + i, 1);
            const CGRect bounds = CTRunGetImageBounds(run, context, range);
            if (CGRectIsEmpty(bounds)) continue;
            size_t length = default_length;
            const double target = fmax(bounds.size.width * sx, bounds.size.height * sy);
            const UInt8 *strike = fit_to_backing ? witty_sbix_strike(table, &length, target) : default_strike;
            CGGlyph glyph;
            CTRunGetGlyphs(run, range, &glyph);
            glyphs[i].image = strike ? witty_sbix_png(strike, length, font_glyphs, glyph) : NULL;
            complete = glyphs[i].image != NULL;
            // Core Text snaps each glyph relative to the run's text origin.
            glyphs[i].bounds = CGRectMake(origin.x + floor((bounds.origin.x + x_offset - origin.x) * sx + 0.5) / sx,
                origin.y + floor((bounds.origin.y - origin.y) * sy + 0.5) / sy,
                round(bounds.size.width * sx) / sx, round(bounds.size.height * sy) / sy);
        }
        const bool rtl = (CTRunGetStatus(run) & kCTRunStatusRightToLeft) != 0;
        for (CFIndex n = 0; n < count; n++) {
            const CFIndex i = rtl ? count - n - 1 : n;
            if (!glyphs[i].image) continue;
            if (complete) CGContextDrawImage(context, glyphs[i].bounds, glyphs[i].image);
            CGImageRelease(glyphs[i].image);
        }
        free(glyphs);
    }
    CFRelease(table);
    return complete;
}

static inline bool witty_canvas_draw_color_glyphs(CGContextRef context, CTRunRef run, CTFontRef font,
        bool fit_to_backing) {
    return witty_canvas_draw_color_glyph_range(context, run, font, CFRangeMake(0, CTRunGetGlyphCount(run)),
        fit_to_backing, 0);
}

#endif
