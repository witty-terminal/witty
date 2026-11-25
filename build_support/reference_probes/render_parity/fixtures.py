import base64
import os
import subprocess
import sys


CLEAR = b"\x1b[2J\x1b[H\x1b[?25l"


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


def main():
    fixture = sys.argv[1]
    output = {
        "ansi": b"Witty GPU parity\n\x1b[1;31mBold red\x1b[0m "
                b"\x1b[3;32mItalic green\x1b[0m \x1b[44;97m Blue cell \x1b[0m\n",
        "unicode": "café · 日本語 · Σ · 😀\n─ ║ █ ░ ☀\n".encode(),
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
    else:
        sys.stdout.buffer.write(output[fixture])
    sys.stdout.flush()
    # Keep the PTY open after emitting the fixture for the reference capture.
    sys.stdin.read(1)


if __name__ == "__main__":
    main()
