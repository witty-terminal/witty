module renderer

import font
import terminal
import configpkg
import datastruct
import macos
import os
import sync
import wuffs.png as wuffs_png

struct SurfaceEventCapture {
mut:
	health_events      []Health
	health_timeouts    []datastruct.BlockingQueueTimeoutKind
	scrollbar_events   []terminal.Scrollbar
	scrollbar_timeouts []datastruct.BlockingQueueTimeoutKind
}

fn capture_surface_event(data voidptr, event SurfaceEvent, timeout datastruct.BlockingQueueTimeout) u32 {
	mut capture := unsafe { &SurfaceEventCapture(data) }
	match event {
		RendererHealthEvent {
			capture.health_events << event.health
			capture.health_timeouts << timeout.kind()
		}
		ScrollbarEvent {
			capture.scrollbar_events << event.scrollbar
			capture.scrollbar_timeouts << timeout.kind()
		}
	}

	return u32(capture.health_events.len + capture.scrollbar_events.len)
}

// ============================================================
// Renderer tests
// ============================================================

// Test creating a DerivedConfig with defaults.
fn test_derived_config_defaults() {
	config := DerivedConfig{}
	assert config.background_opacity == 1.0
	assert config.cursor_opacity == 1.0
	assert config.min_contrast == 0.0
	assert config.vsync == true
	assert config.faint_opacity == 128
}

fn test_background_opacity_alpha_rounds_like_source() {
	assert background_opacity_alpha(0.0) == 0
	assert background_opacity_alpha(0.5) == 128
	assert background_opacity_alpha(1.0) == 255
}

fn test_renderer_emits_health_transitions_and_dirty_scrollbar() {
	mut capture := SurfaceEventCapture{}
	mailbox := SurfaceMailbox{
		user_data: voidptr(&capture)
		push_fn:   capture_surface_event
	}
	mut render := Renderer{
		surface_mailbox: mailbox
		scrollbar:       terminal.Scrollbar{
			total:  20
			offset: 3
			len:    5
		}
		scrollbar_dirty: true
	}
	render.frame_completed(.unhealthy)
	render.frame_completed(.unhealthy)
	render.frame_completed(.healthy)
	assert capture.health_events == [.unhealthy, .healthy]
	assert capture.health_timeouts == [.forever, .forever]

	// Metal's offscreen API reports zero size without a view. OpenGL queries
	// GL_VIEWPORT and needs a configured runtime context for a draw attempt.
	$if renderer_metal ? || ((macos || ios) && !renderer_opengl ?) {
	// A zero-sized renderer exits before GPU work, but the source renderer's
	// deferred scrollbar delivery still runs for that draw attempt.
	render.draw_frame(false)!
	assert capture.scrollbar_events.len == 1
	assert capture.scrollbar_events[0].eql(render.scrollbar)
	assert capture.scrollbar_timeouts == [.instant]
	assert !render.scrollbar_dirty
	}
}

fn test_frame_completion_always_releases_swap_chain_slot() {
	mut render := Renderer{
		frame_sema: sync.new_semaphore_init(0)
		health:     .healthy
	}

	// An unchanged health value still completes a frame and must return its
	// swap-chain permit. This wait would block forever if the early return from
	// the old translation were reintroduced.
	render.frame_completed(.healthy)
	render.frame_sema.wait()
	render.frame_sema.destroy()
	render.frame_sema = unsafe { nil }
}

fn test_swap_chain_slot_can_be_acquired_again_after_release() ! {
	mut render := Renderer{
		frame_sema: sync.new_semaphore_init(1)
	}
	defer {
		render.frame_sema.destroy()
		render.frame_sema = unsafe { nil }
	}

	render.acquire_frame()!
	render.release_frame()
	render.acquire_frame()!
	render.release_frame()
}

fn test_renderer_focus_transition_updates_source_state() ! {
	mut render := Renderer{
		focused: true
	}
	render.set_focus(false)!
	assert !render.focused
	assert render.custom_shader_focused_changed

	render.custom_shader_focused_changed = false
	render.set_focus(true)!
	assert render.focused
	assert render.custom_shader_focused_changed
}

