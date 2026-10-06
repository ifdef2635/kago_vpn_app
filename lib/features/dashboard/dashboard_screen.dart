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
import '../../core/l10n/l10n.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  static const _vpnChannel = MethodChannel('net.usekago.app/service');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(proxyGroupsProvider);
    final profile = ref.watch(importedSubscriptionProvider);
    final coreRunning = ref.watch(desktopCoreRunningProvider);
    final androidVpn =
        Platform.isAndroid ? ref.watch(androidVpnEventProvider) : null;
    final androidEvent = androidVpn?.asData?.value;
    final androidState = androidEvent?['state'] as String?;
    final androidConnected = androidState == 'connected';
    final connected = coreRunning || androidConnected;
    final starting = androidState == 'starting';
    // Only problems are worth a line on the main screen.
    final problem = switch (androidState) {
      'error' => androidEvent?['message'] as String? ??
          tr('Не удалось запустить Android VPN'),
      'revoked' => tr('Разрешение VPN отозвано'),
      _ => null,
    };
    final p = context.kago;
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 760 ? 44.0 : 16.0;
    return ListView(
        padding: EdgeInsets.fromLTRB(side, 12, side, 16),
        children: <Widget>[
          Row(children: <Widget>[
            const KagoLogo(size: 36),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  const Text('KaGo VPN',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(tr('Интернет без границ'),
                      style: TextStyle(color: p.muted, fontSize: 12))
                ])),
            IconButton(
                tooltip: tr('Обновить'),
                onPressed: () {
                  ref.invalidate(coreVersionProvider);
                  ref.invalidate(proxyGroupsProvider);
                  ref.invalidate(ipInfoProvider);
                },
                icon: const Icon(Icons.refresh_rounded)),
          ]),
          if (problem != null) ...<Widget>[
            const SizedBox(height: 8),
            _StatusPill(label: problem, active: false),
          ],
          const SizedBox(height: 10),
          _SubscriptionCard(
              profile: profile.value,
              onAdd: () => showAddSubscription(context, ref)),
          const SizedBox(height: 10),
          SurfaceCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              onTap: () => ref.read(rootTabIndexProvider.notifier).state = 1,
              child: groups.when(
                data: (items) {
                  final group = _primaryGroup(items);
                  final node = group?.selected;
                  final delay = _delayText(
                      items, ref.watch(proxyDelaysProvider), connected);
                  return Row(children: <Widget>[
                    const _CardIcon(icon: Icons.public_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                          Text(tr('Ваш сервер'),
                              style: TextStyle(fontSize: 12, color: p.muted)),
                          const SizedBox(height: 2),
                          Text(node ?? group?.name ?? tr('Добавьте подписку'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          if (group != null)
                            Text(
                                node != null
                                    ? (delay == null
                                        ? group.name
                                        : '${group.name} · $delay')
                                    : tr('{length} серверов', <String, Object?>{
                                        'length': group.nodes.length
                                      }),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: p.muted)),
                        ])),
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                  ]);
                },
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, __) => Text(
                    !Platform.isAndroid && !coreRunning
                        ? tr(
                            'Ядро не запущено. Нажмите кнопку питания ниже, чтобы запустить VPN.')
                        : tr(
                            'Контроллер недоступен — проверьте адрес в настройках.'),
                    style: TextStyle(color: p.muted, fontSize: 12)),
              )),
          const SizedBox(height: 18),
          Center(
              child: _PowerButton(
                  connected: connected,
                  busy: starting,
                  onPressed: () => toggleVpn(context, ref, androidConnected))),
          const SizedBox(height: 10),
          Text(
              starting
                  ? tr('Подключение…')
                  : connected
                      ? tr('Подключено')
                      : tr('Не подключено'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 18),
          _IpCard(connected: connected),
          const SizedBox(height: 10),
          _TrafficMetrics(active: connected),
        ]);
  }

  /// The proxy list and version are cached futures; without this they keep the
  /// old "controller unavailable" error after the core starts or stops.
  static void _refreshCoreData(WidgetRef ref) {
    ref.invalidate(coreVersionProvider);
    ref.invalidate(proxyGroupsProvider);
  }

  /// Starts or stops the VPN (desktop core or Android service). Also used by
  /// the personal account screen.
  static Future<void> toggleVpn(
      BuildContext context, WidgetRef ref, bool androidConnected) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final manager = ref.read(mihomoProcessProvider);
      try {
        if (manager.isRunning) {
          await manager.stop();
          ref.read(desktopCoreRunningProvider.notifier).state = false;
          _refreshCoreData(ref);
          if (context.mounted) {
            _showMessage(context, tr('Ядро Mihomo остановлено.'));
          }
          return;
        }
        final config = await const MihomoConfigBuilder().activeConfigFile();
        await manager.start(configPath: config.path);
        ref.read(desktopCoreRunningProvider.notifier).state = true;
        _refreshCoreData(ref);
        if (context.mounted) {
          _showMessage(context, tr('Mihomo запущен и controller отвечает.'));
        }
      } catch (error) {
        ref.read(desktopCoreRunningProvider.notifier).state = manager.isRunning;
        _refreshCoreData(ref);
        if (context.mounted) {
          _showMessage(
              context,
              tr('Не удалось запустить Mihomo: {error}',
                  <String, Object?>{'error': error}));
        }
      }
      return;
    }
    if (Platform.isAndroid) {
      try {
        if (androidConnected) {
          await _vpnChannel.invokeMethod<Map<dynamic, dynamic>>('disconnect');
          if (context.mounted) {
            _showMessage(context, tr('Запрошено отключение Android VPN.'));
          }
        } else {
          final config = await const MihomoConfigBuilder().activeConfigFile();
          if (!await config.exists()) {
            if (context.mounted) {
              _showMessage(context, tr('Сначала добавьте YAML-подписку.'));
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
                tr('Запуск VPN запрошен. Подтвердите системное разрешение Android.'));
          }
        }
      } on MissingPluginException {
        if (context.mounted) {
          _showMessage(
              context, tr('Android native bridge недоступен в этой сборке.'));
        }
      } on PlatformException catch (error) {
        if (context.mounted) {
          _showMessage(context,
              error.message ?? tr('Не удалось выполнить запрос Android VPN.'));
        }
      } on FormatException catch (error) {
        if (context.mounted) _showMessage(context, error.message);
      } on FileSystemException catch (error) {
        if (context.mounted) {
          _showMessage(
              context,
              tr('Не удалось подготовить профиль: {message}',
                  <String, Object?>{'message': error.message}));
        }
      }
      return;
    }
    try {
      await _vpnChannel.invokeMethod<void>('connect');
    } on MissingPluginException {
      if (context.mounted) {
        _showMessage(context,
            tr('Нативный VPN-мост ещё не подключён. REST-клиент Mihomo доступен после настройки контроллера.'));
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showMessage(context, error.message ?? tr('Не удалось запустить VPN.'));
      }
    }
  }

  static Future<void> showAddSubscription(
      BuildContext context, WidgetRef ref) async {
    final input = TextEditingController();
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (dialogBuildContext, setDialogState) => AlertDialog(
                title: Text(tr('Добавить подписку')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                        controller: input,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                            hintText: 'https://…',
                            labelText: tr('Ссылка на конфигурацию'))),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final value = (await Clipboard.getData(
                                        Clipboard.kTextPlain))
                                    ?.text
                                    ?.trim();
                                if (!dialogContext.mounted) return;
                                if (value == null || value.isEmpty) {
                                  _showMessage(
                                      dialogContext, tr('Буфер обмена пуст.'));
                                  return;
                                }
                                input.text = value;
                                input.selection = TextSelection.collapsed(
                                    offset: value.length);
                              },
                        icon: const Icon(Icons.content_paste_rounded),
                        label: Text(tr('Вставить из буфера')),
                      ),
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                      onPressed:
                          busy ? null : () => Navigator.of(dialogContext).pop(),
                      child: Text(tr('Отмена'))),
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
                                        ? tr(
                                            'Профиль «{name}» сохранён. Встроенный Mihomo загрузится при первом подключении.',
                                            <String, Object?>{
                                                'name': profile.name
                                              })
                                        : tr(
                                            'Профиль «{name}» сохранён. При подключении Android использует встроенное native Mihomo ядро.',
                                            <String, Object?>{
                                                'name': profile.name
                                              }));
                              } catch (error) {
                                setDialogState(() => busy = false);
                                ScaffoldMessenger.of(dialogBuildContext)
                                    .showSnackBar(SnackBar(
                                        content: Text(tr(
                                            'Не удалось добавить профиль: {error}',
                                            <String, Object?>{
                                      'error': error
                                    }))));
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr('Загрузить'))),
                ],
              )),
    );
    input.dispose();
  }

  static void _showMessage(BuildContext context, String value) =>
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
          color: context.kago.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: context.kago.border)),
      child: Row(children: <Widget>[
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: active ? context.kago.accent : context.kago.warning,
                shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.kago.muted, fontSize: 12)))
      ]));
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.profile, required this.onAdd});
  final ImportedSubscription? profile;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final String details;
    if (profile == null) {
      details = tr('Добавьте ссылку, чтобы увидеть трафик и срок');
    } else {
      final used = profile.totalBytes > 0
          ? tr('{used} из {total}', <String, Object?>{
              'used': formatBytes(profile.usedBytes),
              'total': formatBytes(profile.totalBytes)
            })
          : tr('{used} использовано',
              <String, Object?>{'used': formatBytes(profile.usedBytes)});
      final expires = profile.expiresAt;
      details = expires == null
          ? used
          : '$used · ${tr('до {date}', <String, Object?>{
                  'date': formatLongDate(expires)
                })}';
    }
    return SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: <Widget>[
          const _CardIcon(icon: Icons.data_usage_rounded),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(profile?.name ?? tr('Подписка не добавлена'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.kago.muted)),
              ])),
          TextButton(
              onPressed: onAdd,
              child: Text(profile == null ? tr('Добавить') : tr('Обновить'))),
        ]));
  }
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

