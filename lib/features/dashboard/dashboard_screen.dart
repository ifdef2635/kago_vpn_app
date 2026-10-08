import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/android_vpn_events.dart';
import '../../core/network/anonymous_mode.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';
import '../guest/guest_telegram.dart';
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
    final guestNeeded = ref.watch(guestModeNeededProvider);
    final guestActive = ref.watch(guestModeActiveProvider);
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
              profile: profile.valueOrNull,
              onAction: () =>
                  refreshSubscription(context, ref, profile.valueOrNull)),
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
                          Text(node ?? group?.name ?? tr('Войдите в аккаунт'),
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
                  busy: starting || ref.watch(desktopVpnBusyProvider),
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
          if (connected && !guestActive && ref.watch(anonymousActiveProvider))
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Анонимный режим'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 12))),
          if (guestNeeded || (connected && guestActive)) ...<Widget>[
            const SizedBox(height: 4),
            Text(
                connected
                    ? tr(
                        'Бесплатный доступ: через VPN работает только Telegram')
                    : tr('Без подписки — бесплатный доступ к Telegram'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12)),
          ],
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
  /// the personal account screen. False when it failed (the user has already
  /// been told why) or another start/stop is still running.
  static Future<bool> toggleVpn(
      BuildContext context, WidgetRef ref, bool androidConnected) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // One start or stop at a time: a second tap while the core starts would
      // start a second core, and a stop during the start would let the start
      // turn the system proxy on after the stop restored it.
      final busy = ref.read(desktopVpnBusyProvider.notifier);
      if (busy.state) return false;
      busy.state = true;
      final manager = ref.read(mihomoProcessProvider);
      try {
        if (manager.isRunning) {
          await manager.stop();
          ref.read(desktopCoreRunningProvider.notifier).state = false;
          _refreshCoreData(ref);
          if (context.mounted) {
            _showMessage(context, tr('VPN отключён.'));
          }
          return true;
        }
        final (config, guest) = await _connectConfig(ref);
        await manager.start(configPath: config.path);
        ref.read(guestModeActiveProvider.notifier).state = guest;
        ref.read(desktopCoreRunningProvider.notifier).state = true;
        _refreshCoreData(ref);
        final anonymous = !guest && await AnonymousMode.enabled();
        ref.read(anonymousActiveProvider.notifier).state = anonymous;
        if (anonymous) await _matchTimeZone(ref);
        if (context.mounted) {
          _showMessage(
              context,
              manager.notice ??
                  (guest
                      ? tr('Бесплатный доступ к Telegram включён.')
                      : anonymous
                          ? tr('VPN подключён, анонимный режим.')
                          : tr('VPN подключён.')));
        }
        if (guest && context.mounted) {
          await _checkGuest(context, ref, allTraffic: manager.allTraffic);
        }
        return true;
      } on GuestUnavailable catch (error) {
        if (context.mounted) {
          _showMessage(
              context, tr('Бесплатный доступ к Telegram сейчас недоступен.'),
              details: error.message);
        }
      } catch (error) {
        ref.read(desktopCoreRunningProvider.notifier).state = manager.isRunning;
        _refreshCoreData(ref);
        if (context.mounted) {
          _showMessage(context, tr('Не удалось подключиться.'),
              details: '$error');
        }
      } finally {
        busy.state = false;
      }
      return false;
    }
    if (Platform.isAndroid) {
      try {
        if (androidConnected) {
          await _vpnChannel.invokeMethod<Map<dynamic, dynamic>>('disconnect');
          if (context.mounted) {
            _showMessage(context, tr('VPN отключается…'));
          }
        } else {
          final (config, guest) = await _connectConfig(ref);
          ref.read(guestModeActiveProvider.notifier).state = guest;
          ref.read(anonymousActiveProvider.notifier).state =
              !guest && await AnonymousMode.enabled();
          final controller = ref.read(mihomoControllerProvider);
          await const MihomoConfigBuilder().prepareAndroidTunnelConfig(
            config,
            endpoint: await controller.endpoint,
            secret: await controller.ensureSecret(),
          );
          await _vpnChannel.invokeMethod<Map<dynamic, dynamic>>(
              'connect', <String, String>{'configPath': config.path});
          if (context.mounted) {
            _showMessage(
                context,
                guest
                    ? tr('Включаем бесплатный доступ к Telegram…')
                    : tr('Подключаемся…'));
          }
          if (guest &&
              context.mounted &&
              await waitForVpn(ref, true,
                  timeout: const Duration(seconds: 20)) &&
              context.mounted) {
            await _checkGuest(context, ref, allTraffic: true);
          }
        }
        return true;
      } on MissingPluginException {
        if (context.mounted) {
          _showMessage(
              context, tr('Android native bridge недоступен в этой сборке.'));
        }
      } on PlatformException catch (error) {
        if (context.mounted) {
          _showMessage(context, tr('Не удалось подключиться.'),
              details: error.message);
        }
      } on FormatException catch (error) {
        if (context.mounted) {
          _showMessage(context, tr('Не удалось подключиться.'),
              details: error.message);
        }
      } on FileSystemException catch (error) {
        if (context.mounted) {
          _showMessage(context, tr('Не удалось подключиться.'),
              details: error.message);
        }
      } on GuestUnavailable catch (error) {
        if (context.mounted) {
          _showMessage(
              context, tr('Бесплатный доступ к Telegram сейчас недоступен.'),
              details: error.message);
        }
      }
      return false;
    }
    try {
      await _vpnChannel.invokeMethod<void>('connect');
      return true;
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
    return false;
  }

  /// After the free Telegram access starts: checks it through the guest
  /// server and says, in one line, what will stop Telegram (details for
  /// support behind «Подробнее»). Nothing when all is well.
  static Future<void> _checkGuest(BuildContext context, WidgetRef ref,
      {required bool allTraffic}) async {
    final controller = ref.read(mihomoControllerProvider);
    final GuestCheck result;
    try {
      result = await GuestTelegram.check(
          (url) => controller.testDelay(GuestTelegram.groupName, url: url));
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    switch (result) {
      case GuestCheck.serverDown:
        _showMessage(
            context, tr('Бесплатный сервер Telegram сейчас не отвечает.'),
            details: tr(
                'Через гостевой сервер не открылся {url} за 5 секунд. Проверьте гостевой сервер, его ноду и подписку гостя в панели.',
                <String, Object?>{'url': GuestTelegram.checkUrl}));
      case GuestCheck.addressesBlocked:
        _showMessage(context,
            tr('Telegram может не подключиться через бесплатный сервер.'),
            details: tr(
                'Сайт telegram.org открывается через гостевой сервер, а адрес Telegram ({url}) — нет. Приложения Telegram подключаются по адресам, поэтому в маршрутизации Xray гостевого inbound нужно разрешить geoip:telegram (README, «Гостевой доступ к Telegram»).',
                <String, Object?>{'url': GuestTelegram.addressCheckUrl}));
      case GuestCheck.ok:
        if (!allTraffic) {
          _showMessage(context,
              tr('Приложение Telegram может не подключиться без режима «Весь трафик через VPN».'),
              details: tr(
                  'Включите «Весь трафик через VPN» в Настройках. Или в Telegram: Настройки → Продвинутые настройки → Тип соединения → «Использовать системный прокси».'));
        }
    }
  }

  /// Waits until the VPN is [active] (or not); false after [timeout].
  static Future<bool> waitForVpn(WidgetRef ref, bool active,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (ref.read(vpnActiveProvider) == active) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return ref.read(vpnActiveProvider) == active;
  }

  /// After sign-in on a guest connection: reconnect with the subscription,
  /// so everything (not only Telegram) goes through the VPN again.
  static Future<void> reconnectIfGuest(
      BuildContext context, WidgetRef ref) async {
    if (!ref.read(guestModeActiveProvider) || !ref.read(vpnActiveProvider)) {
      return;
    }
    final profile = await ref
        .read(importedSubscriptionProvider.future)
        .catchError((Object _) => null);
    if (GuestTelegram.needed(profile, DateTime.now()) || !context.mounted) {
      return;
    }
    await reconnect(context, ref);
  }

  /// Restarts a running VPN, so it uses the profile saved just now.
  static Future<void> reconnect(BuildContext context, WidgetRef ref) async {
    if (!ref.read(vpnActiveProvider)) return;
    await toggleVpn(context, ref, true);
    if (!await waitForVpn(ref, false, timeout: const Duration(seconds: 8)) ||
        !context.mounted) {
      return;
    }
    await toggleVpn(context, ref, false);
  }

  /// Windows, anonymous profile: the system time zone of the VPN exit, so
  /// the browser's clock matches the IP.
  static Future<void> _matchTimeZone(WidgetRef ref) async {
    if (!Platform.isWindows) return;
    try {
      final info = await ref.read(ipInfoServiceProvider).fetch(proxyPort: 7890);
      final zone = info.timeZone;
      if (zone != null) await WindowsTimeZone.apply(zone);
    } catch (_) {
      // Not fatal: the connection works, only the clock is not matched.
    }
  }

  /// The profile to connect with: the subscription, or — without a working
  /// one — the free guest config that carries only Telegram.
  static Future<(File, bool)> _connectConfig(WidgetRef ref) async {
    final active = await const MihomoConfigBuilder().activeConfigFile();
    final profile = await ref
        .read(importedSubscriptionProvider.future)
        .catchError((Object _) => null);
    if (!GuestTelegram.needed(profile, DateTime.now()) &&
        await active.exists()) {
      // The anonymous profile is derived from the subscription each time.
      if (await AnonymousMode.enabled()) {
        return (await AnonymousMode.write(active), false);
      }
      return (active, false);
    }
    try {
      return (await GuestTelegram.prepare(), true);
    } on GuestUnavailable catch (error) {
      if (await active.exists()) rethrow;
      // Nothing saved either: say why the free access failed (the user may
      // be on «Кабинет» trying to sign in through Telegram right now).
      ref.read(rootTabIndexProvider.notifier).state = 3;
      throw GuestUnavailable(tr(
          '{reason}\nВойдите в аккаунт KAGO по email во вкладке «Кабинет» или попробуйте позже.',
          <String, Object?>{'reason': error.message}));
    }
  }

  /// Subscriptions come only from the KAGO account: without one the button
  /// leads to the account tab; with one it reloads the saved subscription.
  static Future<void> refreshSubscription(BuildContext context, WidgetRef ref,
      ImportedSubscription? profile) async {
    if (profile == null || profile.url.isEmpty) {
      ref.read(rootTabIndexProvider.notifier).state = 3;
      return;
    }
    _showMessage(context, tr('Обновляем подписку…'));
    try {
      await SubscriptionRepository().import(profile.url);
      ref.invalidate(importedSubscriptionProvider);
      ref.invalidate(proxyGroupsProvider);
      if (context.mounted) _showMessage(context, tr('Подписка обновлена.'));
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, tr('Не удалось обновить подписку.'),
            details: '$error');
      }
    }
  }

  /// A short line at the bottom; technical [details] (for support) only
  /// behind «Подробнее».
  static void _showMessage(BuildContext context, String value,
          {String? details}) =>
      showShortMessage(context, value, details: details);
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
  const _SubscriptionCard({required this.profile, required this.onAction});
  final ImportedSubscription? profile;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final String details;
    if (profile == null) {
      details = tr('Войдите в аккаунт KAGO — подписка подключится сама');
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
                Text(profile?.name ?? tr('Нет подписки'),
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
              onPressed: onAction,
              child: Text(profile == null ? tr('Войти') : tr('Обновить'))),
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
    final looked = ip.valueOrNull;
    // A previous result from the other state (VPN on/off) is stale.
    final info = looked != null && (looked.viaVpn ?? connected) == connected
        ? looked
        : null;
    final loading = ip.isLoading;
    final failed = ip.hasError && info == null;
    // Free Telegram access: only Telegram goes through the VPN, so the IP
    // the sites see is the user's own.
    final guest = connected && ref.watch(guestModeActiveProvider);
    final title = guest
        ? tr('Ваш IP (через VPN идёт только Telegram)')
        : connected
            ? tr('IP через VPN')
            : tr('Ваш IP');
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
