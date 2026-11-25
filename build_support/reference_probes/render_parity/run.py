import argparse
import hashlib
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from PIL import Image

from capture import (
    build_window_reader, capture_witty, configure_xvfb_capture, open_window,
    output_directory, read_window, write_versions,
)
from fixtures import CURSOR_STYLES, GRID_COLUMNS, GRID_ROWS, KITTY_SCROLL_FIXTURES


PROBE = Path(__file__).resolve().parent
PADDING = 2
SELECTION_BACKGROUND = (23, 81, 107)
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
    "ansi", "decorations", "unicode", "wide-wrap", "selection-wide",
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
    "--foreground=e4e5e9",
    "--cursor-color=ffeeaa",
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
    if name == "terminal-sprites-adjusted":
        options.extend(("--adjust-cell-width=1", "--adjust-cell-height=1"))
        name = "terminal-sprites"
    if name == "selection-wide":
        options.extend((
            "--copy-on-select=false",
            "--selection-foreground=fef1d4",
            f"--selection-background={bytes(SELECTION_BACKGROUND).hex()}",
        ))
    return [*options, "-e", sys.executable, str(PROBE / "fixtures.py"), name]


def capture_ghostty(command, helper, prefix, settle):
    with open_window(command, prefix.with_suffix(".log")) as (_, window):
        time.sleep(settle)
        with read_window(helper, window) as image:
            image.save(prefix.with_suffix(".png"))


def capture_wide_selection(binary, args, helper, prefix, settle, scale, *, witty=False):
    png = prefix.with_suffix(".png")
    capture_args = [f"--screenshot={png}"] if witty else []
    env = {**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(settle + 3)} if witty else None
    log = prefix.with_suffix(".log")
    with open_window([binary, *capture_args, *args], log, env=env) as (process, window):
        time.sleep(settle)
        with read_window(helper, window) as image:
            padding = PADDING * scale
            cell_width = (image.width - 2 * padding) // GRID_COLUMNS
            cell_height = (image.height - 2 * padding) // GRID_ROWS

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

        if witty:
            if process.wait(timeout=settle + 10) or not png.is_file():
                raise RuntimeError(f"Witty selection capture failed. See {log}")
            with Image.open(png) as image:
                if image.getpixel(probe)[:3] == SELECTION_BACKGROUND:
                    return
        else:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                with read_window(helper, window) as image:
                    image.save(png)
                    if image.getpixel(probe)[:3] == SELECTION_BACKGROUND:
                        return
                time.sleep(0.05)
        raise RuntimeError(f"Mouse drag did not highlight the fixture text. See {png} and {log}")


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
            if name == "selection-wide":
                capture_wide_selection(ghostty, args, helper, expected, settle, scale)
                capture_wide_selection(witty, args, helper, actual, settle, scale, witty=True)
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
