module terminal

// --- Original Ghostty Comments Start: src/terminal/kitty/graphics_image.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/terminal/kitty/graphics_image.zig
//
// Maximum width or height of an image. Taken directly from Kitty.
// Maximum size in bytes, taken from Kitty.
// An image that is still being loaded. The image should be initialized
// using init on the first chunk and then addData for each subsequent
// chunk. Once all chunks have been added, complete should be called
// to finalize the image.
// The in-progress image. The first chunk must have all the metadata
// so this comes from that initially.
// The data that is being built up.
// This is non-null when a transmit and display command is given
// so that we display the image after it is fully loaded.
// Quiet is the quiet settings for the initial load command. This is
// used if q isn't set on subsequent chunks.
// Initialize a chunked immage from the first image transmission.
// If this is a multi-chunk image, this should only be the FIRST
// chunk.
// Build our initial image from the properties sent via the control.
// These can be overwritten by the data loading process. For example,
// PNG loading sets the width/height from the data.
// Special case for the direct medium, we just add the chunk directly.
// Otherwise, the payload data is guaranteed to be a path.
// posix.realpath *asserts* that the path does not have
// internal nulls instead of erroring.
// Depending on the medium, load the data from the path.
// Reads the data from a shared memory segment.
// windows is currently unsupported, does it support shm?
// libc is required for shm_open
// Since we're only supporting posix then max_path_bytes should
// be enough to stack allocate the path.
// The size from stat on may be larger than our expected size because
// shared memory has to be a multiple of the page size.
// Png we decode the full data size because later decoding will
// get the proper dimensions and assert validity.
// For these formats we have a size we must have.
// Our stat size must be at least the expected size otherwise
// the shared memory data is invalid.
// Our end size always uses the expected size so we cut off the
// padding for mmap alignment.
// Reads the data from a temporary file and returns it. This allocates
// and does not free any of the data, so the caller must free it.
//
// This will also delete the temporary file if it is in a safe location.
// Verify file seems "safe". This is logic copied directly from Kitty,
// mostly. This is really rough but it will catch obvious bad actors.
// Temporary file logic
// File must be a regular file
// Read the file
// Set our data
// Returns true if path appears to be in a temporary directory.
// Copies logic from Kitty.
// The temporary dir is sometimes a symlink. On macOS for
// example /tmp is /private/var/...
// Adds a chunk of data to the image. Use this if the image
// is coming in chunks (the "m" parameter in the protocol).
// If no data, skip
// If our data would get too big, return an error
// Ensure we have enough room to add the data
// to the end of the ArrayList before doing so.
// Complete the chunked image, returning a completed image.
// Decompress the data if it is compressed.
// Decode the png if we have to
// Validate our dimensions.
// Data length must be what we expect
// Set our time
// Everything looks good, copy the image data over.
// Debug function to write the data to a file. This is useful for
// capturing some test data for unit tests.
// Decompress the data in-place.
// Open our zlib stream
// Write it to an array list
// Empty our current data list, take ownership over managed array list
// Make sure we note that our image is no longer compressed
// Decode the data as PNG. This will also updated the image dimensions.
// Replace our data
// Store updated image dimensions
// Image represents a single fully loaded image.
// Set this to true if this image was loaded by a command that
// doesn't specify an ID or number, since such commands should
// not be responded to, even though we do currently give them
// IDs in the public range (which is bad!).
// Mostly for logging
// The rect taken up by some image placement, in grid cells. This will
// be rounded up to the nearest grid cell since we can't place images
// in partial grid cells.
// This specifically tests we ALLOW invalid RGB data because Kitty
// documents that this should work.
// <ESC>_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA<ESC>\
// should be decompressed
// should be decompressed
// Setup our initial chunk
// Read our remaining chunks
// Complete
// Setup our initial chunk
// Read our remaining chunks
// Complete
// Temporary file should still be there
// Temporary file should be gone
//
// --- Original Ghostty Comments End: src/terminal/kitty/graphics_image.zig

