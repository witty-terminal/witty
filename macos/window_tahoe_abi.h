#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include "canvas_text_darwin.h"

static inline NSFont* witty_tahoe_title_font(void* font) {
    return (NSFont*)font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
}

static inline witty_macos_size witty_tahoe_title_size(void* view, void* title, void* font) {
    const NSSize size = [(NSString*)title sizeWithAttributes:@{NSFontAttributeName:witty_tahoe_title_font(font)}];
    const double scale = ((NSView*)view).window.backingScaleFactor ?: 1;
    // Give color glyphs room to extend past the line metrics without shifting the line's center.
    return (witty_macos_size){ceil(size.width * scale) / scale, size.height + 2 / scale};
}

static inline bool witty_tahoe_title_is_dark(NSView* view) {
    NSAppearance* appearance = view.window.effectiveAppearance ?: view.effectiveAppearance;
    return [[appearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
}

static inline void witty_tahoe_update_title_vibrancy(void* owner) {
    NSView* view = (NSView*)owner;
    // The same macOS vibrancy filters are used for the legacy tab strip.
    view.layer.compositingFilter = witty_tahoe_title_is_dark(view) ? @"plusL" : @"plusD";
}

static inline void witty_tahoe_draw_title(void* owner, CGContextRef context, void* title,
        void* font, bool main, bool vibrant, const CGRect* pixel_bounds,
        uint32_t* pixels, int width, int height) {
    NSView* view = (NSView*)owner;
    const CGRect clip = view.bounds;
    const double scale = view.window.backingScaleFactor ?: 1;
    NSDictionary* attributes = @{
        NSFontAttributeName:witty_tahoe_title_font(font),
        (NSString*)kCTForegroundColorFromContextAttributeName:@YES,
    };
    CTLineRef line = witty_canvas_text_line((NSString*)title, attributes);
    if (!line) return;
    double ascent, descent;
    double advance = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    // The toolbar can round the intrinsic width down by half a backing pixel.
    if (advance > CGRectGetWidth(clip) + 0.5 / scale) {
        CTLineRef token = witty_canvas_text_line(@"…", attributes);
        CTLineRef shortened = CTLineCreateTruncatedLine(line, CGRectGetWidth(clip),
            kCTLineTruncationEnd, token);
        if (token) CFRelease(token);
        CFRelease(line);
        if (!shortened) return;
        line = shortened;
        advance = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    }
    CGPoint origin = CGPointMake(CGRectGetMidX(clip) - advance * 0.5,
        CGRectGetMidY(clip) + (descent - ascent) * 0.5);
    const CGPoint in_window = [view convertPoint:origin toView:nil];
    origin.x += round(in_window.x * scale) / scale - in_window.x;
    origin.y += round(in_window.y * scale) / scale - in_window.y;
    const bool dark = witty_tahoe_title_is_dark(view);
    const double white = dark ? 1 : 0;
    // Inactive monochrome ink blends with the toolbar backdrop through vibrancy.
    // Color glyphs always composite normally.
    const double opacity = (main ? (dark ? 229.0 : 178.0) : (dark ? 124.0 : 127.0)) / 255;
    NSColor* color = [NSColor colorWithSRGBRed:white green:white blue:white alpha:opacity];
    WittyCanvasTextLayout layout = {
        .bounds = *pixel_bounds,
        .clip = clip,
        .position = origin,
        .color_baseline_offset = -1 / scale,
        .ink_rounding = WittyCanvasRoundInkNearest,
        .fit_color_glyphs_to_backing = true,
        .glyphs = main ? WittyCanvasAllGlyphs :
            (vibrant ? WittyCanvasMonochromeGlyphs : WittyCanvasColorGlyphs),
    };
    witty_canvas_draw_text_runs(context, line, color, layout, pixels, width, height);
    CFRelease(line);
}

typedef void (*witty_tahoe_frame_callback)(void*);
static inline void* witty_tahoe_observe_frame(void* view, void* context,
                                             witty_tahoe_frame_callback callback) {
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSViewFrameDidChangeNotification object:(id)view
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* notification) {
            callback(context);
        }];
    return [token retain];
}
static inline void witty_tahoe_observe_group(void* group, void* observer) {
    [(id)group addObserver:(id)observer forKeyPath:@"windows"
                 options:NSKeyValueObservingOptionNew context:NULL];
    [(id)group addObserver:(id)observer forKeyPath:@"tabBarVisible"
                 options:NSKeyValueObservingOptionNew context:NULL];
}
static inline void witty_tahoe_remove_group_observer(void* group, void* observer) {
    [(id)group removeObserver:(id)observer forKeyPath:@"windows"];
    [(id)group removeObserver:(id)observer forKeyPath:@"tabBarVisible"];
}
static inline bool witty_tahoe_event_in_view(void* view, void* event) {
    NSView* target = (NSView*)view;
    NSPoint point = [target convertPoint:[(NSEvent*)event locationInWindow] fromView:nil];
    return CGRectContainsPoint(target.bounds, point);
}
#endif
