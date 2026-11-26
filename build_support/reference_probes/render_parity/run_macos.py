import argparse
import base64
import csv
import hashlib
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

from applications import (
    NEOVIM_FIXTURES, TMUX_ACTIVE, prepare_applications, prepare_neovim, tmux_fixture_command,
    write_pager_fixture,
)
from capture import capture_witty, output_directory, write_versions
from fixtures import CLEAR as CLEAR_FRAME
from fixtures import (
    TERMINAL_COLOR_PALETTE, TERMINAL_COLOR_RESET, TERMINAL_COLOR_SCREEN,
    WALLPAPER_OPTIONS, colored_line_erase, grapheme_sequences, kitty_layers, kitty_layout,
    kitty_retransmit, kitty_unicode, prepare_raster_effects, shader_fixture_options,
    terminal_color_updates, wrapped_wide_edits, wrapped_wide_glyphs,
)


REFERENCE = Path(__file__).with_name("ghostty-1.4.0-macos.tsv")
WINDOW_COLUMNS, WINDOW_ROWS = 56, 15
OPTIONS = (
    "--config-default-files=false",
    "--window-save-state=never",
    f"--window-width={WINDOW_COLUMNS}",
    f"--window-height={WINDOW_ROWS}",
    "--shell-integration=none",
    "--window-colorspace=display-p3",
    "--window-theme=dark",
    "--background=161820",
    "--foreground=e4e5e9",
    "--cursor-color=ffeeaa",
    "--cursor-style-blink=false",
)
DEFAULT_WINDOW = ("--window-width=0", "--window-height=0")
TMUX_FIXTURES = ("tmux", "tmux-switch-pane")
OPTIONAL_APPLICATIONS = {"tmux": TMUX_FIXTURES, "nvim": NEOVIM_FIXTURES}
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
KITTY_FIXTURES = {
    "kitty-layers": kitty_layers,
    "kitty-layout": kitty_layout,
    "kitty-retransmit": kitty_retransmit,
    "kitty-unicode": kitty_unicode,
}
WAIT_FOR_PTY_GRID = r'''while :; do
    size=$(/bin/stty size) || exit 1
    case "$size" in
        "0 "*|*" 0") ;;
        *)
            if [ -z "$2" ] || [ "$size" = "$2" ]; then
                break
            fi
            ;;
    esac
    /bin/sleep 0.01
done
'''
LESS = WAIT_FOR_PTY_GRID + r'''
case "$1" in
    search) set -- -R '+/needle' pager-search.txt ;;
    next) set -- -R "$(printf '+/needle\nn')" pager-search.txt ;;
    *) set -- pager.txt ;;
esac
printf '\033[?25l'
exec /usr/bin/env -i TERM=xterm-256color LC_ALL=en_US.UTF-8 LESSHISTFILE=- LESSSECURE=1 \
    /usr/bin/less -N -PsPager "$@"
'''
GRID_FRAME_START = WAIT_FOR_PTY_GRID + r'''
/bin/stty -icanon -echo -opost || exit 1
/bin/cat "$1.bin" || exit 1
shift 2
'''
GRID_FRAME = GRID_FRAME_START + r'''
for frame in "$@"; do
    # Let the previous frame render before sending the next update.
    /bin/sleep 0.18
    /bin/cat "$frame.bin" || exit 1
done
exec /bin/sleep 20
'''
VIM_RETURN = GRID_FRAME_START + r'''
/bin/sleep 0.18
"$@" -c 'redraw!' -c 'sleep 180m' -c 'qa!' || exit 1
printf 'ready'
exec /bin/sleep 20
'''
ZSH = r'''stty -echo
printf '\033[2J\033[H\033[1;32malex\033[0m files %%\r\n'
whence -v printf
exec /bin/sleep 20
'''


