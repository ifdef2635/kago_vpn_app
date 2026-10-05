import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/android_vpn_events.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../subscriptions/subscription_providers.dart';
import '../subscriptions/subscription_repository.dart';

const _siteUrl = 'https://usekago.net';
const _cabinetUrl = 'https://usekago.net/my';
const _botUrl = 'https://t.me/KaGoVPNbot';

/// Personal account, laid out like usekago.net/my: the navy subscription card
/// with status, expiry and three counters, then account actions. Everything
/// comes from the saved subscription (its `subscription-userinfo` header).
/// Devices, promo codes, referrals and key re-issue need the site's account
/// login, so those open the site.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(importedSubscriptionProvider).value;
    final coreRunning = ref.watch(desktopCoreRunningProvider);
    final androidConnected = Platform.isAndroid &&
        ref.watch(androidVpnEventProvider
            .select((event) => event.value?['state'] == 'connected'));
    final connected = coreRunning || androidConnected;
    final wide = MediaQuery.sizeOf(context).width > 760;
    final p = context.kago;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 44 : 20, 22, wide ? 44 : 20, 28),
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: _Pill(
              label: 'Личный кабинет',
              color: p.success,
              background: p.successSoft),
        ),
        const SizedBox(height: 12),
        Text('Здравствуйте!',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text('Управляйте подпиской и подключением в одном месте.',
            style: TextStyle(color: p.muted, fontSize: 14)),
        const SizedBox(height: 20),
        _SubscriptionHero(
          profile: profile,
          connected: connected,
          onConnect: () =>
              DashboardScreen.toggleVpn(context, ref, androidConnected),
          onAdd: () => DashboardScreen.showAddSubscription(context, ref),
          onRefresh: profile == null ? null : () => _refresh(context, ref),
        ),
        const SizedBox(height: 16),
        _ActionsCard(
          icon: Icons.devices_rounded,
          title: 'Устройства и промокоды',
          text:
              'Список устройств, промокоды, перевыпуск ключа и реферальная программа доступны в личном кабинете на сайте.',
          actions: <Widget>[
            FilledButton.icon(
                onPressed: () => _open(context, _cabinetUrl),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Открыть кабинет')),
            OutlinedButton.icon(
                onPressed: () => _open(context, _botUrl),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Telegram-бот')),
          ],
        ),
        const SizedBox(height: 16),
        _ActionsCard(
          icon: Icons.person_outline_rounded,
          title: 'Аккаунт',
          text: profile == null
              ? 'Купите подписку на сайте, затем добавьте ссылку из личного кабинета («Скопировать ссылку»).'
              : 'Подписка «${profile.name}» сохранена на этом устройстве в защищённом хранилище.',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => _open(context, _siteUrl),
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('Тарифы')),
            OutlinedButton.icon(
                onPressed: () => _open(context, _botUrl),
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: const Text('Поддержка')),
          ],
        ),
        const SizedBox(height: 20),
        Center(
            child: Text('© KAGO · usekago.net',
                style: TextStyle(color: p.muted, fontSize: 12))),
      ],
    );
  }

  static Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final profile = await SubscriptionRepository().refreshUsage();
      ref.invalidate(importedSubscriptionProvider);
      messenger.showSnackBar(SnackBar(
          content: Text(profile == null
              ? 'Сервер не прислал данные о трафике.'
              : 'Данные подписки обновлены.')));
    } catch (error) {
      messenger.showSnackBar(
          SnackBar(content: Text('Не удалось обновить подписку: $error')));
    }
  }

  static Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
            .catchError((Object _) => false);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Откройте $url')));
    }
  }
}

/// Days left, "∞" for open-ended plans (the site shows ∞ for 2099).
String remainingLabel(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return '∞';
  final days = expiresAt.difference(now).inHours / 24;
  if (days > 3650) return '∞';
  if (days <= 0) return '0 дн.';
  return '${days.ceil()} дн.';
}

String formatRussianDate(DateTime date) {
  const months = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year} г.';
}