fn test_update_frame_marks_search_viewport_dirty() ! {
	mut term := terminal.Terminal.init(terminal.Options{ cols: 2, rows: 2 })!
	defer { term.deinit() }
	term.modes.set(.cursor_visible, false)
	state := RenderState{
		mutex:     sync.new_mutex()
		terminal_: &term
	}
	defer { state.mutex.destroy() }
	mut render := Renderer{
		images: ImageRenderState.empty()
	}
	assert !term.flags.search_viewport_dirty()
	render.update_frame(&state, true)!
	assert term.flags.search_viewport_dirty()
}

// Test DerivedConfig init and deinit.
fn test_derived_config_deinit() {
	mut config := DerivedConfig{
		font_features:  ['liga', 'calt']
		custom_shaders: configpkg.RepeatablePath{
			items: [configpkg.Path(configpkg.PathRequired{ path: '/tmp/shader.glsl' })]
		}
		bg_image:       configpkg.PathRequired{
			path: '/tmp/background.png'
		}
	}
	config.deinit()
	assert config.font_features.len == 0
	assert config.custom_shaders.items.len == 0
	assert config.bg_image == none
}

fn test_prep_background_image_detects_magic_without_extension() ! {
	path := os.join_path(os.dir(@FILE), '..', 'terminal', 'kitty_testdata',
		'image-png-none-50x76-2147483647-raw.data')
	mut render := Renderer{
		config: DerivedConfig{
			bg_image: configpkg.PathRequired{
				path: path
			}
		}
	}
	render.prep_background_image()!
	mut image := render.bg_image or { return error('background image was not prepared') }
	assert image is ImagePending
	pending := image.get_pending() or { return error('background image has no pending pixels') }
	assert pending.width == 50
	assert pending.height == 76
	assert pending.data.len == 50 * 76 * 4
	image.deinit()
}

fn test_derived_config_owns_shader_path_list() {
	mut cfg := configpkg.Config.default_config()
	cfg.custom_shader.items << configpkg.PathRequired{
		path: '/tmp/first.glsl'
	}
	mut derived := DerivedConfig.init(&cfg)!
	cfg.custom_shader.items[0] = configpkg.PathRequired{
		path: '/tmp/changed.glsl'
	}
	cfg.custom_shader.items << configpkg.PathRequired{
		path: '/tmp/second.glsl'
	}
	assert derived.custom_shaders.items.len == 1
	assert derived.custom_shaders.items[0] is configpkg.PathRequired
	assert (derived.custom_shaders.items[0] as configpkg.PathRequired).path == '/tmp/first.glsl'
	derived.deinit()
}

fn test_derived_config_compiles_default_links() {
	cfg := configpkg.Config.default_config()
	mut derived := DerivedConfig.init(&cfg)!
	assert derived.links.links.len == 1
	derived.deinit()
	assert derived.links.links.len == 0
}

fn test_derived_config_preserves_explicit_bold_color() {
	mut cfg := configpkg.Config.default_config()
	cfg.load_string('bold-color = #123456\n')
	mut derived := DerivedConfig.init(&cfg)!
	bold := derived.bold_color or { panic('missing bold color') }
	assert bold is terminal.BoldColorColor
	assert (bold as terminal.BoldColorColor).color == terminal.RGB{
		r: 0x12
		g: 0x34
		b: 0x56
	}
	derived.deinit()
}

fn test_terminal_color_resolves_explicit_and_cell_colors() {
	fg := terminal.RGB{
		r: 10
		g: 20
		b: 30
	}
	bg := terminal.RGB{
		r: 40
		g: 50
		b: 60
	}
	explicit := configpkg.TerminalColorColor{
		color: configpkg.ColorRGB{
			r: 1
			g: 2
			b: 3
		}
	}
	assert resolve_terminal_color(explicit, false, fg, bg) == terminal.RGB{
		r: 1
		g: 2
		b: 3
	}
	assert resolve_terminal_color(configpkg.TerminalColorCellForeground{}, false, fg, bg) == fg
	assert resolve_terminal_color(configpkg.TerminalColorCellForeground{}, true, fg, bg) == bg
	assert resolve_terminal_color(configpkg.TerminalColorCellBackground{}, false, fg, bg) == bg
	assert resolve_terminal_color(configpkg.TerminalColorCellBackground{}, true, fg, bg) == fg
}

