#ifndef WITTY_CANVAS_TEXT_DARWIN_H
#define WITTY_CANVAS_TEXT_DARWIN_H

#include "canvas_color_glyph_darwin.h"
#include "canvas_overlay_darwin.h"

typedef enum {
    WittyCanvasNativeInk,
    WittyCanvasRoundInkNearest,
    WittyCanvasRoundInkUp,
} WittyCanvasInkRounding;

typedef struct {
    CGRect bounds;
    CGRect clip;
    CGPoint position;
    double color_baseline_offset;
    CFStringRef bitmap_color_space;
    bool flipped;
    bool premultiply_translucent_ink;
    WittyCanvasInkRounding ink_rounding;
    bool use_bitmap_color_glyphs;
} WittyCanvasTextLayout;

static inline bool witty_canvas_font_has_color_glyphs(CTFontRef font) {
    return font && (CTFontGetSymbolicTraits(font) & kCTFontColorGlyphsTrait);
}

static inline CTLineRef witty_canvas_text_line(NSString *text, NSDictionary *attributes) {
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    return line;
}

static inline void witty_canvas_round_text_coverage(uint32_t *pixels, size_t count, double opacity,
        WittyCanvasInkRounding rounding) {
    const uint32_t tint_alpha = (uint32_t)lround(opacity * 255);
    const uint32_t bias = rounding == WittyCanvasRoundInkUp ? 254 : 127;
    for (size_t i = 0; i < count; ++i) {
        const uint32_t pixel = pixels[i];
        const uint32_t coverage = pixel >> 24;
        if (coverage == 0) continue;
        const uint32_t alpha = (coverage * tint_alpha + bias) / 255;
        const uint32_t r = (((pixel >> 16) & 255) * alpha + coverage / 2) / coverage;
        const uint32_t g = (((pixel >> 8) & 255) * alpha + coverage / 2) / coverage;
        const uint32_t b = ((pixel & 255) * alpha + coverage / 2) / coverage;
        pixels[i] = (alpha << 24) | (r << 16) | (g << 8) | b;
    }
}

static inline void witty_canvas_draw_text_runs(CGContextRef target, CTLineRef line, NSColor *color,
        WittyCanvasTextLayout layout, uint32_t *pixels, int width, int height) {
    // Shape positions and the raster use Core Text's y-up coordinates.
    CGRect frame = layout.bounds;
    const double flip_axis = CGRectGetMinY(layout.clip) + CGRectGetMaxY(layout.clip);
    if (layout.flipped) frame.origin.y = flip_axis - CGRectGetMaxY(frame);
    CGContextRef context = witty_canvas_bitmap_context_in_space(pixels, width, height, frame,
        layout.bitmap_color_space ?: kCGColorSpaceDisplayP3);
    if (!context) return;

    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
        CTFontRef font = (CTFontRef)attributes[(id)kCTFontAttributeName];
        const bool color_glyphs = witty_canvas_font_has_color_glyphs(font);
        NSColor *tint = attributes[NSForegroundColorAttributeName] ?: color;
        const double x = layout.position.x;
        const double y = layout.position.y + (color_glyphs ? layout.color_baseline_offset : 0);
        if (color_glyphs && !layout.use_bitmap_color_glyphs && CGBitmapContextGetBitsPerComponent(target) == 0) {
            CGContextSaveGState(target);
            CGContextClipToRect(target, layout.clip);
            if (layout.flipped) {
                CGContextTranslateCTM(target, 0, flip_axis);
                CGContextScaleCTM(target, 1, -1);
            }
            CGContextSetTextMatrix(target, CGAffineTransformIdentity);
            CGContextSetTextPosition(target, x, y);
            const bool drawn = witty_canvas_draw_color_glyphs(target, run, font);
            CGContextRestoreGState(target);
            if (drawn) continue;
        }

        const double opacity = CGColorGetAlpha(tint.CGColor);
        const bool round_coverage = layout.ink_rounding != WittyCanvasNativeInk && !color_glyphs && opacity < 1;
        const bool rounded_mask = round_coverage && CGBitmapContextGetBitsPerComponent(target) == 0;
        const bool rgba = color_glyphs || (round_coverage && !rounded_mask) ||
            (layout.premultiply_translucent_ink && opacity < 1);
        NSColor *paint = rgba && !round_coverage ? tint : [tint colorWithAlphaComponent:1];
        CGContextSaveGState(context);
        CGContextClipToRect(context, layout.clip);
        CGContextSetFillColorWithColor(context, paint.CGColor);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, x, y);
        CTRunDraw(run, context, CFRangeMake(0, 0));
        CGContextRestoreGState(context);
        if (round_coverage) witty_canvas_round_text_coverage(pixels, (size_t)width * height, opacity,
            layout.ink_rounding);

        CGImageRef image = rgba ? CGBitmapContextCreateImage(context)
            : witty_canvas_make_text_mask(pixels, width, height);
        if (image) {
            if (rgba) {
                witty_canvas_present_oriented_image(target, image, &layout.bounds, layout.flipped);
            } else {
                // Fill through the coverage clip to apply the original tint
                // and alpha directly in the destination.
                CGContextSaveGState(target);
                if (layout.flipped) {
                    CGContextTranslateCTM(target, 0, CGRectGetMinY(layout.bounds) + CGRectGetMaxY(layout.bounds));
                    CGContextScaleCTM(target, 1, -1);
                }
                CGContextSetInterpolationQuality(target, kCGInterpolationNone);
                CGContextClipToMask(target, layout.bounds, image);
                CGContextSetFillColorWithColor(target, (rounded_mask ? paint : tint).CGColor);
                CGContextFillRect(target, layout.bounds);
                CGContextRestoreGState(target);
            }
            CGImageRelease(image);
        }
        CGContextClearRect(context, frame);
    }
    CGContextRelease(context);
}

#endif
