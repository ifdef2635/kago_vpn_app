import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_providers.dart';
import '../../core/network/mihomo_windows_core_updater.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _endpoint = TextEditingController(text: 'http://127.0.0.1:9090');
  final _binary = TextEditingController();
  bool _loading = true;
  bool _coreUpdating = false;
  String _windowsCoreStatus = 'Ядро будет загружено при первом подключении.';

  @override
  void initState() {
    super.initState();
    final manager = ref.read(mihomoProcessProvider);
    ref.read(mihomoControllerProvider).endpoint.then((value) async {
      final binary = await manager.executable;
      final core = await manager.installedCore();
      if (!mounted) return;
      setState(() {
        _endpoint.text = value;
        _binary.text = binary ?? '';
        _windowsCoreStatus = core == null
            ? 'Mihomo ещё не установлен: он скачается автоматически в %APPDATA%\\KaGo\\core.'
            : 'Установлен Mihomo ${core.version}.';
        _loading = false;
      });
    }).catchError((Object _) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _binary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(mihomoProcessProvider);
    final coreRunning = ref.watch(desktopCoreRunningProvider);
    final androidUpdate =
        Platform.isAndroid ? ref.watch(androidCoreUpdateStatusProvider) : null;
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: <Widget>[
          const SectionTitle('Настройки'),
          const SizedBox(height: 6),
          const Text('KaGo VPN · usekago.net',
              style: TextStyle(color: KaGoColors.muted, fontSize: 13)),
          const SizedBox(height: 20),
          SurfaceCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                const Text('Контроллер Mihomo',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 7),
                const Text(
                    'Удалённый controller должен использовать HTTPS. HTTP разрешён только для localhost/127.0.0.1. Secret создаётся автоматически и хранится в защищённом хранилище.',
                    style: TextStyle(fontSize: 12, color: KaGoColors.muted)),
                const SizedBox(height: 16),
                TextField(
                    controller: _endpoint,
                    enabled: !_loading,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: 'HTTPS или локальный HTTP адрес',
                        hintText: 'http://127.0.0.1:9090',
                        prefixIcon: Icon(Icons.link_rounded))),
                // Windows uses the managed core in %APPDATA%\KaGo; Android ships
                // its own. Only Linux/macOS still need a manual path.
                if (!Platform.isAndroid && !Platform.isWindows) ...<Widget>[
                  const SizedBox(height: 12),
                  TextField(
                      controller: _binary,
                      enabled: !_loading,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                          labelText:
                              'Путь к Mihomo (необязательное переопределение)',
                          hintText: r'C:\KaGo\mihomo.exe',
                          prefixIcon: Icon(Icons.terminal_rounded))),
                  const SizedBox(height: 6),
                  const Text(
                      'На этой платформе укажите путь к бинарнику Mihomo.',
                      style: TextStyle(fontSize: 11, color: KaGoColors.muted)),
                ],
                const SizedBox(height: 15),
                FilledButton.icon(
                    onPressed: _loading ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Сохранить настройки')),
              ])),
          const SizedBox(height: 14),
          SurfaceCard(
              child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Чисто черный фон'),
                  subtitle: const Text('Для OLED-дисплеев',
                      style: TextStyle(color: KaGoColors.muted)),
                  value: ref.watch(pureBlackProvider),
                  activeThumbColor: KaGoColors.accent,
                  onChanged: (value) =>
                      ref.read(pureBlackProvider.notifier).state = value)),
          const SizedBox(height: 14),
          if (Platform.isWindows) ...<Widget>[
            SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  const Text('Встроенный Mihomo · Windows x64',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(_windowsCoreStatus,
                      style: const TextStyle(
                          color: KaGoColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text(
                      'Перед подключением проверяется официальный GitHub release, ZIP сверяется с SHA-256 digest из GitHub API, а бинарь проходит запуск -v. При недоступности сети остаётся последняя установленная версия.',
                      style: TextStyle(color: KaGoColors.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  const Text(
                      'Windows connection mode: mixed-port Mihomo + reversible user-level system proxy. Работают приложения, которые используют proxy settings Windows; это не full-device Wintun TUN.',
                      style: TextStyle(color: KaGoColors.muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed:
                        _coreUpdating || coreRunning ? null : _checkWindowsCore,
                    icon: _coreUpdating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.system_update_alt_rounded),
                    label: Text(coreRunning
                        ? 'Остановите ядро для обновления'
                        : 'Проверить и установить обновление'),
                  ),
                ])),
          ] else if (Platform.isAndroid) ...<Widget>[
            SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  const Text('Встроенный Mihomo · Android',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  androidUpdate!.when(
                    data: (status) => Text(status,
                        style: const TextStyle(
                            color: KaGoColors.muted, fontSize: 12)),
                    loading: () => const Text(
                        'Проверка версии встроенного Mihomo…',
                        style:
                            TextStyle(color: KaGoColors.muted, fontSize: 12)),
                    error: (error, _) => Text(
                        'Не удалось проверить upstream release: $error',
                        style: const TextStyle(
                            color: KaGoColors.muted, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Android core поставляется внутри подписанного APK/AAB. Обновление ядра выполняется вместе с обновлением KaGo VPN через выбранный канал распространения; удалённая подмена .so отключена.',
                      style: TextStyle(color: KaGoColors.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                      onPressed: () =>
                          ref.invalidate(androidCoreUpdateStatusProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Проверить версию Mihomo')),
                ])),
          ] else ...<Widget>[
            const SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Text('Desktop core',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text(
                      'На Linux/macOS пока требуется внешний Mihomo binary. Встроенное автообновление поддерживает Windows x64. Windows сейчас маршрутизирует приложения через системный proxy; full-device TUN/Wintun ещё не включён.',
                      style: TextStyle(color: KaGoColors.muted, fontSize: 12)),
                ])),
          ],
          if (coreRunning) ...<Widget>[
            const SizedBox(height: 14),
            SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  const Text('Логи Mihomo',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  StreamBuilder<String>(
                    stream: manager.logs,
                    initialData: manager.recentLogs.isEmpty
                        ? 'Ожидание логов ядра…'
                        : manager.recentLogs.last,
                    builder: (context, snapshot) => ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            manager.recentLogs.isEmpty
                                ? snapshot.data ?? 'Ожидание логов ядра…'
                                : manager.recentLogs.join('\n'),
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: KaGoColors.muted),
                          )),
                    ),
                  ),
                ])),
          ],
        ]);
  }

  Future<void> _save() async {
    try {
      await ref
          .read(mihomoControllerProvider)
          .saveSettings(endpoint: _endpoint.text);
      if (!Platform.isAndroid && !Platform.isWindows) {
        await ref.read(mihomoProcessProvider).saveExecutable(_binary.text);
      }
      ref.invalidate(coreVersionProvider);
      ref.invalidate(proxyGroupsProvider);
      ref.invalidate(connectionsSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Настройки сохранены.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось сохранить: $error')));
      }
    }
  }

  Future<void> _checkWindowsCore() async {
    setState(() {
      _coreUpdating = true;
      _windowsCoreStatus =
          'Загружаются и проверяются release metadata и Mihomo binary…';
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
