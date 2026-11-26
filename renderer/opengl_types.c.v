module renderer

import log
import opengl
import sokol.gfx

$if renderer_opengl ?|| ( !renderer_metal ?&& !macos && !ios ) {

	// OpenGL sub-types: Buffer, Frame, RenderPass, Pipeline, Sampler, Target, Texture.
	//
	// Translated from ghostty/src/renderer/opengl/*.zig.

	// ============================================================
	// OpenGL Buffer
	// ============================================================

	pub struct GLBuffer {
	pub mut:
		id     u32
		len    uint
		target opengl.BufferTarget = .array
		usage  opengl.BufferUsage  = .dynamic_draw
	}

	pub struct GLBufferOptions {
	pub:
		target opengl.BufferTarget = .array
		usage  opengl.BufferUsage  = .dynamic_draw
	}

	pub fn GLBuffer.init(opts GLBufferOptions, len uint) !GLBuffer {
		buffer := opengl.Buffer.create()!
		binding := buffer.bind(opts.target) or {
			buffer.destroy()
			return err
		}
		binding.set_data_null_manual(len, opts.usage) or {
			binding.unbind()
			buffer.destroy()
			return err
		}
		binding.unbind()
		return GLBuffer{
			id:     buffer.id
			len:    len
			target: opts.target
			usage:  opts.usage
		}
	}

	pub fn GLBuffer.init_fill[T](opts GLBufferOptions, data []T) !GLBuffer {
		buffer := opengl.Buffer.create()!
		binding := buffer.bind(opts.target) or {
			buffer.destroy()
			return err
		}
		byte_len := data.len * int($sizeof(T))
		bytes := if byte_len == 0 {
			[]u8{}
		} else {
			unsafe { voidptr(data.data).vbytes(byte_len) }
		}
		binding.set_data(bytes, opts.usage) or {
			binding.unbind()
			buffer.destroy()
			return err
		}
		binding.unbind()
		return GLBuffer{
			id:     buffer.id
			len:    uint(byte_len)
			target: opts.target
			usage:  opts.usage
		}
	}

	pub fn (mut self GLBuffer) deinit() {
		if self.id != 0 {
			opengl.Buffer{
				id: self.id
			}.destroy()
		}
		self.id = 0
		self.len = 0
	}

	pub fn (mut self GLBuffer) sync(data []u8) ! {
		buffer := opengl.Buffer{
			id: self.id
		}
		binding := buffer.bind(self.target)!
		defer {
			binding.unbind()
		}
		required := uint(data.len)
		if required > self.len {
			self.len = required * 2
			binding.set_data_null_manual(self.len, self.usage)!
		}
		binding.set_sub_data(0, data)!
	}

	pub fn (mut self GLBuffer) sync_values[T](values []T) ! {
		if values.len == 0 {
			self.sync([]u8{})!
			return
		}
		byte_len := values.len * int($sizeof(T))
		bytes := unsafe { voidptr(values.data).vbytes(byte_len) }
		self.sync(bytes)!
	}

	// Like GLBuffer.sync but takes data from an array of lists, rather than a
	// single array. Returns the number of items synced.
	pub fn (mut self GLBuffer) sync_from_array_lists[T](lists [][]T) !uint {
		buffer := opengl.Buffer{
			id: self.id
		}
		binding := buffer.bind(self.target)!
		defer {
			binding.unbind()
		}

		mut total_len := uint(0)
		for list in lists {
			total_len += uint(list.len)
		}

		// If we need more space than our buffer has, we need to reallocate. This
		// local specialization stores bytes, so `len` is a byte count.
		req_bytes := total_len * uint($sizeof(T))
		if req_bytes > self.len {
			// Reallocate the buffer to hold double what we require.
			self.len = req_bytes * 2
			binding.set_data_null_manual(self.len, self.usage)!
		}

		// We can fit within the buffer so we can just replace bytes.
		mut i := uint(0)
		for list in lists {
			if list.len == 0 {
				continue
			}
			byte_len := list.len * int($sizeof(T))
			bytes := unsafe { voidptr(list.data).vbytes(byte_len) }
			binding.set_sub_data(i, bytes)!
			i += uint(byte_len)
		}

		return total_len
	}

	// ============================================================
	// OpenGL Frame
	// ============================================================

	pub struct GLFrame {
	pub mut:
		healthy bool       = true
		api     &OpenGLAPI = unsafe { nil }
		target  &GLTarget  = unsafe { nil }
	}

	pub fn GLFrame.begin(mut api OpenGLAPI, mut target GLTarget) !GLFrame {
		return GLFrame{
			api:    unsafe { &api }
			target: unsafe { &target }
		}
	}

	fn (mut frame GLFrame) render_pass(attachment GLRenderAttachment) !GLRenderPass {
		mut pass := GLRenderPass.begin([attachment])
		$if linux && !renderer_metal ? {
			scope, format := frame.api.gg_render_pass(attachment)!
			pass.gg_scope = scope
			pass.gg_format = format
			pass.gg_api = frame.api
			pass.gg_needs_reset = true
		}
		return pass
	}

	// Complete this frame and present the target.
	//
	// NOTE: For OpenGL, `sync` is ignored and we always block.
	pub fn (mut self GLFrame) complete(sync_ bool) {
		_ = sync_
		$if linux && !renderer_metal ? {
			if self.api != unsafe { nil } && self.api.gg.handle != unsafe { nil } {
				C.witty_gg_gl_commit(self.api.gg.handle)
			}
		}
		opengl.finish()

		// If there are any GL errors, consider the frame unhealthy.
		opengl.get_error() or { self.healthy = false }

		// If the frame is healthy, present it. A presentation failure is reported
		// but does not change the health we report for the frame itself.
		if self.healthy && self.api != unsafe { nil } && self.target != unsafe { nil } {
			mut api := unsafe { self.api }
			target := unsafe { *self.target }
			api.present(target) or {
				log.error('Failed to present render target: err=${err}')
			}
		}
	}

	// ============================================================
	// OpenGL RenderPass
	// ============================================================

	pub enum GLRenderAttachmentKind as u8 {
		texture
		target
	}

	pub type GLRenderAttachmentTarget = GLTexture | GLTarget

	pub fn (self GLRenderAttachmentTarget) kind() GLRenderAttachmentKind {
		return match self {
			GLTexture { .texture }
			GLTarget { .target }
		}
	}

	pub struct GLRenderAttachment {
	pub:
		target      GLRenderAttachmentTarget @[required]
		clear_color ?[4]f32
	}

	pub struct GLRenderPass {
	pub mut:
		attachments []GLRenderAttachment
		step_number uint
	mut:
		gg_scope       voidptr
		gg_api         &OpenGLAPI = unsafe { nil }
		gg_format      gfx.PixelFormat
		gg_needs_reset bool
	}

	pub struct GLDraw {
	pub:
		primitive      opengl.Primitive @[required]
		vertex_count   uint            @[required]
		instance_count uint = 1
	}

	pub struct GLRenderStep {
	pub:
		pipeline GLPipeline @[required]
		uniforms ?GLBuffer
		buffers  []GLBuffer
		textures []GLTexture
		samplers []GLSampler
		draw     GLDraw @[required]
	}

	pub fn GLRenderPass.begin(attachments []GLRenderAttachment) GLRenderPass {
		return GLRenderPass{
			attachments: attachments
		}
	}

	pub fn (mut self GLRenderPass) step(s GLRenderStep) {
		if s.draw.instance_count == 0 {
			return
		}
		if s.pipeline.program == 0 || s.pipeline.vao == 0 {
			return
		}

		gg_draw := $if linux && !renderer_metal ? { self.apply_gg_pipeline(s) } $else { false }
		mut program_binding := ?opengl.ProgramBinding(none)
		if !gg_draw {
			self.gg_needs_reset = true
			program := opengl.Program{ id: s.pipeline.program }
			program_binding = program.use() or { return }
		}
		defer {
			if binding := program_binding {
				binding.unbind()
			}
		}

		vao := opengl.VertexArray{
			id: s.pipeline.vao
		}
		vaobind := vao.bind() or { return }
		defer {
			vaobind.unbind()
		}

		mut framebuffer := ?opengl.FramebufferBinding(none)
		defer {
			if binding := framebuffer {
				binding.unbind()
			}
		}
		if self.gg_scope == unsafe { nil } {
			attachment := self.attachments[0]
			match attachment.target {
				GLTarget {
					fbo := opengl.Framebuffer{ id: attachment.target.fbo }
					framebuffer = fbo.bind(.framebuffer) or { return }
				}
				GLTexture {
					if s.pipeline.fbo == 0 {
						return
					}
					fbo := opengl.Framebuffer{ id: s.pipeline.fbo }
					binding := fbo.bind(.framebuffer) or { return }
					framebuffer = binding
					binding.texture_2d(.color0, attachment.target.target, opengl.Texture{
						id: attachment.target.id
					}, 0) or { return }
				}
			}
			if self.step_number == 0 {
				if color := attachment.clear_color {
					opengl.clear_color(color[0], color[1], color[2], color[3])
					opengl.clear(opengl.gl_color_buffer_bit)
				}
			}
		}

		if uniforms := s.uniforms {
			opengl.Buffer{
				id: uniforms.id
			}.bind_base(.uniform, 1) or { return }
		}

		if s.buffers.len > 0 {
			first := s.buffers[0]
			if first.id != 0 {
				vaobind.bind_vertex_buffer(0, first.id, 0, int(s.pipeline.stride)) or { return }
			}
			for i in 1 .. s.buffers.len {
				buffer := s.buffers[i]
				if buffer.id == 0 {
					continue
				}

				opengl.Buffer{
					id: buffer.id
				}.bind_base(.storage, u32(i)) or { return }
			}
		}

		for i, texture in s.textures {
			if texture.id == 0 {
				continue
			}
			opengl.texture_active(u32(i)) or { return }

			opengl.Texture{
				id: texture.id
			}.bind(texture.target) or { return }
		}

		for i, sampler in s.samplers {
			if sampler.id == 0 {
				continue
			}

			opengl.Sampler{
				id: sampler.id
			}.bind(u32(i)) or { return }
		}

		if gg_draw {
			gfx.draw(0, int(s.draw.vertex_count), int(s.draw.instance_count))
		} else {
			if s.pipeline.blending_enabled {
				opengl.enable(opengl.gl_blend) or { return }
				opengl.blend_func(opengl.gl_one, opengl.gl_one_minus_src_alpha) or { return }
			} else {
				opengl.disable(opengl.gl_blend) or { return }
			}
			opengl.draw_arrays_instanced(s.draw.primitive, 0, int(s.draw.vertex_count), int(s.draw.instance_count)) or { return }
		}
		self.step_number++
	}

	pub fn (mut self GLRenderPass) complete() {
		$if linux && !renderer_metal ? {
			if self.gg_scope != unsafe { nil } {
				C.witty_gg_gl_end_pass(self.gg_scope)
				self.gg_scope = unsafe { nil }
			}
		}
		opengl.flush()
	}

	// ============================================================
	// OpenGL Pipeline
	// ============================================================

	pub struct GLPipeline {
	pub mut:
		program          u32
		fbo              u32
		vao              u32
		stride           uint
		blending_enabled bool = true
	mut:
		vertex_source   string
		fragment_source string
	}

	pub struct GLPipelineOptions {
	pub:
		vertex_source    string @[required]
		fragment_source  string @[required]
		stride           uint
		attributes       []GLVertexAttribute
		step_function    GLVertexStepFunction = .per_vertex
		blending_enabled bool                 = true
	}

	pub enum GLVertexStepFunction as u8 {
		constant
		per_vertex
		per_instance
	}

	pub enum GLVertexScalarType as u8 {
		u8_
		u16_
		u32_
		i8_
		i16_
		i32_
		f32_
		f64_
	}

	pub struct GLVertexAttribute {
	pub:
		scalar_type GLVertexScalarType
		count       u32 = 1
		offset      u32
	}

	pub fn GLPipeline.init(opts GLPipelineOptions) !GLPipeline {
		program := opengl.Program.create_vf(opts.vertex_source, opts.fragment_source)!
		program_binding := program.use() or {
			program.destroy()
			return err
		}
		defer {
			program_binding.unbind()
		}
		fbo := opengl.Framebuffer.create() or {
			program.destroy()
			return err
		}
		fbo_binding := fbo.bind(.framebuffer) or {
			fbo.destroy()
			program.destroy()
			return err
		}
		defer {
			fbo_binding.unbind()
		}
		vao := opengl.VertexArray.create() or {
			fbo.destroy()
			program.destroy()
			return err
		}
		vao_binding := vao.bind() or {
			vao.destroy()
			fbo.destroy()
			program.destroy()
			return err
		}
		defer {
			vao_binding.unbind()
		}
		configure_gl_vertex_attributes(vao_binding, opts.attributes, opts.step_function) or {
			vao.destroy()
			fbo.destroy()
			program.destroy()
			return err
		}
		return GLPipeline{
			program:          program.id
			vao:              vao.id
			fbo:              fbo.id
			stride:           opts.stride
			blending_enabled: opts.blending_enabled
			vertex_source:    opts.vertex_source
			fragment_source:  opts.fragment_source
		}
	}

	fn configure_gl_vertex_attributes(binding opengl.VertexArrayBinding, attributes []GLVertexAttribute, step_function GLVertexStepFunction) ! {
		divisor := match step_function {
			.per_vertex { u32(0) }
			.per_instance { u32(1) }
			.constant { ~u32(0) }
		}
		for i, attribute in attributes {
			index := u32(i)
			binding.enable_attrib_array(index)!
			binding.attribute_binding(index, 0)!
			binding.binding_divisor(index, divisor)!
			match attribute.scalar_type {
				.u8_ {
					binding.attribute_i_format(index, int(attribute.count), opengl.gl_unsigned_byte, attribute.offset)!
				}
				.u16_ {
					binding.attribute_i_format(index, int(attribute.count), opengl.gl_unsigned_short, attribute.offset)!
				}
				.u32_ {
					binding.attribute_i_format(index, int(attribute.count), opengl.gl_unsigned_int, attribute.offset)!
				}
				.i8_ {
					binding.attribute_i_format(index, int(attribute.count), opengl.gl_byte, attribute.offset)!
				}
				.i16_ {
					binding.attribute_i_format(index, int(attribute.count), opengl.gl_short, attribute.offset)!
				}
				.i32_ {
					binding.attribute_i_format(index, int(attribute.count), opengl.gl_int, attribute.offset)!
				}
				.f32_ {
					binding.attribute_format(index, int(attribute.count), opengl.gl_float, false, attribute.offset)!
				}
				.f64_ {
					binding.attribute_l_format(index, int(attribute.count), attribute.offset)!
				}
			}
		}
	}

	pub fn (mut self GLPipeline) deinit() {
		if self.program != 0 {
			opengl.Program{
				id: self.program
			}.destroy()
		}
		if self.vao != 0 {
			opengl.VertexArray{
				id: self.vao
			}.destroy()
		}
		if self.fbo != 0 {
			opengl.Framebuffer{
				id: self.fbo
			}.destroy()
		}
		self.program = 0
		self.vao = 0
		self.fbo = 0
	}

	// ============================================================
	// OpenGL Sampler
	// ============================================================

	pub struct GLSampler {
	pub mut:
		id u32
	}

	pub struct GLSamplerOptions {
	pub:
		min_filter opengl.TextureMinFilter @[required]
		mag_filter opengl.TextureMagFilter @[required]
		wrap_s     opengl.TextureWrap      @[required]
		wrap_t     opengl.TextureWrap      @[required]
	}

	pub fn GLSampler.init(opts GLSamplerOptions) !GLSampler {
		sampler := opengl.Sampler.create()!
		sampler.parameter(.min_filter, int(opts.min_filter)) or {
			sampler.destroy()
			return err
		}
		sampler.parameter(.mag_filter, int(opts.mag_filter)) or {
			sampler.destroy()
			return err
		}
		sampler.parameter(.wrap_s, int(opts.wrap_s)) or {
			sampler.destroy()
			return err
		}
		sampler.parameter(.wrap_t, int(opts.wrap_t)) or {
			sampler.destroy()
			return err
		}
		return GLSampler{
			id: sampler.id
		}
	}

	pub fn (mut self GLSampler) deinit() {
		if self.id != 0 {
			opengl.Sampler{
				id: self.id
			}.destroy()
		}
		self.id = 0
	}

	// ============================================================
	// OpenGL Target
	// ============================================================

	pub struct GLTarget {
	pub mut:
		fbo             u32
		rbo             u32
		texture         u32
		width           uint
		height          uint
		internal_format opengl.TextureInternalFormat = .rgba
	}

	pub struct GLTargetOptions {
	pub:
		width           uint                        @[required]
		height          uint                        @[required]
		internal_format opengl.TextureInternalFormat @[required]
		texture         bool
	}

	pub fn GLTarget.init(opts GLTargetOptions) !GLTarget {
		fbo := opengl.Framebuffer.create()!
		mut result := GLTarget{ fbo: fbo.id, width: opts.width, height: opts.height,
			internal_format: opts.internal_format }
		mut complete := false
		defer {
			if !complete { result.deinit() }
		}
		fbo_bind := fbo.bind(.framebuffer)!
		defer { fbo_bind.unbind() }
		if opts.texture {
			texture := GLTexture.init(GLTextureOptions{
				format: .rgba
				internal_format: opts.internal_format
				target: .t2d
				min_filter: .linear
				mag_filter: .linear
				wrap_s: .clamp_to_edge
				wrap_t: .clamp_to_edge
			}, opts.width, opts.height, none)!
			result.texture = texture.id
			fbo_bind.texture_2d(.color0, .t2d, opengl.Texture{ id: texture.id }, 0)!
		} else {
			rbo := opengl.Renderbuffer.create()!
			result.rbo = rbo.id
			rbo_bind := rbo.bind()!
			defer { rbo_bind.unbind() }
			rbo_bind.storage(opts.internal_format, int(opts.width), int(opts.height))!
			fbo_bind.renderbuffer(.color0, rbo)!
		}
		complete = true
		return result
	}

	pub fn (mut self GLTarget) deinit() {
		if self.fbo != 0 {
			opengl.Framebuffer{ id: self.fbo }.destroy()
		}
		if self.rbo != 0 {
			opengl.Renderbuffer{ id: self.rbo }.destroy()
		}
		if self.texture != 0 {
			opengl.Texture{ id: self.texture }.destroy()
		}
		self.fbo = 0
		self.rbo = 0
		self.texture = 0
	}

	// ============================================================
	// OpenGL Texture
	// ============================================================

	pub struct GLTexture {
	pub mut:
		id     u32
		width  uint
		height uint
		format opengl.TextureFormat = .rgba
		target opengl.TextureTarget = .t2d
		internal_format opengl.TextureInternalFormat = .rgba
	}

	pub struct GLTextureOptions {
	pub:
		format          opengl.TextureFormat         @[required]
		internal_format opengl.TextureInternalFormat @[required]
		target          opengl.TextureTarget         @[required]
		min_filter      opengl.TextureMinFilter      @[required]
		mag_filter      opengl.TextureMagFilter      @[required]
		wrap_s          opengl.TextureWrap           @[required]
		wrap_t          opengl.TextureWrap           @[required]
	}

	pub fn GLTexture.init(opts GLTextureOptions, width uint, height uint, data ?[]u8) !GLTexture {
		texture := opengl.Texture.create()!
		binding := texture.bind(opts.target) or {
			texture.destroy()
			return err
		}
		binding.parameter(.wrap_s, int(opts.wrap_s)) or {
			binding.unbind()
			texture.destroy()
			return err
		}
		binding.parameter(.wrap_t, int(opts.wrap_t)) or {
			binding.unbind()
			texture.destroy()
			return err
		}
		binding.parameter(.min_filter, int(opts.min_filter)) or {
			binding.unbind()
			texture.destroy()
			return err
		}
		binding.parameter(.mag_filter, int(opts.mag_filter)) or {
			binding.unbind()
			texture.destroy()
			return err
		}
		mut ptr := voidptr(unsafe { nil })
		if d := data {
			if d.len > 0 {
				ptr = voidptr(d.data)
			}
		}
		binding.image_2d(0, opts.internal_format, int(width), int(height), opts.format, .unsigned_byte, ptr) or {
			binding.unbind()
			texture.destroy()
			return err
		}
		binding.unbind()
		return GLTexture{
			id:     texture.id
			width:  width
			height: height
			format: opts.format
			target: opts.target
			internal_format: opts.internal_format
		}
	}

	pub fn (mut self GLTexture) deinit() {
		if self.id != 0 {
			opengl.Texture{
				id: self.id
			}.destroy()
		}
		self.id = 0
	}

	pub fn (self GLTexture) replace_region(x uint, y uint, width uint, height uint, data []u8) ! {
		mut ptr := voidptr(unsafe { nil })
		if data.len > 0 {
			ptr = voidptr(data.data)
		}
		binding := opengl.Texture{
			id: self.id
		}.bind(self.target)!
		defer {
			binding.unbind()
		}
		binding.sub_image_2d(0, int(x), int(y), int(width), int(height), self.format, .unsigned_byte, ptr)!
	}

	// ============================================================
	// OpenGL per-frame resources
	// ============================================================

	// GLFrameState owns every OpenGL resource whose contents can change while a
	// frame is being assembled. OpenGL completes synchronously, so its swap chain
	// contains one of these states, matching renderer/opengl/Frame.zig.
	pub struct GLFrameState {
	pub mut:
		uniforms                 GLBuffer
		cells                    GLBuffer
		cells_bg                 GLBuffer
		bg_image_buffer          GLBuffer
		grayscale                GLTexture
		grayscale_modified       uint
		color                    GLTexture
		color_modified           uint
		target                   GLTarget
		target_config_modified   uint
		bg_image_buffer_modified uint
		custom_shader_state      ?GLCustomShaderState
	}

	pub fn GLFrameState.init(api &OpenGLAPI, custom_shaders bool) !GLFrameState {
		mut uniforms := GLBuffer.init(api.uniform_buffer_options(), uint($sizeof(GLUniforms)))!
		mut cells := GLBuffer.init(api.fg_buffer_options(), uint($sizeof(CellText))) or {
			uniforms.deinit()
			return err
		}
		mut cells_bg := GLBuffer.init(api.bg_buffer_options(), uint($sizeof(CellBg))) or {
			cells.deinit()
			uniforms.deinit()
			return err
		}
		mut bg_image_buffer := GLBuffer.init(api.bg_image_buffer_options(), uint($sizeof(BgImageBuffer))) or {
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		mut grayscale := GLTexture.init(api.atlas_texture_options(.grayscale)!, 1, 1, [
			u8(0),
		]) or {
			bg_image_buffer.deinit()
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		mut color := GLTexture.init(api.atlas_texture_options(.bgra)!, 1, 1, [u8(0), 0, 0, 0]) or {
			grayscale.deinit()
			bg_image_buffer.deinit()
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		mut custom_shader_state := if custom_shaders {
			GLCustomShaderState.init(api) or {
				color.deinit()
				grayscale.deinit()
				bg_image_buffer.deinit()
				cells_bg.deinit()
				cells.deinit()
				uniforms.deinit()
				return err
			}
		} else {
			none
		}
		mut target := api.init_target(1, 1) or {
			if mut state := custom_shader_state {
				state.deinit()
			}
			color.deinit()
			grayscale.deinit()
			bg_image_buffer.deinit()
			cells_bg.deinit()
			cells.deinit()
			uniforms.deinit()
			return err
		}
		return GLFrameState{
			uniforms:            uniforms
			cells:               cells
			cells_bg:            cells_bg
			bg_image_buffer:     bg_image_buffer
			grayscale:           grayscale
			color:               color
			target:              target
			custom_shader_state: custom_shader_state
		}
	}

	pub fn (mut self GLFrameState) deinit() {
		self.target.deinit()
		self.uniforms.deinit()
		self.cells.deinit()
		self.cells_bg.deinit()
		self.grayscale.deinit()
		self.color.deinit()
		self.bg_image_buffer.deinit()
		if mut state := self.custom_shader_state {
			state.deinit()
		}
		self.custom_shader_state = none
	}

	pub fn (mut self GLFrameState) resize_target(api &OpenGLAPI, width uint, height uint) ! {
		if mut state := self.custom_shader_state {
			state.resize(api, width, height)!
			self.custom_shader_state = state
		}
		mut target := api.init_target(width, height)!
		self.target.deinit()
		self.target = target
	}

	// GLCustomShaderState is the ping-pong texture pair and uniforms used by a
	// chain of Shadertoy-compatible post-processing pipelines.
	pub struct GLCustomShaderState {
	pub mut:
		front_texture GLTexture
		back_texture  GLTexture
		sampler       GLSampler
		uniforms      GLBuffer
	}

	pub fn GLCustomShaderState.init(api &OpenGLAPI) !GLCustomShaderState {
		mut uniforms := GLBuffer.init(api.uniform_buffer_options(), uint($sizeof(CustomShaderUniforms)))!
		mut front_texture := GLTexture.init(api.texture_options(), 1, 1, none) or {
			uniforms.deinit()
			return err
		}
		mut back_texture := GLTexture.init(api.texture_options(), 1, 1, none) or {
			front_texture.deinit()
			uniforms.deinit()
			return err
		}
		mut sampler := GLSampler.init(api.sampler_options()) or {
			back_texture.deinit()
			front_texture.deinit()
			uniforms.deinit()
			return err
		}
		return GLCustomShaderState{
			front_texture: front_texture
			back_texture:  back_texture
			sampler:       sampler
			uniforms:      uniforms
		}
	}

	pub fn (mut self GLCustomShaderState) deinit() {
		self.front_texture.deinit()
		self.back_texture.deinit()
		self.sampler.deinit()
		self.uniforms.deinit()
	}

	pub fn (mut self GLCustomShaderState) swap() {
		front := self.front_texture
		self.front_texture = self.back_texture
		self.back_texture = front
	}

	pub fn (mut self GLCustomShaderState) resize(api &OpenGLAPI, width uint, height uint) ! {
		mut front_texture := GLTexture.init(api.texture_options(), width, height, none)!
		mut back_texture := GLTexture.init(api.texture_options(), width, height, none) or {
			front_texture.deinit()
			return err
		}
		self.front_texture.deinit()
		self.back_texture.deinit()
		self.front_texture = front_texture
		self.back_texture = back_texture
	}

	// ============================================================
	// OpenGL Shaders
	// ============================================================

	// GLUniforms is the std140 byte layout consumed by common.glsl.
	pub struct GLUniforms {
	pub mut:
		projection_matrix [16]f32
		screen_size       [2]f32
		cell_size         [2]f32
		grid_size         [2]u16
		reserved0         [12]u8
		grid_padding      [4]f32
		padding_extend    u32
		min_contrast      f32
		cursor_pos        [2]u16
		cursor_color      [4]u8
		bg_color          [4]u8
		bools             u32
		reserved2         [8]u8
	}

	pub fn gl_uniforms(value Uniforms) GLUniforms {
		mut padding_extend := u32(0)
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
		mut bools := u32(0)
		if value.bools.cursor_wide {
			bools |= 1
		}
		if value.bools.use_display_p3 {
			bools |= 2
		}
		if value.bools.use_linear_blending {
			bools |= 4
		}
		if value.bools.use_linear_correction {
			bools |= 8
		}
		return GLUniforms{
			projection_matrix: value.projection_matrix
			screen_size:       value.screen_size
			cell_size:         value.cell_size
			grid_size:         value.grid_size
			grid_padding:      value.grid_padding
			padding_extend:    padding_extend
			min_contrast:      value.min_contrast
			cursor_pos:        value.cursor_pos
			cursor_color:      value.cursor_color
			bg_color:          value.bg_color
			bools:             bools
		}
	}

	pub struct GLShaders {
	pub mut:
		bg_color       GLPipeline
		cell_bg        GLPipeline
		cell_text      GLPipeline
		image          GLPipeline
		bg_image       GLPipeline
		post_pipelines []GLPipeline
		defunct        bool
	}

	pub fn GLShaders.init(custom_shaders []string) !GLShaders {
		mut shaders := GLShaders{}
		shaders.bg_color = gl_builtin_pipeline(gl_full_screen_vertex_shader, gl_bg_color_fragment_shader_raw, [], 0, .per_vertex, false) or {
			return err
		}
		shaders.cell_bg = gl_builtin_pipeline(gl_full_screen_vertex_shader, gl_cell_bg_fragment_shader_raw, [], 0, .per_vertex, true) or {
			shaders.deinit()
			return err
		}
		shaders.cell_text = gl_builtin_pipeline(gl_cell_text_vertex_shader_raw, gl_cell_text_fragment_shader_raw, gl_text_cell_attributes(), uint($sizeof(CellText)), .per_instance, true) or {
			shaders.deinit()
			return err
		}
		shaders.image = gl_builtin_pipeline(gl_image_vertex_shader_raw, gl_image_fragment_shader_raw, gl_image_attributes(), uint($sizeof(ImageVertex)), .per_instance, true) or {
			shaders.deinit()
			return err
		}
		shaders.bg_image = gl_builtin_pipeline(gl_bg_image_vertex_shader_raw, gl_bg_image_fragment_shader_raw, gl_bg_image_attributes(), uint($sizeof(BgImageBuffer)), .per_instance, true) or {
			shaders.deinit()
			return err
		}
		for source in custom_shaders {
			pipeline := GLPipeline.init(GLPipelineOptions{
				vertex_source:   gl_full_screen_vertex_shader
				fragment_source: source
			}) or {
				for mut initialized in shaders.post_pipelines {
					initialized.deinit()
				}
				shaders.post_pipelines = []
				log.warn('error initializing postprocess shaders err=${err}')
				return shaders
			}
			shaders.post_pipelines << pipeline
		}
		return shaders
	}

	pub fn (mut self GLShaders) deinit() {
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
		self.post_pipelines = []
	}

	const gl_full_screen_vertex_shader = $embed_file('shaders/glsl/full_screen.v.glsl').to_string()
	const gl_common_shader = $embed_file('shaders/glsl/common.glsl').to_string()
	const gl_bg_color_fragment_shader_raw = $embed_file('shaders/glsl/bg_color.f.glsl').to_string()
	const gl_cell_bg_fragment_shader_raw = $embed_file('shaders/glsl/cell_bg.f.glsl').to_string()
	const gl_cell_text_vertex_shader_raw = $embed_file('shaders/glsl/cell_text.v.glsl').to_string()
	const gl_cell_text_fragment_shader_raw = $embed_file('shaders/glsl/cell_text.f.glsl').to_string()
	const gl_image_vertex_shader_raw = $embed_file('shaders/glsl/image.v.glsl').to_string()
	const gl_image_fragment_shader_raw = $embed_file('shaders/glsl/image.f.glsl').to_string()
	const gl_bg_image_vertex_shader_raw = $embed_file('shaders/glsl/bg_image.v.glsl').to_string()
	const gl_bg_image_fragment_shader_raw = $embed_file('shaders/glsl/bg_image.f.glsl').to_string()

	fn expand_gl_shader(source string) string {
		return source.replace('#include "common.glsl"', gl_common_shader)
	}

	fn gl_builtin_pipeline(vertex_source string, fragment_source string, attributes []GLVertexAttribute, stride uint, step_function GLVertexStepFunction, blending_enabled bool) !GLPipeline {
		return GLPipeline.init(GLPipelineOptions{
			vertex_source:    expand_gl_shader(vertex_source)
			fragment_source:  expand_gl_shader(fragment_source)
			attributes:       attributes
			stride:           stride
			step_function:    step_function
			blending_enabled: blending_enabled
		})
	}

	fn gl_text_cell_attributes() []GLVertexAttribute {
		return [
			GLVertexAttribute{ scalar_type: .u32_, count: 2, offset: __offsetof(CellText, glyph_pos) },
			GLVertexAttribute{ scalar_type: .u32_, count: 2, offset: __offsetof(CellText, glyph_size) },
			GLVertexAttribute{ scalar_type: .i16_, count: 2, offset: __offsetof(CellText, bearings) },
			GLVertexAttribute{ scalar_type: .u16_, count: 2, offset: __offsetof(CellText, grid_pos) },
			GLVertexAttribute{ scalar_type: .u8_, count: 4, offset: __offsetof(CellText, color) },
			GLVertexAttribute{ scalar_type: .u8_, count: 1, offset: __offsetof(CellText, atlas) },
			GLVertexAttribute{ scalar_type: .u8_, count: 1, offset: __offsetof(CellText, bools) },
		]
	}

	fn gl_image_attributes() []GLVertexAttribute {
		return [
			GLVertexAttribute{ scalar_type: .f32_, count: 2, offset: __offsetof(ImageVertex, grid_pos) },
			GLVertexAttribute{ scalar_type: .f32_, count: 2, offset: __offsetof(ImageVertex, cell_offset) },
			GLVertexAttribute{ scalar_type: .f32_, count: 4, offset: __offsetof(ImageVertex, source_rect) },
			GLVertexAttribute{ scalar_type: .f32_, count: 2, offset: __offsetof(ImageVertex, dest_size) },
		]
	}

	fn gl_bg_image_attributes() []GLVertexAttribute {
		return [
			GLVertexAttribute{ scalar_type: .f32_, count: 1, offset: __offsetof(BgImageBuffer, opacity) },
			GLVertexAttribute{ scalar_type: .u8_, count: 1, offset: __offsetof(BgImageBuffer, info) },
		]
	}
}
