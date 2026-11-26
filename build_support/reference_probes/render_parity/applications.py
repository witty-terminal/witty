import os
import shutil
import subprocess
import tempfile
import time

from capture import open_window, read_window
from fixtures import GRID_COLUMNS, GRID_ROWS


APPLICATION_STAGES = {
    "less": ("", "-search", "-search-next"),
    "tmux": ("", "-switch-pane"),
}
LESS_MARKERS = {1: (24, 130, 80), 15: (54, 92, 156), 29: (144, 80, 120)}
TMUX_ACTIVE = (24, 130, 80)
NEOVIM_FIXTURES = {"nvim-diagnostics": 0, "nvim-selection": 1}
NEOVIM_SCRIPT = '''local api = vim.api

vim.o.termguicolors = true
vim.o.background = "dark"
vim.o.shortmess = "I"
vim.o.number = true
vim.o.signcolumn = "no"
vim.o.laststatus = 2
vim.o.statusline = " Neovim %=%{mode()} "
vim.o.showmode = false
vim.o.showcmd = false
vim.o.ruler = false
vim.o.guicursor = "a:block-blinkon0"

api.nvim_set_hl(0, "Normal", { fg = "#e4e5e9", bg = "#161820" })
api.nvim_set_hl(0, "LineNr", { fg = "#8194ad" })
api.nvim_set_hl(0, "EndOfBuffer", { fg = "#8194ad" })
api.nvim_set_hl(0, "StatusLine", { fg = "#eff4ff", bg = "#344566", bold = true })
api.nvim_set_hl(0, "Visual", { fg = "#f2f7ff", bg = "#404d90" })
api.nvim_set_hl(0, "FixtureKeyword", { fg = "#95c3ff", bold = true })
api.nvim_set_hl(0, "FixtureComment", { fg = "#84ba8d", italic = true })
api.nvim_set_hl(0, "DiagnosticUnderlineError", { undercurl = true, sp = "#ff6080" })
api.nvim_set_hl(0, "DiagnosticVirtualTextError", { fg = "#ff9db0", bg = "#453141" })

local lines = {
  'local label = "café 🚀"',
  "return read(label)",
  "",
  "-- Wide cells ┌─┐ and combining accents é",
}
api.nvim_buf_set_lines(0, 0, -1, false, lines)
local namespace = api.nvim_create_namespace("witty-fixture")
api.nvim_buf_set_extmark(0, namespace, 0, 0, { end_col = 5, hl_group = "FixtureKeyword" })
api.nvim_buf_set_extmark(0, namespace, 1, 0, { end_col = 6, hl_group = "FixtureKeyword" })
api.nvim_buf_set_extmark(0, namespace, 3, 0, { end_col = #lines[4], hl_group = "FixtureComment" })
vim.diagnostic.set(namespace, 0, {
  { lnum = 1, col = 7, end_col = 11, message = "Undefined name", severity = vim.diagnostic.severity.ERROR },
}, { signs = false, underline = true, virtual_text = { prefix = "!", spacing = 2 } })
if vim.g.parity_select == 1 then
  api.nvim_win_set_cursor(0, { 1, 14 })
  vim.cmd("normal! v$")
else
  api.nvim_win_set_cursor(0, { 1, 0 })
end
'''


def prepare_neovim(work, executable):
    (work / "editor.lua").write_text(NEOVIM_SCRIPT, encoding="utf-8")
    return {
        name: (
            "--term=xterm-256color", "-e", executable, "-u", "NONE", "-i", "NONE", "-n",
            "--cmd", f"let g:parity_select = {select}", "-c", "luafile editor.lua",
        )
        for name, select in NEOVIM_FIXTURES.items()
    }


