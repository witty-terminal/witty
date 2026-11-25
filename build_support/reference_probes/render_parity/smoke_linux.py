import argparse
from pathlib import Path
import subprocess

from PIL import Image

from capture import capture_witty, configure_xvfb_capture, output_directory


COLUMNS = 60
ROWS = 12
PADDING = 2
COMMAND = r'printf "\033[2J\033[H\033[?25l\033[48;2;255;0;0m     \033[0m"; exec /bin/sleep 20'
UNLINKABLE_SHADER = """\
layout(location = 2) in vec4 input_color;
void mainImage(out vec4 color, in vec2 uv) {
    color = input_color;
}
"""


def capture_grid(binary, name, columns, rows, *options):
    capture_witty(
        binary,
        [
            "--config-default-files=false",
            f"--window-padding-x={PADDING}",
            f"--window-padding-y={PADDING}",
            f"--window-width={columns}",
            f"--window-height={rows}",
            "--shell-integration=none",
            *options,
            "-e", "/bin/sh", "-c", COMMAND,
        ],
        name,
        1,
    )
    with Image.open(name.with_suffix(".png")) as png:
        frame = png.convert("RGB")
        marker = frame.getpixel((PADDING + 1, PADDING + 1))
        if marker != (255, 0, 0):
            raise RuntimeError(f"{name}.png is missing the terminal's red cell background")
        return frame.size


def main():
    parser = argparse.ArgumentParser(description="Check Linux screenshot content and viewport sizing in Xvfb.")
    parser.add_argument("witty", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    configure_xvfb_capture()
    try:
        output = output_directory(args.output)
        binary = args.witty.resolve()
        width, height = capture_grid(binary, output / "grid-60x12", COLUMNS, ROWS)
        wider, taller = capture_grid(binary, output / "grid-61x13", COLUMNS + 1, ROWS + 1)
        expected_width = COLUMNS * (wider - width) + 2 * PADDING
        expected_height = ROWS * (taller - height) + 2 * PADDING
        if (width, height) != (expected_width, expected_height):
            raise RuntimeError(
                f"Expected a {expected_width}x{expected_height} viewport for "
                f"{COLUMNS}x{ROWS} cells, captured {width}x{height}. See {output}"
            )
        with_tabs = capture_grid(
            binary, output / "grid-60x12-tabs", COLUMNS, ROWS,
            "--window-decoration=client",
            "--gtk-titlebar-style=tabs",
            "--window-show-tab-bar=always",
        )
        if with_tabs != (width, height):
            raise RuntimeError(f"The configured tabs changed the capture size to {with_tabs}. See {output}")

        shader = output / "missing-vertex-output.glsl"
        shader.write_text(UNLINKABLE_SHADER)
        fallback = output / "shader-fallback"
        # The fragment shader compiles, but its input has no matching vertex output.
        if capture_grid(binary, fallback, COLUMNS, ROWS, f"--custom-shader={shader}") != (width, height):
            raise RuntimeError(f"Post-processing fallback changed the capture size. See {output}")
        log = fallback.with_suffix(".log")
        if "error initializing postprocess shaders" not in log.read_text():
            raise RuntimeError(f"Expected OpenGL to reject the post-processing pipeline. See {log}")
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Linux screenshot check failed: {error}\n")
    print(f"Verified terminal grid sizing and rendering after a shader link failure. See {output}")


if __name__ == "__main__":
    main()
