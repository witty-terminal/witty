import base64
import os
import subprocess
import sys
import termios
import time
import tty


CLEAR = b"\x1b[2J\x1b[H\x1b[?25l"
GRID_ROWS, GRID_COLUMNS = 12, 60
CURSOR_STYLES = {"cursor-block": 2, "cursor-bar": 6, "cursor-underline": 4}
KITTY_SCROLL_FIXTURES = ("kitty-scroll-up", "kitty-scroll-down")
SCROLLBACK_FIXTURES = ("scrollback-follow-output", "scrollback-keep-position")
SCROLLBACK_LAST_COLOR = (38, 198, 216)
SCROLLBACK_RECOLORED = (221, 117, 170)
RESIZE_FIXTURES = (
    "resize-cursor-in-blanks", "resize-cursor-near-bottom", "resize-pending-wrap", "resize-prompt-last",
)
RESIZE_WRAP_COLOR = (129, 68, 93)


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


def kitty_relative():
    commands = bytearray(b"Kitty relative placements")
    for image_id, color in (
        (471, (240, 73, 70)), (472, (78, 229, 119)), (473, (91, 137, 242)),
        (474, (247, 201, 80)), (475, (192, 92, 241)),
    ):
        commands += kitty_solid(1, 1, image_id, color, place=False)
    # Move the fixed root after attaching a child and grandchild.
    commands += b"\x1b[3;4H\x1b_Ga=p,i=471,p=1,c=3,r=2,C=1,q=2;\x1b\\"
    commands += b"\x1b[5;24H\x1b_Ga=p,i=472,p=1,P=471,Q=1,H=-2,V=1,c=3,r=2,q=2;\x1b\\Same cursor"
    commands += b"\x1b_Ga=p,i=473,p=1,P=472,H=-1,V=-2,c=2,r=1,q=2;\x1b\\"
    commands += b"\x1b[7;3H\x1b_Ga=p,i=471,p=1,c=3,r=2,C=1,q=2;\x1b\\"
    commands += b"\x1b[2;12r\x1b[S\x1b[r"

    # The virtual root takes its leftmost column and topmost row independently.
    commands += b"\x1b_Ga=p,i=474,p=12,U=1,c=1,r=1,q=2;\x1b\\"
    commands += b"\x1b_Ga=p,i=475,p=1,P=474,Q=12,H=-1,V=-1,c=3,r=1,q=2;\x1b\\"
    for row, col in ((8, 23), (9, 20)):
        commands += f"\x1b[{row};{col}H\x1b[38:2::0:1:218;58:5:12m\U0010eeee\u0305\u0305\x1b[0m".encode()

    # Deleting a parent removes its children, and they stay gone if the ID is reused.
    commands += b"\x1b[3;43H\x1b_Ga=p,i=471,p=2,c=2,r=1,C=1,q=2;\x1b\\"
    commands += b"\x1b[5;43H\x1b_Ga=p,i=472,p=2,P=471,Q=2,H=1,V=1,c=2,r=1,q=2;\x1b\\"
    commands += b"\x1b_Ga=d,d=i,i=471,p=2,q=2;\x1b\\"
    commands += b"\x1b[3;45H\x1b_Ga=p,i=471,p=2,c=2,r=1,C=1,q=2;\x1b\\"
    return commands


