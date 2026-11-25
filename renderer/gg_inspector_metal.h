#pragma once

#include <Metal/Metal.h>

typedef struct witty_gg_inspector_target {
    void* texture;
    unsigned int width, height;
    unsigned long format;
    double red, green, blue, alpha;
} witty_gg_inspector_target;

typedef struct witty_gg_inspector_texture {
    unsigned int width, height;
    unsigned long format;
} witty_gg_inspector_texture;

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline witty_gg_inspector_target witty_gg_inspector_target_get(MTLRenderPassDescriptor* pass) {
    MTLRenderPassColorAttachmentDescriptor* color = pass.colorAttachments[0];
    id<MTLTexture> texture = color.texture;
    if (!texture || texture.sampleCount != 1 || pass.depthAttachment.texture ||
        pass.stencilAttachment.texture || color.loadAction != MTLLoadActionClear)
        return (witty_gg_inspector_target){0};
    const MTLClearColor clear = color.clearColor;
    return (witty_gg_inspector_target){
        (void*)texture, (unsigned int)texture.width, (unsigned int)texture.height, texture.pixelFormat,
        clear.red, clear.green, clear.blue, clear.alpha,
    };
}

static inline witty_gg_inspector_texture witty_gg_inspector_texture_get(id<MTLTexture> texture) {
    return (witty_gg_inspector_texture){
        (unsigned int)texture.width, (unsigned int)texture.height, texture.pixelFormat,
    };
}
#endif
