module font

import witty_macos as macos
import math
import opentype

fn test_coretext_render_options_match_source_defaults() {
	opts := RenderOptions{}
	assert opts.cell_width == none
	assert opts.constraint_width == 1
	assert opts.thicken_strength == 255
}

fn test_coretext_glyph_layout_preserves_source_subpixel_math() {
	layout := coretext_glyph_layout(GlyphSize{
		width: 5.2
		height: 7.1
		x: 1.25
		y: -3.5
	}, false, none, RenderOptions{
		grid_metrics: Metrics{
			cell_width: 10
			cell_height: 20
			cell_baseline: 4
			face_width: 8
			face_height: 12
		}
		thicken: true
	}) or { panic('expected a drawable glyph') }
	assert layout.px_width == 8
	assert layout.px_height == 10
	assert layout.offset_x == 1
	assert layout.offset_y == 9
	assert math.abs(layout.translate_x - 1.25) < 0.000001
	assert math.abs(layout.translate_y - 1.5) < 0.000001
	assert math.abs(layout.scale_x - 1.0) < 0.000001
	assert math.abs(layout.scale_y - 1.0) < 0.000001
}

fn named_coretext_test_font(name string, points f32) !voidptr {
	$if macos {
		cf_name := macos.CFString.create_with_bytes(name.bytes(), .utf8, false)!
		defer { cf_name.release() }
		desc := macos.CTFontDescriptor.create_with_name_and_size(cf_name, f64(points))!
		defer { desc.release() }
		return voidptr(macos.CTFont.create_with_descriptor(desc, f64(points))!)
	} $else {
		return error('CoreText unsupported')
	}
}

fn named_coretext_test_face(name string, points f32) !CoreTextFace {
	$if macos {
		base := named_coretext_test_font(name, points)!
		defer { macos.cf_release(base) }
		return CoreTextFace.init_font_copy(base, FaceOptions{
			size: DesiredSize{
				points: points
			}
		})
	} $else {
		return error('CoreText unsupported')
	}
}

fn test_coretext_basic_ascii_rendering() {
	$if macos {
		mut face := named_coretext_test_face('Menlo', 12) or { panic(err) }
		defer { face.deinit() }
		face_metrics := face.get_metrics()
		assert face_metrics.px_per_em > 0
		assert face_metrics.cell_width > 0
		assert face_metrics.ascent > 0
		assert face_metrics.descent < 0
		assert face_metrics.ascii_height or { 0 } > 0
		metrics := Metrics.calc(face_metrics)
		mut atlas := Atlas.init(512, .grayscale)!
		defer { atlas.deinit() }
		for cp in u32(32) .. u32(127) {
			glyph := face.glyph_index(cp) or { panic('Menlo is missing ASCII ${cp}') }
			face.render_glyph(mut atlas, glyph, RenderOptions{
				grid_metrics: metrics
			}) or { panic(err) }
		}
	}
}

fn test_coretext_name() {
	$if macos {
		mut face := named_coretext_test_face('Menlo', 12) or { panic(err) }
		defer { face.deinit() }
		mut buf := []u8{len: 1024}
		assert face.name(mut buf)! == 'Menlo'
	}
}

fn test_coretext_synthetic_faces_preserve_size() {
	$if macos {
		opts := FaceOptions{
			size: DesiredSize{
				points: 24
			}
		}
		mut face := named_coretext_test_face('Menlo', opts.size.points) or { panic(err) }
		defer { face.deinit() }
		expected := face.get_metrics().px_per_em

		mut italic := face.synthetic_italic(opts) or { panic(err) }
		defer { italic.deinit() }
		assert math.abs(italic.get_metrics().px_per_em - expected) < 0.001

		mut bold := face.synthetic_bold(opts) or { panic(err) }
		defer { bold.deinit() }
		assert math.abs(bold.get_metrics().px_per_em - expected) < 0.001
		assert bold.synthetic_bold? == 24.0 / 14.0
	}
}

fn test_coretext_emoji_color_detection() {
	$if macos {
		mut face := named_coretext_test_face('Apple Color Emoji', 18) or { panic(err) }
		defer { face.deinit() }
		glyph := face.glyph_index(0x1f978) or { panic('emoji glyph unavailable') }
		assert face.is_color_glyph(glyph)
		mut atlas := Atlas.init(512, .bgra)!
		defer { atlas.deinit() }
		info := face.render_glyph(mut atlas, glyph, RenderOptions{
			grid_metrics: Metrics.calc(face.get_metrics())
		}) or { panic(err) }
		assert info.width > 0
		assert info.height > 0
	}
}

