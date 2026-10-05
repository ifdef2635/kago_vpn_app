import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_providers.dart';
import '../../core/network/mihomo_windows_core_updater.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/appearance.dart';
import '../../core/theme/kago_theme.dart';
import '../../core/l10n/l10n.dart';

/// Refresh rate Flutter currently renders at ("144 Гц"). Updates when the window
/// moves to another monitor or the display mode changes.
class _RefreshRateLabel extends StatefulWidget {
  const _RefreshRateLabel();

  @override
  State<_RefreshRateLabel> createState() => _RefreshRateLabelState();
}

class _RefreshRateLabelState extends State<_RefreshRateLabel>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hz = View.of(context).display.refreshRate;
    return Text(
        hz > 0
            ? tr('{v} Гц · анимации и прокрутка на полной частоте', <String, Object?>{'v': hz.round()})
            : tr('Частота экрана не определена'),
        style: TextStyle(fontSize: 12, color: context.kago.muted));
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _endpoint = 'http://127.0.0.1:9090';
  String _binary = '';
  bool _coreUpdating = false;
  String _windowsCoreStatus = tr('Проверяется…');

  @override
  void initState() {
    super.initState();
    final manager = ref.read(mihomoProcessProvider);
    ref.read(mihomoControllerProvider).endpoint.then((value) async {
      final binary = await manager.executable;
      final core = await manager.installedCore();
      if (!mounted) return;
      setState(() {
        _endpoint = value;
        _binary = binary ?? '';
        _windowsCoreStatus = core == null
            ? tr('Mihomo ещё не установлен: он скачается автоматически в %APPDATA%\\KaGo\\core.')
            : tr('Установлен Mihomo {version}.', <String, Object?>{'version': core.version});
      });
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final coreRunning = ref.watch(desktopCoreRunningProvider);
    final appearance = ref.watch(appearanceProvider);
    final androidUpdate =
        Platform.isAndroid ? ref.watch(androidCoreUpdateStatusProvider) : null;
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: <Widget>[
          SectionTitle(tr('Настройки')),
          const SizedBox(height: 18),
          _SettingsGroup(title: tr('Внешний вид'), children: <Widget>[
            _SettingsTile(
                icon: Icons.contrast_rounded,
                title: tr('Тема'),
                subtitleWidget: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<ThemeMode>>[
                      ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(tr('Авто'))),
                      ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(tr('Светлая'))),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(tr('Тёмная'))),
                    ],
                    selected: <ThemeMode>{appearance.mode},
                    onSelectionChanged: (value) => ref
                        .read(appearanceProvider.notifier)
                        .setMode(value.first),
                  ),
                )),
            _SettingsTile(
                icon: Icons.translate_rounded,
                title: tr('Язык'),
                subtitleWidget: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<String>>[
                      ButtonSegment(value: 'system', label: Text(tr('Авто'))),
                      const ButtonSegment(value: 'ru', label: Text('Русский')),
                      const ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: <String>{appearance.language},
                    onSelectionChanged: (value) => ref
                        .read(appearanceProvider.notifier)
                        .setLanguage(value.first),
                  ),
                )),
            if (appearance.mode != ThemeMode.light)
              _SettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: tr('Чисто чёрный фон'),
                  subtitle: tr('Тёмная тема для OLED-дисплеев'),
                  trailing: Switch(
                      value: appearance.pureBlack,
                      onChanged: (value) => ref
                          .read(appearanceProvider.notifier)
                          .setPureBlack(value)),
                  onTap: () => ref
                      .read(appearanceProvider.notifier)
                      .setPureBlack(!appearance.pureBlack)),
            _SettingsTile(
                icon: Icons.speed_rounded,
                title: tr('Частота экрана'),
                subtitleWidget: const _RefreshRateLabel()),
          ]),
          _SettingsGroup(title: tr('Подключение'), children: <Widget>[
            _SettingsTile(
                icon: Icons.hub_outlined,
                title: tr('Адрес контроллера'),
                subtitle: _endpoint,
                onTap: _editEndpoint),
            _SettingsTile(
                icon: Icons.vpn_key_outlined,
                title: tr('Secret контроллера'),
                subtitle:
                    tr('Создаётся автоматически и хранится в защищённом хранилище')),
            if (Platform.isWindows)
              _SettingsTile(
                  icon: Icons.lan_outlined,
                  title: tr('Режим подключения'),
                  subtitle:
                      tr('Системный прокси Windows (127.0.0.1:7890). Работают приложения, которые используют его; это не полноценный TUN.')),
            if (!Platform.isAndroid && !Platform.isWindows)
              _SettingsTile(
                  icon: Icons.terminal_rounded,
                  title: tr('Путь к Mihomo'),
                  subtitle: _binary.isEmpty
                      ? tr('Не задан. Укажите путь к бинарнику Mihomo.')
                      : _binary,
                  onTap: _editBinary),
          ]),
          _SettingsGroup(title: tr('Безопасность'), children: _securityTiles()),
          _SettingsGroup(
              title: tr('Ядро Mihomo'),
              children: _coreTiles(coreRunning, androidUpdate)),
          _SettingsGroup(title: tr('Диагностика'), children: <Widget>[
            _SettingsTile(
                icon: Icons.receipt_long_outlined,
                title: tr('Логи Mihomo'),
                subtitle: tr('Последние строки лога ядра и загрузки'),
                onTap: _showLogs),
          ]),
          _SettingsGroup(title: tr('О приложении'), children: <Widget>[
            _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: tr('Версия и сайт'),
                subtitle: tr('KaGo VPN · usekago.net · клиент на ядре Mihomo')),
            _SettingsTile(
                icon: Icons.description_outlined,
                title: tr('Лицензии'),
                subtitle: tr('Mihomo распространяется под GPL-3.0'),
                onTap: () => showLicensePage(
                    context: context, applicationName: 'KaGo VPN')),
          ]),
        ]);
  }

  List<Widget> _securityTiles() {
    if (Platform.isAndroid) {
      return <Widget>[
        _SettingsTile(
            icon: Icons.shield_outlined,
            title: tr('Блокировать интернет без VPN'),
            subtitle:
                tr('Kill switch: в системных настройках включите для KaGo VPN «Постоянная VPN» и «Блокировать соединения без VPN»'),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: _openVpnSettings),
        _SettingsTile(
            icon: Icons.dns_outlined,
            title: tr('Защита от утечек'),
            subtitle:
                tr('DNS только через ядро (DoH, fake-ip), IPv6 мимо туннеля заблокирован, обход VPN приложениями запрещён')),
        _SettingsTile(
            icon: Icons.visibility_off_outlined,
            title: tr('Без локальных прокси-портов'),
            subtitle:
                tr('Другие приложения на телефоне не могут через 127.0.0.1 обнаружить VPN и узнать адрес сервера. В логах ядра не сохраняются посещённые сайты.')),
      ];
    }
    return <Widget>[
      if (Platform.isWindows)
        _SettingsTile(
            icon: Icons.warning_amber_rounded,
            title: tr('Ограничение режима прокси'),
            subtitle:
                tr('Приложения, которые не используют системный прокси Windows, и их DNS-запросы идут мимо VPN.')),
      _SettingsTile(
          icon: Icons.lock_outline_rounded,
          title: tr('Локальный доступ'),
          subtitle:
              tr('Прокси и контроллер слушают только 127.0.0.1; подписка не может открыть порты для сети или запустить входящие серверы.')),
    ];
  }

  Future<void> _openVpnSettings() async {
    var opened = false;
    try {
      opened = await const MethodChannel('net.usekago.vpn/service')
              .invokeMethod<bool>('openVpnSettings') ??
          false;
    } on MissingPluginException {
      opened = false;
    } on PlatformException {
      opened = false;
    }
    if (!opened) {
      _snack(
          tr('Откройте «Настройки → Сеть → VPN» и включите для KaGo VPN «Постоянная VPN».'));
    }
  }

  List<Widget> _coreTiles(bool coreRunning, AsyncValue<String>? androidUpdate) {
    if (Platform.isWindows) {
      return <Widget>[
        _SettingsTile(
            icon: Icons.memory_rounded,
            title: 'Mihomo · Windows x64',
            subtitle: coreRunning
                ? tr('{windowsCoreStatus} Остановите ядро, чтобы обновить.', <String, Object?>{'windowsCoreStatus': _windowsCoreStatus})
                : _windowsCoreStatus,
            trailing: _coreUpdating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.system_update_alt_rounded,
                    color:
                        coreRunning ? context.kago.muted : context.kago.accent),
            onTap: _coreUpdating || coreRunning ? null : _checkWindowsCore),
        _SettingsTile(
            icon: Icons.folder_outlined,
            title: tr('Папка ядра'),
            subtitle: r'%APPDATA%\KaGo\core · нажмите, чтобы скопировать путь',
            onTap: () async {
              await Clipboard.setData(
                  const ClipboardData(text: r'%APPDATA%\KaGo\core'));
              _snack(tr('Путь скопирован.'));
            }),
        _SettingsTile(
            icon: Icons.verified_user_outlined,
            title: tr('Проверка и обновление'),
            subtitle:
                tr('Автозагрузка с GitHub, проверка SHA-256 при установке и перед запуском, старые версии удаляются автоматически.')),
      ];
    }
    if (Platform.isAndroid) {
      final status = androidUpdate?.when(
              data: (value) => value,
              loading: () => tr('Проверка версии встроенного Mihomo…'),
              error: (error, _) =>
                  tr('Не удалось проверить upstream release: {error}', <String, Object?>{'error': error})) ??
          '';
      return <Widget>[
        _SettingsTile(
            icon: Icons.memory_rounded,
            title: 'Mihomo · Android',
            subtitle: status,
            trailing: Icon(Icons.refresh_rounded, color: context.kago.accent),
            onTap: () => ref.invalidate(androidCoreUpdateStatusProvider)),
        _SettingsTile(
            icon: Icons.verified_user_outlined,
            title: tr('Обновление ядра'),
            subtitle:
                tr('Ядро поставляется внутри подписанного APK/AAB и обновляется вместе с приложением; удалённая подмена .so отключена.')),
      ];
    }
    return <Widget>[
      _SettingsTile(
          icon: Icons.memory_rounded,
          title: tr('Mihomo · внешний бинарник'),
          subtitle:
              tr('На Linux/macOS пока нужен внешний Mihomo. Встроенное автообновление поддерживает Windows x64.')),
    ];
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editEndpoint() async {
    final value = await showDialog<String>(
        context: context,
        builder: (_) => _TextPromptDialog(
            title: tr('Адрес контроллера'),
            initial: _endpoint,
            hint: 'http://127.0.0.1:9090',
            helper:
                tr('HTTPS или локальный HTTP. Secret создаётся автоматически.')));
    if (value == null) return;
    try {
      final controller = ref.read(mihomoControllerProvider);
      await controller.saveSettings(endpoint: value);
      final saved = await controller.endpoint;
      ref.invalidate(coreVersionProvider);
      ref.invalidate(proxyGroupsProvider);
      ref.invalidate(connectionsSnapshotProvider);
      if (mounted) setState(() => _endpoint = saved);
      _snack(tr('Адрес контроллера сохранён.'));
    } catch (error) {
      _snack(tr('Не удалось сохранить: {error}', <String, Object?>{'error': error}));
    }
  }

  Future<void> _editBinary() async {
    final value = await showDialog<String>(
        context: context,
        builder: (_) => _TextPromptDialog(
            title: tr('Путь к Mihomo'),
            initial: _binary,
            hint: '/usr/local/bin/mihomo',
            helper: tr('Полный путь к исполняемому файлу Mihomo.')));
    if (value == null) return;
    try {
      await ref.read(mihomoProcessProvider).saveExecutable(value);
      if (mounted) setState(() => _binary = value.trim());
      _snack(tr('Путь к Mihomo сохранён.'));
    } catch (error) {
      _snack(tr('Не удалось сохранить: {error}', <String, Object?>{'error': error}));
    }
  }

  Future<void> _showLogs() {
    final manager = ref.read(mihomoProcessProvider);
    return showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(tr('Логи Mihomo')),
              content: SizedBox(
                  width: 560,
                  height: 320,
                  child: StreamBuilder<String>(
                      stream: manager.logs,
                      builder: (context, _) => SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                              manager.recentLogs.isEmpty
                                  ? tr('Логов пока нет. Они появятся при запуске или загрузке ядра.')
                                  : manager.recentLogs.join('\n'),
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: context.kago.muted))))),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Clipboard.setData(
                        ClipboardData(text: manager.recentLogs.join('\n'))),
                    child: Text(tr('Копировать'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Закрыть'))),
              ],
            ));
  }

  Future<void> _checkWindowsCore() async {
    setState(() {
      _coreUpdating = true;
      _windowsCoreStatus = tr('Проверяются и загружаются данные релиза Mihomo…');
    });
    try {
      final install = await ref.read(mihomoProcessProvider).updateCore();
      if (mounted) {
        setState(() => _windowsCoreStatus = install.note == null
            ? tr('Установлен Mihomo {version}.', <String, Object?>{'version': install.version})
            : tr('Установлен Mihomo {version}. Проверить обновление не удалось ({note}).', <String, Object?>{'version': install.version, 'note': install.note}));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _windowsCoreStatus = error is MihomoCoreNetworkException
            ? error.message
            : tr('Обновление не выполнено: {error}', <String, Object?>{'error': error}));
      }
    } finally {
      if (mounted) setState(() => _coreUpdating = false);
    }
  }
}

