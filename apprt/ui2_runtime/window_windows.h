#pragma once
#include <windows.h>

static inline bool witty_ui2_windows_resize(void *window, unsigned int width, unsigned int height) {
    HWND hwnd = (HWND)window;
    if (!hwnd || IsZoomed(hwnd)) return false;
    RECT rect = {0, 0, (LONG)width, (LONG)height};
    DWORD style = (DWORD)GetWindowLongPtrW(hwnd, GWL_STYLE);
    DWORD ex_style = (DWORD)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (!AdjustWindowRectExForDpi(&rect, style, GetMenu(hwnd) != NULL, ex_style, GetDpiForWindow(hwnd))) {
        return false;
    }
    return SetWindowPos(hwnd, NULL, 0, 0, rect.right - rect.left, rect.bottom - rect.top,
        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE) != 0;
}
