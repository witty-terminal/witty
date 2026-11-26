#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_text_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static NSString *const witty_hover_ellipsis_attribute = @"WittyHoverEllipsis";

typedef struct {
    CTRunRef run;
    CFIndex index;
    double x_offset;
    bool right_to_left;
} WittyHoverColorGlyph;

typedef struct {
    CTLineRef core_text;
    NSTextLineFragment *fragment;
    NSTextContentStorage *fragment_owner;
    WittyHoverColorGlyph *color_glyphs;
    size_t color_count;
} WittyHoverLine;

static inline void witty_hover_release_line(WittyHoverLine *line) {
    if (line->core_text) CFRelease(line->core_text);
    [line->fragment release];
    [line->fragment_owner release];
    free(line->color_glyphs);
    free(line);
}

static inline bool witty_hover_line_has_color(CTLineRef line) {
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
        if (witty_canvas_font_has_color_glyphs((CTFontRef)attributes[(id)kCTFontAttributeName])) return true;
    }
    return false;
}

static inline bool witty_hover_line_is_left_to_right(CTLineRef line) {
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        if (CTRunGetStatus((CTRunRef)CFArrayGetValueAtIndex(runs, i)) &
                (kCTRunStatusRightToLeft | kCTRunStatusNonMonotonic)) return false;
    }
    return true;
}

static inline CTLineRef witty_hover_join_truncation(NSString *text, NSDictionary *attributes,
        NSUInteger prefix_end, NSUInteger suffix_start, double prefix_width) {
    if (suffix_start <= prefix_end || suffix_start > text.length) return NULL;
    if (suffix_start < text.length &&
        [text rangeOfComposedCharacterSequenceAtIndex:suffix_start].location != suffix_start) return NULL;
    NSRange last_prefix = NSMakeRange(0, 0);
    if (prefix_end) {
        last_prefix = [text rangeOfComposedCharacterSequenceAtIndex:prefix_end - 1];
        if (NSMaxRange(last_prefix) != prefix_end) return NULL;
    }
    NSString *display = [NSString stringWithFormat:@"%@…%@",
        [text substringToIndex:prefix_end], [text substringFromIndex:suffix_start]];
    NSMutableAttributedString *value = [[NSMutableAttributedString alloc] initWithString:display
        attributes:attributes];
    // Give the ellipsis its own advance and preserve kerning inside the prefix.
    [value addAttribute:NSKernAttributeName value:@0 range:NSMakeRange(prefix_end, 1)];
    CTLineRef joined = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    if (joined && prefix_end) {
        const double adjustment = prefix_width - CTLineGetOffsetForStringIndex(joined, (CFIndex)prefix_end, NULL);
        if (adjustment != 0) {
            [value addAttribute:NSKernAttributeName value:@(adjustment) range:last_prefix];
            CFRelease(joined);
            joined = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
        }
    }
    [value release];
    return joined;
}

