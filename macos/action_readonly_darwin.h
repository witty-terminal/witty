#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline NSFont *witty_readonly_font(void) {
    return [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
}

static inline double witty_readonly_title_width(NSString *title) {
    return [title sizeWithAttributes:@{NSFontAttributeName: witty_readonly_font()}].width;
}

static inline void witty_readonly_set_mask(NSVisualEffectView *view, CGImageRef mask, double width, double height) {
    NSImage *image = [[NSImage alloc] initWithCGImage:mask size:NSMakeSize(width, height)];
    view.maskImage = image;
    [image release];
}

static inline void witty_readonly_draw_content(CGContextRef context, NSString *title, double height) {
    NSColor *tint = [NSColor colorWithSRGBRed:0.8 green:0.592 blue:0.4 alpha:1];
    NSImageSymbolConfiguration *font = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
    NSImageSymbolConfiguration *color = [NSImageSymbolConfiguration configurationWithPaletteColors:@[tint]];
    NSImage *eye = [NSImage imageWithSystemSymbolName:@"eye.fill" accessibilityDescription:nil];
    eye = [eye imageWithSymbolConfiguration:[font configurationByApplyingConfiguration:color]];
    [eye drawInRect:NSMakeRect(8, (height - 12) / 2, 18, 12)];

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
