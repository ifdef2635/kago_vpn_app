import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mihomo_models.dart';
import '../../core/network/app_providers.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';
import '../../core/l10n/l10n.dart';
import '../guest/guest_telegram.dart';
import 'proxy_mode.dart';

/// Servers tab, laid out like the FlClashX list view: every group is a card
/// with its current server, a latency test and an unfold button; an unfolded
/// group shows a grid of compact server cards (two columns on a phone). The
/// header has the FlClashX actions: routing mode, test all, fold all, search.
class ProxiesScreen extends ConsumerStatefulWidget {
  const ProxiesScreen({super.key});

  @override
  ConsumerState<ProxiesScreen> createState() => _ProxiesScreenState();
}

class _ProxiesScreenState extends ConsumerState<ProxiesScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(vpnActiveProvider);
    final groupsAsync = ref.watch(proxyGroupsProvider);
    final sort = ref.watch(proxySortProvider);
    final mode = ref.watch(effectiveProxyModeProvider);
    final guest = ref.watch(guestModeActiveProvider);
    final pending = ref.watch(proxyDelayTestingProvider);
    final query = _searching ? _search.text.trim().toLowerCase() : '';
    final groups = filterProxyGroups(
        visibleProxyGroups(groupsAsync.valueOrNull ?? const <ProxyGroup>[],
            mode: mode),
        query);
    final expandedSaved = ref.watch(expandedProxyGroupsProvider);
    final expanded = query.isNotEmpty
        ? <String>{for (final group in groups) group.name}
        : expandedSaved ?? <String>{if (groups.isNotEmpty) groups.first.name};
    final allExpanded =
        groups.isNotEmpty && groups.every((g) => expanded.contains(g.name));
    final testNames = <String>{
      for (final group in groups)
        for (final node in group.nodes)
          if (_testable(node)) node.name,
    }.toList(growable: false);

    const compact = VisualDensity.compact;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(proxyGroupsProvider);
        await ref
            .read(proxyGroupsProvider.future)
            .catchError((Object _) => const <ProxyGroup>[]);
      },
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(children: <Widget>[
                Expanded(child: SectionTitle(tr('Серверы'))),
                if (!guest)
                  PopupMenuButton<ProxyMode>(
                      tooltip: tr('Режим'),
                      icon: Icon(mode == ProxyMode.global
                          ? Icons.public_rounded
                          : Icons.rule_rounded),
                      initialValue: mode,
                      onSelected: (value) =>
                          ref.read(proxyModeProvider.notifier).set(value),
                      itemBuilder: (_) => <PopupMenuEntry<ProxyMode>>[
                            _modeItem(
                                ProxyMode.rule,
                                Icons.rule_rounded,
                                tr('По правилам'),
                                tr('Как задано в подписке: российские сайты напрямую, остальное через VPN')),
                            _modeItem(
                                ProxyMode.global,
                                Icons.public_rounded,
                                tr('Глобальный'),
                                tr('Весь трафик через сервер, выбранный в GLOBAL')),
                          ]),
                IconButton(
                    tooltip: tr('Проверить задержку всех серверов'),
                    visualDensity: compact,
                    onPressed: online && pending.isEmpty && testNames.isNotEmpty
                        ? () => _testDelays(ref, testNames, guest: guest)
                        : null,
                    icon: pending.isNotEmpty
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_ping_rounded)),
                IconButton(
                    tooltip:
                        allExpanded ? tr('Свернуть все') : tr('Развернуть все'),
                    visualDensity: compact,
                    onPressed: groups.isEmpty || query.isNotEmpty
                        ? null
                        : () => ref
                                .read(expandedProxyGroupsProvider.notifier)
                                .state =
                            allExpanded
                                ? <String>{}
                                : <String>{for (final g in groups) g.name},
                    icon: Icon(allExpanded
                        ? Icons.unfold_less_rounded
                        : Icons.unfold_more_rounded)),
                IconButton(
                    tooltip: tr('Поиск'),
                    visualDensity: compact,
                    isSelected: _searching,
                    onPressed: () => setState(() {
                          _searching = !_searching;
                          if (!_searching) _search.clear();
                        }),
                    icon: const Icon(Icons.search_rounded),
                    selectedIcon: const Icon(Icons.search_off_rounded)),
                PopupMenuButton<Object>(
                    tooltip: tr('Ещё'),
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      if (value is ProxySort) {
                        ref.read(proxySortProvider.notifier).state = value;
                      } else {
                        ref.invalidate(proxyGroupsProvider);
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<Object>>[
                          for (final (value, label) in <(ProxySort, String)>[
                            (ProxySort.config, tr('По порядку')),
                            (ProxySort.delay, tr('По задержке')),
                            (ProxySort.name, tr('По имени')),
                          ])
                            CheckedPopupMenuItem<Object>(
                                value: value,
                                checked: sort == value,
                                child: Text(label)),
                          const PopupMenuDivider(),
                          PopupMenuItem<Object>(
                              value: 'refresh',
                              child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.refresh_rounded),
                                  title: Text(tr('Обновить')))),
                        ]),
              ]),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: tr('Название сервера'))),
              ),
            if (!online)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                    tr('VPN выключен. Выбрать сервер и проверить задержку можно после подключения.'),
                    style: TextStyle(color: context.kago.muted, fontSize: 13)),
              )
            else if (mode == ProxyMode.global)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                    tr('Глобальный режим: весь трафик идёт через выбранный сервер, правила подписки не действуют.'),
                    style: TextStyle(color: context.kago.muted, fontSize: 13)),
              ),
            const SizedBox(height: 14),
            groupsAsync.when(
              loading: () => const LoadingPanel(),
              error: (error, _) => ErrorPanel(
                  message: tr('Не удалось загрузить список серверов.'),
                  onRetry: () => ref.invalidate(proxyGroupsProvider)),
              data: (items) {
                if (groups.isEmpty) {
                  return SurfaceCard(
                      child: Text(
                          query.isNotEmpty
                              ? tr('Ничего не найдено.')
                              : tr(
                                  'Серверов пока нет. Войдите в аккаунт KAGO с активной подпиской во вкладке «Кабинет» — серверы появятся здесь.'),
                          style: TextStyle(color: context.kago.muted)));
                }
                final info = _ProxyInfo(items);
                return Column(
                    children: groups
                        .map((group) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _GroupSection(
                                group: group,
                                info: info,
                                sort: sort,
                                online: online,
                                guest: guest,
                                expanded: expanded.contains(group.name),
                                onToggle: query.isNotEmpty
                                    ? null
                                    : () {
                                        final next = <String>{...expanded};
                                        if (!next.remove(group.name)) {
                                          next.add(group.name);
                                        }
                                        ref
                                            .read(expandedProxyGroupsProvider
                                                .notifier)
                                            .state = next;
                                      })))
                        .toList(growable: false));
              },
            ),
          ]),
    );
  }

  PopupMenuItem<ProxyMode> _modeItem(
          ProxyMode value, IconData icon, String title, String subtitle) =>
      PopupMenuItem<ProxyMode>(
          value: value,
          child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
              trailing: ref.read(effectiveProxyModeProvider) == value
                  ? const Icon(Icons.check_rounded)
                  : null));
}

