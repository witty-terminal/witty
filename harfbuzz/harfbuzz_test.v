module harfbuzz

import freetype
import witty_macos as macos
import os

const test_font_path = os.join_path(@VMODROOT, 'font', 'res', 'JetBrainsMono-Regular.ttf')

struct BlobUserDataProbe {
mut:
	destroyed bool
}

fn destroy_blob_user_data(data voidptr) {
	mut probe := unsafe { &BlobUserDataProbe(data) }
	probe.destroyed = true
}

fn test_version_surface() {
	current := version()
	assert current.major > 0
	assert version_at_least(Version{
		major: 1
	})
	assert version_string().len > 0
}

fn test_blob_lifecycle_and_user_data() {
	assert sizeof(MemoryMode) == 1
	assert u8(MemoryMode.duplicate) == 0
	assert u8(MemoryMode.readonly) == 1
	assert u8(MemoryMode.writable) == 2
	assert u8(MemoryMode.readonly_may_make_writable) == 3

	mut blob := Blob.create('hello'.bytes(), .duplicate)!
	mut key := u8(0)
	mut probe := BlobUserDataProbe{}
	assert blob.set_user_data(&key, &probe, destroy_blob_user_data, false)
	assert blob.get_user_data(&key) == voidptr(&probe)
	blob.destroy()
	assert probe.destroyed
	assert blob.ptr == unsafe { nil }

	mut empty := Blob.create([], .duplicate)!
	empty.destroy()
}

fn test_freetype_face_and_font_surface() {
	mut library := freetype.Library.init()!
	defer { library.deinit() }
	mut ft_face := library.init_face(test_font_path, 0)!
	defer { ft_face.deinit() }

	mut face := Face.create_freetype(ft_face.handle)!
	assert face.ptr != unsafe { nil }
	mut generic_font := Font.create(&face)!
	generic_font.set_scale(16, 32)
	generic_font.set_freetype_funcs()
	generic_font.destroy()
	face.destroy()

	mut ft_font := Font.create_freetype(ft_face.handle)!
	ft_font.set_scale(64, 64)
	ft_font.set_freetype_funcs()
	ft_font.destroy()
}

fn test_coretext_font_surface() {
	$if macos {
		name := macos.CFString.create_with_bytes('Monaco'.bytes(), .utf8, false)!
		defer { name.release() }
		descriptor := macos.CTFontDescriptor.create_with_name_and_size(name, 12)!
		defer { descriptor.release() }
		ct_font := macos.CTFont.create_with_descriptor(descriptor, 12)!
		defer { ct_font.release() }
		mut hb_font := Font.create_coretext(voidptr(ct_font))!
		assert hb_font.ptr != unsafe { nil }
		hb_font.destroy()
	}
}

fn test_common_enum_layouts() {
	assert sizeof(ContentType) == 1
	assert sizeof(ClusterLevel) == 1
	assert sizeof(Direction) == 1
	assert sizeof(Script) == 4
	assert sizeof(GlyphInfo) == 20
	assert sizeof(GlyphPosition) == 20
	assert u8(ClusterLevel.graphemes) == 3
	assert u8(Direction.bit) == 7
	assert u32(Script.common) == 0x5a797979
	assert u32(Script.arabic) == 0x41726162
	assert u32(Script.math) == 0x5a6d7468
	assert u32(Script.invalid) == 0
}

fn test_language_and_feature_roundtrip() {
	language := Language.from_string('en-US')
	assert language.to_string() == 'en-us'
	assert Language.get_default().to_string().len > 0

	feature := Feature.from_string('dlig') or {
		assert false
		return
	}
	mut buf := []u8{len: 64}
	feature.to_string(mut buf)
	text := unsafe { cstring_to_vstring(&char(buf.data)) }
	assert text == 'dlig'
}

fn test_buffer_complete_input_and_property_surface() {
	mut buffer := Buffer.create()!
	defer { buffer.destroy() }
	buffer.reset()
	buffer.set_content_type(.unicode)
	assert buffer.get_content_type() == .unicode
	buffer.set_cluster_level(.characters)
	buffer.set_direction(.ltr)
	assert buffer.get_direction() == .ltr
	buffer.set_script(.arabic)
	assert buffer.get_script() == .arabic
	language := Language.from_string('en')
	buffer.set_language(language)
	assert buffer.get_language().to_string() == 'en'

	buffer.add(u32(`A`), 27)
	buffer.add_codepoints([u32(`B`), u32(`C`)])
	buffer.add_utf32([u32(`D`), u32(`E`)])
	buffer.add_utf16([u16(`F`), u16(`G`)])
	buffer.add_utf8('HI'.bytes())
	buffer.add_latin1('JK'.bytes())
	assert buffer.get_length() == 11
	mut native_info_length := u32(0)
	native_infos := C.hb_buffer_get_glyph_infos(buffer.ptr, &native_info_length)
	infos := buffer.get_glyph_infos()
	assert infos.len == 11
	assert infos.data == voidptr(native_infos)
	positions := buffer.get_glyph_positions() or {
		assert false
		return
	}
	assert positions.len == 11
	mut native_position_length := u32(0)
	native_positions := C.hb_buffer_get_glyph_positions(buffer.ptr, &native_position_length)
	assert positions.data == voidptr(native_positions)

	buffer.reset()
	buffer.add_utf8('abc'.bytes())
	buffer.guess_segment_properties()
	assert buffer.get_direction() == .ltr
	assert buffer.get_script() == .latin
}
