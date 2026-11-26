#pragma once

#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "dcimgui.h"
#include "dcimgui_internal.h"

#ifdef __cplusplus
extern "C" {
#endif

// Extensions supplied by Ghostty's pkg/dcimgui/ext.cpp.
void ImFontConfig_ImFontConfig(ImFontConfig* self);
void ImGuiStyle_ImGuiStyle(ImGuiStyle* self);

static inline ImGuiContext* witty_cimgui_context_create(void) {
    ImGuiContext* context = ImGui_CreateContext(NULL);
    if (context == NULL) return NULL;

    ImGui_SetCurrentContext(context);
    return context;
}

static inline void witty_cimgui_set_backend_platform(ImGuiContext* context, int platform) {
    ImGui_SetCurrentContext(context);
    ImGuiIO* io = ImGui_GetIO();
    io->BackendPlatformName = platform == 1 ? "witty_ui2" : "ghostty_embedded";
}

static inline void witty_cimgui_inspector_setup(
    ImGuiContext* context,
    void* font_data,
    int font_len
) {
    ImGui_SetCurrentContext(context);
    ImGuiIO* io = ImGui_GetIO();
    io->ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io->ConfigFlags |= ImGuiConfigFlags_IsSRGB;
    io->IniFilename = NULL;
    io->LogFilename = NULL;

    ImFontConfig font_config;
    ImFontConfig_ImFontConfig(&font_config);
    font_config.FontDataOwnedByAtlas = false;
    (void)ImFontAtlas_AddFontFromMemoryTTF(
        io->Fonts,
        font_data,
        font_len,
        32.0f,
        &font_config,
        NULL
    );
}

static inline void witty_cimgui_context_destroy(ImGuiContext* context) {
    if (context == NULL) return;
    ImGui_SetCurrentContext(context);
    ImGui_DestroyContext(context);
}

static inline void witty_cimgui_reset_style(ImGuiContext* context, float scale) {
    ImGui_SetCurrentContext(context);
    ImGuiStyle style;
    ImGuiStyle_ImGuiStyle(&style);
    ImGuiStyle_ScaleAllSizes(&style, scale);
    *ImGui_GetStyle() = style;
}

static inline void witty_cimgui_set_size(ImGuiContext* context, unsigned int width, unsigned int height) {
    ImGui_SetCurrentContext(context);
    ImGui_GetIO()->DisplaySize = (ImVec2){(float)width, (float)height};
}

static inline void witty_cimgui_add_mouse_button(ImGuiContext* context, int button, bool down) {
    ImGui_SetCurrentContext(context);
    ImGuiIO_AddMouseButtonEvent(ImGui_GetIO(), button, down);
}

static inline void witty_cimgui_add_mouse_wheel(ImGuiContext* context, float x, float y) {
    ImGui_SetCurrentContext(context);
    ImGuiIO_AddMouseWheelEvent(ImGui_GetIO(), x, y);
}

static inline void witty_cimgui_add_mouse_pos(ImGuiContext* context, float x, float y) {
    ImGui_SetCurrentContext(context);
    ImGuiIO_AddMousePosEvent(ImGui_GetIO(), x, y);
}

static inline void witty_cimgui_add_focus(ImGuiContext* context, bool focused) {
    ImGui_SetCurrentContext(context);
    ImGuiIO_AddFocusEvent(ImGui_GetIO(), focused);
}

static inline void witty_cimgui_add_text(ImGuiContext* context, const char* text) {
    ImGui_SetCurrentContext(context);
    ImGuiIO_AddInputCharactersUTF8(ImGui_GetIO(), text);
}

static inline void witty_cimgui_add_key(ImGuiContext* context, int key, bool down) {
    ImGui_SetCurrentContext(context);
    ImGuiIO_AddKeyEvent(ImGui_GetIO(), key, down);
}

static inline void witty_cimgui_begin_frame(ImGuiContext* context, float delta_time) {
    ImGui_SetCurrentContext(context);
    ImGui_GetIO()->DeltaTime = delta_time;
    ImGui_NewFrame();
}

static inline void witty_cimgui_render_frame(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_Render();
}

static inline const char* witty_cimgui_version(void) {
    return ImGui_GetVersion();
}

static inline int witty_cimgui_config_flags(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetIO()->ConfigFlags;
}

static inline float witty_cimgui_display_width(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetIO()->DisplaySize.x;
}

static inline float witty_cimgui_display_height(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetIO()->DisplaySize.y;
}

static inline float witty_cimgui_delta_time(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetIO()->DeltaTime;
}

static inline bool witty_cimgui_is_key_down(ImGuiContext* context, int key) {
    ImGui_SetCurrentContext(context);
    return ImGui_IsKeyDown(key);
}

static inline bool witty_cimgui_build_font_atlas(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    cImFontAtlasBuildMain(ImGui_GetIO()->Fonts);
    return true;
}

static inline unsigned int witty_cimgui_get_id(ImGuiContext* context, const char* value) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetID(value);
}

