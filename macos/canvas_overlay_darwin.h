#ifndef WITTY_CANVAS_OVERLAY_DARWIN_H
#define WITTY_CANVAS_OVERLAY_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <CoreGraphics/CoreGraphics.h>
#include <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdint.h>

static inline void witty_canvas_place_overlay(void *parent, void *child, void *above) {
    [(NSView *)parent addSubview:(NSView *)child positioned:NSWindowAbove relativeTo:(NSView *)above];
}

static inline void witty_canvas_set_material_mask(NSVisualEffectView *view, CGImageRef mask,
        double width, double height) {
    NSImage *image = [[NSImage alloc] initWithCGImage:mask size:NSMakeSize(width, height)];
    view.maskImage = image;
    [image release];
}

static inline void witty_canvas_set_image(NSImageView *view, CGImageRef pixels) {
    NSImage *image = [[NSImage alloc] initWithCGImage:pixels size:NSZeroSize];
    view.image = image;
    [image release];
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

static inline void witty_canvas_set_translucent_fill(CALayer *layer, NSView *view, NSColor *color,
        double opacity) {
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        CGColorRef fill = [color colorWithAlphaComponent:opacity].CGColor;
        if (!layer.backgroundColor || !CGColorEqualToColor(layer.backgroundColor, fill)) {
            layer.backgroundColor = fill;
        }
    }];
}

static inline bool witty_canvas_resolve_linear_srgb(NSView *view, NSColor *color,
        double *r, double *g, double *b) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
    if (!space) return false;
    __block CGColorRef resolved = NULL;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        resolved = CGColorCreateCopyByMatchingToColorSpace(space, kCGRenderingIntentDefault,
            color.CGColor, NULL);
    }];
    CGColorSpaceRelease(space);
    if (!resolved) return false;
    const CGFloat *components = CGColorGetComponents(resolved);
    *r = components[0];
    *g = components[1];
    *b = components[2];
    CGColorRelease(resolved);
    return true;
}

static inline CGColorRef witty_canvas_make_opaque_color(CGColorSpaceRef space, double r, double g,
        double b) {
    const CGFloat components[] = {r, g, b, 1};
    return CGColorCreate(space, components);
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

static inline CGImageRef witty_canvas_rgba_image(CFDataRef data, int width, int height, int depth,
        CGColorSpaceRef space, bool interpolate) {
    CGDataProviderRef provider = data ? CGDataProviderCreateWithCFData(data) : NULL;
    CGBitmapInfo info = kCGImageAlphaPremultipliedLast;
    if (depth == 16) info |= kCGBitmapByteOrder16Little;
    CGImageRef image = provider && space ? CGImageCreate(width, height, depth, depth * 4,
        (size_t)width * depth / 2, space, info, provider, NULL, interpolate, kCGRenderingIntentDefault) : NULL;
    if (provider) CGDataProviderRelease(provider);
    return image;
}

static inline CGImageRef witty_canvas_make_srgb_tile(float r, float g, float b, float a) {
    // Core Animation dithers 16-bit layer contents when compositing to the
    // window. An 8-bit tile keeps an opaque flat color uniform.
    const UInt8 rgba[] = {
        (UInt8)lround(fmin(fmax(r, 0), 1) * 255),
        (UInt8)lround(fmin(fmax(g, 0), 1) * 255),
        (UInt8)lround(fmin(fmax(b, 0), 1) * 255),
        (UInt8)lround(fmin(fmax(a, 0), 1) * 255),
    };
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)rgba, sizeof(rgba));
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = witty_canvas_rgba_image(data, 1, 1, 8, space, false);
    if (space) CGColorSpaceRelease(space);
    if (data) CFRelease(data);
    return image;
}

static inline NSColor *witty_canvas_gamma22_gray(double white) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
    const CGFloat components[] = { white, 1 };
    CGColorRef color = space ? CGColorCreate(space, components) : NULL;
    NSColor *result = color ? [NSColor colorWithCGColor:color] : nil;
    if (color) CGColorRelease(color);
    if (space) CGColorSpaceRelease(space);
    return result;
}

