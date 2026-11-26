#ifndef WITTY_ACTION_PALETTE_ROW_DARWIN_H
#define WITTY_ACTION_PALETTE_ROW_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>
#include "canvas_overlay_darwin.h"

static inline NSFont *witty_palette_row_font(double size, bool medium) {
    return [NSFont systemFontOfSize:size weight:(medium ? NSFontWeightMedium : NSFontWeightRegular)];
}

static inline double witty_palette_row_text_width(NSString *text, double size, bool medium) {
    return [text sizeWithAttributes:@{NSFontAttributeName: witty_palette_row_font(size, medium)}].width;
}

static inline CTLineRef witty_palette_row_line(NSString *text, NSDictionary *attributes) {
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    return line;
}

static inline NSArray<NSValue *> *witty_palette_match_ranges(NSString *text, NSString *query) {
    if (query.length == 0 || text.length == 0) return nil;
    NSRange found = [text rangeOfString:query options:NSCaseInsensitiveSearch];
    if (found.location != NSNotFound) {
        return @[[NSValue valueWithRange:[text rangeOfComposedCharacterSequencesForRange:found]]];
    }

    NSMutableArray<NSValue *> *matches = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    __block NSUInteger offset = 0;
    __block BOOL wordStart = YES;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
        options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *grapheme, NSRange range, NSRange enclosing, BOOL *stop) {
            if ([grapheme rangeOfCharacterFromSet:whitespace].location != NSNotFound) {
                wordStart = YES;
                return;
            }
            if (!wordStart) return;
            wordStart = NO;
            NSRange next = [query rangeOfComposedCharacterSequenceAtIndex:offset];
            NSString *initial = [query substringWithRange:next];
            if ([grapheme.lowercaseString compare:initial.lowercaseString] == NSOrderedSame) {
                [matches addObject:[NSValue valueWithRange:range]];
                offset = NSMaxRange(next);
                *stop = offset == query.length;
            }
        }];
    return offset == query.length ? matches : nil;
}

static inline void witty_palette_draw_canvas_text(CGContextRef target, NSString *text, NSColor *color,
        NSArray<NSValue *> *matches, NSColor *accent,
        double size, bool medium, double baseline, const CGRect *clip, const CGRect *bounds,
        uint32_t *pixels, int width, int height) {
    if (text.length == 0) return;
    NSRange newline = [text rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
    NSRange visible = NSMakeRange(0, text.length);
    if (newline.location != NSNotFound) {
        visible.length = newline.location;
        text = [[text substringToIndex:newline.location] stringByAppendingString:@"…"];
    }
    NSDictionary *attrs = @{NSFontAttributeName:witty_palette_row_font(size, medium),
        NSForegroundColorAttributeName:color};
    CTLineRef line;
    if (matches.count > 0) {
        NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text attributes:attrs];
        // SwiftUI resolves the emphasized caption and body weights differently.
        NSFontWeight weight = size == 10 ? NSFontWeightMedium : NSFontWeightSemibold;
        NSDictionary *highlight = @{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight],
            NSForegroundColorAttributeName:accent};
        for (NSValue *value in matches) {
            NSRange span = NSIntersectionRange(value.rangeValue, visible);
            if (span.length > 0) [attributed addAttributes:highlight range:span];
        }
        line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
        [attributed release];
    } else {
        line = witty_palette_row_line(text, attrs);
    }
    if (!line) return;
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) > clip->size.width) {
        CTLineRef token = witty_palette_row_line(@"…", attrs);
        CTLineRef truncated = token
            ? CTLineCreateTruncatedLine(line, clip->size.width, kCTLineTruncationEnd, token) : NULL;
        if (token) CFRelease(token);
        CFRelease(line);
        line = truncated;
        if (!line) return;
    }
    // The button and empty-message views use flipped coordinates. In the
    // y-up raster, the line baseline is measured from the bottom of the view.
    CGRect frame = *bounds;
    frame.origin.y = clip->size.height - CGRectGetMaxY(frame);
    CGContextRef context = witty_canvas_text_context(pixels, width, height, frame);
    if (!context) {
        CFRelease(line);
        return;
    }
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
        CTFontRef font = (CTFontRef)attributes[(id)kCTFontAttributeName];
        // SwiftUI positions the color emoji fallback half a point lower.
        bool colorGlyphs = font && (CTFontGetSymbolicTraits(font) & kCTFontColorGlyphsTrait);
        NSColor *tint = attributes[NSForegroundColorAttributeName];
        bool mask = !colorGlyphs && tint && CGColorGetAlpha(tint.CGColor) == 1;

        CGContextSaveGState(context);
        CGContextClipToRect(context, *clip);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, clip->origin.x,
            clip->size.height - baseline - (colorGlyphs ? 0.5 : 0));
        CTRunDraw(run, context, CFRangeMake(0, 0));
        CGContextRestoreGState(context);

        // Present opaque system colors at their original precision. Bitmap
        // emoji and translucent colors keep their premultiplied RGBA pixels.
        CGImageRef image = mask ? witty_canvas_make_text_mask(pixels, width, height)
            : CGBitmapContextCreateImage(context);
        if (image) {
            if (mask) witty_canvas_present_text_mask(target, image, bounds, tint, true);
            else witty_canvas_present_oriented_image(target, image, bounds, true);
            CGImageRelease(image);
        }
        CGContextClearRect(context, frame);
    }
    CFRelease(line);
    CGContextRelease(context);
}

static inline NSImage *witty_palette_row_symbol(NSString *name, double x, double height,
        CGRect *frame, double *width) {
    NSImage *symbol = witty_canvas_system_symbol(name, 14, NSFontWeightMedium);
    if (!symbol) return nil;
    NSRect alignment = symbol.alignmentRect;
    *frame = CGRectMake(x - alignment.origin.x,
        (height + alignment.size.height) / 2 + alignment.origin.y - symbol.size.height,
        symbol.size.width, symbol.size.height);
    *width = alignment.size.width;
    return symbol;
}
#endif

#endif