/// The groups the servers tab lists. By rules: all but `GLOBAL` and the
/// groups the subscription marks `hidden`. Global mode: only `GLOBAL`, the one
/// group the core uses then (as FlClashX; by rules when there is none, as
/// without the core).
List<ProxyGroup> visibleProxyGroups(List<ProxyGroup> groups,
    {ProxyMode mode = ProxyMode.rule}) {
  if (mode == ProxyMode.global) {
    final global = groups.where((group) => group.name == 'GLOBAL').toList();
    if (global.isNotEmpty) return global;
  }
  return groups
      .where((group) => group.name != 'GLOBAL' && !group.hidden)
      .toList(growable: false);
}

/// [groups] with only the servers whose name contains [query] (any case);
/// groups without such servers are left out. An empty query keeps all.
List<ProxyGroup> filterProxyGroups(List<ProxyGroup> groups, String query) {
  final text = query.trim().toLowerCase();
  if (text.isEmpty) return groups;
  return <ProxyGroup>[
    for (final group in groups)
      if (group.nodes.any((node) => node.name.toLowerCase().contains(text)))
        ProxyGroup(
            name: group.name,
            type: group.type,
            selected: group.selected,
            description: group.description,
            hidden: group.hidden,
            icon: group.icon,
            testUrl: group.testUrl,
            nodes: group.nodes
                .where((node) => node.name.toLowerCase().contains(text))
                .toList(growable: false)),
  ];
}

