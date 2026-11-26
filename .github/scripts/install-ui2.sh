#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
revision=f18e784d96a27991974ef8cfdd25b33830a9f067
patch="$root/.github/patches/ui2-window-hooks.patch"
modules="${1:-$root/.witty-build/ui2-modules}"
destination="$modules/ui2"
receipt="$revision $(git hash-object "$patch")"

if [[ -f "$destination/.witty-ui2" && $(cat "$destination/.witty-ui2") == "$receipt" ]]; then
  exit 0
fi

if [[ -e "$destination" && ! -f "$destination/.witty-ui2" ]]; then
  printf 'UI2 cache path already exists: %s\n' "$destination" >&2
  exit 1
fi

mkdir -p "$modules"
temporary=$(mktemp -d "$modules/ui2.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
git init --quiet "$temporary"
git -C "$temporary" fetch --quiet --depth 1 "${WITTY_UI2_SOURCE:-https://github.com/vlang/ui2.git}" "$revision"
git -C "$temporary" checkout --quiet --detach FETCH_HEAD
git -C "$temporary" apply --unidiff-zero "$patch"
printf '%s\n' "$receipt" > "$temporary/.witty-ui2"
if [[ -f "$destination/.witty-ui2" ]]; then
  rm -rf "$destination"
fi
mv "$temporary" "$destination"
