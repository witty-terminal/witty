#ifndef WITTY_SPLIT_DIVIDER_DARWIN_H
#define WITTY_SPLIT_DIVIDER_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

static inline void witty_split_place_overlay(void *parent, void *child) {
    [(NSView *)parent addSubview:(NSView *)child positioned:NSWindowAbove relativeTo:nil];
}

static inline void witty_split_present_dividers(void *target, const uint32_t *pixel, const void *positions, int count) {
    CGContextRef context = (CGContextRef)target;
    if (!context || count <= 0) return;
    const CGRect *rects = positions;
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)pixel, sizeof(*pixel));
    CGDataProviderRef provider = data ? CGDataProviderCreateWithCFData(data) : NULL;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef tile = provider && space ? CGImageCreate(1, 1, 8, 32, sizeof(*pixel), space,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, provider, NULL, false,
        kCGRenderingIntentDefault) : NULL;
    if (tile) {
        CGContextSaveGState(context);
        CGContextSetInterpolationQuality(context, kCGInterpolationNone);
        for (int i = 0; i < count; i++) CGContextDrawImage(context, rects[i], tile);
        CGContextRestoreGState(context);
        CGImageRelease(tile);
    }
    if (space) CGColorSpaceRelease(space);
    if (provider) CGDataProviderRelease(provider);
    if (data) CFRelease(data);
}
#endif

#endif