static inline void *witty_canvas_make_tile(const uint32_t *pixel, void *target, double opacity,
        int blend_over_gray) {
    double r, g, b;
    CGColorSpaceRef space = witty_canvas_convert_rgb(*pixel, target, &r, &g, &b);
    if (blend_over_gray >= 0) {
        // Resolve the color blend in the output profile. Moving its luminosity
        // into range preserves hue when the adjusted tint exceeds the gamut.
        double gr, gg, gb;
        CGColorSpaceRef graySpace = witty_canvas_convert_rgb((uint32_t)blend_over_gray * 0x010101,
            target, &gr, &gg, &gb);
        if (graySpace) CGColorSpaceRelease(graySpace);
        double luma = .30 * r + .59 * g + .11 * b;
        double base = .30 * gr + .59 * gg + .11 * gb;
        double low = fmin(r, fmin(g, b)) - luma;
        double high = fmax(r, fmax(g, b)) - luma;
        double scale = 1;
        if (base + low < 0) scale = base / -low;
        if (base + high > 1) scale = fmin(scale, (1 - base) / high);
        r = base + (r - luma) * scale;
        g = base + (g - luma) * scale;
        b = base + (b - luma) * scale;
    }
    int depth = blend_over_gray >= 0 ? 8 : 16;
    double alpha = opacity * (depth == 8 ? 255 : 65535);
    const uint16_t rgba[] = {
        (uint16_t)lround(fmin(fmax(r, 0), 1) * alpha),
        (uint16_t)lround(fmin(fmax(g, 0), 1) * alpha),
        (uint16_t)lround(fmin(fmax(b, 0), 1) * alpha),
        (uint16_t)lround(alpha),
    };
    const UInt8 narrow[] = { (UInt8)rgba[0], (UInt8)rgba[1], (UInt8)rgba[2], (UInt8)rgba[3] };
    CFDataRef data = depth == 8 ? CFDataCreate(NULL, narrow, sizeof(narrow))
        : CFDataCreate(NULL, (const UInt8 *)rgba, sizeof(rgba));
    CGImageRef tile = witty_canvas_rgba_image(data, 1, 1, depth, space, false);
    if (space) CGColorSpaceRelease(space);
    if (data) CFRelease(data);
    return tile;
}

static inline CGImageRef witty_canvas_alpha_image(const uint32_t *pixels, const float *coverage,
        int width, int height,
        CGColorSpaceRef space, double r, double g, double b, double opacity) {
    const size_t count = (size_t)width * height;
    const CFIndex bytes = (CFIndex)(count * 8);
    CFMutableDataRef data = CFDataCreateMutable(NULL, bytes);
    if (!data) return NULL;
    CFDataSetLength(data, bytes);
    uint16_t *rgba = (uint16_t *)CFDataGetMutableBytePtr(data);
    r = fmin(fmax(r, 0), 1);
    g = fmin(fmax(g, 0), 1);
    b = fmin(fmax(b, 0), 1);
    const double alpha_scale = 257 * fmin(fmax(opacity, 0), 1);
    for (size_t i = 0; i < count; i++) {
        const double a = coverage ? fmin(fmax(coverage[i], 0), 1) * 65535
            : (uint16_t)((pixels[i] >> 24) * alpha_scale + 0.5);
        rgba[4 * i] = (uint16_t)lround(r * a);
        rgba[4 * i + 1] = (uint16_t)lround(g * a);
        rgba[4 * i + 2] = (uint16_t)lround(b * a);
        rgba[4 * i + 3] = (uint16_t)lround(a);
    }
    CGImageRef image = witty_canvas_rgba_image(data, width, height, 16, space, true);
    CFRelease(data);
    return image;
}