fn inspector_features_callback(ptr voidptr) []OverlayFeature {
	assert !isnil(ptr)
	return [.semantic_prompts, .highlight_hyperlinks]
}

fn test_render_state_reads_features_from_opaque_inspector() {
	bridge := InspectorOverlayBridge{
		overlay_features_fn: inspector_features_callback
	}
	state := RenderState{
		inspector: voidptr(&bridge)
	}
	assert state.inspector_overlay_features() == [.semantic_prompts, .highlight_hyperlinks]
	assert RenderState{}.inspector_overlay_features().len == 0
}

fn test_renderer_rebuilds_reuses_and_removes_inspector_overlay() ! {
	mut render := Renderer{
		size:           Size{
			screen: ScreenSize{
				width:  40
				height: 10
			}
			cell:   CellSize{
				width:  10
				height: 10
			}
		}
		images:         ImageRenderState.empty()
		terminal_state: terminal.RenderState{
			row_data: [
				terminal.RenderRow{
					raw:   terminal.RowData{
						header: &terminal.PageRowHeader{ hyperlink: true }
					}
					cells: [
						terminal.RenderCell{},
						terminal.RenderCell{
							raw: terminal.CellData{
								has_hyperlink: true
							}
						},
						terminal.RenderCell{
							raw: terminal.CellData{
								has_hyperlink: true
							}
						},
						terminal.RenderCell{},
					]
				},
			]
		}
	}

	render.rebuild_overlay([.highlight_hyperlinks])!
	mut overlay := render.overlay or { return error('overlay was not created') }
	assert overlay.width() == 40
	assert overlay.height() == 10
	assert overlay.surface.pixels[5 * 40 + 15] >> 24 == 96
	pixels := overlay.surface.pixels.data

	render.rebuild_overlay([.highlight_hyperlinks])!
	overlay = render.overlay or { return error('overlay was not retained') }
	assert overlay.surface.pixels.data == pixels
	render.images.overlay_update(render.overlay)
	assert render.images.overlay_placements.len == 1

	render.rebuild_overlay([])!
	assert render.overlay == none
	render.images.overlay_update(render.overlay)
	assert render.images.overlay_placements.len == 0
	render.images.deinit()
}

fn test_renderer_set_macos_display_id_preserves_fallible_entry_point() {
	mut render := Renderer{}
	render.set_macos_display_id(1)!
}

// Test CellContents resize and reset.
fn test_cell_contents_resize() ! {
	mut cells := CellContents{}
	cells.resize(GridSize{ columns: 80, rows: 24 })!
	assert cells.size.columns == 80
	assert cells.size.rows == 24
	assert cells.bg_cells.len == 80 * 24
	assert cells.fg_rows.lists.len == 26
	assert cells.fg_rows.lists[0].len == 0
	assert cells.fg_rows.lists[0].cap >= 1
	assert cells.fg_rows.lists[1].cap >= 80 * 3
	assert cells.fg_rows.lists[25].len == 0
	assert cells.fg_rows.lists[25].cap >= 1
}

// Test CellContents reset clears everything.
fn test_cell_contents_reset() ! {
	mut cells := CellContents{}
	cells.resize(GridSize{ columns: 10, rows: 5 })!

	// Set some bg cell data
	mut bg_cell := unsafe { &CellBg(cells.bg_cell(0, 0)) }
	unsafe {
		*bg_cell = CellBg([u8(255), 0, 0, 255]!)
	}

	// Add a fg cell
	cells.add(.text, CellText{
		grid_pos:   [u16(0), u16(0)]!
		color:      [u8(255), 255, 255, 255]!
		glyph_size: [u32(10), u32(20)]!
	})!

	cells.reset()

	// Check bg is cleared
	assert cells.bg_cells[0] == CellBg([u8(0), 0, 0, 0]!)
	// Check fg is cleared
	assert cells.fg_rows.lists[1].len == 0
}

// Test CellContents clear for a specific row.
fn test_cell_contents_clear_row() ! {
	mut cells := CellContents{}
	cells.resize(GridSize{ columns: 10, rows: 5 })!

	// Add fg cells to rows 0 and 1
	cells.add(.text, CellText{
		grid_pos: [u16(0), u16(0)]!
		color:    [u8(255), 255, 255, 255]!
	})!
	cells.add(.text, CellText{
		grid_pos: [u16(0), u16(1)]!
		color:    [u8(255), 255, 255, 255]!
	})!

	// Clear row 0 only
	cells.clear(0)
	assert cells.fg_rows.lists[1].len == 0
	assert cells.fg_rows.lists[2].len == 1
}