// Kitty graphics protocol image types.
//
// Source: kitty/graphics_image.zig, kitty/graphics_render.zig
//
// Defines the Image (fully loaded image data), LoadingImage (in-progress
// image loading), Rect (placement rectangle in grid cells), and
// RenderPlacement (placement rendering information) types.
import os
import time
import zigimg
import log
import wuffs.png as wuffs_png

// POSIX shared-memory / mmap bindings, required for the shared_memory
// medium (t=s). shm_open needs libc; these map directly to the Zig
// std.c.shm_open / posix.fstat / posix.mmap calls.
$if !windows {
	#include <sys/mman.h>
	#include <sys/stat.h>
	#include <fcntl.h>
	#include <unistd.h>
}

fn C.shm_open(name &char, oflag int, mode u32) int

fn C.shm_unlink(name &char) int

fn C.close(fd int) int

fn C.fstat(fd int, buf &C.stat) int

fn C.mmap(addr voidptr, length uint, prot int, flags int, fd int, offset i64) voidptr

fn C.munmap(addr voidptr, length uint) int

fn C.memcpy(dest voidptr, src voidptr, n uint) voidptr

// mmap protection / flag constants from <sys/mman.h> and <fcntl.h>.
// These are C macros; we reference them directly (C.PROT_READ etc.).
// C.O_RDONLY is already provided by the standard headers.

// C.stat is already declared by the `os` module (imported above), so we
// reuse its declaration here for fstat().

// Maximum width or height of an image. Taken directly from Kitty.
pub const max_dimension = 10000

// Maximum size in bytes, taken from Kitty.
pub const max_image_size = 400 * 1024 * 1024 // 400MB

// ============================================================
// Image
// ============================================================

// Image represents a single fully loaded image that can be placed
// in the terminal grid.
pub struct Image {
pub mut:
	// Image identifier.
	id u32
	// Image number (for image number-based addressing).
	number u32
	// Image width in pixels.
	width u32
	// Image height in pixels.
	height u32
	// The pixel format of the image data.
	format TransmissionFormat = .rgb
	// Compression used on the data.
	compression TransmissionCompression = .none_
	// The raw pixel data.
	data []u8
	// Timestamp when image was transmitted. Set in complete(), matching
	// ghostty (which leaves it undefined until then).
	transmit_time u64
	// True if image was loaded by a command that doesn't specify
	// an ID or number.
	implicit_id bool
}

// Free the image data.
pub fn (mut self Image) deinit() {
	self.data = []
}

// Mostly for logging.
pub fn (self &Image) without_data() Image {
	return Image{
		id:            self.id
		number:        self.number
		width:         self.width
		height:        self.height
		format:        self.format
		compression:   self.compression
		transmit_time: self.transmit_time
		implicit_id:   self.implicit_id
	}
}

// ============================================================
// LoadingImage
// ============================================================

// LoadingImage represents an image that is still being loaded in
// chunks. Once all chunks are received, it is completed into an Image.
pub struct LoadingImage {
pub mut:
	// The in-progress image with metadata from the first chunk.
	image Image
	// The raw data being built up from chunks.
	data []u8
	// Non-null when transmit and display command is given to display
	// the image after loading.
	display ?Display
	// Quiet settings for the initial load command (used if q isn't
	// set on subsequent chunks).
	quiet Quiet = .no
	// Identifiers from the first chunk, used when replying to later chunks.
	response Response
}

// Free the loading image data.
pub fn (mut self LoadingImage) deinit() {
	self.data = []
	self.image.deinit()
}

pub fn (mut self LoadingImage) destroy() {
	self.deinit()
}

