#ifndef WITTY_ACTION_PALETTE_ROW_DARWIN_H
#define WITTY_ACTION_PALETTE_ROW_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>

static inline void witty_palette_draw_swatch(CGContextRef context, const CGRect *rect, CGImageRef mask,
        NSColor *color) {
    CGContextSaveGState(context);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextClipToMask(context, *rect, mask);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, *rect);
    CGContextRestoreGState(context);
}

static inline NSFont *witty_palette_row_font(double size, bool medium) {
    return [NSFont systemFontOfSize:size weight:(medium ? NSFontWeightMedium : NSFontWeightRegular)];
}

static inline double witty_palette_row_text_width(NSString *text, double size, bool medium) {
    return [text sizeWithAttributes:@{NSFontAttributeName: witty_palette_row_font(size, medium)}].width;
}

static inline CTLineRef witty_palette_row_line(NSString *text, NSDictionary *attributes) {
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    return line;
}

static inline void witty_palette_draw_row_text(CGContextRef context, NSString *text, NSColor *color,
        double size, bool medium, double x, double baseline, double width, double height) {
    if (width <= 0 || text.length == 0) return;
    NSRange newline = [text rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
    if (newline.location != NSNotFound) {
        text = [[text substringToIndex:newline.location] stringByAppendingString:@"…"];
    }
    NSDictionary *attrs = @{NSFontAttributeName:witty_palette_row_font(size, medium),
        NSForegroundColorAttributeName:color};
    CTLineRef line = witty_palette_row_line(text, attrs);
    if (!line) return;
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) > width) {
        CTLineRef token = witty_palette_row_line(@"…", attrs);
        CTLineRef truncated = token ? CTLineCreateTruncatedLine(line, width, kCTLineTruncationEnd, token) : NULL;
        if (token) CFRelease(token);
        CFRelease(line);
        line = truncated;
        if (!line) return;
    }
    CGContextSaveGState(context);
    CGContextClipToRect(context, CGRectMake(x, 0, width, height));
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, x, height - baseline);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
}

static inline NSImage *witty_palette_row_symbol(NSString *name) {
    NSImage *symbol = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    NSImageSymbolConfiguration *font = [NSImageSymbolConfiguration configurationWithPointSize:14
        weight:NSFontWeightMedium];
    return [symbol imageWithSymbolConfiguration:[font configurationByApplyingConfiguration:
        [NSImageSymbolConfiguration configurationPreferringMonochrome]]];
}

static inline double witty_palette_draw_row_symbol(CGContextRef context, NSString *name, CGImageRef tint,
        double x, double height) {
    NSImage *symbol = witty_palette_row_symbol(name);
    if (!symbol) return 0;
    NSRect alignment = symbol.alignmentRect;
    NSRect rect = NSMakeRect(x - alignment.origin.x,
        (height + alignment.size.height) / 2 + alignment.origin.y - symbol.size.height,
        symbol.size.width, symbol.size.height);
    CGContextSaveGState(context);
    CGContextBeginTransparencyLayer(context, NULL);
    [symbol drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
        fraction:1 respectFlipped:YES hints:nil];
    CGContextSetBlendMode(context, kCGBlendModeSourceIn);
    CGContextDrawImage(context, rect, tint);
    CGContextEndTransparencyLayer(context);
    CGContextRestoreGState(context);
    return alignment.size.width;
}
#endif

#endif