static inline CGImageRef witty_canvas_make_tinted_alpha_image(const uint32_t *pixels,
        const float *coverage, int width, int height, uint32_t color, void *target) {
    double r, g, b;
    CGColorSpaceRef space = witty_canvas_convert_rgb(color, target, &r, &g, &b);
    CGImageRef image = witty_canvas_alpha_image(pixels, coverage, width, height, space, r, g, b, 1);
    if (space) CGColorSpaceRelease(space);
    return image;
}

static inline void *witty_canvas_make_alpha_image(const uint32_t *pixels, int width, int height,
        uint32_t color, void *target) {
    return witty_canvas_make_tinted_alpha_image(pixels, NULL, width, height, color, target);
}

static inline void *witty_canvas_make_gradient_mask(const float *coverage, int width, int height,
        uint32_t color, void *target) {
    return witty_canvas_make_tinted_alpha_image(NULL, coverage, width, height, color, target);
}

static inline CGImageRef witty_canvas_make_native_color_mask(const uint32_t *pixels, int width,
        int height, NSView *view, NSColor *color) {
    // Native swatches can be appearance-dependent or outside the sRGB gamut.
    NSColorSpace *space = NSColorSpace.displayP3ColorSpace;
    __block NSColor *resolved = nil;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        resolved = [color colorUsingColorSpace:space];
    }];
    if (!resolved) return NULL;
    return witty_canvas_alpha_image(pixels, NULL, width, height, space.CGColorSpace, resolved.redComponent,
        resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent);
}

static inline NSImage *witty_canvas_system_symbol(NSString *name, double size, double weight) {
    NSImage *symbol = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    NSImageSymbolConfiguration *font = [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    return [symbol imageWithSymbolConfiguration:[font configurationByApplyingConfiguration:
        [NSImageSymbolConfiguration configurationPreferringMonochrome]]];
}

static inline void witty_canvas_pixel_bounds(CGContextRef context, const CGRect *frame,
        CGRect *bounds, int *width, int *height) {
    CGRect device = CGRectIntegral(CGContextConvertRectToDeviceSpace(context, *frame));
    *bounds = CGContextConvertRectToUserSpace(context, device);
    *width = (int)device.size.width;
    *height = (int)device.size.height;
}

static inline CGContextRef witty_canvas_bitmap_context(uint32_t *pixels, int width, int height,
        CGRect bounds) {
    // Keep color glyphs and the system label's alpha in the Canvas buffer.
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    if (!space) return NULL;
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, (size_t)width * sizeof(*pixels),
        space, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    if (!context) return NULL;
    CGContextScaleCTM(context, width / bounds.size.width, height / bounds.size.height);
    CGContextTranslateCTM(context, -bounds.origin.x, -bounds.origin.y);
    return context;
}

static inline bool witty_canvas_rasterize_ellipse(uint32_t *pixels, int width, int height,
        double opacity) {
    const CGRect bounds = CGRectMake(0, 0, width, height);
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, bounds);
    if (!context) return false;
    CGContextSetGrayFillColor(context, 1, opacity);
    CGContextFillEllipseInRect(context, bounds);
    CGContextRelease(context);
    return true;
}

static inline bool witty_canvas_rasterize_capsule(uint32_t *pixels, int width, int height,
        double scale, double stroke, double opacity) {
    const CGRect bounds = CGRectMake(0, 0, width / scale, height / scale);
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, bounds);
    if (!context) return false;
    CALayer *layer = [[CALayer alloc] init];
    CGColorRef color = CGColorCreateGenericGray(1, opacity);
    const bool ready = layer && color;
    if (ready) {
        // Snapshot QuartzCore's continuous corners into the Canvas storage.
        layer.frame = bounds;
        layer.contentsScale = scale;
        layer.cornerCurve = kCACornerCurveContinuous;
        layer.cornerRadius = fmin(bounds.size.width, bounds.size.height) / 2;
        if (stroke > 0) {
            layer.borderWidth = stroke;
            layer.borderColor = color;
        } else {
            layer.backgroundColor = color;
        }
        [layer renderInContext:context];
    }
    if (color) CGColorRelease(color);
    [layer release];
    CGContextRelease(context);
    return ready;
}