// Initialize a chunked image from the first image transmission.
// If this is a multi-chunk image, this should only be the FIRST chunk.
pub fn LoadingImage.init_from_cmd(cmd &Command) !LoadingImage {
	t := cmd.transmission() or { return error('no transmission in command') }
	mut result := LoadingImage{
		image:    Image{
			id:          t.image_id
			number:      t.image_number
			width:       t.width
			height:      t.height
			compression: t.compression
			format:      t.format_
		}
		display:  cmd.display()
		quiet:    cmd.quiet
		response: t.response()
	}

	// Special case for the direct medium, we just add the chunk directly.
	if t.medium == .direct {
		result.add_data(cmd.data)!
		return result
	}

	// Otherwise, the payload data is guaranteed to be a path.

	// posix.realpath *asserts* that the path does not have internal nulls
	// instead of erroring, so we reject those up-front.
	if cmd.data.contains(u8(0)) {
		return error('invalid data: path contains null byte')
	}

	// For file / temporary_file we resolve to the absolute (real) path.
	// For shared_memory we use the raw path as-is (it names a shm object,
	// not a filesystem path).
	path := match t.medium {
		.direct {
			return error('invalid data: unreachable')
		}
		.file, .temporary_file {
			os.real_path(cmd.data.bytestr())
		}
		.shared_memory {
			cmd.data.bytestr()
		}
	}

	if path.len == 0 {
		return error('invalid data: empty file path')
	}

	// Depending on the medium, load the data from the path.
	match t.medium {
		.direct {
			return error('invalid data: unreachable')
		}
		.file {
			result.read_file(.file, t, path)!
		}
		.temporary_file {
			result.read_file(.temporary_file, t, path)!
		}
		.shared_memory {
			result.read_shared_memory(t, path)!
		}
	}

	return result
}

// Reads the data from a shared memory segment.
fn (mut self LoadingImage) read_shared_memory(t Transmission, path string) ! {
	// POSIX shared memory (shm_open/mmap) is unavailable on Windows.
	$if windows {
		return error('unsupported medium')
	} $else {
		// shm_open requires a NUL-terminated path. Since we only support posix
		// here, a stack C string is sufficient.
		pathz := &char(path.str)

		fd := C.shm_open(pathz, C.O_RDONLY, 0)
		if fd < 0 {
			return error('invalid data: unable to open shared memory ${path}')
		}
		// Always close and unlink the shm object when we're done, matching
		// the Zig `defer` cleanup order (close then unlink).
		defer {
			C.close(fd)
			C.shm_unlink(pathz)
		}

		// The size from stat may be larger than our expected size because
		// shared memory has to be a multiple of the page size.
		st := C.stat{}
		if C.fstat(fd, &st) != 0 {
			return error('invalid data: unable to fstat shared memory ${path}')
		}
		if st.st_size <= 0 {
			return error('invalid data: shared memory empty')
		}
		stat_size := uint(st.st_size)

		expected_size := match self.image.format {
			// Png we decode the full data size because later decoding will
			// get the proper dimensions and assert validity.
			.png {
				stat_size
			}
			// For these formats we have a size we must have.
			.gray, .gray_alpha, .rgb, .rgba {
				bpp := uint(self.image.format.bpp())
				uint(self.image.width) * uint(self.image.height) * bpp
			}
		}

		// Our stat size must be at least the expected size otherwise
		// the shared memory data is invalid.
		if stat_size < expected_size {
			return error('invalid data: shared memory size too small expected=${expected_size} actual=${stat_size}')
		}

		// mmap always uses the stat size.
		map_ptr := C.mmap(unsafe { nil }, stat_size, C.PROT_READ, C.MAP_SHARED, fd, 0)
		if map_ptr == voidptr(C.MAP_FAILED) || map_ptr == unsafe { nil } {
			return error('invalid data: unable to mmap shared memory ${path}')
		}
		defer {
			C.munmap(map_ptr, stat_size)
		}

		// Our end size always uses the expected size so we cut off the
		// padding for mmap alignment.
		start := uint(t.offset)
		end := if t.size > 0 {
			e := uint(t.offset) + uint(t.size)
			if e < expected_size {
				e
			} else {
				expected_size
			}
		} else {
			expected_size
		}
		if start > end || end > stat_size {
			return error('invalid data: shared memory offset out of bounds')
		}

		// Copy the mapped region into our data buffer (the mapping is freed
		// by the deferred munmap above).
		n := int(end - start)
		if n > 0 {
			mut buf := []u8{len: n}
			unsafe {
				C.memcpy(buf.data, voidptr(uint(map_ptr) + start), uint(n))
			}
			self.data << buf
		}
	}
}

