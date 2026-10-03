import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/android_vpn_events.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';
import '../subscriptions/config_builder.dart';
import '../subscriptions/subscription_providers.dart';
import '../subscriptions/subscription_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  static const _vpnChannel = MethodChannel('net.usekago.vpn/service');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(coreVersionProvider);
    final groups = ref.watch(proxyGroupsProvider);
    final profile = ref.watch(importedSubscriptionProvider);
    final coreRunning = ref.watch(desktopCoreRunningProvider);
    final androidVpn =
        Platform.isAndroid ? ref.watch(androidVpnEventProvider) : null;
    final androidCoreUpdate =
        Platform.isAndroid ? ref.watch(androidCoreUpdateStatusProvider) : null;
    final androidEvent = androidVpn?.asData?.value;
    final androidState = androidEvent?['state'] as String?;
    final androidConnected = androidState == 'connected';
    final width = MediaQuery.sizeOf(context).width;
    return ListView(
        padding: EdgeInsets.fromLTRB(
            width > 760 ? 44 : 20, 20, width > 760 ? 44 : 20, 28),
        children: <Widget>[
          Row(children: <Widget>[
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: KaGoColors.accent.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(15)),
                child: const Center(
                    child: Text('K',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            color: KaGoColors.accent)))),
            const SizedBox(width: 12),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Text('KaGo VPN',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                  Text('Интернет без границ',
                      style: TextStyle(color: KaGoColors.muted, fontSize: 12))
                ])),
            IconButton(
                tooltip: 'Обновить',
                onPressed: () {
                  ref.invalidate(coreVersionProvider);
                  ref.invalidate(proxyGroupsProvider);
                },
                icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 22),
          version.when(
              data: (value) => _StatusPill(
                  label: 'Контроллер Mihomo · $value', active: true),
              loading: () =>
                  const _StatusPill(label: 'Проверка Mihomo…', active: false),
              error: (_, __) => const _StatusPill(
                  label: 'Ядро не подключено', active: false)),
          if (androidCoreUpdate != null)
            androidCoreUpdate.when(
              data: (status) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(status,
                      style: const TextStyle(
                          fontSize: 11, color: KaGoColors.muted))),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          if (Platform.isAndroid) ...<Widget>[
            const SizedBox(height: 8),
            androidVpn!.when(
              data: (event) {
                final state = event['state'] as String? ?? 'disconnected';
                final message = event['message'] as String?;
                final label = message ??
                    switch (state) {
                      'starting' => 'Запуск Android VPN service…',
                      'connected' => 'Android VPN подключён',
                      'stopping' => 'Остановка VPN…',
                      'revoked' => 'Разрешение VPN отозвано',
                      'error' => 'Не удалось запустить Android VPN',
                      _ => 'Android VPN отключён',
                    };
                return _StatusPill(label: label, active: state == 'connected');
              },
              loading: () => const _StatusPill(
                  label: 'Android VPN отключён', active: false),
              error: (_, __) => const _StatusPill(
                  label: 'Android VPN service недоступен', active: false),
            ),
          ],
          const SizedBox(height: 20),
          _SubscriptionCard(
              profile: profile.value,
              onAdd: () => _showAddSubscription(context, ref)),
          const SizedBox(height: 16),
          SurfaceCard(
              onTap: () => ref.read(rootTabIndexProvider.notifier).state = 1,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                const SectionTitle('Ваш сервер',
                    trailing:
                        Icon(Icons.tune_rounded, color: KaGoColors.muted)),
                const SizedBox(height: 15),
                groups.when(
                  data: (items) {
                    final group = _primaryGroup(items);
                    final node = group?.selected;
                    return Row(children: <Widget>[
                      const Icon(Icons.public_rounded,
                          size: 34, color: KaGoColors.accent),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                            Text(node ?? group?.name ?? 'Добавьте подписку',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                node != null
                                    ? group!.name
                                    : group != null
                                        ? '${group.nodes.length} серверов · выбор доступен после подключения'
                                        : 'Список серверов появится здесь',
                                style: const TextStyle(
                                    fontSize: 12, color: KaGoColors.muted))
                          ])),
                      const Icon(Icons.chevron_right_rounded,
                          color: KaGoColors.muted),
                    ]);
                  },
                  loading: () => const LinearProgressIndicator(minHeight: 2),
                  error: (_, __) => Text(
                      !Platform.isAndroid && !coreRunning
                          ? 'Ядро не запущено. Нажмите кнопку питания ниже, чтобы запустить VPN.'
                          : 'Контроллер недоступен — проверьте адрес в настройках.',
                      style: const TextStyle(color: KaGoColors.muted)),
                ),
                const SizedBox(height: 14),
                Row(children: <Widget>[
                  const Icon(Icons.speed_rounded,
                      color: KaGoColors.accent, size: 18),
                  const SizedBox(width: 7),
                  Expanded(
                      child: Text(
                          _delayText(
                              groups.asData?.value,
                              ref.watch(proxyDelaysProvider),
                              coreRunning || androidConnected),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: KaGoColors.muted, fontSize: 12)))
                ]),
              ])),
          const SizedBox(height: 22),
          Center(
              child: Column(children: <Widget>[
            SizedBox(
                width: 194,
                height: 194,
                child: Stack(alignment: Alignment.center, children: <Widget>[
                  Container(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: KaGoColors.accent.withValues(alpha: .16),
                              width: 1))),
                  Container(
                      width: 152,
                      height: 152,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KaGoColors.accent.withValues(alpha: .07),
                          border: Border.all(
                              color:
                                  KaGoColors.accent.withValues(alpha: .25)))),
                  FilledButton(
                      onPressed: () =>
                          _tryConnect(context, ref, androidConnected),
                      style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(37),
                          backgroundColor: coreRunning || androidConnected
                              ? KaGoColors.danger
                              : KaGoColors.accent,
                          foregroundColor: const Color(0xFF071009)),
                      child: Icon(
                          coreRunning || androidConnected
                              ? Icons.stop_rounded
                              : Icons.power_settings_new_rounded,
                          size: 48)),
                ])),
            const SizedBox(height: 12),
            Text(
                coreRunning || androidConnected
                    ? 'Подключено'
                    : 'Не подключено',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            Text(
                coreRunning || androidConnected
                    ? 'Нажмите, чтобы отключить VPN'
                    : 'Нажмите, чтобы запустить VPN',
                style: const TextStyle(color: KaGoColors.muted, fontSize: 12)),
          ])),
          const SizedBox(height: 20),
          const SizedBox(height: 16),
          _IpCard(connected: coreRunning || androidConnected),
          const SizedBox(height: 20),
          _TrafficMetrics(active: coreRunning || androidConnected),
          const SizedBox(height: 18),
          const Center(
              child: Text('Поддержка: usekago.net',
                  style: TextStyle(color: KaGoColors.muted, fontSize: 12))),
        ]);
  }

  /// The proxy list and version are cached futures; without this they keep the
  /// old "controller unavailable" error after the core starts or stops.
  void _refreshCoreData(WidgetRef ref) {
    ref.invalidate(coreVersionProvider);
    ref.invalidate(proxyGroupsProvider);
  }

  Future<void> _tryConnect(
      BuildContext context, WidgetRef ref, bool androidConnected) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final manager = ref.read(mihomoProcessProvider);
      try {
        if (manager.isRunning) {
          await manager.stop();
          ref.read(desktopCoreRunningProvider.notifier).state = false;
          _refreshCoreData(ref);
          if (context.mounted) {
            _showMessage(context, 'Ядро Mihomo остановлено.');
          }
          return;
        }
        final config = await const MihomoConfigBuilder().activeConfigFile();
        await manager.start(configPath: config.path);
        ref.read(desktopCoreRunningProvider.notifier).state = true;
        _refreshCoreData(ref);
        if (context.mounted) {
          _showMessage(context, 'Mihomo запущен и controller отвечает.');
        }
      } catch (error) {
        ref.read(desktopCoreRunningProvider.notifier).state = manager.isRunning;
        _refreshCoreData(ref);
        if (context.mounted) {
          _showMessage(context, 'Не удалось запустить Mihomo: $error');
        }
      }
      return;
    }
    if (Platform.isAndroid) {
      try {
        if (androidConnected) {
          await _vpnChannel.invokeMethod<Map<dynamic, dynamic>>('disconnect');
          if (context.mounted) {
            _showMessage(context, 'Запрошено отключение Android VPN.');
          }
        } else {
          final config = await const MihomoConfigBuilder().activeConfigFile();
          if (!await config.exists()) {
            if (context.mounted) {
              _showMessage(context, 'Сначала добавьте YAML-подписку.');
            }
            return;
          }
          final controller = ref.read(mihomoControllerProvider);
          await const MihomoConfigBuilder().prepareAndroidTunnelConfig(
            config,
            endpoint: await controller.endpoint,
            secret: await controller.ensureSecret(),
          );
          await _vpnChannel.invokeMethod<Map<dynamic, dynamic>>(
              'connect', <String, String>{'configPath': config.path});
          if (context.mounted) {
            _showMessage(context,
                'Запуск VPN запрошен. Подтвердите системное разрешение Android.');
          }
        }
      } on MissingPluginException {
        if (context.mounted) {
          _showMessage(
              context, 'Android native bridge недоступен в этой сборке.');
        }
      } on PlatformException catch (error) {
        if (context.mounted) {
          _showMessage(context,
              error.message ?? 'Не удалось выполнить запрос Android VPN.');
        }
      } on FormatException catch (error) {
        if (context.mounted) _showMessage(context, error.message);
      } on FileSystemException catch (error) {
        if (context.mounted) {
          _showMessage(
              context, 'Не удалось подготовить профиль: ${error.message}');
        }
      }
      return;
    }
    try {
      await _vpnChannel.invokeMethod<void>('connect');
    } on MissingPluginException {
      if (context.mounted) {
        _showMessage(context,
            'Нативный VPN-мост ещё не подключён. REST-клиент Mihomo доступен после настройки контроллера.');
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showMessage(context, error.message ?? 'Не удалось запустить VPN.');
      }
    }
  }

  Future<void> _showAddSubscription(BuildContext context, WidgetRef ref) async {
    final input = TextEditingController();
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (dialogBuildContext, setDialogState) => AlertDialog(
                title: const Text('Добавить подписку'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                        controller: input,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            hintText: 'https://…',
                            labelText: 'Ссылка на конфигурацию')),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final value =
                                    (await Clipboard.getData(Clipboard.kTextPlain))
                                        ?.text
                                        ?.trim();
                                if (!dialogContext.mounted) return;
                                if (value == null || value.isEmpty) {
                                  _showMessage(
                                      dialogContext, 'Буфер обмена пуст.');
                                  return;
                                }
                                input.text = value;
                                input.selection = TextSelection.collapsed(
                                    offset: value.length);
                              },
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('Вставить из буфера'),
                      ),
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                      onPressed:
                          busy ? null : () => Navigator.of(dialogContext).pop(),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setDialogState(() => busy = true);
                              try {
                                final profile = await SubscriptionRepository()
                                    .import(input.text);
                                if (!dialogContext.mounted) return;
                                ref.invalidate(importedSubscriptionProvider);
                                Navigator.of(dialogContext).pop();
                                final desktop = Platform.isWindows ||
                                    Platform.isLinux ||
                                    Platform.isMacOS;
                                _showMessage(
                                    context,
                                    desktop
                                        ? 'Профиль «${profile.name}» сохранён. Встроенный Mihomo загрузится при первом подключении.'
                                        : 'Профиль «${profile.name}» сохранён. При подключении Android использует встроенное native Mihomo ядро.');
                              } catch (error) {
                                setDialogState(() => busy = false);
                                ScaffoldMessenger.of(dialogBuildContext)
                                    .showSnackBar(SnackBar(
                                        content: Text(
                                            'Не удалось добавить профиль: $error')));
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Загрузить')),
                ],
              )),
    );
    input.dispose();
  }

  void _showMessage(BuildContext context, String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.active});
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
          color: KaGoColors.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: KaGoColors.border)),
      child: Row(children: <Widget>[
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: active ? KaGoColors.accent : KaGoColors.warning,
                shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: KaGoColors.muted, fontSize: 12)))
      ]));
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.profile, required this.onAdd});
  final ImportedSubscription? profile;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => SurfaceCard(
          child: Row(children: <Widget>[
        Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: KaGoColors.accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14)),
            child:
                const Icon(Icons.data_usage_rounded, color: KaGoColors.accent)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
              Text(profile?.name ?? 'Подписка не добавлена',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  profile == null
                      ? 'Добавьте ссылку, чтобы увидеть трафик и срок'
                      : '${formatBytes(profile!.usedBytes)} использовано${profile!.totalBytes > 0 ? ' из ${formatBytes(profile!.totalBytes)}' : ''}',
                  style:
                      const TextStyle(fontSize: 12, color: KaGoColors.muted)),
              if (profile?.expiresAt != null)
                Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                        'Действует до ${profile!.expiresAt!.toLocal().toString().split(' ').first}',
                        style: const TextStyle(
                            fontSize: 11, color: KaGoColors.muted))),
            ])),
        TextButton(
            onPressed: onAdd,
            child: Text(profile == null ? 'Добавить' : 'Обновить')),
      ]));
}

