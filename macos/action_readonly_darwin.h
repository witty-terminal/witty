#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_overlay_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
@interface WittyReadonlyOutlineLayer : CALayer
@end

@implementation WittyReadonlyOutlineLayer

- (void)renderInContext:(CGContextRef)context {
    // The ink view paints the outline into AppKit's bitmap captures.
}

@end

static inline void witty_readonly_configure_layers(NSView *material, NSView *ink,
        double corner, double border) {
    material.wantsLayer = YES;
    ink.wantsLayer = YES;
    // Clip the system backdrop and blend the outline at window presentation scale.
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.layer.cornerRadius = corner;
    material.layer.masksToBounds = YES;
    CALayer *outline = [WittyReadonlyOutlineLayer layer];
    outline.cornerCurve = kCACornerCurveContinuous;
    outline.cornerRadius = corner;
    outline.borderWidth = border;
    [ink.layer addSublayer:outline];
}

static inline CALayer *witty_readonly_outline(NSView *ink) {
    for (CALayer *layer in ink.layer.sublayers) {
        if ([layer isKindOfClass:WittyReadonlyOutlineLayer.class]) return layer;
    }
    return nil;
}

static inline void witty_readonly_update_outline(NSView *ink) {
    CALayer *layer = witty_readonly_outline(ink);
    if (!layer) return;
    const CGRect bounds = ink.bounds;
    const CGFloat scale = ink.layer.contentsScale;
    [ink.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *orange = [NSColor.systemOrangeColor colorUsingColorSpace:NSColorSpace.extendedSRGBColorSpace];
        CGColorRef tint = [orange colorWithAlphaComponent:0.6].CGColor;
        if (tint && (!layer.borderColor || !CGColorEqualToColor(layer.borderColor, tint) ||
                !CGRectEqualToRect(layer.frame, bounds) || layer.contentsScale != scale)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            // Preserve half-point widths on Retina displays.
            layer.contentsScale = scale;
            layer.frame = bounds;
            layer.borderColor = tint;
            [CATransaction commit];
        }
    }];
}

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
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, *bounds);
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