// Reads the data from a regular / temporary file and appends it to the
// loading image. This applies Kitty's "safe file" checks and, for
// temporary files, deletes the file after reading (regardless of success).
fn (mut self LoadingImage) read_file(medium TransmissionMedium, t Transmission, path string) ! {
	// Verify file seems "safe". This is logic copied directly from Kitty,
	// mostly. This is really rough but it will catch obvious bad actors.
	if path.starts_with('/proc/') || path.starts_with('/sys/')
		|| (path.starts_with('/dev/') && !path.starts_with('/dev/shm/')) {
		return error('invalid data: unsafe file path ${path}')
	}

	// Temporary file logic
	if medium == .temporary_file {
		if !is_path_in_temp_dir(path) {
			return error('temporary file not in temp dir')
		}
		if !path.contains('tty-graphics-protocol') {
			return error('temporary file not named correctly')
		}
	}
	// Delete the temporary file when we're done, regardless of outcome.
	defer {
		if medium == .temporary_file {
			os.rm(path) or {}
		}
	}

	// File must be a regular file.
	st := os.stat(path) or { return error('invalid data: failed to stat file ${path}') }
	if st.get_filetype() != .regular {
		return error('invalid data: not a regular file ${path}')
	}

	// Mirror the source file.reader buffer and appendRemaining(.limited(size)).
	// Reaching the limit is StreamTooLong even when it coincides with EOF.
	size := if t.size > 0 {
		if uint(t.size) < uint(max_image_size) { int(t.size) } else { max_image_size }
	} else {
		max_image_size
	}
	mut f := os.open(path) or { return error('InvalidData: failed to open file ${path}') }
	defer { f.close() }
	if t.offset > 0 {
		f.seek(i64(t.offset), .start) or { return error('InvalidData: failed to seek file') }
	}
	mut data := []u8{}
	mut buffer := []u8{len: 4096}
	for {
		remaining := size - data.len
		if remaining == 0 {
			return error('InvalidData: stream too long')
		}
		count := f.read(mut buffer[..if remaining < buffer.len { remaining } else { buffer.len }]) or {
			if err is os.Eof { break }
			return error('InvalidData: failed to read file')
		}
		data << buffer[..count]
	}
	assert self.data.len == 0
	self.data = data
}

// Adds a chunk of data to the image. Use this if the image
// is coming in chunks (the "m" parameter in the protocol).
pub fn (mut self LoadingImage) add_data(data []u8) ! {
	// If no data, skip
	if data.len == 0 {
		return
	}
	// If our data would get too big, return an error
	if self.data.len + data.len > max_image_size {
		return error('InvalidData: image data too large max_size=${max_image_size}')
	}
	// Append the data
	self.data << data
}

// Complete the chunked image, returning a completed image.
pub fn (mut self LoadingImage) complete() !Image {
	// Decompress the data if it is compressed.
	self.decompress()!

	// Decode the PNG if we have to. PNG decoding produces raw pixel data
	// and sets the width/height/format from the PNG header.
	if self.image.format == .png {
		self.decode_png()!
	}

	// Validate our dimensions.
	if self.image.width == 0 || self.image.height == 0 {
		return error('dimensions required')
	}
	if self.image.width > max_dimension || self.image.height > max_dimension {
		return error('dimensions too large')
	}

	// Data length must be what we expect
	bpp := int(self.image.format.bpp())
	expected_len := int(self.image.width) * int(self.image.height) * bpp
	actual_len := self.data.len
	if actual_len != expected_len {
		return error('InvalidData: unexpected length image id=${self.image.id} expected=${expected_len} actual=${actual_len}')
	}

	// Set our time.
	self.image.transmit_time = time.sys_mono_now()

	// Everything looks good, copy the image data over.
	mut result := self.image
	result.data = self.data.clone()
	self.image = Image{}
	self.data = []
	return result
}