def kitty_delete_selection():
    commands = bytearray(b"Kitty delete selection")
    for row, col, image_id, color, place in (
        (3, 4, 701, (240, 73, 70), True),
        (3, 9, 702, (78, 229, 119), True),
        (3, 14, 704, (91, 137, 242), True),
        (3, 19, 705, (247, 201, 80), False),
        (3, 24, 706, (192, 92, 241), True),
        (3, 29, 707, (42, 199, 229), False),
    ):
        commands += kitty_solid(row, col, image_id, color, place=place)
    commands += b"\x1b_Ga=d,d=r,x=702,y=704,q=2;\x1b\\"
    commands += b"\x1b[4;9H\x1b_Ga=p,i=702,c=2,r=1,C=1,q=2;\x1b\\"
    # The uppercase range also frees images that have no placements.
    commands += b"\x1b_Ga=d,d=R,x=703,y=705,q=2;\x1b\\"
    commands += b"\x1b[4;19H\x1b_Ga=p,i=705,c=2,r=1,C=1,q=2;\x1b\\"
    commands += b"\x1b_Ga=d,d=R,y=701,q=2;\x1b\\"
    # Deleting an absent placement ID leaves the transmitted image available.
    commands += b"\x1b_Ga=d,d=I,i=707,p=9,q=2;\x1b\\"
    commands += b"\x1b[4;29H\x1b_Ga=p,i=707,c=2,r=1,C=1,q=2;\x1b\\"
    commands += b"\x1b[6;16H\x1b_Ga=p,i=706,c=3,r=3,C=1,q=2;\x1b\\"
    # The cell is on a middle row of the image, outside its column bounds.
    commands += b"\x1b_Ga=d,d=p,x=1,y=7,q=2;\x1b\\"
    return commands


def kitty_delete_visible():
    commands = bytearray(kitty_solid(1, 3, 601, (240, 73, 70)))
    commands += kitty_solid(1, 20, 602, (78, 229, 119), place=False)
    commands += b"\x1b_Ga=p,i=602,p=1,c=2,r=2,C=1,q=2;\x1b\\"
    commands += kitty_solid(1, 1, 603, (91, 137, 242), place=False)
    commands += f"\x1b[{GRID_ROWS};1H\n".encode()
    commands += kitty_solid(3, 30, 604, (247, 201, 80))
    # One placement is wholly in history, and another straddles the top edge.
    commands += b"\x1b_Ga=d,d=A,q=2;\x1b\\"
    commands += b"\x1b[2;1HKitty delete visible\x1b_Ga=p,i=603,P=601,Q=1,H=3,V=5,c=3,r=1,q=2;\x1b\\"
    commands += b"\x1b[7;19H\x1b_Ga=p,i=602,c=2,r=1,C=1,q=2;\x1b\\"
    commands += b"\x1b[7;30H\x1b_Ga=p,i=604,c=2,r=1,C=1,q=2;\x1b\\"
    return commands


def kitty_chunked():
    commands = bytearray(b"Kitty chunked uploads")
    commands += kitty_solid(3, 4, 801, (240, 73, 70))
    commands += b"\x1b[3;12H\x1b_Ga=p,i=801,p=2,c=2,r=1,C=1,q=2;\x1b\\"
    commands += b"\x1b[6;4H\x1b_Ga=T,f=24,i=802,s=1,v=2,c=2,r=2,C=1,m=1,q=2;"
    commands += base64.b64encode(bytes((247, 201, 80))) + b"\x1b\\"
    # Any delete aborts an unfinished upload, even when the delete selects another ID.
    commands += b"\x1b_Ga=d,d=i,i=899,q=2;\x1b\\"
    commands += b"\x1b_Gm=0,q=2;" + base64.b64encode(bytes((192, 92, 241))) + b"\x1b\\"
    commands += kitty_solid(6, 14, 804, (78, 229, 119))

    # A file transmission starts independently of an unfinished direct upload.
    commands += b"\x1b[8;4H\x1b_Ga=T,f=24,i=803,s=1,v=2,c=2,r=2,C=1,m=1,q=2;"
    commands += base64.b64encode(bytes((247, 201, 80))) + b"\x1b\\"
    path = os.path.abspath("kitty-chunk-rgb")
    with open(path, "wb") as image_file:
        image_file.write(bytes((91, 137, 242)))
    commands += b"\x1b[8;14H\x1b_Ga=T,t=f,f=24,i=805,s=1,v=1,c=2,r=1,C=1,q=2;"
    commands += base64.b64encode(os.fsencode(path)) + b"\x1b\\"

    # Capture between chunks, after the existing placements of 801 have disappeared.
    commands += b"\x1b_Ga=t,f=24,i=801,s=1,v=2,m=1,q=2;"
    commands += base64.b64encode(bytes((42, 199, 229))) + b"\x1b\\"
    return commands


