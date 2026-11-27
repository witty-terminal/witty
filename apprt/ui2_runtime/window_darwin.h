#pragma once
#include <AppKit/AppKit.h>
#include <QuartzCore/CAMetalLayer.h>
#include <MetalKit/MetalKit.h>
#include <dispatch/dispatch.h>

static inline void witty_ui2_macos_configure_render_targets(void *window) {
    NSView *content = ((NSWindow *)window).contentView;
    if (![content isKindOfClass:[MTKView class]]) return;
    MTKView *view = (MTKView *)content;
    if ([view.layer isKindOfClass:[CAMetalLayer class]]) {
        // Pane updates already wait for the previous window pass to finish.
        ((CAMetalLayer *)view.layer).maximumDrawableCount = 2;
    }
    if (@available(macOS 13.0, *)) {
        if ([view.device supportsFamily:MTLGPUFamilyApple7]) {
            // The window pass clears depth and discards it when it ends.
            view.depthStencilStorageMode = MTLStorageModeMemoryless;
        }
    }
}

static inline void witty_ui2_macos_set_display_p3(void *window) {
    CALayer *layer = ((NSWindow *)window).contentView.layer;
    if (![layer isKindOfClass:[CAMetalLayer class]]) return;
    // Both terminal color modes produce Display P3 pixels.
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    if (!space) return;
    ((CAMetalLayer *)layer).colorspace = space;
    CGColorSpaceRelease(space);
}

static inline void witty_ui2_macos_set_translucent(void *window, bool translucent) {
    NSWindow *native = (NSWindow *)window;
    CALayer *layer = native.contentView.layer;
    if (![layer isKindOfClass:[CAMetalLayer class]]) return;
    if (native.isOpaque == translucent) {
        native.backgroundColor = translucent ? NSColor.clearColor : NSColor.windowBackgroundColor;
        native.opaque = !translucent;
    }
    layer.opaque = !translucent;
}

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
