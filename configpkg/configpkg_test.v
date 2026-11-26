module configpkg

import os
import input
import terminal
import cli_args
import buildcfg
import font

fn test_finalize_auto_update_channel_uses_compiled_channel_and_preserves_override() {
	mut automatic := Config.default_config()
	assert automatic.auto_update_channel == none
	automatic.finalize()!
	assert automatic.auto_update_channel? == buildcfg.release_channel
	mut explicit := Config.default_config()
	explicit.auto_update_channel = if buildcfg.release_channel == .stable { .tip } else { .stable }
	expected := explicit.auto_update_channel?
	explicit.finalize()!
	assert explicit.auto_update_channel? == expected
}

fn assert_metric_modifier_absolute(modifier ?font.MetricsModifier, expected i32) {
	value := modifier or { panic('missing metrics modifier') }
	assert value is font.MetricsModifierAbsolute
	assert value.value == expected
}

fn assert_metric_modifier_percent(modifier ?font.MetricsModifier, expected f64) {
	value := modifier or { panic('missing metrics modifier') }
	assert value is font.MetricsModifierPercent
	assert value.value == expected
}

enum FormatterTestEnum {
	one
	two
	three
}

struct FormatterTestFlags {
	one bool = true
	two bool
}

fn test_platform_config_enum_layouts_and_source_ordinals() {
	assert sizeof(MacOSDockDropBehavior) == 1
	assert [MacOSDockDropBehavior.new_tab, .new_window].map(u8(it)) == [u8(0), 1]

	assert sizeof(NonNativeFullscreen) == 4
	assert [NonNativeFullscreen.false_, .true_, .visible_menu, .padded_notch].map(i32(it)) == [i32(0),
		1, 2, 3]

	assert sizeof(MacWindowButtons) == 1
	assert [MacWindowButtons.visible, .hidden].map(u8(it)) == [u8(0), 1]
	assert sizeof(MacTitlebarStyle) == 1
	assert [MacTitlebarStyle.native, .transparent, .tabs, .hidden].map(u8(it)) == [u8(0), 1,
		2, 3]
	assert sizeof(MacTitlebarProxyIcon) == 1
	assert [MacTitlebarProxyIcon.visible, .hidden].map(u8(it)) == [u8(0), 1]
	assert sizeof(MacHidden) == 1
	assert [MacHidden.never, .always].map(u8(it)) == [u8(0), 1]

	assert sizeof(MacAppIcon) == 1
	assert [MacAppIcon.official, .blueprint, .chalkboard, .microchip, .glass, .holographic,
		.paper, .retro, .xray, .custom, .custom_style].map(u8(it)) == [u8(0), 1, 2, 3, 4, 5,
		6, 7, 8, 9, 10]
	assert sizeof(MacAppIconFrame) == 1
	assert [MacAppIconFrame.aluminum, .beige, .plastic, .chrome].map(u8(it)) == [u8(0), 1,
		2, 3]
	assert sizeof(MacShortcuts) == 1
	assert [MacShortcuts.allow, .deny, .ask].map(u8(it)) == [u8(0), 1, 2]

	assert sizeof(LinuxCgroup) == 1
	assert [LinuxCgroup.never, .always, .single_instance].map(u8(it)) == [u8(0), 1, 2]
}

fn test_config_value_tag_layouts_and_source_ordinals() {
	assert sizeof(WindowPaddingColor) == 1
	assert [WindowPaddingColor.background, .extend, .extend_always].map(u8(it)) == [u8(0), 1,
		2]
	assert sizeof(WindowColorspace) == 1
	assert [WindowColorspace.srgb, .display_p3].map(u8(it)) == [u8(0), 1]
	assert sizeof(AlphaBlending) == 1
	assert [AlphaBlending.native, .linear, .linear_corrected].map(u8(it)) == [u8(0), 1, 2]

	assert sizeof(BackgroundImagePosition) == 1
	assert [BackgroundImagePosition.top_left, .top_center, .top_right, .center_left, .center_center,
		.center_right, .bottom_left, .bottom_center, .bottom_right, .center].map(u8(it)) == [u8(0),
		1, 2, 3, 4, 5, 6, 7, 8, 9]
	assert sizeof(BackgroundImageFit) == 1
	assert [BackgroundImageFit.contain, .cover, .stretch, .none_].map(u8(it)) == [u8(0), 1,
		2, 3]

	assert sizeof(FontStyleKind) == 1
	assert [FontStyleKind.default_, .false_, .name].map(u8(it)) == [u8(0), 1, 2]
}

