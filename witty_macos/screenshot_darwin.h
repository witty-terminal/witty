#ifndef WITTY_SCREENSHOT_DARWIN_H
#define WITTY_SCREENSHOT_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOSurface/IOSurface.h>
#include <ImageIO/ImageIO.h>
#include <stdbool.h>

static inline bool witty_write_iosurface_png(void *surface_ptr, const char *path) {
	IOSurfaceRef surface = (IOSurfaceRef)surface_ptr;
	if (IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL) != kIOReturnSuccess) return false;
	size_t width = IOSurfaceGetWidth(surface);
	size_t height = IOSurfaceGetHeight(surface);
	size_t pitch = IOSurfaceGetBytesPerRow(surface);
	size_t length = IOSurfaceGetAllocSize(surface);
	const void *pixels = IOSurfaceGetBaseAddress(surface);
	CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
	CGDataProviderRef provider = pixels && pitch && height <= length / pitch
		? CGDataProviderCreateWithData(NULL, pixels, length, NULL) : NULL;
	CGImageRef image = provider && colorspace
		? CGImageCreate(width, height, 8, 32, pitch, colorspace,
			kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
			provider, NULL, false, kCGRenderingIntentDefault) : NULL;
	CFMutableDataRef png = image ? CFDataCreateMutable(kCFAllocatorDefault, 0) : NULL;
	CGImageDestinationRef destination = png
		? CGImageDestinationCreateWithData(png, CFSTR("public.png"), 1, NULL) : NULL;
	bool encoded = false;
	if (destination) {
		CGImageDestinationAddImage(destination, image, NULL);
		encoded = CGImageDestinationFinalize(destination);
		CFRelease(destination);
	}
	if (image) CGImageRelease(image);
	if (provider) CGDataProviderRelease(provider);
	if (colorspace) CGColorSpaceRelease(colorspace);
	IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
	bool written = encoded && [(__bridge NSData *)png
		writeToFile:[NSString stringWithUTF8String:path] options:NSDataWritingAtomic error:NULL];
	if (png) CFRelease(png);
	return written;
}
#endif

#endif