API_AVAILABLE(macos(12.0))
static inline CTLineRef witty_hover_line_from_fragment(NSString *text, NSDictionary *attributes,
        NSTextLineFragment *fragment, CTLineRef token, double limit, double *width) {
    const double epsilon = 0.0001;
    const double fitted_width = fragment.typographicBounds.size.width;
    const double token_width = CTLineGetTypographicBounds(token, NULL, NULL, NULL);
    if (!fragment || fitted_width > limit || fitted_width < token_width) return NULL;
    if (fabs(fitted_width - token_width) < epsilon) {
        *width = fitted_width;
        return (CTLineRef)CFRetain(token);
    }

    // Hit testing jumps across the hidden source characters at the ellipsis's right edge.
    CTLineRef single_cluster_cut = NULL;
    for (NSUInteger prefix = 0, next; prefix < text.length; prefix = next) {
        next = NSMaxRange([text rangeOfComposedCharacterSequenceAtIndex:prefix]);
        const double start = [fragment locationForCharacterAtIndex:(NSInteger)prefix].x;
        NSUInteger suffix = text.length;
        double suffix_origin = fitted_width;
        if (fabs(start + token_width - fitted_width) < epsilon) {
            if ([fragment characterIndexForPoint:CGPointMake(start + token_width / 2, 0)] !=
                (NSInteger)prefix) continue;
        } else {
            if (next >= text.length) break;
            suffix_origin = [fragment locationForCharacterAtIndex:(NSInteger)next].x;
            if (suffix_origin <= start || suffix_origin + epsilon >= fitted_width ||
                [fragment characterIndexForPoint:CGPointMake((start + suffix_origin) / 2, 0)] !=
                (NSInteger)prefix) continue;
            const NSInteger hit = [fragment characterIndexForPoint:CGPointMake(suffix_origin + epsilon, 0)];
            if (hit < (NSInteger)next || hit >= (NSInteger)text.length ||
                fabs([fragment locationForCharacterAtIndex:hit].x - suffix_origin) >= epsilon) continue;
            suffix = (NSUInteger)hit;
            if (suffix == next && (single_cluster_cut || fabs(suffix_origin - start - token_width) >= epsilon)) continue;
        }

        CTLineRef joined = witty_hover_join_truncation(text, attributes, prefix, suffix, suffix_origin - token_width);
        if (!joined) continue;
        // Ligatures can also share caret positions. Require the rebuilt line to fit the measured layout.
        const double joined_width = CTLineGetTypographicBounds(joined, NULL, NULL, NULL);
        // The line fragment can clip its reported width at the offered edge.
        if (fabs(joined_width - fitted_width) >= epsilon &&
            !(fitted_width == limit && joined_width > limit && joined_width - limit <= 1.0 / 1024)) {
            CFRelease(joined);
            continue;
        }
        if (suffix == next && suffix < text.length) {
            single_cluster_cut = joined;
            continue;
        }
        if (single_cluster_cut) CFRelease(single_cluster_cut);
        *width = fitted_width;
        return joined;
    }
    if (single_cluster_cut) *width = fitted_width;
    return single_cluster_cut;
}

API_AVAILABLE(macos(12.0))
static inline NSTextLineFragment *witty_hover_layout_fragment(NSString *text, NSDictionary *attributes,
        double limit, NSIndexSet *hidden_colors, NSTextContentStorage **owner) {
    @autoreleasepool {
        NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
        style.lineBreakMode = NSLineBreakByTruncatingMiddle;
        style.allowsDefaultTighteningForTruncation = NO;
        NSMutableDictionary *layout_attributes = [[attributes mutableCopy] autorelease];
        layout_attributes[NSParagraphStyleAttributeName] = style;
        if (hidden_colors.count) {
            // Explicit ink prevents a transparent color run from tinting its neighbors.
            [layout_attributes removeObjectForKey:(__bridge NSString *)kCTForegroundColorFromContextAttributeName];
            layout_attributes[NSForegroundColorAttributeName] = [NSColor colorWithName:@"WittyHoverOpaqueLabel"
                dynamicProvider:^NSColor *(NSAppearance *appearance) {
                    NSString *mode = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
                    return [mode isEqualToString:NSAppearanceNameDarkAqua] ? NSColor.whiteColor : NSColor.blackColor;
                }];
        }
        NSTextContentStorage *content = [[[NSTextContentStorage alloc] init] autorelease];
        NSMutableAttributedString *value = [[[NSMutableAttributedString alloc] initWithString:text
            attributes:layout_attributes] autorelease];
        [hidden_colors enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            [value addAttribute:NSForegroundColorAttributeName value:NSColor.clearColor range:range];
        }];
        content.attributedString = value;
        NSTextLayoutManager *layout = [[[NSTextLayoutManager alloc] init] autorelease];
        [content addTextLayoutManager:layout];
        NSTextContainer *container = [[[NSTextContainer alloc] initWithSize:NSMakeSize(limit, CGFLOAT_MAX)] autorelease];
        container.maximumNumberOfLines = 1;
        container.lineFragmentPadding = 0;
        container.lineBreakMode = NSLineBreakByTruncatingMiddle;
        layout.textContainer = container;
        NSTextRange *range = layout.documentRange;
        [layout ensureLayoutForRange:range];
        __block NSTextLineFragment *line = nil;
        [layout enumerateTextLayoutFragmentsFromLocation:range.location
            options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout usingBlock:^BOOL(NSTextLayoutFragment *fragment) {
                line = [fragment.textLineFragments.firstObject retain];
                return NO;
            }];
        // AppKit uses the layout manager to resolve explicit foreground colors at draw time.
        if (line && owner) *owner = [content retain];
        return line;
    }
}

