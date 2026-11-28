module renderer

import font
import log
import witty_macos as macos
import time

$if renderer_metal ?|| ( ( macos || ios ) && !renderer_opengl ?) {

	// Metal sub-types: Buffer, Frame, RenderPass, Pipeline, Sampler, Target, Texture
	//
	// These wrappers mirror the native Metal resources used by Ghostty.

	// ============================================================
	// Metal Buffer
	// ============================================================

	// MetalBuffer wraps a Metal GPU buffer (MTLBuffer).
	//
	// Port of ghostty's src/renderer/metal/buffer.zig `Buffer(comptime T)`.
	// The local specialization stores bytes, so lengths are byte counts.
	pub struct MetalBuffer {
	pub mut:
		// The underlying buffer handle (opaque).
		handle voidptr = unsafe { nil }
		// The options this buffer was initialized with.
		opts MetalBufferOptions
		// The number of elements currently stored in the buffer.
		len uint
	}

	// MetalBufferOptions configures how a buffer is created.
	pub struct MetalBufferOptions {
	pub:
		// MTLDevice used to allocate this buffer.
		device           voidptr              @[required]
		resource_options MetalResourceOptions @[required]
	}

	// Initialize a buffer with the given length pre-allocated.
	pub fn MetalBuffer.init(opts MetalBufferOptions, len uint) !MetalBuffer {
		handle := macos.metal_new_buffer_length(opts.device, len, opts.resource_options.int_val())
		if handle == unsafe { nil } {
			return error('Metal buffer allocation failed')
		}
		return MetalBuffer{
			handle: handle
			opts:   opts
			len:    len
		}
	}

	// Init the buffer filled with the given data.
	pub fn MetalBuffer.init_fill[T](opts MetalBufferOptions, data []T) !MetalBuffer {
		byte_len := uint(data.len) * uint($sizeof(T))
		mut ptr := voidptr(unsafe { nil })
		if data.len > 0 {
			ptr = voidptr(data.data)
		}
		handle := macos.metal_new_buffer_raw(opts.device, ptr, byte_len, opts.resource_options.int_val())
		if handle == unsafe { nil } {
			return error('Metal buffer allocation failed')
		}
		return MetalBuffer{
			handle: handle
			opts:   opts
			len:    uint(data.len)
		}
	}

	pub fn (mut self MetalBuffer) deinit() {
		macos.metal_release(self.handle)
		self.handle = unsafe { nil }
		self.len = 0
	}

	// Sync new contents to the buffer. The data is expected to be the complete
	// contents of the buffer. If the amount of data is larger than the buffer
	// capacity, the buffer is reallocated to hold it. If the amount of data is
	// smaller than the buffer capacity, the remaining data is left untouched.
	pub fn (mut self MetalBuffer) sync(data []u8) ! {
		mut ptr := voidptr(unsafe { nil })
		if data.len > 0 {
			ptr = voidptr(data.data)
		}
		self.sync_raw(ptr, uint(data.len))!
	}

	pub fn (mut self MetalBuffer) sync_values[T](values []T) ! {
		mut ptr := voidptr(unsafe { nil })
		if values.len > 0 {
			ptr = voidptr(values.data)
		}
		self.sync_raw(ptr, uint(values.len) * uint($sizeof(T)))!
	}

	// Like MetalBuffer.sync but takes data from an array of lists, rather than a
	// single array. Returns the number of items synced.
	pub fn (mut self MetalBuffer) sync_from_array_lists[T](lists [][]T) !uint {
		mut total_len := uint(0)
		for list in lists {
			total_len += uint(list.len)
		}

		req_bytes := total_len * uint($sizeof(T))
		if req_bytes == 0 {
			return total_len
		}
		self.ensure_capacity(req_bytes)!

		// We can fit within the buffer so we can just replace bytes.
		dst := macos.metal_buffer_contents(self.handle)
		if dst == unsafe { nil } {
			return error('Metal buffer contents pointer is null')
		}
		mut i := uint(0)
		for list in lists {
			if list.len == 0 {
				continue
			}
			bytes := uint(list.len) * uint($sizeof(T))
			unsafe { vmemcpy(voidptr(&u8(dst) + i), voidptr(list.data), int(bytes)) }
			i += bytes
		}

		// If we're using the managed resource storage mode, then we need to signal
		// Metal to synchronize the buffer data.
		//
		// Ref: https://developer.apple.com/documentation/metal/synchronizing-a-managed-resource-in-macos?language=objc
		if self.opts.resource_options.storage_mode() == .managed {
			macos.metal_buffer_did_modify(self.handle, req_bytes)
		}

		return total_len
	}

	fn (mut self MetalBuffer) ensure_capacity(req_bytes uint) ! {
		available_bytes := macos.metal_buffer_length(self.handle)
		if req_bytes <= available_bytes {
			return
		}
		// Both the native capacity and the required size are already in bytes.
		replacement := macos.metal_new_buffer_length(self.opts.device, req_bytes * 2,
			self.opts.resource_options.int_val())
		if replacement == unsafe { nil } {
			return error('Metal buffer reallocation failed')
		}
		macos.metal_release(self.handle)
		self.handle = replacement
	}

	fn (mut self MetalBuffer) sync_raw(data voidptr, req_bytes uint) ! {
		if req_bytes == 0 {
			return
		}
		self.ensure_capacity(req_bytes)!
		dst := macos.metal_buffer_contents(self.handle)
		if dst == unsafe { nil } {
			return error('Metal buffer contents pointer is null')
		}
		unsafe { vmemcpy(dst, data, int(req_bytes)) }
		if self.opts.resource_options.storage_mode() == .managed {
			macos.metal_buffer_did_modify(self.handle, req_bytes)
		}
	}

	fn metal_command_buffer_status(raw u64) MetalCommandBufferStatus {
		return match raw {
			0 { .not_enqueued }
			1 { .enqueued }
			2 { .committed }
			3 { .scheduled }
			4 { .completed }
			else { .error }
		}
	}

	// ============================================================
	// Metal Frame
	// ============================================================

	// MetalFrame owns pass encoding and submission for a terminal frame.
	// It can encode terminal passes in its own or the window's GG context.
	pub struct MetalFrame {
	pub mut:
		// The command buffer handle.
		command_buffer voidptr = unsafe { nil }
		// Captures copied into the Objective-C completion block.
		renderer            voidptr = unsafe { nil }
		target              voidptr = unsafe { nil }
		completion_callback voidptr = unsafe { nil }
	mut:
		gg &GGMetalFrame = unsafe { nil }
	}

	pub fn MetalFrame.begin(queue voidptr, renderer_ptr voidptr, target voidptr, completion_callback voidptr) !MetalFrame {
		if queue == unsafe { nil } {
			return error('Metal frame requires a command queue')
		}
		if renderer_ptr == unsafe { nil } || target == unsafe { nil }
			|| completion_callback == unsafe { nil } {
			return error('Metal frame requires completion captures')
		}
		buffer := macos.metal_create_command_buffer(queue)
		if buffer == unsafe { nil } {
			return error('Metal command buffer allocation failed')
		}
		return MetalFrame{
			command_buffer:      buffer
			renderer:            renderer_ptr
			target:              target
			completion_callback: completion_callback
		}
	}

	fn MetalFrame.begin_for_device(api &MetalAPI, renderer_ptr voidptr, target voidptr, callback voidptr) !MetalFrame {
		$if macos && !renderer_opengl ? {
			if api.gg_owned {
				if renderer_ptr == unsafe { nil } || target == unsafe { nil } || callback == unsafe { nil } {
					return error('Metal frame requires completion captures')
				}
				return MetalFrame{
					renderer:            renderer_ptr
					target:              target
					completion_callback: callback
					gg:                  gg_metal_begin()
				}
			}
		}
		return MetalFrame.begin(api.queue, renderer_ptr, target, callback)
	}

	pub fn (mut self MetalFrame) render_pass(attachments []MetalRenderPassAttachment) !MetalRenderPass {
		$if macos && !renderer_opengl ? {
			if self.gg != unsafe { nil } {
				return self.gg.render_pass(attachments)
			}
		}
		return MetalRenderPass.begin(MetalRenderPassOptions{
			command_buffer: self.command_buffer
			attachments:    attachments
		})
	}

	fn (mut self MetalFrame) submit(pass &MetalRenderPass, sync_ bool) ! {
		$if macos && !renderer_opengl ? {
			if self.gg != unsafe { nil } {
				self.gg.submit(pass, self, sync_)!
				return
			}
		}
		pass.complete()
		self.complete(sync_)
	}

	fn (mut self MetalFrame) cancel() {
		$if macos && !renderer_opengl ? {
			if self.gg != unsafe { nil } {
				self.gg.cancel()
			}
		}
	}

	pub fn (mut self MetalFrame) complete(sync_ bool) {
		if !sync_ {
			if !macos.metal_command_buffer_add_completed_handler(self.command_buffer,
				self.completion_callback, self.renderer, self.target) {
				panic('Metal completion handler registration failed')
			}
		}
		macos.metal_command_buffer_commit(self.command_buffer)
		if sync_ {
			macos.metal_command_buffer_wait(self.command_buffer)
			macos.metal_command_buffer_invoke_completion(self.command_buffer, self.completion_callback,
				self.renderer, self.target, true)
		}
	}

	// ============================================================
	// Metal RenderPass
	// ============================================================

	// MetalRenderPass wraps the Metal encoder for the terminal shaders.
	pub struct MetalRenderPass {
	pub mut:
		// The render command encoder handle.
		encoder voidptr = unsafe { nil }
	mut:
		gg &GGMetalFrame = unsafe { nil }
	}

	// MetalRenderStep describes a single step in a render pass.
	pub struct MetalRenderStep {
	pub:
		// The pipeline to use.
		pipeline MetalPipeline @[required]
		// Uniform buffer, bound at index 1 for both shader stages.
		uniforms ?MetalBuffer
		// Vertex and fragment buffers. Entry zero uses index zero; later entries
		// start at index two so uniforms can remain at index one.
		buffers []?MetalBuffer
		// Textures bound to both stages by slice index.
		textures []?MetalTexture
		// Fragment samplers bound by slice index.
		samplers []?MetalSampler
		// Draw call configuration.
		draw MetalRenderDraw @[required]
	}

	pub struct MetalRenderDraw {
	pub:
		draw_type      MetalPrimitiveType @[required]
		vertex_count   uint              @[required]
		instance_count uint = 1
	}

	pub type MetalRenderAttachmentTarget = MetalTarget | MetalTexture

	pub struct MetalRenderPassAttachment {
	pub:
		target      MetalRenderAttachmentTarget @[required]
		clear_color ?[4]f64
	}

	pub struct MetalRenderPassOptions {
	pub:
		command_buffer voidptr                     @[required]
		attachments    []MetalRenderPassAttachment @[required]
	}

	pub fn MetalRenderPass.begin(opts MetalRenderPassOptions) MetalRenderPass {
		descriptor := macos.metal_render_pass_descriptor()
		for index, attachment in opts.attachments {
			target := match attachment.target {
				MetalTarget { attachment.target.texture }
				MetalTexture { attachment.target.handle }
			}
			macos.metal_render_pass_set_attachment(descriptor, uint(index), target,
				attachment.clear_color)
		}
		return MetalRenderPass{
			encoder: macos.metal_create_encoder(opts.command_buffer, descriptor)
		}
	}

	pub fn (self &MetalRenderPass) step(s MetalRenderStep) {
		if s.draw.instance_count == 0 {
			return
		}
		$if macos && !renderer_opengl ? {
			if self.gg != unsafe { nil } {
				mut frame := self.gg
				if s.pipeline.gg.pipeline.id != 0 {
					frame.draw(self.encoder, s) or {
						log.debug('GG Metal draw unavailable: ${err}')
						frame.native_draw = true
						self.step_native(s)
						return
					}
					return
				}
				frame.native_draw = true
			}
		}
		self.step_native(s)
	}

	fn (self &MetalRenderPass) step_native(s MetalRenderStep) {
		macos.metal_encoder_set_pipeline(self.encoder, s.pipeline.handle)
		if s.buffers.len > 0 {
			if buffer := s.buffers[0] {
				macos.metal_encoder_set_buffer(self.encoder, buffer.handle, 0)
			}
			for index in 1 .. s.buffers.len {
				if buffer := s.buffers[index] {
					macos.metal_encoder_set_buffer(self.encoder, buffer.handle, uint(index + 1))
				}
			}
		}
		if uniforms := s.uniforms {
			macos.metal_encoder_set_buffer(self.encoder, uniforms.handle, 1)
		}
		for index, texture in s.textures {
			if value := texture {
				macos.metal_encoder_set_texture(self.encoder, value.handle, uint(index))
			}
		}
		for index, sampler in s.samplers {
			if value := sampler {
				macos.metal_encoder_set_sampler(self.encoder, value.handle, uint(index))
			}
		}
		macos.metal_encoder_draw(self.encoder, u64(s.draw.draw_type), s.draw.vertex_count, s.draw.instance_count)
	}

	pub fn (self &MetalRenderPass) complete() {
		$if macos && !renderer_opengl ? {
			if self.gg != unsafe { nil } {
				gg_metal_end_render_pass()
				return
			}
		}
		macos.metal_end_encoding(self.encoder)
	}

	// ============================================================
	// Metal Pipeline
	// ============================================================

	// MetalPipeline wraps a Metal render pipeline state (MTLRenderPipelineState).
	pub struct MetalPipeline {
	pub mut:
		// The pipeline state handle.
		handle voidptr = unsafe { nil }
	mut:
		gg GGMetalPipeline
	}

	pub struct MetalVertexAttribute {
	pub:
		format MetalVertexFormat
		offset uint
	}

	pub enum MetalVertexStepFunction as u64 {
		constant                = 0
		per_vertex              = 1
		per_instance            = 2
		per_patch               = 3
		per_patch_control_point = 4
	}

	pub struct MetalPipelineOptions {
	pub:
		device           voidptr @[required]
		vertex_fn        string  @[required]
		fragment_fn      string  @[required]
		vertex_library   voidptr @[required]
		fragment_library voidptr @[required]
		attributes       []MetalVertexAttribute
		vertex_stride    uint
		step_fn          MetalVertexStepFunction = .per_vertex
		attachments      []MetalPipelineAttachment @[required]
	}

	pub struct MetalPipelineAttachment {
	pub:
		pixel_format     MetalPixelFormat @[required]
		blending_enabled bool = true
	}

	pub fn MetalPipeline.init(opts MetalPipelineOptions) !MetalPipeline {
		mut attributes := []macos.MetalVertexAttribute{cap: opts.attributes.len}
		for attribute in opts.attributes {
			attributes << macos.MetalVertexAttribute{
				format: u64(attribute.format)
				offset: attribute.offset
			}
		}
		mut attachments := []macos.MetalPipelineAttachment{cap: opts.attachments.len}
		for attachment in opts.attachments {
			attachments << macos.MetalPipelineAttachment{
				pixel_format:     u64(attachment.pixel_format)
				blending_enabled: attachment.blending_enabled
			}
		}
		handle := macos.metal_new_pipeline(opts.device, opts.vertex_library, opts.fragment_library, opts.vertex_fn, opts.fragment_fn, attributes, opts.vertex_stride, u64(opts.step_fn), attachments)
		if handle == unsafe { nil } {
			return error('Metal render pipeline creation failed')
		}
		return MetalPipeline{
			handle: handle
		}
	}

	pub fn (mut self MetalPipeline) deinit() {
		$if macos && !renderer_opengl ? {
			self.gg.deinit()
			self.gg = GGMetalPipeline{}
		}
		macos.metal_release(self.handle)
		self.handle = unsafe { nil }
	}

	// ============================================================
	// Metal Sampler
	// ============================================================

	// MetalSampler wraps a Metal sampler state (MTLSamplerState).
	pub struct MetalSampler {
	pub mut:
		handle voidptr = unsafe { nil }
	}

	// MetalSamplerOptions configures sampler creation.
	pub struct MetalSamplerOptions {
	pub:
		// MTLDevice
		device         voidptr                 @[required]
		min_filter     MetalSamplerFilter      @[required]
		mag_filter     MetalSamplerFilter      @[required]
		s_address_mode MetalSamplerAddressMode @[required]
		t_address_mode MetalSamplerAddressMode @[required]
	}

	pub fn MetalSampler.init(opts MetalSamplerOptions) !MetalSampler {
		handle := macos.metal_new_sampler(opts.device, u64(opts.min_filter), u64(opts.mag_filter), u64(opts.s_address_mode), u64(opts.t_address_mode))
		if handle == unsafe { nil } {
			return error('Metal sampler allocation failed')
		}
		return MetalSampler{
			handle: handle
		}
	}

	pub fn (mut self MetalSampler) deinit() {
		macos.metal_release(self.handle)
		self.handle = unsafe { nil }
	}

	// ============================================================
	// Metal Target
	// ============================================================

	// MetalTarget wraps a Metal render target (IOSurface-backed MTLTexture).
	pub struct MetalTarget {
	pub mut:
		// The IOSurface handle.
		surface &macos.IOSurface = unsafe { nil }
		// The texture handle.
		texture voidptr = unsafe { nil }
		ui2_texture voidptr = unsafe { nil }
		// Width and height of the target.
		width        uint
		height       uint
		pixel_format MetalPixelFormat
	}

	pub struct MetalTargetOptions {
	pub:
		// MTLDevice
		device voidptr @[required]
		// Desired width.
		width uint @[required]
		// Desired height.
		height uint @[required]
		// Pixel format for the MTLTexture.
		pixel_format MetalPixelFormat @[required]
		// Storage mode for the MTLTexture.
		storage_mode MetalStorageMode @[required]
	}

	pub fn MetalTarget.init(opts MetalTargetOptions) !MetalTarget {
		colorspace := macos.CGColorSpace.create_named(.display_p3)!
		defer {
			colorspace.release()
		}
		surface := macos.IOSurface.init(macos.IOSurfaceProperties{
			width:             int(opts.width)
			height:            int(opts.height)
			pixel_format:      .p32_bgra
			bytes_per_element: 4
			colorspace:        colorspace
		})!
		resource_options := MetalResourceOptions.init(.write_combined, opts.storage_mode, .default)
		// UI2 samples the completed render target directly.
		usage := MetalTextureUsage.from_int(0x05)
		texture := macos.metal_new_iosurface_texture(opts.device, voidptr(surface), u64(opts.pixel_format), opts.width, opts.height, resource_options.int_val(), usage.int_val())
		if texture == unsafe { nil } {
			surface.deinit()
			return error('Metal target texture allocation failed')
		}
		mut ui2_texture := unsafe { voidptr(nil) }
		$if app_runtime_ui2 ? {
			if opts.pixel_format == .bgra8unorm_srgb {
				// The UI2 pass expects encoded color values. Read the same IOSurface
				// through a non-sRGB view to avoid decoding a second time.
				ui2_texture = macos.metal_new_iosurface_texture(opts.device, voidptr(surface),
					u64(MetalPixelFormat.bgra8unorm), opts.width, opts.height, resource_options.int_val(), 1)
				if ui2_texture == unsafe { nil } {
					macos.metal_release(texture)
					surface.deinit()
					return error('Metal UI2 texture allocation failed')
				}
			}
		}
		return MetalTarget{
			surface:      surface
			texture:      texture
			ui2_texture:  ui2_texture
			width:        opts.width
			height:       opts.height
			pixel_format: opts.pixel_format
		}
	}

	pub fn (mut self MetalTarget) deinit() {
		if self.surface != unsafe { nil } {
			self.surface.deinit()
		}
		macos.metal_release(self.texture)
		macos.metal_release(self.ui2_texture)
		self.surface = unsafe { nil }
		self.texture = unsafe { nil }
		self.ui2_texture = unsafe { nil }
	}

	// ============================================================
	// Metal Texture
	// ============================================================

	// MetalTexture wraps a Metal texture (MTLTexture).
	//
	// Port of ghostty's src/renderer/metal/texture.zig.
	pub struct MetalTexture {
	pub mut:
		// The texture handle.
		handle voidptr = unsafe { nil }
		// Width and height.
		width  uint
		height uint
		// Bytes per pixel for this texture.
		bpp          uint
		pixel_format MetalPixelFormat
	}

	// MetalTextureOptions configures texture creation.
	pub struct MetalTextureOptions {
	pub:
		// MTLDevice
		device           voidptr              @[required]
		pixel_format     MetalPixelFormat     @[required]
		resource_options MetalResourceOptions @[required]
		usage            MetalTextureUsage    @[required]
	}

	// Initialize a texture. If data is provided, it is uploaded starting at the
	// top-left (0, 0) origin.
	pub fn MetalTexture.init(opts MetalTextureOptions, width uint, height uint, data ?[]u8) !MetalTexture {
		bpp := bpp_of(opts.pixel_format)
		handle := macos.metal_new_texture(opts.device, u64(opts.pixel_format), width, height, opts.resource_options.int_val(), opts.usage.int_val())
		if handle == unsafe { nil } {
			return error('Metal texture allocation failed')
		}
		mut self := MetalTexture{
			handle:       handle
			width:        width
			height:       height
			bpp:          bpp
			pixel_format: opts.pixel_format
		}

		if d := data {
			assert d.len == int(width * height * bpp)
			self.replace_region(0, 0, width, height, d)
		}

		return self
	}

	// bpp_of returns the bytes per pixel for the provided pixel format.
	fn bpp_of(pixel_format MetalPixelFormat) uint {
		return match pixel_format {
			.invalid {
				panic('invalid pixel format')
			}

			// 8-bit pixel formats.
			.a8unorm, .r8unorm, .r8unorm_srgb, .r8snorm, .r8uint, .r8sint, .rg8unorm,
			.rg8unorm_srgb, .rg8snorm, .rg8uint, .rg8sint, .stencil8 {
				uint(1)
			}

			// 16-bit pixel formats.
			.r16unorm, .r16snorm, .r16uint, .r16sint, .r16float, .rg16unorm, .rg16snorm, .rg16uint,
			.rg16sint, .rg16float, .b5g6r5unorm, .a1bgr5unorm, .abgr4unorm, .bgr5a1unorm,
			.depth16unorm {
				uint(2)
			}

			// 32-bit pixel formats.
			.rgba8unorm, .rgba8unorm_srgb, .rgba8snorm, .rgba8uint, .rgba8sint, .bgra8unorm,
			.bgra8unorm_srgb, .rgb10a2unorm, .rgb10a2uint, .rg11b10float, .rgb9e5float,
			.bgr10a2unorm, .bgr10_xr, .bgr10_xr_srgb, .r32uint, .r32sint, .r32float, .depth32float,
			.depth24unorm_stencil8 {
				uint(4)
			}

			// 64-bit pixel formats.
			.rg32uint, .rg32sint, .rg32float, .rgba16unorm, .rgba16snorm, .rgba16uint, .rgba16sint,
			.rgba16float, .bgra10_xr, .bgra10_xr_srgb {
				uint(8)
			}

			// 128-bit pixel formats.
			.rgba32uint, .rgba32sint, .rgba32float {
				uint(128)
			}
			else {
				panic('pixel format size unknown (unlikely that this format was actually used, could be memory corruption)')
			}
		}
	}

	pub fn (mut self MetalTexture) deinit() {
		macos.metal_release(self.handle)
		self.handle = unsafe { nil }
	}

	// Replace a rectangular region of the texture with the provided data.
	//
	// Does NOT check the dimensions of the data to ensure correctness. The source
	// data is laid out with a stride of `width * bpp` (the region width), and is
	// written into the texture using the texture's own row stride of
	// `self.width * bpp`.
	pub fn (self MetalTexture) replace_region(x uint, y uint, width uint, height uint, data []u8) {
		macos.metal_texture_replace_region(self.handle, x, y, width, height, data, width * self.bpp)
	}

	// ============================================================
	// Metal IOSurfaceLayer
	// ============================================================

	// MetalIOSurfaceLayer wraps a CALayer subclass with IOSurface backing.
	pub struct MetalIOSurfaceLayer {
	pub mut:
		// The layer handle (CALayer*).
		layer voidptr = unsafe { nil }
	}

	pub fn MetalIOSurfaceLayer.init() !MetalIOSurfaceLayer {
		layer := macos.metal_iosurface_layer_new()
		if layer == unsafe { nil } {
			return error('Metal IOSurface layer allocation failed')
		}
		return MetalIOSurfaceLayer{
			layer: layer
		}
	}

	pub fn (self &MetalIOSurfaceLayer) release() {
		macos.metal_release(self.layer)
	}

	// Sets the layer's `contents` to the provided IOSurface.
	//
	// Makes sure to do so on the main thread to avoid visual artifacts. The
	// retain/release pairing, the main-thread check, and the discard of a surface
	// whose size no longer matches the layer all live in the C shim, which stands
	// in for the source's Objective-C block.
	pub fn (self &MetalIOSurfaceLayer) set_surface(surface &macos.IOSurface) ! {
		if !macos.metal_iosurface_layer_set_surface(self.layer, voidptr(surface)) {
			return error('Metal IOSurface layer update failed')
		}
	}

	// Sets the layer's `contents` to the provided IOSurface.
	//
	// Does not ensure this happens on the main thread.
	pub fn (self &MetalIOSurfaceLayer) set_surface_sync(surface &macos.IOSurface) {
		macos.metal_iosurface_layer_set_surface_sync(self.layer, voidptr(surface))
	}

	pub type MetalLayerDisplayCallback = fn (context voidptr)

	pub fn (self &MetalIOSurfaceLayer) set_display_callback(callback MetalLayerDisplayCallback, context voidptr) {
		macos.metal_iosurface_layer_set_display_callback(self.layer, voidptr(callback), context)
	}

	// surface_size returns the current size of the runtime surface.
	pub fn (self &MetalIOSurfaceLayer) surface_size() (f64, f64) {
		return macos.metal_layer_surface_size(self.layer)
	}

	// ============================================================
	// Metal cell shader parameter (GPU-side text cell)
	// ============================================================

	// MetalUniforms is the ABI-stable representation consumed by shaders.metal.
	// V's logical Uniforms type contains nested boolean structs, so it cannot be
	// copied directly to a Metal constant buffer. The explicit padding below
	// mirrors the alignments in ghostty's extern shader Uniforms structure.
	pub struct MetalUniforms {
	pub mut:
		projection_matrix     [16]f32
		screen_size           [2]f32
		cell_size             [2]f32
		grid_size             [2]u16
		reserved0             [12]u8
		grid_padding          [4]f32
		padding_extend        u8
		reserved1             [3]u8
		min_contrast          f32
		cursor_pos            [2]u16
		cursor_color          [4]u8
		bg_color              [4]u8
		cursor_wide           u8
		use_display_p3        u8
		use_linear_blending   u8
		use_linear_correction u8
		reserved2             [8]u8
	}

	// metal_uniforms converts the renderer's convenient logical representation
	// into the exact byte layout declared by the Metal shader.
	pub fn metal_uniforms(value Uniforms) MetalUniforms {
		mut padding_extend := u8(0)
		if value.padding_extend.left {
			padding_extend |= 1
		}
		if value.padding_extend.right {
			padding_extend |= 2
		}
		if value.padding_extend.up {
			padding_extend |= 4
		}
		if value.padding_extend.down {
			padding_extend |= 8
		}
		return MetalUniforms{
			projection_matrix:     value.projection_matrix
			screen_size:           value.screen_size
			cell_size:             value.cell_size
			grid_size:             value.grid_size
			grid_padding:          value.grid_padding
			padding_extend:        padding_extend
			min_contrast:          value.min_contrast
			cursor_pos:            value.cursor_pos
			cursor_color:          value.cursor_color
			bg_color:              value.bg_color
			cursor_wide:           u8(value.bools.cursor_wide)
			use_display_p3:        u8(value.bools.use_display_p3)
			use_linear_blending:   u8(value.bools.use_linear_blending)
			use_linear_correction: u8(value.bools.use_linear_correction)
		}
	}

	// ============================================================
	// Metal Shaders
	// ============================================================

	// MetalFrameState contains every resource that the CPU may update while a
	// frame is in flight. Renderer keeps one instance per swap-chain slot, just
	// like ghostty's generic renderer FrameState.
	pub struct MetalFrameState {
	pub mut:
		uniforms                 MetalBuffer
		cells                    MetalBuffer
		cells_bg                 MetalBuffer
		bg_image_buffer          MetalBuffer
		grayscale                MetalTexture
		grayscale_modified       uint
		color                    MetalTexture
		color_modified           uint
		target                   MetalTarget
		target_config_modified   uint
		bg_image_buffer_modified uint
		custom_shader_uniforms   MetalBuffer
	mut:
		window_compute WindowComputeState
		window_raster WindowRasterBuffer
	}

	struct WindowRasterBuffer {
	mut:
		pixels   voidptr
		capacity usize
		failed   bool
	}

	struct WindowComputeState {
	mut:
		pipeline voidptr
		offsets MetalBuffer
		indices MetalBuffer
		tile_offsets []u32
		tile_indices []u32
		failed bool
	}

	pub fn MetalFrameState.init(api &MetalAPI) !MetalFrameState {
		mut uniforms := MetalBuffer.init(api.buffer_options(), uint($sizeof(MetalUniforms)))!
		mut cells := MetalBuffer.init(api.buffer_options(), uint($sizeof(CellText))) or {
			uniforms.deinit()
			return err
		}
		mut cells_bg := MetalBuffer.init(api.buffer_options(), uint($sizeof(CellBg))) or {
			cells.deinit()
			uniforms.deinit()
			return err
		}
		mut bg_image_buffer := MetalBuffer.init(api.buffer_options(), uint($sizeof(BgImageBuffer))) or {
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		mut grayscale := api.init_atlas_texture(&font.Atlas{
			size:   1
			format: .grayscale
		}) or {
			bg_image_buffer.deinit()
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		mut color := api.init_atlas_texture(&font.Atlas{
			size:   1
			format: .bgra
		}) or {
			grayscale.deinit()
			bg_image_buffer.deinit()
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		target := api.init_target(1, 1) or {
			color.deinit()
			grayscale.deinit()
			bg_image_buffer.deinit()
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		return MetalFrameState{
			uniforms:            uniforms
			cells:               cells
			cells_bg:            cells_bg
			bg_image_buffer:     bg_image_buffer
			grayscale:           grayscale
			color:               color
			target:              target
			custom_shader_uniforms: MetalBuffer{opts: api.buffer_options()}
			window_compute: WindowComputeState{
				offsets: MetalBuffer{opts: api.buffer_options()}
				indices: MetalBuffer{opts: api.buffer_options()}
			}
		}
	}

	pub fn (mut self MetalFrameState) deinit() {
		$if macos && !renderer_opengl ? {
			self.window_compute.deinit()
			self.window_raster.deinit()
		}
		self.target.deinit()
		self.uniforms.deinit()
		self.cells.deinit()
		self.cells_bg.deinit()
		self.grayscale.deinit()
		self.color.deinit()
		self.bg_image_buffer.deinit()
		self.custom_shader_uniforms.deinit()
	}

	pub fn (mut self MetalFrameState) resize_target(api &MetalAPI, width uint, height uint) ! {
		target := api.init_target(width, height)!
		self.target.deinit()
		self.target = target
	}

	// These textures are shared across frames submitted to the same command
	// queue. Each pass binds them directly, so Metal tracks reads and writes
	// across command buffers. The CPU-updated uniforms remain per frame.
	struct MetalShaderTextures {
	mut:
		textures [2]MetalTexture
		sampler  MetalSampler
	}

	fn MetalShaderTextures.init(api &MetalAPI, width uint, height uint, ping_pong bool) !MetalShaderTextures {
		opts := MetalTextureOptions{
			...api.texture_options()
			resource_options: MetalResourceOptions.init(.default, .private, .tracked)
		}
		mut state := MetalShaderTextures{}
		state.textures[0] = MetalTexture.init(opts, width, height, none)!
		if ping_pong {
			state.textures[1] = MetalTexture.init(opts, width, height, none) or {
				state.deinit()
				return err
			}
		}
		state.sampler = MetalSampler.init(api.sampler_options()) or {
			state.deinit()
			return err
		}
		return state
	}

	fn (mut self MetalShaderTextures) deinit() {
		self.textures[0].deinit()
		self.textures[1].deinit()
		self.sampler.deinit()
	}

	$if compiled_metallib ? {
		const metal_shader_library = $embed_file('../.witty-build/native/witty.metallib').to_bytes()
	}

	// MetalShaders manages the Metal shader library and all pipelines.
	pub struct MetalShaders {
	pub mut:
		// Library containing Ghostty's built-in Metal shader functions.
		library voidptr = unsafe { nil }
		// Pipeline for background color.
		bg_color MetalPipeline
		// Pipeline for cell backgrounds.
		cell_bg MetalPipeline
		// Pipeline for cell text.
		cell_text MetalPipeline
		// Pipeline for images.
		image MetalPipeline
		// Pipeline for background images.
		bg_image MetalPipeline
		// Post-processing pipelines (custom shaders).
		post_pipelines []MetalPipeline
		// Protect against duplicate lifecycle teardown.
		defunct bool
	}

	pub fn MetalShaders.init(device voidptr, post_shaders []string, pixel_format MetalPixelFormat) !MetalShaders {
		library := load_builtin_metal_library(device)!
		mut self := MetalShaders{
			library: library
		}

		self.bg_color = MetalPipeline.init(MetalPipelineOptions{
			device:           device
			vertex_fn:        'full_screen_vertex'
			fragment_fn:      'bg_color_fragment'
			vertex_library:   library
			fragment_library: library
			attachments:      [MetalPipelineAttachment{
				pixel_format:     pixel_format
				blending_enabled: false
			}]
		}) or {
			self.deinit()
			return err
		}
		self.cell_bg = MetalPipeline.init(MetalPipelineOptions{
			device:           device
			vertex_fn:        'full_screen_vertex'
			fragment_fn:      'cell_bg_fragment'
			vertex_library:   library
			fragment_library: library
			attachments:      [MetalPipelineAttachment{
				pixel_format: pixel_format
			}]
		}) or {
			self.deinit()
			return err
		}
		self.cell_text = MetalPipeline.init(MetalPipelineOptions{
			device:           device
			vertex_fn:        'cell_text_vertex'
			fragment_fn:      'cell_text_fragment'
			vertex_library:   library
			fragment_library: library
			attributes:       metal_text_cell_attributes()
			vertex_stride:    $sizeof(CellText)
			step_fn:          .per_instance
			attachments:      [MetalPipelineAttachment{
				pixel_format: pixel_format
			}]
		}) or {
			self.deinit()
			return err
		}
		self.image = MetalPipeline.init(MetalPipelineOptions{
			device:           device
			vertex_fn:        'image_vertex'
			fragment_fn:      'image_fragment'
			vertex_library:   library
			fragment_library: library
			attributes:       metal_image_attributes()
			vertex_stride:    $sizeof(ImageVertex)
			step_fn:          .per_instance
			attachments:      [MetalPipelineAttachment{
				pixel_format: pixel_format
			}]
		}) or {
			self.deinit()
			return err
		}
		self.bg_image = MetalPipeline.init(MetalPipelineOptions{
			device:           device
			vertex_fn:        'bg_image_vertex'
			fragment_fn:      'bg_image_fragment'
			vertex_library:   library
			fragment_library: library
			attributes:       metal_bg_image_attributes()
			vertex_stride:    $sizeof(BgImageBuffer)
			step_fn:          .per_instance
			attachments:      [MetalPipelineAttachment{
				pixel_format: pixel_format
			}]
		}) or {
			self.deinit()
			return err
		}

		mut post_failed := false
		for source in post_shaders {
			post_library := macos.metal_new_library_source(device, source)
			if post_library == unsafe { nil } {
				post_failed = true
				break
			}
			pipeline := MetalPipeline.init(MetalPipelineOptions{
				device:           device
				vertex_fn:        'full_screen_vertex'
				fragment_fn:      'main0'
				vertex_library:   library
				fragment_library: post_library
				attachments:      [MetalPipelineAttachment{
					pixel_format:     pixel_format
					blending_enabled: false
				}]
			}) or {
				macos.metal_release(post_library)
				post_failed = true
				break
			}
			macos.metal_release(post_library)
			self.post_pipelines << pipeline
		}
		if post_failed {
			// If an error happens while building postprocess shaders we want to
			// just not use any postprocess shaders since we don't want to block
			// Ghostty from working.
			log.warn('error initializing postprocess shaders')
			for mut pipeline in self.post_pipelines {
				pipeline.deinit()
			}
			self.post_pipelines = []MetalPipeline{}
		}

		return self
	}

	pub fn (mut self MetalShaders) deinit() {
		if self.defunct {
			return
		}
		self.defunct = true
		self.bg_color.deinit()
		self.cell_bg.deinit()
		self.cell_text.deinit()
		self.image.deinit()
		self.bg_image.deinit()
		for mut p in self.post_pipelines {
			p.deinit()
		}
		self.post_pipelines = []MetalPipeline{}
		macos.metal_release(self.library)
		self.library = unsafe { nil }
	}

	fn metal_text_cell_attributes() []MetalVertexAttribute {
		return [
			MetalVertexAttribute{ format: .uint2, offset: __offsetof(CellText, glyph_pos) },
			MetalVertexAttribute{ format: .uint2, offset: __offsetof(CellText, glyph_size) },
			MetalVertexAttribute{ format: .short2, offset: __offsetof(CellText, bearings) },
			MetalVertexAttribute{ format: .ushort2, offset: __offsetof(CellText, grid_pos) },
			MetalVertexAttribute{ format: .uchar4, offset: __offsetof(CellText, color) },
			MetalVertexAttribute{ format: .uchar, offset: __offsetof(CellText, atlas) },
			MetalVertexAttribute{ format: .uchar, offset: __offsetof(CellText, bools) },
		]
	}

	fn metal_image_attributes() []MetalVertexAttribute {
		return [
			MetalVertexAttribute{ format: .float2, offset: __offsetof(ImageVertex, grid_pos) },
			MetalVertexAttribute{ format: .float2, offset: __offsetof(ImageVertex, cell_offset) },
			MetalVertexAttribute{ format: .float4, offset: __offsetof(ImageVertex, source_rect) },
			MetalVertexAttribute{ format: .float2, offset: __offsetof(ImageVertex, dest_size) },
		]
	}

	fn metal_bg_image_attributes() []MetalVertexAttribute {
		return [
			MetalVertexAttribute{ format: .float, offset: __offsetof(BgImageBuffer, opacity) },
			MetalVertexAttribute{ format: .uchar, offset: __offsetof(BgImageBuffer, info) },
		]
	}

	fn load_builtin_metal_library(device voidptr) !voidptr {
		$if compiled_metallib ? {
			start := time.sys_mono_now()
			library := macos.metal_new_library_data(device, metal_shader_library) or {
				log.error('metal error=${err}')
				return err
			}
			log.debug('shader library loaded time=${(time.sys_mono_now() - start) / 1000}us')
			return library
		} $else {
			// Unconfigured direct compiler invocations have no selected Metal build
			// artifact. The translated production build compiles it first and always
			// passes compiled_metallib; this guard never substitutes runtime compilation.
			return error('MetalShaderLibraryNotBuilt: run tools/metallib_build and compile with -d compiled_metallib')
		}
	}
}
