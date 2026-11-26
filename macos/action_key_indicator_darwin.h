#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include "canvas_text_darwin.h"

static inline void witty_key_indicator_clip_material(NSView *view, double radius) {
    CALayer *layer = view.layer;
    // Clip the backdrop in its own layer so coverage is applied when it composites.
    layer.cornerCurve = kCACornerCurveContinuous;
    layer.cornerRadius = radius;
    layer.masksToBounds = YES;
}

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

static inline void witty_key_indicator_draw_text(CGContextRef target, NSString *label, bool keycap,
        const CGRect *clip, const CGRect *bounds, uint32_t *pixels, int width, int height) {
    NSColor *color = [NSColor labelColor];
    NSDictionary *attributes = @{
        NSFontAttributeName: witty_key_indicator_font(keycap),
        NSForegroundColorAttributeName: color,
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName: @YES,
    };
    CTLineRef line = witty_canvas_text_line(label, attributes);
    if (!line) return;
    const double baseline = (clip->size.height - (keycap ? 15 : 16)) / 2 + 3;
    const WittyCanvasTextLayout layout = {
        .bounds = *bounds,
        .clip = *clip,
        .position = CGPointMake(clip->origin.x, baseline),
        .round_ink_coverage_up = true,
    };
    witty_canvas_draw_text_runs(target, line, color, layout, pixels, width, height);
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
