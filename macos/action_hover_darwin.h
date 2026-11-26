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

static inline bool witty_hover_line_has_color(CTLineRef line) {
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
        if (witty_canvas_font_has_color_glyphs((CTFontRef)attributes[(id)kCTFontAttributeName])) return true;
    }
    return false;
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

static inline int witty_hover_corner_phase(NSView *view, bool round_left) {
    NSWindow *window = view.window;
    if (!window) return 0;
    const NSRect bounds = [window convertRectToBacking:[view convertRect:view.bounds toView:nil]];
    const NSRect frame = [window convertRectToBacking:[window convertRectFromScreen:window.frame]];
    const long x = lround(round_left ? CGRectGetMinX(bounds) : CGRectGetMaxX(bounds));
    const long y = lround(CGRectGetMaxY(frame) - CGRectGetMaxY(bounds));
    return (x & 1) | ((y & 1) << 1);
}

static inline void witty_hover_draw_background(CGContextRef target, NSView *view, const CGRect *bounds,
        const CGRect *clip, const uint32_t *pixels, int width, int height) {
    CGImageRef mask = witty_canvas_make_text_mask(pixels, width, height);
    if (!mask) return;
    CGContextSaveGState(target);
    CGContextClipToRect(target, *clip);
    CGContextSetInterpolationQuality(target, kCGInterpolationNone);
    CGContextClipToMask(target, *bounds, mask);
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        CGContextSetFillColorWithColor(target, [NSColor windowBackgroundColor].CGColor);
    }];
    CGContextFillRect(target, *bounds);
    CGContextRestoreGState(target);
    CGImageRelease(mask);
}

static inline void witty_hover_set_background(NSView *view, CALayer *bottom, CALayer *top,
        const CGRect *corner) {
    const CGRect bounds = view.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    bottom.frame = CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width,
        CGRectGetMinY(*corner) - bounds.origin.y);
    const bool left = CGRectGetMinX(*corner) == bounds.origin.x;
    top.frame = CGRectMake(left ? CGRectGetMaxX(*corner) : bounds.origin.x, corner->origin.y,
        bounds.size.width - corner->size.width, corner->size.height);
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        bottom.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        top.backgroundColor = bottom.backgroundColor;
    }];
    [CATransaction commit];
}

static inline void witty_hover_draw_line(CGContextRef target, CTLineRef line, NSView *view,
        const CGRect *bounds, uint32_t *pixels, int width, int height, double padding, double baseline) {
    // Cached mixed-color previews use an sRGB bitmap. Live previews apply label opacity in the compositor.
    const bool mixed_color = witty_hover_line_has_color(line);
    const bool bitmap_target = CGBitmapContextGetBitsPerComponent(target) != 0;
    const WittyCanvasTextLayout layout = {
        .bounds = *bounds,
        .clip = CGRectInset(*bounds, padding, 0),
        .position = CGPointMake(bounds->origin.x + padding, bounds->origin.y + baseline),
        .color_baseline_offset = -0.5,
        .bitmap_color_space = mixed_color && bitmap_target ? kCGColorSpaceSRGB : NULL,
        .ink_rounding = !mixed_color ? WittyCanvasRoundInkUp :
            (bitmap_target ? WittyCanvasRoundInkNearest : WittyCanvasNativeInk),
        .fit_color_glyphs_to_backing = true,
    };
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        witty_canvas_draw_text_runs(target, line, [NSColor labelColor], layout, pixels, width, height);
    }];
}
#endif