def kitty_animation():
    commands = bytearray(b"Kitty animation")

    def transmit(header, pixels):
        commands.extend(f"\x1b_G{header},f=32,q=2;".encode() + base64.b64encode(bytes(pixels)) + b"\x1b\\")

    for image_id, col in ((821, 4), (822, 18), (823, 32)):
        commands.extend(f"\x1b[4;{col}H".encode())
        transmit(f"a=T,i={image_id},s=4,v=2,c=8,r=2,C=1", (232, 60, 85, 255) * 8)

    # The edited frame copies the root canvas and alpha blends a partial upload.
    transmit("a=f,i=821,c=1,s=2,v=1,x=1,y=1,m=1", (73, 215, 148, 128))
    commands += b"\x1b_Gm=0,q=2;" + base64.b64encode(bytes((96, 150, 246, 200))) + b"\x1b\\"
    commands += b"\x1b_Ga=a,i=821,c=2,q=2;\x1b\\"

    transmit("a=f,i=822,s=4,v=2", (245, 191, 60, 255) * 8)
    commands += b"\x1b_Ga=c,i=822,r=2,c=1,w=2,h=1,X=1,Y=1,x=2,y=0,C=1,q=2;\x1b\\"
    commands += b"\x1b_Ga=d,d=f,i=822,r=2,q=2;\x1b\\"

    # One timed loop skips the gapless frame and freezes on the last frame.
    transmit("a=f,i=823,s=4,v=2,z=-1", (70, 113, 228, 255) * 8)
    transmit("a=f,i=823,s=4,v=2,z=90", (89, 222, 160, 255) * 8)
    commands += b"\x1b_Ga=a,i=823,r=1,z=80,s=3,v=2,q=2;\x1b\\"
    return commands


def terminal_sprites():
    lines = []
    for start in (0x2500, 0x2520, 0x2540, 0x2560, 0x2580, 0x1FB00):
        lines.append("".join(chr(cp) for cp in range(start, start + 32)))
    lines.extend((
        "⠁⠂⠄⡀⠈⠐⠠⢀ ⡇⢸⣿⣄⣤⣶⣷⣾⣽⣻⡿⢿⠀ ◸◹◺◿",
        "\x1b[38;2;106;201;170m\x1b[48;2;31;47;59m"
        + "".join(chr(cp) for cp in range(0xE0B0, 0xE0C0)) + "\x1b[0m",
        "╭──────────┬──────╮ ╔════╦════╗",
        "│ ▓▒░ ▏▎▍▌ │ ⠗⣷⣿⡇ │ ╠════╬════╣",
        "╰──────────┴──────╯ ╚════╩════╝",
    ))
    return "".join(f"\x1b[{row};1H{text}" for row, text in enumerate(lines, 1)).encode()


def scrollback_output():
    attrs = termios.tcgetattr(sys.stdin)
    tty.setraw(sys.stdin)
    try:
        r, g, b = SCROLLBACK_LAST_COLOR
        marker = f"\x1b[48;2;{r};{g};{b}m"
        rows = [
            f"\x1b[48;5;42m  \x1b[0m Output row {row:02d} · {'█' * (row % 13)}"
            for row in range(1, 48)
        ]
        rows.append(f"{marker}  \x1b[0m Output row 48")
        sys.stdout.write("\r\n".join(rows))
        sys.stdout.flush()
        if sys.stdin.read(1):
            # The palette change is visible in both the live and scrolled views.
            # It also confirms the PTY received the input that produces row 49.
            color = bytes(SCROLLBACK_RECOLORED).hex()
            sys.stdout.write(f"\x1b]4;42;#{color}\x07\r\n\x1b[1mNew output, row 49\x1b[0m")
            sys.stdout.flush()
            sys.stdin.read(1)
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSANOW, attrs)


def wait_for_terminal_size(matches, expected):
    deadline = time.monotonic() + 5
    while True:
        size = os.get_terminal_size(sys.stdout.fileno())
        if matches(size):
            return
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Expected {expected}, got a {size.columns}×{size.lines} PTY")
        time.sleep(0.01)


