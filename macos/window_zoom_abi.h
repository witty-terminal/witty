#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>

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
#endif
