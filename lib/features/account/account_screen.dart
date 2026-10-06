import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/mihomo_models.dart';
import '../../core/network/android_vpn_events.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../subscriptions/subscription_providers.dart';
import '../subscriptions/subscription_repository.dart';
import 'account_providers.dart';
import 'kago_api.dart';
import 'site_session_screen.dart';

const _plansUrl = '$kagoSiteUrl/plans';
const _cabinetUrl = '$kagoSiteUrl/my';
const _supportUrl = 'https://t.me/KaGoHelp';
const _botUrl = 'https://t.me/kagovpnbot';

/// Personal account, the same as usekago.net/my: sign in with the site's
/// email and password, then the subscription, devices, promo code, account
/// settings and referral program come from the site's API. A guest sees the
/// sign-in card and the subscription saved on this device.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(accountUserProvider);
    final p = context.kago;
    final wide = MediaQuery.sizeOf(context).width > 760;
    final signedIn = user.value;
    return RefreshIndicator(
      onRefresh: () async {
        refreshAccount(ref);
        ref.invalidate(importedSubscriptionProvider);
        await ref
            .read(accountUserProvider.future)
            .catchError((Object _) => null);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 44 : 20, 22, wide ? 44 : 20, 28),
        children: <Widget>[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Pill(
                        label: tr('Личный кабинет'),
                        color: p.success,
                        background: p.successSoft),
                    const SizedBox(height: 12),
                    Text(
                        signedIn == null
                            ? tr('Добро пожаловать')
                            : signedIn.name.isEmpty
                                ? tr('Здравствуйте!')
                                : tr('Здравствуйте, {name}',
                                    <String, Object?>{'name': signedIn.name}),
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                        tr('Управляйте подпиской, устройствами и аккаунтом в одном месте.'),
                        style: TextStyle(color: p.muted, fontSize: 14)),
                  ]),
            ),
            if (signedIn != null)
              OutlinedButton.icon(
                  onPressed: () => _logout(context, ref),
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: Text(tr('Выйти'))),
          ]),
          const SizedBox(height: 20),
          ...user.when(
            loading: () => <Widget>[const _HeroFrame(child: _HeroLoading())],
            error: (error, _) => <Widget>[
              ErrorPanel(message: '$error', onRetry: () => refreshAccount(ref)),
            ],
            data: (value) => value == null
                ? ref.watch(importedSubscriptionProvider).value == null
                    ? <Widget>[
                        const _LoginCard(),
                        const SizedBox(height: 16),
                        const _LocalSubscriptionHero(),
                      ]
                    // A subscription added by link already works: show it
                    // first and fold the sign-in form into one line.
                    : <Widget>[
                        const _LocalSubscriptionHero(),
                        const SizedBox(height: 16),
                        const _LoginCard(collapsed: true),
                      ]
                : <Widget>[
                    const _AccountHero(),
                    const SizedBox(height: 16),
                    const _DevicesCard(),
                    const SizedBox(height: 16),
                    const _PromoCard(),
                    const SizedBox(height: 16),
                    _ProfileCard(user: value),
                    const SizedBox(height: 16),
                    _ReferralCard(user: value),
                  ],
          ),
          const SizedBox(height: 16),
          const _HelpCard(),
          const SizedBox(height: 20),
          Center(
              child: Text('© KAGO · usekago.net',
                  style: TextStyle(color: p.muted, fontSize: 12))),
        ],
      ),
    );
  }

  static Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(kagoApiProvider).logout();
    await SiteSessionScreen.clearWebSession();
    refreshAccount(ref);
    if (context.mounted) showSnack(context, tr('Вы вышли из аккаунта.'));
  }
}

// ─── Helpers ────────────────────────────────────────────────────

void showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String _errorText(Object error) =>
    error is KagoApiException ? error.message : '$error';

Future<void> openUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok =
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
          .catchError((Object _) => false);
  if (!ok) {
    messenger.showSnackBar(SnackBar(
        content: Text(tr('Откройте {url}', <String, Object?>{'url': url}))));
  }
}

Future<bool> _confirm(BuildContext context, String title, String text,
    {required String action, bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('Отмена'))),
        FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: dialogContext.kago.danger)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

/// Days left, "∞" for open-ended plans (the site shows ∞ for 2099).
String remainingLabel(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null || expiresAt.year >= 2099) return '∞';
  final days = expiresAt.difference(now).inHours / 24;
  if (days > 3650) return '∞';
  if (days <= 0) return tr('{n} дн.', const <String, Object?>{'n': 0});
  return tr('{n} дн.', <String, Object?>{'n': days.ceil()});
}

