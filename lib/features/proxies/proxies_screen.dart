import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';

/// Servers tab, laid out like FlClashX: group tabs on top, a grid of node
/// cards (name, protocol, latency) below, latency test and sorting in the header.
class ProxiesScreen extends ConsumerWidget {
  const ProxiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(vpnActiveProvider);
    final groupsAsync = ref.watch(proxyGroupsProvider);
    final sort = ref.watch(proxySortProvider);
    final pending = ref.watch(proxyDelayTestingProvider);
    final delays = ref.watch(proxyDelaysProvider);
    final selectedName = ref.watch(selectedProxyGroupProvider);
    final groups = groupsAsync.asData?.value ?? const <ProxyGroup>[];
    final active = _activeGroup(groups, selectedName);

    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: <Widget>[
          Row(children: <Widget>[
            const Expanded(child: SectionTitle('Серверы и группы')),
            IconButton(
                tooltip: 'Проверить задержку',
                onPressed: active == null || pending.isNotEmpty || !online
                    ? null
                    : () => _testGroupDelays(context, ref, active),
                icon: pending.isNotEmpty
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.speed_rounded)),
            PopupMenuButton<ProxySort>(
                tooltip: 'Сортировка',
                icon: const Icon(Icons.sort_rounded),
                initialValue: sort,
                onSelected: (value) =>
                    ref.read(proxySortProvider.notifier).state = value,
                itemBuilder: (_) => const <PopupMenuEntry<ProxySort>>[
                      PopupMenuItem(
                          value: ProxySort.config, child: Text('По порядку')),
                      PopupMenuItem(
                          value: ProxySort.delay, child: Text('По задержке')),
                      PopupMenuItem(
                          value: ProxySort.name, child: Text('По имени')),
                    ]),
            IconButton(
                tooltip: 'Обновить',
                onPressed: () => ref.invalidate(proxyGroupsProvider),
                icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 6),
          Text(
              online
                  ? 'Выберите активный узел. Данные берутся из ядра Mihomo.'
                  : 'Ядро выключено: показаны серверы из профиля. Выбор узла и проверка задержки доступны после подключения.',
              style: const TextStyle(color: KaGoColors.muted, fontSize: 13)),
          const SizedBox(height: 16),
          groupsAsync.when(
            loading: () => const LoadingPanel(),
            error: (error, _) => ErrorPanel(
                message: 'Не удалось получить группы прокси: $error',
                onRetry: () => ref.invalidate(proxyGroupsProvider)),
            data: (items) {
              final group = _activeGroup(items, selectedName);
              if (group == null) {
                return const SurfaceCard(
                    child: Text(
                        'Прокси-групп нет. Добавьте профиль и загрузите конфигурацию ядра.',
                        style: TextStyle(color: KaGoColors.muted)));
              }
              final nodes = _sorted(group.nodes, sort, delays);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: items
                                .map((item) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _GroupTab(
                                        label: item.name,
                                        selected: item.name == group.name,
                                        onTap: () => ref
                                            .read(selectedProxyGroupProvider
                                                .notifier)
                                            .state = item.name)))
                                .toList(growable: false))),
                    const SizedBox(height: 12),
                    Text(
                        !online
                            ? '${group.type} · ${group.nodes.length} шт.'
                            : group.isSelectable
                                ? '${group.type} · ${group.nodes.length} шт.'
                                : '${group.type} · узел выбирается автоматически',
                        style: const TextStyle(
                            color: KaGoColors.muted, fontSize: 12)),
                    if (group.description != null &&
                        group.description!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(group.description!,
                          style: const TextStyle(
                              color: KaGoColors.muted, fontSize: 12)),
                    ],
                    const SizedBox(height: 14),
                    if (nodes.isEmpty)
                      const Text('У этой группы нет доступных узлов.',
                          style: TextStyle(color: KaGoColors.muted))
                    else
                      LayoutBuilder(builder: (context, constraints) {
                        const gap = 10.0;
                        final columns = constraints.maxWidth >= 900
                            ? 3
                            : constraints.maxWidth >= 520
                                ? 2
                                : 1;
                        final width =
                            (constraints.maxWidth - gap * (columns - 1)) /
                                columns;
                        return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: nodes
                                .map((node) => SizedBox(
                                    width: width,
                                    child: _NodeCard(
                                        node: node,
                                        selected: node.name == group.selected,
                                        enabled: group.isSelectable && online,
                                        delay: delays[node.name] ?? node.delay,
                                        testing: pending.contains(node.name),
                                        onTap: () => _selectNode(
                                            context, ref, group, node.name))))
                                .toList(growable: false));
                      }),
                  ]);
            },
          ),
        ]);
  }
}

