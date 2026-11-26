"""Compare native scrollbar drags in Witty and Ghostty."""

import argparse
import csv
import os
from pathlib import Path
import subprocess
import sys

from PIL import Image

from capture import compare_rgba, output_directory, write_versions
from run_macos import INPUT_FRAME_START, OPTIONS, WINDOW_COLUMNS, WINDOW_ROWS, build_probe_input


STATES = ("middle", "top", "bottom")
CASES = {
    "dark": (),
    "light": ("--background=e3ece5", "--foreground=262535", "--window-theme=light"),
    "translucent": ("--background=29415a", "--foreground=f4e3dd", "--background-opacity=0.7", "--window-colorspace=srgb"),
}
SCROLLBAR_OPTIONS = (
    "--window-decoration=none",
    "--macos-titlebar-style=transparent",
    "--window-padding-x=0",
    "--window-padding-y=0",
    "--window-padding-balance=false",
    "--resize-overlay=never",
    "--scrollbar=system",
)


def capture(binary, app, helper, prefix, work, options):
    images = {state: prefix.with_name(f"{prefix.name}-{state}.png") for state in STATES}
    ready = prefix.with_suffix(".ready")
    for path in (*images.values(), ready):
        path.unlink(missing_ok=True)
    env = {
        **os.environ,
        "DYLD_INSERT_LIBRARIES": str(helper),
        "LC_ALL": "en_US.UTF-8",
        "WITTY_VIEWPORT_READY": str(ready),
        "WITTY_VIEWPORT_SCROLLBAR_CAPTURE": str(prefix),
    }
    env.pop("GHOSTTY_RESOURCES_DIR", None)
    env.pop("WITTY_VIEWPORT_HOVER_GHOSTTY", None)
    extra = ()
    if app == "ghostty":
        env["WITTY_VIEWPORT_HOVER_GHOSTTY"] = "1"
        extra = ("--auto-update=off", "--drag-handle=never")
    args = (*OPTIONS, *SCROLLBAR_OPTIONS, *extra, *options, "-e", "/bin/bash", "scrollbar.sh", "scrollbar",
            f"{WINDOW_ROWS} {WINDOW_COLUMNS}", ready)
    log_path = prefix.with_suffix(".log")
    with log_path.open("wb") as log:
        result = subprocess.run([binary, *args], cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=20)
    if result.returncode or not all(path.is_file() for path in images.values()):
        raise RuntimeError(f"{app} scrollbar capture failed with status {result.returncode}. See {log_path}")
    frames = {}
    for state, path in images.items():
        with Image.open(path) as png:
            frames[state] = png.convert("RGBA")
    return frames


def run(witty, ghostty, output):
    work = output / "fixtures"
    work.mkdir(exist_ok=True)
    rows = "\r\n".join(
        f"\x1b[38;2;{100 + row % 97};154;212m{row:03d}\x1b[0m   scrollback   café ─── 界"
        for row in range(171)
    )
    (work / "scrollbar.bin").write_bytes(("\x1b[2J\x1b[3J\x1b[H\x1b[?25l" + rows).encode())
    (work / "scrollbar.sh").write_text(INPUT_FRAME_START + "exec /bin/sleep 20\n")
    helper = build_probe_input(output)
    write_versions(output, witty, ghostty)
    report = output / "live-scrollbar-parity.tsv"
    passed = True
    with report.open("w", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(("fixture", "state", "witty_size", "ghostty_size",
                         "different_pixels", "maximum_channel_error", "status"))
        for fixture, options in CASES.items():
            captures = {app: capture(binary, app, helper, output / f"{fixture}-{app}", work, options)
                        for app, binary in (("ghostty", ghostty), ("witty", witty))}
            for state in STATES:
                actual, expected = captures["witty"][state], captures["ghostty"][state]
                count, error = compare_rgba(actual, expected)
                writer.writerow((fixture, state, f"{actual.width}x{actual.height}", f"{expected.width}x{expected.height}",
                                 count, error, "pass" if count == 0 else "mismatch"))
                passed &= count == 0
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
        print(f"Live scrollbar comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
