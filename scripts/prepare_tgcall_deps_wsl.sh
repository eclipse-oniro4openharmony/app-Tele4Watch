#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OHOS_SDK_NATIVE_PATH="${OHOS_SDK_NATIVE_PATH:-/home/pmandes/setup-ohos-sdk/linux/20/native}"
TGCALLS_REPO_URL="${TGCALLS_REPO_URL:-https://github.com/TelegramMessenger/tgcalls.git}"
TGCALLS_COMMIT="${TGCALLS_COMMIT:-8099768559edb0efd2d1b300090c18141226e9a8}"
OHOS_WEBRTC_REPO_URL="${OHOS_WEBRTC_REPO_URL:-https://gitcode.com/openharmony-sig/ohos_webrtc.git}"
OHOS_WEBRTC_COMMIT="${OHOS_WEBRTC_COMMIT:-3c9c9059d045261a5701cbe6c14301628aaa1561}"
BORINGSSL_REPO_URL="${BORINGSSL_REPO_URL:-https://github.com/google/boringssl.git}"
BORINGSSL_COMMIT="${BORINGSSL_COMMIT:-c1c5839717bf8b8532d49accda57887836d71f4b}"
DEPOT_TOOLS_REPO_URL="${DEPOT_TOOLS_REPO_URL:-https://chromium.googlesource.com/chromium/tools/depot_tools.git}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$REPO_ROOT/third_party/depot_tools}"
JOBS="${JOBS:-$(nproc)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdk-native)
      OHOS_SDK_NATIVE_PATH="$2"
      shift 2
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Missing required path: $path" >&2
    exit 1
  fi
}

checkout_repo() {
  local path="$1"
  local url="$2"
  local commit="$3"

  if [[ ! -d "$path/.git" ]]; then
    mkdir -p "$(dirname "$path")"
    git clone "$url" "$path"
  fi

  git -C "$path" fetch --tags origin
  git -C "$path" checkout "$commit"
}

require_path "$OHOS_SDK_NATIVE_PATH"
require_path "$OHOS_SDK_NATIVE_PATH/build/cmake/ohos.toolchain.cmake"
require_path "$OHOS_SDK_NATIVE_PATH/build-tools/cmake/bin/cmake"
require_path "$OHOS_SDK_NATIVE_PATH/build-tools/cmake/bin/ninja"

checkout_repo "$DEPOT_TOOLS_DIR" "$DEPOT_TOOLS_REPO_URL" "main"
export PATH="$DEPOT_TOOLS_DIR:$PATH"
command -v gn >/dev/null
command -v ninja >/dev/null

checkout_repo "$REPO_ROOT/third_party/tgcalls" "$TGCALLS_REPO_URL" "$TGCALLS_COMMIT"
checkout_repo "$REPO_ROOT/third_party/ohos_webrtc" "$OHOS_WEBRTC_REPO_URL" "$OHOS_WEBRTC_COMMIT"
checkout_repo "$REPO_ROOT/third_party/boringssl" "$BORINGSSL_REPO_URL" "$BORINGSSL_COMMIT"

TGCALLS_COMPAT_PATCH="$REPO_ROOT/scripts/patches/tgcalls-ohos-webrtc-compat.patch"
if git -C "$REPO_ROOT/third_party/tgcalls" apply --check "$TGCALLS_COMPAT_PATCH"; then
  git -C "$REPO_ROOT/third_party/tgcalls" apply "$TGCALLS_COMPAT_PATCH"
elif git -C "$REPO_ROOT/third_party/tgcalls" apply --reverse --check "$TGCALLS_COMPAT_PATCH"; then
  echo "tgcalls OHOS compatibility patch already applied."
else
  echo "Failed to apply tgcalls OHOS compatibility patch." >&2
  exit 1
fi

WEBRTC_ROOT="$REPO_ROOT/third_party/ohos_webrtc"
if [[ ! -d "$WEBRTC_ROOT/third_party/abseil-cpp" ]]; then
  tmp_dir="$WEBRTC_ROOT/.webrtc_third_party_tmp"
  rm -rf "$tmp_dir"
  git clone https://gitee.com/zhong-luping/webrtc_third_party.git "$tmp_dir"
  rm -rf "$WEBRTC_ROOT/third_party"
  mv "$tmp_dir/third_party" "$WEBRTC_ROOT/third_party"
  rm -rf "$tmp_dir"
fi

git -C "$WEBRTC_ROOT" submodule update --init --recursive

build_boringssl() {
  local arch="$1"
  local suffix="$2"
  local build_dir="$REPO_ROOT/third_party/build/boringssl-ohos-$suffix"
  local cmake="$OHOS_SDK_NATIVE_PATH/build-tools/cmake/bin/cmake"
  local ohos_ninja="$OHOS_SDK_NATIVE_PATH/build-tools/cmake/bin/ninja"

  "$cmake" -S "$REPO_ROOT/third_party/boringssl" -B "$build_dir" -G Ninja \
    "-DCMAKE_MAKE_PROGRAM=$ohos_ninja" \
    "-DCMAKE_TOOLCHAIN_FILE=$OHOS_SDK_NATIVE_PATH/build/cmake/ohos.toolchain.cmake" \
    "-DOHOS_ARCH=$arch" \
    "-DCMAKE_BUILD_TYPE=Release" \
    "-DBUILD_SHARED_LIBS=OFF" \
    "-DBUILD_TESTING=OFF" \
    "-DCMAKE_C_FLAGS=-Wno-error=unused-command-line-argument" \
    "-DCMAKE_CXX_FLAGS=-Wno-error=unused-command-line-argument"

  "$cmake" --build "$build_dir" --target crypto ssl -j "$JOBS"
}

build_webrtc() {
  local target_cpu="$1"
  local out_dir="$2"
  local args
  args="target_cpu=\"$target_cpu\" target_os=\"ohos\" ohos_sdk_native_root=\"$OHOS_SDK_NATIVE_PATH\" is_clang=true is_debug=false rtc_include_tests=false treat_warnings_as_errors=false use_glib=false"

  (
    cd "$WEBRTC_ROOT"
    gn gen "out/$out_dir" --args="$args"
    ninja -C "out/$out_dir" -j "$JOBS"
  )
}

build_boringssl arm64-v8a arm64
build_boringssl x86_64 x86_64
build_webrtc arm64 ohos_arm64_linux
build_webrtc x64 ohos_x64_linux

echo "tgcall native dependencies are ready."
