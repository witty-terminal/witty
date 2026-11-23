# Built-in Metal shader artifact

`create(repo_root, Options)?Step` translates Ghostty's
`src/build/MetallibStep.zig`, including the macOS/iOS SDK, simulator minimum
version flag, and default versions. `build(repo_root, Options)!BuildResult`
executes its metal compilation before metallib archive creation. A non-Apple
OS returns a result whose output is absent; tool failures return an error.

The production Metal build must call this helper before compiling the renderer,
then pass `-d compiled_metallib`. The output is
`.witty-build/native/witty.metallib` (with intermediate `witty.ir`).
The renderer embeds that data and calls `newLibraryWithData:error:` through
libdispatch data. Direct compiler invocations without the prerequisite return
`MetalShaderLibraryNotBuilt` when loading the built-in library.
Custom shaders retain the original independent source compilation path.

Apple's Metal compiler is an external prerequisite. This audit host only has
Command Line Tools at `/Library/Developer/CommandLineTools`, without Xcode or
`metal`. The real helper invocation therefore fails through xcrun (exit 72).
SDK/argument mapping and the unconfigured guard were executed. Compilation of
the real metallib and its GPU loading were not executed on this host; no fake
artifact or runtime compilation fallback is used.
