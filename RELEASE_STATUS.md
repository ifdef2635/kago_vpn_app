# KaGo VPN — release status

**Status: Android release-candidate artifacts built but unsigned; Windows native build and real VPN traffic verification remain release gates.** This is not a signed or store-ready public release.

_Last updated: 2026-10-03 (third change set)._ This file is updated with every change set; the newest changes are listed under "Implemented in source, not yet verified"._

## Implemented and verified in source

- **Windows Mihomo updater (baseline, verified earlier; extended by the unverified changes below):** downloads the official stable Windows x64 compatible ZIP over HTTPS, verifies the GitHub release digest/size, extracts only the expected executable, probes its version, uses versioned installs, checks at most every 12 hours and falls back to the last-known-good executable.
- **Windows connection mode:** launches the managed Mihomo process, waits for the local External Controller, then enables a reversible per-user system proxy. It restores saved settings on normal disconnect/core exit and recovers a stale KaGo-owned proxy at the next start. This is system-proxy routing, not full Wintun TUN; apps that ignore Windows proxy settings are not covered.
- **Android core:** official Mihomo source pinned to `v1.19.32`; Go/cgo adapter parses config, attaches to a duplicate of the Android `VpnService` TUN descriptor, installs `VpnService.protect()` for outbound sockets, and exports version/error/start/stop functions through JNI. Build scripts target `arm64-v8a` and `x86_64`.
- **Subscription import:** HTTPS URL + clipboard paste; normalizes Clash/Mihomo YAML, base64 YAML and common VLESS/VMess/Trojan/Shadowsocks/Hysteria2/TUIC share links to a selectable Mihomo profile.
- **Dart quality gates:** `flutter analyze` has no issues; all Flutter unit/widget tests pass after the import and system-proxy changes. Go host unit tests pass for the native adapter.
- **Android native compile:** NDK builds of the embedded Mihomo JNI shared object were completed for both declared ABIs in the Sandbox.
- **Android release packaging:** `KaGoVPN-Android-release.aab` (122 MiB) and `KaGoVPN-Android-release.apk` (142 MiB) were built with Flutter 3.47.5; both packages contain native libraries for `arm64-v8a` and `x86_64`. `apksigner verify` confirms the APK is unsigned, as expected without the product-owner key. `flutter analyze` reports no issues and all Flutter tests pass.

## Implemented in source, not yet verified

These changes were written after the last full `flutter analyze` / `flutter test` run. The authoring sandbox has no Flutter SDK, so **none of them has been analyzed, unit-tested or run**; the patch was only checked to apply cleanly to the source archive. Run `flutter analyze` and `flutter test` first (new tests: `mihomo_core_updater_test`, `proxy_groups_test`, `connections_snapshot_test`, `ip_info_test`, `subscription_usage_test`, plus additions to the parser and widget tests), then test on a real Windows machine and an Android device.

### 2026-10-03 — core-off states (third change set)

- **Servers tab with the core off:** shows the servers and groups of the saved profile (read from the active config; protocol per server, nested groups, `include-all`/`filter` groups) instead of a controller error. Which node is selected is unknown without the core, so none is highlighted; choosing a node and the latency test are disabled until connected, and the tab says so. The list switches to live controller data when the VPN turns on.
- **Connections tab with the core off:** shows "no active connections" instead of an error and does not poll.
- **Blue KAGO palette:** the UI moved from green to the colors of the KAGO logo (blue `#1A4780` and white). The exact logo blue is used for filled buttons, the connect button and the "K" brand mark; icons, selected states and indicators use a lighter tint of the same hue, because the logo blue itself is too dark to read on the dark surfaces. A unit test checks WCAG AA contrast (4.5:1) for all text/icon colors on all surfaces. **Not changed yet:** the Windows `app_icon.ico`, the Android launcher icons and any splash/notification colors still use the old artwork.
- **Build fix:** the owner's first `flutter run -d windows` of this series failed with one compile error (`connections_screen.dart`: a `const` card containing a runtime value). Fixed; a scan of the other changed files found no further `const` problems. `flutter analyze` and `flutter test` are still not run.
- **Dashboard "Ваш сервер" card with the core off:** shows the group name and server count instead of an error.

### 2026-10-03 — audit fixes (second change set)

Read-only audit of the Windows system proxy, process lifecycle, config generation and the core updater. Android `VpnService`/Go adapter and the share-link parsers were **not** re-audited in this pass. Fixed:

- **UI stayed "connected" after the core crashed.** The proxy was already restored, so traffic went direct while the app showed protection. The process manager now emits unexpected exits and the UI switches to disconnected (`MihomoProcessManager.exits`).
- **Closing the desktop window could leave `mihomo.exe` running** with the system proxy still set. The app now stops the core on exit (6 s limit). A core orphaned by a hard crash/kill is **not** yet detected at the next start (no stored PID): it can keep ports 7890/9090 busy and answer the controller with the old config. Open item below.
- **Hostile subscription YAML could expose the proxy to the LAN.** The generated config now forces `allow-lan: false`, `bind-address: 127.0.0.1` and removes `listeners`, `tunnels`, `authentication`, `external-ui*`, `external-controller-tls/unix/pipe/cors`, `tls`; the same lock is re-applied at core start on desktop and Android.
- **Update button reported plain success when GitHub was unreachable** and a core was already installed. It now says the update check failed and why.

### 2026-10-03

