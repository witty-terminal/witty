"""Compare live macOS Find captures in Witty and Ghostty."""

import argparse
import csv
import os
from pathlib import Path
import subprocess
import sys

from PIL import Image

from capture import compare_rgba, output_directory, write_versions
from run_macos import INPUT_FRAME_START, OPTIONS, WINDOW_COLUMNS, WINDOW_ROWS, build_probe_input


STATES = ("closed", "selected", "typing", "unfocused")
PROFILES = (("display-p3", 1), ("display-p3", 0), ("srgb", 0.7))
FIND_OPTIONS = (
    "--window-decoration=none", "--macos-titlebar-style=transparent", "--resize-overlay=never",
    "--window-padding-x=0", "--window-padding-y=0", "--window-padding-balance=false",
    "--background=ffffff", "--background-blur=0", "--keybind=f7=start_search",
)


def capture(binary, app, work, library, prefix, appearance, color_space, opacity):
    ready = prefix.with_suffix(".ready")
    images = {state: prefix.with_name(f"{prefix.name}-{state}.png") for state in STATES}
    for path in (*images.values(), ready):
        path.unlink(missing_ok=True)
    env = {**os.environ, "DYLD_INSERT_LIBRARIES": str(library), "LC_ALL": "en_US.UTF-8",
           "WITTY_VIEWPORT_FIND_CAPTURE": str(prefix), "WITTY_VIEWPORT_READY": str(ready)}
    env.pop("GHOSTTY_RESOURCES_DIR", None)
    env.pop("WITTY_VIEWPORT_HOVER_GHOSTTY", None)
    extra = ()
    if app == "ghostty":
        env["WITTY_VIEWPORT_HOVER_GHOSTTY"] = "1"
        extra = ("--auto-update=off", "--drag-handle=never")
    args = (*OPTIONS, *FIND_OPTIONS, *extra, f"--window-theme={appearance}",
            f"--window-colorspace={color_space}", f"--background-opacity={opacity:g}",
            "-e", "/bin/sh", "find.sh", "find", f"{WINDOW_ROWS} {WINDOW_COLUMNS}", ready)
    log_path = prefix.with_suffix(".log")
    with log_path.open("wb") as log:
        result = subprocess.run([binary, *args], cwd=work, env=env, stdout=log,
                                stderr=subprocess.STDOUT, timeout=16)
    if result.returncode or not all(image.is_file() for image in images.values()):
        raise RuntimeError(f"{app} Find capture failed with status {result.returncode}. See {log_path}")
    frames = {}
    for state, image in images.items():
        with Image.open(image) as png:
            frames[state] = png.convert("RGBA")
    if frames["closed"] == frames["selected"] or frames["selected"] == frames["typing"]:
        raise RuntimeError(f"Find overlay did not open or update in {prefix.name}. See {log_path}")
    return frames


def run(witty, ghostty, output):
    work = output / "fixtures"
    work.mkdir(exist_ok=True)
    (work / "find.sh").write_text(INPUT_FRAME_START + "exec /bin/sleep 20\n")
    (work / "find.bin").write_text(
        "\x1b[?25l\x1b[2J\x1b[H\x1b[2;2Hneedle first\x1b[4;2Hsecond needle"
        "\x1b[7;2Hthird needle\x1b[10;2Hspecial café ✨\r\n", encoding="utf-8",
    )
    helper = build_probe_input(output)
    write_versions(output, witty, ghostty)
    report = output / "live-find-parity.tsv"
    passed = True
    with report.open("w", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("color_space", "background_opacity", "appearance", "state", "witty_size",
                         "ghostty_size", "different_pixels", "maximum_channel_error", "status"))
        for color_space, opacity in PROFILES:
            for appearance in ("light", "dark"):
                prefix = f"{color_space}-{opacity:g}-{appearance}"
                reference = capture(ghostty, "ghostty", work, helper, output / f"{prefix}-ghostty",
                                    appearance, color_space, opacity)
                current = capture(witty, "witty", work, helper, output / f"{prefix}-witty",
                                  appearance, color_space, opacity)
                for state in STATES:
                    actual, expected = current[state], reference[state]
                    count, error = compare_rgba(actual, expected)
                    matches = error == 0
                    writer.writerow((color_space, opacity, appearance, state, f"{actual.width}x{actual.height}",
                                     f"{expected.width}x{expected.height}", count, error,
                                     "pass" if matches else "mismatch"))
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
        print(f"Live Find comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
