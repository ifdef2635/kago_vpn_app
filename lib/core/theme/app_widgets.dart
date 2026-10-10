import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import 'kago_theme.dart';

/// Where «Поддержка» leads: the subscription's `support-url` when it sends
/// one (as FlClashX), otherwise KAGO support in Telegram.
abstract final class SupportLink {
  static const fallback = 'https://t.me/KaGoHelp';
  static String current = fallback;
}

/// The only message at the bottom of the screen: a critical error (the VPN
/// did not connect, an account action failed…). Successes, progress and tips
/// are not announced (requested 2026-10-09). «Поддержка» opens the technical
/// [details] (to copy for support) and the support chat.
void showCriticalError(BuildContext context, String text, {String? details}) {
  final messenger = ScaffoldMessenger.of(context);
  // The messenger sits above the app's Navigator: the dialog needs the root
  // navigator (taken now — [context] may be gone when «Поддержка» is pressed).
  final navigator = Navigator.of(context, rootNavigator: true);
  final more = details?.trim() ?? '';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(text),
      action: SnackBarAction(
        label: tr('Поддержка'),
        onPressed: () => showDialog<void>(
          context: navigator.context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(Icons.support_agent_rounded,
                color: dialogContext.kago.accent),
            title: Text(text),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(tr(
                        'Напишите в поддержку KAGO — поможем разобраться. Приложите текст ошибки.')),
                    if (more.isNotEmpty && more != text) ...<Widget>[
                      const SizedBox(height: 12),
                      SelectableText(more,
                          style: TextStyle(
                              fontSize: 12, color: dialogContext.kago.muted)),
                    ],
                  ]),
            ),
            actions: <Widget>[
              if (more.isNotEmpty && more != text)
                TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: '$text\n$more')),
                    child: Text(tr('Копировать'))),
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(tr('Закрыть'))),
              FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    launchUrl(Uri.parse(SupportLink.current),
                            mode: LaunchMode.externalApplication)
                        .catchError((Object _) => false);
                  },
                  child: Text(tr('Написать'))),
            ],
          ),
        ),
      ),
    ));
}

/// The card of usekago.net: a white surface with a hairline border and the
/// soft shadow of `--color-shadow` (`.hero__status-card`).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(18),
      this.onTap,
      this.accent = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// The selected state of the site's cards (`.pp-card-desk--active`).
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final light = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(KaGoRadius.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: light && !accent ? context.kagoCardShadow : null,
      ),
      child: Material(
        color: accent ? p.accentSoft : p.surface,
        shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: accent ? p.accentTint : p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// A row inside a card (`.feature-card`): the quiet surface with a 2px light
/// border, used for device rows, list items and settings tiles.
class InsetTile extends StatelessWidget {
  const InsetTile(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      this.onTap,
      this.selected = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final radius = BorderRadius.circular(KaGoRadius.md);
    return Material(
      color: selected ? p.accentSoft : p.surfaceRaised,
      shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
              color: selected ? p.accentTint : p.borderLight, width: 2)),
      clipBehavior: Clip.antiAlias,
      child:
          InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// The tinted icon square of the site's cards (`.feature-card__icon`).
class IconChip extends StatelessWidget {
  const IconChip(this.icon,
      {super.key, this.size = 42, this.color, this.background, this.child});
  final IconData icon;
  final double size;
  final Color? color;
  final Color? background;

  /// Drawn instead of [icon] (a flag, a letter).
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: background ?? p.accentSoft,
          borderRadius: BorderRadius.circular(KaGoRadius.button)),
      child: child ?? Icon(icon, size: size * .5, color: color ?? p.accent),
    );
  }
}

/// The rounded label of the site (`.hero__badge`): a tinted pill with a thin
/// border, optionally with a status dot in front.
class KagoPill extends StatelessWidget {
  const KagoPill(this.label,
      {super.key, this.color, this.background, this.dot = false, this.icon});
  final String label;
  final Color? color;
  final Color? background;
  final bool dot;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final tone = color ?? p.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
          color: background ?? tone.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(KaGoRadius.pill),
          border: Border.all(color: tone.withValues(alpha: .28))),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (dot) ...<Widget>[StatusDot(color: tone), const SizedBox(width: 8)],
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
        ],
        Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: KaGoWeight.body, color: tone))),
      ]),
    );
  }
}

/// The status dot of the site (`.hero__status-dot`): a circle in a soft ring.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 10});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withValues(alpha: .2), spreadRadius: 3)
          ]));
}

/// A number with its caption (`.hero__metric`): the value in the accent
/// colour, the label below it.
class MetricValue extends StatelessWidget {
  const MetricValue(
      {super.key,
      required this.value,
      required this.label,
      this.color,
      this.size = 22});
  final String value;
  final String label;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: KaGoWeight.heading,
                  letterSpacing: -.4,
                  color: color ?? p.accent)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: KaGoWeight.body, color: p.muted)),
        ]);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final Widget? trailing;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Row(children: <Widget>[
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null)
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall)),
          ])),
      if (trailing != null) trailing!
    ]);
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => SurfaceCard(
          child: Row(children: <Widget>[
        Icon(Icons.wifi_off_rounded, color: context.kago.warning),
        const SizedBox(width: 12),
        Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall)),
        if (onRetry != null)
          IconButton(
              onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
      ]));
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});
  @override
  Widget build(BuildContext context) => const Center(
      child: Padding(
          padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
}

/// The KAGO mark (the penguin of usekago.net) — the same picture as the app
/// icon; generated from `assets/branding/kago-mark.svg` by `tool/make_icons.py`.
class KagoLogo extends StatelessWidget {
  const KagoLogo({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 28 / 120), // the mark's rx
        child: Image.asset(
          'assets/branding/kago_icon.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'KAGO',
        ),
      );
}

/// The site's lockup: the mark plus the «KAGO.» wordmark (`.kago-logo`).
class KagoWordmark extends StatelessWidget {
  const KagoWordmark({super.key, this.size = 34, this.subtitle});
  final double size;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final subtitle = this.subtitle;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      KagoLogo(size: size),
      SizedBox(width: size * .28),
      Flexible(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
            Text('KAGO.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: size * .55,
                    fontWeight: KaGoWeight.heading,
                    letterSpacing: -.5,
                    height: 1.1,
                    color: p.text)),
            if (subtitle != null)
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: size * .34,
                      fontWeight: KaGoWeight.body,
                      height: 1.3,
                      color: p.muted)),
          ])),
    ]);
  }
}
