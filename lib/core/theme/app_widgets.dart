import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'kago_theme.dart';

/// A short message at the bottom of the screen. Technical [details] (an
/// exception, a server answer) are not shown in it, only behind «Подробнее».
void showShortMessage(BuildContext context, String text, {String? details}) {
  final messenger = ScaffoldMessenger.of(context);
  final more = details?.trim() ?? '';
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    action: more.isEmpty || more == text
        ? null
        : SnackBarAction(
            label: tr('Подробнее'),
            onPressed: () => showDialog<void>(
              context: messenger.context,
              builder: (dialogContext) => AlertDialog(
                title: Text(text),
                content: SingleChildScrollView(child: SelectableText(more)),
                actions: <Widget>[
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(tr('Закрыть'))),
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