def alternate_screen_frames():
    rows = "".join(
        f"\x1b[38;2;{120 + line * 10};154;227m {line:02d}  café 日本語\x1b[0m\r\n"
        for line in range(1, 9)
    )
    return {
        "alternate-screen-primary": CLEAR_FRAME + (
            "\x1b[48;2;53;73;104m Shell before full-screen program\x1b[K\x1b[0m"
            "\x1b[3;1H\x1b[38;2;120;208;166;48;2;34;61;53m$ echo "
            f"\x1b[{WINDOW_COLUMNS}G>\x1b[2 q\x1b[?25h"
        ).encode(),
        "alternate-screen": (
            "\x1b[?1049h\x1b[0m\x1b[H\x1b[48;2;45;68;94m Full-screen header\x1b[K\x1b[0m"
            "\x1b[8;1H\x1b[48;2;82;53;78m [q] Return to shell\x1b[K\x1b[0m"
            "\x1b[2;6r\x1b[2;1H" + rows + "\x1b[r\x1b[8;38H\x1b[38;2;247;165;128m"
        ).encode(),
        "alternate-screen-return": b"\x1b[?1049lready",
        "alternate-screen-reenter": b"\x1b[?1049h\x1b[0m\x1b[HSecond full-screen session",
    }


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
    (work / "pager.sh").write_text(LESS)
    (work / "vim-return.sh").write_text(VIM_RETURN)
    write_pager_fixture(work / "pager-search.txt")
    for name, payload in (("text", TEXT), ("ansi", ANSI), ("unicode", UNICODE)):
        (work / f"{name}.bin").write_bytes(("\x1b[2J\x1b[H" + payload).encode("utf-8"))
    (work / "grid-frame.sh").write_text(GRID_FRAME)
    (work / "grapheme-sequences.bin").write_bytes(CLEAR_FRAME + grapheme_sequences(WINDOW_COLUMNS))
    (work / "colored-line-erase.bin").write_bytes(CLEAR_FRAME + colored_line_erase(WINDOW_ROWS))
    (work / "wide-edit-before.bin").write_bytes(CLEAR_FRAME + wrapped_wide_glyphs(WINDOW_COLUMNS))
    (work / "wide-edit.bin").write_bytes(wrapped_wide_edits())
    (work / "terminal-colors.bin").write_bytes(CLEAR_FRAME + TERMINAL_COLOR_SCREEN)
    overrides = b""
    for name, update in terminal_color_updates().items():
        overrides += update
        (work / f"terminal-colors-{name}.bin").write_bytes(overrides)
    (work / "terminal-colors-reset.bin").write_bytes(TERMINAL_COLOR_RESET)
    (work / "terminal-colors-reverse.bin").write_bytes(overrides + b"\x1b[?5h")
    for name, payload in alternate_screen_frames().items():
        (work / f"{name}.bin").write_bytes(payload)

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
    for name, payload in KITTY_FIXTURES.items():
        (work / f"{name}.bin").write_bytes(CLEAR_FRAME + payload())
    prepare_raster_effects(work)


def terminal_command(script):
    return ("-e", "/bin/sh", "-c", f"stty -echo; {script}; exec /bin/sleep 20")