static inline bool witty_cimgui_dock_node_exists(ImGuiContext* context, unsigned int id) {
    ImGui_SetCurrentContext(context);
    return ImGui_DockBuilderGetNode(id) != NULL;
}

static inline bool witty_cimgui_dock_node_add(ImGuiContext* context, unsigned int id) {
    ImGui_SetCurrentContext(context);
    return ImGui_DockBuilderAddNodeEx(id, ImGuiDockNodeFlags_DockSpace) == id;
}

static inline void witty_cimgui_dock_node_set_main_viewport_size(ImGuiContext* context, unsigned int id) {
    ImGui_SetCurrentContext(context);
    ImGui_DockBuilderSetNodeSize(id, ImGui_GetMainViewport()->Size);
}

static inline void witty_cimgui_dock_window(ImGuiContext* context, const char* name, unsigned int id) {
    ImGui_SetCurrentContext(context);
    ImGui_DockBuilderDockWindow(name, id);
}

static inline void witty_cimgui_dock_finish(ImGuiContext* context, unsigned int id) {
    ImGui_SetCurrentContext(context);
    ImGui_DockBuilderFinish(id);
}

static inline bool witty_cimgui_dock_space_over_main_viewport(ImGuiContext* context, unsigned int id) {
    ImGui_SetCurrentContext(context);
    return ImGui_DockSpaceOverViewportEx(
        id,
        ImGui_GetMainViewport(),
        ImGuiDockNodeFlags_PassthruCentralNode,
        NULL
    ) == id;
}

static inline bool witty_cimgui_screen_dockspace(
    ImGuiContext* context,
    unsigned int id
) {
    ImGui_SetCurrentContext(context);
    bool setup = ImGui_DockBuilderGetNode(id) == NULL;
    if (setup) {
        (void)ImGui_DockBuilderAddNodeEx(id, ImGuiDockNodeFlags_DockSpace);
        ImGui_DockBuilderDockWindow("Info", id);
        ImGui_DockBuilderDockWindow("Cell", id);
        ImGui_DockBuilderDockWindow("PageList", id);
        ImGui_DockBuilderFinish(id);
    }
    return ImGui_DockSpaceEx(
        id,
        (ImVec2){0.0f, 0.0f},
        ImGuiDockNodeFlags_None,
        NULL
    ) == id;
}

static inline void witty_cimgui_set_next_window_size_max(
    ImGuiContext* context,
    float width,
    float height
) {
    ImGui_SetCurrentContext(context);
    ImVec2 viewport_size = ImGui_GetMainViewport()->Size;
    ImGui_SetNextWindowSize(
        (ImVec2){
            width < viewport_size.x ? width : viewport_size.x,
            height < viewport_size.y ? height : viewport_size.y,
        },
        ImGuiCond_FirstUseEver
    );
}

static inline bool witty_cimgui_begin_window(ImGuiContext* context, const char* name) {
    ImGui_SetCurrentContext(context);
    return ImGui_Begin(name, NULL, ImGuiWindowFlags_NoFocusOnAppearing);
}

static inline bool witty_cimgui_begin_window_open(
    ImGuiContext* context,
    const char* name,
    bool* open
) {
    ImGui_SetCurrentContext(context);
    return ImGui_Begin(name, open, ImGuiWindowFlags_NoFocusOnAppearing);
}

