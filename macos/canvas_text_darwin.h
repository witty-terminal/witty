#ifndef WITTY_CANVAS_TEXT_DARWIN_H
#define WITTY_CANVAS_TEXT_DARWIN_H

#include "canvas_color_glyph_darwin.h"
#include "canvas_overlay_darwin.h"

typedef struct {
    CGRect bounds;
    CGRect clip;
    CGPoint position;
    double color_baseline_offset;
    bool flipped;
    bool premultiply_translucent_ink;
} WittyCanvasTextLayout;

static inline CTLineRef witty_canvas_text_line(NSString *text, NSDictionary *attributes) {
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    return line;
}

static inline void witty_canvas_draw_text_runs(CGContextRef target, CTLineRef line, NSColor *color,
        WittyCanvasTextLayout layout, uint32_t *pixels, int width, int height) {
    // Shape positions and the raster use Core Text's y-up coordinates.
    CGRect frame = layout.bounds;
    const double flip_axis = CGRectGetMinY(layout.clip) + CGRectGetMaxY(layout.clip);
    if (layout.flipped) frame.origin.y = flip_axis - CGRectGetMaxY(frame);
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, frame);
    if (!context) return;

    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
        CTFontRef font = (CTFontRef)attributes[(id)kCTFontAttributeName];
        const bool color_glyphs = font && (CTFontGetSymbolicTraits(font) & kCTFontColorGlyphsTrait);
        NSColor *tint = attributes[NSForegroundColorAttributeName] ?: color;
        const double x = layout.position.x;
        const double y = layout.position.y + (color_glyphs ? layout.color_baseline_offset : 0);
        if (color_glyphs && CGBitmapContextGetBitsPerComponent(target) == 0) {
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

        const bool rgba = color_glyphs || (layout.premultiply_translucent_ink && CGColorGetAlpha(tint.CGColor) < 1);
        NSColor *paint = rgba ? tint : [tint colorWithAlphaComponent:1];
        CGContextSaveGState(context);
        CGContextClipToRect(context, layout.clip);
        CGContextSetFillColorWithColor(context, paint.CGColor);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, x, y);
        CTRunDraw(run, context, CFRangeMake(0, 0));
        CGContextRestoreGState(context);

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
                CGContextSetFillColorWithColor(target, tint.CGColor);
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