/// The first config-order group that has a chosen node; GLOBAL is only a
/// fallback because it just mirrors the default route (usually DIRECT).
ProxyGroup? _primaryGroup(List<ProxyGroup> groups) {
  for (final group in groups) {
    if (group.name != 'GLOBAL' && group.selected != null) return group;
  }
  for (final group in groups) {
    if (group.selected != null) return group;
  }
  return groups.isEmpty ? null : groups.first;
}

String _delayText(
    List<ProxyGroup>? groups, Map<String, int> measured, bool online) {
  const idle = 'Задержка появится после подключения ядра';
  if (!online) return idle;
  final group = groups == null ? null : _primaryGroup(groups);
  final selected = group?.selected;
  if (group == null || selected == null) return idle;
  for (final node in group.nodes) {
    if (node.name != selected) continue;
    final value = measured[node.name] ?? node.delay;
    if (value == null) return 'Задержка не измерена — проверьте на вкладке «Серверы»';
    return value > 0 ? 'Задержка: $value мс' : 'Узел не отвечает';
  }
  return idle;
}

/// "Ваш IP": the address the internet currently sees, with country, city and
/// provider. Tap the eye to hide it for screenshots.
class _IpCard extends ConsumerWidget {
  const _IpCard({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ip = ref.watch(ipInfoProvider);
    final hidden = ref.watch(ipHiddenProvider);
    final info = ip.value;
    final loading = ip.isLoading;
    final failed = ip.hasError && info == null;
    final title = connected ? 'IP через VPN' : 'Ваш IP';
    final String address;
    if (info != null) {
      address = hidden ? '•••.•••.•••.•••' : info.ip;
    } else {
      address = failed ? 'Не определён' : 'Определяем…';
    }
    final details = <String>[
      if (info != null && info.place.isNotEmpty) info.place,
      if (info?.isp != null) info!.isp!,
    ].join(' · ');
    return SurfaceCard(
        child: Row(children: <Widget>[
      Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: KaGoColors.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: info != null && info.flag.isNotEmpty && !hidden
              ? Text(info.flag, style: const TextStyle(fontSize: 22))
              : const Icon(Icons.public_rounded, color: KaGoColors.accent)),
      const SizedBox(width: 12),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
            Text(title,
                style: const TextStyle(fontSize: 12, color: KaGoColors.muted)),
            const SizedBox(height: 3),
            SelectableText(address,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: failed ? KaGoColors.muted : KaGoColors.text)),
            if (details.isNotEmpty && !hidden)
              Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: KaGoColors.muted))),
          ])),
      IconButton(
          tooltip: hidden ? 'Показать IP' : 'Скрыть IP',
          onPressed: () => ref.read(ipHiddenProvider.notifier).state = !hidden,
          icon: Icon(
              hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: KaGoColors.muted)),
      loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : IconButton(
              tooltip: 'Проверить IP',
              onPressed: () => ref.invalidate(ipInfoProvider),
              icon: const Icon(Icons.refresh_rounded, color: KaGoColors.muted)),
    ]));
  }
}