// This is Ghostty's inspector/widgets.zig DetachableHeader.window translated
// into a single bridge call. A negative result means no window was begun.
static inline int witty_cimgui_detachable_window(
    ImGuiContext* context,
    const char* label,
    bool* detached,
    bool* window_first,
    bool dock
) {
    ImGui_SetCurrentContext(context);
    if (!*detached) {
        *window_first = true;
        return -1;
    }

    if (*window_first) {
        *window_first = false;
        if (dock) {
            ImGuiID dock_id = ImGui_GetWindowDockID();
            if (dock_id != 0) {
                ImGuiID dock_id_right = 0;
                ImGuiID dock_id_left = 0;
                (void)ImGui_DockBuilderSplitNode(
                    dock_id,
                    ImGuiDir_Right,
                    0.4f,
                    &dock_id_right,
                    &dock_id_left
                );
                ImGui_DockBuilderDockWindow(label, dock_id_right);
                ImGui_DockBuilderFinish(dock_id);
            }
        }
    }

    return ImGui_Begin(
        label,
        detached,
        ImGuiWindowFlags_NoFocusOnAppearing
    ) ? 1 : 0;
}

// This is Ghostty's inspector/widgets.zig DetachableHeader.header translated
// into a single bridge call so the ImVec2 layout values remain C-native.
static inline bool witty_cimgui_detachable_header(
    ImGuiContext* context,
    const char* label,
    bool* detached
) {
    ImGui_SetCurrentContext(context);
    if (*detached) return false;

    ImGui_PushID(label);
    ImGui_SetNextItemAllowOverlap();
    bool is_open = ImGui_CollapsingHeader(label, ImGuiTreeNodeFlags_None);

    ImVec2 header_max = ImGui_GetItemRectMax();
    ImVec2 header_min = ImGui_GetItemRectMin();
    float button_size = ImGui_GetFrameHeight() - 4.0f;
    ImGui_SameLine();
    ImGui_SetCursorScreenPos((ImVec2){
        header_max.x - button_size - 4.0f,
        header_min.y + 2.0f,
    });
    ImGui_PushStyleVarImVec2(
        ImGuiStyleVar_FramePadding,
        (ImVec2){0.0f, 0.0f}
    );
    if (ImGui_ButtonEx(">>##detach", (ImVec2){button_size, button_size})) {
        *detached = true;
    }
    ImGui_PopStyleVar();
    if (ImGui_IsItemHovered(ImGuiHoveredFlags_DelayShort)) {
        ImGui_SetTooltipUnformatted("Detach into separate window");
    }
    ImGui_PopID();
    return is_open;
}

// This is Ghostty's newer callback-based detachableHeader helper. Bit zero in
// the result means a window was begun and must be ended; bit one means the
// caller should render its content. The pushed ID is always popped by the
// matching end call.
static inline int witty_cimgui_detachable_header_state_begin(
    ImGuiContext* context,
    const char* label,
    bool* show_window,
    bool* first_show
) {
    ImGui_SetCurrentContext(context);
    ImGui_PushID(label);

    if (*show_window) {
        if (!*first_show) {
            *first_show = true;
            ImGuiID current_dock_id = ImGui_GetWindowDockID();
            if (current_dock_id != 0) {
                ImGuiID dock_id_right = 0;
                ImGuiID dock_id_left = 0;
                (void)ImGui_DockBuilderSplitNode(
                    current_dock_id,
                    ImGuiDir_Right,
                    0.3f,
                    &dock_id_right,
                    &dock_id_left
                );
                ImGui_DockBuilderDockWindow(label, dock_id_right);
                ImGui_DockBuilderFinish(current_dock_id);
            }
        }

        bool visible = ImGui_Begin(
            label,
            show_window,
            ImGuiWindowFlags_NoFocusOnAppearing
        );
        return visible ? 3 : 1;
    }

    *first_show = false;
    ImGui_SetNextItemAllowOverlap();
    bool is_open = ImGui_CollapsingHeader(label, ImGuiTreeNodeFlags_None);

    ImVec2 header_max = ImGui_GetItemRectMax();
    ImVec2 header_min = ImGui_GetItemRectMin();
    float button_size = ImGui_GetFrameHeight() - 4.0f;
    ImGui_SameLine();
    ImGui_SetCursorScreenPos((ImVec2){
        header_max.x - button_size - 4.0f,
        header_min.y + 2.0f,
    });
    ImGui_PushStyleVarImVec2(
        ImGuiStyleVar_FramePadding,
        (ImVec2){0.0f, 0.0f}
    );
    if (ImGui_ButtonEx(">>##detach", (ImVec2){button_size, button_size})) {
        *show_window = true;
    }
    ImGui_PopStyleVar();
    if (ImGui_IsItemHovered(ImGuiHoveredFlags_DelayShort)) {
        ImGui_SetTooltipUnformatted("Pop out into separate window");
    }

    return is_open ? 2 : 0;
}