API_AVAILABLE(macos(12.0))
static inline bool witty_hover_fragment_color_origin(NSTextLineFragment *fragment, NSRange cluster,
        double advance, double token_width, double *origin, bool *right_to_left) {
    const double caret = [fragment locationForCharacterAtIndex:(NSInteger)cluster.location].x;
    const double end = fragment.typographicBounds.size.width;
    const double step = advance / 4;
    // The reported caret can belong to the ellipsis or the other side of an RTL run.
    // Verify the advance from two hit tests and recover the glyph's left edge.
    const double reach = 2 * advance + token_width;
    for (double x = fmax(0, caret - reach) + step / 2; x + step < fmin(end, caret + reach); x += step) {
        const CGPoint left = CGPointMake(x, 0);
        const CGPoint right = CGPointMake(x + step, 0);
        const NSInteger left_index = [fragment characterIndexForPoint:left];
        const NSInteger right_index = [fragment characterIndexForPoint:right];
        if (left_index < 0 || right_index < 0 || !NSLocationInRange((NSUInteger)left_index, cluster) ||
            !NSLocationInRange((NSUInteger)right_index, cluster)) continue;
        const double first = [fragment fractionOfDistanceThroughGlyphForPoint:left];
        const double second = [fragment fractionOfDistanceThroughGlyphForPoint:right];
        if (fabs(fabs(second - first) - 0.25) > 0.0001) continue;
        *right_to_left = second < first;
        *origin = x - advance * (*right_to_left ? 1 - first : first);
        return true;
    }
    return false;
}

API_AVAILABLE(macos(12.0))
static inline void witty_hover_set_fragment_colors(WittyHoverLine *result, NSTextLineFragment *fragment,
        NSString *text, NSDictionary *attributes, double limit, double token_width) {
    CTLineRef source = result->core_text;
    WittyHoverColorGlyph *glyphs = calloc((size_t)CTLineGetGlyphCount(source), sizeof(*glyphs));
    if (!glyphs) return;
    NSMutableIndexSet *hidden = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *seen = [NSMutableIndexSet indexSet];
    size_t count = 0;
    CFArrayRef runs = CTLineGetGlyphRuns(source);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        CTFontRef font = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
        if (!witty_canvas_font_has_color_glyphs(font)) continue;
        if (!CGAffineTransformIsIdentity(CTRunGetTextMatrix(run))) goto unsupported;
        for (CFIndex j = 0; j < CTRunGetGlyphCount(run); ++j) {
            CFRange glyph = CFRangeMake(j, 1);
            CFIndex index;
            CTRunGetStringIndices(run, glyph, &index);
            if (index < 0 || (NSUInteger)index >= text.length) goto unsupported;
            NSRange cluster = [text rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)index];
            // Each replayed bitmap must cover one complete composed character.
            if (cluster.location != (NSUInteger)index || [seen containsIndex:cluster.location]) goto unsupported;
            [seen addIndex:cluster.location];
            CGSize advance;
            CTRunGetAdvances(run, glyph, &advance);
            if (advance.width <= token_width) goto unsupported;
            double origin;
            bool right_to_left;
            if (!witty_hover_fragment_color_origin(fragment, cluster, advance.width, token_width, &origin,
                &right_to_left)) continue;
            CGPoint source_origin;
            CTRunGetPositions(run, glyph, &source_origin);
            glyphs[count++] = (WittyHoverColorGlyph){run, j, origin - fragment.glyphOrigin.x - source_origin.x,
                right_to_left};
            [hidden addIndexesInRange:cluster];
        }
    }

    if (count == 0) {
        free(glyphs);
        result->fragment = [fragment retain];
        return;
    }
    NSTextContentStorage *owner = nil;
    NSTextLineFragment *ink = witty_hover_layout_fragment(text, attributes, limit, hidden, &owner);
    if (!ink || !CGRectEqualToRect(ink.typographicBounds, fragment.typographicBounds) ||
        !CGPointEqualToPoint(ink.glyphOrigin, fragment.glyphOrigin)) {
        [ink release];
        [owner release];
        goto unsupported;
    }
    result->fragment = ink;
    result->fragment_owner = owner;
    result->color_glyphs = glyphs;
    result->color_count = count;
    return;

