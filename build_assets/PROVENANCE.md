The shell integration, C headers, locale catalogs and desktop/Windows assets
originated in Ghostty commit
`6c0e02d1138d5376e4ac2f5e311b225494514a97`.

`themes/` originated in the dependency pinned by that commit's `build.zig.zon`:
`ghostty-themes-release-20260126-150817-02c580d.tgz`, from
`https://deps.files.ghostty.org/ghostty-themes-release-20260126-150817-02c580d.tgz`.
Zig 0.15.2's package hash was checked before extracting it:
`N-V-__8AAM5RAwB5jHC1P1uqrabiz_ieQvfrIYNzs4eAY__c`.

These are source data and external integration assets. Build decisions and
generation/install orchestration are translated in `build_support/` and
`tools/`; they do not execute the upstream Zig build.
