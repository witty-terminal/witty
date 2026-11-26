#!/usr/bin/env python3
"""Generate the live link preview's coverage masks on a 2× macOS display."""

import argparse
import bisect
import struct
import subprocess
import tempfile
from pathlib import Path

from PIL import Image


PROBE = Path(__file__).resolve().with_suffix(".swift")
ASSETS = PROBE.parents[3] / "build_assets" / "macos"
OPACITIES = [1 - step / 128 for step in range(65)]
HALF_VALUES = [struct.unpack("<e", struct.pack("<H", bits))[0] for bits in range(0x3C01)]


def alpha_intervals():
    """Invert the half-float color buffer and its final 8-bit capture."""
    intervals = {}
    for i, alpha in enumerate(HALF_VALUES):
        sample = round(255 * alpha)
        lo = (alpha + HALF_VALUES[i - 1]) / 2 if i > 0 else 0
        hi = (alpha + HALF_VALUES[i + 1]) / 2 if i + 1 < len(HALF_VALUES) else 1
        intervals[sample] = (intervals.get(sample, (lo, hi))[0], hi)
    return intervals


def recover_coverage(samples, opaque_samples, intervals):
    if samples == opaque_samples:
        return 65535
    if not any(samples):
        return 0
    lo = max(intervals[sample][0] / opacity for sample, opacity in zip(samples, OPACITIES))
    hi = min(intervals[sample][1] / opacity for sample, opacity in zip(samples, OPACITIES))
    first = bisect.bisect_left(HALF_VALUES, lo)
    last = bisect.bisect_right(HALF_VALUES, hi)
    if first == last:
        raise ValueError(f"Inconsistent alpha samples {samples}")
    midpoint = (lo + hi) / 2
    alpha = min(HALF_VALUES[first:last], key=lambda a: abs(a - midpoint))
    return round(alpha * 65535)


def pack_masks(directory, scale):
    # The rounded edge stops changing once it meets the straight top edge.
    min_width, max_width, corner_size = (20, 29, 28) if scale == 2 else (10, 15, 14)
    captured_widths = 15 if scale == 2 else 8
    control_y = ((captured_widths * 4 + 11) // 12) * 60 + 5
    captures = []
    for step in range(len(OPACITIES)):
        with Image.open(directory / f"{step}.png") as png:
            captures.append(png.convert("RGBA").getchannel("A"))
    opaque = [image.getpixel((5, control_y)) for image in captures]
    if opaque != [round(255 * opacity) for opacity in OPACITIES]:
        raise ValueError("Opacity ramp differs from its control swatch")

    intervals = alpha_intervals()
    masks = []
    for width in range(min_width, max_width + 1):
        for phase in range(4):
            index = (width - min_width) * 4 + phase
            x0 = (index % 12) * 44 + 2 + ((phase ^ width) & 1)
            y0 = (index // 12) * 60 + 2 + (phase >> 1)
            mask = bytearray()
            for y in range(corner_size):
                coverage = []
                for x in range(min(width, corner_size)):
                    samples = [image.getpixel((x0 + width - 1 - x, y0 + y)) for image in captures]
                    coverage.append(recover_coverage(samples, opaque, intervals))
                first = next((x for x, alpha in enumerate(coverage) if alpha != 0), len(coverage))
                end = next((x + 1 for x in reversed(range(first, len(coverage)))
                            if coverage[x] != 65535), first)
                band = coverage[first:end]
                mask.extend((first, len(band)))
                mask.extend(struct.pack(f"<{len(band)}H", *band))
            masks.append(mask)

    # Little-endian byte offsets followed by one row stream per width and phase.
    offset = len(masks) * 2
    packed = bytearray()
    for mask in masks:
        packed.extend(struct.pack("<H", offset))
        offset += len(mask)
    return packed + b"".join(masks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures", type=Path, help="Reuse an existing alpha1 and alpha2 pair")
    args = parser.parse_args()
    if args.captures is not None:
        for scale in (1, 2):
            data = pack_masks(args.captures / f"alpha{scale}", scale)
            (ASSETS / f"hover_corner_masks_{scale}x.bin").write_bytes(data)
        return
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        probe = temp / "probe"
        subprocess.run(["swiftc", "-parse-as-library", str(PROBE), "-o", str(probe)], check=True)
        for scale in (1, 2):
            captures = temp / f"alpha{scale}"
            captures.mkdir()
            subprocess.run([str(probe), str(captures), str(scale)], check=True)
            (ASSETS / f"hover_corner_masks_{scale}x.bin").write_bytes(pack_masks(captures, scale))


if __name__ == "__main__":
    main()
