@[has_globals]
module renderer

import macos
import sokol.gfx
import sync

struct GGMetalTexture {
	texture voidptr
	image   gfx.Image
}

// The frame holds the GG backend lock until its command buffer is submitted.
@[heap]
struct GGMetalFrame {
mut:
	images      []GGMetalTexture
	attachments []gfx.Attachments
	finished    bool
}

$if macos && !renderer_opengl ? {
	#flag -DV_SOKOL_MTL_END_PASS_HOOK
	#include "@VMODROOT/renderer/gg_metal.h"

	fn C.witty_gg_metal_lock()
	fn C.witty_gg_metal_unlock()
	fn C.witty_gg_metal_retain_import(object voidptr) bool
	fn C.sg_mtl_render_command_encoder() voidptr
	fn C.v_sokol_mtl_set_end_pass_hook(callback fn (voidptr, voidptr, voidptr), owner voidptr) bool

	__global (
		gg_metal_users  int
		gg_metal_device voidptr
	)

	fn gg_metal_acquire(device voidptr) bool {
		C.witty_gg_metal_lock()
		defer { C.witty_gg_metal_unlock() }
		if gg_metal_users == 0 {
			// An embedding application may already own the global backend.
			if gfx.is_valid() {
				return false
			}
			mut desc := gfx.Desc{
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
			gg_metal_device = device
		}
		if gg_metal_device != device {
			return false
		}
		gg_metal_users++
		return true
	}

	fn gg_metal_release() {
		C.witty_gg_metal_lock()
		defer { C.witty_gg_metal_unlock() }
		gg_metal_users--
		if gg_metal_users == 0 {
			gfx.shutdown()
			gg_metal_device = unsafe { nil }
		}
	}

	fn gg_metal_begin() &GGMetalFrame {
		C.witty_gg_metal_lock()
		return &GGMetalFrame{}
	}

	fn (mut frame GGMetalFrame) attachment(texture voidptr, width uint, height uint) !gfx.Image {
		if texture == unsafe { nil } || width == 0 || height == 0 {
			return error('GG Metal pass has no render texture')
		}
		for value in frame.images {
			if value.texture == texture {
				return value.image
			}
		}
		// The real texture already has its Metal pixel format, including
		// BGRA8-sRGB when requested. GG uses this metadata to create a render
		// attachment. Witty binds pipelines directly to its borrowed encoder.
		retained := C.witty_gg_metal_retain_import(texture)
		image := gfx.make_image(&gfx.ImageDesc{
			render_target: true
			width:         int(width)
			height:        int(height)
			pixel_format:  .bgra8
			mtl_textures:  [texture, unsafe { nil }]!
		})
		if gfx.query_image_state(image) != .valid {
			gfx.destroy_image(image)
			if retained {
				macos.metal_release(texture)
			}
			return error('GG could not import the Metal render texture')
		}
		frame.images << GGMetalTexture{ texture: texture, image: image }
		return image
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
				MetalTarget { frame.attachment(value.texture, value.width, value.height)! }
				MetalTexture { frame.attachment(value.handle, value.width, value.height)! }
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
		view := gfx.make_attachments(&target)
		if gfx.query_attachments_state(view) != .valid {
			gfx.destroy_attachments(view)
			return error('GG could not create the Metal render pass attachments')
		}
		frame.attachments << view
		gfx.begin_pass(&gfx.Pass{
			attachments: view
			action:      action
		})
		encoder := C.sg_mtl_render_command_encoder()
		if encoder == unsafe { nil } {
			gfx.end_pass()
			return error('GG could not begin the Metal render pass')
		}
		return MetalRenderPass{ encoder: encoder, gg: true }
	}

	fn (mut frame GGMetalFrame) commit() {
		gfx.commit()
		// Destroy the attachment views before releasing the imported images.
		for attachments in frame.attachments {
			gfx.destroy_attachments(attachments)
		}
		for entry in frame.images {
			gfx.destroy_image(entry.image)
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
		installed := C.v_sokol_mtl_set_end_pass_hook(gg_metal_end_pass, owner)
		pass.complete()
		if installed {
			C.v_sokol_mtl_set_end_pass_hook(unsafe { nil }, owner)
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
