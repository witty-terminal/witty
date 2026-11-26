#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_text_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static NSString *const witty_hover_ellipsis_attribute = @"WittyHoverEllipsis";

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

static inline CTLineRef witty_hover_layout_truncation(NSString *text, NSDictionary *attributes,
        CTLineRef token, double limit, double *width) {
    if (@available(macOS 12.0, *)) {
        if (CTLineGetTypographicBounds(token, NULL, NULL, NULL) > limit) return NULL;
        @autoreleasepool {
            NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
            style.lineBreakMode = NSLineBreakByTruncatingMiddle;
            style.allowsDefaultTighteningForTruncation = NO;
            NSMutableDictionary *layout_attributes = [[attributes mutableCopy] autorelease];
            layout_attributes[NSParagraphStyleAttributeName] = style;
            NSTextContentStorage *content = [[[NSTextContentStorage alloc] init] autorelease];
            content.attributedString = [[[NSAttributedString alloc] initWithString:text
                attributes:layout_attributes] autorelease];
            NSTextLayoutManager *layout = [[[NSTextLayoutManager alloc] init] autorelease];
            [content addTextLayoutManager:layout];
            NSTextContainer *container = [[[NSTextContainer alloc] initWithSize:NSMakeSize(limit, CGFLOAT_MAX)] autorelease];
            container.maximumNumberOfLines = 1;
            container.lineFragmentPadding = 0;
            container.lineBreakMode = NSLineBreakByTruncatingMiddle;
            layout.textContainer = container;
            NSTextRange *range = layout.documentRange;
            [layout ensureLayoutForRange:range];
            __block CTLineRef line = NULL;
            [layout enumerateTextLayoutFragmentsFromLocation:range.location
                options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout usingBlock:^BOOL(NSTextLayoutFragment *fragment) {
                    line = witty_hover_line_from_fragment(text, attributes, fragment.textLineFragments.firstObject, token,
                        limit, width);
                    return NO;
                }];
            return line;
        }
    }
    return NULL;
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

static inline CTLineRef witty_hover_line(NSString *text, double limit, double *width) {
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName: @YES,
    };
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    if (!line) return NULL;
    *width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    if (*width <= limit) return line;

    NSMutableDictionary *token_attributes = [attributes mutableCopy];
    token_attributes[witty_hover_ellipsis_attribute] = @YES;
    NSAttributedString *ellipsis = [[NSAttributedString alloc] initWithString:@"…" attributes:token_attributes];
    [token_attributes release];
    CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)ellipsis);
    [ellipsis release];
    CTLineRef truncated = NULL;
    if (token) {
        // Preserve Core Text's ordering for bidirectional runs.
        const bool left_to_right = witty_hover_line_is_left_to_right(line);
        if (left_to_right) truncated = witty_hover_layout_truncation(text, attributes, token, limit, width);
        if (truncated) {
            CFRelease(line);
            CFRelease(token);
            return truncated;
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
        return line;
    }
    CFRelease(line);
    *width = CTLineGetTypographicBounds(truncated, NULL, NULL, NULL);
    return truncated;
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

static inline void witty_hover_draw_background(CGContextRef target, NSView *view, const CGRect *bounds,
        const uint32_t *pixels, int width, int height) {
    CGImageRef mask = witty_canvas_make_text_mask(pixels, width, height);
    if (!mask) return;
    CGContextSaveGState(target);
    CGContextSetInterpolationQuality(target, kCGInterpolationNone);
    CGContextClipToMask(target, *bounds, mask);
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
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
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
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

static inline void witty_hover_draw_line(CGContextRef target, CTLineRef line, NSView *view,
        const CGRect *bounds, uint32_t *pixels, int width, int height, double padding, double baseline) {
    // Cached mixed-color previews use an sRGB bitmap. Live previews apply label opacity in the compositor.
    const bool mixed_color = witty_hover_line_has_color(line);
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
    [[view effectiveAppearance] performAsCurrentDrawingAppearance:^{
        witty_canvas_draw_text_runs(target, line, [NSColor labelColor], layout, pixels, width, height);
    }];
}
#endif
