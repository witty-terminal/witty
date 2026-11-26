#include "canvas_text_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline NSPasteboard *witty_search_find_pasteboard(void) {
    return [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
}

static inline void witty_search_configure_editor(NSTextField *field) {
    field.bordered = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = [NSFont systemFontOfSize:13];
    field.textColor = NSColor.labelColor;
    field.placeholderString = @"Search";
    field.cell.usesSingleLineMode = YES;
    field.cell.scrollable = YES;
}

static inline void witty_search_panel_colors(NSView *bar, NSView *shadow, NSView *plate, NSView *field) {
    NSAppearance *appearance = bar.window.effectiveAppearance ?: bar.effectiveAppearance;
    if (![bar.appearance isEqual:appearance]) {
        bar.appearance = appearance;
        for (NSView *child in bar.subviews) child.needsDisplay = YES;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [appearance performAsCurrentDrawingAppearance:^{
        shadow.layer.backgroundColor = NSColor.blackColor.CGColor;
        plate.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        NSColor *ink = NSColor.labelColor;
        field.layer.backgroundColor = [ink colorWithAlphaComponent:ink.alphaComponent * 0.1].CGColor;
    }];
    [CATransaction commit];
}

static inline void witty_search_configure_button(NSButton *button, NSString *label) {
    button.bordered = NO;
    button.focusRingType = NSFocusRingTypeNone;
    button.accessibilityLabel = label;
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:button userInfo:nil];
    [button addTrackingArea:area];
    [area release];
}

static inline void witty_search_reset_cursor(NSButton *button) {
    [button addCursorRect:button.bounds cursor:NSCursor.pointingHandCursor];
}

static inline double witty_search_symbol_bounds(NSImage *symbol, const CGRect *bounds, CGRect *frame) {
    const NSRect alignment = symbol.alignmentRect;
    const NSSize size = symbol.size;
    *frame = CGRectMake(CGRectGetMidX(*bounds) - alignment.size.width / 2 - alignment.origin.x,
        CGRectGetMidY(*bounds) - size.height / 2, size.width, size.height);
    return alignment.size.width;
}

static inline void witty_search_draw_count(CGContextRef target, NSTextField *view, const CGRect *bounds,
        uint32_t *pixels, int width, int height) {
    if (!view.stringValue.length) return;
    NSFont *font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular];
    NSDictionary *attributes = @{NSFontAttributeName:font,
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName:@YES};
    CTLineRef line = witty_canvas_text_line(view.stringValue, attributes);
    if (!line) return;
    const double scale = height / bounds->size.height;
    const double x = CGRectGetMaxX(*bounds) - 8 - CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    const double y = CGRectGetMidY(*bounds) - (round(font.ascender) + floor(font.descender)) / 2;
    const WittyCanvasTextLayout layout = {.bounds = *bounds, .clip = *bounds, .flipped = view.isFlipped,
        .position = CGPointMake(round(x * scale) / scale, round(y * scale) / scale),
        .ink_rounding = WittyCanvasRoundInkUp};
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        witty_canvas_draw_text_runs(target, line, NSColor.secondaryLabelColor, layout, pixels, width, height);
    }];
    CFRelease(line);
}

static inline void witty_search_fill_button(CGContextRef target, NSView *view, const CGRect *bounds,
        const uint32_t *pixels, int width, int height, bool pressed) {
    CGImageRef mask = witty_canvas_make_text_mask(pixels, width, height);
    if (!mask) return;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *ink = NSColor.labelColor;
        NSColor *color = [ink colorWithAlphaComponent:ink.alphaComponent * (pressed ? 0.2 : 0.1)];
        witty_canvas_present_text_mask(target, mask, bounds, color, view.isFlipped);
    }];
    CGImageRelease(mask);
}
#endif