def prepare_applications(work, fixtures):
    if "less" in fixtures:
        lines = []
        for i in range(1, 38):
            marker = LESS_MARKERS.get(i, (62, 66, 86))
            color = ";".join(map(str, marker))
            label = "Search for needle" if i in (15, 29) else "Terminal pager line"
            lines.append(f"\x1b[48;2;{color}m  {i:02}  \x1b[0m  {label}\n")
        (work / "pager.txt").write_text("".join(lines))
    if "tmux" in fixtures:
        (work / "tmux.conf").write_text(
            "set -g default-shell /bin/sh\n"
            "set -g status-interval 0\n"
            "set -g status-left 'tmux fixture  '\n"
            "set -g status-right ''\n"
            "set -g window-status-format ''\n"
            "set -g window-status-current-format ''\n"
            "set -g status-style 'fg=white,bg=blue'\n"
            "set -g pane-border-status top\n"
            "set -g pane-border-format '#{?pane_active,#[bg=green],#[bg=blue]}        #[default]Pane #{pane_index}'\n"
        )


def capture_application_frame(helper, window, output, settle, visible):
    time.sleep(settle)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        with read_window(helper, window) as image:
            if visible(image):
                image.save(output)
                return
        time.sleep(0.05)
    raise RuntimeError(f"The terminal did not render {output.stem}")


def capture_less(binary, args, helper, output, app, work, settle, scale, padding):
    command = [
        binary, *args, "-e", shutil.which("env"), "-i", "TERM=xterm-256color", "LC_ALL=C.UTF-8",
        "LESSHISTFILE=-", "LESSSECURE=1", shutil.which("less"), "-R", "-PsPager fixture", work / "pager.txt",
    ]
    with open_window(command, output / f"less-{app}.log") as (_, window):
        subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
        actions = ((1, ()), (15, ("slash", "n", "e", "e", "d", "l", "e", "Return")), (29, ("n",)))
        point = ((padding + 1) * scale, (padding + 1) * scale)
        for stage, (row, keys) in zip(APPLICATION_STAGES["less"], actions):
            if keys:
                subprocess.run(["xdotool", "key", *keys], check=True, timeout=5)
            capture_application_frame(helper, window, output / f"less{stage}-{app}.png", settle,
                                      lambda image: image.getpixel(point) == LESS_MARKERS[row])


def tmux_fixture_command(server, work, columns, rows, *, switch_pane=False):
    left = r"printf '\033[?25lLeft pane\r\n┌────┐\r\n│ ░░ │\r\n└────┘\r\n'; exec sleep 60"
    right = r"printf '\033[?25lRight pane\r\n╔════╗\r\n║ ██ ║\r\n╚════╝\r\n'; exec sleep 60"
    command = [
        *server, "-f", work / "tmux.conf", "new-session", "-d", "-x", str(columns),
        "-y", str(rows), "-s", "parity", left, ";", "split-window", "-h", "-t", "parity", right, ";",
    ]
    if switch_pane:
        command.extend(("set-hook", "-t", "parity", "client-attached", "select-pane -t parity:.0", ";"))
    command.extend(("attach-session", "-t", "parity"))
    return command


def capture_tmux(binary, args, helper, output, app, work, settle, scale):
    env = os.environ.copy()
    env.pop("TMUX", None)
    env.pop("TMUX_PANE", None)
    with tempfile.TemporaryDirectory(prefix="witty-tmux-", dir="/tmp") as socket_dir:
        tmux = [shutil.which("tmux"), "-S", f"{socket_dir}/server"]
        command = [
            binary, *args, f"--palette=2={bytes(TMUX_ACTIVE).hex()}",
            "-e", *tmux_fixture_command(tmux, work, GRID_COLUMNS, GRID_ROWS),
        ]
        try:
            with open_window(command, output / f"tmux-{app}.log", env=env) as (_, window):
                subprocess.run(["xdotool", "windowfocus", "--sync", window], check=True, timeout=5)
                for stage, right_active in zip(APPLICATION_STAGES["tmux"], (True, False)):
                    if not right_active:
                        subprocess.run(["xdotool", "key", "ctrl+b", "o"], check=True, timeout=5)

                    def active_pane_visible(image):
                        start = image.width // 2 if right_active else 0
                        end = start + image.width // 2
                        top = image.crop((start, 0, end, 20 * scale))
                        return any(color == TMUX_ACTIVE for _, color in top.getcolors(top.width * top.height))

                    capture_application_frame(helper, window, output / f"tmux{stage}-{app}.png",
                                              settle, active_pane_visible)
        finally:
            subprocess.run([*tmux, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=5)