static inline bool witty_canvas_rasterize_shadow(uint32_t *mask, int mask_width, int mask_height,
        uint32_t *pixels, int width, int height, double radius, double opacity) {
    const CGRect mask_bounds = CGRectMake(0, 0, mask_width, mask_height);
    CGContextRef source = witty_canvas_bitmap_context(mask, mask_width, mask_height, mask_bounds);
    if (!source) return false;
    CGImageRef silhouette = CGBitmapContextCreateImage(source);
    CGContextRelease(source);
    if (!silhouette) return false;

    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, CGRectMake(0, 0, width, height));
    CGColorRef color = CGColorCreateGenericGray(0, opacity);
    const bool ready = context && color;
    if (ready) {
        // Move the silhouette outside the bitmap and offset its shadow back into it.
        const double x = (width - mask_width) / 2.0 - width;
        const double y = (height - mask_height) / 2.0;
        CGContextSetShadowWithColor(context, CGSizeMake(width, 0), 2 * radius, color);
        CGContextDrawImage(context, CGRectOffset(mask_bounds, x, y), silhouette);
    }
    if (color) CGColorRelease(color);
    if (context) CGContextRelease(context);
    CGImageRelease(silhouette);
    return ready;
}

static inline void witty_canvas_add_continuous_rect(CGMutablePathRef path, CGRect bounds,
        double radius, double inset, const double (*x)[3][4], const double (*y)[3][4]) {
    const double right = bounds.size.width - inset;
    const double top = bounds.size.height - inset;
    const double extent_x = (*x)[0][0];
    const double extent_y = (*y)[2][3];
    radius = fmax(0, fmin(radius - inset, fmin((right - inset) / (2 * extent_x),
        (top - inset) / (2 * extent_y))));
    // Reflect the curve without exchanging the two axes of a capsule endcap.
    const CGAffineTransform corners[] = {
        {-radius, 0, 0, -radius, right, top},
        {radius, 0, 0, -radius, inset, top},
        {radius, 0, 0, radius, inset, inset},
        {-radius, 0, 0, radius, right, inset},
    };
    CGPathMoveToPoint(path, NULL, right, bounds.size.height / 2);
    for (int i = 0; i < 4; ++i) {
        if (i % 2 == 0) {
            CGPathAddLineToPoint(path, &corners[i], 0, extent_y);
            for (int j = 2; j >= 0; --j) {
                const double *px = (*x)[j];
                const double *py = (*y)[j];
                CGPathAddCurveToPoint(path, &corners[i], px[2], py[2], px[1], py[1], px[0], py[0]);
            }
        } else {
            CGPathAddLineToPoint(path, &corners[i], extent_x, 0);
            for (int j = 0; j < 3; ++j) {
                const double *px = (*x)[j];
                const double *py = (*y)[j];
                CGPathAddCurveToPoint(path, &corners[i], px[1], py[1], px[2], py[2], px[3], py[3]);
            }
        }
    }
    CGPathCloseSubpath(path);
}

static inline bool witty_canvas_rasterize_continuous_rect(uint32_t *pixels, int width, int height,
        double scale, double radius, double stroke, double opacity, bool fill_stroke,
        const double (*x)[3][4], const double (*y)[3][4]) {
    const CGRect bounds = CGRectMake(0, 0, width / scale, height / scale);
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, bounds);
    if (!context) return false;
    CGMutablePathRef path = CGPathCreateMutable();
    if (!path) {
        CGContextRelease(context);
        return false;
    }

    CGContextTranslateCTM(context, 0, bounds.size.height);
    CGContextScaleCTM(context, 1, -1);
    CGContextSetAlpha(context, opacity);
    if (stroke > 0 && !fill_stroke) {
        witty_canvas_add_continuous_rect(path, bounds, radius, stroke / 2, x, y);
        CGContextAddPath(context, path);
        CGContextSetLineWidth(context, stroke);
        CGContextStrokePath(context);
    } else {
        // Fill the ring directly to avoid Quartz's stroke tessellation gaps where the corners
        // meet the straight edges.
        witty_canvas_add_continuous_rect(path, bounds, radius, 0, x, y);
        if (stroke > 0 && 2 * stroke < fmin(bounds.size.width, bounds.size.height)) {
            witty_canvas_add_continuous_rect(path, bounds, radius, stroke, x, y);
        }
        CGContextAddPath(context, path);
        CGContextEOFillPath(context);
    }
    CGPathRelease(path);
    CGContextRelease(context);
    return true;
}

