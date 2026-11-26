#ifndef WITTY_UI2_X11_WINDOW_H
#define WITTY_UI2_X11_WINDOW_H

#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include "sokol_app.h"

static inline void witty_ui2_x11_identify(const char *class_name) {
    Display *display = (Display *)sapp_x11_get_display();
    Window window = (Window)sapp_x11_get_window();
    if (!display || !window) return;

    XClassHint hint = { .res_name = "witty", .res_class = (char *)class_name };
    XSetClassHint(display, window, &hint);
    unsigned long pid = (unsigned long)getpid();
    Atom property = XInternAtom(display, "_NET_WM_PID", False);
    XChangeProperty(display, window, property, XA_CARDINAL, 32, PropModeReplace,
        (const unsigned char *)&pid, 1);
    XFlush(display);
}

static inline bool witty_ui2_x11_resize(unsigned int width, unsigned int height) {
    Display *display = (Display *)sapp_x11_get_display();
    Window window = (Window)sapp_x11_get_window();
    if (!display || !window) return false;
    XResizeWindow(display, window, width, height);
    XFlush(display);
    return true;
}

#endif
