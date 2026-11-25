#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned char component(unsigned long pixel, unsigned long mask) {
    while ((mask & 1) == 0) {
        mask >>= 1;
        pixel >>= 1;
    }
    return (unsigned char)((pixel & mask) * 255 / mask);
}

int main(int argc, char **argv) {
    char *end;
    Window window = argc == 2 ? strtoul(argv[1], &end, 0) : 0;
    if (!window || *end) {
        fprintf(stderr, "Expected an X11 window ID\n");
        return 1;
    }

    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "Could not connect to the X11 display\n");
        return 1;
    }

    XWindowAttributes attr;
    if (!XGetWindowAttributes(display, window, &attr) || attr.map_state != IsViewable) {
        fprintf(stderr, "The X11 window is not visible\n");
        XCloseDisplay(display);
        return 1;
    }

    XImage *image = XGetImage(display, window, 0, 0, attr.width, attr.height, AllPlanes, ZPixmap);
    if (!image) {
        fprintf(stderr, "Could not read the X11 window pixels\n");
        XCloseDisplay(display);
        return 1;
    }
    if (!image->red_mask || !image->green_mask || !image->blue_mask) {
        fprintf(stderr, "Expected a true-color X11 window\n");
        XDestroyImage(image);
        XCloseDisplay(display);
        return 1;
    }

    printf("P6\n%d %d\n255\n", image->width, image->height);
    for (int y = 0; y < image->height; ++y) {
        for (int x = 0; x < image->width; ++x) {
            unsigned long pixel = XGetPixel(image, x, y);
            putchar(component(pixel, image->red_mask));
            putchar(component(pixel, image->green_mask));
            putchar(component(pixel, image->blue_mask));
        }
    }
    XDestroyImage(image);
    XCloseDisplay(display);
    return fflush(stdout) == EOF ? 1 : 0;
}
