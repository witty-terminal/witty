module renderer

import configpkg
import font
import macos

$if renderer_metal ?|| ( ( macos || ios ) && !renderer_opengl ?) {

	// MetalAPI wraps the Metal graphics API implementation.
	pub struct MetalAPI {
	pub mut:
		// Opaque handles to Metal objects.
		device voidptr = unsafe { nil }
		queue  voidptr = unsafe { nil }

		// The presentation layer. Absent for the off-screen/test API, which has no
		// runtime surface to present to.
		layer ?MetalIOSurfaceLayer

		// Alpha blending mode
		blending configpkg.AlphaBlending

		// The default storage mode to use for resources.
		default_storage_mode MetalStorageMode

		// The maximum 2D texture width and height supported by the device.
		max_texture_size u32

		// The autorelease pool held for the duration of a frame draw.
		autorelease_pool ?macos.AutoreleasePool

		// True when this instance created and therefore owns device and queue.
		owns_handles bool
	mut:
		// This surface shares Witty's GG submission backend.
		gg_owned bool

		post_textures MetalShaderTextures
	}

	// Storage mode for Metal resources.
	pub enum MetalStorageMode as u8 {
		// Shared between CPU and GPU (unified memory).
		shared     = 0
		// Managed by the GPU (discrete GPU).
		managed    = 1
		private    = 2
		memoryless = 3
	}

	// CPU cache mode for Metal resources.
	pub enum MetalCPUCacheMode as u8 {
		default        = 0
		write_combined = 1
	}

	// Hazard tracking mode for Metal resources.
	pub enum MetalHazardTrackingMode as u8 {
		default   = 0
		untracked = 1
		tracked   = 2
	}

	// MetalResourceOptions retains the native c_ulong packed layout.
	pub struct MetalResourceOptions {
		value u64
	}

	pub fn MetalResourceOptions.init(cache MetalCPUCacheMode, storage MetalStorageMode, hazard MetalHazardTrackingMode) MetalResourceOptions {
		return MetalResourceOptions{
			value: u64(cache) | (u64(storage) << 4) | (u64(hazard) << 8)
		}
	}

	pub fn MetalResourceOptions.from_int(value u64) MetalResourceOptions {
		return MetalResourceOptions{
			value: value
		}
	}

	pub fn (opts MetalResourceOptions) int_val() u64 {
		return opts.value
	}

	pub fn (opts MetalResourceOptions) cpu_cache_mode() MetalCPUCacheMode {
		return unsafe { MetalCPUCacheMode(opts.value & 0xf) }
	}

	pub fn (opts MetalResourceOptions) storage_mode() MetalStorageMode {
		return unsafe { MetalStorageMode((opts.value >> 4) & 0xf) }
	}

	pub fn (opts MetalResourceOptions) hazard_tracking_mode() MetalHazardTrackingMode {
		return unsafe { MetalHazardTrackingMode((opts.value >> 8) & 0x3) }
	}

	// Triple buffering for Metal swap chain.
	pub const metal_swap_chain_count = 3

	// The fragCoord for Metal shaders is +Y = down.
	pub const metal_custom_shader_y_is_down = true

	fn metal_default_storage_mode(device voidptr) MetalStorageMode {
		$if ios {
			return .shared
		} $else {
			return if macos.metal_has_unified_memory(device) { .shared } else { .managed }
		}
	}

	// init_from_view initializes the Metal API and installs Ghostty's
	// IOSurface-backed presentation layer on the runtime-provided view.
	pub fn MetalAPI.init_from_view(view voidptr, content_scale f64) !MetalAPI {
		if view == unsafe { nil } {
			return error('Metal view is unavailable')
		}
		device := macos.metal_system_default_device()
		if device == unsafe { nil } {
			return error('Metal not available')
		}
		queue := macos.metal_new_command_queue(device)
		if queue == unsafe { nil } {
			macos.metal_release(device)
			return error('Metal command queue unavailable')
		}
		layer := MetalIOSurfaceLayer.init() or {
			macos.metal_release(queue)
			macos.metal_release(device)
			return err
		}
		macos.metal_install_iosurface_layer(view, layer.layer, content_scale)

		storage := metal_default_storage_mode(device)
		max_tex := macos.metal_max_texture_size(device)

		return MetalAPI{
			device:               device
			queue:                queue
			layer:                layer
			blending:             .native
			default_storage_mode: storage
			max_texture_size:     max_tex
			owns_handles:         true
			gg_owned:             $if macos && !renderer_opengl ? { gg_metal_acquire(device) } $else { false }
		}
	}

	// init creates an offscreen Metal API with a real device and command queue.
	// The layer is absent because this entry point is used by renderer tests.
	pub fn MetalAPI.init() !MetalAPI {
		device := macos.metal_system_default_device()
		if device == unsafe { nil } {
			return error('Metal not available')
		}
		queue := macos.metal_new_command_queue(device)
		if queue == unsafe { nil } {
			return error('Metal command queue unavailable')
		}
		return MetalAPI{
			device:               device
			queue:                queue
			blending:             .native
			default_storage_mode: metal_default_storage_mode(device)
			max_texture_size:     macos.metal_max_texture_size(device)
			owns_handles:         true
			gg_owned:             $if macos && !renderer_opengl ? { gg_metal_acquire(device) } $else { false }
		}
	}

	pub fn (mut self MetalAPI) deinit() {
		self.post_textures.deinit()
		$if macos && !renderer_opengl ? {
			if self.gg_owned {
				gg_metal_release()
				self.gg_owned = false
			}
		}
		if self.owns_handles {
			macos.metal_release(self.queue)
			macos.metal_release(self.device)
		}
		if layer := self.layer {
			layer.release()
		}
		self.device = unsafe { nil }
		self.queue = unsafe { nil }
		self.layer = none
		self.owns_handles = false
	}

	// loop_enter installs the display callback the Metal layer invokes when the
	// compositor is ready for a new frame. Called by renderer.Thread when it
	// starts the main loop.
	pub fn (self &MetalAPI) loop_enter(r &Renderer) {
		layer := self.layer or { return }
		layer.set_display_callback(renderer_metal_layer_display_callback, voidptr(r))
	}

	// draw_frame_start performs the actions taken before doing anything in
	// `draw_frame`.
	//
	// Right now we use this to start an AutoreleasePool.
	pub fn (mut self MetalAPI) draw_frame_start() {
		assert self.autorelease_pool == none
		self.autorelease_pool = macos.AutoreleasePool.init()
	}

	// draw_frame_end performs the actions taken after `draw_frame` is done.
	//
	// Right now we use this to end our AutoreleasePool.
	pub fn (mut self MetalAPI) draw_frame_end() {
		assert self.autorelease_pool != none
		mut pool := self.autorelease_pool or { return }
		pool.deinit()
		self.autorelease_pool = none
	}

	// init_shaders initializes the built-in and optional post-process pipelines.
	pub fn (self &MetalAPI) init_shaders(custom_shaders []string) !MetalShaders {
		format := self.target_pixel_format()
		mut shaders := MetalShaders.init(self.device, custom_shaders, format)!
		$if macos && !renderer_opengl ? {
			$if compiled_metallib ? {
				if self.gg_owned {
					shaders.init_gg_pipelines(format, custom_shaders)
				}
			}
		}
		return shaders
	}

	// present_last_target presents the last presented target again. (noop for
	// Metal)
	pub fn (self &MetalAPI) present_last_target() ! {
		_ = self
	}

	pub fn (self &MetalAPI) buffer_options() MetalBufferOptions {
		return MetalBufferOptions{
			device:           self.device
			resource_options: MetalResourceOptions.init(.write_combined, self.default_storage_mode, .default)
		}
	}

	// Pixel format for image texture options.
	pub enum ImageTextureFormat as u8 {
		// 1 byte per pixel grayscale.
		gray
		// 4 bytes per pixel RGBA.
		rgba
		// 4 bytes per pixel BGRA.
		bgra
	}

	// metal_pixel_format translates an image pixel layout to its Metal format.
	fn (format ImageTextureFormat) metal_pixel_format(srgb bool) MetalPixelFormat {
		return match format {
			.gray {
				if srgb { MetalPixelFormat.r8unorm_srgb } else { MetalPixelFormat.r8unorm }
			}
			.rgba {
				if srgb { MetalPixelFormat.rgba8unorm_srgb } else { MetalPixelFormat.rgba8unorm }
			}
			.bgra {
				if srgb { MetalPixelFormat.bgra8unorm_srgb } else { MetalPixelFormat.bgra8unorm }
			}
		}
	}

	// image_texture_options returns the options to use when constructing textures
	// for images.
	pub fn (self &MetalAPI) image_texture_options(format ImageTextureFormat, srgb bool) MetalTextureOptions {
		return MetalTextureOptions{
			device:           self.device
			pixel_format:     format.metal_pixel_format(srgb)
			// Indicate that the CPU writes to this resource but never reads it.
			resource_options: MetalResourceOptions.init(.write_combined, self.default_storage_mode, .default)
			// We only need to read from this texture from a shader.
			usage:            MetalTextureUsage.from_int(0x01)
		}
	}

	// texture_options returns the options to use when constructing textures.
	pub fn (self &MetalAPI) texture_options() MetalTextureOptions {
		return MetalTextureOptions{
			device:           self.device
			// Using an `*_srgb` pixel format makes Metal gamma encode the pixels
			// written to it *after* blending, which means we get linear alpha
			// blending rather than gamma-incorrect blending.
			pixel_format:     self.target_pixel_format()
			// Indicate that the CPU writes to this resource but never reads it.
			resource_options: MetalResourceOptions.init(.write_combined, self.default_storage_mode, .default)
			// texture_options is currently only used for custom shaders, which
			// require both the shader read (for when multiple shaders are chained)
			// and render target (for the final output) usage. Disabling either of
			// these will lead to metal validation errors in Xcode.
			usage:            MetalTextureUsage.from_int(0x05)
		}
	}

	fn (mut self MetalAPI) prepare_post_textures(width uint, height uint, passes int) ! {
		first := self.post_textures.textures[0]
		if passes == 0 {
			if first.handle != unsafe { nil } {
				self.post_textures.deinit()
			}
			return
		}
		ping_pong := passes > 1
		has_second := self.post_textures.textures[1].handle != unsafe { nil }
		if first.handle != unsafe { nil } && first.width == width && first.height == height
			&& first.pixel_format == self.target_pixel_format() && has_second == ping_pong {
			return
		}
		replacement := MetalShaderTextures.init(&self, width, height, ping_pong)!
		self.post_textures.deinit()
		self.post_textures = replacement
	}

	pub fn (self &MetalAPI) sampler_options() MetalSamplerOptions {
		return MetalSamplerOptions{
			device:         self.device
			// These parameters match Shadertoy behaviors.
			min_filter:     .linear
			mag_filter:     .linear
			s_address_mode: .clamp_to_edge
			t_address_mode: .clamp_to_edge
		}
	}

	// atlas_texture_options translates a font atlas format to its exact Metal
	// pixel layout. BGR is unsupported by the source backend.
	pub fn (self &MetalAPI) atlas_texture_options(format font.AtlasFormat) !MetalTextureOptions {
		pixel_format := match format {
			.grayscale {
				MetalPixelFormat.r8unorm
			}
			.bgra {
				MetalPixelFormat.bgra8unorm_srgb
			}
			.bgr {
				return error('BGR font atlases are unsupported by Metal')
			}
		}
		return MetalTextureOptions{
			device:           self.device
			pixel_format:     pixel_format
			// Indicate that the CPU writes to this resource but never reads it.
			resource_options: MetalResourceOptions.init(.write_combined, self.default_storage_mode, .default)
			// We only need to read from this texture from a shader.
			usage:            MetalTextureUsage.from_int(0x01)
		}
	}

	// init_atlas_texture initializes an empty texture matching the atlas. Atlas
	// bytes are synchronized separately by the renderer.
	pub fn (self &MetalAPI) init_atlas_texture(atlas &font.Atlas) !MetalTexture {
		return MetalTexture.init(self.atlas_texture_options(atlas.format)!, uint(atlas.size),
			uint(atlas.size), none)
	}

	pub fn (self &MetalAPI) target_pixel_format() MetalPixelFormat {
		return if self.blending.is_linear() { .bgra8unorm_srgb } else { .bgra8unorm }
	}

	pub fn (self &MetalAPI) init_target(width uint, height uint) !MetalTarget {
		return MetalTarget.init(MetalTargetOptions{
			device:       self.device
			width:        width
			height:       height
			pixel_format: self.target_pixel_format()
			storage_mode: self.default_storage_mode
		})
	}

	pub fn (self &MetalAPI) present(target &MetalTarget, sync_ bool) ! {
		layer := self.layer or { return error('Metal presentation layer unavailable') }
		if sync_ {
			layer.set_surface_sync(target.surface)
		} else {
			layer.set_surface(target.surface)!
		}
	}

	// Get the current size of the runtime surface.
	pub fn (self &MetalAPI) surface_size() (u32, u32) {
		layer := self.layer or { return 0, 0 }
		width, height := layer.surface_size()
		return clamped_metal_surface_dimension(width, self.max_texture_size), clamped_metal_surface_dimension(height, self.max_texture_size)
	}

	fn clamped_metal_surface_dimension(value f64, maximum u32) u32 {
		if value <= 0 || maximum == 0 {
			return 0
		}
		if value >= f64(maximum) {
			return maximum
		}
		return u32(value)
	}

	// Metal pixel formats.
	pub enum MetalPixelFormat as u64 {
		invalid               = 0
		a8unorm               = 1
		r8unorm               = 10
		r8unorm_srgb          = 11
		r8snorm               = 12
		r8uint                = 13
		r8sint                = 14
		r16unorm              = 20
		r16snorm              = 22
		r16uint               = 23
		r16sint               = 24
		r16float              = 25
		rg8unorm              = 30
		rg8unorm_srgb         = 31
		rg8snorm              = 32
		rg8uint               = 33
		rg8sint               = 34
		b5g6r5unorm           = 40
		a1bgr5unorm           = 41
		abgr4unorm            = 42
		bgr5a1unorm           = 43
		r32uint               = 53
		r32sint               = 54
		r32float              = 55
		rg16unorm             = 60
		rg16snorm             = 62
		rg16uint              = 63
		rg16sint              = 64
		rg16float             = 65
		rgba8unorm            = 70
		rgba8unorm_srgb       = 71
		rgba8snorm            = 72
		rgba8uint             = 73
		rgba8sint             = 74
		bgra8unorm            = 80
		bgra8unorm_srgb       = 81
		rgb10a2unorm          = 90
		rgb10a2uint           = 91
		rg11b10float          = 92
		rgb9e5float           = 93
		bgr10a2unorm          = 94
		bgr10_xr              = 554
		bgr10_xr_srgb         = 555
		rg32uint              = 103
		rg32sint              = 104
		rg32float             = 105
		rgba16unorm           = 110
		rgba16snorm           = 112
		rgba16uint            = 113
		rgba16sint            = 114
		rgba16float           = 115
		bgra10_xr             = 552
		bgra10_xr_srgb        = 553
		rgba32uint            = 123
		rgba32sint            = 124
		rgba32float           = 125
		bc1_rgba              = 130
		bc1_rgba_srgb         = 131
		bc2_rgba              = 132
		bc2_rgba_srgb         = 133
		bc3_rgba              = 134
		bc3_rgba_srgb         = 135
		bc4_runorm            = 140
		bc4_rsnorm            = 141
		bc5_rgunorm           = 142
		bc5_rgsnorm           = 143
		bc6h_rgbfloat         = 150
		bc6h_rgbufloat        = 151
		bc7_rgbaunorm         = 152
		bc7_rgbaunorm_srgb    = 153
		pvrtc_rgb_2bpp        = 160
		pvrtc_rgb_2bpp_srgb   = 161
		pvrtc_rgb_4bpp        = 162
		pvrtc_rgb_4bpp_srgb   = 163
		pvrtc_rgba_2bpp       = 164
		pvrtc_rgba_2bpp_srgb  = 165
		pvrtc_rgba_4bpp       = 166
		pvrtc_rgba_4bpp_srgb  = 167
		eac_r11unorm          = 170
		eac_r11snorm          = 172
		eac_rg11unorm         = 174
		eac_rg11snorm         = 176
		eac_rgba8             = 178
		eac_rgba8_srgb        = 179
		etc2_rgb8             = 180
		etc2_rgb8_srgb        = 181
		etc2_rgb8a1           = 182
		etc2_rgb8a1_srgb      = 183
		astc_4x4_srgb         = 186
		astc_5x4_srgb         = 187
		astc_5x5_srgb         = 188
		astc_6x5_srgb         = 189
		astc_6x6_srgb         = 190
		astc_8x5_srgb         = 192
		astc_8x6_srgb         = 193
		astc_8x8_srgb         = 194
		astc_10x5_srgb        = 195
		astc_10x6_srgb        = 196
		astc_10x8_srgb        = 197
		astc_10x10_srgb       = 198
		astc_12x10_srgb       = 199
		astc_12x12_srgb       = 200
		astc_4x4_ldr          = 204
		astc_5x4_ldr          = 205
		astc_5x5_ldr          = 206
		astc_6x5_ldr          = 207
		astc_6x6_ldr          = 208
		astc_8x5_ldr          = 210
		astc_8x6_ldr          = 211
		astc_8x8_ldr          = 212
		astc_10x5_ldr         = 213
		astc_10x6_ldr         = 214
		astc_10x8_ldr         = 215
		astc_10x10_ldr        = 216
		astc_12x10_ldr        = 217
		astc_12x12_ldr        = 218
		astc_4x4_hdr          = 222
		astc_5x4_hdr          = 223
		astc_5x5_hdr          = 224
		astc_6x5_hdr          = 225
		astc_6x6_hdr          = 226
		astc_8x5_hdr          = 228
		astc_8x6_hdr          = 229
		astc_8x8_hdr          = 230
		astc_10x5_hdr         = 231
		astc_10x6_hdr         = 232
		astc_10x8_hdr         = 233
		astc_10x10_hdr        = 234
		astc_12x10_hdr        = 235
		astc_12x12_hdr        = 236
		gbgr422               = 240
		bgrg422               = 241
		depth16unorm          = 250
		depth32float          = 252
		stencil8              = 253
		depth24unorm_stencil8 = 255
		depth32float_stencil8 = 260
		x32_stencil8          = 261
		x24_stencil8          = 262
	}

	// Metal GPU family for feature detection.
	pub enum MetalGPUFamily as i64 {
		apple1  = 1001
		apple2  = 1002
		apple3  = 1003
		apple4  = 1004
		apple5  = 1005
		apple6  = 1006
		apple7  = 1007
		apple8  = 1008
		apple9  = 1009
		apple10 = 1010
		common1 = 3001
		common2 = 3002
		common3 = 3003
		metal3  = 5001
		metal4  = 5002
	}

	// Metal command buffer status.
	pub enum MetalCommandBufferStatus as u64 {
		not_enqueued = 0
		enqueued     = 1
		committed    = 2
		scheduled    = 3
		completed    = 4
		error        = 5
	}

	// Metal load action.
	pub enum MetalLoadAction as u64 {
		dont_care = 0
		load      = 1
		clear     = 2
	}

	// Metal store action.
	pub enum MetalStoreAction as u64 {
		dont_care                     = 0
		store                         = 1
		multisample_resolve           = 2
		store_and_multisample_resolve = 3
		unknown                       = 4
		custom_sample_depth_store     = 5
	}

	// Metal primitive type.
	pub enum MetalPrimitiveType as u64 {
		point          = 0
		line           = 1
		line_strip     = 2
		triangle       = 3
		triangle_strip = 4
	}

	// Metal index type.
	pub enum MetalIndexType as u64 {
		uint16 = 0
		uint32 = 1
	}

	// Metal vertex formats.
	pub enum MetalVertexFormat as u64 {
		invalid               = 0
		uchar2                = 1
		uchar3                = 2
		uchar4                = 3
		char2                 = 4
		char3                 = 5
		char4                 = 6
		uchar2normalized      = 7
		uchar3normalized      = 8
		uchar4normalized      = 9
		char2normalized       = 10
		char3normalized       = 11
		char4normalized       = 12
		ushort2               = 13
		ushort3               = 14
		ushort4               = 15
		short2                = 16
		short3                = 17
		short4                = 18
		ushort2normalized     = 19
		ushort3normalized     = 20
		ushort4normalized     = 21
		short2normalized      = 22
		short3normalized      = 23
		short4normalized      = 24
		half2                 = 25
		half3                 = 26
		half4                 = 27
		float                 = 28
		float2                = 29
		float3                = 30
		float4                = 31
		int_                  = 32
		int2                  = 33
		int3                  = 34
		int4                  = 35
		uint                  = 36
		uint2                 = 37
		uint3                 = 38
		uint4                 = 39
		int1010102normalized  = 40
		uint1010102normalized = 41
		uchar4normalized_bgra = 42
		uchar                 = 45
		char_                 = 46
		ucharnormalized       = 47
		charnormalized        = 48
		ushort                = 49
		short                 = 50
		ushortnormalized      = 51
		shortnormalized       = 52
		half                  = 53
		floatrg11b10          = 54
		floatrgb9e5           = 55
	}

	// Metal blend factor.
	pub enum MetalBlendFactor as u64 {
		zero                     = 0
		one                      = 1
		source_color             = 2
		one_minus_source_color   = 3
		source_alpha             = 4
		one_minus_source_alpha   = 5
		dest_color               = 6
		one_minus_dest_color     = 7
		dest_alpha               = 8
		one_minus_dest_alpha     = 9
		source_alpha_saturated   = 10
		blend_color              = 11
		one_minus_blend_color    = 12
		blend_alpha              = 13
		one_minus_blend_alpha    = 14
		source_1_color           = 15
		one_minus_source_1_color = 16
		source_1_alpha           = 17
		one_minus_source_1_alpha = 18
	}

	// Metal blend operation.
	pub enum MetalBlendOperation as u64 {
		add              = 0
		subtract         = 1
		reverse_subtract = 2
		min              = 3
		max              = 4
	}

	// Metal texture usage, retained in the native c_ulong packed layout.
	pub struct MetalTextureUsage {
		value u64
	}

	pub fn MetalTextureUsage.from_int(value u64) MetalTextureUsage {
		return MetalTextureUsage{
			value: value
		}
	}

	pub fn (usage MetalTextureUsage) int_val() u64 {
		return usage.value
	}

	pub fn (usage MetalTextureUsage) shader_read() bool {
		return usage.value & 0x01 != 0
	}

	pub fn (usage MetalTextureUsage) shader_write() bool {
		return usage.value & 0x02 != 0
	}

	pub fn (usage MetalTextureUsage) render_target() bool {
		return usage.value & 0x04 != 0
	}

	pub fn (usage MetalTextureUsage) pixel_format_view() bool {
		return usage.value & 0x10 != 0
	}

	pub fn (usage MetalTextureUsage) shader_atomic() bool {
		return usage.value & 0x20 != 0
	}

	// Metal sampler filter.
	pub enum MetalSamplerFilter as u64 {
		nearest = 0
		linear  = 1
	}

	// Metal sampler address mode.
	pub enum MetalSamplerAddressMode as u64 {
		clamp_to_edge         = 0
		mirror_clamp_to_edge  = 1
		repeat                = 2
		mirror_repeat         = 3
		clamp_to_zero         = 4
		clamp_to_border_color = 5
	}

	// Metal purgeable state.
	pub enum MetalPurgeableState as u64 {
		keep_current = 1
		non_volatile = 2
		volatile_    = 3
		empty        = 4
	}

	// Metal memory-barrier scope.
	pub enum MetalBarrierScope as u64 {
		buffers        = 1
		textures       = 2
		render_targets = 4
	}

	// Metal render stage.
	pub enum MetalRenderStage as u64 {
		vertex   = 1
		fragment = 2
		tile     = 4
		object   = 8
		mesh     = 16
	}

	// Metal clear color.
	pub struct MetalClearColor {
	pub:
		red   f64
		green f64
		blue  f64
		alpha f64
	}

	// Metal viewport.
	pub struct MetalViewport {
	pub:
		x      f64
		y      f64
		width  f64
		height f64
		znear  f64
		zfar   f64
	}

	// Metal region.
	pub struct MetalRegion {
	pub:
		origin MetalOrigin
		size   MetalSize
	}

	// Metal region origin.
	pub struct MetalOrigin {
	pub:
		x u64
		y u64
		z u64
	}

	// Metal region size.
	pub struct MetalSize {
	pub:
		width  u64
		height u64
		depth  u64
	}
}