static inline void witty_cimgui_detachable_header_state_end(
    ImGuiContext* context,
    int state
) {
    ImGui_SetCurrentContext(context);
    if ((state & 1) != 0) ImGui_End();
    ImGui_PopID();
}

static inline void witty_cimgui_end_window(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_End();
}

static inline void witty_cimgui_set_window_focus(ImGuiContext* context, const char* name) {
    ImGui_SetCurrentContext(context);
    ImGui_SetWindowFocusStr(name);
}

static inline void witty_cimgui_open_popup(ImGuiContext* context, const char* name) {
    ImGui_SetCurrentContext(context);
    ImGui_OpenPopup(name, ImGuiPopupFlags_None);
}

static inline bool witty_cimgui_begin_popup_modal(ImGuiContext* context, const char* name) {
    ImGui_SetCurrentContext(context);
    return ImGui_BeginPopupModal(name, NULL, ImGuiWindowFlags_AlwaysAutoResize);
}

static inline void witty_cimgui_end_popup(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_EndPopup();
}

static inline void witty_cimgui_close_current_popup(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_CloseCurrentPopup();
}

static inline bool witty_cimgui_window_focused(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows);
}

static inline bool witty_cimgui_key_pressed(ImGuiContext* context, int key) {
    ImGui_SetCurrentContext(context);
    return ImGui_IsKeyPressed(key);
}

static inline void witty_cimgui_text(ImGuiContext* context, const char* value) {
    ImGui_SetCurrentContext(context);
    ImGui_TextUnformatted(value);
}

static inline void witty_cimgui_text_disabled(ImGuiContext* context, const char* value) {
    ImGui_SetCurrentContext(context);
    ImGui_TextDisabledUnformatted(value);
}

static inline void witty_cimgui_text_wrapped(ImGuiContext* context, const char* value) {
    ImGui_SetCurrentContext(context);
    ImGui_TextWrappedUnformatted(value);
}

static inline bool witty_cimgui_collapsing_header(ImGuiContext* context, const char* label) {
    ImGui_SetCurrentContext(context);
    return ImGui_CollapsingHeader(label, 0);
}

static inline bool witty_cimgui_collapsing_header_default_open(
    ImGuiContext* context,
    const char* label
) {
    ImGui_SetCurrentContext(context);
    return ImGui_CollapsingHeader(label, ImGuiTreeNodeFlags_DefaultOpen);
}

static inline void witty_cimgui_separator_text(ImGuiContext* context, const char* label) {
    ImGui_SetCurrentContext(context);
    ImGui_SeparatorText(label);
}

static inline void witty_cimgui_set_next_item_open(ImGuiContext* context, bool open) {
    ImGui_SetCurrentContext(context);
    ImGui_SetNextItemOpen(open, ImGuiCond_Once);
}

static inline bool witty_cimgui_checkbox(ImGuiContext* context, const char* label, bool* value) {
    ImGui_SetCurrentContext(context);
    return ImGui_Checkbox(label, value);
}

static inline bool witty_cimgui_input_text(
    ImGuiContext* context,
    const char* label,
    char* value,
    size_t capacity
) {
    ImGui_SetCurrentContext(context);
    return ImGui_InputText(label, value, capacity, ImGuiInputTextFlags_None);
}

static inline bool witty_cimgui_input_u16(
    ImGuiContext* context,
    const char* label,
    unsigned short* value
) {
    ImGui_SetCurrentContext(context);
    return ImGui_InputScalar(label, ImGuiDataType_U16, value);
}

static inline bool witty_cimgui_color_edit3(
    ImGuiContext* context,
    const char* label,
    float r,
    float g,
    float b,
    int flags
) {
    ImGui_SetCurrentContext(context);
    float color[3] = {r, g, b};
    return ImGui_ColorEdit3(label, color, flags);
}

