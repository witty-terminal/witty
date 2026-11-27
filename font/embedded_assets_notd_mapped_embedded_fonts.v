module font

import v.embed_file

pub const embedded_variable = embedded_font_bytes($embed_file('@VMODROOT/font/res/JetBrainsMono-Variable.ttf'))
pub const embedded_variable_italic = embedded_font_bytes($embed_file('@VMODROOT/font/res/JetBrainsMono-VariableItalic.ttf'))
pub const embedded_symbols_nerd_font = embedded_font_bytes($embed_file('@VMODROOT/font/res/SymbolsNerdFont-Regular.ttf'))
pub const embedded_emoji = embedded_font_bytes($embed_file('@VMODROOT/font/res/NotoColorEmoji.ttf'))
pub const embedded_emoji_text = embedded_font_bytes($embed_file('@VMODROOT/font/res/NotoEmoji-Regular.ttf'))

// Font faces only read these process-lifetime assets. Use the embedded
// storage directly so each asset does not also occupy a copy on the heap.
fn embedded_font_bytes(asset embed_file.EmbedFileData) []u8 {
	bytes := asset.data()
	return unsafe { bytes.vbytes(asset.len) }
}