unsupported:
    free(glyphs);
}

static inline CTLineRef witty_hover_refine_truncation(NSString *text, NSDictionary *attributes,
        CTLineRef line, CTLineRef truncated, CTLineRef token, double limit) {
    CFIndex prefix_end = 0;
    CFIndex suffix_start = (CFIndex)text.length;
    bool after_token = false;
    CGPoint token_origin = CGPointZero;
    CFArrayRef runs = CTLineGetGlyphRuns(truncated);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        if (CFDictionaryContainsKey(CTRunGetAttributes(run), witty_hover_ellipsis_attribute)) {
            CTRunGetPositions(run, CFRangeMake(0, 1), &token_origin);
            after_token = true;
            continue;
        }
        const CFRange chars = CTRunGetStringRange(run);
        if (after_token) {
            suffix_start = chars.location;
            break;
        }
        prefix_end = chars.location + chars.length;
    }
    double prefix_width = token_origin.x;
    const bool missing_prefix = prefix_end == 0 && suffix_start < (CFIndex)text.length;
    if (missing_prefix) {
        // Keep the first complete character when both ends fit beside the ellipsis.
        const CFIndex first = (CFIndex)NSMaxRange([text rangeOfComposedCharacterSequenceAtIndex:0]);
        const double leading = CTLineGetOffsetForStringIndex(line, first, NULL);
        if (first >= suffix_start || leading <= 0 ||
            leading + CTLineGetTypographicBounds(truncated, NULL, NULL, NULL) > limit) {
            return (CTLineRef)CFRetain(token);
        }
        prefix_end = first;
        prefix_width = leading;
    }
    if (prefix_end <= 0 || suffix_start <= prefix_end || suffix_start >= (CFIndex)text.length) return NULL;

    // Preserve the leading part and let whole characters from the URL tail use the remaining width.
    const double suffix_budget = limit - prefix_width - CTLineGetTypographicBounds(token, NULL, NULL, NULL);
    const double line_width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CFIndex start = suffix_start;
    while (start > prefix_end) {
        const NSRange cluster = [text rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)start - 1];
        const CFIndex next = (CFIndex)cluster.location;
        if (next <= prefix_end || NSMaxRange(cluster) != (NSUInteger)start ||
            line_width - CTLineGetOffsetForStringIndex(line, next, NULL) > suffix_budget) break;
        start = next;
    }
    if (start == suffix_start && !missing_prefix) return NULL;

    CTLineRef expanded = witty_hover_join_truncation(text, attributes, (NSUInteger)prefix_end, (NSUInteger)start, prefix_width);
    if (expanded && CTLineGetTypographicBounds(expanded, NULL, NULL, NULL) > limit) {
        CFRelease(expanded);
        expanded = NULL;
    }
    if (!expanded && missing_prefix) return (CTLineRef)CFRetain(token);
    return expanded;
}

