# Android embedded Mihomo bridge

The Android build uses the official Mihomo Go module pinned to `v1.19.32` (the same stable version discovered by the Windows updater). `go.mod` replaces the module with the pinned source under `native/mihomo`; the source pin and module-proxy checksum are recorded in `native/CORE_PIN.md`.

`KaGoVpnService` obtains Android's consent through `VpnService.prepare()`, establishes the TUN with `VpnService.Builder`, and passes the descriptor to `libkago_mihomo_bridge.so`. The Go adapter duplicates the file descriptor before returning success, sets the Mihomo `file-descriptor` field, and leaves routing to Android (`auto-route: false`). It installs Mihomo's socket hook to call `VpnService.protect(int)` before outbound sockets are opened. A failed TUN attach is fail-closed and must not leave the Android VPN routes active.

The C++ JNI shim is compiled into the same shared object as the CGo exports. The APK/AAB must contain `libkago_mihomo_bridge.so` for every shipped ABI under `android/app/src/main/jniLibs/<abi>/`. Core updates are delivered only with a newly signed KaGo VPN APK/AAB; the app must not download and load a replacement native library at runtime. `tool/build_android_release.ps1` is the supported Windows build entry point.

The embedded Mihomo release carries GPL-3.0 licensing. Keep its `LICENSE`, this source tree, corresponding-source notices, and licenses for bundled Go dependencies with the Android release. The intended distribution license for KaGo VPN must be reviewed for compatibility before public distribution, especially if the app is intended to remain closed-source.


## Reproducible Android core build

From Linux/macOS/WSL with Go, Flutter and Android SDK/NDK installed:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
# Leave ANDROID_NDK_HOME unset to select the highest installed side-by-side NDK,
# or set it to the NDK version required by the Flutter Gradle plugin.
./tool/build_android_native.sh
```

The script runs host-side parser tests, then cross-compiles the `android && cgo` Go package and JNI C++ shim for `arm64-v8a` and `x86_64`. It places both `libkago_mihomo_bridge.so` and the matching NDK `libc++_shared.so` in each `jniLibs/<abi>/` directory. `tool/build_android_native.ps1` is the Windows/PowerShell equivalent. The Android app bundle build must follow so Gradle packages those ABI libraries.

This source build was compiled in the Sandbox against the pinned Mihomo release for both Android ABIs and the shared libraries export the Kotlin JNI entry points. A native compile does not prove device-level VPN operation: physical-device checks are still required for consent/revoke lifecycle, TUN attach, protected sockets, DNS/IPv6 behavior, data routing, and disconnect/leak cleanup.

For a release APK/AAB, run `tool/build_android_release.ps1` on Windows or `tool/build_android_release.sh` on Linux/macOS/WSL. Production signing variables must be supplied locally; private keystores/passwords are never included in the repository or archive. Android core updates are packaged with the signed app through a configured app store/channel, not fetched as a replacement native library.
