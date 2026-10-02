# KaGo VPN

Flutter/Dart 3 VPN client for [usekago.net](https://usekago.net), using Riverpod and the official Mihomo core. This repository now contains the Android Go/cgo/JNI integration and the Windows-managed-core path; it is a **release candidate scaffold**, not yet a store-certified production release.

## Implemented

- Responsive Dashboard, Proxies, Connections and Settings screens.
- Mihomo External Controller REST client, Riverpod state, secure controller secret storage and live desktop core logs.
- Subscription import over HTTPS, clipboard paste, Clash/Mihomo YAML, base64-encoded YAML, and common `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`/`hy2://`, and `tuic://` node links.
- Windows x64: official Mihomo stable-release updater, GitHub API SHA-256 digest verification, safe ZIP extraction, versioned app-support install, binary version probe, 12-hour check interval and last-known-good fallback.
- Windows connection: Mihomo mixed port plus reversible per-user Windows system proxy. Original proxy settings are backed up and restored on disconnect/core exit. This routes apps that honor Windows proxy settings; it is **not** a full-device Wintun tunnel.
- Android: `VpnService`, system consent, foreground service, TUN descriptor lifecycle, JNI/CGo callback for `VpnService.protect()`, embedded official Mihomo `v1.19.32`, and native libraries for `arm64-v8a` and `x86_64` produced by the Android NDK build script.
- Android core version is compared with the latest upstream release. New Android core versions must be shipped inside a newly signed app through the chosen store/channel; the app deliberately does not download and execute a replacement `.so`.
- KaGo-branded Android and Windows runners/icons; tests cover config generation, subscription parsing, release selection, network policy, and widgets.

## Import a subscription

In Dashboard, choose **Добавить подписку**, paste a subscription URL or use **Вставить из буфера**. External subscription URLs must use HTTPS; HTTP is allowed only for loopback development endpoints. The response must contain a Clash/Mihomo YAML profile, a base64-encoded YAML profile, or a supported URI list. The imported config is normalized, validated and written to the app's support directory. Subscription-specific metadata headers are parsed separately from the config body.

`ssr://`, provider-specific encrypted formats, and arbitrary proprietary subscription responses are not decoded by the current importer; add a compatible provider export or convert to a supported format first.

## Build Android

Prerequisites: Flutter stable, JDK 17+, Go (use the version supported by your Mihomo module), Android SDK/NDK, and accepted Android SDK licenses.

On Linux/macOS/WSL:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
./tool/build_android_release.sh
```

On Windows PowerShell:

```powershell
.\tool\build_android_release.ps1
```

The release Gradle configuration reads a private upload key only from environment variables: `KAGO_ANDROID_KEYSTORE`, `KAGO_ANDROID_KEYSTORE_PASSWORD`, `KAGO_ANDROID_KEY_ALIAS`, and `KAGO_ANDROID_KEY_PASSWORD`. Without those variables Gradle can emit an **unsigned** build artifact; it is not installable/distributable as a production release. Generate an upload key locally with `tool/create_android_upload_key.ps1`, keep it out of the repository and back it up securely. Do not send the key or passwords in chat.

The release script builds Mihomo pinned at `v1.19.32` for both declared ABIs, runs `flutter analyze` and `flutter test`, builds the AAB/APK, and copies them into `dist/android/`. The Android app only connects after the core has attached to the Android-owned TUN descriptor; startup fails closed if the native library/core fails. It selects the highest installed side-by-side NDK unless `ANDROID_NDK_HOME` is explicitly set.

## Build Windows

Run on Windows with Flutter stable and Visual Studio 2022 **Desktop development with C++** workload:

```powershell
.\tool\build_windows_release.ps1
```

It runs format/analyze/tests, builds `flutter build windows --release`, and creates `dist/KaGoVPN-Windows-x64.zip`. Mihomo downloads on first connection if the optional custom binary path is empty. Public distribution should code-sign the Windows executable/installer; no signing certificate is included.

The Windows runtime currently uses system-proxy mode, not full TUN. Only software that honors Windows Internet Settings is routed. If product requirements demand all-device traffic capture, a Wintun/elevation/service implementation and device-level route/DNS/leak tests remain necessary.

## Android update policy

Android `.so` code remains inside the signed APK/AAB. When a newer stable Mihomo release is detected, Settings shows that a newer KaGo VPN app build is needed. Publish that app through Google Play or another trusted update channel. Remote native-library replacement is intentionally disabled under Android dynamic-code-loading guidance: <https://developer.android.com/privacy-and-security/risks/dynamic-code-loading>.

## Release-critical notes

- Android AAB/APK artifacts and native libraries for `arm64-v8a` and `x86_64` have been built in the Sandbox; both artifacts are unsigned because the product-owner upload key is not present. The Windows release still must be compiled on Windows/MSVC. Neither compilation nor unit tests substitute for Android VPN end-to-end testing on physical devices.
- Android production artifacts need the product owner's private upload key. Windows public distribution needs an appropriate code-signing certificate.
- Mihomo is GPL-3.0. Review the app's licensing/distribution model and provide required corresponding source and notices before public distribution. See `native/CORE_PIN.md` and `native/mihomo/LICENSE`.
- Windows proxy cleanup is automatic on normal disconnect/core exit and recovers a stale KaGo-owned proxy at the next app start; it is not equivalent to a dedicated VPN service surviving crashes/reboots.
- Before public release, run physical-device tests for Android permission/revoke/reconnect, DNS/IPv6, socket protection, traffic routing, cancellation, and leak behavior; test Windows proxy restore after app/core failure.

See [RELEASE_STATUS.md](RELEASE_STATUS.md) for the current verification results and remaining release gates.
