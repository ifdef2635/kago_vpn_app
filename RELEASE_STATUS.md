# KaGo VPN — release status

**Status: Android release-candidate artifacts built but unsigned; Windows native build and real VPN traffic verification remain release gates.** This is not a signed or store-ready public release.

_Last updated: 2026-10-05 (localization)._ This file is updated with every change set; the newest changes are listed under "Implemented in source, not yet verified"._

## 2026-10-05 — многоязычность: русский и английский (версия 0.1.0+1)

Сделано:
- Весь интерфейс, сообщения об ошибках и логи ядра переводятся через `tr()` (`lib/core/l10n`). Ключ — русский текст, английский перевод — `strings_en.dart` (370 строк); строки с подстановками используют `{имя}`.
- Выбор языка в «Настройки → Внешний вид»: Авто / Русский / English, сохраняется. «Авто» берёт язык системы; для украинского, белорусского, казахского, киргизского и узбекского — русский, для остальных — английский.
- Системные элементы Flutter (диалоги, страница лицензий) локализуются через `flutter_localizations`. Даты — «15 ноября 2099 г.» / «November 15, 2099».
- Android: уведомления VPN-сервиса и ошибки запуска вынесены в ресурсы (`values` — английский, `values-ru` — русский); язык следует системе.
- Тест `l10n_test`: у каждой строки интерфейса есть английский перевод с теми же подстановками.

Осталось:
- Ошибки, которые возвращает сервер usekago.net, приходят на русском и не переводятся.
- Kotlin-часть в этой среде не компилировалась (нет Android SDK) — проверяется сборкой в CI.

## 2026-10-05 — полноценный личный кабинет (версия 0.1.0+1)

Сделано (по исходникам сайта и его `openapi.json`, API Remnashop `https://usekago.net/api/v1/public`):
- **Вход и регистрация** по email и паролю; сессия — httpOnly-cookie сайта, хранится в защищённом хранилище; при 401 один раз вызывается `/auth/refresh` (как на сайте), при неудаче — выход. «Забыли пароль?» повторяет подсказки сайта.
- **Подписка из аккаунта**: тариф, статус, «Активна до», пробный период, «Осталось» (∞ для 2099), «Устройств N / M», трафик с полосой лимита, предупреждение за 7 дней до конца.
- **«Подключить это устройство»**: ссылка подписки из аккаунта импортируется в приложение и VPN запускается; после входа на новом устройстве подписка добавляется автоматически.
- **Перевыпуск ключа** с подтверждением; если устройство использовало старую ссылку, новая импортируется сама.
- **Устройства**: список, отключение одного и всех. **Промокод**. **Аккаунт**: статус email/Telegram, смена пароля, смена email с кодом, подтверждение email. **Реферальная программа**: счётчики, ссылка `usekago.net/ref/<код>` (после подтверждения почты).
- Неактивная подписка: «Продлить» / «Выбрать тариф» открывают сайт (оплата идёт через платёжные шлюзы сайта).
- Цвета взяты точно из `globals.css` сайта (светлая и тёмная темы); где цвет сайта ниже WCAG AA для текста, он немного затемнён.
- Тесты клиента API на поддельном сервере: cookie, обновление сессии, выход при мёртвой сессии, ошибки FastAPI.

Осталось:
- Вход через Telegram (OIDC-виджет Telegram работает только в браузере) — в приложении нет; нужен вход по email/паролю.
- Оплата/продление внутри приложения — открывается сайт.
- Работа с реальным сервером не проверена из среды сборки (usekago.net недоступен): проверить вход на устройстве. Если сервер отвергает запросы не из браузера (проверка Origin/CSRF), понадобится правка на стороне бэкенда.

## 2026-10-05 — оформление usekago.net и личный кабинет (версия 0.1.0+1)

