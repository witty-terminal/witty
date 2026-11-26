# Terminal render comparison

## Linux

Run this probe on Linux with an installed [Ghostty GTK release](https://ghostty.org/download), Python 3 with Pillow, DejaVu Sans Mono, Xvfb, `xauth`, `dbus-run-session`, `xdotool`, a C compiler with X11 headers, GNU `ls`, Git, Vim, less, and tmux.

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

The probe uses Witty’s `--screenshot` and captures Ghostty’s matching X11 client window with decorations and the scrollbar hidden. It compares decoded RGBA pixels for ANSI colors, text decorations, Unicode and emoji, wide characters wrapping at the right edge, block, bar, and underline cursors, Kitty images and Unicode placeholders, stretched and repeated background images, colored `ls` output, Git diff, Vim, and a two-pass GLSL shader. The Kitty fixtures also cover clipping, retransmission, interrupted chunked uploads, relative placement, cursor movement, image deletion, scrollback clearing, and z-index ordering across cell backgrounds, text, and overlapping images. The animation fixture covers chunked frame edits, frame composition, and playback through a finite loop.

The terminal glyph fixtures cover box drawing, block elements, Braille patterns, and Powerline separators at default and adjusted cell sizes.
The grapheme fixture covers emoji presentation selectors and combining accents at the right edge, with grapheme clustering enabled and disabled.
The colored line erase fixture waits for the configured PTY grid before erasing to either edge and across a full row.
The wide glyph editing fixture renders a colored glyph across a wrap, then erases or deletes it and checks that the previous row redraws.
The text selection fixture uses a mouse drag starting on the second cell of an emoji to verify the highlight covers the full glyph.
The Unicode input fixtures capture GTK’s underlined preview over a terminal wallpaper and at the right edge before the character is committed.
The scrollback fixtures update the palette and append a row after scrolling into history, with `scroll-to-bottom=output` enabled and disabled.
The scrollbar fixtures drag through terminal history and compare the visible text and scrollbar at the bottom, during the drag, and at the top. They cover the default GTK overlay scrollbar and a fixed scrollbar with a CSS track, thumb, and border.
The search fixture drives scrollback search through keybindings and checks both highlight colors as navigation wraps from the newest match to the oldest and back.
The split search fixture captures the full GTK client window and compares both panes as Find takes focus in the right pane.
The `split-search-themed` fixture also checks custom CSS colors for the divider and the unfocused pane.
The `split-close` fixture closes a nested pane and verifies that the two surviving panes redraw with the expected focus.
The `visual-bell-themed` fixture checks a CSS fill and rounded border during an unfocused bell and verifies that refocusing clears the overlay.
The `progress-overlay-themed` fixture verifies the CSS colors of a paused progress fill and its trough.
The command exit fixtures capture the banner over terminal text after a successful command and a failed command with custom CSS. They also verify that the Close button exits the terminal.
The `readonly-overlay-themed` fixture checks that a custom badge background and fractional outlines match when the terminal enters read-only mode.
The resize fixtures narrow the window with the cursor after blank cells or near the bottom of the screen. They also check which row of a newly wrapped Bash prompt clears and where the next character appears after widening a full row.
The `font-zoom` fixture enlarges, shrinks, and resets the font while the terminal is open. It checks live reflow and compares text, emoji, and sprites after the glyph atlases change.
The `wallpaper-reload` fixture loads a PNG, turns on tiling, changes its opacity, and replaces it with a progressive JPEG. It then removes the wallpaper and reloads the original PNG while the terminal text stays on screen.
The `shader-reload` fixture enables a custom shader, adds and reorders a second pass, and replaces the chain with a single pass. It then removes and restores the shader while comparing the terminal text and colors at each stage.
The `terminal-colors` fixture applies OSC palette, foreground, background, and cursor colors to the running terminal. It compares the rendered colors after resetting the overrides and after reloading new defaults from the configuration file.

The `less` fixture captures an ANSI-colored file when it opens, after searching, and after advancing to the next match. The `tmux` fixture captures a two-pane session with box drawing, a colored status line, and focus switching with Ctrl+B followed by O.

Each run saves the PNGs, application logs, executable versions and hashes, and a `results.tsv` report under `.witty-build/render-parity/`. Differing pixels appear white in the corresponding `*-diff.png` mask. A size or pixel mismatch returns exit status 1.

Use `--output` to choose a new directory, `--fixture` to repeat a single case, or `--settle-seconds` to allow more time for rendering on a slower host. Pass `--scale 2` to compare HiDPI captures. The probe defaults to 1× and records the requested GTK scale in `versions.txt`.

The optional `gtk-chrome-tabs` and `gtk-chrome-native` fixtures capture the full GTK client window after opening a second tab. They cover the integrated title bar with configured colors and the native header with a bottom tab bar. Use a release Witty build for these fixtures to avoid the debug-build banner.

The optional `tab-overview` fixture uses a release build to capture two live thumbnails with configured window colors. It also searches for one tab and selects the result.

The `command-palette-resize` fixture narrows the window with the palette open. It captures the dimmed terminal text and palette together, then restores the window and closes the palette. The workflow also runs this fixture at 2× with the OpenGL compositor.

The `command-palette-themed` fixture applies custom CSS to the panel, search field, and selected row, then captures the filtered palette. The workflow runs this fixture with Cairo and with the OpenGL compositor at 2×.

The `terminal-title` fixture checks typing, canceling, applying, and resetting the title. The optional `close-confirmation` fixture verifies keyboard focus, canceling, and confirming the window close. It launches Witty normally and uses a release build to avoid the debug banner.

The regular Linux CI build checks the initial PTY and a full-width colored erase at two grid sizes, capture with a configured tab bar, and rendering after an OpenGL shader link failure. It also replaces a red shader with a green one in a running terminal and uses the reload keybinding to verify that the rendered frame changes.

The [Linux render parity workflow](../../../.github/workflows/render-parity.yml) runs on demand in GitHub Actions. It builds Witty on Ubuntu 26.04, verifies and extracts the pinned Ghostty 1.4.0 reference package, and uploads the screenshots, logs, and report. On Ubuntu 26.04 with the capture dependencies installed, the same script can compare an existing Witty build locally.

```sh
bash .github/scripts/linux-render-parity.sh \
  .witty-build/render-parity-witty/bin/witty .witty-build/render-parity/ubuntu-26-hidpi --scale 2
```

## macOS

Run with a built Witty app and Python 3 with Pillow.

```sh
python3 build_support/reference_probes/render_parity/run_macos.py \
  ./Witty.app/Contents/MacOS/witty
```

The probe runs Witty's screenshot command offscreen and compares the dimensions and SHA-256 of the decoded RGBA pixels. It saves screenshots, logs, the executable hash, and a comparison report under `.witty-build/render-parity/`. It accepts the same `--output`, `--fixture`, and `--settle-seconds` options.

The terminal text fixtures cover ligatures, ANSI colors and decorations, box drawing, Powerline separators, combining accents, wide characters, and emoji. The translucent cases check how styled cells and glyphs blend over a partially transparent background with unequal padding.

The `grapheme-sequences` fixture places emoji presentation selectors and combining accents at the right edge with clustering enabled and disabled. The `colored-line-erase` fixture checks the backgrounds after erasing to either edge and across a full row. The `wide-edit-before` and `wide-edit` fixtures capture wrapped double-width glyphs before and after erasing a glyph and deleting from its trailing cell. The fixtures wait for the configured PTY grid before writing text at the margin.

The `terminal-colors` fixtures compare live OSC changes to the palette, foreground, background, and cursor after the text is already on screen. They also check that resetting the overrides restores the initial frame and compare the overrides with reverse video and a translucent background.

The Kitty fixtures also check z-order across cell backgrounds and glyphs, cropped and offset placement, image replacement, and Unicode placeholders. The layering case runs with opaque and translucent backgrounds.

The wallpaper fixtures stretch and tile an alpha PNG behind styled text and colored cells. The shader fixtures run a tint pass followed by a channel swap with default and linear-corrected blending. `shader-wallpaper` runs that chain over the translucent tiled wallpaper.

The `text-balanced` fixture checks equal vertical padding in a viewport with room left after laying out the grid. The `vim-saved` fixture uses explicit grid dimensions and padding to reproduce the viewport from a restored Ghostty window.

The `pager-search` and `pager-search-next` fixtures use the system `less` (version 668 for the reference). They run a search and a repeat search through the pager's startup commands, checking the inverted matches, ANSI backgrounds, line numbers, and end-of-file rows. The pager fixtures with explicit dimensions wait for the configured PTY grid before opening the file.

The optional `tmux` and `tmux-switch-pane` fixtures compare pane borders, the status line, and the active-pane highlight. The second case selects the left pane when the client attaches. The references use tmux 3.8. With `tmux` on `PATH`, run both cases with the same Witty executable.

```sh
python3 build_support/reference_probes/render_parity/run_macos.py \
  ./Witty.app/Contents/MacOS/witty --fixture tmux --fixture tmux-switch-pane
```

The optional `nvim-diagnostics` and `nvim-selection` fixtures use Neovim 0.12.6. They check the colored diagnostic undercurl, inline diagnostic text, and a visual selection across a wide emoji. With `nvim` on `PATH`, select both fixtures to compare the editor frames.

```sh
python3 build_support/reference_probes/render_parity/run_macos.py \
  ./Witty.app/Contents/MacOS/witty --fixture nvim-diagnostics --fixture nvim-selection
```

The [reference table](ghostty-1.4.0-macos.tsv) uses captures from Ghostty's own terminal IOSurface at 2× on Apple Silicon running macOS 27.2. The Metal output is Display P3, including in fixtures where the terminal interprets its input colors as sRGB. The application fixtures cover Vim and `less` at explicit and default window sizes, colored `ls`, Git diff, and zsh. The `less` fixtures wait for the PTY grid before capturing the numbered lines and status prompt. The original Ghostty 1.4.0 executable had SHA-256 `4b30ac9b049cdf9eb75b6d8c7764856c2b882de97c688dce8a1b80916b55271b`. [Ghostty download](https://ghostty.org/download)
