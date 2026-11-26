module terminal

// Fundamental types for the terminal module.
// These types are used by both Screen and Terminal.

// ============================================================
// Constants
// ============================================================

// The default style ID (no style applied).
pub const default_style_id = u32(0)

// ============================================================
// Cell types
// ============================================================

// CellWide describes the width behavior of a cell.
pub enum CellWide as u8 {
	narrow      = 0
	wide        = 1
	spacer_tail = 2
	spacer_head = 3
}

// ContentTag describes what kind of content a cell holds.
// The content tag dictates the active field in CellData and possibly
// some other behaviors.
pub enum ContentTag as u8 {
	// A single codepoint, could be zero to be empty cell.
	codepoint          = 0
	// A codepoint that is part of a multi-codepoint grapheme cluster.
	// The codepoint field is active, but also expect more
	// codepoints in the graphemes data.
	codepoint_grapheme = 1
	// The cell has no text but only a background color. This is an
	// optimization so that cells with only backgrounds don't take up
	// style map space and also don't require a style map lookup.
	bg_color_palette   = 2
	bg_color_rgb       = 3
}

// SemanticContent describes what the cell content semantically represents.
pub enum SemanticContent as u8 {
	output = 0
	input  = 1
	prompt = 2
}

// CellData is the data for a single cell in the terminal grid.
//
// The zero value of this struct must be a valid cell representing empty,
// since we zero initialize cells by default.
#include "@VMODROOT/terminal/page_storage.h"
pub struct C.WittyPageCell {
pub mut:
	content_tag ContentTag
	// Source packed union codepoint member has exactly 21 active bits.
	codepoint        u32
	style_id         u32
	wide             CellWide
	is_protected     bool
	has_hyperlink    bool
	semantic_content SemanticContent
}

pub type CellData = C.WittyPageCell

fn C.witty_cell_content(&CellData) u32
fn C.witty_cell_set_content(&CellData, u32)

pub fn (self CellData) color_palette() u8 { return u8(C.witty_cell_content(&self)) }

pub fn (self CellData) color_rgb_r() u8 { return u8(C.witty_cell_content(&self)) }

pub fn (self CellData) color_rgb_g() u8 { return u8(C.witty_cell_content(&self) >> 8) }

pub fn (self CellData) color_rgb_b() u8 { return u8(C.witty_cell_content(&self) >> 16) }

// Initialize the active palette/RGB union member without overlapping V
// designated initializers overwriting a different packed union member.
pub fn CellData.from_color_payload(tag ContentTag, payload u32) CellData {
	assert tag in [.bg_color_palette, .bg_color_rgb]
	assert payload <= if tag == .bg_color_palette { u32(255) } else { u32(0xFFFFFF) }
	mut cell := CellData{ content_tag: tag }
	C.witty_cell_set_content(&cell, payload)
	return cell
}

// Helper to make a cell that just has a codepoint.
pub fn CellData.init(cp u32) CellData {
	return CellData{
		content_tag: .codepoint
		codepoint:   cp
	}
}

// Returns true if this cell represents all zeroes.
pub fn (self &CellData) is_zero() bool {
	return unsafe { *(&u64(self)) == 0 }
}

// Returns true if the cell has displayable text.
//
// Cases this returns false:
//   - Cell text is blank
//   - Cell is styled but only with a background color and no text
pub fn (self &CellData) has_text() bool {
	return match self.content_tag {
		.codepoint, .codepoint_grapheme { self.codepoint != 0 }
		.bg_color_palette, .bg_color_rgb { false }
	}
}

// Returns the codepoint for this cell, or 0 for bg-only cells.
pub fn (self &CellData) codepoint() u32 {
	return match self.content_tag {
		.codepoint, .codepoint_grapheme { self.codepoint }
		.bg_color_palette, .bg_color_rgb { 0 }
	}
}

// Returns true if this cell has multi-codepoint grapheme data.
pub fn (self &CellData) has_grapheme() bool {
	return self.content_tag == .codepoint_grapheme
}

// The width in grid cells that this cell takes up.
pub fn (self &CellData) grid_width() int {
	return match self.wide {
		.narrow, .spacer_head, .spacer_tail { 1 }
		.wide { 2 }
	}
}

// Returns true if the cell has a non-default style.
pub fn (self &CellData) has_styling() bool {
	return self.style_id != default_style_id
}

// Returns true if the cell has no text or styling.
pub fn (self &CellData) is_empty() bool {
	return match self.content_tag {
		// Textual cells are empty if they have no text and are narrow.
		// The "narrow" requirement is because wide spacers are meaningful.
		.codepoint, .codepoint_grapheme {
			!self.has_text() && self.wide == .narrow
		}
		.bg_color_palette, .bg_color_rgb {
			false
		}
	}
}

// Returns true if the set of cells has text in any cell.
pub fn has_text_any(cells []CellData) bool {
	for cell in cells {
		if cell.has_text() {
			return true
		}
	}
	return false
}

