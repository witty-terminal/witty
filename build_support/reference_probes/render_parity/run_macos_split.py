"""Compare live macOS split panes in Witty and Ghostty."""

import argparse
import csv
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

from PIL import Image

from capture import compare_rgba, output_directory, write_versions
from run_macos import OPTIONS, build_probe_input


STATES = ("initial", "right", "left", "nested", "zoomed", "unzoomed", "closed")
SPLIT_OPTIONS = (
    "--window-decoration=none",
    "--macos-titlebar-style=transparent",
    "--window-padding-x=0",
    "--window-padding-y=0",
    "--window-padding-balance=false",
    "--confirm-close-surface=false",
    "--resize-overlay=never",
    "--keybind=f7=new_split:right",
    "--keybind=f8=new_split:down",
    "--keybind=f9=goto_split:previous",
    "--keybind=f10=toggle_split_zoom",
    "--keybind=f11=close_surface",
)
FIXTURES = {
    "default": (),
    "custom": ("--unfocused-split-fill=81315a", "--unfocused-split-opacity=0.56", "--split-divider-color=47637c"),
    "translucent": ("--background=29415a", "--foreground=f4e3dd", "--background-opacity=0.7", "--window-colorspace=srgb",
                    "--unfocused-split-fill=9b3561", "--split-divider-color=886753"),
    "light": ("--background=e3ece5", "--foreground=262535", "--window-theme=light"),
}
# The alternate screen keeps login output out of the zoomed and unzoomed frames.
PANE_SCRIPT = r"""work=$1
pane=1
while [ "$pane" -le 3 ] && ! mkdir "$work/pane$pane" 2>/dev/null; do
    pane=$((pane + 1))
done
[ "$pane" -le 3 ] || exit 1
stty -echo -icanon
printf '\033[?1049h\033[2J\033[H\033[?25l\033[2;2Hpane %s\033[4;2H\033[38;2;156;211;251mANSI color\033[0m\033[6;2H\033[48;2;71;99;124m        \033[0m\033[7;2Hbox ┌─┐ 界' "$pane"
: > "$work/pane$pane.ready"
exec /bin/sleep 30
"""


def capture(binary, app, helper, prefix, options):
    paths = {state: prefix.with_name(f"{prefix.name}-{state}.png") for state in STATES}
    for path in paths.values():
        path.unlink(missing_ok=True)
    log_path = prefix.with_suffix(".log")
    with tempfile.TemporaryDirectory(prefix="split-", dir=prefix.parent) as directory:
        script = Path(directory) / "pane.sh"
        script.write_text(PANE_SCRIPT, encoding="utf-8")
        env = {
            **os.environ,
            "DYLD_INSERT_LIBRARIES": str(helper),
            "LC_ALL": "en_US.UTF-8",
            "WITTY_VIEWPORT_READY": directory,
            "WITTY_VIEWPORT_SPLIT_CAPTURE": str(prefix),
        }
        env.pop("GHOSTTY_RESOURCES_DIR", None)
        env.pop("WITTY_VIEWPORT_HOVER_GHOSTTY", None)
        extra = ()
        if app == "ghostty":
            env["WITTY_VIEWPORT_HOVER_GHOSTTY"] = "1"
            extra = ("--auto-update=off", "--drag-handle=never")
        command = shlex.join(("/bin/sh", str(script), directory))
        args = (*OPTIONS, *SPLIT_OPTIONS, *extra, *options, f"--command={command}")
        with log_path.open("wb") as log:
            result = subprocess.run([binary, *args], cwd=prefix.parent, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=30)
    if result.returncode or not all(path.is_file() for path in paths.values()):
        raise RuntimeError(f"{app} split capture failed with status {result.returncode}. See {log_path}")
    frames = {}
    for state, path in paths.items():
        with Image.open(path) as png:
            frames[state] = png.convert("RGBA")
    return frames


def run(witty, ghostty, output):
    helper = build_probe_input(output)
    write_versions(output, witty, ghostty)
    report = output / "live-split-parity.tsv"
    passed = True
    with report.open("w", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(("fixture", "state", "witty_size", "ghostty_size",
                         "different_pixels", "maximum_channel_error", "status"))
        for fixture, options in FIXTURES.items():
            captures = {app: capture(binary, app, helper, output / f"{fixture}-{app}", options)
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
        print(f"Live split comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