/// Imports [url] as this device's subscription unless it already is.
Future<void> useOnThisDevice(WidgetRef ref, String url) async {
  final current = await SubscriptionRepository().latest();
  if (current?.url == url) return;
  await SubscriptionRepository().import(url);
  ref.invalidate(importedSubscriptionProvider);
  ref.invalidate(proxyGroupsProvider);
}

bool _vpnOn(WidgetRef ref) {
  final desktop = ref.watch(desktopCoreRunningProvider);
  final android = Platform.isAndroid &&
      ref.watch(androidVpnEventProvider
          .select((event) => event.value?['state'] == 'connected'));
  return desktop || android;
}

bool _androidVpnOn(WidgetRef ref) =>
    Platform.isAndroid &&
    ref.read(androidVpnEventProvider).value?['state'] == 'connected';

// ─── Sign in / register ────────────────────────────────────────

class _LoginCard extends ConsumerStatefulWidget {
  const _LoginCard({this.collapsed = false});

  /// Start as a one-line "sign in" row that opens the form on tap.
  final bool collapsed;
  @override
  ConsumerState<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends ConsumerState<_LoginCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidden = true;
  late bool _collapsed = widget.collapsed;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showSnack(context, tr('Введите корректный email.'));
      return;
    }
    if (_register && password.length < 8) {
      showSnack(context, tr('Пароль — минимум 8 символов.'));
      return;
    }
    if (password.isEmpty) {
      showSnack(context, tr('Введите пароль.'));
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(kagoApiProvider);
    try {
      if (_register) {
        await api.register(email, password, name: _name.text);
      } else {
        await api.login(email, password);
      }
      await _afterSignIn();
    } catch (error) {
      if (mounted) showSnack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sets up this device right away when it has no subscription yet.
  Future<void> _afterSignIn() async {
    final api = ref.read(kagoApiProvider);
    final sub = await api.subscription().catchError((Object _) => null);
    var imported = false;
    if (sub != null && sub.isActive && sub.url.isNotEmpty) {
      final local = await SubscriptionRepository().latest();
      if (local == null) {
        await useOnThisDevice(ref, sub.url).catchError((Object _) {});
        imported = true;
      }
    }
    refreshAccount(ref);
    if (mounted) {
      showSnack(
          context,
          imported
              ? tr('Вы вошли. Подписка добавлена на это устройство.')
              : tr('Вы вошли в аккаунт.'));
    }
  }

  Future<void> _telegram() async {
    setState(() => _busy = true);
    try {
      final ok = await SiteSessionScreen.open(context, SiteSessionMode.login,
          api: ref.read(kagoApiProvider));
      if (ok) await _afterSignIn();
    } catch (error) {
      if (mounted) showSnack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('Забыли пароль?')),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(tr('Вы регистрировались раньше и пароль не задавали'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tr(
                    'Зарегистрируйтесь с той же почтой — аккаунт и подписка сохранятся.')),
                const SizedBox(height: 14),
                Text(tr('Пароль был, но вы его забыли'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tr('Напишите в поддержку — поможем восстановить доступ.')),
              ]),
          actions: <Widget>[
            TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  setState(() => _register = true);
                },
                child: Text(tr('Регистрация'))),
            FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  openUrl(context, _supportUrl);
                },
                child: Text(tr('Поддержка'))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    if (_collapsed) {
      return SurfaceCard(
        onTap: () => setState(() => _collapsed = false),
        child: Row(children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: p.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.person_outline_rounded, color: p.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(tr('Войти в аккаунт KAGO'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(tr('Устройства, промокоды и продление — в приложении'),
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.all(22),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_register ? tr('Регистрация') : tr('Вход'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
                _register
                    ? tr('Создайте аккаунт KAGO')
                    : tr('Войдите в личный кабинет KAGO'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 18),
            if (!_register) ...<Widget>[
              // Telegram first: most accounts were created by the bot.
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: telegramBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                onPressed: _busy ? null : _telegram,
                icon: const Icon(Icons.telegram, size: 22),
                label: Text(tr('Войти через Telegram')),
              ),
              const SizedBox(height: 16),
              Row(children: <Widget>[
                Expanded(child: Divider(color: p.border)),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(tr('или по email'),
                        style: TextStyle(color: p.muted, fontSize: 12))),
                Expanded(child: Divider(color: p.border)),
              ]),
              const SizedBox(height: 16),
            ],
            if (_register) ...<Widget>[
              TextField(
                  controller: _name,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.name],
                  decoration:
                      InputDecoration(labelText: tr('Имя (необязательно)'))),
              const SizedBox(height: 12),
            ],
            TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
                decoration: const InputDecoration(
                    labelText: 'Email', hintText: 'example@mail.ru')),
            const SizedBox(height: 12),
            TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _hidden,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                autofillHints: <String>[
                  _register ? AutofillHints.newPassword : AutofillHints.password
                ],
                decoration: InputDecoration(
                  labelText: _register
                      ? tr('Пароль (минимум 8 символов)')
                      : tr('Пароль'),
                  suffixIcon: IconButton(
                      tooltip:
                          _hidden ? tr('Показать пароль') : tr('Скрыть пароль'),
                      onPressed: () => setState(() => _hidden = !_hidden),
                      icon: Icon(_hidden
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded)),
                )),
            const SizedBox(height: 16),
            FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_register ? tr('Зарегистрироваться') : tr('Войти'))),
            const SizedBox(height: 10),
            Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                      _register ? tr('Уже есть аккаунт?') : tr('Нет аккаунта?'),
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _register = !_register),
                      child: Text(
                          _register ? tr('Войти') : tr('Зарегистрироваться'))),
                ]),
            if (!_register)
              TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: Text(tr('Забыли пароль?'))),
          ],
        ),
      ),
    );
  }
}