// Debug function to write the data to a file. This is useful for
// capturing test data for unit tests.
pub fn (self LoadingImage) debug_dump() ! {
	compression := if self.image.compression == .none_ {
		'none'
	} else {
		self.image.compression.str()
	}
	filename := 'image-${self.image.format.str()}-${compression}-${self.image.width}x${self.image.height}-${self.image.id}.data'
	mut file := os.create(filename)!
	defer {
		file.close()
	}
	file.write(self.data)!
}

// Decompress the data in-place.
fn (mut self LoadingImage) decompress() ! {
	match self.image.compression {
		.none_ {}
		.zlib_deflate { self.decompress_zlib()! }
	}
}

fn (mut self LoadingImage) decompress_zlib() ! {
	decompressed := zigimg.decode_zlib_bounded(self.data, uint(max_image_size)) or {
		log.warn('failed to read decompressed data: ${err}')
		return error('DecompressionFailed')
	}
	self.data = decompressed
	self.image.compression = .none_
}

// Decode the data as PNG. This will also update the image dimensions.
//
fn (mut self LoadingImage) decode_png() ! {
	assert self.image.format == .png
	if self.data.len == 0 {
		return error('invalid data: empty png')
	}

	result := wuffs_png.decode(self.data) or { return error('InvalidData') }
	if result.data.len > max_image_size {
		log.warn('png image too large size=${result.data.len} max_size=${max_image_size}')
		return error('InvalidData')
	}

	self.data = result.data.clone()

	// Store updated image dimensions.
	self.image.width = result.width
	self.image.height = result.height
	self.image.format = .rgba
}

// Returns true if path appears to be in a temporary directory.
// Copies the upstream checks and the selected OS temporary directory.
fn is_path_in_temp_dir(path string) bool {
	if path.starts_with('/tmp') {
		return true
	}
	if path.starts_with('/dev/shm') {
		return true
	}

	// src/os/file.zig chooses TMPDIR, then TMP, then /tmp on POSIX.
	// Only that selected directory has its realpath checked.
	mut selected := ?string(none)
	$if windows {
		selected = os.getenv_opt('TMP')
	} $else {
		selected = os.getenv_opt('TMPDIR')
		if selected == none { selected = os.getenv_opt('TMP') }
		if selected == none { selected = '/tmp' }
	}
	if dir := selected {
		if path.starts_with(dir) { return true }
		real_dir := os.real_path(dir)
		if path.starts_with(real_dir) { return true }
	}

	return false
}

// ============================================================
// Rect
// ============================================================

// Rect represents the rectangular area taken up by an image placement
// in grid cells (rounded up to nearest grid cell).
pub struct Rect {
pub:
	top_left     Pin
	bottom_right Pin
}

fn (self &Rect) contains(pin Pin) bool {
	return pin.x >= self.top_left.x && pin.x <= self.bottom_right.x
		&& pin.is_between(self.top_left, self.bottom_right)
}

// ============================================================
// RenderPlacement
// ============================================================

// RenderPlacement holds placement and rendering information for
// an image in the terminal view.
pub struct RenderPlacement {
pub mut:
	// Top-left corner of the image in grid coordinates.
	top_left Pin
	// Horizontal offset in pixels from the top-left corner of the grid cell.
	offset_x u32
	// Vertical offset in pixels from the top-left corner of the grid cell.
	offset_y u32
	// X coordinate of source rectangle in the image.
	source_x u32
	// Y coordinate of source rectangle in the image.
	source_y u32
	// Width of source rectangle (from the image data).
	source_width u32
	// Height of source rectangle (from the image data).
	source_height u32
	// Final width of the image in pixels at destination.
	dest_width u32
	// Final height of the image in pixels at destination.
	dest_height u32
}
