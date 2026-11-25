#ifndef WITTY_ACTION_PALETTE_CHROME_DARWIN_H
#define WITTY_ACTION_PALETTE_CHROME_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <QuartzCore/QuartzCore.h>

static inline NSArray *witty_palette_backdrop_filters(bool light) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL factory = NSSelectorFromString(@"filterWithType:");
    if (![filterClass respondsToSelector:factory]) return nil;
    id saturation = [filterClass performSelector:factory withObject:@"colorSaturate"];
    id blur = [filterClass performSelector:factory withObject:@"gaussianBlur"];
    if (!saturation || !blur) return nil;
    [saturation setValue:@(light ? 1.8 : 1.6) forKey:@"inputAmount"];
    [blur setValue:@60 forKey:@"inputRadius"];
    [blur setValue:@YES forKey:@"inputNormalizeEdges"];
    return @[saturation, blur];
}

static inline CALayer *witty_palette_backdrop_layer(NSView *plate) {
    // Sample the terminal with the same material recipe as SwiftUI's ultra-thin material.
    CALayer *blur = [NSClassFromString(@"CABackdropLayer") layer];
    if (![blur respondsToSelector:NSSelectorFromString(@"setScale:")]) return nil;
    @try {
        blur.filters = witty_palette_backdrop_filters(false);
        if (!blur.filters.count) return nil;
        [blur setValue:@0.25 forKey:@"scale"];
    } @catch (NSException *exception) {
        return nil;
    }

    CALayer *material = [CALayer layer];
    [material addSublayer:blur];
    [material addSublayer:[CALayer layer]];
    CALayer *chameleon = [NSClassFromString(@"CAChameleonLayer") layer];
    if (chameleon) {
        chameleon.opacity = 0.05;
        [material addSublayer:chameleon];
    }
    [plate.layer addSublayer:material];
    return material;
}

static inline void witty_palette_backdrop_appearance(CALayer *material, bool light, CGImageRef limit) {
    CALayer *blur = material.sublayers[0];
    // The material's own fill is part of the system backdrop filter.
    blur.backgroundColor = light
        ? [NSColor colorWithSRGBRed:0.9646 green:0.9648 blue:0.9646 alpha:0.36].CGColor
        : [NSColor colorWithSRGBRed:0.1569 green:0.1569 blue:0.1569 alpha:0.4].CGColor;
    blur.filters = witty_palette_backdrop_filters(light);
    CALayer *clamp = material.sublayers[1];
    clamp.compositingFilter = light ? @"darkenBlendMode" : @"lightenBlendMode";
    clamp.contents = (id)limit;
}

static inline void witty_palette_backdrop_frame(CALayer *material, double width, double height, double scale) {
    material.frame = CGRectMake(0, 0, width, height);
    material.contentsScale = scale;
    for (CALayer *layer in material.sublayers) {
        layer.frame = material.bounds;
        layer.contentsScale = scale;
    }
}
#endif

#endif
