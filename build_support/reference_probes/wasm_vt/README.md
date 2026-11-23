The production build uses the selected V compiler's C backend and Emscripten's unchanged runtime to produce the source Wasm C ABI. Emscripten 4.0.10 was used for validation. Set `EMCC` and, when using a local SDK, `EM_CONFIG`, then invoke `tools/build lib-vt -Dtarget=wasm32-freestanding` with an isolated prefix. The installed `bin/witty-vt.js` and `bin/witty-vt.wasm` stay together; Node's factory export and the browser's `GhosttyVT` factory load that same binary. `ghosttyLog(text)` optionally supplies the source `env.log` host; the default uses the original examples' TextDecoder/console behavior.

```sh
node build_support/reference_probes/wasm_vt/run.cjs /path/to/prefix/bin/witty-vt.js
python3 build_support/reference_probes/wasm_vt/compare_log.py /path/to/ghostty /path/to/zig-0.15.2 /path/to/v /path/to/emcc /path/to/.emscripten
```

The installed artifact probe checks all 50 source exports, the upstream Kitty key example's result, OSC title/reset, Kakoune SGR attributes, unsafe paste detection, checked enum/SGR warnings, every paired allocation/free family, and growth updating the runtime heap views. The source SGR enum's exported tags differ from the pinned C header (which inserts RESET_UNDERLINE); the probe follows the unchanged implementation, as documented in the VT C example probe.

The logger comparison compiles both original `os/wasm` files byte-for-byte, wraps their function with the original `lib_vt.zig` std_options branch, and compares six actual Wasm fixtures in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall. It covers default/scoped prefixes, level filtering and the 2048-byte stack buffer/allocation fallback. V callers format their messages before invoking the translated logging function; the buffer and allocation operations remain those of the source.

Compiler adaptations are explicit: C backend imports are isolated to the source VT dependency boundary; Emscripten supplies the compiler runtime's actual OS/libc imports; static data starts at 64 KiB because this selected V runtime suppresses memory operations on lower pointers; its musl float parser uses decimal dots directly where locale-specific strtod_l/strtof_l are unavailable. The installed JS loader is required for those runtime imports. This changes compiler/runtime glue, not the terminal algorithms. Browser execution was not available during this validation.
