#include "canvas_text_darwin.h"

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#import <objc/runtime.h>

static inline NSColor *witty_search_unfocused_text_color(void) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        __block NSColor *ink;
        [appearance performAsCurrentDrawingAppearance:^{
            ink = NSColor.labelColor;
            CGColorRef color = ink.CGColor;
            if (CGColorGetAlpha(color) == 216.0 / 255) {
                // The plain field draws with 85% opacity before AppKit rounds glyph coverage.
                CGColorRef precise = CGColorCreateCopyWithAlpha(color, 0.85f);
                if (precise) {
                    ink = [NSColor colorWithCGColor:precise];
                    CGColorRelease(precise);
                }
            }
        }];
        return ink;
    }];
}

@interface WittySearchFieldCell : NSTextFieldCell
@end

@implementation WittySearchFieldCell

- (NSTextView *)fieldEditorForView:(NSView *)view {
    static char editorKey;
    NSTextView *editor = objc_getAssociatedObject(view, &editorKey);
    if (!editor) {
        // Find's selection style belongs to this control's field editor.
        editor = [NSTextView textViewUsingTextLayoutManager:YES];
        editor.fieldEditor = YES;
        objc_setAssociatedObject(view, &editorKey, editor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return editor;
}

- (NSText *)setUpFieldEditorAttributes:(NSText *)text {
    self.textColor = NSColor.labelColor;
    NSText *editor = [super setUpFieldEditorAttributes:text];
    if ([editor isKindOfClass:NSTextView.class]) {
        NSTextView *view = (NSTextView *)editor;
        NSMutableDictionary *selection = [view.selectedTextAttributes mutableCopy];
        selection[NSForegroundColorAttributeName] = self.textColor;
        view.selectedTextAttributes = selection;
        [selection release];
    }
    return editor;
}

- (void)endEditing:(NSText *)text {
    [super endEditing:text];
    self.textColor = witty_search_unfocused_text_color();
}

@end

static inline NSPasteboard *witty_search_find_pasteboard(void) {
    return [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
}

static inline void witty_search_configure_editor(NSTextField *field) {
    WittySearchFieldCell *cell = [[WittySearchFieldCell alloc] initTextCell:@""];
    field.cell = cell;
    [cell release];
    field.editable = YES;
    field.selectable = YES;
    field.bordered = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = [NSFont systemFontOfSize:13];
    field.textColor = witty_search_unfocused_text_color();
    field.placeholderString = @"Search";
    field.cell.usesSingleLineMode = YES;
    field.cell.scrollable = YES;
}

static inline void witty_search_configure_shadow(NSView *bar) {
    // Apply the shadow to the composited Canvas silhouette at presentation scale.
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0.33];
    shadow.shadowBlurRadius = 4;
    shadow.shadowOffset = CGSizeZero;
    bar.shadow = shadow;
    [shadow release];
}

static inline void witty_search_panel_colors(NSView *bar, NSView *plate, NSView *field) {
    NSAppearance *appearance = bar.window.effectiveAppearance ?: bar.effectiveAppearance;
    if (![bar.appearance isEqual:appearance]) {
        bar.appearance = appearance;
        for (NSView *child in bar.subviews) child.needsDisplay = YES;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    plate.layer.cornerCurve = kCACornerCurveContinuous;
    plate.layer.cornerRadius = 8;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.layer.cornerRadius = 6;
    [appearance performAsCurrentDrawingAppearance:^{
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

static inline CALayer *witty_search_button_layer(CALayer *host, NSString *name) {
    for (CALayer *layer in host.sublayers) {
        if ([layer.name isEqualToString:name]) return layer;
    }
    return nil;
}

static inline void witty_search_present_symbol(NSView *view, const CGRect *bounds,
        const uint32_t *pixels, int width, int height, bool active) {
    CALayer *host = view.layer;
    if (!host) return;
    CALayer *ink = witty_search_button_layer(host, @"WittySearchSymbol");

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!ink) {
        ink = [CALayer layer];
        ink.name = @"WittySearchSymbol";
        [host addSublayer:ink];
    }
    CGRect frame = *bounds;
    if (view.isFlipped != host.geometryFlipped) {
        frame.origin.y = CGRectGetMinY(view.bounds) + CGRectGetMaxY(view.bounds) - CGRectGetMaxY(frame);
    }
    ink.frame = frame;
    witty_canvas_set_layer_mask(ink, pixels, width, height, width / bounds->size.width);
    // Resolve the original tint on the compositor layer so the glyph blends once.
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        ink.backgroundColor = (active ? NSColor.labelColor : NSColor.secondaryLabelColor).CGColor;
    }];
    [CATransaction commit];
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

static inline void witty_search_fill_button(NSView *view, bool active, bool pressed) {
    CALayer *host = view.layer;
    if (!host) return;
    CALayer *fill = witty_search_button_layer(host, @"WittySearchButtonFill");
    if (!fill && !active) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!fill) {
        fill = [CALayer layer];
        fill.name = @"WittySearchButtonFill";
        fill.cornerCurve = kCACornerCurveContinuous;
        fill.cornerRadius = 6;
        [host insertSublayer:fill atIndex:0];
    }
    fill.hidden = !active;
    if (active) {
        fill.frame = host.bounds;
        [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
            NSColor *ink = [NSColor.labelColor colorUsingColorSpace:NSColorSpace.extendedSRGBColorSpace];
            if (ink) witty_canvas_set_layer_srgb_fill(fill, ink.redComponent, ink.greenComponent,
                ink.blueComponent, ink.alphaComponent * (pressed ? 0.2 : 0.1));
        }];
    }
    [CATransaction commit];
}
#endif
