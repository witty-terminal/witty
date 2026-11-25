#pragma once

#include "dcimgui.h"

typedef struct witty_cimgui_draw_frame {
    void* data;
    float x, y, width, height, scale_x, scale_y;
    int lists, vertices, indices, vertex_stride, index_stride;
} witty_cimgui_draw_frame;

typedef struct witty_cimgui_draw_list {
    void* list;
    void* vertices;
    void* indices;
    int vertex_count, index_count, commands;
} witty_cimgui_draw_list;

typedef struct witty_cimgui_draw_command {
    unsigned int vertex_offset, index_offset, count;
    float left, top, right, bottom;
    void* texture;
    bool callback;
} witty_cimgui_draw_command;

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#ifdef __APPLE__
void ImGui_ImplMetal_UpdateTexture(ImTextureData* texture);

static inline bool witty_cimgui_metal_update_textures(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    const ImDrawData* data = ImGui_GetDrawData();
    if (!data || !data->Valid) return false;
    if (data->Textures) {
        for (int i = 0; i < data->Textures->Size; ++i) {
            ImTextureData* texture = data->Textures->Data[i];
            if (texture->Status != ImTextureStatus_OK)
                ImGui_ImplMetal_UpdateTexture(texture);
        }
    }
    return true;
}
#endif

static inline witty_cimgui_draw_frame witty_cimgui_draw_frame_get(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImDrawData* data = ImGui_GetDrawData();
    if (!data || !data->Valid) return (witty_cimgui_draw_frame){0};
    return (witty_cimgui_draw_frame){
        .data = data,
        .x = data->DisplayPos.x, .y = data->DisplayPos.y,
        .width = data->DisplaySize.x, .height = data->DisplaySize.y,
        .scale_x = data->FramebufferScale.x, .scale_y = data->FramebufferScale.y,
        .lists = data->CmdListsCount, .vertices = data->TotalVtxCount,
        .indices = data->TotalIdxCount, .vertex_stride = sizeof(ImDrawVert),
        .index_stride = sizeof(ImDrawIdx),
    };
}

static inline witty_cimgui_draw_list witty_cimgui_draw_list_get(const ImDrawData* data, int i) {
    ImDrawList* list = data->CmdLists.Data[i];
    return (witty_cimgui_draw_list){
        .list = list, .vertices = list->VtxBuffer.Data, .indices = list->IdxBuffer.Data,
        .vertex_count = list->VtxBuffer.Size, .index_count = list->IdxBuffer.Size,
        .commands = list->CmdBuffer.Size,
    };
}

static inline witty_cimgui_draw_command witty_cimgui_draw_command_get(ImDrawList* list, int i) {
    ImDrawCmd* cmd = &list->CmdBuffer.Data[i];
    return (witty_cimgui_draw_command){
        .vertex_offset = cmd->VtxOffset, .index_offset = cmd->IdxOffset, .count = cmd->ElemCount,
        .left = cmd->ClipRect.x, .top = cmd->ClipRect.y, .right = cmd->ClipRect.z, .bottom = cmd->ClipRect.w,
        .texture = cmd->UserCallback ? NULL : (void*)(uintptr_t)ImDrawCmd_GetTexID(cmd),
        .callback = cmd->UserCallback != NULL,
    };
}
#endif