// ─── Subscription hero ─────────────────────────────────────────

/// The navy card of usekago.net/my with its blue and green glows.
class _HeroFrame extends StatelessWidget {
  const _HeroFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const <double>[0, .55, 1.35],
            colors: <Color>[p.heroStart, p.heroEnd, p.heroAccent]),
        boxShadow: light
            ? <BoxShadow>[
                BoxShadow(
                    color: const Color(0xFF14285A).withValues(alpha: .12),
                    blurRadius: 40,
                    offset: const Offset(0, 14)),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: <Widget>[
        Positioned(
            top: -90,
            right: -60,
            child: _Blob(color: p.heroBlob, size: 300, alpha: .45)),
        Positioned(
            bottom: -120,
            left: 90,
            child: _Blob(color: p.heroGlow, size: 260, alpha: .22)),
        Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20), child: child),
      ]),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size, required this.alpha});
  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(stops: const <double>[
              0,
              .65
            ], colors: <Color>[
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ]),
          ),
        ),
      );
}

class _HeroLoading extends StatelessWidget {
  const _HeroLoading();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 180,
      child: Center(child: CircularProgressIndicator(color: Colors.white)));
}

/// The subscription from the account: status, expiry, devices, traffic and
/// the actions of the site (connect, copy link, renew, re-issue the key).
class _AccountHero extends ConsumerStatefulWidget {
  const _AccountHero();
  @override
  ConsumerState<_AccountHero> createState() => _AccountHeroState();
}

class _AccountHeroState extends ConsumerState<_AccountHero> {
  bool _busy = false;

