#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <QuartzCore/QuartzCore.h>

typedef struct { long majorVersion; long minorVersion; long patchVersion; } witty_native_os_version;
static inline bool witty_native_os_at_least(long major, long minor, long patch) {
    id info=((id (*)(id,SEL))objc_msgSend)((id)objc_getClass("NSProcessInfo"),sel_registerName("processInfo"));
    return ((bool (*)(id,SEL,witty_native_os_version))objc_msgSend)(info,sel_registerName("isOperatingSystemAtLeastVersion:"),(witty_native_os_version){major,minor,patch});
}

typedef bool (*witty_zoom_draw_template_fn)(void *, const CGRect *);

static inline NSImage *witty_zoom_image_from_pdf(const uint8_t *bytes, size_t count) {
    NSData *pdf = [NSData dataWithBytes:bytes length:count];
    return [[[NSImage alloc] initWithData:pdf] autorelease];
}

static inline NSImage *witty_zoom_canvas_template(const uint8_t *bytes, size_t count,
        witty_zoom_draw_template_fn draw) {
    NSImage *source = [NSImage imageNamed:@"ResetZoom"];
    if (!source) source = witty_zoom_image_from_pdf(bytes, count);
    if (!source) return nil;

    NSImage *image = [NSImage imageWithSize:source.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        return draw(source, &rect);
    }];
    image.template = YES;
    return image;
}

static inline void witty_zoom_accessory_tint(NSButton *button, CALayer *layer) {
    NSAppearance *appearance = button.effectiveAppearance;
    NSColor *color = button.contentTintColor;
    __block NSColor *tint = nil;
    [appearance performAsCurrentDrawingAppearance:^{
        tint = [color colorUsingColorSpace:NSColorSpace.displayP3ColorSpace];
    }];
    NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [name isEqualToString:NSAppearanceNameDarkAqua];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // Apply vibrancy to the Canvas mask over the titlebar at composition time.
    layer.compositingFilter = button.window.isMainWindow ? nil : (dark ? @"plusL" : @"plusD");
    layer.contentsFormat = kCAContentsFormatRGBA16Float;
    layer.backgroundColor = tint.CGColor;
    layer.opacity = button.isHighlighted ? 0.75f : 1.0f;
    [CATransaction commit];
}
#endif