String? _delayText(
    List<ProxyGroup>? groups, Map<String, int> measured, bool online) {
  if (!online) return null;
  final group = groups == null ? null : _primaryGroup(groups);
  final selected = group?.selected;
  if (group == null || selected == null) return null;
  for (final node in group.nodes) {
    if (node.name != selected) continue;
    final value = measured[node.name] ?? node.delay;
    if (value == null) return null;
    return value > 0
        ? tr('{value} мс', <String, Object?>{'value': value})
        : tr('Узел не отвечает');
  }
  return null;
}

/// Small tinted icon square used by the dashboard cards.
class _CardIcon extends StatelessWidget {
  const _CardIcon({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
          color: context.kago.accentSoft,
          borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 21, color: context.kago.accent));
}

/// The round on/off button with a soft ring.
class _PowerButton extends StatelessWidget {
  const _PowerButton(
      {required this.connected, required this.busy, required this.onPressed});
  final bool connected;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return SizedBox(
        width: 148,
        height: 148,
        child: Stack(alignment: Alignment.center, children: <Widget>[
          Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent.withValues(alpha: .07),
                  border: Border.all(color: p.accent.withValues(alpha: .22)))),
          SizedBox(
            width: 116,
            height: 116,
            child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: connected ? p.danger : p.brand,
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: p.accent.withValues(alpha: .55), width: 2)),
                child: busy
                    ? const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : Icon(
                        connected
                            ? Icons.stop_rounded
                            : Icons.power_settings_new_rounded,
                        size: 46)),
          ),
        ]));
  }
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
    final title = connected ? tr('IP через VPN') : tr('Ваш IP');
    final String address;
    if (info != null) {
      address = hidden ? '•••.•••.•••.•••' : info.ip;
    } else {
      address = failed ? tr('Не определён') : tr('Определяем…');
    }
    final details = <String>[
      if (info != null && info.place.isNotEmpty) info.place,
      if (info?.isp != null) info!.isp!,
    ].join(' · ');
    return SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(children: <Widget>[
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: context.kago.accentSoft,
                  borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: info != null && info.flag.isNotEmpty && !hidden
                  ? Text(info.flag, style: const TextStyle(fontSize: 22))
                  : Icon(Icons.public_rounded, color: context.kago.accent)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(title,
                    style: TextStyle(fontSize: 12, color: context.kago.muted)),
                const SizedBox(height: 1),
                SelectableText(address,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color:
                            failed ? context.kago.muted : context.kago.text)),
                if (details.isNotEmpty && !hidden)
                  Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: context.kago.muted))),
              ])),
          IconButton(
              tooltip: hidden ? tr('Показать IP') : tr('Скрыть IP'),
              onPressed: () =>
                  ref.read(ipHiddenProvider.notifier).state = !hidden,
              icon: Icon(
                  hidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: context.kago.muted)),
          loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: tr('Проверить IP'),
                  onPressed: () => ref.invalidate(ipInfoProvider),
                  icon: Icon(Icons.refresh_rounded, color: context.kago.muted)),
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
              label: tr('Загрузка'),
              value: traffic == null ? '—' : formatSpeed(traffic.downloadSpeed),
              caption: traffic == null
                  ? null
                  : tr('всего {v}', <String, Object?>{
                      'v': formatBytes(traffic.downloadTotal)
                    }))),
      const SizedBox(width: 10),
      Expanded(
          child: _MetricCard(
              icon: Icons.arrow_upward_rounded,
              label: tr('Отдача'),
              value: traffic == null ? '—' : formatSpeed(traffic.uploadSpeed),
              caption: traffic == null
                  ? null
                  : tr('всего {v}', <String, Object?>{
                      'v': formatBytes(traffic.uploadTotal)
                    }))),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(children: <Widget>[
        Icon(icon, color: context.kago.accent, size: 20),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              Text(caption == null ? label : '$label · $caption',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.kago.muted))
            ])),
      ]));
}
