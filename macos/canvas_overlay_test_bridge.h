#include <AppKit/AppKit.h>
#include <QuartzCore/QuartzCore.h>
#include <stdint.h>
#include <string.h>

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

static inline void *witty_overlay_test_png(void *object) {
    NSView *view = (NSView *)object;
    NSRect area = [view bounds];
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:area];
    if (!image) return nil;
    [view cacheDisplayInRect:area toBitmapImageRep:image];
    return [image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
