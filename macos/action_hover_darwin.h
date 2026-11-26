#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_text_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline CTLineRef witty_hover_line(NSString *text, double limit, double *width) {
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName: @YES,
    };
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    if (!line) return NULL;
    *width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    if (*width <= limit) return line;

    NSAttributedString *ellipsis = [[NSAttributedString alloc] initWithString:@"…" attributes:attributes];
    CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)ellipsis);
    [ellipsis release];
    CTLineRef truncated = token ? CTLineCreateTruncatedLine(line, limit, kCTLineTruncationMiddle, token) : NULL;
    CFRelease(line);
    if (token) CFRelease(token);
    *width = truncated ? CTLineGetTypographicBounds(truncated, NULL, NULL, NULL) : 0;
    return truncated;
}

static inline bool witty_hover_rasterize_circular_corner(uint32_t *pixels, int width, int height,
        double radius, bool round_left) {
    const CGRect bounds = CGRectMake(0, 0, width, height);
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, bounds);
    if (!context) return false;
    if (round_left) {
        CGContextTranslateCTM(context, width, 0);
        CGContextScaleCTM(context, -1, 1);
    }
    CGContextMoveToPoint(context, 0, 0);
    CGContextAddLineToPoint(context, width, 0);
    CGContextAddLineToPoint(context, width, height - radius);
    CGContextAddArc(context, width - radius, height - radius, radius, 0, M_PI_2, false);
    CGContextAddLineToPoint(context, 0, height);
    CGContextClosePath(context);
    CGContextFillPath(context);
    CGContextRelease(context);
    return true;
}

static inline void witty_hover_draw_background(CGContextRef target, NSView *view, const CGRect *bounds,
        const uint32_t *pixels, int width, int height) {
    CGImageRef mask = witty_canvas_make_text_mask(pixels, width, height);
    if (!mask) return;
    CGContextSaveGState(target);
    CGContextSetInterpolationQuality(target, kCGInterpolationNone);
    CGContextClipToMask(target, *bounds, mask);
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        CGContextSetFillColorWithColor(target, [NSColor windowBackgroundColor].CGColor);
    }];
    CGContextFillRect(target, *bounds);
    CGContextRestoreGState(target);
    CGImageRelease(mask);
}

static inline void witty_hover_draw_line(CGContextRef target, CTLineRef line, NSView *view,
        const CGRect *bounds, uint32_t *pixels, int width, int height, double padding, double baseline) {
    const WittyCanvasTextLayout layout = {
        .bounds = *bounds,
        .clip = CGRectInset(*bounds, padding, 0),
        .position = CGPointMake(bounds->origin.x + padding, bounds->origin.y + baseline),
        .color_baseline_offset = -0.5,
        .round_ink_coverage_up = true,
        .use_bitmap_color_glyphs = true,
    };
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        witty_canvas_draw_text_runs(target, line, [NSColor labelColor], layout, pixels, width, height);
    }];
}
#endif
