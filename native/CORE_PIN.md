# Mihomo core pin and release notes

- Embedded Android core target: official Go module `github.com/metacubex/mihomo v1.19.32`.
- Module proxy checksum recorded during resolution: `h1:uD7ZC3P77isWD554NNvtee65L+99+/C5hyc+Lk8rVEk=`.
- The upstream latest stable GitHub release API reported `v1.19.32`, published 2026-09-30. Windows updater and Android app-bundled core use the same semantic version baseline.
- Upstream source: [MetaCubeX/mihomo v1.19.32](https://github.com/MetaCubeX/mihomo/tree/v1.19.32). The Android bridge in this project is KaGo-owned code; the earlier FlClash-specific fork checkout is not part of the intended build.
- Android core updates are delivered with a new signed KaGo VPN APK/AAB, not by downloading a replacement native library at runtime. The app can check the upstream core version and direct the user to the app update path.
- Before distributing Android binaries, include the upstream license and corresponding-source notices required by the pinned Mihomo release and all other bundled dependencies. Confirm license compatibility for the intended product distribution model.
