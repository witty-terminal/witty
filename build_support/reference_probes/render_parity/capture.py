import hashlib
import os
from pathlib import Path
import subprocess
import tempfile


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