  Future<void> _connect(KagoSubscription sub) async {
    setState(() => _busy = true);
    try {
      await useOnThisDevice(ref, sub.url);
      if (!mounted) return;
      await DashboardScreen.toggleVpn(context, ref, _androidVpnOn(ref));
    } catch (error) {
      if (mounted) showSnack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reissue(KagoSubscription sub) async {
    final ok = await _confirm(context, tr('Перевыпустить ключ?'),
        tr('Старая ссылка перестанет работать. На этом устройстве подписка обновится автоматически, на остальных её нужно добавить заново.'),
        action: tr('Перевыпустить'), danger: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final api = ref.read(kagoApiProvider);
    try {
      final usedHere =
          (await SubscriptionRepository().latest())?.url == sub.url;
      await api.reissue();
      final fresh = await api.subscription();
      if (usedHere && fresh != null && fresh.url.isNotEmpty) {
        await useOnThisDevice(ref, fresh.url);
      }
      refreshAccount(ref);
      if (mounted) showSnack(context, tr('Ключ перевыпущен.'));
    } catch (error) {
      if (mounted) showSnack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(accountSubscriptionProvider);
    final devices = ref.watch(accountDevicesProvider).value;
    final local = ref.watch(importedSubscriptionProvider).value;
    final vpnOn = _vpnOn(ref);
    return _HeroFrame(
      child: subscription.when(
        loading: () => const _HeroLoading(),
        error: (error, _) => _HeroMessage(
            title: tr('Не удалось загрузить подписку'),
            text: _errorText(error),
            actions: <Widget>[
              _HeroButton(
                  icon: Icons.refresh_rounded,
                  label: tr('Повторить'),
                  onPressed: () => ref.invalidate(accountSubscriptionProvider)),
            ]),
        data: (sub) {
          if (sub == null || !sub.isActive) {
            final expired = sub != null;
            return _HeroMessage(
              pill: tr('Подписка неактивна'),
              pillColor: const Color(0xFFFFB4B4),
              title: expired
                  ? tr('Срок подписки истёк')
                  : tr('Защита пока выключена'),
              text: expired
                  ? tr(
                      'Продлите подписку — доступ к серверам и защита ваших устройств вернутся сразу после оплаты.')
                  : tr(
                      'Оформите подписку и получите доступ к серверам на скорости до 1 Гбит/с и защите до 5 устройств.'),
              actions: <Widget>[
                _HeroButton(
                    primary: true,
                    icon: Icons.bolt_rounded,
                    label: expired ? tr('Продлить') : tr('Выбрать тариф'),
                    onPressed: () =>
                        openUrl(context, expired ? _cabinetUrl : _plansUrl)),
                _HeroButton(
                    icon: Icons.compare_arrows_rounded,
                    label: tr('Сравнить тарифы'),
                    onPressed: () => openUrl(context, _plansUrl)),
              ],
            );
          }
          final onThisDevice = local?.url == sub.url;
          final now = DateTime.now();
          final daysLeft = sub.expireAt?.difference(now).inHours;
          final expiringSoon =
              !sub.isLifetime && daysLeft != null && daysLeft <= 7 * 24;
          final deviceMax = devices?.max ?? sub.deviceLimit;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Pill(
                  label:
                      vpnOn && onThisDevice ? tr('Подключено') : tr('Активна'),
                  color: const Color(0xFF5BE49B),
                  background: Colors.white.withValues(alpha: .1),
                  border: const Color(0xFF5BE49B).withValues(alpha: .45)),
              const SizedBox(height: 14),
              Text(sub.planName.isEmpty ? 'KAGO' : sub.planName,
                  style: TextStyle(
                      color: context.kago.heroText,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4)),
              const SizedBox(height: 4),
              Text(
                  [
                    if (sub.expireAt != null)
                      tr('Активна до {date}', <String, Object?>{
                        'date': formatLongDate(sub.expireAt!)
                      }),
                    if (sub.isTrial) tr('Пробный период'),
                  ].join(' · '),
                  style:
                      TextStyle(color: context.kago.heroMuted, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                _HeroButton(
                  primary: true,
                  busy: _busy,
                  icon: vpnOn && onThisDevice
                      ? Icons.stop_rounded
                      : Icons.power_settings_new_rounded,
                  label: !onThisDevice
                      ? tr('Подключить это устройство')
                      : vpnOn
                          ? tr('Отключиться')
                          : tr('Подключиться'),
                  onPressed: _busy ? null : () => _connect(sub),
                ),
                _HeroButton(
                  icon: Icons.copy_rounded,
                  label: tr('Скопировать ссылку'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: sub.url));
                    if (context.mounted) {
                      showSnack(context,
                          tr('Ссылка скопирована. Это ваш ключ — не передавайте её посторонним.'));
                    }
                  },
                ),
              ]),
              const SizedBox(height: 18),
              Row(children: <Widget>[
                Expanded(
                    child: _HeroStat(
                        label: tr('Осталось'),
                        value: remainingLabel(sub.expireAt, now),
                        warn: expiringSoon)),
                const SizedBox(width: 10),
                Expanded(
                    child: _HeroStat(
                        label: tr('Устройств'),
                        value:
                            '${devices?.current ?? 0} / ${deviceMax > 0 ? deviceMax : '∞'}')),
                const SizedBox(width: 10),
                Expanded(
                    child: _HeroStat(
                        label: tr('Трафик'),
                        value: sub.trafficLimitGb > 0
                            ? '${formatBytes(sub.usedTrafficBytes ?? 0)} / ${sub.trafficLimitGb} ${tr('ГБ')}'
                            : tr('Безлимит'))),
              ]),
              if (sub.trafficLimitGb > 0) ...<Widget>[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: ((sub.usedTrafficBytes ?? 0) /
                            (sub.trafficLimitGb * 1e9))
                        .clamp(0, 1)
                        .toDouble(),
                    backgroundColor: Colors.white.withValues(alpha: .12),
                    color: Colors.white,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: .12), height: 1),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                if (!sub.isLifetime)
                  _HeroButton(
                      primary: expiringSoon,
                      icon: Icons.bolt_rounded,
                      label: sub.isTrial
                          ? tr('Оформить подписку')
                          : tr('Продлить'),
                      onPressed: () => openUrl(
                          context, sub.isTrial ? _plansUrl : _cabinetUrl)),
                _HeroButton(
                    icon: Icons.key_rounded,
                    label: tr('Перевыпустить ключ'),
                    onPressed: _busy ? null : () => _reissue(sub)),
              ]),
            ],
          );
        },
      ),
    );
  }
}