class _SubscriptionHero extends StatelessWidget {
  const _SubscriptionHero({
    required this.profile,
    required this.connected,
    required this.onConnect,
    required this.onAdd,
    required this.onRefresh,
  });
  final ImportedSubscription? profile;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onAdd;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final item = profile;
    final now = DateTime.now();
    final expired = item?.expiresAt != null && item!.expiresAt!.isBefore(now);
    final String status;
    final Color statusColor;
    if (item == null) {
      status = 'Нет подписки';
      statusColor = p.heroMuted;
    } else if (expired) {
      status = 'Истекла';
      statusColor = const Color(0xFFFF9B9B);
    } else {
      status = connected ? 'Подключено' : 'Активна';
      statusColor = const Color(0xFF5BE49B);
    }
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[p.heroStart, p.heroEnd]),
        boxShadow: light
            ? <BoxShadow>[
                BoxShadow(
                    color: p.heroStart.withValues(alpha: .25),
                    blurRadius: 24,
                    offset: const Offset(0, 10)),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: <Widget>[
        // The teal glow in the lower half of the site's card.
        Positioned(
          left: -40,
          bottom: -90,
          child: Container(
            width: 260,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: <Color>[
                p.heroGlow.withValues(alpha: .45),
                p.heroGlow.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Pill(
                  label: status,
                  color: statusColor,
                  background: Colors.white.withValues(alpha: .1),
                  border: statusColor.withValues(alpha: .45)),
              const SizedBox(height: 14),
              Text(item?.name ?? 'Подписка не добавлена',
                  style: TextStyle(
                      color: p.heroText,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4)),
              const SizedBox(height: 4),
              Text(
                  item == null
                      ? 'Добавьте ссылку из личного кабинета usekago.net'
                      : item.expiresAt == null
                          ? 'Бессрочно'
                          : '${expired ? 'Истекла' : 'Активна до'} ${formatRussianDate(item.expiresAt!)}',
                  style: TextStyle(color: p.heroMuted, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                FilledButton.icon(
                  onPressed: item == null ? onAdd : onConnect,
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: p.heroStart),
                  icon: Icon(
                      item == null
                          ? Icons.add_rounded
                          : connected
                              ? Icons.stop_rounded
                              : Icons.power_settings_new_rounded,
                      size: 18),
                  label: Text(item == null
                      ? 'Добавить подписку'
                      : connected
                          ? 'Отключиться'
                          : 'Подключиться'),
                ),
                if (item != null && item.url.isNotEmpty)
                  _HeroOutlinedButton(
                    icon: Icons.copy_rounded,
                    label: 'Скопировать ссылку',
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: item.url));
                      messenger.showSnackBar(const SnackBar(
                          content: Text(
                              'Ссылка скопирована. Это ваш ключ — не передавайте её посторонним.')));
                    },
                  ),
              ]),
              const SizedBox(height: 18),
              Builder(builder: (context) {
                final tiles = <Widget>[
                  _HeroStat(
                      label: 'Осталось',
                      value: item == null
                          ? '—'
                          : remainingLabel(item.expiresAt, now)),
                  _HeroStat(
                      label: 'Использовано',
                      value: item == null ? '—' : formatBytes(item.usedBytes)),
                  _HeroStat(
                      label: 'Трафик',
                      value: item == null
                          ? '—'
                          : item.totalBytes > 0
                              ? formatBytes(item.totalBytes)
                              : 'Безлимит'),
                ];
                return Row(children: <Widget>[
                  for (var i = 0; i < tiles.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: tiles[i]),
                  ],
                ]);
              }),
              if (onRefresh != null) ...<Widget>[
                const SizedBox(height: 16),
                Divider(color: Colors.white.withValues(alpha: .12), height: 1),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                  _HeroOutlinedButton(
                      icon: Icons.sync_rounded,
                      label: 'Обновить данные',
                      onPressed: onRefresh!),
                  _HeroOutlinedButton(
                      icon: Icons.key_rounded,
                      label: 'Перевыпустить ключ',
                      onPressed: () =>
                          AccountScreen._open(context, _cabinetUrl)),
                ]),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _HeroOutlinedButton extends StatelessWidget {
  const _HeroOutlinedButton(
      {required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: .06),
          side: BorderSide(color: Colors.white.withValues(alpha: .35)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label,
                  style:
                      TextStyle(color: context.kago.heroMuted, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard(
      {required this.icon,
      required this.title,
      required this.text,
      required this.actions});
  final IconData icon;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: p.accentSoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: p.accent, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge)),
          ]),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: p.muted, fontSize: 13.5)),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label,
      required this.color,
      required this.background,
      this.border});
  final String label;
  final Color color;
  final Color background;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}
