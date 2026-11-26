module font

import sprite as spritepkg
import sprite_types
import v.embed_file

// Fonts that can be embedded with Ghostty. Note they are only actually
// embedded in the binary if they are referenced by the code, so fonts
// used for tests will not result in the final binary being larger.
//
// Be careful to ensure that any fonts you embed are licensed for
// redistribution and include their license as necessary.
//
// Translated from ghostty/src/font/embedded.zig. V's `$embed_file` provides
// the same compile-time resource embedding used by Zig's `@embedFile`.

// Default fonts that we prefer for Ghostty.
pub const embedded_variable = embedded_font_bytes($embed_file('@VMODROOT/font/res/JetBrainsMono-Variable.ttf'))
pub const embedded_variable_italic = embedded_font_bytes($embed_file('@VMODROOT/font/res/JetBrainsMono-VariableItalic.ttf'))

// Symbols-only nerd font.
pub const embedded_symbols_nerd_font = embedded_font_bytes($embed_file('@VMODROOT/font/res/SymbolsNerdFont-Regular.ttf'))

// Static jetbrains mono faces, currently unused.
pub const embedded_regular = $embed_file('@VMODROOT/font/res/JetBrainsMono-Regular.ttf').to_bytes()
pub const embedded_bold = $embed_file('@VMODROOT/font/res/JetBrainsMono-Bold.ttf').to_bytes()
pub const embedded_italic = $embed_file('@VMODROOT/font/res/JetBrainsMono-Italic.ttf').to_bytes()
pub const embedded_bold_italic = $embed_file('@VMODROOT/font/res/JetBrainsMono-BoldItalic.ttf').to_bytes()

// Emoji fonts
pub const embedded_emoji = embedded_font_bytes($embed_file('@VMODROOT/font/res/NotoColorEmoji.ttf'))
pub const embedded_emoji_text = embedded_font_bytes($embed_file('@VMODROOT/font/res/NotoEmoji-Regular.ttf'))

// Font faces only read these process-lifetime assets. Use the embedded
// storage directly so each asset does not also occupy a copy on the heap.
fn embedded_font_bytes(asset embed_file.EmbedFileData) []u8 {
	bytes := asset.data()
	return unsafe { bytes.vbytes(asset.len) }
}

// Fonts below are ONLY used for testing.

// Fonts with general properties
pub const embedded_arabic = $embed_file('@VMODROOT/font/res/KawkabMono-Regular.ttf').to_bytes()

// A font for testing which is patched with nerd font symbols.
pub const embedded_test_nerd_font = $embed_file('@VMODROOT/font/res/JetBrainsMonoNerdFont-Regular.ttf').to_bytes()

// Specific font families below:
pub const embedded_code_new_roman = $embed_file('@VMODROOT/font/res/CodeNewRoman-Regular.otf').to_bytes()
pub const embedded_inconsolata = $embed_file('@VMODROOT/font/res/Inconsolata-Regular.ttf').to_bytes()
pub const embedded_geist_mono = $embed_file('@VMODROOT/font/res/GeistMono-Regular.ttf').to_bytes()
pub const embedded_jetbrains_mono = $embed_file('@VMODROOT/font/res/JetBrainsMonoNoNF-Regular.ttf').to_bytes()
pub const embedded_julia_mono = $embed_file('@VMODROOT/font/res/JuliaMono-Regular.ttf').to_bytes()

// Cozette is a unique font because it embeds some emoji characters
// but has a text presentation.
pub const embedded_cozette = $embed_file('@VMODROOT/font/res/CozetteVector.ttf').to_bytes()

// Monaspace has weird ligature behaviors we want to test in our shapers
// so we embed it here.
pub const embedded_monaspace_neon = $embed_file('@VMODROOT/font/res/MonaspaceNeon-Regular.otf').to_bytes()

// Terminus TTF is a scalable font with bitmap glyphs at various sizes.
pub const embedded_terminus_ttf = $embed_file('@VMODROOT/font/res/TerminusTTF-Regular.ttf').to_bytes()

// Spleen is a monospaced bitmap font available in multiple formats.
// Used for testing bitmap font support across different file formats.
pub const embedded_spleen_bdf = $embed_file('@VMODROOT/font/res/spleen-8x16.bdf').to_bytes()
pub const embedded_spleen_pcf = $embed_file('@VMODROOT/font/res/spleen-8x16.pcf').to_bytes()
pub const embedded_spleen_otb = $embed_file('@VMODROOT/font/res/spleen-8x16.otb').to_bytes()

// ============================================================
// Built-in sprite rendering
// ============================================================
//
// The `sprite` module implements Ghostty's full built-in sprite face. It
// returns a dependency-neutral raster which this module inserts into the
// font-owned atlas.

// render_builtin_cell_glyph renders a built-in sprite glyph into the atlas.
// Unsupported codepoints trap with runtime safety; release builds retain the blank fallback.
pub fn render_builtin_cell_glyph(mut atlas Atlas, cp u32, metrics Metrics) !Glyph {
	return sprite_face_render_glyph(mut atlas, cp, metrics, RenderOptions{})
}

// sprite_face_render_glyph renders the sprite glyph for the given
// codepoint into the atlas, faithful to ghostty's sprite Face.renderGlyph.
// This is the shared implementation used by SpriteFace.render_glyph.
//
pub fn sprite_face_has_codepoint(cp u32) bool {
	return spritepkg.has_codepoint(cp)
}

pub fn sprite_face_render_glyph(mut atlas Atlas, cp u32, metrics Metrics, opts RenderOptions) !Glyph {
	opts.assert_narrow_widths()
	face := spritepkg.SpriteFace{
		metrics: sprite_metrics(metrics)
	}
	rendered := face.render_glyph(cp, spritepkg.RenderOptions{
		cell_width: u32(opts.cell_width or { u8(1) })
	})!
	region := rendered.raster.write_atlas(mut atlas)!

	return Glyph{
		width:    region.width
		height:   region.height
		offset_x: rendered.offset_x
		offset_y: rendered.offset_y
		atlas_x:  region.x
		atlas_y:  region.y
	}
}

fn sprite_metrics(metrics Metrics) sprite_types.Metrics {
	return sprite_types.Metrics{
		cell_width:              metrics.cell_width
		cell_height:             metrics.cell_height
		cell_baseline:           metrics.cell_baseline
		underline_position:      metrics.underline_position
		underline_thickness:     metrics.underline_thickness
		strikethrough_position:  metrics.strikethrough_position
		strikethrough_thickness: metrics.strikethrough_thickness
		overline_position:       metrics.overline_position
		overline_thickness:      metrics.overline_thickness
		box_thickness:           metrics.box_thickness
		cursor_thickness:        metrics.cursor_thickness
		cursor_height:           metrics.cursor_height
		icon_height:             metrics.icon_height
		icon_height_single:      metrics.icon_height_single
		face_width:              metrics.face_width
		face_height:             metrics.face_height
		face_y:                  metrics.face_y
	}
}
