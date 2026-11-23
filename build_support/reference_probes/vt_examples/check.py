"""Compile and run the unchanged pinned Ghostty C examples against installed V artifacts."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("prefix", type=Path, help="lib-vt installation prefix")
args = parser.parse_args()
prefix = args.prefix.resolve()
fixtures = Path(__file__).resolve().parent
library = next(path for path in (prefix / "lib").glob("libwitty-vt.*")
               if path.is_file() and not path.name.endswith(".o"))
with tempfile.TemporaryDirectory(prefix="witty-vt-examples-") as temporary:
    for source in sorted(fixtures.glob("*.c")):
        executable = Path(temporary) / source.stem
        subprocess.run(["clang", "-I" + str(prefix / "include"), str(source),
                        str(library), "-Wl,-rpath," + str(prefix / "lib"),
                        "-o", str(executable)], check=True)
        result = subprocess.run([str(executable)], input=b"", capture_output=True, check=True)
        print(source.stem + ": " + result.stdout.decode().strip())
