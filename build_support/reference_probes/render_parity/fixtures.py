import base64
import os
import subprocess
import sys
import termios
import time


CLEAR = b"\x1b[2J\x1b[H\x1b[?25l"
GRID_ROWS, GRID_COLUMNS = 12, 60
CURSOR_STYLES = {"cursor-block": 2, "cursor-bar": 6, "cursor-underline": 4}
KITTY_SCROLL_FIXTURES = ("kitty-scroll-up", "kitty-scroll-down")


def kitty_image():
    width, height = 32, 24
    pixels = bytes(
        channel
        for y in range(height)
        for x in range(width)
        for channel in (y * 11, x * 7, (x + y) * 4, (x * 29 + y * 23) % 256)
    )
    header = f"\x1b[3;4H\x1b_Ga=T,f=32,s={width},v={height},q=2;".encode()
    return header + base64.b64encode(pixels) + b"\x1b\\"


def kitty_scroll(down):
    commands = bytearray(b"Kitty scrolling margins")
    row = 8 if down else 5
    for col, top, bottom in (
        (15, (250, 50, 30), (50, 230, 70)),
        (5, (20, 120, 245), (20, 120, 245)),
        (40, (245, 190, 20), (245, 190, 20)),
    ):
        # Each image spans two rows. Only the first fits inside both margins.
        commands += f"\x1b[{row};{col}H\x1b_Ga=T,f=32,s=4,v=4,c=2,r=2,C=1,q=2;".encode()
        commands += base64.b64encode(bytes((*top, 255)) * 8 + bytes((*bottom, 255)) * 8)
        commands += b"\x1b\\"
    commands += b"\x1b[3;9r\x1b[?69h\x1b[10;40s"
    commands += b"\x1b[1T" if down else b"\x1b[3S"
    return commands


def wait_for_grid():
    # Resizing can reflow the image anchors and reset scrolling margins.
    deadline = time.monotonic() + 1
    while termios.tcgetwinsize(sys.stdout.fileno()) != (GRID_ROWS, GRID_COLUMNS):
        if time.monotonic() >= deadline:
            raise RuntimeError(f"terminal did not reach {GRID_COLUMNS}x{GRID_ROWS}")
        time.sleep(0.01)


def main():
    fixture = sys.argv[1]
    output = {
        "ansi": b"Witty GPU parity\n\x1b[1;31mBold red\x1b[0m "
                b"\x1b[3;32mItalic green\x1b[0m \x1b[44;97m Blue cell \x1b[0m\n",
        "decorations": (
            b"\x1b[4mSingle underline\x1b[0m\n"
            b"\x1b[4:2mDouble underline\x1b[0m\n"
            b"\x1b[4:3;58:2::255:113:115mColored undercurl\x1b[0m\n"
            b"\x1b[4:4mDotted underline\x1b[0m\n"
            b"\x1b[4:5mDashed underline\x1b[0m\n"
            b"\x1b[9mStrikethrough\x1b[0m\n"
            b"\x1b[53mOverline\x1b[0m\n"
            b"\x1b[7m Reversed \x1b[0m \x1b[2mFaint text\x1b[0m\n"
        ),
        "unicode": "café · 日本語 · Σ · 😀\n─ ║ █ ░ ☀\n".encode(),
        # Leave one column at the right edge before printing a two-cell glyph.
        "wide-wrap": ("60 column wrap\n" + "X" * 59 + "日本語 😀 café\n").encode(),
        "shader": b"Witty shader chain\n",
    }
    if fixture in KITTY_SCROLL_FIXTURES:
        wait_for_grid()
    sys.stdout.buffer.write(CLEAR)
    sys.stdout.flush()
    if fixture == "ls":
        subprocess.run(
            ["ls", "--color=always", "-C", "listing"],
            env={**os.environ, "LS_COLORS": "di=01;34:ex=01;32"},
            check=True,
        )
    elif fixture == "git":
        result = subprocess.run(
            ["git", "--no-pager", "diff", "--no-index", "--color=always", "before.py", "after.py"],
            env={**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"},
        )
        if result.returncode != 1:
            raise RuntimeError("the Git fixture must produce a diff")
    elif fixture == "kitty":
        sys.stdout.buffer.write(b"Kitty graphics\n" + kitty_image())
    elif fixture in KITTY_SCROLL_FIXTURES:
        sys.stdout.buffer.write(kitty_scroll(down=fixture == "kitty-scroll-down"))
    elif fixture in CURSOR_STYLES:
        # Reposition over an existing glyph and show a steady cursor.
        style = CURSOR_STYLES[fixture]
        sys.stdout.buffer.write(f"Cursor style: abc\x1b[16G\x1b[{style} q\x1b[?25h".encode())
    else:
        sys.stdout.buffer.write(output[fixture])
    sys.stdout.flush()
    # Keep the PTY open after emitting the fixture for the reference capture.
    sys.stdin.read(1)


if __name__ == "__main__":
    main()
