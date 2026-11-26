#include "canvas_text_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline NSTimer *witty_resize_indicator_timer(double interval, id owner, SEL selector) {
    NSTimer *timer = [NSTimer timerWithTimeInterval:interval target:owner selector:selector userInfo:nil repeats:NO];
    // A window being dragged runs its event loop in tracking mode.
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    return timer;
}

static inline CTLineRef witty_resize_indicator_line(NSString *text) {
    return witty_canvas_text_line(text, @{NSFontAttributeName:[NSFont systemFontOfSize:13],
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName:@YES});
}

static inline double witty_resize_indicator_text_width(NSString *text) {
    CTLineRef line = witty_resize_indicator_line(text);
    if (!line) return 0;
    const double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CFRelease(line);
    return width;
}

static inline void witty_resize_indicator_place(NSView *view, NSView *parent) {
    view.wantsLayer = YES;
    view.layer.masksToBounds = YES;
    [parent addSubview:view positioned:NSWindowBelow relativeTo:nil];
}

static inline void witty_resize_indicator_set_fill(NSView *view) {
    [view.window.effectiveAppearance performAsCurrentDrawingAppearance:^{
        view.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    }];
}

static inline void witty_resize_indicator_set_mask(NSView *view, const uint32_t *pixels,
        int width, int height, double scale, bool shadow) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
    CGImageRef image = witty_canvas_alpha_image(pixels, NULL, width, height, space, 0, 0, 0, 1);
    if (space) CGColorSpaceRelease(space);
    if (!image) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CALayer *layer = view.layer;
    if (shadow) layer.backgroundColor = NSColor.blackColor.CGColor;
    CALayer *mask = layer.mask ?: [CALayer layer];
    mask.contentsFormat = kCAContentsFormatRGBA16Float;
    mask.minificationFilter = kCAFilterNearest;
    mask.magnificationFilter = kCAFilterNearest;
    mask.frame = layer.bounds;
    mask.contents = (id)image;
    mask.contentsScale = scale;
    layer.mask = mask;
    [CATransaction commit];
    CGImageRelease(image);
}

static inline void witty_resize_indicator_draw(CGContextRef target, NSView *view, NSString *text,
        const CGRect *frame, uint32_t *pixels, int width, int height) {
    [view.window.effectiveAppearance performAsCurrentDrawingAppearance:^{
        CTLineRef line = witty_resize_indicator_line(text);
        const CGRect clip = CGRectInset(*frame, 5, 0);
        if (!line || clip.size.width <= 0) {
            if (line) CFRelease(line);
            return;
        }
        const double half_pixel = 0.5 * frame->size.width / width;
        if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) > clip.size.width + half_pixel) {
            CTLineRef ellipsis = witty_resize_indicator_line(@"…");
            CTLineRef truncated = CTLineCreateTruncatedLine(line, clip.size.width, kCTLineTruncationEnd, ellipsis);
            if (ellipsis) CFRelease(ellipsis);
            CFRelease(line);
            if (!truncated) return;
            line = truncated;
        }
        const WittyCanvasTextLayout layout = {.bounds = *frame, .clip = clip,
            .position = CGPointMake(clip.origin.x, clip.origin.y + 8), .ink_rounding = WittyCanvasRoundInkUp};
        witty_canvas_draw_text_runs(target, line, NSColor.labelColor, layout, pixels, width, height);
        CFRelease(line);
    }];
}
#endif
