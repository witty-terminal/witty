import base64
import os
import subprocess
import sys


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


def kitty_solid(row, col, image_id, color, *, place=True):
    action = "T" if place else "t"
    placement = ",p=1,c=2,r=1,C=1" if place else ""
    header = f"\x1b[{row};{col}H\x1b_Ga={action},f=24,i={image_id},s=1,v=1,q=2{placement};"
    return header.encode() + base64.b64encode(bytes(color)) + b"\x1b\\"


def kitty_retransmit():
    return (
        b"Kitty image replacement"
        + kitty_solid(4, 15, 401, (250, 50, 30))
        + b"\x1b[6;15H\x1b_Ga=p,i=401,p=2,c=2,r=1,C=1,q=2;\x1b\\"
        + kitty_solid(4, 30, 402, (250, 50, 30))
        + kitty_solid(4, 5, 403, (245, 190, 20))
        + kitty_solid(8, 15, 401, (50, 230, 70), place=False)
        + kitty_solid(8, 30, 402, (20, 120, 245))
    )


def kitty_history():
    return (
        kitty_solid(1, 5, 404, (250, 50, 30))
        + b"\x1b[6;12H\x1b_Ga=p,i=404,p=1,c=4,r=2,C=1,q=2;\x1b\\"
        + kitty_solid(2, 5, 405, (20, 120, 245))
        # Scroll the blue image into history and erase that history.
        + f"\x1b[{GRID_ROWS};1H\n\n\x1b[3J\x1b[2;1HKitty image history".encode()
    )


def kitty_layout():
    pixels = bytes(
        channel
        for y in range(12)
        for x in range(16)
        for channel in (x * 16, y * 20, 240 - x * 8 - y * 4, 255)
    )
    commands = bytearray(b"Kitty image layout\x1b_Ga=t,f=32,i=410,s=16,v=12,q=2;")
    commands += base64.b64encode(pixels) + b"\x1b\\"
    for row, col, layout in (
        (3, 3, "x=5,y=4"),
        (3, 12, "x=9,y=7,w=40,h=20,c=4,r=2,X=3,Y=5"),
        (3, 27, "x=8,y=2,w=8,c=3,X=7,Y=6"),
        (7, 12, "c=2,r=1,X=30,Y=44"),
        (7, 27, "x=16,c=2,r=2"),
    ):
        commands += f"\x1b[{row};{col}H\x1b_Ga=p,i=410,C=1,q=2,{layout};\x1b\\".encode()
    return commands


def kitty_cursor():
    commands = bytearray(kitty_solid(1, 1, 411, (205, 135, 245), place=False))
    for row, col, cols, rows, label in (
        (2, 4, 3, 2, "Below and right"),
        (5, GRID_COLUMNS - 1, 2, 1, "Wrapped caption"),
    ):
        commands += f"\x1b[{row};{col}H\x1b_Ga=p,i=411,c={cols},r={rows},q=2;\x1b\\{label}".encode()

    # Use cursor-origin mode with both vertical and horizontal margins.
    commands += b"\x1b[8;11r\x1b[?69h\x1b[10;40s\x1b[?6h"
    commands += b"\x1b[1;3H\x1b_Ga=p,i=411,c=2,r=2,q=2;\x1b\\Inside margins"
    commands += b"\x1b[4;3H\x1b_Ga=p,i=411,c=2,r=1,q=2;\x1b\\Bottom row"
    return commands


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
    elif fixture == "kitty-retransmit":
        sys.stdout.buffer.write(kitty_retransmit())
    elif fixture == "kitty-history":
        sys.stdout.buffer.write(kitty_history())
    elif fixture == "kitty-layout":
        sys.stdout.buffer.write(kitty_layout())
    elif fixture == "kitty-cursor":
        sys.stdout.buffer.write(kitty_cursor())
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
