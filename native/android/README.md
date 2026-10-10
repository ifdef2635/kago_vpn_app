# Встроенный мост Mihomo для Android

Android-сборка использует официальный Go-модуль Mihomo, закреплённый на `v1.19.32` (та же стабильная версия, что и у обновления ядра на Windows). Модуль скачивается при сборке как обычная зависимость (`proxy.golang.org`), версию закрепляют `go.mod` и контрольная сумма в `go.sum` (она же — в `native/CORE_PIN.md`); копии исходников ядра в репозитории нет. Обновление ядра: `go get github.com/metacubex/mihomo@vX.Y.Z && go mod tidy` в `native/android`, затем `MIHOMO_VERSION` в `tool/build_android_native.sh`, версия ядра Windows/macOS и `native/CORE_PIN.md`.

## Как это работает

`KaGoVpnService` получает согласие пользователя через `VpnService.prepare()`, создаёт TUN через `VpnService.Builder` и передаёт дескриптор в `libkago_mihomo_bridge.so`. Go-адаптер (`core.go`):

- дублирует дескриптор до возврата успеха и записывает его в поле Mihomo `file-descriptor`, маршрутизацию оставляет Android (`auto-route: false`);
- задаёт абсолютные пути рабочей папки и конфига (`SetHomeDir`, `SetConfig`) — иначе Mihomo пишет `config.yaml` в корень `/`, доступный только для чтения;
- ставит хук сокетов Mihomo, который вызывает `VpnService.protect(int)` до открытия исходящих соединений;
- отключает все локальные порты (`port`, `socks-port`, `mixed-port` и др.) и входящие серверы (`tuic-server`, `ss-config`, `vmess-config`), контроллер — только на loopback;
- для DNS-серверов `system` использует `1.1.1.1` и `8.8.8.8` (в режиме `cmfa` Mihomo не знает DNS Android);
- если TUN не подключился, возвращает ошибку с причиной из лога ядра; запуск «fail-closed» — маршруты VPN не остаются активными.

Ядро собирается с тегом **`cmfa`** — режим Mihomo для встраивания в Android-приложения. Без него при создании TUN Mihomo читает `/data/system/packages.list`, недоступный обычному приложению.

C++ JNI-прослойка (`kago_mihomo_jni_android.cpp`) компилируется в тот же shared object, что и CGo-экспорты. APK/AAB должен содержать `libkago_mihomo_bridge.so` для каждого ABI в `android/app/src/main/jniLibs/<abi>/`.

## Сборка ядра

Linux/macOS/WSL с Go, Flutter и Android SDK/NDK:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
# Без ANDROID_NDK_HOME берётся самая новая установленная NDK;
# либо укажите версию NDK, которую требует Flutter Gradle plugin.
./tool/build_android_native.sh
```

Скрипт запускает тесты адаптера на хосте, затем кросс-компилирует пакет `android && cgo` и JNI-прослойку для `arm64-v8a` и `x86_64` (`-tags cmfa -trimpath`) и кладёт `libkago_mihomo_bridge.so` и `libc++_shared.so` из NDK в `jniLibs/<abi>/`. На Windows то же делает `tool/build_android_native.ps1`. После этого нужна сборка APK/AAB, чтобы Gradle упаковал библиотеки. В GitHub Actions ядро пересобирается автоматически при каждой сборке APK.

Компиляция не доказывает работу VPN на устройстве: согласие и отзыв, подключение TUN, защиту сокетов, DNS/IPv6, маршрутизацию и очистку при отключении нужно проверять на реальном телефоне.

## Обновления и лицензия

Новое ядро поставляется только с новой подписанной версией KaGo VPN (APK/AAB) через выбранный магазин или канал обновлений; приложение не скачивает и не загружает замену нативной библиотеки во время работы.

Mihomo распространяется под GPL-3.0. Вместе с Android-релизом храните его `LICENSE`, эти исходники, уведомления об исходном коде и лицензии Go-зависимостей. Совместимость с лицензией KaGo VPN нужно проверить до публичного распространения, особенно если приложение остаётся закрытым.

Для релизного APK/AAB используйте `tool/build_android_release.ps1` (Windows) или `tool/build_android_release.sh` (Linux/macOS/WSL). Переменные подписи задаются только локально или в секретах CI; ключи и пароли не попадают в репозиторий.
