module terminal

// color_test.v - Tests for color types.
//
// Translated from the tests in Ghostty's terminal/color.zig.

// Helper to compare two [256]RGB palettes element-by-element,
// since V's `==` on large fixed arrays of structs is unreliable.
fn palettes_equal(a [256]RGB, b [256]RGB) bool {
	for i in 0 .. 256 {
		if !a[i].eql(b[i]) {
			return false
		}
	}
	return true
}

fn color_name_from_u8(value u8) Name {
	return unsafe { Name(value) }
}

// ============================================================
// Palette: default
// ============================================================

fn test_palette_default() {
	// Safety check: first 16 entries should match named color defaults.
	for i in 0 .. 16 {
		expected := unsafe { Name(u8(i)) }.default() or {
			assert false, 'expected default for index ${i}'
			return
		}
		assert default_palette[i].r == expected.r
			&& default_palette[i].g == expected.g
			&& default_palette[i].b == expected.b
	}
}

fn test_color_name_unnamed_has_no_default() {
	if _ := color_name_from_u8(16).default() {
		assert false, 'unnamed color unexpectedly had a default'
	}
	if _ := color_name_from_u8(255).default() {
		assert false, 'unnamed color unexpectedly had a default'
	}
}

// ============================================================
// RGB.parse
// ============================================================

fn test_rgb_cval() {
	assert sizeof(RGB) == 4
	assert sizeof(RGBC) == 3
	value := RGB{ r: 0xaa, g: 0xbb, b: 0xcc }.cval()
	assert value == RGBC{
		r: 0xaa
		g: 0xbb
		b: 0xcc
	}
}

fn test_rgb_parse_rgbi() {
	c := RGB.parse('rgbi:1.0/0/0') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 0 && c.b == 0
	assert RGB.parse('rgbi:0x1p0/0_0.0/0')? == RGB{255, 0, 0}
	assert RGB.parse('rgbi: 1/0/0') == none
}

fn test_rgb_parse_hex_channels_use_zig_unsigned_grammar() {
	// Zig ignores repeated interior underscores. Channel width still uses the
	// original four-byte spelling, so 0xff is scaled as a 16-bit channel.
	c := RGB.parse('rgb:f__f/0/0') or { panic('expected color') }
	assert c == RGB{0, 0, 0}
	assert RGB.parse('rgb:_ff/0/0') == none
	assert RGB.parse('rgb:ff_/0/0') == none
}

fn test_rgb_parse_rgb_mixed_lengths() {
	c := RGB.parse('rgb:7f/a0a0/0') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 127 && c.g == 160 && c.b == 0
}

fn test_rgb_parse_rgb_various_lengths() {
	c := RGB.parse('rgb:f/ff/fff') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 255 && c.b == 255
}

fn test_rgb_parse_hash6() {
	c := RGB.parse('#ffffff') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 255 && c.b == 255
}

fn test_rgb_parse_hash3() {
	c := RGB.parse('#fff') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 255 && c.b == 255
}

fn test_rgb_parse_hash9() {
	c := RGB.parse('#fffffffff') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 255 && c.b == 255
}

fn test_rgb_parse_hash12() {
	c := RGB.parse('#ffffffffffff') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 255 && c.b == 255
}

fn test_rgb_parse_hash6_specific() {
	c := RGB.parse('#ff0010') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 0 && c.b == 16
}

fn test_rgb_parse_x11_black() {
	c := RGB.parse('black') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 0 && c.g == 0 && c.b == 0
}

fn test_rgb_parse_x11_red() {
	c := RGB.parse('red') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 0 && c.b == 0
}

fn test_rgb_parse_x11_green() {
	c := RGB.parse('green') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 0 && c.g == 255 && c.b == 0
}

fn test_rgb_parse_x11_blue() {
	c := RGB.parse('blue') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 0 && c.g == 0 && c.b == 255
}

fn test_rgb_parse_x11_white() {
	c := RGB.parse('white') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 255 && c.g == 255 && c.b == 255
}

fn test_rgb_parse_x11_lawngreen() {
	c := RGB.parse('LawnGreen') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 124 && c.g == 252 && c.b == 0
}

fn test_rgb_parse_x11_medium_spring_green() {
	c := RGB.parse('medium spring green') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 0 && c.g == 250 && c.b == 154
}

fn test_rgb_parse_x11_forest_green_with_spaces() {
	c := RGB.parse(' Forest Green ') or {
		assert false, 'expected valid parse'
		return
	}
	assert c.r == 34 && c.g == 139 && c.b == 34
}

fn test_rgb_parse_x11_trims_only_spaces() {
	assert RGB.parse('\tForest Green\t') == none
	assert RGB.parse('\nForest Green\n') == none
}

fn test_rgb_parse_invalid_format() {
	// Invalid format tests
	assert RGB.parse('rgb;') == none
	assert RGB.parse('rgb:') == none
	assert RGB.parse(':a/a/a') == none
	assert RGB.parse('a/a/a') == none
	assert RGB.parse('rgb:a/a/a/') == none
	assert RGB.parse('rgb:00000///') == none
	assert RGB.parse('rgb:000/') == none
	assert RGB.parse('rgbi:a/a/a') == none
	assert RGB.parse('rgb:0.5/0.0/1.0') == none
	assert RGB.parse('rgb:not/hex/zz') == none
	assert RGB.parse('#') == none
	assert RGB.parse('#ff') == none
	assert RGB.parse('#ffff') == none
	assert RGB.parse('#fffff') == none
	assert RGB.parse('#gggggg') == none
}

