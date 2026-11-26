module cimgui

// Key mirrors the named keyboard range in Dear ImGui 1.92.5. The explicit
// first value and declaration order are the ABI: ImGuiKey_Tab is 512 and the
// remaining values are consecutive.
pub enum Key as int {
	none = 0
	tab  = 512
	left_arrow
	right_arrow
	up_arrow
	down_arrow
	page_up
	page_down
	home
	end
	insert
	delete
	backspace
	space
	enter
	escape
	left_ctrl
	left_shift
	left_alt
	left_super
	right_ctrl
	right_shift
	right_alt
	right_super
	menu
	key_0
	key_1
	key_2
	key_3
	key_4
	key_5
	key_6
	key_7
	key_8
	key_9
	key_a
	key_b
	key_c
	key_d
	key_e
	key_f
	key_g
	key_h
	key_i
	key_j
	key_k
	key_l
	key_m
	key_n
	key_o
	key_p
	key_q
	key_r
	key_s
	key_t
	key_u
	key_v
	key_w
	key_x
	key_y
	key_z
	f1
	f2
	f3
	f4
	f5
	f6
	f7
	f8
	f9
	f10
	f11
	f12
	f13
	f14
	f15
	f16
	f17
	f18
	f19
	f20
	f21
	f22
	f23
	f24
	apostrophe
	comma
	minus
	period
	slash
	semicolon
	equal
	left_bracket
	backslash
	right_bracket
	grave_accent
	caps_lock
	scroll_lock
	num_lock
	print_screen
	pause
	keypad_0
	keypad_1
	keypad_2
	keypad_3
	keypad_4
	keypad_5
	keypad_6
	keypad_7
	keypad_8
	keypad_9
	keypad_decimal
	keypad_divide
	keypad_multiply
	keypad_subtract
	keypad_add
	keypad_enter
	keypad_equal
}

pub enum MouseButton as int {
	left
	right
	middle
}

// BackendPlatform identifies the host runtime that owns an ImGui context.
pub enum BackendPlatform {
	embedded
	ui2
}

// Color is Dear ImGui's normalized RGBA color representation.
pub struct Color {
pub:
	r f32
	g f32
	b f32
	a f32 = 1.0
}

// These flag values are part of the pinned Dear ImGui 1.92.5 ABI. They are
// named for the exact combinations used by Ghostty's key-stream inspector.
pub const table_flags_key_stream = (1 << 0) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 10) | (1 << 13) | (1 << 25)
pub const table_column_width_stretch = 1 << 3
pub const table_column_width_fixed = 1 << 4
pub const table_column_no_resize = 1 << 5
pub const table_column_prefer_sort_ascending = 1 << 14
pub const table_flags_borders_row_bg = (1 << 6) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 10)
pub const table_flags_borders_row_bg_sizing_fixed_fit = (1 << 6) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 10) | (1 << 13)
pub const table_flags_row_bg_sizing_fixed_fit = (1 << 6) | (1 << 13)
pub const table_flags_inner_v_row_bg_sizing_fixed_fit = (1 << 6) | (1 << 9) | (1 << 13)
pub const tree_node_flags_page_header = (1 << 2) | (1 << 10) | (1 << 12)
pub const color_edit_flags_none = 0
pub const color_edit_flags_no_inputs = 1 << 5
pub const color_edit_flags_style = (1 << 2) | (1 << 7) | (1 << 22)

// Context owns one Dear ImGui context. Ghostty creates one context per
// terminal inspector and always makes it current before touching its state.
pub struct Context {
pub:
	handle voidptr
}
