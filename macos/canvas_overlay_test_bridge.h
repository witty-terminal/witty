#include <AppKit/AppKit.h>
#include <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

static inline NSColor *witty_overlay_test_display_p3_color(double r, double g, double b, double a) {
    return [NSColor colorWithDisplayP3Red:r green:g blue:b alpha:a];
}

static inline uint32_t witty_overlay_test_tile(void *object) {
    CGImageRef image = (CGImageRef)[(CALayer *)object contents];
    if (!image || CGImageGetWidth(image) != 1 || CGImageGetHeight(image) != 1) return 0;
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image));
    uint16_t rgba[4] = {0};
    if (data && CFDataGetLength(data) == sizeof(rgba)) {
        memcpy(rgba, CFDataGetBytePtr(data), sizeof(rgba));
    }
    if (data) CFRelease(data);
    return ((uint32_t)(rgba[3] / 257) << 24) | ((uint32_t)(rgba[0] / 257) << 16)
        | ((uint32_t)(rgba[1] / 257) << 8) | (rgba[2] / 257);
}

static inline float witty_overlay_test_opacity(void *object) {
    return [(CALayer *)object opacity];
}

static inline bool witty_overlay_test_window_fill_matches(CALayer *layer, NSColor *color) {
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGImageRef image = (CGImageRef)layer.contents;
    if (!srgb || srgb.alphaComponent == 0) return !image && !layer.backgroundColor;
    if (srgb.alphaComponent < 1) return !image && layer.backgroundColor
        && CGColorEqualToColor(layer.backgroundColor, color.CGColor);
    if (layer.backgroundColor) return false;
    if (!image || CGImageGetWidth(image) != 1 || CGImageGetHeight(image) != 1 ||
        CGImageGetBitsPerComponent(image) != 8 ||
        CGImageGetAlphaInfo(image) != kCGImageAlphaPremultipliedLast) return false;
    CGColorSpaceRef space = CGImageGetColorSpace(image);
    CFStringRef name = space ? CGColorSpaceGetName(space) : NULL;
    if (!name || !CFEqual(name, kCGColorSpaceSRGB)) return false;
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image));
    uint8_t rgba[4];
    bool matches = data && CFDataGetLength(data) == sizeof(rgba);
    if (matches) {
        memcpy(rgba, CFDataGetBytePtr(data), sizeof(rgba));
        double alpha = srgb.alphaComponent;
        const double expected[] = { srgb.redComponent * alpha, srgb.greenComponent * alpha,
            srgb.blueComponent * alpha, alpha };
        for (int i = 0; i < 4; ++i) {
            if (fabs(rgba[i] - expected[i] * 255) > 0.50001) matches = false;
        }
    }
    if (data) CFRelease(data);
    return matches;
}

static inline void *witty_overlay_test_png(void *object) {
    NSView *view = (NSView *)object;
    NSRect area = [view bounds];
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:area];
    if (!image) return nil;
    [view cacheDisplayInRect:area toBitmapImageRep:image];
    return [image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

// The test window belongs to this process, so its composited image can be
// captured without recording the display or another application's windows.
static inline void *witty_overlay_test_window_png(NSWindow *window) {
    typedef CGImageRef (*WindowImage)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);
    WindowImage capture = (WindowImage)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
    if (!capture) return nil;
    [window orderBack:nil];
    [window displayIfNeeded];
    [CATransaction flush];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    CGWindowID identifier = (CGWindowID)window.windowNumber;
    CGWindowListOption options = kCGWindowListOptionIncludingWindow;
    NSArray *info = (NSArray *)CGWindowListCopyWindowInfo(options, identifier);
    BOOL owned = [info.firstObject[(NSString *)kCGWindowOwnerPID] intValue] == getpid();
    [info release];
    CGImageRef image = owned ? capture(CGRectNull, options, identifier,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution) : NULL;
    if (!image) return nil;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [bitmap release];
    return png;
}
