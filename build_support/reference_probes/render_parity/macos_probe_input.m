#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static NSView *terminal_view(NSView *view) {
    if (!view) return nil;
    if ([NSStringFromClass(view.class) isEqualToString:@"VTTerminalView"]) return view;
    for (NSView *child in view.subviews) {
        NSView *terminal = terminal_view(child);
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

    const NSRect bounds = view.bounds;
    NSPoint start = NSMakePoint(NSMinX(bounds) + coords[0] * NSWidth(bounds),
        NSMinY(bounds) + (view.isFlipped ? coords[1] : 1 - coords[1]) * NSHeight(bounds));
    NSPoint end = NSMakePoint(NSMinX(bounds) + coords[2] * NSWidth(bounds),
        NSMinY(bounds) + (view.isFlipped ? coords[3] : 1 - coords[3]) * NSHeight(bounds));
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

static void wait_for_terminal(const char *ready, int attempts, void (^dispatch_input)(NSView *)) {
    if (access(ready, F_OK) == 0) {
        for (NSWindow *window in NSApplication.sharedApplication.windows) {
            NSView *view = terminal_view(window.contentView);
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
        dispatch_get_main_queue(), ^{ wait_for_terminal(ready, attempts - 1, dispatch_input); });
}

__attribute__((constructor)) static void install_probe_input(void) {
    const char *sequence = getenv("WITTY_VIEWPORT_KEYS");
    const char *drag = getenv("WITTY_VIEWPORT_DRAG");
    const char *option = getenv("WITTY_VIEWPORT_DRAG_OPTION");
    const char *size = getenv("WITTY_VIEWPORT_RESIZE");
    const char *ready = getenv("WITTY_VIEWPORT_READY");
    const bool has_keys = sequence && *sequence;
    const bool has_drag = drag && *drag;
    const bool has_resize = size && *size;
    if (!ready || has_keys + has_drag + has_resize != 1) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (has_resize) {
            wait_for_terminal(ready, 50, ^(NSView *view) { resize_window(view, size); });
        } else if (has_drag) {
            const NSEventModifierFlags modifiers = option && *option ? NSEventModifierFlagOption : 0;
            wait_for_terminal(ready, 50, ^(NSView *view) { send_mouse_drag(view, drag, modifiers); });
        } else {
            NSArray<NSString *> *keys = [[NSString stringWithUTF8String:sequence] componentsSeparatedByString:@","];
            wait_for_terminal(ready, 50, ^(NSView *view) { send_key_sequence(view, keys, 0); });
        }
    });
}
