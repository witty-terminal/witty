module terminal

import math
import wuffs
import wuffs.swizzle

const kitty_default_frame_gap_ms = u32(40)

struct KittyAnimationFrame {
mut:
	data   []u8
	gap_ms u32
}

// Frame 1 uses Image.data. Subsequent frames store full RGBA canvases.
struct KittyAnimation {
mut:
	frames        []KittyAnimationFrame
	root_gap_ms   u32
	current_index u32
	state         AnimationAction = .stop
	shown_at_ms   ?u64
	max_loops     u32
	loops         u32
}

fn (a &KittyAnimation) count() u32 {
	return u32(a.frames.len) + 1
}

fn (a &KittyAnimation) gap(index u32) u32 {
	return if index == 0 { a.root_gap_ms } else { a.frames[index - 1].gap_ms }
}

fn (mut a KittyAnimation) set_gap(index u32, gap_ms i32) {
	gap := u32(math.max(gap_ms, i32(0)))
	if index == 0 {
		a.root_gap_ms = gap
	} else {
		a.frames[index - 1].gap_ms = gap
	}
}

fn (mut a KittyAnimation) tick(now_ms u64) ?u64 {
	if a.state == .stop || a.frames.len == 0 || (a.max_loops > 0 && a.loops >= a.max_loops) {
		return none
	}
	if a.root_gap_ms == 0 && !a.frames.any(it.gap_ms > 0) {
		return none
	}
	shown_at := math.min(a.shown_at_ms or { now_ms }, now_ms)
	a.shown_at_ms = shown_at
	elapsed := now_ms - shown_at
	gap := u64(a.gap(a.current_index))
	if elapsed < gap {
		return gap - elapsed
	}

	// Advance once per tick, skipping gapless frames. A loading animation
	// parks at the end until the client supplies another frame.
	mut index := a.current_index
	for {
		index = (index + 1) % a.count()
		if index == 0 {
			if a.state == .run_wait {
				return none
			}
			if a.max_loops > 0 {
				a.loops++
				if a.loops >= a.max_loops {
					return none
				}
			}
		}
		if a.gap(index) > 0 {
			a.current_index = index
			a.shown_at_ms = now_ms
			return u64(a.gap(index))
		}
	}
	return none
}

fn (img &Image) frame_data(number u32) ?[]u8 {
	if number == 0 || number > img.animation.count() {
		return none
	}
	return if number == 1 { img.data } else { img.animation.frames[number - 2].data }
}

pub fn (img &Image) render_data() []u8 {
	return img.frame_data(img.animation.current_index + 1) or { img.data }
}

fn (img &Image) storage_size() uint {
	mut size := uint(img.data.len)
	for frame in img.animation.frames {
		size += uint(frame.data.len)
	}
	return size
}

// Tick under the terminal lock. Unplaced data cannot wake the renderer.
pub fn (mut storage ImageStorage) animation_tick(now_ms u64) ?u64 {
	if storage.animations_idle {
		return none
	}
	mut next := ?u64(none)
	for id, mut img in storage.images {
		if img.animation.state == .stop || img.animation.frames.len == 0
			|| !storage.placements.any(it.key.image_id == id) {
			continue
		}
		previous := img.animation.current_index
		if delay := img.animation.tick(now_ms) {
			next = math.min(next or { delay }, delay)
		}
		if img.animation.current_index != previous {
			img.pixel_revision++
			storage.dirty = true
		}
		storage.images[id] = img
	}
	storage.animations_idle = next == none
	return next
}

fn (img &Image) rgba_data() ![]u8 {
	return match img.format {
		.rgba { img.data }
		.rgb { swizzle.rgb_to_rgba(img.data)! }
		.gray { swizzle.g_to_rgba(img.data)! }
		.gray_alpha { swizzle.ga_to_rgba(img.data)! }
		.png { return error('InvalidData: undecoded PNG') }
	}
}

struct KittyPixelRect {
	x      u32
	y      u32
	width  u32
	height u32
}

fn compose_kitty_rect(mut destination []u8, dst_width u32, dst_x u32, dst_y u32, source []u8, src_width u32, rect KittyPixelRect, mode CompositionMode) {
	row_bytes := int(rect.width) * 4
	for row in u32(0) .. rect.height {
		dst_start := (int(dst_y + row) * int(dst_width) + int(dst_x)) * 4
		src_start := (int(rect.y + row) * int(src_width) + int(rect.x)) * 4
		src := source[src_start..src_start + row_bytes]
		mut dst := unsafe { destination[dst_start..dst_start + row_bytes] }
		if mode == .overwrite {
			copy(mut dst, src)
		} else {
			wuffs.rgba_src_over(mut dst, src)
		}
	}
}

fn (mut storage ImageStorage) reserve_frame_bytes(mut screen Screen, img &Image, extra uint) bool {
	if img.storage_size() + extra > storage.total_limit {
		return false
	}
	room := storage.total_limit - extra
	if storage.total_bytes > room && !storage.evict_image(mut screen, storage.total_bytes - room, img.id) {
		return false
	}
	storage.total_bytes += extra
	return true
}

