module zigimg

pub const png_magic_header = [u8(0x89), `P`, `N`, `G`, 13, 10, 26, 10]!

pub enum PngColorType as u8 {
	grayscale       = 0
	rgb_color       = 2
	indexed         = 3
	grayscale_alpha = 4
	rgba_color      = 6
}
pub enum PngFilterType as u8 {
	none    = 0
	sub     = 1
	up      = 2
	average = 3
	paeth   = 4
}
pub enum PngInterlaceMethod as u8 {
	none  = 0
	adam7 = 1
}
@['nonexhaustive']
pub enum PngCompressionMethod as u8 {
	deflate = 0
}
@['nonexhaustive']
pub enum PngFilterMethod as u8 {
	adaptive = 0
}
pub struct PngTryAll {}

pub struct PngHeuristic {}

pub struct PngSpecified {
pub mut:
	filter PngFilterType @[required]
}

pub type PngFilterChoice = PngHeuristic | PngSpecified | PngTryAll

pub struct PngEncoderOptions {
pub mut:
	interlaced    bool
	filter_choice PngFilterChoice = PngHeuristic{}
}

pub fn (color PngColorType) channel_count() u8 {
	return match color {
		.grayscale, .indexed { 1 }
		.rgb_color { 3 }
		.grayscale_alpha { 2 }
		.rgba_color { 4 }
	}
}

pub fn PngColorType.from_pixel_format(format PixelFormat) !PngColorType {
	return match format {
		.rgb24, .rgb48 { .rgb_color }
		.rgba32, .rgba64 { .rgba_color }
		.grayscale1, .grayscale2, .grayscale4, .grayscale8, .grayscale16 { .grayscale }
		.grayscale8_alpha, .grayscale16_alpha { .grayscale_alpha }
		.indexed1, .indexed2, .indexed4, .indexed8 { .indexed }
		else { return error('Unsupported') }
	}
}

@[packed]
pub struct PngHeaderData {
pub mut:
	width              u32                  @[required]
	height             u32                  @[required]
	bit_depth          u8                   @[required]
	color_type         PngColorType         @[required]
	compression_method PngCompressionMethod @[required]
	filter_method      PngFilterMethod      @[required]
	interlace_method   PngInterlaceMethod   @[required]
}

pub fn (header PngHeaderData) is_valid() bool {
	if header.width == 0 || header.height == 0 || header.width > 0x7fffffff
		|| header.height > 0x7fffffff {
		return false
	}
	return match header.color_type {
		.grayscale { header.bit_depth in [u8(1), 2, 4, 8, 16] }
		.indexed { header.bit_depth in [u8(1), 2, 4, 8] }
		else { header.bit_depth in [u8(8), 16] }
	}
}

pub fn (header PngHeaderData) allows_palette() bool {
	return header.color_type in [.indexed, .rgb_color, .rgba_color]
}

pub fn (header PngHeaderData) max_palette_size() u16 {
	return if header.bit_depth > 8 { u16(256) } else { u16(1) << header.bit_depth }
}

pub fn (header PngHeaderData) channel_count() u8 {
	return header.color_type.channel_count()
}

pub fn (header PngHeaderData) pixel_bits() u8 {
	channels := header.channel_count()
	if header.bit_depth > u8(255) / channels { panic('integer overflow') }
	return header.bit_depth * channels
}

pub fn (header PngHeaderData) line_bytes() u32 {
	pixel_bits := u32(header.pixel_bits())
	if pixel_bits != 0 && header.width > u32(0xffffffff) / pixel_bits {
		panic('integer overflow')
	}
	bits := pixel_bits * header.width
	if bits > u32(0xffffffff) - 7 { panic('integer overflow') }
	return (bits + 7) / 8
}

pub fn (header PngHeaderData) get_pixel_format() PixelFormat {
	valid_depth := match header.color_type {
		.grayscale { header.bit_depth in [u8(1), 2, 4, 8, 16] }
		.indexed { header.bit_depth in [u8(1), 2, 4, 8] }
		else { header.bit_depth in [u8(8), 16] }
	}

	if !valid_depth { panic('reached unreachable code') }

	return match header.color_type {
		.grayscale {
			match header.bit_depth {
				1 { .grayscale1 }
				2 { .grayscale2 }
				4 { .grayscale4 }
				8 { .grayscale8 }
				else { .grayscale16 }
			}
		}
		.indexed {
			match header.bit_depth {
				1 { .indexed1 }
				2 { .indexed2 }
				4 { .indexed4 }
				else { .indexed8 }
			}
		}
		.rgb_color {
			if header.bit_depth == 8 {
				PixelFormat.rgb24
			} else {
				PixelFormat.rgb48
			}
		}
		.grayscale_alpha {
			if header.bit_depth == 8 {
				PixelFormat.grayscale8_alpha
			} else {
				PixelFormat.grayscale16_alpha
			}
		}
		.rgba_color {
			if header.bit_depth == 8 {
				PixelFormat.rgba32
			} else {
				PixelFormat.rgba64
			}
		}
	}
}

pub struct PNG {}

pub fn PNG.format_detect(mut stream ReadStream) !bool {
	return stream.peek(8)! == png_magic_header[..]
}

pub fn PNG.ensure_writable(image ImageUnmanaged) ! {
	if image.width > 0x7fffffff || image.height > 0x7fffffff { return error('Unsupported') }
	if image.pixel_format() !in [.indexed1, .indexed2, .indexed4, .indexed8, .grayscale1, .grayscale2,
		.grayscale4, .grayscale8, .grayscale16, .grayscale8_alpha, .grayscale16_alpha, .rgb24,
		.rgb48, .rgba32, .rgba64] {
		return error('Unsupported')
	}
}

pub fn PNG.write_image(mut stream WriteStream, image ImageUnmanaged, options PngEncoderOptions) ! {
	PNG.ensure_writable(image)!
	header := PngHeaderData{
		compression_method: .deflate
		filter_method:      .adaptive

		width:            u32(image.width)
		height:           u32(image.height)
		bit_depth:        image.pixel_format().bits_per_channel()
		color_type:       PngColorType.from_pixel_format(image.pixel_format())!
		interlace_method: if options.interlaced { .adam7 } else { .none }
	}
	if !header.is_valid() { panic('reached unreachable code') }
	PNG.write(mut stream, image.pixels, header, options.filter_choice)!
}

pub fn PNG.write(mut stream WriteStream, pixels PixelStorage, header PngHeaderData, filter_choice PngFilterChoice) ! {
	if header.interlace_method != .none || header.compression_method != .deflate
		|| header.filter_method != .adaptive {
		return error('Unsupported')
	}
	// In this exact locked revision, IHDR, PLTE, tRNS, IDAT, and IEND writing
	// bodies are commented out. Native source execution confirms only these
	// eight bytes are written. Do not replace this with an invented encoder.
	_ = pixels
	_ = filter_choice
	stream.write_all(png_magic_header[..])!
	stream.flush()!
}
