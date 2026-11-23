The four C fixtures are adapted from `example/*/src/main.c` at Ghostty
`6c0e02d1138d5376e4ac2f5e311b225494514a97`. They exercise the actual exported
library and V runtime initialization from a C process, rather than linking
through a V test executable.

Build and install with the selected V compiler:

```
VEXE=/path/to/v /path/to/v -path "$PWD|@vlib|@vmodules" run tools/libvt_build --prefix /tmp/witty-vt
python3 build_support/reference_probes/vt_examples/check.py /tmp/witty-vt
```

All four exit successfully on macOS arm64 in both scalar and SIMD builds.
The SGR example inherits a pinned upstream header discrepancy: `sgr.h` declares
`GHOSTTY_SGR_ATTR_RESET_UNDERLINE` at value 8, while `terminal/sgr.zig`'s
`Attribute.Tag` has no corresponding member. The original C export reflects
the latter enum (underline color 8, foreground RGB 21, background RGB 22).
Consequently this unchanged example mislabels some parsed attributes. The V
implementation preserves the original parser/export tags; this example's
successful exit is not evidence that the upstream public enum is consistent.
