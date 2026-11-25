import argparse
import hashlib
import io
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from PIL import Image

from capture import capture_witty, configure_xvfb_capture, output_directory, write_versions
from fixtures import CURSOR_STYLES


PROBE = Path(__file__).resolve().parent
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
    "ansi", "decorations", "unicode", "wide-wrap", *CURSOR_STYLES,
    "kitty", *WALLPAPER_OPTIONS, "ls", "git", "vim", "shader",
)
OPTIONS = (
    "--config-default-files=false",
    "--gtk-single-instance=false",
    "--window-decoration=none",
    "--window-save-state=never",
    "--resize-overlay=never",
    "--window-width=60",
    "--window-height=12",
    "--window-theme=dark",
    "--window-padding-x=2",
    "--window-padding-y=2",
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
    blend = "native" if name in ("ansi", "kitty") else "linear-corrected"
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
    return [*options, "-e", sys.executable, str(PROBE / "fixtures.py"), name]


def find_window(process, log_path):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        status = process.poll()
        if status is not None:
            raise RuntimeError(f"Ghostty exited with status {status}. See {log_path}")
        windows = subprocess.run(
            ["xdotool", "search", "--onlyvisible", "--pid", str(process.pid)],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
        ).stdout.split()
        if windows:
            return windows[-1]
        time.sleep(0.05)
    raise RuntimeError(f"Ghostty did not open a visible window. See {log_path}")


def capture_ghostty(command, helper, prefix, settle):
    log_path = prefix.with_suffix(".log")
    with log_path.open("wb") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            window = find_window(process, log_path)
            time.sleep(settle)
            pixels = subprocess.check_output([helper, window], timeout=5)
            with Image.open(io.BytesIO(pixels)) as image:
                image.save(prefix.with_suffix(".png"))
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


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
    subprocess.run(
        ["cc", "-Wall", "-Wextra", "-Werror", PROBE / "window_ppm.c", "-o", helper, "-lX11"],
        check=True,
    )
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
