#include "canvas_text_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline NSString *witty_child_exit_duration(uint64_t runtime) {
    NSMeasurementFormatter *formatter = [[[NSMeasurementFormatter alloc] init] autorelease];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    formatter.unitOptions = runtime > 1000 ? NSMeasurementFormatterUnitOptionsNaturalScale
        : NSMeasurementFormatterUnitOptionsProvidedUnit;
    NSMeasurement *time = [[[NSMeasurement alloc] initWithDoubleValue:runtime
        unit:NSUnitDuration.milliseconds] autorelease];
    return [formatter stringFromMeasurement:time];
}

static inline double witty_child_exit_height(double size) {
    NSFont *font = [NSFont systemFontOfSize:size];
    return round(font.ascender) + ceil(-font.descender) + 8;
}

static inline void witty_child_exit_prepare_view(NSView *view) {
    view.wantsLayer = YES;
    view.accessibilityElement = YES;
    view.accessibilityRole = NSAccessibilityStaticTextRole;
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:view userInfo:nil];
    [view addTrackingArea:area];
    [area release];
}

static inline void witty_child_exit_set_fill(NSView *view, bool failed) {
    [view.window.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *fill = failed ? [NSColor.systemRedColor colorWithAlphaComponent:0.5]
            : NSColor.windowBackgroundColor;
        view.layer.backgroundColor = fill.CGColor;
    }];
}

static inline void witty_child_exit_draw(CGContextRef target, NSView *view, NSString *text,
        NSString *duration, double size, const CGRect *bounds, uint32_t *pixels, int width, int height) {
    NSFont *font = [NSFont systemFontOfSize:size];
    NSDictionary *attributes = @{NSFontAttributeName:font,
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName:@YES};
    NSMutableAttributedString *value = [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];
    if (duration.length) {
        const NSRange range = [text rangeOfString:duration];
        if (range.location != NSNotFound) {
            [value addAttribute:NSFontAttributeName value:[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightBold]
                range:range];
        }
    }
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    const CGRect clip = CGRectInset(*bounds, 8, 0);
    if (!line || clip.size.width <= 0) {
        if (line) CFRelease(line);
        return;
    }
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) > clip.size.width) {
        CTLineRef token = witty_canvas_text_line(@"…", attributes);
        CTLineRef shortened = CTLineCreateTruncatedLine(line, clip.size.width, kCTLineTruncationEnd, token);
        if (token) CFRelease(token);
        CFRelease(line);
        if (!shortened) return;
        line = shortened;
    }
    const double scale = height / bounds->size.height;
    const double x = CGRectGetMidX(clip) - CTLineGetTypographicBounds(line, NULL, NULL, NULL) / 2;
    const double y = CGRectGetMinY(clip) + 4 + ceil(-font.descender);
    const WittyCanvasTextLayout layout = {
        .bounds = *bounds, .clip = clip,
        .position = CGPointMake(round(x * scale) / scale, round(y * scale) / scale),
        .ink_rounding = WittyCanvasRoundInkUp,
    };
    [view.window.effectiveAppearance performAsCurrentDrawingAppearance:^{
        witty_canvas_draw_text_runs(target, line, NSColor.labelColor, layout, pixels, width, height);
    }];
    CFRelease(line);
}
#endif
