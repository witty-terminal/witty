#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/ev_keymap.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static NSView *terminal_view(NSView *view, BOOL ghostty) {
    if (!view) return nil;
    if ([NSStringFromClass(view.class) isEqualToString:@"VTTerminalView"]) return view;
    if (ghostty && [NSStringFromClass(view.layer.class) isEqualToString:@"IOSurfaceLayer"]) return view;
    for (NSView *child in view.subviews) {
        NSView *terminal = terminal_view(child, ghostty);
        if (terminal) return terminal;
    }
    return nil;
}

static void send_key_sequence(NSView *view, NSArray<NSString *> *keys, NSUInteger index, NSString *config_path) {
    if (index == keys.count) {
        fprintf(stderr, "macOS render probe dispatched input\n");
        return;
    }
    NSString *key = keys[index];
    if (config_path && [key isEqualToString:@"f7"]) {
        NSString *stage = [config_path stringByAppendingFormat:@".%lu", (unsigned long)index + 1];
        NSData *settings = [NSData dataWithContentsOfFile:stage];
        if (![settings writeToFile:config_path atomically:YES]) {
            fprintf(stderr, "macOS render probe could not install staged config %s\n", stage.fileSystemRepresentation);
            exit(EXIT_FAILURE);
        }
    }
    static const struct {
        const char *name;
        unichar character;
        unsigned short code;
    } inputs[] = {
        {"f7", NSF7FunctionKey, kVK_F7},
        {"f8", NSF8FunctionKey, kVK_F8},
        {"f9", NSF9FunctionKey, kVK_F9},
        {"f10", NSF10FunctionKey, kVK_F10},
        {"f11", NSF11FunctionKey, kVK_F11},
        {"space", ' ', kVK_Space},
    };
    for (size_t i = 0; i < sizeof(inputs) / sizeof(inputs[0]); ++i) {
        if (strcmp(key.UTF8String, inputs[i].name) != 0) continue;
        NSString *characters = [NSString stringWithCharacters:&inputs[i].character length:1];
        for (int released = 0; released <= 1; ++released) {
            NSEvent *event = [NSEvent keyEventWithType:released ? NSEventTypeKeyUp : NSEventTypeKeyDown
                location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                windowNumber:view.window.windowNumber context:nil characters:characters
                charactersIgnoringModifiers:characters isARepeat:NO keyCode:inputs[i].code];
            if (released) [view keyUp:event];
            else [view keyDown:event];
        }
        // Let terminal actions update the viewport before the next binding.
        int delay_ms = config_path ? 450 : 350;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
            dispatch_get_main_queue(), ^{ send_key_sequence(view, keys, index + 1, config_path); });
        return;
    }
    fprintf(stderr, "macOS render probe does not support key %s\n", key.UTF8String);
    exit(EXIT_FAILURE);
}

static NSPoint terminal_point(NSView *view, double x, double y) {
    const NSRect bounds = view.bounds;
    return NSMakePoint(NSMinX(bounds) + x * NSWidth(bounds),
        NSMinY(bounds) + (view.isFlipped ? y : 1 - y) * NSHeight(bounds));
}

