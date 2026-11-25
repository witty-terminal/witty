import argparse
import base64
import csv
import hashlib
import math
import os
from pathlib import Path
import platform
import subprocess
import sys

from PIL import Image

from capture import capture_witty, output_directory, write_versions


REFERENCE = Path(__file__).with_name("ghostty-1.4.0-macos.tsv")
OPTIONS = (
    "--config-default-files=false",
    "--window-save-state=never",
    "--window-width=56",
    "--window-height=15",
    "--shell-integration=none",
    "--window-colorspace=display-p3",
    "--window-theme=dark",
    "--background=161820",
    "--foreground=e4e5e9",
    "--cursor-color=ffeeaa",
    "--cursor-style-blink=false",
)
DEFAULT_WINDOW = ("--window-width=0", "--window-height=0")
TRANSLUCENT_WINDOW = (
    "--background-opacity=0.5", "--window-padding-x=7,5", "--window-padding-y=3,8",
)
CLEAR = r'printf "\033[2J\033[H"'
CLEAR_AND_HIDE_CURSOR = r'printf "\033[2J\033[H\033[?25l"'
CURSOR = r'printf "\033[2J\033[H\033[4G\033[38;2;151;249;164mabc\033[0m"'
TEXT = "ordinary text 0123456789 -+=>\r\nASCII ilI1O0 fi ffi => != ->\r\n"
ANSI = (
    "\x1b[1;31mBold red\x1b[0m / \x1b[3;32mItalic green\x1b[0m / \x1b[4;34mUnderline blue\x1b[0m\r\n"
    "\x1b[7mReverse\x1b[0m / \x1b[9mStrike\x1b[0m / \x1b[2mFaint\x1b[0m / "
    "\x1b[38;2;123;89;245;48;2;17;24;37mTrue Color\x1b[0m\r\n"
    "\x1b[48;5;24m     indexed background     \x1b[0m\r\n"
)
UNICODE = (
    "┌─────┬─────┐ ╭────╮ ░▒▓█\r\n"
    "│ ▄▆▀ └→←↕  │ │ ▖▚▝ │\r\n"
    "└─────┴─────┘ ╰────╯ \ue0b0 \ue0b2\r\n"
    "café cafe\u0301 漢字 😀 🚀 ❤️ 👩‍💻\r\n"
)
LESS = r'''while :; do
    size=$(/bin/stty size) || exit 1
    case "$size" in
        "0 "*|*" 0") /bin/sleep 0.01 ;;
        *) break ;;
    esac
done
printf '\033[?25l'
exec /usr/bin/env -i TERM=xterm-256color LC_ALL=en_US.UTF-8 LESSHISTFILE=- LESSSECURE=1 \
    /usr/bin/less -N -PsPager pager.txt
'''
ZSH = r'''stty -echo
printf '\033[2J\033[H\033[1;32malex\033[0m files %%\r\n'
whence -v printf
exec /bin/sleep 20
'''


def prepare_fixtures(work):
    work.mkdir()
    files = work / "files"
    files.mkdir()
    (files / "subdir").mkdir()
    executable = files / "execute"
    executable.touch()
    executable.chmod(0o755)
    source = (
        "from pathlib import Path\n\n"
        "# A compact terminal fixture.\n"
        "def read(input_path: Path) -> str:\n"
    )
    (files / "terminal.py").write_text(source + '    return input_path.read_text(encoding="utf-8")\n')
    (work / "patch.py").write_text(source + "    return input_path.read_bytes()\n")
    (work / "zsh-fixture.sh").write_text(ZSH)
    (work / "pager.txt").write_text(
        "".join(f"Section {section:02d}   Terminal pager fixture\n" for section in range(1, 31))
    )
    for name, payload in (("text", TEXT), ("ansi", ANSI), ("unicode", UNICODE)):
        (work / f"{name}.bin").write_bytes(("\x1b[2J\x1b[H" + payload).encode("utf-8"))

    width, height = 32, 24
    pixels = bytes(
        channel
        for y in range(height)
        for x in range(width)
        for channel in (y * 8, x * 7, (y * 6) ^ (x * 7), x * 29 % 256)
    )
    header = (
        "\x1b[2J\x1b[H\x1b[?25lKitty graphics\r\n\x1b[3;4H"
        f"\x1b_Ga=T,f=32,s={width},v={height},q=2;"
    )
    (work / "kitty.bin").write_bytes(header.encode() + base64.b64encode(pixels) + b"\x1b\\")


def terminal_command(script):
    return ("-e", "/bin/sh", "-c", f"stty -echo; {script}; exec /bin/sleep 20")


