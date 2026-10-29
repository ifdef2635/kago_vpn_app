import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/device/device_identity.dart';
import '../../core/network/android_battery.dart';
import '../../core/network/anonymous_mode.dart';
import '../../core/network/app_providers.dart';
import '../../core/network/mihomo_macos.dart';
import '../../core/network/mihomo_windows_system_proxy.dart';
import '../../core/network/mihomo_windows_tun.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/appearance.dart';
import '../../core/theme/kago_theme.dart';
import '../../core/update/app_updater.dart';
import '../connections/connections_screen.dart';
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
  bool _bypassRussian = false;
  bool _macTun = true;
  bool _windowsTun = true;
  bool _restarting = false;

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
          _windowsTun = prefs.getBool(MihomoWindowsTun.tunKey) ?? true;
        });
      }).catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider);
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
          _SettingsGroup(title: tr('Инструменты'), children: <Widget>[
            _SettingsTile(
                icon: Icons.swap_horiz_rounded,
                title: tr('Соединения'),
                subtitle: tr('Какие сайты и приложения сейчас идут через ядро'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const ConnectionsScreen()))),
            _SettingsTile(
                icon: Icons.receipt_long_outlined,
                title: tr('Логи Mihomo'),
                onTap: _showLogs),
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
          _SettingsGroup(
              title: tr('Ядро'), children: <Widget>[_restartCoreTile()]),
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
          _batteryTile(),
        ],
        if (Platform.isMacOS)
          _SettingsTile(
              icon: Icons.vpn_lock_rounded,
              title: tr('Весь трафик через VPN'),
              subtitle: tr(
                  'Для Telegram и приложений, которые не используют системный прокси. Один раз спросит пароль администратора.'),
              trailing: Switch(value: _macTun, onChanged: _setMacTun),
              onTap: () => _setMacTun(!_macTun)),
        if (Platform.isWindows)
          _SettingsTile(
              icon: Icons.vpn_lock_rounded,
              title: tr('Весь трафик через VPN (TUN)'),
              subtitle: tr(
                  'Для Discord, звонков, игр и программ без системного прокси. Windows один раз спросит разрешение администратора.'),
              trailing: Switch(value: _windowsTun, onChanged: _setWindowsTun),
              onTap: () => _setWindowsTun(!_windowsTun)),
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

  /// Battery optimization (Android): asked once at the first connection,
  /// changed here later.
  Widget _batteryTile() {
    final free = ref.watch(androidBatteryUnrestrictedProvider).valueOrNull;
    return _SettingsTile(
        icon: Icons.battery_saver_outlined,
        title: tr('Работа в фоне'),
        subtitle: free == false
            ? tr(
                'Android может остановить VPN в фоне. Нажмите и разрешите работу без ограничений.')
            : tr('Без ограничений батареи: Android не останавливает VPN'),
        trailing: free == false
            ? Icon(Icons.warning_amber_rounded, color: context.kago.warning)
            : Icon(Icons.open_in_new_rounded,
                size: 20, color: context.kago.muted),
        onTap: AndroidBattery.request);
  }

  /// The last row, as in FlClashX: restarts the running core (stop, then
  /// start with the saved profile).
  Widget _restartCoreTile() {
    final running = ref.watch(vpnActiveProvider);
    final p = context.kago;
    final (color, label) = _restarting
        ? (p.warning, tr('Перезапуск…'))
        : running
            ? (p.success, tr('Работает'))
            : (p.hint, tr('Остановлено'));
    return _SettingsTile(
        icon: Icons.memory_rounded,
        title: tr('Перезапустить ядро'),
        subtitleWidget: Row(children: <Widget>[
          StatusDot(color: color, size: 8),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
        trailing: _restarting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.restart_alt_rounded,
                color: running ? p.accent : p.hint),
        onTap: running && !_restarting ? _restartCore : null);
  }

  Future<void> _restartCore() async {
    setState(() => _restarting = true);
    try {
      await DashboardScreen.reconnect(context, ref);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

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
      _error(tr('Не удалось открыть настройки VPN.'),
          details: tr(
              'Откройте «Настройки → Сеть → VPN» и включите для KaGo VPN «Постоянная VPN».'));
    }
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
        // TUN has no system proxy: its rules change with a restart.
        if (ref.read(mihomoProcessProvider).allTraffic) await _reconnect();
      }
    } catch (error) {
      _error(tr('Не удалось сохранить.'), details: '$error');
    }
  }

  Future<void> _setWindowsTun(bool value) async {
    setState(() => _windowsTun = value);
    await MihomoWindowsTun.setEnabled(value);
    await _reconnect();
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
          _error(tr('Режим не включён.'), details: error);
          return;
        }
      }
      await _reconnect();
    } catch (error) {
      _error(tr('Не удалось сохранить.'), details: '$error');
    }
  }

  /// A running VPN picks up the new mode right away (instead of asking the
  /// user to reconnect).
  Future<void> _reconnect() async {
    if (!mounted || !ref.read(desktopCoreRunningProvider)) return;
    await DashboardScreen.reconnect(context, ref);
  }

  /// Critical errors only (CLAUDE.md): successes are not announced.
  void _error(String text, {String? details}) {
    if (!mounted) return;
    showCriticalError(context, text, details: details);
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
                child: Text(title.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: KaGoWeight.extraBold,
                        letterSpacing: .8,
                        color: context.kago.accent))),
            DecoratedBox(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(KaGoRadius.lg),
                    boxShadow: Theme.of(context).brightness == Brightness.light
                        ? context.kagoCardShadow
                        : null),
                child: Material(
                    color: context.kago.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KaGoRadius.lg),
                        side: BorderSide(color: context.kago.border)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: <Widget>[
                      for (var i = 0; i < children.length; i++) ...<Widget>[
                        if (i > 0)
                          Divider(
                              height: 1,
                              indent: 72,
                              endIndent: 16,
                              color: context.kago.borderLight),
                        children[i],
                      ],
                    ]))),
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
            ? Icon(Icons.chevron_right_rounded, color: context.kago.hint)
            : null);
    return InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: <Widget>[
              IconChip(icon),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(title,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: KaGoWeight.bold,
                            color: context.kago.text)),
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
