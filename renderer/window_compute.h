#ifndef WITTY_WINDOW_COMPUTE_H
#define WITTY_WINDOW_COMPUTE_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <stdbool.h>
#ifndef SOKOL_GFX_INCLUDED
#include "sokol_gfx.h"
#endif

#if defined(SOKOL_METAL) && defined(V_SOKOL_MTL_COMMAND_QUEUE)
#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

static inline void witty_window_compute_configure(void *handle) {
    NSWindow *window = (__bridge NSWindow *)handle;
    if (![window.contentView isKindOfClass:MTKView.class]) return;
    MTKView *view = (MTKView *)window.contentView;
    if (@available(macOS 10.15, *)) {
        if ([view.device supportsFamily:MTLGPUFamilyApple4]) view.framebufferOnly = NO;
    }
}

static inline bool witty_window_compute_can_write(void *handle) {
    id<MTLTexture> texture = (__bridge id<MTLTexture>)handle;
    return texture && (texture.usage & MTLTextureUsageShaderWrite);
}

static inline void *witty_window_compute_make_pipeline(void *device_ref, void *library_ref) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_ref;
    id<MTLLibrary> library = (__bridge id<MTLLibrary>)library_ref;
    id<MTLFunction> function = [library newFunctionWithName:@"terminal_window_compute"];
    if (!function) return NULL;
    NSError *error = nil;
    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
#if __has_feature(objc_arc)
    return (__bridge_retained void *)pipeline;
#else
    [function release];
    return (void *)pipeline;
#endif
}

// Returns -1 after a failed submission, when this frame must acquire a new drawable.
static inline int witty_window_compute_present(
    void *pipeline_ref, void *drawable_ref, void *uniforms, void *background, void *glyphs,
    void *offsets, void *indices, void *grayscale, void *color, const void *params, size_t params_size
) {
    id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)sg_v_mtl_command_queue();
    id<MTLComputePipelineState> pipeline = (__bridge id<MTLComputePipelineState>)pipeline_ref;
    id<CAMetalDrawable> drawable = (__bridge id<CAMetalDrawable>)drawable_ref;
    id<MTLCommandBuffer> command = [queue commandBufferWithUnretainedReferences];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    if (!encoder) return 0;
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:drawable.texture atIndex:0];
    [encoder setTexture:(__bridge id<MTLTexture>)grayscale atIndex:1];
    [encoder setTexture:(__bridge id<MTLTexture>)color atIndex:2];
    [encoder setBuffer:(__bridge id<MTLBuffer>)uniforms offset:0 atIndex:0];
    [encoder setBuffer:(__bridge id<MTLBuffer>)background offset:0 atIndex:1];
    [encoder setBuffer:(__bridge id<MTLBuffer>)glyphs offset:0 atIndex:2];
    [encoder setBuffer:(__bridge id<MTLBuffer>)offsets offset:0 atIndex:3];
    [encoder setBuffer:(__bridge id<MTLBuffer>)indices offset:0 atIndex:4];
    [encoder setBytes:params length:params_size atIndex:5];
    const NSUInteger group_width = pipeline.threadExecutionWidth;
    const NSUInteger group_height = MIN(8, pipeline.maxTotalThreadsPerThreadgroup / group_width);
    [encoder dispatchThreads:MTLSizeMake(drawable.texture.width, drawable.texture.height, 1)
       threadsPerThreadgroup:MTLSizeMake(group_width, group_height, 1)];
    [encoder endEncoding];
    [command presentDrawable:drawable];
    [command commit];
    [command waitUntilCompleted];
    return command.status == MTLCommandBufferStatusCompleted ? 1 : -1;
}
#else
static inline void witty_window_compute_configure(void *handle) { (void)handle; }
static inline bool witty_window_compute_can_write(void *texture) { (void)texture; return false; }
static inline void *witty_window_compute_make_pipeline(void *device, void *library) {
    (void)device; (void)library; return NULL;
}
static inline int witty_window_compute_present(
    void *pipeline, void *drawable, void *uniforms, void *background, void *glyphs,
    void *offsets, void *indices, void *grayscale, void *color, const void *params, size_t params_size
) {
    (void)pipeline; (void)drawable; (void)uniforms; (void)background; (void)glyphs;
    (void)offsets; (void)indices; (void)grayscale; (void)color; (void)params; (void)params_size;
    return 0;
}
#endif
#endif
#endif
