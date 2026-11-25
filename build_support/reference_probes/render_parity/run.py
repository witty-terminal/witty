import argparse
import hashlib
import math
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

from PIL import Image, ImageChops

from applications import (
    APPLICATION_STAGES, capture_application_frame, capture_less, capture_tmux, prepare_applications,
)
from capture import (
    build_window_reader, capture_witty, configure_xvfb_capture, open_window,
    output_directory, read_window, write_versions,
)
from fixtures import (
    CURSOR_STYLES, FONT_ZOOM_MARKER, GRID_COLUMNS, GRID_ROWS, KITTY_SCROLL_FIXTURES, RESIZE_FIXTURES, RESIZE_WRAP_COLOR,
    SCROLLBACK_FIXTURES, SCROLLBACK_LAST_COLOR, SCROLLBACK_RECOLORED, SCROLLBAR_MARKER,
    SHADER_RELOAD_MARKER, SPLIT_RIGHT_COLOR, WALLPAPER_RELOAD_MARKER, WIDE_EDIT_AFTER, WIDE_EDIT_BEFORE,
)


PROBE = Path(__file__).resolve().parent
PADDING = 2
BACKGROUND = (22, 24, 32)
FOREGROUND = (228, 229, 233)
CURSOR_COLOR = (255, 238, 170)
SELECTION_BACKGROUND = (23, 81, 107)
SEARCH_BACKGROUND = (255, 224, 130)
SEARCH_SELECTED_BACKGROUND = (242, 165, 126)
PALETTE_THEME_BACKGROUND = (54, 87, 129)
READONLY_THEME_BACKGROUND = (33, 128, 205)
SPLIT_THEME_DIVIDER = (190, 115, 185)
BELL_THEME_FILL = (33, 128, 205)
BELL_THEME_BORDER = (214, 106, 69)
COMMAND_EXIT_THEME_BACKGROUND = (33, 128, 205)
PROGRESS_THEME_TROUGH = (90, 67, 90)
PROGRESS_THEME_FILL = (33, 128, 205)
FONT_ZOOM_ACTIONS = (
    ("", None, 0), ("-larger", "1", 1), ("-restored", "2", 0), ("-smaller", "2", -1), ("-reset", "3", 0),
)
WALLPAPER_RELOAD_STAGES = ("", "-load", "-repeat", "-fade", "-replace", "-remove", "-restore")
SHADER_RELOAD_STAGES = ("", "-enable", "-chain", "-reorder", "-replace", "-remove", "-restore")
SCROLLBAR_FIXTURES = ("scrollbar", "scrollbar-themed")
SCROLLBAR_STAGES = ("", "-drag", "-top")
SCROLLBAR_THUMB = (33, 128, 205)
CAPTURE_STAGES = {
    **APPLICATION_STAGES,
    "font-zoom": tuple(stage for stage, _, _ in FONT_ZOOM_ACTIONS),
    "wallpaper-reload": WALLPAPER_RELOAD_STAGES,
    "shader-reload": SHADER_RELOAD_STAGES,
    **dict.fromkeys(SCROLLBAR_FIXTURES, SCROLLBAR_STAGES),
}
PREEDIT_FIXTURES = ("preedit-inline", "preedit-edge")
INTERACTIVE_FIXTURES = (
    "selection-wide", "wide-edit", "search-wrap", *PREEDIT_FIXTURES, *SCROLLBACK_FIXTURES, *RESIZE_FIXTURES,
)
LINK_PREVIEW_FIXTURES = ("link-preview", "link-preview-right")
READONLY_FIXTURES = ("readonly-overlay", "readonly-overlay-themed")
SPLIT_SEARCH_FIXTURES = ("split-search", "split-search-themed")
BELL_FIXTURES = ("visual-bell", "visual-bell-themed")
COMMAND_EXIT_FIXTURES = ("command-exit-banner", "command-exit-banner-themed")
PROGRESS_FIXTURES = ("progress-overlay", "progress-overlay-themed")
COMMAND_PALETTE_FIXTURES = (
    "command-palette", "command-palette-compact", "command-palette-resize", "command-palette-themed",
)
WINDOW_CHROME_FIXTURES = ("gtk-chrome-tabs", "gtk-chrome-native")
TITLE_DIALOG_ACTIONS = {"terminal-title": "prompt_surface_title", "tab-title": "prompt_tab_title"}
TERMINAL_DIALOG_FIXTURES = (*TITLE_DIALOG_ACTIONS, "close-confirmation")
WALLPAPER_OPTIONS = {
    "wallpaper-stretch": ("--background-image-fit=stretch",),
    "wallpaper-repeat": (
        "--background-image-fit=none",
        "--background-image-position=bottom-right",
        "--background-image-repeat=true",
        "--background-image-opacity=0.65",
    ),
}
FIXTURES = (
    "ansi", "decorations", "unicode", "grapheme-sequences", "font-zoom", "wide-wrap", "colored-line-erase",
    *INTERACTIVE_FIXTURES, *SCROLLBAR_FIXTURES, *SPLIT_SEARCH_FIXTURES, "split-close", *BELL_FIXTURES, *PROGRESS_FIXTURES,
    "resize-overlay", "key-state-overlay", *COMMAND_EXIT_FIXTURES,
    *LINK_PREVIEW_FIXTURES, *READONLY_FIXTURES, *COMMAND_PALETTE_FIXTURES, "clipboard-confirmation", "config-errors",
    *TITLE_DIALOG_ACTIONS, "gtk-toast",
    "terminal-sprites", "terminal-sprites-adjusted", *CURSOR_STYLES,
    "kitty", *KITTY_SCROLL_FIXTURES, "kitty-retransmit", "kitty-history", "kitty-layout", "kitty-cursor",
    "kitty-unicode", "kitty-unicode-pinned", "kitty-layers", "kitty-relative",
    "kitty-delete-selection", "kitty-delete-visible", "kitty-chunked", "kitty-animation",
    *WALLPAPER_OPTIONS, "wallpaper-reload", "ls", "git", "vim", *APPLICATION_STAGES, "shader", "shader-reload",
)
OPTIONS = (
    "--config-default-files=false",
    "--gtk-single-instance=false",
    "--window-decoration=none",
    "--scrollbar=never",
    "--window-save-state=never",
    "--resize-overlay=never",
    f"--window-width={GRID_COLUMNS}",
    f"--window-height={GRID_ROWS}",
    "--window-theme=dark",
    f"--window-padding-x={PADDING}",
    f"--window-padding-y={PADDING}",
    "--font-family=DejaVu Sans Mono",
    "--font-size=13",
    f"--background={bytes(BACKGROUND).hex()}",
    f"--foreground={bytes(FOREGROUND).hex()}",
    f"--cursor-color={bytes(CURSOR_COLOR).hex()}",
    "--cursor-style-blink=false",
    "--term=xterm-256color",
    "--shell-integration=none",
)


def prepare_fixtures(path):
    path.mkdir()
    listing = path / "listing"
    listing.mkdir()
    (listing / "directory").mkdir()
    executable = listing / "script.sh"
    executable.write_text("#!/bin/sh\nprintf '%s\\n' hello\n")
    executable.chmod(0o755)
    (listing / "note.txt").write_text("plain file\n")
    (path / "before.py").write_text(
        "from pathlib import Path\n\n"
        "def read(path: Path) -> str:\n"
        '    return path.read_text(encoding="utf-8")\n'
    )
    (path / "after.py").write_text(
        "from pathlib import Path\n\n"
        "def read(path: Path) -> bytes:\n"
        "    return path.read_bytes()\n"
    )
    (path / "tint.glsl").write_text(
        "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
        "    vec4 color = texture(iChannel0, fragCoord / iResolution.xy);\n"
        "    fragColor = vec4(color.rgb * vec3(0.7, 0.9, 1.0), color.a);\n"
        "}\n"
    )
    (path / "flip-rb.glsl").write_text(
        "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
        "    fragColor = texture(iChannel0, fragCoord / iResolution.xy).bgra;\n"
        "}\n"
    )
    wallpaper = Image.new("RGBA", (61, 39))
    wallpaper.putdata([
        (20 + x * 3, 30 + y * 4, 200 - x * 2, 70 + (x * 7 + y * 5) % 186)
        for y in range(wallpaper.height)
        for x in range(wallpaper.width)
    ])
    wallpaper.save(path / "wallpaper.png")