Сделано:
- **Палитра сайта usekago.net** (`KaGoPalette`, `ThemeExtension`): светлая тема — фон `#EEF2F9`, белые карточки с тонкой рамкой и мягкой тенью, кнопки/ссылки `#2D5BD0`, тёмно-синяя карточка подписки с бирюзовым свечением; тёмная тема в тех же оттенках и вариант «чисто чёрный». Цвета взяты со скриншотов сайта (сам сайт из среды сборки недоступен), возможны небольшие расхождения оттенков.
- **Переключатель темы** «Авто / Светлая / Тёмная» в настройках, выбор и OLED-режим сохраняются между запусками (раньше «чёрный фон» сбрасывался).
- **Вкладка «Кабинет»** по образцу usekago.net/my: «Здравствуйте!», карточка подписки (статус Активна/Подключено/Истекла, срок «Активна до 15 ноября 2099 г.», плитки «Осталось» (∞ для бессрочных), «Использовано», «Трафик»/«Безлимит»), кнопки «Подключиться/Отключиться», «Скопировать ссылку», «Обновить данные», «Перевыпустить ключ». Карточки «Устройства и промокоды» и «Аккаунт» открывают сайт и Telegram-бота @KaGoVPNbot.
- Тест контраста (WCAG AA) переписан на обе палитры; тесты срока и русской даты для кабинета. `flutter analyze` — без замечаний, `flutter test` — 69 тестов. Экраны проверены рендером в тестовом окружении (светлая/тёмная, 390×844).

Осталось:
- **Настоящий вход в аккаунт** (email/пароль, Telegram), список устройств, промокоды, рефералы и перевыпуск ключа внутри приложения требуют API usekago.net — его описания нет. Сейчас эти функции открывают сайт.
- Иконки приложения (Windows `.ico`, Android launcher) по-прежнему старые.

## 2026-10-05 — безопасность и анонимность (версия 0.1.0+1)

Сделано:
- **Android: закрыты локальные прокси-порты.** Весь трафик идёт через TUN, поэтому `mixed-port`/`port`/`socks-port`/`redir-port`/`tproxy-port` отключаются (в Dart-конфиге и повторно в Go-адаптере). Открытый порт на 127.0.0.1 — это прокси без пароля для любого приложения на телефоне: по нему можно обнаружить VPN и узнать адрес выхода.
- **Входящие серверы из подписки запрещены** (Android и Windows): `tuic-server`, `ss-config`, `vmess-config` удаляются из конфига, в Go-адаптере дополнительно выключаются.
- **Android: логи без истории посещений** — уровень `warning` (уровень `info` пишет каждый домен).
- **Kill switch (Android):** в «Настройки → Безопасность» кнопка открывает системные настройки VPN, где включаются «Постоянная VPN» и «Блокировать соединения без VPN». Сам приложение их включить не может (ограничение Android).
- Описание действующей защиты в настройках: DNS только через ядро (DoH, fake-ip), IPv6 мимо туннеля блокируется системой (IPv6-маршрут не задан), обход VPN приложениями не разрешён (`allowBypass` не вызывается).

Проверено: `flutter analyze` — без замечаний; `flutter test` — 62 теста; `go test` и `go vet` (android, cmfa) адаптера проходят. На устройстве не проверено.

Осталось:
- Контроллер Mihomo на Android слушает `127.0.0.1:9090` (с secret). Порт виден другим приложениям; можно перенести на случайный порт.
- Windows: режим системного прокси — приложения, не использующие прокси, и их DNS идут мимо VPN (нужен TUN/Wintun).

## 2026-10-05 — Android: VPN подключён, но трафик не работает (версия 0.1.0+1)

Исправлено:
- **Ядро запускалось, но ничего не открывалось.** Если в подписке нет `dns.enable: true`, встроенный DNS Mihomo выключен. На Android это ломает всё: DNS-запросы из TUN получают SERVFAIL, а сам Mihomo не может разрешить имена серверов прокси (на Android нет `/etc/resolv.conf`). Теперь `prepareAndroidTunnelConfig` включает DNS, если подписка его не включает: `fake-ip` (198.18.0.1/16), DoH `1.1.1.1` / `8.8.8.8`, bootstrap `1.1.1.1`, `8.8.8.8`, IPv6 выкл. DNS, включённый в подписке, не трогается. Так же делают FlClash/CMFA.
- Тесты: `mihomo_config_builder_test` — DNS добавляется и не перезаписывается. `flutter analyze` — без замечаний, `flutter test` — 61 тест проходит.

Осталось:
- Проверить на устройстве: открываются ли сайты, какой IP показывает карточка, вкладка «Трафик» (через какой прокси идут соединения).

## 2026-10-05 — Android: ядро не подключалось к TUN (версия 0.1.0+1)

