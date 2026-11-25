# Terminal render comparison

## Linux

Run this probe on Linux with an installed [Ghostty GTK release](https://ghostty.org/download), Python 3 with Pillow, DejaVu Sans Mono, Xvfb, `xauth`, `dbus-run-session`, `xdotool`, a C compiler with X11 headers, GNU `ls`, Git, and Vim.

The probe works with debug and release builds. This command builds Witty with the settings used by the on-demand parity workflow.

```sh
VFLAGS='-cc clang -nocache' v -path "$PWD|@vlib|@vmodules" run tools/build install \
  -Doptimize=ReleaseSafe --prefix "$PWD/.witty-build/render-parity-witty"
```

From the repository root, start a fresh 24-bit Xvfb session and pass the two executable paths.

```sh
xvfb-run -a -s "-screen 0 1440x900x24" dbus-run-session -- \
  python3 build_support/reference_probes/render_parity/run.py \
  .witty-build/render-parity-witty/bin/witty "$(command -v ghostty)"
```

The probe uses Witty’s `--screenshot` and captures Ghostty’s matching X11 client window. It compares decoded RGBA pixels for ANSI colors, Unicode and emoji, Kitty images, colored `ls` output, Git diff, Vim, and a two-pass GLSL shader.

Each run saves the PNGs, application logs, executable versions and hashes, and a `results.tsv` report under `.witty-build/render-parity/`. Differing pixels appear white in the corresponding `*-diff.png` mask. A size or pixel mismatch returns exit status 1.

Use `--output` to choose a new directory, `--fixture` to repeat a single case, or `--settle-seconds` to allow more time for rendering on a slower host.

The regular Linux CI build checks two grid sizes with the default window settings and also verifies capture with a configured tab bar. Each screenshot must contain the colored terminal cell.

The [Linux render parity workflow](../../../.github/workflows/render-parity.yml) runs on demand in GitHub Actions. It builds Witty on Ubuntu 26.04, verifies and extracts the pinned Ghostty 1.4.0 reference package, and uploads the screenshots, logs, and report. On Ubuntu 26.04 with the capture dependencies installed, the same script can compare an existing Witty build locally.

```sh
bash .github/scripts/linux-render-parity.sh \
  .witty-build/render-parity-witty/bin/witty .witty-build/render-parity/ubuntu-26
```

## macOS

Run with a built Witty app and Python 3 with Pillow.

```sh
python3 build_support/reference_probes/render_parity/run_macos.py \
  ./Witty.app/Contents/MacOS/witty
```

The probe runs Witty's screenshot command offscreen and compares the dimensions and SHA-256 of the decoded RGBA pixels in ten fixtures. It saves screenshots, logs, the executable hash, and a comparison report under `.witty-build/render-parity/`. It accepts the same `--output`, `--fixture`, and `--settle-seconds` options.

The [reference table](ghostty-1.4.0-macos.tsv) uses captures from Ghostty's own terminal IOSurface at 2× on Apple Silicon running macOS 27.2. It covers the cursor, sRGB blending, translucent Kitty graphics, both explicit and default Vim window sizing, colored `ls`, Git diff, and zsh. The original Ghostty 1.4.0 executable had SHA-256 `4b30ac9b049cdf9eb75b6d8c7764856c2b882de97c688dce8a1b80916b55271b`. [Ghostty download](https://ghostty.org/download)
