#!/usr/bin/env bash
set -euo pipefail

# The 0.5.2 release predates uint and the top-level json2 module. Keep the
# source and its generated C bootstrap pinned together.
v_revision=f60a27d4b072e47dda80a21db0af579106ce0a11
vc_revision=6d0cac84be76dc026af545314418b18a242220f5

case "$RUNNER_OS/$RUNNER_ARCH" in
  macOS/ARM64) tcc_revision=69ba759bc4ec12bff4098828b5464e99bd29954a ;;
  Linux/X64) tcc_revision=60d606e37e6afe1ac5801fd88c55036a56b7caae ;;
  Windows/X64) tcc_revision=c2f1eaf22973877b336b8064271d725aa15a420a ;;
  *) echo "Unsupported V bootstrap platform: $RUNNER_OS/$RUNNER_ARCH" >&2; exit 1 ;;
esac

checkout_revision() {
  local repo=$1 revision=$2 destination=$3
  git init -q "$destination"
  git -C "$destination" fetch --quiet --depth 1 "https://github.com/vlang/$repo.git" "$revision"
  git -C "$destination" checkout --quiet --detach FETCH_HEAD
}

v_root="$RUNNER_TEMP/v"
checkout_revision v "$v_revision" "$v_root"
checkout_revision vc "$vc_revision" "$v_root/vc"
checkout_revision tccbin "$tcc_revision" "$v_root/thirdparty/tcc"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
git -C "$v_root" apply "$script_dir/../patches/v-gg-render-buffers.patch"
git -C "$v_root" apply "$script_dir/../patches/v-gg-grow-text-atlas.patch"
# V emits some callback typedefs after their structs and can drop optional enum typedefs.
git -C "$v_root" apply "$script_dir/../patches/v-c-declarations.patch"
if [[ "$RUNNER_OS" == macOS ]]; then
  git -C "$v_root" apply "$script_dir/../patches/v-sokol-metal-formats.patch"
  git -C "$v_root" apply "$script_dir/../patches/v-sokol-metal-shader-stages.patch"
  git -C "$v_root" apply "$script_dir/../patches/v-sokol-metal-command-buffer.patch"
  git -C "$v_root" apply "$script_dir/../patches/v-sokol-metal-inline-uniforms.patch"
  git -C "$v_root" apply "$script_dir/../patches/v-sokol-macos-view-opacity.patch"
fi
if [[ "$RUNNER_OS" == Linux ]]; then
  git -C "$v_root" apply "$script_dir/../patches/v-sokol-gl-contexts.patch"
fi

unset VEXE
if [[ "$RUNNER_OS" == Windows ]]; then
  (cd "$v_root" && cmd.exe //d //c 'makev.bat -gcc --local')
  v_root=$(cygpath -am "$v_root")
  v_exe="$v_root/v.exe"
else
  make -C "$v_root" local=1 CC=clang VFLAGS='-cc clang'
  v_exe="$v_root/v"
fi

"$v_exe" version
echo "VEXE=$v_exe" >> "$GITHUB_ENV"
echo "$v_root" >> "$GITHUB_PATH"
