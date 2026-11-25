#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 WITTY_BINARY OUTPUT_DIRECTORY" >&2
  exit 2
fi

case "$(dpkg --print-architecture)" in
  amd64)
    asset=ghostty_1.4.0-0.ppa2_amd64_26.04.deb
    digest=2d70bf419494362dffb6463d8ff3ab76c3fd1b0e247ea9b0b0aeda5c2fa4c681
    ;;
  arm64)
    asset=ghostty_1.4.0-0.ppa2_arm64_26.04.deb
    digest=17c15d4ab6b0d46a84d333609038d1aca59d60a6196027e165f8f66764979922
    ;;
  *)
    echo "The Ubuntu 26.04 Ghostty reference is available for amd64 and arm64." >&2
    exit 2
    ;;
esac

reference_dir=$(mktemp -d)
trap 'rm -rf "$reference_dir"' EXIT
curl --fail --silent --show-error --location --retry 3 \
  --output "$reference_dir/$asset" \
  "https://github.com/mkasberg/ghostty-ubuntu/releases/download/1.4.0-0-ppa2/$asset"
printf '%s  %s\n' "$digest" "$reference_dir/$asset" | sha256sum --check
dpkg-deb --extract "$reference_dir/$asset" "$reference_dir/root"

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
xvfb-run -a -s "-screen 0 1440x900x24" dbus-run-session -- \
  python3 "$root/build_support/reference_probes/render_parity/run.py" \
  "$1" "$reference_dir/root/usr/bin/ghostty" --output "$2"
