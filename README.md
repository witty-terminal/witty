A translated fork of Ghostty

`Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors`


<img width="752" height="528" alt="image" src="https://github.com/user-attachments/assets/5962e635-1197-48f7-9926-e564ff4f4c84" />

## Building on Linux

Install `make`, the V revision pinned in CI, and the Linux dependencies listed in the CI workflow. [V compiler setup](.github/scripts/install-v.sh) · [Linux dependencies](.github/workflows/ci.yml)

Run this command from the repository root.

```sh
make
```

Witty builds its bundled glslang shader compiler into `.witty-build/native/libglslang.a`. The `libslang-devel` package provides the separate S-Lang library. If `v .` reports that the archive is missing, run `make` from the Witty checkout or invoke the build driver directly. Both commands build the native dependencies before compiling Witty.

```sh
VFLAGS='-cc clang' v -path "$PWD|@vlib|@vmodules" run tools/build install
```

Run the installed application with `./v-out/bin/witty`.

## Capturing the terminal

Witty saves the rendered terminal viewport at backing-pixel resolution and exits.
On macOS, capture writes a Display P3 PNG offscreen and works without Screen Recording permission.

```sh
./Witty.app/Contents/MacOS/witty --screenshot=/tmp/witty.png -e /bin/ls -G
```

On Linux, capture reads the OpenGL frame from a GTK window. Run it on a desktop or use Xvfb for automation.

```sh
xvfb-run -a ./v-out/bin/witty --screenshot=/tmp/witty.png -e /bin/ls --color=always
```

Set `SCREENSHOT_SETTLE_SECONDS` to change the default two-second wait before capture.