static inline bool witty_cimgui_input_u32(
    ImGuiContext* context,
    const char* label,
    unsigned int* value
) {
    ImGui_SetCurrentContext(context);
    return ImGui_InputScalar(label, ImGuiDataType_U32, value);
}

static inline void witty_cimgui_set_next_item_width_for_text(
    ImGuiContext* context,
    const char* text
) {
    ImGui_SetCurrentContext(context);
    ImGui_SetNextItemWidth(ImGui_CalcTextSize(text).x);
}

static inline bool witty_cimgui_begin_combo(
    ImGuiContext* context,
    const char* label,
    const char* preview
) {
    ImGui_SetCurrentContext(context);
    return ImGui_BeginCombo(label, preview, ImGuiComboFlags_HeightSmall);
}

static inline void witty_cimgui_end_combo(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_EndCombo();
}

static inline bool witty_cimgui_selectable(
    ImGuiContext* context,
    const char* label,
    bool selected
) {
    ImGui_SetCurrentContext(context);
    return ImGui_SelectableEx(
        label,
        selected,
        ImGuiSelectableFlags_None,
        (ImVec2){0.0f, 0.0f}
    );
}

static inline void witty_cimgui_set_item_default_focus(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_SetItemDefaultFocus();
}

static inline bool witty_cimgui_begin_list_box(
    ImGuiContext* context,
    const char* label
) {
    ImGui_SetCurrentContext(context);
    return ImGui_BeginListBox(label, (ImVec2){0.0f, 0.0f});
}

static inline void witty_cimgui_end_list_box(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_EndListBox();
}

static inline bool witty_cimgui_begin_rows_child(
    ImGuiContext* context,
    const char* label,
    unsigned int visible_rows
) {
    ImGui_SetCurrentContext(context);
    float height = ImGui_GetTextLineHeightWithSpacing() * ((float)visible_rows + 2.0f);
    return ImGui_BeginChild(
        label,
        (ImVec2){0.0f, height},
        ImGuiChildFlags_Borders,
        ImGuiWindowFlags_None
    );
}

static inline void witty_cimgui_end_child(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_EndChild();
}

static inline bool witty_cimgui_tree_node(ImGuiContext* context, const char* label) {
    ImGui_SetCurrentContext(context);
    return ImGui_TreeNodeEx(label, ImGuiTreeNodeFlags_None);
}

static inline bool witty_cimgui_tree_node_flags(
    ImGuiContext* context,
    const char* label,
    int flags
) {
    ImGui_SetCurrentContext(context);
    return ImGui_TreeNodeEx(label, flags);
}

static inline float witty_cimgui_item_rect_min_x(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetItemRectMin().x;
}

static inline float witty_cimgui_item_rect_min_y(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetItemRectMin().y;
}

static inline float witty_cimgui_item_rect_max_y(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetItemRectMax().y;
}

static inline float witty_cimgui_text_line_height(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetTextLineHeight();
}

static inline void witty_cimgui_set_cursor_screen_pos(
    ImGuiContext* context,
    float x,
    float y
) {
    ImGui_SetCurrentContext(context);
    ImGui_SetCursorScreenPos((ImVec2){x, y});
}

static inline void witty_cimgui_tree_pop(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_TreePop();
}

static inline void witty_cimgui_help_marker(ImGuiContext* context, const char* value) {
    ImGui_SetCurrentContext(context);
    ImGui_TextDisabledUnformatted("(?)");
    if (!ImGui_BeginItemTooltip()) return;
    ImGui_PushTextWrapPos(ImGui_GetFontSize() * 35.0f);
    ImGui_TextUnformatted(value);
    ImGui_PopTextWrapPos();
    ImGui_EndTooltip();
}

static inline void witty_cimgui_indent(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_Indent();
}

static inline void witty_cimgui_unindent(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_Unindent();
}

static inline bool witty_cimgui_color_button(
    ImGuiContext* context,
    const char* label,
    float r,
    float g,
    float b,
    float a
) {
    ImGui_SetCurrentContext(context);
    return ImGui_ColorButton(label, (ImVec4){r, g, b, a}, ImGuiColorEditFlags_NoTooltip);
}

static inline void witty_cimgui_text_colored(
    ImGuiContext* context,
    float r,
    float g,
    float b,
    float a,
    const char* value
) {
    ImGui_SetCurrentContext(context);
    ImGui_TextColoredUnformatted((ImVec4){r, g, b, a}, value);
}

