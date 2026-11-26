module renderer

import terminal

// Returns true if the row of this pin should never have its background
// color extended for filling padding space in the renderer. This is
// a set of heuristics that help making our padding look better.
fn never_extend_bg(row &terminal.RenderRow, palette [256]terminal.RGB, default_background terminal.RGB) bool {
	// Any semantic prompts should not have their background extended
	// because prompts often contain special formatting (such as
	// powerline) that looks bad when extended.
	match row.raw.header.semantic_prompt {
		.prompt, .prompt_continuation { return true }
		else {}
	}

	for rendered in row.cells {
		cell := &rendered.raw
		// For codepoint cells we also never extend bg if any cell has a
		// powerline glyph because these are perfect-fit.
		if cell.content_tag == .codepoint || cell.content_tag == .codepoint_grapheme {
			cp := cell.codepoint
			if (cp >= 0xE0B0 && cp <= 0xE0C8) || cp == 0xE0CA
				|| (cp >= 0xE0CC && cp <= 0xE0D2) || cp == 0xE0D4 {
				return true
			}
		}

		// If any cell has a default background color then we don't extend
		// because the default background probably looks good enough as an
		// extension. Resolve the cell's background (mirrors ghostty
		// Style.bg): bg-color cells carry the color on the cell, otherwise
		// it comes from the style; a nil result means the default bg.
		style := if cell.has_styling() { rendered.style } else { default_cell_style }
		bg := style.bg(cell, palette) or { return true }
		if bg.r == default_background.r && bg.g == default_background.g
			&& bg.b == default_background.b {
			return true
		}
	}

	return false
}
