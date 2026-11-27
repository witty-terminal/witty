module witty_macos

import log

$if macos || ios {
	#flag -framework Foundation
	#flag -framework Metal
	#flag -framework QuartzCore
	#flag -lobjc
	#flag -I@VEXEROOT/vlib/macos
	#flag -I@VMODROOT/macos
	#include "metal_bridge.h"
	#insert "@VMODROOT/witty_macos/string_abi.h"

	type ObjId = voidptr

	type Sel = voidptr

	type ObjCRect = C.macos_rect

	type ObjCPoint = C.witty_macos_point

	type ObjCSize = C.witty_macos_size

	type MetalClearColor = C.witty_macos_clear_color

	pub struct C.macos_rect {
	pub mut:
		x      f64
		y      f64
		width  f64
		height f64
	}

	struct C.witty_macos_point {
	mut:
		x f64
		y f64
	}

	struct C.witty_macos_size {
	mut:
		width  f64
		height f64
	}

	struct C.witty_macos_clear_color {
	mut:
		red   f64
		green f64
		blue  f64
		alpha f64
	}

	fn C.macos_objc_msg_id0(obj ObjId, selector Sel) ObjId

	fn C.macos_objc_msg_id1(obj ObjId, selector Sel, a0 voidptr) ObjId
	fn C.witty_macos_nsstring(bytes &u8, length uint) ObjId
	fn C.witty_macos_utf8_length(value ObjId) uint

	fn C.macos_objc_msg_id2(obj ObjId, selector Sel, a0 voidptr, a1 voidptr) ObjId

	fn C.macos_objc_msg_id3(obj ObjId, selector Sel, a0 voidptr, a1 voidptr, a2 voidptr) ObjId

	fn C.macos_objc_msg_id_rect(obj ObjId, selector Sel, rect ObjCRect) ObjId

	fn C.macos_objc_msg_id_rect_u64_u64_bool(obj ObjId, selector Sel, rect ObjCRect, a1 u64, a2 u64, a3 bool) ObjId

	fn C.macos_objc_msg_id_obj_sel_obj(obj ObjId, selector Sel, a0 voidptr, a1 voidptr, a2 voidptr) ObjId

	fn C.macos_objc_msg_id_f64(obj ObjId, selector Sel, a0 f64) ObjId

	fn C.macos_objc_msg_id_u64(obj ObjId, selector Sel, a0 u64) ObjId

	fn C.macos_objc_msg_void0(obj ObjId, selector Sel)

	fn C.macos_objc_msg_void1(obj ObjId, selector Sel, a0 voidptr)

	fn C.macos_objc_msg_void2(obj ObjId, selector Sel, a0 voidptr, a1 voidptr)

	fn C.macos_objc_msg_void_bool(obj ObjId, selector Sel, a0 bool)

	fn C.macos_objc_msg_void_u64(obj ObjId, selector Sel, a0 u64)

	fn C.macos_objc_msg_void_f64(obj ObjId, selector Sel, a0 f64)

	fn C.macos_objc_msg_void_rect(obj ObjId, selector Sel, rect ObjCRect)

	fn C.macos_objc_msg_bool0(obj ObjId, selector Sel) bool

	fn C.macos_objc_msg_bool1(obj ObjId, selector Sel, a0 voidptr) bool

	fn C.macos_objc_msg_i64(obj ObjId, selector Sel) i64

	fn C.macos_objc_msg_u64(obj ObjId, selector Sel) u64

	fn C.macos_objc_msg_f64(obj ObjId, selector Sel) f64

	fn C.macos_objc_msg_rect(obj ObjId, selector Sel) ObjCRect

	fn C.macos_objc_get_class(name &char) ObjId

	fn C.macos_objc_get_protocol(name &char) ObjId

	fn C.macos_sel_register_name(name &char) Sel

	fn C.macos_objc_allocate_class_pair(superclass ObjId, name &char, extra_bytes uint) ObjId

	fn C.macos_objc_register_class_pair(cls ObjId)

	fn C.macos_class_add_method(cls ObjId, name Sel, imp voidptr, types &char) bool

	fn C.macos_class_add_ivar(cls ObjId, name &char, size uint, alignment u8, types &char) bool

	fn C.macos_class_add_protocol(cls ObjId, protocol ObjId) bool

	fn C.macos_objc_set_ptr_ivar(obj ObjId, name &char, value voidptr)

	fn C.macos_objc_get_ptr_ivar(obj ObjId, name &char) voidptr

	fn C.macos_set_associated_object(obj ObjId, key voidptr, value ObjId, policy uint)

	fn C.macos_get_associated_object(obj ObjId, key voidptr) ObjId

	fn C.witty_macos_objc_msg_point0(obj ObjId, selector Sel) ObjCPoint

	fn C.witty_macos_objc_msg_point_point_obj(obj ObjId, selector Sel, point ObjCPoint, a1 voidptr) ObjCPoint

	fn C.witty_macos_objc_msg_bool2(obj ObjId, selector Sel, a0 voidptr, a1 voidptr) bool

	fn C.witty_macos_objc_msg_bool_u64(obj ObjId, selector Sel, a0 u64) bool

	fn C.witty_macos_objc_msg_id_rect_u64_obj_obj(obj ObjId, selector Sel, rect ObjCRect, options u64, owner ObjId, user_info ObjId) ObjId

	fn C.witty_macos_objc_msg_super_bool0(obj ObjId, selector Sel) bool

	fn C.witty_macos_objc_msg_super_void0(obj ObjId, selector Sel)

	fn C.witty_macos_objc_msg_super_void1(obj ObjId, selector Sel, value ObjId)

	fn C.witty_macos_objc_msg_void_size(obj ObjId, selector Sel, size ObjCSize)

	fn C.witty_macos_objc_msg_void_clear_color(obj ObjId, selector Sel, color MetalClearColor)

	fn C.witty_macos_set_window_background_blur(window voidptr, radius int)

	fn C.witty_macos_observe(center voidptr, observer voidptr, selector voidptr, name voidptr, object voidptr)
	fn C.witty_macos_dispatch_main_weak(view voidptr, callback voidptr)

	fn C.witty_metal_new_buffer_length(device voidptr, length uint, options u64) voidptr

	fn C.witty_metal_new_buffer_bytes(device voidptr, bytes voidptr, length uint, options u64) voidptr

	fn C.witty_metal_buffer_length(buffer voidptr) uint

	fn C.witty_metal_buffer_contents(buffer voidptr) voidptr

	fn C.witty_metal_buffer_did_modify(buffer voidptr, length uint)

	fn C.witty_metal_new_texture(device voidptr, pixel_format u64, width uint, height uint, resource_options u64, usage u64) voidptr

	fn C.witty_metal_texture_replace_region(texture voidptr, x uint, y uint, width uint, height uint, bytes voidptr, bytes_per_row uint)

	fn C.witty_metal_texture_get_bytes(texture voidptr, bytes voidptr, bytes_per_row uint, x uint, y uint, width uint, height uint)

	fn C.witty_metal_command_buffer_commit(command_buffer voidptr)

	fn C.witty_metal_command_buffer_wait(command_buffer voidptr)

	fn C.witty_metal_command_buffer_status(command_buffer voidptr) u64

	fn C.witty_metal_command_buffer_add_completed_handler(command_buffer voidptr, callback voidptr, renderer voidptr, target voidptr) bool

	fn C.witty_metal_command_buffer_invoke_completion(command_buffer voidptr, callback voidptr, renderer voidptr, target voidptr, sync_ bool)

	fn C.witty_metal_render_pass_descriptor() voidptr

	fn C.witty_metal_render_pass_set_attachment(descriptor voidptr, index uint, texture voidptr, has_clear_color bool, color MetalClearColor)

	fn C.witty_metal_encoder_set_pipeline(encoder voidptr, pipeline voidptr)

	fn C.witty_metal_encoder_set_buffer(encoder voidptr, buffer voidptr, index uint)

	fn C.witty_metal_encoder_set_texture(encoder voidptr, texture voidptr, index uint)

	fn C.witty_metal_encoder_set_sampler(encoder voidptr, sampler voidptr, index uint)

	fn C.witty_metal_encoder_draw(encoder voidptr, primitive u64, vertex_count uint, instance_count uint)

	fn C.witty_metal_new_sampler(device voidptr, min_filter u64, mag_filter u64, s_address_mode u64, t_address_mode u64) voidptr

	fn C.witty_metal_new_iosurface_texture(device voidptr, surface voidptr, pixel_format u64, width uint, height uint, resource_options u64, usage u64) voidptr

	fn C.witty_metal_library_data(device voidptr, data voidptr, error &voidptr) voidptr
	fn C.witty_metal_dispatch_data(data voidptr, length uint) voidptr
	fn C.witty_metal_dispatch_release(data voidptr)
	fn C.witty_metal_error_description(error voidptr) &char

	fn C.witty_metal_new_library_source(device voidptr, source &char, length uint) voidptr

	fn C.witty_metal_new_pipeline(device voidptr, vertex_library voidptr, fragment_library voidptr, vertex_name &char, vertex_name_length uint, fragment_name &char, fragment_name_length uint, attributes &C.witty_metal_vertex_attribute, attribute_count uint, vertex_stride uint, step_function u64, attachments &C.witty_metal_pipeline_attachment, attachment_count uint) voidptr

	fn C.witty_metal_iosurface_layer_new() voidptr

	fn C.witty_metal_iosurface_layer_set_display_callback(layer voidptr, callback voidptr, context voidptr)

	fn C.witty_metal_iosurface_layer_set_surface(layer voidptr, surface voidptr) bool

	fn C.witty_metal_iosurface_layer_set_surface_sync(layer voidptr, surface voidptr)

	fn C.witty_macos_is_main_thread() bool

	fn C.witty_macos_is_at_least_version(major i64, minor i64, patch i64) bool

	fn C.witty_macos_user_directory(directory u64) &char

	fn C.witty_macos_dispatch_main(fnptr voidptr, ctx voidptr)

	fn C.witty_macos_string_task_new(view voidptr, text &char) &C.witty_macos_string_task

	fn C.witty_macos_string_task_free(task &C.witty_macos_string_task)

	struct C.witty_macos_string_task {
		view voidptr
		text &char
	}

	pub struct C.witty_metal_vertex_attribute {
	pub mut:
		format u64
		offset uint
	}

	pub struct C.witty_metal_pipeline_attachment {
	pub mut:
		pixel_format     u64
		blending_enabled bool
	}

	pub struct MetalVertexAttribute {
	pub:
		format u64
		offset uint
	}

	pub struct MetalPipelineAttachment {
	pub:
		pixel_format     u64
		blending_enabled bool = true
	}

	fn C.MTLCreateSystemDefaultDevice() ObjId

	fn C.vt_ct_font_attribute_name() voidptr

	fn C.vt_create_font(name &char, size f64) voidptr

	fn C.vt_draw_text(ctx voidptr, text &u8, text_len int, font voidptr, x f64, y f64, fg_r f64, fg_g f64, fg_b f64)

	@[inline]
	fn nil_obj() ObjId {
		return unsafe { nil }
	}

	@[inline]
	fn is_nil(obj ObjId) bool {
		return obj == unsafe { nil }
	}

	@[inline]
	fn cstr(s string) &char {
		return &char(s.str)
	}

	@[inline]
	fn get_class(name string) ObjId {
		return ObjId(C.macos_objc_get_class(cstr(name)))
	}

	@[inline]
	fn get_protocol(name string) ObjId {
		return C.macos_objc_get_protocol(cstr(name))
	}

	@[inline]
	fn sel(name string) Sel {
		return C.macos_sel_register_name(cstr(name))
	}

	@[inline]
	fn objc_rect(x f64, y f64, width f64, height f64) ObjCRect {
		return ObjCRect{
			x:      x
			y:      y
			width:  width
			height: height
		}
	}

	@[inline]
	fn objc_size(width f64, height f64) ObjCSize {
		return ObjCSize{
			width:  width
			height: height
		}
	}

	@[inline]
	fn msg_id(obj ObjId, selector string) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id0(obj, sel(selector))
	}

	@[inline]
	fn msg_id1(obj ObjId, selector string, a0 ObjId) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id1(obj, sel(selector), a0)
	}

	@[inline]
	fn msg_id2(obj ObjId, selector string, a0 ObjId, a1 ObjId) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id2(obj, sel(selector), a0, a1)
	}

	@[inline]
	fn msg_id3(obj ObjId, selector string, a0 ObjId, a1 ObjId, a2 ObjId) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id3(obj, sel(selector), a0, a1, a2)
	}

	@[inline]
	fn msg_id_rect(obj ObjId, selector string, rect ObjCRect) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id_rect(obj, sel(selector), rect)
	}

	@[inline]
	fn msg_id_rect_u64_u64_bool(obj ObjId, selector string, rect ObjCRect, a1 u64, a2 u64, a3 bool) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id_rect_u64_u64_bool(obj, sel(selector), rect, a1, a2, a3)
	}

	@[inline]
	fn msg_id_rect_u64_obj_obj(obj ObjId, selector string, rect ObjCRect, options u64, owner ObjId, user_info ObjId) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.witty_macos_objc_msg_id_rect_u64_obj_obj(obj, sel(selector), rect, options, owner, user_info)
	}

	@[inline]
	fn msg_super_bool(obj ObjId, selector string) bool {
		if is_nil(obj) {
			return false
		}
		return C.witty_macos_objc_msg_super_bool0(obj, sel(selector))
	}

	@[inline]
	fn msg_super_void(obj ObjId, selector string) {
		if !is_nil(obj) {
			C.witty_macos_objc_msg_super_void0(obj, sel(selector))
		}
	}

	@[inline]
	fn msg_super_void1(obj ObjId, selector string, value ObjId) {
		if !is_nil(obj) {
			C.witty_macos_objc_msg_super_void1(obj, sel(selector), value)
		}
	}

	@[inline]
	fn msg_id_obj_sel_obj(obj ObjId, selector string, a0 ObjId, a1 Sel, a2 ObjId) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id_obj_sel_obj(obj, sel(selector), a0, a1, a2)
	}

	@[inline]
	fn msg_id_f64(obj ObjId, selector string, a0 f64) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id_f64(obj, sel(selector), a0)
	}

	@[inline]
	fn msg_id_u64(obj ObjId, selector string, a0 u64) ObjId {
		if is_nil(obj) {
			return nil_obj()
		}
		return C.macos_objc_msg_id_u64(obj, sel(selector), a0)
	}

	@[inline]
	fn msg_void(obj ObjId, selector string) {
		if !is_nil(obj) {
			C.macos_objc_msg_void0(obj, sel(selector))
		}
	}

	@[inline]
	fn msg_void1(obj ObjId, selector string, a0 ObjId) {
		if !is_nil(obj) {
			C.macos_objc_msg_void1(obj, sel(selector), a0)
		}
	}

	@[inline]
	fn msg_void2(obj ObjId, selector string, a0 ObjId, a1 ObjId) {
		if !is_nil(obj) {
			C.macos_objc_msg_void2(obj, sel(selector), a0, a1)
		}
	}

	@[inline]
	fn msg_void_bool(obj ObjId, selector string, a0 bool) {
		if !is_nil(obj) {
			C.macos_objc_msg_void_bool(obj, sel(selector), a0)
		}
	}

	@[inline]
	fn msg_void_u64(obj ObjId, selector string, a0 u64) {
		if !is_nil(obj) {
			C.macos_objc_msg_void_u64(obj, sel(selector), a0)
		}
	}

	@[inline]
	fn msg_void_f64(obj ObjId, selector string, a0 f64) {
		if !is_nil(obj) {
			C.macos_objc_msg_void_f64(obj, sel(selector), a0)
		}
	}

	@[inline]
	fn msg_void_rect(obj ObjId, selector string, rect ObjCRect) {
		if !is_nil(obj) {
			C.macos_objc_msg_void_rect(obj, sel(selector), rect)
		}
	}

	@[inline]
	fn msg_void_size(obj ObjId, selector string, size ObjCSize) {
		if !is_nil(obj) {
			C.witty_macos_objc_msg_void_size(obj, sel(selector), size)
		}
	}

	@[inline]
	fn msg_bool(obj ObjId, selector string) bool {
		if is_nil(obj) {
			return false
		}
		return C.macos_objc_msg_bool0(obj, sel(selector))
	}

	@[inline]
	fn msg_bool1(obj ObjId, selector string, a0 ObjId) bool {
		if is_nil(obj) {
			return false
		}
		return C.macos_objc_msg_bool1(obj, sel(selector), a0)
	}

	@[inline]
	fn msg_bool2(obj ObjId, selector string, a0 ObjId, a1 ObjId) bool {
		if is_nil(obj) {
			return false
		}
		return C.witty_macos_objc_msg_bool2(obj, sel(selector), a0, a1)
	}

	@[inline]
	fn msg_bool_u64(obj ObjId, selector string, a0 u64) bool {
		if is_nil(obj) {
			return false
		}
		return C.witty_macos_objc_msg_bool_u64(obj, sel(selector), a0)
	}

	@[inline]
	fn msg_u64(obj ObjId, selector string) u64 {
		if is_nil(obj) {
			return 0
		}
		return C.macos_objc_msg_u64(obj, sel(selector))
	}

	@[inline]
	fn msg_i64(obj ObjId, selector string) i64 {
		if is_nil(obj) {
			return 0
		}
		return C.macos_objc_msg_i64(obj, sel(selector))
	}

	@[inline]
	fn msg_f64(obj ObjId, selector string) f64 {
		if is_nil(obj) {
			return 0
		}
		return C.macos_objc_msg_f64(obj, sel(selector))
	}

	// set_window_background_blur applies the private CoreGraphics background blur
	// radius to an NSWindow. The caller is responsible for checking transparency.

	fn msg_rect(obj ObjId, selector string) ObjCRect {
		if is_nil(obj) {
			return objc_rect(0, 0, 0, 0)
		}
		return C.macos_objc_msg_rect(obj, sel(selector))
	}

	@[inline]
	fn msg_point(obj ObjId, selector string) ObjCPoint {
		if is_nil(obj) {
			return ObjCPoint{}
		}
		return C.witty_macos_objc_msg_point0(obj, sel(selector))
	}

	@[inline]
	fn msg_point_point_obj(obj ObjId, selector string, point ObjCPoint, other ObjId) ObjCPoint {
		if is_nil(obj) {
			return ObjCPoint{}
		}
		return C.witty_macos_objc_msg_point_point_obj(obj, sel(selector), point, other)
	}

	@[inline]
	fn nsstring(s string) ObjId {
		return C.witty_macos_nsstring(s.str, uint(s.len))
	}

	fn objc_utf8_string(obj ObjId) string {
		if is_nil(obj) {
			return ''
		}
		ptr := &char(C.macos_objc_msg_id0(obj, sel('UTF8String')))
		if ptr == unsafe { nil } {
			return ''
		}
		return unsafe { ptr.vstring_with_len(int(C.witty_macos_utf8_length(obj))).clone() }
	}

	// home_directory_for_current_user returns the current user's home through
	// NSFileManager. This is the reliable lookup for multi-user macOS sessions.
	pub fn home_directory_for_current_user() ?string {
		manager := msg_id(get_class('NSFileManager'), 'defaultManager')
		if is_nil(manager) {
			return none
		}
		home_url := msg_id(manager, 'homeDirectoryForCurrentUser')
		if is_nil(home_url) {
			return none
		}
		home_path := msg_id(home_url, 'path')
		if is_nil(home_path) {
			return none
		}
		return objc_utf8_string(home_path)
	}

	// AutoreleasePool wraps an NSAutoreleasePool. Objects autoreleased while the
	// pool is alive are released when it is drained.
	pub struct AutoreleasePool {
	mut:
		pool ObjId = unsafe { nil }
	}

	// AutoreleasePool.init pushes a new pool onto the current thread's stack.
	pub fn AutoreleasePool.init() AutoreleasePool {
		return AutoreleasePool{
			pool: msg_id(alloc('NSAutoreleasePool'), 'init')
		}
	}

	// deinit drains the pool, releasing everything autoreleased into it.
	pub fn (mut self AutoreleasePool) deinit() {
		if is_nil(self.pool) {
			return
		}
		msg_void(self.pool, 'drain')
		self.pool = unsafe { nil }
	}

	// process_arguments returns NSProcessInfo.processInfo.arguments. Cocoa owns
	// the array and NSString values, so clone each UTF-8 projection for the caller.
	pub fn process_arguments() []string {
		pool := msg_id(alloc('NSAutoreleasePool'), 'init')
		defer { msg_void(pool, 'drain') }
		info := msg_id(get_class('NSProcessInfo'), 'processInfo')
		if is_nil(info) {
			return []string{}
		}
		values := msg_id(info, 'arguments')
		if is_nil(values) {
			return []string{}
		}
		count := uint(msg_u64(values, 'count'))
		mut result := []string{cap: int(count)}
		for i in uint(0) .. count {
			value := msg_id_u64(values, 'objectAtIndex:', u64(i))
			result << if is_nil(value) { '' } else { objc_utf8_string(value) }
		}
		return result
	}

	// is_at_least_version checks the running macOS version through NSProcessInfo.
	pub fn is_at_least_version(major i64, minor i64, patch i64) bool {
		return C.witty_macos_is_at_least_version(major, minor, patch)
	}

	// user_directory returns an NSSearchPathDirectory in the user domain. The
	// Foundation lookup also creates the base directory, matching URLForDirectory.
	pub fn user_directory(directory u64) ?string {
		path := C.witty_macos_user_directory(directory)
		if path == unsafe { nil } {
			return none
		}
		defer { C.free(path) }
		return unsafe { path.vstring().clone() }
	}

	// SystemLocale contains the language and country components reported by
	// NSLocale.currentLocale.
	pub struct SystemLocale {
	pub:
		language string
		country  string
	}

	// system_locale returns the current Cocoa locale used to seed LANG for app
	// launches where the parent process did not provide one.
	pub fn system_locale() ?SystemLocale {
		pool := msg_id(alloc('NSAutoreleasePool'), 'init')
		defer { msg_void(pool, 'drain') }
		locale := msg_id(get_class('NSLocale'), 'currentLocale')
		if is_nil(locale) {
			return none
		}
		language_obj := msg_id(locale, 'languageCode')
		country_obj := msg_id(locale, 'countryCode')
		if is_nil(language_obj) || is_nil(country_obj) {
			return none
		}
		return SystemLocale{
			language: objc_utf8_string(language_obj)
			country:  objc_utf8_string(country_obj)
		}
	}

	// preferred_languages returns NSLocale.preferredLanguages in priority order.
	pub fn preferred_languages() []string {
		pool := msg_id(alloc('NSAutoreleasePool'), 'init')
		defer { msg_void(pool, 'drain') }
		values := msg_id(get_class('NSLocale'), 'preferredLanguages')
		if is_nil(values) {
			return []string{}
		}
		count := int(msg_u64(values, 'count'))
		mut result := []string{cap: count}
		for i in 0 .. count {
			value := msg_id_u64(values, 'objectAtIndex:', u64(i))
			if is_nil(value) {
				continue
			}
			result << objc_utf8_string(value)
		}
		return result
	}

	fn alloc(class_name string) ObjId {
		return msg_id(get_class(class_name), 'alloc')
	}

	fn new_obj(class_name string) ObjId {
		return msg_id(get_class(class_name), 'new')
	}

	pub fn metal_install_iosurface_layer(view voidptr, layer voidptr, content_scale f64) {
		if is_nil(view) || is_nil(layer) {
			return
		}
		bounds := msg_rect(ObjId(view), 'bounds')
		msg_void_rect(ObjId(layer), 'setFrame:', bounds)
		$if macos {
			msg_void1(ObjId(view), 'setLayer:', ObjId(layer))
			msg_void_bool(ObjId(view), 'setWantsLayer:', true)
		} $else $if ios {
			view_layer := msg_id(ObjId(view), 'layer')
			msg_void1(view_layer, 'addSublayer:', ObjId(layer))
		}
		msg_void_bool(ObjId(view), 'setClipsToBounds:', true)
		msg_void_f64(ObjId(layer), 'setContentsScale:', content_scale)
		msg_void_bool(ObjId(layer), 'setNeedsDisplayOnBoundsChange:', true)
	}

	// metal_layer_surface_size returns the drawable dimensions derived from the
	// layer bounds and its backing scale.
	pub fn metal_layer_surface_size(layer voidptr) (f64, f64) {
		if is_nil(layer) {
			return 0, 0
		}
		bounds := msg_rect(ObjId(layer), 'bounds')
		scale := msg_f64(ObjId(layer), 'contentsScale')
		return bounds.width * scale, bounds.height * scale
	}

	pub fn metal_system_default_device() voidptr {
		return C.MTLCreateSystemDefaultDevice()
	}

	pub fn metal_new_command_queue(device voidptr) voidptr {
		return msg_id(ObjId(device), 'newCommandQueue')
	}

	pub fn metal_new_buffer_length(device voidptr, length uint, options u64) voidptr {
		return C.witty_metal_new_buffer_length(device, length, options)
	}

	pub fn metal_new_buffer_bytes(device voidptr, data []u8, options u64) voidptr {
		mut bytes := voidptr(unsafe { nil })
		if data.len > 0 {
			bytes = voidptr(data.data)
		}
		return C.witty_metal_new_buffer_bytes(device, bytes, uint(data.len), options)
	}

	pub fn metal_new_buffer_raw(device voidptr, data voidptr, length uint, options u64) voidptr {
		return C.witty_metal_new_buffer_bytes(device, data, length, options)
	}

	pub fn metal_buffer_length(buffer voidptr) uint {
		return C.witty_metal_buffer_length(buffer)
	}

	pub fn metal_buffer_contents(buffer voidptr) voidptr {
		return C.witty_metal_buffer_contents(buffer)
	}

	pub fn metal_buffer_did_modify(buffer voidptr, length uint) {
		C.witty_metal_buffer_did_modify(buffer, length)
	}

	pub fn metal_new_texture(device voidptr, pixel_format u64, width uint, height uint, resource_options u64, usage u64) voidptr {
		return C.witty_metal_new_texture(device, pixel_format, width, height, resource_options, usage)
	}

	pub fn metal_texture_replace_region(texture voidptr, x uint, y uint, width uint, height uint, data []u8, bytes_per_row uint) {
		if data.len == 0 {
			return
		}
		C.witty_metal_texture_replace_region(texture, x, y, width, height, voidptr(data.data), bytes_per_row)
	}

	pub fn metal_texture_get_bytes(texture voidptr, mut data []u8, bytes_per_row uint, x uint, y uint, width uint, height uint) {
		if data.len == 0 {
			return
		}
		C.witty_metal_texture_get_bytes(texture, voidptr(data.data), bytes_per_row, x, y, width, height)
	}

	pub fn metal_command_buffer_commit(command_buffer voidptr) {
		C.witty_metal_command_buffer_commit(command_buffer)
	}

	pub fn metal_command_buffer_wait(command_buffer voidptr) {
		C.witty_metal_command_buffer_wait(command_buffer)
	}

	pub fn metal_command_buffer_status(command_buffer voidptr) u64 {
		return C.witty_metal_command_buffer_status(command_buffer)
	}

	pub fn metal_command_buffer_add_completed_handler(command_buffer voidptr, callback voidptr, renderer voidptr, target voidptr) bool {
		return C.witty_metal_command_buffer_add_completed_handler(command_buffer, callback, renderer,
			target)
	}

	pub fn metal_command_buffer_invoke_completion(command_buffer voidptr, callback voidptr, renderer voidptr, target voidptr, sync_ bool) {
		C.witty_metal_command_buffer_invoke_completion(command_buffer, callback, renderer, target,
			sync_)
	}

	pub fn metal_render_pass_descriptor() voidptr {
		return C.witty_metal_render_pass_descriptor()
	}

	pub fn metal_render_pass_set_attachment(descriptor voidptr, index uint, texture voidptr, clear_color ?[4]f64) {
		if color := clear_color {
			C.witty_metal_render_pass_set_attachment(descriptor, index, texture, true, MetalClearColor{
				red:   color[0]
				green: color[1]
				blue:  color[2]
				alpha: color[3]
			})
		} else {
			C.witty_metal_render_pass_set_attachment(descriptor, index, texture, false, MetalClearColor{})
		}
	}

	pub fn metal_encoder_set_pipeline(encoder voidptr, pipeline voidptr) {
		C.witty_metal_encoder_set_pipeline(encoder, pipeline)
	}

	pub fn metal_encoder_set_buffer(encoder voidptr, buffer voidptr, index uint) {
		C.witty_metal_encoder_set_buffer(encoder, buffer, index)
	}

	pub fn metal_encoder_set_texture(encoder voidptr, texture voidptr, index uint) {
		C.witty_metal_encoder_set_texture(encoder, texture, index)
	}

	pub fn metal_encoder_set_sampler(encoder voidptr, sampler voidptr, index uint) {
		C.witty_metal_encoder_set_sampler(encoder, sampler, index)
	}

	pub fn metal_encoder_draw(encoder voidptr, primitive u64, vertex_count uint, instance_count uint) {
		C.witty_metal_encoder_draw(encoder, primitive, vertex_count, instance_count)
	}

	pub fn metal_new_sampler(device voidptr, min_filter u64, mag_filter u64, s_address_mode u64, t_address_mode u64) voidptr {
		return C.witty_metal_new_sampler(device, min_filter, mag_filter, s_address_mode, t_address_mode)
	}

	pub fn metal_new_iosurface_texture(device voidptr, surface voidptr, pixel_format u64, width uint, height uint, resource_options u64, usage u64) voidptr {
		return C.witty_metal_new_iosurface_texture(device, surface, pixel_format, width, height, resource_options, usage)
	}

	pub fn metal_new_library_source(device voidptr, source string) voidptr {
		return C.witty_metal_new_library_source(device, &char(source.str), uint(source.len))
	}

	pub fn metal_new_pipeline(device voidptr, vertex_library voidptr, fragment_library voidptr, vertex_name string, fragment_name string, attributes []MetalVertexAttribute, vertex_stride uint, step_function u64, attachments []MetalPipelineAttachment) voidptr {
		mut c_attributes := []C.witty_metal_vertex_attribute{cap: attributes.len}
		for attribute in attributes {
			c_attributes << C.witty_metal_vertex_attribute{
				format: attribute.format
				offset: attribute.offset
			}
		}
		mut attrs := unsafe { &C.witty_metal_vertex_attribute(nil) }
		if attributes.len > 0 {
			unsafe {
				attrs = &c_attributes[0]
			}
		}
		mut c_attachments := []C.witty_metal_pipeline_attachment{cap: attachments.len}
		for attachment in attachments {
			c_attachments << C.witty_metal_pipeline_attachment{
				pixel_format:     attachment.pixel_format
				blending_enabled: attachment.blending_enabled
			}
		}
		mut attachment_ptr := unsafe { &C.witty_metal_pipeline_attachment(nil) }
		if attachments.len > 0 {
			unsafe {
				attachment_ptr = &c_attachments[0]
			}
		}
		return C.witty_metal_new_pipeline(device, vertex_library, fragment_library, &char(vertex_name.str), uint(vertex_name.len), &char(fragment_name.str), uint(fragment_name.len), attrs, uint(attributes.len), vertex_stride, step_function, attachment_ptr, uint(attachments.len))
	}

	pub fn metal_iosurface_layer_new() voidptr {
		return C.witty_metal_iosurface_layer_new()
	}

	pub fn metal_iosurface_layer_set_display_callback(layer voidptr, callback voidptr, context voidptr) {
		C.witty_metal_iosurface_layer_set_display_callback(layer, callback, context)
	}

	pub fn metal_iosurface_layer_set_surface(layer voidptr, surface voidptr) bool {
		return C.witty_metal_iosurface_layer_set_surface(layer, surface)
	}

	pub fn metal_iosurface_layer_set_surface_sync(layer voidptr, surface voidptr) {
		C.witty_metal_iosurface_layer_set_surface_sync(layer, surface)
	}

	pub fn metal_create_command_buffer(queue voidptr) voidptr {
		return msg_id(ObjId(queue), 'commandBuffer')
	}

	pub fn metal_create_encoder(cmd_buf voidptr, pass voidptr) voidptr {
		if is_nil(cmd_buf) || is_nil(pass) {
			return unsafe { nil }
		}
		return msg_id1(ObjId(cmd_buf), 'renderCommandEncoderWithDescriptor:', ObjId(pass))
	}

	pub fn metal_end_encoding(encoder voidptr) {
		msg_void(ObjId(encoder), 'endEncoding')
	}

	pub fn metal_release(ptr voidptr) {
		msg_void(ObjId(ptr), 'release')
	}

	pub fn metal_max_texture_size(device voidptr) u32 {
		if is_nil(device) {
			return 16384
		}
		if msg_bool_u64(ObjId(device), 'supportsFamily:', mtl_gpu_family_apple10) {
			return 32768
		}
		if msg_bool_u64(ObjId(device), 'supportsFamily:', mtl_gpu_family_apple3) {
			return 16384
		}
		return 8192
	}

	pub fn metal_has_unified_memory(device voidptr) bool {
		if is_nil(device) {
			return true
		}
		return msg_bool(ObjId(device), 'hasUnifiedMemory')
	}

	// Built-in shaders use compiled library data. Custom ShaderToy shaders retain
	// their separate source-compilation API, as in the original renderer.
	pub fn metal_new_library_data(device voidptr, bytes []u8) !voidptr {
		data := C.witty_metal_dispatch_data(bytes.data, uint(bytes.len))
		if isnil(data) { return error('OutOfMemory') }
		defer { C.witty_metal_dispatch_release(data) }
		mut native_error := voidptr(unsafe { nil })
		library := C.witty_metal_library_data(device, data, &native_error)
		if !isnil(native_error) {
			description := C.witty_metal_error_description(native_error)
			assert !isnil(description)
			log.error('metal error=${unsafe { cstring_to_vstring(description) }}')
			return error('MetalFailed')
		}
		return library
	}

	const mtl_gpu_family_apple3 = u64(1003)

	const mtl_gpu_family_apple10 = u64(1010)

	pub fn ct_font_attribute_name() voidptr {
		return C.vt_ct_font_attribute_name()
	}
}