static inline WittyHoverLine *witty_hover_line(NSString *text, double limit, double *width) {
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName: @YES,
    };
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    if (!line) return NULL;
    WittyHoverLine *result = calloc(1, sizeof(*result));
    if (!result) {
        CFRelease(line);
        return NULL;
    }
    result->core_text = line;
    *width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    if (*width <= limit) return result;

    NSMutableDictionary *token_attributes = [attributes mutableCopy];
    token_attributes[witty_hover_ellipsis_attribute] = @YES;
    NSAttributedString *ellipsis = [[NSAttributedString alloc] initWithString:@"…" attributes:token_attributes];
    [token_attributes release];
    CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)ellipsis);
    [ellipsis release];
    CTLineRef truncated = NULL;
    if (token) {
        const bool left_to_right = witty_hover_line_is_left_to_right(line);
        if (@available(macOS 12.0, *)) {
            const double token_width = CTLineGetTypographicBounds(token, NULL, NULL, NULL);
            if (token_width <= limit) {
                NSTextLineFragment *fragment = witty_hover_layout_fragment(text, attributes, limit, nil, NULL);
                if (left_to_right) {
                    truncated = witty_hover_line_from_fragment(text, attributes, fragment, token, limit, width);
                } else if (fragment && fragment.typographicBounds.size.width > 0 && fragment.typographicBounds.size.width <= limit) {
                    // The laid-out fragment preserves joining and ellipsis placement.
                    if (witty_hover_line_has_color(line)) {
                        witty_hover_set_fragment_colors(result, fragment, text, attributes, limit, token_width);
                    } else {
                        result->fragment = [fragment retain];
                    }
                    if (result->fragment) *width = fragment.typographicBounds.size.width;
                }
                [fragment release];
                if (truncated || result->fragment) {
                    CFRelease(token);
                    if (result->color_count == 0) {
                        CFRelease(line);
                        result->core_text = truncated;
                    }
                    return result;
                }
            }
        }
        truncated = CTLineCreateTruncatedLine(line, limit, kCTLineTruncationMiddle, token);
        if (truncated && left_to_right) {
            CTLineRef refined = witty_hover_refine_truncation(text, attributes, line, truncated, token, limit);
            if (refined) {
                CFRelease(truncated);
                truncated = refined;
            }
        }
        CFRelease(token);
    }
    if (!truncated) {
        // Use the offered width and clip the original line when the ellipsis cannot fit.
        *width = limit;
        return result;
    }
    CFRelease(line);
    *width = CTLineGetTypographicBounds(truncated, NULL, NULL, NULL);
    result->core_text = truncated;
    return result;
}

static inline bool witty_hover_rasterize_circular_corner(uint32_t *pixels, int width, int height,
        double radius, bool round_left) {
    const CGRect bounds = CGRectMake(0, 0, width, height);
    CGContextRef context = witty_canvas_bitmap_context(pixels, width, height, bounds);
    if (!context) return false;
    if (round_left) {
        CGContextTranslateCTM(context, width, 0);
        CGContextScaleCTM(context, -1, 1);
    }
    CGContextMoveToPoint(context, 0, 0);
    CGContextAddLineToPoint(context, width, 0);
    CGContextAddLineToPoint(context, width, height - radius);
    CGContextAddArc(context, width - radius, height - radius, radius, 0, M_PI_2, false);
    CGContextAddLineToPoint(context, 0, height);
    CGContextClosePath(context);
    CGContextFillPath(context);
    CGContextRelease(context);
    return true;
}

static inline int witty_hover_backing_phases(NSView *view) {
    NSWindow *window = view.window;
    if (!window) return 0;
    const NSRect bounds = [window convertRectToBacking:[view convertRect:view.bounds toView:nil]];
    const NSRect frame = [window convertRectToBacking:[window convertRectFromScreen:window.frame]];
    const long left = lround(CGRectGetMinX(bounds));
    const long right = lround(CGRectGetMaxX(bounds));
    const long top = lround(CGRectGetMaxY(frame) - CGRectGetMaxY(bounds));
    const long bottom = lround(CGRectGetMaxY(frame) - CGRectGetMinY(bounds));
    return (left & 1) | ((right & 1) << 1) | ((top & 1) << 2) | ((bottom & 1) << 3);
}

static inline NSAppearance *witty_hover_appearance(NSView *view) {
    // The scroll view can use a different appearance for its scrollbar.
    return view.window.effectiveAppearance ?: view.effectiveAppearance;
}

