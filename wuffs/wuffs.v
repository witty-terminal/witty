module wuffs

// Translated from Ghostty's pkg/wuffs wrapper around the pinned Wuffs v0.4
// amalgamation. Witty keeps the large generated C implementation isolated in
// its own translation unit and retains the allocation and overflow decisions
// in V.

#flag -I @VMODROOT/wuffs
$if !managed_native ? {
	#flag @VMODROOT/wuffs/wuffs_bridge.c
}
#include "wuffs_bridge.h"

fn C.witty_wuffs_decoder_size(kind int) uint

fn C.witty_wuffs_decode_image_config(kind int, decoder voidptr, decoder_size uint, source &u8, source_len uint, width &u32, height &u32, source_read_index &uint, work_buffer_len &u64, error_message &&char) int

fn C.witty_wuffs_decode_frame(kind int, decoder voidptr, source &u8, source_len uint, source_read_index uint, width u32, height u32, destination &u8, destination_len uint, work_buffer &u8, work_buffer_len uint, error_message &&char) int

fn C.witty_wuffs_swizzle(kind int, source &u8, source_len uint, destination &u8, destination_len uint, error_message &&char) int
fn C.witty_wuffs_rgba_src_over(destination &u8, source &u8, len uint)

pub const maximum_image_size = u64(4) * 1024 * 1024 * 1024

pub struct ImageData {
pub:
	width  u32
	height u32
	data   []u8
}

enum DecoderKind as int {
	png
	jpeg
}

enum SwizzleKind as int {
	g_to_rgba
	ga_to_rgba
	rgb_to_rgba
	bgr_to_rgba
	bgra_to_rgba
}

fn check_decode_result(result int, message &char, scope string) ! {
	if result != 0 {
		return
	}
	if !isnil(message) {
		text := unsafe { cstring_to_vstring(message) }
		eprintln('${scope}: decode err=${text}')
	}
	return error('WuffsError')
}

fn check_swizzle_result(result int, message &char) ! {
	if result != 0 {
		return
	}
	if !isnil(message) {
		text := unsafe { cstring_to_vstring(message) }
		eprintln('wuffs_swizzler: ${text}')
	}
	return error('WuffsError')
}

fn decode(kind DecoderKind, scope string, source []u8) !ImageData {
	decoder_size := C.witty_wuffs_decoder_size(int(kind))
	if decoder_size == 0 || decoder_size > uint(max_int) {
		return error('OutOfMemory')
	}
	mut decoder := []u8{len: int(decoder_size)}
	mut width := u32(0)
	mut height := u32(0)
	mut source_read_index := uint(0)
	mut work_buffer_len := u64(0)
	mut message := &char(unsafe { nil })
	result := C.witty_wuffs_decode_image_config(int(kind), decoder.data, decoder_size,
		source.data, uint(source.len), &width, &height, &source_read_index, &work_buffer_len,
		&message)
	check_decode_result(result, message, scope)!

	pixel_count := u64(width) * u64(height)
	if pixel_count > max_u64 / u64(sizeof(u32)) {
		return error('Overflow')
	}
	byte_len := pixel_count * u64(sizeof(u32))
	if byte_len > maximum_image_size {
		eprintln('${scope}: image size ${byte_len} is larger than the maximum allowed (${maximum_image_size})')
		return error('Overflow')
	}
	if byte_len > u64(max_int) || work_buffer_len > u64(max_int) {
		return error('OutOfMemory')
	}

	mut destination := []u8{len: int(byte_len)}
	mut work_buffer := []u8{len: int(work_buffer_len)}
	message = &char(unsafe { nil })
	frame_result := C.witty_wuffs_decode_frame(int(kind), decoder.data, source.data,
		uint(source.len), source_read_index, width, height, destination.data,
		uint(destination.len), work_buffer.data, uint(work_buffer.len), &message)
	check_decode_result(frame_result, message, scope)!
	return ImageData{
		width: width
		height: height
		data: destination
	}
}

// png_decode is the flattened V spelling of wuffs.png.decode.
pub fn png_decode(source []u8) !ImageData {
	return decode(.png, 'wuffs_png', source)
}

// jpeg_decode is the flattened V spelling of wuffs.jpeg.decode.
pub fn jpeg_decode(source []u8) !ImageData {
	return decode(.jpeg, 'wuffs_jpeg', source)
}

fn swizzle(kind SwizzleKind, source_size uint, source []u8) ![]u8 {
	assert source_size > 0
	assert uint(source.len) % source_size == 0
	destination_len := uint(source.len) / source_size * 4
	if destination_len > uint(max_int) {
		return error('OutOfMemory')
	}
	mut destination := []u8{len: int(destination_len)}
	mut message := &char(unsafe { nil })
	result := C.witty_wuffs_swizzle(int(kind), source.data, uint(source.len), destination.data,
		destination_len, &message)
	check_swizzle_result(result, message)!
	return destination
}

pub fn g_to_rgba(source []u8) ![]u8 {
	return swizzle(.g_to_rgba, 1, source)
}

pub fn ga_to_rgba(source []u8) ![]u8 {
	return swizzle(.ga_to_rgba, 2, source)
}

pub fn rgb_to_rgba(source []u8) ![]u8 {
	return swizzle(.rgb_to_rgba, 3, source)
}

pub fn bgr_to_rgba(source []u8) ![]u8 {
	return swizzle(.bgr_to_rgba, 3, source)
}

pub fn bgra_to_rgba(source []u8) ![]u8 {
	return swizzle(.bgra_to_rgba, 4, source)
}

pub fn rgba_src_over(mut destination []u8, source []u8) {
	assert destination.len == source.len && source.len % 4 == 0
	C.witty_wuffs_rgba_src_over(destination.data, source.data, uint(source.len))
}