fn (mut storage ImageStorage) animation_changed(img Image) {
	storage.images[img.id] = img
	storage.dirty = true
	storage.animations_idle = false
}

fn animation_image(storage &ImageStorage, target Response) !Image {
	if target.id > 0 && target.image_number > 0 {
		return error('EINVAL: image ID and number are mutually exclusive')
	}
	if target.empty() {
		return error('EINVAL: image ID or number required')
	}
	img := if target.id > 0 { storage.image_by_id(target.id) } else { storage.image_by_number(target.image_number) }
	return img or { error('ENOENT: image not found') }
}

struct PendingKittyFrame {
	settings      AnimationFrameLoading
	image_id      u32
	transmit_time u64
}

fn exec_animation_frame(mut t Terminal, cmd &Command, transmission Transmission) Response {
	mut storage := &t.screens.active.kitty_images
	if mut loading := storage.loading {
		loading.add_data(cmd.data) or {
			mut reply := loading.response
			encode_error(mut reply, err.msg())
			return reply
		}
		if transmission.more_chunks {
			return Response{}
		}
		defer { storage.abort_loading() }
		return complete_kitty_frame(mut storage, mut t.screens.active, mut loading)
	}

	settings := cmd.control as AnimationFrameLoading
	mut reply := transmission.response()
	reply.frame = settings.edit_frame
	img := animation_image(storage, reply) or {
		reply.message = err.msg()
		return reply
	}
	mut loading := LoadingImage.init_from_cmd(cmd) or {
		encode_error(mut reply, err.msg())
		return reply
	}
	reply.id = img.id
	loading.response = reply
	loading.animation_frame = PendingKittyFrame{
		settings:      settings
		image_id:      img.id
		transmit_time: img.transmit_time
	}
	if transmission.more_chunks {
		storage.loading = &loading
		return Response{}
	}
	return complete_kitty_frame(mut storage, mut t.screens.active, mut loading)
}

fn complete_kitty_frame(mut storage ImageStorage, mut screen Screen, mut loading LoadingImage) Response {
	mut reply := loading.response
	pending := loading.animation_frame or { panic('missing animation frame data') }
	mut img := storage.image_by_id(pending.image_id) or {
		reply.message = 'ENOENT: image not found'
		return reply
	}
	if img.transmit_time != pending.transmit_time {
		reply.message = 'ENOENT: image not found'
		return reply
	}
	frame := loading.complete() or {
		encode_error(mut reply, err.msg())
		return reply
	}
	if frame.width > img.width || frame.height > img.height {
		reply.message = 'EINVAL: frame dimensions exceed image'
		return reply
	}
	settings := pending.settings
	count := img.animation.count()
	number := if settings.edit_frame == 0 { count + 1 } else { math.min(settings.edit_frame, count + 1) }
	reply.frame = number
	create := number > count
	if create && settings.create_frame > count {
		reply.message = 'EINVAL: base frame not found'
		return reply
	}
	root := img.rgba_data() or {
		encode_error(mut reply, err.msg())
		return reply
	}
	patch := frame.rgba_data() or {
		encode_error(mut reply, err.msg())
		return reply
	}
	extra := uint(root.len - img.data.len) + if create { uint(root.len) } else { uint(0) }
	if extra > 0 && !storage.reserve_frame_bytes(mut screen, &img, extra) {
		reply.message = 'ENOSPC: animation frame storage full'
		return reply
	}
	img.data = root
	img.format = .rgba

	mut canvas := []u8{}
	if create {
		if settings.create_frame > 0 {
			base := img.frame_data(settings.create_frame) or { panic('missing base frame') }
			canvas = base.clone()
		} else {
			canvas = []u8{len: root.len}
			bg := settings.background
			if bg.int() != 0 {
				for offset := 0; offset < canvas.len; offset += 4 {
					canvas[offset] = bg.r()
					canvas[offset + 1] = bg.g()
					canvas[offset + 2] = bg.b()
					canvas[offset + 3] = bg.a()
				}
			}
		}
	} else {
		canvas = img.frame_data(number) or { panic('missing destination frame') }
	}
	if settings.x < img.width && settings.y < img.height {
		compose_kitty_rect(mut canvas, img.width, settings.x, settings.y, patch, frame.width,
			KittyPixelRect{
				width:  math.min(frame.width, img.width - settings.x)
				height: math.min(frame.height, img.height - settings.y)
			}, settings.composition_mode)
	}
	if create {
		gap := if settings.gap_ms == 0 { kitty_default_frame_gap_ms } else { u32(math.max(settings.gap_ms, i32(0))) }
		img.animation.frames << KittyAnimationFrame{ data: canvas, gap_ms: gap }
	} else {
		img.set_frame_data(number, canvas)
		if settings.gap_ms != 0 {
			img.animation.set_gap(number - 1, settings.gap_ms)
		}
		if number - 1 == img.animation.current_index {
			img.animation.shown_at_ms = none
			img.pixel_revision++
		}
	}
	storage.animation_changed(img)
	return reply
}