static inline void witty_hover_draw_background(CGContextRef target, NSView *view, const CGRect *bounds,
        const uint32_t *pixels, int width, int height) {
    CGImageRef mask = witty_canvas_make_text_mask(pixels, width, height);
    if (!mask) return;
    CGContextSaveGState(target);
    CGContextSetInterpolationQuality(target, kCGInterpolationNone);
    CGContextClipToMask(target, *bounds, mask);
    [witty_hover_appearance(view) performAsCurrentDrawingAppearance:^{
        CGContextSetFillColorWithColor(target, [NSColor windowBackgroundColor].CGColor);
    }];
    CGContextFillRect(target, *bounds);
    CGContextRestoreGState(target);
    CGImageRelease(mask);
}

static inline void witty_hover_set_background(NSView *view, CALayer *layer, const CGRect *center,
        const float *coverage, int width, int height, double scale) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.frame = view.bounds;
    [witty_hover_appearance(view) performAsCurrentDrawingAppearance:^{
        layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    }];
    // Core Animation applies the 16-bit coverage to the original opaque tint.
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
    CGImageRef image = witty_canvas_alpha_image(NULL, coverage, width, height, space, 0, 0, 0, 1);
    if (space) CGColorSpaceRelease(space);
    if (image) {
        CALayer *mask = layer.mask;
        if (!mask) {
            mask = [CALayer layer];
            mask.contentsFormat = kCAContentsFormatRGBA16Float;
            mask.minificationFilter = kCAFilterNearest;
            mask.magnificationFilter = kCAFilterNearest;
            layer.mask = mask;
        }
        mask.frame = layer.bounds;
        mask.contentsScale = scale;
        mask.contentsCenter = *center;
        mask.contents = (id)image;
        CGImageRelease(image);
    } else {
        layer.mask = nil;
    }
    [CATransaction commit];
}

API_AVAILABLE(macos(12.0))
static inline void witty_hover_draw_fragment(CGContextRef target, NSTextLineFragment *fragment, NSColor *tint,
        WittyCanvasTextLayout layout, uint32_t *pixels, int width, int height) {
    CGContextRef context = witty_canvas_bitmap_context_in_space(pixels, width, height, layout.bounds,
        layout.bitmap_color_space ?: kCGColorSpaceDisplayP3);
    if (!context) return;
    NSColor *paint = [tint colorWithAlphaComponent:1];
    const CGPoint origin = fragment.glyphOrigin;
    CGContextClipToRect(context, layout.clip);
    CGContextSetFillColorWithColor(context, paint.CGColor);
    CGContextTranslateCTM(context, layout.position.x - origin.x, layout.position.y + origin.y);
    CGContextScaleCTM(context, 1, -1);
    [fragment drawAtPoint:CGPointZero inContext:context];

    const double opacity = CGColorGetAlpha(tint.CGColor);
    const bool round_coverage = layout.ink_rounding != WittyCanvasNativeInk && opacity < 1;
    if (round_coverage) witty_canvas_round_text_coverage(pixels, (size_t)width * height, opacity, layout.ink_rounding);
    if (CGBitmapContextGetBitsPerComponent(target) && round_coverage) {
        CGImageRef image = CGBitmapContextCreateImage(context);
        if (image) {
            witty_canvas_present_oriented_image(target, image, &layout.bounds, false);
            CGImageRelease(image);
        }
    } else {
        CGImageRef mask = witty_canvas_make_text_mask(pixels, width, height);
        if (mask) {
            CGContextSaveGState(target);
            CGContextSetInterpolationQuality(target, kCGInterpolationNone);
            CGContextClipToMask(target, layout.bounds, mask);
            CGContextSetFillColorWithColor(target, (round_coverage ? paint : tint).CGColor);
            CGContextFillRect(target, layout.bounds);
            CGContextRestoreGState(target);
            CGImageRelease(mask);
        }
    }
    CGContextRelease(context);
}

