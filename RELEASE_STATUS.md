# KaGo VPN — release status

**Status: Android release-candidate artifacts built but unsigned; Windows native build and real VPN traffic verification remain release gates.** This is not a signed or store-ready public release.

## Implemented and verified in source

- **Windows Mihomo updater:** downloads the official stable Windows x64 compatible ZIP over HTTPS, verifies the GitHub release digest/size, extracts only the expected executable, probes its version, uses versioned installs, checks at most every 12 hours and falls back to the last-known-good executable.
- **Windows connection mode:** launches the managed Mihomo process, waits for the local External Controller, then enables a reversible per-user system proxy. It restores saved settings on normal disconnect/core exit and recovers a stale KaGo-owned proxy at the next start. This is system-proxy routing, not full Wintun TUN; apps that ignore Windows proxy settings are not covered.
- **Android core:** official Mihomo source pinned to `v1.19.32`; Go/cgo adapter parses config, attaches to a duplicate of the Android `VpnService` TUN descriptor, installs `VpnService.protect()` for outbound sockets, and exports version/error/start/stop functions through JNI. Build scripts target `arm64-v8a` and `x86_64`.
- **Subscription import:** HTTPS URL + clipboard paste; normalizes Clash/Mihomo YAML, base64 YAML and common VLESS/VMess/Trojan/Shadowsocks/Hysteria2/TUIC share links to a selectable Mihomo profile.
- **Dart quality gates:** `flutter analyze` has no issues; all Flutter unit/widget tests pass after the import and system-proxy changes. Go host unit tests pass for the native adapter.
- **Android native compile:** NDK builds of the embedded Mihomo JNI shared object were completed for both declared ABIs in the Sandbox.
- **Android release packaging:** `KaGoVPN-Android-release.aab` (122 MiB) and `KaGoVPN-Android-release.apk` (142 MiB) were built with Flutter 3.47.5; both packages contain native libraries for `arm64-v8a` and `x86_64`. `apksigner verify` confirms the APK is unsigned, as expected without the product-owner key. `flutter analyze` reports no issues and all Flutter tests pass.

## Still required before a public release

1. **Sign Android for installation/distribution.** The built AAB/APK are unsigned and therefore not installable/publishable as production artifacts. No product-owner upload key is present in this workspace. Sign locally with the owner's existing upload key, or generate a new one on the owner's machine and set `KAGO_ANDROID_KEYSTORE`, `KAGO_ANDROID_KEYSTORE_PASSWORD`, `KAGO_ANDROID_KEY_ALIAS`, and `KAGO_ANDROID_KEY_PASSWORD` only in that local environment. Do not use an agent-generated key for a long-lived app identity.
2. **Run Android device tests:** VPN consent/revoke/reconnect, TUN attach, `protect()` callback, protocol traffic, DNS/IPv6, disconnect cleanup, and traffic-leak tests. Linux compilation and Go unit tests do not validate an Android device's VPN behavior.
3. **Run the Windows release build on Windows/MSVC.** This Sandbox is Linux and cannot emit a native Flutter Windows release binary. Run `tool/build_windows_release.ps1` on Windows with Flutter and Visual Studio 2022 Desktop C++ workload. Test system proxy restoration after disconnect, core crash, app exit and reboot. A signing certificate/installer is not included.
4. **Decide whether system-proxy mode satisfies the product.** Current Windows mode only routes programs honoring Windows Internet Settings. Full-device VPN requires additional Wintun integration, privilege/service lifecycle, and route/DNS/leak testing.
5. **Choose the Android app update channel.** Mihomo `.so` is intentionally shipped in the signed APK/AAB. A newer upstream core is surfaced in Settings and must be bundled into a new app release through Play or another trusted store/update channel; no private store listing or publishing credentials are configured here.
6. **Complete compliance and product setup:** Mihomo is GPL-3.0; review redistribution and corresponding-source notices against the app licensing model, and prepare privacy policy, terms, support URL, Play listing, release keystore backup and Windows signing certificate.
7. **Protocol and integration coverage:** the importer currently supports Clash/Mihomo YAML, base64 YAML and VLESS/VMess/Trojan/SS/Hysteria2/TUIC URI schemes. SSR and proprietary encrypted provider formats remain unsupported. Add regression tests/real provider samples before public rollout.

## Reproducible build commands

Windows PowerShell (Windows host only):

```powershell
.\tool\build_windows_release.ps1
```

Android PowerShell (Windows host with Android SDK/NDK + Go):

```powershell
.\tool\build_android_release.ps1
```

Android Linux/macOS/WSL:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
./tool/build_android_release.sh
```

A build without local signing variables is unsigned. Do not distribute it as a production release. See [README.md](README.md) and [native/android/README.md](native/android/README.md).
