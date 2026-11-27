#ifndef WITTY_MACOS_CORE_FRAMEWORKS_H
#define WITTY_MACOS_CORE_FRAMEWORKS_H
#include <TargetConditionals.h>
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreVideo/CoreVideo.h>
#include <CoreVideo/CVPixelBuffer.h>
#include <QuartzCore/CALayer.h>
#include <IOSurface/IOSurfaceRef.h>
#include <dispatch/dispatch.h>
#include <os/log.h>
#include <os/signpost.h>
#if TARGET_OS_OSX
#include <Carbon/Carbon.h>
#endif
#endif
#endif
