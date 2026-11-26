#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_overlay_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline NSFont *witty_readonly_font(void) {
    return [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
}

static inline double witty_readonly_title_width(NSString *title) {
    return [title sizeWithAttributes:@{NSFontAttributeName: witty_readonly_font()}].width;
}

static inline CGImageRef witty_readonly_rasterize_title(NSString *title, NSColor *tint,
        const CGRect *bounds, uint32_t *pixels, int width, int height) {
    NSDictionary *attributes = @{NSFontAttributeName: witty_readonly_font(), NSForegroundColorAttributeName: tint};
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:title attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    [text release];
    if (!line) return NULL;
    CGContextRef context = witty_canvas_text_context(pixels, width, height, *bounds);
    if (!context) {
        CFRelease(line);
        return NULL;
    }
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, 31, (bounds->size.height - 15) / 2 + 3);
    // Core Text adjusts glyph coverage for the actual text color.
    CTLineDraw(line, context);
    CGContextRelease(context);
    CFRelease(line);
    return witty_canvas_make_text_mask(pixels, width, height);
}
#endif