ProxyGroup? _activeGroup(List<ProxyGroup> groups, String? name) {
  if (groups.isEmpty) return null;
  for (final group in groups) {
    if (group.name == name) return group;
  }
  return groups.first;
}

List<ProxyNode> _sorted(
    List<ProxyNode> nodes, ProxySort sort, Map<String, int> delays) {
  final list = List<ProxyNode>.of(nodes);
  int? delayOf(ProxyNode node) {
    final value = delays[node.name] ?? node.delay;
    return value != null && value > 0 ? value : null;
  }

  switch (sort) {
    case ProxySort.config:
      return list;
    case ProxySort.name:
      list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    case ProxySort.delay:
      list.sort((a, b) {
        final left = delayOf(a);
        final right = delayOf(b);
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });
      return list;
  }
}

Future<void> _selectNode(BuildContext context, WidgetRef ref, ProxyGroup group,
    String node) async {
  try {
    await ref.read(mihomoControllerProvider).selectProxy(group.name, node);
    ref.invalidate(proxyGroupsProvider);
    ref.invalidate(ipInfoProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось выбрать узел: $error')));
    }
  }
}

/// Tests every real node of [group] (not nested groups or REJECT), six at a
/// time, and publishes results after each batch so cards fill in progressively.
Future<void> _testGroupDelays(
    BuildContext context, WidgetRef ref, ProxyGroup group) async {
  final controller = ref.read(mihomoControllerProvider);
  final names = group.nodes
      .where((node) => !node.isGroup && node.type.toLowerCase() != 'reject')
      .map((node) => node.name)
      .toList(growable: false);
  if (names.isEmpty) return;
  final pending = ref.read(proxyDelayTestingProvider.notifier);
  pending.state = names.toSet();
  try {
    const batchSize = 6;
    for (var start = 0; start < names.length; start += batchSize) {
      final batch = names.skip(start).take(batchSize).toList(growable: false);
      final results = await Future.wait(batch.map((name) async =>
          MapEntry<String, int?>(name, await controller.testDelay(name))));
      final next = Map<String, int>.of(ref.read(proxyDelaysProvider));
      for (final result in results) {
        next[result.key] = result.value ?? -1;
      }
      ref.read(proxyDelaysProvider.notifier).state = next;
      pending.state = pending.state.difference(batch.toSet());
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось проверить задержку: $error')));
    }
  } finally {
    pending.state = const <String>{};
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
          color: selected
              ? KaGoColors.accent.withValues(alpha: .16)
              : KaGoColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? KaGoColors.accent.withValues(alpha: .55)
                  : KaGoColors.border)),
      child: Material(
          type: MaterialType.transparency,
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? KaGoColors.accentSoft
                              : KaGoColors.muted),
                      child: Text(label))))));
}

class _NodeCard extends StatelessWidget {
  const _NodeCard(
      {required this.node,
      required this.selected,
      required this.enabled,
      required this.delay,
      required this.testing,
      required this.onTap});
  final ProxyNode node;
  final bool selected;
  final bool enabled;
  final int? delay;
  final bool testing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 78),
      decoration: BoxDecoration(
          color: selected
              ? KaGoColors.accent.withValues(alpha: .12)
              : KaGoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected
                  ? KaGoColors.accent.withValues(alpha: .6)
                  : KaGoColors.border)),
      child: Material(
          type: MaterialType.transparency,
          child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(node.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? KaGoColors.accentSoft
                                : KaGoColors.text)),
                    const SizedBox(height: 8),
                    Row(children: <Widget>[
                      Expanded(
                          child: Text(node.type.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  letterSpacing: .4,
                                  color: KaGoColors.muted))),
                      _DelayLabel(delay: delay, testing: testing),
                    ]),
                  ])))));
}

class _DelayLabel extends StatelessWidget {
  const _DelayLabel({required this.delay, required this.testing});
  final int? delay;
  final bool testing;

  @override
  Widget build(BuildContext context) {
    if (testing) {
      return const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 1.6));
    }
    final value = delay;
    if (value == null) {
      return const Text('—',
          style: TextStyle(fontSize: 12, color: KaGoColors.muted));
    }
    if (value <= 0) {
      return const Text('Таймаут',
          style: TextStyle(fontSize: 12, color: KaGoColors.danger));
    }
    final color = value < 600
        ? KaGoColors.accent
        : value < 1200
            ? KaGoColors.warning
            : KaGoColors.danger;
    return Text('$value мс',
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: color));
  }
}
