#ifndef WITTY_ACTION_PALETTE_ROW_DARWIN_H
#define WITTY_ACTION_PALETTE_ROW_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>
#include <CoreText/CoreText.h>

static inline void witty_palette_set_search_prompt(NSTextField *field, NSString *prompt) {
    [field.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *color = [[NSColor placeholderTextColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (!color) return;
        // Match the SwiftUI prompt's opacity in the palette.
        double transparency = 1 - color.alphaComponent;
        NSColor *ink = [color colorWithAlphaComponent:1 - transparency * transparency];
        NSAttributedString *value = [[NSAttributedString alloc] initWithString:prompt
            attributes:@{NSForegroundColorAttributeName:ink, NSFontAttributeName:field.font}];
        field.placeholderAttributedString = value;
        [value release];
    }];
}

static inline void witty_palette_draw_swatch(CGContextRef context, const CGRect *rect, CGImageRef mask,
        NSColor *color) {
    CGContextSaveGState(context);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextClipToMask(context, *rect, mask);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, *rect);
    CGContextRestoreGState(context);
}

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

static inline void witty_palette_draw_matched_text(CGContextRef context, NSString *text, NSColor *color,
        NSArray<NSValue *> *matches, NSColor *accent,
        double size, bool medium, double x, double baseline, double width, double height) {
    if (width <= 0 || text.length == 0) return;
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
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) > width) {
        CTLineRef token = witty_palette_row_line(@"…", attrs);
        CTLineRef truncated = token ? CTLineCreateTruncatedLine(line, width, kCTLineTruncationEnd, token) : NULL;
        if (token) CFRelease(token);
        CFRelease(line);
        line = truncated;
        if (!line) return;
    }
    CGContextSaveGState(context);
    CGContextClipToRect(context, CGRectMake(x, 0, width, height));
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
        CTFontRef font = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
        // SwiftUI positions the color emoji fallback half a point lower.
        bool colorGlyphs = font && (CTFontGetSymbolicTraits(font) & kCTFontColorGlyphsTrait);
        CGContextSaveGState(context);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, x, height - baseline - (colorGlyphs ? 0.5 : 0));
        CTRunDraw(run, context, CFRangeMake(0, 0));
        CGContextRestoreGState(context);
    }
    CGContextRestoreGState(context);
    CFRelease(line);
}

static inline void witty_palette_draw_row_text(CGContextRef context, NSString *text, NSColor *color,
        double size, bool medium, double x, double baseline, double width, double height) {
    witty_palette_draw_matched_text(context, text, color, nil, nil, size, medium, x, baseline, width, height);
}

static inline NSImage *witty_palette_row_symbol(NSString *name) {
    NSImage *symbol = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    NSImageSymbolConfiguration *font = [NSImageSymbolConfiguration configurationWithPointSize:14
        weight:NSFontWeightMedium];
    return [symbol imageWithSymbolConfiguration:[font configurationByApplyingConfiguration:
        [NSImageSymbolConfiguration configurationPreferringMonochrome]]];
}

static inline double witty_palette_draw_row_symbol(CGContextRef context, NSString *name, CGImageRef tint,
        double x, double height) {
    NSImage *symbol = witty_palette_row_symbol(name);
    if (!symbol) return 0;
    NSRect alignment = symbol.alignmentRect;
    NSRect rect = NSMakeRect(x - alignment.origin.x,
        (height + alignment.size.height) / 2 + alignment.origin.y - symbol.size.height,
        symbol.size.width, symbol.size.height);
    CGContextSaveGState(context);
    CGContextBeginTransparencyLayer(context, NULL);
    [symbol drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
        fraction:1 respectFlipped:YES hints:nil];
    CGContextSetBlendMode(context, kCGBlendModeSourceIn);
    CGContextDrawImage(context, rect, tint);
    CGContextEndTransparencyLayer(context);
    CGContextRestoreGState(context);
    return alignment.size.width;
}
#endif

#endif
