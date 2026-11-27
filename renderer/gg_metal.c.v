@[has_globals]
module renderer

import witty_macos as macos
import sokol.gfx
import sync

struct GGMetalTexture {
	texture       voidptr
	image         gfx.Image
	render_target bool
}

struct GGMetalBuffer {
	handle voidptr
	buffer gfx.Buffer
}

struct GGMetalAttachments {
	colors [4]u32
	view   gfx.Attachments
}

// The frame holds the GG backend lock until its command buffer is submitted.
@[heap]
struct GGMetalFrame {
mut:
	images      []GGMetalTexture
	buffers     []GGMetalBuffer
	attachments []GGMetalAttachments
	native_draw bool
	finished    bool
}

$if macos && !renderer_opengl ? {
	#flag -DV_SOKOL_MTL_END_PASS_HOOK
	#include "@VMODROOT/renderer/gg_metal.h"

	fn C.witty_gg_metal_lock()
	fn C.witty_gg_metal_unlock()
	fn C.witty_gg_metal_retain_import(object voidptr) bool
	fn C.witty_gg_metal_pass_command_buffer() voidptr
	fn C.sg_mtl_render_command_encoder() voidptr
	fn C.v_sokol_mtl_set_end_pass_hook(callback fn (voidptr, voidptr, voidptr), owner voidptr) bool

	__global (
		gg_metal_users  int
		gg_metal_device voidptr
		gg_metal_owned  bool
	)

	fn gg_metal_acquire(device voidptr, share_context bool) bool {
		C.witty_gg_metal_lock()
		defer { C.witty_gg_metal_unlock() }
		if gg_metal_users > 0 {
			if gg_metal_device != device || gg_metal_owned == share_context {
				return false
			}
		} else if share_context {
			if !gfx.is_valid() || gfx.query_backend() != .metal_macos
				|| gfx.query_desc().environment.metal.device != device {
				return false
			}
			gg_metal_device = device
		} else {
			// An embedding application may already own the global backend.
			if gfx.is_valid() {
				return false
			}
			mut desc := gfx.Desc{
				// Terminal draws bind their existing frame buffers. Only the
				// inspector uploads a single projection matrix through Sokol.
				uniform_buffer_size: 256
				mtl_use_command_buffer_with_retained_references: true
			}
			desc.environment.metal.device = device
			desc.environment.defaults.color_format = .bgra8
			desc.environment.defaults.depth_format = .none
			retained := C.witty_gg_metal_retain_import(device)
			gfx.setup(&desc)
			if !gfx.is_valid() {
				if retained {
					macos.metal_release(device)
				}
				return false
			}
			// Runtime custom shaders use Metal's default compile options.
			gfx.mtl_set_shader_compile_options(0, 0, false)
			gg_metal_device = device
			gg_metal_owned = true
		}
		gg_metal_users++
		return true
	}

	fn gg_metal_release() {
		C.witty_gg_metal_lock()
		defer { C.witty_gg_metal_unlock() }
		gg_metal_users--
		if gg_metal_users == 0 {
			if gg_metal_owned {
				gfx.shutdown()
				gg_metal_owned = false
			}
			gg_metal_device = unsafe { nil }
		}
	}

	// The UI2 scene samples a BGRA8 view of the finished pane.
	pub fn import_ui2_metal_target(target MetalTarget) !gfx.Image {
		retained := C.witty_gg_metal_retain_import(target.texture)
		image := gfx.make_image(&gfx.ImageDesc{
			width: int(target.width)
			height: int(target.height)
			pixel_format: .bgra8
			mtl_textures: [target.texture, unsafe { nil }]!
		})
		if gfx.query_image_state(image) == .valid { return image }
		gfx.destroy_image(image)
		if retained { macos.metal_release(target.texture) }
		return error('UI2 could not import the Metal terminal frame')
	}

	pub fn (mut r Renderer) ui2_metal_target() MetalTarget {
		r.draw_mutex.lock()
		defer { r.draw_mutex.unlock() }
		mut target := r.frames[r.frame_index].target
		if target.ui2_texture != unsafe { nil } {
			target.texture = target.ui2_texture
		}
		return target
	}

	fn gg_metal_begin() &GGMetalFrame {
		C.witty_gg_metal_lock()
		return &GGMetalFrame{}
	}

	fn gg_metal_pixel_format(format MetalPixelFormat) gfx.PixelFormat {
		return match format {
			.r8unorm { .r8 }
			.rgba8unorm { .rgba8 }
			.rgba8unorm_srgb { .srgb8a8 }
			.bgra8unorm { .bgra8 }
			.bgra8unorm_srgb { unsafe { gfx.PixelFormat(C.WITTY_GG_BGRA8_SRGB) } }
			else { .none }
		}
	}

	fn gg_metal_attachment_format(format MetalPixelFormat) gfx.PixelFormat {
		value := gg_metal_pixel_format(format)
		// Stock V can still submit a pass with a native Metal pipeline. A
		// BGRA8 attachment descriptor supplies metadata for its sRGB target.
		return if format == .bgra8unorm_srgb && value == .none { .bgra8 } else { value }
	}

	fn (mut frame GGMetalFrame) sample_image(texture MetalTexture) !gfx.Image {
		format := gg_metal_pixel_format(texture.pixel_format)
		if format == .none {
			return error('GG cannot sample the Metal texture format')
		}
		return frame.import_image(texture.handle, texture.width, texture.height, format, false)
	}

	fn (mut frame GGMetalFrame) import_image(texture voidptr, width uint, height uint, format gfx.PixelFormat, render_target bool) !gfx.Image {
		if texture == unsafe { nil } || width == 0 || height == 0 {
			return error('GG Metal image has no texture')
		}
		for value in frame.images {
			if value.texture == texture && value.render_target == render_target {
				return value.image
			}
		}
		retained := C.witty_gg_metal_retain_import(texture)
		image := gfx.make_image(&gfx.ImageDesc{
			render_target: render_target
			width:         int(width)
			height:        int(height)
			pixel_format:  format
			mtl_textures:  [texture, unsafe { nil }]!
		})
		if gfx.query_image_state(image) != .valid {
			gfx.destroy_image(image)
			if retained {
				macos.metal_release(texture)
			}
			return error('GG could not import the Metal texture')
		}
		frame.images << GGMetalTexture{
			texture:       texture
			image:         image
			render_target: render_target
		}
		return image
	}

	fn (mut frame GGMetalFrame) attachment_view(target &gfx.AttachmentsDesc) !gfx.Attachments {
		// The post-processing chain revisits the same render targets as the
		// textures alternate between input and output.
		mut colors := [4]u32{}
		for i, color in target.colors {
			colors[i] = color.image.id
		}
		for entry in frame.attachments {
			if entry.colors == colors {
				return entry.view
			}
		}
		view := gfx.make_attachments(target)
		if gfx.query_attachments_state(view) != .valid {
			gfx.destroy_attachments(view)
			return error('GG could not create the Metal render pass attachments')
		}
		frame.attachments << GGMetalAttachments{ colors: colors, view: view }
		return view
	}

	fn (mut frame GGMetalFrame) render_pass(attachments []MetalRenderPassAttachment) !MetalRenderPass {
		mut target := gfx.AttachmentsDesc{}
		mut action := gfx.PassAction{}
		if attachments.len == 0 || attachments.len > target.colors.len {
			return error('invalid number of GG Metal color attachments')
		}
		for i, attachment in attachments {
			value := attachment.target
			target.colors[i].image = match value {
				MetalTarget {
					frame.import_image(value.texture, value.width, value.height,
						gg_metal_attachment_format(value.pixel_format), true)!
				}
				MetalTexture {
					frame.import_image(value.handle, value.width, value.height,
						gg_metal_attachment_format(value.pixel_format), true)!
				}
			}
			action.colors[i].store_action = .store
			if clear := attachment.clear_color {
				action.colors[i].load_action = .clear
				action.colors[i].clear_value = gfx.Color{
					r: f32(clear[0])
					g: f32(clear[1])
					b: f32(clear[2])
					a: f32(clear[3])
				}
			} else {
				action.colors[i].load_action = .load
			}
		}
		view := frame.attachment_view(&target)!
		gfx.begin_pass(&gfx.Pass{
			attachments: view
			action:      action
		})
		encoder := C.sg_mtl_render_command_encoder()
		if encoder == unsafe { nil } {
			gfx.end_pass()
			return error('GG could not begin the Metal render pass')
		}
		frame.native_draw = false
		return MetalRenderPass{ encoder: encoder, gg: frame }
	}

	fn (mut frame GGMetalFrame) commit() {
		gfx.commit()
		// Destroy the attachment views before releasing the imported images.
		for attachments in frame.attachments {
			gfx.destroy_attachments(attachments.view)
		}
		for entry in frame.images {
			gfx.destroy_image(entry.image)
		}
		for entry in frame.buffers {
			gfx.destroy_buffer(entry.buffer)
		}
		frame.finished = true
		C.witty_gg_metal_unlock()
	}

	fn (mut frame GGMetalFrame) cancel() {
		if !frame.finished {
			// A failed frame can be retried in the same swap-chain slot.
			// Wait for any earlier passes before that target is made writable.
			gfx.flush()
			frame.commit()
		}
	}

	type MetalFrameCompletion = fn (voidptr, voidptr, u64, bool)

	struct GGMetalCompletion {
		renderer voidptr
		target   voidptr
		callback voidptr
	mut:
		done       &sync.Semaphore = unsafe { nil }
		status     u64
		registered bool
	}

	fn gg_metal_finished(context voidptr, _ voidptr, status u64, _ bool) {
		registered := metal_completion_register_thread()
		defer { metal_completion_unregister_thread(registered) }
		mut completion := unsafe { &GGMetalCompletion(context) }
		completion.status = status
		completion.done.post()
	}

	fn gg_metal_end_pass(command_buffer voidptr, _ voidptr, context voidptr) {
		mut completion := unsafe { &GGMetalCompletion(context) }
		completion.registered = if completion.done == unsafe { nil } {
			macos.metal_command_buffer_add_completed_handler(command_buffer, completion.callback,
				completion.renderer, completion.target)
		} else {
			macos.metal_command_buffer_add_completed_handler(command_buffer, voidptr(gg_metal_finished),
				context, completion.target)
		}
	}

	fn (mut frame GGMetalFrame) submit(pass &MetalRenderPass, native &MetalFrame, wait bool) ! {
		mut completion := GGMetalCompletion{
			renderer: native.renderer
			target:   native.target
			callback: native.completion_callback
			done:     if wait { sync.new_semaphore() } else { unsafe { nil } }
		}
		defer {
			if completion.done != unsafe { nil } {
				completion.done.destroy()
			}
		}
		owner := voidptr(&completion)
		command_buffer := C.witty_gg_metal_pass_command_buffer()
		if command_buffer != unsafe { nil } {
			// UI2 can use the end-pass hook for its own window pass.
			gg_metal_end_pass(command_buffer, unsafe { nil }, owner)
			pass.complete()
		} else {
			installed := C.v_sokol_mtl_set_end_pass_hook(gg_metal_end_pass, owner)
			pass.complete()
			if installed {
				C.v_sokol_mtl_set_end_pass_hook(unsafe { nil }, owner)
			}
		}
		if !completion.registered {
			return error('GG Metal frame completion could not be registered')
		}
		frame.commit()
		if wait {
			completion.done.wait()
			callback := unsafe { MetalFrameCompletion(completion.callback) }
			callback(completion.renderer, completion.target, completion.status, true)
		}
	}

	fn gg_metal_end_render_pass() {
		gfx.end_pass()
	}
}
