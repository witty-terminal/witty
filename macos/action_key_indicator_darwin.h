#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_overlay_darwin.h"

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

static inline NSImage *witty_key_indicator_symbol(bool chevron, double x, double height,
        CGRect *frame) {
    NSImage *image = witty_canvas_system_symbol(chevron ? @"chevron.right" : @"keyboard.badge.ellipsis",
        chevron ? 10 : 13, chevron ? NSFontWeightSemibold : NSFontWeightRegular);
    if (!image) return nil;
    NSRect alignment = image.alignmentRect;
    double y = (height - alignment.size.height) / 2 - alignment.origin.y + (chevron ? 0 : 0.5);
    *frame = CGRectMake(x - alignment.origin.x, y, image.size.width, image.size.height);
    return image;
}
#endif
