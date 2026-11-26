#include "imgui.h"
#include "imgui_impl_opengl3.h"

extern "C" bool witty_cimgui_opengl_init(ImGuiContext* context) {
    ImGui::SetCurrentContext(context);
    ImGui::GetIO().BackendPlatformName = "witty_ui2";
    return ImGui_ImplOpenGL3_Init(nullptr);
}

extern "C" void witty_cimgui_opengl_shutdown(ImGuiContext* context) {
    ImGui::SetCurrentContext(context);
    ImGui_ImplOpenGL3_Shutdown();
}

extern "C" void witty_cimgui_opengl_new_frame(ImGuiContext* context) {
    ImGui::SetCurrentContext(context);
    ImGui_ImplOpenGL3_NewFrame();
}

extern "C" void witty_cimgui_opengl_render(ImGuiContext* context) {
    ImGui::SetCurrentContext(context);
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}
