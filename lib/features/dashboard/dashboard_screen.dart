import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/android_vpn_events.dart';
import '../../core/network/android_battery.dart';
import '../../core/network/anonymous_mode.dart';
import '../../core/network/app_providers.dart';
import '../../core/network/desktop_recovery.dart';
import '../../core/network/vpn_connection_controller.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_motion.dart';
import '../../core/theme/kago_theme.dart';
import '../account/key_reissue.dart';
import '../guest/guest_telegram.dart';
import '../proxies/proxy_mode.dart';
import '../subscriptions/config_builder.dart';
import '../subscriptions/subscription_providers.dart';
import '../subscriptions/subscription_repository.dart';
import 'power_orb.dart';
import '../../core/l10n/l10n.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

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
    final recovering = androidState == 'recovering' ||
        (!Platform.isAndroid &&
            ref.watch(desktopRecoveryStatusProvider) ==
                RecoveryStatus.recovering);
    final recoveryError =
        Platform.isAndroid ? null : ref.watch(desktopRecoveryErrorProvider);
    final connected = coreRunning || androidConnected;
    final starting = androidState == 'starting';
    final guestNeeded = ref.watch(guestModeNeededProvider);
    final guestActive = ref.watch(guestModeActiveProvider);
    // Only problems are worth a line on the main screen.
    final problem = recoveryError ??
        switch (androidState) {
          'error' => androidEvent?['message'] as String? ??
              tr('Не удалось запустить Android VPN'),
          'revoked' => tr('Разрешение VPN отозвано'),
          _ => null,
        };
    final p = context.kago;
    final width = MediaQuery.sizeOf(context).width;
    if (width < 760) {
      return _MobileDashboard(
        connected: connected,
        starting: starting,
        recovering: recovering,
        guest: guestNeeded || guestActive && connected,
        problem: problem,
        onToggle: () => toggleVpn(context, ref, androidConnected),
        onRefresh: () => refreshSubscription(context, ref, profile.valueOrNull),
      );
    }
    final side = width > 760 ? 44.0 : 16.0;
    final state = recovering
        ? tr('Восстанавливаем соединение')
        : starting
            ? tr('Подключение…')
            : connected
                ? tr('Подключено')
                : tr('Не подключено');
    final hint = recovering
        ? tr('Соединение прервалось. Повторяем подключение.')
        : guestNeeded || (connected && guestActive)
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
                    size: 38,
                    subtitle: tr('Интернет без границ'),
                    intro: true)),
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
            KagoEntrance(
                order: 1, child: KagoPill(problem, color: p.danger, dot: true)),
          ],
          const SizedBox(height: 14),
          // The hero of usekago.net: state, the power button and the live
          // counters in one card. The cards enter one after another on the
          // first appearance of the app (KagoEntrance).
          KagoEntrance(
            order: 2,
            child: SurfaceCard(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(children: <Widget>[
                  Row(children: <Widget>[
                    StatusDot(
                        color: starting || recovering
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
                                  fontSize: KaGoText.lead,
                                  fontWeight: KaGoWeight.heading,
                                  color: p.text)),
                          Text(hint,
                              style: TextStyle(
                                  fontSize: KaGoText.caption, color: p.muted)),
                        ])),
                  ]),
                  const SizedBox(height: 20),
                  // Its own Consumer: the traffic (once a second) and the
                  // visibility rebuild only the button.
                  Consumer(builder: (context, ref, _) {
                    final live = ref.watch(rootTabIndexProvider) == 0 &&
                        ref.watch(appForegroundProvider);
                    final traffic = connected && live
                        ? ref.watch(connectionsSnapshotProvider).asData?.value
                        : null;
                    return PowerOrb(
                        connected: connected || recovering,
                        busy: !recovering &&
                            (starting || ref.watch(desktopVpnBusyProvider)),
                        recovering: recovering,
                        live: live,
                        activity: _trafficActivity(traffic),
                        onPressed: () =>
                            toggleVpn(context, ref, androidConnected));
                  }),
                ])),
          ),
          const SizedBox(height: 12),
          KagoEntrance(
            order: 3,
            child: _SubscriptionCard(
                profile: profile.valueOrNull,
                busy: ref.watch(_subscriptionRefreshingProvider),
                onAction: () =>
                    refreshSubscription(context, ref, profile.valueOrNull)),
          ),
          const SizedBox(height: 12),
          KagoEntrance(
            order: 4,
            child: SurfaceCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                onTap: () => ref.read(rootTabIndexProvider.notifier).state = 1,
                child: Column(children: <Widget>[
                  groups.when(
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
                                  style: TextStyle(
                                      fontSize: KaGoText.caption,
                                      color: p.muted)),
                              const SizedBox(height: 2),
                              Text(
                                  node ??
                                      group?.name ??
                                      tr('Войдите в аккаунт'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: KaGoText.bodySmall,
                                      fontWeight: KaGoWeight.extraBold,
                                      color: p.text)),
                              if (group != null)
                                Text(
                                    node != null
                                        ? (delay == null
                                            ? group.name
                                            : '${group.name} · $delay')
                                        : tr(
                                            '{length} серверов',
                                            <String, Object?>{
                                                'length': group.nodes.length
                                              }),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: KaGoText.caption,
                                        color: p.muted)),
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
                        style: TextStyle(
                            color: p.muted, fontSize: KaGoText.caption)),
                  ),
                  const SizedBox(height: KaGoSpace.md),
                  const Divider(),
                  _ServerIpLine(connected: connected)
                ])),
          ),
        ]);
  }

  /// Starts or stops the VPN (desktop core or Android service). Also used by
  /// the personal account screen. False when it failed (the user has already
  /// been told why) or another start/stop is still running.
  static Future<bool> toggleVpn(
      BuildContext context, WidgetRef ref, bool androidConnected) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final connection = ref.read(vpnConnectionControllerProvider);
      final recovery = ref.read(desktopRecoveryProvider);
      try {
        if (recovery.desired || ref.read(mihomoProcessProvider).isRunning) {
          return await connection.stopDesktop();
        }
        final (config, guest) = await _connectConfig(ref);
        final anonymous = !guest && await AnonymousMode.enabled();
        if (!await connection.startDesktop(config,
            guest: guest, anonymous: anonymous)) {
          return false;
        }
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
        if (context.mounted) {
          _showError(context, tr('Не удалось подключиться.'),
              details: '$error');
        }
      }
      return false;
    }
    if (Platform.isAndroid) {
      final connection = ref.read(vpnConnectionControllerProvider);
      try {
        if (androidConnected ||
            <String>['starting', 'recovering'].contains(
                ref.read(androidVpnEventProvider).valueOrNull?['state'])) {
          await connection.stopAndroid();
        } else {
          final (config, guest) = await _connectConfig(ref);
          final anonymous = !guest && await AnonymousMode.enabled();
          final profile = await ref
              .read(importedSubscriptionProvider.future)
              .catchError((Object _) => null);
          await connection.startAndroid(config,
              guest: guest,
              anonymous: anonymous,
              expiresAt: profile?.expiresAt);
          // Once: without the exemption the system may stop the VPN in the
          // background (asked after the VPN permission, not over it).
          unawaited(AndroidBattery.askOnce());
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
      await ref.read(vpnConnectionControllerProvider).startOther();
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
  /// A running VPN is restarted when the profile changed: the core keeps the
  /// config it started with, so new servers and rules showed up only after
  /// the next connect and the button looked broken.
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
      final updated = await SubscriptionRepository().import(profile.url);
      ref.invalidate(importedSubscriptionProvider);
      ref.invalidate(proxyGroupsProvider);
      // Compared by the downloaded config, not the file: a desktop core
      // writes its ports and secret into the active file when it starts.
      if (updated.configHash != profile.configHash &&
          ref.read(vpnActiveProvider) &&
          context.mounted) {
        await reconnect(context, ref);
      }
    } catch (error) {
      // 404: the key may have been re-issued elsewhere (or the server does
      // not let this User-Agent in — then nothing is replaced).
      if (error is DioException &&
          error.response?.statusCode == 404 &&
          context.mounted &&
          await KeyReissue.sync(context, ref, force: true)) {
        return;
      }
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
      {required this.profile,
      required this.busy,
      required this.onAction,
      this.compact = false});
  final bool compact;
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
          : tr('Безлимит');
      final expires = profile.expiresAt;
      details = expires == null
          ? used
          : '$used · ${tr('до {date}', <String, Object?>{
                  'date': formatLongDate(expires)
                })}';
    }
    if (compact) {
      return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                        Text(profile?.name ?? tr('Нет подписки'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: KaGoText.label,
                                fontWeight: KaGoWeight.semiBold)),
                        const SizedBox(height: 4),
                        Text(details,
                            style: TextStyle(
                                fontSize: KaGoText.caption,
                                color: context.kago.muted)),
                      ])),
                  IconButton(
                      tooltip: profile == null ? tr('Войти') : tr('Обновить'),
                      onPressed: busy ? null : onAction,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(profile == null
                              ? Icons.login_rounded
                              : Icons.refresh_rounded)),
                ]),
                if (profile != null && profile.totalBytes > 0) ...<Widget>[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                      value: (profile.usedBytes / profile.totalBytes)
                          .clamp(0.0, 1.0),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4)),
                ],
              ]));
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
                        fontSize: KaGoText.bodySmall,
                        fontWeight: KaGoWeight.extraBold,
                        color: context.kago.text)),
                const SizedBox(height: 2),
                Text(details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: KaGoText.caption, color: context.kago.muted)),
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