// ============================================================
// Row types
// ============================================================

// SemanticPromptType tracks what kind of semantic prompt a row has.
pub enum SemanticPromptType as u8 {
	unknown             = 0
	prompt              = 1
	prompt_continuation = 2
}

// RowData is the data for a single row in the terminal grid.
pub struct C.WittyPageRow {
pub mut:
	cells_offset              u32
	wrap                      bool
	wrap_continuation         bool
	grapheme                  bool
	styled                    bool
	hyperlink                 bool
	semantic_prompt           SemanticPromptType
	kitty_virtual_placeholder bool
	dirty                     bool
}

pub type PageRowHeader = C.WittyPageRow

// A transient view. Authoritative row flags and offsets live in packed page
// memory; cells borrows the block addressed by that row's offset.
pub struct RowData {
pub mut:
	header &PageRowHeader = &PageRowHeader{}
	cells  []CellData
}

// Initialize a new row with the given number of columns.
pub fn RowData.init(cols u32) RowData {
	return RowData{
		cells: []CellData{len: int(cols)}
	}
}

// Returns true if this row has any managed memory outside of the
// row structure (graphemes, styles, hyperlinks).
pub fn (self &RowData) managed_memory() bool {
	// Ordered on purpose for likelihood.
	return self.header.styled || self.header.hyperlink || self.header.grapheme
}

pub fn (self &RowData) snapshot() RowData {
	return RowData{ header: &PageRowHeader{ ...*self.header }, cells: self.cells }
}

// ============================================================
// Style types
// ============================================================

// UnderlineStyle for cell underline decoration.
pub enum UnderlineStyle as u8 {
	none   = 0
	single = 1
	double = 2
	curly  = 3
	dotted = 4
	dashed = 5
}

// StyleFlags contains boolean style attributes.
pub struct StyleFlags {
mut:
	value u16
}

pub fn StyleFlags.init(bold bool, italic bool, faint bool, blink bool, inverse bool, invisible bool, strikethrough bool, overline bool, underline UnderlineStyle) StyleFlags {
	return StyleFlags{
		value: u16(bold) | (u16(italic) << 1) | (u16(faint) << 2) | (u16(blink) << 3) | (u16(inverse) << 4) | (u16(invisible) << 5) | (u16(strikethrough) << 6) | (u16(overline) << 7) | (u16(underline) << 8)
	}
}

pub fn (flags StyleFlags) bold() bool {
	return flags.value & 0x0001 != 0
}

pub fn (flags StyleFlags) italic() bool {
	return flags.value & 0x0002 != 0
}

pub fn (flags StyleFlags) faint() bool {
	return flags.value & 0x0004 != 0
}

pub fn (flags StyleFlags) blink() bool {
	return flags.value & 0x0008 != 0
}

pub fn (flags StyleFlags) inverse() bool {
	return flags.value & 0x0010 != 0
}

pub fn (flags StyleFlags) invisible() bool {
	return flags.value & 0x0020 != 0
}

pub fn (flags StyleFlags) strikethrough() bool {
	return flags.value & 0x0040 != 0
}

pub fn (flags StyleFlags) overline() bool {
	return flags.value & 0x0080 != 0
}

pub fn (flags StyleFlags) underline() UnderlineStyle {
	return unsafe { UnderlineStyle((flags.value >> 8) & 0x0007) }
}

pub fn (flags StyleFlags) int() u16 {
	return flags.value
}

fn (mut flags StyleFlags) set_bool(mask u16, enabled bool) {
	flags.value = if enabled { flags.value | mask } else { flags.value & ~mask }
}

pub fn (mut flags StyleFlags) set_bold(enabled bool) {
	flags.set_bool(0x0001, enabled)
}

pub fn (mut flags StyleFlags) set_italic(enabled bool) {
	flags.set_bool(0x0002, enabled)
}

pub fn (mut flags StyleFlags) set_faint(enabled bool) {
	flags.set_bool(0x0004, enabled)
}

pub fn (mut flags StyleFlags) set_blink(enabled bool) {
	flags.set_bool(0x0008, enabled)
}

pub fn (mut flags StyleFlags) set_inverse(enabled bool) {
	flags.set_bool(0x0010, enabled)
}

pub fn (mut flags StyleFlags) set_invisible(enabled bool) {
	flags.set_bool(0x0020, enabled)
}

pub fn (mut flags StyleFlags) set_strikethrough(enabled bool) {
	flags.set_bool(0x0040, enabled)
}

pub fn (mut flags StyleFlags) set_overline(enabled bool) {
	flags.set_bool(0x0080, enabled)
}

pub fn (mut flags StyleFlags) set_underline(underline UnderlineStyle) {
	flags.value = (flags.value & ~u16(0x0700)) | (u16(underline) << 8)
}

// ColorType describes what type of color is set.
pub enum ColorType as u8 {
	none
	palette
	rgb
}