def fixture_args(work):
    kitty = ("-e", "/bin/sh", "-c", "/bin/cat kitty.bin; exec /bin/sleep 20")
    kitty_commands = {name: terminal_command(f"/bin/cat {name}.bin") for name in KITTY_FIXTURES}
    vim_command = (
        "/usr/bin/vim", "-Nu", "NONE", "-n", "-i", "NONE",
        "--cmd", "set shortmess+=F",
        "-c", "set number laststatus=2 noshowmode noruler",
        "-c", "syntax on", "files/terminal.py",
    )
    vim = ("-e", *vim_command)
    cursor = terminal_command(CURSOR)
    pager = ("-e", "/bin/sh", "pager.sh")
    grid_frame = ("-e", "/bin/sh", "grid-frame.sh")
    grid_size = f"{WINDOW_ROWS} {WINDOW_COLUMNS}"
    terminal_colors = (f"--palette=1={bytes(TERMINAL_COLOR_PALETTE).hex()}",
                       *grid_frame, "terminal-colors", grid_size)
    primary_screen = (*grid_frame, "alternate-screen-primary", grid_size)
    alternate_screen = (*primary_screen, "alternate-screen")
    restored_screen = (*alternate_screen, "alternate-screen-return")
    text = terminal_command("/bin/cat text.bin")
    ansi = terminal_command("/bin/cat ansi.bin")
    ansi_without_cursor = terminal_command(r'/bin/cat ansi.bin; printf "\033[?25l"')
    unicode = terminal_command("/bin/cat unicode.bin")
    wallpaper = f"--background-image={work / 'wallpaper.png'}"
    repeated_wallpaper = (
        wallpaper, *WALLPAPER_OPTIONS["wallpaper-repeat"], "--background-opacity=0.72",
    )
    shader = shader_fixture_options(work)
    linear_blending = "--alpha-blending=linear-corrected"
    return {
        "blank": terminal_command(CLEAR),
        "text": text,
        "text-balanced": (
            "--window-padding-x=0", "--window-padding-y=18", "--window-padding-balance=equal", *text,
        ),
        "ansi": ansi,
        "ansi-translucent": (*TRANSLUCENT_WINDOW, "--background-opacity-cells=true", *ansi),
        "unicode": unicode,
        "unicode-translucent": (*TRANSLUCENT_WINDOW, *unicode),
        "grapheme-sequences": (*grid_frame, "grapheme-sequences", grid_size),
        "colored-line-erase": (*grid_frame, "colored-line-erase", grid_size),
        "wide-edit-before": (*grid_frame, "wide-edit-before", grid_size),
        "wide-edit": (*grid_frame, "wide-edit-before", grid_size, "wide-edit"),
        "terminal-colors": terminal_colors,
        "terminal-colors-palette": (*terminal_colors, "terminal-colors-palette"),
        "terminal-colors-foreground": (*terminal_colors, "terminal-colors-foreground"),
        "terminal-colors-background": (*terminal_colors, "terminal-colors-background"),
        "terminal-colors-cursor": (*terminal_colors, "terminal-colors-cursor"),
        "terminal-colors-reset": (*terminal_colors, "terminal-colors-cursor", "terminal-colors-reset"),
        "terminal-colors-reverse": (*terminal_colors, "terminal-colors-reverse"),
        "terminal-colors-translucent": (
            "--background-opacity=0.5", "--background-opacity-cells=true",
            *terminal_colors, "terminal-colors-cursor",
        ),
        "alternate-screen-primary": primary_screen,
        "alternate-screen": alternate_screen,
        "alternate-screen-return": restored_screen,
        "alternate-screen-reenter": (*restored_screen, "alternate-screen-reenter"),
        "kitty": kitty,
        "kitty-translucent": (*TRANSLUCENT_WINDOW, *kitty),
        **kitty_commands,
        "kitty-layers-translucent": (*TRANSLUCENT_WINDOW, *kitty_commands["kitty-layers"]),
        "wallpaper-stretch": (wallpaper, *WALLPAPER_OPTIONS["wallpaper-stretch"], *ansi_without_cursor),
        "wallpaper-repeat": (*repeated_wallpaper, *ansi_without_cursor),
        "shader-chain": (*shader, *ansi_without_cursor),
        "shader-chain-linear": (*shader, linear_blending, *ansi_without_cursor),
        "shader-wallpaper": (*repeated_wallpaper, *shader, linear_blending, *ansi_without_cursor),
        "vim": vim,
        "vim-return": ("-e", "/bin/sh", "vim-return.sh", "alternate-screen-primary", grid_size, *vim_command),
        "vim-default": (*DEFAULT_WINDOW, *vim),
        # Recreate the reference's saved content size with explicit geometry.
        "vim-saved": (
            "--window-width=75", "--window-height=20", "--window-padding-x=2,3",
            "--window-padding-y=2,7", *vim,
        ),
        "pager": (*pager, "open", grid_size),
        "pager-default": (*DEFAULT_WINDOW, *pager),
        "pager-search": (*pager, "search", grid_size),
        "pager-search-next": (*pager, "next", grid_size),
        "cursor": cursor,
        "cursor-srgb": ("--window-colorspace=srgb", "--alpha-blending=linear-corrected", *cursor),
        "ls": terminal_command(f"{CLEAR_AND_HIDE_CURSOR}; /bin/ls -G -C files"),
        "git": terminal_command(
            f"{CLEAR_AND_HIDE_CURSOR}; GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "
            "git --no-pager diff --no-index --color=always files/terminal.py patch.py"
        ),
        "zsh": ("-e", "/bin/zsh", "-f", work / "zsh-fixture.sh"),
    }