/// Traffic as 0…1 for the satellites of the power button: logarithmic, so a
/// page loading already shows, and about 100 Mbit/s is the top.
double _trafficActivity(ConnectionsSnapshot? traffic) {
  final bytes =
      traffic == null ? 0 : traffic.downloadSpeed + traffic.uploadSpeed;
  if (bytes <= 0) return 0;
  return (math.log(1 + bytes / 16384) / math.log(1 + 12500000 / 16384))
      .clamp(0.0, 1.0);
}

/// "Ваш IP": the address the internet currently sees, with country, city and
/// provider. Tap the eye to hide it for screenshots.
/// IP показывается рядом с выбранным сервером; результат другого маршрута скрыт.
class _ServerIpLine extends ConsumerWidget {
  const _ServerIpLine({required this.connected});
  final bool connected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ip = ref.watch(ipInfoProvider);
    final hidden = ref.watch(ipHiddenProvider);
    final looked = ip.valueOrNull;
    final info = looked != null && (looked.viaVpn ?? connected) == connected
        ? looked
        : null;
    final failed = ip.hasError && info == null;
    final guest = connected && ref.watch(guestModeActiveProvider);
    final title = connected && !guest ? tr('IP через VPN') : tr('Ваш IP');
    final address = hidden
        ? '•••.•••.•••.•••'
        : info?.ip ?? (failed ? tr('Не определён') : tr('Определяем…'));
    return Row(key: const ValueKey<String>('server-ip'), children: <Widget>[
      Icon(Icons.public_outlined, size: 16, color: context.kago.muted),
      const SizedBox(width: KaGoSpace.sm),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
            Text(title,
                style: TextStyle(
                    fontSize: KaGoText.meta, color: context.kago.muted)),
            SelectableText(address,
                maxLines: 2,
                style: TextStyle(
                    fontSize: KaGoText.label, color: context.kago.text)),
          ])),
      if (ip.isLoading)
        const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))),
      if (failed)
        IconButton(
            tooltip: tr('Проверить IP'),
            onPressed: () => ref.invalidate(ipInfoProvider),
            icon: const Icon(Icons.refresh, size: 18)),
      IconButton(
          tooltip: hidden ? tr('Показать IP') : tr('Скрыть IP'),
          onPressed: () => ref.read(ipHiddenProvider.notifier).state = !hidden,
          icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: context.kago.muted)),
    ]);
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard(
      {required this.connected,
      required this.starting,
      required this.recovering,
      required this.guest,
      required this.problem,
      required this.onToggle,
      required this.onRefresh});
  final bool connected;
  final bool starting;
  final bool recovering;
  final bool guest;
  final String? problem;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.kago;
    final operationBusy = ref.watch(desktopVpnBusyProvider);
    final busy = !recovering && (starting || operationBusy);
    final groups = ref.watch(proxyGroupsProvider);
    final mode = ref.watch(effectiveProxyModeProvider);
    final profile = ref.watch(importedSubscriptionProvider).valueOrNull;
    final state = recovering
        ? tr('Восстанавливаем соединение')
        : starting || busy && !connected
            ? tr('Подключение…')
            : connected
                ? tr('VPN включён')
                : tr('VPN выключен');
    final detail = guest && connected
        ? tr('Через VPN работает только Telegram')
        : !connected
            ? tr('Сейчас сайты открываются напрямую')
            : ref.watch(anonymousActiveProvider)
                ? tr('Анонимный режим')
                : mode == ProxyMode.global
                    ? tr('Весь трафик идёт через выбранный сервер')
                    : tr('Маршрутизация по правилам подписки');
    final tone = recovering || starting
        ? p.warning
        : connected
            ? p.success
            : p.muted;
    return ListView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
        children: <Widget>[
          const _MobileBrand(),
          const SizedBox(height: 30),
          Text(tr('Состояние соединения'),
              style: TextStyle(fontSize: KaGoText.caption, color: p.muted)),
          const SizedBox(height: 8),
          Semantics(
              liveRegion: true,
              child: Row(children: <Widget>[
                IconChip(
                    connected
                        ? Icons.verified_user_outlined
                        : Icons.shield_outlined,
                    size: 36,
                    color: tone,
                    background: connected ? p.successSoft : p.surfaceRaised),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(state,
                        style: TextStyle(
                            fontSize: KaGoText.appTitle,
                            height: 1.2,
                            fontWeight: KaGoWeight.heading,
                            letterSpacing: -.4,
                            color: p.text))),
              ])),
          const SizedBox(height: 8),
          Text(detail,
              style: TextStyle(fontSize: KaGoText.label, color: p.muted)),
          if (problem != null) ...<Widget>[
            const SizedBox(height: 12),
            KagoPill(problem!, color: p.danger, dot: true),
          ],
          const SizedBox(height: 24),
          if (guest && !connected) ...<Widget>[
            SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Text(tr('Без подписки доступен Telegram'),
                      style: const TextStyle(
                          fontSize: KaGoText.secondary,
                          fontWeight: KaGoWeight.semiBold)),
                  const SizedBox(height: 6),
                  Text(tr('После подключения через VPN будет работать только Telegram. Остальные сайты продолжат работать напрямую.'),
                      style: TextStyle(
                          fontSize: KaGoText.caption,
                          height: 1.5,
                          color: p.muted)),
                  const SizedBox(height: 4),
                  TextButton(
                      onPressed: () =>
                          ref.read(rootTabIndexProvider.notifier).state = 2,
                      child: Text(tr('Войти в KAGO'))),
                ])),
          ] else
            SurfaceCard(
                onTap: () => ref.read(rootTabIndexProvider.notifier).state = 1,
                padding: const EdgeInsets.all(16),
                child: Column(children: <Widget>[
                  groups.when(
                    data: (items) {
                      final group = _primaryGroup(items);
                      final delay = _delayText(
                          items, ref.watch(proxyDelaysProvider), connected);
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(tr('Ваш сервер'),
                                style: TextStyle(
                                    fontSize: KaGoText.caption,
                                    color: p.muted)),
                            const SizedBox(height: 10),
                            Row(children: <Widget>[
                              Icon(Icons.public_outlined,
                                  size: 26, color: p.muted),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                    Text(
                                        group?.selected ??
                                            group?.name ??
                                            tr('Войдите в аккаунт'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: KaGoText.bodySmall,
                                            fontWeight: KaGoWeight.semiBold)),
                                    if (group != null)
                                      Text(group.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: KaGoText.caption,
                                              color: p.muted)),
                                  ])),
                              Icon(Icons.chevron_right,
                                  size: 20, color: p.muted),
                            ]),
                            if (delay != null) ...<Widget>[
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 10),
                              Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(delay,
                                      style: TextStyle(
                                          fontSize: KaGoText.caption,
                                          color: p.success))),
                            ],
                          ]);
                    },
                    loading: () => const LinearProgressIndicator(minHeight: 2),
                    error: (_, __) => Text(
                        tr('Не удалось загрузить список серверов.'),
                        style: TextStyle(color: p.muted)),
                  ),
                  const SizedBox(height: KaGoSpace.md),
                  const Divider(),
                  _ServerIpLine(connected: connected)
                ])),
          const SizedBox(height: 16),
          KagoPressFeedback(
              enabled: !busy,
              child: SizedBox(
                  width: double.infinity,
                  child: connected || recovering
                      ? OutlinedButton.icon(
                          onPressed: busy ? null : onToggle,
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 56),
                              shape: const StadiumBorder(),
                              backgroundColor: p.accentSoft,
                              foregroundColor: p.accentStrong,
                              side:
                                  BorderSide(color: p.accentTint, width: 1.5)),
                          icon: _ConnectionIcon(busy: busy, connected: true),
                          label: Text(tr('Отключить VPN')))
                      : FilledButton.icon(
                          onPressed: busy ? null : onToggle,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 56),
                              shape: const StadiumBorder()),
                          icon: _ConnectionIcon(busy: busy),
                          label: Text(busy
                              ? tr('Подключение…')
                              : guest
                                  ? tr('Подключить Telegram')
                                  : tr('Подключить VPN'))))),
          const SizedBox(height: 26),
          if (guest && !connected) ...<Widget>[
            Text(tr('Подключение'),
                style: TextStyle(fontSize: KaGoText.caption, color: p.muted)),
            const SizedBox(height: 10),
            SurfaceCard(
                child: Column(children: <Widget>[
              Row(children: <Widget>[
                const IconChip(Icons.send_outlined),
                const SizedBox(width: KaGoSpace.md),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                      const Text('Telegram',
                          style: TextStyle(fontWeight: KaGoWeight.semiBold)),
                      Text(tr('Доступен без подписки'),
                          style: TextStyle(
                              fontSize: KaGoText.caption, color: p.muted)),
                    ])),
              ]),
              const SizedBox(height: KaGoSpace.md),
              const Divider(),
              _ServerIpLine(connected: connected),
            ])),
          ] else if (!guest) ...<Widget>[
            _SubscriptionCard(
                profile: profile,
                busy: ref.watch(_subscriptionRefreshingProvider),
                onAction: onRefresh,
                compact: true),
          ],
        ]);
  }
}

class _ConnectionIcon extends StatelessWidget {
  const _ConnectionIcon({required this.busy, this.connected = false});
  final bool busy;
  final bool connected;
  @override
  Widget build(BuildContext context) => busy
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(connected ? Icons.stop_rounded : Icons.play_arrow_rounded,
          size: 22);
}

class _MobileBrand extends StatelessWidget {
  const _MobileBrand();
  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        const KagoLogo(size: 72),
        const SizedBox(height: 12),
        Text('KAGO.',
            style: TextStyle(
                fontSize: KaGoText.titleLarge,
                letterSpacing: -.5,
                fontWeight: KaGoWeight.appTitle,
                color: context.kago.text)),
      ]);
}
