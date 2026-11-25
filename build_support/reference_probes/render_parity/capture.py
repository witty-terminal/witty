from contextlib import contextmanager
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image


def configure_xvfb_capture(scale=1):
    os.environ.update(
        GDK_BACKEND="x11",
        GSK_RENDERER="cairo",
        GDK_SCALE=str(scale),
        GDK_DPI_SCALE="1",
        GSETTINGS_BACKEND="memory",
        GTK_A11Y="none",
        LIBGL_ALWAYS_SOFTWARE="1",
        LC_ALL="C.UTF-8",
    )


def capture_witty(binary, args, prefix, settle):
    png = prefix.with_suffix(".png")
    log_path = prefix.with_suffix(".log")
    with log_path.open("wb") as log:
        result = subprocess.run(
            [binary, f"--screenshot={png}", *args],
            stdout=log,
            stderr=subprocess.STDOUT,
            env={**os.environ, "SCREENSHOT_SETTLE_SECONDS": str(settle)},
            timeout=15 + settle,
        )
    if result.returncode or not png.is_file():
        raise RuntimeError(f"Witty capture failed with status {result.returncode}. See {log_path}")


def build_window_reader(helper):
    source = Path(__file__).with_name("window_ppm.c")
    subprocess.run(["cc", "-Wall", "-Wextra", "-Werror", source, "-o", helper, "-lX11"], check=True)


def find_window(process, log_path):
    application = Path(process.args[0]).name
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        status = process.poll()
        if status is not None:
            raise RuntimeError(f"{application} exited with status {status}. See {log_path}")
        windows = subprocess.run(
            ["xdotool", "search", "--onlyvisible", "--pid", str(process.pid)],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
        ).stdout.split()
        if windows:
            return windows[-1]
        time.sleep(0.05)
    raise RuntimeError(f"{application} did not open a visible window. See {log_path}")


@contextmanager
def open_window(command, log_path):
    with log_path.open("wb") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            yield process, find_window(process, log_path)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def read_window(helper, window):
    pixels = subprocess.check_output([helper, window], timeout=5)
    return Image.open(io.BytesIO(pixels))


def write_versions(output, *binaries):
    with (output / "versions.txt").open("w") as versions:
        for binary in binaries:
            digest = hashlib.sha256()
            with binary.open("rb") as executable:
                for chunk in iter(lambda: executable.read(1024 * 1024), b""):
                    digest.update(chunk)
            versions.write(f"{digest.hexdigest()}  {binary}\n")
            versions.write(
                subprocess.check_output(
                    [binary, "--version"], text=True, stderr=subprocess.STDOUT, timeout=10
                )
            )
            versions.write("\n")


def output_directory(path):
    if path is not None:
        output = path.resolve()
        output.mkdir(parents=True)
        return output
    root = Path(__file__).resolve().parents[3]
    base = root / ".witty-build" / "render-parity"
    base.mkdir(parents=True, exist_ok=True)
    return Path(tempfile.mkdtemp(prefix="run-", dir=base))