pub struct StyleColorNone {}

pub struct StyleColorPalette {
pub:
	index u8
}

pub struct StyleColorRgb {
pub:
	rgb RGB
}

pub type StyleColor = StyleColorNone | StyleColorPalette | StyleColorRgb

// CellStyle holds the complete style for a cell.
pub struct CellStyle {
pub mut:
	flags           StyleFlags
	fg_color        StyleColor = StyleColorNone{}
	bg_color        StyleColor = StyleColorNone{}
	underline_color StyleColor = StyleColorNone{}
}

// Returns true if this is the default (empty) style.
pub fn (self &CellStyle) default() bool {
	return self.flags.int() == 0 && self.fg_color is StyleColorNone
		&& self.bg_color is StyleColorNone && self.underline_color is StyleColorNone
}

// Returns a blank cell with the background color of this style.
//
// If no background color is set this returns none. Otherwise it returns a
// cell tagged as background-only content, so no style-map lookup is needed.
pub fn (self &CellStyle) bg_cell() ?CellData {
	return match self.bg_color {
		StyleColorNone { none }
		StyleColorPalette {
			CellData.from_color_payload(.bg_color_palette, u32(self.bg_color.index))
		}
		StyleColorRgb {
			CellData.from_color_payload(.bg_color_rgb, u32(self.bg_color.rgb.r) | (u32(self.bg_color.rgb.g) << 8) | (u32(self.bg_color.rgb.b) << 16))
		}
	}
}

// Hyperlink is defined in hyperlink.v.

// ============================================================
// KeyFlagStack (Kitty keyboard protocol)
// ============================================================

// KeyFlags is the packed five-bit value used by the Kitty keyboard protocol.
// V's narrowest integer backing is one byte.
pub struct KeyFlags {
mut:
	value u8
}

pub const key_flags_disabled = KeyFlags{}
pub const key_flags_all = KeyFlags{ value: 0b1_1111 }

pub fn KeyFlags.init(disambiguate bool, report_events bool, report_alternates bool, report_all bool, report_associated bool) KeyFlags {
	return KeyFlags{
		value: u8(disambiguate) | (u8(report_events) << 1) | (u8(report_alternates) << 2) | (u8(report_all) << 3) | (u8(report_associated) << 4)
	}
}

pub fn KeyFlags.from_int(value u8) KeyFlags {
	return KeyFlags{
		value: value & 0b1_1111
	}
}

pub fn (self KeyFlags) disambiguate() bool {
	return self.value & 0b0_0001 != 0
}

pub fn (self KeyFlags) report_events() bool {
	return self.value & 0b0_0010 != 0
}

pub fn (self KeyFlags) report_alternates() bool {
	return self.value & 0b0_0100 != 0
}

pub fn (self KeyFlags) report_all() bool {
	return self.value & 0b0_1000 != 0
}

pub fn (self KeyFlags) report_associated() bool {
	return self.value & 0b1_0000 != 0
}

pub fn (self KeyFlags) int() u8 {
	return self.value
}

pub struct KeyFlagStack {
pub mut:
	flags [8]KeyFlags
	idx   u8
}

// Push a new set of flags onto the stack.
pub fn (mut self KeyFlagStack) push(new_flags KeyFlags) {
	// Overflow and wrap around if we're full, which evicts
	// the oldest entry.
	self.idx = (self.idx + 1) % 8
	self.flags[self.idx] = new_flags
}

// Pop `n` entries from the stack. This will just wrap around
// if `n` is greater than the amount in the stack.
pub fn (mut self KeyFlagStack) pop(n uint) {
	// If n is more than our length then we just reset the stack.
	// This also avoids a DoS vector where a malicious client
	// could send a huge number of pop commands to waste cpu.
	if n >= 8 {
		self.idx = 0
		self.flags = [8]KeyFlags{init: key_flags_disabled}
		return
	}

	for _ in 0 .. n {
		self.flags[self.idx] = key_flags_disabled
		self.idx = if self.idx == 0 { u8(7) } else { self.idx - 1 }
	}
}

// Get the current (top) flags value.
pub fn (self KeyFlagStack) current() KeyFlags {
	return self.flags[self.idx]
}

// Set flags using a merge operation.
pub enum KeyFlagSetOp as u8 {
	set_
	or_
	not_
}

pub fn (mut self KeyFlagStack) set(op KeyFlagSetOp, new_flags KeyFlags) {
	match op {
		.set_ {
			self.flags[self.idx] = new_flags
		}
		.or_ {
			self.flags[self.idx] = KeyFlags.from_int(self.flags[self.idx].int() | new_flags.int())
		}
		.not_ {
			self.flags[self.idx] = KeyFlags.from_int(self.flags[self.idx].int() & ~new_flags.int())
		}
	}
}

// ============================================================
// PromptKind - for semantic prompt operations
// ============================================================

pub enum PromptKind as u8 {
	initial
	right
	continuation
	secondary
}