/// A titled card of rows separated by hairlines, like the FlClashX tools page.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Text(title,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                        color: context.kago.accent))),
            Material(
                color: context.kago.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: context.kago.border)),
                clipBehavior: Clip.antiAlias,
                child: Column(children: <Widget>[
                  for (var i = 0; i < children.length; i++) ...<Widget>[
                    if (i > 0)
                      Divider(
                          height: 1,
                          indent: 68,
                          endIndent: 16,
                          color: context.kago.border),
                    children[i],
                  ],
                ])),
          ]));
}

/// One settings row: tinted icon, title, optional subtitle, trailing control or
/// chevron. Rows without [onTap] are informational.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile(
      {required this.icon,
      required this.title,
      this.subtitle,
      this.subtitleWidget,
      this.trailing,
      this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final end = trailing ??
        (onTap != null
            ? Icon(Icons.chevron_right_rounded, color: context.kago.muted)
            : null);
    return InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: <Widget>[
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: context.kago.accentSoft,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 20, color: context.kago.accent)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                    if (subtitleWidget != null || subtitle != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: subtitleWidget ??
                              Text(subtitle!,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.kago.muted))),
                  ])),
              if (end != null)
                Padding(padding: const EdgeInsets.only(left: 8), child: end),
            ])));
  }
}

/// Single-field edit dialog that owns (and disposes) its controller.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog(
      {required this.title,
      required this.initial,
      required this.hint,
      required this.helper});
  final String title;
  final String initial;
  final String hint;
  final String helper;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
            width: 480,
            child: TextField(
                controller: _controller,
                autofocus: true,
                onSubmitted: (value) => Navigator.pop(context, value),
                decoration: InputDecoration(
                    hintText: widget.hint,
                    helperText: widget.helper,
                    helperMaxLines: 3))),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Отмена'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: Text(tr('Сохранить'))),
        ],
      );
}