static void send_mouse_drag(NSView *view, const char *drag, NSEventModifierFlags modifiers) {
    double coords[4];
    char trailing;
    if (sscanf(drag, "%lf,%lf,%lf,%lf%c", &coords[0], &coords[1], &coords[2], &coords[3], &trailing) != 4) {
        fprintf(stderr, "macOS render probe expected four mouse coordinates\n");
        exit(EXIT_FAILURE);
    }
    for (size_t i = 0; i < 4; ++i) {
        if (!isfinite(coords[i]) || coords[i] < 0 || coords[i] >= 1) {
            fprintf(stderr, "macOS render probe expected mouse coordinates inside the terminal\n");
            exit(EXIT_FAILURE);
        }
    }

    const NSPoint start = terminal_point(view, coords[0], coords[1]);
    const NSPoint end = terminal_point(view, coords[2], coords[3]);
    const NSEventType events[] = {
        NSEventTypeMouseMoved, NSEventTypeLeftMouseDown, NSEventTypeLeftMouseDragged, NSEventTypeLeftMouseUp,
    };
    for (int i = 0; i < 4; ++i) {
        const NSEventType type = events[i];
        const NSPoint location = [view convertPoint:i < 2 ? start : end toView:nil];
        const BOOL pressed = type == NSEventTypeLeftMouseDown || type == NSEventTypeLeftMouseDragged;
        NSEvent *event = [NSEvent mouseEventWithType:type location:location modifierFlags:modifiers
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber
            context:nil eventNumber:i clickCount:type == NSEventTypeMouseMoved ? 0 : 1 pressure:pressed ? 1 : 0];
        switch (type) {
            case NSEventTypeMouseMoved: [view mouseMoved:event]; break;
            case NSEventTypeLeftMouseDown: [view mouseDown:event]; break;
            case NSEventTypeLeftMouseDragged: [view mouseDragged:event]; break;
            case NSEventTypeLeftMouseUp: [view mouseUp:event]; break;
            default: break;
        }
    }
    fprintf(stderr, "macOS render probe dispatched input\n");
}

static void resize_window(NSView *view, const char *size) {
    int width, height;
    char trailing;
    if (sscanf(size, "%dx%d%c", &width, &height, &trailing) != 2 || width <= 0 || height <= 0) {
        fprintf(stderr, "macOS render probe expected positive window width and height\n");
        exit(EXIT_FAILURE);
    }
    [view.window setContentSize:NSMakeSize(width, height)];
    [view.window.contentView layoutSubtreeIfNeeded];
    fprintf(stderr, "macOS render probe dispatched input\n");
}