// Test cursor set/get.
fn test_cell_contents_cursor() ! {
	mut cells := CellContents{}
	cells.resize(GridSize{ columns: 80, rows: 24 })!

	// No cursor by default
	assert cells.get_cursor_glyph() == none

	// Set a cursor
	cursor_cell := CellText{
		bools:    cell_text_bools(false, true)
		grid_pos: [u16(5), u16(10)]!
		color:    [u8(255), 255, 255, 255]!
	}
	cells.set_cursor(cursor_cell, .block)
	assert cells.fg_rows.lists[0] == [cursor_cell]
	assert cells.fg_rows.lists[25].len == 0

	got := cells.get_cursor_glyph() or {
		assert false, 'expected cursor'
		return
	}
	assert got.grid_pos[0] == 5
	assert got.grid_pos[1] == 10
	assert got.bools.is_cursor_glyph()

	// Non-block cursor styles are stored after all screen rows so the shared
	// flattened buffer naturally draws them last.
	cells.set_cursor(cursor_cell, .bar)
	assert cells.fg_rows.lists[0].len == 0
	assert cells.fg_rows.lists[25] == [cursor_cell]
	assert cells.get_cursor_glyph()? == cursor_cell

	cells.set_cursor(none, none)
	assert cells.fg_rows.lists[0].len == 0
	assert cells.fg_rows.lists[25].len == 0
	assert cells.get_cursor_glyph() == none
}

fn test_cell_contents_cursor_with_zero_sized_screen() ! {
	mut cells := CellContents{}
	cells.resize(GridSize{})!
	assert cells.fg_rows.lists.len == 2
	cells.set_cursor(CellText{ bools: cell_text_bools(false, true) }, .block)
	assert cells.fg_rows.lists[0].len == 0
	assert cells.fg_rows.lists[1].len == 0
	assert cells.get_cursor_glyph() == none
}

// Test Uniforms default values.
fn test_uniforms_defaults() {
	u := Uniforms{}
	assert u.min_contrast == 0.0
	assert u.bools.cursor_wide == false
}

// Test Size.terminal.
fn test_size_terminal() {
	s := Size{
		screen:  ScreenSize{
			width:  800
			height: 600
		}
		cell:    CellSize{
			width:  10
			height: 20
		}
		padding: Padding{
			top:    5
			bottom: 5
			left:   5
			right:  5
		}
	}
	ts := s.terminal()
	// The terminal area is the screen with padding removed. It is not rounded
	// down to a whole-cell multiple.
	assert ts.width == 790
	assert ts.height == 590
}

// Test ScreenSize.blank_padding.
fn test_screen_size_blank_padding() {
	s := Size{
		screen:  ScreenSize{
			width:  800
			height: 600
		}
		cell:    CellSize{
			width:  10
			height: 20
		}
		padding: Padding{
			top:    0
			bottom: 0
			left:   0
			right:  0
		}
	}
	grid := GridSize{
		columns: 80
		rows:    30
	}
	bp := s.screen.blank_padding(s.padding, grid, s.cell).add(s.padding)
	// Screen 800x600, grid 80*10=800, 30*20=600 => no extra padding
	assert bp.left == 0
	assert bp.right == 0
	assert bp.top == 0
	assert bp.bottom == 0
}

fn test_screen_size_blank_padding_is_trailing_and_includes_explicit_padding() {
	s := Size{
		screen:  ScreenSize{
			width:  108
			height: 112
		}
		cell:    CellSize{
			width:  10
			height: 20
		}
		padding: Padding{
			top:    2
			bottom: 3
			left:   1
			right:  2
		}
	}
	bp := s.screen.blank_padding(s.padding, GridSize{ columns: 10, rows: 5 }, s.cell).add(s.padding)
	assert bp.left == 1
	assert bp.top == 2
	assert bp.right == 7
	assert bp.bottom == 10
}

