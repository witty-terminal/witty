"""Compare terminal pixels after the macOS window compositor presents them."""

import argparse
import csv
import os
from pathlib import Path
import subprocess
import sys

from PIL import Image

from capture import compare_rgba, output_directory, write_versions
from run_macos import INPUT_FRAME_START, OPTIONS, WINDOW_COLUMNS, WINDOW_ROWS, build_probe_input


PROFILES = (
    ("display-p3", 1, False),
    ("display-p3", 0.55, False),
    ("display-p3", 0, False),
    ("srgb", 1, False),
    ("srgb", 0.7, True),
)


def capture(binary, work, library, prefix, profile, ghostty=False):
    color_space, opacity, opacity_cells = profile
    ready = prefix.with_suffix(".ready")
    image = prefix.with_name(f"{prefix.name}-window.png")
    env = {**os.environ, "DYLD_INSERT_LIBRARIES": str(library), "LC_ALL": "en_US.UTF-8",
           "WITTY_VIEWPORT_PRESENTATION_CAPTURE": str(prefix), "WITTY_VIEWPORT_READY": str(ready)}
    env.pop("GHOSTTY_RESOURCES_DIR", None)
    env.pop("WITTY_VIEWPORT_HOVER_GHOSTTY", None)
    extra = ()
    if ghostty:
        env["WITTY_VIEWPORT_HOVER_GHOSTTY"] = "1"
        extra = ("--auto-update=off", "--drag-handle=never")
    args = (*OPTIONS, *extra, "--window-decoration=none", "--background-blur=0",
            f"--window-colorspace={color_space}", f"--background-opacity={opacity:g}",
            f"--background-opacity-cells={str(opacity_cells).lower()}",
            "-e", "/bin/sh", "presentation.sh", "presentation", f"{WINDOW_ROWS} {WINDOW_COLUMNS}", ready)
    log_path = prefix.with_suffix(".log")
    with log_path.open("wb") as log:
        result = subprocess.run([binary, *args], cwd=work, env=env, stdout=log,
                                stderr=subprocess.STDOUT, timeout=16)
    if result.returncode or not image.is_file():
        raise RuntimeError(f"Capture failed for {prefix.name} with status {result.returncode}. See {log_path}")
    with Image.open(image) as png:
        return png.convert("RGBA")


def run(witty, ghostty, output):
    work = output / "fixtures"
    work.mkdir()
    (work / "presentation.sh").write_text(INPUT_FRAME_START + "exec /bin/sleep 20\n")
    (work / "presentation.bin").write_text(
        "\x1b[?25l\x1b[2J\x1b[H\x1b[1;31mHello\x1b[0m\r\nUTF-8 • 😄\r\n"
        "\x1b[48;2;27;75;116m colored background \x1b[0m\r\n", encoding="utf-8",
    )
    helper = build_probe_input(output)
    write_versions(output, witty, ghostty)
    report = output / "live-presentation-parity.tsv"
    passed = True
    with report.open("w", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("color_space", "background_opacity", "opacity_cells", "witty_size",
                         "ghostty_size", "different_pixels", "maximum_channel_error", "status"))
        for profile in PROFILES:
            color_space, opacity, opacity_cells = profile
            name = f"{color_space}-{opacity:g}"
            expected = capture(ghostty, work, helper, output / f"{name}-ghostty", profile, ghostty=True)
            actual = capture(witty, work, helper, output / f"{name}-witty", profile)
            count, error = compare_rgba(actual, expected)
            matches = error == 0
            writer.writerow((*profile, f"{actual.width}x{actual.height}", f"{expected.width}x{expected.height}",
                             count, error, "pass" if matches else "mismatch"))
            passed &= matches
    print(report)
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("witty", type=Path, help="path to the standalone Witty executable")
    parser.add_argument("ghostty", type=Path, help="path to the Ghostty app executable")
    parser.add_argument("--output", type=Path, help="directory for screenshots, logs, and the report")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("run on macOS")
    for binary in (args.witty, args.ghostty):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            parser.error(f"expected an executable file at {binary}")
    try:
        return run(args.witty.resolve(), args.ghostty.resolve(), output_directory(args.output))
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Window presentation comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
