#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline NSFont *witty_readonly_font(void) {
    return [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
}

static inline double witty_readonly_title_width(NSString *title) {
    return [title sizeWithAttributes:@{NSFontAttributeName: witty_readonly_font()}].width;
}

static inline void witty_readonly_draw_title(CGContextRef context, NSString *title, double height, NSColor *tint) {
    NSDictionary *attributes = @{NSFontAttributeName: witty_readonly_font(), NSForegroundColorAttributeName: tint};
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:title attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    [text release];
    if (!line) return;
    CGContextSaveGState(context);
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, 31, (height - 15) / 2 + 3);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
}
#endif
