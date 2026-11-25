#ifndef WITTY_CANVAS_OVERLAY_DARWIN_H
#define WITTY_CANVAS_OVERLAY_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

static inline void witty_canvas_place_overlay(void *parent, void *child, void *above) {
    [(NSView *)parent addSubview:(NSView *)child positioned:NSWindowAbove relativeTo:(NSView *)above];
}

static inline void *witty_canvas_make_tile(const uint32_t *pixel) {
    // Preserve component precision when Core Graphics converts sRGB to the window profile.
    const uint16_t rgba[] = {
        ((*pixel >> 16) & 255) * 257,
        ((*pixel >> 8) & 255) * 257,
        (*pixel & 255) * 257,
        65535,
    };
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)rgba, sizeof(rgba));
    CGDataProviderRef provider = data ? CGDataProviderCreateWithCFData(data) : NULL;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef tile = provider && space ? CGImageCreate(1, 1, 16, 64, sizeof(rgba), space,
        kCGBitmapByteOrder16Little | kCGImageAlphaPremultipliedLast, provider, NULL, false,
        kCGRenderingIntentDefault) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (provider) CGDataProviderRelease(provider);
    if (data) CFRelease(data);
    return tile;
}

static inline void witty_canvas_present_tile(void *target, void *image, const void *positions, int count) {
    CGContextRef context = (CGContextRef)target;
    const CGRect *rects = positions;
    CGContextSaveGState(context);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    for (int i = 0; i < count; i++) CGContextDrawImage(context, rects[i], (CGImageRef)image);
    CGContextRestoreGState(context);
}
#endif

#endif