/// A guest: the subscription saved on this device (from its link's
/// `subscription-userinfo` header).
class _LocalSubscriptionHero extends ConsumerWidget {
  const _LocalSubscriptionHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(importedSubscriptionProvider).value;
    final vpnOn = _vpnOn(ref);
    final p = context.kago;
    if (item == null) {
      return _HeroFrame(
        child: _HeroMessage(
          pill: tr('На этом устройстве'),
          pillColor: p.heroMuted,
          title: tr('Подписка не добавлена'),
          text: tr(
              'Войдите в аккаунт — подписка добавится автоматически. Или вставьте ссылку из личного кабинета.'),
          actions: <Widget>[
            _HeroButton(
                primary: true,
                icon: Icons.add_rounded,
                label: tr('Добавить по ссылке'),
                onPressed: () =>
                    DashboardScreen.showAddSubscription(context, ref)),
            _HeroButton(
                icon: Icons.sell_outlined,
                label: tr('Тарифы'),
                onPressed: () => openUrl(context, _plansUrl)),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final expired = item.expiresAt != null && item.expiresAt!.isBefore(now);
    return _HeroFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Pill(
              label: expired
                  ? tr('Истекла')
                  : vpnOn
                      ? tr('Подключено')
                      : tr('На этом устройстве'),
              color:
                  expired ? const Color(0xFFFFB4B4) : const Color(0xFF5BE49B),
              background: Colors.white.withValues(alpha: .1)),
          const SizedBox(height: 14),
          Text(item.name,
              style: TextStyle(
                  color: p.heroText,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              item.expiresAt == null
                  ? tr('Бессрочно')
                  : expired
                      ? tr('Истекла {date}', <String, Object?>{
                          'date': formatLongDate(item.expiresAt!)
                        })
                      : tr('Активна до {date}', <String, Object?>{
                          'date': formatLongDate(item.expiresAt!)
                        }),
              style: TextStyle(color: p.heroMuted, fontSize: 13)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
            _HeroButton(
                primary: true,
                icon: vpnOn
                    ? Icons.stop_rounded
                    : Icons.power_settings_new_rounded,
                label: vpnOn ? tr('Отключиться') : tr('Подключиться'),
                onPressed: () => DashboardScreen.toggleVpn(
                    context, ref, _androidVpnOn(ref))),
            _HeroButton(
                icon: Icons.sync_rounded,
                label: tr('Обновить данные'),
                onPressed: () async {
                  try {
                    await SubscriptionRepository().refreshUsage();
                    ref.invalidate(importedSubscriptionProvider);
                    if (context.mounted) {
                      showSnack(context, tr('Данные подписки обновлены.'));
                    }
                  } catch (error) {
                    if (context.mounted) showSnack(context, _errorText(error));
                  }
                }),
          ]),
          const SizedBox(height: 18),
          Row(children: <Widget>[
            Expanded(
                child: _HeroStat(
                    label: tr('Осталось'),
                    value: remainingLabel(item.expiresAt, now))),
            const SizedBox(width: 10),
            Expanded(
                child: _HeroStat(
                    label: tr('Использовано'),
                    value: formatBytes(item.usedBytes))),
            const SizedBox(width: 10),
            Expanded(
                child: _HeroStat(
                    label: tr('Трафик'),
                    value: item.totalBytes > 0
                        ? formatBytes(item.totalBytes)
                        : tr('Безлимит'))),
          ]),
        ],
      ),
    );
  }
}

class _HeroMessage extends StatelessWidget {
  const _HeroMessage(
      {required this.title,
      required this.text,
      required this.actions,
      this.pill,
      this.pillColor});
  final String? pill;
  final Color? pillColor;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (pill != null) ...<Widget>[
            _Pill(
                label: pill!,
                color: pillColor ?? Colors.white,
                background: Colors.white.withValues(alpha: .1)),
            const SizedBox(height: 14),
          ],
          Text(title,
              style: TextStyle(
                  color: context.kago.heroText,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(color: context.kago.heroMuted, fontSize: 13.5)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      );
}

class _HeroButton extends StatelessWidget {
  const _HeroButton(
      {required this.icon,
      required this.label,
      required this.onPressed,
      this.primary = false,
      this.busy = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final iconWidget = busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primary ? context.kago.heroStart : Colors.white))
        : Icon(icon, size: 18);
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: context.kago.heroStart,
            disabledBackgroundColor: Colors.white.withValues(alpha: .7),
            disabledForegroundColor: context.kago.heroStart),
        icon: iconWidget,
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: .06),
        side: BorderSide(color: Colors.white.withValues(alpha: .35)),
      ),
      icon: iconWidget,
      label: Text(label),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(
      {required this.label, required this.value, this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: warn
              ? const Color(0xFFF59E0B).withValues(alpha: .14)
              : Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: warn
                  ? const Color(0xFFF59E0B).withValues(alpha: .4)
                  : Colors.white.withValues(alpha: .12)),
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

// ─── Cards ─────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card(
      {required this.icon,
      required this.title,
      required this.child,
      this.trailing});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
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
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: context.kago.accentSoft,
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                color: context.kago.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );
}