// Test Padding.add.
fn test_padding_add() {
	a := Padding{
		top:    5
		bottom: 5
		left:   10
		right:  10
	}
	b := Padding{
		top:    3
		bottom: 3
		left:   7
		right:  7
	}
	c := a.add(b)
	assert c.top == 8
	assert c.bottom == 8
	assert c.left == 17
	assert c.right == 17
}

// Test GridSize.
fn test_grid_size() {
	mut s := Size{
		screen:  ScreenSize{
			width:  800
			height: 600
		}
		cell:    CellSize{
			width:  10
			height: 20
		}
		padding: Padding{
			top:    0
			bottom: 0
			left:   0
			right:  0
		}
	}
	g := s.grid()
	assert g.columns == 80
	assert g.rows == 30
}

fn test_grid_size_equals() {
	a := GridSize{
		columns: 80
		rows:    24
	}
	assert a.equals(GridSize{ columns: 80, rows: 24 })
	assert !a.equals(GridSize{ columns: 81, rows: 24 })
}

// Test ScreenSize.equals.
fn test_screen_size_equals() {
	a := ScreenSize{
		width:  800
		height: 600
	}
	b := ScreenSize{
		width:  800
		height: 600
	}
	c := ScreenSize{
		width:  1024
		height: 768
	}
	assert a.equals(b)
	assert !a.equals(c)
}

// Test Health enum.
fn test_health_enum() {
	h := Health.healthy
	assert h == .healthy
	assert h != .unhealthy
	assert sizeof(Health) == sizeof(int)
	assert int(Health.healthy) == 0
	assert int(Health.unhealthy) == 1
}

// Test Style enum values.
fn test_cursor_style_enum() {
	assert Style.block != Style.bar
	assert Style.block_hollow != Style.underline
}

// Test BgImageBuffer defaults.
fn test_bg_image_buffer_defaults() {
	buf := BgImageBuffer{}
	assert sizeof(BgImageInfo) == 1
	assert sizeof(BgImageBuffer) == 8
	assert __offsetof(BgImageBuffer, opacity) == 0
	assert __offsetof(BgImageBuffer, info) == 4
	assert buf.opacity == 1.0
	assert buf.info.position() == .mc
	assert buf.info.fit() == .contain
	assert !buf.info.repeats()
	assert buf.info.packed() == 4
}

// Test CustomShaderUniforms defaults.
fn test_custom_shader_uniforms_defaults() {
	u := CustomShaderUniforms{}
	assert u.focus == 1
	assert u.frame_rate == 60.0
	assert u.time == 0.0
	assert sizeof(CustomShaderUniforms) == 4480
	assert __offsetof(CustomShaderUniforms, channel_time) == 32
	assert __offsetof(CustomShaderUniforms, palette) == 288
}

// Test HighlightTag enum.
fn test_highlight_tag() {
	t1 := HighlightTag.search_match
	t2 := HighlightTag.search_match_selected
	assert t1 != t2
	assert u8(t1) == 0
	assert u8(t2) == 1
}

// Test Preedit width calculation.
fn test_preedit_width() {
	p := Preedit{
		codepoints: [
			PreeditCodepoint{
				codepoint: 0x3042
				wide:      true
			}, // あ (wide)
			PreeditCodepoint{
				codepoint: 0x3044
				wide:      true
			}, // い (wide)
			PreeditCodepoint{
				codepoint: 0x61
				wide:      false
			}, // a (narrow)
		]
	}
	assert p.width() == 5 // 2 + 2 + 1
}

fn test_preedit_range_fits() {
	p := RenderPreedit{
		codepoints: [
			RenderPreeditCodepoint{
				codepoint: u32(`a`)
			},
			RenderPreeditCodepoint{
				codepoint: 0x3042
				wide:      true
			},
		]
	}
	start, end, cp_offset := p.range(2, 9)
	assert start == 2
	assert end == 4
	assert cp_offset == 0
}

fn test_preedit_range_one_cell_at_right_edge() {
	p := RenderPreedit{ codepoints: [RenderPreeditCodepoint{ codepoint: u32(`a`) }] }
	start, end, cp_offset := p.range(9, 9)
	assert start == 9
	assert end == 9
	assert cp_offset == 0
}

