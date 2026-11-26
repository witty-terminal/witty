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

static void send_key_sequence(NSView *view, NSArray<NSString *> *keys, NSUInteger index) {
    if (index == keys.count) {
        fprintf(stderr, "macOS render probe dispatched input\n");
        return;
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
        {"space", ' ', kVK_Space},
    };
    NSString *key = keys[index];
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC),
            dispatch_get_main_queue(), ^{ send_key_sequence(view, keys, index + 1); });
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

static bool capture_hover_frame(NSView *view, NSString *prefix, NSString *state) {
    // Use the window server image so the preview and terminal appear together.
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

static void move_pointer(NSView *view, double x, double y, NSEventModifierFlags modifiers) {
    NSPoint point = [view convertPoint:terminal_point(view, x, y) toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:point
        modifierFlags:modifiers timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber
        context:nil eventNumber:0 clickCount:0 pressure:0];
    [view mouseMoved:event];
}

static void send_command_flag(NSView *view, bool pressed) {
    CGEventRef cg = CGEventCreateKeyboardEvent(NULL, kVK_Command, pressed);
    if (!cg) exit(EXIT_FAILURE);
    CGEventSetType(cg, kCGEventFlagsChanged);
    CGEventSetFlags(cg, pressed ? kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK : 0);
    [view flagsChanged:[NSEvent eventWithCGEvent:cg]];
    CFRelease(cg);
}

static void capture_hover(NSView *view, NSString *prefix, NSUInteger step) {
    NSArray<NSString *> *states = @[@"idle", @"hover", @"rethemed", @"cleared"];
    if (!capture_hover_frame(view, prefix, states[step])) {
        fprintf(stderr, "macOS render probe could not capture the foreground terminal window\n");
        exit(EXIT_FAILURE);
    }
    if (step == 0) {
        // The fixture prints the link on the second row, beginning at the second column.
        move_pointer(view, .065, .10, 0);
        send_command_flag(view, true);
        move_pointer(view, .067, .10, NSEventModifierFlagCommand);
    } else if (step == 1) {
        NSString *appearance = [view.window.effectiveAppearance bestMatchFromAppearancesWithNames:
            @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        view.window.appearance = [NSAppearance appearanceNamed:
            [appearance isEqualToString:NSAppearanceNameAqua] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    } else if (step == 2) {
        send_command_flag(view, false);
        move_pointer(view, .5, .65, 0);
    } else {
        exit(EXIT_SUCCESS);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 450 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ capture_hover(view, prefix, step + 1); });
}

static void wait_for_terminal(const char *ready, int attempts, BOOL ghostty, void (^dispatch_input)(NSView *)) {
    if (access(ready, F_OK) == 0) {
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

__attribute__((constructor)) static void install_probe_input(void) {
    const char *sequence = getenv("WITTY_VIEWPORT_KEYS");
    const char *drag = getenv("WITTY_VIEWPORT_DRAG");
    const char *option = getenv("WITTY_VIEWPORT_DRAG_OPTION");
    const char *size = getenv("WITTY_VIEWPORT_RESIZE");
    const char *ready = getenv("WITTY_VIEWPORT_READY");
    const char *hover = getenv("WITTY_VIEWPORT_HOVER_CAPTURE");
    const bool ghostty = getenv("WITTY_VIEWPORT_HOVER_GHOSTTY") != NULL;
    const bool has_keys = sequence && *sequence;
    const bool has_drag = drag && *drag;
    const bool has_resize = size && *size;
    const bool has_hover = hover && *hover;
    if (!ready || has_keys + has_drag + has_resize + has_hover != 1) return;
    if (has_hover) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            // A standalone Witty binary may never receive a LaunchServices activation.
            if (!ghostty && NSApp.windows.count == 0) {
                id<NSApplicationDelegate> delegate = NSApp.delegate;
                if ([delegate respondsToSelector:@selector(applicationDidBecomeActive:)]) {
                    [delegate applicationDidBecomeActive:[NSNotification
                        notificationWithName:NSApplicationDidBecomeActiveNotification object:NSApp]];
                }
            }
            NSString *prefix = [NSString stringWithUTF8String:hover];
            wait_for_terminal(ready, 80, ghostty, ^(NSView *view) {
                [view.window makeKeyAndOrderFront:nil];
                [NSApp activateIgnoringOtherApps:YES];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(), ^{ capture_hover(view, prefix, 0); });
            });
        });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (has_resize) {
            wait_for_terminal(ready, 50, NO, ^(NSView *view) { resize_window(view, size); });
        } else if (has_drag) {
            const NSEventModifierFlags modifiers = option && *option ? NSEventModifierFlagOption : 0;
            wait_for_terminal(ready, 50, NO, ^(NSView *view) { send_mouse_drag(view, drag, modifiers); });
        } else {
            NSArray<NSString *> *keys = [[NSString stringWithUTF8String:sequence] componentsSeparatedByString:@","];
            wait_for_terminal(ready, 50, NO, ^(NSView *view) { send_key_sequence(view, keys, 0); });
        }
    });
}