class _DevicesCard extends ConsumerStatefulWidget {
  const _DevicesCard();
  @override
  ConsumerState<_DevicesCard> createState() => _DevicesCardState();
}

class _DevicesCardState extends ConsumerState<_DevicesCard> {
  String? _busy;

  Future<void> _remove(KagoDevice? device) async {
    if (device == null) {
      final ok = await _confirm(context, tr('Отключить все устройства?'),
          tr('Все устройства потеряют доступ, пока снова не подключатся по ссылке.'),
          action: tr('Отключить все'), danger: true);
      if (!ok) return;
    }
    setState(() => _busy = device?.hwid ?? '*');
    final api = ref.read(kagoApiProvider);
    try {
      if (device == null) {
        await api.deleteAllDevices();
      } else {
        await api.deleteDevice(device.hwid);
      }
      ref.invalidate(accountDevicesProvider);
      if (mounted) {
        showSnack(
            context,
            device == null
                ? tr('Все устройства отключены.')
                : tr('Устройство отключено.'));
      }
    } catch (error) {
      if (mounted) showSnack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static IconData _icon(KagoDevice device) {
    final platform = (device.platform ?? '').toLowerCase();
    if (platform.contains('android') || platform.contains('ios')) {
      return Icons.smartphone_rounded;
    }
    if (platform.contains('mac') ||
        platform.contains('windows') ||
        platform.contains('linux')) {
      return Icons.computer_rounded;
    }
    return Icons.devices_other_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(accountDevicesProvider);
    final p = context.kago;
    final value = data.value;
    return _Card(
      icon: Icons.devices_rounded,
      title: tr('Устройства'),
      trailing: value == null
          ? null
          : _Chip('${value.current} / ${value.max > 0 ? value.max : '∞'}'),
      child: data.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (error, _) =>
            Text(_errorText(error), style: TextStyle(color: p.muted)),
        data: (devices) {
          if (devices == null || devices.devices.isEmpty) {
            return Text(
                tr('Устройств пока нет. Устройство появится здесь после первого подключения по ссылке подписки.'),
                style: TextStyle(color: p.muted, fontSize: 13));
          }
          return Column(children: <Widget>[
            for (final device in devices.devices)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(
                    color: p.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.border)),
                child: Row(children: <Widget>[
                  Icon(_icon(device), color: p.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                              device.model?.isNotEmpty == true
                                  ? device.model!
                                  : device.platform ?? tr('Устройство'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                              [device.platform, device.osVersion]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' · ')
                                      .isEmpty
                                  ? device.hwid.substring(
                                      0, device.hwid.length.clamp(0, 12))
                                  : [device.platform, device.osVersion]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 12)),
                        ]),
                  ),
                  _busy == device.hwid
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          tooltip: tr('Отключить'),
                          onPressed:
                              _busy != null ? null : () => _remove(device),
                          icon: Icon(Icons.delete_outline_rounded,
                              color: p.danger)),
                ]),
              ),
            if (devices.devices.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: p.danger),
                    onPressed: _busy != null ? null : () => _remove(null),
                    child: Text(tr('Отключить все'))),
              ),
          ]);
        },
      ),
    );
  }
}

