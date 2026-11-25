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

static inline uint32_t witty_canvas_resolve_srgb_alpha(void *view, void *color, double *alpha) {
    __block uint32_t rgb = 0;
    [[(NSView *)view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        NSColor *resolved = [(NSColor *)color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (resolved) {
            uint32_t r = (uint32_t)(resolved.redComponent * 255 + 0.5);
            uint32_t g = (uint32_t)(resolved.greenComponent * 255 + 0.5);
            uint32_t b = (uint32_t)(resolved.blueComponent * 255 + 0.5);
            rgb = (r << 16) | (g << 8) | b;
            if (alpha) *alpha = resolved.alphaComponent;
        }
    }];
    return rgb;
}

static inline uint32_t witty_canvas_resolve_srgb(void *view, void *color) {
    return witty_canvas_resolve_srgb_alpha(view, color, NULL);
}

static inline CGColorSpaceRef witty_canvas_convert_rgb(uint32_t rgb, void *target, double *r, double *g, double *b) {
    *r = (double)((rgb >> 16) & 255) / 255;
    *g = (double)((rgb >> 8) & 255) / 255;
    *b = (double)(rgb & 255) / 255;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (target) {
        NSWindow *window = [(NSView *)target window];
        NSColorSpace *profile = window.colorSpace ?: window.screen.colorSpace;
        NSColor *color = [NSColor colorWithSRGBRed:*r green:*g blue:*b alpha:1];
        NSColor *converted = profile.colorSpaceModel == NSColorSpaceModelRGB
            ? [color colorUsingColorSpace:profile] : nil;
        if (converted) {
            *r = converted.redComponent;
            *g = converted.greenComponent;
            *b = converted.blueComponent;
            if (space) CGColorSpaceRelease(space);
            space = CGColorSpaceRetain(profile.CGColorSpace);
        }
    }
    return space;
}

static inline CGImageRef witty_canvas_rgba16_image(CFDataRef data, int width, int height, CGColorSpaceRef space, bool interpolate) {
    CGDataProviderRef provider = data ? CGDataProviderCreateWithCFData(data) : NULL;
    CGImageRef image = provider && space ? CGImageCreate(width, height, 16, 64, (size_t)width * 8, space,
        kCGBitmapByteOrder16Little | kCGImageAlphaPremultipliedLast, provider, NULL, interpolate,
        kCGRenderingIntentDefault) : NULL;
    if (provider) CGDataProviderRelease(provider);
    return image;
}

static inline void *witty_canvas_make_tile(const uint32_t *pixel, void *target, double opacity) {
    double r, g, b;
    CGColorSpaceRef space = witty_canvas_convert_rgb(*pixel, target, &r, &g, &b);
    double alpha = opacity * 65535;
    const uint16_t rgba[] = {
        (uint16_t)lround(fmin(fmax(r, 0), 1) * alpha),
        (uint16_t)lround(fmin(fmax(g, 0), 1) * alpha),
        (uint16_t)lround(fmin(fmax(b, 0), 1) * alpha),
        (uint16_t)lround(alpha),
    };
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)rgba, sizeof(rgba));
    CGImageRef tile = witty_canvas_rgba16_image(data, 1, 1, space, false);
    if (space) CGColorSpaceRelease(space);
    if (data) CFRelease(data);
    return tile;
}

static inline void *witty_canvas_make_alpha_image(const uint32_t *pixels, int width, int height, uint32_t color, void *target) {
    const size_t count = (size_t)width * height;
    const CFIndex bytes = (CFIndex)(count * 8);
    CFMutableDataRef data = CFDataCreateMutable(NULL, bytes);
    if (!data) return NULL;
    CFDataSetLength(data, bytes);
    uint16_t *rgba = (uint16_t *)CFDataGetMutableBytePtr(data);
    double r, g, b;
    CGColorSpaceRef space = witty_canvas_convert_rgb(color, target, &r, &g, &b);
    r = fmin(fmax(r, 0), 1);
    g = fmin(fmax(g, 0), 1);
    b = fmin(fmax(b, 0), 1);
    for (size_t i = 0; i < count; i++) {
        const uint16_t a = (pixels[i] >> 24) * 257;
        rgba[4 * i] = (uint16_t)lround(r * a);
        rgba[4 * i + 1] = (uint16_t)lround(g * a);
        rgba[4 * i + 2] = (uint16_t)lround(b * a);
        rgba[4 * i + 3] = a;
    }
    CGImageRef image = witty_canvas_rgba16_image(data, width, height, space, true);
    if (space) CGColorSpaceRelease(space);
    CFRelease(data);
    return image;
}

static inline void *witty_canvas_make_color_image(const uint32_t *pixels, int width, int height) {
    const size_t count = (size_t)width * height;
    const CFIndex bytes = (CFIndex)(count * 8);
    CFMutableDataRef data = CFDataCreateMutable(NULL, bytes);
    if (!data) return NULL;
    CFDataSetLength(data, bytes);
    uint16_t *rgba = (uint16_t *)CFDataGetMutableBytePtr(data);
    for (size_t i = 0; i < count; i++) {
        const uint32_t pixel = pixels[i];
        rgba[4 * i] = ((pixel >> 16) & 255) * 257;
        rgba[4 * i + 1] = ((pixel >> 8) & 255) * 257;
        rgba[4 * i + 2] = (pixel & 255) * 257;
        rgba[4 * i + 3] = (pixel >> 24) * 257;
    }
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = witty_canvas_rgba16_image(data, width, height, space, true);
    if (space) CGColorSpaceRelease(space);
    CFRelease(data);
    return image;
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