/// What a node card shows about other entries: a group's current server and
/// the last latency of any server.
class _ProxyInfo {
  _ProxyInfo(List<ProxyGroup> groups) {
    for (final group in groups) {
      _now[group.name] = group.selected;
      for (final node in group.nodes) {
        if (node.delay != null) _delays[node.name] = node.delay!;
      }
    }
  }

  final _now = <String, String?>{};
  final _delays = <String, int>{};

  String? now(String group) => _now[group];

  /// Latency of [node]; for a nested group, of the server it uses now.
  int? delay(ProxyNode node, Map<String, int> tested) {
    var name = node.name;
    // A group inside a group (up to a few levels) shows its current server.
    for (var i = 0; i < 4 && _now[name] != null; i++) {
      name = _now[name]!;
    }
    return tested[name] ?? _delays[name];
  }
}

/// What a Mihomo group type does, in the interface language.
String proxyGroupKind(String type) => switch (type.toLowerCase()) {
      'selector' => tr('Ручной выбор'),
      'urltest' => tr('Самый быстрый'),
      'fallback' => tr('Резервный'),
      'loadbalance' => tr('Балансировка'),
      'relay' => tr('Цепочка'),
      _ => type,
    };

/// Header line of a group: the chosen server of a manual group; the kind and
/// current server of an automatic one.
String _groupDetail(String type, String? now) {
  if (now == null || now.isEmpty) return proxyGroupKind(type);
  if (type.toLowerCase() == 'selector') return now;
  return '${proxyGroupKind(type)} · $now';
}

bool _testable(ProxyNode node) =>
    !node.isGroup &&
    node.type.toLowerCase() != 'reject' &&
    node.type.toLowerCase() != 'direct';

class _GroupSection extends ConsumerWidget {
  const _GroupSection(
      {required this.group,
      required this.info,
      required this.sort,
      required this.online,
      required this.guest,
      required this.expanded,
      required this.onToggle});
  final ProxyGroup group;
  final _ProxyInfo info;
  final ProxySort sort;
  final bool online;

  /// Free Telegram access: its server answers only Telegram addresses.
  final bool guest;
  final bool expanded;

