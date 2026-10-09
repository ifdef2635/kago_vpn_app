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

class SurfaceCard extends StatelessWidget {
  const SurfaceCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(18),
      this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final light = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(18);
    // White card with a hairline border and a soft shadow, as on usekago.net.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: light
            ? <BoxShadow>[
                BoxShadow(
                    color: const Color(0xFF1A2D5C).withValues(alpha: .08),
                    blurRadius: 20,
                    offset: const Offset(0, 4)),
              ]
            : null,
      ),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
            borderRadius: radius, side: BorderSide(color: p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (trailing != null) trailing!
      ]);
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

/// The KAGO logo (the eye from usekago.net) — the same picture as the app icon.
class KagoLogo extends StatelessWidget {
  const KagoLogo({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/branding/kago_icon.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'KAGO',
      );
}
