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

from capture import (
    build_window_reader, capture_witty, configure_xvfb_capture, open_window,
    output_directory, read_window, write_versions,
)
from fixtures import (
    CURSOR_STYLES, GRID_COLUMNS, GRID_ROWS, KITTY_SCROLL_FIXTURES, RESIZE_FIXTURES, RESIZE_WRAP_COLOR,
    SCROLLBACK_FIXTURES, SCROLLBACK_LAST_COLOR, SCROLLBACK_RECOLORED, SPLIT_RIGHT_COLOR,
    WIDE_EDIT_AFTER, WIDE_EDIT_BEFORE,
)


PROBE = Path(__file__).resolve().parent
PADDING = 2
FOREGROUND = (228, 229, 233)
CURSOR_COLOR = (255, 238, 170)
SELECTION_BACKGROUND = (23, 81, 107)
SEARCH_BACKGROUND = (255, 224, 130)
SEARCH_SELECTED_BACKGROUND = (242, 165, 126)
PREEDIT_FIXTURES = ("preedit-inline", "preedit-edge")
INTERACTIVE_FIXTURES = (
    "selection-wide", "wide-edit", "search-wrap", *PREEDIT_FIXTURES, *SCROLLBACK_FIXTURES, *RESIZE_FIXTURES,
)
LINK_PREVIEW_FIXTURES = ("link-preview", "link-preview-right")
COMMAND_PALETTE_FIXTURES = ("command-palette", "command-palette-compact")
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
    "ansi", "decorations", "unicode", "grapheme-sequences", "wide-wrap", "colored-line-erase",
    *INTERACTIVE_FIXTURES, "split-search", "visual-bell", "progress-overlay", "resize-overlay", "key-state-overlay",
    *LINK_PREVIEW_FIXTURES, "readonly-overlay", *COMMAND_PALETTE_FIXTURES,
    "terminal-sprites", "terminal-sprites-adjusted", *CURSOR_STYLES,
    "kitty", *KITTY_SCROLL_FIXTURES, "kitty-retransmit", "kitty-history", "kitty-layout", "kitty-cursor",
    "kitty-unicode", "kitty-unicode-pinned", "kitty-layers", "kitty-relative",
    "kitty-delete-selection", "kitty-delete-visible", "kitty-chunked", "kitty-animation",
    *WALLPAPER_OPTIONS, "ls", "git", "vim", "shader",
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
    "--background=161820",
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
    if name == "split-search":
        command = [sys.executable, str(PROBE / "fixtures.py"), name]
        return [
            *options, "--keybind=ctrl+alt+d=new_split:right", "--unfocused-split-fill=81315a",
            "--split-divider-color=47637c", f"--command={shlex.join([*command, 'Right'])}",
            "-e", *command, "Left",
        ]
    if name == "visual-bell":
        return [
            *options, "--bell-features=border,no-title,no-attention",
            "-e", sys.executable, str(PROBE / "fixtures.py"), name, str(work / "bell.trigger"),
        ]
    if name == "resize-overlay":
        options.extend(("--resize-overlay=always", "--resize-overlay-duration=5s"))
    if name == "key-state-overlay":
        options.extend(("--keybind=copy/escape=deactivate_key_table", "--keybind=ctrl+alt+k=activate_key_table:copy"))
    if name in LINK_PREVIEW_FIXTURES:
        options.append("--link-previews=true")
    if name == "readonly-overlay":
        options.append("--keybind=ctrl+alt+o=toggle_readonly")
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
    if name == "shader":
        options.extend(
            (
                f"--custom-shader={work / 'tint.glsl'}",
                f"--custom-shader={work / 'flip-rb.glsl'}",
                "--custom-shader-animation=false",
            )
        )
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
    return [*options, "-e", sys.executable, str(PROBE / "fixtures.py"), name]


def capture_ghostty(command, helper, prefix, settle):
    with open_window(command, prefix.with_suffix(".log")) as (_, window):
        time.sleep(settle)
        with read_window(helper, window) as image:
            image.save(prefix.with_suffix(".png"))


def capture_split_search(binary, args, helper, prefix, settle, scale, config_dir, *, witty=False):
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


def capture_visual_bell(binary, args, helper, prefix, settle, scale, *, witty=False):
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
            if body == background or image.getpixel(edge) == body:
                raise RuntimeError("BEL did not draw both the fill and border of the unfocused terminal")

        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() != idle:
                image.save(prefix.with_name(f"{prefix.name}-refocused.png"))
                raise RuntimeError("Refocusing the terminal did not clear the bell overlay")