  /// Null while searching: every group with a match stays unfolded.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delays = ref.watch(proxyDelaysProvider);
    final pending = ref.watch(proxyDelayTestingProvider);
    final testing = group.nodes.any((node) => pending.contains(node.name));
    final selected = group.selected;
    final p = context.kago;
    final radius = BorderRadius.circular(KaGoRadius.lg);
    return DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: Theme.of(context).brightness == Brightness.light
                ? context.kagoCardShadow
                : null),
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
              borderRadius: radius, side: BorderSide(color: p.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: <Widget>[
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(children: <Widget>[
                  if (group.icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _GroupIcon(url: group.icon!),
                    ),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: KaGoWeight.heading,
                                  letterSpacing: -.2,
                                  color: p.text)),
                          const SizedBox(height: 3),
                          Text(_groupDetail(group.type, selected),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: p.muted)),
                        ]),
                  ),
                  if (group.nodes.any(_testable))
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: testing
                          ? const Padding(
                              padding: EdgeInsets.all(11),
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              tooltip: tr('Проверить задержку'),
                              padding: EdgeInsets.zero,
                              onPressed: online && pending.isEmpty
                                  ? () => _testDelays(
                                      ref,
                                      group.nodes
                                          .where(_testable)
                                          .map((node) => node.name)
                                          .toList(growable: false),
                                      guest: guest,
                                      url: group.testUrl)
                                  : null,
                              icon: const Icon(Icons.network_ping_rounded,
                                  size: 21)),
                    ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                      tooltip: expanded ? tr('Свернуть') : tr('Развернуть'),
                      style: IconButton.styleFrom(
                          backgroundColor: p.accentSoft,
                          foregroundColor: p.accent),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 40, height: 40),
                      onPressed: onToggle,
                      icon: AnimatedRotation(
                          turns: expanded ? .5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.expand_more_rounded))),
                ]),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: _grid(context, ref, delays, pending))
                  : const SizedBox(width: double.infinity),
            ),
          ]),
        ));
  }

  Widget _grid(BuildContext context, WidgetRef ref, Map<String, int> delays,
      Set<String> pending) {
    final nodes =
        _sorted(group.nodes, sort, (node) => info.delay(node, delays));
    if (nodes.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(8),
          child: Text(tr('У этой группы нет доступных узлов.'),
              style: TextStyle(color: context.kago.muted)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 8.0;
      final columns =
          math.min(math.max((constraints.maxWidth / 300).ceil(), 2), 4);
      final rows = <Widget>[];
      for (var start = 0; start < nodes.length; start += columns) {
        final cells = <Widget>[];
        for (var i = 0; i < columns; i++) {
          if (i > 0) cells.add(const SizedBox(width: gap));
          final index = start + i;
          if (index >= nodes.length) {
            cells.add(const Expanded(child: SizedBox()));
            continue;
          }
          final node = nodes[index];
          cells.add(Expanded(
              child: _NodeCard(
                  node: node,
                  detail: node.isGroup
                      ? _nestedDetail(node)
                      : node.type.toUpperCase(),
                  selected: node.name == group.selected,
                  delay: info.delay(node, delays),
                  testing: pending.contains(node.name),
                  onTest: online && _testable(node) && pending.isEmpty
                      ? () => _testDelays(ref, <String>[node.name],
                          guest: guest, url: group.testUrl)
                      : null,
                  // Without the core, and in automatic groups, there is
                  // nothing to choose: the card does not react.
                  onTap: online &&
                          group.isSelectable &&
                          node.name != group.selected
                      ? () => _selectNode(context, ref, group, node.name)
                      : null)));
        }
        if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
        rows.add(IntrinsicHeight(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells)));
      }
      return Column(children: rows);
    });
  }

  /// A nested group's card names the server it uses now (its kind when it
  /// has none, as a load balancer).
  String _nestedDetail(ProxyNode node) {
    final now = info.now(node.name);
    return now == null || now.isEmpty ? proxyGroupKind(node.type) : now;
  }
}

List<ProxyNode> _sorted(
    List<ProxyNode> nodes, ProxySort sort, int? Function(ProxyNode) delay) {
  final list = List<ProxyNode>.of(nodes);
  int? delayOf(ProxyNode node) {
    final value = delay(node);
    return value != null && value > 0 ? value : null;
  }

  switch (sort) {
    case ProxySort.config:
      return list;
    case ProxySort.name:
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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

Future<void> _selectNode(
    BuildContext context, WidgetRef ref, ProxyGroup group, String node) async {
  try {
    await ref.read(mihomoControllerProvider).selectProxy(group.name, node);
    ref.invalidate(proxyGroupsProvider);
    ref.invalidate(ipInfoProvider);
  } catch (error) {
    if (context.mounted) {
      showCriticalError(context, tr('Не удалось выбрать сервер.'),
          details: '$error');
    }
  }
}

/// Tests [names] with eight parallel workers. Each result is shown as soon as
/// it arrives, and one slow node (up to the 5 s timeout) does not hold back
/// the others.
Future<void> _testDelays(WidgetRef ref, List<String> names,
    {required bool guest, String? url}) async {
  if (names.isEmpty) return;
  final controller = ref.read(mihomoControllerProvider);
  final pending = ref.read(proxyDelayTestingProvider.notifier);
  pending.state = names.toSet();
  try {
    // Workers take from the end, so reverse to keep the config order.
    final queue = names.reversed.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final name = queue.removeLast();
        // The guest server lets only Telegram through; a group's servers are
        // tested against the group's own `url` (as FlClashX).
        final target = guest ? GuestTelegram.checkUrl : url;
        final delay = target == null
            ? await controller.testDelay(name)
            : await controller.testDelay(name, url: target);
        ref.read(proxyDelaysProvider.notifier).state = <String, int>{
          ...ref.read(proxyDelaysProvider),
          name: delay ?? -1,
        };
        pending.state = <String>{...pending.state}..remove(name);
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < 8 && i < names.length; i++) worker(),
    ]);
  } catch (_) {
    // A failed test shows as «Таймаут» on its card.
  } finally {
    pending.state = const <String>{};
  }
}

