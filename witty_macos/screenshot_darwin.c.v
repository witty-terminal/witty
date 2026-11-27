module witty_macos

#flag darwin -framework ImageIO
#include "@VMODROOT/witty_macos/screenshot_darwin.h"

fn C.witty_write_iosurface_png(surface voidptr, path &char) bool

// The terminal's Metal render target is premultiplied BGRA in Display P3.
pub fn write_iosurface_png(surface &IOSurface, path string) ! {
	if isnil(surface) || surface.get_pixel_format() != .p32_bgra {
		return error('terminal frame has no BGRA surface')
	}
	if !C.witty_write_iosurface_png(voidptr(surface), &char(path.str)) {
		return error('could not write terminal PNG to ${path}')
	}
}