def fixture_args(work):
    kitty = ("-e", "/bin/sh", "-c", "/bin/cat kitty.bin; exec /bin/sleep 20")
    vim = (
        "-e", "/usr/bin/vim", "-Nu", "NONE", "-n", "-i", "NONE",
        "--cmd", "set shortmess+=F",
        "-c", "set number laststatus=2 noshowmode noruler",
        "-c", "syntax on", "files/terminal.py",
    )
    cursor = terminal_command(CURSOR)
    pager = ("-e", "/bin/sh", "-c", LESS)
    ansi = terminal_command("/bin/cat ansi.bin")
    unicode = terminal_command("/bin/cat unicode.bin")
    return {
        "blank": terminal_command(CLEAR),
        "text": terminal_command("/bin/cat text.bin"),
        "ansi": ansi,
        "ansi-translucent": (*TRANSLUCENT_WINDOW, "--background-opacity-cells=true", *ansi),
        "unicode": unicode,
        "unicode-translucent": (*TRANSLUCENT_WINDOW, *unicode),
        "kitty": kitty,
        "kitty-translucent": (*TRANSLUCENT_WINDOW, *kitty),
        "vim": vim,
        "vim-default": (*DEFAULT_WINDOW, *vim),
        "pager": pager,
        "pager-default": (*DEFAULT_WINDOW, *pager),
        "cursor": cursor,
        "cursor-srgb": ("--window-colorspace=srgb", "--alpha-blending=linear-corrected", *cursor),
        "ls": terminal_command(f"{CLEAR_AND_HIDE_CURSOR}; /bin/ls -G -C files"),
        "git": terminal_command(
            f"{CLEAR_AND_HIDE_CURSOR}; GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "
            "git --no-pager diff --no-index --color=always files/terminal.py patch.py"
        ),
        "zsh": ("-e", "/bin/zsh", "-f", work / "zsh-fixture.sh"),
    }


def run(witty, output, settle, references):
    os.environ.pop("GHOSTTY_RESOURCES_DIR", None)
    os.environ.pop("LSCOLORS", None)
    os.environ.update(LC_ALL="en_US.UTF-8", MTL_DEBUG_LAYER="1")
    work = output / "fixtures"
    prepare_fixtures(work)
    commands = fixture_args(work)
    write_versions(output, witty)
    with (output / "versions.txt").open("a") as versions:
        versions.write(f"macOS {platform.mac_ver()[0]} {platform.machine()}\n")
        versions.write(f"Reference: {REFERENCE.name}\n")
    print(f"Captures and logs: {output}", flush=True)
    matches = True
    with (output / "results.tsv").open("w") as report:
        header = "fixture\twitty_size\tghostty_size\tstatus\twitty_rgba_sha256\tghostty_rgba_sha256"
        print(header, file=report)
        print(header, flush=True)
        for name, reference in references.items():
            prefix = output / f"{name}-witty"
            args = [*OPTIONS, f"--working-directory={work}", *commands[name]]
            capture_witty(witty, args, prefix, settle)
            with Image.open(prefix.with_suffix(".png")) as png:
                actual_size = f"{png.width}x{png.height}"
                digest = hashlib.sha256(png.convert("RGBA").tobytes()).hexdigest()
            expected_size = reference["size"]
            expected_digest = reference["rgba_sha256"]
            if actual_size != expected_size:
                status = "size-mismatch"
            elif digest != expected_digest:
                status = "pixel-mismatch"
            else:
                status = "match"
            row = "\t".join((name, actual_size, expected_size, status, digest, expected_digest))
            print(row, file=report, flush=True)
            print(row, flush=True)
            matches = matches and status == "match"
    return 0 if matches else 1


def main():
    with REFERENCE.open() as reference:
        references = {row["fixture"]: row for row in csv.DictReader(reference, delimiter="\t")}
    parser = argparse.ArgumentParser(description="Compare offscreen macOS Witty captures with Ghostty 1.4.0.")
    parser.add_argument("witty", type=Path, help="path to the Witty executable")
    parser.add_argument("--output", type=Path, help="new directory for screenshots, logs, and the report")
    parser.add_argument("--settle-seconds", type=float, default=1.1)
    parser.add_argument("--fixture", choices=references.keys(), action="append")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("run on macOS")
    if not math.isfinite(args.settle_seconds) or args.settle_seconds < 0:
        parser.error("--settle-seconds must be finite and nonnegative")
    if not args.witty.is_file() or not os.access(args.witty, os.X_OK):
        parser.error(f"expected an executable file at {args.witty}")
    selected = {name: references[name] for name in args.fixture or references}
    try:
        return run(args.witty.resolve(), output_directory(args.output), args.settle_seconds, selected)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Render comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
