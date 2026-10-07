import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/device/device_identity.dart';
import '../../core/network/anonymous_mode.dart';
import '../../core/network/app_providers.dart';
import '../../core/network/mihomo_macos.dart';
import '../../core/network/mihomo_windows_core_updater.dart';
import '../../core/network/mihomo_windows_system_proxy.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/appearance.dart';
import '../../core/theme/kago_theme.dart';
import '../../core/update/app_updater.dart';
import '../dashboard/dashboard_screen.dart';
import '../guest/guest_telegram.dart';
import '../subscriptions/russian_rules.dart';
import '../update/update_flow.dart';
import 'app_routing_screen.dart';
import '../../core/l10n/l10n.dart';

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
  bool _bypassRussian = false;
  bool _macTun = true;

  /// Technical rows (core, logs, controller) stay folded away by default.
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS) {
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted) return;
        setState(() {
          _bypassRussian =
              prefs.getBool(MihomoWindowsSystemProxy.bypassRussianKey) ?? false;
          _macTun = prefs.getBool(MihomoMacosCore.tunKey) ?? true;
        });
      }).catchError((Object _) {});
    }
    final manager = ref.read(mihomoProcessProvider);
    ref.read(mihomoControllerProvider).endpoint.then((value) async {
      final binary = await manager.executable;
      final core = await manager.installedCore();
      if (!mounted) return;
      setState(() {
        _endpoint = value;
        _binary = binary ?? '';
        _windowsCoreStatus = core == null
            ? tr(
                'Mihomo ещё не установлен: он скачается автоматически в %APPDATA%\\KaGo\\core.')
            : tr('Установлен Mihomo {version}.',
                <String, Object?>{'version': core.version});
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
                          value: ThemeMode.system, label: Text(tr('Авто'))),
                      ButtonSegment(
                          value: ThemeMode.light, label: Text(tr('Светлая'))),
                      ButtonSegment(
                          value: ThemeMode.dark, label: Text(tr('Тёмная'))),
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
          ]),
          _SettingsGroup(
              title: tr('Подключение'), children: _connectionTiles()),
          _SettingsGroup(title: tr('Дополнительно'), children: <Widget>[
            _SettingsTile(
                icon: Icons.build_outlined,
                title: tr('Для опытных пользователей'),
                subtitle: tr('Ядро, логи и адрес контроллера'),
                trailing: AnimatedRotation(
                    turns: _advanced ? .5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded,
                        color: context.kago.muted)),
                onTap: () => setState(() => _advanced = !_advanced)),
            if (_advanced) ...<Widget>[
              ..._coreTiles(coreRunning, androidUpdate),
              _SettingsTile(
                  icon: Icons.receipt_long_outlined,
                  title: tr('Логи Mihomo'),
                  onTap: _showLogs),
              _SettingsTile(
                  icon: Icons.hub_outlined,
                  title: tr('Адрес контроллера'),
                  subtitle: _endpoint,
                  onTap: _editEndpoint),
              if (Platform.isLinux)
                _SettingsTile(
                    icon: Icons.terminal_rounded,
                    title: tr('Путь к Mihomo'),
                    subtitle: _binary.isEmpty
                        ? tr('Не задан. Укажите путь к бинарнику Mihomo.')
                        : _binary,
                    onTap: _editBinary),
            ],
          ]),
          _SettingsGroup(title: tr('О приложении'), children: <Widget>[
            if (AppUpdater.supported) _updateTile(),
            _SettingsTile(
                icon: Icons.language_rounded,
                title: 'KaGo VPN',
                subtitle: tr('Версия {version} · usekago.net',
                    <String, Object?>{'version': kagoAppVersion}),
                trailing: Icon(Icons.open_in_new_rounded,
                    size: 20, color: context.kago.muted),
                onTap: () => launchUrl(Uri.parse('https://usekago.net'),
                    mode: LaunchMode.externalApplication)),
            _SettingsTile(
                icon: Icons.description_outlined,
                title: tr('Лицензии'),
                onTap: () => showLicensePage(
                    context: context, applicationName: 'KaGo VPN')),
          ]),
        ]);
  }

  Widget _updateTile() {
    final update = ref.watch(appUpdateProvider);
    final release = update.valueOrNull;
    return _SettingsTile(
        icon: Icons.system_update_rounded,
        title: tr('Обновления'),
        subtitle: update.isLoading
            ? tr('Проверка…')
            : release != null
                ? tr('Доступна версия {version} — нажмите, чтобы обновить',
                    <String, Object?>{'version': release.version})
                : update.hasError
                    ? tr('Не удалось проверить. Нажмите, чтобы повторить.')
                    : tr('Установлена последняя версия'),
        trailing: release != null
            ? Icon(Icons.download_rounded, color: context.kago.accent)
            : null,
        onTap: release != null
            ? () => showUpdateDialog(context, release)
            : () => ref.invalidate(appUpdateProvider));
  }

  List<Widget> _connectionTiles() => <Widget>[
        _anonymousTile(),
        if (Platform.isAndroid) ...<Widget>[
          _SettingsTile(
              icon: Icons.apps_rounded,
              title: tr('Приложения без VPN'),
              subtitle: tr('Например, Яндекс Музыка, VK и банки'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AppRoutingScreen()))),
          _SettingsTile(
              icon: Icons.shield_outlined,
              title: tr('Блокировать интернет без VPN'),
              subtitle: tr('Включается в системных настройках VPN'),
              trailing: Icon(Icons.open_in_new_rounded,
                  size: 20, color: context.kago.muted),
              onTap: _openVpnSettings),
        ],
        if (Platform.isMacOS)
          _SettingsTile(
              icon: Icons.vpn_lock_rounded,
              title: tr('Весь трафик через VPN'),
              subtitle: tr(
                  'Для Telegram и приложений, которые не используют системный прокси. Один раз спросит пароль администратора.'),
              trailing: Switch(value: _macTun, onChanged: _setMacTun),
              onTap: () => _setMacTun(!_macTun)),
        // Hidden when the subscription routes Russian sites itself.
        if ((Platform.isWindows || Platform.isMacOS) &&
            ref.watch(subscriptionRoutesRussiaProvider).valueOrNull != true)
          _SettingsTile(
              icon: Icons.alt_route_rounded,
              title: tr('Российские сайты — напрямую'),
              subtitle: tr('Яндекс, VK, банки и Госуслуги — без VPN'),
              trailing:
                  Switch(value: _bypassRussian, onChanged: _setBypassRussian),
              onTap: () => _setBypassRussian(!_bypassRussian)),
        if (Platform.isLinux)
          _SettingsTile(
              icon: Icons.lan_outlined,
              title: tr('Режим подключения'),
              subtitle: tr('Системный прокси 127.0.0.1:7890')),
      ];

  Future<void> _openVpnSettings() async {
    var opened = false;
    try {
      opened = await const MethodChannel('net.usekago.app/service')
              .invokeMethod<bool>('openVpnSettings') ??
          false;
    } on MissingPluginException {
      opened = false;
    } on PlatformException {
      opened = false;
    }
    if (!opened) {
      _snack(tr(
          'Откройте «Настройки → Сеть → VPN» и включите для KaGo VPN «Постоянная VPN».'));
    }
  }

  List<Widget> _coreTiles(bool coreRunning, AsyncValue<String>? androidUpdate) {
    if (Platform.isWindows) {
      return <Widget>[
        _SettingsTile(
            icon: Icons.memory_rounded,
            title: 'Mihomo · Windows x64',
            subtitle: coreRunning
                ? tr('{windowsCoreStatus} Остановите ядро, чтобы обновить.',
                    <String, Object?>{'windowsCoreStatus': _windowsCoreStatus})
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
      ];
    }
    if (Platform.isAndroid) {
      final status = androidUpdate?.when(
              data: (value) => value,
              loading: () => tr('Проверка версии встроенного Mihomo…'),
              error: (error, _) => tr(
                  'Не удалось проверить upstream release: {error}',
                  <String, Object?>{'error': error})) ??
          '';
      return <Widget>[
        _SettingsTile(
            icon: Icons.memory_rounded,
            title: 'Mihomo · Android',
            subtitle: status,
            trailing: Icon(Icons.refresh_rounded, color: context.kago.accent),
            onTap: () => ref.invalidate(androidCoreUpdateStatusProvider)),
      ];
    }
    if (Platform.isMacOS) {
      return <Widget>[
        _SettingsTile(
            icon: Icons.memory_rounded,
            title: 'Mihomo · macOS',
            subtitle: tr(
                'Встроено в приложение: {version}. Обновляется вместе с KaGo VPN.',
                <String, Object?>{'version': MihomoPinnedCore.version})),
      ];
    }
    return <Widget>[
      _SettingsTile(
          icon: Icons.memory_rounded,
          title: tr('Mihomo · внешний бинарник'),
          subtitle: tr(
              'На Linux пока нужен внешний Mihomo. Встроенное ядро есть в версиях для Windows, macOS и Android.')),
    ];
  }

  /// Two connection profiles: "Normal" (the subscription as is) and
  /// "Anonymous" (AnonymousMode).
  Widget _anonymousTile() {
    final anonymous = ref.watch(anonymousModeProvider).valueOrNull ?? false;
    return _SettingsTile(
        icon: Icons.privacy_tip_outlined,
        title: tr('Анонимный режим'),
        subtitle: anonymous
            ? (Platform.isWindows
                ? tr(
                    'DNS только через VPN, без IPv6, часовой пояс как у сервера. Выключите — обычный режим.')
                : tr(
                    'DNS только через VPN, без IPv6. Выключите — обычный режим.'))
            : tr(
                'Обычный режим: подписка как есть. Включите, чтобы скрыть признаки VPN.'),
        trailing: Switch(value: anonymous, onChanged: _setAnonymous),
        onTap: () => _setAnonymous(!anonymous));
  }

  Future<void> _setAnonymous(bool value) async {
    await AnonymousMode.setEnabled(value);
    ref.invalidate(anonymousModeProvider);
    if (!mounted) return;
    // A running connection switches to the chosen profile right away.
    if (ref.read(vpnActiveProvider) && !ref.read(guestModeActiveProvider)) {
      await DashboardScreen.toggleVpn(context, ref, true);
      if (!await DashboardScreen.waitForVpn(ref, false,
              timeout: const Duration(seconds: 8)) ||
          !mounted) {
        return;
      }
      await DashboardScreen.toggleVpn(context, ref, false);
    }
  }

  Future<void> _setBypassRussian(bool value) async {
    setState(() => _bypassRussian = value);
    try {
      if (Platform.isMacOS) {
        await MihomoMacosSystemProxy().setBypassRussian(value);
      } else {
        await MihomoWindowsSystemProxy().setBypassRussian(value);
      }
    } catch (error) {
      _snack(tr(
          'Не удалось сохранить: {error}', <String, Object?>{'error': error}));
    }
  }

  Future<void> _setMacTun(bool value) async {
    setState(() => _macTun = value);
    try {
      await MihomoMacosCore.setTunEnabled(value);
      if (value && await MihomoMacosCore.authorizedHelper() == null) {
        final error = await MihomoMacosCore.authorize();
        if (error != null) {
          await MihomoMacosCore.setTunEnabled(false);
          if (mounted) setState(() => _macTun = false);
          _snack(tr('Не включено: {error}', <String, Object?>{'error': error}));
          return;
        }
      }
      if (ref.read(desktopCoreRunningProvider)) {
        _snack(tr('Переподключитесь, чтобы применить.'));
      }
    } catch (error) {
      _snack(tr(
          'Не удалось сохранить: {error}', <String, Object?>{'error': error}));
    }
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
            helper: tr(
                'HTTPS или локальный HTTP. Secret создаётся автоматически.')));
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
      _snack(tr(
          'Не удалось сохранить: {error}', <String, Object?>{'error': error}));
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
      _snack(tr(
          'Не удалось сохранить: {error}', <String, Object?>{'error': error}));
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
                                  ? tr(
                                      'Логов пока нет. Они появятся при запуске или загрузке ядра.')
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
      _windowsCoreStatus =
          tr('Проверяются и загружаются данные релиза Mihomo…');
    });
    try {
      final install = await ref.read(mihomoProcessProvider).updateCore();
      if (mounted) {
        setState(() => _windowsCoreStatus = install.note == null
            ? tr('Установлен Mihomo {version}.',
                <String, Object?>{'version': install.version})
            : tr(
                'Установлен Mihomo {version}. Проверить обновление не удалось ({note}).',
                <String, Object?>{
                    'version': install.version,
                    'note': install.note
                  }));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _windowsCoreStatus = error is MihomoCoreNetworkException
            ? error.message
            : tr('Обновление не выполнено: {error}',
                <String, Object?>{'error': error}));
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