static inline CGImageRef witty_canvas_make_text_mask(const uint32_t *pixels, int width, int height) {
    size_t count = (size_t)width * height;
    CFMutableDataRef data = CFDataCreateMutable(NULL, count);
    if (!data) return NULL;
    CFDataSetLength(data, count);
    UInt8 *samples = CFDataGetMutableBytePtr(data);
    // Core Graphics image masks store inverse opacity.
    for (size_t i = 0; i < count; i++) samples[i] = 255 - (pixels[i] >> 24);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGImageRef image = provider
        ? CGImageMaskCreate(width, height, 8, 8, width, provider, NULL, false) : NULL;
    if (provider) CGDataProviderRelease(provider);
    CFRelease(data);
    return image;
}

static inline CGImageRef witty_canvas_rasterize_attributed_text(NSAttributedString *text,
        const CGRect *frame, const CGRect *bounds, uint32_t *pixels, int width, int height, bool flipped) {
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, *bounds);
    if (!context) return NULL;
    if (flipped) {
        CGContextTranslateCTM(context, 0, 2 * bounds->origin.y + bounds->size.height);
        CGContextScaleCTM(context, 1, -1);
    }
    @autoreleasepool {
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:flipped]];
        [text drawInRect:NSRectFromCGRect(*frame)];
        [NSGraphicsContext restoreGraphicsState];
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

static inline bool witty_canvas_symbol_mask(NSImage *symbol, const CGRect *glyph, const CGRect *bounds,
        uint32_t *pixels, int width, int height, bool flipped) {
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(pixels, width, height, 8, width * sizeof(*pixels), rgb,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(rgb);
    if (!bitmap) return false;
    if (flipped) CGContextTranslateCTM(bitmap, 0, height);
    CGContextScaleCTM(bitmap, width / bounds->size.width,
        (flipped ? -height : height) / bounds->size.height);
    // Release AppKit's context wrapper before returning the Canvas-owned buffer.
    @autoreleasepool {
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:bitmap flipped:flipped]];
        [symbol drawInRect:CGRectOffset(*glyph, -bounds->origin.x, -bounds->origin.y)
            fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }
    CGContextRelease(bitmap);
    return true;
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
    CGImageRef image = witty_canvas_rgba_image(data, width, height, 16, space, true);
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

static inline void witty_canvas_present_oriented_image(CGContextRef context, CGImageRef image,
        const CGRect *bounds, bool flipped) {
    CGContextSaveGState(context);
    if (flipped) {
        CGContextTranslateCTM(context, 0, 2 * bounds->origin.y + bounds->size.height);
        CGContextScaleCTM(context, 1, -1);
    }
    witty_canvas_present_tile(context, image, bounds, 1);
    CGContextRestoreGState(context);
}

static inline void witty_canvas_present_text_mask(CGContextRef context, CGImageRef mask,
        const CGRect *bounds, NSColor *tint, bool flipped) {
    CGContextSaveGState(context);
    // Blend the original opaque tint at presentation time to preserve the precision of its RGB.
    CGContextSetFillColorWithColor(context, tint.CGColor);
    witty_canvas_present_oriented_image(context, mask, bounds, flipped);
    CGContextRestoreGState(context);
}
#endif

#endif
