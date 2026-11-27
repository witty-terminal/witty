#pragma once
#include <AppKit/AppKit.h>
#include <dispatch/dispatch.h>

static inline double witty_ui2_macos_scale(void *window) {
    NSWindow *view = (NSWindow *)window;
    return view ? view.backingScaleFactor : 1;
}

static inline void witty_ui2_macos_quit(void) {
    // Terminate after the current UI2 frame. Sokol's application delegate
    // cleans up the renderer even when the window is borderless.
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}

static inline bool witty_ui2_macos_resize(void *window, double width, double height) {
    NSWindow *view = (NSWindow *)window;
    if (!view || (view.styleMask & NSWindowStyleMaskFullScreen)) return false;
    [view setContentSize:NSMakeSize(width, height)];
    return true;
}