fn test_preedit_range_keeps_trailing_codepoints_when_clipped() {
	p := RenderPreedit{
		codepoints: [
			RenderPreeditCodepoint{
				codepoint: u32(`a`)
			},
			RenderPreeditCodepoint{
				codepoint: u32(`b`)
			},
			RenderPreeditCodepoint{
				codepoint: 0x3042
				wide:      true
			},
		]
	}
	start, end, cp_offset := p.range(8, 9)
	assert start == 7
	assert end == 9
	assert cp_offset == 1
}

// Test CellText initialization.
fn test_cell_text_init() {
	ct := CellText{
		atlas:      .grayscale
		bools:      cell_text_bools(true, false)
		grid_pos:   [u16(42), u16(7)]!
		color:      [u8(200), 100, 50, 255]!
		glyph_pos:  [u32(100), u32(200)]!
		glyph_size: [u32(8), u32(16)]!
		bearings:   [i16(1), i16(-2)]!
	}
	assert ct.atlas == .grayscale
	assert ct.bools.no_min_contrast()
	assert ct.grid_pos[0] == 42
	assert ct.grid_pos[1] == 7
	assert ct.color[0] == 200
	assert ct.glyph_size[0] == 8
	assert ct.bearings[1] == -2
}

// Test UniformBools initialization.
fn test_uniform_bools() {
	b := UniformBools{
		cursor_wide:    true
		use_display_p3: true
	}
	assert b.cursor_wide == true
	assert b.use_display_p3 == true
	assert b.use_linear_blending == false
}

// Test PaddingExtend.
fn test_padding_extend() {
	pe := PaddingExtend{
		up:    true
		down:  true
		left:  true
		right: true
	}
	assert pe.up == true
	assert pe.right == true
}

fn test_resize_refreshes_terminal_projection_and_padding() ! {
	mut render := Renderer{}
	render.cells.resize(GridSize{ columns: 8, rows: 4 })!
	render.set_screen_size(Size{
		screen: ScreenSize{ width: 90, height: 72 }
		cell:   CellSize{ width: 10, height: 16 }
		padding: Padding{ top: 2, right: 3, bottom: 4, left: 5 }
	})
	assert render.cells_rebuilt
	assert render.uniforms.screen_size == [f32(90), 72]!
	assert render.uniforms.grid_padding == [f32(2), 5, 6, 5]!
	assert render.uniforms.projection_matrix[0] == f32(2) / 90
	assert render.uniforms.projection_matrix[5] == -f32(2) / 72
}

// Test multiple fg cells per row.
fn test_multiple_fg_cells_per_row() ! {
	mut cells := CellContents{}
	cells.resize(GridSize{ columns: 80, rows: 24 })!

	// Add multiple cells to the same row
	for col in 0 .. 10 {
		cells.add(.text, CellText{
			grid_pos:   [u16(col), u16(0)]!
			color:      [u8(255), 255, 255, 255]!
			glyph_size: [u32(8), u32(16)]!
		})!
	}

	assert cells.fg_rows.lists[1].len == 10
	assert cells.fg_rows.lists[2].len == 0
}

// Test the source-shaped background-cell pointer accessor.
fn test_bg_cell_access() ! {
	assert sizeof(CellBg) == 4

	mut cells := CellContents{}
	cells.resize(GridSize{ columns: 10, rows: 5 })!

	// Set bg for cell at (3, 2)
	mut bg_cell := unsafe { &CellBg(cells.bg_cell(2, 3)) }
	unsafe {
		*bg_cell = CellBg([u8(100), 150, 200, 255]!)
	}

	// Read it back
	idx := 2 * 10 + 3
	assert cells.bg_cells[idx] == CellBg([u8(100), 150, 200, 255]!)

	assert cells.bg_cell(2, 3) == voidptr(&cells.bg_cells[idx])
}

// Test AtlasKind enum.
fn test_atlas_kind() {
	assert sizeof(AtlasKind) == 1
	assert u8(AtlasKind.grayscale) == 0
	assert u8(AtlasKind.color) == 1
}

// Test source cell content keys.
fn test_cell_key_source_layout_and_ordinals() {
	assert sizeof(CellKey) == 1
	assert u8(CellKey.bg) == 0
	assert u8(CellKey.text) == 1
	assert u8(CellKey.underline) == 2
	assert u8(CellKey.strikethrough) == 3
	assert u8(CellKey.overline) == 4
}