static bool capture_window_frame(NSView *view, NSString *prefix, NSString *state) {
    // The window server image includes the terminal and composited overlays.
    typedef CGImageRef (*WindowImage)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);
    WindowImage snapshot = (WindowImage)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
    NSWindow *window = view.window;
    CGImageRef shot = snapshot ? snapshot(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)window.windowNumber, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution) : NULL;
    if (!shot) return false;

    NSRect screen = [window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
    double scale = window.backingScaleFactor;
    CGRect crop = CGRectMake(lround((NSMinX(screen) - NSMinX(window.frame)) * scale),
        lround((NSMaxY(window.frame) - NSMaxY(screen)) * scale),
        lround(NSWidth(screen) * scale), lround(NSHeight(screen) * scale));
    CGImageRef image = CGImageCreateWithImageInRect(shot, crop);
    CGImageRelease(shot);
    if (!image) return false;
    NSBitmapImageRep *pixels = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    NSString *path = [NSString stringWithFormat:@"%@-%@.png", prefix, state];
    return [[pixels representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static NSEvent *move_pointer(NSView *view, double x, double y, NSEventModifierFlags modifiers) {
    NSPoint point = [view convertPoint:terminal_point(view, x, y) toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:point
        modifierFlags:modifiers timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber
        context:nil eventNumber:0 clickCount:0 pressure:0];
    [view mouseMoved:event];
    return event;
}

static NSEvent *tracking_event(NSEvent *motion, bool inside) {
    return [NSEvent enterExitEventWithType:inside ? NSEventTypeMouseEntered : NSEventTypeMouseExited
        location:motion.locationInWindow modifierFlags:motion.modifierFlags timestamp:motion.timestamp
        windowNumber:motion.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
}

static void move_hover_pointer(NSView *view, double y, bool ghostty) {
    NSEvent *motion = move_pointer(view, .067, y, NSEventModifierFlagCommand);
    // The probe drives tracking in the launched app without moving the desktop pointer.
    if (ghostty) {
        static bool hosting_entered;
        for (NSView *host = view.superview; host; host = host.superview) {
            if (![NSStringFromClass(host.class) containsString:@"NSHostingView"]) continue;
            if (!hosting_entered) {
                [host mouseEntered:tracking_event(motion, true)];
                hosting_entered = true;
            }
            [host mouseMoved:motion];
            break;
        }
        return;
    }

    static bool inside_preview;
    for (NSView *overlay in view.subviews) {
        if (![NSStringFromClass(overlay.class) isEqualToString:@"WittyActionOverlay"]) continue;
        NSPoint point = [overlay convertPoint:motion.locationInWindow fromView:nil];
        for (NSTrackingArea *area in overlay.trackingAreas) {
            if (!(area.options & NSTrackingMouseEnteredAndExited)) continue;
            bool inside = NSPointInRect(point, area.rect);
            if (inside == inside_preview) continue;
            inside_preview = inside;
            NSEvent *event = tracking_event(motion, inside);
            if (inside) [area.owner mouseEntered:event];
            else [area.owner mouseExited:event];
        }
    }
}

static void send_command_flag(NSView *view, bool pressed) {
    CGEventRef cg = CGEventCreateKeyboardEvent(NULL, kVK_Command, pressed);
    if (!cg) exit(EXIT_FAILURE);
    CGEventSetType(cg, kCGEventFlagsChanged);
    CGEventSetFlags(cg, pressed ? kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK : 0);
    [view flagsChanged:[NSEvent eventWithCGEvent:cg]];
    CFRelease(cg);
}

static void capture_hover(NSView *view, NSString *prefix, BOOL ghostty, NSUInteger step) {
    NSArray<NSString *> *states = @[@"idle", @"hover", @"relocated", @"rethemed", @"returned", @"cleared"];
    if (!capture_window_frame(view, prefix, states[step])) {
        fprintf(stderr, "macOS render probe could not capture the foreground terminal window\n");
        exit(EXIT_FAILURE);
    }
    if (step == 0) {
        // The fixture prints the link on the second row, beginning at the second column.
        move_pointer(view, .065, .10, 0);
        send_command_flag(view, true);
        move_hover_pointer(view, .10, ghostty);
    } else if (step == 1) {
        // The same link on the last row keeps the preview active during relocation.
        move_hover_pointer(view, .97, ghostty);
    } else if (step == 2) {
        NSString *appearance = [view.window.effectiveAppearance bestMatchFromAppearancesWithNames:
            @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        view.window.appearance = [NSAppearance appearanceNamed:
            [appearance isEqualToString:NSAppearanceNameAqua] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    } else if (step == 3) {
        move_hover_pointer(view, .10, ghostty);
    } else if (step == 4) {
        send_command_flag(view, false);
        move_pointer(view, .5, .65, 0);
    } else {
        exit(EXIT_SUCCESS);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 450 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ capture_hover(view, prefix, ghostty, step + 1); });
}

static void wait_for_terminal(NSString *ready, int attempts, BOOL ghostty, void (^dispatch_input)(NSView *)) {
    if (access(ready.fileSystemRepresentation, F_OK) == 0) {
        for (NSWindow *window in NSApplication.sharedApplication.windows) {
            NSView *view = terminal_view(window.contentView, ghostty);
            if (!view) continue;
            // The PTY may still be draining the bytes written before the marker.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC),
                dispatch_get_main_queue(), ^{ dispatch_input(view); });
            return;
        }
    }
    if (attempts <= 0) {
        fprintf(stderr, "macOS render probe timed out waiting for the terminal and its PTY\n");
        exit(EXIT_FAILURE);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ wait_for_terminal(ready, attempts - 1, ghostty, dispatch_input); });
}

static void capture_split(NSWindow *window, NSString *prefix, NSString *ready, BOOL ghostty,
                          NSUInteger step, int attempts) {
    static const struct {
        const char *name;
        const char *next_key;
        unsigned panes_started;
        BOOL left;
        BOOL bottom;
        BOOL full_width;
    } stages[] = {
        {"initial", "f7", 1, YES, NO, YES},
        {"right", "f9", 2, NO, NO, NO},
        {"left", "f8", 2, YES, NO, NO},
        {"nested", "f10", 3, YES, YES, NO},
        {"zoomed", "f10", 3, YES, NO, YES},
        {"unzoomed", "f11", 3, YES, YES, NO},
        {"closed", NULL, 3, YES, NO, NO},
    };
    NSString *marker = [ready stringByAppendingFormat:@"/pane%u.ready", stages[step].panes_started];
    NSView *content = window.contentView;
    id responder = window.firstResponder;
    NSView *view = [responder isKindOfClass:NSView.class] ? responder : nil;
    NSRect area = [content convertRect:content.bounds toView:nil];
    NSRect frame = view ? [view convertRect:view.bounds toView:nil] : NSZeroRect;
    BOOL left = NSMinX(frame) < NSMidX(area) - NSWidth(area) / 4;
    BOOL bottom = NSMaxY(frame) < NSMidY(area) + NSHeight(area) / 4;
    BOOL full_width = NSWidth(frame) > 3 * NSWidth(area) / 4;
    BOOL focused = view && terminal_view(view, ghostty) == view && !view.isHiddenOrHasHiddenAncestor;
    if (!focused || left != stages[step].left || bottom != stages[step].bottom ||
            full_width != stages[step].full_width || access(marker.fileSystemRepresentation, F_OK) != 0) {
        if (attempts <= 0) {
            fprintf(stderr, "macOS render probe timed out waiting for split state %s\n", stages[step].name);
            exit(EXIT_FAILURE);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            capture_split(window, prefix, ready, ghostty, step, attempts - 1);
        });
        return;
    }
    if (!capture_window_frame(content, prefix, [NSString stringWithUTF8String:stages[step].name])) {
        fprintf(stderr, "macOS render probe could not capture split state %s\n", stages[step].name);
        exit(EXIT_FAILURE);
    }
    if (!stages[step].next_key) exit(EXIT_SUCCESS);
    send_key_sequence(view, @[[NSString stringWithUTF8String:stages[step].next_key]], 0, nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        capture_split(window, prefix, ready, ghostty, step + 1, 30);
    });
}

static NSEvent *scroller_event(NSScroller *scroller, NSEventType type, NSPoint location) {
    return [NSEvent mouseEventWithType:type location:[scroller convertPoint:location toView:nil]
        modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
        windowNumber:scroller.window.windowNumber context:nil eventNumber:0 clickCount:1
        pressure:type == NSEventTypeLeftMouseUp ? 0 : 1];
}

static void capture_scrollbar(NSScrollView *scroll, NSString *prefix, NSUInteger step) {
    static NSString *const states[] = {@"middle", @"top", @"bottom"};
    static const double positions[] = {0.5, 0.0, 1.0};
    NSScroller *scroller = scroll.verticalScroller;
    NSRect knob = scroller ? [scroller rectForPart:NSScrollerKnob] : NSZeroRect;
    NSRect slot = scroller ? [scroller rectForPart:NSScrollerKnobSlot] : NSZeroRect;
    const double travel = NSHeight(slot) - NSHeight(knob);
    if (!scroller || NSIsEmptyRect(knob) || travel <= 0) {
        fprintf(stderr, "macOS render probe could not find a scrollbar with history\n");
        exit(EXIT_FAILURE);
    }

    NSPoint from = NSMakePoint(NSMidX(knob), NSMidY(knob));
    NSPoint to = NSMakePoint(from.x, NSMinY(slot) + NSHeight(knob) / 2 + positions[step] * travel);
    // AppKit tracks a pressed scrollbar in its own event loop. Queue the
    // drag and release for that loop before starting the actual press.
    [NSApp postEvent:scroller_event(scroller, NSEventTypeLeftMouseDragged, to) atStart:NO];
    [NSApp postEvent:scroller_event(scroller, NSEventTypeLeftMouseUp, to) atStart:NO];
    [scroller mouseDown:scroller_event(scroller, NSEventTypeLeftMouseDown, from)];
    [scroll flashScrollers];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 420 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (fabs(scroller.doubleValue - positions[step]) > 1.0 / travel ||
                !capture_window_frame(scroll.window.contentView, prefix, states[step])) {
            fprintf(stderr, "macOS render probe could not capture scrollbar at %s\n", states[step].UTF8String);
            exit(EXIT_FAILURE);
        }
        if (step == 2) exit(EXIT_SUCCESS);
        capture_scrollbar(scroll, prefix, step + 1);
    });
}

