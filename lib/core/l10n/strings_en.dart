/// English. Keys are the Russian source strings (see l10n.dart); a
/// missing key falls back to Russian. `test/l10n_test.dart` checks coverage.
const stringsEn = <String, String>{
  'Главная': 'Home',
  'Серверы': 'Servers',
  'Трафик': 'Traffic',
  'Кабинет': 'Account',
  'Настройки': 'Settings',
  '{v}/с': '{v}/s',
  '{bytes} Б': '{bytes} B',
  'КБ': 'KB',
  'МБ': 'MB',
  'ГБ': 'GB',
  'ТБ': 'TB',
  'Проверка Android core доступна только на Android.':
      'The Android core check is only available on Android.',
  'В этой сборке не найден native Mihomo. Android .so должен входить в подписанный APK/AAB.':
      'No native Mihomo in this build. The Android .so must be part of the signed APK/AAB.',
  'Версия встроенного Mihomo не распознана: {installed}':
      'Unrecognized embedded Mihomo version: {installed}',
  'Доступен Mihomo {version}. На Android ядро обновляется вместе с новой KaGo VPN сборкой.':
      'Mihomo {version} is available. On Android the core is updated with a new KaGo VPN build.',
  'Встроенный Mihomo {installed} актуален.':
      'Embedded Mihomo {installed} is up to date.',
  'Сервис не вернул IP-адрес.': 'The service did not return an IP address.',
  'ipwho.is: отказ.': 'ipwho.is: request refused.',
  'Неожиданный ответ сервиса IP.': 'Unexpected response from the IP service.',
  'Нет сервисов для определения IP.': 'No services to detect the IP.',
  'Укажите корректный HTTPS или локальный HTTP адрес без userinfo/query/fragment.':
      'Enter a valid HTTPS or local HTTP address without userinfo/query/fragment.',
  'HTTP разрешён только для localhost; удалённый контроллер должен использовать HTTPS.':
      'HTTP is allowed only for localhost; a remote controller must use HTTPS.',
  'Mihomo FFI не поддерживается на {operatingSystem}.':
      'Mihomo FFI is not supported on {operatingSystem}.',
  '\nЛог ядра:\n{v}': '\nCore log:\n{v}',
  'Встроенный Mihomo {version} готов.': 'Embedded Mihomo {version} is ready.',
  'Автозагрузка ядра не удалась: {error}':
      'Automatic core download failed: {error}',
  'Не удалось восстановить сохранённые proxy settings: {error}':
      'Could not restore the saved proxy settings: {error}',
  'Остановите Mihomo перед проверкой/установкой обновления.':
      'Stop Mihomo before checking for or installing an update.',
  'Запускается встроенный Mihomo {version}.':
      'Starting embedded Mihomo {version}.',
  'Для этой desktop-платформы укажите путь к Mihomo в настройках.':
      'On this desktop platform, set the Mihomo path in settings.',
  'Файл Mihomo из настроек не найден. Исправьте путь или очистите поле, чтобы использовать встроенное ядро':
      'The Mihomo file from settings was not found. Fix the path or clear the field to use the embedded core',
  'Встроенный Mihomo не найден на диске. Нажмите «Проверить и установить обновление» в настройках':
      'Embedded Mihomo was not found on disk. Press “Check and install update” in settings',
  'Сначала импортируйте YAML-подписку': 'Import a YAML subscription first',
  'Desktop core запускается с локальным HTTP controller. Укажите http://127.0.0.1:<port>.':
      'The desktop core starts with a local HTTP controller. Use http://127.0.0.1:<port>.',
  'Активная конфигурация Mihomo повреждена.':
      'The active Mihomo configuration is damaged.',
  'Mihomo завершился с кодом {code}.': 'Mihomo exited with code {code}.',
  'Mihomo завершился при запуске. Проверьте права и логи.{v}':
      'Mihomo exited during startup. Check permissions and logs.{v}',
  'Mihomo controller готов.': 'Mihomo controller is ready.',
  'External Controller не стал доступен за 12 секунд: {lastError}{v}':
      'External Controller did not become available within 12 seconds: {lastError}{v}',
  'Не дождались завершения процесса Mihomo.':
      'Timed out waiting for the Mihomo process to exit.',
  'Mihomo остановлен.': 'Mihomo stopped.',
  'GitHub вернул неверные данные о релизе Mihomo.':
      'GitHub returned invalid Mihomo release data.',
  'Тег Mihomo не похож на стабильную версию.':
      'The Mihomo tag does not look like a stable version.',
  'Непроверенный URL релиза Mihomo.': 'Unverified Mihomo release URL.',
  'В релизе Mihomo отсутствует список assets.':
      'The Mihomo release has no list of assets.',
  'Неверный формат версии Mihomo.': 'Invalid Mihomo version format.',
  'Не удалось связаться с GitHub ({reason}), а встроенное ядро Mihomo ещё не установлено. Проверьте интернет и доступ к github.com: загрузка повторится при следующем подключении.':
      'Could not reach GitHub ({reason}), and the embedded Mihomo core is not installed yet. Check the internet and access to github.com: the download will be retried on the next connection.',
  'Удалена старая версия ядра: {v}': 'Removed an old core version: {v}',
  'Не удалось удалить {v} (возможно, оно запущено): {message}':
      'Could not remove {v} (it may be running): {message}',
  'Очистка старых версий ядра не удалась: {error}':
      'Cleaning up old core versions failed: {error}',
  'Встроенное автоматическое ядро пока поддерживает Windows x64.':
      'The embedded automatic core currently supports Windows x64.',
  'Сохранённый mihomo.exe отсутствует или не прошёл проверку SHA-256; ядро будет установлено заново.':
      'The saved mihomo.exe is missing or failed the SHA-256 check; the core will be reinstalled.',
  'Проверка обновлений Mihomo…': 'Checking for Mihomo updates…',
  'GitHub недоступен; используется Mihomo {version}: {error}':
      'GitHub is unavailable; using Mihomo {version}: {error}',
  'GitHub API недоступен, встроенное ядро не установлено: {error}':
      'GitHub API is unavailable, the embedded core is not installed: {error}',
  'Загружается закреплённая версия {version} напрямую с github.com.':
      'Downloading the pinned version {version} directly from github.com.',
  'Mihomo {version} уже установлен.': 'Mihomo {version} is already installed.',
  'Для {latest} не найден поддерживаемый asset; оставлено Mihomo {version}.':
      'No supported asset found for {latest}; keeping Mihomo {version}.',
  'В релизе {latest} нет поддерживаемой Windows x64 сборки Mihomo.':
      'Release {latest} has no supported Windows x64 Mihomo build.',
  'Размер Mihomo ZIP превышает безопасный лимит.':
      'The Mihomo ZIP is larger than the safe limit.',
  'Загрузка Mihomo: {v}%': 'Downloading Mihomo: {v}%',
  'Загруженный Mihomo ZIP имеет неверный размер.':
      'The downloaded Mihomo ZIP has the wrong size.',
  'Для закреплённой версии нет эталонного SHA-256: проверены источник github.com по HTTPS, структура ZIP и запуск mihomo -v.':
      'No reference SHA-256 for the pinned version: checked the github.com source over HTTPS, the ZIP structure and running mihomo -v.',
  'SHA-256 Mihomo ZIP не совпал с GitHub release digest.':
      'The Mihomo ZIP SHA-256 does not match the GitHub release digest.',
  'В Mihomo ZIP должен быть ровно один Windows executable.':
      'The Mihomo ZIP must contain exactly one Windows executable.',
  'Небезопасный размер mihomo.exe в ZIP.':
      'Unsafe size of mihomo.exe in the ZIP.',
  'mihomo.exe распакован неполностью.': 'mihomo.exe was not fully extracted.',
  'Mihomo {latest} установлен и проверен.':
      'Mihomo {latest} installed and verified.',
  'Обновление Mihomo не завершилось; оставлено {version}: {error}':
      'The Mihomo update did not finish; keeping {version}: {error}',
  'На странице релиза не найден SHA-256 для {assetName}.':
      'No SHA-256 for {assetName} found on the release page.',
  'SHA-256 для {assetName} получен со страницы релиза.':
      'SHA-256 for {assetName} taken from the release page.',
  'Не удалось получить SHA-256 со страницы релиза: {error}':
      'Could not get the SHA-256 from the release page: {error}',
  'Проверка mihomo.exe не прошла для {expectedVersion} (код {exitCode}).':
      'mihomo.exe check failed for {expectedVersion} (code {exitCode}).',
  'Не удалось обновить настройки системного прокси Windows.':
      'Could not update the Windows system proxy settings.',
  'Системный прокси доступен только в Windows.':
      'The system proxy is only available on Windows.',
  'Личный кабинет': 'Personal account',
  'Добро пожаловать': 'Welcome',
  'Здравствуйте!': 'Hello!',
  'Здравствуйте, {name}': 'Hello, {name}',
  'Управляйте подпиской, устройствами и аккаунтом в одном месте.':
      'Manage your subscription, devices and account in one place.',
  'Выйти': 'Log out',
  'Вы вышли из аккаунта.': 'You have logged out.',
  'Откройте {url}': 'Open {url}',
  'Отмена': 'Cancel',
  '{n} дн.': '{n} d.',
  'Введите корректный email.': 'Enter a valid email.',
  'Пароль — минимум 8 символов.': 'Password must be at least 8 characters.',
  'Введите пароль.': 'Enter your password.',
  'Вы вошли. Подписка добавлена на это устройство.':
      'You are signed in. The subscription was added to this device.',
  'Вы вошли в аккаунт.': 'You are signed in.',
  'Забыли пароль?': 'Forgot your password?',
  'Вы регистрировались раньше и пароль не задавали':
      'You registered before and never set a password',
  'Зарегистрируйтесь с той же почтой — аккаунт и подписка сохранятся.':
      'Sign up with the same email — your account and subscription will be kept.',
  'Пароль был, но вы его забыли': 'You had a password but forgot it',
  'Напишите в поддержку — поможем восстановить доступ.':
      'Contact support — we will help you restore access.',
  'Регистрация': 'Sign up',
  'Поддержка': 'Support',
  'Вход': 'Sign in',
  'Создайте аккаунт KAGO': 'Create a KAGO account',
  'Войдите в личный кабинет KAGO': 'Sign in to your KAGO account',
  'Имя (необязательно)': 'Name (optional)',
  'Пароль (минимум 8 символов)': 'Password (at least 8 characters)',
  'Пароль': 'Password',
  'Показать пароль': 'Show password',
  'Скрыть пароль': 'Hide password',
  'Зарегистрироваться': 'Sign up',
  'Войти': 'Sign in',
  'Уже есть аккаунт?': 'Already have an account?',
  'Нет аккаунта?': 'No account?',
  'Перевыпустить ключ?': 'Re-issue the key?',
  'Старая ссылка перестанет работать. На этом устройстве подписка обновится автоматически, на остальных её нужно добавить заново.':
      'The old link will stop working. On this device the subscription updates automatically; on other devices add it again.',
  'Перевыпустить': 'Re-issue',
  'Ключ перевыпущен.': 'The key has been re-issued.',
  'Не удалось загрузить подписку': 'Could not load the subscription',
  'Повторить': 'Retry',
  'Подписка неактивна': 'Subscription inactive',
  'Срок подписки истёк': 'Your subscription has expired',
  'Защита пока выключена': 'Protection is off',
  'Продлите подписку — доступ к серверам и защита ваших устройств вернутся сразу после оплаты.':
      'Renew your subscription — access to the servers and protection of your devices return right after payment.',
  'Оформите подписку и получите доступ к серверам на скорости до 1 Гбит/с и защите до 5 устройств.':
      'Get a subscription for servers with up to 1 Gbit/s and protection for up to 5 devices.',
  'Продлить': 'Renew',
  'Выбрать тариф': 'Choose a plan',
  'Сравнить тарифы': 'Compare plans',
  'Подключено': 'Connected',
  'Активна': 'Active',
  'Активна до {date}': 'Active until {date}',
  'Пробный период': 'Trial period',
  'Подключить это устройство': 'Connect this device',
  'Отключиться': 'Disconnect',
  'Подключиться': 'Connect',
  'Скопировать ссылку': 'Copy link',
  'Ссылка скопирована. Это ваш ключ — не передавайте её посторонним.':
      'Link copied. This is your key — do not share it.',
  'Осталось': 'Left',
  'Устройств': 'Devices',
  'Безлимит': 'Unlimited',
  'Оформить подписку': 'Get a subscription',
  'Перевыпустить ключ': 'Re-issue key',
  'Тарифы': 'Plans',
  'Отключить все устройства?': 'Disconnect all devices?',
  'Все устройства потеряют доступ, пока снова не подключатся по ссылке.':
      'All devices lose access until they connect again with the link.',
  'Отключить все': 'Disconnect all',
  'Все устройства отключены.': 'All devices disconnected.',
  'Устройство отключено.': 'Device disconnected.',
  'Устройства': 'Devices',
  'Устройств пока нет. Устройство появится здесь после первого подключения по ссылке подписки.':
      'No devices yet. A device appears here after its first connection with the subscription link.',
  'Устройство': 'Device',
  'Отключить': 'Disconnect',
  'Промокод активирован.': 'Promo code activated.',
  'Промокод': 'Promo code',
  'Есть код? Активируйте его и получите бонус к подписке.':
      'Have a code? Activate it to get a subscription bonus.',
  'Введите код': 'Enter code',
  'Активировать': 'Activate',
  'Аккаунт': 'Account',
  'Не указан': 'Not set',
  'Подтверждён': 'Verified',
  'Не подтверждён': 'Not verified',
  'Новый email (ожидает подтверждения)': 'New email (awaiting confirmation)',
  'Подключен': 'Linked',
  'Не подключен': 'Not linked',
  'Сменить пароль': 'Change password',
  'Сменить email': 'Change email',
  'Подтвердить новый email': 'Confirm new email',
  'Подтвердить email': 'Verify email',
  'Сохранить': 'Save',
  'Текущий пароль': 'Current password',
  'Новый пароль (мин. 8)': 'New password (min. 8)',
  'Новый пароль — минимум 8 символов.':
      'New password must be at least 8 characters.',
  'Пароль изменён.': 'Password changed.',
  'Отправить код': 'Send code',
  'Новый email': 'New email',
  'Код отправлен на {email}': 'Code sent to {email}',
  'Email обновлён.': 'Email updated.',
  'Код отправлен на email.': 'Code sent to your email.',
  'Email подтверждён.': 'Email verified.',
  'Код из письма': 'Code from the email',
  'Подтвердить': 'Confirm',
  '6 цифр': '6 digits',
  'Реферальная программа': 'Referral program',
  'Программа сейчас недоступна.': 'The program is unavailable right now.',
  'Приглашайте друзей по своей ссылке. За каждого, кто оформит подписку, вы оба получите +30 дней бесплатно.':
      'Invite friends with your link. For everyone who subscribes, you both get +30 days for free.',
  'Приглашено': 'Invited',
  'Оплатили': 'Paid',
  'Копировать': 'Copy',
  'Скопировано.': 'Copied.',
  'Реферальная программа доступна после подтверждения почты. Подтвердите email в разделе «Аккаунт» выше.':
      'The referral program is available after you verify your email. Verify it in the “Account” section above.',
  'Помощь': 'Help',
  'Telegram-бот': 'Telegram bot',
  'Сессия истекла. Войдите снова.': 'Session expired. Please sign in again.',
  'usekago.net не отвечает. Проверьте интернет и попробуйте ещё раз.':
      'usekago.net is not responding. Check the internet and try again.',
  'Нет связи с usekago.net. Проверьте интернет и попробуйте ещё раз.':
      'No connection to usekago.net. Check the internet and try again.',
  'Ошибка сервера (HTTP {status})': 'Server error (HTTP {status})',
  'Соединения': 'Connections',
  'Активные сетевые сессии ядра Mihomo. Список обновляется автоматически.':
      'Active network sessions of the Mihomo core. The list updates automatically.',
  'Контроллер недоступен: {error}': 'Controller unavailable: {error}',
  'Активных соединений нет.': 'No active connections.',
  'Ядро выключено — активных соединений нет.':
      'The core is off — no active connections.',
  'Ошибка: {error}': 'Error: {error}',
  'Закрыть все': 'Close all',
  'Закрыть соединение': 'Close connection',
  'Интернет без границ': 'Internet without borders',
  'Обновить': 'Refresh',
  'Разрешение VPN отозвано': 'VPN permission revoked',
  'Не удалось запустить Android VPN': 'Could not start Android VPN',
  'Ваш сервер': 'Your server',
  'Ядро не запущено. Нажмите кнопку питания ниже, чтобы запустить VPN.':
      'The core is not running. Press the power button below to start the VPN.',
  'Контроллер недоступен — проверьте адрес в настройках.':
      'Controller unavailable — check the address in settings.',
  'Не подключено': 'Not connected',
  'Ядро Mihomo остановлено.': 'Mihomo core stopped.',
  'Mihomo запущен и controller отвечает.':
      'Mihomo started and the controller responds.',
  'Не удалось запустить Mihomo: {error}': 'Could not start Mihomo: {error}',
  'Запрошено отключение Android VPN.': 'Android VPN disconnect requested.',
  'Запуск VPN запрошен. Подтвердите системное разрешение Android.':
      'VPN start requested. Confirm the Android system permission.',
  'Android native bridge недоступен в этой сборке.':
      'The Android native bridge is not available in this build.',
  'Не удалось выполнить запрос Android VPN.':
      'Could not complete the Android VPN request.',
  'Не удалось подготовить профиль: {message}':
      'Could not prepare the profile: {message}',
  'Нативный VPN-мост ещё не подключён. REST-клиент Mihomo доступен после настройки контроллера.':
      'The native VPN bridge is not connected yet. The Mihomo REST client is available after configuring the controller.',
  'Не удалось запустить VPN.': 'Could not start the VPN.',
  '{used} использовано': '{used} used',
  'Узел не отвечает': 'Node does not respond',
  'IP через VPN': 'IP via VPN',
  'Ваш IP': 'Your IP',
  'Не определён': 'Unknown',
  'Определяем…': 'Detecting…',
  'Показать IP': 'Show IP',
  'Скрыть IP': 'Hide IP',
  'Проверить IP': 'Check IP',
  'Загрузка': 'Download',
  'всего {v}': 'total {v}',
  'Отдача': 'Upload',
  'Серверы и группы': 'Servers and groups',
  'Проверить задержку': 'Test latency',
  'Сортировка': 'Sort',
  'По порядку': 'By order',
  'По задержке': 'By latency',
  'По имени': 'By name',
  'Выберите активный узел. Данные берутся из ядра Mihomo.':
      'Choose the active node. Data comes from the Mihomo core.',
  'Ядро выключено: показаны серверы из профиля. Выбор узла и проверка задержки доступны после подключения.':
      'The core is off: servers from the profile are shown. Node selection and latency tests are available after connecting.',
  'Не удалось получить группы прокси: {error}':
      'Could not get proxy groups: {error}',
  'Прокси-групп нет. Добавьте профиль и загрузите конфигурацию ядра.':
      'No proxy groups. Add a profile and load the core configuration.',
  '{type} · {length} шт.': '{type} · {length} nodes',
  '{type} · узел выбирается автоматически':
      '{type} · node is chosen automatically',
  'У этой группы нет доступных узлов.': 'This group has no available nodes.',
  'Не удалось выбрать узел: {error}': 'Could not select the node: {error}',
  'Не удалось проверить задержку: {error}': 'Could not test latency: {error}',
  'Таймаут': 'Timeout',
  '{value} мс': '{value} ms',
  'Проверяется…': 'Checking…',
  'Mihomo ещё не установлен: он скачается автоматически в %APPDATA%\\KaGo\\core.':
      'Mihomo is not installed yet: it will be downloaded automatically to %APPDATA%\\KaGo\\core.',
  'Установлен Mihomo {version}.': 'Mihomo {version} installed.',
  'Внешний вид': 'Appearance',
  'Тема': 'Theme',
  'Авто': 'Auto',
  'Светлая': 'Light',
  'Тёмная': 'Dark',
  'Чисто чёрный фон': 'Pure black background',
  'Тёмная тема для OLED-дисплеев': 'Dark theme for OLED displays',
  'Подключение': 'Connection',
  'Адрес контроллера': 'Controller address',
  'Режим подключения': 'Connection mode',
  'Путь к Mihomo': 'Mihomo path',
  'Не задан. Укажите путь к бинарнику Mihomo.':
      'Not set. Specify the path to the Mihomo binary.',
  'Логи Mihomo': 'Mihomo logs',
  'О приложении': 'About',
  'Лицензии': 'Licenses',
  'Блокировать интернет без VPN': 'Block the internet without VPN',
  'Откройте «Настройки → Сеть → VPN» и включите для KaGo VPN «Постоянная VPN».':
      'Open “Settings → Network → VPN” and turn on “Always-on VPN” for KaGo VPN.',
  '{windowsCoreStatus} Остановите ядро, чтобы обновить.':
      '{windowsCoreStatus} Stop the core to update.',
  'Проверка версии встроенного Mihomo…':
      'Checking the embedded Mihomo version…',
  'Не удалось проверить upstream release: {error}':
      'Could not check the upstream release: {error}',
  'Mihomo · внешний бинарник': 'Mihomo · external binary',
  'HTTPS или локальный HTTP. Secret создаётся автоматически.':
      'HTTPS or local HTTP. The secret is generated automatically.',
  'Адрес контроллера сохранён.': 'Controller address saved.',
  'Не удалось сохранить: {error}': 'Could not save: {error}',
  'Полный путь к исполняемому файлу Mihomo.':
      'Full path to the Mihomo executable.',
  'Путь к Mihomo сохранён.': 'Mihomo path saved.',
  'Логов пока нет. Они появятся при запуске или загрузке ядра.':
      'No logs yet. They appear when the core starts or downloads.',
  'Закрыть': 'Close',
  'Проверяются и загружаются данные релиза Mihomo…':
      'Checking and downloading Mihomo release data…',
  'Установлен Mihomo {version}. Проверить обновление не удалось ({note}).':
      'Mihomo {version} installed. Could not check for updates ({note}).',
  'Обновление не выполнено: {error}': 'Update failed: {error}',
  'Корень конфигурации Mihomo должен быть YAML-объектом.':
      'The root of the Mihomo configuration must be a YAML object.',
  'В подписке не найдены proxies или proxy-providers.':
      'No proxies or proxy-providers found in the subscription.',
  'Для встроенного Android Mihomo задайте локальный HTTP controller: http://127.0.0.1:<port>.':
      'For the embedded Android Mihomo use a local HTTP controller: http://127.0.0.1:<port>.',
  'Подписка вернула пустой ответ.':
      'The subscription returned an empty response.',
  'Ответ не является Clash/Mihomo YAML или поддерживаемым списком ссылок VLESS/VMess/Trojan/SS/Hysteria2/TUIC.':
      'The response is not Clash/Mihomo YAML or a supported list of VLESS/VMess/Trojan/SS/Hysteria2/TUIC links.',
  'VLESS URI не содержит UUID.': 'The VLESS URI has no UUID.',
  'Trojan URI не содержит пароль.': 'The Trojan URI has no password.',
  'VMess URI должен содержать JSON-профиль.':
      'The VMess URI must contain a JSON profile.',
  'VMess URI содержит неполный адрес, порт или UUID.':
      'The VMess URI has an incomplete address, port or UUID.',
  'Shadowsocks URI содержит неверную Base64-строку.':
      'The Shadowsocks URI has an invalid Base64 string.',
  'Shadowsocks URI должен содержать method:password@host:port.':
      'The Shadowsocks URI must contain method:password@host:port.',
  'Shadowsocks URI не содержит method/password.':
      'The Shadowsocks URI has no method/password.',
  'Hysteria2 URI не содержит пароль.': 'The Hysteria2 URI has no password.',
  'TUIC URI должен содержать UUID и пароль.':
      'The TUIC URI must contain a UUID and password.',
  'URI не содержит сервер.': 'The URI has no server.',
  'URI содержит неверный порт.': 'The URI has an invalid port.',
  'Ссылка вернула пустой профиль.': 'The link returned an empty profile.',
  'Для внешней подписки используйте HTTPS; HTTP допустим только на localhost. Ссылки с userinfo/fragment запрещены.':
      'Use HTTPS for an external subscription; HTTP is allowed only on localhost. Links with userinfo/fragment are not allowed.',
  'Язык': 'Language',
  'Приложения и VPN': 'Apps and VPN',
  'Раздельное туннелирование доступно только на Android.':
      'Split tunneling is only available on Android.',
  'Сохранено. Изменения применятся при следующем подключении VPN.':
      'Saved. Changes apply the next time the VPN connects.',
  'Российские сервисы из списка не установлены.':
      'None of the listed Russian services are installed.',
  'Добавлено приложений: {n}': 'Apps added: {n}',
  'Все': 'All',
  'Кроме выбранных': 'Except selected',
  'Только выбранные': 'Only selected',
  'Отмеченные приложения работают напрямую, без VPN. Так работают сервисы, которые не открываются через VPN (Яндекс Музыка, VK, банки).':
      'Checked apps work directly, without the VPN. Use this for services that do not open through a VPN (Yandex Music, VK, banks).',
  'Через VPN идут только отмеченные приложения, остальные — напрямую.':
      'Only checked apps use the VPN; the rest go directly.',
  'Все приложения работают через VPN.': 'All apps use the VPN.',
  'Российские сервисы — мимо VPN': 'Russian services — bypass VPN',
  'Поиск приложения': 'Search apps',
  'Российские сайты — напрямую': 'Russian sites — direct',
  'или': 'or',
  'Войти через Telegram': 'Sign in with Telegram',
  'Привяжите Telegram, чтобы входить через бота и в приложении.':
      'Link Telegram to sign in through the bot and in the app.',
  'Привязать Telegram': 'Link Telegram',
  'Не удалось перенести вход в приложение. Попробуйте ещё раз или войдите по email и паролю.':
      'Could not bring the sign-in into the app. Try again or sign in with email and password.',
  'Вход через Telegram': 'Telegram sign-in',
  'Кабинет на сайте': 'Website account',
  'Готово': 'Done',
  'Нажмите «Войти через Telegram» и подтвердите вход в Telegram. Окно закроется само.':
      'Tap “Войти через Telegram” and confirm the sign-in in Telegram. This window closes by itself.',
  'Здесь можно привязать Telegram к аккаунту. Нажмите «Готово», когда закончите.':
      'Link Telegram to your account here. Tap “Done” when finished.',
  'Назад': 'Back',
  'Входим в аккаунт…': 'Signing you in…',
  'Подключаемся к usekago.net…': 'Connecting to usekago.net…',
  'Подтвердите вход в Telegram — пароль не нужен. Аккаунт KAGO и подписка подключатся автоматически.':
      'Confirm the sign-in in Telegram, no password needed. Your KAGO account and subscription connect automatically.',
  'Продолжить с Telegram': 'Continue with Telegram',
  'Вход через официальный сайт Telegram':
      'Signed in via the official Telegram website',
  'или по email': 'or with email',
  'Дополнительно': 'Advanced',
  'Для опытных пользователей': 'For advanced users',
  'Ядро, логи и адрес контроллера': 'Core, logs and controller address',
  'Приложения без VPN': 'Apps without VPN',
  'Например, Яндекс Музыка, VK и банки':
      'For example Yandex Music, VK and banks',
  'Включается в системных настройках VPN':
      'Turned on in the system VPN settings',
  'Яндекс, VK, банки и Госуслуги — без VPN':
      'Yandex, VK, banks and Gosuslugi bypass the VPN',
  'Системный прокси 127.0.0.1:7890': 'System proxy 127.0.0.1:7890',
  'Сервер подписки не выдал серверы: «{message}». Проверьте лимит устройств в «Кабинете» → «Устройства» и обновите подписку.':
      'The subscription server returned no servers: “{message}”. Check the device limit in “Account” → “Devices” and refresh the subscription.',
  'Достигнут лимит устройств подписки. Удалите лишнее устройство в «Кабинете» → «Устройства» и обновите подписку.':
      'The subscription device limit is reached. Remove a device in “Account” → “Devices” and refresh the subscription.',
  'Сервер подписки не принял идентификатор устройства (HWID). Обновите приложение или напишите в поддержку.':
      'The subscription server did not accept the device ID (HWID). Update the app or contact support.',
  '{length} серверов': '{length} servers',
  'Подключение…': 'Connecting…',
  '{used} из {total}': '{used} of {total}',
  'до {date}': 'until {date}',
  'Версия {version} · usekago.net': 'Version {version} · usekago.net',
  'Войдите в аккаунт': 'Sign in to your account',
  'Сначала войдите в аккаунт KAGO во вкладке «Кабинет».':
      'First sign in to your KAGO account on the “Account” tab.',
  'Обновляем подписку…': 'Updating the subscription…',
  'Подписка обновлена.': 'Subscription updated.',
  'Не удалось обновить подписку: {error}':
      'Could not update the subscription: {error}',
  'Войдите в аккаунт KAGO — подписка подключится сама':
      'Sign in to your KAGO account and the subscription is added automatically',
  'Нет подписки': 'No subscription',
  'Встроено в приложение: {version}. Обновляется вместе с KaGo VPN.':
      'Built into the app: {version}. Updated together with KaGo VPN.',
  'На Linux пока нужен внешний Mihomo. Встроенное ядро есть в версиях для Windows, macOS и Android.':
      'Linux still needs an external Mihomo. The Windows, macOS and Android versions have a built-in core.',
  'Не удалось получить список сетей macOS: {error}':
      'Could not list macOS network services: {error}',
  'Не удалось включить системный прокси macOS: {error}. Нужна учётная запись администратора.':
      'Could not turn on the macOS system proxy: {error}. An administrator account is required.',
  'нет активных сетей': 'no active networks',
  'Системный прокси macOS доступен только в macOS.':
      'The macOS system proxy is only available on macOS.',
  'Системный прокси направлен на 127.0.0.1:7890.':
      'The system proxy points to 127.0.0.1:7890.',
  'Нужна учётная запись администратора macOS.':
      'A macOS administrator account is required.',
  'KaGo VPN включает режим «Весь трафик через VPN». Это нужно один раз.':
      'KaGo VPN is turning on "All traffic through VPN". This is needed once.',
  'Отменено.': 'Cancelled.',
  'Режим «Весь трафик через VPN» выключен: {error}':
      '"All traffic through VPN" is off: {error}',
  'Весь трафик идёт через VPN (TUN).':
      'All traffic goes through the VPN (TUN).',
  'Весь трафик через VPN': 'All traffic through VPN',
  'Для Telegram и приложений, которые не используют системный прокси. Один раз спросит пароль администратора.':
      'For Telegram and apps that ignore the system proxy. Asks for the administrator password once.',
  'Не включено: {error}': 'Not turned on: {error}',
  'Переподключитесь, чтобы применить.': 'Reconnect to apply.',
  'Не удалось узнать последнюю версию.':
      'Could not find out the latest version.',
  'В релизе нет контрольной суммы обновления.':
      'The release has no checksum for the update.',
  'Файл обновления повреждён (контрольная сумма не совпала). Попробуйте ещё раз.':
      'The update file is damaged (checksum mismatch). Please try again.',
  'Обновление не поддерживается на этой системе.':
      'Updates are not supported on this system.',
  'Доступна версия {version}': 'Version {version} is available',
  'Обновление скачается и установится прямо из приложения. Настройки и вход сохранятся.':
      'The update downloads and installs right from the app. Your settings and sign-in are kept.',
  'Скачано {done} из {total}': '{done} of {total} downloaded',
  'Скачивание…': 'Downloading…',
  'Открывается установка…': 'Opening the installer…',
  'Устанавливается. KaGo VPN перезапустится сам.':
      'Installing. KaGo VPN will restart by itself.',
  'Разрешите KaGo VPN устанавливать приложения (откроются настройки), вернитесь и нажмите «Установить».':
      'Allow KaGo VPN to install apps (settings will open), then come back and tap "Install".',
  'Открыт образ диска с новой версией: перетащите KaGo VPN в «Программы» с заменой и запустите снова.':
      'The disk image with the new version is open: drag KaGo VPN to Applications, replace it and start it again.',
  'Не удалось обновить: {error}': 'Could not update: {error}',
  'Позже': 'Later',
  'Установить': 'Install',
  'Понятно': 'Got it',
  'Обновления': 'Updates',
  'Проверка…': 'Checking…',
  'Доступна версия {version} — нажмите, чтобы обновить':
      'Version {version} is available — tap to update',
  'Не удалось проверить. Нажмите, чтобы повторить.':
      'Could not check. Tap to retry.',
  'Установлена последняя версия': 'You have the latest version',
  'Не удалось скопировать ядро.': 'Could not copy the core.',
};
