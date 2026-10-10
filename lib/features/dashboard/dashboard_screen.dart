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
    final state = starting
        ? tr('Подключение…')
        : connected
            ? tr('Подключено')
            : tr('Не подключено');
    final hint = guestNeeded || (connected && guestActive)
        ? (connected
            ? tr('Бесплатный доступ: через VPN работает только Telegram')
            : tr('Без подписки — бесплатный доступ к Telegram'))
        : connected && ref.watch(anonymousActiveProvider)
            ? tr('Анонимный режим')
            : connected
                ? tr('Весь трафик идёт через выбранный сервер')
                : tr('Нажмите, чтобы включить защиту');
    return ListView(
        padding: EdgeInsets.fromLTRB(side, 14, side, 18),
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(
                child: KagoWordmark(
                    size: 38, subtitle: tr('Интернет без границ'))),
            IconButton(
                tooltip: tr('Обновить'),
                onPressed: () {
                  ref.invalidate(coreVersionProvider);
                  ref.invalidate(proxyGroupsProvider);
                  ref.invalidate(ipInfoProvider);
                },
                icon: Icon(Icons.refresh_rounded, color: p.muted)),
          ]),
          if (problem != null) ...<Widget>[
            const SizedBox(height: 12),
            KagoPill(problem, color: p.danger, dot: true),
          ],
          const SizedBox(height: 14),
          // The hero of usekago.net: state, the power button and the live
          // counters in one card.
          SurfaceCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(children: <Widget>[
                Row(children: <Widget>[
                  StatusDot(
                      color: starting
                          ? p.warning
                          : connected
                              ? p.success
                              : p.hint),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                        Text(state,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: KaGoWeight.heading,
                                color: p.text)),
                        Text(hint,
                            style: TextStyle(fontSize: 12, color: p.muted)),
                      ])),
                ]),
                const SizedBox(height: 20),
                _PowerButton(
                    connected: connected,
                    busy: starting || ref.watch(desktopVpnBusyProvider),
                    onPressed: () => toggleVpn(context, ref, androidConnected)),
                const SizedBox(height: 20),
                _TrafficMetrics(active: connected),
              ])),
          const SizedBox(height: 12),
          _SubscriptionCard(
              profile: profile.valueOrNull,
              busy: ref.watch(_subscriptionRefreshingProvider),
              onAction: () =>
                  refreshSubscription(context, ref, profile.valueOrNull)),
          const SizedBox(height: 12),
          SurfaceCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              onTap: () => ref.read(rootTabIndexProvider.notifier).state = 1,
              child: groups.when(
                data: (items) {
                  final group = _primaryGroup(items);
                  final node = group?.selected;
                  final delay = _delayText(
                      items, ref.watch(proxyDelaysProvider), connected);
                  return Row(children: <Widget>[
                    const IconChip(Icons.public_rounded),
                    const SizedBox(width: 14),
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
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: KaGoWeight.extraBold,
                                  color: p.text)),
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
                    Icon(Icons.chevron_right_rounded, color: p.hint),
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
          const SizedBox(height: 12),
          _IpCard(connected: connected),
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
        // The power button shows the state; a declined TUN (manager.notice)
        // is in the log.
        if (guest && context.mounted) await _checkGuest(context, ref);
        return true;
      } on GuestUnavailable catch (error) {
        if (context.mounted) {
          _showError(
              context, tr('Бесплатный доступ к Telegram сейчас недоступен.'),
              details: error.message);
        }
      } catch (error) {
        ref.read(desktopCoreRunningProvider.notifier).state = manager.isRunning;
        _refreshCoreData(ref);
        if (context.mounted) {
          _showError(context, tr('Не удалось подключиться.'),
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
          if (guest &&
              context.mounted &&
              await waitForVpn(ref, true,
                  timeout: const Duration(seconds: 20)) &&
              context.mounted) {
            await _checkGuest(context, ref);
          }
        }
        return true;
      } on MissingPluginException {
        if (context.mounted) {
          _showError(context, tr('Не удалось подключиться.'),
              details: 'Android native bridge (MissingPluginException)');
        }
      } on PlatformException catch (error) {
        if (context.mounted) {
          _showError(context, tr('Не удалось подключиться.'),
              details: error.message);
        }
      } on FormatException catch (error) {
        if (context.mounted) {
          _showError(context, tr('Не удалось подключиться.'),
              details: error.message);
        }
      } on FileSystemException catch (error) {
        if (context.mounted) {
          _showError(context, tr('Не удалось подключиться.'),
              details: error.message);
        }
      } on GuestUnavailable catch (error) {
        if (context.mounted) {
          _showError(
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
        _showError(context, tr('Не удалось подключиться.'),
            details: 'Native VPN bridge (MissingPluginException)');
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showError(context, tr('Не удалось подключиться.'),
            details: error.message);
      }
    }
    return false;
  }

  /// After the free Telegram access starts: checks it through the guest
  /// server and reports, as a critical error, what will stop Telegram
  /// (details for support behind «Поддержка»). Nothing when all is well.
  static Future<void> _checkGuest(BuildContext context, WidgetRef ref) async {
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
        _showError(
            context, tr('Бесплатный сервер Telegram сейчас не отвечает.'),
            details: tr(
                'Через гостевой сервер не открылся {url} за 5 секунд. Проверьте гостевой сервер, его ноду и подписку гостя в панели.',
                <String, Object?>{'url': GuestTelegram.checkUrl}));
      case GuestCheck.addressesBlocked:
        _showError(context,
            tr('Telegram может не подключиться через бесплатный сервер.'),
            details: tr(
                'Сайт telegram.org открывается через гостевой сервер, а адрес Telegram ({url}) — нет. Приложения Telegram подключаются по адресам, поэтому в маршрутизации Xray гостевого inbound нужно разрешить geoip:telegram (README, «Гостевой доступ к Telegram»).',
                <String, Object?>{'url': GuestTelegram.addressCheckUrl}));
      case GuestCheck.ok:
        break;
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
      ref.read(rootTabIndexProvider.notifier).state = 2;
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
      ref.read(rootTabIndexProvider.notifier).state = 2;
      return;
    }
    final busy = ref.read(_subscriptionRefreshingProvider.notifier);
    if (busy.state) return;
    busy.state = true;
    try {
      await SubscriptionRepository().import(profile.url);
      ref.invalidate(importedSubscriptionProvider);
      ref.invalidate(proxyGroupsProvider);
    } catch (error) {
      if (context.mounted) {
        _showError(context, tr('Не удалось обновить подписку.'),
            details: '$error');
      }
    } finally {
      busy.state = false;
    }
  }

  /// The only kind of message at the bottom of the screen (CLAUDE.md):
  /// critical errors, with support and the technical [details].
  static void _showError(BuildContext context, String value,
          {String? details}) =>
      showCriticalError(context, value, details: details);
}

