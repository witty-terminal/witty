A translated fork of Ghostty

`Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors`


<img width="752" height="528" alt="image" src="https://github.com/user-attachments/assets/5962e635-1197-48f7-9926-e564ff4f4c84" />

## Building on Linux

Install `make`, the V revision pinned in CI, and the Linux dependencies listed in the CI workflow. [V compiler setup](.github/scripts/install-v.sh) · [Linux dependencies](.github/workflows/ci.yml)

Run this command from the repository root.

```sh
make
```

The build driver creates `.witty-build/native/libglslang.a` and the other native dependencies before compiling Witty. If `v .` reports that `libglslang.a` is missing, use `make` or run the build driver directly with the following command.

```sh
VFLAGS='-cc clang' v -path "$PWD|@vlib|@vmodules" run tools/build install
```

Run the installed application with `./v-out/bin/ghostty`.