fn (mut img Image) set_frame_data(number u32, data []u8) {
	if number == 1 {
		img.data = data
	} else {
		img.animation.frames[number - 2].data = data
	}
}

fn exec_animation_control(mut storage ImageStorage, settings AnimationControl) Response {
	mut result := settings.target
	mut img := animation_image(&storage, result) or {
		result.message = err.msg()
		return result
	}
	if settings.frame > 0 && settings.frame <= img.animation.count() && settings.gap_ms != 0 {
		img.animation.set_gap(settings.frame - 1, settings.gap_ms)
	}
	if settings.current_frame > 0 && settings.current_frame <= img.animation.count()
		&& settings.current_frame - 1 != img.animation.current_index {
		img.animation.current_index = settings.current_frame - 1
		img.animation.shown_at_ms = none
		img.pixel_revision++
	}
	if settings.action != .invalid {
		if img.animation.state == .stop && settings.action != .stop {
			img.animation.shown_at_ms = none
		}
		img.animation.state = settings.action
		img.animation.loops = 0
	}
	if settings.loops > 0 {
		img.animation.max_loops = settings.loops - 1
	}
	storage.animation_changed(img)
	return Response{}
}

fn exec_animation_compose(mut storage ImageStorage, mut screen Screen, settings AnimationFrameComposition) Response {
	mut result := settings.target
	mut img := animation_image(&storage, result) or {
		result.message = err.msg()
		return result
	}
	result.id = img.id
	if settings.source_frame == 0 || settings.source_frame > img.animation.count() {
		result.message = 'ENOENT: source frame not found'
		return result
	}
	if settings.dest_frame == 0 || settings.dest_frame > img.animation.count() {
		result.message = 'ENOENT: destination frame not found'
		return result
	}
	width := if settings.width > 0 { settings.width } else { img.width }
	height := if settings.height > 0 { settings.height } else { img.height }
	if u64(settings.x) + width > img.width || u64(settings.y) + height > img.height {
		result.message = 'EINVAL: destination rectangle out of bounds'
		return result
	}
	if u64(settings.left_edge) + width > img.width || u64(settings.top_edge) + height > img.height {
		result.message = 'EINVAL: source rectangle out of bounds'
		return result
	}
	if settings.source_frame == settings.dest_frame {
		x_overlaps := math.max(settings.left_edge, settings.x) < math.min(settings.left_edge, settings.x) + width
		y_overlaps := math.max(settings.top_edge, settings.y) < math.min(settings.top_edge, settings.y) + height
		if x_overlaps && y_overlaps {
			result.message = 'EINVAL: source and destination rectangles overlap'
			return result
		}
	}
	root := img.rgba_data() or {
		encode_error(mut result, err.msg())
		return result
	}
	extra := uint(root.len - img.data.len)
	if extra > 0 && !storage.reserve_frame_bytes(mut screen, &img, extra) {
		result.message = 'ENOMEM: out of memory'
		return result
	}
	img.data = root
	img.format = .rgba
	src := img.frame_data(settings.source_frame) or { panic('missing source frame') }
	mut dst := img.frame_data(settings.dest_frame) or { panic('missing destination frame') }
	compose_kitty_rect(mut dst, img.width, settings.x, settings.y, src, img.width, KittyPixelRect{
		x:      settings.left_edge
		y:      settings.top_edge
		width:  width
		height: height
	}, settings.composition_mode)
	img.set_frame_data(settings.dest_frame, dst)
	if settings.dest_frame - 1 == img.animation.current_index {
		img.pixel_revision++
	}
	storage.animation_changed(img)
	return result
}

fn (mut storage ImageStorage) delete_animation_frame(mut screen Screen, settings DeleteAnimationFrames) {
	mut img := animation_image(&storage, settings.target) or { return }
	if img.animation.frames.len == 0 {
		if settings.delete {
			storage.delete_by_id(mut screen, img.id, 0, true)
		}
		return
	}
	index := math.max(u32(1), math.min(settings.frame, img.animation.count())) - 1
	if index == 0 {
		storage.total_bytes -= uint(img.data.len)
		root := img.animation.frames[0]
		img.data = root.data
		img.animation.root_gap_ms = root.gap_ms
		img.animation.frames.delete(0)
	} else {
		storage.total_bytes -= uint(img.animation.frames[index - 1].data.len)
		img.animation.frames.delete(index - 1)
	}
	if index == img.animation.current_index {
		img.animation.current_index = math.min(index, img.animation.count() - 1)
		img.animation.shown_at_ms = none
		img.pixel_revision++
	} else if index < img.animation.current_index {
		img.animation.current_index--
	}
	storage.animation_changed(img)
}