// ============================================================
// Special.osc4
// ============================================================

fn test_special_osc4() {
	assert Special.bold.osc4() == 256
	assert Special.underline.osc4() == 257
	assert Special.blink.osc4() == 258
	assert Special.reverse.osc4() == 259
	assert Special.italic.osc4() == 260
}

// ============================================================
// Dynamic.next
// ============================================================

fn test_dynamic_next() {
	assert Dynamic.foreground.next() or { return } == .background
	assert Dynamic.background.next() or { return } == .cursor
	assert Dynamic.cursor.next() or { return } == .pointer_foreground
	assert Dynamic.pointer_foreground.next() or { return } == .pointer_background
	assert Dynamic.pointer_background.next() or { return } == .tektronix_foreground
	assert Dynamic.tektronix_foreground.next() or { return } == .tektronix_background
	assert Dynamic.tektronix_background.next() or { return } == .highlight_background
	assert Dynamic.highlight_background.next() or { return } == .tektronix_cursor
	assert Dynamic.tektronix_cursor.next() or { return } == .highlight_foreground
	assert Dynamic.highlight_foreground.next() == none
}

// ============================================================
// DynamicPalette tests
// ============================================================

fn test_dynamic_palette_init() {
	p := DynamicPalette.init(default_palette)
	assert palettes_equal(p.current, default_palette)
	assert palettes_equal(p.original, default_palette)
	assert p.mask_count() == 0
}

fn test_dynamic_palette_set() {
	mut p := DynamicPalette.init(default_palette)
	new_color := RGB{ r: 255, g: 0, b: 0 }

	p.set(0, new_color)
	assert p.current[0].eql(new_color)
	assert p.mask_is_set(0)
	assert p.mask_count() == 1

	// Original should be unchanged
	assert p.original[0].eql(default_palette[0])
}

fn test_dynamic_palette_reset() {
	mut p := DynamicPalette.init(default_palette)
	new_color := RGB{ r: 255, g: 0, b: 0 }

	p.set(0, new_color)
	assert p.mask_is_set(0)

	p.reset(0)
	assert p.current[0].eql(default_palette[0])
	assert !p.mask_is_set(0)
	assert p.mask_count() == 0
}

fn test_dynamic_palette_reset_all() {
	mut p := DynamicPalette.init(default_palette)
	new_color := RGB{ r: 255, g: 0, b: 0 }

	p.set(0, new_color)
	p.set(5, new_color)
	p.set(10, new_color)
	assert p.mask_count() == 3

	p.reset_all()
	assert palettes_equal(p.current, default_palette)
	assert palettes_equal(p.original, default_palette)
	assert p.mask_count() == 0
}

fn test_dynamic_palette_change_default_no_changes() {
	mut p := DynamicPalette.init(default_palette)
	mut new_palette := default_palette
	new_palette[0] = RGB{ r: 100, g: 100, b: 100 }

	p.change_default(new_palette)
	assert palettes_equal(p.original, new_palette)
	assert palettes_equal(p.current, new_palette)
	assert p.mask_count() == 0
}

fn test_dynamic_palette_change_default_preserves_changes() {
	mut p := DynamicPalette.init(default_palette)
	custom_color := RGB{ r: 255, g: 0, b: 0 }

	p.set(5, custom_color)
	assert p.mask_is_set(5)

	mut new_palette := default_palette
	new_palette[0] = RGB{ r: 100, g: 100, b: 100 }
	new_palette[5] = RGB{ r: 50, g: 50, b: 50 }

	p.change_default(new_palette)

	assert palettes_equal(p.original, new_palette)
	// Index 0 should use the new default (wasn't changed by user)
	assert p.current[0].eql(new_palette[0])
	// Index 5 should keep the custom color (was changed by user)
	assert p.current[5].eql(custom_color)
	assert p.mask_is_set(5)
	assert p.mask_count() == 1
}

fn test_dynamic_palette_change_default_multiple_changes() {
	mut p := DynamicPalette.init(default_palette)
	red := RGB{ r: 255, g: 0, b: 0 }
	green := RGB{ r: 0, g: 255, b: 0 }
	blue := RGB{ r: 0, g: 0, b: 255 }

	p.set(1, red)
	p.set(2, green)
	p.set(3, blue)

	mut new_palette := default_palette
	new_palette[0] = RGB{ r: 50, g: 50, b: 50 }
	new_palette[1] = RGB{ r: 60, g: 60, b: 60 }

	p.change_default(new_palette)

	// Index 0 should use the new default
	assert p.current[0].eql(new_palette[0])
	// Indices 1-3 should keep the custom colors
	assert p.current[1].eql(red)
	assert p.current[2].eql(green)
	assert p.current[3].eql(blue)
	assert p.mask_count() == 3
}

fn test_dynamic_rgb_reset_follows_default_changes() {
	initial := RGB{ r: 22, g: 24, b: 32 }
	configured := RGB{ r: 28, g: 42, b: 46 }
	custom := RGB{ r: 56, g: 32, b: 49 }
	mut color := DynamicRGB.init(initial)
	color.set(custom)
	assert color.get() == ?RGB(custom)

	color.reset()
	assert color.get() == ?RGB(initial)
	color.default_color = configured
	assert color.get() == ?RGB(configured)
	color.default_color = none
	assert color.get() == none
}