def fixture_args(name, work):
    blend = "native" if name == "ansi" or name.startswith("kitty") else "linear-corrected"
    options = [*OPTIONS, f"--alpha-blending={blend}", f"--working-directory={work}"]
    if name in APPLICATION_STAGES:
        return options
    if name == "font-zoom":
        options.extend((
            "--keybind=ctrl+alt+1=increase_font_size:3",
            "--keybind=ctrl+alt+2=decrease_font_size:3",
            "--keybind=ctrl+alt+3=reset_font_size",
        ))
    if name in ("wallpaper-reload", "shader-reload"):
        options.extend((
            f"--config-file={work / f'{name}.conf'}",
            "--keybind=ctrl+alt+r=reload_config",
            "--app-notifications=no-config-reload",
        ))
    if name == "tab-overview":
        program = shlex.join([sys.executable, str(PROBE / "fixtures.py"), name, str(work / "overview-tab-count")])
        return [
            *options, "--window-width=84", "--window-height=28", "--window-decoration=client",
            "--gtk-titlebar-style=tabs", "--window-show-tab-bar=always", "--window-theme=ghostty",
            "--window-titlebar-background=3b294f", "--window-titlebar-foreground=e2c6a5",
            "--keybind=ctrl+alt+t=new_tab", "--keybind=ctrl+alt+o=toggle_tab_overview", f"--command={program}",
        ]
    if name in TERMINAL_DIALOG_FIXTURES:
        action = TITLE_DIALOG_ACTIONS.get(name, "close_window")
        return [
            *options, "--window-width=72", "--window-height=22", "--confirm-close-surface=always",
            "--quit-after-last-window-closed=false", f"--keybind=ctrl+alt+t={action}",
            "-e", sys.executable, str(PROBE / "fixtures.py"), "terminal-dialog",
        ]
    if name == "config-errors":
        return [
            *options, "--initial-window=false", "--quit-after-last-window-closed=false",
            f"--config-file={work / 'diagnostics.conf'}",
        ]
    if name in WINDOW_CHROME_FIXTURES:
        program = shlex.join([sys.executable, str(PROBE / "fixtures.py"), "window-chrome"])
        options.extend((
            "--window-decoration=client", "--window-width=80", "--window-height=22",
            "--window-show-tab-bar=always", "--title=Chrome Fixture", "--keybind=ctrl+alt+t=new_tab",
            f"--command={program}",
        ))
        if name == "gtk-chrome-tabs":
            options.extend((
                "--gtk-titlebar-style=tabs", "--gtk-tabs-location=top", "--window-theme=ghostty",
                "--window-titlebar-background=3b294f", "--window-titlebar-foreground=e2c6a5",
            ))
        else:
            options.extend(("--gtk-titlebar-style=native", "--gtk-tabs-location=bottom", "--window-theme=light"))
        return options
    if name in (*SPLIT_SEARCH_FIXTURES, "split-close"):
        command = [sys.executable, str(PROBE / "fixtures.py"), "split-search"]
        if name == "split-close":
            options.extend((
                "--confirm-close-surface=false", "--keybind=ctrl+alt+h=goto_split:left",
                "--keybind=ctrl+alt+v=new_split:down", "--keybind=ctrl+alt+w=close_surface",
            ))
        if name == "split-search-themed":
            css = work / "split-theme.css"
            css.write_text(
                "widget.unfocused-split { background-color: #21b443; opacity: .43; }\n"
                f".window .split paned > separator {{ background-color: #{bytes(SPLIT_THEME_DIVIDER).hex()}; }}\n"
            )
            options.append(f"--gtk-custom-css={css}")
        return [
            *options, "--keybind=ctrl+alt+d=new_split:right", "--unfocused-split-fill=81315a",
            "--split-divider-color=47637c", f"--command={shlex.join([*command, 'Right'])}",
            "-e", *command, "Left",
        ]
    if name in BELL_FIXTURES:
        if name == "visual-bell-themed":
            css = work / "bell-theme.css"
            css.write_text(
                ".surface .bell-overlay { "
                f"background-color: #{bytes(BELL_THEME_FILL).hex()}; "
                f"border-color: #{bytes(BELL_THEME_BORDER).hex()}; border-radius: 9px; }}\n"
            )
            options.append(f"--gtk-custom-css={css}")
        return [
            *options, "--bell-features=border,no-title,no-attention",
            "-e", sys.executable, str(PROBE / "fixtures.py"), "visual-bell", str(work / "bell.trigger"),
        ]
    if name == "clipboard-confirmation":
        return [
            *options, "--window-width=85", "--window-height=28", "--clipboard-write=ask",
            "-e", sys.executable, str(PROBE / "fixtures.py"), name, str(work / "clipboard.trigger"),
        ]
    if name in COMMAND_EXIT_FIXTURES:
        themed = name == "command-exit-banner-themed"
        if themed:
            css = work / "command-exit-theme.css"
            css.write_text(
                ".child-exited.abnormal banner revealer > widget { "
                f"background-color: #{bytes(COMMAND_EXIT_THEME_BACKGROUND).hex()}; "
                "border-radius: 6px; }\n"
            )
            options.append(f"--gtk-custom-css={css}")
        return [
            *options, "--wait-after-command=true", "--confirm-close-surface=false",
            "-e", sys.executable, str(PROBE / "fixtures.py"), "command-exit-banner",
            str(work / "command-exit.trigger"), "7" if themed else "0",
        ]
    if name == "gtk-toast":
        return [
            *options, "--window-width=85", "--window-height=28", "--clipboard-write=allow",
            "--app-notifications=clipboard-copy",
            "-e", sys.executable, str(PROBE / "fixtures.py"), name, str(work / "toast.trigger"),
        ]
    if name == "resize-overlay":
        options.extend(("--resize-overlay=always", "--resize-overlay-duration=5s"))
    if name == "progress-overlay-themed":
        css = work / "progress-theme.css"
        css.write_text(
            ".surface progressbar.osd trough { "
            f"background-color: #{bytes(PROGRESS_THEME_TROUGH).hex()}; }}\n"
            ".surface progressbar.osd.error trough progress { "
            f"background-color: #{bytes(PROGRESS_THEME_FILL).hex()}; }}\n"
        )
        options.append(f"--gtk-custom-css={css}")
        name = "progress-overlay"
    if name == "key-state-overlay":
        options.extend(("--keybind=copy/escape=deactivate_key_table", "--keybind=ctrl+alt+k=activate_key_table:copy"))
    if name in LINK_PREVIEW_FIXTURES:
        options.append("--link-previews=true")
    if name in READONLY_FIXTURES:
        options.append("--keybind=ctrl+alt+o=toggle_readonly")
        if name == "readonly-overlay-themed":
            css = work / "readonly.css"
            css.write_text(
                ".surface .readonly_overlay {\n"
                f"  background: #{bytes(READONLY_THEME_BACKGROUND).hex()};\n"
                "  background-clip: padding-box;\n"
                "  border: 1.5px solid #917aa5;\n"
                "  outline: 1.5px solid #c89768;\n"
                "  border-radius: 5.5px;\n"
                "}\n"
            )
            options.append(f"--gtk-custom-css={css}")
    if name in COMMAND_PALETTE_FIXTURES:
        options.extend((
            "--title=Palette Fixture",
            "--keybind=ctrl+alt+p=toggle_command_palette",
            "--keybind=alt+a=text:paletteA", "--keybind=alt+b=text:paletteB",
            "--command-palette-entry=clear",
            "--command-palette-entry=title:Palette Probe Alpha,action:text:paletteA",
            "--command-palette-entry=title:Palette Probe Bravo,action:text:paletteB",
        ))
        if name == "command-palette-compact":
            options.extend(("--window-width=53", "--window-height=17", "--window-theme=light"))
        else:
            options.extend(("--window-width=85", "--window-height=25"))
        if name == "command-palette-themed":
            css = work / f"{name}-config" / "palette.css"
            options.append(f"--gtk-custom-css={css}")
    if name == "shader":
        options.extend(
            (
                f"--custom-shader={work / 'tint.glsl'}",
                f"--custom-shader={work / 'flip-rb.glsl'}",
                "--custom-shader-animation=false",
            )
        )
    if name == "shader-reload":
        options.append("--custom-shader-animation=false")
    if name == "vim":
        return [
            *options,
            "-e", shutil.which("vim"), "-Nu", "NONE", "-n", "-i", "NONE",
            "--cmd", "set shortmess+=F",
            "-c", "set number laststatus=2 noshowmode noruler",
            "-c", "syntax on", "before.py",
        ]
    if name in WALLPAPER_OPTIONS:
        options.extend([f"--background-image={work / 'wallpaper.png'}", *WALLPAPER_OPTIONS[name]])
        name = "ansi"
    if name == "preedit-inline":
        options.extend((f"--background-image={work / 'wallpaper.png'}", "--background-image-fit=stretch"))
    if name == "terminal-sprites-adjusted":
        options.extend(("--adjust-cell-width=1", "--adjust-cell-height=1"))
        name = "terminal-sprites"
    if name == "selection-wide":
        options.extend((
            "--copy-on-select=false",
            "--selection-foreground=fef1d4",
            f"--selection-background={bytes(SELECTION_BACKGROUND).hex()}",
        ))
    if name == "search-wrap":
        options.extend((
            "--keybind=ctrl+shift+f=search:needle",
            "--keybind=ctrl+shift+g=navigate_search:next",
            "--keybind=ctrl+alt+g=navigate_search:previous",
            f"--search-background={bytes(SEARCH_BACKGROUND).hex()}",
            f"--search-selected-background={bytes(SEARCH_SELECTED_BACKGROUND).hex()}",
        ))
    if name in SCROLLBACK_FIXTURES:
        output = "output" if name == "scrollback-follow-output" else "no-output"
        options.append(f"--scroll-to-bottom=no-keystroke,{output}")
    if name in SCROLLBAR_FIXTURES:
        options.append("--scrollbar=system")
        if name == "scrollbar-themed":
            css = work / "scrollbar.css"
            css.write_text(
                "scrollbar.vertical { min-width: 16px; padding: 2px; background-color: #43304a; }\n"
                "scrollbar.vertical trough { background-color: #534355; border-radius: 4px; }\n"
                "scrollbar.vertical slider { "
                f"background: #{bytes(SCROLLBAR_THUMB).hex()}; min-width: 12px; margin: 0; "
                "border: 1px solid #ffb94a; border-radius: 4px; }\n"
            )
            options.append(f"--gtk-custom-css={css}")
        name = "scrollbar"
    return [*options, "-e", sys.executable, str(PROBE / "fixtures.py"), name]