def wait_for_initial_grid():
    wait_for_terminal_size(lambda size: size == (GRID_COLUMNS, GRID_ROWS), f"a {GRID_COLUMNS}×{GRID_ROWS} PTY")


def resize_pending_wrap():
    wait_for_initial_grid()
    # The next printable character would normally wrap to the next row.
    line = "Full line before widening " + "1234567890" * GRID_COLUMNS
    sys.stdout.write("\x1b[2 q\x1b[?25h" + line[:GRID_COLUMNS])
    sys.stdout.flush()
    wait_for_terminal_size(lambda size: size.columns > GRID_COLUMNS, "a wider PTY")
    r, g, b = RESIZE_WRAP_COLOR
    return f"\x1b[48;2;{r};{g};{b}mX\x1b[0m".encode()


def resize_prompt_last():
    wait_for_initial_grid()
    # The command starts on one row and wraps after the window narrows.
    return (
        b"Previous command output\r\n\x1b]133;A;redraw=last\x07bash$ \x1b]133;B\x07"
        b"printf '%s\\n' 'a long command waiting for redraw'\x1b[2 q\x1b[?25h"
    )


def colored_line_erase():
    # An erase issued before the startup resize uses the old right edge.
    wait_for_initial_grid()
    return (
        "Colored line erase\x1b[2;1HErase to end \x1b[48;2;71;99;143m\x1b[K\x1b[0m"
        "\x1b[3;23HErase to start\x1b[3;22H\x1b[48;2;55;105;81m\x1b[1K\x1b[0m"
        "\x1b[4;17HPreviously visible\x1b[48;2;112;73;96m\x1b[2K\x1b[1GErase whole row\x1b[0m"
        f"\x1b[{GRID_ROWS};1HLast row \x1b[48;2;99;75;59m\x1b[K\x1b[0m"
    ).encode()


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
        "selection-wide": (
            "Select across the second cell of a wide glyph\n"
            "0123456789ABCDEFGHIJKLMNOPQRST\n"
            "Default  \x1b[31;44mstyled text\x1b[0m  \x1b[7;33;45minverse colors\x1b[0m\n"
            "wide glyphs  😀 + café  │██░▒▓│\n"
            "This line stays unselected\n"
        ).encode(),
        "preedit-inline": (
            b"Unicode input preview\n"
            b"\x1b[3;1H\x1b[38;2;140;191;252;48;2;50;62;73m"
            b" styled text: ABCDEFGHIJKLMNOPQRSTUVWX \x1b[0m\x1b[3;17H\x1b[?25h"
        ),
        "preedit-edge": b"Unicode input near the right edge\x1b[6;57H\x1b[?25h",
        "resize-cursor-in-blanks": b"shell % \r\nabc\x1b[1;56H\x1b[2 q\x1b[?25h",
        "resize-cursor-near-bottom": (
            b"line 1 before resize\r\n\x1b[10;1Hbottom "
            b"\x1b[33mline that should remain visible after resize\x1b[0m\x1b[2 q\x1b[?25h"
        ),
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
    elif fixture == "kitty-relative":
        sys.stdout.buffer.write(kitty_relative())
    elif fixture == "kitty-delete-selection":
        sys.stdout.buffer.write(kitty_delete_selection())
    elif fixture == "kitty-delete-visible":
        sys.stdout.buffer.write(kitty_delete_visible())
    elif fixture == "kitty-chunked":
        sys.stdout.buffer.write(kitty_chunked())
    elif fixture == "kitty-animation":
        sys.stdout.buffer.write(kitty_animation())
    elif fixture == "terminal-sprites":
        sys.stdout.buffer.write(terminal_sprites())
    elif fixture == "colored-line-erase":
        sys.stdout.buffer.write(colored_line_erase())
    elif fixture == "resize-pending-wrap":
        sys.stdout.buffer.write(resize_pending_wrap())
    elif fixture == "resize-prompt-last":
        sys.stdout.buffer.write(resize_prompt_last())
    elif fixture in SCROLLBACK_FIXTURES:
        scrollback_output()
        return
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
