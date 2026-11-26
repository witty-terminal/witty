#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_overlay_darwin.h"

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

static inline CGImageRef witty_hover_rasterize_line(CTLineRef line, NSView *view, uint32_t *pixels,
        int width, int height, double padding, double baseline) {
    CGContextRef context = witty_canvas_text_context(pixels, width, height, NSRectToCGRect(view.bounds));
    if (!context) return NULL;
    CGContextClipToRect(context, NSRectToCGRect(NSInsetRect(view.bounds, padding, 0)));
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        CGContextSetFillColorWithColor(context, [NSColor labelColor].CGColor);
    }];
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, padding, baseline);
    CTLineDraw(line, context);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}
#endif
