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


def kitty_unicode():
    pixels = bytes(
        channel
        for y in range(18)
        for x in range(24)
        for channel in (x * 10, y * 14, 230 - x * 6, 255)
    )
    data = base64.b64encode(pixels) + b"\x1b\\"
    commands = bytearray(b"Kitty Unicode placeholders")
    for image_id in (42, 0x0200002A):
        commands += f"\x1b_Ga=t,f=32,i={image_id},s=24,v=18,q=2;".encode() + data
    commands += b"\x1b_Ga=p,i=42,U=1,c=3,r=2,q=2;\x1b\\"
    commands += b"\x1b_Ga=p,i=42,p=9,U=1,c=2,r=1,q=2;\x1b\\"
    commands += b"\x1b_Ga=p,i=42,p=4,U=1,c=4,r=2,q=2;\x1b\\"
    commands += b"\x1b_Ga=p,i=33554474,U=1,c=4,r=1,q=2;\x1b\\"

    marks = "\u0305\u030d\u030e\u0310"
    for row, col, image_row, count, placement_id, high_byte in (
        (3, 4, 0, 4, 0, 0),
        (4, 4, 1, 4, 0, 0),
        (3, 18, 0, 2, 9, 0),
        (4, 18, 1, 3, 4, 0),
        (7, 4, 0, 4, 0, 2),
    ):
        commands += f"\x1b[{row};{col}H\x1b[38;5;42m".encode()
        if placement_id:
            commands += f"\x1b[58:5:{placement_id}m".encode()
        for image_col in range(count):
            first = image_col == 0
            # The high-byte run inherits its coordinates after the first cell.
            diacritics = marks[image_row] + marks[image_col] if first or not high_byte else ""
            if high_byte and first:
                diacritics += marks[high_byte]
            commands += ("\U0010eeee" + diacritics).encode()
        commands += b"\x1b[0m"
    return commands


def kitty_unicode_pinned():
    return (
        b"Kitty explicit placeholder target"
        + kitty_solid(3, 4, 43, (230, 80, 100))
        + "\x1b[7;4H\x1b[38;5;43;58:5:1m\U0010eeee\u0305\u0305\U0010eeee\u0305\u030d\x1b[0m".encode()
    )


def kitty_layers():
    commands = bytearray(b"Kitty image layers")
    for image_id, col, z in (
        (441, 3, -1073741825), (442, 13, -1073741824),
        (443, 23, -1), (444, 33, 0),
    ):
        commands += f"\x1b[3;{col}H\x1b[48;2;20;100;170m TEXT \x1b[0m".encode()
        commands += f"\x1b[3;{col}H\x1b_Ga=T,i={image_id},f=32,s=1,v=1,c=8,r=1,z={z},C=1,q=2;".encode()
        commands += base64.b64encode(bytes((240, 165, 25, 144))) + b"\x1b\\"

    # At equal z, sort by image ID even when they are transmitted in reverse order.
    # Two translucent colors make the order observable in the overlapping region.
    for row, image_id, col, z, rgba in (
        (6, 507, 6, 0, (250, 40, 60, 160)), (6, 506, 4, 0, (40, 220, 120, 185)),
        (8, 526, 4, 1, (40, 220, 120, 185)), (8, 527, 6, 0, (250, 40, 60, 160)),
    ):
        commands += f"\x1b[{row};{col}H\x1b_Ga=T,i={image_id},f=32,s=1,v=1,c=4,r=1,z={z},C=1,q=2;".encode()
        commands += base64.b64encode(bytes(rgba)) + b"\x1b\\"

    # Both placements use the same image and z. The fixed placement uses a different crop.
    commands += b"\x1b[6;20H\x1b_Ga=T,f=24,i=43,p=1,s=2,v=1,x=1,w=1,c=2,r=1,z=-1,C=1,q=2;"
    commands += base64.b64encode(bytes((245, 55, 85, 50, 225, 185))) + b"\x1b\\"
    commands += b"\x1b_Ga=p,i=43,p=2,U=1,c=2,r=1,q=2;\x1b\\"
    commands += "\x1b[6;20H\x1b[38;5;43;58:5:2m\U0010eeee\u0305\u0305\U0010eeee\u0305\u030d\x1b[0m".encode()
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
    elif fixture == "kitty-unicode":
        sys.stdout.buffer.write(kitty_unicode())
    elif fixture == "kitty-unicode-pinned":
        sys.stdout.buffer.write(kitty_unicode_pinned())
    elif fixture == "kitty-layers":
        sys.stdout.buffer.write(kitty_layers())
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