def capture_ghostty(command, helper, prefix, settle):
    with open_window(command, prefix.with_suffix(".log")) as (_, window):
        time.sleep(settle)
        with read_window(helper, window) as image:
            image.save(prefix.with_suffix(".png"))


def capture_font_zoom(binary, args, helper, output, app, settle, scale):
    sample_y = (PADDING + 1) * scale

    def marker_width(image):
        return sum(image.getpixel((x, sample_y)) == FONT_ZOOM_MARKER for x in range(image.width))

    # Use screenshot mode to suppress the debug banner while sampling live X11 frames.
    capture_args = [f"--screenshot={output / 'font-zoom-terminal.png'}"] if app == "witty" else []
    delay = len(FONT_ZOOM_ACTIONS) * (settle + 5) + 5
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(delay)}
    with open_window([binary, *capture_args, *args], output / f"font-zoom-{app}.log", env=env) as (_, window):
        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        original_width = 0
        for stage, key, relative_size in FONT_ZOOM_ACTIONS:
            path = output / f"font-zoom{stage}-{app}.png"
            if key:
                subprocess.run(["xdotool", "key", f"ctrl+alt+{key}"], check=True, timeout=5)

            def zoom_visible(image):
                width = marker_width(image)
                # The first row's solid marker scales with the cell width.
                direction = (width > original_width) - (width < original_width)
                return width > 0 and (original_width == 0 or direction == relative_size)

            capture_application_frame(helper, window, path, settle, zoom_visible)
            if not stage:
                with Image.open(path) as initial:
                    original_width = marker_width(initial)


