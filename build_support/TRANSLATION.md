The build driver translates Ghostty `6c0e02d1138d5376e4ac2f5e311b225494514a97` `build.zig` and `src/build/`. Run it with the selected V compiler in both the executable path and `VEXE`; this prevents another compiler tree from supplying incompatible `@vlib` declarations.

```sh
WITTY_V_COMPILER=/path/to/v
VEXE="$WITTY_V_COMPILER" "$WITTY_V_COMPILER" -path 'repo|@vlib|@vmodules' run tools/build --help
VEXE="$WITTY_V_COMPILER" "$WITTY_V_COMPILER" -path 'repo|@vlib|@vmodules' run tools/build install --prefix /tmp/witty-install
VEXE="$WITTY_V_COMPILER" "$WITTY_V_COMPILER" -path 'repo|@vlib|@vmodules' run tools/build test-lib-vt -Dtest-filter=key_event
```

The verified compiler for this port is V 0.5.2. Native dependency builds use structured argv and the artifact's target/SDK/optimization settings. The reference identity stays in `build_meta`; generated build identity comes from the current repository, options and artifact type.

| Original | Translation |
| --- | --- |
| Config, GitVersion, build_config | config.v, git_version.v, compile_options.v, target.v, buildcfg |
| SharedDeps and native package builders | native_graph.v, native_packages.v, native_* modules, pinned build_assets/native |
| GhosttyExe, GhosttyLib, GhosttyLibVt | artifacts.v |
| GhosttyResources, GhosttyDocs, GhosttyWebdata, GhosttyI18n | resources.v, locales.v, tools/build_data, tools/docgen |
| HelpStrings, UnicodeTables | generators.v, help_strings, tools/helpgen, tools/props_unigen, tools/symbols_unigen |
| GhosttyBench, GhosttyFrameData | installation.v, frame_data.v, tools/bench, tools/gen, build_assets/framegen |
| GhosttyDist and distcheck | distribution.v |
| GhosttyXCFramework, LibtoolStep, LipoStep, XCFrameworkStep | xcframework.v, artifacts.v |
| GhosttyXcodebuild and project bundle settings | macos_app.v, pinned build_assets/macos |
| install, run, tests and Valgrind graph | installation.v, testing.v, tools/build |

V has one executable per test file. The driver compiles and runs the selected source test set with the original Debug/baseline/strip/frame/unwind choices, propagates filters and failures, and can install those artifacts under bin/witty-tests. Native macOS contract tests are part of this translated test set; the original Swift XCTest compiler invocation is replaced by V compilation.

The macOS application compiler step builds the translated V AppKit host. The source resource folders, original plist/entitlements/assets, Debug versus ReleaseLocal settings, universal/native architectures, frameworks, signing, copy operations and run environment are retained. It does not compile the original Swift application. Asset catalogs, Metal libraries and XCFramework packaging require the original Apple SDK/Xcode tools; unavailable tools fail the actual build step.

Help documentation remains pinned generated input, as recorded in the audit. The restored emitter reproduces the original helpgen output exactly and supplies V record imports. Unicode generators consume an independently generated uucode two-stage buildtime input, run the translated full-u21 three-stage generator, and embed the new output. The native reproduction probe is under reference_probes/uucode_input; this does not regenerate Unicode by reading Ghostty's finished runtime lookup.

The selected V compiler's unchanged GC source is bundled into retargeted native libraries instead of linking a prebuilt host runtime. This is a compiler adaptation; it is not a replacement for Ghostty's application logic. Platform/compiler validation limits and inherited source omissions remain recorded in AUDIT_FINDINGS_ULTRA.md.

V represents the source's compile-time font backend alternatives as runtime tagged values. Their destructors and dispatch retain native Fontconfig/HarfBuzz entry points even with CoreText selected, so full native artifacts link those unchanged source packages (with FreeType and Darwin CoreText HarfBuzz integrations enabled). The selected backend and its application behavior remain the configured source choice. VT artifacts return before that native graph.