static inline bool witty_cimgui_button(ImGuiContext* context, const char* label) {
    ImGui_SetCurrentContext(context);
    return ImGui_Button(label);
}

static inline bool witty_cimgui_small_button(ImGuiContext* context, const char* label) {
    ImGui_SetCurrentContext(context);
    return ImGui_SmallButton(label);
}

static inline void witty_cimgui_separator(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_Separator();
}

static inline bool witty_cimgui_begin_table(
    ImGuiContext* context,
    const char* id,
    int columns,
    int flags
) {
    ImGui_SetCurrentContext(context);
    return ImGui_BeginTable(id, columns, flags);
}

static inline void witty_cimgui_end_table(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_EndTable();
}

static inline void witty_cimgui_table_setup_scroll_freeze(
    ImGuiContext* context,
    int columns,
    int rows
) {
    ImGui_SetCurrentContext(context);
    ImGui_TableSetupScrollFreeze(columns, rows);
}

static inline void witty_cimgui_table_setup_column(
    ImGuiContext* context,
    const char* label,
    int flags,
    float width
) {
    ImGui_SetCurrentContext(context);
    ImGui_TableSetupColumnEx(label, flags, width, 0);
}

static inline void witty_cimgui_table_headers_row(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_TableHeadersRow();
}

static inline void witty_cimgui_screens_table_headers(
    ImGuiContext* context,
    const char* help
) {
    ImGui_SetCurrentContext(context);
    ImGui_TableNextRowEx(ImGuiTableRowFlags_Headers, 0.0f);
    (void)ImGui_TableSetColumnIndex(0);
    ImGui_PushStyleVarImVec2(
        ImGuiStyleVar_FramePadding,
        (ImVec2){0.0f, 0.0f}
    );
    witty_cimgui_help_marker(context, help);
    ImGui_PopStyleVar();
    ImGui_SameLineEx(0.0f, ImGui_GetStyle()->ItemInnerSpacing.x);
    ImGui_TableHeader("Screen");
    (void)ImGui_TableSetColumnIndex(1);
    ImGui_TableHeader("Status");
    (void)ImGui_TableSetColumnIndex(2);
    ImGui_TableHeader("");
}

static inline void witty_cimgui_table_next_row(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_TableNextRow();
}

static inline bool witty_cimgui_table_next_column(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_TableNextColumn();
}

static inline void witty_cimgui_table_set_column(ImGuiContext* context, int column) {
    ImGui_SetCurrentContext(context);
    (void)ImGui_TableSetColumnIndex(column);
}

static inline void witty_cimgui_table_set_bg_color(
    ImGuiContext* context,
    int target,
    unsigned int color
) {
    ImGui_SetCurrentContext(context);
    ImGui_TableSetBgColor(target, color, -1);
}

static inline bool witty_cimgui_selectable_bool(
    ImGuiContext* context,
    const char* label,
    bool* selected
) {
    ImGui_SetCurrentContext(context);
    return ImGui_SelectableBoolPtr(label, selected, ImGuiSelectableFlags_SpanAllColumns);
}

static inline void witty_cimgui_set_scroll_here_y(ImGuiContext* context, float ratio) {
    ImGui_SetCurrentContext(context);
    ImGui_SetScrollHereY(ratio);
}

static inline void witty_cimgui_push_id_ptr(ImGuiContext* context, const void* value) {
    ImGui_SetCurrentContext(context);
    ImGui_PushIDPtr(value);
}

static inline void witty_cimgui_push_id_str(ImGuiContext* context, const char* value) {
    ImGui_SetCurrentContext(context);
    ImGui_PushID(value);
}

static inline void witty_cimgui_push_id_int(ImGuiContext* context, int value) {
    ImGui_SetCurrentContext(context);
    ImGui_PushIDInt(value);
}

static inline void witty_cimgui_pop_id(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_PopID();
}

static inline void witty_cimgui_same_line(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_SameLine();
}

static inline void witty_cimgui_new_line(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_NewLine();
}

static inline bool witty_cimgui_item_hovered(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_IsItemHovered(0);
}

static inline bool witty_cimgui_item_hovered_delay_short(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_IsItemHovered(ImGuiHoveredFlags_DelayShort);
}

