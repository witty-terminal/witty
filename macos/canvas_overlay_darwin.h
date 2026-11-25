#ifndef WITTY_CANVAS_OVERLAY_DARWIN_H
#define WITTY_CANVAS_OVERLAY_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>

static inline void witty_canvas_place_overlay(void *parent, void *child, void *above) {
    [(NSView *)parent addSubview:(NSView *)child positioned:NSWindowAbove relativeTo:(NSView *)above];
}

static inline uint32_t witty_canvas_resolve_srgb(void *view, void *color) {
    __block uint32_t rgb = 0;
    [[(NSView *)view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        NSColor *resolved = [(NSColor *)color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (resolved) {
            uint32_t r = (uint32_t)(resolved.redComponent * 255 + 0.5);
            uint32_t g = (uint32_t)(resolved.greenComponent * 255 + 0.5);
            uint32_t b = (uint32_t)(resolved.blueComponent * 255 + 0.5);
            rgb = (r << 16) | (g << 8) | b;
        }
    }];
    return rgb;
}

static inline void *witty_canvas_make_tile(const uint32_t *pixel, void *target, double opacity) {
    double r = (double)((*pixel >> 16) & 255) / 255;
    double g = (double)((*pixel >> 8) & 255) / 255;
    double b = (double)(*pixel & 255) / 255;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (target) {
        NSWindow *window = [(NSView *)target window];
        NSColorSpace *profile = window.colorSpace ?: window.screen.colorSpace;
        NSColor *color = [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];
        NSColor *converted = profile.colorSpaceModel == NSColorSpaceModelRGB
            ? [color colorUsingColorSpace:profile] : nil;
        if (converted) {
            r = converted.redComponent;
            g = converted.greenComponent;
            b = converted.blueComponent;
            if (space) CGColorSpaceRelease(space);
            space = CGColorSpaceRetain(profile.CGColorSpace);
        }
    }
    // Preserve component precision when Core Graphics converts sRGB to the window profile.
    double alpha = opacity * 65535;
    const uint16_t rgba[] = {
        (uint16_t)lround(fmin(fmax(r, 0), 1) * alpha),
        (uint16_t)lround(fmin(fmax(g, 0), 1) * alpha),
        (uint16_t)lround(fmin(fmax(b, 0), 1) * alpha),
        (uint16_t)lround(alpha),
    };
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)rgba, sizeof(rgba));
    CGDataProviderRef provider = data ? CGDataProviderCreateWithCFData(data) : NULL;
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
