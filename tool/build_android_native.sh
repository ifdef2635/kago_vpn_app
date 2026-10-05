#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$PROJECT_ROOT/native/android"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
NDK_ROOT="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"

if [[ -z "$NDK_ROOT" && -n "$SDK_ROOT" && -d "$SDK_ROOT/ndk" ]]; then
  NDK_ROOT="$(find "$SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
fi
if [[ -z "$NDK_ROOT" || ! -d "$NDK_ROOT/toolchains/llvm/prebuilt" ]]; then
  echo "Android NDK not found. Set ANDROID_NDK_HOME, or install NDK side-by-side in ANDROID_SDK_ROOT/ndk." >&2
  exit 2
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) HOST_TAG=linux-x86_64 ;;
  Darwin-x86_64) HOST_TAG=darwin-x86_64 ;;
  Darwin-arm64) HOST_TAG=darwin-arm64 ;;
  *) echo "Unsupported NDK host: $(uname -s)-$(uname -m)" >&2; exit 2 ;;
esac
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG"
if [[ ! -d "$TOOLCHAIN/bin" ]]; then
  echo "NDK toolchain not found: $TOOLCHAIN" >&2
  exit 2
fi

MIHOMO_VERSION="v1.19.32"
TEMP_DIR="$CORE_DIR/build/android-native"
mkdir -p "$TEMP_DIR"
cd "$CORE_DIR"
go test ./...

build_abi() {
  local abi="$1" goarch="$2" triple="$3"
  local cc="$TOOLCHAIN/bin/${triple}21-clang"
  local cxx="$TOOLCHAIN/bin/${triple}21-clang++"
  local cxx_shared="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/sysroot/usr/lib/$triple/libc++_shared.so"
  local output="$TEMP_DIR/$abi/libkago_mihomo_bridge.so"
  local temp_output="$TEMP_DIR/$abi.tmp/libkago_mihomo_bridge.so"
  
  if [[ ! -x "$cc" || ! -x "$cxx" ]]; then
    echo "NDK compiler missing for $abi: $cc / $cxx" >&2
    exit 2
  fi
  if [[ ! -f "$cxx_shared" ]]; then
    echo "NDK libc++_shared.so missing for $abi: $cxx_shared" >&2
    exit 2
  fi
  mkdir -p "$(dirname "$temp_output")"
  echo "Building Mihomo $MIHOMO_VERSION for Android $abi..."
  CGO_ENABLED=1 GOOS=android GOARCH="$goarch" CC="$cc" CXX="$cxx" \
    CGO_LDFLAGS="-llog -landroid -lc++_shared" \
    go build -mod=readonly -buildmode=c-shared -tags cmfa \
      -ldflags "-X github.com/metacubex/mihomo/constant.Version=${MIHOMO_VERSION#v} -s -w" \
      -o "$temp_output" .
  mkdir -p "$TEMP_DIR/$abi"
  mv "$temp_output" "$output"
  cp "$cxx_shared" "$TEMP_DIR/$abi/libc++_shared.so"
  rm -rf "$TEMP_DIR/$abi.tmp"
  mkdir -p "$PROJECT_ROOT/android/app/src/main/jniLibs/$abi"
  cp "$output" "$PROJECT_ROOT/android/app/src/main/jniLibs/$abi/libkago_mihomo_bridge.so"
  cp "$cxx_shared" "$PROJECT_ROOT/android/app/src/main/jniLibs/$abi/libc++_shared.so"
}

build_abi arm64-v8a arm64 aarch64-linux-android
build_abi x86_64 amd64 x86_64-linux-android

echo "Android Mihomo JNI libraries installed under android/app/src/main/jniLibs/."