fn test_cell_selected_source_layout_and_ordinals() {
	assert sizeof(CellSelected) == 1
	assert u8(CellSelected.false_) == 0
	assert u8(CellSelected.selection) == 1
	assert u8(CellSelected.search) == 2
	assert u8(CellSelected.search_selected) == 3
}

// Test FontStyleStatus defaults.
fn test_font_style_status() {
	s := FontStyleStatus{}
	assert s.bold == true
	assert s.italic == true
	assert s.bold_italic == true
}

// Test balanced padding when the top cap has no effect.
fn test_balance_padding() {
	mut s := Size{
		screen:  ScreenSize{
			width:  810
			height: 610
		}
		cell:    CellSize{
			width:  10
			height: 20
		}
		padding: Padding{}
	}
	s.set_padding(Padding{}, .true_)
	// 810/10 = 81 cols, extra 0. 610/20 = 30 rows, extra 10. The
	// vertical shift caps top padding to half a cell width.
	assert s.padding.top == 5
	assert s.padding.bottom == 5
}

fn test_balance_padding_modes() {
	mut s := Size{
		screen:  ScreenSize{
			width:  805
			height: 639
		}
		cell:    CellSize{
			width:  10
			height: 20
		}
		padding: Padding{}
	}
	s.set_padding(Padding{}, .true_)
	assert s.padding.left == 2
	assert s.padding.right == 2
	assert s.padding.top == 5
	assert s.padding.bottom == 13

	s.set_padding(Padding{}, .equal)
	assert s.padding == Padding{ top: 9, bottom: 9, left: 2, right: 2 }

	explicit := Padding{ top: 3, bottom: 17, left: 12, right: 7 }
	s.set_padding(explicit, .false_)
	assert s.padding == explicit
}