/// The subscription is being reloaded (the card's button shows progress).
final _subscriptionRefreshingProvider = StateProvider<bool>((ref) => false);

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard(
      {required this.profile, required this.busy, required this.onAction});
  final ImportedSubscription? profile;
  final bool busy;
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
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(children: <Widget>[
          const IconChip(Icons.data_usage_rounded),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(profile?.name ?? tr('Нет подписки'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: KaGoWeight.extraBold,
                        color: context.kago.text)),
                const SizedBox(height: 2),
                Text(details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.kago.muted)),
              ])),
          TextButton(
              onPressed: busy ? null : onAction,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(profile == null ? tr('Войти') : tr('Обновить'))),
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

/// The round on/off button: the brand blue in a soft ring of the same hue
/// (the site's primary / primary-tint pair), red while connected.
class _PowerButton extends StatelessWidget {
  const _PowerButton(
      {required this.connected, required this.busy, required this.onPressed});
  final bool connected;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final tone = connected ? p.danger : p.brand;
    return SizedBox(
        width: 152,
        height: 152,
        child: Stack(alignment: Alignment.center, children: <Widget>[
          Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: .08),
                  border: Border.all(color: tone.withValues(alpha: .20)))),
          Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: .14),
                  border: Border.all(color: tone.withValues(alpha: .28)))),
          SizedBox(
            width: 108,
            height: 108,
            child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: tone,
                    foregroundColor: Colors.white,
                    elevation: 0),
                child: busy
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : Icon(
                        connected
                            ? Icons.stop_rounded
                            : Icons.power_settings_new_rounded,
                        size: 44)),
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
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        child: Row(children: <Widget>[
          IconChip(Icons.public_rounded,
              child: info != null && info.flag.isNotEmpty && !hidden
                  ? Text(info.flag, style: const TextStyle(fontSize: 22))
                  : null),
          const SizedBox(width: 14),
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
                        fontWeight: KaGoWeight.extraBold,
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
        child: InsetTile(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: <Widget>[
              Expanded(
                  child: _Metric(
                      icon: Icons.arrow_downward_rounded,
                      label: tr('Загрузка'),
                      value: traffic == null
                          ? '—'
                          : formatSpeed(traffic.downloadSpeed),
                      caption: traffic == null
                          ? null
                          : tr('всего {v}', <String, Object?>{
                              'v': formatBytes(traffic.downloadTotal)
                            }))),
              Container(width: 1, height: 34, color: context.kago.border),
              const SizedBox(width: 14),
              Expanded(
                  child: _Metric(
                      icon: Icons.arrow_upward_rounded,
                      label: tr('Отдача'),
                      value: traffic == null
                          ? '—'
                          : formatSpeed(traffic.uploadSpeed),
                      caption: traffic == null
                          ? null
                          : tr('всего {v}', <String, Object?>{
                              'v': formatBytes(traffic.uploadTotal)
                            }))),
            ])));
  }
}

/// One counter of the hero card (`.hero__metric`).
class _Metric extends StatelessWidget {
  const _Metric(
      {required this.icon,
      required this.label,
      required this.value,
      this.caption});
  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Icon(icon, color: context.kago.accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: MetricValue(
                value: value,
                label: caption == null ? label : '$label · $caption',
                size: 18)),
      ]);
}