class _PromoCard extends ConsumerStatefulWidget {
  const _PromoCard();
  @override
  ConsumerState<_PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends ConsumerState<_PromoCard> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(kagoApiProvider).activatePromocode(_code.text);
      _code.clear();
      ref.invalidate(accountSubscriptionProvider);
      if (mounted) showSnack(context, tr('Промокод активирован.'));
    } catch (error) {
      if (mounted) showSnack(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Card(
        icon: Icons.sell_outlined,
        title: tr('Промокод'),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(tr('Есть код? Активируйте его и получите бонус к подписке.'),
                  style: TextStyle(color: context.kago.muted, fontSize: 13)),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(
                  child: TextField(
                      controller: _code,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _activate(),
                      decoration: InputDecoration(
                          hintText: tr('Введите код'), isDense: true)),
                ),
                const SizedBox(width: 10),
                FilledButton(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                    onPressed: _busy ? null : _activate,
                    child: Text(tr('Активировать'))),
              ]),
            ]),
      );
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.user});
  final KagoUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.kago;
    Widget row(IconData icon, String label, String value, Widget? badge) =>
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(
              color: p.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.border)),
          child: Row(children: <Widget>[
            Icon(icon, color: p.muted, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
                    Text(value,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
            ),
            if (badge != null) badge,
          ]),
        );
    Widget badge(bool ok, String yes, String no) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: ok ? p.successSoft : p.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: ok ? p.success.withValues(alpha: .35) : p.border)),
          child: Text(ok ? '✓ $yes' : no,
              style: TextStyle(
                  color: ok ? p.success : p.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        );
    return _Card(
      icon: Icons.person_outline_rounded,
      title: tr('Аккаунт'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          row(
              Icons.mail_outline_rounded,
              'Email',
              user.email ?? tr('Не указан'),
              user.email == null
                  ? null
                  : badge(user.isEmailVerified, tr('Подтверждён'),
                      tr('Не подтверждён'))),
          if (user.pendingEmail != null)
            row(
                Icons.mark_email_unread_outlined,
                tr('Новый email (ожидает подтверждения)'),
                user.pendingEmail!,
                null),
          row(
              Icons.send_rounded,
              'Telegram',
              user.telegramId != null
                  ? (user.username != null ? '@${user.username}' : user.name)
                  : '—',
              badge(user.telegramId != null, tr('Подключен'),
                  tr('Не подключен'))),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
            OutlinedButton.icon(
                onPressed: () => _changePassword(context, ref),
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: Text(tr('Сменить пароль'))),
            OutlinedButton.icon(
                onPressed: () => _changeEmail(context, ref),
                icon: const Icon(Icons.mail_outline_rounded, size: 18),
                label: Text(tr('Сменить email'))),
            if (user.pendingEmail != null)
              OutlinedButton(
                  onPressed: () => _verify(context, ref, user.pendingEmail),
                  child: Text(tr('Подтвердить новый email'))),
            if (user.email != null && !user.isEmailVerified)
              OutlinedButton(
                  onPressed: () => _verify(context, ref, null),
                  child: Text(tr('Подтвердить email'))),
          ]),
          if (user.telegramId == null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
                tr('Привяжите Telegram, чтобы входить через бота и в приложении.'),
                style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: telegramBlue),
              onPressed: () async {
                await SiteSessionScreen.open(context, SiteSessionMode.cabinet,
                    api: ref.read(kagoApiProvider));
                refreshAccount(ref);
              },
              icon: const Icon(Icons.telegram, size: 20),
              label: Text(tr('Привязать Telegram')),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _changePassword(
      BuildContext context, WidgetRef ref) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FormDialog(
        title: tr('Сменить пароль'),
        action: tr('Сохранить'),
        fields: <_Field>[
          _Field(tr('Текущий пароль'), obscure: true),
          _Field(tr('Новый пароль (мин. 8)'), obscure: true),
        ],
      ),
    );
    if (values == null || !context.mounted) return;
    if (values[1].length < 8) {
      showSnack(context, tr('Новый пароль — минимум 8 символов.'));
      return;
    }
    try {
      await ref.read(kagoApiProvider).changePassword(values[0], values[1]);
      if (context.mounted) showSnack(context, tr('Пароль изменён.'));
    } catch (error) {
      if (context.mounted) showSnack(context, _errorText(error));
    }
  }

  static Future<void> _changeEmail(BuildContext context, WidgetRef ref) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FormDialog(
        title: tr('Сменить email'),
        action: tr('Отправить код'),
        fields: <_Field>[_Field(tr('Новый email'), email: true)],
      ),
    );
    if (values == null || values.first.trim().isEmpty || !context.mounted) {
      return;
    }
    final api = ref.read(kagoApiProvider);
    try {
      final pending = await api.changeEmail(values.first);
      await api.requestEmailVerification(pending);
      ref.invalidate(accountUserProvider);
      if (context.mounted) {
        showSnack(
            context,
            tr('Код отправлен на {email}',
                <String, Object?>{'email': pending}));
        await _enterCode(context, ref, tr('Email обновлён.'));
      }
    } catch (error) {
      if (context.mounted) showSnack(context, _errorText(error));
    }
  }

  static Future<void> _verify(
      BuildContext context, WidgetRef ref, String? email) async {
    try {
      await ref.read(kagoApiProvider).requestEmailVerification(email);
      if (context.mounted) {
        showSnack(context, tr('Код отправлен на email.'));
        await _enterCode(context, ref,
            email == null ? tr('Email подтверждён.') : tr('Email обновлён.'));
      }
    } catch (error) {
      if (context.mounted) showSnack(context, _errorText(error));
    }
  }

  static Future<void> _enterCode(
      BuildContext context, WidgetRef ref, String done) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FormDialog(
        title: tr('Код из письма'),
        action: tr('Подтвердить'),
        fields: <_Field>[_Field(tr('6 цифр'), numeric: true)],
      ),
    );
    if (values == null || values.first.trim().length != 6 || !context.mounted) {
      return;
    }
    try {
      await ref.read(kagoApiProvider).confirmEmail(values.first);
      refreshAccount(ref);
      if (context.mounted) showSnack(context, done);
    } catch (error) {
      if (context.mounted) showSnack(context, _errorText(error));
    }
  }
}

