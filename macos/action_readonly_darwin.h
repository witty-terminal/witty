#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_overlay_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
@interface WittyReadonlyPresentationLayer : CALayer
@end

@implementation WittyReadonlyPresentationLayer

- (void)renderInContext:(CGContextRef)context {
    // The ink view paints these layers into AppKit's bitmap captures.
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
    CALayer *outline = [WittyReadonlyPresentationLayer layer];
    outline.name = @"WittyReadonlyOutline";
    outline.cornerCurve = kCACornerCurveContinuous;
    outline.cornerRadius = corner;
    outline.borderWidth = border;
    [ink.layer addSublayer:outline];

    CALayer *eye = [WittyReadonlyPresentationLayer layer];
    eye.name = @"WittyReadonlyEye";
    [ink.layer addSublayer:eye];
}

static inline CALayer *witty_readonly_layer(NSView *ink, NSString *name) {
    for (CALayer *layer in ink.layer.sublayers) {
        if ([layer.name isEqualToString:name]) return layer;
    }
    return nil;
}

static inline CALayer *witty_readonly_outline(NSView *ink) {
    return witty_readonly_layer(ink, @"WittyReadonlyOutline");
}

static inline void witty_readonly_present_eye(NSView *ink, NSColor *tint, const CGRect *bounds,
        const uint32_t *pixels, int width, int height) {
    CALayer *eye = witty_readonly_layer(ink, @"WittyReadonlyEye");
    if (!eye) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    eye.contentsScale = ink.layer.contentsScale;
    eye.frame = *bounds;
    // Apply the unrounded tint when the window composites the Canvas coverage.
    eye.backgroundColor = tint.CGColor;
    witty_canvas_set_layer_mask(eye, pixels, width, height, width / bounds->size.width);
    [CATransaction commit];
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