def capture_progress_overlay(binary, args, helper, prefix, settle, scale, *, witty=False):
    capture_args = [f"--screenshot={prefix}-terminal.png"] if witty else []
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(settle + 8)}
    with open_window([binary, *capture_args, *args], prefix.with_suffix(".log"), env=env) as (_, window):
        time.sleep(settle)
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            with read_window(helper, window) as image:
                fill = image.getpixel((image.width * 48 // 100, scale))
                rest = image.getpixel((image.width * 54 // 100, scale))
                if fill != rest:
                    image.save(prefix.with_suffix(".png"))
                    return
            time.sleep(0.05)
        raise RuntimeError("The paused progress fill did not reach 51%")


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
        try:
            subprocess.run(["xdotool", *command], check=True, timeout=5)
            # Read-only uses a 500 ms GTK crossfade.
            if not link_preview:
                time.sleep(0.65)
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline:
                with read_window(helper, window) as image:
                    if ImageChops.difference(before, image.crop(region)).getbbox():
                        image.save(prefix.with_suffix(".png"))
                        return
                time.sleep(0.05)
            raise RuntimeError(f"The {name} did not render")
        finally:
            if link_preview:
                subprocess.run(["xdotool", "keyup", "Control_L"], check=True, timeout=5)


def capture_command_palette(binary, args, helper, prefix, settle, config_dir, *, witty=False):
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
            image.save(prefix.with_suffix(".png"))
        subprocess.run(["xdotool", "key", "Return"], check=True, timeout=5)
        time.sleep(fade)
        with read_window(helper, window) as image:
            if image.tobytes() == idle or image.crop(rest).tobytes() != idle_rest:
                raise RuntimeError("The selected command did not execute and close the palette")


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
            if name in INTERACTIVE_FIXTURES:
                capture_interactive(ghostty, args, helper, expected, name, settle, scale)
                capture_interactive(witty, args, helper, actual, name, settle, scale, witty=True)
            elif name == "split-search":
                config_dir = work / "split-search-config"
                gtk_config = config_dir / "gtk-4.0"
                gtk_config.mkdir(parents=True)
                (gtk_config / "settings.ini").write_text("[Settings]\ngtk-cursor-blink=false\n")
                capture_split_search(ghostty, args, helper, expected, settle, scale, config_dir)
                capture_split_search(witty, args, helper, actual, settle, scale, config_dir, witty=True)
            elif name == "visual-bell":
                capture_visual_bell(ghostty, args, helper, expected, settle, scale)
                capture_visual_bell(witty, args, helper, actual, settle, scale, witty=True)
            elif name == "progress-overlay":
                capture_progress_overlay(ghostty, args, helper, expected, settle, scale)
                capture_progress_overlay(witty, args, helper, actual, settle, scale, witty=True)
            elif name in ("resize-overlay", "key-state-overlay"):
                capture_mode_overlay(ghostty, args, helper, expected, name, settle, scale)
                capture_mode_overlay(witty, args, helper, actual, name, settle, scale, witty=True)
            elif name in (*LINK_PREVIEW_FIXTURES, "readonly-overlay"):
                capture_surface_badge(ghostty, args, helper, expected, name, settle, scale)
                capture_surface_badge(witty, args, helper, actual, name, settle, scale, witty=True)
            elif name in COMMAND_PALETTE_FIXTURES:
                config_dir = work / f"{name}-config"
                gtk_config = config_dir / "gtk-4.0"
                gtk_config.mkdir(parents=True)
                (gtk_config / "settings.ini").write_text("[Settings]\ngtk-cursor-blink=false\n")
                capture_command_palette(ghostty, args, helper, expected, settle, config_dir)
                capture_command_palette(witty, args, helper, actual, settle, config_dir, witty=True)
            else:
                capture_ghostty([ghostty, *args], helper, expected, settle)
                capture_witty(witty, args, actual, settle)
            row, match = compare(
                name, actual.with_suffix(".png"), expected.with_suffix(".png"),
                output / f"{name}-diff.png",
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
    parser.add_argument("--fixture", choices=FIXTURES, action="append", help="run only this fixture, repeatable")
    args = parser.parse_args()
    if sys.platform != "linux" or not os.environ.get("DISPLAY"):
        parser.error("run on Linux inside xvfb-run")
    if not math.isfinite(args.settle_seconds) or args.settle_seconds < 0:
        parser.error("--settle-seconds must be finite and nonnegative")
    for binary in (args.witty, args.ghostty):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            parser.error(f"expected an executable file at {binary}")
    fixtures = tuple(dict.fromkeys(args.fixture or FIXTURES))
    tools = ("cc", "xdotool", *(name for name in fixtures if name in ("ls", "git", "vim")))
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
