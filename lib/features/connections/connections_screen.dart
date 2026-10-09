import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';
import '../../core/l10n/l10n.dart';

/// Live connections of the core: a page opened from Settings → Tools (as in
/// FlClashX), not a main tab. It polls only while open.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(vpnActiveProvider);
    // With the core off there is nothing to ask: show "no connections"
    // instead of a controller error, and do not poll.
    final snapshot = online
        ? ref.watch(connectionsSnapshotProvider)
        : const AsyncValue<ConnectionsSnapshot>.data(
            ConnectionsSnapshot(connections: <ActiveConnection>[]));
    final hasConnections =
        snapshot.valueOrNull?.connections.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Соединения')),
        actions: <Widget>[
          if (hasConnections)
            IconButton(
                tooltip: tr('Закрыть все'),
                onPressed: () => _close(
                    context,
                    () => ref
                        .read(mihomoControllerProvider)
                        .closeAllConnections()),
                icon: const Icon(Icons.clear_all_rounded)),
          IconButton(
              tooltip: tr('Обновить'),
              onPressed: () => ref.invalidate(connectionsSnapshotProvider),
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: <Widget>[
            Text(
                tr('Активные сетевые сессии ядра Mihomo. Список обновляется автоматически.'),
                style: TextStyle(color: context.kago.muted, fontSize: 13)),
            const SizedBox(height: 14),
            snapshot.when(
              loading: () => const LoadingPanel(),
              error: (error, _) => ErrorPanel(
                  message: tr('Контроллер недоступен: {error}',
                      <String, Object?>{'error': error}),
                  onRetry: () => ref.invalidate(connectionsSnapshotProvider)),
              data: (snapshot) => snapshot.connections.isEmpty
                  ? SurfaceCard(
                      child: Row(children: <Widget>[
                      Icon(Icons.check_circle_outline,
                          color: context.kago.accent),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              online
                                  ? tr('Активных соединений нет.')
                                  : tr(
                                      'Ядро выключено — активных соединений нет.'),
                              style: TextStyle(color: context.kago.muted)))
                    ]))
                  : Column(
                      children: snapshot.connections
                          .map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ConnectionTile(
                                  item: item,
                                  onClose: () => _close(
                                      context,
                                      () => ref
                                          .read(mihomoControllerProvider)
                                          .closeConnection(item.id)))))
                          .toList(growable: false)),
            ),
          ]),
    );
  }

  static Future<void> _close(
      BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        showShortMessage(context, tr('Не удалось закрыть соединение.'),
            details: '$error');
      }
    }
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.item, required this.onClose});
  final ActiveConnection item;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => SurfaceCard(
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
            Icon(Icons.language_rounded, color: context.kago.accent),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Text(item.host,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${item.destination} · ${item.network} · ${item.rule}',
                      style:
                          TextStyle(fontSize: 11, color: context.kago.muted)),
                  if (item.chain.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(item.chain,
                            style: TextStyle(
                                fontSize: 11, color: context.kago.accent))),
                  const SizedBox(height: 7),
                  Text(
                      '↓ ${formatBytes(item.download)}    ↑ ${formatBytes(item.upload)}',
                      style:
                          TextStyle(fontSize: 11, color: context.kago.muted)),
                ])),
            IconButton(
                tooltip: tr('Закрыть соединение'),
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18)),
          ]));
}