/// A compact server card: name (two lines), protocol or the nested group's
/// current server, latency. The chosen server is tinted and has a check mark.
class _NodeCard extends StatelessWidget {
  const _NodeCard(
      {required this.node,
      required this.detail,
      required this.selected,
      required this.delay,
      required this.testing,
      required this.onTest,
      required this.onTap});
  final ProxyNode node;
  final String detail;
  final bool selected;
  final int? delay;
  final bool testing;
  final VoidCallback? onTest;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
          color: selected ? p.accentSoft : p.surfaceRaised,
          borderRadius: BorderRadius.circular(KaGoRadius.md),
          border: Border.all(
              color: selected ? p.accentTint : p.borderLight, width: 2)),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KaGoRadius.md),
          child: Stack(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 9),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.only(right: selected ? 20 : 0),
                      child: Text(node.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.25,
                              fontWeight: KaGoWeight.bold,
                              color: selected ? p.accent : p.text)),
                    ),
                    const SizedBox(height: 8),
                    Row(children: <Widget>[
                      Expanded(
                          child: Text(detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: .3,
                                  color: p.muted))),
                      const SizedBox(width: 6),
                      _DelayLabel(
                          delay: delay, testing: testing, onTest: onTest),
                    ]),
                  ]),
            ),
            if (selected)
              Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                          color: p.accent, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                          size: 12, color: Colors.white))),
          ]),
        ),
      ),
    );
  }
}

/// Latency of a card; tapping it (or the bolt of an untested server) tests
/// that server again.
class _DelayLabel extends StatelessWidget {
  const _DelayLabel(
      {required this.delay, required this.testing, required this.onTest});
  final int? delay;
  final bool testing;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    if (testing) {
      return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.6));
    }
    final value = delay;
    final Widget label;
    if (value == null) {
      if (onTest == null) {
        return Text('—', style: TextStyle(fontSize: 12, color: p.muted));
      }
      label = Icon(Icons.bolt_rounded, size: 17, color: p.muted);
    } else if (value <= 0) {
      label =
          Text(tr('Таймаут'), style: TextStyle(fontSize: 12, color: p.danger));
    } else {
      final color = value < 600
          ? p.success
          : value < 1200
              ? p.warning
              : p.danger;
      label = Text(tr('{value} мс', <String, Object?>{'value': value}),
          style: TextStyle(
              fontSize: 12, fontWeight: KaGoWeight.bold, color: color));
    }
    if (onTest == null) return label;
    return Tooltip(
      message: tr('Проверить задержку'),
      child: InkWell(
          onTap: onTest,
          borderRadius: BorderRadius.circular(KaGoRadius.sm),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: label)),
    );
  }
}

/// The group's `icon` from the config (FlClashX shows it the same way).
/// Nothing while it loads or when it does not load.
class _GroupIcon extends StatelessWidget {
  const _GroupIcon({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
            color: context.kago.accentSoft,
            borderRadius: BorderRadius.circular(KaGoRadius.button)),
        child: Image.network(url,
            fit: BoxFit.contain,
            // Icons are small; do not keep a full-size image in memory.
            cacheWidth: (42 * MediaQuery.devicePixelRatioOf(context)).round(),
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                AnimatedOpacity(
                    opacity: wasSynchronouslyLoaded || frame != null ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: child),
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink()),
      );
}
