#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
command -v "$FLUTTER_BIN" >/dev/null 2>&1 || { echo "Flutter executable not found: $FLUTTER_BIN" >&2; exit 2; }
cd "$PROJECT_ROOT"

./tool/build_android_native.sh
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test

if [[ -n "${KAGO_ANDROID_KEYSTORE:-}" && -n "${KAGO_ANDROID_KEYSTORE_PASSWORD:-}" && -n "${KAGO_ANDROID_KEY_ALIAS:-}" && -n "${KAGO_ANDROID_KEY_PASSWORD:-}" ]]; then
  echo 'Building Android App Bundle and APK with the provided local upload key.'
else
  echo 'WARNING: no local upload key configured; release outputs will be unsigned and are not distributable.' >&2
fi
"$FLUTTER_BIN" build appbundle --release
"$FLUTTER_BIN" build apk --release --target-platform android-arm64,android-x64
mkdir -p dist/android
cp build/app/outputs/bundle/release/app-release.aab dist/android/KaGoVPN-Android-release.aab
cp build/app/outputs/flutter-apk/app-release.apk dist/android/KaGoVPN-Android-release.apk
printf 'Android release artifacts: %s/dist\n' "$PROJECT_ROOT"