def capture_tmux_frame(witty, tmux, options, work, prefix, settle, switch_pane):
    with tempfile.TemporaryDirectory(prefix="witty-tmux-", dir="/tmp") as socket_dir:
        server = [tmux, "-S", f"{socket_dir}/server"]
        args = [
            *options, "--term=xterm-256color", f"--palette=2={bytes(TMUX_ACTIVE).hex()}",
            "-e", "/usr/bin/env", "-u", "TMUX", "-u", "TMUX_PANE",
            *tmux_fixture_command(server, work, WINDOW_COLUMNS, WINDOW_ROWS, switch_pane=switch_pane),
        ]
        try:
            capture_witty(witty, args, prefix, settle)
        finally:
            subprocess.run([*server, "kill-server"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=5)


def run(witty, output, settle, references, programs):
    os.environ.pop("GHOSTTY_RESOURCES_DIR", None)
    os.environ.pop("LSCOLORS", None)
    os.environ.update(LC_ALL="en_US.UTF-8", MTL_DEBUG_LAYER="1")
    work = output / "fixtures"
    prepare_fixtures(work)
    tmux = programs.get("tmux")
    if tmux:
        prepare_applications(work, ("tmux",))
    commands = fixture_args(work)
    if "nvim" in programs:
        commands.update(prepare_neovim(work, programs["nvim"]))
    options = [*OPTIONS, f"--working-directory={work}"]
    write_versions(output, witty)
    with (output / "versions.txt").open("a") as versions:
        versions.write(f"macOS {platform.mac_ver()[0]} {platform.machine()}\n")
        versions.write(f"Reference: {REFERENCE.name}\n")
        for name, executable in programs.items():
            flag = "-V" if name == "tmux" else "--version"
            version = subprocess.check_output([executable, flag], text=True, timeout=5).splitlines()[0]
            versions.write(f"{version}\n")
    print(f"Captures and logs: {output}", flush=True)
    matches = True
    with (output / "results.tsv").open("w") as report:
        header = "fixture\twitty_size\tghostty_size\tstatus\twitty_rgba_sha256\tghostty_rgba_sha256"
        print(header, file=report)
        print(header, flush=True)
        for name, reference in references.items():
            prefix = output / f"{name}-witty"
            if name in TMUX_FIXTURES:
                capture_tmux_frame(witty, tmux, options, work, prefix, settle, name == "tmux-switch-pane")
            else:
                capture_witty(witty, [*options, *commands[name]], prefix, settle)
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
    parser.add_argument("--fixture", choices=references.keys(), action="append",
                        help="run a specific fixture, including optional application cases")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("run on macOS")
    if not math.isfinite(args.settle_seconds) or args.settle_seconds < 0:
        parser.error("--settle-seconds must be finite and nonnegative")
    if not args.witty.is_file() or not os.access(args.witty, os.X_OK):
        parser.error(f"expected an executable file at {args.witty}")
    optional_fixtures = {name for fixtures in OPTIONAL_APPLICATIONS.values() for name in fixtures}
    default_fixtures = [name for name in references if name not in optional_fixtures]
    selected = {name: references[name] for name in args.fixture or default_fixtures}
    programs = {}
    for program, fixtures in OPTIONAL_APPLICATIONS.items():
        if not any(name in selected for name in fixtures):
            continue
        executable = shutil.which(program)
        if executable is None:
            parser.error(f"the {program} fixtures require {program} on PATH")
        programs[program] = Path(executable).resolve()
    try:
        return run(args.witty.resolve(), output_directory(args.output), args.settle_seconds, selected, programs)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Render comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