static inline void witty_cimgui_begin_disabled(ImGuiContext* context, bool disabled) {
    ImGui_SetCurrentContext(context);
    ImGui_BeginDisabled(disabled);
}

static inline void witty_cimgui_end_disabled(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_EndDisabled();
}

static inline void witty_cimgui_push_item_width_for_text(
    ImGuiContext* context,
    const char* text
) {
    ImGui_SetCurrentContext(context);
    ImGui_PushItemWidth(ImGui_CalcTextSize(text).x);
}

static inline void witty_cimgui_pop_item_width(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_PopItemWidth();
}

static inline void witty_cimgui_align_text_to_frame_padding(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    ImGui_AlignTextToFramePadding();
}

// Ghostty's inspector PageList scrollbar widget. The returned row delta is
// zero unless the invisible drag target was moved during this frame.
static inline long long witty_cimgui_pagelist_scrollbar(
    ImGuiContext* context,
    size_t total,
    size_t offset,
    size_t len
) {
    ImGui_SetCurrentContext(context);
    if (total == 0) return 0;

    float avail_width = ImGui_GetContentRegionAvail().x;
    float bar_height = ImGui_GetFrameHeight();
    ImVec2 cursor_pos = ImGui_GetCursorScreenPos();
    float total_f = (float)total;
    float grab_start = ((float)offset / total_f) * avail_width;
    float grab_width = ((float)len / total_f) * avail_width;
    if (grab_width < 4.0f) grab_width = 4.0f;

    ImDrawList* draw_list = ImGui_GetWindowDrawList();
    ImU32 bg_color = ImGui_GetColorU32(ImGuiCol_ScrollbarBg);
    ImU32 grab_color = ImGui_GetColorU32(ImGuiCol_ScrollbarGrab);
    ImDrawList_AddRectFilledEx(
        draw_list,
        cursor_pos,
        (ImVec2){cursor_pos.x + avail_width, cursor_pos.y + bar_height},
        bg_color,
        0.0f,
        ImDrawFlags_None
    );
    ImDrawList_AddRectFilledEx(
        draw_list,
        (ImVec2){cursor_pos.x + grab_start, cursor_pos.y},
        (ImVec2){cursor_pos.x + grab_start + grab_width, cursor_pos.y + bar_height},
        grab_color,
        0.0f,
        ImDrawFlags_None
    );
    (void)ImGui_InvisibleButton(
        "scrollbar_drag",
        (ImVec2){avail_width, bar_height},
        ImGuiButtonFlags_None
    );

    long long delta_row = 0;
    if (ImGui_IsItemActive()) {
        ImVec2 drag_delta = ImGui_GetMouseDragDelta(ImGuiMouseButton_Left, 0.0f);
        if (drag_delta.x != 0.0f) {
            delta_row = (long long)((drag_delta.x / avail_width) * total_f);
            ImGui_ResetMouseDragDelta();
        }
    }
    if (ImGui_IsItemHovered(ImGuiHoveredFlags_DelayShort)) {
        char tooltip[128];
        snprintf(
            tooltip,
            sizeof(tooltip),
            "offset=%zu len=%zu total=%zu",
            offset,
            len,
            total
        );
        ImGui_SetTooltipUnformatted(tooltip);
    }
    return delta_row;
}

static inline void witty_cimgui_tooltip(ImGuiContext* context, const char* value) {
    ImGui_SetCurrentContext(context);
    ImGui_SetTooltipUnformatted(value);
}

static inline float witty_cimgui_cursor_screen_y(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetCursorScreenPos().y;
}

static inline float witty_cimgui_mouse_y(ImGuiContext* context) {
    ImGui_SetCurrentContext(context);
    return ImGui_GetMousePos().y;
}

#ifdef __APPLE__
bool witty_cimgui_metal_init(void* device);
void witty_cimgui_metal_shutdown(void);
void witty_cimgui_metal_new_frame(void* descriptor);
void witty_cimgui_metal_render(void* command_buffer, void* descriptor);
#elif defined(__linux__)
bool witty_cimgui_opengl_init(ImGuiContext* context);
void witty_cimgui_opengl_shutdown(ImGuiContext* context);
void witty_cimgui_opengl_new_frame(ImGuiContext* context);
void witty_cimgui_opengl_render(ImGuiContext* context);
#endif

#ifdef __cplusplus
}
#endif