static inline void witty_hover_draw_fragment_colors(CGContextRef target, WittyHoverLine *line, NSColor *tint,
        WittyCanvasTextLayout layout, uint32_t *pixels, int width, int height) {
    const double x = layout.position.x;
    const double y = layout.position.y + layout.color_baseline_offset;
    const bool live = CGBitmapContextGetBitsPerComponent(target) == 0;
    CGContextRef context = NULL;
    for (size_t i = 0; i < line->color_count; ++i) {
        const WittyHoverColorGlyph glyph = line->color_glyphs[i];
        const CFRange range = CFRangeMake(glyph.index, 1);
        CTFontRef font = CFDictionaryGetValue(CTRunGetAttributes(glyph.run), kCTFontAttributeName);
        if (live) {
            CGContextSaveGState(target);
            CGContextClipToRect(target, layout.clip);
            CGContextSetTextMatrix(target, CGAffineTransformIdentity);
            CGContextSetTextPosition(target, x, y);
            const bool drawn = witty_canvas_draw_color_glyph_range(target, glyph.run, font, range,
                layout.fit_color_glyphs_to_backing, glyph.x_offset, glyph.right_to_left);
            CGContextRestoreGState(target);
            if (drawn) continue;
        }
        if (!context) {
            context = witty_canvas_bitmap_context_in_space(pixels, width, height, layout.bounds,
                layout.bitmap_color_space ?: kCGColorSpaceDisplayP3);
            if (!context) return;
            CGContextSetFillColorWithColor(context, tint.CGColor);
            CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        }
        CGContextClearRect(context, layout.bounds);
        CGContextSaveGState(context);
        CGContextClipToRect(context, layout.clip);
        bool drawn = false;
        if (glyph.right_to_left) {
            CGContextSetTextPosition(context, x, y);
            drawn = witty_canvas_draw_color_glyph_range(context, glyph.run, font, range,
                layout.fit_color_glyphs_to_backing, glyph.x_offset, true);
        }
        if (!drawn) {
            CGContextSetTextPosition(context, 0, 0);
            CGPoint position;
            CGGlyph code;
            CTRunGetPositions(glyph.run, range, &position);
            CTRunGetGlyphs(glyph.run, range, &code);
            // Pass the placed glyph position to avoid a second snap at the run origin.
            position.x += x + glyph.x_offset;
            position.y += y;
            CTFontDrawGlyphs(font, &code, &position, 1, context);
        }
        CGContextRestoreGState(context);
        CGImageRef image = CGBitmapContextCreateImage(context);
        if (image) {
            witty_canvas_present_oriented_image(target, image, &layout.bounds, false);
            CGImageRelease(image);
        }
    }
    if (context) CGContextRelease(context);
}

static inline void witty_hover_draw_line(CGContextRef target, WittyHoverLine *line, NSView *view,
        const CGRect *bounds, uint32_t *pixels, int width, int height, double padding, double baseline) {
    // Cached mixed-color previews use an sRGB bitmap. Live previews apply label opacity in the compositor.
    const bool mixed_color = line->fragment ? line->color_count != 0 : witty_hover_line_has_color(line->core_text);
    const bool bitmap_target = CGBitmapContextGetBitsPerComponent(target) != 0;
    const WittyCanvasTextLayout layout = {
        .bounds = *bounds,
        .clip = CGRectInset(*bounds, padding, 0),
        .position = CGPointMake(bounds->origin.x + padding, bounds->origin.y + baseline),
        .color_baseline_offset = -0.5,
        .bitmap_color_space = mixed_color && bitmap_target ? kCGColorSpaceSRGB : NULL,
        .ink_rounding = !mixed_color ? WittyCanvasRoundInkUp :
            (bitmap_target ? WittyCanvasRoundInkNearest : WittyCanvasNativeInk),
        .fit_color_glyphs_to_backing = true,
    };
    [witty_hover_appearance(view) performAsCurrentDrawingAppearance:^{
        if (@available(macOS 12.0, *)) {
            if (line->fragment) {
                NSColor *tint = NSColor.labelColor;
                witty_hover_draw_fragment(target, line->fragment, tint, layout, pixels, width, height);
                witty_hover_draw_fragment_colors(target, line, tint, layout, pixels, width, height);
                return;
            }
        }
        witty_canvas_draw_text_runs(target, line->core_text, NSColor.labelColor, layout, pixels, width, height);
    }];
}
#endif