/// Upload/download cards. Only this widget listens to the once-per-second
/// traffic poll, so the rest of the dashboard is not rebuilt every second, and
/// polling runs only while the dashboard tab is visible and a core is running.
class _TrafficMetrics extends ConsumerWidget {
  const _TrafficMetrics({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(rootTabIndexProvider) == 0;
    final traffic = active && visible
        ? ref.watch(connectionsSnapshotProvider).asData?.value
        : null;
    return RepaintBoundary(
        child: Row(children: <Widget>[
      Expanded(
          child: _MetricCard(
              icon: Icons.arrow_downward_rounded,
              label: 'Загрузка',
              value: traffic == null ? '—' : formatSpeed(traffic.downloadSpeed),
              caption: traffic == null
                  ? null
                  : 'всего ${formatBytes(traffic.downloadTotal)}')),
      const SizedBox(width: 12),
      Expanded(
          child: _MetricCard(
              icon: Icons.arrow_upward_rounded,
              label: 'Отдача',
              value: traffic == null ? '—' : formatSpeed(traffic.uploadSpeed),
              caption: traffic == null
                  ? null
                  : 'всего ${formatBytes(traffic.uploadTotal)}')),
    ]));
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.icon,
      required this.label,
      required this.value,
      this.caption});
  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  @override
  Widget build(BuildContext context) => SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: KaGoColors.accent, size: 19),
            const SizedBox(height: 9),
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(caption == null ? label : '$label · $caption',
                style: const TextStyle(fontSize: 11, color: KaGoColors.muted))
          ]));
}
