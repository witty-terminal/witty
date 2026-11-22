#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${RELEASE_TAG:-}" ]]; then
  set -- "$@" "-Dversion-string=${RELEASE_TAG#v}" -Doptimize=ReleaseFast -Dstrip=true
fi

v -path "$PWD|@vlib|@vmodules" run tools/build "$@" --prefix "$RUNNER_TEMP/witty"
