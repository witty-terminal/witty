#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline NSFont *witty_key_indicator_font(bool keycap) {
    double size = keycap ? 12 : 13;
    NSFont *system = [NSFont systemFontOfSize:size weight:NSFontWeightMedium];
    NSFontDescriptor *rounded = [system.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
    NSFont *font = rounded ? [NSFont fontWithDescriptor:rounded size:size] : nil;
    return font ?: system;
}

static inline double witty_key_indicator_width(NSString *text, bool keycap) {
    return [text sizeWithAttributes:@{NSFontAttributeName: witty_key_indicator_font(keycap)}].width;
}

static inline void witty_key_indicator_draw_text(CGContextRef context, NSString *label, bool keycap,
        double x, double width, double height) {
    NSDictionary *attributes = @{
        NSFontAttributeName: witty_key_indicator_font(keycap),
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:label attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    if (!line) return;
    CGContextSaveGState(context);
    CGContextClipToRect(context, CGRectMake(x, 0, width, height));
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, x, (height - (keycap ? 15 : 16)) / 2 + 3);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
}

static inline void witty_key_indicator_draw_symbol(bool chevron, double x, double height) {
    NSImageSymbolConfiguration *font = [NSImageSymbolConfiguration
        configurationWithPointSize:(chevron ? 10 : 13)
        weight:(chevron ? NSFontWeightSemibold : NSFontWeightRegular)];
    NSColor *ink = chevron ? [NSColor tertiaryLabelColor] : [NSColor secondaryLabelColor];
    ink = [ink colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: [NSColor blackColor];
    NSImageSymbolConfiguration *color = [NSImageSymbolConfiguration configurationWithPaletteColors:
        @[[ink colorWithAlphaComponent:1]]];
    NSImage *image = [NSImage imageWithSystemSymbolName:(chevron ? @"chevron.right" : @"keyboard.badge.ellipsis")
        accessibilityDescription:nil];
    image = [image imageWithSymbolConfiguration:[font configurationByApplyingConfiguration:color]];
    NSRect alignment = image.alignmentRect;
    double y = (height - alignment.size.height) / 2 - alignment.origin.y + (chevron ? 0 : 0.5);
    [image drawInRect:NSMakeRect(x - alignment.origin.x, y, image.size.width, image.size.height)
        fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:ink.alphaComponent];
}
#endif
