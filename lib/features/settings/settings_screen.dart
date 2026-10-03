import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_providers.dart';
import '../../core/network/mihomo_windows_core_updater.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';

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
            ? '${hz.round()} Гц · анимации и прокрутка на полной частоте'
            : 'Частота экрана не определена',
        style: const TextStyle(fontSize: 12, color: KaGoColors.muted));
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
  String _windowsCoreStatus = 'Проверяется…';

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
            ? 'Mihomo ещё не установлен: он скачается автоматически в %APPDATA%\\KaGo\\core.'
            : 'Установлен Mihomo ${core.version}.';
      });
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final coreRunning = ref.watch(desktopCoreRunningProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final androidUpdate =
        Platform.isAndroid ? ref.watch(androidCoreUpdateStatusProvider) : null;
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: <Widget>[
          const SectionTitle('Настройки'),
          const SizedBox(height: 18),
          _SettingsGroup(title: 'Внешний вид', children: <Widget>[
            _SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: 'Чисто чёрный фон',
                subtitle: 'Для OLED-дисплеев',
                trailing: Switch(
                    value: pureBlack,
                    activeThumbColor: KaGoColors.accent,
                    onChanged: (value) =>
                        ref.read(pureBlackProvider.notifier).state = value),
                onTap: () =>
                    ref.read(pureBlackProvider.notifier).state = !pureBlack),
            const _SettingsTile(
                icon: Icons.speed_rounded,
                title: 'Частота экрана',
                subtitleWidget: _RefreshRateLabel()),
          ]),
          _SettingsGroup(title: 'Подключение', children: <Widget>[
            _SettingsTile(
                icon: Icons.hub_outlined,
                title: 'Адрес контроллера',
                subtitle: _endpoint,
                onTap: _editEndpoint),
            const _SettingsTile(
                icon: Icons.vpn_key_outlined,
                title: 'Secret контроллера',
                subtitle:
                    'Создаётся автоматически и хранится в защищённом хранилище'),
            if (Platform.isWindows)
              const _SettingsTile(
                  icon: Icons.lan_outlined,
                  title: 'Режим подключения',
                  subtitle:
                      'Системный прокси Windows (127.0.0.1:7890). Работают приложения, которые используют его; это не полноценный TUN.'),
            if (!Platform.isAndroid && !Platform.isWindows)
              _SettingsTile(
                  icon: Icons.terminal_rounded,
                  title: 'Путь к Mihomo',
                  subtitle: _binary.isEmpty
                      ? 'Не задан. Укажите путь к бинарнику Mihomo.'
                      : _binary,
                  onTap: _editBinary),
          ]),
          _SettingsGroup(
              title: 'Ядро Mihomo',
              children: _coreTiles(coreRunning, androidUpdate)),
          _SettingsGroup(title: 'Диагностика', children: <Widget>[
            _SettingsTile(
                icon: Icons.receipt_long_outlined,
                title: 'Логи Mihomo',
                subtitle: 'Последние строки лога ядра и загрузки',
                onTap: _showLogs),
          ]),
          _SettingsGroup(title: 'О приложении', children: <Widget>[
            const _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Версия и сайт',
                subtitle: 'KaGo VPN · usekago.net · клиент на ядре Mihomo'),
            _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Лицензии',
                subtitle: 'Mihomo распространяется под GPL-3.0',
                onTap: () => showLicensePage(
                    context: context, applicationName: 'KaGo VPN')),
          ]),
        ]);
  }

  List<Widget> _coreTiles(bool coreRunning, AsyncValue<String>? androidUpdate) {
    if (Platform.isWindows) {
      return <Widget>[
        _SettingsTile(
            icon: Icons.memory_rounded,
            title: 'Mihomo · Windows x64',
            subtitle: coreRunning
                ? '$_windowsCoreStatus Остановите ядро, чтобы обновить.'
                : _windowsCoreStatus,
            trailing: _coreUpdating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.system_update_alt_rounded,
                    color: coreRunning ? KaGoColors.muted : KaGoColors.accent),
            onTap: _coreUpdating || coreRunning ? null : _checkWindowsCore),
        _SettingsTile(
            icon: Icons.folder_outlined,
            title: 'Папка ядра',
            subtitle: r'%APPDATA%\KaGo\core · нажмите, чтобы скопировать путь',
            onTap: () async {
              await Clipboard.setData(
                  const ClipboardData(text: r'%APPDATA%\KaGo\core'));
              _snack('Путь скопирован.');
            }),
        const _SettingsTile(
            icon: Icons.verified_user_outlined,
            title: 'Проверка и обновление',
            subtitle:
                'Автозагрузка с GitHub, проверка SHA-256 при установке и перед запуском, старые версии удаляются автоматически.'),
      ];
    }
    if (Platform.isAndroid) {
      final status = androidUpdate?.when(
              data: (value) => value,
              loading: () => 'Проверка версии встроенного Mihomo…',
              error: (error, _) =>
                  'Не удалось проверить upstream release: $error') ??
          '';
      return <Widget>[
        _SettingsTile(
            icon: Icons.memory_rounded,
            title: 'Mihomo · Android',
            subtitle: status,
            trailing:
                const Icon(Icons.refresh_rounded, color: KaGoColors.accent),
            onTap: () => ref.invalidate(androidCoreUpdateStatusProvider)),
        const _SettingsTile(
            icon: Icons.verified_user_outlined,
            title: 'Обновление ядра',
            subtitle:
                'Ядро поставляется внутри подписанного APK/AAB и обновляется вместе с приложением; удалённая подмена .so отключена.'),
      ];
    }
    return const <Widget>[
      _SettingsTile(
          icon: Icons.memory_rounded,
          title: 'Mihomo · внешний бинарник',
          subtitle:
              'На Linux/macOS пока нужен внешний Mihomo. Встроенное автообновление поддерживает Windows x64.'),
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
            title: 'Адрес контроллера',
            initial: _endpoint,
            hint: 'http://127.0.0.1:9090',
            helper:
                'HTTPS или локальный HTTP. Secret создаётся автоматически.'));
    if (value == null) return;
    try {
      final controller = ref.read(mihomoControllerProvider);
      await controller.saveSettings(endpoint: value);
      final saved = await controller.endpoint;
      ref.invalidate(coreVersionProvider);
      ref.invalidate(proxyGroupsProvider);
      ref.invalidate(connectionsSnapshotProvider);
      if (mounted) setState(() => _endpoint = saved);
      _snack('Адрес контроллера сохранён.');
    } catch (error) {
      _snack('Не удалось сохранить: $error');
    }
  }

  Future<void> _editBinary() async {
    final value = await showDialog<String>(
        context: context,
        builder: (_) => _TextPromptDialog(
            title: 'Путь к Mihomo',
            initial: _binary,
            hint: '/usr/local/bin/mihomo',
            helper: 'Полный путь к исполняемому файлу Mihomo.'));
    if (value == null) return;
    try {
      await ref.read(mihomoProcessProvider).saveExecutable(value);
      if (mounted) setState(() => _binary = value.trim());
      _snack('Путь к Mihomo сохранён.');
    } catch (error) {
      _snack('Не удалось сохранить: $error');
    }
  }

  Future<void> _showLogs() {
    final manager = ref.read(mihomoProcessProvider);
    return showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Логи Mihomo'),
              content: SizedBox(
                  width: 560,
                  height: 320,
                  child: StreamBuilder<String>(
                      stream: manager.logs,
                      builder: (context, _) => SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                              manager.recentLogs.isEmpty
                                  ? 'Логов пока нет. Они появятся при запуске или загрузке ядра.'
                                  : manager.recentLogs.join('\n'),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: KaGoColors.muted))))),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Clipboard.setData(
                        ClipboardData(text: manager.recentLogs.join('\n'))),
                    child: const Text('Копировать')),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Закрыть')),
              ],
            ));
  }

  Future<void> _checkWindowsCore() async {
    setState(() {
      _coreUpdating = true;
      _windowsCoreStatus = 'Проверяются и загружаются данные релиза Mihomo…';
    });
    try {
      final install = await ref.read(mihomoProcessProvider).updateCore();
      if (mounted) {
        setState(
            () => _windowsCoreStatus = 'Установлен Mihomo ${install.version}.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _windowsCoreStatus = error is MihomoCoreNetworkException
            ? error.message
            : 'Обновление не выполнено: $error');
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
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                        color: KaGoColors.accent))),
            Material(
                color: KaGoColors.surface,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: Column(children: <Widget>[
                  for (var i = 0; i < children.length; i++) ...<Widget>[
                    if (i > 0)
                      const Divider(
                          height: 1,
                          indent: 68,
                          endIndent: 16,
                          color: KaGoColors.border),
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
            ? const Icon(Icons.chevron_right_rounded, color: KaGoColors.muted)
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
                      color: KaGoColors.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 20, color: KaGoColors.accent)),
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
                                  style: const TextStyle(
                                      fontSize: 12, color: KaGoColors.muted))),
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
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: const Text('Сохранить')),
        ],
      );
}
