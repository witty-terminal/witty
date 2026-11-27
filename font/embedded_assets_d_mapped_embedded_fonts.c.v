module font

#include "@VMODROOT/font/embedded_darwin.h"

fn C.witty_mapped_font_bytes(section &char, len &u64) &u8

pub const embedded_variable = mapped_font_bytes(c'__font_mono')
pub const embedded_variable_italic = mapped_font_bytes(c'__font_italic')
pub const embedded_symbols_nerd_font = mapped_font_bytes(c'__font_symbols')
pub const embedded_emoji = mapped_font_bytes(c'__font_emoji')
pub const embedded_emoji_text = mapped_font_bytes(c'__font_emoji_tx')

fn mapped_font_bytes(section &char) []u8 {
	mut len := u64(0)
	bytes := C.witty_mapped_font_bytes(section, &len)
	assert bytes != unsafe { nil } && len > 0
	return unsafe { bytes.vbytes(int(len)) }
}
