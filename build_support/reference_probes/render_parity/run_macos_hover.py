"""Compare the foreground macOS link preview in Witty and Ghostty."""

import argparse
import csv
import itertools
import os
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageChops

from capture import output_directory, write_versions
from run_macos import INPUT_FRAME_START, OPTIONS, WINDOW_COLUMNS, WINDOW_ROWS, build_probe_input


STATES = ("idle", "hover", "relocated", "rethemed", "returned", "cleared")
URL = b"https://example.org/path?q=parity"
HOVER_OPTIONS = (
    "--window-decoration=none",
    "--macos-titlebar-style=transparent",
    "--window-padding-x=0",
    "--window-padding-y=0",
    "--window-padding-balance=false",
    "--background=334d66",
    "--foreground=e2e4e7",
    "--link-previews=true",
    "--resize-overlay=never",
)


def prepare_fixture(directory):
    directory.mkdir(exist_ok=True)
    start = b"\x1b[2J\x1b[H\x1b[?25l\x1b[2;2H"
    last_row = f"\x1b[{WINDOW_ROWS};2H".encode("ascii")
    osc8 = b"\x1b]8;;" + URL + b"\x1b\\Example link\x1b]8;;\x1b\\"
    for kind, link in (("plain", URL), ("osc8", osc8)):
        (directory / f"{kind}.bin").write_bytes(start + link + last_row + link)
    (directory / "hover.sh").write_text(INPUT_FRAME_START + "exec /bin/sleep 20\n")


def capture(binary, app, work, helper, prefix, kind, appearance, color_space, opacity):
    ready = prefix.with_name(f"{prefix.name}.ready")
    ready.unlink(missing_ok=True)
    images = {state: prefix.parent / f"{prefix.name}-{state}.png" for state in STATES}
    for image in images.values():
        image.unlink(missing_ok=True)
    log_path = prefix.with_name(f"{prefix.name}.log")
    env = {
        **os.environ,
        "DYLD_INSERT_LIBRARIES": str(helper),
        "LC_ALL": "en_US.UTF-8",
        "WITTY_VIEWPORT_READY": str(ready),
        "WITTY_VIEWPORT_HOVER_CAPTURE": str(prefix),
    }
    env.pop("GHOSTTY_RESOURCES_DIR", None)
    env.pop("WITTY_VIEWPORT_HOVER_GHOSTTY", None)
    extra = ()
    if app == "ghostty":
        env["WITTY_VIEWPORT_HOVER_GHOSTTY"] = "1"
        extra = ("--auto-update=off", "--drag-handle=never")
    args = (*OPTIONS, *HOVER_OPTIONS, *extra, f"--window-theme={appearance}",
            f"--window-colorspace={color_space}", f"--background-opacity={opacity:g}",
            "-e", "/bin/sh", "hover.sh", kind, f"{WINDOW_ROWS} {WINDOW_COLUMNS}", ready)
    with log_path.open("wb") as log:
        result = subprocess.run([binary, *args], cwd=work, env=env, stdout=log,
                                stderr=subprocess.STDOUT, timeout=16)
    if result.returncode or not all(image.is_file() for image in images.values()):
        raise RuntimeError(f"{app} hover capture failed with status {result.returncode}. See {log_path}")
    frames = {}
    for state, image in images.items():
        with Image.open(image) as png:
            frames[state] = png.convert("RGBA")
    return frames


def verify_transitions(frames, fixture, opacity):
    idle = frames["idle"]
    width, height = idle.size
    if any(frame.size != (width, height) for frame in frames.values()):
        raise RuntimeError(f"Terminal size changed during {fixture}")
    alpha = idle.getpixel((width // 2, height // 2))[3]
    if abs(alpha - 255 * opacity) > 0.5:
        raise RuntimeError(f"Terminal background alpha {alpha} does not match opacity {opacity:g} in {fixture}")
    # The preview extends above the last text row. Check placement in that band.
    bounds = (0, 3 * height // 4, width, height - height // WINDOW_ROWS)
    strips = {state: frame.crop(bounds) for state, frame in frames.items()}
    idle_rgb = strips["idle"].convert("RGB")
    for state, on_right in (("hover", False), ("relocated", True), ("rethemed", True), ("returned", False)):
        box = ImageChops.difference(idle_rgb, strips[state].convert("RGB")).getbbox()
        if box:
            at_edge = box[0] > 0 and box[2] == width if on_right else box[0] == 0 and box[2] < width
        else:
            at_edge = False
        if not at_edge:
            side = "right" if on_right else "left"
            raise RuntimeError(f"Link preview did not appear on the {side} in {fixture} {state}")
        if strips[state].getchannel("A").getextrema() != (alpha, 255):
            raise RuntimeError(f"Link preview did not retain its opaque fill in {fixture} {state}")
    if strips["relocated"] == strips["rethemed"] or idle != frames["cleared"]:
        raise RuntimeError(f"Link preview did not repaint and clear in {fixture}")


def compare(witty, ghostty):
    if witty.size != ghostty.size:
        return "", ""
    r, g, b, a = ImageChops.difference(witty, ghostty).split()
    levels = ImageChops.lighter(ImageChops.lighter(r, g), ImageChops.lighter(b, a))
    return witty.width * witty.height - levels.histogram()[0], levels.getextrema()[1]


def run(witty, ghostty, output, tolerance):
    work = output / "fixtures"
    prepare_fixture(work)
    helper = build_probe_input(output)
    write_versions(output, witty, ghostty)
    report = output / "live-hover-parity.tsv"
    passed = True
    with report.open("w", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(("color_space", "background_opacity", "link", "appearance", "state", "witty_size",
                         "ghostty_size", "different_pixels", "maximum_channel_error", "status"))
        fixtures = itertools.product(("display-p3", "srgb"), (1.0, 0.7), ("plain", "osc8"), ("light", "dark"))
        for color_space, opacity, kind, appearance in fixtures:
            frames = {}
            for app, binary in (("ghostty", ghostty), ("witty", witty)):
                fixture = f"{color_space}-{opacity:g}-{kind}-{appearance}-{app}"
                frames[app] = capture(binary, app, work, helper, output / fixture, kind, appearance, color_space, opacity)
                verify_transitions(frames[app], fixture, opacity)
            for state in STATES:
                actual, reference = frames["witty"][state], frames["ghostty"][state]
                count, error = compare(actual, reference)
                within_limit = isinstance(error, int) and error <= tolerance
                writer.writerow((color_space, opacity, kind, appearance, state, f"{actual.width}x{actual.height}",
                                 f"{reference.width}x{reference.height}", count, error,
                                 "pass" if within_limit else "mismatch"))
                passed &= within_limit
    print(report)
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("witty", type=Path, help="path to the standalone Witty executable")
    parser.add_argument("ghostty", type=Path, help="path to the Ghostty app executable")
    parser.add_argument("--output", type=Path, help="directory for screenshots, logs, and the report")
    parser.add_argument("--maximum-channel-error", type=int, default=0,
                        help="largest permitted 8-bit channel difference (default 0)")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("run on macOS")
    if not 0 <= args.maximum_channel_error <= 255:
        parser.error("--maximum-channel-error must be between 0 and 255")
    for binary in (args.witty, args.ghostty):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            parser.error(f"expected an executable file at {binary}")
    try:
        return run(args.witty.resolve(), args.ghostty.resolve(), output_directory(args.output),
                   args.maximum_channel_error)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Live hover comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
