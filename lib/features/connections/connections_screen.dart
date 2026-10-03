import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';

class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The tabs stay mounted in an IndexedStack. Rendering nothing while this tab
    // is hidden stops the once-per-second poll and its rebuilds off-screen.
    if (ref.watch(rootTabIndexProvider) != 2) return const SizedBox.shrink();
    return _buildList(context, ref);
  }

  Widget _buildList(BuildContext context, WidgetRef ref) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          children: <Widget>[
            Row(children: <Widget>[
              const Expanded(child: SectionTitle('Соединения')),
              IconButton(
                  onPressed: () => ref.invalidate(connectionsSnapshotProvider),
                  icon: const Icon(Icons.refresh_rounded))
            ]),
            const SizedBox(height: 5),
            const Text(
                'Активные сетевые сессии ядра Mihomo. Список обновляется автоматически.',
                style: TextStyle(color: KaGoColors.muted, fontSize: 13)),
            const SizedBox(height: 18),
            ref.watch(connectionsSnapshotProvider).when(
                  loading: () => const LoadingPanel(),
                  error: (error, _) => ErrorPanel(
                      message: 'Контроллер недоступен: $error',
                      onRetry: () => ref.invalidate(connectionsSnapshotProvider)),
                  data: (snapshot) => snapshot.connections.isEmpty
                      ? const SurfaceCard(
                          child: Row(children: <Widget>[
                          Icon(Icons.check_circle_outline,
                              color: KaGoColors.accent),
                          SizedBox(width: 12),
                          Expanded(
                              child: Text('Активных соединений нет.',
                                  style: TextStyle(color: KaGoColors.muted)))
                        ]))
                      : Column(children: <Widget>[
                          Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(mihomoControllerProvider)
                                          .closeAllConnections();
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content:
                                                    Text('Ошибка: $error')));
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('Закрыть все'))),
                          ...snapshot.connections.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ConnectionTile(
                                  item: item,
                                  onClose: () async {
                                    try {
                                      await ref
                                          .read(mihomoControllerProvider)
                                          .closeConnection(item.id);
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content:
                                                    Text('Ошибка: $error')));
                                      }
                                    }
                                  }))),
                        ]),
                ),
          ]);
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
            const Icon(Icons.language_rounded, color: KaGoColors.accent),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Text(item.host,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${item.destination} · ${item.network} · ${item.rule}',
                      style: const TextStyle(
                          fontSize: 11, color: KaGoColors.muted)),
                  if (item.chain.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(item.chain,
                            style: const TextStyle(
                                fontSize: 11, color: KaGoColors.accentSoft))),
                  const SizedBox(height: 7),
                  Text(
                      '↓ ${formatBytes(item.download)}    ↑ ${formatBytes(item.upload)}',
                      style: const TextStyle(
                          fontSize: 11, color: KaGoColors.muted)),
                ])),
            IconButton(
                tooltip: 'Закрыть соединение',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18)),
          ]));
}
