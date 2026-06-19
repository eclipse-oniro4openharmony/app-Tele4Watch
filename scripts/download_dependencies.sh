#!/usr/bin/env bash
#
# download_dependencies.sh — first step of the from-clean-clone build chain.
#
# Clones and pins every SOURCE third_party dependency the project needs.
# `/third_party` is gitignored, so a fresh checkout has none of these — this
# script fetches them at known-good commits, idempotently (safe to re-run).
#
# It only downloads sources. Building happens in the next chain steps:
#   1. scripts/download_dependencies.sh        (this — clone all sources)
#   2. scripts/prepare_tgcall_deps_wsl.sh      (WSL: webrtc third_party +
#                                               submodules, tgcalls patch,
#                                               build webrtc + boringssl, both ABI)
#   3. scripts/build_tdlib_ohos.ps1            (Windows: patch + build TDLib, both ABI)
#   4. ohpm install && hvigorw ... assembleHap (build the HAP)
#
# Toolchain tools NOT handled here (see README "Requirements"):
#   - depot_tools : fetched by prepare_tgcall_deps_wsl.sh (WebRTC gn/ninja build)
#   - gperf.exe   : Windows host tool for the TDLib build (manual, third_party/tools/gperf/)
#
# Usage:
#   bash scripts/download_dependencies.sh
# Run from WSL/Linux or Git Bash on Windows (needs `git`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TP="$REPO_ROOT/third_party"

# name | path-under-third_party | git url | pinned commit
# Pins mirror the working tree validated for Sprint 5 (calls v2 / protocol 13.0.0)
# and the opusdecoder audio module.
DEPS=(
  "td|td|https://github.com/tdlib/td.git|8ff05a0e7e064fa796593f3105c2dcf983e279d4"
  "boringssl|boringssl|https://github.com/google/boringssl.git|c1c5839717bf8b8532d49accda57887836d71f4b"
  "tgcalls|tgcalls|https://github.com/TelegramMessenger/tgcalls.git|8099768559edb0efd2d1b300090c18141226e9a8"
  "ohos_webrtc|ohos_webrtc|https://gitcode.com/openharmony-sig/ohos_webrtc.git|3c9c9059d045261a5701cbe6c14301628aaa1561"
  "ogg|ogg|https://github.com/xiph/ogg.git|06a5e0262cdc28aa4ae6797627a783b5010440f0"
  "opus|opus|https://github.com/xiph/opus.git|788cc89ce4f2c42025d8c70ec1b4457dc89cd50f"
  "opusfile|opusfile|https://github.com/xiph/opusfile.git|6dfd29e7adb87f2e193575fc3fa88cbf1a0b27df"
)

clone_or_checkout() {
  local name="$1" path="$2" url="$3" commit="$4"

  if [[ -d "$path/.git" ]]; then
    local cur
    cur="$(git -C "$path" rev-parse HEAD 2>/dev/null || echo none)"
    if [[ "$cur" == "$commit" ]]; then
      echo "  [skip]     $name already at ${commit:0:10}"
      return 0
    fi
    echo "  [checkout] $name -> ${commit:0:10}"
    git -C "$path" fetch --tags origin
    git -C "$path" checkout --quiet "$commit"
  else
    echo "  [clone]    $name <- $url"
    mkdir -p "$(dirname "$path")"
    git clone "$url" "$path"
    git -C "$path" fetch --tags origin
    git -C "$path" checkout --quiet "$commit"
  fi
}

echo "Downloading third_party source dependencies into: $TP"
echo "(ohos_webrtc is large — the first clone can take a while.)"
echo

for entry in "${DEPS[@]}"; do
  IFS='|' read -r name sub url commit <<<"$entry"
  clone_or_checkout "$name" "$TP/$sub" "$url" "$commit"
done

echo
echo "All source dependencies are present and pinned. Next steps:"
echo "  2. WSL/Linux:  bash scripts/prepare_tgcall_deps_wsl.sh --sdk-native <linux-OHOS-native-sdk>"
echo "  3. Windows:    powershell -ExecutionPolicy Bypass -File scripts/build_tdlib_ohos.ps1 -Arch x86_64"
echo "                 powershell -ExecutionPolicy Bypass -File scripts/build_tdlib_ohos.ps1 -Arch arm64-v8a"
echo "  4. App:        ohpm install && hvigorw --mode project assembleApp -p product=default -p buildMode=debug"
echo
echo "Reminder: gperf.exe (Windows TDLib host tool) goes to third_party/tools/gperf/gperf.exe (manual)."