fn test_general_config_enum_layouts_and_source_ordinals() {
	assert sizeof(ShellIntegration) == 1
	assert [ShellIntegration.none_, .detect, .bash, .elvish, .fish, .nushell, .zsh].map(u8(it)) == [u8(0),
		1, 2, 3, 4, 5, 6]
	assert sizeof(LinkPreviews) == 1
	assert [LinkPreviews.false_, .true_, .osc8].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(ClipboardAccess) == 1
	assert [ClipboardAccess.allow, .deny, .ask].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(CopyOnSelect) == 1
	assert [CopyOnSelect.false_, .true_, .clipboard].map(u8(it)) == [u8(0), 1, 2]

	assert sizeof(ConfirmCloseSurface) == 4
	assert [ConfirmCloseSurface.false_, .true_, .always].map(i32(it)) == [i32(0), 1, 2]
	assert sizeof(CustomShaderAnimation) == 4
	assert [CustomShaderAnimation.false_, .true_, .always].map(i32(it)) == [i32(0), 1, 2]
	assert sizeof(WindowDecoration) == 4
	assert [WindowDecoration.auto, .client, .server, .none_].map(i32(it)) == [i32(0), 1,
		2, 3]

	assert sizeof(MouseShiftCapture) == 1
	assert [MouseShiftCapture.false_, .true_, .always, .never].map(u8(it)) == [u8(0), 1, 2,
		3]
	assert sizeof(Theme) == 1
	assert [Theme.light, .dark].map(u8(it)) == [u8(0), 1]
	assert sizeof(ConditionalKey) == 1
	assert [ConditionalKey.theme, .os].map(u8(it)) == [u8(0), 1]
	assert sizeof(ConditionalOp) == 1
	assert [ConditionalOp.eq, .ne].map(u8(it)) == [u8(0), 1]

	assert sizeof(TargetOs) == 1
	assert [TargetOs.freestanding, .other, .contiki, .fuchsia, .hermit, .aix, .haiku, .hurd,
		.linux, .plan9, .rtems, .serenity, .zos, .dragonfly, .freebsd, .netbsd, .openbsd,
		.driverkit, .ios, .macos, .tvos, .visionos, .watchos, .illumos, .solaris, .windows,
		.uefi, .ps3, .ps4, .ps5, .emscripten, .wasi, .amdhsa, .amdpal, .cuda, .mesa3d, .nvcl,
		.opencl, .opengl, .vulkan].map(u8(it)) == [u8(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
		11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
		31, 32, 33, 34, 35, 36, 37, 38, 39]

	assert sizeof(NotifyOnCommandFinish) == 1
	assert [NotifyOnCommandFinish.never, .unfocused, .always].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(GraphemeWidthMethod) == 1
	assert [GraphemeWidthMethod.legacy, .unicode].map(u8(it)) == [u8(0), 1]
	assert sizeof(Scrollbar) == 1
	assert [Scrollbar.system, .never].map(u8(it)) == [u8(0), 1]
	assert sizeof(terminal.CursorStyle) == 1
	assert [terminal.CursorStyle.bar, .block, .underline, .block_hollow].map(u8(it)) == [u8(0),
		1, 2, 3]
}

fn test_window_and_runtime_config_enum_layouts_and_source_ordinals() {
	assert sizeof(WindowTheme) == 1
	assert [WindowTheme.auto, .system, .light, .dark, .witty].map(u8(it)) == [u8(0), 1,
		2, 3, 4]
	assert sizeof(RightClickAction) == 1
	assert [RightClickAction.ignore, .paste, .copy, .copy_or_paste, .context_menu].map(u8(it)) == [u8(0),
		1, 2, 3, 4]
	assert sizeof(OSCColorReportFormat) == 1
	assert [OSCColorReportFormat.none_, .format_8_bit, .format_16_bit].map(u8(it)) == [u8(0),
		1, 2]
	assert sizeof(WindowSubtitle) == 1
	assert [WindowSubtitle.false_, .working_directory].map(u8(it)) == [u8(0), 1]
	assert sizeof(WindowSaveState) == 1
	assert [WindowSaveState.default, .never, .always].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(WindowNewTabPosition) == 1
	assert [WindowNewTabPosition.current, .end].map(u8(it)) == [u8(0), 1]
	assert sizeof(WindowShowTabBar) == 1
	assert [WindowShowTabBar.always, .auto, .never].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(ResizeOverlay) == 1
	assert [ResizeOverlay.always, .never, .after_first].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(ResizeOverlayPosition) == 1
	assert [ResizeOverlayPosition.center, .top_left, .top_center, .top_right, .bottom_left,
		.bottom_center, .bottom_right].map(u8(it)) == [u8(0), 1, 2, 3, 4, 5, 6]
	assert sizeof(AsyncBackend) == 1
	assert [AsyncBackend.auto, .epoll, .io_uring].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(AutoUpdate) == 1
	assert [AutoUpdate.off, .check, .download].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(buildcfg.ReleaseChannel) == 1
	assert [buildcfg.ReleaseChannel.tip, .stable].map(u8(it)) == [u8(0), 1]
}

fn test_config_local_and_quick_terminal_tag_layouts_and_source_ordinals() {
	assert sizeof(ReplayStepKind) == 1
	assert [ReplayStepKind.arg, .expand, .conditional_arg, .diagnostic, .command].map(u8(it)) == [u8(0),
		1, 2, 3, 4]
	steps := [ReplayStep(ReplayArg{}), ReplayStep(ReplayExpand{}),
		ReplayStep(ReplayConditionalArg{}), ReplayStep(ReplayDiagnostic{}),
		ReplayStep(ReplayCommand{})]
	assert steps.map(it.kind()) == [ReplayStepKind.arg, .expand, .conditional_arg, .diagnostic,
		.command]
	assert sizeof(OptionalFileAction) == 1
	assert [OptionalFileAction.loaded, .not_found, .error_].map(u8(it)) == [u8(0), 1, 2]

	assert sizeof(CQuickTerminalSizeTag) == 4
	assert [CQuickTerminalSizeTag.none, .percentage, .pixels].map(i32(it)) == [i32(0), 1, 2]
	assert sizeof(QuickTerminalPosition) == 1
	assert [QuickTerminalPosition.top, .bottom, .left, .right, .center].map(u8(it)) == [u8(0),
		1, 2, 3, 4]
	assert sizeof(QuickTerminalScreen) == 1
	assert [QuickTerminalScreen.main, .mouse, .macos_menu_bar].map(u8(it)) == [u8(0), 1, 2]
	assert sizeof(QuickTerminalSpaceBehavior) == 1
	assert [QuickTerminalSpaceBehavior.remain, .move].map(u8(it)) == [u8(0), 1]
	assert sizeof(QuickTerminalKeyboardInteractivity) == 1
	assert [QuickTerminalKeyboardInteractivity.none_, .on_demand, .exclusive].map(u8(it)) == [u8(0),
		1, 2]
}

fn test_load_file_applies_theme_colors() {
	path := os.join_path(os.temp_dir(), 'witty-theme-test.conf')
	os.write_file(path, '
# comment
palette = 0=#010203
palette = 15=#fdfefd
background = #102030
foreground = #abcdef
')!
	defer {
		os.rm(path) or {}
	}

	mut cfg := Config.default_config()
	cfg.load_file(path)!

	assert cfg.diagnostics.len == 0
	assert cfg.background == ColorRGB{
		r: 0x10
		g: 0x20
		b: 0x30
	}
	assert cfg.foreground == ColorRGB{
		r: 0xab
		g: 0xcd
		b: 0xef
	}
	assert cfg.palette.value[0] == ColorRGB{
		r: 1
		g: 2
		b: 3
	}
	assert cfg.palette.value[15] == ColorRGB{
		r: 0xfd
		g: 0xfe
		b: 0xfd
	}
}

fn test_load_cli_args_applies_flags_paths_and_command_tail() {
	mut cfg := Config.default_config()
	cfg.font_family = ['From File']
	cfg.load_cli_args([
		'--font-family=From CLI',
		'--window-vsync=false',
		'--custom-shader=shader.glsl',
		'-e',
		'/bin/echo',
		'hello world',
	])!

	assert cfg.font_family == ['From CLI']
	assert !cfg.window_vsync
	assert cfg.custom_shader.items == [
		Path(PathRequired{ path: os.join_path(os.getwd(), 'shader.glsl') }),
	]
	command := cfg.initial_command or { panic('missing -e command') }
	match command {
		DirectCmd {
			assert command.direct == ['/bin/echo', 'hello world']
		}
		ShellCmd {
			assert false, '-e must produce a direct command'
		}
	}
	assert cfg.quit_after_last_window_closed
}

fn test_load_args_cli_can_discard_default_files_and_add_recursive_file() {
	dir := os.join_path(os.temp_dir(), 'witty-config-cli-${os.getpid()}')
	xdg_dir := os.join_path(dir, 'witty')
	os.rmdir_all(dir) or {}
	os.mkdir_all(xdg_dir)!
	defer { os.rmdir_all(dir) or {} }
	old_xdg := os.getenv_opt('XDG_CONFIG_HOME')
	os.setenv('XDG_CONFIG_HOME', dir, true)
	defer {
		if value := old_xdg {
			os.setenv('XDG_CONFIG_HOME', value, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
	}
	os.write_file(os.join_path(xdg_dir, 'config.witty'), 'font-size = 9\n')!
	extra := os.join_path(dir, 'extra.conf')
	os.write_file(extra, 'cursor-opacity = 0.25\n')!

	cfg := Config.load_args([
		'--config-default-files=false',
		'--font-size=17',
		'--config-file=${extra}',
	])!
	assert cfg.font_size == 17
	assert cfg.cursor_opacity == 0.25
	assert !cfg.config_default_files
	assert cfg.diagnostics.len == 0
}

fn test_load_file_records_diagnostics_for_invalid_lines() {
	path := os.join_path(os.temp_dir(), 'witty-theme-invalid-test.conf')
	os.write_file(path, '
foreground #ffffff
background = nope
palette = 300=#ffffff
')!
	defer {
		os.rm(path) or {}
	}

	mut cfg := Config.default_config()
	cfg.load_file(path)!

	assert cfg.diagnostics.len == 3
	assert cfg.diagnostics[0].format() == '${path}:2:foreground #ffffff: unknown field'
	assert cfg.diagnostics[1].format() == '${path}:3:background: invalid value "nope"'
	assert cfg.diagnostics[2].format().starts_with('${path}:4:palette: ')
}

fn test_load_cli_args_records_diagnostic_location_and_key() {
	mut cfg := Config.default_config()
	cfg.load_cli_args(['--font-size=nope'])!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == 'cli:1:font-size: invalid value "nope"'
}

fn test_load_cli_args_diagnostic_lists_enum_values() {
	mut cfg := Config.default_config()
	cfg.load_cli_args(['--window-theme=nope'])!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == 'cli:1:window-theme: invalid value "nope", valid values are: auto, system, light, dark, witty'
}

fn test_load_iter_uses_iterator_location_contract() {
	mut without_location := Config.default_config()
	mut slice_iter := cli_args.slice_iterator(['--font-size=nope'])
	without_location.load_iter(mut slice_iter)
	assert without_location.diagnostics.len == 1
	assert without_location.diagnostics[0].format() == 'font-size: invalid value "nope"'

	mut with_location := Config.default_config()
	mut args_iter := cli_args.ArgsIterator.new(['+version', '--font-size=nope'])
	with_location.load_iter(mut args_iter)
	assert with_location.diagnostics.len == 1
	assert with_location.diagnostics[0].format() == 'cli:2:font-size: invalid value "nope"'
}

fn test_load_iter_replay_keeps_exact_normalized_argument() {
	mut cfg := Config.default_config()
	mut iter := cli_args.slice_iterator(['--title=a=b'])
	cfg.load_iter(mut iter)
	assert cfg.title or { '' } == 'a=b'
	assert cfg.replay_steps.len == 1
	assert cfg.replay_steps[0] is ReplayArg
	assert (cfg.replay_steps[0] as ReplayArg).value == '--title=a=b'
}

fn test_parse_manually_hook_records_args_and_consumes_command_tail() {
	mut regular := Config.default_config()
	mut empty := cli_args.slice_iterator([])
	assert regular.parse_manually_hook('--font-size=18', mut empty)
	assert regular.replay_steps.len == 1
	assert regular.replay_steps[0] is ReplayArg
	assert (regular.replay_steps[0] as ReplayArg).value == '--font-size=18'

	mut command := Config.default_config()
	mut params := cli_args.slice_iterator(['echo', 'hello world'])
	assert !command.parse_manually_hook('-e', mut params)
	assert command.initial_command or { panic('missing command') }.string_val() == 'echo hello world'
	assert command.replay_steps.len == 3
	assert command.replay_steps[0] is ReplayCommand
	assert command.replay_steps[1] is ReplayArg
	assert (command.replay_steps[1] as ReplayArg).value == 'echo'
	assert command.replay_steps[2] is ReplayArg
	assert (command.replay_steps[2] as ReplayArg).value == 'hello world'
}

fn test_empty_command_diagnostic_is_regenerated_without_replay_location() ! {
	theme := os.join_path(os.temp_dir(), 'witty-empty-command-theme-${os.getpid()}')
	os.write_file(theme, '')!
	defer {
		os.rm(theme) or {}
	}
	mut cfg := Config.default_config()
	cfg.load_cli_args(['--theme=${theme}', '-e'])!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == 'cli:2: missing command after -e'
	cfg.finalize()!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == 'missing command after -e'
}

fn test_add_diagnostic_fmt_has_no_location_or_replay_step() {
	mut cfg := Config.default_config()
	cfg.add_diagnostic_fmt('startup failed: OutOfMemory')
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == 'startup failed: OutOfMemory'
	assert cfg.replay_steps.len == 0
}

fn test_theme_replay_regenerates_diagnostic_without_iterator_location() ! {
	path := os.join_path(os.temp_dir(), 'witty-diagnostic-theme-${os.getpid()}')
	os.write_file(path, '')!
	defer {
		os.rm(path) or {}
	}
	mut cfg := Config.default_config()
	cfg.load_cli_args(['--theme=${path}', '--font-size=nope'])!
	cfg.finalize()!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == 'font-size: invalid value "nope"'
}

fn test_preferred_default_file_path_uses_platform_location() ! {
	old := os.getenv_opt('XDG_CONFIG_HOME')
	os.setenv('XDG_CONFIG_HOME', '/tmp/witty-config-home', true)
	defer {
		if value := old {
			os.setenv('XDG_CONFIG_HOME', value, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
	}

	expected := $if macos { default_app_support_path()! } $else { os.join_path('/tmp/witty-config-home', 'witty', 'config.witty') }
	assert preferred_default_file_path()! == expected
}

// ============================================================
// Translated from ghostty src/config/Config.zig `test "..."` blocks.
// ============================================================

// expect_parse_error asserts that the given error carries the given
// ParseError kind (mirroring Zig's expectError).
fn expect_parse_error(err IError, want ParseError) {
	got := parse_error_of(err) or {
		assert false, 'expected ParseError.${want}, got non-ParseError: ${err}'
		return
	}
	assert got == want, 'expected ParseError.${want}, got ParseError.${got}'
}

// --- Color ---

// Config.zig: Color "fromHex"
fn test_color_from_hex() {
	assert ColorRGB.from_hex('#000000')! == ColorRGB{0, 0, 0}
	assert color_from_hex('#000000')! == ColorRGB{0, 0, 0}
	assert color_from_hex('#0A0B0C')! == ColorRGB{10, 11, 12}
	assert color_from_hex('0A0B0C')! == ColorRGB{10, 11, 12}
	assert color_from_hex('FFFFFF')! == ColorRGB{255, 255, 255}
	assert color_from_hex('FFF')! == ColorRGB{255, 255, 255}
	assert color_from_hex('#345')! == ColorRGB{51, 68, 85}
}

// Config.zig: Color "parseCLI from name"
fn test_color_parse_cli_from_name() {
	assert ColorRGB.parse_cli('black')! == ColorRGB{0, 0, 0}
	assert color_parse_cli('black')! == ColorRGB{0, 0, 0}
}

// Config.zig: Color "parseCLI with whitespace"
fn test_color_parse_cli_with_whitespace() {
	assert color_parse_cli(' #AABBCC   ')! == ColorRGB{0xAA, 0xBB, 0xCC}
	assert color_parse_cli('  black ')! == ColorRGB{0, 0, 0}
}

// Config.zig: Color "formatConfig"
fn test_color_format() {
	color := ColorRGB{10, 11, 12}
	assert color.clone().equal(color)
	assert color.format_buf() == '#0a0b0c'
	assert color.format_entry() == '#0a0b0c'
	assert color.to_terminal_rgb() == terminal.RGB{ r: 10, g: 11, b: 12 }
	assert color.cval() == CConfigColor{ r: 10, g: 11, b: 12 }
	assert format_color(color) == '#0a0b0c'
}

// --- TerminalColor ---

// Config.zig: TerminalColor "parseCLI"
fn test_terminal_color_parse_cli() {
	a := terminal_color_parse_cli('#4e2a84')!
	assert a is TerminalColorColor
	assert (a as TerminalColorColor).color == ColorRGB{78, 42, 132}

	b := terminal_color_parse_cli('black')!
	assert b is TerminalColorColor
	assert (b as TerminalColorColor).color == ColorRGB{0, 0, 0}

	assert terminal_color_parse_cli('cell-foreground')! is TerminalColorCellForeground
	assert terminal_color_parse_cli('cell-background')! is TerminalColorCellBackground
	mut got_value_required := false
	TerminalColor.parse_cli(none) or {
		expect_parse_error(err, .value_required)
		got_value_required = true
	}
	assert got_value_required
	terminal_rgb := a.to_terminal_rgb() or { terminal.RGB{} }
	assert terminal_rgb == terminal.RGB{ r: 78, g: 42, b: 132 }
	assert TerminalColor(TerminalColorCellForeground{}).to_terminal_rgb() == none
	assert TerminalColor(TerminalColorCellBackground{}).format_entry() == 'cell-background'

	terminal_color_parse_cli('a') or {
		expect_parse_error(err, .invalid_value)
		return
	}
	assert false, 'expected error for "a"'
}

// --- BoldColor ---

// Config.zig: BoldColor "parseCLI"
fn test_bold_color_parse_cli() {
	a := bold_color_parse_cli('#4e2a84')!
	assert a is BoldColorColor
	assert (a as BoldColorColor).color == ColorRGB{78, 42, 132}
	assert a.format_entry() == '#4e2a84'

	b := bold_color_parse_cli('black')!
	assert b is BoldColorColor
	assert (b as BoldColorColor).color == ColorRGB{0, 0, 0}

	assert BoldColor.parse_cli('bright')! is BoldColorBright
	assert BoldColor.parse_cli('bright')!.format_entry() == 'bright'
	BoldColor.parse_cli(none) or {
		expect_parse_error(err, .value_required)
	}

	bold_color_parse_cli('a') or {
		expect_parse_error(err, .invalid_value)
		return
	}
	assert false, 'expected error for "a"'
}

// --- Palette ---

fn test_palette_default_matches_terminal_palette() {
	p := Palette.default_palette()
	for i in 0 .. 256 {
		expected := terminal.default_palette[i]
		assert p.value[i] == ColorRGB{expected.r, expected.g, expected.b}
	}
}

// Config.zig: Palette "parseCLI"
fn test_palette_parse_cli() {
	mut p := Palette.default_palette()
	p.parse_cli('0=#AABBCC')!
	assert p.value[0].r == 0xAA
	assert p.value[0].g == 0xBB
	assert p.value[0].b == 0xCC
}

// Config.zig: Palette "parseCLI base"
fn test_palette_parse_cli_base() {
	mut p := Palette.default_palette()
	p.parse_cli('0b1=#014589')!
	p.parse_cli('0o7=#234567')!
	p.parse_cli('0xF=#ABCDEF')!
	p.parse_cli('+0x1__0=#102030')!
	p.parse_cli('-0=#000000')!

	assert p.value[0] == ColorRGB{0x00, 0x00, 0x00}
	assert p.value[1] == ColorRGB{0x01, 0x45, 0x89}
	assert p.value[7] == ColorRGB{0x23, 0x45, 0x67}
	assert p.value[15] == ColorRGB{0xAB, 0xCD, 0xEF}
	assert p.value[16] == ColorRGB{0x10, 0x20, 0x30}
}

// Config.zig: Palette "parseCLI overflow"
fn test_palette_parse_cli_overflow() {
	mut p := Palette.default_palette()
	for value in ['256=#AABBCC', '-1=#AABBCC', '18446744073709551616=#AABBCC'] {
		p.parse_cli(value) or {
			expect_parse_error(err, .overflow)
			continue
		}
		assert false, 'expected overflow error for ${value}'
	}
}

fn test_palette_parse_cli_rejects_edge_underscores() {
	mut p := Palette.default_palette()
	for value in ['_1=#AABBCC', '1_=#AABBCC', '0x_1=#AABBCC'] {
		p.parse_cli(value) or {
			expect_parse_error(err, .invalid_value)
			continue
		}
		assert false, 'expected invalid value for ${value}'
	}
}

// Config.zig: Palette "parseCLI with whitespace"
fn test_palette_parse_cli_with_whitespace() {
	mut p := Palette.default_palette()
	p.parse_cli('0 =  #AABBCC')!
	p.parse_cli(' 1= #DDEEFF    ')!
	p.parse_cli('  2  =  #123456 ')!

	assert p.value[0] == ColorRGB{0xAA, 0xBB, 0xCC}
	assert p.value[1] == ColorRGB{0xDD, 0xEE, 0xFF}
	assert p.value[2] == ColorRGB{0x12, 0x34, 0x56}
}

// --- RepeatableString ---

// Config.zig: RepeatableString "parseCLI"
fn test_repeatable_string_parse_cli() {
	mut list := RepeatableStringList{}
	list.parse_cli('A')!
	list.parse_cli('B')!
	assert list.list.len == 2

	list.parse_cli('')!
	assert list.list.len == 0
}

// Config.zig: RepeatableString "parseCLI overwrite"
fn test_repeatable_string_parse_cli_overwrite() {
	mut list := RepeatableStringList{}
	list.parse_cli('A')!

	list.overwrite_next = true

	list.parse_cli('B')!
	assert list.list.len == 1
	list.parse_cli('C')!
	assert list.list.len == 2
}

fn test_repeatable_string_value_apis() {
	mut list := RepeatableStringList{}
	assert list.format_entry() == ['']
	list.parse_cli('A')!
	list.parse_cli('B')!
	cloned := list.clone()
	assert list.equal(cloned)
	assert cloned.count() == 2
	assert cloned.format_entry() == ['A', 'B']
}

// --- Duration ---

// Config.zig: "parse duration"
fn test_parse_duration() {
	// "0<unit>" == 0 for every unit.
	for unit in duration_units {
		d := duration_parse_cli('0${unit.name}')!
		assert d.duration == 0
	}
	// "1<unit>" == unit.factor for every unit.
	for unit in duration_units {
		d := duration_parse_cli('1${unit.name}')!
		assert d.duration == unit.factor
	}

	assert duration_parse_cli('0')!.duration == 0
	assert duration_parse_cli('100ns')!.duration == 100
	assert duration_parse_cli('1µs')!.duration == 1000
	assert duration_parse_cli('1µs1ns')!.duration == 1001
	assert duration_parse_cli('1µs 1ns')!.duration == 1001
	assert duration_parse_cli(' 1µs1ns')!.duration == 1001
	assert duration_parse_cli('1µs1ns ')!.duration == 1001
	assert duration_parse_cli('30s')!.duration == u64(30) * 1_000_000_000
	assert duration_parse_cli('584y 49w 23h 34m 33s 709ms 551µs 615ns')!.duration == u64_max
	// Overflow saturates.
	assert duration_parse_cli('600y')!.duration == u64_max
	duration_parse_cli('18446744073709551616ns') or {
		expect_parse_error(err, .invalid_value)
	}
	// Repeated units accumulate.
	assert duration_parse_cli('100ns100ns')!.duration == 200

	duration_parse_cli(none) or {
		expect_parse_error(err, .value_required)
		duration_parse_cli('') or {
			expect_parse_error(err, .value_required)
			duration_parse_cli('1') or {
				expect_parse_error(err, .invalid_value)
				duration_parse_cli('s') or {
					expect_parse_error(err, .invalid_value)
					duration_parse_cli('1x') or {
						expect_parse_error(err, .invalid_value)
						duration_parse_cli('1 ') or {
							expect_parse_error(err, .invalid_value)
							return
						}
						assert false
						return
					}
					assert false
					return
				}
				assert false
				return
			}
			assert false
			return
		}
		assert false
		return
	}
	assert false, 'expected value_required for null'
}

// Config.zig: "test format" (Duration formatting)
fn test_duration_format() {
	for unit in duration_units {
		d := Duration{
			duration: unit.factor
		}
		expected := if unit.name != 'us' { '1${unit.name}' } else { '1µs' }
		assert d.format() == expected
	}
}

// Config.zig: Duration "test entryFormatter" (max value formatting)
fn test_duration_format_max() {
	d := Duration{
		duration: u64_max
	}
	assert d.format() == '584y 49w 23h 34m 33s 709ms 551µs 615ns'
}

fn test_duration_as_milliseconds_saturates() {
	assert Duration{ duration: 999_999 }.as_milliseconds() == 0
	assert Duration{ duration: 1_500_000 }.as_milliseconds() == 1
	assert Duration{ duration: u64_max }.as_milliseconds() == u32(0xffff_ffff)
	assert Duration{ duration: 1_500_000 }.cval() == uint(1)
}

fn test_duration_round_and_lte() {
	d := Duration{ duration: 1_999_999 }
	assert d.clone().equal(d)
	assert d.format_entry() == '1ms 999µs 999ns'
	assert d.round(1_000_000) == Duration{
		duration: 1_000_000
	}
	assert Duration{ duration: 5 }.lte(Duration{ duration: 5 })
	assert Duration{ duration: 4 }.lte(Duration{ duration: 5 })
	assert !Duration{ duration: 6 }.lte(Duration{ duration: 5 })
	assert Duration.parse_cli('5ms')! == Duration{ duration: 5_000_000 }
}

fn test_quit_after_last_window_closed_delay_parse_and_format() {
	mut cfg := Config.default_config()
	assert cfg.quit_after_last_window_closed == default_quit_after_last_window_closed
	assert cfg.quit_after_last_window_closed_delay == none
	cfg.load_string('quit-after-last-window-closed-delay = 1s500ms')
	delay := cfg.quit_after_last_window_closed_delay or {
		assert false, 'expected quit delay'
		return
	}
	assert delay.duration == 1_500_000_000
	assert cfg.format_config(true).contains('quit-after-last-window-closed-delay = 1s 500ms\n')

	cfg.load_string('quit-after-last-window-closed-delay =')
	assert cfg.quit_after_last_window_closed_delay == none
	cfg.load_string('quit-after-last-window-closed-delay = soon')
	assert cfg.diagnostics.len == 1
}

fn test_resize_overlay_defaults_parse_and_format() {
	mut cfg := Config.default_config()
	assert cfg.resize_overlay == .after_first
	assert cfg.resize_overlay_position == .center
	assert cfg.resize_overlay_duration.duration == 750_000_000

	cfg.load_string('resize-overlay = always\nresize-overlay-position = bottom-right\nresize-overlay-duration = 1s250ms')
	assert cfg.diagnostics.len == 0
	assert cfg.resize_overlay == .always
	assert cfg.resize_overlay_position == .bottom_right
	assert cfg.resize_overlay_duration.duration == 1_250_000_000
	formatted := cfg.format_config(true)
	assert formatted.contains('resize-overlay = always\n')
	assert formatted.contains('resize-overlay-position = bottom-right\n')
	assert formatted.contains('resize-overlay-duration = 1s 250ms\n')

	cfg.load_string('resize-overlay = sometimes\nresize-overlay-position = middle\nresize-overlay-duration = soon')
	assert cfg.diagnostics.len == 3
}

// --- WindowPadding ---

// Config.zig: WindowPadding "parse WindowPadding"
fn test_parse_window_padding() {
	one := window_padding_parse_cli('100')!
	assert one == WindowPadding{100, 100}
	assert WindowPadding.parse_cli('100')! == one
	assert one.clone().equal(one)
	assert one.format_entry() == '100'
	two := window_padding_parse_cli('100,200')!
	assert two == WindowPadding{100, 200}
	assert two.format_entry() == '100,200'
	assert window_padding_parse_cli(' 100 , 200 ')! == WindowPadding{100, 200}
	assert window_padding_parse_cli('+1__0,-0')! == WindowPadding{10, 0}
	window_padding_parse_cli('0x10') or {
		expect_parse_error(err, .invalid_value)
	}

	window_padding_parse_cli(none) or {
		expect_parse_error(err, .value_required)
		window_padding_parse_cli('') or {
			expect_parse_error(err, .invalid_value)
			window_padding_parse_cli('a') or {
				expect_parse_error(err, .invalid_value)
				return
			}
			assert false
			return
		}
		assert false
		return
	}
	assert false, 'expected value_required for null'
}

// --- MouseScrollMultiplier ---

// Config.zig: MouseScrollMultiplier "parse"
fn test_mouse_scroll_multiplier_parse() {
	mut args := MouseScrollMultiplier{
		precision: 0.1
		discrete: 3
	}
	args.parse_cli('3')!
	assert args.precision == 3
	assert args.discrete == 3

	args = MouseScrollMultiplier{
		precision: 0.1
		discrete: 3
	}
	args.parse_cli('precision:1')!
	assert args.precision == 1
	assert args.discrete == 3

	args = MouseScrollMultiplier{
		precision: 0.1
		discrete: 3
	}
	args.parse_cli('discrete:5')!
	assert args.precision == 0.1
	assert args.discrete == 5

	args = MouseScrollMultiplier{
		precision: 0.1
		discrete: 3
	}
	args.parse_cli('precision:3,discrete:7')!
	assert args.precision == 3
	assert args.discrete == 7

	args = MouseScrollMultiplier{
		precision: 0.1
		discrete: 3
	}
	args.parse_cli('discrete:8,precision:6')!
	assert args.precision == 6
	assert args.discrete == 8

	args.parse_cli('0x1p1')!
	assert args.precision == 2
	assert args.discrete == 2
	args.parse_cli('precision:1_0e-1')!
	assert args.precision == 1
	assert args.discrete == 2
	before_invalid := args.clone()
	args.parse_cli('precision:4,invalid:5') or {
		assert args.equal(before_invalid)
	}

	mut e := MouseScrollMultiplier{}
	e.parse_cli('foo:1') or {
		expect_parse_error(err, .invalid_value)
		e.parse_cli('precision:bar') or {
			expect_parse_error(err, .invalid_value)
			e.parse_cli('precision:1,discrete:3,foo:5') or {
				expect_parse_error(err, .invalid_value)
				e.parse_cli('precision:1,,discrete:3') or {
					expect_parse_error(err, .invalid_value)
					e.parse_cli(',precision:1,discrete:3') or {
						expect_parse_error(err, .invalid_value)
						return
					}
					assert false
					return
				}
				assert false
				return
			}
			assert false
			return
		}
		assert false
		return
	}
	assert false, 'expected invalid_value for foo:1'
}

// Config.zig: MouseScrollMultiplier "format entry MouseScrollMultiplier"
fn test_mouse_scroll_multiplier_format() {
	args := MouseScrollMultiplier{
		precision: 1.5
		discrete: 2.5
	}
	assert args.format_entry() == 'precision:1.5,discrete:2.5'
	assert args.clone().equal(args)
}

// --- QuickTerminalSize ---

// Config.zig: QuickTerminalSize "parse QuickTerminalSize"
fn test_parse_quick_terminal_size() {
	mut v := QuickTerminalSize{}
	parsed_size := QuickTerminalSizeValue.parse('25%')!
	assert parsed_size.to_pixels(200) == 50
	assert parsed_size.format() == '25%'
	assert CQuickTerminalSize.percentage(25).tag == .percentage
	assert CQuickTerminalSize.pixels(25) == CQuickTerminalSize{ tag: .pixels, value: 25 }

	v.parse_cli('50%')!
	primary := v.primary or {
		assert false
		return
	}
	assert primary is QuickTerminalSizePercentage
	assert (primary as QuickTerminalSizePercentage).value == 50
	assert v.secondary == none
	assert v.clone() == v
	formatted_size := v.format_entry() or { '' }
	assert formatted_size == '50%'
	assert v.cval().primary.tag == .percentage

	v = QuickTerminalSize{}
	v.parse_cli('0x32p0%')!
	hex_percentage := v.primary or {
		assert false
		return
	}
	assert hex_percentage is QuickTerminalSizePercentage
	assert (hex_percentage as QuickTerminalSizePercentage).value == 50

	v = QuickTerminalSize{}
	v.parse_cli('200px')!
	p2 := v.primary or {
		assert false
		return
	}
	assert p2 is QuickTerminalSizePixels
	assert (p2 as QuickTerminalSizePixels).value == 200
	assert v.secondary == none

	v = QuickTerminalSize{}
	v.parse_cli('+2__0px,-0px')!
	underscore_primary := v.primary or {
		assert false
		return
	}
	underscore_secondary := v.secondary or {
		assert false
		return
	}
	assert underscore_primary is QuickTerminalSizePixels
	assert (underscore_primary as QuickTerminalSizePixels).value == 20
	assert underscore_secondary is QuickTerminalSizePixels
	assert (underscore_secondary as QuickTerminalSizePixels).value == 0

	v = QuickTerminalSize{}
	v.parse_cli('50%,200px')!
	p3 := v.primary or {
		assert false
		return
	}
	s3 := v.secondary or {
		assert false
		return
	}
	assert p3 is QuickTerminalSizePercentage
	assert (p3 as QuickTerminalSizePercentage).value == 50
	assert s3 is QuickTerminalSizePixels
	assert (s3 as QuickTerminalSizePixels).value == 200

	mut e := QuickTerminalSize{}
	e.parse_cli(none) or {
		expect_parse_error(err, .value_required)
		e.parse_cli('') or {
			expect_parse_error(err, .value_required)
			e.parse_cli('69px,') or {
				expect_parse_error(err, .value_required)
				e.parse_cli('69px,42%,69px') or {
					expect_parse_error(err, .too_many_arguments)
					e.parse_cli('420') or {
						expect_parse_error(err, .missing_unit)
						e.parse_cli('bobr') or {
							expect_parse_error(err, .missing_unit)
							e.parse_cli('bobr%') or {
								expect_parse_error(err, .invalid_value)
								e.parse_cli('-32%') or {
									expect_parse_error(err, .invalid_value)
									e.parse_cli('-69px') or {
										expect_parse_error(err, .invalid_value)
										return
									}
									assert false
									return
								}
								assert false
								return
							}
							assert false
							return
						}
						assert false
						return
					}
					assert false
					return
				}
				assert false
				return
			}
			assert false
			return
		}
		assert false
		return
	}
	assert false, 'expected value_required for null'
}

fn test_repeatable_font_variation_uses_zig_float_grammar() {
	mut variation := RepeatableFontVariation{}
	variation.parse_cli('wght=0x1p1')!
	assert variation.list[0].value == 2
	variation.parse_cli('wght= 1 ')!
	assert variation.list[1].value == 1
	variation.parse_cli('wght=1 ')!
	assert variation.list[2].value == 1
	variation.parse_cli('wght=1 x') or {
		expect_parse_error(err, .invalid_value)
		return
	}
	assert false, 'expected trailing junk to fail'
}

fn test_font_value_type_formatters() {
	mut style := font_style_parse_cli('default')!
	style.parse_cli('Regular')!
	assert style.clone() == style
	assert style.name_value() or { '' } == 'Regular'
	assert style.format_entry() == 'Regular'
	assert font_style_parse_cli('default')!.format_entry() == 'default'

	mut variation := RepeatableFontVariation{}
	assert variation.format_entry() == ['']
	variation.parse_cli('wght=200')!
	variation.parse_cli('slnt=-15.5')!
	assert variation.format_entry() == ['wght=200', 'slnt=-15.5']

	mut mappings := RepeatableCodepointMap{}
	assert mappings.format_entry() == ['']
	mappings.parse_cli('U+0001-U+0005, U+ABCD=Comic Sans')!
	assert mappings.format_entry() == [
		'U+0001-U+0005=Comic Sans',
		'U+ABCD=Comic Sans',
	]
}

// Config.zig: QuickTerminalSize "calculate QuickTerminalSize"
fn test_calculate_quick_terminal_size() {
	dims_landscape := QuickTerminalDimensions{
		width: 2560
		height: 1600
	}
	dims_portrait := QuickTerminalDimensions{
		width: 1600
		height: 2560
	}

	size := QuickTerminalSize{}
	assert size.calculate(.top, dims_landscape) == QuickTerminalDimensions{2560, 400}
	assert size.calculate(.left, dims_landscape) == QuickTerminalDimensions{400, 1600}
	// Center on landscape: 800x400
	assert size.calculate(.center, dims_landscape) == QuickTerminalDimensions{800, 400}
	// Center on portrait: 400x800
	assert size.calculate(.center, dims_portrait) == QuickTerminalDimensions{400, 800}
}

// --- BackgroundBlur ---

// Config.zig: BackgroundBlur "parse BackgroundBlur"
fn test_parse_background_blur() {
	assert background_blur_parse_cli(none)! is BackgroundBlurTrue
	assert background_blur_parse_cli('true')! is BackgroundBlurTrue
	assert background_blur_parse_cli('false')! is BackgroundBlurFalse

	r := background_blur_parse_cli('42')!
	assert r is BackgroundBlurRadius
	assert (r as BackgroundBlurRadius).radius == 42

	assert background_blur_parse_cli('macos-glass-regular')! is BackgroundBlurMacosGlassRegular
	assert background_blur_parse_cli('macos-glass-clear')! is BackgroundBlurMacosGlassClear

	background_blur_parse_cli('') or {
		expect_parse_error(err, .invalid_value)
		background_blur_parse_cli('aaaa') or {
			expect_parse_error(err, .invalid_value)
			background_blur_parse_cli('420') or {
				expect_parse_error(err, .invalid_value)
				return
			}
			assert false
			return
		}
		assert false
		return
	}
	assert false, 'expected invalid_value for empty'
}

fn test_background_blur_cval() {
	assert BackgroundBlur(BackgroundBlurFalse{}).cval() == 0
	assert BackgroundBlur(BackgroundBlurTrue{}).cval() == 20
	assert BackgroundBlur(BackgroundBlurRadius{ radius: 37 }).cval() == 37
	assert BackgroundBlur(BackgroundBlurRadius{ radius: 255 }).cval() == 255
	assert BackgroundBlur(BackgroundBlurMacosGlassRegular{}).cval() == -1
	assert BackgroundBlur(BackgroundBlurMacosGlassClear{}).cval() == -2
	assert BackgroundBlur(BackgroundBlurFalse{}).format_entry() == 'false'
	assert BackgroundBlur(BackgroundBlurTrue{}).format_entry() == 'true'
	assert BackgroundBlur(BackgroundBlurRadius{ radius: 37 }).format_entry() == '37'
	assert BackgroundBlur(BackgroundBlurMacosGlassRegular{}).format_entry() == 'macos-glass-regular'
	assert BackgroundBlur(BackgroundBlurMacosGlassClear{}).format_entry() == 'macos-glass-clear'
	mut blur := BackgroundBlur(BackgroundBlurFalse{})
	blur.parse_cli(none)!
	assert blur is BackgroundBlurTrue
	blur.parse_cli('invalid') or {
		assert blur is BackgroundBlurTrue
	}
}

fn test_repeatable_command_parse_clear_clone_and_format() {
	mut defaults := Config.default_config()
	assert defaults.command_palette_entry.items.len == input.command_defaults.len
	defaults.load_string('command-palette-entry =\ncommand-palette-entry = title:Only,action:ignore\n')
	assert defaults.command_palette_entry.items.len == input.command_defaults.len + 1
	assert defaults.command_palette_entry.items.last().title == 'Only'
	defaults.load_string('command-palette-entry = clear\ncommand-palette-entry = title:Only,action:ignore\n')
	assert defaults.diagnostics.len == 0
	assert defaults.command_palette_entry.items.len == 1
	assert defaults.command_palette_entry.cval().len == 1
	assert defaults.command_palette_entry.items[0].title == 'Only'

	mut commands := RepeatableCommand{}
	commands.parse_cli('title:Foo,action:ignore')!
	commands.parse_cli('title:"Bar, Baz",description:"line\\ntext",action:"text:hello, world"')!
	assert commands.items.len == 2
	assert commands.items[0].title == 'Foo'
	assert commands.items[0].action.tag() == .ignore
	assert commands.items[1].title == 'Bar, Baz'
	assert commands.items[1].description == 'line\ntext'
	assert commands.items[1].action.tag() == .text
	assert (commands.items[1].action as input.ActionText).value == 'hello, world'

	clone := commands.clone()
	assert clone.equal(commands)
	assert clone.items_c.len == clone.items.len
	assert clone.cval().len == uint(clone.items.len)
	assert clone.format_entry() == [
		'title:"Foo",action:"ignore"',
		'title:"Bar, Baz",description:"line\\ntext",action:"text:hello, world"',
	]

	mut cfg := Config{}
	cfg.command_palette_entry = commands
	formatted := cfg.format_config(false)
	assert formatted.contains('command-palette-entry = title:"Foo",action:"ignore"\n')
	assert formatted.contains('command-palette-entry = title:"Bar, Baz",description:"line\\ntext",action:"text:hello, world"\n')

	mut roundtrip := Config{}
	roundtrip.load_string(formatted)
	assert roundtrip.command_palette_entry.equal(cfg.command_palette_entry)

	commands.parse_cli('')!
	assert commands.items.len == 0
	assert commands.format_entry() == ['']
	commands.parse_cli('title:Again,action:ignore')!
	commands.parse_cli(none)!
	assert commands.items.len == 0
}

fn test_config_command_public_parse_and_format_apis() {
	shell := Command.parse_cli(' shell:  echo hello ')!
	assert shell == Command(ShellCmd{ shell: 'echo hello' })
	assert shell.string_val() == 'echo hello'
	assert shell.format_entry() == 'echo hello'

	direct := Command.parse_cli(' direct:  echo  hello ')!
	assert direct == Command(DirectCmd{ direct: ['echo', '', 'hello'] })
	assert direct.string_val() == 'echo  hello'
	assert direct.format_entry() == 'direct:echo  hello'

	Command.parse_cli(' ') or {
		assert err.msg() == 'value required'
		return
	}
	assert false, 'expected an empty command to fail'
}

fn test_config_command_arg_iterator_matches_zig_general_defaults() {
	command := Command(ShellCmd{
		shell: 'one\t"two three" \'four five\' six\\ seven "" eight\\\\\\"nine'
	})
	mut it := command.arg_iterator()
	defer { it.deinit() }
	mut args := []string{}
	for {
		args << it.next() or { break }
	}
	assert args == ['one', 'two three', "'four", "five'", 'six\\', 'seven', '', 'eight\\"nine']
}

fn test_readable_io_parse_clone_parse_and_format() {
	raw := ReadableIO.parse_cli('foo\\n\\u{1F601}\\x21')!
	assert raw == ReadableIO(ReadableIORaw{
		value: 'foo\\n\\u{1F601}\\x21'
	})
	assert raw.clone_parsed()! == ReadableIO(ReadableIORaw{
		value: 'foo\n😁!'
	})
	assert parse_zig_string('zero=\\u{0000000}')! == 'zero=\x00'
	assert ReadableIO.parse_cli('raw:hello')! == ReadableIO(ReadableIORaw{ value: 'hello' })
	assert ReadableIO.parse_cli('path:file.txt')! == ReadableIO(ReadableIOPath{ value: 'file.txt' })
	assert ReadableIO.parse_cli(' raw \t: hello')! == ReadableIO(ReadableIORaw{ value: ' hello' })
	assert ReadableIO.parse_cli('path')! == ReadableIO(ReadableIOPath{ value: '' })
	assert ReadableIO.parse_cli('raw')! == ReadableIO(ReadableIORaw{ value: '' })
	assert ReadableIO.parse_cli('other:value')! == ReadableIO(ReadableIORaw{
		value: 'other:value'
	})

	ReadableIO.parse_cli('bad\\q') or {
		assert err.msg() == 'invalid string'
		return
	}
	assert false, 'expected an invalid Zig escape'
}

fn test_repeatable_readable_io_clear_clone_and_format() {
	mut values := RepeatableReadableIO{}
	values.parse_cli('raw:A')!
	values.parse_cli('path:B')!
	assert values.items.len == 2
	assert values.clone().items == values.items
	assert values.equal(values.clone())
	assert values.format_entry() == ['raw:A', 'path:B']

	mut cfg := Config.default_config()
	cfg.input = values
	formatted := cfg.format_config(true)
	assert formatted.contains('input = raw:A\n')
	assert formatted.contains('input = path:B\n')

	mut roundtrip := Config.default_config()
	roundtrip.load_string(formatted)
	assert roundtrip.diagnostics.len == 0
	assert roundtrip.input.items == values.items

	values.parse_cli('')!
	assert values.items.len == 0
	assert values.format_entry() == ['']
}

fn test_repeatable_string_map_public_api() {
	mut values := RepeatableStringMap{}
	values.parse_cli(' A = B ')!
	values.parse_cli('B=C')!
	values.parse_cli('\r\nC\v=\fD\r')!
	values.parse_cli('A=replaced')!
	assert values.count() == 3
	assert values.format_entry() == ['A=replaced', 'B=C', 'C=D']
	assert values.equal(RepeatableStringMap{
		entries: [StringMapEntry{'B', 'C'}, StringMapEntry{'C', 'D'},
			StringMapEntry{'A', 'replaced'}]
	})
	assert values.clone().equal(values)

	values.parse_cli('A=')!
	assert values.format_entry() == ['B=C', 'C=D']
	values.parse_cli('')!
	assert values.count() == 0
	assert values.format_entry() == ['']

	values.parse_cli('missing-assignment') or {
		assert err.msg() == 'value required'
		return
	}
	assert false, 'expected missing assignment to fail'
}

fn test_macos_configuration_parse_clone_and_format() {
	mut cfg := Config.default_config()
	assert cfg.macos_non_native_fullscreen == .false_
	assert cfg.macos_window_buttons == .visible
	assert cfg.macos_titlebar_style == .transparent
	assert cfg.macos_titlebar_proxy_icon == .visible
	assert cfg.macos_option_as_alt == none
	assert cfg.macos_window_shadow
	assert cfg.macos_hidden == .never
	assert cfg.macos_auto_secure_input
	assert cfg.macos_secure_input_indication
	assert cfg.macos_icon == .official
	assert cfg.macos_icon_frame == .aluminum
	assert cfg.macos_shortcuts == .ask

	cfg.load_string('macos-non-native-fullscreen = padded-notch\nmacos-window-buttons = hidden\nmacos-titlebar-style = tabs\nmacos-titlebar-proxy-icon = hidden\nmacos-dock-drop-behavior = new-window\nmacos-option-as-alt = left\nmacos-window-shadow = false\nmacos-hidden = always\nmacos-auto-secure-input = false\nmacos-secure-input-indication = false\nmacos-icon = custom-style\nmacos-custom-icon = /tmp/icon.icns\nmacos-icon-frame = chrome\nmacos-icon-ghost-color = RebeccaPurple\nmacos-icon-screen-color = black, white ,#123456\nmacos-shortcuts = deny\n')
	assert cfg.diagnostics.len == 0
	assert cfg.macos_non_native_fullscreen == .padded_notch
	assert cfg.macos_window_buttons == .hidden
	assert cfg.macos_titlebar_style == .tabs
	assert cfg.macos_titlebar_proxy_icon == .hidden
	assert cfg.macos_dock_drop_behavior == .new_window
	assert cfg.macos_option_as_alt? == .left
	assert !cfg.macos_window_shadow
	assert cfg.macos_hidden == .always
	assert !cfg.macos_auto_secure_input
	assert !cfg.macos_secure_input_indication
	assert cfg.macos_icon == .custom_style
	assert cfg.macos_custom_icon? == '/tmp/icon.icns'
	assert cfg.macos_icon_frame == .chrome
	assert cfg.macos_icon_ghost_color? == ColorRGB{ r: 0x66, g: 0x33, b: 0x99 }
	colors := cfg.macos_icon_screen_color or { panic('missing icon gradient') }
	assert colors.colors == [ColorRGB{ r: 0, g: 0, b: 0 }, ColorRGB{
		r: 0xff
		g: 0xff
		b: 0xff
	}, ColorRGB{ r: 0x12, g: 0x34, b: 0x56 }]

	cloned := cfg.clone()
	assert cloned.macos_icon_screen_color?.colors == colors.colors
	formatted := cfg.format_config(true)
	assert formatted.contains('macos-non-native-fullscreen = padded-notch\n')
	assert formatted.contains('macos-option-as-alt = left\n')
	assert formatted.contains('macos-icon = custom-style\n')
	assert formatted.contains('macos-icon-screen-color = #000000,#ffffff,#123456\n')

	mut roundtrip := Config.default_config()
	roundtrip.load_string(formatted)
	assert roundtrip.diagnostics.len == 0
	assert roundtrip.macos_icon_screen_color?.colors == colors.colors
}

fn test_macos_color_list_resets_and_limits_entries() {
	mut colors := ColorList{}
	colors.parse_cli('black,white')!
	assert colors.colors_c == [CConfigColor{ r: 0, g: 0, b: 0 }, CConfigColor{
		r: 0xff
		g: 0xff
		b: 0xff
	}]
	colors.parse_cli('#123456')!
	assert colors.colors == [ColorRGB{ r: 0x12, g: 0x34, b: 0x56 }]
	assert colors.format_entry() == '#123456'
	cloned := colors.clone()
	assert colors.equal(cloned)
	cvalue := colors.cval()
	assert cvalue.len == 1
	assert unsafe { cvalue.colors[0] } == CConfigColor{ r: 0x12, g: 0x34, b: 0x56 }

	mut rejected_limit := false
	colors.parse_cli(['black'].repeat(65).join(',')) or {
		assert err.msg() == 'invalid value'
		rejected_limit = true
	}
	assert rejected_limit
	mut rejected_whitespace_token := false
	colors.parse_cli('${['black'].repeat(64).join(',')}, ') or {
		rejected_whitespace_token = true
	}
	assert rejected_whitespace_token
}

fn test_palette_value_apis() {
	mut palette := Palette.default_palette()
	palette.parse_cli('1=#123456')!
	cloned := palette.clone()
	assert palette.equal(cloned)
	assert palette.format_entry()[1] == '1=#123456'
	cvalue := palette.cval()
	assert cvalue.colors[1] == CConfigColor{ r: 0x12, g: 0x34, b: 0x56 }
}

fn test_repeatable_command_rejects_missing_and_invalid_fields() {
	mut commands := RepeatableCommand{}
	commands.parse_cli('title:Foo') or {
		commands.parse_cli('action:ignore') or {
			commands.parse_cli('title:Foo,unknown:x,action:ignore') or {
				commands.parse_cli('title:Foo,action:not_an_action') or { return }
			}
		}
	}
	assert false, 'expected invalid command palette entries'
}

fn test_window_and_quick_terminal_config_roundtrip() {
	mut cfg := Config.default_config()
	assert cfg.window_new_tab_position == .current
	assert cfg.window_show_tab_bar == .auto
	assert cfg.window_subtitle == .false_
	assert cfg.quick_terminal_position == .top
	assert cfg.quick_terminal_size.primary == none
	assert cfg.quick_terminal_screen == .main
	assert cfg.quick_terminal_animation_duration == 0.2
	assert cfg.quick_terminal_autohide == default_quick_terminal_autohide
	assert cfg.quick_terminal_space_behavior == .move
	assert cfg.quick_terminal_keyboard_interactivity == .on_demand

	quick_autohide_value := if default_quick_terminal_autohide { 'false' } else { 'true' }
	cfg.load_string('window-new-tab-position = end
window-show-tab-bar = never
window-subtitle = working-directory
quick-terminal-position = right
quick-terminal-size = 50%,320px
quick-terminal-screen = macos-menu-bar
quick-terminal-animation-duration = 0.35
quick-terminal-autohide = ${quick_autohide_value}
quick-terminal-space-behavior = remain
quick-terminal-keyboard-interactivity = exclusive')
	assert cfg.diagnostics.len == 0
	assert cfg.window_new_tab_position == .end
	assert cfg.window_show_tab_bar == .never
	assert cfg.window_subtitle == .working_directory
	assert cfg.quick_terminal_position == .right
	quick_primary := cfg.quick_terminal_size.primary or {
		assert false
		return
	}
	quick_secondary := cfg.quick_terminal_size.secondary or {
		assert false
		return
	}
	assert quick_primary is QuickTerminalSizePercentage
	assert (quick_primary as QuickTerminalSizePercentage).value == 50
	assert quick_secondary is QuickTerminalSizePixels
	assert (quick_secondary as QuickTerminalSizePixels).value == 320
	assert cfg.quick_terminal_screen == .macos_menu_bar
	assert cfg.quick_terminal_animation_duration == 0.35
	assert cfg.quick_terminal_autohide == !default_quick_terminal_autohide
	assert cfg.quick_terminal_space_behavior == .remain
	assert cfg.quick_terminal_keyboard_interactivity == .exclusive

	formatted := cfg.format_config(true)
	assert formatted.contains('window-new-tab-position = end\n')
	assert formatted.contains('window-show-tab-bar = never\n')
	assert formatted.contains('window-subtitle = working-directory\n')
	assert formatted.contains('quick-terminal-position = right\n')
	assert formatted.contains('quick-terminal-size = 50%,320px\n')
	assert formatted.contains('quick-terminal-screen = macos-menu-bar\n')
	assert formatted.contains('quick-terminal-animation-duration = 0.35\n')
	assert formatted.contains('quick-terminal-autohide = ${quick_autohide_value}\n')
	assert formatted.contains('quick-terminal-space-behavior = remain\n')
	assert formatted.contains('quick-terminal-keyboard-interactivity = exclusive\n')

	mut roundtrip := Config.default_config()
	roundtrip.load_string(formatted)
	assert roundtrip.window_new_tab_position == cfg.window_new_tab_position
	assert roundtrip.window_show_tab_bar == cfg.window_show_tab_bar
	assert roundtrip.window_subtitle == cfg.window_subtitle
	assert roundtrip.quick_terminal_position == cfg.quick_terminal_position
	roundtrip_primary := roundtrip.quick_terminal_size.primary or {
		assert false
		return
	}
	roundtrip_secondary := roundtrip.quick_terminal_size.secondary or {
		assert false
		return
	}
	assert roundtrip_primary is QuickTerminalSizePercentage
	assert roundtrip_primary.value == quick_primary.value
	assert roundtrip_secondary is QuickTerminalSizePixels
	assert roundtrip_secondary.value == quick_secondary.value
	assert roundtrip.quick_terminal_screen == cfg.quick_terminal_screen
	assert roundtrip.quick_terminal_animation_duration == cfg.quick_terminal_animation_duration
	assert roundtrip.quick_terminal_autohide == cfg.quick_terminal_autohide
	assert roundtrip.quick_terminal_space_behavior == cfg.quick_terminal_space_behavior
	assert roundtrip.quick_terminal_keyboard_interactivity == cfg.quick_terminal_keyboard_interactivity
}

fn test_linux_cgroup_config_parse_format_and_defaults() {
	mut cfg := Config.default_config()
	assert cfg.linux_cgroup == default_linux_cgroup
	assert cfg.linux_cgroup_memory_limit == none
	assert cfg.linux_cgroup_processes_limit == none
	assert !cfg.linux_cgroup_hard_fail

	cfg.load_string('linux-cgroup = always
linux-cgroup-memory-limit = 1048576
linux-cgroup-processes-limit = 256
linux-cgroup-hard-fail = true')
	assert cfg.diagnostics.len == 0
	assert cfg.linux_cgroup == .always
	assert cfg.linux_cgroup_memory_limit or { 0 } == 1_048_576
	assert cfg.linux_cgroup_processes_limit or { 0 } == 256
	assert cfg.linux_cgroup_hard_fail
	formatted := cfg.format_config(true)
	assert formatted.contains('linux-cgroup = always\n')
	assert formatted.contains('linux-cgroup-memory-limit = 1048576\n')
	assert formatted.contains('linux-cgroup-processes-limit = 256\n')
	assert formatted.contains('linux-cgroup-hard-fail = true\n')

	cfg.load_string('linux-cgroup-memory-limit =\nlinux-cgroup-processes-limit =')
	assert cfg.linux_cgroup_memory_limit == none
	assert cfg.linux_cgroup_processes_limit == none
	cfg.load_string('linux-cgroup = sometimes')
	assert cfg.diagnostics.len == 1
}

fn test_open_path_helper_creates_file_without_truncating() ! {
	dir := os.join_path(os.temp_dir(), 'witty-edit-config-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'witty', 'config.witty')
	ensure_editable_config_path(path)!
	assert os.is_file(path)
	os.write_file(path, 'keep me')!
	ensure_editable_config_path(path)!
	assert os.read_file(path)! == 'keep me'
}

fn test_write_config_template_creates_parent_and_interpolates_path() ! {
	dir := os.join_path(os.temp_dir(), 'witty-config-template-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'witty', 'config.witty')
	write_config_template(path)!
	content := os.read_file(path)!
	assert content.contains('#   ${path}\n')
	assert !content.contains('{[path]s}')
	assert !content.contains('\nfont-family =')
}

fn test_load_optional_file_reports_source_actions() ! {
	dir := os.join_path(os.temp_dir(), 'witty-optional-config-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(dir)!
	missing := os.join_path(dir, 'missing')
	empty := os.join_path(dir, 'empty')
	os.write_file(empty, '')!
	mut cfg := Config.default_config()
	assert cfg.load_optional_file(missing) == .not_found
	assert cfg.load_optional_file(empty) == .error_
	assert cfg.load_optional_file(dir) == .loaded
}

fn test_load_file_returns_constrained_open_errors_without_diagnostics() ! {
	dir := os.join_path(os.temp_dir(), 'witty-load-file-error-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	missing := os.join_path(dir, 'missing')
	empty := os.join_path(dir, 'empty')
	os.write_file(empty, '')!

	mut cfg := Config.default_config()
	mut missing_kind := OpenFileError.file_open_failed
	cfg.load_file(missing) or {
		missing_kind = open_file_error_of(err) or { OpenFileError.file_open_failed }
	}
	assert missing_kind == .file_not_found
	mut empty_kind := OpenFileError.file_open_failed
	cfg.load_file(empty) or {
		empty_kind = open_file_error_of(err) or { OpenFileError.file_open_failed }
	}
	assert empty_kind == .file_is_empty
	assert cfg.diagnostics.len == 0
}

fn test_preferred_config_path_prefers_nonempty_then_existing() ! {
	dir := os.join_path(os.temp_dir(), 'witty-preferred-config-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(dir)!
	first := os.join_path(dir, 'first')
	second := os.join_path(dir, 'second')
	third := os.join_path(dir, 'third')

	assert preferred_existing_config_path([first, second, third])! == first
	os.write_file(first, '')!
	assert preferred_existing_config_path([first, second, third])! == first
	os.write_file(second, 'configured')!
	assert preferred_existing_config_path([first, second, third])! == second
	os.write_file(first, 'higher priority')!
	assert preferred_existing_config_path([first, second, third])! == first
}

fn test_packed_config_flag_layouts_match_source() {
	assert sizeof(FontShapingBreak) == 1
	assert FontShapingBreak{}.int_val() == 0x01
	assert FontShapingBreak.init(false).int_val() == 0
	assert sizeof(SplitPreserveZoom) == 1
	assert SplitPreserveZoom{}.int_val() == 0
	assert SplitPreserveZoom.init(true).int_val() == 0x01
	assert sizeof(ShellIntegrationFeatures) == 1
	assert ShellIntegrationFeatures{}.int_val() == 0x25
	assert ShellIntegrationFeatures.init(true, true, true, true, true, true).int_val() == 0x3f
	assert sizeof(BellFeatures) == 1
	assert BellFeatures{}.int_val() == 0x0c
	assert BellFeatures.init(true, true, true, true, true).int_val() == 0x1f
	assert sizeof(AppNotifications) == 1
	assert AppNotifications{}.int_val() == 0x03
	assert AppNotifications.init(false, true).int_val() == 0x02
	assert sizeof(ScrollToBottom) == 1
	assert ScrollToBottom{}.int_val() == 0x01
	assert ScrollToBottom.init(false, true).int_val() == 0x02
	assert sizeof(NotifyOnCommandFinishAction) == 1
	assert NotifyOnCommandFinishAction{}.int_val() == 0x01
	assert NotifyOnCommandFinishAction.init(false, true).int_val() == 0x02
}

fn test_bell_features_parse_format_and_defaults() {
	mut cfg := Config.default_config()
	assert !cfg.bell_features.system()
	assert !cfg.bell_features.audio()
	assert cfg.bell_features.attention()
	assert cfg.bell_features.title()
	assert !cfg.bell_features.border()

	cfg.load_string('bell-features = audio,no-attention,no-title,border')
	assert cfg.diagnostics.len == 0
	assert !cfg.bell_features.system()
	assert cfg.bell_features.audio()
	assert !cfg.bell_features.attention()
	assert !cfg.bell_features.title()
	assert cfg.bell_features.border()
	assert cfg.format_config(true).contains('bell-features = no-system,audio,no-attention,no-title,border\n')

	cfg.load_string('bell-features = true')
	assert cfg.bell_features.system()
	assert cfg.bell_features.audio()
	assert cfg.bell_features.attention()
	assert cfg.bell_features.title()
	assert cfg.bell_features.border()

	cfg.load_string('bell-features = sparkle')
	assert cfg.diagnostics.len == 1
}

fn test_bell_audio_parse_format_and_path_expansion() {
	base := os.join_path(os.temp_dir(), 'witty-config-bell-${os.getpid()}')
	os.rmdir_all(base) or {}
	os.mkdir_all(base)!
	defer {
		os.rmdir_all(base) or {}
	}
	mut cfg := Config.default_config()
	assert cfg.bell_audio_path == none
	assert cfg.bell_audio_volume == 0.5
	cfg.load_string('bell-audio-path = ?sounds/bell.oga\nbell-audio-volume = 0.75')
	assert cfg.diagnostics.len == 0
	assert cfg.bell_audio_path? == Path(PathOptional{ path: 'sounds/bell.oga' })
	assert cfg.bell_audio_volume == 0.75
	cfg.expand_paths(base)!
	assert cfg.bell_audio_path? == Path(PathOptional{
		path: os.join_path(base, 'sounds', 'bell.oga')
	})
	formatted := cfg.format_config(true)
	assert formatted.contains('bell-audio-path = ?${os.join_path(base, 'sounds', 'bell.oga')}\n')
	assert formatted.contains('bell-audio-volume = 0.75\n')

	cfg.load_string('bell-audio-path =\nbell-audio-volume = loud')
	assert cfg.bell_audio_path == none
	assert cfg.diagnostics.len == 1
}

fn test_window_title_config_parse_format_and_clear() {
	mut cfg := Config.default_config()
	cfg.load_string('window-title-font-family = Cantarell\nwindow-titlebar-background = #123456\nwindow-titlebar-foreground = aliceblue')
	assert cfg.diagnostics.len == 0
	assert cfg.window_title_font_family? == 'Cantarell'
	assert cfg.window_titlebar_background? == ColorRGB{18, 52, 86}
	assert cfg.window_titlebar_foreground? == ColorRGB{240, 248, 255}
	formatted := cfg.format_config(true)
	assert formatted.contains('window-title-font-family = Cantarell\n')
	assert formatted.contains('window-titlebar-background = #123456\n')
	assert formatted.contains('window-titlebar-foreground = #f0f8ff\n')

	cfg.load_string('window-title-font-family =\nwindow-titlebar-background =\nwindow-titlebar-foreground =')
	assert cfg.window_title_font_family == none
	assert cfg.window_titlebar_background == none
	assert cfg.window_titlebar_foreground == none
}

fn test_app_notifications_parse_format_and_defaults() {
	mut cfg := Config.default_config()
	assert cfg.app_notifications.clipboard_copy()
	assert cfg.app_notifications.config_reload()

	cfg.load_string('app-notifications = no-clipboard-copy,config-reload')
	assert cfg.diagnostics.len == 0
	assert !cfg.app_notifications.clipboard_copy()
	assert cfg.app_notifications.config_reload()
	assert cfg.format_config(true).contains('app-notifications = no-clipboard-copy,config-reload\n')

	cfg.load_string('app-notifications = false')
	assert !cfg.app_notifications.clipboard_copy()
	assert !cfg.app_notifications.config_reload()

	cfg.load_string('app-notifications = true')
	assert cfg.app_notifications.clipboard_copy()
	assert cfg.app_notifications.config_reload()

	cfg.load_string('app-notifications = sparkle')
	assert cfg.diagnostics.len == 1
}

fn test_notify_on_command_finish_action_and_after() {
	mut cfg := Config.default_config()
	assert cfg.notify_on_command_finish == .never
	assert cfg.notify_on_command_finish_action.bell()
	assert !cfg.notify_on_command_finish_action.notify()
	assert cfg.notify_on_command_finish_after == Duration{ duration: 5_000_000_000 }

	cfg.load_string('notify-on-command-finish = unfocused\nnotify-on-command-finish-action = no-bell,notify\nnotify-on-command-finish-after = 1m 250ms')
	assert cfg.diagnostics.len == 0
	assert cfg.notify_on_command_finish == .unfocused
	assert !cfg.notify_on_command_finish_action.bell()
	assert cfg.notify_on_command_finish_action.notify()
	assert cfg.notify_on_command_finish_after == Duration{ duration: 60_250_000_000 }
	formatted := cfg.format_config(true)
	assert formatted.contains('notify-on-command-finish-action = no-bell,notify\n')
	assert formatted.contains('notify-on-command-finish-after = 1m 250ms\n')

	cfg.load_string('notify-on-command-finish-action = false')
	assert !cfg.notify_on_command_finish_action.bell()
	assert !cfg.notify_on_command_finish_action.notify()
	cfg.load_string('notify-on-command-finish-action = true')
	assert cfg.notify_on_command_finish_action.bell()
	assert cfg.notify_on_command_finish_action.notify()

	cfg.load_string('notify-on-command-finish-action = sparkle\nnotify-on-command-finish-after = soon')
	assert cfg.diagnostics.len == 2
}

// --- WindowDecoration ---

// Config.zig: WindowDecoration "parse WindowDecoration"
fn test_parse_window_decoration() {
	assert WindowDecoration.parse_cli(none)! == .auto
	assert window_decoration_parse_cli('true')! == .auto
	assert window_decoration_parse_cli('false')! == .none_
	assert window_decoration_parse_cli('server')! == .server
	assert window_decoration_parse_cli('client')! == .client
	assert window_decoration_parse_cli('auto')! == .auto
	assert window_decoration_parse_cli('none')! == .none_

	window_decoration_parse_cli('') or {
		expect_parse_error(err, .invalid_value)
		window_decoration_parse_cli('aaaa') or {
			expect_parse_error(err, .invalid_value)
			return
		}
		assert false
		return
	}
	assert false, 'expected invalid_value for empty'
}

// --- Theme ---

// Config.zig: Theme "parse Theme"
fn test_parse_theme() {
	// Single
	single := theme_pair_parse_cli('foo')!
	assert single.light == 'foo'
	assert single.dark == 'foo'
	assert single.clone().format_entry() == 'foo'

	// Single whitespace
	single_ws := theme_pair_parse_cli('  foo  ')!
	assert single_ws.light == 'foo'
	assert single_ws.dark == 'foo'

	// Light/dark
	pair := theme_pair_parse_cli(' light:foo,  dark : bar  ')!
	assert pair.light == 'foo'
	assert pair.dark == 'bar'
	assert pair.format_entry() == 'light:foo,dark:bar'
	quoted := theme_pair_parse_cli('light:"foo,bar",dark:"baz\\nqux"')!
	assert quoted.light == 'foo,bar'
	assert quoted.dark == 'baz\nqux'
	mut parsed := ThemePair{}
	parsed.parse_cli('light:day,dark:night')!
	assert parsed.format_entry() == 'light:day,dark:night'
	mut invalid_config := Config.default_config()
	invalid_config.load_string('theme = light:foo\n')
	assert invalid_config.theme == none
	assert invalid_config.diagnostics.len == 1

	theme_pair_parse_cli(none) or {
		expect_parse_error(err, .value_required)
		theme_pair_parse_cli('') or {
			expect_parse_error(err, .value_required)
			theme_pair_parse_cli('light:foo') or {
				expect_parse_error(err, .invalid_value)
				theme_pair_parse_cli('dark:foo') or {
					expect_parse_error(err, .invalid_value)
					return
				}
				assert false
				return
			}
			assert false
			return
		}
		assert false
		return
	}
	assert false, 'expected value_required for null'
}

// ============================================================
// Top-level Config tests
// ============================================================

// Config.zig: "handle bom in config files"
fn test_handle_bom_in_config_files() {
	// With a UTF-8 BOM prefix.
	{
		mut cfg := Config.default_config()
		cfg.load_string('﻿abnormal-command-exit-runtime = 2500\n')
		cfg.finalize()!
		assert cfg.diagnostics.len == 0
		assert cfg.abnormal_command_exit_runtime == 2500
	}
	// Without a BOM prefix.
	{
		mut cfg := Config.default_config()
		cfg.load_string('abnormal-command-exit-runtime = 2500\n')
		cfg.finalize()!
		assert cfg.diagnostics.len == 0
		assert cfg.abnormal_command_exit_runtime == 2500
	}
}

fn test_config_file_whitespace_matches_source_byte_set() {
	mut cfg := Config.default_config()
	cfg.load_string('\vfont-size = 20\nenv = NAME=\vvalue\v\nfont-shaping-break = \vcursor')

	// LineIterator trims space, tab, and a trailing carriage return. The env
	// value's RepeatableStringMap parser additionally trims all ASCII whitespace.
	assert cfg.font_size == default_font_size
	assert cfg.env.entries == [StringMapEntry{
		key: 'NAME'
		value: 'value'
	}]
	assert cfg.font_shaping_break == FontShapingBreak{}
	assert cfg.diagnostics.len == 2

	assert parse_font_shaping_break(' \tcursor\t ')? == FontShapingBreak.init(true)
	assert parse_font_shaping_break('\vcursor') == none
}

fn test_config_file_bare_values_match_line_iterator() {
	mut cfg := Config.default_config()
	cfg.font_thicken = false
	cfg.background_blur = BackgroundBlurFalse{}
	cfg.window_decoration = .none_
	cfg.cursor_style_blink = none
	cfg.command_palette_entry.parse_cli('title:Example,action:new_window')!

	cfg.load_string('font-thicken\nbackground-blur\nwindow-decoration\ncursor-style-blink\ncommand-palette-entry\n')
	assert cfg.diagnostics.len == 0
	assert cfg.font_thicken
	assert cfg.background_blur is BackgroundBlurTrue
	assert cfg.window_decoration == .auto
	assert cfg.cursor_style_blink or { false }
	assert cfg.command_palette_entry.items.len == 0
	for step in cfg.replay_steps {
		if step is ReplayArg {
			assert !step.value.contains('=')
		}
	}
}

fn test_config_file_bare_required_and_unknown_values_are_diagnostics() {
	mut cfg := Config.default_config()
	cfg.load_string('font-size\nnot-a-real-option\n')
	assert cfg.font_size == default_font_size
	assert cfg.diagnostics.len == 2
	assert cfg.diagnostics[0].message.contains('value required')
	assert cfg.diagnostics[1].message.contains('unknown field')
}

fn test_config_file_surrounding_quotes_match_line_iterator() {
	mut cfg := Config.default_config()
	cfg.load_string('title =  "  spaced title  "  \n')
	assert cfg.diagnostics.len == 0
	assert cfg.title or { '' } == '  spaced title  '
}

fn test_cli_bare_values_match_reflected_parser() {
	mut cfg := Config.default_config()
	cfg.load_cli_args(['--font-thicken', '--background-blur', '--cursor-style-blink',
		'--background-blur-radius'])!
	assert cfg.diagnostics.len == 0
	assert cfg.font_thicken
	assert cfg.background_blur is BackgroundBlurTrue
	assert cfg.cursor_style_blink or { false }
}

fn test_config_file_bare_value_is_preserved_during_conditional_replay() {
	dir := os.join_path(os.temp_dir(), 'witty-bare-replay-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	light := os.join_path(dir, 'light')
	dark := os.join_path(dir, 'dark')
	os.write_file(light, 'background = #111111\n')!
	os.write_file(dark, 'background = #222222\n')!

	mut cfg := Config.default_config()
	cfg.load_string('theme = light:${light},dark:${dark}\nfont-thicken\n')
	cfg.finalize()!
	assert cfg.font_thicken
	dark_result := cfg.change_conditional_state(ConditionalState{ theme: .dark })!
	dark_cfg := dark_result.value or {
		panic('conditional theme was not marked relevant')
	}
	assert dark_cfg.font_thicken
	assert dark_cfg.background == ColorRGB{0x22, 0x22, 0x22}
}

// Config.zig: "clone default"
fn test_clone_default() {
	source := Config.default()
	dest := source.clone()
	// A cloned default should equal the source on representative fields.
	assert dest.font_size == source.font_size
	assert dest.background == source.background
	assert dest.foreground == source.foreground
	assert dest.term == source.term
	assert dest.abnormal_command_exit_runtime == source.abnormal_command_exit_runtime
	mut changes := source.change_iterator(&dest)
	assert changes.next() == none
}

fn test_clone_empty_and_shallow_clone() {
	mut source := Config.default()
	source.conditional_state.theme = .dark
	source.font_size = 42
	source.font_family = ['original']

	empty := source.clone_empty()
	assert empty.conditional_state.theme == .dark
	assert empty.font_size == default_font_size
	assert empty.font_family.len == 0

	mut shallow := source.shallow_clone()
	shallow.font_size = 24
	assert source.font_size == 42
	shallow.font_family[0] = 'shared'
	assert source.font_family[0] == 'shared'
}

// Config.zig: "changed"
fn test_config_changed_and_change_iterator() {
	source := Config.default_config()
	mut dest := source.clone()
	dest.font_thicken = true
	dest.window_width = 100

	assert source.changed(&dest, 'font-thicken')
	assert !source.changed(&dest, 'font-size')
	dest.link.links = []
	assert source.changed(&dest, 'link')
	mut it := source.change_iterator(&dest)
	mut keys := []string{}
	for key := it.next(); key != none; key = it.next() {
		keys << key or { break }
	}
	assert keys == ['font-thicken', 'link', 'window-width']

	mut lazy_dest := source.clone()
	mut lazy_it := source.change_iterator(&lazy_dest)
	lazy_dest.font_thicken = true
	lazy_key := lazy_it.next() or { '' }
	assert lazy_key == 'font-thicken'

	mut formatted_dest := source.clone()
	formatted_dest.font_feature = ['liga']
	formatted_dest.font_size += 1
	formatted := formatted_dest.format_config(true)
	feature_index := formatted.index('font-feature =') or { -1 }
	size_index := formatted.index('font-size =') or { -1 }
	assert feature_index >= 0
	assert feature_index < size_index
}

// Config.zig: "clone preserves conditional state"
fn test_clone_preserves_conditional_state() {
	mut a := Config.default_config()
	a.conditional_state = ConditionalState{
		theme: .dark
	}
	assert a.conditional_state.theme == .dark
	dest := a.clone()
	assert dest.conditional_state.theme == .dark
}

fn test_conditional_enum_match() {
	state := ConditionalState{
		theme: .dark
		os: .linux
	}
	assert state.match(Conditional{
		key: .theme
		op: .eq
		value: 'dark'
	})
	assert !state.match(Conditional{
		key: .theme
		op: .ne
		value: 'dark'
	})
	assert state.match(Conditional{
		key: .theme
		op: .ne
		value: 'light'
	})
	assert state.match(Conditional{
		key: .os
		op: .eq
		value: 'linux'
	})
	assert Conditional{
		key: .os
		op: .ne
		value: 'macos'
	}.clone() == Conditional{
		key: .os
		op: .ne
		value: 'macos'
	}
	assert ConditionalState{}.os == current_target_os()
}

fn test_conditional_replay_requires_every_condition_to_match() {
	mut destination := Config.default_config()
	destination.conditional_state = ConditionalState{
		theme: .dark
		os: .linux
	}
	replay_steps_into(mut destination, [
		ReplayStep(ReplayConditionalArg{
			conditions: [
				Conditional{ key: .theme, op: .eq, value: 'dark' },
				Conditional{ key: .os, op: .eq, value: 'linux' },
			]
			arg: '--font-size=19'
		}),
		ReplayStep(ReplayConditionalArg{
			conditions: [
				Conditional{ key: .theme, op: .eq, value: 'dark' },
				Conditional{ key: .os, op: .ne, value: 'linux' },
			]
			arg: '--font-thicken=true'
		}),
	])
	assert destination.font_size == 19
	assert !destination.font_thicken
}

// Config.zig: "changeConditionalState ignores irrelevant changes"
fn test_change_conditional_state_ignores_irrelevant() {
	mut cfg := Config.default_config()
	cfg.load_string('theme = foo\n')
	cfg.finalize()!

	// A single (non light/dark) theme is not conditional.
	result := cfg.change_conditional_state(ConditionalState{ theme: .dark })!
	if _ := result.value {
		assert false, 'expected none for irrelevant change'
	}
}

// Config.zig: "changeConditionalState applies relevant changes"
fn test_change_conditional_state_applies_relevant() {
	mut cfg := Config.default_config()
	cfg.load_string('theme = light:foo,dark:bar\n')
	cfg.finalize()!

	result := cfg.change_conditional_state(ConditionalState{ theme: .dark })!
	cfg2 := result.value or {
		assert false, 'expected a config for relevant change'
		return
	}
	assert 'theme' in cfg2.conditional_set
}

fn test_change_conditional_state_ignores_unchanged_relevant_value() {
	mut cfg := Config.default_config()
	cfg.load_string('theme = light:foo,dark:bar\n')
	cfg.finalize()!

	result := cfg.change_conditional_state(cfg.conditional_state)!
	if _ := result.value {
		assert false, 'expected none when conditional state is unchanged'
	}
}

// Config.zig: "theme loading"
fn test_theme_loading() {
	dir := os.join_path(os.temp_dir(), 'witty-theme-load-${os.getpid()}')
	os.mkdir_all(dir) or {}
	path := os.join_path(dir, 'theme')
	os.write_file(path, 'background = #123ABC\n')!
	defer {
		os.rmdir_all(dir) or {}
	}

	mut cfg := Config.default_config()
	cfg.load_string('theme = ${path}\n')
	cfg.finalize()!

	assert cfg.background == ColorRGB{0x12, 0x3A, 0xBC}
	// Not a conditional theme.
	assert 'theme' !in cfg.conditional_set
}

fn test_theme_loading_resolves_user_theme_name() {
	dir := os.join_path(os.temp_dir(), 'witty-theme-name-${os.getpid()}')
	theme_dir := os.join_path(dir, 'witty', 'themes')
	os.rmdir_all(dir) or {}
	os.mkdir_all(theme_dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	old_xdg := os.getenv_opt('XDG_CONFIG_HOME')
	os.setenv('XDG_CONFIG_HOME', dir, true)
	defer {
		if value := old_xdg {
			os.setenv('XDG_CONFIG_HOME', value, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
	}
	os.write_file(os.join_path(theme_dir, 'named-theme'), 'background = #123456\ncustom-shader = shader.glsl\n')!
	mut cfg := Config.default_config()
	cfg.load_string('theme = named-theme\n')
	cfg.finalize()!
	assert cfg.background == ColorRGB{0x12, 0x34, 0x56}
	assert cfg.custom_shader.items == [
		Path(PathRequired{ path: 'shader.glsl' }),
	]
	assert cfg.diagnostics.len == 0
}

fn test_theme_diagnostic_retains_file_location() ! {
	path := os.join_path(os.temp_dir(), 'witty-theme-diagnostic-${os.getpid()}')
	os.write_file(path, 'font-size = nope\n')!
	defer {
		os.rm(path) or {}
	}

	mut cfg := Config.default_config()
	cfg.load_string('theme = ${path}\n')
	cfg.finalize()!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == '${path}:1:font-size: invalid value "nope"'
}

fn test_theme_rejects_relative_path_with_separator() {
	mut cfg := Config.default_config()
	cfg.load_string('theme = nested/theme\n')
	cfg.finalize()!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].message.contains('cannot include path separators')
}

// Config.zig: "theme priority is lower than config"
fn test_theme_priority_lower_than_config() {
	dir := os.join_path(os.temp_dir(), 'witty-theme-prio-${os.getpid()}')
	os.mkdir_all(dir) or {}
	path := os.join_path(dir, 'theme')
	os.write_file(path, 'background = #123ABC\n')!
	defer {
		os.rmdir_all(dir) or {}
	}

	mut cfg := Config.default_config()
	// Config sets background explicitly; theme must not override it.
	cfg.load_string('background = #ABCDEF\ntheme = ${path}\n')
	cfg.finalize()!

	assert cfg.background == ColorRGB{0xAB, 0xCD, 0xEF}
}

fn test_theme_replay_preserves_all_user_overrides_and_repeatables() {
	dir := os.join_path(os.temp_dir(), 'witty-theme-replay-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	theme_path := os.join_path(dir, 'theme')
	config_path := os.join_path(dir, 'config')
	os.write_file(theme_path, '
font-size = 9
cursor-color = #010203
palette = 1=#111111
font-family = Theme Font
custom-shader = theme.glsl
keybind = ctrl+a=new_window
config-file = ignored.conf
')!
	os.write_file(config_path, '
theme = ${theme_path}
font-size = 17
cursor-color = #AABBCC
palette = 2=#222222
font-family = User Font
custom-shader = user.glsl
keybind = ctrl+b=new_tab
')!

	mut cfg := Config.default_config()
	cfg.load_file(config_path)!
	cfg.finalize()!

	assert cfg.font_size == 17
	cursor_color := cfg.cursor_color or { panic('missing cursor color') }
	assert cursor_color is TerminalColorColor
	assert (cursor_color as TerminalColorColor).color == ColorRGB{0xAA, 0xBB, 0xCC}
	assert cfg.palette.value[1] == ColorRGB{0x11, 0x11, 0x11}
	assert cfg.palette.value[2] == ColorRGB{0x22, 0x22, 0x22}
	assert cfg.font_family == ['Theme Font', 'User Font']
	assert cfg.custom_shader.items == [
		Path(PathRequired{ path: os.join_path(dir, 'theme.glsl') }),
		Path(PathRequired{ path: os.join_path(dir, 'user.glsl') }),
	]
	assert cfg.config_file.items == [Path(PathRequired{ path: os.join_path(dir, 'ignored.conf') })]
	assert (cfg.keybind.set.get(input.Trigger.parse('ctrl+a')!) or {
		panic('theme keybind was not retained')
	}.value as input.Leaf).action.tag() == .new_window
	assert (cfg.keybind.set.get(input.Trigger.parse('ctrl+b')!) or {
		panic('user keybind was not retained')
	}.value as input.Leaf).action.tag() == .new_tab
	assert cfg.diagnostics.len == 0
}

fn test_conditional_theme_replay_replaces_theme_repeatables() {
	dir := os.join_path(os.temp_dir(), 'witty-theme-replay-conditional-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	light := os.join_path(dir, 'light')
	dark := os.join_path(dir, 'dark')
	os.write_file(light, 'font-family = Light Font\ncustom-shader = light.glsl\n')!
	os.write_file(dark, 'font-family = Dark Font\ncustom-shader = dark.glsl\n')!

	mut cfg := Config.default_config()
	cfg.load_string('theme = light:${light},dark:${dark}\nfont-family = User Font\ncustom-shader = user.glsl\n')
	cfg.finalize()!
	assert cfg.font_family == ['Light Font', 'User Font']
	mut saw_light_theme_step := false
	for step in cfg.replay_steps {
		if step is ReplayConditionalArg && step.arg == '--font-family=Light Font' {
			saw_light_theme_step = true
			assert step.conditions == [Conditional{
				key: .theme
				op: .eq
				value: 'light'
			}]
		}
	}
	assert saw_light_theme_step
	assert cfg.custom_shader.items == [
		Path(PathRequired{ path: 'light.glsl' }),
		Path(PathRequired{ path: 'user.glsl' }),
	]

	dark_result := cfg.change_conditional_state(ConditionalState{ theme: .dark })!
	dark_cfg := dark_result.value or {
		panic('conditional theme was not marked relevant')
	}
	assert dark_cfg.font_family == ['Dark Font', 'User Font']
	mut saw_dark_theme_step := false
	for step in dark_cfg.replay_steps {
		if step is ReplayConditionalArg && step.arg == '--font-family=Dark Font' {
			saw_dark_theme_step = true
			assert step.conditions == [Conditional{
				key: .theme
				op: .eq
				value: 'dark'
			}]
		}
		match step {
			ReplayArg { assert step.value != '--font-family=Light Font' }
			ReplayConditionalArg { assert step.arg != '--font-family=Light Font' }
			else {}
		}
	}
	assert saw_dark_theme_step
	assert dark_cfg.custom_shader.items == [
		Path(PathRequired{ path: 'dark.glsl' }),
		Path(PathRequired{ path: 'user.glsl' }),
	]
}

// Config.zig: "theme loading correct light/dark"
fn test_theme_loading_correct_light_dark() {
	dir := os.join_path(os.temp_dir(), 'witty-theme-ld-${os.getpid()}')
	os.mkdir_all(dir) or {}
	light := os.join_path(dir, 'theme_light')
	dark := os.join_path(dir, 'theme_dark')
	os.write_file(light, 'background = #FFFFFF\n')!
	os.write_file(dark, 'background = #EEEEEE\n')!
	defer {
		os.rmdir_all(dir) or {}
	}

	theme_line := 'theme = light:${light},dark:${dark}\n'

	// Light
	{
		mut cfg := Config.default_config()
		cfg.load_string(theme_line)
		cfg.finalize()!
		assert cfg.background == ColorRGB{0xFF, 0xFF, 0xFF}
	}
	// Dark (via conditional state)
	{
		mut cfg := Config.default_config()
		cfg.conditional_state = ConditionalState{
			theme: .dark
		}
		cfg.load_string(theme_line)
		cfg.finalize()!
		assert cfg.background == ColorRGB{0xEE, 0xEE, 0xEE}
	}
	// Light to Dark (via changeConditionalState)
	{
		mut cfg := Config.default_config()
		cfg.load_string(theme_line)
		cfg.finalize()!
		result := cfg.change_conditional_state(ConditionalState{ theme: .dark })!
		newc := result.value or {
			assert false
			return
		}
		assert newc.background == ColorRGB{0xEE, 0xEE, 0xEE}
	}
}

// Config.zig: "theme specifying light/dark changes window-theme from auto"
fn test_theme_light_dark_changes_window_theme() {
	mut cfg := Config.default_config()
	cfg.load_string('theme = light:foo,dark:bar\nwindow-theme = auto\n')
	cfg.finalize()!
	assert cfg.window_theme == .system
}

// Config.zig: "theme specifying light/dark sets theme usage in conditional state"
fn test_theme_light_dark_sets_conditional() {
	mut cfg := Config.default_config()
	cfg.load_string('theme = light:foo,dark:bar\nwindow-theme = auto\n')
	cfg.finalize()!
	assert cfg.window_theme == .system
	assert 'theme' in cfg.conditional_set
}

fn test_compat_renamed_config_fields() {
	mut cfg := Config.default_config()
	cfg.load_string('background-blur-radius = 17\n')
	assert cfg.diagnostics.len == 0
	assert cfg.background_blur is BackgroundBlurRadius
	assert (cfg.background_blur as BackgroundBlurRadius).radius == 17

	// The generic renamed-field handler applies the destination field's
	// declared default for an explicitly empty value.
	cfg.load_string('background-blur-radius =\n')
	assert cfg.background_blur is BackgroundBlurFalse
}

fn test_compat_removed_bool_invalid_value_is_not_silently_accepted() {
	mut cfg := Config.default_config()
	cfg.load_string('cursor-invert-fg-bg = maybe\nselection-invert-fg-bg = maybe\nbold-is-bright = maybe\n')
	assert cfg.diagnostics.len == 3
	assert cfg.diagnostics.all(it.message == 'unknown field')
	assert cfg.diagnostics.map(it.key) == ['cursor-invert-fg-bg', 'selection-invert-fg-bg',
		'bold-is-bright']
}

// Config.zig: "compatibility: removed cursor-invert-fg-bg"
fn test_compat_removed_cursor_invert_fg_bg() {
	mut cfg := Config.default_config()
	cfg.load_string('cursor-invert-fg-bg = true\n')
	cfg.finalize()!
	cursor_color := cfg.cursor_color or { panic('missing cursor color') }
	cursor_text := cfg.cursor_text or { panic('missing cursor text') }
	assert cursor_color is TerminalColorCellForeground
	assert cursor_text is TerminalColorCellBackground
}

// Config.zig: "compatibility: removed selection-invert-fg-bg"
fn test_compat_removed_selection_invert_fg_bg() {
	mut cfg := Config.default_config()
	cfg.load_string('selection-invert-fg-bg = true\n')
	cfg.finalize()!
	selection_foreground := cfg.selection_foreground or { panic('missing selection foreground') }
	selection_background := cfg.selection_background or { panic('missing selection background') }
	assert selection_foreground is TerminalColorCellBackground
	assert selection_background is TerminalColorCellForeground
}

fn test_terminal_color_config_fields() {
	mut cfg := Config.default_config()
	assert (cfg.search_foreground as TerminalColorColor).color == ColorRGB{0, 0, 0}
	assert (cfg.search_background as TerminalColorColor).color == ColorRGB{0xff, 0xe0, 0x82}
	assert (cfg.search_selected_foreground as TerminalColorColor).color == ColorRGB{0, 0, 0}
	assert (cfg.search_selected_background as TerminalColorColor).color == ColorRGB{0xf2, 0xa5, 0x7e}

	cfg.load_string('cursor-color = #4e2a84\ncursor-text = cell-background\nselection-background = cell-foreground\nsearch-background = #010203\n')
	cursor_color := cfg.cursor_color or { panic('missing cursor color') }
	cursor_text := cfg.cursor_text or { panic('missing cursor text') }
	selection_background := cfg.selection_background or { panic('missing selection background') }
	assert cursor_color is TerminalColorColor
	assert (cursor_color as TerminalColorColor).color == ColorRGB{78, 42, 132}
	assert cursor_text is TerminalColorCellBackground
	assert selection_background is TerminalColorCellForeground
	assert (cfg.search_background as TerminalColorColor).color == ColorRGB{1, 2, 3}
	assert cfg.diagnostics.len == 0

	cfg.load_string('cursor-color =\nselection-background =\n')
	assert cfg.cursor_color == none
	assert cfg.selection_background == none
}

// Config.zig: "compatibility: removed bold-is-bright"
fn test_compat_removed_bold_is_bright() {
	mut cfg := Config.default_config()
	cfg.load_string('bold-is-bright = true\n')
	cfg.finalize()!
	bc := cfg.bold_color or {
		assert false, 'expected bold_color to be set'
		return
	}
	assert bc is BoldColorBright
}

// Config.zig: "compatibility: window new-window"
fn test_compat_window_new_window() {
	mut cfg := Config.default_config()
	cfg.load_string('macos-dock-drop-behavior = window\n')
	cfg.finalize()!
	assert cfg.macos_dock_drop_behavior == .new_window
}

// --- Keybinds ---
// Translations of Config.zig's `Keybinds` tests.

// Config.zig: Keybinds "parseCLI"
fn test_keybinds_parse_cli() {
	mut set := Keybinds{}
	set.parse_cli('shift+a=copy_to_clipboard')!
	set.parse_cli('shift+a=csi:hello')!
	// Same trigger, so the second overwrites the first.
	assert set.set.bindings.len == 1
}

// Config.zig: Keybinds "formatConfig single"
fn test_keybinds_format_config_single() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('shift+a=csi:hello')!
	assert format_entry('a', keybinds) == 'a = shift+a=csi:hello\n'
}

// Config.zig: Keybinds "formatConfig multiple items"
fn test_keybinds_format_config_multiple_items() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('ctrl+z>1=goto_tab:1')!
	keybinds.parse_cli('ctrl+z>2=goto_tab:2')!
	assert format_entry('keybind', keybinds) == 'keybind = ctrl+z>1=goto_tab:1\nkeybind = ctrl+z>2=goto_tab:2\n'
}

// Config.zig: Keybinds "formatConfig multiple items nested"
fn test_keybinds_format_config_multiple_items_nested() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('ctrl+a>ctrl+b>n=new_window')!
	keybinds.parse_cli('ctrl+a>ctrl+b>w=close_window')!
	keybinds.parse_cli('ctrl+a>ctrl+c>t=new_tab')!
	keybinds.parse_cli('ctrl+b>ctrl+d>a=previous_tab')!
	assert format_entry('a', keybinds) == 'a = ctrl+a>ctrl+b>n=new_window\na = ctrl+a>ctrl+b>w=close_window\na = ctrl+a>ctrl+c>t=new_tab\na = ctrl+b>ctrl+d>a=previous_tab\n'
}

// Config.zig: Keybinds "parseCLI table definition"
fn test_keybinds_parse_cli_table_definition() {
	mut keybinds := Keybinds{}

	// Define a table by adding a binding to it.
	keybinds.parse_cli('foo/shift+a=copy_to_clipboard')!
	assert keybinds.tables.len == 1
	assert 'foo' in keybinds.tables

	table := keybinds.tables['foo'] or { panic('missing table') }
	assert table.bindings.len == 1
}

// Config.zig: Keybinds "parseCLI table clear"
fn test_keybinds_parse_cli_table_clear() {
	mut keybinds := Keybinds{}

	keybinds.parse_cli('foo/shift+a=copy_to_clipboard')!
	assert keybinds.tables['foo']!.bindings.len == 1

	// Clear the table with "foo/".
	keybinds.parse_cli('foo/')!
	assert keybinds.tables['foo']!.bindings.len == 0
}

// Config.zig: Keybinds "parseCLI table multiple bindings"
fn test_keybinds_parse_cli_table_multiple_bindings() {
	mut keybinds := Keybinds{}

	keybinds.parse_cli('foo/shift+a=copy_to_clipboard')!
	keybinds.parse_cli('foo/shift+b=paste_from_clipboard')!
	keybinds.parse_cli('bar/ctrl+c=close_window')!

	assert keybinds.tables.len == 2
	assert keybinds.tables['foo']!.bindings.len == 2
	assert keybinds.tables['bar']!.bindings.len == 1
}

// Config.zig: Keybinds "parseCLI table does not affect root set"
fn test_keybinds_parse_cli_table_does_not_affect_root_set() {
	mut keybinds := Keybinds{}

	keybinds.parse_cli('shift+a=copy_to_clipboard')!
	keybinds.parse_cli('foo/shift+b=paste_from_clipboard')!

	// Root set should have the first binding.
	assert keybinds.set.bindings.len == 1
	// Table should have the second binding.
	assert keybinds.tables['foo']!.bindings.len == 1
}

// Config.zig: Keybinds "parseCLI table empty name is invalid"
fn test_keybinds_parse_cli_table_empty_name_is_invalid() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('/shift+a=copy_to_clipboard') or {
		assert err.msg() == 'InvalidFormat'
		return
	}
	assert false, 'expected an error'
}

// Config.zig: Keybinds "parseCLI table with key sequence"
fn test_keybinds_parse_cli_table_with_key_sequence() {
	mut keybinds := Keybinds{}

	// Key sequences should work within tables.
	keybinds.parse_cli('foo/ctrl+a>ctrl+b=new_window')!

	table := keybinds.tables['foo'] or { panic('missing table') }
	assert table.bindings.len == 1
}

// Config.zig: Keybinds "parseCLI slash in action argument is not a table"
fn test_keybinds_parse_cli_slash_in_action_argument_is_not_a_table() {
	mut keybinds := Keybinds{}

	// A slash after the = should not be interpreted as a table delimiter.
	keybinds.parse_cli('ctrl+a=text:/hello')!

	// Should be in root set, not a table.
	assert keybinds.set.bindings.len == 1
	assert keybinds.tables.len == 0
}

// Config.zig: Keybinds "parseCLI slash as key with modifier is not a table"
fn test_keybinds_parse_cli_slash_as_key_with_modifier_is_not_a_table() {
	mut keybinds := Keybinds{}

	// ctrl+/ should be parsed as a keybind with '/' as the key, not a table.
	keybinds.parse_cli('ctrl+/=text:foo')!

	assert keybinds.set.bindings.len == 1
	assert keybinds.tables.len == 0
}

// Config.zig: Keybinds "parseCLI shift+slash as key is not a table"
fn test_keybinds_parse_cli_shift_slash_as_key_is_not_a_table() {
	mut keybinds := Keybinds{}

	// shift+/ should be parsed as a keybind, not a table.
	keybinds.parse_cli('shift+/=ignore')!

	assert keybinds.set.bindings.len == 1
	assert keybinds.tables.len == 0
}

// Config.zig: Keybinds "parseCLI bare slash as key is not a table"
fn test_keybinds_parse_cli_bare_slash_as_key_is_not_a_table() {
	mut keybinds := Keybinds{}

	// Bare / as a key should work (empty table name is rejected).
	keybinds.parse_cli('/=text:foo')!

	assert keybinds.set.bindings.len == 1
	assert keybinds.tables.len == 0
}

// Config.zig: Keybinds "parseCLI slash in key sequence is not a table"
fn test_keybinds_parse_cli_slash_in_key_sequence_is_not_a_table() {
	mut keybinds := Keybinds{}

	// Key sequence ending with / should work.
	keybinds.parse_cli('ctrl+a>ctrl+/=new_window')!

	assert keybinds.set.bindings.len == 1
	assert keybinds.tables.len == 0
}

// Config.zig: Keybinds "parseCLI table with slash in binding"
fn test_keybinds_parse_cli_table_with_slash_in_binding() {
	mut keybinds := Keybinds{}

	// Table with a binding that uses / as the key.
	keybinds.parse_cli('mytable//=text:foo')!

	assert keybinds.set.bindings.len == 0
	assert keybinds.tables.len == 1
	assert 'mytable' in keybinds.tables
	assert keybinds.tables['mytable']!.bindings.len == 1
}

// Config.zig: Keybinds "parseCLI table with sequence containing slash"
fn test_keybinds_parse_cli_table_with_sequence_containing_slash() {
	mut keybinds := Keybinds{}

	// Table with a key sequence that ends with /.
	keybinds.parse_cli('mytable/a>/=new_window')!

	assert keybinds.set.bindings.len == 0
	assert keybinds.tables.len == 1
	assert 'mytable' in keybinds.tables
}

// Config.zig: Keybinds "clone with tables"
fn test_keybinds_clone_with_tables() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('shift+a=copy_to_clipboard')!
	keybinds.parse_cli('foo/shift+b=paste_from_clipboard')!
	keybinds.parse_cli('bar/ctrl+c=close_window')!

	cloned := keybinds.clone()

	// Verify the clone has the same structure.
	assert cloned.set.bindings.len == keybinds.set.bindings.len
	assert cloned.tables.len == keybinds.tables.len
	assert cloned.tables['foo']!.bindings.len == keybinds.tables['foo']!.bindings.len
	assert cloned.tables['bar']!.bindings.len == keybinds.tables['bar']!.bindings.len
}

// Config.zig: Keybinds "equal with tables"
fn test_keybinds_equal_with_tables() {
	mut keybinds1 := Keybinds{}
	keybinds1.parse_cli('foo/shift+a=copy_to_clipboard')!

	mut keybinds2 := Keybinds{}
	keybinds2.parse_cli('foo/shift+a=copy_to_clipboard')!

	assert keybinds1.equal(keybinds2)
}

// Config.zig: Keybinds "equal with tables different table count"
fn test_keybinds_equal_with_tables_different_table_count() {
	mut keybinds1 := Keybinds{}
	keybinds1.parse_cli('foo/shift+a=copy_to_clipboard')!

	mut keybinds2 := Keybinds{}
	keybinds2.parse_cli('foo/shift+a=copy_to_clipboard')!
	keybinds2.parse_cli('bar/shift+b=paste_from_clipboard')!

	assert !keybinds1.equal(keybinds2)
}

// Config.zig: Keybinds "equal with tables different table names"
fn test_keybinds_equal_with_tables_different_table_names() {
	mut keybinds1 := Keybinds{}
	keybinds1.parse_cli('foo/shift+a=copy_to_clipboard')!

	mut keybinds2 := Keybinds{}
	keybinds2.parse_cli('bar/shift+a=copy_to_clipboard')!

	assert !keybinds1.equal(keybinds2)
}

// Config.zig: Keybinds "equal with tables different bindings"
fn test_keybinds_equal_with_tables_different_bindings() {
	mut keybinds1 := Keybinds{}
	keybinds1.parse_cli('foo/shift+a=copy_to_clipboard')!

	mut keybinds2 := Keybinds{}
	keybinds2.parse_cli('foo/shift+b=paste_from_clipboard')!

	assert !keybinds1.equal(keybinds2)
}

// Config.zig: Keybinds "formatEntry with tables"
fn test_keybinds_format_entry_with_tables() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('foo/shift+a=csi:hello')!
	assert format_entry('keybind', keybinds) == 'keybind = foo/shift+a=csi:hello\n'
}

// Config.zig: Keybinds "formatEntry with tables and root set"
fn test_keybinds_format_entry_with_tables_and_root_set() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('shift+b=csi:world')!
	keybinds.parse_cli('foo/shift+a=csi:hello')!
	output := format_entry('keybind', keybinds)
	assert output.contains('keybind = shift+b=csi:world\n')
	assert output.contains('keybind = foo/shift+a=csi:hello\n')
}

// Config.zig: Keybinds "parseCLI clear clears tables"
fn test_keybinds_parse_cli_clear_clears_tables() {
	mut keybinds := Keybinds{}

	// Add bindings to root set and tables.
	keybinds.parse_cli('shift+a=copy_to_clipboard')!
	keybinds.parse_cli('foo/shift+b=paste_from_clipboard')!
	keybinds.parse_cli('bar/ctrl+c=close_window')!

	assert keybinds.set.bindings.len == 1
	assert keybinds.tables.len == 2

	// Clear all keybinds.
	keybinds.parse_cli('clear')!

	// Both root set and tables should be cleared.
	assert keybinds.set.bindings.len == 0
	assert keybinds.tables.len == 0
}

// Config.zig: Keybinds "parseCLI reset clears tables"
fn test_keybinds_parse_cli_reset_clears_tables() {
	mut keybinds := Keybinds{}

	// Add bindings to tables.
	keybinds.parse_cli('foo/shift+a=copy_to_clipboard')!
	keybinds.parse_cli('bar/shift+b=paste_from_clipboard')!

	assert keybinds.tables.len == 2

	// Reset to defaults (empty value).
	keybinds.parse_cli('')!

	// Tables should be cleared, root set has defaults.
	assert keybinds.tables.len == 0
	assert keybinds.set.bindings.len > 0
}

// Verify config defaults match ghostty's src/config/Config.zig declared defaults.
fn test_default_values_match_ghostty() {
	mut cfg := Config.default_config()
	// @"font-size": f32 = 13 on macOS and 12 everywhere else.
	$if macos {
		assert cfg.font_size == 13
	} $else {
		assert cfg.font_size == 12
	}

	// background: Color = .{ .r = 0x28, .g = 0x2C, .b = 0x34 }
	assert cfg.background == ColorRGB{
		r: 0x28
		g: 0x2C
		b: 0x34
	}
	// foreground: Color = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }
	assert cfg.foreground == ColorRGB{
		r: 0xFF
		g: 0xFF
		b: 0xFF
	}
	// term: []const u8 = "xterm-witty"
	assert cfg.term == 'xterm-witty'
	// @"title-report": bool = false
	assert cfg.title_report == false
	// @"mouse-hide-while-typing": bool = false
	assert cfg.mouse_hide_while_typing == false
	// @"selection-clear-on-copy": bool = false
	assert cfg.selection_clear_on_copy == false
	// @"selection-clear-on-typing": bool = true
	assert cfg.selection_clear_on_typing == true
	// @"cursor-click-to-move": bool = true
	assert cfg.cursor_click_to_move == true
	// @"clipboard-trim-trailing-spaces": bool = true
	assert cfg.clipboard_trim_trailing_spaces == true
	// @"font-thicken-strength": u8 = 255
	assert cfg.font_thicken_strength == 255
	// @"minimum-contrast": f64 = 1
	assert cfg.minimum_contrast == 1.0

	// Empty term falls back to xterm-witty in finalize.
	mut cfg2 := Config.default_config()
	cfg2.term = ''
	cfg2.finalize()!
	assert cfg2.term == 'xterm-witty'
}

fn test_finalize_translates_inherit_working_directory_and_preserves_unclamped_opacities() {
	mut cfg := Config.default_config()
	cfg.working_directory = 'inherit'
	cfg.background_opacity = 2
	cfg.cursor_opacity = -1
	cfg.faint_opacity = 2
	cfg.finalize()!
	assert cfg.working_directory == none
	assert cfg.background_opacity == 2
	assert cfg.cursor_opacity == -1
	assert cfg.faint_opacity == 1
}

fn test_probable_cli_environment_uses_term_program() {
	previous := os.getenv_opt('TERM_PROGRAM')
	os.setenv('TERM_PROGRAM', 'witty-test', true)
	defer {
		if value := previous {
			os.setenv('TERM_PROGRAM', value, true)
		} else {
			os.unsetenv('TERM_PROGRAM')
		}
	}
	assert probable_cli_environment()
}

fn test_default_config_initializes_complete_darwin_keybinds() {
	cfg := Config.default_config()
	$if macos {
		assert cfg.keybind.set.bindings.len == 93

		quit := cfg.keybind.set.get(input.Trigger{
			key: input.TriggerKeyUnicode{ codepoint: u32(`q`) }
			mods: input.Mods.init(false, false, false, true, false, false, input.SideInfo{})
		}) or { panic('missing default quit binding') }
		assert (quit.value as input.Leaf).action.tag() == .quit

		resize := cfg.keybind.set.get(input.Trigger{
			key: input.TriggerKeyPhysical{ key: .arrow_left }
			mods: input.Mods.init(false, true, false, true, false, false, input.SideInfo{})
		}) or { panic('missing default split resize binding') }
		assert (resize.value as input.Leaf).action == input.Action(input.ActionResizeSplit{ value: input.SplitResizeParameter{ direction: .left, amount: 10 } })

		natural := cfg.keybind.set.get(input.Trigger{
			key: input.TriggerKeyPhysical{ key: .arrow_right }
			mods: input.Mods.init(false, false, true, false, false, false, input.SideInfo{})
		}) or { panic('missing natural text editing binding') }
		assert (natural.value as input.Leaf).action == input.Action(input.ActionEsc{ value: 'f' })
	} $else {
		assert cfg.keybind.set.bindings.len > 60
	}
}

fn test_default_config_initializes_url_link() {
	mut cfg := Config.default_config()
	assert cfg.link.links.len == 1
	link := cfg.link.links[0]
	assert link.regex == default_url_pattern
	assert link.action == .open
	assert link.highlight is input.LinkHighlightHoverMods
	assert (link.highlight as input.LinkHighlightHoverMods).mods == input.ctrl_or_super_mods(input.Mods{})
	assert cfg.link.format_entry().len == 0
	assert cfg.link.equal(cfg.link.clone())
	assert !cfg.format_config(false).split_into_lines().any(it.starts_with('link ='))
	mut custom := RepeatableLink{}
	custom.parse_cli('regex:foo') or { assert err.msg() == 'not implemented' }

	clone := cfg.clone()
	cfg.link.links << input.Link{
		regex: 'issue-[0-9]+'
		action: .open
		highlight: input.LinkHighlightAlways{}
	}
	assert clone.link.links.len == 1

	cfg.link_url = false
	cfg.finalize()!
	assert cfg.link.links.len == 1
	assert cfg.link.links[0].regex == 'issue-[0-9]+'
}

fn test_selection_word_chars_defaults_and_parse() {
	mut chars := SelectionWordChars.defaults()
	assert chars.codepoints[0] == 0
	assert u32(`;`) in chars.codepoints
	assert u32(0x2502) in chars.codepoints

	chars.parse_cli('._')!
	assert chars.codepoints == [u32(0), u32(`.`), u32(`_`)]
	assert chars.format_entry() == '._'
	assert SelectionWordChars{
		codepoints: [u32(0), u32(`a`), u32(0xd800), u32(`b`)]
	}.format_entry() == 'ab'
}

fn test_clipboard_codepoint_map_parse() {
	mut mappings := RepeatableClipboardCodepointMap{}
	mappings.parse_cli('U+2500=U+002D')!
	mappings.parse_cli('U+0001 - U+0005, U+03A3=SUM')!
	mappings.parse_cli('U+0010=U+0__02D')!
	mappings.parse_cli('U+0011=U++02D')!
	mappings.parse_cli('U+0012=U+-0')!
	assert mappings.map.list.len == 6
	assert mappings.map.list[0].range_start == 0x2500
	assert mappings.map.list[0].range_end == 0x2500
	match mappings.map.list[0].replacement {
		terminal.CodepointRepl {
			assert mappings.map.list[0].replacement.codepoint == u32(`-`)
		}
		terminal.StringRepl {
			assert false, 'expected codepoint replacement'
		}
	}
	assert mappings.map.list[1].range_start == 1
	assert mappings.map.list[1].range_end == 5
	match mappings.map.list[2].replacement {
		terminal.StringRepl {
			assert mappings.map.list[2].replacement.str == 'SUM'
		}
		terminal.CodepointRepl {
			assert false, 'expected string replacement'
		}
	}
	for i in 3 .. 5 {
		match mappings.map.list[i].replacement {
			terminal.CodepointRepl {
				assert mappings.map.list[i].replacement.codepoint == u32(`-`)
			}
			terminal.StringRepl {
				assert false, 'expected codepoint replacement'
			}
		}
	}
	match mappings.map.list[5].replacement {
		terminal.CodepointRepl {
			assert mappings.map.list[5].replacement.codepoint == 0
		}
		terminal.StringRepl {
			assert false, 'expected codepoint replacement'
		}
	}
}

fn test_clipboard_codepoint_map_clone_add_and_format_entry() {
	mut base := ClipboardCodepointMap{}
	base.add(terminal.CodepointMap{
		range_start: 1
		range_end: 5
		replacement: terminal.CodepointReplacement(terminal.StringRepl{ str: 'SUM' })
	})
	cloned := base.clone()
	assert cloned.equal(base)
	assert cloned.list.len == 1
	match cloned.list[0].replacement {
		terminal.StringRepl {
			assert cloned.list[0].replacement.str == 'SUM'
		}
		terminal.CodepointRepl {
			assert false
		}
	}

	mut mappings := RepeatableClipboardCodepointMap{}
	assert mappings.format_entry() == ['']
	mappings.parse_cli('U+0001-U+0005=SUM')!
	mappings.parse_cli('U+2500=U+002D')!
	assert mappings.format_entry() == [
		'U+0001-U+0005=SUM',
		'U+2500=U+002D',
	]
}

fn test_unicode_range_parser_matches_source_scanning() {
	mut empty := RepeatableCodepointMap{}
	empty.parse_cli('=Font')!
	assert empty.map.entries.len == 0

	for value in ['U+ 0001=Font', 'U+0_001=Font', 'U+0001-U+ 0002=Font'] {
		mut invalid := RepeatableCodepointMap{}
		invalid.parse_cli(value) or {
			expect_parse_error(err, .invalid_value)
			continue
		}
		assert false, 'expected invalid range for ${value}'
	}

	// The source mutates the repeatable map after every parsed range, so an
	// error in a later range leaves earlier entries in place.
	mut partial := RepeatableCodepointMap{}
	partial.parse_cli('U+0001,U+ZZZZ=Font') or {
		expect_parse_error(err, .invalid_value)
		assert partial.map.entries.len == 1
		assert partial.map.entries[0].range == [u32(1), u32(1)]!
		return
	}
	assert false, 'expected invalid second range'
}

fn test_load_string_applies_selection_and_clipboard_maps() {
	mut cfg := Config.default_config()
	cfg.load_string('
selection-word-chars = ._
clipboard-codepoint-map = U+2500=U+002D
')
	assert cfg.selection_word_chars.codepoints == [u32(0), u32(`.`), u32(`_`)]
	assert cfg.clipboard_codepoint_map.map.list.len == 1
	assert cfg.diagnostics.len == 0
}

fn test_font_configuration_rejects_invalid_values_and_resets_metric_modifier() {
	mut cfg := Config.default_config()
	cfg.load_string('adjust-cell-width = 2\nadjust-cell-width = \nfont-variation = abc=1\nfont-codepoint-map = U+0001-0002=Symbols\nadjust-cell-height = 1.5\nfont-synthetic-style = shadow\nfreetype-load-flags = lcd\n')
	assert cfg.adjust_cell_width == none
	assert cfg.diagnostics.len == 5
}

fn test_config_key_remap_is_parsed_cloned_and_finalized() {
	mut cfg := Config.default_config()
	cfg.load_string('key-remap = ctrl=super\nkey-remap = right_ctrl=alt\n')
	assert cfg.diagnostics.len == 0
	cfg.finalize()!

	left_ctrl := input.Mods.init(false, true, false, false, false, false, input.SideInfo.init(.left, .left, .left, .left))
	right_ctrl := input.Mods.init(false, true, false, false, false, false, input.SideInfo.init(.left, .right, .left, .left))
	assert cfg.key_remap.apply(left_ctrl).super_()
	assert cfg.key_remap.apply(right_ctrl).alt()

	cloned := cfg.clone()
	assert cloned.key_remap.equal(cfg.key_remap)
}

fn test_load_string_applies_full_existing_config_surface() {
	mut cfg := Config.default_config()
	cfg.load_string('
command = direct:nvim file.txt
initial-command = shell:echo hi
input = hello
input = path:startup.txt
env = FOO=first
env = BAR=second
env = FOO=replaced
enquiry-response = witty
font-feature = liga
font-feature = calt
font-style = Regular
font-style-bold = Bold
font-style-italic = Italic
font-style-bold-italic = Bold Italic
font-synthetic-style = bold,no-italic,no-bold-italic
font-variation = wght=200
font-variation = slnt=-15.5
font-variation-bold = wght=700
font-variation-italic = ital=1
font-variation-bold-italic = opsz=13
font-codepoint-map = U+ABCD=Comic Sans
font-codepoint-map = U+0001-U+0005,U+0006=Verdana
font-thicken = true
font-thicken-strength = 42
font-shaping-break = no-cursor
adjust-cell-width = 1
adjust-cell-height = 20%
adjust-font-baseline = -2
adjust-underline-position = 3
adjust-underline-thickness = 4
adjust-strikethrough-position = -5
adjust-strikethrough-thickness = 6
adjust-overline-position = -7
adjust-overline-thickness = 8
adjust-cursor-thickness = 9
adjust-cursor-height = -10%
adjust-box-thickness = 11
adjust-icon-height = 12%
freetype-load-flags = no-hinting,force-autohint,monochrome,no-autohint,light
custom-shader = one.glsl
custom-shader = ?"optional shader.glsl"
config-file = extra.conf
config-file = ?optional.conf
background-image = ?bg.png
background-image-opacity = 0.75
background-image-position = center-center
background-image-fit = cover
background-image-repeat = true
background-opacity-cells = true
bold-color = RebeccaPurple
unfocused-split-fill = LightGoldenrodYellow
split-divider-color = #abc
split-preserve-zoom = navigation
window-padding-x = 3,4
window-padding-y = 1,2
window-padding-balance = true
window-padding-color = extend-always
window-position-x = -120
window-position-y = 340
window-save-state = always
window-step-resize = true
window-vsync = false
window-colorspace = display-p3
alpha-blending = linear
background-blur = 37
clipboard-read = deny
clipboard-write = ask
copy-on-select = clipboard
confirm-close-surface = always
mouse-shift-capture = never
shell-integration = fish
shell-integration-features = no-cursor,sudo,ssh-env,no-path
link-previews = osc8
scroll-to-bottom = no-keystroke,output
grapheme-width-method = legacy
scrollbar = never
notify-on-command-finish = always
cursor-style = bar
cursor-style-blink = false
right-click-action = copy-or-paste
osc-color-report-format = 8-bit
custom-shader-animation = always
mouse-scroll-multiplier = 2.5
image-storage-limit = 0x100
undo-timeout = 1h30m
async-backend = io_uring
auto-update = download
auto-update-channel = stable
')

	assert cfg.diagnostics.len == 0
	command := cfg.command or { panic('missing command') }
	match command {
		DirectCmd {
			assert command.direct == ['nvim', 'file.txt']
		}
		ShellCmd {
			assert false, 'expected direct command'
		}
	}
	initial_command := cfg.initial_command or { panic('missing initial command') }
	match initial_command {
		ShellCmd {
			assert initial_command.shell == 'echo hi'
		}
		DirectCmd {
			assert false, 'expected shell command'
		}
	}
	assert cfg.input.items == [ReadableIO(ReadableIORaw{ value: 'hello' }),
		ReadableIO(ReadableIOPath{ value: 'startup.txt' })]
	assert cfg.env.entries == [StringMapEntry{'FOO', 'replaced'}, StringMapEntry{'BAR', 'second'}]
	assert cfg.enquiry_response == 'witty'
	assert cfg.font_feature == ['liga', 'calt']
	assert cfg.font_style.name_value()? == 'Regular'
	assert cfg.font_style_bold.name_value()? == 'Bold'
	assert cfg.font_style_italic.name_value()? == 'Italic'
	assert cfg.font_style_bold_italic.name_value()? == 'Bold Italic'
	assert cfg.font_synthetic_style.bold()
	assert !cfg.font_synthetic_style.italic()
	assert !cfg.font_synthetic_style.bold_italic()
	assert cfg.font_variation.list.len == 2
	assert cfg.font_variation.list[0].id.str() == 'wght'
	assert cfg.font_variation.list[0].value == 200
	assert cfg.font_variation.list[1].id.str() == 'slnt'
	assert cfg.font_variation.list[1].value == -15.5
	assert cfg.font_variation_bold.list[0].id.str() == 'wght'
	assert cfg.font_variation_italic.list[0].id.str() == 'ital'
	assert cfg.font_variation_bold_italic.list[0].id.str() == 'opsz'
	assert cfg.font_codepoint_map.map.entries.len == 3
	assert cfg.font_codepoint_map.map.entries[0].range == [u32(0xabcd), u32(0xabcd)]!
	assert cfg.font_codepoint_map.map.entries[0].descriptor.family? == 'Comic Sans'
	assert cfg.font_codepoint_map.map.entries[1].range == [u32(1), u32(5)]!
	assert cfg.font_codepoint_map.map.entries[2].range == [u32(6), u32(6)]!
	assert_metric_modifier_absolute(cfg.adjust_cell_width, 1)
	assert_metric_modifier_percent(cfg.adjust_cell_height, 1.2)
	assert_metric_modifier_absolute(cfg.adjust_font_baseline, -2)
	assert_metric_modifier_absolute(cfg.adjust_underline_position, 3)
	assert_metric_modifier_absolute(cfg.adjust_underline_thickness, 4)
	assert_metric_modifier_absolute(cfg.adjust_strikethrough_position, -5)
	assert_metric_modifier_absolute(cfg.adjust_strikethrough_thickness, 6)
	assert_metric_modifier_absolute(cfg.adjust_overline_position, -7)
	assert_metric_modifier_absolute(cfg.adjust_overline_thickness, 8)
	assert_metric_modifier_absolute(cfg.adjust_cursor_thickness, 9)
	assert_metric_modifier_percent(cfg.adjust_cursor_height, 0.9)
	assert_metric_modifier_absolute(cfg.adjust_box_thickness, 11)
	assert_metric_modifier_percent(cfg.adjust_icon_height, 1.12)
	assert !cfg.freetype_load_flags.hinting()
	assert cfg.freetype_load_flags.force_autohint()
	assert cfg.freetype_load_flags.monochrome()
	assert !cfg.freetype_load_flags.autohint()
	assert cfg.freetype_load_flags.light()
	assert cfg.font_thicken
	assert cfg.font_thicken_strength == 42
	assert !cfg.font_shaping_break.cursor()
	assert cfg.custom_shader.items == [
		Path(PathRequired{ path: 'one.glsl' }),
		Path(PathOptional{ path: 'optional shader.glsl' }),
	]
	assert cfg.config_file.items == [
		Path(PathRequired{ path: 'extra.conf' }),
		Path(PathOptional{ path: 'optional.conf' }),
	]
	background_image := cfg.background_image or { panic('missing background image') }
	assert background_image is PathOptional
	assert (background_image as PathOptional).path == 'bg.png'
	assert cfg.background_image_opacity == 0.75
	assert cfg.background_image_position == .center_center
	assert cfg.background_image_fit == .cover
	assert cfg.background_image_repeat
	assert cfg.background_opacity_cells
	bold_color := cfg.bold_color or { panic('missing bold color') }
	assert bold_color is BoldColorColor
	assert (bold_color as BoldColorColor).color == ColorRGB{102, 51, 153}
	assert cfg.unfocused_split_fill? == ColorRGB{250, 250, 210}
	assert cfg.split_divider_color? == ColorRGB{170, 187, 204}
	assert cfg.split_preserve_zoom.navigation()
	assert cfg.window_padding_x == WindowPadding{3, 4}
	assert cfg.window_padding_y == WindowPadding{1, 2}
	assert cfg.window_padding_balance == .true_
	assert cfg.window_padding_color == .extend_always
	assert cfg.window_position_x? == -120
	assert cfg.window_position_y? == 340
	assert cfg.window_save_state == .always
	assert cfg.window_step_resize
	assert !cfg.window_vsync
	assert cfg.window_colorspace == .display_p3
	assert cfg.alpha_blending == .linear
	assert cfg.background_blur is BackgroundBlurRadius
	assert (cfg.background_blur as BackgroundBlurRadius).radius == 37
	assert cfg.clipboard_read == .deny
	assert cfg.clipboard_write == .ask
	assert cfg.copy_on_select == .clipboard
	assert cfg.confirm_close_surface == .always
	assert cfg.mouse_shift_capture == .never
	assert cfg.shell_integration == .fish
	assert !cfg.shell_integration_features.cursor()
	assert cfg.shell_integration_features.sudo()
	assert cfg.shell_integration_features.ssh_env()
	assert !cfg.shell_integration_features.path()
	assert cfg.link_previews == .osc8
	assert !cfg.scroll_to_bottom.keystroke()
	assert cfg.scroll_to_bottom.output()
	assert cfg.grapheme_width_method == .legacy
	assert cfg.scrollbar == .never
	assert cfg.notify_on_command_finish == .always
	assert cfg.cursor_style == .bar
	assert cfg.cursor_style_blink? == false
	assert cfg.right_click_action == .copy_or_paste
	assert cfg.osc_color_report_format == .format_8_bit
	assert cfg.custom_shader_animation == .always
	assert cfg.mouse_scroll_multiplier.precision == 2.5
	assert cfg.mouse_scroll_multiplier.discrete == 2.5
	assert cfg.image_storage_limit == 0x100
	assert cfg.undo_timeout.duration == u64(5_400) * 1_000_000_000
	assert cfg.async_backend == .io_uring
	assert cfg.auto_update? == .download
	assert cfg.auto_update_channel? == .stable
}

fn test_config_mouse_scroll_multiplier_struct_and_finalize() {
	mut cfg := Config.default_config()
	assert cfg.mouse_scroll_multiplier == MouseScrollMultiplier{
		precision: 1
		discrete: 3
	}
	cfg.load_string('mouse-scroll-multiplier = precision:0.001,discrete:20000\n')
	assert cfg.diagnostics.len == 0
	assert cfg.mouse_scroll_multiplier.precision == 0.001
	assert cfg.mouse_scroll_multiplier.discrete == 20_000
	cfg.finalize()!
	assert cfg.mouse_scroll_multiplier.precision == 0.01
	assert cfg.mouse_scroll_multiplier.discrete == 10_000
	assert cfg.format_config(true).contains('mouse-scroll-multiplier = precision:0.01,discrete:10000\n')
}

fn test_config_empty_values_reset_every_field_kind_to_source_defaults() {
	mut cfg := Config.default_config()
	cfg.load_string('
background = ff0000
term = ansi
window-vsync = false
font-size = 42
window-theme = dark
mouse-scroll-multiplier = precision:4,discrete:8
selection-word-chars = abc
keybind = clear
command-palette-entry =
command-palette-entry = title:Custom,action:quit
theme = light:One,dark:Two
_xdg-terminal-exec = true
')
	assert cfg.diagnostics.len == 0
	assert cfg.term == 'ansi'
	assert !cfg.window_vsync
	assert cfg.selection_word_chars.codepoints == [u32(0), u32(`a`), u32(`b`), u32(`c`)]
	assert cfg.keybind.set.bindings.len == 0
	assert cfg.command_palette_entry.items.len == input.command_defaults.len + 1
	assert cfg.command_palette_entry.items.last().title == 'Custom'
	assert cfg.theme != none
	assert cfg.xdg_terminal_exec

	cfg.load_string('
background =
term =
window-vsync =
font-size =
window-theme =
mouse-scroll-multiplier =
selection-word-chars =
keybind =
command-palette-entry =
theme =
_xdg-terminal-exec =
')
	assert cfg.diagnostics.len == 0
	defaults := Config.default_config()
	assert cfg.background == defaults.background
	assert cfg.term == defaults.term
	assert cfg.window_vsync == defaults.window_vsync
	assert cfg.font_size == defaults.font_size
	assert cfg.window_theme == defaults.window_theme
	assert cfg.mouse_scroll_multiplier == defaults.mouse_scroll_multiplier
	assert cfg.selection_word_chars == defaults.selection_word_chars
	assert cfg.keybind.equal(defaults.keybind)
	assert cfg.command_palette_entry.items.len == defaults.command_palette_entry.items.len
	assert cfg.theme == none
	assert 'theme' !in cfg.conditional_set
	assert !cfg.xdg_terminal_exec
}

fn test_config_empty_link_uses_field_default_not_runtime_default_url() {
	mut cfg := Config.default_config()
	assert cfg.link.links.len == 1
	cfg.load_string('link =\n')
	assert cfg.diagnostics.len == 0
	assert cfg.link.links.len == 0
}

fn test_xdg_terminal_exec_sets_only_initial_command_mode() {
	mut cfg := Config.default_config()
	default_quit := cfg.quit_after_last_window_closed
	cfg.load_xdg_terminal_exec_args(['echo', 'hello world'])
	assert cfg.xdg_terminal_exec
	assert cfg.quit_after_last_window_closed == default_quit
	command := cfg.initial_command or { panic('missing initial command') }
	assert command.string_val() == 'echo hello world'
	assert cfg.replay_steps.len == 3
	assert cfg.replay_steps[0] is ReplayCommand
	assert cfg.replay_steps[1] is ReplayArg
	assert (cfg.replay_steps[1] as ReplayArg).value == 'echo'
	assert cfg.replay_steps[2] is ReplayArg
	assert (cfg.replay_steps[2] as ReplayArg).value == 'hello world'
}

fn test_xdg_terminal_exec_theme_replay_uses_command_marker() ! {
	theme := os.join_path(os.temp_dir(), 'witty-xdg-command-theme-${os.getpid()}')
	os.write_file(theme, '')!
	defer {
		os.rm(theme) or {}
	}

	mut cfg := Config.default_config()
	cfg.load_string('theme = ${theme}\n')
	cfg.load_xdg_terminal_exec_args(['echo', 'hello world'])
	cfg.finalize()!

	command := cfg.initial_command or { panic('missing replayed initial command') }
	assert command.string_val() == 'echo hello world'
	assert cfg.quit_after_last_window_closed
	// cloneEmpty retains conditional state only, so the internal xdg marker is
	// not copied when the synthetic -e stream rebuilds the config around a theme.
	assert !cfg.xdg_terminal_exec
}

fn test_config_enum_parser_rejects_values_not_present_in_source() {
	mut cfg := Config.default_config()
	cfg.load_string('
window-theme = sepia
window-show-tab-bar = sometimes
cursor-style = block-hollow
')
	assert cfg.diagnostics.len == 3
}

fn test_repeatable_config_values_reset_and_env_remove() {
	mut cfg := Config.default_config()
	cfg.load_string('
font-feature = liga
font-feature =
custom-shader = one
custom-shader =
config-file = one
config-file =
env = A=B
env = A=
env = C=D
env =
command = echo hi
command =
')
	assert cfg.font_feature.len == 0
	assert cfg.custom_shader.items.len == 0
	assert cfg.config_file.items.len == 0
	assert cfg.env.entries.len == 0
	assert cfg.command == none
	assert cfg.diagnostics.len == 0
}

fn test_invalid_scalar_config_values_are_diagnostics_not_zeroes() {
	mut cfg := Config.default_config()
	before_font_size := cfg.font_size
	before_window_width := cfg.window_width
	cfg.load_string('
font-size = nope
window-width = -1
font-thicken-strength = 256
background-image-opacity = nope
font-shaping-break = mouse
shell-integration = powershell
right-click-action = explode
')
	assert cfg.font_size == before_font_size
	assert cfg.window_width == before_window_width
	assert cfg.font_thicken_strength == 255
	assert cfg.background_image_opacity == 1.0
	assert cfg.diagnostics.len == 7
}

fn test_integer_config_values_use_zig_parse_int_grammar() {
	mut cfg := Config.default_config()
	cfg.load_string('
window-width = +0x2a
window-height = 1__0
scrollback-limit = -0
font-thicken-strength = 0xff
window-position-x = -0x1__0
')
	assert cfg.window_width == 42
	assert cfg.window_height == 10
	assert cfg.scrollback_limit == 0
	assert cfg.font_thicken_strength == 255
	assert cfg.window_position_x? == -16
	assert cfg.diagnostics.len == 0

	cfg.load_string('
window-width = 0x_10
window-position-x = 32768
')
	assert cfg.window_width == 42
	assert cfg.window_position_x? == -16
	assert cfg.diagnostics.len == 2
}

fn test_named_colors_work_for_base_colors_and_palette() {
	mut cfg := Config.default_config()
	cfg.load_string('
background = RebeccaPurple
foreground = LightGoldenrodYellow
palette = 17=DeepSkyBlue
')
	assert cfg.background == ColorRGB{102, 51, 153}
	assert cfg.foreground == ColorRGB{250, 250, 210}
	assert cfg.palette.value[17] == ColorRGB{0, 191, 255}
	assert cfg.diagnostics.len == 0
}

fn test_repeatable_path_parses_required_optional_quotes_and_reset() {
	mut paths := RepeatablePath{}
	paths.parse_cli('one.glsl')!
	paths.parse_cli('?"optional shader.glsl"')!
	paths.parse_cli('?')!
	assert paths.items == [
		Path(PathRequired{ path: 'one.glsl' }),
		Path(PathOptional{ path: 'optional shader.glsl' }),
	]
	paths.parse_cli('')!
	assert paths.items.len == 0
}

fn test_path_parse_distinguishes_quoted_question_mark() {
	maybe_required := Path.parse('"?required.conf"')!
	maybe_optional := Path.parse('?"optional.conf"')!
	required := maybe_required.value or { panic('missing required path') }
	optional := maybe_optional.value or { panic('missing optional path') }
	assert required == Path(PathRequired{ path: '?required.conf' })
	assert optional == Path(PathOptional{ path: 'optional.conf' })
	assert !required.equal(optional)
	assert !Path(PathRequired{ path: 'same.conf' }).equal(Path(PathOptional{ path: 'same.conf' }))
}

fn test_path_parse_preserves_error_union_optional_contract() {
	mut missing_error := ParseError.invalid_value
	_ := Path.parse(none) or {
		missing_error = parse_error_of(err) or { ParseError.invalid_value }
		PathParseResult{}
	}
	assert missing_error == .value_required
	assert Path.parse('')!.value == none
	assert Path.parse('?')!.value? == Path(PathOptional{ path: '' })
	assert Path.parse('""')!.value? == Path(PathRequired{ path: '' })
	assert Path.parse('?""')!.value? == Path(PathOptional{ path: '' })
}

fn test_path_public_parse_and_format_apis() {
	mut path := Path(PathRequired{
		path: 'original.conf'
	})
	assert path.len() == 13
	assert path.format_entry() == 'original.conf'

	path.parse_cli('?"optional.conf"')!
	assert path == Path(PathOptional{ path: 'optional.conf' })
	assert path.format_entry() == '?optional.conf'

	// Empty parsed paths do not replace the existing value.
	path.parse_cli('?')!
	path.parse_cli('""')!
	assert path == Path(PathOptional{ path: 'optional.conf' })

	assert RepeatablePath{}.format_entry() == ['']
	assert RepeatablePath{
		items: [Path(PathRequired{ path: 'one' }), Path(PathOptional{ path: 'two' })]
	}.format_entry() == ['one', '?two']
}

fn test_path_expand_uses_translated_home_expansion() {
	previous := os.getenv_opt('HOME')
	defer {
		if value := previous {
			os.setenv('HOME', value, true)
		} else {
			os.unsetenv('HOME')
		}
	}
	os.setenv('HOME', '/tmp/witty-path-home/', true)

	mut path := Path(PathRequired{ path: '~/shader.glsl' })
	mut diagnostics := []Diagnostic{}
	path.expand('/tmp', mut diagnostics)!
	assert path is PathRequired
	assert (path as PathRequired).path == '/tmp/witty-path-home//shader.glsl'
	assert diagnostics.len == 0
}

fn test_path_expand_canonicalizes_existing_relative_path() ! {
	$if !windows {
		dir := os.join_path(os.temp_dir(), 'witty-path-real-${os.getpid()}')
		os.rmdir_all(dir) or {}
		os.mkdir_all(os.join_path(dir, 'actual'))!
		defer {
			os.rmdir_all(dir) or {}
		}
		os.symlink(os.join_path(dir, 'actual'), os.join_path(dir, 'linked'))!

		mut path := Path(PathRequired{ path: 'linked' })
		mut diagnostics := []Diagnostic{}
		path.expand(dir, mut diagnostics)!
		assert path is PathRequired
		assert (path as PathRequired).path == os.real_path(os.join_path(dir, 'actual'))
		assert diagnostics.len == 0
	}
}

fn test_path_expand_records_resolution_errors_and_blanks_path() ! {
	$if !windows {
		dir := os.join_path(os.temp_dir(), 'witty-path-error-${os.getpid()}')
		os.rmdir_all(dir) or {}
		os.mkdir_all(dir)!
		defer {
			os.rmdir_all(dir) or {}
		}
		os.write_file(os.join_path(dir, 'file'), '')!

		mut path := Path(PathOptional{ path: 'file/child' })
		mut diagnostics := []Diagnostic{}
		path.expand(dir, mut diagnostics)!
		assert path == Path(PathRequired{ path: '' })
		assert diagnostics.len == 1
		assert diagnostics[0].message.starts_with('error resolving file path file/child: ')
	}
}

fn test_load_file_expands_paths_relative_to_declaring_file() {
	dir := os.join_path(os.temp_dir(), 'witty-config-paths-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'config.witty')
	os.write_file(path, 'custom-shader = shader.glsl\nbackground-image = images/bg.png\n')!
	mut cfg := Config.default_config()
	cfg.load_file(path)!
	assert cfg.custom_shader.items == [Path(PathRequired{ path: os.join_path(dir, 'shader.glsl') })]
	assert cfg.background_image? == Path(PathRequired{ path: os.join_path(dir, 'images', 'bg.png') })
	assert cfg.diagnostics.len == 0
}

fn test_load_recursive_files_preserves_order_and_nested_bases() {
	dir := os.join_path(os.temp_dir(), 'witty-config-recursive-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(os.join_path(dir, 'nested'))!
	defer {
		os.rmdir_all(dir) or {}
	}
	root := os.join_path(dir, 'config.witty')
	first := os.join_path(dir, 'first.conf')
	second := os.join_path(dir, 'nested', 'second.conf')
	os.write_file(root, 'font-size = 10\nconfig-file = first.conf\n')!
	os.write_file(first, 'font-size = 11\nconfig-file = nested/second.conf\n')!
	os.write_file(second, 'font-size = 12\ncustom-shader = effect.glsl\n')!

	mut cfg := Config.default_config()
	cfg.load_file(root)!
	cfg.load_recursive_files()!
	assert cfg.font_size == 12
	assert cfg.config_file.items == [
		Path(PathRequired{ path: os.real_path(first) }),
		Path(PathRequired{ path: os.real_path(second) }),
	]
	assert cfg.custom_shader.items == [
		Path(PathRequired{ path: os.join_path(os.dir(os.real_path(second)), 'effect.glsl') }),
	]
	assert cfg.diagnostics.len == 0
}

fn test_recursive_files_skip_optional_missing_and_report_required_and_cycles() {
	dir := os.join_path(os.temp_dir(), 'witty-config-recursive-errors-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	root := os.join_path(dir, 'config.witty')
	child := os.join_path(dir, 'child.conf')
	os.write_file(root, 'config-file = ?missing.conf\nconfig-file = required.conf\nconfig-file = child.conf\n')!
	os.write_file(child, 'config-file = child.conf\n')!

	mut cfg := Config.default_config()
	cfg.load_file(root)!
	cfg.load_recursive_files()!
	assert cfg.diagnostics.len == 2
	assert cfg.diagnostics[0].message == 'error opening config-file ${os.join_path(dir, 'required.conf')}: error.FileNotFound'
	assert cfg.diagnostics[1].message == 'config-file ${os.real_path(child)}: cycle detected'
}

fn test_recursive_file_diagnostics_keep_the_declaring_path() {
	dir := os.join_path(os.temp_dir(), 'witty-config-recursive-location-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	root := os.join_path(dir, 'config.witty')
	child := os.join_path(dir, 'child.conf')
	os.write_file(root, 'config-file = child.conf\n')!
	os.write_file(child, 'font-size = invalid\n')!

	mut cfg := Config.default_config()
	cfg.load_file(root)!
	cfg.load_recursive_files()!
	assert cfg.diagnostics.len == 1
	assert cfg.diagnostics[0].format() == '${os.real_path(child)}:1:font-size: invalid value "invalid"'
}

fn test_recursive_replay_steps_are_inserted_before_command_tail() {
	dir := os.join_path(os.temp_dir(), 'witty-config-recursive-replay-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	child := os.join_path(dir, 'child.conf')
	os.write_file(child, 'font-size = 19\n')!

	mut cfg := Config.default_config()
	cfg.load_cli_args(['--config-file=${child}', '-e', 'echo', 'hello'])!
	cfg.load_recursive_files()!
	mut child_index := -1
	mut command_index := -1
	for i, step in cfg.replay_steps {
		if step is ReplayArg && step.value == '--font-size=19' {
			child_index = i
		}
		if step is ReplayCommand {
			command_index = i
		}
	}
	assert child_index >= 0
	assert command_index > child_index
}

fn test_preferred_xdg_path_uses_new_then_legacy_name() ! {
	dir := os.join_path(os.temp_dir(), 'witty-config-default-path-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(os.join_path(dir, 'ghostty'))!
	os.mkdir_all(os.join_path(dir, 'witty'))!
	defer {
		os.rmdir_all(dir) or {}
	}
	old_xdg := os.getenv_opt('XDG_CONFIG_HOME')
	os.setenv('XDG_CONFIG_HOME', dir, true)
	defer {
		if value := old_xdg {
			os.setenv('XDG_CONFIG_HOME', value, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
	}
	new_path := os.join_path(dir, 'witty', 'config.witty')
	previous_path := os.join_path(dir, 'ghostty', 'config.ghostty')
	legacy_path := os.join_path(dir, 'ghostty', 'config')
	assert preferred_xdg_path()! == new_path
	os.write_file(legacy_path, 'font-size = 10\n')!
	assert preferred_xdg_path()! == legacy_path
	os.write_file(new_path, '')!
	assert preferred_xdg_path()! == legacy_path
	os.write_file(previous_path, 'font-size = 12\n')!
	assert preferred_xdg_path()! == previous_path
	os.write_file(new_path, 'font-size = 11\n')!
	assert preferred_xdg_path()! == new_path
}

fn expect_open_file_error(path string, want OpenFileError) {
	mut file := open(path) or {
		got := open_file_error_of(err) or {
			assert false, 'expected OpenFileError.${want}, got ${err}'
			return
		}
		assert got == want
		return
	}
	file.close()
	assert false, 'expected OpenFileError.${want}'
}

fn test_config_file_open_requires_nonempty_regular_file() ! {
	dir := os.join_path(os.temp_dir(), 'witty-config-open-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	missing := os.join_path(dir, 'missing')
	empty := os.join_path(dir, 'empty')
	configured := os.join_path(dir, 'configured')
	expect_open_file_error(missing, .file_not_found)
	expect_open_file_error(dir, .not_a_file)
	os.write_file(empty, '')!
	expect_open_file_error(empty, .file_is_empty)
	os.write_file(configured, 'font-size = 11\n')!
	mut file := open(configured)!
	file.close()
}

fn test_keybinds_format_entries_includes_root_tables_and_chains() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('ctrl+a=new_window')!
	keybinds.parse_cli('editing/x=text:hello')!
	keybinds.parse_cli('editing/chain=new_tab')!
	assert keybinds.format_entries() == [
		'keybind = ctrl+a=new_window',
		'keybind = editing/x=text:hello',
		'keybind = chain=new_tab',
	]
}

fn test_keybinds_format_entry_docs_matches_pinned_source_lookup() {
	mut keybinds := Keybinds{}
	keybinds.parse_cli('shift+a=copy_to_clipboard')!
	keybinds.parse_cli('foo/ctrl+b=new_tab')!
	assert keybinds.format_entry_docs(true) == [
		'',
		'keybind = shift+a=copy_to_clipboard:mixed',
		'keybind = foo/ctrl+b=new_tab',
	]
}

// Witty's `font-size` default is 13 on macOS and 12 elsewhere.
const default_font_size_line = $if macos { 'font-size = 13.0\n' } $else { 'font-size = 12.0\n' }

fn test_format_config_default_formats_all_supported_values() {
	formatted := Config.default_config().format_config(false)
	assert formatted.contains(default_font_size_line)
	assert formatted.contains('background = #282c34\n')
	assert formatted.contains('clipboard-codepoint-map = \n')
	assert formatted.contains('keybind = ')
	assert formatted.contains('palette = 255=#eeeeee\n')
	assert config_entry_groups(Config.default_config()).map(it.key) == config_keys
}

fn test_entry_formatter_formats_primitive_optional_and_packed_values() {
	formatter := entry_formatter('a')
	assert formatter.format_entry(true) == 'a = true\n'
	assert formatter.format_entry(false) == 'a = false\n'
	assert formatter.format_entry(u8(123)) == 'a = 123\n'
	assert formatter.format_entry(f64(0.7)) == 'a = 0.7\n'
	assert formatter.format_entry(FormatterTestEnum.two) == 'a = two\n'
	assert formatter.format_entry(?bool(none)) == 'a = \n'
	assert formatter.format_entry(?bool(false)) == 'a = false\n'
	assert formatter.format_entry('hello') == 'a = hello\n'
	assert formatter.format_entry(FormatterTestFlags{}) == 'a = one,no-two\n'
}

fn test_format_entry_uses_composite_format_entry_methods() {
	assert format_entry('color', ColorRGB{ r: 10, g: 11, b: 12 }) == 'color = #0a0b0c\n'
	assert format_entry('path', RepeatablePath{}) == 'path = \n'
	assert format_entry('size', QuickTerminalSize{}) == ''
}

fn test_window_padding_balance_accepts_equal_and_legacy_booleans() {
	mut cfg := Config.default_config()
	cfg.load_cli_args(['--window-padding-balance'])
	assert cfg.window_padding_balance == .true_
	cfg.load_cli_args(['--window-padding-balance=0'])
	assert cfg.window_padding_balance == .false_
	cfg.load_cli_args(['--window-padding-balance=equal'])
	assert cfg.window_padding_balance == .equal
	mut parsed := Config.default_config()
	parsed.load_string(cfg.format_config(true))
	assert parsed.window_padding_balance == .equal
	parsed.load_string('window-padding-balance = ')
	assert parsed.window_padding_balance == .false_
	assert cfg.diagnostics.len == 0
	assert parsed.diagnostics.len == 0
}

fn test_format_config_changes_only_round_trips_supported_values() {
	mut original := Config.default_config()
	original.load_string('font-size = 17.5\nfont-style-bold = Heavy\nfont-synthetic-style = no-bold,italic,bold-italic\nfont-variation = wght=321.5\nfont-codepoint-map = U+0001-U+0002=Symbols\nadjust-cell-height = -25%\nfreetype-load-flags = no-hinting,force-autohint\nbackground = RebeccaPurple\ncommand = direct:echo hello\ncustom-shader = ?shader.glsl\nkeybind = ctrl+a>n=new_window\nkeybind = chain=move_tab:-1\nsplit-preserve-zoom = navigation\nwindow-padding-x = 6,7\nwindow-padding-y = 8\nwindow-position-x = -9\nwindow-position-y = 10\nwindow-save-state = never\nwindow-step-resize = true\nundo-timeout = 45s\nasync-backend = io_uring\nauto-update = check\nauto-update-channel = stable\n')
	formatted := original.format_config(true)
	assert formatted.contains('font-size = 17.5\n')
	assert formatted.contains('font-style-bold = Heavy\n')
	assert formatted.contains('font-synthetic-style = no-bold,italic,bold-italic\n')
	assert formatted.contains('font-variation = wght=321.5\n')
	assert formatted.contains('font-codepoint-map = U+0001-U+0002=Symbols\n')
	assert formatted.contains('adjust-cell-height = -25%\n')
	assert formatted.contains('freetype-load-flags = no-hinting,force-autohint,no-monochrome,autohint,light\n')
	assert formatted.contains('background = #663399\n')
	assert formatted.contains('command = direct:echo hello\n')
	assert formatted.contains('custom-shader = ?shader.glsl\n')
	assert formatted.contains('keybind = ctrl+a>n=new_window\n')
	assert formatted.contains('keybind = chain=move_tab:-1\n')
	assert formatted.contains('split-preserve-zoom = navigation\n')
	assert formatted.contains('window-padding-x = 6,7\n')
	assert formatted.contains('window-padding-y = 8\n')
	assert formatted.contains('window-position-x = -9\n')
	assert formatted.contains('window-position-y = 10\n')
	assert formatted.contains('window-save-state = never\n')
	assert formatted.contains('window-step-resize = true\n')
	assert formatted.contains('undo-timeout = 45s\n')
	assert formatted.contains('async-backend = io_uring\n')
	assert formatted.contains('auto-update = check\n')
	assert formatted.contains('auto-update-channel = stable\n')

	mut parsed := Config.default_config()
	parsed.load_string(formatted)
	assert parsed.diagnostics.len == 0
	assert parsed.font_size == original.font_size
	assert parsed.font_style_bold == original.font_style_bold
	assert parsed.font_synthetic_style == original.font_synthetic_style
	assert parsed.font_variation.equal(original.font_variation)
	assert parsed.font_codepoint_map.equal(original.font_codepoint_map)
	assert parsed.adjust_cell_height == original.adjust_cell_height
	assert parsed.freetype_load_flags == original.freetype_load_flags
	assert parsed.background == original.background
	assert parsed.command?.string_val() == original.command?.string_val()
	assert parsed.custom_shader.equal(original.custom_shader)
	assert parsed.split_preserve_zoom.navigation()
	assert parsed.window_padding_x == original.window_padding_x
	assert parsed.window_padding_y == original.window_padding_y
	assert parsed.window_position_x == original.window_position_x
	assert parsed.window_position_y == original.window_position_y
	assert parsed.window_save_state == original.window_save_state
	assert parsed.window_step_resize
	assert parsed.undo_timeout == original.undo_timeout
	assert parsed.async_backend == original.async_backend
	assert parsed.auto_update == original.auto_update
	assert parsed.auto_update_channel == original.auto_update_channel
	// Witty's binding formatter intentionally serializes triggers and
	// actions but not the in-memory performable/consumed flags.
	assert parsed.keybind.set.get_trigger(input.ActionNewWindow{}) != none
}