__attribute__((constructor)) static void install_probe_input(void) {
    const char *sequence = getenv("WITTY_VIEWPORT_KEYS");
    const char *drag = getenv("WITTY_VIEWPORT_DRAG");
    const char *option = getenv("WITTY_VIEWPORT_DRAG_OPTION");
    const char *size = getenv("WITTY_VIEWPORT_RESIZE");
    const char *ready = getenv("WITTY_VIEWPORT_READY");
    const char *hover = getenv("WITTY_VIEWPORT_HOVER_CAPTURE");
    const char *split = getenv("WITTY_VIEWPORT_SPLIT_CAPTURE");
    const char *scrollbar = getenv("WITTY_VIEWPORT_SCROLLBAR_CAPTURE");
    const bool ghostty = getenv("WITTY_VIEWPORT_HOVER_GHOSTTY") != NULL;
    const bool has_keys = sequence && *sequence;
    const bool has_drag = drag && *drag;
    const bool has_resize = size && *size;
    const bool has_hover = hover && *hover;
    const bool has_split = split && *split;
    const bool has_scrollbar = scrollbar && *scrollbar;
    if (!ready || has_keys + has_drag + has_resize + has_hover + has_split + has_scrollbar != 1) return;
    if (has_hover || has_split || has_scrollbar) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            // A standalone Witty binary may never receive a LaunchServices activation.
            if (!ghostty && NSApp.windows.count == 0) {
                id<NSApplicationDelegate> delegate = NSApp.delegate;
                if ([delegate respondsToSelector:@selector(applicationDidBecomeActive:)]) {
                    [delegate applicationDidBecomeActive:[NSNotification
                        notificationWithName:NSApplicationDidBecomeActiveNotification object:NSApp]];
                }
            }
            NSString *prefix = [NSString stringWithUTF8String:has_hover ? hover : has_split ? split : scrollbar];
            NSString *ready_path = [NSString stringWithUTF8String:ready];
            NSString *marker = has_split ? [ready_path stringByAppendingPathComponent:@"pane1.ready"] : ready_path;
            wait_for_terminal(marker, 80, ghostty, ^(NSView *view) {
                [view.window makeKeyAndOrderFront:nil];
                [NSApp activateIgnoringOtherApps:YES];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (has_split ? 450 : 400) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    if (has_split) capture_split(view.window, prefix, ready_path, ghostty, 0, 30);
                    else if (has_scrollbar) {
                        NSScrollView *scroll = view.enclosingScrollView;
                        [scroll flashScrollers];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 420 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                            capture_scrollbar(scroll, prefix, 0);
                        });
                    }
                    else capture_hover(view, prefix, ghostty, 0);
                });
            });
        });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *ready_path = [NSString stringWithUTF8String:ready];
        if (has_resize) {
            wait_for_terminal(ready_path, 50, NO, ^(NSView *view) { resize_window(view, size); });
        } else if (has_drag) {
            const NSEventModifierFlags modifiers = option && *option ? NSEventModifierFlagOption : 0;
            wait_for_terminal(ready_path, 50, NO, ^(NSView *view) { send_mouse_drag(view, drag, modifiers); });
        } else {
            NSArray<NSString *> *keys = [[NSString stringWithUTF8String:sequence] componentsSeparatedByString:@","];
            const char *path = getenv("WITTY_VIEWPORT_RELOAD_CONFIG");
            NSString *config_path = path && *path ? [NSString stringWithUTF8String:path] : nil;
            wait_for_terminal(ready_path, 50, config_path != nil, ^(NSView *view) {
                send_key_sequence(view, keys, 0, config_path);
            });
        }
    });
}