- **IP status (dashboard):** new card showing the public IP, country/city and provider, with hide/show and refresh. Lookup order: `ipwho.is` → `api.ip.sb` → `api.ipify.org`. While the Windows/desktop core runs, the request goes through the local proxy (`127.0.0.1:7890`) so the VPN address is shown, not the real one; on Android the VPN already covers the app. Re-checked on VPN on/off, after switching the node and every 3 minutes. These third-party services see the request: **disclose in the privacy policy**.
- **Subscription usage auto-refresh:** used/total traffic and expiry are re-read from the `subscription-userinfo` header (HEAD, then GET) at start, on VPN on/off, every minute while connected and every 5 minutes otherwise. Only the counters are stored; the saved profile config is not rewritten. Previously the numbers changed only on re-import. The panel itself may lag behind real usage.
- **Settings redesign (FlClashX style):** grouped cards with icon rows (appearance, connection, core, diagnostics, about). Controller address and the Linux/macOS core path are edited in dialogs. Logs are available in a dialog at any time (also after a failed start) and can be copied.
- **Windows core: SHA-256 verification extended.** The fallback download now reads the asset digest from the release page on github.com (best effort; the parser is tested only on hand-written samples, not on the live page). `MihomoPinnedCore.sha256Hex` can hold a compiled-in digest. The SHA-256 of the installed `mihomo.exe` is recorded and re-checked before use; a modified or corrupted file is re-downloaded. Installs from older builds are recorded on first use.
- **Windows core: old versions are cleaned up.** After each check/install only the active version folder is kept; stale `.staging-*` folders are removed. A folder in use cannot be deleted on Windows and is retried on the next run.
- **Display refresh rate / smoothness:** Android requests the highest refresh rate at the current resolution; Windows follows the monitor (Flutter default). Tab switches fade in, selection changes animate, the dashboard no longer rebuilds every second and the connections poll runs only while its tab is visible. Settings shows the detected refresh rate.

### Earlier in this change series

- **Windows core location and fallback:** the core is installed to `%APPDATA%\KaGo\core\<version>\mihomo.exe` (created on demand) and fetched automatically at app start. If `api.github.com` is unreachable and no core is installed, the pinned `v1.19.32` `mihomo-windows-amd64-compatible` ZIP is downloaded directly from `github.com`. The manual core path was removed from Windows settings (a path saved by older builds is dropped); it remains only on Linux/macOS.
- **Clear errors instead of raw `DioException`:** `MihomoCoreNetworkException` explains that GitHub is unreachable and no core is installed; missing-binary errors name their cause; a failed start now includes the last core log lines; the dashboard no longer shows a stale "controller unavailable" after the core starts.
- **Servers tab (FlClashX style):** group tabs in config order (GLOBAL last), node cards with protocol and latency, group-wide delay test, sorting; the dashboard "Ваш сервер" card opens this tab and prefers the main group over GLOBAL.
- **Share-link names** are percent-decoded (flags, Cyrillic). Subscriptions imported earlier keep the encoded names until re-imported.
- **Live traffic:** upload/download speed and totals on the dashboard from `/connections`; the connections list refreshes automatically.
- **Controller secret** is generated automatically and stored in secure storage; the Secret field was removed. A custom secret for a remote controller can no longer be entered.

## Still required before a public release

00. **Orphaned core detection (Windows):** store the core PID at start and, at the next start, stop a leftover `mihomo.exe` from a crashed session (verify the image name first). Also redact subscription URLs/tokens from core logs before the "copy logs" action.

0. **Verify the unverified changes above:** run `flutter analyze` and `flutter test`; on Windows check core auto-install into `%APPDATA%\KaGo\core` (also with `api.github.com` blocked), old-version cleanup, the IP card showing the VPN address while connected, usage refresh and the settings screens; on Android check the 90/120 Hz request and that the IP card shows the VPN address.

1. **Sign Android for installation/distribution.** The built AAB/APK are unsigned and therefore not installable/publishable as production artifacts. No product-owner upload key is present in this workspace. Sign locally with the owner's existing upload key, or generate a new one on the owner's machine and set `KAGO_ANDROID_KEYSTORE`, `KAGO_ANDROID_KEYSTORE_PASSWORD`, `KAGO_ANDROID_KEY_ALIAS`, and `KAGO_ANDROID_KEY_PASSWORD` only in that local environment. Do not use an agent-generated key for a long-lived app identity.
2. **Run Android device tests:** VPN consent/revoke/reconnect, TUN attach, `protect()` callback, protocol traffic, DNS/IPv6, disconnect cleanup, and traffic-leak tests. Linux compilation and Go unit tests do not validate an Android device's VPN behavior.
3. **Run the Windows release build on Windows/MSVC.** This Sandbox is Linux and cannot emit a native Flutter Windows release binary. Run `tool/build_windows_release.ps1` on Windows with Flutter and Visual Studio 2022 Desktop C++ workload. Test system proxy restoration after disconnect, core crash, app exit and reboot. A signing certificate/installer is not included.
4. **Decide whether system-proxy mode satisfies the product.** Current Windows mode only routes programs honoring Windows Internet Settings. Full-device VPN requires additional Wintun integration, privilege/service lifecycle, and route/DNS/leak testing.
5. **Choose the Android app update channel.** Mihomo `.so` is intentionally shipped in the signed APK/AAB. A newer upstream core is surfaced in Settings and must be bundled into a new app release through Play or another trusted store/update channel; no private store listing or publishing credentials are configured here.
6. **Complete compliance and product setup:** Mihomo is GPL-3.0; review redistribution and corresponding-source notices against the app licensing model, and prepare privacy policy (including the public-IP lookups and subscription polling above), terms, support URL, Play listing, release keystore backup and Windows signing certificate.
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