Исправлено:
- **«Mihomo could not attach to the Android TUN descriptor».** Ядро собиралось без build-тега `cmfa` (режим Mihomo для встраивания в Android-приложения). Без него при создании TUN Mihomo читает список пакетов `/data/system/packages.list`, недоступный обычному приложению, и TUN не создаётся. Скрипты `tool/build_android_native.sh` / `.ps1` теперь собирают с `-tags cmfa`. Тег также отключает поиск процесса по соединению и loopback-детектор и включает embed-режим контроллера (запрещены PUT/PATCH `/configs`, `/rules`, restart/upgrade — приложение их не использует).
- В режиме `cmfa` Mihomo не знает системный DNS Android. DNS-серверы `system` в конфиге теперь идут на `1.1.1.1` и `8.8.8.8` (сокеты защищены `VpnService.protect`, мимо туннеля).
- Если TUN всё же не поднимется, в ошибке теперь будет настоящая причина из лога ядра вместо «see core logs».
- `kago_socket_protector_android.c`: добавлен `#include <stddef.h>` (NULL).

Проверено: `go test` адаптера проходит; `go vet` для `GOOS=android` с тегом `cmfa` проходит (на заглушках заголовков, без NDK). Сборка с NDK — в CI, на устройстве ещё не проверено.

## 2026-10-05 — Android: ядро не запускалось (версия 0.1.0+1)

Исправлено:
- **На Android ядро падало при старте** с ошибкой `initialize Mihomo home: can't create file config.yaml: open config.yaml: read-only file system`. Mihomo искал `config.yaml` по относительному пути в текущей папке процесса (`/`, только чтение). Теперь адаптер (`native/android/core.go`) передаёт абсолютный путь конфига (`SetConfig`) вместе с рабочей папкой.
- Удалён устаревший дубликат `native/android/kago_mihomo_jni.cpp` (старая версия `kago_mihomo_jni_android.cpp` без `lastError`). Он ломал Go-тесты на хосте («C++ source files not allowed») и при сборке под Android давал бы дублирующиеся JNI-символы. Go-тесты адаптера теперь проходят.

Сделано:
- CI запускается и при изменениях в `native/android`, `native/mihomo` и `tool/build_android_native.sh` (раньше коммит только с нативным кодом сборку не запускал).
- CI (`android-release.yml`) теперь пересобирает `libkago_mihomo_bridge.so` из исходников (Go 1.24 + NDK раннера) перед сборкой APK, вместо закоммиченных бинарников.

Осталось:
- Закоммиченные `android/app/src/main/jniLibs/*/libkago_mihomo_bridge.so` ещё старые (с ошибкой): здесь нет NDK. Локальная сборка без `tool/build_android_native.sh` даст APK со старым ядром; APK из CI — с новым.
- Проверить на устройстве: старт ядра, трафик через VPN.

## 2026-10-05 — сборка Android release APK (версия 0.1.0+1)

Сделано:
- Новый workflow `.github/workflows/android-release.yml` (GitHub Actions, Flutter 3.47.5, Java 17): `pub get` → `analyze` → `test` → `flutter build apk --release` (arm64-v8a, x86_64) → проверка подписи (`apksigner`) и наличия `libkago_mihomo_bridge.so` → артефакт `KaGoVPN-Android-<версия>-<release|debugsigned>.apk` + `.sha256`. Запуск: вручную (workflow_dispatch, после попадания файла в `main`), push в `claude/**`, `feat/**`, `fix/**`, тег `v*` (тег дополнительно создаёт GitHub Release).
- Подпись: если заданы секреты `KAGO_ANDROID_KEYSTORE_BASE64`, `KAGO_ANDROID_KEYSTORE_PASSWORD`, `KAGO_ANDROID_KEY_ALIAS`, `KAGO_ANDROID_KEY_PASSWORD` — ключом владельца. Иначе — одноразовым debug-ключом (`KAGO_ANDROID_DEBUG_SIGNING=true` в `android/app/build.gradle.kts`): APK устанавливается для тестов, но **не для публикации**, и следующая такая сборка не встанет поверх как обновление. Локальные сборки без этой переменной не изменились.
- Нативное ядро в CI не пересобирается: используются закоммиченные `jniLibs` (Mihomo v1.19.32).

Исправлено:
- Предупреждение `flutter analyze` (неиспользуемый `dart:async` в `lib/app/root_shell.dart`), из-за которого CI падал бы.
- Проверено в этой сессии (Linux, Flutter 3.47.5): `flutter analyze` — без замечаний; `flutter test` — все 59 тестов проходят. Это закрывает пункт «not analyzed / not tested» для изменений от 2026-10-03.

Осталось:
- Сам APK в этой сессии не собран: сетевая политика окружения блокирует `dl.google.com` (Android SDK). Сборка выполняется в GitHub Actions; результат первого запуска workflow ещё не проверен.
- Добавить секреты ключа подписи в репозиторий для настоящего релиза; тесты на устройстве (см. ниже) по-прежнему нужны.

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
