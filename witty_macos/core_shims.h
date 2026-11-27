#include <stdbool.h>
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreVideo/CoreVideo.h>
#include <IOSurface/IOSurfaceRef.h>
#include <dispatch/dispatch.h>
#include <os/log.h>
#include <os/signpost.h>
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_ct_font_attribute_name(void) {
	return kCTFontAttributeName;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_cf_allocator_null(void) {
	return kCFAllocatorNull;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_cf_type_dictionary_key_callbacks(void) {
	return &kCFTypeDictionaryKeyCallBacks;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_cf_type_dictionary_value_callbacks(void) {
	return &kCFTypeDictionaryValueCallBacks;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_cf_type_array_callbacks(void) {
	return &kCFTypeArrayCallBacks;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_cf_character_set_create_with_range(long location, long length) {
	CFRange range = CFRangeMake(location, length);
	return (void*)CFCharacterSetCreateWithCharactersInRange(NULL, range);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_k_ct_font_open_type_feature_tag(void) {
	return kCTFontOpenTypeFeatureTag;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_k_ct_font_open_type_feature_value(void) {
	return kCTFontOpenTypeFeatureValue;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_k_ct_font_feature_settings_attribute(void) {
	return kCTFontFeatureSettingsAttribute;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_k_ct_typesetter_option_forced_embedding_level(void) {
	return kCTTypesetterOptionForcedEmbeddingLevel;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_k_ct_paragraph_style_attribute_name(void) {
	return kCTParagraphStyleAttributeName;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_k_ct_writing_direction_attribute_name(void) {
	return kCTWritingDirectionAttributeName;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_k_cf_null(void) {
	return kCFNull;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_ct_font_attribute(int attribute) {
	switch (attribute) {
		case 0: return kCTFontURLAttribute;
		case 1: return kCTFontNameAttribute;
		case 2: return kCTFontDisplayNameAttribute;
		case 3: return kCTFontFamilyNameAttribute;
		case 4: return kCTFontStyleNameAttribute;
		case 5: return kCTFontTraitsAttribute;
		case 6: return kCTFontVariationAttribute;
		case 7: return kCTFontSizeAttribute;
		case 8: return kCTFontMatrixAttribute;
		case 9: return kCTFontCascadeListAttribute;
		case 10: return kCTFontCharacterSetAttribute;
		case 11: return kCTFontLanguagesAttribute;
		case 12: return kCTFontBaselineAdjustAttribute;
		case 13: return kCTFontMacintoshEncodingsAttribute;
		case 14: return kCTFontFeaturesAttribute;
		case 15: return kCTFontFeatureSettingsAttribute;
		case 16: return kCTFontFixedAdvanceAttribute;
		case 17: return kCTFontOrientationAttribute;
		case 18: return kCTFontFormatAttribute;
		case 19: return kCTFontRegistrationScopeAttribute;
		case 20: return kCTFontPriorityAttribute;
		case 21: return kCTFontEnabledAttribute;
		case 22: return kCTFontDownloadableAttribute;
		case 23: return kCTFontDownloadedAttribute;
		case 24: return kCTFontVariationAxesAttribute;
		default: return NULL;
	}
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_ct_font_trait_key(int key) {
	switch (key) {
		case 0: return kCTFontSymbolicTrait;
		case 1: return kCTFontWeightTrait;
		case 2: return kCTFontWidthTrait;
		case 3: return kCTFontSlantTrait;
		default: return NULL;
	}
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_ct_font_variation_axis_key(int key) {
	switch (key) {
		case 0: return kCTFontVariationAxisIdentifierKey;
		case 1: return kCTFontVariationAxisMinimumValueKey;
		case 2: return kCTFontVariationAxisMaximumValueKey;
		case 3: return kCTFontVariationAxisDefaultValueKey;
		case 4: return kCTFontVariationAxisNameKey;
		case 5: return kCTFontVariationAxisHiddenKey;
		default: return NULL;
	}
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_cfattributedstring_replace_string(void *str_ptr, long location, long length, void *replacement_ptr) {
	if (!str_ptr || !replacement_ptr) return;
	CFAttributedStringReplaceString(
		(CFMutableAttributedStringRef)str_ptr,
		CFRangeMake(location, length),
		(CFStringRef)replacement_ptr
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_cfattributedstring_set_attribute(void *str_ptr, long location, long length, void *key_ptr, void *value_ptr) {
	if (!str_ptr || !key_ptr) return;
	CFAttributedStringSetAttribute(
		(CFMutableAttributedStringRef)str_ptr,
		CFRangeMake(location, length),
		(CFStringRef)key_ptr,
		(CFTypeRef)value_ptr
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_create_font(const char *name, double size) {
	if (!name) return NULL;
	CFStringRef font_name = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
	if (!font_name) return NULL;
	CTFontRef font = CTFontCreateWithName(font_name, size, NULL);
	CFRelease(font_name);
	return (void*)font;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_draw_text(CGContextRef ctx, const char *text, int text_len,
				  void *font, double x, double y,
				  double fg_r, double fg_g, double fg_b) {
	if (!ctx || !text || text_len <= 0 || !font) return;

	CFStringRef cfstr = CFStringCreateWithBytes(
		NULL, (const UInt8*)text, text_len,
		kCFStringEncodingUTF8, false);
	if (!cfstr) return;

	CGColorRef color = CGColorCreateSRGB(fg_r, fg_g, fg_b, 1.0);
	CFStringRef keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName };
	CFTypeRef vals[] = { (CTFontRef)font, color };
	CFDictionaryRef attrs = CFDictionaryCreate(
		NULL, (const void**)keys, (const void**)vals, 2,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFAttributedStringRef attr_str = attrs ? CFAttributedStringCreate(NULL, cfstr, attrs) : NULL;
	CTLineRef line = attr_str ? CTLineCreateWithAttributedString(attr_str) : NULL;

	if (line) {
		CGContextSetTextPosition(ctx, x, y);
		CTLineDraw(line, ctx);
		CFRelease(line);
	}
	if (attr_str) CFRelease(attr_str);
	if (attrs) CFRelease(attrs);
	if (color) CGColorRelease(color);
	CFRelease(cfstr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_ct_typesetter_create_line(void *typesetter_ptr, long location, long length) {
	if (!typesetter_ptr) return NULL;
	CFRange range = CFRangeMake(location, length);
	return (void*)CTTypesetterCreateLine((CTTypesetterRef)typesetter_ptr, range);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_ctrun_get_glyphs_all(void *run_ptr, void *out_glyphs) {
	if (!run_ptr || !out_glyphs) return;
	CTRunGetGlyphs((CTRunRef)run_ptr, CFRangeMake(0, 0), (CGGlyph *)out_glyphs);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_ctrun_get_advances_all(void *run_ptr, void *out_advances) {
	if (!run_ptr || !out_advances) return;
	CTRunGetAdvances((CTRunRef)run_ptr, CFRangeMake(0, 0), (CGSize *)out_advances);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_ctrun_get_positions_all(void *run_ptr, void *out_positions) {
	if (!run_ptr || !out_positions) return;
	CTRunGetPositions((CTRunRef)run_ptr, CFRangeMake(0, 0), (CGPoint *)out_positions);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_ctrun_get_string_indices_all(void *run_ptr, void *out_indices) {
	if (!run_ptr || !out_indices) return;
	CTRunGetStringIndices((CTRunRef)run_ptr, CFRangeMake(0, 0), (CFIndex *)out_indices);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_ctfont_get_bounding_rects_for_glyphs(
	void *font_ptr,
	unsigned int orientation,
	const uint16_t *glyphs,
	void *rects_ptr,
	size_t count,
	double *x_out,
	double *y_out,
	double *width_out,
	double *height_out
) {
	CGRect rect = CTFontGetBoundingRectsForGlyphs(
		(CTFontRef)font_ptr,
		(CTFontOrientation)orientation,
		(const CGGlyph *)glyphs,
		(CGRect *)rects_ptr,
		(CFIndex)count);
	*x_out = rect.origin.x;
	*y_out = rect.origin.y;
	*width_out = rect.size.width;
	*height_out = rect.size.height;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void *vt_ctfont_create_for_string(
	void *font_ptr,
	void *string_ptr,
	long location,
	long length
) {
	return (void *)CTFontCreateForString(
		(CTFontRef)font_ptr,
		(CFStringRef)string_ptr,
		CFRangeMake(location, length));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_ctparagraphstyle_create(void *settings_ptr, size_t count) {
	return (void*)CTParagraphStyleCreate((const CTParagraphStyleSetting *)settings_ptr, count);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_ctframesetter_create_frame(void *framesetter_ptr, long location, long length, void *path_ptr, void *attrs_ptr) {
	if (!framesetter_ptr || !path_ptr) return NULL;
	return (void*)CTFramesetterCreateFrame(
		(CTFramesetterRef)framesetter_ptr,
		CFRangeMake(location, length),
		(CGPathRef)path_ptr,
		(CFDictionaryRef)attrs_ptr
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_ctframe_get_line_origins(void *frame_ptr, long location, long length, void *points_ptr) {
	if (!frame_ptr || !points_ptr) return;
	CTFrameGetLineOrigins((CTFrameRef)frame_ptr, CFRangeMake(location, length), (CGPoint *)points_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_cgrect_is_null(double x, double y, double w, double h) {
	return CGRectIsNull(CGRectMake(x, y, w, h));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_cgpath_create_with_rect(double x, double y, double w, double h) {
	return (void*)CGPathCreateWithRect(CGRectMake(x, y, w, h), NULL);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_cgpath_create_mutable(void) {
	return (void*)CGPathCreateMutable();
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_cgpath_add_rect(void *path_ptr, double x, double y, double w, double h) {
	if (!path_ptr) return;
	CGPathAddRect((CGMutablePathRef)path_ptr, NULL, CGRectMake(x, y, w, h));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_cgpath_get_bounding_box(void *path_ptr, double *x, double *y, double *w, double *h) {
	if (!path_ptr || !x || !y || !w || !h) return;
	CGRect rect = CGPathGetBoundingBox((CGPathRef)path_ptr);
	*x = rect.origin.x;
	*y = rect.origin.y;
	*w = rect.size.width;
	*h = rect.size.height;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_cgcolorspace_create_device_gray(void) {
	return (void*)CGColorSpaceCreateDeviceGray();
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_cgcolorspace_create_device_rgb(void) {
	return (void*)CGColorSpaceCreateDeviceRGB();
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_cgcolorspace_create_named(int name_id) {
	CFStringRef name = NULL;
	switch (name_id) {
		case 0: name = kCGColorSpaceDisplayP3; break;
		case 1: name = kCGColorSpaceExtendedLinearDisplayP3; break;
		case 2: name = kCGColorSpaceSRGB; break;
		case 3: name = kCGColorSpaceLinearSRGB; break;
		case 4: name = kCGColorSpaceExtendedSRGB; break;
		case 5: name = kCGColorSpaceExtendedLinearSRGB; break;
		case 6: name = kCGColorSpaceGenericGrayGamma2_2; break;
		case 7: name = kCGColorSpaceLinearGray; break;
		case 8: name = kCGColorSpaceExtendedGray; break;
		case 9: name = kCGColorSpaceExtendedLinearGray; break;
		default: return NULL;
	}
	return (void*)CGColorSpaceCreateWithName(name);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_cgcolorspace_release(void *space_ptr) {
	if (!space_ptr) return;
	CGColorSpaceRelease((CGColorSpaceRef)space_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_cgbitmap_context_create(void *data, size_t width, size_t height,
								 size_t bits_per_component, size_t bytes_per_row,
								 void *space, unsigned int opts) {
	return (void*)CGBitmapContextCreate(
		data,
		width,
		height,
		bits_per_component,
		bytes_per_row,
		(CGColorSpaceRef)space,
		opts
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_cgcontext_set_text_matrix(void *ctx_ptr, double a, double b, double c, double d, double tx, double ty) {
	if (!ctx_ptr) return;
	CGContextSetTextMatrix((CGContextRef)ctx_ptr, CGAffineTransformMake(a, b, c, d, tx, ty));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_cgcontext_fill_rect(void *ctx_ptr, double x, double y, double w, double h) {
	if (!ctx_ptr) return;
	CGContextFillRect((CGContextRef)ctx_ptr, CGRectMake(x, y, w, h));
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_iosurface_create(int width, int height, unsigned int pixel_format, int bytes_per_element, void *colorspace_ptr) {
	CFNumberRef w = CFNumberCreate(NULL, kCFNumberIntType, &width);
	CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &height);
	CFNumberRef pf = CFNumberCreate(NULL, kCFNumberIntType, &pixel_format);
	CFNumberRef bpe = CFNumberCreate(NULL, kCFNumberIntType, &bytes_per_element);
	if (!w || !h || !pf || !bpe) {
		if (w) CFRelease(w);
		if (h) CFRelease(h);
		if (pf) CFRelease(pf);
		if (bpe) CFRelease(bpe);
		return NULL;
	}

	const void *keys[] = {
		kIOSurfaceWidth,
		kIOSurfaceHeight,
		kIOSurfacePixelFormat,
		kIOSurfaceBytesPerElement,
	};
	const void *vals[] = { w, h, pf, bpe };
	CFDictionaryRef dict = CFDictionaryCreate(
		NULL,
		keys,
		vals,
		4,
		&kCFTypeDictionaryKeyCallBacks,
		&kCFTypeDictionaryValueCallBacks
	);

	CFRelease(w);
	CFRelease(h);
	CFRelease(pf);
	CFRelease(bpe);

	if (!dict) return NULL;
	IOSurfaceRef surface = IOSurfaceCreate(dict);
	CFRelease(dict);
	if (!surface) return NULL;

	if (colorspace_ptr) {
		CFPropertyListRef serialized = CGColorSpaceCopyPropertyList((CGColorSpaceRef)colorspace_ptr);
		if (serialized) {
			IOSurfaceSetValue(surface, kIOSurfaceColorSpace, serialized);
			CFRelease(serialized);
		}
	}

	return (void*)surface;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_iosurface_deinit(void *surface_ptr) {
	if (!surface_ptr) return;
	IOSurfaceRef surface = (IOSurfaceRef)surface_ptr;
	IOSurfaceSetPurgeable(surface, kIOSurfacePurgeableEmpty, NULL);
	CFRelease(surface);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_iosurface_retain(void *surface_ptr) {
	if (!surface_ptr) return;
	CFRetain(surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_iosurface_release(void *surface_ptr) {
	if (!surface_ptr) return;
	CFRelease(surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_iosurface_set_color_space(void *surface_ptr, void *colorspace_ptr) {
	if (!surface_ptr || !colorspace_ptr) return;
	CFPropertyListRef serialized = CGColorSpaceCopyPropertyList((CGColorSpaceRef)colorspace_ptr);
	if (!serialized) return;
	IOSurfaceSetValue((IOSurfaceRef)surface_ptr, kIOSurfaceColorSpace, serialized);
	CFRelease(serialized);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_iosurface_lock(void *surface_ptr) {
	if (!surface_ptr) return;
	IOSurfaceLock((IOSurfaceRef)surface_ptr, 0, NULL);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_iosurface_unlock(void *surface_ptr) {
	if (!surface_ptr) return;
	IOSurfaceUnlock((IOSurfaceRef)surface_ptr, 0, NULL);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
size_t vt_iosurface_get_alloc_size(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetAllocSize((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
size_t vt_iosurface_get_width(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetWidth((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
size_t vt_iosurface_get_height(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetHeight((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
size_t vt_iosurface_get_bytes_per_element(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetBytesPerElement((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
size_t vt_iosurface_get_bytes_per_row(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetBytesPerRow((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_iosurface_get_base_address(void *surface_ptr) {
	if (!surface_ptr) return NULL;
	return IOSurfaceGetBaseAddress((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
size_t vt_iosurface_get_element_width(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetElementWidth((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
size_t vt_iosurface_get_element_height(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetElementHeight((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
unsigned int vt_iosurface_get_pixel_format(void *surface_ptr) {
	if (!surface_ptr) return 0;
	return IOSurfaceGetPixelFormat((IOSurfaceRef)surface_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_dispatch_get_main_queue(void) {
	return (void*)dispatch_get_main_queue();
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_dispatch_data_create(const void *data, size_t len, void *queue) {
	return (void*)dispatch_data_create(data, len, (dispatch_queue_t)queue, NULL);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_dispatch_release(void *obj) {
	if (!obj) return;
	dispatch_release((dispatch_object_t)obj);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_kca_gravity_top_left(void) {
	return CFSTR("topLeft");
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_kca_gravity_bottom_left(void) {
	return CFSTR("bottomLeft");
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
const void* vt_kca_gravity_center(void) {
	return CFSTR("center");
}
#endif

#if TARGET_OS_OSX
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_display_link_create_with_active_displays(void) {
	CVDisplayLinkRef link = NULL;
	if (CVDisplayLinkCreateWithActiveCGDisplays(&link) != kCVReturnSuccess) return NULL;
	return (void*)link;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_display_link_release(void *link_ptr) {
	if (!link_ptr) return;
	CVDisplayLinkRelease((CVDisplayLinkRef)link_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_display_link_start(void *link_ptr) {
	if (!link_ptr) return false;
	return CVDisplayLinkStart((CVDisplayLinkRef)link_ptr) == kCVReturnSuccess;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_display_link_stop(void *link_ptr) {
	if (!link_ptr) return false;
	return CVDisplayLinkStop((CVDisplayLinkRef)link_ptr) == kCVReturnSuccess;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_display_link_is_running(void *link_ptr) {
	if (!link_ptr) return false;
	return CVDisplayLinkIsRunning((CVDisplayLinkRef)link_ptr) != 0;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_display_link_set_current_display(void *link_ptr, unsigned int display_id) {
	if (!link_ptr) return false;
	return CVDisplayLinkSetCurrentCGDisplay((CVDisplayLinkRef)link_ptr, display_id) == kCVReturnSuccess;
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_display_link_set_output_callback(
	void *link_ptr,
	void *callback,
	void *context
) {
	if (!link_ptr || !callback) return false;
	return CVDisplayLinkSetOutputCallback(
		(CVDisplayLinkRef)link_ptr,
		(CVDisplayLinkOutputCallback)callback,
		context
	) == kCVReturnSuccess;
}
#endif

#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void* vt_os_log_create(const char *subsystem, const char *category) {
	return (void*)os_log_create(subsystem, category);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_os_release(void *obj) {
	if (!obj) return;
	os_release(obj);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_os_log_type_enabled(void *log_ptr, unsigned char typ) {
	if (!log_ptr) return false;
	return os_log_type_enabled((os_log_t)log_ptr, (os_log_type_t)typ);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_os_log_with_type_str(void *log_ptr, unsigned char typ, const char *msg) {
	if (!log_ptr || !msg) return;
	os_log_with_type((os_log_t)log_ptr, (os_log_type_t)typ, "%{public}s", msg);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
bool vt_os_signpost_enabled(void *log_ptr) {
	if (!log_ptr) return false;
	return os_signpost_enabled((os_log_t)log_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
unsigned long long vt_os_signpost_id_generate(void *log_ptr) {
	if (!log_ptr) return 0;
	return (unsigned long long)os_signpost_id_generate((os_log_t)log_ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
unsigned long long vt_os_signpost_id_for_pointer(void *log_ptr, void *ptr) {
	if (!log_ptr) return 0;
	return (unsigned long long)os_signpost_id_make_with_pointer((os_log_t)log_ptr, ptr);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static void vt_os_signpost_emit_with_name(void *log_ptr, unsigned long long id, const char *name, unsigned char typ) {
	if (!log_ptr || !name) return;
	uint8_t buf[2] = {0, 0};
	_os_signpost_emit_with_name_impl(
		&__dso_handle,
		(os_log_t)log_ptr,
		(os_signpost_type_t)typ,
		(os_signpost_id_t)id,
		name,
		"",
		buf,
		(uint32_t)sizeof(buf)
	);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_os_signpost_event_emit(void *log_ptr, unsigned long long id, const char *name) {
	vt_os_signpost_emit_with_name(log_ptr, id, name, 0);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_os_signpost_interval_begin(void *log_ptr, unsigned long long id, const char *name) {
	vt_os_signpost_emit_with_name(log_ptr, id, name, 1);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
void vt_os_signpost_interval_end(void *log_ptr, unsigned long long id, const char *name) {
	vt_os_signpost_emit_with_name(log_ptr, id, name, 2);
}
#endif