fn test_coretext_in_memory_font() {
	$if macos {
		mut face := CoreTextFace.init(Library{}, embedded_regular, FaceOptions{
			size: DesiredSize{
				points: 12
			}
		}) or { panic(err) }
		defer { face.deinit() }
		assert (face.hb_font.ptr != unsafe { nil }) == Backend.selected_().has_harfbuzz()
		assert face.glyph_index(u32(`A`)) != none
		mut atlas := Atlas.init(128, .grayscale)!
		defer { atlas.deinit() }
		glyph := face.glyph_index(u32(`A`)) or { panic('missing A') }
		info := face.render_glyph(mut atlas, glyph, RenderOptions{
			grid_metrics: Metrics.calc(face.get_metrics())
		}) or { panic(err) }
		assert info.width > 0
		assert info.height > 0
	}
}

fn test_coretext_metrics_refine_hhea_and_post_tables() {
	base := FaceMetrics{
		px_per_em: 10
		cell_width: 6
		ascent: 7
		descent: -2
		line_gap: 0
	}
	metrics := refine_coretext_metrics(base, 1000, opentype.Post{
		underline_position: -100
		underline_thickness: 50
	}, none, opentype.Hhea{
		ascender: 800
		descender: -200
		line_gap: 100
	})
	assert metrics.ascent == 8
	assert metrics.descent == -2
	assert metrics.line_gap == 1
	assert metrics.underline_position? == -1
	assert metrics.underline_thickness? == 0.5
	assert metrics.strikethrough_position == none
	assert metrics.strikethrough_thickness == none
}

fn test_coretext_metrics_refine_typographic_os2_tables() {
	base := FaceMetrics{
		px_per_em: 20
		cap_height: 11
		ex_height: 5
	}
	metrics := refine_coretext_metrics(base, 1000, none, opentype.OS2{
		fs_selection: opentype.fs_selection_from_u16(0x0080)
		s_typo_ascender: 700
		s_typo_descender: -300
		s_typo_line_gap: 50
		y_strikeout_size: 40
		y_strikeout_position: 300
		has_s_cap_height: true
		s_cap_height: 650
		has_sx_height: true
		sx_height: 450
	}, opentype.Hhea{
		ascender: 900
		descender: -100
	})
	assert metrics.ascent == 14
	assert metrics.descent == -6
	assert metrics.line_gap == 1
	assert metrics.strikethrough_position? == 6
	assert metrics.strikethrough_thickness? == 0.8
	assert metrics.cap_height? == 13
	assert metrics.ex_height? == 9
}

fn test_coretext_variable_font_variation() {
	$if macos {
		opts := FaceOptions{
			size: DesiredSize{
				points: 12
			}
		}
		mut face := CoreTextFace.init(Library{}, embedded_variable, opts) or { panic(err) }
		defer { face.deinit() }
		face.set_variations([Variation{
			id: VariationId.init('wght')
			value: 400
		}], opts) or { panic(err) }
		assert face.glyph_index(u32(`A`)) != none
	}
}

fn test_coretext_svg_font_table_and_color_range() {
	$if macos {
		mut face := CoreTextFace.init(Library{}, embedded_julia_mono, FaceOptions{
			size: DesiredSize{
				points: 12
			}
		}) or { panic(err) }
		defer { face.deinit() }
		table := face.copy_table('SVG ') or { panic(err) }
		assert table.len > 0
		text_glyph := face.glyph_index(u32(`A`)) or { panic('missing A') }
		assert !face.is_color_glyph(text_glyph)
		color_glyph := face.glyph_index(0xe800) or { panic('missing SVG glyph') }
		assert face.is_color_glyph(color_glyph)
	}
}

fn test_coretext_deferred_face_queries_and_load() {
	$if macos {
		font_ptr := named_coretext_test_font('Menlo', 12) or { panic(err) }
		mut deferred := CoreTextDeferredFace{
			ct_font: font_ptr
		}
		defer { deferred.deinit() }
		assert deferred.has_codepoint(u32(`A`), .text)
		assert !deferred.has_codepoint(u32(`A`), .emoji)
		mut buf := []u8{len: 1024}
		assert deferred.family_name(mut buf)! == 'Menlo'
		mut display_buf := []u8{len: 1024}
		assert deferred.name(mut display_buf)!.len > 0
		mut loaded := deferred.load(Library{}, FaceOptions{
			size: DesiredSize{
				points: 13
			}
		}) or { panic(err) }
		defer { loaded.deinit() }
		assert loaded.glyph_index(u32(`A`)) != none
		mut lib := Library.init_backend(.coretext_freetype) or { panic(err) }
		defer { lib.deinit() }
		mut freetype_face := deferred.load_freetype(lib, FaceOptions{
			size: DesiredSize{
				points: 13
			}
		}) or { panic(err) }
		defer { freetype_face.deinit() }
		assert freetype_face.glyph_index(u32(`A`)) != none
	}
}