def capture_wallpaper_reload(binary, args, helper, output, work, app, settle, scale):
    config = work / "wallpaper-reload.conf"
    config.write_text("")
    tile = work / "reload-tile.png"
    cover = work / "reload-cover.jpeg"
    tile_color = (114, 69, 180)
    with Image.new("RGB", (31, 19), tile_color) as png:
        png.save(tile)
    with Image.new("RGB", (19, 31), (36, 150, 107)) as jpeg:
        jpeg.save(cover, quality=92, progressive=True)

    natural = f"background-image = {tile}\nbackground-image-fit = none\n"
    repeated = natural + "background-image-repeat = true\n"
    empty = ("", lambda left, center: left == center == BACKGROUND)
    loaded = (natural, lambda left, center: left == BACKGROUND and center == tile_color)
    stages = (
        empty,
        loaded,
        (repeated, lambda left, center: left == center == tile_color),
        (repeated + "background-image-opacity = 0.6\n",
         lambda left, center: left == center and BACKGROUND[0] < left[0] < tile_color[0]),
        (f"background-image = {cover}\nbackground-image-fit = cover\n",
         lambda left, center: left == center and left[1] > 125),
        empty,
        loaded,
    )
    capture_args = [f"--screenshot={output / 'wallpaper-reload-terminal.png'}"] if app == "witty" else []
    delay = len(stages) * (settle + 5) + 5
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(delay)}
    with open_window([binary, *capture_args, *args], output / f"wallpaper-reload-{app}.log", env=env) as (_, window):
        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        for stage, (settings, ready) in zip(WALLPAPER_RELOAD_STAGES, stages, strict=True):
            if stage:
                config.write_text(settings)
                subprocess.run(["xdotool", "key", "ctrl+alt+r"], check=True, timeout=5)

            def rendered(image):
                if image.getpixel(((PADDING + 1) * scale, (PADDING + 1) * scale)) != WALLPAPER_RELOAD_MARKER:
                    return False
                y = image.height // 2
                return ready(image.getpixel((10 * scale, y)), image.getpixel((image.width // 2, y)))

            capture_application_frame(helper, window, output / f"wallpaper-reload{stage}-{app}.png", settle, rendered)


def capture_shader_reload(binary, args, helper, output, work, app, settle, scale):
    config = work / "shader-reload.conf"
    config.write_text("")
    flip = work / "flip-rb.glsl"
    rotate = work / "rotate-rgb.glsl"
    rotate.write_text(
        "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
        "    fragColor = texture(iChannel0, fragCoord / iResolution.xy).gbra;\n"
        "}\n"
    )
    r, g, b = SHADER_RELOAD_MARKER
    stages = (
        ((), (r, g, b)),
        ((flip,), (b, g, r)),
        ((flip, rotate), (g, r, b)),
        ((rotate, flip), (r, b, g)),
        ((rotate,), (g, b, r)),
        ((), (r, g, b)),
        ((flip,), (b, g, r)),
    )
    point = ((PADDING + 1) * scale, (PADDING + 1) * scale)
    # Capture the live window while screenshot mode suppresses the debug banner.
    capture_args = [f"--screenshot={output / 'shader-reload-terminal.png'}"] if app == "witty" else []
    delay = len(stages) * (settle + 5) + 5
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(delay)}
    with open_window([binary, *capture_args, *args], output / f"shader-reload-{app}.log", env=env) as (_, window):
        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        for stage, (paths, color) in zip(SHADER_RELOAD_STAGES, stages, strict=True):
            if stage:
                config.write_text("".join(f"custom-shader = {path}\n" for path in paths))
                subprocess.run(["xdotool", "key", "ctrl+alt+r"], check=True, timeout=5)
            capture_application_frame(helper, window, output / f"shader-reload{stage}-{app}.png", settle,
                                      lambda image: image.getpixel(point) == color)


def capture_scrollbar(binary, args, helper, output, name, app, settle, scale):
    themed = name == "scrollbar-themed"
    env = {
        **os.environ,
        "GTK_OVERLAY_SCROLLING": "0" if themed else "1",
        "SCREENSHOT_SETTLE_SECONDS": str(len(SCROLLBAR_STAGES) * (settle + 5) + 5),
    }
    capture_args = [f"--screenshot={output / f'{name}-terminal.png'}"] if app == "witty" else []
    with open_window([binary, *capture_args, *args], output / f"{name}-{app}.log", env=env) as (_, window):
        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        time.sleep(settle)
        with read_window(helper, window) as frame:
            width, height = frame.size

        def thumb_pixels(image, y):
            # The default dark-theme thumb is brighter than the empty cells underneath it.
            pixels = [(x, image.getpixel((x, y))) for x in range(width - 40 * scale, width)]
            return [x for x, rgb in pixels if rgb == SCROLLBAR_THUMB or (not themed and rgb[0] > 64)]

        point = ((PADDING + 1) * scale, (PADDING + 1) * scale)
        red, green, blue = SCROLLBAR_MARKER
        stages = (
            (height - 20 * scale, range(red + 3 * 48, red + 3 * 50)),
            (height // 2, range(red + 3, red + 3 * 48)),
            (20 * scale, range(red, red + 1)),
        )
        x = width - 4 * scale
        for stage, (y, marker_range) in zip(SCROLLBAR_STAGES, stages, strict=True):
            move = ["mousemove", "--window", window]
            keys = [*move, str(x), str(y)]
            if not stage:
                keys = [*move, str(width // 2), str(height // 2), *move, str(x), str(height - 10 * scale)]
            if stage == "-drag":
                keys = [*move, str(x), str(height - 20 * scale), "mousedown", "1", *keys]
            if stage == "-top":
                keys = [*move, str(x), str(5 * scale), "mouseup", "1",
                        *move, str(width // 2), str(height // 2), "sleep", "0.2",
                        *move, str(width - 4 * scale), str(height // 2)]
            subprocess.run(["xdotool", *keys], check=True, timeout=5)

            def rendered(image):
                color = image.getpixel(point)
                return color[0] in marker_range and color[1:] == (green, blue) and thumb_pixels(image, y)

            path = output / f"{name}{stage}-{app}.png"
            capture_application_frame(helper, window, path, settle, rendered)
            if not stage:
                with Image.open(path) as frame:
                    pixels = thumb_pixels(frame, y)
                    x = pixels[len(pixels) // 2]


def capture_split_search(binary, args, helper, prefix, settle, scale, config_dir, *, themed=False, witty=False):
    # Screenshot mode suppresses Witty's debug banner. The X11 capture
    # includes both panes and the search widget above the terminal content.
    capture_args = [f"--screenshot={prefix}-active-pane.png"] if witty else []
    env = {**os.environ, "XDG_CONFIG_HOME": str(config_dir), "SCREENSHOT_SETTLE_SECONDS": str(3 * settle + 8)}
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        time.sleep(settle)
        subprocess.run(
            ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window, "8", "80",
             "key", "ctrl+alt+d"], check=True, timeout=5,
        )
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            with read_window(helper, window) as image:
                if image.getpixel((3 * image.width // 4, image.height // 8))[:3] == SPLIT_RIGHT_COLOR:
                    probe = (image.width // 2, 10 * scale)
                    divider = image.getpixel(probe)
                    if themed:
                        dimming = image.getpixel((image.width // 6, image.height // 8))
                        # GTK can tint the handle with its focus highlight.
                        if divider[0] < 150 or divider[2] < 150 or dimming[1] <= dimming[0]:
                            raise RuntimeError("Custom CSS did not color the split divider and unfocused pane")
                    break
            time.sleep(0.05)
        else:
            raise RuntimeError("The right pane did not render after splitting")

        # Send the query without pauses between characters so GTK can paint the settled entry.
        subprocess.run(
            ["xdotool", "key", "ctrl+shift+f", "sleep", "0.25", "type", "--delay", "0", "pane"],
            check=True, timeout=5,
        )
        time.sleep(settle)
        with read_window(helper, window) as image:
            if image.getpixel(probe) == divider:
                raise RuntimeError("The search bar did not render in the split")
            image.save(prefix.with_suffix(".png"))


def capture_split_close(binary, args, helper, prefix, settle, scale, config_dir, *, witty=False):
    capture_args = [f"--screenshot={prefix}-active-pane.png"] if witty else []
    env = {**os.environ, "XDG_CONFIG_HOME": str(config_dir), "SCREENSHOT_SETTLE_SECONDS": "30"}
    left_color = (202, 122, 89)
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        time.sleep(settle)
        with read_window(helper, window) as image:
            width, height = image.size
        left = (width // 5, 24 * scale)
        right = (3 * width // 4, 24 * scale)
        bottom = (left[0], height // 2 + left[1])

        def command(*args):
            subprocess.run(["xdotool", *args], check=True, timeout=5)

        def frame_until(matches, message):
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline:
                with read_window(helper, window) as image:
                    if matches(image):
                        return image.copy()
                time.sleep(0.05)
            raise RuntimeError(message)

        command("windowfocus", "--sync", window, "mousemove", "--window", window,
                "8", str(80 * scale), "key", "ctrl+alt+d")
        frame_until(lambda image: image.getpixel(right) == SPLIT_RIGHT_COLOR, "The right pane did not open")
        command("key", "ctrl+alt+h")
        focused = frame_until(
            lambda image: image.getpixel(left) == left_color
            and 100 < image.getpixel(right)[2] < SPLIT_RIGHT_COLOR[2],
            "The left pane did not take focus",
        )
        right_dimmed = focused.getpixel(right)
        command("key", "ctrl+alt+v")
        frame_until(lambda image: image.getpixel(bottom) == SPLIT_RIGHT_COLOR, "The nested pane did not open")
        command("key", "ctrl+alt+w")
        time.sleep(settle)
        restored = frame_until(
            lambda image: image.getpixel(left) == left_color and image.getpixel(right) == right_dimmed,
            "The surviving panes did not redraw after closing the nested split",
        )
        restored.save(prefix.with_suffix(".png"))


def capture_visual_bell(binary, args, helper, prefix, settle, scale, *, themed=False, witty=False):
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty else []
    fade = max(settle, 0.65)
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(4 * fade + 8)}
    trigger = Path(args[-1])
    trigger.unlink(missing_ok=True)
    root = subprocess.check_output([helper, "--root-id"], text=True, timeout=5).strip()

    def ring():
        trigger.touch()
        deadline = time.monotonic() + 3
        while trigger.exists():
            if time.monotonic() >= deadline:
                raise RuntimeError("The bell fixture did not send BEL")
            time.sleep(0.05)
        time.sleep(fade)

    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        time.sleep(fade)
        with read_window(helper, window) as image:
            idle = image.tobytes()
            edge = (image.width // 2, scale)
            inside = (image.width // 2, 3 * scale)
            background = image.getpixel(inside)
        ring()
        with read_window(helper, window) as image:
            if image.tobytes() != idle:
                image.save(prefix.with_name(f"{prefix.name}-focused.png"))
                raise RuntimeError("BEL changed the appearance of the focused terminal")

        subprocess.run(["xdotool", "windowfocus", "--sync", root], check=True, timeout=5)
        time.sleep(0.1)
        ring()
        with read_window(helper, window) as image:
            image.save(prefix.with_suffix(".png"))
            body = image.getpixel(inside)
            border = image.getpixel(edge)
            if themed and (body, border) != (BELL_THEME_FILL, BELL_THEME_BORDER):
                raise RuntimeError("The themed visual bell colors did not render")
            if body == background or border == body:
                raise RuntimeError("BEL did not draw both the fill and border of the unfocused terminal")

        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() != idle:
                image.save(prefix.with_name(f"{prefix.name}-refocused.png"))
                raise RuntimeError("Refocusing the terminal did not clear the bell overlay")


def capture_progress_overlay(binary, args, helper, prefix, settle, scale, *, themed=False, witty=False):
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty else []
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(settle + 8)}
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        time.sleep(settle)
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            with read_window(helper, window) as image:
                fill = image.getpixel((image.width * 48 // 100, scale))
                rest = image.getpixel((image.width * 54 // 100, scale))
                ready = (fill, rest) == (PROGRESS_THEME_FILL, PROGRESS_THEME_TROUGH) if themed else fill != rest
                if ready:
                    image.save(prefix.with_suffix(".png"))
                    return
            time.sleep(0.05)
        message = "The themed progress colors did not render" if themed else "The paused progress fill did not reach 51%"
        raise RuntimeError(message)


def capture_command_exit_banner(binary, args, helper, prefix, settle, scale, *, themed=False):
    # Launch normally so the Close button can exit the app after capture.
    trigger = Path(args[-2])
    trigger.unlink(missing_ok=True)
    fade = max(settle, 0.65)
    with open_window([binary, *args], prefix.with_suffix(".log")) as (process, window):
        subprocess.run(["xdotool", "mousemove", "--window", window, "8", "80"], check=True, timeout=5)
        time.sleep(fade)
        with read_window(helper, window) as image:
            probe = (image.width // 8, image.height - 12 * scale)
            idle = image.getpixel(probe)
        trigger.touch()
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            with read_window(helper, window) as image:
                if image.getpixel(probe) != idle:
                    break
            time.sleep(0.05)
        else:
            raise RuntimeError("The command exit banner did not appear")
        time.sleep(fade)
        with read_window(helper, window) as image:
            image.save(prefix.with_suffix(".png"))
            if themed and image.getpixel(probe) != COMMAND_EXIT_THEME_BACKGROUND:
                raise RuntimeError("The themed command exit banner background did not render")
            close_x = image.width - 42 * scale
            close_y = image.height - 23 * scale
        subprocess.run(
            ["xdotool", "mousemove", "--window", window, str(close_x), str(close_y), "click", "1"],
            check=True, timeout=5,
        )
        if process.wait(timeout=5) != 0:
            raise RuntimeError("Closing the command exit banner failed")


def capture_mode_overlay(binary, args, helper, prefix, name, settle, scale, *, witty=False):
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty else []
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(settle + 8)}
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        time.sleep(settle)
        with read_window(helper, window) as idle:
            width, height = idle.size
        command = ["xdotool", "windowfocus", "--sync", window]
        if name == "resize-overlay":
            width += 100 * scale
            command.extend(("windowsize", "--sync", window, str(width), str(height)))
            y = height // 2
        else:
            command.extend(("key", "ctrl+alt+k"))
            y = height - 18 * scale
        subprocess.run(command, check=True, timeout=5)
        probe = (width // 2 - 10 * scale, y - 4 * scale, width // 2 + 10 * scale, y + 4 * scale)
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            with read_window(helper, window) as image:
                if image.size == (width, height) and image.crop(probe).getcolors(1) is None:
                    image.save(prefix.with_suffix(".png"))
                    return
            time.sleep(0.05)
        raise RuntimeError(f"The {name} did not render")


def capture_surface_badge(binary, args, helper, prefix, name, settle, scale, *, witty=False):
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty else []
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(settle + 8)}
    link_preview = name in LINK_PREVIEW_FIXTURES
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        time.sleep(settle)
        subprocess.run(
            ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window, "8", str(80 * scale)],
            check=True, timeout=5,
        )
        with read_window(helper, window) as idle:
            width, height = idle.size
            if link_preview:
                command = ["keydown", "Control_L", "mousemove", "--window", window, str(30 * scale), str(10 * scale)]
                if name == "link-preview-right":
                    # Hover the lower URL to move the preview away from the pointer.
                    command.extend(("sleep", "0.25", "mousemove", "--window", window,
                                    str(30 * scale), str(height - 11 * scale)))
                    region = (width // 2, height - 28 * scale, width, height)
                else:
                    region = (0, height - 28 * scale, width // 2, height)
            else:
                region = (width // 2, 0, width, 48 * scale)
                command = ["key", "ctrl+alt+o"]
            before = idle.crop(region)
            link_cells = (0, 0, width, 24 * scale)
            unhovered = idle.crop(link_cells) if name == "link-preview" else None
        try:
            subprocess.run(["xdotool", *command], check=True, timeout=5)
            # Read-only uses a 500 ms GTK crossfade.
            if not link_preview:
                time.sleep(0.65)
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline:
                with read_window(helper, window) as image:
                    # The preview label can appear before the terminal has painted the underline.
                    badge = image.crop(region)
                    preview_visible = ImageChops.difference(before, badge).getbbox()
                    if name == "readonly-overlay-themed":
                        colors = badge.getcolors(badge.width * badge.height)
                        preview_visible = any(color == READONLY_THEME_BACKGROUND for _, color in colors)
                    underline_visible = (
                        unhovered is None or ImageChops.difference(unhovered, image.crop(link_cells)).getbbox()
                    )
                    if preview_visible and underline_visible:
                        image.save(prefix.with_suffix(".png"))
                        return
                time.sleep(0.05)
            raise RuntimeError(f"The {name} did not render")
        finally:
            if link_preview:
                subprocess.run(["xdotool", "keyup", "Control_L"], check=True, timeout=5)


def capture_command_palette(binary, args, helper, prefix, settle, config_dir, *,
                            resize_scale=None, panel_color=None, witty=False):
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty else []
    fade = max(settle, 0.6)
    # Capture the whole settled dialog after editing the query.
    debug = ",".join(filter(None, (os.environ.get("GSK_DEBUG"), "full-redraw")))
    env = {**os.environ, "GSK_DEBUG": debug, "XDG_CONFIG_HOME": str(config_dir),
           "SCREENSHOT_SETTLE_SECONDS": str(4 * fade + 8)}
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        time.sleep(fade)
        with read_window(helper, window) as image:
            idle = image.tobytes()
            width, height = image.size
            # The command's echoed text occupies the far left of the second line.
            rest = (image.width // 4, 0, image.width, image.height)
            idle_rest = image.crop(rest).tobytes()
        subprocess.run(
            ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window, "14", "80",
             "key", "ctrl+alt+p"], check=True, timeout=5,
        )
        time.sleep(fade)
        with read_window(helper, window) as image:
            opened = image.tobytes()
        if idle == opened:
            raise RuntimeError("The command palette did not open")
        # Match the configured entries regardless of the built-in command catalog.
        subprocess.run(["xdotool", "type", "--delay", "0", "Palette Probe"], check=True, timeout=5)
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() in (opened, idle):
                raise RuntimeError("The command palette did not filter its rows")
            if panel_color is not None:
                colors = image.getcolors(image.width * image.height)
                if not any(color == panel_color for _, color in colors):
                    raise RuntimeError("The custom command palette background did not render")
            if resize_scale is None:
                image.save(prefix.with_suffix(".png"))
        if resize_scale is not None:
            subprocess.run(
                ["xdotool", "key", "ctrl+a", "type", "--delay", "0", "No matching item"],
                check=True, timeout=5,
            )
            time.sleep(fade)
            target = (width - 320 * resize_scale, height - 100 * resize_scale)
            subprocess.run(["xdotool", "windowsize", "--sync", window, *map(str, target)], check=True, timeout=5)
            time.sleep(fade)
            with read_window(helper, window) as image:
                if image.size != target:
                    raise RuntimeError("The window did not resize with the command palette open")
                image.save(prefix.with_suffix(".png"))
            subprocess.run(
                ["xdotool", "windowsize", "--sync", window, str(width), str(height), "key", "Escape"],
                check=True, timeout=5,
            )
            time.sleep(fade)
            with read_window(helper, window) as image:
                if image.tobytes() != idle:
                    raise RuntimeError("The command palette did not close after resizing")
            return
        subprocess.run(["xdotool", "key", "Return"], check=True, timeout=5)
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() == idle or image.crop(rest).tobytes() != idle_rest:
                raise RuntimeError("The selected command did not execute and close the palette")


def capture_window_chrome(binary, args, helper, prefix, settle):
    # Compare the whole settled frame after the tab bar changes.
    debug = ",".join(filter(None, (os.environ.get("GSK_DEBUG"), "full-redraw")))
    env = {**os.environ, "GSK_DEBUG": debug}
    with open_window([binary, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        subprocess.run(
            ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window, "14", "150"],
            check=True, timeout=5,
        )
        time.sleep(settle)
        with read_window(helper, window) as image:
            single_tab = image.tobytes()
        subprocess.run(["xdotool", "key", "ctrl+alt+t"], check=True, timeout=5)
        time.sleep(settle)
        with read_window(helper, window) as image:
            if image.tobytes() == single_tab:
                raise RuntimeError("Opening a second tab did not change the window chrome")
            image.save(prefix.with_suffix(".png"))


def capture_tab_overview(binary, args, helper, prefix, settle, scale, config_dir, counter):
    counter.write_text("0")
    fade = max(settle, 0.8)
    debug = ",".join(filter(None, (os.environ.get("GSK_DEBUG"), "full-redraw")))
    env = {**os.environ, "GSK_DEBUG": debug, "XDG_CONFIG_HOME": str(config_dir)}

    def xdotool(*command):
        return subprocess.check_output(["xdotool", *command], text=True, timeout=5).strip()

    with open_window([binary, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        xdotool("windowfocus", "--sync", window, "mousemove", "--window", window, "4", "10")
        time.sleep(fade)
        if xdotool("getwindowname", window) != "Tab 1":
            raise RuntimeError("The first overview tab did not start")
        xdotool("key", "ctrl+alt+t")
        time.sleep(fade)
        if xdotool("getwindowname", window) != "Tab 2":
            raise RuntimeError("The second overview tab did not start")
        with read_window(helper, window) as image:
            second = image.tobytes()

        xdotool("key", "ctrl+alt+o")
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() == second:
                raise RuntimeError("The tab overview did not open")
            image.save(prefix.with_suffix(".png"))
            width, height = image.size
        search = str(26 * scale)
        xdotool("mousemove", "--window", window, search, search, "click", "1")
        xdotool("type", "--delay", "0", "Tab 1")
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.getpixel((7 * width // 10, height // 3)) != image.getpixel((width // 10, height // 2)):
                raise RuntimeError("Searching the tab overview did not hide the second tab")
        xdotool("mousemove", "--window", window, str(3 * width // 10), str(height // 3), "click", "1")
        time.sleep(fade)
        if xdotool("getwindowname", window) != "Tab 1":
            raise RuntimeError("Selecting the tab overview result did not switch tabs")


def capture_clipboard_confirmation(binary, args, helper, prefix, settle, *, witty=False):
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty else []
    fade = max(settle, 0.65)
    trigger = Path(args[-1])
    trigger.unlink(missing_ok=True)
    debug = ",".join(filter(None, (os.environ.get("GSK_DEBUG"), "full-redraw")))
    env = {**os.environ, "GSK_DEBUG": debug, "SCREENSHOT_SETTLE_SECONDS": str(4 * fade + 8)}
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (process, window):
        subprocess.run(
            ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window, "14", "80"],
            check=True, timeout=5,
        )
        time.sleep(fade)
        with read_window(helper, window) as image:
            idle = image.tobytes()
        trigger.touch()
        deadline = time.monotonic() + 3
        while trigger.exists():
            if time.monotonic() >= deadline:
                raise RuntimeError("The clipboard fixture did not send the request")
            time.sleep(0.05)
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() == idle:
                raise RuntimeError("The clipboard confirmation did not open")
            image.save(prefix.with_suffix(".png"))
        subprocess.run(["xdotool", "key", "Escape"], check=True, timeout=5)
        time.sleep(fade)
        if process.poll() is not None:
            raise RuntimeError("Denying clipboard access exited the terminal")
        with read_window(helper, window) as image:
            if image.tobytes() != idle:
                raise RuntimeError("Denying clipboard access did not close the confirmation")


def capture_gtk_toast(binary, args, helper, prefix, settle):
    trigger = Path(args[-1])
    trigger.unlink(missing_ok=True)
    debug = ",".join(filter(None, (os.environ.get("GSK_DEBUG"), "full-redraw")))
    env = {**os.environ, "GSK_DEBUG": debug}
    with open_window([binary, *args], prefix.with_suffix(".log"), env=env) as (process, window):
        subprocess.run(
            ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window, "14", "80"],
            check=True, timeout=5,
        )
        time.sleep(max(settle, 0.65))
        with read_window(helper, window) as image:
            idle = image.tobytes()
        trigger.touch()
        deadline = time.monotonic() + 2
        while trigger.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        if trigger.exists():
            raise RuntimeError("The toast fixture did not send the clipboard clear request")
        # Let the entrance animation settle within the three-second timeout.
        time.sleep(0.75)
        if process.poll() is not None:
            raise RuntimeError("Clearing the clipboard exited the terminal")
        with read_window(helper, window) as image:
            if image.tobytes() == idle:
                raise RuntimeError("Clearing the clipboard did not show a toast")
            image.save(prefix.with_suffix(".png"))


def capture_config_errors(binary, args, helper, prefix, settle, scale):
    config = Path(args[-1].removeprefix("--config-file="))
    config.write_text("fixture-unknown-option = value\n")
    debug = ",".join(filter(None, (os.environ.get("GSK_DEBUG"), "full-redraw")))
    env = {**os.environ, "GSK_DEBUG": debug}
    with open_window([binary, *args], prefix.with_suffix(".log"), env=env) as (process, window):
        subprocess.run(
            ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window, "5", "10"],
            check=True, timeout=5,
        )
        time.sleep(settle)
        with read_window(helper, window) as image:
            width, height = image.size
            image.save(prefix.with_suffix(".png"))

        # Reload a repaired file and check that no diagnostics window remains.
        config.write_text("font-size = 13\n")
        subprocess.run(
            ["xdotool", "mousemove", "--window", window, str(3 * width // 4), str(height - 50 * scale),
             "click", "1"], check=True, timeout=5,
        )
        time.sleep(settle)
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError("Reloading the configuration exited the application")
            remaining = subprocess.run(
                ["xdotool", "search", "--onlyvisible", "--pid", str(process.pid), "--name", "Configuration Errors"],
                capture_output=True, timeout=5,
            )
            if not remaining.stdout:
                return
            time.sleep(0.05)
        raise RuntimeError("Reloading the repaired configuration left the diagnostics window open")


def capture_terminal_dialog(binary, args, helper, prefix, settle, config_dir, name, *, witty=False):
    # Closing the window is part of the close fixture, so launch it normally.
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty and name in TITLE_DIALOG_ACTIONS else []
    fade = max(settle, 0.65)
    debug = ",".join(filter(None, (os.environ.get("GSK_DEBUG"), "full-redraw")))
    env = {**os.environ, "GSK_DEBUG": debug, "XDG_CONFIG_HOME": str(config_dir),
           "SCREENSHOT_SETTLE_SECONDS": str(8 * fade + 8)}

    def xdotool(*command):
        return subprocess.check_output(["xdotool", *command], text=True, timeout=5).strip()

    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (process, window):
        xdotool("windowfocus", "--sync", window, "mousemove", "--window", window, "14", "80")
        time.sleep(fade)
        with read_window(helper, window) as image:
            idle = image.tobytes()
        xdotool("key", "ctrl+alt+t")
        time.sleep(fade)
        if name == "close-confirmation":
            # Expose the Cancel button's keyboard focus consistently.
            xdotool("key", "Tab", "shift+Tab")
            time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() == idle:
                raise RuntimeError(f"{name} did not open")
            image.save(prefix.with_suffix(".png"))
        xdotool("key", "Escape")
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() != idle:
                raise RuntimeError(f"Escape did not dismiss {name}")

        xdotool("key", "ctrl+alt+t")
        time.sleep(fade)
        if name in TITLE_DIALOG_ACTIONS:
            xdotool("key", "ctrl+a", "type", "--delay", "0", "Parity title")
            xdotool("key", "Return")
            time.sleep(fade)
            if xdotool("getwindowname", window) != "Parity title":
                raise RuntimeError(f"Enter did not apply the title in {name}")
            xdotool("key", "ctrl+alt+t")
            time.sleep(fade)
            xdotool("key", "ctrl+a", "key", "BackSpace", "key", "Return")
            time.sleep(fade)
            if xdotool("getwindowname", window) != "Initial title":
                raise RuntimeError("A blank title did not restore the default")
        else:
            xdotool("key", "Tab", "key", "Return")
            time.sleep(fade)
            windows = subprocess.run(
                ["xdotool", "search", "--onlyvisible", "--pid", str(process.pid)],
                capture_output=True, timeout=5,
            )
            if windows.stdout or process.poll() not in (None, 0):
                raise RuntimeError("Confirming close did not close the terminal window")


def drag_wide_selection(window, padding, cell_width, cell_height):
    # The emoji is in columns 13 and 14 (zero-based). Start on its
    # spacer tail and drag past the space in column 15.
    y = padding + 3 * cell_height + cell_height // 2
    x_start = padding + 14 * cell_width + cell_width // 4
    x_end = padding + 19 * cell_width + 4 * cell_width // 5
    probe = (padding + 15 * cell_width + cell_width // 2, y)
    subprocess.run(
        ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window,
         str(x_start), str(y), "mousedown", "1", "sleep", "0.1", "mousemove", "--window",
         window, str(x_end), str(y), "sleep", "0.1", "mouseup", "1"],
        check=True, timeout=5,
    )

    def rendered(image):
        return image.getpixel(probe)[:3] == SELECTION_BACKGROUND

    return rendered


def type_unicode_preedit(window, fixture, padding, cell_width, cell_height):
    # GTK's Unicode entry shows an underlined preview until Enter is pressed.
    subprocess.run(
        ["xdotool", "windowfocus", "--sync", window, "key", "ctrl+shift+u",
         "sleep", "0.1", "key", "--delay", "80", "2", "6", "0", "3"],
        check=True, timeout=5,
    )
    left, right, row = (16, 21, 2) if fixture == "preedit-inline" else (52, 60, 5)
    area = (padding + left * cell_width, padding + row * cell_height,
            padding + right * cell_width, padding + (row + 1) * cell_height)

    def rendered(image):
        crop = image.crop(area).convert("RGB")
        colors = crop.getcolors(crop.width * crop.height)
        return any(color == FOREGROUND and count >= 4 * cell_width for count, color in colors)

    return rendered


def edit_wrapped_wide(window, helper, padding, cell_width, cell_height):
    x = padding + (GRID_COLUMNS - 1) * cell_width + cell_width // 2

    def row_y(row):
        return padding + row * cell_height + cell_height // 2

    with read_window(helper, window) as image:
        if any(image.getpixel((x, row_y(row)))[:3] != WIDE_EDIT_BEFORE for row in (0, 2)):
            raise RuntimeError("The wrapped wide cells were missing before editing")
    subprocess.run(["xdotool", "windowfocus", "--sync", window, "key", "space"], check=True, timeout=5)

    def rendered(image):
        # Delete-character inserts a blank with the new background at the margin.
        return image.getpixel((x, row_y(3)))[:3] == WIDE_EDIT_AFTER

    return rendered


def navigate_search(window, helper, padding, cell_width, cell_height):
    x = padding + 9 * cell_width

    def has_match(image, row, color):
        y = padding + row * cell_height + cell_height // 2
        strip = image.crop((x, y, x + cell_width, y + 1)).convert("RGB")
        return any(rgb == color for _, rgb in strip.getcolors(cell_width))

    subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
    steps = (
        ("ctrl+shift+f", 7, SEARCH_BACKGROUND),
        ("ctrl+shift+g", 7, SEARCH_SELECTED_BACKGROUND),
        ("ctrl+alt+g", 0, SEARCH_SELECTED_BACKGROUND),
        ("ctrl+shift+g", 7, SEARCH_SELECTED_BACKGROUND),
    )
    for key, row, color in steps:
        subprocess.run(["xdotool", "key", key], check=True, timeout=5)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            with read_window(helper, window) as image:
                if has_match(image, row, color):
                    break
            time.sleep(0.05)
        else:
            raise RuntimeError(f"Search highlight did not reach row {row + 1} after {key}")

    def rendered(image):
        return has_match(image, 7, SEARCH_SELECTED_BACKGROUND) and has_match(image, 3, SEARCH_BACKGROUND)

    return rendered


def scroll_history(window, helper, padding, cell_width, cell_height):
    x = padding + cell_width // 2

    def has_marker(image, color):
        strip = image.crop((x, 0, x + 1, image.height)).convert("RGB")
        return any(pixel == color for _, pixel in strip.getcolors(image.height))

    with read_window(helper, window) as image:
        if not has_marker(image, SCROLLBACK_LAST_COLOR):
            raise RuntimeError("The last output row was missing before scrolling")
    subprocess.run(
        ["xdotool", "windowfocus", "--sync", window, "mousemove", "--window", window,
         str(padding + 5 * cell_width), str(padding + 5 * cell_height), "click", "--repeat", "2", "4"],
        check=True, timeout=5,
    )
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        with read_window(helper, window) as image:
            if not has_marker(image, SCROLLBACK_LAST_COLOR):
                break
        time.sleep(0.05)
    else:
        raise RuntimeError("The viewport did not move into scrollback")

    subprocess.run(["xdotool", "key", "space"], check=True, timeout=5)

    def rendered(image):
        return has_marker(image, SCROLLBACK_RECOLORED)

    return rendered


def resize_window(window, target, expected_color):
    subprocess.run(
        ["xdotool", "windowfocus", "--sync", window, "windowsize", "--sync", window,
         str(target[0]), str(target[1]), "sleep", "0.25"],
        check=True, timeout=5,
    )

    def rendered(image):
        if image.size != target:
            return False
        colors = image.convert("RGB").getcolors(4096)
        return colors is not None and any(color == expected_color for _, color in colors)

    return rendered


def capture_interactive(binary, args, helper, prefix, fixture, settle, scale, *, witty=False):
    png = prefix.with_suffix(".png")
    capture_args = [f"--screenshot={png}"] if witty else []
    env = os.environ.copy()
    if witty:
        env["SCREENSHOT_SETTLE_SECONDS"] = str(settle + 3)
    if fixture in PREEDIT_FIXTURES:
        env["GTK_IM_MODULE"] = "gtk-im-context-simple"
    log = prefix.with_suffix(".log")
    with open_window([binary, *capture_args, *args], log, env=env) as (process, window):
        time.sleep(settle)
        with read_window(helper, window) as image:
            padding = PADDING * scale
            cell_width = (image.width - 2 * padding) // GRID_COLUMNS
            cell_height = (image.height - 2 * padding) // GRID_ROWS
            window_height = image.height

        if fixture == "selection-wide":
            rendered = drag_wide_selection(window, padding, cell_width, cell_height)
        elif fixture == "wide-edit":
            rendered = edit_wrapped_wide(window, helper, padding, cell_width, cell_height)
        elif fixture == "search-wrap":
            rendered = navigate_search(window, helper, padding, cell_width, cell_height)
        elif fixture in SCROLLBACK_FIXTURES:
            rendered = scroll_history(window, helper, padding, cell_width, cell_height)
        elif fixture == "resize-pending-wrap":
            rendered = resize_window(window, (684 * scale, window_height), RESIZE_WRAP_COLOR)
        elif fixture in RESIZE_FIXTURES:
            rendered = resize_window(window, (412 * scale, 211 * scale), CURSOR_COLOR)
        else:
            rendered = type_unicode_preedit(window, fixture, padding, cell_width, cell_height)

        if witty:
            if process.wait(timeout=settle + 10) or not png.is_file():
                raise RuntimeError(f"Witty interactive capture failed. See {log}")
            with Image.open(png) as image:
                if rendered(image):
                    return
        else:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                with read_window(helper, window) as image:
                    image.save(png)
                    if rendered(image):
                        return
                time.sleep(0.05)
        raise RuntimeError(f"Interaction did not render for {fixture}. See {png} and {log}")


def compare(name, actual_path, expected_path, difference_path):
    with Image.open(actual_path) as png:
        actual = png.convert("RGBA")
    with Image.open(expected_path) as png:
        expected = png.convert("RGBA")
    actual_size = f"{actual.width}x{actual.height}"
    expected_size = f"{expected.width}x{expected.height}"
    actual_bytes = actual.tobytes()
    expected_bytes = expected.tobytes()
    if actual.size != expected.size:
        different = "size-mismatch"
    else:
        actual_pixels = memoryview(actual_bytes).cast("I")
        expected_pixels = memoryview(expected_bytes).cast("I")
        mask = bytes(255 if a != b else 0 for a, b in zip(actual_pixels, expected_pixels))
        count = mask.count(255)
        different = str(count)
        if count:
            Image.frombytes("L", actual.size, mask).save(difference_path)
        elif actual.getcolors(1) is not None:
            raise RuntimeError(f"{name} produced single-color captures. See {actual_path} and {expected_path}")
    return "\t".join(
        (
            name, actual_size, expected_size, different,
            hashlib.sha256(actual_bytes).hexdigest(),
            hashlib.sha256(expected_bytes).hexdigest(),
        )
    ), different == "0"


def run(witty, ghostty, output, settle, fixtures, scale=1):
    configure_xvfb_capture(scale)
    work = output / "fixtures"
    prepare_fixtures(work)
    prepare_applications(work, fixtures)
    helper = output / "window_ppm"
    build_window_reader(helper)
    write_versions(output, witty, ghostty)
    with (output / "versions.txt").open("a") as versions:
        versions.write(f"GTK scale: {scale}\n")
        versions.write(f"GTK renderer: {os.environ['GSK_RENDERER']}\n")
    print(f"Captures and logs: {output}", flush=True)
    matches = True
    with (output / "results.tsv").open("w") as report:
        header = "fixture\twitty_size\tghostty_size\tdiffering_pixels\twitty_rgba_sha256\tghostty_rgba_sha256"
        print(header, file=report)
        print(header, flush=True)
        for name in fixtures:
            args = fixture_args(name, work)
            actual = output / f"{name}-witty"
            expected = output / f"{name}-ghostty"
            if name == "less":
                capture_less(ghostty, args, helper, output, "ghostty", work, settle, scale, PADDING)
                capture_less(witty, args, helper, output, "witty", work, settle, scale, PADDING)
            elif name == "tmux":
                capture_tmux(ghostty, args, helper, output, "ghostty", work, settle, scale)
                capture_tmux(witty, args, helper, output, "witty", work, settle, scale)
            elif name == "font-zoom":
                capture_font_zoom(ghostty, args, helper, output, "ghostty", settle, scale)
                capture_font_zoom(witty, args, helper, output, "witty", settle, scale)
            elif name == "wallpaper-reload":
                capture_wallpaper_reload(ghostty, args, helper, output, work, "ghostty", settle, scale)
                capture_wallpaper_reload(witty, args, helper, output, work, "witty", settle, scale)
            elif name == "shader-reload":
                capture_shader_reload(ghostty, args, helper, output, work, "ghostty", settle, scale)
                capture_shader_reload(witty, args, helper, output, work, "witty", settle, scale)
            elif name in SCROLLBAR_FIXTURES:
                capture_scrollbar(ghostty, args, helper, output, name, "ghostty", settle, scale)
                capture_scrollbar(witty, args, helper, output, name, "witty", settle, scale)
            elif name in INTERACTIVE_FIXTURES:
                capture_interactive(ghostty, args, helper, expected, name, settle, scale)
                capture_interactive(witty, args, helper, actual, name, settle, scale, witty=True)
            elif name in (*SPLIT_SEARCH_FIXTURES, "split-close"):
                config_dir = work / f"{name}-config"
                gtk_config = config_dir / "gtk-4.0"
                gtk_config.mkdir(parents=True)
                (gtk_config / "settings.ini").write_text("[Settings]\ngtk-cursor-blink=false\n")
                if name == "split-close":
                    capture_split_close(ghostty, args, helper, expected, settle, scale, config_dir)
                    capture_split_close(witty, args, helper, actual, settle, scale, config_dir, witty=True)
                else:
                    themed = name == "split-search-themed"
                    capture_split_search(ghostty, args, helper, expected, settle, scale, config_dir, themed=themed)
                    capture_split_search(witty, args, helper, actual, settle, scale, config_dir, themed=themed, witty=True)
            elif name in BELL_FIXTURES:
                themed = name == "visual-bell-themed"
                capture_visual_bell(ghostty, args, helper, expected, settle, scale, themed=themed)
                capture_visual_bell(witty, args, helper, actual, settle, scale, themed=themed, witty=True)
            elif name in PROGRESS_FIXTURES:
                themed = name == "progress-overlay-themed"
                capture_progress_overlay(ghostty, args, helper, expected, settle, scale, themed=themed)
                capture_progress_overlay(witty, args, helper, actual, settle, scale, themed=themed, witty=True)
            elif name in COMMAND_EXIT_FIXTURES:
                themed = name == "command-exit-banner-themed"
                capture_command_exit_banner(ghostty, args, helper, expected, settle, scale, themed=themed)
                capture_command_exit_banner(witty, args, helper, actual, settle, scale, themed=themed)
            elif name in ("resize-overlay", "key-state-overlay"):
                capture_mode_overlay(ghostty, args, helper, expected, name, settle, scale)
                capture_mode_overlay(witty, args, helper, actual, name, settle, scale, witty=True)
            elif name in (*LINK_PREVIEW_FIXTURES, *READONLY_FIXTURES):
                capture_surface_badge(ghostty, args, helper, expected, name, settle, scale)
                capture_surface_badge(witty, args, helper, actual, name, settle, scale, witty=True)
            elif name in COMMAND_PALETTE_FIXTURES:
                config_dir = work / f"{name}-config"
                gtk_config = config_dir / "gtk-4.0"
                gtk_config.mkdir(parents=True)
                (gtk_config / "settings.ini").write_text("[Settings]\ngtk-cursor-blink=false\n")
                panel_color = None
                if name == "command-palette-themed":
                    panel_color = PALETTE_THEME_BACKGROUND
                    (config_dir / "palette.css").write_text(
                        f"dialog sheet.background {{ background: #{bytes(panel_color).hex()}; }}\n"
                        ".command-palette-search { background: #2180cd; }\n"
                        ".command-palette-view row:selected { background: #744821; }\n"
                    )
                resize_scale = scale if name == "command-palette-resize" else None
                capture_command_palette(ghostty, args, helper, expected, settle, config_dir,
                                        resize_scale=resize_scale, panel_color=panel_color)
                capture_command_palette(witty, args, helper, actual, settle, config_dir,
                                        resize_scale=resize_scale, panel_color=panel_color, witty=True)
            elif name in WINDOW_CHROME_FIXTURES:
                capture_window_chrome(ghostty, args, helper, expected, settle)
                capture_window_chrome(witty, args, helper, actual, settle)
            elif name == "tab-overview":
                config_dir = work / "tab-overview-config"
                gtk_config = config_dir / "gtk-4.0"
                gtk_config.mkdir(parents=True)
                (gtk_config / "settings.ini").write_text("[Settings]\ngtk-cursor-blink=false\n")
                counter = work / "overview-tab-count"
                capture_tab_overview(ghostty, args, helper, expected, settle, scale, config_dir, counter)
                capture_tab_overview(witty, args, helper, actual, settle, scale, config_dir, counter)
            elif name == "clipboard-confirmation":
                capture_clipboard_confirmation(ghostty, args, helper, expected, settle)
                capture_clipboard_confirmation(witty, args, helper, actual, settle, witty=True)
            elif name == "gtk-toast":
                capture_gtk_toast(ghostty, args, helper, expected, settle)
                capture_gtk_toast(witty, args, helper, actual, settle)
            elif name == "config-errors":
                capture_config_errors(ghostty, args, helper, expected, settle, scale)
                capture_config_errors(witty, args, helper, actual, settle, scale)
            elif name in TERMINAL_DIALOG_FIXTURES:
                config_dir = work / f"{name}-config"
                gtk_config = config_dir / "gtk-4.0"
                gtk_config.mkdir(parents=True)
                (gtk_config / "settings.ini").write_text("[Settings]\ngtk-cursor-blink=false\n")
                capture_terminal_dialog(ghostty, args, helper, expected, settle, config_dir, name)
                capture_terminal_dialog(witty, args, helper, actual, settle, config_dir, name, witty=True)
            else:
                capture_ghostty([ghostty, *args], helper, expected, settle)
                capture_witty(witty, args, actual, settle)
            for stage in CAPTURE_STAGES.get(name, ("",)):
                case = f"{name}{stage}"
                row, match = compare(
                    case, output / f"{case}-witty.png", output / f"{case}-ghostty.png",
                    output / f"{case}-diff.png",
                )
                print(row, file=report, flush=True)
                print(row, flush=True)
                matches = matches and match
    return 0 if matches else 1


def main():
    parser = argparse.ArgumentParser(description="Compare Witty and Ghostty terminal pixels in Xvfb.")
    parser.add_argument("witty", type=Path, help="path to the Witty executable")
    parser.add_argument("ghostty", type=Path, help="path to the Ghostty reference executable")
    parser.add_argument("--output", type=Path, help="new directory for screenshots, logs, and the report")
    parser.add_argument("--settle-seconds", type=float, default=1.0)
    parser.add_argument("--scale", type=int, choices=(1, 2), default=1, help="GTK display scale (default: 1)")
    parser.add_argument("--fixture", choices=(*FIXTURES, *WINDOW_CHROME_FIXTURES, "tab-overview", "close-confirmation"), action="append",
                        help="run only this fixture, repeatable")
    args = parser.parse_args()
    if sys.platform != "linux" or not os.environ.get("DISPLAY"):
        parser.error("run on Linux inside xvfb-run")
    if not math.isfinite(args.settle_seconds) or args.settle_seconds < 0:
        parser.error("--settle-seconds must be finite and nonnegative")
    for binary in (args.witty, args.ghostty):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            parser.error(f"expected an executable file at {binary}")
    fixtures = tuple(dict.fromkeys(args.fixture or FIXTURES))
    tools = ("cc", "xdotool", "env", *(name for name in fixtures if name in ("ls", "git", "vim", *APPLICATION_STAGES)))
    for tool in tools:
        if not shutil.which(tool):
            parser.error(f"missing {tool}")
    try:
        output = output_directory(args.output)
        return run(args.witty.resolve(), args.ghostty.resolve(), output, args.settle_seconds, fixtures, args.scale)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Render comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
