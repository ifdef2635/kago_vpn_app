# KaGo VPN

VPN-клиент на Flutter/Dart 3 для [usekago.net](https://usekago.net) со встроенным официальным ядром Mihomo (Clash Meta) и Riverpod. Платформы — Android, Windows x64 и macOS (Apple Silicon и Intel). Текущая версия — **1.0.4**; история изменений и известные ограничения — в [RELEASE_STATUS.md](RELEASE_STATUS.md).

## Возможности

- **Вкладки:** «Главная», «Серверы», «Трафик», «Кабинет», «Настройки»; адаптивная разметка (на широком экране — боковая панель).
- **Личный кабинет usekago.net:** вход и регистрация по email и паролю, подписка (тариф, срок, устройства, трафик), «Подключить это устройство» (ссылка из аккаунта импортируется и VPN запускается), перевыпуск ключа, список устройств с отключением, промокод, смена пароля и email, подтверждение email, реферальная программа. Работает через API сайта (Remnashop, `https://usekago.net/api/v1/public`), сессия — httpOnly-cookie в защищённом хранилище.
- **Оформление как на сайте:** светлая и тёмная темы с цветами из `globals.css` usekago.net, вариант «чисто чёрный» для OLED.
- **Языки:** русский и английский, выбор «Авто / Русский / English» в настройках.
- **Подписка — только через аккаунт KAGO:** после входа в «Кабинете» подписка аккаунта подключается сама, добавить её по ссылке нельзя. Поддерживаются форматы Clash/Mihomo YAML, YAML в base64 и ссылки `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`/`hy2://`, `tuic://`. Имена серверов декодируются из `%`-кодировки, счётчики трафика и срок обновляются сами.
- **Главная** (помещается на экран без прокрутки): подписка, «Ваш сервер» (ведёт на «Серверы»), кнопка подключения, текущий IP, скорость и объём загрузки/отдачи.
- **Серверы и группы** в стиле FlClashX: группы в порядке конфига, протокол и задержка узлов, проверка задержки группы, сортировка.
- **Соединения:** активные сессии ядра с автообновлением, закрытие одного или всех.

### Android

- `VpnService` с системным разрешением, foreground-служба, TUN-дескриптор передаётся ядру; исходящие сокеты ядра защищаются `VpnService.protect()`.
- Встроенный Mihomo `v1.19.32` (тег сборки `cmfa`); APK только для `arm64-v8a` (~30 МБ). Нативные библиотеки в APK сжаты, другие архитектуры исключены (`packaging.jniLibs` в `android/app/build.gradle.kts`).
- **Плитка в шторке** «KaGo VPN», как во FlClashX: включение и выключение VPN без открытия приложения (после первого подключения из приложения).
- **Маршрутизация по приложениям из подписки:** правила `PROCESS-NAME` (например, российские приложения → DIRECT) работают. Ядро узнаёт приложение соединения через `ConnectivityManager.getConnectionOwnerUid` (Android 10+). Ручной список «Приложения без VPN» нужен только для исключений.
- **Защита:** DNS только через ядро (DoH, fake-ip), IPv6 мимо туннеля блокируется системой, локальные прокси-порты закрыты (другие приложения не могут обнаружить VPN через 127.0.0.1), подписка не может открыть входящие серверы, логи ядра без истории сайтов. Kill switch — через системные «Постоянная VPN» и «Блокировать соединения без VPN» (кнопка в «Настройки → Подключение»).
- Новое ядро поставляется только вместе с новой подписанной версией приложения; подмена `.so` по сети отключена.

### Windows x64

- Ядро скачивается и обновляется автоматически (сборка compatible, ZIP, `v1.19.32`) в `%APPDATA%\KaGo\core`, с проверкой SHA-256; при недоступном `api.github.com` — запасная загрузка с `github.com`.
- «Российские сайты — напрямую» (Настройки → Подключение): `.ru`/`.рф`, Яндекс, VK, банки и Госуслуги добавляются в исключения системного прокси и открываются без VPN.
- Подключение через обратимый системный прокси Windows (`127.0.0.1:7890`). Это **не** полноценный TUN: приложения, которые не используют системный прокси, идут мимо VPN.

## Сборка Android

### В GitHub Actions (рекомендуется)

Workflow `.github/workflows/android-release.yml` запускается при push в ветки `claude/**`, `feat/**`, `fix/**` и по тегу `v*`. Он собирает ядро из исходников (Go + NDK), выполняет `flutter analyze` и `flutter test`, собирает один release APK для arm64 и выкладывает в раздел **Artifacts** `KaGoVPN-Android-<версия>.apk` и `SHA256SUMS-Android.txt`. Приложение само проверяет последний GitHub Release и предлагает обновиться (скачивание и установка внутри приложения, проверка SHA-256; `lib/core/update/`). Поэтому имена файлов релиза менять нельзя: `KaGoVPN-Android-<v>.apk`, `KaGoVPN-Windows-x64-Setup-<v>.exe`, `KaGoVPN-macOS-<v>.dmg`, `SHA256SUMS-<платформа>.txt`. GitHub Release `v<версия>` публикует только workflow `.github/workflows/release.yml`, первый раздел RELEASE_STATUS.md становится его описанием. Его запускает пуш тега `v<версия>`, совпадающего с версией в `pubspec.yaml`, или ручной запуск (Actions → Release → Run workflow): тег создаётся на выбранном коммите автоматически. Он собирает Android, Windows и macOS параллельно и публикует релиз, только когда готовы все три файла: `.apk`, `.exe`, `.dmg`. Если какая-то платформа упала, релиз не публикуется.

Подпись: если в секретах репозитория есть `KAGO_ANDROID_KEYSTORE_BASE64`, `KAGO_ANDROID_KEYSTORE_PASSWORD`, `KAGO_ANDROID_KEY_ALIAS`, `KAGO_ANDROID_KEY_PASSWORD`, APK подписывается постоянным ключом владельца, и каждая новая версия ставится поверх предыдущей как обновление. Без секретов сборка из ветки подписывается одноразовым тестовым ключом (с пометкой `debugsigned`, обновлением не ставится), а сборка по тегу завершается ошибкой.

### Версии и обновления

- Версия в `pubspec.yaml` — `X.Y.Z+N`, где `N = X*10000 + Y*100 + Z` (versionCode Android). Пример: `1.0.1+10001`. Это проверяет `test/version_test.dart`; та же версия — в `kagoAppVersion` (`lib/core/device/device_identity.dart`).
- Каждое небольшое обновление увеличивает `Z` на 1, крупное — `Y`.
- Обновление ставится поверх, пока не меняются имя пакета `net.usekago.app` и ключ подписи. Потеря ключа означает, что пользователям придётся удалять приложение. Храните резервную копию ключа и паролей вне репозитория.
- Не используйте `--split-per-abi`: он добавляет к versionCode 1000×ABI.

### Локально

Нужны: Flutter stable, JDK 17+, Go, Android SDK/NDK с принятыми лицензиями.

Linux/macOS/WSL:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
./tool/build_android_release.sh
```

Windows PowerShell:

```powershell
.\tool\build_android_release.ps1
```

Скрипт собирает ядро Mihomo `v1.19.32` для обоих ABI, запускает `flutter analyze` и `flutter test`, собирает AAB/APK и копирует их в `dist/android/`. Ключ подписи читается только из переменных окружения `KAGO_ANDROID_KEYSTORE`, `KAGO_ANDROID_KEYSTORE_PASSWORD`, `KAGO_ANDROID_KEY_ALIAS`, `KAGO_ANDROID_KEY_PASSWORD`; без них сборка не подписана. Создать ключ можно скриптом `tool/create_android_upload_key.ps1`. Храните ключ вне репозитория, сделайте резервную копию и не пересылайте ключ и пароли в чатах.

### macOS

- Приложение `KaGo VPN.app` в `.dmg` (Apple Silicon и Intel, macOS 12+). Встроенный Mihomo `v1.19.32` — universal-бинарник в `Contents/Resources/mihomo`, обновляется вместе с приложением.
- Подключение: системный прокси macOS (`networksetup`, все включённые сети, `127.0.0.1:7890`) и режим «Весь трафик через VPN» (TUN, включён по умолчанию). TUN нужен Telegram и другим приложениям, которые не используют системный прокси.
  - При первом подключении macOS один раз спрашивает пароль администратора. В `/Library/Application Support/net.usekago.app` (владелец root) ставятся копия ядра и маленькая setuid-обёртка `kago-tun` (`macos/helper/kago_tun.c`, `root:admin`, `4750`). Обёртка игнорирует аргументы и окружение, запускает ядро с домашней папкой root и проверяет конфиг, поэтому другая программа не может с её помощью получить права root.
  - На время подключения DNS сетей — `1.1.1.1`, `8.8.8.8`. Прокси и DNS возвращаются при отключении и после сбоя.
  - Если отменить ввод пароля, остаётся только системный прокси. «Российские сайты — напрямую» работает так же, как на Windows.
  - Нужна учётная запись администратора.
- **Подпись.** Если в секретах репозитория есть сертификат Apple Developer ID, CI подписывает приложение (Hardened Runtime), нотаризует его у Apple и прикрепляет тикет к приложению и к `.dmg`. Тогда macOS открывает KaGo VPN без предупреждений. Без сертификата — ad-hoc подпись, и при первом запуске macOS пишет «Apple не удалось подтвердить, что файл „KaGo VPN“ не содержит вредоносного ПО». Открыть такое приложение можно так: «Готово» → «Системные настройки → Конфиденциальность и безопасность» → внизу «Всё равно открыть» → пароль. Или в Терминале: `xattr -dr com.apple.quarantine "/Applications/KaGo VPN.app"`.

#### Как включить подпись и нотаризацию

1. Вступить в Apple Developer Program ($99 в год) на developer.apple.com.
2. В Xcode («Settings → Accounts → Manage Certificates») или на developer.apple.com создать сертификат **Developer ID Application**, затем экспортировать его из «Связки ключей» в `.p12` с паролем.
3. На appleid.apple.com создать пароль приложения (App-Specific Password).
4. Добавить секреты репозитория (Settings → Secrets and variables → Actions):
   - `KAGO_MACOS_CERT_P12_BASE64` — содержимое `.p12` в base64 (`base64 -i cert.p12 | pbcopy`);
   - `KAGO_MACOS_CERT_PASSWORD` — пароль `.p12`;
   - `KAGO_APPLE_ID` — Apple ID (email);
   - `KAGO_APPLE_TEAM_ID` — Team ID (10 символов, developer.apple.com → Membership);
   - `KAGO_APPLE_APP_PASSWORD` — пароль приложения из п. 3.
5. Перезапустить `release.yml`: файлы релиза заменятся, `.dmg` — нотаризованным.

## Сборка macOS

Workflow `.github/workflows/macos-release.yml` (раннер `macos-latest`): analyze, тесты, загрузка Mihomo для darwin arm64 и amd64 с проверкой SHA-256, объединение в universal-бинарник (`lipo`), `flutter build macos --release`, встраивание ядра, ad-hoc подпись всего бандла и `hdiutil` → `KaGoVPN-macOS-<версия>.dmg` и `SHA256SUMS-macOS.txt`. Публикуется вместе с Android и Windows через `release.yml`.

## Сборка Windows

### В GitHub Actions (рекомендуется)

Workflow `.github/workflows/windows-release.yml` (раннер `windows-latest`) запускается при push в ветки `claude/**`, `feat/**`, `fix/**` и по тегу `v*`. Он выполняет `tool/build_windows_release.ps1` (формат, analyze, тесты, `flutter build windows --release`, ZIP), собирает установщик Inno Setup (`windows/installer/kago_vpn.iss`) и выкладывает в **Artifacts**: `KaGoVPN-Windows-x64-Setup-<версия>.exe`, переносной `KaGoVPN-Windows-x64-<версия>.zip` и `SHA256SUMS-Windows.txt`. Установщик ставит приложение для текущего пользователя без прав администратора (`%LOCALAPPDATA%\Programs\KaGo VPN`), создаёт ярлыки и деинсталлятор.

### Локально

На Windows с Flutter stable и Visual Studio 2022 (компонент **Desktop development with C++**):

```powershell
.\tool\build_windows_release.ps1
```

Скрипт проверяет форматирование, запускает analyze и тесты, выполняет `flutter build windows --release` и создаёт `dist/KaGoVPN-Windows-x64.zip`. Ядро Mihomo скачивается при первом подключении. Для публичного распространения нужен сертификат подписи кода; его в репозитории нет.

## Структура

```
lib/
  app/                # MaterialApp, навигация
  core/l10n/          # tr(), английская таблица строк
  core/network/       # контроллер Mihomo, процесс ядра, обновление ядра Windows, IP
  core/theme/         # палитра KaGoPalette, тема, общие виджеты
  features/account/   # личный кабинет и клиент API usekago.net
  features/dashboard/ # главная
  features/proxies/   # серверы и группы
  features/connections/
  features/settings/
  features/subscriptions/  # импорт и разбор подписок, генерация конфига
android/              # Kotlin: VpnService, JNI-мост, jniLibs
native/android/       # Go/cgo-адаптер ядра для Android
native/mihomo/        # исходники Mihomo v1.19.32 (upstream)
tool/                 # скрипты сборки
```

## Команды

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release
```

## Важно перед релизом

- Проверка на устройствах обязательна: разрешение и отзыв VPN, переподключение, DNS/IPv6, защита сокетов, маршрутизация, утечки; на Windows — восстановление прокси после падения ядра и перезагрузки.
- Mihomo распространяется под GPL-3.0. Проверьте совместимость с моделью лицензирования приложения и приложите требуемые уведомления и исходный код. См. `native/CORE_PIN.md` и `native/mihomo/LICENSE`.
- Политика конфиденциальности должна упоминать запросы к сервисам определения IP, опрос ссылки подписки и API личного кабинета.

Правила работы с репозиторием — в [CLAUDE.md](CLAUDE.md).