// Verify the production row path shapes codepoints, rasterizes their glyphs,
// and emits foreground cells backed by the shared font atlases.
$if renderer_metal ? || ((macos || ios) && !renderer_opengl ?) {
fn test_rebuild_row_shapes_and_renders_text() ! {
	// The OpenGL renderer creates its frame buffers and shaders during init,
	// so it needs a current GL context, which only GtkGLArea supplies. Metal
	// needs no context, so this test runs on macOS only.
	$if !macos {
		return
	}
	mut library := font.Library.init()!
	defer { library.deinit() }

	mut collection := font.Collection.init()
	collection.load_options = font.LoadOptions{
		library: library
		size:    font.DesiredSize{
			points: 12
			xdpi:   96
			ydpi:   96
		}
	}
	load_opts := collection.load_options or { return error('missing font load options') }
	collection.add(font.Face.init_mem(library, font.embedded_regular, load_opts.face_options())!, font.AddOptions{
		style:           .regular
		fallback:        false
		size_adjustment: .none_
	})!

	mut grid := font.SharedGrid.init(font.CodepointResolver{
		collection: collection
	})!
	defer { grid.deinit() }

	mut render := Renderer.init(RendererOpts{
		font_grid: &grid
		config:    DerivedConfig{}
		size:      Size{
			screen: ScreenSize{
				width:  300
				height: 100
			}
			cell:   CellSize{
				width:  grid.metrics.cell_width
				height: grid.metrics.cell_height
			}
		}
	})!
	defer { render.deinit() }

	// The renderer loop owns CVDisplayLink lifecycle. Its callback only queues
	// draw-now work onto the renderer thread; it never renders on CoreVideo's
	// callback thread.
	mut render_thread := RendererThread{}
	render.loop_enter(&render_thread)!
	assert render.has_vsync()
	render.loop_exit()
	assert !render.has_vsync()
	render.cells.resize(GridSize{ columns: 3, rows: 1 })!

	row := terminal.RenderRow{
		cells: [
			terminal.RenderCell{
				raw: terminal.CellData.init(u32(`A`))
			},
			terminal.RenderCell{
				raw: terminal.CellData.init(u32(`B`))
			},
			terminal.RenderCell{
				raw: terminal.CellData.init(u32(`C`))
			},
		]
	}
	links := terminal.CellSet{}
	render.rebuild_row(0, &row, none, &links)!

	assert render.cells.fg_rows.lists[1].len == 3
	for cell in render.cells.fg_rows.lists[1] {
		assert cell.glyph_size[0] > 0
		assert cell.glyph_size[1] > 0
	}
	assert grid.glyphs.len == 3

	// Runs completely covered by preedit are not shaped or cached.
	cache_count := render.font_shaper_cache.count()
	preedit_row := terminal.RenderRow{
		cells: [
			terminal.RenderCell{ raw: terminal.CellData.init(u32(`D`)) },
			terminal.RenderCell{ raw: terminal.CellData.init(u32(`E`)) },
			terminal.RenderCell{ raw: terminal.CellData.init(u32(`F`)) },
		]
	}
	render.rebuild_row(0, &preedit_row, PreeditRange{ y: 0, x: [u16(0), 2]! }, &links)!
	assert render.font_shaper_cache.count() == cache_count
	assert grid.glyphs.len == 3

	// Leaving preedit in the middle of a run advances the shared cell position.
	render.rebuild_row(0, &preedit_row, PreeditRange{ y: 0, x: [u16(0), 0]! }, &links)!
	assert render.font_shaper_cache.count() == cache_count + 1
	assert grid.glyphs.len == 5

	// Exercise the complete off-screen Metal frame path with the exact cells
	// produced above. This compiles/binds all resources, draws the background
	// and glyph instances, commits the command buffer, and waits for the GPU.
	render.uniforms.grid_size = [u16(3), 1]!
	render.uniforms.bools.use_display_p3 = true
	render.uniforms.bg_color = [u8(30), 60, 90, 255]!
	render.update_screen_size_uniforms()
	render.cells_rebuilt = true
	render.draw_frame(true)!
	assert render.health == .healthy
	// Ghostty initializes the swap-chain index to zero and nextFrame advances
	// before returning, so the first Metal frame uses slot one.
	assert render.frame_index == 1
	assert render.frames[1].target.width == 300
	assert render.frames[1].target.height == 100
	mut background_pixel := []u8{len: 4}
	macos.metal_texture_get_bytes(render.frames[1].target.texture, mut background_pixel, 4,
		299, 99, 1, 1)
	assert background_pixel == [u8(90), 60, 30, 255]

	path := os.join_path(os.temp_dir(), 'witty-terminal-frame-${os.getpid()}.png')
	defer { os.rm(path) or {} }
	render.screenshot_png(path)!
	png := wuffs_png.decode(os.read_bytes(path)!)!
	assert png.width == 300
	assert png.height == 100
	channels := png.data.len / int(png.width * png.height)
	assert channels in [3, 4]
	last_pixel := png.data[png.data.len - channels..]
	assert last_pixel[..3] == [u8(30), 60, 90]

	// Keep the composing row intact when the renderer updates a clean frame.
	render.terminal_state.rows = 1
	render.terminal_state.cols = 3
	render.terminal_state.row_data = [preedit_row]
	render.terminal_state.cursor.viewport = terminal.ViewportPoint{ x: 1 }
	render.terminal_state.dirty = .full
	preedit := RenderPreedit{ codepoints: [RenderPreeditCodepoint{ codepoint: u32(`x`) }] }
	render.rebuild_cells(preedit, none, &links)!
	// Two surrounding glyphs, one composing glyph and its underline.
	assert render.cells.fg_rows.lists[1].len == 4
	bg := unsafe { *(&CellBg(render.cells.bg_cell(0, 1))) }
	assert bg == CellBg([u8(0), 0, 0, 0]!)

	render.terminal_state.dirty = .false_
	render.rebuild_cells(preedit, none, &links)!
	assert render.cells.fg_rows.lists[1].len == 4
}

}

fn test_background_color_alpha_uses_native_glass_material() {
	assert background_color_alpha(0.5, configpkg.BackgroundBlurFalse{}) == 128
	$if macos {
		assert background_color_alpha(0.5, configpkg.BackgroundBlurMacosGlassRegular{}) == 0
		assert background_color_alpha(0.5, configpkg.BackgroundBlurMacosGlassClear{}) == 0
	} $else {
		assert background_color_alpha(0.5, configpkg.BackgroundBlurMacosGlassRegular{}) == 128
		assert background_color_alpha(0.5, configpkg.BackgroundBlurMacosGlassClear{}) == 128
	}
}