class _ReferralCard extends ConsumerWidget {
  const _ReferralCard({required this.user});
  final KagoUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(accountReferralProvider);
    final p = context.kago;
    return _Card(
      icon: Icons.card_giftcard_rounded,
      title: tr('Реферальная программа'),
      child: data.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (error, _) =>
            Text(_errorText(error), style: TextStyle(color: p.muted)),
        data: (referral) {
          if (referral == null || !referral.enabled) {
            return Text(tr('Программа сейчас недоступна.'),
                style: TextStyle(color: p.muted));
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                    tr('Приглашайте друзей по своей ссылке. За каждого, кто оформит подписку, вы оба получите +30 дней бесплатно.'),
                    style: TextStyle(color: p.muted, fontSize: 13)),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(
                      child: _Counter(
                          value: referral.invited, label: tr('Приглашено'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _Counter(
                          value: referral.paid,
                          label: tr('Оплатили'),
                          success: true)),
                ]),
                const SizedBox(height: 12),
                if (user.isEmailVerified)
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    decoration: BoxDecoration(
                        color: p.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.border)),
                    child: Row(children: <Widget>[
                      Expanded(
                          child: SelectableText(referral.link,
                              style: const TextStyle(fontSize: 13))),
                      IconButton(
                          tooltip: tr('Копировать'),
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: referral.link));
                            if (context.mounted) {
                              showSnack(context, tr('Скопировано.'));
                            }
                          },
                          icon: Icon(Icons.copy_rounded, color: p.accent)),
                    ]),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: p.accentSoft,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(
                        tr('Реферальная программа доступна после подтверждения почты. Подтвердите email в разделе «Аккаунт» выше.'),
                        style: TextStyle(color: p.text, fontSize: 13)),
                  ),
              ]);
        },
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter(
      {required this.value, required this.label, this.success = false});
  final int value;
  final String label;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          color: success ? p.successSoft : p.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: success ? p.success.withValues(alpha: .3) : p.border)),
      child: Column(children: <Widget>[
        Text('$value',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: success ? p.success : p.text)),
        Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
      ]),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) => _Card(
        icon: Icons.support_agent_rounded,
        title: tr('Помощь'),
        child: Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
          OutlinedButton.icon(
              onPressed: () => openUrl(context, _supportUrl),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(tr('Поддержка'))),
          OutlinedButton.icon(
              onPressed: () => openUrl(context, _botUrl),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(tr('Telegram-бот'))),
          OutlinedButton.icon(
              onPressed: () => openUrl(context, _plansUrl),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text(tr('Тарифы'))),
          OutlinedButton.icon(
              onPressed: () => openUrl(context, '$kagoSiteUrl/faq'),
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: const Text('FAQ')),
        ]),
      );
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

class _Field {
  const _Field(this.label,
      {this.obscure = false, this.email = false, this.numeric = false});
  final String label;
  final bool obscure;
  final bool email;
  final bool numeric;
}

/// A small form in a dialog; returns the entered values, or null on cancel.
class _FormDialog extends StatefulWidget {
  const _FormDialog(
      {required this.title, required this.action, required this.fields});
  final String title;
  final String action;
  final List<_Field> fields;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  late final List<TextEditingController> _controllers = <TextEditingController>[
    for (final _ in widget.fields) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _done() => Navigator.of(context)
      .pop(_controllers.map((controller) => controller.text).toList());

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          for (var i = 0; i < widget.fields.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 12),
            TextField(
              controller: _controllers[i],
              autofocus: i == 0,
              obscureText: widget.fields[i].obscure,
              maxLength: widget.fields[i].numeric ? 6 : null,
              keyboardType: widget.fields[i].numeric
                  ? TextInputType.number
                  : widget.fields[i].email
                      ? TextInputType.emailAddress
                      : TextInputType.text,
              inputFormatters: widget.fields[i].numeric
                  ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
                  : null,
              onSubmitted:
                  i == widget.fields.length - 1 ? (_) => _done() : null,
              decoration: InputDecoration(labelText: widget.fields[i].label),
            ),
          ],
        ]),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Отмена'))),
          FilledButton(onPressed: _done, child: Text(widget.action)),
        ],
      );
}
