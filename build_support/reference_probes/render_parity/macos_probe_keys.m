#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
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
        fprintf(stderr, "macOS render probe dispatched all keys\n");
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

static void wait_for_terminal(NSArray<NSString *> *keys, const char *ready, int attempts) {
    if (access(ready, F_OK) == 0) {
        for (NSWindow *window in NSApplication.sharedApplication.windows) {
            NSView *view = terminal_view(window.contentView);
            if (!view) continue;
            // The PTY may still be draining the history written before the marker.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC),
                dispatch_get_main_queue(), ^{ send_key_sequence(view, keys, 0); });
            return;
        }
    }
    if (attempts <= 0) {
        fprintf(stderr, "macOS render probe timed out waiting for the terminal and its PTY\n");
        exit(EXIT_FAILURE);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ wait_for_terminal(keys, ready, attempts - 1); });
}

__attribute__((constructor)) static void install_probe_keys(void) {
    const char *sequence = getenv("WITTY_VIEWPORT_KEYS");
    const char *ready = getenv("WITTY_VIEWPORT_READY");
    if (!sequence || !ready) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *value = [NSString stringWithUTF8String:sequence];
        wait_for_terminal([value componentsSeparatedByString:@","], ready, 50);
    });
}
